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

- [ ] **Phase 26: GAMEOVER Path Audit** - Audit the terminal distribution path where all remaining protocol funds converge into a single irreversible execution
- [ ] **Phase 27: Payout/Claim Path Audit** - Audit all 19 normal-gameplay distribution systems covering every value-transfer path outside GAMEOVER
- [ ] **Phase 28: Cross-Cutting Verification** - Verify recent changes, protocol invariants, edge cases, and top vulnerable functions across the full audited system
- [ ] **Phase 29: Comment/Documentation Correctness** - Verify every natspec, inline comment, storage layout, and parameter reference against audited ground truth
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
**Plans:** 3/4 plans executed

Plans:
- [ ] 26-01-PLAN.md — Core distribution audit: terminal decimator (GO-08) + handleGameOverDrain (GO-01)
- [ ] 26-02-PLAN.md — Safety properties audit: reverts (GO-05), reentrancy/CEI (GO-06), VRF fallback (GO-09)
- [x] 26-03-PLAN.md — Ancillary paths audit: deity refunds (GO-07), final sweep (GO-02), death clock (GO-03), distress mode (GO-04)
- [ ] 26-04-PLAN.md — Consolidation: cross-reference all verdicts, claimablePool consistency, update findings report

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
**Plans**: TBD

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
**Plans**: TBD

### Phase 29: Comment/Documentation Correctness
**Goal**: Every natspec comment, inline comment, storage layout comment, and constants comment in the protocol contracts matches the actual verified behavior established in Phases 26-28
**Depends on**: Phase 28 (ground truth must be established before verifying descriptions match)
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-05
**Success Criteria** (what must be TRUE):
  1. Every natspec comment on every external/public function across all protocol contracts is verified to match actual behavior, with corrections applied where discrepancies exist
  2. Every inline comment is verified against current code with no stale references from prior code versions remaining
  3. Storage layout comments match actual storage positions, constants comments match actual values, and parameter reference doc values are spot-checked against contract source
**Plans**: TBD

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
**Plans**: TBD

## Progress

**Execution Order:** Phase 26 -> 27 -> 28 -> 29 -> 30

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 26. GAMEOVER Path Audit | 3/4 | In Progress|  | - |
| 27. Payout/Claim Path Audit | v3.0 | 0/TBD | Not started | - |
| 28. Cross-Cutting Verification | v3.0 | 0/TBD | Not started | - |
| 29. Comment/Documentation Correctness | v3.0 | 0/TBD | Not started | - |
| 30. Payout Specification Document | v3.0 | 0/TBD | Not started | - |

## Deferred (v3.1+)

- **FV-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FV-02**: Formal verification of vote counting arithmetic via Halmos
- **FV-03**: Monte Carlo simulation of governance outcomes under various voter distributions

---
*Last updated: 2026-03-17 after Phase 26 planning complete -- 4 plans created*
