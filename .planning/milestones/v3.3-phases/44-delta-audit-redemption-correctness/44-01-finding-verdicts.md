# Phase 44 Finding Verdicts

| ID | Finding | Verdict | Severity | Fix Required |
|----|---------|---------|----------|-------------|
| CP-08 | Deterministic burn double-spend | CONFIRMED | HIGH | Yes |
| CP-06 | Stuck claims at game-over | CONFIRMED | HIGH | Yes |
| Seam-1 | DGNRS.burn() fund trap | CONFIRMED | HIGH | Yes |
| CP-02 | Period index zero sentinel | REFUTED | INFO | No |
| CP-07 | Coinflip resolution stuck-claim | CONFIRMED | MEDIUM | Yes |

---

## CP-08: Deterministic Burn Double-Spend via Missing Segregation Deduction

**Verdict:** CONFIRMED
**Severity:** HIGH (direct fund loss -- reserved ETH/BURNIE counted in proportional share of post-gameOver burners)
**Requirements:** DELTA-03

### Evidence

Three functions compute `totalMoney` and `totalBurnie` to determine a burner's proportional share. Two correctly subtract the segregated pending amounts; one does not.

**`_deterministicBurnFrom` (`StakedDegenerusStonk.sol:477-482`) -- MISSING deduction:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth;
//                   ^^^ Does NOT subtract pendingRedemptionEthValue
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

uint256 totalBurnie = burnieBal + claimableBurnie;
//                    ^^^ Does NOT subtract pendingRedemptionBurnie
burnieOut = (totalBurnie * amount) / supplyBefore;
```

**`previewBurn` (`StakedDegenerusStonk.sol:633,651`) -- CORRECT:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
//                                                      ^^^ Correctly subtracted
uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
//                                                  ^^^ Correctly subtracted
```

**`_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:695,701`) -- CORRECT:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
```

### Root Cause

`_deterministicBurnFrom` predates the gambling burn system. When the gambling burn was added, `previewBurn` and `_submitGamblingClaimFrom` were updated to subtract pending redemption reserves, but `_deterministicBurnFrom` was not updated to match.

### Impact

After game-over, any player calling `burn()` or `burnWrapped()` receives a proportional share calculated against the FULL contract balance including ETH/BURNIE already reserved for pending gambling claims. This means:

1. **Double-spend of reserved ETH:** If 10 ETH is reserved for gambling claimants and the contract holds 100 ETH total, a deterministic burner's share is computed from 100 ETH instead of 90 ETH. The deterministic burner receives more than their fair share.
2. **Double-spend of reserved BURNIE:** Same pattern for BURNIE reserves.
3. **Gambling claimants receive less than owed:** When gambling claimants later call `claimRedemption()`, the contract may have insufficient ETH/BURNIE because deterministic burners already withdrew it.

**Numerical example:** Contract holds 100 ETH, of which 10 ETH is `pendingRedemptionEthValue`. totalSupply = 1000 sDGNRS. A player burns 100 sDGNRS:
- INCORRECT (`_deterministicBurnFrom`): `(100 * 100) / 1000 = 10 ETH` (includes reserved 10 ETH)
- CORRECT (`previewBurn`): `((100-10) * 100) / 1000 = 9 ETH` (excludes reserved)

The deterministic burner receives 1 ETH that belongs to gambling claimants.

### Recommended Fix

Add `- pendingRedemptionEthValue` and `- pendingRedemptionBurnie` to both `totalMoney` and `totalBurnie` in `_deterministicBurnFrom`:

**Before (`StakedDegenerusStonk.sol:477-482`):**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth;
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

uint256 burnieBal = coin.balanceOf(address(this));
uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
uint256 totalBurnie = burnieBal + claimableBurnie;
burnieOut = (totalBurnie * amount) / supplyBefore;
```

**After:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

uint256 burnieBal = coin.balanceOf(address(this));
uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
burnieOut = (totalBurnie * amount) / supplyBefore;
```

This is a two-line change that makes `_deterministicBurnFrom` consistent with `previewBurn` and `_submitGamblingClaimFrom`.

---

## CP-06: Stuck Claims at Game-Over -- Missing Redemption Resolution in _gameOverEntropy

**Verdict:** CONFIRMED
**Severity:** HIGH (permanent fund loss -- players who burned sDGNRS in the last active period cannot claim redemption)
**Requirements:** DELTA-04

### Evidence

The normal advance loop calls `rngGate` (`DegenerusGameAdvanceModule.sol:229`) which resolves pending gambling burns. The game-over path calls `_gameOverEntropy` instead, which does NOT resolve pending gambling burns.

**`rngGate` (`DegenerusGameAdvanceModule.sol:770-780`) -- HAS redemption resolution:**
```solidity
// Resolve gambling burn period if pending
{
    IStakedDegenerusStonk sdgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
    if (sdgnrs.hasPendingRedemptions()) {
        uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25);
        uint48 flipDay = day + 1;
        uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
        if (burnieToCredit != 0) {
            coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);
        }
    }
}
```

**`_gameOverEntropy` (`DegenerusGameAdvanceModule.sol:813-862`) -- MISSING redemption resolution:**
```solidity
function _gameOverEntropy(
    uint48 ts,
    uint48 day,
    uint24 lvl,
    bool isTicketJackpotDay
) private returns (uint256 word) {
    if (rngWordByDay[day] != 0) return rngWordByDay[day];

    uint256 currentWord = rngWordCurrent;
    if (currentWord != 0 && rngRequestTime != 0) {
        currentWord = _applyDailyRng(day, currentWord);
        if (lvl != 0) {
            coinflip.processCoinflipPayouts(
                isTicketJackpotDay,
                currentWord,
                day
            );
        }
        _finalizeLootboxRng(currentWord);
        return currentWord;
        // ^^^ No sdgnrs.hasPendingRedemptions() / resolveRedemptionPeriod() call
    }
    // ... fallback paths also lack redemption resolution
}
```

**Call chain:** `advanceGame` -> `_handleGameOverPath` (`DegenerusGameAdvanceModule.sol:451`) calls `_gameOverEntropy(ts, day, lvl, lastPurchase)` instead of `rngGate`. The `rngGate` function is only called from the normal daily advance loop (`DegenerusGameAdvanceModule.sol:229`).

A global search for `resolveRedemptionPeriod` and `hasPendingRedemptions` confirms they appear only in `rngGate` (lines 772, 775) and nowhere in `_gameOverEntropy` or any other function in this module.

### Root Cause

`_gameOverEntropy` was a pre-existing entropy acquisition function. When the gambling burn system was added, redemption resolution logic was inserted into `rngGate()` only. The parallel `_gameOverEntropy` path was not updated because it follows a different code path for game-over scenarios.

### Impact

If a player submits a gambling burn during the last active game period (the period immediately before the liveness guard triggers game-over):

1. Their sDGNRS is burned and a `PendingRedemption` is recorded.
2. The next `advanceGame` call triggers `_handleGameOverPath` -> `_gameOverEntropy` instead of `rngGate`.
3. `_gameOverEntropy` processes coinflip payouts but does NOT call `resolveRedemptionPeriod`.
4. The `RedemptionPeriod.roll` remains 0 (unresolved).
5. `claimRedemption()` will revert with `NotResolved()` permanently.
6. The player's sDGNRS is burned, ETH is segregated in `pendingRedemptionEthValue`, and neither the player nor anyone else can recover it.

This is permanent loss of both the burned sDGNRS and the underlying ETH/BURNIE reserves.

### Recommended Fix

Add the redemption resolution block from `rngGate` to all code paths within `_gameOverEntropy` that produce a valid RNG word. The block should mirror lines 770-780 of `rngGate`.

**After `_applyDailyRng` in the normal VRF path (`DegenerusGameAdvanceModule.sol:823-832`), before `return currentWord`:**

```solidity
currentWord = _applyDailyRng(day, currentWord);
if (lvl != 0) {
    coinflip.processCoinflipPayouts(
        isTicketJackpotDay,
        currentWord,
        day
    );
}

// --- ADD THIS BLOCK ---
{
    IStakedDegenerusStonk sdgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
    if (sdgnrs.hasPendingRedemptions()) {
        uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25);
        uint48 flipDay = day + 1;
        uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
        if (burnieToCredit != 0) {
            coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);
        }
    }
}
// --- END BLOCK ---

_finalizeLootboxRng(currentWord);
return currentWord;
```

The same block must also be added to the fallback path (`DegenerusGameAdvanceModule.sol:840-849`) after the `_applyDailyRng(day, fallbackWord)` and `processCoinflipPayouts` calls.

**Note:** The `flipDay = day + 1` assignment means the resolved coinflip depends on the NEXT day's `processCoinflipPayouts`. At game-over, if no further days are processed, the coinflip for `flipDay` may not resolve (see CP-07). The fix for CP-06 ensures the period IS resolved (roll != 0), but the coinflip dependency remains a separate issue (CP-07).

---

## Seam-1: DGNRS.burn() Fund Trap -- Gambling Claim Recorded Under Contract Address

**Verdict:** CONFIRMED
**Severity:** HIGH (permanent fund loss -- gambling claim is orphaned under DGNRS contract address which has no claimRedemption function)
**Requirements:** DELTA-05

### Evidence

**Entry point: `DegenerusStonk.burn()` (`DegenerusStonk.sol:164-181`):**
```solidity
function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    _burn(msg.sender, amount);                    // Burns DGNRS from caller
    (ethOut, stethOut, burnieOut) = stonk.burn(amount);  // Calls sDGNRS.burn()
    // ^^^ msg.sender to sDGNRS = address(DGNRS), NOT the original player
```

**Receiver: `StakedDegenerusStonk.burn()` (`StakedDegenerusStonk.sol:435-442`):**
```solidity
function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    if (game.gameOver()) {
        return _deterministicBurn(msg.sender, amount);
        // ^^^ msg.sender = DGNRS contract; deterministic path works because
        //     it sends ETH/BURNIE to msg.sender (DGNRS), and DGNRS forwards to player
    }
    if (game.rngLocked()) revert BurnsBlockedDuringRng();
    _submitGamblingClaim(msg.sender, amount);
    // ^^^ msg.sender = DGNRS contract address
    //     Records claim under address(DGNRS), NOT the original player
    return (0, 0, 0);
}
```

**`_submitGamblingClaim` (`StakedDegenerusStonk.sol:669-671`):**
```solidity
function _submitGamblingClaim(address player, uint256 amount) private {
    _submitGamblingClaimFrom(player, player, amount);
    // player = msg.sender = address(DGNRS)
}
```

**`_submitGamblingClaimFrom` records the claim (`StakedDegenerusStonk.sol:718-724`):**
```solidity
PendingRedemption storage claim = pendingRedemptions[beneficiary];
// beneficiary = address(DGNRS)
claim.ethValueOwed += ethValueOwed;
claim.burnieOwed += burnieOwed;
claim.periodIndex = currentPeriod;
```

The DGNRS contract (`DegenerusStonk.sol`) has no `claimRedemption()` function. A search of the full contract confirms it contains only: `transfer`, `transferFrom`, `approve`, `unwrapTo`, `burn`, `previewBurn`, `burnForSdgnrs`, `_transfer`, `_burn`. There is no mechanism for the DGNRS contract to call `sDGNRS.claimRedemption()`.

**Asymmetry with deterministic path:** The deterministic path (`_deterministicBurn` -> `_deterministicBurnFrom`) sends ETH/stETH/BURNIE directly to `msg.sender` (DGNRS), and `DegenerusStonk.burn()` then forwards them to the player (lines 169-178). This works because deterministic burns are atomic -- assets flow immediately. The gambling path cannot work this way because it is a two-phase commit/reveal.

**Asymmetry with `burnWrapped` path:** The `burnWrapped()` function (`StakedDegenerusStonk.sol:451-458`) correctly passes `msg.sender` (the player) as `beneficiary`:
```solidity
function burnWrapped(uint256 amount) external returns (...) {
    dgnrsWrapper.burnForSdgnrs(msg.sender, amount);  // Burns DGNRS from player
    // ...
    _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
    //                       ^^^ beneficiary = msg.sender = player (CORRECT)
}
```

### Root Cause

`sDGNRS.burn()` uses `msg.sender` as the beneficiary for both the deterministic and gambling paths. For direct calls, `msg.sender` is the player. For proxy calls from `DGNRS.burn()`, `msg.sender` is the DGNRS contract address. The deterministic path masks this issue because assets are sent immediately to `msg.sender` (DGNRS) which forwards them. The gambling path exposes it because the deferred claim is recorded under an address that has no claim mechanism.

### Impact

During active game (before gameOver), any DGNRS holder who calls `DGNRS.burn()` instead of `sDGNRS.burnWrapped()`:

1. Their DGNRS is burned (supply decreased, tokens gone).
2. sDGNRS is burned from the DGNRS contract's balance.
3. A `PendingRedemption` is recorded under `address(DGNRS)`.
4. The DGNRS contract has no `claimRedemption()` function.
5. The claim is permanently orphaned -- ETH stays segregated in `pendingRedemptionEthValue` forever.
6. The player loses both their DGNRS tokens AND the underlying ETH/BURNIE value.

### Recommended Fix

Three options with tradeoffs:

**Option A (Simplest -- recommended): Revert `DGNRS.burn()` during active game**

```solidity
// DegenerusStonk.sol:burn()
function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    _burn(msg.sender, amount);
    (ethOut, stethOut, burnieOut) = stonk.burn(amount);
    // During active game, stonk.burn() returns (0,0,0) -- gambling path
    // The claim is recorded under address(this) which can't claim.
    // SOLUTION: revert during active game.
    if (ethOut == 0 && stethOut == 0 && burnieOut == 0) {
        revert("Use burnWrapped() during active game");
    }
    // ... forward assets to player
}
```

**Tradeoff:** DGNRS holders must use `burnWrapped()` during active game. Simple, no sDGNRS changes needed.

**Option B: Add `burnFor(address beneficiary, uint256 amount)` to sDGNRS**

Add a new function that DGNRS can call with the player's address:
```solidity
function burnFor(address beneficiary, uint256 amount) external returns (...) {
    if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();
    // ... same logic as burn() but uses beneficiary instead of msg.sender
}
```

**Tradeoff:** Adds new function to sDGNRS. More complex but preserves `DGNRS.burn()` during active game.

**Option C: Route DGNRS.burn() through burnWrapped logic**

Modify `DegenerusStonk.burn()` to call `sDGNRS.burnWrapped()` instead of `sDGNRS.burn()`:
```solidity
// Not directly possible -- burnWrapped() burns from sDGNRS balance, not caller
```

**Tradeoff:** Would require architectural changes to sDGNRS. Not recommended.

**Recommendation:** Option A is simplest and safest. DGNRS holders already have `burnWrapped()` as the correct path during active game. After gameOver, `DGNRS.burn()` works correctly (deterministic path).

---

## CP-02: Period Index Zero Sentinel -- Day Index Never Returns Zero

**Verdict:** REFUTED (finding is safe by construction)
**Severity:** INFO (no vulnerability -- the `+ 1` offset in `currentDayIndexAt` prevents sentinel collision)
**Requirements:** DELTA-06

### Evidence

**`GameTimeLib.currentDayIndexAt` (`GameTimeLib.sol:31-34`):**
```solidity
function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
    uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
    return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    //                                                                ^^^
    // The +1 ensures day 1 is the first day. Zero sentinel is safe.
}
```

**`ContractAddresses.DEPLOY_DAY_BOUNDARY` (`ContractAddresses.sol:7`):**
```solidity
uint48 internal constant DEPLOY_DAY_BOUNDARY = 0;
// Placeholder -- deploy script patches this to the actual deploy day boundary
```

**`claimRedemption` sentinel check (`StakedDegenerusStonk.sol:578`):**
```solidity
if (claim.periodIndex == 0) revert NoClaim();
// periodIndex is set from game.currentDayView() which returns currentDayIndex()
```

**Analysis:**

1. `currentDayBoundary = (ts - JACKPOT_RESET_TIME) / 1 days` is the number of whole days since Unix epoch adjusted for the 22:57 UTC reset.
2. `DEPLOY_DAY_BOUNDARY` is set to the `currentDayBoundary` value on the deploy day.
3. The formula returns `currentDayBoundary - DEPLOY_DAY_BOUNDARY + 1`.
4. On deploy day: `currentDayBoundary == DEPLOY_DAY_BOUNDARY`, so `return 0 - 0 + 1 = 1`.
5. On all subsequent days: the result is `>= 2`.
6. Therefore `currentDayIndexAt()` returns `>= 1` for all timestamps at or after deployment.
7. The zero sentinel `periodIndex == 0` in `claimRedemption` can never collide with a real period index.

**Edge case -- underflow:** If `DEPLOY_DAY_BOUNDARY` were set incorrectly (higher than the actual deploy day boundary), the subtraction `currentDayBoundary - DEPLOY_DAY_BOUNDARY` would underflow. However, Solidity 0.8.34 has built-in overflow protection -- this would revert, not produce a wrong result. This is a deploy pipeline correctness dependency, not a contract vulnerability.

### Root Cause

No vulnerability exists. The `+ 1` in `currentDayIndexAt` was specifically designed to make day indexing 1-based, preserving 0 as a clean sentinel value.

### Impact

None. The finding is safe by construction. The `periodIndex == 0` sentinel check in `claimRedemption` works correctly for all post-deploy timestamps.

### Recommended Fix

No code fix needed. The design is correct.

**Deployment note:** The deploy pipeline must set `DEPLOY_DAY_BOUNDARY` to `(deployTimestamp - JACKPOT_RESET_TIME) / 1 days` at compile time. If this value is wrong, `currentDayIndexAt` will revert on underflow (fail-safe) rather than produce incorrect results (fail-dangerous).

---

## CP-07: Coinflip Resolution Dependency Blocks ETH Claim at Game Boundary

**Verdict:** CONFIRMED
**Severity:** MEDIUM (indirect fund loss -- ETH payout blocked by unresolvable coinflip dependency at game-over boundary)
**Requirements:** DELTA-07

### Evidence

**Step 1: `resolveRedemptionPeriod` sets `flipDay = day + 1` (`DegenerusGameAdvanceModule.sol:774`):**
```solidity
// Inside rngGate, during day N+1:
uint48 flipDay = day + 1;  // flipDay = N+2
uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
```

**Step 2: `claimRedemption` requires coinflip for flipDay to be resolved (`StakedDegenerusStonk.sol:584-585`):**
```solidity
(uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay);
if (rewardPercent == 0 && !flipWon) revert FlipNotResolved();
```

**Step 3: `getCoinflipDayResult` returns the stored result (`BurnieCoinflip.sol:356-358`):**
```solidity
function getCoinflipDayResult(uint48 day) external view returns (uint16 rewardPercent, bool win) {
    CoinflipDayResult memory result = coinflipDayResult[day];
    return (result.rewardPercent, result.win);
}
```

The `CoinflipDayResult` struct has `uint16 rewardPercent` and `bool win`. An unresolved day has `rewardPercent == 0` and `win == false` (default values), which matches the `FlipNotResolved` check.

**Step 4: coinflip resolution happens via `processCoinflipPayouts(epoch)` (`BurnieCoinflip.sol:776-814`):**
```solidity
function processCoinflipPayouts(
    bool bonusFlip,
    uint256 rngWord,
    uint48 epoch
) external onlyDegenerusGameContract {
    // ... computes rewardPercent (always >= 50, never 0)
    coinflipDayResult[epoch] = CoinflipDayResult({
        rewardPercent: rewardPercent,
        win: win
    });
}
```

Note: `rewardPercent` is always `>= 50` after `processCoinflipPayouts` runs (the minimum roll is 50% from `roll == 0`). So a resolved day will always have `rewardPercent >= 50`, distinguishing it from unresolved (0).

**Step 5: Timeline analysis:**

- Day N: Player burns sDGNRS. Gambling claim submitted with `periodIndex = N`.
- Day N+1: `rngGate` processes VRF. Calls `resolveRedemptionPeriod(roll, flipDay=N+2)`. Calls `processCoinflipPayouts(epoch=N+1)`. Period N is now resolved with `roll != 0`. But `flipDay = N+2`.
- Day N+2: NORMALLY, `rngGate` or `_gameOverEntropy` would call `processCoinflipPayouts(epoch=N+2)`, resolving the coinflip for `flipDay=N+2`.

**Critical scenario:** If game-over triggers at the liveness check BEFORE day N+2 is processed:

1. The liveness guard in `_handleGameOverPath` (`DegenerusGameAdvanceModule.sol:414-464`) triggers because `ts - lst > timeout`.
2. `_gameOverEntropy(ts, day=N+2, lvl, ...)` is called.
3. Inside `_gameOverEntropy`, `processCoinflipPayouts` is called with `epoch=N+2` (if `lvl != 0`) -- this DOES resolve the coinflip for day N+2.
4. After that, `handleGameOverDrain` sets `gameOver = true`. No further daily processing.

**So the question reduces to:** Can the game-over day = N+2 and `_gameOverEntropy` still fail to resolve the coinflip?

**Scenario where it fails:** If `lvl == 0` when `_gameOverEntropy` runs, `processCoinflipPayouts` is SKIPPED (`DegenerusGameAdvanceModule.sol:824: if (lvl != 0)`). However, at level 0, no player has earned sDGNRS (no game advances completed, no rewards distributed), so gambling burns are impossible. This edge case is unreachable.

**Scenario where it fails (2):** If the game-over triggers on a day AFTER N+2 (e.g., N+3 due to VRF stall), `processCoinflipPayouts` is called for day N+3, NOT for day N+2. Day N+2's coinflip remains unresolved. The player's `claimRedemption()` will revert with `FlipNotResolved()`.

**Scenario where it fails (3):** In the normal `rngGate` flow, the last call processes day M with `processCoinflipPayouts(epoch=M)`. The period is resolved with `flipDay = M+1`. If the NEXT call goes through `_handleGameOverPath`, it processes day M+1. `_gameOverEntropy` calls `processCoinflipPayouts(epoch=M+1)` -- this resolves `flipDay = M+1`. No gap.

BUT: if the period is resolved during `rngGate` day M, and then TWO days pass without `advanceGame` (VRF stall, no callers), the liveness guard triggers at day M+2. `_gameOverEntropy` processes day M+2, calling `processCoinflipPayouts(epoch=M+2)`. The coinflip for `flipDay=M+1` was already resolved by `processCoinflipPayouts(epoch=M+1)` ONLY IF day M+1 was processed. If day M+1 was never processed (skipped), then `flipDay=M+1`'s coinflip is unresolved.

**Key finding:** The gap occurs when at least one day is SKIPPED between the period resolution and game-over. This can happen when the liveness guard triggers after multi-day inactivity. In the `_gameOverEntropy` function, there is NO loop that resolves skipped days' coinflips.

**Additional concern -- ETH blocked by BURNIE dependency:** The `claimRedemption` function blocks the ENTIRE claim (both ETH and BURNIE payouts) on the coinflip resolution. ETH payout does not depend on the coinflip result (`ethPayout = (claim.ethValueOwed * roll) / 100` -- no flip dependency), yet it cannot be claimed independently because the function reverts before reaching `_payEth`.

### Root Cause

`claimRedemption` imposes a single-transaction "all or nothing" claim that requires coinflip resolution for `flipDay`. The coinflip for `flipDay` is resolved by `processCoinflipPayouts(epoch=flipDay)`, which only runs during `rngGate` or `_gameOverEntropy` for that specific day. If that day is skipped (due to VRF stall, multi-day inactivity, or game-over triggering on a different day), the coinflip is never resolved.

The design couples ETH payout (which is coinflip-independent) with BURNIE payout (which is coinflip-dependent) into a single atomic claim.

### Impact

At the game-over boundary, if one or more days are skipped between period resolution and game termination:

1. The coinflip for `flipDay` is never resolved.
2. `claimRedemption()` permanently reverts with `FlipNotResolved()`.
3. The player's ETH payout (which does not depend on the coinflip) is blocked along with the BURNIE payout.
4. ETH remains segregated in `pendingRedemptionEthValue` permanently.

This is less severe than CP-06 (which affects ALL pending claims at game-over) because it only affects claims where the period WAS resolved but the specific coinflip day was skipped. It requires a multi-day gap between the last `rngGate` call and game-over.

### Recommended Fix

Two options:

**Option A (Recommended): Split claim into ETH-only and BURNIE-optional paths**

Modify `claimRedemption` to allow ETH claiming independently of coinflip resolution:

**Before (`StakedDegenerusStonk.sol:575-613`):**
```solidity
function claimRedemption() external {
    // ... checks ...
    (uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay);
    if (rewardPercent == 0 && !flipWon) revert FlipNotResolved();
    // ... compute both payouts ...
    // ... pay both ...
}
```

**After:**
```solidity
function claimRedemption() external {
    address player = msg.sender;
    PendingRedemption storage claim = pendingRedemptions[player];
    if (claim.periodIndex == 0) revert NoClaim();

    RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex];
    if (period.roll == 0) revert NotResolved();

    uint16 roll = period.roll;

    // ETH payout: always available after period resolution (no flip dependency)
    uint256 ethPayout = (claim.ethValueOwed * roll) / 100;

    // BURNIE payout: requires coinflip resolution
    uint256 burniePayout;
    (uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay);
    bool flipResolved = (rewardPercent != 0 || flipWon);
    if (flipResolved && flipWon) {
        burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;
    }

    // Release ETH segregation
    pendingRedemptionEthValue -= ethPayout;

    // Clear claim (ETH always claimed; BURNIE forfeited if flip unresolved or lost)
    delete pendingRedemptions[player];

    // Pay ETH
    _payEth(player, ethPayout);

    // Pay BURNIE (only if flip resolved AND won)
    if (burniePayout != 0) {
        _payBurnie(player, burniePayout);
    }

    emit RedemptionClaimed(player, roll, flipWon, ethPayout, burniePayout);
}
```

**Tradeoff:** Players lose BURNIE upside if flip never resolves. ETH is always claimable. Simpler than Option B.

**Option B: Add emergency coinflip resolution at game-over**

Add a function that resolves the coinflip with a default result (e.g., `flipWon=false, rewardPercent=100`) for any day that was skipped. Callable by anyone after `gameOver()`.

**Tradeoff:** More complex. Requires new function on BurnieCoinflip with access control. But preserves the possibility of BURNIE payout.

**Recommendation:** Option A is preferred. The ETH payout is the primary value; BURNIE payout on flip loss is already zero. If the flip is unresolvable, the player's expected BURNIE value is forfeited (50% chance of loss anyway). This is a fair degradation that prevents permanent ETH lockup.

---
