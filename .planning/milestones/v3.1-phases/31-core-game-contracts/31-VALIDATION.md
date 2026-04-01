---
phase: 31
slug: core-game-contracts
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-18
---

# Phase 31 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit verification (no automated tests) |
| **Config file** | N/A |
| **Quick run command** | N/A (documentation review, not code execution) |
| **Full suite command** | N/A |
| **Estimated runtime** | N/A |

---

## Sampling Rate

- **After every task commit:** Review findings file for completeness -- every function and block comment in the target contract(s) should be covered
- **After every plan wave:** Cross-check that all 3 contracts are covered with no files missed
- **Before `/gsd:verify-work`:** CMT-01 and DRIFT-01 both have explicit verdicts; a per-batch findings file exists with what/why/suggestion for every item
- **Max feedback latency:** N/A (manual review)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 31-01-XX | 01 | 1 | CMT-01 | manual-only | N/A | N/A | ⬜ pending |
| 31-02-XX | 02 | 1 | CMT-01 | manual-only | N/A | N/A | ⬜ pending |
| 31-03-XX | 03 | 1 | CMT-01, DRIFT-01 | manual-only | N/A | N/A | ⬜ pending |
| 31-04-XX | 04 | 1 | DRIFT-01 | manual-only | N/A | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework or stubs needed — this is a documentation/findings-only audit phase.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec accuracy across 3 contracts | CMT-01 | Requires human judgment to determine if English descriptions would mislead a C4A warden | Read each NatSpec tag, cross-reference with code behavior, flag mismatches |
| Inline comment accuracy | CMT-01 | Semantic accuracy of natural language cannot be automated | Read each inline comment, verify against current logic |
| Intent drift detection | DRIFT-01 | Requires understanding of designer intent vs actual behavior | Identify vestigial guards, unnecessary restrictions, behavior drift |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (N/A — manual-only phase)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (N/A — manual-only phase)
- [x] Wave 0 covers all MISSING references (N/A — no test infrastructure needed)
- [x] No watch-mode flags
- [x] Feedback latency < N/A (manual review)
- [x] `nyquist_compliant: true` set in frontmatter

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against code behavior and design intent. There is no automated tool that can determine whether a NatSpec description would mislead a C4A warden. The verification requires understanding the audit verdicts from Phases 26-28, the post-Phase-29 code changes, and the protocol's intended design.

**Approval:** approved 2026-03-18
