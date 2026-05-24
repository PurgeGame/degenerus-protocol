---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 03b
subsystem: contracts
tags: [solidity, do-work-crank, box-cursor, vrf-orphan-index, cross-plan-seam, producer-wiring]

# Dependency graph
requires:
  - phase: 317-03
    provides: "onlySelf enqueueBoxForCrank(uint48 index, address player) authored on DegenerusGame.sol + IDegenerusGame.sol mirror decl; the box-cursor CONSUMER side (parameterless walk gated on lootboxRngWordByIndex != 0)"
provides:
  - "Box-cursor PRODUCER call: IDegenerusGame(address(this)).enqueueBoxForCrank(lbIndex, buyer) wired into the lootbox first-deposit branch of DegenerusGameMintModule.sol — closes CRANK-03 (box do-work crank) by completing the only cross-plan seam (317-03 Deviation 1)"
affects: [317-wave5-batched-diff, 318, 320]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Module->game self-external-call via IDegenerusGame(address(this)).fn(...) (the established MintModule idiom: recordMintQuestStreak :1098 etc.)"
    - "Producer-only enqueue inside the once-per-(index,buyer) first-deposit branch; catastrophe protection lives on the CONSUMER walk gate (lootboxRngWordByIndex != 0), not the producer"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameMintModule.sol

key-decisions:
  - "Placed the enqueue inside the `if (existingAmount == 0)` first-deposit branch (right after `emit LootBoxIdx`), guaranteeing exactly-once-per-box-index firing: every later deposit for the same (index, buyer) takes the `else` branch (or reverts on day mismatch), so it never re-enqueues."
  - "Used `lbIndex` (uint48) + `buyer` (address) — already in scope inside `_purchaseFor(address buyer, ...)` — matching the authored signature `enqueueBoxForCrank(uint48 index, address player)` exactly (no casts needed)."
  - "Matched the existing module->game self-call idiom `IDegenerusGame(address(this)).fn(...)`; IDegenerusGame is already imported (MintModule:8) and the idiom is live at :1098/:1286/:1313/:1518."

requirements-completed: [CRANK-03]

# Metrics
duration: ~15min
completed: 2026-05-23
---

# Phase 317 Plan 03b: Box-Cursor Enqueue Producer Wiring (CRANK-03 seam close) Summary

**Closed 317-03 Deviation 1 — wired the single box-cursor PRODUCER call `IDegenerusGame(address(this)).enqueueBoxForCrank(lbIndex, buyer)` into the lootbox first-deposit branch of `DegenerusGameMintModule.sol`, completing CRANK-03; left UNCOMMITTED for the Phase-317 Wave-5 batched contract approval.**

## Performance

- **Duration:** ~15 min
- **Tasks:** 1 (`auto`) — single producer-call insertion into the one owned file
- **Files modified:** 1 (`contracts/modules/DegenerusGameMintModule.sol`)
- **Compile:** contracts-only build (`forge build --skip test --skip script`) exit 0; full-tree build fails ONLY on a test-layer cross-plan seam (see Verify) — ZERO errors attributable to the owned file.

## The exact change

- **Insertion point (LIVE):** `contracts/modules/DegenerusGameMintModule.sol:999` — the inserted call
  `IDegenerusGame(address(this)).enqueueBoxForCrank(lbIndex, buyer);`
- **Enclosing scope:** `_purchaseFor(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind)` (decl `:899`), inside the lootbox-setup block's first-deposit branch `if (existingAmount == 0)` (opens `:989`), placed immediately after `emit LootBoxIdx(buyer, uint32(lbIndex), lbDay);` (`:994`) and before the `else { if (storedDay != lbDay) revert E(); }`.
- **Matched signature:** authored decl `function enqueueBoxForCrank(uint48 index, address player) external;` at `contracts/interfaces/IDegenerusGame.sol:293`. Call args: `lbIndex` (`uint48`, declared `:978`, set `:982` from `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)`) → `index`; `buyer` (`address`, the `_purchaseFor` param) → `player`. Exact type match, no casts.

## Once-per-box-index guarantee

The first-deposit signal is `existingAmount == 0`, where `existingAmount = lootboxEth[lbIndex][buyer] & ((1 << 232) - 1)` (`:985-986`). The `if (existingAmount == 0)` branch:
- runs on the FIRST deposit for a given `(lbIndex, buyer)` pair (then writes `lootboxEth[lbIndex][buyer]` non-zero at `:1011-1013`, so `existingAmount != 0` thereafter for that index);
- every SUBSEQUENT deposit for the same `(lbIndex, buyer)` takes the `else` branch (or reverts `E()` on a cross-day mismatch).

So `enqueueBoxForCrank(lbIndex, buyer)` fires **exactly once per box index per buyer** (on first deposit only) — no duplicate cursor entries. Cross-checked against `317-LEDGER.md:182` (`lootboxEthBase` first-deposit enqueue signal — live read `:1004` / write `:1008`; the once-per-index signal is the `existingAmount == 0` first-deposit branch immediately above).

## RNG / orphan-index logic: UNTOUCHED

The producer only enqueues an index. The v45 VRF-rotation orphan-index catastrophe protection lives entirely on the CONSUMER side authored in 317-03 (`DegenerusGame.sol:1603` `if (lootboxRngWordByIndex[index] == 0) return;` — a zero-word index is never walked/opened). No `lootboxRngWordByIndex`, no orphan-index gate, no `lootboxEthBase` zeroing/signal logic, and nothing else in `_purchaseFor` was modified. The first-deposit zeroing/signal logic is byte-identical apart from the inserted call + its what-IS comment.

## Self-call idiom match

`IDegenerusGame(address(this)).fn(...)` is the established module->game external-call pattern in this file (live at `:1098` `recordMintQuestStreak(buyer)`, `:1286` `lootboxBoostBps`, `:1313` `recordMint`, `:1518` `recordMintQuestStreak(player)`); `IDegenerusGame` is already imported at `:8`. The inserted call matches it verbatim.

## Verify gate results

- **`FOUNDRY_PROFILE=default forge build` (full tree):** exit nonzero — the ONLY error is
  `Error (9582): Member "setAutoRebuy" not found ... in contract DegenerusGame` at `test/fuzz/BafRebuyReconciliation.t.sol:189`. This is an EXPECTED cross-plan seam: sibling plan 317-03 deleted the afKing-mode `setAutoRebuy` surface (RM-01); the test files that still reference it are owned by the TST phase (318), not by any Wave-2 IMPL plan. The other build output is pre-existing non-fatal `unsafe-typecast` / shadow-declaration warnings (e.g. `DegenerusGameJackpotModule.sol:457`).
- **Contracts-only build (`forge build --skip test --skip script`):** exit 0 — proves the owned edit compiles cleanly against the in-tree sibling Wave-2/3 contract edits.
- **MintModule-attributable errors:** ZERO (`grep -i DegenerusGameMintModule` over the build log → NONE).
- **`git diff --name-only -- contracts/`:** lists `DegenerusGameMintModule.sol` among the dirty files (alongside the EXPECTED untouched sibling files: `BurnieCoin.sol`, `BurnieCoinflip.sol`, `ContractAddresses.sol`, `DegenerusGame.sol`, `interfaces/IBurnieCoinflip.sol`, `interfaces/IDegenerusGame.sol`). My authored change is confined to `DegenerusGameMintModule.sol`.
- **Enqueue call count in MintModule:** exactly 1 (`grep -c enqueueBoxForCrank` → 1, at `:999`), inside the first-deposit branch.

## Deviations from Plan

None — plan executed exactly as written. The producer call landed at the first-deposit branch (`existingAmount == 0`) per the 317-03 SUMMARY Deviation-1 shape and the LEDGER first-deposit-signal lines; matched the authored signature; no other change.

## Deferred-commit status

- **NO git commit made.** The repo commit-guard hook (blocks commits while `contracts/*.sol` is dirty) is intentionally left in force. `STATE.md` / `ROADMAP.md` UNTOUCHED. `contracts/` left dirty.
- This edit + this SUMMARY are UNCOMMITTED, pending the Phase-317 Wave-5 batched USER-APPROVAL gate for the single batched contract diff.
- Did NOT revert/stash/restore/commit any non-owned file; touched ONLY `DegenerusGameMintModule.sol`.

## Self-Check: PASSED

- `contracts/modules/DegenerusGameMintModule.sol` modified — `git diff` shows exactly the single `enqueueBoxForCrank(lbIndex, buyer)` call + its what-IS comment inside the `if (existingAmount == 0)` branch; nothing else changed.
- `317-03b-SUMMARY.md` present on disk at the phase dir (uncommitted; `.planning/` is gitignored).
- No git commit made; `STATE.md` / `ROADMAP.md` untouched; `contracts/` left dirty.
- Contracts-only build exit 0; zero MintModule-attributable errors; the full-tree failure is the expected `setAutoRebuy` test-layer cross-plan seam (phase-318 owned).

---
*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Plan: 03b*
*Completed: 2026-05-23*
