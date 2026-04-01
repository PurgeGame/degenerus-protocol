# Phase 113: sDGNRS + DGNRS - Research Notes

**Completed:** 2026-03-25
**Method:** Line-by-line read of both contracts

## Contract Summary

### StakedDegenerusStonk.sol (sDGNRS) -- 839 lines

**Purpose:** Soulbound token backed by ETH, stETH, and BURNIE reserves. The core value token of the protocol -- players cannot transfer sDGNRS, they can only burn it to claim proportional backing assets. During active game, burns go through a gambling redemption pipeline (submit/resolve/claim) with RNG roll modifying the payout (25%-175%). Post-gameOver, burns are deterministic pro-rata payouts.

**Supply Distribution (constructor, L262-296):**
- INITIAL_SUPPLY = 1 trillion tokens (1e30 wei)
- CREATOR_BPS = 2000 (20%) -> minted to DGNRS wrapper address
- WHALE_POOL_BPS = 1000 (10%)
- AFFILIATE_POOL_BPS = 3500 (35%)
- LOOTBOX_POOL_BPS = 2000 (20%) + dust
- REWARD_POOL_BPS = 500 (5%)
- EARLYBIRD_POOL_BPS = 1000 (10%)
- Total = 100% (dust added to lootbox pool)
- Pools held in `balanceOf[address(this)]` with separate `poolBalances[5]` tracking
- Constructor also claims whale pass and sets afKingMode for sDGNRS address

**Key State Variables:**
- `totalSupply` -- decreases on burn
- `balanceOf[addr]` -- per-address balance (soulbound)
- `poolBalances[5]` -- per-pool allocation tracking
- `pendingRedemptions[addr]` -- PendingRedemption struct (ethValueOwed:uint96, burnieOwed:uint96, periodIndex:uint48, activityScore:uint16) -- 1 slot
- `redemptionPeriods[uint48]` -- RedemptionPeriod struct (roll:uint16, flipDay:uint48)
- `pendingRedemptionEthValue` -- total segregated ETH across all periods
- `pendingRedemptionBurnie` -- total reserved BURNIE
- `pendingRedemptionEthBase` -- current unresolved period ETH base
- `pendingRedemptionBurnieBase` -- current unresolved period BURNIE base
- `redemptionPeriodSupplySnapshot` -- snapshot of totalSupply for 50% cap
- `redemptionPeriodIndex` -- current period index
- `redemptionPeriodBurned` -- tokens burned in current period

**Critical Constants:**
- `MAX_DAILY_REDEMPTION_EV = 160 ether` -- per-wallet daily cap on ethValueOwed
- `BPS_DENOM = 10_000`

### DegenerusStonk.sol (DGNRS) -- 251 lines

**Purpose:** Transferable ERC20 wrapper around sDGNRS. The creator receives 20% of sDGNRS supply as DGNRS, which can be traded on DEXes. DGNRS holders can burn back to claim sDGNRS backing. This is the liquid face of the protocol's value token.

**Key State Variables:**
- Standard ERC20: `totalSupply`, `balanceOf[addr]`, `allowance[from][spender]`
- No special state beyond ERC20

**Key Behaviors:**
- Constructor (L87-93): reads sDGNRS.balanceOf(DGNRS) and mints that to CREATOR
- receive() (L97-99): only accepts ETH from sDGNRS
- transfer/transferFrom: blocks transfer to address(0) and address(this)
- approve: standard, no frontrun protection (noted but not a finding per scope)
- unwrapTo (L152-161): creator-only, burns DGNRS, calls sDGNRS.wrapperTransferTo() to move sDGNRS to recipient. VRF stall guard: reverts if >5h since lastVrfProcessed.
- burn (L171-189): post-gameOver only, burns DGNRS then calls sDGNRS.burn(amount) which returns backing assets (ETH, stETH, BURNIE). Transfers assets to caller. ETH last.
- burnForSdgnrs (L241-250): callable only by sDGNRS, burns DGNRS from player. Used in wrapped gambling burn path.
- previewBurn (L201-203): delegates to sDGNRS.previewBurn()

## Function Inventory

### StakedDegenerusStonk -- 20 functions total

| # | Function | Visibility | Mutability | Lines | Category |
|---|----------|-----------|-----------|-------|----------|
| 1 | constructor | - | - | L262-296 | Setup |
| 2 | receive() | external | payable | L343-345 | B |
| 3 | wrapperTransferTo | external | - | L310-320 | B |
| 4 | gameAdvance | external | - | L327-329 | B |
| 5 | gameClaimWhalePass | external | - | L332-334 | B |
| 6 | depositSteth | external | - | L352-355 | B |
| 7 | poolBalance | external | view | L364-366 | D |
| 8 | transferFromPool | external | - | L376-393 | B |
| 9 | transferBetweenPools | external | - | L401-416 | B |
| 10 | burnRemainingPools | external | - | L420-429 | B |
| 11 | burn | external | - | L443-451 | B |
| 12 | burnWrapped | external | - | L461-470 | B |
| 13 | claimRedemption | external | - | L573-639 | B |
| 14 | resolveRedemptionPeriod | external | - | L540-565 | B |
| 15 | hasPendingRedemptions | external | view | L531-533 | D |
| 16 | previewBurn | external | view | L653-683 | D |
| 17 | burnieReserve | external | view | L688-692 | D |
| 18 | _deterministicBurnFrom | private | - | L481-523 | C |
| 19 | _submitGamblingClaimFrom | private | - | L707-769 | C |
| 20 | _payEth | private | - | L772-794 | C |
| 21 | _payBurnie | private | - | L797-808 | C |
| 22 | _claimableWinnings | private | view | L812-816 | D |
| 23 | _poolIndex | private | pure | L821-823 | D |
| 24 | _mint | private | - | L829-836 | C |
| 25 | _deterministicBurn | private | - | L473-475 | C (trivial wrapper) |
| 26 | _submitGamblingClaim | private | - | L699-701 | C (trivial wrapper) |

### DegenerusStonk -- 10 functions total

| # | Function | Visibility | Mutability | Lines | Category |
|---|----------|-----------|-----------|-------|----------|
| 1 | constructor | - | - | L87-93 | Setup |
| 2 | receive() | external | payable | L97-99 | B |
| 3 | transfer | external | - | L112-114 | B |
| 4 | transferFrom | external | - | L125-134 | B |
| 5 | approve | external | - | L140-144 | B |
| 6 | unwrapTo | external | - | L152-161 | B |
| 7 | burn | external | - | L171-189 | B |
| 8 | burnForSdgnrs | external | - | L241-250 | B |
| 9 | previewBurn | external | view | L201-203 | D |
| 10 | _transfer | private | - | L209-220 | C |
| 11 | _burn | private | - | L222-230 | C |

**Total: 37 functions (26 sDGNRS + 11 DGNRS)**

## Observations Worth Investigating

### O-1: uint96 truncation in PendingRedemption
- `ethValueOwed` and `burnieOwed` are `uint96` (max ~79.2B ETH-equiv)
- Line L758: `claim.ethValueOwed += uint96(ethValueOwed)`
- Line L760: `claim.burnieOwed += uint96(burnieOwed)`
- The 160 ETH daily cap (L756) prevents ethValueOwed from exceeding uint96, but the cast is unchecked
- BURNIE: comment says "max realistic BURNIE is ~2e24, well below uint96.max (~7.9e28)" -- verify this holds

### O-2: Period transition timing
- `_submitGamblingClaimFrom` (L712-717): if `redemptionPeriodIndex != currentPeriod`, resets snapshot/burned
- But existing claims from the old period must be resolved before a player can submit for the new period (L751-753)
- Question: What if the period advances but resolveRedemptionPeriod hasn't been called yet? Player has an unresolved claim. New period starts. Player cannot submit new claim. But can they claim the unresolved one? No -- roll is still 0. They're stuck until game resolves the old period.

### O-3: Partial claim state (claimRedemption L614-620)
- If coinflip is unresolved: ETH is paid, claim.ethValueOwed = 0, but BURNIE portion kept
- Player calls claimRedemption again after coinflip resolves
- Second call: ethValueOwed is 0, so totalRolledEth = 0, ethDirect = 0, lootboxEth = 0
- But roll is still the same, so burniePayout is computed from burnieOwed * roll
- The BURNIE payout is correct on second claim
- pendingRedemptionEthValue was already decremented on first claim (L612) -- second claim decrements 0
- Looks correct but needs careful trace

### O-4: claimRedemption re-reads period.roll twice
- L579: checks `period.roll == 0` -> reverts
- L581: reads `roll = period.roll`
- No issue -- read from storage, consistent within transaction

### O-5: Lootbox ETH accounting in claimRedemption
- L623-628: when lootboxEth != 0, calls game.resolveRedemptionLootbox()
- This does NOT transfer ETH from sDGNRS to game. Comment says "Game debits from sDGNRS's claimable internally"
- Meaning: the lootboxEth stays in sDGNRS's claimable winnings, and game internally records lootbox rewards
- Need to verify this doesn't create ETH accounting mismatch

### O-6: _deterministicBurnFrom balance check (L489)
- `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`
- If pendingRedemptionEthValue > ethBal + stethBal + claimableEth, this underflows and reverts (Solidity 0.8)
- This should only happen if more was segregated than exists -- which would be a bug elsewhere

### O-7: DGNRS.burn() order of operations
- L172: `_burn(msg.sender, amount)` -- burns DGNRS first
- L173: checks `gameOver()` -- reverts if not game over
- This means DGNRS is burned BEFORE the gameOver check. But the revert unwinds the burn.
- Interesting pattern: effects before checks, but safe because revert is atomic.

### O-8: balanceOf[to] overflow in unchecked blocks
- sDGNRS L317: `balanceOf[to] += amount` in unchecked block (wrapperTransferTo)
- sDGNRS L388: `balanceOf[to] += amount` in unchecked block (transferFromPool)
- DGNRS L216: `balanceOf[to] += amount` in unchecked block (_transfer)
- With 1T total supply (1e30 wei), uint256 overflow is impossible (max ~1.15e77)

### O-9: stETH 1-2 wei rebasing issue
- stETH transfers can have 1-2 wei rounding. sDGNRS doesn't account for this.
- In _deterministicBurnFrom (L509): `if (stethOut > stethBal) revert Insufficient()`
- The stethBal is read before the stETH transfer. If stETH rebases between the read and transfer, there could be a 1-wei discrepancy. However, this would only cause a revert (safe direction) or underpay by 1 wei.

### O-10: receive() access control asymmetry
- sDGNRS.receive() (L343): onlyGame modifier -- only game can deposit ETH
- DGNRS.receive() (L97-99): only sDGNRS can send ETH
- During DGNRS.burn(): sDGNRS.burn() sends ETH to DGNRS, then DGNRS forwards to msg.sender
- The DGNRS receive() correctly restricts to sDGNRS sender

## Architecture Diagrams

### Gambling Burn Flow
```
Player calls sDGNRS.burn(amount) during active game
  -> game.rngLocked() check (must be false)
  -> _submitGamblingClaim(player, amount)
    -> _submitGamblingClaimFrom(player, player, amount)
      -> Period check + 50% cap + 160 ETH cap
      -> Burns sDGNRS
      -> Segregates ETH value + BURNIE value
      -> Records PendingRedemption

[Time passes, day advances, VRF fulfills]

Game calls sDGNRS.resolveRedemptionPeriod(roll, flipDay)
  -> Adjusts pendingRedemptionEthValue by roll
  -> Returns burnieToCredit for coinflip

Player calls sDGNRS.claimRedemption()
  -> Reads resolved roll
  -> ETH: 50/50 split (direct + lootbox) or 100% if gameOver
  -> BURNIE: depends on coinflip win/loss
  -> Releases ETH segregation
  -> Pays BURNIE then ETH
```

### Wrapped Burn Flow
```
Player calls sDGNRS.burnWrapped(amount)
  -> dgnrsWrapper.burnForSdgnrs(player, amount) -- burns DGNRS from player
  -> Same deterministic/gambling paths as burn(), but burning from DGNRS balance
```

### DGNRS Post-GameOver Burn Flow
```
Player calls DGNRS.burn(amount)
  -> _burn(msg.sender, amount) -- burns DGNRS
  -> gameOver() check
  -> stonk.burn(amount) -- sDGNRS burns from DGNRS balance
    -> _deterministicBurnFrom(DGNRS, DGNRS, amount)
      -> ETH+stETH sent to DGNRS contract
  -> DGNRS forwards BURNIE, stETH, ETH to player
```
