# Phase 241: Exception Closure - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Confirm the 4 KNOWN-ISSUES RNG entries are the *only* violations of the RNG-consumer determinism invariant at HEAD `7ab515fe`:

- **EXC-01** — affiliate winner roll is the SOLE non-VRF-seeded randomness consumer in `contracts/` (proof subjects: `INV-237-005` 50/50 no-referrer flip at `DegenerusAffiliate.sol:568`, `INV-237-006` 75/20/5 weighted roll at `DegenerusAffiliate.sol:585`)
- **EXC-02** — gameover prevrandao fallback (`_getHistoricalRngFallback`) reachable ONLY inside `_gameOverEntropy` AND ONLY when an in-flight VRF request has been outstanding ≥ `GAMEOVER_RNG_FALLBACK_DELAY = 14 days`; no additional entry points at HEAD (8 proof subjects carried forward from Phase 237 `exception-prevrandao-fallback` subcategory + 17 EXC-02 forward-cite tokens from Phase 240 requiring line-item discharge)
- **EXC-03** — F-29-04 mid-cycle RNG substitution scope unchanged: terminal-state only + no player-reachable timing + post-swap write buffer only (4 proof subjects: `INV-237-024, -045, -053, -054` + 12 EXC-03 forward-cite tokens from Phase 240 requiring line-item discharge)
- **EXC-04** — `EntropyLib.entropyStep()` seed derivation remains fully VRF-derived via `keccak256(rngWord, player, day, amount)` — no new entry point bypasses the keccak seed construction (8 proof subjects from Phase 237 `exception-xor-shift-seed`-adjacent subcategory)

Phase 241 clarifies HOW to re-verify these 4 exceptions and close the universal ONLY-ness claim at HEAD. New capabilities belong in other phases.

</domain>

<decisions>
## Implementation Decisions

### Plan Split & Output Shape (Claude's Discretion — user did not select as gray area; default to ROADMAP + 237/238/240 precedent)
- **D-01 (single consolidated plan — ROADMAP "single consolidated exception-closure plan" option):** ROADMAP says `"TBD (expected 1-2 plans — EXC-01/02 paired (affiliate + prevrandao), EXC-03/04 paired (F-29-04 + EntropyLib); or a single consolidated exception-closure plan)"`. Single consolidated plan chosen: all 4 EXC-NN requirements are HEAD re-verifications against already-documented KIs with Phase 237/238/239/240 cross-cite availability; the universal ONLY-ness claim is one artifact (the closed-set-of-4 exceptions table); parallelization gain from splitting is marginal because each EXC re-verification is narrow and reads largely disjoint prior-artifact slices. Single-plan structure matches 235/239 narrow-scope precedent.
- **D-02 (single consolidated deliverable — ROADMAP SC-1 literal):** ROADMAP Phase 241 SC-1 names `audit/v30-EXCEPTION-CLOSURE.md` (singular). One consolidated file matches 237/238/240 consolidated pattern (Phase 240 D-27) rather than 239's 3-separate-dedicated-files pattern (Phase 239 D-24). No per-EXC intermediate files; the single plan emits the single file directly.
- **D-03 (task structure within single plan — 5 tasks):** Task 1: EXC-01 ONLY-ness table + dual-gate closure (D-06/D-09). Task 2: EXC-02 prevrandao-fallback trigger-gating re-verification + line-item discharge of Phase 240's 17 EXC-02 forward-cites (D-11). Task 3: EXC-03 F-29-04 scope re-verification (tri-gate: terminal-state + no-player-reachable-timing + write-buffer-only) + line-item discharge of Phase 240's 12 EXC-03 forward-cites (D-11). Task 4: EXC-04 EntropyLib keccak seed-derivation re-verification (D-11). Task 5: Consolidation into `audit/v30-EXCEPTION-CLOSURE.md` (single-plan sibling of 238-03 Task 3 / 240-03 Task N consolidation pattern). Tasks 1–4 run sequentially within the single plan (no wave topology needed because there is only one plan).

### EXC-01 Proof Methodology (user-selected gray area)
- **D-04 (inventory-walk primary + grep backstop — reconciled Q1+Q4):** Primary warrant is a per-row walk of Phase 237's 146-row Consumer Index at HEAD `7ab515fe`: each row receives a seed-source verdict in {`VRF_DERIVED` / `NON_VRF_PER_KI_EXC_01` / `NON_VRF_PER_KI_EXC_02` / `NON_VRF_PER_KI_EXC_03` / `NON_VRF_PER_KI_EXC_04` / `CANDIDATE_FINDING`}. Grep runs as a cheap sanity backstop — it does NOT carry co-equal warrant weight (user explicitly chose "Inventory-walk only (lighter)" for primary methodology in Q1 + "Yes — grep as sanity backstop" confirmation follow-up). Phase 237 Consumer Index READ-only per Phase 240 D-31; any non-VRF seed surfaced by grep but absent from Phase 237's inventory routes to scope-guard deferral + Phase 242 FIND-01 intake, not an inventory amendment.

- **D-05 (exploitability frame — user-specified for the entire phase, not just EXC-01):** User: *"I know we aren't using shitty randomness. not worried about that. just worried about exploitability"* (discussion Q2 free-form). Phase 241 does NOT re-litigate randomness distribution quality — the 4 KIs already concede distribution concessions (XOR-shift theoretical weaknesses, prevrandao 1-bit proposer bias, deterministic affiliate seed). Phase 241 re-verifies that **player-reachable exploitability stays closed** at HEAD. This frame applies to all 4 EXC re-verifications:
  - **EXC-01 rows:** primary verdict axis is "does a player have a reachable path to influence the seed in a way that materially biases the outcome?" Admin-only / validator-only / VRF-oracle-only non-VRF surfaces receive verdict `NOT_PLAYER_REACHABLE_OUT_OF_SCOPE` (matches Phase 240 D-13 non-player-actor narrative pattern — closed but de-emphasized).
  - **EXC-02 rows:** re-verification focuses on reachability closure for `_getHistoricalRngFallback` (single-call-site predicate) + the 14-day delay gate (`GAMEOVER_RNG_FALLBACK_DELAY` constant still `14 days`); distribution quality of prevrandao-admixed fallback is NOT re-litigated.
  - **EXC-03 rows:** re-verification focuses on player-reachable-timing disproof of the mid-cycle write-buffer substitution (tri-gate: terminal-state / no-player-timing / buffer-scope); distribution quality of gameover entropy is NOT re-litigated.
  - **EXC-04 rows:** re-verification focuses on keccak seed construction intact — `keccak256(rngWord, player, day, amount)` with `rngWord` VRF-derived; XOR-shift distribution theory is NOT re-litigated.

- **D-06 (fold-all-4-KIs single consolidated ONLY-ness claim):** User chose "Fold all 4 KIs into one ONLY-ness claim" at Q3. The EXC-01 output carries a single consolidated ONLY-ness table that lists the 22 total EXCEPTION rows as the **closed set of documented exceptions** at HEAD: 2 EXC-01-affiliate (`INV-237-005, -006`) + 8 EXC-02-prevrandao + 4 EXC-03-F2904 (`INV-237-024, -045, -053, -054`) + 8 EXC-04-XOR-shift = 22. The table is **set-equal with Phase 238's 22 EXCEPTION / 124 SAFE distribution** — this set-equality is a verification gate (Gate A below). Phase 241 does NOT emit a separate EXC-02-only or EXC-03-only or EXC-04-only table for the ONLY-ness claim; the single consolidated table is the universal-claim artifact. EXC-02/03/04 *re-verification* outputs (trigger-gating / scope / seed-derivation) remain distinct per-requirement tables (D-11) — those are re-verification artifacts, not ONLY-ness artifacts.

- **D-07 (closure-universe scope — player-reachable exploitability surface, not exhaustive theoretical surface):** User's exploitability frame (D-05) scopes the grep backstop's target universe. The grep enumerates **player-reachable** non-VRF entropy surfaces in `contracts/`:
  - `block.timestamp` (used via `currentDayIndex()` or direct)
  - `block.number`
  - `block.prevrandao` (Phase 240 EXC-02 scope)
  - `blockhash(...)`
  - packed state counters used as entropy (e.g., `currentDayIndex()`, `storedCode`, nonce-like reads)
  - `msg.sender` used as seed input
  - `keccak256(...)` hashes over non-VRF-committed state feeding an RNG consumer
  - Each grep hit receives classification `ORTHOGONAL_NOT_RNG_CONSUMED` / `BELONGS_TO_KI_EXC_01` / `BELONGS_TO_KI_EXC_02` / `BELONGS_TO_KI_EXC_03` / `BELONGS_TO_KI_EXC_04` / `CANDIDATE_FINDING`. Not worried about randomness theory universe (user Q2): `block.coinbase`, `tx.origin`-as-entropy, `block.difficulty` included only if they appear in contract tree; NOT exhaustively enumerated as theoretical candidates.

- **D-08 (dual-gate closure per user Q4):**
  - **Gate A (set-equality):** The set of Phase 237 Consumer Index rows with verdict ≠ `VRF_DERIVED` at HEAD equals exactly `{INV-237-005, INV-237-006} ∪ {8 EXC-02 prevrandao rows} ∪ {INV-237-024, -045, -053, -054} ∪ {8 EXC-04 XOR-shift-seed rows}` — 22 rows total, set-equal with Phase 238's 22 EXCEPTION distribution. Any Phase 237 row whose HEAD-re-verified seed source does not land in one of the 4 KI groups is a `CANDIDATE_FINDING`. Any row in the expected 22-row set that is missing at HEAD is a `CANDIDATE_FINDING`.
  - **Gate B (grep backstop):** The negative-space grep (D-07 surface universe) surfaces zero `CANDIDATE_FINDING` hits — every hit classified as `ORTHOGONAL_NOT_RNG_CONSUMED` or `BELONGS_TO_KI_EXC_NN`.
  - **Combined closure:** `ONLY_NESS_HOLDS_AT_HEAD` iff both Gate A and Gate B pass. Any failure on either gate routes to scope-guard deferral + Phase 242 FIND-01 intake (Phase 240 D-31 pattern). Grep does not have co-equal warrant weight (D-04); a grep-Gate-B miss blocks ONLY-ness closure but does not retroactively amend Phase 237's inventory — the scope-guard deferral captures the delta for Phase 242.

- **D-09 (EXC-01 closed-verdict taxonomy — no hedged verdicts):** Each of the 22 rows in the consolidated ONLY-ness table ends in exactly one of {`CONFIRMED_SOLE_EXCEPTION_GROUP_EXC_01/02/03/04` / `NOT_PLAYER_REACHABLE_OUT_OF_SCOPE` / `CANDIDATE_FINDING`}. The overall ONLY-ness claim itself ends in {`ONLY_NESS_HOLDS_AT_HEAD` / `CANDIDATE_FINDING`}. Matches 237 D-14 / 238 D-14 / 239 D-05 / 240 D-07 closed-verdict pattern.

### EXC-02/03/04 Re-verification (Claude's Discretion — user did not select as gray area; default to Phase 240 D-17/D-18 fresh-re-prove + cross-cite precedent)
- **D-10 (hybrid depth — cite Phase 240 for surface, re-derive predicates fresh):** Phase 240 already emitted 17 EXC-02 + 12 EXC-03 forward-cite tokens at consumer-site granularity; those tokens establish **consumer-level** presence of the exceptions but do not constitute **trigger-gating / scope-boundary / seed-construction** re-verification. Phase 241 cites Phase 240's `v30-GAMEOVER-JACKPOT-SAFETY.md` GO-01/GO-02 rows as corroborating consumer inventory coverage per D-17 fresh-re-prove + cross-cite discipline, then **re-derives fresh at HEAD** the three predicate families that ROADMAP SC-2/3/4 require:
  - **EXC-02 predicates (fresh re-derive):** (a) `_getHistoricalRngFallback` single-call-site predicate — grep `contracts/` for all callers, confirm the sole caller is `_gameOverEntropy` at `DegenerusGameAdvanceModule.sol:1252` per KI; (b) 14-day gate predicate — confirm `GAMEOVER_RNG_FALLBACK_DELAY` constant still `14 days` at `DegenerusGameAdvanceModule.sol:109`; confirm the gate check still guards every reachable path into the fallback at HEAD.
  - **EXC-03 predicates (fresh re-derive, tri-gate per ROADMAP SC-3):** (a) terminal-state predicate — the substitution fires only inside `_gameOverEntropy` reachable control flow; no non-gameover caller at HEAD; (b) no-player-reachable-timing predicate — gameover trigger surfaces (120-day liveness stall + pool deficit) are the ONLY entries; no player call can time a game-over against a specific mid-cycle write-buffer state (cite Phase 240 GO-04 `DISPROVEN_PLAYER_REACHABLE_VECTOR` as corroborating); (c) buffer-scope predicate — the substitution applies only to tickets in the post-swap write buffer populated by `_swapAndFreeze(purchaseLevel)` at `:292` or `_swapTicketSlot(purchaseLevel_)` at `:1082`; confirm buffer boundary primitives unchanged at HEAD. Tri-gate verdict `RE_VERIFIED_AT_HEAD` iff all three predicates hold.
  - **EXC-04 predicates (fresh re-derive):** `EntropyLib.entropyStep()` seed construction at HEAD — confirm seed still constructed via `keccak256(rngWord, player, day, amount)`; confirm no new entry point into `entropyStep` bypasses keccak seed construction; confirm `rngWord` parameter is VRF-derived at every call site (cite Phase 237 Consumer Index rows for `EntropyLib.entropyStep` consumers).

- **D-11 (forward-cite discharge — explicit line-item per Phase 239 D-29 precedent):** User did not select as gray area; default chosen over Phase 240 D-32's no-discharge rationale because Phase 240 D-32's rationale ("no prior phase recorded an audit assumption pending Phase 240") **does not apply to Phase 241** — Phase 240 **explicitly** emitted 17 `"See Phase 241 EXC-02"` + 12 `"See Phase 241 EXC-03"` forward-cite tokens expecting Phase 241 closure. Phase 241 emits explicit line-item discharge annotations in the `audit/v30-EXCEPTION-CLOSURE.md` deliverable, one per forward-cite token, citing the Phase 241 row that closes it:
  - **Example:** Phase 240 GO-02 row `INV-237-057` carries `"See Phase 241 EXC-02"` → Phase 241 emits `EXC-241-NNN: DISCHARGES Phase 240 GO-02 forward-cite on INV-237-057 — predicate re-verified at HEAD: fallback reachable only inside _gameOverEntropy:1252 + 14-day delay still enforced at :109"`.
  - **Format:** A dedicated "Forward-Cite Discharge Ledger" section in the consolidated file lists all 29 discharges in a grep-stable table. Matches Phase 239 D-29's discharge-claim precedent for Phase 238-03 Scope-Guard Deferral #1.
  - **Residual handling:** If any forward-cite cannot be discharged (predicate fails at HEAD), the discharge entry carries verdict `CANDIDATE_FINDING` and routes to Phase 242 FIND-01 intake. Phase 241 does NOT emit fresh forward-cites to Phase 242 (Phase 242 consumes the CANDIDATE_FINDING pool directly per 237/238/239/240 D-26 pattern).

### Fresh-Eyes + Cross-Cite Discipline (inherit from Phase 240 D-17/D-18)
- **D-12 (fresh re-prove at HEAD + cross-cite prior — Phase 240 D-17 precedent):** Every verdict in Phase 241 re-derived at HEAD `7ab515fe`. CROSS-CITES are corroborating evidence only — never sole warrant:
  - Phase 237 Consumer Index 22 EXCEPTION rows → Gate A set-equality target
  - Phase 238 22 EXCEPTION / 124 SAFE distribution → Gate A cross-check
  - Phase 239 RNG-01 rngLockedFlag state machine + RNG-02 permissionless sweep + RNG-03 asymmetry justifications → corroborate EXC-02 reachability closure
  - Phase 240 GO-01..05 + 29 forward-cite tokens → consumer-level surface coverage for EXC-02/03 + discharge target pool
  - v29.0 Phase 235 Plan 04 F-29-04 commitment-window trace → EXC-03 corroborating prior-milestone artifact
  - v29.0 KI EXC-03 F-29-04 entry itself → SUBJECT of EXC-03 re-verification, NOT warrant
- **D-13 (re-verify-at-HEAD note on every cross-cite — Phase 240 D-18 precedent):** Each cross-cite carries `re-verified at HEAD 7ab515fe` backtick-quoted note with a one-line structural-equivalence statement. Contract tree identical to v29.0 `1646d5af` per PROJECT.md; re-verification is mechanical but mandatory to guard against silent divergence. Minimum ≥3 instances per audit file (239 Plan Decision erratum precedent).

### Scope Boundaries (what Phase 241 is NOT) — strict boundary preserving 237/238/239/240 handoffs
- **D-14 (Phase 241 does NOT re-enumerate the 146-row Consumer Index):** CITES Phase 237 `audit/v30-CONSUMER-INVENTORY.md` at HEAD per Phase 240 D-31. Any surfaced consumer outside Phase 237's 146-row universe is a scope-guard deferral to Phase 242 FIND-01 (not an inventory amendment).
- **D-15 (Phase 241 does NOT re-derive freeze-proofs):** CITES Phase 238 `audit/v30-FREEZE-PROOF.md` 22-EXCEPTION / 124-SAFE distribution. Phase 241's Gate A set-equality proof is checked against Phase 238's EXCEPTION count; a delta is a CANDIDATE_FINDING.
- **D-16 (Phase 241 does NOT re-derive global-invariant or permissionless-sweep or asymmetry-re-justification):** CITES Phase 239 outputs (`v30-RNGLOCK-STATE-MACHINE.md`, `v30-PERMISSIONLESS-SWEEP.md`, `v30-ASYMMETRY-RE-JUSTIFICATION.md`). Phase 239 RNG-03 Asymmetry B (phase-transition-gate origin proof) is the relevant cross-cite for EXC-02 reachability closure — the 14-day fallback gate is distinct from the phase-transition-gate per 240 D-10.
- **D-17 (Phase 241 does NOT re-derive VRF-available-branch jackpot determinism or GO-05 dual-disjointness):** CITES Phase 240 `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` GO-01..05 verdicts. EXC-03 F-29-04 scope re-verification corroborates but does not re-derive GO-05 `BOTH_DISJOINT` (Phase 240 D-15 verdict stands; Phase 241 adds terminal-state + no-player-timing + buffer-scope predicates on top).
- **D-18 (Phase 241 IS the universal ONLY-ness claim + EXC-02/03/04 predicate re-verification + forward-cite discharge):** These three responsibilities are exclusive to Phase 241. Not owned by 237 (inventory-only), 238 (freeze-proof-only), 239 (global-invariant-only), or 240 (gameover-VRF-available-branch-only).
- **D-19 (Phase 241 is not regression — that's Phase 242):** Prior-milestone cross-cites are contemporaneous corroboration, not regression verdicts (PASS/REGRESSED/SUPERSEDED). Regression appendix is Phase 242 REG-01/02 per Phase 240 D-23 pattern.

### Finding-ID Emission (inherit)
- **D-20 (no F-30-NN emission — 235 D-14 / 237 D-15 / 238 D-15 / 239 D-22 / 240 D-25 pattern):** Phase 241 does NOT emit `F-30-NN` finding IDs. Produces verdicts + tables + proofs + Finding Candidate block that becomes Phase 242 FIND-01 intake. Every verdict cites commit SHA + file:line so Phase 242 can anchor without re-discovery.
- **D-21 (Finding Candidates appendix in single deliverable):** The consolidated `v30-EXCEPTION-CLOSURE.md` carries one "Finding Candidates" section listing any row or predicate with verdict `CANDIDATE_FINDING`. Merges into Phase 242 FIND-01 intake alongside 237/238/239/240 candidate pools.

### Output Shape & Row-ID Taxonomy (Claude's Discretion — inherit precedent)
- **D-22 (single consolidated deliverable per D-02 — 237/238/240 pattern):** `audit/v30-EXCEPTION-CLOSURE.md` is the single authoritative deliverable per ROADMAP SC-1. No per-EXC intermediate files (unlike 237/238/240's per-plan intermediates because Phase 241 is single-plan per D-01).
- **D-23 (tabular, grep-friendly, no mermaid — 237 D-09 / 238 D-25 / 239 D-25 / 240 D-28 convention):** All tables grep-stable. Diagrams in prose, not images. Row IDs `EXC-241-NNN` (three-digit zero-padded; single prefix across all 4 requirements — matches 237 D-06 / 239 D-25 / 240 D-04 naming convention).
- **D-24 (consolidated-file section structure):** 10 sections: (1) Frontmatter + HEAD anchor; (2) Executive Summary (closure verdicts); (3) EXC-01 Consolidated ONLY-ness Table (22 rows, closed set of 4 KI groups); (4) EXC-01 Grep Backstop Classification (Gate B evidence); (5) EXC-02 Predicate Re-Verification (single-call-site + 14-day gate); (6) EXC-03 Tri-Gate Predicate Re-Verification (terminal + no-player-timing + buffer-scope); (7) EXC-04 EntropyLib Seed-Construction Re-Verification; (8) Forward-Cite Discharge Ledger (29 discharges of Phase 240 EXC-02/EXC-03 forward-cites per D-11); (9) Prior-Artifact Cross-Cites (re-verified-at-HEAD notes per D-13); (10) Finding Candidates + Scope-Guard Deferrals + Attestation.

### Scope-Guard Handoff (inherit from Phase 240 D-29/D-30/D-31)
- **D-25 (HEAD anchor `7ab515fe` locked in plan frontmatter — 240 D-29 precedent):** Contract tree unchanged since v29.0 `1646d5af`; all post-v29 commits docs-only per PROJECT.md. Any contract change after `7ab515fe` resets the baseline and requires a scope addendum. Frontmatter freeze mandatory in Plan 241-01 and SUMMARY.
- **D-26 (READ-only scope — 240 D-30 precedent):** No `contracts/` or `test/` writes. Carries forward v28/v29 cross-repo READ-only pattern + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_contract_locations.md`. Writes confined to `.planning/` and `audit/` (creating `v30-EXCEPTION-CLOSURE.md` — single new audit file). `KNOWN-ISSUES.md` is NOT touched in Phase 241 — KI promotions are Phase 242 FIND-03 only.
- **D-27 (Phase 237/238/239/240 outputs READ-only — 240 D-31 precedent):** If Phase 241 surfaces a consumer not in Phase 237's 146-row inventory or a non-VRF seed surface absent from Phase 237's 22-EXCEPTION set, it records a scope-guard deferral in Plan 241-01 SUMMARY (file:line + context + proposed inventory delta). Phase 237/238/239/240 outputs are NOT re-edited in place. Inventory gaps become Phase 242 FIND-01 finding candidates.
- **D-28 (no discharge claim beyond forward-cite ledger — distinct from Phase 239 D-29 discharge of 238-03 Scope-Guard Deferral):** Phase 241 emits the Forward-Cite Discharge Ledger per D-11 (which IS a cross-phase discharge pattern). Beyond that, Phase 241 does NOT discharge any Phase 239 RNG-01/RNG-03 audit assumption (per Phase 238 Scope-Guard Deferral #1 routed to Phase 242 cross-check per ROADMAP Phase 238 note) — that deferral targets Phase 242 REG-02, not Phase 241.

### Claude's Discretion
- Plan task numbering and sub-task granularity within the single plan (D-03 provides 5-task skeleton; plan author may split further if task gas-budget is exceeded)
- Exact grep regex set for Gate B (D-07 provides surface universe; plan author selects regex patterns)
- Forward-Cite Discharge Ledger table column count (D-24 § 8 names the section; plan author selects columns, minimum: forward-cite source file:line, Phase 241 discharging row ID, discharge verdict, predicate used)
- Finding Candidates block ordering within § 10

### Folded Todos
None — todo backlog is empty at phase start (`gsd-tools list-todos` returned 0).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 241 scope anchors (MUST read)
- `.planning/ROADMAP.md` §"Phase 241: Exception Closure" — 4 Success Criteria + "TBD (expected 1-2 plans)" plan hint
- `.planning/REQUIREMENTS.md` lines 54–57 — EXC-01/02/03/04 definitions

### Phase 237 scope anchor (MUST read — READ-only per D-27)
- `audit/v30-CONSUMER-INVENTORY.md` — 146-row Consumer Index at HEAD `7ab515fe`, 22 EXCEPTION rows distributed across EXC-01 (2) / EXC-02 (8) / EXC-03 (4) / EXC-04 (8) per Phase 237 D-06 KI Cross-Ref Distribution

### Phase 238 output (MUST read — corroborating per D-12)
- `audit/v30-FREEZE-PROOF.md` — 124 SAFE + 22 EXCEPTION distribution (EXCEPTION row set-equal with Phase 241 Gate A target)

### Phase 239 output (MUST read — corroborating per D-12)
- `audit/v30-RNGLOCK-STATE-MACHINE.md` — RNG-01 rngLockedFlag state machine (corroborates EXC-02 reachability)
- `audit/v30-PERMISSIONLESS-SWEEP.md` — RNG-02 62-row permissionless sweep
- `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` — RNG-03 Asymmetry B phase-transition-gate origin proof (distinct from EXC-02 14-day gate)

### Phase 240 output (MUST read — corroborating per D-12 + 29 forward-cite discharge targets per D-11)
- `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` — 838 lines final consolidated Phase 240 deliverable; 17 `"See Phase 241 EXC-02"` + 12 `"See Phase 241 EXC-03"` forward-cite tokens to discharge
- `audit/v30-240-01-INV-DET.md` — GO-01 19-row gameover-VRF consumer inventory + GO-02 VRF-available-branch determinism proof
- `audit/v30-240-02-STATE-TIMING.md` — GO-03 state-freeze enumeration + GO-04 trigger-timing disproof
- `audit/v30-240-03-SCOPE.md` — GO-05 F-29-04 dual-disjointness `BOTH_DISJOINT`

### Accepted RNG exceptions (MUST read — SUBJECTS of Phase 241 re-verification, NOT warrants)
- `KNOWN-ISSUES.md` §"Non-VRF entropy for affiliate winner roll" — EXC-01 subject (2 rows)
- `KNOWN-ISSUES.md` §"Gameover prevrandao fallback" — EXC-02 subject (8 rows); constants `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` at `DegenerusGameAdvanceModule.sol:109`; trigger site `_gameOverEntropy` at `:1252`; fallback function `_getHistoricalRngFallback` at `:1301`
- `KNOWN-ISSUES.md` §"Gameover RNG substitution for mid-cycle write-buffer tickets" — EXC-03 subject (4 rows); buffer-swap primitives `_swapAndFreeze(purchaseLevel)` at `:292` + `_swapTicketSlot(purchaseLevel_)` at `:1082`; substitution site `_gameOverEntropy` at `:1222-1246`
- `KNOWN-ISSUES.md` §"EntropyLib XOR-shift PRNG for lootbox outcome rolls" — EXC-04 subject (8 rows); seed construction `keccak256(rngWord, player, day, amount)` in `EntropyLib.entropyStep()`

### Prior-milestone artifacts — CROSS-CITE ONLY (D-12), NOT RELIED UPON
- `audit/FINAL-FINDINGS-REPORT.md` — v29.0 / v25.0 prior findings (regression is Phase 242's job per D-19)
- Phase 235 Plan 04 F-29-04 commitment-window trace — EXC-03 corroborating prior-milestone artifact

### Phase decision lineage (MUST read — precedent inheritance)
- `.planning/phases/237-vrf-consumer-inventory-call-graph/237-CONTEXT.md` — Phase 237 decisions establishing Row-ID naming (D-06), fresh-eyes discipline (D-07), KI-exception handling (D-06 KI distribution)
- `.planning/phases/238-backward-forward-freeze-proofs/238-CONTEXT.md` — Phase 238 decisions establishing 22-EXCEPTION set, Named Gate taxonomy (D-13)
- `.planning/phases/239-rnglocked-invariant-permissionless-sweep/239-CONTEXT.md` — Phase 239 decisions establishing discharge-claim precedent (D-29 discharge of 238-03 SGD #1)
- `.planning/phases/240-gameover-jackpot-safety/240-CONTEXT.md` — Phase 240 decisions establishing forward-cite emission (D-19), no-discharge rationale (D-32), scope-guard-deferral routing (D-31)

### Milestone scope (MUST read)
- `.planning/PROJECT.md` §"v30.0 Milestone" — milestone baseline HEAD `7ab515fe`, write policy READ-only

### Project feedback rules (apply across all plans per user's durable instructions)
- `memory/feedback_contract_locations.md` — READ contracts from `contracts/` only
- `memory/feedback_no_contract_commits.md` — never commit `contracts/` or `test/` without explicit approval
- `memory/feedback_rng_backward_trace.md` — RNG audit methodology: backward trace every consumer
- `memory/feedback_rng_commitment_window.md` — verify player-controllable state between VRF request and fulfillment
- `memory/feedback_never_preapprove_contracts.md` — orchestrator must NEVER pre-approve contract changes

### In-scope contract tree (`contracts/`) — HEAD `7ab515fe` (per D-25)
- `contracts/DegenerusAffiliate.sol` — EXC-01 subject sites (`:568` no-referrer, `:585` weighted)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — EXC-02 subject sites (`:109` delay constant, `:1252` trigger, `:1301` fallback function); EXC-03 subject sites (`:292` swap, `:1082` lootbox swap, `:1222-1246` gameover substitution); gameover control flow
- `contracts/libraries/EntropyLib.sol` — EXC-04 subject site (`entropyStep()` keccak seed construction)
- Full `contracts/` tree — grep backstop surface universe (Gate B per D-07)

</canonical_refs>

<code_context>
## Existing Code Insights

### EXC-01 Surface (Affiliate Winner Roll — 2 proof subjects from Phase 237)
- `contracts/DegenerusAffiliate.sol:568` (INV-237-005) — `processAffiliatePayment` no-referrer branch; seed `keccak256(AFFILIATE_ROLL_TAG, currentDayIndex(), sender, storedCode)` 50/50 VAULT/DGNRS flip
- `contracts/DegenerusAffiliate.sol:585` (INV-237-006) — `processAffiliatePayment` referred branch; 75/20/5 weighted winner roll (affiliate / upline1 / upline2) from deterministic seed
- **Exploitability frame per D-05:** player times purchases to influence `currentDayIndex()` component → redirects affiliate credit between candidates. No protocol value extraction (KI-documented). Phase 241 re-verifies this exploit ceiling holds at HEAD — no new seed component, no new call site.

### EXC-02 Surface (Prevrandao Fallback — 8 proof subjects)
- `DegenerusGameAdvanceModule.sol:109` — `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` constant (predicate target)
- `DegenerusGameAdvanceModule.sol:1252` — `_gameOverEntropy` trigger site (single-call-site predicate target)
- `DegenerusGameAdvanceModule.sol:1301` — `_getHistoricalRngFallback` fallback function definition
- Reachability closure: Phase 239 RNG-01 rngLockedFlag state machine + Phase 240 GO-04 player-centric trigger-timing disproof cover gameover entry paths
- Grep target: all callers of `_getHistoricalRngFallback` in `contracts/` must resolve to exactly `_gameOverEntropy` at `:1252`

### EXC-03 Surface (F-29-04 Mid-Cycle Substitution — 4 proof subjects)
- `DegenerusGameAdvanceModule.sol:292` — `_swapAndFreeze(purchaseLevel)` daily RNG request trigger
- `DegenerusGameAdvanceModule.sol:1082` — `_swapTicketSlot(purchaseLevel_)` mid-day lootbox RNG request trigger
- `DegenerusGameAdvanceModule.sol:1222-1246` — `_gameOverEntropy` substitution site
- Tri-gate predicates per ROADMAP SC-3: terminal-state + no-player-reachable-timing + post-swap-write-buffer-only
- Corroborating: Phase 240 GO-05 dual-disjointness `BOTH_DISJOINT` (inventory-level + state-variable-level)

### EXC-04 Surface (EntropyLib Seed Derivation — 8 proof subjects)
- `contracts/libraries/EntropyLib.sol` — `entropyStep()` function definition; seed construction `keccak256(rngWord, player, day, amount)`
- Predicate: no new caller site bypasses keccak seed construction; `rngWord` parameter VRF-derived at every call site
- Call-site inventory: Phase 237 Consumer Index rows tagged `exception-xor-shift-seed`-adjacent (8 rows)

### Shared Cross-Phase Evidence
- Phase 237 `audit/v30-CONSUMER-INVENTORY.md` — 146-row index, 22 EXCEPTION distribution (Gate A target)
- Phase 238 `audit/v30-FREEZE-PROOF.md` — 22-EXCEPTION count set-equality check (Gate A cross-check)
- Phase 240 `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` — 29 forward-cite tokens (discharge ledger target per D-11)

### Integration Points
- Deliverable: `audit/v30-EXCEPTION-CLOSURE.md` (single new file; 237/238/240 consolidated pattern per D-22)
- Plan file: `.planning/phases/241-exception-closure/241-01-PLAN.md`
- SUMMARY file: `.planning/phases/241-exception-closure/241-01-SUMMARY.md`
- Phase 242 handoff: Finding Candidates appendix feeds FIND-01 intake; Forward-Cite Discharge Ledger closes Phase 240's 29 pending cross-phase forward-cites

</code_context>

<specifics>
## Specific Ideas — Single Plan, 5-Task Sequential Structure

### Plan 241-01-PLAN.md — Exception Closure (Single Consolidated Plan per D-01)

**Tasks (sequential, single wave per D-01):**

**Task 1 — EXC-01 ONLY-ness Table + Dual-Gate Closure (D-06/D-08/D-09):**
- Walk Phase 237 Consumer Index 146 rows; per-row seed-source verdict
- Build 22-row consolidated ONLY-ness table (2 EXC-01 + 8 EXC-02 + 4 EXC-03 + 8 EXC-04)
- Gate A: set-equality with Phase 238 22 EXCEPTION / 124 SAFE distribution
- Gate B: grep backstop over player-reachable non-VRF surfaces (D-07)
- Combined verdict `ONLY_NESS_HOLDS_AT_HEAD` iff both gates pass
- Emit Finding Candidates for any gate failure; route to scope-guard deferral per D-27

**Task 2 — EXC-02 Predicate Re-Verification (D-10):**
- Single-call-site predicate: grep all callers of `_getHistoricalRngFallback`; confirm sole caller `_gameOverEntropy` at `DegenerusGameAdvanceModule.sol:1252`
- 14-day gate predicate: confirm `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` at `:109`; confirm gate check guards every reachable path at HEAD
- Cross-cite Phase 239 RNG-01 rngLockedFlag + Phase 240 GO-02 EXC-02 forward-cite rows (corroborating per D-12)
- Discharge 17 Phase 240 EXC-02 forward-cite tokens via Forward-Cite Discharge Ledger (D-11)

**Task 3 — EXC-03 Tri-Gate Re-Verification (D-10):**
- Terminal-state predicate: substitution reachable only inside `_gameOverEntropy` control flow at `:1222-1246`
- No-player-reachable-timing predicate: cross-cite Phase 240 GO-04 `DISPROVEN_PLAYER_REACHABLE_VECTOR`; confirm gameover triggers (120-day liveness stall, pool deficit) unchanged at HEAD
- Buffer-scope predicate: confirm `_swapAndFreeze(:292)` + `_swapTicketSlot(:1082)` buffer primitives unchanged; cross-cite Phase 240 GO-05 `BOTH_DISJOINT` (corroborating)
- Discharge 12 Phase 240 EXC-03 forward-cite tokens via Forward-Cite Discharge Ledger (D-11)

**Task 4 — EXC-04 EntropyLib Seed Re-Verification (D-10):**
- Grep all callers of `EntropyLib.entropyStep()`; confirm every call site passes VRF-derived `rngWord`
- Confirm `keccak256(rngWord, player, day, amount)` seed construction intact at HEAD; no new entry point bypasses
- No forward-cite discharge needed (Phase 240 did not emit EXC-04 forward-cites — Phase 240 scope was gameover-VRF-available branch)

**Task 5 — Consolidation into `audit/v30-EXCEPTION-CLOSURE.md` (D-22/D-24):**
- Assemble 10-section consolidated file (D-24)
- Executive Summary + closure verdicts
- All 22 ONLY-ness rows + grep classification + 3 predicate re-verification tables + 29-row Forward-Cite Discharge Ledger + Prior-Artifact Cross-Cites + Finding Candidates + Attestation
- Commit as single atomic operation (D-22)

### Cross-plan invariants (apply to all 5 tasks)
- **HEAD anchor `7ab515fe` locked in frontmatter** (D-25)
- **READ-only contracts/test/** (D-26)
- **Phase 237/238/239/240 outputs READ-only** (D-27)
- **No F-30-NN emission** (D-20)
- **Tabular grep-friendly no mermaid** (D-23)
- **Row-ID prefix `EXC-241-NNN`** (D-23)
- **Closed-verdict taxonomy** (D-09 / D-10 extended)
- **≥3 re-verified-at-HEAD cross-cite instances** (D-13)
- **Finding Candidates appendix** (D-21)
- **Scope-guard deferral routing** (D-27)

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
None — todo backlog was empty at phase start.

### Ideas mentioned but out of scope
- **Fresh XOR-shift distribution analysis** — user explicitly said exploitability, not randomness quality (D-05). XOR-shift theoretical weakness is already KI-accepted; re-litigating distribution belongs in a separate cryptographic-review phase, not in v30 determinism audit.
- **Admin / validator / VRF-oracle-reachable non-VRF seed enumeration** — D-05 scopes Phase 241 to player-reachable surfaces. If a future phase wants any-actor coverage (matching Phase 240 D-11 player-centric → admin/validator narrative split), that belongs in a dedicated cross-actor-reachability phase.
- **Regression verdicts (PASS/REGRESSED/SUPERSEDED) against prior-milestone findings** — that's Phase 242 REG-01/02 per D-19. Phase 241 cross-cites prior artifacts as corroborating only.
- **Fresh F-30-NN finding ID emission** — Phase 241 surfaces Finding Candidates only (D-20). FIND-01 promotion to F-30-NN is Phase 242's job.
- **KNOWN-ISSUES.md edits** — KI promotions are Phase 242 FIND-03. Phase 241 does NOT touch `KNOWN-ISSUES.md` per D-26.

</deferred>

---

*Phase: 241-exception-closure*
*Context gathered: 2026-04-19*
