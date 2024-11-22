// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FlexiscrowFactory.sol";

contract DeployFlexiscrowFactory is Script {
    address public arbitrator = 0x2140eF2532a4CB0f1A2399B673F374b7f6289481;

    address public erc20Token = 0xb592fcedC173B15203F03142E4e7584530B45759;

    uint256 public flatFee = 3e18;

    uint256 public basepoints = 250;

    function run() public returns (FlexiscrowFactory) {
        vm.startBroadcast();
        FlexiscrowFactory flexiscrowFactory = new FlexiscrowFactory(
            arbitrator,
            erc20Token,
            flatFee,
            basepoints
        );
        vm.stopBroadcast();
        return flexiscrowFactory;
    }
}

// 0x9dcB214fcC8138AceA795Bc5cc339cdD11D26Edc
// ╰─ forge script script/DeployFlexiscrowFactory.s.sol --rpc-url $ETH_RPC_URL --account defaultKey --broadcast --verify --verifier blockscout --verifier-url $VERIFIER_URL
