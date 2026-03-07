# DegenerusStonk.sol -- Function-Level Audit

**Contract:** DegenerusStonk
**File:** contracts/DegenerusStonk.sol
**Lines:** 1109
**Solidity:** 0.8.34
**Inherits:** None (standalone ERC-20 implementation)
**Audit date:** 2026-03-07

## Summary

DegenerusStonk (DGNRS) is a standalone ERC-20 token backed by ETH, stETH, WWXRP, and BURNIE reserves. It receives ETH/stETH from game distributions. Its 1 trillion token supply is split into a 20% creator allocation and five reward pools (Whale, Affiliate, Lootbox, Reward, Earlybird). Holders can lock tokens to gain proportional "action rights" at the current game level -- spending ETH or BURNIE on game purchases, degenerette bets, and decimator burns through proxy functions. A BURNIE rebate system rewards ETH purchases with 70% BURNIE value. Burning DGNRS claims a proportional share of all backing assets (ETH first, then stETH, plus proportional BURNIE and WWXRP). The contract also acts as a game participant itself (whale pass, afKing mode, quest streak tracking).

**Key external dependencies:**
- `IDegenerusGamePlayer` (game): level queries, purchase proxying, lootbox, whale pass, degenerette bets, claimable winnings
- `IDegenerusCoinPlayer` (coin): BURNIE balance queries, transfers, decimator burns
- `IBurnieCoinflipPlayer` (coinflip): claimable BURNIE preview/withdrawal
- `IWrappedWrappedXRP` (wwxrp): WWXRP balance/transfer for burn payouts
- `IDegenerusQuestsView` (quests): streak queries for quest contribution rewards
- `IStETH` (steth): stETH balance/transfer

**Storage layout:**
- ERC-20: `totalSupply`, `balanceOf`, `allowance`
- Reserves: `ethReserve` (declared but never written -- see finding)
- Pools: `poolBalances[5]` (Whale=0, Affiliate=1, Lootbox=2, Reward=3, Earlybird=4)
- Lock state: `lockedBalance`, `lockedLevel`, `ethSpentThisLevel`, `burnieSpentThisLevel`

---

## Function Audit

### ERC-20 Core

---

### `approve(address spender, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function approve(address spender, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `spender` (address): address authorized to spend; `amount` (uint256): allowance amount |
| **Returns** | `bool`: always true |

**State Reads:** None
**State Writes:** `allowance[msg.sender][spender] = amount`

**Callers:** External users/contracts
**Callees:** None

**ETH Flow:** No
**Invariants:** Allowance is set unconditionally (no check on balance). Standard ERC-20 approve pattern.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transfer(address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transfer(address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** (via `_transfer`) `balanceOf[from]`, `lockedBalance[from]`, `lockedLevel[from]`
**State Writes:** (via `_transfer`) `balanceOf[from]`, `balanceOf[to]`

**Callers:** External users/contracts
**Callees:** `_transfer(msg.sender, to, amount)`

**ETH Flow:** No
**Invariants:** Transfer amount must not exceed unlocked balance. Zero-address recipient blocked.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferFrom(address from, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFrom(address from, address to, uint256 amount) external returns (bool)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | `bool`: always true |

**State Reads:** `allowance[from][msg.sender]`, (via `_transfer`) `balanceOf[from]`, `lockedBalance[from]`, `lockedLevel[from]`
**State Writes:** `allowance[from][msg.sender]` (decremented if not max), (via `_transfer`) `balanceOf[from]`, `balanceOf[to]`

**Callers:** External users/contracts, COIN contract (trusted bypass)
**Callees:** `_transfer(from, to, amount)`

**ETH Flow:** No
**Invariants:** COIN contract bypasses allowance checks (trusted spender). For other callers, allowance must be sufficient unless max(uint256). Emits Approval with new allowance on decrement.
**NatSpec Accuracy:** Accurate. Correctly documents COIN trust.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_transfer(address from, address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transfer(address from, address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): source; `to` (address): destination; `amount` (uint256): transfer amount |
| **Returns** | None |

**State Reads:** `balanceOf[from]`, `lockedBalance[from]`, `lockedLevel[from]`, `game.level()` (external call)
**State Writes:** `balanceOf[from]` (decremented), `balanceOf[to]` (incremented)

**Callers:** `transfer`, `transferFrom`, `transferFromPool`, `_transferFromPoolInternal`
**Callees:** `game.level()` (only if lockedBalance > 0)

**ETH Flow:** No
**Invariants:** Zero-address `to` blocked. Balance must be sufficient. Locked tokens at the current level cannot be transferred -- only `bal - locked` is transferable. Uses unchecked arithmetic safe because of prior checks.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** External call to `game.level()` only when `lockedBalance[from] > 0` -- good optimization. For pool transfers from `address(this)`, the lock check is harmless (contract won't have locks).
**Verdict:** CORRECT

---

### Access Control

---

### `onlyGame()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyGame()` |
| **Visibility** | (modifier) |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `ContractAddresses.GAME` (compile-time constant)
**State Writes:** None

**Callers:** `receive()`, `depositSteth`, `transferFromPool`, `transferBetweenPools`, `burnForGame`
**Callees:** None

**ETH Flow:** No
**Invariants:** Only the GAME contract can call protected functions.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `onlyHolder()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyHolder()` |
| **Visibility** | (modifier) |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** `balanceOf[msg.sender]`
**State Writes:** None

**Callers:** `gameAdvance`, `gameOpenLootBox`, `gameClaimWhalePass`
**Callees:** None

**ETH Flow:** No
**Invariants:** Caller must have non-zero DGNRS balance.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_requireApproved(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _requireApproved(address player) private view` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player to check approval for |
| **Returns** | None (reverts on failure) |

**State Reads:** None directly (delegates to external call)
**State Writes:** None

**Callers:** `burn`
**Callees:** `game.isOperatorApproved(player, msg.sender)` (external call)

**ETH Flow:** No
**Invariants:** If msg.sender != player, must be an approved operator in the game contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Constructor

---

### `constructor()` [constructor]

| Field | Value |
|-------|-------|
| **Signature** | `constructor()` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | N/A |

**State Reads:** Constants: `INITIAL_SUPPLY`, `CREATOR_BPS`, `BPS_DENOM`, pool BPS constants, `ContractAddresses.CREATOR`, `ContractAddresses.GAME`
**State Writes:** `totalSupply` (via `_mint`), `balanceOf[CREATOR]`, `balanceOf[address(this)]`, `poolBalances[0..4]`

**Callers:** Deployment
**Callees:** `_mint(CREATOR, creatorAmount)`, `_mint(address(this), poolTotal)`, `game.claimWhalePass(address(0))`, `game.setAfKingMode(address(0), true, 10 ether, 0)`

**ETH Flow:** No
**Invariants:**
- Total supply = INITIAL_SUPPLY (1 trillion * 1e18)
- Creator gets 20% (200B tokens)
- Remaining 80% split into 5 pools with BPS-based allocation
- Dust from rounding error added to Lootbox pool
- Pool totals verified: Whale=1143, Affiliate=3428, Lootbox=1143+dust, Reward=1143, Earlybird=1143 -- these sum to 8000 BPS = 80%
- Claims whale pass for DGNRS contract in the game
- Enables afKing mode with 10 ETH take-profit, 0 BURNIE take-profit

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Lock Mechanics

---

### `lockForLevel(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function lockForLevel(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount of DGNRS to lock (additive) |
| **Returns** | None |

**State Reads:** `game.level()` (external), `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `balanceOf[msg.sender]`
**State Writes:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `ethSpentThisLevel[msg.sender]` (reset on auto-unlock), `burnieSpentThisLevel[msg.sender]` (reset on auto-unlock)

**Callers:** External holders
**Callees:** `game.level()`

**ETH Flow:** No
**Invariants:**
- If locked at a different level, auto-unlocks first (resets spend counters, emits Unlocked)
- `amount` must not exceed `balanceOf - currentLocked` (unlocked portion)
- Additive within the same level (can increase lock)
- lockedLevel set to current game level
- Emits Locked with the incremental `amount`, not the total locked

**NatSpec Accuracy:** Accurate. Correctly documents additive behavior and auto-unlock.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `unlock()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function unlock() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `game.level()` (external)
**State Writes:** `lockedBalance[msg.sender] = 0`, `ethSpentThisLevel[msg.sender] = 0`, `burnieSpentThisLevel[msg.sender] = 0`

**Callers:** External holders
**Callees:** `game.level()`

**ETH Flow:** No
**Invariants:**
- Must have non-zero locked balance (reverts NoLockedTokens)
- Level must have changed (reverts LockStillActive if still at locked level)
- Resets all spending counters

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Game Proxy Functions

---

### `gameAdvance()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gameAdvance() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `balanceOf[msg.sender]` (via onlyHolder)
**State Writes:** None directly

**Callers:** External DGNRS holders
**Callees:** `game.advanceGame()`

**ETH Flow:** No
**Invariants:** Caller must hold DGNRS tokens. Does not require locked tokens -- only holder status.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gamePurchase(uint256 ticketQuantity, uint256 lootBoxAmount, MintPaymentKind payKind)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchase(uint256 ticketQuantity, uint256 lootBoxAmount, MintPaymentKind payKind) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `ticketQuantity` (uint256): ticket count; `lootBoxAmount` (uint256): ETH for lootboxes; `payKind` (MintPaymentKind): payment method |
| **Returns** | None |

**State Reads:** `game.mintPrice()`, `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `ethSpentThisLevel[msg.sender]`, `game.level()`, `quests.playerQuestStates(address(this))`, `poolBalances[Pool.Reward]`
**State Writes:** `ethSpentThisLevel[msg.sender]`, `poolBalances[Pool.Reward]` (if quest completed), `balanceOf` (via pool transfer on quest reward)

**Callers:** External DGNRS holders with locked tokens
**Callees:** `game.mintPrice()`, `_checkAndRecordEthSpend`, `quests.playerQuestStates`, `game.purchase{value}`, `_rebateBurnieFromEthValue`, `_transferFromPoolInternal`

**ETH Flow:** msg.value forwarded to game.purchase. BURNIE rebate paid from contract's BURNIE balance.
**Invariants:**
- Requires locked tokens at current level
- Ticket cost = `(priceWei * ticketQuantity) / 400` -- consistent with game's 4*100 scaling
- Total cost (tickets + lootboxes) must not exceed ETH spend limit (10x proportional ETH value of locked tokens)
- Uses `AFFILIATE_CODE_DGNRS` ("DGNRS") for all purchases
- Passes `address(0)` as buyer (resolves to msg.sender in game = DGNRS contract itself)
- BURNIE rebate uses totalCost for DirectEth, msg.value otherwise
- Quest contribution reward: if DGNRS contract's streak increments, caller gets 0.05% of Reward pool

**NatSpec Accuracy:** Mostly accurate. NatSpec says "on behalf of DGNRS" which is correct -- the purchase is for the DGNRS contract address, not the caller. The caller gets the BURNIE rebate and potential quest reward but tickets go to DGNRS contract.
**Gas Flags:** Two external calls to `quests.playerQuestStates` (before and after). Could be avoided if quest reward is rare, but this is defensive/correct.
**Verdict:** CORRECT

---

### `gamePurchaseTicketsBurnie(uint256 ticketQuantity)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `ticketQuantity` (uint256): number of tickets to purchase |
| **Returns** | None |

**State Reads:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `burnieSpentThisLevel[msg.sender]`, `game.level()`
**State Writes:** `burnieSpentThisLevel[msg.sender]`

**Callers:** External DGNRS holders with locked tokens
**Callees:** `_checkAndRecordBurnieSpend`, `game.purchaseCoin`

**ETH Flow:** No
**Invariants:**
- `ticketQuantity` must be non-zero (reverts Insufficient)
- BURNIE cost = `ticketQuantity * PRICE_COIN_UNIT` (1000 BURNIE per ticket)
- Must not exceed BURNIE spend limit
- Routes through `game.purchaseCoin(address(0), ticketQuantity, 0)` -- tickets only, no lootboxes

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gamePurchaseBurnieLootbox(uint256 burnieAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gamePurchaseBurnieLootbox(uint256 burnieAmount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `burnieAmount` (uint256): amount of BURNIE (18 decimals) |
| **Returns** | None |

**State Reads:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `burnieSpentThisLevel[msg.sender]`, `game.level()`
**State Writes:** `burnieSpentThisLevel[msg.sender]`

**Callers:** External DGNRS holders with locked tokens
**Callees:** `_checkAndRecordBurnieSpend`, `game.purchaseBurnieLootbox`

**ETH Flow:** No
**Invariants:**
- `burnieAmount` must be non-zero (reverts Insufficient)
- Must not exceed BURNIE spend limit
- Routes through `game.purchaseBurnieLootbox(address(0), burnieAmount)`

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gameDegeneretteBetEth(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetEth(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `amountPerTicket` (uint128): ETH per ticket; `ticketCount` (uint8): number of spins; `customTicket` (uint32): custom trait pack; `customSpecial` (uint8): hero quadrant |
| **Returns** | None |

**State Reads:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `ethSpentThisLevel[msg.sender]`, `game.level()`
**State Writes:** `ethSpentThisLevel[msg.sender]`

**Callers:** External DGNRS holders with locked tokens
**Callees:** `_checkAndRecordEthSpend`, `game.placeFullTicketBets{value: msg.value}`

**ETH Flow:** msg.value forwarded to game.placeFullTicketBets
**Invariants:**
- Total bet = `amountPerTicket * ticketCount`, must not exceed ETH spend limit
- Currency = 0 (ETH) passed to game
- buyer = address(0) (DGNRS contract)

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gameDegeneretteBetBurnie(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gameDegeneretteBetBurnie(uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 customSpecial) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amountPerTicket` (uint128): BURNIE per ticket; `ticketCount` (uint8): number of spins; `customTicket` (uint32): custom trait pack; `customSpecial` (uint8): hero quadrant |
| **Returns** | None |

**State Reads:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `burnieSpentThisLevel[msg.sender]`, `game.level()`
**State Writes:** `burnieSpentThisLevel[msg.sender]`

**Callers:** External DGNRS holders with locked tokens
**Callees:** `_checkAndRecordBurnieSpend`, `game.placeFullTicketBets`

**ETH Flow:** No
**Invariants:**
- Total bet = `amountPerTicket * ticketCount`, must not exceed BURNIE spend limit
- Currency = 1 (BURNIE) passed to game
- buyer = address(0) (DGNRS contract)

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gameOpenLootBox(uint48 lootboxIndex)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gameOpenLootBox(uint48 lootboxIndex) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lootboxIndex` (uint48): index of lootbox to open |
| **Returns** | None |

**State Reads:** `balanceOf[msg.sender]` (via onlyHolder)
**State Writes:** None directly

**Callers:** External DGNRS holders
**Callees:** `game.openLootBox(address(0), lootboxIndex)`

**ETH Flow:** No (lootbox rewards go to DGNRS contract)
**Invariants:** Caller must hold DGNRS tokens. Does not require locked tokens.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `gameClaimWhalePass()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function gameClaimWhalePass() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:** `balanceOf[msg.sender]` (via onlyHolder)
**State Writes:** None directly

**Callers:** External DGNRS holders
**Callees:** `game.claimWhalePass(address(0))`

**ETH Flow:** No
**Invariants:** Caller must hold DGNRS tokens. Does not require locked tokens. Claims whale pass for DGNRS contract.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `coinDecimatorBurn(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function coinDecimatorBurn(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): amount of BURNIE to burn (18 decimals) |
| **Returns** | None |

**State Reads:** `lockedBalance[msg.sender]`, `lockedLevel[msg.sender]`, `burnieSpentThisLevel[msg.sender]`, `game.level()`
**State Writes:** `burnieSpentThisLevel[msg.sender]`

**Callers:** External DGNRS holders with locked tokens
**Callees:** `_checkAndRecordBurnieSpend`, `coin.decimatorBurn(address(this), amount)`

**ETH Flow:** No
**Invariants:**
- Must have locked tokens at current level
- BURNIE amount must not exceed spend limit
- Burns BURNIE from the DGNRS contract's balance (not the caller's) via `coin.decimatorBurn(address(this), amount)`

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### BURNIE Rebate

---

### `_rebateBurnieFromEthValue(uint256 ethValue)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rebateBurnieFromEthValue(uint256 ethValue) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ethValue` (uint256): ETH value used for rebate calculation |
| **Returns** | None |

**State Reads:** `game.mintPrice()`, `coin.balanceOf(address(this))`, `game.rngLocked()`, `coinflip.previewClaimCoinflips(address(this))`
**State Writes:** None directly (BURNIE transfer is external)

**Callers:** `gamePurchase`
**Callees:** `game.mintPrice()`, `coin.balanceOf`, `game.rngLocked()`, `coinflip.previewClaimCoinflips`, `coinflip.claimCoinflips`, `coin.transfer`

**ETH Flow:** No ETH movement. BURNIE is transferred from contract to msg.sender.
**Invariants:**
- Formula: `burnieValue = (ethValue * PRICE_COIN_UNIT) / priceWei`, then `burnieOut = (burnieValue * BURNIE_ETH_BUY_BPS) / BPS_DENOM`
- Effectively: `burnieOut = (ethValue * 1000e18 * 7000) / (priceWei * 10000)` = `(ethValue * 700e18) / priceWei`
- So for 1 ETH at priceWei, you get 700 BURNIE tokens -- 70% of the BURNIE-equivalent value
- Pays from contract's BURNIE balance first
- If insufficient, attempts to claim from coinflip claimables (only if RNG not locked)
- Silently returns (no revert) if insufficient funds or RNG locked -- graceful degradation
- Emits BurnieRebate on success

**NatSpec Accuracy:** Accurate. Correctly documents fallback behavior.
**Gas Flags:** Up to 5 external calls in worst case (mintPrice, balanceOf, rngLocked, previewClaimCoinflips, claimCoinflips + transfer). Acceptable for the functionality.
**Verdict:** CORRECT

---

### Deposit Functions (Game Only)

---

### `receive()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `receive() external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | None (receives ETH via msg.value) |
| **Returns** | None |

**State Reads:** `ContractAddresses.GAME` (via onlyGame)
**State Writes:** None (ETH stored in contract balance implicitly)

**Callers:** Game contract (ETH distributions)
**Callees:** None

**ETH Flow:** Game -> DGNRS contract (ETH deposit, stored in contract balance)
**Invariants:** Only game contract can send ETH. Note: `ethReserve` is NOT updated -- ETH backing is tracked by `address(this).balance` at query time.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** INFORMATIONAL -- `ethReserve` storage variable is declared (line 227) but never written anywhere in the contract. All ETH-related calculations use `address(this).balance` directly. The `ethReserve` variable is dead storage.
**Verdict:** CONCERN (informational) -- `ethReserve` is declared but never used. It occupies a storage slot but is never read or written. This is not a bug but is dead code that should be removed for clarity.

---

### `depositSteth(uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function depositSteth(uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): stETH amount to deposit |
| **Returns** | None |

**State Reads:** `ContractAddresses.GAME` (via onlyGame)
**State Writes:** None (stETH tracked by external balanceOf)

**Callers:** Game contract (stETH distributions)
**Callees:** `steth.transferFrom(msg.sender, address(this), amount)`

**ETH Flow:** stETH transferred from game to DGNRS contract.
**Invariants:** Only game contract can deposit stETH. Uses transferFrom (game must have approved DGNRS for stETH).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Pool Accounting

---

### `poolBalance(Pool pool)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function poolBalance(Pool pool) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `pool` (Pool): pool enum identifier |
| **Returns** | `uint256`: remaining pool balance |

**State Reads:** `poolBalances[_poolIndex(pool)]`
**State Writes:** None

**Callers:** External callers, game contract
**Callees:** `_poolIndex(pool)`

**ETH Flow:** No
**Invariants:** Pure lookup, no access control.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferFromPool(Pool pool, address to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferFromPool(Pool pool, address to, uint256 amount) external returns (uint256 transferred)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `pool` (Pool): source pool; `to` (address): recipient; `amount` (uint256): requested amount |
| **Returns** | `uint256`: actual amount transferred (may be less) |

**State Reads:** `poolBalances[idx]`, `ContractAddresses.GAME` (via onlyGame), `balanceOf[address(this)]`, `lockedBalance[address(this)]`
**State Writes:** `poolBalances[idx]` (decremented), `balanceOf[address(this)]` (decremented via `_transfer`), `balanceOf[to]` (incremented)

**Callers:** Game contract
**Callees:** `_poolIndex`, `_transfer(address(this), to, amount)`

**ETH Flow:** No (DGNRS token transfer, not ETH)
**Invariants:**
- Only game can call
- Zero-address `to` will revert in `_transfer`
- Graceful degradation: if pool has less than requested, transfers available amount
- Returns 0 for zero amount or empty pool
- Uses unchecked subtraction safe due to prior `amount <= available` check
- Emits PoolTransfer

**NatSpec Accuracy:** Accurate. Correctly documents partial-fill behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `transferBetweenPools(Pool from, Pool to, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function transferBetweenPools(Pool from, Pool to, uint256 amount) external returns (uint256 transferred)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (Pool): source pool; `to` (Pool): destination pool; `amount` (uint256): requested amount |
| **Returns** | `uint256`: actual amount transferred |

**State Reads:** `poolBalances[fromIdx]`, `ContractAddresses.GAME` (via onlyGame)
**State Writes:** `poolBalances[fromIdx]` (decremented), `poolBalances[toIdx]` (incremented)

**Callers:** Game contract
**Callees:** `_poolIndex` (x2)

**ETH Flow:** No
**Invariants:**
- Only game can call
- No actual token transfer -- just internal pool accounting rebalance
- Graceful degradation for insufficient source pool
- Emits PoolRebalance

**NatSpec Accuracy:** Accurate. Correctly notes no token movement.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Burn Mechanics

---

### `burnForGame(address from, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burnForGame(address from, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): amount to burn |
| **Returns** | None |

**State Reads:** `ContractAddresses.GAME` (via onlyGame), `balanceOf[from]` (via `_burn`)
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented), `lockedBalance[from]` (via `_reduceActiveLock`)

**Callers:** Game contract
**Callees:** `_burn(from, amount)`

**ETH Flow:** No
**Invariants:**
- Only game can call
- No-op for zero amount (returns early)
- Burns reduce total supply, which increases proportional backing per remaining token

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `burn(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function burn(address player, uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to burn for (address(0) = msg.sender); `amount` (uint256): DGNRS amount to burn |
| **Returns** | `ethOut` (uint256): ETH received; `stethOut` (uint256): stETH received; `burnieOut` (uint256): BURNIE received |

**State Reads:** `balanceOf[player]`, `totalSupply`, various external balances
**State Writes:** (via `_burnFor`) `balanceOf[player]`, `totalSupply`, `lockedBalance[player]`

**Callers:** External users/operators
**Callees:** `_requireApproved(player)` (if player != msg.sender and player != address(0)), `_burnFor(player, amount)`

**ETH Flow:** Pays out proportional ETH + stETH from contract reserves to player.
**Invariants:**
- address(0) resolves to msg.sender
- If player != msg.sender, must be approved operator
- Delegates to _burnFor for actual logic

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_burnFor(address player, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnFor(address player, uint256 amount) private returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address to burn from and pay out to; `amount` (uint256): DGNRS to burn |
| **Returns** | `ethOut`, `stethOut`, `burnieOut`: amounts paid out |

**State Reads:** `balanceOf[player]`, `totalSupply`, `address(this).balance`, `steth.balanceOf(address(this))`, `game.claimableWinningsOf(address(this))` (via `_claimableWinnings`), `coin.balanceOf(address(this))`, `coinflip.previewClaimCoinflips(address(this))`, `wwxrp.balanceOf(address(this))`
**State Writes:** `balanceOf[player]`, `totalSupply`, `lockedBalance[player]` (via `_burnWithBalance` -> `_reduceActiveLock`)

**Callers:** `burn`
**Callees:** `_claimableWinnings`, `_burnWithBalance`, `game.claimWinnings(address(0))` (conditional), `coin.transfer`, `coinflip.claimCoinflips`, `steth.transfer`, `wwxrp.transfer`

**ETH Flow:**
- Calculates total money = ETH balance + stETH balance + claimable ETH
- Proportional share = `(totalMoney * amount) / supplyBefore`
- Prefers ETH over stETH: if totalValueOwed <= ethBal, pay all in ETH; otherwise pay ethBal in ETH + remainder in stETH
- If need more ETH than available but claimable exists, calls `game.claimWinnings` to materialize claimable ETH
- BURNIE share: `(totalBurnie * amount) / supplyBefore` from balance + coinflip claimables
- WWXRP share: `(wwxrpBal * amount) / supplyBefore`

**Invariants:**
- Amount must be > 0 and <= balance
- Burns BEFORE payouts (reducing totalSupply first for security)
- ETH-preferential payout: ETH first, stETH only when ETH insufficient
- BURNIE: pays from balance first, then claims from coinflip
- Reverts Insufficient if stethOut > stethBal (can't pay full share)
- Emits Burn and BurnWwxrp

**NatSpec Accuracy:** Accurate.
**Gas Flags:** Multiple external calls (up to 8+ in worst case). Complex but necessary for multi-asset proportional withdrawal.
**Verdict:** CORRECT

---

### `previewBurn(uint256 amount)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `amount` (uint256): DGNRS amount to preview burning |
| **Returns** | `ethOut`, `stethOut`, `burnieOut`: projected payout amounts |

**State Reads:** `totalSupply`, `address(this).balance`, `steth.balanceOf(address(this))`, `_claimableWinnings()`, `coin.balanceOf(address(this))`, `coinflip.previewClaimCoinflips(address(this))`
**State Writes:** None

**Callers:** External callers (UI)
**Callees:** `_claimableWinnings`, `steth.balanceOf`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`

**ETH Flow:** No (view only)
**Invariants:**
- Returns (0,0,0) if amount is 0 or exceeds totalSupply
- ETH payout: prefers ETH+claimable over stETH (note: slight difference from _burnFor which only has contract balance before claiming)
- BURNIE: includes claimable coinflips
- Does NOT preview WWXRP -- minor inconsistency with _burnFor which also pays WWXRP

**NatSpec Accuracy:** CONCERN -- NatSpec does not mention WWXRP omission. The function does not return wwxrpOut even though _burnFor pays it.
**Gas Flags:** None.
**Verdict:** CONCERN (informational) -- previewBurn does not include WWXRP in its return values, while the actual burn pays WWXRP proportionally. Users previewing a burn won't see the WWXRP component. Not a security issue but a UX gap.

---

### `totalBacking()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function totalBacking() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: total backing value across all asset types |

**State Reads:** `address(this).balance`, `steth.balanceOf(address(this))`, `_claimableWinnings()`, `coin.balanceOf(address(this))`, `coinflip.previewClaimCoinflips(address(this))`
**State Writes:** None

**Callers:** External callers (UI)
**Callees:** `steth.balanceOf`, `_claimableWinnings`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`

**ETH Flow:** No
**Invariants:** Sums ETH + stETH + claimable ETH + BURNIE + claimable BURNIE. Does not include WWXRP -- same gap as previewBurn.
**NatSpec Accuracy:** NatSpec says "ETH + stETH + claimable ETH + BURNIE backing" which matches the implementation. Does not mention WWXRP omission.
**Gas Flags:** None.
**Verdict:** CONCERN (informational) -- totalBacking omits WWXRP balance, which IS paid on burn. Inconsistency with actual backing composition.

---

### `burnieReserve()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function burnieReserve() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: BURNIE backing (balance + claimable coinflips) |

**State Reads:** `coin.balanceOf(address(this))`, `coinflip.previewClaimCoinflips(address(this))`
**State Writes:** None

**Callers:** External callers (UI)
**Callees:** `coin.balanceOf`, `coinflip.previewClaimCoinflips`

**ETH Flow:** No
**Invariants:** Returns sum of on-hand BURNIE + claimable BURNIE from coinflip.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `getLockStatus(address holder)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getLockStatus(address holder) external view returns (uint256 locked, uint24 lockLevel, uint256 ethLimit, uint256 ethSpent, uint256 burnieLimit, uint256 burnieSpent, bool canUnlock)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `holder` (address): address to query |
| **Returns** | Comprehensive lock status tuple |

**State Reads:** `lockedBalance[holder]`, `lockedLevel[holder]`, `game.level()`, `ethSpentThisLevel[holder]`, `burnieSpentThisLevel[holder]`, (via `_lockedClaimableValues`) `totalSupply`, `address(this).balance`, `steth.balanceOf`, `_claimableWinnings`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`
**State Writes:** None

**Callers:** External callers (UI)
**Callees:** `game.level()`, `_lockedClaimableValues`

**ETH Flow:** No
**Invariants:**
- If locked at current level: returns ethLimit/burnieLimit (10x proportional values), spent counters, canUnlock=false
- If locked at different level: returns canUnlock=true, limits/spent are 0
- If not locked: all zeros

**NatSpec Accuracy:** Accurate.
**Gas Flags:** Heavy view function (many external calls via `_lockedClaimableValues`). Acceptable for a view.
**Verdict:** CORRECT

---

### Internal Helpers

---

### `_maxEthActionFromLocked(uint256 locked)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _maxEthActionFromLocked(uint256 locked) private view returns (uint256 maxEth)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `locked` (uint256): locked DGNRS amount |
| **Returns** | `uint256`: maximum ETH spend allowed (10x proportional value) |

**State Reads:** (via `_lockedClaimableValues`) `totalSupply`, `address(this).balance`, `steth.balanceOf`, `_claimableWinnings`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`
**State Writes:** None

**Callers:** `_checkAndRecordEthSpend`
**Callees:** `_lockedClaimableValues(locked)`

**ETH Flow:** No
**Invariants:** Returns ethValue * 10 from _lockedClaimableValues. Unchecked multiply by 10 is safe because ethValue is bounded by total contract ETH.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_maxBurnieActionFromLocked(uint256 locked)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _maxBurnieActionFromLocked(uint256 locked) private view returns (uint256 maxBurnie)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `locked` (uint256): locked DGNRS amount |
| **Returns** | `uint256`: maximum BURNIE spend allowed (10x proportional value) |

**State Reads:** (via `_lockedClaimableValues`) same as above
**State Writes:** None

**Callers:** `_checkAndRecordBurnieSpend`
**Callees:** `_lockedClaimableValues(locked)`

**ETH Flow:** No
**Invariants:** Returns burnieValue * 10. Unchecked multiply safe for same reason.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_lockedClaimableValues(uint256 locked)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _lockedClaimableValues(uint256 locked) private view returns (uint256 ethValue, uint256 burnieValue)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `locked` (uint256): locked DGNRS amount |
| **Returns** | `ethValue`: proportional ETH+stETH+claimable share; `burnieValue`: proportional BURNIE share |

**State Reads:** `totalSupply`, `address(this).balance`, `steth.balanceOf(address(this))`, `_claimableWinnings()`, `coin.balanceOf(address(this))`, `coinflip.previewClaimCoinflips(address(this))`
**State Writes:** None

**Callers:** `_maxEthActionFromLocked`, `_maxBurnieActionFromLocked`, `getLockStatus`
**Callees:** `steth.balanceOf`, `_claimableWinnings`, `coin.balanceOf`, `coinflip.previewClaimCoinflips`

**ETH Flow:** No
**Invariants:**
- ethValue = `(totalMoney * locked) / supply` where totalMoney = ETH + stETH + claimable ETH
- burnieValue = `(totalBurnie * locked) / supply` where totalBurnie = BURNIE balance + claimable coinflips
- Returns (0,0) if supply is 0 or locked is 0

**NatSpec Accuracy:** Accurate.
**Gas Flags:** 4 external calls. Called multiple times per transaction in spend-check paths.
**Verdict:** CORRECT

---

### `_transferFromPoolInternal(Pool pool, address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _transferFromPoolInternal(Pool pool, address to, uint256 amount) private returns (uint256 transferred)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `pool` (Pool): source pool; `to` (address): recipient; `amount` (uint256): requested amount |
| **Returns** | `uint256`: actual amount transferred |

**State Reads:** `poolBalances[idx]`
**State Writes:** `poolBalances[idx]` (decremented), `balanceOf[address(this)]`, `balanceOf[to]` (via `_transfer`)

**Callers:** `gamePurchase` (quest contribution reward)
**Callees:** `_poolIndex`, `_transfer`

**ETH Flow:** No
**Invariants:** Same logic as external `transferFromPool` but without onlyGame guard. Used for internal pool-to-player transfers (quest rewards).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_checkAndRecordEthSpend(address holder, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _checkAndRecordEthSpend(address holder, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `holder` (address): spending holder; `amount` (uint256): ETH being spent |
| **Returns** | None |

**State Reads:** `game.level()`, `lockedBalance[holder]`, `lockedLevel[holder]`, `ethSpentThisLevel[holder]`, (via `_maxEthActionFromLocked`) multiple external reads
**State Writes:** `ethSpentThisLevel[holder]`

**Callers:** `gamePurchase`, `gameDegeneretteBetEth`
**Callees:** `game.level()`, `_maxEthActionFromLocked`

**ETH Flow:** No (validation only)
**Invariants:**
- Holder must have locked tokens at current level (reverts NoLockedTokens)
- Cumulative spend (previous + current) must not exceed limit (reverts ActionLimitExceeded)
- Limit = 10x proportional ETH value of locked DGNRS

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_checkAndRecordBurnieSpend(address holder, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _checkAndRecordBurnieSpend(address holder, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `holder` (address): spending holder; `amount` (uint256): BURNIE being spent |
| **Returns** | None |

**State Reads:** `game.level()`, `lockedBalance[holder]`, `lockedLevel[holder]`, `burnieSpentThisLevel[holder]`, (via `_maxBurnieActionFromLocked`) multiple external reads
**State Writes:** `burnieSpentThisLevel[holder]`

**Callers:** `gamePurchaseTicketsBurnie`, `gamePurchaseBurnieLootbox`, `gameDegeneretteBetBurnie`, `coinDecimatorBurn`
**Callees:** `game.level()`, `_maxBurnieActionFromLocked`

**ETH Flow:** No (validation only)
**Invariants:** Same pattern as _checkAndRecordEthSpend but for BURNIE.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_claimableWinnings()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimableWinnings() private view returns (uint256 claimable)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: claimable winnings minus 1 wei dust |

**State Reads:** `game.claimableWinningsOf(address(this))`
**State Writes:** None

**Callers:** `_burnFor`, `previewBurn`, `totalBacking`, `_lockedClaimableValues`
**Callees:** `game.claimableWinningsOf`

**ETH Flow:** No
**Invariants:** Returns 0 if stored <= 1 (dust guard). Otherwise returns stored - 1. This prevents claiming the last wei which could cause issues in game accounting.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_poolIndex(Pool pool)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _poolIndex(Pool pool) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `pool` (Pool): pool enum |
| **Returns** | `uint8`: array index |

**State Reads:** None
**State Writes:** None

**Callers:** `poolBalance`, `transferFromPool`, `transferBetweenPools`, `_transferFromPoolInternal`
**Callees:** None

**ETH Flow:** No
**Invariants:** Direct cast from enum to uint8. Enum values 0-4 match array indices.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_mint(address to, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _mint(address to, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `to` (address): recipient; `amount` (uint256): tokens to mint |
| **Returns** | None |

**State Reads:** None
**State Writes:** `totalSupply` (incremented), `balanceOf[to]` (incremented)

**Callers:** `constructor` (only)
**Callees:** None

**ETH Flow:** No
**Invariants:** Zero-address blocked. Unchecked arithmetic safe because only called twice in constructor with bounded values. Emits Transfer from address(0).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_burn(address from, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burn(address from, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): address to burn from; `amount` (uint256): tokens to burn |
| **Returns** | None |

**State Reads:** `balanceOf[from]`
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented), `lockedBalance[from]` (via `_reduceActiveLock`)

**Callers:** `burnForGame`
**Callees:** `_reduceActiveLock(from, amount)`

**ETH Flow:** No
**Invariants:** Amount must not exceed balance. Reduces active lock proportionally. Unchecked arithmetic safe due to prior check. Emits Transfer to address(0).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_burnWithBalance(address from, uint256 amount, uint256 bal)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _burnWithBalance(address from, uint256 amount, uint256 bal) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `from` (address): burn address; `amount` (uint256): tokens to burn; `bal` (uint256): pre-fetched balance |
| **Returns** | None |

**State Reads:** None (balance pre-fetched by caller)
**State Writes:** `balanceOf[from]` (decremented), `totalSupply` (decremented), `lockedBalance[from]` (via `_reduceActiveLock`)

**Callers:** `_burnFor`
**Callees:** `_reduceActiveLock(from, amount)`

**ETH Flow:** No
**Invariants:** Optimization of `_burn` that skips the balanceOf read (caller already has it). Caller must ensure `amount <= bal`. Unchecked arithmetic relies on this invariant.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_reduceActiveLock(address holder, uint256 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _reduceActiveLock(address holder, uint256 amount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `holder` (address): holder whose lock to reduce; `amount` (uint256): amount being burned |
| **Returns** | None |

**State Reads:** `lockedLevel[holder]`, `game.level()`, `lockedBalance[holder]`
**State Writes:** `lockedBalance[holder]` (reduced or zeroed)

**Callers:** `_burn`, `_burnWithBalance`
**Callees:** `game.level()`

**ETH Flow:** No
**Invariants:**
- Only reduces lock if holder is locked at current level
- If burn amount >= locked amount, zeroes the lock
- If burn amount < locked amount, reduces lock by burn amount
- This prevents a burned holder from retaining action rights beyond their remaining balance

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

## Lock-for-Level Mechanics

### Lock/Unlock Lifecycle

1. **Lock (`lockForLevel`):** Holder calls with a DGNRS amount. Tokens are locked against the current game level. The locked amount is additive within the same level (can call multiple times to increase lock). If a lock exists from a prior level, it auto-unlocks first (resets spending counters, emits Unlocked), then applies the new lock at the current level.

2. **Spend:** While locked, holder can spend ETH or BURNIE through game proxy functions up to 10x the proportional backing value of their locked tokens:
   - ETH limit: `10 * (totalMoney * locked / totalSupply)` where totalMoney = ETH balance + stETH balance + claimable ETH
   - BURNIE limit: `10 * (totalBurnie * locked / totalSupply)` where totalBurnie = BURNIE balance + claimable coinflips
   - Spending is cumulative per level -- each spend adds to the running total

3. **Unlock (`unlock`):** Holder can only unlock after the game level has changed. Resets `lockedBalance`, `ethSpentThisLevel`, and `burnieSpentThisLevel` to 0. Emits Unlocked.

4. **Auto-unlock on re-lock:** If holder calls `lockForLevel` while locked at a different level, the old lock is automatically released before applying the new one.

5. **Burn interaction (`_reduceActiveLock`):** If tokens are burned (via `burnForGame` or `burn`) while the holder has an active lock at the current level, the lock amount is reduced by the burn amount (or zeroed if burn >= locked).

6. **Transfer interaction (`_transfer`):** Locked tokens at the current level cannot be transferred. Only `balance - lockedBalance` is transferable.

### Token Requirement Per Level

There is no minimum token requirement per level. Any non-zero amount can be locked. The spending limit scales proportionally with the locked amount. Locking more tokens gives a higher spending limit.

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Lock at level 0 | Works normally, level 0 is valid |
| Lock 0 tokens | Allowed (no state change, lockedLevel updated) |
| Re-lock at same level | Additive -- increases locked amount |
| Re-lock at different level | Auto-unlocks old lock, resets spend counters, applies new lock |
| Unlock at same level | Reverts LockStillActive |
| Unlock with no lock | Reverts NoLockedTokens |
| Transfer while locked | Only unlocked portion transferable (reverts TokensLocked if exceeding) |
| Burn while locked | _reduceActiveLock reduces lock by burn amount |
| Spend without lock | Reverts NoLockedTokens |
| Spend at different level | Reverts NoLockedTokens (lock must be at current level) |

---

## BURNIE Rebate Analysis

### Rebate Formula

The `_rebateBurnieFromEthValue` function converts ETH value to a BURNIE payout:

```
burnieValue = (ethValue * PRICE_COIN_UNIT) / priceWei
            = (ethValue * 1000e18) / priceWei

burnieOut   = (burnieValue * BURNIE_ETH_BUY_BPS) / BPS_DENOM
            = (burnieValue * 7000) / 10000
            = burnieValue * 0.70

Combined:
burnieOut = (ethValue * 1000e18 * 7000) / (priceWei * 10000)
          = (ethValue * 700e18) / priceWei
```

**Interpretation:** For every 1x priceWei of ETH spent, the holder receives 700 BURNIE (70% of the 1000 BURNIE unit rate).

### Rebate Trigger Points

Only `gamePurchase` triggers BURNIE rebates. The ETH value used for the rebate depends on payment kind:
- `DirectEth`: uses `totalCost` (ticketCost + lootBoxAmount) -- the actual ETH committed
- `Claimable` or `Combined`: uses `msg.value` -- the ETH portion of the payment

### BURNIE Source Priority

1. Contract's on-hand BURNIE balance (`coin.balanceOf(address(this))`)
2. If insufficient: claimable BURNIE from coinflip contract (`coinflip.claimCoinflips`)
3. If still insufficient OR RNG is locked (preventing coinflip claims): rebate silently skipped

### Graceful Degradation

The rebate mechanism never reverts. If funds are unavailable, the rebate is simply not paid. This prevents game purchases from failing due to BURNIE availability issues.

---

## Game Proxy Function Matrix

| Stonk Function | Game Function Called | ETH Forwarded | Requires Lock | BURNIE Rebate | Spend Tracking | Additional Logic |
|----------------|---------------------|---------------|---------------|---------------|----------------|------------------|
| `gameAdvance` | `game.advanceGame()` | No | No (onlyHolder) | No | None | Any holder can advance |
| `gamePurchase` | `game.purchase{value}` | Yes (msg.value) | Yes (ETH) | Yes | ETH | Quest streak reward, affiliate code DGNRS |
| `gamePurchaseTicketsBurnie` | `game.purchaseCoin` | No | Yes (BURNIE) | No | BURNIE | Tickets only (no lootbox) |
| `gamePurchaseBurnieLootbox` | `game.purchaseBurnieLootbox` | No | Yes (BURNIE) | No | BURNIE | Lootbox only |
| `gameDegeneretteBetEth` | `game.placeFullTicketBets{value}` | Yes (msg.value) | Yes (ETH) | No | ETH | Currency=0 (ETH) |
| `gameDegeneretteBetBurnie` | `game.placeFullTicketBets` | No | Yes (BURNIE) | No | BURNIE | Currency=1 (BURNIE) |
| `gameOpenLootBox` | `game.openLootBox` | No | No (onlyHolder) | No | None | Opens DGNRS contract's lootbox |
| `gameClaimWhalePass` | `game.claimWhalePass` | No | No (onlyHolder) | No | None | Claims whale pass for DGNRS contract |
| `coinDecimatorBurn` | `coin.decimatorBurn` | No | Yes (BURNIE) | No | BURNIE | Burns from DGNRS contract BURNIE balance |

**Key observations:**
- All proxy functions pass `address(0)` as buyer/player, which resolves to `msg.sender` (= DGNRS contract) in the game -- so actions are performed as the DGNRS contract entity, not the individual caller
- Only `gamePurchase` includes a BURNIE rebate (the only ETH purchase proxy)
- Only `gamePurchase` includes quest streak tracking (checks before/after for quest completion)
- Lock-requiring functions enforce spending limits via `_checkAndRecordEthSpend` or `_checkAndRecordBurnieSpend`
- Non-lock functions only require holder status (non-zero balance)

---

## Storage Mutation Map

| Function | Variables Written | Write Type |
|----------|------------------|------------|
| `constructor` | `totalSupply`, `balanceOf[CREATOR]`, `balanceOf[this]`, `poolBalances[0..4]` | Initialize |
| `approve` | `allowance[sender][spender]` | Set |
| `transfer` | `balanceOf[from]`, `balanceOf[to]` | Decrement/Increment |
| `transferFrom` | `allowance[from][sender]`, `balanceOf[from]`, `balanceOf[to]` | Decrement/Increment |
| `lockForLevel` | `lockedBalance[sender]`, `lockedLevel[sender]`, `ethSpentThisLevel[sender]`, `burnieSpentThisLevel[sender]` | Set/Reset |
| `unlock` | `lockedBalance[sender]`, `ethSpentThisLevel[sender]`, `burnieSpentThisLevel[sender]` | Zero |
| `gamePurchase` | `ethSpentThisLevel[sender]`, `poolBalances[Reward]`, `balanceOf[this]`, `balanceOf[sender]` | Increment/Decrement |
| `gamePurchaseTicketsBurnie` | `burnieSpentThisLevel[sender]` | Increment |
| `gamePurchaseBurnieLootbox` | `burnieSpentThisLevel[sender]` | Increment |
| `gameDegeneretteBetEth` | `ethSpentThisLevel[sender]` | Increment |
| `gameDegeneretteBetBurnie` | `burnieSpentThisLevel[sender]` | Increment |
| `coinDecimatorBurn` | `burnieSpentThisLevel[sender]` | Increment |
| `transferFromPool` | `poolBalances[idx]`, `balanceOf[this]`, `balanceOf[to]` | Decrement/Increment |
| `transferBetweenPools` | `poolBalances[fromIdx]`, `poolBalances[toIdx]` | Decrement/Increment |
| `burnForGame` | `balanceOf[from]`, `totalSupply`, `lockedBalance[from]` | Decrement |
| `burn` / `_burnFor` | `balanceOf[player]`, `totalSupply`, `lockedBalance[player]` | Decrement |

---

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function |
|------|--------|-------------|---------|----------|
| ETH deposit | Game contract | DGNRS contract balance | Game distribution | `receive()` |
| stETH deposit | Game contract | DGNRS stETH balance | Game distribution | `depositSteth` |
| ETH purchase forwarding | msg.sender (via msg.value) | Game contract | Holder purchase | `gamePurchase` |
| ETH bet forwarding | msg.sender (via msg.value) | Game contract | Holder degenerette bet | `gameDegeneretteBetEth` |
| ETH burn payout | DGNRS contract balance | Burning player | Token burn | `_burnFor` |
| stETH burn payout | DGNRS stETH balance | Burning player | Token burn (overflow) | `_burnFor` |
| BURNIE burn payout | DGNRS BURNIE balance | Burning player | Token burn | `_burnFor` |
| BURNIE claimable payout | Coinflip claimable | Burning player (via DGNRS) | Token burn (shortfall) | `_burnFor` |
| WWXRP burn payout | DGNRS WWXRP balance | Burning player | Token burn | `_burnFor` |
| Claimable ETH materialization | Game claimable | DGNRS contract balance | Burn when balance < owed | `_burnFor` |
| BURNIE rebate | DGNRS BURNIE balance | Caller (msg.sender) | ETH purchase | `_rebateBurnieFromEthValue` |
| BURNIE rebate (claimable) | Coinflip claimable | Caller (via DGNRS) | ETH purchase (shortfall) | `_rebateBurnieFromEthValue` |

---

## Findings Summary

| ID | Severity | Function | Details |
|----|----------|----------|---------|
| S-01 | CONCERN (informational) | `receive()` / global | `ethReserve` storage variable (line 227) is declared but never read or written. Dead storage occupying a slot. Should be removed for clarity. |
| S-02 | CONCERN (informational) | `previewBurn` | Does not return WWXRP component. Actual `_burnFor` pays proportional WWXRP, but preview omits it. UI gap -- users won't see WWXRP portion in preview. |
| S-03 | CONCERN (informational) | `totalBacking` | Does not include WWXRP balance in total backing calculation. Actual backing composition includes WWXRP (paid on burn), so the view under-reports total backing. |

| Severity | Count | Summary |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 3 | S-01 dead storage, S-02/S-03 WWXRP omission in views |
| GAS | 0 | No actionable gas optimizations |
| CORRECT | 41 | All 44 entries verified; 41 unconditionally CORRECT, 3 with informational concerns |

### Correctness Verification

- **ERC-20 compliance:** Standard approve/transfer/transferFrom pattern with lock enforcement. COIN trusted-spender bypass is documented and intentional.
- **Lock-for-level:** Properly enforces per-level locking with auto-unlock, additive locks, and proportional spending limits. _reduceActiveLock correctly handles burn interactions.
- **BURNIE rebate:** Formula correctly converts ETH to 70% BURNIE value. Graceful degradation on insufficient funds or RNG lock.
- **Pool accounting:** Five pools with correct BPS allocation (sums to 100%). Graceful degradation on pool depletion. No double-spend possible.
- **Burn-to-extract:** Proportional share calculation is correct. Burns before payouts (reentrancy safe). ETH-preferential payout logic handles all edge cases. Multi-asset payout (ETH + stETH + BURNIE + WWXRP) covers all backing types.
- **Game proxy:** All proxy functions correctly forward to game contract with DGNRS as actor. Spending limits properly enforced for locked-token actions.
- **Quest contribution reward:** Novel mechanism -- 0.05% of Reward pool given to caller whose purchase completes a quest for the DGNRS contract. Correctly checks streak before/after.
