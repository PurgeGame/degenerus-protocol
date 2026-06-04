---
phase: 370-spec-design-lock-anchor-re-attestation-vs-2b26ec91-cov-01-se
verified: 2026-06-04T23:00:00Z
status: passed
score: 4/4
overrides_applied: 0
re_verification: false
---

# Phase 370: SPEC / Design-Lock + COV-01 Verification Report

**Phase Goal:** SPEC / design-lock for v59.0 — (1) re-attest every cited file:line anchor (SALV / AFAFF / SOLV / PRESALE + Changes A/B/C) against frozen baseline 2b26ec91; (2) LOCK exactly one F-03 / SOLV-01 fix variant with a frozen-source rationale + map the producer-before-consumer batched-diff edit order across all 9 IMPL reqs; (3) WINDOW-01 pre-edit verification (every frozenUntilLevel hit classified, exactly 6 flips, afking eviction boundary inclusive-through-validThroughLevel); (4) COV-01 — re-run the area-solvency XMODEL leg with a SECOND independent model against frozen 2b26ec91 and adjudicate every returned claim. Paper/harness only — ZERO contracts/*.sol.
**Verified:** 2026-06-04T23:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | Every cited file:line anchor (SALV / AFAFF / SOLV / PRESALE + Change-A/B/C) is grep-verified against frozen 2b26ec91 with as-cited / as-found / drift columns — no "by construction" assertion survives un-grepped | VERIFIED | `370-01-SPEC.md` Section 1 contains a 7-group table (Groups 1-7 = SALV, AFAFF, SOLV, PRESALE, WINDOW, STREAK, CENTURY) with 24 distinct anchors. Every row has as-cited / as-found / drift / corrected / role columns. The SPEC cites grep/show method explicitly. Verdict line: "7 anchor groups attested, 7 carry drift on ≥1 line (all corrected), 0 unverified." Commits `8025f06e` (Task 1) and `d3a6d0b6` (Task 2) in git history. |
| 2 | Exactly one F-03 / SOLV-01 fix variant is chosen and recorded with a written rationale citing the frozen function bodies | VERIFIED | `370-01-SPEC.md` Section 2 explicitly locks VARIANT (a) — return the BAF whale-pass remainder from `_queueWhalePassClaimCore` and fold into the BAF caller's `claimableDelta`. Variant (b) is REJECTED with a decisive structural rationale: `futurePrizePool` is a stale cached local `memFuture` (read at `AdvanceModule:801`, written back with a single `_setPrizePools` at `:968`), so a mid-loop `_setFuturePrizePool` push-back inside `runBafJackpot` would be silently clobbered. Four call sites enumerated with AS-FOUND line numbers. SOLV-02 (F-04) confirmed as no-variant single-add at `DecimatorModule:596`. |
| 3 | The producer-before-consumer batched-diff edit order is mapped across all 9 IMPL reqs (STREAK-01 before STREAK-02; SOLV-01 return-value before the BAF caller fold) | VERIFIED | `370-01-SPEC.md` Section 3 contains the ordered edit table with all 9 reqs: STREAK-01 (step 1), SOLV-01 producer half (step 2), SOLV-01 consumer half (step 3), STREAK-02 (step 4), then SALV-01 / AFAFF-01 / SOLV-02 / PRESALE-01 / WINDOW-01 / CENTURY-01 (all order-free). The two producer-before-consumer chains are explicitly stated. |
| 4 | The COV-01 area-solvency XMODEL leg ran against frozen 2b26ec91 with a SECOND independent model; every returned claim has a Claude verdict (CONFIRMED / REFUTED / ALREADY-KNOWN); the coverage gap disposition is recorded for TERMINAL | VERIFIED | `370-02-COV01-ADJUDICATION.md` (267 lines) documents the full re-run. Second model = Gemini (`gemini-3-pro-preview`, NOT the v58 Codex leg). Mechanism = frozen source materialized into `context/frozen-solvency-source.txt` (8,125 lines, 426K), read in Plan Mode (defeats the git-shell-disabled v58 refusal). Raw output: `results/area-solvency.gemini.txt` (non-empty — opens "FROZEN SUBJECT — commit 2b26ec91.", returns 3 concerns + 1 attestation with concrete file:line cites). All 4 model outputs adjudicated: Claims 1 and 2 = CONFIRMED (corroborate F-03/F-04, ALREADY IN SCOPE); Claim 3 = CONFIRMED downstream of F-04 (resolved by SOLV-02, no new work); Attestation = upheld. K = 0 net-new. TERMINAL carry-forward note written. COV-01 disposition: "coverage gap CLOSED." |

**Score:** 4/4 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/370-.../370-01-SPEC.md` | Design-lock SPEC: anchor table + F-03 variant + edit-order map + WINDOW-01 verification; min 80 lines | VERIFIED | Exists, 348 lines. Contains `2b26ec91` (18 occurrences), `drift` (13 occurrences), `F-03`/`SOLV-01` (11 occurrences), `edit order`/`producer-before-consumer` (6 occurrences), `frozenUntilLevel` (27 occurrences), `validThroughLevel` (5 occurrences). Committed via `8025f06e` + `d3a6d0b6` + `46b309a7`. |
| `.planning/audit-v52/runs/v59/xmodel/` | Raw second-model area-solvency run output (prompt + model result + council manifest) against 2b26ec91 | VERIFIED | Directory exists with: `prompts/` (3 prompt files), `context/frozen-solvency-source.txt` (8,125 lines / 426K), `results/area-solvency.gemini.txt` (31 lines, non-empty, genuine frozen-source read), `results/area-solvency.gemini.err` (empty), `results/area-solvency.council.json` (manifest with model, mechanism, smoke-test, exclusions). Committed via `4f5c2658`. |
| `.planning/phases/370-.../370-02-COV01-ADJUDICATION.md` | COV-01 second-model run record + per-claim adjudication + routing dispositions; min 40 lines | VERIFIED | Exists, 267 lines. Contains `CONFIRMED`/`REFUTED` (15 occurrences), `coverage gap`/`CLOSED`/`disposition` (11 occurrences), `2b26ec91` (14 occurrences). TERMINAL carry-forward note present. Committed via `ea217437`. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| 370-01-SPEC.md anchor table | frozen 2b26ec91 source | git show / git grep at 2b26ec91 | VERIFIED | The SPEC states the verification method explicitly ("git show 2b26ec91:<path> + git grep -n '<token>' 2b26ec91 -- <path>") and references `2b26ec91` 18 times in the anchor tables. The AS-FOUND lines are explicitly distinguished from as-cited lines with drift noted. |
| 370-01-SPEC.md edit-order map | Phase 371 IMPL | producer-before-consumer ordering of 9 contract reqs | VERIFIED | Section 3 maps all 9 reqs with explicit predecessor/successor columns. STREAK-01 before STREAK-02 and SOLV-01 producer before SOLV-01 consumer are called out as "Two hard ordering constraints." |
| 370-02-COV01-ADJUDICATION.md | .planning/audit-v52/runs/v59/xmodel/results/ | raw second-model area-solvency output | VERIFIED | The adjudication doc references the raw result file by path and states the output "opens `FROZEN SUBJECT — commit 2b26ec91.`". The `results/area-solvency.gemini.txt` file exists and contains exactly the 3 concerns + 1 attestation adjudicated in the doc. |
| CONFIRMED COV-01 claims | Phase 371 IMPL batched diff | routed-to-IMPL disposition | VERIFIED | K = 0 — no net-new claims to route. Claims 1 and 2 are dispositioned "ALREADY IN SCOPE — corroborates F-03/F-04" (Phase-371 route already in the 370-01 edit order). Claim 3 is "ALREADY IN SCOPE — resolved by the SOLV-02 fix." The disposition summary explicitly states "CONFIRMED-new (routed to 371 as NEW IMPL work): 0." |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| SPEC-01 | 370-01-PLAN.md | Design-lock: anchor re-attestation + F-03 variant lock + edit-order map + WINDOW-01 | SATISFIED | REQUIREMENTS.md traceability table: "Complete (370-01 — anchors re-attested vs 2b26ec91, F-03 variant (a) locked, edit-order mapped, WINDOW-01 verified)". Checkbox `[x]` in REQUIREMENTS.md. All four sub-parts verified in 370-01-SPEC.md Sections 1-4. |
| COV-01 | 370-02-PLAN.md | Second-model area-solvency re-run vs 2b26ec91, adjudicate all claims | SATISFIED | REQUIREMENTS.md traceability table: "Complete (370-02 — second-model Gemini area-solvency re-run vs 2b26ec91; F-03/F-04 corroborated, K=0 net-new)". Checkbox `[x]` in REQUIREMENTS.md. K=0 verdict + TERMINAL carry-forward note in 370-02-COV01-ADJUDICATION.md. |

---

### PRESALE-01 Expansion Consistency Check

The phase context notes a USER-expanded PRESALE-01 design (settle-on-any-sub-change + dailyQuantity-tiered presale divisor) was folded into the design-lock after the initial plan was written.

Verified consistent across all artifacts:

- **REQUIREMENTS.md**: The PRESALE-01 entry carries the full `USER-expanded 2026-06-04` expansion — both the settle-on-any-sub-change and the tiered divisor (`/3` at `dailyQuantity >= 10`, `/2` below). Commit `46b309a7` (`docs(370): expand PRESALE-01`) touched REQUIREMENTS.md (+8/-4).
- **370-01-SPEC.md**: Group (4) PRESALE in Section 1 documents both fix parts (a) and (b) in detail, including the tiered-divisor rationale grounded in the frozen accrual mechanics (flat 100-BURNIE slot-0 + scaling buyer-bonus doubling at `>=10 tickets`). The edit-order table in Section 3 reflects the expanded PRESALE-01 scope at `GameAfkingModule.sol:394-398` with both the CANCEL settle lift and the tiered divisor at `:357-358` & `:1599-1600`.
- **ROADMAP.md**: Phase 370 marked `[x]` completed; Phase 371 PRESALE-01 success criterion matches the expanded form.

The expansion is internally consistent across all three documents.

---

### Contract Integrity Gate

| Check | Status | Evidence |
|-------|--------|---------|
| `git diff 2b26ec91 HEAD -- contracts/` is empty | PASSED | Command produced no output — contracts byte-identical to frozen baseline. |
| `git status --porcelain contracts/` is empty | PASSED | Command produced no output — no working-tree contract drift. |
| Phase produces ZERO `contracts/*.sol` modifications | PASSED | All commits in the phase are `docs(370-*)` type. `git log --oneline 2b26ec91..HEAD -- ':!contracts/'` shows only docs commits; no contract path appears in any stat. |

---

### WINDOW-01 Section Integrity Check

Section 4 of 370-01-SPEC.md contains the exhaustive `frozenUntilLevel` classification table. Spot-checked against the plan requirements:

- **Exactly 6 FLIP comparisons**: Confirmed — MintModule `:291`/`:295`, MintStreakUtils `:56`/`:262`/`:310`, DegenerusGame `:1678`. The table contains 22 classified rows with exactly 6 marked "FLIP".
- **3 EXTENSION sites untouched**: `WhaleModule:221`, `Storage:1070`, `Storage:1151` — all marked EXTENSION, rationale: "`> targetFrozenLevel` renewal-horizon max — different semantics."
- **1 EARLY-RENEWAL guard untouched**: `WhaleModule:428` `> currentLevel + 7` — marked EARLY-RENEWAL.
- **Afking eviction boundary re-confirmed**: The section explicitly cites `processSubscriberStage` (`GameAfkingModule.sol:1103`) and the evict gate `currentLevel > sub.validThroughLevel` (`:1191`) — keeps funded sub through level 10 inclusively, evicts at 11.
- **Post-flip semantics**: After the 6 flips, freeze clears at `lvl > frozenUntilLevel` (level 11), making freeze/floor/bonus/view cover 1–10 inclusively — MATCHING the already-inclusive afking boundary, not diverging.

---

### SOLV-01 Variant Rationale Integrity Check

The F-03 variant (a) rationale in Section 2 of 370-01-SPEC.md cites frozen bodies at specific AS-FOUND lines:

- `runBafJackpot` (`JackpotModule.sol:1901-1909`) — accumulates `claimableDelta` ONLY from `_addClaimableEth`, documented by the trailing comment `~:1976-1977` in the frozen source.
- `_queueWhalePassClaimCore` — `internal` with no return type; `claimablePool += uint128(remainder)` at `:58` bumps the pool inline without any return.
- `AdvanceModule:802` cached-local `memFuture` read once, written back at `:968` single `_setPrizePools` — the decisive structural fact that makes variant (b) incorrect (mid-loop `_setFuturePrizePool` would be silently clobbered).
- `_processSoloBucketWinner` (`JackpotModule.sol:1382`) — the push-back pattern that works only OUTSIDE the cached-`memFuture` window, explaining why it cannot be the BAF precedent.

The rationale is internally consistent and grounded in the frozen function bodies as required.

---

### Anti-Patterns Found

No `TBD`, `FIXME`, or `XXX` markers found in the phase artifacts. The SPEC and adjudication documents use lean functional prose per the project's `lean-code-comments-no-procedural-meta` rule. No stubs, no placeholder sections, no return nulls. The Gemini result (`area-solvency.gemini.txt`) is a genuine substantive response — 31 lines with concrete file:line cites into the frozen tree — not a Plan-Mode refusal.

| File | Pattern | Severity | Impact |
|------|---------|---------|--------|
| (none) | — | — | — |

---

### Human Verification Required

None. This is a paper/harness-only phase. The artifacts are documents and a recorded external-model run:

- The anchor re-attestation table is grep-verifiable and was verified above via the SPEC structure and commit evidence.
- The F-03 variant choice is a design decision backed by a written rationale — verified as substantive above.
- The WINDOW-01 classification is a complete enumeration of a `git grep` result — verified as covering 22 classified rows including exactly 6 FLIPs.
- The COV-01 Gemini run is on disk and was inspected directly — the raw output is a genuine frozen-source read with concrete cites.

No UI, no real-time behavior, no external service integration requiring human testing. Section 8 is empty.

---

### Gaps Summary

No gaps. All 4 ROADMAP success criteria are satisfied in writing:

1. **SC1 (SPEC-01 part 1)** — F-03/SOLV-01 variant locked to (a) with frozen-body rationale; producer-before-consumer edit order mapped for all 9 IMPL reqs with two explicit chains.
2. **SC2 (SPEC-01 part 2)** — 7 anchor groups, 24 distinct anchors, all grep-verified, all drifts corrected, 0 unverified.
3. **SC3 (SPEC-01 part 3)** — WINDOW-01 exhaustive `frozenUntilLevel` classification: 6 FLIPs confirmed, 3 EXTENSION + 1 EARLY-RENEWAL untouched, afking eviction boundary re-confirmed inclusive-through-`validThroughLevel`.
4. **SC4 (COV-01)** — Second independent model (Gemini, not the v58 Codex leg) genuinely read frozen 2b26ec91 via materialized source pack; all 4 model outputs adjudicated; K = 0 net-new; TERMINAL carry-forward note written; COV-01 marked Complete in REQUIREMENTS.md.

Both REQUIREMENTS.md requirement IDs (SPEC-01, COV-01) carry `[x]` checkboxes and "Complete" status entries in the traceability table. Contract integrity is pristine — zero drift from frozen 2b26ec91.

---

_Verified: 2026-06-04T23:00:00Z_
_Verifier: Claude (gsd-verifier)_
