// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title NftConfiguration library
 * @author CHIPMUNK
 * @notice Implements the bitmap logic to handle the NFT configuration
 */
library NftConfiguration {
    uint256 constant LTV_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
    uint256 constant LIQUIDATION_THRESHOLD_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
    uint256 constant ACTIVE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant FROZEN_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant AUCTION_DURATION_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant START_INDEX = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant END_INDEX = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

    /// @dev For the LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
    uint256 constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
    uint256 constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
    uint256 constant IS_ACTIVE_START_BIT_POSITION = 56;
    uint256 constant IS_FROZEN_START_BIT_POSITION = 57;
    uint256 constant AUCTION_DURATION_START_BIT_POSITION = 65;
    uint256 constant START_INDEX_BIT_POSITION = 81;
    uint256 constant END_INDEX_BIT_POSITION = 97;

    uint256 constant MAX_VALID_LTV = 65535;
    uint256 constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
    uint256 constant MAX_VALID_LIQUIDATION_BONUS = 65535;
    uint256 constant MAX_VALID_AUCTION_DURATION = 255;
    uint256 constant MAX_VALID_MIN_BIDFINE = 65535;

    /**
     * @dev Sets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @param ltv the new ltv
     **/
    function setLtv(DataTypes.NftConfigurationMap memory self, uint256 ltv) internal pure {
        require(ltv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & LTV_MASK) | ltv;
    }

    /**
     * @dev Gets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @return The loan to value
     **/
    function getLtv(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (uint256)
    {
        return self.data & ~LTV_MASK;
    }

    /**
     * @dev Sets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @param startIndex the new startIndex
     **/
    function setStartIndex(DataTypes.NftConfigurationMap memory self, uint256 startIndex)
    internal
    pure
    {
        self.data =
        (self.data & START_INDEX) |
        (startIndex << START_INDEX_BIT_POSITION);
    }

    /**
    * @dev Gets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @return The loan to value
     **/
    function getStartIndex(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (uint256)
    {
        return (self.data & ~START_INDEX) >> START_INDEX_BIT_POSITION;
    }


    /**
     * @dev Sets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @param endIndex the new endIndex
     **/
    function setEndIndex(DataTypes.NftConfigurationMap memory self, uint256 endIndex)
    internal
    pure
    {
        self.data =
        (self.data & END_INDEX) |
        (endIndex << END_INDEX_BIT_POSITION);
    }

    /**
    * @dev Gets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @return The loan to value
     **/
    function getEndIndex(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (uint256)
    {
        return (self.data & ~END_INDEX) >> END_INDEX_BIT_POSITION;
    }


    /**
     * @dev Sets the liquidation threshold of the NFT
     * @param self The NFT configuration
     * @param threshold The new liquidation threshold
     **/
    function setLiquidationThreshold(
        DataTypes.NftConfigurationMap memory self,
        uint256 threshold
    ) internal pure {
        require(
            threshold <= MAX_VALID_LIQUIDATION_THRESHOLD,
            Errors.RC_INVALID_LIQ_THRESHOLD
        );

        self.data =
        (self.data & LIQUIDATION_THRESHOLD_MASK) |
        (threshold << LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    /**
     * @dev Gets the liquidation threshold of the NFT
     * @param self The NFT configuration
     * @return The liquidation threshold
     **/
    function getLiquidationThreshold(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (uint256)
    {
        return
        (self.data & ~LIQUIDATION_THRESHOLD_MASK) >>
        LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }



    /**
     * @dev Sets the active state of the NFT
     * @param self The NFT configuration
     * @param active The active state
     **/
    function setActive(DataTypes.NftConfigurationMap memory self, bool active)
    internal
    pure
    {
        self.data =
        (self.data & ACTIVE_MASK) |
        (uint256(active ? 1 : 0) << IS_ACTIVE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the active state of the NFT
     * @param self The NFT configuration
     * @return The active state
     **/
    function getActive(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (bool)
    {
        return (self.data & ~ACTIVE_MASK) != 0;
    }

    /**
     * @dev Sets the frozen state of the NFT
     * @param self The NFT configuration
     * @param frozen The frozen state
     **/
    function setFrozen(DataTypes.NftConfigurationMap memory self, bool frozen)
    internal
    pure
    {
        self.data =
        (self.data & FROZEN_MASK) |
        (uint256(frozen ? 1 : 0) << IS_FROZEN_START_BIT_POSITION);
    }

    /**
     * @dev Gets the frozen state of the NFT
     * @param self The NFT configuration
     * @return The frozen state
     **/
    function getFrozen(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (bool)
    {
        return (self.data & ~FROZEN_MASK) != 0;
    }



    /**
     * @dev Sets the auction duration of the NFT
     * @param self The NFT configuration
     * @param auctionDuration The auction duration
     **/
    function setAuctionDuration(
        DataTypes.NftConfigurationMap memory self,
        uint256 auctionDuration
    ) internal pure {
        require(
            auctionDuration <= MAX_VALID_AUCTION_DURATION,
            Errors.RC_INVALID_AUCTION_DURATION
        );

        self.data =
        (self.data & AUCTION_DURATION_MASK) |
        (auctionDuration << AUCTION_DURATION_START_BIT_POSITION);
    }

    /**
     * @dev Gets the auction duration of the NFT
     * @param self The NFT configuration
     * @return The auction duration
     **/
    function getAuctionDuration(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (uint256)
    {
        return
        (self.data & ~AUCTION_DURATION_MASK) >>
        AUCTION_DURATION_START_BIT_POSITION;
    }

    /**
     * @dev Gets the configuration flags of the NFT
     * @param self The NFT configuration
     * @return The state flags representing active, frozen
     **/
    function getFlags(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (bool, bool)
    {
        uint256 dataLocal = self.data;

        return (
        (dataLocal & ~ACTIVE_MASK) != 0,
        (dataLocal & ~FROZEN_MASK) != 0
        );
    }

    /**
     * @dev Gets the configuration flags of the NFT from a memory object
     * @param self The NFT configuration
     * @return The state flags representing active, frozen
     **/
    function getFlagsMemory(DataTypes.NftConfigurationMap memory self)
    internal
    pure
    returns (bool, bool)
    {
        return (
        (self.data & ~ACTIVE_MASK) != 0,
        (self.data & ~FROZEN_MASK) != 0
        );
    }

    /**
     * @dev Gets the collateral configuration paramters of the NFT
     * @param self The NFT configuration
     * @return The state params representing ltv, liquidation threshold, liquidation bonus
     **/
    function getCollateralParams(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (
        uint256,
        uint256,
        uint256,
        uint256
    )
    {
        uint256 dataLocal = self.data;

        return (
        dataLocal & ~LTV_MASK,
        (dataLocal & ~LIQUIDATION_THRESHOLD_MASK) >>
        LIQUIDATION_THRESHOLD_START_BIT_POSITION,
        (dataLocal & ~START_INDEX) >> START_INDEX_BIT_POSITION,
        (dataLocal & ~END_INDEX) >> END_INDEX_BIT_POSITION
        );
    }

    /**
     * @dev Gets the auction configuration paramters of the NFT
     * @param self The NFT configuration
     **/
    function getAuctionParams(DataTypes.NftConfigurationMap storage self)
    internal
    view
    returns (
        uint256
    )
    {
        uint256 dataLocal = self.data;

        return (
        (dataLocal & ~AUCTION_DURATION_MASK) >>
        AUCTION_DURATION_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the collateral configuration paramters of the NFT from a memory object
     * @param self The NFT configuration
     * @return The state params representing ltv, liquidation threshold
     **/
    function getCollateralParamsMemory(
        DataTypes.NftConfigurationMap memory self
    )
    internal
    pure
    returns (
        uint256,
        uint256,
        uint256,
        uint256
    )
    {
        return (
        self.data & ~LTV_MASK,
        (self.data & ~LIQUIDATION_THRESHOLD_MASK) >>
        LIQUIDATION_THRESHOLD_START_BIT_POSITION,
        (self.data & ~START_INDEX) >> START_INDEX_BIT_POSITION,
        (self.data & ~END_INDEX) >> END_INDEX_BIT_POSITION
        );
    }


}
