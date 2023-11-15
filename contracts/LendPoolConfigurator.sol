// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {ILoanPool} from "./interfaces/ILoanPool.sol";
import {IChipToken} from "./interfaces/IChipToken.sol";
import {IDebtToken} from "./interfaces/IDebtToken.sol";
import {ICNFT} from "./interfaces/ICNFT.sol";
import {ICNFTRegistry} from "./interfaces/ICNFTRegistry.sol";
import {IIncentivesController} from "./interfaces/IIncentivesController.sol";
import {ILendPoolConfigurator} from "./interfaces/ILendPoolConfigurator.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {ChipUpgradeableProxy} from "./libraries/proxy/ChipUpgradeableProxy.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {NftConfiguration} from "./libraries/configuration/NftConfiguration.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {Math} from "./libraries/math/Math.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title LendPoolConfigurator contract
 * @author CHIPMUNK
 * @dev Implements the configuration methods for the CHIPMUNK protocol
 **/

contract LendPoolConfigurator is Initializable, ILendPoolConfigurator {
    using Math for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using NftConfiguration for DataTypes.NftConfigurationMap;

    IAddressesProvider internal _addressesProvider;

    modifier onlyPoolAdmin() {
        require(
            _addressesProvider.getPoolAdmin() == msg.sender,
            Errors.CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(
            _addressesProvider.getEmergencyAdmin() == msg.sender,
            Errors.LPC_CALLER_NOT_EMERGENCY_ADMIN
        );
        _;
    }

    function initialize(IAddressesProvider provider) public initializer {
        _addressesProvider = provider;
    }

    /**
     * @dev Initializes reserves in batch
     **/
    function batchInitReserve(InitReserveInput[] calldata input)
    external
    onlyPoolAdmin
    {
        ILendPool cachedPool = _getLendPool();
        for (uint256 i = 0; i < input.length; i++) {
            _initReserve(cachedPool, input[i]);
        }
    }

    function _initReserve(ILendPool pool_, InitReserveInput calldata input)
    internal
    {
        address cTokenProxyAddress = _initTokenWithProxy(
            input.cTokenImpl,
            abi.encodeWithSelector(
                IChipToken.initialize.selector,
                _addressesProvider,
                input.underlyingAsset,
                input.underlyingAssetDecimals,
                input.cTokenName,
                input.cTokenSymbol
            )
        );

        address debtTokenProxyAddress = _initTokenWithProxy(
            input.debtTokenImpl,
            abi.encodeWithSelector(
                IDebtToken.initialize.selector,
                _addressesProvider,
                input.underlyingAsset,
                input.underlyingAssetDecimals,
                input.debtTokenName,
                input.debtTokenSymbol
            )
        );

        pool_.initReserve(
            input.underlyingAsset,
            cTokenProxyAddress,
            debtTokenProxyAddress,
            input.interestRateAddress
        );

        DataTypes.ReserveConfigurationMap memory currentConfig = pool_.getReserveConfiguration(input.underlyingAsset);

        currentConfig.setDecimals(input.underlyingAssetDecimals);

        currentConfig.setActive(true);
        currentConfig.setFrozen(false);

        pool_.setReserveConfiguration(
            input.underlyingAsset,
            currentConfig.data
        );

        emit ReserveInitialized(
            input.underlyingAsset,
            cTokenProxyAddress,
            debtTokenProxyAddress,
            input.interestRateAddress
        );
    }

    function batchInitNft(InitNftInput[] calldata input)
    external
    onlyPoolAdmin
    {
        ILendPool cachedPool = _getLendPool();
        ICNFTRegistry cachedRegistry = _getCNFTRegistry();

        for (uint256 i = 0; i < input.length; i++) {
            _initNft(cachedPool, cachedRegistry, input[i]);
        }
    }

    function _initNft(
        ILendPool pool_,
        ICNFTRegistry registry_,
        InitNftInput calldata input
    ) internal {
        // CNFT proxy and implementation are created in CNFTRegistry
        (address cNftProxy,) = registry_.getCNFTAddresses(
            input.underlyingAsset
        );
        require(cNftProxy != address(0), Errors.LPC_INVALIED_CNFT_ADDRESS);

        pool_.initNft(input.underlyingAsset, cNftProxy);

        DataTypes.NftConfigurationMap memory currentConfig = pool_
        .getNftConfiguration(input.underlyingAsset);

        currentConfig.setActive(true);
        currentConfig.setFrozen(false);

        pool_.setNftConfiguration(input.underlyingAsset, currentConfig.data);

        emit NftInitialized(input.underlyingAsset, cNftProxy);
    }

    /**
     * @dev Updates the cToken implementation for the reserve
     **/
    function updateCToken(UpdateCTokenInput calldata input)
    external
    onlyPoolAdmin
    {
        ILendPool cachedPool = _getLendPool();

        DataTypes.ReserveData memory reserveData = cachedPool.getReserveData(
            input.asset
        );

        _upgradeTokenImplementation(
            reserveData.cTokenAddress,
            input.implementation,
            input.encodedCallData
        );

        emit CTokenUpgraded(
            input.asset,
            reserveData.cTokenAddress,
            input.implementation
        );
    }

    /**
     * @dev Updates the debt token implementation for the asset
     **/
    function updateDebtToken(UpdateDebtTokenInput calldata input)
    external
    onlyPoolAdmin
    {
        ILendPool cachedPool = _getLendPool();

        DataTypes.ReserveData memory reserveData = cachedPool.getReserveData(
            input.asset
        );

        _upgradeTokenImplementation(
            reserveData.debtTokenAddress,
            input.implementation,
            input.encodedCallData
        );

        emit DebtTokenUpgraded(
            input.asset,
            reserveData.debtTokenAddress,
            input.implementation
        );
    }

    /**
     * @dev Enables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     **/
    function enableBorrowingOnReserve(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setBorrowingEnabled(true);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);

        emit BorrowingEnabledOnReserve(asset);
    }

    /**
     * @dev Disables borrowing on a reserve
     * @param asset The address of the underlying asset of the reserve
     **/
    function disableBorrowingOnReserve(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setBorrowingEnabled(false);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);
        emit BorrowingDisabledOnReserve(asset);
    }

    /**
     * @dev Activates a reserve
     * @param asset The address of the underlying asset of the reserve
     **/
    function activateReserve(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setActive(true);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);

        emit ReserveActivated(asset);
    }

    /**
     * @dev Deactivates a reserve
     * @param asset The address of the underlying asset of the reserve
     **/
    function deactivateReserve(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        _checkReserveNoLiquidity(asset);

        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setActive(false);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);

        emit ReserveDeactivated(asset);
    }

    /**
     * @dev Freezes a reserve. A frozen reserve doesn't allow any new deposit, borrow or rate swap
     *  but allows repayments, liquidations, rate rebalances and withdrawals
     * @param asset The address of the underlying asset of the reserve
     **/
    function freezeReserve(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setFrozen(true);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);

        emit ReserveFrozen(asset);
    }

    /**
     * @dev Unfreezes a reserve
     * @param asset The address of the underlying asset of the reserve
     **/
    function unfreezeReserve(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setFrozen(false);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);

        emit ReserveUnfrozen(asset);
    }

    /**
     * @dev Updates the reserve factor of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param reserveFactor The new reserve factor of the reserve
     **/
    function setReserveFactor(address asset, uint256 reserveFactor)
    external
    onlyPoolAdmin
    {
        ILendPool cachedPool = _getLendPool();
        DataTypes.ReserveConfigurationMap memory currentConfig = cachedPool
        .getReserveConfiguration(asset);

        currentConfig.setReserveFactor(reserveFactor);

        cachedPool.setReserveConfiguration(asset, currentConfig.data);

        emit ReserveFactorChanged(asset, reserveFactor);
    }

    /**
     * @dev Sets the interest rate strategy of a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param rateAddress The new address of the interest strategy contract
     **/
    function setReserveInterestRateAddress(address asset, address rateAddress)
    external
    onlyPoolAdmin
    {
        ILendPool cachedPool = _getLendPool();
        cachedPool.setReserveInterestRateAddress(asset, rateAddress);
        emit ReserveInterestRateChanged(asset, rateAddress);
    }

    /**
     * @dev Configures the NFT collateralization parameters
     * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
     * @param asset The address of the underlying asset of the reserve
     * @param ltv The loan to value of the asset when used as NFT
     * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param startIndex The startIndex
     * @param endIndex The endIndex
     * means the liquidator will receive a 5% bonus
     **/
    function configureNftAsCollateral(address asset, uint256 ltv, uint256 liquidationThreshold, uint256 startIndex,uint256 endIndex) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.NftConfigurationMap memory currentConfig = cachedPool
        .getNftConfiguration(asset);

        require(ltv <= liquidationThreshold, Errors.LPC_INVALID_CONFIGURATION);
        currentConfig.setLtv(ltv);
        currentConfig.setLiquidationThreshold(liquidationThreshold);
        currentConfig.setStartIndex(startIndex);
        currentConfig.setEndIndex(endIndex);

        cachedPool.setNftConfiguration(asset, currentConfig.data);

        emit NftConfigurationChanged(
            asset,
            ltv,
            liquidationThreshold
        );
    }

    /**
     * @dev Activates a NFT
     * @param asset The address of the underlying asset of the NFT
     **/
    function activateNft(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.NftConfigurationMap memory currentConfig = cachedPool
        .getNftConfiguration(asset);

        currentConfig.setActive(true);

        cachedPool.setNftConfiguration(asset, currentConfig.data);

        emit NftActivated(asset);
    }

    /**
     * @dev Deactivates a NFT
     * @param asset The address of the underlying asset of the NFT
     **/
    function deactivateNft(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        _checkNftNoLiquidity(asset);

        DataTypes.NftConfigurationMap memory currentConfig = cachedPool
        .getNftConfiguration(asset);

        currentConfig.setActive(false);

        cachedPool.setNftConfiguration(asset, currentConfig.data);

        emit NftDeactivated(asset);
    }

    /**
     * @dev Freezes a NFT. A frozen NFT doesn't allow any new borrow
     *  but allows repayments, liquidations
     * @param asset The address of the underlying asset of the NFT
     **/
    function freezeNft(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.NftConfigurationMap memory currentConfig = cachedPool
        .getNftConfiguration(asset);

        currentConfig.setFrozen(true);

        cachedPool.setNftConfiguration(asset, currentConfig.data);

        emit NftFrozen(asset);
    }

    /**
     * @dev Unfreezes a NFT
     * @param asset The address of the underlying asset of the NFT
     **/
    function unfreezeNft(address asset) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        DataTypes.NftConfigurationMap memory currentConfig = cachedPool
        .getNftConfiguration(asset);

        currentConfig.setFrozen(false);

        cachedPool.setNftConfiguration(asset, currentConfig.data);

        emit NftUnfrozen(asset);
    }

    function setMaxNumberOfReserves(uint256 newVal) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        //default value is 32
        uint256 curVal = cachedPool.getMaxNumberOfReserves();
        require(newVal > curVal, Errors.LPC_INVALID_CONFIGURATION);
        cachedPool.setMaxNumberOfReserves(newVal);
    }

    function setMaxNumberOfNfts(uint256 newVal) external onlyPoolAdmin {
        ILendPool cachedPool = _getLendPool();
        //default value is 256
        uint256 curVal = cachedPool.getMaxNumberOfNfts();
        require(newVal > curVal, Errors.LPC_INVALID_CONFIGURATION);
        cachedPool.setMaxNumberOfNfts(newVal);
    }


    function getTokenImplementation(address proxyAddress)
    external
    view
    onlyPoolAdmin
    returns (address)
    {
        ChipUpgradeableProxy proxy = ChipUpgradeableProxy(
            payable(proxyAddress)
        );
        return proxy.getImplementation();
    }

    function _initTokenWithProxy(
        address implementation,
        bytes memory initParams
    ) internal returns (address) {
        ChipUpgradeableProxy proxy = new ChipUpgradeableProxy(
            implementation,
            address(this),
            initParams
        );

        return address(proxy);
    }

    function _upgradeTokenImplementation(
        address proxyAddress,
        address implementation,
        bytes memory encodedCallData
    ) internal {
        ChipUpgradeableProxy proxy = ChipUpgradeableProxy(
            payable(proxyAddress)
        );

        if (encodedCallData.length > 0) {
            proxy.upgradeToAndCall(implementation, encodedCallData);
        } else {
            proxy.upgradeTo(implementation);
        }
    }

    function _checkReserveNoLiquidity(address asset) internal view {
        DataTypes.ReserveData memory reserveData = _getLendPool()
        .getReserveData(asset);

        uint256 availableLiquidity = IERC20Upgradeable(asset).balanceOf(
            reserveData.cTokenAddress
        );

        require(
            availableLiquidity == 0 && reserveData.currentLiquidityRate == 0,
            Errors.LPC_RESERVE_LIQUIDITY_NOT_0
        );
    }

    function _checkNftNoLiquidity(address asset) internal view {
        uint256 collateralAmount = _getLendPoolLoan().getNftCollateralAmount(
            asset
        );

        require(collateralAmount == 0, Errors.LPC_NFT_LIQUIDITY_NOT_0);
    }

    function _getLendPool() internal view returns (ILendPool) {
        return ILendPool(_addressesProvider.getLendPool());
    }

    function _getLendPoolLoan() internal view returns (ILoanPool) {
        return ILoanPool(_addressesProvider.getLendPoolLoan());
    }

    function _getIncentivesController()
    internal
    view
    returns (IIncentivesController)
    {
        return
        IIncentivesController(_addressesProvider.getIncentivesController());
    }

    function _getCNFTRegistry() internal view returns (ICNFTRegistry) {
        return ICNFTRegistry(_addressesProvider.getCNFTRegistry());
    }
}
