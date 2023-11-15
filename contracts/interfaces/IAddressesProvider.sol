// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IAddressesProvider {
    event LendPoolUpdated(address indexed newAddress, bytes encodedCallData);
    event ConfigurationAdminUpdated(address indexed newAddress);
    event ManageUpdated(address manage);
    event EmergencyAdminUpdated(address indexed newAddress);
    event LendPoolConfiguratorUpdated(
        address indexed newAddress,
        bytes encodedCallData
    );
    event ReserveOracleUpdated(address indexed newAddress);
    event NftOracleUpdated(address indexed newAddress);
    event LendPoolLoanUpdated(
        address indexed newAddress,
        bytes encodedCallData
    );
    event ProxyCreated(bytes32 id, address indexed newAddress);
    event AddressSet(
        bytes32 id,
        address indexed newAddress,
        bool hasProxy,
        bytes encodedCallData
    );
    event CNFTRegistryUpdated(address indexed newAddress);
    event LendPoolLiquidatorUpdated(address indexed newAddress);
    event IncentivesControllerUpdated(address indexed newAddress);
    event UIDataProviderUpdated(address indexed newAddress);
    event DataProviderUpdated(address indexed newAddress);


    function setAddress(bytes32 id, address newAddress) external;

    function setAddressAsProxy(
        bytes32 id,
        address impl,
        bytes memory encodedCallData
    ) external;

    function getAddress(bytes32 id) external view returns (address);

    function getManage() external view returns (address);

    function getConfigurator() external view returns (address);

    function getESM() external view returns (address);

    function getLendPool() external view returns (address);

    function setLendPoolImpl(address pool, bytes memory encodedCallData)
    external;

    function getLendPoolConfigurator() external view returns (address);

    function setLendPoolConfiguratorImpl(
        address configurator,
        bytes memory encodedCallData
    ) external;

    function getPoolAdmin() external view returns (address);

    function getCapitalPool() external view returns (address);

    function getCTokensAndCNFTsHelper() external view returns (address);

    function getVault() external view returns (address);

    function setPoolAdmin(address admin) external;

    function setManage(address manage) external;

    function getEmergencyAdmin() external view returns (address);

    function setEmergencyAdmin(address admin) external;

    function getReserveOracle() external view returns (address);

    function setReserveOracle(address reserveOracle) external;

    function getNFTOracle() external view returns (address);

    function setNFTOracle(address nftOracle) external;

    function getLendPoolLoan() external view returns (address);

    function setLendPoolLoanImpl(address loan, bytes memory encodedCallData)
    external;

    function getCNFTRegistry() external view returns (address);

    function setCNFTRegistry(address factory) external;

    function getIncentivesController() external view returns (address);

    function setIncentivesController(address controller) external;

    function getUIDataProvider() external view returns (address);

    function setUIDataProvider(address provider) external;

    function getDataProvider() external view returns (address);

    function setDataProvider(address provider) external;

}
