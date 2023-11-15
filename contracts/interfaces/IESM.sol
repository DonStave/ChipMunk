// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.0;

interface IESM {
    event Open(uint256 id);
    event Pause(uint256 id);

    function open(uint256 id) external;

    function pause(uint256 id) external;

    function isSwitchPaused(uint256 id) external view returns (bool);
}
