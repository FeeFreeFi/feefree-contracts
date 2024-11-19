// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {USDC} from "../src/mock/USDC.sol";

/**
 * usage: forge script script/USDC.s.sol:Deploy --broadcast -vvvv --rpc-url $RPC_URL
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address dev = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        USDC usdc = new USDC(dev);
        console.logString("USDC depoly success");
        console.log(address(usdc));

        vm.stopBroadcast();
    }
}