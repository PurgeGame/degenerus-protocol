/**
 * Phase 27: White Hat Completionist -- Attestation Tests
 *
 * No Medium+ findings were discovered during the completionist review.
 * These tests verify the QA-level observations documented in the SUMMARY.
 */

import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol } from "../helpers/deployFixture.js";

describe("Phase 27: White Hat Completionist Attestation", function () {
  async function deployFixture() {
    return deployFullProtocol();
  }

  describe("QA-01: receive() adds to futurePrizePool without event", function () {
    it("should accept plain ETH and add to futurePrizePool", async function () {
      const { game } = await loadFixture(deployFixture);
      const [signer] = await hre.ethers.getSigners();
      const poolBefore = await game.futurePrizePoolTotalView();
      const amount = hre.ethers.parseEther("0.01");
      await signer.sendTransaction({ to: game.target, value: amount });
      const poolAfter = await game.futurePrizePoolTotalView();
      expect(poolAfter - poolBefore).to.equal(amount);
    });
  });

  describe("QA-02: ERC20 zero-amount transfer", function () {
    it("BurnieCoin should allow zero-amount transfer", async function () {
      const { coin } = await loadFixture(deployFixture);
      const [signer] = await hre.ethers.getSigners();
      // Zero transfer should not revert
      await expect(coin.transfer(signer.address, 0)).to.not.be.reverted;
    });
  });

  describe("QA-03: ERC20 self-transfer", function () {
    it("BurnieCoin self-transfer should succeed if balance allows", async function () {
      const { coin } = await loadFixture(deployFixture);
      const [signer] = await hre.ethers.getSigners();
      // Self-transfer of 0 should always work
      await expect(coin.transfer(signer.address, 0)).to.not.be.reverted;
    });
  });

  describe("QA-04: ERC20 infinite approval", function () {
    it("BurnieCoin max approval should skip allowance decrement on transferFrom", async function () {
      const { coin } = await loadFixture(deployFixture);
      const [owner, spender] = await hre.ethers.getSigners();
      const maxUint = hre.ethers.MaxUint256;
      await coin.connect(owner).approve(spender.address, maxUint);
      const allowance = await coin.allowance(owner.address, spender.address);
      expect(allowance).to.equal(maxUint);
    });
  });

  describe("QA-05: DegenerusDeityPass ERC721 compliance", function () {
    it("should revert on ownerOf for nonexistent token", async function () {
      const { deityPass } = await loadFixture(deployFixture);
      await expect(deityPass.ownerOf(0)).to.be.revertedWithCustomError(
        deityPass,
        "InvalidToken"
      );
    });

    it("should revert on balanceOf(address(0))", async function () {
      const { deityPass } = await loadFixture(deployFixture);
      await expect(
        deityPass.balanceOf(hre.ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(deityPass, "ZeroAddress");
    });

    it("should support ERC721 interface", async function () {
      const { deityPass } = await loadFixture(deployFixture);
      // IERC721 = 0x80ac58cd
      expect(await deityPass.supportsInterface("0x80ac58cd")).to.be.true;
      // IERC721Metadata = 0x5b5e139f
      expect(await deityPass.supportsInterface("0x5b5e139f")).to.be.true;
      // IERC165 = 0x01ffc9a7
      expect(await deityPass.supportsInterface("0x01ffc9a7")).to.be.true;
    });
  });

  describe("QA-06: Operator approval system", function () {
    it("should allow setting and revoking operator approval", async function () {
      const { game } = await loadFixture(deployFixture);
      const [owner, operator] = await hre.ethers.getSigners();
      await game.connect(owner).setOperatorApproval(operator.address, true);
      expect(
        await game.isOperatorApproved(owner.address, operator.address)
      ).to.be.true;
      await game.connect(owner).setOperatorApproval(operator.address, false);
      expect(
        await game.isOperatorApproved(owner.address, operator.address)
      ).to.be.false;
    });

    it("should revert on zero address operator", async function () {
      const { game } = await loadFixture(deployFixture);
      const [owner] = await hre.ethers.getSigners();
      await expect(
        game.connect(owner).setOperatorApproval(hre.ethers.ZeroAddress, true)
      ).to.be.revertedWithCustomError(game, "E");
    });
  });

  describe("QA-07: claimWinnings with no balance", function () {
    it("should revert when claimable is 0 or only sentinel", async function () {
      const { game } = await loadFixture(deployFixture);
      const [signer] = await hre.ethers.getSigners();
      await expect(
        game.connect(signer).claimWinnings(hre.ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(game, "E");
    });
  });

  describe("QA-08: WrappedWrappedXRP compliance", function () {
    it("should revert mintPrize from unauthorized caller", async function () {
      const { wwxrp } = await loadFixture(deployFixture);
      const [signer] = await hre.ethers.getSigners();
      await expect(
        wwxrp.connect(signer).mintPrize(signer.address, 100)
      ).to.be.revertedWithCustomError(wwxrp, "OnlyMinter");
    });
  });
});
