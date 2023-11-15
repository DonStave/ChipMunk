// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {ERC20Detailed} from "./interfaces/ERC20Detailed.sol";

/**
 * @notice implementation of the CHIPMUNK token contract
 * @author CHIPMUNK
 */
contract ChipMunkToken is ERC20Detailed {
    string internal constant NAME = "ChipMunk Token";
    string internal constant SYMBOL = "CHIPMUNK";
    uint8 internal constant DECIMALS = 18;

    function initialize(address misc, uint256 _amount) external initializer {
        __ERC20Detailed_init(NAME, SYMBOL, DECIMALS);
        _mint(misc, _amount);
    }
}