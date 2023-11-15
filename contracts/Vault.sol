// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IVault} from "./interfaces/IVault.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @title Vault
 * @notice Stores all the CHIPMUNK kept for incentives, just giving approval to the different
 * systems that will pull CHIPMUNK funds for their specific use case
 * @author CHIPMUNK
 **/
contract Vault is Initializable, IVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public chipToken;
    IAddressesProvider public _addressProvider;

    function initialize(address _token,address addressProvider) external initializer {
        chipToken = _token;
        _addressProvider = IAddressesProvider(addressProvider);
    }

    function approve(address recipient, uint256 amount)
    external
    override
    onlyManager
    {
        IERC20Upgradeable(chipToken).safeApprove(recipient, amount);
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
}
