// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {ICTokensAndCNFTsHelper} from "./interfaces/ICTokensAndCNFTsHelper.sol";
import {LendPoolConfigurator} from "./LendPoolConfigurator.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract CTokensAndCNFTsHelper is ICTokensAndCNFTsHelper{
    IAddressesProvider public addressesProvider;
    address public admin;
    constructor(address _addressesProvider) {
        addressesProvider = IAddressesProvider(_addressesProvider);
        admin = msg.sender;
    }

    function configureReserves(ConfigureReserveInput[] calldata inputParams)external override onlyAdmin{
        LendPoolConfigurator configurator = LendPoolConfigurator(
            addressesProvider.getLendPoolConfigurator()
        );
        for (uint256 i = 0; i < inputParams.length; i++) {
            if (inputParams[i].borrowingEnabled) {
                configurator.enableBorrowingOnReserve(inputParams[i].asset);
            }
            configurator.setReserveFactor(
                inputParams[i].asset,
                inputParams[i].reserveFactor
            );
        }
    }

    function configureNfts(ConfigureNftInput[] calldata inputParams)external override onlyAdmin{
        LendPoolConfigurator configurator = LendPoolConfigurator(
            addressesProvider.getLendPoolConfigurator()
        );
        for (uint256 i = 0; i < inputParams.length; i++) {
            configurator.configureNftAsCollateral(
                inputParams[i].asset,
                inputParams[i].baseLTV,
                inputParams[i].liquidationThreshold,
                inputParams[i].startIndex,
                inputParams[i].endIndex
            );
        }
    }



    function setAdmin(address _admin) external override onlyManager {
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "CTokensAndCNFTsHelper: !admin");
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
        return addressesProvider.getManage();
    }

}
