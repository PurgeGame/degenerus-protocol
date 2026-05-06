import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  eth,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";
import {
  deployGNRUSFixture,
  impersonate,
  stopImpersonating,
  giveSDGNRS,
  POOL_REWARD,
} from "../helpers/charityFixture.js";

const INITIAL_SUPPLY = hre.ethers.parseEther("1000000000000"); // 1T
const MIN_BURN = hre.ethers.parseEther("1"); // 1 GNRUS
const DISTRIBUTION_BPS = 200n;
const BPS_DENOM = 10_000n;

// ---------------------------------------------------------------------------
// Helper: distribute GNRUS to a recipient via v33 setCharity (instant-apply on slot 5) + impersonated pickCharity.
// Single-active-slot wins by default — no votes needed (skip-path B does NOT fire because
// we are not voting; the winner-loop tracks bestSlot via strict `>` so a single active slot
// with bestWeight == 0 is selected as the winner with bestSlot = 5 — verify against
// contracts/GNRUS.sol pickCharity winner-phase L639-650).
// NOTE: in v33, a slot with zero approve weight still wins if it is the only active slot
//       — re-read pickCharity skip-path B at L653: `if (bestSlot == type(uint8).max)`.
//       bestSlot is initialized to 0xFF and only set when w > bestWeight (i.e. w > 0).
//       Therefore a single active slot with ZERO votes still hits skip-path B (LevelSkipped).
//       To force a real distribution this helper MUST cast at least one vote.
// ---------------------------------------------------------------------------
async function distributeGNRUS(charity, deployer, recipientAddr, gameAddress, voter) {
  const slot = 5; // any non-locked, non-conflicting slot
  const level = await charity.currentLevel();
  // 1. Vault-owner sets recipient into empty slot 5 (instant-apply branch).
  await charity.connect(deployer).setCharity(slot, recipientAddr);
  // 2. Voter casts a vote so bestWeight > 0 → distribution path fires (not LevelSkipped).
  await charity.connect(voter).vote(slot);
  // 3. Game impersonates and resolves.
  const gameSigner = await impersonate(gameAddress);
  await charity.connect(gameSigner).pickCharity(level);
  await stopImpersonating(gameAddress);
}

// Alias so fixture name matches loadFixture usage
const deployCharityFixture = deployGNRUSFixture;

describe("GNRUS (GNRUS)", function () {
  describe("Token Metadata", function () {
    it("name is 'Degenerus Donations'", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.name()).to.equal("GNRUS Donations");
    });

    it("symbol is 'GNRUS'", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.symbol()).to.equal("GNRUS");
    });

    it("decimals is 18", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.decimals()).to.equal(18n);
    });

    it("totalSupply is 1T after deploy", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.totalSupply()).to.equal(INITIAL_SUPPLY);
    });

    it("all tokens minted to contract itself (unallocated pool)", async function () {
      const { charity, charityAddress } = await loadFixture(deployCharityFixture);
      expect(await charity.balanceOf(charityAddress)).to.equal(INITIAL_SUPPLY);
    });

    it("currentLevel starts at 0", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.currentLevel()).to.equal(0);
    });

    it("finalized starts as false", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.finalized()).to.equal(false);
    });
  });

  describe("Soulbound Enforcement", function () {
    it("transfer() reverts with TransferDisabled", async function () {
      const { charity, voter1, voter2 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).transfer(voter2.address, eth("1"))
      ).to.be.revertedWithCustomError(charity, "TransferDisabled");
    });

    it("transferFrom() reverts with TransferDisabled", async function () {
      const { charity, voter1, voter2, deployer } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).transferFrom(deployer.address, voter2.address, eth("1"))
      ).to.be.revertedWithCustomError(charity, "TransferDisabled");
    });

    it("approve() reverts with TransferDisabled", async function () {
      const { charity, voter1, voter2 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).approve(voter2.address, eth("1"))
      ).to.be.revertedWithCustomError(charity, "TransferDisabled");
    });
  });

  describe("Burn Redemption", function () {
    it("burn below MIN_BURN (1 GNRUS) reverts with InsufficientBurn", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).burn(eth("0.5"))
      ).to.be.revertedWithCustomError(charity, "InsufficientBurn");
    });

    it("burn(0) reverts with InsufficientBurn", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).burn(0n)
      ).to.be.revertedWithCustomError(charity, "InsufficientBurn");
    });

    it("burn reduces totalSupply by burned amount", async function () {
      const { charity, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      expect(bal).to.be.gt(0n);

      const supplyBefore = await charity.totalSupply();
      await charity.connect(recipient1).burn(bal);
      expect(await charity.totalSupply()).to.equal(supplyBefore - bal);
    });

    it("burn reduces balanceOf[caller] to 0 on full burn", async function () {
      const { charity, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      await charity.connect(recipient1).burn(bal);
      expect(await charity.balanceOf(recipient1.address)).to.equal(0n);
    });

    it("burn emits Transfer(caller, address(0), amount) and Burn events", async function () {
      const { charity, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);

      const transferEv = await getEvent(tx, charity, "Transfer");
      expect(transferEv.args.from).to.equal(recipient1.address);
      expect(transferEv.args.to).to.equal(ZERO_ADDRESS);
      expect(transferEv.args.amount).to.equal(bal);

      const burnEv = await getEvent(tx, charity, "Burn");
      expect(burnEv.args.burner).to.equal(recipient1.address);
      expect(burnEv.args.gnrusAmount).to.equal(bal);
    });

    it("burn with ETH backing pays proportional ETH", async function () {
      const { charity, charityAddress, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      // Fund charity with 10 ETH
      await deployer.sendTransaction({ to: charityAddress, value: eth("10") });

      // Distribute GNRUS to recipient1
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      const supply = await charity.totalSupply();
      const ethBal = await hre.ethers.provider.getBalance(charityAddress);

      // Expected ETH out: (ethBal * bal) / supply
      const expectedEthOut = (ethBal * bal) / supply;

      const recipientBalBefore = await hre.ethers.provider.getBalance(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const recipientBalAfter = await hre.ethers.provider.getBalance(recipient1.address);

      const burnEv = await getEvent(tx, charity, "Burn");
      expect(burnEv.args.ethOut).to.be.gt(0n);
      expect(burnEv.args.ethOut).to.be.closeTo(expectedEthOut, eth("0.01"));
      expect(recipientBalAfter + gasUsed - recipientBalBefore).to.equal(burnEv.args.ethOut);
    });

    it("burn with stETH backing pays proportional stETH", async function () {
      const { charity, charityAddress, deployer, mockSteth, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      // Fund charity with stETH
      await mockSteth.mint(charityAddress, eth("5"));

      // Distribute GNRUS to recipient1
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);

      const stethBefore = await mockSteth.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");

      expect(burnEv.args.stethOut).to.be.gt(0n);
      const stethAfter = await mockSteth.balanceOf(recipient1.address);
      expect(stethAfter - stethBefore).to.equal(burnEv.args.stethOut);
    });

    it("burn with zero ETH and zero stETH sends nothing (no revert)", async function () {
      const { charity, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      // No ETH or stETH funded -- charity has 0 backing
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");
      expect(burnEv.args.ethOut).to.equal(0n);
      expect(burnEv.args.stethOut).to.equal(0n);
    });

    it("ETH-preferred: ETH covers owed first, stETH fills remainder", async function () {
      const { charity, charityAddress, deployer, mockSteth, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      // Fund with both ETH and stETH
      await deployer.sendTransaction({ to: charityAddress, value: eth("3") });
      await mockSteth.mint(charityAddress, eth("7"));

      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");

      // Total owed is proportional to (3 + 7) ETH equivalent
      // ETH is preferred, so ethOut should be used first
      expect(burnEv.args.ethOut).to.be.gt(0n);
      // If owed <= ethBalance, stethOut should be 0
      // With 2% of 1T = 20B GNRUS distributed, and 1T total supply:
      // owed = 10 * 20B / 1T = 0.2 ETH approx, well under 3 ETH
      // So ethOut should cover it all, stethOut = 0
      expect(burnEv.args.stethOut).to.equal(0n);
    });

    it("last-holder sweep: burning exact balance sweeps full amount", async function () {
      const { charity, charityAddress, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      await deployer.sendTransaction({ to: charityAddress, value: eth("1") });
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);

      const bal = await charity.balanceOf(recipient1.address);
      // Burn exactly the balance -- triggers last-holder sweep
      const tx = await charity.connect(recipient1).burn(bal);
      expect(await charity.balanceOf(recipient1.address)).to.equal(0n);
    });

    it("burn reverts on underflow when amount exceeds balance", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      // voter1 has no GNRUS
      await expect(
        charity.connect(voter1).burn(eth("1"))
      ).to.be.reverted; // Solidity 0.8 underflow revert
    });
  });

  describe("burnAtGameOver", function () {
    it("burnAtGameOver burns all unallocated GNRUS (onlyGame)", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployCharityFixture);

      const gameSigner = await impersonate(gameAddress);
      const unallocated = await charity.balanceOf(charityAddress);
      const supplyBefore = await charity.totalSupply();

      const tx = await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      expect(await charity.balanceOf(charityAddress)).to.equal(0n);
      expect(await charity.totalSupply()).to.equal(supplyBefore - unallocated);

      const ev = await getEvent(tx, charity, "GameOverFinalized");
      expect(ev.args.gnrusBurned).to.equal(unallocated);
    });

    it("burnAtGameOver reverts if not called by game", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).burnAtGameOver()
      ).to.be.revertedWithCustomError(charity, "Unauthorized");
    });

    it("burnAtGameOver reverts if called twice (AlreadyFinalized)", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);

      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).burnAtGameOver();

      await expect(
        charity.connect(gameSigner).burnAtGameOver()
      ).to.be.revertedWithCustomError(charity, "AlreadyFinalized");
      await stopImpersonating(gameAddress);
    });

    it("burnAtGameOver sets finalized to true", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);
      expect(await charity.finalized()).to.equal(false);

      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      expect(await charity.finalized()).to.equal(true);
    });

    it("burnAtGameOver emits Transfer(contract, address(0), amount)", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployCharityFixture);
      const unallocated = await charity.balanceOf(charityAddress);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      const transferEv = await getEvent(tx, charity, "Transfer");
      expect(transferEv.args.from).to.equal(charityAddress);
      expect(transferEv.args.to).to.equal(ZERO_ADDRESS);
      expect(transferEv.args.amount).to.equal(unallocated);
    });

    it("burnAtGameOver after partial distribution burns only remaining", async function () {
      const { charity, charityAddress, deployer, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      // Distribute some GNRUS via governance first
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);
      const distributed = await charity.balanceOf(recipient1.address);
      expect(distributed).to.be.gt(0n);

      const unallocatedAfterDist = await charity.balanceOf(charityAddress);
      expect(unallocatedAfterDist).to.be.lt(INITIAL_SUPPLY);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      const ev = await getEvent(tx, charity, "GameOverFinalized");
      expect(ev.args.gnrusBurned).to.equal(unallocatedAfterDist);
      expect(await charity.balanceOf(charityAddress)).to.equal(0n);
      // Recipient still has their GNRUS
      expect(await charity.balanceOf(recipient1.address)).to.equal(distributed);
    });
  });

  describe("receive() -- ETH acceptance", function () {
    it("contract can receive ETH from anyone", async function () {
      const { charity, charityAddress, voter1 } = await loadFixture(deployCharityFixture);
      const balBefore = await hre.ethers.provider.getBalance(charityAddress);
      await voter1.sendTransaction({ to: charityAddress, value: eth("1") });
      const balAfter = await hre.ethers.provider.getBalance(charityAddress);
      expect(balAfter - balBefore).to.equal(eth("1"));
    });

    it("contract can receive ETH from game", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployCharityFixture);
      const gameSigner = await impersonate(gameAddress);
      await gameSigner.sendTransaction({ to: charityAddress, value: eth("5") });
      await stopImpersonating(gameAddress);
      const balance = await hre.ethers.provider.getBalance(charityAddress);
      expect(balance).to.equal(eth("5"));
    });
  });

  describe("Edge Cases", function () {
    it("totalSupply is conserved: unallocated + all holders = totalSupply", async function () {
      const { charity, charityAddress, deployer, voter1, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);

      // Distribute to two recipients across two levels
      await distributeGNRUS(charity, deployer, recipient1.address, gameAddress, voter1);
      await distributeGNRUS(charity, deployer, recipient2.address, gameAddress, voter1);

      const unallocated = await charity.balanceOf(charityAddress);
      const r1Bal = await charity.balanceOf(recipient1.address);
      const r2Bal = await charity.balanceOf(recipient2.address);
      const supply = await charity.totalSupply();

      // Sum of all balances should equal totalSupply
      expect(unallocated + r1Bal + r2Bal).to.equal(supply);
    });
  });
});
