---
phase: 282-multi-call-drain-regression-fixture-tst-fix
verified: 2026-05-16T00:00:00Z
status: passed
score: 11/11 must-haves verified
overrides_applied: 2
overrides:
  - must_have: "TST-FIX-05 hard gas ceiling assertion (≤2880 cumulative / ≤144 per-call)"
    reason: "User-authorized reduced scope 2026-05-16 — no v40 baseline harness exists; no delta to assert against. Theoretical ceiling from 281-01-MEASUREMENT.md §3a remains theoretical-only. Empirical patched-side gas logged informationally (216,449,415 total / 8,354,736 max / 6,764,044 avg)."
    accepted_by: "purgegamenft@gmail.com"
    accepted_at: "2026-05-16T00:00:00Z"
  - must_have: "TST-FIX-06 production anchor replay against blocks 10862393..10862412 (PRODUCTION_REPLAYABLE evidence class)"
    reason: "User-authorized reduced scope 2026-05-16. Quote: 'if the underlying issue is fixed, doing exact replication tests is not necessary, we diagnosed the bug'. v40 git-worktree harness + captured production trace artifact dropped. F-41-01 evidence class downgrades PRODUCTION_REPLAYABLE → ALGORITHM_VERIFIED; the W2 invariant + structural-distinctness + single-call byte-identity (TST-FIX-01..04) is the proof basis."
    accepted_by: "purgegamenft@gmail.com"
    accepted_at: "2026-05-16T00:00:00Z"
---

# Phase 282: Multi-Call Drain Regression Fixture (TST-FIX) — Verification Report

**Phase Goal:** Regression test suite covering the cross-call-equivalence-to-single-call invariant Phase 281 establishes (reduced scope per user authorization 2026-05-16 — production replay + hard gas ceiling dropped).
**Verified:** 2026-05-16
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (under reduced scope)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | TST-FIX-01 W2 indexer-replay: JS reference reconstruction equals on-chain credited trait multiset trait-by-trait, across the multi-call drain | VERIFIED | Test `TST-FIX-01 — W2 indexer-replay…` PASS in 618ms. Log line: `[W2 lvl=1] num-emissions=29 \| emitted-count-sum=8000 \| on-chain=8000 \| reconstructed=8000 \| path-accumulator=B`. Trait-by-trait mismatch count asserted == 0. |
| 2 | TST-FIX-02 non-increasing 4th-field: `owed_at_call_entry` is strictly non-increasing across consecutive emissions within a player's drain at a fixed `(lvl, queueIdx)` slot, and terminal emission reaches `owedAtCallEntry == count` | VERIFIED | Test `TST-FIX-02 — emitted owed_at_call_entry is monotonically non-increasing…` PASS in 376ms. Anchor sequence first=8000 → last=266 over 29 emissions; terminal emit `owedAtCallEntry==count==266`. |
| 3 | TST-FIX-03 pairwise-distinct keccak inputs: the 29 emitted `owed_at_call_entry` values within `(lvl=1, queueIdx=2)` are pairwise distinct (backward-trace witness) | VERIFIED | Test `TST-FIX-03 — emitted owed_at_call_entry values are pairwise distinct…` PASS in 380ms. `Set(owedValues).size == owedValues.length` asserted per slot. |
| 4 | TST-FIX-04 single-call byte-identity: 1-ticket purchase → 1 emission with `count=4`; JS reference replay against `(baseKey, entropy, processed=0, owedSalt=owed, count=owed)` byte-identical to on-chain credited multiset | VERIFIED | Test `TST-FIX-04 — single-call drain byte-identity…` PASS in 130ms. Log line: `[TST-FIX-04 slot 1-2] count=4 owed_at_call_entry=4 → JS reference returned 4 traits with 4 unique trait ids`. |
| 5 | B2 symmetric coverage: both drain paths exercised — Path B (current-level via `_processOneTicketEntry` from `processTicketBatch`) via the 2000-ticket purchase; Path A (future-pool via `processFutureTicketBatch`) via whale-bundle queueing at future levels 2..5 | VERIFIED | Anchor test `[B2-symmetric] whale bundle drain exercises Path A…` PASS in 495ms. Log lines: `[B2 path-A W2 lvl=2..5] ... path-accumulator=A` (4 levels confirmed Path A). 2000-ticket scenario `path-accumulator=B` confirms Path B at lvl=1. |
| 6 | TST-FIX-05 informational (overridden): empirical patched-side gas logged but no hard ceiling assertion (no v40 baseline) | VERIFIED (override) | Log line: `[gas-info] patched-side empirical: total=216449415 \| per-call max=8354736 \| per-call avg=6764044 \| across 32 txs`. Override accepted per user authorization 2026-05-16. |
| 7 | TST-FIX-06 dropped (overridden): production crime-scene replay dropped; F-41-01 evidence class downgrades PRODUCTION_REPLAYABLE → ALGORITHM_VERIFIED | VERIFIED (override) | SUMMARY.md §"Decisions Modified" + commit `a1212b00` body cite explicit user authorization quote. Phase 284 handoff narrative documented. |
| 8 | Zero `contracts/` mutations since Phase 281 (HEAD `221afcf7`) | VERIFIED | `git diff --stat 221afcf7..HEAD -- contracts/` → empty output. |
| 9 | Zero `KNOWN-ISSUES.md` edits | VERIFIED | `git diff --stat 221afcf7..HEAD -- KNOWN-ISSUES.md` → empty output. |
| 10 | No comparative/historical language in test files (per `feedback_no_history_in_comments.md`) | VERIFIED | `grep -cE "previously\|pre-fix this would\|the bug at v40\|formerly was"` → `0:0` on both files. (Header comment block on test file describes reduced scope using "is dropped"/"is the audit subject" present-tense framing; no `previously`/`pre-fix this would`/`the bug at v40`/`formerly was` matches.) |
| 11 | Diff scope exactly the 3 documented files (SUMMARY + test + helper); no orphan files | VERIFIED | `git diff --name-only 221afcf7..HEAD` returns exactly: `.planning/phases/282-multi-call-drain-regression-fixture-tst-fix/282-01-SUMMARY.md`, `test/edge/MintBatchDeterminism.test.js`, `test/helpers/raritySymbolBatchRef.mjs`. |

**Score:** 11/11 truths verified (9 directly + 2 via accepted override per user re-scope authorization 2026-05-16)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/edge/MintBatchDeterminism.test.js` | 794 LOC, 6 `it()` blocks, drives end-to-end multi-call drain via `purchase(...) → advanceGame()` chain | VERIFIED | File exists, 794 LOC, 6 `it()` blocks all PASS in ~23s. Imports `raritySymbolBatchRef` + `computeBaseKey` from helper; uses `loadFixture(deployFullProtocol)`. |
| `test/helpers/raritySymbolBatchRef.mjs` | 183 LOC, verbatim port of `_raritySymbolBatch` (L544-L643) at HEAD `221afcf7`; exports `TICKET_LCG_MULT`, `computeBaseKey`, `raritySymbolBatchRef` | VERIFIED | File exists, 183 LOC, all 3 symbols exported (lines 38, 47, 126). Constant `TICKET_LCG_MULT = 6364136223846793005n` matches contract L92 `uint64 private constant TICKET_LCG_MULT = 6364136223846793005`. `abi.encode` tuple `(uint256, uint256, uint32, uint32)` over `(baseKey, entropyWord, groupIdx, ownedSalt)` matches contract L572 byte-for-byte. |
| `.planning/phases/282-multi-call-drain-regression-fixture-tst-fix/282-01-SUMMARY.md` | Source of truth for what landed under reduced scope; cites D-282-* + inherited D-281-* anchors; documents Phase 284 handoff | VERIFIED | File present, 12,803 bytes. "Decisions Modified" section documents D-282-PREFIX-BRANCH-01 DROPPED + D-282-GAS-EMPIRICAL-01 DOWNGRADED + F-41-01 evidence class downgrade. Path-accumulator deviation note documented. Phase 284 handoff itemized. |
| `scripts/v41/capture-v40-anchor-replay-trace.mjs` | DROPPED per user re-scope | OVERRIDE | Not present (intentional under reduced scope). Override applied. |
| `282-V40-ANCHOR-REPLAY-TRACE.json` | DROPPED per user re-scope | OVERRIDE | Not present (intentional under reduced scope). Override applied. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `test/edge/MintBatchDeterminism.test.js` | `test/helpers/raritySymbolBatchRef.mjs` | `import { computeBaseKey, raritySymbolBatchRef }` | WIRED | Lines 79-82: import resolves; runtime invocations at lines 197-204, 738-745 produce real trait arrays consumed by W2 invariant asserts. |
| Test file | Solidity `_raritySymbolBatch` body (L544-L643) | Verbatim port: per-group keccak 4-tuple + LCG seeds + LCG step + quadrant addition | WIRED | JS encode tuple `(uint256, uint256, uint32, uint32)` over `(baseKey, entropyWord, groupIdx, ownedSalt)` byte-for-byte matches contract L572 `abi.encode(baseKey, entropyWord, groupIdx, ownedSalt)`. `TICKET_LCG_MULT = 6364136223846793005n` matches contract L92. LCG step at JS L171 (`s = s * TICKET_LCG_MULT + 1n`) matches contract L582 (`s = s * TICKET_LCG_MULT + 1`). Quadrant addition at JS L174 matches L585-L586. |
| Test file | `TraitsGenerated` event payload | `storage.interface.parseLog(log)` + `parsed.args.startIndex → owedAtCallEntry` field rename | WIRED | Lines 98-115: payload parser captures `startIndex` as `owedAtCallEntry` per D-281-STARTINDEX-SEMANTICS-01; consumed by all 4 invariant tests. |
| Test file | On-chain credited trait state | `game.getTickets(trait, lvl, 0, 10_000, player)` × 256 trait ids | WIRED | Lines 137-156 `readPlayerTraitMultiset` — iterates all 256 trait ids; produces multiset for W2 comparison. Real call (not mock). |
| Test file | Production codepath | `game.connect(buyer).purchase(...)` + `game.connect(deployer).advanceGame()` chain | WIRED | Lines 121-135 `buyTickets` invokes public `purchase(...)`; lines 280-303 `drainViaAdvanceGame` calls public `advanceGame()` in a loop — the exact codepath that produced the v40 bug. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Test file | `aliceEvents` | `parseTraitsGeneratedEvents(receipt, storage)` against real receipts from real `advanceGame()` txs | YES — 29 emissions for the 2000-ticket Path B anchor; 12 emissions across lvl=2..5 for Path A whale bundle | FLOWING |
| Test file | `onChainMultiset` | `readPlayerTraitMultiset(game, lvl, alice.address)` — real `getTickets` reads against `traitBurnTicket[lvl][trait]` storage | YES — totals match emitted count-sums (`emitted-count-sum=8000 \| on-chain=8000` for Path B; `400` per level for Path A) | FLOWING |
| Test file | `reconstructed` multiset | `raritySymbolBatchRef({baseKey, entropyWord, ownedSalt, startIndex, count})` against real emit-time inputs | YES — `reconstructed=8000` matches `on-chain=8000`; trait-by-trait mismatches asserted == 0 | FLOWING |
| Helper | `raritySymbolBatchRef` return | Computed inline from inputs (no external store) | YES — `Uint8Array` of length `count` populated by the LCG/keccak step loop | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Test suite passes | `npx hardhat test test/edge/MintBatchDeterminism.test.js` | `6 passing (23s)` | PASS |
| Helper exports the 3 documented symbols | `grep -E "^export" test/helpers/raritySymbolBatchRef.mjs` | `TICKET_LCG_MULT`, `computeBaseKey`, `raritySymbolBatchRef` all present | PASS |
| LCG constant matches contract | `grep -n "6364136223846793005" test/helpers/raritySymbolBatchRef.mjs contracts/modules/DegenerusGameMintModule.sol` | helper L38 + contract L92 both match | PASS |
| `abi.encode` tuple matches contract | Read JS L154-L156 vs contract L572 | Both encode `(uint256, uint256, uint32, uint32)` over `(baseKey, entropyWord, groupIdx, ownedSalt)` | PASS |
| No comparative/historical language in test/helper | `grep -cE "previously\|pre-fix this would\|the bug at v40\|formerly was"` | `0:0` on both files | PASS |
| Zero `contracts/` mutations since Phase 281 | `git diff --stat 221afcf7..HEAD -- contracts/` | empty | PASS |
| Zero `KNOWN-ISSUES.md` edits | `git diff --stat 221afcf7..HEAD -- KNOWN-ISSUES.md` | empty | PASS |
| Diff scope exactly 3 documented paths | `git diff --name-only 221afcf7..HEAD` | `282-01-SUMMARY.md`, `MintBatchDeterminism.test.js`, `raritySymbolBatchRef.mjs` (3 paths, exact match) | PASS |
| Commit shape (2 commits on top of 281) | `git log --oneline 221afcf7..HEAD` | `a2e24593 docs(282-01): plan summary` + `a1212b00 test(282): … [TST-FIX-01..04] (REDUCED SCOPE…)` | PASS |
| Decision-anchor citation chain in commit body | `git log -1 --format=%B a1212b00` | D-281-FIX-SHAPE-01 + D-281-STARTINDEX-SEMANTICS-01 + D-281-FIX01-REFRAME-01 + D-282-ASSERTION-FRAME-01 + D-282-B2-COVERAGE-01 all present | PASS |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| (none declared) | — | Phase is a pure-test phase; no `scripts/*/tests/probe-*.sh` declared in PLAN/SUMMARY, and `find scripts -path '*/tests/probe-*.sh'` returns no matches | SKIPPED (no probes — phase is a Hardhat regression fixture; probe execution is the Hardhat test suite itself, executed under Behavioral Spot-Checks above) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TST-FIX-01 | `282-01-PLAN.md` | Multi-call drain trait-byte-identity (W2 indexer-replay per D-281-FIX01-REFRAME-01) | SATISFIED | `TST-FIX-01 — W2 indexer-replay` test PASS. JS reference reconstruction equals on-chain credited multiset trait-by-trait. |
| TST-FIX-02 | `282-01-PLAN.md` | `TraitsGenerated.startIndex` (semantically `owed_at_call_entry`) monotonically non-increasing within a player's drain run (direction-flipped per D-281-STARTINDEX-SEMANTICS-01) | SATISFIED | `TST-FIX-02` test PASS. 29-emission sequence first=8000 → last=266 strictly non-increasing; terminal `owedAtCallEntry==count`. |
| TST-FIX-03 | `282-01-PLAN.md` | Distinct keccak seeds per call across multi-call drain (witness via pairwise-distinct 4th field per D-282-ASSERTION-FRAME-01) | SATISFIED | `TST-FIX-03` test PASS. `Set(owedAtCallEntry).size == 29` for the per-slot drain. |
| TST-FIX-04 | `282-01-PLAN.md` | Single-call drain byte-identity preserved | SATISFIED | `TST-FIX-04` test PASS. 1-ticket purchase → 1 emission count=4 → JS reference replay byte-identical to on-chain credited multiset for the slot. |
| TST-FIX-05 | `282-01-PLAN.md` (`requirements_dropped`) | Hard gas ceiling regression (≤2880 cumulative / ≤144 per-call) | INFORMATIONAL (override) | Dropped per user authorization 2026-05-16 (no v40 baseline to delta against). Empirical patched-side gas logged: total 216,449,415 / max 8,354,736 / avg 6,764,044 across 32 txs. Phase 281 §3a theoretical ceiling remains theoretical-only. Override accepted. |
| TST-FIX-06 | `282-01-PLAN.md` (`requirements_dropped`) | On-chain anchor replay regression vs production blocks 10862393..10862412 | DROPPED (override) | Dropped per user authorization 2026-05-16. F-41-01 evidence class downgrades PRODUCTION_REPLAYABLE → ALGORITHM_VERIFIED. The algorithm is verified via TST-FIX-01..04. Override accepted. |

All 6 TST-FIX requirements accounted for. REQUIREMENTS.md L84-L89 status flips remain the responsibility of Phase 284 traceability roll-up (verifier note: 4 → Complete; 2 → Dropped-per-user-rescope with override evidence cited in this file's frontmatter).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

Anti-pattern scan results:
- `grep -nE "TBD\|FIXME\|XXX"` on test/helper files → 0 matches
- `grep -nE "TODO\|HACK\|PLACEHOLDER"` → 0 matches
- `grep -cE "previously\|pre-fix this would\|the bug at v40\|formerly was"` → `0:0`
- Stub patterns: helper `raritySymbolBatchRef` returns populated `Uint8Array` via real LCG/keccak iteration (not `return []` or `return {}`); test asserts on real on-chain reads (no hardcoded fixture data masquerading as live state)
- The phrase "the v40 bug in the first place" appears in the commit message body but is intentionally framing the audit history; it is NOT in any source file. The test file header (lines 51-64) uses present-tense framing ("is dropped", "is the audit subject", "is diagnosed") rather than disallowed comparative/historical forms — compliant with `feedback_no_history_in_comments.md`.

### Human Verification Required

None. Phase 282 is a pure regression-fixture phase. All 6 invariants assert directly on on-chain event payloads, on-chain storage reads, and JS-reference-replay outputs — there is no UI/UX, no visual rendering, no real-time behavior, and no external service to verify by eye. The 6-passing Hardhat test run is the verification surface; the verifier has executed it.

### Gaps Summary

No gaps. All 4 in-scope invariants (TST-FIX-01..04) verified via passing tests; the 2 dropped requirements (TST-FIX-05 hard ceiling, TST-FIX-06 production replay) carry explicit user authorization documented in the SUMMARY.md "Decisions Modified" section, the test-file header comment block (lines 51-64), and the commit message body for `a1212b00`. The 3-path diff scope is exact; ZERO `contracts/` mutations; ZERO `KNOWN-ISSUES.md` edits; ZERO existing-test mutations. Decision-anchor citation chain in the commit body covers all 5 inherited + new decisions (D-281-FIX-SHAPE-01, D-281-STARTINDEX-SEMANTICS-01, D-281-FIX01-REFRAME-01, D-282-ASSERTION-FRAME-01, D-282-B2-COVERAGE-01).

## Notes — Phase 284 Handoff (Carry-Forward)

These preserved from the SUMMARY for Phase 284 §3.A + §3.B + §4 prose authorship:

1. **F-41-01 evidence class downgrade** — `PRODUCTION_REPLAYABLE → ALGORITHM_VERIFIED`. Phase 284 §4 prose MUST cite the W2 invariant + structural-distinctness of the keccak input set + byte-identity of single-call drain as the proof basis. Production crime scene at blocks 10862393..10862412 is explicitly NOT replayed.

2. **Anchor metadata** —
   - Path B (2000-ticket purchase): alice, lvl-at-first-emit=1, queueIdx-at-first-emit=2, owed-at-first-emit=8000, 29 emissions across 28 txs (one tx had 2 within-call emissions due to cold-budget split). Terminal emission `owed=266 count=266` (drained to zero).
   - Path A (whale bundle): alice queued at future lvl=2..5, owed=400 per level, 3 emissions per level (12 total).
   - Daily VRF entropy: pinned to a constant 256-bit value via `mockVRF.fulfillRandomWords` (any constant — JS reference impl + on-chain code consume the same pinned word).

3. **Path A vs Path B `processed` accumulator deviation** — pre-existing contract quirk:
   - Path A (`processFutureTicketBatch` L499): `processed += take`
   - Path B (`_processOneTicketEntry` L714): `processed += writesUsed >> 1`
   The test handles this via a path-aware accumulator selector (tries both formulas per per-level group; accepts the formula whose JS-reference reconstruction matches the on-chain credited multiset trait-by-trait). NOT a Phase 281 fix gap. Phase 284 §3 may want a documentation-gap note for indexer implementers.

4. **Empirical patched-side gas (informational, no hard ceiling)** — 216,449,415 total / 8,354,736 max / 6,764,044 avg across 32 advanceGame txs containing TraitsGenerated. Phase 281 §3a theoretical ceiling (≤2880 cumulative / ≤144 per-call) remains theoretical-only — Phase 284 §3.B should cite as "theoretical ceiling, empirically not delta-asserted in this milestone".

5. **REQUIREMENTS.md L84-L89 status flips** — Phase 284 traceability roll-up should record:
   - TST-FIX-01..04: Complete (this phase)
   - TST-FIX-05: Informational-only (per user re-scope; cite override)
   - TST-FIX-06: Dropped (per user re-scope; F-41-01 evidence class downgrade; cite override)

---

*Verified: 2026-05-16*
*Verifier: Claude (gsd-verifier)*
*Verification framework: Goal-backward; 2 user-authorized overrides accepted for TST-FIX-05 + TST-FIX-06; all 11 in-scope must-haves verified; 0 gaps.*
