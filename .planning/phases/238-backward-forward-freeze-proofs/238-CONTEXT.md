# Phase 238: Backward & Forward Freeze Proofs (per consumer) — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning
**Mode:** Auto-decided via Phase 235 / Phase 237 precedents (user directive: "run all the parallel shit you can")

<domain>
## Phase Boundary

Per-consumer exhaustive freeze proof pass over the full v30.0 VRF-consumer universe locked by Phase 237 (`audit/v30-CONSUMER-INVENTORY.md`, 146 INV-237-NNN rows at HEAD `7ab515fe`). Six requirements:

- **BWD-01** — Per-consumer backward trace from consumption site to VRF request origin; every storage read on the consumption path maps to a write site classified `written-before-request` OR `unreachable-after-request`.
- **BWD-02** — Per-consumer enumeration of every storage variable read at consumption time; verdict `written-before-request` / `unreachable-after-request` / `EXCEPTION (KI-cross-ref)`. No `mutable-after-request` verdict without a KNOWN-ISSUES citation.
- **BWD-03** — Per-consumer adversarial closure: can a player / admin / validator / VRF oracle mutate any backward-input state between request and consumption? Exhaustive actor taxonomy, not sampled.
- **FWD-01** — Per-consumer forward enumeration of every consumption-site state read and its write path(s); the "what will be read" universe for that consumer.
- **FWD-02** — Per-consumer forward adversarial closure: can any actor mutate any consumption-site state between VRF request and consumption? Exhaustive per consumer.
- **FWD-03** — Per-consumer gating verification: the specific gating mechanism (`rngLocked` / lootbox index-advance / phase-transition gate / semantic path gate) actually blocks every forward mutation path identified in FWD-01/02. Gating must be demonstrated effective, never assumed.

Scope source is `audit/v30-CONSUMER-INVENTORY.md` (READ-only per Phase 237 D-16). Scope is the Consumer Index `ALL` row for each of BWD-01/02/03 + FWD-01/02/03 (146 rows, no sampling, no shortcuts). Scope is READ-only: no `contracts/` or `test/` writes. Finding-ID emission is deferred to Phase 242 (FIND-01/02/03); Phase 238 produces per-consumer verdicts + mutation-path tables + gating-effectiveness tables that become the finding-candidate pool.

Fresh-eyes mandate (v30.0 milestone-wide per ROADMAP + Phase 237 D-07): prior-milestone artifacts (v25.0 Phase 215, v29.0 Phase 235 Plans 03-04, v3.7 / v3.8) may be CROSS-CITED as corroborating evidence but MUST NOT be relied upon — every verdict re-derived at HEAD `7ab515fe`, and every cited prior verdict carries a `re-verified at HEAD 7ab515fe` note (Phase 235 D-04 pattern).

KNOWN-ISSUES exception rows (22 EXC proof subjects per 237 Consumer Index: EXC-01=2, EXC-02=8, EXC-03=4, EXC-04=8) ARE in Phase 238 BWD/FWD scope — verdict cell records `EXCEPTION (KI: <header>)` and the adversarial-closure columns record the accepted violation envelope. Their acceptance as design decisions is Phase 241's scope (re-litigation forbidden here); Phase 238 documents the freeze-proof posture consistent with the KI envelope.

Gameover-flow rows (19 rows per 237 Consumer Index: 7 `gameover-entropy` + 2 `exception-mid-cycle-substitution` + 8 `exception-prevrandao-fallback` + 4 F-29-04 overlap, minus duplicates) ARE in Phase 238 BWD/FWD scope on the same 146-row basis. Phase 240 layers GO-01..05 gameover-jackpot-specific proofs on top; Phase 238 owns the underlying per-consumer freeze.

</domain>

<decisions>
## Implementation Decisions

### Plan Split
- **D-01 (3 plans, Wave 1 + Wave 2 per Phase 237 precedent):** Matches ROADMAP's "expected 3-5 plans" floor and maximizes parallelism per user directive.
  - `238-01-PLAN.md` BWD-01/02/03 — per-consumer backward freeze proofs (all 146 rows) → `audit/v30-238-01-BWD.md`
  - `238-02-PLAN.md` FWD-01/02 — per-consumer forward enumeration + adversarial closure (all 146 rows) → `audit/v30-238-02-FWD.md`
  - `238-03-PLAN.md` FWD-03 + Consolidation — per-consumer gating verification (depends on 238-02 FWD-01/02 mutation-path tables) + assembly of final consolidated `audit/v30-FREEZE-PROOF.md` → `audit/v30-238-03-GATING.md` + final consolidated file
- **D-02 (wave topology — Wave 1: 238-01 + 238-02 parallel; Wave 2: 238-03):** 238-01 BWD and 238-02 FWD-01/02 share zero inputs (both consume the 146-row inventory independently) and run concurrently. 238-03 FWD-03 gating requires 238-02 FWD-01/02 mutation-path output to verify gating-effectiveness; runs after Wave 1 commits. Final consolidated `audit/v30-FREEZE-PROOF.md` is assembled in 238-03 per Phase 237 D-08 single-file precedent.
- **D-03 (no per-consumer-family split):** Considered family-split (daily 91 / mid-day-lootbox 19 / gap-backfill 3 / gameover-entropy 7 / other 26) but rejected: (a) requirement-split matches the Phase 235 D-01 strict-per-requirement precedent; (b) family-split would fragment BWD/FWD evidence across files and break the Consumer Index `ALL` mapping from 237-03; (c) 238-01 and 238-02 internally can further use shared-prefix chain deduplication (per 237-03's 6-chain pattern covering 130 of 146 rows) as a presentation optimization without splitting plans.

### Per-Consumer Evidence Shape
- **D-04 (BWD tabular format — Phase 235 D-07 pattern):** 238-01 deliverable table columns: `Row ID | Consumer | Consumption File:Line | Storage Reads On Consumption Path | Write-Site Classification (written-before-request / unreachable-after-request / EXCEPTION) | KI Cross-Ref | Backward-Trace Verdict (SAFE / EXCEPTION)`. One row per INV-237-NNN. Shared-prefix chains may group identical backward-trace body text via a reusable "Chain" sub-table cited by row, per 237-03 D-12 pattern.
- **D-05 (FWD tabular format — inverted Phase 235 D-08 pattern):** 238-02 deliverable table columns: `Row ID | Consumer | Consumption-Site Storage Reads | Write Paths To Each Read | Mutable-After-Request Actors | Actor-Class Closure (player / admin / validator / VRF oracle) | FWD-Verdict (SAFE / EXCEPTION)`. One row per INV-237-NNN. Same shared-prefix grouping allowed.
- **D-06 (FWD-03 gating table — new shape, derived from FWD-01/02):** 238-03 deliverable table columns: `Row ID | Forward Mutation Paths (from 238-02) | Named Gate | Gate Site File:Line | Mutation-Path Coverage (EVERY_PATH_BLOCKED / PARTIAL_COVERAGE / NO_GATE_NEEDED_ORTHOGONAL) | Effectiveness Proof`. NAMED_GATE taxonomy is closed to four values per ROADMAP + FWD-03 wording: `rngLocked` / `lootbox-index-advance` / `phase-transition-gate` / `semantic-path-gate`. Any row requiring a gate outside this set is a finding candidate for Phase 242.

### Actor Taxonomy (BWD-03 / FWD-02 Adversarial Closure)
- **D-07 (closed four-actor taxonomy, exhaustive):** Adversarial closure columns enumerate the four actor classes below; no actor left implicit.
  - **player** — any EOA with standard game access (purchase, claim, burn, boon, quest, admin-on-own-tokens). Covers direct calls, delegation, and MEV bundle inclusion.
  - **admin** — any admin role (multisig, deployer, governance, operator). Covers `setters`, `rescue*`, ownership transfers, and any `onlyAdmin`-gated path in `contracts/`.
  - **validator** — block proposer / miner. Covers transaction ordering, censorship, and short-range reorgs within the commitment window.
  - **VRF oracle** — Chainlink VRF coordinator. Can delay / withhold fulfillment but cannot bias the returned word (accepted Chainlink trust model). The 14-day prevrandao fallback (KI EXC-02) is the documented escape hatch for indefinite withholding.
- **D-08 (closure verdicts per actor):** Each Row × Actor cell records one of: `NO_REACHABLE_PATH` (actor cannot mutate) / `PATH_BLOCKED_BY_GATE` (actor path exists but gate blocks — name the gate from D-06) / `EXCEPTION (KI: <header>)` (accepted violation) / `CANDIDATE_FINDING` (actor path exists + gate absent or ineffective — route to Phase 242). `CANDIDATE_FINDING` triggers a Finding Candidate block with file:line + proposed severity.

### Evidence Reuse (cross-cite + fresh re-prove)
- **D-09 (fresh re-prove + cross-cite prior — Phase 235 D-03 pattern):** Every verdict re-derived at HEAD `7ab515fe`. CROSS-CITES (does not reuse) prior-milestone verdicts as corroborating evidence:
  - v29.0 Phase 235 Plan 03 `235-03-BWD-TRACE.md` + Plan 04 `235-04-COMMITMENT-WINDOW.md` — covers the 12 v29.0-delta rows from the 237 reconciliation table (new-since-prior-audit verdict).
  - v25.0 Phase 215 `215-02-BACKWARD-TRACE.md` + `215-03-COMMITMENT-WINDOW.md` — covers the 45 confirmed-fresh-matches-prior rows from 237 reconciliation.
  - v3.7 Phases 63-67 (VRF path test coverage, Foundry invariants + Halmos) + v3.8 Phases 68-72 (VRF commitment window) — corroborating structural baseline.
  - v29.0 Phase 235 Plan 05 `235-05-TRNX-01.md` — load-bearing cross-cite for FWD-03 gating verification of the `rngLocked` state machine (read buffer / write buffer invariants per Phase 235 D-11/D-12).
- **D-10 (re-verify-at-HEAD note on every cross-cite — Phase 235 D-04 pattern):** Every prior-phase cite carries `re-verified at HEAD 7ab515fe` with a one-line structural-equivalence statement. HEAD has not moved relative to v29.0 `1646d5af` for `contracts/` tree (all post-v29 commits docs-only per PROJECT.md), so re-verification is mechanical; the note is still mandatory to guard against silent contract-tree divergence.

### KI-Exception & Gameover Handling (scope inclusion, no re-litigation)
- **D-11 (KI-exception rows IN scope with EXCEPTION verdict — Phase 237 D-06 pattern):** The 22 EXC proof-subject rows (EXC-01 2 / EXC-02 8 / EXC-03 4 / EXC-04 8) are audited in 238-01 BWD and 238-02 FWD with verdict `EXCEPTION (KI: <header>)` and KI-cross-ref filled. Their determinism-invariant violation is accepted per KNOWN-ISSUES.md; Phase 238 does NOT re-litigate acceptance (Phase 241 EXC-01..04 closes that scope). Phase 238 documents the freeze-proof posture consistent with the KI envelope — e.g., the 8 prevrandao-fallback rows carry FWD-verdict `EXCEPTION (KI: Gameover prevrandao fallback)` with the 14-day delay as the effective gate cited from `DegenerusGameAdvanceModule.sol:109` + `:1252`.
- **D-12 (gameover-flow rows IN scope, Phase 240 overlay declared):** The 19 gameover-flow rows (7 `gameover-entropy` + 2 mid-cycle-substitution + 8 prevrandao-fallback + 4 F-29-04 overlap minus duplicates, per 237 Plan 02 INV-02 tally) are audited on the same 146-row basis. Phase 240 GO-01..05 layers gameover-jackpot-specific proofs (consumer inventory, determinism proof, state-freeze enumeration, trigger-timing disproof, F-29-04 scope containment) on top; Phase 238 owns the underlying per-consumer freeze proof. 238-01 / 238-02 / 238-03 verdicts for gameover rows become direct inputs to Phase 240 GO-02/GO-03.

### Gating Taxonomy (FWD-03)
- **D-13 (closed four-gate taxonomy per ROADMAP + REQUIREMENTS.md FWD-03):** NAMED_GATE cell in 238-03 table is one of:
  - **`rngLocked`** — global `rngLockedFlag` SSTORE gate; set at VRF request, cleared at fulfillment (Phase 239 RNG-01 re-proves the state machine from first principles).
  - **`lootbox-index-advance`** — stale-index fallback: writes to `lootboxRngWordByIndex[advancedIndex]` at RNG-request time isolate the consumption-time read to `lootboxRngWordByIndex[consumerIndex]` via the index-advance asymmetry (Phase 239 RNG-03 re-justifies from first principles; 13 index-advance rows per 237 D-06 distribution).
  - **`phase-transition-gate`** — `phaseTransitionActive` branch gate at `DegenerusGameAdvanceModule.sol:283` (Phase 235 D-13 Path 4 re-verified; admits only `advanceGame`-origin writes and creates no player-reachable mutation path to RNG-consumer state).
  - **`semantic-path-gate`** — function-specific early-return or revert that makes the consumption-site unreachable after request; the `rawFulfillRandomWords` L1698 zero-guard + `rngGate` L291 sentinel-1 break + pre-finalize gate (cross-cited from v29.0 Phase 232.1) are archetypal examples.
- **D-14 (gate-taxonomy escape rule):** Any row whose FWD-02 mutation paths are NOT covered by one of the four named gates is a `CANDIDATE_FINDING` and gets a Finding Candidate block with file:line + proposed severity for Phase 242 FIND-01 routing. The taxonomy is closed per ROADMAP's FWD-03 wording; expanding it would be a first-principles v30.0 discovery.

### Finding-ID Emission
- **D-15 (no F-30-NN emission — Phase 237 D-15 / Phase 235 D-14 pattern):** Phase 238 does NOT emit `F-30-NN` finding IDs. Produces per-consumer verdicts + mutation-path tables + gating-effectiveness tables + Finding Candidate blocks that become the pool for Phase 242 FIND-01/02/03. Every verdict cites commit SHA + file:line so Phase 242 can anchor without re-discovery.

### Output Shape
- **D-16 (single consolidated `audit/v30-FREEZE-PROOF.md` + three plan-step files):** Follows Phase 237 D-08 single-consolidated-deliverable pattern.
  - `audit/v30-238-01-BWD.md` — 238-01 plan output (BWD-01/02/03 per-consumer backward-freeze tables)
  - `audit/v30-238-02-FWD.md` — 238-02 plan output (FWD-01/02 per-consumer forward enumeration + adversarial closure tables)
  - `audit/v30-238-03-GATING.md` — 238-03 plan output (FWD-03 per-consumer gating verification tables)
  - `audit/v30-FREEZE-PROOF.md` — final consolidated deliverable assembled in 238-03, merging the three plan outputs row-by-row + Consumer Index mapping BWD/FWD/gating verdicts back to every 237 Row ID. Grep-friendly, tabular, no mermaid (Phase 237 D-09 convention).
- **D-17 (Finding Candidates appendix per-plan, merged in consolidated):** Each plan's deliverable carries a "Finding Candidates" subsection listing rows with verdict `EXCEPTION` (informational — KI-accepted, not new finding) vs verdict `CANDIDATE_FINDING` (first-principles fresh-eyes finding). Consolidated `audit/v30-FREEZE-PROOF.md` merges all three plans' Finding Candidates into a single appendix for Phase 242 FIND-01 intake.

### Scope-Guard Handoff
- **D-18 (Phase 237 inventory READ-only — scope-guard deferral rule per Phase 237 D-16):** If any 238 plan finds a consumer not in the 146-row inventory, it records a scope-guard deferral in its own plan SUMMARY (file:line + path-family proposal + KI cross-ref if applicable). Phase 237 output is NOT re-edited in place. Inventory gaps become Phase 242 FIND-01 finding candidates.
- **D-19 (HEAD anchor `7ab515fe` locked in every plan's frontmatter — Phase 237 D-17 pattern):** Contract tree unchanged since v29.0 `1646d5af`; all post-v29 commits are docs-only. Any contract change after `7ab515fe` resets the baseline and requires a scope addendum. Frontmatter freeze is mandatory in 238-01, 238-02, 238-03, and each plan SUMMARY.
- **D-20 (READ-only scope, no `contracts/` or `test/` writes — Phase 237 D-18 pattern):** Carries forward v28/v29 cross-repo READ-only pattern + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Writes confined to `.planning/` and `audit/` (creating `v30-238-*` files + updating `audit/v30-FREEZE-PROOF.md`). `KNOWN-ISSUES.md` is not touched in Phase 238 — KI promotions are Phase 242 FIND-03 only.

### Claude's Discretion
- Shared-prefix chain grouping threshold — planner decides when to hive off a reused backward-trace body into a sub-table vs inline (237-03 used a ~6-chain / 130-row dedup heuristic; planner may tune).
- Row ordering within 238-01/02/03 deliverables — planner picks most readable (path-family-sorted vs Row-ID-sorted vs consumption-file-sorted) as long as every row appears exactly once.
- Whether 238-03 adds a small "gate coverage heatmap" table (gate × family) as a readability aid at the top of the GATING file — optional, not required.
- Whether Finding Candidates severities are pre-classified (INFO / LOW / MED / HIGH) in 238 or left as `SEVERITY: TBD-242` — Phase 237 used INFO for all surfaced candidates; planner matches that precedent unless a row is unambiguously higher.
- Whether 238-03 cross-cites Phase 239's RNG state-machine proof explicitly (Phase 239 may execute in parallel with Phase 238 per ROADMAP; if 239 commits first, 238-03 can cite, otherwise 238-03 states the `rngLocked` gate's correctness as an audit assumption pending Phase 239 RNG-01 re-proof).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 237 scope anchor (MUST read — READ-only per D-18)
- `audit/v30-CONSUMER-INVENTORY.md` — 146 INV-237-NNN rows + 146 per-consumer call graphs + Consumer Index
  - §"Universe List" — BWD/FWD scope = `ALL` (all 146 rows)
  - §"Per-Consumer Call Graphs" — input to every backward-trace (consumption site back through storage touchpoints to VRF request origin)
  - §"Consumer Index" — INV/BWD/FWD = `ALL`; EXC-01..04 = 22 proof subjects; GO-01..04 = 19 gameover-flow rows; F-29-04 overlap = 4 rows
  - §"Classification Summary" — path-family distribution (daily 91 / mid-day-lootbox 19 / gap-backfill 3 / gameover-entropy 7 / other 26)
  - §"KI Cross-Ref Summary" — every exception row's KI entry for D-11 verdict population

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` §"BWD — Backward Freeze Proof (per consumer)" (BWD-01/02/03) + §"FWD — Forward Freeze Proof (per consumer)" (FWD-01/02/03) — exact requirement wording, locks the BWD/FWD verdict taxonomy
- `.planning/ROADMAP.md` Phase 238 block — 5 Success Criteria + "Depends on: Phase 237" + "expected 3-5 plans — may split by consumer family"
- `.planning/PROJECT.md` Current Milestone v30.0 — write-policy statement + accepted RNG exceptions list

### Accepted RNG exceptions (MUST read — drive D-11 EXCEPTION verdicts)
- `KNOWN-ISSUES.md` — 5 accepted entries referenced in inventory KI Cross-Ref column:
  - "Non-VRF entropy for affiliate winner roll" (2 rows — EXC-01)
  - "Gameover prevrandao fallback" `_getHistoricalRngFallback`, `DegenerusGameAdvanceModule.sol:1301`, gating `:1252` + delay `:109` (8 rows — EXC-02)
  - "Gameover RNG substitution for mid-cycle write-buffer tickets" F-29-04; `_swapAndFreeze` `:292`; `_swapTicketSlot` `:1082`; `_gameOverEntropy` `:1222-1246` (4 rows — EXC-03)
  - "EntropyLib XOR-shift PRNG for lootbox outcome rolls" `EntropyLib.entropyStep()` (8 rows — EXC-04)
  - "Lootbox RNG uses index advance isolation instead of rngLockedFlag" (re-justified Phase 239 RNG-03; informs D-13 `lootbox-index-advance` gate)

### Prior-milestone artifacts — CROSS-CITE ONLY (D-09), NOT RELIED UPON
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-03-BWD-TRACE.md` — per-consumer backward-trace template (RNG-01 scope); cross-cite source for the 12 new-since-prior-audit rows
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-04-COMMITMENT-WINDOW.md` — per-consumer commitment-window enumeration template (RNG-02 scope); cross-cite source paired with 235-03
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-TRNX-01.md` — `rngLocked` state-machine re-proof; cross-cite source for FWD-03 gating of the `rngLocked` named gate (D-13)
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/215-02-BACKWARD-TRACE.md` — direct per-consumer backward-trace table format (Phase 235 D-07 template); cross-cite source for the 45 confirmed-fresh-matches-prior rows
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/215-03-COMMITMENT-WINDOW.md` — direct per-consumer commitment-window enumeration format (Phase 235 D-08 template); cross-cite source paired with 215-02
- `.planning/milestones/v29.0-phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-PFTB-AUDIT.md` — non-zero-entropy guarantee at 4 reachable `_processFutureTicketBatch` call sites; cross-cite source for FWD-03 `semantic-path-gate` archetype (pre-finalize + queue-length + do-while gates)
- v3.7 Phases 63-67 (VRF path test coverage, Foundry invariants + Halmos) + v3.8 Phases 68-72 (VRF commitment window) — corroborating structural baseline (READ via `.planning/milestones/v3.7-phases/` + `v3.8-phases/` index files; cite by phase number + summary file for re-verification at HEAD)

### Phase 237 decision lineage (MUST read — scope-guard + taxonomy)
- `.planning/phases/237-vrf-consumer-inventory-call-graph/237-CONTEXT.md` — D-06 KI-exceptions-in-inventory + D-10 Consumer Index + D-11 call-graph depth + D-16 scope-guard + D-17 HEAD anchor + D-18 READ-only; Phase 238 inherits every structural invariant
- `.planning/phases/237-vrf-consumer-inventory-call-graph/237-03-SUMMARY.md` — 6 shared-prefix chains (PREFIX-DAILY / PREFIX-MIDDAY / PREFIX-GAMEOVER / PREFIX-PREVRANDAO / PREFIX-AFFILIATE / PREFIX-GAP) covering 130 rows; informs D-04/D-05 shared-prefix-chain deduplication presentation
- `.planning/phases/237-vrf-consumer-inventory-call-graph/237-02-SUMMARY.md` — 22 KI Cross-Ref proof subjects distribution (EXC-01=2, EXC-02=8, EXC-03=4, EXC-04=8) and 19 gameover-flow effective scope across 3 path-family labels; informs D-11 + D-12

### Project feedback rules (apply across all plans per user's durable instructions)
- `memory/feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer; verify word was unknown at input commitment time (BWD-01/02/03 methodology anchor)
- `memory/feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment (FWD-01/02 methodology anchor, also covers BWD-03)
- `memory/feedback_no_contract_commits.md` — READ-only scope enforcement, no `contracts/` or `test/` writes without explicit approval (D-20)
- `memory/feedback_never_preapprove_contracts.md` — orchestrator never tells subagents contract changes are pre-approved
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source; stale copies elsewhere are ignored
- `memory/feedback_skip_research_test_phases.md` — skip research for mechanical/obvious phases (Phase 238 is audit-execution, not research-heavy; plan directly from this CONTEXT.md)

### In-scope contract tree (`contracts/`) — HEAD `7ab515fe` (per D-19)
Same surface as Phase 237 D-18 (no re-enumeration): 17 top-level contracts + 11 modules + 5 libraries. Full list in Phase 237 CONTEXT.md `<canonical_refs>` → In-scope contract tree.

</canonical_refs>

<code_context>
## Existing Code Insights

### BWD-01/02/03 Surface (per 237 Consumer Index `ALL` = 146 rows)
- 146 consumers enumerated in `audit/v30-CONSUMER-INVENTORY.md` Universe List with consumption File:Line + VRF request origin File:Line + call-graph reference per row.
- 6 shared-prefix chains (PREFIX-DAILY / PREFIX-MIDDAY / PREFIX-GAMEOVER / PREFIX-PREVRANDAO / PREFIX-AFFILIATE / PREFIX-GAP) absorb 130 of 146 rows — same backward-trace body up to the bifurcation point, then 16 bespoke tails.
- Storage surface touched: `prizePoolsPacked`, `claimableWinnings`, `decimatorPool`, `rngLocked`, `lootboxRngWordByIndex`, `earlybirdDgnrsPoolStart`, `futureTicketsByDay`, `phaseTransitionActive`, `bonusTraitsPacked`, `traitAlignment`, plus library read-side state in `EntropyLib`, `JackpotBucketLib`, `BitPackingLib`. Enumerated per-consumer in 237 call graphs — 238-01 BWD-02 verdict cell per read.
- Storage-write sites have already been catalogued by Phase 230-01-DELTA-MAP §1 + STORAGE-WRITE-MAP.md (repo-root audit artifact); 238-01 cross-cites both as structural corroboration for `written-before-request` verdicts.

### FWD-01/02 Surface
- FWD-01 = mirror of BWD-02 — same storage-read set at consumption time; 238-02 table is the "forward view" of the same universe.
- FWD-02 adversarial-closure is the per-consumer-mutation-path universe: for every consumption-time read, what is the minimum-gas reachable write path from each actor class between VRF request and consumption?
- Access-control scaffolding for actor taxonomy is captured in `audit/ACCESS-CONTROL-MATRIX.md` (repo-root audit artifact); 238-02 cross-cites for the `admin` actor class and the `onlyAdmin` gate enumeration.
- 237 D-11 call graphs already stop at consumption site (delegatecalls traced to target; library calls named with signature). 238-02 extends by enumerating SSTOREs that WRITE to those same storage slots from OUTSIDE the call graph (the "forward mutation path" universe).

### FWD-03 Gating Surface (per D-13 named-gate taxonomy)
- **`rngLocked`** — `rngLocked` storage slot in `DegenerusGameStorage.sol` + set/clear sites enumerated by Phase 235 Plan 05 TRNX-01 4-path walk; Phase 239 RNG-01 re-proves the state machine airtight from first principles.
- **`lootbox-index-advance`** — `lootboxRngWordByIndex` mapping SSTORE site at RNG-request time (index increment); consumption-time read uses `consumerIndex` which was frozen at a prior index value. Phase 239 RNG-03 re-justifies the asymmetry; 237 flagged 13 index-advance rows.
- **`phase-transition-gate`** — `phaseTransitionActive` branch at `DegenerusGameAdvanceModule.sol:283`; Phase 235 D-13 Path 4 proved admits only `advanceGame`-origin writes.
- **`semantic-path-gate`** — `rawFulfillRandomWords` L1698 zero-guard + `rngGate` L291 sentinel-1 break + `_processFutureTicketBatch` pre-finalize / queue-length / do-while gates from 232.1 fix series; 14-day `GAMEOVER_RNG_FALLBACK_DELAY` gate at `:109`/`:1252` for prevrandao-fallback rows (EXC-02 KI).

### Shared Cross-Phase Evidence
- Phase 237 Plan 03 per-consumer call-graphs — direct input to 238-01 BWD-01 (every backward-trace traverses the same path); shared-prefix chain deduplication preserves auditability while keeping table size manageable.
- Phase 232.1 Plan 02 forge invariant tests (8/8 PASS at HEAD) — corroborate structural correctness of the drain-before-swap + no-zero-entropy invariants underlying the `semantic-path-gate` D-13 values; cross-cited by 238-03 FWD-03.
- Phase 230 Consumer Index CONS-01 / RNG-01 / RNG-02 / TRNX-01 row mapping — feeds 238 row citations for the v29.0-delta overlap (12 rows per 237 reconciliation).
- STORAGE-WRITE-MAP.md (repo-root) + ACCESS-CONTROL-MATRIX.md (repo-root) — structural evidence for BWD-02 `written-before-request` / `unreachable-after-request` classifications + FWD-02 actor-class enumeration.

### Plan File Structure (per D-01 / D-16)
- `audit/v30-238-01-BWD.md` — 146-row backward-freeze table (D-04 shape) + Finding Candidates appendix (D-17)
- `audit/v30-238-02-FWD.md` — 146-row forward-enumeration + adversarial-closure table (D-05 shape) + Finding Candidates appendix
- `audit/v30-238-03-GATING.md` — 146-row gating-effectiveness table (D-06 shape) + (optional) gate × family coverage heatmap + Finding Candidates appendix
- `audit/v30-FREEZE-PROOF.md` — final consolidated deliverable (assembled in 238-03) merging the three plan files row-by-row; grep-friendly; Consumer Index maps BWD/FWD/gating verdicts back to every INV-237-NNN

</code_context>

<specifics>
## Specific Ideas — 3-Plan Shape, 2 Waves

Per D-01 + D-02, three plans, wave-ordered:

### Wave 1 (parallel)

#### Plan 238-01-PLAN.md — BWD-01/02/03 Per-Consumer Backward Freeze
- **Anchor citation:** `audit/v30-CONSUMER-INVENTORY.md` §"Per-Consumer Call Graphs" + §"Consumer Index" BWD-01/02/03 `ALL` rows
- **Deliverable:** `audit/v30-238-01-BWD.md` with 146-row backward-trace table per D-04 + Finding Candidates appendix per D-17
- **Cross-cites (re-verified at HEAD per D-10):** `235-03-BWD-TRACE.md` (12 v29.0-delta rows), `215-02-BACKWARD-TRACE.md` (45 confirmed-fresh-matches-prior rows), STORAGE-WRITE-MAP.md, Phase 230-01-DELTA-MAP §1
- **Actor closure (D-07/D-08):** BWD-03 adversarial-closure columns enumerate player / admin / validator / VRF oracle with verdict per cell
- **KI handling (D-11):** 22 EXC rows carry `EXCEPTION (KI: <header>)` verdict; 19 gameover-flow rows audited on same basis per D-12

#### Plan 238-02-PLAN.md — FWD-01/02 Per-Consumer Forward Enumeration + Adversarial Closure
- **Anchor citation:** `audit/v30-CONSUMER-INVENTORY.md` §"Per-Consumer Call Graphs" + §"Consumer Index" FWD-01/02 `ALL` rows
- **Deliverable:** `audit/v30-238-02-FWD.md` with 146-row forward-enumeration + adversarial-closure table per D-05 + Finding Candidates appendix
- **Cross-cites (re-verified at HEAD per D-10):** `235-04-COMMITMENT-WINDOW.md` (12 v29.0-delta rows), `215-03-COMMITMENT-WINDOW.md` (45 confirmed-fresh-matches-prior rows), ACCESS-CONTROL-MATRIX.md, `232.1-03-PFTB-AUDIT.md` (non-zero-entropy corroboration)
- **Actor closure (D-07/D-08):** FWD-02 adversarial-closure columns mirror 238-01 actor taxonomy
- **Output consumed by 238-03:** the "Mutable-After-Request Actors" + "Actor-Class Closure" columns become FWD-03 Forward Mutation Paths input

### Wave 2 (after Wave 1 commits)

#### Plan 238-03-PLAN.md — FWD-03 Gating Verification + Consolidation
- **Anchor citation:** `audit/v30-238-02-FWD.md` Forward Mutation Paths columns + `audit/v30-CONSUMER-INVENTORY.md` §"Per-Consumer Call Graphs" (gate site citations)
- **Deliverable (step 1):** `audit/v30-238-03-GATING.md` with 146-row gating-effectiveness table per D-06, using the closed 4-gate taxonomy of D-13, escape rule of D-14 for `CANDIDATE_FINDING` routing, + (optional) gate × family heatmap + Finding Candidates appendix
- **Deliverable (step 2):** `audit/v30-FREEZE-PROOF.md` final consolidated — merges 238-01 + 238-02 + 238-03 plan files row-by-row; grep-friendly; Consumer Index at end maps every BWD/FWD/gating verdict back to every INV-237-NNN + maps Phase 238 outputs to the 237 D-10 Consumer Index requirements (BWD-01/02/03 + FWD-01/02/03 cells populated for every row)
- **Cross-cites (re-verified at HEAD per D-10):** `235-05-TRNX-01.md` (rngLocked gate state machine), Phase 239 RNG-01/03 re-proof if available at commit time (otherwise state as audit assumption pending Phase 239 commit per Claude's Discretion in D-13), `232.1-03-PFTB-AUDIT.md` (semantic-path-gate archetype)
- **Finding Candidates merge:** consolidates 238-01 + 238-02 + 238-03 candidate pools into a single Phase 242 FIND-01 intake

### Cross-plan invariants (apply to all three)
- HEAD `7ab515fe` frontmatter lock per D-19
- READ-only scope per D-20
- No F-30-NN emission per D-15
- Scope-guard deferral on any out-of-inventory consumer per D-18
- Shared-prefix chain dedup per D-04/D-05 presentation

</specifics>

<deferred>
## Deferred Ideas

- **Phase 239 `rngLocked` state machine re-proof** — gates cited by FWD-03 (D-13 `rngLocked`) assume the state machine is airtight. Phase 239 RNG-01 re-proves from first principles. If Phase 239 commits before Phase 238 completes, 238-03 CROSS-CITES RNG-01 verdict per D-10; otherwise 238-03 states the `rngLocked` correctness as an audit assumption and marks for Phase 242 consolidation cross-check. No re-proof in Phase 238.
- **Phase 239 `lootbox-index-advance` asymmetry re-justification** — same as above; FWD-03 gate citations for the 13 index-advance rows assume asymmetry correctness pending Phase 239 RNG-03 re-proof.
- **Phase 240 gameover-jackpot-specific proofs (GO-01..05)** — Phase 238 owns the underlying per-consumer freeze for gameover-flow rows; Phase 240 adds GO-specific overlay. No gameover-specific jackpot-input determinism proof in Phase 238 (that's GO-03).
- **Phase 241 KI-exception acceptance re-verification (EXC-01..04)** — Phase 238 records `EXCEPTION (KI: <header>)` verdicts for the 22 EXC rows without re-litigating acceptance. Phase 241 closes that scope with first-principles confirmation that the 4 KI entries are the only violations.
- **Phase 242 FIND-01/02/03 consolidation + F-30-NN ID assignment** — Phase 238 produces candidate pool only per D-15. Consolidation into `audit/FINDINGS-v30.0.md` with severity classification + regression appendix is Phase 242's scope.
- **Automated invariant runner against BWD/FWD tables** — Foundry/Halmos-queryable encoding of the 146-row freeze-proof table. Out of v30.0 scope (READ-only, no test writes per D-20). Future-milestone candidate.
- **Row-count divergence investigation** — if Phase 238 surfaces evidence that a "shared-prefix chain" is not actually shared (e.g., a PREFIX-DAILY row has a divergent backward-trace tail not caught by 237-03), the finding is routed to Phase 242 FIND-01 without re-editing 237 output per D-18.
- **Gate-taxonomy expansion** — if FWD-03 finds a row requires a gate outside the 4-value D-13 taxonomy, it is a `CANDIDATE_FINDING` per D-14, not a taxonomy change in Phase 238. Taxonomy expansion would be a first-principles discovery routed to Phase 242.
- **Off-chain consumer drift** — indexer / API / subgraph consumers of VRF-derived state are out of scope per v30.0 focus on `contracts/` determinism. Any finding that implies off-chain divergence is flagged for Phase 242 FIND-02 regression appendix routing.

</deferred>

---

*Phase: 238-backward-forward-freeze-proofs*
*Context gathered: 2026-04-19*
