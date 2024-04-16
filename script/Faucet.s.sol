// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {Faucet} from "../src/mock/Faucet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * usage: forge script script/Faucet.s.sol:Deploy --broadcast -vvvv --rpc-url $BASE_SEPOLIA_RPC_URL
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Faucet faucet = new Faucet();
        console.logString("Faucet depoly success");
        console.log(address(faucet));

        vm.stopBroadcast();
    }
}
