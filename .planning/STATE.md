---
gsd_state_version: 1.0
milestone: v29.0
milestone_name: Post-v27 Contract Delta Audit
status: executing
stopped_at: Phase 231 complete (3/3 plans); parallel execution of 232/233/234 still open per ROADMAP
last_updated: "2026-04-17T22:25:00.000Z"
last_activity: 2026-04-17 -- Phase 231 Plan 03 complete (EBD-03 combined earlybird state-machine adversarial audit, 13 PASS verdicts across 4 paths × 4 attack vectors)
progress:
  total_phases: 7
  completed_phases: 2
  total_plans: 4
  completed_plans: 4
  percent: 70
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-17)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** v29.0 Post-v27 Contract Delta Audit — 7 phases (230-236) covering delta extraction, three adversarial themes (EBD / DCM / JKP), quests/boons/misc grab-bag, conservation + RNG re-proof, and regression + findings consolidation.

## Current Position

Phase: 231 complete (3/3 plans) → next: parallel 232/233/234 (ROADMAP waves) or sequential 232 (Decimator Audit)
Plan: 231-01 complete (EBD-01 AUDIT + SUMMARY shipped); 231-02 complete (EBD-02 AUDIT + SUMMARY shipped); 231-03 complete (EBD-03 AUDIT + SUMMARY shipped)
Milestone: v29.0 — Post-v27 Contract Delta Audit
Status: Executing
Last activity: 2026-04-17 -- Phase 231 Plan 03 complete (EBD-03 combined earlybird state-machine adversarial audit, 13 PASS verdicts across 4 paths × 4 attack vectors)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v29.0 roadmap]: 7 phases (230-236) chosen — modeled on v25.0 pattern (DELTA → adversarial → RNG/conservation → findings) scoped to the 8 v29.0 themes
- [v29.0 roadmap]: Three adversarial themes (EBD, DCM, JKP) each get their own phase — different modules, different attack surfaces
- [v29.0 roadmap]: QST requirements folded into a single grab-bag phase (234) with per-requirement sections — low coupling between the three isolated changes
- [v29.0 roadmap]: CONS + RNG combined into Phase 235 — both are analytical proofs over the full delta and share the same scope dependency on phases 231-234
- [v29.0 roadmap]: REG + FIND combined into Phase 236 (terminal) — regression check feeds directly into the consolidated deliverable
- [v29.0 roadmap]: Phase 230 is lightweight scope-map only (1 plan) — modeled on v25.0's 213-03 and v28.0's 224-01 catalog pattern
- [v29.0 roadmap]: Scope-guard handoff pattern (D-227-10 → D-228-09) carried forward — any phase that bloats defers to a later phase rather than over-scoping
- [v28.0]: Audit target is sibling `database/` repo — planning artifacts remain in `degenerus-audit/.planning/`
- [v28.0]: Three intent sources graded against: API.md prose, openapi.yaml spec, in-source comments
- [v28.0]: Four mismatch directions in scope — docs→code, code→docs, comment→code, schema↔migration
- [v28.0]: Three audit scopes in this milestone — API handlers, DB schema + migrations, indexer
- [v28.0]: Deliverable is `audit/FINDINGS-v28.0.md` in v27.0 consolidated-findings style
- [v28.0 roadmap]: API group split into two phases (224 route↔spec surface, 225 handler bodies + validation schemas) because the 5 API requirements cover meaningfully different audit surfaces
- [v28.0 roadmap]: IDX group split into two phases (227 event-processor correctness, 228 cursor/reorg/view-refresh state machines) because event routing and state-machine semantics are different skillsets of audit work
- [v28.0 roadmap]: SCHEMA group kept as one phase (226) covering all 4 SCHEMA requirements — surface is tractable and migration reconciliation naturally chains into comment/orphan checks
- [v28.0 roadmap]: FIND phase (229) last, depends on all upstream phases
- [v27.0]: Scope bounded to call-site integrity — storage layout (done v25.0), deployed bytecode (requires RPC infra), and revert specificity (debuggability) are explicitly out of scope
- [v27.0]: `is IDegenerusGame` compile-time inheritance not adopted — high mechanical cost (~57 `override` additions) against existing `check-interfaces` Makefile gate that catches the same class; reconsider only if the gate ever produces false negatives
- [Phase 220]: check-delegatecall gate operates on source text (no forge build prereq). Runs under 1s vs check-interfaces ~10s.
- [Phase 220]: CONTRACTS_DIR env var pattern established for future gates — scripts must support overriding target tree so negative tests run in /tmp without touching contracts/.
- [Phase 221]: Raw selector gate mirrors Phase 220 architecture (bash+awk, CONTRACTS_DIR override, PASS/FAIL stdout).
- [Phase 222]: 76 leverage-first integration tests in CoverageGap222.t.sol close 177 CRITICAL_GAPs via natural caller chains.
- [Phase 223]: v27.0 Call-Site Integrity Audit SHIPPED 2026-04-13 — all 14/14 CSI-NN requirements Complete, 16 INFO findings consolidated, 3 new KNOWN-ISSUES entries.
- [Phase 224]: API-01 + API-02 verified via 27/27/27 triple-alignment catalog (openapi.yaml, 8 route files, API.md) — zero functional drift; path-normalization rule `{name}` ≡ `:name` locked for Phase 225 to reuse; no gate shipped per D-224-01 (catalog-only).
- [Phase 225 Plan 01]: API-03 HTTP handler comment audit complete — 27/27 handlers audited in `database/src/api/routes/*.ts`; D-225-04 Tier A/B threshold applied; 4 F-28-225-NN finding stubs (01 Tier A on game.ts earliest-day `<> 'dgnrs'` predicate vs "any distributions" comment; 02-03 Tier B on game.ts roll1/roll2 undocumented 404 branches; 04 Tier B on replay.ts day/:day JSDoc omitting the winning-trait + same-tx filter). All INFO, direction comment->code, default resolution RESOLVED-DOC per D-225-02. Tier C count 19/27 (handlers without JSDoc) recorded as context only. D-225-01 scope exclusion respected: no file in `src/handlers/*.ts` was audited.
- [Phase 225]: Response-shape audit: 8 sampled + 19 expanded = 27/27 coverage; 9 F-28-225-NN stubs (5 INFO + 4 LOW); 58 occurrences of z.number() vs integer consolidated as F-28-225-05; 3 endpoints fully PASS on expansion using z.number().int() pattern
- [Phase 226]: 226-03: SCHEMA-02 zero-finding outcome (all 27 column-claims correct); F-28-226-201..299 block unused
- [Phase 226]: Plan 226-02 consumed F-28-226-01 (pre-assigned) plus F-28-226-09 (meta-chain break 0002->0003) and F-28-226-10 (quest_definitions.difficulty TS-vs-SQL drift); next available ID for Plan 226-03 is F-28-226-11.
- [Phase 227]: D-227-09 verdict depth verified across 95 events; 6 LOW silent-truncation findings emitted (F-28-227-101..106)
- [Phase 230]: 230-01-DELTA-MAP.md is the authoritative v29.0 audit-surface catalog — 581 lines, 5 top-level sections (Per-File Baseline / Function-Level Changelog / Cross-Module Interaction Map / Interface Drift Catalog / Consumer Index). Per D-06 it is READ-only after commit; downstream phases record scope-guard deferrals rather than editing it. All 4 automated gates (check-interfaces, check-delegatecall 44/44, check-raw-selectors, forge build) PASS at HEAD — no hidden drift. Phase 230 emitted ZERO F-29-NN finding IDs by design (scope catalog, not findings pass).
- [Phase 230]: 5 known non-issues documented in 230-01-SUMMARY.md for downstream consumer awareness — `boonPacked` auto-getter classified not-required (selector not on interface), 2 UNCHANGED reformat rows (§1.1), IM-09 call-unchanged-but-arithmetic-changed, delegatecall-site count bumped 43→44 (genuine growth since Phase 220), pre-existing `forge build` lint warnings.
- [Phase 230]: Delegatecall-site count at HEAD = 44 (was 43 at Phase 220 v27.0 baseline). The +1 site is genuine new surface from the 10-commit delta — phase 236 regression sweep must confirm it remains aligned.
- [Phase 231-01]: EBD-01 adversarial audit of `f20a2b5e` (earlybird purchase-phase finalize refactor) — ALL PASS. 21 verdict rows across 9 target functions (`_finalizeRngRequest`, `_finalizeEarlybird`, `_purchaseFor`, `_callTicketPurchase`, `_purchaseWhaleBundle`, `_purchaseLazyPass`, `_purchaseDeityPass`, `recordMint`, `_awardEarlybirdDgnrs`) covering all 7 EBD-01 attack vectors from CONTEXT.md D-08. Zero FAIL, zero DEFER at row level. Three DEFER hand-offs documented as scope boundaries (not findings): algebraic pool closure → Phase 235 CONS-01; RNG commitment → Phase 235 RNG-01/02 (N/A for EBD-01 — f20a2b5e adds no new RNG consumer); severity classification → Phase 236 FIND-01. Key evidence: unified `_awardEarlybirdDgnrs(buyer, ticketFreshEth + lootboxFreshEth)` fires exactly once per purchase at `DegenerusGameMintModule:1165`; signature contraction safe (storage body at `DegenerusGameStorage:1001-1044` contains zero `level()` substitute reads); `_finalizeEarlybird` one-shot idempotent via `earlybirdDgnrsPoolStart == type(uint256).max` sentinel flipped BEFORE the external `dgnrs.transferBetweenPools` call (CEI compliant); `recordMint` award-block removal is zero-regression (only production caller is `_callTicketPurchase:1276`, which now routes through `_purchaseFor:1165`). Net gas: strict improvement (one fewer external call per combined purchase).
- [Phase 231-02]: EBD-02 adversarial audit of `20a951df` (earlybird trait-alignment rewrite) — ALL PASS. 6 verdict rows across 2 target functions (`_runEarlyBirdLootboxJackpot` MODIFIED, `_rollWinningTraits` read-only re-verification) covering all 4 EBD-02 attack vectors from CONTEXT.md D-08. Zero FAIL, zero DEFER at row level. Three DEFER hand-offs documented as scope boundaries (not findings): cross-path bonus-trait identity → Phase 233 JKP-03; algebraic pool closure → Phase 235 CONS-01; RNG commitment → Phase 235 RNG-01/02. Key evidence: `_rollWinningTraits(rngWord, true)` call at `DegenerusGameJackpotModule:677` is byte-identical in arg order and salt flag to bonus consumers at lines 1679 and 1705; `BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS")` compile-time constant (line 171) is the cryptographic domain separator giving preimage-resistant isolation between `bonus=true` and `bonus=false` branches; `lvl+1` queue fix verified via direct pre-fix (`20a951df^`) vs post-fix code quote — pre-fix used `baseLevel + levelOffset` with `levelOffset = uint24(entropy % 5)` spreading winners across `baseLevel..baseLevel+4`, post-fix queues all winners at single argument `lvl` (caller passes `lvl + 1` at `payDailyJackpot:379`, matching DCM-01 `decimatorBurn` convention at §1.8). futurePool → nextPool CEI is trivially conserved: single `totalBudget` local debited from futurePool at line 668 and credited to nextPool at line 711 with no mutation in between. Rewrite narrows surface strictly: 100 `_randTraitTicket` calls → 4, 200 `EntropyLib.entropyStep` calls → 0, `levelPrices[5]` scratch array eliminated. Winner-selection salt spaces across the module are disjoint: earlybird [0,3], coin-near-future [252,255] via `DAILY_COIN_SALT_BASE = 252`, other callers [200,203].
- [Phase 231-03]: EBD-03 adversarial audit of the combined earlybird state machine spanning both in-scope commits (`f20a2b5e` purchase-phase finalize + `20a951df` jackpot-phase trait-alignment) — ALL PASS. 13 verdict rows across 4 paths × 4 attack vectors from CONTEXT.md D-08 EBD-03. Path A (Normal Level Progression) + Path B (Skip-Split / Phase-Transition) + Path C (Game-Over Before EBD-END) + Path D (Game-Over At-or-After EBD-END), each PASS on no-double-spend / no-orphaned-reserves / no-missed-emission / cross-commit-invariant where applicable. Zero FAIL, zero row-level DEFER. Three scope-boundary hand-offs documented (not findings): algebraic pool closure → Phase 235 CONS-01; phase-transition interaction → Phase 235 TRNX-01; orphaned-reserve characterization in dead-game terminal state → Phase 236 REG-01. Key clarification of the cross-commit invariant: `_finalizeEarlybird` moves DGNRS tokens in the external StakedDegenerusStonk contract (Pool.Earlybird → Pool.Lootbox) while `_runEarlyBirdLootboxJackpot` operates on ETH-side `futurePrizePool` in DegenerusGameStorage — the two sides use ORTHOGONAL storage namespaces; the EBD-03 invariant reduces to temporal + causal ordering (finalize fires at the `lvl==EARLYBIRD_END_LEVEL=3` RNG-request transition via `_finalizeRngRequest`, and `_runEarlyBirdLootboxJackpot` runs on the first jackpot-phase day of the FOLLOWING tx). Game-over path cleanly isolated from the hook: `_finalizeRngRequest` and `_finalizeEarlybird` appear only in `DegenerusGameAdvanceModule.sol` (grep-confirmed, never in `DegenerusGameGameOverModule.sol`); the inner `_gameOverEntropy:1206 → _tryRequestRng → _finalizeRngRequest` call reaches with `isTicketJackpotDay=false` per the `_handleGameOverPath` line 178 entry guard, skipping the level-increment + hook branch at line 1510. Phase-transition block (2471f8e7 packing context) cannot fire the hook either — `_finalizeRngRequest` is unreachable from inside the `phaseTransitionActive` branch at line 283. Sentinel dual role (`earlybirdDgnrsPoolStart` at `DegenerusGameStorage:978`): guards both `_finalizeEarlybird` double-dump (AdvanceModule:1583) AND post-finalize `_awardEarlybirdDgnrs` double-allocation (Storage:1011), flipped as FIRST state mutation inside `_finalizeEarlybird` (line 1584, pre-external-call CEI).

### Pending Todos

- _(none — orphan commit 2471f8e7 "phase transition fix" folded into v29.0 scope as TRNX-01 on Phase 235)_

### Blockers/Concerns

- v29.0 is a contract-side audit — audit target is `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/` (not the `database/` repo as in v28.0). Per-contract-locations feedback applies: only read from `contracts/` directory, stale copies exist elsewhere.
- v28.0 finalized the cross-repo READ-only audit pattern; v29.0 is same-repo READ-only — writes confined to `audit/` + `.planning/`, no `contracts/` or `test/` modifications without explicit user approval.

## Session Continuity

Last session: 2026-04-17 — Phase 231 Plan 03 executed end-to-end (EBD-03 combined earlybird state-machine adversarial audit shipped; AUDIT committed at `84440ef9`, SUMMARY + STATE/ROADMAP/REQUIREMENTS updates committed in metadata commit)
Stopped at: Phase 231 complete (3/3 plans — EBD-01/EBD-02/EBD-03 all shipped with all-PASS verdicts); parallel execution of 232/233/234 still open per ROADMAP
