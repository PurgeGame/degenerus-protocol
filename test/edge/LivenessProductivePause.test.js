import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { advanceTime } from "../helpers/testUtils.js";

/**
 * LivenessProductivePause — focused unit test for the two clocks inside
 * _livenessTriggered (DegenerusGameStorage.sol).
 *
 * In-phase day clock: fires when currentDay - purchaseStartDay exceeds
 * 365 days (level 0) or 120 days (level 1+). purchaseStartDay only updates
 * at AdvanceModule phase-transition close, so the multi-call window between
 * target-met and the next purchase phase carries the old psd.
 *
 * Productive-phase pause: while lastPurchaseDay or jackpotPhaseFlag is set,
 * _livenessTriggered does NOT consult the in-phase day clock. Instead it
 * returns _vrfDeadmanFired() — the phase-independent VRF-death deadman,
 * (simulatedDayIndex - dailyIdx > 120). So during jackpot / last-purchase
 * the in-phase clock is suppressed (it would false-fire in the productive
 * window and deadlock _queueEntries), but a permanently-stalled game still
 * reaches terminal fund release once no day has sealed for 120 days.
 *
 *   _livenessTriggered():
 *     if (lastPurchaseDay || jackpotPhaseFlag) return _vrfDeadmanFired();
 *     lvl 0  : currentDay - psd > 365  → true
 *     lvl 1+ : currentDay - psd > 120  → true
 *     else   : VRF-grace stall bailout
 *
 *   _vrfDeadmanFired(): simulatedDayIndex - dailyIdx > 120
 *
 * Slot 0 layout (low byte first, authoritative from
 * `forge inspect DegenerusGameStorage storage-layout`):
 *   [0]  purchaseStartDay  uint24
 *   [3]  dailyIdx          uint24
 *   [15] jackpotPhaseFlag  bool
 *   [17] lastPurchaseDay   bool
 *   [19] rngLockedFlag     bool
 *
 * In a "0x" + 64-char hex string, byte N is at hex index (31 - N) * 2 + 2,
 * i.e. byte 0 is the rightmost (least-significant) pair.
 */
describe("LivenessProductivePause", function () {
  after(function () {
    restoreAddresses();
  });

  // Slot 0 byte offsets (from the low/right end).
  const OFF_DAILY_IDX = 3;
  const OFF_JACKPOT_PHASE = 15;
  const OFF_LAST_PURCHASE = 17;

  function toHex2(v) {
    return (v & 0xff).toString(16).padStart(2, "0");
  }

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

  /** Write a little-endian-positioned uint24 at byteIdx (occupies 3 bytes). */
  function setUint24(slotHex, byteIdx, value) {
    let s = setByte(slotHex, byteIdx, toHex2(value));
    s = setByte(s, byteIdx + 1, toHex2(value >> 8));
    s = setByte(s, byteIdx + 2, toHex2(value >> 16));
    return s;
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
    // Warp past it. No productive flag set, so the in-phase clock governs.
    await advanceTime(366 * 86400);

    expect(await game.livenessTriggered()).to.equal(
      true,
      "baseline: liveness must fire past the 365-day deploy idle timeout"
    );
  });

  it("jackpotPhaseFlag pauses the in-phase clock while the deadman has not fired", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    // Set jackpotPhaseFlag and a fresh dailyIdx (== currentDay) so the deadman
    // (currentDay - dailyIdx > 120) is NOT fired. _livenessTriggered then
    // returns _vrfDeadmanFired() == false: the in-phase clock is suppressed.
    const currentDay = Number(await game.currentDayView());
    let slot0 = await readSlot0(addr);
    slot0 = setByte(slot0, OFF_JACKPOT_PHASE, "01");
    slot0 = setUint24(slot0, OFF_DAILY_IDX, currentDay);
    await writeSlot0(addr, slot0);

    expect(await game.livenessTriggered()).to.equal(
      false,
      "jackpotPhaseFlag suppresses the expired in-phase clock; deadman not fired"
    );
  });

  it("lastPurchaseDay pauses the in-phase clock while the deadman has not fired", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    const currentDay = Number(await game.currentDayView());
    let slot0 = await readSlot0(addr);
    slot0 = setByte(slot0, OFF_LAST_PURCHASE, "01");
    slot0 = setUint24(slot0, OFF_DAILY_IDX, currentDay);
    await writeSlot0(addr, slot0);

    expect(await game.livenessTriggered()).to.equal(
      false,
      "lastPurchaseDay suppresses the expired in-phase clock; deadman not fired"
    );
  });

  it("VRF-death deadman overrides the productive pause (jackpotPhaseFlag set, stale dailyIdx)", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    // dailyIdx is still 0 at deploy (no day sealed). Warping 366 days leaves
    // simulatedDayIndex - dailyIdx ~= 367 > 120, so the deadman has fired.
    await advanceTime(366 * 86400);

    const slot0 = await readSlot0(addr);
    await writeSlot0(addr, setByte(slot0, OFF_JACKPOT_PHASE, "01"));

    expect(await game.livenessTriggered()).to.equal(
      true,
      "deadman overrides the in-phase pause: no day sealed for >120 days"
    );
  });

  it("deadman threshold is exact: false at 120-day stall, true at 121 (jackpot phase)", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);
    const currentDay = Number(await game.currentDayView());

    // Stall of exactly 120 days (currentDay - dailyIdx == 120): deadman is
    // `120 > 120` == false, so the jackpot-phase pause still holds.
    let slot0 = await readSlot0(addr);
    slot0 = setByte(slot0, OFF_JACKPOT_PHASE, "01");
    slot0 = setUint24(slot0, OFF_DAILY_IDX, currentDay - 120);
    await writeSlot0(addr, slot0);
    expect(await game.livenessTriggered()).to.equal(
      false,
      "120-day stall: deadman not yet fired (strict > threshold)"
    );

    // One more day of stall (121): deadman fires, overriding the pause.
    slot0 = await readSlot0(addr);
    slot0 = setUint24(slot0, OFF_DAILY_IDX, currentDay - 121);
    await writeSlot0(addr, slot0);
    expect(await game.livenessTriggered()).to.equal(
      true,
      "121-day stall: deadman fires and overrides the pause"
    );
  });

  it("clearing the productive flag re-arms the in-phase day clock", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const addr = await game.getAddress();

    await advanceTime(366 * 86400);
    const currentDay = Number(await game.currentDayView());

    // Pause active (flag set, deadman not fired) → liveness false.
    const baseline = await readSlot0(addr);
    let paused = setByte(baseline, OFF_JACKPOT_PHASE, "01");
    paused = setUint24(paused, OFF_DAILY_IDX, currentDay);
    await writeSlot0(addr, paused);
    expect(await game.livenessTriggered()).to.equal(false);

    // Clear jackpotPhaseFlag — the in-phase level-0 clock (currentDay - psd >
    // 365) is consulted again on the same expired window and fires.
    await writeSlot0(addr, baseline);
    expect(await game.livenessTriggered()).to.equal(
      true,
      "regression guard: clearing the productive flag re-arms the day clock"
    );
  });
});
