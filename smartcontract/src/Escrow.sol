// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Custom Errors
error OnlyBuyerAllowed();
error OnlySellerAllowed();
error OnlyArbitratorAllowed();
error InvalidBuyerOrSellerAddress();
error InvalidArbitratorAddress();
error InvalidERC20TokenAddress();
error InvalidFeeRecipientAddress();
error InvalidMilestone();
error MilestoneNotPending();
error MilestoneOutOfSequence();
error NoActiveDispute();
error InvalidSettlementAmounts();
error DeadlineNotReached();
error MilestoneNotReadyForRelease();
error RefundDeadlineNotReached();
error SellerNotResponded();
error SellerRequestedExtension();

contract Escrow {
    using SafeERC20 for IERC20;

    enum MilestoneStatus {
        Pending,
        Completed,
        Disputed,
        ReadyForRelease
    }
    struct Milestone {
        uint256 amount;
        MilestoneStatus status;
        uint256 deadline; 
        uint256 refundDeadline; 
        bool extensionRequested;
    }

    address public immutable buyer;
    address public immutable seller;
    address public immutable arbitrator;
    address public immutable erc20Token;
    address public immutable feeRecipient;
    uint256 public immutable flatFee;
    uint256 public immutable bpsFee;
    uint256 public constant RELEASE_TIMEOUT = 14 days; 

    Milestone[] public milestones;
    uint256 public currentMilestone;
    bool public isDisputed;

    event MilestoneReleased(uint256 milestoneId, uint256 amount);
    event MilestoneDisputed(uint256 milestoneId);
    event MilestoneSettled(
        uint256 milestoneId,
        uint256 refund,
        uint256 release
    );
    event MilestoneCompleted(uint256 milestoneId);
    event MilestoneRefunded(uint256 milestoneId, uint256 amount);
    event ExtensionRequested(uint256 milestoneId, uint256 newDeadline);
    event ExtensionApproved(uint256 milestoneId, uint256 newDeadline);
    event ExtensionDisputed(uint256 milestoneId);

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
        uint256 _bpsFee,
        uint256 milestoneCount
    ) {
        if (_buyer == address(0) || _seller == address(0))
            revert InvalidBuyerOrSellerAddress();
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipientAddress();

        buyer = _buyer;
        seller = _seller;
        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        feeRecipient = _feeRecipient;
        flatFee = _flatFee;
        bpsFee = _bpsFee;

        // Initialize milestones
        for (uint256 i = 0; i < milestoneCount; i++) {
            milestones.push(
                Milestone({
                    amount: 0,
                    status: MilestoneStatus.Pending,
                    deadline: 0,
                    refundDeadline: 0,
                    extensionRequested: false
                })
            );
        }
    }

    function fundMilestone(
        uint256 milestoneId,
        uint256 amount,
        uint256 timeline
    ) external onlyBuyer {
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        if (milestones[milestoneId].status != MilestoneStatus.Pending)
            revert MilestoneNotPending();

        milestones[milestoneId].amount = amount;
        milestones[milestoneId].refundDeadline = block.timestamp + timeline;
        milestones[milestoneId].deadline = block.timestamp + timeline;

        IERC20(erc20Token).safeTransferFrom(buyer, address(this), amount);
    }

    function markMilestoneComplete(uint256 milestoneId) external onlySeller {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status != MilestoneStatus.Pending)
            revert MilestoneNotPending();

        milestones[milestoneId].status = MilestoneStatus.ReadyForRelease;
        milestones[milestoneId].deadline = block.timestamp + RELEASE_TIMEOUT;
        milestones[milestoneId].refundDeadline = 0; // Cancel refund deadline

        emit MilestoneCompleted(milestoneId);
    }

    function requestExtension(uint256 milestoneId, uint256 newDeadline)
        external
        onlySeller
    {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status != MilestoneStatus.Pending)
            revert MilestoneNotPending();

        milestones[milestoneId].extensionRequested = true;
        milestones[milestoneId].refundDeadline = newDeadline; // Proposed new deadline

        emit ExtensionRequested(milestoneId, newDeadline);
    }

    function approveExtension(uint256 milestoneId, uint256 newDeadline)
        external
        onlyBuyer
    {
        if (milestones[milestoneId].status != MilestoneStatus.Pending)
            revert MilestoneNotPending();
        if (!milestones[milestoneId].extensionRequested)
            revert SellerNotResponded();

        milestones[milestoneId].refundDeadline = newDeadline;
        milestones[milestoneId].extensionRequested = false;

        emit ExtensionApproved(milestoneId, newDeadline);
    }

    function disputeExtension(uint256 milestoneId) external onlyBuyer {
        if (milestones[milestoneId].status != MilestoneStatus.Pending)
            revert MilestoneNotPending();
        if (!milestones[milestoneId].extensionRequested)
            revert SellerNotResponded();

        milestones[milestoneId].status = MilestoneStatus.Disputed;
        isDisputed = true;

        emit ExtensionDisputed(milestoneId);
    }

    function releaseMilestone(uint256 milestoneId) external onlyBuyer {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status != MilestoneStatus.ReadyForRelease)
            revert MilestoneNotReadyForRelease();

        _releaseMilestoneFunds(milestoneId);
    }

    function claimMilestoneFunds(uint256 milestoneId) external onlySeller {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (milestones[milestoneId].status != MilestoneStatus.ReadyForRelease)
            revert MilestoneNotReadyForRelease();
        if (block.timestamp < milestones[milestoneId].deadline)
            revert DeadlineNotReached();

        _releaseMilestoneFunds(milestoneId);
    }

    function refundMilestone(uint256 milestoneId) external onlyBuyer {
        if (milestoneId != currentMilestone) revert MilestoneOutOfSequence();
        if (block.timestamp < milestones[milestoneId].refundDeadline)
            revert RefundDeadlineNotReached();
        if (milestones[milestoneId].extensionRequested)
            revert SellerRequestedExtension();

        uint256 refundAmount = milestones[milestoneId].amount;
        milestones[milestoneId].amount = 0;
        milestones[milestoneId].status = MilestoneStatus.Completed;
        currentMilestone++;

        IERC20(erc20Token).safeTransfer(buyer, refundAmount);
        emit MilestoneRefunded(milestoneId, refundAmount);
    }

    function settleMilestone(
        uint256 milestoneId,
        uint256 refundAmount,
        uint256 releaseAmount
    ) external onlyArbitrator {
        if (!isDisputed) revert NoActiveDispute();
        if (milestoneId >= milestones.length) revert InvalidMilestone();
        if (milestones[milestoneId].status != MilestoneStatus.Disputed)
            revert MilestoneNotPending();

        uint256 totalAmount = refundAmount + releaseAmount;
        if (totalAmount != milestones[milestoneId].amount)
            revert InvalidSettlementAmounts();

        if (refundAmount > 0) {
            IERC20(erc20Token).safeTransfer(buyer, refundAmount);
        }
        if (releaseAmount > 0) {
            IERC20(erc20Token).safeTransfer(seller, releaseAmount);
        }

        milestones[milestoneId].status = MilestoneStatus.Completed;
        isDisputed = false;
        currentMilestone++;

        emit MilestoneSettled(milestoneId, refundAmount, releaseAmount);
    }

    function _releaseMilestoneFunds(uint256 milestoneId) internal {
        uint256 fee = (milestones[milestoneId].amount * bpsFee) /
            10_000 +
            flatFee;
        uint256 releaseAmount = milestones[milestoneId].amount - fee;

        IERC20(erc20Token).safeTransfer(feeRecipient, fee);
        IERC20(erc20Token).safeTransfer(seller, releaseAmount);

        milestones[milestoneId].status = MilestoneStatus.Completed;
        currentMilestone++;

        emit MilestoneReleased(milestoneId, releaseAmount);
    }
}
