# Requirements: Degenerus Protocol Audit

**Defined:** 2026-03-20
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.3 Requirements

Requirements for Gambling Burn Audit + Full Adversarial Sweep.

### Delta Audit (Gambling Burn)

- [x] **DELTA-01**: Redemption accounting -- verify `pendingRedemptionEthValue` segregation reconciles at submit, resolve, and claim
- [x] **DELTA-02**: Cross-contract interaction audit -- 4-contract state consistency (sDGNRS->Game->Coinflip->AdvanceModule) + reentrancy verification
- [x] **DELTA-03**: Confirm or refute CP-08 -- `_deterministicBurnFrom` double-spend via missing `pendingRedemptionEthValue` deduction
- [x] **DELTA-04**: Confirm or refute CP-06 -- stuck claims at game-over (`_gameOverEntropy` missing `resolveRedemptionPeriod`)
- [x] **DELTA-05**: Confirm or refute Seam-1 -- `DGNRS.burn()` fund trap (gambling claim recorded under contract address)
- [x] **DELTA-06**: Confirm or refute CP-02 -- `periodIndex == 0` sentinel collision on first game day
- [x] **DELTA-07**: Confirm or refute CP-07 -- coinflip resolution dependency creating second stuck-claim vector

### Redemption Correctness

- [x] **CORR-01**: Full redemption lifecycle trace -- submit->resolve->claim state machine verification
- [x] **CORR-02**: Segregation solvency invariant -- reserved ETH/BURNIE never exceeds contract holdings
- [x] **CORR-03**: CEI compliance -- `claimRedemption()` deletes claim before external calls, all paths verified
- [x] **CORR-04**: Period state machine -- monotonicity, resolution ordering, 50% supply cap enforcement
- [x] **CORR-05**: `burnWrapped()` supply invariant -- sDGNRS burned equals DGNRS burned

### Invariant Tests

- [x] **INV-01**: Foundry invariant -- segregated ETH never exceeds contract balance
- [x] **INV-02**: Foundry invariant -- no double-claim (claim deleted before payout)
- [x] **INV-03**: Foundry invariant -- period index monotonically increases
- [x] **INV-04**: Foundry invariant -- totalSupply consistent after burn/claim sequences
- [x] **INV-05**: Foundry invariant -- 50% cap correctly enforced per period
- [x] **INV-06**: Foundry invariant -- roll bounds always [25, 175]
- [x] **INV-07**: Foundry invariant -- pendingRedemptionEthValue + pendingRedemptionBurnie track matches sum of individual claims

### Adversarial Sweep

- [x] **ADV-01**: Warden simulation -- fresh-eyes read of all 29 contracts targeting High/Medium C4A findings
- [x] **ADV-02**: Cross-contract composability attacks -- multi-contract interaction sequences that bypass individual contract guards
- [x] **ADV-03**: Access control audit of new entry points -- `claimCoinflipsForRedemption`, `burnForSdgnrs`, `resolveRedemptionPeriod`, `hasPendingRedemptions`

### Economic Analysis

- [x] **ECON-01**: Rational actor strategy catalog -- timing attacks, cap manipulation, stale accumulation, multi-address splitting with cost-benefit
- [x] **ECON-02**: Bank-run scenario analysis -- what happens when many players burn simultaneously near supply cap

### Gas Optimization

- [x] **GAS-01**: Dead variable check -- confirm all 7 new state variables in sDGNRS are actually needed
- [x] **GAS-02**: Storage packing analysis -- identify packing opportunities (e.g. `redemptionPeriodIndex` uint48)
- [x] **GAS-03**: Gas snapshot baseline -- `forge snapshot` for all redemption functions
- [x] **GAS-04**: Unneeded variable elimination -- implement removals identified by GAS-01

### Documentation

- [x] **DOC-01**: NatSpec correctness for all 6 changed files
- [x] **DOC-02**: Bit allocation map comment in `rngGate()` documenting which bits each RNG consumer uses
- [x] **DOC-03**: Error name fix -- `claimCoinflipsForRedemption` uses `OnlyBurnieCoin` (misleading)
- [ ] **DOC-04**: Full audit doc sync -- update all 13+ audit reference docs for gambling burn mechanism

## Prior Milestone Requirements (v3.2)

All complete. See MILESTONES.md for details.

- ✓ RNG-01 through RNG-04: RNG delta audit (Phase 38)
- ✓ CMT-01 through CMT-07: Comment correctness fresh scan (Phases 39-41, 43)
- ✓ GOV-01 through GOV-03: VRF governance fresh eyes (Phase 42)

## Future Requirements

### Deferred (v3.3+)

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **RNG-V01**: Roll derivation correctness -- verify `(currentWord >> 8) % 151 + 25` bit allocation and uniformity
- **EV-01**: Analytical EV proof -- mathematical proof ETH gamble is fair + BURNIE EV formula
- **EV-02**: Monte Carlo verification script -- independent numerical check (~100 lines)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Slither full-suite scan | User deferred -- warden simulation provides higher-value coverage |
| "What if" scenario sweep | User deferred -- rational actor catalog covers strategic edge cases |
| stETH rounding analysis | Low priority -- 1-2 wei edge case unlikely to produce C4A findings |
| Re-audit VRF delivery mechanism | Covered in v1.0-v1.2; mechanism unchanged |
| Re-audit governance system | Covered in v2.1 with 26 verdicts; no governance code changed |
| Formal verification (Halmos/Certora) | Deferred per PROJECT.md |
| Full fuzz suite for all 29 contracts | Weeks of work; diminishing returns beyond invariant tests on new code |
| Re-run comment audit on unchanged contracts | v3.1 + v3.2 already covered 29 contracts with 114 findings |
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | Phase 44 | Complete |
| DELTA-02 | Phase 44 | Complete |
| DELTA-03 | Phase 44 | Complete |
| DELTA-04 | Phase 44 | Complete |
| DELTA-05 | Phase 44 | Complete |
| DELTA-06 | Phase 44 | Complete |
| DELTA-07 | Phase 44 | Complete |
| CORR-01 | Phase 44 | Complete |
| CORR-02 | Phase 44 | Complete |
| CORR-03 | Phase 44 | Complete |
| CORR-04 | Phase 44 | Complete |
| CORR-05 | Phase 44 | Complete |
| INV-01 | Phase 45 | Complete |
| INV-02 | Phase 45 | Complete |
| INV-03 | Phase 45 | Complete |
| INV-04 | Phase 45 | Complete |
| INV-05 | Phase 45 | Complete |
| INV-06 | Phase 45 | Complete |
| INV-07 | Phase 45 | Complete |
| ADV-01 | Phase 46 | Complete |
| ADV-02 | Phase 46 | Complete |
| ADV-03 | Phase 46 | Complete |
| ECON-01 | Phase 46 | Complete |
| ECON-02 | Phase 46 | Complete |
| GAS-01 | Phase 47 | Complete |
| GAS-02 | Phase 47 | Complete |
| GAS-03 | Phase 47 | Complete |
| GAS-04 | Phase 47 | Complete |
| DOC-01 | Phase 48 | Complete |
| DOC-02 | Phase 48 | Complete |
| DOC-03 | Phase 48 | Complete |
| DOC-04 | Phase 48 | Pending |

**Coverage:**
- v3.3 requirements: 32 total
- Mapped to phases: 32
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after roadmap creation (traceability added)*
