---
phase: 277-event-surface-unification-sentinel-retirement-evt-uni
plan: 01
subsystem: lootbox-jackpot-event-surface
tags: [events, sentinel-retirement, refactor, gas]
status: COMPLETE
requirements-completed: [EVT-UNI-01, EVT-UNI-02, EVT-UNI-03, EVT-UNI-04, EVT-UNI-05, EVT-UNI-06, EVT-UNI-07, EVT-UNI-08]
requires:
  - Phase 275 hoisted Bernoulli locals (D-275-HOIST-01)
  - Phase 276 _jackpotTicketRoll Bernoulli math (D-276-EVT-STATUSQUO-01)
provides:
  - LootBoxOpened restructured (real lootboxIndex + day + roundedUp; fields kept uint256 wide)
  - BurnieLootOpen gains roundedUp
  - JackpotTicketWin gains non-indexed roundedUp
  - LootboxTicketRoll event deleted (interface + contract)
  - index != type(uint48).max sentinel retired in _resolveLootboxCommon
  - auto-resolve callers silent (index=0, emitLootboxEvent=false)
affects:
  - off-chain indexers subscribing to LootBoxOpened / BurnieLootOpen / JackpotTicketWin (topic-hash break, accepted per D-40N-EVT-BREAK-01)
tech-stack:
  added: []
  patterns:
    - Bernoulli roundedUp capture mirrored Lootbox -> Jackpot
    - private helper extraction to resolve viaIR stack-too-deep
key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameLootboxModule.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
decisions:
  - D-277-EVT-WIDE-01 honored — LootBoxOpened amount/burnie/bonusBurnie stay uint256 wei
  - D-277-NO-PREROLL-01 honored — no preRollTickets field added
  - D-277-ROUNDEDUP-01 honored — roundedUp is the only new field on all 3 events
  - D-277-AR-SILENT-01 honored — auto-resolve callers flipped emitLootboxEvent true->false
  - D-277-CONSOLATION-GATE-01 honored — manual cold-bust consolation moved under emitLootboxEvent gate
  - D-277-AR-INDEX-01 honored — auto-resolve callers pass index=0
  - lootboxIndex + player are the two indexed topics on LootBoxOpened; day is a non-indexed data field
metrics:
  duration: ~1h
  completed: 2026-05-14
---

# Phase 277 Plan 01: Event Surface Unification + Sentinel Retirement Summary

Consolidated the v39.0-additive `LootboxTicketRoll` event into the existing per-action
events, fixed the `LootBoxOpened` `index`/`day` mislabel, added a `roundedUp` bool to
`LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`, and retired the
`index != type(uint48).max` behavior-gating sentinel in `_resolveLootboxCommon` — with
auto-resolve callers now fully silent on the advanceGame chain.

## What Was Built

### Task 1 — Lootbox module + interface (EVT-UNI-01/-02/-03/-05/-06/-08)
- **Deleted `LootboxTicketRoll`** from both `IDegenerusGameModules.sol`
  (`IDegenerusGameLootboxModule` interface block) and `DegenerusGameLootboxModule.sol`
  (event def + NatSpec). Zero `LootboxTicketRoll` references remain in `contracts/`.
- **Restructured `LootBoxOpened`**: the mislabeled `uint32 indexed index` (which the emit
  fed `day` into) is replaced by a real `uint48 indexed lootboxIndex` plus a separate
  non-indexed `uint32 day` field. Added `bool roundedUp` as the final non-indexed field.
  `amount` / `burnie` / `bonusBurnie` stay `uint256` wei (D-277-EVT-WIDE-01 — no narrowing,
  no `/ 1 ether`). Topic count stays at 2 (`player` + `lootboxIndex`).
- **`BurnieLootOpen`** gains a single `bool roundedUp` field; all pre-existing fields
  unchanged. `_resolveLootboxCommon` return tuple extended to 4 elements ending in
  `bool roundedUp`; `openBurnieLootBox` destructures `( , , , bool roundedUp)` and threads
  it to the emit.
- **Sentinel retired**: the `if (index != type(uint48).max) { ... } else { ... }` construct
  in the `if (futureTickets != 0)` block is gone. Replaced with an unconditional
  `_queueTickets(player, targetLevel, whole, false)` (early-returns on `whole == 0`) plus
  the manual cold-bust WWXRP consolation moved under the existing `if (emitLootboxEvent)`
  gate. No dead branches remain.
- **Auto-resolve callers silenced**: `resolveLootboxDirect` and `resolveRedemptionLootbox`
  now pass `index = 0` (was `type(uint48).max`) and `emitLootboxEvent = false` (was `true`).
  After the flip, `emitLootboxEvent` is `true` for exactly the two manual callers and
  `false` for exactly the two auto-resolve callers — 1:1 with the prior sentinel split.
- NatSpec for `@param index`, `@param emitLootboxEvent`, the `@return` set, and both event
  doc blocks updated to describe current behavior (no change-history language).

### Task 2 — Jackpot module (EVT-UNI-04)
- `JackpotTicketWin` gains `bool roundedUp` as the final, **non-indexed** field (`traitId`
  already occupies the 3rd indexed slot). Event still has exactly 3 indexed params.
- `_jackpotTicketRoll` declares `bool roundedUp = false;` before the Bernoulli predicate and
  sets `roundedUp = true;` inside the `whole += 1` branch — mirrors the LootboxModule capture
  pattern byte-for-byte. Bernoulli math (`entropy >> 200`, `% uint16(TICKET_SCALE)`,
  `< uint16(frac)`) unchanged.
- All 3 `emit JackpotTicketWin` sites supply the 7th arg: `_jackpotTicketRoll` passes the
  captured local; the two trait-matched paths (bonus-trait, near/far-future coin) pass
  literal `false` (zero fractional part by construction).

## Gas / Bytecode Worst-Case Derivation (EVT-UNI-07)

Theoretical worst case derived **first**, per `feedback_gas_worst_case.md`:

- **Manual `openLootBox` path**: deletes one `LootboxTicketRoll` LOG3
  (375 + 2·375 topic + 4 data words ≈ 1125 + 128 = ~1253 gas), adds one `roundedUp` data
  word to `LootBoxOpened` (+32 bytes ≈ +256 gas). `day` moves from the (already-emitted)
  mislabeled `index` slot to its own data word — net-neutral on payload count. **Expected:
  net gas-NEGATIVE (~-1000 gas/manual open on the ticket path).**
- **advanceGame-chain auto-resolve path** (`resolveLootboxDirect` via
  `processCoinflipPayouts`): `emitLootboxEvent` flips `true`→`false`, so a full
  `LootBoxOpened` LOG3 is **removed** from the block-gas-sensitive chain; the sentinel
  branch collapses to a straight-line `_queueTickets`. **Expected: net gas-NEGATIVE.**
- **`JackpotTicketWin` on the advanceGame chain** (`_jackpotTicketRoll`): +1 non-indexed
  data word (+32 bytes ≈ +256 gas). Genuinely new information, unavoidable, minimal.

**Measured deployed-bytecode delta (HEAD baseline `856d3520` vs working tree, viaIR + runs=50):**

| Module | HEAD | Phase 277 | Delta |
|--------|------|-----------|-------|
| `DegenerusGameLootboxModule` | 18655 bytes | 18128 bytes | **-527 bytes** |
| `DegenerusGameJackpotModule` | 23848 bytes | 23871 bytes | **+23 bytes** |

The Lootbox bytecode shrinks despite two new helper functions because the
`LootboxTicketRoll` event def + emit + the dual-branch sentinel construct are deleted. The
Jackpot delta (+23 bytes) is the `roundedUp` capture + 7th emit arg across 3 sites.

`openLootBox` gas test: `test/gas/LootboxOpenGas.test.js` is a HEAD-only ref-pinned
regression test whose REF constants are owned by the Phase 277 test wave (plan 277-02).
No standalone gas test was run for this contract-only plan; the analytical worst-case
derivation above is the load-bearing acceptance per `feedback_gas_worst_case.md`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] viaIR stack-too-deep in `_resolveLootboxCommon`**
- **Found during:** Task 1, first compile after adding the 4th named return `roundedUp`.
- **Issue:** Adding `bool roundedUp` as a 4th named return to the already-14-parameter
  `_resolveLootboxCommon` pushed the function over the viaIR stack limit
  (`YulException: Cannot swap ... too deep in the stack`). The function compiled fine at
  HEAD with 3 named returns.
- **Fix:** Extracted two `private` helper functions from `_resolveLootboxCommon` body —
  both are mechanical, behavior-preserving refactors:
  - `_lootboxBoonBudget(uint256 amount) private pure returns (uint256)` — the boon-budget
    BPS/cap arithmetic, previously an inline local. Now computed where needed (once for
    `mainAmount`, once inside the `allowBoons` block) instead of held in a long-lived local.
  - `_accumulateLootboxRolls(...) private returns (uint256, uint256, uint32)` — the one-or-two
    `_resolveLootboxRoll` invocations + presale/non-presale BURNIE accumulation + scaled
    ticket sum. The tuple re-assignment temporaries were a primary stack-pressure source.
  The split-amount computation was also wrapped in a `{ }` block scope so `mainAmount` frees.
  No behavior change: the same `_resolveLootboxRoll` calls run with the same args/seeds, the
  same accumulation logic applies, the same `boonBudget` value is computed.
- **Files modified:** `contracts/modules/DegenerusGameLootboxModule.sol`
- **Commit:** `02fb7085` (part of the batched contract commit)

## Threat Flags

None. No new network endpoints, auth paths, file-access patterns, or schema/storage
changes. Storage layout is byte-identical to the v39 baseline `6a7455d1` — only event
signatures and private function bodies changed. The two new functions are `private` and
add no entry points.

## Known Stubs

None.

## Task Commits

1. **Tasks 1 + 2 (batched contract diff)** — `02fb7085` (feat) — `feat(277): event surface
   unification + sentinel retirement [EVT-UNI-01..08]`. The user reviewed the full batched
   3-file diff and explicitly approved before the commit was made, per project policy
   (`feedback_no_contract_commits.md`, `feedback_batch_contract_approval.md`,
   `feedback_never_preapprove_contracts.md`). Three files staged:
   `DegenerusGameLootboxModule.sol`, `DegenerusGameJackpotModule.sol`,
   `IDegenerusGameModules.sol`. `contracts/ContractAddresses.sol` (pre-existing unrelated
   change) was deliberately NOT staged. Commit body carries the gas/bytecode delta report
   and the D-40N-EVT-BREAK-01 topic-hash note. Not pushed (future push is a separate user
   gate per `feedback_manual_review_before_push.md`).

**Plan metadata:** committed separately with the SUMMARY.md + STATE.md + ROADMAP.md updates.

## Checkpoint Status

Task 3 was a `checkpoint:human-verify gate="blocking"`. The batched 3-file diff was
presented to the user, the user reviewed it and explicitly typed "approved", and the
commit `02fb7085` was then created. Checkpoint resolved.

## Verification

- `npx hardhat compile` succeeds (8 files compiled).
- `grep -rn "LootboxTicketRoll" contracts/` returns nothing.
- `grep -c "index != type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol` = 0.
- `grep -c "type(uint48).max" contracts/modules/DegenerusGameLootboxModule.sol` = 0.
- `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` each contain `roundedUp`; none
  contain `preRollTickets`.
- `_resolveLootboxCommon` return tuple has 4 elements ending in `bool roundedUp`.
- Both auto-resolve callers pass `0` as the 3rd arg and `false` as the 11th arg.
- Manual cold-bust consolation appears exactly once, inside the `if (emitLootboxEvent)` gate.
- `grep -c "emit JackpotTicketWin"` = 3; all three pass the 7th arg.
- `git diff --stat` for the 3 plan files shows only event/body changes (plus the two new
  private helpers).

## Self-Check: PASSED

- SUMMARY.md present at the plan directory path.
- All contract edits verified present via grep + successful compile (`Nothing to compile`
  — artifacts current).
- Commit `02fb7085` verified present in `git log`; `git diff --stat HEAD~1 HEAD` shows
  exactly the 3 plan files (`IDegenerusGameModules.sol`, `DegenerusGameJackpotModule.sol`,
  `DegenerusGameLootboxModule.sol`) and no others — `ContractAddresses.sol` correctly
  excluded.
