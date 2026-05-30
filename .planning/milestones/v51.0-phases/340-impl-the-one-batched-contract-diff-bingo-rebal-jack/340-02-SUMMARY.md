---
phase: 340-impl-the-one-batched-contract-diff-bingo-rebal-jack
plan: 02
subsystem: contracts/bingo-wiring
tags: [contracts, bingo, entrypoint, delegatecall, interface, contract-boundary]
requires:
  - "340-01: GAME_BINGO_MODULE constant, DegenerusGameBingoModule.claimBingo module body, bingo storage"
provides:
  - "DegenerusGame.claimBingo external delegatecall entrypoint (player-facing surface)"
  - "IDegenerusGameBingoModule selector interface (delegatecall encode source)"
  - "IDegenerusGame.claimBingo facade signature"
affects:
  - contracts/DegenerusGame.sol
  - contracts/interfaces/IDegenerusGameModules.sol
  - contracts/interfaces/IDegenerusGame.sol
tech-stack:
  added: []
  patterns:
    - "delegatecall dispatch mirroring wireVrf (void return, _revertDelegate on failure)"
key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/interfaces/IDegenerusGameModules.sol
    - contracts/interfaces/IDegenerusGame.sol
decisions:
  - "Signature is claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) at ALL wiring sites — matches the live module body (mid-execution USER override of the plan's uint256 level). Selector consistency = claimBingo(uint24,uint8,uint32[8]) across entrypoint + IDegenerusGameBingoModule + module body is the load-bearing requirement."
  - "Mirrored wireVrf (:303-318) void-return dispatch shape, NOT advanceGame (which abi.decodes a return). claimBingo returns nothing."
  - "Reused existing _revertDelegate (:1026); did NOT re-author it."
metrics:
  duration: ~4m
  completed: 2026-05-28
---

# Phase 340 Plan 02: claimBingo Consumer Wiring Summary

Wired the player-facing `claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots)` surface — the `DegenerusGame` external delegatecall entrypoint dispatching to `GAME_BINGO_MODULE`, plus the `IDegenerusGameBingoModule` selector interface and the `IDegenerusGame` facade signature — completing the BINGO-01 surface begun by the 340-01 producers, held uncommitted as part of the BATCH-02 single batched diff.

## What Was Built

### Task 1 — IDegenerusGameBingoModule selector interface
`contracts/interfaces/IDegenerusGameModules.sol`: appended a new `interface IDegenerusGameBingoModule` after the last existing module interface (`IDegenerusGameDegeneretteModule`), declaring `function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) external;` with NatSpec matching the file's per-function style. This is the selector the `DegenerusGame.claimBingo` delegatecall encodes. No existing interface modified.

### Task 2 — DegenerusGame.claimBingo entrypoint + import
`contracts/DegenerusGame.sol`:
- Added `IDegenerusGameBingoModule` to the `IDegenerusGameModules.sol` import group (:35-45).
- Authored `function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) external` placed immediately after `wireVrf`, mirroring `wireVrf`'s void-return dispatch exactly: `ContractAddresses.GAME_BINGO_MODULE.delegatecall(abi.encodeWithSelector(IDegenerusGameBingoModule.claimBingo.selector, level, symbol, slots)); if (!ok) _revertDelegate(data);`. No return value (matches `wireVrf`, not `advanceGame`). Reused the existing `_revertDelegate` (:1026) — not re-authored.

### Task 3 — IDegenerusGame facade signature
`contracts/interfaces/IDegenerusGame.sol`: appended `function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) external;` after `purchaseCoin` (the player-entrypoint group) with NatSpec in the file's style. No existing signature modified.

## Signature override (load-bearing)

The 340-02 PLAN text specified `uint256 level`. This was SUPERSEDED mid-execution by a USER directive applied to the bingo module: the level guard was removed (the 8-color ownership check self-gates) and the module signature is now `uint24 level`. All three wiring sites authored here therefore use `uint24 level` to match the live module selector. Verified ground truth: `contracts/modules/DegenerusGameBingoModule.sol:89` declares `function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) external`.

Selector consistency confirmed across all four sites — `claimBingo(uint24,uint8,uint32[8])`:
- module body (DegenerusGameBingoModule.sol:89) — ground truth
- IDegenerusGameBingoModule (the encode-selector source)
- DegenerusGame.claimBingo (the entrypoint)
- IDegenerusGame.claimBingo (the facade)

## Verification

Adapted the plan's grep gates from `uint256 level` to `uint24 level` (selector consistency is the real gate; the `uint256` greps were superseded). All passed:
- `interface IDegenerusGameBingoModule` count == 1; interface `claimBingo(uint24…)` count == 1.
- `DegenerusGame.claimBingo` count == 1; `GAME_BINGO_MODULE` present (2 occurrences: import-adjacent context + the delegatecall); `IDegenerusGameBingoModule.claimBingo.selector` count == 1; `IDegenerusGameBingoModule` referenced (import + selector = 2).
- `IDegenerusGame.claimBingo(uint24…)` count == 1.
- `_revertDelegate` still declared exactly once (reused, not re-authored).

`forge build` clean is owned by Plan 340-04 (compile-time selector/signature consistency check). No build/test run here per the contract-boundary constraints (340-04 owns the compile-only IMPL bar).

## Deviations from Plan

### Auto-applied (signature override, USER-directed pre-execution)

**1. [Rule 1 — superseded plan signature] uint256 level → uint24 level at all 3 wiring sites**
- **Found during:** pre-execution verification of the live module signature.
- **Issue:** the plan text/must_haves specify `uint256 level`, but the live module body (340-01, USER-amended) is `uint24 level`. Encoding a `uint256` selector would mis-dispatch / fail to compile.
- **Fix:** authored all three sites with `uint24 level` to match the module selector exactly.
- **Files modified:** contracts/DegenerusGame.sol, contracts/interfaces/IDegenerusGameModules.sol, contracts/interfaces/IDegenerusGame.sol.
- **Commit:** none — held uncommitted in the BATCH-02 working tree.

## Contract-boundary handling (BATCH-02 / autonomous:false)

Per the USER-LOCKED contract-boundary constraints: NO `contracts/` file was committed. All edits applied to the working tree only, held for the orchestrator's single batched `feat(340)` commit post-approval. Pre-existing uncommitted 340-01 (producers) and 340-03 (REBAL+JACK) contract edits were left untouched. STATE.md / ROADMAP.md are orchestrator-owned and were not modified by this plan. Only this SUMMARY doc is committed.

## Known Stubs

None — pure dispatch wiring; no placeholder data or unwired surfaces.

## Threat Flags

None — no new trust-boundary surface beyond the plan's threat register (T-340-08/09/10 cover the delegatecall trust model, silent-revert bubbling, and ABI/selector mismatch).

## Self-Check: PASSED

- contracts/DegenerusGame.sol — claimBingo(uint24…) entrypoint + import: FOUND
- contracts/interfaces/IDegenerusGameModules.sol — interface IDegenerusGameBingoModule + claimBingo(uint24…): FOUND
- contracts/interfaces/IDegenerusGame.sol — claimBingo(uint24…) facade: FOUND
- Selector consistency claimBingo(uint24,uint8,uint32[8]) across module body + iface + entrypoint + facade: FOUND
- 340-02-SUMMARY.md committed (docs only, ZERO contracts/): FOUND (ecf3bdf9)
