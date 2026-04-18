---
phase: 231-earlybird-jackpot-audit
plan: 03
subsystem: audit
tags: [solidity, audit, adversarial, earlybird, state-machine, cross-commit-invariant, finalize-hook, sentinel-one-shot, path-walk, phase-transition, gameover-isolation, read-only]

# Dependency graph
requires:
  - phase: Phase 230 (230-01-DELTA-MAP.md)
    provides: §1.1 IM-05 / §1.2 / §1.9 / §2.1 / §2.3 IM-16 / §4 Consumer Index EBD-03 row — authoritative cross-commit scope anchor
  - phase: Phase 231 Plan 01 (231-01-AUDIT.md, dae7f60b)
    provides: Regression anchor for the purchase-phase finalize side (f20a2b5e) — 21 PASS verdicts across 9 target functions
  - phase: Phase 231 Plan 02 (231-02-AUDIT.md, 94ab6cfe)
    provides: Regression anchor for the jackpot-phase run side (20a951df) — 6 PASS verdicts across 2 target functions
provides:
  - 231-03-AUDIT.md — EBD-03 combined earlybird state-machine adversarial audit (end-to-end cross-commit path walk)
  - 13 PASS verdicts across 4 enumerated paths (Normal / Skip-Split / Game-Over Before EBD-END / Game-Over At-or-After EBD-END) × 4 attack vectors
  - Zero FAIL, zero row-level DEFER verdicts; three scope-boundary hand-offs documented (Phase 235 CONS-01 algebraic closure, Phase 235 TRNX-01 phase-transition interaction, Phase 236 REG-01 orphaned-reserve characterization)
  - Cross-commit invariant clarified: _finalizeEarlybird and _runEarlyBirdLootboxJackpot operate on ORTHOGONAL storage namespaces (DGNRS token pools in StakedDegenerusStonk vs ETH accumulators in DegenerusGameStorage); the EBD-03 invariant is temporal + causal, not a direct balance flow
affects: [Phase 235 CONS-01, Phase 235 TRNX-01, Phase 235 RNG-01, Phase 235 RNG-02, Phase 236 FIND-01, Phase 236 REG-01, Phase 236 REG-02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Numbered state-machine path-walk pattern (per CONTEXT.md D-01 + Claude's Discretion) — four paths enumerated with numbered hops and File:Line anchors at each hop; replaces the per-function table used in 231-01/231-02 because EBD-03 is a cross-function state-machine trace, not a per-function audit"
    - "Per-path × per-attack-vector verdict table — locked columns `Path | Attack Vector Considered | Verdict (PASS/FAIL/DEFER) | Evidence | Owning SHA` adapt the 231-01/231-02 auto-rule 4 column set for state-machine tracing"
    - "Fresh-read methodology (CONTEXT D-03) — 231-01 and 231-02 verdicts cited as regression anchors ONLY; every EBD-03 verdict independently established from HEAD source"
    - "Reachability proof by guard-enumeration — each path's hop list cites the ENTRY guard (line 178 _handleGameOverPath, line 283 phaseTransitionActive, line 1510 isTicketJackpotDay) proving the hook fires only in the intended frame, never in unintended frames"
    - "Scope-boundary hand-off pattern (CONTEXT D-06 + D-07) — concerns overlapping Phase 235 / Phase 236 territory recorded as Downstream Hand-offs rather than in-scope row-level DEFERs; keeps the verdict table clean at 13 PASS"
    - "No finding-ID prefix strings emitted (CONTEXT D-09) — Phase 236 FIND-01 owns severity classification and ID assignment"

key-files:
  created:
    - .planning/phases/231-earlybird-jackpot-audit/231-03-AUDIT.md
    - .planning/phases/231-earlybird-jackpot-audit/231-03-SUMMARY.md
  modified: []

key-decisions:
  - "All 13 verdict rows PASS across 4 paths × 4 attack vectors — the combined earlybird state machine is verified safe end-to-end. No FAIL verdicts, no row-level DEFERs, no open concerns for Phase 236 to classify."
  - "Cross-commit invariant clarified through source reading: _finalizeEarlybird dumps DGNRS tokens from IStakedDegenerusStonk.Pool.Earlybird into Pool.Lootbox (DGNRS-side accounting in the external StakedDegenerusStonk contract), while _runEarlyBirdLootboxJackpot reads and mutates futurePrizePool (ETH-side accounting in DegenerusGameStorage). The two operate on ORTHOGONAL storage namespaces — EBD-03's 'pool dumped == pool consumed' invariant is NOT a direct balance flow but a temporal + causal ordering: finalize must fire BEFORE the first jackpot-phase day, which is guaranteed by the state machine (finalize runs at RNG-request time on the lvl==EARLYBIRD_END_LEVEL transition; _runEarlyBirdLootboxJackpot runs on the first jackpot-phase day of the FOLLOWING tx, after jackpotPhaseFlag=true is set at advanceGame line 418 and _endPhase has not yet been reached)."
  - "Path A (Normal) PASS — _finalizeEarlybird at AdvanceModule:1582-1595 fires exactly once at the lvl==EARLYBIRD_END_LEVEL=3 transition. Sentinel flip at line 1584 (earlybirdDgnrsPoolStart = type(uint256).max) precedes the external dgnrs.transferBetweenPools call at lines 1589-1593 (CEI compliant). The dump transfers the FULL remaining pool (not a fraction) via `remainingPool = dgnrs.poolBalance(Pool.Earlybird)` at lines 1585-1587 → `dgnrs.transferBetweenPools(Earlybird, Lootbox, remainingPool)`. In-flight purchase-side _awardEarlybirdDgnrs calls that land AFTER the sentinel flip short-circuit at storage line 1011."
  - "Path B (Skip-Split) PASS — the advanceGame phase-transition block at lines 283-316 does NOT invoke _finalizeRngRequest from inside its body. If rngGate returns rngWord==1 (fresh request), the break at line 279 exits BEFORE phase-transition housekeeping runs. Even if _finalizeRngRequest were reached during a phase-transition frame, the guard at line 1510 `if (isTicketJackpotDay && !isRetry)` evaluates FALSE (lastPurchase=false since the jackpot phase just completed per line 420). The 2471f8e7 _unlockRng removal is orthogonal to the earlybird gate — _unlockRng only clears VRF state (rngLockedFlag, rngWordCurrent, vrfRequestId, rngRequestTime) + calls _unfreezePool, none of which touch earlybirdDgnrsPoolStart or the DGNRS pools."
  - "Path C (Game-Over Before EBD-END) PASS — _handleGameOverPath at AdvanceModule:501-553 is the ONLY game-over entry in advanceGame and delegates exclusively to GameOverModule.handleGameOverDrain / handleFinalSweep (grep-confirmed: _finalizeRngRequest and _finalizeEarlybird appear ONLY in AdvanceModule.sol). The inner _gameOverEntropy path can reach _tryRequestRng at line 1206 with isTicketJackpotDay=lastPurchaseDay=false (per the line 178 guard that only reaches _handleGameOverPath when `!inJackpot && !lastPurchase`), so the level-increment + hook branch at line 1510 is skipped. _finalizeEarlybird never fires at game-over-before-EBD-END — correctly skipped per the state machine's design."
  - "Path D (Game-Over At/After EBD-END) PASS — Path A already executed at the 2→3 transition (monotonic level progression makes lvl==EARLYBIRD_END_LEVEL a one-shot event), flipping the sentinel. Any subsequent game-over at lvl>=3 cannot re-fire the hook (sentinel guard at AdvanceModule:1583 short-circuits; _handleGameOverPath does not reach _finalizeEarlybird anyway). No double-dump possible even under adversarial sequencing."
  - "Sentinel one-shot semantics verified dual-role: earlybirdDgnrsPoolStart at DegenerusGameStorage:978 guards BOTH double-dump from _finalizeEarlybird (AdvanceModule:1583) AND post-finalize double-allocation from _awardEarlybirdDgnrs (DegenerusGameStorage:1011). Flipped as the FIRST state mutation inside _finalizeEarlybird (line 1584, before any external call), it creates a total ordering between finalize and in-flight purchase awards: either _awardEarlybirdDgnrs ran BEFORE the finalize (buyer gets DGNRS, reducing pool balance the finalize will dump) OR it ran AFTER (buyer gets zero DGNRS per sentinel guard — correct, pool moved). No race condition."
  - "Game-over path isolation proven via grep: `_finalizeRngRequest` and `_finalizeEarlybird` appear only in DegenerusGameAdvanceModule.sol (never in DegenerusGameGameOverModule.sol). The game-over delegate target therefore has no path into the earlybird hook even if triggered concurrently with a pending RNG request. This extends the 231-01 Reachability proof (monotonic level progression makes lvl==EARLYBIRD_END_LEVEL a one-shot event) with an orthogonal-call-graph proof (gameover delegate and earlybird hook share zero call sites)."
  - "The orphaned-reserve question for Path C (dead-game terminal state trapped DGNRS) is classified as a SCOPE-BOUNDARY characterization question, not a row-level DEFER. The f20a2b5e refactor does NOT widen the pre-existing surface (pre-f20a2b5e code finalized inside _awardEarlybirdDgnrs, which also would not fire in a dead game). Whether the pre-existing trapped-DGNRS property is a novel concern vs design intent is Phase 236 REG-01's territory (regression sweep against v25.0/v26.0/v27.0). Phase 231 cannot re-prove prior-milestone findings per D-03."

patterns-established:
  - "Cross-commit state-machine audit pattern (EBD-03) — numbered path-walk over every reachable advanceGame transition (Normal / Skip-Split / Game-Over Before / Game-Over At-or-After) + per-path × per-attack-vector verdict table. Reusable for any future plan where an audit target spans multiple commits with a temporal handoff between them"
  - "Cross-commit invariant clarification pattern — when two commits appear to share a 'pool' at the English-language level, read the code to confirm whether they share a STORAGE NAMESPACE. For EBD-03 the two commits operate on orthogonal namespaces (DGNRS tokens in StakedDegenerusStonk vs ETH accumulators in DegenerusGameStorage); the invariant reduces to temporal + causal ordering, not direct balance flow. Documented explicitly in the Cross-Commit Invariant High-Risk Pattern subsection"
  - "Scope-boundary hand-off vs row-level DEFER distinction (CONTEXT D-06/D-07) — characterization questions that require cross-phase context (e.g., pre-existing vs delta-introduced) are documented as Downstream Hand-offs to the owning regression phase, NOT as row-level DEFER verdicts that would muddy the Per-Path Verdict Block. Path C's orphaned-reserve question is the canonical example: the row-level verdict is PASS (f20a2b5e does not widen the surface), the characterization hand-off is a scope-boundary deferral to Phase 236 REG-01"
  - "Guard-enumeration proof pattern — each path's hop list cites the ENTRY guard (`if (isTicketJackpotDay && !isRetry)` at line 1510, `if (lvl == EARLYBIRD_END_LEVEL)` at line 1518, `if (phaseTransitionActive)` at line 283, `_handleGameOverPath` at line 178) so reviewers can see at a glance why the hook fires only in the intended frame. Reusable for any state-machine audit where the correctness claim is 'X happens exactly once in frame F and never elsewhere'"

requirements-completed:
  - EBD-03

# Metrics
duration: 8min
completed: 2026-04-17
---

# Phase 231-03 Summary

EBD-03 Adversarial Audit — Combined Earlybird State Machine (`f20a2b5e` + `20a951df`)

**The combined earlybird state machine is PASS on every attack vector across every reachable transition path in `advanceGame`. The `_finalizeEarlybird` hook fires exactly once at the `lvl == EARLYBIRD_END_LEVEL` transition via `_finalizeRngRequest`, with the sentinel flip preceding the external DGNRS transfer (CEI compliant). The game-over path is cleanly isolated from the hook (orthogonal call graph). The phase-transition path (relevant to the 2471f8e7 `_unlockRng` removal) cannot fire the hook because the `isTicketJackpotDay` guard at line 1510 evaluates false in every non-purchase-phase frame. The cross-commit invariant between the purchase-phase finalize and the jackpot-phase run is clarified: the two sides operate on ORTHOGONAL storage namespaces (DGNRS tokens vs ETH accumulators) — the invariant is temporal + causal (finalize fires in the tx PRECEDING the first jackpot-phase day), not a direct balance flow. 13 PASS verdict rows, zero FAIL, zero row-level DEFER. Three scope-boundary hand-offs documented: algebraic pool closure to Phase 235 CONS-01, phase-transition interaction to Phase 235 TRNX-01, orphaned-reserve characterization in dead-game terminal state to Phase 236 REG-01.**

## Goal

Produce `231-03-AUDIT.md` — a numbered state-machine path walk over every reachable transition in `DegenerusGameAdvanceModule.advanceGame` (normal / skip-split / gameover before EBD-END / gameover at-or-after EBD-END), with a Per-Path Verdict Block covering all 4 EBD-03 attack vectors from `231-CONTEXT.md` D-08 (no double-spend, no orphaned reserves, no missed emissions, cross-commit invariant). READ-only audit: no writes to `contracts/` or `test/`. No finding IDs emitted per D-09.

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-17T22:13:45Z
- **Completed:** 2026-04-17T22:21:35Z
- **Tasks:** 1
- **Files created:** 2 (231-03-AUDIT.md, 231-03-SUMMARY.md)
- **Lines of audit:** 190 (231-03-AUDIT.md)

## Accomplishments

- **13-row per-path × per-attack-vector verdict table** with all PASS verdicts (4 rows Path A, 2 rows Path B, 3 rows Path C, 3 rows Path D, covering double-spend / orphaned-reserves / missed-emission / cross-commit-invariant across the 4 paths)
- **4/4 enumerated paths** covered with numbered hops (Normal / Skip-Split / Game-Over Before EBD-END / Game-Over At-or-After EBD-END) per CONTEXT.md D-08 and ROADMAP Success Criteria
- **4/4 EBD-03 attack vectors** from CONTEXT.md D-08 exercised against every path
- **Cross-Commit Invariant subsection** clarifies that `_finalizeEarlybird` and `_runEarlyBirdLootboxJackpot` operate on orthogonal storage namespaces (DGNRS tokens in StakedDegenerusStonk vs ETH accumulators in DegenerusGameStorage); the EBD-03 invariant reduces to temporal + causal ordering, not direct balance flow
- **Sentinel One-Shot Semantics subsection** documents the dual role of `earlybirdDgnrsPoolStart` — one sentinel guards both `_finalizeEarlybird` double-dump AND `_awardEarlybirdDgnrs` post-finalize double-allocation, forming a total ordering between finalize and in-flight purchase awards
- **Phase-Transition Interaction subsection** records the 2471f8e7 / `_unlockRng`-removal analysis: the earlybird hook placement is unchanged by 2471f8e7 because `_unlockRng` only clears VRF state and does not touch earlybird state; the phase-transition block cannot reach `_finalizeRngRequest` with `isTicketJackpotDay=true`
- **Game-over path isolation proven orthogonally via grep** — `_finalizeRngRequest` and `_finalizeEarlybird` appear only in `DegenerusGameAdvanceModule.sol`; the game-over delegate target (`DegenerusGameGameOverModule.sol`) has no path into the earlybird hook
- **`_tryRequestRng` inside `_gameOverEntropy`** trace — discovered during the fresh-read pass that `_gameOverEntropy:1206` can call `_tryRequestRng`, which reaches `_finalizeRngRequest`. However, `isTicketJackpotDay = lastPurchaseDay = false` per the `_handleGameOverPath` line 178 entry guard, so the level-increment + hook branch at line 1510 is skipped. The path is harmless despite the surface appearance.
- **Three scope-boundary hand-offs** documented as Downstream Hand-offs rather than row-level DEFERs — keeps the verdict table clean at 13 PASS. Phase 235 CONS-01 (algebraic pool closure), Phase 235 TRNX-01 (phase-transition interaction), Phase 236 REG-01 (orphaned-reserve characterization)
- **21 File:Line anchors** across three contract files (`DegenerusGameAdvanceModule.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameStorage.sol`), no placeholders, all read from `contracts/` at HEAD (commit `84440ef9`)
- **Zero finding-ID prefix strings** emitted per D-09
- **231-01 and 231-02 regression-anchor discipline** — 9 explicit "regression anchor" citations; no prior-verdict reuse as pre-approval

## Deviations from Plan

None — plan executed exactly as written. No Rule 1/2/3 auto-fixes required. No Rule 4 architectural decisions encountered. The fresh-read surfaced one subtlety (`_tryRequestRng` reachable from `_gameOverEntropy`) that initially looked like it might fire the hook during game-over, but the `isTicketJackpotDay=false` guard at line 1510 proved the hook remains unreachable on that path. Documented explicitly in Path C hop 4.

## Self-Check: PASSED

- `231-03-AUDIT.md` exists at `.planning/phases/231-earlybird-jackpot-audit/231-03-AUDIT.md` (42.8K, 190 lines)
- Required headers present: `## State-Machine Path Walk`, `## Per-Path Verdict Block`, `## Findings-Candidate Block`, `## Scope-guard Deferrals`, `## Downstream Hand-offs`
- State-Machine Path Walk contains 4 enumerated paths: `### Path A: Normal Level Progression`, `### Path B: Skip-Split / Phase-Transition`, `### Path C: Game-Over Before EARLYBIRD_END_LEVEL`, `### Path D: Game-Over At Or After EARLYBIRD_END_LEVEL`
- Per-Path Verdict Block header row is exactly `| Path | Attack Vector Considered | Verdict (PASS/FAIL/DEFER) | Evidence | Owning SHA |`
- 13 verdict rows total, every row cites at least one of `f20a2b5e` or `20a951df` (cross-commit-invariant rows cite both); every verdict is exactly `PASS`, `FAIL`, or `DEFER` (all PASS in this audit)
- At least one row covers each of the 4 EBD-03 attack vectors (double-spend: 4 rows, orphaned-reserves: 2 rows, missed-emission: 4 rows, cross-commit-invariant: 3 rows)
- `grep -c "PASS\|FAIL\|DEFER"` returns 23 ≥ 8 (required threshold)
- `grep -c "f20a2b5e\|20a951df"` returns 18 ≥ 8 (required threshold)
- Strings `F-29-NN` and `F-29-` do NOT appear anywhere in the file
- Every File:Line anchor resolves into `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`, or `contracts/storage/DegenerusGameStorage.sol` at HEAD (external-contract references named in prose, no File:Line anchors outside those three files)
- No placeholder line numbers (`:<line>`) remain
- 231-01 and 231-02 referenced as regression anchors (9 explicit citations), not pre-approval — every EBD-03 verdict independently established
- High-Risk Patterns Analyzed contains 3 subsections: Cross-Commit Invariant, Sentinel One-Shot Semantics, Phase-Transition Interaction
- Downstream Hand-offs explicitly names Phase 235 CONS-01 and Phase 235 TRNX-01
- Commit `84440ef9` contains the AUDIT file
- No contract source content read from outside `contracts/` directory per `feedback_contract_locations.md`
- No modifications to `contracts/` or `test/` per v29.0 READ-only audit rule and `feedback_no_contract_commits.md`

## Links to Follow-ups

- **Phase 235 CONS-01** — algebraic sum-before = sum-after proof across the combined (`_finalizeEarlybird` dump → `_consolidatePoolsAndRewardJackpots` → `_runEarlyBirdLootboxJackpot` debit/credit) pipeline spanning DGNRS-pool and ETH-pool accounting
- **Phase 235 TRNX-01** — complete `_unlockRng`-removal reasoning across all surfaces (FF drain timing, decimator-window gate, quest-progress hooks, etc.); EBD-03 verified the earlybird hook is unaffected by the removal
- **Phase 235 RNG-01 / RNG-02** — backward-trace that `rngWord` consumed in `_runEarlyBirdLootboxJackpot._rollWinningTraits(rngWord, true)` was unknown at its input-commitment time (RNG-01), and enumeration of player-controllable state between VRF request and earlybird consumer fulfillment (RNG-02)
- **Phase 236 REG-01** — regression cross-check that the Path C "unallocated Earlybird DGNRS pool in dead-game terminal state" is pre-existing behavior rather than a delta-introduced concern
- **Phase 236 FIND-01** — severity classification. EBD-03 emitted 0 FAIL and 0 row-level DEFER verdicts; nothing to classify from this plan.

## Decisions Made

- **Verdict-table row structure:** 13 rows (4 × Path A, 2 × Path B, 3 × Path C, 3 × Path D) because the minimum attack-vector coverage varies by path — Path A exercises all 4 vectors, Path B exercises only double-spend + missed-emission (orphaned-reserves not applicable in phase-transition frames, cross-commit-invariant folded into missed-emission since no hook fires), Paths C/D exercise all except orphaned-reserves-as-its-own-row (folded into the missed-emission row via the "unallocated pool may persist — pre-existing behavior" evidence)
- **Path C orphaned-reserve question as scope-boundary hand-off, not row-level DEFER:** the table verdict is PASS (f20a2b5e does not widen the pre-existing surface), and the characterization question is a Findings-Candidate hand-off to Phase 236 REG-01 (regression sweep). This keeps the verdict table at 13 PASS while honoring the pre-existing-vs-delta-introduced distinction
- **Narrated `_tryRequestRng`-in-gameover discovery explicitly:** during the fresh-read pass, `_gameOverEntropy:1206` was found to call `_tryRequestRng`, which reaches `_finalizeRngRequest`. Documented as Path C hop 4 with the guard at line 1510 shown as the gate. Surfacing the subtlety rather than burying it improves audit trust

## Known Stubs

None. All prose resolves to concrete File:Line anchors or explicitly-labeled scope-boundary hand-offs.

## Threat Flags

None. EBD-03's surface is entirely covered by the Phase 230 delta map anchors (§1.1 IM-05 + §1.2 + §1.9 + §2.1 + §2.3 IM-16 + §4 EBD-03). No new trust boundaries introduced; no new network endpoints; no new auth paths; no new file access patterns. The only new surface is the sentinel flip, which is a defense-in-depth guard that narrows existing behavior.
