---
phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean
reviewed: 2026-05-14T00:00:00Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - contracts/modules/DegenerusGameJackpotModule.sol
  - contracts/libraries/EntropyLib.sol
  - contracts/storage/DegenerusGameStorage.sol
  - contracts/modules/DegenerusGameMintModule.sol
  - contracts/test/JackpotBernoulliTester.sol
  - test/stat/Ent05KeccakRefactorInvariant.test.js
  - test/integration/CrossSurfaceTicketMixing.test.js
  - test/stat/SurfaceRegression.test.js
  - test/stat/JackpotTicketRollSeedUniqueness.test.js
  - test/stat/JackpotTicketRollBernoulliEv.test.js
  - test/fuzz/RollRemainderGas.t.sol
  - test/fuzz/TicketLifecycle.t.sol
  - test/unit/EventSurfaceUnification.test.js
  - package.json
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 278: Code Review Report

**Reviewed:** 2026-05-14
**Depth:** standard
**Files Reviewed:** 14
**Status:** issues_found

## Summary

Phase 278 makes three production-contract changes plus a test wave:
1. `_jackpotTicketRoll` swaps its entropy-evolution primitive from `EntropyLib.entropyStep` (xorshift) to `EntropyLib.hash2(entropy, entropy)` (scratch-slot keccak self-mix).
2. The 3 `JackpotTicketWin` emit sites de-scale their 4th arg from `count * TICKET_SCALE` to whole-ticket counts.
3. The dead `EntropyLib.entropyStep` function and the zero-caller `_queueLootboxTickets` storage wrapper are deleted.

**Correctness verdict on the contract changes: clean.** The keccak swap preserves the caller contract (a pure `uint256 -> uint256` evolution threaded between the two medium-amount-branch rolls); `hash2(e,e)` is a deterministic function so the two sequential rolls still receive distinct words (`hash2(E,E)` vs `hash2(hash2(E,E), hash2(E,E))`), and keccak collision-resistance makes a same-word collision negligible. Output values differ from the pre-refactor xorshift for a given seed — this is intentional and explicitly asserted as a NEW (not byte-equivalent) invariant by `Ent05KeccakRefactorInvariant.test.js`. The emit de-scaling correctly aligns all 3 sites with the whole-ticket count passed to the adjacent `_queueTickets` call; the event signature/topic-hash is unchanged. Both deleted functions are confirmed zero-reference across `contracts/` after the change. Gas: per-roll ~+15-25 gas (accepted, documented), deployed bytecode -689 bytes (net-negative).

All findings below are in the **test wave**, not the production contracts. None block the phase.

## Warnings

### WR-01: CrossSurfaceTicketMixing slot-math "self-validation" is vacuous at baseline

**File:** `test/integration/CrossSurfaceTicketMixing.test.js:497-523, 637-660`
**Issue:** `resolveLiveTicketsOwed` claims to make the hardcoded `TICKETS_OWED_PACKED_BASE_SLOT = 13n` derivation "self-validating" by matching the raw-slot `owed` against `ticketsOwedView`. But `[CROSS-01a]` and `[CROSS-01c]` only ever run it at baseline, where every candidate slot reads `0` and `ticketsOwedView` also returns `0`. The first candidate key (`BigInt(lvl)`) therefore "matches" with `0 === 0` regardless of whether slot 13 is the correct base slot or the keccak nesting is correct. A wrong base slot that happens to read zero (i.e. almost any unused slot) would pass `[CROSS-01c]`'s `snap.matched` assertion identically. The test gives false confidence that the slot math is pinned. `[CROSS-01b]` does re-read post-open, but it can also pass with `sawWholeTicketAward === false` (non-ticket lootbox roll), so the non-zero round-trip may never execute in a given run.
**Fix:** Either (a) drive a deterministic non-zero whole-ticket award before asserting `snap.matched` (so `0 === 0` cannot be the matching pair), or (b) hard-fail `[CROSS-01b]` if no run in the suite ever observes `after.owed > 0n`, or (c) cross-check the base slot independently against the hardhat build-info `storageLayout` JSON rather than relying solely on a runtime read that is all-zero at baseline.

### WR-02: `[CROSS-01b]` primary live-state assertion can pass without exercising any ticket write

**File:** `test/integration/CrossSurfaceTicketMixing.test.js:554-635`
**Issue:** `[CROSS-01b]` is documented as the PRIMARY (D-278-TST-CROSS-DEPTH-01) assertion, but it has three independent escape hatches that each let it pass without testing the rem-byte invariant against a real write: (1) `reachOpenableLootbox` soft-skip, (2) `findOpenableEthIndex` returning null soft-skip, (3) `sawWholeTicketAward === false` warn-and-continue when the lootbox roll picks a non-ticket reward. In the third case the post-open `rem == 0` checks all run against still-empty slots — identical to the baseline `[CROSS-01a]` check — so the "full-stack" assertion degenerates to the baseline assertion. The structural cross-check `[CROSS-01d]` is the real coverage; the live-state test is weaker than its framing claims.
**Fix:** Make the test deterministic enough to guarantee a whole-ticket award (e.g. buy enough lootboxes / pick a VRF seed known to land a ticket reward), or downgrade the in-code framing of `[CROSS-01b]` from "PRIMARY assertion" to "best-effort live-state corroboration" so a future reader does not over-trust it. As written, the comment block at L384-429 overstates the coverage actually delivered.

### WR-03: Hardcoded short-SHA baselines will silently soft-skip on any clone that lacks them

**File:** `test/integration/CrossSurfaceTicketMixing.test.js:322-335`; `test/stat/SurfaceRegression.test.js:1013, 1195-1219`
**Issue:** `[03d]` resolves the pre-278 event-definition baseline via `git show 8a81a87c~1:...` and soft-skips (`this.skip()`) on any failure. `SurfaceRegression` SURF-01..05 anchor on `6a7455d1` and also soft-skip on unreachable baseline. On a shallow clone, a squash-merge, or a history rewrite, every one of these protected-surface gates silently converts to a skip — the byte-identity proof that is the entire point of the file evaporates with only a `console.warn`. This is a pre-existing pattern in the repo, but Phase 278 adds a fresh 360-line v40.0 SURF block and a new `[03d]` gate that inherit it, widening the surface that can vanish unnoticed.
**Fix:** At minimum, add a single suite-level assertion that fails loud if ALL SURF baselines are unreachable (distinguishing "shallow clone — fetch --unshallow" from "one baseline drifted"). A soft-skip per gate is defensible; a suite where 100% of the regression gates skipped and the run still reports green is not.

## Info

### IN-01: Drift-gate regexes are whitespace-tolerant but not comment-tolerant

**File:** `test/stat/Ent05KeccakRefactorInvariant.test.js:165`; `test/stat/JackpotTicketRollBernoulliEv.test.js:174-191`
**Issue:** The drift gates assert production source matches `entropy = EntropyLib.hash2(entropy, entropy);` and the inline Bernoulli predicate via regex over the raw file text. A future refactor that splits the call across lines with an interleaved comment, or renames the `entropy` local, trips the gate as a false positive even when behaviour is identical. This is the intended fail-closed direction (better a false alarm than silent drift), so it is informational only — but the gate is matching source text, not compiled behaviour, and that limitation should be understood by anyone touching `_jackpotTicketRoll`.
**Fix:** None required. Optionally note in the gate comment that it is a source-text pin, not a semantic one.

### IN-02: `JackpotBernoulliTester` NatSpec carries hardcoded source-line references

**File:** `contracts/test/JackpotBernoulliTester.sol:31` ("`DegenerusGameStorage.sol:165`"), and `:36` references; also `test/stat/SurfaceRegression.test.js:459` retains a stale `"L2192 BAF entropy = EntropyLib.entropyStep(entropy)"` label inside `SURF_04_PROTECTED_RANGES`
**Issue:** Line-number references in comments rot the moment any line is inserted above them. The `SurfaceRegression.test.js:459` label still says `entropyStep` even though L2192 now contains `hash2` — it is harmless because the `SURF-04` `it()` is correctly `it.skip()`'d and superseded by the v40.0 block, but a reader auditing the array sees a contradictory label. (Project memory `feedback_no_history_in_comments.md` / "comments describe what IS" applies.)
**Fix:** Drop the `entropyStep` text from the dead `SURF_04_PROTECTED_RANGES` entry (or delete the now-superseded array entirely since its `it()` is skipped). Prefer symbol/anchor references over line numbers in `JackpotBernoulliTester` NatSpec.

### IN-03: `test:stat` script line is now very long and unsorted

**File:** `package.json:10`
**Issue:** The `test:stat` script appends 5 more test files on one line (now 16 files). It is functionally correct but increasingly unreadable and merge-conflict-prone; the file ordering is neither alphabetical nor grouped.
**Fix:** Optional — no functional impact. If touched again, consider a `mocharc` spec glob or splitting the stat suite registration.

---

_Reviewed: 2026-05-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
