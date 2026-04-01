---
phase: 146-execute-removals
plan: 02
subsystem: admin-forwarding-wrappers
tags: [abi-cleanup, access-control, forwarding-removal]
dependency_graph:
  requires: [145-REVIEW-DECISIONS]
  provides: [vault-owner-gated-game-functions]
  affects: [DegenerusAdmin, DegenerusGame, IDegenerusGame]
tech_stack:
  added: []
  patterns: [vault-owner-direct-access-control]
key_files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/DegenerusAdmin.sol
    - contracts/interfaces/IDegenerusGame.sol
decisions:
  - Vault owner check via IDegenerusVaultOwnerGame local interface (same pattern as AdvanceModule)
metrics:
  duration: 2min
  completed: 2026-03-30T03:42:41Z
---

# Phase 146 Plan 02: Remove Admin Forwarding Wrappers Summary

Removed 2 DegenerusAdmin forwarding wrappers (stakeGameEthToStEth, setLootboxRngThreshold) and replaced ADMIN access control with vault-owner checks directly on DegenerusGame functions.

## What Changed

### DegenerusGame.sol
- Added `IDegenerusVaultOwnerGame` local interface and `vault` constant for DGVE ownership check
- `adminStakeEthForStEth`: access control changed from `msg.sender != ContractAddresses.ADMIN` to `!vault.isVaultOwner(msg.sender)`
- `setLootboxRngThreshold`: same access control change
- NatSpec updated on both functions to reflect "vault owner only" access

### DegenerusAdmin.sol
- Deleted `stakeGameEthToStEth` forwarding wrapper (4 lines + NatSpec)
- Deleted `setLootboxRngThreshold` forwarding wrapper (4 lines + NatSpec)
- Removed `adminStakeEthForStEth` and `setLootboxRngThreshold` from local `IDegenerusGameAdmin` interface

### IDegenerusGame.sol
- Removed `setLootboxRngThreshold(uint256)` function declaration and NatSpec

## Verification

- `grep isVaultOwner contracts/DegenerusGame.sol` shows 3 hits (interface + 2 usage sites)
- `grep -c "stakeGameEthToStEth\|function setLootboxRngThreshold" contracts/DegenerusAdmin.sol` returns 0
- `grep -c setLootboxRngThreshold contracts/interfaces/IDegenerusGame.sol` returns 0
- `npx hardhat compile` exits 0 (62 files compiled successfully)

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | e6a1ae06 | Remove Admin forwarding wrappers, gate Game functions by vault owner |

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED
