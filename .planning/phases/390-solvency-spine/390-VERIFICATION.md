---
phase: 390-solvency-spine
verified: 2026-06-14T22:45:00Z
status: passed
score: 12/12
overrides_applied: 0
re_verification: false
---

# Phase 390: Solvency-Spine Verification Report

**Phase Goal:** The claimablePool / sDGNRS backing identities hold across the redemption rework, dust-forfeit, CEI, and JackpotModule fold; BOTH finding nets on record.
**Verified:** 2026-06-14T22:45:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | NET 1 council (gemini + codex) is on record for the full SOLVENCY slice | VERIFIED | `council/solv.council.json` confirms both models available, 0 skipped; `solv.gemini.txt` (22 lines, 394 words) + `solv.codex.txt` (26 lines, 693 words) both present and substantive; captured in `390-01-COUNCIL-NET.md` (131 lines) with "NET 1 ON RECORD" attestation |
| 2 | NET 2 (Claude adversarial net) is on record, independent of the council | VERIFIED | `390-02-CLAUDE-NET.md` (549 lines) covers all 19 items; council outputs explicitly NOT read until §C (confirmed by structural header and §C being the final section at line 469) |
| 3 | Council prompt neutrally charged against frozen a8b702a7, all 7 SOLV + 7 FC + 5 cross-refs named | VERIFIED | `390-01-COUNCIL-PROMPT-SOLV.md` (301 lines): contains `a8b702a7`, FC-390-01..07, FC-392-08, FC-393-02/03, SOLV-05/liveness, SOLV-06/CEI; three prime targets charged hard with multi-tx interleavings spelled out; KNOWN-BY-DESIGN exclusions present; no pre-stated verdict |
| 4 | SOLV-01..07 each carry explicit CONFIRMED/REFUTED/BY-DESIGN/MONITOR verdict with settling bound/cite | VERIFIED | `390-FINDINGS.md` §2a table: all 7 rows present with REFUTED verdicts and file:line cites at `a8b702a7`; §5 re-attestation table: all 7 marked ATTESTED; REQUIREMENTS.md updated with checkmarks and settling cites |
| 5 | FC-390-01..07 + 5 inherited cross-refs each carry explicit adjudicated verdicts | VERIFIED | `390-FINDINGS.md` §2b (FC-390-01..07) + §2c (FC-389-02/-08, FC-392-08, FC-393-02/-03): all 12 rows present with REFUTED/BY-DESIGN/MONITOR verdicts and file:line cites |
| 6 | SOLV-07 divergence resolved with wei-level accounting (gemini HIGH vs codex SOUND) | VERIFIED | `390-FINDINGS.md` §3a: the load-bearing dual-gate traces `_handleSoloBucketWinner:1214-1215` (`paidDelta += wpSpent`) confirming `paidDailyEth` INCLUDES `whalePassCost`; cross-verified at frozen source — `git show a8b702a7:contracts/modules/DegenerusGameJackpotModule.sol` lines 1210-1215 confirm `paidDelta += wpSpent` is present; gemini's premise is FALSE at frozen source; skeptic gate applied, fails reachability condition (1); verdict REFUTED |
| 7 | SOLV-05/FC-390-01 liveness-window settled by dedicated multi-tx ordering analysis | VERIFIED | `390-02-CLAUDE-NET.md` §SOLV-05/FC-390-01 (lines 164-215): three interleavings (a)/(b)/(c) explicitly enumerated; structural fact that redemption ETH is segregated OUT of drain's `totalFunds` (GameOverModule:82-84) established; EVM tx-atomicity + single isGameOver snapshot + atomic release/slot-delete (:854/:857) proven strand/double-credit-free; `390-FINDINGS.md` §2a SOLV-05 row cites the multi-tx bound |
| 8 | SOLV-04/FC-390-02 dust-forfeit settled by dedicated backing proof under MAX reservation | VERIFIED | `390-02-CLAUDE-NET.md` §SOLV-04/FC-390-02 (lines 127-162): traces `ethForForfeit=min(bal,forfeitEth)`, GAME pulls `forfeitEth-msg.value` as stETH (reverting if short) BEFORE `_creditClaimable`, proving fail-closed + value-in-before-credit + MAX(175%) coverage; `390-FINDINGS.md` §2a SOLV-04 row cites the backing proof |
| 9 | SOLV-06 CEI settled by dedicated trace over all changed payout legs | VERIFIED | `390-02-CLAUDE-NET.md` §SOLV-06 (lines 217-254): traces 4 legs (claimWinnings, `_payoutWithStethFallback`, `_payEth`, `pullRedemptionReserve`) + dust-forfeit + new redemption credit legs; `distributeYieldSurplus` cannot observe in-flight stETH; anchored on RedemptionStethFallback 10/10; `390-FINDINGS.md` §2a SOLV-06 row cites the CEI trace |
| 10 | Skeptic gate run and recorded before any CATASTROPHE/HIGH | VERIFIED | `390-FINDINGS.md` §3: skeptic gate section present (2 grep hits); §3a covers the load-bearing SOLV-07 dual-gate (4 dimensions: source pin, wei-level accounting, structural-protection check, 3-condition EV lens); §3b covers 5 MED-attention leads; result = 0 items reach CATASTROPHE/HIGH |
| 11 | AUDIT-ONLY posture maintained — no contract source modified | VERIFIED | `git diff a8b702a7 -- contracts/` produces empty output (0 lines diff); `git diff a8b702a7..HEAD --name-only -- contracts/` is empty; all 4 phase commits (`562c3abc`, `e2e9e042`, `fc97d904`, `09274eaf`) confirmed in git log, all in `.planning/` only |
| 12 | Both nets on record cited together; any CONFIRMED finding documented + routed not fixed | VERIFIED | `390-FINDINGS.md` §1 both-nets-on-record attestation table present (11 NET-1/NET-2 references by grep); §4 routing block: "0 CONFIRMED contract-source findings — document-only; SOLV-01..07 attested at a8b702a7"; INFO/MONITOR items listed for future phases; no contract edits |

**Score: 12/12 truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/390-solvency-spine/390-01-COUNCIL-PROMPT-SOLV.md` | Neutral council prompt, min 40 lines, covers all SOLV + FC IDs | VERIFIED | 301 lines; all required IDs confirmed by grep; `a8b702a7` present; three prime targets charged hard |
| `.planning/phases/390-solvency-spine/390-01-COUNCIL-NET.md` | Capture record: available/skipped, byte-freeze, "NET 1 ON RECORD" | VERIFIED | 131 lines; "NET 1 ON RECORD" present; byte-freeze attestation present; per-model characterizations present; cross-model SOLV-07 divergence documented as priority item for 390-02 |
| `.planning/phases/390-solvency-spine/council/solv.gemini.txt` | Raw gemini output | VERIFIED | 22 lines, 394 words; substantive content with SOLV-01..06 verdicts (SOUND) + SOLV-07 HIGH lead; contains actual findings text |
| `.planning/phases/390-solvency-spine/council/solv.codex.txt` | Raw codex output | VERIFIED | 26 lines, 693 words; substantive content with all items covered SOUND, file:line cites present |
| `.planning/phases/390-solvency-spine/council/solv.council.json` | Manifest: models, skipped, outputs | VERIFIED | 7 lines; models: [gemini, codex]; skipped: []; outputs paths correct |
| `.planning/phases/390-solvency-spine/390-02-CLAUDE-NET.md` | NET 2 adversarial analysis, min 80 lines, all 19 items | VERIFIED | 549 lines; all 19 item IDs present; council outputs NOT read until §C (line 469); dedicated prime-target sections confirmed |
| `.planning/phases/390-solvency-spine/390-FINDINGS.md` | Full adjudication table, both nets, skeptic gate, verdict per item, min 90 lines | VERIFIED | 178 lines; all 19 IDs present; both-nets attestation table present; skeptic gate present; per-item verdict rows with settling cites; §5 re-attestation for SOLV-01..07 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `390-01-COUNCIL-PROMPT-SOLV.md` | `council/solv.{gemini,codex}.txt` | `council.sh --label solv` fan-out | VERIFIED | `council.json` manifest records the run; both outputs present; stderr 0 bytes each |
| `390-01-COUNCIL-NET.md` | `council/solv.council.json` | manifest capture | VERIFIED | COUNCIL-NET references the manifest path; manifest references output paths; consistent |
| `390-FINDINGS.md` | `390-01-COUNCIL-NET.md` + `council/*.txt` | both-nets-on-record fold | VERIFIED | §1 table cites `390-01-COUNCIL-NET.md` + `council/solv.{gemini,codex}.txt` by name; NET-1/NET-2 columns present across all verdict rows |
| `390-FINDINGS.md` | SOLV-01..07 + FC-390-01..07 + 5 cross-refs | per-item adjudicated verdict rows | VERIFIED | 19/19 IDs present; each row has NET-1 result, NET-2 result, VERDICT, and settling cite |

---

### Data-Flow Trace (Level 4)

This is an audit-documentation phase. The "data" is the wei-level tracing from frozen source rather than runtime data flows. The critical chain is verified:

| Chain | Source | Flows to | Status |
|-------|--------|----------|--------|
| SOLV-07 divergence resolution | `git show a8b702a7:DegenerusGameJackpotModule.sol:1214-1215` (verified directly) | `390-02-CLAUDE-NET.md` §SOLV-07 → `390-FINDINGS.md` §3a | FLOWING — the exact line `paidDelta += wpSpent` at :1214 is present at frozen source; the adjudication conclusion follows correctly |
| Prime target traces | frozen source via `git show a8b702a7:contracts/*.sol` | `390-02-CLAUDE-NET.md` §B (per-item) | FLOWING — file:line cites in CLAUDE-NET trace to real functions confirmed by spot-reading GameOverModule:73-182 (drain anatomy), JackpotModule:1246-1281 (_processSoloBucketWinner), LootboxModule:1004-1014 |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — audit-documentation phase with no runnable entry points added. The audit artifacts are documentation only; no new API, CLI, or runnable code was introduced.

---

### Probe Execution

Step 7c: No probes declared in PLAN.md; no conventional `scripts/*/tests/probe-*.sh` applicable to this documentation phase.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SOLV-01 | 390-01-PLAN.md, 390-02-PLAN.md | `claimablePool == Σ claimable + afking` across changed credit/debit | SATISFIED | `390-FINDINGS.md` §2a SOLV-01: REFUTED with file:line cites; REQUIREMENTS.md updated with `[x]` + cite |
| SOLV-02 | 390-01-PLAN.md, 390-02-PLAN.md | sDGNRS backing identity; balance + stETH >= obligations | SATISFIED | `390-FINDINGS.md` §2a SOLV-02: REFUTED; widths bounded (uint96, uint128) confirmed |
| SOLV-03 | 390-01-PLAN.md, 390-02-PLAN.md | submit/claim conservation: ethDirect+lootboxEth+forfeitEth == released | SATISFIED | `390-FINDINGS.md` §2a SOLV-03: REFUTED with branch-by-branch proof |
| SOLV-04 | 390-01-PLAN.md, 390-02-PLAN.md | dust-forfeit self-credit always backed; never phantom bump | SATISFIED | `390-FINDINGS.md` §2a SOLV-04: REFUTED with dedicated backing proof |
| SOLV-05 | 390-01-PLAN.md, 390-02-PLAN.md | claim liveness-window ordering safe vs handleGameOverDrain | SATISFIED | `390-FINDINGS.md` §2a SOLV-05: REFUTED with multi-tx ordering (a)(b)(c) |
| SOLV-06 | 390-01-PLAN.md, 390-02-PLAN.md | CEI / yield-surplus reentrancy closed; V62-03 class | SATISFIED | `390-FINDINGS.md` §2a SOLV-06: REFUTED with 4-leg CEI trace |
| SOLV-07 | 390-01-PLAN.md, 390-02-PLAN.md | JackpotModule delta-fold complete; no pool credited/deleted twice | SATISFIED | `390-FINDINGS.md` §2a SOLV-07: REFUTED; gemini HIGH lead resolved at wei-level; skeptic gate documented |

---

### Anti-Patterns Found

Anti-pattern scanning performed on phase deliverables (`.planning/` docs only — no contract source modified).

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| — | No TBD/FIXME/XXX markers found in phase deliverables | — | — |
| — | No placeholder/stub content found | — | — |
| `council/solv.gemini.txt` | Gemini output ends with "Do you agree with this assessment and the proposed strategy?" (interactive/proposal-stage phrasing) | INFO | Non-blocking — gemini self-flagged this as "research stage" (noted verbatim in 390-01-COUNCIL-NET.md). The 390-01-COUNCIL-NET.md correctly characterizes this as a "RAW lead, NOT a confirmed finding" and routes it to 390-02 for adjudication. The output still contains substantive content for all SOLV-01..06 (SOUND) + the SOLV-07 double-credit claim with line cites. Adjudication correctly treats this as an unresolved lead, not a lazy stub. |

---

### Human Verification Required

None. This is an audit-documentation phase. All verifiable claims are:
- Source code existence and content (verified via `git show a8b702a7:...` direct reads)
- Document existence, line counts, and ID presence (verified by file system checks)
- Git diff state (verified: `git diff a8b702a7 -- contracts/` = empty)
- Commit existence (verified: all 4 commits present in git log)
- The SOLV-07 resolution (verified: frozen source line 1214 `paidDelta += wpSpent` is present)

No visual/UX/real-time/external-service behavior exists in this phase.

---

### Gaps Summary

**No gaps found.** All 12 must-have truths are VERIFIED with direct codebase evidence:

- Both nets are substantively on record (gemini: 394 words of real findings; codex: 693 words with file:line cites)
- All 19 adjudication items (7 SOLV + 7 FC-390 + 5 cross-refs) carry explicit verdicts in both CLAUDE-NET and FINDINGS
- The SOLV-07 divergence is resolved at frozen source, not hand-waved — the pivotal line `paidDelta += wpSpent` at DegenerusGameJackpotModule.sol:1214 is confirmed present and the NET 2 analysis correctly traces why gemini's premise is false
- The three prime targets (SOLV-05/FC-390-01 liveness, SOLV-04/FC-390-02 dust-forfeit, SOLV-06 CEI) each have dedicated multi-paragraph treatment with concrete call sequences
- The audit-only posture is proven by the empty `git diff a8b702a7 -- contracts/` output
- REQUIREMENTS.md SOLV-01..07 are all updated with checkmarks and settling cites, mapping correctly to phase 390

---

_Verified: 2026-06-14T22:45:00Z_
_Verifier: Claude (gsd-verifier)_
