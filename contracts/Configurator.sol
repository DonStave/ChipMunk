// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IConfigurator} from "./interfaces/IConfigurator.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


contract Configurator is IConfigurator, Initializable {
    uint256 internal ONE;
    /// @notice Minimum loan amount 100ETH
    uint256 public override minLend;
    /// @notice Buffer time 12H
    uint256 public override bufferTime;
    /// @notice Countdown 10 minutes
    uint256 public override countdownTime;
    /// @notice liquidate Reward Rate 6%
    uint256 public override bidRewardRate;
    /// @notice minBidDelta Rate 101%
    uint256 public override minBidDelta;
    /// @notice vault address 94%
    address public override vaultAddress;

    IAddressesProvider internal _addressProvider;

    function initialize(address addressProvider, address _vault)
    public
    initializer
    {
        _addressProvider = IAddressesProvider(addressProvider);
        vaultAddress = _vault;
        ONE = 1e18;
        minLend = 1 * ONE;
        bufferTime = 43200;
        countdownTime = 600;
        bidRewardRate = 9400;
        minBidDelta = 10100;
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

    /**
     * @notice Reset minLend
     * @param _minLend New number of minLend
     */
    function setMinLendEvent(uint256 _minLend) external override onlyManager {
        require(
            _minLend >= 0 && _minLend <= 1000 * ONE,
            "The minLend should be between 0 and 1000ETH"
        );
        minLend = _minLend;
        emit MinLendEvent(minLend);
    }

    /**
     * @notice Reset bufferTime
     * @param _bufferTime New number of bufferTime
     */
    function setBufferTimeEvent(uint256 _bufferTime)
    external
    override
    onlyManager
    {
        require(
            _bufferTime >= 0 && _bufferTime <= ONE,
            "The bufferTime should be between 0 "
        );
        bufferTime = _bufferTime;
        emit BufferTimeEvent(bufferTime);
    }

    /**
     * @notice Reset countdownTime
     * @param _countdownTime New number of countdownTime
     */
    function setCountdownTimeEvent(uint256 _countdownTime)
    external
    override
    onlyManager
    {
        require(
            _countdownTime >= 0 && _countdownTime <= ONE,
            "The countdownTime should be between 0 "
        );
        countdownTime = _countdownTime;
        emit CountdownTimeEvent(countdownTime);
    }

    /**
     * @notice Reset bidRewardRate
     * @param _bidRewardRate New number of bidRewardRate
     */
    function setBidRewardRateEvent(uint256 _bidRewardRate)
    external
    override
    onlyManager
    {
        require(
            _bidRewardRate >= 0 && _bidRewardRate <= ONE,
            "The liquidateRewardRate should be between 0 "
        );
        bidRewardRate = _bidRewardRate;
        emit BidRewardRateEvent(_bidRewardRate);
    }

    /**
     * @notice Reset minBidDelta
     * @param _minBidDelta New number of minBidDelta
     */
    function setMinBidDeltaEvent(uint256 _minBidDelta)
    external
    override
    onlyManager
    {
        require(
            _minBidDelta >= 10000 && _minBidDelta <= ONE,
            "The _minBidDelta should be between 0 "
        );
        minBidDelta = _minBidDelta;
        emit MinBidDeltaEvent(_minBidDelta);
    }

    /**
     * @notice update vault address
     * @param vault address of vault address
     */
    function updateVaultAddress(address vault) external override onlyManager {
        require(vault != address(0), "invalid address");
        vaultAddress = vault;
        emit UpdateVaultAddress(vault);
    }
}
