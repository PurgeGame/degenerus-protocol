# Roadmap: Degenerus Protocol

## Milestones

- ✅ **v1.0 Always-Open Purchases** — Phases 1-5 (shipped 2026-03-11)
- ✅ **v1.1 Economic Flow Analysis** — Phases 6-11 (shipped 2026-03-12)
- 🚧 **v1.2 RNG Security Audit** — Phases 12-15 (in progress)

## Phases

<details>
<summary>v1.0 Always-Open Purchases (Phases 1-5) — SHIPPED 2026-03-11</summary>

- [x] Phase 1: Storage Foundation (2/2 plans) — completed 2026-03-11
- [x] Phase 2: Queue Double-Buffer (2/2 plans) — completed 2026-03-11
- [x] Phase 3: Prize Pool Freeze (2/2 plans) — completed 2026-03-11
- [x] Phase 4: advanceGame Rewrite (1/1 plan) — completed 2026-03-11
- [x] Phase 5: Lock Removal (1/1 plan) — completed 2026-03-11

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>v1.1 Economic Flow Analysis (Phases 6-11) — SHIPPED 2026-03-12</summary>

- [x] Phase 6: ETH Inflows and Pool Architecture (2/2 plans) — completed 2026-03-12
- [x] Phase 7: Jackpot & Distribution Mechanics (3/3 plans) — completed 2026-03-12
- [x] Phase 8: BURNIE Economics (2/2 plans) — completed 2026-03-12
- [x] Phase 9: Level Progression and Endgame (2/2 plans) — completed 2026-03-12
- [x] Phase 10: Reward Systems and Modifiers (5/5 plans) — completed 2026-03-12
- [x] Phase 11: Parameter Reference (1/1 plan) — completed 2026-03-12

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

### v1.2 RNG Security Audit (In Progress)

**Milestone Goal:** Exhaustive audit of every variable and function touching RNG -- confirm no manipulation window exists between RNG arrival and consumption, with delta focus on changes since v1.0 audit.

- [x] **Phase 12: RNG State & Function Inventory** - Catalogue every variable, function, and data flow that touches VRF entropy (completed 2026-03-14)
- [x] **Phase 13: Delta Verification** - Verify v1.0 audit findings still hold against 8 changed contract files and new state variables (completed 2026-03-14)
- [ ] **Phase 14: Manipulation Window Analysis** - Adversarial analysis of every window between RNG arrival and consumption
- [ ] **Phase 15: Ticket Creation & Mid-Day RNG Deep-Dive** - Focused trace of ticket/lootbox/coinflip flows for manipulation resistance

## Phase Details

### Phase 12: RNG State & Function Inventory
**Goal**: Complete catalogue of every storage variable and function that touches VRF entropy, with data flow traced from callback to consumption
**Depends on**: Nothing (foundation phase -- builds on prior `audit/v1.0-rng-and-changes-audit.md`)
**Requirements**: RVAR-01, RVAR-02, RVAR-03, RVAR-04, RFN-01, RFN-02, RFN-03, RFN-04
**Success Criteria** (what must be TRUE):
  1. Every storage variable holding a VRF word or derived entropy is listed with its slot number, Solidity type, and lifecycle (who writes, who reads, when cleared)
  2. Every storage variable that influences RNG outcome selection (bucket counts, queue indices, ticket counts) is listed with the same detail
  3. A data flow diagram traces VRF callback through `rngWordCurrent` / `lootboxRngWordByIndex` to every downstream consumer function
  4. `lastLootboxRngWord` and `midDayTicketRngPending` are fully traced with write/read/lifecycle analysis
  5. Every external/public entry point that can modify RNG-dependent state is identified with a call graph to RNG state mutations, and guard conditions (`rngLockedFlag`, `prizePoolFrozen`) are catalogued
**Plans**: 3 plans
Plans:
- [x] 12-01-PLAN.md -- RNG storage variable inventory (direct entropy + influencing vars + lifecycle traces)
- [x] 12-02-PLAN.md -- RNG function inventory (function catalogue + entry points + guard analysis)
- [x] 12-03-PLAN.md -- RNG data flow diagrams and call graphs (VRF callback flows + entry point call graphs)

### Phase 13: Delta Verification
**Goal**: Every v1.0 audit finding re-verified against current code, every changed line in 8 modified contracts assessed for RNG impact, and new attack surfaces from added state variables identified
**Depends on**: Phase 12 (inventory provides the variable/function catalogue to diff against)
**Requirements**: DELTA-01, DELTA-02, DELTA-03, DELTA-04
**Success Criteria** (what must be TRUE):
  1. All 8 attack scenarios from the v1.0 audit (`audit/v1.0-rng-and-changes-audit.md`) have a current-code re-verification with PASS/FAIL verdict and evidence
  2. Every changed line in the 8 modified contract files has an RNG-impact assessment (NO IMPACT / NEW SURFACE / MODIFIED SURFACE) with reasoning
  3. New attack surfaces from `lastLootboxRngWord`, `midDayTicketRngPending`, and coinflip lock changes are explicitly identified and analyzed
  4. FIX-1 (`claimDecimatorJackpot` freeze guard) is confirmed still present with exact code reference
**Plans**: 3 plans
Plans:
- [x] 13-01-PLAN.md -- Re-verify 8 v1.0 attack scenarios + confirm FIX-1
- [x] 13-02-PLAN.md -- RNG-impact assessment of every changed line in 11 contract files
- [x] 13-03-PLAN.md -- New attack surface analysis for lastLootboxRngWord, midDayTicketRngPending, coinflip lock changes

### Phase 14: Manipulation Window Analysis
**Goal**: For every point where RNG is consumed, a complete adversarial analysis of what state can change between VRF arrival and consumption, with verdicts
**Depends on**: Phase 12 (inventory of RNG consumption points), Phase 13 (delta surfaces feed into window analysis)
**Requirements**: WINDOW-01, WINDOW-02, WINDOW-03, WINDOW-04
**Success Criteria** (what must be TRUE):
  1. For each RNG consumption point (from Phase 12 inventory), every piece of state that can change between VRF callback and consumption is enumerated
  2. An adversarial timeline covers block builder + VRF front-running scenarios for both daily advanceGame and mid-day lootbox paths
  3. Inter-block manipulation windows during the 5-day jackpot draw sequence are analyzed (what can change between advanceGame calls)
  4. A verdict table rates each identified manipulation window as BLOCKED / SAFE BY DESIGN / EXPLOITABLE with supporting evidence
**Plans**: 2 plans
Plans:
- [ ] 14-01-PLAN.md -- Per-consumption-point window analysis (D1-D9, L1-L8) and block builder adversarial timeline
- [ ] 14-02-PLAN.md -- Inter-block jackpot sequence analysis and consolidated verdict table

### Phase 15: Ticket Creation & Mid-Day RNG Deep-Dive
**Goal**: Focused end-to-end trace of ticket creation and mid-day RNG flows, verifying manipulation resistance at every step including coinflip lock timing
**Depends on**: Phase 12 (inventory), Phase 14 (window analysis provides framework)
**Requirements**: TICKET-01, TICKET-02, TICKET-03, TICKET-04
**Success Criteria** (what must be TRUE):
  1. A complete trace covers ticket creation through buffer assignment through trait assignment, with the entropy source identified at each step
  2. The mid-day `requestLootboxRng` to buffer swap to `processTicketBatch` flow is verified for manipulation resistance with explicit reasoning
  3. Analysis confirms whether any trait or outcome can be influenced when `lastLootboxRngWord` value is known (e.g., from a prior block), with SAFE/EXPLOITABLE verdict
  4. Coinflip lock timing (`_coinflipLockedDuringTransition` windows) is verified to align with RNG-sensitive periods, with gap analysis if misaligned
**Plans**: TBD

## Progress

**Execution Order:** Phases 12 through 15 in sequence.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Storage Foundation | v1.0 | 2/2 | Complete | 2026-03-11 |
| 2. Queue Double-Buffer | v1.0 | 2/2 | Complete | 2026-03-11 |
| 3. Prize Pool Freeze | v1.0 | 2/2 | Complete | 2026-03-11 |
| 4. advanceGame Rewrite | v1.0 | 1/1 | Complete | 2026-03-11 |
| 5. Lock Removal | v1.0 | 1/1 | Complete | 2026-03-11 |
| 6. ETH Inflows and Pool Architecture | v1.1 | 2/2 | Complete | 2026-03-12 |
| 7. Jackpot & Distribution Mechanics | v1.1 | 3/3 | Complete | 2026-03-12 |
| 8. BURNIE Economics | v1.1 | 2/2 | Complete | 2026-03-12 |
| 9. Level Progression and Endgame | v1.1 | 2/2 | Complete | 2026-03-12 |
| 10. Reward Systems and Modifiers | v1.1 | 5/5 | Complete | 2026-03-12 |
| 11. Parameter Reference | v1.1 | 1/1 | Complete | 2026-03-12 |
| 12. RNG State & Function Inventory | v1.2 | 3/3 | Complete | 2026-03-14 |
| 13. Delta Verification | v1.2 | 3/3 | Complete | 2026-03-14 |
| 14. Manipulation Window Analysis | v1.2 | 0/2 | Not started | - |
| 15. Ticket Creation & Mid-Day RNG | v1.2 | 0/? | Not started | - |
