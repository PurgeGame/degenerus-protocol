---
phase: 43
slug: governance-and-gating-tests
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-07
---

# Phase 43 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Mocha + Chai |
| **Config file** | hardhat.config.js |
| **Quick run command** | `npx hardhat test test/unit/GovernanceGating.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~15 seconds (quick), ~240 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/unit/GovernanceGating.test.js`
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 43-01-01 | 01 | 1 | ADMIN-01 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "onlyOwner"` | yes | green |
| 43-01-02 | 01 | 1 | ADMIN-02 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "onlyVaultOwner"` | yes | green |
| 43-01-03 | 01 | 1 | ADMIN-03 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "shutdownVrf.*access"` | yes | green |
| 43-01-04 | 01 | 1 | ADMIN-04 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "cancels subscription"` | yes | green |
| 43-01-05 | 01 | 1 | ADMIN-05 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "subscriptionId is already 0"` | yes | green |
| 43-01-06 | 01 | 1 | ADMIN-06 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "try.catch"` | yes | green |
| 43-01-07 | 01 | 1 | GATE-01 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "same-day"` | yes | green |
| 43-01-08 | 01 | 1 | GATE-02 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "relaxes"` | yes | green |
| 43-01-09 | 01 | 1 | GATE-03 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "DGVE.*bypass"` | yes | green |
| 43-01-10 | 01 | 1 | GATE-04 | unit | `npx hardhat test test/unit/GovernanceGating.test.js --grep "MustMintToday"` | yes | green |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. 32 tests pre-existed.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-07
