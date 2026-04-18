# Requirements: Degenerus Protocol — Post-v27 Contract Delta Audit

**Defined:** 2026-04-17
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v29.0 Requirements

Requirements for this milestone. Each maps to roadmap phases.

**Audit baseline:** v27.0 phase execution complete (2026-04-12 21:55, commit `14cb45e1`). v28.0 audited the sibling `database/` repo only — contracts were not re-audited. Delta scope is the 10 contract-touching commits between that baseline and today.

**In-scope commits:**
- `2471f8e7` phase transition fix — removes `_unlockRng(day)` from jackpot→purchase transition so housekeeping packs into the last jackpot physical day
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

- [x] **EBD-01**: Earlybird purchase-phase refactor (`f20a2b5e`) audited end-to-end — level-transition finalization path, unified award call, storage read/write ordering, reentrancy/CEI, gas — completed 2026-04-17 (21 PASS verdicts, zero FAIL; see `.planning/phases/231-earlybird-jackpot-audit/231-01-AUDIT.md`)
- [x] **EBD-02**: Earlybird trait-alignment rewrite (`20a951df`) audited — bonus trait parity with coin jackpot, salt-space isolation, fixed-level queueing at `lvl+1`, budget conservation (futurePool → nextPool) — completed 2026-04-17 (6 PASS verdicts across 2 target functions; zero FAIL; see `.planning/phases/231-earlybird-jackpot-audit/231-02-AUDIT.md`)
- [x] **EBD-03**: Combined earlybird state-machine verified across (purchase finalize) + (jackpot-phase earlybird run) — no double-spend, no orphaned reserves, no missed emissions — completed 2026-04-17 (13 PASS verdicts across 4 paths × 4 attack vectors; cross-commit invariant clarified as temporal + causal ordering between orthogonal storage namespaces; see `.planning/phases/231-earlybird-jackpot-audit/231-03-AUDIT.md`)

### Adversarial Audit — Decimator

- [x] **DCM-01**: Decimator burn-key refactor (`3ad0f8d3`) audited — keys now by resolution level; every read site uses the matching key (level-bump timing model proves WRITE-key `level()+1` and READ-key post-bump `lvl` align at every hop), no off-by-one in pro-rata share calculation, consolidated jackpot block x00/x5 mutually exclusive (structural + arithmetic disjointness proofs) with `decPoolWei` zero-deterministic outside both branches and `runDecimatorJackpot` self-call args/CEI byte-identical to pre-fix — completed 2026-04-18 (23 verdict rows / 21 SAFE + 2 SAFE-INFO across 11 target functions; zero VULNERABLE / zero DEFERRED row-level verdicts; 2 Finding Candidate: Y rows for Phase 236 FIND-01 (DECIMATOR_MIN_BUCKET_100 dead-code revival; "prev"-prefixed naming vestige); BurnieCoin sum-in/sum-out hand-off to Phase 235 CONS-02 per D-14; see `.planning/phases/232-decimator-audit/232-01-AUDIT.md`)
- [x] **DCM-02**: Decimator event emission (`67031e7d`) audited — `DecimatorClaimed` + `TerminalDecimatorClaimed` fire at correct CEI position (3 emit sites: gameOver fast-path post-`_creditClaimable` + normal ETH/lootbox split post-`_setFuturePrizePool` + terminal post-`_consumeTerminalDecClaim`+`_creditClaimable` — zero SSTORE/external call between final mutation and emit at every site), argument correctness verified algebraically (`ethPortion + lootboxPortion == amountWei` identity at both DecimatorClaimed sites; `lvl` storage-sourced from `lastTerminalDecClaimRound.lvl` for TerminalDecimatorClaimed eliminating caller-injection; `amountWei` matches consumed return value), v28.0 Phase 227 indexer-compat OBSERVATION recorded per D-10 (neither event signature in v28.0 baseline scope — routes to Phase 236 FIND-02 KNOWN-ISSUES candidate, not contract-side finding) — completed 2026-04-18 (14 verdict rows / 9 SAFE + 5 SAFE-INFO across 3 emit sites + 2 event declarations + 1 OBSERVATION row; zero VULNERABLE / zero DEFERRED row-level verdicts; 1 Finding Candidate: Y row for indexer-compat OBSERVATION; see `.planning/phases/232-decimator-audit/232-02-AUDIT.md`)
- [x] **DCM-03**: `claimTerminalDecimatorJackpot` passthrough (`858d83e4`) audited — wrapper at DegenerusGame.sol:1268-1279 + IDegenerusGame interface decl at line 229 + IM-08 delegatecall chain end-to-end; caller restriction SAFE (module-internal `_consumeTerminalDecClaim` guards cover privilege space; `lastTerminalDecClaimRound.lvl != 0` invariant reachable only post-GAMEOVER via Game-only-guarded `runTerminalDecimatorJackpot:798`); reentrancy SAFE (zero external-interaction surface in IM-08 chain — no `.call`/`.delegatecall`/`.transfer`/`.send` anywhere; one-shot per (player, terminal claim round) preserved by `e.weightedBurn = 0` SSTORE); parameter pass-through SAFE (wrapper zero-arg + payload zero-arg + module zero-arg + `lvl` storage-sourced from `lastTerminalDecClaimRound.lvl` not caller calldata); privilege escalation SAFE (delegatecall preserves msg.sender → original caller credited via `_creditClaimable(msg.sender, amountWei)`; wrapper non-payable blocks msg.value injection); ID-30 + ID-93 interface lockstep PASS; `make check-delegatecall` 44/44 PASS at HEAD cited as corroborating evidence per D-12 — completed 2026-04-18 (7 verdict rows / 6 SAFE + 1 SAFE-INFO across 4 target categories; zero VULNERABLE / zero DEFERRED / zero Finding Candidate: Y rows; DCM-03 contributes zero candidate findings to Phase 236 FIND-01 pool; see `.planning/phases/232-decimator-audit/232-03-AUDIT.md`)

### Adversarial Audit — Jackpot/BAF + Entropy

- [x] **JKP-01**: BAF `traitId=420` sentinel (`104b5d42`) audited — completed 2026-04-19; 22 SAFE + 2 SAFE-INFO verdicts in 233-01-AUDIT.md; 2 Finding Candidate: Y (event-widening indexer-compat OBSERVATIONS for off-chain ABI regeneration, routed to Phase 236 FIND-01/02)
- [x] **JKP-02**: Explicit entropy passthrough to `processFutureTicketBatch` (`52242a10`) audited — completed 2026-04-19; 23 SAFE per-function verdict rows + 16 SAFE commitment-window enumeration rows in 233-02-AUDIT.md; 0 Finding Candidate: Y; D-06 backward-trace + commitment-window rules applied explicitly (per `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md`)
- [x] **JKP-03**: Combined jackpot-side changes + today's earlybird rewrite verified consistent — completed 2026-04-19; 5 SAFE cross-path derivation + 15 SAFE per-function verdicts in 233-03-AUDIT.md; 0 Finding Candidate: Y; D-09 non-overlap with Phase 231 EBD-02 explicit

### Adversarial Audit — Quests / Boons / Misc

- [x] **QST-01**: `mint_ETH` quest wei-credit fix (`d5284be5`) audited — completed 2026-04-19; 11 rows (9 SAFE + 2 SAFE-INFO) in 234-01-AUDIT.md §QST-01; 1 Finding Candidate: Y (FC-234-A companion-test-coverage observation, routed to Phase 236)
- [x] **QST-02**: `boonPacked` mapping exposure (`e0a7f7bc`) audited — completed 2026-04-19; 5 rows (4 SAFE + 1 SAFE-INFO) in 234-01-AUDIT.md §QST-02; 0 Finding Candidate: Y; D-08 document-and-accept on interface-non-declaration
- [x] **QST-03**: `BurnieCoin.sol` change audited — completed 2026-04-19; 7 rows (6 SAFE + 1 SAFE-INFO) in 234-01-AUDIT.md §QST-03; 0 Finding Candidate: Y; D-11 overlap-non-conflict with Phase 232 DCM-01; Phase 235 CONS-02 hand-off for BURNIE supply conservation

### Phase Transition (RNG Lock)

- [ ] **TRNX-01**: Phase-transition RNG lock removal (`2471f8e7`) audited — `_unlockRng(day)` removed from the jackpot→purchase transition at `DegenerusGameAdvanceModule:425`. Verify: (a) no state-changing path between `_endPhase()` and the next `_unlockRng` reactivation allows exploit, (b) RNG lock invariant (no far-future ticket queuing while locked) preserved across the newly-packed housekeeping step, (c) commitment-window integrity — any RNG consumer now inside the packed window still has its word unknown at input commitment time, (d) no missed or double unlock across any reachable path (normal / gameover / skip-split).

### ETH / BURNIE Conservation + RNG Commitment Re-Proof

- [ ] **CONS-01**: ETH conservation proof across the delta — every new or modified SSTORE site touching `currentPrizePool` / `nextPrizePool` / `futurePrizePool` / `claimablePool` / `decimatorPool` accounted for; sum before = sum after at every path endpoint
- [ ] **CONS-02**: BURNIE conservation verified — `BurnieCoin` change + quest changes don't break mint/burn accounting; no new mint site bypasses `mintForGame`
- [ ] **RNG-01**: Backward trace from every new RNG consumer in the delta (earlybird bonus-trait roll, BAF sentinel emission, entropy passthrough) proving the RNG word was unknown at input commitment time
- [ ] **RNG-02**: Commitment-window analysis across the delta — player-controllable state between VRF request and fulfillment verified non-influential for every new consumer

### Regression

- [ ] **REG-01**: All 16 v27.0 INFO findings + 3 KNOWN-ISSUES entries re-verified against current code
- [ ] **REG-02**: All 13 v25.0 findings + v26.0 delta audit conclusions re-verified (no regression introduced by the 10-commit delta)

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

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | 230 | Pending |
| DELTA-02 | 230 | Pending |
| DELTA-03 | 230 | Pending |
| EBD-01 | 231 | Complete (2026-04-17) |
| EBD-02 | 231 | Complete (2026-04-17) |
| EBD-03 | 231 | Complete (2026-04-17) |
| DCM-01 | 232 | Complete (2026-04-18) |
| DCM-02 | 232 | Complete (2026-04-18) |
| DCM-03 | 232 | Complete (2026-04-18) |
| JKP-01 | 233 | Complete (2026-04-19) |
| JKP-02 | 233 | Complete (2026-04-19) |
| JKP-03 | 233 | Complete (2026-04-19) |
| QST-01 | 234 | Complete (2026-04-19) |
| QST-02 | 234 | Complete (2026-04-19) |
| QST-03 | 234 | Complete (2026-04-19) |
| CONS-01 | 235 | Pending |
| CONS-02 | 235 | Pending |
| RNG-01 | 235 | Pending |
| RNG-02 | 235 | Pending |
| TRNX-01 | 235 | Pending |
| REG-01 | 236 | Pending |
| REG-02 | 236 | Pending |
| FIND-01 | 236 | Pending |
| FIND-02 | 236 | Pending |
| FIND-03 | 236 | Pending |

**Coverage:**
- v29.0 requirements: 25 total
- Mapped to phases: 25 ✓
- Unmapped: 0

---
*Requirements defined: 2026-04-17*
*Last updated: 2026-04-18 — DCM-03 marked Complete (Phase 232 Plan 03 shipped, 7 verdict rows / 6 SAFE + 1 SAFE-INFO; zero Finding Candidate: Y rows; Phase 232 Decimator Audit NOW COMPLETE — all 3 DCM requirements shipped with zero VULNERABLE / zero DEFERRED across the full surface)*
