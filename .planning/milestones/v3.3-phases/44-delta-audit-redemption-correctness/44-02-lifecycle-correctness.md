# Phase 44 Lifecycle Correctness

## Redemption Lifecycle Trace (CORR-01)

This document traces the complete gambling burn redemption lifecycle through all contracts involved:
`StakedDegenerusStonk.sol` (sDGNRS), `DegenerusStonk.sol` (DGNRS), `DegenerusGameAdvanceModule.sol`,
and `BurnieCoinflip.sol`. Every state transition and storage mutation is documented with exact line numbers.

---

### Phase 1: Submit (burn / burnWrapped)

Two entry points funnel into the same core gambling claim logic.

#### Entry Point A: `StakedDegenerusStonk.burn(uint256 amount)` (line 435)

```
burn(amount) [line 435]
  |-- game.gameOver()? [line 436]
  |     |-- YES: return _deterministicBurn(msg.sender, amount) [line 437]
  |     |-- NO: continue
  |-- game.rngLocked()? [line 439]
  |     |-- YES: revert BurnsBlockedDuringRng() [line 439]
  |     |-- NO: continue
  |-- _submitGamblingClaim(msg.sender, amount) [line 440]
  |-- return (0, 0, 0) [line 441]
```

**Guard 1 -- Deterministic vs Gambling branch (line 436):**
If `game.gameOver()` returns true, the burn follows the deterministic path (`_deterministicBurn`) which computes and pays out proportional ETH/stETH/BURNIE immediately. During active gameplay, the gambling path is taken.

**Guard 2 -- RNG lock (line 439):**
If `game.rngLocked()` is true (VRF request pending), burns revert with `BurnsBlockedDuringRng()`. This prevents front-running the RNG resolution.

**`_submitGamblingClaim(msg.sender, amount)` (line 669):**
Calls `_submitGamblingClaimFrom(player, player, amount)` (line 670), passing `msg.sender` as both `beneficiary` and `burnFrom`.

**`_submitGamblingClaimFrom(beneficiary, burnFrom, amount)` (line 675) -- Core Logic:**

Storage mutations in execution order:

1. **Balance/amount check (line 676-677):**
   `bal = balanceOf[burnFrom]`. Reverts `Insufficient()` if `amount == 0 || amount > bal`.

2. **Period initialization check (lines 680-684):**
   ```solidity
   uint48 currentPeriod = game.currentDayView();          // line 680
   if (redemptionPeriodIndex != currentPeriod) {           // line 681
       redemptionPeriodSupplySnapshot = totalSupply;       // line 682 -- WRITE #1
       redemptionPeriodIndex = currentPeriod;              // line 683 -- WRITE #2
       redemptionPeriodBurned = 0;                         // line 684 -- WRITE #3
   }
   ```
   When a new period starts (first burn of a new day), three variables reset:
   - `redemptionPeriodSupplySnapshot` captures `totalSupply` at the moment of the first burn
   - `redemptionPeriodIndex` advances to the current day index
   - `redemptionPeriodBurned` resets to 0

3. **50% supply cap check (line 686):**
   ```solidity
   if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();
   ```
   The cap check uses `>` (strictly greater than), meaning exactly 50% is allowed. The check occurs BEFORE the actual burn, using `redemptionPeriodBurned + amount` (prospective, not retroactive). Note: the plan template references `ExceedsRedemptionCap` but the actual revert is `Insufficient()`.

4. **Period burned increment (line 687):**
   ```solidity
   redemptionPeriodBurned += amount;                       // WRITE #4
   ```

5. **Supply snapshot for proportional calculation (line 689):**
   `supplyBefore = totalSupply` -- captured BEFORE the burn for ratio computation.

6. **ETH value computation (lines 692-696):**
   ```solidity
   uint256 ethBal = address(this).balance;                 // line 692
   uint256 stethBal = steth.balanceOf(address(this));      // line 693
   uint256 claimableEth = _claimableWinnings();            // line 694
   uint256 totalMoney = ethBal + stethBal + claimableEth
                        - pendingRedemptionEthValue;       // line 695 -- deducts segregated
   uint256 ethValueOwed = (totalMoney * amount) / supplyBefore; // line 696
   ```
   `totalMoney` correctly subtracts `pendingRedemptionEthValue` (ETH already reserved for prior pending claims). The player's proportional share is computed against `supplyBefore` (pre-burn supply).

7. **BURNIE value computation (lines 699-702):**
   ```solidity
   uint256 burnieBal = coin.balanceOf(address(this));      // line 699
   uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this)); // line 700
   uint256 totalBurnie = burnieBal + claimableBurnie
                         - pendingRedemptionBurnie;        // line 701 -- deducts reserved
   uint256 burnieOwed = (totalBurnie * amount) / supplyBefore; // line 702
   ```
   Same pattern: deducts already-reserved BURNIE before computing proportional share.

8. **sDGNRS burn (lines 705-709):**
   ```solidity
   unchecked {
       balanceOf[burnFrom] = bal - amount;                 // line 706 -- WRITE #5
       totalSupply -= amount;                              // line 707 -- WRITE #6
   }
   emit Transfer(burnFrom, address(0), amount);            // line 709
   ```
   Burns `amount` sDGNRS from `burnFrom` address. Supply decreases by `amount`.

9. **ETH segregation (lines 712-713):**
   ```solidity
   pendingRedemptionEthValue += ethValueOwed;              // line 712 -- WRITE #7
   pendingRedemptionEthBase += ethValueOwed;               // line 713 -- WRITE #8
   ```
   - `pendingRedemptionEthValue`: running total of ALL segregated ETH (across all periods, resolved and unresolved)
   - `pendingRedemptionEthBase`: current-period UNRESOLVED ETH base (zeroed at resolution)

10. **BURNIE reservation (lines 714-715):**
    ```solidity
    pendingRedemptionBurnie += burnieOwed;                 // line 714 -- WRITE #9
    pendingRedemptionBurnieBase += burnieOwed;             // line 715 -- WRITE #10
    ```
    Same dual-accumulator pattern for BURNIE.

11. **Per-player claim stacking (lines 718-724):**
    ```solidity
    PendingRedemption storage claim = pendingRedemptions[beneficiary]; // line 718
    if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) { // line 719
        revert UnresolvedClaim();                          // line 720
    }
    claim.ethValueOwed += ethValueOwed;                    // line 722 -- WRITE #11
    claim.burnieOwed += burnieOwed;                        // line 723 -- WRITE #12
    claim.periodIndex = currentPeriod;                     // line 724 -- WRITE #13
    ```
    **Same-period stacking:** If the player already has a pending claim in the SAME period (`claim.periodIndex == currentPeriod`), values are ADDED (stacked). This is safe because both claims will resolve with the same roll.

    **Cross-period conflict:** If the player has a pending claim from a DIFFERENT period (`claim.periodIndex != 0 && claim.periodIndex != currentPeriod`), the transaction reverts with `UnresolvedClaim()`. The player must claim their prior period's redemption first.

    **No-claim case:** If `claim.periodIndex == 0` (no existing claim), this is the first claim for this player. The `+=` on `ethValueOwed`/`burnieOwed` works correctly since the default struct values are 0.

12. **Event emission (line 726):**
    ```solidity
    emit RedemptionSubmitted(beneficiary, amount, ethValueOwed, burnieOwed, currentPeriod);
    ```

---

#### Entry Point B: `StakedDegenerusStonk.burnWrapped(uint256 amount)` (line 451)

```
burnWrapped(amount) [line 451]
  |-- dgnrsWrapper.burnForSdgnrs(msg.sender, amount)  [line 452]  -- burns DGNRS from player
  |-- game.gameOver()? [line 453]
  |     |-- YES: return _deterministicBurnFrom(msg.sender, DGNRS, amount) [line 454]
  |     |-- NO: continue
  |-- game.rngLocked()? [line 456]
  |     |-- YES: revert BurnsBlockedDuringRng() [line 456]
  |     |-- NO: continue
  |-- _submitGamblingClaimFrom(msg.sender, DGNRS, amount) [line 457]
  |-- return (0, 0, 0) [line 458]
```

**Step 1: `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` (line 452):**
Calls into `DegenerusStonk.burnForSdgnrs(player, amount)` (DegenerusStonk.sol line 233).

**Jump to `DegenerusStonk.burnForSdgnrs(address player, uint256 amount)` (line 233-241):**
```solidity
function burnForSdgnrs(address player, uint256 amount) external {
    if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized(); // line 234
    uint256 bal = balanceOf[player];                                     // line 235
    if (amount == 0 || amount > bal) revert Insufficient();              // line 236
    unchecked {
        balanceOf[player] = bal - amount;                                // line 238
        totalSupply -= amount;                                           // line 239
    }
    emit Transfer(player, address(0), amount);                           // line 241
}
```
This function:
- Only callable by sDGNRS contract (`msg.sender == SDGNRS`)
- Burns `amount` DGNRS from `player` (the original caller)
- Reduces DGNRS `totalSupply` by `amount`
- Does NOT call back into sDGNRS -- returns cleanly to `burnWrapped`

**Step 2: Back in `burnWrapped` (line 453-458):**
After DGNRS is burned, the gambling path calls:
```solidity
_submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount); // line 457
```
- `beneficiary = msg.sender` (the original player)
- `burnFrom = ContractAddresses.DGNRS` (sDGNRS is burned from DGNRS contract's balance)

This means sDGNRS tokens are burned from the DGNRS contract's balance (which holds the creator allocation of sDGNRS), but the gambling claim is recorded under the player's address. The player can later call `claimRedemption()` directly.

**msg.sender chain for burnWrapped:**
```
Player (EOA)
  |-- calls sDGNRS.burnWrapped(amount)    [msg.sender = Player]
       |-- calls DGNRS.burnForSdgnrs(Player, amount) [msg.sender = sDGNRS]
       |    Burns DGNRS from Player's balance
       |    Returns to burnWrapped
       |-- calls _submitGamblingClaimFrom(Player, DGNRS, amount)
            Burns sDGNRS from DGNRS contract's balanceOf
            Records claim under Player (beneficiary = Player)
```

Key difference from Entry Point A: In `burn()`, both `beneficiary` and `burnFrom` are `msg.sender` (the player). In `burnWrapped()`, `beneficiary` is the player but `burnFrom` is the DGNRS contract. The sDGNRS tokens come from DGNRS contract's balance (the creator allocation), and the claim is recorded under the player.

**Contrast with `DegenerusStonk.burn()` (Seam-1 issue):**
When `DegenerusStonk.burn(amount)` is called (line 164-167), it calls `stonk.burn(amount)` where `msg.sender = DGNRS contract`. Inside `sDGNRS.burn()`, the gambling path would call `_submitGamblingClaim(msg.sender, amount)` with `msg.sender = DGNRS`, recording the claim under the DGNRS contract address. The DGNRS contract has no `claimRedemption()` function, so this claim would be permanently orphaned. This is the known Seam-1 finding (CONFIRMED HIGH in Plan 01).

---

### Phase 2: Resolve (inside advanceGame, Day N+1)

Resolution occurs during `DegenerusGameAdvanceModule.rngGate()` when VRF delivers the random word for the next day.

#### Resolution Path in `rngGate()` (DegenerusGameAdvanceModule.sol, lines 739-799)

```
rngGate(ts, day, lvl, isTicketJackpotDay, bonusFlip) [line 739]
  |-- rngWordByDay[day] != 0? [line 747] -- already recorded, return cached
  |-- currentWord = rngWordCurrent [line 749]
  |-- currentWord != 0 && rngRequestTime != 0? [line 752] -- VRF word ready
  |     |-- requestDay = _simulatedDayIndexAt(rngRequestTime) [line 754]
  |     |-- requestDay < day? [line 757] -- stale from previous day
  |     |     |-- finalize lootbox only, request fresh RNG [lines 759-762]
  |     |     |-- return 1
  |     |-- _applyDailyRng(day, currentWord) [line 766]
  |     |-- coinflip.processCoinflipPayouts(bonusFlip, currentWord, day) [line 767]
  |     |-- ** REDEMPTION RESOLUTION BLOCK ** [lines 770-780]
  |     |-- _finalizeLootboxRng(currentWord) [line 782]
  |     |-- return currentWord [line 783]
  |-- ... (VRF not ready: timeout/retry logic)
```

#### Step 1: `coinflip.processCoinflipPayouts()` (line 767)

Called BEFORE redemption resolution. Resolves the daily coinflip for `day`:
- Computes `rewardPercent` from RNG (BurnieCoinflip.sol lines 787-798): 5% chance of 50%, 5% chance of 150%, 90% chance of [78,115]%
- Determines `win = (rngWord & 1) == 1` (50/50, BurnieCoinflip.sol line 808)
- Stores result in `coinflipDayResult[epoch]` (BurnieCoinflip.sol line 811-814)

#### Step 2: `sdgnrs.hasPendingRedemptions()` check (line 772)

```solidity
IStakedDegenerusStonk sdgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS); // line 771
if (sdgnrs.hasPendingRedemptions()) {                                             // line 772
```

`hasPendingRedemptions()` (StakedDegenerusStonk.sol line 536-538):
```solidity
return pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0;
```
Returns true if the current period has any unresolved base amounts. After resolution, both are set to 0, preventing re-entry.

#### Step 3: Roll computation (line 773)

```solidity
uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25); // line 773
```
- `currentWord >> 8`: shifts right 8 bits to use different entropy than the coinflip win bit (bit 0)
- `% 151`: gives range [0, 150]
- `+ 25`: gives final range **[25, 175]**
- Cast to `uint16`: safe since max value 175 fits in uint16

This means burners receive between 25% and 175% of their base ETH value.

#### Step 4: `flipDay` assignment (line 774)

```solidity
uint48 flipDay = day + 1; // line 774
```
The coinflip day for BURNIE gamble is set to `day + 1`. This creates a forward dependency: the BURNIE payout depends on the coinflip result from the NEXT day, which will be resolved during the NEXT advanceGame call.

#### Step 5: `sdgnrs.resolveRedemptionPeriod(roll, flipDay)` (line 775)

Jump into `StakedDegenerusStonk.resolveRedemptionPeriod()` (line 545-570):

Storage mutations in order:

1. **Authorization check (line 546):**
   `if (msg.sender != ContractAddresses.GAME) revert Unauthorized();`

2. **Period read and early exit (lines 548-549):**
   ```solidity
   uint48 period = redemptionPeriodIndex;                                // line 548
   if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return 0; // line 549
   ```

3. **ETH segregation adjustment (lines 552-554):**
   ```solidity
   uint256 rolledEth = (pendingRedemptionEthBase * roll) / 100;        // line 552
   pendingRedemptionEthValue = pendingRedemptionEthValue
                              - pendingRedemptionEthBase + rolledEth;   // line 553 -- WRITE #1
   pendingRedemptionEthBase = 0;                                        // line 554 -- WRITE #2
   ```
   - `rolledEth`: the rolled ETH amount (base * roll / 100)
   - `pendingRedemptionEthValue` adjustment: removes the 100% base and adds the rolled amount. If roll < 100, the segregated total decreases (ETH freed back to the pool). If roll > 100, it increases (more ETH reserved from the pool).
   - `pendingRedemptionEthBase = 0`: clears the current period's unresolved base

4. **BURNIE roll computation (line 557):**
   ```solidity
   burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100;        // line 557
   ```
   This value is returned to the caller (rngGate) for coinflip crediting.

5. **BURNIE reservation release (lines 560-561):**
   ```solidity
   pendingRedemptionBurnie -= pendingRedemptionBurnieBase;             // line 560 -- WRITE #3
   pendingRedemptionBurnieBase = 0;                                     // line 561 -- WRITE #4
   ```
   BURNIE is fully released from reservation because it transitions to the coinflip system (credited as virtual stake via `creditFlip`).

6. **Period result storage (lines 564-567):**
   ```solidity
   redemptionPeriods[period] = RedemptionPeriod({
       roll: roll,                                                       // line 565
       flipDay: flipDay                                                  // line 566
   });                                                                   // WRITE #5
   ```
   Stores the roll and flipDay for this period. `roll != 0` marks the period as resolved.

7. **Event emission (line 569):**
   ```solidity
   emit RedemptionResolved(period, roll, burnieToCredit, flipDay);
   ```

#### Step 6: Back in rngGate -- coinflip credit (lines 776-778)

```solidity
if (burnieToCredit != 0) {
    coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);         // line 777
}
```

`creditFlip` in BurnieCoinflip.sol (line 867-873):
```solidity
function creditFlip(address player, uint256 amount) external onlyFlipCreditors {
    if (player == address(0) || amount == 0) return;
    _addDailyFlip(player, amount, 0, false, false);
}
```
Credits `burnieToCredit` amount of virtual BURNIE stake to the sDGNRS address for the next day's coinflip. Note: `coin` here is the BurnieCoinflip contract (called via its `creditFlip` function on the AdvanceModule), not the BURNIE ERC20 token. The caller is the GAME contract (DegenerusGameAdvanceModule is a module of GAME), which is an authorized flip creditor.

---

### Phase 3: Claim (Day N+2+)

After the redemption period is resolved (Day N+1) and the coinflip for `flipDay` (Day N+2) is resolved, the player can claim.

#### `claimRedemption()` (StakedDegenerusStonk.sol, lines 575-613)

**CHECKS (lines 576-585):**

1. **No-claim check (line 578):**
   ```solidity
   address player = msg.sender;                                          // line 576
   PendingRedemption storage claim = pendingRedemptions[player];         // line 577
   if (claim.periodIndex == 0) revert NoClaim();                        // line 578
   ```
   If `claim.periodIndex == 0`, the player has no pending claim. This is the zero sentinel -- safe because `currentDayView()` is 1-indexed (GameTimeLib.sol line 33: `+ 1`).

2. **Not-resolved check (line 581):**
   ```solidity
   RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex]; // line 580
   if (period.roll == 0) revert NotResolved();                            // line 581
   ```
   If the period's roll is still 0, `resolveRedemptionPeriod` has not been called for this period yet.

3. **Coinflip not resolved check (lines 584-585):**
   ```solidity
   (uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay); // line 584
   if (rewardPercent == 0 && !flipWon) revert FlipNotResolved();         // line 585
   ```
   Queries the coinflip result for `period.flipDay`. If both `rewardPercent == 0` and `flipWon == false`, the coinflip for that day hasn't been resolved yet. Note: a resolved losing flip has `rewardPercent != 0` (e.g., 50, 78-150) and `flipWon == false`, so it passes this check. The only state where both are zero is an unresolved day (default struct values).

**PAYOUT COMPUTATION (lines 587-596):**

4. **ETH payout (line 590):**
   ```solidity
   uint16 roll = period.roll;                                            // line 587
   uint256 ethPayout = (claim.ethValueOwed * roll) / 100;               // line 590
   ```
   ETH payout depends on the roll only (no coinflip multiplier). Range: 25-175% of `ethValueOwed`.

5. **BURNIE payout (lines 593-596):**
   ```solidity
   uint256 burniePayout;                                                 // line 593
   if (flipWon) {                                                        // line 594
       burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000; // line 595
   }
   ```
   - If flip LOST: `burniePayout = 0` (player gets no BURNIE)
   - If flip WON: `burniePayout = burnieOwed * roll * (100 + rewardPercent) / 10000`
     - Example: burnieOwed=1000, roll=100, rewardPercent=100 --> `1000 * 100 * 200 / 10000 = 2000` BURNIE
     - The formula combines the redemption roll (25-175%) with the coinflip bonus (100+rewardPercent where rewardPercent is 50-150%)

**EFFECTS -- State changes (lines 598-602):**

6. **ETH segregation release (line 599):**
   ```solidity
   pendingRedemptionEthValue -= ethPayout;                               // line 599 -- WRITE #1
   ```
   Decrements the global ETH segregation tracker by the player's payout amount.

7. **Claim deletion (line 602):**
   ```solidity
   delete pendingRedemptions[player];                                    // line 602 -- WRITE #2
   ```
   Deletes the entire claim struct. This prevents reentrancy -- any reentrant call to `claimRedemption` would hit `NoClaim` at line 578.

**INTERACTIONS -- External calls (lines 604-612):**

8. **ETH payment (line 605):**
   ```solidity
   _payEth(player, ethPayout);                                           // line 605
   ```
   `_payEth` (lines 730-751):
   - Checks `address(this).balance` against `amount`
   - If insufficient, calls `game.claimWinnings(address(0))` to pull pending ETH from the game contract (line 736)
   - If ETH covers payout: sends via `player.call{value: amount}("")` (line 741)
   - If ETH insufficient even after claiming: sends available ETH via call, then sends remainder as stETH via `steth.transfer(player, stethOut)` (lines 744-751)
   - Reverts with `TransferFailed()` if any transfer fails

9. **BURNIE payment (lines 608-609):**
   ```solidity
   if (burniePayout != 0) {
       _payBurnie(player, burniePayout);                                 // line 609
   }
   ```
   `_payBurnie` (lines 755-765):
   - Reads `burnieBal = coin.balanceOf(address(this))` (line 756)
   - Sends `min(amount, burnieBal)` from existing BURNIE balance via `coin.transfer(player, payBal)` (line 760)
   - If `remaining != 0`: calls `coinflip.claimCoinflipsForRedemption(address(this), remaining)` to mint BURNIE from coinflip winnings (line 763), then transfers the minted amount to player (line 764)
   - `claimCoinflipsForRedemption` (BurnieCoinflip.sol line 344-349): restricted to sDGNRS caller, processes pending claim days, and mints up to `amount` BURNIE tokens

10. **Event emission (line 612):**
    ```solidity
    emit RedemptionClaimed(player, roll, flipWon, ethPayout, burniePayout);
    ```

**CEI Compliance:** The function follows Checks-Effects-Interactions ordering:
- **Checks:** Lines 578, 581, 585 (all reverts)
- **Effects:** Lines 599, 602 (state mutations -- segregation decrement and claim deletion)
- **Interactions:** Lines 605, 609 (external calls to _payEth and _payBurnie)

The claim is deleted at line 602 BEFORE any external call. A reentrant call to `claimRedemption()` would revert at line 578 (`NoClaim`) because `pendingRedemptions[player]` was deleted.

---

### State Transition Diagram

```
                        burn() / burnWrapped()
                        during active game
                              |
                              v
    +----------+     _submitGamblingClaimFrom()     +----------+
    |          |  --------------------------------> |          |
    | NO_CLAIM |     lines 675-727                  | PENDING  |
    |          |     periodIndex = currentDay        | (Day N)  |
    +----------+     claim.ethValueOwed > 0          +----------+
         ^                                                |
         |                                                |
    claimRedemption()                               rngGate() on Day N+1
    lines 575-613                                   resolveRedemptionPeriod()
    delete claim                                    lines 545-570
    pay ETH + BURNIE                                period.roll = [25,175]
         |                                          period.flipDay = N+2
         |                                                |
         |                                                v
    +----------+     coinflip Day N+2             +----------+
    |          | <--  resolves via                 |          |
    | CLAIMED  |      processCoinflipPayouts()    | RESOLVED |
    | (done)   |                                  | (Day N+1)|
    +----------+                                  +----------+
         ^                                                |
         |                                                |
         |                                                v
         |                                        +----------+
         +--------------------------------------- |          |
              claimRedemption()                   | CLAIMABLE|
              lines 575-613                       | (Day N+2)|
              roll != 0 AND flip resolved          +----------+
```

**State definitions:**
- **NO_CLAIM:** `pendingRedemptions[player].periodIndex == 0`. Default state.
- **PENDING:** `claim.periodIndex != 0` AND `redemptionPeriods[claim.periodIndex].roll == 0`. Waiting for period resolution.
- **RESOLVED:** `period.roll != 0` AND coinflip not yet resolved (`rewardPercent == 0 && !flipWon`). Period resolved but coinflip dependency pending.
- **CLAIMABLE:** `period.roll != 0` AND coinflip resolved (`rewardPercent != 0 || flipWon`). Player can claim.
- **CLAIMED:** After `delete pendingRedemptions[player]`. Returns to NO_CLAIM.

**Invalid transitions (reverts):**
- NO_CLAIM --> claimRedemption() --> reverts `NoClaim()` (line 578)
- PENDING --> claimRedemption() --> reverts `NotResolved()` (line 581)
- RESOLVED --> claimRedemption() --> reverts `FlipNotResolved()` (line 585)
- PENDING (period X) --> burn() in period Y (Y != X) --> reverts `UnresolvedClaim()` (line 720)

**Valid within-state transitions:**
- PENDING (period X) --> burn() in period X --> stacks claim (lines 722-724). Same period, values added.

---

## Period State Machine Proof (CORR-04)

### Monotonicity Proof

**Claim:** `redemptionPeriodIndex` only advances forward (monotonically non-decreasing). It never revisits a previous period value.

**Proof:**

1. **Single write site:** `redemptionPeriodIndex` is written at exactly one location in the entire codebase:
   `StakedDegenerusStonk._submitGamblingClaimFrom()` line 683:
   ```solidity
   redemptionPeriodIndex = currentPeriod;
   ```
   This write is guarded by line 681: `if (redemptionPeriodIndex != currentPeriod)`.

2. **`currentPeriod` derivation:** `currentPeriod = game.currentDayView()` (line 680). The game contract's `currentDayView()` delegates to `GameTimeLib.currentDayIndex()`:
   ```solidity
   function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
       uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
       return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
   }
   ```
   (GameTimeLib.sol lines 31-33)

3. **Monotonicity of `currentDayIndexAt`:** The formula is:
   ```
   dayIndex = floor((ts - 82620) / 86400) - DEPLOY_DAY_BOUNDARY + 1
   ```
   Since `ts = block.timestamp` and `block.timestamp` is monotonically non-decreasing (EVM guarantee), `floor((ts - 82620) / 86400)` is monotonically non-decreasing. Therefore `dayIndex` is monotonically non-decreasing.

4. **Guard prevents same-value writes:** The `if (redemptionPeriodIndex != currentPeriod)` guard ensures the write only occurs when advancing to a new period. When `currentPeriod == redemptionPeriodIndex` (same day, multiple burns), no write occurs.

5. **Conclusion:** `redemptionPeriodIndex` can only take on values from the sequence of day indices returned by `currentDayView()`, which is monotonically non-decreasing. Combined with the `!=` guard, `redemptionPeriodIndex` strictly advances or remains unchanged. **MONOTONICITY HOLDS.**

**Edge case: Multiple burns in the same period** do NOT update `redemptionPeriodIndex` (line 681 guard fails, so the body at lines 682-684 is skipped). The existing `redemptionPeriodSupplySnapshot` and `redemptionPeriodBurned` carry forward within the same period.

### Resolution Ordering Proof

**Claim:** `resolveRedemptionPeriod()` is called at most once per period.

**Proof:**

1. **Single call site:** `resolveRedemptionPeriod()` is called from exactly one location:
   `DegenerusGameAdvanceModule.rngGate()` line 775:
   ```solidity
   uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
   ```

2. **Guard before call (line 772):**
   ```solidity
   if (sdgnrs.hasPendingRedemptions()) {
   ```
   `hasPendingRedemptions()` returns `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0` (line 537).

3. **Resolution zeros the bases:** Inside `resolveRedemptionPeriod()`:
   - `pendingRedemptionEthBase = 0` (line 554)
   - `pendingRedemptionBurnieBase = 0` (line 561)

4. **After resolution:** `hasPendingRedemptions()` returns `false` (both bases are 0). The guard at line 772 prevents any subsequent call to `resolveRedemptionPeriod()` until new burns add to the bases.

5. **New burns create a new period:** Since `currentDayView()` has advanced by the time `rngGate()` runs (it runs on Day N+1, burns were on Day N), any new burns would be in a different period. The `redemptionPeriods[period]` mapping uses the period index as key, so each period's result (`roll`, `flipDay`) is stored independently.

6. **Confirm no overwrite:** `redemptionPeriods[period]` is written at exactly one location (line 564-567). Since the same period cannot have `hasPendingRedemptions() == true` twice (bases are zeroed after resolution), the `roll` value for a given period index is set exactly once. **RESOLUTION ORDERING HOLDS.**

**Note on `_gameOverEntropy`:** This function (lines 813-862) does NOT call `resolveRedemptionPeriod()`. This is the CP-06 finding (CONFIRMED HIGH in Plan 01) -- pending redemptions at game-over are never resolved. This proof covers only the normal gameplay path.

### 50% Supply Cap Enforcement

**Claim:** At most 50% of the sDGNRS total supply (at the start of each period) can be burned through the gambling path within a single period.

**Proof:**

1. **Snapshot capture (line 682):**
   ```solidity
   if (redemptionPeriodIndex != currentPeriod) {
       redemptionPeriodSupplySnapshot = totalSupply;  // line 682
       ...
       redemptionPeriodBurned = 0;                    // line 684
   }
   ```
   On the first burn of a new period, `redemptionPeriodSupplySnapshot` captures `totalSupply` at that exact moment. `redemptionPeriodBurned` resets to 0.

2. **Cap check (line 686):**
   ```solidity
   if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();
   ```
   The check is PROSPECTIVE: `redemptionPeriodBurned + amount` (including the current burn). Uses `>` (strictly greater than), so exactly `snapshot / 2` is the maximum (with integer division truncation on odd snapshots).

3. **Increment (line 687):**
   ```solidity
   redemptionPeriodBurned += amount;
   ```
   Tracks cumulative burns within the period. This increment happens AFTER the cap check passes, so `redemptionPeriodBurned` never exceeds `redemptionPeriodSupplySnapshot / 2`.

4. **Per-period isolation:** When a new period starts (line 681 guard triggers), `redemptionPeriodBurned` resets to 0 and `redemptionPeriodSupplySnapshot` takes a fresh snapshot. Previous period's burned amount does not carry over.

5. **Snapshot manipulation analysis:**
   - Can an attacker manipulate `totalSupply` between the snapshot and subsequent burns?
   - sDGNRS has no public `mint` function. Supply can only DECREASE via burns (gambling burn at line 707, deterministic burn at line 487, `burnRemainingPools` at line 418).
   - Therefore, `totalSupply` at any point within the period is <= `redemptionPeriodSupplySnapshot`.
   - The cap allows burning up to 50% of the supply AT PERIOD START, not 50% of CURRENT supply. Since supply can only decrease, the effective cap is conservative: it may allow slightly more than 50% of the current supply, but never more than 50% of the snapshot.

6. **Ordering of burn vs cap check:**
   - Line 686: cap check uses `redemptionPeriodBurned + amount` (prospective)
   - Line 687: `redemptionPeriodBurned += amount`
   - Lines 705-708: actual `totalSupply -= amount` burn
   - The sDGNRS burn happens AFTER the cap check and increment. The `supplyBefore = totalSupply` (line 689) used for proportional computation is captured before the burn, which is correct.

**Conclusion: 50% CAP CORRECTLY ENFORCED per period.**

---

## Supply Invariant Proof (CORR-05)

### burnWrapped() Dual Burn Trace

**Claim:** After `burnWrapped(amount)` completes, both `DGNRS.totalSupply` and `sDGNRS.totalSupply` have decreased by exactly `amount`.

**Trace:**

#### Step 1: `burnWrapped(uint256 amount)` in StakedDegenerusStonk.sol (line 451)

```solidity
function burnWrapped(uint256 amount) external returns (...) {
    dgnrsWrapper.burnForSdgnrs(msg.sender, amount);  // line 452 -- burns DGNRS
    ...
    _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount); // line 457 -- burns sDGNRS
}
```

#### Step 2: `DegenerusStonk.burnForSdgnrs(player, amount)` (DegenerusStonk.sol lines 233-241)

```solidity
function burnForSdgnrs(address player, uint256 amount) external {
    if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();
    uint256 bal = balanceOf[player];
    if (amount == 0 || amount > bal) revert Insufficient();
    unchecked {
        balanceOf[player] = bal - amount;    // DGNRS balance: player -= amount
        totalSupply -= amount;                // DGNRS totalSupply -= amount    <-- DGNRS BURN
    }
    emit Transfer(player, address(0), amount);
}
```

**Effect on DGNRS:** `DGNRS.totalSupply -= amount`, `DGNRS.balanceOf[player] -= amount`.

#### Step 3: Back in `burnWrapped`, the gambling path (line 457)

```solidity
_submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
```
- `beneficiary = msg.sender` (the player)
- `burnFrom = ContractAddresses.DGNRS` (the DGNRS contract address)

#### Step 4: Inside `_submitGamblingClaimFrom` (lines 675-727)

The sDGNRS burn occurs at lines 705-708:
```solidity
unchecked {
    balanceOf[burnFrom] = bal - amount;   // sDGNRS balance: DGNRS -= amount
    totalSupply -= amount;                 // sDGNRS totalSupply -= amount   <-- sDGNRS BURN
}
```

**Token flow for sDGNRS in the wrapped path:**
- The DGNRS contract holds sDGNRS tokens (the creator allocation, minted in the sDGNRS constructor at line 273: `_mint(ContractAddresses.DGNRS, creatorAmount)`)
- `burnWrapped` burns sDGNRS from the DGNRS contract's balance (`burnFrom = ContractAddresses.DGNRS`)
- The DGNRS contract does NOT need to receive sDGNRS tokens from the player -- it already holds them as the creator allocation
- The player's DGNRS tokens are a 1:1 claim on the DGNRS contract's sDGNRS balance

**Balance check:** `balanceOf[ContractAddresses.DGNRS]` must be >= `amount`. Since the player holds DGNRS tokens that were minted 1:1 against the DGNRS contract's sDGNRS balance, and the player cannot burn more DGNRS than they hold (checked in `burnForSdgnrs`), the DGNRS contract's sDGNRS balance should always cover the burn amount. However, if other operations reduce the DGNRS contract's sDGNRS balance (e.g., `unwrapTo` which calls `wrapperTransferTo` to move sDGNRS out of DGNRS's balance), the DGNRS contract's sDGNRS balance could be less than the total DGNRS supply. In that case, `_submitGamblingClaimFrom` would revert at line 677 (`amount > bal`).

#### Invariant Verification

After `burnWrapped(amount)` completes (gambling path):

| Token | Change | Location |
|-------|--------|----------|
| DGNRS.totalSupply | -= amount | DegenerusStonk.sol line 239 |
| DGNRS.balanceOf[player] | -= amount | DegenerusStonk.sol line 238 |
| sDGNRS.totalSupply | -= amount | StakedDegenerusStonk.sol line 707 |
| sDGNRS.balanceOf[DGNRS] | -= amount | StakedDegenerusStonk.sol line 706 |

Both supplies decrease by exactly `amount`. **INVARIANT HOLDS.**

### Deterministic (gameOver) Path Verification

When `game.gameOver() == true`, `burnWrapped` takes the deterministic path:

```solidity
dgnrsWrapper.burnForSdgnrs(msg.sender, amount);                      // line 452 -- DGNRS burned
return _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount); // line 454 -- sDGNRS burned
```

Inside `_deterministicBurnFrom` (lines 469-528):
```solidity
uint256 bal = balanceOf[burnFrom];          // burnFrom = DGNRS contract
if (amount == 0 || amount > bal) revert Insufficient();
uint256 supplyBefore = totalSupply;
...
unchecked {
    balanceOf[burnFrom] = bal - amount;     // line 486: sDGNRS balance: DGNRS -= amount
    totalSupply -= amount;                   // line 487: sDGNRS totalSupply -= amount
}
```

Same result:
- DGNRS.totalSupply -= amount (from `burnForSdgnrs` at line 239)
- sDGNRS.totalSupply -= amount (from `_deterministicBurnFrom` at line 487)

**INVARIANT HOLDS for both gambling and deterministic paths.**

### Note on `_deterministicBurnFrom` CP-08 Issue

The deterministic path (`_deterministicBurnFrom`, line 469) has a known issue (CP-08, CONFIRMED HIGH in Plan 01): it computes `totalMoney = ethBal + stethBal + claimableEth` at line 477 WITHOUT subtracting `pendingRedemptionEthValue`. This means it includes ETH reserved for pending gambling claims in the proportional share calculation, creating a potential double-spend. This issue affects the PAYOUT COMPUTATION but NOT the supply invariant -- both DGNRS and sDGNRS supplies still decrease by the correct `amount`.

---

*Document generated for Phase 44 Plan 02 -- CORR-01, CORR-04, CORR-05 requirements.*
*Line numbers reference contracts as of 2026-03-21.*
