# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v1.1 Economic Flow Audit** — Phases 6-15 (shipped 2026-03-15)
- ✅ **v1.2 RNG Security Audit (Delta)** — Phases 16-18 (shipped 2026-03-15)
- ✅ **v1.3 sDGNRS/DGNRS Split + Doc Sync** — (shipped 2026-03-16)
- ✅ **v2.0 C4A Audit Prep** — Phases 19-23 (shipped 2026-03-17)
- ✅ **v2.1 VRF Governance Audit + Doc Sync** — Phases 24-25 (shipped 2026-03-18)
- **v3.0 Full Contract Audit + Payout Specification** — Phases 26-30 (in progress)

## Phases

<details>
<summary>v2.0 C4A Audit Prep (Phases 19-23) -- SHIPPED 2026-03-17</summary>

- [x] **Phase 19: Delta Security Audit -- sDGNRS/DGNRS Split** (completed 2026-03-16)
- [x] **Phase 20: Correctness Verification -- Docs, Comments, Tests** (completed 2026-03-16)
- [x] **Phase 21: Novel Attack Surface -- Deep Creative Analysis** (completed 2026-03-17)
- [x] **Phase 22: Warden Simulation + Regression Check** (completed 2026-03-17)
- [x] **Phase 23: Gas Optimization -- Dead Code Removal** (completed 2026-03-17)

</details>

<details>
<summary>v2.1 VRF Governance Audit + Doc Sync (Phases 24-25) -- SHIPPED 2026-03-18</summary>

- [x] **Phase 24: Core Governance Security Audit** — 8 plans, 26 requirements (completed 2026-03-17)
- [x] **Phase 25: Audit Doc Sync** — 4 plans, 7 requirements (completed 2026-03-17)

</details>

### v3.0 Full Contract Audit + Payout Specification

**Milestone Goal:** Comprehensive security audit of all value-transfer paths across all Degenerus Protocol contracts, plus a complete payout specification document. Zero tolerance on every code path that moves ETH, stETH, BURNIE, DGNRS, or WWXRP.

- [x] **Phase 26: GAMEOVER Path Audit** - Audit the terminal distribution path where all remaining protocol funds converge into a single irreversible execution (completed 2026-03-18)
- [x] **Phase 27: Payout/Claim Path Audit** - Audit all 19 normal-gameplay distribution systems covering every value-transfer path outside GAMEOVER (completed 2026-03-18)
- [x] **Phase 28: Cross-Cutting Verification** - Verify recent changes, protocol invariants, edge cases, and top vulnerable functions across the full audited system (completed 2026-03-18)
- [x] **Phase 29: Comment/Documentation Correctness** - Verify every natspec, inline comment, storage layout, and parameter reference against audited ground truth (completed 2026-03-18)
- [ ] **Phase 30: Payout Specification Document** - Synthesize all audit findings into a self-contained HTML specification covering all 17+ distribution systems

## Phase Details

### Phase 26: GAMEOVER Path Audit
**Goal**: Every code path in the terminal distribution sequence is verified correct -- no revert can block payouts, no accounting error can desynchronize claimablePool, no reentrancy can double-pay or strand funds
**Depends on**: Nothing (audit root -- highest risk, newest code, all other phases depend on GAMEOVER context)
**Requirements**: GO-01, GO-02, GO-03, GO-04, GO-05, GO-06, GO-07, GO-08, GO-09
**Success Criteria** (what must be TRUE):
  1. handleGameOverDrain distribution is verified: accumulator to decimator (10%), terminal jackpot (90%), and 50/50 vault/sDGNRS sweep each have explicit PASS or FINDING verdict with line references
  2. handleFinalSweep 30-day claim window, claimablePool zeroing, and unclaimed forfeiture are verified correct with no path that strands claimable funds
  3. Death clock trigger conditions (365d at level 0, 120d at level 1+), distress mode effects, and all activation/deactivation paths are mapped and verified
  4. Every require/revert on the GAMEOVER path is confirmed unable to block payout execution, and CEI ordering is confirmed correct with no reentrancy or double-pay path
  5. Terminal decimator integration, deity pass refund calculations, and no-RNG-available fallback path are verified correct against the new code in DegenerusGameDecimatorModule and DegenerusGameGameOverModule
**Plans:** 4/4 plans complete

Plans:
- [x] 26-01-PLAN.md — Core distribution audit: terminal decimator (GO-08) + handleGameOverDrain (GO-01)
- [x] 26-02-PLAN.md — Safety properties audit: reverts (GO-05), reentrancy/CEI (GO-06), VRF fallback (GO-09)
- [x] 26-03-PLAN.md — Ancillary paths audit: deity refunds (GO-07), final sweep (GO-02), death clock (GO-03), distress mode (GO-04)
- [x] 26-04-PLAN.md — Consolidation: cross-reference all verdicts, claimablePool consistency, update findings report

### Phase 27: Payout/Claim Path Audit
**Goal**: Every normal-gameplay distribution system is independently verified -- each claim path has confirmed CEI ordering, correct claimablePool pairing, and no extraction beyond intended amounts
**Depends on**: Phase 26 (GAMEOVER context needed: auto-rebuy suppression, pool zeroing behavior)
**Requirements**: PAY-01, PAY-02, PAY-03, PAY-04, PAY-05, PAY-06, PAY-07, PAY-08, PAY-09, PAY-10, PAY-11, PAY-12, PAY-13, PAY-14, PAY-15, PAY-16, PAY-17, PAY-18, PAY-19
**Success Criteria** (what must be TRUE):
  1. All jackpot paths (daily purchase-phase, 5-day jackpot-phase draws) have verified winner selection, prize scaling, claim mechanism, and unclaimed handling
  2. All scatter/decimator paths (BAF normal, BAF century, decimator normal, decimator x00, terminal decimator claims) have verified trigger conditions, payout calculations, and round tracking
  3. All ancillary payout paths (coinflip, lootbox, quest, affiliate, stETH yield, accumulator milestones, advance bounty, WWXRP consolation, coinflip recycling/boons) have verified distribution formulas and claim mechanisms
  4. sDGNRS burn and DGNRS wrapper burn proportional redemption math is verified correct for ETH/stETH/BURNIE
  5. Ticket conversion, futurepool mechanics, and auto-rebuy carry are verified with no path allowing extraction beyond intended amounts
**Plans:** 6/6 plans complete

Plans:
- [ ] 27-01-PLAN.md — Jackpot distribution: purchase-phase daily (PAY-01), 5-day draws (PAY-02), ticket conversion/futurepool (PAY-16)
- [ ] 27-02-PLAN.md — Scatter and decimator: BAF normal (PAY-03), BAF century (PAY-04), decimator normal (PAY-05), decimator x00 (PAY-06)
- [ ] 27-03-PLAN.md — Coinflip economy: deposit/win/loss (PAY-07), bounty (PAY-08), WWXRP consolation (PAY-18), recycling/boons (PAY-19)
- [ ] 27-04-PLAN.md — Lootbox, quest, affiliate: lootbox rewards (PAY-09), quest rewards (PAY-10), affiliate commissions (PAY-11)
- [ ] 27-05-PLAN.md — Yield, burns, bounty: stETH yield (PAY-12), accumulator milestones (PAY-13), advance bounty (PAY-17), sDGNRS burn (PAY-14), DGNRS burn (PAY-15)
- [ ] 27-06-PLAN.md — Consolidation: cross-reference all 19 verdicts, claimablePool consistency, update findings report

### Phase 28: Cross-Cutting Verification
**Goal**: All recent code changes are regression-verified, all protocol-wide invariants hold across every mutation site mapped in Phases 26-27, all boundary conditions are analyzed, and the top vulnerable functions receive deep adversarial audit
**Depends on**: Phase 27 (requires exhaustive mutation site inventory from Phases 26-27)
**Requirements**: CHG-01, CHG-02, CHG-03, CHG-04, INV-01, INV-02, INV-03, INV-04, INV-05, EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-05, EDGE-06, EDGE-07, VULN-01, VULN-02, VULN-03
**Success Criteria** (what must be TRUE):
  1. Every commit in the last month is reviewed and each change has a correctness assessment; VRF governance, deity non-transferability, and parameter changes are confirmed still correct after recent modifications
  2. claimablePool solvency invariant (claimablePool <= ETH + stETH balance) is verified at every mutation site including terminal decimator paths, with no violation possible
  3. Pool accounting, sDGNRS supply conservation, and BURNIE mint/burn lifecycle are each verified with explicit proof that no desynchronization path exists
  4. GAMEOVER at level 0, level 1, and level 100 boundaries are analyzed; single-player GAMEOVER handles all distributions correctly; advanceGame gas griefing, decimator claim timing, coinflip auto-rebuy during known-RNG windows, affiliate self-referral loops, and rounding accumulation are each analyzed with explicit verdicts
  5. Top 10 most vulnerable functions are ranked with weighted criteria, each receives a deep adversarial audit with a dedicated finding or explicit PASS verdict, and a ranking document with rationale is produced
**Plans:** 6/6 plans complete

Plans:
- [ ] 28-01-PLAN.md -- Recent changes regression: commit coverage map, CHG-01..04 verdicts
- [ ] 28-02-PLAN.md -- Pool invariants: claimablePool solvency proof (INV-01) and pool accounting balance (INV-02)
- [ ] 28-03-PLAN.md -- Supply invariants: sDGNRS conservation (INV-03), BURNIE lifecycle (INV-04), unclaimable funds (INV-05)
- [ ] 28-04-PLAN.md -- Edge cases and griefing: GAMEOVER boundaries, gas griefing, decimator timing, coinflip RNG, affiliate loops, rounding (EDGE-01..07)
- [ ] 28-05-PLAN.md -- Vulnerability ranking: weighted top-10 scoring, deep adversarial audit, ranking document (VULN-01..03)
- [ ] 28-06-PLAN.md -- Consolidation: all 19 verdicts, cross-phase consistency, FINAL-FINDINGS-REPORT + KNOWN-ISSUES update

### Phase 29: Comment/Documentation Correctness
**Goal**: Every natspec comment, inline comment, storage layout comment, and constants comment in the protocol contracts matches the actual verified behavior established in Phases 26-28
**Depends on**: Phase 28 (ground truth must be established before verifying descriptions match)
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-05
**Success Criteria** (what must be TRUE):
  1. Every natspec comment on every external/public function across all protocol contracts is verified to match actual behavior, with corrections applied where discrepancies exist
  2. Every inline comment is verified against current code with no stale references from prior code versions remaining
  3. Storage layout comments match actual storage positions, constants comments match actual values, and parameter reference doc values are spot-checked against contract source
**Plans:** 6/6 plans complete

Plans:
- [ ] 29-01-PLAN.md -- Core game NatSpec: DegenerusGame.sol natspec and inline comment verification (DOC-01, DOC-02)
- [ ] 29-02-PLAN.md -- Module NatSpec part 1: JackpotModule, DecimatorModule, LootboxModule, AdvanceModule (DOC-01, DOC-02)
- [ ] 29-03-PLAN.md -- Module NatSpec part 2: MintModule, DegeneretteModule, WhaleModule, BoonModule, EndgameModule, GameOverModule, PayoutUtils, MintStreakUtils (DOC-01, DOC-02)
- [ ] 29-04-PLAN.md -- Peripheral NatSpec: all token, governance, and utility contracts (DOC-01, DOC-02)
- [ ] 29-05-PLAN.md -- Storage layout and constants: storage slot diagram verification (DOC-03), constants comment verification (DOC-04)
- [x] 29-06-PLAN.md -- Parameter reference and consolidation: v1.1-parameter-reference.md spot-check (DOC-05), Phase 29 consolidation report (completed 2026-03-18)

### Phase 30: Payout Specification Document
**Goal**: A self-contained HTML document at audit/PAYOUT-SPECIFICATION.html covering all 17+ distribution systems, synthesized entirely from verified audit findings in Phases 26-29 with exact code references
**Depends on**: Phase 29 (synthesis document -- requires all prior audit phases complete for verified ground truth)
**Requirements**: SPEC-01, SPEC-02, SPEC-03, SPEC-04, SPEC-05, SPEC-06
**Success Criteria** (what must be TRUE):
  1. audit/PAYOUT-SPECIFICATION.html exists as a self-contained single-file HTML document viewable in any browser
  2. All 17+ distribution systems are covered, each with trigger condition, source pool, calculation formula, recipients, claim mechanism, and currency documented
  3. Flow diagrams are included for every distribution system showing the complete money path from source to recipient
  4. Edge cases (empty pools, single player, max values, expiry) are documented per system, and every formula uses variable names matching contract code exactly
  5. Contract file:line references are included for every relevant code path, traceable to the current codebase commit
**Plans:** 3/6 plans executed

Plans:
- [ ] 30-01-PLAN.md -- HTML scaffold with CSS design system, header, TOC, pool architecture overview SVG (SPEC-01)
- [ ] 30-02-PLAN.md -- Jackpot distribution: PAY-01 daily, PAY-02 5-day draws, PAY-16 ticket conversion (SPEC-02/03/04/05/06)
- [ ] 30-03-PLAN.md -- Scatter/decimator (PAY-03/04/05/06) and coinflip economy (PAY-07/08/18/19) (SPEC-02/03/04/05/06)
- [ ] 30-04-PLAN.md -- Ancillary payouts (PAY-09/10/11/12/13/17) and token burns (PAY-14/15) (SPEC-02/03/04/05/06)
- [ ] 30-05-PLAN.md -- GAMEOVER terminal distribution: GO-01/02/07/08 with master sequence diagram (SPEC-02/03/04/05/06)
- [ ] 30-06-PLAN.md -- Cross-references (claimablePool invariant, known issues), verification script, final assembly (SPEC-01/02/03/04/05/06)

## Progress

**Execution Order:** Phase 26 -> 27 -> 28 -> 29 -> 30

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 26. GAMEOVER Path Audit | v3.0 | Complete    | 2026-03-18 | 2026-03-18 |
| 27. Payout/Claim Path Audit | 6/6 | Complete    | 2026-03-18 | - |
| 28. Cross-Cutting Verification | 6/6 | Complete    | 2026-03-18 | - |
| 29. Comment/Documentation Correctness | 6/6 | Complete    | 2026-03-18 | - |
| 30. Payout Specification Document | 3/6 | In Progress|  | - |

## Deferred (v3.1+)

- **FV-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FV-02**: Formal verification of vote counting arithmetic via Halmos
- **FV-03**: Monte Carlo simulation of governance outcomes under various voter distributions

---
*Last updated: 2026-03-18 after Phase 30 planning complete -- 6 plans created*
