---
phase: 68
slug: commitment-window-inventory
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 68 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (forge test) |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge test --match-path test/fuzz/*.sol -vv` |
| **Full suite command** | `forge test -vv` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Manual review of catalog completeness against source
- **After every plan wave:** Cross-reference catalog entries with `forge inspect` output
- **Before `/gsd:verify-work`:** Full catalog review against all VRF paths
- **Max feedback latency:** N/A (documentation-only phase)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 68-01-01 | 01 | 1 | CW-01 | manual-only | N/A | N/A | ⬜ pending |
| 68-01-02 | 01 | 1 | CW-02 | manual-only | N/A | N/A | ⬜ pending |
| 68-01-03 | 01 | 1 | CW-03 | manual-only | N/A | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test files needed for this documentation-only phase.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Forward-trace catalog completeness | CW-01 | Phase produces documentation, not code. Catalog completeness can only be verified by human review against source. | Run `forge inspect DegenerusGameStorage storage-layout`, trace rawFulfillRandomWords forward through all consumers, verify every touched variable appears in catalog. |
| Backward-trace catalog completeness | CW-02 | Backward traces require semantic understanding of outcome computation paths. | For each outcome type (coinflip, jackpot ETH, jackpot coin, lootbox, redemption, prize pool), trace backward from result to all input variables, verify all appear in catalog. |
| Mutation surface completeness | CW-03 | "Is this list complete?" requires human review of all external functions. | For each cataloged variable, grep all external/public functions that write to it, verify all appear in mutation surface listing with correct call-graph depth. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < N/A (documentation phase)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
