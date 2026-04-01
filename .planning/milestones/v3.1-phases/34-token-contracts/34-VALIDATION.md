---
phase: 34
slug: token-contracts
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-19
---

# Phase 34 — Validation Strategy

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

- **After every task commit:** `grep -c '### CMT-\|### DRIFT-' audit/v3.1-findings-34-token-contracts.md` — verify finding count increments
- **After every plan wave:** Verify all contracts in that plan are covered with review-complete markers
- **Before `/gsd:verify-work`:** Full findings file must have integer counts in summary table (no X/Y/Z placeholders)
- **Max feedback latency:** immediate (grep commands)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 34-01-01 | 01 | 1 | CMT-04 | manual-only | `grep 'BurnieCoin.sol' audit/v3.1-findings-34-token-contracts.md` | N/A | ⬜ pending |
| 34-01-02 | 01 | 1 | CMT-04, DRIFT-04 | manual-only | `grep 'BurnieCoin.sol review complete' audit/v3.1-findings-34-token-contracts.md` | N/A | ⬜ pending |
| 34-02-01 | 02 | 1 | CMT-04 | manual-only | `grep 'StakedDegenerusStonk.sol\|DegenerusStonk.sol\|WrappedWrappedXRP.sol' audit/v3.1-findings-34-token-contracts.md` | N/A | ⬜ pending |
| 34-02-02 | 02 | 1 | CMT-04, DRIFT-04 | manual-only | `grep -c '### CMT-\|### DRIFT-' audit/v3.1-findings-34-token-contracts.md` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a documentation/findings-only audit phase producing a findings markdown file.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NatSpec and inline comment accuracy | CMT-04 | Requires reading and cross-referencing each comment against code behavior | Read every NatSpec tag and inline comment, verify against current HEAD code |
| Intent drift detection | DRIFT-04 | Requires understanding designer intent vs actual behavior | Scan for vestigial guards, stale references, unnecessary restrictions |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-19
