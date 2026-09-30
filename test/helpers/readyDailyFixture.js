import { expect } from "chai";
import { deployFullProtocol } from "./deployFixture.js";
import { eth, advanceToNextDay, getLastVRFRequestId } from "./testUtils.js";

// Finish the first real daily VRF cycle before requesting an ordinary box word.
export async function readyDailyFixture() {
  const f = await deployFullProtocol();
  await f.mockVRF.fundSubscription(1, eth(100));
  await advanceToNextDay();
  for (let calls = 0; calls < 50 && !(await f.game.rngLocked()); calls++) {
    await f.game.connect(f.deployer).advanceGame();
  }
  expect(await f.game.rngLocked(), "daily request must engage").to.equal(true);
  const request = await getLastVRFRequestId(f.mockVRF);
  expect(request, "fresh real VRF request").to.be.gt(0n);
  await f.mockVRF.fulfillRandomWords(request, 0xB007n);
  for (let calls = 0; calls < 100 && await f.game.rngLocked(); calls++) {
    await f.game.connect(f.deployer).advanceGame();
  }
  expect(await f.game.rngLocked(), "daily work must finish within its bound").to.equal(false);
  await f.game.openBoxes(1000);
  expect(await f.game.level(), "fixed live game level").to.equal(0n);
  expect(await f.game.boxesPending(), "fixture starts with no ready entries").to.equal(false);
  return f;
}

