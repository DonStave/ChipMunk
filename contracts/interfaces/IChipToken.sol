// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IAddressesProvider} from "./IAddressesProvider.sol";
import {IIncentivesController} from "./IIncentivesController.sol";
import {IScaledBalanceToken} from "./IScaledBalanceToken.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IChipToken is
    IScaledBalanceToken,
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
{
    /**
     * @dev Emitted when an bToken is initialized
     * @param underlyingAsset The address of the underlying asset
     * @param pool The address of the associated lending pool
     * @param incentivesController The address of the incentives controller for this bToken
     **/
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        address incentivesController
    );

    /**
     * @dev Initializes the bToken
     * @param addressProvider The address of the address provider where this bToken will be used
     * @param underlyingAsset The address of the underlying asset of this bToken
     */
    function initialize(
        IAddressesProvider addressProvider,
        address underlyingAsset,
        uint8 bTokenDecimals,
        string calldata bTokenName,
        string calldata bTokenSymbol
    ) external;

    /**
     * @dev Emitted after the mint action
     * @param from The address performing the mint
     * @param value The amount being
     * @param index The new liquidity index of the reserve
     **/
    event Mint(address indexed from, uint256 value, uint256 index);

    /**
     * @dev Mints `amount` bTokens to `user`
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve 新的储备流动性指数
     * @return `true` if the the previous balance of the user was 0 `true` 如果用户之前的余额为 0
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external returns (bool);

    /**
     * @dev Emitted after bTokens are burned
     * @param from The owner of the bTokens, getting them burned
     * @param target The address that will receive the underlying
     * @param value The amount being burned
     * @param index The new liquidity index of the reserve
     **/
    event Burn(
        address indexed from,
        address indexed target,
        uint256 value,
        uint256 index
    );

    /**
     * @dev Emitted during the transfer action
     * @param from The user whose tokens are being transferred
     * @param to The recipient
     * @param value The amount being transferred
     * @param index The new liquidity index of the reserve
     **/
    event BalanceTransfer(
        address indexed from,
        address indexed to,
        uint256 value,
        uint256 index
    );

    /**
     * @dev Burns bTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * @param user The owner of the bTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     **/
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external;

    /**
     * @dev Mints bTokens to the reserve treasury
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     */
    function mintToTreasury(uint256 amount, uint256 index) external;

    /**
     * @dev Transfers the underlying asset to `target`. Used by the LendPool to transfer
     * assets in borrow(), withdraw()
     * @param user The recipient of the underlying
     * @param amount The amount getting transferred
     * @return The amount transferred
     **/
    function transferUnderlyingTo(address user, uint256 amount)
        external
        returns (uint256);

    /**
     * @dev Returns the address of the incentives controller contract
     **/
    function getIncentivesController()
        external
        view
        returns (IIncentivesController);

    /**
     * @dev Returns the address of the underlying asset of this bToken
     **/
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
