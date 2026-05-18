---
phase: 293-hrroll-regression-fixture-tst-hrroll
verified: 2026-05-17T00:00:00Z
status: passed
score: 13/13 must-haves verified
overrides_applied: 1
overrides:
  - must_have: "TST-HRROLL-06 measures production-path gas-delta against +431 ± 100 soft / ≤ 750 hard window with [BLOCKING_ESCALATION] on noise floor"
    reason: "User RELAX disposition (option i) selected 2026-05-17: production-path delta methodology cannot isolate the _rollHeroSymbol body cost from downstream JackpotBurnieWin / coin-jackpot branch-cost cascades (delta is deterministic at ~46,020 gas, dominated by trait-byte rewrite at _applyHeroOverride L1623 changing downstream bucket selection). TST-HRROLL-06 reformed to log-only traceability + positive-path DailyWinningTraits event-firing assertion + cite to 292-01-MEASUREMENT.md §3.c. Mirrors Phase 291 D-291-GAS-01 SKIP-GAS posture. D-293-INVOKE-01 visibility-flip escalation NOT invoked; contracts/ remains untouched."
    accepted_by: "user (purgegamenft@gmail.com)"
    accepted_at: "2026-05-17"
---

# Phase 293: HRROLL Regression Fixture (TST-HRROLL) Verification Report

**Phase Goal:** Ship TST-HRROLL-01..06 regression fixture covering the post-HRROLL audit subject (Phase 292 commit `a0218952`) — chi² weighted distribution at N=10000, ×1.5 leader-bonus binomial, RNG commitment-window proof, single-bettor + zero-wager edge cases, and production-path gas regression against the +431 theoretical anchor.

**Verified:** 2026-05-17
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth (from ROADMAP SC + plan must_haves)                                                                                                                       | Status      | Evidence                                                                                                                                                                                                                                                                       |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | TST-HRROLL-01 weighted-distribution chi² uniformity passes at N=10000 against bonus-adjusted expected rates (df=3, crit=7.815)                                  | ✓ VERIFIED  | Test runtime output: `chi² = 5.749 < 7.815 (df=3); observed=[4973,2576,1670,781]; expected=[5000.0,2500.0,1666.7,833.3]; N=10000; Wilson-Hilferty Z=1.162`. Seed `[400, 300, 200, 100]` per ROADMAP example. Test passes in 384ms.                                              |
| 2   | TST-HRROLL-02 ×1.5 leader-bonus binomial passes at N=10000 under LOCKED seed `[500, 200, 200, 100]` with expected leader rate 0.60 = 750/1250 (df=1, crit=3.841) | ✓ VERIFIED  | Test runtime output: `empirical leader pick-rate = 0.6033 (target = 0.6 = 750/1250); leaderHits=6033, otherHits=3967, N=10000; chi² = 0.454 < 3.841 (df=1, binomial); Z=-0.020`. LOCKED seed constant at L171 = `[500, 200, 200, 100]`. Test passes in 385ms.                   |
| 3   | TST-HRROLL-03 RNG commitment-window proof: `dailyHeroWagers[D][q]` slot bytes byte-identical across day-D→D+1 wall-clock advance; dailyIdx single-writer        | ✓ VERIFIED  | Test runtime output: `dayD=1; slots=[0x1388·10^25, 0x0, 0x1388·10^42, 0x0]; oracle output={hasWinner:true, q:0, s:3}; dailyIdx==D frozen across wall-clock advance (D-288-FIX-SHAPE-01 single-writer)`. Test uses forge-inspect-derived BASE_SLOT=53. Passes in 20819ms.        |
| 4   | TST-HRROLL-04 single-bettor edge case returns deterministic `(q, s)` over 100 entropy variations (two sub-tests: flat idx 0 + flat idx 17)                      | ✓ VERIFIED  | Both sub-tests pass. Test file L868-L943: seed[idx=0]=1000 asserts (true,0,0) for 100 entropies (82ms); seed[idx=17]=1000 asserts (true,2,1) for 100 entropies, mid-cursor leader-bonus add coverage (93ms).                                                                    |
| 5   | TST-HRROLL-05 zero-wager edge case returns `(false, 0, 0)` over 100 entropy variations per HRROLL-01 early-bail                                                 | ✓ VERIFIED  | Test runtime output: `zero-wager (false, 0, 0) confirmed across 100 distinct entropy values (HRROLL-01 early-bail at total == 0)`. Test passes in 71ms.                                                                                                                       |
| 6   | TST-HRROLL-06 gas regression — RELAX disposition (user-approved override): log-only traceability + DailyWinningTraits event-firing assertion + cite §3.c        | ✓ VERIFIED (override) | 5/5 samples: `gasWorst=713775, gasBaseline=667755, delta=46020`; mean=46020.0; stddev=0.0; DailyWinningTraits fires under both worst-case-seeded and all-zero-seeded paths. Theoretical anchor +431 logged for traceability (cite `292-01-MEASUREMENT.md §3.c`). Test passes in 741ms. RELAX accepted by user 2026-05-17 (see overrides). |
| 7   | Cross-attestation: 16 production-path replays via DailyWinningTraits event decode match JS oracle output exactly (D-293-INVOKE-01 ALGORITHM_VERIFIED)            | ✓ VERIFIED  | Test runtime output: `16/16 production-path replays matched JS oracle output exactly — D-293-INVOKE-01 ALGORITHM_VERIFIED established`. Test passes in 1333ms.                                                                                                                |
| 8   | JS-replay oracle helper `test/helpers/rollHeroSymbolRef.mjs` is a verbatim bit-mirror of `_rollHeroSymbol` (DegenerusGameJackpotModule.sol L1639-L1700)          | ✓ VERIFIED  | File exists (189 lines, 9247 bytes); `rollHeroSymbolRef`, `packDailyHeroWagers`, `ROLL_HERO_SYMBOL_CONSTANTS` exported at L83/L162/L185. Uses `abi.encode(uint256, uint32)` via ethers AbiCoder.defaultAbiCoder() at L130-L133; zero `encodePacked` occurrences. Cross-attested 16/16 against EVM at Plan 02 Task 7. |
| 9   | LOCKED TST-HRROLL-02 seed `[500, 200, 200, 100]` and expected leader rate `750/1250 = 0.60` honored per user disposition 2026-05-17                              | ✓ VERIFIED  | Test L171: `const TST_HRROLL_02_SEED = Object.freeze([500, 200, 200, 100]);` and L172: `const TST_HRROLL_02_EXPECTED_LEADER_RATE = 750 / 1250;`. Empirical 0.6033 against 0.60 target (chi² 0.454 < 3.841).                                                                    |
| 10  | D-293-INVOKE-01 visibility-flip escalation NOT invoked; zero `contracts/` mutations                                                                              | ✓ VERIFIED  | `git diff --name-only contracts/` returns empty (verified at audit time). `_rollHeroSymbol` remains `private view`. ALGORITHM_VERIFIED via 16/16 cross-attestation through DailyWinningTraits event byte-position-`winQuadrant` decode.                                         |
| 11  | Sister frozen test files (`test/edge/HeroOverrideDayIndex.test.js`, `test/edge/MintBatchDeterminism.test.js`, `test/edge/MintCleanupRegression.test.js`, `test/helpers/raritySymbolBatchRef.mjs`) byte-identical | ✓ VERIFIED  | `git diff --name-only` on the four sister files returns empty (verified at audit time).                                                                                                                                                                                       |
| 12  | Single USER-APPROVED batched commit at phase close carrying both Plan 01 helper + Plan 02 test file                                                              | ✓ VERIFIED  | `git log --oneline -5 -- test/edge/HeroOverrideWeightedRoll.test.js test/helpers/rollHeroSymbolRef.mjs` returns commit `0cd01a9c test(293): HRROLL regression fixture TST-HRROLL-01..06 + JS-replay oracle [TST-HRROLL-01..06]`.                                                |
| 13  | D-293-STALE-VIEW-01 honored: `contracts/DegenerusGame.sol:2545-2563 getDailyHeroWinner` NOT touched and NOT used as assertion vehicle                            | ✓ VERIFIED  | `git diff --name-only contracts/` empty (no contract modifications); test file references `getDailyHeroWinner` only in JSDoc bullet (iv) as path-of-investigation prose (per `grep -n getDailyHeroWinner`).                                                                    |

**Score:** 13/13 truths verified (1 via user-approved override on TST-HRROLL-06).

### Required Artifacts

| Artifact                                             | Expected                                                                              | Status     | Details                                                                                                                                                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/helpers/rollHeroSymbolRef.mjs`                 | JS-replay oracle (bit-mirror of `_rollHeroSymbol`); 3 named exports                   | ✓ VERIFIED | 189 lines, 9247 bytes. Exports `rollHeroSymbolRef` (L83), `packDailyHeroWagers` (L162), `ROLL_HERO_SYMBOL_CONSTANTS` (L185). JSDoc cites contract L1639-L1700 + D-42N-* decision-lock IDs. No encodePacked. |
| `test/edge/HeroOverrideWeightedRoll.test.js`         | TST-HRROLL-01..06 + setup-and-sanity + cross-attestation describe blocks (11 tests)   | ✓ VERIFIED | 1499 lines, 68059 bytes. 7 nested describe blocks under top-level `HeroOverrideWeightedRoll — Phase 293 v42.0 HRROLL regression fixture`. 11 tests all PASS in ~24s (24/24 cross-phase regression).      |

### Key Link Verification

| From                                                  | To                                                                                          | Via                                                                                                                                       | Status     | Details                                                                                                                                                                                                                                            |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/helpers/rollHeroSymbolRef.mjs::rollHeroSymbolRef` | `contracts/modules/DegenerusGameJackpotModule.sol:1639-1700` `_rollHeroSymbol` body         | Verbatim port of pass-1 amount decode + pass-2 cumulative cursor walk + leaderBonus add at idx==leaderIdx                                 | ✓ WIRED    | Helper L100-L150 mirrors contract L1647-L1699; AbiCoder used at L130-L133; cross-attested 16/16 via DailyWinningTraits event decode.                                                                                                              |
| `test/edge/HeroOverrideWeightedRoll.test.js`          | `test/helpers/rollHeroSymbolRef.mjs::rollHeroSymbolRef`                                     | ES module import — drives 10000-iter chi² + small-N edge cases                                                                            | ✓ WIRED    | Test L127-L131: `import { rollHeroSymbolRef, packDailyHeroWagers, ROLL_HERO_SYMBOL_CONSTANTS } from "../helpers/rollHeroSymbolRef.mjs";`. Used at L447, L534, L666, L784 (4+ call sites).                                                          |
| `test/edge/HeroOverrideWeightedRoll.test.js` (TST-HRROLL-03) | `contracts/storage/DegenerusGameStorage.sol:1475` `dailyHeroWagers` mapping        | `ethers.provider.getStorage` with nested-mapping slot derivation `keccak256(abi.encode(D, BASE_SLOT)) + q`                                | ✓ WIRED    | Test L296-L320: `derivedailyHeroWagersSlot()` + `readDailyHeroWagersSlots()` use `hre.ethers.keccak256(AbiCoder.defaultAbiCoder().encode(['uint256','uint256'], [BigInt(D), baseSlot]))` then `parentSlot + q`. Empirically validates BASE_SLOT=53. |
| `test/edge/HeroOverrideWeightedRoll.test.js` (cross-attestation) | `contracts/modules/DegenerusGameJackpotModule.sol:106-111` `DailyWinningTraits` event | `tx.receipt log parse` + `mainTraitsPacked` byte-position-`winQuadrant` decode                                                            | ✓ WIRED    | Test L1267-L1492: 16 production-path replays via `payDailyJackpot` → `DailyWinningTraits` log parse. Byte-indexing correction documented in SUMMARY Deviation #1 (byte at oracle's `winQuadrant`, NOT byte 0). 16/16 matches.                       |
| `test/edge/HeroOverrideWeightedRoll.test.js` (TST-HRROLL-06) | `contracts/modules/DegenerusGameJackpotModule.sol:1988` `_applyHeroOverride` callsite | `tx.receipt.gasUsed` delta between worst-case-seeded vs all-zero-seeded states                                                            | ✓ WIRED    | Test L1036-L1240: production-path delta captured at 46020 gas (deterministic, stddev=0.0 across 5 samples). RELAX disposition per user 2026-05-17 — log-only traceability + DailyWinningTraits event-firing assertion + cite §3.c.                |

### Data-Flow Trace (Level 4)

| Artifact                                             | Data Variable                            | Source                                                                                              | Produces Real Data | Status     |
| ---------------------------------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------ | ---------- |
| `test/edge/HeroOverrideWeightedRoll.test.js`         | `dailyHeroWagers` (TST-HRROLL-01/02/04/05) | `packDailyHeroWagers(rawAmounts)` (synthetic seed via JS oracle path)                              | Yes (synthetic, non-zero, exercises pass-1 + pass-2 + leader-bonus + early-bail) | ✓ FLOWING  |
| `test/edge/HeroOverrideWeightedRoll.test.js`         | `dailyHeroWagers[D][q]` (TST-HRROLL-03) | `placeDegeneretteBet` calls into live deployed contract; bytes read back via `ethers.provider.getStorage` against runtime-derived BASE_SLOT | Yes (live storage; non-zero slots [0x1388·10^25, 0x0, 0x1388·10^42, 0x0]) | ✓ FLOWING  |
| `test/edge/HeroOverrideWeightedRoll.test.js`         | `mainTraitsPacked` (cross-attestation)  | `DailyWinningTraits` event log on actual `payDailyJackpot` advanceGame drain                       | Yes (16/16 live event decodes match JS oracle output exactly)              | ✓ FLOWING  |
| `test/edge/HeroOverrideWeightedRoll.test.js`         | `tx.receipt.gasUsed` (TST-HRROLL-06)    | Two-call production-path delta on actual jackpot resolution                                         | Yes (5 deterministic samples at 46020-gas delta; logged for traceability) | ✓ FLOWING  |

### Behavioral Spot-Checks

| Behavior                                                    | Command                                                                                       | Result                                                                                                                                                                                                                                          | Status  |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| TST-HRROLL test suite runs to completion                    | `timeout 120 npx hardhat test test/edge/HeroOverrideWeightedRoll.test.js`                     | `11 passing (24s)` — all 11 tests PASS                                                                                                                                                                                                          | ✓ PASS  |
| TST-HRROLL-01 chi² < 7.815                                  | (inline log from suite)                                                                       | `chi² = 5.749 < 7.815 (df=3); observed=[4973,2576,1670,781]; N=10000`                                                                                                                                                                            | ✓ PASS  |
| TST-HRROLL-02 chi² < 3.841 + empirical leader rate ≈ 0.60   | (inline log from suite)                                                                       | `empirical leader pick-rate = 0.6033 (target = 0.6 = 750/1250); chi² = 0.454 < 3.841 (df=1)`                                                                                                                                                    | ✓ PASS  |
| Cross-attestation 16/16 match                               | (inline log from suite)                                                                       | `16/16 production-path replays matched JS oracle output exactly — D-293-INVOKE-01 ALGORITHM_VERIFIED established`                                                                                                                                | ✓ PASS  |
| Helper module exports                                       | `grep -nE "export function rollHeroSymbolRef\|export function packDailyHeroWagers\|export const ROLL_HERO_SYMBOL_CONSTANTS" test/helpers/rollHeroSymbolRef.mjs` | 3 exports found at L83, L162, L185                                                                                                                                                                                                              | ✓ PASS  |
| Zero `encodePacked` in helper                               | `grep -cE "encodePacked" test/helpers/rollHeroSymbolRef.mjs`                                  | 0                                                                                                                                                                                                                                                | ✓ PASS  |
| Zero `contracts/` mutations                                 | `git diff --name-only contracts/`                                                              | (empty)                                                                                                                                                                                                                                          | ✓ PASS  |
| Sister frozen tests untouched                               | `git diff --name-only test/edge/HeroOverrideDayIndex.test.js ... test/helpers/raritySymbolBatchRef.mjs` | (empty)                                                                                                                                                                                                                                          | ✓ PASS  |
| Test artifacts committed                                    | `git log --oneline -5 -- test/edge/HeroOverrideWeightedRoll.test.js test/helpers/rollHeroSymbolRef.mjs` | `0cd01a9c test(293): HRROLL regression fixture TST-HRROLL-01..06 + JS-replay oracle [TST-HRROLL-01..06]`                                                                                                                                          | ✓ PASS  |

### Probe Execution

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |

No `scripts/*/tests/probe-*.sh` exist in this repository (verified: `find scripts -path '*/tests/probe-*.sh' -type f` returns nothing). PLAN/SUMMARY documents do not declare any probe paths. Step 7c probe execution: N/A (no probes to run).

### Requirements Coverage

| Requirement     | Source Plan        | Description                                                                                                                | Status       | Evidence                                                                                                                                                                                            |
| --------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TST-HRROLL-01   | 293-01, 293-02     | Weighted-distribution chi² test at N=10000; empirical rate matches expected within chi² p>0.05                             | ✓ SATISFIED  | Test passes: chi² = 5.749 < 7.815 (df=3); observed buckets [4973, 2576, 1670, 781].                                                                                                                |
| TST-HRROLL-02   | 293-01, 293-02     | ×1.5 leader-bonus sanity; empirical leader pick-rate matches arithmetic within chi² tolerance                              | ✓ SATISFIED  | Test passes: empirical 0.6033 vs target 0.60 = 750/1250 (LOCKED seed [500,200,200,100] per user disposition 2026-05-17); chi² = 0.454 < 3.841 (df=1).                                              |
| TST-HRROLL-03   | 293-01, 293-02     | RNG commitment-window proof — day-D wagers frozen across day-D→D+1 advance; dailyIdx single-writer (D-288-FIX-SHAPE-01)    | ✓ SATISFIED  | Test passes: slot bytes byte-identical pre/post-advance; JS oracle reproduces same `(true, 0, 3)` on both captures; dailyIdx invariant confirmed.                                                  |
| TST-HRROLL-04   | 293-01, 293-02     | Single-bettor edge case — deterministic `(q, s)` return with probability 1.0                                              | ✓ SATISFIED  | Two sub-tests pass: idx=0 seed and idx=17 seed each over 100 entropy variations, all deterministic.                                                                                                 |
| TST-HRROLL-05   | 293-01, 293-02     | Zero-wager edge case — `_rollHeroSymbol` returns `(false, 0, 0)` per HRROLL-01 early-bail                                  | ✓ SATISFIED  | Test passes: 100 entropy variations against `[0n, 0n, 0n, 0n]` all return `(false, 0, 0)`.                                                                                                          |
| TST-HRROLL-06   | 293-02             | Gas regression — worst-case execution measured; asserted against D-42N-GAS-01 threshold (RELAX disposition: log-only + cite §3.c) | ✓ SATISFIED (override)  | Test passes under RELAX disposition: 5/5 samples deterministic at 46020-gas delta; DailyWinningTraits fires under both paths; cite to `292-01-MEASUREMENT.md §3.c` is the load-bearing acceptance evidence. User RELAX accepted 2026-05-17. |

No orphaned requirements: ROADMAP maps `TST-HRROLL-01..06` to Phase 293; all six are claimed by either Plan 01 (01-05) or Plan 02 (01-06). Plan 02's superset coverage absorbs Plan 01's claims.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `test/edge/HeroOverrideWeightedRoll.test.js` | L36, L1009 | Prose token `[BLOCKING_ESCALATION]` in comments | ℹ️ Info | Historical prose anchors documenting the dispute resolution per Plan 02 key-decisions (RELAX disposition). No active throw code; both occurrences are inside comments per `grep -n BLOCKING_ESCALATION` showing only those two lines. Per `feedback_no_dead_guards.md`, the active throw + soft/hard-bound assertion machinery was removed cleanly. |

No debt markers (TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER/placeholder/coming soon/not yet implemented) found in either `test/edge/HeroOverrideWeightedRoll.test.js` or `test/helpers/rollHeroSymbolRef.mjs` — `grep -nE "TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER" ...` returns empty.

### Human Verification Required

None — all 13 must-haves verified programmatically via:

- Test suite execution (24s, 11/11 PASS, including the 5 ROADMAP Success Criteria + cross-attestation + setup-and-sanity)
- Cross-attestation of JS oracle vs EVM through 16/16 production-path replays via `DailyWinningTraits` event decode (D-293-INVOKE-01 ALGORITHM_VERIFIED)
- Git diff checks (contracts/ clean; sister frozen tests byte-identical)
- File existence + export greps on the helper
- User RELAX disposition recorded as an override for TST-HRROLL-06

No visual, real-time, or external-service behaviors require human verification.

### Gaps Summary

None. Phase 293 ships a complete TST-HRROLL-01..06 regression fixture covering all 5 ROADMAP Success Criteria for the post-HRROLL audit subject (Phase 292 commit `a0218952`):

1. ✓ Weighted-distribution chi² at N=10000 (TST-HRROLL-01) — empirical chi² = 5.749 vs crit = 7.815.
2. ✓ ×1.5 leader-bonus binomial at N=10000 under LOCKED user-disposition seed `[500, 200, 200, 100]` (TST-HRROLL-02) — empirical rate 0.6033 vs target 0.60 = 750/1250; binomial chi² = 0.454 vs crit = 3.841.
3. ✓ RNG commitment-window proof at fixture level — slot-byte invariance + dailyIdx single-writer confirmed (TST-HRROLL-03).
4. ✓ Edge cases — single-bettor deterministic over 100 entropy variations at idx=0 and idx=17 (TST-HRROLL-04); zero-wager `(false, 0, 0)` over 100 entropies (TST-HRROLL-05).
5. ✓ Worst-case gas regression — TST-HRROLL-06 under user-approved RELAX disposition (option i): log-only traceability + positive-path DailyWinningTraits event-firing assertion + cite to `292-01-MEASUREMENT.md §3.c` as the load-bearing acceptance evidence. Mirrors Phase 291 D-291-GAS-01 SKIP-GAS posture. D-293-INVOKE-01 visibility-flip escalation NOT invoked — contracts/ remains untouched (zero mutations confirmed by `git diff --name-only contracts/` empty).

D-293-INVOKE-01 ALGORITHM_VERIFIED is the load-bearing closure path for the `private view` selector: JS-replay oracle bit-mirror cross-attested 16/16 via `DailyWinningTraits` event decode at the production path. Sister frozen tests byte-identical; single USER-APPROVED batched commit `0cd01a9c` carries both Plan 01 helper + Plan 02 test file per `feedback_batch_contract_approval.md` + `feedback_manual_review_before_push.md`.

Ready to proceed to Phase 294 (DPNERF) per ROADMAP dependency chain.

---

_Verified: 2026-05-17_
_Verifier: Claude (gsd-verifier)_
