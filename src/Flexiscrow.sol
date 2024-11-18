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

/**
 * @title Escrow
 * @author Roqib Yusuf's implementation
 * @notice A simple escrow contract for ERC20 tokens with arbitration capabilities
 * @dev Implements a secure payment system with a single escrow period
 */
contract Flexiscrow {
    using SafeERC20 for IERC20;

    /**
     * @notice Status of the escrow
     * @param Unfunded Initial state, awaiting funding from buyer
     * @param InProgress Escrow has been funded and in progress but work not marked complete
     * @param ReadyForRelease Marked as complete by seller, awaiting buyer release
     * @param Completed Funds have been released or refunded
     * @param Disputed Under dispute resolution by arbitrator
     */
    enum EscrowStatus {
        Unfunded,
        InProgress,
        ExtensionRequested,
        ReadyForRelease,
        Completed,
        Disputed
    }

    string public invoiceId;
    /// @notice Address of the buyer who deposits funds
    address private immutable buyer;
    /// @notice Address of the seller who receives funds
    address private immutable seller;
    /// @notice Address of the arbitrator who can resolve disputes
    address private immutable arbitrator;
    /// @notice Address of the ERC20 token used for payments
    address private immutable erc20Token;
    /// @notice Fixed fee amount charged
    uint256 private immutable flatFee;
    /// @notice Fee percentage in basepoints (1 basepoint = 0.01%)
    uint256 private immutable basepoints;
    /// @notice Duration for the seller to complete the task
    uint256 public immutable completionDuration;
    /// @notice Duration until funds can be claimed by seller after marking ready
    uint256 public immutable releaseTimeout;

    /// @notice Current status of the escrow
    EscrowStatus public status;
    /// @notice Amount held in escrow
    uint256 public escrowAmount;
    /// @notice Deadline for buyer to act after seller marks ready
    uint256 public deadline;
    /// @notice Flag indicating if there's an active dispute
    bool public isDisputed;
    /// @notice Address that initiated the current dispute
    address public disputeInitiator;
    /// @notice Timestamp when the current dispute was initiated
    uint256 public disputeTimestamp;

    /// @notice Extension duration that was requested
    uint256 public extensionDuration;

    /**
     * @notice Emitted when escrow is funded by buyer
     * @param amount Amount of tokens deposited
     */
    event EscrowFunded(uint256 amount);

    /**
     * @notice Emitted when funds are released to seller
     * @param amount Amount of tokens released (excluding fees)
     */
    event FundsReleased(uint256 amount);

    event ExtensionRequested(
        uint256 extensionDuration,
        uint256 currentDeadline
    );
    event ExtensionApproved(uint256 oldDeadline, uint256 newDeadline);

    /**
     * @notice Emitted when a dispute is initiated
     * @param initiator Address that initiated the dispute
     */
    event DisputeInitiated(address initiator);

    /**
     * @notice Emitted when arbitrator resolves a dispute
     * @param refundAmount Amount refunded to buyer
     * @param releaseAmount Amount released to seller
     */
    event DisputeResolved(uint256 refundAmount, uint256 releaseAmount);

    /**
     * @notice Emitted when seller marks work as ready for release
     */
    event MarkedReady();

    /**
     * @notice Emitted when funds are refunded to buyer
     * @param amount Amount refunded
     */
    event FundsRefunded(uint256 amount);

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
     * @param _flatFee Fixed fee amount
     * @param _bps Fee percentage in basepoints
     * @param _completionDuration Time window for the seller to complete the task
     * @param _releaseTimeout Time window for buyer to release funds
     * @dev Initializes the contract with Unfunded status
     */
    constructor(
        string memory _invoiceId,
        address _buyer,
        address _seller,
        address _arbitrator,
        address _erc20Token,
        uint256 _flatFee,
        uint256 _bps,
        uint256 _completionDuration,
        uint256 _releaseTimeout
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
        completionDuration = _completionDuration * 1 days;
        releaseTimeout = _releaseTimeout * 1 days;
        status = EscrowStatus.Unfunded;
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
        if (status != EscrowStatus.Unfunded) revert AlreadyFunded();
        uint256 fee = (amount * basepoints) / 10_000 + flatFee;
        if (_fee < fee) revert InvalidFee();
        IERC20(erc20Token).safeTransferFrom(buyer, arbitrator, fee);
        escrowAmount = amount;
        status = EscrowStatus.InProgress;
        deadline = block.timestamp + completionDuration;
        IERC20(erc20Token).safeTransferFrom(buyer, address(this), amount);
        emit EscrowFunded(amount);
    }

    /**
     * @notice Marks the work as complete by the seller
     * @dev Changes status to ReadyForRelease
     * @dev Sets release deadline for buyer action
     */
    function markReady() external onlySeller {
        if (status != EscrowStatus.InProgress) revert NotInProgress();

        status = EscrowStatus.ReadyForRelease;
        deadline = block.timestamp + releaseTimeout;
        emit MarkedReady();
    }

    /**
     * @notice Allows the seller to request an extension to the escrow deadline.
     * @dev The escrow must be in the InProgress state for an extension to be requested.
     * @param _extensionDuration The duration (in days) by which the seller wants to extend the escrow deadline.
     * @custom:requirements
     * - Escrow status must be `InProgress`.
     * - `_extensionDuration` must be greater than or equal to 1 day.
     * @custom:emits Emits `ExtensionRequested` event on successful extension request.
     */
    function requestExtension(uint256 _extensionDuration) external onlySeller {
        if (status != EscrowStatus.InProgress) revert NotInProgress();
        if (_extensionDuration < 1) {
            revert InvalidExtensionDuration();
        }
        status = EscrowStatus.ExtensionRequested;
        extensionDuration = _extensionDuration * 1 days;
        emit ExtensionRequested(_extensionDuration, deadline);
    }

    /**
     * @notice Allows the buyer to approve an extension request made by the seller.
     * @dev The escrow must be in the ExtensionRequested state for approval.
     * @custom:effects Updates the escrow deadline by adding the requested extension duration.
     * @custom:requirements
     * - Escrow status must be `ExtensionRequested`.
     * @custom:emits Emits `ExtensionApproved` event with the old and new deadlines.
     */
    function approveExtension() external onlyBuyer {
        if (status != EscrowStatus.ExtensionRequested)
            revert ExtensionNotRequested();
        uint256 oldDeadline = deadline;
        deadline = block.timestamp + extensionDuration;
        extensionDuration = 0;
        status = EscrowStatus.InProgress;
        emit ExtensionApproved(oldDeadline, deadline);
    }

    /**
     * @notice Releases escrow funds to seller
     * @dev Can only be called by buyer
     * @dev Transfers funds to seller and fees to fee recipient
     */
    function releaseFunds() external onlyBuyer {
        if (status != EscrowStatus.ReadyForRelease) revert NotReadyForRelease();
        _releaseFunds();
    }

    /**
     * @notice Claims escrow funds after buyer timeout
     * @dev Can only be called by seller after deadline
     * @dev Transfers funds to seller and fees to fee recipient
     */
    function claimFunds() external onlySeller {
        if (status != EscrowStatus.ReadyForRelease) revert NotReadyForRelease();
        if (block.timestamp < deadline) revert DeadlineNotReached();

        _releaseFunds();
    }

    /**
     * @notice Initiates a dispute for the escrow if status is either in progress or extenstion requested or ready for release
     * @dev Can be called by only buyer
     * @dev Changes status to Disputed
     */
    function initiateDispute() external onlyBuyer {
        if (
            status != EscrowStatus.InProgress &&
            status != EscrowStatus.ExtensionRequested &&
            status != EscrowStatus.ReadyForRelease
        ) {
            revert InvalidStatus();
        }

        status = EscrowStatus.Disputed;
        isDisputed = true;
        disputeInitiator = msg.sender;
        disputeTimestamp = block.timestamp;
        emit DisputeInitiated(msg.sender);
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
        if (!isDisputed) revert NoActiveDispute();
        if (status != EscrowStatus.Disputed) revert NoActiveDispute();
        if (refundAmount + releaseAmount != escrowAmount) {
            revert InvalidSettlementAmounts();
        }

        if (refundAmount > 0) {
            IERC20(erc20Token).safeTransfer(buyer, refundAmount);
        }
        if (releaseAmount > 0) {
            IERC20(erc20Token).safeTransfer(seller, releaseAmount);
        }

        status = EscrowStatus.Completed;
        isDisputed = false;
        disputeInitiator = address(0);
        disputeTimestamp = 0;
        emit DisputeResolved(refundAmount, releaseAmount);
    }

    /**
     * @dev Internal function to release escrow funds
     */
    function _releaseFunds() internal {
        IERC20(erc20Token).safeTransfer(seller, escrowAmount);
        status = EscrowStatus.Completed;
        emit FundsReleased(escrowAmount);
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
