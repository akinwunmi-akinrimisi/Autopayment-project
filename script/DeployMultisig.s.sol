// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Multisig.sol";

contract DeployMultisig is Script {
    uint256 public quorum = 2;

    /// @notice List of authorized signers
    address[] public signers = [
        0x89773C5d56De1a6BdE05dfAFB95c3319458Dc5b1,
        0x575109e921C6d6a1Cb7cA60Be0191B10950AfA6C,
        0x6c8fcDeb117a1d40Cd2c2eB6ECDa58793FD636b1
    ];

    /// @notice Token used for fee payments
    address public feeToken = 0xb592fcedC173B15203F03142E4e7584530B45759;

    function run() public returns (Multisig) {
        vm.startBroadcast();
        Multisig multisig = new Multisig(signers, quorum, feeToken);
        vm.stopBroadcast();
        return multisig;
    }
}

// 0x2140eF2532a4CB0f1A2399B673F374b7f6289481
// ╰─ forge script script/DeployMultisig.s.sol --rpc-url $ETH_RPC_URL --account defaultKey --broadcast --verify --verifier blockscout --verifier-url $VERIFIER_URL