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

### Top Lessons (Verified Across Milestones)

1. Simplify before shipping — removing complexity is more valuable than documenting it
2. User review of audit findings catches design-level improvements that formal analysis misses
3. Multi-pass audits catch what single passes miss — 84 findings after a "thorough" first pass (v2.1→v3.1 pattern)
4. Research phase code analysis predicts actual findings with high accuracy (4/5 confirmed in v3.3) — front-loading this investment pays off
5. False positive analysis saves real money — REDM-06-A (v3.4) was downgraded by tracing mutually exclusive code paths, avoiding an unnecessary code change
6. Ghost variable invariant testing is the strongest technique for proving cross-transaction accounting properties — validated in v3.3 (redemption) and v3.7 (VRF lifecycle)
7. Halmos symbolic proofs give mathematical certainty for numeric invariants — redemption roll [25,175] proven for all 2^256 inputs (v3.7)
