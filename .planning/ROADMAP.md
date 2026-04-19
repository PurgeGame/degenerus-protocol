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

- [ ] **Phase 237: VRF Consumer Inventory & Call Graph** — Exhaustive universe list of every VRF-consuming call site in `contracts/`, typed by path family, with per-consumer end-to-end call graph from VRF request through fulfillment to consumption
- [ ] **Phase 238: Backward & Forward Freeze Proofs (per consumer)** — Per-consumer backward trace (inputs committed at request time) + forward enumeration (consumption-site state frozen between request and consumption) + adversarial closure + gating verification, exhaustive per consumer
- [ ] **Phase 239: rngLocked Invariant & Permissionless Sweep** — `rngLockedFlag` set/clear state machine airtight; every permissionless function classified (respects rngLocked / respects equivalent isolation / proven orthogonal); two documented asymmetries (lootbox index-advance, `phaseTransitionActive` exemption) re-justified from first principles
- [ ] **Phase 240: Gameover Jackpot Safety** — Dedicated proof that the VRF-available gameover-jackpot branch is fully deterministic; every gameover-VRF consumer enumerated; trigger-timing manipulation disproven; F-29-04 scope containment verified (jackpot-input determinism distinct from mid-cycle write-buffer ticket substitution)
- [ ] **Phase 241: Exception Closure** — Confirm the 4 KNOWN-ISSUES RNG entries are the *only* violations of the determinism invariant — no latent non-VRF entropy source, no additional prevrandao entry point, F-29-04 scope unchanged, EntropyLib seed still keccak-derived
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
  - [ ] 237-03-PLAN.md — INV-03 Per-consumer call graphs + Consumer Index + final consolidation (wave 2, parallel with 237-02, depends on 237-01). Outputs `audit/v30-237-03-CALLGRAPH.md` (call graphs per D-11 stop-at-consumption + D-12 companion files) and assembles the final `audit/v30-CONSUMER-INVENTORY.md` by merging 237-01 + 237-02 + 237-03 (D-08).

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
**Plans**: TBD (expected 3-5 plans — may split by consumer family per Phase 237 classification, e.g. daily / mid-day-lootbox / gap-backfill / gameover-entropy / other; parallelizable after inventory completes)

### Phase 239: rngLocked Invariant & Permissionless Sweep
**Goal**: The global `rngLockedFlag` state machine is proven airtight; every permissionless function in `contracts/` is classified against the RNG-consumer state space; and the two documented asymmetries (lootbox index-advance, `phaseTransitionActive` exemption) are re-justified from first principles
**Depends on**: Phase 237
**Requirements**: RNG-01, RNG-02, RNG-03
**Success Criteria** (what must be TRUE):
  1. `audit/v30-RNGLOCK-STATE-MACHINE.md` enumerates every `rngLockedFlag` set site, every clear site, and every early-return / revert path in between, with a proof that no reachable path produces set-without-clear or clear-without-matching-set
  2. `audit/v30-PERMISSIONLESS-SWEEP.md` lists every permissionless function in `contracts/` with a classification of `respects-rngLocked` / `respects-equivalent-isolation` / `proven-orthogonal` — no permissionless function may touch RNG-consumer input state or consumption-time state without falling into one of these three classes
  3. Both documented asymmetries are re-proven from first principles in a dedicated `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` section: (a) lootbox RNG index-advance isolation proven equivalent to flag-based isolation; (b) `phaseTransitionActive` exemption proven to admit only advanceGame-origin writes and to not create any player-reachable mutation path to RNG-consumer state
  4. Prior-milestone artifacts (v25.0 RNG sweep, v29.0 Plan 235-05 TRNX-01, v3.7/v3.8) may be referenced as context but MUST NOT be relied upon — every assertion in this phase is re-proven against HEAD `7ab515fe`
**Plans**: TBD (expected 2-3 plans — RNG-01 state-machine proof, RNG-02 permissionless sweep, RNG-03 asymmetry re-justification)

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
**Plans**: TBD (expected 2-3 plans — GO-01 consumer inventory + GO-02 determinism proof, GO-03 state-freeze + GO-04 trigger-timing disproof, GO-05 F-29-04 scope containment)

### Phase 241: Exception Closure
**Goal**: The four documented KNOWN-ISSUES RNG entries are confirmed to be the *only* violations of the determinism invariant — no latent non-VRF entropy source, no additional prevrandao entry point, F-29-04 scope unchanged, EntropyLib seed still keccak-derived
**Depends on**: Phase 237
**Requirements**: EXC-01, EXC-02, EXC-03, EXC-04
**Success Criteria** (what must be TRUE):
  1. `audit/v30-EXCEPTION-CLOSURE.md` contains an EXC-01 proof that the affiliate winner roll is the *only* non-VRF-seeded randomness consumer in `contracts/` — no other deterministic-seed surface (`block.timestamp`, `block.number`, packed counters, etc.) leaks into any RNG-derived payout or winner-selection path
  2. An EXC-02 trigger-gating re-verification confirms the gameover prevrandao fallback (`_getHistoricalRngFallback`) is reachable only inside `_gameOverEntropy` AND only when an in-flight VRF request has been outstanding ≥ `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` — no additional entry points exist at HEAD
  3. An EXC-03 F-29-04 scope re-verification confirms the mid-cycle RNG substitution is terminal-state only, has no player-reachable timing, and applies only to tickets in the post-swap write buffer — distinct from GO-02 coverage of the VRF-available gameover-jackpot branch
  4. An EXC-04 EntropyLib re-verification confirms `EntropyLib.entropyStep()` seed derivation remains fully VRF-derived via `keccak256(rngWord, player, day, amount)` — no new entry point bypasses the keccak seed construction
**Plans**: TBD (expected 1-2 plans — EXC-01/02 paired (affiliate + prevrandao), EXC-03/04 paired (F-29-04 + EntropyLib); or a single consolidated exception-closure plan)

### Phase 242: Regression + Findings Consolidation
**Goal**: Every prior RNG-adjacent finding is regression-checked against the current baseline, and all v30.0 findings are consolidated into `audit/FINDINGS-v30.0.md` with per-consumer proof table, dedicated gameover-jackpot section, and regression appendix; any new KI-eligible items are promoted to `KNOWN-ISSUES.md`
**Depends on**: Phase 238, Phase 239, Phase 240, Phase 241
**Requirements**: REG-01, REG-02, FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v30.0.md` exists with an executive summary (CRITICAL/HIGH/MEDIUM/LOW/INFO counts), a per-consumer proof table covering INV + BWD + FWD + RNG + GO outputs from Phases 237-240, and a dedicated gameover-jackpot section consolidating GO-01..05 verdicts
  2. A regression appendix in `audit/FINDINGS-v30.0.md` re-verifies v29.0 RNG-adjacent findings (F-29-03, F-29-04) + v25.0 + v3.7 + v3.8 rngLocked invariant items against current baseline with PASS / REGRESSED / SUPERSEDED verdicts per item
  3. Every finding emitted by Phases 237-241 has a stable `F-30-NN` ID, severity classification, source phase + file:line citation, and resolution status in `audit/FINDINGS-v30.0.md`
  4. `KNOWN-ISSUES.md` is updated with any new design-decision entries referencing `F-30-NN` IDs — items that qualify are accepted design decisions, tolerable theoretical non-uniformities, or non-exploitable asymmetries discovered fresh-eyes in v30.0
**Plans**: TBD (expected 2 plans — Plan 01 creates `audit/FINDINGS-v30.0.md` with executive summary + per-consumer proof table + gameover section + F-30-NN blocks; Plan 02 appends regression appendix + KI promotions; modeled on 236-01/236-02 and 217-01/217-02 precedents)

## Progress

**Execution Order:**
Phase 237 first (inventory is the scope foundation). After 237 completes, Phases 238, 239, 240, 241 can execute in parallel (each has its own scope lane: 238 = per-consumer freeze, 239 = global invariant, 240 = gameover branch, 241 = exception closure). Phase 242 requires Phases 238-241.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 237. VRF Consumer Inventory & Call Graph | 2/3 | Wave 1 complete (Plan 01 INV-01); Wave 2 in progress (Plan 02 INV-02 complete 2026-04-19, Plan 03 INV-03 pending) | — |
| 238. Backward & Forward Freeze Proofs | 0/TBD | Not started | — |
| 239. rngLocked Invariant & Permissionless Sweep | 0/TBD | Not started | — |
| 240. Gameover Jackpot Safety | 0/TBD | Not started | — |
| 241. Exception Closure | 0/TBD | Not started | — |
| 242. Regression + Findings Consolidation | 0/TBD | Not started | — |

**Prior RNG artifact references** (for phase planner context — NOT relied upon in v30.0; this milestone is fresh-eyes from first principles):
- v25.0 Phases 213-217: RNG fresh-eyes sweep (99 chains mapped, VRF/RNG proven SOUND)
- v29.0 Phase 235 Plans 03-04: per-consumer backward-trace + commitment-window enumeration
- v29.0 Phase 235 Plan 05: TRNX-01 rngLocked invariant 4-path re-proof
- v3.7 Phases 63-67: VRF Path Test Coverage (Foundry invariants + Halmos proofs)
- v3.8 Phases 68-72: VRF commitment window audit

</details>
</content>
