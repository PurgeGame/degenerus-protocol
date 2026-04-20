# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ✅ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (shipped 2026-04-15) — see [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md)
- ✅ **v29.0 Post-v27 Contract Delta Audit** — Phases 230-236 (shipped 2026-04-18) — see [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md)
- 🚧 **v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit** — Phases 237-242 (in progress)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

<details>
<summary>✅ v27.0 Call-Site Integrity Audit (Phases 220-223) — SHIPPED 2026-04-13</summary>

- [x] Phase 220: Delegatecall Target Alignment (2/2 plans) — completed 2026-04-12
- [x] Phase 221: Raw Selector & Calldata Audit (2/2 plans) — completed 2026-04-12
- [x] Phase 222: External Function Coverage Gap (3/3 plans) — completed 2026-04-13
- [x] Phase 223: Findings Consolidation (2/2 plans) — completed 2026-04-13

</details>

<details>
<summary>✅ v28.0 Database & API Intent Alignment Audit (Phases 224-229) — SHIPPED 2026-04-15</summary>

- [x] Phase 224: API Route & OpenAPI Alignment (1/1 plans) — completed 2026-04-13
- [x] Phase 225: API Handler Behavior & Validation Schema Alignment (3/3 plans) — completed 2026-04-13
- [x] Phase 226: Schema, Migration & Orphan Audit (4/4 plans) — completed 2026-04-15
- [x] Phase 227: Indexer Event Processing Correctness (3/3 plans) — completed 2026-04-15
- [x] Phase 228: Cursor, Reorg & View Refresh State Machines (2/2 plans) — completed 2026-04-15
- [x] Phase 229: Findings Consolidation (2/2 plans) — completed 2026-04-15

**Findings:** 69 total (0 CRITICAL/HIGH/MEDIUM, 27 LOW, 42 INFO). See [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md) and [audit/FINDINGS-v28.0.md](../audit/FINDINGS-v28.0.md).

</details>

<details>
<summary>✅ v29.0 Post-v27 Contract Delta Audit (Phases 230-236) — SHIPPED 2026-04-18</summary>

- [x] Phase 230: Delta Extraction & Scope Map (1/1 plans) — completed 2026-04-17
- [x] Phase 231: Earlybird Jackpot Audit (3/3 plans) — completed 2026-04-17
- [x] Phase 232: Decimator Audit (3/3 plans) — completed 2026-04-18
- [x] Phase 232.1: RNG-Index Ticket Drain Ordering Enforcement (3/3 plans) — completed 2026-04-18
- [x] Phase 233: Jackpot/BAF + Entropy Audit (3/3 plans) — completed 2026-04-19
- [x] Phase 234: Quests / Boons / Misc Audit (1/1 plans) — completed 2026-04-19
- [x] Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition (5/5 plans) — completed 2026-04-18
- [x] Phase 236: Regression + Findings Consolidation (2/2 plans) — completed 2026-04-18

**Findings:** 4 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 32 prior findings re-verified (31 PASS + 1 SUPERSEDED + 0 REGRESSED). See [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md) and [audit/FINDINGS-v29.0.md](../audit/FINDINGS-v29.0.md).

</details>

<details open>
<summary>🚧 v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit (Phases 237-242) — IN PROGRESS</summary>

**Milestone Goal:** For every function in `contracts/` that consumes a VRF word, prove that from the moment the VRF request is fired, every variable influencing how that word is eventually consumed is frozen — backward (inputs committed at request time) and forward (consumption-site state un-mutable by any actor between request and consumption), exhaustively enumerated per consumer (no sampling). The only accepted violations are the four documented exceptions in `KNOWN-ISSUES.md` (Affiliate winner roll non-VRF seed, Gameover prevrandao fallback, Gameover RNG substitution for mid-cycle write-buffer tickets, EntropyLib XOR-shift PRNG). Read-only audit — writes confined to `.planning/`, `audit/`, and possibly `KNOWN-ISSUES.md` (for FIND-03 promotions). Audit baseline: HEAD `7ab515fe` (contract tree identical to v29.0 `1646d5af`). Deliverable: `audit/FINDINGS-v30.0.md`.

- [x] **Phase 237: VRF Consumer Inventory & Call Graph** — Exhaustive universe list of every VRF-consuming call site in `contracts/`, typed by path family, with per-consumer end-to-end call graph from VRF request through fulfillment to consumption (completed 2026-04-19; 146 INV-237-NNN rows; final consolidated deliverable `audit/v30-CONSUMER-INVENTORY.md` assembled)
- [x] **Phase 238: Backward & Forward Freeze Proofs (per consumer)** — Per-consumer backward trace (inputs committed at request time) + forward enumeration (consumption-site state frozen between request and consumption) + adversarial closure + gating verification, exhaustive per consumer (completed 2026-04-19; 3/3 plans; final consolidated `audit/v30-FREEZE-PROOF.md` 459 lines + 146-row Consolidated Freeze-Proof Table merging BWD + FWD + gating verdicts + 26-requirement Consumer Index; 124 SAFE + 22 EXCEPTION + 0 CANDIDATE_FINDING; Named Gate distribution rngLocked=106 / lootbox-index-advance=20 / semantic-path-gate=18 / NO_GATE_NEEDED_ORTHOGONAL=2; Phase 239 RNG-01/RNG-03 audit assumption recorded in Scope-Guard Deferral #1 for Phase 242 cross-check)
- [x] **Phase 239: rngLocked Invariant & Permissionless Sweep** (completed 2026-04-19; 3/3 plans) — `rngLockedFlag` set/clear state machine airtight (RNG-01 commit `5764c8a4`); every permissionless function classified (RNG-02 commit `0877d282`, distribution respects-rngLocked=24 / respects-equivalent-isolation=0 / proven-orthogonal=38); two documented asymmetries re-justified from first principles (RNG-03 commit `7e4b3170`, § Asymmetry A lootbox-index-advance equivalent + § Asymmetry B phaseTransitionActive admits only advanceGame-origin writes). All three portions of Phase 238-03 Scope-Guard Deferral #1 discharged (rngLocked via 239-01, lootbox-index-advance via 239-03 § A, phase-transition-gate via 239-03 § B)
- [x] **Phase 240: Gameover Jackpot Safety** — Dedicated proof that the VRF-available gameover-jackpot branch is fully deterministic (completed 2026-04-19; 3/3 plans; `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` 838 lines final consolidated deliverable per D-27 at commit `4e8a7d51`). GO-01 19-row gameover-VRF consumer inventory + GO-02 VRF-available-branch determinism proof (7 SAFE + 8 EXCEPTION (KI: EXC-02) + 4 EXCEPTION (KI: EXC-03)) at 240-01 commit `22b8b109`; GO-03 dual-table state-freeze (28 GOVAR-240-NNN + 19 Per-Consumer Cross-Walk) + GO-04 trigger-timing disproof (2 GOTRIG DISPROVEN_PLAYER_REACHABLE_VECTOR + 3-verdict Non-Player Narrative) at 240-02 commit `1003ad31`; GO-05 F-29-04 dual-disjointness BOTH_DISJOINT per D-15 at 240-03 commit `b0a6487d`; 17+12 forward-cite tokens (See Phase 241 EXC-02/EXC-03) preserved in consolidated file for Phase 241 handshake; zero F-30-NN + zero CANDIDATE_FINDING across all 3 sub-plans
- [x] **Phase 241: Exception Closure** — Confirm the 4 KNOWN-ISSUES RNG entries are the *only* violations of the determinism invariant — no latent non-VRF entropy source, no additional prevrandao entry point, F-29-04 scope unchanged, EntropyLib seed still keccak-derived (completed 2026-04-19; 1/1 plan; final consolidated `audit/v30-EXCEPTION-CLOSURE.md` 312 lines assembled at commit `e6b3a396` per ROADMAP SC-1 literal. 22-row ONLY-ness table (2 EXC-01 + 8 EXC-02 + 4 EXC-03 + 8 EXC-04) + Gate A PASSES + Gate B PASSES → ONLY_NESS_HOLDS_AT_HEAD. EXC-02 two-predicate (single-call-site + 14-day gate) RE_VERIFIED_AT_HEAD. EXC-03 tri-gate (terminal-state + no-player-timing + buffer-scope) RE_VERIFIED_AT_HEAD. EXC-04 two-part (P1a EntropyLib body + P1b caller-site keccak VRF-sourced at all 8 call sites) RE_VERIFIED_AT_HEAD. 29/29 Phase 240 forward-cite tokens discharged (17 EXC-02 EXC-241-023..039 + 12 EXC-03 EXC-241-040..051) with literal verdict DISCHARGED_RE_VERIFIED_AT_HEAD; zero CANDIDATE_FINDING; zero v30.0-series finding IDs. 18 `re-verified at HEAD 7ab515fe` notes across 8 cross-cited prior artifacts.)
- [ ] **Phase 242: Regression + Findings Consolidation** — Re-verify v29.0 + v25.0 + v3.7 + v3.8 RNG-adjacent findings against current baseline; consolidate all v30.0 findings into `audit/FINDINGS-v30.0.md` with per-consumer proof table + dedicated gameover-jackpot section + regression appendix; promote any new KI-eligible items to `KNOWN-ISSUES.md`

## Phase Details

### Phase 237: VRF Consumer Inventory & Call Graph
**Goal**: The universe list of every VRF-consuming call site in `contracts/` is exhaustively enumerated, typed by path family, and each consumer has a full request→fulfillment→consumption call graph documented
**Depends on**: Nothing (first phase of v30.0)
**Requirements**: INV-01, INV-02, INV-03
**Success Criteria** (what must be TRUE):
  1. `audit/v30-CONSUMER-INVENTORY.md` contains a typed row for every VRF-consuming function in `contracts/`, with no sampling — each row cites file:line of the consumption site, the VRF-request origin site, and the path family (`daily` / `mid-day-lootbox` / `gap-backfill` / `gameover-entropy` / `other`)
  2. The inventory classification column (INV-02) resolves every consumer into exactly one path family; any consumer that does not fit an existing family is added under `other` with a named subcategory and justification
  3. Per-consumer call graphs (INV-03) are recorded either inline in the inventory or in companion `audit/v30-237-CALLGRAPH-*.md` files, covering every intermediate storage touchpoint between VRF request, `rawFulfillRandomWords`, and the consumption site
  4. The inventory is usable as the authoritative scope definition for Phases 238-241 — downstream phases reference inventory row IDs without needing additional discovery
**Plans**: 3 plans
  - [ ] 237-01-PLAN.md — INV-01 Enumeration sweep (wave 1, solo): zero-glance fresh-eyes pass at HEAD 7ab515fe + post-hoc reconciliation against prior milestone artifacts (v29.0 Phase 235 03/04, v25.0 Phase 215, v3.7/v3.8). Outputs `audit/v30-237-01-UNIVERSE.md` (with TBD placeholders for 237-02 / 237-03 downstream columns).
  - [x] 237-02-PLAN.md — INV-02 Path-family classification + subcategory + KI cross-ref (wave 2, parallel with 237-03, depends on 237-01). Outputs `audit/v30-237-02-CLASSIFICATION.md` — replaces 237-01's TBD-237-02 placeholders with locked path families (`daily` / `mid-day-lootbox` / `gap-backfill` / `gameover-entropy` / `other` + named subcategory) and KI Cross-Ref column mapping every KI-exception row to a KNOWN-ISSUES.md entry. Completed 2026-04-19: 146 rows classified (daily 91 / mid-day-lootbox 19 / gap-backfill 3 / gameover-entropy 7 / other 26); all 5 KI exception headers cross-referenced; 7 Finding Candidates surfaced (INFO).
  - [x] 237-03-PLAN.md — INV-03 Per-consumer call graphs + Consumer Index + final consolidation (wave 2, parallel with 237-02, depends on 237-01). Completed 2026-04-19: `audit/v30-237-03-CALLGRAPH.md` (1943 lines; 146 call-graph entries; 6 shared-prefix chains deduplicate 130 rows; zero companion files needed). Final consolidated `audit/v30-CONSUMER-INVENTORY.md` (2362 lines; 13 required sections; 146 Universe List rows + 146 Per-Consumer Call Graphs + 26-row Consumer Index mapping every v30.0 requirement to its INV-237-NNN subset per D-10). 5 new Finding Candidates surfaced (INFO) bringing merged total across Phase 237 to 17 for Phase 242 FIND-01..03 routing.

### Phase 238: Backward & Forward Freeze Proofs (per consumer)
**Goal**: Every consumer in the Phase 237 inventory has an exhaustive backward freeze proof (inputs committed at VRF request time) AND forward freeze proof (consumption-site state un-mutable between request and consumption), with adversarial closure and gating verification documented per consumer
**Depends on**: Phase 237
**Requirements**: BWD-01, BWD-02, BWD-03, FWD-01, FWD-02, FWD-03
**Success Criteria** (what must be TRUE):
  1. `audit/v30-FREEZE-PROOF.md` (or a per-consumer-family set of sibling files) contains, for every consumer in the Phase 237 inventory, a backward-trace table mapping every storage read at consumption time to a write site classified `written-before-request` OR `unreachable-after-request` — no variable classified `mutable-after-request` except via an explicitly-cited KNOWN-ISSUES exception
  2. Every consumer row has an adversarial-closure column (BWD-03) answering "can a player, admin, or validator mutate any backward-input state between request and consumption?" with a verdict of SAFE or EXCEPTION (with KI reference), covering every actor class exhaustively — not sampled
  3. Every consumer row has a forward-enumeration block (FWD-01) listing every piece of state read at consumption time and its write path(s), paired with an adversarial-closure column (FWD-02) answering "can any actor mutate any consumption-site state between VRF request and consumption?" — again exhaustive, not sampled
  4. Every consumer's forward-gating mechanism (FWD-03 — `rngLocked` / lootbox index-advance / phase-transition gate / semantic path gate) is named and proven to block every forward mutation path identified in FWD-01/02 — gating is demonstrated effective, never assumed
  5. Any row that cannot be proven SAFE is promoted to the Phase 242 finding candidate pool with severity classification and supporting evidence
**Plans**: 3 plans (2 waves per 238-CONTEXT.md D-01/D-02)
  - [x] 238-01-PLAN.md — BWD-01/02/03 per-consumer backward freeze (146 rows) — Wave 1 (parallel with 238-02); completed 2026-04-19 at commit `d0a37c75`: `audit/v30-238-01-BWD.md` (620 lines; 146 Backward Freeze Table rows + 146 Backward Adversarial Closure Table rows + 19-row Gameover-Flow subset + 6 shared-prefix chains + 7 prior-artifact cross-cites; 22 EXCEPTION matching EXC-01..04 distribution + 124 SAFE + 0 CANDIDATE_FINDING; zero F-30-NN; zero contracts/test writes; inventory unmodified)
  - [x] 238-02-PLAN.md — FWD-01/02 per-consumer forward enumeration + adversarial closure (146 rows) — Wave 1 (parallel with 238-01); completed 2026-04-19 at commit `8b0bd585`: `audit/v30-238-02-FWD.md` (660 lines; 146 Forward Enumeration Table rows + Forward Mutation Paths per-chain + bespoke-tail tuples as Plan 238-03 FWD-03 direct input + 19-row Gameover-Flow subset + 6 shared-prefix chains + 6 prior-artifact cross-cites; 22 EXCEPTION matching EXC-01..04 distribution + 124 SAFE + 0 CANDIDATE_FINDING; zero F-30-NN; zero contracts/test writes; inventory + Plan 238-01 BWD both unmodified)
  - [x] 238-03-PLAN.md — FWD-03 per-consumer gating verification + final consolidated audit/v30-FREEZE-PROOF.md assembly — Wave 2 (depended on 238-01 + 238-02). Completed 2026-04-19: `audit/v30-238-03-GATING.md` (308 lines, commit `1f302d6e`; 146-row Gating Verification Table × 6 columns per D-06; Named Gate distribution rngLocked=106 / lootbox-index-advance=20 / phase-transition-gate=0 / semantic-path-gate=18 / NO_GATE_NEEDED_ORTHOGONAL=2; Mutation-Path Coverage EVERY_PATH_BLOCKED=144 / NO_GATE_NEEDED_ORTHOGONAL=2 / PARTIAL_COVERAGE=0) + `audit/v30-FREEZE-PROOF.md` (459 lines, commit `9a8f423d`; 146-row Consolidated Freeze-Proof Table × 10 columns merging BWD+FWD+gating + 19-row Gameover-Flow Freeze-Proof Subset + 22-row KI-Exception Freeze-Proof Subset + 26-requirement Consumer Index + merged Finding Candidates + merged Scope-Guard Deferrals including Phase 239 audit assumption). 124 SAFE + 22 EXCEPTION + 0 CANDIDATE_FINDING = 146. Zero F-30-NN; zero contracts/test writes; inventory + 238-01 + 238-02 unmodified.

### Phase 239: rngLocked Invariant & Permissionless Sweep
**Goal**: The global `rngLockedFlag` state machine is proven airtight; every permissionless function in `contracts/` is classified against the RNG-consumer state space; and the two documented asymmetries (lootbox index-advance, `phaseTransitionActive` exemption) are re-justified from first principles
**Depends on**: Phase 237
**Requirements**: RNG-01, RNG-02, RNG-03
**Success Criteria** (what must be TRUE):
  1. `audit/v30-RNGLOCK-STATE-MACHINE.md` enumerates every `rngLockedFlag` set site, every clear site, and every early-return / revert path in between, with a proof that no reachable path produces set-without-clear or clear-without-matching-set
  2. `audit/v30-PERMISSIONLESS-SWEEP.md` lists every permissionless function in `contracts/` with a classification of `respects-rngLocked` / `respects-equivalent-isolation` / `proven-orthogonal` — no permissionless function may touch RNG-consumer input state or consumption-time state without falling into one of these three classes
  3. Both documented asymmetries are re-proven from first principles in a dedicated `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` section: (a) lootbox RNG index-advance isolation proven equivalent to flag-based isolation; (b) `phaseTransitionActive` exemption proven to admit only advanceGame-origin writes and to not create any player-reachable mutation path to RNG-consumer state
  4. Prior-milestone artifacts (v25.0 RNG sweep, v29.0 Plan 235-05 TRNX-01, v3.7/v3.8) may be referenced as context but MUST NOT be relied upon — every assertion in this phase is re-proven against HEAD `7ab515fe`
**Plans**: 3 plans (single wave — all 3 parallel per 239-CONTEXT.md D-01/D-02)
  - [x] 239-01-PLAN.md — RNG-01 `rngLockedFlag` state machine airtight proof (wave 1, parallel with 239-02 + 239-03). Output `audit/v30-RNGLOCK-STATE-MACHINE.md` (317 lines, commit `5764c8a4`): 1-row Set-Site Table @ AdvanceModule:1579 + 3-row Clear-Site Table (`_unlockRng` :1676, `updateVrfCoordinatorAndSub` :1635, L1700 `rawFulfillRandomWords` branch Clear-Site-Ref per D-06) + 9-row Path Enumeration Table (7 SET_CLEARS_ON_ALL_PATHS + 2 CLEAR_WITHOUT_SET_UNREACHABLE, zero CANDIDATE_FINDING; includes D-06 L1700 revert-safety, D-07 12h retry-timeout, D-19 gameover-bracket) + closed-form biconditional Invariant Proof + 5 prior-milestone cross-cites × 7 re-verified-at-HEAD notes + `None surfaced` Finding Candidates + `None surfaced` Scope-Guard Deferrals + Attestation. Closed verdict taxonomy per D-05; RNG-01 AIRTIGHT. Discharges Phase 238-03 Scope-Guard Deferral #1 (rngLocked audit assumption) per D-29 — no re-edit of 238 files. Zero F-30-NN; zero contracts/test writes; KNOWN-ISSUES + Phase 237/238 outputs unchanged. Completed 2026-04-19.
  - [x] 239-02-PLAN.md — RNG-02 permissionless sweep with 3-class classification (wave 1, parallel with 239-01 + 239-03). Output `audit/v30-PERMISSIONLESS-SWEEP.md` (328 lines, commit `0877d282`): two-pass methodology (Pass 1 mechanical grep + Pass 2 semantic classification) + 62-row Permissionless Sweep Table per D-10 (11 columns); closed 3-class taxonomy per D-08 with distribution respects-rngLocked=24 / respects-equivalent-isolation=0 / proven-orthogonal=38 / CANDIDATE_FINDING=0 (24+0+38+0=62); Classification Distribution Heatmap reconciles; Pass 1 grep commands preserved for reviewer reproducibility per Claude's Discretion; Phase 237 inventory input per D-12 (NOT Phase 238 output — D-02 single-wave parallel preserved); 3 rows forward-cite RNG-03(a) `§ Asymmetry A` per D-15 as FORWARD-ONLY corroborating (primary warrant is direct rngLockedFlag gate); 5 prior-milestone cross-cites × 6+ re-verified-at-HEAD notes; `None surfaced` Finding Candidates; `None surfaced` Scope-Guard Deferrals. Zero F-30-NN; zero contracts/test writes; KNOWN-ISSUES + Phase 237/238 + Plan 239-01 outputs unchanged. Completed 2026-04-19.
  - [x] 239-03-PLAN.md — RNG-03 two asymmetries re-justified from first principles (wave 1, parallel with 239-01 + 239-02). Output `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` (296 lines, commit `7e4b3170`): § Asymmetry A (lootbox index-advance equivalent to flag-based isolation) with 6 sub-sections (Asymmetry Statement + Storage Primitives + 5-row Write Sites table ASYM-239-A-W-01..05 + 7-row Read Sites table ASYM-239-A-R-01..07 + closed-form Equivalence Proof via 6-step freeze-guarantee composition + Discharge of Phase 238-03 lootbox-index-advance portion per D-29) + § Asymmetry B (phaseTransitionActive admits only advanceGame-origin writes) with 6 sub-sections (Asymmetry Statement + Storage Primitives + 13-row Enumerated SSTORE Sites table ASYM-239-B-S-01..13 + Call-Chain Rooting Proof via single-caller-of-`_endPhase` grep-verification + No-Player-Reachable-Mutation-Path Proof via exhaustion over Plan 239-02 62-row RNG-02 permissionless universe + Discharge of Phase 238-03 phase-transition-gate portion per D-29) + Prior-Artifact Cross-Cites (7 cites × 7 `re-verified at HEAD 7ab515fe` backtick-quoted-phrase notes per D-14 format) + `None surfaced` Finding Candidates + `None surfaced` Scope-Guard Deferrals + Attestation. Proof-by-exhaustion from storage primitives at HEAD `7ab515fe` per D-14; KNOWN-ISSUES.md entry `"Lootbox RNG uses index advance isolation instead of rngLockedFlag"` named SUBJECT of Asymmetry A (NOT warrant). Discharges Phase 238-03 lootbox-index-advance + phase-transition-gate audit assumptions per D-29. Zero F-30-NN; zero `contracts/`/`test/` writes; KNOWN-ISSUES + Phase 237/238 + Plans 239-01/239-02 outputs unchanged. Completed 2026-04-19.

### Phase 240: Gameover Jackpot Safety
**Goal**: The VRF-available gameover-jackpot branch is proven fully deterministic — every gameover-VRF consumer is enumerated, every jackpot-input state variable is proven frozen at gameover VRF request time, trigger-timing manipulation is disproven, and F-29-04 scope is confirmed to contain only mid-cycle write-buffer ticket substitution (not jackpot-input determinism)
**Depends on**: Phase 237
**Requirements**: GO-01, GO-02, GO-03, GO-04, GO-05
**Success Criteria** (what must be TRUE):
  1. `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` contains a GO-01 consumer inventory listing every consumer of the gameover VRF word (gameover jackpot winner selection, trait rolls, terminal ticket drain, final-day burn/coinflip resolution, sweep distribution, any others discovered fresh-eyes), each with file:line citations
  2. A GO-02 per-consumer determinism proof demonstrates that on the VRF-available branch (not prevrandao fallback), no player, admin, or validator may influence trait rolls, winner selection, or payout values between gameover VRF request and consumption — exhaustively answered per consumer
  3. A GO-03 state-freeze enumeration lists every state variable that feeds into gameover jackpot resolution (winner indices, pool totals, trait arrays, pending queues, counter state) with a verdict of `frozen-at-request` for each — any variable that cannot be proven frozen is promoted to the Phase 242 finding candidate pool
  4. A GO-04 trigger-timing analysis disproves the hypothesis that an attacker can manipulate gameover trigger timing (120-day liveness stall / pool deficit) to align with a specific mid-cycle state that biases the jackpot on the VRF-available branch
  5. A GO-05 scope-containment section explicitly delineates the VRF-available gameover-jackpot branch from the F-29-04 mid-cycle ticket substitution path — jackpot inputs must be proven frozen irrespective of write-buffer swap state, and F-29-04 must be shown not to leak into jackpot-input determinism
**Plans**: 3 plans
  - [x] 240-01-PLAN.md — GO-01 Gameover-VRF Consumer Inventory + GO-02 VRF-Available Determinism Proof (wave 1, parallel with 240-02). Completed 2026-04-19 at commit `22b8b109`: `audit/v30-240-01-INV-DET.md` (333 lines) — 19-row GO-01 fresh-eyes inventory (7 gameover-entropy + 8 prevrandao-fallback + 4 F-29-04; all CONFIRMED_FRESH_MATCHES_237) + 19-row GO-02 VRF-available-branch determinism proof (7 SAFE_VRF_AVAILABLE + 8 EXCEPTION (KI: EXC-02) + 4 EXCEPTION (KI: EXC-03); zero CANDIDATE_FINDING) + 12 forward-cite tokens to Phase 241 EXC-02/EXC-03 per D-19 + 9 Prior-Artifact Cross-Cites with 14 re-verified-at-HEAD notes + 0 F-30-NN; Phase 237/238/239 outputs untouched per D-31.
  - [x] 240-02-PLAN.md — GO-03 State-Freeze Enumeration + GO-04 Trigger-Timing Disproof (wave 1, parallel with 240-01). Completed 2026-04-19 at commit `1003ad31`: `audit/v30-240-02-STATE-TIMING.md` (368 lines) — GO-03 dual-table (28 GOVAR-240-NNN Per-Variable rows × 6 columns per D-09 with Named Gate distribution 18 rngLocked + 1 lootbox-index-advance + 4 phase-transition-gate + 5 semantic-path-gate + 0 NO_GATE_NEEDED_ORTHOGONAL = 28; Verdict distribution 3 FROZEN_AT_REQUEST + 19 FROZEN_BY_GATE + 3 EXCEPTION (KI: EXC-02) + 3 EXCEPTION (KI: EXC-03) + 0 CANDIDATE_FINDING = 28 + 19-row Per-Consumer Cross-Walk set-bijective with Plan 240-01 GO-240-NNN per D-24; 7 SAFE + 8 EXCEPTION (KI: EXC-02) + 4 EXCEPTION (KI: EXC-03) + 0 CANDIDATE_FINDING = 19) + GO-04 player-centric (2 GOTRIG-240-NNN rows: 120-day liveness stall + pool-deficit safety-escape; both DISPROVEN_PLAYER_REACHABLE_VECTOR) + Non-Player Actor Narrative 3 closed verdicts per D-13 (Admin NO_DIRECT_TRIGGER_SURFACE / Validator BOUNDED_BY_14DAY_EXC02_FALLBACK / VRF-oracle EXC-02_FALLBACK_ACCEPTED) + 6 forward-cite tokens `See Phase 241 EXC-02` per D-19 + 11 Prior-Artifact Cross-Cites with 19 re-verified-at-HEAD notes + 0 F-30-NN; Phase 237/238/239 outputs + Plan 240-01 output untouched per D-31.
  - [x] 240-03-PLAN.md — GO-05 F-29-04 Scope Containment + Final Consolidation (wave 2, depends on 240-01 + 240-02). Completed 2026-04-19: `audit/v30-240-03-SCOPE.md` (316 lines, commit `b0a6487d`) — GO-05 dual-disjointness per D-14 (Inventory-Level DISJOINT — `{4 F-29-04 rows: INV-237-024, -045, -053, -054} ∩ {7 VRF-available gameover-entropy rows: INV-237-052, -072, -077..081} = ∅`, |A∪B|=11; State-Variable-Level DISJOINT — `{6 F-29-04 write-buffer-swap primitive slots: ticketWriteSlot/ticketsFullyProcessed/ticketQueue[]/ticketsOwedPacked[][]/ticketCursor/ticketLevel} ∩ {25 GOVAR-240-NNN jackpot-input sub-universe slots} = ∅`, |C∪D|=31; combined BOTH_DISJOINT per D-15) + 7 Prior-Artifact Cross-Cites with 13 re-verified-at-HEAD notes + 1 forward-cite `See Phase 241 EXC-03` + Finding Candidates (None surfaced) + Scope-Guard Deferrals (None surfaced) + Attestation. `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (838 lines, commit `4e8a7d51`) — FINAL consolidated Phase 240 deliverable per D-27 assembled via Python merge script `/tmp/gameover-jackpot-build/build_consolidated.py` (238-03 Task 3 precedent) with 10 sections merging 240-01/02/03 outputs + Consumer Index mapping GO-01..05 Phase 240 verdicts; 19-row GO-01 Unified Inventory (7 VRF-available + 8 prevrandao + 4 F-29-04) + 19-row GO-02 Determinism Proof (7 SAFE + 8 EXCEPTION (KI: EXC-02) + 4 EXCEPTION (KI: EXC-03)) + GO-03 Per-Variable (28 GOVAR-240-NNN) + Per-Consumer Cross-Walk (19 rows) + GO-04 Trigger Surface (2 GOTRIG-240-NNN DISPROVEN_PLAYER_REACHABLE_VECTOR) + Non-Player Narrative (3 bold-labeled closed verdicts per D-13) + GO-05 BOTH_DISJOINT + merged Prior-Artifact Cross-Cites (47 re-verified-at-HEAD instances grep-counted) + 17 `See Phase 241 EXC-02` + 12 `See Phase 241 EXC-03` forward-cite tokens + zero CANDIDATE_FINDING + zero F-30-NN; Phase 237/238/239 + Plan 240-01/02 intermediate files + KNOWN-ISSUES untouched per D-30/D-31.

### Phase 241: Exception Closure
**Goal**: The four documented KNOWN-ISSUES RNG entries are confirmed to be the *only* violations of the determinism invariant — no latent non-VRF entropy source, no additional prevrandao entry point, F-29-04 scope unchanged, EntropyLib seed still keccak-derived
**Depends on**: Phase 237
**Requirements**: EXC-01, EXC-02, EXC-03, EXC-04
**Success Criteria** (what must be TRUE):
  1. `audit/v30-EXCEPTION-CLOSURE.md` contains an EXC-01 proof that the affiliate winner roll is the *only* non-VRF-seeded randomness consumer in `contracts/` — no other deterministic-seed surface (`block.timestamp`, `block.number`, packed counters, etc.) leaks into any RNG-derived payout or winner-selection path
  2. An EXC-02 trigger-gating re-verification confirms the gameover prevrandao fallback (`_getHistoricalRngFallback`) is reachable only inside `_gameOverEntropy` AND only when an in-flight VRF request has been outstanding ≥ `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` — no additional entry points exist at HEAD
  3. An EXC-03 F-29-04 scope re-verification confirms the mid-cycle RNG substitution is terminal-state only, has no player-reachable timing, and applies only to tickets in the post-swap write buffer — distinct from GO-02 coverage of the VRF-available gameover-jackpot branch
  4. An EXC-04 EntropyLib re-verification confirms `EntropyLib.entropyStep()` seed derivation remains fully VRF-derived via `keccak256(rngWord, player, day, amount)` — no new entry point bypasses the keccak seed construction
**Plans**: 1 plan (single consolidated per CONTEXT.md D-01)
  - [x] 241-01-PLAN.md — EXC-01 ONLY-ness + EXC-02/03/04 predicate re-verification + 29-row Phase 240 forward-cite discharge → single consolidated deliverable `audit/v30-EXCEPTION-CLOSURE.md` (312 lines, 10 sections per D-24); 5 sequential tasks per D-03 (EXC-01 dual-gate at `144da0f4` / EXC-02 single-call-site + 14-day gate at `1f6d9342` / EXC-03 tri-gate at `9e850d60` / EXC-04 P1a body + P1b caller-site keccak at `48170f8e` / consolidation + SUMMARY at `e6b3a396`); HEAD anchor `7ab515fe` per D-25; READ-only contracts/test per D-26. Completed 2026-04-19: ONLY_NESS_HOLDS_AT_HEAD (Gate A PASSES + Gate B PASSES per D-08); EXC-02 RE_VERIFIED_AT_HEAD (2/2 predicates); EXC-03 RE_VERIFIED_AT_HEAD (3/3 tri-gate); EXC-04 RE_VERIFIED_AT_HEAD (P1a + P1b); 29/29 Phase 240 forward-cite tokens discharged (17 EXC-02 + 12 EXC-03); zero CANDIDATE_FINDING; zero v30.0-series finding IDs; 18 `re-verified at HEAD 7ab515fe` notes (D-13 minimum 3 exceeded); 8 cross-cited prior artifacts.

### Phase 242: Regression + Findings Consolidation
**Goal**: Every prior RNG-adjacent finding is regression-checked against the current baseline, and all v30.0 findings are consolidated into `audit/FINDINGS-v30.0.md` with per-consumer proof table, dedicated gameover-jackpot section, and regression appendix; any new KI-eligible items are promoted to `KNOWN-ISSUES.md`
**Depends on**: Phase 238, Phase 239, Phase 240, Phase 241
**Requirements**: REG-01, REG-02, FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v30.0.md` exists with an executive summary (CRITICAL/HIGH/MEDIUM/LOW/INFO counts), a per-consumer proof table covering INV + BWD + FWD + RNG + GO outputs from Phases 237-240, and a dedicated gameover-jackpot section consolidating GO-01..05 verdicts
  2. A regression appendix in `audit/FINDINGS-v30.0.md` re-verifies v29.0 RNG-adjacent findings (F-29-03, F-29-04) + v25.0 + v3.7 + v3.8 rngLocked invariant items against current baseline with PASS / REGRESSED / SUPERSEDED verdicts per item
  3. Every finding emitted by Phases 237-241 has a stable `F-30-NN` ID, severity classification, source phase + file:line citation, and resolution status in `audit/FINDINGS-v30.0.md`
  4. `KNOWN-ISSUES.md` is updated with any new design-decision entries referencing `F-30-NN` IDs — items that qualify are accepted design decisions, tolerable theoretical non-uniformities, or non-exploitable asymmetries discovered fresh-eyes in v30.0
**Plans**: 1 plan (single consolidated per CONTEXT.md D-01; overrides ROADMAP's expected 2-plan split)
  - [ ] 242-01-PLAN.md — FIND-01 (executive summary + 146×5=730-cell per-consumer proof table + dedicated gameover-jackpot section + 17 F-30-NNN finding blocks) + REG-01 (v29.0 F-29-03 + F-29-04 regression, 2 rows) + REG-02 (v3.7 + v3.8 + v25.0 rngLocked invariant items regression, 29 rows) + FIND-02 (combined 31-row regression appendix) + FIND-03 (D-09 3-predicate KI gating walk on all 17 candidates, expected 0 promotions per D-05) → single consolidated deliverable `audit/FINDINGS-v30.0.md` with 10 sections per D-23; 5 sequential tasks per D-03 (Task 1 exec summary + F-30-NNN IDs / Task 2 proof table + gameover section / Task 3 REG-01 / Task 4 REG-02 / Task 5 FIND-02 + FIND-03 + milestone closure attestation); HEAD anchor `7ab515fe` per D-17; READ-only contracts/test per D-24; terminal-phase zero forward-cites per D-25.

## Progress

**Execution Order:**
Phase 237 first (inventory is the scope foundation). After 237 completes, Phases 238, 239, 240, 241 can execute in parallel (each has its own scope lane: 238 = per-consumer freeze, 239 = global invariant, 240 = gameover branch, 241 = exception closure). Phase 242 requires Phases 238-241.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 237. VRF Consumer Inventory & Call Graph | 3/3 | Complete — 146 Row IDs; `audit/v30-CONSUMER-INVENTORY.md` assembled; downstream 238-242 unblocked | 2026-04-19 |
| 238. Backward & Forward Freeze Proofs | 3/3 | Complete — 238-01 BWD-01/02/03 (commit `d0a37c75`) + 238-02 FWD-01/02 (commit `8b0bd585`) + 238-03 FWD-03 gating (commit `1f302d6e`) + 238-03 consolidated `audit/v30-FREEZE-PROOF.md` (commit `9a8f423d`). 146 rows × 3 verdicts each; 124 SAFE + 22 EXCEPTION + 0 CANDIDATE_FINDING. Phase 239 RNG-01/RNG-03 audit assumption routed to Phase 242 cross-check | 2026-04-19 |
| 239. rngLocked Invariant & Permissionless Sweep | 3/3 | Complete    | 2026-04-19 |
| 240. Gameover Jackpot Safety | 3/3 | Complete — 240-01 GO-01 + GO-02 at `22b8b109` (19-row inventory + determinism proof: 7 SAFE + 8 EXC-02 + 4 EXC-03) + 240-02 GO-03 + GO-04 at `1003ad31` (28 GOVAR + 19 Per-Consumer Cross-Walk + 2 GOTRIG DISPROVEN + 3 non-player closed verdicts per D-13) + 240-03 GO-05 at `b0a6487d` (dual-disjointness BOTH_DISJOINT per D-15) + final consolidated `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (838 lines) at `4e8a7d51` per D-27 satisfying ROADMAP SC-1 literal; all 5 GO-NN requirements closed; 19 forward-cite tokens preserved for Phase 241 EXC-02/EXC-03 handshake; zero CANDIDATE_FINDING; zero F-30-NN | 2026-04-19 |
| 241. Exception Closure | 1/1 | Complete — 241-01 EXC-01/02/03/04 at commits `144da0f4` + `1f6d9342` + `9e850d60` + `48170f8e` + `e6b3a396` (5 task commits + consolidation); final consolidated `audit/v30-EXCEPTION-CLOSURE.md` (312 lines, 10 sections per D-24) satisfying ROADMAP SC-1..SC-4 literal; 22-row ONLY-ness table + Gate A/B → ONLY_NESS_HOLDS_AT_HEAD; EXC-02/EXC-03/EXC-04 all RE_VERIFIED_AT_HEAD; 29/29 Phase 240 forward-cite tokens discharged; zero CANDIDATE_FINDING; zero v30.0-series finding IDs emitted | 2026-04-19 |
| 242. Regression + Findings Consolidation | 0/TBD | Not started | — |

**Prior RNG artifact references** (for phase planner context — NOT relied upon in v30.0; this milestone is fresh-eyes from first principles):
- v25.0 Phases 213-217: RNG fresh-eyes sweep (99 chains mapped, VRF/RNG proven SOUND)
- v29.0 Phase 235 Plans 03-04: per-consumer backward-trace + commitment-window enumeration
- v29.0 Phase 235 Plan 05: TRNX-01 rngLocked invariant 4-path re-proof
- v3.7 Phases 63-67: VRF Path Test Coverage (Foundry invariants + Halmos proofs)
- v3.8 Phases 68-72: VRF commitment window audit

</details>
</content>
