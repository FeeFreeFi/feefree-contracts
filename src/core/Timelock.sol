// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC6909Claims} from "../uniswap/interfaces/external/IERC6909Claims.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";

/***
 *    00000000\                  00000000\
 *    00  _____|                 00  _____|
 *    00 |    000000\   000000\  00 |    000000\   000000\   000000\
 *    00000\ 00  __00\ 00  __00\ 00000\ 00  __00\ 00  __00\ 00  __00\
 *    00  __|00000000 |00000000 |00  __|00 |  \__|00000000 |00000000 |
 *    00 |   00   ____|00   ____|00 |   00 |      00   ____|00   ____|
 *    00 |   \0000000\ \0000000\ 00 |   00 |      \0000000\ \0000000\
 *    \__|    \_______| \_______|\__|   \__|       \_______| \_______|
 */
contract Timelock is ITimelock {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;

    error InvalidLock();
    error NotYetUnlocked();
    error NotOwner();
    error AlreadyUnlocked();

    event Lock(bytes32 lockId);
    event Unlock(bytes32 lockId);

    uint256 private nonce;

    mapping (bytes32 lockId => LockData) private _lockDatas;
    mapping (address owner => mapping (uint256 tokenId => EnumerableSet.Bytes32Set)) private _ownedLocks;
    mapping (address owner => EnumerableSet.UintSet) private _ownedTokens;

    function lock(IERC6909Claims token, address from, uint256 tokenId, uint256 amount, uint256 unlockTime, address owner) external returns (bytes32 lockId) {
        token.transferFrom(from, address(this), tokenId, amount);

        unchecked {
            nonce++;
        }

        lockId = keccak256(abi.encodePacked(block.timestamp, lockId, tokenId, nonce));
        _lockDatas[lockId] = LockData(lockId, token, tokenId, amount, unlockTime, owner, false);

        _ownedLocks[owner][tokenId].add(lockId);
        if (!_ownedTokens[owner].contains(tokenId)) {
            _ownedTokens[owner].add(tokenId);
        }

        emit Lock(lockId);
    }

    function unlock(bytes32 lockId, address recipient) external override {
        LockData storage lockData = _lockDatas[lockId];
        uint256 tokenId = lockData.tokenId;

        if (tokenId == 0) {
            revert InvalidLock();
        }

        if (lockData.unlockTime > block.timestamp) {
            revert NotYetUnlocked();
        }

        if (msg.sender != lockData.owner) {
            revert NotOwner();
        }

        if (lockData.unlocked) {
            revert AlreadyUnlocked();
        }

        lockData.unlocked = true;
        _ownedLocks[msg.sender][tokenId].remove(lockId);

        if (_ownedLocks[msg.sender][tokenId].length() == 0) {
            _ownedTokens[msg.sender].remove(tokenId);
        }

        emit Unlock(lockId);

        lockData.token.transfer(recipient, tokenId, lockData.amount);
    }

    function getLockData(bytes32 lockId) external view override returns (LockData memory) {
        return _lockDatas[lockId];
    }

    function getLockIds(address owner, uint256 tokenId) external view override returns (bytes32[] memory) {
        return _ownedLocks[owner][tokenId].values();
    }

    function getTokenIds(address owner) external view override returns (uint256[] memory) {
        return _ownedTokens[owner].values();
    }
}