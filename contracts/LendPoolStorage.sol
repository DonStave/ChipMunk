// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {DataTypes} from "./libraries/types/DataTypes.sol";
import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {NftLogic} from "./libraries/logic/NftLogic.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {IESM} from "./interfaces/IESM.sol";

contract LendPoolStorage {
    using ReserveLogic for DataTypes.ReserveData;
    using NftLogic for DataTypes.NftData;

    IAddressesProvider internal _addressesProvider;
    IESM internal esm;

    mapping(address => DataTypes.ReserveData) internal _reserves;
    mapping(address => DataTypes.NftData) internal _nfts;

    mapping(uint256 => address) internal _reservesList;
    uint256 internal _reservesCount;

    mapping(uint256 => address) internal _nftsList;
    uint256 internal _nftsCount;

    bool internal _paused;

    uint256 internal _maxNumberOfReserves;
    uint256 internal _maxNumberOfNfts;
}
