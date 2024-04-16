// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {OP} from "../src/mock/OP.sol";

/**
 * usage: forge script script/OP.s.sol:Deploy --broadcast -vvvv --rpc-url $BASE_SEPOLIA_RPC_URL
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        OP op = new OP();
        console.logString("OP depoly success");
        console.log(address(op));

        vm.stopBroadcast();
    }
}