// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {ICNFTRegistry} from "./interfaces/ICNFTRegistry.sol";
import {ICNFT} from "./interfaces/ICNFT.sol";
import {CNFTUpgradeableProxy} from "./libraries/proxy/CNFTUpgradeableProxy.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CNFTRegistry is ICNFTRegistry, Initializable {
    mapping(address => address) public cNFTProxys;
    mapping(address => address) public cNFTImpls;
    address[] public cNFTAssetLists;
    string public namePrefix;
    string public symbolPrefix;
    address public cNFTGenericImpl;
    mapping(address => string) public customSymbols;
    uint256 private constant _NOT_ENTERED = 0;
    uint256 private constant _ENTERED = 1;
    uint256 private _status;
    address private _claimAdmin;
    address public admin;
    IAddressesProvider internal _addressProvider;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Throws if called by any account other than the claim admin.
     */
    modifier onlyClaimAdmin() {
        require(
            claimAdmin() == msg.sender,
            "CNFT: caller is not the claim admin"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "!admin");
        _;
    }

    function getCNFTAddresses(address nftAsset)
    external
    view
    override
    returns (address cNFTProxy, address cNFTImpl)
    {
        cNFTProxy = cNFTProxys[nftAsset];
        cNFTImpl = cNFTImpls[nftAsset];
    }

    function getCNFTAddressesByIndex(uint16 index)
    external
    view
    override
    returns (address cNFTProxy, address cNFTImpl)
    {
        require(index < cNFTAssetLists.length, "CNFT: invalid index");
        cNFTProxy = cNFTProxys[cNFTAssetLists[index]];
        cNFTImpl = cNFTImpls[cNFTAssetLists[index]];
    }

    function getCNFTAssetList()
    external
    view
    override
    returns (address[] memory)
    {
        return cNFTAssetLists;
    }

    function allCNFTAssetLength() external view override returns (uint256) {
        return cNFTAssetLists.length;
    }

    function initialize(
        address addressProvider,
        address genericImpl,
        string memory namePrefix_,
        string memory symbolPrefix_
    ) external override  initializer {
        require(genericImpl != address(0), "CNFT: impl is zero address");

        cNFTGenericImpl = genericImpl;

        namePrefix = namePrefix_;
        symbolPrefix = symbolPrefix_;

        _setClaimAdmin(msg.sender);
        admin = msg.sender;
        _addressProvider = IAddressesProvider(addressProvider);

        emit Initialized(genericImpl, namePrefix, symbolPrefix);
    }

    /**
     * @dev See {ICNFTegistry-createCNFT}.
     */
    function createCNFT(address nftAsset)
    public
    override
    nonReentrant
    returns (address cNFTProxy)
    {
        _requireAddressIsERC721(nftAsset);
        require(cNFTProxys[nftAsset] == address(0), "CNFT: asset exist");
        require(cNFTGenericImpl != address(0), "CNFT: impl is zero address");

        cNFTProxy = _createProxyAndInitWithImpl(nftAsset, cNFTGenericImpl);

        emit CNFTCreated(
            nftAsset,
            cNFTImpls[nftAsset],
            cNFTProxy,
            cNFTAssetLists.length
        );
        return cNFTProxy;
    }

    /**
     * @dev See {ICNFTegistry-setCNFTGenericImpl}.
     */
    function setCNFTGenericImpl(address genericImpl)
    external
    override
    nonReentrant
    onlyAdmin
    {
        require(genericImpl != address(0), "CNFT: impl is zero address");
        cNFTGenericImpl = genericImpl;

        emit GenericImplementationUpdated(genericImpl);
    }

    /**
     * @dev See {ICNFTegistry-createCNFTWithImpl}.
     */
    function createCNFTWithImpl(address nftAsset, address cNFTImpl)
    external
    override
    nonReentrant
    onlyAdmin
    returns (address cNFTProxy)
    {
        _requireAddressIsERC721(nftAsset);
        require(cNFTImpl != address(0), "CNFT: implement is zero address");
        require(cNFTProxys[nftAsset] == address(0), "CNFT: asset exist");

        cNFTProxy = _createProxyAndInitWithImpl(nftAsset, cNFTImpl);

        emit CNFTCreated(
            nftAsset,
            cNFTImpls[nftAsset],
            cNFTProxy,
            cNFTAssetLists.length
        );

        return cNFTProxy;
    }

    /**
     * @dev See {ICNFTegistry-upgradeCNFTWithImpl}.
     */
    function upgradeCNFTWithImpl(
        address nftAsset,
        address cNFTImpl,
        bytes memory encodedCallData
    ) external override nonReentrant onlyAdmin {
        address cNFTProxy = cNFTProxys[nftAsset];
        require(cNFTProxy != address(0), "CNFT: asset nonexist");

        CNFTUpgradeableProxy proxy = CNFTUpgradeableProxy(payable(cNFTProxy));

        if (encodedCallData.length > 0) {
            proxy.upgradeToAndCall(cNFTImpl, encodedCallData);
        } else {
            proxy.upgradeTo(cNFTImpl);
        }

        cNFTImpls[nftAsset] = cNFTImpl;

        emit CNFTUpgraded(nftAsset, cNFTImpl, cNFTProxy, cNFTAssetLists.length);
    }

    /**
     * @dev See {ICNFTegistry-addCustomeSymbols}.
     */
    function addCustomeSymbols(address[] memory nftAssets_,string[] memory symbols_) external override nonReentrant onlyAdmin {
        require(
            nftAssets_.length == symbols_.length,
            "CNFT: inconsistent parameters"
        );

        for (uint256 i = 0; i < nftAssets_.length; i++) {
            customSymbols[nftAssets_[i]] = symbols_[i];
        }

        emit CustomSymbolsAdded(nftAssets_, symbols_);
    }

    /**
     * @dev Returns the address of the current claim admin.
     */
    function claimAdmin() public view virtual returns (address) {
        return _claimAdmin;
    }

    /**
     * @dev Set claim admin of the contract to a new account (`newAdmin`).
     * Can only be called by the current owner.
     */
    function setClaimAdmin(address newAdmin) public virtual onlyAdmin {
        require(newAdmin != address(0), "CNFT: new admin is the zero address");
        _setClaimAdmin(newAdmin);
    }

    function _setClaimAdmin(address newAdmin) internal virtual {
        address oldAdmin = _claimAdmin;
        _claimAdmin = newAdmin;
        emit ClaimAdminUpdated(oldAdmin, newAdmin);
    }

    function setAdmin(address newAdmin) external override{
        require(newAdmin != address(0), "CNFT: new admin is the zero address");
        require(msg.sender == _addressProvider.getManage(), Errors.CT_CALLER_MUST_BE_MANAGE);
        admin = newAdmin;
    }

    function _createProxyAndInitWithImpl(address nftAsset, address cNFTImpl)
    internal
    returns (address cNFTProxy)
    {
        bytes memory initParams = _buildInitParams(nftAsset);

        CNFTUpgradeableProxy proxy = new CNFTUpgradeableProxy(
            cNFTImpl,
            address(this),
            initParams
        );

        cNFTProxy = address(proxy);

        cNFTImpls[nftAsset] = cNFTImpl;
        cNFTProxys[nftAsset] = cNFTProxy;
        cNFTAssetLists.push(nftAsset);
    }

    function _buildInitParams(address nftAsset)
    internal
    view
    returns (bytes memory initParams)
    {
        string memory nftSymbol = customSymbols[nftAsset];
        if (bytes(nftSymbol).length == 0) {
            nftSymbol = IERC721MetadataUpgradeable(nftAsset).symbol();
        }
        string memory cNFTName = string(
            abi.encodePacked(namePrefix, " ", nftSymbol)
        );
        string memory cNFTSymbol = string(
            abi.encodePacked(symbolPrefix, nftSymbol)
        );

        initParams = abi.encodeWithSelector(
            ICNFT.initialize.selector,
            nftAsset,
            cNFTName,
            cNFTSymbol,
            admin,
            claimAdmin()
        );
    }

    function _requireAddressIsERC721(address nftAsset) internal view {
        require(nftAsset != address(0), "CNFT: asset is zero address");
        require(
            AddressUpgradeable.isContract(nftAsset),
            "CNFT: asset is not contract"
        );
    }
}
