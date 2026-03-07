# Requirements: Degenerus Protocol — Function-Level Exhaustive Audit

**Defined:** 2026-03-07
**Core Value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor can extract value beyond what the game mechanics intend.

## v7.0 Requirements

Requirements for exhaustive function-level audit. Each maps to roadmap phases.

### Audit Infrastructure

- [ ] **INFRA-01**: JSON schema defined for function-level audit reports (signature, visibility, params, state reads/writes, callers, callees, invariants, NatSpec verdict, gas flags, overall verdict)
- [ ] **INFRA-02**: Cross-reference index mapping every function to all callers and callees across the protocol
- [ ] **INFRA-03**: State mutation map showing which functions write which storage slots

### Core Game

- [ ] **CORE-01**: DegenerusGame.sol — every function audited with JSON + markdown report
- [ ] **CORE-02**: DegenerusGameStorage.sol — every storage variable documented and verified against usage

### Delegatecall Modules

- [x] **MOD-01**: DegenerusGameAdvanceModule.sol — every function audited with JSON + markdown report
- [x] **MOD-02**: DegenerusGameMintModule.sol — every function audited with JSON + markdown report
- [x] **MOD-03**: DegenerusGameJackpotModule.sol — every function audited with JSON + markdown report
- [x] **MOD-04**: DegenerusGameEndgameModule.sol — every function audited with JSON + markdown report
- [x] **MOD-05**: DegenerusGameLootboxModule.sol — every function audited with JSON + markdown report
- [x] **MOD-06**: DegenerusGameGameOverModule.sol — every function audited with JSON + markdown report
- [ ] **MOD-07**: DegenerusGameWhaleModule.sol — every function audited with JSON + markdown report
- [ ] **MOD-08**: DegenerusGameDegeneretteModule.sol — every function audited with JSON + markdown report
- [x] **MOD-09**: DegenerusGameBoonModule.sol — every function audited with JSON + markdown report
- [x] **MOD-10**: DegenerusGameDecimatorModule.sol — every function audited with JSON + markdown report
- [x] **MOD-11**: DegenerusGameMintStreakUtils.sol — every function audited with JSON + markdown report
- [x] **MOD-12**: DegenerusGamePayoutUtils.sol — every function audited with JSON + markdown report

### Token & Economics

- [x] **TOKEN-01**: BurnieCoin.sol — every function audited with JSON + markdown report
- [x] **TOKEN-02**: BurnieCoinflip.sol — every function audited with JSON + markdown report
- [x] **TOKEN-03**: DegenerusVault.sol — every function audited with JSON + markdown report
- [x] **TOKEN-04**: DegenerusStonk.sol — every function audited with JSON + markdown report

### Pass & Viewer

- [ ] **PASS-01**: DegenerusDeityPass.sol — every function audited with JSON + markdown report
- [ ] **PASS-02**: DeityBoonViewer.sol — every function audited with JSON + markdown report

### Social & Rewards

- [ ] **SOCIAL-01**: DegenerusAffiliate.sol — every function audited with JSON + markdown report
- [ ] **SOCIAL-02**: DegenerusQuests.sol — every function audited with JSON + markdown report
- [ ] **SOCIAL-03**: DegenerusJackpots.sol — every function audited with JSON + markdown report

### Admin & Support

- [ ] **ADMIN-01**: DegenerusAdmin.sol — every function audited with JSON + markdown report
- [ ] **ADMIN-02**: DegenerusTraitUtils.sol — every function audited with JSON + markdown report
- [ ] **ADMIN-03**: ContractAddresses.sol — every constant verified against deploy order and usage
- [ ] **ADMIN-04**: Icons32Data.sol — audited with JSON + markdown report
- [ ] **ADMIN-05**: WrappedWrappedXRP.sol — every function audited with JSON + markdown report

### Libraries

- [x] **LIB-01**: BitPackingLib.sol — every function audited with JSON + markdown report
- [x] **LIB-02**: EntropyLib.sol — every function audited with JSON + markdown report
- [x] **LIB-03**: GameTimeLib.sol — every function audited with JSON + markdown report
- [x] **LIB-04**: PriceLookupLib.sol — every function audited with JSON + markdown report
- [x] **LIB-05**: JackpotBucketLib.sol — every function audited with JSON + markdown report

### Interfaces

- [ ] **IFACE-01**: Every interface function signature verified to match its implementation
- [ ] **IFACE-02**: Every interface NatSpec verified to match implementation behavior

### Cross-Contract Verification

- [ ] **XREF-01**: Complete call graph with context annotations (delegatecall vs direct, internal vs external)
- [ ] **XREF-02**: ETH flow map — every path ETH enters, moves within, or exits the protocol
- [ ] **XREF-03**: State mutation matrix — which modules can write which storage slots via delegatecall

### Gas Optimization

- [ ] **GAS-01**: Impossible condition checks flagged across all contracts
- [ ] **GAS-02**: Redundant storage reads and unnecessary computation flagged

### Prior Verification

- [ ] **VERIFY-01**: v1-v6 critical claims spot-checked against current code
- [ ] **VERIFY-02**: Game theory paper intent cross-referenced for ambiguous functions

### Synthesis

- [ ] **SYNTH-01**: Aggregate findings report with severity ratings (Critical/High/Medium/Low/QA)
- [ ] **SYNTH-02**: Executive summary with confidence assessment and honest limitations

## Future Requirements

None — this milestone covers exhaustive scope.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization fixes | Flag-only — fixes are a separate concern/milestone |
| Mock contracts | Test infrastructure, not production attack surface |
| Test helper contracts | Test infrastructure only (PriceLookupTester.sol) |
| Deploy scripts | Operational, not testing surface |
| Foundry/Halmos test files | Test code, not production |
| New test writing | This milestone produces audit reports, not new tests |
| Code changes/fixes | Report findings only — fixes require separate review cycle |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 48 | Pending |
| INFRA-02 | Phase 48 | Pending |
| INFRA-03 | Phase 48 | Pending |
| CORE-01 | Phase 49 | Pending |
| CORE-02 | Phase 49 | Pending |
| MOD-01 | Phase 50 | Complete |
| MOD-02 | Phase 50 | Complete |
| MOD-03 | Phase 50 | Complete |
| MOD-04 | Phase 51 | Complete |
| MOD-05 | Phase 51 | Complete |
| MOD-06 | Phase 51 | Complete |
| MOD-07 | Phase 52 | Pending |
| MOD-08 | Phase 52 | Pending |
| MOD-09 | Phase 52 | Complete |
| MOD-10 | Phase 52 | Complete |
| MOD-11 | Phase 53 | Complete |
| MOD-12 | Phase 53 | Complete |
| TOKEN-01 | Phase 54 | Complete |
| TOKEN-02 | Phase 54 | Complete |
| TOKEN-03 | Phase 54 | Complete |
| TOKEN-04 | Phase 54 | Complete |
| PASS-01 | Phase 55 | Pending |
| PASS-02 | Phase 55 | Pending |
| SOCIAL-01 | Phase 55 | Pending |
| SOCIAL-02 | Phase 55 | Pending |
| SOCIAL-03 | Phase 55 | Pending |
| IFACE-01 | Phase 55 | Pending |
| IFACE-02 | Phase 55 | Pending |
| ADMIN-01 | Phase 56 | Pending |
| ADMIN-02 | Phase 56 | Pending |
| ADMIN-03 | Phase 56 | Pending |
| ADMIN-04 | Phase 56 | Pending |
| ADMIN-05 | Phase 56 | Pending |
| LIB-01 | Phase 53 | Complete |
| LIB-02 | Phase 53 | Complete |
| LIB-03 | Phase 53 | Complete |
| LIB-04 | Phase 53 | Complete |
| LIB-05 | Phase 53 | Complete |
| XREF-01 | Phase 57 | Pending |
| XREF-02 | Phase 57 | Pending |
| XREF-03 | Phase 57 | Pending |
| GAS-01 | Phase 57 | Pending |
| GAS-02 | Phase 57 | Pending |
| VERIFY-01 | Phase 57 | Pending |
| VERIFY-02 | Phase 57 | Pending |
| SYNTH-01 | Phase 58 | Pending |
| SYNTH-02 | Phase 58 | Pending |

**Coverage:**
- v7.0 requirements: 47 total
- Mapped to phases: 47
- Unmapped: 0

---
*Requirements defined: 2026-03-07*
*Last updated: 2026-03-07 after roadmap creation*
