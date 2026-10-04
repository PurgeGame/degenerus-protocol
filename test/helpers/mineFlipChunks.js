// Gas witnesses for the checkpointed mining engine.
//
// Owner rule (2026-10-03): only the size of one chunk between checkpoints matters; a whole
// mineFlip transaction may legitimately approach 16M because every admitted chunk is
// budgeted. The engine keeps admitting chunks while the supplied gas covers the next
// declared bound (MineFlipGasBounds), so a transaction's total mirrors its own gas limit
// and is never bounded here. The properties these helpers assert are:
//   (1) one admitted chunk costs <= 10M in a realistic state (minimum-allowance probe),
//   (2) a call given a realistic allowance (10M, or the 16.7M block ceiling) succeeds and
//       makes progress: zero-progress calls revert (NoWork / RngNotReady /
//       InsufficientExecutionGas), so a successful receipt implies progress.
import { expect } from "chai";
import { getEvents, getLastVRFRequestId } from "./testUtils.js";

export const REALISTIC_ALLOWANCE = 10_000_000;
export const CEILING_ALLOWANCE = 16_700_000;
export const CHUNK_GAS_TARGET = 10_000_000n;
// A pre-daily allowance that admits publication and ticket-drain work but not the 3.6M
// DailyApply bound (plus engine reserves) behind it, so the daily phase that follows is
// walked one chunk at a time.
export const PRE_DAILY_ALLOWANCE = 3_500_000;

// DegenerusGameStorage.MinerAction ordinals.
export const MINER_IDLE = 0n;
export const MINER_WAIT = 2n;
export const MINER_PUBLISH = 3n;
export const MINER_TICKETS = 4n;

/** Advance stages carried by one receipt, in emission order (advanceModule ABI). */
export async function stagesOf(tx, advanceModule) {
  return (await getEvents(tx, advanceModule, "Advance")).map((e) => e.args.stage);
}

/** One mineFlip under a bounded caller allowance; success implies progress. */
export async function mine(game, signer, gasLimit = REALISTIC_ALLOWANCE) {
  const tx = await game.connect(signer).mineFlip({ gasLimit });
  const receipt = await tx.wait();
  expect(receipt.status, `mineFlip with a ${gasLimit} allowance must succeed`).to.equal(1);
  return { tx, receipt };
}

/**
 * Per-chunk probe: the smallest allowance at which the next mineFlip makes progress is
 * the next chunk's admission requirement (its declared bound plus the engine reserves).
 * A call at that allowance runs the next chunk; when that chunk spends well under its
 * bound, the leftover can also admit a following lighter-bound chunk, so the receipt
 * (incl. intrinsic) is an upper bound on the next chunk's measured cost.
 */
export async function minimumProgressAllowance(game, signer) {
  // The search tops out at the realistic 10M allowance: a chunk that needs more fails here.
  // (Probing far above it is also costly in Hardhat, whose per-call traces grow with the
  // number of chunks a single huge eth_call composes.)
  let lo = 400_000;
  let hi = REALISTIC_ALLOWANCE;
  try { await game.connect(signer).mineFlip.staticCall({ gasLimit: hi }); }
  catch (e) { expect.fail(`next chunk is not admitted under a realistic ${hi} allowance: ${e.message.slice(0, 120)}`); }
  while (hi - lo > 25_000) {
    const mid = Math.floor((lo + hi) / 2);
    try { await game.connect(signer).mineFlip.staticCall({ gasLimit: mid }); hi = mid; }
    catch { lo = mid; }
  }
  return hi;
}

/** Run the next chunk at its minimum admission allowance and assert both <= 10M. */
export async function measureNextChunk(game, signer, label) {
  const allowance = await minimumProgressAllowance(game, signer);
  const { tx, receipt } = await mine(game, signer, allowance);
  console.log(`      [CHUNK ${label}] admission allowance=${allowance.toLocaleString()} measured=${receipt.gasUsed.toLocaleString()} (incl. intrinsic)`);
  expect(BigInt(allowance), `${label}: next chunk admitted under a realistic 10M allowance`).to.be.lte(CHUNK_GAS_TARGET);
  expect(receipt.gasUsed, `${label}: measured chunk (upper bound) stays <= 10M`).to.be.lte(CHUNK_GAS_TARGET);
  return { allowance, tx, receipt };
}

/**
 * Walk the delivered daily cohort chunk by chunk: publication and the ticket drain run at
 * PRE_DAILY_ALLOWANCE, every later checkpoint runs at its own minimum admission allowance
 * (each asserted <= 10M). Stops at Idle, at the next VRF wait, or (untilUnlocked) as soon
 * as the daily lock is released. `receipts`, when given, collects every receipt in order.
 */
export async function walkDailyChunks(game, signer, advanceModule, label,
  { maxCalls = 400, untilUnlocked = false, receipts = null } = {}) {
  const chunks = [];
  for (let i = 0; i < maxCalls; i++) {
    if (untilUnlocked && !(await game.rngLocked())) return chunks;
    const action = await game.nextMinerAction();
    if (action === MINER_IDLE || action === MINER_WAIT) return chunks;
    if (action === MINER_PUBLISH || action === MINER_TICKETS) {
      const { receipt } = await mine(game, signer, PRE_DAILY_ALLOWANCE);
      if (receipts) receipts.push(receipt);
      continue;
    }
    const { allowance, tx, receipt } = await measureNextChunk(game, signer, `${label} action=${action}`);
    if (receipts) receipts.push(receipt);
    chunks.push({ action, allowance, gasUsed: receipt.gasUsed, receipt, stages: await stagesOf(tx, advanceModule) });
  }
  expect.fail(`${label}: daily cohort did not settle within ${maxCalls} calls`);
}

/**
 * Settle the engine at realistic allowances: mine until Idle, fulfilling each fresh VRF
 * request (daily or mid-day) with a word derived from `word`. Returns every call.
 */
export async function settle(game, signer, mockVRF, advanceModule, word, maxCalls = 300) {
  const calls = [];
  for (let i = 0; i < maxCalls; i++) {
    const action = await game.nextMinerAction();
    if (action === MINER_IDLE) return calls;
    if (action === MINER_WAIT) {
      const id = await getLastVRFRequestId(mockVRF);
      const [, , done] = await mockVRF.pendingRequests(id);
      expect(done, "a waiting engine holds an unfulfilled request").to.equal(false);
      await mockVRF.fulfillRandomWords(id, BigInt(word) + id);
      continue;
    }
    const { tx, receipt } = await mine(game, signer);
    calls.push({ action, receipt, stages: await stagesOf(tx, advanceModule) });
  }
  expect.fail(`engine did not settle within ${maxCalls} calls`);
}

/**
 * From a settled or mid-day-waiting state on a fresh day: deliver outstanding mid-day
 * words, issue the daily request (under a realistic allowance, or chunk by chunk when
 * `measureRequest`), deliver `word`, then walk the daily cohort chunk by chunk. Returns
 * the walked chunks (request-side chunks first when measured).
 */
export async function walkNextDay(game, signer, mockVRF, advanceModule, word, label, { measureRequest = false } = {}) {
  const chunks = [];
  for (let i = 0; i < 100 && !(await game.rngLocked()); i++) {
    const action = await game.nextMinerAction();
    if (action === MINER_WAIT) {
      await mockVRF.fulfillRandomWords(await getLastVRFRequestId(mockVRF), BigInt(word) ^ 0x5eedn);
      continue;
    }
    expect(action, `${label}: the daily request is reachable`).to.not.equal(MINER_IDLE);
    if (!measureRequest) {
      await mine(game, signer);
      continue;
    }
    const { allowance, tx, receipt } = await measureNextChunk(game, signer, `${label} request action=${action}`);
    chunks.push({ action, allowance, gasUsed: receipt.gasUsed, receipt, stages: await stagesOf(tx, advanceModule) });
  }
  expect(await game.rngLocked(), `${label}: daily request engaged`).to.equal(true);
  await mockVRF.fulfillRandomWords(await getLastVRFRequestId(mockVRF), BigInt(word));
  return chunks.concat(await walkDailyChunks(game, signer, advanceModule, label));
}

/** Heaviest walked chunk per Advance stage. */
export function heaviestByStage(chunks, into = new Map()) {
  for (const c of chunks) {
    for (const st of c.stages) {
      const prev = into.get(st);
      if (!prev || c.gasUsed > prev.gasUsed) into.set(st, c);
    }
  }
  return into;
}
