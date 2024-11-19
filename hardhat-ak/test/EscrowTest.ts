import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { Flexiscrow, MockERC20 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Flexiscrow", function () {
  async function deployEscrowFixture() {
    const [deployer, buyer, seller, arbitrator]: HardhatEthersSigner[] =
      await ethers.getSigners();

    // Deploy MockERC20
    const Token = await ethers.getContractFactory("MockERC20");
    const erc20Token = (await Token.deploy()) as MockERC20;
    await erc20Token.waitForDeployment();

    const flatFee = ethers.parseUnits("50", 18);
    const basepoints = 250; // 2.5%
    const completionDuration = 30;
    const releaseTimeout = 7;
    const invoiceId = "INV123";

    const Escrow = await ethers.getContractFactory("Flexiscrow");
    const escrow = (await Escrow.deploy(
      invoiceId,
      buyer.address,
      seller.address,
      arbitrator.address,
      await erc20Token.getAddress(),
      flatFee,
      basepoints,
      completionDuration,
      releaseTimeout
    )) as Flexiscrow;
    await escrow.waitForDeployment();

    return {
      escrow,
      buyer,
      seller,
      arbitrator,
      erc20Token,
      flatFee,
      basepoints,
      deployer,
    };
  }

  describe("Basic Setup and Constructor", function () {
    it("Should set the correct buyer, seller, and arbitrator addresses", async function () {
      const { escrow, buyer, seller, arbitrator } = await loadFixture(
        deployEscrowFixture
      );
      const [returnedBuyer, returnedSeller, returnedArbitrator] =
        await escrow.getParties();
      expect(returnedBuyer).to.equal(buyer.address);
      expect(returnedSeller).to.equal(seller.address);
      expect(returnedArbitrator).to.equal(arbitrator.address);
    });

    it("Should initialize with Unfunded status", async function () {
      const { escrow } = await loadFixture(deployEscrowFixture);
      expect(await escrow.status()).to.equal(0); // Unfunded
    });

    it("Should set the correct invoice ID", async function () {
      const { escrow } = await loadFixture(deployEscrowFixture);
      expect(await escrow.invoiceId()).to.equal("INV123");
    });
  });

  describe("Funding Escrow", function () {
    it("Should only allow buyer to fund escrow", async function () {
      const { escrow, seller } = await loadFixture(deployEscrowFixture);
      const amount = ethers.parseUnits("100", 18);
      const fee = ethers.parseUnits("52.5", 18); // 50 flat + 2.5%

      await expect(
        escrow.connect(seller).fundEscrow(amount, fee)
      ).to.be.revertedWithCustomError(escrow, "OnlyBuyerAllowed");
    });

    it("Should revert with insufficient fee", async function () {
      const { escrow, buyer, erc20Token, deployer } = await loadFixture(
        deployEscrowFixture
      );

      const amount = ethers.parseUnits("100", 18);
      // Mint tokens to buyer
      await erc20Token.connect(deployer).mint(buyer.address, amount);
      // Approve spending
      await erc20Token
        .connect(buyer)
        .approve(await escrow.getAddress(), amount);

      const invalidFee = ethers.parseUnits("1", 18); // Too low fee

      await expect(
        escrow.connect(buyer).fundEscrow(amount, invalidFee)
      ).to.be.revertedWithCustomError(escrow, "InvalidFee");
    });

    it("Should fund escrow and update status", async function () {
      const { escrow, buyer, erc20Token, deployer } = await loadFixture(
        deployEscrowFixture
      );

      const amount = ethers.parseUnits("100", 18);
      const fee = ethers.parseUnits("52.5", 18); // 50 flat + 2.5%
      const totalAmount = amount + fee;

      // Mint tokens to buyer
      await erc20Token.connect(deployer).mint(buyer.address, totalAmount);
      // Approve spending
      await erc20Token
        .connect(buyer)
        .approve(await escrow.getAddress(), totalAmount);

      // Fund the escrow
      await escrow.connect(buyer).fundEscrow(amount, fee);

      expect(await escrow.escrowAmount()).to.equal(amount);
      expect(await escrow.status()).to.equal(1); // InProgress
    });

    it("Should prevent re-funding an already funded escrow", async function () {
      const { escrow, buyer, erc20Token, deployer } = await loadFixture(
        deployEscrowFixture
      );

      const amount = ethers.parseUnits("100", 18);
      const fee = ethers.parseUnits("52.5", 18);
      const totalAmount = amount + fee;

      // Mint tokens to buyer
      await erc20Token.connect(deployer).mint(buyer.address, totalAmount);
      // Approve spending
      await erc20Token
        .connect(buyer)
        .approve(await escrow.getAddress(), totalAmount);

      // First funding
      await escrow.connect(buyer).fundEscrow(amount, fee);

      // Try to fund again
      await expect(
        escrow.connect(buyer).fundEscrow(amount, fee)
      ).to.be.revertedWithCustomError(escrow, "AlreadyFunded");
    });
  });

  describe("Events", function () {
    it("Should emit EscrowFunded event when funded", async function () {
      const { escrow, buyer, erc20Token, deployer } = await loadFixture(
        deployEscrowFixture
      );

      const amount = ethers.parseUnits("100", 18);
      const fee = ethers.parseUnits("52.5", 18);
      const totalAmount = amount + fee;

      await erc20Token.connect(deployer).mint(buyer.address, totalAmount);
      await erc20Token
        .connect(buyer)
        .approve(await escrow.getAddress(), totalAmount);

      await expect(escrow.connect(buyer).fundEscrow(amount, fee))
        .to.emit(escrow, "EscrowFunded")
        .withArgs(amount);
    });
  });
});
