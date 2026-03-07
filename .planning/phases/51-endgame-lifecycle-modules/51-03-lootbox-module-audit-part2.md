# DegenerusGameLootboxModule.sol -- Function-Level Audit (Part 2)

**Contract:** DegenerusGameLootboxModule
**File:** contracts/modules/DegenerusGameLootboxModule.sol
**Lines:** 1771
**Solidity:** 0.8.34
**Inherits:** DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

Part 2 covers remaining internal helpers: lootbox roll resolution, ticket count calculation, DGNRS reward calculation, DGNRS reward crediting, BURNIE-to-ETH conversion, whale pass activation, lazy pass pricing, decimator window check, deity daily seed generation, and deity boon-for-slot determination.

## Function Audit

### `_resolveLootboxRoll(address, uint256, uint256, uint24, uint256, uint24, uint48, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveLootboxRoll(address player, uint256 amount, uint256 lootboxAmount, uint24 targetLevel, uint256 targetPrice, uint24 currentLevel, uint48 day, uint256 entropy) private returns (uint256 burnieOut, uint32 ticketsOut, uint256 nextEntropy, bool applyPresaleMultiplier)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player receiving the reward; `amount` (uint256): ETH amount for this roll (may be half of total for split lootboxes); `lootboxAmount` (uint256): total lootbox amount for events; `targetLevel` (uint24): target level for tickets; `targetPrice` (uint256): price at target level; `currentLevel` (uint24): current game level; `day` (uint48): current day index; `entropy` (uint256): starting entropy |
| **Returns** | `burnieOut` (uint256): BURNIE tokens to award; `ticketsOut` (uint32): tickets to queue for future level; `nextEntropy` (uint256): updated entropy; `applyPresaleMultiplier` (bool): whether BURNIE should get presale bonus |

**State Reads:** None directly (reads happen via callees `_lootboxTicketCount`, `_lootboxDgnrsReward`, `_creditDgnrsReward`)

**State Writes:** Indirect via `_creditDgnrsReward` -> `dgnrs.transferFromPool()` (external call). Also calls `wwxrp.mintPrize()` for WWXRP path.

**Callers:** `_resolveLootboxCommon` (called once or twice depending on split threshold)

**Callees:**
- `EntropyLib.entropyStep(entropy)` -- advance entropy
- `_lootboxTicketCount(budgetWei, targetPrice, nextEntropy)` -- 55% ticket path
- `_lootboxDgnrsReward(amount, nextEntropy)` -- 10% DGNRS path
- `_creditDgnrsReward(player, dgnrsAmount)` -- credit DGNRS to player
- `wwxrp.mintPrize(player, wwxrpAmount)` -- 10% WWXRP path (external call)

**ETH Flow:** No direct ETH movement. Determines reward type distribution:
- 55% chance (roll < 11): Ticket path -- computes ticket count from budget at 161% of input amount. If targetLevel < currentLevel, converts tickets to BURNIE at `PRICE_COIN_UNIT / TICKET_SCALE` rate instead.
- 10% chance (roll 11-12): DGNRS token path -- transfers from DGNRS Lootbox pool to player.
- 10% chance (roll 13-14): WWXRP token path -- mints 1 WWXRP to player (external mint call).
- 25% chance (roll 15-19): Large BURNIE path with variance. 80% sub-chance: low path (58.1%-130.4%), 20% sub-chance: high path (307%-590%).

**Invariants:**
- Roll modulus is 20, partitions sum to 20 (11 + 2 + 2 + 5 = 20). Correct.
- For ticket path: if targetLevel < currentLevel, tickets are converted to BURNIE rather than queued -- avoids queuing tickets for already-passed levels.
- Large BURNIE path low: `5808 + roll * 477` for rolls 0-15 gives range 5808-12963 BPS (58%-130%). Correct.
- Large BURNIE path high: `30705 + (roll-16) * 9430` for rolls 16-19 gives range 30705-58995 BPS (307%-590%). Correct.
- `applyPresaleMultiplier` is only true for the large BURNIE path.

**NatSpec Accuracy:** NatSpec says "55% tickets, 10% DGNRS, 10% WWXRP, 25% BURNIE." Matches roll < 11 (55%), < 13 (10%), < 15 (10%), else (25%). Accurate.

**Gas Flags:** None. Clean branch structure with early return pattern via if/else.

**Verdict:** CORRECT

---

### `_lootboxTicketCount(uint256, uint256, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _lootboxTicketCount(uint256 budgetWei, uint256 priceWei, uint256 entropy) private pure returns (uint32 countScaled, uint256 nextEntropy)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `budgetWei` (uint256): ETH budget for tickets; `priceWei` (uint256): price per ticket at target level; `entropy` (uint256): starting entropy |
| **Returns** | `countScaled` (uint32): number of tickets x TICKET_SCALE (100); `nextEntropy` (uint256): updated entropy |

**State Reads:** None (pure function)

**State Writes:** None (pure function)

**Callers:** `_resolveLootboxRoll` (ticket path, 55% chance)

**Callees:** `EntropyLib.entropyStep(entropy)` -- advance entropy for variance roll

**ETH Flow:** None. Pure calculation function.

**Invariants:**
- Variance tiers: 1% chance at 4.6x (46000 BPS), 4% at 2.3x (23000 BPS), 20% at 1.1x (11000 BPS), 45% at 0.651x (6510 BPS), 30% at 0.45x (4500 BPS). Chance BPS sum: 100 + 400 + 2000 + 4500 = 7000. Remaining 3000/10000 = 30% gets tier 5. Correct.
- Overflow protection: `if (base > type(uint32).max) revert E()` -- prevents uint32 overflow on countScaled.
- Division order: `(budgetWei * ticketBps) / 10_000` then `(adjustedBudget * TICKET_SCALE) / priceWei` -- multiplication before division minimizes rounding loss.
- Zero-check: returns (0, entropy) if budgetWei or priceWei is zero.

**NatSpec Accuracy:** NatSpec says "1% get 4.6x, 4% get 2.3x, 20% get 1.1x, 45% get 0.651x, 30% get 0.45x." Matches the cumulative threshold logic. Accurate.

**Gas Flags:** None. Clean if-else ladder with constant comparisons.

**Verdict:** CORRECT

---

### `_lootboxDgnrsReward(uint256, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _lootboxDgnrsReward(uint256 amount, uint256 entropy) private view returns (uint256 dgnrsAmount)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `amount` (uint256): ETH amount for calculation; `entropy` (uint256): entropy for tier selection |
| **Returns** | `dgnrsAmount` (uint256): DGNRS tokens to award |

**State Reads:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Lootbox)` -- external view call to DGNRS contract to get lootbox pool balance

**State Writes:** None (view function)

**Callers:** `_resolveLootboxRoll` (DGNRS path, 10% chance)

**Callees:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Lootbox)` -- external view call

**ETH Flow:** None. Calculates the DGNRS reward amount; actual transfer happens in `_creditDgnrsReward`.

**Invariants:**
- Tier distribution: 79.5% small (10 PPM), 15% medium (390 PPM), 5% large (800 PPM), 0.5% mega (8000 PPM). Roll mod 1000: < 795 small, < 945 medium, < 995 large, >= 995 mega. Correct.
- Formula: `(poolBalance * ppm * amount) / (1_000_000 * 1 ether)`. This gives PPM of pool balance scaled by amount/1ETH. At 1 ETH input with 10 PPM: yields 0.001% of pool. At 8000 PPM with 1 ETH: yields 0.8% of pool. Correct.
- Cap: `if (dgnrsAmount > poolBalance) dgnrsAmount = poolBalance` -- prevents awarding more than pool contains.
- Zero check: returns 0 if poolBalance, ppm, or unit (always 1 ether) is zero.

**NatSpec Accuracy:** NatSpec says "79.5% small tier, 15% medium, 5% large, 0.5% mega." Matches threshold logic. Accurate.

**Gas Flags:** The `unit` local variable is always `1 ether` -- could be a constant. Minor informational; compiler likely optimizes this away.

**Verdict:** CORRECT

---

### `_creditDgnrsReward(address, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditDgnrsReward(address player, uint256 amount) private returns (uint256 paid)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to credit; `amount` (uint256): requested DGNRS amount to credit |
| **Returns** | `paid` (uint256): actual DGNRS amount paid from pool |

**State Reads:** None directly (external call reads/writes DGNRS contract state)

**State Writes:** None directly (external call modifies DGNRS contract state via `transferFromPool`)

**Callers:** `_resolveLootboxRoll` (DGNRS path, 10% chance)

**Callees:**
- `dgnrs.transferFromPool(IDegenerusStonk.Pool.Lootbox, player, amount)` -- external call to DGNRS contract, transfers tokens from Lootbox pool to player

**ETH Flow:** No ETH movement. Transfers DGNRS tokens (ERC20-like) from pool to player.

**Invariants:**
- Returns 0 for zero amount input -- no-op.
- Return value `paid` may be less than `amount` if pool has insufficient balance (per `transferFromPool` interface comment).

**NatSpec Accuracy:** NatSpec says "Credit DGNRS reward to player from pool only." Accurate. Correctly uses only the Lootbox pool.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_burnieToEthValue(uint256, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnieToEthValue(uint256 burnieAmount, uint256 priceWei) private pure returns (uint256 valueWei)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `burnieAmount` (uint256): BURNIE token amount (in 18-decimal wei); `priceWei` (uint256): current BURNIE price in wei per PRICE_COIN_UNIT |
| **Returns** | `valueWei` (uint256): equivalent ETH value in wei |

**State Reads:** None (pure function)

**State Writes:** None (pure function)

**Callers:** `_boonPoolStats` (called multiple times for coinflip max boon values and decimator max values)

**Callees:** None

**ETH Flow:** None. Pure conversion calculation.

**Invariants:**
- Formula: `(burnieAmount * priceWei) / PRICE_COIN_UNIT` where `PRICE_COIN_UNIT = 1000 ether`. Given that price is in wei per 1000 BURNIE tokens, this correctly converts BURNIE (18 decimals) to ETH value.
- Zero-check: returns 0 if either input is zero.

**NatSpec Accuracy:** NatSpec says "Convert BURNIE amount to ETH value using current price." The function takes `priceWei` as parameter rather than reading from storage, which is slightly more precise than the NatSpec implies. Minor discrepancy: NatSpec does not mention the parameter. Functionally correct.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_activateWhalePass(address)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _activateWhalePass(address player) private returns (uint24 ticketStartLevel)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player receiving the whale pass |
| **Returns** | `ticketStartLevel` (uint24): first level tickets are queued for |

**State Reads:**
- `level` -- current game level (via `level + 1` for passLevel)

**State Writes:**
- Via `_applyWhalePassStats(player, ticketStartLevel)` -- writes to `mintPacked_[player]` (whale pass stats bitmap)
- Via `_queueTickets(player, lvl, tickets)` x100 -- writes to `ticketsBuyersMap_`, `ticketsBuyerList_`, `ticketsBy_` for each of 100 levels

**Callers:** `_applyBoon` (whale pass boon path, type 28)

**Callees:**
- `_applyWhalePassStats(player, ticketStartLevel)` -- inherited from DegenerusGameStorage, applies whale pass metadata
- `_queueTickets(player, lvl, ticketsPerLevel)` -- inherited from DegenerusGameStorage, queues tickets at each level

**ETH Flow:** No direct ETH movement. Awards tickets (future value) across 100 levels.

**Invariants:**
- Start level calculation: if passLevel <= 4, starts at level 1; otherwise starts at next 50-level boundary + 1: `((passLevel + 1) / 50) * 50 + 1`. At passLevel=5: `(6/50)*50+1 = 1`. At passLevel=50: `(51/50)*50+1 = 51`. At passLevel=51: `(52/50)*50+1 = 51`. Correct snapping to 50-level boundaries.
- Bonus tickets: 40/level for levels within [passLevel, 10] (WHALE_PASS_BONUS_END_LEVEL), 2/level for the rest. The `isBonus` check requires `lvl >= passLevel AND lvl <= 10`. If ticketStartLevel > 10 or passLevel > 10, no bonus levels.
- Loop iterates exactly 100 times with unchecked increment for gas efficiency.
- Uses `_queueTickets` (unscaled) not `_queueTicketsScaled` -- passes whole ticket counts directly.

**NatSpec Accuracy:** NatSpec says "Activate a 100-level whale pass for a player. Applies the same mint/streak bonuses as a whale bundle purchase." The function does apply stats and tickets over 100 levels. The comment about "mint/streak bonuses" refers to `_applyWhalePassStats`. Accurate.

**Gas Flags:** 100-iteration loop with external storage writes per iteration. This is inherently gas-heavy (~100 SSTORE operations) but necessary for the whale pass design. No optimization possible without architectural change.

**Verdict:** CORRECT
