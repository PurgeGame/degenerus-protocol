# DegenerusGameEndgameModule.sol -- Function-Level Audit

**Contract:** DegenerusGameEndgameModule
**File:** contracts/modules/DegenerusGameEndgameModule.sol
**Lines:** 518
**Solidity:** 0.8.34
**Inherits:** DegenerusGamePayoutUtils -> DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

The EndgameModule handles three distinct endgame-related operations during level transitions:

1. **Top Affiliate Reward** (`rewardTopAffiliate`): Awards DGNRS tokens (1% of affiliate pool balance) to the top affiliate for a completed level.
2. **Reward Jackpots** (`runRewardJackpots`): Resolves BAF (Big-Ass Flip) jackpots every 10 levels and Decimator jackpots at x5/x00 levels, drawing from the future prize pool.
3. **Whale Pass Claims** (`claimWhalePass`): Allows players to claim deferred large lootbox rewards (>5 ETH) as deterministic ticket distributions across 100 levels.

The module also contains internal helpers for auto-rebuy logic, jackpot ticket distribution with tiered sizing, and probabilistic ticket roll resolution.

**External contract references (compile-time constants):**
- `affiliate` = IDegenerusAffiliate (ContractAddresses.AFFILIATE)
- `jackpots` = IDegenerusJackpots (ContractAddresses.JACKPOTS)
- `dgnrs` = IDegenerusStonk (ContractAddresses.DGNRS)

---

## Function Audit

### `rewardTopAffiliate(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rewardTopAffiliate(uint24 lvl) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): The level to reward the top affiliate for |
| **Returns** | none |

**State Reads:** None (all data fetched via external calls to `affiliate` and `dgnrs` contracts)

**State Writes:** None (all state changes happen in external contracts -- DegenerusStonk and DegenerusAffiliate)

**Callers:**
- `DegenerusGameAdvanceModule._rewardTopAffiliate(lvl)` via delegatecall during level transition (after final jackpot cap reached, line 276 of AdvanceModule)

**Callees:**
- `affiliate.affiliateTop(lvl)` -- external call to get top affiliate address and score for the level
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)` -- external call to get DGNRS affiliate pool balance
- `dgnrs.transferFromPool(IDegenerusStonk.Pool.Affiliate, top, dgnrsReward)` -- external call to transfer DGNRS reward

**ETH Flow:** No ETH movement. This function exclusively moves DGNRS tokens from the Affiliate pool to the top affiliate address.

**Invariants:**
- If no top affiliate exists (address(0)), function returns early with no effect
- Reward is always 1% of current affiliate pool balance (AFFILIATE_POOL_REWARD_BPS = 100 / 10000)
- `paid` may be less than `dgnrsReward` if pool has insufficient balance (handled by `transferFromPool`)

**NatSpec Accuracy:** NatSpec says "Mint trophy and DGNRS reward" but the function only handles DGNRS reward distribution. There is no trophy minting in this function. The trophy logic appears to be handled separately. Minor NatSpec inaccuracy -- the "mint trophy" part is misleading since no trophy is minted here.

**Gas Flags:**
- Three external calls (affiliateTop, poolBalance, transferFromPool) are unavoidable and correctly ordered
- `dgnrsReward` calculation uses multiplication before division (correct, avoids precision loss)
- No redundant reads

**Verdict:** CORRECT -- with minor NatSpec inaccuracy (mentions trophy minting that does not occur in this function)

---

### `runRewardJackpots(uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runRewardJackpots(uint24 lvl, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level to resolve jackpots for; `rngWord` (uint256): VRF entropy for jackpot selection |
| **Returns** | none |

**State Reads:**
- `futurePrizePool` -- cached as `futurePoolLocal` and `baseFuturePool` for pre/post comparison

**State Writes:**
- `futurePrizePool` -- updated only if changed (gas optimization: skips SSTORE when no jackpot fires)
- `claimablePool` -- incremented by `claimableDelta` when non-zero
- Additional writes via `_runBafJackpot` and delegated calls (see callees)

**Callers:**
- `DegenerusGameAdvanceModule._runRewardJackpots(lvl, rngWord)` via delegatecall during level transition (after final jackpot cap reached, line 277 of AdvanceModule)

**Callees:**
- `_runBafJackpot(bafPoolWei, lvl, rngWord)` -- private, for BAF jackpot at every 10th level
- `IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord)` -- external self-call for Decimator jackpot at x00 and x5 levels

**ETH Flow:**

| Trigger | Source Pool | Amount | Destination |
|---------|-----------|--------|-------------|
| BAF (lvl % 10 == 0) | futurePrizePool | 10-25% of base | Winners via _runBafJackpot (split: claimable ETH + lootbox tickets) |
| Decimator (lvl % 100 == 0) | futurePrizePool | 30% of base | Winners via runDecimatorJackpot (deferred claims in claimablePool) |
| Decimator (lvl % 10 == 5, not x95) | futurePrizePool | 10% of current local | Winners via runDecimatorJackpot (deferred claims in claimablePool) |

BAF pool percentages by level:
- Level x00 (100, 200...): 20% of base future pool
- Level 50: 25% of base future pool
- All other x0 levels (10, 20, 30, 40, 60, 70, 80, 90): 10% of base future pool

Decimator pool percentages:
- Level x00: 30% of base future pool (uses `baseFuturePool`)
- Levels x5 (5, 15, 25...85, not 95): 10% of current `futurePoolLocal` (after BAF deduction, if applicable)

**Key accounting logic:**
- BAF: Full pool pulled out, then `netSpend` (pool minus refund) consumed; lootbox ETH recycled back into futurePool; unused portion returned
- Decimator x00: `decPoolWei - returnWei` = spend; deducted from futurePoolLocal; spend added to claimableDelta
- Decimator x5: Same pattern as x00 but uses current `futurePoolLocal` (post-BAF) and 10%

**Invariants:**
- `futurePrizePool` is only written when it actually changed (pre/post comparison with `baseFuturePool`)
- `claimablePool` is only incremented when `claimableDelta != 0`
- At level x00, BOTH BAF (20%) and Decimator (30%) fire -- but BAF uses `baseFuturePool` for its percentage, while Decimator also uses `baseFuturePool`. Total maximum draw from future pool at x00 = 20% + 30% = 50% (minus refunds/returns)
- At levels where both BAF and x5 Decimator fire (impossible: x0 and x5 are mutually exclusive modulo 10), no overlap occurs
- Level 95 is explicitly excluded from Decimator (`prevMod100 != 95`)

**NatSpec Accuracy:** NatSpec documents BAF and Decimator trigger schedules accurately. The NatSpec shows level 100 BAF at 20% and level 100 Decimator at 30%, matching the code. The note about Decimator "NOT 95" is correct.

**Gas Flags:**
- `baseFuturePool` captures the initial value for percentage calculations -- correct pattern for multi-draw scenarios
- `futurePoolLocal` vs `baseFuturePool` comparison avoids unnecessary SSTORE when no jackpot fires
- The x00 Decimator uses `baseFuturePool` for its 30% calculation, not the post-BAF `futurePoolLocal`. This means at level 100, BAF 20% and Decimator 30% are both computed from the original pool, potentially summing to >50% of the original if refunds are zero. However, since BAF refunds unused ETH back into `futurePoolLocal`, and the Decimator also returns unused ETH via `returnWei`, the actual net draw is bounded by available funds.

**Concern: Overlapping draws at x00 levels.** At level x00 (e.g., 100), BAF draws 20% and Decimator draws 30% -- both from `baseFuturePool`. The BAF draw is subtracted from `futurePoolLocal` first (line 148), then the Decimator draw is subtracted (line 175). But the Decimator percentage is computed from `baseFuturePool`, not from the already-reduced `futurePoolLocal`. In the worst case (zero refund from BAF, zero return from Decimator), total draw = 50% of `baseFuturePool`. Since `futurePoolLocal` starts at `baseFuturePool` and only 50% is drawn, this never underflows. The pattern is intentional -- each jackpot gets a guaranteed percentage of the original pool. Verified safe.

**Verdict:** CORRECT

---

### `claimWhalePass(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimWhalePass(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address to claim whale pass rewards for |
| **Returns** | none |

**State Reads:**
- `whalePassClaims[player]` -- number of half-passes owed
- `level` -- current game level (for startLevel calculation)

**State Writes:**
- `whalePassClaims[player] = 0` -- cleared before awarding (reentrancy-safe pattern)
- `mintPacked_[player]` -- updated via `_applyWhalePassStats` (level count, frozen level, bundle type, last level, day)
- `ticketsOwedPacked[lvl][player]` -- updated for each of 100 levels via `_queueTicketRange`
- `ticketQueue[lvl]` -- player pushed to queue for each new level via `_queueTicketRange`

**Callers:**
- `DegenerusGame.claimWhalePass(player)` via `_claimWhalePassFor` delegatecall -- externally callable by anyone
- Also called from lootbox module when resolving large lootbox wins

**Callees:**
- `_applyWhalePassStats(player, startLevel)` -- internal (from DegenerusGameStorage), updates mint stats
- `_queueTicketRange(player, startLevel, 100, uint32(halfPasses))` -- internal (from DegenerusGameStorage), queues tickets across 100 levels

**ETH Flow:** No direct ETH movement. This function converts previously deferred lootbox ETH credit (stored as half-pass count in `whalePassClaims`) into ticket distributions. The ETH was already accounted for when `_queueWhalePassClaimCore` was called (lootbox ETH stays in `futurePrizePool`).

**Invariants:**
- If `halfPasses == 0`, returns early with no effect (prevents empty claims)
- Claim is zeroed BEFORE awarding tickets (prevents double-claiming, reentrancy-safe)
- `startLevel = level + 1` -- tickets start at next level to avoid giving tickets for an already-active level during jackpot phase
- Each half-pass gives 1 ticket per level for 100 consecutive levels (e.g., 3 half-passes = 300 total tickets)
- `uint32(halfPasses)` cast is safe because ETH supply limits the maximum number of half-passes (documented in comment)

**NatSpec Accuracy:** NatSpec says "Claim deferred whale pass rewards for a player" and "Awards deterministic tickets based on pre-calculated half-pass count" -- accurate. The note about starting at `level + 1` matches the code.

**Gas Flags:**
- `_queueTicketRange` loops over 100 levels, performing a storage read + potential write per level. This is O(100) SSTOREs in the worst case. Gas cost is significant but bounded and unavoidable for the ticket distribution pattern.
- `_applyWhalePassStats` performs packed storage updates (single SSTORE)

**Verdict:** CORRECT
