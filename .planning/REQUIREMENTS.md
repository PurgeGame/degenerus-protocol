# Requirements: v16.0 Module Consolidation & Storage Repack

**Defined:** 2026-04-02
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Storage Repack

- [ ] **STOR-01**: ticketsFullyProcessed and gameOverPossible moved from slot 1 to slot 0 (filling 2-byte padding to 32/32)
- [ ] **STOR-02**: currentPrizePool downsized from uint256 (slot 2) to uint128 packed into slot 1
- [ ] **STOR-03**: All slot header comments in DegenerusGameStorage.sol match actual layout
- [ ] **STOR-04**: All `_get`/`_set` helpers for currentPrizePool updated for uint128 packing
- [ ] **STOR-05**: forge inspect confirms identical layout across DegenerusGameStorage, DegenerusGame, and all modules

## Module Redistribution

- [ ] **MOD-01**: rewardTopAffiliate inlined directly in AdvanceModule (no delegatecall)
- [x] **MOD-02**: runRewardJackpots + all private helpers moved to JackpotModule
- [x] **MOD-03**: claimWhalePass moved to JackpotModule
- [x] **MOD-04**: DegenerusGame delegatecall targets updated (claimWhalePass -> JackpotModule)
- [x] **MOD-05**: EndgameModule contract, interface, and GAME_ENDGAME_MODULE address deleted
- [x] **MOD-06**: All references to EndgameModule removed (imports, comments, NatSpec)

## Verification

- [ ] **VER-01**: All hardcoded slot offsets in Foundry tests updated for new layout
- [ ] **VER-02**: Full test suite green (Hardhat + Foundry)
- [ ] **VER-03**: Delta audit of all moved/modified functions confirms behavioral equivalence

## Future Requirements

None deferred.

## Out of Scope

- Gas optimization beyond the storage repack (no new packing opportunities this milestone)
- Refactoring internal logic of moved functions (verbatim copy, no behavioral changes)
- ContractAddresses.sol management (user-managed, GAME_ENDGAME_MODULE removal only)

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| STOR-01 | 168 | Pending |
| STOR-02 | 168 | Pending |
| STOR-03 | 168 | Pending |
| STOR-04 | 168 | Pending |
| STOR-05 | 168 | Pending |
| MOD-01 | 169 | Pending |
| MOD-02 | 170 | Complete |
| MOD-03 | 171 | Complete |
| MOD-04 | 171 | Complete |
| MOD-05 | 171 | Complete |
| MOD-06 | 171 | Complete |
| VER-01 | 172 | Pending |
| VER-02 | 172 | Pending |
| VER-03 | 172 | Pending |
