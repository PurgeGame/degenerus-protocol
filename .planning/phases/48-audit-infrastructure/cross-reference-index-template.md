# Cross-Reference Index Template

**Purpose:** Record every caller/callee relationship across the protocol in a standardized, auditable format. This template formalizes the format used in the Phase 57 cross-contract call graph analysis.

**How to fill out:** For each contract and module in scope, trace every external call, delegatecall, and view call. Record each relationship as a row in the appropriate section. Include context annotations for security-critical paths.

---

## Section A: Delegatecall Dispatch Map

Every delegatecall from the central contract (e.g., `DegenerusGame.sol`) into a delegatecall module. Each row represents one dispatch path where the central contract forwards execution to a module that runs in the central contract's storage context.

| # | Game Function | Target Module | Module Function | Call Type |
|---|--------------|---------------|-----------------|-----------|
| 1 | `advanceGame()` | GAME_ADVANCE_MODULE | `advanceGame()` | delegatecall |
| 2 | `wireVrf(coordinator_, subId, keyHash_)` | GAME_ADVANCE_MODULE | `wireVrf(coordinator_, subId, keyHash_)` | delegatecall |
| 3 | `_purchaseFor(buyer, ticketQty, lootBoxAmt, affCode, payKind)` | GAME_MINT_MODULE | `purchase(buyer, ticketQty, lootBoxAmt, affCode, payKind)` | delegatecall |
| ... | ... | ... | ... | delegatecall |

**Fill-in instructions:**

- **Game Function:** The external or internal function on the central contract that initiates the delegatecall. Include full signature with parameter names.
- **Target Module:** Use the `ContractAddresses` constant name (e.g., `GAME_ADVANCE_MODULE`, `GAME_MINT_MODULE`). This matches the address used in the `delegatecall` instruction.
- **Module Function:** The function actually executed in the module contract. May differ from the Game function name if the central contract renames the dispatch (e.g., `_purchaseFor` dispatches to `purchase`).
- **Call Type:** Always `delegatecall` in this section.
- Each row = one unique delegatecall dispatch path from the central contract.

---

## Section B: Cross-Contract External Calls

All external calls between protocol contracts, grouped by source contract. This captures every state-changing call, view call, and value transfer between independent contract deployments.

| Source Contract | Function | Target Contract | Method Called | Call Type |
|----------------|----------|----------------|--------------|-----------|
| DegenerusGame | `payCoinflipBountyDgnrs` | DegenerusStonk | `poolBalance(Pool.Reward)` | view |
| DegenerusGame | `payCoinflipBountyDgnrs` | DegenerusStonk | `transferFromPool(Pool.Reward, player, payout)` | external |
| BurnieCoin | `creditFlip` | BurnieCoinflip | `creditFlip(player, amount)` | external |
| ... | ... | ... | ... | ... |

**Fill-in instructions:**

- **Source Contract:** The contract initiating the call. For modules executing via delegatecall, note the module name with "(via Game)" since the call originates from the Game's address.
- **Function:** The source function that makes the call. Use the actual function name visible in source code.
- **Target Contract:** The destination contract receiving the call.
- **Method Called:** The function signature called on the target, including key parameter names.
- **Call Type values:**
  - `external` = state-changing external call (modifies target state or sends ETH)
  - `view` = staticcall / view function (read-only, no state changes)
  - `delegatecall` = delegatecall (only appears in Section A)

**Grouping:** Group rows by source contract for readability. When modules execute via delegatecall from a central contract, create a subsection noting "Modules executing in Game context (via delegatecall -- external calls originate from Game's address)."

---

## Section C: Module-to-Game Self-Calls

The self-call pattern is unique to delegatecall architectures. When a module executing via delegatecall on the central contract needs to invoke another module, it calls back into the central contract's external interface using `IDegenerusGame(address(this))`. This triggers a new delegatecall chain through the central contract's dispatch.

| Source Module | Intermediate Call | Final Target Module | Final Function |
|--------------|-------------------|---------------------|----------------|
| MintModule | `Game.recordMint{value}(...)` | MintModule | `recordMintData(...)` |
| MintModule | `Game.consumePurchaseBoost(...)` | BoonModule | `consumePurchaseBoost(...)` |
| EndgameModule | `Game.runDecimatorJackpot(...)` | DecimatorModule | `runDecimatorJackpot(...)` |
| ... | ... | ... | ... |

**Fill-in instructions:**

- **Source Module:** The module currently executing via delegatecall that initiates the self-call.
- **Intermediate Call:** The external function called on the central contract via `IDegenerusGame(address(this))`. This is a true external call that re-enters the central contract.
- **Final Target Module:** The module that ultimately executes the delegatecall dispatched by the central contract.
- **Final Function:** The function executed in the final target module.
- Note: Some self-calls target view functions (e.g., `playerActivityScore`) which do NOT trigger delegatecall -- these should be documented separately with a "(view, no delegatecall)" annotation.

**Why this matters:** Self-calls create implicit dependencies between modules. A module's execution may be interrupted by re-entry through the central contract, and the self-call executes in a fresh delegatecall context while the original call is still on the stack. Reentrancy safety must be verified for each self-call path.

---

## Section D: Context Annotations

For security-critical relationships, annotate each caller/callee edge with the following context dimensions. Not every edge needs all annotations -- focus on paths that handle ETH, modify critical state, or cross trust boundaries.

### D.1 Access Control

Who can initiate the call chain? Document the entry-point access control.

```
| Relationship | Access Control | Notes |
|-------------|----------------|-------|
| Game.advanceGame -> AdvanceModule | public (anyone) | Bounty-incentivized; requires RNG ready |
| Game.wireVrf -> AdvanceModule | onlyAdmin | One-time setup only |
| Game.purchase -> MintModule | public (anyone) | Requires msg.value >= cost |
```

### D.2 Value Flow

Does ETH (or token value) move with this call? Document the value flow direction and magnitude.

```
| Relationship | Value Flow | Direction | Magnitude |
|-------------|------------|-----------|-----------|
| MintModule -> VAULT.call{value} | ETH | Game -> Vault | 20% of lootbox ETH (presale only) |
| Game._claimWinningsInternal -> player.call{value} | ETH | Game -> Player | claimableWinnings[player] |
```

### D.3 Reentrancy Implications

Can this call lead to re-entry? Document the reentrancy risk and mitigation.

```
| Relationship | Reentrancy Risk | Mitigation |
|-------------|-----------------|------------|
| Game._claimWinningsInternal -> player.call{value} | External call to untrusted address | CEI pattern: state cleared before call |
| Module self-call via address(this) | Re-entry through Game dispatch | rngLockedFlag prevents state conflicts |
```

### D.4 Guard Conditions

What must be true for the call to execute? Document preconditions that gate the call.

```
| Relationship | Guard Condition | Effect if False |
|-------------|-----------------|-----------------|
| AdvanceModule.advanceGame -> BurnieCoin.creditFlip | rngLockedFlag == false | Reverts with RngLocked |
| GameOverModule.handleGameOverDrain -> DecimatorModule | gameOver == true | Never reached |
```

---

## Section E: Aggregation Summary

Summary statistics for the complete cross-reference index.

| Metric | Count |
|--------|-------|
| Total delegatecall paths | N |
| Total cross-contract edges (protocol-internal) | N |
| Module self-call patterns | N |
| Contracts with outbound calls | N |
| Contracts with zero outbound calls | N |
| External dependencies (non-protocol) | N |

**Per-contract edge summary:**

| Contract | Outbound Edges | Inbound Edges | Net Direction |
|----------|---------------|---------------|---------------|
| DegenerusGame (direct + via modules) | N | N | hub |
| BurnieCoin | N | N | ... |
| ... | ... | ... | ... |

---

## Appendix: Inbound Call Summary

For each contract, which other contracts call INTO it. This is the reverse view of Section B, useful for understanding a contract's attack surface.

| Target Contract | Called By | Via Function | Methods Exposed |
|----------------|-----------|-------------|-----------------|
| DegenerusGame | BurnieCoin, BurnieCoinflip, Vault, Stonk, Admin, ... | various | `rngLocked()`, `level()`, `purchase()`, ... |
| BurnieCoin | Game (modules), Coinflip, Vault, Stonk, Affiliate, Admin | various | `creditFlip()`, `burnCoin()`, `mintForGame()`, ... |
| ... | ... | ... | ... |

**Fill-in instructions:** Derive this by reversing Section B. For each target contract, collect all rows from Section B where it appears as the target. Group by calling contract and summarize the methods exposed.
