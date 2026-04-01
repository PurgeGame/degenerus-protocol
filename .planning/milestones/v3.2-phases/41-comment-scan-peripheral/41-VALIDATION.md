---
phase: 41
slug: comment-scan-peripheral
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 41 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual audit (comment correctness is a review task, not a code task) |
| **Config file** | none |
| **Quick run command** | `grep -c "CMT-" .planning/phases/41-comment-scan-peripheral/41-*-SUMMARY.md` |
| **Full suite command** | `cat .planning/phases/41-comment-scan-peripheral/41-*-SUMMARY.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify findings file exists and has correct format
- **After every plan wave:** Review findings list for completeness
- **Before `/gsd:verify-work`:** All contracts in scope must have verdict (findings or "clean")
- **Max feedback latency:** 1 second

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 41-01-01 | 01 | 1 | CMT-04 | manual+grep | `grep -c "BurnieCoinflip" .planning/phases/41-comment-scan-peripheral/41-01-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 41-01-02 | 01 | 1 | CMT-04 | manual+grep | `grep -c "DegenerusVault" .planning/phases/41-comment-scan-peripheral/41-01-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 41-01-03 | 01 | 1 | CMT-04 | manual+grep | `grep -c "DegenerusAffiliate" .planning/phases/41-comment-scan-peripheral/41-01-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 41-02-01 | 02 | 1 | CMT-04, CMT-05 | manual+grep | `grep -c "DegenerusQuests\|DegenerusJackpots\|IBurnieCoinflip\|IDegenerusGame" .planning/phases/41-comment-scan-peripheral/41-02-SUMMARY.md` | ❌ W0 | ⬜ pending |
| 41-03-01 | 03 | 1 | CMT-05 | manual+grep | `grep -c "DeityPass\|TraitUtils\|DeityBoonViewer\|ContractAddresses\|Icons32Data" .planning/phases/41-comment-scan-peripheral/41-03-SUMMARY.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. This is a documentation/audit phase — no test stubs needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec accuracy | CMT-04, CMT-05 | Requires human-level code comprehension to verify comment vs behavior | Read each function, compare NatSpec to actual parameters/returns/behavior |
| Inline comment accuracy | CMT-04, CMT-05 | Requires understanding code intent | Read code blocks, verify inline comments describe actual logic |
| Interface-implementation parity | CMT-04, CMT-05 | Requires cross-file comparison | Compare interface NatSpec with implementation behavior |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 1s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
