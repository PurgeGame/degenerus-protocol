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
