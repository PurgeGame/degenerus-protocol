---
phase: 9
slug: level-progression-and-endgame
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification (documentation-only phase) |
| **Config file** | none — no code changes |
| **Quick run command** | `grep -c "##" audit/level-progression-and-endgame.md` |
| **Full suite command** | `grep -cE "LEVL-0[1-4]|END-0[1-2]" audit/level-progression-and-endgame.md` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Verify document section completeness
- **After every plan wave:** Cross-reference all formulas against contract source
- **Before `/gsd:verify-work`:** All six requirements (LEVL-01 through LEVL-04, END-01, END-02) must have exact contract values
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | LEVL-01 | manual | `grep "price" audit/level-progression-and-endgame.md` | n/a | pending |
| 09-01-02 | 01 | 1 | LEVL-02 | manual | `grep "purchase target" audit/level-progression-and-endgame.md` | n/a | pending |
| 09-01-03 | 01 | 1 | LEVL-03 | manual | `grep "whale bundle\|lazy pass" audit/level-progression-and-endgame.md` | n/a | pending |
| 09-02-01 | 02 | 1 | LEVL-04 | manual | `grep "activity" audit/level-progression-and-endgame.md` | n/a | pending |
| 09-02-02 | 02 | 1 | END-01 | manual | `grep "death clock" audit/level-progression-and-endgame.md` | n/a | pending |
| 09-02-03 | 02 | 1 | END-02 | manual | `grep "terminal\|gameOver" audit/level-progression-and-endgame.md` | n/a | pending |

*Status: pending*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. (Documentation-only phase — no test framework needed.)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Price curve formulas match PriceLookupLib.sol | LEVL-01 | Documentation accuracy requires human review | Cross-reference every ETH price against contract source |
| Purchase target formula matches AdvanceModule.sol | LEVL-02 | Must verify Solidity expressions against contract | Check purchaseTarget calculation against advanceGame logic |
| Whale bundle/lazy pass level economics | LEVL-03 | Must verify duration/cost changes per level | Cross-reference PurchaseModule whale/lazy paths |
| Activity score BPS components | LEVL-04 | Must verify all 6 activity score components | Search for activityScore calculations in contract source |
| Death clock timing constants | END-01 | Must verify timeout/distress values | Check AdvanceModule timeout logic |
| Terminal distribution formulas | END-02 | Must verify gameOver payout splits | Check EndgameModule distribution logic |

---

## Validation Sign-Off

- [x] All tasks have verification criteria
- [x] Sampling continuity: documentation phase — continuous review
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
