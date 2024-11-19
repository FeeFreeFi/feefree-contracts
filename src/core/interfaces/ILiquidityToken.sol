// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC6909Claims} from "../../uniswap/interfaces/external/IERC6909Claims.sol";

interface ILiquidityToken is IERC6909Claims {
    function mint(address to, uint256 tokenId, uint256 amount) external;
    function burn(address from, uint256 tokenId, uint256 amount) external;
    function getOwnedIds(address account) external view returns (uint256[] memory);
}