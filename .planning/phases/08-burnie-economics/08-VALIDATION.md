---
phase: 8
slug: burnie-economics
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification (documentation-only phase) |
| **Config file** | none — no code changes |
| **Quick run command** | `grep -c "##" audit/burnie-economics.md` |
| **Full suite command** | `grep -c "BURN-0[1-4]" audit/burnie-economics.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify document section completeness
- **After every plan wave:** Cross-reference all formulas against contract source
- **Before `/gsd:verify-work`:** All four BURN requirements must have exact contract values
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | BURN-01 | manual | `grep "coinflip" audit/burnie-economics.md` | n/a | pending |
| 08-01-02 | 01 | 1 | BURN-02 | manual | `grep "earning" audit/burnie-economics.md` | n/a | pending |
| 08-01-03 | 01 | 1 | BURN-03 | manual | `grep "burn" audit/burnie-economics.md` | n/a | pending |
| 08-01-04 | 01 | 1 | BURN-04 | manual | `grep "vault" audit/burnie-economics.md` | n/a | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. (Documentation-only phase — no test framework needed.)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Coinflip formulas match BurnieCoinflip.sol | BURN-01 | Documentation accuracy requires human review | Cross-reference every constant/formula against contract source |
| Earning path completeness | BURN-02 | Must verify all earning call sites are enumerated | Search contract source for all mintForCoinflip/creditFlip calls |
| Burn sink completeness | BURN-03 | Must verify all burn call sites are enumerated | Search contract source for all _burn/burnCoin calls |
| Vault invariant accuracy | BURN-04 | Supply struct interpretation requires source verification | Verify supply struct fields match documented invariants |

---

## Validation Sign-Off

- [x] All tasks have verification criteria
- [x] Sampling continuity: documentation phase — continuous review
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
