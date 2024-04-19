// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {FFWeekNFT} from "../src/nft/FFWeekNFT.sol";

/**
 * usage: forge script script/FFWeekNFT.s.sol:Deploy --broadcast -vvvv --rpc-url $BASE_SEPOLIA_RPC_URL
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FFWeekNFT weekNft1 = new FFWeekNFT("FFWeekNFT", 202416);
        console.log("FFWeekNFT depoly success", address(weekNft1));

        FFWeekNFT weekNft2 = new FFWeekNFT("FFWeekNFT", 202417);
        console.log("FFWeekNFT depoly success", address(weekNft2));

        vm.stopBroadcast();
    }
}