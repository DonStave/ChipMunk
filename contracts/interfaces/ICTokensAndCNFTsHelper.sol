// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICTokensAndCNFTsHelper {
    struct ConfigureReserveInput {
        address asset;
        uint256 reserveFactor;
        bool borrowingEnabled;
    }

    struct ConfigureNftInput {
        address asset;
        uint256 baseLTV;
        uint256 liquidationThreshold;
        uint256 startIndex;
        uint256 endIndex;
    }

    function configureReserves(ConfigureReserveInput[] calldata inputParams) external;

    function configureNfts(ConfigureNftInput[] calldata inputParams)external;
    function setAdmin(address _admin) external;
}
