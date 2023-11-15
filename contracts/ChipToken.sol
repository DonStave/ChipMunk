// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

import {IAddressesProvider} from "./interfaces/IAddressesProvider.sol";
import {ILendPoolConfigurator} from "./interfaces/ILendPoolConfigurator.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {IChipToken} from "./interfaces/IChipToken.sol";
import {Math} from "./libraries/math/Math.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IESM} from "./interfaces/IESM.sol";
import {IConfigurator} from "./interfaces/IConfigurator.sol";

import {IncentivizedERC20} from "./IncentivizedERC20.sol";
import {IIncentivesController} from "./ProtocolIncentivesController.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


/**
 * @title ERC20 CToken
 * @dev Implementation of the interest bearing token
 */
contract ChipToken is Initializable, IChipToken, IncentivizedERC20 {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IAddressesProvider internal _addressProvider;
    address internal _underlyingAsset;

    modifier onlyLendPool() {
        require(
            _msgSender() == address(_getLendPool()),
            Errors.CT_CALLER_MUST_BE_LEND_POOL
        );
        _;
    }

    modifier onlyLendPoolConfigurator() {
        require(
            _msgSender() == address(_getLendPoolConfigurator()),
            Errors.LP_CALLER_NOT_LEND_POOL_CONFIGURATOR
        );
        _;
    }

    /**
     * @dev Initializes the cToken
     * @param addressProvider The address of the address provider where this cToken will be used
     * @param underlyingAsset The address of the underlying asset of this cToken
     */
    function initialize(
        IAddressesProvider addressProvider,
        address underlyingAsset,
        uint8 cTokenDecimals,
        string calldata cTokenName,
        string calldata cTokenSymbol
    ) external override initializer {
        __IncentivizedERC20_init(cTokenName, cTokenSymbol, cTokenDecimals);

        _underlyingAsset = underlyingAsset;

        _addressProvider = addressProvider;

        emit Initialized(
            underlyingAsset,
            _addressProvider.getLendPool(),
            _addressProvider.getIncentivesController()
        );
    }

    /**
     * @dev Burns cTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * - Only callable by the LendPool, as extra state updates there need to be managed
     * @param user The owner of the cTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     **/
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external override onlyLendPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.CT_INVALID_BURN_AMOUNT);
        _burn(user, amountScaled);

        IERC20Upgradeable(_underlyingAsset).safeTransfer(
            receiverOfUnderlying,
            amount
        );

        emit Burn(user, receiverOfUnderlying, amount, index);
    }

    /**
     * @dev Mints `amount` cTokens to `user`
     * - Only callable by the LendPool, as extra state updates there need to be managed
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyLendPool returns (bool) {
        uint256 previousBalance = super.balanceOf(user);

        // index is expressed in Ray, so:
        // amount.wadToRay().rayDiv(index).rayToWad() => amount.rayDiv(index)
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);
        _mint(user, amountScaled);

        emit Mint(user, amount, index);

        return previousBalance == 0;
    }


    /**
     * @dev Mints cTokens to the reserve treasury
     * - Only callable by the LendPool
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     */
    function mintToTreasury(uint256 amount, uint256 index)
    external
    override
    onlyLendPool
    {
        if (amount == 0) {
            return;
        }
        IConfigurator configurator = IConfigurator(_addressProvider.getConfigurator());
        address treasury = configurator.vaultAddress();

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest ccrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mint(treasury, amount.rayDiv(index));

        emit Transfer(address(0), treasury, amount);
        emit Mint(treasury, amount, index);
    }


    /**
     * @dev Calculates the balance of the user: principal balance + interest generated by the principal
     * @param user The user whose balance is calculated
     * @return The balance of the user
     **/
    function balanceOf(address user) public view override returns (uint256) {
        ILendPool pool = _getLendPool();
        return
            super.balanceOf(user).rayMul(
                pool.getReserveNormalizedIncome(_underlyingAsset)
            );
    }

    /**
     * @dev Returns the scaled balance of the user. The scaled balance is the sum of all the
     * updated stored balance divided by the reserve's liquidity index at the moment of the update
     * @param user The user whose balance is calculated
     * @return The scaled balance of the user
     **/
    function scaledBalanceOf(address user)
        external
        view
        override
        returns (uint256)
    {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the scaled balance of the user and the scaled total supply.
     * @param user The address of the user
     * @return The scaled balance of the user
     * @return The scaled balance and the scaled total supply
     **/
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        override
        returns (uint256, uint256)
    {
        return (super.balanceOf(user), super.totalSupply());
    }

    /**
     * @dev calculates the total supply of the specific cToken
     * since the balance of every single user increases over time, the total supply
     * does that too.
     * @return the current total supply
     **/
    function totalSupply() public view override returns (uint256) {
        uint256 currentSupplyScaled = super.totalSupply();

        if (currentSupplyScaled == 0) {
            return 0;
        }

        ILendPool pool = _getLendPool();
        return
            currentSupplyScaled.rayMul(
                pool.getReserveNormalizedIncome(_underlyingAsset)
            );
    }

    /**
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
     * @return the scaled total supply
     **/
    function scaledTotalSupply()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return super.totalSupply();
    }

    /**
     * @dev Returns the address of the ChipMunk treasury, receiving the fees on this cToken
     **/
    function RESERVE_TREASURY_ADDRESS() public view returns (address) {
        IConfigurator configurator = IConfigurator(_addressProvider.getConfigurator());
        return configurator.vaultAddress();
    }

    /**
     * @dev Returns the address of the underlying asset of this cToken
     **/
    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the lending pool where this cToken is used
     **/
    function POOL() public view returns (ILendPool) {
        return _getLendPool();
    }

    /**
     * @dev For internal usage in the logic of the parent contract IncentivizedERC20
     **/
    function _getIncentivesController()
        internal
        view
        override
        returns (IIncentivesController)
    {
        return
            IIncentivesController(_addressProvider.getIncentivesController());
    }

    function _getUnderlyingAssetAddress()
        internal
        view
        override
        returns (address)
    {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the incentives controller contract
     **/
    function getIncentivesController()
        external
        view
        override
        returns (IIncentivesController)
    {
        return _getIncentivesController();
    }

    /**
     * @dev Transfers the underlying asset to `target`. Used by the LendPool to transfer
     * assets in borrow(), withdraw()
     * @param target The recipient of the cTokens
     * @param amount The amount getting transferred
     * @return The amount transferred
     **/
    function transferUnderlyingTo(address target, uint256 amount)
        external
        override
        onlyLendPool
        returns (uint256)
    {
        IERC20Upgradeable(_underlyingAsset).safeTransfer(target, amount);
        return amount;
    }

    function _getLendPool() internal view returns (ILendPool) {
        return ILendPool(_addressProvider.getLendPool());
    }

    function _getLendPoolConfigurator()
        internal
        view
        returns (ILendPoolConfigurator)
    {
        return
            ILendPoolConfigurator(_addressProvider.getLendPoolConfigurator());
    }


    /**
     * @dev Transfers the cTokens between two users. Validates the transfer
     * (ie checks for valid HF after the transfer) if required
     * @param from The source address
     * @param to The destination address
     * @param amount The amount getting transferred
     * @param validate `true` if the transfer needs to be validated
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount,
        bool validate
    ) internal {
        address underlyingAsset = _underlyingAsset;
        ILendPool pool = _getLendPool();

        uint256 index = pool.getReserveNormalizedIncome(underlyingAsset);

        uint256 fromBalanceBefore = super.balanceOf(from).rayMul(index);
        uint256 toBalanceBefore = super.balanceOf(to).rayMul(index);

        super._transfer(from, to, amount.rayDiv(index));

        if (validate) {
            pool.finalizeTransfer(
                underlyingAsset,
                from,
                to,
                amount,
                fromBalanceBefore,
                toBalanceBefore
            );
        }

        emit BalanceTransfer(from, to, amount, index);
    }

    /**
     * @dev Overrides the parent _transfer to force validated transfer() and transferFrom()
     * @param from The source address
     * @param to The destination address
     * @param amount The amount getting transferred
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        _transfer(from, to, amount, true);
    }
}
