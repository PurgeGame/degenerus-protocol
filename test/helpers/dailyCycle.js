import { getEvents, getLastVRFRequestId } from "./testUtils.js";

// DegenerusGameStorage.MinerAction ordinals.
export const ACTION_IDLE = 0n;
export const ACTION_TERMINAL = 1n;
export const ACTION_WAIT = 2n;
export const ACTION_REQUEST_MIDDAY = 17n;

/**
 * Drive the engine through one logical day on the CURRENT wall day: run whatever the miner
 * selects next (maintenance, subscriptions, the daily request, publication, ticket drain,
 * daily apply/phase, consumers), deliver `word` to the daily request and a derived word to any
 * other waiting request, and stop when the engine is idle or its next step is an optional mid-day
 * request. Wall-clock time creates no day by itself, so callers advance the wall day first
 * (advanceToNextDay) when they want a fresh daily request to come due.
 *
 * Returns the last Advance stage observed (-1n when none). Stops without error at game over or
 * on a terminal selection; the caller asserts on those.
 */
export async function driveDailyCycle(game, signer, mockVRF, advanceModule, word, { maxCalls = 400 } = {}) {
  let lastStage = -1n;
  for (let i = 0; i < maxCalls; i++) {
    const action = await game.nextMinerAction();
    if (action === ACTION_IDLE || action === ACTION_REQUEST_MIDDAY || action === ACTION_TERMINAL) return lastStage;
    if (action === ACTION_WAIT) {
      const id = await getLastVRFRequestId(mockVRF);
      const daily = await game.rngLocked();
      await mockVRF.fulfillRandomWords(id, daily ? BigInt(word) : BigInt(word) ^ (0x5eedn + id));
      continue;
    }
    const tx = await game.connect(signer).mineRun(0, { gasLimit: 16_777_216 });
    const events = await getEvents(tx, advanceModule, "Advance");
    if (events.length > 0) lastStage = events[events.length - 1].args.stage;
  }
  throw new Error(`driveDailyCycle: engine did not settle within ${maxCalls} calls`);
}
