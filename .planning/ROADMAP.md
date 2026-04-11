# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

### v26.0 Bonus Jackpot Split (In Progress)

**Milestone Goal:** Split the jackpot into two independent drawings — main (ETH, current-level tickets) and bonus (BURNIE, future-level tickets) — with independent trait rolls derived via keccak256 domain separation from the same VRF word.

- [ ] **Phase 218: Bonus Split Implementation** - Independent bonus trait roll, wiring into both code paths, and event emission
- [ ] **Phase 219: Delta Audit & Gas Verification** - Verify main ETH path unchanged and gas headroom preserved

## Phase Details

### Phase 218: Bonus Split Implementation
**Goal**: Both jackpot code paths produce independent bonus trait rolls and distribute BURNIE/carryover tickets using bonus traits while main ETH distribution remains on main traits
**Depends on**: Nothing (first phase of v26.0)
**Requirements**: TSPL-01, TSPL-02, WIRE-01, WIRE-02, WIRE-03, WIRE-04, WIRE-05, EVNT-01, EVNT-02
**Success Criteria** (what must be TRUE):
  1. `payDailyJackpot` rolls bonus traits via keccak256 domain separation from the VRF word, producing traits independent of the main roll
  2. `payDailyCoinJackpot` (purchase phase) and `payDailyJackpotCoinAndTickets` (jackpot phase) both select BURNIE coin winners using bonus traits with near-future target range [lvl+1, lvl+4]
  3. Carryover ticket distribution in `payDailyJackpotCoinAndTickets` uses bonus traits (not main traits) for winner selection
  4. Main ETH jackpot and 20% ticket distribution still use main traits at the current level — no behavioral change
  5. `BonusWinningTraits` event is emitted per bonus drawing with the level and packed traits
**Plans:** 2 plans
Plans:
- [ ] 218-01-PLAN.md — Parameterize _rollWinningTraits with domain separation, update target level range, remove DJT storage
- [ ] 218-02-PLAN.md — Rewire all caller sites, add DailyWinningTraits event, compile verification

### Phase 219: Delta Audit & Gas Verification
**Goal**: Prove the Phase 218 changes are safe: main ETH distribution path is behaviorally unchanged and gas remains within block limits under worst-case bonus distribution
**Depends on**: Phase 218
**Requirements**: VRFY-01, VRFY-02
**Success Criteria** (what must be TRUE):
  1. Delta audit confirms every line in the main ETH distribution path (`_resumeDailyEth`, main jackpot payout, 20% ticket distribution) is identical or provably equivalent to pre-Phase-218 code
  2. Gas measurement under worst-case bonus distribution (50 creditFlip calls) confirms total gas stays within the existing 1.99x headroom margin
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 218 -> 219

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 213. Delta Extraction | v25.0 | 3/3 | Complete | 2026-04-10 |
| 214. Adversarial Audit | v25.0 | 5/5 | Complete | 2026-04-10 |
| 215. RNG Fresh Eyes | v25.0 | 5/5 | Complete | 2026-04-11 |
| 216. Pool & ETH Accounting | v25.0 | 3/3 | Complete | 2026-04-11 |
| 217. Findings Consolidation | v25.0 | 2/2 | Complete | 2026-04-11 |
| 218. Bonus Split Implementation | v26.0 | 0/2 | Not started | - |
| 219. Delta Audit & Gas Verification | v26.0 | 0/? | Not started | - |
