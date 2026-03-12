---
phase: 6
slug: eth-inflows-and-pool-architecture
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification against Solidity source (documentation-only phase) |
| **Config file** | N/A |
| **Quick run command** | `grep -c "BPS\|ether\|pool" audit/06-eth-inflows-and-pool-architecture.md` |
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
| 06-01-01 | 01 | 1 | INFLOW-01 | manual-only | Cross-reference cost formulas with .sol source | N/A | ⬜ pending |
| 06-01-02 | 01 | 1 | INFLOW-02 | manual-only | Verify BURNIE burn amounts in MintModule.sol | N/A | ⬜ pending |
| 06-01-03 | 01 | 1 | INFLOW-03 | manual-only | Verify degenerette min bets in DegeneretteModule.sol | N/A | ⬜ pending |
| 06-01-04 | 01 | 1 | INFLOW-04 | manual-only | Verify presale conditionals in AdvanceModule.sol | N/A | ⬜ pending |
| 06-02-01 | 02 | 1 | POOL-01 | manual-only | Verify transition triggers against AdvanceModule.sol | N/A | ⬜ pending |
| 06-02-02 | 02 | 1 | POOL-02 | manual-only | Grep all BPS constants, cross-reference doc values | N/A | ⬜ pending |
| 06-02-03 | 02 | 1 | POOL-03 | manual-only | Verify freeze/unfreeze in DegenerusGameStorage.sol | N/A | ⬜ pending |
| 06-02-04 | 02 | 1 | POOL-04 | manual-only | Verify purchase target in AdvanceModule.sol | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a documentation-only phase — contract source code serves as the test fixture.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ETH cost formulas match source | INFLOW-01 | Documentation phase — no executable tests | Compare each documented formula against the corresponding .sol function |
| BURNIE conversion paths match source | INFLOW-02 | Documentation phase | Verify purchaseCoin/purchaseBurnieLootbox formulas |
| Degenerette wager routing | INFLOW-03 | Documentation phase | Verify min bets and pool routing in DegeneretteModule |
| Presale conditionals | INFLOW-04 | Documentation phase | Verify toggle conditions and feature differences |
| Pool lifecycle transitions | POOL-01 | Documentation phase | Trace each transition through AdvanceModule/JackpotModule |
| BPS split values | POOL-02 | Documentation phase | Grep all *_BPS constants, verify against documented table |
| Freeze/unfreeze mechanics | POOL-03 | Documentation phase | Verify _swapAndFreeze/_unfreezePool in Storage |
| Purchase target formula | POOL-04 | Documentation phase | Verify levelPrizePool ratchet logic |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
