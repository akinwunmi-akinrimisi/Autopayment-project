// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error NotAuthorizedSigner();
error SignersRequired();
error InvalidQuorum();
error InvalidERC20TokenAddress();
error AlreadyVoted();
error ProposalAlreadyExecuted();
error InsufficientVotesToExecute();
error HigherVotesAgainst();
error AlreadyASigner();
error NotASigner();
error InsufficientTokenBalance();
error SignerNotFound();
error EscrowContractFailed();

interface IEscrow {
    function settleMilestone(uint256 milestoneId, uint256 refundAmount, uint256 releaseAmount) external;
}

contract Multisig is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public quorum;
    address[] public signers;
    IERC20 public feeToken;

    enum ProposalType {
        AddSigner,
        RemoveSigner,
        UpdateQuorum,
        WithdrawFees
    }

    struct Proposal {
        ProposalType proposalType;
        address target;
        address signer;
        uint256 newQuorum;
        uint256 withdrawalAmount;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        mapping(address => bool) voted;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    event ProposalCreated(uint256 proposalId, ProposalType proposalType, address target);
    event VoteCast(uint256 proposalId, address voter, bool support);
    event ProposalExecuted(uint256 proposalId);
    event MilestoneSettled(uint256 milestoneId, uint256 refundAmount, uint256 releaseAmount, address indexed signer);

    modifier onlySigner() {
        if (!isSigner(msg.sender)) revert NotAuthorizedSigner();
        _;
    }

    constructor(address[] memory _signers, uint256 _quorum, IERC20 _feeToken) {
        if (_signers.length == 0) revert SignersRequired();
        if (_quorum == 0 || _quorum > _signers.length) revert InvalidQuorum();
        if (address(_feeToken) == address(0)) revert InvalidERC20TokenAddress();

        for (uint256 i = 0; i < _signers.length; i++) {
            signers.push(_signers[i]);
        }
        quorum = _quorum;
        feeToken = _feeToken;
    }

    function isSigner(address account) public view returns (bool) {
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == account) {
                return true;
            }
        }
        return false;
    }

    function createProposal(
        ProposalType proposalType,
        address target,
        address signer,
        uint256 newQuorum,
        uint256 withdrawalAmount
    ) external onlySigner returns (uint256) {
        Proposal storage proposal = proposals[proposalCount];

        proposal.proposalType = proposalType;
        proposal.target = target;
        proposal.signer = signer;
        proposal.newQuorum = newQuorum;
        proposal.withdrawalAmount = withdrawalAmount;
        proposal.votesFor = 0;
        proposal.votesAgainst = 0;
        proposal.executed = false;

        emit ProposalCreated(proposalCount, proposalType, target);
        return proposalCount++;
    }

    function vote(uint256 proposalId, bool support) external onlySigner nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.voted[msg.sender]) revert AlreadyVoted();
        if (proposal.executed) revert ProposalAlreadyExecuted();

        proposal.voted[msg.sender] = true;

        if (support) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }

        emit VoteCast(proposalId, msg.sender, support);
    }

    function executeProposal(uint256 proposalId) external onlySigner nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.votesFor < quorum) revert InsufficientVotesToExecute();
        if (proposal.votesFor <= proposal.votesAgainst) {
            revert HigherVotesAgainst();
        }
        if (proposal.proposalType == ProposalType.AddSigner) {
            if (isSigner(proposal.signer)) revert AlreadyASigner();
            signers.push(proposal.signer);
        } else if (proposal.proposalType == ProposalType.RemoveSigner) {
            if (!isSigner(proposal.signer)) revert NotASigner();
            _removeSigner(proposal.signer);
        } else if (proposal.proposalType == ProposalType.UpdateQuorum) {
            if (proposal.newQuorum == 0 || proposal.newQuorum > signers.length) {
                revert InvalidQuorum();
            }
            quorum = proposal.newQuorum;
        } else if (proposal.proposalType == ProposalType.WithdrawFees) {
            if (proposal.withdrawalAmount > feeToken.balanceOf(address(this))) {
                revert InsufficientTokenBalance();
            }
            feeToken.safeTransfer(proposal.target, proposal.withdrawalAmount);
        }

        proposal.executed = true;
        emit ProposalExecuted(proposalId);
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool voted) {
        if (!isSigner(voter)) revert NotAuthorizedSigner();
        Proposal storage proposal = proposals[proposalId];
        voted = proposal.voted[voter];
    }

    function settleMilestoneWithoutQuorum(
        address escrowContract,
        uint256 milestoneId,
        uint256 refundAmount,
        uint256 releaseAmount
    ) external onlySigner nonReentrant {
        try IEscrow(escrowContract).settleMilestone(milestoneId, refundAmount, releaseAmount) {}
        catch (bytes memory) {
            revert EscrowContractFailed();
        }

        emit MilestoneSettled(milestoneId, refundAmount, releaseAmount, msg.sender);
    }

    function _removeSigner(address signer) internal {
        uint256 index;
        bool found = false;
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == signer) {
                index = i;
                found = true;
                break;
            }
        }
        if (!found) revert SignerNotFound();

        signers[index] = signers[signers.length - 1];
        signers.pop();
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }
}
