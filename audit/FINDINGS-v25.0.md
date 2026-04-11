# Degenerus Protocol -- Delta Findings Report (v25.0 Full Audit)

**Audit Date:** 2026-04-11
**Methodology:** Three-phase audit: adversarial vulnerability sweep (Phase 214), RNG fresh-eyes analysis (Phase 215), pool and ETH accounting verification (Phase 216). All phases executed by Opus (claude-opus-4-6) with structured reasoning and cross-phase synthesis.
**Scope:** Post-v5.0 delta covering all code changes v6.0 through v24.1. This is a delta supplement -- the v5.0 Master Findings Report (`audit/FINDINGS.md`) remains the baseline.
**Contracts in scope:** DegenerusGame, DegenerusGameAdvanceModule, JackpotModule, DecimatorModule, GameOverModule, MintModule, WhaleModule, DegeneretteModule, StakedDegenerusStonk, DegenerusStonk, BurnieCoin, GNRUS, DegenerusGameStorage, PayoutUtils, BitPackingLib

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 13 |
| **Total** | **13** |

**Overall Assessment:** Zero exploitable vulnerabilities found across all three audit phases. The protocol security posture is maintained through the v6.0-v24.1 development cycle. All 13 findings are informational observations documenting design decisions, safety margins, and code-quality notes with no security impact.

This report is a delta supplement to the v5.0 Master Findings Report (`audit/FINDINGS.md`, 29 INFO). External auditors should read both documents together. Regression verification of all prior findings (I-01 through I-29, F-185-01, F-187-01) is provided in the Regression Appendix section of this document.

---

## Findings

### Phase 214: Adversarial Audit (6 findings)

#### F-25-01: MintModule._purchaseFor Multi-Call Tail After State Writes

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 214-05 (Attack Chains), originally INFO-REENT-01 from 214-01 (Reentrancy/CEI) |
| **Contract** | MintModule |
| **Function** | `_purchaseFor` |

Multi-call tail (affiliate, quests, coinflip) after state writes. CEI ordering is followed -- all storage mutations complete before external calls -- but the volume of sequential external calls is notable.

**Severity justification:** INFO because CEI ordering is respected. All called contracts (DegenerusAffiliate, DegenerusQuests, BurnieCoinflip) are trusted protocol contracts with no callback paths. The rngLockedFlag provides mutual exclusion against concurrent VRF operations. No reentrancy vector exists.

---

#### F-25-02: DegeneretteModule._distributePayout Sequential External Calls

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 214-05 (Attack Chains), originally INFO-REENT-02 from 214-01 (Reentrancy/CEI) |
| **Contract** | DegeneretteModule |
| **Function** | `_distributePayout` |

Two sequential external calls (`coin.mintForGame`, `sdgnrs.transferFromPool`) after state writes. Both are one-way token operations with no callback mechanism.

**Severity justification:** INFO because state is finalized before external calls. BurnieCoin.mintForGame and StakedDegenerusStonk.transferFromPool are one-way token operations that do not invoke callbacks on the caller. No reentrancy window.

---

#### F-25-03: GameOverModule.handleGameOverDrain Sequential Multi-Call

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 214-05 (Attack Chains), originally INFO-REENT-03 from 214-01 (Reentrancy/CEI) |
| **Contract** | GameOverModule |
| **Function** | `handleGameOverDrain` |

Sequential multi-call pattern: 2 burnAtGameOver calls + 2 self-calls + _sendToVault. The `gameOver=true` flag is set before all external calls, preventing all re-entry via purchase, advance, or other game operations.

**Severity justification:** INFO because the gameOver flag is a terminal state toggle that blocks all game entry points. Once set, no function that could mutate game state is reachable. The multi-call pattern is safe by terminal state exclusion.

---

#### F-25-04: StakedDegenerusStonk.poolTransfer Self-Win Burns

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 214-05 (Attack Chains), originally INFO-REENT-04 from 214-01 (Reentrancy/CEI) |
| **Contract** | StakedDegenerusStonk |
| **Function** | `poolTransfer` |

Self-win scenario (`to == address(this)`) now burns tokens instead of performing a no-op. This is a notable behavior change from the v5.0 baseline but is internal-only and has no security impact.

**Severity justification:** INFO because the burn path is reached only when the Game contract is both sender and recipient (self-win). Token supply accounting remains correct -- the burned tokens are removed from totalSupply. No external caller can trigger this path.

---

#### F-25-05: DegenerusGameStorage._setCurrentPrizePool uint256-to-uint128 Cast

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 214-05 (Attack Chains), originally INFO-OVERFLOW-01 from 214-02 (Access Control + Overflow) |
| **Contract** | DegenerusGameStorage |
| **Function** | `_setCurrentPrizePool` |

Explicit `uint256`-to-`uint128` cast does not revert on truncation. All callers verified to always pass values that fit within uint128 bounds.

**Severity justification:** INFO because the maximum possible pool value is bounded by total ETH supply (~1.2e8 ETH = 1.2e26 wei), which is far below uint128 max (~3.4e38 wei) -- a safety margin of approximately 10^12x. Phase 214-02 proved all 271 integer narrowing verdicts SAFE.

---

#### F-25-06: _consolidatePoolsAndRewardJackpots Auto-Rebuy Overwrite by Design

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 214-05 (Attack Chains), originally INFO-STATE-01 from 214-03 (State Corruption + Composition) |
| **Contract** | DegenerusGameAdvanceModule |
| **Function** | `_consolidatePoolsAndRewardJackpots` |

Auto-rebuy pool storage writes during self-calls are overwritten by the memory batch writeback. The auto-rebuy amounts stay in memFuture implicitly, which is the correct behavior by design.

**Severity justification:** INFO because the memory-batch pattern intentionally overwrites intermediate storage writes. Phase 214-03 verified that all 5 memory locals in `_consolidatePoolsAndRewardJackpots` are written back at lines 790-795 with no intermediate value lost. The auto-rebuy ETH is conserved within the memFuture accumulator.

---

### Phase 215: RNG Fresh-Eyes Audit (3 findings)

#### F-25-07: rngLockedFlag Asymmetry -- Daily vs Lootbox

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 215-05 (rngLocked Synthesis), originally F-215-01 from 215-01 (VRF Lifecycle) |
| **Contract** | DegenerusGameStorage / JackpotModule |
| **Function** | rngLockedFlag guard sites (9 revert guards + 8 non-revert references) |

The rngLockedFlag is set for daily VRF requests but NOT for mid-day lootbox RNG requests. Lootbox RNG isolation relies on index advance isolation instead of the flag. This is an intentional design asymmetry documented at Storage L277.

**Severity justification:** INFO because lootbox isolation via index advance is proven equivalent to flag-based isolation. Phase 215-03 Section 2 verified that the index advance mechanism prevents any commitment window overlap between lootbox and daily VRF operations. The asymmetry is a documented design decision, not an omission.

---

#### F-25-08: Gameover prevrandao Fallback -- Validator 1-Bit Bias

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 215-05 (rngLocked Synthesis), originally F-215-02, F-215-03, F-215-04 from plans 215-02 (Backward Trace), 215-03 (Commitment Window), 215-04 (Word Derivation). Three raw findings deduplicated to one root cause. |
| **Contract** | DegenerusGameAdvanceModule |
| **Function** | `_gameOverEntropy` / `_getHistoricalRngFallback` |

The gameover entropy fallback uses historical VRF words XORed with `block.prevrandao` when VRF is dead for 3+ days at gameover. A block validator can bias the result by 1 bit (include/skip block). This is a mixed entropy source (MIXED classification in Phase 215-04).

**Severity justification:** INFO because this is a terminal one-time event with structural mitigations: (1) gameover triggers only once per game lifetime, (2) it requires a 3-day VRF stall which implies Chainlink infrastructure failure, (3) at level 0 the prize pool is minimal, (4) at level 1+ the historical VRF words dilute validator bias below practical exploitation threshold. The design tradeoff is documented in code NatSpec (AdvanceModule L1168-1174).

---

#### F-25-09: Deity Boon Deterministic Fallback Before First VRF

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 215-05 (rngLocked Synthesis), originally F-215-05 from 215-04 (Word Derivation) |
| **Contract** | DegenerusGameAdvanceModule |
| **Function** | `_deityDailySeed` |

The deity boon daily seed uses `keccak256(day, address(this))` as a tier-3 fallback when no VRF word exists. This is fully deterministic and predictable by any observer.

**Severity justification:** INFO because the fallback fires only before the first `advanceGame` call or during a prolonged VRF stall. The deity boon affects cosmetic/utility display only (deity boon selection) -- it does not influence ETH payouts, jackpot outcomes, or any economic game mechanic. Not an economic attack vector.

---

### Phase 216: Pool and ETH Accounting Audit (4 findings)

#### F-25-10: Overpayment Dust in DirectEth Mode

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 216-01 (ETH Conservation), INFO-216-01 |
| **Contract** | DegenerusGame |
| **Function** | `_processMintPayment` (Game.sol L911) |

When `payKind == MintPaymentKind.DirectEth`, the contract accepts `msg.value >= costWei`. Excess ETH (`msg.value - costWei`) stays in the Game contract balance as untracked surplus. This surplus is eventually captured by `distributeYieldSurplus()` and distributed to protocol recipients.

**Severity justification:** INFO because overpayment is retained by the protocol, not lost or extractable by a third party. The `distributeYieldSurplus()` mechanism sweeps untracked surplus into tracked variables. No ETH leak -- the surplus is accounted for, just not immediately.

---

#### F-25-11: Rounding Dust in BPS Calculations

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 216-01 (ETH Conservation), INFO-216-02 |
| **Contract** | Multiple (all BPS arithmetic sites) |
| **Function** | Various fee/split calculations |

All BPS (basis point) calculations use integer division, which truncates. For example, `(totalPrice * 3000) / 10_000` discards the remainder. This dust accumulates in the contract balance as untracked surplus, captured by `distributeYieldSurplus()`.

**Severity justification:** INFO because integer division truncation is a universal property of Solidity arithmetic with no workaround. Amounts are sub-wei per transaction. The surplus capture mechanism ensures no ETH is permanently lost. This is an inherent property of fixed-point arithmetic, not a protocol-specific issue.

---

#### F-25-12: claimablePool Temporary Inequality During Decimator Settlement

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 216-01 (ETH Conservation), INFO-216-03 |
| **Contract** | DegenerusGameStorage / DecimatorModule |
| **Function** | Decimator settlement flow |

During decimator settlement, the full pool is reserved in `claimablePool` before individual claims are credited to `claimableWinnings`, temporarily breaking the invariant `claimablePool == SUM(claimableWinnings[*])`. The inequality is always `claimablePool >= SUM(claimableWinnings[*])` (over-reserved, not under-reserved). Documented at DegenerusGameStorage L344-L345.

**Severity justification:** INFO because the temporary inequality is in the safe direction -- over-reservation means the contract holds more ETH against claims than is owed, never less. The invariant is restored when all decimator claims are credited. This is an intentional design decision to avoid partial settlement complexity.

---

#### F-25-13: uint128 Narrowing Safety Margins Across Pool Variables

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 216-02 (Pool Mutation SSTORE Catalogue), 5 individual uint128 narrowing observations consolidated to one root cause (lines 821, 794, 1290, claimablePool casts, setPendingPools) |
| **Contract** | DegenerusGameAdvanceModule, JackpotModule, DegenerusGameStorage |
| **Function** | `_consolidatePoolsAndRewardJackpots`, `_processDailyEth`, `_setCurrentPrizePool`, `_setPrizePools`, claimablePool cast sites |

Five SSTORE sites across the pool mutation catalogue involve uint128 narrowing casts. All share the same root cause: pool variables stored as uint128 receive values computed as uint256.

**Severity justification:** INFO because all narrowings are proven safe by Phase 214-02 with a 10^12x safety margin. Maximum possible pool value is bounded by total ETH supply (~1.2e26 wei), far below uint128 max (~3.4e38 wei). The 75-site SSTORE catalogue (Phase 216-02) confirmed all verdicts SAFE. These are observations about type narrowing patterns, not exploitable conditions.

---

## Summary Statistics

### By Severity

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 13 |

### By Source Phase

| Phase | Description | Findings |
|-------|-------------|----------|
| 214 | Adversarial Audit | 6 (F-25-01 through F-25-06) |
| 215 | RNG Fresh-Eyes | 3 (F-25-07 through F-25-09) |
| 216 | Pool & ETH Accounting | 4 (F-25-10 through F-25-13) |

### By Contract

| Contract | Findings |
|----------|----------|
| MintModule | 1 (F-25-01) |
| DegeneretteModule | 1 (F-25-02) |
| GameOverModule | 1 (F-25-03) |
| StakedDegenerusStonk | 1 (F-25-04) |
| DegenerusGameStorage | 2 (F-25-05, F-25-12) |
| DegenerusGameAdvanceModule | 3 (F-25-06, F-25-08, F-25-09) |
| DegenerusGame | 1 (F-25-10) |
| Multiple (BPS sites) | 1 (F-25-11) |
| Multiple (pool cast sites) | 1 (F-25-13) |

---

## Audit Trail

| Phase | Scope | Plans | Findings | Verdict |
|-------|-------|-------|----------|---------|
| 214 | Adversarial: reentrancy/CEI, access control/overflow, state corruption/composition, storage layout, attack chains | 5 | 6 INFO | SAFE |
| 215 | RNG fresh-eyes: VRF lifecycle, backward trace, commitment window, word derivation, rngLocked synthesis | 5 | 5 raw / 3 deduplicated INFO | SOUND |
| 216 | Pool & ETH accounting: ETH conservation proof, SSTORE catalogue, cross-module flow verification | 3 | 8 raw / 4 consolidated INFO | SOUND |
| **Total** | **3-phase delta audit (v6.0-v24.1)** | **13** | **13 INFO** | **SAFE** |

---

## Regression Check: v5.0 Findings (I-01 through I-29)

Regression verification of all 29 INFO findings from the v5.0 Master Findings Report (`audit/FINDINGS.md`). Each finding is checked against current contract source with code-level evidence. Classification uses the Phase 213 delta extraction (`213-DELTA-EXTRACTION.md`) for structural changes and direct grep for function-level verification.

**Status key:**
- **STILL APPLIES** -- Code unchanged or semantically equivalent; finding remains valid as documented
- **FIXED** -- Code was changed in a way that resolves the finding
- **SUPERSEDED** -- Function was modified and finding's concern is addressed differently
- **STRUCTURALLY RESOLVED** -- Function or module was deleted; finding is moot

| Finding | Contract | Status | Evidence |
|---------|----------|--------|----------|
| I-01 | AdvanceModule | STILL APPLIES | `ADVANCE_BOUNTY_ETH` computed at call start using `PriceLookupLib.priceForLevel(lvl)` (L435); level can change during jackpot phase within same call. Bounty now paid via `coinflip.creditFlip` (L433-437). Same staleness concern. |
| I-02 | AdvanceModule | STRUCTURALLY RESOLVED | `lastLootboxRngWord` variable removed entirely. All lootbox resolution now uses `lootboxRngWordByIndex[index]` exclusively (AdvanceModule L1074, L1546; Storage L1370). The global staleness concern is moot -- per-index mapping is the sole source. |
| I-03 | Test code | STILL APPLIES | `_readKeyForLevel` helper still present in `test/fuzz/TicketLifecycle.t.sol` (L204, L340, L381, L434). Same double-buffer slot confusion in test assertions. Not deployed contract code. |
| I-04 | JackpotModule | STILL APPLIES | `distributeYieldSurplus` (JackpotModule L716-723) reads `obligations` snapshot from `_getCurrentPrizePool() + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator`. Conservative staleness direction unchanged. |
| I-05 | MintModule (moved from JackpotModule) | STILL APPLIES | Assembly slot calculation `add(levelSlot, traitId)` at MintModule L612 for `traitBurnTicket` mapping. Function `_raritySymbolBatch` moved from JackpotModule to MintModule during v16.0 refactor. Same non-obvious but correct layout assumption. Contract non-upgradeable. |
| I-06 | MintModule (moved from JackpotModule) | STILL APPLIES | `processTicketBatch` moved to MintModule (L656). Processed counter approximation `processed += writesUsed >> 1` at L700. Same LCG seed derivation impact on resume. Traits still aesthetic only. |
| I-07 | JackpotModule | FIXED | Original double `_getFuturePrizePool()` read in `_runEarlyBirdLootboxJackpot` (formerly L774-778) eliminated. Current implementation at JackpotModule L636 reads once into `futurePoolLocal` and operates on that single value. |
| I-08 | JackpotModule + PayoutUtils | STILL APPLIES | `_calcAutoRebuy` in PayoutUtils L63-66: when `takeProfit == 0`, `c.reserved = 0` and `c.rebuyAmount = weiAmount`. Division remainder `weiAmount - (baseTickets * ticketPrice)` at L77-81 is dropped as dust. Same economic bound (less than ticketPrice/4). |
| I-09 | AdvanceModule (moved from EndgameModule) | FIXED | `RewardJackpotsSettled` event at AdvanceModule L796 now emits `memFuture` AFTER all reconciliation (BAF jackpot subtraction L724, decimator subtraction L734-735, keep roll L764-768, drawdown L784-786). The pre-reconciliation staleness from the original EndgameModule implementation is resolved by inlining. |
| I-10 | GameOverModule | STILL APPLIES | `handleGameOverDrain` (GameOverModule L79) still uses `unchecked` arithmetic at L118-121 for deity pass refund loop (`claimableWinnings[owner] += refund`, `totalRefunded += refund`, `budget -= refund`). Same ETH supply constraint safety argument applies. |
| I-11 | WhaleModule | STILL APPLIES | Multi-quantity whale purchase calls `_rewardWhaleBundleDgnrs` in a loop (WhaleModule L329-333). Each iteration reads FRESH `dgnrs.poolBalance(Whale)` at L704. Diminishing returns on multi-bundle DGNRS reward unchanged. |
| I-12 | DegeneretteModule | STILL APPLIES | ETH bet resolution checks `prizePoolFrozen` at DegeneretteModule L695. During freeze, payouts route through pending pool side-channel (L702-708). Transient freeze during `advanceGame` still blocks direct ETH resolution path. |
| I-13 | LootboxModule | SUPERSEDED | `_applyBoon` rewritten with upgrade-only tier semantics. Coinflip boons: `if (newTier > existingTier)` at L1331. Lootbox: `newTier > existingTier ? newTier : existingTier` at L1352. Purchase: L1378. Decimator: L1404. Deity boons can no longer downgrade existing higher-tier boons. Original overwrite concern is resolved. |
| I-14 | BurnieCoin | STILL APPLIES | Standard ERC20 `approve` at BurnieCoin L285-292. No change to approve/transferFrom pattern. Same front-running concern. Game contract bypass (trusted contract pattern) unchanged. |
| I-15 | BurnieCoin | STILL APPLIES | `vaultMintTo` at BurnieCoin L517-529. Self-mint path (vault calling `vaultMintTo(VAULT, amount)`) still creates circulating tokens held by vault. `_transfer` redirect to vault escrow still makes it a no-op. Supply invariant maintained. |
| I-16 | BurnieCoin | STILL APPLIES | `burnForCoinflip` (L420) and `mintForGame` (L429) revert with `OnlyGame()` error for coinflip/game caller checks. Misleading error name unchanged. `mintForGame` now accepts both COINFLIP and GAME (L429), making the `OnlyGame` name even less accurate. |
| I-17 | StakedDegenerusStonk | STILL APPLIES | `claimRedemption` at sDGNRS L621: `totalRolledEth = (claim.ethValueOwed * roll) / 100`. Per-claimant floor division dust in `pendingRedemptionEthValue` unchanged. Comment at L619-620 explicitly documents the dust. |
| I-18 | StakedDegenerusStonk | STILL APPLIES | `_submitGamblingClaimFrom` at sDGNRS L794: `claim.burnieOwed += uint96(burnieOwed)`. Unchecked uint96 narrowing cast unchanged. Comment at L793 documents the safety bound. |
| I-19 | StakedDegenerusStonk | STILL APPLIES | `previewBurn` (L694) and `burnieReserve` (L725): subtraction of `pendingRedemptionEthValue`/`pendingRedemptionBurnie` from balance can underflow on negative stETH rebase. View functions still revert instead of returning data. |
| I-20 | WrappedWrappedXRP | STRUCTURALLY RESOLVED | `donate()` function and `wXRPReserves` variable removed entirely. WWXRP contract was rewritten (289 lines, no wXRP wrapping mechanism). The CEI ordering concern is moot -- the function no longer exists. |
| I-21 | DegenerusAdmin | STILL APPLIES | `vote` at DegenerusAdmin L703-724 uses live sDGNRS balances via `_voterWeight()` (L714). No snapshot mechanism. Same vote weight inflation via sDGNRS transfer between votes. Comment at L713 documents: "Safe: VRF dead = supply frozen". |
| I-22 | DegenerusAdmin | STILL APPLIES | `_executeSwap` at DegenerusAdmin L859: old subscription cancellation uses `try/catch` at L875/L952. Silent failure by design -- governance swap needed precisely when old coordinator is broken. |
| I-23 | DegenerusAdmin | STILL APPLIES | `shutdownVrf` at DegenerusAdmin L944-967: LINK transfer in `try/catch` at L958. If transfer fails, LINK remains in Admin. Same root cause as dismissed L-02. Silent failure intentional for game-over shutdown. |
| I-24 | DegenerusJackpots | STILL APPLIES | `runBafJackpot` scatter section at DegenerusJackpots L396: `uint24 maxBack = lvl > 99 ? 99 : lvl - 1`. When `lvl == 0` (century check passes since `0 % 100 == 0`), `lvl - 1` underflows to uint24 max. Scatter rounds at level 0 target non-existent levels, returning empty. ETH recycled to future pool. |
| I-25 | EntropyLib | STILL APPLIES | `entropyStep` at EntropyLib L16-23: XOR-shift `state ^= state << 7; state ^= state >> 9; state ^= state << 8`. Fixed point at zero unchanged -- `entropyStep(0)` returns 0. VRF seed origin and player salt XOR mitigate. |
| I-26 | BitPackingLib | FIXED | Comment at BitPackingLib L16 now correctly reads `[152-153] WHALE_BUNDLE_TYPE_SHIFT -- Bundle type (2 bits)`. Original finding noted comment said "bits 152-154" (3 bits). Comment corrected to match actual 2-bit field width. |
| I-27 | DegenerusGame | STILL APPLIES | `resolveRedemptionLootbox` at Game L1703-1704: unchecked subtraction on `claimableWinnings[SDGNRS]`. Mutual exclusion safety documented in comment at L1698-1700. Checked `claimablePool -= uint128(amount)` at L1706 provides defense-in-depth. |
| I-28 | DegenerusGame | STILL APPLIES | `_setAfKingMode` at Game L1536-1575: external calls to `coinflip.setCoinflipAutoRebuy` (L1567) and `coinflip.settleFlipModeChange` (L1570) execute before state writes `state.afKingMode = true` (L1571) and `state.afKingActivatedLevel = level` (L1572). Coinflip is compile-time constant with no callback. Style concern only. |
| I-29 | DegenerusGame | STILL APPLIES | `steth.submit{value: amount}(address(0))` at Game L1810: return value captured in try block but not used. Already disclosed in KNOWN-ISSUES.md. Lido 1:1 mint with 1-2 wei rounding strengthens solvency invariant. |
