// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;
pragma abicoder v2;

import {IScaledBalanceToken} from "./IScaledBalanceToken.sol";

interface IIncentivesController {
    event RewardsAccrued(address indexed _user, uint256 _amount);
    event RewardsClaimed(address indexed _user, uint256 _amount);
    event UpdateRewardVault(address vault);
    event WithdrawRewardToTreasury(uint256 amount);

    /**
     * @dev Configure assets for a certain rewards emission
     * @param _assets The assets to incentivize
     * @param _emissionsPerSecond The emission for each asset
     */
    function configureAssets(
        IScaledBalanceToken[] calldata _assets,
        uint256[] calldata _emissionsPerSecond
    ) external;

    /**
     * @dev Called by the corresponding asset on any update that affects the rewards distribution
     * @param _asset The address of the asset
     * @param _user The address of the user
     * @param _totalSupply The total supply of the asset in the lending pool
     * @param _userBalance The balance of the user of the asset in the lending pool
     **/
    function handleAction(
        address _asset,
        address _user,
        uint256 _totalSupply,
        uint256 _userBalance
    ) external;

    /**
     * @dev Returns the total of rewards of an user, already accrued + not yet accrued
     * @param _user The address of the user
     * @return The rewards
     **/
    function getRewardsBalance(address[] calldata _assets, address _user)
        external
        view
        returns (uint256);

    /**
     * @dev Claims reward for an user, on all the assets of the lending pool, accumulating the pending rewards
     * @return Rewards claimed
     **/
    function claimRewards(address[] calldata _assets)
        external
        returns (uint256);

    /**
     * @dev returns the unclaimed rewards of the user
     * @param _asset the address of the _asset
     * @param _user the address of the user
     * @return the unclaimed user rewards
     */
    function getUserUnclaimedRewards(address _asset, address _user)
        external
        view
        returns (uint256);

    function setAdmin(address _admin) external;

    function updateRewardVault(address vault) external;

    function withdrawReward(uint256 amount) external;
}
