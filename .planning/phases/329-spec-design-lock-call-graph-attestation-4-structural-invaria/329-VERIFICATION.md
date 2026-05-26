---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
verified: 2026-05-26T00:00:00Z
status: passed
score: 4/4
overrides_applied: 0
---

# Phase 329: SPEC Design-Lock Verification Report

**Phase Goal:** The 4 load-bearing structural invariants are locked in writing, every shared signature (the advanceGame return shape, the doWork(maxCount) signature, the O(1) discovery views) is settled, the ROUTER-07 reentrancy disposition (GAS-03 single day-start epoch + the OPEN-C guard-vs-CEI decision) is resolved, and every cited file:line + the bounty/gas math is grep-verified against the v48.0-closure HEAD 0cc5d10f — so the IMPL phase authors a fully reconciled diff with zero 'by construction' assumptions and the VRF-freeze invariant is proven to survive the new router composition on paper before any code is written.
**Verified:** 2026-05-26
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1 — 4 structural invariants locked in writing (BATCH-01): (a) one-category early-return, (b) frozen advance-consume incl. totalFlipReversals (ADV-04), (c) guaranteed free-fallback advanceGame() caller, (d) single day-start epoch (GAS-03) | VERIFIED | 329-SPEC.md §2 has labeled subsections for each invariant citing decision id + ATTEST grep verdict + IMPL instruction. Spot-grepped: totalFlipReversals at AdvanceModule:1838+:1844 MATCH; 30-min bypass at :1012 MATCH; Vault/sStonk wrappers MATCH; death-clock at :109/:1200 MATCH; dual-epoch formulas at AfKing:829 + AdvanceModule:243-246 MATCH. |
| 2 | SC2 — shared signatures settled: advanceGame return shape (design-1 (uint8 mult, bool rewardable) + :275 wrapper decode), doWork(maxCount) + ROUTER-06 NoWork() signal, 3 O(1) discovery views (advanceDue covering new-day AND mid-day partial-drain, boxesPending(), buys-pending via AfKing cursor) | VERIFIED | 329-SPEC.md §1 R1-R4 each settle one signature with producing file + consuming files + apply-order. Design-1 `(uint8 mult, bool rewardable)` distinct-bool tuple confirmed (Plan 01 §D.2). advanceDue covers both new-day (currentDayView()!=dailyIdx) AND mid-day (LR_MID_DAY!=0). boxesPending() O(1). buys-pending AfKing-local cursor. D-06 maxCount==0 default (fixed count, NOT gasleft) locked at R2. |
| 3 | SC3 — ROUTER-07 reentrancy disposition decided (a nonReentrant guard OR a proven composed-CEI argument); v48 KEEP-04 affiliate-code wiring confirmed valid at v49 HEAD | VERIFIED | NO nonReentrant guard decided (D-01). Per-leg no-untrusted-ETH-send grep done in 329-ATTEST-ROUTER-ADVANCE.md §B (0 untrusted-push legs; advance makes ZERO ETH sends, autoOpen/_autoBuy route through claimableWinnings pull, bounty as creditFlip flip-credit, CEI-last). Formal basis recorded verbatim in SPEC §2 disposition ROUTER-07. KEEP-04 bytes32("DGNRS") at DegenerusGame.sol:1781 confirmed live (SHIFTED +3 from v48 :1778 — recorded as carried correction C1). This is the locked D-01/D-01a "proven composed-CEI argument" branch per the LOCKED-DECISION nuances. |
| 4 | SC4 — every cited file:line grep-verified against 0cc5d10f; any drift corrected in the SPEC; no "by construction" survives unchecked; producer-before-consumer edit-order map confirmed | VERIFIED | `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` returns EMPTY (verified independently during this verification). 34 router/advance anchors attested at 0 ABSENT / 0 blockers. Line-drifts C1-C6 carried (KEEP-04 +3, 30-min bypass +4, death-clock +2, GASOPT-01 sites, gas-peg range, interface-file ABSENT correction). Producer-before-consumer edit-order map in §3: AdvanceModule → Game wrapper/views → interfaces → AfKing router/_autoBuy/re-peg/micro-opts. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-ROUTER-ADVANCE.md` | Per-anchor grep tables for the router/advance surface, the per-leg no-untrusted-ETH-send attestation (D-01a), the dual-epoch attestation (D-03), the invariant-(c) fallback-caller attestation (D-04), the totalFlipReversals freeze attestation (ADV-04), and the GASOPT-01/02 hoist-site confirmation | VERIFIED | 347 lines. Sections A (13 AfKing anchors) / B (per-leg no-untrusted-ETH-send, 0 ROUTER-07 blockers) / C (GAS-03 dual-epoch + GASOPT-01 hoist) / D (AdvanceModule + wrapper + 3 creditFlip classifications) / E (ADV-04 totalFlipReversals freeze) / F (O(1) discovery views + maxCount + D-06 baseline) / G (invariant-(c) free-fallback callers) all present. Roll-up present. Verdict legend present. Byte-identical-to-0cc5d10f header note present. 34 anchors: 34 MATCH / 0 ABSENT / 0 IMPL blockers. |
| `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-DEGENERETTE-RESOLVE.md` | The autoResolve→degeneretteResolve rename-surface attestation, the D-05f losing-bet-liveness grep-finding (the load-bearing deliverable), the D-05c real-gas exploitability basis, the D-05b flat-~1-BURNIE/≥3-gate/revert-on-no-work shape feasibility, and the architectural-non-foldability confirmation — all at HEAD 0cc5d10f | VERIFIED | 362 lines. Sections A (rename surface — 3 contract targets + ABSENT interface correction + 5 test files/57 refs incl. CrankLeversAndPacking literal-string assertions) / B (payment-shape feasibility FEASIBLE) / C (real-gas exploitability NET LOSS, NOT the 0.5-gwei peg ref) / D (D-05f losing-bet liveness: INERT-SAFE, SURFACE-TO-USER NONE — 8 consumers enumerated, GameOver/Jackpot/Advance grep-CLEAN) / E (ROUTER-05 non-foldability CONFIRMED) all present. Roll-up present. 0 IMPL blockers. |
| `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md` | The reconciled v49.0 design-lock blueprint: §0 attestation verdict roll-up, §1 settled shared signatures (advanceGame return / doWork+NoWork / O(1) discovery views), §2 the 4 structural invariants + the ROUTER-07/GAS-03 dispositions + the D-05 design-lock, §3 per-item IMPL blueprint + producer-before-consumer edit-order map | VERIFIED | 194 lines. §0 (attestation roll-up with C1-C6 carried corrections + all 5 load-bearing decision verdicts) / §1 (R1-R4 shared signatures, each with producing+consuming files + apply-order) / §2 (4 invariants + ROUTER-07 disposition + GAS-03 disposition + D-05a-g design-lock) / §3 (Files in the diff + edit-order map + one blueprint paragraph per work-area + SC1..SC4 checklist) all present. SOURCE-TREE not mutated line present twice. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| CONTEXT locked decisions D-01..D-06g | 329-SPEC.md §2 dispositions and invariants | Each D-NN decision cited in the corresponding §2 subsection | VERIFIED | Every locked decision from 329-CONTEXT.md is cited by ID in 329-SPEC.md §2 and resolved with an IMPL instruction. D-01/D-01a (NO nonReentrant) → SPEC §2 Disposition ROUTER-07. D-03/D-03a (epochs intentionally distinct) → §2 Invariant (d). D-04 (existing free-fallback paths only) → §2 Invariant (c). D-05a-g (degeneretteResolve design lock) → §2 D-05 design-lock. D-06 (maxCount==0 fixed default) → §1 R2. |
| Two 329-ATTEST-*.md docs (Wave-1 deliverables) | 329-SPEC.md §0 verdict roll-up + §1 signatures + §2 invariants/dispositions | Fold attestation drift + decision verdicts + D-05f finding into the locked design | VERIFIED | §0 aggregate verdict table references both ATTEST docs, zero material ABSENT, 0 blockers. Every ATTEST-ROUTER-ADVANCE load-bearing verdict (ROUTER-07 no-guard / GAS-03 epochs-distinct / ADV-04 no-new-in-window-read / invariant-(c) fallbacks-intact) is carried verbatim into §0 and §2. D-05f INERT-SAFE finding from ATTEST-DEGENERETTE-RESOLVE carried verbatim into §0 and §2, explicitly NOT softened. |
| 4 structural invariants + design-1 advanceGame return | Producer-before-consumer edit-order map for Phase 330 | §3 "Files in the diff" + edit-order | VERIFIED | §3 names the exact 5-step edit-order: (1) AdvanceModule delete 3 creditFlip sites + add design-1 return; (2) DegenerusGame :275 wrapper decode + discovery views + BATCH-02 rename/re-peg; (3) interfaces; (4) AfKing doWork router + _autoBuy refactor; (5) MintModule GASOPT-01. One blueprint paragraph per work-area. |
| The no-guard disposition (D-01) | Grep-checked per-leg no-untrusted-ETH-send basis | 329-ATTEST-ROUTER-ADVANCE.md §B per-leg rows | VERIFIED | Section B has one row per doWork leg (advance/autoOpen/_autoBuy) with grep evidence. Advance: ZERO .call{value} in AdvanceModule. autoOpen: player value via claimableWinnings pull, send only to pinned ContractAddresses.*. _autoBuy: unspent-value refund to pinned keeper-contract AfKing only. Bounty as creditFlip flip-credit, keeper-never-a-payee, CEI-last. 0 ROUTER-07 blockers. Formal basis recorded verbatim. |

### Data-Flow Trace (Level 4)

This is a paper-only SPEC phase — no runnable components render dynamic data. There are no React components, API routes, or data-fetching hooks to trace. Level 4 data-flow trace is not applicable.

### Behavioral Spot-Checks

Step 7b: SKIPPED — paper-only deliverables; no runnable entry points exist in this phase.

### Probe Execution

Step 7c: No probe scripts referenced in plan or summary. Phase is docs-only. No probes to execute.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BATCH-01 | Plans 01, 02, 03 | SPEC design-lock — lock 4 structural invariants, settle shared signatures, grep-attest every cited file:line vs v48.0 HEAD | SATISFIED | 329-ATTEST-ROUTER-ADVANCE.md (34 anchors, 0 blockers) + 329-ATTEST-DEGENERETTE-RESOLVE.md (rename surface + D-05f + D-05c + D-05b + ROUTER-05) + 329-SPEC.md (§0 roll-up + §1 signatures + §2 invariants + §3 edit-order map). All 4 invariants locked as CODE invariants with IMPL instructions. |
| ROUTER-07 | Plans 01, 03 | Router reentrancy disposition decided at SPEC (guard vs proven composed-CEI) | SATISFIED | D-01 NO guard decided on per-leg no-untrusted-ETH-send grep basis (D-01a). Formal basis recorded verbatim in 329-SPEC.md §2 Disposition ROUTER-07. D-01b TST-02 empirical backstop scoped to Phase 332. 0 untrusted-push legs found — confirmed by independent spot-checks during this verification. |
| ADV-04 | Plans 01, 03 | Router advance-consume reads only frozen VRF-window state; totalFlipReversals nudge stays frozen | SATISFIED | 329-ATTEST-ROUTER-ADVANCE.md §E: totalFlipReversals :1838 read + reset :1844 inside _applyDailyRng :1834 MATCH. Backward-trace confirms router consumes via design-1 return, adds NO new mutable in-window SLOAD. 329-SPEC.md §2 Invariant (b) locks the router ordering with IMPL instruction. TST-01 empirical freeze fuzz handed to Phase 332. |
| GAS-03 | Plans 01, 03 | Stall multiplier uses a single unified day-start epoch | SATISFIED | Design-1-satisfies resolution (D-03/D-03a) confirmed. Both epoch formulas grep-attested: AfKing absolute-day today*1days+82_620 at :829 MATCH; AdvanceModule game-day (day-1+DEPLOY_DAY_BOUNDARY)*1days+82_620 at :243-246 MATCH. Intentionally-distinct rationale documented with WHY-they-differ explanation. SPEC cross-references invariant (d). This is the locked D-03 resolution (not a gap). |

**Requirements ownership:** REQUIREMENTS.md Traceability table assigns exactly {BATCH-01, ROUTER-07, ADV-04, GAS-03} to Phase 329. All 4 are SATISFIED by the deliverable documents. The remaining 27 requirements are correctly assigned to Phases 330-333 — no orphaned requirements for this phase.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| 329-SPEC.md | 75, 184 | "SPEC PLACEHOLDERS" — break-even peg constants + RESOLVE_FLAT_BURNIE + D-06 default-count constants not pinned | INFO | Intentional and tracked: D-06g explicitly routes calibration to GAS Phase 331 with a reference to the v46 Phase 319 CR-01 "peg to the marginal" discipline. D-05e routes the ~1 BURNIE literal to GAS Phase 331. These are design-time deferrals with formal traceability, not unresolved code stubs. |

No TBD, FIXME, or XXX markers found in any of the three deliverable documents. No `return null`, stub handlers, or empty implementations (this is a paper-only attestation phase; the deliverables are documentation, not code). No contracts/*.sol modified (confirmed via `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` returning EMPTY).

### Human Verification Required

None. This is a paper-only SPEC design-lock phase with no runnable code, no visual UI components, and no external service integrations. All observable truths are verifiable by document inspection and grep. All truths resolved to VERIFIED.

### Gaps Summary

No gaps. All 4 roadmap success criteria are verified.

The phase delivered exactly what it committed to: three substantive planning documents (329-ATTEST-ROUTER-ADVANCE.md, 329-ATTEST-DEGENERETTE-RESOLVE.md, 329-SPEC.md) each with content that independently verifies against live contract source at baseline 0cc5d10f. The two locked-decision nuances (GAS-03 design-1-satisfies and ROUTER-07 NO-guard via composed-CEI) are correctly resolved as documented decisions, not gaps. The D-05 degeneretteResolve item is correctly present in 329-SPEC.md §2 as a v49.0 design item even though its code lands at Phase 330 and its REQ-IDs (GAS-06/TST-05) are owned by 331/332.

---

_Verified: 2026-05-26_
_Verifier: Claude (gsd-verifier)_
