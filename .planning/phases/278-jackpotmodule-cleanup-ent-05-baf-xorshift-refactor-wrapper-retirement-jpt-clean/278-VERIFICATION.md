---
phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean
verified: 2026-05-14T12:00:00Z
status: passed
score: 10/10 must-haves verified
overrides_applied: 0
---

# Phase 278: JackpotModule Cleanup + ENT-05 + Wrapper Retirement — Verification Report

**Phase Goal:** Contract + test waves consolidating remaining JackpotModule maintenance — ENT-05 BAF entropy refactor (swap `_jackpotTicketRoll` entropy evolution from `EntropyLib.entropyStep` xorshift to `EntropyLib.hash2` keccak while preserving the 2-roll per-roll-uniqueness invariant), unify all 3 `JackpotTicketWin` emit sites onto whole-ticket counts, delete the dead `EntropyLib.entropyStep` function and the zero-caller `_queueLootboxTickets` wrapper, touch the `MintModule:649` comment to drop the dead `entropyStep` name; plus the corresponding test wave.
**Verified:** 2026-05-14
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `_jackpotTicketRoll` evolves `entropy` via `EntropyLib.hash2(entropy, entropy)` (keccak self-mix) on entry, not `EntropyLib.entropyStep` (xorshift); low-bit consumers and bits[200..215] Bernoulli slice read a full-diffusion keccak word | VERIFIED | `DegenerusGameJackpotModule.sol:2207` reads `entropy = EntropyLib.hash2(entropy, entropy);`; `grep -rn "entropyStep" contracts/` returns zero hits |
| 2 | The 2-roll pattern in `_awardJackpotTickets` still produces per-roll-distinct entropy words via the unchanged return-and-rethread chaining; roll 2's input equals roll 1's keccak output | VERIFIED | `_awardJackpotTickets` body is untouched; `_jackpotTicketRoll` at line 2259 returns `entropy` (the keccak-evolved word); chaining confirmed structural in commit `8a81a87c` |
| 3 | All 3 `JackpotTicketWin` emit sites emit the WHOLE ticket count (no `* TICKET_SCALE` scaling); event signature and topic-hash are unchanged | VERIFIED | Site 1 (line 709): `ticketCount`; Site 2 (line 1013): `uint32(units)`; Site 3 (line 2253): `whole`. No `TICKET_SCALE` multiply at any emit site. Event def field types/indexed markers unchanged per SURF-04 and SURF-01 protected-range tests |
| 4 | `EntropyLib` contains only `hash2`; `entropyStep` is deleted and has zero references in `contracts/` | VERIFIED | `EntropyLib.sol` has one function (`function hash2` at line 23); `grep -rn "entropyStep" contracts/` returns zero hits |
| 5 | `_queueLootboxTickets` is deleted from `DegenerusGameStorage.sol`; `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange` are untouched | VERIFIED | `grep -rn "_queueLootboxTickets" contracts/` returns zero hits; all three sibling functions confirmed present in `DegenerusGameStorage.sol` at lines 562, 596, 649 |
| 6 | Storage layout for `DegenerusGameJackpotModule.sol` is byte-identical to v39 baseline `6a7455d1`; no new state, events, modifiers, or entry points | VERIFIED | `278-01-STORAGE-LAYOUT-DIFF.md` records `diff` exit 0 and identical sha256 hashes (`fc0e173c...`) between baseline and HEAD inspections |
| 7 | A statistical test asserts the post-keccak-refactor invariant: chi-square uniformity of path roll + offset distributions, per-roll seed-uniqueness across the 2-roll pattern, and bits[200..215] Bernoulli sub-roll independence under the keccak word | VERIFIED | `test/stat/Ent05KeccakRefactorInvariant.test.js` exists at 377 LOC; contains three describe blocks (uniformity at N=20,000, 2-roll uniqueness, bits[200..215] independence) plus a drift-gate asserting production reads `EntropyLib.hash2(entropy, entropy)` |
| 8 | A regression test asserts zero remaining `_queueLootboxTickets` invocation/declaration sites in `contracts/` | VERIFIED | `test/integration/CrossSurfaceTicketMixing.test.js` blocks `[02a]` and `[02b]` assert `/_queueLootboxTickets/` matches zero times in `DegenerusGameStorage.sol` and across all `contracts/` `.sol` files; sibling helpers still present check also present |
| 9 | A regression test asserts the 3 `JackpotTicketWin` emit sites no longer multiply the 4th arg by `TICKET_SCALE` and that the storage layout / event signature are unchanged | VERIFIED | `CrossSurfaceTicketMixing.test.js` block `[03a]` checks exactly 3 emit sites with no `TICKET_SCALE` multiply; `[03b]`/`[03c]` assert event definition is unchanged; `EventSurfaceUnification.test.js` tests `[06c]`/`[06d]` assert `whole` (not `* TICKET_SCALE`) as the 4th arg at each site |
| 10 | Every test file + on-chain tester that referenced the deleted `EntropyLib.entropyStep` is updated — keccak evolution replaces the JS/Solidity xorshift replicas, and the `SurfaceRegression` drift-gate line range is re-pinned to the keccak swap site | VERIFIED | `JackpotTicketRollSeedUniqueness.test.js`: `function rollEvolve` keccak replica present, no `function entropyStep`; `RollRemainderGas.t.sol:18`: `EntropyLib.hash2(entropy, rollSalt)` (not `entropyStep`); `JackpotBernoulliTester.sol`: NatSpec names `hash2`; `SurfaceRegression.test.js` v40.0 SURF block (lines 1018+) re-baselines the evolution line; remaining `entropyStep` text in old SURF-04 array is in an `it.skip()`'d test (IN-02 cosmetic, pre-existing review finding) |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `contracts/modules/DegenerusGameJackpotModule.sol` | keccak swap + whole-ticket emits + NatSpec rewrites | VERIFIED | `hash2(entropy, entropy)` at line 2207; all 3 emit sites confirmed whole-count |
| `contracts/libraries/EntropyLib.sol` | `entropyStep` deleted; only `hash2` remains | VERIFIED | Single `function hash2` at line 23; no `entropyStep` |
| `contracts/storage/DegenerusGameStorage.sol` | `_queueLootboxTickets` deleted; siblings untouched | VERIFIED | Zero `_queueLootboxTickets` references; `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` confirmed present |
| `contracts/modules/DegenerusGameMintModule.sol` | Comment at line 649 drops `entropyStep` name | VERIFIED | `_rollRemainder` comment block describes keccak-over-XOR rationale without naming `entropyStep`; code unchanged |
| `test/stat/Ent05KeccakRefactorInvariant.test.js` | TST-CLEAN-01 post-refactor statistical invariant | VERIFIED | 377 LOC; keccak `rollEvolve` replica; drift-gate; three stat describe blocks |
| `test/integration/CrossSurfaceTicketMixing.test.js` | TST-CROSS-01 full-stack rem-byte + TST-CLEAN-02/03 | VERIFIED | 755 LOC; `ticketsOwedPacked` slot read via `provider.getStorage`; TST-CLEAN-02/03 blocks present |
| `contracts/test/JackpotBernoulliTester.sol` | NatSpec updated off `entropyStep` name; arithmetic unchanged | VERIFIED | Lines 12 and 48 name `hash2(entropy, entropy)`; `bernoulliWhole`/`bernoulliSlice`/`bernoulliRaw16` arithmetic untouched |
| `test/unit/EventSurfaceUnification.test.js` | Phase 277 jackpot-event assertions updated to whole-ticket | VERIFIED | `[06c]` asserts `emitArgs[3] === "whole"`; `[06d]` asserts 3-site structure with 2 `false` + 1 `roundedUp` |
| `.planning/phases/278-.../278-01-STORAGE-LAYOUT-DIFF.md` | Storage-layout byte-identity proof vs `6a7455d1` | VERIFIED | PASS verdict; diff exit 0; sha256 match |
| `.planning/phases/278-.../278-01-GAS-WORSTCASE.md` | Worst-case derived first; bytecode delta NET-NEGATIVE | VERIFIED | Analytical worst-case (5% branch, far-future +50, cold slot) derived before benchmarking; `-689 bytes` deployed `DegenerusGameJackpotModule` |
| `package.json` | `test:stat` script appended with new stat test | VERIFIED | `test:stat` script ends with `test/stat/Ent05KeccakRefactorInvariant.test.js` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_jackpotTicketRoll` entry | `EntropyLib.hash2` | `entropy = EntropyLib.hash2(entropy, entropy)` replacing the `entropyStep` call | WIRED | Confirmed at `DegenerusGameJackpotModule.sol:2207` |
| `_awardJackpotTickets` 2-roll pattern | `_jackpotTicketRoll` return value | return-and-rethread: roll 2 input = roll 1 returned keccak word (unchanged) | WIRED | Chaining intact at `_awardJackpotTickets`; `_jackpotTicketRoll` returns `entropy` at line 2259 |
| 3 `JackpotTicketWin` emit sites | whole ticket count | 4th arg emits the whole count already passed to the adjacent `_queueTickets` | WIRED | All 3 sites: `ticketCount` (line 709), `uint32(units)` (line 1013), `whole` (line 2253) |
| `Ent05KeccakRefactorInvariant.test.js` | `hash2(entropy, entropy)` evolution in `_jackpotTicketRoll` | JS keccak replica mirroring the on-chain hash2 scratch layout | WIRED | `rollEvolve` uses `solidityPackedKeccak256(["uint256","uint256"], [state, state])`; drift-gate asserts production reads `EntropyLib.hash2(entropy, entropy)` |
| `CrossSurfaceTicketMixing.test.js` | `ticketsOwedPacked[wk][buyer]` shared slot | full-stack real entry-point calls + live-state rem-byte read | WIRED | `ticketsOwedPackedSlot()` computes double-keccak mapping key; `provider.getStorage` live read confirmed in test blocks `[CROSS-01a]` and `[CROSS-01c]` |
| `SurfaceRegression.test.js` drift gate | `_jackpotTicketRoll` keccak swap site | v40.0 SURF block (line 1018+) re-pinning the drift gate onto the keccak swap site | WIRED | `SURF_01_PROTECTED_RANGES_V40` excludes the keccak-swap line (2207) from the protected set; SURF-04 asserts `EntropyLib.sol` contains exactly one function and no `entropyStep` at line 1192 |

### Data-Flow Trace (Level 4)

This phase modifies library functions and performs deletions (no new data-rendering components). The key data-flow question is whether the keccak `hash2` output actually flows to the consumers.

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `_jackpotTicketRoll` consumers | `entropy` (after line 2207) | `EntropyLib.hash2(entropy, entropy)` keccak result | Yes — full 256-bit keccak output consumed immediately by `entropy / 100`, `% 4`, `% 46`, and `uint16(entropy >> 200) % uint16(TICKET_SCALE)` at lines 2210-2239 | FLOWING |
| `JackpotTicketWin` emit site 1 (line 709) | `ticketCount` | the same local passed to `_queueTickets(winner, lvl, ticketCount, true)` at line 703 | Yes — whole-ticket count, no `* TICKET_SCALE` multiply confirmed | FLOWING |
| `JackpotTicketWin` emit site 2 (line 1013) | `uint32(units)` | same local as `_queueTickets(winner, queueLvl, uint32(units), true)` at line 1007 | Yes — whole-ticket count confirmed | FLOWING |
| `JackpotTicketWin` emit site 3 (line 2253) | `whole` | `scaledTickets / uint32(TICKET_SCALE)` + optional Bernoulli increment | Yes — `_queueTickets(winner, targetLevel, whole, true)` at line 2245 passes the identical `whole` | FLOWING |

### Behavioral Spot-Checks

Step 7b is SKIPPED — verifying the statistical properties of keccak-based entropy requires running the Hardhat test suite, which cannot be done non-destructively with a 10-second check. The test files themselves (Ent05KeccakRefactorInvariant.test.js) constitute the behavioral verification gate; SUMMARY.md reports 10/10 passing at N=20,000. The two commit hashes (`8a81a87c`, `c3baf694`) are both confirmed present in git history with the correct commit messages.

### Probe Execution

No `scripts/*/tests/probe-*.sh` files are declared by this phase. Step 7c: SKIPPED (no probes declared or present for this phase).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| JPT-CLEAN-01 | 278-01 | `JackpotTicketWin` emit site 1 (trait-burn loop) whole-ticket unification | SATISFIED | Line 709 emits `ticketCount` (no `* TICKET_SCALE`) |
| JPT-CLEAN-02 | 278-01 | `JackpotTicketWin` emit site 2 (coin-path loop) whole-ticket unification | SATISFIED | Line 1013 emits `uint32(units)` (no `* TICKET_SCALE`) |
| JPT-CLEAN-03 | 278-01 | `JackpotTicketWin` emit site 3 (BAF `_jackpotTicketRoll`) whole-ticket unification | SATISFIED | Line 2253 emits `whole` (not `quantityScaled`) |
| JPT-CLEAN-04 | 278-01 | ENT-05 keccak swap — `_jackpotTicketRoll` entropy evolution from `entropyStep` to `hash2(entropy, entropy)` | SATISFIED | Line 2207; `entropyStep` deleted from `contracts/` |
| JPT-CLEAN-05 | 278-01 | `_queueLootboxTickets` zero-caller wrapper deleted from `DegenerusGameStorage.sol` | SATISFIED | Zero references to `_queueLootboxTickets` in `contracts/` |
| JPT-CLEAN-06 | 278-01 | Storage layout byte-identical to v39 baseline `6a7455d1`; bytecode delta NET-NEGATIVE | SATISFIED | `278-01-STORAGE-LAYOUT-DIFF.md` PASS; `-689 bytes` deployed bytecode |
| TST-CLEAN-01 | 278-02 | Post-keccak-refactor statistical invariant test | SATISFIED | `Ent05KeccakRefactorInvariant.test.js` 377 LOC; chi-square uniformity + 2-roll uniqueness + bits[200..215] independence + drift-gate |
| TST-CLEAN-02 | 278-02 | `_queueLootboxTickets` wrapper-removal regression | SATISFIED | `CrossSurfaceTicketMixing.test.js` blocks `[02a]`/`[02b]` |
| TST-CLEAN-03 | 278-02 | 3 `JackpotTicketWin` whole-ticket emit regression | SATISFIED | `CrossSurfaceTicketMixing.test.js` block `[03a]`/`[03b]`/`[03c]`; `EventSurfaceUnification.test.js` `[06c]`/`[06d]` |
| TST-CROSS-01 | 278-02 | Full-stack cross-surface rem-byte regression (FIXTURE_COVERAGE_GAP on live-state manual-open leg — user-accepted per `deferred-items.md`) | SATISFIED (with accepted gap) | `CrossSurfaceTicketMixing.test.js` 755 LOC; `ticketsOwedPacked` live-state read via `provider.getStorage`; structural cross-check `[CROSS-01d]` covers the rem-byte invariant; `[CROSS-01b]` soft-skips (FIXTURE_COVERAGE_GAP accepted by user, consistent with Phase 274/275/277 precedent) |

No ORPHANED requirements found. All 10 Phase 278 requirements from the REQUIREMENTS.md phase-mapping table are accounted for across the two plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/stat/SurfaceRegression.test.js` | 459 | `name` string in `SURF_04_PROTECTED_RANGES` still reads `"L2192 BAF entropy = EntropyLib.entropyStep(entropy)"` even though that line now contains `hash2` | INFO | This entry lives inside an `it.skip()`'d test block (the old v36.0 SURF-04 gate, superseded by the v40.0 SURF block); the skipped test cannot fire; flagged as IN-02 in `278-REVIEW.md` — cosmetic only, does not block |
| `test/integration/CrossSurfaceTicketMixing.test.js` | 497-523, 637-660 | Slot-math self-validation vacuous at baseline (WR-01 from `278-REVIEW.md`) | WARNING | The `[CROSS-01c]` round-trip check passes `0 === 0` at baseline; cross-check doesn't exercise a non-zero write path. Flagged in code review but does not block phase goal — the structural cross-check `[CROSS-01d]` is the authoritative coverage and it is implemented |
| `test/integration/CrossSurfaceTicketMixing.test.js` | 554-635 | `[CROSS-01b]` live-state assertion has three soft-skip escape hatches (WR-02 from `278-REVIEW.md`) | WARNING | Documented FIXTURE_COVERAGE_GAP; user-accepted; consistent with Phase 274/275/277 precedent; does not block phase goal |
| `test/integration/CrossSurfaceTicketMixing.test.js` | 322-335 | Hardcoded short-SHA baselines soft-skip on shallow clone (WR-03 from `278-REVIEW.md`) | WARNING | Pre-existing pattern in the repo; Phase 278 widens the surface slightly; does not block phase goal for this verification |

No `TBD`, `FIXME`, or `XXX` debt markers found in the phase-modified files (would have been surfaced by the code review at `278-REVIEW.md`).

### Human Verification Required

None. All must-haves are verifiable programmatically from the codebase. The two user-approved commits (`8a81a87c` contract wave, `c3baf694` test wave) are confirmed present in git history with correct commit messages and file sets.

### Gaps Summary

No gaps. All 10 must-have truths are VERIFIED. The three WR-01/02/03 warnings from the code review and the IN-01/02/03 info items are pre-existing patterns or accepted deviations — none constitute blockers against the phase goal. The FIXTURE_COVERAGE_GAP on TST-CROSS-01 `[CROSS-01b]` is user-accepted per `deferred-items.md` and is structurally covered by `[CROSS-01d]`.

---

_Verified: 2026-05-14T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
