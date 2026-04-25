import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { advanceTime } from "../helpers/testUtils.js";

/**
 * LivenessProductivePause — focused unit test for the _livenessTriggered
 * productive-phase short-circuit at DegenerusGameStorage.sol:1247.
 *
 * The day-based liveness clock fires when currentDay - purchaseStartDay
 * exceeds 365 days (level 0) or 120 days (level 1+). purchaseStartDay
 * only updates at AdvanceModule:330 (phase-transition close), so the
 * multi-call window between target-met and the next purchase phase
 * carries the old psd. If liveness fires inside that window,
 * _handleGameOverPath is unreachable (gated by !inJackpot && !lastPurchase
 * at AdvanceModule:182) and execution falls into _queueTickets paths that
 * revert on the unconditional liveness guard, leaving rngLockedFlag stuck.
 *
 * Fix: _livenessTriggered short-circuits to false while lastPurchaseDay
 * or jackpotPhaseFlag is set. phaseTransitionActive is implied by
 * jackpotPhaseFlag throughout the transition window.
 *
 * Slot 0 layout (low byte first):
 *   [17] jackpotPhaseFlag        bool
 *   [19] lastPurchaseDay         bool
 *
 * In a "0x" + 64-char hex string, byte N is at hex index
 * (31 - N) * 2 + 2:
 *   jackpotPhaseFlag (byte 17) → chars 30..32
 *   lastPurchaseDay  (byte 19) → chars 26..28
 */
describe("LivenessProductivePause", function () {
  after(function () {
    restoreAddresses();
  });

  /**
   * Replace one byte in a 32-byte hex slot value (preserving length).
   * @param slotHex  "0x" + 64 hex chars
   * @param byteIdx  byte position [0..31] from low (right) end
   * @param byteHex  2-char replacement (e.g. "01")
   */
  function setByte(slotHex, byteIdx, byteHex) {
    const charPos = (31 - byteIdx) * 2 + 2;
    return slotHex.slice(0, charPos) + byteHex + slotHex.slice(charPos + 2);
  }

  async function readSlot0(addr) {
    return hre.network.provider.send("eth_getStorageAt", [
      addr,
      "0x0",
      "latest",
    ]);
  }

  async function writeSlot0(addr, hexValue) {
    return hre.network.provider.send("hardhat_setStorageAt", [
      addr,
      "0x0",
      hexValue,
    ]);
  }

  it("baseline: livenessTriggered() returns true past the level-0 idle timeout", async function () {
    const { game } = await loadFixture(deployFullProtocol);

    // Level 0 idle timeout is 365 days from purchaseStartDay (set at deploy).
    // Warp past it.
    await advanceTime(366 * 86400);

    expect(await game.livenessTriggered()).to.equal(
      true,
      "baseline: liveness must fire past the 365-day deploy idle timeout"
    );
  });

  it("jackpotPhaseFlag=true pauses liveness past the death clock", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    // Poke jackpotPhaseFlag (byte 17) to 0x01.
    const slot0 = await readSlot0(addr);
    await writeSlot0(addr, setByte(slot0, 17, "01"));

    expect(await game.livenessTriggered()).to.equal(
      false,
      "fix: liveness must pause while jackpotPhaseFlag is set"
    );
  });

  it("lastPurchaseDay=true pauses liveness past the death clock", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    // Poke lastPurchaseDay (byte 19) to 0x01.
    const slot0 = await readSlot0(addr);
    await writeSlot0(addr, setByte(slot0, 19, "01"));

    expect(await game.livenessTriggered()).to.equal(
      false,
      "fix: liveness must pause while lastPurchaseDay is set"
    );
  });

  it("clearing the productive flag re-arms liveness on the same expired clock", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);

    const baseline = await readSlot0(addr);
    await writeSlot0(addr, setByte(baseline, 17, "01"));
    expect(await game.livenessTriggered()).to.equal(false);

    // Clear jackpotPhaseFlag — same elapsed days, liveness must fire again.
    await writeSlot0(addr, baseline);
    expect(await game.livenessTriggered()).to.equal(
      true,
      "regression guard: clearing productive flag re-arms the day clock"
    );
  });
});
