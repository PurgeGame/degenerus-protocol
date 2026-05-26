---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 02
status: complete
requirements: [BTOMB-01, BTOMB-02]
files_modified:
  - contracts/BurnieCoin.sol
  - contracts/modules/DegenerusGameGameOverModule.sol
committed: false
---

# 326-02 BTOMB — gameover BURNIE worthless-token tombstone

## What changed
At `gameOver()` the protocol one-shot floods BURNIE's virtual VAULT mint allowance
(`_supply.vaultAllowance`) by **1e36 wei (1 quintillion BURNIE)** as an overhang tombstone
signal. Circulating `totalSupply()` is NOT touched — the signal lands only in
`supplyIncUncirculated()`, `vaultMintAllowance()`, and `balanceOf(VAULT)`.

## BurnieCoin.sol
- New constant `uint256 private constant BURNIE_TOMBSTONE_WEI = 1e36;` (NatSpec: ~340x headroom under uint128 max ~3.4e38).
- New one-shot latch `bool private _tombstoneFlooded;` (declared after `_supply`).
- New entrypoint `tombstoneAtGameOver()`:
  - **GAME-gated**: `if (msg.sender != ContractAddresses.GAME) revert OnlyGame();`
  - **one-shot**: `if (_tombstoneFlooded) return;` then `_tombstoneFlooded = true;` (early-return, NOT revert — chosen so a (structurally impossible) re-call cannot brick the critical gameover path).
  - **CHECKED add** (NOT `unchecked`): `_supply.vaultAllowance = _toUint128(uint256(_supply.vaultAllowance) + BURNIE_TOMBSTONE_WEI);` — `_toUint128` reverts on uint128 overflow.
  - Reuses the existing `VaultEscrowRecorded(sender, amount)` event (an allowance increase). Does NOT route through `vaultEscrow`'s `unchecked` block, and does NOT touch the `:370` reclassification path (C4).

## DegenerusGameGameOverModule.sol
- New `interface IBurnieTombstone { function tombstoneAtGameOver() external; }` (after `IGNRUSGameOver`).
- New `IBurnieTombstone private constant burnie = IBurnieTombstone(ContractAddresses.COIN);` (BURNIE = `COIN`; mirrors the `charityGameOver` constant convention).
- New call `burnie.tombstoneAtGameOver();` adjacent to `dgnrs.burnAtGameOver();` in the gameover-drain — two adjacent drain hooks. `handleFinalSweep` byte-unchanged.

## Coordination note
POOL (326-05) co-hooks the same gameover-drain region but in DIFFERENT contracts
(StakedDegenerusStonk / DegenerusVault); only the drain ORDERING is shared, no shared signature — composes cleanly.

## Verification
- `grep 1e36` present + named; GAME gate present; checked add (no `unchecked` in fn); early-return latch.
- `git diff` shows NO `_supply.totalSupply` mutation (only the NatSpec mentions `totalSupply()` is untouched).
- GameOverModule call wired at the drain; `handleFinalSweep` not in any diff hunk.
- Compile authoritative at the 326-08 full-tree build.

## Not committed
Batched-diff discipline.
