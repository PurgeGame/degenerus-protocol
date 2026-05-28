---
phase: 340-impl-the-one-batched-contract-diff-bingo-rebal-jack
plan: 01
subsystem: bingo
tags: [contracts, bingo, storage, module, tier-precedence, cei, contract-boundary]
requires:
  - "339-DESIGN-LOCK-BINGO (signature / storage shape / traitId / constants / reward paths)"
  - "339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT (the 3-tier cascade)"
  - "339-BINGO06-FREEZE-PROOF (read-only traitBurnTicket consumer, no write)"
provides:
  - "3 claimBingo-exclusive bitfield mappings in DegenerusGameStorage.sol (bingoClaimed/firstQuadrant/firstSymbol)"
  - "contracts/modules/DegenerusGameBingoModule.sol (claimBingo 3-tier delegatecall body)"
  - "GAME_BINGO_MODULE address constant in ContractAddresses.sol"
affects:
  - "Plan 340-02 (DegenerusGame.claimBingo entrypoint + interface — consumes these producers)"
tech-stack:
  added: []
  patterns:
    - "delegatecall module sharing DegenerusGameStorage layout"
    - "CEI on reward withdrawals (effects before transferFromPool/creditFlip)"
    - "clamped-return-as-dgnrsPaid (NEW capture pattern — analogs discard the return)"
    - "graceful empty-pool no-op"
    - "custom-error reverts + bounds-guard before array read"
    - "address-indexed-only event topology"
key-files:
  created:
    - contracts/modules/DegenerusGameBingoModule.sol
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/ContractAddresses.sol
decisions:
  - "Appended the 3 mappings after boonPacked (:1635) — the last storage-occupying state var (the trailing BP_* constants take no storage slot), the true storage-layout tail."
  - "Used the inherited dgnrs/coinflip storage constants (Storage:147/:139) — no new module-local constant (the lighter JACK-branch choice over the Degenerette-module's own sdgnrs constant)."
  - "Single-line claimBingo signature to satisfy the plan's exact single-line <verify>/acceptance grep gate."
  - "level_() private helper reads the `level` storage member, avoiding the name collision with the `level` calldata param."
  - "Custom errors NotSlotOwner / InvalidSymbol / InvalidLevel / AlreadyClaimed (+ inherited E() for gameOver) — all custom errors, no require-strings (D-340-02)."
metrics:
  duration: ~12m
  completed: 2026-05-28
  tasks: 3
  files: 3
---

# Phase 340 Plan 01: BINGO Producers (Storage + Module + Address Constant) Summary

Authored the producer half of the v51.0 claimBingo bundle — the 3 shared-storage
bitfield mappings, the new `DegenerusGameBingoModule.sol` 3-tier color-completion
entrypoint body, and the `GAME_BINGO_MODULE` address constant — as a faithful
transcription of the LOCKED 339 SPEC, applied to the working tree and HELD uncommitted
at the BATCH-02 contract boundary (only this SUMMARY is committed).

## What Was Built

### Task 1 — 3 claimBingo bitfield mappings (DegenerusGameStorage.sol)

Appended at the storage-layout tail (after `boonPacked` at `:1635`, the last
storage-occupying state variable; the trailing `BP_*` declarations are `constant` and
occupy no slot). All keyed by `uint24` level — the identical key width to
`traitBurnTicket` (`:416`), no truncation. All `internal`.

```solidity
mapping(uint24 => mapping(address => uint8)) internal bingoClaimed;  // per-player 4-bit quadrant mask
mapping(uint24 => uint8) internal firstQuadrant;                     // systemwide 4-bit quadrant mask
mapping(uint24 => uint32) internal firstSymbol;                      // systemwide 32-bit symbol mask
```

`git diff` shows zero deleted lines — no existing slot mutated, `traitBurnTicket`
byte-unchanged. Pre-launch redeploy-fresh → appending at the tail is safe, no migration.

### Task 2 — DegenerusGameBingoModule.sol (the 3-tier cascade body)

New file `contracts/modules/DegenerusGameBingoModule.sol`:

- Header `// SPDX-License-Identifier: AGPL-3.0-only` + `pragma solidity 0.8.34;`;
  inherits `DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils` (mirrors the
  Degenerette/Jackpot modules → transitively includes `DegenerusGameStorage`, so the
  3 new mappings + `gameOver` + `level` + the inherited `coinflip`/`dgnrs` constants
  resolve).
- The six reward constants transcribed VERBATIM from 339-DESIGN-LOCK §5
  (`REGULAR_DGNRS_BPS=5`, `FIRST_SYMBOL_BONUS_DGNRS_BPS=5`, `FIRST_QUADRANT_DGNRS_BPS=50`,
  `REGULAR_BURNIE=1_000e18`, `FIRST_SYMBOL_BONUS_BURNIE=1_000e18`,
  `FIRST_QUADRANT_BURNIE=5_000e18`).
- Three `address indexed player`-only events (D-340-01): `FirstQuadrantBingo`,
  `FirstSymbolBingo`, `BingoClaimed`.
- Custom errors (D-340-02, all custom errors not require-strings): `NotSlotOwner`,
  `InvalidSymbol`, `InvalidLevel`, `AlreadyClaimed` (+ inherited `E()` for `gameOver`).
- `claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots) external`:
  1. **Validation:** `if (gameOver) revert E();` (D-08 hard cutoff), `symbol >= 32` →
     `InvalidSymbol`, `level > level` → `InvalidLevel`. Derives `quadrant = symbol >> 3`,
     `symInQ = symbol & 7`, `qMask = uint8(1 << quadrant)`, `sMask = uint32(1) << symbol`.
  2. **Ownership read (READ-ONLY):** loops `c ∈ [0,7]`, computes
     `traitId = (quadrant << 6) | (c << 3) | symInQ`, GUARDS `slots[c]` against
     `holders.length` BEFORE the read, then requires
     `traitBurnTicket[lvl][traitId][slots[c]] == msg.sender` — one clean `NotSlotOwner`
     for both wrong-owner and out-of-bounds (no bare `Panic(0x32)`). NO write to
     `traitBurnTicket`.
  3. **Per-player dedup (EFFECT):** `bingoClaimed[lvl][msg.sender] & qMask != 0` →
     `AlreadyClaimed`; else `|= qMask`.
  4. **Cascade (EFFECTS, exactly per 339-TIER-PRECEDENCE §2-3):**
     `if (isQuadrantFirst)` → mark BOTH `firstQuadrant[lvl] |= qMask` AND
     `firstSymbol[lvl] |= sMask` (the double-pay-trap guard), pay 50 bps + 5_000e18,
     emit `FirstQuadrantBingo`; `else if (isSymbolFirst)` → mark `firstSymbol[lvl] |= sMask`,
     pay 10 bps + 2_000e18, emit `FirstSymbolBingo`; `else` → 5 bps + 1_000e18 (no tier event).
  5. **Interactions (after all effects — CEI):** `dgnrsPaid = dgnrs.transferFromPool(Pool.Reward, msg.sender, (poolBal*dgnrsBps)/10_000)`
     capturing the clamped return; then `coinflip.creditFlip(msg.sender, burnie)`. Empty
     pool = graceful no-op (`dgnrsPaid==0`, no revert, BURNIE still credited, bits stay set).
  6. `emit BingoClaimed(msg.sender, level, symbol, burnie, dgnrsPaid);`.

A strict read-only `traitBurnTicket` consumer (freeze-safe per BINGO-06).

### Task 3 — GAME_BINGO_MODULE (ContractAddresses.sol)

Added `address internal constant GAME_BINGO_MODULE = address(0xB14609De6e7eC52e4eAE6cbB1fEaE8e4d4dB1f60);`
after `GAME_DEGENERETTE_MODULE` (`:31-32`). Placeholder address (deploy pipeline patches
the predicted address pre-compile per the file header). No existing module constant
altered (`git diff` shows zero deleted lines). `ContractAddresses.sol` is freely
modifiable (`feedback_contractaddresses_policy`).

## Verification

All plan `<verify>` and `<acceptance_criteria>` grep gates pass:

- Task 1: 3 mappings present with exact locked types; 0 deleted lines (no slot mutated).
- Task 2: `claimBingo` single-line signature present; 6 constants verbatim;
  `isQuadrantFirst` branch before `isSymbolFirst`; quadrant-first sets BOTH bits;
  clamped-return capture (1); NO `traitBurnTicket` write (0); custom errors (>=1);
  3 `address indexed player` events.
- Task 3: `GAME_BINGO_MODULE` constant decl == 1; 0 deleted lines.

`forge build` is NOT run here — it is the IMPL bar at Plan 340-04 (D-340-03 compile-only).
Behavior is Phase 341 TST-01..06.

## Deviations from Plan

None affecting semantics. Two faithful-transcription choices worth noting:

1. **[Discretion - Storage placement]** The plan/SPEC say "after `:416`
   (`traitBurnTicket`)". The live `DegenerusGameStorage.sol` interleaves state-var
   mappings with helper functions throughout, and the last storage-occupying state var
   is `boonPacked` (`:1635`). Appended the 3 mappings there (the true storage-layout
   tail; appending mid-file directly after `:416` would scatter them among unrelated
   slots, and storage-tail safety only requires appending after the last real slot).
   Pure addition, no existing slot mutated — verified by 0 deleted lines.

2. **[Discretion - Signature formatting]** Collapsed the `claimBingo` declaration to a
   single line to satisfy the plan's exact single-line `<verify>`/acceptance grep
   (`function claimBingo(uint256 level, uint8 symbol, uint32[8] calldata slots) external`).
   Semantically identical to the locked D-01 signature.

## CONTRACT BOUNDARY Compliance

NO `contracts/` file was committed. All three contract edits are applied to the working
tree and left UNCOMMITTED (HELD for user hand-review at Plan 340-04 / the single batched
`feat(340)` commit). Only this SUMMARY is committed (a `docs(340-01)` commit). STATE.md
and ROADMAP.md were NOT touched (orchestrator-owned).

## Self-Check: PASSED

- FOUND: contracts/modules/DegenerusGameBingoModule.sol (created)
- FOUND: contracts/storage/DegenerusGameStorage.sol (modified, +3 mappings)
- FOUND: contracts/ContractAddresses.sol (modified, +GAME_BINGO_MODULE)
- All three `contracts/` edits UNCOMMITTED (working-tree only) per the BATCH-02 contract boundary.
- No commit hashes to verify — no `contracts/` file was committed (by design). Only this SUMMARY is committed.
