// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Escrow.sol";

/**
 * @title EscrowFactory
  * @author Roqib Yusuf
 * @notice Factory contract for deploying new escrow instances
 * @dev Manages creation and configuration of escrow contracts
 */
contract EscrowFactory is Ownable {
    /// @notice Immutable arbitrator address for all created escrows. This is using our MultiSig contract
    address public immutable arbitrator;

    /// @notice Immutable token address used for payments
    address public immutable erc20Token;

    /// @notice Immutable fee recipient address
    address public immutable feeRecipient;

    /// @notice Time window in days for buyers to release funds
    uint256 public releaseTimeout; //Example: 14days

    /// @notice Fixed fee amount per milestone
    uint256 public flatFee;

    /// @notice Fee percentage in basepoints.  1 basepoint is 1/100 of 1%, also 0.01% or 1/10000.
    uint256 public basepoints;

    event EscrowCreated(
        address indexed escrow,
        address indexed buyer,
        address indexed seller
    );
    event FeeUpdated(uint256 flatFee, uint256 basepoints);
    event TimeOutUpdated(uint256 releaseTimeout);

    /**
     * @notice Creates a new EscrowFactory contract
     * @param _arbitrator Address of the arbitrator
     * @param _erc20Token Address of the payment token
     * @param _feeRecipient Address receiving fees
     * @param _flatFee Fixed fee amount
     * @param _bps Fee percentage in basepoints
     */
    constructor(
        address _arbitrator,
        address _erc20Token,
        address _feeRecipient,
        uint256 _flatFee,
        uint256 _bps
    ) Ownable(msg.sender) {
        if (_arbitrator == address(0)) revert InvalidArbitratorAddress();
        if (_erc20Token == address(0)) revert InvalidERC20TokenAddress();
        if (_feeRecipient == address(0)) revert InvalidFeeRecipientAddress();

        arbitrator = _arbitrator;
        erc20Token = _erc20Token;
        feeRecipient = _feeRecipient;
        flatFee = _flatFee;
        basepoints = _bps;
    }

    /**
     * @notice Creates a new escrow contract instance
     * @param buyer Address of the buyer
     * @param seller Address of the seller
     * @param milestoneCount Number of milestones
     * @return Address of the newly created escrow contract
     */
    function createEscrow(
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
            basepoints,
            milestoneCount,
            releaseTimeout
        );

        emit EscrowCreated(address(escrow), buyer, seller);
        return address(escrow);
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
