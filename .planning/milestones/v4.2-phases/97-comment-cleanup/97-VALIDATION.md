---
phase: 97
slug: comment-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-25
---

# Phase 97 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge) + Hardhat (mocha/chai) |
| **Config file** | `foundry.toml`, `hardhat.config.ts` |
| **Quick run command** | `forge build` |
| **Full suite command** | `forge build && forge test --summary` |
| **Estimated runtime** | ~30 seconds (build only; comment-only changes have no runtime effect) |

---

## Sampling Rate

- **After every task commit:** Run `forge build`
- **After every plan wave:** Run `forge build`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 97-01-01 | 01 | 1 | CMT-01 | compilation | `forge build` | N/A | pending |
| 97-01-02 | 01 | 1 | CMT-01 | compilation + grep | `forge build && grep -rn "Chunk\|chunk" contracts/modules/DegenerusGameJackpotModule.sol` | N/A | pending |
| 97-01-03 | 01 | 1 | CMT-01 | compilation + grep | `forge build && grep -rn "dailyEthBucketCursor\|chunkProcessed\|chunkWinners\|lastBucketProcessed\|currentBucketIndex\|DAILY_JACKPOT_GAS_LIMIT" contracts/` | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Comment changes are verified by compilation (no syntax breaks) and manual review of diff against `forge inspect DegenerusGame storage` output.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Storage layout comment byte offsets match forge inspect output | CMT-01 | Comment content accuracy cannot be tested programmatically | Compare diff of DegenerusGameStorage.sol comments against `forge inspect DegenerusGame storage` field-by-field |
| NatSpec @param/@return tags match function signatures | CMT-01 | Semantic accuracy of NatSpec descriptions is a human judgment | Review diff of JackpotModule NatSpec additions against function parameters |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
