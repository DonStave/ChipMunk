// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title NftLogic library
 * @author ChipMunk
 * @notice Implements the logic to update the nft state
 */
library NftLogic {
    /**
     * @dev Initializes a nft
     * @param nft The nft object
     * @param cNftAddress The address of the cNft contract
     **/
    function init(DataTypes.NftData storage nft, address cNftAddress) external {
        require(
            nft.cNftAddress == address(0),
            Errors.RL_RESERVE_ALREADY_INITIALIZED
        );

        nft.cNftAddress = cNftAddress;
    }
}
