# Phase 331 — Deferred Items (out-of-scope discoveries)

Logged during execution; NOT fixed in their discovering plan (scope-boundary rule).

## 331-02 — pre-existing v48-model reward-rehoming failures in `test/fuzz/CrankFaucetResistance.t.sol`

**Discovered:** 331-02 (the GAS-05/GAS-06 round-trip-guard extension).
**Status:** PRE-EXISTING at the committed 330 IMPL HEAD `63bc16ca` — NOT introduced by 331-02.
**Disposition:** DEFERRED to Phase 332 TST (the reward-rehoming proof phase), per STATE.md
("suite 616 passed / 58 failed = v48.0 baseline + 16 reward-rehoming tests INTENTIONALLY
deferred to Phase 332 TST").

The 330 keeper-router redesign re-homed the buy/open/advance bounty into `AfKing.doWork()` and
collapsed the per-item `degeneretteResolve` reward to a count-independent flat `RESOLVE_FLAT_BURNIE`
gated at `>=3` non-WWXRP. The following 9 tests in this file still assert the SUPERSEDED v48
per-item gas-units reward model (`CRANK_RESOLVE_BET_GAS_UNITS` / `CRANK_OPEN_BOX_GAS_UNITS`, the
unrewarded `autoOpen`/single-bet `degeneretteResolve` reward) and therefore fail against `63bc16ca`:

| Test | Why it fails (the 330 model change) |
|------|-------------------------------------|
| `testSelfCrankRoundTripNonPositive` | single losing bet earns 0 (the new `>=3` non-WWXRP gate) |
| `testFuzz_RoundTripNonPositiveAcrossGasPrices` | same — 1 bet is below the `>=3` gate |
| `testBatchEmitsExactlyOneCreditFlipWithSum` | flat `1e18` once, not `3 × per-item` |
| `testDuplicateInBatchRewardsOnce` | below-gate (2 effective) earns 0 under the flat model |
| `testWinningBetFullResolvePathStillPegsReward` | single bet below the `>=3` gate → 0 reward |
| `testCrankBeforeRngWordSkipsAndDoesNotReward` | now reverts `NoWork()` (0 resolved) instead of returning |
| `testZeroSuccessBatchEmitsNoCreditFlip` | now reverts `NoWork()` (0 resolved) instead of returning |
| `testMultiBoxSelfCrankRoundTripNonPositive` | `AfKing.autoOpen` is the UNREWARDED passthrough; only `doWork()` credits |
| `testFuzz_MultiBoxRoundTripNonPositiveAcrossGasPrices` | same — open reward moved to `doWork()` |

**Why NOT fixed here:** 331-02's charter is to ADD the flat-per-tx round-trip guards (GAS-05) and
the `degeneretteResolve` flat-reward guard (GAS-06) — all 10 new guards pass. Rewriting the 9
superseded v48-model assertions is the reward-rehoming proof that Phase 332 TST owns (TST-01..04).
The 10 new 331-02 guards already cover the v49 flat-per-tx model end-to-end against REAL gas.

## 331-03 — pre-existing v48-model / slot-drift failures in `test/fuzz/CrankNonBrick.t.sol`

**Discovered:** 331-03 (the Seed 2 keeper-batch no-brick extension).
**Status:** PRE-EXISTING at the committed 330 IMPL HEAD `63bc16ca` — NOT introduced by 331-03
(verified: my 117-line addition is purely additive [0 deletions]; the four tests fail IDENTICALLY
with my change stashed, on the committed file). Same deferral basis as the 331-02 entry above
(the known 58-failure baseline; 16 reward-rehoming + slot-drift tests deferred to Phase 332 TST).
**Disposition:** DEFERRED to Phase 332 TST.

| Test | Why it fails (the 330 model change / slot drift) |
|------|--------------------------------------------------|
| `testCrankBetsSkipsPoisonedMiddleItem` | reward model: 2 resolves are below the new `>=3` non-WWXRP flat gate → 0 creditFlip (asserts the v48 per-item `1 != 0`) |
| `testFuzz_CrankBetsPoisonPositionNeverBricks` | same — 2 resolves below the `>=3` gate → 0 reward (v48 per-item peg assertion) |
| `testCrankBoxesSkipsPoisonedEntryViaTryCatch` | `autoOpen` is the UNREWARDED passthrough post-330 + the `lootboxEthBase` slot drifted from the v47 `:1548-1559` layout the helper hardcodes (331-01 SUMMARY: 330 moved box cursors to slots 62/63); the inject mis-targets → `E()` |
| `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` | the rngLocked whole-batch pre-check no longer reverts at entry for this fixture's slot-injected state (slot-drift: the `RNG_LOCKED_SHIFT`/`lootboxRngPacked` slot-37 comment is pre-330) |

**Why NOT fixed here:** 331-03's charter is to ADD the Seed 2 keeper-batch no-brick proof
(`testKeeperBatchSkipsPoisonedMiddlePlayer` + the fuzz variant) parameterized for the gated 331-05
path — both NEW tests pass GREEN against the current path. The pre-existing slot-drift + v48-reward
assertions in the untouched part of the file are the reward-rehoming / slot-resync work Phase 332
TST owns. The new no-brick proof does not depend on the drifted slots (it reads `lootboxEthBase`
via the same helper but for FRESH daily-index buys, and asserts purchase/refund, not the box-open
reward path).
