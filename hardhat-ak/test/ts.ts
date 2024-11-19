const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const { parseUnits } = require("ethers");

describe("Escrow", function () {
  async function deployEscrowFixture() {
    const [deployer] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    const erc20Token = await Token.deploy();

    const flatFee = parseUnits("50", 18);
    const basepoints = 250;
    const completionDuration = 30;
    const releaseTimeout = 7;
    const invoiceId = "INV123";

    const buyerAddress = ethers.Wallet.createRandom().address;
    const sellerAddress = ethers.Wallet.createRandom().address;
    const arbitratorAddress = ethers.Wallet.createRandom().address;

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

      // Check that the ERC20 token address is set correctly
      expect(await escrow.erc20Token()).to.equal(erc20Token.target);

      // Verify the token has standard ERC20 functions like balanceOf
      const tokenBalance = await erc20Token.balanceOf(erc20Token.target);
      expect(tokenBalance).to.be.a("bigint"); // ERC20 balance should return a big integer
    });

// 

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
