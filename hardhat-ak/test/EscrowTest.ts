const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { parseUnits } = require("ethers");

describe("Escrow", function () {
  async function deployEscrowFixture() {
    // Get signers first so we can use them for addresses
    const [deployer, buyer, seller, arbitrator] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    const erc20Token = await Token.deploy();

    const flatFee = parseUnits("50", 18);
    const basepoints = 250;
    const completionDuration = 30;
    const releaseTimeout = 7;
    const invoiceId = "INV123";

    // Use signer addresses instead of random addresses
    const buyerAddress = buyer.address;
    const sellerAddress = seller.address;
    const arbitratorAddress = arbitrator.address;

    const Escrow = await ethers.getContractFactory("Escrow");
    const escrow = await Escrow.deploy(
      invoiceId,
      buyerAddress,
      sellerAddress,
      arbitratorAddress,
      erc20Token.target,
      flatFee,
      basepoints,
      completionDuration,
      releaseTimeout
    );

    return {
      escrow,
      buyer,
      seller,
      arbitrator,
      buyerAddress,
      sellerAddress,
      arbitratorAddress,
      erc20Token,
      flatFee,
      basepoints,
      completionDuration,
      releaseTimeout,
    };
  }

  async function fundedEscrowFixture() {
    const fixture = await deployEscrowFixture();
    const { escrow, erc20Token, buyer } = fixture;

    // Mint tokens to the buyer
    await erc20Token.mint(buyer.address, parseUnits("1000", 18));

    // Approve the escrow contract to spend tokens
    await erc20Token
      .connect(buyer)
      .approve(escrow.target, parseUnits("1000", 18));

    return fixture;
  }

  describe("Basic Setup and Constructor", function () {
    it("Should set the correct buyer, seller, and arbitrator addresses", async function () {
      const { escrow, buyerAddress, sellerAddress, arbitratorAddress } =
        await loadFixture(deployEscrowFixture);
      const [returnedBuyer, returnedSeller, returnedArbitrator] =
        await escrow.getParties();
      expect(returnedBuyer).to.equal(buyerAddress);
      expect(returnedSeller).to.equal(sellerAddress);
      expect(returnedArbitrator).to.equal(arbitratorAddress);
    });

    it("Should initialize with Unfunded status", async function () {
      const { escrow } = await loadFixture(deployEscrowFixture);
      expect(await escrow.status()).to.equal(0); // Corresponds to Unfunded status
    });

    it("Should set the correct invoice ID", async function () {
      const { escrow } = await loadFixture(deployEscrowFixture);
      expect(await escrow.invoiceId()).to.equal("INV123");
    });

    it("Should set a valid ERC20 token address", async function () {
      const { escrow, erc20Token } = await loadFixture(deployEscrowFixture);
      expect(await escrow.erc20Token()).to.equal(erc20Token.target);
      const tokenBalance = await erc20Token.balanceOf(erc20Token.target);
      expect(tokenBalance).to.be.a("bigint");
    });
  });

  describe("Funding Escrow", function () {
    it("Should only allow buyer to fund escrow", async function () {
      const { escrow, seller } = await loadFixture(deployEscrowFixture);
      await expect(
        escrow
          .connect(seller)
          .fundEscrow(parseUnits("100", 18), parseUnits("10", 18))
      ).to.be.revertedWithCustomError(escrow, "OnlyBuyerAllowed");
    });

    it("Should revert with insufficient fee", async function () {
      const { escrow, buyer, erc20Token } = await loadFixture(
        deployEscrowFixture
      );

      // Mint tokens to the buyer first
      await erc20Token.mint(buyer.address, parseUnits("1000", 18));

      // Approve spending
      await erc20Token
        .connect(buyer)
        .approve(escrow.target, parseUnits("1000", 18));

      await expect(
        escrow
          .connect(buyer)
          .fundEscrow(parseUnits("100", 18), parseUnits("1", 18))
      ).to.be.revertedWithCustomError(escrow, "InvalidFee");
    });

    it("Should fund escrow and update status", async function () {
      const { escrow, buyer, arbitratorAddress } = await loadFixture(
        fundedEscrowFixture
      );

      const escrowAmount = parseUnits("100", 18);
      const fee = parseUnits("52.5", 18); // 50 flat + 2.5%

      // Fund the escrow
      await escrow.connect(buyer).fundEscrow(escrowAmount, fee);

      // Check escrow amount
      expect(await escrow.escrowAmount()).to.equal(escrowAmount);

      // Check status
      expect(await escrow.status()).to.equal(1); // InProgress
    });

    it("Should prevent re-funding an already funded escrow", async function () {
      const { escrow, buyer } = await loadFixture(fundedEscrowFixture);

      const escrowAmount = parseUnits("100", 18);
      const fee = parseUnits("52.5", 18);

      // First funding
      await escrow.connect(buyer).fundEscrow(escrowAmount, fee);

      // Try to fund again
      await expect(
        escrow.connect(buyer).fundEscrow(escrowAmount, fee)
      ).to.be.revertedWithCustomError(escrow, "AlreadyFunded");
    });
  });
});
