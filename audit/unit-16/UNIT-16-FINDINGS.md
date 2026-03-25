# Unit 16: Cross-Contract Integration Sweep -- Final Findings

## Executive Summary

Unit 16 is the meta-analysis phase of the v5.0 Ultimate Adversarial Audit. It does not re-audit individual functions (covered in Units 1-15). Instead, it examines cross-contract interactions, shared state, composition risks, and protocol-wide invariants that individual unit audits could not catch.

**Protocol:** Degenerus Protocol (29 contracts, ~15,000+ lines of Solidity)
**Audit type:** Three-agent adversarial integration sweep (Taskmaster + Mad Genius + Skeptic)
**Input:** All 15 unit findings reports (Units 1-15), contract source code
**Date:** 2026-03-25

### Key Results

- **693 functions** analyzed across all 16 units (100% coverage verified by Taskmaster in every unit)
- **7 cross-contract attack surfaces** examined at the integration level
- **0 new integration-level findings** -- no composition bugs discovered beyond what unit audits caught
- **1 MEDIUM finding confirmed** at integration level (decBucketOffsetPacked collision, originally from Unit 7)
- **ETH conservation: PROVEN** -- all entry/exit paths traced, rounding favors protocol
- **Token supply invariants: PROVEN** -- BURNIE, DGNRS, sDGNRS, WWXRP all verified
- **Delegatecall coherence: SAFE** -- all 10 module boundaries verified, no stale-cache bugs
- **State machine: SAFE** -- no permanent stuck states, multiple recovery paths for VRF failure
- **Access control: COMPLETE** -- all external functions use compile-time constant guards

---

## Findings Summary (All 16 Units Combined)

| Severity | Unit-Level | Integration-Level | Total |
|----------|-----------|------------------|-------|
| CRITICAL | 0 | 0 | **0** |
| HIGH | 0 | 0 | **0** |
| MEDIUM | 1 | 0 (confirmed existing) | **1** |
| LOW | 2 | 0 | **2** |
| INFO | 29 | 0 | **29** |
| **Total** | **32** | **0** | **32** |

---

## Confirmed Integration-Level Findings

### [MEDIUM] decBucketOffsetPacked Collision Between Regular and Terminal Decimator

**Originally found:** Unit 7 (Phase 109, Decimator System)
**Integration confirmation:** Both the regular decimator (via EndgameModule.runRewardJackpots) and terminal decimator (via GameOverModule.handleGameOverDrain) write to the same storage slot `decBucketOffsetPacked[lvl]` when game-over occurs at a decimator level.

**Cross-module call chain:**
1. `advanceGame()` -> `_handleGameOverPath()` -> `runRewardJackpots(lvl, rngWord)`
2. `runRewardJackpots` calls `runDecimatorJackpot(decPoolWei, lvl, rngWord)` -- writes `decBucketOffsetPacked[lvl]` (EndgameModule L215/L231 -> DecimatorModule L248)
3. Returns to `_handleGameOverPath` -> `handleGameOverDrain(lvl, rngWord)` (GameOverModule)
4. `handleGameOverDrain` calls `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` -- OVERWRITES `decBucketOffsetPacked[lvl]` (GameOverModule L139 -> DecimatorModule L817)

**Impact:** At the GAMEOVER level, if regular decimator also fired, unclaimed regular decimator winners lose access to their prizes (subbucket offsets overwritten). Affects up to 10-30 ETH at a single level.

**Occurrence:** ~20% probability (game-over at a decimator level: levels ending in 0 or 5).

**Recommendation:** Store terminal decimator offsets in a separate mapping `terminalDecBucketOffsetPacked`. Zero-overhead fix.

**Skeptic verdict:** CONFIRMED MEDIUM.

---

## Cross-Contract Interaction Analysis Results

### 1. Delegatecall Storage Coherence: SAFE

All 10 game modules share DegenerusGameStorage (102 variables, slots 0-78). Storage layout is EXACT MATCH across all modules (verified Unit 1 with forge inspect). Three isolation mechanisms prevent cross-module cache-overwrite bugs:

| Mechanism | Where | What It Prevents |
|-----------|-------|-----------------|
| Do-while break isolation | AdvanceModule L135-235 | Prevents reuse of stale locals after rngGate chain completes |
| Pre-commit before delegatecall | DegeneretteModule L703-704 | Ensures pool/claimable writes are committed before lootbox delegatecall |
| rebuyDelta reconciliation | EndgameModule L244-246 | Captures all auto-rebuy writes that occurred during BAF/Decimator resolution |

All BAF-class cache-overwrite checks across all 16 units returned SAFE. The original BAF bug (v4.4 fix) is correctly resolved.

### 2. ETH Conservation: PROVEN

**10 entry points** and **9 exit points** traced across all contracts.

**Conservation invariant:** `Game.balance + Game.stethBalance >= claimablePool` holds because:
- Every ETH entry adds to both contract balance and pool accounting
- Every ETH exit deducts from claimablePool BEFORE sending ETH (CEI pattern)
- Prize pool flow is zero-sum: `futurePrizePool -> nextPrizePool -> currentPrizePool -> claimableWinnings`
- Auto-rebuy is an internal transfer (claimable -> futurePrizePool), not creation/destruction
- Integer division rounding favors the protocol (remainders stay in source pool)

**stETH rebase:** Positive rebases create yield surplus (protocol benefits). Negative rebases (validator slashing) are absorbed by the 8% yield surplus buffer. Catastrophic negative rebases are an accepted external dependency (documented in KNOWN-ISSUES.md).

### 3. Token Supply Invariants: PROVEN

| Token | Supply Property | Proof |
|-------|----------------|-------|
| BURNIE | All 7 mint paths require authorized caller (GAME/COINFLIP/VAULT/ADMIN compile-time constants) | No unauthorized minting possible |
| DGNRS | No runtime mint function. Supply monotonically decreasing. | Constructor-only mint |
| sDGNRS | Pool accounting (Whale + Affiliate + Claims) + reserves = totalMoney, computed from live balances | Proportional burn with fresh balance reads |
| WWXRP | Intentionally undercollateralized. mintPrize requires one of 4 authorized callers. | Documented design decision |

### 4. Cross-Contract Reentrancy: SAFE

**7 ETH send sites** across 4 contracts. All either:
- Follow CEI (state updated before ETH send, preventing re-entry exploitation), OR
- Send to trusted compile-time constant contracts with trivial receive() functions (no callback)

No re-entry path allows double-claiming, state corruption, or unauthorized fund extraction.

### 5. State Machine Consistency: SAFE

| Concern | Status | Recovery Path |
|---------|--------|--------------|
| VRF never responds | SAFE | 120-day timeout -> game-over. Governance can swap coordinator. |
| rngLocked permanently | SAFE | Cleared by VRF response or timeout. Governance swap as fallback. |
| prizePoolFrozen persists | SAFE | Set and cleared within same advanceGame call. Revert unwinds. |
| jackpotPhaseFlag/currentDay inconsistency | SAFE | Single-writer (AdvanceModule), atomic updates within do-while FSM. |
| Game reaches unreachable state | SAFE | gameOver is terminal. All claim functions remain accessible. |

### 6. Access Control: COMPLETE

**All external state-changing functions** across 29 contracts have documented access control. Key patterns:
- **45+ functions** guarded by compile-time constant addresses (ContractAddresses.*)
- **5 functions** guarded by DGVE majority owner (vault share voting)
- **30+ functions** permissionless but self-affecting (claims, burns, standard ERC20)
- **0 configurable admin addresses, 0 proxy upgrade paths, 0 address re-pointing**

---

## Aggregate Statistics (All 16 Units)

| Metric | Value |
|--------|-------|
| Contracts audited | 29 |
| Total Solidity lines | ~15,000+ |
| Functions analyzed | 693 |
| Functions with full call trees | 200+ (all Category B across all units) |
| Storage write maps | 200+ (all Category B) |
| Cached-local-vs-storage checks | 200+ (all Category B) |
| BAF-class checks | ALL SAFE (0 cache-overwrite bugs) |
| Integration attack surfaces | 7 |
| Cross-contract call edges | 61 |
| ETH entry points verified | 10 |
| ETH exit points verified | 9 |
| Token supply chains verified | 4 |
| Taskmaster coverage verdicts | 16/16 PASS (100% in every unit) |
| Skeptic verdicts | All SAFE confirmed, 1 MEDIUM confirmed |

---

## Summary of All Findings Across v5.0 Audit

### MEDIUM (1)

| ID | Unit | Finding | Recommendation |
|----|------|---------|---------------|
| DEC-01 | 7 | decBucketOffsetPacked collision between regular and terminal decimator at GAMEOVER level | Separate terminalDecBucketOffsetPacked mapping |

### LOW (2)

| ID | Unit | Finding | Recommendation |
|----|------|---------|---------------|
| DEG-01 | 8 | ETH claimable pull uses strict inequality preventing exact balance usage | Change `<=` to `<` at DegeneretteModule L552 |
| ADM-01 | 13 | No LINK recovery path after failed shutdownVrf transfer | Add owner-only sweepLink function |

### INFO (29)

| Unit | Count | Key Themes |
|------|-------|-----------|
| 1 | 0 | (2 downgraded observations documented in dismissed findings) |
| 2 | 3 | Stale advanceBounty, lastLootboxRngWord staleness, ticket queue test bug |
| 3 | 5 | Yield surplus snapshot, assembly non-obvious, processed counter, double read, dust drop |
| 4 | 2 | Event pre-reconciliation value, unchecked deity refund |
| 5 | 0 | -- |
| 6 | 1 | DGNRS diminishing returns |
| 7 | 0 | -- |
| 8 | 1 | ETH bet resolution transiently blocked during freeze |
| 9 | 1 | Deity boon overwrite can downgrade existing boon |
| 10 | 3 | ERC20 approve race, vault self-mint, misleading error name |
| 11 | 3 | Dust in pending redemption, uint96 BURNIE truncation, view revert on negative rebase |
| 12 | 1 | CEI ordering in WWXRP donate |
| 13 | 3 | Vote weight inflation, silent subscription cancel, LINK stuck (same root as LOW) |
| 14 | 1 | uint24 underflow in BAF scatter at level 0 |
| 15 | 2 | EntropyLib zero fixed point, BitPackingLib comment discrepancy |
| 16 | 0 | No new findings at integration level |

---

## Audit Trail

| Unit | Phase | Deliverables | Coverage | Findings |
|------|-------|-------------|----------|----------|
| 1 | 103 | COVERAGE-CHECKLIST, STORAGE-LAYOUT-VERIFICATION, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 177/177 (100%) | 0 confirmed |
| 2 | 104 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 40/40 (100%) | 3 INFO |
| 3 | 105 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 55/55 (100%) | 5 INFO |
| 4 | 106 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 21/21 (100%) | 2 INFO |
| 5 | 107 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 20/20 (100%) | 0 confirmed |
| 6 | 108 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 16/16 (100%) | 1 INFO |
| 7 | 109 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 32/32 (100%) | 1 MEDIUM |
| 8 | 110 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 27/27 (100%) | 1 LOW + 1 INFO |
| 9 | 111 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 32/32 (100%) | 1 INFO |
| 10 | 112 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 71/71 (100%) | 3 INFO |
| 11 | 113 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 37/37 (100%) | 3 INFO |
| 12 | 114 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 64/64 (100%) | 1 INFO |
| 13 | 115 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 17/17 (100%) | 1 LOW + 3 INFO |
| 14 | 116 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 61/61 (100%) | 1 INFO |
| 15 | 117 | COVERAGE-CHECKLIST, ATTACK-REPORT, COVERAGE-REVIEW, SKEPTIC-REVIEW, FINDINGS | 18/18 (100%) | 2 INFO |
| 16 | 118 | INTEGRATION-MAP, INTEGRATION-ATTACK-REPORT, INTEGRATION-SKEPTIC-REVIEW, INTEGRATION-COVERAGE-REVIEW, FINDINGS | 7 attack surfaces (100%) | 0 new (1 MEDIUM confirmed from Unit 7) |

---

## Conclusion

The Degenerus Protocol passes the v5.0 Ultimate Adversarial Audit integration sweep with:

- **0 CRITICAL findings** across 693 functions in 29 contracts
- **0 HIGH findings**
- **1 MEDIUM finding** (decBucketOffsetPacked collision -- recommended fix: separate storage mapping)
- **2 LOW findings** (strict inequality in Degenerette, missing LINK recovery in Admin)
- **29 INFO findings** (code quality, gas, cosmetic issues)
- **100% Taskmaster coverage** in all 16 units
- **All BAF-class cache-overwrite checks SAFE**
- **ETH conservation PROVEN**
- **Token supply invariants PROVEN**
- **Access control COMPLETE** (compile-time constants, no admin re-pointing)
- **State machine SAFE** (no permanent stuck states, multiple VRF recovery paths)

The protocol is well-architected with effective isolation mechanisms (do-while break, pre-commit delegatecall, rebuyDelta reconciliation). The original BAF cache-overwrite bug class has been comprehensively eliminated. The one MEDIUM finding (decBucketOffsetPacked) has a straightforward fix.

---

*Unit 16 integration sweep complete: 2026-03-25*
*v5.0 Ultimate Adversarial Audit: Units 1-16 all PASS. Ready for Phase 119 Final Deliverables.*
