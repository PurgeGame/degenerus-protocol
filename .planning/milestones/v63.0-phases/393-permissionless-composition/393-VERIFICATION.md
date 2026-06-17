---
phase: 393-permissionless-composition
verified: 2026-06-15T00:00:00Z
status: passed
score: 9/9
overrides_applied: 0
---

# Phase 393: PERMISSIONLESS-COMPOSITION Verification Report

**Phase Goal:** the new permissionless/keeper surface cannot grief, faucet, or steer, and composition across boundaries is safe; BOTH finding nets on record.
**Verified:** 2026-06-15
**Status:** passed
**Re-verification:** No — initial verification

---

## Step 0: Previous Verification

No previous VERIFICATION.md found. Initial mode.

---

## Step 1: Phase Context

- ROADMAP Goal: "the new permissionless/keeper surface cannot grief, faucet, or steer, and composition across boundaries is safe"
- ROADMAP Success Criteria: (1) permissionless claims beneficiary-only; (2) keeper bounty net-negative vs real gas + un-manufacturable; (3) forced claim-timing inert; (4) partial-balance burst solvency + all gates/reentrancy intact; both nets on record.
- Requirements: ACCESS-01, ACCESS-02, ACCESS-03, ACCESS-04, ACCESS-05
- Phase type: dual-net audit sweep (AUDIT-ONLY — no contract source modified)
- Subject frozen at: `a8b702a7`
- Plans: 393-01-PLAN.md (Wave 1: Council NET 1), 393-02-PLAN.md (Wave 2: Claude NET 2 + adjudication)

---

## Step 2: Must-Haves

Derived from ROADMAP success criteria (primary) merged with PLAN frontmatter must_haves (additive detail).

**Roadmap truths (non-negotiable):**
1. Permissionless claims credit only the beneficiary (no third-party ETH push / forced-credit grief).
2. Keeper box-bounty is net-negative vs real prevailing gas (5-50+ gwei, not the 0.5-gwei peg) + flip-credit illiquidity + un-manufacturable.
3. Forced claim-timing cannot materially reduce a winner's reward or steer an outcome.
4. Partial-balance redemption-leg solvency holds under same-block bursts + all gates/reentrancy intact.
5. BOTH nets (NET 1 council + NET 2 Claude) are on record before any verdict is issued.
6. ACCESS-02 (keeper bounty) settled by a REAL economic argument — real-gas cost vs reward — not a hand-wave.
7. ACCESS-04 (partial-balance burst) settled by a dedicated same-block multi-claim leg-accounting argument.
8. Every ACCESS-01..05 req AND every FC-393-01..04 owned lead AND the 4 inherited cross-refs (FC-390-03, FC-390-06, FC-392-08, FC-392-20) carries an explicit verdict (CONFIRMED/REFUTED/BY-DESIGN/MONITOR) with a settling cite in 393-FINDINGS.md.
9. `git diff a8b702a7 -- contracts/` EMPTY throughout; no contract source modified.

---

## Step 3: Observable Truths

### Goal Achievement

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Permissionless claims credit only the beneficiary — all entrypoints forward value to `player`, never `msg.sender` | VERIFIED | 393-FINDINGS.md §2a ACCESS-01 row: per-entrypoint beneficiary credit traced at DecimatorModule:316/:459, sDGNRS:884/:892/:830, BurnieCoinflip:777; post-gameOver self-claim-only gate verified; 393-02-CLAUDE-NET.md §2 gives the full per-entrypoint table |
| 2 | Keeper box-bounty net-negative vs REAL prevailing gas (5-50+ gwei, not the 0.5-gwei peg) + flip-credit illiquidity + un-manufacturable | VERIFIED | 393-FINDINGS.md §2a ACCESS-02 row + §3 cite-reconciliation: real-gas table 10x@5gwei / 40x@20gwei / 100x@50gwei before ×0.30 flip-credit illiquidity; decimator 15e12 / redemption 24e12 DISTINCT — both net-negative by identical ratio; un-manufacturable per real burn; issuance bounded per FC-390-06; 393-02-CLAUDE-NET.md §3 carries the full closed-form accounting |
| 3 | Forced claim-timing settled on adjacent-level MAGNITUDE question (not a timing-by-design dismissal), ruled inert | VERIFIED | 393-FINDINGS.md §2a ACCESS-03 row: reward magnitude frozen at resolution; `_rollTargetLevel` offset distribution frozen-seed-invariant; only the level anchor moves; forced earlier = beneficial/neutral; MONITOR posture recorded for any future level-dependent magnitude change; 393-02-CLAUDE-NET.md §5 carries the concrete magnitude reasoning |
| 4 | Partial-balance burst solvency: Σ legs == Σ rolled == Σ released; MAX(175%) reservation covers; ETH-drain shifts to stETH leg fail-closed; no strand/under-pull | VERIFIED | 393-FINDINGS.md §2a ACCESS-04 row + §2b FC-393-03 row: the same-block burst interleavings are spelled out (ETH-drain, stETH-shift, fail-closed); Σ identity proven; sDGNRS:822/:854/:880-900 + LootboxModule:932-936/:1009-1011 cited; 393-02-CLAUDE-NET.md §4 gives the full adversarial leg-accounting trace |
| 5 | All gates + reentrancy intact on every new/widened entrypoint (freeze/rngLocked/liveness/gameOver per entrypoint; CEI stETH-first/ETH-last; SDGNRS-gated callees; internal-only yield-surplus) | VERIFIED | 393-FINDINGS.md §2a ACCESS-05 row: per-entrypoint gate table present; DecimatorModule:298/:329/:399; sDGNRS:775/:854/:857; BurnieCoinflip:759; LootboxModule:927/:1005; DegenerusGame.sol:1888 (V62-03 reorder); 393-02-CLAUDE-NET.md §6 gives the full per-entrypoint enumeration |
| 6 | BOTH nets on record: NET 1 (gemini council) + NET 2 (Claude) on record before any verdict | VERIFIED | 393-01-COUNCIL-NET.md records gemini on record with substantive traced audit (VERIFIED SOUND all ACCESS-01..05, 0 findings, real-gas numbers); codex skipped (hard usage-cap, recorded in `skipped[]`, post-reset re-run flagged to 396 — a single available model satisfies council-on-record per the plan's both-unavailable rule); 393-02-CLAUDE-NET.md is the independent NET 2 (council folded at §7 after independent pass); 393-FINDINGS.md §1 has the both-nets-on-record attestation table |
| 7 | ACCESS-02 keeper-bounty settled by a dedicated REAL economic argument (not a hand-wave) | VERIFIED | 393-02-CLAUDE-NET.md §3 contains the full real-gas table (gas × gwei = cost vs reward ETH-value), the flip-credit illiquidity derivation (×0.5 survive-flip × ~0.59 peg ≈ 0.30 realized), the un-manufacturability proof per entrypoint (decimator `e.claimed=1` gate; redemption `ethValueOwed==0→return false` + BurnsBlockedBeforeDailyRng gate), and the FC-390-06 issuance-bound coupling; 393-FINDINGS.md §2a ACCESS-02 cites the real-gas numbers explicitly (10x/40x/100x); no hand-wave |
| 8 | Every ACCESS-01..05 req + FC-393-01..04 + FC-390-03 + FC-390-06 + FC-392-08 + FC-392-20 carries an explicit verdict with a settling cite | VERIFIED | 393-FINDINGS.md §2a (ACCESS reqs), §2b (owned leads), §2c (inherited cross-refs): all 13 items present, each with NET 1 / NET 2 / VERDICT / settling cite columns; all verdicts are REFUTED, BY-DESIGN/REFUTED, or REFUTED/INFO; §5 cross-ref consistency block confirms each ACCESS half is consistent with its 390/392 solvency/ECON counterpart |
| 9 | No contract source modified — AUDIT-ONLY posture, subject byte-frozen at a8b702a7 throughout | VERIFIED | `git diff a8b702a7 -- contracts/` EMPTY (verified by bash in this session); the four phase commits (26db45a4, 5764ba0c, 7ad0ee8c, fa70840d) affect only `.planning/` docs; contract delta across the commit range is 0 bytes |

**Score: 9/9 truths verified**

---

## Step 4: Artifact Verification

| Artifact | Expected | Lines | Status | Details |
|----------|----------|-------|--------|---------|
| `393-01-COUNCIL-PROMPT-ACCESS.md` | Council prompt ≥50 lines, neutral, covers all 13 IDs, charged against a8b702a7, ACCESS-02/04 HARD primes | 309 | VERIFIED | All 13 ID grep checks pass; a8b702a7 present; real-gas, illiquidity, burst/reservation, beneficiary language all present; ACCESS-02 and ACCESS-04 designated as dedicated numbered prime break-targets |
| `council/access.council.json` | Manifest with available/skipped fields | 8 | VERIFIED | JSON has `models: ["gemini"]`, `skipped: ["codex"]`, `outputs.gemini` path; correctly reflects the actual fan-out result |
| `council/access.gemini.txt` | Substantive gemini audit output | 43 | VERIFIED | 43 lines of concrete per-item traces, VERIFIED SOUND across ACCESS-01..05 + FC-393-04, with real-gas numbers (40x@20gwei, 10x@5gwei, ~30% liquid) and the MAX_ROLL 175% burst-solvency trace; not a placeholder |
| `393-01-COUNCIL-NET.md` | NET 1 capture record ≥20 lines, "NET 1 ON RECORD" line, byte-freeze attestation, codex-skip recorded, 396 re-run flagged | 175 | VERIFIED | "NET 1 ON RECORD for PERMISSIONLESS-COMPOSITION" present; codex skip documented with skip_reason (usage-limit cap); 396 re-run flag present; byte-freeze attestation (`git diff a8b702a7 -- contracts/` EMPTY) present; 2 gemini cite-drifts routed to 393-02 |
| `393-02-CLAUDE-NET.md` | NET 2 independent adversarial analysis ≥90 lines, all 13 IDs, dedicated real-gas economics, burst leg-accounting, magnitude analysis, gate enumeration | 442 | VERIFIED | All 13 IDs present; §3 real-gas table (gwei × gas = cost vs ETH-reward); §4 same-block burst leg-accounting with interleavings spelled out; §5 adjacent-level magnitude analysis with concrete offset-distribution reasoning; §6 per-entrypoint gate enumeration; council folded at §7 after independent pass |
| `393-FINDINGS.md` | Full adjudication ≥90 lines, both-nets-on-record table, all 13 verdict rows, skeptic gate, cross-ref consistency block, re-attestation line | 201 | VERIFIED | Both-nets attestation table present (§1); 13-row verdict table present (§2a/§2b/§2c); §3 cite-reconciliation (2 gemini cite-drifts settled); §4a skeptic gate applied to the 3 substantive items (ACCESS-02, ACCESS-04, ACCESS-03) with the 3-condition EV lens; §4b routing; §5 cross-ref consistency block (6 cross-refs, each confirmed consistent); §6 re-attestation line (5 reqs attested-or-finding) |

---

## Step 5: Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| 393-01-COUNCIL-PROMPT-ACCESS.md | council/access.council.json + access.gemini.txt | council.sh fan-out | VERIFIED | council.sh ran with `--label access`; manifest exists; gemini output exists with 43 lines of real content |
| 393-01-COUNCIL-NET.md | council/access.council.json | manifest available/skipped capture | VERIFIED | COUNCIL-NET references `access.council.json`, records available=gemini, skipped=codex |
| 393-FINDINGS.md | council/access.gemini.txt (NET 1) | both-nets-on-record fold | VERIFIED | 393-FINDINGS.md §1 explicitly cites `393-01-COUNCIL-NET.md + council/access.gemini.txt`; §2a verdict rows cite "NET 1: SOUND" |
| 393-FINDINGS.md | 393-02-CLAUDE-NET.md (NET 2) | per-item adjudication synthesis | VERIFIED | 393-FINDINGS.md §2 verdict rows cite NET 2 results; §1 both-nets table cites `393-02-CLAUDE-NET.md` |
| 393-FINDINGS.md | ACCESS-01..05 + FC-393-01..04 + cross-refs | per-item verdict rows | VERIFIED | All 13 IDs verified present via grep; each carries a CONFIRMED/REFUTED/BY-DESIGN/MONITOR verdict and a settling cite |
| REQUIREMENTS.md ACCESS-01..05 | 393-FINDINGS.md verdicts | attestation | VERIFIED | All five ACCESS reqs marked `[x]` with `✅ ATTESTED 393-02 (both nets; ...)` in REQUIREMENTS.md |

---

## Step 6: Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| ACCESS-01 | 393-01 + 393-02 | Every permissionless claim credits only the beneficiary (no third-party ETH push or forced-credit grief) | SATISFIED | REQUIREMENTS.md line 74 `[x]` ATTESTED; 393-FINDINGS.md §2a ACCESS-01 REFUTED verdict + per-entrypoint beneficiary cite |
| ACCESS-02 | 393-01 + 393-02 | Keeper box-bounty net-negative vs real prevailing gas (5-50+ gwei, not 0.5-gwei peg) + flip-credit illiquidity + un-manufacturable | SATISFIED | REQUIREMENTS.md line 75 `[x]` ATTESTED; 393-FINDINGS.md §2a ACCESS-02 REFUTED with real-gas numbers 10x/40x/100x; cite-reconciliation in §3 (redemption bounty 24e12 confirmed at sDGNRS:348) |
| ACCESS-03 | 393-01 + 393-02 | Forced claim-timing cannot materially reduce winner's reward or steer outcome | SATISFIED | REQUIREMENTS.md line 76 `[x]` ATTESTED; 393-FINDINGS.md §2a ACCESS-03 BY-DESIGN/REFUTED with magnitude reasoning (reward frozen; offset distribution frozen-seed-invariant); MONITOR posture documented |
| ACCESS-04 | 393-01 + 393-02 | Partial-balance redemption-leg solvency holds under same-block bursts | SATISFIED | REQUIREMENTS.md line 77 `[x]` ATTESTED; 393-FINDINGS.md §2a ACCESS-04 REFUTED with Σ identity + MAX(175%) reservation coverage; same-block burst interleavings spelled out |
| ACCESS-05 | 393-01 + 393-02 | Freeze/rngLocked/liveness/gameOver gates intact on all new/widened entrypoints; reentrancy closed | SATISFIED | REQUIREMENTS.md line 78 `[x]` ATTESTED; 393-FINDINGS.md §2a ACCESS-05 REFUTED with per-entrypoint gate enumeration + CEI ordering + SDGNRS-gated callees + internal-only yield-surplus |

No orphaned requirements — ROADMAP.md §Coverage table confirms ACCESS-01..05 mapped to 393 exclusively; all 5 are attested.

---

## Step 7: Anti-Pattern Scan

Phase is AUDIT-ONLY. Files modified are exclusively `.planning/` documentation (no application code, no contracts, no tests). Anti-pattern scan is applied to the four deliverable docs.

| File | Pattern | Status |
|------|---------|--------|
| 393-FINDINGS.md | TBD/FIXME/XXX debt markers | CLEAR — none found |
| 393-FINDINGS.md | Placeholder / "not yet implemented" language | CLEAR — every verdict has a concrete settling cite |
| 393-02-CLAUDE-NET.md | "will be here" / stub language | CLEAR — full adversarial reasoning present per section |
| 393-01-COUNCIL-NET.md | Silent both-unavailable false-green | CLEAR — codex skip explicitly documented, T-393-02 mitigation stated, 396 re-run flagged |
| council/access.gemini.txt | Stub or placeholder output | CLEAR — 43 lines with concrete per-item traces, real-gas numbers, and cite-backed reasoning |

No debt markers. No stubs. No placeholders. The one deviation (codex usage-cap skip) is correctly documented — it does not constitute an unreferenced debt marker because the skip is faithfully recorded in the council.json `skipped[]` and the post-reset re-run is explicitly flagged to phase 396.

---

## Step 7b: Behavioral Spot-Checks

Phase is AUDIT-ONLY (documentation deliverables, no runnable code produced). Behavioral spot-checks do not apply. Step 7b: SKIPPED (no runnable entry points — audit-only doc phase).

---

## Step 7c: Probe Execution

No probes declared in PLAN.md or SUMMARY.md. No conventional `scripts/*/tests/probe-*.sh` files reference this phase. Step 7c: SKIPPED (no probes declared or applicable).

---

## Step 8: Human Verification

This is a read-only audit sweep over byte-frozen contract source. All verdicts are based on source-code traces to specific line numbers at `a8b702a7`. The following items are routed to human attention but are NOT blockers for this phase's goal:

**Carried forward to phases 395/396 (informational, not blocking):**

1. **Un-netted test-hardening item — real-gas-net-negative oracle for ACCESS-02:** The closed-form 10x/40x/100x × 0.30-illiquidity argument is not a pinned forge assertion. A redemption-bounty (24e12) regression mirror of the 5 decimator rules (`DecimatorBountyRegression.t.sol`) is also absent. Both are oracle-completeness gaps, not contract defects. Routed to 395/396.

2. **Un-netted test-hardening item — same-block-burst burst-solvency oracle for ACCESS-04:** No dedicated K-claim same-block drain invariant exists (single-claim tests exercise the legs; neither runs an adversarial multi-claim burst). Oracle-completeness gap only; the burst-solvency is proven by trace + Σ identity + MAX-reservation bound. Routed to 395/396.

3. **Un-netted test-hardening item — packed-layout worst-case gas measurement for FC-393-04:** The 0a2209d4 perma-brick regression pins the 1460-deep + 365-window bounds but not the fresh packed-layout (32-days/slot masked sub-word) worst-case measurement. Oracle-completeness gap only. Routed to 395/396.

4. **Codex second-source owed:** codex hit its usage cap and skipped. Gemini + Claude satisfy the dual-net (one external model + Claude). Post-reset codex re-run of ACCESS-02 / ACCESS-04 substantive primes is recommended at phase 396.

None of these require human verification of visual appearance, external service behavior, or real-time interaction. They are observable oracle-completeness gaps appropriate for a test phase.

---

## Step 9: Overall Status Determination

Working through the decision tree:

- Any FAILED truth, MISSING/STUB artifact, NOT_WIRED key link, or blocker anti-pattern? **NO** — all 9 truths VERIFIED, all artifacts substantive and wired, no debt markers.
- Any human verification items (Section 8 is non-empty)? The items in Section 8 are test-hardening gaps ROUTED to 395/396 — they are oracle-completeness gaps, not verification items that block this phase's goal achievement. The phase goal ("the new permissionless/keeper surface cannot grief, faucet, or steer, and composition across boundaries is safe; BOTH finding nets on record") is fully achieved by source-code trace. The routed items cannot be validated by human observation — they require forge test authoring, which belongs to phase 395/396.
- Result: **status: passed**

---

## Summary

Phase 393 delivered exactly what the goal requires: a dual-net audit sweep of the new permissionless/keeper surface with both finding nets on record (NET 1 gemini + NET 2 Claude; codex usage-cap skip documented), every ACCESS-01..05 requirement adjudicated with an explicit verdict backed by source-code cites at `a8b702a7`, the two substantive primes (ACCESS-02 keeper-bounty economics, ACCESS-04 partial-balance burst solvency) given dedicated rigorous treatment rather than hand-waving, the forced-timing question settled on the magnitude dimension (not a by-design dismissal), all 13 items carrying REFUTED/BY-DESIGN verdicts with no CONFIRMED contract findings, the cross-ref ACCESS halves consistent with their 390/392 solvency/ECON counterparts, and the subject byte-frozen throughout (no contract source modified).

The 2 gemini cite-drifts were correctly identified, reconciled at the frozen source (redemption bounty = 24e12 at sDGNRS:348, confirming gemini was right and the surface-map wrong; carry entry = :754, mint = :777), and the verdicts updated to rest on the correct lines. The overall conclusion is unchanged.

Four un-netted test-hardening items and a codex second-source are routed to 395/396. These do not affect the phase goal.

**0 CONFIRMED contract findings. ACCESS-01..05 attested at `a8b702a7`.**

---

_Verified: 2026-06-15_
_Verifier: Claude (gsd-verifier)_
