# Requirements: v18.0 Delta Audit & AdvanceGame Revert Safety

**Defined:** 2026-04-03
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v18.0 Requirements

### Delta Audit

- [ ] **DELTA-01**: Every function added or modified since v15.0 is traced with file:line citations and verdict (SAFE/INFO/LOW+)
- [ ] **DELTA-02**: Storage layout verified identical across all DegenerusGameStorage inheritors after repack and rngBypass changes
- [ ] **DELTA-03**: rngBypass parameter usage verified correct — all `true` callers proven internal to advanceGame, all `false` callers proven external-facing
- [ ] **DELTA-04**: ContractAddresses alignment verified — every label maps to correct deployed contract after ENDGAME_MODULE removal
- [ ] **DELTA-05**: Full `git diff` from v15.0 audit baseline to HEAD reviewed — every changed line in `contracts/` accounted for, regardless of which milestone or manual edit introduced it

### AdvanceGame Revert Safety

- [ ] **AGSAFE-01**: Every revert/require in advanceGame's direct code proven unreachable under normal operation, or intentional (NotTimeYet, RngNotReady)
- [ ] **AGSAFE-02**: Every delegatecall target (JackpotModule, MintModule, GameOverModule) audited — no revert in any function reachable from advanceGame can fire during normal game progression
- [ ] **AGSAFE-03**: Every external call from advanceGame (runDecimatorJackpot, quests, VRF) proven non-reverting or failure-tolerant
- [ ] **AGSAFE-04**: Every guard pattern (RngLocked, prizePoolFrozen, access control) in advanceGame-reachable code verified to not block internal operations
- [ ] **AGSAFE-05**: State machine transitions proven complete — no combination of flags/counters can leave advanceGame stuck in an unrecoverable state

### Regression Check

- [ ] **REG-01**: All v15.0 adversarial findings (76 functions SAFE) spot-checked against current code — no regressions from v16.0/v17.0 refactors
- [ ] **REG-02**: Foundry + Hardhat test suites pass with zero unexpected failures

## Future Requirements

None — this is an audit milestone, not a feature milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization | Separate concern, not part of correctness audit |
| Comment correctness | Already covered by v17.1 |
| New feature implementation | Audit-only milestone |
| Frontend/off-chain code | Not in audit scope |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | — | Pending |
| DELTA-02 | — | Pending |
| DELTA-03 | — | Pending |
| DELTA-04 | — | Pending |
| DELTA-05 | — | Pending |
| AGSAFE-01 | — | Pending |
| AGSAFE-02 | — | Pending |
| AGSAFE-03 | — | Pending |
| AGSAFE-04 | — | Pending |
| AGSAFE-05 | — | Pending |
| REG-01 | — | Pending |
| REG-02 | — | Pending |

**Coverage:**
- v18.0 requirements: 12 total
- Mapped to phases: 0
- Unmapped: 12 (pending roadmap)

---
*Requirements defined: 2026-04-03*
*Last updated: 2026-04-03 after initial definition*
