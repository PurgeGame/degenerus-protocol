---
phase: 65
slug: vrf-stall-edge-cases
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 65 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) with Solidity 0.8.34 |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-path test/fuzz/VRFStallEdgeCases.t.sol -vvv` |
| **Full suite command** | `forge test --fuzz-runs 1000 -vvv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path test/fuzz/VRFStallEdgeCases.t.sol -vvv`
- **After every plan wave:** Run `forge test --fuzz-runs 1000 -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 65-01-01 | 01 | 1 | STALL-01 | fuzz | `forge test --match-test test_gapBackfillEntropy -vvv` | ❌ W0 | ⬜ pending |
| 65-01-02 | 01 | 1 | STALL-02 | unit + analysis | `forge test --match-test test_manipulationWindow -vvv` | ❌ W0 | ⬜ pending |
| 65-01-03 | 01 | 1 | STALL-03 | gas-report | `forge test --match-test test_gapBackfillGas --gas-report -vvv` | ❌ W0 | ⬜ pending |
| 65-01-04 | 01 | 1 | STALL-04 | unit + fuzz | `forge test --match-test test_coordinatorSwap -vvv` | ❌ W0 | ⬜ pending |
| 65-01-05 | 01 | 1 | STALL-05 | unit | `forge test --match-test test_zeroSeed -vvv` | ❌ W0 | ⬜ pending |
| 65-01-06 | 01 | 1 | STALL-06 | unit + analysis | `forge test --match-test test_gameoverFallback -vvv` | ❌ W0 | ⬜ pending |
| 65-01-07 | 01 | 1 | STALL-07 | unit + analysis | `forge test --match-test test_dailyIdxTiming -vvv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fuzz/VRFStallEdgeCases.t.sol` — new file covering STALL-01 through STALL-07
- [ ] No new framework install needed (Foundry already configured)
- [ ] No new helpers needed (StallResilience.t.sol patterns reusable)

*Existing infrastructure covers framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Manipulation window analysis | STALL-02 | Requires code reasoning about MEV timing | Read _backfillOrphanedDays and document the window between VRF callback and advanceGame consumption |
| prevrandao sequencer bias | STALL-06 | L2 sequencer property, not testable in Foundry | Document 1-bit manipulation on gameover+VRF-death edge case |
| dailyIdx consistency audit | STALL-07 | Requires systematic code read across contracts | Grep all block.timestamp usages, verify each is appropriate for context |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
