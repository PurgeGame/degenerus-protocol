# DegenerusGame.sol -- View Functions Audit

**Contract:** DegenerusGame
**File:** contracts/DegenerusGame.sol
**Lines audited:** 2027-2810
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Audit date:** 2026-03-07

## Summary

All view and pure functions providing the external read interface: prize pool balances, RNG state, game phase, player mint stats, activity scores, ticket sampling, and degenerette queries. No state mutations. Focus is on return value correctness and NatSpec accuracy.

## Function Audit

### `prizePoolTargetView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function prizePoolTargetView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The ratchet target for level progression (ETH wei) |

**State Reads:** `levelPrizePool[level]`, `level`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "next-pool ratchet target" -- matches behavior. Returns `levelPrizePool[level]` which is the previous level's captured pool (snapshot taken at level transition). Falls back to `BOOTSTRAP_PRIZE_POOL` (50 ETH) if zero. NatSpec accurately describes the threshold check against `levelPrizePool[level]`.
**Gas Flags:** None -- minimal reads.
**Verdict:** CORRECT

---

### `nextPrizePoolView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function nextPrizePoolView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The nextPrizePool value (ETH wei) |

**State Reads:** `nextPrizePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "prize pool accumulated for the next level" -- correct. `nextPrizePool` accumulates mint fees toward the target.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `futurePrizePoolView(uint24)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function futurePrizePoolView(uint24 lvl) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Unused; retained for interface compatibility |
| **Returns** | `uint256`: The futurePrizePool value (ETH wei) |

**State Reads:** `futurePrizePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "unified future pool reserve" and notes `lvl` is unused but retained for compatibility -- accurate. The `lvl;` statement silences the unused parameter compiler warning.
**Gas Flags:** None -- single SLOAD, unused param is free (no storage read).
**Verdict:** CORRECT

---

### `futurePrizePoolTotalView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function futurePrizePoolTotalView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The futurePrizePool value (ETH wei) |

**State Reads:** `futurePrizePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "aggregate future pool reserve" -- correct. Returns the same unified `futurePrizePool` as `futurePrizePoolView`. Functionally identical to `futurePrizePoolView` but without the unused parameter.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `ticketsOwedView(uint24, address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function ticketsOwedView(uint24 lvl, address player) external view returns (uint32)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Target level; `player` (address): Player address |
| **Returns** | `uint32`: Number of whole ticket rewards owed |

**State Reads:** `ticketsOwedPacked[lvl][player]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "queued future ticket rewards owed for a level" -- correct. Notes that fractional remainder resolves at batch time, which is accurate since the lower 8 bits store the remainder and only the upper 32 bits (whole tickets) are returned via `>> 8`.
**Gas Flags:** None -- single nested mapping SLOAD.
**Verdict:** CORRECT

---

### `lootboxStatus(address, uint48)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lootboxStatus(address player, uint48 lootboxIndex) external view returns (uint256 amount, bool presale)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address; `lootboxIndex` (uint48): RNG index |
| **Returns** | `amount` (uint256): ETH amount in wei; `presale` (bool): Whether presale is currently active |

**State Reads:** `lootboxEth[lootboxIndex][player]`, `lootboxPresaleActive`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "loot box status for a player/index" -- correct. The `presale` return reflects current presale state (not whether this specific lootbox was bought during presale). This semantic distinction is noted in the Phase 55 interface audit as an informational. The amount extraction masks the lower 232 bits, which matches the packed layout in storage (`[232 bits: amount] [24 bits: purchase level]`).
**Gas Flags:** None -- two SLOADs, mask is compile-time constant.
**Verdict:** CORRECT

---

### `degeneretteBetInfo(address, uint64)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function degeneretteBetInfo(address player, uint64 betId) external view returns (uint256 packed)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address; `betId` (uint64): Bet identifier |
| **Returns** | `packed` (uint256): Raw packed bet data |

**State Reads:** `degeneretteBets[player][betId]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "View Degenerette packed bet info for a player/betId" -- accurate. Returns the raw packed uint256 which consumers must unpack. The NatSpec parameter description labels `betId` as `uint24` in the plan but the actual signature uses `uint64` -- function signature is correct per storage declaration.
**Gas Flags:** None -- single nested mapping SLOAD.
**Verdict:** CORRECT

---

### `lootboxPresaleActiveFlag()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lootboxPresaleActiveFlag() external view returns (bool active)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `active` (bool): True if presale is active |

**State Reads:** `lootboxPresaleActive`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "Check whether lootbox presale mode is currently active" -- correct.
**Gas Flags:** None -- single SLOAD (bool shares slot packing in storage but EVM loads full slot).
**Verdict:** CORRECT

---

### `lootboxRngIndexView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lootboxRngIndexView() external view returns (uint48 index)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `index` (uint48): Current lootbox RNG index (1-based) |

**State Reads:** `lootboxRngIndex`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "current lootbox RNG index for new purchases" -- correct. Storage initializes to 1 so it is 1-based as documented.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `lootboxRngWord(uint48)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lootboxRngWord(uint48 lootboxIndex) external view returns (uint256 word)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `lootboxIndex` (uint48): RNG index to query |
| **Returns** | `word` (uint256): VRF random word (0 if not yet fulfilled) |

**State Reads:** `lootboxRngWordByIndex[lootboxIndex]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "VRF random word for a lootbox RNG index" and "(0 if not ready)" -- correct. Mapping returns default 0 for unfulfilled indices.
**Gas Flags:** None -- single mapping SLOAD.
**Verdict:** CORRECT

---

### `lootboxRngThresholdView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lootboxRngThresholdView() external view returns (uint256 threshold)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `threshold` (uint256): ETH threshold that triggers RNG request |

**State Reads:** `lootboxRngThreshold`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "lootbox RNG request threshold (wei)" -- correct. Default is 1 ether per storage declaration.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `lootboxRngMinLinkBalanceView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lootboxRngMinLinkBalanceView() external view returns (uint256 minBalance)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `minBalance` (uint256): Minimum LINK balance required |

**State Reads:** `lootboxRngMinLinkBalance`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "minimum LINK balance required for manual lootbox RNG rolls" -- correct. Default is 14 ether (14 LINK) per storage declaration.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `currentPrizePoolView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function currentPrizePoolView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The currentPrizePool value (ETH wei) |

**State Reads:** `currentPrizePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "current prize pool (jackpots are paid from this)" -- correct. This is the active level's prize pool from which daily jackpots draw.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `rewardPoolView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function rewardPoolView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The futurePrizePool value (ETH wei) |

**State Reads:** `futurePrizePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "unified future pool (reserve for jackpots and carryover)" -- INFORMATIONAL: function named `rewardPoolView` returns `futurePrizePool`, not a separate "reward pool". This is because reward and future pools were unified. NatSpec accurately says "futurePrizePool" in the return doc. The function name is a legacy alias.
**Gas Flags:** None -- single SLOAD. Returns same value as `futurePrizePoolView`/`futurePrizePoolTotalView`.
**Verdict:** CORRECT (informational: function name is legacy alias)

---

### `claimablePoolView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function claimablePoolView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The claimablePool value (ETH wei) |

**State Reads:** `claimablePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "claimable pool (reserved for player winnings claims)" -- correct.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `yieldPoolView()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function yieldPoolView() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: The yield surplus value (ETH wei) |

**State Reads:** `address(this).balance`, `steth.balanceOf(address(this))`, `currentPrizePool`, `nextPrizePool`, `claimablePool`, `futurePrizePool`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "yield surplus (stETH appreciation above all pool obligations)" -- correct. Dev comment describes calculation as `(ETH balance + stETH balance) - (current + next + claimable + future pools)` which exactly matches the code. Returns 0 if balance <= obligations to prevent underflow.
**Gas Flags:** 6 reads (4 SLOADs + 1 balance + 1 external call to stETH). The external `steth.balanceOf()` call is the most expensive. Acceptable for a view function.
**Verdict:** CORRECT

---

### `mintPrice()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function mintPrice() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: Current mint price in wei |

**State Reads:** `price`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "current mint price in wei" with price tiers "intro 0.01/0.02, then cycle 0.04/0.08/0.12/0.24 ETH" -- partially accurate. The actual PriceLookupLib defines 0.04/0.08/0.12/0.16/0.24 ETH cycle tiers, but the NatSpec omits 0.16 ETH (x90-x99 range). This is an NatSpec informational only -- the function correctly returns the stored `price` variable which is set by game logic.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT (informational: NatSpec omits 0.16 ETH tier from price description)

---

### `rngWordForDay(uint48)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function rngWordForDay(uint48 day) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `day` (uint48): Day index to query |
| **Returns** | `uint256`: Random word (0 if none recorded) |

**State Reads:** `rngWordByDay[day]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "VRF random word recorded for a specific day" with "day 1 = deploy day" and "0 if no word recorded" -- correct. Mapping returns default 0 for days without recorded words.
**Gas Flags:** None -- single mapping SLOAD.
**Verdict:** CORRECT

---

### `lastRngWord()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lastRngWord() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: Random word for the most recent day (0 if none) |

**State Reads:** `rngWordByDay[dailyIdx]`, `dailyIdx`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "most recently recorded RNG word" using `dailyIdx` -- correct. `dailyIdx` is the monotonic day counter incremented during game progression.
**Gas Flags:** None -- 2 SLOADs (dailyIdx + mapping lookup).
**Verdict:** CORRECT

---

### `rngLocked()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function rngLocked() external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: True if RNG lock is active |

**State Reads:** `rngLockedFlag`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "RNG is currently locked (daily jackpot resolution)" and "When locked, burns and certain operations are blocked" -- correct.
**Gas Flags:** None -- single SLOAD (bool packs in slot 1).
**Verdict:** CORRECT

---

### `isRngFulfilled()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function isRngFulfilled() external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: True if random word is available |

**State Reads:** `rngWordCurrent`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "VRF has been fulfilled for current request" -- correct. `rngWordCurrent != 0` indicates fulfillment since 0 is the "pending" sentinel value.
**Gas Flags:** None -- single SLOAD with comparison.
**Verdict:** CORRECT

---

### `_threeDayRngGap(uint48)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _threeDayRngGap(uint48 day) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `day` (uint48): Day index to check from |
| **Returns** | `bool`: True if day, day-1, day-2 all have no VRF word |

**State Reads:** `rngWordByDay[day]`, `rngWordByDay[day-1]`, `rngWordByDay[day-2]`
**Callers:** `rngStalledForThreeDays()` (this contract), `_threeDayRngGap` in AdvanceModule (separate declaration)
**NatSpec Accuracy:** NatSpec says "3-consecutive-day gap in VRF words" and "Used to detect VRF coordinator failures" -- correct. Early return `if (day < 2)` prevents underflow on day-2 subtraction, returning false which is correct (can't have 3-day gap with fewer than 3 days).
**Gas Flags:** Up to 3 SLOADs in worst case (all zero). Short-circuits on first non-zero word found.
**Verdict:** CORRECT

---

### `rngStalledForThreeDays()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function rngStalledForThreeDays() external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: True if no VRF word recorded for last 3 day slots |

**State Reads:** Via `_threeDayRngGap(_simulatedDayIndex())` -- reads `rngWordByDay[day]`, `rngWordByDay[day-1]`, `rngWordByDay[day-2]`, and calls `GameTimeLib.currentDayIndex()`.
**Callers:** External (UI/Admin for VRF coordinator rotation check)
**NatSpec Accuracy:** NatSpec says "VRF has stalled for 3 consecutive days" and "Enables emergency VRF coordinator rotation via updateVrfCoordinatorAndSub()" -- correct.
**Gas Flags:** None -- delegates to `_threeDayRngGap` which short-circuits.
**Verdict:** CORRECT

---

### `decWindow()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function decWindow() external view returns (bool on, uint24 lvl)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `on` (bool): True if decimator entries allowed; `lvl` (uint24): Current game level |

**State Reads:** `level`, `decWindowOpen`, `lastPurchaseDay`, `rngLockedFlag`, plus reads via `_isGameoverImminent()` (`gameOver`, `levelStartTime`, `block.timestamp`, `level`)
**Callers:** External (UI/frontend for decimator entry UI)
**NatSpec Accuracy:** NatSpec describes window conditions accurately: "on" if flag is set OR gameover imminent, with RNG lock blocking during lastPurchaseDay (when jackpots resolve). The explanation of x5 vs x00 level gate behavior is correct.
**Gas Flags:** Multiple reads from slot 0 and slot 1 -- both packed slots so 2 SLOADs total for `level`, `decWindowOpen`, `lastPurchaseDay`, `rngLockedFlag`, `jackpotPhaseFlag`, plus `_isGameoverImminent()` reads. Efficient.
**Verdict:** CORRECT

---

### `decWindowOpenFlag()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function decWindowOpenFlag() external view returns (bool open)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `open` (bool): True if decimator window flag is set or gameover imminent |

**State Reads:** `decWindowOpen`, plus `_isGameoverImminent()` reads
**Callers:** External (UI/frontend)
**NatSpec Accuracy:** NatSpec says "Raw check of decimator window flag (ignores RNG lock)" -- correct. This does NOT check the `lastPurchaseDay && rngLockedFlag` gate that `decWindow()` applies.
**Gas Flags:** None -- same reads as `_isGameoverImminent()` plus one slot-1 read.
**Verdict:** CORRECT

---

### `isCompressedJackpot()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function isCompressedJackpot() external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: True if compressed jackpot phase is active |

**State Reads:** `compressedJackpotFlag`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "current jackpot phase is compressed (3 days instead of 5)" -- correct per storage documentation.
**Gas Flags:** None -- single SLOAD (bool in slot 1).
**Verdict:** CORRECT

---

### `_isGameoverImminent()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _isGameoverImminent() private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: True if gameover would trigger within ~10 days |

**State Reads:** `gameOver`, `levelStartTime`, `block.timestamp`, `level`
**Callers:** `decWindow()`, `decWindowOpenFlag()` (this contract)
**NatSpec Accuracy:** NatSpec says "True when gameover would trigger within ~10 days" and "Used to allow decimator burns near liveness timeout" -- correct. At level 0, uses `DEPLOY_IDLE_TIMEOUT_DAYS` (912 days). At level 1+, uses 365 days. Returns false if `gameOver` is already true (terminal state).
**Gas Flags:** None -- reads from slot 0 and slot 1 (2 packed SLOADs max) plus `block.timestamp`.
**Verdict:** CORRECT

---

### `_activeTicketLevel()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _activeTicketLevel() private view returns (uint24)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint24`: Active ticket level for direct ticket purchases |

**State Reads:** `jackpotPhaseFlag`, `level`
**Callers:** `purchaseInfo()`, `ethMintStreakCount()`, `ethMintStats()`, `_playerActivityScore()` (this contract)
**NatSpec Accuracy:** NatSpec says "During jackpot phase, direct tickets target the current level. During purchase phase, direct tickets target the next level." -- correct. `jackpotPhaseFlag ? level : level + 1` matches this description.
**Gas Flags:** None -- reads from slot 0 (1 packed SLOAD).
**Verdict:** CORRECT

---

### `jackpotPhase()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function jackpotPhase() external view returns (bool)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: True if jackpot phase is active |

**State Reads:** `jackpotPhaseFlag`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "Returns true when jackpot phase is active" -- correct.
**Gas Flags:** None -- single SLOAD (bool in slot 0).
**Verdict:** CORRECT

---

### `purchaseInfo()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function purchaseInfo() external view returns (uint24 lvl, bool inJackpotPhase, bool lastPurchaseDay_, bool rngLocked_, uint256 priceWei)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `lvl` (uint24): Active direct-ticket level; `inJackpotPhase` (bool): Jackpot phase active; `lastPurchaseDay_` (bool): Prize target met; `rngLocked_` (bool): VRF pending; `priceWei` (uint256): Current mint price |

**State Reads:** `jackpotPhaseFlag`, `lastPurchaseDay`, `level`, `rngLockedFlag`, `price` (via `_activeTicketLevel()` also reads `jackpotPhaseFlag` and `level` -- same packed slot, no extra cost)
**Callers:** External (UI/frontend for purchase flow)
**NatSpec Accuracy:** NatSpec accurately describes all return values. Key detail: `lvl` is the active direct-ticket level (level+1 during purchase phase, level during jackpot phase). `lastPurchaseDay_` is AND-gated with `!inJackpotPhase` -- only true during purchase phase when target is met. This is correct: during jackpot phase, `lastPurchaseDay` storage value is irrelevant.
**Gas Flags:** Reads from slots 0 (level, jackpotPhaseFlag, rngLockedFlag), 1 (lastPurchaseDay), and 2 (price) = 3 SLOADs. Efficient for 5 return values.
**Verdict:** CORRECT

---

### `lastPurchaseDayFlipTotals()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function lastPurchaseDayFlipTotals() external view returns (uint256 prevTotal, uint256 currentTotal)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `prevTotal` (uint256): Previous level's flip deposits; `currentTotal` (uint256): Current level's flip deposits |

**State Reads:** `lastPurchaseDayFlipTotalPrev`, `lastPurchaseDayFlipTotal`
**Callers:** External (BurnieCoinflip for payout tuning)
**NatSpec Accuracy:** NatSpec says "last-purchase-day coinflip totals for payout tuning" -- correct.
**Gas Flags:** None -- 2 SLOADs.
**Verdict:** CORRECT

---

### `ethMintLastLevel(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function ethMintLastLevel(address player) external view returns (uint24)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `uint24`: Last level where player minted with ETH (0 if never) |

**State Reads:** `deityPassCount[player]`, `mintPacked_[player]`, `level`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "last level where player minted with ETH" -- correct. Deity pass holders always return current `level` (they are treated as always having minted). Non-deity players extract from `mintPacked_` using `BitPackingLib.LAST_LEVEL_SHIFT` and `MASK_24` -- bits [0-23], correct per layout.
**Gas Flags:** 2-3 SLOADs depending on deity pass check short-circuit.
**Verdict:** CORRECT

---

### `ethMintLevelCount(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function ethMintLevelCount(address player) external view returns (uint24)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `uint24`: Number of distinct levels with ETH mints |

**State Reads:** `deityPassCount[player]`, `mintPacked_[player]`, `level`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "total count of levels where player minted with ETH" -- correct. Deity pass holders return current `level`. Non-deity players extract from `mintPacked_` using `LEVEL_COUNT_SHIFT` (bits 24-47) -- correct per layout.
**Gas Flags:** Same as `ethMintLastLevel` -- 2-3 SLOADs.
**Verdict:** CORRECT

---

### `ethMintStreakCount(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function ethMintStreakCount(address player) external view returns (uint24)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `uint24`: Number of consecutive levels with ETH mints |

**State Reads:** `deityPassCount[player]`, `level`, plus via `_mintStreakEffective()`: `mintPacked_[player]` (bits MINT_STREAK_LAST_COMPLETED_SHIFT [160-183], LEVEL_STREAK_SHIFT [48-71]), and via `_activeTicketLevel()`: `jackpotPhaseFlag`, `level`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "player's current consecutive ETH mint streak" -- correct. Deity pass holders return current `level`. Non-deity players use `_mintStreakEffective(player, _activeTicketLevel())` which resets streak if a level was missed (i.e., `currentMintLevel > lastCompleted + 1`).
**Gas Flags:** More complex than other mint stat functions due to `_mintStreakEffective` call, but still lightweight (2-3 SLOADs).
**Verdict:** CORRECT

---

### `ethMintStats(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function ethMintStats(address player) external view returns (uint24 lvl, uint24 levelCount, uint24 streak)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `lvl` (uint24): Current game level; `levelCount` (uint24): Total levels with ETH mints; `streak` (uint24): Consecutive level streak |

**State Reads:** `deityPassCount[player]`, `level`, `mintPacked_[player]`, `jackpotPhaseFlag` (via `_activeTicketLevel()`)
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "combined mint statistics for a player" and "batches multiple stats into single call for gas efficiency" -- correct. Deity pass holders return `(currLevel, currLevel, currLevel)` for all three. Non-deity path correctly unpacks `levelCount` from `mintPacked_` and uses `_mintStreakEffective` for streak.
**Gas Flags:** Gas-efficient batching of 3 values that would otherwise require 3 separate external calls. Single `mintPacked_` SLOAD reused for multiple fields.
**Verdict:** CORRECT

---

### `playerActivityScore(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function playerActivityScore(address player) external view returns (uint256 scoreBps)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `scoreBps` (uint256): Total activity score in basis points |

**State Reads:** Delegates to `_playerActivityScore(player)` -- see below.
**Callers:** External only (UI/frontend, lootbox/decimator/degenerette modules read via internal `_playerActivityScore`)
**NatSpec Accuracy:** NatSpec gives detailed breakdown: "50% (streak) + 25% (count) + 100% (quest) + 50% (affiliate) + 40% (whale) = 265% max" and "Deity pass adds +80% in place of whale bundle bonus (305% max base)" -- matches code. Consumer caps mentioned (lootbox 255%, degenerette 305%, decimator 235%) are informational and not enforced here.
**Gas Flags:** See `_playerActivityScore` below.
**Verdict:** CORRECT

---

### `_playerActivityScore(address)` [internal view]

| Field | Value |
|-------|-------|
| **Signature** | `function _playerActivityScore(address player) internal view returns (uint256 scoreBps)` |
| **Visibility** | internal |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `scoreBps` (uint256): Total activity score in basis points |

**State Reads:** `deityPassCount[player]`, `mintPacked_[player]` (LEVEL_COUNT_SHIFT, FROZEN_UNTIL_LEVEL_SHIFT, WHALE_BUNDLE_TYPE_SHIFT), `level`, `jackpotPhaseFlag` (via `_activeTicketLevel`), `mintPacked_[player]` again (via `_mintStreakEffective` -- same SLOAD cached by optimizer). External calls: `questView.playerQuestStates(player)`, `affiliate.affiliateBonusPointsBest(currLevel, player)`.
**Callers:** `playerActivityScore()` (this contract), internal callers in modules via delegatecall
**NatSpec Accuracy:** Function computes correctly:
- **Deity pass path**: 50*100 + 25*100 = 7500 bps base (75%), then adds quest + affiliate + DEITY_PASS_ACTIVITY_BONUS_BPS (8000 = 80%). This represents automatic max streak (50%) + max count (25%) + deity bonus (80%).
- **Non-deity path**: streak capped at 50 points, mint count via `_mintCountBonusPoints` (max 25 points). Active pass holders get floor of 50 streak + 25 count. Each point * 100 = bps. Quest streak max 100 points (100%). Affiliate bonus from external contract. Whale pass: bundleType 1 = +1000 bps (10%), bundleType 3 = +4000 bps (40%).
- `passActive` check: `frozenUntilLevel > currLevel && (bundleType == 1 || bundleType == 3)` -- correct: pass is active only while frozen and only for valid bundle types (1=10-level, 3=100-level).
- `unchecked` block is safe: all additions are bounded by caps (5000 + 2500 + 10000 + 5000 + 8000 = 30500 bps max, well within uint256).
**Gas Flags:** 2 external calls (`questView.playerQuestStates` and `affiliate.affiliateBonusPointsBest`) dominate gas cost. Acceptable for view function.
**Verdict:** CORRECT

---

### `_mintCountBonusPoints(uint24, uint24)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _mintCountBonusPoints(uint24 mintCount, uint24 currLevel) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `mintCount` (uint24): Player's total level mint count; `currLevel` (uint24): Current game level |
| **Returns** | `uint256`: Bonus points (0-25) scaled by participation percentage |

**State Reads:** None (pure function)
**Callers:** `_playerActivityScore()` (this contract)
**NatSpec Accuracy:** NatSpec gives worked examples: "Level 10 with 7 mints (70%): 17.5 points" -- but the function returns `(7 * 25) / 10 = 17` (integer division truncates). The NatSpec example of "17.5" is technically inaccurate for the integer return but the intent is clear. Returns 0 if `currLevel == 0`, returns 25 if perfect participation (`mintCount >= currLevel`), otherwise proportional. This is correct.
**Gas Flags:** None -- pure arithmetic, no storage access.
**Verdict:** CORRECT (informational: NatSpec example shows 17.5 but integer division returns 17)

---

### `getWinnings()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getWinnings() external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint256`: Claimable amount in wei (excludes 1 wei sentinel) |

**State Reads:** `claimableWinnings[msg.sender]`
**Callers:** External only (UI/frontend for player's own balance)
**NatSpec Accuracy:** NatSpec says "caller's claimable winnings balance" and "Returns 0 if balance is only the 1 wei sentinel" -- correct. The sentinel pattern uses 1 wei to mark "has balance" (avoids cold SSTORE on first credit). `stored <= 1` check returns 0 for both 0 (never credited) and 1 (sentinel only). The `unchecked { return stored - 1; }` is safe because `stored > 1` is guaranteed by the guard.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `claimableWinningsOf(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function claimableWinningsOf(address player) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address to query |
| **Returns** | `uint256`: Raw claimable balance in wei (includes sentinel) |

**State Reads:** `claimableWinnings[player]`
**Callers:** External only (UI/frontend, admin tools for arbitrary player lookup)
**NatSpec Accuracy:** NatSpec says "raw claimable balance (includes the 1 wei sentinel)" -- correct. Unlike `getWinnings()` which strips the sentinel, this returns the raw storage value. Useful for admin/debug but requires consumer to subtract 1 if > 0.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `whalePassClaimAmount(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function whalePassClaimAmount(address player) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `uint256`: Amount of ETH claimable as whale pass tickets |

**State Reads:** `whalePassClaims[player]`
**Callers:** External only (UI/frontend for whale pass claim flow)
**NatSpec Accuracy:** NatSpec says "pending whale pass claim amount for a player" -- correct. Storage holds deferred large lootbox wins (>5 ETH threshold per `LOOTBOX_CLAIM_THRESHOLD`).
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `deityPassCountFor(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function deityPassCountFor(address player) external view returns (uint16)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `uint16`: Count of deity passes owned |

**State Reads:** `deityPassCount[player]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "deity pass count for a player" -- correct. Value is 0 or 1 in practice (single deity pass per player) but type allows up to 65535.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `deityPassPurchasedCountFor(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function deityPassPurchasedCountFor(address player) external view returns (uint16)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `uint16`: Count of presale-purchased deity passes |

**State Reads:** `deityPassPurchasedCount[player]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "deity pass count purchased via presale bundle" -- correct. Tracks presale purchases separately from grants.
**Gas Flags:** None -- single SLOAD.
**Verdict:** CORRECT

---

### `deityPassTotalIssuedCount()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function deityPassTotalIssuedCount() external view returns (uint32 count)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `count` (uint32): Total deity passes issued (capped at 32) |

**State Reads:** `deityPassOwners.length`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "total deity passes issued across all sources" with "(capped at 32)" -- correct. `deityPassOwners` is the canonical list. Note: constructor sets `deityPassCount` for DGNRS and VAULT but does NOT push them to `deityPassOwners`, so they are not counted in the "issued" total, which is correct (they are synthetic deity-equivalent accounts, not actual pass holders).
**Gas Flags:** None -- single SLOAD (array length is in first slot).
**Verdict:** CORRECT

---

### `sampleTraitTickets(uint256)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function sampleTraitTickets(uint256 entropy) external view returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `entropy` (uint256): Random seed for selection |
| **Returns** | `lvlSel` (uint24): Selected level; `traitSel` (uint8): Selected trait ID; `tickets` (address[]): Up to 4 ticket holder addresses |

**State Reads:** `level`, `traitBurnTicket[lvlSel][traitSel]` (array length + elements)
**Callers:** External only (used by JackpotModule via delegatecall for scatter draws)
**NatSpec Accuracy:** NatSpec says "Sample up to 4 trait burn tickets from a random trait and recent level" with "last 20 levels" -- correct. Level selection: `offset = (entropy % maxOffset) + 1` where `maxOffset = min(currentLvl - 1, 20)`. Trait: `uint8(entropy >> 24)` uses disjoint byte. Start offset: `(entropy >> 40) % len` uses another disjoint slice. Returns empty array if `currentLvl <= 1` or no tickets at selected level/trait.
**Algorithm Verification:**
- Level range: `[currentLvl - maxOffset, currentLvl - 1]` where maxOffset up to 20. So samples from most recent 20 completed levels. Correct.
- Trait selection: `uint8(word >> 24)` gives uniform distribution over 256 traits. Correct.
- Wrap-around sampling: `tickets[i] = arr[(start + i) % len]` ensures contiguous window with wrap. Correct.
- Max 4 tickets: `take = len > 4 ? 4 : len`. Correct.
**Gas Flags:** Storage reads scale with `take` (max 4 array element reads). Acceptable for view.
**Verdict:** CORRECT

---

### `sampleTraitTicketsAtLevel(uint24, uint256)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function sampleTraitTicketsAtLevel(uint24 targetLvl, uint256 entropy) external view returns (uint8 traitSel, address[] memory tickets)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `targetLvl` (uint24): Level to sample from; `entropy` (uint256): Random seed |
| **Returns** | `traitSel` (uint8): Selected trait ID; `tickets` (address[]): Up to 4 ticket holder addresses |

**State Reads:** `traitBurnTicket[targetLvl][traitSel]` (array length + elements)
**Callers:** External only (used by JackpotModule for BAF scatter at specific level)
**NatSpec Accuracy:** NatSpec says "Simplified variant of sampleTraitTickets for targeted level sampling" and "Used by BAF scatter to sample the next level's ticket holders" -- correct. Same trait and offset derivation as `sampleTraitTickets` but without level randomization.
**Algorithm Verification:**
- Trait: `uint8(entropy >> 24)` -- same as `sampleTraitTickets`. Correct.
- Start offset: `(entropy >> 40) % len` -- same slice usage. Correct.
- Sampling: same wrap-around `(start + i) % len`, max 4. Correct.
**Gas Flags:** Same as `sampleTraitTickets`.
**Verdict:** CORRECT

---

### `sampleFarFutureTickets(uint256)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function sampleFarFutureTickets(uint256 entropy) external view returns (address[] memory tickets)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `entropy` (uint256): Random entropy from VRF |
| **Returns** | `tickets` (address[]): Array of 0-4 player addresses |

**State Reads:** `level`, `ticketQueue[candidate]` for up to 10 candidates (array length + element reads)
**Callers:** External only (used by JackpotModule for BAF far-future selection)
**NatSpec Accuracy:** NatSpec says "Sample up to 4 far-future ticket holders from ticketQueue" with range "[current+5, current+99]" and "Tries up to 10 random levels" -- correct.
**Algorithm Verification:**
- Entropy derivation: `word = keccak256(abi.encodePacked(word, s))` generates independent entropy per attempt. Correct.
- Level range: `candidate = currentLvl + 5 + uint24(word % 95)` gives range [currentLvl+5, currentLvl+99]. Since `word % 95` gives [0,94], the range is exactly [+5, +99]. Correct.
- Winner selection: `idx = (word >> 32) % len` picks a random queue entry. Checks `winner != address(0)` before adding. Correct.
- Loop: tries up to 10 attempts, stops when 4 found. Populates `tmp[4]` then copies to dynamic array sized to `found`. Correct.
- Note: does NOT check for duplicate addresses across attempts -- a player in multiple levels' queues could be selected multiple times. This is likely intentional (more ticket exposure = higher selection probability).
**Gas Flags:** Up to 10 keccak256 hashes + 10 array length SLOADs + up to 4 element SLOADs. Moderate for a view function but bounded.
**Verdict:** CORRECT

---

### `getTickets(uint8, uint24, uint32, uint32, address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getTickets(uint8 trait, uint24 lvl, uint32 offset, uint32 limit, address player) external view returns (uint24 count, uint32 nextOffset, uint32 total)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `trait` (uint8): Trait ID; `lvl` (uint24): Level; `offset` (uint32): Start index; `limit` (uint32): Max entries to scan; `player` (address): Player to count |
| **Returns** | `count` (uint24): Tickets found in this page; `nextOffset` (uint32): Next offset for pagination; `total` (uint32): Total tickets in array |

**State Reads:** `traitBurnTicket[lvl][trait]` (length + elements in range [offset, min(offset+limit, total)))
**Callers:** External only (UI/frontend for player ticket display)
**NatSpec Accuracy:** NatSpec says "Count a player's tickets for a specific trait and level" and "Paginated for large ticket arrays" -- correct. Returns early with `(0, total, total)` if `offset >= total`. Pagination via `nextOffset = uint32(end)` allows sequential page fetching.
**Algorithm Verification:**
- End calculation: `end = offset + limit; if (end > total) end = total` -- correct clamping.
- Linear scan: `if (a[i] == player) count++` counts player's addresses in the page. Correct.
- `count` is uint24 which caps at ~16M. For a single page, this is more than sufficient. Correct.
**Gas Flags:** Linear scan of up to `limit` storage slots. Caller should use reasonable `limit` values (e.g., 100-500) to avoid excessive gas in view calls. No optimization needed -- pagination design handles this.
**Verdict:** CORRECT

---

### `getPlayerPurchases(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getPlayerPurchases(address player) external view returns (uint32 mints, uint32 tickets)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address |
| **Returns** | `mints` (uint32): Token mints owed (always 0); `tickets` (uint32): Tickets owed for current level |

**State Reads:** `level`, `ticketsOwedPacked[level][player]`
**Callers:** External only (UI/frontend)
**NatSpec Accuracy:** NatSpec says "pending mints and tickets owed to a player" -- partially accurate. `mints` is hardcoded to 0 (mint tracking was removed/deprecated). The `tickets` return correctly extracts whole tickets from `ticketsOwedPacked[level][player] >> 8`, same as `ticketsOwedView`. The function queries the current `level`, while `ticketsOwedView` takes a specific level parameter -- different use cases.
**Gas Flags:** None -- 2 SLOADs.
**Verdict:** CORRECT (informational: `mints` always returns 0, field retained for interface compatibility)

---

### `getDailyHeroWager(uint48, uint8, uint8)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getDailyHeroWager(uint48 day, uint8 quadrant, uint8 symbol) external view returns (uint256 wagerUnits)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `day` (uint48): Day index; `quadrant` (uint8): 0-3; `symbol` (uint8): 0-7 |
| **Returns** | `wagerUnits` (uint256): Wagered amount in 1e12 wei units |

**State Reads:** `dailyHeroWagers[day][quadrant]`
**Callers:** External only (UI/frontend for degenerette hero display)
**NatSpec Accuracy:** NatSpec says "daily hero wager for a specific quadrant/symbol on a given day" and "wagerUnits" in 1e12 wei units -- correct. The 1e12 unit scale matches storage documentation: "Amounts stored in units of 1e12 wei (0.000001 ETH) to fit 32 bits."
**Algorithm Verification:**
- Bounds check: `if (quadrant >= 4 || symbol >= 8) return 0` -- correct, prevents out-of-bounds access.
- Bit extraction: `(packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF` extracts the 32-bit wager amount at the correct position. 8 symbols * 32 bits = 256 bits per quadrant, perfectly filling a uint256. Correct.
**Gas Flags:** None -- single mapping SLOAD with bitwise extraction.
**Verdict:** CORRECT

---

### `getDailyHeroWinner(uint48)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getDailyHeroWinner(uint48 day) external view returns (uint8 winQuadrant, uint8 winSymbol, uint256 winAmount)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `day` (uint48): Day index |
| **Returns** | `winQuadrant` (uint8): Winning quadrant; `winSymbol` (uint8): Winning symbol; `winAmount` (uint256): Wagered units for winner |

**State Reads:** `dailyHeroWagers[day][0..3]` (all 4 quadrants)
**Callers:** External only (UI/frontend for daily hero result)
**NatSpec Accuracy:** NatSpec says "winning hero symbol for a given day (most wagered across all quadrants)" -- correct. Scans all 4 quadrants x 8 symbols = 32 entries, returns the one with highest wager. Ties go to first found (lower quadrant, lower symbol).
**Algorithm Verification:**
- Double loop: `q: 0..3`, `s: 0..7` -- covers all 32 symbols. Correct.
- Same bit extraction as `getDailyHeroWager`. Correct.
- `if (amount > winAmount)` strict greater-than: first occurrence wins ties. Correct.
- Default return: if no wagers exist, returns `(0, 0, 0)`. Correct.
**Gas Flags:** 4 SLOADs (one per quadrant). Fixed cost regardless of wager density. Acceptable.
**Verdict:** CORRECT

---

### `getPlayerDegeneretteWager(address, uint24)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getPlayerDegeneretteWager(address player, uint24 lvl) external view returns (uint256 weiAmount)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): Player address; `lvl` (uint24): Level to query |
| **Returns** | `weiAmount` (uint256): Total ETH wagered in wei |

**State Reads:** `playerDegeneretteEthWagered[player][lvl]`
**Callers:** External only (UI/frontend for degenerette stats)
**NatSpec Accuracy:** NatSpec says "player's total ETH wagered on degenerette at a specific level" -- correct. Returns full wei amount (not scaled units).
**Gas Flags:** None -- single nested mapping SLOAD.
**Verdict:** CORRECT

---

### `getTopDegenerette(uint24)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getTopDegenerette(uint24 lvl) external view returns (address topPlayer, uint256 amountUnits)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Level to query |
| **Returns** | `topPlayer` (address): Top wagerer address; `amountUnits` (uint256): Wagered amount in 1e12 wei units |

**State Reads:** `topDegeneretteByLevel[lvl]`
**Callers:** External only (UI/frontend for degenerette leaderboard)
**NatSpec Accuracy:** NatSpec says "top degenerette player for a given level" -- correct.
**Algorithm Verification:**
- Unpacking: `topPlayer = address(uint160(packed))` extracts lower 160 bits (address). `amountUnits = packed >> 160` extracts upper 96 bits (amount in 1e12 units). This matches the storage layout: "Packed: [96 bits: amount in 1e12 units] [160 bits: address]". Correct.
**Gas Flags:** None -- single SLOAD with bit manipulation.
**Verdict:** CORRECT

---

### `receive()` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `receive() external payable` |
| **Visibility** | external |
| **Mutability** | payable (state-mutating, not view) |
| **Parameters** | None (implicit `msg.value`) |
| **Returns** | None |

**State Reads:** `gameOver`
**State Writes:** `futurePrizePool += msg.value`
**Callers:** External (any ETH sender)
**NatSpec Accuracy:** NatSpec says "Accept ETH and add to the future pool reserve" and "Plain ETH transfers are routed to jackpot reserves" -- correct. Reverts with `E()` if `gameOver` is true.
**Gas Flags:** None -- single SLOAD (gameOver) + single SSTORE (futurePrizePool).
**Note:** This is technically not a view function but is included as it is the last function in the file and part of the external interface.
**Verdict:** CORRECT

---

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 0 | No actionable gas issues |
| CORRECT | 53 | All verified |
| INFORMATIONAL | 4 | NatSpec informationals (see below) |

### Informational Notes

1. **`rewardPoolView()`** -- Function name is a legacy alias for `futurePrizePool` after reward/future pool unification. Returns same value as `futurePrizePoolView()` and `futurePrizePoolTotalView()`. No behavioral issue.

2. **`mintPrice()`** -- NatSpec price tier description omits 0.16 ETH tier (x90-x99 levels). Function correctly returns stored `price` regardless.

3. **`_mintCountBonusPoints()`** -- NatSpec example shows "17.5 points" for 70% participation, but integer division returns 17. Intent is clear; the fractional point description is slightly misleading.

4. **`getPlayerPurchases()`** -- `mints` return value is always 0 (deprecated field retained for interface compatibility).

## Notes

- Total view/pure functions audited: 53 (38 in Task 1 + 15 in Task 2)
- All view functions are read-only (no state mutations except `receive()`)
- No ETH flow paths (view functions cannot transfer)
- `receive()` is the only state-mutating function in the audited range and is correctly guarded by `gameOver` check
- Three view functions (`rewardPoolView`, `futurePrizePoolView`, `futurePrizePoolTotalView`) return the same `futurePrizePool` value -- legacy interfaces preserved for backward compatibility
- Activity score calculation involves 2 external calls (quests, affiliate) which are the most gas-intensive operations among all view functions
- Bit-packed field extraction in mint stats functions (`ethMintLastLevel`, `ethMintLevelCount`, `ethMintStreakCount`, `ethMintStats`) correctly uses BitPackingLib shift constants and masks, verified against the documented 256-bit layout
- Ticket sampling functions (`sampleTraitTickets`, `sampleTraitTicketsAtLevel`, `sampleFarFutureTickets`) use entropy slicing to derive independent random values from a single VRF word -- no overlap in bit ranges used for level/trait/offset selection
