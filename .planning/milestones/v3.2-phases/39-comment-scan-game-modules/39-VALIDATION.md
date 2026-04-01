---
phase: 39
slug: comment-scan-game-modules
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 39 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit (no automated test framework — this is a comment correctness scan) |
| **Config file** | none |
| **Quick run command** | `grep -c "CMT-\|DRIFT-" .planning/phases/39-comment-scan-game-modules/39-*-SUMMARY.md` |
| **Full suite command** | `cat .planning/phases/39-comment-scan-game-modules/39-*-SUMMARY.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify findings file written with expected format
- **After every plan wave:** Verify all module files in the wave have been audited
- **Before `/gsd:verify-work`:** All 12 module files audited, consolidated findings produced
- **Max feedback latency:** 2 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 39-01-01 | 01 | 1 | CMT-01 | manual-audit | `grep -c "Finding" .planning/phases/39-comment-scan-game-modules/39-01-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 39-02-01 | 02 | 1 | CMT-01 | manual-audit | `grep -c "Finding" .planning/phases/39-comment-scan-game-modules/39-02-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 39-03-01 | 03 | 1 | CMT-01 | manual-audit | `grep -c "Finding" .planning/phases/39-comment-scan-game-modules/39-03-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 39-04-01 | 04 | 1 | CMT-01 | manual-audit | `grep -c "Finding" .planning/phases/39-comment-scan-game-modules/39-04-SUMMARY.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. This phase produces findings documents, not executable tests.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec accuracy | CMT-01 | Comments require human reading comprehension to verify against code | Read each function's NatSpec and verify params, returns, dev notes match actual code |
| Inline comment accuracy | CMT-01 | Semantic correctness of comments vs code requires understanding intent | Read inline comments and verify they describe what the adjacent code actually does |
| Block comment structure | CMT-01 | Section headers and organization require architectural understanding | Verify section headers reflect actual contract structure |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
