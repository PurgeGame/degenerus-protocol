# Phase 16 Research: Remaining Invariant Harnesses

## Overview

Phase 15 established the handler architecture and proved ETH solvency. Phase 16 adds four more invariant harnesses covering:
- FUZZ-02: BurnieCoin supply conservation
- FUZZ-03: Game FSM transitions
- FUZZ-04: Vault share math
- FUZZ-05: Ticket queue ordering

## FUZZ-02: BurnieCoin Supply Conservation

### What to check
The BurnieCoin contract maintains a packed `Supply` struct: `{uint128 totalSupply, uint128 vaultAllowance}`.
The critical invariant from the contract NatSpec:
```
totalSupply + vaultAllowance == supplyIncUncirculated
```
The `supplyIncUncirculated` value should be **monotonically non-decreasing** or at least conserved relative to the mint/burn operations. However, the actual invariant is simpler: `supplyIncUncirculated()` is literally `totalSupply + vaultAllowance`, so it's tautological. The real invariant to test is:

1. **Balance conservation**: `sum(balanceOf[all]) == totalSupply()` -- all minted tokens are accounted for in balances
2. **Supply + vault allowance consistency**: `supplyIncUncirculated()` should never decrease unless tokens are burned (and burns reduce totalSupply but may increase vaultAllowance for vault burns)

### Handler design: CoinHandler
The CoinHandler needs to drive:
- `creditCoin(player, amount)` -- called by game/coinflip (onlyFlipCreditors)
- `transfer(from, to, amount)` -- standard ERC20
- Direct purchase (which credits BURNIE via game flow)

Since BurnieCoin's mint/burn functions are access-controlled (onlyDegenerusGameContract, onlyFlipCreditors, onlyVault), the CoinHandler can't call them directly. Instead, we rely on the GameHandler's purchase flow which naturally triggers BURNIE credits. The invariant itself only needs view functions.

### Ghost variables
- `ghost_totalMinted` -- track every successful mint via purchase that credits BURNIE
- No separate handler needed -- we can assert the invariant using existing handlers

### Simplified approach
Rather than a separate CoinHandler, add the BurnieCoin supply invariant to a new invariant test file that reuses GameHandler + VRFHandler + WhaleHandler. The invariant assertions check:
- `coin.supplyIncUncirculated() == coin.totalSupply() + coin.vaultMintAllowance()`
- `coin.totalSupply() >= 0` (always true but canary)
- Initial vault allowance was 2M BURNIE; track that `supplyIncUncirculated >= 2_000_000 ether`

## FUZZ-03: Game FSM Transitions

### What to check
The game has a 3-state FSM:
- PURCHASE (jackpotPhaseFlag=false, gameOver=false)
- JACKPOT (jackpotPhaseFlag=true, gameOver=false)
- GAMEOVER (gameOver=true) -- terminal

Invariants:
1. **Level monotonicity**: `level` can only increase (never decrease)
2. **gameOver is terminal**: once `gameOver == true`, it stays true forever
3. **rngLocked follows request-fulfill-unlock**: when `rngLockedFlag == true`, a VRF request is pending
4. **Phase transitions are valid**: PURCHASE -> JACKPOT -> PURCHASE (cycle) or -> GAMEOVER

### Handler design
Reuse existing GameHandler + VRFHandler + WhaleHandler. Add ghost variables to track FSM state:
- `ghost_prevLevel` -- previous level snapshot
- `ghost_wasGameOver` -- whether gameOver was ever true

### Invariant assertions
- `game.level() >= ghost_prevLevel` (monotonic)
- If `ghost_wasGameOver` then `game.gameOver()` (terminal)
- Level only changes during advanceGame (not during purchase)

## FUZZ-04: Vault Share Math

### What to check
The vault has two share classes: DGVB (coin shares) and DGVE (ETH shares).
Invariant: total redeemable value should not exceed total assets.

For DGVE: `vault.ethReserves() >= 0` (the vault should not become insolvent).
For DGVB: coin reserves should cover outstanding shares.

### Handler design: VaultHandler
The vault's deposit function is `onlyGame`, so we can't deposit directly. Deposits happen naturally through the game flow. For redemptions, only vault owners (>30% of DGVE) can act. Since the creator gets the initial 1T supply, the creator address IS the vault owner.

Handler actions:
- `burnCoin(player, amount)` -- redeem DGVB for BURNIE
- `burnEth(player, amount)` -- redeem DGVE for ETH/stETH

But the vault is complex and tightly coupled. A simpler approach: assert view-level invariants using existing handlers, since game purchases trigger `vault.deposit()`.

### Invariant assertions
- DGVB share supply * coin reserve per share should be consistent
- DGVE share supply * eth reserve per share should be consistent
- `ethShare.totalSupply() > 0` (never fully drained without refill)
- `coinShare.totalSupply() > 0` (never fully drained without refill)

## FUZZ-05: Ticket Queue Ordering

### What to check
The ticket queue (`ticketQueue[level]`) should never contain the same player twice at the same level. The `_queueTickets` function checks `if (owed == 0 && rem == 0)` before pushing to the array, which should prevent duplicates.

### Handler design
Reuse existing GameHandler. After each purchase, the invariant checks that no player appears twice at any given level.

### Invariant assertion
For each active level, scan `ticketQueue[level]` and verify no duplicate addresses. This is O(n^2) per level, so we limit checking to levels near the current level.

## Integration Strategy

### New files needed
1. `test/fuzz/invariant/CoinSupply.inv.t.sol` -- BurnieCoin supply invariant (FUZZ-02)
2. `test/fuzz/invariant/GameFSM.inv.t.sol` -- Game FSM invariant (FUZZ-03)
3. `test/fuzz/invariant/VaultShare.inv.t.sol` -- Vault share invariant (FUZZ-04)
4. `test/fuzz/invariant/TicketQueue.inv.t.sol` -- Ticket queue invariant (FUZZ-05)

### Shared infrastructure
All four reuse DeployProtocol, GameHandler, VRFHandler, WhaleHandler from Phase 15. GameFSM needs a wrapper handler to snapshot state. No new handlers needed for the simple invariant-only approach.

### Plan breakdown
- 16-01: CoinHandler (lightweight) + CoinSupply invariant
- 16-02: FSMHandler (state snapshots) + GameFSM invariant
- 16-03: VaultShare invariant (view-only, no new handler)
- 16-04: TicketQueue invariant (view-only, no new handler)
