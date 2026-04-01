---
phase: 44
slug: delta-audit-redemption-correctness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 44 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry v1.0 (forge test) |
| **Config file** | `foundry.toml` |
| **Quick run command** | `forge build` |
| **Full suite command** | `forge test -v` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** `forge build` (verify any proposed fix compiles)
- **After every plan wave:** Verify all requirement verdicts have supporting evidence
- **Before `/gsd:verify-work`:** All 12 requirements have verdicts with evidence
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 44-01-01 | 01 | 1 | DELTA-03 | manual | N/A — code comparison | N/A | ⬜ pending |
| 44-01-02 | 01 | 1 | DELTA-04 | manual | N/A — code trace | N/A | ⬜ pending |
| 44-01-03 | 01 | 1 | DELTA-05 | manual | N/A — msg.sender trace | N/A | ⬜ pending |
| 44-01-04 | 01 | 1 | DELTA-06 | manual | N/A — code trace | N/A | ⬜ pending |
| 44-01-05 | 01 | 1 | DELTA-07 | manual | N/A — code trace | N/A | ⬜ pending |
| 44-02-01 | 02 | 1 | CORR-01 | manual | N/A — lifecycle trace | N/A | ⬜ pending |
| 44-02-02 | 02 | 1 | DELTA-01 | manual | N/A — accounting trace | N/A | ⬜ pending |
| 44-02-03 | 02 | 1 | CORR-02 | manual | N/A — solvency proof | N/A | ⬜ pending |
| 44-02-04 | 02 | 1 | DELTA-02 | manual | N/A — interaction audit | N/A | ⬜ pending |
| 44-02-05 | 02 | 1 | CORR-03 | manual | N/A — CEI trace | N/A | ⬜ pending |
| 44-02-06 | 02 | 1 | CORR-04 | manual | N/A — state machine analysis | N/A | ⬜ pending |
| 44-02-07 | 02 | 1 | CORR-05 | manual | N/A — supply invariant trace | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a pure audit analysis phase — no test stubs or fixtures needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CP-08 double-spend | DELTA-03 | Code comparison between 3 functions | Compare totalMoney formula in _deterministicBurnFrom, previewBurn, _submitGamblingClaimFrom |
| CP-06 stuck claims | DELTA-04 | Code path trace | Verify _gameOverEntropy vs rngGate — does each call resolveRedemptionPeriod? |
| Seam-1 fund trap | DELTA-05 | Cross-contract msg.sender trace | Trace DGNRS.burn() → stonk.burn() msg.sender value |
| CP-02 zero sentinel | DELTA-06 | Day index domain analysis | Verify GameTimeLib returns ≥ 1 for all post-deploy timestamps |
| CP-07 coinflip dependency | DELTA-07 | Boundary condition analysis | Trace flipDay dependency at game-over boundary |
| Redemption lifecycle | CORR-01 | 3-phase state machine trace | Document submit → resolve → claim transitions |
| Segregation solvency | CORR-02 | Invariant proof | Prove pendingRedemptionEthValue ≤ holdings at every step |
| CEI compliance | CORR-03 | External call graph analysis | Map state-at-call-point for all external calls in claimRedemption |
| Period state machine | CORR-04 | Monotonicity analysis | Verify period index advances correctly, 50% cap enforced |
| Supply invariant | CORR-05 | Dual burn trace | Verify DGNRS and sDGNRS supply decrease correctly through burnWrapped |
| Accounting reconciliation | DELTA-01 | Rounding analysis | Trace pendingRedemptionEthValue through submit/resolve/claim |
| Cross-contract interaction | DELTA-02 | 4-contract state consistency | Map all external calls and verify state consistency |

**Justification:** Phase 44 is an analytical audit producing confirmed/refuted verdicts with severity classifications. Automated invariant tests are sequenced in Phase 45 after this phase's findings are resolved.

---

## Validation Sign-Off

- [x] All tasks have manual verify with detailed test instructions
- [x] Sampling continuity: each task produces auditable evidence (verdict + code references)
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency < 30s (forge build only)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
