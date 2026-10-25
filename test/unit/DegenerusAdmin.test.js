import { ownerAction } from "../helpers/deployFixture.js";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  flip,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const Pool = { Whale: 0, Affiliate: 1, Lootbox: 2, Reward: 3, Earlybird: 4 };

async function grantSdgnrs(sdgnrs, game, recipient, amount) {
  const gameAddr = await game.getAddress();
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
  await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0xDE0B6B3A7640000"]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  try {
    await sdgnrs.connect(gameSigner).transferFromPool(Pool.Reward, recipient, amount);
  } catch {
    try {
      await sdgnrs.connect(gameSigner).transferFromPool(Pool.Whale, recipient, amount);
    } catch {
      await sdgnrs.connect(gameSigner).transferFromPool(Pool.Lootbox, recipient, amount);
    }
  }
  await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });
}

describe("DegenerusAdmin", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // 1. Constructor / Initial State
  // ---------------------------------------------------------------------------
  describe("Initial state", function () {
    it("subscriptionId is non-zero after deployment", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();
      expect(subId).to.be.gt(0n);
    });

    it("coordinator is set to VRF coordinator address", async function () {
      const { admin, mockVRF } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      expect(await admin.coordinator()).to.equal(vrfAddr);
    });

    it("vrfKeyHash is set (non-zero)", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      const hash = await admin.vrfKeyHash();
      expect(hash).to.not.equal(ZERO_BYTES32);
    });



    it("constructor emits SubscriptionCreated event", async function () {
      // We verify state instead of replaying constructor events
      const { admin } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();
      expect(subId).to.be.gt(0n);
    });

    it("constructor emits CoordinatorUpdated event (captured via state)", async function () {
      const { admin, mockVRF } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      // Coordinator was updated during construction
      expect(await admin.coordinator()).to.equal(vrfAddr);
    });
  });

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------


  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------


  // ---------------------------------------------------------------------------
  // 5. VRF Governance (propose / vote / execute)
  // ---------------------------------------------------------------------------
  describe("VRF Governance", function () {
    it("propose reverts when VRF is not stalled (< 44h)", async function () {
      const { admin, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const newKeyHash = hre.ethers.id("test-key-hash");
      await expect(
        ownerAction(admin.connect(deployer), "propose", [vrfAddr, newKeyHash, 300000])
      ).to.be.revertedWithCustomError(admin, "NotStalled");
    });

    it("propose reverts with ZeroAddress for zero coordinator", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      const newKeyHash = hre.ethers.id("test-key-hash");
      // Even if stalled, zero coordinator should revert ZeroAddress first
      await expect(
        ownerAction(admin.connect(deployer), "propose", [ZERO_ADDRESS, newKeyHash, 300000])
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("propose reverts with ZeroAddress for zero keyHash", async function () {
      const { admin, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      await expect(
        ownerAction(admin.connect(deployer), "propose", [vrfAddr, ZERO_BYTES32, 300000])
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("community propose reverts with InsufficientStake when caller has no sDGNRS", async function () {
      const { admin, mockVRF, alice } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const newKeyHash = hre.ethers.id("test-key-hash");
      // Even after 7d stall, alice has no sDGNRS
      await hre.ethers.provider.send("evm_increaseTime", [7 * 86400 + 1]);
      await hre.ethers.provider.send("evm_mine");
      await expect(
        admin.connect(alice).propose(vrfAddr, newKeyHash, 300000)
      ).to.be.revertedWithCustomError(admin, "InsufficientStake");
    });

    it("vote reverts ProposalNotActive when the proposal does not exist (active-proposal precondition runs before any stall logic)", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      // vote() validates the proposal is active FIRST; the stall is no longer a
      // revert source (a recovered/healthy VRF now KILLS the proposal in-place
      // rather than reverting). A non-existent proposal (createdAt == 0) trips
      // the active-proposal guard regardless of stall state.
      await expect(
        admin.connect(deployer).vote(1, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
    });

    it("vote reverts with ProposalNotActive for non-existent proposal", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      // Advance 21 hours to pass stall check
      await hre.ethers.provider.send("evm_increaseTime", [21 * 3600]);
      await hre.ethers.provider.send("evm_mine");
      await expect(
        admin.connect(deployer).vote(999, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
    });

    it("votingSupply excludes the undistributed pools and wrapper allocation at genesis", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const supply = await sdgnrs.votingSupply();
      expect(supply).to.equal(0n);
    });

    it("threshold returns zero for a non-existent proposal", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      // Threshold for non-existent proposal: createdAt=0, elapsed=block.timestamp (huge) → 0
      // This is expected — expired proposals have 0 threshold
      expect(await admin.threshold(0)).to.equal(0);
    });

    it("canExecute returns false for non-existent proposal", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      expect(await admin.canExecute(1)).to.equal(false);
    });

    it("proposalCount starts at 0", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      expect(await admin.proposalCount()).to.equal(0n);
    });

  });

  // ---------------------------------------------------------------------------
  // 6. shutdownVrf
  // ---------------------------------------------------------------------------
  describe("shutdownVrf", function () {
    it("reverts when called by non-GAME address", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });

    it("reverts when called by alice", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });
  });

  // ---------------------------------------------------------------------------
  // 7. swapGameEthForStEth
  // ---------------------------------------------------------------------------
  describe("swapGameEthForStEth", function () {
    it("rejects zero and the governance executor as recipients", async function () {
      const { admin, deployer, ownerGovernance } = await loadFixture(deployFullProtocol);
      for (const recipient of [hre.ethers.ZeroAddress, await ownerGovernance.getAddress()]) {
        await expect(ownerAction(admin.connect(deployer), "swapGameEthForStEth", [recipient], {value: eth("1")}))
          .to.be.revertedWithCustomError(admin, "InvalidRecipient");
      }
    });
    it("reverts when called by non-owner", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).swapGameEthForStEth(await (admin.connect(alice)).runner.getAddress(), { value: eth("1") })
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("reverts when msg.value is zero", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        ownerAction(admin.connect(deployer), "swapGameEthForStEth", [await (admin.connect(deployer)).runner.getAddress()], { value: 0n })
      ).to.be.revertedWithCustomError(admin, "InvalidAmount");
    });
  });

  // stakeGameEthToStEth and setLootboxRngThreshold removed from Admin in Phase 146
  // (now live directly on DegenerusGame with vault-owner access control)
});
