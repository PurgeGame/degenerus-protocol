# DegenerusJackpots.sol -- Function-Level Audit

**Contract:** DegenerusJackpots
**File:** contracts/DegenerusJackpots.sol
**Lines:** 761
**Solidity:** 0.8.34
**Implements:** IDegenerusJackpots
**Audit date:** 2026-03-07

## Summary

Standalone BAF (Big Ass Flip) jackpot system managing coinflip stake accumulation per player per level, a sorted top-4 leaderboard per level, and multi-category jackpot distribution at level transitions. Prize pool splits across 7 categories: top BAF bettor (10%), top coinflip bettor last 24h (10%), random 3rd/4th BAF pick (5%), affiliate draw (10%), far-future ticket holders (5%), scatter 1st place (40%), scatter 2nd place (20%). Unfilled prizes are returned to the caller. Winner-mask bits flag scatter recipients for ticket routing by the game contract. ETH is not transferred directly -- winners and amounts are returned as arrays and the game contract handles actual disbursement.

**Key design notes:**
- Contract holds no ETH and transfers no ETH -- it is a pure computation contract
- `_creditOrRefund` is misleadingly named: it is a `pure` function that writes to memory buffers, not storage/ETH
- All actual ETH distribution happens in the calling game contract (JackpotModule)
- Leaderboard state (`bafTop`, `bafTopLen`, `bafTotals`) is cleared per-level after resolution

## Function Audit

---

### Errors and Modifiers

#### `OnlyCoin` (error)
Thrown when `msg.sender` is not `ContractAddresses.COIN` and not `ContractAddresses.COINFLIP`.

#### `OnlyGame` (error)
Thrown when `msg.sender` is not `ContractAddresses.GAME`.

#### `onlyCoin()` (modifier)

| Field | Value |
|-------|-------|
| **Guard** | `msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP` |
| **Reverts** | `OnlyCoin()` |

**NatSpec Accuracy:** NatSpec says "Restricts function to coin or coinflip contract" which matches the implementation. The `@custom:reverts` says "When caller is not the coin or coinflip contract" -- accurate.

**Verdict:** CORRECT

#### `onlyGame()` (modifier)

| Field | Value |
|-------|-------|
| **Guard** | `msg.sender != ContractAddresses.GAME` |
| **Reverts** | `OnlyGame()` |

**NatSpec Accuracy:** Accurate.

**Verdict:** CORRECT

---

### External -- Recording

### `recordBafFlip(address player, uint24 lvl, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address; `lvl` (uint24): current game level / BAF bracket; `amount` (uint256): raw coinflip stake amount |
| **Returns** | none |
| **Modifiers** | `onlyCoin` |

**State Reads:**
- `bafTotals[lvl][player]` -- current accumulated total for this player at this level

**State Writes:**
- `bafTotals[lvl][player]` -- updated with `total + amount`
- `bafTop[lvl]` -- via `_updateBafTop` (leaderboard entries)
- `bafTopLen[lvl]` -- via `_updateBafTop` (leaderboard length)

**Callers:** BurnieCoin contract (external, via `onlyCoin` modifier). Also BurnieCoinflip contract.

**Callees:**
- `_updateBafTop(lvl, player, total)` -- updates leaderboard

**ETH Flow:** None. No ETH is sent or received.

**Invariants:**
- `bafTotals[lvl][player]` is monotonically non-decreasing (only adds, never subtracts)
- After call, player's total equals previous total + amount
- If player is the VAULT address, function returns early (no state change)
- Leaderboard remains sorted descending by score after update

**NatSpec Accuracy:** NatSpec says "Record a coinflip stake for BAF leaderboard tracking. Called by coin contract on every manual coinflip. Silently ignores vault address." This is accurate. The `@custom:access` correctly notes `onlyCoin` restriction.

**Gas Flags:**
- `unchecked { total += amount; }` -- comment says "reasonable values won't overflow uint256". Given that `amount` is a coinflip stake in wei, overflow of uint256 is practically impossible. Safe.

**Verdict:** CORRECT

---

### External -- Jackpot Execution

### `runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function runBafJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) external override onlyGame returns (address[] memory winners, uint256[] memory amounts, uint256 winnerMask, uint256 returnAmountWei)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `poolWei` (uint256): total ETH prize pool; `lvl` (uint24): level being resolved; `rngWord` (uint256): VRF-derived randomness seed |
| **Returns** | `winners` (address[]): winner addresses; `amounts` (uint256[]): prize amounts; `winnerMask` (uint256): bitmask for scatter ticket routing; `returnAmountWei` (uint256): unawarded amount |
| **Modifiers** | `onlyGame` |

**State Reads:**
- `bafTop[lvl]` -- via `_bafTop(lvl, 0)`, `_bafTop(lvl, pick)` for leaderboard positions
- `bafTopLen[lvl]` -- via `_bafTop` and `_clearBafTop`
- `bafTotals[lvl][player]` -- via `_bafScore` for far-future and scatter scoring

**State Writes:**
- `bafTop[lvl]` -- deleted via `_clearBafTop`
- `bafTopLen[lvl]` -- deleted via `_clearBafTop`
- Note: `bafTotals` is NOT cleared (historical data preserved)

**Callers:** DegenerusGame contract (via `onlyGame` modifier), specifically through JackpotModule delegatecall.

**Callees:**
- `_bafTop(lvl, 0)` -- get #1 BAF bettor
- `_bafTop(lvl, pick)` -- get #3 or #4 BAF bettor (random pick)
- `coin.coinflipTopLastDay()` -- external call to COINFLIP for last-24h top bettor
- `_creditOrRefund(...)` -- memory buffer write helper (pure)
- `affiliate.affiliateTop(uint24(lvl - offset))` -- external call to Affiliate for top referrers per level
- `_bafScore(player, lvl)` -- BAF score lookup for affiliate candidates
- `degenerusGame.sampleFarFutureTickets(entropy)` -- external call to Game for far-future ticket holders
- `_bafScore(cand, lvl)` -- scoring far-future and scatter candidates
- `degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy)` -- external call to Game for trait ticket sampling
- `_clearBafTop(lvl)` -- cleanup after resolution

**ETH Flow:** None directly. This function computes winners and amounts, returning them as arrays. The calling game contract (JackpotModule) handles actual ETH transfers using the returned data.

**Prize Distribution Logic (verified):**

| Slice | Share | Source | Selection Method |
|-------|-------|--------|------------------|
| A: Top BAF | 10% (`P / 10`) | `_bafTop(lvl, 0)` | Deterministic: highest BAF bettor |
| A2: Top Coinflip | 10% (`P / 10`) | `coin.coinflipTopLastDay()` | Deterministic: highest 24h coinflip bettor |
| B: Random Pick | 5% (`P / 20`) | `_bafTop(lvl, 2 or 3)` | Pseudo-random: entropy LSB selects 3rd or 4th |
| C: Affiliate | 10% (`P / 10`) | Top affiliates from past 20 levels | Shuffle + sort by BAF score; 5/3/2/0 split |
| D: Far-Future | 5% (3% + 2%) | `sampleFarFutureTickets` | Top 2 by BAF score from sampled set |
| E: Scatter 1st | 40% (`P * 2 / 5`) | `sampleTraitTicketsAtLevel` | 50 rounds x 4 tickets, best per round |
| E2: Scatter 2nd | 20% (`P / 5`) | `sampleTraitTicketsAtLevel` | 50 rounds x 4 tickets, second per round |

Total: 100% (10 + 10 + 5 + 10 + 5 + 40 + 20 = 100)

**Scatter Level Targeting:**
- Non-century levels: 20 rounds at lvl+1, 10 at lvl+2, 10 at lvl+3, 10 at lvl+4
- Century levels (lvl % 100 == 0): 4 at lvl+1, 4 at lvl+2, 4 at lvl+3, 38 random from past 99

**Winner Mask Logic:**
- After scatter processing, the last `BAF_SCATTER_TICKET_WINNERS` (40) scatter entries get mask bits set
- Bits are set at positions `BAF_SCATTER_MASK_OFFSET + idx` (128 + idx)
- The mask is computed from the end of the scatter array backwards, flagging the last 40 (or fewer) entries

**Entropy Chaining:** Each random selection uses `entropy = keccak256(entropy, salt)` with incrementing salt, ensuring independence of random decisions from a single VRF word.

**Invariants:**
- Sum of all awarded amounts + returnAmountWei == poolWei (conservation of prize pool)
- After execution, leaderboard for `lvl` is cleared (bafTop and bafTopLen deleted)
- Maximum 108 winners (1 + 1 + 1 + 3 + 2 + 50 + 50)
- All unfilled slots contribute to `toReturn`

**NatSpec Accuracy:** NatSpec is comprehensive and accurate. Prize distribution percentages in the banner comment match code. The `@custom:access` correctly notes `onlyGame` restriction.

**Gas Flags:**
- 50 rounds of scatter sampling with external calls (`sampleTraitTicketsAtLevel`) is gas-intensive but bounded by `BAF_SCATTER_ROUNDS = 50`
- 20 iterations for affiliate candidate collection with external calls to `affiliate.affiliateTop`
- Assembly `mstore` to trim array length is safe and gas-efficient
- Affiliate dedup loop is O(n^2) but bounded by n <= 20, acceptable

**Conservation Verification:**
Let P = poolWei. Slices allocated:
- Slice A: P/10
- Slice A2: P/10
- Slice B: P/20
- Slice C: P/10 (affiliateSlice = sum of affiliatePrizes[0..2])
- Slice D: P*3/100 + P/50 = 3P/100 + 2P/100 = 5P/100 = P/20
- Slice E: P*2/5
- Slice E2: P/5

Total = P/10 + P/10 + P/20 + P/10 + P/20 + 2P/5 + P/5
      = 2P/20 + 2P/20 + P/20 + 2P/20 + P/20 + 8P/20 + 4P/20
      = 20P/20 = P

Rounding: Due to integer division, small dust amounts (< winner count) in scatter slices are added to `toReturn`. This is correct.

**Affiliate 4th Prize:** `affiliatePrizes[3]` is never set (remains 0). The weights are 5/3/2/0 as documented. The 4th affiliate winner receives 0 ETH. `affiliateSlice` sums only indices [0..2], so the unallocated portion (if paid < affiliateSlice) returns correctly.

**Verdict:** CORRECT

---

### Private -- ETH Payout

### `_creditOrRefund(address candidate, uint256 prize, address[] memory winnersBuf, uint256[] memory amountsBuf, uint256 idx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditOrRefund(address candidate, uint256 prize, address[] memory winnersBuf, uint256[] memory amountsBuf, uint256 idx) private pure returns (bool credited)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `candidate` (address): potential winner; `prize` (uint256): prize amount in wei; `winnersBuf` (address[]): pre-allocated winners array; `amountsBuf` (uint256[]): pre-allocated amounts array; `idx` (uint256): current write index |
| **Returns** | `credited` (bool): true if winner was credited |

**State Reads:** None (pure function)

**State Writes:** None (pure function, only writes to memory arrays)

**Callers:**
- `runBafJackpot` -- Slices A, A2, B, D (far-future 1st and 2nd)

**Callees:** None

**ETH Flow:** None. Despite the name suggesting ETH credit/refund, this is a pure memory-buffer helper. It writes winner address and prize amount to pre-allocated memory arrays if the candidate is eligible (non-zero address and non-zero prize). The actual ETH distribution happens in the game contract.

**Invariants:**
- Returns `false` if prize == 0 OR candidate == address(0)
- Returns `true` and writes to buffers only if both prize > 0 AND candidate != address(0)
- Never modifies storage

**NatSpec Accuracy:** NatSpec says "Credit prize to non-zero winner or return false for refund. Writes to preallocated buffers if winner is valid." The name `_creditOrRefund` is slightly misleading (implies ETH transfer) but the NatSpec clarifies it operates on buffers. The plan's context reference to "BurnieCoin.creditCoin fallback payout" is incorrect for this contract -- this function does not interact with BurnieCoin at all.

**Gas Flags:** None. Simple conditional writes to memory.

**Verdict:** CORRECT -- Note: The function name is misleading (no ETH/credit operations), but functionally correct as a buffer-write helper.

---

### Private -- Score / Leaderboard

### `_bafScore(address player, uint24 lvl)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _bafScore(address player, uint24 lvl) private view returns (uint256)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): address to query; `lvl` (uint24): level number |
| **Returns** | uint256: accumulated coinflip total (0 if no activity) |

**State Reads:**
- `bafTotals[lvl][player]` -- accumulated coinflip stake

**State Writes:** None (view function)

**Callers:**
- `runBafJackpot` -- affiliate candidate scoring, far-future ticket scoring, scatter ticket scoring

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Returns 0 for players with no recorded flips at the given level
- Returns the exact value stored in `bafTotals[lvl][player]`

**NatSpec Accuracy:** NatSpec says "Get player's BAF score for a level" and returns "Accumulated coinflip total (0 if player not in this level)." Accurate.

**Gas Flags:** None. Single storage read.

**Verdict:** CORRECT

---

### `_score96(uint256 s)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _score96(uint256 s) private pure returns (uint96)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `s` (uint256): raw score in base units (wei) |
| **Returns** | uint96: capped score in whole tokens |

**State Reads:** None (pure)

**State Writes:** None (pure)

**Callers:**
- `_updateBafTop` -- converts raw stake to uint96 for leaderboard storage

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Output is always <= type(uint96).max
- Divides by 1 ether (1e18) to convert from wei to whole tokens
- Cap at uint96.max (~79.2 billion tokens) prevents overflow when storing in PlayerScore struct

**NatSpec Accuracy:** NatSpec says "Convert raw score to capped uint96 (whole tokens only)." Accurate.

**Gas Flags:** None. Pure arithmetic.

**Verdict:** CORRECT

---

### `_updateBafTop(uint24 lvl, address player, uint256 stake)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _updateBafTop(uint24 lvl, address player, uint256 stake) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level number; `player` (address): player address; `stake` (uint256): new total stake |
| **Returns** | none |

**State Reads:**
- `bafTop[lvl]` -- entire 4-entry leaderboard array
- `bafTopLen[lvl]` -- current leaderboard length

**State Writes:**
- `bafTop[lvl][i]` -- leaderboard entries (insert, swap, overwrite)
- `bafTopLen[lvl]` -- incremented when new entry added (Case 2 only)

**Callers:**
- `recordBafFlip` -- after accumulating new total

**Callees:**
- `_score96(stake)` -- converts raw stake to uint96

**ETH Flow:** None

**Logic Walkthrough:**

1. **Search phase:** Scans leaderboard (0 to `len`) for existing `player` entry. Uses sentinel `existing = 4` for "not found".

2. **Case 1 (existing < 4):** Player already on board.
   - If new score <= current score, early return (no improvement due to whole-token truncation).
   - Update score in-place, then bubble-up: swap with predecessor while score is higher. Maintains sorted order.

3. **Case 2 (len < 4):** Board not full, player not on board.
   - Find insertion point by shifting entries right while new score > predecessor's score.
   - Insert at correct position. Increment `bafTopLen[lvl]`.

4. **Case 3 (len == 4):** Board full, player not on board.
   - If new score <= board[3].score (lowest), early return.
   - Otherwise, shift entries right from position 3 upward while new score > predecessor. Insert new entry, effectively evicting the old #4.

**Invariants:**
- Leaderboard is always sorted descending by score after any update
- Length never exceeds 4
- No duplicate players on the leaderboard (search before insert)
- A player's score on the board can only increase (early return on no improvement)

**NatSpec Accuracy:** NatSpec says "Update top-4 BAF leaderboard with new stake. Maintains sorted order. Handles existing player update, new player insertion, and capacity management." Accurate and complete.

**Gas Flags:**
- Worst case: 4 storage reads (search) + 3 storage writes (shift + insert) + 1 storage write (length). Acceptable for a bounded-4 leaderboard.
- Case 1 "no improvement" early return avoids unnecessary writes when score truncation hasn't changed the uint96 value.

**Verdict:** CORRECT

---

### `_bafTop(uint24 lvl, uint8 idx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _bafTop(uint24 lvl, uint8 idx) private view returns (address player, uint96 score)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): level number; `idx` (uint8): position (0 = top) |
| **Returns** | `player` (address): player at position; `score` (uint96): player's score |

**State Reads:**
- `bafTopLen[lvl]` -- current leaderboard length
- `bafTop[lvl][idx]` -- leaderboard entry (only if idx < len)

**State Writes:** None (view)

**Callers:**
- `runBafJackpot` -- Slice A (idx=0), Slice B (idx=2 or 3)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Returns (address(0), 0) if idx >= len (safe bounds check)
- Returns actual stored entry otherwise

**NatSpec Accuracy:** NatSpec says "Get player at leaderboard position. Position 0 = top. Returns address(0) if empty." Accurate.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_clearBafTop(uint24 lvl)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _clearBafTop(uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): level number |
| **Returns** | none |

**State Reads:**
- `bafTopLen[lvl]` -- to know how many entries to delete

**State Writes:**
- `bafTopLen[lvl]` -- deleted (set to 0)
- `bafTop[lvl][i]` for i in 0..len-1 -- each entry deleted

**Callers:**
- `runBafJackpot` -- at end of jackpot resolution

**Callees:** None

**ETH Flow:** None

**Invariants:**
- After execution, `bafTopLen[lvl]` == 0 and all `bafTop[lvl][i]` entries are zeroed
- Note: `bafTotals` is NOT cleared (accumulated stakes persist beyond jackpot resolution)
- If len is already 0, only the delete of bafTopLen is skipped (no-op guard), but the loop body does not execute either

**NatSpec Accuracy:** NatSpec says "Clear leaderboard state for a level after jackpot resolution." Accurate.

**Gas Flags:**
- `delete bafTopLen[lvl]` only executes when `len != 0`, saving the SSTORE when already zero. Good optimization.
- Loop deletes each entry individually. Maximum 4 iterations (bounded).

**Verdict:** CORRECT

---

### Struct: `PlayerScore`

| Field | Value |
|-------|-------|
| **player** | address (160 bits) |
| **score** | uint96 (96 bits) |
| **Total** | 256 bits (1 storage slot) |

Efficient single-slot packing. Used in `bafTop` mapping for leaderboard entries.

**Verdict:** CORRECT

---

### Constants

| Constant | Value | Usage |
|----------|-------|-------|
| `BAF_SCATTER_MASK_OFFSET` | 128 | Bit offset for scatter winner flags in winnerMask |
| `BAF_SCATTER_TICKET_WINNERS` | 40 | Number of scatter winners receiving ticket routing |
| `BAF_SCATTER_ROUNDS` | 50 | Fixed number of scatter sampling rounds |

**Verdict:** CORRECT -- Values are consistent with their usage in `runBafJackpot`.

---

### Events

#### `BafFlipRecorded(address indexed player, uint24 indexed lvl, uint256 amount, uint256 newTotal)`

Emitted by `recordBafFlip` after accumulating stake and updating leaderboard. Parameters match function semantics. Both `player` and `lvl` are indexed for efficient filtering.

**Verdict:** CORRECT

---

### Local Interface: `IDegenerusCoinJackpotView`

| Field | Value |
|-------|-------|
| **Method** | `coinflipTopLastDay() external view returns (address player, uint96 score)` |
| **Used by** | `runBafJackpot` (Slice A2) |
| **Target** | COINFLIP contract (`ContractAddresses.COINFLIP`) |

Defines a minimal view interface for querying the top coinflip bettor from the last 24-hour window. Note: the constant `coin` is typed as `IDegenerusCoinJackpotView` pointing to `ContractAddresses.COINFLIP`, not `ContractAddresses.COIN`. This is correct -- the coinflip contract tracks per-day betting activity.

**Verdict:** CORRECT
