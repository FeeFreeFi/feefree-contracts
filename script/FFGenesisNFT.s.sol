// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {FFGenesisNFT} from "../src/nft/FFGenesisNFT.sol";

/**
 * usage: forge script script/FFGenesisNFT.s.sol:Deploy --broadcast -vvvv --rpc-url $BASE_SEPOLIA_RPC_URL
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FFGenesisNFT genesisNFT = new FFGenesisNFT("https://app.feefree.fi/uri/nft/84532/genesis/", 1e16);
        console.log("FFGenesisNFT depoly success", address(genesisNFT));

        vm.stopBroadcast();
    }
}