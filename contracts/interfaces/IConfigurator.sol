// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IConfigurator {
    event MinLendEvent(uint256 _minLend);
    event BufferTimeEvent(uint256 _bufferTime);
    event CountdownTimeEvent(uint256 _countdownTime);
    event BidRewardRateEvent(uint256 _bidRewardRate);
    event MinBidDeltaEvent(uint256 _minBidDelta);
    event UpdateVaultAddress(address vault);

    function minLend() external view returns (uint256);

    function bufferTime() external view returns (uint256);

    function countdownTime() external view returns (uint256);

    function bidRewardRate() external view returns (uint256);

    function minBidDelta() external view returns (uint256);

    function vaultAddress() external view returns (address);

    function setMinLendEvent(uint256 _minLend) external;

    function setBufferTimeEvent(uint256 _bufferTime) external;

    function setCountdownTimeEvent(uint256 _countdownTime) external;

    function setBidRewardRateEvent(uint256 _bidRewardRate) external;

    function setMinBidDeltaEvent(uint256 _minBidDelta) external;

    function updateVaultAddress(address vault) external;
}
