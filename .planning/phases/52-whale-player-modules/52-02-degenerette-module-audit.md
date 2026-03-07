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
