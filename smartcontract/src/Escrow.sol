// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

contract Escrow {
    using SafeERC20 for IERC20;

    enum MilestoneStatus {
        Pending,
        ReadyForRelease,
        Completed,
        Disputed
    }

    struct Milestone {
        uint256 amount;
        MilestoneStatus status;
        uint256 deadline;
        uint256 refundDeadline;
    }

    address public immutable buyer;
    address public immutable seller;
    address public immutable arbitrator;
    address public immutable erc20Token;
    address public immutable feeRecipient;
    uint256 public immutable flatFee;
    uint256 public immutable basepoints;
    uint256 public immutable releaseTimeout;

    Milestone[] public milestones;
    uint256 public currentMilestone;
    bool public isDisputed;
    address public disputeInitiator;
    uint256 public disputeTimestamp;

    event MilestoneReleased(uint256 indexed milestoneId, uint256 amount);
    event MilestoneDisputed(uint256 indexed milestoneId, address initiator);
    event DisputeResolved(uint256 indexed milestoneId, uint256 refundAmount, uint256 releaseAmount);
    event MilestoneCompleted(uint256 indexed milestoneId);
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

    constructor(
        address _buyer,
        address _seller,
        address _arbitrator,
        address _erc20Token,
        address _feeRecipient,
        uint256 _flatFee,
        uint256 _bps,
        uint256 milestoneCount,
        uint256 _releaseTimeline
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
        releaseTimeout = _releaseTimeline;

        for (uint256 i = 0; i < milestoneCount; i++) {
            milestones.push(Milestone({amount: 0, status: MilestoneStatus.Pending, deadline: 0, refundDeadline: 0}));
        }
    }

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

    function releaseMilestone(uint256 milestoneId) external onlyBuyer {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status == MilestoneStatus.Pending) {
            revert MilestoneNotReadyForRelease();
        }

        _releaseMilestoneFunds(milestoneId);
    }

    function disputeMilestone(uint256 milestoneId) external {
        if (msg.sender != buyer && msg.sender != seller) revert OnlyBuyerOrSellerAllowed();

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
