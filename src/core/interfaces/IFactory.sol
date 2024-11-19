// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "../../uniswap/types/Currency.sol";

interface IFactory {
    function deploy(string memory name, string memory symbol, uint256 totalSupply) external returns (Currency positiveCurrency, Currency negativeCurrency);
}