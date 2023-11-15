// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;
pragma abicoder v2;

import {DistributionTypes} from "./DistributionTypes.sol";
import {DistributionManager} from "./DistributionManager.sol";
import {IScaledBalanceToken} from "./interfaces/IScaledBalanceToken.sol";
import {IIncentivesController} from "./interfaces/IIncentivesController.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {IESM} from "./interfaces/IESM.sol";
import {IConfigurator} from "./interfaces/IConfigurator.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract ProtocolIncentivesController is
IIncentivesController,
DistributionManager
{
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public REWARD_TOKEN;
    address public REWARDS_VAULT;

    mapping(address => mapping(address => uint256)) internal usersUnclaimedRewards;
    mapping(address => bool) public authorizedAssets;

    function initialize(
        address _rewardToken,
        address _rewardsVault,
        uint128 _distributionDuration,
        address addressProvider
    ) external initializer {
        __DistributionManager_init(_distributionDuration,addressProvider);
        REWARD_TOKEN = IERC20Upgradeable(_rewardToken);
        REWARDS_VAULT = _rewardsVault;
    }

    /**
     * @dev Configure assets for a certain rewards emission
     * @param _assets The assets to incentivize
     * @param _emissionsPerSecond The emission for each asset
     */
    function configureAssets(IScaledBalanceToken[] calldata _assets, uint256[] calldata _emissionsPerSecond) external override onlyAdmin {
        require(
            _assets.length == _emissionsPerSecond.length,
            "INVALID_CONFIGURATION"
        );

        DistributionTypes.AssetConfigInput[]
        memory assetsConfig = new DistributionTypes.AssetConfigInput[](
            _assets.length
        );

        for (uint256 i = 0; i < _assets.length; i++) {
            authorizedAssets[address(_assets[i])] = true;
            assetsConfig[i].underlyingAsset = address(_assets[i]);
            assetsConfig[i].emissionPerSecond = uint128(_emissionsPerSecond[i]);

            require(
                assetsConfig[i].emissionPerSecond == _emissionsPerSecond[i],
                "INVALID_CONFIGURATION"
            );

            assetsConfig[i].totalStaked = _assets[i].scaledTotalSupply();
        }
        _configureAssets(assetsConfig);
    }

    /**
     * @dev Called by the corresponding asset on any update that affects the rewards distribution
     * @param _asset The address of the asset
     * @param _user The address of the user
     * @param _totalSupply The total supply of the asset in the lending pool
     * @param _userBalance The balance of the user of the asset in the lending pool
     **/
    function handleAction(
        address _asset,
        address _user,
        uint256 _totalSupply,
        uint256 _userBalance
    ) external override {
        require(authorizedAssets[msg.sender], "Sender Unauthorized");
        uint256 accruedRewards = _updateUserAssetInternal(
            _user,
            msg.sender,
            _userBalance,
            _totalSupply
        );
        if (accruedRewards != 0) {
            usersUnclaimedRewards[_asset][_user] = usersUnclaimedRewards[_asset][_user].add(
                accruedRewards
            );
            emit RewardsAccrued(_user, accruedRewards);
        }
    }

    /**
     * @dev Returns the total of rewards of an user, already accrued + not yet accrued
     * @param _user The address of the user
     * @return The rewards
     **/
    function getRewardsBalance(address[] calldata _assets, address _user)
    external
    view
    override
    returns (uint256)
    {
        uint256 unclaimedRewards;

        DistributionTypes.UserStakeInput[]
        memory userState = new DistributionTypes.UserStakeInput[](
            _assets.length
        );
        for (uint256 i = 0; i < _assets.length; i++) {
            userState[i].underlyingAsset = _assets[i];
            (
            userState[i].stakedByUser,
            userState[i].totalStaked
            ) = IScaledBalanceToken(_assets[i]).getScaledUserBalanceAndSupply(
                _user
            );
            unclaimedRewards = usersUnclaimedRewards[_assets[i]][_user];
        }
        unclaimedRewards = unclaimedRewards.add(
            _getUnclaimedRewards(_user, userState)
        );
        return unclaimedRewards;
    }

    /**

     * @dev returns the unclaimed rewards of the user
     * @param _asset the address of the _asset
     * @param _user the address of the user
     * @return the unclaimed user rewards
     */
    function getUserUnclaimedRewards(address _asset, address _user)
    external
    view
    override
    returns (uint256)
    {
        return usersUnclaimedRewards[_asset][_user];
    }

    /**
     * @dev Claims reward for an user, on all the assets of the lending pool, accumulating the pending rewards
     * @return Rewards claimed
     **/
    function claimRewards(address[] calldata _assets)
    external
    override
    returns (uint256)
    {
        IESM esm = IESM(_addressProvider.getESM());
        require(esm.isSwitchPaused(5), Errors.CLAIM_REWARD);
        address user = msg.sender;
        uint256 unclaimedRewards;

        DistributionTypes.UserStakeInput[]
        memory userState = new DistributionTypes.UserStakeInput[](
            _assets.length
        );
        for (uint256 i = 0; i < _assets.length; i++) {
            userState[i].underlyingAsset = _assets[i];
            (
            userState[i].stakedByUser,
            userState[i].totalStaked
            ) = IScaledBalanceToken(_assets[i]).getScaledUserBalanceAndSupply(
                user
            );
            unclaimedRewards = usersUnclaimedRewards[_assets[i]][user];
            usersUnclaimedRewards[_assets[i]][user] = 0;
        }

        uint256 accruedRewards = _claimRewards(user, userState);
        if (accruedRewards != 0) {
            unclaimedRewards = unclaimedRewards.add(accruedRewards);
            emit RewardsAccrued(user, accruedRewards);
        }

        if (unclaimedRewards == 0) {
            return 0;
        }

        // Safe due to the previous line
        IERC20Upgradeable(REWARD_TOKEN).safeTransferFrom(
            REWARDS_VAULT,
            msg.sender,
            unclaimedRewards
        );

        emit RewardsClaimed(msg.sender, unclaimedRewards);

        return unclaimedRewards;
    }

    function withdrawReward(uint256 amount) external override onlyManager {
        IConfigurator configurator = IConfigurator(
            _addressProvider.getConfigurator()
        );
        IERC20Upgradeable(REWARD_TOKEN).safeTransferFrom(
            REWARDS_VAULT,
            configurator.vaultAddress(),
            amount
        );

        emit WithdrawRewardToTreasury(amount);
    }

    function setAdmin(address _admin) external override onlyManager {
        admin = _admin;
    }

    function updateRewardVault(address _vault) external override onlyManager {
        require(_vault != address(0), "Invalid address");
        REWARDS_VAULT = _vault;
        emit UpdateRewardVault(_vault);
    }


}
