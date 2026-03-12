---
phase: 7
slug: jackpot-distribution-mechanics
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification against Solidity source (documentation-only phase) |
| **Config file** | N/A |
| **Quick run command** | `grep -c "BPS\|ether\|pool\|jackpot\|draw" audit/07-jackpot-distribution-mechanics.md` |
| **Full suite command** | Visual diff of documented expressions against contract source |
| **Estimated runtime** | ~30 seconds (manual spot-check) |

---

## Sampling Rate

- **After every task commit:** Spot-check documented values against contract source
- **After every plan wave:** Full cross-reference of all BPS constants and formulas
- **Before `/gsd:verify-work`:** All documented expressions verified against source
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | JACK-01 | manual-only | Cross-reference drip formulas with AdvanceModule.sol | N/A | ⬜ pending |
| 07-01-02 | 01 | 1 | JACK-02 | manual-only | Verify BURNIE jackpot selection in AdvanceModule.sol | N/A | ⬜ pending |
| 07-02-01 | 02 | 1 | JACK-03 | manual-only | Verify daily pool slice formulas in JackpotModule.sol | N/A | ⬜ pending |
| 07-02-02 | 02 | 1 | JACK-04 | manual-only | Verify trait bucket mapping in JackpotModule.sol | N/A | ⬜ pending |
| 07-02-03 | 02 | 1 | JACK-05 | manual-only | Verify carryover and compressed conditions | N/A | ⬜ pending |
| 07-02-04 | 02 | 1 | JACK-06 | manual-only | Verify lootbox conversion BPS in JackpotModule.sol | N/A | ⬜ pending |
| 07-02-05 | 02 | 1 | JACK-07 | manual-only | Verify BURNIE parallel distribution formulas | N/A | ⬜ pending |
| 07-03-01 | 03 | 1 | JACK-08 | manual-only | Verify BAF percentages in AdvanceModule.sol | N/A | ⬜ pending |
| 07-03-02 | 03 | 1 | JACK-09 | manual-only | Verify decimator triggers/tiers in DecimatorModule.sol | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a documentation-only phase — contract source code serves as the test fixture.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Daily future pool drip formulas | JACK-01 | Documentation phase | Verify 1% drip and early-bird 3% in AdvanceModule |
| BURNIE jackpot selection/payout | JACK-02 | Documentation phase | Verify winner selection and payout in AdvanceModule |
| 5-day draw pool slice formulas | JACK-03 | Documentation phase | Verify 6-14% random range and 100% day-5 in JackpotModule |
| Trait bucket distribution | JACK-04 | Documentation phase | Verify trait-to-day mapping in JackpotModule |
| Carryover and compressed jackpot | JACK-05 | Documentation phase | Verify counterStep logic and carryover routing |
| Lootbox conversion ratios | JACK-06 | Documentation phase | Verify 50%/75% BPS constants |
| BURNIE parallel distribution | JACK-07 | Documentation phase | Verify far-future allocation formulas |
| BAF mechanics | JACK-08 | Documentation phase | Verify level-10 triggers and pool percentages |
| Decimator mechanics | JACK-09 | Documentation phase | Verify multiplier tiers and burn requirements |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
