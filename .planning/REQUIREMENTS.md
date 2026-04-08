# Requirements: v22.0 Delta Audit & Payout Reference Rewrite

## Delta Audit

- [x] **AUDIT-01**: Every variable touched by _processDailyEth changes (splitMode, isJackpotPhase, skip-split detection) is traced through all caller paths and verified correct
- [x] **AUDIT-02**: Non-daily callers (runTerminalJackpot, _runJackpotEthFlow) produce identical payout results to the deleted _distributeJackpotEth/_processOneBucket
- [x] **AUDIT-03**: Skip-split path (totalWinners <= 160) produces identical results to SPLIT_CALL1+SPLIT_CALL2 combined
- [x] **AUDIT-04**: resumeEthPool is never written when splitMode=SPLIT_NONE and never stale across level boundaries
- [x] **AUDIT-05**: isJackpotPhase=false callers never award whale passes or DGNRS
- [x] **AUDIT-06**: Deleted code (_distributeJackpotEth, _processOneBucket, JackpotEthCtx) has no remaining references

## Gas Ceiling

- [x] **GAS-01**: Derive theoretical worst-case gas for advanceGame STAGE_JACKPOT_DAILY_STARTED (call 1) — must be < 16M
- [x] **GAS-02**: Derive theoretical worst-case gas for advanceGame STAGE_JACKPOT_ETH_RESUME (call 2) — must be < 16M
- [x] **GAS-03**: Derive theoretical worst-case gas for skip-split path (all 4 buckets in one call, <= 160 winners) — must be < 16M
- [x] **GAS-04**: Verify skip-split threshold (160) is the correct cutoff where single-call gas stays safe

## Payout Reference

- [ ] **DOC-01**: JACKPOT-PAYOUT-REFERENCE.md rewritten from scratch, organized by jackpot type (daily normal, daily final, x10/x100, early-burn, early-bird lootbox, terminal, decimator, BAF, BURNIE coin)
- [ ] **DOC-02**: Each jackpot type section covers: trigger, pool source, winner selection, share allocation, split behavior, payout mechanics, events emitted, pool accounting
- [ ] **DOC-03**: All references use current function names (_processDailyEth, splitMode, isJackpotPhase) — no stale names
- [ ] **DOC-04**: JACKPOT-EVENT-CATALOG.md updated to reflect unified function if needed

## Traceability

| REQ-ID | Phase |
|--------|-------|
| AUDIT-01..06 | 199 |
| GAS-01..04 | 199 |
| DOC-01..04 | 200 |
