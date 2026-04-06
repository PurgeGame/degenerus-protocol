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

## Milestone: v23.0 — JackpotModule Delta Audit & Payout Reference

**Shipped:** 2026-04-06
**Phases:** 2 | **Plans:** 3

### What Was Built
- Function-level changelog of 38 changes across 5 files (commits 93c05869, 520249a2) with refactor/intentional classification
- 9 REFACTOR equivalence proofs, 8 deleted-item unreachability proofs, event migration mapping (JackpotTicketWinner to 5 specialized events)
- Correctness proofs for 4 intentional behavioral changes (whale pass, DGNRS fold, coin target, ticket budget)
- Gas ceiling analysis: peak 6.28M (4.78x margin), worst-case gap identified (~25M with 321 autorebuy winners)
- Test regression baseline: Foundry 150/28, Hardhat 1232/13/3

### What Worked
- Lean 2-phase structure for a focused delta audit — no wasted phases
- Splitting delta extraction (192-01) from intentional change proofs (192-02) allowed each plan to stay focused
- Gas analysis correctly identified the theoretical worst-case gap that existing benchmarks missed — this is the GAS-01 methodology paying off

### What Was Inefficient
- CLI milestone-complete tool counted stale on-disk phase directories from prior milestones (190, 191) — inflated stats needed manual correction
- Phase 193 PLAN file was deleted from disk (visible in git status) but summary exists — cleanup inconsistency

### Patterns Established
- "Derive worst case FIRST, then test" methodology (from feedback_gas_worst_case) proven essential — existing benchmarks showed comfortable 4.78x margin but missed the 321-winner scenario entirely

### Key Lessons
1. Gas benchmarks that only test typical cases create false confidence — worst-case derivation must precede any "margin" claims
2. A 2-phase audit milestone (extract+classify, then verify+gas) is the right granularity for focused delta audits of 2-3 commits

### Cost Observations
- Model mix: 100% opus (quality profile)
- Single-session execution (~3 hours wall clock)
- Notable: 38 function changes fully classified and proven in 3 plans — efficient for the scope

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
| v23.0 | 2 | 3 | Worst-case-first gas analysis; lean 2-phase delta audit; theoretical gap identification (321-winner scenario) |

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
