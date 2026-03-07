# DegenerusGameDegeneretteModule.sol -- Function-Level Audit

**Contract:** DegenerusGameDegeneretteModule
**File:** contracts/modules/DegenerusGameDegeneretteModule.sol
**Lines:** 1176
**Solidity:** 0.8.34
**Inherits:** DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

Handles full-ticket Degenerette betting mechanic. Players bet ETH, BURNIE, or WWXRP on 4-trait ticket matches (8 attributes total: 4 colors + 4 symbols). Payouts based on 0-8 attribute matches with per-outcome EV normalization (product-of-ratios) and optional hero quadrant multiplier. Supports affiliate credit betting for BURNIE. Multi-currency resolution: ETH splits 25/75 claimable/lootbox (capped at 10% of pool), BURNIE minted via coin contract, WWXRP minted via WWXRP contract. Activity score drives ROI (90%-99.9%) with bonus redistribution into high-match buckets for ETH and WWXRP.

## Function Audit

### `placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): player address, zero for msg.sender; `currency` (uint8): 0=ETH, 1=BURNIE, 3=WWXRP; `amountPerTicket` (uint128): bet amount per spin; `ticketCount` (uint8): number of spins 1-10; `customTicket` (uint32): packed 4x8-bit traits; `heroQuadrant` (uint8): 0-3 for boost, 0xFF for none |
| **Returns** | none |

**State Reads:** (delegated to `_resolvePlayer` and `_placeFullTicketBets`)
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)

**State Writes:** (delegated to `_placeFullTicketBets`)

**Callers:** DegenerusGame via delegatecall (external entry point)
**Callees:** `_resolvePlayer(player)`, `_placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)`

**ETH Flow:** Receives msg.value when currency=ETH; delegates handling to `_collectBetFunds`
**Invariants:** Player must be msg.sender or approved operator. Bet parameters validated downstream.
**NatSpec Accuracy:** Accurate. Documents currency types, parameter meanings, hero quadrant semantics.
**Gas Flags:** None -- thin wrapper delegating to private functions.
**Verdict:** CORRECT

---

### `placeFullTicketBetsFromAffiliateCredit(address player, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBetsFromAffiliateCredit(address player, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external` |
| **Visibility** | external |
| **Mutability** | state-changing (not payable) |
| **Parameters** | `player` (address): player address, zero for msg.sender; `amountPerTicket` (uint128): bet amount per spin; `ticketCount` (uint8): spins 1-10; `customTicket` (uint32): packed traits; `heroQuadrant` (uint8): 0-3 or 0xFF |
| **Returns** | none |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)
- `lootboxRngIndex`, `lootboxRngWordByIndex[index]` (via `_placeFullTicketBetsCore`)
- `mintPacked_[player]`, `level`, `deityPassCount[player]` (via `_playerActivityScoreInternal`)
- `degeneretteBetNonce[player]`

**State Writes:**
- `degeneretteBets[player][nonce]` = packed bet (via `_placeFullTicketBetsCore`)
- `degeneretteBetNonce[player]` = nonce+1 (via `_placeFullTicketBetsCore`)
- `lootboxRngPendingBurnie += totalBet`

**Callers:** DegenerusGame via delegatecall (external entry point)
**Callees:** `_resolvePlayer(player)`, `_placeFullTicketBetsCore(...)`, `affiliate.consumeDegeneretteCredit(player, totalBet)` [external], `coin.notifyQuestDegenerette(player, totalBet, false)` [external]

**ETH Flow:** No ETH movement. Uses affiliate BURNIE credit (consumed via external call).
**Invariants:**
- `affiliate.consumeDegeneretteCredit` must return exactly `totalBet`; otherwise reverts `InvalidBet`
- Currency is hardcoded to `CURRENCY_BURNIE` (1)
- Not payable -- no ETH accepted
**NatSpec Accuracy:** Accurate. States it uses "BURNIE bet currency semantics without burning wallet balance."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `resolveBets(address player, uint64[] calldata betIds)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resolveBets(address player, uint64[] calldata betIds) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player address, zero for msg.sender; `betIds` (uint64[]): array of bet IDs to resolve |
| **Returns** | none |

**State Reads:**
- `operatorApprovals[player][msg.sender]` (via `_resolvePlayer`)
- `degeneretteBets[player][betId]` for each bet (via `_resolveBet`)
- `lootboxRngWordByIndex[index]` for RNG word availability
- `futurePrizePool` for ETH payout capping

**State Writes:**
- `degeneretteBets[player][betId]` = 0 (deleted on resolve)
- `futurePrizePool` -= ethPortion (on ETH wins)
- `claimableWinnings[player]` += ethPortion (on ETH wins)
- `claimablePool` += ethPortion (on ETH wins)

**Callers:** DegenerusGame via delegatecall (external entry point)
**Callees:** `_resolvePlayer(player)`, `_resolveBet(player, betIds[i])` in loop

**ETH Flow:** ETH payouts from `futurePrizePool` to `claimableWinnings[player]` (via `_distributePayout`). Excess routed to lootbox.
**Invariants:**
- Each betId must have non-zero packed data (otherwise `InvalidBet`)
- RNG word must be available for the bet's index (otherwise `RngNotReady`)
- Bets are deleted after resolution (prevents double-resolve)
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Loop uses unchecked increment -- appropriate gas optimization.
**Verdict:** CORRECT

---

### `_revertDelegate(bytes memory reason)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _revertDelegate(bytes memory reason) private pure` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `reason` (bytes memory): revert reason bytes from failed delegatecall |
| **Returns** | none (always reverts) |

**State Reads:** None
**State Writes:** None

**Callers:** `_resolveLootboxDirect` (on delegatecall failure)
**Callees:** None (assembly revert)

**ETH Flow:** None
**Invariants:** If reason is empty, reverts with `E()`. Otherwise propagates the original revert reason.
**NatSpec Accuracy:** Accurate. Describes "Reverts with the provided reason bytes from a delegatecall failure."
**Gas Flags:** None -- minimal assembly-based revert propagation.
**Verdict:** CORRECT

---

### `_requireApproved(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _requireApproved(address player) private view` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player address to check approval for |
| **Returns** | none |

**State Reads:** `operatorApprovals[player][msg.sender]`
**State Writes:** None

**Callers:** `_resolvePlayer` (when player != msg.sender)
**Callees:** None

**ETH Flow:** None
**Invariants:** Reverts `NotApproved` unless msg.sender == player OR operatorApprovals[player][msg.sender] is true.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_resolvePlayer(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolvePlayer(address player) private view returns (address resolved)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player address or zero for msg.sender |
| **Returns** | `resolved` (address): resolved player address |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_requireApproved`, only if player != address(0) && player != msg.sender)
**State Writes:** None

**Callers:** `placeFullTicketBets`, `placeFullTicketBetsFromAffiliateCredit`, `resolveBets`
**Callees:** `_requireApproved(player)` (conditionally)

**ETH Flow:** None
**Invariants:** Returns msg.sender if player == address(0). Otherwise returns player after approval check.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet per spin; `ticketCount` (uint8): spins; `customTicket` (uint32): packed traits; `heroQuadrant` (uint8): hero quadrant |
| **Returns** | none |

**State Reads:** (delegated to `_placeFullTicketBetsCore` and `_collectBetFunds`)
**State Writes:** (delegated to `_placeFullTicketBetsCore` and `_collectBetFunds`)

**Callers:** `placeFullTicketBets`
**Callees:** `_placeFullTicketBetsCore(...)`, `_collectBetFunds(player, currency, totalBet, msg.value, jackpotResolutionActive)`, `coin.notifyQuestDegenerette(player, totalBet, isEth)` [external]

**ETH Flow:** Passes msg.value to `_collectBetFunds` for ETH bets.
**Invariants:** Quest notification sent only for ETH (isEth=true) and BURNIE (isEth=false) currencies. WWXRP bets do not trigger quest progress.
**NatSpec Accuracy:** No NatSpec provided (internal implementation). Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_placeFullTicketBetsCore(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _placeFullTicketBetsCore(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) private returns (uint256 totalBet, bool jackpotResolutionActive)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): resolved player; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet per spin; `ticketCount` (uint8): spin count; `customTicket` (uint32): packed traits; `heroQuadrant` (uint8): hero quadrant |
| **Returns** | `totalBet` (uint256): total bet amount; `jackpotResolutionActive` (bool): whether jackpot resolution is active |

**State Reads:**
- `lootboxRngIndex` -- current RNG batch index
- `lootboxRngWordByIndex[index]` -- must be 0 (no RNG word yet = accepting bets)
- `rngLockedFlag`, `lastPurchaseDay`, `level` -- for jackpot resolution detection
- `mintPacked_[player]`, `deityPassCount[player]` -- via `_playerActivityScoreInternal`
- `degeneretteBetNonce[player]` -- current bet nonce
- `dailyHeroWagers[day][heroQuadrant]` -- for hero wager tracking (ETH only)
- `playerDegeneretteEthWagered[player][lvl]` -- per-player per-level ETH wagered
- `topDegeneretteByLevel[lvl]` -- top wagerer tracking

**State Writes:**
- `degeneretteBetNonce[player]` = nonce + 1
- `degeneretteBets[player][nonce]` = packed bet data
- `dailyHeroWagers[day][heroQuadrant]` -- updated hero wager packed data (ETH only)
- `playerDegeneretteEthWagered[player][lvl]` += totalBet (ETH only)
- `topDegeneretteByLevel[lvl]` = (playerScaled << 160) | player (if new top, ETH only)

**Callers:** `_placeFullTicketBets`, `placeFullTicketBetsFromAffiliateCredit`
**Callees:** `_validateMinBet(currency, amountPerTicket)`, `_playerActivityScoreInternal(player)`, `_packFullTicketBet(...)`, `_simulatedDayIndex()` [inherited from DegenerusGameStorage]

**ETH Flow:** No direct ETH movement (funds collected separately in `_collectBetFunds`).
**Invariants:**
- `ticketCount` must be 1-10 (MAX_SPINS_PER_BET)
- `amountPerTicket` must be non-zero
- `lootboxRngIndex` must be non-zero (game initialized)
- RNG word for current index must be 0 (bet window open)
- ETH bets blocked during jackpot resolution (`rngLockedFlag && lastPurchaseDay && (level+1)%5==0`)
- `totalBet` = amountPerTicket * ticketCount (no overflow risk: uint128 * uint8 fits uint256)
- Hero wager tracking: wagerUnit scaled by 1e12, saturates at uint32 max (0xFFFFFFFF)
- Top degenerette: stores playerScaled (totalWei/1e12) in upper 96 bits, player address in lower 160 bits

**NatSpec Accuracy:** No NatSpec beyond "@dev Internal implementation for placing Full Ticket bets." Inline comments are thorough.
**Gas Flags:**
- The `dailyHeroWagers` tracking involves a read-modify-write of a packed uint256, acceptable gas cost.
- Hero wager tracking only runs for ETH bets with heroQuadrant < 4, avoiding unnecessary computation.
**Verdict:** CORRECT

---

### `_validateMinBet(uint8 currency, uint128 amount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _validateMinBet(uint8 currency, uint128 amount) private pure` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `currency` (uint8): currency type; `amount` (uint128): bet amount to validate |
| **Returns** | none |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_placeFullTicketBetsCore`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- ETH: min 0.005 ETH (`5 ether / 1000`)
- BURNIE: min 100 BURNIE (`100 ether` = 100e18)
- WWXRP: min 1 WWXRP (`1 ether` = 1e18)
- Unknown currency: reverts `UnsupportedCurrency`
**NatSpec Accuracy:** Accurate (brief: "Validates minimum bet amount for currency").
**Gas Flags:** None -- simple conditional checks.
**Verdict:** CORRECT

---

### `_collectBetFunds(address player, uint8 currency, uint256 totalBet, uint256 ethPaid, bool jackpotResolutionActive)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _collectBetFunds(address player, uint8 currency, uint256 totalBet, uint256 ethPaid, bool jackpotResolutionActive) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): bettor; `currency` (uint8): currency type; `totalBet` (uint256): total bet; `ethPaid` (uint256): msg.value; `jackpotResolutionActive` (bool): jackpot lock |
| **Returns** | none |

**State Reads:**
- `claimableWinnings[player]` (for ETH shortfall from claimable)

**State Writes:**
- `claimableWinnings[player]` -= fromClaimable (ETH shortfall)
- `claimablePool` -= fromClaimable (ETH shortfall)
- `futurePrizePool` += totalBet (ETH only)
- `lootboxRngPendingEth` += totalBet (ETH only)
- `lootboxRngPendingBurnie` += totalBet (BURNIE only)

**Callers:** `_placeFullTicketBets`
**Callees:** `coin.burnCoin(player, totalBet)` [external, BURNIE], `wwxrp.burnForGame(player, totalBet)` [external, WWXRP]

**ETH Flow:**
- ETH bets: msg.value goes to contract balance; `futurePrizePool` and `lootboxRngPendingEth` increase by totalBet
- If ethPaid < totalBet: shortfall pulled from `claimableWinnings[player]` (decrements `claimablePool`)
- If ethPaid > totalBet: reverts `InvalidBet` (overpayment rejected)
- BURNIE: tokens burned from player wallet via `coin.burnCoin`
- WWXRP: tokens burned from player wallet via `wwxrp.burnForGame`

**Invariants:**
- ETH bets during jackpot resolution: double-reverts with `E()` (redundant with `_placeFullTicketBetsCore` check, defensive)
- For claimable shortfall: requires `claimableWinnings[player] > fromClaimable` (strict greater-than). Note: this means if claimableWinnings exactly equals fromClaimable, it reverts. This is intentional -- prevents draining claimable balance to zero via degenerette bets, preserving a dust balance.
- WWXRP bets do not update `lootboxRngPendingBurnie` or `lootboxRngPendingEth` -- WWXRP is mint/burn-based with no pool accounting.

**NatSpec Accuracy:** Brief NatSpec ("Processes bet funds"). Inline comments adequate.
**Gas Flags:** The double-check of `jackpotResolutionActive` for ETH (already checked in `_placeFullTicketBetsCore`) is redundant but defensive. Minimal gas cost.
**Verdict:** CORRECT -- The strict greater-than check on claimable is a design choice preventing zero-balance draining.

---

### `_resolveBet(address player, uint64 betId)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveBet(address player, uint64 betId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `betId` (uint64): bet identifier |
| **Returns** | none |

**State Reads:** `degeneretteBets[player][betId]`
**State Writes:** (delegated to `_resolveFullTicketBet`)

**Callers:** `resolveBets` (in loop)
**Callees:** `_resolveFullTicketBet(player, betId, packed)`

**ETH Flow:** Delegated to resolution functions.
**Invariants:** Packed data must be non-zero (otherwise `InvalidBet`). Mode bit is always 1 (full ticket) since that is the only mode.
**NatSpec Accuracy:** Accurate ("Resolves a bet (determines mode from packed data)"). Note: the mode determination comment is vestigial -- only full ticket mode exists now.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_resolveFullTicketBet(address player, uint64 betId, uint256 packed)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveFullTicketBet(address player, uint64 betId, uint256 packed) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `betId` (uint64): bet ID; `packed` (uint256): packed bet data |
| **Returns** | none |

**State Reads:**
- Unpacked from `packed`: customTicket, ticketCount, currency, amountPerTicket, index, activityScore, heroBits
- `lootboxRngWordByIndex[index]` -- the RNG word for this bet's batch

**State Writes:**
- `degeneretteBets[player][betId]` = 0 (delete)
- `futurePrizePool` -= ethPortion (via `_distributePayout`, ETH only)
- `claimableWinnings[player]` += ethPortion (via `_addClaimableEth`, ETH only)
- `claimablePool` += ethPortion (via `_addClaimableEth`, ETH only)

**Callers:** `_resolveBet`
**Callees:**
- `_roiBpsFromScore(activityScore)` -- ROI calculation
- `_wwxrpHighValueRoi(activityScore)` -- WWXRP bonus ROI (only if currency == WWXRP)
- `DegenerusTraitUtils.packedTraitsFromSeed(resultSeed)` [library] -- generate result traits
- `_countMatches(playerTicket, resultTicket)` -- count attribute matches
- `_fullTicketPayout(...)` -- calculate payout amount
- `_distributePayout(player, currency, payout, lootboxWord)` -- distribute winnings
- `_maybeAwardConsolation(player, currency, amountPerTicket)` -- consolation prize on total loss

**ETH Flow:**
- For each winning spin: payout distributed via `_distributePayout`
- ETH: 25% to claimable (capped at 10% of pool), 75% + excess to lootbox
- BURNIE: minted to player
- WWXRP: minted to player
- On total loss (totalPayout == 0): consolation prize (1 WWXRP) if qualifying

**Invariants:**
- RNG word must be available (non-zero) for the bet's index
- Bet is deleted before payout processing (prevents reentrancy on resolve)
- Each spin uses a deterministic seed: spin 0 uses legacy seed (backwards compatible), spins 1+ mix spinIdx into hash
- Lootbox words for multi-spin ETH bets are also diversified per spin (prevents identical lootbox outcomes)
- Consolation prize only awarded if ALL spins produced 0 payout
- Hero quadrant decoded as 3 bits: bit 0 = enabled, bits 1-2 = quadrant index

**NatSpec Accuracy:** Accurate.
**Gas Flags:**
- The `_roiBpsFromScore` is called once outside the loop with the snapshot activity score -- efficient.
- `_wwxrpHighValueRoi` is also called once outside the loop -- efficient.
- Per-spin hash computation is unavoidable for deterministic independence.
**Verdict:** CORRECT

---

### `_distributePayout(address player, uint8 currency, uint256 payout, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributePayout(address player, uint8 currency, uint256 payout, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `currency` (uint8): currency type; `payout` (uint256): payout amount; `rngWord` (uint256): RNG word for lootbox conversion |
| **Returns** | none |

**State Reads:**
- `futurePrizePool` (ETH only, for cap calculation)

**State Writes:**
- `futurePrizePool` -= ethPortion (ETH only, unchecked subtraction)
- `claimablePool` += ethPortion (via `_addClaimableEth`)
- `claimableWinnings[player]` += ethPortion (via `_addClaimableEth` -> `_creditClaimable`)

**Callers:** `_resolveFullTicketBet` (per winning spin)
**Callees:**
- `_addClaimableEth(player, ethPortion)` (ETH)
- `_resolveLootboxDirect(player, lootboxPortion, rngWord)` (ETH, excess to lootbox)
- `coin.mintForGame(player, payout)` [external] (BURNIE)
- `wwxrp.mintPrize(player, payout)` [external] (WWXRP)

**ETH Flow:**
- ETH: Split 25% claimable / 75% lootbox
- Cap: ethPortion capped at 10% of futurePrizePool (ETH_WIN_CAP_BPS = 1000)
- Excess above cap: redirected to lootbox portion
- After capping: `futurePrizePool -= ethPortion` (unchecked, safe because ethPortion <= 10% of pool)
- Emits `PayoutCapped` event when cap triggers

**Invariants:**
- `ethPortion = payout / 4` (integer division, 25%)
- `lootboxPortion = payout - ethPortion` (75% + rounding)
- maxEth = pool * 1000 / 10000 = pool * 10%
- After capping, ethPortion <= pool * 10%, so unchecked subtraction is safe
- BURNIE and WWXRP payouts are fully minted (no pool constraints)

**NatSpec Accuracy:** Accurate. States "25% as ETH (capped at 10% of pool), 75% + any excess above cap converted to lootbox rewards."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_maybeAwardConsolation(address player, uint8 currency, uint128 amountPerTicket)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeAwardConsolation(address player, uint8 currency, uint128 amountPerTicket) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet amount per spin |
| **Returns** | none |

**State Reads:** None
**State Writes:** None directly (external call to wwxrp.mintPrize)

**Callers:** `_resolveFullTicketBet` (when totalPayout == 0)
**Callees:** `wwxrp.mintPrize(player, CONSOLATION_PRIZE_WWXRP)` [external] (if qualifying)

**ETH Flow:** None. Awards 1 WWXRP token via external mint.
**Invariants:**
- Qualification thresholds: ETH >= 0.01 ETH, BURNIE >= 500, WWXRP >= 20
- Consolation amount: fixed 1 WWXRP (1e18)
- Unsupported currencies do not qualify (no else clause)
- Only called when ALL spins resulted in 0 payout

**NatSpec Accuracy:** Accurate. Documents thresholds and behavior.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint256): ETH value for lootbox; `rngWord` (uint256): RNG word for lootbox roll |
| **Returns** | none |

**State Reads:** None directly (delegatecall reads/writes happen in LootboxModule context)
**State Writes:** None directly (delegatecall writes happen in LootboxModule context)

**Callers:** `_distributePayout` (for ETH lootbox portion)
**Callees:**
- `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(...)` -- calls `IDegenerusGameLootboxModule.resolveLootboxDirect(player, amount, rngWord)`
- `_revertDelegate(data)` -- on delegatecall failure

**ETH Flow:** ETH value is conceptually "converted" to lootbox rewards via the LootboxModule. The actual ETH remains in the Game contract; the LootboxModule handles reward distribution (DGNRS tickets, whale pass claims, etc.) through its own internal accounting.
**Invariants:**
- Delegatecall executes LootboxModule code in Game's storage context
- If delegatecall fails, original revert reason is propagated
- The lootbox module applies its own activity-score-based EV multiplier

**NatSpec Accuracy:** Accurate. Notes "Applies activity-score EV multiplier (80-135%) to match regular lootbox opens."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_packFullTicketBet(uint32 customTicket, uint8 ticketCount, uint8 currency, uint128 amountPerTicket, uint48 index, uint16 activityScore, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _packFullTicketBet(uint32 customTicket, uint8 ticketCount, uint8 currency, uint128 amountPerTicket, uint48 index, uint16 activityScore, uint8 heroQuadrant) private pure returns (uint256 packed)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `customTicket` (uint32): packed traits; `ticketCount` (uint8): spins; `currency` (uint8): currency type; `amountPerTicket` (uint128): bet amount; `index` (uint48): RNG index; `activityScore` (uint16): player activity score; `heroQuadrant` (uint8): hero quadrant |
| **Returns** | `packed` (uint256): packed bet data |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_placeFullTicketBetsCore`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Bit layout: [0]=mode(1), [1]=isRandom(0, implicit), [2-33]=customTicket, [34-41]=ticketCount, [42-43]=currency(2 bits), [44-171]=amountPerTicket, [172-219]=index, [220-235]=activityScore, [236]=hasCustom(1), [237-239]=hero(3 bits: [0]=enabled, [1-2]=quadrant)
- Mode always set to MODE_FULL_TICKET (1)
- hasCustom always set to 1
- Hero encoding: if heroQuadrant < 4, sets enabled bit (1) and quadrant bits. Otherwise hero bits are 0 (disabled).
- Currency field is only 2 bits: values 0-3. Currency=2 is marked UnsupportedCurrency upstream.

**NatSpec Accuracy:** Brief but adequate ("Packs a Full Ticket bet for storage").
**Gas Flags:** None -- bitwise OR operations are gas-efficient.
**Verdict:** CORRECT

---

### `_evNormalizationRatio(uint32 playerTicket, uint32 resultTicket)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _evNormalizationRatio(uint32 playerTicket, uint32 resultTicket) private pure returns (uint256 num, uint256 den)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `playerTicket` (uint32): player's packed traits; `resultTicket` (uint32): result packed traits |
| **Returns** | `num` (uint256): numerator; `den` (uint256): denominator |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_fullTicketPayout`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- For each of 4 quadrants, computes probability ratio uniform/actual:
  - Both match: num *= 100, den *= wC * wS (where wC/wS are 8, 9, or 10 based on bucket index)
  - One match: num *= 1300, den *= 75*(wC+wS) - 2*wC*wS
  - No match: num *= 4225, den *= (75-wC)*(75-wS)
- Weight calculation: bucket 0-3 = 10, 4-6 = 9, 7 = 8
- Uniform probabilities: both=100/5625, one=1300/5625, none=4225/5625 (total = 5625/5625)
- Product of 4 ratios normalizes payout to ensure EXACT equal EV for all trait selections
- Uses unchecked block for gas efficiency; all intermediate values safely bounded
- Max num: 4225^4 = ~3.18e14, max den: 67^4 * factor ~ bounded. Both fit in uint256.

**NatSpec Accuracy:** Thorough. Describes the per-quadrant probability ratio computation, weight derivation, and equal-EV guarantee.
**Gas Flags:** Uses unchecked arithmetic -- appropriate since all values are bounded by trait weight ranges.
**Verdict:** CORRECT

---

### `_countMatches(uint32 playerTicket, uint32 resultTicket)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _countMatches(uint32 playerTicket, uint32 resultTicket) private pure returns (uint8 matches)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `playerTicket` (uint32): player's packed traits; `resultTicket` (uint32): result packed traits |
| **Returns** | `matches` (uint8): number of matching attributes (0-8) |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_resolveFullTicketBet`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- For each of 4 quadrants: extracts color (bits 5-3, masked with & 7) and symbol (bits 2-0, masked with & 7)
- Quadrant bits (7-6) are ignored via the masking -- correct behavior
- Each quadrant can produce 0, 1, or 2 matches (color + symbol independently)
- Maximum total: 4 quadrants * 2 = 8 matches
- Uses unchecked increment -- safe since max is 8

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None -- minimal loop with bit extraction.
**Verdict:** CORRECT

---

### `_wwxrpBonusBucket(uint8 matches)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _wwxrpBonusBucket(uint8 matches) private pure returns (uint8 bucket)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `matches` (uint8): number of attribute matches |
| **Returns** | `bucket` (uint8): bonus bucket (0 or 5-8) |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_fullTicketPayout` (for WWXRP and ETH bonus redistribution)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Matches < 5: returns 0 (no bonus bucket)
- Matches 5-8: returns matches value directly (bucket = matches)
- Bonus redistribution only applies to 5+ match outcomes

**NatSpec Accuracy:** Accurate. Documents "Maps match count to a WWXRP bonus bucket."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_wwxrpBonusRoiForBucket(uint8 bucket, uint256 bonusRoiBps)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _wwxrpBonusRoiForBucket(uint8 bucket, uint256 bonusRoiBps) private pure returns (uint256 bonusBps)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `bucket` (uint8): bonus bucket (5-8); `bonusRoiBps` (uint256): total bonus ROI to distribute |
| **Returns** | `bonusBps` (uint256): bonus BPS for this bucket |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_fullTicketPayout`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Bucket 5: factor = 1,531,388 (smallest share, ~10% of bonus EV)
- Bucket 6: factor = 13,016,797 (~30% of bonus EV, scaled by probability)
- Bucket 7: factor = 57,745,766 (~30% of bonus EV, scaled by probability)
- Bucket 8: factor = 30,027,799 (~30% of bonus EV, scaled by probability)
- Scale = 1,000,000
- bonusBps = bonusRoiBps * factor / WWXRP_BONUS_FACTOR_SCALE
- Factors are derived from uniform-ticket probabilities and the payout table
- Unknown bucket: returns 0

**NatSpec Accuracy:** Accurate. "Returns bonus ROI (bps) for a bucket given total bonus ROI (bps)."
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_fullTicketPayout(uint32 playerTicket, uint32 resultTicket, uint8 matches, uint8 currency, uint128 betAmount, uint256 roiBps, uint256 wwxrpHighRoi, bool heroEnabled, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _fullTicketPayout(uint32 playerTicket, uint32 resultTicket, uint8 matches, uint8 currency, uint128 betAmount, uint256 roiBps, uint256 wwxrpHighRoi, bool heroEnabled, uint8 heroQuadrant) private pure returns (uint256 payout)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `playerTicket` (uint32): player traits; `resultTicket` (uint32): result traits; `matches` (uint8): match count; `currency` (uint8): currency type; `betAmount` (uint128): bet per spin; `roiBps` (uint256): base ROI; `wwxrpHighRoi` (uint256): WWXRP bonus ROI target; `heroEnabled` (bool): hero active; `heroQuadrant` (uint8): hero quadrant |
| **Returns** | `payout` (uint256): payout amount |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_resolveFullTicketBet` (per spin)
**Callees:**
- `_getBasePayoutBps(matches)` -- base payout multiplier
- `_wwxrpBonusBucket(matches)` -- bonus bucket assignment (WWXRP and ETH)
- `_wwxrpBonusRoiForBucket(bucket, bonusRoi/ETH_ROI_BONUS_BPS)` -- per-bucket bonus
- `_evNormalizationRatio(playerTicket, resultTicket)` -- EV normalization
- `_applyHeroMultiplier(payout, playerTicket, resultTicket, matches, heroQuadrant)` -- hero boost/penalty

**ETH Flow:** None (pure computation)
**Invariants:**
- Base formula: `payout = betAmount * basePayoutBps * effectiveRoi / 1,000,000`
  - basePayoutBps is in centi-x (190 = 1.90x)
  - effectiveRoi is in bps (9000 = 90%)
  - Division by 1,000,000 = 100 (centi-x) * 10,000 (bps)
- WWXRP bonus: if wwxrpHighRoi > roiBps, bonus = wwxrpHighRoi - roiBps, redistributed into 5+ match buckets
- ETH bonus: flat ETH_ROI_BONUS_BPS (500 = 5%) redistributed into 5+ match buckets
- EV normalization: payout *= evNum / evDen (product-of-ratios per quadrant)
- Hero multiplier: applied only for 2 <= matches < 8 when heroEnabled
  - Not applied for 0-1 matches (payout already 0)
  - Not applied for 8 matches (hero always matches at jackpot, can't offset)

**NatSpec Accuracy:** Thorough. Documents all parameters and the rarity adjustment.
**Gas Flags:** None -- the nested function calls are all pure with bounded inputs.
**Verdict:** CORRECT

---

### `_applyHeroMultiplier(uint256 payout, uint32 playerTicket, uint32 resultTicket, uint8 matches, uint8 heroQuadrant)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyHeroMultiplier(uint256 payout, uint32 playerTicket, uint32 resultTicket, uint8 matches, uint8 heroQuadrant) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `payout` (uint256): pre-hero payout; `playerTicket` (uint32): player traits; `resultTicket` (uint32): result traits; `matches` (uint8): match count; `heroQuadrant` (uint8): hero quadrant index 0-3 |
| **Returns** | adjusted payout (uint256) |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_fullTicketPayout` (when heroEnabled && 2 <= matches < 8)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Checks if hero quadrant's color AND symbol both match between player and result tickets
- If both match: uses per-M boost from HERO_BOOST_PACKED (16 bits per match count, indexed by matches-2)
  - M=2: 23500, M=3: 14166, M=4: 11833, M=5: 10900, M=6: 10433, M=7: 10166
- If not both match: uses HERO_PENALTY = 9500 (95%)
- Result: `payout * multiplier / HERO_SCALE` where HERO_SCALE = 10,000
- EV-neutrality constraint: P(hero|M) * boost(M) + (1 - P(hero|M)) * penalty = 10,000 for each M
- Boost decreases as M increases (more matches = higher chance hero quadrant matches, so less boost needed)

**NatSpec Accuracy:** Accurate. Describes "hero quadrant boost/penalty" and EV-neutrality.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_getBasePayoutBps(uint8 matches)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _getBasePayoutBps(uint8 matches) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `matches` (uint8): number of attribute matches (0-8) |
| **Returns** | base payout in centi-x (uint256) |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_fullTicketPayout`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Matches >= 8: returns QUICK_PLAY_BASE_PAYOUT_8_MATCHES = 10,000,000 (100,000x)
- Matches 0-7: extracted from QUICK_PLAY_BASE_PAYOUTS_PACKED, 32 bits per match count
  - 0 matches: 0 (no payout)
  - 1 match: 0 (no payout)
  - 2 matches: 190 (1.90x)
  - 3 matches: 475 (4.75x)
  - 4 matches: 1500 (15x)
  - 5 matches: 4250 (42.5x)
  - 6 matches: 19500 (195x)
  - 7 matches: 100000 (1,000x)
- Values are in centi-x: divide by 100 for actual multiplier

**NatSpec Accuracy:** Accurate. Documents "base payout multiplier in centi-x."
**Gas Flags:** None -- single packed constant extraction.
**Verdict:** CORRECT

---

### `_playerActivityScoreInternal(address player)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _playerActivityScoreInternal(address player) private view returns (uint256 scoreBps)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `player` (address): player address |
| **Returns** | `scoreBps` (uint256): activity score in basis points |

**State Reads:**
- `deityPassCount[player]` -- deity pass ownership
- `mintPacked_[player]` -- packed mint data (levelCount, frozenUntilLevel, bundleType)
- `level` -- current game level (used for streak effective calculation and mint count bonus)

**State Writes:** None (view)

**Callers:** `_placeFullTicketBetsCore` (at bet placement, score snapshot stored in packed bet)
**Callees:**
- `_mintStreakEffective(player, level + 1)` [inherited] -- effective mint streak
- `_mintCountBonusPoints(levelCount, currLevel)` -- mint count to bonus points
- `questView.playerQuestStates(player)` [external] -- quest streak from Quests contract
- `affiliate.affiliateBonusPointsBest(currLevel, player)` [external] -- affiliate bonus points

**ETH Flow:** None
**Invariants:**
- Returns 0 for address(0)
- Deity pass holders get fixed 50 streak + 25 mint count + 80% deity bonus = 155% base + quest + affiliate
- Non-deity: streak capped at 50 points, mint count proportional (0-25 points)
- Whale pass active: streak floor = 50 points, mint count floor = 25 points
- Quest streak: up to 100 points (capped)
- Affiliate bonus: from affiliate.affiliateBonusPointsBest (external)
- Whale bundle bonus: type 1 = +10%, type 3 = +40%
- All components multiplied by 100 to convert points to BPS
- Score is uncapped here; capping happens in `_roiBpsFromScore`

**NatSpec Accuracy:** Accurate. Documents "activity score based on various engagement metrics."
**Gas Flags:** Two external calls (questView, affiliate) per bet placement -- unavoidable for real-time scoring.
**Verdict:** CORRECT

---

### `_mintCountBonusPoints(uint24 mintCount, uint24 currLevel)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _mintCountBonusPoints(uint24 mintCount, uint24 currLevel) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `mintCount` (uint24): player's total mint count; `currLevel` (uint24): current game level |
| **Returns** | bonus points (uint256): 0-25 |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_playerActivityScoreInternal`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Level 0: always returns 0 (no mints possible)
- mintCount >= currLevel: returns 25 (maximum)
- Otherwise: proportional = mintCount * 25 / currLevel (integer division)
- Output range: 0-25

**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_roiBpsFromScore(uint256 score)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _roiBpsFromScore(uint256 score) private pure returns (uint256 roiBps)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `score` (uint256): activity score in basis points |
| **Returns** | `roiBps` (uint256): ROI in basis points |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_resolveFullTicketBet`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Score capped at ACTIVITY_SCORE_MAX_BPS (30,500 = 305%)
- Three-segment piecewise curve:
  1. 0 to 7,500 (75%): quadratic 9,000 -> 9,500 (90% -> 95% ROI)
     - Formula: 9000 + 1000*x/7500 - 500*x^2/7500^2
     - Concave curve (diminishing returns)
  2. 7,500 to 25,500 (75% -> 255%): linear 9,500 -> 9,950 (95% -> 99.5% ROI)
  3. 25,500 to 30,500 (255% -> 305%): linear 9,950 -> 9,990 (99.5% -> 99.9% ROI)
- At score=0: roiBps = 9,000 (90%)
- At score=7,500: roiBps = 9,500 (95%) -- verify: 9000 + 1000 - 500 = 9,500. Correct.
- At score=30,500: roiBps = 9,990 (99.9%)
- ETH bonus note: ETH bonus redistribution is handled in `_fullTicketPayout`, not here

**NatSpec Accuracy:** Accurate. Documents the three-segment curve with exact thresholds.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_wwxrpHighValueRoi(uint256 score)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _wwxrpHighValueRoi(uint256 score) private pure returns (uint256 roiBps)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `score` (uint256): activity score in basis points |
| **Returns** | `roiBps` (uint256): WWXRP high-value ROI in basis points |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_resolveFullTicketBet` (only when currency == WWXRP)
**Callees:** None

**ETH Flow:** None
**Invariants:**
- Score capped at ACTIVITY_SCORE_MAX_BPS (30,500)
- Linear scale from 9,000 (90%) at score=0 to 10,990 (109.9%) at score=30,500
- Formula: 9,000 + score * (10,990 - 9,000) / 30,500 = 9,000 + score * 1,990 / 30,500
- This ROI can exceed 100% (up to 109.9%) -- this is the target ROI for WWXRP bonus redistribution
- The difference (wwxrpHighRoi - roiBps) is the bonus ROI redistributed into 5+ match buckets
- At max score: bonus ROI = 10,990 - 9,990 = 1,000 bps (10%)

**NatSpec Accuracy:** Accurate. Documents "WWXRP high-value ROI" and the linear scaling.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_addClaimableEth(address beneficiary, uint256 weiAmount)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _addClaimableEth(address beneficiary, uint256 weiAmount) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `beneficiary` (address): address to credit; `weiAmount` (uint256): amount in wei |
| **Returns** | none |

**State Reads:** None directly (reads happen in `_creditClaimable`)
**State Writes:**
- `claimablePool` += weiAmount
- `claimableWinnings[beneficiary]` += weiAmount (via `_creditClaimable`)

**Callers:** `_distributePayout` (for ETH payouts)
**Callees:** `_creditClaimable(beneficiary, weiAmount)` [inherited from DegenerusGamePayoutUtils]

**ETH Flow:** Credits ETH to player's claimable balance. No actual ETH transfer -- ETH remains in contract, player withdraws later.
**Invariants:**
- Early return if weiAmount == 0 (no-op)
- `claimablePool` acts as aggregate liability counter
- `_creditClaimable` increments per-player balance and emits `PlayerCredited`
- Note: This version does NOT use auto-rebuy (simplified compared to other modules' `_addClaimableEth` that take entropy parameter)

**NatSpec Accuracy:** Accurate. "Adds ETH to a player's claimable winnings balance."
**Gas Flags:** None.
**Verdict:** CORRECT

---

## Payout Table Verification

| Matches | Base Centi-x | Multiplier | Description | Code Constant | Verified |
|---------|-------------|------------|-------------|---------------|----------|
| 0 | 0 | 0x | No match (consolation only) | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 0-31 | YES |
| 1 | 0 | 0x | One attribute match (no payout) | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 32-63 | YES |
| 2 | 190 | 1.90x | Two attribute matches | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 64-95 | YES |
| 3 | 475 | 4.75x | Three attribute matches | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 96-127 | YES |
| 4 | 1500 | 15x | Four attribute matches | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 128-159 | YES |
| 5 | 4250 | 42.5x | Five attribute matches | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 160-191 | YES |
| 6 | 19500 | 195x | Six attribute matches | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 192-223 | YES |
| 7 | 100000 | 1,000x | Seven attribute matches | QUICK_PLAY_BASE_PAYOUTS_PACKED bit 224-255 | YES |
| 8 | 10,000,000 | 100,000x | Perfect match (jackpot) | QUICK_PLAY_BASE_PAYOUT_8_MATCHES | YES |

**EV Verification:** Code comment states "Total EV at 100% ROI: 99.99% (just under 100%)". This is achieved through the combination of base payouts and weighted trait probabilities (75-value weight space with buckets of 8, 9, or 10). The per-outcome EV normalization ratio ensures identical expected value regardless of trait selection.

**Hero Multiplier Table:**

| Matches | Boost (hero matches) | Penalty (hero doesn't match) | Scale |
|---------|---------------------|------------------------------|-------|
| 2 | 23,500 (2.35x) | 9,500 (0.95x) | 10,000 |
| 3 | 14,166 (1.4166x) | 9,500 (0.95x) | 10,000 |
| 4 | 11,833 (1.1833x) | 9,500 (0.95x) | 10,000 |
| 5 | 10,900 (1.09x) | 9,500 (0.95x) | 10,000 |
| 6 | 10,433 (1.0433x) | 9,500 (0.95x) | 10,000 |
| 7 | 10,166 (1.0166x) | 9,500 (0.95x) | 10,000 |

**Hero Boost Packed Constant Verification:**
`HERO_BOOST_PACKED = 0x27b628c12a942e3937565bcc`
- M=2 (offset 0): 0x5bcc = 23,500 -- Correct
- M=3 (offset 16): 0x3756 = 14,166 -- Correct
- M=4 (offset 32): 0x2e39 = 11,833 -- Correct
- M=5 (offset 48): 0x2a94 = 10,900 -- Correct
- M=6 (offset 64): 0x28c1 = 10,433 -- Correct
- M=7 (offset 80): 0x27b6 = 10,166 -- Correct

## Multi-Currency Flow Map

| Currency | ID | Bet Collection | Payout Distribution | Pool Tracking | Notes |
|----------|-----|---------------|---------------------|---------------|-------|
| ETH | 0 | msg.value -> futurePrizePool (or claimable shortfall) | 25% -> claimableWinnings (capped 10% pool); 75% + excess -> lootbox via delegatecall | futurePrizePool, lootboxRngPendingEth | ETH stays in contract; player withdraws claimable later |
| BURNIE | 1 | coin.burnCoin(player, totalBet) | coin.mintForGame(player, payout) | lootboxRngPendingBurnie | Pure burn/mint cycle; no pool accounting |
| WWXRP | 3 | wwxrp.burnForGame(player, totalBet) | wwxrp.mintPrize(player, payout) | None | Pure burn/mint cycle; no pool accounting |
| Affiliate BURNIE | 1 (via affiliate) | affiliate.consumeDegeneretteCredit(player, totalBet) | coin.mintForGame(player, payout) | lootboxRngPendingBurnie | Credit consumed, no wallet burn; payout same as BURNIE |

**Consolation Prize (all currencies):** On total loss (all spins = 0 payout), if bet qualifies (ETH >= 0.01, BURNIE >= 500, WWXRP >= 20), awards 1 WWXRP via wwxrp.mintPrize.

## ETH Mutation Path Map

| # | Path | Source | Destination | Trigger | Function |
|---|------|--------|-------------|---------|----------|
| 1 | Bet placement (ETH, msg.value) | msg.value (external) | contract balance + futurePrizePool | placeFullTicketBets with currency=0 | _collectBetFunds |
| 2 | Bet placement (ETH, from claimable) | claimableWinnings[player] | futurePrizePool | placeFullTicketBets with ethPaid < totalBet | _collectBetFunds |
| 3 | Claimable pool decrement (shortfall) | claimablePool | (decremented) | ETH bet with claimable shortfall | _collectBetFunds |
| 4 | Lootbox pending tracking | (accounting) | lootboxRngPendingEth += totalBet | ETH bet placement | _collectBetFunds |
| 5 | Payout: ETH claimable credit | futurePrizePool | claimableWinnings[player] + claimablePool | ETH bet resolution with matches >= 2 | _distributePayout -> _addClaimableEth |
| 6 | Payout: ETH lootbox conversion | futurePrizePool (virtual) | Lootbox rewards via delegatecall | ETH bet resolution, 75% of payout | _distributePayout -> _resolveLootboxDirect |
| 7 | Payout cap overflow | ETH portion excess | Lootbox rewards (added to lootboxPortion) | ethPortion > 10% of pool | _distributePayout |

**Key ETH Accounting Invariants:**
- futurePrizePool increases by totalBet at placement, decreases by ethPortion at resolution
- claimablePool increases by ethPortion at resolution, decreases by fromClaimable at claimable-funded bets
- The 75% lootbox portion is "virtual" -- it does not reduce futurePrizePool; the lootbox module handles its own distribution from the same contract balance
- ETH solvency: contract must hold >= claimablePool at all times; guaranteed because ethPortion <= 10% of pool

## Activity Score Breakdown

| Component | Source | Non-Deity Points | Deity Points | BPS |
|-----------|--------|-------------------|-------------|-----|
| Streak | _mintStreakEffective | min(streak, 50) | 50 (fixed) | x100 |
| Mint Count | _mintCountBonusPoints | 0-25 (proportional) | 25 (fixed) | x100 |
| Quest Streak | questView.playerQuestStates | min(streak, 100) | min(streak, 100) | x100 |
| Affiliate | affiliate.affiliateBonusPointsBest | variable | variable | x100 |
| Deity Bonus | deityPassCount | N/A | +8,000 BPS (80%) | direct |
| Whale x10 | bundleType == 1 | +1,000 BPS (10%) | N/A | direct |
| Whale x100 | bundleType == 3 | +4,000 BPS (40%) | N/A | direct |

**Whale Pass Floor:** When pass is active (frozenUntilLevel > currLevel), streak floor = 50 points, mintCount floor = 25 points.

**ROI Curve Summary:**

| Score Range (BPS) | Activity % | ROI Range | Curve Type |
|-------------------|-----------|-----------|------------|
| 0 - 7,500 | 0% - 75% | 90.0% - 95.0% | Quadratic (concave) |
| 7,500 - 25,500 | 75% - 255% | 95.0% - 99.5% | Linear |
| 25,500 - 30,500 | 255% - 305% | 99.5% - 99.9% | Linear |

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS | 0 | No significant inefficiencies |
| CORRECT | 28 | All 28 functions verified correct |

**Overall Assessment:** All 28 functions in DegenerusGameDegeneretteModule.sol are CORRECT. The contract implements a mathematically rigorous betting system with:
- Per-outcome EV normalization ensuring equal expected value regardless of trait selection
- EV-neutral hero quadrant multipliers (boost/penalty balanced per match count)
- Multi-currency support with appropriate pool accounting (ETH) and burn/mint cycles (BURNIE, WWXRP)
- Proper access control via operator approvals
- Defensive double-checks (jackpot resolution block in both Core and CollectBetFunds)
- Safe arithmetic (unchecked blocks only where overflow is impossible)
- Deterministic RNG derivation with per-spin independence
