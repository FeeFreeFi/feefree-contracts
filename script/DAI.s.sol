// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {DAI} from "../src/mock/DAI.sol";

/**
 * usage: forge script script/DAI.s.sol:Deploy --broadcast -vvvv --rpc-url $RPC_URL
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address dev = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        DAI dai = new DAI(dev);
        console.logString("DAI depoly success");
        console.log(address(dai));

        vm.stopBroadcast();
    }
}