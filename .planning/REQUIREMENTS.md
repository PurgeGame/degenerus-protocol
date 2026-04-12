# Requirements: Degenerus Protocol — v26.0 Bonus Jackpot Split

**Defined:** 2026-04-11
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v26.0 Requirements

Requirements for the bonus jackpot split. Each maps to roadmap phases.

### Trait Split

- [x] **TSPL-01**: Bonus drawing rolls independent traits via keccak256 domain separation from same VRF word
- [x] **TSPL-02**: Hero symbol override applies to bonus trait roll — same hero symbol, independently rerolled color from bonus entropy

### Distribution Wiring

- [x] **WIRE-01**: BURNIE coin near-future targets [lvl+1, lvl+4] instead of [lvl, lvl+4]
- [x] **WIRE-02**: Carryover ticket distribution uses bonus traits for winner selection
- [x] **WIRE-03**: Purchase-phase `payDailyCoinJackpot` rolls bonus traits independently
- [x] **WIRE-04**: Jackpot-phase `payDailyJackpotCoinAndTickets` coin portion rolls bonus traits independently
- [x] **WIRE-05**: Main ETH jackpot and 20% ticket distribution unchanged (current-level, main traits)

### Events

- [x] **EVNT-01**: `DailyWinningTraits` event emitted per daily drawing with main traits, bonus traits, and bonus target level
- [x] **EVNT-02**: Existing `JackpotBurnieWin` reused for individual bonus winners

### Verification

- [ ] **VRFY-01**: Delta audit confirms main ETH distribution path unchanged
- [x] **VRFY-02**: Gas measurement confirms headroom preserved under worst-case bonus distribution

## v25.0 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Delta Extraction

- [x] **DELTA-01**: Function-level changelog of all changed/new/deleted functions from v5.0 (phase 103) through v24.1 (phase 212)
- [x] **DELTA-02**: Contract-by-contract change classification (NEW / MODIFIED / DELETED / UNCHANGED)
- [x] **DELTA-03**: Interaction map between changed functions identifying cross-module call chains

### Adversarial Audit

- [x] **ADV-01**: Every changed/new function audited for reentrancy, access control, integer overflow, and state corruption
- [x] **ADV-02**: Storage layout verified across all DegenerusGameStorage inheritors via forge inspect
- [x] **ADV-03**: Cross-function attack chain analysis for composition bugs across the combined v6.0-v24.1 delta
- [x] **ADV-04**: Call graph audit of all changed external/public entry points

### RNG (Fresh Eyes)

- [x] **RNG-01**: VRF request/fulfillment lifecycle traced end-to-end with no reliance on prior audit conclusions
- [x] **RNG-02**: Backward trace from every RNG consumer proving word was unknown at input commitment time
- [x] **RNG-03**: Controllable-state window analysis between VRF request and fulfillment for every path
- [x] **RNG-04**: Word derivation verification — every keccak/shift/mask producing a game outcome traced to its VRF source
- [x] **RNG-05**: rngLocked mutual exclusion verification across all state-changing paths

### Pool & ETH Accounting

- [x] **POOL-01**: ETH conservation proof across the restructured pool architecture (consolidated pools, write batching, two-call split)
- [x] **POOL-02**: Pool mutation audit of all SSTORE sites touching prize pool / claimable pool / future pool
- [x] **POOL-03**: Cross-module flow verification for jackpot payouts, redemption, and sweep paths

### Findings Consolidation

- [x] **FIND-01**: All findings severity-classified (CRITICAL / HIGH / MEDIUM / LOW / INFO)
- [x] **FIND-02**: KNOWN-ISSUES.md updated with any new entries
- [x] **FIND-03**: Regression check against all prior findings (v3.3 through v24.1)

## Future Requirements

None deferred.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Separate VRF request for bonus | Creates commitment window vulnerability; same VRF word with domain separation is sufficient |
| New storage slot for bonus traits | Space exists but unnecessary -- derive inline from randWord |
| Lootbox eligibility gate | No gate change -- eligible by having future-level tickets |
| Changes to far-future BURNIE distribution | Queue-based (no traits), unaffected by split |
| Changes to early-bird lootbox jackpot | Own per-winner trait selection at lvl+1, already correct |
| Separate BonusBurnieWin event | Existing JackpotBurnieWin reused per user decision |
| Test coverage gaps | User explicitly excluded test work from this milestone |
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |
| Unchanged functions (pre-v6.0) | Covered by v5.0 Ultimate Adversarial Audit |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TSPL-01 | 218 | Complete |
| TSPL-02 | 218 | Complete |
| WIRE-01 | 218 | Complete |
| WIRE-02 | 218 | Complete |
| WIRE-03 | 218 | Complete |
| WIRE-04 | 218 | Complete |
| WIRE-05 | 218 | Complete |
| EVNT-01 | 218 | Complete |
| EVNT-02 | 218 | Complete |
| VRFY-01 | 219 | Pending |
| VRFY-02 | 219 | Complete |
| DELTA-01 | 213 | Complete |
| DELTA-02 | 213 | Complete |
| DELTA-03 | 213 | Complete |
| ADV-01 | 214 | Complete |
| ADV-02 | 214 | Complete |
| ADV-03 | 214 | Complete |
| ADV-04 | 214 | Complete |
| RNG-01 | 215 | Complete |
| RNG-02 | 215 | Complete |
| RNG-03 | 215 | Complete |
| RNG-04 | 215 | Complete |
| RNG-05 | 215 | Complete |
| POOL-01 | 216 | Complete |
| POOL-02 | 216 | Complete |
| POOL-03 | 216 | Complete |
| FIND-01 | 217 | Complete |
| FIND-02 | 217 | Complete |
| FIND-03 | 217 | Complete |

**Coverage:**
- v26.0 requirements: 11 total
- v25.0 requirements: 18 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-04-11*
*Last updated: 2026-04-12 -- EVNT-01 corrected to DailyWinningTraits, Phase 218 requirements marked Complete, VRFY-02 marked Complete*
