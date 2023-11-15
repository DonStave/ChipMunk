// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
pragma experimental ABIEncoderV2;

import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import {Errors} from "./libraries/helpers/Errors.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {ICapitalPool} from "./interfaces/ICapitalPool.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {ILoanPool} from "./interfaces/ILoanPool.sol";
import {IChipToken} from "./interfaces/IChipToken.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {Math} from "./libraries/math/Math.sol";
import {IESM} from "./interfaces/IESM.sol";
import {EmergencyTokenRecoveryUpgradeable} from "./EmergencyTokenRecoveryUpgradeable.sol";

import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";


contract CapitalPool is
ICapitalPool,
ERC721HolderUpgradeable,
EmergencyTokenRecoveryUpgradeable
{
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IAddressesProvider internal _addressProvider;

    IWETH internal WETH;


    uint256 private constant _NOT_ENTERED = 0;
    uint256 private constant _ENTERED = 1;
    uint256 private _status;
    address lendPool;
    address public admin;

    /**
     * @dev Sets the WETH address and the LendPoolAddressesProvider address. Infinite approves lend pool.
     * @param _weth Address of the Wrapped Ether contract
     **/
    function initialize(address addressProvider, address _weth)
    public
    initializer
    {
        __ERC721Holder_init();
        __EmergencyTokenRecovery_init();

        _addressProvider = IAddressesProvider(addressProvider);

        WETH = IWETH(_weth);
        WETH.approve(address(_getLendPool()), type(uint256).max);
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "CapitalPool: !admin");
        _;
    }
    modifier OnlyLendPool() {
        require(
            msg.sender == address(lendPool),
            "Caller is not lendPool contract"
        );
        _;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    function setAdmin(address newAdmin) external override{
        require(newAdmin != address(0), "CapitalPool: new admin is the zero address");
        require(msg.sender == _addressProvider.getManage(), Errors.CT_CALLER_MUST_BE_MANAGE);
        admin = newAdmin;
    }

    function _getLendPool() internal view returns (ILendPool) {
        return ILendPool(_addressProvider.getLendPool());
    }

    function _getLoanPool() internal view returns (ILoanPool) {
        return ILoanPool(_addressProvider.getLendPoolLoan());
    }

    function authorizeLendPoolNFT(address[] calldata nftAssets)
    external
    nonReentrant
    onlyAdmin
    {
        for (uint256 i = 0; i < nftAssets.length; i++) {
            IERC721Upgradeable(nftAssets[i]).setApprovalForAll(
                address(_getLendPool()),
                true
            );
        }
    }

    function depositETH(uint16 referralCode)
    external
    payable
    override
    nonReentrant
    {
        address depositor = tx.origin;
        ILendPool cachedPool = _getLendPool();

        WETH.deposit{value : msg.value}();
        cachedPool.deposit(address(WETH), msg.value, depositor, referralCode);
    }

    function withdrawETH(uint256 amount, address to)
    external
    override
    nonReentrant
    {
        ILendPool cachedPool = _getLendPool();
        IChipToken cETH = IChipToken(
            cachedPool.getReserveData(address(WETH)).cTokenAddress
        );

        uint256 userBalance = cETH.balanceOf(msg.sender);
        uint256 amountToWithdraw = amount;

        // if amount is equal to uint(-1), the user wants to redeem everything
        if (amount ==type(uint256).max) {
        amountToWithdraw = userBalance;
        }

        cETH.transferFrom(msg.sender, address(this), amountToWithdraw);
        cachedPool.withdraw(address(WETH), amountToWithdraw, address(this));
        WETH.withdraw(amountToWithdraw);
        _safeTransferETH(to, amountToWithdraw);
    }

    function borrowETH(
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        address borrower,
        uint16 referralCode
    ) external override nonReentrant {
        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        uint256 loanId = loanPool.getCollateralLoanId(nftAsset, nftTokenId);
        if (loanId == 0) {
            IERC721Upgradeable(nftAsset).safeTransferFrom(
                msg.sender,
                address(this),
                nftTokenId
            );
        }
        cachedPool.borrow(
            address(WETH),
            amount,
            nftAsset,
            nftTokenId,
            borrower,
            referralCode
        );
        WETH.withdraw(amount);
        _safeTransferETH(borrower, amount);
    }

    function borrowWETH(
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        address borrower,
        uint16 referralCode
    ) external override nonReentrant {
        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        uint256 loanId = loanPool.getCollateralLoanId(nftAsset, nftTokenId);
        if (loanId == 0) {
            IERC721Upgradeable(nftAsset).safeTransferFrom(
                msg.sender,
                address(this),
                nftTokenId
            );
        }
        cachedPool.borrow(
            address(WETH),
            amount,
            nftAsset,
            nftTokenId,
            borrower,
            referralCode
        );
        IERC20Upgradeable(address(WETH)).transfer(borrower, amount);
    }

    function batchBorrowETH(
        uint256[] calldata amounts,
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds,
        address borrower,
        uint16 referralCode
    ) external override nonReentrant {
        require(
            nftAssets.length == nftTokenIds.length,
            "inconsistent tokenIds length"
        );
        require(
            nftAssets.length == amounts.length,
            "inconsistent amounts length"
        );

        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        for (uint256 i = 0; i < nftAssets.length; i++) {
            uint256 loanId = loanPool.getCollateralLoanId(
                nftAssets[i],
                nftTokenIds[i]
            );
            if (loanId == 0) {
                IERC721Upgradeable(nftAssets[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    nftTokenIds[i]
                );
            }
            cachedPool.borrow(
                address(WETH),
                amounts[i],
                nftAssets[i],
                nftTokenIds[i],
                borrower,
                referralCode
            );

            WETH.withdraw(amounts[i]);
            _safeTransferETH(borrower, amounts[i]);
        }
    }

    function batchBorrowWETH(
        uint256[] calldata amounts,
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds,
        address borrower,
        uint16 referralCode
    ) external override nonReentrant {
        require(
            nftAssets.length == nftTokenIds.length,
            "inconsistent tokenIds length"
        );
        require(
            nftAssets.length == amounts.length,
            "inconsistent amounts length"
        );

        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        for (uint256 i = 0; i < nftAssets.length; i++) {
            uint256 loanId = loanPool.getCollateralLoanId(
                nftAssets[i],
                nftTokenIds[i]
            );
            if (loanId == 0) {
                IERC721Upgradeable(nftAssets[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    nftTokenIds[i]
                );
            }
            cachedPool.borrow(
                address(WETH),
                amounts[i],
                nftAssets[i],
                nftTokenIds[i],
                borrower,
                referralCode
            );
            IERC20Upgradeable(address(WETH)).transfer(borrower, amounts[i]);
        }
    }

    function repayETH(
        address nftAsset,
        uint256 nftTokenId,
        uint256 amount
    ) external payable override nonReentrant returns (uint256, bool) {
        (uint256 repayAmount, bool repayAll) = _repayETH(
            nftAsset,
            nftTokenId,
            amount,
            0
        );

        // refund remaining dust eth
        if (msg.value > repayAmount) {
            _safeTransferETH(tx.origin, msg.value - repayAmount);
        }

        return (repayAmount, repayAll);
    }

    function batchRepayETH(
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds,
        uint256[] calldata amounts
    )
    external
    payable
    override
    nonReentrant
    returns (uint256[] memory, bool[] memory)
    {
        require(
            nftAssets.length == amounts.length,
            "inconsistent amounts length"
        );
        require(
            nftAssets.length == nftTokenIds.length,
            "inconsistent tokenIds length"
        );

        uint256[] memory repayAmounts = new uint256[](nftAssets.length);
        bool[] memory repayAlls = new bool[](nftAssets.length);
        uint256 allRepayDebtAmount = 0;

        for (uint256 i = 0; i < nftAssets.length; i++) {
            (repayAmounts[i], repayAlls[i]) = _repayETH(
                nftAssets[i],
                nftTokenIds[i],
                amounts[i],
                allRepayDebtAmount
            );

            allRepayDebtAmount += repayAmounts[i];
        }

        // refund remaining dust eth
        if (msg.value > allRepayDebtAmount) {
            _safeTransferETH(tx.origin, msg.value - allRepayDebtAmount);
        }

        return (repayAmounts, repayAlls);
    }

    function _repayETH(
        address nftAsset,
        uint256 nftTokenId,
        uint256 amount,
        uint256 accAmount
    ) internal returns (uint256, bool) {
        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        uint256 loanId = loanPool.getCollateralLoanId(nftAsset, nftTokenId);
        require(loanId > 0, "collateral loan id not exist");

        (address reserveAsset, uint256 repayDebtAmount) = loanPool
        .getLoanReserveBorrowAmount(loanId);
        require(reserveAsset == address(WETH), "loan reserve not WETH");

        if (amount < repayDebtAmount) {
            repayDebtAmount = amount;
        }

        require(
            msg.value >= (accAmount + repayDebtAmount),
            "msg.value is less than repay amount"
        );

        WETH.deposit{value : repayDebtAmount}();
        (uint256 paybackAmount, bool burn) = cachedPool.repay(
            nftAsset,
            nftTokenId,
            amount
        );

        return (paybackAmount, burn);
    }

    function auctionETH(
        address nftAsset,
        uint256 nftTokenId,
        address bidder
    ) external payable override nonReentrant {
        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        uint256 loanId = loanPool.getCollateralLoanId(nftAsset, nftTokenId);
        require(loanId > 0, "collateral loan id not exist");

        DataTypes.LoanData memory loan = loanPool.getLoan(loanId);
        require(loan.reserveAsset == address(WETH), "loan reserve not WETH");

        WETH.deposit{value : msg.value}();
        cachedPool.auction(nftAsset, nftTokenId, msg.value, bidder);
    }

    function liquidateETH(address nftAsset, uint256 nftTokenId)
    external
    payable
    override
    nonReentrant
    returns (uint256)
    {
        ILendPool cachedPool = _getLendPool();
        ILoanPool loanPool = _getLoanPool();

        uint256 loanId = loanPool.getCollateralLoanId(nftAsset, nftTokenId);
        require(loanId > 0, "collateral loan id not exist");

        DataTypes.LoanData memory loan = loanPool.getLoan(loanId);
        require(loan.reserveAsset == address(WETH), "loan reserve not WETH");

        if (msg.value > 0) {
            WETH.deposit{value : msg.value}();
        }

        uint256 extraAmount = cachedPool.liquidate(
            nftAsset,
            nftTokenId,
            msg.value
        );

        if (msg.value > extraAmount) {
            WETH.withdraw(msg.value - extraAmount);
            _safeTransferETH(msg.sender, msg.value - extraAmount);
        }

        return (extraAmount);
    }

    /**
     * @dev transfer ETH to an address, revert if it fails.
     * @param to recipient of the transfer
     * @param value the amount to send
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value : value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }

    /**
     * @dev Get WETH address used by WETHGateway
     */
    function getWETHAddress() external view returns (address) {
        return address(WETH);
    }

    /**
     * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(WETH), "Receive not allowed");
    }


}
