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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v2.1 | 2 | 12 | Post-audit hardening pass added; adversarial persona protocol (CP-01) |

### Top Lessons (Verified Across Milestones)

1. Simplify before shipping — removing complexity is more valuable than documenting it
2. User review of audit findings catches design-level improvements that formal analysis misses
