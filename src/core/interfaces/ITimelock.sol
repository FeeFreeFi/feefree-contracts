// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC6909Claims} from "../../uniswap/interfaces/external/IERC6909Claims.sol";

interface ITimelock {
    struct LockData {
        bytes32 lockId;
        IERC6909Claims token;
        uint256 tokenId;
        uint256 amount;
        uint256 unlockTime;
        address owner;
        bool unlocked;
    }

    function getLockData(bytes32 lockId) external view returns (LockData memory);

    function getLockIds(address owner, uint256 tokenId) external view returns (bytes32[] memory);
    function getTokenIds(address owner) external view returns (uint256[] memory);

    function lock(IERC6909Claims token, address from, uint256 tokenId, uint256 amount, uint256 unlockTime, address owner) external returns (bytes32 lockId);
    function unlock(bytes32 lockId, address recipient) external;
}