# DegenerusGameMintModule.sol -- Function-Level Audit

**Contract:** DegenerusGameMintModule
**File:** contracts/modules/DegenerusGameMintModule.sol
**Lines:** 1147
**Solidity:** 0.8.34
**Inherits:** DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

DegenerusGameMintModule is the primary purchase/minting module for the Degenerus game protocol. It handles:

- **Ticket purchasing** with ETH, claimable winnings, combined payment, or BURNIE tokens
- **Mint history tracking** via bit-packed `mintPacked_` storage (level count, streak, whale bundle status)
- **Trait generation** using LCG-based PRNG seeded from VRF entropy for deterministic ticket traits
- **BURNIE rewards** credited as coinflip stake through the BurnieCoin/BurnieCoinflip system
- **Lootbox purchases** with ETH pool splitting (future/next/vault) and boost mechanics
- **Future ticket activation** via gas-budgeted batch processing with fractional remainder rolling
- **Affiliate integration** for rakeback on fresh ETH and recycled claimable purchases
- **Earlybird DGNRS rewards** for early-game participants

The module is called exclusively via `delegatecall` from DegenerusGame, so all storage reads/writes operate on the game contract's storage slots defined in DegenerusGameStorage.

## Function Audit

---

### `recordMintData(address player, uint24 lvl, uint32 mintUnits)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function recordMintData(address player, uint24 lvl, uint32 mintUnits) external payable returns (uint256 coinReward)` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): player making the purchase; `lvl` (uint24): current game level; `mintUnits` (uint32): scaled ticket units purchased |
| **Returns** | `coinReward` (uint256): BURNIE amount to credit as coinflip stake (currently always 0) |

**State Reads:**
- `mintPacked_[player]` -- player's bit-packed mint history

**State Writes:**
- `mintPacked_[player]` -- updated mint history (only if data changed)

**Callers:** Called via delegatecall from DegenerusGame.recordMint(), which is invoked by `_callTicketPurchase` within this module.

**Callees:**
- `_currentMintDay()` (inherited from DegenerusGameStorage) -- gets current day index
- `_setMintDay()` (inherited from DegenerusGameStorage) -- updates day field in packed data
- `BitPackingLib.setPacked()` -- bit-field manipulation

**ETH Flow:** No ETH movement. Marked `payable` for delegatecall compatibility but does not use `msg.value`.

**Invariants:**
- `levelCount` can only increase (never decremented), capped at `type(uint24).max`
- If `frozenUntilLevel > 0 && lvl < frozenUntilLevel`, total is NOT incremented (whale bundle pre-set levels)
- New level with `levelUnitsAfter < 4` does NOT count as "minted" -- only updates unit tracking fields
- `levelUnits` field is capped at `MASK_16` (65535)

**NatSpec Accuracy:** NatSpec states coinReward is "currently 0" which matches -- the function always returns the default 0 value. The level transition logic documentation (same level / new level <4 units / new level >=4 units) accurately matches implementation. The NatSpec mentions "century boundary" accumulation which is correct -- no special century handling exists, total simply increments.

**Gas Flags:**
- Efficient: only writes to storage if `data != prevData`
- The whale bundle frozen-level clearing block at lines 257-263 executes even when `frozenUntilLevel > 0 && lvl >= frozenUntilLevel` and the frozen state was already cleared in a prior call (writes zeros to already-zero fields). This is harmless because the `data != prevData` guard prevents actual SSTORE.

**Verdict:** CORRECT

---

### `processFutureTicketBatch(uint24 lvl)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function processFutureTicketBatch(uint24 lvl) external returns (bool worked, bool finished, uint32 writesUsed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level to process future tickets for |
| **Returns** | `worked` (bool): whether any writes were made; `finished` (bool): whether all entries processed; `writesUsed` (uint32): gas budget units consumed |

**State Reads:**
- `rngWordCurrent` -- VRF entropy for trait generation
- `ticketQueue[lvl]` -- array of player addresses with pending tickets
- `ticketLevel` -- current processing level
- `ticketCursor` -- current processing index
- `ticketsOwedPacked[lvl][player]` -- packed (owed tickets, remainder) per player

**State Writes:**
- `ticketCursor` -- updated cursor position
- `ticketLevel` -- set/cleared for level tracking
- `ticketsOwedPacked[lvl][player]` -- decremented as tickets are generated
- `ticketQueue[lvl]` -- deleted when processing complete
- `traitBurnTicket[lvl][traitId]` -- trait ticket arrays (via `_raritySymbolBatch`)

**Callers:** Called via delegatecall from DegenerusGame (during advance phase to activate queued tickets).

**Callees:**
- `_rollRemainder(entropy, baseKey, rem)` -- fractional ticket probabilistic resolution
- `_raritySymbolBatch(player, baseKey, processed, take, entropy)` -- batch trait generation

**ETH Flow:** No ETH movement.

**Invariants:**
- Write budget `WRITES_BUDGET_SAFE = 550`, scaled to 65% on first batch (cold storage)
- Processing is resumable: cursor and level are persisted between calls
- Queue is deleted only when fully processed (`idx >= total`)
- Each player's owed count decrements monotonically toward 0
- Remainders (fractional tickets) are rolled probabilistically via `_rollRemainder`

**NatSpec Accuracy:** No NatSpec on this function. The function behavior is clear from code: it processes a gas-budgeted batch of future ticket activations for a given level.

**Gas Flags:**
- Gas-budgeted design with `WRITES_BUDGET_SAFE = 550` prevents runaway gas consumption
- First-batch cold storage scaling (65%) is a deliberate optimization
- `baseOv` overhead calculation accounts for cold vs warm storage access patterns
- `total > type(uint32).max` check at line 301 prevents overflow but is practically unreachable (would need >4B queue entries)

**Verdict:** CORRECT

---

### `_raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): receiving trait tickets; `baseKey` (uint256): encoded key with level/index/player; `startIndex` (uint32): starting position within player's owed tickets; `count` (uint32): number of tickets to process this batch; `entropyWord` (uint256): VRF entropy for trait generation |
| **Returns** | None |

**State Reads:**
- `traitBurnTicket[lvl][traitId]` -- array lengths (via assembly)

**State Writes:**
- `traitBurnTicket[lvl][traitId]` -- appends player address `occurrences` times per trait (via assembly)

**Callers:** `processFutureTicketBatch`

**Callees:**
- `DegenerusTraitUtils.traitFromWord(s)` -- generates 6-bit trait from LCG state

**ETH Flow:** No ETH movement.

**Invariants:**
- Deterministic trait generation: same `baseKey + groupIdx ^ entropyWord` always produces same traits
- LCG seed is forced odd (`| 1`) for full period guarantee
- Each ticket gets a trait assigned to one of 4 quadrants via `(uint8(i & 3) << 6)` cycling
- Trait counts tracked in memory first, then batch-written to storage (gas optimization)

**NatSpec Accuracy:** NatSpec accurately describes the function as "LCG-based PRNG" for "gas-efficient bulk storage writes" using "inline assembly."

**Gas Flags:**
- Assembly-based storage writes avoid per-element Solidity overhead
- Memory arrays `counts[256]` and `touchedTraits[256]` are allocated once and reused
- Group-of-16 processing minimizes seed recalculation

**Verdict:** CORRECT

---

### `_rollRemainder(uint256 entropy, uint256 rollSalt, uint8 rem)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollRemainder(uint256 entropy, uint256 rollSalt, uint8 rem) private pure returns (bool win)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): VRF entropy base; `rollSalt` (uint256): unique salt per roll; `rem` (uint8): remainder percentage (0-99) |
| **Returns** | `win` (bool): true if remainder resolves to a whole ticket |

**State Reads:** None (pure).

**State Writes:** None (pure).

**Callers:** `processFutureTicketBatch`

**Callees:**
- `EntropyLib.entropyStep(entropy ^ rollSalt)` -- XOR-shift PRNG step

**ETH Flow:** No ETH movement.

**Invariants:**
- Probability of winning = `rem / TICKET_SCALE` (rem out of 100)
- `rem` value range 0-99; rem=0 means 0% chance, rem=99 means 99% chance
- Deterministic: same entropy + rollSalt + rem always produces same result

**NatSpec Accuracy:** Brief but accurate: "Roll remainder chance for a fractional ticket (0-99)."

**Gas Flags:** None -- minimal pure computation.

**Verdict:** CORRECT

---

### `purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of purchases; `ticketQuantity` (uint256): tickets (2 decimals, scaled by 100); `lootBoxAmount` (uint256): ETH for lootboxes; `affiliateCode` (bytes32): referral code; `payKind` (MintPaymentKind): payment method selector |
| **Returns** | None |

**State Reads:** All reads delegated to `_purchaseFor`.

**State Writes:** All writes delegated to `_purchaseFor`.

**Callers:** Called via delegatecall from DegenerusGame (main purchase entry point for ETH/claimable).

**Callees:**
- `_purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`

**ETH Flow:** Passes `msg.value` through to `_purchaseFor` which handles all ETH routing.

**Invariants:** Pure passthrough -- all validation and logic in `_purchaseFor`.

**NatSpec Accuracy:** NatSpec accurately describes the parameters and purpose. Notes that `ticketQuantity` is "scaled by 100" (2 decimal places) and `lootBoxAmount` is ETH amount.

**Gas Flags:** None -- single internal call delegation.

**Verdict:** CORRECT

---

### `purchaseCoin(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseCoin(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): recipient of purchases; `ticketQuantity` (uint256): tickets (2 decimals, scaled by 100); `lootBoxBurnieAmount` (uint256): BURNIE amount for lootboxes |
| **Returns** | None |

**State Reads:** Delegated to `_purchaseCoinFor`.

**State Writes:** Delegated to `_purchaseCoinFor`.

**Callers:** Called via delegatecall from DegenerusGame (BURNIE-paid purchase entry point). Note: IDegenerusGame interface shows `purchaseCoin` takes 3 params (buyer, ticketQuantity, lootBoxBurnieAmount) -- no affiliateCode for BURNIE purchases.

**Callees:**
- `_purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount)`

**ETH Flow:** No ETH movement -- BURNIE-only purchase path.

**Invariants:** Pure passthrough to `_purchaseCoinFor`.

**NatSpec Accuracy:** Accurately describes BURNIE ticket and lootbox purchase path. Notes "allowed whenever RNG is unlocked" which is enforced by `_callTicketPurchase`.

**Gas Flags:** None -- single internal call delegation.

**Verdict:** CORRECT

---

### `purchaseBurnieLootbox(address buyer, uint256 burnieAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): recipient; `burnieAmount` (uint256): BURNIE to spend on lootbox |
| **Returns** | None |

**State Reads:** Delegated to `_purchaseBurnieLootboxFor`.

**State Writes:** Delegated to `_purchaseBurnieLootboxFor`.

**Callers:** Called via delegatecall from DegenerusGame (standalone BURNIE lootbox entry).

**Callees:**
- `_purchaseBurnieLootboxFor(buyer, burnieAmount)`

**ETH Flow:** No ETH movement -- BURNIE-only.

**Invariants:**
- Reverts if `buyer == address(0)` (explicit null check)
- All other validation in `_purchaseBurnieLootboxFor`

**NatSpec Accuracy:** Describes it as "low-EV loot box with BURNIE" -- accurate.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): ticket recipient; `ticketQuantity` (uint256): tickets scaled by 100; `lootBoxBurnieAmount` (uint256): BURNIE for lootboxes |
| **Returns** | None |

**State Reads:**
- `block.timestamp` -- for elapsed time check
- `levelStartTime` -- start of current level (inherited storage)
- `level` -- current game level (inherited storage)

**State Writes:** Delegated to `_callTicketPurchase` and `_purchaseBurnieLootboxFor`.

**Callers:** `purchaseCoin`

**Callees:**
- `_callTicketPurchase(buyer, payer, ticketQuantity, MintPaymentKind.DirectEth, true, bytes32(0), 0)` -- for ticket purchase with `payInCoin=true`
- `_purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount)` -- for BURNIE lootbox

**ETH Flow:** No ETH movement.

**Invariants:**
- BURNIE ticket purchases are blocked within 30 days of liveness-guard timeout:
  - Level 0: `elapsed > 882 days` (912 - 30) reverts with `CoinPurchaseCutoff`
  - Other levels: `elapsed > 335 days` (365 - 30) reverts with `CoinPurchaseCutoff`
- Uses `msg.sender` as payer (not buyer) -- BURNIE burned from caller
- Passes `MintPaymentKind.DirectEth` to ticket purchase despite being BURNIE -- the `payInCoin=true` flag overrides payment handling
- Affiliate code is `bytes32(0)` -- no affiliate attribution for BURNIE purchases

**NatSpec Accuracy:** No explicit NatSpec on this private function. The cutoff logic matches the documented 30-day safety window.

**Gas Flags:**
- The ternary for cutoff check `level == 0 ? ... : ...` is efficient
- `payer = msg.sender` local variable avoids repeated `msg.sender` reads (though Solidity compiler typically optimizes this)

**Verdict:** CORRECT

---

### `_purchaseFor(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseFor(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): recipient; `ticketQuantity` (uint256): tickets scaled by 100; `lootBoxAmount` (uint256): ETH for lootboxes; `affiliateCode` (bytes32): referral code; `payKind` (MintPaymentKind): payment method |
| **Returns** | None |

**State Reads:**
- `level` -- current game level
- `price` -- current ticket price in wei
- `rngLockedFlag` -- whether VRF is pending
- `lastPurchaseDay` -- whether this is the last purchase day
- `claimableWinnings[buyer]` -- player's claimable balance
- `claimablePool` -- total claimable pool
- `lootboxRngIndex` -- current lootbox RNG index
- `lootboxPresaleActive` -- presale mode flag
- `lootboxEth[index][buyer]` -- existing lootbox ETH for player
- `lootboxDay[index][buyer]` -- day of lootbox purchase
- `lootboxEthBase[index][buyer]` -- base (pre-boost) lootbox amount
- `lootboxEthTotal` -- global lootbox ETH total
- `lootboxPresaleMintEth` -- presale mint ETH tracker
- `futurePrizePool` -- future prize pool balance
- `nextPrizePool` -- next prize pool balance

**State Writes:**
- `claimableWinnings[buyer]` -- decreased if claimable used for lootbox shortfall
- `claimablePool` -- decreased by lootbox claimable shortfall
- `lootboxDay[index][buyer]` -- set on first lootbox purchase per index
- `lootboxBaseLevelPacked[index][buyer]` -- set to `level + 2` on first purchase
- `lootboxEvScorePacked[index][buyer]` -- player activity score + 1
- `lootboxIndexQueue[buyer]` -- push index on first purchase
- `lootboxEthBase[index][buyer]` -- accumulated base (pre-boost) amount
- `lootboxEth[index][buyer]` -- packed (purchaseLevel, boostedAmount)
- `lootboxEthTotal` -- increased by raw lootBoxAmount
- `lootboxRngPendingEth` -- increased (via `_maybeRequestLootboxRng`)
- `lootboxPresaleMintEth` -- increased if presale active
- `futurePrizePool` -- increased by futureShare + rewardShare
- `nextPrizePool` -- increased by nextShare
- Plus all writes from `_callTicketPurchase` (if tickets purchased)
- Plus all writes from `_applyLootboxBoostOnPurchase` (boost consumption)

**Callers:** `purchase`

**Callees:**
- `_callTicketPurchase(buyer, buyer, ticketQuantity, payKind, false, affiliateCode, remainingEth)` -- ticket purchase delegation
- `_simulatedDayIndex()` -- current day index
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` -- self-call for activity score
- `_applyLootboxBoostOnPurchase(buyer, day, lootBoxAmount)` -- boost application
- `_maybeRequestLootboxRng(lootBoxAmount)` -- lootbox RNG threshold tracking
- `affiliate.payAffiliate(...)` -- affiliate reward distribution (called separately for fresh ETH and claimable portions)
- `coin.creditFlip(buyer, lootboxRakeback)` -- BURNIE coinflip credit from affiliate rakeback
- `coin.notifyQuestMint(buyer, questUnits, true/false)` -- quest progress for lootbox purchases
- `coin.notifyQuestLootBox(buyer, lootBoxAmount)` -- lootbox quest progress
- `_awardEarlybirdDgnrs(buyer, lootboxFreshEth, purchaseLevel)` -- DGNRS earlybird rewards
- `_ethToBurnieValue(amountWei, priceWei)` -- ETH to BURNIE conversion
- `coin.creditFlip(buyer, bonusAmount)` -- 10% "spent-all-claimable" bonus

**ETH Flow:**

1. **Ticket cost:** `(priceWei * ticketQuantity) / (4 * TICKET_SCALE)` -- ETH flows via `_callTicketPurchase` to `recordMint` which routes to prize pools
2. **Lootbox ETH split (normal):** 90% future pool, 10% next pool, 0% remainder added to future
3. **Lootbox ETH split (presale):** 40% future, 40% next, 20% vault (sent via `call`)
4. **Lootbox claimable shortfall:** deducted from `claimableWinnings[buyer]` and `claimablePool`
5. **Vault share:** sent via low-level `call{value: vaultShare}` to `ContractAddresses.VAULT`

**Invariants:**
- `purchaseLevel = level + 1` (tickets target next level)
- Lootbox purchases blocked during BAF/Decimator resolution: `rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)`
- Minimum lootbox purchase: 0.01 ETH (`LOOTBOX_MIN`)
- Total cost (tickets + lootbox) must be > 0
- Lootbox payment prefers `msg.value` first, then claimable shortfall (unless `DirectEth`)
- Claimable balance must exceed shortfall (preserves 1 wei sentinel: `claimable <= shortfall` reverts)
- "Spent all claimable" 10% bonus: only if `totalClaimableUsed >= priceWei * 3` (at least 3 full ticket prices of claimable spent)
- Bonus formula: `(totalClaimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100)` = 10% of total claimable used, denominated in BURNIE

**NatSpec Accuracy:** NatSpec describes "Handles payment routing, affiliates, and queues" -- accurate but understates complexity. The inline comments within the function are thorough.

**Gas Flags:**
- Multiple external calls to `affiliate.payAffiliate` (one for fresh ETH, one for claimable) could be batched but affiliate contract design requires separate calls for different `isFreshEth` flags
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` is a self-delegatecall -- relatively expensive but necessary for cross-module access
- The vault share `call` has no gas limit (sends all gas) -- standard for ETH transfers to known contracts

**Verdict:** CORRECT

---

### `_callTicketPurchase(address buyer, address payer, uint256 quantity, MintPaymentKind payKind, bool payInCoin, bytes32 affiliateCode, uint256 value)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _callTicketPurchase(address buyer, address payer, uint256 quantity, MintPaymentKind payKind, bool payInCoin, bytes32 affiliateCode, uint256 value) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): ticket recipient; `payer` (address): who pays (may differ from buyer); `quantity` (uint256): tickets scaled by 100; `payKind` (MintPaymentKind): payment method; `payInCoin` (bool): true if paying with BURNIE; `affiliateCode` (bytes32): referral code; `value` (uint256): remaining ETH available for this ticket purchase |
| **Returns** | None |

**State Reads:**
- `gameOver` -- terminal state check
- `rngLockedFlag` -- VRF lock check
- `jackpotPhaseFlag` -- current phase (purchase vs jackpot)
- `level` -- current level
- `price` -- current ticket price
- `lastPurchaseDay` -- last purchase day flag
- `jackpotCounter` -- jackpot day counter (for final-day affiliate bonus)

**State Writes:**
- Via `IDegenerusGame(address(this)).recordMint{value}(...)` -- records mint and routes ETH to prize pools
- Via `_coinReceive(payer, coinCost)` -- burns BURNIE if `payInCoin`
- Via `coin.creditFlip(buyer, bonusCredit)` -- credits BURNIE coinflip stake
- Via `_queueTicketsScaled(buyer, ticketLevel, adjustedQty32)` -- queues tickets for trait generation
- Via `affiliate.payAffiliate(...)` -- distributes affiliate rewards
- Via `coin.notifyQuestMint(payer, questUnits, true/false)` -- quest progress

**Callers:** `_purchaseFor` (ETH path), `_purchaseCoinFor` (BURNIE path)

**Callees:**
- `IDegenerusGame(address(this)).recordMint{value}(payer, targetLevel, costWei, mintUnits, payKind)` -- self-call to record mint and handle ETH routing
- `IDegenerusGame(address(this)).consumePurchaseBoost(payer)` -- consume pending boost
- `_coinReceive(payer, coinCost)` -- burn BURNIE
- `affiliate.payAffiliate(...)` -- affiliate reward (called 1-2 times depending on `payKind`)
- `coin.creditFlip(buyer, bonusCredit)` -- credit BURNIE coinflip stake
- `coin.notifyQuestMint(payer, questUnits, paidWithEth)` -- quest tracking
- `_ethToBurnieValue(freshEth, priceWei)` -- conversion helper
- `_queueTicketsScaled(buyer, ticketLevel, adjustedQty32)` -- ticket queuing

**ETH Flow:**
- **DirectEth:** `value >= costWei` required; full `value` forwarded to `recordMint`
- **Claimable:** `value == 0` required; claimable deducted in `recordMint`
- **Combined:** `value <= costWei`; partial ETH + partial claimable handled in `recordMint`
- All ETH ultimately flows through `recordMint` to prize pool splits (current/next/future/coinflip)

**Invariants:**
- `quantity` must be non-zero, <= `type(uint32).max`
- `gameOver` must be false
- `rngLockedFlag` must be false
- `costWei = (priceWei * quantity) / (4 * TICKET_SCALE)` must be > 0 and >= `TICKET_MIN_BUYIN_WEI` (0.0025 ETH)
- Target level differs by phase: `jackpotPhaseFlag ? level : level + 1`
- Purchase boost (if available and `!payInCoin`): increases `adjustedQuantity` but cost remains same (bonus tickets)
- Boost cap: `LOOTBOX_BOOST_MAX_VALUE = 10 ether` -- boost applies to at most 10 ETH equivalent
- Final jackpot day affiliate bonus: +40% (levels 1-3) or +50% (levels 4+) BURNIE affiliate amount
- BURNIE bonuses: base 10% of coinCost, plus 2.5% if bulk (>= 10 full tickets), plus 20% of coinCost if lastPurchaseDay and level % 100 > 90

**NatSpec Accuracy:** No explicit NatSpec on this private function.

**Gas Flags:**
- Three separate `affiliate.payAffiliate` calls for Combined path (one for fresh ETH, one for recycled) plus separate handling for DirectEth and Claimable -- necessarily separate due to `isFreshEth` flag differences
- `IDegenerusGame(address(this)).consumePurchaseBoost(payer)` self-call overhead is unavoidable for cross-module access
- `adjustedQuantity` overflow check at line 845 (capped to `uint32.max`) is a safety bound

**Verdict:** CORRECT

---

### `_coinReceive(address payer, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _coinReceive(address payer, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `payer` (address): address to burn BURNIE from; `amount` (uint256): BURNIE amount to burn |
| **Returns** | None |

**State Reads:** None directly (delegated to external call).

**State Writes:** None directly -- BURNIE burn happens in external contract.

**Callers:** `_callTicketPurchase` (when `payInCoin == true`)

**Callees:**
- `coin.burnCoin(payer, amount)` -- burns BURNIE tokens from payer

**ETH Flow:** No ETH movement.

**Invariants:**
- Requires `payer` to have sufficient BURNIE balance and approval (enforced by BurnieCoin contract)

**NatSpec Accuracy:** No NatSpec. Function name and implementation are self-documenting.

**Gas Flags:** None -- single external call.

**Verdict:** CORRECT

---

### `_ethToBurnieValue(uint256 amountWei, uint256 priceWei)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _ethToBurnieValue(uint256 amountWei, uint256 priceWei) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `amountWei` (uint256): ETH amount in wei; `priceWei` (uint256): current ticket price in wei |
| **Returns** | `uint256`: equivalent BURNIE amount in base units |

**State Reads:** None (pure).

**State Writes:** None (pure).

**Callers:** `_purchaseFor` (lootbox affiliate), `_callTicketPurchase` (ticket affiliate)

**Callees:** None.

**ETH Flow:** No ETH movement -- pure conversion.

**Invariants:**
- Returns 0 if either input is 0 (division-by-zero guard)
- Formula: `(amountWei * PRICE_COIN_UNIT) / priceWei` where `PRICE_COIN_UNIT = 1000 ether`
- Result represents "how many full-ticket BURNIE equivalents" the ETH amount represents

**NatSpec Accuracy:** NatSpec says "Convert ETH-denominated spend to BURNIE base units at current ticket price" -- accurate.

**Gas Flags:** None -- minimal pure arithmetic.

**Verdict:** CORRECT

---

### `_purchaseBurnieLootboxFor(address buyer, uint256 burnieAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _purchaseBurnieLootboxFor(address buyer, uint256 burnieAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): lootbox recipient; `burnieAmount` (uint256): BURNIE amount to spend |
| **Returns** | None |

**State Reads:**
- `lootboxRngIndex` -- current lootbox RNG index
- `lootboxBurnie[index][buyer]` -- existing BURNIE lootbox amount
- `lootboxDay[index][buyer]` -- day of first lootbox purchase
- `price` -- current ticket price
- `lootboxRngPendingBurnie` -- pending BURNIE for RNG tracking

**State Writes:**
- `lootboxBurnie[index][buyer]` -- accumulated BURNIE lootbox amount
- `lootboxDay[index][buyer]` -- set if first purchase for this index
- `lootboxRngPendingBurnie` -- increased by burnieAmount
- `lootboxRngPendingEth` -- increased by virtualEth (via `_maybeRequestLootboxRng`)

**Callers:** `_purchaseCoinFor`, `purchaseBurnieLootbox`

**Callees:**
- `coin.burnCoin(buyer, burnieAmount)` -- burns BURNIE from buyer
- `coin.notifyQuestMint(buyer, questUnitsRaw, false)` -- quest progress (BURNIE-paid)
- `_simulatedDayIndex()` -- day index for first purchase
- `_maybeRequestLootboxRng(virtualEth)` -- RNG threshold tracking

**ETH Flow:** No ETH movement. BURNIE is burned. Virtual ETH equivalent tracked for RNG threshold calculation.

**Invariants:**
- Minimum BURNIE: `BURNIE_LOOTBOX_MIN = 1000 ether` (1000 BURNIE)
- `lootboxRngIndex` must be > 0 (reverts if 0 -- no active lootbox RNG index)
- Virtual ETH conversion: `(burnieAmount * priceWei) / PRICE_COIN_UNIT`
- Quest units: `burnieAmount / PRICE_COIN_UNIT` (whole ticket equivalents)
- BURNIE lootbox has no presale mode, no boost application, no affiliate rakeback
- Day is set only on first purchase per (index, buyer) pair

**NatSpec Accuracy:** Parent function NatSpec describes "low-EV loot box" -- accurate for BURNIE path.

**Gas Flags:**
- `price` loaded locally as `priceWei` to avoid multiple storage reads

**Verdict:** CORRECT

---

### `_maybeRequestLootboxRng(uint256 lootBoxAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeRequestLootboxRng(uint256 lootBoxAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lootBoxAmount` (uint256): ETH amount (or virtual ETH equivalent) to add to pending threshold |
| **Returns** | None |

**State Reads:** None directly (only writes).

**State Writes:**
- `lootboxRngPendingEth` -- increased by `lootBoxAmount`

**Callers:** `_purchaseFor` (ETH lootbox), `_purchaseBurnieLootboxFor` (BURNIE lootbox virtual ETH)

**Callees:** None.

**ETH Flow:** No ETH movement -- accumulator for RNG request threshold.

**Invariants:**
- Simple accumulator -- actual VRF request is triggered elsewhere (in DegenerusGame when threshold is met)

**NatSpec Accuracy:** No NatSpec. Function name is descriptive enough -- "maybe request" refers to threshold-based triggering done at a higher level.

**Gas Flags:** None -- single SSTORE increment.

**Verdict:** CORRECT

---

### `_calculateBoost(uint256 amount, uint16 bonusBps)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _calculateBoost(uint256 amount, uint16 bonusBps) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `amount` (uint256): base amount; `bonusBps` (uint16): boost in basis points |
| **Returns** | `uint256`: boost amount to add |

**State Reads:** None (pure).

**State Writes:** None (pure).

**Callers:** `_applyLootboxBoostOnPurchase`

**Callees:** None.

**ETH Flow:** No ETH movement -- pure computation.

**Invariants:**
- Amount capped at `LOOTBOX_BOOST_MAX_VALUE = 10 ether` before applying BPS
- Formula: `(min(amount, 10 ETH) * bonusBps) / 10_000`
- Maximum possible boost: 10 ETH * 2500 / 10000 = 2.5 ETH (with 25% boost)

**NatSpec Accuracy:** NatSpec says "Calculate boost amount given base amount and bonus bps" -- accurate.

**Gas Flags:** None -- minimal pure arithmetic in unchecked block.

**Verdict:** CORRECT

---

### `_applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount) private returns (uint256 boostedAmount)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): buyer; `day` (uint48): current day index; `amount` (uint256): base lootbox purchase amount |
| **Returns** | `boostedAmount` (uint256): amount after boost (>= original amount) |

**State Reads:**
- `lootboxBoon25Active[player]` -- 25% boost active flag
- `lootboxBoon25Day[player]` -- day boost was awarded
- `lootboxBoon15Active[player]` -- 15% boost active flag
- `lootboxBoon15Day[player]` -- day boost was awarded
- `lootboxBoon5Active[player]` -- 5% boost active flag
- `lootboxBoon5Day[player]` -- day boost was awarded

**State Writes:**
- `lootboxBoon25Active[player]` -- set to false (consumed or expired)
- `lootboxBoon15Active[player]` -- set to false (consumed or expired)
- `lootboxBoon5Active[player]` -- set to false (consumed or expired)

**Callers:** `_purchaseFor` (lootbox section)

**Callees:**
- `_calculateBoost(amount, bonusBps)` -- compute boost amount

**ETH Flow:** No direct ETH movement -- modifies the boosted lootbox amount which affects pool splits.

**Invariants:**
- Cascading priority: 25% > 15% > 5% (only best available boost applies)
- Expiry: boost expires after `LOOTBOX_BOOST_EXPIRY_DAYS = 2` days from award
- Single-use: boost flag set to false on consumption or expiration
- Expired boosts are cleaned up (set to false) on encounter, preventing stale state
- `boostedAmount >= amount` (boost only adds, never subtracts)

**NatSpec Accuracy:** No explicit NatSpec on this function.

**Gas Flags:**
- Cascading if-else means at most 3 storage reads for the worst case (no boost available)
- Expired boosts are cleaned up eagerly (deactivated on check) -- prevents accumulation of stale state

**Verdict:** CORRECT

---

## ETH Mutation Path Map

### Purchase ETH Flow

The primary ETH entry point is `purchase()` -> `_purchaseFor()`. All ETH flows through this single private function.

#### Ticket Purchase ETH Path

```
msg.value
  |
  v
_purchaseFor()
  |-- Lootbox portion deducted first (msg.value >= lootBoxAmount)
  |     |-- If shortfall and payKind != DirectEth:
  |     |     claimableWinnings[buyer] -= shortfall
  |     |     claimablePool -= shortfall
  |     v
  |-- remainingEth = msg.value - lootBoxAmount
  |
  v
_callTicketPurchase(buyer, buyer, ticketQuantity, payKind, false, affiliateCode, remainingEth)
  |
  |-- costWei = (priceWei * quantity) / (4 * TICKET_SCALE)
  |
  v
IDegenerusGame(address(this)).recordMint{value: remainingEth}(payer, targetLevel, costWei, mintUnits, payKind)
  |
  |-- recordMint (in DegenerusGame) handles the actual ETH distribution:
  |     |
  |     |-- DirectEth: value >= costWei; excess refunded
  |     |-- Claimable: value == 0; deducts from claimableWinnings
  |     |-- Combined: value <= costWei; remainder from claimable
  |     |
  |     v
  |   ETH Split (inside DegenerusGame.recordMint):
  |     |-- currentPrizePool += currentPoolShare
  |     |-- nextPrizePool += nextPoolShare
  |     |-- futurePrizePool += futurePoolShare
  |     |-- coinflip credit (BURNIE via coin.creditFlip)
  |     |-- Any excess refunded
```

| Step | Source | Destination | Amount/Formula | Function |
|------|--------|-------------|----------------|----------|
| 1 | msg.value | _purchaseFor | Full msg.value received | purchase() |
| 2 | msg.value | Lootbox allocation | Up to lootBoxAmount | _purchaseFor |
| 3 | msg.value remainder | _callTicketPurchase | remainingEth = msg.value - lootBoxAmount | _purchaseFor |
| 4 | remainingEth | recordMint (self-call) | Full remainingEth forwarded | _callTicketPurchase |
| 5 | costWei | Prize pool splits | (priceWei * qty) / 400 | recordMint (DegenerusGame) |
| 6 | costWei fraction | currentPrizePool | Configurable BPS | recordMint |
| 7 | costWei fraction | nextPrizePool | Configurable BPS | recordMint |
| 8 | costWei fraction | futurePrizePool | Configurable BPS | recordMint |
| 9 | Affiliate BURNIE | coin.creditFlip | _ethToBurnieValue(freshEth) | _callTicketPurchase |

#### Lootbox ETH Path

```
lootBoxAmount (from msg.value or claimable or both)
  |
  v
Pool Splitting (in _purchaseFor):
  |
  |-- Normal mode (lootboxPresaleActive == false):
  |     |-- futureShare = lootBoxAmount * 9000 / 10000 (90%)
  |     |-- nextShare = lootBoxAmount * 1000 / 10000 (10%)
  |     |-- vaultShare = 0
  |     |-- rewardShare = lootBoxAmount - futureShare - nextShare (rounding dust)
  |     |
  |     |-- futurePrizePool += futureShare + rewardShare
  |     |-- nextPrizePool += nextShare
  |
  |-- Presale mode (lootboxPresaleActive == true):
  |     |-- futureShare = lootBoxAmount * 4000 / 10000 (40%)
  |     |-- nextShare = lootBoxAmount * 4000 / 10000 (40%)
  |     |-- vaultShare = lootBoxAmount * 2000 / 10000 (20%)
  |     |-- rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare (dust)
  |     |
  |     |-- futurePrizePool += futureShare + rewardShare
  |     |-- nextPrizePool += nextShare
  |     |-- VAULT.call{value: vaultShare}("") -- ETH TRANSFER to vault
  |
  v
Affiliate (BURNIE, not ETH):
  |-- Fresh ETH portion: affiliate.payAffiliate(burnieValue, ..., true, activityScore)
  |-- Claimable portion: affiliate.payAffiliate(burnieValue, ..., false, 0)
  |-- Rakeback: coin.creditFlip(buyer, totalRakeback)
```

| Step | Source | Destination | Amount/Formula | Function |
|------|--------|-------------|----------------|----------|
| 1 | lootBoxAmount | Pool split calculation | Raw lootbox ETH amount | _purchaseFor |
| 2 | futureShare | futurePrizePool | 90% normal / 40% presale | _purchaseFor |
| 3 | nextShare | nextPrizePool | 10% normal / 40% presale | _purchaseFor |
| 4 | vaultShare | VAULT contract | 0% normal / 20% presale | _purchaseFor (call) |
| 5 | rewardShare (dust) | futurePrizePool | Rounding remainder | _purchaseFor |
| 6 | lootboxFreshEth | Affiliate BURNIE calc | _ethToBurnieValue(freshEth, price) | _purchaseFor |

#### Claimable Payment Flow

```
MintPaymentKind.Claimable or MintPaymentKind.Combined:
  |
  v
Lootbox shortfall (in _purchaseFor):
  |-- claimable = claimableWinnings[buyer]
  |-- shortfall = lootBoxAmount - msg.value (if msg.value < lootBoxAmount)
  |-- claimable > shortfall required (preserves 1 wei sentinel)
  |-- claimableWinnings[buyer] -= shortfall
  |-- claimablePool -= shortfall
  |
Ticket purchase (in recordMint via _callTicketPurchase):
  |-- Claimable: value=0, costWei deducted from claimableWinnings in recordMint
  |-- Combined: value=partial ETH, remainder from claimableWinnings in recordMint
  |
"Spent All Claimable" Bonus (in _purchaseFor):
  |-- Condition: totalClaimableUsed > 0 AND availableClaimable < minTicketUnitCost
  |-- Condition: totalClaimableUsed >= priceWei * 3 (at least 3 full tickets worth)
  |-- Bonus: (totalClaimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100)
  |         = 10% of claimable used, in BURNIE units
  |-- coin.creditFlip(buyer, bonusAmount)
```

### BURNIE Purchase Flow

```
purchaseCoin() -> _purchaseCoinFor()
  |
  |-- Liveness guard cutoff check (882 days lvl 0, 335 days otherwise)
  |
  |-- Ticket path:
  |     _callTicketPurchase(..., payInCoin=true, ...)
  |       |-- coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE
  |       |-- coin.burnCoin(payer, coinCost)  -- BURNIE BURNED
  |       |-- bonusCredit = coinCost / 10     -- 10% of BURNIE cost as coinflip credit
  |       |-- coin.creditFlip(buyer, bonusCredit)
  |       |-- _queueTicketsScaled(buyer, targetLevel, qty)
  |       |-- coin.notifyQuestMint(payer, questQty, false)
  |       |
  |       |-- NO ETH movement
  |       |-- NO affiliate call (affiliateCode = bytes32(0) and isFreshEth meaningless)
  |
  |-- Lootbox path:
        _purchaseBurnieLootboxFor(buyer, burnieAmount)
          |-- coin.burnCoin(buyer, burnieAmount)  -- BURNIE BURNED
          |-- lootboxBurnie[index][buyer] += burnieAmount
          |-- lootboxRngPendingBurnie += burnieAmount
          |-- virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT
          |-- _maybeRequestLootboxRng(virtualEth)  -- tracks toward RNG threshold
          |-- coin.notifyQuestMint(buyer, questUnitsRaw, false)
          |
          |-- NO ETH movement
          |-- NO pool splits (BURNIE lootboxes don't add to prize pools)
          |-- NO affiliate rakeback
```

### Standalone BURNIE Lootbox Flow

```
purchaseBurnieLootbox(buyer, burnieAmount)
  |-- buyer != address(0) check
  v
_purchaseBurnieLootboxFor(buyer, burnieAmount)
  |-- Same as BURNIE lootbox path above
  |-- Minimum: 1000 BURNIE (BURNIE_LOOTBOX_MIN)
  |-- lootboxRngIndex must be > 0
```

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 2 | (1) `_purchaseFor` makes two `affiliate.payAffiliate` calls for mixed fresh/claimable lootbox -- necessary due to `isFreshEth` flag separation. (2) Self-call `IDegenerusGame(address(this)).playerActivityScore` and `.consumePurchaseBoost` add delegatecall overhead -- required for cross-module storage access pattern. |
| CORRECT | 16 | All 16 functions verified correct |

### NatSpec Header Verification

**Activity Score System (lines 25-50):**
- Documents 5 metrics: Level Count, Level Streak, Quest Streak, Affiliate Points, Whale Bundle
- Implementation: `recordMintData` updates Level Count and Whale Bundle status in `mintPacked_`
- Level Streak is documented in NatSpec but NOT updated in `recordMintData` -- the streak field in `mintPacked_` (bits 48-71) is never written by this function. **However**, streak is managed by `DegenerusGame.recordMint()` which calls `recordMintData` via delegatecall. The streak update happens in the caller, not this module. NatSpec correctly notes "Quest Streak and Affiliate Points are tracked separately."
- **Verdict:** NatSpec accurately describes the system. Streak omission from this module is by design.

**Mint Data Bit Packing Layout (lines 34-47):**
- Matches `BitPackingLib` constants exactly:
  - Bits 0-23: lastLevel (`LAST_LEVEL_SHIFT = 0`, `MASK_24`)
  - Bits 24-47: levelCount (`LEVEL_COUNT_SHIFT = 24`, `MASK_24`)
  - Bits 48-71: levelStreak (`LEVEL_STREAK_SHIFT = 48`, `MASK_24`) -- not written by this module
  - Bits 72-103: lastMintDay (`DAY_SHIFT = 72`, `MASK_32`)
  - Bits 104-127: unitsLevel (`LEVEL_UNITS_LEVEL_SHIFT = 104`, `MASK_24`)
  - Bits 128-151: frozenUntilLevel (`FROZEN_UNTIL_LEVEL_SHIFT = 128`, `MASK_24`)
  - Bits 152-154: whaleBundleType (`WHALE_BUNDLE_TYPE_SHIFT = 152`, mask 3) -- NatSpec says "152-153" (2 bits) but constant mask is 3 (2 bits). The shift constant says bits 152-154 (3 bits) in BitPackingLib comment. Minor: NatSpec says 2 bits but the shift position allows 3 bits. Actual mask `3` = 2 bits. **Consistent.**
  - Bits 228-243: levelUnits (`LEVEL_UNITS_SHIFT = 228`, `MASK_16`)
  - Bit 244: deprecated
- **Verdict:** Layout matches implementation.

**Purchase Cost Formula:**
- NatSpec header doesn't explicitly state the formula, but inline comments confirm:
  - `costWei = (priceWei * ticketQuantity) / (4 * TICKET_SCALE)`
  - `TICKET_SCALE = 100`, so `costWei = (priceWei * ticketQuantity) / 400`
  - 1 full ticket = quantity 400 (4 * 100) = costs exactly priceWei
- **Verdict:** Matches project memory documentation exactly.

### MintPaymentKind Behavior Summary

| PayKind | value (msg.value) | Claimable Used | Affiliate freshEth Flag |
|---------|-------------------|----------------|-------------------------|
| DirectEth (0) | >= costWei | No | true |
| Claimable (1) | == 0 | Yes, full costWei | false |
| Combined (2) | 0 < value <= costWei | Yes, costWei - value | Both (split calls) |

### Trait Generation Determinism

- Trait generation is fully deterministic from `(baseKey, groupIdx, entropyWord)`
- `baseKey` encodes `(level, queueIndex, playerAddress)` for uniqueness
- LCG with multiplier `6364136223846793005` provides full-period coverage (seed forced odd)
- Quadrant cycling via `(i & 3) << 6` ensures even distribution across 4 trait quadrants
- `DegenerusTraitUtils.traitFromWord()` provides weighted bucket distribution (8 categories x 8 sub-buckets)
- **Verdict:** Deterministic and manipulation-resistant (VRF-seeded entropy).
