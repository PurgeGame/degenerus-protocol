---
phase: 44
slug: affiliate-system-tests
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-07
---

# Phase 44 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Mocha + Chai |
| **Config file** | hardhat.config.js |
| **Quick run command** | `npx hardhat test test/unit/AffiliateHardening.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~15 seconds (quick), ~240 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/unit/AffiliateHardening.test.js`
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 44-01-01 | 01 | 1 | AFF-01 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "cap at 0.5 ETH"` | yes | green |
| 44-01-02 | 01 | 1 | AFF-02 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "cumulative"` | yes | green |
| 44-01-03 | 01 | 1 | AFF-03 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "resets per level"` | yes | green |
| 44-01-04 | 01 | 1 | AFF-04 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "independent caps"` | yes | green |
| 44-01-05 | 01 | 1 | AFF-05 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "score.*15000"` | yes | green |
| 44-01-06 | 01 | 1 | AFF-06 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "linear taper"` | yes | green |
| 44-01-07 | 01 | 1 | AFF-07 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "floor at 50"` | yes | green |
| 44-01-08 | 01 | 1 | AFF-08 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "leaderboard.*untapered"` | yes | green |
| 44-01-09 | 01 | 1 | AFF-09 | unit | `npx hardhat test test/unit/AffiliateHardening.test.js --grep "lootboxActivityScore"` | yes | green |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. 39 tests pre-existed.

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
