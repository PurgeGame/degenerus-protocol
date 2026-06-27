// SPDX-License-Identifier: AGPL-3.0-only
//
// HeroOverrideWeightedRoll.test.js — Phase 293 v42.0 HRROLL regression fixture (TST-HRROLL-01..06).
//
// Audit subject: Phase 292 audit-subject commit `a0218952` — the v42 HRROLL
// cleanup that replaces the deterministic `_topHeroSymbol(uint32 day)` selector
// with `_rollHeroSymbol(uint32 day, uint256 entropy) private view returns
// (bool, uint8, uint8)` — a weighted random roll across the 32 `(quadrant,
// symbol)` slots in `dailyHeroWagers[day]` with a ×1.5 leader-weight bonus
// (D-42N-LEADER-BONUS-01) and no min-wager floor on any other slot
// (D-42N-FLOOR-01).
//
// Path of investigation (5 bullets per 293-CONTEXT.md `<decisions>`
// "JSDoc test-file header" anchor):
//
// (i)  Mechanic covered: the v42 HRROLL weighted-roll hero-override selector
//      at `contracts/modules/DegenerusGameJackpotModule.sol:1630-1700`,
//      consumed by `_applyHeroOverride` at the same file's L1600-L1628 with
//      the production callsite at L1988 from `_rollWinningTraits`.
//
// (ii) JS-replay oracle + cross-attestation strategy per D-293-INVOKE-01:
//      `_rollHeroSymbol` is `private view` so no inheritance-style harness can
//      reach it. The ALGORITHM_VERIFIED evidence class is established via a
//      pure-function JS bit-mirror at `test/helpers/rollHeroSymbolRef.mjs`
//      (Plan 01 deliverable). The oracle drives N=10000 iterations for the
//      chi² assertions (TST-HRROLL-01 + TST-HRROLL-02) and small-N samples
//      for the edge cases (TST-HRROLL-04 + TST-HRROLL-05). Cross-attestation
//      lives in a separate describe block: 16 production-path replays drive
//      `advanceGame()` through the natural jackpot resolution chain that
//      fires `DailyWinningTraits`; the event's `mainTraitsPacked` byte
//      decodes to the on-chain hero `(quadrant, symbol)` per
//      `_applyHeroOverride` L1623-L1627, asserted byte-equal to the JS oracle
//      output for the same `(dailyHeroWagers, randWord, day)` triple.
//
// (iii) D-293-GAS-01 RELAX posture (user disposition 2026-05-17,
//       resolving the original [BLOCKING_ESCALATION] checkpoint surfaced
//       at first execution): production-path delta measurement between (a)
//       worst-case-seeded `dailyHeroWagers[D]` (all 32 slots populated;
//       leader at flat idx 31 to maximise the pass-2 cursor walk +
//       leader-bonus add at the last cursor position) and (b) all-zero-
//       seeded baseline (HRROLL-01 early-bail at `total == 0` skips the
//       pass-2 cursor walk entirely) is log-only traceability — the
//       per-sample delta, mean, and stddev are captured and logged but
//       NOT asserted against any soft/hard window. Rationale: the
//       worst-case-seeded path triggers downstream JackpotFlipWin /
//       coin-jackpot cascades that fire differently from the all-zero-
//       seeded path (the trait-byte rewrite at `_applyHeroOverride`
//       L1623 affects bucket selection downstream); the observed delta
//       is dominated by those downstream cascades rather than the
//       `_rollHeroSymbol` body's ~+431 gas contribution. Theoretical
//       acceptance evidence remains the analytical anchor at
//       `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md`
//       §3.c (~+431 gas vs v41 `_topHeroSymbol` baseline; well within
//       the D-42N-GAS-01 soft +500 / hard +750 thresholds). Positive-path
//       coverage IS asserted: the test verifies `DailyWinningTraits`
//       fires under both worst-case-seeded and all-zero-seeded paths so
//       the production-path arrival at `_applyHeroOverride` is
//       structurally exercised. Mirrors the Phase 291 D-291-GAS-01
//       SKIP-GAS posture.
//
// (iv) D-293-STALE-VIEW-01 path-of-investigation note: the public view
//      `getDailyHeroWinner(uint32 day)` at `contracts/DegenerusGame.sol:2545`
//      carries a v41-leftover deterministic-leader body (most-wagered slot
//      wins, body unchanged from the deleted `_topHeroSymbol` algorithm).
//      Semantically misleading post-HRROLL since the actual mechanism is now
//      a weighted random roll requiring per-call entropy. NOT used as a
//      TST-HRROLL assertion vehicle (would return v41-deterministic output,
//      not weighted-roll output). Deferred to v43+ explicit cleanup phase
//      per `293-CONTEXT.md` `<deferred>` register.
//
// (v)  LOCKED TST-HRROLL-02 disposition (user 2026-05-17): seed
//      `[500, 200, 200, 100]` placed at flat idx 0..3 (quadrant 0, symbols
//      0..3). Algebra under the v42 mechanic: total = 500 + 200 + 200 + 100
//      = 1000; maxAmount = 500 (leader at flat idx 0 by strict-`>`
//      first-seen tie-break); leaderBonus = 500 / 2 = 250; effectiveTotal =
//      1000 + 250 = 1250; leader effective weight = 500 + 250 = 750;
//      expected leader pick-rate = 750 / 1250 = 0.60 exactly. The ROADMAP
//      success-criterion-2 example `(500 + 250) / 1250 = 60%` was paired
//      with seed `[500, 100, 100, 100]` which yields 750/1050 ≈ 71.4% under
//      the actual contract arithmetic — algebraically inconsistent with the
//      60% target. This fixture asserts the LOCKED seed `[500, 200, 200,
//      100]` which is uniquely-up-to-permutation the 4-slot vector
//      satisfying `(L + L/2) / (T + L/2) = 0.60` ⇒ `L = 0.5 × T` with `T =
//      1000`, `L = 500`. The path-of-investigation note here documents the
//      algebraic basis for the chosen seed per
//      `feedback_no_history_in_comments.md`; the asserting code describes
//      only the v42 mechanic.
//
// Per-test mapping (one line per TST-HRROLL-NN ⇒ describe block):
//   TST-HRROLL-01 — weighted-distribution chi² uniformity at N=10000 under
//     seed [400, 300, 200, 100]; df=3 crit=7.815; bonus-adjusted expected
//     rates [0.5, 0.25, 0.1667, 0.0833].
//   TST-HRROLL-02 — ×1.5 leader-bonus binomial sanity at N=10000 under
//     LOCKED seed [500, 200, 200, 100]; df=1 crit=3.841; expected leader
//     pick-rate exactly 0.60 = 750/1250.
//   TST-HRROLL-03 — RNG commitment-window proof: dailyHeroWagers[D][0..3]
//     slot bytes byte-identical across day-D→D+1 advance; JS oracle replay
//     produces identical (q, s) for both captures; D-288-FIX-SHAPE-01
//     dailyIdx single-writer invariant preserved.
//   TST-HRROLL-04 — single-bettor edge case: deterministic (q, s) return
//     with probability 1.0 across 100 entropy variations, at two distinct
//     flat-idx positions (idx 0 and idx 17).
//   TST-HRROLL-05 — zero-wager edge case: HRROLL-01 early-bail returns
//     (false, 0, 0) across 100 entropy variations.
//   TST-HRROLL-06 — production-path gas-delta log-only traceability
//     (RELAX posture); positive-path coverage via `DailyWinningTraits`
//     event-firing assertion under both worst-case-seeded and all-zero-
//     seeded paths; theoretical-attestation cite to
//     292-01-MEASUREMENT.md §3.c (D-291-GAS-01 SKIP-GAS posture mirror).

import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { execSync } from "node:child_process";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getLastVRFRequestId,
  fulfillVRF,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
import {
  rollHeroSymbolRef,
  packDailyHeroWagers,
  ROLL_HERO_SYMBOL_CONSTANTS,
} from "../helpers/rollHeroSymbolRef.mjs";

// -----------------------------------------------------------------------------
// Module-level constants
// -----------------------------------------------------------------------------

// Inline chi² critical-value table at α=0.05 — copied verbatim from
// test/stat/PerPullLevelDistribution.test.js L89-97 per 293-CONTEXT.md
// "Chi² implementation pattern" (no helper-file extraction for a single
// new consumer — deferred to a v43+ test-maintenance bundle).
const CHI2_CRIT_05 = Object.freeze({
  1: 3.841,
  2: 5.991,
  3: 7.815,
  4: 9.488,
  5: 11.070,
  6: 12.592,
  7: 14.067,
});

// Phase 282 / 291 invariant-continuity pin reused for cross-phase trace
// stability; chosen entropy value with no algebraic structure to seed deep
// keccak chains uniformly.
const DAILY_ENTROPY =
  0x2f02_3456_789a_bcde_f012_3456_789a_bcde_f012_3456_789a_bcde_f012_3456_789a_bcden;

const N_CHI2 = 10000;        // TST-HRROLL-01 + TST-HRROLL-02 iteration count
const N_EDGE = 100;          // TST-HRROLL-04 + TST-HRROLL-05 entropy-variation count
const N_GAS_SAMPLES = 5;     // TST-HRROLL-06 measurement repetitions for stddev
const N_CROSS = 16;          // small-N cross-attestation per D-293-INVOKE-01

// TST-HRROLL-01 chi² seed — 4 non-zero slots at quadrant 0, symbols 0..3.
// Bonus-adjusted expectation: leader at idx 0 effective weight 600
// (= 400 + 200 leaderBonus); effectiveTotal = 1000 + 200 = 1200; per-bucket
// rates [600/1200, 300/1200, 200/1200, 100/1200] = [0.5, 0.25, 0.1667, 0.0833].
const TST_HRROLL_01_SEED = Object.freeze([400, 300, 200, 100]);

// TST-HRROLL-02 LOCKED seed (user disposition 2026-05-17) — quadrant 0,
// symbols 0..3; total=1000, leaderBonus=250, effectiveTotal=1250, leader
// effective weight=750; expected leader pick-rate exactly 0.60 = 750/1250.
const TST_HRROLL_02_SEED = Object.freeze([500, 200, 200, 100]);
const TST_HRROLL_02_EXPECTED_LEADER_RATE = 750 / 1250; // 0.60 exactly

// D-42N-GAS-01 theoretical anchor (292-01-MEASUREMENT.md §3.c). RELAX
// disposition (user 2026-05-17): TST-HRROLL-06 is log-only traceability —
// production-path delta is captured + logged but NOT asserted on (downstream
// branch-cost cascade between worst-case-seeded vs all-zero-seeded paths
// dominates the ~+431 gas _rollHeroSymbol body contribution; the production
// granularity cannot isolate the body cost from those downstream cascades).
// The cited theoretical-attestation in 292-01-MEASUREMENT.md §3.c remains
// the load-bearing acceptance evidence for the gas regression. Mirrors the
// D-291-GAS-01 SKIP-GAS posture from Phase 291.
const GAS_DELTA_THEORETICAL = 431;

// Currency tag for ETH bets per DegenerusGameDegeneretteModule constants
// (CURRENCY_ETH = 0; see DegenerusGameDegeneretteModule.sol).
const CURRENCY_ETH = 0;

// MIN_BET_ETH at DegenerusGameDegeneretteModule.sol:217 — 5 ether / 1000 =
// 0.005 ETH. Bets at or above this value flow through the wager-tracking
// path that writes to dailyHeroWagers[dailyIdx][q].
const MIN_BET_ETH_VALUE = hre.ethers.parseEther("0.005");

// Slot 0 packs purchaseStartDay (bytes 0..3), dailyIdx (bytes 4..7),
// rngRequestTime (bytes 8..13), etc. — see DegenerusGameStorage.sol storage
// layout. dailyIdx is read as (word >> 32) & 0xFFFFFFFF where `word` is the
// big-endian uint256 storage word.
const SLOT0_TIMING_FSM = "0x" + (0).toString(16).padStart(64, "0");
const DAILY_IDX_BIT_SHIFT = 32n;
const UINT32_MASK = 0xffffffffn;

// Storage slot for lootboxRngPacked — gates placeDegeneretteBet at
// DegenerusGameDegeneretteModule.sol:451 (`if (index == 0) revert E()`).
const LOOTBOX_RNG_PACKED_SLOT =
  "0x" + (35).toString(16).padStart(64, "0");

// -----------------------------------------------------------------------------
// Module-level helpers
// -----------------------------------------------------------------------------

// Verbatim copy from test/stat/PerPullLevelDistribution.test.js L99-103.
// Wilson-Hilferty normal approximation of the chi² distribution; used for
// traceability logging — assertion uses the critical-value table directly.
function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

// Per-bucket chi² accumulation. observed[k] and expected[k] are bucket
// counts across the same length array; expected[k] must be non-zero for
// every k. Returns the chi² statistic as a Number.
function computeChi2Multinomial(observed, expected) {
  if (observed.length !== expected.length) {
    throw new Error(
      `computeChi2Multinomial: length mismatch observed=${observed.length} expected=${expected.length}`
    );
  }
  let chi2 = 0;
  for (let k = 0; k < observed.length; k++) {
    const e = expected[k];
    if (e === 0) {
      throw new Error(
        `computeChi2Multinomial: expected[${k}] is zero (chi² undefined)`
      );
    }
    const diff = observed[k] - e;
    chi2 += (diff * diff) / e;
  }
  return chi2;
}

// Runs `forge inspect` at test runtime and extracts the storage-layout slot
// index for `dailyHeroWagers`. Re-validates the Phase 292 §2 EMPTY-diff
// attestation against the v41 close pin (slot 53). Returns a BigInt.
function deriveDailyHeroWagersBaseSlot() {
  let forgeOut;
  try {
    forgeOut = execSync(
      "FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout 2>/dev/null"
    ).toString();
  } catch (err) {
    throw new Error(
      `deriveDailyHeroWagersBaseSlot: forge inspect failed — ${err.message}. Ensure foundry is installed and on PATH.`
    );
  }
  let slotIdx = null;
  for (const line of forgeOut.split("\n")) {
    if (!line.includes("dailyHeroWagers")) continue;
    const cells = line.split("|").map((c) => c.trim());
    for (let k = 0; k < cells.length; k++) {
      if (cells[k] === "dailyHeroWagers") {
        if (k + 2 < cells.length) {
          const candidate = cells[k + 2];
          if (/^[0-9]+$/.test(candidate)) {
            slotIdx = candidate;
          }
        }
        break;
      }
    }
    if (slotIdx) break;
  }
  if (slotIdx === null) {
    throw new Error(
      `deriveDailyHeroWagersBaseSlot: failed to parse slot index from forge output (looking for 'dailyHeroWagers' row). First 400 chars:\n${forgeOut.slice(
        0,
        400
      )}`
    );
  }
  const slot = BigInt(slotIdx);
  if (slot < 0n) {
    throw new Error(
      `deriveDailyHeroWagersBaseSlot: parsed slot=${slot} is negative`
    );
  }
  return slot;
}

// Solidity nested-mapping-with-fixed-array slot derivation:
//   `dailyHeroWagers` is `mapping(uint32 => uint256[4])` at base slot
//   `baseSlot`. For key `D`, the inner fixed array starts at
//   `parentSlot = keccak256(abi.encode(uint256(D), uint256(baseSlot)))`,
//   and element `q` lives contiguously at `parentSlot + q` (no further
//   keccak for fixed-length array elements).
function derivedailyHeroWagersSlot(D, q, baseSlot) {
  const parentSlot = BigInt(
    hre.ethers.keccak256(
      hre.ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "uint256"],
        [BigInt(D), baseSlot]
      )
    )
  );
  return (
    "0x" + (parentSlot + BigInt(q)).toString(16).padStart(64, "0")
  );
}

// Reads `dailyHeroWagers[D][0..3]` as `BigInt[4]` (matches the
// `rollHeroSymbolRef` input shape).
async function readDailyHeroWagersSlots(addr, D, baseSlot) {
  const out = [0n, 0n, 0n, 0n];
  for (let q = 0; q < 4; ++q) {
    const slot = derivedailyHeroWagersSlot(D, q, baseSlot);
    const raw = await hre.ethers.provider.getStorage(addr, slot);
    out[q] = BigInt(raw);
  }
  return out;
}

// Reads the `dailyIdx` uint32 directly from storage slot 0 of the game
// contract (internal — no public accessor; bytes [4:8] of slot 0 per
// DegenerusGameStorage.sol layout).
async function readDailyIdx(gameAddr) {
  const word = BigInt(
    await hre.ethers.provider.getStorage(gameAddr, SLOT0_TIMING_FSM)
  );
  return Number((word >> DAILY_IDX_BIT_SHIFT) & UINT32_MASK);
}

// Seed `lootboxRngPacked` low 48 bits to `index` so the bet gate at
// DegenerusGameDegeneretteModule.sol:451 (`if (index == 0) revert E()`)
// opens. The companion gate at L452 (`lootboxRngWordByIndex[index] != 0
// revert RngNotReady()`) passes by default — slot for index=1 is unset.
async function seedLootboxRngIndex(gameAddr, index = 1) {
  const provider = hre.ethers.provider;
  const current = BigInt(await provider.getStorage(gameAddr, LOOTBOX_RNG_PACKED_SLOT));
  const INDEX_MASK = (1n << 48n) - 1n;
  const cleared = current & ~INDEX_MASK;
  const updated = cleared | (BigInt(index) & INDEX_MASK);
  await hre.network.provider.send("hardhat_setStorageAt", [
    gameAddr,
    LOOTBOX_RNG_PACKED_SLOT,
    "0x" + updated.toString(16).padStart(64, "0"),
  ]);
}

// Pack the customTicket so the heroQuadrant's symbol byte decodes to
// `symbol` per `uint8(customTicket >> (heroQuadrant * 8)) & 7` (the
// extraction at DegenerusGameDegeneretteModule.sol:487-488).
function customTicketWithSymbol(quadrant, symbol) {
  return (symbol & 0x7) << (quadrant * 8);
}

// Place one ETH-currency degenerette bet for `signer` against the
// `(quadrant, symbol)` slot. Defaults to MIN_BET_ETH per spin, 1 spin total.
async function placeEthBet(game, signer, quadrant, symbol) {
  const customTicket = customTicketWithSymbol(quadrant, symbol);
  return game.connect(signer).placeDegeneretteBet(
    hre.ethers.ZeroAddress,
    CURRENCY_ETH,
    MIN_BET_ETH_VALUE,
    1,
    customTicket,
    quadrant,
    { value: MIN_BET_ETH_VALUE }
  );
}

// Phase 282 / 291 pattern: drive advanceGame() to issue a VRF request,
// then fulfill with the pinned word. Subsequent jackpot-resolution calls
// inside the advanceGame chain consume rngWordByDay[day] = word.
async function pinDailyEntropy(game, deployer, mockVRF, word) {
  await advanceToNextDay();
  await game.connect(deployer).advanceGame();
  const requestId = await getLastVRFRequestId(mockVRF);
  try {
    await mockVRF.fulfillRandomWords(requestId, word);
  } catch {
    // Tolerate race where advanceGame already fulfilled in-line.
  }
}

// Decode one trait byte at `mainTraitsPacked[heroQuadrant]` per
// _applyHeroOverride L1623-1627: trait byte = (quadrant << 6) | (color << 3)
// | symbol. The hero override writes the SAME byte to all 4 quadrant slots
// (per L1623), so byte 0 suffices for cross-attestation — but reading
// `heroQuadrant`'s own byte index is equivalent and self-documenting.
function unpackHeroFromTraitsPacked(mainTraitsPacked, heroQuadrant) {
  const byte = Number(
    (BigInt(mainTraitsPacked) >> BigInt(heroQuadrant * 8)) & 0xffn
  );
  return {
    quadrant: (byte >> 6) & 3,
    color: (byte >> 3) & 7,
    symbol: byte & 7,
  };
}

// Synthetic state seeding for the chi² and gas-regression fixtures. Packs
// the 32-length raw uint32 amounts via `packDailyHeroWagers` (Plan 01),
// then writes the 4 packed values directly into slot[D][0..3] via
// hardhat_setStorageAt. The chi² fixtures (TST-HRROLL-01 + 02) and the
// worst-case-seeded gas-regression baseline (TST-HRROLL-06) use this path;
// TST-HRROLL-03 uses the production path (placeDegeneretteBet) instead.
async function seedDailyHeroWagersDirect(addr, D, baseSlot, rawAmounts) {
  const packed = packDailyHeroWagers(rawAmounts);
  for (let q = 0; q < 4; ++q) {
    const slot = derivedailyHeroWagersSlot(D, q, baseSlot);
    const valueHex =
      "0x" + packed[q].toString(16).padStart(64, "0");
    await hre.network.provider.send("hardhat_setStorageAt", [
      addr,
      slot,
      valueHex,
    ]);
  }
}

// -----------------------------------------------------------------------------
// Top-level describe block
// -----------------------------------------------------------------------------

describe("HeroOverrideWeightedRoll — Phase 293 v42.0 HRROLL regression fixture", function () {
  this.timeout(900_000);

  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // Setup + sanity — JS-replay oracle wiring + forge-inspect storage-layout
  // baseSlot derivation. Anchor block that exercises the helper imports +
  // the storage-layout EMPTY-diff re-validation before any TST-HRROLL-NN
  // assertion fires.
  // ---------------------------------------------------------------------------
  describe("TST-HRROLL setup-and-sanity — JS-replay oracle wiring + forge-inspect storage-layout baseSlot derivation", function () {
    it("derives dailyHeroWagers base slot from forge inspect storageLayout and asserts the slot index is a non-negative BigInt", function () {
      const baseSlot = deriveDailyHeroWagersBaseSlot();
      expect(typeof baseSlot).to.equal("bigint");
      expect(baseSlot >= 0n).to.equal(true);
      console.log(
        `      [TST-HRROLL setup] dailyHeroWagers BASE_SLOT = ${baseSlot.toString()}`
      );
    });

    it("the JS-replay oracle returns (false, 0, 0) on a zero-wager input (HRROLL-01 early-bail)", function () {
      const out = rollHeroSymbolRef({
        day: 1,
        entropy: 0n,
        dailyHeroWagers: [0n, 0n, 0n, 0n],
      });
      expect(out.hasWinner).to.equal(false);
      expect(out.winQuadrant).to.equal(0);
      expect(out.winSymbol).to.equal(0);
    });

    it("packDailyHeroWagers round-trips a single-bettor raw-amount array into a 4-element BigInt array with the expected slot byte layout", function () {
      const raw = new Array(32).fill(0);
      raw[0] = 1000;
      const packed = packDailyHeroWagers(raw);
      expect(packed.length).to.equal(4);
      expect(Number(packed[0] & ROLL_HERO_SYMBOL_CONSTANTS.U32_MASK)).to.equal(
        1000
      );
      for (let q = 1; q < 4; ++q) {
        expect(packed[q]).to.equal(0n);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // TST-HRROLL-01 — weighted-distribution chi² uniformity at N=10000
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-01 — weighted-distribution chi² uniformity at N=" +
      N_CHI2 +
      " under seed " +
      JSON.stringify(TST_HRROLL_01_SEED) +
      " (df=3, crit=" +
      CHI2_CRIT_05[3] +
      ")",
    function () {
      it(
        "chi² statistic over " +
          N_CHI2 +
          " JS-oracle iterations is < " +
          CHI2_CRIT_05[3] +
          " against bonus-adjusted expected rates",
        function () {
          // Place the seed at quadrant 0, symbols 0..3. The leader is at flat
          // idx 0 (strict-> first-seen tie-break), so the leaderBonus add
          // applies at idx 0 in the cursor walk.
          const raw = new Array(32).fill(0);
          raw[0] = TST_HRROLL_01_SEED[0]; // 400
          raw[1] = TST_HRROLL_01_SEED[1]; // 300
          raw[2] = TST_HRROLL_01_SEED[2]; // 200
          raw[3] = TST_HRROLL_01_SEED[3]; // 100

          // Bonus-adjusted expectation (v42 mechanic):
          //   total = 400 + 300 + 200 + 100 = 1000
          //   maxAmount = 400; leaderBonus = 400 / 2 = 200
          //   effectiveTotal = 1000 + 200 = 1200
          //   per-bucket effective weights: [400+200, 300, 200, 100] = [600, 300, 200, 100]
          //   expected pick rates: [600/1200, 300/1200, 200/1200, 100/1200]
          //                      = [0.5, 0.25, 0.1667, 0.0833]
          const total = 1000;
          const maxAmount = TST_HRROLL_01_SEED[0];
          const leaderBonus = maxAmount / 2; // 200
          const effectiveTotal = total + leaderBonus; // 1200

          expect(total).to.equal(
            TST_HRROLL_01_SEED.reduce((a, b) => a + b, 0)
          );
          expect(maxAmount).to.equal(Math.max(...TST_HRROLL_01_SEED));
          expect(effectiveTotal).to.equal(1200);

          const packed = packDailyHeroWagers(raw);
          const day = 1;

          // observed[k] = bucket counts for flat idx 0..3 only (the seeded
          // slots). The 28 zero-amount buckets MUST have count 0 — enforced
          // by the per-iteration throw on flatIdx >= 4 below.
          const observed = [0, 0, 0, 0];

          for (let i = 0; i < N_CHI2; ++i) {
            // Deterministic-but-distinct entropy across iterations. Spread
            // the iteration counter `i` across 4 disjoint 64-bit lanes of
            // the uint256 input so the keccak-hashed pick varies maximally.
            const entropy =
              (BigInt(i) << 192n) |
              (BigInt(i + 1) << 128n) |
              (BigInt(i + 2) << 64n) |
              BigInt(i + 3);
            const out = rollHeroSymbolRef({
              day,
              entropy,
              dailyHeroWagers: packed,
            });
            if (!out.hasWinner) {
              throw new Error(
                "TST-HRROLL-01: hasWinner=false at i=" + i + " on non-zero seed"
              );
            }
            const flatIdx = (out.winQuadrant << 3) | out.winSymbol;
            if (flatIdx >= 4) {
              throw new Error(
                "TST-HRROLL-01: oracle returned non-seeded slot at i=" +
                  i +
                  " flatIdx=" +
                  flatIdx +
                  " (q=" +
                  out.winQuadrant +
                  ", s=" +
                  out.winSymbol +
                  ")"
              );
            }
            observed[flatIdx]++;
          }

          // Total-count invariant: every iteration produced exactly one hit.
          expect(observed.reduce((a, b) => a + b, 0)).to.equal(
            N_CHI2,
            `observed counts must sum to N_CHI2=${N_CHI2}`
          );

          // Bonus-adjusted expectation (NOT raw-weight expectation):
          const expected = [
            N_CHI2 * (600 / effectiveTotal), // 5000
            N_CHI2 * (300 / effectiveTotal), // 2500
            N_CHI2 * (200 / effectiveTotal), // 1666.67
            N_CHI2 * (100 / effectiveTotal), // 833.33
          ];

          const chi2 = computeChi2Multinomial(observed, expected);
          const crit = CHI2_CRIT_05[3]; // 7.815, df = 4 buckets - 1

          const observedStr = observed.join(",");
          const expectedStr = expected.map((e) => e.toFixed(1)).join(",");
          const z = wilsonHilfertyZ(chi2, 3);

          console.log(
            `      [TST-HRROLL-01] chi² = ${chi2.toFixed(3)} < ${crit} (df=3); observed=[${observedStr}]; expected=[${expectedStr}]; N=${N_CHI2}; Wilson-Hilferty Z=${z.toFixed(3)}`
          );

          expect(
            chi2,
            `chi² = ${chi2.toFixed(3)} >= ${crit} (df=3); observed=[${observedStr}], expected=[${expectedStr}]`
          ).to.be.lt(crit);
        }
      );
    }
  );

  // ---------------------------------------------------------------------------
  // TST-HRROLL-02 — ×1.5 leader-bonus binomial at N=10000 under LOCKED seed
  // [500, 200, 200, 100]; expected leader pick-rate exactly 0.60 = 750/1250.
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-02 — ×1.5 leader-bonus binomial sanity at N=" +
      N_CHI2 +
      " under LOCKED seed " +
      JSON.stringify(TST_HRROLL_02_SEED) +
      " (df=1, crit=" +
      CHI2_CRIT_05[1] +
      ")",
    function () {
      it(
        "leader pick-rate matches expected 0.60 = 750/1250 (= (maxAmount + leaderBonus) / effectiveTotal) within chi² df=1 tolerance",
        function () {
          // LOCKED seed at quadrant 0, symbols 0..3; leader at flat idx 0 by
          // strict-> first-seen tie-break.
          //
          // v42 mechanic (D-42N-LEADER-BONUS-01):
          //   total           = 500 + 200 + 200 + 100 = 1000
          //   maxAmount       = 500 (leader at flat idx 0; strict-> first-seen)
          //   leaderBonus     = maxAmount / 2 = 250
          //   effectiveTotal  = total + leaderBonus = 1250
          //   leader weight   = maxAmount + leaderBonus = 750
          //   pick-rate(leader) = 750 / 1250 = 0.60 exactly
          //
          // LOCKED disposition note (path-of-investigation): the seed
          // [500, 200, 200, 100] is uniquely-up-to-permutation the 4-slot
          // vector satisfying L = 0.5 * T which is the algebraic constraint
          // for `(L + L/2) / (T + L/2) = 0.60` under
          // D-42N-LEADER-BONUS-01 with T = 1000, L = 500. The ROADMAP
          // success-criterion-2 example `(500 + 250) / 1250 = 60%` paired
          // with seed `[500, 100, 100, 100]` yields 750/1050 ≈ 71.4% under
          // the actual contract arithmetic — algebraically inconsistent.
          // User locked the [500, 200, 200, 100] seed on 2026-05-17.

          const raw = new Array(32).fill(0);
          raw[0] = TST_HRROLL_02_SEED[0]; // 500
          raw[1] = TST_HRROLL_02_SEED[1]; // 200
          raw[2] = TST_HRROLL_02_SEED[2]; // 200
          raw[3] = TST_HRROLL_02_SEED[3]; // 100

          // Lock-in the algebra at runtime so a stray edit fails loudly.
          expect(
            TST_HRROLL_02_SEED.reduce((a, b) => a + b, 0),
            "TST_HRROLL_02_SEED total must equal 1000 (LOCKED disposition)"
          ).to.equal(1000);
          expect(
            Math.max(...TST_HRROLL_02_SEED),
            "TST_HRROLL_02_SEED leader must equal 500 (LOCKED disposition)"
          ).to.equal(500);
          expect(
            TST_HRROLL_02_EXPECTED_LEADER_RATE,
            "TST_HRROLL_02_EXPECTED_LEADER_RATE must equal 0.60 = 750/1250"
          ).to.equal(0.6);

          const packed = packDailyHeroWagers(raw);
          const day = 2; // distinct from TST-HRROLL-01 day=1 for trace clarity

          let leaderHits = 0;
          let otherHits = 0;

          for (let i = 0; i < N_CHI2; ++i) {
            // Offset the entropy construction by 0xDEADBEEF to make the
            // distribution independent of the TST-HRROLL-01 sample stream.
            const entropy =
              ((BigInt(i) + 0xDEADBEEFn) << 192n) |
              (BigInt(i + 1) << 128n) |
              (BigInt(i + 2) << 64n) |
              BigInt(i + 3);
            const out = rollHeroSymbolRef({
              day,
              entropy,
              dailyHeroWagers: packed,
            });
            if (!out.hasWinner) {
              throw new Error(
                "TST-HRROLL-02: hasWinner=false at i=" + i + " on non-zero LOCKED seed"
              );
            }
            const flatIdx = (out.winQuadrant << 3) | out.winSymbol;
            if (flatIdx >= 4) {
              throw new Error(
                "TST-HRROLL-02: oracle returned non-seeded slot at i=" +
                  i +
                  " flatIdx=" +
                  flatIdx
              );
            }
            if (flatIdx === 0) {
              leaderHits++;
            } else {
              otherHits++;
            }
          }

          expect(leaderHits + otherHits).to.equal(
            N_CHI2,
            "leaderHits + otherHits must equal N_CHI2"
          );

          const empiricalLeaderRate = leaderHits / N_CHI2;

          // Binomial chi² (collapsed to "leader vs others", df=1).
          const expectedLeader = N_CHI2 * TST_HRROLL_02_EXPECTED_LEADER_RATE; // 6000
          const expectedOther =
            N_CHI2 * (1 - TST_HRROLL_02_EXPECTED_LEADER_RATE); // 4000

          const chi2 = computeChi2Multinomial(
            [leaderHits, otherHits],
            [expectedLeader, expectedOther]
          );
          const crit = CHI2_CRIT_05[1]; // 3.841

          const z = wilsonHilfertyZ(chi2, 1);
          console.log(
            `      [TST-HRROLL-02] empirical leader pick-rate = ${empiricalLeaderRate.toFixed(
              4
            )} (target = ${TST_HRROLL_02_EXPECTED_LEADER_RATE} = 750/1250); leaderHits=${leaderHits}, otherHits=${otherHits}, N=${N_CHI2}`
          );
          console.log(
            `      [TST-HRROLL-02] chi² = ${chi2.toFixed(3)} < ${crit} (df=1, binomial); Wilson-Hilferty Z=${z.toFixed(3)}`
          );

          expect(
            chi2,
            `chi² = ${chi2.toFixed(3)} >= ${crit} (df=1); leaderHits=${leaderHits}, otherHits=${otherHits}`
          ).to.be.lt(crit);
        }
      );
    }
  );

  // ---------------------------------------------------------------------------
  // TST-HRROLL-03 — RNG commitment-window proof: dailyHeroWagers[D][q] slot
  // bytes byte-identical across day-D→D+1 advance; JS oracle replay produces
  // identical (q, s) for both captures. D-288-FIX-SHAPE-01 dailyIdx
  // single-writer invariant preserved.
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-03 — RNG commitment-window proof: dailyHeroWagers[D][q] frozen across day-D→D+1 advance",
    function () {
      it(
        "captures dailyHeroWagers[D][0..3] slot bytes pre-advance, advances day, asserts post-advance bytes are byte-identical, and the JS-oracle reproduces the same (q, s) for both captures",
        async function () {
          const fixture = await loadFixture(deployFullProtocol);
          const { game, alice } = fixture;
          const gameAddr = await game.getAddress();
          await seedLootboxRngIndex(gameAddr, 1);

          const baseSlot = deriveDailyHeroWagersBaseSlot();

          // Day D — read dailyIdx from slot 0 byte offset [4:8] per the v41
          // Phase 288 D-288-FIX-SHAPE-01 layout. (`dailyIdx` is internal; no
          // public accessor.)
          const dayD = await readDailyIdx(gameAddr);
          expect(dayD, "dailyIdx must be a non-negative uint32 at fixture boot").to.be.gte(0);

          // Place at least 2 hero wagers via the production path
          // (placeDegeneretteBet). Bets land at
          // dailyHeroWagers[_simulatedDayIndex()][heroQuadrant] per L486-L499
          // of DegenerusGameDegeneretteModule.sol. At fixture boot
          // _simulatedDayIndex() == dailyIdx, so the bets land at slot[D]
          // which is exactly the slot the operational read at L1609
          // (`_rollHeroSymbol(dailyIdx, ...)`) targets.
          await placeEthBet(game, alice, 0, 3); // quadrant 0, symbol 3
          await placeEthBet(game, alice, 2, 5); // quadrant 2, symbol 5

          // Pre-advance storage capture.
          const slotsBeforeAdvance = await readDailyHeroWagersSlots(
            gameAddr,
            dayD,
            baseSlot
          );

          // Sanity: at least one non-zero slot proves the bets landed at the
          // slots being read.
          const anyNonZero = slotsBeforeAdvance.some((s) => s !== 0n);
          expect(
            anyNonZero,
            `at least one of dailyHeroWagers[${dayD}][0..3] must be non-zero after bet placement; got [${slotsBeforeAdvance
              .map((s) => "0x" + s.toString(16))
              .join(", ")}]`
          ).to.equal(true);

          // JS-oracle output under fixed entropy (locks the pre-advance
          // (q, s) reference).
          const refEntropy = DAILY_ENTROPY;
          const refOut = rollHeroSymbolRef({
            day: dayD,
            entropy: refEntropy,
            dailyHeroWagers: slotsBeforeAdvance,
          });

          // Advance day-D → D+1 via the wall-clock warp. The fixture uses
          // the storage-layout proof technique (per the
          // HeroOverrideDayIndex.test.js sister-fixture path-of-investigation
          // note): the test asserts on slot byte-identity under the natural
          // day-warp, which is the same invariant the production
          // `_unlockRng` write would otherwise preserve. `dailyIdx` remains
          // frozen across `advanceToNextDay()` (no `_unlockRng` fires in
          // this minimal fixture path; the slot read at the post-advance
          // step is what TST-HRROLL-03 is structurally about).
          await advanceToNextDay();
          const wallDayAfter = Number(await game.currentDayView());
          expect(
            wallDayAfter,
            `wall-clock day must advance from D=${dayD} to D+1=${dayD + 1}`
          ).to.equal(dayD + 1);

          // Post-advance storage capture.
          const slotsAfterAdvance = await readDailyHeroWagersSlots(
            gameAddr,
            dayD,
            baseSlot
          );

          // Byte-identity assertion across all 4 quadrants of slot[D].
          for (let q = 0; q < 4; ++q) {
            expect(
              slotsAfterAdvance[q],
              `dailyHeroWagers[${dayD}][${q}] mutated across day advance (pre=0x${slotsBeforeAdvance[
                q
              ].toString(16)} post=0x${slotsAfterAdvance[q].toString(16)})`
            ).to.equal(slotsBeforeAdvance[q]);
          }

          // JS-oracle replay against post-advance bytes — must produce the
          // exact same (q, s) outcome under the fixed entropy.
          const replayOut = rollHeroSymbolRef({
            day: dayD,
            entropy: refEntropy,
            dailyHeroWagers: slotsAfterAdvance,
          });
          expect(replayOut.hasWinner).to.equal(refOut.hasWinner);
          expect(replayOut.winQuadrant).to.equal(refOut.winQuadrant);
          expect(replayOut.winSymbol).to.equal(refOut.winSymbol);

          // D-288-FIX-SHAPE-01 single-writer invariant: dailyIdx is written
          // only by `_unlockRng` (AdvanceModule). `advanceToNextDay()` warps
          // wall-clock without firing `_unlockRng`, so `dailyIdx` remains
          // frozen at its fixture-init value. This is the same structural
          // anchor TST-HOFIX-01 documents in HeroOverrideDayIndex.test.js
          // under the v41 Phase 288 closure.
          const dailyIdxAfter = await readDailyIdx(gameAddr);
          expect(
            dailyIdxAfter,
            `dailyIdx must remain at D=${dayD} after wall-clock warp (no _unlockRng fired; D-288-FIX-SHAPE-01 single-writer invariant)`
          ).to.equal(dayD);

          console.log(
            `      [TST-HRROLL-03] dayD=${dayD}; slots=[${slotsBeforeAdvance
              .map((s) => "0x" + s.toString(16))
              .join(", ")}]; oracle output={hasWinner:${refOut.hasWinner}, q:${refOut.winQuadrant}, s:${refOut.winSymbol}}; dailyIdx invariant: dailyIdx==D frozen across wall-clock advance (D-288-FIX-SHAPE-01 single-writer)`
          );
        }
      );
    }
  );

  // ---------------------------------------------------------------------------
  // TST-HRROLL-04 — single-bettor edge case: deterministic (q, s) return
  // with probability 1.0 across N_EDGE entropy variations. Exercises 2
  // distinct leader-idx positions (flat idx 0 and flat idx 17 — quadrant 2,
  // symbol 1) to cover both early-cursor-position and mid-cursor-position
  // leader-bonus add at pass-2.
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-04 — single-bettor edge case: deterministic (q, s) return with probability 1.0 across " +
      N_EDGE +
      " entropy variations",
    function () {
      it(
        "seed[flatIdx=0] = 1000; assert rollHeroSymbolRef returns (true, 0, 0) for all " +
          N_EDGE +
          " distinct entropy values",
        function () {
          const raw = new Array(32).fill(0);
          raw[0] = 1000;
          const packed = packDailyHeroWagers(raw);
          const day = 3;

          for (let i = 0; i < N_EDGE; ++i) {
            const entropy =
              (BigInt(i) << 200n) ^
              (BigInt(i * 0x12345678) << 64n) ^
              BigInt(i + 0xcafebabe);
            const out = rollHeroSymbolRef({
              day,
              entropy,
              dailyHeroWagers: packed,
            });
            expect(out.hasWinner, "i=" + i + " hasWinner should be true").to.equal(
              true
            );
            expect(
              out.winQuadrant,
              "i=" + i + " winQuadrant should be 0"
            ).to.equal(0);
            expect(
              out.winSymbol,
              "i=" + i + " winSymbol should be 0"
            ).to.equal(0);
          }

          console.log(
            "      [TST-HRROLL-04 idx=0] single-bettor probability 1.0 confirmed across " +
              N_EDGE +
              " distinct entropy values (HRROLL-03 single-bettor disposition; leader at flat idx 0)"
          );
        }
      );

      it(
        "seed[flatIdx=17] = 1000 (quadrant 2, symbol 1); assert rollHeroSymbolRef returns (true, 2, 1) for all " +
          N_EDGE +
          " distinct entropy values (mid-cursor leader-idx coverage)",
        function () {
          const raw = new Array(32).fill(0);
          raw[17] = 1000; // flat idx 17 = (q=2, s=1)
          const packed = packDailyHeroWagers(raw);
          const day = 3;

          for (let i = 0; i < N_EDGE; ++i) {
            const entropy =
              (BigInt(i) << 208n) ^
              (BigInt(i * 0x9abcdef0) << 96n) ^
              BigInt(i + 0xfeedface);
            const out = rollHeroSymbolRef({
              day,
              entropy,
              dailyHeroWagers: packed,
            });
            expect(out.hasWinner, "i=" + i + " hasWinner should be true").to.equal(
              true
            );
            expect(
              out.winQuadrant,
              "i=" + i + " winQuadrant should be 2"
            ).to.equal(2);
            expect(
              out.winSymbol,
              "i=" + i + " winSymbol should be 1"
            ).to.equal(1);
          }

          console.log(
            "      [TST-HRROLL-04 idx=17] single-bettor probability 1.0 confirmed across " +
              N_EDGE +
              " distinct entropy values (leader at flat idx 17 = q=2 s=1; mid-cursor leader-bonus add)"
          );
        }
      );
    }
  );

  // ---------------------------------------------------------------------------
  // TST-HRROLL-05 — zero-wager edge case: HRROLL-01 early-bail returns
  // (false, 0, 0) across N_EDGE entropy variations. Exercises the
  // `total == 0` branch at _rollHeroSymbol L1677-1679.
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-05 — zero-wager edge case: HRROLL-01 early-bail returns (false, 0, 0) across " +
      N_EDGE +
      " entropy variations",
    function () {
      it(
        "all-zero dailyHeroWagers slots; assert rollHeroSymbolRef returns (false, 0, 0) for all " +
          N_EDGE +
          " distinct entropy values",
        function () {
          const packed = [0n, 0n, 0n, 0n];
          const day = 4;

          for (let i = 0; i < N_EDGE; ++i) {
            const entropy =
              (BigInt(i) << 200n) ^
              (BigInt(i * 0x87654321) << 64n) ^
              BigInt(i + 0xdeadbeef);
            const out = rollHeroSymbolRef({
              day,
              entropy,
              dailyHeroWagers: packed,
            });
            expect(
              out.hasWinner,
              "i=" + i + " hasWinner should be false (early-bail at total == 0)"
            ).to.equal(false);
            expect(
              out.winQuadrant,
              "i=" + i + " winQuadrant should be 0"
            ).to.equal(0);
            expect(
              out.winSymbol,
              "i=" + i + " winSymbol should be 0"
            ).to.equal(0);
          }

          console.log(
            "      [TST-HRROLL-05] zero-wager (false, 0, 0) confirmed across " +
              N_EDGE +
              " distinct entropy values (HRROLL-01 early-bail at total == 0)"
          );
        }
      );
    }
  );

  // ---------------------------------------------------------------------------
  // TST-HRROLL-06 — production-path gas regression (RELAXED — log-only
  // traceability; theoretical-attestation cite 292-01-MEASUREMENT.md §3.c).
  //
  // RELAX disposition (user 2026-05-17, resolving the first-execution
  // [BLOCKING_ESCALATION] checkpoint): the production-path delta between
  // worst-case-seeded `dailyHeroWagers[D]` (all 32 slots populated; leader
  // at flat idx 31) and all-zero-seeded baseline (HRROLL-01 early-bail at
  // total == 0) is captured + logged for traceability but NOT asserted
  // against any soft/hard window. The production path
  //   `advanceGame()` → state machine → _emitDailyWinningTraits →
  //   _rollWinningTraits → _applyHeroOverride → _rollHeroSymbol
  // triggers downstream JackpotFlipWin / coin-jackpot cascades that fire
  // differently between the two seeded states (the trait-byte rewrite at
  // _applyHeroOverride L1623 affects bucket selection downstream); the
  // observed delta is dominated by those downstream cascades rather than
  // the _rollHeroSymbol body's ~+431 gas contribution. Production-path
  // granularity cannot isolate the body cost from these downstream
  // cascades, so a strict assertion against the +431 ± 100 soft / ≤ 750
  // hard window is not a sound signal.
  //
  // Theoretical acceptance evidence remains the analytical anchor at
  //   `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md`
  //   §3.c (~+431 gas vs v41 `_topHeroSymbol` baseline; well within the
  //   D-42N-GAS-01 soft +500 / hard +750 thresholds).
  //
  // Positive-path coverage IS asserted: the test verifies that
  // `DailyWinningTraits` fires under both worst-case-seeded AND
  // all-zero-seeded paths so the production-path arrival at
  // _applyHeroOverride is structurally exercised. Mirrors the Phase 291
  // D-291-GAS-01 SKIP-GAS posture.
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-06 — production-path gas regression (RELAXED — log-only traceability; theoretical-attestation cite 292-01-MEASUREMENT.md §3.c)",
    function () {
      it(
        "DailyWinningTraits event fires under both worst-case-seeded and all-zero-seeded advanceGame jackpot-resolution paths across " +
          N_GAS_SAMPLES +
          " measurements; per-sample gas-delta logged for traceability against the +" +
          GAS_DELTA_THEORETICAL +
          " gas theoretical anchor (292-01-MEASUREMENT.md §3.c)",
        async function () {
          this.timeout(600_000); // 5 fresh fixtures × 2 paths each = 10 deploys

          // Resolve the JackpotModule interface ONCE for DailyWinningTraits
          // event parsing (the event is declared on the JackpotModule but
          // emitted via delegatecall from the GAME contract, so the event
          // ABI lives on the JackpotModule interface).
          const jackpotIface = (
            await hre.ethers.getContractAt(
              "DegenerusGameJackpotModule",
              hre.ethers.ZeroAddress // any address; we only need the ABI
            )
          ).interface;

          // Run one gas-measurement sample:
          //   1. Deploy fresh fixture (per-sample to avoid contamination).
          //   2. Purchase tickets so the state machine has work to drain.
          //   3. Day-warp + advanceGame to issue VRF request; fulfillRandomWords.
          //   4. Drain queue via repeated advanceGame() until DailyWinningTraits
          //      fires — that's the tx whose gasUsed we capture and whose
          //      fired-event we treat as positive-path proof.
          //   5. (Optional) seed dailyHeroWagers[dailyIdx] with raw32 RIGHT
          //      BEFORE the final advance so _rollHeroSymbol reads the
          //      seeded state. dailyIdx is the dailyHeroWagers key that
          //      _applyHeroOverride passes to _rollHeroSymbol per L1609.
          //
          // Returns { gasUsed, dailyWinningTraitsFired } — gasUsed is null
          // and dailyWinningTraitsFired is false when the state machine
          // never reaches _emitDailyWinningTraits within the drain budget.
          async function measureAdvanceGameGas(raw32OrNull) {
            const fixture = await loadFixture(deployFullProtocol);
            const { game, deployer, mockVRF, alice } = fixture;
            const gameAddr = await game.getAddress();
            const baseSlot = deriveDailyHeroWagersBaseSlot();

            // Purchase enough tickets to ensure the drain chain enters the
            // purchaseLevel==1 / ticketsFullyProcessed branch that triggers
            // _emitDailyWinningTraits. 200 tickets is sufficient per the
            // debug trace; matches the Phase 282 / 291 fixture-volume
            // baseline scaled down for gas-measurement determinism.
            await game.connect(alice).purchase(
              hre.ethers.ZeroAddress,
              200n,
              0n,
              ZERO_BYTES32,
              0, // MintPaymentKind.DirectEth
              false, // foil
              { value: hre.ethers.parseEther("2") }
            );

            // Day-warp + advanceGame to issue VRF request, then fulfill
            // with DAILY_ENTROPY. The fulfilled rngWordByDay[D] is consumed
            // by subsequent advanceGame() calls in the drain chain.
            await pinDailyEntropy(game, deployer, mockVRF, DAILY_ENTROPY);

            // Drain via repeated advanceGame() until DailyWinningTraits
            // fires. Cap the drain at 30 iterations to prevent infinite
            // loops if the state machine gets stuck.
            const MAX_DRAIN_ITERS = 30;
            let finalReceipt = null;
            for (let iter = 0; iter < MAX_DRAIN_ITERS; ++iter) {
              // Seed dailyHeroWagers[dailyIdx][q] RIGHT BEFORE each
              // advanceGame call so that whichever call triggers
              // _emitDailyWinningTraits reads the seeded state. The seed is
              // re-applied per iteration because intervening _unlockRng
              // writes to dailyIdx could shift the slot index.
              if (raw32OrNull !== null) {
                const curDailyIdx = await readDailyIdx(gameAddr);
                await seedDailyHeroWagersDirect(
                  gameAddr,
                  curDailyIdx,
                  baseSlot,
                  raw32OrNull
                );
              }

              let tx;
              try {
                tx = await game.connect(deployer).advanceGame();
              } catch {
                // Drain ended (NotTimeYet, etc.).
                break;
              }
              const receipt = await tx.wait();

              // Check if DailyWinningTraits fired in this tx.
              let dailyWinningTraitsFired = false;
              for (const log of receipt.logs) {
                try {
                  const parsed = jackpotIface.parseLog(log);
                  if (parsed && parsed.name === "DailyWinningTraits") {
                    dailyWinningTraitsFired = true;
                    break;
                  }
                } catch {
                  /* not from jackpot interface; skip */
                }
              }
              if (dailyWinningTraitsFired) {
                finalReceipt = receipt;
                break;
              }
            }

            if (finalReceipt === null) {
              return { gasUsed: null, dailyWinningTraitsFired: false };
            }
            return {
              gasUsed: Number(finalReceipt.gasUsed),
              dailyWinningTraitsFired: true,
            };
          }

          // Worst-case raw amounts: all 32 slots populated; leader at flat
          // idx 31 (quadrant 3, symbol 7). The leader-bonus add lands at
          // the last cursor position, forcing the pass-2 walk to run the
          // full 32-step cumulative loop before returning.
          const worstRaw = new Array(32);
          for (let i = 0; i < 31; ++i) worstRaw[i] = 100 + i;
          worstRaw[31] = 10000; // leader at flat idx 31

          const samples = [];
          let invalidSamples = 0;
          let totalAttempts = 0;
          const MAX_ATTEMPTS = N_GAS_SAMPLES * 3; // tolerate up to 2× retry budget

          while (samples.length < N_GAS_SAMPLES && totalAttempts < MAX_ATTEMPTS) {
            ++totalAttempts;
            const worstResult = await measureAdvanceGameGas(worstRaw);
            const baselineResult = await measureAdvanceGameGas(null); // all-zero seeded

            // Positive-path coverage assertion: BOTH paths must fire
            // DailyWinningTraits. The RELAX posture drops the soft/hard
            // window assertion on the delta, but the event-firing check
            // remains the load-bearing structural assertion that the
            // production path reaches _applyHeroOverride → _rollHeroSymbol.
            expect(
              worstResult.dailyWinningTraitsFired,
              `worst-case-seeded path did not emit DailyWinningTraits (sample attempt ${totalAttempts}); advanceGame drain never reached _emitDailyWinningTraits`
            ).to.equal(true);
            expect(
              baselineResult.dailyWinningTraitsFired,
              `all-zero-seeded baseline path did not emit DailyWinningTraits (sample attempt ${totalAttempts}); advanceGame drain never reached _emitDailyWinningTraits`
            ).to.equal(true);

            if (worstResult.gasUsed === null || baselineResult.gasUsed === null) {
              // Defensive guard — should be unreachable given the
              // event-firing assertions above pass, but mirrored for
              // explicit logical coverage.
              ++invalidSamples;
              continue;
            }
            const delta = worstResult.gasUsed - baselineResult.gasUsed;
            samples.push({
              gasWorst: worstResult.gasUsed,
              gasBaseline: baselineResult.gasUsed,
              delta,
            });
            console.log(
              `      [TST-HRROLL-06 sample ${samples.length}/${N_GAS_SAMPLES}] gasWorst=${worstResult.gasUsed}, gasBaseline=${baselineResult.gasUsed}, delta=${delta}`
            );
          }

          if (samples.length < N_GAS_SAMPLES) {
            throw new Error(
              `TST-HRROLL-06: only ${samples.length}/${N_GAS_SAMPLES} valid samples collected after ${totalAttempts} attempts (${invalidSamples} invalid). The advanceGame() path is not reliably reaching _emitDailyWinningTraits — verify state-machine routing.`
            );
          }

          const deltas = samples.map((s) => s.delta);
          const meanDelta =
            deltas.reduce((a, b) => a + b, 0) / deltas.length;
          const variance =
            deltas.reduce((a, b) => a + (b - meanDelta) ** 2, 0) /
            deltas.length;
          const stddev = Math.sqrt(variance);

          // Log-only traceability output — see RELAX rationale at the
          // describe-block header. No assertion on the delta window; the
          // theoretical-attestation cite at 292-01-MEASUREMENT.md §3.c
          // remains the load-bearing acceptance evidence for the gas
          // regression. Mirrors the Phase 291 D-291-GAS-01 SKIP-GAS
          // posture.
          console.log(
            `      [TST-HRROLL-06] gas-delta samples = [${deltas.join(
              ", "
            )}]; mean = ${meanDelta.toFixed(
              1
            )} gas; stddev = ${stddev.toFixed(
              1
            )} gas; theoretical anchor = +${GAS_DELTA_THEORETICAL} gas (292-01-MEASUREMENT.md §3.c — load-bearing acceptance evidence; production-path delta is NOT asserted against this anchor under the RELAX disposition)`
          );
          console.log(
            `      [TST-HRROLL-06] PASS — DailyWinningTraits fired under both worst-case-seeded and all-zero-seeded paths across all ${N_GAS_SAMPLES} samples; production-path delta is dominated by downstream JackpotFlipWin / coin-jackpot branch-cost cascades (the trait-byte rewrite at _applyHeroOverride L1623 changes downstream bucket selection), not the _rollHeroSymbol body's ~+${GAS_DELTA_THEORETICAL} gas contribution`
          );
        }
      );
    }
  );

  // ---------------------------------------------------------------------------
  // TST-HRROLL-01..05 cross-attestation — small-N production-path replay
  // matches JS oracle output via DailyWinningTraits event decode.
  //
  // Per D-293-INVOKE-01: `_rollHeroSymbol` is `private view` so no
  // inheritance-style harness can reach it. ALGORITHM_VERIFIED evidence is
  // established by (a) the JS-replay oracle at test/helpers/rollHeroSymbolRef.mjs
  // (used for the chi² + edge-case fixtures) plus (b) this cross-attestation
  // block: for N_CROSS distinct (dailyHeroWagers, randWord) pairs the
  // on-chain `DailyWinningTraits` mainTraitsPacked byte decodes to the
  // hero (q, s) and is asserted byte-equal to the JS oracle's
  // (winQuadrant, winSymbol) output for the same inputs.
  //
  // Decode rules (from _applyHeroOverride L1623-1627):
  //   trait byte = (heroQuadrant << 6) | (heroColor << 3) | heroSymbol
  //   The hero override writes the SAME byte to ALL 4 quadrant slots in
  //   `mainTraitsPacked`, so byte 0 suffices (we read byte at heroQuadrant
  //   for self-documenting symmetry).
  //
  // Cross-attestation strategy NOT used as the LOAD-BEARING distributional
  // verification (handled by the chi² fixtures at N=10000); this is the
  // structural correctness anchor proving the JS oracle's bit-mirror.
  // ---------------------------------------------------------------------------
  describe(
    "TST-HRROLL-01..05 cross-attestation — small-N production-path replay matches JS oracle output via DailyWinningTraits event decode",
    function () {
      it(
        "for " +
          N_CROSS +
          " distinct (dailyHeroWagers, randWord) pairs, the on-chain DailyWinningTraits hero (q, s) matches rollHeroSymbolRef output exactly",
        async function () {
          this.timeout(900_000); // 16 fresh fixtures = 16 full deploys

          // Resolve the JackpotModule interface ONCE for DailyWinningTraits
          // event parsing. The event is declared on JackpotModule but
          // emitted via delegatecall from the GAME contract.
          const jackpotIface = (
            await hre.ethers.getContractAt(
              "DegenerusGameJackpotModule",
              hre.ethers.ZeroAddress // any address; we only need the ABI
            )
          ).interface;

          let matchCount = 0;

          for (let i = 0; i < N_CROSS; ++i) {
            const fixture = await loadFixture(deployFullProtocol);
            const { game, deployer, mockVRF, alice } = fixture;
            const gameAddr = await game.getAddress();
            const baseSlot = deriveDailyHeroWagersBaseSlot();

            // Per-iteration distinct seed pattern. Place ≥ 3 non-zero
            // amounts at varying flat-idx positions so the leader is at
            // different positions across iterations (not always idx 0).
            // The amounts cap at uint32 max via the packDailyHeroWagers
            // saturation guard.
            const raw = new Array(32).fill(0);
            raw[i % 32] = 1000 + i * 100;
            raw[(i + 7) % 32] = 500 + i * 50;
            raw[(i + 13) % 32] = 200 + i * 25;

            // Per-iteration distinct VRF entropy. Cap at uint256 (the
            // 33-byte literal is masked by rollHeroSymbolRef's U256_MASK on
            // the JS side and by the Solidity uint256 type on the on-chain
            // side, so the two byte layouts match exactly).
            const entropy =
              (BigInt(0xc0de0000 + i) << 192n) |
              (BigInt(0xcafe0000 + i) << 128n) |
              (BigInt(0xbeef0000 + i) << 64n) |
              BigInt(0xdead0000 + i);

            // Purchase enough tickets to drive the drain chain into
            // _emitDailyWinningTraits.
            await game.connect(alice).purchase(
              hre.ethers.ZeroAddress,
              200n,
              0n,
              ZERO_BYTES32,
              0, // MintPaymentKind.DirectEth
              false, // foil
              { value: hre.ethers.parseEther("2") }
            );

            // Day-warp + advanceGame to issue VRF request, then fulfill
            // with the per-iteration `entropy` so that the downstream
            // _rollHeroSymbol(dailyIdx, heroEntropy = keccak256(randWord,
            // dailyIdx)) consumes this exact VRF word.
            await pinDailyEntropy(game, deployer, mockVRF, entropy);

            // Drain via repeated advanceGame() until DailyWinningTraits
            // fires. Seed dailyHeroWagers[dailyIdx][q] RIGHT BEFORE each
            // advance so whichever call reaches _emitDailyWinningTraits
            // reads the seeded state. Capture the dailyIdx + final-tx
            // receipt that fires the event.
            const MAX_DRAIN_ITERS = 30;
            let finalReceipt = null;
            let finalDailyIdx = null;
            let capturedSlots = null;
            for (let iter = 0; iter < MAX_DRAIN_ITERS; ++iter) {
              const curDailyIdx = await readDailyIdx(gameAddr);
              await seedDailyHeroWagersDirect(
                gameAddr,
                curDailyIdx,
                baseSlot,
                raw
              );

              let tx;
              try {
                tx = await game.connect(deployer).advanceGame();
              } catch {
                break;
              }
              const receipt = await tx.wait();

              let dailyWinningTraitsFired = false;
              for (const log of receipt.logs) {
                try {
                  const parsed = jackpotIface.parseLog(log);
                  if (parsed && parsed.name === "DailyWinningTraits") {
                    dailyWinningTraitsFired = true;
                    break;
                  }
                } catch {
                  /* not from jackpot interface; skip */
                }
              }
              if (dailyWinningTraitsFired) {
                finalReceipt = receipt;
                finalDailyIdx = curDailyIdx;
                // Re-read the slots after the seed lands so the JS oracle
                // replays against the exact bytes the contract read.
                capturedSlots = await readDailyHeroWagersSlots(
                  gameAddr,
                  curDailyIdx,
                  baseSlot
                );
                break;
              }
            }

            if (finalReceipt === null) {
              throw new Error(
                `TST-HRROLL cross-attestation i=${i}: advanceGame drain never reached _emitDailyWinningTraits within ${MAX_DRAIN_ITERS} iters`
              );
            }

            // Parse mainTraitsPacked from the DailyWinningTraits log.
            let mainTraitsPacked = null;
            let questDay = null;
            for (const log of finalReceipt.logs) {
              try {
                const parsed = jackpotIface.parseLog(log);
                if (parsed && parsed.name === "DailyWinningTraits") {
                  mainTraitsPacked = parsed.args.mainTraitsPacked;
                  questDay = parsed.args.day;
                  break;
                }
              } catch {
                /* skip */
              }
            }
            if (mainTraitsPacked === null) {
              throw new Error(
                `TST-HRROLL cross-attestation i=${i}: failed to parse DailyWinningTraits log from receipt`
              );
            }

            // Drive the JS oracle on the captured state. The on-chain
            // call chain for the natural advanceGame() drain path is:
            //   AdvanceModule._emitDailyWinningTraits(1, rngWord, 1)
            //     → JackpotModule.emitDailyWinningTraits (L1798)
            //     → mainTraitsPacked = _rollWinningTraits(randWord, true)
            //     → r = keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG))
            //     → _applyHeroOverride(traits, r, randWord)
            //     → _rollHeroSymbol(dailyIdx, heroEntropy = randWord)
            // The heroEntropy passed to _rollHeroSymbol is the RAW
            // `randWord` (the third arg of _applyHeroOverride per L1600,
            // wired through to the second arg of _rollHeroSymbol at
            // L1609), NOT the bonus-salted `r`. The oracle's internal
            // keccak chain `pick = keccak256(abi.encode(entropy, day)) %
            // effectiveTotal` then mirrors the contract exactly because
            // the contract does the same keccak at L1683-1685 on the
            // same raw `entropy = randWord` and the same `day = dailyIdx`.
            const oracleOut = rollHeroSymbolRef({
              day: Number(finalDailyIdx),
              entropy,
              dailyHeroWagers: capturedSlots,
            });

            // Assert hasWinner=true (seed has 3 non-zero amounts, so total
            // != 0 and the early-bail at _rollHeroSymbol L1677-1679 does
            // not fire).
            expect(
              oracleOut.hasWinner,
              `i=${i} oracleOut.hasWinner must be true on non-zero seed (raw[${i % 32}]=${raw[i % 32]}, raw[${(i + 7) % 32}]=${raw[(i + 7) % 32]}, raw[${(i + 13) % 32}]=${raw[(i + 13) % 32]})`
            ).to.equal(true);

            // Decode the on-chain hero byte at position `oracleOut.winQuadrant`.
            // Rationale: _applyHeroOverride L1623 writes
            //   `w[heroQuadrant] = (heroQuadrant << 6) | (heroColor << 3) | heroSymbol`
            // — so ONLY the byte at index `heroQuadrant` in mainTraitsPacked
            // carries the override-injected `heroSymbol`. The other three
            // bytes carry JackpotBucketLib.getRandomTraits(r)'s random
            // per-quadrant symbols (each with `quadrant_bits == position`).
            //
            // The quadrant_bits of EVERY byte position N in mainTraitsPacked
            // equal N by construction (both random and override paths
            // encode the byte's own position in its top 2 bits), so the
            // quadrant-byte index IS the load-bearing structural
            // determinator of where the override landed. Cross-attestation
            // therefore reads the byte at `oracleOut.winQuadrant` and
            // asserts symbol_bits == `oracleOut.winSymbol`. If oracle and
            // contract disagree on `heroQuadrant`, the byte at that
            // position will carry a DIFFERENT random symbol (not the
            // oracle's `winSymbol`) and the symbol assertion fails loudly.
            const decoded = unpackHeroFromTraitsPacked(
              mainTraitsPacked,
              oracleOut.winQuadrant
            );
            const onChainSymbolAtOracleQuadrant = decoded.symbol;

            // Sanity invariant: byte at position N always has quadrant
            // bits == N (verified for every byte position; getRandomTraits
            // and _applyHeroOverride both encode position into the top 2
            // bits of the byte at that position).
            expect(
              decoded.quadrant,
              `i=${i} byte-at-position-${oracleOut.winQuadrant} quadrant-bits invariant broke: byte=0x${(
                (BigInt(mainTraitsPacked) >> BigInt(oracleOut.winQuadrant * 8)) &
                0xffn
              ).toString(16)}, expected quadrant_bits=${oracleOut.winQuadrant}`
            ).to.equal(oracleOut.winQuadrant);

            // Load-bearing match assertion: the on-chain symbol at the
            // oracle's predicted hero quadrant must equal the oracle's
            // winSymbol. If the contract's _rollHeroSymbol picked a
            // DIFFERENT (heroQuadrant, heroSymbol) tuple, this byte would
            // hold the random getRandomTraits symbol at that position
            // (uncorrelated with oracle's winSymbol).
            expect(
              onChainSymbolAtOracleQuadrant,
              `i=${i} symbol mismatch at oracle's predicted hero quadrant ${oracleOut.winQuadrant}: oracle.winSymbol=${oracleOut.winSymbol}, onChain symbol at byte ${oracleOut.winQuadrant}=${onChainSymbolAtOracleQuadrant}; mainTraitsPacked=0x${BigInt(mainTraitsPacked).toString(16)}; capturedSlots=[${capturedSlots.map((s) => "0x" + s.toString(16)).join(",")}]; entropy=0x${entropy.toString(16)}; questDay=${questDay}; finalDailyIdx=${finalDailyIdx}`
            ).to.equal(oracleOut.winSymbol);

            matchCount += 1;
          }

          console.log(
            `      [TST-HRROLL cross-attest] ${matchCount}/${N_CROSS} production-path replays matched JS oracle output exactly — D-293-INVOKE-01 ALGORITHM_VERIFIED established`
          );
          expect(matchCount).to.equal(N_CROSS);
        }
      );
    }
  );
});
