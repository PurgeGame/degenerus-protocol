---
phase: 46
slug: game-theory-paper-parity
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-07
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Mocha + Chai |
| **Config file** | hardhat.config.js |
| **Quick run command** | `npx hardhat test test/validation/PaperParity.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~20 seconds (quick), ~240 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/validation/PaperParity.test.js`
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 46-01-01 | 01 | 1 | PAR-01 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "PriceLookupLib"` | yes | green |
| 46-01-02 | 01 | 1 | PAR-02 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "ticket cost formula"` | yes | green |
| 46-01-03 | 01 | 1 | PAR-03 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "prize pool split"` | yes | green |
| 46-01-04 | 01 | 1 | PAR-04 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "jackpot day"` | yes | green |
| 46-01-05 | 01 | 1 | PAR-05 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "bucket shares"` | yes | green |
| 46-01-06 | 01 | 1 | PAR-06 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "activity score"` | yes | green |
| 46-01-07 | 01 | 1 | PAR-07 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "lootbox EV"` | yes | green |
| 46-01-08 | 01 | 1 | PAR-08 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "affiliate commission"` | yes | green |
| 46-01-09 | 01 | 1 | PAR-09 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "tier structure"` | yes | green |
| 46-01-10 | 01 | 1 | PAR-10 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "whale bundle"` | yes | green |
| 46-01-11 | 01 | 1 | PAR-11 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "lazy pass"` | yes | green |
| 46-01-12 | 01 | 1 | PAR-12 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "deity pass"` | yes | green |
| 46-01-13 | 01 | 1 | PAR-13 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "coinflip"` | yes | green |
| 46-01-14 | 01 | 1 | PAR-14 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "yield distribution"` | yes | green |
| 46-01-15 | 01 | 1 | PAR-15 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "BURNIE entry"` | yes | green |
| 46-01-16 | 01 | 1 | PAR-16 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "Degenerette"` | yes | green |
| 46-01-17 | 01 | 1 | PAR-17 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "capital injection"` | yes | green |
| 46-01-18 | 01 | 1 | PAR-18 | validation | `npx hardhat test test/validation/PaperParity.test.js --grep "future ticket"` | yes | green |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. 118 tests pre-existed.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 20s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-07
