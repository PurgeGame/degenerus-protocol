---
phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
verified: 2026-05-30T00:00:00Z
status: passed
score: 5/5
overrides_applied: 0
---

# Phase 348: SPEC — Design-Lock + Freeze Proof + Discharged-Invariant Carry — Verification Report

**Phase Goal:** The AfKing-in-Game redesign's shapes are settled in writing so the 349 IMPL phase authors a fully reconciled, code-size-safe diff with zero "by construction" assumptions, and the FREEZE spine is PROVEN before any code is written. Specifically: lock the GameAfkingModule split + the DegenerusGameStorage append layout + the per-sub stamp shape + the two-open-route wiring; PROVE the freeze invariants (freeze-completeness / pre-RNG index-binding / stamped-day determinism); carry the discharged REVERT-FREE-CHAIN + EV-cap-at-open invariants as locked SPEC invariants; DECIDE §4 placement on non-revert grounds; produce the code-size reclaim plan (ARCH-04, sequenced < 24,576 at every step) + the GAS inventory; confirm the OPEN-E/AFSUB/set-mutation carry-over; grep-attest every file:line vs the v54 HEAD 20ca1f79 — PAPER-ONLY, ZERO contracts/*.sol.
**Verified:** 2026-05-30
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Critical Framing Applied

This is a paper-only SPEC phase. Goal achievement = design docs + proofs EXIST and are SOUND on paper. Contract code implementing named symbols is NOT expected and their absence is correct. All five requirements (FREEZE-01/02/03, PLACE-01, ARCH-04) are owned by this phase; the other 24 v55.0 requirements belong to phases 349–352.

**Key in-phase decisions superseding ROADMAP/PLAN wording (treated as CORRECT per verification instructions):**

- **D-348-01:** §4 placement = REQUIRED-PATH (USER override of separate-legs recommendation; recorded explicitly as deliberate override in 348-PLACEMENT-DECISION.md).
- **D-348-04:** try/catch valve DROPPED; REVERT-02 rewritten to no-valve form (corrected in 348-INVARIANT-CARRY.md and reconciled in REQUIREMENTS.md).
- **D-348-07:** score + baseLevel moved from live-read → stamped-frozen; stamp grows to 5 fields `(index, amount, day, scorePlus1, baseLevelPlus1)`; FREEZE-01 now PROVEN (not split). REQUIREMENTS.md FREEZE-01 and BOX-02 already reflect this.
- **Code-size reality:** clean reclaim corrected to ~1.4–1.7 KB (not the doc's optimistic ~2.8 KB); running-total arithmetic confirms < 24,576 at every step.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | FREEZE spine proven on paper — freeze-completeness (FREEZE-01), pre-RNG index-binding (FREEZE-02), stamped-day determinism (FREEZE-03) | VERIFIED | `348-FREEZE-PROOF.md` delivers all three proofs with source-attested anchors. FREEZE-01 PROVEN per D-348-07 (5-field stamp). FREEZE-02: `subsFullyProcessed` no-interleave guard specified against `AdvanceModule:1016/:1089/:1629/:274`. FREEZE-03: `keccak256(abi.encode(rngWord, player, day, amount))` at `LB:534`, zero `block.*` entropy (grep-confirmed), seed from STAMPED day. |
| 2 | Discharged REVERT-FREE-CHAIN + EV-cap invariants carried as locked SPEC invariants (with D-348-04 correction applied) | VERIFIED | `348-INVARIANT-CARRY.md` carries obligations 1–3; obligation 4 (try/catch valve) explicitly DROPPED by D-348-04 in a labeled correction section. REQUIREMENTS.md REVERT-02 updated to no-valve form. Light /contract-auditor obligation-1 pass: PASS (5/5 invariants stated correctly). Cost-unit reconciliation, stamp field widths, and double-draw guard discharged. |
| 3 | §4 placement DECIDED on non-revert grounds, recorded as deliberate USER override | VERIFIED | `348-PLACEMENT-DECISION.md` leads with REQUIRED-PATH decision, explicitly marks PLAN-V55 §4+§9 SUPERSEDED, records decision basis as guaranteed-every-day (NOT revert-safety), specifies chunked-STAGE mechanism (`subsFullyProcessed` + `_subCursor` before `rngGate:274`), carries both proof obligations (D-348-02 → FREEZE-PROOF, D-348-04 → INVARIANT-CARRY), and accepts mint-gate standing dependency (ZERO new gate code). |
| 4 | Code-size reclaim plan MEASURED + sequenced so Game never breaches 24,576 mid-flight (ARCH-04) | VERIFIED | `348-CODE-SIZE-PLAN.md` ran `forge build --sizes --skip "test/**"` and measured DegenerusGame at 24,358 B / 218 B headroom (confirmed EXACT, not stale). R1 (`claimAffiliateDgnrs→BingoModule`, ~1.2–1.35 KB) sequenced FIRST. Running-total arithmetic: worst case (R1 low + stubs high + R2+R3 wrappers) = 24,418 < 24,576. Central case = 24,275 < 24,576. R1-FIRST ordering is mandatory and confirmed. `348-IMPL-EDIT-ORDER-MAP.md` carries the producer-before-consumer edit-order with running-total < 24,576 at every step. |
| 5 | OPEN-E/set-mutation carry-over confirmed and every cited file:line grep-attested vs 20ca1f79 (FREEZE / ARCH / CONSENT inputs) | VERIFIED | `348-GREP-ATTESTATION.md` records `git diff --numstat 20ca1f79 HEAD -- contracts/` as EMPTY (live tree == v54 baseline). Four drifts CORRECTED: box-seed is `abi.encode` at LB:534 (not `abi.encodePacked`); OPEN-E subscribe gate re-pinned to `:343-352` (not `:400-409`); funder resolution re-pinned to `:624` (not `:682`); `_resolveBuy` body extent re-pinned to `:727-863` (not `:727-795`). `348-SPEC-INDEX.md` §6 confirms CONSENT carry-over: isOperatorApproved gate, validThroughLevel, VAULT/SDGNRS exemption-on-player, funder=src accounting, "no cursor advance after swap-pop" — all verified against re-pinned source. OPEN-E 4-protection structure re-attested. |

**Score: 5/5 truths verified**

---

### Deferred Items

None identified. All items scoped to phase 348 are delivered. The stale `AfKing.poolOf` test references are correctly deferred to 351 TST and logged in `deferred-items.md`.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `348-GREP-ATTESTATION.md` | Call-graph attestation + drift-correction table | VERIFIED | Substantive: per-file tables with matched source text quoted; box-seed pattern-drift resolved; 4 drift corrections; no-"by-construction" attestation. Wired: cited by all downstream docs as anchor source. |
| `348-CODE-SIZE-PLAN.md` | MEASURED reclaim + running-total edit-order | VERIFIED | Substantive: `forge build --sizes` output recorded, per-target re-derived bytes, running-total table with R1-FIRST ordering, both scenario A (worst) and B (central) computed. Contains "24576"/"24,576". |
| `348-GAS-INVENTORY.md` | Advisory gas candidates + GAS-03 carve-out | VERIFIED | Substantive: 7 ADVISORY/UNVALIDATED candidates tabulated; GAS-01/02 flagged structural-to-IMPL; GAS-03 SAFE-WITH-CONDITIONS section explicit (no `quests.handleAffiliate` batching). Contains "gas-skeptic", "ADVISORY", "SAFE-WITH-CONDITIONS". |
| `348-FREEZE-PROOF.md` | FREEZE-01/02/03 proven on paper | VERIFIED | Substantive: Three distinct proof sections (FREEZE-01 PROVEN per D-348-07, FREEZE-02 with `subsFullyProcessed` guard, FREEZE-03 with entropy-side grep). D-348-07 amendment note present. Known-issue handling: EV-cap RMW residual noted as benign monotonic clamp, NOT findings-grade, marked for FINDINGS-v55.0 + v52 sweep. |
| `348-INVARIANT-CARRY.md` | Obligations 1–3 + D-348-04 correction + 3 §7 follow-ups + auditor pass | VERIFIED | Substantive: obligation-1 table with live lines; D-348-04 correction section with REVERT-02 text, fail-loud, class B, class C all present; 3 §7 follow-ups discharged; light /contract-auditor pass PASS (5/5); D-348-07 amendment note present. |
| `348-PLACEMENT-DECISION.md` | §4 placement DECIDED (required-path, USER override) | VERIFIED | Substantive: SUPERSEDED table for §4+§9; decision basis as guaranteed-every-day (not revert-safety); chunked-STAGE mechanism with `subsFullyProcessed`; D-348-02 and D-348-04 cross-references; `_enforceDailyMintGate:973` cited; bounty fold noted as PLACE-02 (349-owned). |
| `348-IMPL-EDIT-ORDER-MAP.md` | Producer-before-consumer edit-order for 349 diff | VERIFIED | Substantive: storage-append layout (5-field stamp per D-348-07), `GameAfkingModule` contents, two open routes, AfKing.sol stub collapse; ordered edit-order table (reclaim FIRST → storage append → GameAfkingModule → AdvanceModule STAGE → interfaces → AfKing stubs); 4 carried corrections threaded; re-pin-before-authoring caution present. |
| `348-SPEC-INDEX.md` | D-08 navigation index + traceability + verdict + 349 hand-off | VERIFIED | Substantive: doc-set table (7 sibling docs); requirement→doc table (FREEZE-01/02/03, PLACE-01, ARCH-04 all COVERED); success-criterion→doc table (SC1–SC5 all COVERED); SPEC verdict PASS; §6 CONSENT carry-over confirmation; 349 IMPL hand-off with carried corrections; paper-only assertion. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `348-FREEZE-PROOF.md` | `AdvanceModule:1016/:1089/:1629/:274` | subsFullyProcessed no-interleave guard specification citing re-pinned lines | VERIFIED | FREEZE-PROOF §(c) specifies the guard in two equivalent forms against exactly these re-pinned anchors |
| `348-FREEZE-PROOF.md` | `348-GREP-ATTESTATION.md` | "cite the ACTUAL re-grepped lines, never the drifted doc-cited lines" | VERIFIED | FREEZE-PROOF preamble explicitly sources all anchors from 348-GREP-ATTESTATION |
| `348-INVARIANT-CARRY.md` | REQUIREMENTS.md REVERT-02 | D-348-04 correction section quotes current text and rewrites it | VERIFIED | Section §2 quotes the exact "try/catch" language and records the no-valve rewrite; REQUIREMENTS.md confirmed to reflect no-valve form |
| `348-PLACEMENT-DECISION.md` | `348-FREEZE-PROOF.md` + `348-INVARIANT-CARRY.md` | D-348-02 → FREEZE-PROOF, D-348-04 → INVARIANT-CARRY cross-references | VERIFIED | §4a and §4b explicitly cross-reference by doc name |
| `348-IMPL-EDIT-ORDER-MAP.md` | `348-CODE-SIZE-PLAN.md` running-total | "carry reclaim-FIRST into the edit-order" | VERIFIED | Edit-order map §2 carries the running-total < 24,576 from CODE-SIZE-PLAN; reclaim FIRST sequencing honored |
| `348-SPEC-INDEX.md` | All 7 sibling docs | doc-set table + requirement→doc + SC→doc tables | VERIFIED | §2 table lists all 7 docs; §3 maps 5 requirements; §4 maps 5 SCs; all rows marked COVERED |
| `contracts/` (working tree) | `20ca1f79` (v54 HEAD) | `git diff --numstat 20ca1f79 HEAD -- contracts/` = EMPTY | VERIFIED | Verified directly: command returned empty output. Paper-only invariant holds across all 6 plans. |

---

### Data-Flow Trace (Level 4)

Not applicable — this is a paper-only SPEC phase. No dynamic data rendering; all artifacts are Markdown documents. Level 4 trace is skipped.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| contracts/ byte-identical to 20ca1f79 | `git diff --numstat 20ca1f79 HEAD -- contracts/` | (empty output) | PASS |
| FREEZE-PROOF contains subsFullyProcessed | `grep -c "subsFullyProcessed" 348-FREEZE-PROOF.md` | 7 matches | PASS |
| INVARIANT-CARRY contains D-348-04 correction with class B, class C | `grep -c "D-348-04" 348-INVARIANT-CARRY.md` | 11 matches | PASS |
| CODE-SIZE-PLAN contains 24576 (the ceiling) | `grep -c "24,576\|24576" 348-CODE-SIZE-PLAN.md` | 16 matches | PASS |
| SPEC-INDEX maps all 5 requirements as COVERED | `grep -c "COVERED" 348-SPEC-INDEX.md` | 12 matches | PASS |
| GAS-INVENTORY tags all candidates ADVISORY + includes gas-skeptic | `grep -c "gas-skeptic" 348-GAS-INVENTORY.md` | 2 matches | PASS |
| GREP-ATTESTATION resolves abi.encode box-seed drift | `grep -c "abi.encode" 348-GREP-ATTESTATION.md` | 5 matches with `:534` context | PASS |
| PLACEMENT-DECISION contains required-path + supersede + guaranteed-every-day | Direct read confirmed | All three present | PASS |

---

### Probe Execution

No probe scripts declared or expected for a paper-only SPEC phase. Step 7c: SKIPPED (no runnable probes; this phase produces only Markdown artifacts).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FREEZE-01 | 348-03 (FREEZE-PROOF) + 348-01 (GREP-ATTESTATION) | Freeze-completeness — stamp captures ALL outcome-determining state (D-348-07: now includes scorePlus1 + baseLevelPlus1); EV-cap RMW is the sole residual live-read (benign monotonic clamp) | SATISFIED | `348-FREEZE-PROOF.md` FREEZE-01 section: proven per D-348-07; stamp = `(index, amount, day, scorePlus1, baseLevelPlus1)`; EV-cap RMW documented as benign. REQUIREMENTS.md [x] FREEZE-01. |
| FREEZE-02 | 348-03 (FREEZE-PROOF) + 348-01 (GREP-ATTESTATION) | Index-binding — stamp binds to pre-RNG LR_INDEX; process-pass must not straddle requestLootboxRng advance | SATISFIED | `348-FREEZE-PROOF.md` FREEZE-02: proves LR_INDEX advanced at exactly two sites (`:1089`/`:1629`), both after the STAGE; specifies `subsFullyProcessed` no-interleave guard; `subsFullyProcessed` CONFIRMED-NEW (zero matches in source). REQUIREMENTS.md [x] FREEZE-02. |
| FREEZE-03 | 348-03 (FREEZE-PROOF) + 348-01 (GREP-ATTESTATION) | Determinism — box seed uses STAMPED buy-day; no block.* entropy in draw | SATISFIED | `348-FREEZE-PROOF.md` FREEZE-03: seed at `LB:534` is `keccak256(abi.encode(...))`, zero `block.*` (grep-confirmed), open seeds from stamped day. Pattern-drift (abi.encodePacked claimed, abi.encode actual) resolved in GREP-ATTESTATION §1a. REQUIREMENTS.md [x] FREEZE-03. |
| PLACE-01 | 348-04 (PLACEMENT-DECISION) | §4 placement decided at SPEC on non-revert grounds; process-leg pre-RNG cursor-chunked, open-leg post-RNG cursor-chunked | SATISFIED | `348-PLACEMENT-DECISION.md`: REQUIRED-PATH decided (D-348-01 USER override); decision basis = guaranteed-every-day (not revert-safety); PLAN-V55 §4+§9 SUPERSEDED; chunked-STAGE mechanism specified; both proof obligations carried. REQUIREMENTS.md [x] PLACE-01. |
| ARCH-04 | 348-02 (CODE-SIZE-PLAN) + 348-05 (IMPL-EDIT-ORDER-MAP) | Game runtime code-size stays < 24,576 at every intermediate step; reclaim FIRST before adding afking stubs | SATISFIED | `348-CODE-SIZE-PLAN.md`: `forge build --sizes` measured 24,358 B / 218 B headroom (EXACT); R1 FIRST is mandatory per arithmetic; worst-case running-total = 24,418 < 24,576 after R1+R2+R3-wrapper. `348-IMPL-EDIT-ORDER-MAP.md`: producer-before-consumer edit-order with reclaim FIRST. REQUIREMENTS.md [x] ARCH-04. |

**All 5 phase requirements satisfied. No orphaned requirements for this phase.**

Note: REVERT-01, REVERT-02, EVCAP-01, BOX-01..05, CONSENT-01/02, PLACE-02, ARCH-01/02/03, GAS-01..03, TST-01..06, AUDIT-01 are owned by phases 349–352 (Pending in REQUIREMENTS.md — correct, not phase 348 gaps).

---

### Anti-Patterns Found

Files modified by this phase are Markdown planning documents (`.planning/` only). No `contracts/*.sol` were modified (confirmed: `git diff --numstat 20ca1f79 HEAD -- contracts/` = EMPTY). Anti-pattern scan scoped to the 8 deliverable Markdown docs.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `348-SPEC-INDEX.md` | Progress table | "6/7 In Progress" in ROADMAP.md (not a deliverable file) | Info | ROADMAP tracking field is stale (says 6/7, phase has 6 plans and is complete per STATE.md). No impact on verification. STATE.md correctly records "Phase complete — all 6 plans authored." |
| `348-GAS-INVENTORY.md` + `348-PLACEMENT-DECISION.md` | Multiple | Describes live-read window under pre-D-348-07 framing (score/baseLevel/EV-cap read LIVE) | Info | These two docs were authored before D-348-07 amended the stamp. SPEC-INDEX §5.6 explicitly surfaces this as a known upstream correction. The substance (open stays normal post-RNG leg) is unchanged. Not a blocker. |

No TBD/FIXME/XXX/TODO debt markers found in the deliverable docs. No placeholder patterns. No stub implementations. No hardcoded empty returns. All sections contain substantive content verified above.

**No blockers. No warnings requiring remediation.**

---

### Human Verification Required

None. This is a paper-only SPEC phase producing Markdown design documentation. All truths are verifiable by reading the docs and running grep/git commands. The 348-03 `checkpoint:human-verify` gate (the only autonomous:false task in the phase) was approved and recorded in `348-03-SUMMARY.md` with:

> "Human-verify checkpoint APPROVED — auto-approved per the project rule that only contract commits require user approval; this phase commits ZERO contracts. Freeze spine + no-valve invariant set LOCKED for 349"

The SPEC verdict is PASS. No items require human testing. The light /contract-auditor obligation-1 pass ran inline and returned PASS (5/5) with its method transparently documented (no Task/Skill tool available; real /contract-auditor deferred to the 352 TERMINAL in-milestone sweep on folded code).

---

### Gaps Summary

No gaps. All 5 phase requirements are substantiated by delivered, substantive, internally-consistent documents. The phase delivered what the goal required:

1. **FREEZE spine PROVEN** — three proof documents (FREEZE-01 via D-348-07, FREEZE-02 with the `subsFullyProcessed` guard specified, FREEZE-03 with the abi.encode confirmation and entropy-side guard).
2. **Discharged invariants CARRIED** — obligations 1–3 as the locked v55 invariant set, with D-348-04 correction applied, 3 follow-ups discharged, and the auditor pass at PASS.
3. **Placement DECIDED** — required-path on guaranteed-every-day grounds, recorded as deliberate USER override with PLAN-V55 §4+§9 superseded.
4. **Code-size MEASURED and SEQUENCED** — `forge build --sizes` confirmed; R1-FIRST ordering; running-total < 24,576 at every row; doc's overstatement (~2.8 KB) corrected to ~1.4–1.7 KB clean.
5. **OPEN-E/set-mutation carry-over CONFIRMED and anchors ATTESTED** — 4 drift corrections made; all 5 CONSENT carry-over elements confirmed against re-pinned source; 348-IMPL-EDIT-ORDER-MAP.md provides the producer-before-consumer sequencing.

The only notable item is that `subsFullyProcessed` is explicitly confirmed-new (does not exist in v54 source — ZERO grep matches in AdvanceModule). This is correct: it is a SPECIFICATION for 349 to author, not an attestation of existing code. The FREEZE-PROOF acknowledges this explicitly and 351 TST-01 owns the empirical proof.

---

_Verified: 2026-05-30_
_Verifier: Claude (gsd-verifier)_
