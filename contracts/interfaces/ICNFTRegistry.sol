// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

interface ICNFTRegistry {
    event Initialized(
        address genericImpl,
        string namePrefix,
        string symbolPrefix
    );
    event GenericImplementationUpdated(address genericImpl);
    event CNFTCreated(
        address indexed nftAsset,
        address cNftImpl,
        address cNftProxy,
        uint256 totals
    );
    event CNFTUpgraded(
        address indexed nftAsset,
        address cNftImpl,
        address cNftProxy,
        uint256 totals
    );
    event CustomSymbolsAdded(address[] nftAssets, string[] symbols);
    event ClaimAdminUpdated(address oldAdmin, address newAdmin);

    function getCNFTAddresses(address nftAsset)
        external
        view
        returns (address cNftProxy, address cNftImpl);

    function getCNFTAddressesByIndex(uint16 index)
        external
        view
        returns (address cNftProxy, address cNftImpl);

    function getCNFTAssetList() external view returns (address[] memory);

    function allCNFTAssetLength() external view returns (uint256);

    function initialize(
        address addressProvider,
        address genericImpl,
        string memory namePrefix_,
        string memory symbolPrefix_
    ) external;

    function setCNFTGenericImpl(address genericImpl) external;

    /**
     * @dev Create CNFT proxy and implement, then initialize it
     * @param nftAsset The address of the underlying asset of the CNFT
     **/
    function createCNFT(address nftAsset) external returns (address cNftProxy);

    /**
     * @dev Create cNft proxy with already deployed implement, then initialize it
     * @param nftAsset The address of the underlying asset of the CNFT
     * @param cNftImpl The address of the deployed implement of the CNFT
     **/
    function createCNFTWithImpl(address nftAsset, address cNftImpl)
        external
        returns (address cNftProxy);

    /**
     * @dev Update cNft proxy to an new deployed implement, then initialize it
     * @param nftAsset The address of the underlying asset of the CNFT
     * @param cNftImpl The address of the deployed implement of the CNFT
     * @param encodedCallData The encoded function call.
     **/
    function upgradeCNFTWithImpl(
        address nftAsset,
        address cNftImpl,
        bytes memory encodedCallData
    ) external;

    /**
     * @dev Adding custom symbol for some special NFTs like CryptoPunks
     * @param nftAssets_ The addresses of the NFTs
     * @param symbols_ The custom symbols of the NFTs
     **/
    function addCustomeSymbols(
        address[] memory nftAssets_,
        string[] memory symbols_
    ) external;

    function setAdmin(address newAdmin) external;
}
