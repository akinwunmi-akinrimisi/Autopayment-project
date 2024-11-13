# Escrow Autopayment System with Milestone and Arbitration Support

This project is a Solidity-based escrow system implemented in three main contracts: `Escrow`, `EscrowFactory`, and `Multisig`. It provides milestone-based payment and dispute resolution features using ERC20 tokens. The system is designed to facilitate secure transactions between a buyer and seller, with support for arbitrated dispute resolution.

## Table of Contents
1. [Overview](#overview)
2. [Contracts](#contracts)
3. [Installation](#installation)
4. [Usage](#usage)
5. [Tests](#tests)
6. [License](#license)

## Overview
This escrow system allows parties to set up payment milestones for a transaction using ERC20 tokens. Each milestone has a defined amount and status that progresses from pending to completed or disputed. Disputes can be resolved by an arbitrator via a multisignature wallet (multisig), enhancing transparency and security.

### Key Features
- **Milestone-based Payments**: Funds are held in escrow and released upon milestone completion.
- **Dispute Resolution**: Allows for dispute resolution by an arbitrator using a multisig wallet.
- **Configurable Fees**: Fees can be applied as fixed amounts and percentage-based rates.

## Contracts

### Escrow Contract
The `Escrow` contract is responsible for handling funds for each milestone. It:
- Tracks each milestone’s status and ensures that milestones are funded, completed, or disputed as needed.
- Allows the buyer to release funds or the seller to claim funds after a timeout period.
- Supports arbitration through milestone-level dispute initiation and resolution.

### EscrowFactory Contract
The `EscrowFactory` contract is a factory for deploying `Escrow` instances. It:
- Creates and configures escrow contracts between specified buyers and sellers.
- Configures a standard arbitrator, ERC20 token address, and fee recipient across all escrow contracts created.
- Manages fees and timeout periods.

### Multisig Contract
The `Multisig` contract serves as a governance layer to handle escrow disputes. It:
- Manages a list of authorized signers who can create, vote on, and execute proposals.
- Allows for the adjustment of governance parameters such as adding/removing signers and updating quorum.
- Enables settling escrow milestones without requiring quorum, facilitating fast dispute resolution.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/akinwunmi-akinrimisi/Autopayment-project/
   cd Autopayment-project
   ```

2. Install Foundry:
   Follow the [Foundry installation guide](https://getfoundry.sh/) if you don’t have Foundry installed.

3. Install dependencies:
   ```bash
   forge install
   ```

## Usage

1. **Deploying the Factory Contract**: 
   Deploy the `EscrowFactory` contract with necessary parameters such as the arbitrator and fee recipient addresses.

2. **Creating an Escrow**: 
   Use the `createEscrow` function in `EscrowFactory` to initialize an escrow contract with buyer and seller addresses and milestone details.

3. **Dispute Resolution**: 
   Disputes can be initiated on a milestone, and arbitration can be handled by the multisig wallet. Once quorum is achieved, the multisig can settle the disputed milestone.

4. **Multisig Proposals**:
   - **Add Signer**: Adds an authorized signer to the multisig.
   - **Remove Signer**: Removes a signer from the multisig.
   - **Update Quorum**: Changes the required votes to pass a proposal.
   - **Withdraw Fees**: Withdraws accumulated fees to a specified address.

## Tests
Testing is handled using Foundry’s Forge tool:
```bash
forge test
```
Ensure tests cover milestone funding, status progression, dispute initiation, and resolution.

## License
This project is licensed under the MIT License.