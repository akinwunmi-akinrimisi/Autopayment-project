// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

//Custom Errors
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
    function settleMilestone(
        uint256 milestoneId,
        uint256 refundAmount,
        uint256 releaseAmount
    ) external;
}

/**
 * @title Multisig
 * @author Roqib Yusuf
 * @notice Multi-signature wallet for governance and escrow dispute resolution
 * @dev Implements a governance system with proposal creation, voting, and execution
 */

contract Multisig is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Required number of votes for proposal execution
    uint256 public quorum;

    /// @notice List of authorized signers
    address[] public signers;

    /// @notice Token used for fee payments
    IERC20 public feeToken;

    /**
     * @notice Types of proposals that can be created
     * @param AddSigner Add a new signer to the multisig
     * @param RemoveSigner Remove an existing signer
     * @param UpdateQuorum Change the required number of votes
     * @param WithdrawFees Withdraw accumulated fees
     */
    enum ProposalType {
        AddSigner,
        RemoveSigner,
        UpdateQuorum,
        WithdrawFees
    }

    /**
     * @notice Structure containing proposal details
     * @param proposalType Type of action being proposed
     * @param target Address receiving withdrawn fees
     * @param signer Address being added/removed as signer
     * @param newQuorum New quorum value for quorum updates
     * @param withdrawalAmount Amount of fees to withdraw
     * @param votesFor Number of votes supporting the proposal
     * @param votesAgainst Number of votes against the proposal
     * @param executed Whether the proposal has been executed
     * @param voted Mapping of signer addresses to their voting status
     */
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
    /// @notice Mapping of proposal IDs to proposal details
    mapping(uint256 => Proposal) public proposals;

    /// @notice Total number of proposals created
    uint256 public proposalCount;

    event ProposalCreated(
        uint256 proposalId,
        ProposalType proposalType,
        address target
    );
    event VoteCasted(uint256 proposalId, address voter, bool support);
    event ProposalExecuted(uint256 proposalId);
    event MilestoneSettled(
        uint256 milestoneId,
        uint256 refundAmount,
        uint256 releaseAmount,
        address indexed signer
    );

    modifier onlySigner() {
        if (!isSigner(msg.sender)) revert NotAuthorizedSigner();
        _;
    }

    /**
     * @notice Creates a new Multisig contract
     * @param _signers Initial list of authorized signers
     * @param _quorum Number of required votes
     * @param _feeToken Address of the fee token
     */
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

    /**
     * @notice Checks if an address is an authorized signer
     * @param account The address to check
     * @return True if the address is a signer, false otherwise
     */
    function isSigner(address account) public view returns (bool) {
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == account) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Creates a new proposal for governance actions
     * @param proposalType The type of proposal (e.g., AddSigner, RemoveSigner)
     * @param target The address for fee withdrawal proposals
     * @param signer The address to add or remove as a signer (if applicable)
     * @param newQuorum The new quorum value (if applicable)
     * @param withdrawalAmount The amount to withdraw (if applicable)
     * @return The ID of the newly created proposal
     */
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

    /**
     * @notice Casts a vote on a specific proposal
     * @param proposalId The ID of the proposal being voted on
     * @param support True to vote in favor, false to vote against
     */
    function vote(
        uint256 proposalId,
        bool support
    ) external onlySigner nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.voted[msg.sender]) revert AlreadyVoted();
        if (proposal.executed) revert ProposalAlreadyExecuted();

        proposal.voted[msg.sender] = true;

        if (support) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }

        emit VoteCasted(proposalId, msg.sender, support);
    }

    /**
     * @notice Executes a proposal if it meets the required quorum and vote count
     * @param proposalId The ID of the proposal to execute
     */
    function executeProposal(
        uint256 proposalId
    ) external onlySigner nonReentrant {
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
            if (
                proposal.newQuorum == 0 || proposal.newQuorum > signers.length
            ) {
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

    /**
     * @notice Checks if a signer has voted on a specific proposal
     * @param proposalId The ID of the proposal
     * @param voter The address of the signer to check
     * @return voted True if the signer has voted, false otherwise
     */
    function hasVoted(
        uint256 proposalId,
        address voter
    ) external view returns (bool voted) {
        if (!isSigner(voter)) revert NotAuthorizedSigner();
        Proposal storage proposal = proposals[proposalId];
        voted = proposal.voted[voter];
    }

    /**
     * @notice Settles an escrow milestone without requiring quorum
     * @param escrowContract Address of the escrow contract
     * @param milestoneId ID of the milestone to settle
     * @param refundAmount Amount to refund to buyer
     * @param releaseAmount Amount to release to seller
     */
    function settleMilestoneWithoutQuorum(
        address escrowContract,
        uint256 milestoneId,
        uint256 refundAmount,
        uint256 releaseAmount
    ) external onlySigner nonReentrant {
        try
            IEscrow(escrowContract).settleMilestone(
                milestoneId,
                refundAmount,
                releaseAmount
            )
        {} catch {
            revert EscrowContractFailed();
        }

        emit MilestoneSettled(
            milestoneId,
            refundAmount,
            releaseAmount,
            msg.sender
        );
    }

    /**
     * @notice Removes a signer from the list of authorized signers
     * @param signer The address of the signer to remove
     * @dev This function is internal and only called within the contract
     */
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

    /**
     * @notice Retrieves the list of all authorized signers
     * @return An array of addresses of the current signers
     */
    function getSigners() external view returns (address[] memory) {
        return signers;
    }
}
