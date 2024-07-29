// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract USDC is ERC20 {
    constructor() ERC20("USDC", "USDC", 6) {
        _mint(msg.sender, 1e40);
    }
}
