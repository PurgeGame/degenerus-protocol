---
phase: 236-regression-findings-consolidation
verified: 2026-04-18T00:00:00Z
status: passed
score: 4/4 success criteria verified
head_anchor: e8155cab09c4e16ed83c1eeba3ae174da0508fc5
baseline_stability: CONFIRMED — git diff --name-only 1646d5af..HEAD -- contracts/ test/ returns empty; zero code changes
gaps: []
human_verification: []
---

# Phase 236: Regression + Findings Consolidation — Verification Report

**Phase Goal:** Every prior finding is regression-checked against the delta, and all v29.0 findings are consolidated into `audit/FINDINGS-v29.0.md` with severity / source / resolution fields.
**Verified:** 2026-04-18
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Baseline Stability

`git diff --name-only 1646d5af..HEAD -- contracts/ test/` returns empty. Zero contract or test modifications between the audit baseline and current HEAD. Phase 236 is docs-only as required. HEAD advances from `1646d5af` (code baseline) to `e8155cab` across 5 docs-only commits:

- `519b57e8` — create `audit/FINDINGS-v29.0.md` with 4 F-29-NN INFO blocks
- `5de8ad0c` — update `KNOWN-ISSUES.md` with 2 new KI entries + 3 v29.0 back-refs
- `11739687` — complete Findings Consolidation plan + tracking updates
- `3a553329` — append Regression Appendix to `audit/FINDINGS-v29.0.md`
- `e8155cab` — add 236-02 SUMMARY.md

Historical files (`audit/FINDINGS-v25.0.md`, `audit/FINDINGS-v27.0.md`, `audit/FINDINGS-v28.0.md`, `audit/FINDINGS.md`) are untouched — confirmed via `git diff --name-only 1646d5af..HEAD`.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: All 16 v27.0 INFO findings + 3 v27.0 KNOWN-ISSUES entries re-verified with PASS/REGRESSED/SUPERSEDED verdict | VERIFIED | 16 F-27-01..F-27-16 rows at lines 217-232 + 3 KI-entry rows at lines 244-246 of FINDINGS-v29.0.md; all 19 carry verdicts and evidence at HEAD 1646d5af |
| 2 | SC2: All 13 v25.0 findings + v26.0 delta-audit conclusions re-verified with no regression | VERIFIED | 13 F-25-01..F-25-13 rows at lines 187-199; v26.0 one-paragraph design-only note at lines 205-207; 12 PASS + 1 SUPERSEDED + 0 REGRESSED |
| 3 | SC3: `audit/FINDINGS-v29.0.md` exists in v27.0-style per-finding block format with 4 F-29-NN blocks, per-phase sectioning, and required fields | VERIFIED | File exists, 268 lines; Executive Summary table (0/0/0/0/4); phases 231/232/232.1/233/234/235 in order; 4 F-29-NN INFO blocks each with Severity/Source/Contract/Function/Resolution |
| 4 | SC4: `KNOWN-ISSUES.md` (repo root) updated with 2 new entries referencing F-29-NN IDs + 3 back-refs; D-09 and D-10 exclusions honored | VERIFIED | Both new KI entries present (BAF event-widening refs F-29-01/02; Gameover RNG substitution refs F-29-04); 3 existing entries carry v29.0 back-refs; no 232.1 entry (D-09); no F-29-03/FC-234-A entry (D-10) |

**Score:** 4/4 truths verified

---

## SC1: REG-01 — v27.0 Regression Coverage

**Scope:** 16 v27.0 INFO findings (F-27-01..F-27-16) + 3 v27.0 KNOWN-ISSUES entries

**Row count:** 16 F-27-NN rows verified by grep against `audit/FINDINGS-v29.0.md` lines 217-232. All 16 map to distinct findings from `audit/FINDINGS-v27.0.md` (confirmed by grep against source file).

**KI entries:** 3 rows in the `v27.0 KNOWN-ISSUES Entries` table (lines 244-246):
- "Deploy-pipeline VRF_KEY_HASH regex is single-line only." — PASS, cites F-27-12
- "Parallel `make -j test` mutates `ContractAddresses.sol` concurrently." — PASS, cites F-27-05
- "v27.0 Phase 222 VERIFICATION gap closures (in-cycle)." — PASS, cites F-27-13, F-27-14

**Verdicts:** 16 PASS / 0 REGRESSED across F-27 findings; 3 PASS / 0 REGRESSED across KI entries. Evidence column in each row cites HEAD `1646d5af` or specific file:line.

**Verdict summary block** (lines 234, 248) present with explicit counts and evidence notes.

**Status: PASS**

---

## SC2: REG-02 — v25.0 + v26.0 Regression Coverage

**Scope:** 13 v25.0 INFO findings (F-25-01..F-25-13) + v26.0 design-only-milestone note

**Row count:** 13 F-25-NN rows verified by grep at lines 187-199 of `audit/FINDINGS-v29.0.md`. All 13 map to distinct findings from `audit/FINDINGS-v25.0.md` (confirmed by grep against source file).

**Verdicts:** 12 PASS + 1 SUPERSEDED (F-25-09, deity-boon fallback relocation graded at v27.0 cycle — conclusion still holds) + 0 REGRESSED.

**v26.0 note:** One-paragraph design-only-milestone note at lines 205-207 explicitly states no findings rows exist for v26.0, notes implicit re-verification via Phase 231 EBD-02 and Phase 233 JKP-03. Satisfies the "v26.0 one-paragraph note" requirement from D-03.

**Status: PASS**

---

## SC3: FIND-01 + FIND-03 — FINDINGS-v29.0.md Structure

**File:** `audit/FINDINGS-v29.0.md` — EXISTS (268 lines)

**Executive Summary:** Severity table at lines 12-19 shows 0/0/0/0/4 per D-04. "Overall Assessment" paragraph at lines 21 present, zero on-chain vulnerabilities stated, 5 audit phases / 13 plans / 251 aggregate verdict rows cited.

**Per-phase sections — order verified:**
- Phase 231 (line 27) — 0 findings, one-paragraph note
- Phase 232 (line 33) — 0 findings, one-paragraph note
- Phase 232.1 (line 39) — 0 findings, one-paragraph note
- Phase 233 (line 45) — 2 findings (F-29-01, F-29-02)
- Phase 234 (line 79) — 1 finding (F-29-03)
- Phase 235 (line 97) — 1 finding (F-29-04)

Order matches D-02 (231 → 232 → 232.1 → 233 → 234 → 235). Phases with zero findings have explicit one-paragraph "zero findings" subsections.

**F-29-NN blocks — all 4 verified:**

| ID | Severity | Contract | Resolution | Source Phase |
|----|----------|----------|------------|--------------|
| F-29-01 | INFO | `DegenerusGameJackpotModule.sol` | OFF-CHAIN-INDEXER-REGEN | Phase 233 |
| F-29-02 | INFO | `DegenerusGameJackpotModule.sol` | OFF-CHAIN-INDEXER-REGEN | Phase 233 |
| F-29-03 | INFO | `test/fuzz/CoverageGap222.t.sol` | INFO-ACCEPTED | Phase 234 |
| F-29-04 | INFO | `DegenerusGameAdvanceModule.sol` | DESIGN-ACCEPTED | Phase 235 |

Each block contains: Severity, Source (phase + AUDIT.md path), Contract, Function (with file:line), Resolution, severity-justification paragraph. All per D-01, D-04, D-07.

**Regression Appendix:** Present, starting at line 170. Contains 32 per-item rows + v26.0 note + Regression Summary block. Regression Summary (lines 253-264) shows 31 PASS + 1 SUPERSEDED + 0 REGRESSED. FIND-03 milestone-closure statement at line 268 confirms combined deliverable is complete.

**Summary Statistics section** (lines 115-163): per-severity table + per-source-phase table + per-contract table + full Audit Trail table. Satisfies FIND-03 executive summary + per-phase counts requirement.

**Status: PASS**

---

## SC4: FIND-02 — KNOWN-ISSUES.md Updates

**File path:** `./KNOWN-ISSUES.md` (repo root) — CORRECT. Not `audit/KNOWN-ISSUES.md`. ROADMAP path typo confirmed avoided per CONTEXT.md.

**New entry 1 — BAF event-widening + BAF_TRAIT_SENTINEL=420 pattern (D-05):**
Present at line 38. Discloses: uint16 sentinel 420 out-of-domain for uint8 traits, event decls widened, topic0 changes, off-chain ABI regen needed. Consolidates both 233-01 observations into ONE entry per D-05. Cites "(See F-29-01 and F-29-02 in `audit/FINDINGS-v29.0.md`)".

**New entry 2 — Gameover RNG substitution for mid-cycle write-buffer tickets (D-06):**
Present at line 40. Discloses: "RNG-consumer determinism" invariant, terminal-state violation, acceptance rationale (a)-(d), TRNX-01 Gameover-row verdict unchanged. Cites "(See F-29-04 in `audit/FINDINGS-v29.0.md`)".

**Back-ref 1 — Gameover prevrandao fallback (D-08):**
Present at line 29. Appended text: "(re-verified v29.0 Phase 235 RNG-01 at HEAD 1646d5af — see `audit/FINDINGS-v29.0.md` regression appendix)". Matches D-08 requirement.

**Back-ref 2 — Lootbox RNG uses index advance isolation (D-08):**
Present at line 33. Appended text: "(re-verified v29.0 Phase 235 RNG-01 + RNG-02 at HEAD 1646d5af)". Matches D-08 requirement.

**Back-ref 3 — Decimator settlement temporarily over-reserves claimablePool (D-08):**
Present at line 36. Appended text: "(re-verified v29.0 Phase 235 CONS-01 at HEAD 1646d5af)". Matches D-08 requirement.

**D-09 honored — no 232.1 entry:** grep for "232.1" and "FC-234-A" in KNOWN-ISSUES.md returns no matches. Correct.

**D-10 honored — no F-29-03/test-coverage entry:** grep for "F-29-03" and "FC-234-A" in KNOWN-ISSUES.md returns no matches. Correct.

**Status: PASS**

---

## Requirements Coverage

| Requirement | Plans | Status | Evidence |
|-------------|-------|--------|----------|
| REG-01 | 236-02 | SATISFIED | 16 F-27-NN rows + 3 KI-entry rows in Regression Appendix; all PASS; zero REGRESSED |
| REG-02 | 236-02 | SATISFIED | 13 F-25-NN rows + v26.0 note in Regression Appendix; 12 PASS + 1 SUPERSEDED + 0 REGRESSED |
| FIND-01 | 236-01 | SATISFIED | 4 F-29-NN INFO blocks with severity/source/file:line/resolution in FINDINGS-v29.0.md |
| FIND-02 | 236-01 | SATISFIED | KNOWN-ISSUES.md updated with 2 new entries (refs F-29-01/02, F-29-04) + 3 back-refs |
| FIND-03 | 236-01 + 236-02 | SATISFIED | Executive summary + per-phase counts + per-severity totals + Regression Appendix; milestone-closure statement at FINDINGS-v29.0.md line 268 |

---

## Scope Guards

**Historical findings files unmodified:** `git diff --name-only 1646d5af..HEAD -- audit/FINDINGS-v25.0.md audit/FINDINGS-v27.0.md audit/FINDINGS-v28.0.md audit/FINDINGS.md` returns empty. All four historical records preserved.

**KNOWN-ISSUES.md path:** Correctly edited at repo root `./KNOWN-ISSUES.md`; no `audit/KNOWN-ISSUES.md` created.

**D-09 (no 232.1 KI):** Confirmed absent from KNOWN-ISSUES.md.

**D-10 (no F-29-03 KI):** Confirmed absent from KNOWN-ISSUES.md.

**D-11 (v28.0 KI-suppression not applied):** The 2 new KI entries were written per normal v25/v27 pattern. No suppression applied.

---

## Anti-Patterns Found

None. Phase 236 is documentation-only. No code files modified. No stub patterns applicable.

---

## Observational Notes (Non-Blocking)

**DCM-01 SAFE-INFO rows reclassified:** The Phase 232 section note (lines 35-36) explains that DCM-01's two `Finding Candidate: Y` rows (DECIMATOR_MIN_BUCKET_100 dead-code revival + "prev"-prefixed naming vestige) were reviewed during Phase 236 consolidation and classified below the INFO finding threshold. This decision is documented in the FINDINGS deliverable body, which is the appropriate place. The AUDIT.md record preserves the original Finding Candidate: Y annotation.

**F-27-13 v29.0 back-reference:** The F-27-13 regression row (line 229) correctly notes that commit `d5284be5` edited `test/fuzz/CoverageGap222.t.sol` (the same file as F-27-13) but explains the edit is a selector-alignment hunk (see F-29-03) that does NOT regress the post-fix test-quality state. Clear and accurate.

**Regression verdict count discrepancy resolved:** The Regression Summary at line 260 states "31 PASS + 1 SUPERSEDED" for 32 items. Arithmetic: 12 PASS (F-25) + 16 PASS (F-27) + 3 PASS (v27 KI) = 31 PASS + 1 SUPERSEDED (F-25-09) = 32 total. Correct.

---

_Verified: 2026-04-18_
_Verifier: Claude (gsd-verifier)_
