# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.1 — VRF Governance Audit + Doc Sync

**Shipped:** 2026-03-18
**Phases:** 2 | **Plans:** 12

### What Was Built
- 2,339-line governance verdicts file covering 26 security requirements
- 6 war-game scenario assessments with exploit feasibility and severity ratings
- M-02 closure: emergencyRecover fully eliminated, severity downgraded Medium→Low
- All audit docs synchronized for governance: findings report, known issues, function audits, parameter reference, RNG docs, historical annotations
- Post-audit code hardening: CEI fix, death clock simplification, state variable removal

### What Worked
- Phase 24→25 dependency chain (audit before doc sync) prevented stale finding IDs
- Adversarial persona protocol (CP-01) caught the _executeSwap CEI violation and uint8 overflow
- 3-source requirements cross-reference (VERIFICATION + SUMMARY + traceability) caught zero gaps across 33 requirements
- Post-audit code review with the user identified unnecessary complexity (death clock pause) that the formal audit accepted as correct

### What Was Inefficient
- VALIDATION.md files created for all 7 phases but never filled out (Nyquist validation gap)
- activeProposalCount was designed, implemented, audited, documented, and then removed — could have been caught during design review

### Patterns Established
- Post-audit hardening pass: review known issues with the user to decide which are worth fixing vs. accepting
- "Meteor-level paranoia" filter: if an attack requires multiple independent black swans, remove the defensive code rather than adding more complexity to protect it

### Key Lessons
1. Audit scope should include a "simplification pass" — code that exists only to defend against implausible scenarios adds attack surface
2. The user's intuition about unnecessary complexity was more valuable than the formal audit's acceptance of the mechanism as correct
3. Documentation-heavy milestones benefit from tiered doc sync (Tier 1 critical → Tier 3 historical) to parallelize work

---

## Milestone: v3.1 — Pre-Audit Polish — Comment Correctness + Intent Verification

**Shipped:** 2026-03-19
**Phases:** 7 | **Plans:** 16

### What Was Built
- Full comment audit across all 29 protocol contracts (~25,000 lines of Solidity)
- 84 findings (80 CMT + 4 DRIFT) with what/where/why/suggestion per item
- 5 cross-cutting pattern analysis (orphaned NatSpec, coinflip split refs, post-Phase-29 gaps, onlyCoin naming, error reuse)
- Consolidated findings deliverable with severity index and master summary table
- Independent verification of 4 post-Phase-29 code changes

### What Worked
- Batch-by-contract-group structure (5 audit phases + 1 consolidation) scaled well across 29 contracts
- CMT/DRIFT sequential numbering across phases prevented ID collisions despite concurrent plan execution
- "Flag-only, no auto-fix" constraint kept scope tight and delivered a clean findings list
- Second-pass audit (after v3.0 Phase 29) found 84 additional issues the first pass missed — validates multi-pass approach
- Pre-identified issues from research phase gave each plan a checklist to verify, reducing false negatives

### What Was Inefficient
- Phase 36 was not formally verified (no VERIFICATION.md), requiring Phase 37 gap closure — should auto-verify consolidation phases
- REQUIREMENTS.md traceability fell behind during Phase 35 execution (still showed "In Progress" after completion)
- Executive summary contract count (23 vs 29) was stale from before Phase 35 scope expansion — manual header metrics are fragile
- Phase 35 CMT numbering offset (CMT-072 instead of expected CMT-059) due to concurrent plan execution claiming IDs — not a bug but surprised the integration checker

### Patterns Established
- Per-batch findings file per phase → consolidated deliverable pattern works well for audit milestones
- Post-Phase-29 code change verification: each batch audit independently verifies recent commits that touched its contracts
- 6-field finding format (What/Where/Why/Suggestion/Category/Severity) provides consistent warden-consumable output

### Key Lessons
1. Consolidation phases need VERIFICATION.md too — don't skip verification just because the phase is "just merging"
2. Keep header metrics (counts, summaries) derived from the data rather than manually written — they drift
3. Multi-pass comment audits are valuable — 84 findings after a "thorough" first pass proves no single pass catches everything
4. Concurrent plan execution needs explicit CMT ID reservation to prevent numbering surprises

---

## Milestone: v3.3 — Gambling Burn Audit + Full Adversarial Sweep

**Shipped:** 2026-03-21
**Phases:** 6 | **Plans:** 15

### What Was Built
- Delta audit of gambling burn / sDGNRS redemption system: 3 HIGH + 1 MEDIUM confirmed and fixed (CP-08, CP-06, Seam-1, CP-07)
- 7 Foundry invariant tests for redemption system (solvency, double-claim, supply, cap, roll bounds, aggregate tracking)
- 29-contract adversarial sweep: 0 new HIGH/MEDIUM, 13 composability sequences SAFE, 4 access control gates CORRECT
- Economic analysis: ETH EV=100% (fair), BURNIE EV=0.98425x (1.575% house edge), bank-run solvency proven
- Gas baseline for 7 redemption functions, 3 storage packing opportunities documented
- 12 audit docs updated with gambling burn findings, PAY-16 payout path, error renames, VRF bit allocation map

### What Worked
- Research phase spawned 4 parallel researchers that identified 3 HIGH findings from code analysis before any execution began — these were all confirmed in Phase 44, saving significant time
- Phase ordering (delta → invariants → adversarial → gas → docs) ensured each phase built on verified foundations — no rework needed
- Invariant test suite caught the fix correctness immediately — all 7 invariants passed on first run after applying Phase 44 fixes
- Milestone audit + gap closure (Phase 49) caught documentation staleness that would have been visible to C4A wardens (stale line numbers in audit docs)

### What Was Inefficient
- Phase 47 gas analysis was written before Phase 45 code fixes finalized, causing 60+ stale line references that Phase 49 had to correct
- 4 of 5 phases had PARTIAL Nyquist compliance — VALIDATION.md files were created but not filled out during execution
- SUMMARY.md frontmatter for Phase 48 Plan 01 had empty requirements_completed — caught by milestone audit but shouldn't have shipped empty

### Patterns Established
- Research-flagged findings → delta audit confirmation → invariant test encoding → adversarial verification pipeline is highly effective for new feature audits
- Split-claim design pattern for coinflip-dependent payouts (ETH immediate, BURNIE deferred) — useful for any future RNG-dependent two-stage payout
- Ghost variable tracking in Foundry handlers enables invariant testing of cross-transaction accounting properties

### Key Lessons
1. Run gas analysis AFTER code fixes are finalized, not in parallel — avoids the line reference staleness problem
2. Research phase findings from code analysis are remarkably accurate (4/5 confirmed) — worth the investment for new feature audits
3. Milestone audit → gap closure → re-audit cycle is lightweight and catches real documentation quality issues
4. Economic fairness proofs (EV-neutral, contraction mapping solvency) are the strongest defense against game-theoretic C4A findings

### Cost Observations
- Model mix: ~80% opus (research, planning, execution), ~20% sonnet (synthesis, integration checks)
- 46 commits across 2 days
- Notable: 4 parallel research agents + 1 synthesizer in ~10 minutes produced findings that held through the entire milestone

---

## Milestone: v3.7 — VRF Path Audit

**Shipped:** 2026-03-22
**Phases:** 5 | **Plans:** 10

### What Was Built
- VRF callback revert-safety proof with gas budget analysis (300k limit, 28-47k actual)
- Complete lootbox RNG lifecycle trace: index-to-word 1:1 mapping across all 5 mutation/fulfillment paths
- VRF stall edge case audit: gap backfill entropy, coordinator swap state, zero-seed, gameover fallback
- 77-test suite: 22 VRF core + 21 lootbox + 17 stall + 13 invariant/parametric + 4 Halmos symbolic proofs
- 7 INFO findings documented (V37-001 through V37-007), 0 HIGH/MEDIUM/LOW
- V37-003 zero guard fix applied to contract code

### What Worked
- Phase dependency chain (core → lootbox → stall → tests → verification) built naturally — each phase reused test infrastructure from the previous
- Halmos symbolic verification of redemption roll formula proved [25,175] bounds for all 2^256 inputs — strongest possible guarantee for a numeric invariant
- Milestone audit → gap closure (Phase 67) → re-audit cycle caught V37-001 open status and missing Phase 66 cross-references before archival
- Parallel plan execution within phases (test suite + findings doc) reduced wall-clock time without coordination overhead

### What Was Inefficient
- Phase 67 Plans 01/02 showed as incomplete in ROADMAP.md despite having SUMMARY.md files — ROADMAP.md plan checkboxes weren't updated during execution
- Phases 63-66 had PARTIAL Nyquist compliance — VALIDATION.md files created but not filled out (recurring pattern from v3.3)
- Phase 66 SUMMARY frontmatter referenced Phase 63 by wrong slug and Phase 62 (deleted) — planning metadata quality drifts when phases are renumbered

### Patterns Established
- VRFHandler test helper pattern: reusable MockVRFCoordinator + DeployProtocol + storage slot verification across all VRF test files
- Invariant handler with ghost variables for stateful property testing of multi-step VRF lifecycle (7 actions, 9 ghost vars)
- Halmos for arithmetic invariants: isolate pure formula in standalone contract, prove with symbolic execution — avoids importing full contract state

### Key Lessons
1. ROADMAP.md plan checkboxes need updating during plan completion, not just SUMMARY.md — the archival process reads both
2. Nyquist VALIDATION.md remains consistently unfilled across milestones — either automate it or drop the requirement
3. Ghost variable invariant testing is the most effective way to prove cross-transaction accounting properties in Foundry
4. Single-day milestones (26 commits in ~4 hours) are viable when phases build naturally on each other's test infrastructure

---

## Milestone: v3.9 — Far-Future Ticket Fix

**Shipped:** 2026-03-23
**Phases:** 7 | **Plans:** 8

### What Was Built
- Third key space (TICKET_FAR_FUTURE_BIT = 1 << 22) with fuzz-proven three-way collision-freedom
- Central routing fix in _queueTickets/_queueTicketsScaled covering all 6 ticket sources (lootbox, whale, vault, endgame, decimator, jackpot auto-rebuy)
- Dual-queue drain in processFutureTicketBatch with FF-bit cursor encoding for seamless read-side → far-future transition
- Combined pool jackpot selection eliminating TQ-01 (MEDIUM) — _tqWriteKey fully removed from _awardFarFutureCoinJackpot
- RNG commitment window proof: 12 mutation paths all SAFE, combined pool length invariant proven
- 35 Foundry tests including 23-contract integration test proving zero FF ticket stranding across 9 levels

### What Worked
- TDD approach (failing test → implementation → green) across Phases 74-77 caught boundary issues early (e.g., FF-bit stripping in _prepareFutureTickets)
- Combined pool approach (Phase 77) superseded the simple TQ-01 one-line fix with a structurally superior design that reads from both correct pools
- Phase 78 proved both edge cases SAFE with zero code changes — the Phase 74-76 implementation inherently handled EDGE-01/EDGE-02
- Reusing v3.8 backward-trace methodology for Phase 79 RNG proof kept analysis consistent and trustworthy
- Integration test (Phase 80) deploying all 23 contracts via DeployProtocol provided strongest end-to-end confidence

### What Was Inefficient
- ROADMAP.md progress table had stale data (Phase 79 showed "Not started", Phase 78 showed "0/1 plans") despite both being complete — recurring ROADMAP staleness pattern
- 3 SUMMARY files missing requirements-completed frontmatter — caught by milestone audit but shouldn't ship incomplete
- Phase 79 had no formal PLAN.md (showed "TBD") since it was a proof/analysis phase — the workflow assumes all phases have plans

### Patterns Established
- Bit-reservation pattern for storage key spaces: dedicate high bits for new key categories, validate collision-freedom with fuzz tests
- phaseTransitionActive exemption pattern: guards that block permissionless callers can exempt privileged flows via existing protocol state flags
- Combined pool selection pattern: when multiple storage locations hold eligible items, read all pools and index over the combined length rather than trying to merge them

### Key Lessons
1. "Zero code changes needed" is the best Phase 78 outcome — proving safety from existing implementation is cheaper and more reliable than adding defensive code
2. Single-day milestones with strong dependency chains (74→75→76→77→78→79→80) execute efficiently when each phase reuses the previous phase's test infrastructure
3. Integration tests that deploy the full protocol stack are expensive but catch real issues (e.g., constructor pre-queuing behavior) that unit tests with mocks miss
4. Combined pool approach is structurally superior to patching individual reads — eliminates the class of bug rather than the instance

### Cost Observations
- Model mix: ~90% opus (all planning + execution), ~10% sonnet (integration checks)
- 82 commits in ~10 hours
- Notable: 7 phases from bug discovery (TQ-01) to fully proven fix in a single session

---

## Milestone: v4.1 — Ticket Lifecycle Integration Tests

**Shipped:** 2026-03-24
**Phases:** 3 | **Plans:** 4

### What Was Built
- 24 Foundry integration tests deploying full 23-contract protocol via DeployProtocol
- All 6 ticket sources (direct purchase x3, lootbox near/far, whale bundle) verified end-to-end with storage-level inspection
- Edge case coverage: boundary routing (L+5 write vs L+6 FF), FF drain timing (phaseTransitionActive only), jackpot read-slot pipeline, last-day routing override
- Zero-stranding sweep helper checking both buffer sides + FF keys across all processed levels
- Formal RNG commitment window proof: 9/9 permissionless paths SAFE, traitBurnTicket 0 permissionless writers
- 4 rngLocked guard tests verifying FF key write blocking and double-buffer write-slot isolation
- 1 contract bug fix: requestLootboxRng blocked during mid-day ticket processing

### What Worked
- v3.9's DeployProtocol + vm.store/vm.load pattern scaled perfectly — all v4.1 tests reused the same infrastructure
- Phase ordering (scaffold → edge cases → RNG proofs) minimized rework: each phase extended the single accumulating test file
- "ticketsOwed over queue length" decision (Phase 92) propagated cleanly through Phases 93-94, avoiding the vault-perpetual false assertion trap
- buyer3 isolation pattern eliminated _driveToLevel contamination in all lootbox/whale tests
- try/catch pattern for lootbox RNG-03b test elegantly handled the non-deterministic near/far roll outcome

### What Was Inefficient
- 92-VERIFICATION.md was stale (showed gaps_found pre-fix) — autonomous execution didn't re-run verification after SRC-05 fix
- 7 auto-fixed bugs across 4 plans: plan-sketched assertions consistently needed adjustment for actual storage semantics (queue length vs ticketsOwed, writeSlot toggle parity, slot/offset misalignment)

### Patterns Established
- Accumulating single test file pattern: all phases contribute to one TicketLifecycle.t.sol rather than separate files per phase
- _assertZeroStranding sweep: checks both buffer sides (plain + SLOT_BIT) to handle writeSlot toggle parity
- Analytical proof + Foundry test pattern: formal path enumeration for structural properties (RNG-01/02), integration tests for behavioral properties (RNG-03/04)

### Key Lessons
1. Plan-sketched test assertions are consistently wrong about storage semantics — the auto-fix pipeline (Rule 1) handles this well, but planning should note "assertion approach TBD pending actual storage behavior"
2. Single accumulating test file works better than per-phase files for integration suites where later tests reuse earlier helpers
3. Autonomous execution should re-run verification after auto-fixes — the stale 92-VERIFICATION.md was caught by milestone audit but shouldn't have shipped
4. vm.store slot manipulation patterns (bit shifts for slot 0/slot 1 packed fields) are reusable infrastructure worth documenting in helper functions rather than inline constants

### Cost Observations
- Model mix: ~90% opus (all phases), ~10% sonnet (integration checks)
- 16 commits in ~3 hours
- Notable: 24 integration tests from zero in a single session, building on v3.9 infrastructure

---

## Milestone: v7.0 — Delta Adversarial Audit (v6.0 Changes)

**Shipped:** 2026-03-26
**Phases:** 4 | **Plans:** 11

### What Was Built
- Delta extraction: 17 changed files, 65 function catalog entries across 12 production contracts, 23/29 plan items MATCH with 5 DRIFT flagged
- DegenerusCharity full adversarial audit: 17 functions across 3 domains (token ops, governance, game hooks), 0 VULNERABLE, GOV-01 finding led to onlyGame guard fix
- Changed contract audit: 48 functions across 11 contracts, formatting-only triage fast-tracked 17/18 DegeneretteModule changes, 5 cross-contract seams analyzed
- Consolidated: 3 FIXED (GOV-01 permissionless resolveLevel, GH-01/GH-02 burnAtGameOver reorder), 4 INFO, 0 open actionable findings
- All 11 changed contract storage layouts verified via forge inspect

### What Worked
- Plan-vs-reality reconciliation (Phase 126) caught the unplanned DegenerusAffiliate change and 5 DRIFT items that needed explicit audit attention
- Formatting-only triage in Phase 128 Plan 02 correctly fast-tracked 17/18 DegeneretteModule functions, focusing audit time on the 1 logic change
- Cross-contract integration seam analysis (Phase 128 Plan 05) validated 5 seams across module boundaries — fund split, level transition, gameover drain, storage read-through, event emission
- Delta audit methodology (extract → reconcile → per-phase audit → consolidated) executed in a single session with zero rework

### What Was Inefficient
- REQUIREMENTS.md traceability table was never updated during execution — all 20 requirements stayed "Pending" despite being satisfied
- ROADMAP.md plan checkboxes for Phases 127-129 showed unchecked despite summaries existing (recurring pattern from v3.7+)
- Some SUMMARY.md one-liners were malformed (contained "PART A -- Game Hook Analysis:", "Commit:", "Seam 1 --" fragments) — summary-extract tool needs better parsing of multi-section summaries

### Patterns Established
- Formatting-only triage: when a large batch of functions changed, classify formatting-only vs logic changes first to focus audit time
- Plan-vs-reality reconciliation as Phase 1: establishes audit scope precisely before adversarial analysis begins
- Parallel adversarial audits: Phases 127 and 128 ran concurrently after Phase 126 dependency was met

### Key Lessons
1. Delta audits are fast when the base audit (v5.0) was thorough — the three-agent system only needs to re-examine changed functions
2. Plan reconciliation catches unplanned changes that would otherwise be audit blind spots (DegenerusAffiliate default code namespace change)
3. Formatting-only triage is a legitimate optimization — 17 functions correctly fast-tracked with zero missed findings
4. The v6.0→v7.0 implementation→audit cycle validates the "ship fixes, then delta-audit" approach for iterative protocol development

### Cost Observations
- Model mix: 100% opus (quality profile for all agents)
- Single-session execution (~4 hours wall clock)
- Notable: 65 functions audited with 11 plans, 3 real bugs found and fixed — lean and effective

---

## Milestone: v29.0 — Post-v27 Contract Delta Audit

**Shipped:** 2026-04-18
**Phases:** 8 (230, 231, 232, 232.1, 233, 234, 235, 236) | **Plans:** 21 | **Requirements:** 25/25 satisfied

### What Was Built
- Adversarial audit of every `contracts/` change since the v27.0 (2026-04-13) baseline — 10 in-scope commits across 12 contract/interface files plus 2 post-Phase-230 RNG-hardening commits captured via `230-02-DELTA-ADDENDUM.md`
- ETH + BURNIE conservation re-proven across the delta (41 SSTORE catalog rows + 10 named-path proofs; 10 mint + 6 burn sites)
- Per-consumer RNG commitment-window re-proof for every new RNG consumer (28+ backward-trace rows + 19 commitment-window rows + 25-variable global state-space enumeration); rngLocked invariant formally annotated
- TRNX-01 4-path walk verifying rngLocked invariant preserved across the packed phase-transition (Normal / Gameover / Skip-split / Phase-transition freeze)
- `audit/FINDINGS-v29.0.md` published in v27.0 structural form with 4 INFO findings (F-29-01..04) and 32-row Regression Appendix
- `KNOWN-ISSUES.md` refined for warden-facing scope: 1 new design-decision entry codifying the "RNG-consumer determinism" invariant; 4 out-of-scope test/script entries removed; all internal audit-artifact cross-references stripped

### What Worked
- Mid-milestone phase insertion (232.1) handled cleanly when RNG-index ticket-drain ordering surfaced as a separate hardening concern — `/gsd-insert-phase` decimal-numbering pattern preserved phase ordering without renumbering 233+
- 5-plan parallel Wave 1 in Phase 235 (CONS-01/02 + RNG-01/02 + TRNX-01) executed in one sitting via `/gsd-execute-phase --auto` with all 5 SAFE verdicts and zero candidate findings
- Phase 230 lightweight scope-map pattern (modeled on v25.0's 213-03 + v28.0's 224-01) gave every downstream phase a precise per-file/per-function delta to audit, eliminating ambiguity at planning time
- Strong precedent reuse — Phase 236 followed 217-01/217-02 (consolidation + regression) verbatim with `feedback_skip_research_test_phases.md` correctly applied to skip the research step
- Cross-repo READ-only pattern from v28.0 (D-229) carried forward — zero `contracts/` or `test/` writes throughout the milestone
- User-surfaced retroactive disclosure (F-29-04 Gameover RNG substitution) caught a subtle invariant violation that the formal audit had marked SAFE — adversarial review cycle on KI text proved valuable beyond the original audit pass

### What Was Inefficient
- Plan 236-02 deferred tracking sync (REQUIREMENTS.md flips, FIND-03 status) to `/gsd-complete-milestone`, which then surfaced as a verification gap during pre-close audit — could have been folded into Plan 02 SUMMARY directly with no extra cost
- Initial F-29-04 entry in `audit/FINDINGS-v29.0.md` and `KNOWN-ISSUES.md` carried internal audit-artifact cross-references that had to be stripped post-close for warden delivery — KI text should be drafted warden-facing from the start
- BAF event-widening and 3 test/script entries were initially added to `KNOWN-ISSUES.md` per Plan 236-01, then removed during user review — the consolidation plan should have explicit "warden-facing scope" gate before promoting items to KI
- Two race-commit-subject artifacts during Phase 235 parallel execution (`0e963b05`, `950cc7f5`) — same class of bug as 4a06e5af in Phase 233/234 parallel runs; suggests the sequential-dispatch-with-run_in_background pattern from execute-phase doesn't fully eliminate the race

### Patterns Established
- **User-surfaced retroactive findings during consolidation review** — Phase 236 pre-publication review caught the F-29-04 Gameover RNG substitution disclosure that formal audit had marked SAFE/Finding-Candidate-N. Surface-area for "things the audit didn't flag but a warden should know" lives in the consolidation phase, not the original audit phase.
- **"RNG-consumer determinism" as a named protocol invariant** — established this milestone; future RNG audits should cite by name and verify each new consumer against it
- **Warden-facing scope gate for KI promotions** — KI is for things wardens might find-and-flag; not every audit observation belongs there. Test tooling, deploy scripts, and internal audit cross-references stay in `audit/FINDINGS-vXX.0.md` (which may not even ship in delivery)
- **Tracking-sync deferral pattern is fragile** — plans that defer REQUIREMENTS.md/STATE.md flips to milestone-close should explicitly call out which flips and own the gap until close-out

### Key Lessons
- A "clean cycle" milestone (zero on-chain findings) still produces meaningful disclosure work — the F-29-04 retrospective surfacing shows audit substance and disclosure substance are different deliverables
- KNOWN-ISSUES.md is warden-facing, not internal — every cross-reference to internal audit artifacts (`audit/FINDINGS-vXX.0.md`, phase IDs, `F-XX-NN` IDs) needs scope review before publication
- `feedback_skip_research_test_phases.md` is reliably applicable to consolidation phases with strong precedent (217, 229 → 236) — saves an entire researcher agent spawn cycle without quality loss
- Mid-milestone phase insertions (232.1) with decimal numbering work well; the renumber-other-phases anti-pattern is correctly avoided
- Pre-close artifact audit (`audit-open --json`) is essential — caught a bookkeeping gap (Phase 231 EBD-03 traceability row stale) AND a tracking-sync deferral that would have shipped with stale Pending statuses

### Cost Observations
- Model mix: ~95% opus (planner + executor on all phases), ~5% sonnet (plan-checker + verifier)
- Sessions: 2 (Phases 230-235 in session 1 on 2026-04-17/18; Phase 236 + close-out in session 2)
- Notable: Phase 235 5-plan parallel Wave 1 executed in a single user prompt cycle via `/gsd-execute-phase --auto` — high efficiency on independent-plan parallelization

---

## Milestone: v30.0 — Full Fresh-Eyes VRF Consumer Determinism Audit

**Shipped:** 2026-04-20
**Phases:** 6 (237, 238, 239, 240, 241, 242) | **Plans:** 14 | **Requirements:** 26/26 satisfied

### What Was Built
- Exhaustive per-consumer VRF determinism audit at HEAD `7ab515fe` — 146 VRF-consuming call sites enumerated (no sampling) and classified into 5 path families
- Per-consumer backward freeze + forward freeze + gating verification on all 146 rows (124 SAFE + 22 EXCEPTION matching EXC-01..04 distribution; 0 CANDIDATE_FINDING at the freeze-proof layer)
- `rngLockedFlag` proven AIRTIGHT with closed-form biconditional Invariant Proof; 62-row permissionless sweep (3-class closed taxonomy); both documented asymmetries (lootbox index-advance + `phaseTransitionActive`) re-justified from first principles
- VRF-available gameover-jackpot branch proven fully deterministic — 19-row inventory / 28-row GOVAR state-freeze / 2-row GOTRIG trigger-timing DISPROVEN / GO-05 dual-disjointness BOTH_DISJOINT
- ONLY_NESS_HOLDS_AT_HEAD for the 4 KNOWN-ISSUES RNG exceptions — Gate A set-equality + Gate B grep backstop; EXC-02/03/04 predicates all RE_VERIFIED_AT_HEAD
- `audit/FINDINGS-v30.0.md` published (729 lines, 10 sections per D-23): 17 F-30-NNN INFO finding blocks + 31-row Regression Appendix (31 PASS / 0 REGRESSED / 0 SUPERSEDED) + 17-row FIND-03 Non-Promotion Ledger (0 KI promotions) + §10 MILESTONE_V30_CLOSED_AT_HEAD_7ab515fe attestation
- 29/29 Phase 240 → 241 forward-cite tokens discharged with literal `DISCHARGED_RE_VERIFIED_AT_HEAD`; 0 Phase 241 → 242 residuals (D-25 terminal-phase rule satisfied)

### What Worked
- **Fresh-eyes-from-first-principles discipline paid off** — every assertion re-proven at HEAD `7ab515fe`; prior-milestone artifacts (v25.0 Phase 215, v29.0 Phase 235 Plans 03-04, v3.7/v3.8) cited as context but NOT relied upon. No false-confidence carry-over.
- **HEAD anchor lockdown (D-17) caught zero drift** — contract tree byte-identical to v29.0 `1646d5af` throughout the milestone; every phase verified `git diff 7ab515fe -- contracts/` empty at task boundaries, so any mid-milestone contract change would have been visible immediately.
- **146-row universe-set pattern** gave every downstream phase a precise row-aligned scope — Phase 238's BWD/FWD/gating tables, Phase 240's gameover subset (19 rows), Phase 241's 22 EXCEPTION row set-equality all reconcile cleanly against a single 146-row inventory. Removed ambiguity about "what's in scope."
- **Closed verdict taxonomies per phase** (BWD-03 4-value actor-cell vocabulary, 3-class permissionless sweep, Named Gate 5-value taxonomy, FIND-03 3-predicate + 2-verdict KI ledger) prevented free-form verdicts and made row-level mechanical reconciliation possible between phases.
- **Forward-cite discharge ledger pattern** (Phase 240 → 241) — 29 tokens with unique IDs (EXC-241-023..051) preserved audit chain-of-custody across parallel phase execution; every token verifiable at Phase 242 § 9 without re-running the underlying proofs.
- **D-26 two-commit plan-close pattern** (Phase 242 Task 5): audit file + SUMMARY in Commit 1; STATE + ROADMAP orchestrator-driven in Commit 2. Enables forensic reconstruction and keeps the audit deliverable commit separate from the orchestrator tracking commit.
- **D-01 single consolidated plan per phase** (Phase 241 + Phase 242 both overrode ROADMAP's 2-plan split) — enabled atomic milestone-closure attestation where all 5 task commits are sequentially attributable to one plan's scope.
- **Pre-existing `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md`** (from v29.0 retrospective) were applied uniformly across Phase 238 — backward trace from every consumer to rawFulfillRandomWords paired with commitment-window enumeration at every request-fulfillment boundary.

### What Was Inefficient
- **No MILESTONE-AUDIT.md was run** — followed v28.0/v29.0 precedent (optional), but the pre-close artifact audit DID surface 2 stale quick-task tracker entries (`260327-n7h`, `260327-q8y`) that an earlier MILESTONE-AUDIT would have caught cleaner. They're unrelated to v30.0 but now carry forward as "known deferred items at close" in MILESTONES.md a second time (first time in v29.0).
- **REQUIREMENTS.md traceability table stayed stale during execution** — remained "Pending" through the milestone even as phases completed; only the archived `v30.0-REQUIREMENTS.md` reflects final status. Same tracking-sync deferral pattern flagged as fragile in v29.0 retrospective.
- **ROADMAP.md accumulated extensive per-phase detail during execution** (the v30.0 `<details>` block grew to ~120 lines including Phase Details + Progress table) — all of which had to be extracted at milestone-close into `milestones/v30.0-ROADMAP.md`. Future milestones may benefit from keeping ROADMAP.md compact throughout execution and accumulating detail directly into the archive-target file.
- **Phase 242 plan was 1130 lines** with 5 sequential tasks in a single plan — worked cleanly but the verifier's `key_links` regex patterns in the 244-line plan went through 1 revision iteration (3 BLOCKER + 4 WARNING) before plan-checker approval. Plan-checker is carrying real value; allow for revision cycles in terminal consolidation plans.

### Patterns Established
- **HEAD anchor lockdown (D-17) as a cross-phase discipline** — every phase verifies `git diff {HEAD_ANCHOR} -- contracts/` empty at every task boundary. Catches any silent contract drift within the milestone.
- **Closed verdict taxonomies per phase dimension** — no free-form verdicts; every cell value comes from an explicitly-enumerated vocabulary (BWD-03 4-actor cells; RNG-02 3-class; Named Gate 5-value; GO-02 3-verdict; FIND-03 3-predicate). Enables mechanical cross-phase reconciliation and prevents verdict creep.
- **Forward-cite discharge ledger** (prev-phase emits tokens with unique IDs → next-phase emits `DISCHARGED_RE_VERIFIED_AT_HEAD` ledger) — chain-of-custody for audit assertions across parallel phases; avoids re-running proofs at consolidation.
- **D-26 two-commit plan-close** — audit deliverable + SUMMARY in one commit; STATE + ROADMAP orchestrator tracking in a second commit. Separates content from tracking and gives clean forensic boundaries.
- **D-09 KI-eligibility 3-predicate gate** (accepted-design + non-exploitable + sticky) — not every audit observation belongs in `KNOWN-ISSUES.md`; codifies the warden-facing scope gate first established in v29.0 as a formal 3-predicate test. 0 of 17 candidates qualified under this gate in v30.0.
- **D-25 terminal-phase zero-forward-cites rule** — any finding that cannot close in the milestone MUST route to an F-NN-NNN block or explicit user-acknowledged rollover addendum. Prevents "deferred to next milestone" scope creep.
- **Universe-set per-row reconciliation** — establish the universe as a numbered row set once (Phase 237 INV-237-NNN = 146 rows), then every downstream phase cites by row ID rather than re-deriving. Phase 240 gameover = 19-row subset; Phase 241 EXCEPTION = 22-row subset; Phase 242 proof table = full 146×5 grid.

### Key Lessons
1. **Fresh-eyes audits are a different product from delta audits** — v29.0 was a delta audit (10 commits in scope); v30.0 was a fresh-eyes universe audit (every VRF consumer in `contracts/`, prior-artifact cites optional not load-bearing). Same methodology (BWD + FWD + adversarial closure) but different scope posture — fresh-eyes requires re-proving assertions you could have trusted in a delta.
2. **146 rows × 5 proof dimensions = 730 verdict cells** is tractable when every column has a closed taxonomy and the universe is row-aligned upstream. Without universe alignment, cross-phase verdict reconciliation would explode combinatorially.
3. **"ONLY-ness" claims require two gates**: set-equality with a prior exhaustive enumeration (Gate A) + fresh-grep backstop over the pattern space (Gate B). Either alone is insufficient: Gate A trusts prior enumeration is exhaustive; Gate B trusts the grep pattern space is exhaustive. Combining them covers the cases where either assumption drifts.
4. **Re-justifying documented asymmetries from first principles** (RNG-03 § A and § B) was more valuable than the direct RNG-01/RNG-02 sweep — asymmetries are where prior-milestone shortcuts most likely hide, and proving them by exhaustion over the storage-primitive set produced clean first-principles warrants.
5. **Zero on-chain vulnerabilities is the expected outcome of a READ-only carry-forward audit, not a success claim** — the value is the audit artifact (730-cell proof table + 17 F-30-NNN INFO blocks + 29/29 forward-cite discharges), which now exists as public evidence the invariant holds. The deliverable IS the product.
6. **Plan-checker carries real value on large consolidation plans** — Phase 242's 1130-line plan went through 3 BLOCKER + 4 WARNING resolutions before approval; the plan that executed was measurably better than the first draft. Allow time for plan-checker iteration on terminal-phase plans.
7. **Byte-identity checks on upstream deliverables** (`git diff {plan_start_commit} -- 'audit/v30-*.md' ':!scratch'` empty) caught zero drift but would have caught any silent mid-execution edit. Cheap to run at task boundaries, high signal if it ever fires.

### Cost Observations
- Model mix: ~95% opus (planner + executor across all phases), ~5% sonnet (plan-checker + verifier)
- Sessions: ~3 (planning + parallel execution of 238/239/240 + terminal 241/242)
- Notable: Phase 242 executor produced a 729-line audit deliverable + 230-line SUMMARY in one sustained run (~25 min wall-clock, fully autonomous, no checkpoints hit, ~113 tool uses, ~429k tokens). Single-plan consolidation with 5 sequential tasks scales well with 1M-context models.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v2.1 | 2 | 12 | Post-audit hardening pass added; adversarial persona protocol (CP-01) |
| v3.1 | 7 | 16 | Batch-by-group audit structure; flag-only mode; 6-field finding format |
| v3.3 | 6 | 15 | Research-first pipeline; invariant test encoding; economic fairness proofs; milestone audit cycle |
| v3.4 | 4 | 10 | False positive detection (REDM-06-A mutually exclusive paths); parallel audit phases |
| v3.5 | 4 | 13 | 3-workstream parallelism; gas ceiling profiling; regression tracking across milestones |
| v3.6 | 4 | 6 | VRF stall resilience code changes; integration tests for stall-to-recovery cycle |
| v3.7 | 5 | 10 | Halmos symbolic verification; ghost variable invariant testing; single-day milestone delivery |
| v3.8 | 6 | 13 | Backward-trace commitment window proofs; mutation path enumeration; boon storage packing |
| v3.9 | 7 | 8 | TDD fix pipeline; combined pool pattern; bit-reservation key spaces; full-protocol integration tests |
| v4.0 | 11 | 24 | Exhaustive lifecycle trace; file:line citation density; false positive withdrawal; cross-phase consistency |
| v4.1 | 3 | 4 | Accumulating test file; analytical proof + Foundry test pairing; zero-stranding sweep helper |
| v6.0 | 6 | 12 | Implementation milestone: test cleanup, storage/gas fixes, DegenerusCharity contract, game integration |
| v7.0 | 4 | 11 | Delta audit methodology; formatting-only triage; plan-vs-reality reconciliation; parallel adversarial audits |
| v29.0 | 8 | 21 | Mid-milestone phase insertion (232.1) with decimal numbering; user-surfaced retroactive disclosure pattern (F-29-04); 5-plan parallel Wave 1 in single execution; warden-facing scope gate for KI promotions; "RNG-consumer determinism" invariant named |
| v30.0 | 6 | 14 | Fresh-eyes universe-audit posture (146-row VRF consumer inventory); HEAD anchor lockdown (D-17) as cross-phase discipline; closed verdict taxonomies per dimension; forward-cite discharge ledger chain-of-custody; D-09 3-predicate KI-eligibility gate; D-26 two-commit plan-close; D-25 terminal-phase zero-forward-cites; Gate A + Gate B two-gate ONLY-ness proof pattern |

### Top Lessons (Verified Across Milestones)

1. Simplify before shipping — removing complexity is more valuable than documenting it
2. User review of audit findings catches design-level improvements that formal analysis misses
3. Multi-pass audits catch what single passes miss — 84 findings after a "thorough" first pass (v2.1→v3.1 pattern)
4. Research phase code analysis predicts actual findings with high accuracy (4/5 confirmed in v3.3) — front-loading this investment pays off
5. False positive analysis saves real money — REDM-06-A (v3.4) was downgraded by tracing mutually exclusive code paths, avoiding an unnecessary code change
6. Ghost variable invariant testing is the strongest technique for proving cross-transaction accounting properties — validated in v3.3 (redemption) and v3.7 (VRF lifecycle)
7. Halmos symbolic proofs give mathematical certainty for numeric invariants — redemption roll [25,175] proven for all 2^256 inputs (v3.7)
8. Combined pool selection eliminates entire classes of buffer-read bugs — structurally superior to single-read patches (v3.9)
9. Full-protocol integration tests (23 contracts, multi-level advancement) catch constructor/deploy-order issues that unit tests with mocks miss (v3.9, v4.1)
10. Plan-sketched test assertions are consistently wrong about storage semantics — auto-fix pipelines handle this, but acknowledging it during planning reduces deviation count (v4.1)
11. Accumulating single test file beats per-phase files for integration suites where later tests reuse earlier helpers and storage inspection patterns (v4.1)
