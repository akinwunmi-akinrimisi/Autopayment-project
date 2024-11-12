// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Escrow.sol";

contract EscrowFactory is Ownable {
    address public immutable arbitrator;
    address public immutable erc20Token;
    address public immutable feeRecipient;

    uint256 public flatFee; 
    uint256 public bpsFee;  

    event EscrowCreated(address indexed escrow, address indexed buyer, address indexed seller);
    event FeeUpdated(uint256 flatFee, uint256 bpsFee); 

    constructor(
        address _arbitrator,
        address _erc20Token,
        address _feeRecipient,
        uint256 _flatFee,
        uint256 _bpsFee
    ) Ownable(msg.sender) {
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipientAddress();

        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        feeRecipient = _feeRecipient;
        flatFee = _flatFee;
        bpsFee = _bpsFee;
    }

    function createEscrow (
        address buyer,
        address seller,
        uint256 milestoneCount
    ) external returns (address) {
        Escrow escrow = new Escrow(
            buyer,
            seller,
            arbitrator,
            erc20Token,
            feeRecipient,
            flatFee,
            bpsFee,
            milestoneCount
        );

        emit EscrowCreated(address(escrow), buyer, seller);
        return address(escrow);
    }

    function updateFees(uint256 _flatFee, uint256 _bpsFee) external onlyOwner {
        flatFee = _flatFee;
        bpsFee = _bpsFee;

        emit FeeUpdated(flatFee, bpsFee);
    }
}
