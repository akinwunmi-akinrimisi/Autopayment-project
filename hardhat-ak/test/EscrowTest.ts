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
  });
});
