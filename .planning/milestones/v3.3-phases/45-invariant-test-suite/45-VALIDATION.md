---
phase: 45
slug: invariant-test-suite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 45 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) |
| **Config file** | foundry.toml |
| **Quick run command** | `forge test --match-path test/invariant/RedemptionInvariant.t.sol -vv` |
| **Full suite command** | `forge test --match-path test/invariant/RedemptionInvariant.t.sol -vvv` |
| **Estimated runtime** | ~30-60 seconds (256 runs, depth 128) |

---

## Sampling Rate

- **After every task commit:** Run `forge test --match-path test/invariant/RedemptionInvariant.t.sol -vv`
- **After every plan wave:** Run `forge test --match-path test/invariant/RedemptionInvariant.t.sol -vvv`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 45-01-01 | 01 | 1 | INV-01 thru INV-07 | invariant | `forge test --match-path test/invariant/RedemptionInvariant.t.sol -vv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/invariant/RedemptionInvariant.t.sol` — invariant test contract with 7 invariant functions
- [ ] `test/invariant/handlers/RedemptionHandler.sol` — handler contract driving burn/resolve/claim lifecycle

*Existing Foundry invariant infrastructure covers framework requirements.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
