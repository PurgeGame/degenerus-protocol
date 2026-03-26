---
phase: 51
slug: redemption-lootbox-audit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 51 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with Solidity 0.8.34, via-ir=true |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-contract RedemptionInvariants -vv` |
| **Full suite command** | `forge test -vv` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-contract RedemptionInvariants -vv`
- **After every plan wave:** Run `forge test -vv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 51-01-01 | 01 | 1 | REDM-01 | manual (code audit) | N/A — static analysis of lines 583-595 | N/A | ⬜ pending |
| 51-01-02 | 01 | 1 | REDM-02 | manual (code audit) | N/A — static analysis of lines 470-521, 590 | N/A | ⬜ pending |
| 51-02-01 | 02 | 1 | REDM-03 | manual + invariant | `forge test --match-test invariant_fiftyPercentCap -vv` | ✅ | ⬜ pending |
| 51-02-02 | 02 | 1 | REDM-05 | manual (code audit) | N/A — struct verification: 96+96+48+16=256 | N/A | ⬜ pending |
| 51-03-01 | 03 | 1 | REDM-04 | manual (code audit) | N/A — static analysis of lines 759-762, 581 | N/A | ⬜ pending |
| 51-04-01 | 04 | 2 | REDM-06 | manual (code audit) | N/A — static analysis of Game.sol lines 1808-1822 | N/A | ⬜ pending |
| 51-04-02 | 04 | 2 | REDM-07 | manual (code audit) | N/A — call-chain enumeration | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. RedemptionInvariants.inv.t.sol and RedemptionGas.t.sol provide the test baseline. New invariant tests for the redemption lootbox split specifically are deferred to Phase 52 (INV-03).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 50/50 split routing | REDM-01 | Static code audit — verify arithmetic correctness | Read sDGNRS lines 583-595, verify ethDirect + lootboxEth == totalRolledEth |
| gameOver bypass | REDM-02 | Static code audit — verify conditional branching | Read _deterministicBurnFrom (470-521) and claimRedemption (590) |
| Activity score immutability | REDM-04 | Static code audit — verify guard condition | Read lines 759-762 (snapshot) and 581 (consumption) |
| Slot packing | REDM-05 | Static code audit — verify struct layout | Verify PendingRedemption struct: 96+96+48+16=256 |
| No ETH transfer in reclassification | REDM-06 | Static code audit — verify internal accounting | Read Game.sol 1808-1822, verify no transfer/send/call |
| Access control chain | REDM-07 | Static code audit — verify msg.sender checks | Trace sDGNRS -> Game -> LootboxModule permissions |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
