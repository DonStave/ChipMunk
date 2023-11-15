// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ICNFT} from "./interfaces/ICNFT.sol";
import {ILoanPool} from "./interfaces/ILoanPool.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {Math} from "./libraries/math/Math.sol";

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract LoanPool is
Initializable,
ILoanPool,
ContextUpgradeable,
IERC721ReceiverUpgradeable
{
    using Math for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    IAddressesProvider private _addressesProvider;

    CountersUpgradeable.Counter private _loanIdTracker;

    mapping(uint256 => DataTypes.LoanData) private _loans;

    // nftAsset + nftTokenId => loanId
    mapping(address => mapping(uint256 => uint256)) private _nftToLoanIds;
    mapping(address => uint256) private _nftTotalCollateral;
    mapping(address => mapping(address => uint256)) private _userNftCollateral;
    mapping(address => uint256[]) private _userLoans;
    mapping(address => uint256[]) private _userAuctionedLoans;
    mapping(address => uint256[]) private _blackList;
    mapping(uint256 => bool) private _auctioned;
    uint256[] public effectiveLoan;
    uint256[] public auctionLoans;

    /**
     * @dev Only lending pool can call functions marked by this modifier
     **/
    modifier onlyLendPool() {
        require(
            _msgSender() == address(_getLendPool()),
            Errors.CT_CALLER_MUST_BE_LEND_POOL
        );
        _;
    }

    modifier onlyPoolAdmin() {
        require(
            _addressesProvider.getPoolAdmin() == msg.sender,
            Errors.CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    // called once by the factory at time of deployment
    function initialize(IAddressesProvider provider) external initializer {
        __Context_init();

        _addressesProvider = provider;

        // Avoid having loanId = 0
        _loanIdTracker.increment();

        emit Initialized(address(_getLendPool()));
    }

    function initNft(address nftAsset, address cNftAddress)
    external
    override
    onlyLendPool
    {
        IERC721Upgradeable(nftAsset).setApprovalForAll(cNftAddress, true);
    }

    /**
     * @inheritdoc ILoanPool
     */
    function createLoan(
        address initiator,
        address onBehalfOf,
        address nftAsset,
        uint256 nftTokenId,
        address cNftAddress,
        address reserveAsset,
        uint256 amount,
        uint256 borrowIndex
    ) external override onlyLendPool returns (uint256) {
        require(
            _nftToLoanIds[nftAsset][nftTokenId] == 0,
            Errors.LP_NFT_HAS_USED_AS_COLLATERAL
        );
        // index is expressed in Ray, so:
        // amount.wadToRay().rayDiv(index).rayToWad() => amount.rayDiv(index)
        uint256 amountScaled = amount.rayDiv(borrowIndex);

        uint256 loanId = _loanIdTracker.current();
        _loanIdTracker.increment();

        _nftToLoanIds[nftAsset][nftTokenId] = loanId;

        // transfer underlying NFT asset to pool and mint cNFT to onBehalfOf
        IERC721Upgradeable(nftAsset).safeTransferFrom(
            _msgSender(),
            address(this),
            nftTokenId
        );

        ICNFT(cNftAddress).mint(onBehalfOf, nftTokenId);

        // Save Info
        DataTypes.LoanData storage loanData = _loans[loanId];
        loanData.loanId = loanId;
        loanData.state = DataTypes.LoanState.Active;
        loanData.borrower = onBehalfOf;
        loanData.nftAsset = nftAsset;
        loanData.nftTokenId = nftTokenId;
        loanData.reserveAsset = reserveAsset;
        loanData.scaledAmount = amountScaled;

        _userNftCollateral[onBehalfOf][nftAsset] += 1;

        _nftTotalCollateral[nftAsset] += 1;

        uint256[] storage userLoan = _userLoans[loanData.borrower];
        userLoan.push(loanId);
        effectiveLoan.push(loanId);

        emit LoanCreated(
            initiator,
            onBehalfOf,
            loanId,
            nftAsset,
            nftTokenId,
            reserveAsset,
            amount,
            borrowIndex
        );

        return (loanId);
    }

    /**
     * @inheritdoc ILoanPool
     */
    function updateLoan(
        address initiator,
        uint256 loanId,
        uint256 amountAdded,
        uint256 amountTaken,
        uint256 borrowIndex,
        bool isLiquidate
    ) external override onlyLendPool {
        // Must use storage to change state
        DataTypes.LoanData storage loan = _loans[loanId];

        // Ensure valid loan state
        require(
            loan.state == DataTypes.LoanState.Active,
            Errors.LPL_INVALID_LOAN_STATE
        );

        uint256 amountScaled = 0;


        if (amountAdded > 0) {
            amountScaled = amountAdded.rayDiv(borrowIndex);
            require(amountScaled != 0, Errors.LPL_INVALID_LOAN_AMOUNT);
            loan.scaledAmount += amountScaled;
        }

        if (amountTaken > 0) {
            amountScaled = amountTaken.rayDiv(borrowIndex);
            require(amountScaled != 0, Errors.LPL_INVALID_TAKEN_AMOUNT);
            require(loan.scaledAmount >= amountScaled, Errors.LPL_AMOUNT_OVERFLOW);
            loan.isLiquidate = isLiquidate;
            loan.repayTime = block.timestamp;
            loan.scaledAmount -= amountScaled;
        }

        emit LoanUpdated(
            initiator,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            loan.reserveAsset,
            amountAdded,
            amountTaken,
            borrowIndex
        );
    }

    /**
     * @inheritdoc ILoanPool
     */
    function repayLoan(
        address initiator,
        uint256 loanId,
        address cNftAddress,
        uint256 amount,
        uint256 borrowIndex
    ) external override onlyLendPool {
        // Must use storage to change state
        DataTypes.LoanData storage loan = _loans[loanId];

        // Ensure valid loan state
        require(
            loan.state == DataTypes.LoanState.Active,
            Errors.LPL_INVALID_LOAN_STATE
        );

        // state changes and cleanup
        // NOTE: these must be performed before assets are released to prevent reentrance
        _loans[loanId].state = DataTypes.LoanState.Repaid;

        _nftToLoanIds[loan.nftAsset][loan.nftTokenId] = 0;

        require(
            _userNftCollateral[loan.borrower][loan.nftAsset] >= 1,
            Errors.LP_INVALIED_USER_NFT_AMOUNT
        );
        _userNftCollateral[loan.borrower][loan.nftAsset] -= 1;

        require(
            _nftTotalCollateral[loan.nftAsset] >= 1,
            Errors.LP_INVALIED_NFT_AMOUNT
        );
        _nftTotalCollateral[loan.nftAsset] -= 1;

        _removeUserLoan(loan.borrower, loanId);

        // burn cNft and transfer underlying NFT asset to user
        ICNFT(cNftAddress).burn(loan.nftTokenId);

        IERC721Upgradeable(loan.nftAsset).safeTransferFrom(
            address(this),
            _msgSender(),
            loan.nftTokenId
        );

        emit LoanRepaid(
            initiator,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            loan.reserveAsset,
            amount,
            borrowIndex
        );
    }

    /**
     * @inheritdoc ILoanPool
     */
    function auctionLoan(
        address initiator,
        uint256 loanId,
        address onBehalfOf,
        uint256 bidPrice,
        uint256 borrowAmount,
        uint256 borrowIndex
    ) external override onlyLendPool {
        // Must use storage to change state
        DataTypes.LoanData storage loan = _loans[loanId];
        address previousBidder = loan.bidderAddress;
        uint256 previousPrice = loan.bidPrice;

        // Ensure valid loan state
        if (loan.bidStartTimestamp == 0) {
            require(
                loan.state == DataTypes.LoanState.Active,
                Errors.LPL_INVALID_LOAN_STATE
            );

            loan.state = DataTypes.LoanState.Auction;

        } else {
            require(
                loan.state == DataTypes.LoanState.Auction,
                Errors.LPL_INVALID_LOAN_STATE
            );

            require(
                bidPrice > loan.bidPrice,
                Errors.LPL_BID_PRICE_LESS_THAN_HIGHEST_PRICE
            );
            _removeBidderLoan(loan.bidderAddress, loanId);
        }
        loan.bidStartTimestamp = block.timestamp;
        loan.bidBorrowAmount = borrowAmount;
        loan.bidderAddress = onBehalfOf;
        loan.bidPrice = bidPrice;
        loan.bidderAddresses.push(onBehalfOf);
        loan.bidTimestamps.push(block.timestamp);
        loan.bidPrices.push(bidPrice);

        uint256[] storage bidderLoan = _userAuctionedLoans[onBehalfOf];
        bidderLoan.push(loanId);
        _removeUserLoan(loan.borrower, loanId);
        if (!_auctioned[loanId]) {
            auctionLoans.push(loanId);
            _auctioned[loanId] = true;
        }
        emit LoanAuctioned(
            initiator,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            loan.bidBorrowAmount,
            borrowIndex,
            onBehalfOf,
            bidPrice,
            previousBidder,
            previousPrice
        );
    }

    /**
     * @inheritdoc ILoanPool
     */
    function availableAuctionLoan(
        uint256 loanId
    ) external override onlyLendPool {
        // Must use storage to change state
        DataTypes.LoanData storage loan = _loans[loanId];

        // Ensure valid loan state
        if (loan.bidStartTimestamp == 0) {
            require(
                loan.state == DataTypes.LoanState.Active,
                Errors.LPL_INVALID_LOAN_STATE
            );

            loan.state = DataTypes.LoanState.AvailableAuction;

        } else {
            require(
                loan.state == DataTypes.LoanState.Auction,
                Errors.LPL_INVALID_LOAN_STATE
            );
        }
    }

    /**
     * @inheritdoc ILoanPool
     */
    function liquidateLoan(
        address initiator,
        uint256 loanId,
        address cNftAddress,
        uint256 borrowAmount,
        uint256 borrowIndex
    ) external override onlyLendPool {
        // Must use storage to change state
        DataTypes.LoanData storage loan = _loans[loanId];

        // Ensure valid loan state
        require(
            loan.state == DataTypes.LoanState.Auction,
            Errors.LPL_INVALID_LOAN_STATE
        );

        // state changes and cleanup
        // NOTE: these must be performed before assets are released to prevent reentrance
        _loans[loanId].state = DataTypes.LoanState.Defaulted;
        _loans[loanId].bidBorrowAmount = borrowAmount;

        _nftToLoanIds[loan.nftAsset][loan.nftTokenId] = 0;

        require(
            _userNftCollateral[loan.borrower][loan.nftAsset] >= 1,
            Errors.LP_INVALIED_USER_NFT_AMOUNT
        );
        _userNftCollateral[loan.borrower][loan.nftAsset] -= 1;

        require(
            _nftTotalCollateral[loan.nftAsset] >= 1,
            Errors.LP_INVALIED_NFT_AMOUNT
        );
        _nftTotalCollateral[loan.nftAsset] -= 1;
        _removeBidderLoan(loan.bidderAddress, loanId);
        _removeAuctionLoans(loanId);
        // burn cNft and transfer underlying NFT asset to user
        ICNFT(cNftAddress).burn(loan.nftTokenId);

        IERC721Upgradeable(loan.nftAsset).safeTransferFrom(
            address(this),
            _msgSender(),
            loan.nftTokenId
        );

        emit LoanLiquidated(
            initiator,
            loanId,
            loan.nftAsset,
            loan.nftTokenId,
            loan.reserveAsset,
            borrowAmount,
            borrowIndex
        );
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function addBlackList(address _nftContract, uint256 _tokenId) external override onlyPoolAdmin {
        uint256[] storage blackList = _blackList[_nftContract];
        blackList.push(_tokenId);
        emit AddBlackList(_nftContract, _tokenId);
    }

    function getBlackList(address _nftContract) external view override returns (uint256[] memory){
        return _blackList[_nftContract];
    }

    function removeBlackList(address _nftContract, uint256 _tokenId) external override onlyPoolAdmin {
        uint256 length = _blackList[_nftContract].length;
        if (length < 1) {
            return;
        }
        for (uint256 i = 0; i < length; i++) {
            if (_blackList[_nftContract][i] == _tokenId) {
                _blackList[_nftContract][i] = _blackList[_nftContract][length - 1];
                _blackList[_nftContract].pop();
                break;
            }
        }
        emit RemoveBlackList(_nftContract, _tokenId);
    }

    function isBlackList(address _nftContract, uint256 _tokenId) external view override returns (bool) {
        uint256 length = _blackList[_nftContract].length;
        if (length < 1) {
            return false;
        }
        for (uint256 i = 0; i < length; i++) {
            if (_blackList[_nftContract][i] == _tokenId) {
                return true;
            }
        }
        return false;
    }


    function getBidRecord(uint256 loanId)
    external
    view
    override
    returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        return (_loans[loanId].bidderAddresses, _loans[loanId].bidTimestamps, _loans[loanId].bidPrices);
    }

    function borrowerOf(uint256 loanId)
    external
    view
    override
    returns (address)
    {
        return _loans[loanId].borrower;
    }

    function getCollateralLoanId(address nftAsset, uint256 nftTokenId)
    external
    view
    override
    returns (uint256)
    {
        return _nftToLoanIds[nftAsset][nftTokenId];
    }

    function getLoan(uint256 loanId)
    external
    view
    override
    returns (DataTypes.LoanData memory loanData)
    {
        return _loans[loanId];
    }

    function getUserLoan(address user)
    external
    view
    override
    returns (uint256[] memory loadIds)
    {
        return _userLoans[user];
    }

    function getBidderLoan(address bidder) external
    view
    override
    returns (uint256[] memory loadIds){
        return _userAuctionedLoans[bidder];
    }

    function getEffectiveLoan()
    external
    view
    override
    returns (uint256[] memory)
    {
        return effectiveLoan;
    }

    function getAuctionLoans()
    external
    view
    override
    returns (uint256[] memory)
    {
        return auctionLoans;
    }


    function getLoanCollateralAndReserve(uint256 loanId)
    external
    view
    override
    returns (
        address nftAsset,
        uint256 nftTokenId,
        address reserveAsset,
        uint256 scaledAmount
    )
    {
        return (
        _loans[loanId].nftAsset,
        _loans[loanId].nftTokenId,
        _loans[loanId].reserveAsset,
        _loans[loanId].scaledAmount
        );
    }

    function getLoanReserveBorrowAmount(uint256 loanId)
    external
    view
    override
    returns (address, uint256)
    {
        uint256 scaledAmount = _loans[loanId].scaledAmount;
        if (scaledAmount == 0) {
            return (_loans[loanId].reserveAsset, 0);
        }
        uint256 amount = scaledAmount.rayMul(
            _getLendPool().getReserveNormalizedVariableDebt(
                _loans[loanId].reserveAsset
            )
        );

        return (_loans[loanId].reserveAsset, amount);
    }

    function getLoanReserveBorrowScaledAmount(uint256 loanId)
    external
    view
    override
    returns (address, uint256)
    {
        return (_loans[loanId].reserveAsset, _loans[loanId].scaledAmount);
    }

    function getLoanHighestBid(uint256 loanId)
    external
    view
    override
    returns (address, uint256)
    {
        return (_loans[loanId].bidderAddress, _loans[loanId].bidPrice);
    }

    function getNftCollateralAmount(address nftAsset)
    external
    view
    override
    returns (uint256)
    {
        return _nftTotalCollateral[nftAsset];
    }

    function getNFTAuctioned(uint256 loanId)
    external
    view
    override
    returns (bool)
    {
        return _auctioned[loanId];
    }

    function getUserNftCollateralAmount(address user, address nftAsset)
    external
    view
    override
    returns (uint256)
    {
        return _userNftCollateral[user][nftAsset];
    }

    function _removeUserLoan(address user, uint256 loanId) private {
        uint256 length = _userLoans[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (_userLoans[user][i] == loanId) {
                _userLoans[user][i] = _userLoans[user][length - 1];
                _userLoans[user].pop();
                break;
            }
        }

        uint256 len = effectiveLoan.length;
        for (uint256 i = 0; i < len; i++) {
            if (effectiveLoan[i] == loanId) {
                effectiveLoan[i] = effectiveLoan[len - 1];
                effectiveLoan.pop();
                break;
            }
        }
    }

    function _removeBidderLoan(address user, uint256 loanId) private {
        uint256 length = _userAuctionedLoans[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (_userAuctionedLoans[user][i] == loanId) {
                _userAuctionedLoans[user][i] = _userAuctionedLoans[user][length - 1];
                _userAuctionedLoans[user].pop();
                break;
            }
        }
    }

    function _removeAuctionLoans(uint256 loanId) private {
        uint256 len = auctionLoans.length;
        for (uint256 i = 0; i < len; i++) {
            if (auctionLoans[i] == loanId) {
                auctionLoans[i] = auctionLoans[len - 1];
                auctionLoans.pop();
                break;
            }
        }
    }




    function _getLendPool() internal view returns (ILendPool) {
        return ILendPool(_addressesProvider.getLendPool());
    }
}
