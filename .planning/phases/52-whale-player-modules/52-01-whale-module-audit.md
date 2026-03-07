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
