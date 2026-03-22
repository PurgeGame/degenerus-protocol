# Requirements: Degenerus Protocol — VRF Path Audit

**Defined:** 2026-03-22
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.7 Requirements

Requirements for VRF path audit milestone. Each maps to roadmap phases.

### VRF Core

- [x] **VRFC-01**: rawFulfillRandomWords cannot revert (except msg.sender check), gas budget sufficient for all code paths
- [x] **VRFC-02**: vrfRequestId lifecycle verified — set on request, cleared on fulfillment, retry detection correct in _finalizeRngRequest
- [x] **VRFC-03**: rngLockedFlag mutual exclusion proven airtight — no path allows daily and mid-day VRF requests to collide
- [x] **VRFC-04**: VRF 12h timeout retry path verified — stale request detection and re-request behavior correct

### Lootbox RNG

- [x] **LBOX-01**: All lootboxRngIndex mutation points mapped and verified — increment on fresh, increment on mid-day, no increment on retry
- [x] **LBOX-02**: lootboxRngWordByIndex stores correct word at correct index for every VRF fulfillment path
- [x] **LBOX-03**: EntropyLib xorshift zero-state guards verified — word==0 to word=1 at all VRF word sources
- [x] **LBOX-04**: Lootbox open entropy derivation produces unique tickets per purchase (keccak256 inputs verified)
- [x] **LBOX-05**: Full purchase-to-open lifecycle traced — ticket purchase through VRF to prize determination

### VRF Stall

- [ ] **STALL-01**: Gap backfill entropy derivation verified — keccak256(vrfWord, gapDay) produces unique per-day words
- [ ] **STALL-02**: Gap backfill manipulation window analyzed — time between VRF callback and advanceGame consumption with severity
- [ ] **STALL-03**: Gap backfill gas ceiling verified — per-iteration cost profiled, safe upper bound for gap count
- [ ] **STALL-04**: Coordinator swap state cleanup complete — all state resets confirmed, orphaned lootbox recovery correct
- [ ] **STALL-05**: Zero-seed edge case verified — lastLootboxRngWord==0 at coordinator swap cannot produce degenerate entropy
- [ ] **STALL-06**: Game-over fallback entropy verified — _getHistoricalRngFallback and prevrandao usage with C4A severity
- [ ] **STALL-07**: All game operations verified using dailyIdx timing consistently — audit whether resolveRedemptionPeriod uses block.timestamp or dailyIdx, flag any clock mismatch where stall-frozen operations continue on wall-clock time

### Testing

- [ ] **TEST-01**: Foundry fuzz tests for lootboxRngIndex lifecycle invariants
- [ ] **TEST-02**: Foundry invariant tests for VRF stall-to-recovery scenarios
- [ ] **TEST-03**: Foundry tests for gap backfill edge cases (multi-day gaps, boundary conditions)
- [ ] **TEST-04**: Halmos verification of entropy bounds (redemption roll formula consistency across 3 sites)

## Future Requirements

Deferred to future milestones.

### RNG Consumers

- **COIN-01**: Coinflip RNG consumption audit — processCoinflipPayouts entropy derivation, nudge arithmetic, claim paths
- **DAYRNG-01**: advanceGame day RNG audit — daily seed flow through all game modules (jackpot, lootbox, decimator, etc.)

### Formal Verification

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Re-audit of v1.0-v1.2 RNG findings from scratch | Regression check only; full re-audit is redundant |
| Formal verification of xorshift period | Well-studied; 20-step consumption trivially within period |
| Statistical testing of lootbox outcome distributions | Monte Carlo; separate workstream |
| Gas optimization of VRF callback | Covered in v3.5; not a v3.7 deliverable |
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| VRFC-01 | Phase 63 | Complete |
| VRFC-02 | Phase 63 | Complete |
| VRFC-03 | Phase 63 | Complete |
| VRFC-04 | Phase 63 | Complete |
| LBOX-01 | Phase 64 | Complete |
| LBOX-02 | Phase 64 | Complete |
| LBOX-03 | Phase 64 | Complete |
| LBOX-04 | Phase 64 | Complete |
| LBOX-05 | Phase 64 | Complete |
| STALL-01 | Phase 65 | Pending |
| STALL-02 | Phase 65 | Pending |
| STALL-03 | Phase 65 | Pending |
| STALL-04 | Phase 65 | Pending |
| STALL-05 | Phase 65 | Pending |
| STALL-06 | Phase 65 | Pending |
| STALL-07 | Phase 65 | Pending |
| TEST-01 | Phase 66 | Pending |
| TEST-02 | Phase 66 | Pending |
| TEST-03 | Phase 66 | Pending |
| TEST-04 | Phase 66 | Pending |

**Coverage:**
- v3.7 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-03-22*
*Last updated: 2026-03-22 after roadmap creation -- traceability populated*
