# Event Correctness Audit -- Non-Game Contracts (Partial)

**Phase:** 132 (Event Correctness)
**Plan:** 02 (Non-Game Contracts)
**Date:** 2026-03-27
**Methodology:** Three verification passes per external/public state-changing function:
1. Event exists for the state change
2. Emitted parameter values match actual post-state
3. Indexer-critical transitions emit sufficient data

**Disposition policy:** DOCUMENT per D-03 (no code changes). Indexed field evaluation per D-04 (indexer-critical events only).

---

## BurnieCoin (BurnieCoin.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |
| DecimatorBurn | player, amountBurned, bucket | player | Custom |
| TerminalDecimatorBurn | player, amountBurned | player | Custom |
| DailyQuestRolled | day, questType, highDifficulty | day | Custom |
| QuestCompleted | player, questType, streak, reward | player | Custom |
| LinkCreditRecorded | player, amount | player | Custom |
| VaultEscrowRecorded | sender, amount | sender | Custom |
| VaultAllowanceSpent | spender, amount | spender | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES -- emits requested amount | NO | OK |
| transfer(to, amount) | external | balance update, possible coinflip claim | Transfer(from, to, amount) via _transfer | YES -- amount matches transfer | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) + Approval on allowance decrement | YES | YES | OK |
| burnForCoinflip(from, amount) | external | balance + supply decrease | Transfer(from, 0, amount) via _burn | YES | YES | OK |
| mintForCoinflip(to, amount) | external | balance + supply increase | Transfer(0, to, amount) via _mint | YES | YES | OK |
| mintForGame(to, amount) | external | balance + supply increase | Transfer(0, to, amount) via _mint | YES | YES | OK |
| creditCoin(player, amount) | external | balance + supply increase | Transfer(0, player, amount) via _mint | YES | NO | OK |
| creditFlip(player, amount) | external | forwards to coinflip | No direct event (coinflip emits) | N/A | NO | OK |
| creditFlipBatch(players, amounts) | external | forwards to coinflip | No direct event (coinflip emits) | N/A | NO | OK |
| creditLinkReward(player, amount) | external | forwards to coinflip | LinkCreditRecorded(player, amount) | YES | NO | OK |
| vaultEscrow(amount) | external | vaultAllowance increase | VaultEscrowRecorded(sender, amount) | YES | NO | OK |
| vaultMintTo(to, amount) | external | supply + balance increase, allowance decrease | VaultAllowanceSpent(address(this), amount) + Transfer(0, to, amount) | YES | YES | OK |
| rollDailyQuest(day, entropy) | external | quest state update | DailyQuestRolled(day, questType, highDifficulty) x2 | YES | NO | OK |
| notifyQuestMint(player, quantity, paidWithEth) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| notifyQuestLootBox(player, amountWei) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| notifyQuestDegenerette(player, amount, paidWithEth) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| affiliateQuestReward(player, amount) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| burnCoin(target, amount) | external | balance + supply decrease | Transfer(target, 0, amount-consumed) via _burn | YES | YES | OK |
| decimatorBurn(player, amount) | external | balance + supply decrease, game state | DecimatorBurn(caller, amount, bucketUsed) | YES -- emits raw input amount + actual bucket used | NO | OK |
| terminalDecimatorBurn(player, amount) | external | balance + supply decrease, game state | TerminalDecimatorBurn(caller, amount) | YES | NO | OK |

**Special attention: _transfer to VAULT**
When `to == ContractAddresses.VAULT`, `_transfer` emits `Transfer(from, address(0), amount)` + `VaultEscrowRecorded(from, amount)`. This is correct: sending BURNIE to the vault effectively burns it (converts to mint allowance). The Transfer event shows `to=address(0)` which accurately represents the burn, not a misleading transfer to VAULT address. Indexers tracking total supply will see the burn correctly.

**Special attention: _mint to VAULT**
When minting to VAULT, `_mint` emits only `VaultEscrowRecorded(address(0), amount)` with NO Transfer event. This is intentional -- no tokens enter circulation, only virtual allowance increases. However, an indexer tracking total supply via Transfer events would miss this. Since vault allowance is tracked separately via `supplyIncUncirculated()`, this is a design choice.

**Special attention: _burn from VAULT**
When burning from VAULT, `_burn` emits only `VaultAllowanceSpent(from, amount)` with NO Transfer event. Same reasoning as mint-to-vault above.

### Findings

- **EVT-BC-01 (INFO):** `_mint` to VAULT emits no Transfer event -- intentional design (virtual allowance, no circulating tokens created). Indexers relying solely on Transfer events will undercount total-plus-uncirculated supply. -- Disposition: DOCUMENT
- **EVT-BC-02 (INFO):** `_burn` from VAULT emits no Transfer event -- same design pattern as EVT-BC-01. -- Disposition: DOCUMENT

---

## BurnieCoinflip (BurnieCoinflip.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| CoinflipDeposit | player, creditedFlip | player | Custom |
| CoinflipAutoRebuyToggled | player, enabled | player | Custom |
| CoinflipAutoRebuyStopSet | player, stopAmount | player | Custom |
| QuestCompleted | player, questType, streak, reward | player | Custom |
| CoinflipStakeUpdated | player, day, amount, newTotal | player, day | Custom |
| CoinflipDayResolved | day, win, rewardPercent, bountyAfter, bountyPaid, bountyRecipient | day | Custom |
| CoinflipTopUpdated | day, player, score | day, player | Custom |
| BiggestFlipUpdated | player, recordAmount | player | Custom |
| BountyOwed | player, bounty, recordFlip | player | Custom |
| BountyPaid | to, amount | to | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| settleFlipModeChange(player) | external | claimableStored update | None | N/A -- settlement is internal accounting | NO | OK |
| depositCoinflip(player, amount) | external | stake + burn + quest | CoinflipDeposit(caller, amount) + CoinflipStakeUpdated(...) | YES -- amount is raw deposit, newTotal is post-update | YES | OK |
| claimCoinflips(player, amount) | external | mint + state updates | None directly (mint emits Transfer in BurnieCoin) | N/A | NO | OK |
| claimCoinflipsFromBurnie(player, amount) | external | state updates | None directly | N/A | NO | OK |
| claimCoinflipsForRedemption(player, amount) | external | state updates | None directly | N/A | NO | OK |
| consumeCoinflipsForBurn(player, amount) | external | state updates | None directly | N/A | NO | OK |
| setCoinflipAutoRebuy(player, enabled, takeProfit) | external | auto-rebuy config | CoinflipAutoRebuyToggled + CoinflipAutoRebuyStopSet | YES | NO | OK |
| setCoinflipAutoRebuyTakeProfit(player, takeProfit) | external | takeProfit update | CoinflipAutoRebuyStopSet(player, takeProfit) | YES | NO | OK |
| processCoinflipPayouts(bonusFlip, rngWord, epoch) | external | day result + bounty | CoinflipDayResolved(epoch, ...) + BountyPaid if applicable | YES | YES | OK |
| creditFlip(player, amount) | external | stake update | CoinflipStakeUpdated(...) via _addDailyFlip | YES | NO | OK |
| creditFlipBatch(players, amounts) | external | stake updates | CoinflipStakeUpdated(...) per player via _addDailyFlip | YES | NO | OK |

**Special attention: CoinflipDeposit emits raw `amount` (not creditedFlip)**
`_depositCoinflip` emits `CoinflipDeposit(caller, amount)` where `amount` is the original deposit, not the credited amount after quest/recycling bonuses. The actual credited amount is captured in the separate `CoinflipStakeUpdated` event. This is consistent -- deposit event shows what the player put in; stake event shows what they got.

**Special attention: bounty resolution in processCoinflipPayouts**
`CoinflipDayResolved` emits `bountyAfter` which is `currentBounty` AFTER the +1000 accumulation (line 847: `currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT)`). This post-state value is correct for indexers.

**Special attention: settleFlipModeChange emits no event**
This is a pure internal settlement function (accumulates pending claims into claimableStored). No external state transition to signal. Acceptable.

### Findings

- **EVT-CF-01 (INFO):** `settleFlipModeChange` emits no event for claimableStored accumulation. This is internal accounting only; the actual mint/claim path emits events when tokens move. -- Disposition: DOCUMENT
- **EVT-CF-02 (INFO):** Claim functions (claimCoinflips, claimCoinflipsFromBurnie, consumeCoinflipsForBurn) emit no events of their own. The downstream mint via BurnieCoin emits Transfer events. Indexers tracking claims must listen for BurnieCoin Transfer events, not coinflip events. -- Disposition: DOCUMENT

---

## DegenerusStonk (DegenerusStonk.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |
| BurnThrough | from, amount, ethOut, stethOut, burnieOut | from | Custom |
| UnwrapTo | recipient, amount | recipient | Custom |
| YearSweep | ethToGnrus, stethToGnrus, ethToVault, stethToVault | (none) | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| transfer(to, amount) | external | balance update | Transfer(msg.sender, to, amount) | YES | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) | YES | YES | OK |
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES | NO | OK |
| unwrapTo(recipient, amount) | external | burn + sDGNRS transfer | Transfer(msg.sender, 0, amount) via _burn + UnwrapTo(recipient, amount) | YES | YES | OK |
| burn(amount) | external | burn + asset withdrawal | Transfer(msg.sender, 0, amount) via _burn + BurnThrough(msg.sender, amount, ethOut, stethOut, burnieOut) | YES -- ethOut/stethOut/burnieOut are actual values returned by stonk.burn() | YES | OK |
| yearSweep() | external | sDGNRS burn + asset distribution | YearSweep(ethToGnrus, stethToGnrus, ethToVault, stethToVault) | YES -- values computed from 50-50 split of actual burn output | YES | OK |
| burnForSdgnrs(player, amount) | external | balance + supply decrease | Transfer(player, 0, amount) | YES | YES | OK |
| constructor() | -- | initial mint | Transfer(0, CREATOR, deposited) | YES | YES | OK |

**Special attention: burn() event ordering**
`_burn` is called first (emits Transfer(from, 0, amount)), then stonk.burn() returns actual values, then BurnThrough is emitted with the actual out values. The BurnThrough event correctly contains the actual received amounts, not estimates.

**Special attention: yearSweep no Transfer event for sDGNRS burn**
The yearSweep function calls `stonk.burn(remaining)` which burns sDGNRS from the DGNRS contract's balance. The sDGNRS contract emits its own Transfer event for that burn. The DGNRS contract only emits YearSweep. No DGNRS Transfer event is emitted since no DGNRS tokens are burned (they were already burned by prior burn() calls). This is correct.

### Findings

- **EVT-DS-01 (INFO):** `YearSweep` event has no indexed fields. Since this is a once-per-game permissionless call, indexed fields are not needed for filtering. -- Disposition: DOCUMENT

---

## StakedDegenerusStonk (StakedDegenerusStonk.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Burn | from, amount, ethOut, stethOut, burnieOut | from | Custom |
| Deposit | from, ethAmount, stethAmount, burnieAmount | from | Custom |
| PoolTransfer | pool, to, amount | pool, to | Custom |
| PoolRebalance | from, to, amount | from, to | Custom |
| RedemptionSubmitted | player, sdgnrsAmount, ethValueOwed, burnieOwed, periodIndex | player | Custom |
| RedemptionResolved | periodIndex, roll, rolledBurnie, flipDay | periodIndex | Custom |
| RedemptionClaimed | player, roll, flipResolved, ethPayout, burniePayout, lootboxEth | player | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor() | -- | mint to DGNRS + this | Transfer(0, DGNRS, creatorAmount) + Transfer(0, this, poolTotal) | YES | YES | OK |
| wrapperTransferTo(to, amount) | external | balance transfer | Transfer(DGNRS, to, amount) | YES -- soulbound transfer from wrapper | YES | OK |
| receive() | external payable | ETH deposit | Deposit(msg.sender, msg.value, 0, 0) | YES | YES | OK |
| depositSteth(amount) | external | stETH deposit | Deposit(msg.sender, 0, amount, 0) | YES | YES | OK |
| transferFromPool(pool, to, amount) | external | pool + balance update | Transfer(this, to, amount) + PoolTransfer(pool, to, amount) | YES -- amount may be capped to available | YES | OK |
| transferBetweenPools(from, to, amount) | external | pool rebalance | PoolRebalance(from, to, amount) | YES -- no token movement | NO | OK |
| burnAtGameOver() | external | burn all pool tokens | Transfer(this, 0, bal) | YES | YES | OK |
| burn(amount) | external | burn or submit gambling claim | Transfer(from, 0, amount) + Burn(...) for deterministic; Transfer + RedemptionSubmitted for gambling | YES | YES | OK |
| burnWrapped(amount) | external | wrapped burn path | Same as burn() but from DGNRS address | YES | YES | OK |
| resolveRedemptionPeriod(roll, flipDay) | external | period resolution | RedemptionResolved(period, roll, burnieToCredit, flipDay) | YES -- burnieToCredit is actual rolled amount | YES | OK |
| claimRedemption() | external | payout to player | RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth) | YES -- actual payout values after all calculations | YES | OK |

**Special attention: soulbound enforcement**
sDGNRS has no transfer/transferFrom/approve functions at all (they are simply absent, not reverting). Transfer events only fire for mint (constructor), burn, pool distributions, and wrapper transfers. This is correct for a soulbound token.

**Special attention: _deterministicBurnFrom Burn event**
`_deterministicBurnFrom` emits `Burn(beneficiary, amount, ethOut, stethOut, 0)` where beneficiary may differ from burnFrom (for wrapped burns, beneficiary=msg.sender, burnFrom=DGNRS). The event correctly reflects who receives the assets. The Transfer event uses `burnFrom` to show whose sDGNRS balance decreased.

**Special attention: _payEth has no event**
`_payEth` (line 772) is an internal ETH transfer helper with no event. It is always called AFTER the higher-level event (RedemptionClaimed or Burn) has already captured the amounts. This is the Slither DOC-02 pattern -- the higher-level event provides full context, making a per-transfer event redundant. See DOC-02 assessment below.

**Slither DOC-02 assessment:**
DOC-02 flagged `claimablePool -= amount` in DegenerusGame.resolveRedemptionLootbox() (not in sDGNRS). The _payEth pattern here in sDGNRS is similar but different. In sDGNRS, _payEth is always preceded by RedemptionClaimed or Burn events that capture the full payout context. No additional event needed for _payEth itself.

### Findings

- **EVT-SD-01 (INFO):** `_payEth` internal helper emits no event. The calling function (claimRedemption or _deterministicBurnFrom) always emits a comprehensive event before _payEth is called. -- Disposition: DOCUMENT
- **EVT-SD-02 (INFO):** No `transfer`, `transferFrom`, or `approve` functions exist (soulbound). No Approval events are possible. This is intentional for soulbound tokens -- warden filings about "missing ERC-20 functions" are invalid since sDGNRS is not positioned as ERC-20. -- Disposition: DOCUMENT

---

## GNRUS (GNRUS.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Burn | burner, gnrusAmount, ethOut, stethOut | burner | Custom |
| ProposalCreated | level, proposalId, proposer, recipient | level, proposalId, proposer | Custom |
| Voted | level, proposalId, voter, approve, weight | level, proposalId, voter | Custom |
| LevelResolved | level, winningProposalId, recipient, gnrusDistributed | level, winningProposalId | Custom |
| LevelSkipped | level | level | Custom |
| GameOverFinalized | gnrusBurned, ethClaimed, stethClaimed | (none) | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor() | -- | mint 1T to this | Transfer(0, this, INITIAL_SUPPLY) via _mint | YES | YES | OK |
| transfer/transferFrom/approve | external pure | reverts always | None (reverts with TransferDisabled) | N/A | N/A | OK |
| burn(amount) | external | balance + supply decrease, ETH/stETH payout | Transfer(burner, 0, amount) + Burn(burner, amount, ethOut, stethOut) | YES -- ethOut/stethOut reflect actual computed values | YES | OK |
| burnAtGameOver() | external | burn unallocated + finalize | Transfer(this, 0, unallocated) + GameOverFinalized(unallocated, 0, 0) | YES -- GameOverFinalized correctly shows 0 for ETH/stETH since this only burns tokens | YES | OK |
| propose(recipient) | external | proposal creation | ProposalCreated(level, proposalId, proposer, recipient) | YES -- proposalId is the pre-increment value | YES | OK |
| vote(proposalId, approveVote) | external | weight update | Voted(level, proposalId, voter, approveVote, weight) | YES -- weight includes vault bonus if applicable | YES | OK |
| pickCharity(level) | external | level resolution + distribution | LevelResolved(level, bestId, recipient, distribution) or LevelSkipped(level) | YES -- distribution is actual computed amount | YES | OK |
| receive() | external payable | ETH deposit | None | N/A | NO | EVT-GN-01 |

**Special attention: soulbound enforcement**
`transfer`, `transferFrom`, and `approve` all revert with `TransferDisabled()`. No events emitted. Correct for soulbound token.

**Special attention: burn() last-holder sweep**
If the caller's entire balance equals `amount`, or all non-contract GNRUS equals `amount`, the actual burn amount may be swept to their full balance. The Transfer event uses the swept `amount` (after adjustment at line 283/307). The Burn event also uses the adjusted amount. Both correctly reflect the actual post-state.

**Special attention: pickCharity distribution**
`pickCharity` emits both `Transfer(this, recipient, distribution)` and `LevelResolved(level, bestId, recipient, distribution)`. If distribution is 0 (empty pool), it emits `LevelSkipped(level)` instead. All three branches have correct events.

**Special attention: GameOverFinalized hardcoded zeros**
`GameOverFinalized(unallocated, 0, 0)` always emits 0 for ethClaimed and stethClaimed. This is correct because `burnAtGameOver` only burns tokens -- it does not claim any ETH/stETH. The game contract pushes ETH/stETH separately. The event name could be misleading but the values are accurate.

### Findings

- **EVT-GN-01 (INFO):** `receive()` function accepts ETH with no event. ETH arrives from game claimWinnings and direct deposits. Since the game contract emits its own distribution events, and direct ETH sends to GNRUS are uncommon utility operations, the missing event is low-impact but worth noting for indexer completeness. -- Disposition: DOCUMENT
- **EVT-GN-02 (INFO):** `GameOverFinalized` event hardcodes `ethClaimed=0, stethClaimed=0`. These fields exist for potential future use but are always zero in current implementation. Not misleading since burnAtGameOver genuinely claims no assets. -- Disposition: DOCUMENT

---

## WrappedWrappedXRP (WrappedWrappedXRP.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |
| Unwrapped | user, amount | user | Custom |
| Donated | donor, amount | donor | Custom |
| VaultAllowanceSpent | spender, amount | spender | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES | NO | OK |
| transfer(to, amount) | external | balance update | Transfer(from, to, amount) via _transfer | YES | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) + Approval(from, msg.sender, allowed-amount) on allowance decrement | YES | YES | OK |
| unwrap(amount) | external | burn + wXRP reserve decrease | Transfer(sender, 0, amount) via _burn + Unwrapped(msg.sender, amount) | YES -- amount matches both burn and wXRP transfer | YES | OK |
| donate(amount) | external | wXRP reserve increase | Donated(msg.sender, amount) | YES | NO | OK |
| mintPrize(to, amount) | external | supply + balance increase | Transfer(0, to, amount) via _mint | YES | YES | OK |
| vaultMintTo(to, amount) | external | supply + balance + allowance decrease | Transfer(0, to, amount) via _mint + VaultAllowanceSpent(this, amount) | YES | YES | OK |
| burnForGame(from, amount) | external | supply + balance decrease | Transfer(from, 0, amount) via _burn | YES | YES | OK |

**Special attention: transferFrom emits Approval on allowance decrement**
Unlike BurnieCoin (which also does this), WWXRP emits `Approval(from, msg.sender, allowed - amount)` in transferFrom when allowance is not max uint256. This correctly reflects the updated allowance. Standard ERC-20 practice, though some implementations skip the redundant Approval emit.

**Special attention: vaultMintTo with amount=0**
When `amount == 0`, the function returns early with no event. This is correct -- no state change, no event needed.

**Special attention: wrap/unwrap amounts**
`unwrap` burns WWXRP and transfers wXRP at 1:1. The Unwrapped event amount matches both the burn amount and the wXRP transfer. `donate` only transfers wXRP in (no WWXRP minted), so Donated event correctly shows only the wXRP donation amount.

### Findings

No findings. All events correctly match post-state values. Event coverage is complete.

---

## DegenerusVault (DegenerusVault.sol)

Note: DegenerusVault.sol contains TWO contracts:
1. **DegenerusVaultShare** -- Minimal ERC20 for share tokens (DGVB, DGVE)
2. **DegenerusVault** -- Main vault contract

### DegenerusVaultShare Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |

### DegenerusVaultShare Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor(name_, symbol_) | -- | initial supply mint | Transfer(0, CREATOR, INITIAL_SUPPLY) | YES | YES | OK |
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES | NO | OK |
| transfer(to, amount) | external | balance update | Transfer(from, to, amount) via _transfer | YES | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) + Approval(from, sender, newAllowance) | YES | YES | OK |
| vaultMint(to, amount) | external | supply + balance increase | Transfer(0, to, amount) | YES | YES | OK |
| vaultBurn(from, amount) | external | supply + balance decrease | Transfer(from, 0, amount) | YES | YES | OK |

### DegenerusVault Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Deposit | from, ethAmount, stEthAmount, coinAmount | from | Custom |
| Claim | from, sharesBurned, ethOut, stEthOut, coinOut | from | Custom |

### DegenerusVault Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| deposit(coinAmount, stEthAmount) | external payable | coin escrow + stETH pull | Deposit(msg.sender, msg.value, stEthAmount, coinAmount) | YES -- msg.value is actual ETH received | YES | OK |
| receive() | external payable | ETH received | Deposit(msg.sender, msg.value, 0, 0) | YES | YES | OK |
| burnCoin(player, amount) | external | DGVB burn + BURNIE payout | Claim(player, amount, 0, 0, coinOut) | YES -- coinOut is actual computed value | YES | OK |
| burnEth(player, amount) | external | DGVE burn + ETH/stETH payout | Claim(player, amount, ethOut, stEthOut, 0) | YES -- ethOut/stEthOut are actual computed values | YES | OK |
| gameAdvance() | external | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchase(...) | external payable | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchaseTicketsBurnie(quantity) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchaseBurnieLootbox(burnieAmount) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameOpenLootBox(lootboxIndex) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchaseDeityPassFromBoon(priceWei, symbolId) | external payable | forwards to game | None (game emits) | N/A | NO | OK |
| gameClaimWinnings() | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameClaimWhalePass() | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameDegeneretteBetEth(...) | external payable | forwards to game | None (game emits) | N/A | NO | OK |
| gameDegeneretteBetBurnie(...) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameDegeneretteBetWwxrp(...) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameResolveDegeneretteBets(betIds) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetAutoRebuy(enabled) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetAutoRebuyTakeProfit(takeProfit) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetDecimatorAutoRebuy(enabled) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetAfKingMode(...) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetOperatorApproval(operator, approved) | external | forwards to game | None (game emits) | N/A | NO | OK |
| coinDepositCoinflip(amount) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| coinClaimCoinflips(amount) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| coinDecimatorBurn(amount) | external | forwards to coin | None (coin emits) | N/A | NO | OK |
| coinSetAutoRebuy(enabled, takeProfit) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| coinSetAutoRebuyTakeProfit(takeProfit) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| wwxrpMint(to, amount) | external | forwards to WWXRP | None (WWXRP emits) | N/A | NO | OK |
| jackpotsClaimDecimator(lvl) | external | forwards to game | None (game emits) | N/A | NO | OK |

**Special attention: _payEth has no event (Slither DOC-02 pattern)**
`_payEth` and `_paySteth` are internal transfer helpers with no events. They are always called after the Claim event is emitted, which captures the full payout amounts. Same pattern as sDGNRS. No additional event needed.

**Special attention: Vault forwarding functions emit no events**
All 20+ gameplay forwarding functions (gameAdvance, gamePurchase, etc.) emit no events at the vault level. The target contracts (game, coinflip, coin, WWXRP) emit their own events. This is correct -- the vault is a thin proxy and adding redundant events would waste gas.

**Special attention: Refill mechanism (burnCoin/burnEth full supply)**
When a user burns the entire supply of DGVB or DGVE, 1T new shares are minted to them. The `vaultMint` on the share token emits `Transfer(0, player, REFILL_SUPPLY)`. The Claim event captures the burn amount and payout. Both events fire correctly.

### Findings

- **EVT-DV-01 (INFO):** `_payEth` internal helper emits no event. The calling function always emits Claim event before _payEth is called, capturing the full payout context. Same pattern as Slither DOC-02 in DegenerusGame. -- Disposition: DOCUMENT

---

## Slither DOC-02 Cross-Reference

**DOC-02:** `events-maths` detector flagged `claimablePool -= amount` in `DegenerusGame.resolveRedemptionLootbox()` for missing a dedicated event.

**Assessment for non-game contracts:** The `_payEth` pattern in StakedDegenerusStonk and DegenerusVault follows the same design -- internal ETH transfer helpers with no dedicated event, relying on higher-level events (Burn, RedemptionClaimed, Claim) to capture the full context. This is consistent and correct. The DOC-02 finding itself targets DegenerusGame (Plan 01 scope), not these non-game contracts. Confirmed addressed here: no additional events needed for non-game _payEth helpers.

---

## Summary of Findings (Task 1)

| ID | Contract | Severity | Description | Disposition |
|----|----------|----------|-------------|-------------|
| EVT-BC-01 | BurnieCoin | INFO | _mint to VAULT emits no Transfer event (virtual allowance design) | DOCUMENT |
| EVT-BC-02 | BurnieCoin | INFO | _burn from VAULT emits no Transfer event (virtual allowance design) | DOCUMENT |
| EVT-CF-01 | BurnieCoinflip | INFO | settleFlipModeChange emits no event (internal accounting) | DOCUMENT |
| EVT-CF-02 | BurnieCoinflip | INFO | Claim functions emit no events (downstream mint emits Transfer) | DOCUMENT |
| EVT-DS-01 | DegenerusStonk | INFO | YearSweep event has no indexed fields (once-per-game call) | DOCUMENT |
| EVT-SD-01 | StakedDegenerusStonk | INFO | _payEth helper emits no event (higher-level event captures context) | DOCUMENT |
| EVT-SD-02 | StakedDegenerusStonk | INFO | No transfer/approve functions exist (soulbound by design) | DOCUMENT |
| EVT-GN-01 | GNRUS | INFO | receive() accepts ETH with no event (game emits distribution events) | DOCUMENT |
| EVT-GN-02 | GNRUS | INFO | GameOverFinalized hardcodes ethClaimed=stethClaimed=0 (accurate) | DOCUMENT |
| EVT-DV-01 | DegenerusVault | INFO | _payEth helper emits no event (Claim event captures context) | DOCUMENT |
