---
phase: 45
slug: security-and-economic-hardening-tests
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-07
---

# Phase 45 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Mocha + Chai |
| **Config file** | hardhat.config.js |
| **Quick run command** | `npx hardhat test test/unit/SecurityEconHardening.test.js test/edge/CompressedJackpot.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~48 seconds (quick), ~240 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run quick command
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 48 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 45-01-01 | 01 | 1 | FIX-01 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "whale.*gameOver"` | yes | green |
| 45-01-02 | 01 | 1 | FIX-02 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "lazy.*gameOver"` | yes | green |
| 45-01-03 | 01 | 1 | FIX-03 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "deity.*gameOver"` | yes | green |
| 45-01-04 | 01 | 1 | FIX-04 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "receive.*gameOver"` | yes | green |
| 45-01-05 | 01 | 1 | FIX-05 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "deityPassPurchasedCount"` | yes | green |
| 45-01-06 | 01 | 1 | FIX-06 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "no voluntary"` | yes | green |
| 45-01-07 | 01 | 1 | FIX-07 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "flat 20 ETH"` | yes | green |
| 45-01-08 | 01 | 1 | FIX-08 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "liveness"` | yes | green |
| 45-01-09 | 01 | 1 | FIX-09 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "uint256"` | yes | green |
| 45-01-10 | 01 | 1 | FIX-10 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "1 wei sentinel"` | yes | green |
| 45-01-11 | 01 | 1 | FIX-11 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "capBucketCounts"` | yes | green |
| 45-01-12 | 01 | 1 | FIX-12 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "carryover"` | yes | green |
| 45-02-01 | 02 | 2 | ECON-01 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "46.*futureShare"` | yes | green |
| 45-02-02 | 02 | 2 | ECON-02 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "no level-dependent"` | yes | green |
| 45-02-03 | 02 | 2 | ECON-03 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "scatter"` | yes | green |
| 45-02-04 | 02 | 2 | ECON-04 | integration | `npx hardhat test test/edge/CompressedJackpot.test.js` | yes | green |
| 45-02-05 | 02 | 2 | ECON-05 | unit | `npx hardhat test test/unit/SecurityEconHardening.test.js --grep "LINK reward"` | yes | green |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. 47 tests pre-existed.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 48s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-07
