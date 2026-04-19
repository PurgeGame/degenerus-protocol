# Phase 240: Gameover Jackpot Safety — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning
**Mode:** Interactive gray-area selection (user answered 4 discuss questions; plan split + file structure = Claude's Discretion default)

<domain>
## Phase Boundary

Gameover-branch-specific determinism audit that proves the VRF-available gameover-jackpot branch is fully deterministic — every gameover-VRF consumer enumerated (19-row gameover-flow scope anchored by Phase 237 Consumer Index: 7 `gameover-entropy` + 4 `other / exception-mid-cycle-substitution` (F-29-04) + 8 `other / exception-prevrandao-fallback`), every jackpot-input state variable frozen at gameover VRF request, trigger-timing manipulation disproven, and F-29-04 scope confirmed distinct from jackpot-input determinism. Fresh-eyes at HEAD `7ab515fe` — prior-milestone artifacts (v25.0, v29.0 Phase 232.1-03 / Phase 235 Plan 04, v3.7, v3.8) may be CROSS-CITED but MUST NOT be relied upon.

Five requirements:
- **GO-01** — Enumerate every consumer of the gameover VRF word (gameover jackpot winner selection, trait rolls, terminal ticket drain, final-day burn/coinflip resolution, sweep distribution). Universe list.
- **GO-02** — Prove jackpot is fully deterministic on the **VRF-available branch** (i.e. when gameover VRF word is the real `rawFulfillRandomWords` output, not prevrandao fallback). No player, admin, or validator may influence trait rolls, winner selection, or payout values between gameover VRF request and consumption.
- **GO-03** — Enumerate every state variable feeding gameover jackpot resolution (winner indices, pool totals, trait arrays, pending queues, counter state). Each confirmed `frozen-at-request`.
- **GO-04** — Disprove trigger-timing manipulation: gameover trigger (120-day liveness stall / pool deficit) cannot be manipulated to align with a specific mid-cycle state that biases the jackpot on the VRF-available branch.
- **GO-05** — Confirm the gameover-jackpot branch is structurally distinct from the F-29-04 mid-cycle ticket substitution path — jackpot inputs must be proven frozen irrespective of write-buffer swap state. F-29-04 applies only to tickets awaiting mid-day fulfillment; it must not leak into jackpot-input determinism.

Single consolidated deliverable per ROADMAP literal wording: `audit/v30-GAMEOVER-JACKPOT-SAFETY.md`. Built incrementally via three per-plan intermediate files (237/238-style pattern, not 239-style multi-file). Scope is READ-only: no `contracts/` or `test/` writes. Finding-ID emission deferred to Phase 242 (FIND-01/02/03); Phase 240 produces verdicts + tables + proofs + Finding Candidate blocks.

Phase 240 is parallel to Phases 238/239/241 per ROADMAP execution order — each has its own scope lane (238 = per-consumer freeze, 239 = global invariant, 240 = gameover branch, 241 = exception closure). All four share Phase 237's `audit/v30-CONSUMER-INVENTORY.md` as the scope anchor for any RNG-consumer state-space reference. Phase 240 additionally READs Phase 238's `audit/v30-FREEZE-PROOF.md` (19-row Gameover-Flow Freeze-Proof Subset + 22-row KI-Exception subset) and Phase 239's `audit/v30-RNGLOCK-STATE-MACHINE.md` + `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` (rngLockedFlag bookkeeping around gameover VRF request + phase-transition-gate origin proof) as corroborating evidence.

KNOWN-ISSUES exceptions (4 accepted entries) frame GO-02's EXCEPTION verdicts and GO-05's SUBJECT of scope containment but do NOT re-litigate acceptance (Phase 241 EXC-02 owns prevrandao-fallback acceptance; Phase 241 EXC-03 owns F-29-04 acceptance; Phase 241 EXC-04 owns EntropyLib keccak-seed acceptance; Phase 241 EXC-01 owns affiliate non-VRF-entropy uniqueness).

</domain>

<decisions>
## Implementation Decisions

### Plan Split (Claude's Discretion default — user did not select as gray area)
- **D-01 (3 plans — matches ROADMAP literal grouping):** ROADMAP says `"expected 2-3 plans — GO-01 consumer inventory + GO-02 determinism proof, GO-03 state-freeze + GO-04 trigger-timing disproof, GO-05 F-29-04 scope containment"`. Three plans, comma-delimited grouping honoured verbatim.
  - `240-01-PLAN.md` — GO-01 consumer inventory + GO-02 VRF-available determinism proof → `audit/v30-240-01-INV-DET.md`
  - `240-02-PLAN.md` — GO-03 state-freeze enumeration + GO-04 trigger-timing disproof → `audit/v30-240-02-STATE-TIMING.md`
  - `240-03-PLAN.md` — GO-05 F-29-04 scope containment + final consolidation → `audit/v30-240-03-SCOPE.md` + `audit/v30-GAMEOVER-JACKPOT-SAFETY.md`
- **D-02 (wave topology — 2 waves, Wave 1 parallel 240-01 + 240-02, Wave 2 solo 240-03):** Plans 240-01 and 240-02 share zero inputs at HEAD (each reads Phase 237 Consumer Index + Phase 238 FREEZE-PROOF directly). Plan 240-03's GO-05 state-variable-disjointness proof REQUIRES Plan 240-02's GOVAR-240-NNN enumeration (per D-13 dual-disjointness choice), and Plan 240-03 ALSO owns final consolidation of `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` which requires 240-01 + 240-02 both committed. Matches Phase 238's 2-wave topology exactly (238-03 was Wave 2 because FWD-03 gating depended on FWD-01/02 mutation-path output + owned final consolidated `v30-FREEZE-PROOF.md`).
- **D-03 (single consolidated deliverable per ROADMAP literal):** ROADMAP Phase 240 Success Criterion 1 names `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (singular). Three per-plan intermediate files + one consolidated file matches 237/238 pattern (NOT 239's 3-separate-dedicated-files pattern). Consolidation lives in Plan 240-03 Task N (same as 238-03 Plan-Task structure).

### GO-01 Evidence Shape (Gameover-VRF Consumer Inventory)
- **D-04 (fresh-eyes re-derivation + Phase 237 cross-ref column):** 19-row gameover-VRF-consumer inventory at HEAD `7ab515fe`, fresh-eyes re-derived from `contracts/` (not copied from Phase 237). Each row carries a Phase 237 `INV-237-NNN` cross-reference cell. Row ID prefix `GO-240-NNN` (three-digit zero-padded), consistent with 237 D-06 / 239 D-25 naming convention.
  - **Inventory Table columns:** `Row ID | INV-237 Cross-Ref | Consumer (Contract.Function) | Path Family | Consumption Site (File:Line) | VRF-Request Origin (File:Line) | Branch (VRF-available / prevrandao-fallback / F-29-04) | Verdict`. Branch classification takes precedence: the 8 prevrandao rows are `prevrandao-fallback`, the 4 F-29-04 rows are `F-29-04`, remaining 7 rows are `VRF-available`.
- **D-05 (reconciliation verdict — fresh-eyes invariant):** Each GO-240-NNN row's Phase 237 cross-ref resolves to one of: `CONFIRMED_FRESH_MATCHES_237` (row exists in Phase 237 Consumer Index gameover-flow 19-row subset with identical consumer / site) / `NEW_SINCE_237` (fresh-eyes surfaced a consumer Phase 237 missed → Finding Candidate per D-22) / `SUPERSEDED_IN_237` (Phase 237 listed a row that no longer exists at HEAD → Finding Candidate). v30.0 fresh-eyes invariant expectation: all 19 rows `CONFIRMED_FRESH_MATCHES_237` (contract tree unchanged since v29.0 `1646d5af` per PROJECT.md). Any divergence is a `CANDIDATE_FINDING` per D-22 / D-27.

### GO-02 Evidence Shape (VRF-Available Branch Determinism Proof)
- **D-06 (EXCEPTION verdict pattern — 238 FREEZE-PROOF precedent, per user choice):** All 19 rows from GO-01 inventory in scope for GO-02 determinism proof. The 8 prevrandao-fallback rows carry verdict `EXCEPTION (KI: EXC-02)` with forward-cite to Phase 241 EXC-02 per D-19. The 4 F-29-04 rows carry verdict `EXCEPTION (KI: EXC-03)` at consumer level (the write-buffer swap substitution is the exception) with forward-cite to Phase 241 EXC-03 per D-19. The 7 pure-VRF-available gameover-entropy rows carry verdict `SAFE_VRF_AVAILABLE`. Matches Phase 238's 22-EXCEPTION / 124-SAFE pattern exactly for reviewer consistency. Reviewer sees all 19 rows in one GO-02 table with no ambiguity about which rows Phase 240 vs Phase 241 owns.
- **D-07 (closed verdict taxonomy):** Every GO-02 row ends in exactly one of {`SAFE_VRF_AVAILABLE` / `EXCEPTION (KI: EXC-02)` / `EXCEPTION (KI: EXC-03)` / `CANDIDATE_FINDING`}. No hedged verdicts (235 D-14 / 238 D-14 / 239 D-05 pattern).
- **D-08 (per-consumer adversarial-closure columns — player / admin / validator):** For each GO-02 row, three actor columns disprove influence on trait rolls / winner selection / payout values between gameover VRF request and consumption. Closed-verdict cells in {`NO_INFLUENCE_PATH (<gate>)` / `EXCEPTION (KI: EXC-NN)` / `CANDIDATE_FINDING`}. VRF-oracle column is OMITTED from GO-02 (scope is VRF-available branch — VRF-oracle withholding routes to EXC-02 prevrandao fallback already accepted in D-06). Cross-cites Phase 238 BWD-03 / FWD-02 19-row Gameover-Flow subset for actor-cell verdicts (corroborating, per D-17 re-verify discipline — verdicts re-derived fresh at HEAD, not copied).

### GO-03 Evidence Shape (State-Freeze Enumeration) — dual-table per user choice
- **D-09 (dual-table structure — per-variable AND per-consumer):**
  - **Per-Variable State-Freeze Table** — every storage slot / mapping key / counter touched by any GO-240-NNN consumer at consumption time. Columns: `Var ID | Storage Slot (File:Line) | Consumer Row IDs (GO-240-NNN) | Write Paths (File:Line list) | Named Gate (D-10) | Frozen-At-Request Verdict`. Row ID prefix `GOVAR-240-NNN`. Verdict in {`FROZEN_AT_REQUEST` / `FROZEN_BY_GATE` / `EXCEPTION (KI: EXC-NN)` / `CANDIDATE_FINDING`}.
  - **Per-Consumer State-Freeze Cross-Walk** — 19-row table mapping each `GO-240-NNN` consumer row to its `GOVAR-240-NNN` variable set + aggregate state-freeze verdict. Columns: `GO-240-NNN | Consumer | GOVAR-240-NNN set | Aggregate Verdict`. Aggregate verdict = SAFE if ALL member GOVAR rows are `FROZEN_AT_REQUEST` or `FROZEN_BY_GATE`; EXCEPTION if any member is `EXCEPTION`; CANDIDATE_FINDING if any member is `CANDIDATE_FINDING`.
- **D-10 (Named Gate taxonomy reuse from Phase 238 D-13):** GOVAR row Named Gate column draws from closed 4-value set {`rngLocked` / `lootbox-index-advance` / `phase-transition-gate` / `semantic-path-gate`} + one meta-value `NO_GATE_NEEDED_ORTHOGONAL` for storage slots no RNG consumer reads. Extension outside the 4-value taxonomy = `CANDIDATE_FINDING` per D-22. Cross-cite Phase 238-03 GATING Named Gate distribution for the 19-row gameover-flow subset (expected distribution: `rngLocked` = 7 gameover-entropy + `semantic-path-gate` = 12 exception rows = 19, per Phase 238 Plan 03 Decisions). Fresh re-derivation at HEAD required per D-17.

### GO-04 Evidence Shape (Trigger-Timing Disproof) — player-centric per user choice
- **D-11 (player-centric attacker model per user choice):** GO-04 primary focus is player-reachable manipulation of the two gameover-trigger surfaces (120-day liveness stall, pool deficit). Admin / validator / VRF-oracle coverage is provided as a narrative paragraph AFTER the player-focused Trigger Surface Table, with closed-verdict summary per non-player actor. Divergence from Phase 238's 4-actor BWD-03 pattern acknowledged; narrative completeness ensures REQUIREMENTS.md "any actor" language is fully addressed even though the primary analytic unit is player-reachable vectors.
  - **Rationale:** ROADMAP Success Criterion 4 names "an attacker" (singular threat model). Admin has no direct gameover-trigger toggle at HEAD (verify during planning); validator-level block-delay attacks are bounded by the 14-day `GAMEOVER_RNG_FALLBACK_DELAY` accepted in KI EXC-02 (not a gameover-trigger manipulation, a gameover-*fulfillment* manipulation already out-of-scope for GO-04); VRF-oracle is Phase 241 EXC-02 scope. Player-centric focus is the load-bearing novel analysis.
- **D-12 (dual evidence shape — table + narrative):**
  - **Trigger Surface Table** — columns: `Trigger ID | Trigger Surface | Triggering Mechanism (File:Line) | Player-Reachable Manipulation Vector(s) | Vector Neutralized By (File:Line) | Verdict`. Expected 2 rows (`GOTRIG-240-001` 120-day liveness stall, `GOTRIG-240-002` pool deficit). Closed verdict in {`DISPROVEN_PLAYER_REACHABLE_VECTOR` / `CANDIDATE_FINDING`}. Each row enumerates every player-reachable manipulation path considered + the specific mechanism that neutralizes it (storage gate, access control, economic infeasibility, etc.).
  - **Non-Player Actor Narrative** — follows table. Covers admin (closed verdict: `NO_DIRECT_TRIGGER_SURFACE` with file:line verification), validator (closed verdict: `BOUNDED_BY_14DAY_EXC02_FALLBACK` — block delay is not trigger manipulation in Phase 240 scope; out-of-band block manipulation cited and deferred), VRF-oracle (closed verdict: `EXC-02_FALLBACK_ACCEPTED` — Phase 241 owns acceptance). Narrative is grep-friendly: each actor closed verdict in a bold label for reviewer extraction.
- **D-13 (narrative closed-verdict attestation — player-only analytic choice is Phase-240-specific, not milestone-level):** The decision to focus GO-04 primary evidence on the player actor (with admin/validator/VRF narrative) is a Phase 240 CONTEXT decision anchored in ROADMAP Success Criterion 4 wording. If Phase 242 REG-02 or a future C4A warden argues this is insufficient coverage of REQUIREMENTS.md GO-04 "any actor" language, the gap routes to Phase 242 FIND-01 pool (not a Phase 240 amendment). Planner MUST attest in 240-02-SUMMARY that the narrative paragraph exists and delivers a closed verdict for each of the 3 non-player actors.

### GO-05 Evidence Shape (F-29-04 Scope Containment) — dual-disjointness per user choice
- **D-14 (dual-disjointness proof structure):**
  - **Inventory-Level Disjointness Proof** — show the 4 F-29-04 rows (INV-237-024, -045, -053, -054 per Phase 238 Plan 03 Decisions) are set-disjoint from the 11 VRF-available-gameover-jackpot rows (7 gameover-entropy + 4 F-29-04 → wait: F-29-04 rows ARE the exception, so the "VRF-available jackpot input universe" = 7 gameover-entropy rows only for the disjointness check). Closed-form set-equality statement: `{4 F-29-04 rows} ∩ {7 gameover-entropy rows} = ∅`. Cite INV-237-NNN IDs verbatim from Phase 237 Consumer Index.
  - **State-Variable-Level Disjointness Proof** — show the storage slots touched by F-29-04 mid-cycle substitution path (specifically the ticket pre-swap-vs-post-swap RNG-word substitution surface) are set-disjoint from the `GOVAR-240-NNN` jackpot-input state variable universe enumerated in Plan 240-02's GO-03 per-variable table. Closed-form set-equality statement: `{F-29-04 write-buffer-swap storage slots} ∩ {GOVAR-240-NNN jackpot-input slots} = ∅`. Cites GOVAR-240-NNN IDs from Plan 240-02 (Wave-2 dependency per D-02).
- **D-15 (verdict taxonomy):** Each of the two proofs ends in closed verdict in {`DISJOINT` / `CANDIDATE_FINDING`}. Combined scope-containment verdict `BOTH_DISJOINT` iff both sub-proofs `DISJOINT`; otherwise `CANDIDATE_FINDING` for the combined claim + route to Phase 242 FIND-01.
- **D-16 (proof-by-exhaustion format per 239 D-14 pattern):** Neither disjointness sub-proof is "shown by prior milestone XYZ". Each enumerates the specific storage slots / row IDs at HEAD `7ab515fe` and argues from those primitives. Prior-milestone cites (v29.0 Phase 235 Plan 04 F-29-04 commitment-window trace; v29.0 KI EXC-03 F-29-04 entry — SUBJECT, not warrant) are "we independently re-derived the same result" notes only.

### Fresh-Eyes + Cross-Cite Discipline
- **D-17 (fresh re-prove + cross-cite prior — Phase 237 D-07 / Phase 238 D-09 / Phase 239 D-16 pattern):** Every verdict in all three plans re-derived at HEAD `7ab515fe`. CROSS-CITES prior-milestone artifacts as corroborating evidence only — never as the sole warrant:
  - **Phase 237** `audit/v30-CONSUMER-INVENTORY.md` — 19-row gameover-flow subset + 4-row F-29-04 subset (GO-05 input) + Consumer Index GO-01..05 row mapping. SCOPE ANCHOR per D-27.
  - **Phase 238** `audit/v30-FREEZE-PROOF.md` — 19-row Gameover-Flow Freeze-Proof Subset (per-consumer BWD/FWD/gating verdicts) + 22-row KI-Exception subset (EXC-02 prevrandao + EXC-03 F-29-04 rows with Named Gate distribution). CORROBORATING per D-17.
  - **Phase 239** `audit/v30-RNGLOCK-STATE-MACHINE.md` — rngLockedFlag set/clear bookkeeping around gameover VRF request (Path Enumeration row D-19 gameover-bracket). Corroborating.
  - **Phase 239** `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` § Asymmetry B — phase-transition-gate origin proof; corroborating for GOVAR rows gated by `phase-transition-gate`.
  - **v29.0 Phase 232.1-03-PFTB-AUDIT.md** — non-zero-entropy guarantees around phase transition; corroborating for GOVAR rows and GO-02 VRF-available verdicts.
  - **v29.0 Phase 235 Plan 04** `235-04-COMMITMENT-WINDOW.md` — gameover-flow cross-cycle consumer trace; corroborating for GO-01 fresh-eyes reconciliation.
  - **v29.0 Phase 235 Plan 05** `235-05-TRNX-01.md` — `rngLocked` 4-path walk; corroborating for GO-02 on-chain-actor-column adversarial closure.
  - **v25.0 Phase 215** RNG fresh-eyes SOUND baseline; corroborating structural.
  - **v3.7 Phases 63-67** VRF path test coverage + rawFulfillRandomWords revert-safety; corroborating.
  - **v3.8 Phases 68-72** VRF commitment window 51/51 SAFE; corroborating.
  - **KNOWN-ISSUES entries** EXC-01 affiliate (out-of-scope, not cited), EXC-02 prevrandao-fallback (SUBJECT of GO-02 EXCEPTION rows + forward-cite to Phase 241), EXC-03 F-29-04 mid-cycle substitution (SUBJECT of GO-02 EXCEPTION rows + GO-05 containment proof + forward-cite to Phase 241), EXC-04 EntropyLib XOR-shift (out-of-scope for Phase 240, Phase 241 EXC-04).
- **D-18 (re-verify-at-HEAD note on every cross-cite — 237 D-07 / 238 D-10 / 239 D-17 pattern):** Each cross-cite carries `re-verified at HEAD 7ab515fe` backtick-quoted-phrase note with a one-line structural-equivalence statement. Contract tree identical to v29.0 `1646d5af` (all post-v29 commits docs-only per PROJECT.md), so re-verification is mechanical; the note is mandatory to guard against silent divergence. Minimum ≥3 instances per audit file per 239 Plan Decision erratum precedent.

### Scope Boundaries (what Phase 240 is NOT) — strict boundary per user choice
- **D-19 (Phase 240 owns VRF-available-branch determinism ONLY; Phase 241 owns KI acceptance — strict boundary per user choice):**
  - Phase 240 GO-02's 8 prevrandao-fallback rows carry verdict `EXCEPTION (KI: EXC-02)` with forward-cite `See Phase 241 EXC-02 for acceptance`. No prevrandao acceptance re-verification in Phase 240.
  - Phase 240 GO-02's 4 F-29-04 rows carry verdict `EXCEPTION (KI: EXC-03)` with forward-cite `See Phase 241 EXC-03 for acceptance`. No F-29-04 acceptance re-verification in Phase 240.
  - Phase 240 GO-05 proves scope CONTAINMENT (F-29-04 does not leak into jackpot-input determinism) with forward-cite `See Phase 241 EXC-03 for F-29-04 acceptance; GO-05 proves scope-containment only`.
  - Forward-cite format: `See Phase 241 EXC-NN` or `See \`audit/v30-EXCEPTION-CLOSURE.md\` § EXC-NN` (if Phase 241 output file name is agreed during planning). Post-commit reconciliation if Phase 241 produces a divergent header structure (239-02 → 239-03 forward-cite precedent: cite held by path; no re-edit of Phase 240 files; erratum per D-22).
- **D-20 (Phase 240 is not per-consumer freeze-proof — that's Phase 238):** Phase 240 does NOT re-derive per-consumer backward/forward freeze-proof verdicts for gameover-flow rows. Phase 240 CITES Phase 238's 19-row Gameover-Flow Freeze-Proof Subset SAFE/EXCEPTION verdicts and layers jackpot-specific GO-02/GO-03/GO-04/GO-05 proofs on top (jackpot-winner-selection determinism, state-variable freeze, trigger-timing disproof, F-29-04 scope containment). Where GO-02's per-consumer adversarial-closure cells overlap with Phase 238's BWD-03 / FWD-02 verdicts, Phase 240 re-derives fresh at HEAD per D-17 (not copy-paste from 238).
- **D-21 (Phase 240 is not global-invariant — that's Phase 239):** Phase 240 does not re-derive the rngLockedFlag state machine; CITES Phase 239 RNG-01 output. Phase 240 does not re-derive the permissionless sweep; CITES Phase 239 RNG-02 output. Phase 240 does not re-justify the two asymmetries; CITES Phase 239 RNG-03 output (§ Asymmetry B phase-transition-gate origin proof is the relevant cross-cite for GOVAR rows gated by phase-transition-gate).
- **D-22 (Phase 240 is not KI-acceptance — that's Phase 241 per D-19 strict boundary):** Phase 240 re-verifies determinism on the VRF-available branch; Phase 241 EXC-02 re-verifies prevrandao-fallback trigger-gating; Phase 241 EXC-03 re-verifies F-29-04 scope. Phase 240 emits EXCEPTION verdicts with forward-cites to Phase 241; does NOT re-litigate acceptance.
- **D-23 (Phase 240 is not regression — that's Phase 242):** Phase 240 does not carry a regression appendix. Prior-milestone cross-cites are contemporaneous corroboration, not regression verdicts (PASS/REGRESSED/SUPERSEDED). Regression appendix is Phase 242 REG-01/02.
- **D-24 (Phase 240 is not full-inventory — scope is 19-row gameover-flow subset + 4-row F-29-04 subset ONLY):** Phase 240 does NOT re-enumerate the full 146-row Phase 237 Consumer Index. Row-ID integrity check: set-equality with Phase 237's 19-row gameover-flow subset + 4-row F-29-04 subset is a verification gate per D-05. Any surfaced consumer outside Phase 237's 19 rows is a Finding Candidate per D-27 (not a scope amendment).

### Finding-ID Emission
- **D-25 (no F-30-NN emission — 235 D-14 / 237 D-15 / 238 D-15 / 239 D-22 pattern):** Phase 240 does NOT emit `F-30-NN` finding IDs. Produces verdicts + tables + proofs + Finding Candidate blocks that become the pool for Phase 242 FIND-01 intake. Every verdict cites commit SHA + file:line so Phase 242 can anchor without re-discovery.
- **D-26 (Finding Candidates appendix per-plan):** Each of the three plan deliverables carries a "Finding Candidates" subsection listing any rows whose verdict is `CANDIDATE_FINDING`. The three appendices aggregate into Phase 242 FIND-01 intake alongside Phase 237/238/239 candidate pools (Phase 242 merges via commit-SHA + file:line + Row-ID anchors).

### Output Shape
- **D-27 (three intermediate audit files + one consolidated deliverable — 237/238 pattern per D-03):** Unlike Phase 239 D-24 (3-dedicated-file pattern without a consolidated file), Phase 240 produces 3 per-plan intermediate files + 1 consolidated deliverable mirroring ROADMAP SC-1..5 exactly.
  - `audit/v30-240-01-INV-DET.md` — GO-01 inventory + GO-02 VRF-available determinism proof + per-plan Finding Candidates appendix
  - `audit/v30-240-02-STATE-TIMING.md` — GO-03 dual state-freeze tables + GO-04 trigger-surface table + non-player narrative + per-plan Finding Candidates appendix
  - `audit/v30-240-03-SCOPE.md` — GO-05 inventory-disjointness proof + GO-05 state-variable-disjointness proof + per-plan Finding Candidates appendix
  - `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` — consolidated deliverable; assembled in Plan 240-03 Task N via Python merge script (238-03 Task 3 pattern); contains: GO-01 Unified Gameover-VRF Consumer Inventory (19 rows merging 240-01 + 240-02 + 240-03 per-plan verdicts); GO-02 Determinism Proof Table; GO-03 Per-Variable + Per-Consumer tables; GO-04 Trigger Surface Table + non-player narrative; GO-05 Dual-Disjointness Proof; Consumer Index updating Phase 237's GO-01..05 rows with Phase 240 verdicts; Finding Candidates merged; Scope-Guard Deferrals (if any); Attestation with HEAD `7ab515fe` anchor.
- **D-28 (tabular, grep-friendly, no mermaid — 237 D-09 / 238 D-25 / 239 D-25 convention):** All four files use tabular evidence. Diagrams in prose, not images. Row IDs grep-stable (`GO-240-NNN`, `GOVAR-240-NNN`, `GOTRIG-240-NNN`). Downstream Phase 242 greps by Row ID for finding anchoring.

### Scope-Guard Handoff
- **D-29 (HEAD anchor `7ab515fe` locked in every plan's frontmatter — 237 D-17 / 238 D-19 / 239 D-26 pattern):** Contract tree unchanged since v29.0 `1646d5af`; all post-v29 commits are docs-only. Any contract change after `7ab515fe` resets the baseline and requires a scope addendum. Frontmatter freeze is mandatory in 240-01, 240-02, 240-03, and each plan SUMMARY.
- **D-30 (READ-only scope, no `contracts/` or `test/` writes — 237 D-18 / 238 D-20 / 239 D-27 pattern):** Carries forward v28/v29 cross-repo READ-only pattern + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Writes confined to `.planning/` and `audit/` (creating `v30-240-01-*`, `v30-240-02-*`, `v30-240-03-*`, `v30-GAMEOVER-JACKPOT-SAFETY.md` files). `KNOWN-ISSUES.md` is not touched in Phase 240 — KI promotions are Phase 242 FIND-03 only.
- **D-31 (Phase 237/238/239 outputs READ-only — scope-guard deferral rule per 237 D-16 / 238 D-20 / 239 D-28):** If any Phase 240 plan surfaces a consumer not in Phase 237's 19-row gameover-flow subset or a state variable touching jackpot-input state not in Phase 237's consumer universe, it records a scope-guard deferral in its own plan SUMMARY (file:line + context + proposed inventory delta). Phase 237/238/239 outputs are NOT re-edited in place. Inventory gaps become Phase 242 FIND-01 finding candidates. READ-only-after-commit applies to Phase 240's own intermediate files too (238-03 D-28 precedent): once 240-01-INV-DET.md commits, it is READ-only for Plans 240-02 and 240-03 (consolidation in 240-03 Task N merges content, never mutates the intermediate file).
- **D-32 (no discharge claim in Phase 240 deliverables):** Unlike Phase 239 D-29 which explicitly discharged Phase 238-03 Scope-Guard Deferral #1, Phase 240 does NOT emit a "discharge" claim. Phase 240 produces GO-01..05 verdicts that Phase 242 REG/FIND consumes for cross-checking; any cross-phase discharge routing is Phase 242's job at milestone consolidation. Rationale: no prior phase recorded an audit assumption pending Phase 240 (Phase 238-03 Scope-Guard Deferral #1 was fully discharged by Phase 239; Phase 239 emitted no deferrals).

### Claude's Discretion
- Exact ordering of GO-01 table subsections (by row ID vs by path family vs by branch) — planner picks most readable.
- Whether the GO-03 Per-Variable table precedes or follows the Per-Consumer cross-walk — planner picks (recommend Per-Variable first for grep-stability, Per-Consumer second as the aggregate layer).
- Whether GO-04 Trigger Surface Table precedes or follows the Non-Player Actor Narrative — planner picks (recommend table-first for grep-stability per 237 D-09 convention).
- Whether GO-05 Inventory Disjointness or State-Variable Disjointness appears first — planner picks (recommend Inventory first — faster reviewer anchor via Row IDs).
- Whether Finding Candidate severities are pre-classified (INFO / LOW / MED / HIGH) or left as `SEVERITY: TBD-242` — Phase 237 used INFO, Phase 238/239 used `None surfaced` or omitted (no candidates); planner matches precedent unless a row is unambiguously higher.
- Whether the consolidated `v30-GAMEOVER-JACKPOT-SAFETY.md` mirrors the 238 FREEZE-PROOF 10-column Consolidated Table format or uses a GO-01..05 per-requirement section layout — planner picks (recommend per-requirement section layout because GO-01..05 are semantically distinct, unlike 238's uniform per-consumer rows).
- Row ID prefix variants (`GO-240-NNN` vs `GOJP-NNN` vs `GO240-NNN`) — planner picks, used consistently within each file.
- Whether the GO-04 narrative uses bulleted actor-verdict labels vs prose paragraphs — planner picks (recommend bulleted for grep-stability).
- Whether Plan 240-01 preserves the raw `grep` commands used for fresh-eyes GO-01 re-derivation — encouraged when non-obvious (239-02 Claude's Discretion carry-forward).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 237 scope anchor (MUST read — READ-only per D-31)
- `audit/v30-CONSUMER-INVENTORY.md` — 146 INV-237-NNN rows + 146 per-consumer call graphs + Consumer Index
  - §"Universe List" — 19-row gameover-flow subset (7 gameover-entropy + 4 F-29-04 + 8 prevrandao-fallback) is GO-01 scope anchor; 4-row F-29-04 subset is GO-05 input
  - §"Per-Consumer Call Graphs" — storage-read set per consumer (feeds GO-03 per-variable enumeration); PREFIX-GAMEOVER (7 rows) + PREFIX-PREVRANDAO (8 rows) shared-prefix chains
  - §"Consumer Index" — GO-01..04 = 19 rows; GO-05 = 4 F-29-04 rows (reused verbatim; Phase 240 reconciliation per D-05)
  - §"KI Cross-Ref Summary" — 4 accepted KI entries including EXC-02 prevrandao (GO-02 exception subject) + EXC-03 F-29-04 (GO-02 exception subject + GO-05 containment subject)

### Phase 238 output (MUST read — corroborating per D-17)
- `audit/v30-FREEZE-PROOF.md` — final consolidated 238 deliverable; 19-row Gameover-Flow Freeze-Proof Subset + 22-row KI-Exception subset (8 prevrandao + 4 F-29-04 rows match GO-02 EXCEPTION scope) + Named Gate distribution for gameover-flow subset; Scope-Guard Deferral section (Phase 239 audit assumption already discharged per 239 Plan Decisions; Phase 240 needs no new deferral)
- `audit/v30-238-01-BWD.md` — 19-row Gameover-Flow Backward-Freeze Subset (per-consumer BWD-01/02/03 verdicts); cross-cite source for GO-02 player / admin / validator adversarial-closure cells
- `audit/v30-238-02-FWD.md` — 19-row Gameover-Flow Forward-Enumeration Subset; cross-cite source for GO-03 state-variable enumeration (storage reads + write-path enumeration already per-consumer)
- `audit/v30-238-03-GATING.md` — 19-row subset of the 146-row Gating Verification Table; Named Gate citations for gameover-flow rows (expected distribution: `rngLocked` = 7 gameover-entropy + `semantic-path-gate` = 12 exception rows = 19)

### Phase 239 output (MUST read — corroborating per D-17)
- `audit/v30-RNGLOCK-STATE-MACHINE.md` — RNG-01 rngLockedFlag state machine; D-19 gameover-bracket Path Enumeration row covers rngLockedFlag set/clear around gameover VRF request
- `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` § Asymmetry B — phase-transition-gate origin proof; corroborating for GOVAR rows gated by `phase-transition-gate`
- `audit/v30-PERMISSIONLESS-SWEEP.md` — 62-row permissionless sweep; Phase 240 GO-04 trigger-timing player-centric analysis can cross-cite the `respects-rngLocked` / `respects-equivalent-isolation` / `proven-orthogonal` row verdicts for any function that touches gameover-trigger state (expected: `advanceGame`, `_endPhase`, `handleEffectivePoolDeficit` — verify at HEAD during planning)

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` §"GO — Gameover Jackpot Safety (VRF-available branch)" (GO-01/02/03/04/05) — exact requirement wording, locks GO-02 VRF-available-branch-only scope and GO-05 F-29-04-scope-containment framing
- `.planning/ROADMAP.md` Phase 240 block — 5 Success Criteria + "Depends on: Phase 237" + "expected 2-3 plans — GO-01 consumer inventory + GO-02 determinism proof, GO-03 state-freeze + GO-04 trigger-timing disproof, GO-05 F-29-04 scope containment" (literal grouping honoured per D-01)
- `.planning/PROJECT.md` Current Milestone v30.0 — write-policy statement + accepted RNG exceptions list

### Accepted RNG exceptions (MUST read — frame GO-02 EXCEPTION verdicts + GO-05 SUBJECT, NOT basis)
- `KNOWN-ISSUES.md` §"Gameover prevrandao fallback" — SUBJECT of GO-02's 8 EXCEPTION rows (INV-237-055..062); forward-cite to Phase 241 EXC-02 per D-19 strict boundary
- `KNOWN-ISSUES.md` §"Gameover RNG substitution for mid-cycle write-buffer tickets" (F-29-04) — SUBJECT of GO-02's 4 EXCEPTION rows (INV-237-024, -045, -053, -054) + SUBJECT of GO-05 scope-containment proof; forward-cite to Phase 241 EXC-03 per D-19
- `KNOWN-ISSUES.md` §"Lootbox RNG uses index advance isolation instead of rngLockedFlag" — OUT of Phase 240 scope (no gameover-jackpot interaction); cross-ref only if GOVAR-240-NNN rows touch lootbox storage (unlikely)
- `KNOWN-ISSUES.md` §"Non-VRF entropy for affiliate winner roll" — OUT of Phase 240 scope; Phase 241 EXC-01
- `KNOWN-ISSUES.md` §"EntropyLib XOR-shift PRNG for lootbox outcome rolls" — OUT of Phase 240 scope (gameover jackpot does not use EntropyLib XOR-shift per Phase 237 Consumer Index); Phase 241 EXC-04

### Prior-milestone artifacts — CROSS-CITE ONLY (D-17), NOT RELIED UPON
- `.planning/milestones/v29.0-phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-PFTB-AUDIT.md` — non-zero-entropy guarantees around phase transition; corroborating for GOVAR rows gated by phase-transition-gate + GO-02 VRF-available verdicts
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-04-COMMITMENT-WINDOW.md` — per-consumer commitment-window enumeration; corroborating for GO-01 fresh-eyes reconciliation (gameover-flow rows specifically)
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-TRNX-01.md` — `rngLocked` 4-path walk; corroborating for GO-02 on-chain-actor-column adversarial closure
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` — v25.0 RNG fresh-eyes SOUND verdict; last milestone-level RNG-invariant baseline
- `.planning/milestones/v3.7-phases/` — Phases 63-67 VRF path test coverage (Foundry invariants + Halmos) + rawFulfillRandomWords revert-safety proof; corroborating
- `.planning/milestones/v3.8-phases/` — Phases 68-72 VRF commitment window (55 variables, 87 permissionless paths, 51/51 SAFE); corroborating structural baseline

### Phase decision lineage (MUST read — precedent inheritance)
- `.planning/phases/237-vrf-consumer-inventory-call-graph/237-CONTEXT.md` — D-06 KI-exceptions-in-inventory + D-10 Consumer Index + D-17 HEAD anchor + D-18 READ-only; Phase 240 inherits every structural invariant
- `.planning/phases/238-backward-forward-freeze-proofs/238-CONTEXT.md` — D-01 strict-per-requirement plan split + D-09/D-10 fresh-re-prove + cross-cite + D-13 named-gate taxonomy (reused in GO-03 D-10) + D-19/D-20 HEAD anchor + READ-only + D-16 consolidated-file-in-last-plan pattern (reused in D-27)
- `.planning/phases/239-rnglocked-invariant-permissionless-sweep/239-CONTEXT.md` — D-14 proof-by-exhaustion format + D-15 forward-cite reconciliation precedent + D-22 no-F-30-NN emission + D-27 READ-only + D-29 discharge-evidenced-by-commit pattern (Phase 240 D-32 inherits and adjusts — no new discharges)

### Project feedback rules (apply across all plans per user's durable instructions)
- `memory/feedback_rng_backward_trace.md` — RNG-audit methodology anchor (GO-02 adversarial closure + GO-03 state-freeze enumeration)
- `memory/feedback_rng_commitment_window.md` — commitment-window methodology (GO-02 per-consumer determinism evidence)
- `memory/feedback_no_contract_commits.md` — READ-only scope enforcement (D-30)
- `memory/feedback_never_preapprove_contracts.md` — orchestrator never tells subagents contract changes are pre-approved
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source; stale copies elsewhere are ignored
- `memory/feedback_skip_research_test_phases.md` — skip research for mechanical/obvious phases (Phase 240 is audit-execution with strong precedent from 237/238/239; plan directly from this CONTEXT.md unless the planner identifies a genuinely novel research question)

### In-scope contract tree (`contracts/`) — HEAD `7ab515fe` (per D-29)
Same surface as Phase 237 D-18 + Phase 238/239 inherited (no re-enumeration): 17 top-level contracts + 11 modules + 5 libraries. `contracts/mocks/` OUT of scope.

### Known-concentration files for gameover-flow audit (pre-scan informational; planner re-greps at HEAD)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `_gameOverEntropy` function + gameover VRF request site + `_getHistoricalRngFallback` prevrandao fallback (EXC-02 subject) + 14-day `GAMEOVER_RNG_FALLBACK_DELAY` @ L109 + call-site @ L1252 + terminal-state gameover @ L292 + L1082 + L1222-1246 + `_endPhase` @ L634 (gameover trigger via 120-day liveness + pool deficit path; single caller from `advanceGame:460` per 239-03 § Asymmetry B)
- `contracts/modules/DegenerusGameMintModule.sol` — F-29-04 mid-cycle write-buffer ticket substitution surface (entered via delegatecall from AdvanceModule `_processFutureTicketBatch`); GO-05 state-variable-disjointness proof inputs
- `contracts/storage/DegenerusGameStorage.sol` — jackpot-pool storage slots, winner-index storage slots, trait-array storage, pending-queue storage, counter state; GO-03 per-variable enumeration inputs
- `contracts/DegenerusGame.sol` — gameover-termination bookkeeping + pool-deficit handler; GO-04 trigger-surface file:line inputs
- `contracts/libraries/JackpotBucketLib.sol` — `soloBucketIndex` library call (per 237-03 Plan Decisions); GO-03 per-variable inputs if jackpot bucket state is read at gameover consumption

</canonical_refs>

<code_context>
## Existing Code Insights

### GO-01 Surface (Gameover-VRF Consumer Inventory)
- **19-row gameover-flow scope anchor** from Phase 237 Consumer Index:
  - **7 `gameover-entropy` rows** — VRF-available gameover-jackpot consumers (winner selection, trait rolls, terminal ticket drain, final-day burn/coinflip resolution, sweep distribution). Consumer family: `_gameOverEntropy` cluster per Phase 237-02 Decision.
  - **4 `other / exception-mid-cycle-substitution` rows** (INV-237-024, -045, -053, -054) — F-29-04 mid-cycle substitution surface. `EXCEPTION (KI: EXC-03)` per Phase 238 FREEZE-PROOF 22-row KI-Exception Subset.
  - **8 `other / exception-prevrandao-fallback` rows** (INV-237-055..062) — prevrandao fallback surface. `EXCEPTION (KI: EXC-02)` per Phase 238 FREEZE-PROOF 22-row KI-Exception Subset. 14-day `GAMEOVER_RNG_FALLBACK_DELAY` @ AdvanceModule.sol:109 + call-site @ :1252.
- **Fresh-eyes re-derivation at HEAD `7ab515fe`** — planner performs independent `grep -rn 'gameover\|_gameOverEntropy\|rawFulfillRandomWords' contracts/` pass in Plan 240-01 Task 1; reconciles against 19-row Phase 237 subset per D-05.

### GO-02 Surface (VRF-Available Determinism)
- **Per-consumer adversarial closure** inputs from Phase 238 19-row Gameover-Flow Freeze-Proof Subset (124 SAFE + 22 EXCEPTION distribution filtered to gameover-flow rows only). Phase 240 re-derives fresh at HEAD per D-17; Phase 238 verdicts are corroborating cross-cites, not basis.
- **VRF-available branch isolation** — the 7 pure `gameover-entropy` rows have adversarial-closure verdict `NO_INFLUENCE_PATH (rngLocked)` for player / admin / validator (per Phase 238 BWD-03 / FWD-02 + Phase 239 RNG-01 airtight). Fresh re-derivation traces same gate at HEAD.
- **EXCEPTION boundary** — the 8 prevrandao + 4 F-29-04 rows carry EXCEPTION verdicts with forward-cites to Phase 241 EXC-02 / EXC-03 per D-19. No re-derivation of acceptance (strict boundary).

### GO-03 Surface (State-Freeze Enumeration)
- **Per-variable anchor slots** (from Phase 238 FWD-01 storage-read set for 19-row gameover-flow subset):
  - Jackpot pool totals (DegenerusGameStorage.sol storage slots — planner re-greps at HEAD for exact file:line)
  - Winner-index storage (per-bracket winner-index slots)
  - Trait arrays (per-NFT trait storage for gameover trait rolls)
  - Pending queues (post-swap write-buffer queue — GO-05 containment proof input for disjointness check)
  - Counter state (phase counter, day counter, gameover-trigger liveness timer)
  - Phase-transition active flag (`phaseTransitionActive` storage @ DegenerusGameStorage.sol:282; gate branch @ AdvanceModule.sol:298)
  - rngLockedFlag (DegenerusGameStorage storage; set/clear sites per Phase 239 RNG-01: AdvanceModule.sol:1579 set + :1635 + :1676 + :1700 clear)
- **Named Gate distribution expectation** (from Phase 238-03 GATING 19-row gameover-flow filter):
  - 7 gameover-entropy rows → `rngLocked`
  - 4 F-29-04 rows → `semantic-path-gate` (EXC-03 subject, terminal-state gameover)
  - 8 prevrandao-fallback rows → `semantic-path-gate` (EXC-02 subject, 14-day `GAMEOVER_RNG_FALLBACK_DELAY`)
- **Per-consumer cross-walk** maps each `GO-240-NNN` consumer row to its `GOVAR-240-NNN` variable set; aggregate verdict per D-09.

### GO-04 Surface (Trigger-Timing Disproof)
- **Two primary gameover-trigger surfaces** at HEAD:
  - **120-day liveness stall trigger** — `advanceGame`-origin check; triggering mechanism in DegenerusGameAdvanceModule.sol (planner re-greps for `120 days` / `LIVENESS_STALL_DELAY` constant at HEAD to lock file:line); called from `_endPhase` @ :634 per Phase 239-03 § Asymmetry B Call-Chain Rooting Proof
  - **Pool deficit trigger** — `handleEffectivePoolDeficit` or equivalent (planner re-greps at HEAD for `effectivePool` / `poolDeficit` identifiers); entry path for gameover-termination when pool collateral becomes insufficient
- **Player-reachable manipulation vectors to consider** (per D-11 player-centric model):
  - Direct trigger-state SSTORE: blocked by storage-slot access control + single-caller-from-`advanceGame:460` per Phase 239-03 § Asymmetry B (no player-reachable write path to trigger-state)
  - Indirect trigger-state influence via timing of mint/burn/purchase transactions (pool-deficit trigger): economic analysis — player can delay their own tx but cannot advance time; 120-day liveness requires network-level inactivity (not player-reachable)
  - Cross-tx state timing: players can serialize their tx calls, but gameover-trigger state is single-threaded-EVM atomic (per Phase 239-03 § Asymmetry B No-Player-Reachable-Mutation-Path Proof)
- **Non-player actors** (per D-11 narrative paragraph):
  - Admin: no `onlyAdmin` gameover-trigger toggle at HEAD (planner verifies via grep over `onlyAdmin\|onlyOwner\|onlyGovernance` modifiers on any function touching gameover-trigger state)
  - Validator: block-delay attacks bounded by 14-day `GAMEOVER_RNG_FALLBACK_DELAY` (EXC-02 accepted); gameover-trigger is state-based, not time-based (block.timestamp not directly in gameover-trigger predicate per Phase 237/238)
  - VRF-oracle: withholding fulfillment routes to prevrandao fallback (EXC-02); Phase 241 EXC-02 owns acceptance re-verification

### GO-05 Surface (F-29-04 Scope Containment)
- **4 F-29-04 rows** (INV-237-024, -045, -053, -054 per Phase 238 Plan 03 Decisions) — terminal-state mid-cycle write-buffer ticket substitution
- **11 VRF-available jackpot-input rows** = 19-row gameover-flow subset − 8 prevrandao-fallback rows = 11 rows (7 gameover-entropy + 4 F-29-04 if scope-wide) — for GO-05 disjointness, the target is 7-row gameover-entropy subset (F-29-04 rows ARE the exception under test, so the proof is `{4 F-29-04 rows} ∩ {7 gameover-entropy rows} = ∅`)
- **F-29-04 storage slots** — ticket pre-swap-vs-post-swap RNG-word substitution surface (post-swap write buffer storage). Planner re-greps at HEAD for write-buffer-related storage identifiers (e.g., `pendingTickets`, `writeBuffer`, `postSwapQueue`)
- **Jackpot-input storage slots** — Plan 240-02 output `GOVAR-240-NNN` enumeration (required Wave-2 dependency per D-02)

### Shared Cross-Phase Evidence
- **Phase 237** provides the 19-row gameover-flow subset + 4-row F-29-04 subset (Consumer Index) as the scope anchor
- **Phase 238** provides the per-consumer BWD/FWD/gating verdicts for the 19-row subset (Phase 240 cites; re-derives fresh at HEAD per D-17)
- **Phase 239** provides the rngLockedFlag state machine + phase-transition-gate origin proof that underwrite Phase 240's Named Gate citations for GOVAR rows
- **v29.0 Phase 235 Plan 05 TRNX-01** — 4-path rngLocked walk; corroborating for GO-02 player adversarial closure
- **Repo-root audit artifacts** (`STORAGE-WRITE-MAP.md`, `ACCESS-CONTROL-MATRIX.md`, `ETH-FLOW-MAP.md`) — structural scaffolding for GO-03 per-variable Write Paths column + GO-04 admin narrative closed-verdict

### Plan File Structure (per D-01 / D-27)
- `240-01-PLAN.md` → `audit/v30-240-01-INV-DET.md` — GO-01 19-row fresh-eyes inventory + Phase 237 reconciliation + GO-02 VRF-available determinism proof with 19-row EXCEPTION-pattern table (7 SAFE + 12 EXCEPTION forward-cited) + Finding Candidates appendix
- `240-02-PLAN.md` → `audit/v30-240-02-STATE-TIMING.md` — GO-03 Per-Variable `GOVAR-240-NNN` enumeration + Per-Consumer cross-walk + GO-04 Trigger Surface `GOTRIG-240-NNN` table + non-player actor narrative with closed verdicts + Finding Candidates appendix
- `240-03-PLAN.md` → `audit/v30-240-03-SCOPE.md` + `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` — GO-05 inventory-disjointness + state-variable-disjointness dual-proof (reads Plan 240-02's `GOVAR-240-NNN` output) + Finding Candidates appendix; consolidated file assembles all 5 requirement sections via Python merge script (238-03 Task 3 pattern) + merged Finding Candidates + merged Scope-Guard Deferrals (if any) + Attestation

</code_context>

<specifics>
## Specific Ideas — 3-Plan Shape, 2-Wave Topology

Per D-01 + D-02, three plans, 2-wave topology:

### Wave 1 (240-01 + 240-02 parallel — zero cross-dependencies at HEAD)

#### Plan 240-01-PLAN.md — GO-01 Consumer Inventory + GO-02 VRF-Available Determinism Proof
- **Anchor citation:** `contracts/` gameover-VRF-consumer sites at HEAD `7ab515fe` (pre-scanned surfaces in `<code_context>`); Phase 237 `audit/v30-CONSUMER-INVENTORY.md` 19-row gameover-flow subset for reconciliation per D-05
- **Deliverable:** `audit/v30-240-01-INV-DET.md` — GO-01 19-row inventory table per D-04 + GO-01 reconciliation verdicts per D-05 + GO-02 19-row determinism proof table per D-06 (7 SAFE + 12 EXCEPTION with forward-cites per D-19) + per-plan Finding Candidates appendix per D-26
- **Cross-cites (re-verified at HEAD per D-18):** Phase 237 Consumer Index 19-row gameover-flow subset (scope anchor), Phase 238 FREEZE-PROOF 19-row Gameover-Flow subset (corroborating for player/admin/validator adversarial closure), Phase 239 RNG-01 D-19 gameover-bracket (corroborating for rngLocked gate), v29.0 Phase 232.1-03 (non-zero-entropy corroborating), v29.0 Phase 235 Plan 04 commitment-window (GO-01 reconciliation corroborating), v25.0 Phase 215 (structural baseline), KI EXC-02 + EXC-03 (EXCEPTION verdict subjects, forward-cited to Phase 241 per D-19)
- **Verdict taxonomy:** GO-01 reconciliation {`CONFIRMED_FRESH_MATCHES_237` / `NEW_SINCE_237` / `SUPERSEDED_IN_237` / `CANDIDATE_FINDING`}; GO-02 verdicts {`SAFE_VRF_AVAILABLE` / `EXCEPTION (KI: EXC-02)` / `EXCEPTION (KI: EXC-03)` / `CANDIDATE_FINDING`}; no hedged verdicts per D-07
- **Forward-cites:** GO-02's 8 prevrandao rows + 4 F-29-04 rows cite Phase 241 EXC-02 / EXC-03 by path (cite held; reconciliation erratum per D-19 if Phase 241 structure diverges — strict boundary mandates no Phase 240 re-edit)

#### Plan 240-02-PLAN.md — GO-03 State-Freeze Enumeration + GO-04 Trigger-Timing Disproof
- **Anchor citation:** `contracts/` storage slots touched by 19-row gameover-flow consumers + gameover-trigger surfaces at HEAD `7ab515fe`; Phase 237 Consumer Index + Phase 238 FWD-01 storage-read set for 19-row subset
- **Deliverable:** `audit/v30-240-02-STATE-TIMING.md` — GO-03 Per-Variable `GOVAR-240-NNN` table per D-09 + Per-Consumer cross-walk per D-09 + GO-04 Trigger Surface `GOTRIG-240-NNN` table per D-12 + Non-Player Actor Narrative with closed verdicts per D-12 + per-plan Finding Candidates appendix per D-26
- **Cross-cites (re-verified at HEAD per D-18):** Phase 237 Consumer Index (19-row gameover-flow subset Consumer Index), Phase 238-02 FWD-01 storage-read set (corroborating for GOVAR rows), Phase 238-03 GATING Named Gate distribution (corroborating for Named Gate column per D-10), Phase 239 RNG-01 gameover-bracket Path Enumeration (corroborating for rngLocked gate), Phase 239-03 § Asymmetry B Call-Chain Rooting Proof + No-Player-Reachable-Mutation-Path Proof (corroborating for GO-04 single-threaded-EVM + player-closure arguments), v29.0 Phase 232.1-03 (phase-transition corroborating), STORAGE-WRITE-MAP + ACCESS-CONTROL-MATRIX (admin-narrative verdict corroborating), v25.0 + v3.7 + v3.8 (structural baselines)
- **Verdict taxonomy:** GO-03 GOVAR verdicts {`FROZEN_AT_REQUEST` / `FROZEN_BY_GATE` / `EXCEPTION (KI: EXC-NN)` / `CANDIDATE_FINDING`}; GO-03 per-consumer aggregate {`SAFE` / `EXCEPTION` / `CANDIDATE_FINDING`}; GO-04 GOTRIG verdicts {`DISPROVEN_PLAYER_REACHABLE_VECTOR` / `CANDIDATE_FINDING`}; Non-player narrative closed verdicts {`NO_DIRECT_TRIGGER_SURFACE` (admin) / `BOUNDED_BY_14DAY_EXC02_FALLBACK` (validator) / `EXC-02_FALLBACK_ACCEPTED` (VRF-oracle)} per D-12; no hedged verdicts per D-13
- **Attestation requirement (per D-13):** 240-02-SUMMARY must attest the non-player narrative exists and delivers a closed verdict per actor; absence = re-open plan

### Wave 2 (240-03 solo — reads 240-01 + 240-02 outputs + produces consolidated file)

#### Plan 240-03-PLAN.md — GO-05 F-29-04 Scope Containment + Final Consolidation
- **Anchor citation:** `contracts/` F-29-04 write-buffer-swap storage slots + Plan 240-02's `GOVAR-240-NNN` jackpot-input universe at HEAD `7ab515fe`; Phase 237 Consumer Index 4-row F-29-04 subset for inventory-disjointness proof
- **Deliverable 1:** `audit/v30-240-03-SCOPE.md` — GO-05 Inventory-Disjointness Proof per D-14 + GO-05 State-Variable-Disjointness Proof per D-14 + closed verdict per D-15 + per-plan Finding Candidates appendix per D-26
- **Deliverable 2:** `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` — consolidated assembly per D-27; Python merge script pattern from 238-03 Task 3 (`/tmp/gameover-build/build_consolidated.py`); sections: GO-01 Unified Gameover-VRF Consumer Inventory, GO-02 Determinism Proof Table, GO-03 Per-Variable + Per-Consumer tables, GO-04 Trigger Surface Table + non-player narrative, GO-05 Dual-Disjointness Proof, Consumer Index updating Phase 237's GO-01..05 rows with Phase 240 verdicts, merged Finding Candidates, merged Scope-Guard Deferrals (if any), Attestation with HEAD `7ab515fe` anchor
- **Cross-cites (re-verified at HEAD per D-18):** Phase 237 Consumer Index 4-row F-29-04 subset (scope anchor), Plan 240-02's `GOVAR-240-NNN` table (Wave-2 direct input), Phase 238 FREEZE-PROOF 22-row KI-Exception subset (corroborating for F-29-04 EXCEPTION boundary), Phase 239-03 § Asymmetry B (corroborating for phase-transition-gate write boundary), v29.0 Phase 235 Plan 04 F-29-04 commitment-window trace (corroborating), KI EXC-03 F-29-04 entry (SUBJECT, not warrant — acceptance forward-cited to Phase 241 per D-19)
- **Verdict taxonomy:** GO-05 sub-proof verdicts {`DISJOINT` / `CANDIDATE_FINDING`}; combined containment verdict `BOTH_DISJOINT` iff both sub-proofs `DISJOINT` per D-15
- **Task split (238-03 Task 3 precedent):** Task 1 (build 240-03-SCOPE.md GO-05 section) + Task 2 (commit 240-03-SCOPE.md) → single commit; Task 3 (assemble + commit consolidated v30-GAMEOVER-JACKPOT-SAFETY.md via Python merge script) → separate commit; Task 4 (SUMMARY + ROADMAP/STATE updates + commit) → plan-close commit

### Cross-plan invariants (apply to all three)
- HEAD `7ab515fe` frontmatter lock per D-29
- READ-only scope per D-30
- No F-30-NN emission per D-25
- Scope-guard deferral on any out-of-scope consumer or state variable per D-31
- Four closed verdict taxonomies across all plans (GO-01 reconciliation / GO-02 determinism / GO-03 freeze / GO-04 trigger / GO-05 disjointness) — no hedged narrative-only verdicts in any plan
- Phase 237 inventory + Phase 238 freeze-proof + Phase 239 state-machine outputs READ-only (NOT re-edited) per D-31
- Forward-cites to Phase 241 EXC-02 / EXC-03 per D-19 strict boundary — no Phase 241 acceptance re-verification in Phase 240

</specifics>

<deferred>
## Deferred Ideas

- **Phase 241 KI-exception acceptance re-verification (EXC-01..04)** — Phase 240 forward-cites KI EXC-02 (prevrandao fallback) + KI EXC-03 (F-29-04) as SUBJECTS of GO-02 EXCEPTION rows + GO-05 containment subject but does NOT re-litigate acceptance. Phase 241 EXC-02 (prevrandao trigger-gating at HEAD — only reachable inside `_gameOverEntropy` when VRF request ≥ 14 days outstanding), EXC-03 (F-29-04 scope unchanged — terminal-state only, no player-reachable timing, post-swap write buffer only) own acceptance re-verification per D-22 strict boundary.
- **Phase 242 FIND-01/02/03 consolidation + F-30-NN ID assignment** — Phase 240 produces Finding Candidate pool only per D-25. Consolidation into `audit/FINDINGS-v30.0.md` with severity classification + regression appendix is Phase 242's scope per D-23.
- **Non-player-actor deep-dive for GO-04** — the user chose player-centric attacker model with narrative paragraph for admin/validator/VRF-oracle per D-11. If a future C4A warden or Phase 242 audit argues the narrative paragraph is insufficient coverage of REQUIREMENTS.md GO-04 "any actor" language, the gap routes to Phase 242 FIND-01 pool per D-13 (NOT a Phase 240 amendment — READ-only-after-commit per D-31). Future-milestone candidate: full 4-actor BWD-03-style per-actor per-trigger table.
- **Cross-cycle gameover-VRF chaining audit** — gameover VRF word seeds entropy for multiple dependent consumers (winner selection, trait rolls, ticket drain, burn/coinflip resolution, sweep). Phase 240 GO-02 covers per-consumer determinism on the VRF-available branch; cross-consumer entropy-chain correlation (e.g., if trait-roll output biases winner-selection seed) is implicitly covered via GO-03's per-variable enumeration but not explicitly enumerated as a cross-consumer chain. Out of Phase 240 scope (Phase 237 deferred this already; Phase 242 REG-02 v3.8 commitment-window regression may surface it).
- **Automated invariant runner against GO-01..05 tables** — Foundry/Halmos-queryable encoding of gameover-VRF consumer universe + state-freeze invariants + trigger-timing guards. Out of v30.0 scope (READ-only, no test writes per D-30). Future-milestone candidate (237/238/239 all deferred similarly).
- **EntropyLib XOR-shift PRNG inside gameover-flow consumers** — if any GO-240-NNN consumer calls `EntropyLib.entropyStep()`, the PRNG-primitive acceptance is Phase 241 EXC-04. Phase 240 GO-03 lists `EntropyLib.*` as a keccak-seeded library call with VRF-word seed per 237-03 D-11 (not a state-machine participant). Per-gameover-consumer XOR-shift acceptance is out of Phase 240 scope.
- **Gameover liveness-stall constant recalibration** — if `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` or the 120-day liveness-stall constant is proposed for change in a future milestone, Phase 240 GO-04 player-reachable-manipulation-vector analysis requires re-derivation. Out of v30.0 scope (constants are frozen at HEAD `7ab515fe`; any post-v30 change triggers a scope addendum per D-29).
- **Post-v29 contract-tree divergence** — if any post-v29.0 commit to `contracts/` lands before Phase 240 commits (tree currently identical to `1646d5af` per PROJECT.md), the baseline resets and all three Phase 240 plans require scope addendums per D-29. Planner monitors HEAD between plan starts.
- **Admin-actor gameover-trigger-state audit** — Phase 240 GO-04 D-11 covers admin via narrative (`NO_DIRECT_TRIGGER_SURFACE` closed verdict). Deep-dive per-admin-function enumeration (like Phase 239 RNG-02 but admin-gated) is out of Phase 240 scope — admin actor class is Phase 238 BWD-03 / FWD-02 per-consumer scope already covered. Any admin-gated function that touches gameover-trigger state is a Phase 238 row; Phase 240 GO-04 cites Phase 238's verdicts for admin.
- **Gameover-jackpot UX / frontend / indexer determinism** — off-chain consumers of gameover-VRF outputs (frontend winner display, indexer jackpot-payout events, database-side jackpot-distribution logic) are out of v30.0 scope per REQUIREMENTS.md §"Out of Scope" (Indexer / database / sim / frontend covered v28.0). Phase 240 is VRF-available-branch-determinism-at-the-contract-level only.

</deferred>

---

*Phase: 240-gameover-jackpot-safety*
*Context gathered: 2026-04-19*
