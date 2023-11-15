// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IChipToken} from "../../interfaces/IChipToken.sol";
import {IDebtToken} from "../../interfaces/IDebtToken.sol";
import {IInterestRate} from "../../interfaces/IInterestRate.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IReserveOracleGetter} from "../../interfaces/IReserveOracleGetter.sol";
import {INFTOracleGetter} from "../../interfaces/INFTOracleGetter.sol";
import {ILoanPool} from "../../interfaces/ILoanPool.sol";
import {IConfigurator} from "../../interfaces/IConfigurator.sol";

import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {Math} from "../math/Math.sol";
import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import {ReserveLogic} from "./ReserveLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";

/**
 * @title BorrowLogic library
 * @author CHIPMUNK
 * @notice Implements the logic to borrow feature
 */
library BorrowLogic {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ReserveLogic for DataTypes.ReserveData;

    /**
     * @dev Emitted on borrow() when loan needs to be opened
     * @param user The address of the user initiating the borrow(), receiving the funds
     * @param reserve The address of the underlying asset being borrowed
     * @param amount The amount borrowed out
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token id of the underlying NFT used as collateral
     * @param onBehalfOf The address that will be getting the loan
     * @param referral The referral code used
     **/
    event Borrow(
        address user,
        address indexed reserve,
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        address indexed onBehalfOf,
        uint256 borrowRate,
        uint256 loanId,
        uint16 indexed referral
    );

    /**
     * @dev Emitted on repay()
     * @param user The address of the user initiating the repay(), providing the funds
     * @param reserve The address of the underlying asset of the reserve
     * @param amount The amount repaid
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token id of the underlying NFT used as collateral
     * @param borrower The beneficiary of the repayment, getting his debt reduced
     * @param loanId The loan ID of the NFT loans
     **/
    event Repay(
        address user,
        address indexed reserve,
        uint256 amount,
        address indexed nftAsset,
        uint256 nftTokenId,
        address indexed borrower,
        uint256 loanId
    );

    struct ExecuteBorrowLocalVars {
        address initiator;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 loanId;
        address reserveOracle;
        address nftOracle;
        address loanAddress;
    }

    /**
     * @notice Implements the borrow feature. Through `borrow()`, users borrow assets from the protocol.
     * @dev Emits the `Borrow()` event.
     * @param reservesData The state of all the reserves
     * @param nftsData The state of all the nfts
     * @param params The additional parameters needed to execute the borrow function
     */
    function executeBorrow(
        IAddressesProvider addressesProvider,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(address => DataTypes.NftData) storage nftsData,
        DataTypes.ExecuteBorrowParams memory params
    ) external {
        _borrow(addressesProvider, reservesData, nftsData, params);
    }

    /**
     * @notice Implements the batch borrow feature. Through `batchBorrow()`, users repay borrow to the protocol.
     * @dev Emits the `Borrow()` event.
     * @param reservesData The state of all the reserves
     * @param nftsData The state of all the nfts
     * @param params The additional parameters needed to execute the batchBorrow function
     */
    function executeBatchBorrow(
        IAddressesProvider addressesProvider,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(address => DataTypes.NftData) storage nftsData,
        DataTypes.ExecuteBatchBorrowParams memory params
    ) external {
        require(
            params.nftAssets.length == params.assets.length,
            "inconsistent assets length"
        );
        require(
            params.nftAssets.length == params.amounts.length,
            "inconsistent amounts length"
        );
        require(
            params.nftAssets.length == params.nftTokenIds.length,
            "inconsistent tokenIds length"
        );

        for (uint256 i = 0; i < params.nftAssets.length; i++) {
            _borrow(
                addressesProvider,
                reservesData,
                nftsData,
                DataTypes.ExecuteBorrowParams({
            initiator : params.initiator,
            asset : params.assets[i],
            amount : params.amounts[i],
            nftAsset : params.nftAssets[i],
            nftTokenId : params.nftTokenIds[i],
            onBehalfOf : params.onBehalfOf,
            referralCode : params.referralCode
            })
            );
        }
    }

    function _borrow(
        IAddressesProvider addressesProvider,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(address => DataTypes.NftData) storage nftsData,
        DataTypes.ExecuteBorrowParams memory params
    ) internal {
        require(
            params.onBehalfOf != address(0),
            Errors.VL_INVALID_ONBEHALFOF_ADDRESS
        );
        require(!ILoanPool(addressesProvider.getLendPoolLoan()).isBlackList(params.nftAsset, params.nftTokenId),"The current NFT is on the blacklist and cannot borrow");

        ExecuteBorrowLocalVars memory vars;
        vars.initiator = params.initiator;

        DataTypes.ReserveData storage reserveData = reservesData[params.asset];
        DataTypes.NftData storage nftData = nftsData[params.nftAsset];

        // update state MUST BEFORE get borrow amount which is depent on latest borrow index
        reserveData.updateState();

        // Convert asset amount to ETH
        vars.reserveOracle = addressesProvider.getReserveOracle();
        vars.nftOracle = addressesProvider.getNFTOracle();
        vars.loanAddress = addressesProvider.getLendPoolLoan();

        vars.loanId = ILoanPool(vars.loanAddress).getCollateralLoanId(
            params.nftAsset,
            params.nftTokenId
        );

        ValidationLogic.validateBorrow(
            params.onBehalfOf,
            params.asset,
            params.amount,
            reserveData,
            params.nftAsset,
            nftData,
            vars.loanAddress,
            vars.loanId,
            vars.reserveOracle,
            vars.nftOracle
        );

        if (vars.loanId == 0) {
            IConfigurator configurator = IConfigurator(addressesProvider.getConfigurator());
            require(params.amount >= configurator.minLend(), Errors.LP_AMOUNT_LESS_THAN_MIN_LEND);
            IERC721Upgradeable(params.nftAsset).safeTransferFrom(
                vars.initiator,
                address(this),
                params.nftTokenId
            );

            vars.loanId = ILoanPool(vars.loanAddress).createLoan(
                vars.initiator,
                params.onBehalfOf,
                params.nftAsset,
                params.nftTokenId,
                nftData.cNftAddress,
                params.asset,
                params.amount,
                reserveData.variableBorrowIndex
            );
        } else {
            ILoanPool(vars.loanAddress).updateLoan(
                vars.initiator,
                vars.loanId,
                params.amount,
                0,
                reserveData.variableBorrowIndex,
                false
            );
        }

        IDebtToken(reserveData.debtTokenAddress).mint(
            vars.initiator,
            params.onBehalfOf,
            params.amount,
            reserveData.variableBorrowIndex
        );

        // update interest rate according latest borrow amount (utilizaton)
        reserveData.updateInterestRates(
            params.asset,
            reserveData.cTokenAddress,
            0,
            params.amount
        );

        IChipToken(reserveData.cTokenAddress).transferUnderlyingTo(
            vars.initiator,
            params.amount
        );

        emit Borrow(
            vars.initiator,
            params.asset,
            params.amount,
            params.nftAsset,
            params.nftTokenId,
            params.onBehalfOf,
            reserveData.currentVariableBorrowRate,
            vars.loanId,
            params.referralCode
        );
    }

    struct RepayLocalVars {
        address initiator;
        address poolLoan;
        address onBehalfOf;
        uint256 loanId;
        bool isUpdate;
        uint256 borrowAmount;
        uint256 repayAmount;
        address loanAddress;
        address reserveOracle;
        address nftOracle;
        bool isLiquidate;
        uint256 thresholdPrice;
        uint256 liquidatePrice;
        uint256 highestThresholdPrice;
    }

    /**
     * @notice Implements the borrow feature. Through `repay()`, users repay assets to the protocol.
     * @dev Emits the `Repay()` event.
     * @param reservesData The state of all the reserves
     * @param nftsData The state of all the nfts
     * @param params The additional parameters needed to execute the repay function
     */
    function executeRepay(
        IAddressesProvider addressesProvider,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(address => DataTypes.NftData) storage nftsData,
        DataTypes.ExecuteRepayParams memory params
    ) external returns (uint256, bool) {
        return _repay(addressesProvider, reservesData, nftsData, params);
    }

    /**
     * @notice Implements the batch repay feature. Through `batchRepay()`, users repay assets to the protocol.
     * @dev Emits the `repay()` event.
     * @param reservesData The state of all the reserves
     * @param nftsData The state of all the nfts
     * @param params The additional parameters needed to execute the batchRepay function
     */
    function executeBatchRepay(
        IAddressesProvider addressesProvider,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(address => DataTypes.NftData) storage nftsData,
        DataTypes.ExecuteBatchRepayParams memory params
    ) external returns (uint256[] memory, bool[] memory) {
        require(
            params.nftAssets.length == params.amounts.length,
            "inconsistent amounts length"
        );
        require(
            params.nftAssets.length == params.nftTokenIds.length,
            "inconsistent tokenIds length"
        );

        uint256[] memory repayAmounts = new uint256[](params.nftAssets.length);
        bool[] memory repayAlls = new bool[](params.nftAssets.length);

        for (uint256 i = 0; i < params.nftAssets.length; i++) {
            (repayAmounts[i], repayAlls[i]) = _repay(
                addressesProvider,
                reservesData,
                nftsData,
                DataTypes.ExecuteRepayParams({
            initiator : params.initiator,
            nftAsset : params.nftAssets[i],
            nftTokenId : params.nftTokenIds[i],
            amount : params.amounts[i]
            })
            );
        }

        return (repayAmounts, repayAlls);
    }

    function _repay(
        IAddressesProvider addressesProvider,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(address => DataTypes.NftData) storage nftsData,
        DataTypes.ExecuteRepayParams memory params
    ) internal returns (uint256, bool) {
        RepayLocalVars memory vars;
        vars.initiator = params.initiator;

        vars.poolLoan = addressesProvider.getLendPoolLoan();

        vars.loanId = ILoanPool(vars.poolLoan).getCollateralLoanId(
            params.nftAsset,
            params.nftTokenId
        );
        require(vars.loanId != 0, Errors.LP_NFT_IS_NOT_USED_AS_COLLATERAL);

        DataTypes.LoanData memory loanData = ILoanPool(vars.poolLoan).getLoan(
            vars.loanId
        );

        DataTypes.ReserveData storage reserveData = reservesData[
        loanData.reserveAsset
        ];
        DataTypes.NftData storage nftData = nftsData[loanData.nftAsset];
        vars.loanAddress = addressesProvider.getLendPoolLoan();
        vars.reserveOracle = addressesProvider.getReserveOracle();
        vars.nftOracle = addressesProvider.getNFTOracle();

        // update state MUST BEFORE get borrow amount which is depent on latest borrow index
        reserveData.updateState();

        (, vars.borrowAmount) = ILoanPool(vars.poolLoan)
        .getLoanReserveBorrowAmount(vars.loanId);


        ValidationLogic.validateRepay(
            reserveData,
            nftData,
            loanData,
            params.amount,
            vars.borrowAmount
        );

        vars.repayAmount = vars.borrowAmount;
        vars.isUpdate = false;
        if (params.amount < vars.repayAmount) {
            vars.isUpdate = true;
            vars.repayAmount = params.amount;
        }

        if (vars.isUpdate) {
            (
            vars.borrowAmount,
            vars.thresholdPrice,
            vars.liquidatePrice,
            vars.highestThresholdPrice
            ) = GenericLogic.calculateLoanLiquidatePrice(
                vars.loanId,
                loanData.reserveAsset,
                reserveData,
                loanData.nftAsset,
                nftData,
                vars.loanAddress,
                vars.reserveOracle,
                vars.nftOracle
            );

            if (vars.borrowAmount - vars.repayAmount <= vars.thresholdPrice) {
                vars.isLiquidate = true;
            }
            ILoanPool(vars.poolLoan).updateLoan(
                vars.initiator,
                vars.loanId,
                0,
                vars.repayAmount,
                reserveData.variableBorrowIndex,
                vars.isLiquidate
            );
        } else {
            ILoanPool(vars.poolLoan).repayLoan(
                vars.initiator,
                vars.loanId,
                nftData.cNftAddress,
                vars.repayAmount,
                reserveData.variableBorrowIndex
            );
        }

        IDebtToken(reserveData.debtTokenAddress).burn(
            loanData.borrower,
            vars.repayAmount,
            reserveData.variableBorrowIndex
        );

        // update interest rate according latest borrow amount (utilizaton)
        reserveData.updateInterestRates(
            loanData.reserveAsset,
            reserveData.cTokenAddress,
            vars.repayAmount,
            0
        );


        // transfer repay amount to cToken
        IERC20Upgradeable(loanData.reserveAsset).safeTransferFrom(
            vars.initiator,
            reserveData.cTokenAddress,
            vars.repayAmount
        );

        // transfer erc721 to borrower
        if (!vars.isUpdate) {
            IERC721Upgradeable(loanData.nftAsset).safeTransferFrom(
                address(this),
                loanData.borrower,
                params.nftTokenId
            );
        }

        emit Repay(
            vars.initiator,
            loanData.reserveAsset,
            vars.repayAmount,
            loanData.nftAsset,
            loanData.nftTokenId,
            loanData.borrower,
            vars.loanId
        );

        return (vars.repayAmount, !vars.isUpdate);
    }
}
