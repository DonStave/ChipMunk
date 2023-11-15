// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;
pragma abicoder v2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {DistributionTypes} from "./DistributionTypes.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
/**
 * @title DistributionManager
 * @notice Accounting contract to manage multiple staking distributions
 * @author CHIPMUNK
 **/
contract DistributionManager is Initializable {
    using SafeMath for uint256;

    struct AssetData {
        uint128 emissionPerSecond;
        uint128 lastUpdateTimestamp;
        uint256 index;
        mapping(address => uint256) users;
    }

    uint256 public DISTRIBUTION_END;

    uint8 public constant PRECISION = 18;

    address public admin;

    IAddressesProvider internal _addressProvider;

    mapping(address => AssetData) public assets;

    event AssetConfigUpdated(
        address indexed _asset,
        uint256 _emissionPerSecond
    );
    event AssetIndexUpdated(address indexed _asset, uint256 _index);
    event DistributionEndUpdated(uint256 newDistributionEnd);

    event UserIndexUpdated(
        address indexed user,
        address indexed asset,
        uint256 index
    );

    function __DistributionManager_init(uint256 _distributionDuration,address addressProvider)
    internal
    initializer
    {
        DISTRIBUTION_END = block.timestamp.add(_distributionDuration);
        admin = msg.sender;
        _addressProvider = IAddressesProvider(addressProvider);
    }

    function setDistributionEnd(uint256 _distributionEnd) external onlyAdmin {
        DISTRIBUTION_END = _distributionEnd;
        emit DistributionEndUpdated(_distributionEnd);
    }

    function _configureAssets(
        DistributionTypes.AssetConfigInput[] memory _assetsConfigInput
    ) internal onlyAdmin {
        for (uint256 i = 0; i < _assetsConfigInput.length; i++) {
            AssetData storage assetConfig = assets[
            _assetsConfigInput[i].underlyingAsset
            ];

            _updateAssetStateInternal(
                _assetsConfigInput[i].underlyingAsset,
                assetConfig,
                _assetsConfigInput[i].totalStaked
            );

            assetConfig.emissionPerSecond = _assetsConfigInput[i]
            .emissionPerSecond;

            emit AssetConfigUpdated(
                _assetsConfigInput[i].underlyingAsset,
                _assetsConfigInput[i].emissionPerSecond
            );
        }
    }

    /**
     * @dev Updates the state of one distribution, mainly rewards index and timestamp
     * @param _underlyingAsset The address used as key in the distribution, for example sCHIPMUNK or the aTokens addresses on Bend
     * @param _assetConfig Storage pointer to the distribution's config
     * @param _totalStaked Current total of staked assets for this distribution
     * @return The new distribution index
     **/
    function _updateAssetStateInternal(
        address _underlyingAsset,
        AssetData storage _assetConfig,
        uint256 _totalStaked
    ) internal returns (uint256) {
        uint256 oldIndex = _assetConfig.index;
        uint128 lastUpdateTimestamp = _assetConfig.lastUpdateTimestamp;

        if (block.timestamp == lastUpdateTimestamp) {
            return oldIndex;
        }
        uint256 newIndex = _getAssetIndex(
            oldIndex,
            _assetConfig.emissionPerSecond,
            lastUpdateTimestamp,
            _totalStaked
        );

        if (newIndex != oldIndex) {
            _assetConfig.index = newIndex;
            emit AssetIndexUpdated(_underlyingAsset, newIndex);
        }

        _assetConfig.lastUpdateTimestamp = uint128(block.timestamp);

        return newIndex;
    }

    /**
     * @dev Updates the state of an user in a distribution
     * @param _user The user's address
     * @param _asset The address of the reference asset of the distribution
     * @param _stakedByUser Amount of tokens staked by the user in the distribution at the moment
     * @param _totalStaked Total tokens staked in the distribution
     * @return The accrued rewards for the user until the moment
     **/
    function _updateUserAssetInternal(
        address _user,
        address _asset,
        uint256 _stakedByUser,
        uint256 _totalStaked
    ) internal returns (uint256) {
        AssetData storage assetData = assets[_asset];
        uint256 userIndex = assetData.users[_user];
        uint256 accruedRewards = 0;

        uint256 newIndex = _updateAssetStateInternal(
            _asset,
            assetData,
            _totalStaked
        );
        if (userIndex != newIndex) {
            if (_stakedByUser != 0) {
                accruedRewards = _getRewards(
                    _stakedByUser,
                    newIndex,
                    userIndex
                );
            }

            assetData.users[_user] = newIndex;
            emit UserIndexUpdated(_user, _asset, newIndex);
        }
        return accruedRewards;
    }

    /**
     * @dev Used by "frontend" stake contracts to update the data of an user when claiming rewards from there
     * @param _user The address of the user
     * @param _stakes List of structs of the user data related with his stake
     * @return The accrued rewards for the user until the moment
     **/
    function _claimRewards(
        address _user,
        DistributionTypes.UserStakeInput[] memory _stakes
    ) internal returns (uint256) {
        uint256 accruedRewards = 0;

        for (uint256 i = 0; i < _stakes.length; i++) {
            accruedRewards = accruedRewards.add(
                _updateUserAssetInternal(
                    _user,
                    _stakes[i].underlyingAsset,
                    _stakes[i].stakedByUser,
                    _stakes[i].totalStaked
                )
            );
        }

        return accruedRewards;
    }

    /**
     * @dev Return the accrued rewards for an user over a list of distribution
     * @param _user The address of the user
     * @param _stakes List of structs of the user data related with his stake
     * @return The accrued rewards for the user until the moment
     **/
    function _getUnclaimedRewards(
        address _user,
        DistributionTypes.UserStakeInput[] memory _stakes
    ) internal view returns (uint256) {
        uint256 accruedRewards = 0;

        for (uint256 i = 0; i < _stakes.length; i++) {
            AssetData storage assetConfig = assets[_stakes[i].underlyingAsset];
            uint256 assetIndex = _getAssetIndex(
                assetConfig.index,
                assetConfig.emissionPerSecond,
                assetConfig.lastUpdateTimestamp,
                _stakes[i].totalStaked
            );

            accruedRewards = accruedRewards.add(
                _getRewards(
                    _stakes[i].stakedByUser,
                    assetIndex,
                    assetConfig.users[_user]
                )
            );
        }
        return accruedRewards;
    }

    /**
     * @dev Internal function for the calculation of user's rewards on a distribution
     * @param _principalUserBalance Amount staked by the user on a distribution
     * @param _reserveIndex Current index of the distribution
     * @param _userIndex Index stored for the user, representation his staking moment
     * @return The rewards
     **/
    function _getRewards(
        uint256 _principalUserBalance,
        uint256 _reserveIndex,
        uint256 _userIndex
    ) internal pure returns (uint256) {
        return
        _principalUserBalance.mul(_reserveIndex.sub(_userIndex)).div(
            10 ** uint256(PRECISION)
        );
    }

    /**
     * @dev Calculates the next value of an specific distribution index, with validations
     * @param _currentIndex Current index of the distribution
     * @param _emissionPerSecond Representing the total rewards distributed per second per asset unit, on the distribution
     * @param _lastUpdateTimestamp Last moment this distribution was updated
     * @param _totalBalance of tokens considered for the distribution
     * @return The new index.
     **/
    function _getAssetIndex(
        uint256 _currentIndex,
        uint256 _emissionPerSecond,
        uint128 _lastUpdateTimestamp,
        uint256 _totalBalance
    ) internal view returns (uint256) {
        if (
            _emissionPerSecond == 0 ||
            _totalBalance == 0 ||
            _lastUpdateTimestamp == block.timestamp ||
            _lastUpdateTimestamp >= DISTRIBUTION_END
        ) {
            return _currentIndex;
        }

        uint256 currentTimestamp = block.timestamp > DISTRIBUTION_END
        ? DISTRIBUTION_END
        : block.timestamp;
        uint256 timeDelta = currentTimestamp.sub(_lastUpdateTimestamp);
        return
        _emissionPerSecond
        .mul(timeDelta)
        .mul(10 ** uint256(PRECISION))
        .div(_totalBalance)
        .add(_currentIndex);
    }

    /**
     * @dev Returns the data of an user on a distribution
     * @param _user Address of the user
     * @param _asset The address of the reference asset of the distribution
     * @return The new index
     **/
    function getUserAssetData(address _user, address _asset)
    public
    view
    returns (uint256)
    {
        return assets[_asset].users[_user];
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "ProtocolIncentivesController: !admin");
        _;
    }

    /**
 * @dev Only Manage can call functions marked by this modifier
     **/
    modifier onlyManager() {
        require(msg.sender == _getManage(), Errors.CT_CALLER_MUST_BE_MANAGE);
        _;
    }

    function _getManage() internal view returns (address) {
        return _addressProvider.getManage();
    }
}
