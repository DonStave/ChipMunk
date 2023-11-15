// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

/************
@title INFTOracle interface
@notice Interface for NFT price oracle.*/
interface INFTOracle {
    struct NFTPriceData {
        uint256 roundId;
        uint256 price;
        uint256 timestamp;
    }

    struct NFTPriceFeed {
        bool registered;
        NFTPriceData[] nftPriceData;
    }

    struct HighestPrice {
        uint256 highestPrice;
        uint256 timestamp;
    }

    /* CAUTION: Price uint is ETH based (WEI, 18 decimals) */
    // get latest price
    function getAssetPrice(address _asset) external view returns (uint256);

    function getHighestPrice(address _asset) external view returns (uint256);

    // get latest timestamp
    function getLatestTimestamp(address _asset) external view returns (uint256);

    // get previous price with _back rounds
    function getPreviousPrice(address _asset, uint256 _numOfRoundBack)
    external
    view
    returns (uint256);

    // get previous timestamp with _back rounds
    function getPreviousTimestamp(address _asset, uint256 _numOfRoundBack)
    external
    view
    returns (uint256);

    // get twap price depending on _period
    function getTwapPrice(address _asset, uint256 _interval)
    external
    view
    returns (uint256);

    function setAssetData(
        address _asset,
        uint256 _price
    ) external;

    function setPause(address _nftContract, bool val) external;

    function paused(address _nftContract) external view returns (bool);

    function setAssetDatas(
        address[] calldata _nftContracts,
        uint256[] calldata _prices
    ) external;

    function getAssetDatas()
    external
    view
    returns (address[] memory, uint256[] memory, uint256[] memory);


    function setPriceFeedAdmin(address _admin) external;
}
