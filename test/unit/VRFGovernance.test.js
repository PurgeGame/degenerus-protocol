import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  advanceTime,
  advanceToNextDay,
  fulfillVRF,
  getLastVRFRequestId,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/**
 * VRF Governance Tests (M-02 Mitigation)
 *
 * Tests the sDGNRS-holder governance system for emergency VRF coordinator swaps.
 * Covers: propose, vote, threshold decay, execute, kill, expiry,
 * multi-proposal approval voting, unwrapTo block during stall, VRF recovery invalidation.
 */
describe("VRF Governance", function () {
  after(() => restoreAddresses());

  const TWENTY_HOURS = 20 * 3600;
  const SEVEN_DAYS = 7 * 86400;
  const ONE_DAY = 86400;

  // =========================================================================
  // Helper: create VRF stall by advancing time past lastVrfProcessed
  // =========================================================================
  async function createStall(hours) {
    await hre.ethers.provider.send("evm_increaseTime", [hours * 3600 + 1]);
    await hre.ethers.provider.send("evm_mine");
  }

  // =========================================================================
  // Helper: drive the game through a full VRF day so lastVrfProcessed catches
  // up to ~now (VRF "recovery"), dropping the measured stall below threshold.
  // Mirrors GovernanceGating's advanceGameOneDay; deployer holds DGVE majority
  // so it clears the mint gate.
  // =========================================================================
  async function recoverVrf(game, caller, mockVRF) {
    const before = await game.lastVrfProcessed();
    const previousRequest = await getLastVRFRequestId(mockVRF);
    let delivered = false;
    for (let i = 0; i < 128; i++) {
      const reqId = await getLastVRFRequestId(mockVRF);
      if (reqId > previousRequest) {
        const pending = await mockVRF.pendingRequests(reqId);
        if (!pending.fulfilled) {
          await fulfillVRF(mockVRF, reqId, 123456789n);
          delivered = true;
        }
      }
      if (delivered && await game.lastVrfProcessed() > before && !(await game.rngLocked())) return;
      await game.connect(caller).mineFlip({ gasLimit: 12_000_000 });
    }
    throw new Error("VRF recovery did not request, deliver and apply a new daily word");
  }

  // =========================================================================
  // Helper: give sDGNRS from Reward pool via impersonated game contract
  // =========================================================================
  const Pool = { Whale: 0, Affiliate: 1, Lootbox: 2, Reward: 3, Earlybird: 4 };

  async function giveSDGNRS(sdgnrs, game, recipient, amount) {
    const gameAddr = await game.getAddress();
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [gameAddr],
    });
    await hre.ethers.provider.send("hardhat_setBalance", [
      gameAddr,
      "0xDE0B6B3A7640000",
    ]);
    const gameSigner = await hre.ethers.getSigner(gameAddr);
    await sdgnrs
      .connect(gameSigner)
      .transferFromPool(Pool.Reward, recipient, amount);
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [gameAddr],
    });
  }

  // =========================================================================
  // 1. Propose
  // =========================================================================
  describe("propose", function () {
    it("admin path: DGVE holder can propose after 44h stall", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const keyHash = hre.ethers.id("new-key");

      await createStall(45);

      const tx = await admin.connect(deployer).propose(vrfAddr, keyHash);
      const ev = await getEvent(tx, admin, "ProposalCreated");
      expect(ev.args.proposalId).to.equal(1n);
      expect(ev.args.proposer).to.equal(await game.walletIdOf(deployer.address));
      expect(ev.args.coordinator).to.equal(vrfAddr);
      expect(ev.args.keyHash).to.equal(keyHash);
      expect(ev.args.path).to.equal(0); // Admin path

      expect(await admin.proposalCount()).to.equal(1n);
    });

    it("reverts with NotStalled if VRF stall < 44h for admin", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const keyHash = hre.ethers.id("new-key");

      await createStall(43);

      await expect(
        admin.connect(deployer).propose(vrfAddr, keyHash)
      ).to.be.revertedWithCustomError(admin, "NotStalled");
    });

    it("community path: reverts with NotStalled before 7d", async function () {
      const { admin, mockVRF, alice } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const keyHash = hre.ethers.id("new-key");

      // Even after 45h (past the admin threshold), non-DGVE holder needs 7d stall
      await createStall(45);

      await expect(
        admin.connect(alice).propose(vrfAddr, keyHash)
      ).to.be.revertedWithCustomError(admin, "NotStalled");
    });

    it("community path: reverts with InsufficientStake without sDGNRS", async function () {
      const { admin, mockVRF, alice } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const keyHash = hre.ethers.id("new-key");

      await createStall(7 * 24); // 7 days

      await expect(
        admin.connect(alice).propose(vrfAddr, keyHash)
      ).to.be.revertedWithCustomError(admin, "InsufficientStake");
    });

    it("reverts with ZeroAddress for zero coordinator", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).propose(ZERO_ADDRESS, hre.ethers.id("key"))
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("reverts with ZeroAddress for zero keyHash", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).propose(await mockVRF.getAddress(), ZERO_BYTES32)
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("increments proposalCount for each proposal", async function () {
      const { admin, mockVRF, deployer, sdgnrs, game } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer sDGNRS so reject vote has weight to kill
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));

      await createStall(45);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));
      expect(await admin.proposalCount()).to.equal(1n);

      // Kill proposal 1 via reject vote so deployer can propose again
      await admin.connect(deployer).vote(1, false);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key2"));
      expect(await admin.proposalCount()).to.equal(2n);
    });

    it("snapshots circulating supply at creation", async function () {
      const { admin, game, mockVRF, deployer, sdgnrs } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      const [, , circulatingSnapshot] = await admin.proposals(1);
      const liveCirc = await sdgnrs.votingSupply();
      // circulatingSnapshot is now uint40 whole tokens (divided by 1e18)
      expect(circulatingSnapshot).to.equal(liveCirc / hre.ethers.parseUnits("1", 12));
    });
  });

  // =========================================================================
  // 2. Vote
  // =========================================================================
  describe("vote", function () {
    it("kills a recovered proposal instead of reverting (auto-cancellation)", async function () {
      const { admin, mockVRF, game, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Open a proposal during a genuine stall.
      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));
      const [, , , , stateBefore] = await admin.proposals(1);
      expect(stateBefore).to.equal(0, "proposal 1 should be Active before recovery");

      // VRF recovers — lastVrfProcessed catches up, so the stall drops below 44h.
      await recoverVrf(game, deployer, mockVRF);

      // Voting now auto-cancels the stale proposal by killing it (no NotStalled revert).
      const tx = await admin.connect(deployer).vote(1, true);
      const ev = await getEvent(tx, admin, "ProposalKilled");
      expect(ev.args.proposalId).to.equal(1n);
      const [, , , , stateAfter] = await admin.proposals(1);
      expect(stateAfter).to.equal(2, "proposal 1 should be Killed after recovery");
    });

    it("reverts with ProposalNotActive for non-existent proposal", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);

      await createStall(45);

      await expect(
        admin.connect(deployer).vote(999, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
    });

    it("zero-weight vote succeeds as poke but emits no VoteCast", async function () {
      const { admin, mockVRF, deployer, alice } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // alice has no sDGNRS — vote succeeds as a poke (checks execute/kill) but no VoteCast
      const tx = await admin.connect(alice).vote(1, true);
      const events = await getEvents(tx, admin, "VoteCast");
      expect(events.length).to.equal(0, "No VoteCast event for zero-weight poke");
    });

    it("sub-token sDGNRS has zero VRF governance voting weight", async function () {
      const { admin, mockVRF, sdgnrs, game, deployer, alice, bob } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Keep a nonzero whole-token snapshot so a dust vote cannot resolve by
      // virtue of a zero denominator.
      await giveSDGNRS(sdgnrs, game, bob.address, hre.ethers.parseUnits("1", 12));
      await giveSDGNRS(sdgnrs, game, alice.address, 1n);

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      const tx = await admin.connect(alice).vote(1, true);
      expect((await getEvents(tx, admin, "VoteCast")).length).to.equal(0);
      expect(await admin.voteWeight(1, alice.address)).to.equal(0n);
      expect((await admin.proposals(1))[6]).to.equal(0n);
    });
  });

  // =========================================================================
  // 3. Threshold Decay
  // =========================================================================
  describe("threshold decay", function () {
    it("returns 5000 (50%) at creation", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      expect(await admin.threshold(1)).to.equal(5000);
    });

    it("stays at 5000 (50%) after 24h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(ONE_DAY);
      expect(await admin.threshold(1)).to.equal(5000);
    });

    it("decays to 4000 (40%) after 48h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(2 * ONE_DAY);
      expect(await admin.threshold(1)).to.equal(4000);
    });

    it("decays to 3000 (30%) after 72h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(3 * ONE_DAY);
      expect(await admin.threshold(1)).to.equal(3000);
    });

    it("decays to 2000 (20%) after 96h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(4 * ONE_DAY);
      expect(await admin.threshold(1)).to.equal(2000);
    });

    it("decays to 1000 (10%) after 120h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(5 * ONE_DAY);
      expect(await admin.threshold(1)).to.equal(1000);
    });

    it("decays to 500 (5%) after 144h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(6 * ONE_DAY);
      expect(await admin.threshold(1)).to.equal(500);
    });

    it("returns 0 (expired) after 168h", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      await advanceTime(7 * ONE_DAY);
      expect(await admin.threshold(1)).to.equal(0);
    });
  });

  // =========================================================================
  // 4. Proposal Expiry
  // =========================================================================
  describe("proposal expiry", function () {
    it("voting on expired proposal marks it Expired and reverts", async function () {
      const { admin, game, mockVRF, deployer, sdgnrs } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // Advance past 168h lifetime
      await advanceTime(7 * ONE_DAY + 1);

      // Deployer may have sDGNRS if pools distributed some
      // Regardless, the expiry check should fire first
      await expect(
        admin.connect(deployer).vote(1, true)
      ).to.be.reverted; // ProposalExpired or InsufficientStake
    });
  });

  // =========================================================================
  // 5. canExecute view
  // =========================================================================
  describe("canExecute", function () {
    it("returns false for non-existent proposal", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      expect(await admin.canExecute(1)).to.equal(false);
    });

    it("returns false when VRF not stalled", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // canExecute doesn't revert, just returns false when no approve weight
      expect(await admin.canExecute(1)).to.equal(false);
    });
  });

  // =========================================================================
  // 6. votingSupply
  // =========================================================================
  describe("votingSupply", function () {
    it("returns total minus SDGNRS, DGNRS, and vault balances", async function () {
      const { sdgnrs, dgnrs, vault } = await loadFixture(deployFullProtocol);
      const circ = await sdgnrs.votingSupply();

      const total = await sdgnrs.totalSupply();
      const sdgnrsAddr = await sdgnrs.getAddress();
      const dgnrsAddr = await dgnrs.getAddress();
      const vaultAddr = await vault.getAddress();
      const sdgnrsBal = await sdgnrs.balanceOf(sdgnrsAddr);
      const dgnrsBal = await sdgnrs.balanceOf(dgnrsAddr);
      const vaultBal = await sdgnrs.balanceOf(vaultAddr);

      expect(circ).to.equal(total - sdgnrsBal - dgnrsBal - vaultBal);
    });
  });

  // =========================================================================
  // 8. DGNRS unwrapTo block during VRF stall
  // =========================================================================
  describe("unwrapTo VRF stall guard", function () {
    it("unwrapTo works normally (rngLocked=false)", async function () {
      const { dgnrs, sdgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = hre.ethers.parseUnits("100", 12);

      const wrapperBefore = await dgnrs.balanceOf(deployer.address);
      const stakedBefore = await sdgnrs.balanceOf(alice.address);
      await dgnrs.connect(deployer).unwrapTo(alice.address, amount);
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(wrapperBefore - amount);
      expect(await sdgnrs.balanceOf(alice.address)).to.equal(stakedBefore + amount);
    });

    it("unwrapTo reverts when rngLocked is true", async function () {
      const { dgnrs, game, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = hre.ethers.parseUnits("100", 12);

      // Advance to next day and call mineFlip to trigger VRF request,
      // which sets rngLockedFlag = true
      await advanceToNextDay();
      await game.connect(deployer).mineFlip();

      await expect(
        dgnrs.connect(deployer).unwrapTo(alice.address, amount)
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });
  });

  // =========================================================================
  // 9. VRF Recovery Invalidation
  // =========================================================================
  describe("VRF recovery invalidation", function () {
    it("anyone can poke a recovered proposal into Killed", async function () {
      const { admin, mockVRF, game, deployer, alice } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // VRF recovers.
      await recoverVrf(game, deployer, mockVRF);

      // The stall re-check precedes vote recording, so any caller (here alice, not
      // the proposer) auto-cancels the now-invalid proposal by killing it.
      const tx = await admin.connect(alice).vote(1, true);
      const ev = await getEvent(tx, admin, "ProposalKilled");
      expect(ev.args.proposalId).to.equal(1n);
      const [, , , , state] = await admin.proposals(1);
      expect(state).to.equal(2, "proposal 1 should be Killed");
    });
  });

  // =========================================================================
  // 10. lastVrfProcessed view
  // =========================================================================
  describe("lastVrfProcessed", function () {
    it("returns non-zero after deployment (set in wireVrf)", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      const ts = await game.lastVrfProcessed();
      expect(ts).to.be.gt(0n);
    });

    it("is close to current block timestamp after deployment", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      const ts = await game.lastVrfProcessed();
      const block = await hre.ethers.provider.getBlock("latest");
      // Should be within a few seconds of current time
      expect(Number(ts)).to.be.closeTo(block.timestamp, 60);
    });
  });

  // =========================================================================
  // 11. 1-Per-Address Active Proposal Limit (WAR-06 fix)
  // =========================================================================
  describe("1-per-address active proposal limit", function () {
    it("reverts with AlreadyHasActiveProposal when same address proposes twice", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));

      await expect(
        admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key2"))
      ).to.be.revertedWithCustomError(admin, "AlreadyHasActiveProposal");
    });

    it("sets activeProposalId after propose", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      expect(await admin.activeProposalId(deployer.address)).to.equal(0n);

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));

      expect(await admin.activeProposalId(deployer.address)).to.equal(1n);
    });

    it("allows new proposal after previous is Killed", async function () {
      const { admin, mockVRF, deployer, sdgnrs, game } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));
      await createStall(45);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));

      // Kill proposal 1 via reject vote
      await admin.connect(deployer).vote(1, false);
      const [, , , , state] = await admin.proposals(1);
      expect(state).to.equal(2, "Proposal 1 should be Killed");

      // Deployer can now propose again
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key2"));
      expect(await admin.proposalCount()).to.equal(2n);
      expect(await admin.activeProposalId(deployer.address)).to.equal(2n);
    });

    it("allows new proposal after previous is Executed", async function () {
      const { admin, mockVRF, deployer, sdgnrs, game } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));
      await createStall(45);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));

      // Execute proposal 1 via approve vote
      await admin.connect(deployer).vote(1, true);
      const [, , , , state] = await admin.proposals(1);
      expect(state).to.equal(1, "Proposal 1 should be Executed");

      // Deployer can now propose again (VRF still stalled after swap)
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key2"));
      expect(await admin.proposalCount()).to.equal(2n);
    });

    it("allows new proposal after previous expires (lazy expiry)", async function () {
      const { admin, game, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      await createStall(45);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));

      // Advance past PROPOSAL_LIFETIME (168h)
      await advanceTime(7 * ONE_DAY + 1);

      // Deployer can propose again — lazy expiry check passes
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key2"));
      expect(await admin.proposalCount()).to.equal(2n);
      expect(await admin.activeProposalId(deployer.address)).to.equal(2n);
    });

    it("different addresses can each have one active proposal", async function () {
      const { admin, mockVRF, deployer, alice, bob, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give alice and bob enough sDGNRS for community path (0.5% of circulating)
      await giveSDGNRS(sdgnrs, game, alice.address, hre.ethers.parseUnits("500", 12));
      await giveSDGNRS(sdgnrs, game, bob.address, hre.ethers.parseUnits("500", 12));

      // 7-day stall for community path
      await createStall(7 * 24);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));
      await admin.connect(alice).propose(vrfAddr, hre.ethers.id("key2"));
      await admin.connect(bob).propose(vrfAddr, hre.ethers.id("key3"));

      expect(await admin.proposalCount()).to.equal(3n);
    });
  });

  // =========================================================================
  // 12. Epoch-cutoff invalidation (multi-proposal, O(1), no loop)
  // =========================================================================
  describe("epoch-cutoff invalidation on execute", function () {
    it("executing one proposal invalidates all others via epoch cutoff (no loop, no kill events)", async function () {
      const { admin, mockVRF, deployer, alice, bob, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer majority sDGNRS (>60% for threshold), alice and bob for community proposals
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("5000", 12));
      await giveSDGNRS(sdgnrs, game, alice.address, hre.ethers.parseUnits("100", 12));
      await giveSDGNRS(sdgnrs, game, bob.address, hre.ethers.parseUnits("100", 12));

      // 7-day stall for community path
      await createStall(7 * 24);

      // Create 3 proposals from different addresses
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));
      await admin.connect(alice).propose(vrfAddr, hre.ethers.id("key2"));
      await admin.connect(bob).propose(vrfAddr, hre.ethers.id("key3"));

      expect(await admin.proposalCount()).to.equal(3n);

      // Vote approve on proposal 2 — deployer has enough weight to trigger execution.
      // The epoch cutoff advances past every existing id in O(1) (no void loop).
      const tx = await admin.connect(deployer).vote(2, true);

      // Proposal 2: Executed
      const [, , , , state2] = await admin.proposals(2);
      expect(state2).to.equal(1, "Proposal 2 should be Executed");

      // Competitors 1 and 3 keep state == Active in storage (no loop rewrites them) but are inert:
      // canExecute returns false and any vote reverts. No ProposalKilled events fire on execution.
      expect(await admin.canExecute(1)).to.equal(false);
      expect(await admin.canExecute(3)).to.equal(false);
      await expect(
        admin.connect(alice).vote(1, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
      await expect(
        admin.connect(bob).vote(3, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
      expect((await getEvents(tx, admin, "ProposalKilled")).length).to.equal(0);

      // Verify ProposalExecuted event for proposal 2
      const execEvent = await getEvent(tx, admin, "ProposalExecuted");
      expect(execEvent.args.proposalId).to.equal(2n);
    });

    it("a reject-killed proposal stays Killed; executing another invalidates the rest via cutoff", async function () {
      const { admin, mockVRF, deployer, alice, bob, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer majority sDGNRS (>60% for threshold)
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("5000", 12));
      await giveSDGNRS(sdgnrs, game, alice.address, hre.ethers.parseUnits("100", 12));
      await giveSDGNRS(sdgnrs, game, bob.address, hre.ethers.parseUnits("100", 12));

      // 7-day stall
      await createStall(7 * 24);

      // Create 3 proposals from different addresses
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));
      await admin.connect(alice).propose(vrfAddr, hre.ethers.id("key2"));
      await admin.connect(bob).propose(vrfAddr, hre.ethers.id("key3"));

      // Kill proposal 1 by voting reject with enough weight
      await admin.connect(deployer).vote(1, false);
      const [, , , , state1Before] = await admin.proposals(1);
      expect(state1Before).to.equal(2, "Proposal 1 should be Killed after reject vote");

      // Execute proposal 2 — cutoff advances; no loop touches proposal 1.
      const tx = await admin.connect(deployer).vote(2, true);

      const [, , , , state2] = await admin.proposals(2);
      expect(state2).to.equal(1, "Proposal 2 should be Executed");

      // Proposal 1: still Killed (unchanged)
      const [, , , , state1After] = await admin.proposals(1);
      expect(state1After).to.equal(2, "Proposal 1 should still be Killed");

      // Proposal 3: Active in storage but inert via cutoff
      const [, , , , state3] = await admin.proposals(3);
      expect(state3).to.equal(0, "Proposal 3 still Active in storage");
      expect(await admin.canExecute(3)).to.equal(false);
      await expect(
        admin.connect(bob).vote(3, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");

      // Execution emits no kill events (cutoff is silent)
      expect((await getEvents(tx, admin, "ProposalKilled")).length).to.equal(0);
    });

    it("after a swap, superseded proposals stay inert and fresh proposals (id >= cutoff) execute", async function () {
      const { admin, mockVRF, deployer, alice, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer and alice sDGNRS
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));
      await giveSDGNRS(sdgnrs, game, alice.address, hre.ethers.parseUnits("500", 12));

      // First stall episode: create and execute a proposal
      await createStall(7 * 24);

      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key1"));
      await admin.connect(alice).propose(vrfAddr, hre.ethers.id("key2"));
      expect(await admin.proposalCount()).to.equal(2n);

      // Execute proposal 1 — cutoff advances to 3; proposal 2 is superseded.
      await admin.connect(deployer).vote(1, true);

      const [, , , , s1] = await admin.proposals(1);
      expect(s1).to.equal(1, "Proposal 1 Executed");
      const [, , , , s2] = await admin.proposals(2);
      expect(s2).to.equal(0, "Proposal 2 still Active in storage");
      expect(await admin.canExecute(2)).to.equal(false);
      await expect(
        admin.connect(alice).vote(2, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");

      // Second stall episode: the new coordinator is also stalled (mock). Fresh proposals
      // (id >= cutoff) are executable; the superseded proposers' active slots are freed.
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key3"));
      await admin.connect(alice).propose(vrfAddr, hre.ethers.id("key4"));
      expect(await admin.proposalCount()).to.equal(4n);

      // Execute proposal 3 — O(1), no loop over prior history.
      const tx = await admin.connect(deployer).vote(3, true);

      const [, , , , s3] = await admin.proposals(3);
      expect(s3).to.equal(1, "Proposal 3 Executed");
      expect(await admin.canExecute(4)).to.equal(false); // 4 now superseded
      expect((await getEvents(tx, admin, "ProposalKilled")).length).to.equal(0);
    });
  });

  // =========================================================================
  // 13. Kill condition (GOV-06 evidence)
  // =========================================================================
  describe("kill condition", function () {
    it("reject votes exceeding threshold kill the proposal", async function () {
      const { admin, mockVRF, deployer, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer sDGNRS so they can vote
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));

      // Create 21h stall
      await createStall(45);

      // Create a proposal
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // Cast reject vote -- deployer has enough weight to exceed threshold
      const tx = await admin.connect(deployer).vote(1, false);

      // Verify proposal state transitions to Killed (enum value 2)
      const [, , , , state] = await admin.proposals(1);
      expect(state).to.equal(2, "Proposal should be Killed");

      // Verify ProposalKilled event is emitted
      const ev = await getEvent(tx, admin, "ProposalKilled");
      expect(ev.args.proposalId).to.equal(1n);
    });

    it("reject vote below threshold does not kill the proposal", async function () {
      const { admin, mockVRF, deployer, alice, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer a large amount and alice a tiny amount
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));
      await giveSDGNRS(sdgnrs, game, alice.address, hre.ethers.parseUnits("1", 12));

      // Create 21h stall
      await createStall(45);

      // Deployer creates proposal (circ includes both deployer + alice amounts)
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // Alice casts a tiny reject vote -- not enough to meet 60% threshold
      await admin.connect(alice).vote(1, false);

      // Proposal should still be Active (enum value 0)
      const [, , , , state] = await admin.proposals(1);
      expect(state).to.equal(0, "Proposal should still be Active");
    });
  });

  // =========================================================================
  // 14. Execute with weight (GOV-05 evidence)
  // =========================================================================
  describe("execute with approve weight", function () {
    it("approve votes exceeding threshold execute the proposal", async function () {
      const { admin, mockVRF, deployer, sdgnrs, game } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Give deployer sDGNRS
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("1000", 12));

      // Create 21h stall
      await createStall(45);

      // Create proposal
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("key"));

      // Cast approve vote -- deployer has enough weight to exceed threshold
      const tx = await admin.connect(deployer).vote(1, true);

      // Verify proposal state transitions to Executed (enum value 1)
      const [, , , , state] = await admin.proposals(1);
      expect(state).to.equal(1, "Proposal should be Executed");

      // Verify ProposalExecuted event emitted
      const ev = await getEvent(tx, admin, "ProposalExecuted");
      expect(ev.args.proposalId).to.equal(1n);
      expect(ev.args.coordinator).to.equal(vrfAddr);
    });
  });

  // =========================================================================
  // 15. Tie condition (GOV-05/GOV-06 mutual exclusion evidence)
  // =========================================================================
  describe("tie condition", function () {
    it("equal approve and reject weights leave proposal Active (neither execute nor kill)", async function () {
      const { admin, game, mockVRF, deployer, alice, bob, carol, sdgnrs, dgnrs } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const subId = await admin.subscriptionId();
      // Three equal eligible holders: either first vote is below the initial 50%.
      // The third holder abstains; the first two form an exact, nonzero tie.
      for (const owner of [deployer, alice, bob]) {
        await dgnrs.connect(deployer).unwrapTo(owner.address, hre.ethers.parseUnits("1000", 12));
        expect(await sdgnrs.balanceOf(owner.address)).to.equal(hre.ethers.parseUnits("1000", 12));
      }
      expect(await sdgnrs.votingSupply()).to.equal(hre.ethers.parseUnits("3000", 12));
      expect(await sdgnrs.balanceOf(carol.address)).to.equal(0n);
      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("tie-key"));
      const id = await admin.proposalCount();
      expect((await admin.proposals(id))[2]).to.equal(3000n);
      expect(await admin.threshold(id)).to.equal(5000n);

      await expect(admin.connect(deployer).vote(id, true))
        .to.emit(admin, "VoteCast").withArgs(id, await game.walletIdOf(deployer.address), true, hre.ethers.parseUnits("1000", 12));
      const first = await admin.proposals(id);
      expect(first[4], "first vote must leave room for the opposing vote").to.equal(0n);
      expect(first[6]).to.equal(1000n);
      expect(first[7]).to.equal(0n);
      const opposingVote = await admin.connect(alice).vote(id, false);
      const opposingEvent = await getEvent(opposingVote, admin, "VoteCast");
      expect(opposingEvent.args.voter).to.equal(await game.walletIdOf(alice.address));
      expect(opposingEvent.args.approve).to.equal(false);
      expect(opposingEvent.args.weight).to.equal(hre.ethers.parseUnits("1000", 12));
      expect(await admin.voteWeight(id, deployer.address)).to.equal(1000n);
      expect(await admin.voteWeight(id, alice.address)).to.equal(1000n);
      expect(await admin.votes(id, deployer.address)).to.equal(1n);
      expect(await admin.votes(id, alice.address)).to.equal(2n);
      expect((await admin.proposals(id))[4]).to.equal(0n);

      // Decay below either side's weight, then actually poke resolution. Equality,
      // rather than insufficient quorum, must keep both execute and kill closed.
      await advanceTime(3 * ONE_DAY);
      expect(await admin.threshold(id)).to.equal(3000n);
      expect(1000n * 10000n).to.be.gte(3000n * 3000n);
      await admin.connect(carol).vote(id, true);
      const tied = await admin.proposals(id);
      expect(tied[6]).to.equal(1000n);
      expect(tied[7]).to.equal(1000n);
      expect(tied[4], "nonzero tie remains Active even after both sides clear quorum").to.equal(0n);
      expect(await admin.canExecute(id)).to.equal(false);
      expect(await admin.subscriptionId()).to.equal(subId);
      expect(await admin.coordinator()).to.equal(vrfAddr);
    });
  });

  // =========================================================================
  // 16. Proposal struct storage
  // =========================================================================
  describe("proposal storage", function () {
    it("stores correct proposal data", async function () {
      const { admin, game, mockVRF, deployer, sdgnrs } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const keyHash = hre.ethers.id("test-key");

      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, keyHash);

      const [proposer, createdAt, circulatingSnapshot, path, state,
             coordinator, approveWeight, rejectWeight, storedKeyHash]
        = await admin.proposals(1);

      expect(proposer).to.equal(await game.walletIdOf(deployer.address));
      expect(createdAt).to.be.gt(0n);
      // circulatingSnapshot is uint40 whole tokens; may be 0 if circ < 1e12
      const liveCirc = await sdgnrs.votingSupply();
      expect(circulatingSnapshot).to.equal(liveCirc / hre.ethers.parseUnits("1", 12));
      expect(path).to.equal(0); // Admin
      expect(state).to.equal(0); // Active
      expect(coordinator).to.equal(vrfAddr);
      expect(approveWeight).to.equal(0n);
      expect(rejectWeight).to.equal(0n);
      expect(storedKeyHash).to.equal(keyHash);
    });
  });

  // =========================================================================
  // 17. Recovery-spanning kill (475 finding)
  //
  // A proposal exists only to swap a DEAD coordinator. If a VRF word is
  // fulfilled AFTER the proposal was created (lastVrfProcessed > createdAt),
  // a recovery occurred — the proposal must die even if the protocol LATER
  // re-stalls past the 44h threshold. Otherwise a stale proposal could resume
  // voting on a re-stall at a further-decayed (age-keyed) threshold and execute
  // a swap of a coordinator that is no longer dead. vote()/poke + canExecute()
  // both check lastVrfProcessed > createdAt, independent of the live-stall check.
  // =========================================================================
  describe("recovery-spanning kill (475 finding)", function () {
    it("a proposal that spans a VRF recovery cannot execute on a later re-stall", async function () {
      const { admin, mockVRF, game, deployer, alice, sdgnrs } =
        await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();

      // Voting weight: deployer below the initial 50% threshold (stays Active on
      // approve) but enough to clear the DECAYED threshold later — the exact
      // stale-proposal-at-decayed-threshold vector the fix closes.
      await giveSDGNRS(sdgnrs, game, deployer.address, hre.ethers.parseUnits("4000", 12));
      await giveSDGNRS(sdgnrs, game, alice.address, hre.ethers.parseUnits("4500", 12));

      // 1) Open a proposal during a genuine >=44h stall and record approval weight.
      await createStall(45);
      await admin.connect(deployer).propose(vrfAddr, hre.ethers.id("recovery-span"));
      await admin.connect(deployer).vote(1, true); // sub-threshold approve -> stays Active
      let p = await admin.proposals(1);
      const createdAt = p[1];
      expect(p[4]).to.equal(0, "Active after sub-threshold approve");
      expect(p[6]).to.be.gt(0n, "approval weight recorded");

      // 2) Drive a VRF recovery WITHOUT poking the proposal: lastVrfProcessed
      //    advances PAST the proposal's createdAt.
      await recoverVrf(game, deployer, mockVRF);
      const lastVrf = await game.lastVrfProcessed();
      expect(lastVrf).to.be.gt(
        createdAt,
        "recovery must advance lastVrfProcessed past createdAt"
      );

      // 3) Re-stall well past 44h AND past the 72h decay step. The live-stall
      //    kill branch (stall < 44h) therefore does NOT apply — only the
      //    recovery-spanning branch (lastVrf > createdAt) can kill here.
      await createStall(73);
      const blk = await hre.ethers.provider.getBlock("latest");
      expect(Number(blk.timestamp) - Number(lastVrf)).to.be.gte(
        44 * 3600,
        "re-stall must exceed the 44h admin threshold (isolates the recovery branch)"
      );

      // 4) Demonstrate the vector is live: the recorded approval weight WOULD
      //    clear the now-decayed threshold, so without the fix canExecute would
      //    be true. (approve*BPS >= threshold*snapshot && approve > reject)
      p = await admin.proposals(1);
      const snapshot = p[2];
      const approveWeight = p[6];
      const rejectWeight = p[7];
      const t = await admin.threshold(1);
      expect(t).to.be.lt(5000, "threshold has decayed below the initial 50%");
      expect(approveWeight * 10000n).to.be.gte(
        BigInt(t) * snapshot,
        "recorded approval would clear the decayed threshold (vector is live)"
      );
      expect(approveWeight).to.be.gt(rejectWeight);

      // 5) The fix: canExecute returns false purely due to the recovery span.
      expect(await admin.canExecute(1)).to.equal(false);

      // 6) A poke kills the now-invalid proposal (Killed), not executes it.
      const tx = await admin.connect(deployer).vote(1, true);
      const ev = await getEvent(tx, admin, "ProposalKilled");
      expect(ev.args.proposalId).to.equal(1n);
      p = await admin.proposals(1);
      expect(p[4]).to.equal(2, "Killed after recovery-spanning re-stall");
    });
  });
});
