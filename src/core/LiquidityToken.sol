// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {ILiquidityToken} from "./interfaces/ILiquidityToken.sol";
import {IERC6909Claims} from "../uniswap/interfaces/external/IERC6909Claims.sol";
import {ERC6909} from "../uniswap/ERC6909.sol";
import {ERC6909Claims} from "../uniswap/ERC6909Claims.sol";

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
contract LiquidityToken is Owned, ERC6909Claims, ILiquidityToken {
    using EnumerableSet for EnumerableSet.UintSet;

    mapping (address owner => EnumerableSet.UintSet) private _ownedIds;

    constructor(address _owner) Owned(_owner) {}

    function mint(address to, uint256 id, uint256 amount) external override onlyOwner {
        _mint(to, id, amount);
        _updateOwned(to, id);
    }

    function burn(address from, uint256 id, uint256 amount) external override onlyOwner {
        _burnFrom(from, id, amount);
        _updateOwned(from, id);
    }

    function transfer(address receiver, uint256 id, uint256 amount) public override(IERC6909Claims,ERC6909) returns (bool) {
        bool success = super.transfer(receiver, id, amount);
        if (success) {
            _updateOwned(msg.sender, id);
            _updateOwned(receiver, id);
        }
        return success;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) public override(IERC6909Claims,ERC6909) returns (bool) {
        bool success = super.transferFrom(sender, receiver, id, amount);
        if (success) {
            _updateOwned(sender, id);
            _updateOwned(receiver, id);
        }
        return success;
    }

    function _updateOwned(address account, uint256 id) internal {
        if (balanceOf[account][id] > 0) {
            if (!_ownedIds[account].contains(id)) {
                _ownedIds[account].add(id);
            }
        } else {
            if (_ownedIds[account].contains(id)) {
                _ownedIds[account].remove(id);
            }
        }
    }

    function getOwnedIds(address account) external override view returns (uint256[] memory) {
        return _ownedIds[account].values();
    }
}