---
phase: 40
slug: comment-scan-core-token
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-19
---

# Phase 40 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit (no automated tests) |
| **Config file** | N/A |
| **Quick run command** | N/A — documentation review, not code execution |
| **Full suite command** | N/A |
| **Estimated runtime** | N/A |

---

## Sampling Rate

- **After every task commit:** Review findings document for completeness — every function has a verdict, every v3.1 finding has a fix status
- **After every plan wave:** Cross-check that all 7 contracts are covered, no files missed
- **Before `/gsd:verify-work`:** Both CMT-02 and CMT-03 have explicit verdicts with evidence

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 40-01-01 | 01 | 1 | CMT-02 | manual-only | N/A | N/A | pending |
| 40-02-01 | 02 | 1 | CMT-03 | manual-only | N/A | N/A | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a documentation audit phase — no test infrastructure needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Core game contract comments verified | CMT-02 | Semantic accuracy of English NatSpec against code behavior cannot be automated | Read each NatSpec block, verify against function code, produce finding per discrepancy |
| Token contract comments verified | CMT-03 | Same — semantic comment verification requires human reading | Read each NatSpec block, verify against function code, produce finding per discrepancy |

---

## Validation Sign-Off

- [x] All tasks have manual verify (no automated tests applicable)
- [x] This is a documentation audit — sampling continuity via manual review
- [x] Wave 0 not needed — no test infrastructure required
- [x] No watch-mode flags
- [x] N/A — feedback latency not applicable for manual audit
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-19
