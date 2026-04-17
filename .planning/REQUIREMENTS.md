# Requirements: Degenerus Protocol — Post-v27 Contract Delta Audit

**Defined:** 2026-04-17
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v29.0 Requirements

Requirements for this milestone. Each maps to roadmap phases.

**Audit baseline:** v27.0 ship point (2026-04-13). v28.0 audited the sibling `database/` repo only — contracts were not re-audited. Delta scope is the 8 contract-touching commits between v27.0 and today.

**In-scope commits:**
- `52242a10` refactor: explicit entropy passthrough to `processFutureTicketBatch`
- `f20a2b5e` refactor(earlybird): finalize at level transition, unify award call per purchase
- `3ad0f8d3` fix(decimator): key burns by resolution level, consolidate jackpot block
- `104b5d42` feat(jackpot): tag BAF wins with `traitId=420` sentinel
- `67031e7d` feat(decimator): emit `DecimatorClaimed` and `TerminalDecimatorClaimed`
- `858d83e4` feat(game): expose `claimTerminalDecimatorJackpot` passthrough
- `d5284be5` fix(quests): credit fresh ETH wei 1:1 to `mint_ETH` quest
- `e0a7f7bc` feat(boons): expose `boonPacked` mapping for UI reads
- `20a951df` feat(earlybird): align trait roll with coin jackpot, fix queue level *(today)*

**In-scope files (12):** `DegenerusGameJackpotModule.sol`, `DegenerusGameStorage.sol`, `DegenerusQuests.sol`, `IDegenerusQuests.sol`, `DegenerusGameMintModule.sol`, `DegenerusGame.sol`, `IDegenerusGame.sol`, `DegenerusGameDecimatorModule.sol`, `BurnieCoin.sol`, `DegenerusGameAdvanceModule.sol`, `DegenerusGameWhaleModule.sol`, `IDegenerusGameModules.sol`.

### Delta Extraction

- [ ] **DELTA-01**: Function-level changelog of every changed/new/deleted function across the 9 commits, mapped to owning contract and commit SHA
- [ ] **DELTA-02**: Cross-module interaction map for the changed surface — every new or modified call chain crossing module boundaries documented
- [ ] **DELTA-03**: Interface drift catalog — every diff between `IDegenerusGame`, `IDegenerusQuests`, `IDegenerusGameModules` and their implementers identified and verified aligned

### Adversarial Audit — Earlybird Jackpot

- [ ] **EBD-01**: Earlybird purchase-phase refactor (`f20a2b5e`) audited end-to-end — level-transition finalization path, unified award call, storage read/write ordering, reentrancy/CEI, gas
- [ ] **EBD-02**: Earlybird trait-alignment rewrite (`20a951df`) audited — bonus trait parity with coin jackpot, salt-space isolation, fixed-level queueing at `lvl+1`, budget conservation (futurePool → nextPool)
- [ ] **EBD-03**: Combined earlybird state-machine verified across (purchase finalize) + (jackpot-phase earlybird run) — no double-spend, no orphaned reserves, no missed emissions

### Adversarial Audit — Decimator

- [ ] **DCM-01**: Decimator burn-key refactor (`3ad0f8d3`) audited — keys now by resolution level; verify every read site uses the matching key, no off-by-one in pro-rata share calculation, consolidated jackpot block has correct ordering
- [ ] **DCM-02**: Decimator event emission (`67031e7d`) audited — `DecimatorClaimed` + `TerminalDecimatorClaimed` fire at correct CEI position, argument correctness, indexer compatibility with v28.0 event surface
- [ ] **DCM-03**: `claimTerminalDecimatorJackpot` passthrough (`858d83e4`) audited — caller restriction, reentrancy, parameter pass-through to module, no privilege escalation

### Adversarial Audit — Jackpot/BAF + Entropy

- [ ] **JKP-01**: BAF `traitId=420` sentinel (`104b5d42`) audited — no collision with real trait IDs (0-255 domain), event consumers tolerate sentinel, no downstream logic treats 420 as a real trait
- [ ] **JKP-02**: Explicit entropy passthrough to `processFutureTicketBatch` (`52242a10`) audited — verify passed entropy is cryptographically equivalent to prior derivation, no commitment-window widening, no re-use across calls in the same transaction
- [ ] **JKP-03**: Combined jackpot-side changes + today's earlybird rewrite verified consistent — all jackpot paths using `bonusTraitsPacked` produce identical 4-trait set for the same VRF word

### Adversarial Audit — Quests / Boons / Misc

- [ ] **QST-01**: `mint_ETH` quest wei-credit fix (`d5284be5`) audited — 1:1 wei credit correctness, interaction with fresh-ETH detection, no double-credit with companion quests, mint-module integration, test file change reviewed
- [ ] **QST-02**: `boonPacked` mapping exposure (`e0a7f7bc`) audited — read-only accessor safety, storage layout preserved, no write path introduced, slot accessibility matches intent
- [ ] **QST-03**: `BurnieCoin.sol` change audited — isolated cause/effect (only decimator-burn-key-related), no supply conservation impact

### ETH / BURNIE Conservation + RNG Commitment Re-Proof

- [ ] **CONS-01**: ETH conservation proof across the delta — every new or modified SSTORE site touching `currentPrizePool` / `nextPrizePool` / `futurePrizePool` / `claimablePool` / `decimatorPool` accounted for; sum before = sum after at every path endpoint
- [ ] **CONS-02**: BURNIE conservation verified — `BurnieCoin` change + quest changes don't break mint/burn accounting; no new mint site bypasses `mintForGame`
- [ ] **RNG-01**: Backward trace from every new RNG consumer in the delta (earlybird bonus-trait roll, BAF sentinel emission, entropy passthrough) proving the RNG word was unknown at input commitment time
- [ ] **RNG-02**: Commitment-window analysis across the delta — player-controllable state between VRF request and fulfillment verified non-influential for every new consumer

### Regression

- [ ] **REG-01**: All 16 v27.0 INFO findings + 3 KNOWN-ISSUES entries re-verified against current code
- [ ] **REG-02**: All 13 v25.0 findings + v26.0 delta audit conclusions re-verified (no regression introduced by the 9-commit delta)

### Findings Consolidation

- [ ] **FIND-01**: All findings severity-classified (CRITICAL / HIGH / MEDIUM / LOW / INFO) in `audit/FINDINGS-v29.0.md` using v27.0-style per-finding blocks
- [ ] **FIND-02**: `audit/KNOWN-ISSUES.md` updated with any new design-decision entries referencing `F-29-NN` IDs
- [ ] **FIND-03**: Executive summary table (per-phase counts + per-severity totals) + combined deliverable published

## Future Requirements

None — this is a terminal delta-audit milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| `database/` repo re-audit | Covered by v28.0; no delta in that layer this cycle |
| Frontend / UI | Not in audit scope |
| Off-chain VRF coordinator | External dependency, covered by v25.0 RNG fresh-eyes |
| Test coverage gap closure | Covered by v27.0 call-site integrity; new tests only if a finding requires them |
| Contracts unchanged since v27.0 | Audited in prior milestones; re-audit unnecessary without a delta |
| Gas optimization sweep | Gas changes in the delta are verified within the audit; no standalone gas-only phase |

## Traceability

Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | TBD | Pending |
| DELTA-02 | TBD | Pending |
| DELTA-03 | TBD | Pending |
| EBD-01 | TBD | Pending |
| EBD-02 | TBD | Pending |
| EBD-03 | TBD | Pending |
| DCM-01 | TBD | Pending |
| DCM-02 | TBD | Pending |
| DCM-03 | TBD | Pending |
| JKP-01 | TBD | Pending |
| JKP-02 | TBD | Pending |
| JKP-03 | TBD | Pending |
| QST-01 | TBD | Pending |
| QST-02 | TBD | Pending |
| QST-03 | TBD | Pending |
| CONS-01 | TBD | Pending |
| CONS-02 | TBD | Pending |
| RNG-01 | TBD | Pending |
| RNG-02 | TBD | Pending |
| REG-01 | TBD | Pending |
| REG-02 | TBD | Pending |
| FIND-01 | TBD | Pending |
| FIND-02 | TBD | Pending |
| FIND-03 | TBD | Pending |

**Coverage:**
- v29.0 requirements: 24 total
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 24 ⚠️

---
*Requirements defined: 2026-04-17*
*Last updated: 2026-04-17 after initial definition*
