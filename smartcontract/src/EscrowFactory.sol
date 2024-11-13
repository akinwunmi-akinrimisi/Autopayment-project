// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Escrow.sol";

contract EscrowFactory is Ownable {
    address public immutable arbitrator;
    address public immutable erc20Token;
    address public immutable feeRecipient;
    uint256 private releaseTimeout;

    uint256 public flatFee;
    uint256 public basepoints;

    event EscrowCreated(address indexed escrow, address indexed buyer, address indexed seller);
    event FeeUpdated(uint256 flatFee, uint256 basepoints);
    event TimeOutUpdated(uint256 releaseTimeout);

    constructor(address _arbitrator, address _erc20Token, address _feeRecipient, uint256 _flatFee, uint256 _bps)
        Ownable(msg.sender)
    {
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipientAddress();

        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        feeRecipient = _feeRecipient;
        flatFee = _flatFee;
        basepoints = _bps;
    }

    function createEscrow(address buyer, address seller, uint256 milestoneCount) external returns (address) {
        Escrow escrow = new Escrow(
            buyer, seller, arbitrator, erc20Token, feeRecipient, flatFee, basepoints, milestoneCount, releaseTimeout
        );

        emit EscrowCreated(address(escrow), buyer, seller);
        return address(escrow);
    }

    function updateFees(uint256 _flatFee, uint256 _bps) external onlyOwner {
        flatFee = _flatFee;
        basepoints = _bps;

        emit FeeUpdated(flatFee, basepoints);
    }

    function updateReleaseTimeout(uint256 _releaseTimeout) external onlyOwner {
        releaseTimeout = _releaseTimeout;
        emit TimeOutUpdated(_releaseTimeout);
    }
}
