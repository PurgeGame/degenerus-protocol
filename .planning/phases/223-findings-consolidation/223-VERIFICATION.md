---
phase: 223-findings-consolidation
verified: 2026-04-12T00:00:00Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 0
requirements_covered: [CSI-12, CSI-13, CSI-14]
requirements_also_flipped: [CSI-08, CSI-09, CSI-10]
human_verification:
  - test: "Reconcile FINDINGS-v27.0.md Audit Date vs re-verification date"
    expected: "Either change `Audit Date: 2026-04-13` to `2026-04-12` to match the 222-VERIFICATION.md `verified: 2026-04-12T00:00:00Z` timestamp cited in F-27-13/F-27-14 Status blocks, OR add a one-line clarification that 2026-04-13 is the publication target date"
    why_human: "Per 223-REVIEW IN-02: the audit date is one day in the future relative to verification dates referenced in the document body. Either direction is defensible; needs the user to decide publication semantics."
  - test: "Fix stale line reference in F-27-16 sub-point B"
    expected: "Sub-point B currently cites `scripts/coverage-check.sh:200-204` (pre-fix line range copied verbatim from 222-REVIEW IN-222-04). Post-fix the LCOV_FILE missing-file WARN logic now lives at `:230-232` after Plan 222-03's 45-line preflight matrix parser shift. Update to current lines or add `(pre-fix)` marker matching F-27-14's convention."
    why_human: "Per 223-REVIEW IN-01: the line number drift is internal to the document (not in the codebase); human should confirm the convention — keep pre-fix line numbers with marker, or bump to post-fix lines. The document mixes both styles elsewhere."
  - test: "Clarify Executive Summary count ambiguity"
    expected: "The Executive Summary sentence at line 21 interleaves must-haves-verified counts (9/9, 13/13, 4/4) with finding-tier breakdowns (3 WR + 5 IN etc.) inside the same parenthetical. Readers may misread 9/9 as a finding count. Suggested rewrite: 'Phase 220 satisfied 9/9 must-have truths with 3 WR + 5 IN raw review findings consolidated to 6 INFO entries; Phase 221 satisfied 13/13 with 2 WR + 3 IN consolidated to 5 INFO (2 resolved in-cycle)...'"
    why_human: "Per 223-REVIEW IN-03: pure prose-clarity decision. The numbers are all technically correct; the question is whether the mixed-metric phrasing is acceptable or needs separation. User may prefer the current compact form."
  - test: "Reconcile '5 observations resolved in-cycle' vs 4 finding-ID-level Resolved markers"
    expected: "Executive Summary says 'Five observations were resolved in-cycle and carry resolving commit shas below' but grep for `Status: Resolved` returns 5 sub-point-level hits that map to 4 finding-ID-level entries (F-27-07, F-27-08, F-27-13 [with 2 sub-points], F-27-14). Either add a one-line footnote '(counted at sub-point granularity)' or rephrase to 'Four findings carry resolving commit shas; F-27-13 contains two sub-points both closed by commit `ef83c5cd`'"
    why_human: "Per 223-REVIEW IN-04: the 5-vs-4 gap is internally consistent but un-signposted. Reader-facing clarity call."
  - test: "Tighten F-25-08 evidence quote and line range"
    expected: "F-25-08 regression row cites `DegenerusGameAdvanceModule.sol:1191-1221` and the quoted comment 'prevrandao adds unpredictability at the cost of 1-bit bias'. Actual: the function body `_getHistoricalRngFallback` is at :1200-1224 (docstring at :1189-1199). The live comment verbatim at :1192 reads 'prevrandao adds unpredictability at the cost of 1-bit **validator manipulation**', not '1-bit bias'. Quoted text should match verbatim or drop the single-quotes signaling a verbatim quote."
    why_human: "Per 223-REVIEW IN-05: I confirmed the live comment at DegenerusGameAdvanceModule.sol:1192 says '1-bit' + continues at :1193 with 'validator manipulation'. The 'bias' paraphrase is a reasonable shortening but misleads grep-based verification."
  - test: "Add post-fix location marker for F-27-14 Function field"
    expected: "F-27-14 Function field reads `check_matrix_drift` `:89-164` (pre-fix, specifically the global `grep -qF` at `:104`). An auditor navigating the current-tree file goes to :89 and finds the preflight matrix parser, not the drift-check function. Fix: append post-fix location, e.g., `:89-164` (pre-fix ...; post-fix the function lives at `:118-164`)."
    why_human: "Per 223-REVIEW IN-06: navigational aid only — same convention is used correctly on F-27-07/F-27-08 which cite both pre-fix and post-fix anchors. Consistency call."
---

# Phase 223: Findings Consolidation Verification Report

**Phase Goal:** All v27.0 audit findings are severity-classified and rolled up into `audit/FINDINGS-v27.0.md`; design-decision items are promoted to `KNOWN-ISSUES.md`; v27.0 is marked SHIPPED.
**Verified:** 2026-04-12T00:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal is met on all observable truths: `audit/FINDINGS-v27.0.md` exists (392 lines, 16 F-27-NN findings, full v25.0 regression appendix), `KNOWN-ISSUES.md` has 3 new v27.0 design-decision entries referencing F-27-NN IDs, `MILESTONES.md` has the v27.0 retrospective block, `PROJECT.md` moved v27.0 from Current to Completed with narrative preserved, and all 14/14 CSI requirements are flipped to `[x]` / Complete.

However, the phase's own 223-REVIEW.md (dated 2026-04-12) produced 6 INFO-level accuracy/clarity observations on `audit/FINDINGS-v27.0.md` that were never addressed by a follow-up commit (`git log d22a7d98..HEAD` is empty). These are not goal-blocking but the user should decide whether to land fixes before declaring v27.0 fully shipped — each is a one-line edit to the FINDINGS doc and costs nothing to apply. They are surfaced below under `human_verification:`.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `audit/FINDINGS-v27.0.md` exists with every warning and info item from phases 220/221/222 severity-classified | VERIFIED | File exists (392 lines); 16 F-27-NN findings present (F-27-01..F-27-16); source-item mapping table in 223-01-SUMMARY.md accounts for every WR-* / IN-* / Gap item from 220/221/222 REVIEW and VERIFICATION files |
| 2 | FINDINGS-v27.0.md follows FINDINGS-v25.0.md structure (Exec Summary severity table, per-phase subsections with field tables, regression appendix) | VERIFIED | Header lines 1-6 mirror v25.0 format; Executive Summary severity table at lines 12-19 matches v25.0 pattern (0 CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW / 16 INFO); three Phase subsections (220, 221, 222) at lines 29, 125, 206; Regression Appendix at line 353 |
| 3 | Resolved-in-cycle items (WR-221-01, WR-221-02, WR-222-02, WR-222-03, WR-222-04, Gap 1, Gap 2) carry Status: Resolved in v27.0 with resolving commit sha | VERIFIED | 5 `Status: Resolved in v27.0` markers in FINDINGS-v27.0.md; commits `f799da98` (F-27-07, F-27-08), `ef83c5cd` (F-27-13 sub-points A+B), `e0a1aa3e` (F-27-14) all confirmed in `git log --all --oneline` |
| 4 | Regression Appendix verifies every v25.0 finding (F-25-01..F-25-13) with HOLDS/SUPERSEDED/FIXED/INVALIDATED tag and rationale | VERIFIED | Appendix at lines 363-377 covers all 13 F-25-NN with tags: 12 HOLDS + 1 SUPERSEDED (F-25-09) + 0 FIXED + 0 INVALIDATED; spot-check confirmed live code: `deityBoonData` at `DegenerusGame.sol:839-860` with `keccak256(day, address(this))` fallback at line 859 matches F-25-09 SUPERSEDED evidence; `_getHistoricalRngFallback` at `DegenerusGameAdvanceModule.sol:1200` matches F-25-08 HOLDS evidence |
| 5 | v26.0 regression gap noted explicitly in appendix preamble | VERIFIED | Line 23 of Exec Summary and line 355 of Regression Appendix both state 'No separate FINDINGS-v26.0.md document exists' with reason (design-focused, captured in MILESTONES.md) |
| 6 | Verbatim D-07 scope-framing sentence appears in preamble | VERIFIED | Grep for 'Call-site integrity audit covering three axes' returns 1 match at line 5 (byte-identical to CONTEXT D-07 spec) |
| 7 | KNOWN-ISSUES.md has accepted INFO/LOW items from v27.0 meeting D-08 criteria | VERIFIED | 3 new bolded entries at KNOWN-ISSUES.md:38,40,42 each referencing an F-27-NN ID and `audit/FINDINGS-v27.0.md`; total bolded-entry count rose from 34 (pre-edit) to 37 (post-edit per 223-02-SUMMARY.md); all 3 entries sit inside `## Design Decisions` section |
| 8 | MILESTONES.md has v27.0 Call-Site Integrity Audit entry mirroring v26.0 format | VERIFIED | `## v27.0 Call-Site Integrity Audit (Shipped: 2026-04-13)` at line 3 (most-recent-first ordering); `**Phases completed:** 4 phases, 9 plans, 23 tasks` header; 7 Key accomplishments bullets covering delegatecall gate, raw-selector gate, coverage matrix, coverage-check gate, CoverageGap222.t.sol tests, FINDINGS-v27.0.md, KNOWN-ISSUES update |
| 9 | PROJECT.md moves v27.0 from Current to Completed with narrative preserved | VERIFIED | `## Current Milestone: TBD — pending roadmap planning` at line 11; `## Completed Milestone: v27.0 Call-Site Integrity Audit` at line 15 with `**Goal / Target scope / Incident context:**` label at line 19 containing the migrated verbatim pre-edit narrative (Goal paragraph, Target scope bullets, Prior incident context paragraph); grep confirms `Systematically surface runtime call-site-to-implementation mismatches` (Goal opening), `Delegatecall target alignment across all` (Target scope bullet 1), `mintPackedFor(address)..was declared` (Incident context opening) all present |
| 10 | REQUIREMENTS.md flips all 14/14 CSI-NN checkboxes to [x] and traceability rows to Complete | VERIFIED | `grep -c '\[x\] \*\*CSI-'` returns 14; `grep -c '\[ \] \*\*CSI-'` returns 0; traceability table shows `Complete` for all 14 rows (CSI-01..CSI-14); `Pending` does not appear anywhere in the file |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `audit/FINDINGS-v27.0.md` | Severity-classified consolidated findings with full v25.0 regression appendix; contains F-27-01..F-27-15 (target) + F-25-01..F-25-13 | VERIFIED | 392 lines; 16 F-27-NN findings (within 14-16 range); 13 F-25-NN regression entries; structure mirrors v25.0 byte-for-byte on section headings and field-table schema |
| `KNOWN-ISSUES.md` | Updated Design Decisions section referencing F-27-NN IDs | VERIFIED | 3 new entries appended to `## Design Decisions` section; 3 `F-27-` references (F-27-12, F-27-05, F-27-13 + F-27-14); existing entries unchanged |
| `.planning/MILESTONES.md` | v27.0 retrospective entry at top (most-recent-first) | VERIFIED | Entry at line 3; 7 accomplishments bullets; `177+1 CRITICAL_GAP` wording present; `16 INFO findings` wording present |
| `.planning/PROJECT.md` | v27.0 moved to Completed Milestone with narrative preserved | VERIFIED | Current Milestone set to TBD at line 11; Completed Milestone v27.0 block at line 15 with migrated Goal / Target scope / Incident context narrative under explicit label |
| `.planning/REQUIREMENTS.md` | All 14 CSI-NN checkboxes flipped to `[x]` | VERIFIED | 14 `[x]` / 0 `[ ]`; 14 `Complete` / 0 `Pending`; CSI-08..10 (deferred from 222-VERIFICATION) and CSI-12..14 (Phase 223 requirements) all flipped |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| FINDINGS-v27.0.md Phase 220 subsection | 220-REVIEW WR-220-01/02/03 + IN-220-01..05 | per-finding Source field | WIRED | All 8 raw items accounted for across F-27-01..F-27-06 (IN-220-02/04/05 folded into F-27-06 per D-02); mapping table in 223-01-SUMMARY.md lines 52-58 |
| FINDINGS-v27.0.md Phase 221 subsection | 221-REVIEW WR-221-01/02 + IN-221-01/02/03 | per-finding Source field; resolved items cite commit sha | WIRED | All 5 items mapped to F-27-07..F-27-11; WR-221-01 and WR-221-02 both cite commit `f799da98` |
| FINDINGS-v27.0.md Phase 222 subsection | 222-REVIEW WR-222-01..04 + IN-222-01..06 + VERIFICATION Gap 1 + Gap 2 | per-finding Source field; resolved items cite ef83c5cd + e0a1aa3e | WIRED | WR-222-02 + WR-222-04 + Gap 1 consolidated into F-27-13 (shared commit ef83c5cd); WR-222-03 + Gap 2 consolidated into F-27-14 (commit e0a1aa3e); WR-222-01 → F-27-12; IN-222-01/02 → F-27-15; IN-222-03/04/05/06 → F-27-16 |
| FINDINGS-v27.0.md Regression Appendix | FINDINGS-v25.0.md F-25-01..F-25-13 | per-finding HOLDS/SUPERSEDED/FIXED/INVALIDATED tag | WIRED | All 13 F-25-NN IDs cited with status tags and code-pointer evidence in appendix table at lines 365-377 |
| KNOWN-ISSUES.md new v27.0 entries | FINDINGS-v27.0.md | explicit F-27-NN reference in each new KNOWN-ISSUES entry | WIRED | 3 entries reference F-27-12, F-27-05, F-27-13/F-27-14 respectively; all point to `audit/FINDINGS-v27.0.md` |
| MILESTONES.md v27.0 entry | ROADMAP.md Phase 220/221/222/223 rows | phase count + accomplishments bullets | WIRED | Header says 4 phases; 7 accomplishments bullets aligned with ROADMAP.md Phase 220-223 Success Criteria |
| PROJECT.md Completed Milestone v27.0 | MILESTONES.md v27.0 entry | one-line result summary matching MILESTONES | WIRED | Both files use `177+1 CRITICAL_GAP` and `16 INFO findings` wording; bare `178 CRITICAL_GAP` absent from both |
| REQUIREMENTS.md Traceability table | CSI-12/13/14 checkbox section | status column flipped to Complete matching checkbox state | WIRED | CSI-12/13/14 rows all show `Complete` (lines 78-80); checkboxes at lines 36-38 all show `[x]` |

### Data-Flow Trace (Level 4)

N/A — Phase 223 produces documentation artifacts (no dynamic data rendering). Data-flow trace does not apply.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Cited commit SHAs exist in git log | `git log --all --oneline \| grep -E "^(ef83c5cd\|e0a1aa3e\|f799da98\|e4064d67\|f0347093\|3d798794\|5408f745)"` | All 7 commits found | PASS |
| F-27-NN count in findings file | `grep -c '^#### F-27-' audit/FINDINGS-v27.0.md` | 16 (within 14-16 target) | PASS |
| F-25-NN count in regression appendix | `grep -c 'F-25-0[1-9]\|F-25-1[0-3]' audit/FINDINGS-v27.0.md` | 18 references covering all 13 (F-25-01..F-25-13) | PASS |
| D-07 verbatim scope sentence | `grep -c 'Call-site integrity audit covering three axes' audit/FINDINGS-v27.0.md` | 1 | PASS |
| KNOWN-ISSUES F-27 reference count | `grep -c 'F-27-' KNOWN-ISSUES.md` | 3 (one per new entry) | PASS |
| MILESTONES v27.0 header | `grep '^## v27.0' .planning/MILESTONES.md` | `## v27.0 Call-Site Integrity Audit (Shipped: 2026-04-13)` at line 3 | PASS |
| PROJECT Completed Milestone v27.0 | `grep '^## Completed Milestone: v27\.0' .planning/PROJECT.md` | Line 15 | PASS |
| REQUIREMENTS CSI checkboxes flipped | `grep -c '\[x\] \*\*CSI-'` / `grep -c '\[ \] \*\*CSI-'` | 14 / 0 | PASS |
| REQUIREMENTS traceability rows | `grep -c 'Pending' .planning/REQUIREMENTS.md` | 0 | PASS |
| Live code matches F-25-09 SUPERSEDED claim | Read `DegenerusGame.sol:856-860` | `if (rngWord == 0) rngWord = uint256(keccak256(abi.encodePacked(day, address(this))));` at line 859 | PASS |
| Live code matches F-25-08 HOLDS claim | Read `DegenerusGameAdvanceModule.sol:1200-1224` | `_getHistoricalRngFallback` body at :1200-1224; `keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))` at :1221 | PASS |
| No TODO/FIXME/PLACEHOLDER anti-patterns | `grep -iE 'TODO\|FIXME\|XXX\|PLACEHOLDER\|placeholder' audit/FINDINGS-v27.0.md` | 1 match (line 119) — legitimate prose usage ("a future TODO or NatSpec example mentioning GAME_FUTURE_MODULE would be hallucinated") | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CSI-12 | 223-01-PLAN | `audit/FINDINGS-v27.0.md` produced with severity-classified findings rolled up from 220/221/222, following v25.0 structure | SATISFIED | File exists at 392 lines; 16 INFO findings; full v25.0 regression appendix; REQUIREMENTS.md row 78 flipped to Complete |
| CSI-13 | 223-02-PLAN | `KNOWN-ISSUES.md` updated with accepted INFO/LOW items that are design decisions rather than bugs | SATISFIED | 3 new Design Decisions entries referencing F-27-12, F-27-05, F-27-13+F-27-14; REQUIREMENTS.md row 79 flipped to Complete |
| CSI-14 | 223-02-PLAN | `MILESTONES.md` retrospective entry written; `PROJECT.md` moves v27.0 to Completed Milestone; v27.0 SHIPPED | SATISFIED | MILESTONES.md:3 v27.0 entry; PROJECT.md:15 Completed Milestone block with preserved narrative; ROADMAP.md:10 shows v27.0 "in progress" flag — see deferred-item note below; REQUIREMENTS.md row 80 flipped to Complete |
| CSI-08 (also flipped per 222-VERIFICATION note) | 223-02-PLAN Task 2 (per deferred-items.md) | `FuturepoolSkim.t.sol` compile error fixed | SATISFIED | Phase 222 deliverable; REQUIREMENTS.md row 74 flipped from Pending to Complete by this phase's work per 222-VERIFICATION state note |
| CSI-09 (also flipped per 222-VERIFICATION note) | 223-02-PLAN Task 2 | `forge coverage --report summary` produces per-function coverage | SATISFIED | Phase 222 deliverable; REQUIREMENTS.md row 75 flipped to Complete |
| CSI-10 (also flipped per 222-VERIFICATION note) | 223-02-PLAN Task 2 | Every external/public function classified as COVERED/CRITICAL_GAP/EXEMPT | SATISFIED | Phase 222 deliverable (308-function matrix); REQUIREMENTS.md row 76 flipped to Complete |

**Orphan check:** `grep -E "Phase 223" .planning/REQUIREMENTS.md` confirms only CSI-12, CSI-13, CSI-14 are mapped to Phase 223 in the traceability table. No orphans. CSI-08/09/10 are mapped to Phase 222 but are documented in `deferred-items.md` as belonging to this phase's sweep.

**Minor note on ROADMAP.md:** The top-level milestones list at `.planning/ROADMAP.md:10` still carries `🚧 **v27.0 Call-Site Integrity Audit** — Phases 220-223 (in progress)`. The `🚧` emoji and `(in progress)` wording are inconsistent with `.planning/PROJECT.md` and `.planning/MILESTONES.md`, both of which mark v27.0 as SHIPPED/Complete on 2026-04-13. This is a minor consistency gap — the ROADMAP Progress table at line 114 correctly shows Phase 223 `2/2 | Complete | 2026-04-13`. Neither the phase goal nor the CSI-14 requirement text explicitly requires ROADMAP.md top-level milestone-list update (CSI-14 names MILESTONES.md + PROJECT.md only), so this is not a blocking gap — but the user may want to flip the emoji to `✅` and change `(in progress)` to the shipped-date line matching the other milestones in the same list. Flagged here for awareness.

### Anti-Patterns Found

None. The single TODO match in `audit/FINDINGS-v27.0.md:119` is legitimate prose describing a hypothetical future comment that a gate regex might hallucinate — not a phase-work stub.

### Human Verification Required

See the `human_verification:` frontmatter block at the top of this document for six items from 223-REVIEW.md that were flagged as INFO during the phase's own code review but never addressed by a follow-up commit (`git log d22a7d98..HEAD` is empty after the review was added). These are all minor accuracy or clarity fixes to `audit/FINDINGS-v27.0.md`:

1. Audit Date vs re-verification date (line 3 is 2026-04-13, body cites 2026-04-12)
2. F-27-16 sub-point B stale line range (`:200-204` pre-fix vs `:230-232` post-fix)
3. Executive Summary count ambiguity (9/9 vs 3 WR + 5 IN in one parenthetical)
4. `5 observations resolved in-cycle` vs 4 finding-ID-level Resolved markers
5. F-25-08 evidence line range + paraphrased comment quote
6. F-27-14 pre-fix line numbers without post-fix navigation hint

Each is a 1-line edit. None blocks goal achievement or v27.0 shipping — the phase goal and all 10 observable truths pass. But the user should decide whether to land these polish fixes before declaring v27.0 fully sealed. Either a sweep fix-up commit or a conscious accept-as-is decision would close this verification.

### Gaps Summary

No code-level or structural gaps. The phase goal — produce the consolidated findings document, update KNOWN-ISSUES, write the milestone retrospective, move the project-level milestone, and flip all CSI checkboxes — is fully met. All 4 ROADMAP Success Criteria pass, all 14/14 CSI requirements are Complete, and every source-phase REVIEW/VERIFICATION item is traceable through the F-27-NN mapping.

The status is `human_needed` only because the phase's own code review (223-REVIEW.md) produced 6 INFO-level polish observations on `audit/FINDINGS-v27.0.md` that were documented but never addressed in code. The user should decide whether to land fixes or accept the current state.

---

_Verified: 2026-04-12T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
