// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

interface ICNFT {
    /**
     * @dev Emitted when an cNft is initialized
     * @param underlyingAsset_ The address of the underlying asset
     **/
    event Initialized(address indexed underlyingAsset_);

    /**
     * @dev Emitted when the ownership is transferred
     * @param oldOwner The address of the old owner
     * @param newOwner The address of the new owner
     **/
    event OwnershipTransferred(address oldOwner, address newOwner);

    /**
     * @dev Emitted when the claim admin is updated
     * @param oldAdmin The address of the old admin
     * @param newAdmin The address of the new admin
     **/
    event ClaimAdminUpdated(address oldAdmin, address newAdmin);

    /**
     * @dev Emitted on mint
     * @param user The address initiating the burn
     * @param nftAsset address of the underlying asset of NFT
     * @param nftTokenId token id of the underlying asset of NFT
     * @param owner The owner address receive the cNft token
     **/
    event Mint(
        address indexed user,
        address indexed nftAsset,
        uint256 nftTokenId,
        address indexed owner
    );

    /**
     * @dev Emitted on burn
     * @param user The address initiating the burn
     * @param nftAsset address of the underlying asset of NFT
     * @param nftTokenId token id of the underlying asset of NFT
     * @param owner The owner address of the burned cNft token
     **/
    event Burn(
        address indexed user,
        address indexed nftAsset,
        uint256 nftTokenId,
        address indexed owner
    );

    /**
     * @dev Emitted on flashLoan
     * @param target The address of the flash loan receiver contract
     * @param initiator The address initiating the flash loan
     * @param nftAsset address of the underlying asset of NFT
     * @param tokenId The token id of the asset being flash borrowed
     **/
    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed nftAsset,
        uint256 tokenId
    );

    event ClaimERC20Airdrop(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    event ClaimERC721Airdrop(
        address indexed token,
        address indexed to,
        uint256[] ids
    );

    event ClaimERC1155Airdrop(
        address indexed token,
        address indexed to,
        uint256[] ids,
        uint256[] amounts,
        bytes data
    );

    event ExecuteAirdrop(address indexed airdropContract);

    /**
     * @dev Initializes the cNft
     * @param underlyingAsset_ The address of the underlying asset of this cNft (E.g. PUNK for bPUNK)
     */
    function initialize(
        address underlyingAsset_,
        string calldata cNftName,
        string calldata cNftSymbol,
        address owner_,
        address claimAdmin_
    ) external;

    /**
     * @dev Mints cNft token to the user address
     *
     * Requirements:
     *  - The caller can be contract address and EOA.
     *  - `nftTokenId` must not exist.
     *
     * @param to The owner address receive the cNft token
     * @param tokenId token id of the underlying asset of NFT
     **/
    function mint(address to, uint256 tokenId) external;

    /**
     * @dev Burns user cNft token
     *
     * Requirements:
     *  - The caller can be contract address and EOA.
     *  - `tokenId` must exist.
     *
     * @param tokenId token id of the underlying asset of NFT
     **/
    function burn(uint256 tokenId) external;

    /**
     * @dev Allows smartcontracts to access the tokens within one transaction, as long as the tokens taken is returned.
     *
     * Requirements:
     *  - `nftTokenIds` must exist.
     *
     * @param receiverAddress The address of the contract receiving the tokens, implementing the IFlashLoanReceiver interface
     * @param nftTokenIds token ids of the underlying asset
     * @param params Variadic packed params to pass to the receiver as extra information
     */
    function flashLoan(
        address receiverAddress,
        uint256[] calldata nftTokenIds,
        bytes calldata params
    ) external;

    function claimERC20Airdrop(
        address token,
        address to,
        uint256 amount
    ) external;

    function claimERC721Airdrop(
        address token,
        address to,
        uint256[] calldata ids
    ) external;

    function claimERC1155Airdrop(
        address token,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    function executeAirdrop(
        address airdropContract,
        bytes calldata airdropParams
    ) external;

    /**
     * @dev Returns the owner of the `nftTokenId` token.
     *
     * Requirements:
     *  - `tokenId` must exist.
     *
     * @param tokenId token id of the underlying asset of NFT
     */
    function minterOf(uint256 tokenId) external view returns (address);

    /**
     * @dev Returns the address of the underlying asset.
     */
    function underlyingAsset() external view returns (address);

    /**
     * @dev Returns the contract-level metadata.
     */
    function contractURI() external view returns (string memory);
}
