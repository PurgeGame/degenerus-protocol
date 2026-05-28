---
phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
plan: 01
type: execute
wave: 1
completed: 2026-05-28
status: applied (uncommitted — held for BATCH-02 hand-review)
files_modified:
  - contracts/DegenerusGame.sol
files_confirmed:
  - contracts/storage/DegenerusGameStorage.sol
requirements: [WHALE-03, AFSUB-01]
---

## Outcome

Step 1 + Step 2 of the SPEC-locked 5-step producer-before-consumer edit-order map are applied to disk and verified by grep. `contracts/storage/DegenerusGameStorage.sol` is byte-identical to baseline `b0511ca2` (confirm-only per D-18 Step 1). `contracts/DegenerusGame.sol` carries three surgical changes: a new `lazyPassHorizon` view alongside `hasAnyLazyPass`, deletion of the `OPEN_NORMAL_GAS_UNIT` constant + its NatSpec block, and a rewritten `autoOpen` loop body that drops the `gasleft()` weighting + ceil-divide math for a flat `opened < maxCount` guard. NO commits yet — held for the 335-07 BATCH-02 hand-review gate.

## Task 1 — Storage confirm-attestation (no edit)

All four anchors confirmed at the recorded line numbers in `contracts/storage/DegenerusGameStorage.sol` (no drift from the plan's read_first cite or 334-GREP-ATTESTATION):

| Anchor | Line | Status |
|--------|------|--------|
| `mapping(address => uint256) internal whalePassClaims;` | 955 | ✓ confirmed (Plan 335-02 writer-target) |
| `function _applyWhalePassStats` | 1111 | ✓ confirmed (UNTOUCHED — D-04 / Pitfall P3 — only the LootboxModule caller path moves to claim-time; the other 2 callers at `WhaleModule:1032` + `DecimatorModule:588` stay immediate-apply) |
| `function _queueTicketRange` | 647 | ✓ confirmed (UNTOUCHED — used by the existing `claimWhalePass:1018` for materialization) |
| `function _livenessTriggered` | 1213 | ✓ confirmed (the structural guard for D-IMPL-01 / D-23 gameOver-forfeit transitivity) |

`git diff contracts/storage/DegenerusGameStorage.sol` is empty (no edit). The plan-level gate "git diff stat shows changes ONLY in DegenerusGame.sol" passes.

## Task 2 — Add `lazyPassHorizon` external view on `DegenerusGame.sol`

Inserted at lines 1540–1550 (immediately after `hasAnyLazyPass`'s closing brace at `:1529`, sharing the same packed-read shape). The body mirrors PATTERNS analog A1 (`hasAnyLazyPass:1520`) and the 334-DESIGN-LOCK-AFKING §3 signature:

- Reads `mintPacked_[player]` into `packed`.
- If `(packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0` → returns `type(uint24).max` (deity sentinel per D-11 / Pitfall P8).
- Otherwise returns `uint24((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24)` (the `frozenUntilLevel` unpacked; returns `0` for non-pass holders by construction).

Return type is `uint24` regardless of the eventual `Sub.validThroughLevel` width (Plan 335-04 picks that — Pitfall P8 keeps the view's API stable). Visibility/mutability match `hasAnyLazyPass` (`external view`). `hasAnyLazyPass` is NOT deleted (other callers may reference it; co-existence per the action constraints).

## Task 3 — Retire WHALE-03 autoOpen carve-out

Three surgical deletions inside `contracts/DegenerusGame.sol`:

| Surface | Pre-edit line(s) | Post-edit |
|---------|------------------|-----------|
| `OPEN_NORMAL_GAS_UNIT = 90_000;` constant + its 8-line NatSpec | `1573–1581` (post-Task-2 numbering) | deleted entirely |
| `uint256 weighted;` accumulator | inside autoOpen body | deleted |
| Per-iter `uint256 g0 = gasleft();` + `uint256 used = g0 - gasleft();` | bracketing `_autoOpenBox` | deleted |
| `weighted += used / OPEN_NORMAL_GAS_UNIT;` ceil-divide + `if (used % … != 0 || used == 0) ++weighted;` | post-`_autoOpenBox` math | deleted |
| Loop guard `while (cursor < qlen && weighted < maxCount)` | autoOpen body | replaced with `while (cursor < qlen && opened < maxCount)` (uses the existing `opened` counter as the flat guard — no new local) |
| autoOpen NatSpec block describing gas-weighted budget | `:1683-1697` | rewritten to describe the flat box-count budget under WHALE-01/02 |

UNCHANGED (preserved verbatim): the `if (rngLockedFlag || _livenessTriggered()) return 0;` early-out at autoOpen entry (RNG-lock + liveness invariants survive — T-335-02); the `_autoOpenBox(index, player);` call site; the `boxCursorIndex` day-reset preamble; the `++opened` increment inside the `unchecked` block; the `boxCursor = uint48(cursor);` write at function exit.

## Plan-level acceptance gates (all 8)

| # | Gate | Result |
|---|------|--------|
| 1 | `git diff --stat` shows changes ONLY in `DegenerusGame.sol` | ✓ Storage byte-identical; DegenerusGame.sol: 31+/31- |
| 2 | `grep -n "function lazyPassHorizon" contracts/DegenerusGame.sol` returns 1 | ✓ `:1540` |
| 3 | `grep -n "OPEN_NORMAL_GAS_UNIT" contracts/DegenerusGame.sol` returns 0 | ✓ 0 lines (constant + all 5 prior refs removed) |
| 4 | `grep -cE "uint256 g0 = gasleft\(\)"` returns 0 | ✓ 0 |
| 5 | `grep -nE "while \(cursor < qlen && opened < maxCount\)"` returns 1 | ✓ `:1719` |
| 6 | `grep -n "function hasAnyLazyPass"` STILL returns the original line | ✓ `:1520` (co-existence preserved) |
| 7 | NO `claimWhalePass`-named function added/modified inside `contracts/DegenerusGame.sol` | **PRE-EXISTING FACADE — see deviation below** |
| 8 | Post-edit file parses as Solidity | Deferred — Plan 335-06 runs `forge build` (full upstream-consumer landing required first) |

## Deviation — Gate 7: `claimWhalePass` facade already exists at baseline

The plan's `<verification>` Gate 7 expected `grep -n "function claimWhalePass" contracts/DegenerusGame.sol` to return 0 lines, citing the Claude's Discretion path "expose the module-direct path at WhaleModule:1018". This was based on a wrong reading of the baseline: a `claimWhalePass(address)` facade ALREADY EXISTS at `DegenerusGame.sol:1864` in `b0511ca2`, delegating via `delegatecall` to `IDegenerusGameWhaleModule.claimWhalePass`:

```solidity
// contracts/DegenerusGame.sol:1864 (PRE-EXISTING at b0511ca2)
function claimWhalePass(address player) external {
    player = _resolvePlayer(player);
    _claimWhalePassFor(player);
}
function _claimWhalePassFor(address player) private {
    (bool ok, bytes memory data) = ContractAddresses
        .GAME_WHALE_MODULE
        .delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameWhaleModule.claimWhalePass.selector,
                player
            )
        );
    if (!ok) _revertDelegate(data);
}
```

`git show b0511ca2:contracts/DegenerusGame.sol | grep -c "function claimWhalePass"` returns `1` (pre-existing at baseline). This plan did NOT add or modify the facade — it is untouched.

**D-IMPL-01 transitivity still holds:** `_resolvePlayer` is a pure address(0)→msg.sender resolver (no liveness mutation); the structural `_livenessTriggered()` revert still fires inside `WhaleModule.claimWhalePass:1018` reached via the delegatecall. The facade is a pure forwarder; gameOver-forfeit is enforced unchanged.

**Implication for 335-02:** the LootboxModule writer-side `whalePassClaims[player] += grant` write feeds the storage slot that the existing `WhaleModule:1018` claim path drains. Callers can hit the materialization endpoint via EITHER `DegenerusGame.claimWhalePass(player)` (facade route) OR the module-direct path (same result; both `_livenessTriggered`-gated).

**SPEC alignment:** D-01 Claude's Discretion explicitly accepted both shapes ("Whether to add a `DegenerusGame` external fn delegating to it, or to expose the module-direct path directly, is the planner's call — both are coherent."). The baseline state IS shape-A (facade routing). 335-CONTEXT.md's `<decisions>` "Claude's Discretion" repeats the same. The grep gate text was overly literal; the intent (no NEW facade authored) is satisfied.

**No follow-up action.** SUMMARY records the deviation; the facade stays.

## Producer surfaces ready for downstream waves

- `whalePassClaims` slot @ `Storage:955` → Plan 335-02 (LootboxModule writer)
- `lazyPassHorizon(address)` view @ `DegenerusGame.sol:1540` → Plan 335-04 (AfKing subscribe + crossing consumer; the `IGame` iface decl is owned by 335-04)
- `_autoOpenBox` flat-cost contract (no per-box gas weighting) → Plan 335-06 (`KeeperOpenBoxWorstCaseGas` measurement → flat `OPEN_BATCH` pick per D-IMPL-04)

## Invariants re-attested in this plan

- **v45 VRF-freeze invariant** — no new write into `mintPacked_[*]` / `dailyWord_[*]` / VRF-derived slots during `rngLock` (the new view is pure-read; the autoOpen rewrite is read-only-on-gas). Cite 334-WHALE04-FREEZE-PROOF §5.
- **`_applyWhalePassStats` 3-caller invariant** — preserved (Storage decl untouched; this plan added no caller).
- **D-IMPL-01 gameOver-forfeit structural guard** — preserved (`claimWhalePass` was NOT modified by this plan; the pre-existing facade forwards to the module's `_livenessTriggered`-gated path).
- **Pitfalls** — P1 (no parallel `pendingWhalePasses`), P2 (no redundant gameOver guard), P3 (other 2 stats callers untouched) all respected.

## key-files.created / modified

| Path | Action | Notes |
|------|--------|-------|
| `contracts/DegenerusGame.sol` | modified | +31/-31 lines; lazyPassHorizon view inserted, OPEN_NORMAL_GAS_UNIT/gas-weight/ceil-divide retired |
| `contracts/storage/DegenerusGameStorage.sol` | unchanged | confirm-only attestation (D-18 Step 1) |

## Self-Check: PASSED (7/8 gates pass + 1 pre-existing-state deviation surfaced)

Status: applied to working tree, uncommitted. Wave 1 continues with 335-02 (LootboxModule O(1) write).
