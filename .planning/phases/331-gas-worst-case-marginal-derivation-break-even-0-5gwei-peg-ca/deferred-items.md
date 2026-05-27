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
