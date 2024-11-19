// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {FFGenesisNFT} from "../src/nft/FFGenesisNFT.sol";
import {FFWeekNFT} from "../src/nft/FFWeekNFT.sol";

/**
 * usage: forge script script/NFT.s.sol:Deploy --broadcast -vvvv --rpc-url $RPC_URL
 */
contract DeployGenesisNFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FFGenesisNFT genesisNFT = new FFGenesisNFT("https://app.feefree.fi/uri/nft/7777777/genesis/", 1e16);
        console.log("FFGenesisNFT depoly success", address(genesisNFT));

        vm.stopBroadcast();
    }
}

/**
 * usage: forge script script/NFT.s.sol:DeployWeekNFT --broadcast -vvvv --rpc-url $RPC_URL
 */
contract DeployWeekNFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FFWeekNFT weekNft = new FFWeekNFT("https://app.feefree.fi/uri/nft/7777777/202417/", 202417);
        console.log("FFWeekNFT depoly success", address(weekNft));

        vm.stopBroadcast();
    }
}
