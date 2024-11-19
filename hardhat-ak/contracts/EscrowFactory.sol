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

    /// @notice Counter for generating unique invoice IDs
    uint256 private invoiceCounter;

    /// @notice Prefix for invoice IDs
    string private constant PREFIX = "INV";

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
     * @notice Generates a unique invoice ID
     * @return string The generated invoice ID
     */
    function _generateInvoiceId() private returns (string memory) {
        invoiceCounter++;
        // Convert counter and timestamp to strings and concatenate
        return string(
            abi.encodePacked(
                PREFIX,
                "-",
                _uintToString(block.timestamp),
                "-",
                _uintToString(invoiceCounter)
            )
        );
    }

    /**
     * @notice Converts a uint to a string
     * @param _i The uint to convert
     * @return string The resulting string
     */
    function _uintToString(uint256 _i) private pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 temp = _i;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_i != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Creates and tracks a new escrow contract instance with auto-generated invoice ID
     * @param buyer Address of the buyer
     * @param seller Address of the seller
     * @param completionDuration Duration for completion in days
     * @param releaseTimeout Timeout duration for release in days
     * @param buyerEmailAddress Email address of the buyer
     * @param buyerFirstName First name of the buyer
     * @param buyerLastName Last name of the buyer
     * @param productName Name of the product
     * @param productDescription Description of the product
     * @param productPrice Price of the product
     * @return generatedInvoiceId The generated unique invoice ID
     * @return escrowAddr The address of the newly created escrow contract
     */

    function createEscrow(
        // string calldata invoiceId,
        address buyer,
        address seller,
        uint256 completionDuration,
        uint256 releaseTimeout,
        string memory buyerEmailAddress,
        string memory buyerFirstName,
        string memory buyerLastName,
        string memory productName,
        string memory productDescription,
        uint256 productPrice
    ) external returns (string memory generatedInvoiceId, address escrowAddr) {
        // Generate unique invoice ID
        generatedInvoiceId = _generateInvoiceId();
    
        // Check if escrow already exists
        if (escrows[generatedInvoiceId].escrowAddress != address(0)) {
            revert EscrowAlreadyExists();
        }

        Flexiscrow escrow = new Flexiscrow(
            generatedInvoiceId,
            buyer,
            seller,
            arbitrator,
            erc20Token,
            flatFee,
            basepoints,
            completionDuration,
            releaseTimeout,
            buyerEmailAddress,
            buyerFirstName,
            buyerLastName,
            productName,
            productDescription,
            productPrice                       
        );
        
        escrowAddr = address(escrow);
        
        // Store escrow details
        escrows[generatedInvoiceId] = EscrowDetails({
            escrowAddress: escrowAddr,
            buyer: buyer,
            seller: seller,
            createdAt: block.timestamp
        });

        // Track invoice IDs
        allInvoiceIds.push(generatedInvoiceId);

        emit EscrowCreated(generatedInvoiceId, escrowAddr, buyer, seller);
        return (generatedInvoiceId, escrowAddr);
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

}
