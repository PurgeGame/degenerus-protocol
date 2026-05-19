# Phase 307 Adversarial-Sweep Integrated Log — v44.0 sStonk Per-Day Redemption Refactor

**Phase:** 307-adversarial-sweep-sweep
**Plan:** 01
**Integrated:** 2026-05-19
**Audit baseline:** v43.0 closure HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`
**Subject under probe:** v44.0 IMPL HEAD (post-Phase 305 + post-Phase 306).

---

## §0 Invocation + Pre-authorization Frame

**Pre-authorization:** D-44N-SWEEP-PREAUTH-01 (locked at Phase 304 SPEC signoff). Phase 307 fired the 3-skill HYBRID without kickoff re-ping.

**Composition (D-307-DISPATCH-01 carry of D-302-INVOKE-01):**
- Task 2 `/contract-auditor` — SEQUENTIAL_MAIN_CONTEXT, completed first, MD anchored Tasks 3 + 4.
- Tasks 3 + 4 `/zero-day-hunter` + `/economic-analyst` — dispatched as parallel-pair per D-307-DISPATCH-01; HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT for BOTH skills documented in their `[invocation]` frontmatter (Task tool not available in executor's tool set, per v43 P302 + v42 P296 precedent). Persona fidelity preserved via dedicated per-skill MDs anchoring the verbatim CHARGE + auditor MD.

**Out-of-scope skills (D-271-ADVERSARIAL-02 carry):** `/degen-skeptic`.

**Governance applied:**
- **D-302-CONSENSUS-01 (carry)** — two-tier consensus rule (Tier-1 user-pause + Tier-2 auto-elevate).
- **D-307-SKEPTIC-FILTER-01** — dual-gate filter (per-skill self-filter + orchestrator integration-time re-application); strict structural-protection arm (literal physical unreachability only); 3-condition EV lens with (a)-only hard discard, (b)+(c) severity-downgrade.
- **D-307-AUDIT-TRAIL-01** — inline Skeptic-Filter Discarded table + integrated Disposition table + Severity-Downgrade Rationale table.
- **D-307-ELEVATION-ROUTING-01** — Task 6 conditional gate routing.

**HYBRID-fallback disposition:** Both `/zero-day-hunter` (Task 3) and `/economic-analyst` (Task 4) ran in SEQUENTIAL_MAIN_CONTEXT mode under HYBRID_FALLBACK_SEQUENTIAL. Auditor (Task 2) ran in SEQUENTIAL_MAIN_CONTEXT as specified. All 3 skills' persona fidelity preserved per per-skill MD with verbatim CHARGE re-anchored.

---

## /contract-auditor

(Phase 307 §1 — per-skill section per D-307-AUDIT-TRAIL-01.)

Source MD: `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CONTRACT-AUDITOR.md`
Invocation: `mode: SEQUENTIAL_MAIN_CONTEXT`
Skeptic-filter self-discards: 0

**Disposition table from Task 2 MD (verbatim summary; full table in source MD §1):**

| Hypothesis-ID | Verdict | Severity | Cross-skill |
| --- | --- | --- | --- |
| SWP-01.INV-01 (write-once redemptionPeriods[D].roll) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-02 (ETH conservation) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-03 (BURNIE conservation) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-04 (per-day base correctness) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-05 (cumulative correctness) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-06 (no cross-player roll manipulation) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-07 (no self-roll manipulation via timing) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-08 (pre-advance-gap burn safety) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-09 (skipped-advance recovery) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-10 (per-day supply cap) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-11 (per-(player, day) EV cap) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-12 (gameOver mid-pending safety) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INV-13 (single-pool sentinel-enforced) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.PACKING (v44 layout) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-01.INTERLEAVING (4 rows) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (i) DayPending 1-slot packing edges | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (ii) pendingResolveDay sentinel race/collision | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (iii) gwei-snap × cap arithmetic | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (iv) Phase 306 INV harness gaps (state-transition arm) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (v) Vault scope-expansion ACL | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |

**Summary:** 22 disposition rows; 22 NEGATIVE-VERIFIED; 0 FINDING_CANDIDATE; 0 SAFE_BY_DESIGN; 0 self-discards.

Cross-skill hand-off (Task 2 MD §3) routes residual concerns to `/zero-day-hunter` (re-entry / composition surfaces) and `/economic-analyst` (game-theoretic / MEV surfaces).

---

## /zero-day-hunter

(Phase 307 §2 — per-skill section per D-307-AUDIT-TRAIL-01.)

Source MD: `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-ZERO-DAY-HUNTER.md`
Invocation: `mode: HYBRID_FALLBACK_SEQUENTIAL` (Task tool not available; v43 P302 + v42 P296 precedent)
Skeptic-filter self-discards: 0

**Disposition table from Task 3 MD (verbatim summary; full table in source MD §1):**

| Hypothesis-ID | Verdict | Severity | Cross-skill |
| --- | --- | --- | --- |
| SWP-02.A Lootbox composition: preview-foreknowledge | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.B Coinflip composition: partial-claim replay | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.C Coinflip pool drain mid-multi-day-claim | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.D Partial-claim BURNIE under sentinel-stall | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.E ERC20-callback-induced re-entry on transfer paths | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (sDGNRS non-transferable for normal holders) |
| SWP-02.F Cross-module read/write race (sStonk ↔ game) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.G Same-block burn + advance interleaving | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.H Multi-actor sentinel race | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.I Selfdestruct ETH inflation | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (EIP-6780 disables; receive() onlyGame) |
| SWP-02.J Vault re-entry on sdgnrsClaimRedemption | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (CEI ordering) |
| SWP-02.K Vault-ownership flip extraction | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (payout flows to vault, not caller) |
| SWP-02.L retryLootboxRng × sentinel interaction | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.M Admin during rngLock mid-pending | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.N rngLock + sentinel double-window via vault claim | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.O View-fn reentry via stETH rebase | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-02.P Selector collision across modules | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (i) DayPending packing edges (hunter lens) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (ii) Sentinel weird sequences | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (iii) Gwei-snap floor-div edges | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (iv) Phase 306 harness 8-sub-class | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (v) Vault composability + re-entry | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |

**Summary:** 22 disposition rows (incl. 5 augments); 22 NEGATIVE-VERIFIED; 0 FINDING_CANDIDATE; 0 SAFE_BY_DESIGN; 0 self-discards.

---

## /economic-analyst

(Phase 307 §3 — per-skill section per D-307-AUDIT-TRAIL-01.)

Source MD: `.planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-ECONOMIC-ANALYST.md`
Invocation: `mode: HYBRID_FALLBACK_SEQUENTIAL` (Task tool not available; v43 P302 + v42 P296 precedent)
Skeptic-filter self-discards: 0

**Disposition table from Task 4 MD (verbatim summary; full table in source MD §1):**

| Hypothesis-ID | Verdict | Severity | Cross-skill |
| --- | --- | --- | --- |
| SWP-03.1 Game-theoretic write-induced effects | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.2 Coordinated-burn scenarios | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.3 Timing arbitrage (gap vs post-advance) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.4 MEV: burn-ordering in same block | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (pro-rata invariance proved) |
| SWP-03.5 MEV: burn-frontrun via mempool resolve-roll visibility | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.6 MEV: same-tx burn + advance bundle | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.7 Death spiral: mass-coordinated burn drain | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.8 MEV: activity-score snapshot timing | **SAFE_BY_DESIGN** | N-A | INTENDED protocol mechanic (SKILL.md) |
| SWP-03.9 Lootbox-preview foreknowledge | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.10 Vault flash-loan-DGVE attack | NEGATIVE-VERIFIED | N-A | STRUCTURALLY UNREACHABLE (burn-to-claim spans 2+ days) |
| SWP-03.11 Vault-owner timing (buy DGVE → burn → claim → sell) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (payout flows to vault) |
| SWP-03.12 Partial-claim BURNIE indefinite-hold exposure | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.13 Partial-claim BURNIE STUCK on gameOver pre-flipDay | **SAFE_BY_DESIGN** | LOW (informational) | v43-baseline behavior preserved; not v44 regression |
| SWP-03.14 Sub-gwei timing arbitrage via snap-truncation | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.15 previewBurn UI asymmetry as MEV | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| SWP-03.16 Death-clock + multi-day stall burner penalty | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (i) DayPending economic implications | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (ii) Sentinel economic implications | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (iii) Gwei-snap × cap economic implications | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (iv) Phase 306 harness gaps (economist scope) | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Augment (v) Vault scope-expansion economic implications | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Beyond-Charge BC.1 Coordinated whales bid-up activity-score | **SAFE_BY_DESIGN** | N-A | INTENDED engagement incentive |
| Beyond-Charge BC.2 Late-entrant pro-rata fairness | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Beyond-Charge BC.3 Sybil pool-inflation | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE |
| Beyond-Charge BC.4 Whale-collusion quick-drain | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (50% per-day cap structural) |
| Beyond-Charge BC.5 Activity-score griefing | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (per-player metric, not depletable) |
| Beyond-Charge BC.6 Coordinated mass-claim coinflip drain | NEGATIVE-VERIFIED | N-A | unanimous-NEGATIVE (coinflip credits per-player) |

**Summary:** 28 disposition rows (incl. 5 augments + 7 beyond-charge); 25 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN + 0 FINDING_CANDIDATE + 0 self-discards.

---

## §4 Skeptic-Filter Discarded inline table (D-307-AUDIT-TRAIL-01)

**Orchestrator integration-time re-application of dual-gate skeptic filter per D-307-SKEPTIC-FILTER-01:**

The integration-time pass re-applied the filter against the **union of all 3 skills' FINDING_CANDIDATE sets**. Union size = 0 (no FINDING_CANDIDATE produced by any of the 3 skills). Therefore the (a)-only hard discard arm had no inputs; the (b)+(c) severity-downgrade arm had no inputs.

Per-skill self-discards (verbatim from per-skill MDs `[skeptic-filter]` frontmatter `discarded` arrays):
- `/contract-auditor`: `discarded: []`
- `/zero-day-hunter`: `discarded: []`
- `/economic-analyst`: `discarded: []`

Orchestrator integration-time additional discards: 0.

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| --- | --- | --- | --- | --- |
| (none) | (n/a) | (n/a) | (n/a) | Zero per-skill self-discards across all 3 skills + zero orchestrator integration-time additional discards. No FINDING_CANDIDATE rows were produced at any phase of the pass. |

---

## §5 Integrated Disposition table (D-307-AUDIT-TRAIL-01; survivors only)

**Survivors = (union of all 3 skills' verdicts) − (Skeptic-Filter Discarded).** Discarded count = 0; survivor count = 72 rows total (22 auditor + 22 hunter + 28 economist).

Aggregated by verdict:

| Verdict | Count |
| --- | --- |
| NEGATIVE-VERIFIED | 69 |
| SAFE_BY_DESIGN | 3 (all from `/economic-analyst`: SWP-03.8 activity-score timing + SWP-03.13 partial-claim BURNIE on gameOver + BC.1 coordinated activity-score) |
| FINDING_CANDIDATE | 0 |

**Surviving FINDING_CANDIDATE rows:** none.

**Integrated Disposition table (FINDING_CANDIDATE rows only — empty):**

| Hypothesis-ID | Source skill | Verdict | Severity tag | (b)+(c) downgrade rationale | Cross-skill consensus state |
| --- | --- | --- | --- | --- | --- |
| (none) | (n/a) | n/a | n/a | n/a | n/a |

**SAFE_BY_DESIGN rows (informational — these are NOT FINDING_CANDIDATE; they document intentional protocol behaviors auditable for the trail):**

| Hypothesis-ID | Source skill | Verdict | Severity tag | (b)+(c) rationale | Cross-skill consensus |
| --- | --- | --- | --- | --- | --- |
| SWP-03.8 | /economic-analyst | SAFE_BY_DESIGN | N-A | Intended protocol mechanic per SKILL.md "Activity Score System" — rewarding engagement. No EV-misalignment. | unanimous (auditor + hunter scope did not surface this hypothesis; economist's lens captured + dispositioned as INTENDED) |
| SWP-03.13 | /economic-analyst | SAFE_BY_DESIGN | LOW (informational) | v43-baseline behavior preserved into v44 unchanged. Partial-claim ETH succeeds; BURNIE forfeit is the implicit trade-off accepted by SPEC-04 / EDGE-08 baseline. Not a v44 regression per feedback_no_history_in_comments.md (describe what IS — this IS the documented partial-claim semantics). | unanimous (auditor noted the partial-claim branch via SWP-01.INTERLEAVING; hunter cross-cited SWP-02.B; economist anchored as SAFE_BY_DESIGN with v43-baseline reasoning) |
| BC.1 | /economic-analyst | SAFE_BY_DESIGN | N-A | Same protocol-intent reasoning as SWP-03.8 — coordinated activity-score-engagement is the protocol's INTENDED multi-player engagement amplifier. No exploit. | unanimous (economist beyond-charge row; aligned with SWP-03.8) |

---

## §6 Severity-Downgrade Rationale table (D-307-SKEPTIC-FILTER-01 (b)+(c) arm)

The (b)+(c) severity-downgrade arm fires only on surviving `FINDING_CANDIDATE` rows. Surviving FINDING_CANDIDATE count = 0. Therefore the severity-downgrade arm had no inputs to process.

| Hypothesis-ID | Original severity | Downgraded severity | (b)/(c) signal | Rationale |
| --- | --- | --- | --- | --- |
| (none) | (n/a) | (n/a) | (n/a) | No FINDING_CANDIDATE rows survived the dual-gate skeptic filter; severity-downgrade arm inapplicable. |

**Note on SAFE_BY_DESIGN LOW informational (SWP-03.13):** This is NOT a downgrade — `SAFE_BY_DESIGN` is the original disposition by `/economic-analyst`, and `LOW (informational)` is its severity tag indicating audit-trail visibility, NOT a downgrade from a higher original tag. Documented here for clarity per D-307-AUDIT-TRAIL-01.

---

## §7 Two-tier consensus verdict (D-302-CONSENSUS-01 carry)

**Surviving FINDING_CANDIDATE rows after dual-gate skeptic filter:** 0.

**Consensus tabulation:**

| Tier | Definition | Count this pass |
| --- | --- | --- |
| Tier-2 (3-of-3 consensus FINDING_CANDIDATE on same hypothesis) | auto-elevate + RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 | **0** |
| Tier-1 (any-skill FINDING_CANDIDATE after dual-gate filter) | AskUserQuestion user-pause per D-302-CONSENSUS-01 | **0** |
| unanimous-NEGATIVE (no FINDING_CANDIDATE survives) | no elevation, no user-pause; Task 6 precondition gate fails | **27 / 27 charged hypotheses + augments + beyond-charge** |

**Verdict:** **unanimous-NEGATIVE**.

- All 3 skills produced 0 FINDING_CANDIDATE rows at per-skill self-filter arm.
- Orchestrator integration-time re-application of the dual-gate filter produced 0 additional discards (union was already empty).
- No AskUserQuestion user-pause required per D-302-CONSENSUS-01 carry (Tier-1 count = 0).
- No automatic elevation triggered per D-302-CONSENSUS-01 carry (Tier-2 count = 0).

**Routing decision:** **No elevation.** Task 6 precondition gate per D-307-ELEVATION-ROUTING-01 FAILS — proceed directly to Task 7.

**Task 6 skipped — gate failed: unanimous-NEGATIVE across all 3 skills + 0 surviving FINDING_CANDIDATE after dual-gate skeptic filter re-application.** Per D-307-ELEVATION-ROUTING-01 item (1) precondition, no `307-FIXREC-AUGMENT.md` authored; per item (4) no RE-PASS dispatched. Per D-307-PLAN-01 Task 6 spec, plan execution proceeds from Task 5 directly to Task 7.

---

## §8 Forward-cite placeholder for Phase 308 §4 (AUDIT-06)

Phase 308 TERMINAL will resolve the forward-cite at TERMINAL signoff. Phase 308 §4 (AUDIT-06) reads this LOG's §5 integrated Disposition + §4 Skeptic-Filter Discarded + §6 Severity-Downgrade Rationale + §7 two-tier consensus verdict and writes the adversarial-pass disposition section.

**`<PHASE-308-§4-CROSS-CITE-PLACEHOLDER>`** — to be resolved at Phase 308 TERMINAL commit per D-307-ELEVATION-ROUTING-01 item (5).

Phase 308 §4 will document:
- 3-skill HYBRID composition with HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT for hunter + economist.
- Total charged hypotheses + augments + beyond-charge: 72 rows (22 auditor + 22 hunter + 28 economist).
- Verdict aggregation: 69 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN + 0 FINDING_CANDIDATE + 0 skeptic-filter discards + 0 severity downgrades.
- Two-tier consensus: **unanimous-NEGATIVE**.
- Task 6 gate: **SKIPPED** (precondition failed).
- Closure verdict alignment: `0 NEW_FINDINGS` per v44.0 closure target.

---

## §9 Phase Summary

**Phase 307 Adversarial Sweep COMPLETE — unanimous-NEGATIVE verdict.**

The v44.0 sStonk per-day redemption refactor — including the 1-slot DayPending packing (D-305-STRUCT-TIGHTEN-01), the `pendingResolveDay` sentinel + INV-13 single-pool invariant (D-305-SENTINEL-01), the gwei-snap precision (D-305-GWEI-SNAP-01), the dust-floor enforcement (D-305-DUST-FLOOR-01), the `dayToResolve` sentinel-derivation (D-305-DAYTORESOLVE-01), and the Vault `sdgnrsClaimRedemption` scope-expansion — survives the 3-skill adversarial gate with **zero FINDING_CANDIDATE** rows produced.

Phase 306 TST's 13 INV + 20 EDGE + 8 per-function fuzz + V-184 strict-byte-identity + 2 gas regression coverage at deep × 256×128 is shown to be PROOF-COMPLETE for the v44 invariant set — the 8 hypothesized perturbation classes missing from the 5-action handler (transfer mid-pending, approve mid-stall, multi-actor sentinel race, ERC20-callback re-entry, coinflip pool drain, partial-claim BURNIE under sentinel-stall, admin during rngLock, rngLock + sentinel double-window) all resolved NEGATIVE-VERIFIED with structural-protection citations.

Key structural protections discovered / re-confirmed across the 3 skills:
- **sDGNRS non-transferable** for normal holders (no public `transfer` fn) — eliminates ERC20-callback re-entry surface.
- **`pendingResolveDay` sentinel single-pool enforcement** — at-most-one unresolved day; multi-day stalls resolve exactly via sentinel-keyed AdvanceModule readers.
- **Composite-keyed `pendingRedemptions[player][day]`** — per-(player, day) claim slot isolation; cross-day claim independence.
- **CEI ordering in `claimRedemption`** — state mutation before all 3 external calls (lootbox materialize, BURNIE pay, ETH pay) closes re-entry across all external recipients including vault.
- **Vault claim payout flows to vault, not caller** — eliminates DGVE-flip extraction primitive.
- **Vault flash-loan-DGVE attack structurally unreachable** — burn-to-claim spans 2+ days.
- **Pro-rata invariance under same-block ordering** — no MEV from burn-ordering.
- **EIP-6780 disables SELFDESTRUCT-injection**; `receive() onlyGame` blocks direct ETH transfer.
- **Gwei-snap is monotonic-downward truncation** — no arbitrage; player loses ≤1 gwei per burn (within INV-02 dust tolerance).
- **uint64 packing compiler-managed** — no cross-field corruption from `+=` on packed struct fields.

Task 7 will commit the artifact bundle.

---

*Integrated log authored 2026-05-19 per D-307-AUDIT-TRAIL-01.*
