---
phase: 29
slug: comment-documentation-correctness
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-18
---

# Phase 29 — Validation Strategy

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

- **After every task commit:** Review output document for completeness and accuracy
- **After every plan wave:** Cross-check that all contracts are covered, no files missed
- **Before `/gsd:verify-work`:** All 5 DOC requirements have explicit verdicts with evidence
- **Max feedback latency:** N/A (manual review)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 29-01-xx | 01 | 1 | DOC-01 | manual-only | N/A -- requires reading and cross-referencing NatSpec | N/A | ⬜ pending |
| 29-02-xx | 02 | 1 | DOC-02 | manual-only | N/A -- requires reading each comment in context | N/A | ⬜ pending |
| 29-03-xx | 03 | 2 | DOC-03 | manual-only | N/A -- requires byte-offset arithmetic verification | N/A | ⬜ pending |
| 29-04-xx | 04 | 2 | DOC-04 | manual-only | N/A -- requires reading constant declarations | N/A | ⬜ pending |
| 29-05-xx | 05 | 3 | DOC-05 | manual-only | N/A -- requires cross-referencing doc vs source | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. No test infrastructure needed — this is a documentation audit phase producing markdown reports.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec matches actual behavior on all ext/pub functions | DOC-01 | Semantic accuracy of English descriptions cannot be automated | Read each function's NatSpec, compare against Phase 26-28 audit verdicts and code behavior |
| Inline comments match current code | DOC-02 | Stale references require understanding code evolution context | Read each inline comment, verify against surrounding code logic |
| Storage layout comments match actual positions | DOC-03 | Requires byte-offset arithmetic and struct layout knowledge | Verify each slot comment against variable declarations and packing |
| Constants comments match actual values | DOC-04 | Requires reading constant declarations and comparing | Compare each constant's comment against its actual assigned value |
| Parameter reference doc values correct | DOC-05 | Requires cross-referencing external doc against contract source | Spot-check every entry in parameter reference against contract code |

---

## Validation Sign-Off

- [x] All tasks have manual verification procedures defined
- [x] Sampling continuity: per-task review + per-wave cross-check
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency: N/A (manual review phase)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-18
