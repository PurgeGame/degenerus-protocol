# Requirements: Degenerus Protocol — v3.6 VRF Stall Resilience

**Defined:** 2026-03-22
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.6 Requirements

### RNG Gap Backfill

- [x] **GAP-01**: When advanceGame detects dailyIdx gap (day > dailyIdx+1), backfill rngWordByDay for each missed day using keccak256(vrfWord, gapDay)
- [x] **GAP-02**: Backfill lootboxRngWordByIndex for any orphaned indices (index had no VRF response)
- [x] **GAP-03**: Clear midDayTicketRngPending during coordinator swap or on first post-gap advance
- [x] **GAP-04**: Coinflip stakes on gap days resolve normally via backfilled RNG words (no orphaned balances)
- [x] **GAP-05**: Lootboxes assigned to orphaned indices can be opened via backfilled RNG words (no bricked lootboxes)

### Coordinator Swap Cleanup

- [ ] **SWAP-01**: updateVrfCoordinatorAndSub properly handles all stale state from the failed coordinator
- [ ] **SWAP-02**: totalFlipReversals handling documented (carry-over vs reset — design decision)

### Testing

- [ ] **TEST-01**: Foundry test simulating full stall→swap→resume cycle with gap day backfill
- [ ] **TEST-02**: Test that coinflip claims work across gap days
- [ ] **TEST-03**: Test that lootbox opens work after orphaned index backfill

### Audit

- [ ] **AUD-01**: All changes audited for correctness — no new attack vectors introduced
- [ ] **AUD-02**: Consolidated findings documented

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-day catch-up processing | Gap days only need RNG backfill, not full advanceGame processing |
| Nudge refunds for gap days | Nudges carry over — design choice, not a bug |
| Frontend handling of stall UX | Not in audit scope |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GAP-01 | Phase 59 | Complete |
| GAP-02 | Phase 59 | Complete |
| GAP-03 | Phase 59 | Complete |
| GAP-04 | Phase 59 | Complete |
| GAP-05 | Phase 59 | Complete |
| SWAP-01 | Phase 60 | Pending |
| SWAP-02 | Phase 60 | Pending |
| TEST-01 | Phase 61 | Pending |
| TEST-02 | Phase 61 | Pending |
| TEST-03 | Phase 61 | Pending |
| AUD-01 | Phase 62 | Pending |
| AUD-02 | Phase 62 | Pending |

**Coverage:**
- v3.6 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0

---
*Requirements defined: 2026-03-22*
