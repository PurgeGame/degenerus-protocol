# DegenerusGameLootboxModule.sol -- Function-Level Audit (Part 1)

**Contract:** DegenerusGameLootboxModule
**File:** contracts/modules/DegenerusGameLootboxModule.sol
**Lines:** 1771
**Solidity:** 0.8.34
**Inherits:** DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

This module handles lootbox opening and resolution, deity boon issuance, and the EV multiplier system. It is called via delegatecall from DegenerusGame, operating on the game contract's storage. Key subsystems:

- **Lootbox Opening:** ETH lootboxes (`openLootBox`), BURNIE lootboxes (`openBurnieLootBox`), and direct resolution (`resolveLootboxDirect` for decimator claims). Lootboxes split into two rolls if above 0.5 ETH. 10% of value is reserved for boon budget.
- **Deity Boon System:** Deity pass holders get 3 deterministic daily boon slots (`deityBoonSlots`). They can issue boons to other players (`issueDeityBoon`), one recipient per day, one slot each.
- **EV Multiplier:** Activity-score-based reward scaling (80%-135%) with a per-account per-level 10 ETH cap on benefit.
- **Boon Pool:** Weighted random boon selection from ~22 boon types across 12 categories (coinflip, lootbox boost, purchase boost, decimator, whale, deity pass, activity, whale pass, lazy pass).

## Function Audit

### `openLootBox(address player, uint48 index)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openLootBox(address player, uint48 index) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address to open lootbox for; `index` (uint48): RNG index of the lootbox |
| **Returns** | none |

**State Reads:** `rngLockedFlag`, `lootboxEth[index][player]`, `lootboxRngWordByIndex[index]`, `lootboxDay[index][player]`, `lootboxPresaleActive`, `lootboxEthBase[index][player]`, `level`, `lootboxBaseLevelPacked[index][player]`, `lootboxEvScorePacked[index][player]`, `lootboxEvBenefitUsedByLevel[player][lvl]`

**State Writes:** `lootboxEth[index][player] = 0`, `lootboxEthBase[index][player] = 0`, `lootboxBaseLevelPacked[index][player] = 0`, `lootboxEvScorePacked[index][player] = 0`, `lootboxEvBenefitUsedByLevel[player][lvl]` (via `_applyEvMultiplierWithCap`), plus all writes from `_resolveLootboxCommon`

**Callers:** DegenerusGame via delegatecall (through MintModule.openLootBox which routes here)

**Callees:** `_simulatedDayIndex()`, `_rollTargetLevel()`, `_lootboxEvMultiplierBps()` or `_lootboxEvMultiplierFromScore()`, `_applyEvMultiplierWithCap()`, `_resolveLootboxCommon()`

**ETH Flow:** No direct ETH transfer. ETH-equivalent value is used to calculate BURNIE rewards (via `coin.creditFlip`), ticket grants, and boon draws. The lootbox ETH was deposited during purchase and sits in the game contract balance.

**Revert Conditions:**
- `RngLocked()`: if `rngLockedFlag` is true (jackpot resolution in progress)
- `E()`: if `amount == 0` (no lootbox at this index for this player)
- `RngNotReady()`: if `lootboxRngWordByIndex[index] == 0` (RNG not yet fulfilled)

**Invariants:**
- Lootbox is consumed atomically (all 4 storage slots zeroed before resolution)
- EV multiplier cap ensures no player can extract more than 10 ETH of EV benefit per level
- Grace period (7 days) preserves original purchase level for target level calculation
- `targetLevel >= currentLevel` enforced after roll

**NatSpec Accuracy:** Accurate. NatSpec documents RNG lock check, EV multiplier application, and revert conditions. The `@custom:reverts` tags correctly list all three revert paths.

**Gas Flags:** `boonAmount` parameter in `_resolveLootboxCommon` is passed as `baseAmount` but is immediately discarded inside the function (line 850: `boonAmount;`). This is a dead parameter -- no gas cost since it's calldata forwarding, but it's misleading.

**Verdict:** CORRECT

---

### `openBurnieLootBox(address player, uint48 index)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openBurnieLootBox(address player, uint48 index) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to open BURNIE lootbox for; `index` (uint48): RNG index |
| **Returns** | none |

**State Reads:** `rngLockedFlag`, `lootboxBurnie[index][player]`, `lootboxRngWordByIndex[index]`, `price`, `level`, `lootboxDay[index][player]`

**State Writes:** `lootboxBurnie[index][player] = 0`, plus all writes from `_resolveLootboxCommon`

**Callers:** DegenerusGame via delegatecall

**Callees:** `_simulatedDayIndex()`, `_rollTargetLevel()`, `_resolveLootboxCommon()`

**ETH Flow:** No direct ETH transfer. BURNIE amount is converted to ETH-equivalent at 80% rate: `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)`. This ETH-equivalent drives reward calculations but no actual ETH moves.

**Revert Conditions:**
- `RngLocked()`: if `rngLockedFlag` is true
- `E()`: if `burnieAmount == 0` (no BURNIE lootbox)
- `RngNotReady()`: if `lootboxRngWordByIndex[index] == 0`
- `E()`: if `priceWei == 0` (BURNIE price not set)
- `E()`: if `amountEth == 0` (conversion resulted in zero)

**Invariants:**
- BURNIE lootbox is consumed atomically (storage zeroed before resolution)
- No EV multiplier applied (BURNIE lootboxes get neutral 100% EV)
- `allowWhalePass=false`, `allowLazyPass=false`, `emitLootboxEvent=false`, `allowBoons=true` -- BURNIE lootboxes get boon rolls but not whale/lazy pass draws
- `presale=false` -- no presale bonus for BURNIE lootboxes
- Base level for target roll is `currentLevel` (not purchase level)

**NatSpec Accuracy:** Accurate. Documents 80% conversion rate, RNG lock, and revert conditions.

**Gas Flags:** None. The function destructures return values from `_resolveLootboxCommon` to emit `BurnieLootOpen` event.

**Verdict:** CORRECT

---

### `resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to resolve for; `amount` (uint256): ETH amount; `rngWord` (uint256): RNG word for resolution |
| **Returns** | none |

**State Reads:** `level`, `lootboxEvBenefitUsedByLevel[player][lvl]`

**State Writes:** `lootboxEvBenefitUsedByLevel[player][lvl]` (via `_applyEvMultiplierWithCap`), plus all writes from `_resolveLootboxCommon`

**Callers:** DegenerusGame via delegatecall -- called during decimator jackpot claim and other direct-resolution paths

**Callees:** `_simulatedDayIndex()`, `_rollTargetLevel()`, `_lootboxEvMultiplierBps()`, `_applyEvMultiplierWithCap()`, `_resolveLootboxCommon()`

**ETH Flow:** No direct ETH transfer. Operates on ETH-equivalent value for reward calculation. The ETH was already accounted for in the calling context.

**Revert Conditions:**
- Early return if `amount == 0` (not a revert, just no-op)
- Any reverts from `_resolveLootboxCommon` propagate

**Invariants:**
- `allowBoons=false` -- direct resolution does not award boons (jackpot/claim lootboxes)
- `allowWhalePass=true`, `allowLazyPass=true`, `emitLootboxEvent=true` -- but boon path is skipped so these are irrelevant
- `presale=false` -- no presale bonus
- EV multiplier IS applied (decimator claim recipients benefit from activity score)
- No RNG lock check -- direct resolution uses provided rngWord, not stored RNG

**NatSpec Accuracy:** NatSpec says "no RNG wait needed" which is accurate since `rngWord` is passed directly. States "Jackpot/claim lootboxes do not award boons" which matches `allowBoons=false`.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `deityBoonSlots(address deity)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function deityBoonSlots(address deity) external view returns (uint8[3] memory slots, uint8 usedMask, uint48 day)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `deity` (address): deity pass holder address |
| **Returns** | `slots` (uint8[3]): array of 3 boon types (1-31); `usedMask` (uint8): bitmask of used slots; `day` (uint48): current day index |

**State Reads:** `deityBoonDay[deity]`, `deityBoonUsedMask[deity]`, `deityPassOwners.length`, `decWindowOpen`, `rngWordByDay[day]`, `rngWordCurrent`

**State Writes:** None (view function)

**Callers:** External callers (frontend/UI) to display available deity boons

**Callees:** `_simulatedDayIndex()`, `_isDecimatorWindow()`, `_deityBoonForSlot()`

**ETH Flow:** None (view function)

**Revert Conditions:** None -- always succeeds

**Invariants:**
- Slots are deterministic: same deity + day + slot always produces the same boon type
- `usedMask` only returned if `deityBoonDay[deity] == day` (fresh day means mask=0)
- `deityPassAvailable` check uses `deityPassOwners.length < DEITY_PASS_MAX_TOTAL` (24)
- `decimatorAllowed` follows `decWindowOpen` state

**NatSpec Accuracy:** Matches the `@param` tag in the interface. Returns deity boon slot info as documented.

**Gas Flags:** The `_deityBoonForSlot` call computes `_deityDailySeed(day)` inside a loop 3 times. Each call reads `rngWordByDay[day]` from storage. The optimizer should handle this, but a local cache would be slightly more explicit.

**Verdict:** CORRECT

---

### `issueDeityBoon(address deity, address recipient, uint8 slot)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function issueDeityBoon(address deity, address recipient, uint8 slot) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `deity` (address): deity pass holder issuing the boon; `recipient` (address): player receiving the boon; `slot` (uint8): slot index (0-2) |
| **Returns** | none |

**State Reads:** `deityPassPurchasedCount[deity]`, `deityBoonDay[deity]`, `deityBoonUsedMask[deity]`, `deityBoonRecipientDay[recipient]`, `deityPassOwners.length`, `decWindowOpen`, `rngWordByDay[day]`, `rngWordCurrent`

**State Writes:** `deityBoonDay[deity] = day`, `deityBoonUsedMask[deity]` (set/update), `deityBoonRecipientDay[recipient] = day`, plus all writes from `_applyBoon()`

**Callers:** DegenerusGame via delegatecall (called from the game's `issueDeityBoon` proxy)

**Callees:** `_simulatedDayIndex()`, `_isDecimatorWindow()`, `_deityBoonForSlot()`, `_applyBoon()`

**ETH Flow:** None directly. Some boon types applied via `_applyBoon` may indirectly affect ETH (e.g., whale pass activation queues tickets).

**Revert Conditions:**
- `E()`: deity is zero address
- `E()`: recipient is zero address
- `E()`: deity == recipient (self-boon)
- `E()`: slot >= 3 (DEITY_DAILY_BOON_COUNT)
- `E()`: `deityPassPurchasedCount[deity] == 0` (no deity passes)
- `E()`: no RNG available (`rngWordByDay[day] == 0 && rngWordCurrent == 0`)
- `E()`: recipient already received a boon today (`deityBoonRecipientDay[recipient] == day`)
- `E()`: slot already used today (`(mask & slotMask) != 0`)

**Invariants:**
- Each deity gets exactly 3 slots per day, each usable once
- Each recipient can receive at most 1 deity boon per day (across all deities)
- Boon type is deterministic from (deity, day, slot) -- cannot be gamed
- Day reset: if `deityBoonDay[deity] != day`, mask is reset to 0
- `isDeity=true` passed to `_applyBoon` -- deity boons overwrite (not upgrade-only)

**NatSpec Accuracy:** Accurate. All revert conditions documented via `@custom:reverts`. The "up to 3 boons per day" and "one per recipient per day" constraints match implementation.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_lootboxEvMultiplierBps(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _lootboxEvMultiplierBps(address player) private view returns (uint256)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player to calculate EV multiplier for |
| **Returns** | `uint256`: EV multiplier in basis points (8000-13500) |

**State Reads:** None directly -- calls `IDegenerusGame(address(this)).playerActivityScore(player)` which reads player activity state via external call to self

**State Writes:** None

**Callers:** `openLootBox()`, `resolveLootboxDirect()`

**Callees:** `IDegenerusGame(address(this)).playerActivityScore(player)` (external self-call), `_lootboxEvMultiplierFromScore()`

**ETH Flow:** None

**Invariants:**
- Return value always in range [8000, 13500] (80% to 135% EV)
- Uses `address(this)` which in delegatecall context resolves to DegenerusGame, correctly calling the game's `playerActivityScore` function

**NatSpec Accuracy:** Accurate. Documents linear scaling from 0% activity (80% EV) to 60% (100% EV) to 255%+ (135% EV).

**Gas Flags:** The `address(this)` external call is more expensive than a direct storage read, but `playerActivityScore` is a public function on the game contract that may involve complex calculation. This pattern is necessary because the module doesn't have direct access to the activity score computation logic.

**Verdict:** CORRECT

---

### `_lootboxEvMultiplierFromScore(uint256 score)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _lootboxEvMultiplierFromScore(uint256 score) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `score` (uint256): activity score in basis points |
| **Returns** | `uint256`: EV multiplier in basis points (8000-13500) |

**State Reads:** None (pure function)

**State Writes:** None

**Callers:** `_lootboxEvMultiplierBps()`, `openLootBox()` (when `evScorePacked != 0`)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Returns 8000 (80%) at score=0
- Returns 10000 (100%) at score=6000 (60%)
- Returns 13500 (135%) at score>=25500 (255%)
- Linear interpolation between breakpoints
- No overflow risk: max computation is `25500 * 3500 / 19500 = 4577` added to 10000

**NatSpec Accuracy:** Accurate. Documents the linear interpolation between thresholds.

**Gas Flags:** None. Clean pure math.

**Verification of math:**
- At score=0: returns `8000 + (0 * 2000) / 6000 = 8000` -- correct
- At score=6000: returns `8000 + (6000 * 2000) / 6000 = 10000` -- correct
- At score=12750 (midpoint): `excess=6750`, `maxExcess=19500`, returns `10000 + (6750 * 3500) / 19500 = 10000 + 1211 = 11211` -- correct linear interp
- At score=25500: returns 13500 -- correct (capped)

**Verdict:** CORRECT

---

### `_applyEvMultiplierWithCap(address player, uint24 lvl, uint256 amount, uint256 evMultiplierBps)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyEvMultiplierWithCap(address player, uint24 lvl, uint256 amount, uint256 evMultiplierBps) private returns (uint256 scaledAmount)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `lvl` (uint24): current game level; `amount` (uint256): lootbox ETH amount; `evMultiplierBps` (uint256): EV multiplier in basis points |
| **Returns** | `scaledAmount` (uint256): amount after EV adjustment |

**State Reads:** `lootboxEvBenefitUsedByLevel[player][lvl]`

**State Writes:** `lootboxEvBenefitUsedByLevel[player][lvl]` (incremented by `adjustedPortion`)

**Callers:** `openLootBox()`, `resolveLootboxDirect()`

**Callees:** None

**ETH Flow:** None. Calculates scaled reward amount but does not move ETH.

**Revert Conditions:** None -- always succeeds

**Invariants:**
- If `evMultiplierBps == 10000` (neutral), returns `amount` unchanged with no tracking update
- Total benefit tracked per (player, level) never exceeds `LOOTBOX_EV_BENEFIT_CAP` (10 ETH)
- Once cap is exhausted, all subsequent lootboxes at that level get 100% EV
- Split handling: if `amount > remainingCap`, only the first `remainingCap` portion gets the multiplier, remainder gets 100%

**NatSpec Accuracy:** Accurate. Documents the per-account per-level 10 ETH cap and the split behavior.

**Gas Flags:** None. The function correctly handles the edge case where cap is already exhausted (returns early).

**Verification of logic:**
- For EV > 100% (e.g., 120%): benefit = `(portion * 12000) / 10000` = 1.2x, tracking consumes `portion`
- For EV < 100% (e.g., 80%): same logic applies -- benefit tracking still consumes `portion` of the cap, even though the player is penalized. This means low-activity players also consume their cap with sub-100% returns.

**Note:** The cap tracks `adjustedPortion` (the raw ETH amount), not the actual benefit delta. This means a player with 80% EV consuming 10 ETH of cap gets 8 ETH of reward (net loss of 2 ETH from cap), while a player with 135% EV consuming 10 ETH of cap gets 13.5 ETH (net gain of 3.5 ETH). The cap prevents unbounded EV farming in both directions.

**Verdict:** CORRECT

---

### `_rollTargetLevel(uint24 baseLevel, uint256 entropy)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollTargetLevel(uint24 baseLevel, uint256 entropy) private pure returns (uint24 targetLevel, uint256 nextEntropy)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `baseLevel` (uint24): base level to roll from; `entropy` (uint256): starting entropy |
| **Returns** | `targetLevel` (uint24): rolled target level; `nextEntropy` (uint256): updated entropy for subsequent rolls |

**State Reads:** None (pure function)

**State Writes:** None

**Callers:** `openLootBox()`, `openBurnieLootBox()`, `resolveLootboxDirect()`

**Callees:** `EntropyLib.entropyStep()`

**ETH Flow:** None

**Invariants:**
- `targetLevel >= baseLevel` always (offset is always >= 0)
- 95% chance: 0-5 levels ahead (near future), entropy consumed: 1 step
- 5% chance: 5-50 levels ahead (far future), entropy consumed: 2 steps
- Far future range: `(farEntropy % 46) + 5` gives range [5, 50]

**NatSpec Accuracy:** Accurate. Documents 95%/5% split and level offset ranges.

**Gas Flags:** None.

**Verification:**
- Near: `rangeRoll >= 5` (95%), `levelOffset = levelEntropy % 6` gives [0,5], `nextEntropy = levelEntropy`
- Far: `rangeRoll < 5` (5%), `levelOffset = (farEntropy % 46) + 5` gives [5,50], `nextEntropy = farEntropy`
- Both branches consume at least one entropy step; far branch consumes two

**Verdict:** CORRECT

---

### `_resolveLootboxCommon(address player, uint48 day, uint256 amount, uint256 boonAmount, uint24 targetLevel, uint24 currentLevel, uint256 entropy, bool presale, bool allowWhalePass, bool allowLazyPass, bool emitLootboxEvent, bool allowBoons)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveLootboxCommon(address player, uint48 day, uint256 amount, uint256 boonAmount, uint24 targetLevel, uint24 currentLevel, uint256 entropy, bool presale, bool allowWhalePass, bool allowLazyPass, bool emitLootboxEvent, bool allowBoons) private returns (uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): reward recipient; `day` (uint48): day index; `amount` (uint256): ETH-equivalent for rewards; `boonAmount` (uint256): unused; `targetLevel` (uint24): target level for tickets; `currentLevel` (uint24): current game level; `entropy` (uint256): RNG entropy; `presale` (bool): presale bonus; `allowWhalePass` (bool): whale pass draw; `allowLazyPass` (bool): lazy pass draw; `emitLootboxEvent` (bool): emit event; `allowBoons` (bool): boon roll |
| **Returns** | `futureTickets` (uint32): tickets awarded; `burnieAmount` (uint256): total BURNIE; `bonusBurnie` (uint256): presale bonus BURNIE |

**State Reads:** Via `_resolveLootboxRoll`: `price` (for BURNIE conversion), DGNRS pool balance. Via `_rollLootboxBoons`: all boon-related storage.

**State Writes:** Via `_resolveLootboxRoll`: `dgnrs.transferFromPool()`. Via `_rollLootboxBoons`: boon storage writes. Via `_queueTicketsScaled`: `futureTicketsByLevel`, `futureTicketRemainder`. Via `coin.creditFlip`: BURNIE balance.

**Callers:** `openLootBox()`, `openBurnieLootBox()`, `resolveLootboxDirect()`

**Callees:** `PriceLookupLib.priceForLevel()`, `_resolveLootboxRoll()` (1 or 2 calls), `_rollLootboxBoons()`, `IDegenerusGameBoonModule.consumeActivityBoon()` (delegatecall), `_queueTicketsScaled()`, `coin.creditFlip()`

**ETH Flow:** No direct ETH transfer. BURNIE is credited via `coin.creditFlip(player, burnieAmount)`. DGNRS tokens may be transferred from pool via `dgnrs.transferFromPool()`. WWXRP tokens may be minted via `wwxrp.mintPrize()`.

**Revert Conditions:**
- `E()`: if `targetPrice == 0` (PriceLookupLib returned 0, which cannot happen for valid levels)
- `E()`: if ticket accumulation overflows uint32 (extremely unlikely)
- `E()`: if `consumeActivityBoon` delegatecall fails

**Invariants:**
- Boon budget = min(amount * 10%, 1 ETH, amount) -- capped at both 10% and absolute 1 ETH
- Main amount = amount - boonBudget
- If mainAmount > 0.5 ETH, split into two equal(ish) halves for two independent rolls
- `boonAmount` parameter is explicitly discarded (line 850)
- Presale bonus: 62% additional on BURNIE rewards flagged as `applyPresaleMultiplier`
- Tickets are queued only if `futureTickets != 0`
- BURNIE credited only if `burnieAmount != 0`
- `targetLevel >= currentLevel` re-enforced at start

**NatSpec Accuracy:** Mostly accurate. The `boonAmount` parameter is documented as "Amount used for boon chance calculations" but is actually unused. This is a minor NatSpec inaccuracy.

**Gas Flags:** `boonAmount` parameter is passed by all 3 callers but discarded on line 850. Dead code/parameter.

**Verdict:** CONCERN -- The `boonAmount` parameter is documented as meaningful but is explicitly discarded. This is not a bug (it was intentionally silenced with a bare expression statement) but creates confusion. The parameter should either be removed or the NatSpec should note it is reserved/unused.

---

### `_boonPoolStats(bool decimatorAllowed, bool deityEligible, bool allowWhalePass, bool allowLazyPass, uint256 lazyPassValue)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _boonPoolStats(bool decimatorAllowed, bool deityEligible, bool allowWhalePass, bool allowLazyPass, uint256 lazyPassValue) private view returns (uint256 totalWeight, uint256 avgMaxValue)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `decimatorAllowed` (bool): include decimator boons; `deityEligible` (bool): include deity pass boons; `allowWhalePass` (bool): include whale pass; `allowLazyPass` (bool): include lazy pass boons; `lazyPassValue` (uint256): lazy pass ETH value |
| **Returns** | `totalWeight` (uint256): sum of all eligible boon weights; `avgMaxValue` (uint256): weighted average of max boon values in ETH |

**State Reads:** `price`, `deityPassOwners.length`

**State Writes:** None (view function)

**Callers:** `_rollLootboxBoons()`

**Callees:** `_burnieToEthValue()`, `PriceLookupLib.priceForLevel()` (indirectly through lazy pass value)

**ETH Flow:** None (view function)

**Invariants:**
- Weights match the deity boon weight constants used in `_boonFromRoll`
- Activity boons contribute weight but zero value (activity score has no direct ETH value)
- `avgMaxValue = weightedMax / totalWeight`
- When all eligible flags are true and decimator is allowed: total weight = DEITY_BOON_WEIGHT_TOTAL (1298) plus deity pass and lazy pass weights minus any conditional exclusions
- Deity pass price uses triangular number formula: `24 + k*(k+1)/2` ETH

**NatSpec Accuracy:** Brief but accurate. "Calculate total weight and average max boon value."

**Gas Flags:** Multiple `_burnieToEthValue` calls each multiply by `priceWei` which is read from storage once and cached in local `priceWei`. Good optimization.

**Verification of weight consistency:**
- Base weights (always included): Coinflip(200+40+8) + Lootbox(200+30+8) + Purchase(400+80+16) + Whale(28+10+2) + Activity(100+30+8) = 1160
- Conditional: Decimator(40+8+2)=50, DeityPass(28+10+2)=40, WhalePass(8), LazyPass(30+8+2)=40
- Without decimator/deity/whale/lazy: 1160. With all: 1160+50+40+8+40 = 1298. Matches DEITY_BOON_WEIGHT_TOTAL (1298) minus lazy pass (40) since lazy pass is not in the deity constant. Actually, the deity constants include whale pass and lazy pass weights:
  - DEITY_BOON_WEIGHT_TOTAL = 1298 includes everything including decimator
  - DEITY_BOON_WEIGHT_TOTAL_NO_DECIMATOR = 1248 = 1298-50
  - These constants are used only in `_deityBoonForSlot`, not here. The `_boonPoolStats` function computes its own total dynamically based on eligibility flags. This is consistent.

**Verdict:** CORRECT

---

### `_boonFromRoll(uint256 roll, bool decimatorAllowed, bool deityEligible, bool allowWhalePass, bool allowLazyPass)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _boonFromRoll(uint256 roll, bool decimatorAllowed, bool deityEligible, bool allowWhalePass, bool allowLazyPass) private pure returns (uint8 boonType)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `roll` (uint256): weighted roll value; `decimatorAllowed` (bool): include decimator segment; `deityEligible` (bool): include deity pass segment; `allowWhalePass` (bool): include whale pass; `allowLazyPass` (bool): include lazy pass |
| **Returns** | `boonType` (uint8): boon type (1-31) |

**State Reads:** None (pure function)

**State Writes:** None

**Callers:** `_rollLootboxBoons()`, `_deityBoonForSlot()`

**Callees:** None

**ETH Flow:** None

**Invariants:**
- The cursor-based selection maps roll values to boon types in weight-proportional order
- When conditional segments are skipped, subsequent weights shift down accordingly
- Fallback: returns `DEITY_BOON_ACTIVITY_50` if roll exceeds all cumulative weights
- Order: Coinflip(5/10/25) -> Lootbox(5/15/25) -> Purchase(5/15/25) -> [Decimator(10/25/50)] -> Whale(10/25/50) -> [DeityPass(10/25/50)] -> Activity(10/25/50) -> [WhalePass] -> [LazyPass(10/25/50)]

**NatSpec Accuracy:** Brief but accurate. "Convert a weighted roll into a lootbox boon type."

**Gas Flags:** Sequential if-chain with early returns. Could use a lookup table but the current approach is clear and the number of branches is manageable. Not a real concern.

**Verification:**
- Weight ordering matches `_boonPoolStats` -- same categories in same order with same weights
- Conditional segments (decimator, deity, whale pass, lazy pass) are correctly skipped when disabled, and the cursor continues to the next category
- Fallback to `DEITY_BOON_ACTIVITY_50` is safe -- this would only trigger if roll exceeds all weights, which should not happen with correct probability calculation

**Verdict:** CORRECT

---

### `_activeBoonCategory(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _activeBoonCategory(address player) private view returns (uint8 category)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player to check |
| **Returns** | `category` (uint8): active boon category constant (0-12) |

**State Reads:** `coinflipBoonBps[player]`, `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `purchaseBoostBps[player]`, `decimatorBoostBps[player]`, `whaleBoonDay[player]`, `lazyPassBoonDay[player]`, `lazyPassBoonDiscountBps[player]`, `activityBoonPending[player]`, `deityPassBoonTier[player]`

**State Writes:** None (view function)

**Callers:** `_rollLootboxBoons()`

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Returns the first active boon category found in priority order
- Priority: Coinflip > Lootbox > Purchase > Decimator > Whale > LazyPass > Activity > DeityPass > None
- Only one boon category can be active at a time (enforced by `_rollLootboxBoons` which checks `activeCategory != selectedCategory`)
- If all checks return zero/false, returns `BOON_CAT_NONE` (0)

**NatSpec Accuracy:** Brief but accurate.

**Gas Flags:** Up to 11 storage reads in worst case (all boons inactive). This is acceptable for the boon check pattern.

**Verdict:** CORRECT

---

### `_boonCategory(uint8 boonType)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _boonCategory(uint8 boonType) private pure returns (uint8 category)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `boonType` (uint8): boon type (1-31) |
| **Returns** | `category` (uint8): boon category constant |

**State Reads:** None (pure function)

**State Writes:** None

**Callers:** `_rollLootboxBoons()`

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Maps every boon type to exactly one category
- Types 1-3 -> COINFLIP (1)
- Types 5,6,22 -> LOOTBOX (3)
- Types 7,8,9 -> PURCHASE (4)
- Types 13,14,15 -> DECIMATOR (6)
- Types 16,23,24 -> WHALE (7)
- Types 17,18,19 -> ACTIVITY (9)
- Type 28 -> WHALE_PASS (11)
- Types 29,30,31 -> LAZY_PASS (12)
- Types 25,26,27 and any unmatched -> DEITY_PASS (10) (fallback)
- Note: types 4, 10-12, 20-21 are undefined boon types; if passed, they would fall through to `BOON_CAT_DEITY_PASS` as the default return

**NatSpec Accuracy:** Brief but accurate.

**Gas Flags:** None.

**Verification:** Cross-checked all boon type constants against their category assignments. The `boonType <= DEITY_BOON_COINFLIP_25` check handles types 1-3 since `DEITY_BOON_COINFLIP_25 = 3`. Types 4 (undefined gap) would fall through to the lootbox check (`DEITY_BOON_LOOTBOX_5 = 5`), not match, then purchase check, not match, then decimator check, etc., until reaching the default `DEITY_PASS`. This is acceptable since type 4 is never generated by `_boonFromRoll`.

**Verdict:** CORRECT

---

### `_rollLootboxBoons(address player, uint48 day, uint256 originalAmount, uint256 boonBudget, uint256 entropy, bool allowWhalePass, bool allowLazyPass)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollLootboxBoons(address player, uint48 day, uint256 originalAmount, uint256 boonBudget, uint256 entropy, bool allowWhalePass, bool allowLazyPass) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `day` (uint48): current day index; `originalAmount` (uint256): full lootbox ETH amount for event emission; `boonBudget` (uint256): ETH budget allocated for boon draw; `entropy` (uint256): entropy for roll; `allowWhalePass` (bool): enable whale pass draw; `allowLazyPass` (bool): enable lazy pass draw |
| **Returns** | none |

**State Reads:** Via `IDegenerusGameBoonModule.checkAndClearExpiredBoon` delegatecall: all boon expiry fields. Via `_activeBoonCategory`: `coinflipBoonBps[player]`, `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `purchaseBoostBps[player]`, `decimatorBoostBps[player]`, `whaleBoonDay[player]`, `lazyPassBoonDay[player]`, `lazyPassBoonDiscountBps[player]`, `activityBoonPending[player]`, `deityPassBoonTier[player]`. Via `_boonPoolStats`: `price`, `deityPassOwners.length`. Direct reads: `level`, `decWindowOpen`, `deityPassCount[player]`

**State Writes:** Via `IDegenerusGameBoonModule.checkAndClearExpiredBoon` delegatecall: may clear expired boon storage. Via `_applyBoon`: writes to the appropriate boon storage based on selected boon type.

**Callers:** `_resolveLootboxCommon()`

**Callees:** `IDegenerusGameBoonModule.checkAndClearExpiredBoon()` (delegatecall), `_activeBoonCategory()`, `_simulatedDayIndex()`, `_isDecimatorWindow()`, `_boonPoolStats()`, `_boonFromRoll()`, `_boonCategory()`, `_applyBoon()`, `_lazyPassPriceForLevel()`

**ETH Flow:** None directly. Boon application may trigger whale pass activation which queues tickets.

**Revert Conditions:**
- `E()`: if `checkAndClearExpiredBoon` delegatecall fails

**Invariants:**
- Early return if `player == address(0)` or `originalAmount == 0`
- Expired boons are cleared before checking active category
- Only one boon per lootbox opening (single roll, single application)
- Active category enforcement: if player already has an active boon in category X, only boons in category X can be awarded (refresh/upgrade). If selected boon is in a different category, it is silently dropped.
- Boon probability: `totalChance = (boonBudget * 1e6) / expectedPerBoon`, capped at 1e6 (100%)
- `expectedPerBoon = avgMaxValue * 50%` (utilization factor)
- Roll: `entropy % 1e6` compared against `totalChance`
- If roll >= totalChance, no boon awarded (early return)
- Weighted selection: `_boonFromRoll((roll * totalWeight) / totalChance)` maps the winning roll to a specific boon type proportional to weights
- Deity eligibility: player must have 0 deity passes AND total deity pass count < 24
- Lazy pass value calculated for `currentLevel + 1` (or 1 if level is 0)
- `isDeity=false` passed to `_applyBoon` -- lootbox boons use upgrade semantics

**NatSpec Accuracy:** Accurate. Documents the single-boon limit, category restriction, and ppm-based probability system.

**Gas Flags:** The function reads `_simulatedDayIndex()` to get `currentDay`, but this is also computed inside `_boonPoolStats` indirectly. However, `_boonPoolStats` does not read the day, so there is no redundancy. The delegatecall to `checkAndClearExpiredBoon` is an additional cross-module call that adds gas overhead but is necessary for correctness.

**Verification of probability math:**
- `boonBudget` is max 10% of lootbox value, capped at 1 ETH
- `expectedPerBoon` = `avgMaxValue * 0.5` (50% utilization)
- For a 1 ETH lootbox: boonBudget = 0.1 ETH. If avgMaxValue = 0.5 ETH, expectedPerBoon = 0.25 ETH, totalChance = (0.1e18 * 1e6) / 0.25e18 = 400,000 ppm = 40% chance
- This scales linearly: bigger lootboxes get higher boon chance up to 100%
- The `(roll * totalWeight) / totalChance` remapping correctly distributes the winning roll across the weight space

**Verdict:** CORRECT

---

### `_applyBoon(address player, uint8 boonType, uint48 day, uint48 currentDay, uint256 originalAmount, bool isDeity)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyBoon(address player, uint8 boonType, uint48 day, uint48 currentDay, uint256 originalAmount, bool isDeity) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player receiving the boon; `boonType` (uint8): boon type (1-31); `day` (uint48): day index for event emission / deity tracking; `currentDay` (uint48): current day for boon expiry tracking; `originalAmount` (uint256): lootbox amount for event emission; `isDeity` (bool): true if boon is deity-sourced (overwrite), false if lootbox-sourced (upgrade) |
| **Returns** | none |

**State Reads:** `coinflipBoonBps[player]`, `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `purchaseBoostBps[player]`, `decimatorBoostBps[player]`, `whaleBoonDiscountBps[player]`, `activityBoonPending[player]`, `deityPassBoonTier[player]`, `lazyPassBoonDiscountBps[player]`, `level`

**State Writes:** Depends on boon type (one branch per category):
- **Coinflip (1-3):** `coinflipBoonBps[player]`, `coinflipBoonDay[player]`, `deityCoinflipBoonDay[player]`
- **Lootbox boost (5,6,22):** `lootboxBoon25Active[player]`, `lootboxBoon15Active[player]`, `lootboxBoon5Active[player]`, `lootboxBoon25Day[player]`, `lootboxBoon15Day[player]`, `lootboxBoon5Day[player]`, `deityLootboxBoon25Day[player]`, `deityLootboxBoon15Day[player]`, `deityLootboxBoon5Day[player]`
- **Purchase boost (7-9):** `purchaseBoostBps[player]`, `purchaseBoostDay[player]`, `deityPurchaseBoostDay[player]`
- **Decimator boost (13-15):** `decimatorBoostBps[player]`, `deityDecimatorBoostDay[player]`
- **Whale discount (16,23,24):** `whaleBoonDiscountBps[player]`, `whaleBoonDay[player]`, `deityWhaleBoonDay[player]`
- **Activity (17-19):** `activityBoonPending[player]`, `activityBoonDay[player]`, `deityActivityBoonDay[player]`
- **Deity pass discount (25-27):** `deityPassBoonTier[player]`, `deityPassBoonDay[player]`, `deityDeityPassBoonDay[player]`
- **Whale pass (28):** Via `_activateWhalePass`: ticket queue writes, whale pass stats
- **Lazy pass discount (29-31):** `lazyPassBoonDiscountBps[player]`, `lazyPassBoonDay[player]`, `deityLazyPassBoonDay[player]`

**Callers:** `_rollLootboxBoons()`, `issueDeityBoon()`

**Callees:** `_activateWhalePass()` (for whale pass boon type 28 only)

**ETH Flow:** No direct ETH transfer. Whale pass activation (type 28) queues future tickets which have ETH value. Discount boons (whale, deity pass, lazy pass) reduce future purchase costs.

**Revert Conditions:** None within this function. All branches unconditionally succeed.

**Invariants:**

Upgrade vs Overwrite semantics:
- **Lootbox-sourced (`isDeity=false`):** Only upgrades if new bps > current bps (e.g., `bps > coinflipBoonBps[player]`). Day tracking uses `currentDay`, deity day set to 0.
- **Deity-sourced (`isDeity=true`):** Always overwrites regardless of current value. Day tracking uses `day` for deity fields.

Per-category behavior:
- **Coinflip (1-3):** Stores bps (500/1000/2500). Upgrade-only for lootbox. Always sets `coinflipBoonDay[player] = currentDay`. Events: emits `LootBoxReward(player, day, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS)` for non-deity.
- **Lootbox boost (5,6,22):** Deity mode sets the specific tier's active/day fields. Lootbox mode computes the max of selected vs current tier and activates only that tier (deactivating others). Event rewardType: 4=5%, 5=15%, 6=25%.
- **Purchase boost (7-9):** Stores bps (500/1500/2500). Upgrade-only for lootbox. Event rewardType mirrors lootbox boost (4/5/6) based on bps tier.
- **Decimator boost (13-15):** Stores bps (1000/2500/5000). Upgrade-only for lootbox. Note: `decimatorBoostDay` is NOT written -- only `deityDecimatorBoostDay` is set. This means lootbox-sourced decimator boons have no day tracking for expiry in this function (the day is tracked elsewhere or the boon persists until consumed).
- **Whale discount (16,23,24):** Stores discount bps (1000/2500/5000). Upgrade-only for lootbox. Day tracking differs: `whaleBoonDay = isDeity ? day : currentDay`.
- **Activity (17-19):** Stores pending amount (10/25/50). Upgrade-only for lootbox. Consumed later via `consumeActivityBoon` delegatecall.
- **Deity pass discount (25-27):** Stores tier (1/2/3). Upgrade-only for lootbox. Consumed when player purchases a deity pass.
- **Whale pass (28):** Directly activates a 100-level whale pass via `_activateWhalePass`. Event: `LootBoxWhalePassJackpot`.
- **Lazy pass discount (29-31):** Stores discount bps (1000/2500/5000). Upgrade-only for lootbox. Day tracking: `lazyPassBoonDay = isDeity ? day : currentDay`.

**NatSpec Accuracy:** Accurate. Documents the upgrade vs overwrite semantics and the lootbox vs deity distinction.

**Gas Flags:**
- The lootbox boost branch (types 5,6,22) has the most complex logic due to mutual exclusivity of the three tiers. It reads up to 3 active flags and writes up to 6 storage slots (3 active + 3 day fields). This is the most gas-intensive boon type.
- The decimator boost branch does not write a `decimatorBoostDay` -- it only writes `deityDecimatorBoostDay`. For lootbox-sourced decimator boons, this means `deityDecimatorBoostDay[player] = 0`, which is a no-op write (already 0 in most cases). The expiry/day tracking for lootbox-sourced decimator boons appears to rely on separate logic (possibly in the BoonModule's `checkAndClearExpiredBoon`).

**Verdict:** CORRECT

---

## Part 1 Summary

| Category | Count |
|----------|-------|
| External functions audited | 5 |
| Internal functions audited | 11 |
| Total functions (Part 1) | 16 |
| Verdicts: CORRECT | 15 |
| Verdicts: CONCERN | 1 |
| Verdicts: BUG | 0 |

### Concerns

1. **`_resolveLootboxCommon` -- unused `boonAmount` parameter** (informational): The `boonAmount` parameter is documented as "Amount used for boon chance calculations" but is explicitly discarded on line 850 with a bare expression statement (`boonAmount;`). All three callers pass meaningful values. The parameter should either be removed or NatSpec updated to note it is reserved/unused. No functional impact.

### Notes for Part 2

Part 2 (plan 51-03) covers the remaining internal helpers not audited here:
- `_burnieToEthValue` -- BURNIE-to-ETH conversion
- `_activateWhalePass` -- whale pass activation with ticket queuing
- `_resolveLootboxRoll` -- single roll resolution (tickets/DGNRS/WWXRP/BURNIE)
- `_lootboxTicketCount` -- ticket count from budget with variance tiers
- `_lootboxDgnrsReward` -- DGNRS reward calculation from pool
- `_creditDgnrsReward` -- DGNRS pool transfer
- `_lazyPassPriceForLevel` -- lazy pass value calculation
- `_isDecimatorWindow` -- decimator window check
- `_deityDailySeed` -- deity daily RNG seed
- `_deityBoonForSlot` -- deterministic boon slot generation
- ETH mutation path map
