// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IAddressesProvider} from "./IAddressesProvider.sol";
import {IIncentivesController} from "./IIncentivesController.sol";

interface IUiPoolDataProvider {
    struct AggregatedReserveData {
        address underlyingAsset;
        string name;
        string symbol;
        uint256 decimals;
        uint256 reserveFactor;
        bool borrowingEnabled;
        bool isActive;
        bool isFrozen;
        // base data
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 liquidityRate;
        uint128 variableBorrowRate;
        uint40 lastUpdateTimestamp;
        address cTokenAddress;
        address debtTokenAddress;
        address interestRateAddress;
        //
        uint256 availableLiquidity;
        uint256 totalVariableDebt;
        uint256 priceInEth;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
    }

    struct UserReserveData {
        address underlyingAsset;
        uint256 cTokenBalance;
        uint256 variableDebt;
    }

    struct AggregatedNftData {
        address underlyingAsset;
        string name;
        string symbol;
        uint256 ltv;
        uint256 liquidationThreshold;
        bool isActive;
        bool isFrozen;
        address cNftAddress;
        uint256 priceInEth;
        uint256 totalCollateral;
        uint256 startIndex;
        uint256 endIndex;
    }

    struct UserNftData {
        address underlyingAsset;
        address cNftAddress;
        uint256 totalCollateral;
    }

    struct AggregatedLoanData {
        uint256 loanId;
        uint256 state;
        address reserveAsset;
        uint256 totalCollateralInReserve;
        uint256 totalDebtInReserve;
        uint256 availableBorrowsInReserve;
        uint256 healthFactor;
        uint256 liquidatePrice;
        address bidderAddress;
        uint256 bidPrice;
        uint256 bidBorrowAmount;
    }

    function getReservesList(IAddressesProvider provider)
        external
        view
        returns (address[] memory);

    function getSimpleReservesData(IAddressesProvider provider)
        external
        view
        returns (AggregatedReserveData[] memory);

    function getUserReservesData(IAddressesProvider provider, address user)
        external
        view
        returns (UserReserveData[] memory);

    // generic method with full data
    function getReservesData(IAddressesProvider provider, address user)
        external
        view
        returns (AggregatedReserveData[] memory, UserReserveData[] memory);

    function getNftsList(IAddressesProvider provider)
        external
        view
        returns (address[] memory);

    function getSimpleNftsData(IAddressesProvider provider)
        external
        view
        returns (AggregatedNftData[] memory);

    function getUserNftsData(IAddressesProvider provider, address user)
        external
        view
        returns (UserNftData[] memory);

    // generic method with full data
    function getNftsData(IAddressesProvider provider, address user)
        external
        view
        returns (AggregatedNftData[] memory, UserNftData[] memory);

    function getSimpleLoansData(
        IAddressesProvider provider,
        address[] memory nftAssets,
        uint256[] memory nftTokenIds
    ) external view returns (AggregatedLoanData[] memory);
}
