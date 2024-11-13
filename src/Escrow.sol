// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//Custom Errors
error OnlyBuyerAllowed();
error OnlySellerAllowed();
error OnlyBuyerOrSellerAllowed();
error OnlyArbitratorAllowed();
error InvalidBuyerOrSellerAddress();
error InvalidArbitratorAddress();
error InvalidERC20TokenAddress();
error InvalidFeeRecipientAddress();
error InvalidMilestone();
error MilestoneNotPending();
error MilestoneAlreadyFunded();
error MilestoneOutOfSequence();
error NoActiveDispute();
error InvalidSettlementAmounts();
error DeadlineNotReached();
error MilestoneNotReadyForRelease();
error RefundDeadlineNotReached();
error InvalidMilestoneStatus();
error InvalidAmount();

/**
 * @title Escrow
 * @author Roqib Yusuf
 * @notice A milestone-based escrow contract for ERC20 tokens with arbitration capabilities
 * @dev Implements a secure payment system where funds are released based on milestone completion
 */
contract Escrow {
    using SafeERC20 for IERC20;

    /**
     * @notice Status of each milestone
     * @param Pending Initial state, waiting for funding and completion
     * @param ReadyForRelease Marked as complete by seller, awaiting buyer release
     * @param Completed Funds have been released or refunded
     * @param Disputed Under dispute resolution by arbitrator
     */
    enum MilestoneStatus {
        Pending,
        ReadyForRelease,
        Completed,
        Disputed
    }

    /**
     * @notice Structure containing milestone details
     * @param amount The amount of tokens allocated for this milestone
     * @param status Current status of the milestone
     * @param deadline Timestamp by which the seller can claim funds if buyer doesn't release or open dispute
     * @param refundDeadline Timestamp by which the buyer can claim a refund
     */
    struct Milestone {
        uint256 amount;
        MilestoneStatus status;
        uint256 deadline;
        uint256 refundDeadline;
    }

    /// @notice Address of the buyer who deposits funds
    address public immutable buyer;
    /// @notice Address of the seller who receives funds upon milestone completion
    address public immutable seller;
    /// @notice Address of the arbitrator who can resolve disputes
    address public immutable arbitrator;
    /// @notice Address of the ERC20 token used for payments
    address public immutable erc20Token;
    /// @notice Address receiving fees for milestone releases
    address public immutable feeRecipient;
    /// @notice Fixed fee amount charged per milestone
    uint256 public immutable flatFee;
    /// @notice Fee percentage in basepoints.  1 basepoint is 1/100 of 1%, also 0.01% or 1/10000.
    uint256 public immutable basepoints;
    /// @notice Time window for buyer to release funds after seller marks milestone complete
    uint256 public immutable releaseTimeout;

    /// @notice Array of all milestones in the contract
    Milestone[] public milestones;
    /// @notice Index of the current active milestone
    uint256 public currentMilestone;
    /// @notice Flag indicating if there's an active dispute
    bool public isDisputed;
    /// @notice Address that initiated the current dispute
    address public disputeInitiator;
    /// @notice Timestamp when the current dispute was initiated
    uint256 public disputeTimestamp;

    /**
     * @notice Emitted when milestone funds are released to the seller
     * @param milestoneId Index of the milestone
     * @param amount Amount of tokens released (excluding fees)
     */
    event MilestoneReleased(uint256 indexed milestoneId, uint256 amount);

    /**
     * @notice Emitted when a milestone enters disputed status
     * @param milestoneId Index of the milestone
     * @param initiator Address that initiated the dispute
     */
    event MilestoneDisputed(uint256 indexed milestoneId, address initiator);

    /**
     * @notice Emitted when arbitrator resolves a dispute
     * @param milestoneId Index of the milestone
     * @param refundAmount Amount refunded to buyer
     * @param releaseAmount Amount released to seller
     */
    event DisputeResolved(uint256 indexed milestoneId, uint256 refundAmount, uint256 releaseAmount);

    /**
     * @notice Emitted when seller marks a milestone as complete
     * @param milestoneId Index of the milestone
     */
    event MilestoneCompleted(uint256 indexed milestoneId);

    /**
     * @notice Emitted when milestone funds are refunded to the buyer
     * @param milestoneId Index of the milestone
     * @param amount Amount refunded
     */
    event MilestoneRefunded(uint256 indexed milestoneId, uint256 amount);

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert OnlyBuyerAllowed();
        _;
    }

    modifier onlySeller() {
        if (msg.sender != seller) revert OnlySellerAllowed();
        _;
    }

    modifier onlyArbitrator() {
        if (msg.sender != arbitrator) revert OnlyArbitratorAllowed();
        _;
    }

    /**
     * @notice Creates a new Escrow contract
     * @param _buyer Address of the buyer
     * @param _seller Address of the seller
     * @param _arbitrator Address of the arbitrator
     * @param _erc20Token Address of the ERC20 token used for payments
     * @param _feeRecipient Address receiving fees
     * @param _flatFee Fixed fee amount per milestone
     * @param _bps Fee percentage in basepoints
     * @param milestoneCount Number of milestones to create
     * @param _releaseTimeout Time window for buyer to release funds
     * @dev Initializes the contract with empty milestones in Pending status
     */
    constructor(
        address _buyer,
        address _seller,
        address _arbitrator,
        address _erc20Token,
        address _feeRecipient,
        uint256 _flatFee,
        uint256 _bps,
        uint256 milestoneCount,
        uint256 _releaseTimeout
    ) {
        if (_buyer == address(0) || _seller == address(0)) {
            revert InvalidBuyerOrSellerAddress();
        }
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipientAddress();

        buyer = _buyer;
        seller = _seller;
        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        feeRecipient = _feeRecipient;
        flatFee = _flatFee;
        basepoints = _bps;
        releaseTimeout = _releaseTimeout;

        for (uint256 i = 0; i < milestoneCount; i++) {
            milestones.push(Milestone({amount: 0, status: MilestoneStatus.Pending, deadline: 0, refundDeadline: 0}));
        }
    }

    /**
     * @notice Funds a specific milestone with tokens
     * @param milestoneId Index of the milestone to fund
     * @param amount Amount of tokens to fund
     * @param timeline Duration until refund becomes available
     * @dev Transfers tokens from buyer to contract
     * @dev Reverts if milestone is not pending or already funded
     */
    function fundMilestone(uint256 milestoneId, uint256 amount, uint256 timeline) external onlyBuyer {
        if (currentMilestone != milestoneId) revert InvalidMilestone();
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        if (amount < flatFee) revert InvalidAmount();
        if (milestones[milestoneId].status != MilestoneStatus.Pending) {
            revert MilestoneNotPending();
        }
        if (milestones[milestoneId].amount > 0) revert MilestoneAlreadyFunded();

        milestones[milestoneId].amount = amount;
        milestones[milestoneId].refundDeadline = block.timestamp + timeline;
        milestones[milestoneId].deadline = block.timestamp + timeline;

        IERC20(erc20Token).safeTransferFrom(buyer, address(this), amount);
    }

    /**
     * @notice Marks a milestone as complete by the seller
     * @param milestoneId Index of the milestone to complete
     * @dev Changes milestone status to ReadyForRelease
     * @dev Sets release deadline for buyer action
     */
    function markMilestoneComplete(uint256 milestoneId) external onlySeller {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status != MilestoneStatus.Pending) {
            revert MilestoneNotPending();
        }

        milestones[milestoneId].status = MilestoneStatus.ReadyForRelease;
        milestones[milestoneId].deadline = block.timestamp + releaseTimeout;
        milestones[milestoneId].refundDeadline = 0;
        emit MilestoneCompleted(milestoneId);
    }

    /**
     * @notice Releases milestone funds to seller
     * @param milestoneId Index of the milestone to release
     * @dev Can only be called by buyer
     * @dev Transfers funds to seller and fees to fee recipient
     */
    function releaseMilestone(uint256 milestoneId) external onlyBuyer {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status == MilestoneStatus.Pending) {
            revert MilestoneNotReadyForRelease();
        }

        _releaseMilestoneFunds(milestoneId);
    }

    /**
     * @notice Initiates a dispute for a milestone
     * @param milestoneId Index of the milestone to dispute
     * @dev Can be called by either buyer or seller
     * @dev Changes milestone status to Disputed
     */
    function disputeMilestone(uint256 milestoneId) external {
        if (msg.sender != buyer && msg.sender != seller) {
            revert OnlyBuyerOrSellerAllowed();
        }

        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (
            milestones[milestoneId].status != MilestoneStatus.Pending
                || milestones[milestoneId].status != MilestoneStatus.ReadyForRelease
        ) {
            revert InvalidMilestoneStatus();
        }

        milestones[milestoneId].status = MilestoneStatus.Disputed;
        isDisputed = true;
        disputeInitiator = msg.sender;
        disputeTimestamp = block.timestamp;
        emit MilestoneDisputed(milestoneId, msg.sender);
    }

    /**
     * @notice Claims milestone funds after buyer timeout
     * @param milestoneId Index of the milestone to claim
     * @dev Can only be called by seller after deadline
     * @dev Transfers funds to seller and fees to fee recipient
     */
    function claimMilestoneFunds(uint256 milestoneId) external onlySeller {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status != MilestoneStatus.ReadyForRelease) {
            revert MilestoneNotReadyForRelease();
        }
        if (block.timestamp < milestones[milestoneId].deadline) {
            revert DeadlineNotReached();
        }

        _releaseMilestoneFunds(milestoneId);
    }

    /**
     * @notice Refunds milestone funds to buyer
     * @param milestoneId Index of the milestone to refund
     * @dev Can only be called by buyer after refund deadline
     * @dev Returns full amount without fees
     */
    function refundMilestone(uint256 milestoneId) external onlyBuyer {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (block.timestamp < milestones[milestoneId].refundDeadline) {
            revert RefundDeadlineNotReached();
        }
        if (milestones[milestoneId].status != MilestoneStatus.Pending) {
            revert MilestoneNotPending();
        }

        uint256 refundAmount = milestones[milestoneId].amount;
        milestones[milestoneId].amount = 0;
        milestones[milestoneId].status = MilestoneStatus.Completed;
        currentMilestone++;

        IERC20(erc20Token).safeTransfer(buyer, refundAmount);
        emit MilestoneRefunded(milestoneId, refundAmount);
    }

    /**
     * @notice Resolves a disputed milestone
     * @param milestoneId Index of the disputed milestone
     * @param refundAmount Amount to refund to buyer
     * @param releaseAmount Amount to release to seller
     * @dev Can only be called by arbitrator
     * @dev Sum of refund and release must equal milestone amount
     */
    function resolveDispute(uint256 milestoneId, uint256 refundAmount, uint256 releaseAmount) external onlyArbitrator {
        if (!isDisputed) revert NoActiveDispute();
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        if (milestones[milestoneId].status != MilestoneStatus.Disputed) {
            revert NoActiveDispute();
        }

        uint256 totalAmount = refundAmount + releaseAmount;
        if (totalAmount != milestones[milestoneId].amount) {
            revert InvalidSettlementAmounts();
        }

        if (refundAmount > 0) {
            IERC20(erc20Token).safeTransfer(buyer, refundAmount);
        }
        if (releaseAmount > 0) {
            IERC20(erc20Token).safeTransfer(seller, releaseAmount);
        }

        milestones[milestoneId].status = MilestoneStatus.Completed;
        isDisputed = false;
        disputeInitiator = address(0);
        disputeTimestamp = 0;
        currentMilestone++;

        emit DisputeResolved(milestoneId, refundAmount, releaseAmount);
    }

    /**
     * @dev Internal function to release milestone funds
     * Example of fee calculation
     * If the flatFee is set to 50, and basepoints is 250 (which means a 2.5% fee -> Which means 2.5/100 -> Which also means 250 / (100 * 100)),
     * and the amount passed to calculateFee is 1,000, the fee would be:
     * 50 + (1000 * 250) / 10,000
     * = 50 + 25
     * = 75
     * @param milestoneId Index of the milestone
     */
    function _releaseMilestoneFunds(uint256 milestoneId) internal {
        uint256 fee = (milestones[milestoneId].amount * basepoints) / 10_000 + flatFee;
        uint256 releaseAmount = milestones[milestoneId].amount - fee;

        IERC20(erc20Token).safeTransfer(feeRecipient, fee);
        IERC20(erc20Token).safeTransfer(seller, releaseAmount);

        milestones[milestoneId].status = MilestoneStatus.Completed;
        currentMilestone++;

        emit MilestoneReleased(milestoneId, releaseAmount);
    }
}
