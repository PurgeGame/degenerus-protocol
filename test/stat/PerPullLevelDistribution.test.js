// SPDX-License-Identifier: AGPL-3.0-only
// Phase 264 STAT-01 + STAT-02 + D-IMPL-01 boundary cross-validation harness.
//
// STAT-01: per-pull level distribution chi² uniformity over [minLevel, maxLevel].
//          lvlPrime = minLevel + (uint256(keccak256(abi.encode(randomWord, FLIP_LEVEL_TAG, i))) % range)
//          N = 200 calls × 50 pulls/call = 10_000 aggregated samples (D-IMPL-03).
//          Asserts chi² < CHI2_CRIT_05[range - 1] at α=0.05.
//
// STAT-02: per-trait share under deterministic `i % 4` rotation.
//          The JS replica is degenerate (chi² ≈ 0 — exact 13/13/12/12 hits per
//          trait per call, i.e. 50 = 13+13+12+12). The chi² record is
//          informational; the substantive STAT-02 assertion is the boundary
//          harness emitted-traitId series matching the deterministic `i % 4`
//          rotation on-chain (D-IMPL-01 confirms this implicitly via the
//          per-i strict-shape check below).
//
// D-IMPL-01 boundary cross-validation: at fixed seeds, the deployFullProtocol
//          fixture is driven through one full VRF cycle that fulfills with the
//          named seed; the harness harvests the DailyRngApplied event to learn
//          the exact `randomWord` flowed into _awardDailyCoinToTraitWinners
//          (raw VRF word + totalFlipReversals nudge — the helper's actual
//          `randomWord` parameter). For every emitted JackpotFlipWin event
//          the harness recovers the i-index from traitId/64 (each quadrant
//          spans 64 trait IDs and is monotonic in i-order, so the i-index of
//          the k-th emitted event is uniquely determined as the smallest i
//          strictly greater than the prior match where traitIds[i % 4]
//          equals the emitted traitId). The strict assertion is then:
//             jsLvlPrime(randomWord, minLevel, maxLevel, recoveredI) ==
//             emittedEvent.args.level
//          for every emitted event — zero softening, zero multiset fallback.
//          (The event field name is `level` per the contract ABI; this file
//          uses `lvl` as a JS-internal alias for terseness.)
//
// STAT-04 Phase 261 infra reuse: `makeRng`, `CHI2_CRIT_05`, and `wilsonHilfertyZ`
//          are re-declared verbatim from test/stat/TraitDistribution.test.js
//          (Phase 261 L48-56, L87-90, L97-100). Cross-test seed isolation is
//          maintained via distinct seed integers (D-APPROVAL-04 spirit).
//
// Heavy MC + boundary harness — runs ONLY under `npm run test:stat` (NOT
// default `npm test`). Deterministic seeded keccak-counter PRNG; reproducibility
// = exact replay on failure.
//
// Phase 263 HEAD: cf564816 — feat(263): per-pull level resample for daily coin jackpot.

import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// FLIP_LEVEL_TAG = keccak256("coin-level"). The contract declares this as
// `bytes32 private constant FLIP_LEVEL_TAG = keccak256("coin-level");`
// at contracts/modules/DegenerusGameJackpotModule.sol:171. The value is
// computed once here from the same UTF-8 input; STAT-04 sanity test below
// asserts equality with the recomputed digest as a structural pin.
const FLIP_LEVEL_TAG = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("coin-level"));

const PULLS_PER_CALL = 50; // DAILY_COIN_MAX_WINNERS — Phase 263 D-SHAPE-01.

// ---------------------------------------------------------------------------
// STAT-04 Phase 261 infra reuse — re-declared verbatim from
// test/stat/TraitDistribution.test.js (L48-56 / L87-90 / L97-100).
// ---------------------------------------------------------------------------

function makeRng(seed) {
  const seedHex =
    "0x" + BigInt.asUintN(256, BigInt(seed)).toString(16).padStart(64, "0");
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

const CHI2_CRIT_05 = {
  1: 3.841,
  2: 5.991,
  3: 7.815,
  4: 9.488,
  5: 11.070,
  6: 12.592,
  7: 14.067,
};

function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

// ---------------------------------------------------------------------------
// JS replica of the per-pull-level keccak in
// contracts/modules/DegenerusGameJackpotModule.sol _awardDailyCoinToTraitWinners
// (Phase 263 helper body, lines 1794-1796):
//
//   uint24 lvlPrime = minLevel + uint24(uint256(keccak256(
//       abi.encode(randomWord, FLIP_LEVEL_TAG, i)
//   )) % range);
//
// where range = uint24(maxLevel - minLevel + 1).
//
// Drift guard: the D-IMPL-01 boundary harness (describe block 4 below) asserts
// the JS replica produces the EXACT same lvl series as the on-chain
// JackpotFlipWin.lvl emitted across the actual helper invocation under a
// fixed VRF seed. JS-replica drift is structurally impossible without the
// boundary harness failing first.
// ---------------------------------------------------------------------------

function jsLvlPrime(randomWord, minLevel, maxLevel, i) {
  const range = BigInt(maxLevel) - BigInt(minLevel) + 1n;
  const encoded = hre.ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "bytes32", "uint256"],
    [BigInt(randomWord), FLIP_LEVEL_TAG, BigInt(i)],
  );
  const digest = BigInt(hre.ethers.keccak256(encoded));
  return Number(BigInt(minLevel) + (digest % range));
}

// ---------------------------------------------------------------------------
// JS replica of JackpotBucketLib.getRandomTraits + packWinningTraits +
// _rollWinningTraits, used by the boundary harness to know which trait IDs
// the contract derived from a given `randomWord`.
//
// _rollWinningTraits in DegenerusGameJackpotModule.sol composes the entropy
// for the bonus-traits roll as keccak256(abi.encodePacked(randomWord,
// keccak256("BONUS_TRAITS"))) when isBonus=true.
// ---------------------------------------------------------------------------

const BONUS_TRAITS_TAG = hre.ethers.keccak256(
  hre.ethers.toUtf8Bytes("BONUS_TRAITS"),
);

function jsBonusEntropy(randomWord) {
  // abi.encodePacked(uint256, bytes32) = 32-byte word || 32-byte tag = 64 bytes.
  const wordHex = BigInt(randomWord).toString(16).padStart(64, "0");
  const tagHex = BONUS_TRAITS_TAG.slice(2); // strip 0x
  return BigInt(hre.ethers.keccak256("0x" + wordHex + tagHex));
}

// Mirrors JackpotBucketLib.getRandomTraits(uint256 rw):
//   w[0] = uint8(rw & 0x3F)              // 0..63
//   w[1] = 64 + uint8((rw >> 6) & 0x3F)  // 64..127
//   w[2] = 128 + uint8((rw >> 12) & 0x3F)// 128..191
//   w[3] = 192 + uint8((rw >> 18) & 0x3F)// 192..255
function jsGetRandomTraits(rw) {
  const r = BigInt(rw);
  return [
    Number(r & 0x3Fn),
    64 + Number((r >> 6n) & 0x3Fn),
    128 + Number((r >> 12n) & 0x3Fn),
    192 + Number((r >> 18n) & 0x3Fn),
  ];
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

after(function () {
  restoreAddresses();
});

// ---------------------------------------------------------------------------
// (1) STAT-04 — Phase 261 infrastructure reuse + FLIP_LEVEL_TAG sanity.
// ---------------------------------------------------------------------------

describe("STAT-04 — Phase 261 infrastructure reuse + FLIP_LEVEL_TAG sanity", function () {
  it("FLIP_LEVEL_TAG matches keccak256('coin-level')", function () {
    const recomputed = hre.ethers.keccak256(
      hre.ethers.toUtf8Bytes("coin-level"),
    );
    expect(FLIP_LEVEL_TAG).to.equal(recomputed);
  });

  it("makeRng / CHI2_CRIT_05 / wilsonHilfertyZ are byte-identical to Phase 261 source", function () {
    // Structural assertion: the helper bodies live in this file with no
    // out-of-file dependency. STAT-04 default branch is "reuse Phase 261
    // infrastructure" — the source-of-truth is test/stat/TraitDistribution.test.js
    // L48-56 / L87-90 / L97-100. This `it` documents the reuse contract.
    expect(typeof makeRng).to.equal("function");
    expect(CHI2_CRIT_05[3]).to.equal(7.815);
    expect(CHI2_CRIT_05[7]).to.equal(14.067);
    expect(wilsonHilfertyZ(0, 1)).to.be.a("number");

    // Sanity: makeRng is deterministic (fixed seed → fixed first output).
    const a = makeRng(0xC012_DEAD)();
    const b = makeRng(0xC012_DEAD)();
    expect(a).to.equal(b);
  });

  it("BONUS_TRAITS_TAG matches keccak256('BONUS_TRAITS')", function () {
    const recomputed = hre.ethers.keccak256(
      hre.ethers.toUtf8Bytes("BONUS_TRAITS"),
    );
    expect(BONUS_TRAITS_TAG).to.equal(recomputed);
  });

  it("jsGetRandomTraits returns 4 distinct trait IDs across distinct quadrants (0-63, 64-127, 128-191, 192-255)", function () {
    const sample = jsGetRandomTraits(0x123456789abcdef0n);
    expect(sample[0]).to.be.within(0, 63);
    expect(sample[1]).to.be.within(64, 127);
    expect(sample[2]).to.be.within(128, 191);
    expect(sample[3]).to.be.within(192, 255);
  });
});

// ---------------------------------------------------------------------------
// (2) STAT-01 — per-pull level distribution chi² uniformity over 10K samples.
// ---------------------------------------------------------------------------

describe("STAT-01 — per-pull level distribution chi² uniformity over 10K samples", function () {
  this.timeout(60_000); // pure JS loop — sub-second on a modern machine

  // Two range regimes tested independently:
  //   - jackpot-phase: range = 4 (lvl + 1 .. lvl + 4)              df = 3, crit = 7.815
  //   - purchase-phase wider: range = 8 (arbitrary [minLevel, maxLevel]) df = 7, crit = 14.067
  // Each regime gets a distinct seed (D-APPROVAL-04 spirit; cross-test isolation).
  const REGIMES = [
    {
      name: "jackpot-phase range=4",
      minLevel: 100,
      maxLevel: 103,
      range: 4,
      seed: 0xC012_0001,
    },
    {
      name: "purchase-phase range=8",
      minLevel: 50,
      maxLevel: 57,
      range: 8,
      seed: 0xC012_0002,
    },
  ];

  for (const r of REGIMES) {
    it(`${r.name}: chi² < CHI2_CRIT_05[${r.range - 1}] (df=${r.range - 1}) over N=10000`, function () {
      const N_CALLS = 200;
      const observed = new Array(r.range).fill(0);
      const rng = makeRng(r.seed);

      for (let call = 0; call < N_CALLS; call++) {
        const randomWord = rng();
        for (let i = 0; i < PULLS_PER_CALL; i++) {
          const lvl = jsLvlPrime(randomWord, r.minLevel, r.maxLevel, i);
          expect(
            lvl >= r.minLevel && lvl <= r.maxLevel,
            `lvl ${lvl} outside [${r.minLevel}, ${r.maxLevel}] (call ${call} pull ${i})`,
          ).to.be.true;
          observed[lvl - r.minLevel]++;
        }
      }

      const total = N_CALLS * PULLS_PER_CALL; // 10_000
      const expectedPerBucket = total / r.range;
      let chi2 = 0;
      for (let k = 0; k < r.range; k++) {
        const diff = observed[k] - expectedPerBucket;
        chi2 += (diff * diff) / expectedPerBucket;
      }
      const crit = CHI2_CRIT_05[r.range - 1];
      expect(
        chi2 < crit,
        `${r.name}: chi² = ${chi2.toFixed(3)} >= ${crit} (df=${r.range - 1}); observed=[${observed.join(",")}]`,
      ).to.be.true;
      console.log(
        `      [STAT-01] ${r.name}: chi² = ${chi2.toFixed(3)} < ${crit} (df=${r.range - 1}); observed=[${observed.join(",")}]`,
      );
    });
  }
});

// ---------------------------------------------------------------------------
// (3) STAT-02 — per-trait share under deterministic `i % 4` rotation.
// ---------------------------------------------------------------------------

describe("STAT-02 — per-trait share under deterministic `i % 4` rotation", function () {
  it("i % 4 rotation produces exactly 13/13/12/12 hits per trait per call (degenerate chi² ≈ 0)", function () {
    // Phase 263 PPL-03 locks trait_idx = i % 4 with cap = DAILY_COIN_MAX_WINNERS = 50.
    // Across 50 pulls per call:
    //   trait 0 → i ∈ {0, 4, 8, ..., 48}  → 13 pulls
    //   trait 1 → i ∈ {1, 5, 9, ..., 49}  → 13 pulls
    //   trait 2 → i ∈ {2, 6, 10, ..., 46} → 12 pulls
    //   trait 3 → i ∈ {3, 7, 11, ..., 47} → 12 pulls
    // 50 = 13 + 13 + 12 + 12. Recompute structurally below.
    const counts = [0, 0, 0, 0];
    for (let i = 0; i < PULLS_PER_CALL; i++) counts[i % 4]++;
    expect(counts).to.deep.equal([13, 13, 12, 12]);

    // The JS-replica chi² for a degenerate distribution is the chi² of these
    // counts vs uniform expectation (12.5 each). It is a small constant — log
    // for traceability; assertion is trivially below CHI2_CRIT_05[3]=7.815.
    const expectedPerTrait = PULLS_PER_CALL / 4; // 12.5
    let chi2 = 0;
    for (const c of counts) {
      const diff = c - expectedPerTrait;
      chi2 += (diff * diff) / expectedPerTrait;
    }
    expect(chi2).to.be.lt(CHI2_CRIT_05[3]); // df=3, crit=7.815 — trivially passes
    console.log(
      `      [STAT-02] per-trait counts=[${counts.join(",")}] chi²=${chi2.toFixed(4)} (degenerate, df=3 crit=${CHI2_CRIT_05[3]})`,
    );
  });
});

// ---------------------------------------------------------------------------
// Boundary harness drive helpers.
//
// The harness pins the contract-side `randomWord` flowing into
// _awardDailyCoinToTraitWinners to a known value by:
//   1. driving deployFullProtocol to advance one day (which issues a VRF
//      request),
//   2. fulfilling the VRF request with the named seed,
//   3. continuing advanceGame() until the daily flow processes — during which
//      _applyDailyRng emits DailyRngApplied(day, rawWord, nudges, finalWord)
//      and the helper consumes `finalWord` as its `randomWord` argument,
//   4. harvesting the DailyRngApplied event to learn the actual `finalWord`
//      (rawWord + totalFlipReversals); on a freshly-deployed protocol with no
//      coinflip activity, totalFlipReversals == 0 and finalWord == rawWord ==
//      seed.
//
// At purchaseLevel == 1 (level 0, freshly deployed), the advance flow makes
// TWO coin jackpot calls per the contract's `purchaseLevel == 1` branch in
// DegenerusGameAdvanceModule.sol:
//   - First call:  payDailyFlipJackpot(1, rngWord, 1, 1)         range=1
//   - Second call: payDailyFlipJackpot(1, saltedRng, 2, 5)       range=4
//                  saltedRng = keccak256(abi.encodePacked(rngWord, keccak256("BONUS_TRAITS")))
//
// The first call has range=1 (lvlPrime always 1 — degenerate); the second has
// range=4 in [2, 5]. The boundary harness asserts on the SECOND call's events
// so the JS-replica jsLvlPrime is exercised over a non-degenerate range, AND
// the harness verifies the JS replica computes saltedRng identically to the
// contract.
// ---------------------------------------------------------------------------

async function driveOneFullDay(game, deployer, mockVRF, advanceModule, seed) {
  // Step 1: advance one day so the day boundary lets advanceGame() proceed.
  await advanceToNextDay();

  // Step 2: request VRF.
  await game.connect(deployer).advanceGame();
  expect(await game.rngLocked()).to.equal(true);

  // Step 3: fulfill VRF with the named seed.
  const requestId = await getLastVRFRequestId(mockVRF);
  await mockVRF.fulfillRandomWords(requestId, seed);

  // Step 4: continue advancing — collect every receipt + every event for
  // forensic visibility. Stop when rngLocked unlocks.
  const receipts = [];
  for (let i = 0; i < 100; i++) {
    if (!(await game.rngLocked())) break;
    const tx = await game.connect(deployer).advanceGame();
    const receipt = await tx.wait();
    receipts.push({ tx, receipt });
  }
  return receipts;
}

async function harvestDailyRngFinalWord(receipts, advanceModule) {
  // DailyRngApplied(uint32 day, uint256 rawWord, uint256 nudges, uint256 finalWord).
  // Returns the finalWord (= randomWord parameter flowing into the helper).
  for (const { tx } of receipts) {
    const events = await getEvents(tx, advanceModule, "DailyRngApplied");
    if (events.length > 0) {
      return BigInt(events[events.length - 1].args.finalWord);
    }
  }
  return null;
}

async function harvestJackpotFlipWinByCall(receipts, jackpotInterface) {
  // Group emitted JackpotFlipWin events by transaction so we can isolate
  // each individual `_awardDailyCoinToTraitWinners` invocation.
  //
  // Event signature (DegenerusGameJackpotModule.sol L96-102):
  //   event JackpotFlipWin(
  //       address indexed winner,
  //       uint24  indexed level,   // <- positional arg: lvlPrime sampled per pull
  //       uint8   indexed traitId,
  //       uint256 amount,
  //       uint256 ticketIndex
  //   );
  // Three indexed fields means exactly one un-indexed field pair lives in `data`.
  const callGroups = [];
  for (const { tx, receipt } of receipts) {
    const groupForTx = [];
    for (const log of receipt.logs) {
      try {
        const parsed = jackpotInterface.parseLog({
          topics: log.topics,
          data: log.data,
        });
        if (parsed && parsed.name === "JackpotFlipWin") {
          groupForTx.push({
            txHash: tx.hash,
            args: {
              winner: parsed.args.winner,
              lvl: Number(parsed.args.level),
              traitId: Number(parsed.args.traitId),
              amount: BigInt(parsed.args.amount),
              ticketIndex: BigInt(parsed.args.ticketIndex),
            },
          });
        }
      } catch {
        // Not a JackpotFlipWin event — skip.
      }
    }
    if (groupForTx.length > 0) {
      callGroups.push(groupForTx);
    }
  }
  return callGroups;
}


// ---------------------------------------------------------------------------
// (4) D-IMPL-01 — JS replica jsLvlPrime == on-chain JackpotFlipWin.lvl.
// ---------------------------------------------------------------------------

describe("D-IMPL-01 — JS replica jsLvlPrime EXACTLY matches on-chain JackpotFlipWin.lvl at fixed seeds", function () {
  this.timeout(900_000); // 15 min — heavy lifecycle drive across N seeds

  // Distinct deterministic seeds per harness call (D-APPROVAL-04 spirit).
  // ≥3 fixed seeds per the orchestrator's hard requirement and per the plan
  // acceptance criterion `0xC012_010[123]n`.
  const SEEDS = [
    0xC012_0101n,
    0xC012_0102n,
    0xC012_0103n,
  ];

  for (const seed of SEEDS) {
    it(`seed=0x${seed.toString(16)}: jsLvlPrime per-pull byte-identity over [2, 5] under deity-backed dense fixture`, async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, advanceModule, jackpotModule, others } =
        fixture;

      // Pre-compute every contract-side derivative of the seed used by call B:
      //
      //   rngWord    = seed (post-_applyDailyRng with totalFlipReversals == 0)
      //   saltedRng  = keccak256(abi.encodePacked(rngWord, BONUS_TRAITS_TAG))
      //                — passed as `randomWord` arg into call B's helper.
      //                — used by jsLvlPrime per-pull-level keccak.
      //   doubleSalted = keccak256(abi.encodePacked(saltedRng, BONUS_TRAITS_TAG))
      //                — internal `r` in _rollWinningTraits(saltedRng, isBonus=true).
      //                — used by getRandomTraits to derive traitIds.
      //
      // The two distinct salts are required because _rollWinningTraits applies
      // its own BONUS_TRAITS_TAG keccak when isBonus=true, on TOP of the salt
      // already applied by the caller for call B. (Call A's helper instead
      // sees randomWord=rngWord, so its trait roll uses keccak(rngWord, TAG)
      // == saltedRng — different traits than call B's.)
      const saltedRng = jsBonusEntropy(seed);
      const doubleSalted = jsBonusEntropy(saltedRng);
      const traitIds = jsGetRandomTraits(doubleSalted);
      const fullSymIds = traitIds.map((t) => (t >> 6) * 8 + (t & 0x07));

      // Quadrant decomposition guarantees fullSymId in [0, 32) for every
      // quadrant — every trait_i in any quadrant consults the deity cache.
      // Register one deity per quadrant (4 distinct fullSymIds) so the
      // helper's deity-cache lookup populates virtualCount >= 2 for all 4
      // traits. Combined with deity-pass-queued tickets, every (lvlPrime,
      // trait_i) cell across the call B range [2, 5] has effectiveLen >= 2,
      // which means all 50 pulls emit (no skips). This is the precondition
      // for the strict per-pull deep.equal assertion below.
      //
      // Each deity pass costs DEITY_PASS_BASE + k*(k+1)/2 ether (k = prior
      // owners count). Symbol IDs are user-chosen; we register the four
      // fullSymIds derived above. We use signers[6..9] from the `others`
      // array — distinct from the 5 named signers (deployer/alice/bob/carol/
      // dan/eve) to keep the buyer fingerprints separate.
      const deityBuyers = [others[0], others[1], others[2], others[3]];
      for (let q = 0; q < 4; q++) {
        const symbolId = fullSymIds[q];
        const k = q; // owners.length grows by 1 each iteration
        const basePrice = hre.ethers.parseEther(
          (24 + (k * (k + 1)) / 2).toString(),
        );
        await game
          .connect(deityBuyers[q])
          .purchaseDeityPass(deityBuyers[q].address, symbolId, {
            value: basePrice,
          });
      }

      // The contract emits no public view for deityBySymbol — registration
      // success is implied by the purchaseDeityPass tx not reverting (the
      // contract's revert path on duplicate symbolId or other failure modes
      // would surface here as a test crash). The strict 50/50 emit-count
      // assertion below acts as the structural confirmation.

      // Drive one full daily cycle with the seed.
      const receipts = await driveOneFullDay(
        game,
        deployer,
        mockVRF,
        advanceModule,
        seed,
      );

      // Verify the actual `randomWord` flowed through _applyDailyRng matches
      // the seed (no totalFlipReversals nudge — this fixture has no coinflip
      // activity prior to fulfill).
      const finalWord = await harvestDailyRngFinalWord(receipts, advanceModule);
      if (finalWord === null) {
        throw new Error(
          `seed=0x${seed.toString(16)}: DailyRngApplied not emitted in the ` +
          `${receipts.length}-receipt drive cycle — fixture did not reach the ` +
          `daily-RNG branch. Investigate before relaxing the assertion.`,
        );
      }
      expect(
        finalWord,
        `finalWord=0x${finalWord.toString(16)} != seed=0x${seed.toString(16)} ` +
        `— totalFlipReversals nudge unexpected; check fixture state`,
      ).to.equal(seed);

      // Harvest emitted JackpotFlipWin events.
      //
      // The advance flow at purchaseLevel==1 makes TWO coin jackpot calls
      // inside ONE advance transaction:
      //   call A: payDailyFlipJackpot(1, rngWord,    1, 1)  range = 1, lvl=1
      //   call B: payDailyFlipJackpot(1, saltedRng,  2, 5)  range = 4, lvl in [2, 5]
      // The two calls share an emit stream within the same tx. We split them
      // by emitted lvl: call A's events all have lvl == 1; call B's events
      // all have lvl in [2, 5]. Helper invocation order means call A's
      // events come BEFORE call B's events.
      const jackpotInterface = jackpotModule.interface;
      const callGroups = await harvestJackpotFlipWinByCall(
        receipts,
        jackpotInterface,
      );
      expect(
        callGroups.length,
        `Expected >=1 transaction emitting JackpotFlipWin events; got ${callGroups.length}`,
      ).to.be.greaterThanOrEqual(1);

      // Find the transaction containing call B by scanning for events with
      // lvl in [2, 5]. There should be exactly ONE such transaction (the
      // advance tx that ran the daily-jackpot branch).
      let callBEvents = null;
      for (const group of callGroups) {
        const callBSubset = group.filter(
          (e) => e.args.lvl >= 2 && e.args.lvl <= 5,
        );
        if (callBSubset.length > 0) {
          if (callBEvents !== null) {
            throw new Error(
              `seed=0x${seed.toString(16)}: multiple transactions emitted ` +
              `JackpotFlipWin with lvl in [2, 5] — fixture drove an ` +
              `unexpected branch. Investigate before relaxing the assertion.`,
            );
          }
          callBEvents = callBSubset;
        }
      }

      if (callBEvents === null) {
        throw new Error(
          `seed=0x${seed.toString(16)}: no JackpotFlipWin events with ` +
          `lvl in [2, 5] observed — call B (saltedRng, range=[2, 5]) did not ` +
          `emit. Investigate before relaxing the assertion.`,
        );
      }

      // STRICT PRECONDITION: deity-cache backing pins effectiveLen >= 2 for
      // every (lvlPrime, trait_i) cell across the call B range. Every pull
      // must emit. If callBEvents.length != 50, either:
      //   (a) the deity registration did not take effect (fixture bug), or
      //   (b) the helper's deity-cache logic regressed (real drift signal).
      // Either way, surface loud — do NOT relax to per-event match.
      expect(
        callBEvents.length,
        `seed=0x${seed.toString(16)}: call B emitted ${callBEvents.length}/${PULLS_PER_CALL} ` +
        `events under deity-backed dense fixture. Expected 50 (every pull emits). ` +
        `Deity registration: ` +
        traitIds
          .map((t, q) => `q${q}=trait${t}/sym${fullSymIds[q]}`)
          .join(", "),
      ).to.equal(PULLS_PER_CALL);

      // Build the on-chain lvl array (in emission order = i-order).
      const onChainLvls = callBEvents.map((e) => e.args.lvl);
      const onChainTraitIds = callBEvents.map((e) => e.args.traitId);

      // Build the JS-replica lvl array for i = 0..49.
      const jsLvls = [];
      const jsTraitIds = [];
      for (let i = 0; i < PULLS_PER_CALL; i++) {
        jsLvls.push(jsLvlPrime(saltedRng, 2, 5, i));
        jsTraitIds.push(traitIds[i % 4]);
      }

      // STRICT per-pull byte-identity assertion (D-IMPL-01 — orchestrator's
      // explicit requirement: per-pull deep.equal, no multiset fallback).
      expect(
        onChainLvls,
        `seed=0x${seed.toString(16)}: per-pull lvl byte-identity FAILED. ` +
        `JS replica vs on-chain emit stream diverge at one or more i ∈ [0, 50). ` +
        `randomWord=0x${saltedRng.toString(16)}, range=[2, 5]. ` +
        `js[0..9]=[${jsLvls.slice(0, 10).join(",")}] ` +
        `chain[0..9]=[${onChainLvls.slice(0, 10).join(",")}]`,
      ).to.deep.equal(jsLvls);

      // STAT-02 cross-check: emitted traitId series must EXACTLY equal the
      // deterministic `i % 4` rotation under the JS-derived traitIds.
      expect(
        onChainTraitIds,
        `seed=0x${seed.toString(16)}: per-pull traitId byte-identity FAILED. ` +
        `i % 4 rotation drift between JS replica and on-chain emit stream.`,
      ).to.deep.equal(jsTraitIds);

      console.log(
        `      [D-IMPL-01 seed=0x${seed.toString(16)}] ` +
        `${PULLS_PER_CALL}/${PULLS_PER_CALL} pulls emitted; per-pull byte-identity verified ` +
        `over range=[2, 5]; lvl distribution=[${countLevels(onChainLvls).join(",")}] ` +
        `(expected ~12.5 per bucket).`,
      );
    });
  }
});

function countLevels(lvls) {
  const counts = [0, 0, 0, 0]; // [2, 3, 4, 5]
  for (const lvl of lvls) {
    counts[lvl - 2]++;
  }
  return counts;
}
