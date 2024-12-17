// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

interface IShortableToken is IERC20, IERC20Metadata {
    function opponent() external view returns (address);
    function positive() external view returns (bool);

    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}