// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//Custom Errors
error OnlyBuyerAllowed();
error OnlySellerAllowed();
error OnlyArbitratorAllowed();
error InvalidBuyerOrSellerAddress();
error InvalidArbitratorAddress();
error InvalidERC20TokenAddress();
error NoActiveDispute();
error InvalidSettlementAmounts();
error DeadlineNotReached();
error InvalidFee();
error AlreadyFunded();
error NotReadyForRelease();
error NotInProgress();
error InvalidStatus();
error DeadlinePassed();
error ExtensionNotRequested();
error InvalidExtensionDuration();
error ExtensionResponseDeadlinePassed();
error NoExtensionRequested();
error ExtensionResponseTimeNotPassed();

/**
 * @title Flexiscrow
 * @author Roib Yusuf
 * @notice A flexible escrow contract for handling ERC20 token transactions between buyers and sellers
 * @dev Implements a sophisticated escrow system with extension requests, dispute resolution, and penalty calculations
 */
contract Flexiscrow {
    using SafeERC20 for IERC20;

    /**
     * @notice Enum representing the possible states of the escrow
     * @dev The escrow progresses through these states based on participant actions
     */
    enum EscrowStatus {
        Unfunded, // Initial state
        InProgress, // Escrow is funded and work can begin
        ExtensionRequested, // Seller has requested deadline extension
        ReadyForRelease, // Work is complete and ready for buyer review
        Completed, // Transaction has been completed
        Disputed // Dispute has been raised
    }

    /**
     * @notice Struct containing time-related configuration
     * @param completionDuration Duration allowed for completion in seconds
     * @param deadline Current deadline timestamp
     * @param originalDeadline Initial deadline timestamp before any extensions
     */
    struct TimeConfig {
        uint256 completionDuration;
        uint256 deadline;
        uint256 originalDeadline;
    }

    /**
     * @notice Struct containing data related to deadline extensions
     * @param extensionDuration Requested extension duration in seconds
     * @param extensionRequestTimestamp When the extension was requested
     * @param extensionApprovedTimestamp When the extension was approved
     * @param approvedExtensionDeadline New deadline after extension approval
     */
    struct ExtensionData {
        uint256 extensionDuration;
        uint256 extensionRequestTimestamp;
        uint256 extensionApprovedTimestamp;
        uint256 approvedExtensionDeadline;
    }

    /**
     * @notice Struct containing dispute-related information
     * @param isDisputed Whether the escrow is currently disputed
     * @param disputeInitiator Address that initiated the dispute
     * @param disputeTimestamp When the dispute was initiated
     */
    struct DisputeData {
        bool isDisputed;
        address disputeInitiator;
        uint256 disputeTimestamp;
    }

    /**
     * @notice Struct containing the current state of the escrow
     * @param currentStatus Current status of the escrow
     * @param previousStatus Previous status before the last state change
     * @param escrowAmount Amount of tokens in escrow
     * @param readyTimestamp When the seller marked the work as ready
     */
    struct EscrowState {
        EscrowStatus currentStatus;
        EscrowStatus previousStatus;
        uint256 escrowAmount;
        uint256 readyTimestamp;
    }

    /// @notice Penalty rate in basis points (1.5% per day)
    uint256 constant PENALTY_RATE = 150;
    /// @notice Timeout period for various operations
    uint256 constant TIMEOUT = 3 days;
    /// @notice Unique identifier for the associated invoice
    string public invoiceId;
    /// @notice Address of the buyer
    address immutable buyer;
    /// @notice Address of the seller
    address immutable seller;
    /// @notice Address of the arbitrator
    address immutable arbitrator;
    /// @notice Address of the ERC20 token used for payment
    address immutable erc20Token;
    /// @notice Flat fee charged by the arbitrator
    uint256 immutable flatFee;
    /// @notice Fee percentage in basepoints (1 basepoint = 0.01%)
    uint256 immutable basepoints;

    TimeConfig public timeConfig;
    ExtensionData public extensionData;
    DisputeData public disputeData;
    EscrowState public state;

    /// @notice Emitted when the escrow is funded
    event EscrowFunded(uint256 amount);
    /// @notice Emitted when funds are released to the seller
    event FundsReleased(uint256 amount, uint256 penalty);
    /// @notice Emitted when seller requests a deadline extension
    event ExtensionRequested(
        uint256 extensionDuration,
        uint256 requestTimestamp
    );
    /// @notice Emitted when buyer approves an extension request
    event ExtensionApproved(uint256 approvedTimestamp, uint256 newDeadline);
    /// @notice Emitted when a dispute is initiated
    event DisputeInitiated(address initiator, string reason);
    /// @notice Emitted when a dispute is resolved
    event DisputeResolved(uint256 refundAmount, uint256 releaseAmount);
    /// @notice Emitted when seller marks work as ready
    event MarkedReady(uint256 timestamp);
    /// @notice Emitted when funds are refunded to the buyer
    event FundsRefunded(uint256 amount);

    /// @notice Ensures only the buyer can call the function
    modifier onlyBuyer() {
        if (msg.sender != buyer) revert OnlyBuyerAllowed();
        _;
    }

    /// @notice Ensures only the seller can call the function
    modifier onlySeller() {
        if (msg.sender != seller) revert OnlySellerAllowed();
        _;
    }

    /// @notice Ensures only the arbitrator can call the function
    modifier onlyArbitrator() {
        if (msg.sender != arbitrator) revert OnlyArbitratorAllowed();
        _;
    }

    /**
     * @notice Constructs a new Flexiscrow contract
     * @dev Sets up the escrow with initial parameters and validates addresses
     * @param _invoiceId Unique identifier for the invoice
     * @param _buyer Address of the buyer
     * @param _seller Address of the seller
     * @param _arbitrator Address of the arbitrator
     * @param _erc20Token Address of the ERC20 token used for payment
     * @param _flatFee Flat fee charged by the arbitrator
     * @param _bps Percentage fee in basis points
     * @param _completionDuration Duration allowed for completion in days
     */
    constructor(
        string memory _invoiceId,
        address _buyer,
        address _seller,
        address _arbitrator,
        address _erc20Token,
        uint256 _flatFee,
        uint256 _bps,
        uint256 _completionDuration
    ) {
        if (_buyer == address(0) || _seller == address(0)) {
            revert InvalidBuyerOrSellerAddress();
        }
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();

        invoiceId = _invoiceId;
        buyer = _buyer;
        seller = _seller;
        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        flatFee = _flatFee;
        basepoints = _bps;

        timeConfig = TimeConfig({
            completionDuration: _completionDuration * 1 days,
            deadline: 0,
            originalDeadline: 0
        });
    }

    /**
     * @notice Funds the escrow with tokens
     * @param amount Amount of tokens to fund
     * @param _fee Amount of fee to be charged for the escrow
     * @dev Transfers fee to the arbitrator
     * @dev Transfers tokens from buyer to contract
     * @dev Set the deadline for the seller to complete the task
     * Example of fee calculation:
     * If the flatFee is set to 50, and basepoints is 250 (2.5% fee),
     * and the amount is 1,000, the fee would be:
     * 50 + (1000 * 250) / 10,000 = 75
     */
    function fundEscrow(uint256 amount, uint256 _fee) external onlyBuyer {
        if (state.currentStatus != EscrowStatus.Unfunded)
            revert AlreadyFunded();
        uint256 fee = (amount * basepoints) / 10_000 + flatFee;
        if (_fee < fee) revert InvalidFee();

        IERC20(erc20Token).safeTransferFrom(buyer, arbitrator, fee);
        state.escrowAmount = amount;
        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.InProgress;

        timeConfig.deadline = block.timestamp + timeConfig.completionDuration;
        timeConfig.originalDeadline = timeConfig.deadline;

        IERC20(erc20Token).safeTransferFrom(buyer, address(this), amount);
        emit EscrowFunded(amount);
    }

    /**
     * @notice Allows seller to request a deadline extension
     * @dev Changes escrow status to ExtensionRequested
     * @param _extensionDuration Requested extension duration in days
     */
    function requestExtension(uint256 _extensionDuration) external onlySeller {
        if (state.currentStatus != EscrowStatus.InProgress)
            revert NotInProgress();
        if (_extensionDuration < 1) revert InvalidExtensionDuration();

        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.ExtensionRequested;
        extensionData.extensionDuration = _extensionDuration * 1 days;
        extensionData.extensionRequestTimestamp = block.timestamp;

        emit ExtensionRequested(_extensionDuration, block.timestamp);
    }

    /**
     * @notice Allows buyer to approve an extension request
     * @dev Updates deadline and returns escrow to InProgress status
     */
    function approveExtension() external onlyBuyer {
        if (state.currentStatus != EscrowStatus.ExtensionRequested)
            revert ExtensionNotRequested();

        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.InProgress;
        extensionData.extensionApprovedTimestamp = block.timestamp;

        if (block.timestamp < timeConfig.originalDeadline) {
            extensionData.approvedExtensionDeadline =
                timeConfig.originalDeadline +
                extensionData.extensionDuration;
        } else {
            extensionData.approvedExtensionDeadline =
                block.timestamp +
                extensionData.extensionDuration;
        }

        emit ExtensionApproved(
            extensionData.extensionApprovedTimestamp,
            extensionData.approvedExtensionDeadline
        );
    }

    /**
     * @notice Allows seller to open a dispute if buyer doesn't respond to extension
     * @dev Changes status to Disputed if buyer hasn't responded within timeout
     */
    function openDisputeForExtension() external onlySeller {
        if (state.currentStatus != EscrowStatus.ExtensionRequested)
            revert NoExtensionRequested();
        if (
            block.timestamp < extensionData.extensionRequestTimestamp + TIMEOUT
        ) {
            revert ExtensionResponseTimeNotPassed();
        }

        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.Disputed;
        disputeData.isDisputed = true;
        disputeData.disputeInitiator = msg.sender;
        disputeData.disputeTimestamp = block.timestamp;

        emit DisputeInitiated(
            msg.sender,
            "Buyer did not respond to extension request"
        );
    }

    /**
     * @notice Marks the work as complete by the seller
     * @dev Changes status to ReadyForRelease
     * @dev Sets release deadline for buyer action
     */
    function markReady() external onlySeller {
        if (state.currentStatus != EscrowStatus.InProgress)
            revert NotInProgress();

        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.ReadyForRelease;
        state.readyTimestamp = block.timestamp;
        timeConfig.deadline = block.timestamp + TIMEOUT;

        emit MarkedReady(block.timestamp);
    }

    /**
     * @notice Calculates late delivery penalty
     * @dev Penalty is calculated based on days late and penalty rate
     * @return uint256 Penalty amount in tokens
     */
    function calculatePenalty() public view returns (uint256) {
        if (
            extensionData.extensionApprovedTimestamp <
            timeConfig.originalDeadline
        ) {
            if (state.readyTimestamp <= timeConfig.originalDeadline) return 0;
            uint256 daysLate = (state.readyTimestamp -
                timeConfig.originalDeadline) / 1 days;
            if (daysLate == 0) return 0;
            return (state.escrowAmount * PENALTY_RATE * daysLate) / 10000;
        } else {
            uint256 daysLate = (extensionData.extensionApprovedTimestamp -
                state.readyTimestamp) / 1 days;
            if (daysLate == 0) return 0;
            return (state.escrowAmount * PENALTY_RATE * daysLate) / 10000;
        }
    }

    /**
     * @notice Allows buyer to release funds to seller
     * @dev Transfers funds minus any penalties
     */
    function releaseFunds() external onlyBuyer {
        if (state.currentStatus != EscrowStatus.ReadyForRelease)
            revert NotReadyForRelease();

        _releaseFunds();
    }

    /**
     * @notice Allows seller to claim funds after review period
     * @dev Transfers funds if buyer hasn't responded within timeout
     */
    function claimFunds() external onlySeller {
        if (state.currentStatus != EscrowStatus.ReadyForRelease)
            revert NotReadyForRelease();
        if (block.timestamp < timeConfig.deadline) revert DeadlineNotReached();
        _releaseFunds();
    }

    /**
     * @notice Initiates a dispute for the escrow if status is either in progress or extenstion requested or ready for release
     * @dev Can be called by only buyer
     * @dev Changes status to Disputed
     */

    function initiateDispute() external onlyBuyer {
        if (
            state.currentStatus != EscrowStatus.InProgress &&
            state.currentStatus != EscrowStatus.ExtensionRequested &&
            state.currentStatus != EscrowStatus.ReadyForRelease
        ) {
            revert InvalidStatus();
        }

        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.Disputed;
        disputeData.isDisputed = true;
        disputeData.disputeInitiator = msg.sender;
        disputeData.disputeTimestamp = block.timestamp;

        emit DisputeInitiated(msg.sender, "Buyer initiated dispute");
    }

    /**
     * @notice Resolves a disputed escrow
     * @param refundAmount Amount to refund to buyer
     * @param releaseAmount Amount to release to seller
     * @dev Can only be called by arbitrator
     * @dev Sum of refund and release must equal escrow amount
     */
    function resolveDispute(
        uint256 refundAmount,
        uint256 releaseAmount
    ) external onlyArbitrator {
        if (!disputeData.isDisputed) revert NoActiveDispute();
        if (state.currentStatus != EscrowStatus.Disputed)
            revert NoActiveDispute();
        if (refundAmount + releaseAmount != state.escrowAmount) {
            revert InvalidSettlementAmounts();
        }

        if (refundAmount > 0) {
            IERC20(erc20Token).safeTransfer(buyer, refundAmount);
        }
        if (releaseAmount > 0) {
            IERC20(erc20Token).safeTransfer(seller, releaseAmount);
        }

        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.Completed;
        disputeData.isDisputed = false;
        disputeData.disputeInitiator = address(0);
        disputeData.disputeTimestamp = 0;

        emit DisputeResolved(refundAmount, releaseAmount);
    }

    /**
     * @dev Internal function to release escrow funds
     */
    function _releaseFunds() internal {
        uint256 penalty = calculatePenalty();
        uint256 finalAmount = state.escrowAmount - penalty;

        IERC20(erc20Token).safeTransfer(seller, finalAmount);
        if (penalty > 0) {
            IERC20(erc20Token).safeTransfer(buyer, penalty);
        }
        state.previousStatus = state.currentStatus;
        state.currentStatus = EscrowStatus.Completed;
        emit FundsReleased(finalAmount, penalty);
    }

  /**
     * @notice Returns the addresses of the buyer, seller, and arbitrator
     * @dev Provides external visibility for accessing the key parties involved in the escrow
     * @return buyer Address of the buyer
     * @return seller Address of the seller
     * @return arbitrator Address of the arbitrator
     */
    function getParties() external view returns (address, address, address) {
        return (buyer, seller, arbitrator);
    }
}
