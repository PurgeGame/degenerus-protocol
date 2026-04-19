# Phase 239: rngLocked Invariant & Permissionless Sweep — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning
**Mode:** Auto-decided via Phase 235 / Phase 237 / Phase 238 precedents (`--auto`)

<domain>
## Phase Boundary

Global-invariant + whole-tree sweep pass that (a) proves the `rngLockedFlag` set/clear state machine airtight across every set site, every clear site, and every early-return / revert path in between; (b) classifies every permissionless function in `contracts/` against the RNG-consumer state space with one of three closed verdicts; (c) re-justifies from first principles the two documented asymmetries (lootbox RNG index-advance, `phaseTransitionActive` exemption). Fresh-eyes at HEAD `7ab515fe` — prior-milestone artifacts (v25.0, v29.0 Phase 235 Plan 05, v3.7, v3.8) may be CROSS-CITED but MUST NOT be relied upon.

Three requirements:
- **RNG-01** — `rngLockedFlag` state machine airtight: every set site, every clear site, every early-return / revert path in between enumerated; no reachable path produces set-without-clear or clear-without-matching-set.
- **RNG-02** — Permissionless sweep: every permissionless function in `contracts/` classified as one of `respects-rngLocked` / `respects-equivalent-isolation` / `proven-orthogonal`. No permissionless function may touch RNG-consumer input state or consumption-time state without falling into one of these three classes.
- **RNG-03** — Two asymmetries re-justified from first principles: (a) lootbox RNG index-advance isolation proven equivalent to flag-based isolation; (b) `phaseTransitionActive` exemption proven to admit only `advanceGame`-origin writes and to not create any player-reachable mutation path to RNG-consumer state.

Three dedicated deliverables matching ROADMAP success criteria 1-3 exactly:
- `audit/v30-RNGLOCK-STATE-MACHINE.md` (RNG-01)
- `audit/v30-PERMISSIONLESS-SWEEP.md` (RNG-02)
- `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` (RNG-03)

Scope is READ-only: no `contracts/` or `test/` writes. Finding-ID emission is deferred to Phase 242 (FIND-01/02/03); Phase 239 produces set/clear tables + path enumeration + permissionless classification table + asymmetry proofs + Finding Candidate blocks that become the pool for Phase 242 FIND-01 intake.

Discharges downstream audit assumptions from Phase 238 D-13: 238-03 FWD-03 gating cited `rngLocked` gate correctness as an audit assumption pending RNG-01, and `lootbox-index-advance` asymmetry correctness as pending RNG-03. Phase 239 is the load-bearing re-proof for both; 238's Scope-Guard Deferral #1 is closed by Phase 239 commits (Phase 242 cross-checks the discharge).

Phase 239 is parallel to Phases 238/240/241 per ROADMAP execution order — each has its own scope lane (238 = per-consumer freeze, 239 = global invariant, 240 = gameover branch, 241 = exception closure). All four share Phase 237's `audit/v30-CONSUMER-INVENTORY.md` as the scope anchor for any RNG-consumer state-space reference.

KNOWN-ISSUES exceptions (4 accepted entries) frame the asymmetry re-justification but do NOT serve as its basis: the lootbox index-advance KI is the subject of RNG-03(a) proof, not its warrant; the prevrandao fallback KI is informational context for state-machine path enumeration, not a re-justification target for Phase 239 (Phase 241 EXC-02 owns that re-verification). F-29-04 mid-cycle substitution is out-of-band for RNG-01 (rngLockedFlag is not the gate there — EXC-03 / Phase 241).

</domain>

<decisions>
## Implementation Decisions

### Plan Split
- **D-01 (3 plans, strict-per-requirement):** Matches Phase 235 D-01 + Phase 237 D-13 + Phase 238 D-01 precedents (one plan per requirement). Matches ROADMAP "expected 2-3 plans" at the upper end. Clean mapping of plan → deliverable → requirement enables independent verification and parallel execution.
  - `239-01-PLAN.md` RNG-01 — `rngLockedFlag` state machine airtight proof → `audit/v30-RNGLOCK-STATE-MACHINE.md`
  - `239-02-PLAN.md` RNG-02 — permissionless sweep with 3-class classification → `audit/v30-PERMISSIONLESS-SWEEP.md`
  - `239-03-PLAN.md` RNG-03 — two asymmetries re-justified from first principles → `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md`
- **D-02 (wave topology — single wave, all 3 parallel):** Unlike Phase 238 where FWD-03 gating depended on FWD-01/02 mutation-path output, Phase 239's three plans share zero inputs at HEAD. RNG-01 enumerates set/clear sites from the contract tree directly; RNG-02 classifies permissionless functions against the RNG-consumer state space (input is 237 inventory, not RNG-01 output); RNG-03 re-justifies two asymmetries from first principles (lootbox index-advance is a standalone equivalence proof; `phaseTransitionActive` is a standalone origin-proof). All three commit independently in Wave 1. Maximizes parallelism per user directive precedent ("run all the parallel shit you can" — 238-CONTEXT.md).
- **D-03 (no consolidated 4th file — 3 deliverables is the canonical set):** ROADMAP success criteria 1-3 list three specific files and the complete sentence for each. Unlike Phase 238 (which had a 4th consolidated `v30-FREEZE-PROOF.md` per D-16), Phase 239's three files stand alone — each owns a distinct invariant/proof. Cross-file references (e.g., RNG-03 cites the set/clear count from RNG-01) are inline citations, not a merged deliverable.

### RNG-01 Evidence Shape (State Machine)
- **D-04 (set-site + clear-site enumeration tables + path enumeration — 235 D-07 pattern extended):** `v30-RNGLOCK-STATE-MACHINE.md` structure:
  - **Set-Site Table** — columns: `Site ID | File:Line | Function | Trigger Context | Companion Clear Path(s) | Verdict`. One row per `rngLockedFlag = true` SSTORE. Verdict in {`AIRTIGHT_SET_CLEAR_SYMMETRY`, `CANDIDATE_FINDING`}.
  - **Clear-Site Table** — columns: `Site ID | File:Line | Function | Trigger Context | Companion Set Path(s) | Verdict`. One row per `rngLockedFlag = false` SSTORE. Same verdict taxonomy.
  - **Path Enumeration Table** — columns: `Path ID | Set-Site Ref | Entry Condition | Early-Return Points | Revert Points | Clear-Site Ref | Verdict`. Enumerates every reachable execution path from each set site through every early-return / revert branch to a matching clear site. Verdict in {`SET_CLEARS_ON_ALL_PATHS`, `CLEAR_WITHOUT_SET_UNREACHABLE`, `CANDIDATE_FINDING`}.
  - **Invariant Proof Section** — closed-form argument: ∀ reachable path P from set site S, P terminates at a clear site C (matched); ∀ reachable path Q to clear site C, Q originates at a matched set site S (matched).
- **D-05 (airtightness verdict taxonomy — closed, no narrative-only verdicts):** Every RNG-01 row ends in exactly one of {`AIRTIGHT` / `CANDIDATE_FINDING`}. No hedged, pending, or conditional verdicts. If a path cannot be proven airtight, it is a finding candidate for Phase 242 — not a narrative deferral.
- **D-06 (revert-safety of `rawFulfillRandomWords` L1700 guard IS in scope):** The L1700 `if (rngLockedFlag) { ... }` branch in `rawFulfillRandomWords` is part of the state-machine airtightness proof — specifically the revert-safety invariant that a stale VRF delivery cannot leave `rngLockedFlag = true` indefinitely. Enumerated as a Clear-Site Ref with its own Path Enumeration row. Cross-cites v3.7 Phase 63 rawFulfillRandomWords revert-safety proof without relying on it.
- **D-07 (VRF request-retry + 12h timeout path IS in scope):** The retry path (VRF request aged ≥ 12h can be re-requested) has a clear-without-matching-new-set semantics that must be enumerated. Treated as a Path Enumeration row with explicit verdict. Cross-cites v2.1 VRF retry timeout + v3.7 lifecycle audit as corroborating context without relying on them.

### RNG-02 Evidence Shape (Permissionless Sweep)
- **D-08 (3-class closed taxonomy per ROADMAP SC-2):** Every permissionless function row receives exactly one verdict from {`respects-rngLocked`, `respects-equivalent-isolation`, `proven-orthogonal`}. No fourth class permitted. Any function that cannot be classified into one of the three is a `CANDIDATE_FINDING` for Phase 242.
  - **`respects-rngLocked`** — function path reverts or guards via `rngLockedFlag` check (direct `if (rngLockedFlag) revert` OR inherited revert via called helper). Cite the specific `if (rngLockedFlag)` line from `contracts/`.
  - **`respects-equivalent-isolation`** — function operates under a non-flag mechanism proven equivalent to rngLocked for the specific RNG-consumer state subset it touches. Must cite RNG-03 (a) asymmetry proof OR another first-principles equivalence argument. The canonical member is the lootbox-index-advance set; the re-justification is RNG-03(a).
  - **`proven-orthogonal`** — function writes to state no RNG consumer reads. Must cite Phase 237 Consumer Index + 238-02 FWD-01 storage-read set to demonstrate disjointness. The evidence is "this function's write-set ∩ RNG-consumer read-set = ∅".
- **D-09 (permissionless scope — external/public state-changing, not admin-gated):** A function is `permissionless` iff (1) it has `external` or `public` visibility, (2) it is NOT `view` / `pure` (mutates storage), (3) it has NO caller restriction that limits invocation to admin/governance/game-contract roles — i.e., it is callable by an arbitrary EOA player. Explicitly:
  - **IN scope** — mint, purchase, claim, burn, coinflip, boon, quest, redemption, transfer (if it mutates game-observable state), and any external helper a player can invoke directly or via delegation.
  - **OUT of scope — admin-gated (`onlyAdmin`, `onlyOwner`, `onlyGovernance`, `onlyVaultOwner`)** — the admin actor class is Phase 238 BWD-03 / FWD-02 scope, not Phase 239. Phase 239 covers the player actor class at the function-level instead of the state-level.
  - **OUT of scope — game-internal (`onlyGame`, `onlyCoinflip`, self-call, delegatecall-only-invoked)** — inter-module or protocol-internal calls are not player-reachable. Routed as internal to the module call graph already traced in Phase 237 / Phase 238.
  - **OUT of scope — `view` / `pure`** — no state mutation.
  - **OUT of scope — `mocks/`** — mocks are not production contracts (carries forward Phase 237 D-18 in-scope tree).
- **D-10 (sweep table shape):** `v30-PERMISSIONLESS-SWEEP.md` columns: `Row ID | Contract | Function | File:Line | Visibility | Mutates Storage? | Caller Gates | Touches RNG-Consumer State? | Classification | Evidence (File:Line + RNG-03/INV-237-NNN cite) | Verdict`. One row per permissionless function. Verdict in {`CLASSIFIED_CLEAN`, `CANDIDATE_FINDING`}. Row ID format `PERM-239-NNN` (three-digit zero-padded), consistent with Phase 237 D-06 `INV-237-NNN` naming convention.
- **D-11 (two-pass sweep — mechanical grep first, then semantic classification):** Plan 02 uses two passes:
  - **Pass 1 (mechanical, grep-driven):** `grep -rn 'external\|public'` over `contracts/` minus `contracts/mocks/`; filter to non-`view` / non-`pure`; filter out explicit modifier gates (`onlyAdmin`, `onlyGame`, etc.). Produces candidate universe.
  - **Pass 2 (semantic, classification):** For each candidate function, trace the storage write set and touch-check against the RNG-consumer state space from Phase 237 inventory. Assign one of the three classes per D-08. Cross-cite Phase 237 INV-237-NNN for RNG-consumer-touching rows; cite RNG-03(a) for lootbox-index-advance rows.
- **D-12 (input: Phase 237 Consumer Index, not Phase 238 output):** RNG-02 consumes Phase 237 `audit/v30-CONSUMER-INVENTORY.md` Consumer Index (RNG-consumer state space enumeration) directly. It does NOT require Phase 238 BWD/FWD tables — Phase 238 is per-consumer detail, Phase 239 is per-function classification. This preserves the single-wave parallel topology (D-02) and removes an unnecessary cross-phase dependency.

### RNG-03 Evidence Shape (Asymmetry Re-Justification)
- **D-13 (two distinct first-principles proofs, one section each):** `v30-ASYMMETRY-RE-JUSTIFICATION.md` structure:
  - **§ Asymmetry A — Lootbox RNG Index-Advance Isolation Equivalent to Flag-Based Isolation.** Prove: for the lootbox VRF path, advancing `lootboxRngIndex` at request time and reading `lootboxRngWordByIndex[consumerIndex]` at fulfillment time provides the same freeze-proof guarantee that `rngLockedFlag` provides for daily VRF. Formal argument: ∀ lootbox consumer with frozen `consumerIndex = k`, the read `lootboxRngWordByIndex[k]` at fulfillment returns either (a) the uninitialized zero word (guarded elsewhere), or (b) the VRF-delivered word for index `k` written atomically by `rawFulfillRandomWords`. No player, admin, or validator can write `lootboxRngWordByIndex[k]` after index advance past `k`. Concludes equivalent to flag-based isolation for the lootbox path.
  - **§ Asymmetry B — `phaseTransitionActive` Exemption Admits Only `advanceGame`-Origin Writes.** Prove: the `phaseTransitionActive` branch that exempts writes from the rngLocked guard admits only writes originating inside `advanceGame` and creates no player-reachable mutation path to RNG-consumer state. Formal argument: enumerate every SSTORE executed under `phaseTransitionActive = true`, show each SSTORE's call chain roots at `advanceGame`, show no external entry point can toggle `phaseTransitionActive` to `true` without first entering `advanceGame`. Cross-cites v29.0 Phase 235 D-13 Path 4 as corroborating evidence but re-derives the proof at HEAD.
- **D-14 (proof-by-exhaustion format, not proof-by-cite):** Neither asymmetry proof is "shown by prior milestone XYZ". Each proof enumerates the specific storage slots, SSTORE sites, and call chains at HEAD `7ab515fe` and argues from those primitives. Prior-milestone cites are "we independently re-derived the same result" notes, not "we relied on v29.0 Plan 05 conclusion" notes. This is the v30.0 fresh-eyes mandate applied to re-justification specifically.
- **D-15 (RNG-03 output consumed by RNG-02):** The `respects-equivalent-isolation` classification in RNG-02 cites RNG-03(a) as its equivalence warrant. Because both plans run in Wave 1 parallel (D-02), the cite is forward-looking — RNG-02 cites "RNG-03(a) [see `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` § Asymmetry A]" by file+section path. If RNG-03 lands a different proof structure than RNG-02 anticipated, the two are reconciled post-commit in plan SUMMARIES (no re-edit of committed audit files; add an erratum row).

### Fresh-Eyes + Cross-Cite Discipline
- **D-16 (fresh re-prove + cross-cite prior — Phase 235 D-03 / Phase 237 D-07 / Phase 238 D-09 pattern):** Every verdict in all three plans re-derived at HEAD `7ab515fe`. CROSS-CITES prior-milestone artifacts as corroborating evidence only — never as the sole warrant:
  - **v29.0 Phase 235 Plan 05** `235-05-TRNX-01.md` — `rngLocked` 4-path walk: corroborating evidence for RNG-01 path enumeration. NOT relied upon (we re-enumerate from HEAD).
  - **v3.7 Phase 63** VRF path test coverage — rawFulfillRandomWords revert-safety: corroborating for D-06. NOT relied upon.
  - **v3.8 Phases 68-72** VRF commitment window — 55 variables + 87 permissionless paths + 51/51 SAFE general proof: corroborating for RNG-02 sweep scope. NOT relied upon.
  - **v25.0 Phase 215** RNG fresh-eyes sweep — the last milestone-level VRF/RNG SOUND verdict. Corroborating structural baseline. NOT relied upon.
  - **v29.0 KNOWN-ISSUES entry** "Lootbox RNG uses index advance isolation instead of rngLockedFlag" — the design decision RNG-03(a) is re-justifying from first principles. The KI entry is the subject, not the basis.
- **D-17 (re-verify-at-HEAD note on every cross-cite — Phase 235 D-04 pattern):** Each cross-cite carries `re-verified at HEAD 7ab515fe` with a one-line structural-equivalence statement. Contract tree is identical to v29.0 `1646d5af` (all post-v29 commits docs-only per PROJECT.md), so re-verification is mechanical; the note is mandatory to guard against silent divergence.

### Scope Boundaries (what Phase 239 is NOT)
- **D-18 (Phase 239 is not per-consumer — that's Phase 238):** Phase 239's unit of analysis is the `rngLockedFlag` state machine (global invariant) and the permissionless function (not the consumer). Phase 238 owns per-consumer BWD/FWD. Phase 239's intersection with Phase 238 is bounded by the `rngLocked`-gate citation in 238-03 FWD-03 (closed by RNG-01) and the `lootbox-index-advance`-gate citation in 238-03 FWD-03 (closed by RNG-03(a)).
- **D-19 (Phase 239 is not gameover-specific — that's Phase 240):** Phase 239 covers the set/clear state machine for ALL rngLockedFlag toggles; the gameover-entropy branch is ONE of several set/clear pairs. Phase 240 GO-02 specifically proves jackpot-input determinism on the VRF-available gameover branch. Phase 239 does not re-derive gameover determinism — only the rngLockedFlag bookkeeping around the gameover VRF request.
- **D-20 (Phase 239 is not KI-acceptance — that's Phase 241):** Phase 239 re-justifies asymmetries `from first principles`; it does NOT re-litigate whether the KI entries (prevrandao fallback, F-29-04 mid-cycle substitution, affiliate non-VRF entropy, EntropyLib XOR-shift) are acceptable. Phase 241 EXC-01..04 owns acceptance re-verification. Phase 239 may cite KI entries only as the design decisions that created the asymmetries it is re-justifying.
- **D-21 (Phase 239 is not regression — that's Phase 242):** Phase 239 does not carry a regression appendix. Prior-milestone cross-cites are contemporaneous corroboration, not regression verdicts (PASS/REGRESSED/SUPERSEDED). Regression appendix is Phase 242 REG-01/02.

### Finding-ID Emission
- **D-22 (no F-30-NN emission — Phase 235 D-14 / Phase 237 D-15 / Phase 238 D-15 pattern):** Phase 239 does NOT emit `F-30-NN` finding IDs. Produces verdicts + tables + proofs + Finding Candidate blocks that become the pool for Phase 242 FIND-01 intake. Every verdict cites commit SHA + file:line so Phase 242 can anchor without re-discovery.
- **D-23 (Finding Candidates appendix per-plan):** Each of the three plan deliverables carries a "Finding Candidates" subsection listing any rows whose verdict is `CANDIDATE_FINDING`. The three appendices are aggregated into Phase 242 FIND-01 intake alongside Phase 238's candidate pool.

### Output Shape
- **D-24 (three dedicated audit files matching ROADMAP SC-1/2/3 exactly — no consolidated file):** Unlike Phase 238 D-16 (4-file pattern with consolidated `v30-FREEZE-PROOF.md`), Phase 239 produces exactly 3 files mirroring the 3 ROADMAP success criteria. Each file is self-contained with its own Finding Candidates appendix + cross-cite section + frontmatter.
  - `audit/v30-RNGLOCK-STATE-MACHINE.md` — RNG-01 deliverable (Set-Site + Clear-Site + Path-Enumeration + Invariant Proof)
  - `audit/v30-PERMISSIONLESS-SWEEP.md` — RNG-02 deliverable (3-class sweep table + two-pass methodology note)
  - `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` — RNG-03 deliverable (§ Asymmetry A + § Asymmetry B first-principles proofs)
- **D-25 (tabular, grep-friendly, no mermaid — Phase 237 D-09 / Phase 238 D-25 convention):** All three files use tabular evidence. Diagrams in prose, not images. Row IDs grep-stable (`RNGLOCK-239-NNN`, `PERM-239-NNN`, `ASYM-239-A/B-NNN`). Downstream Phase 242 greps by Row ID for finding anchoring.

### Scope-Guard Handoff
- **D-26 (HEAD anchor `7ab515fe` locked in every plan's frontmatter — Phase 237 D-17 / Phase 238 D-19 pattern):** Contract tree unchanged since v29.0 `1646d5af`; all post-v29 commits are docs-only. Any contract change after `7ab515fe` resets the baseline and requires a scope addendum. Frontmatter freeze is mandatory in 239-01, 239-02, 239-03, and each plan SUMMARY.
- **D-27 (READ-only scope, no `contracts/` or `test/` writes — Phase 237 D-18 / Phase 238 D-20 pattern):** Carries forward v28/v29 cross-repo READ-only pattern + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Writes confined to `.planning/` and `audit/` (creating `v30-RNGLOCK-*`, `v30-PERMISSIONLESS-*`, `v30-ASYMMETRY-*` files). `KNOWN-ISSUES.md` is not touched in Phase 239 — KI promotions are Phase 242 FIND-03 only.
- **D-28 (Phase 237 inventory READ-only — scope-guard deferral rule per Phase 237 D-16):** If any Phase 239 plan surfaces a consumer not in Phase 237's inventory, it records a scope-guard deferral in its own plan SUMMARY (file:line + context + proposed inventory delta). Phase 237 output is NOT re-edited in place. Inventory gaps become Phase 242 FIND-01 finding candidates.
- **D-29 (discharges Phase 238 audit assumptions):** Phase 238's `audit/v30-FREEZE-PROOF.md` cited Phase 239 RNG-01 (rngLocked state machine) and RNG-03 (lootbox-index-advance asymmetry) as audit assumptions pending Phase 239 commit (Scope-Guard Deferral #1 per 238-03-SUMMARY + CONTEXT.md Claude's Discretion). Phase 239 commits DISCHARGE those assumptions. Phase 242 REG-01/02 cross-checks the discharge during milestone consolidation — Phase 239 does not re-edit 238 output or claim discharge verdict in its own deliverables (the discharge is evidenced by presence of RNG-01/RNG-03 verdicts at commit time).

### Claude's Discretion
- Exact ordering of RNG-01 table subsections (set-site-first vs clear-site-first vs path-first) — planner picks most readable.
- Whether to include a small "state-machine diagram in prose" summary at top of `v30-RNGLOCK-STATE-MACHINE.md` before the enumeration tables — optional readability aid, not required.
- Whether Plan 02's mechanical grep pass (D-11) preserves raw `grep` commands in the plan SUMMARY for reviewer sanity-checking — encouraged when non-obvious (Phase 237 D-07 precedent).
- Whether RNG-03's two asymmetry proofs share a common-form "freeze-proof equivalence template" across both sections or are written ab initio — planner picks; consistency recommended.
- Whether Finding Candidate severities are pre-classified (INFO / LOW / MED / HIGH) or left as `SEVERITY: TBD-242` — Phase 237/238 both used INFO or TBD; planner matches precedent unless a row is unambiguously higher.
- Row ID prefix variant (`RNGLOCK-239-NNN` vs `RNG01-NNN` vs `SM-NNN`) — planner picks, used consistently within each file.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 237 scope anchor (MUST read — READ-only per D-28)
- `audit/v30-CONSUMER-INVENTORY.md` — 146 INV-237-NNN rows + 146 per-consumer call graphs + Consumer Index
  - §"Universe List" — RNG-02 `Touches RNG-Consumer State?` column input (disjointness check evidence)
  - §"Per-Consumer Call Graphs" — storage-read set per consumer (feeds RNG-02 `proven-orthogonal` evidence)
  - §"Consumer Index" — RNG-01/RNG-02/RNG-03 row mapping from 237 D-10
  - §"KI Cross-Ref Summary" — 4 accepted KI entries including lootbox-index-advance (RNG-03(a) subject)

### Phase 238 output (MUST read — audit-assumption anchor per D-29)
- `audit/v30-238-01-BWD.md` — 146-row backward-freeze table (per-consumer BWD-01/02/03 verdicts); cross-cite source for RNG-01 path enumeration re: set sites preceding VRF request
- `audit/v30-238-02-FWD.md` — 146-row forward-enumeration + adversarial-closure table; cross-cite source for RNG-02 `touches RNG-consumer state` column
- `audit/v30-238-03-GATING.md` — 146-row gating-effectiveness table; CITES Phase 239 RNG-01 + RNG-03 as audit assumptions that Phase 239 DISCHARGES
- `audit/v30-FREEZE-PROOF.md` — final consolidated 238 deliverable; Scope-Guard Deferral #1 entries reference Phase 239 RNG-01/RNG-03

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` §"RNG — rngLocked Invariant & Permissionless Sweep" (RNG-01/RNG-02/RNG-03) — exact requirement wording, locks RNG-02 3-class taxonomy
- `.planning/ROADMAP.md` Phase 239 block — 4 Success Criteria + "Depends on: Phase 237" + "expected 2-3 plans — RNG-01 state-machine proof, RNG-02 permissionless sweep, RNG-03 asymmetry re-justification"
- `.planning/PROJECT.md` Current Milestone v30.0 — write-policy statement + accepted RNG exceptions list

### Accepted RNG exceptions (MUST read — frame RNG-03 asymmetry subjects, NOT its basis)
- `KNOWN-ISSUES.md` §"Lootbox RNG uses index advance isolation instead of rngLockedFlag" — RNG-03(a) asymmetry subject; the design decision being re-justified from first principles (not relied upon as warrant)
- `KNOWN-ISSUES.md` §"Gameover prevrandao fallback" — informational context for RNG-01 path enumeration re: gameover-entropy set/clear symmetry (owned by Phase 241 EXC-02)
- `KNOWN-ISSUES.md` §"Gameover RNG substitution for mid-cycle write-buffer tickets" (F-29-04) — OUT of RNG-01 scope (rngLockedFlag is not the gate there); cross-ref only (Phase 241 EXC-03)
- `KNOWN-ISSUES.md` §"Non-VRF entropy for affiliate winner roll" — OUT of Phase 239 scope (no rngLockedFlag interaction); Phase 241 EXC-01
- `KNOWN-ISSUES.md` §"EntropyLib XOR-shift PRNG for lootbox outcome rolls" — OUT of Phase 239 scope (PRNG primitive, not state-machine interaction); Phase 241 EXC-04

### Prior-milestone artifacts — CROSS-CITE ONLY (D-16), NOT RELIED UPON
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-TRNX-01.md` — `rngLocked` 4-path walk (read buffer / write buffer invariants per Phase 235 D-11/D-12); corroborating for RNG-01 path enumeration + D-07 retry-timeout path treatment
- `.planning/milestones/v3.7-phases/` — Phases 63-67 VRF path test coverage (Foundry invariants + Halmos) + rawFulfillRandomWords revert-safety proof; corroborating for RNG-01 D-06
- `.planning/milestones/v3.8-phases/` — Phases 68-72 VRF commitment window (55 variables, 87 permissionless paths, 51/51 SAFE general proof); corroborating structural baseline for RNG-02 sweep scope
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` — v25.0 RNG fresh-eyes SOUND verdict; last milestone-level RNG-invariant baseline
- `.planning/milestones/v29.0-phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-PFTB-AUDIT.md` — non-zero-entropy guarantee + semantic-path-gate archetypes; corroborating for RNG-01 path enumeration

### Phase decision lineage (MUST read — precedent inheritance)
- `.planning/phases/237-vrf-consumer-inventory-call-graph/237-CONTEXT.md` — D-06 KI-exceptions-in-inventory + D-10 Consumer Index + D-17 HEAD anchor + D-18 READ-only; Phase 239 inherits every structural invariant
- `.planning/phases/238-backward-forward-freeze-proofs/238-CONTEXT.md` — D-01 strict-per-requirement plan split + D-09/D-10 fresh-re-prove + cross-cite + D-13 named-gate taxonomy (rngLocked / lootbox-index-advance gate definitions Phase 239 discharges) + D-19/D-20 HEAD anchor + READ-only
- `.planning/phases/238-backward-forward-freeze-proofs/238-03-SUMMARY.md` — Scope-Guard Deferral #1 entry (Phase 239 RNG-01/RNG-03 audit assumption — discharged by Phase 239 per D-29)

### Project feedback rules (apply across all plans per user's durable instructions)
- `memory/feedback_rng_backward_trace.md` — RNG-audit methodology anchor (RNG-01 set/clear enumeration + RNG-02 touch-check)
- `memory/feedback_rng_commitment_window.md` — commitment-window methodology (RNG-02 `touches RNG-consumer state` evidence)
- `memory/feedback_no_contract_commits.md` — READ-only scope enforcement (D-27)
- `memory/feedback_never_preapprove_contracts.md` — orchestrator never tells subagents contract changes are pre-approved
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source; stale copies elsewhere are ignored
- `memory/feedback_skip_research_test_phases.md` — skip research for mechanical/obvious phases (Phase 239 is audit-execution, not research-heavy; plan directly from this CONTEXT.md)

### In-scope contract tree (`contracts/`) — HEAD `7ab515fe` (per D-26)
Same surface as Phase 237 D-18 + Phase 238 inherited (no re-enumeration): 17 top-level contracts + 11 modules + 5 libraries. `contracts/mocks/` OUT of scope per D-09.

### Known-concentration files (pre-scan informational; planner re-greps at HEAD per D-11)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 9 occurrences of `rngLockedFlag` / `phaseTransitionActive` across set sites (L1579), clear sites (L1635, L1676, L1700 branch), revert guards (L1031), and purchase-level branch (L177)
- `contracts/DegenerusGame.sol` — 6 occurrences
- `contracts/storage/DegenerusGameStorage.sol` — 8 occurrences (variable declarations + internal uses)
- `contracts/modules/DegenerusGameMintModule.sol` — 1 occurrence
- `contracts/modules/DegenerusGameWhaleModule.sol` — 1 occurrence
- Additional surfaces via `rngLocked()` view: `contracts/StakedDegenerusStonk.sol`, `contracts/DegenerusStonk.sol`, `contracts/BurnieCoinflip.sol`, `contracts/BurnieCoin.sol`, `contracts/interfaces/IDegenerusGame.sol` (interface + consumers of the view; not necessarily set/clear sites — planner classifies per D-11 Pass 2)

</canonical_refs>

<code_context>
## Existing Code Insights

### RNG-01 Surface (State Machine)
- `rngLockedFlag` SSTORE sites in `DegenerusGameAdvanceModule.sol`:
  - Set site: `L1579` (`rngLockedFlag = true;` inside VRF request path)
  - Clear sites: `L1635` (standard fulfillment), `L1676` (retry / alternate fulfillment path), `L1700` branch (stale/revert-safety clear)
  - Revert guard: `L1031` (`if (rngLockedFlag) revert RngLocked();`)
  - Purchase-level branch: `L177` (`(lastPurchase && rngLockedFlag)` — read-side; informs state-machine read-surface enumeration but NOT a set/clear site)
- Additional read-side surfaces via the `rngLocked()` view in `DegenerusGame.sol` (6 refs) + cross-contract consumers in `StakedDegenerusStonk.sol`, `DegenerusStonk.sol`, `BurnieCoinflip.sol`, `BurnieCoin.sol` — these are gate-check READ sites (feeds RNG-02 `respects-rngLocked` evidence), not set/clear sites.
- Storage declaration + internal-use in `DegenerusGameStorage.sol` (8 refs) + interface declaration in `IDegenerusGame.sol` — structural scaffolding; RNG-01 path enumeration traces back to this storage slot.
- `phaseTransitionActive` storage slot + branch gate: structural scaffolding for RNG-03(b); branch at `DegenerusGameAdvanceModule.sol:283` per Phase 238 D-13 `phase-transition-gate` citation (Phase 235 D-13 Path 4 precedent).

### RNG-02 Surface (Permissionless Sweep)
- ~636 total `external` / `public` visibility declarations across `contracts/` (mechanical grep count; planner filters per D-11 Pass 1 to permissionless-subset).
- High-density contracts by raw count:
  - `DegenerusGame.sol` (101 decls) — dominant permissionless surface
  - `DegenerusVault.sol` (76) — vault + claim + governance entry points
  - `DegenerusAdmin.sol` (50) — mostly admin-gated; filtered OUT per D-09
  - `StakedDegenerusStonk.sol` (43) — sDGNRS operations
  - `GNRUS.sol` (38) — charity token
  - `DegenerusStonk.sol` (26) — DGNRS wrapper
  - `DegenerusDeityPass.sol` (25) — deity pass NFT
  - `BurnieCoinflip.sol` (25) — coinflip entry points
  - `BurnieCoin.sol` (28) — BURNIE token
  - Remaining contracts (modules, libraries, misc) — tail distribution
- Mocks (`contracts/mocks/`) excluded per D-09 (not production).
- Phase 237 / Phase 238 storage-write scaffolding (STORAGE-WRITE-MAP.md + ACCESS-CONTROL-MATRIX.md — repo-root audit artifacts) provide disjointness-check evidence for `proven-orthogonal` classification.

### RNG-03 Surface (Asymmetry Re-Justification)
- **Asymmetry A — lootbox index-advance isolation:**
  - `lootboxRngIndex` storage slot + advance site in `DegenerusGameAdvanceModule.sol` / mid-day lootbox VRF request path
  - `lootboxRngWordByIndex` mapping SSTORE inside `rawFulfillRandomWords` (atomic write-on-fulfillment per index)
  - Consumer-side read: frozen `consumerIndex` pinned at request time (Phase 237 inventory rows `mid-day-lootbox` path family, 19 rows per 238 D-12 tally)
  - KI entry (KNOWN-ISSUES.md L33 block): "The rngLockedFlag is set for daily VRF requests but NOT for mid-day lootbox RNG requests. Lootbox RNG isolation relies on a separate mechanism: the lootbox VRF request index advances past the current fulfillment index, preventing any overlap between daily and lootbox VRF words."
- **Asymmetry B — `phaseTransitionActive` exemption:**
  - `phaseTransitionActive` storage slot + set/clear sites in `DegenerusGameAdvanceModule.sol` (bracketing `_advanceGame` execution window)
  - Gate branch at `DegenerusGameAdvanceModule.sol:283` (per Phase 238 D-13 `phase-transition-gate` citation) exempting writes from rngLocked guard
  - Prior-milestone corroboration: v29.0 Phase 235 D-13 Path 4 (read/write buffer invariants) + 232.1-03-PFTB-AUDIT.md (non-zero-entropy guarantees around phase transition)

### Shared Cross-Phase Evidence
- **Phase 237** provides the RNG-consumer state-space enumeration (Universe List + Per-Consumer Call Graphs) that RNG-02 touch-checks against.
- **Phase 238** provides the per-consumer freeze-proof verdicts that Phase 239 does NOT duplicate — Phase 238 is the unit-of-analysis `consumer`, Phase 239 is the unit-of-analysis `invariant` / `permissionless function`.
- **v29.0 Phase 235 Plan 05** provides a 4-path rngLocked walk; Phase 239 re-derives at HEAD per D-16 (mechanical re-verification expected given v29.0→v30.0 contract tree identity).
- **Repo-root audit artifacts** (`STORAGE-WRITE-MAP.md`, `ACCESS-CONTROL-MATRIX.md`, `ETH-FLOW-MAP.md`) — structural scaffolding for RNG-02 disjointness checks + RNG-01 revert-path enumeration + RNG-03 origin-proof call-chain rooting.

### Plan File Structure (per D-01 / D-24)
- `239-01-PLAN.md` → `audit/v30-RNGLOCK-STATE-MACHINE.md` — Set-Site Table + Clear-Site Table + Path-Enumeration Table + Invariant Proof + Finding Candidates appendix
- `239-02-PLAN.md` → `audit/v30-PERMISSIONLESS-SWEEP.md` — Permissionless sweep table (3-class classification) + two-pass methodology note + Finding Candidates appendix
- `239-03-PLAN.md` → `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` — § Asymmetry A + § Asymmetry B first-principles proofs + Finding Candidates appendix

</code_context>

<specifics>
## Specific Ideas — 3-Plan Shape, Single Wave

Per D-01 + D-02, three plans, single-wave parallel:

### Wave 1 (all three parallel — no cross-dependencies at HEAD)

#### Plan 239-01-PLAN.md — RNG-01 rngLockedFlag State Machine Airtight Proof
- **Anchor citation:** `contracts/` set/clear/revert sites at HEAD `7ab515fe` (pre-scanned surfaces in `<code_context>`)
- **Deliverable:** `audit/v30-RNGLOCK-STATE-MACHINE.md` with Set-Site Table + Clear-Site Table + Path-Enumeration Table per D-04 + Invariant Proof section + Finding Candidates appendix per D-23
- **Cross-cites (re-verified at HEAD per D-17):** v29.0 Phase 235 Plan 05 `235-05-TRNX-01.md` (4-path walk corroborating), v3.7 Phase 63 rawFulfillRandomWords revert-safety (D-06 corroborating), v3.8 Phases 68-72 commitment window (structural baseline)
- **Verdict taxonomy (D-05):** every row in {`AIRTIGHT` / `CANDIDATE_FINDING`}; no hedged verdicts
- **Retry + 12h timeout path treatment (D-07):** dedicated Path Enumeration row with its own verdict
- **Gameover VRF branch treatment (D-19):** rngLockedFlag set/clear bookkeeping around gameover VRF request IS in scope; jackpot-input determinism is NOT (Phase 240 GO-02)

#### Plan 239-02-PLAN.md — RNG-02 Permissionless Sweep with 3-Class Classification
- **Anchor citation:** `contracts/` external/public declarations + Phase 237 `audit/v30-CONSUMER-INVENTORY.md` Consumer Index (RNG-consumer state space for `proven-orthogonal` evidence)
- **Deliverable:** `audit/v30-PERMISSIONLESS-SWEEP.md` with two-pass methodology note + permissionless sweep table per D-10 + Finding Candidates appendix
- **Cross-cites (re-verified at HEAD per D-17):** v3.8 Phase 72 87-permissionless-path + 51/51 SAFE general proof (structural baseline), repo-root `STORAGE-WRITE-MAP.md` + `ACCESS-CONTROL-MATRIX.md` (disjointness evidence)
- **3-class closed taxonomy (D-08):** every row in {`respects-rngLocked` / `respects-equivalent-isolation` / `proven-orthogonal`} OR verdict `CANDIDATE_FINDING`
- **Permissionless definition (D-09):** external/public + mutating + no admin/game/self-call gate; mocks excluded
- **Two-pass methodology (D-11):** mechanical grep pass → semantic classification pass; preserve grep commands in plan SUMMARY per Claude's Discretion
- **Forward cite to RNG-03(a) (D-15):** `respects-equivalent-isolation` rows cite RNG-03(a) by file+section path

#### Plan 239-03-PLAN.md — RNG-03 Two Asymmetries Re-Justified from First Principles
- **Anchor citation:** `contracts/` SSTORE sites for `lootboxRngIndex` / `lootboxRngWordByIndex` (Asymmetry A) + `phaseTransitionActive` branch at `DegenerusGameAdvanceModule.sol:283` (Asymmetry B) at HEAD `7ab515fe`
- **Deliverable:** `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` with § Asymmetry A first-principles equivalence proof + § Asymmetry B first-principles origin proof per D-13 + Finding Candidates appendix
- **Cross-cites (re-verified at HEAD per D-17):** KNOWN-ISSUES entry "Lootbox RNG uses index advance isolation instead of rngLockedFlag" (Asymmetry A SUBJECT, not warrant), v29.0 Phase 235 D-13 Path 4 (Asymmetry B corroborating), Phase 232.1-03-PFTB-AUDIT.md (semantic-path-gate corroborating)
- **Proof-by-exhaustion format (D-14):** first-principles arguments from storage primitives at HEAD; prior-milestone cites are "we independently re-derived same result" notes only
- **Discharges Phase 238 D-13 gate citations (D-29):** `lootbox-index-advance` gate (238-03 FWD-03) becomes first-principles-proven by Asymmetry A; `phase-transition-gate` gate becomes first-principles-proven by Asymmetry B. No re-edit of Phase 238 files (discharge evidenced by Phase 239 commit presence).

### Cross-plan invariants (apply to all three)
- HEAD `7ab515fe` frontmatter lock per D-26
- READ-only scope per D-27
- No F-30-NN emission per D-22
- Scope-guard deferral on any out-of-inventory consumer per D-28
- Three closed verdict taxonomies (RNG-01 airtightness D-05 / RNG-02 3-class D-08 / RNG-03 first-principles D-14) — no hedged narrative-only verdicts in any plan

</specifics>

<deferred>
## Deferred Ideas

- **Phase 240 gameover-jackpot-specific proofs (GO-01..05)** — Phase 239 RNG-01 covers only rngLockedFlag bookkeeping around gameover VRF request. Jackpot-input determinism on the VRF-available branch is GO-02 (Phase 240), trigger-timing disproof is GO-04, F-29-04 scope containment is GO-05. No gameover-jackpot-specific proof in Phase 239 per D-19.
- **Phase 241 KI-exception acceptance re-verification (EXC-01..04)** — Phase 239 frames KI entries as design context for asymmetry re-justification but does NOT re-litigate acceptance. Phase 241 EXC-01 (affiliate non-VRF entropy uniqueness), EXC-02 (prevrandao fallback trigger-gating), EXC-03 (F-29-04 scope), EXC-04 (EntropyLib keccak seed) own acceptance re-verification per D-20.
- **Phase 242 FIND-01/02/03 consolidation + F-30-NN ID assignment** — Phase 239 produces candidate pool only per D-22. Consolidation into `audit/FINDINGS-v30.0.md` with severity classification + regression appendix is Phase 242's scope per D-21.
- **Cross-cycle VRF chaining audit** — one VRF word seeds entropy for multiple dependent consumers across days. Out of Phase 239 RNG-01 state-machine scope (scope is the `rngLockedFlag` boolean, not the VRF-word-to-consumer chain). Phase 238 FWD handles cross-cycle forward mutation; Phase 240 GO-02 handles gameover cross-cycle. Phase 237 deferred this already (237-CONTEXT.md Deferred §).
- **Automated invariant runner against RNG-01 state-machine table + RNG-02 sweep table** — Foundry/Halmos-queryable encoding of the set/clear paths + permissionless classification. Out of v30.0 scope (READ-only, no test writes per D-27). Future-milestone candidate (237-CONTEXT.md + 238-CONTEXT.md both deferred similarly).
- **Gate-taxonomy expansion in Phase 238 (if discovered via Phase 239)** — if RNG-02 surfaces a function whose classification requires a gate outside Phase 238 D-13's four-value NAMED_GATE taxonomy (`rngLocked` / `lootbox-index-advance` / `phase-transition-gate` / `semantic-path-gate`), it is a `CANDIDATE_FINDING` per Phase 239 D-08, not a taxonomy amendment. Taxonomy expansion is a first-principles v30.0 discovery routed to Phase 242 FIND-01.
- **Post-v29 contract-tree divergence** — if any post-v29.0 commit to `contracts/` lands before Phase 239 commits (tree currently identical to `1646d5af` per PROJECT.md), the baseline resets and all three Phase 239 plans require scope addendums per D-26. Planner monitors HEAD between plan starts.
- **Admin-actor RNG-state mutation** — Phase 239 RNG-02 excludes admin-gated functions per D-09 (Phase 238 BWD-03/FWD-02 adversarial-closure `admin` actor class already owns admin-reachable mutation paths). If a new admin-gated function is added post-HEAD that touches RNG-consumer state, Phase 238 owns the per-consumer adversarial closure; Phase 239 RNG-02 does NOT re-audit admin paths.
- **EntropyLib XOR-shift PRNG internal state audit** — EntropyLib's seed derivation (`EntropyLib.entropyStep()` keccak-derived from VRF word) is out of RNG-01 state-machine scope (EntropyLib is a PRNG primitive, not a state-machine participant). Per-caller classification falls to RNG-02 via D-02 (each `entropyStep` caller is classified at the calling site). PRNG internal-state acceptance re-verification is Phase 241 EXC-04.
- **rngLocked() external view surface audit** — the `rngLocked()` view is read by multiple contracts (`StakedDegenerusStonk.sol`, `DegenerusStonk.sol`, `BurnieCoinflip.sol`, `BurnieCoin.sol`, interfaces). Each READ site is a gate-check evidence row for RNG-02 `respects-rngLocked` classification; Phase 239 does NOT re-audit whether the READ sites correctly interpret the flag semantics (that is function-body correctness, already covered by Phase 238 per-consumer FWD-03 gating verification + v25.0 adversarial audit). Phase 239 RNG-02 cites the READ presence as gate evidence.

</deferred>

---

*Phase: 239-rnglocked-invariant-permissionless-sweep*
*Context gathered: 2026-04-19*
