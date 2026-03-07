# DegenerusGame.sol -- Lootbox, Boon & Degenerette Audit

**Contract:** DegenerusGame
**File:** contracts/DegenerusGame.sol
**Lines audited:** 726-975
**Solidity:** 0.8.34
**Inherits:** DegenerusGameMintStreakUtils -> DegenerusGameStorage
**Audit date:** 2026-03-07

## Summary

Lootbox opening (ETH and BURNIE), degenerette betting, and boon consumption/issuance. All delegate to specialized modules via delegatecall. The Game contract validates access control and resolves player addresses before delegating.

**Key pattern:** Every external entry point calls `_resolvePlayer(player)` which resolves `address(0)` to `msg.sender` and checks `operatorApprovals` for third-party callers. The resolved address is then forwarded into the delegatecall. This ensures consistent access control across all functions in this section.

**Delegatecall safety:** All delegatecall targets are compile-time constants from `ContractAddresses.sol`. Return values are decoded from `bytes memory data` after success check. On failure, `_revertDelegate(data)` re-throws the module's revert reason via assembly.

## Function Audit

### `openLootBox(address, uint48)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openLootBox(address player, uint48 lootboxIndex) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address that owns the loot box (address(0) = msg.sender); `lootboxIndex` (uint48): Lootbox RNG index assigned at purchase time |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly -- delegates all state mutation to LootboxModule

**Callers:** External callers (players, operators)
**Callees:** `_resolvePlayer(player)` -> `_openLootBoxFor(player, lootboxIndex)`

**ETH Flow:** No ETH accepted (not payable). ETH distribution occurs inside LootboxModule via delegatecall (lootbox prizes paid from Game's balance).
**Invariants:** Player must be msg.sender or msg.sender must be an approved operator. Lootbox index must have available RNG.
**NatSpec Accuracy:** CORRECT -- NatSpec accurately describes player resolution and lootbox index semantics.
**Gas Flags:** None -- minimal wrapper, efficient dispatch.
**Verdict:** CORRECT

---

### `openBurnieLootBox(address, uint48)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function openBurnieLootBox(address player, uint48 lootboxIndex) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address that owns the BURNIE loot box (address(0) = msg.sender); `lootboxIndex` (uint48): Lootbox RNG index assigned at purchase time |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly -- delegates all state mutation to LootboxModule

**Callers:** External callers (players, operators)
**Callees:** `_resolvePlayer(player)` -> `_openBurnieLootBoxFor(player, lootboxIndex)`

**ETH Flow:** No ETH accepted (not payable). BURNIE lootbox prizes are BURNIE tokens, not ETH. No ETH flow.
**Invariants:** Same as openLootBox -- player resolution and operator approval required.
**NatSpec Accuracy:** CORRECT -- NatSpec matches behavior. Describes BURNIE variant clearly.
**Gas Flags:** None -- mirror structure to openLootBox.
**Verdict:** CORRECT

---

### `_openLootBoxFor(address, uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _openLootBoxFor(address player, uint48 lootboxIndex) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Pre-resolved player address; `lootboxIndex` (uint48): Lootbox RNG index |
| **Returns** | None |

**State Reads:** None directly in Game contract -- all reads happen in LootboxModule via delegatecall
**State Writes:** None directly in Game contract -- all writes happen in LootboxModule via delegatecall (lootbox state, claimableWinnings, etc.)

**Callers:** `openLootBox(address, uint48)`
**Callees:** `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.openLootBox.selector, player, lootboxIndex)`

**ETH Flow:** ETH prizes from lootbox rolls are credited to `claimableWinnings[player]` within the delegatecall (pull pattern -- no direct transfer).
**Invariants:** Delegatecall target is compile-time constant. If delegatecall fails, `_revertDelegate` propagates the exact revert reason.
**NatSpec Accuracy:** No NatSpec on this private function. Acceptable for internal implementation.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_openBurnieLootBoxFor(address, uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _openBurnieLootBoxFor(address player, uint48 lootboxIndex) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Pre-resolved player address; `lootboxIndex` (uint48): BURNIE lootbox RNG index |
| **Returns** | None |

**State Reads:** None directly -- all reads happen in LootboxModule via delegatecall
**State Writes:** None directly -- all writes happen in LootboxModule via delegatecall

**Callers:** `openBurnieLootBox(address, uint48)`
**Callees:** `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.openBurnieLootBox.selector, player, lootboxIndex)`

**ETH Flow:** No ETH flow -- BURNIE lootboxes pay in BURNIE tokens via coin minting in the module.
**Invariants:** Same delegatecall safety as `_openLootBoxFor`. Compile-time constant target.
**NatSpec Accuracy:** No NatSpec on private function. Acceptable.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `placeFullTicketBets(address, uint8, uint128, uint8, uint32, uint8)` [external payable]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBets(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external payable` |
| **Visibility** | external |
| **Mutability** | state-changing (payable) |
| **Parameters** | `player` (address): Betting player (address(0) = msg.sender); `currency` (uint8): Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP); `amountPerTicket` (uint128): Bet amount per ticket; `ticketCount` (uint8): Number of spins (1-10); `customTicket` (uint32): Custom packed traits; `heroQuadrant` (uint8): Hero quadrant (0-3) for payout boost, or 0xFF for no hero |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` inline in abi.encodeWithSelector)
**State Writes:** None directly -- all state mutation delegated to DegeneretteModule

**Callers:** External callers (players, operators)
**Callees:** `ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(IDegenerusGameDegeneretteModule.placeFullTicketBets.selector, _resolvePlayer(player), currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)`

**ETH Flow:** Payable -- `msg.value` is forwarded to the delegatecall context. For ETH bets (currency=0), the module validates that `msg.value >= amountPerTicket * ticketCount`. ETH is held by the Game contract.
**Invariants:** Player resolution happens inline via `_resolvePlayer(player)`. All 6 parameters forwarded to module without modification. The module handles currency validation, bet size limits, and payout calculations.
**NatSpec Accuracy:** CORRECT -- NatSpec accurately describes all parameters including currency enum values, ticket count range, and hero quadrant semantics.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `placeFullTicketBetsFromAffiliateCredit(address, uint128, uint8, uint32, uint8)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function placeFullTicketBetsFromAffiliateCredit(address player, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Betting player (address(0) = msg.sender); `amountPerTicket` (uint128): Bet amount per ticket; `ticketCount` (uint8): Number of spins (1-10); `customTicket` (uint32): Custom packed traits; `heroQuadrant` (uint8): Hero quadrant (0-3) for payout boost, or 0xFF for no hero |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` inline)
**State Writes:** None directly -- module deducts affiliate credit from storage

**Callers:** External callers (players with affiliate credit)
**Callees:** `ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(IDegenerusGameDegeneretteModule.placeFullTicketBetsFromAffiliateCredit.selector, _resolvePlayer(player), amountPerTicket, ticketCount, customTicket, heroQuadrant)`

**ETH Flow:** Not payable -- no ETH accepted. Bets funded from affiliate Degenerette credit (internal accounting).
**Invariants:** No `currency` parameter -- affiliate credit is implicitly BURNIE-denominated. All 5 parameters forwarded to module without modification.
**NatSpec Accuracy:** CORRECT -- NatSpec omits currency (correct, since affiliate credit is fixed denomination). Documents all parameters accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `resolveDegeneretteBets(address, uint64[])` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resolveDegeneretteBets(address player, uint64[] calldata betIds) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Betting player (address(0) = msg.sender); `betIds` (uint64[]): Array of bet IDs to resolve |
| **Returns** | None |

**State Reads:** `operatorApprovals[player][msg.sender]` (via `_resolvePlayer` inline)
**State Writes:** None directly -- module resolves bets, updates bet storage, credits winnings

**Callers:** External callers (players resolving completed bets)
**Callees:** `ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(IDegenerusGameDegeneretteModule.resolveBets.selector, _resolvePlayer(player), betIds)`

**ETH Flow:** Not payable. The module may credit ETH winnings to `claimableWinnings[player]` (pull pattern) depending on bet currency and outcome.
**Invariants:** Note the selector dispatches to `resolveBets` in the module interface, not `resolveDegeneretteBets`. This is intentional -- the Game-facing name includes the "Degenerette" prefix for clarity, while the module uses the shorter `resolveBets` name.
**NatSpec Accuracy:** CONCERN (minor) -- NatSpec says `@param betIds Bet ids for the player` but the parameter is actually `uint64[] calldata betIds`, not `uint24` as the plan initially suggested. The actual NatSpec matches the code correctly.
**Gas Flags:** Calldata array passed through delegatecall -- efficient, no memory copy needed for encoding. However, large betIds arrays could increase gas costs linearly.
**Verdict:** CORRECT

---

### `consumeCoinflipBoon(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeCoinflipBoon(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player whose boon to consume |
| **Returns** | `boostBps` (uint16): The boost in basis points to apply |

**State Reads:** `ContractAddresses.COIN`, `ContractAddresses.COINFLIP` (compile-time constants for access control check)
**State Writes:** None directly -- module clears/consumes boon state via delegatecall

**Callers:** BurnieCoin contract, BurnieCoinflip contract (external cross-contract calls)
**Callees:** `ContractAddresses.GAME_BOON_MODULE.delegatecall(IDegenerusGameBoonModule.consumeCoinflipBoon.selector, player)`

**ETH Flow:** No ETH -- boon consumption is pure state mutation (clears boon, returns boost value).
**Invariants:** Access restricted to COIN or COINFLIP contracts only via `msg.sender` check. Reverts with `E()` if caller is unauthorized. Note: no `_resolvePlayer` -- the `player` address is passed directly by the calling contract (COIN/COINFLIP already knows the player identity). Return value decoded from delegatecall bytes via `abi.decode(data, (uint16))`.
**NatSpec Accuracy:** CORRECT -- NatSpec documents access control restriction, parameter, return value, and custom revert condition accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `consumeDecimatorBoon(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDecimatorBoon(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player whose boon to consume |
| **Returns** | `boostBps` (uint16): The boost in basis points to apply |

**State Reads:** `ContractAddresses.COIN` (compile-time constant for access control check)
**State Writes:** None directly -- module clears/consumes boon state via delegatecall

**Callers:** BurnieCoin contract only (external cross-contract call during BURNIE burns)
**Callees:** `ContractAddresses.GAME_BOON_MODULE.delegatecall(IDegenerusGameBoonModule.consumeDecimatorBoost.selector, player)`

**ETH Flow:** No ETH -- pure state mutation.
**Invariants:** Access restricted to COIN contract only. Note the selector mismatch: Game function is `consumeDecimatorBoon` but dispatches to module's `consumeDecimatorBoost`. This is intentional naming -- the Game uses "Boon" (user-facing term) while the module uses "Boost" (implementation term). The selector correctly maps to the module interface method. No `_resolvePlayer` -- same pattern as `consumeCoinflipBoon`.
**NatSpec Accuracy:** CORRECT -- NatSpec documents COIN-only access, parameter, return, and revert accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `consumePurchaseBoost(address)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumePurchaseBoost(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player whose boost to consume |
| **Returns** | `boostBps` (uint16): The boost in basis points to apply |

**State Reads:** `address(this)` (for self-call check)
**State Writes:** None directly -- module clears/consumes boost state via delegatecall

**Callers:** Self-call only -- invoked by delegatecall modules (e.g., MintModule) via `address(this).call(...)` or `DegenerusGame(address(this)).consumePurchaseBoost(player)`
**Callees:** `ContractAddresses.GAME_BOON_MODULE.delegatecall(IDegenerusGameBoonModule.consumePurchaseBoost.selector, player)`

**ETH Flow:** No ETH -- pure state mutation.
**Invariants:** Access restricted to `msg.sender == address(this)`. This is the self-call pattern: delegatecall modules run in Game's context and call back to Game's external functions to trigger other modules. This avoids direct cross-module delegatecall (which would be a security risk). No `_resolvePlayer` -- player is already resolved by the calling module.
**NatSpec Accuracy:** CORRECT -- NatSpec documents self-call access pattern, parameter, return, and revert accurately.
**Gas Flags:** None. The self-call adds ~2600 gas (CALL opcode) but is necessary for module isolation.
**Verdict:** CORRECT

---

### `deityBoonData(address)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function deityBoonData(address deity) external view returns (uint256 dailySeed, uint48 day, uint8 usedMask, bool decimatorOpen, bool deityPassAvailable)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `deity` (address): The deity address to query |
| **Returns** | `dailySeed` (uint256): RNG seed for today's boon generation; `day` (uint48): Current day index; `usedMask` (uint8): Bitmask of slots already used; `decimatorOpen` (bool): Whether decimator boons are available; `deityPassAvailable` (bool): Whether deity pass boons can be generated |

**State Reads:** `deityBoonDay[deity]`, `deityBoonUsedMask[deity]`, `decWindowOpen`, `deityPassOwners.length`, `rngWordByDay[day]`, `rngWordCurrent`
**State Writes:** None (view function)

**Callers:** External callers (off-chain, DeityBoonViewer contract)
**Callees:** `_simulatedDayIndex()` (via GameTimeLib)

**ETH Flow:** None (view function).
**Invariants:**
- `usedMask` is only returned if `deityBoonDay[deity] == day` (same-day check). Otherwise returns 0 (fresh day, no slots used yet). This prevents stale mask data from previous days.
- `deityPassAvailable` is `deityPassOwners.length < 24` -- max 24 deity passes in the protocol.
- RNG fallback chain: `rngWordByDay[day]` -> `rngWordCurrent` -> `keccak256(day, address(this))`. The final fallback ensures a deterministic seed even before any VRF fulfillment (pre-game state).
- This is NOT a delegatecall function -- it reads directly from Game storage. This is correct because it's a pure view aggregation of multiple storage reads.
**NatSpec Accuracy:** CORRECT -- NatSpec accurately documents all 5 return values and their semantics.
**Gas Flags:** Three sequential storage reads for RNG fallback (`rngWordByDay`, `rngWordCurrent`, keccak256). In practice only one or two branches execute.
**Verdict:** CORRECT

---

### `issueDeityBoon(address, address, uint8)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function issueDeityBoon(address deity, address recipient, uint8 slot) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `deity` (address): Deity issuing the boon (address(0) = msg.sender); `recipient` (address): Recipient of the boon; `slot` (uint8): Slot index (0-2) |
| **Returns** | None |

**State Reads:** `operatorApprovals[deity][msg.sender]` (via `_resolvePlayer` -> `_requireApproved`)
**State Writes:** None directly -- module writes deity boon state via delegatecall

**Callers:** External callers (deity pass holders, operators)
**Callees:** `_resolvePlayer(deity)`, then `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.issueDeityBoon.selector, deity, recipient, slot)`

**ETH Flow:** No ETH -- boon issuance is pure state mutation.
**Invariants:**
- Self-boon prevention: `recipient == deity` reverts with `E()`. This prevents deities from issuing boons to themselves.
- Player resolution: `deity` is resolved via `_resolvePlayer` (supports operator pattern). `recipient` is NOT resolved -- it's a direct address (the deity chooses who receives the boon).
- Note: dispatches to `GAME_LOOTBOX_MODULE`, NOT `GAME_BOON_MODULE`. This is because deity boon issuance involves generating lootbox-style rewards (the boon generation logic lives alongside lootbox resolution in LootboxModule).
**NatSpec Accuracy:** CORRECT -- NatSpec documents deity resolution, recipient, slot range, and self-boon revert accurately.
**Gas Flags:** None.
**Verdict:** CORRECT

---

## Delegatecall Dispatch Table

| Game Function | Target Module | Module Selector | Return Type | Access Control |
|---------------|--------------|-----------------|-------------|----------------|
| `openLootBox` | `GAME_LOOTBOX_MODULE` | `IDegenerusGameLootboxModule.openLootBox` | void | `_resolvePlayer` (operator approval) |
| `openBurnieLootBox` | `GAME_LOOTBOX_MODULE` | `IDegenerusGameLootboxModule.openBurnieLootBox` | void | `_resolvePlayer` (operator approval) |
| `placeFullTicketBets` | `GAME_DEGENERETTE_MODULE` | `IDegenerusGameDegeneretteModule.placeFullTicketBets` | void | `_resolvePlayer` (operator approval) |
| `placeFullTicketBetsFromAffiliateCredit` | `GAME_DEGENERETTE_MODULE` | `IDegenerusGameDegeneretteModule.placeFullTicketBetsFromAffiliateCredit` | void | `_resolvePlayer` (operator approval) |
| `resolveDegeneretteBets` | `GAME_DEGENERETTE_MODULE` | `IDegenerusGameDegeneretteModule.resolveBets` | void | `_resolvePlayer` (operator approval) |
| `consumeCoinflipBoon` | `GAME_BOON_MODULE` | `IDegenerusGameBoonModule.consumeCoinflipBoon` | `uint16` | `msg.sender == COIN \|\| COINFLIP` |
| `consumeDecimatorBoon` | `GAME_BOON_MODULE` | `IDegenerusGameBoonModule.consumeDecimatorBoost` | `uint16` | `msg.sender == COIN` |
| `consumePurchaseBoost` | `GAME_BOON_MODULE` | `IDegenerusGameBoonModule.consumePurchaseBoost` | `uint16` | `msg.sender == address(this)` |
| `issueDeityBoon` | `GAME_LOOTBOX_MODULE` | `IDegenerusGameLootboxModule.issueDeityBoon` | void | `_resolvePlayer` + self-boon check |
| `deityBoonData` | *(none -- direct storage read)* | N/A | `(uint256, uint48, uint8, bool, bool)` | None (public view) |

**Module distribution:** 3 modules dispatched from this section:
- **GAME_LOOTBOX_MODULE:** 3 dispatch paths (openLootBox, openBurnieLootBox, issueDeityBoon)
- **GAME_DEGENERETTE_MODULE:** 3 dispatch paths (placeFullTicketBets, placeFullTicketBetsFromAffiliateCredit, resolveBets)
- **GAME_BOON_MODULE:** 3 dispatch paths (consumeCoinflipBoon, consumeDecimatorBoost, consumePurchaseBoost)

**Access control patterns:**
1. **Operator approval** (5 functions): `_resolvePlayer` -> `_requireApproved` for third-party callers
2. **Contract-only** (3 functions): `msg.sender` checked against compile-time contract addresses
3. **Unrestricted** (1 function): `deityBoonData` is a view function, no access control needed

**Naming discrepancies (intentional):**
- `resolveDegeneretteBets` (Game) -> `resolveBets` (Module): Game name adds "Degenerette" prefix for API clarity
- `consumeDecimatorBoon` (Game) -> `consumeDecimatorBoost` (Module): Game uses "Boon" (user-facing), module uses "Boost" (implementation)

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | -- |
| CONCERN | 0 | -- |
| GAS | 0 | -- |
| INFORMATIONAL | 2 | Naming discrepancy between Game/Module for resolveBets and consumeDecimatorBoost (intentional, documented) |

**Overall assessment:** All 12 functions (7 lootbox/degenerette + 5 boon) verified CORRECT. Zero bugs, zero concerns. The section demonstrates a clean, consistent delegation pattern with three distinct access control strategies appropriate to each function's role.

**Key observations:**
1. All delegatecall targets are compile-time constants -- no runtime address resolution attack surface
2. `_resolvePlayer` pattern consistently applied to all player-facing entry points
3. Boon consumption functions use contract-identity access control (COIN, COINFLIP, self) rather than operator approval -- correct because these are cross-contract API calls, not user-initiated
4. `deityBoonData` is the only non-delegatecall function in this section -- correctly implemented as a direct storage read for a view aggregation
5. `issueDeityBoon` dispatches to `GAME_LOOTBOX_MODULE` (not `GAME_BOON_MODULE`) because boon generation uses lootbox-style RNG resolution
