// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import {Errors} from "./libraries/helpers/Errors.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {ILoanPool} from "./interfaces/ILoanPool.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {IPunks} from "./interfaces/IPunks.sol";
import {IWrappedPunks} from "./interfaces/IWrappedPunks.sol";
import {IPunkPool} from "./interfaces/IPunkPool.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {ICapitalPool} from "./interfaces/ICapitalPool.sol";

import {EmergencyTokenRecoveryUpgradeable} from "./EmergencyTokenRecoveryUpgradeable.sol";

contract PunkPool is IPunkPool, ERC721HolderUpgradeable, EmergencyTokenRecoveryUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IAddressesProvider internal _addressProvider;
    ICapitalPool internal _capitalPool;

    IPunks public punks;
    IWrappedPunks public wrappedPunks;
    address public proxy;

    uint256 private constant _NOT_ENTERED = 0;
    uint256 private constant _ENTERED = 1;
    uint256 private _status;
    address public admin;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and making it call a
   * `private` function that does the actual work.
   */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "PunkPool: !admin");
        _;
    }

    function initialize(
        address addressProvider,
        address capitalPool,
        address _punks,
        address _wrappedPunks
    ) public initializer {
        __ERC721Holder_init();
        __EmergencyTokenRecovery_init();

        _addressProvider = IAddressesProvider(addressProvider);
        _capitalPool = ICapitalPool(capitalPool);

        punks = IPunks(_punks);
        wrappedPunks = IWrappedPunks(_wrappedPunks);
        wrappedPunks.registerProxy();
        proxy = wrappedPunks.proxyInfo(address(this));

        IERC721Upgradeable(address(wrappedPunks)).setApprovalForAll(address(_getLendPool()), true);
        IERC721Upgradeable(address(wrappedPunks)).setApprovalForAll(address(_capitalPool), true);

        admin = msg.sender;
    }

    function _getLendPool() internal view returns (ILendPool) {
        return ILendPool(_addressProvider.getLendPool());
    }

    function _getLendPoolLoan() internal view returns (ILoanPool) {
        return ILoanPool(_addressProvider.getLendPoolLoan());
    }

    function authorizeLendPoolERC20(address[] calldata tokens) external nonReentrant onlyAdmin {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Upgradeable(tokens[i]).approve(address(_getLendPool()), type(uint256).max);
        }
    }


    function _depositPunk(uint256 punkIndex) internal {
        ILoanPool cachedPoolLoan = _getLendPoolLoan();

        uint256 loanId = cachedPoolLoan.getCollateralLoanId(address(wrappedPunks), punkIndex);
        if (loanId != 0) {
            return;
        }

        address owner = punks.punkIndexToAddress(punkIndex);
        require(owner == _msgSender(), "PunkPool: not owner of punkIndex");

        punks.buyPunk(punkIndex);
        punks.transferPunk(proxy, punkIndex);

        wrappedPunks.mint(punkIndex);
    }

    function borrow(
        address reserveAsset,
        uint256 amount,
        uint256 punkIndex,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant {
        ILendPool cachedPool = _getLendPool();

        _depositPunk(punkIndex);

        cachedPool.borrow(reserveAsset, amount, address(wrappedPunks), punkIndex, onBehalfOf, referralCode);
        IERC20Upgradeable(reserveAsset).transfer(onBehalfOf, amount);
    }

    function batchBorrow(
        address[] calldata reserveAssets,
        uint256[] calldata amounts,
        uint256[] calldata punkIndexs,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant {
        require(punkIndexs.length == reserveAssets.length, "inconsistent reserveAssets length");
        require(punkIndexs.length == amounts.length, "inconsistent amounts length");

        ILendPool cachedPool = _getLendPool();

        for (uint256 i = 0; i < punkIndexs.length; i++) {
            _depositPunk(punkIndexs[i]);

            cachedPool.borrow(reserveAssets[i], amounts[i], address(wrappedPunks), punkIndexs[i], onBehalfOf, referralCode);

            IERC20Upgradeable(reserveAssets[i]).transfer(onBehalfOf, amounts[i]);
        }
    }

    function _withdrawPunk(uint256 punkIndex, address onBehalfOf) internal {
        address owner = wrappedPunks.ownerOf(punkIndex);
        require(owner == _msgSender(), "PunkPool: caller is not owner");
        require(owner == onBehalfOf, "PunkPool: onBehalfOf is not owner");

        wrappedPunks.safeTransferFrom(onBehalfOf, address(this), punkIndex);
        wrappedPunks.burn(punkIndex);
        punks.transferPunk(onBehalfOf, punkIndex);
    }

    function repay(uint256 punkIndex, uint256 amount) external override nonReentrant returns (uint256, bool) {
        return _repay(punkIndex, amount);
    }

    function batchRepay(uint256[] calldata punkIndexs, uint256[] calldata amounts)
    external
    override
    nonReentrant
    returns (uint256[] memory, bool[] memory)
    {
        require(punkIndexs.length == amounts.length, "inconsistent amounts length");

        uint256[] memory repayAmounts = new uint256[](punkIndexs.length);
        bool[] memory repayAlls = new bool[](punkIndexs.length);

        for (uint256 i = 0; i < punkIndexs.length; i++) {
            (repayAmounts[i], repayAlls[i]) = _repay(punkIndexs[i], amounts[i]);
        }

        return (repayAmounts, repayAlls);
    }

    function _repay(uint256 punkIndex, uint256 amount) internal returns (uint256, bool) {
        ILendPool cachedPool = _getLendPool();
        ILoanPool cachedPoolLoan = _getLendPoolLoan();

        uint256 loanId = cachedPoolLoan.getCollateralLoanId(address(wrappedPunks), punkIndex);
        require(loanId != 0, "PunkPool: no loan with such punkIndex");
        (, , address reserve, ) = cachedPoolLoan.getLoanCollateralAndReserve(loanId);
        (, uint256 debt) = cachedPoolLoan.getLoanReserveBorrowAmount(loanId);
        address borrower = cachedPoolLoan.borrowerOf(loanId);

        if (amount > debt) {
            amount = debt;
        }

        IERC20Upgradeable(reserve).transferFrom(msg.sender, address(this), amount);

        (uint256 paybackAmount, bool burn) = cachedPool.repay(address(wrappedPunks), punkIndex, amount);

        if (burn) {
            require(borrower == _msgSender(), "PunkPool: caller is not borrower");
            _withdrawPunk(punkIndex, borrower);
        }

        return (paybackAmount, burn);
    }

    function auction(
        uint256 punkIndex,
        uint256 bidPrice,
        address onBehalfOf
    ) external override nonReentrant {
        ILendPool cachedPool = _getLendPool();
        ILoanPool cachedPoolLoan = _getLendPoolLoan();

        uint256 loanId = cachedPoolLoan.getCollateralLoanId(address(wrappedPunks), punkIndex);
        require(loanId != 0, "PunkPool: no loan with such punkIndex");

        (, , address reserve, ) = cachedPoolLoan.getLoanCollateralAndReserve(loanId);

        IERC20Upgradeable(reserve).transferFrom(msg.sender, address(this), bidPrice);

        cachedPool.auction(address(wrappedPunks), punkIndex, bidPrice, onBehalfOf);
    }



    function liquidate(uint256 punkIndex, uint256 amount) external override nonReentrant returns (uint256) {
        ILendPool cachedPool = _getLendPool();
        ILoanPool cachedPoolLoan = _getLendPoolLoan();

        uint256 loanId = cachedPoolLoan.getCollateralLoanId(address(wrappedPunks), punkIndex);
        require(loanId != 0, "PunkPool: no loan with such punkIndex");

        DataTypes.LoanData memory loan = cachedPoolLoan.getLoan(loanId);
        require(loan.bidderAddress == _msgSender(), "PunkPool: caller is not bidder");

        if (amount > 0) {
            IERC20Upgradeable(loan.reserveAsset).transferFrom(msg.sender, address(this), amount);
        }

        uint256 extraRetAmount = cachedPool.liquidate(address(wrappedPunks), punkIndex, amount);

        _withdrawPunk(punkIndex, loan.bidderAddress);

        if (amount > extraRetAmount) {
            IERC20Upgradeable(loan.reserveAsset).safeTransfer(msg.sender, (amount - extraRetAmount));
        }

        return (extraRetAmount);
    }

    function borrowETH(
        uint256 amount,
        uint256 punkIndex,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant {
        _depositPunk(punkIndex);
        _capitalPool.borrowETH(amount, address(wrappedPunks), punkIndex, onBehalfOf, referralCode);
    }

    function batchBorrowETH(
        uint256[] calldata amounts,
        uint256[] calldata punkIndexs,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant {
        require(punkIndexs.length == amounts.length, "inconsistent amounts length");

        address[] memory nftAssets = new address[](punkIndexs.length);
        for (uint256 i = 0; i < punkIndexs.length; i++) {
            nftAssets[i] = address(wrappedPunks);
            _depositPunk(punkIndexs[i]);
        }

        _capitalPool.batchBorrowETH(amounts, nftAssets, punkIndexs, onBehalfOf, referralCode);
    }


    function borrowWETH(
        uint256 amount,
        uint256 punkIndex,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant {
        _depositPunk(punkIndex);
        _capitalPool.borrowWETH(amount, address(wrappedPunks), punkIndex, onBehalfOf, referralCode);
    }

    function batchBorrowWETH(
        uint256[] calldata amounts,
        uint256[] calldata punkIndexs,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant {
        require(punkIndexs.length == amounts.length, "inconsistent amounts length");

        address[] memory nftAssets = new address[](punkIndexs.length);
        for (uint256 i = 0; i < punkIndexs.length; i++) {
            nftAssets[i] = address(wrappedPunks);
            _depositPunk(punkIndexs[i]);
        }

        _capitalPool.batchBorrowWETH(amounts, nftAssets, punkIndexs, onBehalfOf, referralCode);
    }

    function repayETH(uint256 punkIndex, uint256 amount) external payable override nonReentrant returns (uint256, bool) {
        (uint256 paybackAmount, bool burn) = _repayETH(punkIndex, amount, 0);

        // refund remaining dust eth
        if (msg.value > paybackAmount) {
            _safeTransferETH(msg.sender, msg.value - paybackAmount);
        }

        return (paybackAmount, burn);
    }

    function batchRepayETH(uint256[] calldata punkIndexs, uint256[] calldata amounts)
    external
    payable
    override
    nonReentrant
    returns (uint256[] memory, bool[] memory)
    {
        require(punkIndexs.length == amounts.length, "inconsistent amounts length");

        uint256[] memory repayAmounts = new uint256[](punkIndexs.length);
        bool[] memory repayAlls = new bool[](punkIndexs.length);
        uint256 allRepayAmount = 0;

        for (uint256 i = 0; i < punkIndexs.length; i++) {
            (repayAmounts[i], repayAlls[i]) = _repayETH(punkIndexs[i], amounts[i], allRepayAmount);
            allRepayAmount += repayAmounts[i];
        }

        // refund remaining dust eth
        if (msg.value > allRepayAmount) {
            _safeTransferETH(msg.sender, msg.value - allRepayAmount);
        }

        return (repayAmounts, repayAlls);
    }

    function _repayETH(
        uint256 punkIndex,
        uint256 amount,
        uint256 accAmount
    ) internal returns (uint256, bool) {
        ILoanPool cachedPoolLoan = _getLendPoolLoan();

        uint256 loanId = cachedPoolLoan.getCollateralLoanId(address(wrappedPunks), punkIndex);
        require(loanId != 0, "PunkPool: no loan with such punkIndex");

        address borrower = cachedPoolLoan.borrowerOf(loanId);
        require(borrower == _msgSender(), "PunkPool: caller is not borrower");

        (, uint256 repayDebtAmount) = cachedPoolLoan.getLoanReserveBorrowAmount(loanId);
        if (amount < repayDebtAmount) {
            repayDebtAmount = amount;
        }

        require(msg.value >= (accAmount + repayDebtAmount), "msg.value is less than repay amount");

        (uint256 paybackAmount, bool burn) = _capitalPool.repayETH{value: repayDebtAmount}(
            address(wrappedPunks),
            punkIndex,
            amount
        );

        if (burn) {
            _withdrawPunk(punkIndex, borrower);
        }

        return (paybackAmount, burn);
    }

    function auctionETH(uint256 punkIndex, address onBehalfOf) external payable override nonReentrant {
        _capitalPool.auctionETH{value: msg.value}(address(wrappedPunks), punkIndex, onBehalfOf);
    }


    function liquidateETH(uint256 punkIndex) external payable override nonReentrant returns (uint256) {
        ILoanPool cachedPoolLoan = _getLendPoolLoan();

        uint256 loanId = cachedPoolLoan.getCollateralLoanId(address(wrappedPunks), punkIndex);
        require(loanId != 0, "PunkPool: no loan with such punkIndex");

        DataTypes.LoanData memory loan = cachedPoolLoan.getLoan(loanId);
        require(loan.bidderAddress == _msgSender(), "PunkPool: caller is not bidder");

        uint256 extraAmount = _capitalPool.liquidateETH{value: msg.value}(address(wrappedPunks), punkIndex);

        _withdrawPunk(punkIndex, loan.bidderAddress);

        // refund remaining dust eth
        if (msg.value > extraAmount) {
            _safeTransferETH(msg.sender, msg.value - extraAmount);
        }

        return extraAmount;
    }

    /**
     * @dev transfer ETH to an address, revert if it fails.
   * @param to recipient of the transfer
   * @param value the amount to send
   */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }

    /**
     * @dev
   */
    receive() external payable {}


}