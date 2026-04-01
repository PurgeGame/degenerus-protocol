---
phase: 38
slug: rng-delta-security
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 38 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat + Mocha/Chai (existing), Foundry for fuzz tests |
| **Config file** | `hardhat.config.js`, `foundry.toml` |
| **Quick run command** | `npx hardhat test test/unit/BurnieCoinflip.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/unit/BurnieCoinflip.test.js`
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 38-01-01 | 01 | 1 | RNG-01 | audit/trace | Manual code trace + document | N/A | ⬜ pending |
| 38-01-02 | 01 | 1 | RNG-02 | audit/trace | Manual code trace + document | N/A | ⬜ pending |
| 38-02-01 | 02 | 1 | RNG-03 | audit/trace | Manual code trace + document | N/A | ⬜ pending |
| 38-02-02 | 02 | 1 | RNG-04 | audit/trace | Manual code trace + document | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Phase 38 is an audit/documentation phase — deliverables are security findings documents, not code changes.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Carry isolation proof | RNG-01 | Code trace requires human judgment on safety | Trace all writes to autoRebuyCarry and claimableStored, verify no cross-contamination |
| BAF guard sufficiency | RNG-02 | Enumeration of bypass scenarios requires adversarial reasoning | List all conditions, verify no bypass path exists |
| Decimator persistence correctness | RNG-03 | Storage migration correctness requires state analysis | Verify double-claim prevention and ETH accounting across rounds |
| Cross-contract RNG matrix | RNG-04 | Dependency analysis requires cross-contract reasoning | Build matrix of all rngLocked consumers, verify each is still safe |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
