// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Escrow.sol";

/**
 * @title EscrowFactory
 * @author  Roqib Yusuf's implementation
 * @notice Factory contract for deploying and tracking escrow instances
 * @dev Manages creation, configuration and tracking of escrow contracts
 */
contract EscrowFactory is Ownable {
    /// @notice Immutable arbitrator address for all created escrows
    address public immutable arbitrator;

    /// @notice Immutable token address used for payments
    address public immutable erc20Token;

    /// @notice Time window in days for buyers to release funds
    uint256 public releaseTimeout;

    /// @notice Fixed fee amount per milestone
    uint256 public flatFee;

    /// @notice Fee percentage in basepoints
    uint256 public basepoints;

    /// @notice Struct to store escrow details
    struct EscrowDetails {
        address escrowAddress;
        address buyer;
        address seller;
        uint256 createdAt;
    }

    /// @notice Mapping from invoiceId to escrow details
    mapping(string => EscrowDetails) public escrows;

    /// @notice Array to store all invoice IDs
    string[] public allInvoiceIds;

    event EscrowCreated(
        string indexed invoiceId,
        address indexed escrow,
        address indexed buyer,
        address seller
    );
    event FeeUpdated(uint256 flatFee, uint256 basepoints);
    event TimeOutUpdated(uint256 releaseTimeout);

    error EscrowAlreadyExists();
    error InvalidInvoiceId();

    constructor(
        address _arbitrator,
        address _erc20Token,
        uint256 _flatFee,
        uint256 _bps
    ) Ownable(msg.sender) {
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();

        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        flatFee = _flatFee;
        basepoints = _bps;
    }

    /**
     * @notice Creates and tracks a new escrow contract instance
     * @param invoiceId Unique identifier for the escrow
     * @param buyer Address of the buyer
     * @param seller Address of the seller
     * @return Address of the newly created escrow contract
     */
    function createEscrow(
        string calldata invoiceId,
        address buyer,
        address seller
    ) external returns (address) {
        // Check if invoiceId is empty
        if (bytes(invoiceId).length == 0) revert InvalidInvoiceId();

        // Check if escrow already exists
        if (escrows[invoiceId].escrowAddress != address(0)) {
            revert EscrowAlreadyExists();
        }

        Escrow escrow = new Escrow(
            invoiceId,
            buyer,
            seller,
            arbitrator,
            erc20Token,
            flatFee,
            basepoints,
            releaseTimeout
        );

        // Store escrow details
        escrows[invoiceId] = EscrowDetails({
            escrowAddress: address(escrow),
            buyer: buyer,
            seller: seller,
            createdAt: block.timestamp
        });

        // Track invoice IDs
        allInvoiceIds.push(invoiceId);

        emit EscrowCreated(invoiceId, address(escrow), buyer, seller);
        return address(escrow);
    }

    /**
     * @notice Get the total number of escrows created
     * @return Total number of escrows
     */
    function getTotalEscrows() external view returns (uint256) {
        return allInvoiceIds.length;
    }

    /**
     * @notice Get escrow details by invoice ID
     * @param invoiceId The invoice ID to query
     * @return escrowAddress The address of the escrow contract
     * @return buyer The buyer's address
     * @return seller The seller's address
     * @return createdAt The creation timestamp
     */
    function getEscrowDetails(
        string calldata invoiceId
    )
        external
        view
        returns (
            address escrowAddress,
            address buyer,
            address seller,
            uint256 createdAt
        )
    {
        EscrowDetails memory details = escrows[invoiceId];
        return (
            details.escrowAddress,
            details.buyer,
            details.seller,
            details.createdAt
        );
    }

    /**
     * @notice Updates fee structure
     * @param _flatFee New fixed fee amount
     * @param _bps New fee percentage in basepoints
     */
    function updateFees(uint256 _flatFee, uint256 _bps) external onlyOwner {
        flatFee = _flatFee;
        basepoints = _bps;
        emit FeeUpdated(flatFee, basepoints);
    }

    /**
     * @notice Updates release timeout period
     * @param _releaseTimeout New timeout duration in days
     */
    function updateReleaseTimeout(uint256 _releaseTimeout) external onlyOwner {
        releaseTimeout = _releaseTimeout * 1 days;
        emit TimeOutUpdated(_releaseTimeout);
    }
}
