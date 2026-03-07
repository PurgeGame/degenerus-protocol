# BurnieCoinflip.sol -- Function-Level Audit

**Contract:** BurnieCoinflip
**File:** contracts/BurnieCoinflip.sol
**Lines:** 1204
**Solidity:** 0.8.34
**Inherits:** None (standalone contract; adheres to IBurnieCoinflip interface implicitly)
**Audit date:** 2026-03-07

## Summary

BurnieCoinflip is a standalone daily coinflip wagering system for BurnieCoin (BURNIE). Players deposit BURNIE tokens (which are burned on deposit) into a daily coinflip pool. Each day, a single coinflip is resolved via VRF during game advancement, producing a win/loss outcome with a variable reward percentage. Winners receive principal + bonus (EV-adjusted); losers forfeit principal but receive WWXRP consolation. The contract supports auto-rebuy (carry winnings forward as next-day stakes), take-profit (extract multiples of a stop amount), recycling bonuses (1% base, enhanced for afKing mode), BAF bracket tracking for jackpot eligibility, a bounty system for biggest-flip records, quest integration, and day-leaderboard tracking. All BURNIE minting/burning flows through BurnieCoin's `burnForCoinflip`/`mintForCoinflip` methods.

---

## Function Audit

### State Transition

---

### `settleFlipModeChange(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function settleFlipModeChange(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): the player whose flip state to settle before afKing mode change |
| **Returns** | None |

**State Reads:** `playerState[player].claimableStored`, all state read by `_claimCoinflipsInternal`
**State Writes:** `playerState[player].claimableStored` (increased by mintable if nonzero)

**Callers:** DegenerusGame contract (via delegatecall modules, before afKing mode toggle)
**Callees:** `_claimCoinflipsInternal(player, false)`

**ETH Flow:** No
**Invariants:** Must be called before any afKing mode change so in-flight flips are settled under the correct bonus regime. Only callable by the game contract (`onlyDegenerusGameContract`).
**NatSpec Accuracy:** NatSpec says "Processes pending claims so mode change doesn't affect in-flight flips" -- matches behavior. Accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Deposit & Claim

---

### `depositCoinflip(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function depositCoinflip(address player, uint256 amount) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): deposit target (address(0) or msg.sender = self-deposit); `amount` (uint256): BURNIE to deposit |
| **Returns** | None |

**State Reads:** None directly; delegates to `_depositCoinflip`
**State Writes:** None directly; delegates to `_depositCoinflip`

**Callers:** External (players, operators, BurnieCoin contract)
**Callees:** `degenerusGame.isOperatorApproved(player, msg.sender)`, `_depositCoinflip(caller, amount, directDeposit)`

**ETH Flow:** No
**Invariants:** If `player != address(0)` and `player != msg.sender`, msg.sender must be an approved operator for `player`. Direct deposits (self or address(0)) set `directDeposit=true` which enables bounty eligibility and biggest-flip tracking.
**NatSpec Accuracy:** NatSpec is minimal ("Deposit BURNIE into daily coinflip system"). Adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_depositCoinflip(address caller, uint256 amount, bool directDeposit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _depositCoinflip(address caller, uint256 amount, bool directDeposit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `caller` (address): the player; `amount` (uint256): BURNIE to deposit; `directDeposit` (bool): whether deposit is direct (enables bounty + biggest-flip tracking) |
| **Returns** | None |

**State Reads:** `playerState[caller]` (claimableStored, autoRebuyEnabled, autoRebuyCarry)
**State Writes:** `playerState[caller].claimableStored` (via `_claimCoinflipsInternal` settlement)

**Callers:** `depositCoinflip`
**Callees:** `_coinflipLockedDuringTransition()`, `_claimCoinflipsInternal(caller, false)`, `burnie.burnForCoinflip(caller, amount)`, `questModule.handleFlip(caller, amount)`, `_questApplyReward(...)`, `degenerusGame.recordCoinflipDeposit(amount)`, `degenerusGame.afKingModeFor(caller)`, `degenerusGame.deityPassCountFor(caller)`, `_afKingDeityBonusHalfBpsWithLevel(caller, level)`, `_afKingRecyclingBonus(rebetAmount, deityBonusHalfBps)`, `_recyclingBonus(rebetAmount)`, `_addDailyFlip(caller, creditedFlip, ...)`, `degenerusGame.level()`

**ETH Flow:** No (BURNIE tokens only; burn on deposit, no ETH moves)
**Invariants:**
- Amount must be >= MIN (100 ether) unless amount == 0 (claim-only call).
- Coinflip must not be locked during BAF transition levels.
- Burns BURNIE before crediting flip (CEI pattern).
- Recycling bonus only applies to the "rebet" portion (min of creditedFlip, rollAmount).
- rollAmount is autoRebuyCarry if auto-rebuy enabled, else the freshly computed mintable.
- Quest reward is added to creditedFlip (principal + questReward).
- Direct deposits pass `amount` as `recordAmount` for bounty eligibility; indirect pass 0.

**NatSpec Accuracy:** NatSpec says "Internal deposit for daily coinflip mode" -- accurate but minimal.
**Gas Flags:** The `amount == 0` path still calls `_claimCoinflipsInternal` for settlement, which is intentional. No wasted computation.
**Verdict:** CORRECT

---

### `claimCoinflips(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address(0) = msg.sender, else validated; `amount` (uint256): exact BURNIE to claim |
| **Returns** | `claimed` (uint256): actual amount claimed (may be less than requested if balance insufficient) |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsAmount`

**Callers:** External (players, operators)
**Callees:** `degenerusGame.rngLocked()`, `_resolvePlayer(player)`, `_claimCoinflipsAmount(resolved, amount, true)`

**ETH Flow:** No
**Invariants:** Reverts if RNG locked (prevents BAF credit manipulation during VRF pending). Mints tokens (`mintTokens=true`).
**NatSpec Accuracy:** "Claim coinflip winnings (exact amount)." and dev note about RNG lock -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `claimCoinflipsTakeProfit(address player, uint256 multiples)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimCoinflipsTakeProfit(address player, uint256 multiples) external returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): address(0) = msg.sender; `multiples` (uint256): number of take-profit multiples to claim (0 = max) |
| **Returns** | `claimed` (uint256): amount claimed |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsTakeProfit`

**Callers:** External (players, operators)
**Callees:** `degenerusGame.rngLocked()`, `_resolvePlayer(player)`, `_claimCoinflipsTakeProfit(resolved, multiples)`

**ETH Flow:** No
**Invariants:** Reverts if RNG locked. Takes profit in exact multiples of `autoRebuyStop`.
**NatSpec Accuracy:** "Claim coinflip winnings (take profit multiples)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `claimCoinflipsFromBurnie(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function claimCoinflipsFromBurnie(address player, uint256 amount) external onlyBurnieCoin returns (uint256 claimed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to claim for; `amount` (uint256): amount to claim |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsAmount`

**Callers:** BurnieCoin contract (to cover token transfers/burns from claimable balance)
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsAmount(player, amount, true)`

**ETH Flow:** No
**Invariants:** Only callable by BurnieCoin (`onlyBurnieCoin`). Player address passed directly (no `_resolvePlayer` -- BurnieCoin is trusted). Mints tokens.
**NatSpec Accuracy:** "Claim coinflip winnings via BurnieCoin to cover token transfers/burns." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `consumeCoinflipsForBurn(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeCoinflipsForBurn(address player, uint256 amount) external onlyBurnieCoin returns (uint256 consumed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player to consume from; `amount` (uint256): amount to consume |
| **Returns** | `consumed` (uint256): actual amount consumed |

**State Reads:** `degenerusGame.rngLocked()`
**State Writes:** Via `_claimCoinflipsAmount`

**Callers:** BurnieCoin contract (for burns that reduce claimable without minting)
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsAmount(player, amount, false)`

**ETH Flow:** No
**Invariants:** Only callable by BurnieCoin. Differs from `claimCoinflipsFromBurnie` in that `mintTokens=false` -- reduces claimable balance but does NOT mint new BURNIE. Used for burning from claimable.
**NatSpec Accuracy:** "Consume coinflip winnings via BurnieCoin for burns (no mint)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipsTakeProfit(address player, uint256 multiples)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipsTakeProfit(address player, uint256 multiples) private returns (uint256 claimed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `multiples` (uint256): number of take-profit multiples (0 = max available) |
| **Returns** | `claimed` (uint256): amount claimed |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop, claimableStored)
**State Writes:** `playerState[player].claimableStored`

**Callers:** `claimCoinflipsTakeProfit`
**Callees:** `_claimCoinflipsInternal(player, false)`, `burnie.mintForCoinflip(player, toClaim)`

**ETH Flow:** No
**Invariants:**
- Auto-rebuy must be enabled (reverts `AutoRebuyNotEnabled` otherwise).
- Take-profit stop must be nonzero (reverts `TakeProfitZero`).
- Claims in exact multiples of `autoRebuyStop`. If `multiples == 0`, claims max available multiples.
- Remaining balance (modulo) stays in `claimableStored`.

**NatSpec Accuracy:** "Internal claim keeping multiples of auto-rebuy stop amount." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipsAmount(address player, uint256 amount, bool mintTokens)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipsAmount(address player, uint256 amount, bool mintTokens) private returns (uint256 claimed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `amount` (uint256): amount to claim; `mintTokens` (bool): whether to mint BURNIE tokens |
| **Returns** | `claimed` (uint256): actual amount claimed |

**State Reads:** `playerState[player].claimableStored`
**State Writes:** `playerState[player].claimableStored` (reduced by toClaim)

**Callers:** `claimCoinflips`, `claimCoinflipsFromBurnie`, `consumeCoinflipsForBurn`
**Callees:** `_claimCoinflipsInternal(player, false)`, `burnie.mintForCoinflip(player, toClaim)` (only if mintTokens)

**ETH Flow:** No
**Invariants:**
- Claims minimum of requested `amount` and available `stored` balance.
- If `mintTokens == false`, balance is consumed but no tokens are minted (used by `consumeCoinflipsForBurn`).
- Updates `claimableStored` even if only to add newly computed `mintable` from `_claimCoinflipsInternal`.

**NatSpec Accuracy:** "Internal claim exact amount." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_claimCoinflipsInternal(address player, bool deepAutoRebuy)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function _claimCoinflipsInternal(address player, bool deepAutoRebuy) internal returns (uint256 mintable)` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `deepAutoRebuy` (bool): if true and auto-rebuy active, processes larger window (up to 1095 days) |
| **Returns** | `mintable` (uint256): total amount to mint (after take-profit extraction) |

**State Reads:** `flipsClaimableDay`, `playerState[player]` (lastClaim, autoRebuyEnabled, autoRebuyStop, autoRebuyCarry, autoRebuyStartDay, claimableStored), `coinflipDayResult[cursor]`, `coinflipBalance[cursor][player]`, `degenerusGame` (syncAfKingLazyPassFromCoin, deityPassCountFor, level, purchaseInfo, gameOver)
**State Writes:** `coinflipBalance[cursor][player]` (zeroed on processed days), `playerState[player].lastClaim`, `playerState[player].autoRebuyCarry`

**Callers:** `settleFlipModeChange`, `_depositCoinflip`, `_claimCoinflipsTakeProfit`, `_claimCoinflipsAmount`, `_setCoinflipAutoRebuy`, `_setCoinflipAutoRebuyTakeProfit`
**Callees:** `degenerusGame.syncAfKingLazyPassFromCoin(player)`, `degenerusGame.deityPassCountFor(player)`, `degenerusGame.level()`, `_afKingDeityBonusHalfBpsWithLevel(player, cachedLevel)`, `_recyclingBonus(carry)`, `_afKingRecyclingBonus(carry, deityBonusHalfBps)`, `_bafBracketLevel(bafLevel)`, `jackpots.recordBafFlip(player, bafLvl, winningBafCredit)`, `degenerusGame.purchaseInfo()`, `degenerusGame.gameOver()`, `wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD)`

**ETH Flow:** No direct ETH. Mints WWXRP on losses (1 ether per loss day).
**Invariants:**
- Processes from `lastClaim+1` to `flipsClaimableDay`, bounded by a claim window.
- Claim window: first 30 days (if `lastClaim==0`), then 90 days (normal), or AUTO_REBUY_OFF_CLAIM_DAYS_MAX (1095) when `deepAutoRebuy=true`.
- If auto-rebuy is off but `autoRebuyCarry != 0`, the carry is added to `mintable` and cleared.
- On win: payout = stake + (stake * rewardPercent / 100). If auto-rebuy, winnings go to carry (with take-profit extraction); otherwise added to mintable.
- Carry gets recycling bonus after each win day (base 1% or afKing enhanced).
- On loss: stake is forfeited, carry is zeroed (if auto-rebuy), lossCount incremented for WWXRP.
- BAF credit is recorded for all winning days via `jackpots.recordBafFlip`.
- Reverts `RngLocked()` if there is winning BAF credit and the game is at a BAF resolution level (purchaseLevel % 10 == 0) on last purchase day with RNG locked.
- Auto-rebuy start day bounds the minimum claimable day (no expiry for auto-rebuy positions).
- If `start < minClaimableDay` and auto-rebuy active, carry is zeroed (stale carry from expired days).

**NatSpec Accuracy:** "Process daily coinflip claims and calculate winnings." -- adequate but understates complexity.
**Gas Flags:** The function iterates up to `windowDays` (90) or `AUTO_REBUY_OFF_CLAIM_DAYS_MAX` (1095) days. For deep auto-rebuy processing, 1095 iterations could be gas-intensive but is capped to keep tx cost bounded.
**Verdict:** CORRECT

---

### Daily Flip Accumulation

---

### `_addDailyFlip(address player, uint256 coinflipDeposit, uint256 recordAmount, bool canArmBounty, bool bountyEligible)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addDailyFlip(address player, uint256 coinflipDeposit, uint256 recordAmount, bool canArmBounty, bool bountyEligible) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `coinflipDeposit` (uint256): total credited amount (with bonuses); `recordAmount` (uint256): raw deposit for bounty (0 for non-direct); `canArmBounty` (bool): can this call arm the bounty; `bountyEligible` (bool): whether deposit is eligible for bounty tracking |
| **Returns** | None |

**State Reads:** `coinflipBalance[targetDay][player]`, `biggestFlipEver`, `bountyOwedTo`, `currentBounty`
**State Writes:** `coinflipBalance[targetDay][player]` (increased), `biggestFlipEver` (if new record), `bountyOwedTo` (set to player if new record), `coinflipTopByDay[targetDay]` (via `_updateTopDayBettor`)

**Callers:** `_depositCoinflip`, `processCoinflipPayouts` (for bounty payout), `creditFlip`, `creditFlipBatch`
**Callees:** `degenerusGame.consumeCoinflipBoon(player)` (only when `recordAmount != 0`), `_targetFlipDay()`, `_updateTopDayBettor(player, newStake, targetDay)`

**ETH Flow:** No
**Invariants:**
- Coinflip boon is only consumed on manual deposits (`recordAmount != 0`), boosting up to 100k BURNIE by boonBps.
- Target day is always `currentDayView() + 1` (next day).
- Bounty can only be armed when `canArmBounty && bountyEligible && recordAmount != 0` and `recordAmount > biggestFlipEver` and RNG not locked.
- To steal an existing bounty, must exceed current record by 1% (min 1 wei).
- `recordAmount` overflow is guarded (reverts `Insufficient` if > uint128.max).

**NatSpec Accuracy:** "Add daily flip stake for player." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Auto-Rebuy

---

### `setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): target player (address(0) = msg.sender); `enabled` (bool): enable/disable auto-rebuy; `takeProfit` (uint256): take-profit threshold |
| **Returns** | None |

**State Reads:** None directly; delegates
**State Writes:** None directly; delegates

**Callers:** External (players, operators, game contract)
**Callees:** `_requireApproved(player)` (if not from game and player != msg.sender), `_setCoinflipAutoRebuy(player, enabled, takeProfit, !fromGame)`

**ETH Flow:** No
**Invariants:** When called by the game contract (`fromGame=true`), `strict=false` (lenient mode: no revert on already-enabled, different event ordering). When called externally, `strict=true`.
**NatSpec Accuracy:** "Configure auto-rebuy mode for coinflips." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): target (address(0) = msg.sender); `takeProfit` (uint256): new take-profit stop |
| **Returns** | None |

**State Reads:** None directly; delegates
**State Writes:** None directly; delegates

**Callers:** External (players, operators)
**Callees:** `_resolvePlayer(player)`, `_setCoinflipAutoRebuyTakeProfit(resolved, takeProfit)`

**ETH Flow:** No
**Invariants:** Requires auto-rebuy already enabled (checked in `_setCoinflipAutoRebuyTakeProfit`).
**NatSpec Accuracy:** "Set auto-rebuy take profit." -- adequate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit, bool strict)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit, bool strict) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address); `enabled` (bool); `takeProfit` (uint256); `strict` (bool): if true, reverts on already-enabled |
| **Returns** | None |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyCarry, lastClaim, autoRebuyStartDay, autoRebuyStop)
**State Writes:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop, autoRebuyStartDay, autoRebuyCarry)

**Callers:** `setCoinflipAutoRebuy`
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsInternal(player, false)` (enable) or `_claimCoinflipsInternal(player, true)` (disable, deep), `burnie.mintForCoinflip(player, mintable)`, `degenerusGame.deactivateAfKingFromCoin(player)`

**ETH Flow:** No
**Invariants:**
- Reverts if RNG locked.
- **Enable path (strict=true):** If already enabled, reverts `AutoRebuyAlreadyEnabled`. Otherwise sets enabled=true, sets startDay=lastClaim, sets stop=takeProfit. If takeProfit < AFKING_KEEP_MIN_COIN (20,000 ether), deactivates afKing.
- **Enable path (strict=false, from game):** If already enabled, just updates stop amount silently. If not enabled, enables with different event ordering (toggle then stop vs stop then toggle). Still deactivates afKing on low take-profit.
- **Disable path:** Deep-claims all days (up to 1095), adds carry to mintable, clears carry. Sets enabled=false, startDay=0. Always deactivates afKing.
- Mints any accumulated mintable at the end.

**NatSpec Accuracy:** "Internal auto-rebuy configuration." -- adequate.
**Gas Flags:** The `strict` flag creates two similar branches for enable -- could be consolidated, but not a gas issue since only one path executes.
**Verdict:** CORRECT

---

### `_setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _setCoinflipAutoRebuyTakeProfit(address player, uint256 takeProfit) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address); `takeProfit` (uint256): new take-profit stop |
| **Returns** | None |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop)
**State Writes:** `playerState[player].autoRebuyStop`

**Callers:** `setCoinflipAutoRebuyTakeProfit`
**Callees:** `degenerusGame.rngLocked()`, `_claimCoinflipsInternal(player, false)`, `burnie.mintForCoinflip(player, mintable)`, `degenerusGame.deactivateAfKingFromCoin(player)`

**ETH Flow:** No
**Invariants:** Reverts if RNG locked. Reverts if auto-rebuy not enabled. Settles claims before updating stop. If `takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_COIN`, deactivates afKing (low take-profit is incompatible with afKing min balance requirement).
**NatSpec Accuracy:** "Internal auto-rebuy take profit configuration." -- accurate.
**Gas Flags:** The mintable settlement is done before updating stop, which is correct (settling under old regime).
**Verdict:** CORRECT

---

### Payout Processing

---

### `processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint48 epoch)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint48 epoch) external onlyDegenerusGameContract` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `bonusFlip` (bool): whether this is a last-purchase-day bonus flip; `rngWord` (uint256): VRF random word; `epoch` (uint48): the day being resolved |
| **Returns** | None |

**State Reads:** `currentBounty`, `bountyOwedTo`, `degenerusGame` (lootboxPresaleActiveFlag, lastPurchaseDayFlipTotals)
**State Writes:** `coinflipDayResult[epoch]`, `flipsClaimableDay`, `currentBounty`, `bountyOwedTo`

**Callers:** DegenerusGame contract (during advanceGame via AdvanceModule)
**Callees:** `degenerusGame.lootboxPresaleActiveFlag()`, `degenerusGame.lastPurchaseDayFlipTotals()`, `_coinflipTargetEvBps(prevTotal, currentTotal)`, `_applyEvToRewardPercent(rewardPercent, evBps)`, `_addDailyFlip(to, slice, 0, false, false)` (for bounty payout), `degenerusGame.payCoinflipBountyDgnrs(to)`

**ETH Flow:** No direct ETH. Bounty payout is credited as flip stake (not ETH).
**Invariants:**
- Only callable by game contract.
- Entropy: seedWord = keccak256(rngWord, epoch) for per-day uniqueness.
- Reward percent: 5% chance each for 50% (1.5x) or 150% (2.5x), otherwise [78%, 115%] range.
- Presale bonus: +6% reward when presale active and bonusFlip.
- EV adjustment: only when bonusFlip and not presaleBonus, using `_coinflipTargetEvBps` based on last-purchase-day flip totals.
- Win: (rngWord & 1) == 1 (50/50 from original rngWord, not seedWord).
- Bounty resolution: if bountyOwner exists and bounty > 0, halve bounty. If win, credit half as flip stake to bountyOwner and pay DGNRS bounty. Clear bountyOwner regardless.
- After resolution: advances `flipsClaimableDay` to epoch and adds PRICE_COIN_UNIT (1000 ether) to bounty pool.

**NatSpec Accuracy:** "Process coinflip payout for a day (called by game contract)." -- accurate.
**Gas Flags:** The reward percent calculation re-uses `seedWord` for the normal-range roll (`seedWord % COINFLIP_EXTRA_RANGE`), which is correct since `seedWord` was derived from keccak256 but note that the extreme roll uses `seedWord % 20` while the normal range uses `seedWord % COINFLIP_EXTRA_RANGE` (38). These use the same `seedWord` but test different moduli -- the extreme check (`roll == 0 || roll == 1`) gates whether the normal-range formula is used, so no conflict.
**Verdict:** CORRECT

---

### Credit System

---

### `creditFlip(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlip(address player, uint256 amount) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): BURNIE-denominated flip credit |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via `_addDailyFlip`

**Callers:** DegenerusGame contract or BurnieCoin contract (onlyFlipCreditors)
**Callees:** `_addDailyFlip(player, amount, 0, false, false)`

**ETH Flow:** No
**Invariants:** No-op if player is address(0) or amount is 0. Credits with `recordAmount=0`, `canArmBounty=false`, `bountyEligible=false` -- no bounty or boon interaction. Only game or coin contract can call.
**NatSpec Accuracy:** "Credit flip to a player (called by authorized creditors)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external onlyFlipCreditors` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `players` (address[3]): up to 3 recipients; `amounts` (uint256[3]): corresponding amounts |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via `_addDailyFlip` for each valid entry

**Callers:** DegenerusGame contract or BurnieCoin contract (onlyFlipCreditors)
**Callees:** `_addDailyFlip(player, amount, 0, false, false)` for each non-zero entry

**ETH Flow:** No
**Invariants:** Skips entries where player is address(0) or amount is 0. Fixed size 3 (calldata optimization). No bounty interaction.
**NatSpec Accuracy:** "Credit flips to multiple players (batch)." -- accurate.
**Gas Flags:** Fixed-size array (3) is gas-efficient vs dynamic. Uses unchecked increment.
**Verdict:** CORRECT

---

### View Functions

---

### `previewClaimCoinflips(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function previewClaimCoinflips(address player) external view returns (uint256 mintable)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | `mintable` (uint256): total claimable BURNIE (stored + daily winnings) |

**State Reads:** `playerState[player].claimableStored`, via `_viewClaimableCoin(player)`
**State Writes:** None

**Callers:** External (UI, off-chain queries)
**Callees:** `_viewClaimableCoin(player)`

**ETH Flow:** No
**Invariants:** Sum of stored claimable + pending daily winnings within the claim window. Does not account for auto-rebuy carry or recycling bonuses (those are only computed during state-changing claims).
**NatSpec Accuracy:** "Preview claimable coinflip winnings." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT -- Note: the preview is an approximation for auto-rebuy players since it doesn't simulate carry/recycling. This is acceptable for a view function.

---

### `coinflipAmount(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function coinflipAmount(address player) external view returns (uint256)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | uint256: stake amount for the next day |

**State Reads:** `coinflipBalance[targetDay][player]`
**State Writes:** None

**Callers:** External
**Callees:** `_targetFlipDay()`

**ETH Flow:** No
**Invariants:** Returns the currently staked amount for the next flip day.
**NatSpec Accuracy:** "Get player's current coinflip stake for next day." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinflipAutoRebuyInfo(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint48 startDay)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | `enabled` (bool), `stop` (uint256), `carry` (uint256), `startDay` (uint48) |

**State Reads:** `playerState[player]` (autoRebuyEnabled, autoRebuyStop, autoRebuyCarry, autoRebuyStartDay)
**State Writes:** None

**Callers:** External
**Callees:** None

**ETH Flow:** No
**Invariants:** Direct storage read, no computation.
**NatSpec Accuracy:** "Get player's auto-rebuy configuration." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `coinflipTopLastDay()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function coinflipTopLastDay() external view returns (address player, uint128 score)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `player` (address): top bettor; `score` (uint128): their score |

**State Reads:** `flipsClaimableDay`, `coinflipTopByDay[lastDay]`
**State Writes:** None

**Callers:** External
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns address(0) and 0 if flipsClaimableDay is 0 (no days resolved yet). Score is cast from uint96 to uint128 (safe widening).
**NatSpec Accuracy:** "Get last day's coinflip leaderboard winner." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_viewClaimableCoin(address player)` [internal view]

| Field | Value |
|-------|-------|
| **Signature** | `function _viewClaimableCoin(address player) internal view returns (uint256 total)` |
| **Visibility** | internal |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | `total` (uint256): pending daily flip winnings |

**State Reads:** `flipsClaimableDay`, `playerState[player].lastClaim`, `coinflipDayResult[cursor]`, `coinflipBalance[cursor][player]`
**State Writes:** None

**Callers:** `previewClaimCoinflips`
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Iterates from `lastClaim+1` to `flipsClaimableDay` within the claim window (first 30 or 90 days).
- Only counts winning days: payout = stake + (stake * rewardPercent / 100).
- Skips unresolved days (rewardPercent == 0 and !win).
- Does NOT simulate auto-rebuy carry or recycling bonuses. This is a simplified view.

**NatSpec Accuracy:** "View helper for daily coinflip claimable winnings." -- accurate.
**Gas Flags:** Iterates up to `windowDays` (max 90). Bounded.
**Verdict:** CORRECT

---

### EV & Bonus Calculations

---

### `_coinflipLockedDuringTransition()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _coinflipLockedDuringTransition() private view returns (bool locked)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `locked` (bool): true if coinflip deposits should be blocked |

**State Reads:** `degenerusGame.purchaseInfo()`, `degenerusGame.gameOver()`
**State Writes:** None

**Callers:** `_depositCoinflip`
**Callees:** `degenerusGame.purchaseInfo()`, `degenerusGame.gameOver()`

**ETH Flow:** No
**Invariants:** Returns true only when: not in jackpot phase, not game over, is last purchase day, RNG is locked, and purchase level is a multiple of 10 (BAF resolution level). This prevents front-running the BAF leaderboard between VRF request and fulfillment.
**NatSpec Accuracy:** "Check if coinflip deposits are locked during BAF resolution levels." with detailed dev note -- accurate and thorough.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_recyclingBonus(uint256 amount)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _recyclingBonus(uint256 amount) private pure returns (uint256 bonus)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `amount` (uint256): base amount for bonus calculation |
| **Returns** | `bonus` (uint256): recycling bonus amount |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `_depositCoinflip`, `_claimCoinflipsInternal`
**Callees:** None

**ETH Flow:** No
**Invariants:** 1% of amount, capped at 1000 ether. Returns 0 if amount is 0.
**NatSpec Accuracy:** "Calculate recycling bonus for daily flip deposits (1% bonus, capped at 1000 BURNIE)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_afKingRecyclingBonus(uint256 amount, uint16 deityBonusHalfBps)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _afKingRecyclingBonus(uint256 amount, uint16 deityBonusHalfBps) private pure returns (uint256 bonus)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `amount` (uint256): base amount; `deityBonusHalfBps` (uint16): deity pass bonus in half-bps |
| **Returns** | `bonus` (uint256): recycling bonus with afKing enhancement |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `_depositCoinflip`, `_claimCoinflipsInternal`
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Base half-bps = AFKING_RECYCLE_BONUS_BPS * 2 = 160 * 2 = 320 half-bps = 1.6% in BPS = 1.6%.
- If no deity bonus or amount <= DEITY_RECYCLE_CAP (1M ether): full (base + deity) applied to entire amount.
- If amount > DEITY_RECYCLE_CAP: full bonus on first 1M, base-only on remainder.
- Division by `BPS_DENOMINATOR * 2` (20,000) converts half-bps to actual bonus.
- Returns 0 if amount is 0.

**NatSpec Accuracy:** "Calculate recycling bonus for afKing flip deposits. Deity bonus portion is capped at DEITY_RECYCLE_CAP; remainder gets base only." -- accurate and complete.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_afKingDeityBonusHalfBpsWithLevel(address player, uint24 currentLevel)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _afKingDeityBonusHalfBpsWithLevel(address player, uint24 currentLevel) private view returns (uint16)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address); `currentLevel` (uint24): current game level |
| **Returns** | uint16: deity bonus in half-bps |

**State Reads:** `degenerusGame.afKingActivatedLevelFor(player)`
**State Writes:** None

**Callers:** `_depositCoinflip`, `_claimCoinflipsInternal`
**Callees:** `degenerusGame.afKingActivatedLevelFor(player)`

**ETH Flow:** No
**Invariants:**
- Returns 0 if activation level is 0 (never activated) or current level <= activation level.
- Bonus = (currentLevel - activationLevel) * AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS (2 half-bps per level).
- Capped at AFKING_DEITY_BONUS_MAX_HALF_BPS (300 half-bps = 1.5% in BPS).
- Uses half-bps for finer granularity: 2 half-bps per level = 0.01% per level, max 1.5%.

**NatSpec Accuracy:** "Calculate deity pass bonus in half-bps using a cached level." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_coinflipTargetEvBps(uint256 prevTotal, uint256 currentTotal)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _coinflipTargetEvBps(uint256 prevTotal, uint256 currentTotal) private pure returns (int256 evBps)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `prevTotal` (uint256): previous level's last-purchase-day flip total; `currentTotal` (uint256): current level's total |
| **Returns** | `evBps` (int256): target EV in basis points |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `processCoinflipPayouts`
**Callees:** `_lerpEvBps(...)`

**ETH Flow:** No
**Invariants:**
- If prevTotal == 0: returns COINFLIP_EV_EQUAL_BPS (0 bps).
- ratioBps = (currentTotal * 10,000) / prevTotal.
- If ratio <= 10,000 (equal or less activity): 0 bps EV (neutral).
- If ratio >= 30,000 (3x or more activity): 300 bps EV (+3%).
- Between: linearly interpolates from 0 to 300 bps.
- Purpose: reward increased coinflip activity on last purchase days with better EV.

**NatSpec Accuracy:** "Derive target EV (in bps) based on last-purchase-day flip totals." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_lerpEvBps(uint256 x0, uint256 x1, int256 y0, int256 y1, uint256 x)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _lerpEvBps(uint256 x0, uint256 x1, int256 y0, int256 y1, uint256 x) private pure returns (int256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `x0` (uint256): start x; `x1` (uint256): end x; `y0` (int256): start y; `y1` (int256): end y; `x` (uint256): interpolation point |
| **Returns** | int256: interpolated y value |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `_coinflipTargetEvBps`
**Callees:** None

**ETH Flow:** No
**Invariants:**
- Standard linear interpolation: y = y0 + (x - x0) * (y1 - y0) / (x1 - x0).
- Clamps to y0 if x <= x0, y1 if x >= x1.
- Safe for the specific inputs used (COINFLIP_RATIO_BPS_EQUAL to COINFLIP_RATIO_BPS_TRIPLE, 0 to 300).

**NatSpec Accuracy:** "Linear interpolation helper for EV bps." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_applyEvToRewardPercent(uint16 rewardPercent, int256 evBps)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyEvToRewardPercent(uint16 rewardPercent, int256 evBps) private pure returns (uint16 adjustedPercent)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `rewardPercent` (uint16): base reward percent; `evBps` (int256): EV adjustment in bps |
| **Returns** | `adjustedPercent` (uint16): adjusted reward percent |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `processCoinflipPayouts`
**Callees:** None

**ETH Flow:** No
**Invariants:**
- targetRewardBps = 10,000 + (evBps * 2). For 0 bps EV: targetRewardBps = 10,000. For 300 bps: targetRewardBps = 10,600.
- deltaBps = targetRewardBps - COINFLIP_REWARD_MEAN_BPS (9685). For 0 bps EV: delta = 315. For 300 bps: delta = 915.
- adjustedBps = (rewardPercent * 100) + deltaBps. Converts rewardPercent (in %) to bps, adds delta.
- Rounds back to percent: (adjustedBps + 50) / 100. Banker's-like rounding.
- Clamped: returns 0 if adjustedBps <= 0, type(uint16).max if > 65535.
- For typical inputs: rewardPercent=96 (midrange), evBps=0 -> adjustedBps=9600+315=9915 -> rounded=99%. evBps=300 -> adjustedBps=9600+915=10515 -> rounded=105%.

**NatSpec Accuracy:** "Apply EV-based adjustment to the payout percent (bps) on last purchase day." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Utility Functions

---

### `_targetFlipDay()` [internal view]

| Field | Value |
|-------|-------|
| **Signature** | `function _targetFlipDay() internal view returns (uint48)` |
| **Visibility** | internal |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | uint48: the day new deposits target |

**State Reads:** None directly
**State Writes:** None

**Callers:** `_addDailyFlip`, `coinflipAmount`
**Callees:** `degenerusGame.currentDayView()`

**ETH Flow:** No
**Invariants:** Always returns currentDay + 1 (deposits are for the next day's flip).
**NatSpec Accuracy:** "Calculate the target day for new coinflip deposits." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questApplyReward(address player, uint256 reward, uint8 questType, uint32 streak, bool completed) private returns (uint256)` |
| **Visibility** | private |
| **Mutability** | state-changing (emits event) |
| **Parameters** | `player` (address); `reward` (uint256); `questType` (uint8); `streak` (uint32); `completed` (bool) |
| **Returns** | uint256: reward if completed, 0 otherwise |

**State Reads:** None
**State Writes:** None (only emits event)

**Callers:** `_depositCoinflip`
**Callees:** None

**ETH Flow:** No
**Invariants:** Returns 0 if not completed. Emits `QuestCompleted` event if completed.
**NatSpec Accuracy:** "Helper to process quest rewards and emit event." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_score96(uint256 s)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _score96(uint256 s) private pure returns (uint96)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `s` (uint256): stake in wei |
| **Returns** | uint96: score in whole tokens, capped at uint96.max |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `_updateTopDayBettor`
**Callees:** None

**ETH Flow:** No
**Invariants:** Converts wei to whole tokens (divides by 1 ether). Capped at type(uint96).max to prevent overflow.
**NatSpec Accuracy:** "Convert stake to uint96 score (whole tokens)." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_updateTopDayBettor(address player, uint256 stakeScore, uint48 day)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _updateTopDayBettor(address player, uint256 stakeScore, uint48 day) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address); `stakeScore` (uint256): total stake for this day; `day` (uint48) |
| **Returns** | None |

**State Reads:** `coinflipTopByDay[day]`
**State Writes:** `coinflipTopByDay[day]` (if player beats current leader)

**Callers:** `_addDailyFlip`
**Callees:** `_score96(stakeScore)`

**ETH Flow:** No
**Invariants:** Updates leader if player's score > current leader's score, OR if no leader set (address(0)). Uses cumulative stake for the day (newStake), not just the current deposit.
**NatSpec Accuracy:** "Update day leaderboard if player's score is higher." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### `_bafBracketLevel(uint24 lvl)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _bafBracketLevel(uint24 lvl) private pure returns (uint24)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `lvl` (uint24): raw game level |
| **Returns** | uint24: BAF bracket level (rounded up to nearest multiple of 10) |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `_claimCoinflipsInternal`
**Callees:** None

**ETH Flow:** No
**Invariants:** Rounds up to next multiple of 10: (lvl + 9) / 10 * 10. Level 0 -> 0, level 1 -> 10, level 10 -> 10, level 11 -> 20. Capped at MAX_BAF_BRACKET (type(uint24).max / 10 * 10 = 16,777,210).
**NatSpec Accuracy:** "Round level up to next BAF bracket (multiple of 10)." -- accurate.
**Gas Flags:** None. Note: level 0 maps to bracket 0 (not 10) because (0+9)/10*10 = 0. This is correct since level 0 is pre-game.
**Verdict:** CORRECT

---

### `_resolvePlayer(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolvePlayer(address player) private view returns (address resolved)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): address(0) = msg.sender |
| **Returns** | `resolved` (address): actual player address |

**State Reads:** None directly
**State Writes:** None

**Callers:** `claimCoinflips`, `claimCoinflipsTakeProfit`, `setCoinflipAutoRebuyTakeProfit`
**Callees:** `degenerusGame.isOperatorApproved(player, msg.sender)`

**ETH Flow:** No
**Invariants:** Returns msg.sender if player is address(0). If player != msg.sender, checks operator approval via game contract. Reuses `OnlyBurnieCoin` error for unapproved operators (error reuse for bytecode savings).
**NatSpec Accuracy:** "Resolve player address (address(0) -> msg.sender, else validate approval)." -- accurate.
**Gas Flags:** Reuses `OnlyBurnieCoin` error instead of `NotApproved` -- minor inconsistency but saves bytecode. Not a bug.
**Verdict:** CORRECT -- Informational: error reuse (`OnlyBurnieCoin` for operator approval failure) may confuse debuggers but is intentional for bytecode size.

---

### `_requireApproved(address player)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _requireApproved(address player) private view` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): the account to check approval for |
| **Returns** | None (reverts on failure) |

**State Reads:** None directly
**State Writes:** None

**Callers:** `setCoinflipAutoRebuy`
**Callees:** `degenerusGame.isOperatorApproved(player, msg.sender)`

**ETH Flow:** No
**Invariants:** Reverts `NotApproved` if msg.sender is neither the player nor an approved operator. Self-calls (msg.sender == player) always pass.
**NatSpec Accuracy:** "Check if caller is approved to act on behalf of player." -- accurate.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Constructor

---

### `constructor(address _burnie, address _degenerusGame, address _jackpots, address _wwxrp)`

| Field | Value |
|-------|-------|
| **Signature** | `constructor(address _burnie, address _degenerusGame, address _jackpots, address _wwxrp)` |
| **Visibility** | public (constructor) |
| **Mutability** | state-changing |
| **Parameters** | `_burnie` (address): BurnieCoin; `_degenerusGame` (address): game contract; `_jackpots` (address): jackpots contract; `_wwxrp` (address): WWXRP token |
| **Returns** | None |

**State Reads:** None
**State Writes:** Sets immutable references: `burnie`, `degenerusGame`, `jackpots`, `wwxrp`

**Callers:** Deploy script
**Callees:** None

**ETH Flow:** No
**Invariants:** All four addresses must be valid deployed contracts. No validation in constructor (relies on deploy script correctness).
**NatSpec Accuracy:** No NatSpec. Adequate for constructor.
**Gas Flags:** None
**Verdict:** CORRECT

---

### Modifiers

---

### `onlyDegenerusGameContract()`

| Field | Value |
|-------|-------|
| **Type** | modifier |
| **Check** | `msg.sender != address(degenerusGame)` |
| **Error** | `OnlyDegenerusGame()` |

**Used by:** `settleFlipModeChange`, `processCoinflipPayouts`
**Verdict:** CORRECT

---

### `onlyFlipCreditors()`

| Field | Value |
|-------|-------|
| **Type** | modifier |
| **Check** | `msg.sender != address(degenerusGame) && msg.sender != address(burnie)` |
| **Error** | `OnlyFlipCreditors()` |

**Used by:** `creditFlip`, `creditFlipBatch`
**Verdict:** CORRECT

---

### `onlyBurnieCoin()`

| Field | Value |
|-------|-------|
| **Type** | modifier |
| **Check** | `msg.sender != address(burnie)` |
| **Error** | `OnlyBurnieCoin()` |

**Used by:** `claimCoinflipsFromBurnie`, `consumeCoinflipsForBurn`
**Verdict:** CORRECT

---

## Coinflip Lifecycle Flow

The BurnieCoinflip system follows a multi-phase daily lifecycle:

### 1. Deposit Phase

```
Player calls depositCoinflip(player, amount)
  |
  +-> _depositCoinflip(caller, amount, directDeposit)
       |
       +-> _coinflipLockedDuringTransition()    // Check BAF lock
       +-> _claimCoinflipsInternal(caller, false) // Settle pending claims
       +-> burnie.burnForCoinflip(caller, amount) // BURN tokens (CEI)
       +-> questModule.handleFlip(caller, amount)  // Quest integration
       +-> _questApplyReward(...)                  // Apply quest bonus
       +-> degenerusGame.recordCoinflipDeposit(amount) // Track in game
       |
       +-> Calculate recycling bonus:
       |   if autoRebuyEnabled -> rollAmount = autoRebuyCarry
       |   else                -> rollAmount = mintable (freshly settled)
       |   rebetAmount = min(creditedFlip, rollAmount)
       |   if afKing -> _afKingRecyclingBonus(rebetAmount, deityBonus)
       |   else      -> _recyclingBonus(rebetAmount)
       |
       +-> _addDailyFlip(caller, creditedFlip, recordAmount, ...)
            |
            +-> consumeCoinflipBoon() // Optional boon boost (manual only)
            +-> coinflipBalance[targetDay][player] += creditedFlip
            +-> _updateTopDayBettor() // Leaderboard update
            +-> Bounty logic (direct deposits only, requires beating record by 1%)
```

### 2. Resolution Phase (during advanceGame)

```
Game calls processCoinflipPayouts(bonusFlip, rngWord, epoch)
  |
  +-> seedWord = keccak256(rngWord, epoch)  // Per-day entropy
  +-> Determine rewardPercent:
  |     5% chance: 50%  (1.5x payout)
  |     5% chance: 150% (2.5x payout)
  |    90% chance: [78%, 115%] (normal range)
  |
  +-> EV adjustment (bonusFlip only, not presale):
  |   _coinflipTargetEvBps(prevTotal, currentTotal)
  |   _applyEvToRewardPercent(rewardPercent, evBps)
  |
  +-> Presale bonus: +6% if presale active and bonusFlip
  +-> Win = (rngWord & 1) == 1  (50/50 from original rngWord)
  |
  +-> Record: coinflipDayResult[epoch] = {rewardPercent, win}
  +-> Bounty resolution:
  |   If bountyOwner exists: halve bounty pool
  |   If win: credit half as flip stake, pay DGNRS bounty
  |   Clear bountyOwner regardless
  |
  +-> flipsClaimableDay = epoch  // Enable claims
  +-> currentBounty += 1000 ether (PRICE_COIN_UNIT)
```

### 3. Claim Phase

```
Player calls claimCoinflips(player, amount) [or variants]
  |
  +-> Check: !rngLocked()
  +-> _resolvePlayer(player)
  +-> _claimCoinflipsAmount(player, amount, true)
       |
       +-> _claimCoinflipsInternal(player, false)
       |    |
       |    +-> Iterate from lastClaim+1 to flipsClaimableDay (up to 90 days)
       |    +-> For each resolved day:
       |    |   Win: payout = stake + (stake * rewardPercent / 100)
       |    |         if autoRebuy: extract takeProfit multiples -> mintable; rest -> carry
       |    |         if autoRebuy: carry += recyclingBonus(carry)
       |    |         else: mintable += payout
       |    |   Loss: stake forfeited, carry zeroed, lossCount++
       |    |
       |    +-> BAF credit: jackpots.recordBafFlip(player, bracket, winningBafCredit)
       |    +-> WWXRP consolation: wwxrp.mintPrize(player, lossCount * 1 ether)
       |    +-> Update: lastClaim = processed, autoRebuyCarry = carry
       |
       +-> claimableStored = stored - toClaim
       +-> burnie.mintForCoinflip(player, toClaim)  // MINT tokens
```

### 4. Auto-Rebuy Cycle

```
When autoRebuyEnabled:
  Win payout -> extract takeProfit multiples -> mintable (claimed)
            -> remainder -> carry (re-staked automatically)
            -> carry gets recycling bonus (1% base, or afKing enhanced)
  Loss      -> carry zeroed (principal lost)
  Next deposit -> carry is added to new stake as "free roll"
```

---

## EV Calculation Verification

The EV adjustment system incentivizes increased coinflip activity on last-purchase-day bonus flips.

### Chain of Functions

1. **`_coinflipTargetEvBps(prevTotal, currentTotal)`**
   - Inputs: previous level's last-purchase-day flip deposits vs current level's.
   - Compute: `ratioBps = (currentTotal * 10,000) / prevTotal`
   - Output: Target EV in BPS:

   | Condition | ratioBps | evBps |
   |-----------|----------|-------|
   | prevTotal == 0 | N/A | 0 (neutral) |
   | ratio <= 10,000 (1x) | <= 10,000 | 0 (neutral) |
   | ratio >= 30,000 (3x) | >= 30,000 | 300 (+3%) |
   | Between 1x-3x | 10,001-29,999 | lerp(0, 300) |

2. **`_lerpEvBps(x0, x1, y0, y1, x)`**
   - Standard linear interpolation.
   - For the specific call: x0=10,000, x1=30,000, y0=0, y1=300.
   - Example: ratioBps=20,000 (2x) -> evBps = (10,000 * 300) / 20,000 = 150 bps.

3. **`_applyEvToRewardPercent(rewardPercent, evBps)`**
   - `targetRewardBps = 10,000 + (evBps * 2)`
   - `deltaBps = targetRewardBps - 9,685` (COINFLIP_REWARD_MEAN_BPS)
   - `adjustedBps = (rewardPercent * 100) + deltaBps`
   - `adjustedPercent = (adjustedBps + 50) / 100`

   Worked examples:

   | evBps | targetRewardBps | deltaBps | Input % | adjustedBps | Output % |
   |-------|-----------------|----------|---------|-------------|----------|
   | 0 | 10,000 | 315 | 96 | 9,915 | 99 |
   | 0 | 10,000 | 315 | 78 | 8,115 | 81 |
   | 0 | 10,000 | 315 | 115 | 11,815 | 118 |
   | 150 | 10,300 | 615 | 96 | 10,215 | 102 |
   | 300 | 10,600 | 915 | 96 | 10,515 | 105 |
   | 300 | 10,600 | 915 | 78 | 8,715 | 87 |
   | 300 | 10,600 | 915 | 115 | 12,415 | 124 |

   **Observation:** Even with evBps=0 (neutral), the delta is +315 bps, shifting the mean reward from ~96.85% to ~100%. This creates a slightly positive-EV baseline for last-purchase-day bonus flips. At max activity (3x), the shift is +915 bps, pushing the effective mean to ~106%.

### Recycling Bonus Verification

- **Base (`_recyclingBonus`):** 1% of rebet amount, capped at 1,000 BURNIE.
- **afKing (`_afKingRecyclingBonus`):**
  - Base: 160 BPS = 1.6% (AFKING_RECYCLE_BONUS_BPS).
  - Deity bonus: 0.01% per level since activation, max 1.5% (AFKING_DEITY_BONUS_MAX_HALF_BPS = 300 half-bps).
  - Total afKing + deity: up to 1.6% + 1.5% = 3.1%.
  - Deity bonus capped at DEITY_RECYCLE_CAP (1M BURNIE); amounts above receive base-only bonus.
  - Half-bps math: `(amount * totalHalfBps) / (BPS_DENOMINATOR * 2)` = `(amount * totalHalfBps) / 20,000`.

### afKing Deity Bonus Verification

- **`_afKingDeityBonusHalfBpsWithLevel(player, currentLevel)`:**
  - `levelsActive = currentLevel - activationLevel`
  - `bonus = levelsActive * 2` (half-bps)
  - Max: 300 half-bps (150 levels to max)
  - Conversion: 300 half-bps = 150 bps = 1.5%

---

## Storage Mutation Map

| Function | Variables Written | Write Type |
|----------|------------------|------------|
| `settleFlipModeChange` | `playerState[player].claimableStored` | Accumulate |
| `_depositCoinflip` | `playerState[caller].claimableStored` | Accumulate |
| `_claimCoinflipsTakeProfit` | `playerState[player].claimableStored` | Set (stored - toClaim) |
| `_claimCoinflipsAmount` | `playerState[player].claimableStored` | Set (stored - toClaim) |
| `_claimCoinflipsInternal` | `coinflipBalance[cursor][player]` | Zero (clear on process) |
| `_claimCoinflipsInternal` | `playerState[player].lastClaim` | Set (cursor position) |
| `_claimCoinflipsInternal` | `playerState[player].autoRebuyCarry` | Set (carry or 0) |
| `_addDailyFlip` | `coinflipBalance[targetDay][player]` | Accumulate |
| `_addDailyFlip` | `biggestFlipEver` | Set (new record) |
| `_addDailyFlip` | `bountyOwedTo` | Set (new bounty owner) |
| `_addDailyFlip` | `coinflipTopByDay[day]` (via `_updateTopDayBettor`) | Set (new leader) |
| `_setCoinflipAutoRebuy` | `playerState[player].autoRebuyEnabled` | Set |
| `_setCoinflipAutoRebuy` | `playerState[player].autoRebuyStop` | Set |
| `_setCoinflipAutoRebuy` | `playerState[player].autoRebuyStartDay` | Set |
| `_setCoinflipAutoRebuy` | `playerState[player].autoRebuyCarry` | Zero (on disable) |
| `_setCoinflipAutoRebuyTakeProfit` | `playerState[player].autoRebuyStop` | Set |
| `processCoinflipPayouts` | `coinflipDayResult[epoch]` | Set (new result) |
| `processCoinflipPayouts` | `flipsClaimableDay` | Set (epoch) |
| `processCoinflipPayouts` | `currentBounty` | Modify (halve + add 1000) |
| `processCoinflipPayouts` | `bountyOwedTo` | Zero (clear) |

---

## Cross-Contract Call Graph

| Function | Calls To | Contract | Method | Direction |
|----------|----------|----------|--------|-----------|
| `_depositCoinflip` | BurnieCoin | `burnie` | `burnForCoinflip(caller, amount)` | Outgoing |
| `_depositCoinflip` | Quests | `questModule` | `handleFlip(caller, amount)` | Outgoing |
| `_depositCoinflip` | Game | `degenerusGame` | `recordCoinflipDeposit(amount)` | Outgoing |
| `_depositCoinflip` | Game | `degenerusGame` | `afKingModeFor(caller)` | Outgoing (view) |
| `_depositCoinflip` | Game | `degenerusGame` | `deityPassCountFor(caller)` | Outgoing (view) |
| `_depositCoinflip` | Game | `degenerusGame` | `level()` | Outgoing (view) |
| `depositCoinflip` | Game | `degenerusGame` | `isOperatorApproved(player, msg.sender)` | Outgoing (view) |
| `_claimCoinflipsInternal` | Game | `degenerusGame` | `syncAfKingLazyPassFromCoin(player)` | Outgoing |
| `_claimCoinflipsInternal` | Game | `degenerusGame` | `deityPassCountFor(player)` | Outgoing (view) |
| `_claimCoinflipsInternal` | Game | `degenerusGame` | `level()` | Outgoing (view) |
| `_claimCoinflipsInternal` | Game | `degenerusGame` | `purchaseInfo()` | Outgoing (view) |
| `_claimCoinflipsInternal` | Game | `degenerusGame` | `gameOver()` | Outgoing (view) |
| `_claimCoinflipsInternal` | Jackpots | `jackpots` | `recordBafFlip(player, bafLvl, winningBafCredit)` | Outgoing |
| `_claimCoinflipsInternal` | WWXRP | `wwxrp` | `mintPrize(player, lossCount * 1 ether)` | Outgoing |
| `_claimCoinflipsTakeProfit` | BurnieCoin | `burnie` | `mintForCoinflip(player, toClaim)` | Outgoing |
| `_claimCoinflipsAmount` | BurnieCoin | `burnie` | `mintForCoinflip(player, toClaim)` | Outgoing |
| `_addDailyFlip` | Game | `degenerusGame` | `consumeCoinflipBoon(player)` | Outgoing |
| `_addDailyFlip` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `_coinflipLockedDuringTransition` | Game | `degenerusGame` | `purchaseInfo()` | Outgoing (view) |
| `_coinflipLockedDuringTransition` | Game | `degenerusGame` | `gameOver()` | Outgoing (view) |
| `_afKingDeityBonusHalfBpsWithLevel` | Game | `degenerusGame` | `afKingActivatedLevelFor(player)` | Outgoing (view) |
| `_setCoinflipAutoRebuy` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `_setCoinflipAutoRebuy` | Game | `degenerusGame` | `deactivateAfKingFromCoin(player)` | Outgoing |
| `_setCoinflipAutoRebuy` | BurnieCoin | `burnie` | `mintForCoinflip(player, mintable)` | Outgoing |
| `_setCoinflipAutoRebuyTakeProfit` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `_setCoinflipAutoRebuyTakeProfit` | Game | `degenerusGame` | `deactivateAfKingFromCoin(player)` | Outgoing |
| `_setCoinflipAutoRebuyTakeProfit` | BurnieCoin | `burnie` | `mintForCoinflip(player, mintable)` | Outgoing |
| `processCoinflipPayouts` | Game | `degenerusGame` | `lootboxPresaleActiveFlag()` | Outgoing (view) |
| `processCoinflipPayouts` | Game | `degenerusGame` | `lastPurchaseDayFlipTotals()` | Outgoing (view) |
| `processCoinflipPayouts` | Game | `degenerusGame` | `payCoinflipBountyDgnrs(to)` | Outgoing |
| `claimCoinflips` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `claimCoinflipsTakeProfit` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `claimCoinflipsFromBurnie` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `consumeCoinflipsForBurn` | Game | `degenerusGame` | `rngLocked()` | Outgoing (view) |
| `_resolvePlayer` | Game | `degenerusGame` | `isOperatorApproved(player, msg.sender)` | Outgoing (view) |
| `_requireApproved` | Game | `degenerusGame` | `isOperatorApproved(player, msg.sender)` | Outgoing (view) |
| `_targetFlipDay` | Game | `degenerusGame` | `currentDayView()` | Outgoing (view) |
| `settleFlipModeChange` | Game (incoming) | `degenerusGame` | `settleFlipModeChange(player)` | Incoming |
| `processCoinflipPayouts` | Game (incoming) | `degenerusGame` | `processCoinflipPayouts(...)` | Incoming |
| `creditFlip` | Game/Coin (incoming) | `degenerusGame`/`burnie` | `creditFlip(player, amount)` | Incoming |
| `creditFlipBatch` | Game/Coin (incoming) | `degenerusGame`/`burnie` | `creditFlipBatch(...)` | Incoming |
| `claimCoinflipsFromBurnie` | BurnieCoin (incoming) | `burnie` | `claimCoinflipsFromBurnie(...)` | Incoming |
| `consumeCoinflipsForBurn` | BurnieCoin (incoming) | `burnie` | `consumeCoinflipsForBurn(...)` | Incoming |

### Summary by Contract

| External Contract | State-Changing Calls | View Calls |
|-------------------|---------------------|------------|
| BurnieCoin (`burnie`) | 5 (3x mintForCoinflip, 1x burnForCoinflip) | 0 |
| DegenerusGame (`degenerusGame`) | 5 (recordCoinflipDeposit, syncAfKingLazyPassFromCoin, deactivateAfKingFromCoin x2, consumeCoinflipBoon, payCoinflipBountyDgnrs) | 16 (rngLocked x5, purchaseInfo x2, gameOver x2, level x2, isOperatorApproved x2, afKingModeFor, deityPassCountFor x2, afKingActivatedLevelFor, currentDayView, lootboxPresaleActiveFlag, lastPurchaseDayFlipTotals) |
| Jackpots (`jackpots`) | 1 (recordBafFlip) | 0 |
| WWXRP (`wwxrp`) | 1 (mintPrize) | 0 |
| Quests (`questModule`) | 1 (handleFlip) | 0 |

---

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 0 | No significant inefficiencies |
| INFORMATIONAL | 2 | See below |
| CORRECT | 37 | All functions verified correct (+ constructor + 3 modifiers) |

### Informational Notes

**1. Error reuse in `_resolvePlayer`**
- `_resolvePlayer` uses `OnlyBurnieCoin()` error when an operator is not approved, instead of the more descriptive `NotApproved()`.
- This is intentional for bytecode size optimization but could confuse debuggers.
- Impact: None (display-only).

**2. `_viewClaimableCoin` does not simulate auto-rebuy**
- The view function `previewClaimCoinflips` returns stored + daily winnings but does not account for auto-rebuy carry or recycling bonuses.
- For auto-rebuy players, the actual claimable amount may differ from the preview.
- This is acceptable for a view function and documented in the audit entry.

### Key Correctness Properties Verified

1. **CEI Pattern:** `_depositCoinflip` burns tokens before crediting flip stake. No reentrancy vector.
2. **RNG Lock Guards:** All claim functions check `rngLocked()` to prevent BAF credit manipulation during VRF pending.
3. **BAF Transition Lock:** `_coinflipLockedDuringTransition()` blocks deposits at BAF resolution levels (every 10th level) on last purchase day with RNG locked.
4. **Bounty Fairness:** Bounty requires exceeding record by 1% to steal, preventing spam. Cleared regardless of win/loss.
5. **Auto-Rebuy Carry Integrity:** Carry is zeroed on loss, credited with recycling bonus on win. Stale carry from expired days is cleared when start < minClaimableDay.
6. **Deity Bonus Cap:** `_afKingDeityBonusHalfBpsWithLevel` caps at 300 half-bps (1.5%). `_afKingRecyclingBonus` caps deity-portion at 1M BURNIE.
7. **EV Adjustment Correctness:** Linear interpolation from neutral (1x activity) to +3% EV (3x activity). Baseline shift of +315 bps ensures last-purchase-day bonus flips are slightly positive-EV.
8. **Claim Window Enforcement:** Non-auto-rebuy players expire after 30/90 days. Auto-rebuy players use `autoRebuyStartDay` as minimum (no expiry while auto-rebuy active).
9. **Deep Auto-Rebuy:** Disabling auto-rebuy processes up to 1095 days (3 years) to recover all accumulated positions.
10. **WWXRP Consolation:** Loss days mint 1 WWXRP per loss day -- ensures losers receive something.
