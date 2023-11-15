// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IESM} from "./interfaces/IESM.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ESM is IESM, Initializable {
    /// @notice Access depositETH pause
    uint256 public depositETHLive = 0;
    /// @notice Access withdrawETH pause
    uint256 public withdrawETHLive = 0;
    /// @notice Access stake pause
    uint256 public borrowETHLive = 0;
    /// @notice Access redeem pause
    uint256 public repayETHLive = 0;
    /// @notice Access claimReward pause
    uint256 public claimRewardLive = 0;
    /// @notice Access withdrawFromSPLive pause
    uint256 public auctionLive = 0;
    /// @notice Access liquidateLive pause
    uint256 public liquidateLive = 0;
    /// @notice Access oracle pause
    uint256 public oracleLive = 0;
    IAddressesProvider internal _addressProvider;

    function initialize(address addressProvider) public initializer {
        _addressProvider = IAddressesProvider(addressProvider);
    }

    /**
     * @dev Only Manage can call functions marked by this modifier
     **/
    modifier onlyManage() {
        require(msg.sender == _getManage(), Errors.CT_CALLER_MUST_BE_MANAGE);
        _;
    }

    function _getManage() internal view returns (address) {
        return _addressProvider.getManage();
    }

    /**
     * @notice Open Switch, if Switch is paused
     */
    function open(uint256 id) external override onlyManage {
        if (id == 0) {
            depositETHLive = 0;
            withdrawETHLive = 0;
            borrowETHLive = 0;
            repayETHLive = 0;
            claimRewardLive = 0;
            auctionLive = 0;
            oracleLive = 0;
            liquidateLive = 0;
        } else if (id == 1) {
            depositETHLive = 0;
        } else if (id == 2) {
            withdrawETHLive = 0;
        }  else if (id == 3) {
            borrowETHLive = 0;
        } else if (id == 4) {
            repayETHLive = 0;
        } else if (id == 5) {
            claimRewardLive = 0;
        } else if (id == 6) {
            auctionLive = 0;
        } else if (id == 7) {
            liquidateLive = 0;
        } else if (id == 8) {
            oracleLive = 0;
        }
        emit Open(id);
    }

    /**
     * @notice Paused Switch, if Switch opened
     */
    function pause(uint256 id) external override onlyManage {
        if (id == 0) {
            depositETHLive = 1;
            withdrawETHLive = 1;
            borrowETHLive = 1;
            repayETHLive = 1;
            claimRewardLive = 1;
            auctionLive = 1;
            oracleLive = 1;
            liquidateLive = 1;
        } else if (id == 1) {
            depositETHLive = 1;
        } else if (id == 2) {
            withdrawETHLive = 1;
        }  else if (id == 3) {
            borrowETHLive = 1;
        } else if (id == 4) {
            repayETHLive = 1;
        } else if (id == 5) {
            claimRewardLive = 1;
        } else if (id == 6) {
            auctionLive = 1;
        } else if (id == 7) {
            liquidateLive = 1;
        } else if (id == 8) {
            oracleLive = 1;
        }
        emit Pause(id);
    }

    /**
     * @notice Status of Switch
     * @param id ID
     */
    function isSwitchPaused(uint256 id) external view override returns (bool) {
        if (id == 1) {
            return depositETHLive == 0;
        } else if (id == 2) {
            return withdrawETHLive == 0;
        }  else if (id == 3) {
            return borrowETHLive == 0;
        } else if (id == 4) {
            return repayETHLive == 0;
        } else if (id == 5) {
            return claimRewardLive == 0;
        } else if (id == 6) {
            return auctionLive == 0;
        } else if (id == 7) {
            return liquidateLive == 0;
        } else if (id == 8) {
            return oracleLive == 0;
        }
        return false;
    }
}
