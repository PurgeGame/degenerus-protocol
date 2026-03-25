# Degenerus Protocol -- Master Findings Report (v5.0 Ultimate Adversarial Audit)

**Audit Date:** 2026-03-25
**Methodology:** Three-agent adversarial system (Taskmaster + Mad Genius + Skeptic), Opus (claude-opus-4-6)
**Scope:** 29 contracts, ~15,000+ lines Solidity, 693 functions analyzed across 16 audit units
**Coverage:** 100% Taskmaster-verified in all 16 units

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 2 |
| INFO | 29 |
| **Total** | **31** |

**Overall Assessment:** The Degenerus Protocol is well-architected with effective isolation mechanisms. All BAF-class cache-overwrite checks are SAFE. ETH conservation is PROVEN across all entry/exit paths. Token supply invariants are PROVEN for all 4 tokens (BURNIE, DGNRS, sDGNRS, WWXRP). Access control is COMPLETE with compile-time constant guards and no admin re-pointing.

Zero CRITICAL, HIGH, or MEDIUM findings across all 29 contracts. The 2 LOW findings are minor UX friction and a missing recovery path for an unlikely failure mode. The 29 INFO findings are code quality observations, gas inefficiencies, and cosmetic issues with no security impact.

---

## ~~MEDIUM Findings~~ (0)

### ~~M-01: decBucketOffsetPacked Collision Between Regular and Terminal Decimator~~

**Original Severity:** MEDIUM
**Verdict:** FALSE POSITIVE -- dismissed during protocol team review

**Why False Positive:** `runDecimatorJackpot` fires from `runRewardJackpots` during `advanceGame()` level transitions. `runTerminalDecimatorJackpot` fires from `handleGameOverDrain` during GAMEOVER. Once GAMEOVER triggers, `advanceGame()` never runs again -- no more level transitions occur. The regular decimator can never fire at the GAMEOVER level because that level will never have a level transition. The two functions operate in mutually exclusive game states, making `decBucketOffsetPacked[lvl]` collision at the same `lvl` structurally impossible.

---

## LOW Findings (2)

### L-01: ETH Claimable Pull Uses Strict Inequality Preventing Exact Balance Usage

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Unit** | 8 (Degenerette Betting) |
| **Phase** | 110 |
| **Contract** | DegenerusGameDegeneretteModule.sol |
| **Function** | `placeFullTicketBets()` L552 |

**Description:**
The claimable pull check at L552 uses `<=` instead of `<`:
```solidity
if (claimableWinnings[player] <= fromClaimable) revert InvalidBet();
```
A player cannot use their exact full claimable balance to fund a Degenerette bet. If `claimableWinnings[player] == fromClaimable`, the bet reverts. The player must send at least 1 wei as msg.value or place a slightly smaller bet.

**Impact:** Minor UX friction. No funds at risk, no state corruption, no exploitable vector.

**Recommendation:** Change `<=` to `<` at L552, or document as intentional behavior.

**Evidence:** Unit 8 ATTACK-REPORT.md F-01, SKEPTIC-REVIEW.md F-01

---

### L-02: No LINK Recovery Path After Failed shutdownVrf Transfer

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Unit** | 13 (Admin + Governance) |
| **Phase** | 115 |
| **Contract** | DegenerusAdmin.sol |
| **Function** | `shutdownVrf()` L651-674 |

**Description:**
When `shutdownVrf()` is called during game-over, the function zeros `subscriptionId` at L656 before attempting LINK transfer at L665. If the LINK transfer fails (try/catch catches the error), LINK remains permanently locked in the Admin contract with no recovery function available.

**Impact:** Permanent LINK lock if transfer fails at game-over. Very low likelihood (LINK is standard ERC-677 without pause/blacklist; target is compile-time constant).

**Recommendation:** Add an owner-only `sweepLink(address to)` function callable after game-over. Adds no attack surface since game is over and VRF is shutdown.

**Evidence:** Unit 13 ATTACK-REPORT.md F-03/F-05, SKEPTIC-REVIEW.md

---

## INFO Findings (29)

### Unit 2: Day Advancement + VRF (3 INFO)

#### I-01: advanceBounty Computed from Potentially Stale Price

| Field | Value |
|-------|-------|
| **Unit** | 2 |
| **Contract** | DegenerusGameAdvanceModule.sol |
| **Function** | `advanceGame()` L127, L396 |

`advanceBounty` is computed at L127 using current `price`. The descendant `_finalizeRngRequest` can update `price` at L1355-1380 (price doubling on level transition). The caller receives ~2x BURNIE bounty that the new price justifies. Impact bounded at ~0.005 ETH BURNIE equivalent per level transition. BURNIE is in-game currency with no secondary market.

---

#### I-02: lastLootboxRngWord Not Updated on Mid-Day VRF Fulfillment Path

| Field | Value |
|-------|-------|
| **Unit** | 2 |
| **Contract** | DegenerusGameAdvanceModule.sol |
| **Function** | `rawFulfillRandomWords()` L1468-1475 |

When `rawFulfillRandomWords` processes a mid-day VRF callback, it correctly stores the word in `lootboxRngWordByIndex[index]` but does not update `lastLootboxRngWord`. All lootbox resolution uses the per-index mapping (correctly set), so the global staleness has no functional impact.

---

#### I-03: Ticket Queue Drain Test Assertion Uses Wrong Buffer Slot

| Field | Value |
|-------|-------|
| **Unit** | 2 |
| **Contract** | Test helper `_readKeyForLevel()` (not contract code) |

Three TicketLifecycle Foundry tests fail because the test's `_readKeyForLevel` helper computes the read key from the assertion-time `ticketWriteSlot`, not the processing-time slot. After multi-level transitions, the double-buffer rotation means the test checks the wrong buffer. Contract behavior is correct -- the drain gate in `_swapTicketSlot` verifies completeness.

---

### Unit 3: Jackpot Distribution (5 INFO)

#### I-04: Yield Surplus Obligations Snapshot Staleness

| Field | Value |
|-------|-------|
| **Unit** | 3 |
| **Contract** | DegenerusGameJackpotModule.sol |
| **Function** | `_distributeYieldSurplus()` L883-914 |

The `obligations` snapshot can become stale if auto-rebuy writes to futurePrizePool/nextPrizePool during the same call. Staleness direction is conservative (actual surplus smaller than computed). 8% buffer absorbs the difference. No external attack surface.

---

#### I-05: Assembly Storage Slot Calculation Non-Obvious

| Field | Value |
|-------|-------|
| **Unit** | 3 |
| **Contract** | DegenerusGameJackpotModule.sol |
| **Function** | `_raritySymbolBatch()` L2050-2145 |

Inline Yul assembly uses `add(levelSlot, traitId)` for fixed-array-within-mapping layout. Both agents independently verified the calculation is CORRECT for the declared type. Contract is non-upgradeable, so layout cannot change.

---

#### I-06: Processed Counter Approximation in processTicketBatch

| Field | Value |
|-------|-------|
| **Unit** | 3 |
| **Contract** | DegenerusGameJackpotModule.sol |
| **Function** | `processTicketBatch()` L1812-1873 |

The `processed` counter uses `writesUsed >> 1` as an approximation. This affects the LCG seed derivation in `_raritySymbolBatch`, potentially producing slightly different trait assignments on resume. Traits are aesthetic only (VRF-derived, no economic value). Exact tracking would require additional SSTORE per loop iteration.

---

#### I-07: Double _getFuturePrizePool() Read in Earlybird Deduction

| Field | Value |
|-------|-------|
| **Unit** | 3 |
| **Contract** | DegenerusGameJackpotModule.sol |
| **Function** | `_runEarlyBirdLootboxJackpot()` L774-778 |

A second SLOAD reads the same value already cached locally. The warm SLOAD costs 100 gas with no correctness impact.

---

#### I-08: Zero takeProfit Drops Dust in Auto-Rebuy

| Field | Value |
|-------|-------|
| **Unit** | 3 |
| **Contract** | DegenerusGameJackpotModule.sol, DegenerusGamePayoutUtils.sol |
| **Functions** | `_processAutoRebuy()` L959-999, `_calcAutoRebuy()` D16 |

When `takeProfit == 0`, the integer division remainder (`weiAmount % (ticketPrice / 4)`) is dropped. Dust is always less than ticketPrice/4 (~0.00225 ETH at level 1). NatSpec explicitly documents this behavior.

---

### Unit 4: Endgame + Game Over (2 INFO)

#### I-09: RewardJackpotsSettled Event Emits Pre-Reconciliation Pool Value

| Field | Value |
|-------|-------|
| **Unit** | 4 |
| **Contract** | DegenerusGameEndgameModule.sol |
| **Function** | `runRewardJackpots()` L252 |

The event emits `futurePoolLocal` (pre-reconciliation) rather than `futurePoolLocal + rebuyDelta` (post-reconciliation). No on-chain state impact; cosmetic event data discrepancy.

---

#### I-10: Unchecked Deity Pass Refund Arithmetic (Hygiene Note)

| Field | Value |
|-------|-------|
| **Unit** | 4 |
| **Contract** | DegenerusGameGameOverModule.sol |
| **Function** | `handleGameOverDrain()` L91-95 |

The deity pass refund loop uses `unchecked` arithmetic for `claimableWinnings[owner] += refund` and related operations. Overflow is mathematically impossible given ETH supply constraints (max ~120M ETH / 20 ETH per pass = 6M passes, well within uint256).

---

### Unit 6: Whale Purchases (1 INFO)

#### I-11: DGNRS Whale Pool Diminishing Returns in Multi-Quantity Purchase

| Field | Value |
|-------|-------|
| **Unit** | 6 |
| **Contract** | DegenerusGameWhaleModule.sol |
| **Functions** | `purchaseWhaleBundle()` L284-287, `_rewardWhaleBundleDgnrs()` L587-603 |

The DGNRS reward loop reads FRESH pool balance per iteration. Multi-bundle purchases in a single transaction receive diminishing returns (cumulative minter reward for quantity=100 is ~63.4% of initial pool, not 100 x 1%). This is standard anti-drain pool mechanics.

---

### Unit 8: Degenerette Betting (1 INFO)

#### I-12: ETH Bet Resolution Transiently Blocked During Prize Pool Freeze

| Field | Value |
|-------|-------|
| **Unit** | 8 |
| **Contract** | DegenerusGameDegeneretteModule.sol |
| **Function** | `_distributePayout()` L685 |

ETH Degenerette bet resolutions revert when `prizePoolFrozen` is true. The freeze exists only within a single `advanceGame` transaction (transient). BURNIE and WWXRP resolutions are unaffected. By-design defensive behavior.

---

### Unit 9: Lootbox + Boons (1 INFO)

#### I-13: Deity Boon Overwrite Can Downgrade Existing Higher-Tier Lootbox Boon

| Field | Value |
|-------|-------|
| **Unit** | 9 |
| **Contract** | DegenerusGameLootboxModule.sol |
| **Function** | `_applyBoon()` L1396-1601 |

A deity issuing a boon overwrites the existing boon regardless of tier. A deity could theoretically downgrade a player's high-tier lootbox boon. Deity passes cost 24+ ETH, max 32 total, one boon per recipient per day. Pure griefing with no economic profit.

---

### Unit 10: BURNIE Token + Coinflip (3 INFO)

#### I-14: ERC20 Approve Race Condition

| Field | Value |
|-------|-------|
| **Unit** | 10 |
| **Contract** | BurnieCoin.sol |
| **Functions** | `approve()` L394-401, `transferFrom()` L422-441 |

Standard ERC20 approve/transferFrom race condition. A spender could front-run an approve change. Well-known ERC20 design characteristic. The game contract bypasses allowance entirely (trusted contract pattern).

---

#### I-15: Vault Self-Mint Semantic Oddity

| Field | Value |
|-------|-------|
| **Unit** | 10 |
| **Contract** | BurnieCoin.sol |
| **Function** | `vaultMintTo()` L705-717 |

The vault calling `vaultMintTo(VAULT, amount)` would create circulating tokens held by the vault. On subsequent transfer, `_transfer` redirects to vault escrow, effectively a no-op. Supply invariant maintained. Path unreachable in normal operations.

---

#### I-16: Misleading Error Name in Coinflip Gate Functions

| Field | Value |
|-------|-------|
| **Unit** | 10 |
| **Contract** | BurnieCoin.sol |
| **Functions** | `burnForCoinflip()` L529, `mintForCoinflip()` L538 |

Both functions revert with `OnlyGame()` error when the caller is not the coinflip contract. The error name implies game contract, but the check is `msg.sender != coinflipContract`. Cosmetic naming issue.

---

### Unit 11: sDGNRS + DGNRS (3 INFO)

#### I-17: Dust Accumulation in Pending Redemption ETH Tracking

| Field | Value |
|-------|-------|
| **Unit** | 11 |
| **Contract** | StakedDegenerusStonk.sol |
| **Functions** | `resolveRedemptionPeriod()` L547-548, `claimRedemption()` L587, L612 |

Per-claimant floor division during `claimRedemption()` causes up to (n-1) wei dust per period in `pendingRedemptionEthValue`. Over the game's lifetime (~1000 periods, ~100 claimants), total dust is ~99,000 wei (~0.0000000000001 ETH).

---

#### I-18: uint96 BURNIE Truncation Theoretical Possibility

| Field | Value |
|-------|-------|
| **Unit** | 11 |
| **Contract** | StakedDegenerusStonk.sol |
| **Function** | `_submitGamblingClaimFrom()` L760 |

`claim.burnieOwed += uint96(burnieOwed)` performs unchecked narrowing cast. Truncation requires the wallet's proportional BURNIE share to exceed ~7.9e28 (~4.9e37 wei given the 160 ETH daily cap). Far beyond any realistic BURNIE supply.

---

#### I-19: View Function Revert on Negative stETH Rebase

| Field | Value |
|-------|-------|
| **Unit** | 11 |
| **Contract** | StakedDegenerusStonk.sol |
| **Functions** | `previewBurn()` L660, `burnieReserve()` L691 |

If a stETH negative rebase reduces `stethBal` such that `totalMoney` subtraction underflows, view functions revert instead of returning data. State-changing functions would still function correctly. stETH negative rebases are extremely rare.

---

### Unit 12: Vault + WWXRP (1 INFO)

#### I-20: donate() External Call Before State Update (CEI Ordering)

| Field | Value |
|-------|-------|
| **Unit** | 12 |
| **Contract** | WrappedWrappedXRP.sol |
| **Function** | `donate()` L314-326 |

The donate function calls `wXRP.transferFrom` at L318 before updating `wXRPReserves` at L323. Not exploitable because wXRP is a standard ERC20 without transfer hooks, and untracked wXRP surplus cannot be extracted (unwrap checks wXRPReserves, not actual balance).

---

### Unit 13: Admin + Governance (3 INFO)

#### I-21: Vote Weight Inflation via sDGNRS Transfer Between Votes

| Field | Value |
|-------|-------|
| **Unit** | 13 |
| **Contract** | DegenerusAdmin.sol |
| **Function** | `vote()` L452-517 |

The voting system uses live sDGNRS balances rather than snapshots. A voter can vote, transfer sDGNRS, and the new holder can also vote. Total vote weight can exceed circulating supply. Symmetric (both sides can inflate), bounded by supply redistribution, and standard governance pattern for emergency-only systems.

---

#### I-22: Silent Catch on Old Subscription Cancellation During VRF Swap

| Field | Value |
|-------|-------|
| **Unit** | 13 |
| **Contract** | DegenerusAdmin.sol |
| **Function** | `_executeSwap()` L566-627 |

When executing a VRF coordinator swap, the try/catch on old subscription cancellation silently swallows failures. Intentional defensive design -- the governance swap is needed precisely because the old coordinator is broken/stalled.

---

#### I-23: LINK Stuck in Admin After Failed Shutdown Transfer

| Field | Value |
|-------|-------|
| **Unit** | 13 |
| **Contract** | DegenerusAdmin.sol |
| **Function** | `shutdownVrf()` L664-671 |

If LINK transfer fails in the try/catch, LINK remains in Admin. Same root cause as L-02. The silent failure is intentional -- game-over shutdown must succeed regardless of LINK transfer outcome.

---

### Unit 14: Affiliate + Quests + Jackpots (1 INFO)

#### I-24: uint24 Underflow in BAF Scatter Level Targeting at Level 0

| Field | Value |
|-------|-------|
| **Unit** | 14 |
| **Contract** | DegenerusJackpots.sol |
| **Function** | `runBafJackpot()` scatter section L396 |

When `lvl == 0` and `isCentury` is true (since `0 % 100 == 0`), the expression `lvl - 1` underflows to uint24 max. 38 out of 50 scatter rounds would produce no winners. Unawarded ETH is recycled to the future prize pool. At level 0 the prize pool is minimal, so practical effect is negligible.

---

### Unit 15: Libraries (2 INFO)

#### I-25: EntropyLib XOR-Shift Fixed Point at Zero

| Field | Value |
|-------|-------|
| **Unit** | 15 |
| **Contract** | EntropyLib.sol |
| **Function** | `entropyStep()` L16-23 |

`entropyStep(0)` returns 0 (mathematical fixed point of XOR-shift). All entropy seeds originate from Chainlink VRF words -- probability of a VRF word being exactly 0 is 1/2^256. Most callers also XOR with player-specific salt.

---

#### I-26: BitPackingLib Comment Discrepancy on WHALE_BUNDLE_TYPE_SHIFT

| Field | Value |
|-------|-------|
| **Unit** | 15 |
| **Contract** | BitPackingLib.sol |
| **Line** | L59 |

NatSpec comment states "bits 152-154" (implying 3-bit field) but actual field width is 2 bits (bits 152-153). All callers use mask=3 (0b11). Code is correct; only comment is inaccurate.

---

### Unit 1: Game Router + Storage Layout (Originally 2 downgraded observations -- not counted in findings total per Unit 1 report, included here for completeness)

The following were documented in Unit 1 as dismissed/downgraded observations, not as confirmed findings. They are included here for full traceability.

#### I-27: Unchecked Subtraction on claimableWinnings[SDGNRS]

| Field | Value |
|-------|-------|
| **Unit** | 1 |
| **Contract** | DegenerusGame.sol |
| **Function** | `resolveRedemptionLootbox()` L1744-1745 |

Unchecked subtraction relies on mutual exclusion between two debit paths (resolveRedemptionLootbox during active game, claimWinningsStethFirst at gameOver). The checked `claimablePool -= amount` at L1747 provides defense-in-depth. Sound in current code; future maintainability concern.

---

#### I-28: CEI Violation in _setAfKingMode -- External Calls Before State Writes

| Field | Value |
|-------|-------|
| **Unit** | 1 |
| **Contract** | DegenerusGame.sol |
| **Function** | `_setAfKingMode()` L1597-1602 |

Two external calls to BurnieCoinflip execute before state writes (`afKingMode = true`, `afKingActivatedLevel = level`). Callee is a compile-time constant (COINFLIP) with no callback path. Style concern only.

---

#### I-29: stETH submit Return Value Ignored

| Field | Value |
|-------|-------|
| **Unit** | 1 |
| **Contract** | DegenerusGame.sol |

Already disclosed in KNOWN-ISSUES.md. Lido 1:1 mint with 1-2 wei rounding strengthens (not weakens) solvency invariant.

---

## Findings by Contract

| Contract | MEDIUM | LOW | INFO | Total |
|----------|--------|-----|------|-------|
| DegenerusGameDecimatorModule | 1 | 0 | 0 | 1 |
| DegenerusGameDegeneretteModule | 0 | 1 | 1 | 2 |
| DegenerusAdmin | 0 | 1 | 3 | 4 |
| DegenerusGameAdvanceModule | 0 | 0 | 3 | 3 |
| DegenerusGameJackpotModule | 0 | 0 | 5 | 5 |
| DegenerusGameEndgameModule | 0 | 0 | 1 | 1 |
| DegenerusGameGameOverModule | 0 | 0 | 1 | 1 |
| DegenerusGameWhaleModule | 0 | 0 | 1 | 1 |
| DegenerusGameLootboxModule | 0 | 0 | 1 | 1 |
| BurnieCoin | 0 | 0 | 3 | 3 |
| StakedDegenerusStonk | 0 | 0 | 3 | 3 |
| WrappedWrappedXRP | 0 | 0 | 1 | 1 |
| DegenerusJackpots | 0 | 0 | 1 | 1 |
| EntropyLib | 0 | 0 | 1 | 1 |
| BitPackingLib | 0 | 0 | 1 | 1 |
| DegenerusGame (router) | 0 | 0 | 3 | 3 |
| Test code (not deployed) | 0 | 0 | 1 | 1 |
| DegenerusGamePayoutUtils | 0 | 0 | (shared with JackpotModule) | 0 |

---

## Protocol-Wide Security Properties

### Verified SAFE
- **BAF-class cache-overwrite bugs:** ALL checks SAFE across all 16 units
- **ETH conservation:** PROVEN -- all 10 entry points and 9 exit points traced
- **Token supply invariants:** PROVEN -- BURNIE, DGNRS, sDGNRS, WWXRP
- **Delegatecall coherence:** SAFE -- all 10 module boundaries verified
- **State machine consistency:** SAFE -- no permanent stuck states, multiple VRF recovery paths
- **Access control:** COMPLETE -- all external functions use compile-time constant guards, no admin re-pointing
- **Cross-contract reentrancy:** SAFE -- all 7 ETH send sites follow CEI or send to trusted contracts

### Isolation Mechanisms
1. **Do-while break isolation** (AdvanceModule) -- prevents stale local reuse after rngGate chain
2. **Pre-commit before delegatecall** (DegeneretteModule) -- ensures pool/claimable writes committed
3. **rebuyDelta reconciliation** (EndgameModule) -- captures all auto-rebuy writes during resolution

---

## Audit Trail

| Unit | Phase | Functions | Coverage | Findings |
|------|-------|-----------|----------|----------|
| 1. Game Router + Storage | 103 | 177 | 100% | 0 confirmed (2 observations) |
| 2. Day Advancement + VRF | 104 | 40 | 100% | 3 INFO |
| 3. Jackpot Distribution | 105 | 55 | 100% | 5 INFO |
| 4. Endgame + Game Over | 106 | 21 | 100% | 2 INFO |
| 5. Mint + Purchase Flow | 107 | 20 | 100% | 0 confirmed |
| 6. Whale Purchases | 108 | 16 | 100% | 1 INFO |
| 7. Decimator System | 109 | 32 | 100% | 1 MEDIUM |
| 8. Degenerette Betting | 110 | 27 | 100% | 1 LOW + 1 INFO |
| 9. Lootbox + Boons | 111 | 32 | 100% | 1 INFO |
| 10. BURNIE Token + Coinflip | 112 | 71 | 100% | 3 INFO |
| 11. sDGNRS + DGNRS | 113 | 37 | 100% | 3 INFO |
| 12. Vault + WWXRP | 114 | 64 | 100% | 1 INFO |
| 13. Admin + Governance | 115 | 17 | 100% | 1 LOW + 3 INFO |
| 14. Affiliate + Quests + Jackpots | 116 | 61 | 100% | 1 INFO |
| 15. Libraries | 117 | 18 | 100% | 2 INFO |
| 16. Integration Sweep | 118 | 7 surfaces | 100% | 0 new (1 MEDIUM confirmed) |
| **Total** | | **693** | **100%** | **1M + 2L + 29I = 32** |

---

*Master findings report compiled from 16 unit audits, v5.0 Ultimate Adversarial Audit.*
*Phase 119 deliverable DEL-01.*
*Date: 2026-03-25*
