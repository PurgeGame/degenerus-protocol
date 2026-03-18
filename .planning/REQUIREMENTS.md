# Requirements: Degenerus Protocol v3.0

**Defined:** 2026-03-17
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.0 Requirements

### GAMEOVER Path Audit

- [x] **GO-01**: `handleGameOverDrain` audited — accumulator distribution, decimator 10%, terminal jackpot 90%, 50/50 vault/DGNRS split on sweep verified correct
- [x] **GO-02**: `handleFinalSweep` audited — 30-day claim window, claimablePool zeroing, unclaimed forfeiture logic verified correct
- [x] **GO-03**: Death clock trigger conditions audited — level 0 (365d) and level 1+ (120d) thresholds verified, all activation paths mapped
- [x] **GO-04**: Distress mode activation audited — effects on lootbox routing and ticket bonuses verified, activation/deactivation conditions mapped
- [x] **GO-05**: Every `require`/`revert` on GAMEOVER path audited — no revert can block payout execution
- [x] **GO-06**: Reentrancy and state ordering on GAMEOVER path audited — no path allows funds stuck or double-paid
- [x] **GO-07**: Deity pass refunds on early GAMEOVER (levels 0-9) audited — refund calculations and claimability verified
- [x] **GO-08**: Terminal decimator integration audited — new code path through GAMEOVER verified, interaction with existing accumulator/jackpot logic correct
- [x] **GO-09**: No-RNG-available GAMEOVER path audited — fallback behavior when VRF is unavailable during terminal distribution, deterministic/default selection logic, fund safety verified

### Payout/Claim Path Audit

- [x] **PAY-01**: Daily jackpot (purchase phase) audited — ETH distribution formula, winner selection, claim mechanism verified
- [x] **PAY-02**: Daily jackpot (jackpot phase) audited — 5-day draw sequence, prize scaling, unclaimed handling verified
- [x] **PAY-03**: BAF normal scatter payout audited — trigger conditions, recipient selection, payout calculation verified
- [x] **PAY-04**: BAF century scatter payout audited — century trigger, enhanced payout calculation, distribution verified
- [x] **PAY-05**: Decimator normal claims audited — `claimDecimatorJackpot` path, round tracking, `lastDecClaimRound` logic verified
- [x] **PAY-06**: Decimator x00 claims audited — century decimator claim path, enhanced payout, eligibility verified
- [x] **PAY-07**: Coinflip deposit/win/loss paths audited — `claimCoinflips`, `claimCoinflipsFromBurnie`, auto-rebuy carry verified
- [x] **PAY-08**: Coinflip bounty system audited — bounty trigger, DGNRS gating (50k bet, 20k pool), payout verified
- [ ] **PAY-09**: Lootbox rewards audited — whale passes, lazy passes, deity passes, future tickets, BURNIE payouts verified
- [ ] **PAY-10**: Quest rewards and streak bonuses audited — trigger conditions, reward calculations, streak mechanics verified
- [ ] **PAY-11**: Affiliate commissions audited — 3-tier system, taper schedule, ETH and DGNRS claim paths verified
- [ ] **PAY-12**: stETH yield distribution audited — 50/25/25 split, accumulator milestone payouts verified
- [ ] **PAY-13**: Accumulator milestone payouts audited — milestone thresholds, payout triggers, distribution verified
- [ ] **PAY-14**: sDGNRS `burn()` audited — ETH/stETH/BURNIE proportional redemption math verified
- [ ] **PAY-15**: DGNRS wrapper `burn()` audited — delegation to sDGNRS, unwrap mechanics verified
- [x] **PAY-16**: Ticket conversion and futurepool mechanics audited — conversion formula, futurepool allocation, rollover verified
- [ ] **PAY-17**: Advance bounty system audited — trigger, payout calculation, claim mechanism verified
- [x] **PAY-18**: WWXRP consolation prizes audited — distribution logic, value transfer paths verified
- [x] **PAY-19**: Coinflip recycling and boons audited — recycled BURNIE flow, boon mechanics verified

### Recent Changes Verification

- [ ] **CHG-01**: All commits in last month verified — git log reviewed, each change assessed for correctness
- [ ] **CHG-02**: VRF governance mechanism verified — propose/vote/execute paths still correct after recent changes
- [ ] **CHG-03**: Deity non-transferability changes verified — soulbound enforcement, edge cases checked
- [ ] **CHG-04**: Parameter changes verified — any constant modifications cross-referenced against parameter reference doc

### Comment/Documentation Correctness

- [ ] **DOC-01**: Every natspec comment on every external/public function verified — description matches actual behavior
- [ ] **DOC-02**: Every inline comment verified — no stale comments from prior code versions
- [ ] **DOC-03**: Storage layout comments verified — comments match actual storage positions
- [ ] **DOC-04**: Constants comments verified — comment values match actual contract values
- [ ] **DOC-05**: Parameter reference doc spot-checked — every value verified against contract source

### Invariant Verification

- [ ] **INV-01**: `claimablePool <= address(this).balance + stETH balance` verified — all mutation paths checked, no violation possible
- [ ] **INV-02**: Pool accounting verified — all pool additions and subtractions balance across all paths
- [ ] **INV-03**: sDGNRS total supply = sum of all balances (including pool-held) verified
- [ ] **INV-04**: BURNIE mint/burn accounting verified — coinflip lifecycle accounting correct
- [ ] **INV-05**: No permanently unclaimable funds path exists (outside intentional expiry) — verified across all systems

### Edge Cases & Griefing

- [ ] **EDGE-01**: GAMEOVER at level 0, level 1, level 100 analyzed — behavior at each boundary documented and verified correct
- [ ] **EDGE-02**: Single-player GAMEOVER scenario analyzed — all distribution paths handle 1 player correctly
- [ ] **EDGE-03**: `advanceGame` gas griefing and state manipulation analyzed — no blocking vector exists
- [ ] **EDGE-04**: Decimator `lastDecClaimRound` overwrite timing analyzed — no claim bricking possible
- [ ] **EDGE-05**: Coinflip auto-rebuy carry during known-RNG windows analyzed — no extraction possible
- [ ] **EDGE-06**: Affiliate self-referral loop analysis — cannot extract more than intended
- [ ] **EDGE-07**: Rounding accumulation analysis — no path where rounding compounds to material amounts

### Payout Specification Document

- [ ] **SPEC-01**: Payout specification HTML document created at `audit/PAYOUT-SPECIFICATION.html`
- [ ] **SPEC-02**: All 17 distribution systems covered with trigger, source, calculation, recipients, claim mechanism, currency
- [ ] **SPEC-03**: Flow diagrams included for every distribution system showing money path
- [ ] **SPEC-04**: Edge cases documented for each system (empty pools, single player, max values)
- [ ] **SPEC-05**: Contract file:line references included for every relevant code path
- [ ] **SPEC-06**: All formulas use variable names matching contract code exactly

### Top 10 Vulnerable Functions

- [ ] **VULN-01**: All state-changing functions ranked by vulnerability likelihood using weighted criteria (value moved, complexity, interaction count, prior coverage gaps)
- [ ] **VULN-02**: Top 10 most vulnerable functions receive deep adversarial audit — each with dedicated finding or explicit PASS verdict
- [ ] **VULN-03**: Vulnerability ranking document produced with rationale for each ranking position, suitable for manual review

## v3.1 Requirements (Deferred)

### Formal Verification

- **FV-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FV-02**: Formal verification of vote counting arithmetic via Halmos
- **FV-03**: Monte Carlo simulation of governance outcomes under various voter distributions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Frontend code | Not in audit scope per PROJECT.md |
| Off-chain infrastructure | VRF coordinator is external |
| Gas optimization | Already covered in v2.0, C4A QA findings are low-cost |
| Governance UI | Not in audit scope |
| Contract upgrade mechanisms | Contracts are immutable per spec |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GO-01 | Phase 26 | Complete |
| GO-02 | Phase 26 | Complete |
| GO-03 | Phase 26 | Complete |
| GO-04 | Phase 26 | Complete |
| GO-05 | Phase 26 | Complete |
| GO-06 | Phase 26 | Complete |
| GO-07 | Phase 26 | Complete |
| GO-08 | Phase 26 | Complete |
| GO-09 | Phase 26 | Complete |
| PAY-01 | Phase 27 | Complete |
| PAY-02 | Phase 27 | Complete |
| PAY-03 | Phase 27 | Complete |
| PAY-04 | Phase 27 | Complete |
| PAY-05 | Phase 27 | Complete |
| PAY-06 | Phase 27 | Complete |
| PAY-07 | Phase 27 | Complete |
| PAY-08 | Phase 27 | Complete |
| PAY-09 | Phase 27 | Pending |
| PAY-10 | Phase 27 | Pending |
| PAY-11 | Phase 27 | Pending |
| PAY-12 | Phase 27 | Pending |
| PAY-13 | Phase 27 | Pending |
| PAY-14 | Phase 27 | Pending |
| PAY-15 | Phase 27 | Pending |
| PAY-16 | Phase 27 | Complete |
| PAY-17 | Phase 27 | Pending |
| PAY-18 | Phase 27 | Complete |
| PAY-19 | Phase 27 | Complete |
| CHG-01 | Phase 28 | Pending |
| CHG-02 | Phase 28 | Pending |
| CHG-03 | Phase 28 | Pending |
| CHG-04 | Phase 28 | Pending |
| INV-01 | Phase 28 | Pending |
| INV-02 | Phase 28 | Pending |
| INV-03 | Phase 28 | Pending |
| INV-04 | Phase 28 | Pending |
| INV-05 | Phase 28 | Pending |
| EDGE-01 | Phase 28 | Pending |
| EDGE-02 | Phase 28 | Pending |
| EDGE-03 | Phase 28 | Pending |
| EDGE-04 | Phase 28 | Pending |
| EDGE-05 | Phase 28 | Pending |
| EDGE-06 | Phase 28 | Pending |
| EDGE-07 | Phase 28 | Pending |
| VULN-01 | Phase 28 | Pending |
| VULN-02 | Phase 28 | Pending |
| VULN-03 | Phase 28 | Pending |
| DOC-01 | Phase 29 | Pending |
| DOC-02 | Phase 29 | Pending |
| DOC-03 | Phase 29 | Pending |
| DOC-04 | Phase 29 | Pending |
| DOC-05 | Phase 29 | Pending |
| SPEC-01 | Phase 30 | Pending |
| SPEC-02 | Phase 30 | Pending |
| SPEC-03 | Phase 30 | Pending |
| SPEC-04 | Phase 30 | Pending |
| SPEC-05 | Phase 30 | Pending |
| SPEC-06 | Phase 30 | Pending |

**Coverage:**
- v3.0 requirements: 58 total
- Mapped to phases: 58
- Unmapped: 0

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after roadmap creation -- all 57 requirements mapped to phases*
