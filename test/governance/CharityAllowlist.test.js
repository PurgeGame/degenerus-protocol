import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  eth,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";
import { restoreAddresses } from "../helpers/deployFixture.js";
import {
  deployGNRUSFixture,
  impersonate,
  stopImpersonating,
  giveSDGNRS,
  runLevelTransitionViaGame,
  POOL_REWARD,
} from "../helpers/charityFixture.js";

// =====================================================================
//  Module-level constants
//  Pre-declared so plans 03b and 03c can append their describes
//  (vote() reject codes, pickCharity reject codes, distribution math,
//  gas guardrail) without touching this header block.
// =====================================================================

const LOCKED_SLOTS = 3;
const MAX_ACTIVE_SLOTS = 20;

// vote() reject reasons (consumed by Plan 03b vote() describe — mirror contracts/GNRUS.sol)
const REJECT_EMPTY_SLOT = 0;
const REJECT_ALREADY_VOTED = 1;
const REJECT_ZERO_WEIGHT = 2;

// pickCharity() reject reasons (consumed by Plan 03c pickCharity describe)
const REJECT_LEVEL_NOT_ACTIVE = 0;
const REJECT_LEVEL_ALREADY_RESOLVED = 1;

// Distribution math (consumed by Plan 03c)
const DISTRIBUTION_BPS = 200n;
const BPS_DENOM = 10_000n;

// Gas guardrail ceiling (consumed by Plan 03c — D-256-GAS-01)
const PICK_CHARITY_CEILING_GAS = 700_000n;

// =====================================================================
//  In-file helpers (consumed by ≥2 it-blocks per feedback_no_dead_guards)
// =====================================================================

/**
 * Vault-owner-side setCharity convenience wrapper.
 * Used by every it-block that drives an instant-apply or queue write.
 */
async function setCharityFromVaultOwner(charity, vaultOwner, slot, recipient) {
  return charity.connect(vaultOwner).setCharity(slot, recipient);
}

describe("GNRUS Charity Allowlist (v33.0)", function () {
  after(function () {
    restoreAddresses();
  });

  // -------------------------------------------------------------------
  //  Section 1: setCharity -- instant-apply branch (TST-01 instant-apply)
  // -------------------------------------------------------------------
  describe("setCharity -- instant-apply branch", function () {
    it("instant-apply on empty slot writes directly to currentSlate", async function () {
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      expect(await charity.getCharity(5)).to.equal(recipient1.address);
      expect(await charity.activeCount()).to.equal(1n);
    });

    it("instant-apply emits CharityApplied(slot, recipient)", async function () {
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      const tx = await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      const ev = await getEvent(tx, charity, "CharityApplied");
      expect(ev.args.slot).to.equal(5n);
      expect(ev.args.recipient).to.equal(recipient1.address);
    });

    it("instant-apply slot is votable in the same level", async function () {
      const { charity, deployer, recipient1, voter1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);
      const level = await charity.currentLevel();
      expect(await charity.slotApproveWeight(level, 5)).to.equal(100n);
    });

    it("instant-apply on locked slot 0 succeeds via first-fill", async function () {
      // D-256-LOCKED-SLOT-01 first-fill path: slots 0/1/2 accept the FIRST setCharity
      // and become irrevocable; the locked-slot guard fires only on subsequent mutations.
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 0, recipient1.address);
      expect(await charity.getCharity(0)).to.equal(recipient1.address);
    });

    it("setCharity from non-vault-owner reverts Unauthorized", async function () {
      const { charity, voter1, recipient1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(voter1).setCharity(5, recipient1.address)
      ).to.be.revertedWithCustomError(charity, "Unauthorized");
    });

    it("setCharity with slot >= 20 reverts InvalidSlot (slot=20)", async function () {
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(deployer).setCharity(20, recipient1.address)
      ).to.be.revertedWithCustomError(charity, "InvalidSlot");
    });

    it("setCharity with slot >= 20 reverts InvalidSlot (slot=255)", async function () {
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(deployer).setCharity(255, recipient1.address)
      ).to.be.revertedWithCustomError(charity, "InvalidSlot");
    });

    it("contract-recipient acceptance: setCharity to a contract address succeeds", async function () {
      // D-256-CONTRACT-RECIPIENT-01 — Phase 254 deviation lock: the GNRUS contract
      // contains NO RecipientIsContract revert path. Setting a contract as the
      // charity recipient is a valid action (the owner of the contract can later
      // burn for proportional ETH/stETH). No `setCode` extension check exists.
      const { charity, deployer, stethAddress } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, stethAddress);
      expect(await charity.getCharity(5)).to.equal(stethAddress);
    });
  });

  // -------------------------------------------------------------------
  //  Section 2: setCharity -- queue branch (TST-01 queue)
  // -------------------------------------------------------------------
  describe("setCharity -- queue branch", function () {
    it("queue branch: filled slot replace writes to pending, currentSlate unchanged", async function () {
      const { charity, deployer, recipient1, recipient2 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      expect(await charity.getCharity(5)).to.equal(recipient1.address);
      const [slots, recipients] = await charity.getPendingEdits();
      expect(slots.length).to.equal(1);
      expect(slots[0]).to.equal(5n);
      expect(recipients[0]).to.equal(recipient2.address);
    });

    it("queue emits CharityQueued(slot, recipient)", async function () {
      const { charity, deployer, recipient1, recipient2 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      const tx = await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      const ev = await getEvent(tx, charity, "CharityQueued");
      expect(ev.args.slot).to.equal(5n);
      expect(ev.args.recipient).to.equal(recipient2.address);
    });

    it("queue branch: filled slot remove writes pending-remove, currentSlate unchanged", async function () {
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      const tx = await setCharityFromVaultOwner(charity, deployer, 5, ZERO_ADDRESS);
      const ev = await getEvent(tx, charity, "CharityQueued");
      expect(ev.args.recipient).to.equal(ZERO_ADDRESS);
      expect(await charity.getCharity(5)).to.equal(recipient1.address);
      const [slots, recipients] = await charity.getPendingEdits();
      expect(slots.length).to.equal(1);
      expect(slots[0]).to.equal(5n);
      expect(recipients[0]).to.equal(ZERO_ADDRESS);
    });

    it("queued slot keeps OLD address votable until flush", async function () {
      const { charity, deployer, recipient1, recipient2, voter1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      // Slot 5 still active in current slate → vote succeeds against the OLD recipient.
      await charity.connect(voter1).vote(5);
      const level = await charity.currentLevel();
      expect(await charity.slotApproveWeight(level, 5)).to.equal(100n);
    });

    it("setCharity removal on already-empty slot with no pending reverts SlotAlreadyEmpty", async function () {
      const { charity, deployer } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(deployer).setCharity(7, ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(charity, "SlotAlreadyEmpty");
    });
  });

  // -------------------------------------------------------------------
  //  Section 3: setCharity -- locked slots (D-256-LOCKED-SLOT-01)
  //  Parametric across slots 0/1/2 via a for-loop.
  // -------------------------------------------------------------------
  describe("setCharity -- locked slots (0/1/2)", function () {
    for (const lockedSlot of [0, 1, 2]) {
      it(`slot ${lockedSlot}: replace on filled locked slot reverts SlotLocked`, async function () {
        const { charity, deployer, recipient1, recipient2 } = await loadFixture(deployGNRUSFixture);
        await setCharityFromVaultOwner(charity, deployer, lockedSlot, recipient1.address);
        await expect(
          charity.connect(deployer).setCharity(lockedSlot, recipient2.address)
        ).to.be.revertedWithCustomError(charity, "SlotLocked");
      });

      it(`slot ${lockedSlot}: remove on filled locked slot reverts SlotLocked`, async function () {
        const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
        await setCharityFromVaultOwner(charity, deployer, lockedSlot, recipient1.address);
        await expect(
          charity.connect(deployer).setCharity(lockedSlot, ZERO_ADDRESS)
        ).to.be.revertedWithCustomError(charity, "SlotLocked");
      });
    }

    it("voters CAN vote on locked slot 0 (locked-slot guard lives only in setCharity)", async function () {
      // D-256-LOCKED-SLOT-01 positive case. The locked-slot guard is intentionally
      // confined to setCharity (contracts/GNRUS.sol L375); vote(uint8) has no such
      // restriction, so once a locked slot is filled it is a normal voting target.
      const { charity, deployer, recipient1, voter1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 0, recipient1.address);
      await charity.connect(voter1).vote(0);
      const level = await charity.currentLevel();
      expect(await charity.slotApproveWeight(level, 0)).to.equal(100n);
    });

    it("locked-slot guard fires before SlotAlreadyEmpty on filled locked slot remove", async function () {
      // Confirms revert order: contracts/GNRUS.sol L375 (SlotLocked) executes BEFORE the
      // L386 SlotAlreadyEmpty branch. Even though slot 0 is filled (so SlotAlreadyEmpty
      // could not fire on a remove anyway), this it-block locks the structural ordering
      // for any future refactor that might move the guards.
      const { charity, deployer, recipient1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 0, recipient1.address);
      await expect(
        charity.connect(deployer).setCharity(0, ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(charity, "SlotLocked");
    });
  });

  // -------------------------------------------------------------------
  //  Section 4: setCharity -- pending overwrite + cap (structural unreachability verdict)
  // -------------------------------------------------------------------
  describe("setCharity -- pending overwrite + cap (structural unreachability verdict)", function () {
    // D-256-CANCEL-QUEUED-01 verdict: the branch at contracts/GNRUS.sol:382-391 (cancellation
    // path: currentSlate[slot] == 0 AND pendingEditSet[slot] == 1 AND recipient == 0) is
    // structurally unreachable. pendingEditSet bit i is only set inside the queue branch (L405)
    // which fires only when current != 0 (L380 else). Therefore (current == 0 AND pendingEditSet
    // bit set) cannot be reached from any sequence of external calls. Disposition: defensive
    // guard, no test path. Phase 257 audit cites this verdict and grep-proves unreachability as
    // a SAFE row in AUDIT-02.

    it("queue overwrite: setCharity(5, A) then setCharity(5, B) → only B in pending", async function () {
      const { charity, deployer, recipient1, recipient2, recipient3 } = await loadFixture(deployGNRUSFixture);
      // Instant-apply with recipient1 so subsequent calls hit the queue branch.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      // Queue A
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      // Queue B (overwrites A in pending mapping; bitmap bit already set)
      await setCharityFromVaultOwner(charity, deployer, 5, recipient3.address);
      const [slots, recipients] = await charity.getPendingEdits();
      expect(slots.length).to.equal(1);
      expect(slots[0]).to.equal(5n);
      expect(recipients[0]).to.equal(recipient3.address);
    });

    // CapExceeded structural unreachability verdict (parallel to D-256-CANCEL-QUEUED-01):
    //
    // The check `_popcount32(_futureBitmapAfter(...)) > MAX_ACTIVE_SLOTS` (contracts/GNRUS.sol
    // L394 + L402) can never fire from any external call sequence because:
    //
    // - currentActiveBitmap is only ever modified via `currentActiveBitmap | (1 << slot)` where
    //   slot < 20 (L371 enforces), so bits 20-31 are structurally always 0.
    // - pendingEditSet is only ever modified via `pendingEditSet | (1 << slot)` where slot < 20,
    //   so bits 20-31 are structurally always 0.
    // - _futureBitmapAfter (L416-444) iterates i = 0..19 and only modifies future bits 0-19.
    // - For bits NOT in pSet (i.e., i >= 20), future retains its currentActiveBitmap value
    //   (always 0).
    // - Therefore _popcount32(future) is mathematically capped at 20.
    //
    // Disposition: defensive guard, no test path. The 20-slot fill smoke (next it-block) verifies
    // the cap is approached cleanly; no it-block attempts to drive the unreachable 21st-slot
    // path. Per Blocker #2 resolution, attempting to forge `currentActiveBitmap > 0xFFFFF` via
    // hardhat_setStorageAt would test artificial state, not real reachability — explicitly
    // forbidden. Phase 257 audit cites this verdict and grep-proves unreachability as a SAFE row
    // in AUDIT-02.
    it("20-slot fill via instant-apply succeeds; activeCount() == 20 and currentActiveBitmap == 0xFFFFF", async function () {
      const { charity, deployer, recipient1, recipient2, recipient3, others } =
        await loadFixture(deployGNRUSFixture);

      // Build 20 distinct recipient addresses: recipient1 + recipient2 + recipient3 + others[1..17]
      // (recipient3 is itself others[0] per fixture, so start the slice at others[1] to avoid duplicates).
      const recipients = [
        recipient1.address,
        recipient2.address,
        recipient3.address,
        ...others.slice(1, 18).map((s) => s.address),
      ];
      expect(recipients.length).to.equal(20);

      for (let slot = 0; slot < 20; slot++) {
        await setCharityFromVaultOwner(charity, deployer, slot, recipients[slot]);
      }

      expect(await charity.activeCount()).to.equal(20n);
      expect(await charity.currentActiveBitmap()).to.equal(0xFFFFFn);
    });
  });

  // -------------------------------------------------------------------
  //  Section 5: setCharity -- edit-queue level-boundary semantics (TST-02)
  // -------------------------------------------------------------------
  describe("setCharity -- edit-queue level-boundary semantics", function () {
    it("queued replace: level L pays OLD recipient; new recipient appears in slate only at L+1", async function () {
      const { charity, charityAddress, deployer, recipient1, recipient2, voter1, voter2, gameAddress } =
        await loadFixture(deployGNRUSFixture);

      // Setup: instant-apply slot 5 → recipient1; queue-replace slot 5 → recipient2.
      // Slot 5 is still active in current slate during level L.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);

      // Both voters cast for slot 5 — they observe slot 5 as filled (currentSlate[5] = recipient1
      // until pickCharity flush, which now runs AFTER payout per FIX-01).
      await charity.connect(voter1).vote(5);
      await charity.connect(voter2).vote(5);

      const level = await charity.currentLevel();
      expect(await charity.slotApproveWeight(level, 5)).to.equal(200n);

      // Pre-pickCharity: currentSlate[5] still recipient1; pendingEdit[5] = recipient2.
      expect(await charity.getCharity(5)).to.equal(recipient1.address);

      // Capture the pre-payout unallocated GNRUS balance to compute the expected 2% distribution.
      const unallocatedBefore = await charity.balanceOf(charityAddress);
      const expectedDistribution = (unallocatedBefore * DISTRIBUTION_BPS) / BPS_DENOM;

      const recipient1BalBefore = await charity.balanceOf(recipient1.address);
      const recipient2BalBefore = await charity.balanceOf(recipient2.address);

      const tx = await runLevelTransitionViaGame(charity, gameAddress, level);

      // Payment lands on recipient1 (OLD recipient — slot 5's value at the moment voters chose).
      expect((await charity.balanceOf(recipient1.address)) - recipient1BalBefore).to.equal(expectedDistribution);
      expect((await charity.balanceOf(recipient2.address)) - recipient2BalBefore).to.equal(0n);

      // LevelResolved event names recipient1 (OLD).
      const resolved = await getEvent(tx, charity, "LevelResolved");
      expect(resolved.args.slot).to.equal(5n);
      expect(resolved.args.recipient).to.equal(recipient1.address);
      expect(resolved.args.gnrusDistributed).to.equal(expectedDistribution);

      // Post-flush state: queued recipient2 is now in slot 5; pending bit cleared.
      expect(await charity.getCharity(5)).to.equal(recipient2.address);
      expect(await charity.pendingEditSet()).to.equal(0n);

      // CharityFlushed emitted for slot 5 with recipient2.
      const flushed = await getEvent(tx, charity, "CharityFlushed");
      expect(flushed.args.slot).to.equal(5n);
      expect(flushed.args.recipient).to.equal(recipient2.address);

      // lastWinningRecipient updated to recipient1 (FIX-02; written in the paid branch).
      expect(await charity.lastWinningRecipient()).to.equal(recipient1.address);
    });

    it("queued remove: slot still votable until flush", async function () {
      const { charity, deployer, recipient1, voter1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      // Queue remove (`setCharity(5, 0)`); slot still active in current slate.
      await setCharityFromVaultOwner(charity, deployer, 5, ZERO_ADDRESS);
      await charity.connect(voter1).vote(5);
      const level = await charity.currentLevel();
      expect(await charity.slotApproveWeight(level, 5)).to.equal(100n);
    });

    it("after pickCharity flush: queued edits visible in current slate, dead pending entries cleared", async function () {
      const { charity, deployer, recipient1, recipient2, recipient3, others, voter1, gameAddress } =
        await loadFixture(deployGNRUSFixture);

      // Setup: instant-apply slots 5, 7, 9 with three distinct recipients.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 7, recipient2.address);
      await setCharityFromVaultOwner(charity, deployer, 9, recipient3.address);

      // Queue mutations: slot 5 replace → others[1], slot 7 remove, slot 9 replace → others[2].
      const replacement5 = others[1].address;
      const replacement9 = others[2].address;
      await setCharityFromVaultOwner(charity, deployer, 5, replacement5);
      await setCharityFromVaultOwner(charity, deployer, 7, ZERO_ADDRESS);
      await setCharityFromVaultOwner(charity, deployer, 9, replacement9);

      // Cast a vote so the level resolves with a winner (skip-path B otherwise drops us
      // through to LevelSkipped — flush still happens, but we want to assert post-flush state
      // either way; voting on slot 5 keeps the post-flush sequence cleanly distinguishable).
      await charity.connect(voter1).vote(5);

      const level = await charity.currentLevel();
      const tx = await runLevelTransitionViaGame(charity, gameAddress, level);

      // CharityFlushed events: one per applied edit (3 edits).
      const flushed = await getEvents(tx, charity, "CharityFlushed");
      expect(flushed.length).to.equal(3);

      // Post-flush current slate reflects queued edits.
      expect(await charity.getCharity(5)).to.equal(replacement5);
      expect(await charity.getCharity(7)).to.equal(ZERO_ADDRESS);
      expect(await charity.getCharity(9)).to.equal(replacement9);

      // pendingEditSet zeroed; getPendingEdits returns empty.
      expect(await charity.pendingEditSet()).to.equal(0n);
      const [pendingSlots, pendingRecipients] = await charity.getPendingEdits();
      expect(pendingSlots.length).to.equal(0);
      expect(pendingRecipients.length).to.equal(0);
    });
  });

  // -------------------------------------------------------------------
  //  Section 6: vote(uint8 slot) (TST-03)
  //  Covers all 4 reject paths via reason codes, multi-slot independence
  //  (D-256-MULTI-VOTE-01), hasVoted state, and revert order
  //  (InvalidSlot fires before EMPTY_SLOT per contracts/GNRUS.sol:558-573).
  //  The locked-slot vote positive case (D-256-LOCKED-SLOT-01) lives in
  //  Section 3 only — keeping it out of Section 6 avoids duplication.
  // -------------------------------------------------------------------
  describe("vote(uint8 slot)", function () {
    it("single-slot vote applies full sDGNRS weight and emits Voted", async function () {
      const { charity, deployer, recipient1, voter1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      const tx = await charity.connect(voter1).vote(5);
      const ev = await getEvent(tx, charity, "Voted");
      expect(ev.args.level).to.equal(0n);
      expect(ev.args.slot).to.equal(5n);
      expect(ev.args.voter).to.equal(voter1.address);
      expect(ev.args.weight).to.equal(100n);
      expect(await charity.slotApproveWeight(0, 5)).to.equal(100n);
    });

    it("multi-slot vote independence: voter1 votes slots 3, 5, 7 — full weight each (D-256-MULTI-VOTE-01)", async function () {
      // D-256-MULTI-VOTE-01: a single voter casting on N slots in one level applies the FULL
      // sDGNRS-derived weight to EACH slot independently (sum across slots = N * weight, NOT
      // weight / N). hasVoted is keyed per (level, voter, slot), not per (level, voter).
      const { charity, deployer, recipient1, recipient2, recipient3, voter1 } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 3, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      await setCharityFromVaultOwner(charity, deployer, 7, recipient3.address);

      const tx3 = await charity.connect(voter1).vote(3);
      const tx5 = await charity.connect(voter1).vote(5);
      const tx7 = await charity.connect(voter1).vote(7);

      const ev3 = await getEvent(tx3, charity, "Voted");
      const ev5 = await getEvent(tx5, charity, "Voted");
      const ev7 = await getEvent(tx7, charity, "Voted");
      expect(ev3.args.weight).to.equal(100n);
      expect(ev5.args.weight).to.equal(100n);
      expect(ev7.args.weight).to.equal(100n);

      expect(await charity.slotApproveWeight(0, 3)).to.equal(100n);
      expect(await charity.slotApproveWeight(0, 5)).to.equal(100n);
      expect(await charity.slotApproveWeight(0, 7)).to.equal(100n);
      // Sum across the three slots = 300 (NOT 100 / 3 = 33).
      const sum =
        (await charity.slotApproveWeight(0, 3)) +
        (await charity.slotApproveWeight(0, 5)) +
        (await charity.slotApproveWeight(0, 7));
      expect(sum).to.equal(300n);
    });

    it("hasVoted is set per (level, voter, slot) tuple after vote", async function () {
      const { charity, deployer, recipient1, voter1, voter2 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);

      // Positive: the exact (level, voter, slot) tuple is set.
      expect(await charity.hasVoted(0, voter1.address, 5)).to.equal(true);

      // Negative: other slots for the same voter / level are not set.
      expect(await charity.hasVoted(0, voter1.address, 7)).to.equal(false);

      // Negative: other voters at the same (level, slot) are not set.
      expect(await charity.hasVoted(0, voter2.address, 5)).to.equal(false);

      // Negative: same (voter, slot) at a different level is not set.
      expect(await charity.hasVoted(1, voter1.address, 5)).to.equal(false);
    });

    it("InvalidSlot on slot == 20 (boundary)", async function () {
      const { charity, voter1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(voter1).vote(20)
      ).to.be.revertedWithCustomError(charity, "InvalidSlot");
    });

    it("InvalidSlot on slot == 255 (uint8 max)", async function () {
      const { charity, voter1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(voter1).vote(255)
      ).to.be.revertedWithCustomError(charity, "InvalidSlot");
    });

    it("VoteRejected(REJECT_EMPTY_SLOT) on slot never filled", async function () {
      // Slot 7 is in-bounds (< 20) but currentSlate[7] == address(0); contracts/GNRUS.sol L563.
      const { charity, voter1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(voter1).vote(7)
      )
        .to.be.revertedWithCustomError(charity, "VoteRejected")
        .withArgs(REJECT_EMPTY_SLOT);
    });

    it("VoteRejected(REJECT_ALREADY_VOTED) on second vote for same (level, voter, slot)", async function () {
      const { charity, deployer, recipient1, voter1 } = await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);
      await expect(
        charity.connect(voter1).vote(5)
      )
        .to.be.revertedWithCustomError(charity, "VoteRejected")
        .withArgs(REJECT_ALREADY_VOTED);
    });

    it("VoteRejected(REJECT_ZERO_WEIGHT) on sub-1e18 sDGNRS balance (integer-floor path)", async function () {
      // D-256-VOTE-REJECT-01: explicitly exercise the `weight = balanceOf / 1e18` integer
      // floor at contracts/GNRUS.sol L572-573. A non-zero sub-1e18 balance flows past
      // EMPTY_SLOT and ALREADY_VOTED checks and reverts at the weight comparison — proving
      // the floor is the actual gate (not a balance == 0 short-circuit).
      const { charity, deployer, recipient1, sdgnrs, gameAddress, others } =
        await loadFixture(deployGNRUSFixture);
      const subWhole = others[5];
      await giveSDGNRS(sdgnrs, gameAddress, subWhole.address, eth("0.5")); // 5e17 → floor = 0
      // Sanity check: balance is non-zero but sub-1e18.
      expect(await sdgnrs.balanceOf(subWhole.address)).to.equal(eth("0.5"));

      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await expect(
        charity.connect(subWhole).vote(5)
      )
        .to.be.revertedWithCustomError(charity, "VoteRejected")
        .withArgs(REJECT_ZERO_WEIGHT);
    });

    it("vote revert order: InvalidSlot fires before EMPTY_SLOT (slot=20, never-filled slate)", async function () {
      // Verifies the explicit revert order at contracts/GNRUS.sol L560-563:
      // bounds check (InvalidSlot) precedes the EMPTY_SLOT check. With slot=20 on a
      // pristine slate (no setCharity calls), both gates would semantically apply, but
      // only InvalidSlot is observable.
      const { charity, voter1 } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(voter1).vote(20)
      ).to.be.revertedWithCustomError(charity, "InvalidSlot");
    });
  });

  // -------------------------------------------------------------------
  //  Section NN: vote(uint8 slot) -- previous-winner block (FIX-02)
  //  Covers PreviousWinnerNotVotable across three semantic cases:
  //    (a) winner blocked at L+1 via the slot it occupied at L
  //    (b) queue-replace of the winning slot's recipient unblocks at L+1
  //    (c) skipped level retains the L-1 winner block
  // -------------------------------------------------------------------
  describe("vote(uint8 slot) -- previous-winner block (FIX-02)", function () {
    it("(a) charity that won level L cannot be voted for at L+1 via the slot it occupied", async function () {
      const { charity, deployer, recipient1, voter1, voter2, gameAddress } =
        await loadFixture(deployGNRUSFixture);

      // Setup: slot 5 = recipient1; voter1 casts for slot 5 in level L.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);

      // Resolve level L — recipient1 wins; lastWinningRecipient = recipient1.
      const level = await charity.currentLevel();
      await runLevelTransitionViaGame(charity, gameAddress, level);
      expect(await charity.lastWinningRecipient()).to.equal(recipient1.address);

      // Slot 5 still holds recipient1 (no queued edit between L and L+1) — vote(5) at L+1 must revert.
      expect(await charity.getCharity(5)).to.equal(recipient1.address);
      await expect(
        charity.connect(voter2).vote(5)
      ).to.be.revertedWithCustomError(charity, "PreviousWinnerNotVotable");
    });

    it("(b) queue-replace of winning slot recipient between L payout and L+1 vote unblocks the slot", async function () {
      const { charity, deployer, recipient1, recipient2, voter1, voter2, gameAddress } =
        await loadFixture(deployGNRUSFixture);

      // Setup: slot 5 = recipient1; voter1 casts for slot 5 in level L.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);
      const levelL = await charity.currentLevel();

      // Resolve level L — recipient1 wins; the queue-replace setCharity(5, recipient2) is staged
      // BEFORE pickCharity(L) so the post-payout flush flips slot 5 to recipient2.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      await runLevelTransitionViaGame(charity, gameAddress, levelL);

      // Post-flush: slot 5 = recipient2; lastWinningRecipient = recipient1 (paid branch).
      expect(await charity.getCharity(5)).to.equal(recipient2.address);
      expect(await charity.lastWinningRecipient()).to.equal(recipient1.address);

      // vote(5) at L+1 succeeds because currentSlate[5] = recipient2 != lastWinningRecipient.
      await expect(charity.connect(voter2).vote(5)).to.not.be.reverted;
      const levelLp1 = await charity.currentLevel();
      expect(levelLp1).to.equal(levelL + 1n);
      expect(await charity.slotApproveWeight(levelLp1, 5)).to.be.gt(0n);
    });

    it("(c) skipped level retains the prior winner block (lastWinningRecipient unchanged on skip)", async function () {
      const { charity, deployer, recipient1, voter1, voter2, gameAddress } =
        await loadFixture(deployGNRUSFixture);

      // Level L-1: setup, vote, resolve — recipient1 wins; lastWinningRecipient = recipient1.
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);
      const levelLm1 = await charity.currentLevel();
      await runLevelTransitionViaGame(charity, gameAddress, levelLm1);
      expect(await charity.lastWinningRecipient()).to.equal(recipient1.address);

      // Level L: NO new votes cast (skip-path B candidate — bestSlot == type(uint8).max).
      // BUT slot 5 still holds recipient1, so any voter at L would also be blocked by the
      // PreviousWinnerNotVotable guard. We rely on no votes being cast → bestSlot = 0xFF → skip.
      // Resolve L — emits LevelSkipped; lastWinningRecipient is NOT touched in skip path.
      const levelL = await charity.currentLevel();
      const tx = await runLevelTransitionViaGame(charity, gameAddress, levelL);
      const skipped = await getEvent(tx, charity, "LevelSkipped");
      expect(skipped.args.level).to.equal(levelL);
      expect(await charity.lastWinningRecipient()).to.equal(recipient1.address);

      // Level L+1: slot 5 still holds recipient1 → PreviousWinnerNotVotable still fires.
      expect(await charity.getCharity(5)).to.equal(recipient1.address);
      await expect(
        charity.connect(voter2).vote(5)
      ).to.be.revertedWithCustomError(charity, "PreviousWinnerNotVotable");
    });
  });

  // -------------------------------------------------------------------
  //  Section 7: pickCharity(uint24 level) (TST-04 + D-256-PICKCHARITY-REJECT-01 + D-256-TIEBREAK-01)
  //  Covers both PickCharityRejected reason codes (NOT_ACTIVE direct,
  //  ALREADY_RESOLVED via hardhat_setStorageAt-driven state per Blocker #1),
  //  Unauthorized (onlyGame), idempotence ordering (L606-608: state writes
  //  before flush+winner+distribution), single-active winner with distribution
  //  math (DISTRIBUTION_BPS / BPS_DENOM), multi-vote winner, tie-break (D-256-
  //  TIEBREAK-01 cases A and B), and all 3 LevelSkipped paths (A: zero active
  //  slots after flush; B: zero votes / bestSlot stays at 0xFF; C: 2% rounds
  //  to zero via deterministic balanceOf storage write per Warning #5).
  // -------------------------------------------------------------------
  describe("pickCharity(uint24 level)", function () {
    it("PickCharityRejected(REJECT_LEVEL_NOT_ACTIVE) on wrong-level call", async function () {
      const { charity, gameAddress } = await loadFixture(deployGNRUSFixture);
      const gameSigner = await impersonate(gameAddress);
      await expect(charity.connect(gameSigner).pickCharity(5))
        .to.be.revertedWithCustomError(charity, "PickCharityRejected")
        .withArgs(REJECT_LEVEL_NOT_ACTIVE);
      await stopImpersonating(gameAddress);
    });

    it("PickCharityRejected(REJECT_LEVEL_ALREADY_RESOLVED) on re-call with already-resolved level", async function () {
      // Blocker #1 resolution per checker iteration 1 — drive state directly via
      // hardhat_setStorageAt rather than dropping the test. Storage layout per
      // contracts/GNRUS.sol L144-184:
      //   slot 0 = totalSupply (uint256)
      //   slot 1 = balanceOf (mapping address => uint256)
      //   slot 2 = currentLevel(3) + finalized(1) + currentActiveBitmap(4) + pendingEditSet(4) packed
      //   slot 3 = levelResolved (mapping uint24 => bool)
      // For levelResolved[level], slot index = keccak256(abi.encode(uint24(level), uint256(3))).
      // We set levelResolved[0] = true while leaving currentLevel == 0 unchanged.
      // This produces (level == currentLevel) AND (levelResolved[level] == true)
      // → first check passes (level != currentLevel is false), second check fires.
      const { charity, charityAddress, gameAddress } = await loadFixture(deployGNRUSFixture);
      const levelResolvedSlot = hre.ethers.keccak256(
        hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint24", "uint256"], [0, 3])
      );
      await hre.network.provider.send("hardhat_setStorageAt", [
        charityAddress,
        levelResolvedSlot,
        "0x0000000000000000000000000000000000000000000000000000000000000001",
      ]);
      // Verify forged state.
      expect(await charity.levelResolved(0)).to.equal(true);
      expect(await charity.currentLevel()).to.equal(0);

      const gameSigner = await impersonate(gameAddress);
      await expect(charity.connect(gameSigner).pickCharity(0))
        .to.be.revertedWithCustomError(charity, "PickCharityRejected")
        .withArgs(REJECT_LEVEL_ALREADY_RESOLVED);
      await stopImpersonating(gameAddress);
    });

    it("pickCharity called by non-game reverts Unauthorized", async function () {
      const { charity, deployer } = await loadFixture(deployGNRUSFixture);
      await expect(
        charity.connect(deployer).pickCharity(0)
      ).to.be.revertedWithCustomError(charity, "Unauthorized");
    });

    it("idempotence: state writes (levelResolved + currentLevel) happen BEFORE flush + winner", async function () {
      // Locks the L606-608 ordering: levelResolved[level] = true and currentLevel = level + 1
      // are SET FIRST in pickCharity, BEFORE the flush/winner/distribution work. After a clean
      // resolve at level 0 we observe both writes regardless of which downstream path is taken.
      const { charity, deployer, recipient1, voter1, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);
      await runLevelTransitionViaGame(charity, gameAddress, 0);
      expect(await charity.levelResolved(0)).to.equal(true);
      expect(await charity.currentLevel()).to.equal(1n);
    });

    it("single-active-slot wins; LevelResolved fires with correct slot, recipient, distribution", async function () {
      const { charity, charityAddress, deployer, recipient1, voter1, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);

      // Snapshot unallocated before transition so we can compute expected distribution.
      const unallocatedBefore = await charity.balanceOf(charityAddress);
      const expectedDistribution = (unallocatedBefore * DISTRIBUTION_BPS) / BPS_DENOM;

      const tx = await runLevelTransitionViaGame(charity, gameAddress, 0);
      const ev = await getEvent(tx, charity, "LevelResolved");
      expect(ev.args.level).to.equal(0n);
      expect(ev.args.slot).to.equal(5n);
      expect(ev.args.recipient).to.equal(recipient1.address);
      expect(ev.args.gnrusDistributed).to.equal(expectedDistribution);

      // Sanity: recipient balance moved by exactly the distribution.
      expect(await charity.balanceOf(recipient1.address)).to.equal(expectedDistribution);
      expect(await charity.balanceOf(charityAddress)).to.equal(unallocatedBefore - expectedDistribution);
    });

    it("multi-vote highest-weight wins (no tie)", async function () {
      const { charity, deployer, recipient1, recipient2, voter1, voter3, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 7, recipient2.address);
      await charity.connect(voter1).vote(5); // weight 100
      await charity.connect(voter3).vote(7); // weight 200

      const tx = await runLevelTransitionViaGame(charity, gameAddress, 0);
      const ev = await getEvent(tx, charity, "LevelResolved");
      expect(ev.args.slot).to.equal(7n);
      expect(ev.args.recipient).to.equal(recipient2.address);
    });

    it("tie → lowest slot index wins (D-256-TIEBREAK-01 case A: 200 vs 100+100)", async function () {
      // voter3 (200) votes slot 3; voter1 (100) + voter2 (100) vote slot 5.
      // Both slots end at weight 200 — strict `>` keeps bestSlot at the first slot scanned.
      const { charity, deployer, recipient1, recipient2, voter1, voter2, voter3, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 3, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      await charity.connect(voter3).vote(3); // 200
      await charity.connect(voter1).vote(5); // 100
      await charity.connect(voter2).vote(5); // 100 → slot 5 total = 200

      const tx = await runLevelTransitionViaGame(charity, gameAddress, 0);
      const ev = await getEvent(tx, charity, "LevelResolved");
      expect(ev.args.slot).to.equal(3n);
      expect(ev.args.recipient).to.equal(recipient1.address);
    });

    it("4-way tie at slots 3, 5, 7, 11 → slot 3 wins (D-256-TIEBREAK-01 case B)", async function () {
      // Four fresh voters each weight 100; one vote per tied slot. Avoid voter3 (200 weight
      // would break the tie). Use others[7..10] and fund each with 100 sDGNRS via giveSDGNRS.
      const { charity, deployer, recipient1, recipient2, recipient3, others, sdgnrs, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 3, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient2.address);
      await setCharityFromVaultOwner(charity, deployer, 7, recipient3.address);
      await setCharityFromVaultOwner(charity, deployer, 11, others[6].address);

      const tieVoters = [others[7], others[8], others[9], others[10]];
      for (const v of tieVoters) {
        await giveSDGNRS(sdgnrs, gameAddress, v.address, eth("100"));
      }
      await charity.connect(tieVoters[0]).vote(3);
      await charity.connect(tieVoters[1]).vote(5);
      await charity.connect(tieVoters[2]).vote(7);
      await charity.connect(tieVoters[3]).vote(11);
      // Sanity — all four slots at 100.
      expect(await charity.slotApproveWeight(0, 3)).to.equal(100n);
      expect(await charity.slotApproveWeight(0, 5)).to.equal(100n);
      expect(await charity.slotApproveWeight(0, 7)).to.equal(100n);
      expect(await charity.slotApproveWeight(0, 11)).to.equal(100n);

      const tx = await runLevelTransitionViaGame(charity, gameAddress, 0);
      const ev = await getEvent(tx, charity, "LevelResolved");
      expect(ev.args.slot).to.equal(3n);
      expect(ev.args.recipient).to.equal(recipient1.address);
    });

    it("LevelSkipped path A: zero active slots after flush (currentActiveBitmap == 0)", async function () {
      const { charity, gameAddress } = await loadFixture(deployGNRUSFixture);
      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      await stopImpersonating(gameAddress);
      const skipped = await getEvents(tx, charity, "LevelSkipped");
      const resolved = await getEvents(tx, charity, "LevelResolved");
      expect(skipped.length).to.equal(1);
      expect(skipped[0].args.level).to.equal(0n);
      expect(resolved.length).to.equal(0);
    });

    it("LevelSkipped path B: zero votes cast (bestSlot stays at type(uint8).max)", async function () {
      // Active slates exist but no voter has cast a ballot — winner loop walks all 20 slots,
      // every slotApproveWeight(0, i) == 0, so bestSlot is never overwritten from 0xFF and the
      // skip-B branch fires.
      const { charity, deployer, recipient1, recipient2, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await setCharityFromVaultOwner(charity, deployer, 7, recipient2.address);
      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      await stopImpersonating(gameAddress);
      const skipped = await getEvents(tx, charity, "LevelSkipped");
      const resolved = await getEvents(tx, charity, "LevelResolved");
      expect(skipped.length).to.equal(1);
      expect(skipped[0].args.level).to.equal(0n);
      expect(resolved.length).to.equal(0);
    });

    it("LevelSkipped path C: 2% rounds to zero (deterministic storage write — Warning #5)", async function () {
      // Drive distribution-rounds-to-zero by overwriting the contract's GNRUS balance via
      // hardhat_setStorageAt. Storage layout per contracts/GNRUS.sol L144-147:
      //   slot 0 = totalSupply (uint256)
      //   slot 1 = balanceOf (mapping address => uint256)
      // For balanceOf[addr], slot index = keccak256(abi.encode(addr, uint256(1))).
      // 49 * DISTRIBUTION_BPS / BPS_DENOM = 49 * 200 / 10_000 = 0 → skip-path C fires.
      const { charity, charityAddress, deployer, recipient1, voter1, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      const balanceSlot = hre.ethers.keccak256(
        hre.ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [charityAddress, 1]
        )
      );
      await hre.network.provider.send("hardhat_setStorageAt", [
        charityAddress,
        balanceSlot,
        "0x0000000000000000000000000000000000000000000000000000000000000031", // 49
      ]);
      expect(await charity.balanceOf(charityAddress)).to.equal(49n);

      // Active slot + vote so winner phase finds a non-zero weight (path B does not fire).
      await setCharityFromVaultOwner(charity, deployer, 5, recipient1.address);
      await charity.connect(voter1).vote(5);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      await stopImpersonating(gameAddress);

      const skipped = await getEvents(tx, charity, "LevelSkipped");
      const resolved = await getEvents(tx, charity, "LevelResolved");
      expect(skipped.length).to.equal(1);
      expect(skipped[0].args.level).to.equal(0n);
      expect(resolved.length).to.equal(0);
    });
  });

  // -------------------------------------------------------------------
  //  Section 8: post-gameover inertness (TST-06, D-256-POSTGAMEOVER-01)
  //
  //  Two it-blocks per Blocker #3 resolution:
  //    (a) GNRUS-side state assertion after burnAtGameOver — balanceOf zeroed,
  //        totalSupply decremented by the unallocated amount, finalized() == true.
  //    (b) Positive inertness smoke — setCharity and vote post-burnAtGameOver
  //        do NOT revert. v33 contract has no `finalized` guard on these paths;
  //        inertness comes from absence of game-side caller (the only pickCharity
  //        caller — DegenerusGameAdvanceModule:1634 — stops at gameover), NOT from
  //        any contract-level guard. This test empirically verifies no revert path
  //        was inadvertently introduced — satisfies ROADMAP SC-5 wording
  //        ("subsequent calls to setCharity / vote either revert or are inert").
  // -------------------------------------------------------------------
  describe("post-gameover inertness (TST-06)", function () {
    it("after burnAtGameOver: balanceOf(charityAddress) == 0, totalSupply -= unallocated, finalized() == true", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployGNRUSFixture);

      const unallocatedBefore = await charity.balanceOf(charityAddress);
      const totalSupplyBefore = await charity.totalSupply();
      expect(unallocatedBefore).to.be.gt(0n); // Sanity — fixture mints 1T to address(this).

      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      expect(await charity.balanceOf(charityAddress)).to.equal(0n);
      expect(await charity.totalSupply()).to.equal(totalSupplyBefore - unallocatedBefore);
      expect(await charity.finalized()).to.equal(true);
    });

    it("inertness smoke: setCharity and vote after burnAtGameOver do NOT revert (inert by absence)", async function () {
      // v33 contract has no `finalized` guard on setCharity / vote / pickCharity. Inertness
      // comes from absence of game-side caller (DegenerusGameAdvanceModule:1634 is the only
      // pickCharity caller, and the game stops at gameover), NOT from contract-level guards.
      // This positive smoke empirically verifies no revert path was inadvertently introduced
      // — satisfies ROADMAP SC-5 wording ("subsequent calls to setCharity / vote either revert
      // or are inert"). Drives the chosen behavior (inert) for the test record.
      const { charity, deployer, recipient1, voter1, gameAddress } =
        await loadFixture(deployGNRUSFixture);
      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      // setCharity from vault owner — instant-apply on empty slot, must not revert.
      await expect(
        charity.connect(deployer).setCharity(5, recipient1.address)
      ).to.not.be.reverted;
      // vote from a sDGNRS-funded voter against the freshly-applied slot — must not revert.
      await expect(
        charity.connect(voter1).vote(5)
      ).to.not.be.reverted;
    });
  });

  // -------------------------------------------------------------------
  //  Section 9: gas guardrail (D-256-GAS-01)
  //
  //  Single measurement: pickCharity full-slate worst case — 20 slots active +
  //  one vote per slot (all weighted) + 17 pending edits queued (slots 0/1/2 are
  //  locked so cannot have pending edits). Theoretical ceiling derived inline in
  //  256-03c-PLAN.md objective: ≈622k gas; ×1.1 buffer → CEILING = 700_000.
  //  The gas log line lets future runs spot regressions before the ceiling is hit.
  // -------------------------------------------------------------------
  describe("gas guardrail (D-256-GAS-01)", function () {
    it("pickCharity full-slate worst case: gasUsed < PICK_CHARITY_CEILING_GAS", async function () {
      const {
        charity,
        deployer,
        recipient1,
        recipient2,
        recipient3,
        voter1,
        voter2,
        voter3,
        others,
        sdgnrs,
        gameAddress,
      } = await loadFixture(deployGNRUSFixture);

      // (a) 20 distinct recipients for slots 0..19. others[0] === recipient3 per fixture, so
      //     start the slice at others[1] to keep recipients unique.
      const recipients = [
        recipient1.address,
        recipient2.address,
        recipient3.address,
        ...others.slice(1, 18).map((s) => s.address),
      ];
      expect(recipients.length).to.equal(20);
      for (let slot = 0; slot < 20; slot++) {
        await setCharityFromVaultOwner(charity, deployer, slot, recipients[slot]);
      }
      expect(await charity.activeCount()).to.equal(20n);

      // (b) One vote per slot, every slot weighted. voter1/voter2/voter3 already funded
      //     by the fixture (100/100/200). Fund 17 extra voters and assign each to a slot 3..19.
      const extraVoters = others.slice(50, 67);
      expect(extraVoters.length).to.equal(17);
      for (const v of extraVoters) {
        await giveSDGNRS(sdgnrs, gameAddress, v.address, eth("100"));
      }
      await charity.connect(voter1).vote(0);
      await charity.connect(voter2).vote(1);
      await charity.connect(voter3).vote(2);
      for (let i = 0; i < 17; i++) {
        await charity.connect(extraVoters[i]).vote(3 + i);
      }

      // (c) Queue 17 pending replaces on slots 3..19 (slots 0/1/2 are locked — cannot queue).
      const replacements = others.slice(70, 87);
      expect(replacements.length).to.equal(17);
      for (let i = 0; i < 17; i++) {
        await setCharityFromVaultOwner(charity, deployer, 3 + i, replacements[i].address);
      }
      // Sanity — pendingEditSet bits 3..19 should all be set; popcount = 17.
      // Bits 3..19 inclusive = 0xFFFF8 (slots 3..19 set, slots 0/1/2 clear, slots 20+ clear).
      expect(await charity.pendingEditSet()).to.equal(0xFFFF8n);

      // (d) Impersonate game and measure pickCharity.
      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const receipt = await tx.wait();
      await stopImpersonating(gameAddress);

      // Visibility log for future tightening — see PLAN.md objective for the derivation.
      console.log(`      [gas] pickCharity worst-case: ${receipt.gasUsed.toString()}`);

      expect(receipt.gasUsed).to.be.lt(PICK_CHARITY_CEILING_GAS);
    });
  });
});
