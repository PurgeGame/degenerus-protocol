---
phase: 10
slug: reward-systems-and-modifiers
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification (documentation-only phase) |
| **Config file** | none — no code changes |
| **Quick run command** | `grep -c "##" audit/v1.1-dgnrs-tokenomics.md audit/v1.1-deity-system.md audit/v1.1-affiliate-system.md audit/v1.1-steth-yield.md audit/v1.1-quest-rewards.md` |
| **Full suite command** | `grep -cE "DGNR-0[1-4]" audit/v1.1-dgnrs-tokenomics.md && grep -cE "DEIT-0[1-3]" audit/v1.1-deity-system.md && grep -cE "AFFL-0[1-3]" audit/v1.1-affiliate-system.md && grep -cE "STETH-0[1-2]" audit/v1.1-steth-yield.md && grep -cE "QRWD-0[1-2]" audit/v1.1-quest-rewards.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify document section completeness
- **After every plan wave:** Cross-reference all formulas against contract source
- **Before `/gsd:verify-work`:** All 14 requirements (DGNR-01–04, DEIT-01–03, AFFL-01–03, STETH-01–02, QRWD-01–02) must have exact contract values
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | DGNR-01, DGNR-02, DGNR-03, DGNR-04 | manual | `grep -c "DGNR" audit/v1.1-dgnrs-tokenomics.md` | N/A | ⬜ pending |
| 10-02-01 | 02 | 1 | DEIT-01, DEIT-02, DEIT-03 | manual | `grep -c "DEIT" audit/v1.1-deity-system.md` | N/A | ⬜ pending |
| 10-03-01 | 03 | 1 | AFFL-01, AFFL-02, AFFL-03 | manual | `grep -c "AFFL" audit/v1.1-affiliate-system.md` | N/A | ⬜ pending |
| 10-04-01 | 04 | 1 | STETH-01, STETH-02 | manual | `grep -c "STETH" audit/v1.1-steth-yield.md` | N/A | ⬜ pending |
| 10-05-01 | 05 | 1 | QRWD-01, QRWD-02 | manual | `grep -c "QRWD" audit/v1.1-quest-rewards.md` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Documentation-only phase — no test framework needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| DGNRS token distribution amounts | DGNR-01 | Documentation accuracy | Cross-reference pool allocations against DegenerusStonk.sol constants |
| Deity pass pricing curve | DEIT-01 | Formula verification | Verify triangular number formula against WhaleModule |
| Affiliate reward flows | AFFL-01 | Economic flow tracing | Trace ETH/DGNRS paths through DegenerusAffiliate.sol |
| stETH yield mechanics | STETH-01 | Integration verification | Verify yield surplus calculation against DegenerusGame.sol |
| Quest reward values | QRWD-01 | Value extraction | Confirm BURNIE amounts against DegenerusQuests.sol constants |

---

## Validation Sign-Off

- [x] All tasks have manual verification criteria
- [x] Sampling continuity: documentation phases verified per-section
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
