import { expect } from "chai";
import { deployFullProtocol } from "./deployFixture.js";
import { eth, advanceToNextDay, getLastVRFRequestId } from "./testUtils.js";

// MinerAction ordinals (DegenerusGameStorage.MinerAction).
const IDLE = 0n;
const WAIT = 2n;
export const MINER_HUMAN_BOXES = 10n;
export const MINER_REQUEST_MIDDAY = 18n;

// Name of the custom error a reverted mineFlip carried, if the Game ABI decodes it.
function minerRefusal(game, error) {
  for (let e = error; e; e = e.error ?? e.cause) {
    if (e.revert?.name) return e.revert.name;
    const data = typeof e.data === "string" ? e.data : e.data?.data;
    if (typeof data === "string" && data.length >= 10) {
      try {
        const parsed = game.interface.parseError(data);
        if (parsed) return parsed.name;
      } catch { /* not a Game error */ }
    }
  }
  const match = /custom error '(\w+)\(/.exec(String(error?.message ?? ""));
  return match ? match[1] : null;
}

/**
 * Call mineFlip as `signer` until the engine refuses with NoWork() or RngNotReady()
 * (or `maxCalls` is reached); any other revert is re-raised. Returns every receipt.
 */
export async function mineAll(game, signer, { maxCalls = 50, gasLimit } = {}) {
  const receipts = [];
  for (let i = 0; i < maxCalls; i++) {
    let tx;
    try {
      tx = await game.connect(signer).mineFlip(0, gasLimit ? { gasLimit } : {});
    } catch (error) {
      const name = minerRefusal(game, error);
      if (name === "NoWork" || name === "RngNotReady") return receipts;
      throw error;
    }
    receipts.push(await tx.wait());
  }
  return receipts;
}

/**
 * Issue the mid-day RNG request through mineFlip as an ordinary caller: the creditless
 * selector must already pick it (pending box ETH at or above the threshold), so the
 * request charges nothing. Returns the new VRF request id.
 */
export async function requestMiddayRng(game, signer, mockVRF) {
  expect(await game.nextMinerAction(), "a creditless caller's next action is the mid-day request")
    .to.equal(MINER_REQUEST_MIDDAY);
  const credit = await game.middayRngCredits(signer.address);
  const before = await getLastVRFRequestId(mockVRF);
  await (await game.connect(signer).mineFlip(0)).wait();
  const request = await getLastVRFRequestId(mockVRF);
  expect(request, "mid-day request issued").to.be.gt(before);
  expect(await game.middayRngCredits(signer.address), "an at-threshold request charges no credit").to.equal(credit);
  expect(await game.rngLocked(), "a mid-day request does not take the daily lock").to.equal(false);
  return request;
}

// Finish the first real daily VRF cycle before requesting an ordinary box word.
export async function readyDailyFixture() {
  const f = await deployFullProtocol();
  await f.mockVRF.fundSubscription(1, eth(100));
  await advanceToNextDay();
  for (let calls = 0; calls < 50 && !(await f.game.rngLocked()); calls++) {
    await f.game.connect(f.deployer).mineFlip(0);
  }
  expect(await f.game.rngLocked(), "daily request must engage").to.equal(true);
  const request = await getLastVRFRequestId(f.mockVRF);
  expect(request, "fresh real VRF request").to.be.gt(0n);
  await f.mockVRF.fulfillRandomWords(request, 0xB007n);
  for (let calls = 0; calls < 100 && await f.game.rngLocked(); calls++) {
    await f.game.connect(f.deployer).mineFlip(0);
  }
  expect(await f.game.rngLocked(), "daily work must finish within its bound").to.equal(false);
  // The engine keeps going after the daily seal: read consumers drain, and a shut
  // genesis Craps window is write-side request work that rides an ordinary mid-day
  // round. Settle every such round: mineFlip selects no fresh mid-day request until
  // the read cohort completes (rngComplete).
  let fulfilled = request;
  for (let calls = 0; calls < 100; calls++) {
    const action = await f.game.nextMinerAction();
    if (action === IDLE) break;
    if (action === WAIT) {
      const pending = await getLastVRFRequestId(f.mockVRF);
      expect(pending, "waiting engine must hold an unfulfilled request").to.be.gt(fulfilled);
      await f.mockVRF.fulfillRandomWords(pending, 0xB007n + pending);
      fulfilled = pending;
      continue;
    }
    await f.game.connect(f.deployer).mineFlip(0);
  }
  expect(await f.game.nextMinerAction(), "fixture settles to an idle engine").to.equal(IDLE);
  await expect(f.game.connect(f.deployer).mineFlip.staticCall(0), "no box or other engine work remains")
    .to.be.revertedWithCustomError(f.game, "NoWork");
  expect(await f.game.level(), "fixed live game level").to.equal(0n);
  expect(await f.game.boxesPending(), "fixture starts with no ready entries").to.equal(false);
  return f;
}
