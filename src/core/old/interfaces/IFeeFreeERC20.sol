// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IERC20Metadata} from "../../interfaces/IERC20Metadata.sol";

interface IFeeFreeERC20 is IERC20, IERC20Metadata {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}
