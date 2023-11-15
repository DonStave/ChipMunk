// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IERC20Detailed} from "./interfaces/IERC20Detailed.sol";
import {IERC721Detailed} from "./interfaces/IERC721Detailed.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {IUiPoolDataProvider} from "./interfaces/IUiPoolDataProvider.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {ILoanPool} from "./interfaces/ILoanPool.sol";
import {IReserveOracleGetter} from "./interfaces/IReserveOracleGetter.sol";
import {INFTOracleGetter} from "./interfaces/INFTOracleGetter.sol";
import {IChipToken} from "./interfaces/IChipToken.sol";
import {IDebtToken} from "./interfaces/IDebtToken.sol";
import {Math} from "./libraries/math/Math.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {NftConfiguration} from "./libraries/configuration/NftConfiguration.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {InterestRate} from "./protocol/InterestRate.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract UiPoolDataProvider is IUiPoolDataProvider {
    using Math for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using NftConfiguration for DataTypes.NftConfigurationMap;

    IReserveOracleGetter public immutable reserveOracle;
    INFTOracleGetter public immutable nftOracle;

    constructor(
        IReserveOracleGetter _reserveOracle,
        INFTOracleGetter _nftOracle
    ) {
        reserveOracle = _reserveOracle;
        nftOracle = _nftOracle;
    }

    function getInterestRateStrategySlopes(InterestRate interestRate)
        internal
        view
        returns (uint256, uint256)
    {
        return (
            interestRate.variableRateSlope1(),
            interestRate.variableRateSlope2()
        );
    }

    function getReservesList(IAddressesProvider provider)
        public
        view
        override
        returns (address[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        return lendPool.getReservesList();
    }

    function getSimpleReservesData(IAddressesProvider provider)
        public
        view
        override
        returns (AggregatedReserveData[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        address[] memory reserves = lendPool.getReservesList();
        AggregatedReserveData[]
            memory reservesData = new AggregatedReserveData[](reserves.length);

        for (uint256 i = 0; i < reserves.length; i++) {
            AggregatedReserveData memory reserveData = reservesData[i];

            DataTypes.ReserveData memory baseData = lendPool.getReserveData(
                reserves[i]
            );

            _fillReserveData(reserveData, reserves[i], baseData);
        }

        return (reservesData);
    }

    function getUserReservesData(IAddressesProvider provider, address user)
        external
        view
        override
        returns (UserReserveData[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        address[] memory reserves = lendPool.getReservesList();

        UserReserveData[] memory userReservesData = new UserReserveData[](
            user != address(0) ? reserves.length : 0
        );

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveData memory baseData = lendPool.getReserveData(
                reserves[i]
            );

            _fillUserReserveData(
                userReservesData[i],
                user,
                reserves[i],
                baseData
            );
        }

        return (userReservesData);
    }

    function getReservesData(IAddressesProvider provider, address user)
        external
        view
        override
        returns (AggregatedReserveData[] memory, UserReserveData[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        address[] memory reserves = lendPool.getReservesList();

        AggregatedReserveData[]
            memory reservesData = new AggregatedReserveData[](reserves.length);
        UserReserveData[] memory userReservesData = new UserReserveData[](
            user != address(0) ? reserves.length : 0
        );

        for (uint256 i = 0; i < reserves.length; i++) {
            AggregatedReserveData memory reserveData = reservesData[i];

            DataTypes.ReserveData memory baseData = lendPool.getReserveData(
                reserves[i]
            );
            _fillReserveData(reserveData, reserves[i], baseData);

            if (user != address(0)) {
                _fillUserReserveData(
                    userReservesData[i],
                    user,
                    reserves[i],
                    baseData
                );
            }
        }

        return (reservesData, userReservesData);
    }

    function _fillReserveData(
        AggregatedReserveData memory reserveData,
        address reserveAsset,
        DataTypes.ReserveData memory baseData
    ) internal view {
        reserveData.underlyingAsset = reserveAsset;

        // reserve current state
        reserveData.liquidityIndex = baseData.liquidityIndex;
        reserveData.variableBorrowIndex = baseData.variableBorrowIndex;
        reserveData.liquidityRate = baseData.currentLiquidityRate;
        reserveData.variableBorrowRate = baseData.currentVariableBorrowRate;
        reserveData.lastUpdateTimestamp = baseData.lastUpdateTimestamp;
        reserveData.cTokenAddress = baseData.cTokenAddress;
        reserveData.debtTokenAddress = baseData.debtTokenAddress;
        reserveData.interestRateAddress = baseData.interestRateAddress;
        reserveData.priceInEth = reserveOracle.getAssetPrice(
            reserveData.underlyingAsset
        );

        reserveData.availableLiquidity = IERC20Detailed(
            reserveData.underlyingAsset
        ).balanceOf(reserveData.cTokenAddress);
        reserveData.totalVariableDebt = IDebtToken(reserveData.debtTokenAddress)
            .totalSupply();

        // reserve configuration
        reserveData.symbol = IERC20Detailed(reserveData.underlyingAsset)
            .symbol();
        reserveData.name = IERC20Detailed(reserveData.underlyingAsset).name();

        (, , reserveData.decimals, reserveData.reserveFactor) = baseData
            .configuration
            .getParamsMemory();
        (
            reserveData.isActive,
            reserveData.isFrozen,
            reserveData.borrowingEnabled,

        ) = baseData.configuration.getFlagsMemory();
        (
            reserveData.variableRateSlope1,
            reserveData.variableRateSlope2
        ) = getInterestRateStrategySlopes(
            InterestRate(reserveData.interestRateAddress)
        );
    }

    function _fillUserReserveData(
        UserReserveData memory userReserveData,
        address user,
        address reserveAsset,
        DataTypes.ReserveData memory baseData
    ) internal view {
        // user reserve data
        userReserveData.underlyingAsset = reserveAsset;
        userReserveData.cTokenBalance = IChipToken(baseData.cTokenAddress)
            .balanceOf(user);
        userReserveData.variableDebt = IDebtToken(baseData.debtTokenAddress)
            .balanceOf(user);
    }

    function getNftsList(IAddressesProvider provider)
        external
        view
        override
        returns (address[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        return lendPool.getNftsList();
    }

    function getSimpleNftsData(IAddressesProvider provider)
        external
        view
        override
        returns (AggregatedNftData[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        ILoanPool lendPoolLoan = ILoanPool(provider.getLendPoolLoan());
        address[] memory nfts = lendPool.getNftsList();
        AggregatedNftData[] memory nftsData = new AggregatedNftData[](
            nfts.length
        );

        for (uint256 i = 0; i < nfts.length; i++) {
            AggregatedNftData memory nftData = nftsData[i];

            DataTypes.NftData memory baseData = lendPool.getNftData(nfts[i]);

            _fillNftData(nftData, nfts[i], baseData, lendPoolLoan);
        }

        return (nftsData);
    }

    function getUserNftsData(IAddressesProvider provider, address user)
        external
        view
        override
        returns (UserNftData[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        ILoanPool lendPoolLoan = ILoanPool(provider.getLendPoolLoan());
        address[] memory nfts = lendPool.getNftsList();

        UserNftData[] memory userNftsData = new UserNftData[](
            user != address(0) ? nfts.length : 0
        );

        for (uint256 i = 0; i < nfts.length; i++) {
            UserNftData memory userNftData = userNftsData[i];

            DataTypes.NftData memory baseData = lendPool.getNftData(nfts[i]);

            _fillUserNftData(
                userNftData,
                user,
                nfts[i],
                baseData,
                lendPoolLoan
            );
        }

        return (userNftsData);
    }

    // generic method with full data
    function getNftsData(IAddressesProvider provider, address user)
        external
        view
        override
        returns (AggregatedNftData[] memory, UserNftData[] memory)
    {
        ILendPool lendPool = ILendPool(provider.getLendPool());
        ILoanPool lendPoolLoan = ILoanPool(provider.getLendPoolLoan());
        address[] memory nfts = lendPool.getNftsList();

        AggregatedNftData[] memory nftsData = new AggregatedNftData[](
            nfts.length
        );
        UserNftData[] memory userNftsData = new UserNftData[](
            user != address(0) ? nfts.length : 0
        );

        for (uint256 i = 0; i < nfts.length; i++) {
            AggregatedNftData memory nftData = nftsData[i];
            UserNftData memory userNftData = userNftsData[i];

            DataTypes.NftData memory baseData = lendPool.getNftData(nfts[i]);

            _fillNftData(nftData, nfts[i], baseData, lendPoolLoan);
            if (user != address(0)) {
                _fillUserNftData(
                    userNftData,
                    user,
                    nfts[i],
                    baseData,
                    lendPoolLoan
                );
            }
        }

        return (nftsData, userNftsData);
    }

    function _fillNftData(
        AggregatedNftData memory nftData,
        address nftAsset,
        DataTypes.NftData memory baseData,
        ILoanPool lendPoolLoan
    ) internal view {
        nftData.underlyingAsset = nftAsset;

        // nft current state
        nftData.cNftAddress = baseData.cNftAddress;
        nftData.priceInEth = nftOracle.getAssetPrice(nftData.underlyingAsset);

        nftData.totalCollateral = lendPoolLoan.getNftCollateralAmount(nftAsset);

        // nft configuration
        nftData.symbol = IERC721Detailed(nftData.underlyingAsset).symbol();
        nftData.name = IERC721Detailed(nftData.underlyingAsset).name();

        (
            nftData.ltv,
            nftData.liquidationThreshold,
            nftData.startIndex,
            nftData.endIndex
        ) = baseData.configuration.getCollateralParamsMemory();
        (nftData.isActive, nftData.isFrozen) = baseData
            .configuration
            .getFlagsMemory();
    }

    function _fillUserNftData(
        UserNftData memory userNftData,
        address user,
        address nftAsset,
        DataTypes.NftData memory baseData,
        ILoanPool lendPoolLoan
    ) internal view {
        userNftData.underlyingAsset = nftAsset;

        // user nft data
        userNftData.cNftAddress = baseData.cNftAddress;

        userNftData.totalCollateral = lendPoolLoan.getUserNftCollateralAmount(
            user,
            nftAsset
        );
    }

    function getSimpleLoansData(
        IAddressesProvider provider,
        address[] memory nftAssets,
        uint256[] memory nftTokenIds
    ) external view override returns (AggregatedLoanData[] memory) {
        require(
            nftAssets.length == nftTokenIds.length,
            Errors.LP_INCONSISTENT_PARAMS
        );

        ILendPool lendPool = ILendPool(provider.getLendPool());
        ILoanPool poolLoan = ILoanPool(provider.getLendPoolLoan());

        AggregatedLoanData[] memory loansData = new AggregatedLoanData[](
            nftAssets.length
        );

        for (uint256 i = 0; i < nftAssets.length; i++) {
            AggregatedLoanData memory loanData = loansData[i];

            // NFT debt data
            (
                loanData.loanId,
                loanData.reserveAsset,
                loanData.totalCollateralInReserve,
                loanData.totalDebtInReserve,
                loanData.availableBorrowsInReserve,
                loanData.healthFactor
            ) = lendPool.getNftDebtData(nftAssets[i], nftTokenIds[i]);

            DataTypes.LoanData memory loan = poolLoan.getLoan(loanData.loanId);
            loanData.state = uint256(loan.state);

            (loanData.liquidatePrice, ) = lendPool.getNftLiquidatePrice(
                nftAssets[i],
                nftTokenIds[i]
            );

            // NFT auction data
            (
                ,
                loanData.bidderAddress,
                loanData.bidPrice,
                loanData.bidBorrowAmount
            ) = lendPool.getNftAuctionData(nftAssets[i], nftTokenIds[i]);
        }

        return loansData;
    }
}
