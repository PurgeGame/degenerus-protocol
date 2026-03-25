# Requirements: Degenerus Protocol — Ultimate Adversarial Audit

**Defined:** 2026-03-25
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v5.0 Requirements

Requirements for exhaustive three-agent adversarial audit. Each maps to roadmap phases.

### Coverage (Taskmaster)

- [x] **COV-01**: Every state-changing function (external, public, internal, private) across all 29 protocol contracts has a Taskmaster-built checklist entry
- [x] **COV-02**: Every function checklist entry is signed off with: analyzed (Y/N), call tree complete (Y/N), storage writes complete (Y/N), cache check done (Y/N)
- [x] **COV-03**: No unit advances to Skeptic review until Taskmaster gives PASS verdict with 100% coverage

### Attack (Mad Genius)

- [x] **ATK-01**: Every function has a fully-expanded recursive call tree with line numbers for every call site
- [x] **ATK-02**: Every function has a complete storage-write map listing every variable written by any function in its transitive call graph
- [x] **ATK-03**: Every function has an explicit cached-local-vs-storage check identifying all (ancestor_local, descendant_write) pairs
- [x] **ATK-04**: Every function is attacked from all applicable angles: state coherence, RNG manipulation, cross-contract desync, rare paths, access control, ordering, silent failures, economic/MEV, griefing
- [x] **ATK-05**: Every finding classified as VULNERABLE or INVESTIGATE includes exact line numbers, a concrete attack scenario, and proof-of-concept steps

### Validation (Skeptic)

- [x] **VAL-01**: Every VULNERABLE and INVESTIGATE finding from the Mad Genius has a Skeptic verdict: CONFIRMED, FALSE POSITIVE, or DOWNGRADE TO INFO
- [x] **VAL-02**: Every FALSE POSITIVE dismissal cites the specific line(s) that prevent the attack
- [x] **VAL-03**: Every CONFIRMED finding has a severity rating (CRITICAL / HIGH / MEDIUM / LOW / INFO)
- [x] **VAL-04**: Skeptic independently verifies the Taskmaster's function checklist for each unit — confirms no state-changing functions were omitted from the coverage checklist

### Unit Execution

- [x] **UNIT-01**: Unit 1 — Game Router + Storage Layout complete (DegenerusGame, DegenerusGameStorage)
- [ ] **UNIT-02**: Unit 2 — Day Advancement + VRF complete (DegenerusGameAdvanceModule)
- [ ] **UNIT-03**: Unit 3 — Jackpot Distribution complete (DegenerusGameJackpotModule, DegenerusGamePayoutUtils)
- [ ] **UNIT-04**: Unit 4 — Endgame + Game Over complete (DegenerusGameEndgameModule, DegenerusGameGameOverModule)
- [ ] **UNIT-05**: Unit 5 — Mint + Purchase Flow complete (DegenerusGameMintModule, DegenerusGameMintStreakUtils)
- [ ] **UNIT-06**: Unit 6 — Whale Purchases complete (DegenerusGameWhaleModule)
- [ ] **UNIT-07**: Unit 7 — Decimator System complete (DegenerusGameDecimatorModule)
- [ ] **UNIT-08**: Unit 8 — Degenerette Betting complete (DegenerusGameDegeneretteModule)
- [ ] **UNIT-09**: Unit 9 — Lootbox + Boons complete (DegenerusGameLootboxModule, DegenerusGameBoonModule)
- [ ] **UNIT-10**: Unit 10 — BURNIE Token + Coinflip complete (BurnieCoin, BurnieCoinflip)
- [ ] **UNIT-11**: Unit 11 — sDGNRS + DGNRS complete (StakedDegenerusStonk, DegenerusStonk)
- [ ] **UNIT-12**: Unit 12 — Vault + WWXRP complete (DegenerusVault, WrappedWrappedXRP)
- [ ] **UNIT-13**: Unit 13 — Admin + Governance complete (DegenerusAdmin)
- [ ] **UNIT-14**: Unit 14 — Affiliate + Quests + Jackpots complete (DegenerusAffiliate, DegenerusQuests, DegenerusJackpots)
- [ ] **UNIT-15**: Unit 15 — Libraries complete (EntropyLib, BitPackingLib, GameTimeLib, JackpotBucketLib, PriceLookupLib)
- [ ] **UNIT-16**: Unit 16 — Cross-Contract Integration Sweep complete (all contracts, meta-analysis)

### Final Deliverables

- [ ] **DEL-01**: Master FINDINGS.md with all confirmed findings, severity-sorted
- [ ] **DEL-02**: ACCESS-CONTROL-MATRIX.md mapping every external function to its guard
- [ ] **DEL-03**: STORAGE-WRITE-MAP.md listing every storage slot and every function that writes to it
- [ ] **DEL-04**: ETH-FLOW-MAP.md tracing every wei from entry to exit

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Arithmetic overflow/underflow | Exhaustively audited in v3.0-v4.2, Solidity 0.8.34 built-in protection |
| Classic reentrancy | No raw `.call` patterns, Solidity 0.8.34, audited in v3.0-v3.3 |
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |
| Mock/test contracts | Not deployed |
| Gas optimization | Not the goal of this milestone |

## Traceability

**Cross-cutting process requirements** (COV-*, ATK-*, VAL-*) apply to every unit phase (103-118). They are not mapped 1:1 to a single phase because they define the methodology each unit must follow. They are satisfied when ALL 16 unit phases complete with full coverage, attack reports, and Skeptic validation.

| Requirement | Phase(s) | Status |
|-------------|----------|--------|
| COV-01 | 103-118 (every unit) | Complete |
| COV-02 | 103-118 (every unit) | Complete |
| COV-03 | 103-118 (every unit) | Complete |
| ATK-01 | 103-118 (every unit) | Complete |
| ATK-02 | 103-118 (every unit) | Complete |
| ATK-03 | 103-118 (every unit) | Complete |
| ATK-04 | 103-118 (every unit) | Complete |
| ATK-05 | 103-118 (every unit) | Complete |
| VAL-01 | 103-118 (every unit) | Complete |
| VAL-02 | 103-118 (every unit) | Complete |
| VAL-03 | 103-118 (every unit) | Complete |
| VAL-04 | 103-118 (every unit) | Complete |
| UNIT-01 | Phase 103 | Complete |
| UNIT-02 | Phase 104 | Pending |
| UNIT-03 | Phase 105 | Pending |
| UNIT-04 | Phase 106 | Pending |
| UNIT-05 | Phase 107 | Pending |
| UNIT-06 | Phase 108 | Pending |
| UNIT-07 | Phase 109 | Pending |
| UNIT-08 | Phase 110 | Pending |
| UNIT-09 | Phase 111 | Pending |
| UNIT-10 | Phase 112 | Pending |
| UNIT-11 | Phase 113 | Pending |
| UNIT-12 | Phase 114 | Pending |
| UNIT-13 | Phase 115 | Pending |
| UNIT-14 | Phase 116 | Pending |
| UNIT-15 | Phase 117 | Pending |
| UNIT-16 | Phase 118 | Pending |
| DEL-01 | Phase 119 | Pending |
| DEL-02 | Phase 119 | Pending |
| DEL-03 | Phase 119 | Pending |
| DEL-04 | Phase 119 | Pending |

**Coverage:**
- v5.0 requirements: 32 total
- Mapped to phases: 32 (16 UNIT-* to phases 103-118, 4 DEL-* to phase 119, 12 COV/ATK/VAL cross-cutting across 103-118)
- Unmapped: 0

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap creation*
