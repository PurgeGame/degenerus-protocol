---
phase: 232-decimator-audit
plan: 01
subsystem: audit
tags: [solidity, audit, adversarial, decimator, burn-key, level-keying, consolidated-jackpot-block, mutual-exclusivity, cei, read-only]

# Dependency graph
requires:
  - phase: Phase 230 (230-01-DELTA-MAP.md)
    provides: §1.1 _consolidatePoolsAndRewardJackpots / §1.3 DegenerusGameDecimatorModule surface / §1.8 BurnieCoin.decimatorBurn / §2.2 IM-06 IM-07 IM-09 / §4 Consumer Index DCM-01 row — authoritative scope anchor
provides:
  - 232-01-AUDIT.md — DCM-01 per-function adversarial verdict table covering all 11 decimator-state functions (3 in-3ad0f8d3-diff plus 8 readers in DegenerusGameDecimatorModule.sol whose key-space alignment was re-routed by the fix)
  - 23 SAFE-bucket verdict rows (21 SAFE + 2 SAFE-INFO) across 7 attack vectors from CONTEXT.md D-06 and D-07
  - Zero VULNERABLE, zero DEFERRED row-level verdicts
  - Two SAFE-INFO Finding Candidate: Y rows for Phase 236 FIND-01 (DECIMATOR_MIN_BUCKET_100 dead-code revival; "prev"-prefixed naming vestige in _consolidatePoolsAndRewardJackpots)
affects: [Phase 235 CONS-02, Phase 236 FIND-01, Phase 236 REG-01, Phase 232 DCM-02, Phase 232 DCM-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-function adversarial verdict table pattern mirrored from v25.0 Phase 214 + Phase 231-01 precedent — locked columns Function | File:Line | Attack Vector | Verdict | Evidence | SHA | Finding Candidate (per CONTEXT D-02 + D-13)"
    - "Fresh-read methodology (CONTEXT D-03) — pre-fix vs post-fix comparison via git show 3ad0f8d3^:... and git show 3ad0f8d3 -- ... for both touched files; no reuse of v25.0 Phase 214 or v27.0 Phase 223 verdicts as pre-approved"
    - "Scope-anchor discipline (CONTEXT D-04) — target function set sourced exclusively from 230-01-DELTA-MAP.md §4 Consumer Index DCM-01 row, even though §1.3 (DecimatorModule) is not itself in the 3ad0f8d3 diff (its readers are re-routed by the +1 keying so they MUST be enumerated per D-06)"
    - "Level-bump timing model proof — load-bearing for every key-space verdict; documented inline in Methodology section so downstream auditors do not have to re-derive"
    - "Verdict vocabulary locked to SAFE | SAFE-INFO | VULNERABLE | DEFERRED (per CONTEXT D-02) — different from Phase 231 PASS/FAIL/DEFER vocabulary; CONTEXT D-02 explicitly chose this 4-bucket scheme for 232/233/234"
    - "No F-29-NN finding IDs emitted (CONTEXT D-13) — Phase 236 FIND-01 owns severity classification and ID assignment"
    - "BurnieCoin scope boundary respected (CONTEXT D-14) — burn-key correctness only; sum-in/sum-out hand-off to Phase 235 CONS-02"

key-files:
  created:
    - .planning/phases/232-decimator-audit/232-01-AUDIT.md
    - .planning/phases/232-decimator-audit/232-01-SUMMARY.md
  modified: []

key-decisions:
  - "All 23 row-level verdicts SAFE or SAFE-INFO — 3ad0f8d3 is verified safe on every attack vector from CONTEXT.md D-06 (pro-rata off-by-one + read/write key-space alignment across every consumer) and D-07 (consolidated-block mutual exclusivity + decPoolWei determinism + runDecimatorJackpot self-call args + CEI). No VULNERABLE verdicts, no row-level DEFERRED verdicts."
  - "Level-bump timing model is the load-bearing invariant for every key-space verdict: _finalizeRngRequest at AdvanceModule:1481 increments level (line 1514: level = lvl) SYNCHRONOUSLY at VRF request time, not at fulfillment. By the time advanceGame:402-408 calls _consolidatePoolsAndRewardJackpots(lvl=level, ...) on jackpot-phase day 1, the level has already been bumped on the previous advanceGame call. WRITE-key (BurnieCoin's level()+1 at burn time) and READ-key (post-bump lvl at jackpot resolution) are the SAME integer at every hop."
  - "x00 / x5 mutual exclusivity proven both structurally (else-if at AdvanceModule:758-762 makes x5 unreachable when x00 fires) AND arithmetically (prevMod100==0 ⇒ prevMod10==0≠5; prevMod10==5 ⇒ prevMod100∈{5,15,25,...,95}, none equal 0). Disjointness holds for all lvl ∈ [0, type(uint24).max]."
  - "decPoolWei determinism verified by enumeration: declared at AdvanceModule:757, only assigned at lines 759 and 761 (the two branch arms), zero-initialized by Solidity language semantics. When neither branch fires the variable retains 0 and the if (decPoolWei != 0) tail at line 764 evaluates false — runDecimatorJackpot self-call correctly skipped."
  - "runDecimatorJackpot self-call args byte-identical to pre-fix per git show 3ad0f8d3^: signature (decPoolWei, lvl, rngWord), ordering returnWei = ... → spend = decPoolWei - returnWei → memFuture -= spend → claimableDelta += spend. CEI preserved: only state mutation after the self-call is local-memory variable arithmetic (memFuture, claimableDelta), no SSTORE, no external interaction."
  - "x00-uses-baseMemFuture vs x5-uses-memFuture distinction preserved byte-identically: x00 still draws from the pre-BAF futurePool snapshot (correct — L100 deserves the larger pre-jackpot pool), x5 still draws from the post-BAF live memFuture (correct — x5 jackpots run AFTER any concurrent x10 BAF). The consolidation is a pure refactor — no math change."
  - "DECIMATOR_MIN_BUCKET_100 dead-code revival recorded as SAFE-INFO with Finding Candidate: Y. Pre-fix the lvl % 100 == 0 branch at BurnieCoin:591 was unreachable (decimator window is closed at every L100/L200/... boundary, so decimatorBurn reverted before reaching the bucket selection). Post-fix lvl = level()+1 evaluates to 100 during the L99 OPEN window, activating the better-odds bucket as intended per the commit message."
  - "Terminal decimator path (recordTerminalDecBurn / runTerminalDecimatorJackpot / claimTerminalDecimatorJackpot / terminalDecClaimable) keys by lvl=level (no +1) and is INTENTIONALLY unaffected by 3ad0f8d3. Terminal path has no level-bump between burn and resolution (gameover is a terminal event). Writer key (level via terminalDecWindow()) and reader key (level via GameOverModule.handleGameOverDrain) match by construction. Internal consistency unaffected; recorded SAFE."
  - "BurnieCoin caller-side math on degenerusGame.level() return value verified by single-call-site enumeration: grep -n 'degenerusGame.level\\|.level()' contracts/BurnieCoin.sol returns exactly one hit (line 574). No mixed-key risk — local lvl is then used at lines 591 and 611 with no secondary level() reads. Per CONTEXT D-14, BurnieCoin sum-in/sum-out conservation handed off to Phase 235 CONS-02."

patterns-established:
  - "Documenting the level-bump timing model inline in the AUDIT methodology section so downstream auditors of any decimator-touching commit (not just 3ad0f8d3) can re-verify key-space alignment without re-deriving the synchronous _finalizeRngRequest level=lvl bump"
  - "Pre-fix vs post-fix diff inclusion verbatim in the AUDIT methodology — gives Phase 236 FIND-01 a single-source check for whether the consolidate-block refactor preserved CEI / args / ordering without re-running git show"
  - "Out-of-scope-for-the-fix-but-in-scope-for-the-audit pattern: DegenerusGameDecimatorModule.sol body itself is NOT in the 3ad0f8d3 diff (the commit only touches BurnieCoin.sol and DegenerusGameAdvanceModule.sol per git show 3ad0f8d3 --stat), but every reader of the now +1-keyed decBurn / decBucketBurnTotal / decBucketOffsetPacked / decClaimRounds state MUST be enumerated per D-06 because their key-space is re-routed by the fix"

requirements-completed:
  - DCM-01

# Metrics
duration: 11min
completed: 2026-04-18
---

# Phase 232-01 Summary

DCM-01 Adversarial Audit — Decimator Burn-Key Refactor (`3ad0f8d3`)

**The `3ad0f8d3` decimator burn-key refactor is SAFE on every attack vector: BurnieCoin's `lvl = degenerusGame.level() + 1` write-key matches the post-bump `lvl` read-key at every consumer in `DegenerusGameDecimatorModule` (closing the pre-fix WRITE-at-X / READ-at-X+1 mismatch); the consolidated jackpot block in `_consolidatePoolsAndRewardJackpots` preserves the x00 / x5 branch arithmetic and ordering byte-identically with mutual exclusivity guaranteed both structurally and arithmetically; `decPoolWei` is zero-deterministic outside the two branches so the shared `runDecimatorJackpot` tail self-call is correctly skipped; and the dead-code revival of `DECIMATOR_MIN_BUCKET_100` at the L100 boundary fires exactly as the commit message intended.**

## Goal

Produce `232-01-AUDIT.md` — a per-function adversarial verdict table covering every function touched by commit `3ad0f8d3` plus every reader whose key-space was re-routed by the new `+1` keying, with all 7 DCM-01 attack vectors from `232-CONTEXT.md` D-06 + D-07 exercised. READ-only audit: no writes to `contracts/` or `test/`. No `F-29-NN` finding IDs emitted. BurnieCoin sum-in/sum-out conservation deferred to Phase 235 CONS-02 per D-14.

## What Was Done

- **Task 1 (AUDIT.md production):**
  - Extracted the authored `3ad0f8d3` diff via `git show 3ad0f8d3 -- contracts/BurnieCoin.sol contracts/modules/DegenerusGameAdvanceModule.sol` — confirmed the commit only touches 2 files (BurnieCoin +3/-1; AdvanceModule +17/-29 hunk). `DegenerusGameDecimatorModule.sol` has zero bytes touched by `3ad0f8d3` itself; the module bodies are nonetheless in DCM-01 scope per D-04 / D-06 because the `lvl+1` key-space change re-routes ALL their decimator-state reads.
  - Performed a fresh read of HEAD source (per D-03) for all 11 target functions across `contracts/BurnieCoin.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/modules/DegenerusGameDecimatorModule.sol`, plus the supporting `contracts/DegenerusGame.sol` (`terminalDecWindow()` source) and `contracts/modules/DegenerusGameGameOverModule.sol` (terminal jackpot caller for completeness verification). Recorded real File:Line anchors for every verdict row (no placeholders).
  - Performed a pre-fix vs post-fix comparison via `git show 3ad0f8d3^:contracts/modules/DegenerusGameAdvanceModule.sol` (extracted in the AUDIT.md Methodology section verbatim) — confirmed the consolidated jackpot block preserves arg list `(decPoolWei, lvl, rngWord)`, ordering `runDecimatorJackpot → spend → memFuture -= spend → claimableDelta += spend`, and the `baseMemFuture` vs `memFuture` distinction byte-identically.
  - Derived the level-bump timing model: `_finalizeRngRequest` at AdvanceModule:1481 increments `level` (line 1514: `level = lvl`) SYNCHRONOUSLY at VRF request time, not at fulfillment. By the time `advanceGame:402-408` calls `_consolidatePoolsAndRewardJackpots(lvl=level, ...)` on jackpot-phase day 1, the level has already been bumped on the previous `advanceGame` call. This is load-bearing for every key-space verdict and is documented inline in the AUDIT Methodology section.
  - Grep-enumerated every read/write site of `decBurn` / `decBucketBurnTotal` / `decBucketOffsetPacked` / `decClaimRounds` inside `DegenerusGameDecimatorModule.sol` at HEAD (in-flight: lines 142, 152, 157, 173, 175, 180, 217, 236, 252, 256-258, 279, 282, 286, 297, 362, 502, 505, 527, 542-544; terminal: lines 692, 697, 730-731, 763, 780-781, 795, 798-800, 829, 832, 834, 839, 843, 847, 857, 860, 861, 867, 871). Classified READ vs WRITE; verified each `lvl` key expression matches the writer's key-space.
  - Verified DECIMATOR_MIN_BUCKET_100 reachability proof: pre-fix `lvl % 100 == 0` was unreachable because the decimator window is closed at every L100/L200/... boundary (window closes when transitioning INTO x00 per AdvanceModule:1528) AND at level()=0; post-fix `lvl = level()+1` evaluates to 100 during the L99 OPEN window, activating `DECIMATOR_MIN_BUCKET_100 = 2` (better odds) as intended. Recorded as SAFE-INFO with Finding Candidate: Y.
  - Verified terminal path is intentionally unaffected by `3ad0f8d3`: `terminalDecimatorBurn` at BurnieCoin:646 reads `lvl` from `degenerusGame.terminalDecWindow()` which returns `lvl = level` (DegenerusGame:1169) without `+1`; `handleGameOverDrain` at GameOverModule:82 reads `uint24 lvl = level` and passes to `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` at line 162. Writer key (`level`) and reader key (`level`) match by construction. Recorded as SAFE for all 4 terminal-side rows.
  - Constructed the per-function verdict table with 23 rows spanning all 11 target functions plus the IM-09 BurnieCoin → Game.level chain row. All 7 DCM-01 attack vectors from CONTEXT.md D-06 + D-07 covered: (a) pro-rata off-by-one, (b) read/write key-space alignment across every consumer, (c) x00/x5 mutual exclusivity, (d) decPoolWei determinism, (e) runDecimatorJackpot self-call args + CEI preserved, (f) DECIMATOR_MIN_BUCKET_100 reachability, (g) BurnieCoin caller-side math on degenerusGame.level() return value.
  - Added four subsections in the High-Risk Patterns Analyzed block: Burn-Key Space Alignment (BurnieCoin → recordDecBurn → jackpot readers); Consolidated Jackpot-Block Disjointness (with both structural and arithmetic disjointness proofs); `decPoolWei` Determinism and Tail Reachability; `DECIMATOR_MIN_BUCKET_100` — Newly Live Branch. Plus a fifth orientation subsection on the Terminal Decimator Path being out-of-scope for the +1 keying change.
  - Wrote Findings-Candidate Block (no FAIL/VULNERABLE candidates; two SAFE-INFO observations recorded), Scope-guard Deferrals ("None surfaced"), and Downstream Hand-offs sections (Phase 235 CONS-02 BurnieCoin conservation per D-14; Phase 235 RNG-01/02 N/A no new RNG consumer; Phase 236 FIND-01 ID assignment; Phase 236 REG-01 storage-layout interaction re-check; intra-phase DCM-02 and DCM-03 hand-offs).
  - Initial draft had a 3-bullet Findings-Candidate Block / "Three SAFE-INFO" tally that didn't match the 2-row table; reconciled by folding the third sub-observation (now-live `decBucketBurnTotal[100][2..12][...]` slot) into the first SAFE-INFO bullet (DECIMATOR_MIN_BUCKET_100 dead-code revival) since they describe the same dead-code revival from different angles. Final tally: 23 rows (21 SAFE + 2 SAFE-INFO); 2 Y / 21 N in the Finding Candidate column.
  - Committed atomically as `a7d497e7` via `git add -f` (`.planning/` is gitignored in this repo per repo convention; `git status --porcelain contracts/ test/` empty before and after task execution).

## Artifacts

- `.planning/phases/232-decimator-audit/232-01-AUDIT.md` — DCM-01 adversarial audit: 23-row Per-Function Verdict Table (21 SAFE + 2 SAFE-INFO), Findings-Candidate Block (two SAFE-INFO observations recorded), Scope-guard Deferrals (none surfaced), Downstream Hand-offs (Phase 235 CONS-02 / RNG-01-02 / Phase 236 FIND-01 / Phase 236 REG-01 / DCM-02 / DCM-03), plus High-Risk Patterns Analyzed with five subsections. ~195 lines.
- `.planning/phases/232-decimator-audit/232-01-SUMMARY.md` — this file.

## Counts

| Metric | Value |
|---|---|
| Target functions in scope (from 230-01-DELTA-MAP.md §4 DCM-01) | 11 |
| Verdict-table rows | 23 |
| SAFE verdicts | 21 |
| SAFE-INFO verdicts | 2 |
| VULNERABLE verdicts | 0 |
| DEFERRED verdicts (row-level) | 0 |
| Finding Candidate: Y rows | 2 |
| Finding Candidate: N rows | 21 |
| Scope-boundary hand-offs (documented in Findings-Candidate Block / Downstream Hand-offs prose, not row-level findings) | 4 (Phase 235 CONS-02, Phase 235 RNG-01/02 N/A, Phase 236 FIND-01, Phase 236 REG-01) plus 2 intra-phase (DCM-02, DCM-03) |
| Attack vectors from CONTEXT.md D-06 + D-07 covered | 7 / 7 |
| Owning commit SHA cited | 3ad0f8d3 (36 citations across the file) |
| Files referenced via contracts/*.sol File:Line anchors | 5 (BurnieCoin.sol, DegenerusGameAdvanceModule.sol, DegenerusGameDecimatorModule.sol, DegenerusGame.sol, DegenerusGameGameOverModule.sol — last two for terminal-path verification corroboration) |
| F-29-NN finding IDs emitted | 0 |
| F-29- string occurrences in the file | 0 |
| Out-of-scope deviations from scope-anchor rows | 0 |
| Placeholder `:<line>` strings | 0 |
| `git status --porcelain contracts/ test/` before / after | empty / empty |

## Attack Vector Coverage

All 7 DCM-01 attack vectors per `232-CONTEXT.md` D-06 + D-07 are covered in the verdict table. Sample row-count per vector (some functions have multiple rows per vector where distinct evidence warranted separation):

| Vector | Coverage | Verdict |
|---|---|---|
| (a) Pro-rata off-by-one under `lvl+1` keying | 9+ rows across `decimatorBurn`, `recordDecBurn`, `runDecimatorJackpot`, `_consumeDecClaim`, `consumeDecClaim`, `claimDecimatorJackpot`, `decClaimable`, `_consolidatePoolsAndRewardJackpots` | SAFE |
| (b) Read/write key-space alignment across every consumer | 4+ rows across `recordDecBurn`, `_consumeDecClaim`, `decClaimable`, `_decUpdateSubbucket`/`_decRemoveSubbucket` helpers | SAFE |
| (c) Consolidated-block x00 / x5 mutual exclusivity | 1 row on `_consolidatePoolsAndRewardJackpots` (with explicit two-way proof in High-Risk Patterns subsection) | SAFE |
| (d) `decPoolWei` determinism outside both branches | 1 row on `_consolidatePoolsAndRewardJackpots` (with line-by-line enumeration of the 6 sites referencing `decPoolWei`) | SAFE |
| (e) `runDecimatorJackpot` self-call args + CEI preserved | 1 row on `_consolidatePoolsAndRewardJackpots` (with verbatim pre-fix vs post-fix arg list comparison) | SAFE |
| (f) DECIMATOR_MIN_BUCKET_100 reachability side-effect | 1 row on `BurnieCoin.decimatorBurn` (SAFE-INFO with Finding Candidate: Y; full reachability proof in High-Risk Patterns subsection) | SAFE-INFO |
| (g) BurnieCoin caller-side math on `degenerusGame.level()` return value (IM-09) | 2 rows: 1 on `BurnieCoin.decimatorBurn` for the line-574 single-call-site verification + 1 dedicated IM-09 chain row (Known Non-Issue #3) | SAFE |

## Deviations from Plan

None semantic. Plan executed exactly as written. Two minor in-flight reconciliations recorded for transparency:

- Initial Findings-Candidate Block enumerated "Three SAFE-INFO observations" with the third bullet being the now-live `decBucketBurnTotal[100][2..12][...]` key-space — but that observation is conceptually a sub-consequence of SAFE-INFO #1 (DECIMATOR_MIN_BUCKET_100 dead-code revival), not a standalone row in the verdict table. Reconciled by folding it into the SAFE-INFO #1 bullet so the prose count matches the table count (2 SAFE-INFO rows / 2 Y rows). Verdict tally updated correspondingly.
- Plan instructions named the storage variables as `decBurns` / `decBurnBuckets` / `decPool` (plural / conceptual names). Actual storage at HEAD is `decBurn[lvl][player]` (DecEntry struct), `decBucketBurnTotal[lvl][denom][sub]` (subbucket aggregate), `decBucketOffsetPacked[lvl]` (packed winning subbuckets), `decClaimRounds[lvl]` (DecClaimRound struct holding `poolWei`/`totalBurn`/`rngWord`). Used the actual storage names throughout the AUDIT for File:Line precision.

All acceptance criteria literally satisfied:
- File exists ✓
- All 4 required headers present (Per-Function Verdict Table / Findings-Candidate Block / Scope-guard Deferrals / Downstream Hand-offs) ✓
- Locked column header exact: `| Function | File:Line | Attack Vector | Verdict | Evidence | SHA | Finding Candidate |` ✓
- 36 `3ad0f8d3` citations (requirement ≥ 11) ✓
- 33 `SAFE|SAFE-INFO|VULNERABLE|DEFERRED` occurrences (requirement ≥ 15) ✓
- All 11 target functions have at least one row (verified via grep tally — every named function appears in the table at File:Line in `contracts/`) ✓
- Zero `F-29-` strings (per D-13) ✓
- Zero placeholder `:<line>` strings ✓
- Every verdict cell is `SAFE` or `SAFE-INFO` (no leakage of strings outside the locked vocabulary) ✓
- Every Finding Candidate cell is `Y` or `N` (21 N + 2 Y = 23 rows) ✓
- Every File:Line anchor resolves into `contracts/` at HEAD ✓
- High-Risk Patterns Analyzed has 4 required subsections (Burn-Key Space Alignment / Consolidated Jackpot-Block Disjointness / decPoolWei Determinism / DECIMATOR_MIN_BUCKET_100) plus 1 supplementary (Terminal Decimator Path orientation) ✓
- Phase 235 CONS-02 explicitly named in Downstream Hand-offs (3 occurrences across Methodology + Hand-offs + boundary statement) ✓
- Phase 236 FIND-01 explicitly named (6 occurrences across Findings-Candidate Block + High-Risk Patterns + Hand-offs) ✓
- x00 / x5 disjointness proof explicit in `Consolidated Jackpot-Block Disjointness` subsection (`prevMod10` / `prevMod100` arithmetic enumerated) ✓
- At least one row carries SAFE-INFO + Finding Candidate: Y for DECIMATOR_MIN_BUCKET_100 reachability (BurnieCoin.decimatorBurn at contracts/BurnieCoin.sol:591-593) ✓
- `git status --porcelain contracts/ test/` empty before AND after task execution (READ-only v29.0 milestone constraint honored) ✓

## Known Stubs

None. The artifact is substantive: every verdict row has a real File:Line anchor pointing at HEAD source, every evidence cell cites concrete code semantics with line numbers (not placeholder text), and the five subsections in High-Risk Patterns Analyzed trace the refactor's semantics across the delta with arithmetic proofs.

## Downstream Hand-offs

Emitted from 232-01-AUDIT.md § Downstream Hand-offs:

- **Phase 235 CONS-02 (D-14)** — BurnieCoin sum-in / sum-out conservation proof across `decimatorBurn` plus the `terminalDecimatorBurn` / `burnCoin` / `burnForCoinflip` paths is OUT OF SCOPE for Phase 232 DCM-01. Phase 232 verified burn-key correctness only. Anchor: `230-01-DELTA-MAP.md` §1.8 + §2.2 IM-09 + §4 Consumer Index CONS-02 row.
- **Phase 235 RNG-01 / RNG-02** — N/A: no RNG consumer is added or moved by `3ad0f8d3`. The `runDecimatorJackpot` self-call at AdvanceModule:765-766 forwards the existing `rngWord` byte-identically to pre-fix.
- **Phase 236 FIND-01** — Two SAFE-INFO Finding Candidate: Y rows above (DECIMATOR_MIN_BUCKET_100 dead-code revival including the now-live `decBucketBurnTotal[100][2..12][...]` key-space; "prev"-prefixed naming vestige inside `_consolidatePoolsAndRewardJackpots`) become anchors for Phase 236 severity classification. Recommended Phase 236 disposition: surface as INFO-grade observations.
- **Phase 236 REG-01** — The new `+1` keying interacts with the `decClaimRounds[lvl]` / `decBucketBurnTotal[lvl][...]` / `decBucketOffsetPacked[lvl]` / `decBurn[lvl][player]` storage layout. Phase 236 REG-01 should re-verify any v27.0 INFO finding or `audit/KNOWN-ISSUES.md` entry mentioning these storage variables to confirm the new keying does not regress prior conclusions.
- **Phase 232 DCM-02 (intra-phase)** — DCM-02 owns the `DecimatorClaimed` and `TerminalDecimatorClaimed` event-emission CEI / argument-correctness audit (`67031e7d`). DCM-01 audited the `lvl` argument's KEY-SPACE correctness only — NOT the event-emission semantics.
- **Phase 232 DCM-03 (intra-phase)** — DCM-03 owns the new `claimTerminalDecimatorJackpot` passthrough (`858d83e4`) audit. DCM-01 confirmed the underlying module function reads `lastTerminalDecClaimRound.lvl` from storage — eliminating any caller-passed `lvl` injection risk on the terminal claim.

## Self-Check

All 232-01-AUDIT.md claims verified by direct inspection (re-grep + sed extraction after the in-flight 3-→2 SAFE-INFO reconciliation):

- 36 `3ad0f8d3` citations counted via `grep -c` (requirement ≥ 11) ✓
- 33 `SAFE|SAFE-INFO|VULNERABLE|DEFERRED` occurrences counted (requirement ≥ 15) ✓
- 0 `F-29-` strings (any form) — acceptance criterion satisfied literally ✓
- 0 `:<line>` placeholder strings — every anchor is a concrete integer or integer range ✓
- All 11 target functions have ≥ 1 verdict row (counts via greppable function-name occurrences in the table: `decimatorBurn`=3, `_consolidatePoolsAndRewardJackpots`=5, `recordDecBurn`=2, `runDecimatorJackpot`=2, `_consumeDecClaim`=1, `consumeDecClaim`=1, `claimDecimatorJackpot`=1, `decClaimable`=1, `recordTerminalDecBurn`=1, `runTerminalDecimatorJackpot`=1, `claimTerminalDecimatorJackpot`=1, `terminalDecClaimable`=1, plus `_decUpdateSubbucket`/`_decRemoveSubbucket`=1 helper row + IM-09 chain row=1; total distinct rows = 23)
- Column header line exactly matches CONTEXT D-02 + D-13 locked set ✓
- All 23 verdict cells are exactly `SAFE` or `SAFE-INFO` (extracted via `awk -F' \\| '` on the 4th column → 21 SAFE + 2 SAFE-INFO; zero leakage to other strings) ✓
- All 23 Finding Candidate cells are exactly `Y` or `N` (extracted via `sed -E 's/.*\\| ([YN]) \\|$/\\1/'` → 21 N + 2 Y) ✓
- Task commit `a7d497e7` verified in `git log --oneline` ✓
- `git status --porcelain contracts/ test/` empty (verified before commit AND after commit; READ-only milestone honored) ✓

## Self-Check: PASSED

- `.planning/phases/232-decimator-audit/232-01-AUDIT.md` — FOUND (committed at `a7d497e7`)
- `.planning/phases/232-decimator-audit/232-01-SUMMARY.md` — FOUND (this file)
- Task commit verified: `a7d497e7` in `git log --oneline`.
- Target commit `3ad0f8d3` cited 36 times in 232-01-AUDIT.md (requirement ≥ 11).
- All 11 target functions from 230-01-DELTA-MAP.md §4 DCM-01 row have ≥ 1 verdict row.
- Zero `F-29-` strings in 232-01-AUDIT.md (per D-13).
- READ-only scope guard honored: zero `contracts/` or `test/` writes in this plan (verified via `git status --porcelain contracts/ test/` empty before and after each commit).

---
*Phase: 232-decimator-audit*
*Completed: 2026-04-18*
