# Cross-model robustness review — Degenerus Protocol, frozen submission candidate

You are reviewing a Solidity smart-contract codebase for defensive-engineering robustness before an external audit. Read the CURRENT source under `contracts/` (the working tree is the exact frozen submission candidate, `contracts/` tree `4970ba5b`). Be concrete and source-anchored; cite `file:line`.

## Context

Six prior cross-model review cycles found 0 catastrophe / 0 high-severity issues outstanding. The most recent cycle applied THREE in-cycle fixes to the core game column. THIS review has two jobs:
1. Verify those three fixes did not introduce a regression.
2. A final robustness sweep of the spinal column (`mintFlip` / `purchase` mint chain + the `advanceGame` state machine + the 13 delegatecall modules + the synchronously-called peripherals FLIP / Coinflip / DegenerusVault / sDGNRS / DegenerusAffiliate).

Assume honest admin / governance (a legitimate VRF-coordinator rotation must not be able to brick or corrupt state; key-compromise is out of scope).

## The three fixes to verify (look at the current source, reason about reachable paths)

1. **Mid-day lootbox RNG latch release.** In `contracts/modules/DegenerusGameAdvanceModule.sol`, the mid-day lootbox latch (`LR_MID_DAY` field of the packed lootbox-RNG word) is released on the new-day drain path so a mid-day ticket batch that drains on the new-day path cannot leave the latch permanently set (which previously bricked `requestLootboxRng`). Question: can the latch now be cleared while a mid-day word is still in-flight / undelivered, producing a double-finalize, a wrong-index binding, or a skipped/duplicated ticket batch? Trace the latch set/clear across the day boundary.

2. **Direct-call guard on payable delegatecall-only entrypoints.** Four payable entrypoints meant to run only via `delegatecall` from the Game (three Boon dispatches + `resolveLootboxDirect`) now guard with `require(address(this) == GAME)` so a direct external call reverts instead of trapping `msg.value` against the module's own (empty) storage. Question: does the guard admit every legitimate delegatecall path and block only direct calls? Is any analogous payable delegatecall-only entrypoint missing the guard? Is there any legitimate path where `address(this) == GAME` is false?

3. **Afking subscriber-evict gas retune (constants only).** Gas-model weights in the afking subscriber-eviction batching were retuned (eviction weight and per-chunk budget raised) so the all-evict worst-case chunk stays under the 16.7M block-gas ceiling. Question: constants-only — is there a reachable worst-case chunk that can still exceed 16.7M, or a retune that under-fills a chunk such that a required batch cannot make progress (a liveness brick)?

## What to report

Identify any reachable transaction on the frozen spine that can (a) permanently brick the state machine (no further `advanceGame` / terminal finalization / VRF fulfillment possible), (b) corrupt packed storage or accounting, or (c) break ETH/backing solvency — with special attention to regressions from the three fixes above. For each finding give: the exact `file:line`, the reachable path / preconditions, a severity (CATASTROPHE / HIGH / MEDIUM / LOW / INFO), and the reasoning. If you find nothing, state the strongest hypothesis you tested per area and why the source defeats it. Do not pad with style or gas-micro-optimization notes — robustness only.
