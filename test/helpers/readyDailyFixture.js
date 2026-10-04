import { expect } from "chai";
import { deployFullProtocol } from "./deployFixture.js";
import { eth, advanceToNextDay, getLastVRFRequestId } from "./testUtils.js";

// MinerAction ordinals (DegenerusGameStorage.MinerAction).
const IDLE = 0n;
const WAIT = 2n;

// Finish the first real daily VRF cycle before requesting an ordinary box word.
export async function readyDailyFixture() {
  const f = await deployFullProtocol();
  await f.mockVRF.fundSubscription(1, eth(100));
  await advanceToNextDay();
  for (let calls = 0; calls < 50 && !(await f.game.rngLocked()); calls++) {
    await f.game.connect(f.deployer).mineFlip();
  }
  expect(await f.game.rngLocked(), "daily request must engage").to.equal(true);
  const request = await getLastVRFRequestId(f.mockVRF);
  expect(request, "fresh real VRF request").to.be.gt(0n);
  await f.mockVRF.fulfillRandomWords(request, 0xB007n);
  for (let calls = 0; calls < 100 && await f.game.rngLocked(); calls++) {
    await f.game.connect(f.deployer).mineFlip();
  }
  expect(await f.game.rngLocked(), "daily work must finish within its bound").to.equal(false);
  // The engine keeps going after the daily seal: read consumers drain, and a shut
  // genesis Craps window is write-side request work that rides an ordinary mid-day
  // round. Settle every such round so the next fresh request is not refused by the
  // read-cohort gate (requestLootboxRng reverts RngNotReady until rngComplete).
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
    await f.game.connect(f.deployer).mineFlip();
  }
  expect(await f.game.nextMinerAction(), "fixture settles to an idle engine").to.equal(IDLE);
  expect(await f.game.openBoxes.staticCall(1000), "no box remains for the compatibility door").to.equal(0n);
  expect(await f.game.level(), "fixed live game level").to.equal(0n);
  expect(await f.game.boxesPending(), "fixture starts with no ready entries").to.equal(false);
  return f;
}
