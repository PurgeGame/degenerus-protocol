---
phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl
plan: 02
subsystem: contracts
tags: [solidity, burnie-coin-purchase, far-future-salvage, sdgnrs, quest-rebate, loss-of-funds-fix]

# Dependency graph
requires:
  - phase: 358-spec-design-lock
    provides: "BURNIE-03 D-21/22/23/24 (verified loss-of-funds bug + queue-on-return + deferred net-burn rebate), SALVAGE-02 D-25..D-29 (combo ETH/BURNIE cash leg + sDGNRS-owned-BURNIE primitives + solvency-positive accounting), Handoff Invariants 3-6"
  - phase: 359-01
    provides: "DegenerusQuests.handlePurchase RETURNS burnieMintReward (no inline creditFlip); the returned-reward contract this plan's BURNIE coin caller nets against a deferred burn"
provides:
  - "BURNIE-01: _purchaseCoinFor now QUEUES tickets (queue-on-return mirroring the ETH path) — the coin-burned-zero-tickets loss-of-funds sink is closed"
  - "BURNIE-02: the MINT_BURNIE quest credit restored on the coin path as a deferred net-burn rebate (full coinCost gated upfront, burn = coinCost − reward floored at 0, never a separate creditFlip)"
  - "SALVAGE-01: sellFarFutureTickets cash leg splits into ETH + BURNIE; BURNIE transferred from sDGNRS-owned BURNIE via coin.transferFrom (GAME bypass, auto-sources coinflip stake), ETH fallback; only the ETH part leaves claimableWinnings[SDGNRS] (solvency-positive)"
  - "SALVAGE-01 preview parity: _quoteFarFutureBurnieSplit (new same-seed third slice + sDGNRS availability read) shared by execute + a new previewSellFarFutureSplit view"
affects: [359-03 (build checkpoint + WWXRP/TDEC/CANCEL), 360 (GAS), 361 (TST HYG-03 buy-then-claim + SEC-02 posture-widening + SALVAGE-03 no-arb re-proof), 362 (TERMINAL delta-audit)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Queue-on-return on the coin path (mirror of the ETH path _queueTicketsScaled(buyer, targetLevel, qty, false))"
    - "Deferred net-burn rebate: gate full cost upfront via balanceOfWithClaimable, run the quest leg, burn net of the returned reward (one fewer creditFlip than credit-then-reburn)"
    - "sDGNRS-owned-BURNIE payout via coin.transferFrom (GAME bypass; _claimCoinflipShortfall auto-draws wallet-then-coinflip-stake) instead of a creditFlip mint"
    - "Same-seed third bit-slice (no new VRF) + source-availability read shared by both quote and execute for previewable salvage splits"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameMintStreakUtils.sol
    - contracts/interfaces/IDegenerusCoin.sol
    - contracts/DegenerusGame.sol

key-decisions:
  - "BURNIE-02 affordability gate uses coin.balanceOfWithClaimable(buyer) (added to IDegenerusCoin) against the FULL coinCost — the rebate can only reduce the burn, never enable an unaffordable buy"
  - "The deferred-burn reorder removes _coinReceive from _callTicketPurchase's payInCoin branch (only reachable from _purchaseCoinFor) and re-issues it in _purchaseCoinFor AFTER handlePurchase, on burnAmount = coinCost − rebate (floored 0)"
  - "SALVAGE pays the BURNIE leg via coin.transferFrom(SDGNRS, player, burnieTokens) — a single GAME-bypass primitive that auto-sources wallet balance then claimable coinflip stake (via _claimCoinflipShortfall), so no onlyBurnieCoin consume is needed and value is conserved"
  - "Only the ETH portion leaves SDGNRS: claimableWinnings[SDGNRS] -= ethRelabel (= ticketWei + ethCashWei = totalBudget − burnieEthValue), so ethRelabel <= totalBudget (solvency-positive). The >=1 ETH floor stays gated on the FULL totalBudget (strictly more conservative) — byte-unchanged"
  - "Quote stays a sibling helper _quoteFarFutureBurnieSplit (NOT a re-typed _quoteFarFutureSwap) so the existing 4-tuple preview + the 45 forge fixtures binding it are byte-untouched; the split is exposed via a NEW previewSellFarFutureSplit view (zero churn on the existing preview)"

patterns-established:
  - "Producer-before-consumer reward netting: plan-01's handlePurchase return is consumed on the coin path as a burn rebate (deferred), not a credit"
  - "GAME-bypass token move as the sDGNRS-owned-BURNIE payout primitive (transferFrom auto-resolves both BURNIE sources)"

requirements-completed: [BURNIE-01, BURNIE-02, SALVAGE-01]

# Metrics
duration: ~25min
completed: 2026-06-04
---

# Phase 359 Plan 02: BURNIE-01/02 + SALVAGE-01 — Coin-Path Queue/Rebate + Combo ETH/BURNIE Salvage Summary

**Closed the Critical BURNIE-coin loss-of-funds sink (coin burned, zero tickets queued) by capturing `_callTicketPurchase`'s returns and queuing on the coin path; restored the MINT_BURNIE quest credit as a deferred net-burn rebate (full cost gated upfront, never a separate creditFlip); and split the far-future-salvage cash leg into a variable ETH+BURNIE combo paid from sDGNRS-owned BURNIE (transfer, never mint) with an ETH fallback, leaving only the ETH part out of `claimableWinnings[SDGNRS]` (solvency-positive). All contract edits are UNCOMMITTED, held for the plan-04 batched USER hand-review.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-04T12:56:37Z
- **Completed:** 2026-06-04T13:21Z
- **Tasks:** 3 (Task 1 BURNIE-01/02; Task 2 SALVAGE execute; Task 3 SALVAGE quote)
- **Files modified:** 4 contracts (uncommitted) + docs

## Accomplishments

- **BURNIE-01 (Critical loss-of-funds fix)** — `_purchaseCoinFor` (`DegenerusGameMintModule.sol:887`) no longer calls `_callTicketPurchase(...)` as a bare statement discarding all 4 returns. It now CAPTURES `(, adjustedQty32, targetLevel, burnieMintUnits)` and, after the burn/quest steps, calls `if (adjustedQty32 != 0) _queueTicketsScaled(buyer, targetLevel, adjustedQty32, false);` — the EXACT `(..., false)` shape the ETH path uses at `:1251`. A live BURNIE buy now mints tickets instead of being a pure token sink.
- **BURNIE-02 (MINT_BURNIE quest credit restored as a burn rebate)** — the coin path now: (a) gates the FULL `coinCost = (ticketQuantity * (PRICE_COIN_UNIT/4)) / TICKET_SCALE` upfront via `coin.balanceOfWithClaimable(buyer) < coinCost → revert E()` (eligibility is the full amount, never the net); (b) calls `quests.handlePurchase(buyer, 0 /*ethMintSpendWei*/, burnieMintUnits, 0 /*lootBoxAmount*/, nextLevelPrice, nextLevelPrice)` — MINT_BURNIE leg only (skips activity score / affiliate / non-mint quests); (c) takes the RETURNED reward (the value plan 01 now returns) as a `rebate` and burns net `burnAmount = rebate >= coinCost ? 0 : coinCost − rebate` via the existing `_coinReceive` primitive. The rebate is a reduced burn ≤ full cost, NEVER a separate `creditFlip`.
- **SALVAGE-01 (combo ETH/BURNIE pawn-shop payout)** — `sellFarFutureTickets` (`:976`) now splits the `cashWei` leg via the new shared quote helper into `(ethCashWei, burnieTokens)`. It relabels only `ethRelabel = ticketWei + ethCashWei` out of `claimableWinnings[SDGNRS]` (so `ethRelabel <= totalBudget` — solvency-positive) and transfers `burnieTokens` from sDGNRS-owned BURNIE via `coin.transferFrom(SDGNRS, player, burnieTokens)` (GAME bypass; auto-sources wallet balance then claimable coinflip stake through `_claimCoinflipShortfall`). Zero sDGNRS BURNIE / zero-target seed ⇒ all-ETH (the "like now" fallback). The `FarFutureSwap` event now carries `(…, ticketWei, ethCashWei, burnieTokens)`.
- **SALVAGE-01 preview parity** — `_quoteFarFutureBurnieSplit` (`DegenerusGameMintStreakUtils.sol:204`) derives `targetEth ∈ [0, cashWei]` from a NEW third bit-slice `(seed >> 64) % (cashWei + 1)` of the SAME settled prior-day seed (`keccak256(player, rngWordByDay[_simulatedDayIndex()-1])` — no new VRF), reads `coin.balanceOfWithClaimable(SDGNRS)` for availability, caps `burnieTokens = min(targetBurnie, owned)`, and re-derives `burnieEth` from the capped tokens so value is conserved exactly (`ethCashWei + value(burnieTokens) == cashWei`). Both the execute path AND the new `previewSellFarFutureSplit` view (`DegenerusGame.sol:2130`) call it, so the displayed ETH/BURNIE breakdown equals what is paid.

## Exact functions / lines changed

### `contracts/modules/DegenerusGameMintModule.sol`

- **`_purchaseCoinFor` (`:887`)** — rewritten body: captures the 4-tuple from `_callTicketPurchase`; full-cost affordability gate `coin.balanceOfWithClaimable(buyer) < coinCost`; MINT_BURNIE `handlePurchase` leg in a scoped block (`nextLevelPrice = priceForLevel(level + 1)` for both the `mintPrice` and `levelQuestPrice` args); `rebate = questReward` on `questCompleted`; **deferred net burn** `_coinReceive(buyer, coinCost − rebate floored 0)`; `_queueTicketsScaled(buyer, targetLevel, adjustedQty32, false)` when non-zero. The `_livenessTriggered():891` + `gameOverPossible:895` gates are byte-unchanged (only the stale `// ENF-01:` prefix on the gameOverPossible comment was trimmed per the lean-comment rule).
- **`_callTicketPurchase` payInCoin branch (`:1609`)** — removed the in-branch `coinCost` compute + `_coinReceive(buyer, coinCost)` (the burn is **deferred** to `_purchaseCoinFor`). The branch now only accumulates `burnieMintUnits` (the mint-quest unit count). This branch is reachable ONLY from `_purchaseCoinFor` (the ETH caller passes `payInCoin=false`), so the ETH path is byte-unchanged.
- **`sellFarFutureTickets` (`:976`)** — destructuring now captures `cashWei`; added the `_quoteFarFutureBurnieSplit` call; replaced the `claimableWinnings[SDGNRS] -= totalBudget` / `+= totalBudget` pair with `-= ethRelabel` / `+= ethRelabel` (`ethRelabel = ticketWei + ethCashWei`) plus `coin.transferFrom(SDGNRS, player, burnieTokens)` when non-zero. The `>=1 ETH` floor (`:1007`, `< totalBudget + 1 ether`), the rngLocked/gameOver/liveness gates (`:982-984`), and the ticket leg (`_purchaseFor(player, qty, 0, bytes32(0), Claimable)`) are byte-unchanged.
- **`FarFutureSwap` event (`:956`)** — last field `cashWei` split into `ethCashWei` + `burnieTokens` (+ a doc note). Event is defined/emitted only in this file (no interface or test binds its arity), so the signature change is build-safe.

### `contracts/modules/DegenerusGameMintStreakUtils.sol`

- **NEW `_quoteFarFutureBurnieSplit(player, cashWei) → (ethCashWei, burnieTokens)` (`:204`)** — `internal view`. Recomputes the SAME seed as `_quoteFarFutureSwap`; third slice `(seed >> 64) % (cashWei + 1)`; price `priceForLevel(_activeTicketLevel())`; availability `coin.balanceOfWithClaimable(ContractAddresses.SDGNRS)`; `targetBurnie = targetEth * PRICE_COIN_UNIT / priceWei`; `burnieTokens = min(targetBurnie, owned)`; `burnieEth = burnieTokens * priceWei / PRICE_COIN_UNIT` (re-derived from the capped tokens for exact conservation, defensively clamped `<= cashWei`); `ethCashWei = cashWei − burnieEth`. Early-returns `(cashWei, 0)` (all-ETH) on `cashWei==0`-guarded zero-target / zero-price. **`_quoteFarFutureSwap` (the existing 4-tuple) is byte-unchanged.**

### `contracts/interfaces/IDegenerusCoin.sol`

- Added `balanceOfWithClaimable(address) → uint256` and `transferFrom(address,address,uint256) → bool` to the `IDegenerusCoin` interface (both already implemented on `BurnieCoin`; needed so the module can gate full cost + transfer sDGNRS-owned BURNIE).

### `contracts/DegenerusGame.sol`

- Added `previewSellFarFutureSplit(player, levels, quantities) → (ticketWei, ethCashWei, burnieTokens)` (`:2130`), an `external view` that calls `_quoteFarFutureSwap` then `_quoteFarFutureBurnieSplit` so the salvage offer's ETH/BURNIE split is previewable end-to-end. The existing 4-tuple `previewSellFarFutureTickets` is byte-unchanged (forge fixtures binding it unaffected).

## The deferred-burn reorder shape

Before: burn happened INSIDE `_callTicketPurchase:1548` (`_coinReceive(buyer, coinCost)`) BEFORE any quest handling, and the coin path returned without queuing.

After: `_purchaseCoinFor` runs in producer-before-consumer order — (1) `_callTicketPurchase` (computes `adjustedQty32`/`targetLevel`/`burnieMintUnits`, no burn) → (2) full-cost affordability gate (`balanceOfWithClaimable >= coinCost`) → (3) `handlePurchase` MINT_BURNIE leg returns the reward → (4) burn net `coinCost − reward` (floored 0) → (5) queue tickets. The burn primitive (`_coinReceive` → `coin.burnCoin`) is unchanged; only WHEN and HOW MUCH it burns moved.

## sDGNRS-owned-BURNIE source primitives used

- **Payment:** `coin.transferFrom(SDGNRS, player, burnieTokens)` — the GAME-bypass ERC20 transfer (no allowance). `BurnieCoin.transferFrom` calls `_claimCoinflipShortfall(SDGNRS, amount)` first, which (when RNG is unlocked — guaranteed here by the `:982 rngLockedFlag` gate) claims from sDGNRS's coinflip stake into the wallet to cover any shortfall, then `_transfer`s. So ONE call atomically draws from BOTH sources (token balance + claimable coinflip stake) and never mints — exactly the D-26 "transfer, never creditFlip" requirement.
- **Availability read (quote + gate):** `coin.balanceOfWithClaimable(SDGNRS)` = `balanceOf[SDGNRS] + previewClaimCoinflips(SDGNRS)` — the same two sources `transferFrom` will draw from, so the previewed cap equals the executable cap at any block.

## The relabel reduction (only ETH part leaves SDGNRS)

`claimableWinnings[SDGNRS] -= ethRelabel` where `ethRelabel = ticketWei + ethCashWei = totalBudget − value(burnieTokens)`. Since `ethCashWei <= cashWei` ⇒ `ethRelabel <= ticketWei + cashWei = totalBudget`, and the `>=1 ETH` floor still gates on the full `totalBudget`, the `-=` cannot underflow and SDGNRS pays strictly less ETH than before (the BURNIE part replaces ETH) → **solvency-positive**. `claimablePool` (the ETH prize pool) is NOT touched anywhere in `sellFarFutureTickets` (the only `claimablePool` mention is the comment noting it's unchanged).

## The relabel-target / no-VRF / new-slice details

- **No new VRF:** the split target derives from `(seed >> 64)` of the SAME `keccak256(player, rngWordByDay[_simulatedDayIndex()-1])` settled prior-day word the jitter (`seed % 4001`) and ticket-share (`(seed >> 128) % 4001`) slices already use. Distinct bit windows (0.., 64.., 128..) keep them independent.
- **Value conservation:** the cash-leg VALUE is unchanged; the split changes only form/source (ETH vs sDGNRS-owned BURNIE), so every reachable offer stays ≤ the existing no-arb ceiling + eth-% cap (re-proven empirically at SALVAGE-03 / TST 361).

## Decisions Made

See frontmatter `key-decisions`. The load-bearing ones: (1) `balanceOfWithClaimable` as the full-cost gate primitive (added to the interface); (2) `coin.transferFrom` as the single sDGNRS-owned-BURNIE payout (auto-resolves both sources, no `onlyBurnieCoin` consume needed); (3) a sibling quote helper + new preview view rather than re-typing `_quoteFarFutureSwap` (zero churn on the existing 4-tuple preview and its forge fixtures).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extended `IDegenerusCoin` with `balanceOfWithClaimable` + `transferFrom`**
- **Found during:** Task 1 (BURNIE-02 affordability gate) and Task 2 (SALVAGE BURNIE transfer)
- **Issue:** The module's `coin` handle is typed `IDegenerusCoin`, which exposed only `vaultEscrow`/`burnCoin`/`mintForGame`. The full-cost affordability gate needs a spendable-balance read and the SALVAGE BURNIE leg needs a GAME-bypass transfer — both already implemented on `BurnieCoin` but absent from the interface, so the edits would not compile.
- **Fix:** Added `balanceOfWithClaimable(address) view` and `transferFrom(address,address,uint256)` declarations to `contracts/interfaces/IDegenerusCoin.sol`, matching the existing `BurnieCoin` implementations exactly.
- **Files modified:** `contracts/interfaces/IDegenerusCoin.sol`
- **Verification:** Signatures match `BurnieCoin.balanceOfWithClaimable:243` and `BurnieCoin.transferFrom:329` (return types/params identical); deferred full `forge build` to the plan-03 checkpoint per SPEC D-03.

**2. [Rule 2 - Missing Critical] Added `previewSellFarFutureSplit` so the salvage offer is previewable end-to-end**
- **Found during:** Task 3 (preview parity)
- **Issue:** SALVAGE-01's success criterion requires the offer to stay "truly knowable in advance" — the previewed ETH/BURNIE split must match what the execute path pays. The existing 4-tuple `previewSellFarFutureTickets` shows only `cashWei` (the pre-split total) and cannot be extended to a 6-tuple without breaking the 45+ forge fixtures and the `IDegenerusGame*` callers that destructure the 4-tuple.
- **Fix:** Added a separate `external view previewSellFarFutureSplit` on `DegenerusGame` that returns `(ticketWei, ethCashWei, burnieTokens)` from the shared `_quoteFarFutureBurnieSplit` (reflecting live sDGNRS availability + the ETH fallback). The existing 4-tuple preview is left byte-unchanged.
- **Files modified:** `contracts/DegenerusGame.sol`
- **Verification:** `previewSellFarFutureTickets` 4-tuple unchanged; the new view shares the exact same-seed split + availability primitive as the execute path.

---

**Total deviations:** 2 auto-fixed (1 blocking interface extension, 1 missing-critical preview view).
**Impact on plan:** Both are required to make the planned MintModule + MintStreakUtils edits compile (interface) and satisfy the previewability success criterion (preview view). The plan's `files_modified` listed only the 2 module files; these two supporting files are the minimal additions needed to realize them. No scope creep beyond the three requirements.

## Issues Encountered

**Plan-01 handoff note re-examined (not a bug; correction recorded).** Plan 01 flagged a "now-stale comment" at `MintModule:1712` (`/// BURNIE mints: reward creditFlipped internally by handler (nothing to batch)`) on the assumption it described `handlePurchase`. On inspection that comment belongs to `_questMint` (`:1755` after this plan's edits), which calls `handleMint` — NOT `handlePurchase`. `handleMint` was untouched by plan 01 and STILL credits the BURNIE reward internally (`DegenerusQuests.sol:613`), so the comment is factually accurate. Furthermore `_questMint` is **dead code** (no callers anywhere in `contracts/`). I therefore left it untouched to avoid out-of-scope churn / contract-size surprises. This corrects plan 01's handoff item: no comment fix was warranted there.

## NO CONTRACT COMMIT MADE

Per the contract-commit boundary (this plan is `autonomous: false`; project rule: only `contracts/*.sol` commits need USER approval), all four contract edits — `contracts/modules/DegenerusGameMintModule.sol`, `contracts/modules/DegenerusGameMintStreakUtils.sol`, `contracts/interfaces/IDegenerusCoin.sol`, `contracts/DegenerusGame.sol` — are left **UNCOMMITTED** in the working tree, alongside plan 01's still-uncommitted `contracts/DegenerusQuests.sol`. They accumulate across plans 01–04 and are committed as ONE batched diff ONLY after explicit USER hand-review at the plan-04 HARD STOP. No `git add -A`/`git add .`/`git add contracts` was run; no `contracts/*.sol` was staged. No `forge build` was run (SPEC D-03 = build checkpoints at end of plan 03 and in plan 04 only); verification was source-assertion + targeted grep.

## Next Phase Readiness

- The BURNIE coin path (queue-on-return + deferred net-burn rebate) and the SALVAGE combo split are authored against the frozen subject and ready for the plan-03 build checkpoint (alongside WWXRP/TDEC/CANCEL).
- The interface extension (`IDegenerusCoin`) and the preview view (`DegenerusGame`) are part of the same uncommitted batch — they must be reviewed together with the module edits at plan 04.
- TST 361 deferred proofs: HYG-03 (BURNIE buy-then-claim + `claimablePool <= balance`), SEC-02 (the flagged posture-widening — restored ticket claims), SALVAGE-03 (EXTEND-`SWAP08` no-arb across the full split range + the zero-available all-ETH fallback).

## Self-Check: PASSED

- `_purchaseCoinFor` captures the `_callTicketPurchase` returns and calls `_queueTicketsScaled(buyer, targetLevel, adjustedQty32, false)` (grep `_queueTicketsScaled(buyer, targetLevel` count = 2: ETH path + coin path).
- `quests.handlePurchase` routed on the coin path with `ethMintSpendWei=0, lootBoxAmount=0` (grep `handlePurchase` count = 2: ETH caller + coin caller).
- `sellFarFutureTickets` debits only `ethRelabel` from `claimableWinnings[SDGNRS]` and transfers `burnieTokens` via `coin.transferFrom` (grep shows the floor gate `< totalBudget + 1 ether` byte-unchanged + the new `-= ethRelabel`).
- `_quoteFarFutureBurnieSplit` present (`MintStreakUtils.sol:204`); reads `coin.balanceOfWithClaimable` for availability; `_quoteFarFutureSwap` 4-tuple unchanged.
- `git status` shows modified `contracts/*.sol`, all UNCOMMITTED; no `contracts/*.sol` staged.

## In-Session Revisions (post-commit, USER-directed — supersede the above where noted)

After this SUMMARY was committed (`af1dc742`), the USER directed two revisions to this plan's deliverables, applied to the still-uncommitted working tree (held for the same plan-04 HARD STOP) and confirmed by a green `forge build`:

1. **SALVAGE preview merged into one 5-tuple (supersedes deviation #2 + the `previewSellFarFutureSplit` view).** The separate `previewSellFarFutureSplit` is **deleted**; `previewSellFarFutureTickets` now returns the full breakdown `(totalFaceWei, totalBudget, ticketWei, ethCashWei, burnieTokens)` — `cashWei` replaced by its `ethCashWei + burnieTokens` split (conserved as `cashWei == ethCashWei + value(burnieTokens)`). One call gives the whole picture; no redundant `_quoteFarFutureSwap` recompute. The 6 binding sites in `test/fuzz/FarFutureSalvageSwap.t.sol` were bumped to the 5-tuple arity (they ignore the cash slot). `_quoteFarFutureBurnieSplit` and the SALVAGE execute path are unchanged.

2. **BURNIE-02 rebate dropped → MINT_BURNIE quest reward awarded via `creditFlip` (supersedes the deferred net-burn rebate).** The deferred net-burn rebate is removed. The **full** `coinCost` burn is restored at its original site (the `payInCoin` branch of `_callTicketPurchase`, matching frozen `1e7a646d`). `_purchaseCoinFor` keeps the BURNIE-01 queue-on-return fix and now, after `handlePurchase`, awards the returned reward as `if (questCompleted && questReward != 0) coinflip.creditFlip(buyer, questReward);` — the normal flip-credit mechanism. The rebate-only `balanceOfWithClaimable(buyer)` full-cost gate is removed (the burn itself gates affordability); the `balanceOfWithClaimable` **interface declaration stays** (SALVAGE's quote at `MintStreakUtils:225` still uses it). **BATCH-01 (plan 01) is KEPT** — `handlePurchase` still returns the reward; the ETH path still batches into `lootboxFlipCredit`; the coin path `creditFlip`s the return. Both paths award via flip credit.

**Related (out-of-plan, same batched diff):** the USER also directed a lazy-pass purchase-window change in `contracts/modules/DegenerusGameWhaleModule.sol` (now purchasable at **0–2 OR x9 OR x0**, terminal x00 excluded). That is NOT part of this plan's three requirements; it is a new in-session scope addition tracked for the plan-04 UDVT sweep (its day-bearing code) and the HARD STOP hand-review. See STATE.md.

---
*Phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl*
*Completed: 2026-06-04*
