---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 04
subsystem: keeper
tags: [afking, keeper, subscription, sweep, batchPurchase, burnForKeeper, creditFlip, two-tier-skip-kill, cursor-sweep]
requires:
  - "317-03: DegenerusGame.batchPurchase(address[],uint256[],uint8[]) PROTO-04 + hasAnyLazyPass PROTO-01"
  - "317-02: BurnieCoin.burnForKeeper(address,uint256) PROTO-02 + BurnieCoinflip.creditFlip onlyFlipCreditors PROTO-03 + ContractAddresses.AF_KING PROTO-05"
provides:
  - "contracts/AfKing.sol: canonical in-tree keeper (D-01)"
  - "AfKing.subscribe(address,bool,bool,uint8,uint8) signature for SUB-09 self-subscribe wiring (Plan 05)"
affects:
  - "317-05: Vault/sStonk SUB-09 self-subscribe wires against this subscribe signature"
  - "317-06: ../degenerus-utilities single-source reconciliation (D-01b)"
tech-stack:
  added: []
  patterns:
    - "parameterless cursor sweep (advanceGame progress-cursor model + 1/2/4/6x stall-escalating bounty)"
    - "maximal storage packing (reinvestPct + windowPaid into Sub free bytes, NO new slot)"
    - "two-tier skip-kill by un-spoofable pinned ContractAddresses identity (no settable flag)"
    - "all-or-nothing burnForKeeper charge; single gas-pegged creditFlip bounty (deferred mint)"
key-files:
  created:
    - "contracts/AfKing.sol"
  modified: []
decisions:
  - "Self-contained owner-less posture preserved: AfKing carries its own minimal local IGame/IBurnie/ICoinflip interfaces (signatures matched verbatim to the live audit-repo siblings) + inline ContractAddresses call sites + the 3 economic immutables only — no immutable BURNIE/IGAME injection, no admin/owner."
  - "subscribe extended to subscribe(address player, bool drainGameCreditFirst, bool useTickets, uint8 dailyQuantity, uint8 reinvestPct): adds the SUB-02 third-party player arg, the SUB-04 reinvestPct, and useTickets (so SUB-09 sets lootbox mode in one call). useTickets is also independently togglable via setMode."
  - "windowPaid is a 1-bit flag inside a new Sub.flags byte (offset 12); reinvestPct is a uint8 (offset 11). Both land in the previously-free Sub bytes — the struct stays exactly 32 bytes (one slot), slots 0-3 byte-identical to the original."
  - "Sweep cursor + its day-stamp (_sweepDay uint32 + _sweepCursor uint224) pack into a single NEW slot 4. Daily reset: first sweep of a new keeper-local day restarts the cursor at 0; within a day the cursor advances monotonically so concurrent same-block callers self-partition; per-entry lastSweptDay is the idempotency backstop."
  - "Bounty model is creditFlip-only (no BURNIE pool transfer / no mintForKeeper fallback): the keeper holds zero BURNIE custody, so the IBurnie interface needs only burnForKeeper. The stall multiplier (1/2/4/6x) multiplies the per-player bounty, mirroring advanceGame."
metrics:
  duration: ~50m
  completed: 2026-05-23
---

# Phase 317 Plan 04: AfKing Keeper In-Tree Rework Summary

Brought `StreakKeeperV2.sol` in-tree as the canonical `contracts/AfKing.sol` (D-01) and reworked it to the INTENDED end-state — parameterless cursor sweep, packed `reinvestPct`/`windowPaid`, two-tier pinned-identity skip-kill, `batchPurchase` switch, all-or-nothing `burnForKeeper` charge, and single gas-pegged `creditFlip` bounty — authored against the SPEC end-state rather than the mixed live source. UNCOMMITTED (deferred to the Wave-5 approval gate).

## What Was Built

### Task 1 — File creation + Sub packing + cursor sweep
- Created `contracts/AfKing.sol` (contract renamed `StreakKeeperV2 → AfKing`; owner-less / no-admin posture preserved). Self-contained: local minimal `IGame` / `IBurnie` / `ICoinflip` interfaces (signatures matched verbatim to the live audit-repo siblings), inline `ContractAddresses` call sites, constructor sets ONLY the 3 economic immutables (`SUB_COST_ETH_TARGET` / `BOUNTY_ETH_TARGET` / `LOOTBOX_MIN`) with 3 sanity reverts.
- Extended the `Sub` struct: `reinvestPct (uint8)` at offset 11 + a `flags (uint8)` byte at offset 12 (bit 0 = `windowPaid`), into the FREE bytes. **`forge inspect` confirms `Sub` is exactly 32 bytes (one slot)** — slots 0-3 (`_poolOf`/`_subOf`/`_subscribers`/`_subscriberIndex`) byte-identical to the original; NO new struct slot.
- Replaced the OLD caller-supplied `sweep(uint256 startIdx, uint256 count)` with the parameterless `sweep(uint256 maxCount)` + internal daily-reset cursor (`_sweepDay uint32` + `_sweepCursor uint224` packed into a single new slot 4). Cursor resumes from its prior position, processes ≤ `maxCount` entries, advances, and pays the per-chunk stall-escalating bounty (1/2/4/6× by elapsed time since day-start, mirroring `advanceGame`). `lastSweptDay >= today` idempotency backstop preserved (reason-2 skip).

### Task 2 — Quantity max-semantics + funding waterfall + two-tier skip-kill + lifecycle
- SUB-04 quantity model: `effectiveQty = max(dailyQuantity, floor(claimable * reinvestPct / 100 / mp))` with `dailyQuantity` minimum 1 (the `InvalidDailyQuantity` revert disallows flat-0; cancel is the `setDailyQuantity(0)` tombstone). `TICKET_SCALE = 400` keeps the comparison unit-consistent (one `dailyQuantity` unit = one `mintPrice` lootbox).
- Funding waterfall preserved byte-faithfully: `!drainGameCreditFirst → DirectEth msgValue=cost`; else `cred>cost → Claimable msgValue=0`, `cred>1 → Combined msgValue=cost-(cred-1)`, else `DirectEth`. `_poolOf[player] < msgValue` is the InsufficientPool funding skip. Claimable-only = empty `_poolOf` (no `claimableOnly` flag added — emergent property).
- Two-tier skip-kill (SUB-06): a NORMAL sub on a funding skip is CANCELLED via `_removeFromSet` swap-pop (sets `dailyQuantity=0`, clears `windowPaid`, emits `SubscriptionExpired(player,1)`, continues WITHOUT advancing the cursor — the swap-pop occupant is processed this sweep). `Vault` + `sDGNRS` are EXEMPT via the un-spoofable pinned `ContractAddresses.VAULT` / `SDGNRS` identity branch (no-op-and-retry, `PlayerSkipped(player,3)`, stays in set). **No settable exemption flag exists** (verify gate: zero non-comment `isExempt|exemptFlag|skipKillExempt|_exempt` matches).
- LootboxFloor transient skip (reason 4, `!useTickets && cost < LOOTBOX_MIN`) kept distinct from the funding kill (stays in set, retries next-day sweep).
- SUB-07 lifecycle: tombstone-on-cancel; in-sweep swap-pop reclaim WITHOUT cursor-advance; `windowPaid`-gated `_subOf` reclaim — `delete` on cancel unless `windowPaid` set AND `paidThroughDay > today` (preserve a paid, unexpired window). `windowPaid` set on `burnForKeeper` success, cleared on the free pass-extend. Stranded `_poolOf` stays withdrawable.

### Task 3 — batchPurchase switch + burnForKeeper charge + creditFlip bounty + authorization
- Per-player purchase switched to the PROTO-04 `batchPurchase(address[],uint256[],uint8[])` — slices accumulated in the per-player accounting loop (CEI debit before, day-stamp after), fired ONCE after the loop with one slice per successful player. The buffers are trimmed to the exact `batchLen` (via `mstore` length-trim) so the game-side length-equality guard holds.
- Charge is the all-or-nothing `burnForKeeper(player, cost)`; `burned != cost` → auto-pause (`dailyQuantity=0`, clear `windowPaid`, `_removeFromSet`, `SubscriptionExpired(player,1)`, continue WITHOUT cursor-advance). `windowPaid` set on success.
- Bounty: ONE `creditFlip(msg.sender, batchLen * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * bountyMultiplier) / mp))` per tx (never per-item, REW-02); `revert NoSubscribersSwept` when zero buys. Deferred-mint coinflip credit — no liquid BURNIE leaves the keeper.
- SUB-01 pass-OR-pay at the day-31 renewal branch only: `hasAnyLazyPass(player)` → free extend; else `burnForKeeper` or skip-with-emit (never reverts the whole sweep).
- SUB-02 authorization checked ONCE at `subscribe` (self-consent `player==0||msg.sender`, else `isOperatorApproved`), NEVER at sweep.
- Zero surviving `pullForKeeper` / `mintForKeeper` references (the live source's were comment-prose only; the rework's docstrings describe what IS).

## Cross-Plan Signature Verification

| External call | AfKing call site | Live sibling source | Match |
|---------------|------------------|---------------------|-------|
| `batchPurchase(address[],uint256[],uint8[]) payable` | `:738` `batchPurchase{value: totalValue}(players, amounts, modes)` | `DegenerusGame.sol:1687` | verbatim |
| `burnForKeeper(address,uint256) returns (uint256 burned)` | `:396` / `:587` | `BurnieCoin.sol:456` | verbatim |
| `creditFlip(address,uint256)` | `:746` | `BurnieCoinflip.sol:848` | verbatim |
| `AF_KING` pinned identity | (keeper IS AF_KING — knows itself via `address(this)`; sibling gates reference the pinned const) | `ContractAddresses.sol:53` | n/a (correct: keeper does not gate on itself) |

The PROTO-04 `batchPurchase` per-player param is an **ETH-wei `amounts` slice** + a `uint8 modes` MintPaymentKind cast (the game-side `_batchPurchaseUnit` forwards the slice's `msg.value` into the mint module via `_purchaseFor(player, 0, msg.value, bytes32(0), payKind)` — ticketQuantity hardcoded 0). The rework conforms to this LIVE shape (the old `purchase(player, ticketQty, lootBoxAmt, ...)` per-player call is gone). Plan 06's pre-task reconciles this call site against the Plan-03 authored signature.

## Compilation Verification

`forge inspect contracts/AfKing.sol:AfKing storage-layout` confirms:
- Slots 0-3 LOCKED: `_poolOf` / `_subOf` / `_subscribers` / `_subscriberIndex` (each 32 bytes, offset 0).
- Slot 4 (new): `_sweepDay uint32` (offset 0) + `_sweepCursor uint224` (offset 4) — single packed slot.
- `Sub` struct = 32 bytes (one slot): `reinvestPct` offset 11 + `flags` offset 12 in the previously-free bytes.

A source-only `forge build` (`FOUNDRY_TEST`/`FOUNDRY_SCRIPT` pointed at an empty dir to exclude the pre-existing RM-cascade test-compile breaks owned by Plan 06) **compiled `contracts/AfKing.sol` clean** (exit 0, zero `Error (` / `Compiler run failed`; only repo-wide `forge-lint` advisory warnings, all pre-existing house style). The full-tree build's only error is `setAutoRebuy not found` in `test/fuzz/BafRebuyReconciliation.t.sol` — an RM-removed-symbol test reference owned by the Plan-06 test re-derivation, zero relation to AfKing.sol; held-out test files were all restored (`git status test/` clean).

## Deviations from Plan

None of the Rule-1/2/3 auto-fix kind were needed. Two in-scope authored design clarifications (within the SPEC end-state, not deviations):

1. **`subscribe` signature shape.** The SPEC/PATTERNS lock the existence of `reinvestPct` + the SUB-02 third-party `player` arg but do not fix the exact arg tuple. Authored `subscribe(address player, bool drainGameCreditFirst, bool useTickets, uint8 dailyQuantity, uint8 reinvestPct)` — `useTickets` is included so SUB-09 (Plan 05) can set lootbox mode at subscribe in one call (it remains independently togglable via `setMode`). Plan 05 conforms to this LIVE signature per its own instruction.
2. **Bounty payout is `creditFlip`-only (no pool-drain transfer / no `mintForKeeper`).** The intended end-state holds zero BURNIE custody (the charge is burned, the bounty is a fresh coinflip-credit emission), so the OLD pool-drains-first `transfer` + `mintForKeeper`-shortfall block is dropped entirely — consistent with the SPEC bounty model and the `IBurnie` interface needing only `burnForKeeper`.

## Known Stubs

None. No hardcoded empty values flowing to UI, no placeholder text, no unwired data sources. The keeper is fully self-contained; the only external coupling is the four matched sibling signatures above (all live in the dirty working tree from Wave-2/3).

## Threat Flags

None beyond the plan's `<threat_model>` register. The new surface (`subscribe` third-party path, `sweep` cursor, `batchPurchase` call) is exactly the threat-modeled surface; the SUB-06 spoof-resistance (T-317-04-01) is mitigated by the pinned-identity-only exemption (zero settable-exemption-flag matches), and the all-or-nothing burn (T-317-04-03) + CEI/swap-pop (T-317-04-02) are implemented as specified. Empirical proofs (SAFE-02/03 non-brick + concurrency) are routed to 318 TST; spoof/griefing review to 320 AUDIT, per the register.

## Commit Status

NOT COMMITTED. `contracts/AfKing.sol` is now covered by the commit-guard hook (D-01a) and is left UNTRACKED/dirty alongside the sibling Wave-2/3 `contracts/` edits. STATE.md / ROADMAP.md untouched. Nothing in `../degenerus-utilities` edited (D-01b reconciliation owned by Plan 06). The single batched contract commit is the orchestrator's Wave-5 USER-approval gate.

## Self-Check: PASSED

- `contracts/AfKing.sol` exists (untracked) — FOUND.
- All 3 task verify gates PASS (sweep(maxCount)/sweepCursor/reinvestPct/windowPaid present, zero startIdx; VAULT/SDGNRS + `_removeFromSet` present, zero settable-exemption-flag matches; batchPurchase/burnForKeeper/creditFlip/hasAnyLazyPass present, zero pull/mintForKeeper).
- Zero `gasleft()` / `tx.gasprice` (no measured-gas peg).
- `forge inspect` storage-layout confirms one-slot Sub packing + locked slots 0-3.
- No commit made; STATE.md/ROADMAP.md untouched; no file outside `contracts/AfKing.sol` authored.
