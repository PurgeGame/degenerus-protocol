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

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount, uint256 entropy) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): Address to credit; `weiAmount` (uint256): ETH amount to credit; `entropy` (uint256): RNG seed for fractional ticket roll |
| **Returns** | `claimableDelta` (uint256): Amount to add to claimablePool for this credit |

**State Reads:**
- `autoRebuyState[beneficiary]` -- checks if auto-rebuy is enabled for the player
- `level` -- current game level (passed to `_calcAutoRebuy`)

**State Writes (auto-rebuy path):**
- `futurePrizePool += calc.ethSpent` -- if target level is future (75% chance)
- `nextPrizePool += calc.ethSpent` -- if target level is next (25% chance)
- `ticketsOwedPacked[calc.targetLevel][beneficiary]` -- via `_queueTickets`
- `ticketQueue[calc.targetLevel]` -- via `_queueTickets` (if new entry)
- `claimableWinnings[beneficiary] += calc.reserved` -- via `_creditClaimable` (take-profit portion)
- `claimablePool += calc.reserved` -- direct write for take-profit portion

**State Writes (normal path):**
- `claimableWinnings[beneficiary] += weiAmount` -- via `_creditClaimable`

**Callers:**
- `_runBafJackpot` -- for ETH portions of BAF jackpot winnings (large winner 50% ETH, small even-index 100% ETH)

**Callees:**
- `_calcAutoRebuy(beneficiary, weiAmount, entropy, state, level, 13_000, 14_500)` -- pure helper from DegenerusGamePayoutUtils
- `_creditClaimable(beneficiary, weiAmount)` -- internal (from DegenerusGamePayoutUtils)
- `_creditClaimable(beneficiary, calc.reserved)` -- for take-profit portion (auto-rebuy path)
- `_queueTickets(beneficiary, calc.targetLevel, calc.ticketCount)` -- internal (from DegenerusGameStorage)

**ETH Flow:**

| Auto-Rebuy State | Path | Source | Destination |
|-------------------|------|--------|-------------|
| Disabled | Normal | (incoming weiAmount) | claimableWinnings[beneficiary] |
| Enabled, no tickets | Normal fallback | (incoming weiAmount) | claimableWinnings[beneficiary] |
| Enabled, has tickets | Rebuy | (incoming weiAmount - reserved) | futurePrizePool or nextPrizePool (via ethSpent) + tickets |
| Enabled, has tickets | Take-profit | (reserved portion) | claimableWinnings[beneficiary] + claimablePool |

**Key auto-rebuy bonus BPS:** 13,000 (130% base) / 14,500 (145% afKing mode). These are higher than the standard auto-rebuy bonuses used elsewhere, reflecting the jackpot reward context.

**Invariants:**
- Returns 0 immediately if `weiAmount == 0`
- Auto-rebuy path returns `claimableDelta = 0` when tickets are generated (ETH goes to prize pools, not claimable)
- Normal path returns `claimableDelta = weiAmount` (full amount goes to claimable)
- Take-profit: `calc.reserved` is a multiple of `state.takeProfit` extracted from `weiAmount` before rebuy conversion
- `calc.hasTickets = false` triggers normal credit fallback even when auto-rebuy is enabled (happens when amount is too small for even 1 ticket at target price)

**NatSpec Accuracy:** NatSpec accurately describes the auto-rebuy flow, take-profit mechanism, and fractional dust handling. The claim about "fractional dust is dropped unconditionally" refers to dust within the auto-rebuy calculation (amounts smaller than a single ticket price at the target level) -- this dust is not explicitly credited to claimable in the auto-rebuy path and is implicitly absorbed into the prize pool via `calc.ethSpent` rounding. This is by design.

**Gas Flags:**
- `autoRebuyState[beneficiary]` is a struct SLOAD -- memory copy is efficient
- `_calcAutoRebuy` is `pure` -- no additional storage reads
- Single branch for auto-rebuy vs normal flow

**Verdict:** CORRECT

---

### `_runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) private returns (uint256 netSpend, uint256 claimableDelta, uint256 lootboxToFuture)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): Total ETH for BAF distribution; `lvl` (uint24): Level triggering the BAF; `rngWord` (uint256): VRF entropy |
| **Returns** | `netSpend` (uint256): Amount consumed from future pool; `claimableDelta` (uint256): ETH credited to claimable balances; `lootboxToFuture` (uint256): Lootbox ETH recycled into future pool |

**State Reads:**
- None directly (all inputs passed as parameters)

**State Writes (via callees):**
- `claimableWinnings[winner]` -- via `_addClaimableEth` -> `_creditClaimable` (ETH portions)
- `claimablePool` -- via `_addClaimableEth` (take-profit auto-rebuy) or returned as claimableDelta to caller
- `futurePrizePool` / `nextPrizePool` -- via `_addClaimableEth` (auto-rebuy path)
- `ticketsOwedPacked[targetLevel][winner]` -- via `_awardJackpotTickets` -> `_queueLootboxTickets` (lootbox portions)
- `ticketQueue[targetLevel]` -- via `_awardJackpotTickets` -> `_queueLootboxTickets`
- `whalePassClaims[winner]` -- via `_queueWhalePassClaimCore` (large lootbox deferred)

**Callers:**
- `runRewardJackpots` -- at every 10th level during level transition

**Callees:**
- `jackpots.runBafJackpot(poolWei, lvl, rngWord)` -- external call to get winners array, amounts, and refund
- `_addClaimableEth(winner, ethPortion, rngWord)` -- for ETH portions of large winners and full ETH for small even-index winners
- `_awardJackpotTickets(winner, lootboxPortion, lvl, rngWord)` -- for lootbox portions of large winners and full lootbox for small odd-index winners
- `_queueWhalePassClaimCore(winner, lootboxPortion)` -- for large lootbox portions exceeding LOOTBOX_CLAIM_THRESHOLD

**ETH Flow:**

Winners are split into two categories based on a 5% pool threshold (`poolWei / 20`):

| Winner Type | Condition | ETH Path | Lootbox Path |
|-------------|-----------|----------|-------------|
| Large | `amount >= poolWei/20` | 50% (amount/2) to claimable via `_addClaimableEth` | 50% (amount - amount/2) to tickets via `_awardJackpotTickets` or deferred via `_queueWhalePassClaimCore` |
| Small even-index | `amount < poolWei/20, i%2==0` | 100% to claimable via `_addClaimableEth` | None |
| Small odd-index | `amount < poolWei/20, i%2==1` | None | 100% to tickets via `_awardJackpotTickets` |

Lootbox sub-routing (within `_awardJackpotTickets` and direct):
- Small lootbox (<=5 ETH, i.e. `<= LOOTBOX_CLAIM_THRESHOLD`): immediate ticket awards
- Large lootbox (>5 ETH): deferred via `_queueWhalePassClaimCore` (whale pass claim)

**Return values:**
- `netSpend = poolWei - refund` -- refund is returned by `jackpots.runBafJackpot`
- `claimableDelta` -- sum of all ETH credited to claimable balances
- `lootboxToFuture = lootboxTotal` -- all lootbox ETH stays in future pool

**Invariants:**
- First winner (winners[0]) should receive BAF trophy per NatSpec, but no trophy logic exists in this function (see NatSpec note below)
- `lootboxToFuture` equals total lootbox amounts across all winners (sum of lootbox portions)
- `netSpend + refund = poolWei` (total pool is fully accounted for)
- Large winner 50/50 split: `ethPortion = amount / 2`, `lootboxPortion = amount - ethPortion` -- handles odd amounts correctly (lootbox gets the extra wei)

**NatSpec Accuracy:** NatSpec mentions "First winner (winners[0]) receives BAF trophy" in the Trophy section, but no trophy awarding code exists in this function. This is a NatSpec-only artifact -- trophies may be awarded elsewhere (e.g., in the Jackpots contract's `runBafJackpot`). Minor inaccuracy in the NatSpec within this function.

**Gas Flags:**
- `unchecked { ++i; }` in the loop is correct (loop counter cannot overflow)
- Winner array length is fetched once and cached as `winnersLen`
- `largeWinnerThreshold` computed once outside the loop
- Entropy (`rngWord`) is threaded through `_awardJackpotTickets` for deterministic sub-rolls

**Verdict:** CORRECT

---

### `_awardJackpotTickets(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardJackpotTickets(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): Address to receive rewards; `amount` (uint256): ETH amount for ticket conversion; `minTargetLevel` (uint24): Minimum target level for tickets; `entropy` (uint256): RNG state |
| **Returns** | Updated entropy state (uint256) |

**State Reads:** None directly (all via callees)

**State Writes (via callees):**
- `whalePassClaims[winner]` -- via `_queueWhalePassClaimCore` (large amounts > 5 ETH)
- `claimableWinnings[winner]` -- via `_queueWhalePassClaimCore` (remainder < HALF_WHALE_PASS_PRICE)
- `claimablePool` -- via `_queueWhalePassClaimCore` (remainder)
- `ticketsOwedPacked[targetLevel][winner]` -- via `_jackpotTicketRoll` -> `_queueLootboxTickets` (small/medium amounts)
- `ticketQueue[targetLevel]` -- via `_jackpotTicketRoll` -> `_queueLootboxTickets`

**Callers:**
- `_runBafJackpot` -- for lootbox portions of both large winners (50% lootbox split) and small odd-index winners (100% lootbox)

**Callees:**
- `_queueWhalePassClaimCore(winner, amount)` -- for large amounts (> 5 ETH / LOOTBOX_CLAIM_THRESHOLD)
- `_jackpotTicketRoll(winner, amount, minTargetLevel, entropy)` -- for very small amounts (<= 0.5 ETH), single roll
- `_jackpotTicketRoll(winner, halfAmount, minTargetLevel, entropy)` -- first roll for medium amounts (0.5-5 ETH)
- `_jackpotTicketRoll(winner, secondAmount, minTargetLevel, entropy)` -- second roll for medium amounts

**ETH Flow:** No direct ETH movement. This function routes incoming lootbox-designated ETH to the appropriate ticket distribution mechanism:

| Amount Range | Routing | Ticket Rolls |
|-------------|---------|-------------|
| > 5 ETH | Deferred whale pass via `_queueWhalePassClaimCore` | 0 (deferred) |
| 0.5 - 5 ETH | Split in half, two probabilistic rolls | 2 |
| <= 0.5 ETH | Single probabilistic roll | 1 |

**Invariants:**
- Tiered routing ensures gas efficiency: large payouts defer to claim system, medium payouts get two chances at level targeting, small payouts get one chance
- For medium amounts: `halfAmount = amount / 2`, `secondAmount = amount - halfAmount` -- correctly handles odd wei amounts (second roll gets the extra wei)
- Entropy is threaded through and returned to maintain deterministic PRNG chain

**NatSpec Accuracy:** NatSpec describes "Small (0.5-5 ETH)" and "Large (> 5 ETH)" tiers accurately. The "2 probabilistic rolls" for medium tier and "100-ticket chunks" for large tier are accurate descriptions of the actual behavior.

**Gas Flags:**
- Early return for large amounts (>5 ETH) avoids unnecessary roll computation
- Medium tier splits into 2 rolls for better level diversity rather than 1 large roll
- No redundant computations

**Verdict:** CORRECT

---

### `_jackpotTicketRoll(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _jackpotTicketRoll(address winner, uint256 amount, uint24 minTargetLevel, uint256 entropy) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): Address to receive tickets; `amount` (uint256): ETH amount for this roll; `minTargetLevel` (uint24): Minimum target level; `entropy` (uint256): RNG state |
| **Returns** | Updated entropy state (uint256) |

**State Reads:** None directly

**State Writes (via callees):**
- `ticketsOwedPacked[targetLevel][winner]` -- via `_queueLootboxTickets` -> `_queueTicketsScaled`
- `ticketQueue[targetLevel]` -- via `_queueLootboxTickets` -> `_queueTicketsScaled` (if new entry)

**Callers:**
- `_awardJackpotTickets` -- for small and medium lootbox amounts (1-2 rolls per award)

**Callees:**
- `EntropyLib.entropyStep(entropy)` -- pure, advances PRNG state
- `PriceLookupLib.priceForLevel(targetLevel)` -- pure, gets ticket price for target level
- `_queueLootboxTickets(winner, targetLevel, quantityScaled)` -- internal (from DegenerusGameStorage)

**ETH Flow:** No direct ETH movement. Converts an ETH amount into scaled tickets at a probabilistically-selected target level.

**Probability distribution for target level:**

| Roll Range | Probability | Target Level | Description |
|-----------|------------|-------------|-------------|
| 0-29 | 30% | minTargetLevel | Current level ticket |
| 30-94 | 65% | minTargetLevel + 1 to +4 | Near-future levels (1-4 ahead) |
| 95-99 | 5% | minTargetLevel + 5 to +50 | Far-future levels (rare, 5-50 ahead) |

**Ticket quantity calculation:**
- `targetPrice = PriceLookupLib.priceForLevel(targetLevel)` -- actual game price for the target level
- `quantityScaled = (amount * TICKET_SCALE) / targetPrice` -- scaled ticket count (2 decimal places)
- Passed to `_queueLootboxTickets` which handles remainder accumulation

**Roll mechanics:**
- `entropy = EntropyLib.entropyStep(entropy)` -- xorshift64 PRNG step
- `roll = entropy % 100` (via manual modulo: `entropy - (entropyDiv100 * 100)`)
- For near-future offset: `1 + (entropyDiv100 % 4)` uses the upper bits (after dividing by 100) for independence from the roll
- For far-future offset: `5 + (entropyDiv100 % 46)` similarly uses upper bits

**Invariants:**
- Entropy is always advanced before use (deterministic chain)
- `quantityScaled` may be 0 if `amount < targetPrice / TICKET_SCALE` -- in that case `_queueLootboxTickets` returns early (no effect)
- Target level can exceed current game level by up to 50 -- these future tickets will be processed when those levels are reached
- Price increases with level, so higher target levels yield fewer tickets per ETH (risk/reward tradeoff is built into the probability distribution)

**NatSpec Accuracy:** NatSpec accurately describes "Selects target level based on probability, then awards tickets" and "Uses actual game pricing for the selected target level."

**Gas Flags:**
- Manual modulo (`entropy - (entropyDiv100 * 100)`) is gas-equivalent to `entropy % 100` in Solidity 0.8+ but avoids an extra division in the compiler output. Minor optimization.
- `entropyDiv100` is reused for both the roll and the offset calculation, saving one division
- Single PRNG step per roll (efficient)

**Verdict:** CORRECT

---

## ETH Mutation Path Map

All paths through which ETH enters, moves between pools, or exits via the EndgameModule:

| # | Path | Source Pool | Destination | Trigger | Function Chain |
|---|------|-----------|-------------|---------|----------------|
| 1 | BAF ETH payout (large winner) | futurePrizePool | claimableWinnings[winner] + claimablePool | Level x0 transition | runRewardJackpots -> _runBafJackpot -> _addClaimableEth -> _creditClaimable |
| 2 | BAF ETH payout (small even-index) | futurePrizePool | claimableWinnings[winner] + claimablePool | Level x0 transition | runRewardJackpots -> _runBafJackpot -> _addClaimableEth -> _creditClaimable |
| 3 | BAF auto-rebuy conversion | futurePrizePool | futurePrizePool or nextPrizePool (recycled) | Level x0, auto-rebuy enabled | runRewardJackpots -> _runBafJackpot -> _addClaimableEth -> _calcAutoRebuy |
| 4 | BAF auto-rebuy take-profit | futurePrizePool | claimableWinnings[winner] + claimablePool | Level x0, auto-rebuy with takeProfit | runRewardJackpots -> _runBafJackpot -> _addClaimableEth |
| 5 | BAF lootbox small (<=0.5 ETH) | futurePrizePool | stays in futurePrizePool (tickets queued) | Level x0 transition | runRewardJackpots -> _runBafJackpot -> _awardJackpotTickets -> _jackpotTicketRoll -> _queueLootboxTickets |
| 6 | BAF lootbox medium (0.5-5 ETH) | futurePrizePool | stays in futurePrizePool (tickets queued, 2 rolls) | Level x0 transition | runRewardJackpots -> _runBafJackpot -> _awardJackpotTickets -> _jackpotTicketRoll x2 |
| 7 | BAF lootbox large (>5 ETH) | futurePrizePool | stays in futurePrizePool (deferred whale pass) | Level x0 transition | runRewardJackpots -> _runBafJackpot -> _awardJackpotTickets -> _queueWhalePassClaimCore |
| 8 | BAF lootbox large (remainder) | futurePrizePool | claimableWinnings[winner] + claimablePool | Level x0, remainder < HALF_WHALE_PASS_PRICE | runRewardJackpots -> _runBafJackpot -> _queueWhalePassClaimCore |
| 9 | BAF refund | futurePrizePool (deducted) | futurePrizePool (returned) | Level x0, undistributed BAF pool | runRewardJackpots (bafPoolWei - netSpend recycled) |
| 10 | Decimator x00 payout | futurePrizePool | claimablePool (deferred per-player claims) | Level x00 transition | runRewardJackpots -> runDecimatorJackpot (external self-call) |
| 11 | Decimator x5 payout | futurePrizePool | claimablePool (deferred per-player claims) | Level x5 transition (not x95) | runRewardJackpots -> runDecimatorJackpot (external self-call) |
| 12 | Whale pass claim | (no pool movement) | tickets queued across 100 levels | Player/contract calls claimWhalePass | claimWhalePass -> _queueTicketRange |
| 13 | Affiliate DGNRS reward | DGNRS Affiliate Pool | top affiliate address | Level transition | rewardTopAffiliate -> dgnrs.transferFromPool (DGNRS tokens, not ETH) |

**Notes:**
- Paths 5-8 (lootbox) do NOT move ETH between pools -- the ETH stays in futurePrizePool and tickets are queued as claims against future level entries. The `lootboxToFuture` return value from `_runBafJackpot` is added back to `futurePoolLocal` in `runRewardJackpots`.
- Path 12 (whale pass claim) has no ETH movement because the ETH was already accounted for at queue time (paths 7-8).
- Path 13 moves DGNRS tokens, not ETH. Included for completeness as it is a value transfer through this module.
- Decimator payouts (paths 10-11) go through an external self-call to `IDegenerusGame(address(this)).runDecimatorJackpot`. The Decimator module handles per-player claim snapshots; the EndgameModule only tracks aggregate pool movements.

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 1 | `rewardTopAffiliate` NatSpec mentions trophy minting that does not occur in this function; `_runBafJackpot` NatSpec mentions first-winner trophy that is not awarded here |
| GAS | 1 | Manual modulo in `_jackpotTicketRoll` is a minor stylistic choice, not a real optimization in 0.8+ |
| CORRECT | 7 | All 7 functions verified correct |

### Detailed Findings

**CONCERN-01: NatSpec mentions trophy minting/awarding not present in code**
- **Functions:** `rewardTopAffiliate`, `_runBafJackpot`
- **Description:** `rewardTopAffiliate` NatSpec says "Mint trophy and DGNRS reward" but only DGNRS reward is handled. `_runBafJackpot` NatSpec says "First winner (winners[0]) receives BAF trophy" but no trophy logic exists.
- **Impact:** Documentation-only. Trophy logic may exist in the Jackpots contract (`jackpots.runBafJackpot`) or in an event the Jackpots contract emits, but it is not in this module.
- **Recommendation:** Update NatSpec to remove trophy references from this module, or add cross-references to where trophy logic actually lives.

**GAS-01: Manual modulo calculation**
- **Function:** `_jackpotTicketRoll`
- **Description:** `entropy - (entropyDiv100 * 100)` is used instead of `entropy % 100`. Both compile to equivalent bytecode in Solidity 0.8+ with optimizer enabled.
- **Impact:** Negligible. The pattern does allow reuse of `entropyDiv100` for the offset calculation, which is a legitimate micro-optimization.
