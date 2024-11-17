# Flexiscrow

## **Overview**

Flexiscrow allows buyers and sellers to enter into secure transactions using an escrow service. An arbitrator resolves disputes when necessary. Each transaction is represented as a unique escrow contract, deployed and managed via the `EscrowFactory`. The `Multisig` contract centralizes dispute records and aids in tracking resolutions.

---

## **Contracts Overview**

### **1. EscrowFactory**
- **Purpose**: Deploys and manages multiple escrow contracts.
- **Key Features**:
  - Creates new escrow instances.
  - Tracks deployed escrow contracts.
  - Emits events for contract creation.

### **2. Escrow**
- **Purpose**: Handles the escrow lifecycle for individual transactions.
- **Key Features**:
  - Supports funding, marking work as complete, releasing funds, and disputes.
  - Charges flat and percentage-based fees.
  - Transfers tokens securely between buyer, seller, and arbitrator.

### **3. Multisig Contract**
The `Multisig` contract serves as a governance layer to handle escrow disputes. It:
- Manages a list of authorized signers who can create, vote on, and execute proposals.
- Allows for the adjustment of governance parameters such as adding/removing signers and updating quorum.
- Enables settling escrow, facilitating fast dispute resolution.

---

## **DApp Flow**

### **1. Setup**
1. **Deployment**:
   - Deploy the `EscrowFactory` contract to enable the creation of individual escrow contracts.
   - Deploy the `Multisig` contract for dispute resolution and receiving fees.

2. **Configuration**:
   - Set roles (buyer, seller, arbitrator -- which is the multisig contract).
   - Configure flat fee, percentage fee (basepoints), and timeout values.

---

### **2. Transaction Lifecycle**

#### **Step 1: Create an Escrow**
- The buyer or seller interacts with the DApp to initiate a new escrow.
- The `EscrowFactory` deploys a new `Escrow` contract instance with:
  - Buyer address.
  - Seller address.
  - Arbitrator address.
  - ERC20 token address.
  - Fees and timeout configuration.
- **Event Emitted**: `EscrowCreated`.

#### **Step 2: Fund the Escrow**
- The buyer deposits the agreed amount and the fee into the `Escrow` contract.
- The contract transitions to the **Funded** state.
- **Event Emitted**: `EscrowFunded`.

#### **Step 3: Mark Work Ready**
- The seller marks the work as complete via the `markReady()` function.
- The contract transitions to the **ReadyForRelease** state.
- A timeout period (`releaseTimeout`) is set for buyer action.
- **Event Emitted**: `MarkedReady`.

#### **Step 4: Release Funds**
- The buyer reviews the work and releases funds using the `releaseFunds()` function.
- The contract transitions to the **Completed** state.
- **Event Emitted**: `FundsReleased`.

#### **Step 5: Claim Funds (if timeout passes)**
- If the buyer takes no action within the timeout period, the seller can claim the funds using the `claimFunds()` function.
- **Event Emitted**: `FundsReleased`.

---

### **3. Dispute Resolution**

#### **Step 1: Initiate a Dispute**
- The seller can call `initiateDispute()` to escalate the issue.
- The contract transitions to the **Disputed** state.
- The `Escrow` contract logs the dispute.
- **Event Emitted**: `DisputeInitiated`.

#### **Step 2: Resolve a Dispute**
- The arbitrator reviews the dispute and calls `resolveDispute()` on the `Escrow` contract with the amounts to:
  - Refund the buyer.
  - Release funds to the seller.
- The contract transitions to the **Completed** state.
- The `Escrow` contract logs the resolution.
- **Event Emitted**: `DisputeResolved`.

---

## **Roles**

### **1. Buyer**
- Funds the escrow.
- Reviews and approves the release of funds.
- Can initiate a dispute if dissatisfied or seller not delivered.

### **2. Seller**
- Delivers the agreed service or product.
- Marks work as ready.
- Claims funds after timeout or via buyer release.

### **3. Arbitrator**
- Resolves disputes.
- Ensures fair distribution of funds during disputes.

---

## **Events**

### **EscrowFactory**
- `EscrowCreated(address escrowAddress)`: Triggered when a new escrow contract is deployed.

### **Escrow**
- `EscrowFunded(uint256 amount)`: Triggered when the buyer funds the escrow.
- `MarkedReady()`: Triggered when the seller marks work as complete.
- `FundsReleased(uint256 amount)`: Triggered when funds are released to the seller.
- `DisputeInitiated(address initiator)`: Triggered when a dispute is initiated.
- `DisputeResolved(uint256 refundAmount, uint256 releaseAmount)`: Triggered when a dispute is resolved.


---

## **Technical Details**

### **Fee Calculation**
- Flat Fee (`flatFee`) + Percentage Fee (`basepoints`).
- Example:
  - Amount: 1,000 tokens.
  - `flatFee`: 50 tokens.
  - `basepoints`: 250 (2.5%).
  - Fee: `50 + (1000 * 250 / 10,000) = 75 tokens`.

### **State Transitions**
1. **Unfunded → Funded**: Upon funding by buyer.
2. **Funded → ReadyForRelease**: Upon marking work ready by seller.
3. **ReadyForRelease → Completed**: Upon release or claim of funds.
4. **Funded or ReadyForRelease → Disputed**: Upon initiating a dispute.

---

## **Usage Notes**
- Disputes must be initiated only when valid issues arise to avoid misuse.
- Arbitration decisions are final and cannot be reversed.
---
