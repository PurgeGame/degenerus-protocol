---
phase: 1
slug: storage-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) via Solidity 0.8.34, via_ir=true |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-test testTicketSlotKeys -vvv` |
| **Full suite command** | `forge test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge clean && forge build` (zero warnings check)
- **After every plan wave:** Run `forge test` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | STOR-01 | smoke (forge inspect) | `forge inspect DegenerusGameStorage storage-layout` | No -- Wave 0 | ⬜ pending |
| 01-01-02 | 01 | 1 | STOR-02 | unit | `forge test --match-test testPrizePoolPacking -vvv` | No -- Wave 0 | ⬜ pending |
| 01-01-03 | 01 | 1 | STOR-03 | unit | `forge test --match-test testPendingPoolPacking -vvv` | No -- Wave 0 | ⬜ pending |
| 01-01-04 | 01 | 1 | STOR-04 | unit | `forge test --match-test testTicketSlotKeys -vvv` | No -- Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/StorageFoundation.t.sol` — new test file for STOR-01 through STOR-04
  - Test: `testSlot1FieldOffsets` — verify `ticketWriteSlot`, `ticketsFullyProcessed`, `prizePoolFrozen` at expected offsets
  - Test: `testPrizePoolPackingRoundTrip` — set/get for prizePoolsPacked with boundary values (0, max uint128, mixed)
  - Test: `testPendingPoolPackingRoundTrip` — same for prizePoolPendingPacked
  - Test: `testTicketSlotKeys` — for ticketWriteSlot=0 and ticketWriteSlot=1, assert `_tqWriteKey(level) != _tqReadKey(level)`
  - Test: `testTicketSlotKeyBit23Isolation` — verify bit 23 is set on one and not the other
- [ ] Test harness: a minimal contract that inherits `DegenerusGameStorage` and exposes internal functions for testing

*Existing infrastructure covers framework installation — no gaps.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Storage layout byte offsets | STOR-01 | forge inspect output needs human review | Run `forge inspect DegenerusGameStorage storage-layout` and verify byte offsets in Slot 1 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
