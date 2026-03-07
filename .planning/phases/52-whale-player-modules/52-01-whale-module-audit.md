# DegenerusGameWhaleModule.sol -- Function-Level Audit

**Contract:** DegenerusGameWhaleModule
**File:** contracts/modules/DegenerusGameWhaleModule.sol
**Lines:** 890
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

Handles whale bundle purchases (100-level pass at 2.4/4 ETH), lazy pass purchases (10-level pass at 0.24 ETH flat or sum-of-level-prices), deity pass purchases (symbol-bound premium pass at 24+T(n) ETH), and deity pass transfers. Manages DGNRS token rewards for whale-tier purchases (whale pool and affiliate pool distributions). All functions execute via delegatecall, operating on DegenerusGame's storage. Records lootbox entries at 20% (presale) or 10% (post-presale) of purchase value. Pool splits are 70/30 (pre-game) or 95/5 (post-game) future/next, except lazy pass which uses a fixed 10/90 future/next split.

## Contract-Level Notes

**Constants (18 total):**
- Lootbox boost BPS: 500 (5%), 1500 (15%), 2500 (25%); max value 10 ETH; expiry 2 days
- DGNRS PPM scale: 1,000,000; whale minter 10,000 (1%); affiliate direct whale 1,000 (0.1%); upline whale 200 (0.02%); affiliate direct deity 5,000 (0.5%); upline deity 1,000 (0.1%)
- Deity whale pool BPS: 500 (5%)
- Lazy pass: 10 levels, 4 tickets/level, lootbox presale 2000 BPS (20%), post 1000 BPS (10%), boon default 1000 BPS (10%), to-future 1000 BPS (10%)
- Whale bundle: early price 2.4 ETH, standard 4 ETH, bonus tickets/level 40, standard tickets/level 2, bonus end level 10, lootbox presale/post same as lazy
- Deity: base 24 ETH, transfer cost 5 ETH, boon expiry 4 days, lootbox presale/post same

**External Contract References:**
- `affiliate` = IDegenerusAffiliate(ContractAddresses.AFFILIATE) -- referral chain lookups
- `dgnrs` = IDegenerusStonk(ContractAddresses.DGNRS) -- DGNRS pool transfers

**Events:**
- `LootBoxBoostConsumed(player, day, originalAmount, boostedAmount, boostBps)` -- emitted when lootbox boost boon consumed
- `LootBoxIndexAssigned(buyer, index, day)` -- emitted on new lootbox index assignment

**Errors:**
- `E()` -- generic revert for all validation failures

## Function Audit

### `purchaseWhaleBundle(address buyer, uint256 quantity)` [external] + `_purchaseWhaleBundle` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseWhaleBundle(address buyer, uint256 quantity) external payable` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of the bundle; `quantity` (uint256): number of bundles (1-100) |
| **Returns** | none |

**State Reads:**
- `gameOver` -- revert guard
- `level` -- derives passLevel = level + 1; determines price tier and pool split ratio
- `whaleBoonDay[buyer]` -- checks for valid discount boon
- `whaleBoonDiscountBps[buyer]` -- discount tier in BPS (10/25/50% off standard)
- `mintPacked_[buyer]` -- unpacks frozenUntilLevel, levelCount for delta calculations
- `lootboxPresaleActive` -- determines lootbox percentage (20% vs 10%)
- `dailyIdx` (via `_currentMintDay()`) -- day tracking
- `lootboxRngIndex` (via `_recordLootboxEntry`) -- current lootbox RNG index
- `lootboxEth[index][buyer]`, `lootboxDay[index][buyer]`, `lootboxBaseLevelPacked[index][buyer]`, `lootboxEvScorePacked[index][buyer]`, `lootboxEthBase[index][buyer]`, `lootboxEthTotal`, `lootboxRngPendingEth` -- lootbox recording state
- `lootboxBoon25Active/Day`, `lootboxBoon15Active/Day`, `lootboxBoon5Active/Day` (via `_applyLootboxBoostOnPurchase`) -- boost boon state
- `ticketsOwedPacked[lvl][buyer]` (via `_queueTickets`) -- existing ticket state
- `earlybirdDgnrsPoolStart`, `earlybirdEthIn` (via `_awardEarlybirdDgnrs`) -- earlybird DGNRS tracking
- `dgnrs.poolBalance(Whale)`, `dgnrs.poolBalance(Affiliate)` (via `_rewardWhaleBundleDgnrs`) -- DGNRS pool reserves
- `affiliate.getReferrer(buyer/affiliate/upline)` -- referral chain resolution

**State Writes:**
- `whaleBoonDay[buyer]` -- deleted if boon consumed
- `whaleBoonDiscountBps[buyer]` -- deleted if boon consumed
- `mintPacked_[buyer]` -- updated: LEVEL_COUNT += levelsToAdd, FROZEN_UNTIL_LEVEL = max(old, ticketStartLevel+99), WHALE_BUNDLE_TYPE = 3, LAST_LEVEL = newFrozenLevel, DAY = currentMintDay
- `ticketsOwedPacked[lvl][buyer]` -- tickets queued for 100 levels (40/lvl bonus <= level 10, 2/lvl standard)
- `ticketQueue[lvl]` -- buyer pushed if first entry
- `futurePrizePool += totalPrice - nextShare` -- ETH pool allocation
- `nextPrizePool += nextShare` -- ETH pool allocation
- `lootboxEth[index][buyer]`, `lootboxDay[index][buyer]`, `lootboxBaseLevelPacked[index][buyer]`, `lootboxEvScorePacked[index][buyer]`, `lootboxEthBase[index][buyer]`, `lootboxEthTotal`, `lootboxRngPendingEth`, `lootboxIndexQueue[buyer]` -- lootbox entry recording
- `lootboxBoon25Active/15Active/5Active[player]` -- consumed if applicable
- `earlybirdEthIn`, `earlybirdDgnrsPoolStart` (via `_awardEarlybirdDgnrs`) -- earlybird tracking
- DGNRS token transfers from Whale and Affiliate pools (external state on DGNRS contract)

**Callers:**
- DegenerusGame dispatches via delegatecall when player calls whale bundle purchase

**Callees:**
- `_simulatedDayIndex()` -- current game day (inherited from Storage via GameTimeLib)
- `_currentMintDay()` -- mint day calculation
- `_setMintDay()` -- packed day field update
- `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` -- earlybird DGNRS distribution
- `_queueTickets(buyer, lvl, tickets)` -- queues tickets for each of 100 levels
- `affiliate.getReferrer(buyer)` -- external: referral chain lookup (3 levels deep)
- `_rewardWhaleBundleDgnrs(buyer, affiliate, upline, upline2)` -- per-bundle DGNRS distribution
- `_recordLootboxEntry(buyer, lootboxAmount, passLevel, data)` -- lootbox recording
- `dgnrs.poolBalance(Pool)` (indirect via reward functions) -- external: pool balance check
- `dgnrs.transferFromPool(Pool, addr, amount)` (indirect via reward functions) -- external: DGNRS transfer

**ETH Flow:**
- `msg.value` -> validated against `totalPrice`
- `totalPrice - nextShare` -> `futurePrizePool` (70% pre-game, 95% post-game)
- `nextShare` -> `nextPrizePool` (30% pre-game, 5% post-game)
- Lootbox virtual: `totalPrice * whaleLootboxBps / 10000` -> `lootboxEthTotal` (not actual ETH movement, accounting only)

**Pricing Formula Verification:**
- Early price (passLevel <= 4): `WHALE_BUNDLE_EARLY_PRICE = 2.4 ether` -- CORRECT
- Standard price (passLevel > 4): `WHALE_BUNDLE_STANDARD_PRICE = 4 ether` -- CORRECT
- Boon discount: `(STANDARD * (10000 - discountBps)) / 10000`, default 10% if discountBps==0 -- CORRECT
- Total: `unitPrice * quantity` -- CORRECT

**Invariants:**
- `gameOver == false` (pre-condition)
- `quantity >= 1 && quantity <= 100`
- `msg.value == totalPrice` (exact match, no over/underpayment)
- `futurePrizePool + nextPrizePool` increases by exactly `totalPrice`
- Bundle type is always set to 3 (100-level), overwriting any previous 10-level (1) designation
- levelsToAdd is delta-based: overlapping whale bundles do not double-count levels

**NatSpec Accuracy:**
- NatSpec says "Available at any level. Tickets always start at x1." -- ACCURATE. `ticketStartLevel = passLevel <= 4 ? 1 : passLevel` confirms tickets start at level 1 for early purchases.
- NatSpec says "Boosts levelCount by delta" -- ACCURATE. levelsToAdd is capped at deltaFreeze.
- NatSpec says "40 x quantity bonus tickets/lvl for levels passLevel-10" -- ACCURATE. Loop checks `isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL)`.
- NatSpec says "Price: 2.4 ETH at levels 0-3" -- SLIGHTLY IMPRECISE: code uses `passLevel <= 4` which is `level + 1 <= 4`, meaning `level <= 3`, so levels 0-3 is correct. ACCURATE.
- NatSpec says "Pre-game (level 0): 30% next pool, 70% future pool" -- ACCURATE. Code: `level == 0 -> nextShare = totalPrice * 3000 / 10000`.
- NatSpec says "Post-game (level > 0): 5% next pool, 95% future pool" -- ACCURATE.

**Gas Flags:**
- `_rewardWhaleBundleDgnrs` is called `quantity` times in a loop (line 282-285). Each call reads `dgnrs.poolBalance(Whale)` and `dgnrs.poolBalance(Affiliate)` externally. For quantity=100, this is 200 external calls minimum. Gas-expensive but functionally correct -- the pool balance changes after each transfer so re-reading is necessary for accurate proportional distribution.
- The 100-level ticket loop (line 265-270) writes `ticketsOwedPacked` 100 times and may push to `ticketQueue` up to 100 times. Gas-expensive but unavoidable for per-level ticket tracking.

**Verdict:** CORRECT

---

### `purchaseLazyPass(address buyer)` [external] + `_purchaseLazyPass` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseLazyPass(address buyer) external payable` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of the pass |
| **Returns** | none |

**State Reads:**
- `gameOver` -- revert guard
- `level` -- current game level for eligibility and pricing
- `lazyPassBoonDiscountBps[buyer]` -- boon discount tier
- `lazyPassBoonDay[buyer]` -- boon timestamp for expiry check
- `deityLazyPassBoonDay[buyer]` -- deity-granted lazy pass boon (same-day only)
- `deityPassCount[buyer]` -- deity pass holders cannot buy lazy pass
- `mintPacked_[buyer]` -- unpacks frozenUntilLevel for renewal eligibility
- `lootboxPresaleActive` -- lootbox percentage selection
- All reads from `_activate10LevelPass`: mintPacked_ (re-read), ticketsOwedPacked, ticketQueue
- All reads from `_recordLootboxEntry` (same as whale bundle)
- All reads from `_awardEarlybirdDgnrs` (same as whale bundle)

**State Writes:**
- `lazyPassBoonDay[buyer]` -- cleared (on invalid boon check or after use)
- `lazyPassBoonDiscountBps[buyer]` -- cleared (on invalid boon check or after use)
- `deityLazyPassBoonDay[buyer]` -- cleared (on invalid boon check or after use)
- `mintPacked_[buyer]` -- updated via `_activate10LevelPass`: LEVEL_COUNT += levelsToAdd (capped by delta), FROZEN_UNTIL_LEVEL = max(old, startLevel+9), WHALE_BUNDLE_TYPE = 1 (if not already higher), LAST_LEVEL = max(old, newFrozen), DAY = currentMintDay
- `ticketsOwedPacked[lvl][buyer]` -- 4 tickets per level for 10 levels, plus bonusTickets at startLevel
- `ticketQueue[lvl]` -- buyer pushed if first entry
- `futurePrizePool += futureShare` -- 10% of totalPrice
- `nextPrizePool += nextShare` -- 90% of totalPrice
- All writes from `_recordLootboxEntry` (same as whale bundle)
- All writes from `_awardEarlybirdDgnrs` (same as whale bundle)

**Callers:**
- DegenerusGame dispatches via delegatecall for lazy pass purchase

**Callees:**
- `_simulatedDayIndex()` -- boon expiry check
- `_lazyPassCost(startLevel)` -- sum of 10 level prices
- `PriceLookupLib.priceForLevel(startLevel)` -- single level price (for bonus ticket calc)
- `_awardEarlybirdDgnrs(buyer, benefitValue, startLevel)` -- earlybird DGNRS
- `_activate10LevelPass(buyer, startLevel, LAZY_PASS_TICKETS_PER_LEVEL=4)` -- pass activation + ticket queuing
- `_queueTickets(buyer, startLevel, bonusTickets)` -- bonus tickets from flat-price overpayment
- `_recordLootboxEntry(buyer, lootboxAmount, currentLevel+1, mintPacked_[buyer])` -- lootbox recording

**ETH Flow:**
- `msg.value` -> validated against `totalPrice`
- `totalPrice * LAZY_PASS_TO_FUTURE_BPS / 10000` (10%) -> `futurePrizePool`
- `totalPrice - futureShare` (90%) -> `nextPrizePool`
- Lootbox virtual: `benefitValue * lootboxBps / 10000` -> `lootboxEthTotal`

**Note on Pool Splits:** Lazy pass uses a DIFFERENT split from whale/deity. It is 10% future / 90% next at ALL levels (not the 70/30 pre-game or 95/5 post-game split). This is a deliberate design choice documented by the constant `LAZY_PASS_TO_FUTURE_BPS = 1000`.

**Pricing Formula Verification:**
- Levels 0-2: `benefitValue = 0.24 ether` (flat). `baseCost = _lazyPassCost(startLevel)` sums 10 level prices. `balance = 0.24 ether - baseCost` converts to bonus tickets. At level 0, startLevel=1: prices are 0.01*4 + 0.02*5 + 0.04 = 0.18 ETH, balance = 0.06 ETH -> bonus tickets = (0.06 * 4) / 0.01 = 24. CORRECT.
- With boon at levels 0-2: `totalPrice = (0.24 ether * (10000 - boonDiscountBps)) / 10000`. Player pays less but gets same benefit value. CORRECT.
- Levels 3+: `benefitValue = baseCost = _lazyPassCost(startLevel)`. With boon: `totalPrice = (baseCost * (10000 - boonDiscountBps)) / 10000`. CORRECT.
- Default boon discount: 10% (1000 BPS) if boonDiscountBps is 0 but boon is valid. CORRECT.

**Eligibility Logic:**
- Level must be 0, 1, 2, or end in 9 (x9 pattern: 9, 19, 29...), OR have valid boon
- Cannot have deity pass (`deityPassCount[buyer] != 0` reverts)
- Must have <=7 levels remaining on freeze (`frozenUntilLevel <= currentLevel + 7`)

**Boon Expiry Logic:**
- Standard lootbox boon: `currentDay <= boonDay + 4` (4-day window)
- Deity-granted boon: same-day only (`deityDay != 0 && deityDay != currentDay` -> invalidate)
- If boonDay is set but no deityDay and no valid standard boon, fields are cleared

**NatSpec Accuracy:**
- NatSpec says "Available at levels 0-2 or x9 (9, 19, 29...), or with a valid lazy pass boon" -- ACCURATE. Code: `currentLevel > 2 && currentLevel % 10 != 9 && !hasValidBoon -> revert`.
- NatSpec says "Can renew when 7 or fewer levels remain on current pass freeze" -- SLIGHTLY IMPRECISE: code checks `frozenUntilLevel > currentLevel + 7 -> revert`, meaning it reverts if more than 7 levels remain. So renewal is allowed when `frozenUntilLevel <= currentLevel + 7`, i.e., 7 OR FEWER remain. If frozenUntilLevel == currentLevel + 8 it reverts (8 levels remain). NatSpec is ACCURATE on the boundary.
- NatSpec says "Price: flat 0.24 ETH at levels 0-2" -- ACCURATE.
- NatSpec says "sum of per-level ticket prices across the 10-level window at levels 3+" -- ACCURATE.

**Gas Flags:**
- At levels 0-2, `PriceLookupLib.priceForLevel(startLevel)` is called separately in addition to `_lazyPassCost` which also loops. The separate call is for computing bonus tickets and uses just the first level's price, not redundant with the sum loop.
- `_activate10LevelPass` re-reads `mintPacked_[buyer]` even though the caller already has it cached. This is a minor gas inefficiency but the storage slot may have been modified by `_awardEarlybirdDgnrs` in between, so the re-read is safe.

**Verdict:** CORRECT

---

### `purchaseDeityPass(address buyer, uint8 symbolId)` [external] + `_purchaseDeityPass` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseDeityPass(address buyer, uint8 symbolId) external payable` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (payable) |
| **Parameters** | `buyer` (address): recipient of the pass; `symbolId` (uint8): symbol to claim (0-31) |
| **Returns** | none |

**State Reads:**
- `gameOver` -- revert guard
- `deityBySymbol[symbolId]` -- check symbol availability
- `deityPassCount[buyer]` -- check buyer doesn't already own one
- `deityPassOwners.length` -- k = number of passes sold so far (for pricing)
- `deityPassBoonTier[buyer]` -- discount boon tier (1=10%, 2=25%, 3=50%)
- `deityDeityPassBoonDay[buyer]` -- deity-granted boon expiry (1-day)
- `deityPassBoonDay[buyer]` -- lootbox-rolled boon expiry (4-day)
- `level` -- for passLevel and pool split logic
- `mintPacked_[buyer]` (via `_recordLootboxEntry`) -- lootbox recording
- `lootboxPresaleActive` -- lootbox percentage
- All reads from `_awardEarlybirdDgnrs`, `_rewardDeityPassDgnrs`, `_recordLootboxEntry` (same as above)
- `affiliate.getReferrer(buyer/affiliate/upline)` -- referral chain
- `dgnrs.poolBalance(Whale)`, `dgnrs.poolBalance(Affiliate)` -- DGNRS reserves

**State Writes:**
- `deityPassBoonTier[buyer]` -- set to 0 (consumed regardless of expiry)
- `deityPassBoonDay[buyer]` -- set to 0
- `deityDeityPassBoonDay[buyer]` -- set to 0
- `deityPassPaidTotal[buyer] += totalPrice` -- tracking total ETH paid
- `deityPassCount[buyer] = 1` -- mark buyer as deity pass holder
- `deityPassPurchasedCount[buyer] += 1` -- increment purchase count
- `deityPassOwners.push(buyer)` -- append to owners array
- `deityPassSymbol[buyer] = symbolId` -- bind symbol to buyer
- `deityBySymbol[symbolId] = buyer` -- bind buyer to symbol
- `nextPrizePool += nextShare` -- 30% pre-game, 5% post-game
- `futurePrizePool += totalPrice - nextShare` -- 70% pre-game, 95% post-game
- All writes from `_recordLootboxEntry` (same as above)
- All writes from `_awardEarlybirdDgnrs` (same as above)
- DGNRS transfers from Whale and Affiliate pools (external state on DGNRS contract)
- `ticketsOwedPacked[lvl][buyer]`, `ticketQueue[lvl]` -- 100 levels of tickets
- External: `IDegenerusDeityPassMint(DEITY_PASS).mint(buyer, symbolId)` -- ERC721 mint

**Callers:**
- DegenerusGame dispatches via delegatecall for deity pass purchase

**Callees:**
- `_simulatedDayIndex()` -- boon expiry check
- `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` -- earlybird DGNRS
- `IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId)` -- external: ERC721 mint
- `affiliate.getReferrer(buyer)` -- external: referral chain (3 levels deep)
- `_rewardDeityPassDgnrs(buyer, affiliateAddr, upline, upline2)` -- DGNRS rewards
- `_queueTickets(buyer, lvl, tickets)` -- 100 levels of tickets
- `_recordLootboxEntry(buyer, lootboxAmount, passLevel, mintPacked_[buyer])` -- lootbox recording

**ETH Flow:**
- `msg.value` -> validated against `totalPrice`
- `nextShare` -> `nextPrizePool` (30% pre-game level 0, 5% post-game)
- `totalPrice - nextShare` -> `futurePrizePool` (70% pre-game, 95% post-game)
- Lootbox virtual: `totalPrice * deityLootboxBps / 10000` -> `lootboxEthTotal`

**Pricing Formula Verification:**
- Base price: `DEITY_PASS_BASE + (k * (k+1) * 1 ether) / 2` where k = `deityPassOwners.length`
- This is `24 + T(k)` where `T(k) = k*(k+1)/2` is the k-th triangular number
- Pass 0 (k=0): 24 + 0 = 24 ETH -- CORRECT
- Pass 1 (k=1): 24 + 1 = 25 ETH -- CORRECT
- Pass 31 (k=31): 24 + 31*32/2 = 24 + 496 = 520 ETH -- CORRECT (matches NatSpec "last 32nd costs 520 ETH")
- Boon tiers: tier 1 = 1000 BPS (10%), tier 2 = 2500 BPS (25%), tier 3 = 5000 BPS (50%) -- CORRECT
- Boon expiry: lootbox-rolled = `stampDay + DEITY_PASS_BOON_EXPIRY_DAYS (4)`, deity-granted = same day only (`deityDay != currentDay -> expired`). Boon consumed regardless of expiry. CORRECT.

**Ticket Queuing Logic:**
- `ticketStartLevel = passLevel <= 4 ? 1 : uint24(((passLevel + 1) / 50) * 50 + 1)`
- For early levels (passLevel <= 4): starts at level 1, covers 1-100
- For later levels: rounds down to nearest x50+1 boundary. E.g., passLevel=5 -> (6/50)*50+1 = 1; passLevel=50 -> (51/50)*50+1 = 51; passLevel=99 -> (100/50)*50+1 = 51; passLevel=100 -> (101/50)*50+1 = 101
- Tickets: 40/lvl bonus for levels between passLevel and level 10, 2/lvl standard otherwise (same rates as whale bundle but without quantity multiplier)

**Invariants:**
- `gameOver == false`
- `symbolId < 32`
- `deityBySymbol[symbolId] == address(0)` (symbol not taken)
- `deityPassCount[buyer] == 0` (one per player)
- `msg.value == totalPrice` (exact match)
- `futurePrizePool + nextPrizePool` increases by exactly `totalPrice`
- `deityPassOwners.length` increments by 1
- Maximum 32 deity passes total (bounded by symbolId < 32 and each symbol can only be taken once)

**NatSpec Accuracy:**
- NatSpec says "One per player, up to 32 total (one per symbol)" -- ACCURATE. `deityPassCount[buyer] != 0 -> revert` and `symbolId >= 32 -> revert`.
- NatSpec says "Price: 24 + T(n) ETH where n = passes sold so far" -- ACCURATE.
- NatSpec says "First pass costs 24 ETH, last (32nd) costs 520 ETH" -- ACCURATE (k=0 -> 24, k=31 -> 520).
- NatSpec says "Pre-game (level 0): 30% next pool, 70% future pool" -- ACCURATE.
- NatSpec says "Buyer chooses from available symbols (0-31)" -- ACCURATE. The 4 quadrants (Crypto, Zodiac, Cards, Dice with 8 symbols each) is cosmetic labeling, code just checks `symbolId < 32`.

**Gas Flags:**
- `_queueTickets` is called 100 times in a loop (line 523-528), each writing `ticketsOwedPacked`. Similar cost profile to whale bundle but without quantity multiplier (each call queues a fixed 40 or 2 tickets).
- `deityPassPurchasedCount[buyer] += 1` at line 501: this counter survives deity pass transfers (transferred to new owner), tracking total purchases ever made through this ownership lineage.

**Verdict:** CORRECT

---

### `handleDeityPassTransfer(address from, address to)` [external] + `_handleDeityPassTransfer` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function handleDeityPassTransfer(address from, address to) external` |
| **Visibility** | external (wrapper) / private (implementation) |
| **Mutability** | state-changing (not payable) |
| **Parameters** | `from` (address): current deity pass holder; `to` (address): receiving address |
| **Returns** | none |

**State Reads:**
- `level` -- must be > 0 (no pre-game transfers)
- `deityPassCount[from]` -- must be > 0 (sender must own pass)
- `deityPassCount[to]` -- must be 0 (receiver must not own pass)
- `price` -- current game price for BURNIE burn calculation
- `deityPassSymbol[from]` -- symbol ID to transfer
- `deityPassOwners` (full array) -- linear scan to find and replace sender
- `deityPassPurchasedCount[from]` -- transferred to receiver
- `deityPassPaidTotal[from]` -- transferred to receiver
- `mintPacked_[from]` (via `_nukePassHolderStats`) -- sender's packed mint data

**State Writes:**
- External: `IDegenerusCoin(COIN).burnCoin(from, burnAmount)` -- burns 5 ETH worth of BURNIE from sender
- `deityBySymbol[symbolId] = to` -- rebind symbol to receiver
- `deityPassSymbol[to] = symbolId` -- assign symbol to receiver
- `deityPassSymbol[from]` -- deleted
- `deityPassCount[to] = 1` -- receiver now has pass
- `deityPassCount[from] = 0` -- sender no longer has pass
- `deityPassPurchasedCount[to] = deityPassPurchasedCount[from]` -- transfer purchase history
- `deityPassPurchasedCount[from] = 0` -- clear sender's history
- `deityPassPaidTotal[to] = deityPassPaidTotal[from]` -- transfer payment history
- `deityPassPaidTotal[from] = 0` -- clear sender's payment history
- `deityPassOwners[i] = to` -- replace sender with receiver in owners array
- `mintPacked_[from]` (via `_nukePassHolderStats`) -- zeros LEVEL_COUNT, LEVEL_STREAK, LAST_LEVEL, MINT_STREAK_LAST_COMPLETED
- External: `IDegenerusQuestsReset(QUESTS).resetQuestStreak(from)` -- resets quest streak

**Callers:**
- DegenerusGame's `onDeityPassTransfer` callback (triggered by ERC721 transfer event on DeityPass contract)

**Callees:**
- `IDegenerusCoin(ContractAddresses.COIN).burnCoin(from, burnAmount)` -- external: burns BURNIE from sender
- `_nukePassHolderStats(from)` -- zeros sender's mint stats and quest streak
- `IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(from)` -- external: resets quest streak

**ETH Flow:**
- No direct ETH movement. The BURNIE burn is a token operation, not ETH.
- `burnAmount = (DEITY_TRANSFER_ETH_COST * PRICE_COIN_UNIT) / price`
- At default price 0.01 ETH: `(5 ether * 1000 ether) / 0.01 ether = 500,000 ether` BURNIE tokens burned
- The burn cost scales inversely with price: higher price = fewer BURNIE needed

**Invariants:**
- `level > 0` (transfers only allowed after game starts)
- `deityPassCount[from] > 0` (sender must own pass)
- `deityPassCount[to] == 0` (receiver must not already own pass)
- After transfer: `deityPassCount[from] == 0 && deityPassCount[to] == 1`
- After transfer: `deityBySymbol[symbolId] == to`
- deityPassOwners array length unchanged (replacement, not push/pop)
- Sender's mint stats are zeroed (punishment for transfer)
- Sender's quest streak is reset (punishment for transfer)

**NatSpec Accuracy:**
- NatSpec says "Burns 5 ETH worth of BURNIE from sender" -- ACCURATE. `DEITY_TRANSFER_ETH_COST = 5 ether`, formula converts to BURNIE equivalent.
- NatSpec says "Nukes sender's mint stats and quest streak" -- ACCURATE. `_nukePassHolderStats` zeros 4 packed fields + calls `resetQuestStreak`.
- NatSpec says "Called via delegatecall from game's onDeityPassTransfer" -- ACCURATE.

**Gas Flags:**
- Linear scan of `deityPassOwners` array (line 584-590) to find `from`. Max 32 entries (one per symbol), so O(32) worst case. Acceptable for a max-32 array.
- The `burnCoin` external call could revert if sender lacks sufficient BURNIE balance, which would revert the entire transfer. This is intentional -- the burn is a mandatory cost.

**Edge Cases:**
- If `from == to`: Would pass all checks (deityPassCount[from] > 0, deityPassCount[to] == 0 only if from != to). Since `deityPassCount[to] != 0` check uses `to` and the sender has count 1, this would revert at `deityPassCount[to] != 0`. CORRECT -- self-transfer is prevented.
- The function is non-payable, so no ETH can be accidentally sent.

**Verdict:** CORRECT

---

## Internal/Private Helper Functions

### `_lazyPassCost(uint24 startLevel)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _lazyPassCost(uint24 startLevel) private pure returns (uint256 total)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `startLevel` (uint24): first level of the 10-level window |
| **Returns** | `total` (uint256): sum of per-level ticket prices in wei |

**State Reads:** None (pure function)
**State Writes:** None (pure function)

**Callers:**
- `_purchaseLazyPass` -- computes base cost for 10-level lazy pass

**Callees:**
- `PriceLookupLib.priceForLevel(startLevel + i)` -- library call for each of 10 levels

**ETH Flow:** None (computation only)

**Invariants:**
- Always sums exactly `LAZY_PASS_LEVELS (10)` prices
- Return value is deterministic for a given startLevel
- Loop uses `unchecked { ++i }` safely since i < 10 cannot overflow uint24

**NatSpec Accuracy:**
- NatSpec says "Cost equals the sum of per-level ticket prices (4 tickets per level)" -- SLIGHTLY MISLEADING: the function sums prices-per-level (each being the price of ONE ticket at that level), not 4x. The "4 tickets per level" note describes how many tickets the pass grants, not the cost multiplication. The sum represents the cost of buying 1 ticket at each of 10 levels. ACCURATE in computation, slightly confusing in documentation.

**Gas Flags:** None. Simple 10-iteration loop with pure library calls.

**Verification:** At startLevel=1 (level 0 purchase):
- Levels 1-4: 0.01 ETH each = 0.04 ETH
- Levels 5-9: 0.02 ETH each = 0.10 ETH
- Level 10: 0.04 ETH
- Total: 0.18 ETH -- matches expected value

At startLevel=10 (level 9 purchase):
- Level 10: 0.04 ETH
- Levels 11-19: 0.04 ETH each = 0.36 ETH
- Total: 0.40 ETH

**Verdict:** CORRECT

---

### `_rewardWhaleBundleDgnrs(address buyer, address affiliateAddr, address upline, address upline2)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rewardWhaleBundleDgnrs(address buyer, address affiliateAddr, address upline, address upline2) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): bundle purchaser; `affiliateAddr` (address): direct referrer; `upline` (address): 2nd-tier referrer; `upline2` (address): 3rd-tier referrer |
| **Returns** | none |

**State Reads:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Whale)` -- external: whale pool DGNRS balance
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)` -- external: affiliate pool DGNRS balance

**State Writes:**
- `dgnrs.transferFromPool(Pool.Whale, buyer, minterShare)` -- external: 1% of whale pool to buyer
- `dgnrs.transferFromPool(Pool.Affiliate, affiliateAddr, affiliateShare)` -- external: 0.1% of affiliate pool to direct referrer
- `dgnrs.transferFromPool(Pool.Affiliate, upline, uplineShare)` -- external: 0.02% of affiliate pool to upline
- `dgnrs.transferFromPool(Pool.Affiliate, upline2, upline2Share)` -- external: 0.01% (uplineShare/2) of affiliate pool to upline2

**Callers:**
- `_purchaseWhaleBundle` -- called once per bundle in quantity loop

**Callees:**
- `dgnrs.poolBalance(Pool)` -- external: 2 calls per invocation
- `dgnrs.transferFromPool(Pool, addr, amount)` -- external: up to 4 calls per invocation

**ETH Flow:** None (DGNRS token transfers only, no ETH movement)

**DGNRS Distribution:**
- Buyer: `whaleReserve * 10_000 / 1_000_000` = 1% of whale pool
- Direct affiliate: `affiliateReserve * 1_000 / 1_000_000` = 0.1% of affiliate pool
- Upline: `affiliateReserve * 200 / 1_000_000` = 0.02% of affiliate pool
- Upline2: `uplineShare / 2` = 0.01% of affiliate pool

**Invariants:**
- All transfers are proportional to current pool balance (re-read each call)
- If whale pool is 0, no buyer reward
- If affiliate pool is 0, early return (no affiliate rewards)
- upline2Share is half of uplineShare (derived, not independently calculated from pool)
- Each address checked for non-zero before transfer
- Amount checked for non-zero before transfer

**NatSpec Accuracy:**
- NatSpec says "0.1% of affiliate pool" for direct affiliate -- ACCURATE (1_000 / 1_000_000 = 0.1%)
- NatSpec says "0.02% of affiliate pool" for upline -- ACCURATE (200 / 1_000_000 = 0.02%)
- NatSpec says "0.01% of affiliate pool" for upline2 -- ACCURATE (uplineShare/2, where uplineShare is 0.02%, so 0.01%)

**Gas Flags:**
- Called once per `quantity` in a loop. For quantity=100, this function executes 100 times with up to 600 external calls total. This is gas-heavy but functionally required since each transfer changes the pool balance.
- The `upline2Share = uplineShare / 2` pattern calculates from the same `affiliateReserve` read, meaning upline2 gets half the upline amount (0.01% vs 0.02%), not a fresh pool proportion. This is intentional as upline2 is a derived share.

**Verdict:** CORRECT

---

### `_rewardDeityPassDgnrs(address buyer, address affiliateAddr, address upline, address upline2)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rewardDeityPassDgnrs(address buyer, address affiliateAddr, address upline, address upline2) private returns (uint96 buyerDgnrs)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): deity pass purchaser; `affiliateAddr` (address): direct referrer; `upline` (address): 2nd-tier referrer; `upline2` (address): 3rd-tier referrer |
| **Returns** | `buyerDgnrs` (uint96): DGNRS amount transferred to buyer (capped at uint96 max) |

**State Reads:**
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Whale)` -- external: whale pool balance
- `dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate)` -- external: affiliate pool balance

**State Writes:**
- `dgnrs.transferFromPool(Pool.Whale, buyer, totalReward)` -- external: 5% of whale pool to buyer
- `dgnrs.transferFromPool(Pool.Affiliate, affiliateAddr, affiliateShare)` -- external: 0.5% of affiliate pool
- `dgnrs.transferFromPool(Pool.Affiliate, upline, uplineShare)` -- external: 0.1% of affiliate pool
- `dgnrs.transferFromPool(Pool.Affiliate, upline2, upline2Share)` -- external: 0.05% of affiliate pool

**Callers:**
- `_purchaseDeityPass` -- called once per deity pass purchase

**Callees:**
- `dgnrs.poolBalance(Pool)` -- external: 2 calls
- `dgnrs.transferFromPool(Pool, addr, amount)` -- external: up to 4 calls

**ETH Flow:** None (DGNRS token transfers only)

**DGNRS Distribution (deity pass -- 5x whale bundle rates):**
- Buyer: `whaleReserve * 500 / 10_000` = 5% of whale pool (vs 1% for whale bundle)
- Direct affiliate: `affiliateReserve * 5_000 / 1_000_000` = 0.5% of affiliate pool (vs 0.1%)
- Upline: `affiliateReserve * 1_000 / 1_000_000` = 0.1% of affiliate pool (vs 0.02%)
- Upline2: `uplineShare / 2` = 0.05% of affiliate pool (vs 0.01%)

**Invariants:**
- Buyer DGNRS return value capped at `type(uint96).max` to prevent overflow in callers
- `transferFromPool` returns actual transferred amount (may be less than requested if pool depleted)
- Same null-check pattern as whale bundle rewards

**NatSpec Accuracy:**
- NatSpec says "5% of whale pool" for buyer -- ACCURATE. Note: constant uses BPS (500/10000) not PPM, unlike whale bundle which uses PPM (10000/1000000). Both resolve to the correct percentages.
- NatSpec says "0.5% of affiliate pool" -- ACCURATE (5_000 / 1_000_000 = 0.5%)
- NatSpec says "0.1% of affiliate pool" for upline -- ACCURATE (1_000 / 1_000_000 = 0.1%)
- NatSpec says "0.05% of affiliate pool" for upline2 -- ACCURATE (uplineShare/2)

**Gas Flags:**
- Buyer reward uses BPS scale (DEITY_WHALE_POOL_BPS = 500, divided by 10_000) while affiliate rewards use PPM scale (divided by 1_000_000). Both are correct but use different denomination conventions. Not a bug, just inconsistent constant naming.
- The `buyerDgnrs` return value is used nowhere in the calling code (`_purchaseDeityPass` does not capture the return). The return exists for potential future use. No gas impact beyond the comparison.

**Verdict:** CORRECT

---

### `_recordLootboxEntry(address buyer, uint256 lootboxAmount, uint24 purchaseLevel, uint256 cachedPacked)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordLootboxEntry(address buyer, uint256 lootboxAmount, uint24 purchaseLevel, uint256 cachedPacked) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `buyer` (address): lootbox recipient; `lootboxAmount` (uint256): base ETH amount for lootbox; `purchaseLevel` (uint24): level at time of purchase; `cachedPacked` (uint256): caller's cached mintPacked_ |
| **Returns** | none |

**State Reads:**
- `lootboxRngIndex` -- current global lootbox RNG index
- `lootboxEth[index][buyer]` -- existing lootbox amount for this index
- `lootboxDay[index][buyer]` -- day of existing lootbox entry
- `lootboxEthBase[index][buyer]` -- unboosted base lootbox amount
- `mintPacked_[buyer]` (via `_recordLootboxMintDay`) -- mint day tracking
- `lootboxBoon25Active/15Active/5Active[buyer]`, `lootboxBoon25Day/15Day/5Day[buyer]` (via `_applyLootboxBoostOnPurchase`) -- boost state

**State Writes:**
- `mintPacked_[buyer]` (via `_recordLootboxMintDay`) -- update mint day field
- `lootboxDay[index][buyer] = dayIndex` -- set day (if new entry)
- `lootboxBaseLevelPacked[index][buyer]` -- set base level (level+2, if new entry)
- `lootboxEvScorePacked[index][buyer]` -- set activity score (if new entry)
- `lootboxIndexQueue[buyer].push(index)` -- push index to queue (if new entry)
- `lootboxBoon25Active/15Active/5Active[buyer]` -- consumed if boost applied (via `_applyLootboxBoostOnPurchase`)
- `lootboxEthBase[index][buyer]` -- incremented by lootboxAmount (unboosted)
- `lootboxEth[index][buyer]` -- set to `(purchaseLevel << 232) | newAmount` (boosted amount packed with level)
- `lootboxEthTotal += lootboxAmount` -- global lootbox ETH tracking (unboosted)
- `lootboxRngPendingEth += lootboxAmount` (via `_maybeRequestLootboxRng`) -- pending RNG ETH

**Callers:**
- `_purchaseWhaleBundle` -- after pool splits
- `_purchaseLazyPass` -- after pool splits
- `_purchaseDeityPass` -- after pool splits

**Callees:**
- `_recordLootboxMintDay(buyer, uint32(dayIndex), cachedPacked)` -- mint day update
- `_simulatedDayIndex()` -- current day
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` -- external self-call for EV score (executes on game contract since this is delegatecall context)
- `_applyLootboxBoostOnPurchase(buyer, dayIndex, lootboxAmount)` -- boost application
- `_maybeRequestLootboxRng(lootboxAmount)` -- pending ETH accumulation

**ETH Flow:**
- No actual ETH movement. Records virtual lootbox amounts for later resolution.
- `lootboxEthTotal` tracks cumulative virtual lootbox ETH across all purchases.
- `lootboxRngPendingEth` tracks pending ETH for next RNG request threshold.

**Invariants:**
- If entry exists for this index+buyer: must be same day (`storedDay == dayIndex`), else reverts
- If new entry: assigns day, base level (level+2), activity score, pushes to index queue
- `lootboxEthBase` stores unboosted amount; `lootboxEth` stores boosted amount packed with level
- `lootboxEthTotal` accumulates unboosted amounts only
- `lootboxRngPendingEth` accumulates unboosted amounts for RNG threshold

**NatSpec Accuracy:** No NatSpec on this function. The inline comments adequately describe behavior.

**Gas Flags:**
- `IDegenerusGame(address(this)).playerActivityScore(buyer)` is an external self-call. Since this runs in delegatecall context, `address(this)` is the game contract, so this calls back into the game. This is a gas-expensive pattern for what could theoretically be an internal read, but the function likely lives on the game contract itself (not the module), making the external call necessary.
- `existingBase` initialization (line 764-767): if existingAmount != 0 but existingBase == 0, sets existingBase = existingAmount. This handles a migration case where older entries didn't track base separately.

**Verdict:** CORRECT

---

### `_maybeRequestLootboxRng(uint256 lootboxAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeRequestLootboxRng(uint256 lootboxAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lootboxAmount` (uint256): ETH amount to add to pending total |
| **Returns** | none |

**State Reads:** None (only writes)
**State Writes:**
- `lootboxRngPendingEth += lootboxAmount` -- accumulates pending lootbox ETH

**Callers:**
- `_recordLootboxEntry` -- after recording each lootbox entry

**Callees:** None

**ETH Flow:** None (accounting only)

**Invariants:**
- Simple accumulation. The actual RNG request threshold check and VRF call happen elsewhere (in AdvanceModule when `requestLootboxRng` is called).

**NatSpec Accuracy:**
- NatSpec says "Accumulate lootbox ETH for pending RNG request" -- ACCURATE but function name `_maybeRequestLootboxRng` implies conditional logic (maybe request). The function always accumulates. The name is slightly misleading since it never actually requests RNG. Previously this function likely contained threshold-checking logic that was refactored out.

**Gas Flags:** None. Single SLOAD + SSTORE.

**Verdict:** CORRECT

---

### `_applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyLootboxBoostOnPurchase(address player, uint48 day, uint256 amount) private returns (uint256 boostedAmount)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose boost to check; `day` (uint48): current day for event; `amount` (uint256): base lootbox amount |
| **Returns** | `boostedAmount` (uint256): amount after applying boost (>= amount) |

**State Reads:**
- `lootboxBoon25Active[player]` -- 25% boost flag
- `lootboxBoon25Day[player]` -- 25% boost timestamp
- `lootboxBoon15Active[player]` -- 15% boost flag
- `lootboxBoon15Day[player]` -- 15% boost timestamp
- `lootboxBoon5Active[player]` -- 5% boost flag
- `lootboxBoon5Day[player]` -- 5% boost timestamp

**State Writes:**
- `lootboxBoon25Active[player] = false` -- consumed (if used or expired)
- `lootboxBoon15Active[player] = false` -- consumed (if used or expired)
- `lootboxBoon5Active[player] = false` -- consumed (if used or expired)

**Callers:**
- `_recordLootboxEntry` -- to apply boost before recording final amount

**Callees:** None (emits event `LootBoxBoostConsumed`)

**ETH Flow:** None (computation only, modifies virtual lootbox amount)

**Boost Logic:**
- Priority order: 25% > 15% > 5% (checks highest first)
- Each boost: `cappedAmount = min(amount, 10 ETH)`, `boost = cappedAmount * boostBps / 10000`
- The boost applies to the capped amount only, not the full amount if > 10 ETH
- Example: 15 ETH with 25% boost -> boost = 10 * 0.25 = 2.5 ETH, boostedAmount = 17.5 ETH
- Only ONE boost consumed per call (first valid one found)
- Expiry: `currentDay > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS (2)` -- expired boosts are deactivated but not applied
- Expired boosts: flag set to false but no event emitted

**Invariants:**
- `boostedAmount >= amount` (boost only adds, never subtracts)
- At most one boost consumed per purchase
- Boost cap ensures maximum additional value is 2.5 ETH (10 ETH * 25%)
- Day parameter is used for event emission only, not for expiry calculation (uses `_simulatedDayIndex()`)

**NatSpec Accuracy:**
- NatSpec says "Checks boosts in order: 25% > 15% > 5%" -- ACCURATE
- NatSpec says "Consumes the first valid boost found" -- ACCURATE
- NatSpec says "Boost is capped at LOOTBOX_BOOST_MAX_VALUE (10 ETH)" -- ACCURATE
- NatSpec says "expires after 2 game days" -- ACCURATE (LOOTBOX_BOOST_EXPIRY_DAYS = 2)

**Gas Flags:**
- `_simulatedDayIndex()` is called once at the top (line 796) but may also be called multiple times in the nested if-else structure. Actually, `currentDay` is cached at line 796 and reused throughout. Efficient.
- Three separate storage reads for each boost tier (active + day). In the worst case (no active boosts), all 6 slots are read. Minor but unavoidable.

**Verdict:** CORRECT

---

### `_recordLootboxMintDay(address player, uint32 day, uint256 cachedPacked)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _recordLootboxMintDay(address player, uint32 day, uint256 cachedPacked) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `day` (uint32): current day index; `cachedPacked` (uint256): caller's cached mintPacked_ value |
| **Returns** | none |

**State Reads:**
- Uses `cachedPacked` parameter (avoids SLOAD of `mintPacked_[player]`)

**State Writes:**
- `mintPacked_[player]` -- updates DAY field if changed

**Callers:**
- `_recordLootboxEntry` -- to update mint day in packed data

**Callees:** None

**ETH Flow:** None

**Invariants:**
- If `prevDay == day`, no-op (idempotent)
- Only modifies the DAY field (bits 72-103) in mintPacked_, leaves all other fields intact
- Uses bit manipulation: clears DAY field, then ORs new day value

**NatSpec Accuracy:**
- NatSpec says "Record the mint day in player's packed data for lootbox tracking" -- ACCURATE
- NatSpec says "The caller's cached mintPacked_ value to avoid a redundant SLOAD" -- ACCURATE. The caller passes their cached copy to avoid re-reading storage.

**Gas Flags:**
- Accepts cached packed data to skip one SLOAD. Good optimization.
- Still performs one SSTORE if day changed. Unavoidable.

**Verdict:** CORRECT

---

### `_nukePassHolderStats(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _nukePassHolderStats(address player) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose stats to zero |
| **Returns** | none |

**State Reads:**
- `mintPacked_[player]` -- current packed mint data

**State Writes:**
- `mintPacked_[player]` -- zeros 4 fields:
  - LEVEL_COUNT (bits 24-47) -> 0
  - LEVEL_STREAK (bits 48-71) -> 0
  - LAST_LEVEL (bits 0-23) -> 0
  - MINT_STREAK_LAST_COMPLETED (bits 160-183) -> 0
- External: `IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(player)` -- resets quest streak

**Callers:**
- `_handleDeityPassTransfer` -- penalty for transferring deity pass

**Callees:**
- `BitPackingLib.setPacked()` -- 4 calls to zero fields
- `IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(player)` -- external: quest streak reset

**ETH Flow:** None

**Invariants:**
- Only zeros specific stat fields; preserves other packed fields (FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, DAY, LEVEL_UNITS_LEVEL, LEVEL_UNITS)
- Quest streak reset is an external call to the Quests contract, which also runs in the game's delegatecall context (the call originates from the game address)

**NatSpec Accuracy:**
- NatSpec says "Zero mint stats and quest streak" -- ACCURATE. Four packed fields zeroed plus external quest reset.

**Gas Flags:**
- Uses `BitPackingLib.setPacked` four times sequentially on the same `data` variable. Could potentially be optimized with a single bitmask operation, but the current approach is clear and correct.

**Verdict:** CORRECT

---

## Local Interface Declarations

### `IDegenerusQuestsReset` [interface]

```solidity
interface IDegenerusQuestsReset {
    function resetQuestStreak(address player) external;
}
```

Minimal interface declared at end of file (line 882-885). Used only by `_nukePassHolderStats` to reset the deity pass seller's quest streak. Called in delegatecall context (msg.sender is the game contract address).

### `IDegenerusDeityPassMint` [interface]

```solidity
interface IDegenerusDeityPassMint {
    function mint(address to, uint256 tokenId) external;
}
```

Minimal interface declared at end of file (line 888-890). Used only by `_purchaseDeityPass` to mint the ERC721 deity pass token. Called in delegatecall context (msg.sender is the game contract address, which must be authorized as a minter on the DeityPass contract).

---

## Pricing Formula Verification

| Pass Type | Formula | Code Implementation | Verified |
|-----------|---------|---------------------|----------|
| Whale Bundle (early) | 2.4 ETH (levels 0-3) | `WHALE_BUNDLE_EARLY_PRICE = 2.4 ether`, `passLevel <= 4` | YES |
| Whale Bundle (standard) | 4 ETH (levels 4+) | `WHALE_BUNDLE_STANDARD_PRICE = 4 ether` | YES |
| Whale Bundle (boon) | 10/25/50% off standard | `(STANDARD * (10000 - discountBps)) / 10000`, default 10% if discountBps==0 | YES |
| Lazy Pass (early) | 0.24 ETH flat (levels 0-2) | `benefitValue = 0.24 ether` | YES |
| Lazy Pass (standard) | sum of 10 level prices | `_lazyPassCost` loops `PriceLookupLib.priceForLevel` for 10 levels | YES |
| Lazy Pass (boon) | 10% default discount on payment | `(benefitValue or baseCost) * (10000 - boonDiscountBps) / 10000` | YES |
| Deity Pass | 24 + T(n) ETH, T(n)=n*(n+1)/2 | `DEITY_PASS_BASE + (k*(k+1)*1 ether)/2` where k = deityPassOwners.length | YES |
| Deity Pass (boon) | Tier 1=10%, 2=25%, 3=50% off | `(basePrice * (10000 - discountBps)) / 10000` | YES |
| Deity Transfer | 5 ETH worth of BURNIE | `(DEITY_TRANSFER_ETH_COST * PRICE_COIN_UNIT) / price` | YES |

### Spot-Check: Deity Pass Price Sequence

| Pass # (k) | Formula: 24 + k*(k+1)/2 | Price (ETH) |
|-------------|--------------------------|-------------|
| 0 | 24 + 0 | 24 |
| 1 | 24 + 1 | 25 |
| 2 | 24 + 3 | 27 |
| 3 | 24 + 6 | 30 |
| 10 | 24 + 55 | 79 |
| 20 | 24 + 210 | 234 |
| 31 | 24 + 496 | 520 |

Total ETH across all 32 passes: sum(24 + k*(k+1)/2 for k=0..31) = 768 + 2976 = 3744 ETH (before any boon discounts).

### Spot-Check: Lazy Pass Cost at Various Levels

| Level | startLevel | 10-Level Price Sum | Calculation |
|-------|------------|-------------------|-------------|
| 0 | 1 | 0.18 ETH | 4x0.01 + 5x0.02 + 1x0.04 |
| 9 | 10 | 0.40 ETH | 10x0.04 (levels 10-19, all < 30) |
| 29 | 30 | 0.80 ETH | 10x0.08 (levels 30-39, all < 60) |
| 59 | 60 | 1.20 ETH | 10x0.12 (levels 60-69, all < 90) |
| 89 | 90 | 1.60 ETH | 10x0.16 (levels 90-99, all < 100) |
| 99 | 100 | 0.64 ETH | 0.24 + 9x0.04 (milestone + 9 early-cycle) |

## ETH Mutation Path Map

| # | Path | Source | Destination | Trigger | Function |
|---|------|--------|-------------|---------|----------|
| 1 | Whale bundle pre-game | msg.value | futurePrizePool (70%) + nextPrizePool (30%) | purchaseWhaleBundle at level 0 | _purchaseWhaleBundle |
| 2 | Whale bundle post-game | msg.value | futurePrizePool (95%) + nextPrizePool (5%) | purchaseWhaleBundle at level > 0 | _purchaseWhaleBundle |
| 3 | Lazy pass (all levels) | msg.value | futurePrizePool (10%) + nextPrizePool (90%) | purchaseLazyPass | _purchaseLazyPass |
| 4 | Deity pass pre-game | msg.value | futurePrizePool (70%) + nextPrizePool (30%) | purchaseDeityPass at level 0 | _purchaseDeityPass |
| 5 | Deity pass post-game | msg.value | futurePrizePool (95%) + nextPrizePool (5%) | purchaseDeityPass at level > 0 | _purchaseDeityPass |
| 6 | Lootbox recording (whale) | (virtual) | lootboxEthTotal, lootboxRngPendingEth | purchaseWhaleBundle | _recordLootboxEntry |
| 7 | Lootbox recording (lazy) | (virtual) | lootboxEthTotal, lootboxRngPendingEth | purchaseLazyPass | _recordLootboxEntry |
| 8 | Lootbox recording (deity) | (virtual) | lootboxEthTotal, lootboxRngPendingEth | purchaseDeityPass | _recordLootboxEntry |
| 9 | Lootbox boost (all) | (virtual) | lootboxEth[index][buyer] (boosted amount) | Any purchase with active boost | _applyLootboxBoostOnPurchase |
| 10 | DGNRS whale pool | Whale pool | buyer | purchaseWhaleBundle/purchaseDeityPass | _rewardWhaleBundleDgnrs/_rewardDeityPassDgnrs |
| 11 | DGNRS affiliate pool | Affiliate pool | referral chain (3 tiers) | purchaseWhaleBundle/purchaseDeityPass | _rewardWhaleBundleDgnrs/_rewardDeityPassDgnrs |
| 12 | DGNRS earlybird pool | Earlybird pool | buyer | All purchases (early levels) | _awardEarlybirdDgnrs (inherited) |
| 13 | BURNIE burn (transfer) | sender's BURNIE balance | burned | handleDeityPassTransfer | _handleDeityPassTransfer |

**ETH Accounting Integrity:**
- For every payable function (whale, lazy, deity): `futurePrizePool_delta + nextPrizePool_delta == msg.value`. Verified by code analysis -- all splits sum to totalPrice with no remainder.
- Lootbox amounts are virtual (not additional ETH -- they record a fraction of the already-split ETH for later lootbox resolution). `lootboxEthTotal` grows by the unboosted amount.
- No ETH leaves the contract through this module. All ETH stays in pool accounting variables.

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 3 | (1) Whale DGNRS rewards loop O(quantity) with external calls; (2) 100-level ticket queuing loop; (3) _rewardDeityPassDgnrs return value unused |
| CORRECT | 12 | All 4 external + 8 internal functions verified correct |

**Overall Assessment:** All 12 functions (4 external/public + 8 internal/private) are CORRECT. No bugs or security concerns found. Three minor gas observations noted (all functionally necessary). Pricing formulas for all pass types verified against expected values. ETH mutation paths fully traced -- all ETH is properly accounted for within pool variables. NatSpec is accurate across all functions with no material discrepancies.
