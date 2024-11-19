// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Capped {
    function cap() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}