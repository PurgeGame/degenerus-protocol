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
