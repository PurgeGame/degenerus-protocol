# Requirements: v17.1 Comment Correctness Sweep

**Defined:** 2026-04-03
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Comment Sweep

- [x] **CMT-01**: All game module inline comments and NatSpec verified accurate (AdvanceModule, MintModule, MintStreakUtils, JackpotModule, LootboxModule, BoonModule, DegeneretteModule, DecimatorModule, WhaleModule, GameOverModule, PayoutUtils)
- [ ] **CMT-02**: All core game + storage inline comments and NatSpec verified accurate (DegenerusGame, DegenerusGameStorage)
- [x] **CMT-03**: All token contract inline comments and NatSpec verified accurate (BurnieCoin, BurnieCoinflip, DegenerusStonk, StakedDegenerusStonk, GNRUS)
- [x] **CMT-04**: All infrastructure contract inline comments and NatSpec verified accurate (DegenerusAdmin, DegenerusVault, DegenerusAffiliate, DegenerusDeityPass, DegenerusQuests, DegenerusJackpots, DeityBoonViewer)
- [x] **CMT-05**: All library and interface comments verified accurate; interface NatSpec matches implementations (EntropyLib, GameTimeLib, JackpotBucketLib, PriceLookupLib, BitPackingLib + all I* interfaces)
- [x] **CMT-06**: All misc contracts verified (WrappedWrappedXRP, DegenerusTraitUtils, Icons32Data)

## Consolidation

- [ ] **CON-01**: Findings consolidated into single document with LOW/INFO severities
- [ ] **CON-02**: v3.1/v3.5 prior findings verified still fixed (no regressions)

## Future Requirements

None deferred.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Auto-fixing comments | Findings doc is the deliverable; user decides what to fix |
| Code logic changes | Comment correctness only, no behavioral changes |
| Mock/test contracts | Not in audit scope |
| ContractAddresses.sol | User-managed |

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| CMT-01 | Phase 175 | Complete |
| CMT-02 | Phase 176 | Pending |
| CMT-03 | Phase 176 | Complete |
| CMT-04 | Phase 177 | Complete |
| CMT-05 | Phase 177 | Complete |
| CMT-06 | Phase 177 | Complete |
| CON-01 | Phase 178 | Pending |
| CON-02 | Phase 178 | Pending |

**Coverage:**
- v17.1 requirements: 8 total
- Mapped to phases: 8
- Unmapped: 0

---
*Requirements defined: 2026-04-03*
*Last updated: 2026-04-03 after roadmap creation*
