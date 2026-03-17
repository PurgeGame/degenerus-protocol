# Requirements: Degenerus Protocol — VRF Governance Audit v2.1

**Defined:** 2026-03-17
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v2.1 Requirements

Requirements for VRF governance security audit and doc sync.

### Governance Core Audit

- [x] **GOV-01**: Storage layout verified — `lastVrfProcessedTimestamp` at safe delegatecall slot, no collisions with existing GameStorage layout
- [x] **GOV-02**: `propose()` access control verified — admin path (DGVE >50.1%, 20h stall) and community path (0.5% sDGNRS, 7d stall) both correctly gated
- [x] **GOV-03**: `vote()` arithmetic verified — changeable votes correctly subtract old weight before adding new, no double-counting or weight leakage
- [x] **GOV-04**: Threshold decay verified — discrete daily steps match spec (6000→5000→4000→3000→2000→1000→500→0 at 24h intervals), boundary conditions clean
- [x] **GOV-05**: Execute condition verified — `approveWeight * BPS >= threshold * circulatingSnapshot AND approveWeight > rejectWeight` with no overflow or truncation
- [x] **GOV-06**: Kill condition verified — `rejectWeight > approveWeight AND rejectWeight * BPS >= threshold * circulatingSnapshot` symmetric with execute
- [x] **GOV-07**: `_executeSwap()` follows CEI — state set to Executed before external calls, reentrancy via malicious coordinator cannot trigger dual execution on sibling proposals
- [x] **GOV-08**: `_voidAllActive()` correctly voids all Active proposals except the executed one, decrements `activeProposalCount` to 0
- [x] **GOV-09**: Proposal expiry — voting on expired proposal (168h+) transitions state to Expired and reverts, `activeProposalCount` decremented
- [x] **GOV-10**: `circulatingSupply()` correctly excludes undistributed pools (sDGNRS held by SDGNRS contract) and DGNRS wrapper balance

### Cross-Contract Interactions

- [x] **XCON-01**: `lastVrfProcessedTimestamp` write paths exhaustively enumerated — only `_applyDailyRng()` and `wireVrf()`, no manipulation vector
- [x] **XCON-02**: Death clock pause verified — `anyProposalActive()` correctly pauses liveness guard in `_handleGameOverPath()`, try/catch handles Admin revert
- [x] **XCON-03**: `unwrapTo` stall guard verified — blocks during VRF stall (>20h), boundary condition at exactly 20h analyzed
- [x] **XCON-04**: `updateVrfCoordinatorAndSub` `_threeDayRngGap` removal verified — Admin governance enforces stall, no bypass via direct Game call
- [x] **XCON-05**: VRF retry timeout change verified — 18h→12h in `rngGate()`, no downstream breakage

### Vote Integrity

- [x] **VOTE-01**: sDGNRS supply frozen during VRF stall proven — all balance-mutation paths enumerated and verified blocked (no advances, no unwrapTo, soulbound)
- [x] **VOTE-02**: `circulatingSnapshot` immutable after proposal creation — cannot be manipulated by burning sDGNRS post-proposal
- [x] **VOTE-03**: `activeProposalCount` uint8 overflow analyzed — 256 proposals with `unchecked` increment, impact on `anyProposalActive()` and death clock

### War-Game Scenarios

- [x] **WAR-01**: Compromised admin key scenario — admin proposes malicious coordinator, community can reject via threshold decay, admin cannot self-approve without sDGNRS
- [x] **WAR-02**: Colluding voter cartel at low threshold — day 6 (5% threshold) with minimal sDGNRS holders, practical exploitability assessed
- [x] **WAR-03**: VRF oscillation attack — stall → governance active → VRF recovers → proposals invalidated → repeat, assess DoS potential
- [x] **WAR-04**: Creator unwrapTo timing attack — attempt vote-stacking via DGNRS→sDGNRS conversion at exact 20h boundary
- [x] **WAR-05**: Post-execute governance loop — `lastVrfProcessedTimestamp` not reset after swap, can new proposals be created immediately?
- [x] **WAR-06**: Admin spam-propose gas griefing — no per-proposer cooldown, assess `_voidAllActive` gas with many proposals

### M-02 Closure

- [x] **M02-01**: Original M-02 attack scenario (admin key compromise + VRF death = RNG control) verified as mitigated by governance
- [x] **M02-02**: Severity re-assessment — M-02 downgraded from Medium with explicit rationale documenting residual risk (if any)

### Audit Doc Sync

- [ ] **DOCS-01**: FINAL-FINDINGS-REPORT.md updated — M-02 status changed, governance findings added, plan/phase counts updated
- [ ] **DOCS-02**: KNOWN-ISSUES.md updated — `emergencyRecover` references replaced, governance-specific known issues added
- [x] **DOCS-03**: state-changing-function-audits.md updated — ~8 new entries (governance functions), ~7 updated entries (modified functions), ~5 verified-unchanged
- [ ] **DOCS-04**: parameter-reference.md updated — governance constants added (thresholds, timeouts, BPS values)
- [ ] **DOCS-05**: Tier 2 reference docs updated — economic flow, VRF lifecycle, admin function references corrected
- [ ] **DOCS-06**: Tier 3 footnotes added — minor references in delta audit docs, warden reports updated
- [ ] **DOCS-07**: Cross-reference integrity verified — no stale `emergencyRecover`, `EmergencyRecovered`, `_threeDayRngGap`, or `18 hours` references remain in audit docs

## v2.2+ Requirements

Deferred to future milestone.

- **FUZZ-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-01**: Formal verification of vote counting arithmetic via Halmos
- **SIM-01**: Monte Carlo simulation of governance outcomes under various voter distributions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Governance UI/frontend | Not in audit scope |
| Off-chain vote aggregation | On-chain only governance |
| Governance upgrade mechanisms | Contract is immutable per spec |
| Re-auditing non-governance contracts | Covered in v1.0-v2.0 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GOV-01 | Phase 24 | Complete |
| GOV-02 | Phase 24 | Complete |
| GOV-03 | Phase 24 | Complete |
| GOV-04 | Phase 24 | Complete |
| GOV-05 | Phase 24 | Complete |
| GOV-06 | Phase 24 | Complete |
| GOV-07 | Phase 24 | Complete |
| GOV-08 | Phase 24 | Complete |
| GOV-09 | Phase 24 | Complete |
| GOV-10 | Phase 24 | Complete |
| XCON-01 | Phase 24 | Complete |
| XCON-02 | Phase 24 | Complete |
| XCON-03 | Phase 24 | Complete |
| XCON-04 | Phase 24 | Complete |
| XCON-05 | Phase 24 | Complete |
| VOTE-01 | Phase 24 | Complete |
| VOTE-02 | Phase 24 | Complete |
| VOTE-03 | Phase 24 | Complete |
| WAR-01 | Phase 24 | Complete |
| WAR-02 | Phase 24 | Complete |
| WAR-03 | Phase 24 | Complete |
| WAR-04 | Phase 24 | Complete |
| WAR-05 | Phase 24 | Complete |
| WAR-06 | Phase 24 | Complete |
| M02-01 | Phase 24 | Complete |
| M02-02 | Phase 24 | Complete |
| DOCS-01 | Phase 25 | Pending |
| DOCS-02 | Phase 25 | Pending |
| DOCS-03 | Phase 25 | Complete |
| DOCS-04 | Phase 25 | Pending |
| DOCS-05 | Phase 25 | Pending |
| DOCS-06 | Phase 25 | Pending |
| DOCS-07 | Phase 25 | Pending |

**Coverage:**
- v2.1 requirements: 33 total
- Mapped to phases: 33
- Unmapped: 0

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after roadmap creation (phases 24-25)*
