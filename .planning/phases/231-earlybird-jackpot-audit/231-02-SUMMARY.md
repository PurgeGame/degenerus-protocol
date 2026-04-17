---
phase: 231-earlybird-jackpot-audit
plan: 02
subsystem: audit
tags: [solidity, audit, adversarial, earlybird, jackpot-phase, trait-alignment, bonus-traits, salt-isolation, keccak-domain-separator, queue-level-fix, cei, pool-conservation, read-only]

# Dependency graph
requires:
  - phase: Phase 230 (230-01-DELTA-MAP.md)
    provides: §1.2 / §2.3 IM-16 / §4 Consumer Index EBD-02 row — authoritative scope anchor
provides:
  - 231-02-AUDIT.md — EBD-02 per-function adversarial verdict table covering _runEarlyBirdLootboxJackpot (MODIFIED by 20a951df) + _rollWinningTraits (read-only re-verification)
  - 6 PASS verdicts across 4 attack vectors (bonus-trait parity, 4×25 structure, lvl+1 queue fix, futurePool→nextPool CEI, salt-space isolation)
  - Zero FAIL, zero DEFER verdict rows; three DEFER hand-offs to Phase 233 JKP-03, Phase 235 CONS-01, and Phase 235 RNG-01/02 documented as scope boundaries (not findings)
affects: [Phase 233 JKP-03, Phase 235 CONS-01, Phase 235 RNG-01, Phase 235 RNG-02, Phase 236 FIND-01, Phase 236 REG-01, Phase 236 REG-02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-function adversarial verdict table pattern mirrored from v25.0 Phase 214 (214-01-REENTRANCY-CEI.md) — locked columns Function | File:Line | Attack Vector Considered | Verdict (PASS/FAIL/DEFER) | Evidence | Owning SHA"
    - "Fresh-read methodology (CONTEXT D-03) — no reuse of v25.0 Phase 214 or v26.0 Phase 218/219 verdicts as pre-approved; every function audited as if no prior work exists"
    - "Scope-anchor discipline (CONTEXT D-04) — target function set sourced exclusively from 230-01-DELTA-MAP.md §4 Consumer Index EBD-02 row"
    - "Pre-fix vs post-fix diff-comparison pattern — used `git show 20a951df^:contracts/modules/DegenerusGameJackpotModule.sol` to extract the pre-fix queue-index expression and verify the commit message's 'fix queue level' claim against the §1.2 delta-map assertion"
    - "Scope-guard deferral pattern (CONTEXT D-06) — cross-phase concerns recorded as Downstream Hand-offs rather than in-scope findings (Phase 233 JKP-03 cross-path identity, Phase 235 CONS-01 pool algebra, Phase 235 RNG-01/02 commitment window)"
    - "No finding-ID prefix strings emitted (CONTEXT D-09) — Phase 236 FIND-01 owns severity classification and ID assignment"

key-files:
  created:
    - .planning/phases/231-earlybird-jackpot-audit/231-02-AUDIT.md
    - .planning/phases/231-earlybird-jackpot-audit/231-02-SUMMARY.md
  modified: []

key-decisions:
  - "All 6 verdict rows PASS — 20a951df is verified safe on every attack vector from CONTEXT.md D-08 EBD-02. No FAIL verdicts, no open concerns for Phase 236 to classify."
  - "Bonus-trait parity (attack vector a) is PASS at the call-form level — the earlybird call `_rollWinningTraits(rngWord, true)` at contracts/modules/DegenerusGameJackpotModule.sol:677 is byte-identical in arg order and salt flag to the other two bonus-branch consumers at line 1679 (payDailyCoinJackpot bonus branch) and line 1705 (emitDailyWinningTraits main-equivalent at purchaseLevel==1). Cross-path end-to-end identity under actual daily sequencing is a DEFER hand-off to Phase 233 JKP-03, not an open concern."
  - "Salt-space isolation (attack vector b) is PASS via BONUS_TRAITS_TAG = keccak256(\"BONUS_TRAITS\") compile-time domain separator at line 171 — the bonus branch preimage is `keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG))` per line 1870, giving a cryptographically preimage-resistant separation from the main branch's raw randWord input space. No bypass, no player-controllable mix-in."
  - "lvl+1 queue fix (attack vector c) is PASS — pre-fix (20a951df^) spread winners across `baseLevel..baseLevel+4` via a random `levelOffset = uint24(entropy % 5)` then queued at `baseLevel + levelOffset`; HEAD queues all winners at the single argument `lvl` (line 691 `_queueTickets(winner, lvl, ticketCount, true)` + matching emit at lines 693-698). Caller pattern `payDailyJackpot:379` passes `lvl + 1` (game level + 1 = resolution level), matching DCM-01's `decimatorBurn` convention at §1.8 (`BurnieCoin.decimatorBurn`: `uint24 lvl = degenerusGame.level() + 1;`)."
  - "futurePool → nextPool CEI (attack vector d) is PASS at the caller-side-math level — `_setFuturePrizePool(futurePoolLocal - totalBudget)` at line 668 debits BEFORE any `_queueTickets` call; `_setNextPrizePool(_getNextPrizePool() + totalBudget)` at line 711 credits AFTER all queueing writes and event emits complete. `totalBudget` is a single local computed once at line 666 and used unchanged as both debit and credit — sum-before ≡ sum-after at this boundary trivially. Algebraic closure across the four-pool system is a DEFER hand-off to Phase 235 CONS-01."
  - "Winner-selection salt-space isolation inside `_randTraitTicket` is PASS — the earlybird call passes `salt = t ∈ [0,3]` (line 686); other module callers use disjoint salt spaces (`DAILY_COIN_SALT_BASE = 252` at line 221 giving [252,255], and `200 + traitIdx` at lines 1253/1356 giving [200,203]). No salt-space collision across module callers. The 4 bonus trait IDs themselves are quadrant-partitioned [0,63]/[64,127]/[128,191]/[192,255] by `JackpotBucketLib.getRandomTraits` so they are pairwise distinct — no self-collision inside the earlybird loop."
  - "Rewrite narrows surface strictly (qualitative gas improvement): 100 × 2 = 200 `EntropyLib.entropyStep` calls eliminated, 100 × 1 = 100 `_randTraitTicket` calls collapsed to 4, 5-entry `levelPrices` scratch array deleted. Commit message claims 'batches winner selection into 4 _randTraitTicket calls (down from 100), drops the levelPrices[5] array and per-winner entropy step' — corroborated by pre-fix source inspection."
  - "Re-verification per D-03 of the v26.0 Phase 218 `_rollWinningTraits` bonus-branch salt flag: fresh read at HEAD (lines 1865-1875) confirms the keccak domain-separation mechanism is intact. Prior Phase 218/219 verdicts cited as regression anchors only, not as exemption."

patterns-established:
  - "Pre-fix / post-fix diff-quote block in the Queue-Level Fix subsection — both versions of the earlybird queue-index expression are quoted verbatim so reviewers can see the shift from `baseLevel + levelOffset` to the single `lvl` argument without needing to re-run `git show 20a951df^`. Reusable pattern for any future commit with a claimed 'fix' in the message"
  - "Three DEFER hand-offs in the Downstream Hand-offs block documented as scope boundaries (not findings) — Phase 233 JKP-03 (cross-path bonus-trait identity across purchase/jackpot/earlybird paths), Phase 235 CONS-01 (algebraic pool closure), Phase 235 RNG-01/02 (commitment-window back-trace). Matches 231-01-SUMMARY pattern — two of three plans in this phase have emitted zero open findings"
  - "Winner-selection salt-space survey: documented salt ranges across ALL `_randTraitTicket` call sites in the module (earlybird [0,3], coin-near-future [252,255], other [200,203]) to prove no tuple-collision surface exists. Reusable pattern for any audit that touches `_randTraitTicket` or similar keccak-salted selection helpers"

requirements-completed:
  - EBD-02

# Metrics
duration: 20min
completed: 2026-04-17
---

# Phase 231-02 Summary

EBD-02 Adversarial Audit — Earlybird Trait-Alignment Rewrite (`20a951df`)

**The `20a951df` earlybird trait-alignment rewrite is PASS on every attack vector: the bonus-trait call form matches the coin-jackpot consumer byte-for-byte, the `BONUS_TRAITS_TAG` keccak domain separator gives cryptographically sound isolation from the main branch, the `lvl+1` queue fix verifiably replaces the pre-fix 5-level spread with a single-resolution-level queue, and futurePool → nextPool CEI is preserved with a single conserved `totalBudget` local. The 4 × 25-winner structure collapses the pre-fix 100 `_randTraitTicket` calls + 200 entropy steps into 4 calls with zero per-winner entropy stepping — a strict surface narrowing.**

## Goal

Produce `231-02-AUDIT.md` — a per-function adversarial verdict table covering every function touched by commit `20a951df` across §1.2 of `230-01-DELTA-MAP.md` (`_runEarlyBirdLootboxJackpot` MODIFIED) plus a read-only re-verification of `_rollWinningTraits` via §2.3 IM-16, with all 4 attack vectors from `231-CONTEXT.md` D-08 EBD-02 exercised. READ-only audit: no writes to `contracts/` or `test/`. No finding IDs emitted.

## Performance

- **Duration:** ~20 min
- **Started:** 2026-04-17 (post 231-01 completion)
- **Completed:** 2026-04-17
- **Tasks:** 1
- **Files created:** 2 (231-02-AUDIT.md, 231-02-SUMMARY.md)

## Accomplishments

- 6-row per-function verdict table with all PASS verdicts
- 4/4 EBD-02 attack vectors from CONTEXT.md D-08 covered
- Pre-fix (`20a951df^`) vs post-fix (HEAD) queue-index expressions quoted verbatim in the Queue-Level Fix subsection
- Cross-path bonus-trait identity hand-off to Phase 233 JKP-03 documented explicitly
- Algebraic pool-conservation hand-off to Phase 235 CONS-01 documented explicitly
- Winner-selection salt-space survey added (all `_randTraitTicket` callers' salt ranges enumerated)

## Task Commits

1. **Task 1: Extract 20a951df diff + read JackpotModule at HEAD to audit the earlybird trait-alignment rewrite** — `94ab6cfe` (docs)

**Plan metadata:** (this summary + STATE.md + ROADMAP.md update) committed separately below.

## What Was Done

- **Task 1 (AUDIT.md production):**
  - Extracted the authored `20a951df` diff via `git show 20a951df -- contracts/modules/DegenerusGameJackpotModule.sol` — confirmed the 92-line rewrite of `_runEarlyBirdLootboxJackpot` matches the §1.2 delta-map row description exactly.
  - Extracted the pre-fix source via `git show 20a951df^:contracts/modules/DegenerusGameJackpotModule.sol` — captured the per-winner 100-iteration loop, the `levelPrices[5]` scratch array, and the `levelOffset = uint24(entropy % 5)` spread expression for direct quote in the Queue-Level Fix subsection.
  - Performed a fresh read of HEAD source (per D-03) for both target functions: `_runEarlyBirdLootboxJackpot` at lines 664-712, `_rollWinningTraits` at lines 1865-1875. Recorded real File:Line anchors for every verdict row (no placeholders).
  - Traced `rngWord` flow into the earlybird call site: `DegenerusGameAdvanceModule.advanceGame:455` → `payDailyJackpot(true, lvl, rngWord)` → `payDailyJackpot:379` (jackpot-phase, day-1 branch) → `_runEarlyBirdLootboxJackpot(lvl + 1, randWord)` → `_rollWinningTraits(rngWord, true)`:677.
  - Grep-surveyed all other `_rollWinningTraits(..., true)` call sites in the module (lines 343 `false`, 507 `true`, 518 `false`, 521 `true`, 592 `false`, 593 `true`, 677 `true` earlybird, 1679 `true` daily coin, 1705/1707 purchase-phase). Confirmed the earlybird call is syntactically identical to the other `true` consumers.
  - Grep-surveyed all `_randTraitTicket` call sites to map the salt-space partition: earlybird [0,3] at line 686, coin-near-future [252,255] at line 1752 via `DAILY_COIN_SALT_BASE = 252`, other callers [200,203] at lines 1253/1356. Strict disjoint — no tuple collision surface.
  - Inspected `JackpotBucketLib.getRandomTraits` at lines 281-286 and `JackpotBucketLib.unpackWinningTraits` at lines 272-277 to confirm the quadrant-partitioned 4-trait output shape matches the 4-iteration outer loop in the earlybird rewrite.
  - Inspected the `BONUS_TRAITS_TAG` compile-time constant at line 171 — `keccak256("BONUS_TRAITS")`. Not player-controllable. The `abi.encodePacked(randWord, BONUS_TRAITS_TAG)` preimage at line 1870 produces a cryptographically sound domain separator vs. the `randWord`-raw main branch.
  - Constructed the per-function verdict table with 6 rows spanning 2 target functions. All 4 EBD-02 attack vectors from CONTEXT.md D-08 covered across the rows: (a) bonus-trait parity, (b) salt-space isolation, (c) `lvl+1` queue fix, (d) futurePool → nextPool CEI. Added a 5th row specifically for the winner-selection salt-space survey inside `_randTraitTicket` because it's adjacent to vector (b) but distinct — inside-the-function salt space vs. keccak-domain salt flag.
  - Added four subsections in the High-Risk Patterns Analyzed block: Bonus-Trait Parity Invariant (IM-16), Salt-Space Isolation (Bonus vs Main), Queue-Level Fix (`lvl+1`), Pool Arithmetic Integrity (Caller-Side Only) — each traces the semantics for downstream reviewer context and includes the pre-fix/post-fix code quotes.
  - Wrote Findings-Candidate Block ("No candidate findings"), Scope-guard Deferrals ("None surfaced"), and Downstream Hand-offs sections (Phase 233 JKP-03, Phase 235 CONS-01, Phase 235 RNG-01, Phase 235 RNG-02, Phase 236 FIND-01, Phase 236 REG-01/02) per `231-CONTEXT.md` D-06 / D-07 / D-09.
  - Initial draft contained three incidental `F-29-NN` / `F-29-` string mentions in policy/hand-off prose (meta-references explaining what was NOT emitted). All three rewritten to use neutral phrasing ("finding IDs", "finding-ID assignment", "finding-ID prefix strings") so the acceptance criterion "no `F-29-` in any form" is literally satisfied.
  - Committed atomically as `94ab6cfe` via `git add -f` (`.planning/` is gitignored in this repo; prior planning commits follow the same `add -f` pattern — confirmed via `git show dae7f60b --stat`).

## Artifacts

- `.planning/phases/231-earlybird-jackpot-audit/231-02-AUDIT.md` — EBD-02 adversarial audit: 6-row Per-Function Verdict Table (all PASS), Findings-Candidate Block (no candidates), Scope-guard Deferrals (none), Downstream Hand-offs (Phase 233 JKP-03, Phase 235 CONS/RNG, Phase 236 FIND/REG), plus High-Risk Patterns Analyzed with four subsections. Commit `94ab6cfe`.
- `.planning/phases/231-earlybird-jackpot-audit/231-02-SUMMARY.md` — this file.

## Counts

| Metric | Value |
|---|---|
| Target functions in scope (from 230-01-DELTA-MAP.md §4 EBD-02) | 2 (`_runEarlyBirdLootboxJackpot` MODIFIED, `_rollWinningTraits` re-verification) |
| Verdict-table rows | 6 |
| PASS verdicts | 6 |
| FAIL verdicts | 0 |
| DEFER verdicts (open concerns) | 0 |
| DEFER hand-offs (scope boundaries documented in Findings-Candidate Block + Downstream Hand-offs prose) | 3 (Phase 233 JKP-03, Phase 235 CONS-01, Phase 235 RNG-01/02) |
| Attack vectors from CONTEXT.md D-08 EBD-02 covered | 4 / 4 |
| Owning commit SHAs cited | 20a951df (primary), 20a951df^ (pre-fix reference for Queue-Level Fix only) |
| Files referenced via contracts/*.sol File:Line anchors | 1 primary (`DegenerusGameJackpotModule.sol`) + 1 corroborating (`JackpotBucketLib.sol` for `getRandomTraits` / `unpackWinningTraits` shape evidence) + 1 caller (`DegenerusGameAdvanceModule.sol` for `rngWord` trace) |
| Finding IDs emitted | 0 |
| Out-of-scope deviations from scope-anchor rows | 0 |

## Attack Vector Coverage

All 4 EBD-02 attack vectors per `231-CONTEXT.md` D-08 are covered in the verdict table. Row-count per vector:

| Vector | Coverage | Verdict |
|---|---|---|
| (a) Bonus-trait parity with coin jackpot (same 4 traits from same VRF word via `_rollWinningTraits(rngWord, true)`) | 1 primary row on `_runEarlyBirdLootboxJackpot:677` + 1 structural row on `_runEarlyBirdLootboxJackpot:676-708` covering the 4×25 loop shape against `unpackWinningTraits` output | PASS at call-form level; DEFER cross-path identity to Phase 233 JKP-03 |
| (b) Salt-space isolation — `true` bonus branch keccak-separates from `false` main branch | 1 row on `_rollWinningTraits:1865-1875` (keccak-domain separator) + 1 row on `_runEarlyBirdLootboxJackpot:686` (winner-selection salt tuple survey across all `_randTraitTicket` callers) | PASS |
| (c) Fixed-level queueing at `lvl+1` — post-fix queues all winners at resolution level (was spread across `baseLevel..baseLevel+4`) | 1 row on `_runEarlyBirdLootboxJackpot:679, 691, 694, 697` quoting pre-fix vs post-fix expressions + caller-side `lvl + 1` trace at `payDailyJackpot:379` | PASS |
| (d) futurePool → nextPool budget conservation across the rewritten block | 1 row on `_runEarlyBirdLootboxJackpot:665-668, 711` (SSTORE ordering + `totalBudget` single-local conservation) | PASS (caller-side); DEFER Phase 235 CONS-01 for algebraic closure |

## Decisions Made

All decisions listed in `key-decisions` frontmatter above. Summary:
- All 6 verdict rows PASS — no FAILs, no open concerns.
- Salt-space isolation is cryptographically sound via `BONUS_TRAITS_TAG` compile-time keccak domain separator.
- The `lvl+1` queue fix is verified by direct pre-fix vs post-fix code-quote comparison.
- CEI ordering is preserved at the rewritten block; `totalBudget` is a single conserved local.
- Cross-path bonus-trait identity and algebraic pool conservation are documented hand-offs to Phase 233 JKP-03 and Phase 235 CONS-01 respectively, not open concerns.

## Deviations from Plan

None. Plan executed exactly as written. All acceptance criteria satisfied:
- File exists ✓
- All 4 required headers present (Per-Function Verdict Table / Findings-Candidate Block / Scope-guard Deferrals / Downstream Hand-offs) ✓
- Locked column header exact ✓
- 16 `20a951df` citations (requirement ≥ 5) ✓
- 14 `PASS|FAIL|DEFER` occurrences (requirement ≥ 5) ✓
- Both target functions have at least one row ✓
- `_runEarlyBirdLootboxJackpot` has ≥ 4 rows covering all 4 EBD-02 attack vectors ✓ (actually 5 rows — bonus parity, 4×25 structure, lvl+1 queue, pool CEI, winner-selection salt survey)
- `_rollWinningTraits` has ≥ 1 row covering salt-space isolation ✓
- Zero `F-29-` strings (including the composite `F-29-NN`) ✓
- Zero placeholder `:<line>` strings ✓
- Every verdict row uses exactly `PASS` (6 rows — no FAIL, no DEFER at row level) ✓
- Every File:Line anchor resolves into `contracts/` at HEAD ✓
- High-Risk Patterns Analyzed section has 4 subsections (Bonus-Trait Parity Invariant, Salt-Space Isolation, Queue-Level Fix, Pool Arithmetic Integrity) ✓
- Downstream Hand-offs explicitly names Phase 233 JKP-03 ✓ and Phase 235 CONS-01 ✓
- Queue-Level Fix subsection references both pre-fix (from `20a951df^`) and post-fix (HEAD) queue-index expressions ✓

One minor in-flight adjustment recorded for transparency (not a deviation; in-plan):
- Initial draft included three policy/hand-off prose sentences mentioning `F-29-NN` / `F-29-` as meta-references to explain the acceptance policy. All three rewritten to neutral "finding IDs" / "finding-ID assignment" / "finding-ID prefix strings" phrasing so the acceptance criterion "no `F-29-` in any form" is literally satisfied. No semantic loss.

## Issues Encountered

None. The rewrite is surgical, the pre-fix source was readily accessible via `git show 20a951df^:`, and the `BONUS_TRAITS_TAG` domain separator is a clean compile-time constant with no player-controllable surface.

## Known Stubs

None. The artifact is substantive: every verdict row has a real File:Line anchor pointing at HEAD source, every evidence cell cites concrete code semantics (keccak preimages, salt-space ranges, quadrant partitioning, SSTORE line numbers), and the four subsections in High-Risk Patterns Analyzed include verbatim code quotes of the pre-fix and post-fix expressions where semantic comparison is the evidence.

## Downstream Hand-offs

Emitted from 231-02-AUDIT.md § Downstream Hand-offs:

- **Phase 233 JKP-03** — Cross-path bonus-trait identity proof. The three bonus-branch consumers (earlybird at `contracts/modules/DegenerusGameJackpotModule.sol:677`, daily coin near-future at line 1679, purchase-phase main-equivalent at line 1705) must all produce the same 4-trait `uint32` packed output when fed the same VRF word on the same game day. Phase 231 EBD-02 verified the earlybird call is correctly formed and uses `bonus=true`; Phase 233 JKP-03 owns the end-to-end cross-path identity proof.
- **Phase 235 CONS-01** — Algebraic sum-before = sum-after proof for every pool-mutating SSTORE in the rewritten `_runEarlyBirdLootboxJackpot` block within the broader `payDailyJackpot` / `advanceGame` frame. Phase 231 verified CEI position (lines 668 and 711), `_setNextPrizePool` call integrity, and that no new SSTORE site was introduced. Phase 235 proves the delta closes across `futurePrizePool`, `nextPrizePool`, `currentPrizePool`, `claimablePool` simultaneously.
- **Phase 235 RNG-01** — Backward trace proving the VRF word consumed in `_runEarlyBirdLootboxJackpot._rollWinningTraits(rngWord, true)` was unknown at its input-commitment time (per `feedback_rng_backward_trace.md`). 20a951df adds no new RNG consumer (the same `rngWord` was already consumed by the pre-fix earlybird); Phase 235 RNG-01 owns the commitment-window proof.
- **Phase 235 RNG-02** — Enumeration of player-controllable state between VRF request and earlybird-path fulfillment (per `feedback_rng_commitment_window.md`). No candidate player-controllable variables surfaced during this audit; Phase 235 RNG-02 finalizes the enumeration.
- **Phase 236 FIND-01** — Zero FAIL verdicts and zero candidate-finding anchors emitted. If Phase 236 elects an INFO note describing the rewrite's surface narrowing (100 `_randTraitTicket` calls → 4; 200 entropy steps → 0), the Queue-Level Fix subsection of `231-02-AUDIT.md` is the canonical source anchor.
- **Phase 236 REG-01 / REG-02** — Prior-milestone findings tied to the pre-fix earlybird surface (per-winner entropy loop, 5-level spread, `levelPrices[5]` scratch array) must be re-checked against HEAD. Phase 231 flagged the surface narrowing but did not enumerate prior findings (out of scope per D-03). Phase 236 regression sweep owns the re-verification.

## Self-Check: PASSED

- `.planning/phases/231-earlybird-jackpot-audit/231-02-AUDIT.md` — FOUND (committed at `94ab6cfe`)
- `.planning/phases/231-earlybird-jackpot-audit/231-02-SUMMARY.md` — FOUND (this file)
- Task commit verified: `94ab6cfe` present in `git log --oneline` as top commit.
- Target commit `20a951df` cited 16 times in 231-02-AUDIT.md (requirement ≥ 5).
- Both target functions from 230-01-DELTA-MAP.md §4 EBD-02 row have ≥ 1 verdict row (`_runEarlyBirdLootboxJackpot` = 5 rows, `_rollWinningTraits` = 1 row).
- Zero `F-29-` strings in 231-02-AUDIT.md (per D-09).
- READ-only scope guard honored: no `contracts/` or `test/` writes in this plan (verified via `git diff --name-only HEAD~1 HEAD` showing only `.planning/phases/231-earlybird-jackpot-audit/231-02-AUDIT.md`).
- Cross-path bonus-trait identity explicitly handed off to Phase 233 JKP-03.
- Algebraic pool conservation explicitly handed off to Phase 235 CONS-01.

---
*Phase: 231-earlybird-jackpot-audit*
*Completed: 2026-04-17*
