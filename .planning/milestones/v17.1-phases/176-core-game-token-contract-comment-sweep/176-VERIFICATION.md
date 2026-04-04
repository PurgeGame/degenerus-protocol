---
phase: 176-core-game-token-contract-comment-sweep
verified: 2026-04-03T22:00:00Z
status: gaps_found
score: 6/7 must-haves verified
re_verification: false
gaps:
  - truth: "ROADMAP and REQUIREMENTS.md reflect CMT-02 as complete and 176-01-PLAN as checked"
    status: partial
    reason: "176-01-FINDINGS.md exists, is substantive, and its commit (634d71af) exists in git history. However ROADMAP.md still marks 176-01-PLAN.md as '[ ]' unchecked and REQUIREMENTS.md still marks CMT-02 as '[ ] Pending'. The deliverable is complete; only the tracking documents are stale."
    artifacts:
      - path: ".planning/ROADMAP.md"
        issue: "Line 201: '- [ ] 176-01-PLAN.md' should be '- [x] 176-01-PLAN.md'; line 232 shows '2/3' plans complete"
      - path: ".planning/REQUIREMENTS.md"
        issue: "Line 9: CMT-02 checkbox is '[ ]' (Pending); line 38 traceability table says 'Pending'; should be Complete"
    missing:
      - "Check both '176-01-PLAN.md' checkbox in ROADMAP.md and CMT-02 checkbox in REQUIREMENTS.md to mark complete"
      - "Update ROADMAP progress table from '2/3 In Progress' to '3/3 Complete' for phase 176"
human_verification:
  - test: "Spot-check that DegenerusGame.sol line 239 reads '18h timeout' and BitPackingLib lines 69-75 define bits 184/185/209 as live fields"
    expected: "Line 239 should contain '18h timeout'; BitPackingLib should confirm HAS_DEITY_PASS_SHIFT=184, AFFILIATE_BONUS_LEVEL_SHIFT=185, AFFILIATE_BONUS_POINTS_SHIFT=209"
    why_human: "Automated grep confirmed the presence of these values; a human should confirm the finding severity (LOW) is appropriate given the discrepancy is within DegenerusGame.sol itself and does not affect runtime behavior"
---

# Phase 176: Core Game + Token Contract Comment Sweep — Verification Report

**Phase Goal:** Core game storage and all token contracts have accurate inline comments and NatSpec — every discrepancy logged as a finding
**Verified:** 2026-04-03T22:00:00Z
**Status:** gaps_found (tracking documents not updated for plan 01 completion)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | DegenerusGame (2524 lines) swept end-to-end | VERIFIED | 176-01-FINDINGS.md contains DGM-01 through DGM-04 with line refs; DGM-01 (line 14/76), DGM-02 (line 168-185), DGM-03 (line 239) independently confirmed against contracts/DegenerusGame.sol |
| 2 | DegenerusGameStorage (1649 lines) swept end-to-end | VERIFIED | DGST-01 (lines 427-434) confirmed; slot 0/1 layout, boon tiers, TICKET_SLOT_BIT, TICKET_FAR_FUTURE_BIT all explicitly verified as accurate in DGST-02 |
| 3 | BurnieCoin (717 lines) swept end-to-end | VERIFIED | 176-02-FINDINGS.md contains BC-01 through BC-07; BC-03 (burnCoin access control misstatement) and BC-06 (VaultAllowanceSpent spender field) confirmed against contracts/BurnieCoin.sol |
| 4 | BurnieCoinflip (1159 lines) swept end-to-end | VERIFIED | BCF-01 (onlyFlipCreditors lists BURNIE not in code) confirmed against contracts/BurnieCoinflip.sol lines 192-203; creditor expansion and mintForGame merger explicitly verified |
| 5 | DegenerusStonk (359 lines), GNRUS (547 lines), StakedDegenerusStonk (874 lines) swept | VERIFIED | 176-03-FINDINGS.md: G03-01 (GNRUS burnAtGameOver says DGNRS not sDGNRS) confirmed against contracts/GNRUS.sol line 337; G03-02 (vote() weight "fixed at 5%" vs balance+5% bonus) confirmed against contracts/GNRUS.sol lines 425-429; S03-02 (burnWrapped "convert DGNRS to sDGNRS credit") confirmed against contracts/StakedDegenerusStonk.sol line 489 |
| 6 | All discrepancies have severity (LOW/INFO), contract name, line reference, comment-vs-code description | VERIFIED | All 23 findings (10 LOW + 13 INFO across 3 plans) satisfy the format requirement. Every finding has an explicit severity, location, "Comment says" block, and "Code does" block |
| 7 | ROADMAP and REQUIREMENTS.md reflect plan 01 completion (CMT-02 marked complete) | FAILED | ROADMAP.md line 201 marks 176-01-PLAN as '[ ]' unchecked; REQUIREMENTS.md line 9 marks CMT-02 as '[ ]' Pending. The work is done (findings file exists, commit 634d71af confirmed in git history) but tracking was not updated |

**Score:** 6/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/176-core-game-token-contract-comment-sweep/176-01-FINDINGS.md` | Comment audit findings for DegenerusGame and DegenerusGameStorage (CMT-02) | VERIFIED | Exists, 185 lines, substantive. Contains `## DegenerusGameStorage` and `## DegenerusGame` sections. Header declares "2 LOW, 2 INFO" — confirmed: DGST-01 INFO, DGST-02 INFO (confirmed accurate, not a finding), DGM-01 LOW, DGM-02 LOW, DGM-03 LOW, DGM-04 INFO. Note: header says "2 LOW, 2 INFO" but actual distinct findings are 3 LOW + 1 INFO. See below. |
| `.planning/phases/176-core-game-token-contract-comment-sweep/176-02-FINDINGS.md` | Comment audit findings for BurnieCoin and BurnieCoinflip (CMT-03) | VERIFIED | Exists, 248 lines, substantive. Contains `## BurnieCoin` and `## BurnieCoinflip` sections. Summary table: 5 LOW + 7 INFO (12 findings). BCF-06 section heading remains but body explicitly marked "No finding — removing BCF-06" — minor formatting inelegance, not a material defect. |
| `.planning/phases/176-core-game-token-contract-comment-sweep/176-03-FINDINGS.md` | Comment audit findings for DegenerusStonk, GNRUS, StakedDegenerusStonk (CMT-03) | VERIFIED | Exists, 183 lines, substantive. Contains `## DegenerusStonk`, `## GNRUS`, `## StakedDegenerusStonk` sections. Header declares "3 LOW, 4 INFO" — confirmed: G03-01 LOW, G03-02 LOW, S03-02 LOW; D03-01 INFO, D03-02 INFO, G03-03 INFO, S03-01 INFO (S03-03 and S03-04 are verification confirmations, not findings). |

### Finding Count Reconciliation

**176-01-FINDINGS.md header says "2 LOW, 2 INFO" — actual finding count is 3 LOW + 1 INFO:**

- DGST-01: INFO (stale ETH_* reference)
- DGST-02: INFO — labeled "Verified Accurate" (not a discrepancy, confirmation note)
- DGM-01: LOW (stale 3-module list)
- DGM-02: LOW (mintPacked_ bit layout missing 30 live bits)
- DGM-03: LOW (18h timeout should be 12h)
- DGM-04: INFO — labeled "Verified Accurate" (not a discrepancy, confirmation note)

The file header says "2 LOW, 2 INFO" but 176-01-SUMMARY.md correctly says "3 LOW findings (not 2): DGM-01, DGM-02, DGM-03 are all LOW severity." The summary's `key-decisions` field documents the correction: "3 LOW findings (not 2)." The findings file header is inconsistent with the summary and with the actual findings, but all three LOW findings (DGM-01, DGM-02, DGM-03) are present with full documentation. This is a header typo in 176-01-FINDINGS.md, not a missing finding.

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| contracts/DegenerusGame.sol | 176-01-FINDINGS.md | line-by-line comparison | WIRED | DGM-01 (line 14/76), DGM-02 (lines 168-185), DGM-03 (line 239) all confirmed against actual file |
| contracts/storage/DegenerusGameStorage.sol | 176-01-FINDINGS.md | line-by-line comparison | WIRED | DGST-01 (lines 427-434) confirmed; slot 0 verified accurate per DGST-02 |
| contracts/BurnieCoin.sol | 176-02-FINDINGS.md | line-by-line comparison | WIRED | BC-03 (lines 559-562) confirmed; onlyGame modifier at line 505-507 confirmed GAME-only |
| contracts/BurnieCoinflip.sol | 176-02-FINDINGS.md | line-by-line comparison | WIRED | BCF-01 (lines 192-203) confirmed against actual modifier code |
| contracts/GNRUS.sol | 176-03-FINDINGS.md | line-by-line comparison | WIRED | G03-01 (line 337) confirmed "DGNRS" text present; G03-02 (lines 425-429) confirmed weight += bonus pattern |
| contracts/StakedDegenerusStonk.sol | 176-03-FINDINGS.md | line-by-line comparison | WIRED | S03-02 (line 489) confirmed "convert DGNRS to sDGNRS credit" text present |
| contracts/DegenerusStonk.sol | 176-03-FINDINGS.md | line-by-line comparison | WIRED | D03-01, D03-02 documented; DegenerusStonk is 359 lines and has 2 INFO findings |

### Data-Flow Trace (Level 4)

Not applicable. Phase deliverable is findings documentation, not runtime code. No data flows to verify.

### Behavioral Spot-Checks

Not applicable. The deliverable is audit findings files. No runnable entry points to test.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| CMT-02 | 176-01-PLAN | All core game + storage inline comments and NatSpec verified accurate (DegenerusGame, DegenerusGameStorage) | SATISFIED — findings complete; tracking doc stale | 176-01-FINDINGS.md exists with substantive findings; commit 634d71af confirmed in git. ROADMAP and REQUIREMENTS.md not updated (gap). |
| CMT-03 | 176-02-PLAN, 176-03-PLAN | All token contract inline comments and NatSpec verified accurate (BurnieCoin, BurnieCoinflip, DegenerusStonk, StakedDegenerusStonk, GNRUS) | SATISFIED | 176-02-FINDINGS.md (5 LOW, 7 INFO) and 176-03-FINDINGS.md (3 LOW, 4 INFO) both complete; REQUIREMENTS.md marks CMT-03 as [x] Complete |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| 176-01-FINDINGS.md | 5 | Header says "2 LOW, 2 INFO" but actual distinct findings are 3 LOW + 1 INFO | Warning | Inconsistency between findings file header and actual finding count; 176-01-SUMMARY.md corrects this in its key-decisions field. All findings are documented — nothing is missing. |
| 176-02-FINDINGS.md | 168 | BCF-06 section heading remains in file ("Finding BCF-06 — INFO") despite body stating "No finding — removing BCF-06" | Info | Minor formatting inelegance; the section body makes the intent clear and the summary table correctly excludes BCF-06. No material impact on audit usefulness. |

No stub implementations, placeholder content, or missing contract sweeps detected. All 7 contracts produce substantive findings with specific line references.

### Human Verification Required

#### 1. DGM-02 Severity Appropriateness

**Test:** Open `contracts/DegenerusGame.sol` lines 168-185 (MINT PACKED BIT LAYOUT comment block) and `contracts/libraries/BitPackingLib.sol` lines 10-24. Confirm the comment block says "[184-227] (reserved) - 44 unused bits" while BitPackingLib defines bits 184 (HAS_DEITY_PASS_SHIFT), 185-208 (AFFILIATE_BONUS_LEVEL_SHIFT), and 209-214 (AFFILIATE_BONUS_POINTS_SHIFT) as live storage fields.
**Expected:** Confirmed mismatch. Bits 184-213 (30 bits) are live, not reserved. The layout comment misleads a reader into believing these fields do not exist.
**Why human:** The finding is verified correct. Human judgment is useful to confirm the LOW severity assignment is appropriate for a layout comment that hides 30 live bits from a reader (vs. INFO). This is the highest-severity finding in plan 01.

---

### Gaps Summary

**One gap blocking full goal achievement:**

The phase work is substantively complete. All 7 contracts were swept, 176-01-FINDINGS.md through 176-03-FINDINGS.md exist with proper format, and all findings are corroborated against the actual contracts. However, the tracking state in ROADMAP.md and REQUIREMENTS.md was not updated after plan 01 completed:

- ROADMAP.md line 201 still shows `[ ] 176-01-PLAN.md` as unchecked
- ROADMAP.md progress table (line 232) shows "2/3 In Progress" instead of "3/3 Complete"
- REQUIREMENTS.md line 9 still marks CMT-02 as `[ ]` Pending
- REQUIREMENTS.md traceability table line 38 says CMT-02 is "Pending"

The underlying work exists (commit 634d71af, findings file on disk, summary file on disk). Only the tracking checkboxes need updating.

**The findings file header in 176-01-FINDINGS.md says "2 LOW, 2 INFO" but the actual findings include 3 LOW (DGM-01, DGM-02, DGM-03) + 1 INFO (DGST-01).** The summary correctly documents "3 LOW findings (not 2)" in its key-decisions field. This is a header typo in the findings file, not a missing finding.

---

## All Findings Summary (Phase 176 Total)

**Total: 11 LOW, 12 INFO** across all three plans

### Plan 01 (CMT-02): DegenerusGameStorage + DegenerusGame

| ID | Severity | Contract | Location | Description |
|----|----------|----------|----------|-------------|
| DGST-01 | INFO | DegenerusGameStorage | Lines 427-434 | mintPacked_ comment references "ETH_* constants in DegenerusGame" — actual source is BitPackingLib; deity pass flag (bit 184) and affiliate bonus cache (bits 185-214) not mentioned |
| DGM-01 | LOW | DegenerusGame | Lines 14, 76 | Contract NatSpec lists 3 modules (endgame, jackpot, mint); current code has 8 modules; "endgame" module name does not exist |
| DGM-02 | LOW | DegenerusGame | Lines 168-185 | MINT PACKED BIT LAYOUT marks bits 184-227 as "44 unused bits"; 30 of those bits (184-213) are live fields (deity pass flag, affiliate bonus cache) |
| DGM-03 | LOW | DegenerusGame | Line 239 | VRF timeout comment says "18h" — actual timeout is 12h (confirmed in AdvanceModule line 908) |

### Plan 02 (CMT-03): BurnieCoin + BurnieCoinflip

| ID | Severity | Contract | Location | Description |
|----|----------|----------|----------|-------------|
| BC-01 | INFO | BurnieCoin | Lines 183-189 | Orphaned struct doc blocks for PlayerScore and CoinflipDayResult — both structs live in BurnieCoinflip |
| BC-02 | INFO | BurnieCoin | Lines 265-279 | Orphaned BOUNTY STATE section with slot table — all three variables (currentBounty, biggestFlipEver, bountyOwedTo) live in BurnieCoinflip |
| BC-03 | LOW | BurnieCoin | Lines 559-562 | burnCoin NatSpec says "DegenerusGame, game, or affiliate" — onlyGame modifier allows GAME only |
| BC-04 | LOW | BurnieCoin | Line 448 | burnForCoinflip is COINFLIP-only but reverts with OnlyGame() error name |
| BC-05 | LOW | BurnieCoin | Lines 452-460 | mintForGame is COINFLIP-or-GAME but reverts with OnlyGame() error name |
| BC-06 | INFO | BurnieCoin | Lines 82-84 | VaultAllowanceSpent event emits address(this) as spender, not the actual vault caller |
| BC-07 | INFO | BurnieCoin | Lines 525-528 | vaultEscrow NatSpec says "game contract and modules" — VAULT is also an authorized caller |
| BCF-01 | LOW | BurnieCoinflip | Lines 192-203 | onlyFlipCreditors NatSpec lists BURNIE as allowed; BURNIE (ContractAddresses.COIN) is absent from the actual code check |
| BCF-02 | INFO | BurnieCoinflip | Lines 892-893 | creditFlip NatSpec omits QUESTS as authorized caller |
| BCF-03 | INFO | BurnieCoinflip | Lines 903-904 | creditFlipBatch NatSpec omits QUESTS as authorized caller |
| BCF-04 | LOW | BurnieCoinflip | Lines 352-364 | claimCoinflipsForRedemption says "skips RNG lock" — only unconditionally true for sDGNRS caller |
| BCF-05 | INFO | BurnieCoinflip | Lines 813-814 | Presale max "156%" is accurate only for 1/20 lucky roll; typical presale max is 121% |

### Plan 03 (CMT-03): DegenerusStonk + GNRUS + StakedDegenerusStonk

| ID | Severity | Contract | Location | Description |
|----|----------|----------|----------|-------------|
| D03-01 | INFO | DegenerusStonk | Line 57 | GameNotOver error comment says "use burnWrapped() instead" without specifying it lives on StakedDegenerusStonk |
| D03-02 | INFO | DegenerusStonk | Line 68 | BurnThrough event comment says "burned through to sDGNRS" — actual flow burns FROM sDGNRS, not to it |
| G03-01 | LOW | GNRUS | Lines 337-340 | burnAtGameOver NatSpec says "VAULT, DGNRS, and GNRUS" — gameover module sends to VAULT, sDGNRS, and GNRUS (cross-confirmed with Phase 175 G05-01) |
| G03-02 | LOW | GNRUS | Lines 410-411 | vote() NatSpec says vault owner weight "fixed at 5% of the sDGNRS snapshot" — actual code adds 5% bonus on top of their own balance weight |
| G03-03 | INFO | GNRUS | Lines 279-281 | burn() last-holder sweep says "all non-contract GNRUS" — actual condition is "all externally-held GNRUS" including contracts |
| S03-01 | INFO | StakedDegenerusStonk | Lines 280-281 | Constructor NatSpec omits setAfKingMode call (game.setAfKingMode(address(0), true, 10 ether, 0)) |
| S03-02 | LOW | StakedDegenerusStonk | Line 489 | burnWrapped() NatSpec says "convert DGNRS to sDGNRS credit, then burns the resulting sDGNRS" — no conversion occurs; pre-existing sDGNRS backing balance is consumed |

---

_Verified: 2026-04-03T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
