// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {INFTOracle} from "./interfaces/INFTOracle.sol";
import {BlockContext} from "./utils/BlockContext.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {IESM} from "./interfaces/IESM.sol";
import {IConfigurator} from "./interfaces/IConfigurator.sol";

contract NFTOracle is INFTOracle, Initializable, BlockContext {
    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);
    event FeedAdminUpdated(address indexed admin);
    event SetAssetData(address indexed asset, uint256 price);

    address public priceFeedAdmin;

    // key is nft contract address
    mapping(address => NFTPriceFeed) public nftPriceFeedMap;
    address[] public nftPriceFeedKeys;

    // data validity check parameters
    uint256 private constant DECIMAL_PRECISION = 10 ** 18;
    // Maximum deviation allowed between two consecutive oracle prices. 18-digit precision.
    uint256 public maxPriceDeviation; // 20%,18-digit precision. 最大价格偏差
    // The maximum allowed deviation between two consecutive oracle prices within a certain time frame. 18-bit precision.
    uint256 public maxPriceDeviationWithTime; // 10%
    uint256 public timeIntervalWithPrice; // 30 minutes
    uint256 public minimumUpdateTime; // 10 minutes
    IAddressesProvider internal _addressProvider;

    mapping(address => bool) internal _nftPaused;

    modifier whenNotPaused(address _nftContract) {
        _whenNotPaused(_nftContract);
        _;
    }

    function _whenNotPaused(address _nftContract) internal view {
        IESM esm = IESM(_addressProvider.getESM());
        require(esm.isSwitchPaused(8), Errors.ORACLE_PAUSED);
        bool _paused = _nftPaused[_nftContract];
        require(!_paused, "NFTOracle: nft price feed paused");
    }

    modifier onlyAdmin() {
        require(msg.sender == priceFeedAdmin, "NFTOracle: !admin");
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

    function initialize(
        address _admin,
        uint256 _maxPriceDeviation,
        uint256 _maxPriceDeviationWithTime,
        uint256 _timeIntervalWithPrice,
        uint256 _minimumUpdateTime,
        address addressProvider
    ) public initializer {
        priceFeedAdmin = _admin;
        maxPriceDeviation = _maxPriceDeviation;
        maxPriceDeviationWithTime = _maxPriceDeviationWithTime;
        timeIntervalWithPrice = _timeIntervalWithPrice;
        minimumUpdateTime = _minimumUpdateTime;
        _addressProvider = IAddressesProvider(addressProvider);
    }

    function setPriceFeedAdmin(address _admin) external override onlyManager {
        priceFeedAdmin = _admin;
        emit FeedAdminUpdated(_admin);
    }

    function setAssets(address[] calldata _nftContracts) external onlyAdmin {
        for (uint256 i = 0; i < _nftContracts.length; i++) {
            _addAsset(_nftContracts[i]);
        }
    }

    function addAsset(address _nftContract) external onlyAdmin {
        _addAsset(_nftContract);
    }

    function _addAsset(address _nftContract) internal {
        requireKeyExisted(_nftContract, false);
        nftPriceFeedMap[_nftContract].registered = true;
        nftPriceFeedKeys.push(_nftContract);
        emit AssetAdded(_nftContract);
    }

    function removeAsset(address _nftContract) external onlyAdmin {
        requireKeyExisted(_nftContract, true);
        delete nftPriceFeedMap[_nftContract];

        uint256 length = nftPriceFeedKeys.length;
        for (uint256 i = 0; i < length; i++) {
            if (nftPriceFeedKeys[i] == _nftContract) {
                nftPriceFeedKeys[i] = nftPriceFeedKeys[length - 1];
                nftPriceFeedKeys.pop();
                break;
            }
        }
        emit AssetRemoved(_nftContract);
    }

    function setAssetData(address _nftContract, uint256 _price)
    public
    override
    onlyAdmin
    whenNotPaused(_nftContract)
    {
        requireKeyExisted(_nftContract, true);
        uint256 _timestamp = _blockTimestamp();
        require(
            _timestamp > getLatestTimestamp(_nftContract),
            "NFTOracle: incorrect timestamp"
        );
        require(_price > 0, "NFTOracle: price can not be 0");
        bool dataValidity = checkValidityOfPrice(
            _nftContract,
            _price,
            _timestamp
        );
        require(dataValidity, "NFTOracle: invalid price data");
        uint256 roundId;
        roundId = getLatestRoundId(_nftContract) + 1;
        NFTPriceData memory data = NFTPriceData({
        price : _price,
        timestamp : _timestamp,
        roundId : roundId
        });
        nftPriceFeedMap[_nftContract].nftPriceData.push(data);

        emit SetAssetData(_nftContract, _price);
    }

    function setAssetDatas(
        address[] calldata _nftContracts,
        uint256[] calldata _prices
    ) external override onlyAdmin {
        for (uint256 i = 0; i < _nftContracts.length; i++) {
            setAssetData(_nftContracts[i], _prices[i]);
        }
    }

    function getAssetDatas()
    external
    view
    override
    returns (
        address[] memory,
        uint256[] memory,
        uint256[] memory
    )
    {
        uint256[] memory nftPriceDatas = new uint256[](nftPriceFeedKeys.length);
        uint256[] memory roundIdDatas = new uint256[](nftPriceFeedKeys.length);
        for (uint256 i = 0; i < nftPriceFeedKeys.length; i++) {
            nftPriceDatas[i] = getAssetPrice(nftPriceFeedKeys[i]);
            roundIdDatas[i] = getLatestRoundId(nftPriceFeedKeys[i]);
        }
        return (nftPriceFeedKeys, nftPriceDatas, roundIdDatas);
    }

    function getAssetPrice(address _nftContract)
    public
    view
    override
    returns (uint256)
    {
        require(isExistedKey(_nftContract), "NFTOracle: key not existed");
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: no price data");
        return nftPriceFeedMap[_nftContract].nftPriceData[len - 1].price;
    }

    function getHighestPrice(address _nftContract)
    public
    view
    override
    returns (uint256)
    {
        uint256 highestPrice = getAssetPrice(_nftContract);
        require(isExistedKey(_nftContract), "NFTOracle: key not existed");
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: no price data");
        for (uint256 i = len; i > 0; i--) {
            if (
                _blockTimestamp() -
                nftPriceFeedMap[_nftContract].nftPriceData[i - 1].timestamp >
                IConfigurator(_addressProvider.getConfigurator()).bufferTime()
            ) {
                return highestPrice;
            }
            if (getPreviousPrice(_nftContract, i - 1) > highestPrice) {
                highestPrice = getPreviousPrice(_nftContract, i - 1);
            }
        }
        return highestPrice;
    }

    function getLatestTimestamp(address _nftContract)
    public
    view
    override
    returns (uint256)
    {
        require(isExistedKey(_nftContract), "NFTOracle: key not existed");
        uint256 len = getPriceFeedLength(_nftContract);
        if (len == 0) {
            return 0;
        }
        return nftPriceFeedMap[_nftContract].nftPriceData[len - 1].timestamp;
    }

    function getTwapPrice(address _nftContract, uint256 _interval)
    external
    view
    override
    returns (uint256)
    {
        require(isExistedKey(_nftContract), "NFTOracle: key not existed");
        require(_interval != 0, "NFTOracle: interval can't be 0");

        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: Not enough history");
        uint256 round = len - 1;
        NFTPriceData memory priceRecord = nftPriceFeedMap[_nftContract]
        .nftPriceData[round];
        uint256 latestTimestamp = priceRecord.timestamp;
        uint256 baseTimestamp = _blockTimestamp() - _interval;
        // if latest updated timestamp is earlier than target timestamp, return the latest price.
        if (latestTimestamp < baseTimestamp || round == 0) {
            return priceRecord.price;
        }

        // rounds are like snapshots, latestRound means the latest price snapshot. follow chainlink naming
        uint256 cumulativeTime = _blockTimestamp() - latestTimestamp;
        uint256 previousTimestamp = latestTimestamp;
        uint256 weightedPrice = priceRecord.price * cumulativeTime;
        while (true) {
            if (round == 0) {
                // if cumulative time is less than requested interval, return current twap price
                return weightedPrice / cumulativeTime;
            }

            round = round - 1;
            // get current round timestamp and price
            priceRecord = nftPriceFeedMap[_nftContract].nftPriceData[round];
            uint256 currentTimestamp = priceRecord.timestamp;
            uint256 price = priceRecord.price;

            // check if current round timestamp is earlier than target timestamp
            if (currentTimestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice =
                weightedPrice +
                (price * (previousTimestamp - baseTimestamp));
                break;
            }

            uint256 timeFraction = previousTimestamp - currentTimestamp;
            weightedPrice = weightedPrice + price * timeFraction;
            cumulativeTime = cumulativeTime + timeFraction;
            previousTimestamp = currentTimestamp;
        }
        return weightedPrice / _interval;
    }

    function getPreviousPrice(address _nftContract, uint256 _numOfRoundBack)
    public
    view
    override
    returns (uint256)
    {
        require(isExistedKey(_nftContract), "NFTOracle: key not existed");

        uint256 len = getPriceFeedLength(_nftContract);
        require(
            len > 0 && _numOfRoundBack < len,
            "NFTOracle: Not enough history"
        );
        return
        nftPriceFeedMap[_nftContract]
        .nftPriceData[len - _numOfRoundBack - 1]
        .price;
    }

    function getPreviousTimestamp(address _nftContract, uint256 _numOfRoundBack)
    public
    view
    override
    returns (uint256)
    {
        require(isExistedKey(_nftContract), "NFTOracle: key not existed");

        uint256 len = getPriceFeedLength(_nftContract);
        require(
            len > 0 && _numOfRoundBack < len,
            "NFTOracle: Not enough history"
        );
        return
        nftPriceFeedMap[_nftContract]
        .nftPriceData[len - _numOfRoundBack - 1]
        .timestamp;
    }

    function getPriceFeedLength(address _nftContract)
    public
    view
    returns (uint256 length)
    {
        return nftPriceFeedMap[_nftContract].nftPriceData.length;
    }

    function getLatestRoundId(address _nftContract)
    public
    view
    returns (uint256)
    {
        uint256 len = getPriceFeedLength(_nftContract);
        if (len == 0) {
            return 0;
        }
        return nftPriceFeedMap[_nftContract].nftPriceData[len - 1].roundId;
    }

    function isExistedKey(address _nftContract) private view returns (bool) {
        return nftPriceFeedMap[_nftContract].registered;
    }

    function requireKeyExisted(address _key, bool _existed) private view {
        if (_existed) {
            require(isExistedKey(_key), "NFTOracle: key not existed");
        } else {
            require(!isExistedKey(_key), "NFTOracle: key existed");
        }
    }

    function checkValidityOfPrice(
        address _nftContract,
        uint256 _price,
        uint256 _timestamp
    ) private view returns (bool) {
        uint256 len = getPriceFeedLength(_nftContract);
        if (len > 0) {
            uint256 price = nftPriceFeedMap[_nftContract]
            .nftPriceData[len - 1]
            .price;
            if (_price == price) {
                return true;
            }
            uint256 timestamp = nftPriceFeedMap[_nftContract]
            .nftPriceData[len - 1]
            .timestamp;
            uint256 percentDeviation;
            if (_price > price) {
                percentDeviation =
                ((_price - price) * DECIMAL_PRECISION) /
                price;
            } else {
                percentDeviation =
                ((price - _price) * DECIMAL_PRECISION) /
                price;
            }
            uint256 timeDeviation = _timestamp - timestamp;
            if (percentDeviation > maxPriceDeviation) {
                return false;
            } else if (timeDeviation < minimumUpdateTime) {
                return false;
            } else if (
                (percentDeviation > maxPriceDeviationWithTime) &&
                (timeDeviation < timeIntervalWithPrice)
            ) {
                return false;
            }
        }
        return true;
    }

    function setDataValidityParameters(
        uint256 _maxPriceDeviation,
        uint256 _maxPriceDeviationWithTime,
        uint256 _timeIntervalWithPrice,
        uint256 _minimumUpdateTime
    ) external onlyAdmin {
        maxPriceDeviation = _maxPriceDeviation;
        maxPriceDeviationWithTime = _maxPriceDeviationWithTime;
        timeIntervalWithPrice = _timeIntervalWithPrice;
        minimumUpdateTime = _minimumUpdateTime;
    }

    function setPause(address _nftContract, bool val)
    external
    override
    onlyAdmin
    {
        _nftPaused[_nftContract] = val;
    }

    function paused(address _nftContract)
    external
    view
    override
    returns (bool)
    {
        return _nftPaused[_nftContract];
    }
}
