// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LiskToken.sol";

contract DeployLiskToken is Script {
    function run() public returns (LiskToken) {
        vm.startBroadcast();
        LiskToken liskToken = new LiskToken();
        vm.stopBroadcast();
        return liskToken;
    }
}

// 0xb592fcedC173B15203F03142E4e7584530B45759.
// source .env
// ╰─ forge script script/DeployLisk.s.sol --rpc-url $ETH_RPC_URL --account defaultKey --broadcast --verify --verifier blockscout --verifier-url $VERIFIER_URL