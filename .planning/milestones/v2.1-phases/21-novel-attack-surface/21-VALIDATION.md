---
phase: 21
slug: novel-attack-surface
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hardhat (Mocha/Chai) + Foundry fuzz |
| **Config file** | hardhat.config.js / foundry.toml |
| **Quick run command** | `npx hardhat test test/DGNRSLiquid.test.js test/sDGNRS*.test.js` |
| **Full suite command** | `npx hardhat test` |
| **Estimated runtime** | ~60 seconds (focused) / ~300 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `npx hardhat test test/DGNRSLiquid.test.js test/sDGNRS*.test.js`
- **After every plan wave:** Run `npx hardhat test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 1 | NOVEL-01 | doc review | `grep -c "MEV\|sandwich\|flash.loan" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-01-02 | 01 | 1 | NOVEL-12 | doc review | `grep -c "amplifier\|transferable" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-01-03 | 01 | 1 | NOVEL-02 | doc review | `grep -c "composition\|cross-contract" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-02-01 | 02 | 1 | NOVEL-03 | doc review | `grep -c "griefing\|DoS" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-02-02 | 02 | 1 | NOVEL-04 | doc review | `grep -c "zero.*amount\|max.*uint\|dust\|rounding" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-02-03 | 02 | 1 | NOVEL-05 | doc + test | `grep -c "invariant\|conservation" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-03-01 | 03 | 1 | NOVEL-09 | doc review | `grep -c "privilege\|escalation\|onlyGame" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-03-02 | 03 | 1 | NOVEL-10 | doc review | `grep -c "rebase\|stETH\|oracle" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |
| 21-03-03 | 03 | 1 | NOVEL-11 | doc review | `grep -c "race.*condition\|game.over\|concurrent" docs/novel-attack-surface-report.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. Phase 21 is documentation-heavy (attack analysis reports). No new test infrastructure needed, though invariant tests may be added.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Economic EV calculations | NOVEL-01 | Requires manual math review | Verify flash loan profitability math, sandwich EV |
| stETH rebase magnitude | NOVEL-10 | Requires current APR data | Check Lido oracle timing against burn() trace |

*Most verifications are doc-completeness checks (grep-verifiable).*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
