# 331 GAS-01 — Keeper-Router Worst-Case Marginal Gas Derivation

**Phase:** 331 (GAS — worst-case marginal derivation + break-even @0.5 gwei peg calibration)
**Plan:** 331-01
**Subject:** the committed 330 IMPL keeper-router diff (`63bc16ca`) — `AfKing.doWork()` (`AfKing.sol:868`) + `_autoBuy` (`:561`) + `DegenerusGame.autoOpen` (`:1666`) + `DegenerusGameAdvanceModule.advanceGame` (`:154`).
**Method:** theory-FIRST (this document), then measure (`test/gas/RouterWorstCaseGas.t.sol`) per `feedback_gas_worst_case`.
**Analog:** v46 Phase 319 `319-GAS-DERIVATION.md` — this is the same derive-then-measure pass repeated one phase up for the v49 router.

> ### ⚠️ CORRECTION PASS (2026-05-27) — superseding the original §1/§2/§5 BUY + OPEN conclusions
> The originally-committed 331-01 derivation had TWO load-bearing errors, fixed in this pass
> (test harness commit `322fd972`):
> 1. **BUY marginal was measured on the REVERT-CATCH path, not a real buy (~40,224 wrong → ~256,000 correct).**
>    The buy harness asserted "the buy landed" via AfKing's `lastAutoBoughtDay` day-stamp. That stamp
>    is set in `_autoBuy`'s accounting loop (`AfKing.sol:744`) BEFORE the batched `IGame.batchPurchase`
>    fires, and `batchPurchase` wraps each per-player slice in
>    `try this._batchPurchaseUnit{value: slice}() catch {}` (`DegenerusGame.sol:1773-1780`). The keeper
>    buy is lootbox-only (`_purchaseFor(player, 0, slice, "DGNRS", payKind)`, ticketQuantity=0,
>    `DegenerusGame.sol:1806`), so the mint module's `lootBoxAmount < LOOTBOX_MIN (0.01 ether)` guard
>    (`DegenerusGameMintModule.sol:1011`) REVERTED every slice below 0.01 ether inside the try/catch —
>    a reverted (skipped+refunded) buy that LEFT THE DAY-STAMP SET. The original `40,224` was the cost
>    of that revert-catch path. The corrected harness verifies the buy actually LANDED via
>    `lootboxEthBase[index][player] > 0` (the same correct first-deposit signal the OPEN test uses) and
>    funds DirectEth with a slice == mp == 0.01 ether == LOOTBOX_MIN. **A correctly-verified DirectEth
>    first-deposit buy marginal is ~261,809 (whole-set N=32) / ~255,614 (clean N=32); whole 32-leg
>    ~8.38M.** BUY is therefore the MOST EXPENSIVE per-item leg, not the cheapest.
> 2. **OPEN worst case omitted the whale-pass branch (the GAP).** §2 originally asserted the per-box
>    cost is FLAT (~89,287) with "no heavier per-box branch." WRONG: a box-open whose probabilistic
>    boon roll selects the whale-pass boon (type 28, `BOON_WHALE_PASS`) runs `_activateWhalePass`
>    (`DegenerusGameLootboxModule.sol:1240-1261`), a **100-iteration `_queueTickets` loop** — measured
>    at **~5,396,350 gas for a single box**, ~60x the typical ~89k marginal. This is the true open
>    per-box worst case; it is RARE (boon weight 8; needs a sizeable box for boon budget; the
>    `LOOTBOX_CLAIM_THRESHOLD = 5 ether` corner raises it).
> 3. **The block-fit ceiling is 16.7M, not 30M.** Every "30M" reference below is corrected to the
>    16.7M effective gas-target ceiling; the DEFAULT box buy/open leg targets a ~9M average.
> 4. **The single `DOWORK_BATCH=100` should be SPLIT into `BUY_BATCH` + `OPEN_BATCH`** (sized in §5.1).
>
> The advance (`210,689`) and typical-open (`89,287`) marginals are UNCHANGED and remain correct.

---

## 0. Scope, peg target, and the CR-01 rule (load-bearing)

The break-even keeper bounty is a function of **measured worst-case marginal gas at 0.5 gwei**
(`AUTO_GAS_PRICE_REF`). It cannot be a guess and it must NOT be read off `forge test --gas-report`.
The `doWork()` router pays a single flat-per-tx bounty per the D-07 model (`AfKing.sol:869-903`):

```
unit       = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice     // level-invariant break-even BURNIE
buy  leg   = (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN  = unit * 3/2  // flat 1.5x per tx
advance    = unit * ADVANCE_RATIO_NUM * mult         = unit * 2 * mult
open leg   = (unit * min(opened, OPEN_KNEE)) / OPEN_KNEE           // 1x at/above knee, pro-rated below
```

The four calibration inputs this plan MEASURES are:

| Calibration input | What it sizes (331-04) |
|-------------------|------------------------|
| `router_dowork_buy_per_player_marginal_gas`  | the buy-leg break-even floor (per successful subscriber) |
| `router_dowork_open_per_box_marginal_gas`    | the open-leg break-even floor + the `OPEN_KNEE` small-batch corner |
| `router_dowork_advance_marginal_gas`         | the advance-leg break-even floor (the `mult` ladder rides on top) |
| `router_dowork_dispatch_overhead_gas`        | the once-per-tx router cost (predicate reads + `keeperSnapshot` mintPrice + the single `creditFlip`) |

**CR-01 rule (the load-bearing lesson from 319, `319-CR01-FIX.md`):** the per-item flat reward
MUST be pegged to the per-item **MARGINAL at N>=32**, never to a single-item TOTAL. A single-item
total bundles the whole per-tx fixed overhead into one item — at 319 this over-pegged the box reward
~2x (137_944 single-box total vs ~71_203 per-box marginal) and opened a Sybil self-crank faucet on
the multi-box path. The measured amortization gradient there was:
`N=1 -> 137,944 / N=8 -> 89,841 / N=16 -> 69,437 / N=32 -> 71,203` (converged at N>=32). This harness
measures buy and open at **N>=32**.

**Anti-exploit basis is REAL prevailing gas, NOT the 0.5 gwei peg ref** (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`):
the round-trip / faucet judgement (GAS-05, owned by `CrankFaucetResistance`) values the keeper's real
tx cost at 5-50+ gwei against the illiquid flip-credit reward valued at the 0.5 gwei peg. This document
sizes the peg; the faucet floor is proven separately.

---

## 1. BUY leg — per-subscriber `_autoBuy` worst case (theory-first)

### 1(a) The structural driver

`doWork()`'s highest-priority leg is `_autoBuy(DOWORK_BATCH)` (`AfKing.sol:875-878`). The per-call
fixed overhead (cursor SLOAD/SSTORE at `:570-573`/`:753`, the per-chunk memory buffers `:578-581`,
and the single batched `IGame.batchPurchase{value: totalValue}(...)` at `:774`) is paid ONCE per call.
The per-SUBSCRIBER marginal is the unit that bounds the buy-leg break-even.

### 1(b) The max-laden per-subscriber path

The heaviest per-subscriber path that ends in a real buy (the only path that earns a bounty) is:

1. NOT a cancel-tombstone (`dailyQuantity != 0`, `:605`) and NOT already-bought (`lastAutoBoughtDay < today`, `:620`) — so the cheap skips do not fire.
2. The renewal branch is NOT due (`paidThroughDay > today`, `:630`) — skips the day-31 `hasAnyLazyPass`/`burnForKeeper` extract. (Renewal day is a once-per-30-days event, not the steady-state per-buy marginal; it is bounded separately and is not the recurring per-tx cost the flat bounty reimburses.)
3. SUB-04 funding resolution `_resolveBuy` (`:676-680`, `:793-840`) on the **heaviest funding shape**: a `reinvestPct > 0` **drain-first** sub. This runs the GASOPT-03 `keeperSnapshot([player])` STATICCALL ONCE (`:807`) feeding BOTH the reinvest effective-quantity term (`:811-814`) AND the drain-first waterfall (`:826-838`). The drain-first `Combined` payKind (`:831`) is the richest mode (it moves both claimable + a residual ETH slice).
4. CEI debit `_poolOf[src] -= msgValue` (`:727`) + slice accumulation into the batch buffers (`:733-738`) + the `lastAutoBoughtDay` day-stamp (`:744`).
5. The amortized share of the single batched `batchPurchase` -> per-player `this._batchPurchaseUnit{value: slice}` (try/catch + slice) -> `_purchaseFor(player, 0, slice, bytes32("DGNRS"), payKind)` -> MintModule `purchase` (the mint -> affiliate -> lootbox-enqueue -> prize-pool -> EV-cap -> quest write chain).

### 1(c) The cap and WHY it is the maximum

- Per-subscriber work is bounded: there is no inner unbounded loop over a subscriber. The `_autoBuy`
  loop runs at most `maxCount` subscribers per call (`:562`; today `DOWORK_BATCH = 100`, recommended
  split to `BUY_BATCH = 50` in §5.1 so the whole buy leg stays under the 16.7M ceiling), and each
  subscriber contributes one slice. So the worst per-subscriber marginal is the heaviest single
  iteration, NOT a loop-amplified quantity.
- The reinvest+drain-first shape is the structural maximum because it is the ONLY shape that runs the
  extra `keeperSnapshot` read AND the richest `Combined` payment mode. A renewal-not-due / cheap-skip /
  tombstoned / lootbox-floor-skipped subscriber costs strictly less (each is an early `continue`).

### 1(d) THE LANDING-vs-REVERT distinction (the CORRECTION-PASS lesson — supersedes the prior 1(d))

The keeper buy is **forced lootbox** (`_batchPurchaseUnit -> _purchaseFor(player, 0, msg.value,
"DGNRS", payKind)`, ticketQuantity=0, `DegenerusGame.sol:1806`). The mint module floors a lootbox buy
at `LOOTBOX_MIN = 0.01 ether` (`DegenerusGameMintModule.sol:1011`: `if (lootBoxAmount != 0 &&
lootBoxAmount < LOOTBOX_MIN) revert E();`). A slice below 0.01 ether REVERTS — and because
`batchPurchase` isolates each player in `try this._batchPurchaseUnit{value: slice}() catch {}`
(`DegenerusGame.sol:1773-1780`), a reverting slice is silently skipped+refunded while AfKing's
`lastAutoBoughtDay` day-stamp (set at `:744`, BEFORE the batch fires) stays set. **A "landing" buy is
therefore one whose slice is >= 0.01 ether AND whose `lootboxEthBase[index][player]` first-deposit
signal becomes non-zero.** The original harness's funding shape (drain-first reinvest, claimable mp/2)
produced a `Combined`-mode slice of ~mp/2 ≈ 0.005 ETH < LOOTBOX_MIN → every buy reverted in the
try/catch, and the `40,224` figure was the revert-catch cost, NOT a real buy.

The corrected worst-case landing shape is a DirectEth, ticket-mode, qty-1 sub: cost = mp = 0.01 ether
== LOOTBOX_MIN (the guard is strict `<`, so exactly 0.01 lands), msgValue == slice == cost, first
deposit fires `enqueueBoxForAutoOpen`. The 319 shape-insensitivity finding still holds (reinvest
pre-warms the claimable slot, within ~5% of the DirectEth landing path), so DirectEth is the clean,
conservative LANDING marginal.

### 1(e) Worst-case-first prediction — CORRECTED

A LANDED keeper buy crosses the full mint -> affiliate (KEEP-04 DGNRS two-tier) -> lootbox-enqueue ->
prize-pool -> EV-cap -> quest write chain, plus the first-deposit `lootboxEthBase`/`lootboxPurchasePacked`
SSTOREs. Predicted O(240k-260k) gas per landed player — materially heavier than the typical box OPEN
marginal (~89k) because the buy WRITES the box that open later resolves. **BUY is the most expensive
per-item leg.** The WHOLE `_autoBuy(N)` of N landing subs at the recommended `BUY_BATCH` is the binding
batch-size constraint against the 16.7M ceiling (§5.1).

**FILLED BY CORRECTION PASS:** [see §5 measured table — buy ~261,809 whole-set / ~255,614 clean N=32]

---

## 2. OPEN leg — per-box `autoOpen` worst case (theory-first)

### 2(a) The structural driver

`doWork()`'s open leg is `IGame.autoOpen(DOWORK_BATCH)` (`AfKing.sol:888`). `DegenerusGame.autoOpen`
(`:1666-1704`) walks `boxPlayers[index]` from the self-partitioning `boxCursor`, opening each ready box
via `_autoOpenBox -> _openLootBoxFor` (the SAME `_resolveLootboxCommon` body as the bet path). The
per-tx fixed overhead (the `boxCursorIndex`/`boxCursor` SLOAD + conditional SSTORE `:1675-1678`, the
`lootboxRngWordByIndex[index]` gate SLOAD `:1683`, the final `boxCursor` SSTORE `:1703`) is paid ONCE
per call regardless of N. Plus the once-per-tx `creditFlip` in `doWork` itself (the dispatch leg).

### 2(b) The max-laden per-box branch — CORRECTED (the whale-pass gap)

The *reward* is one box per queue entry, but the *gas* is NOT flat across boxes. Every box-open runs
`_resolveLootboxCommon` → `_rollLootboxBoons` (`DegenerusGameLootboxModule.sol:1097-1103`), a
probabilistic boon roll whose chance scales with the box's `boonBudget` (∝ box amount, capped). One of
the rollable boons is the **whale pass (type 28, `BOON_WHALE_PASS`)**, which in `_applyBoon`
(`:1635-1641`) calls `_activateWhalePass` (`:1240-1261`) — a **100-iteration `_queueTickets` loop**
(40 tickets/lvl for the bonus band, 2 tickets/lvl thereafter). That loop is the heavy per-box branch
the original derivation wrongly excluded. There are TWO open-gas regimes:

1. **TYPICAL box** (no whale-pass boon, the overwhelmingly common case): the single-roll/double-roll
   `_resolveLootboxCommon` body — the ~89k N≥32 marginal (matches the prior measurement, unchanged).
2. **WHALE-PASS box** (the rare worst case): the 100-iter `_activateWhalePass` loop dominates —
   **~5,396,350 gas for a single box** (~60x the typical marginal). A box win above the
   `LOOTBOX_CLAIM_THRESHOLD = 5 ether` (`DegenerusGameStorage.sol:169`) raises the boon budget and
   thus the whale-pass roll chance; a 6-ETH box reliably reaches it under a forced seed.

> NOTE on the >5 ETH deferred path: the >`LOOTBOX_CLAIM_THRESHOLD` "defer to claim" branches at
> `DegenerusGameJackpotModule.sol:1966/2029` and `DegenerusGameDecimatorModule.sol:583` are the
> JACKPOT and DECIMATOR payout paths — they queue a deferred whale-pass claim and are CHEAP. They are
> NOT the per-box `autoOpen` path. The heavy branch reachable from a keeper box-open is the INLINE
> whale-pass BOON (type 28 → `_activateWhalePass` 100-iter loop), which materializes at open time.

### 2(c) The cap and WHY it is the maximum

- `autoOpen` opens at most `maxCount = OPEN_BATCH` boxes per call (caller-bounded, anti-DoS).
- The whale-pass box (§2(b).2) is the per-box maximum; the typical box (§2(b).1) is the per-box common
  case. The OPEN leg is sized so the TYPICAL leg averages ~9M (§5.1); the all-whale-pass worst case
  (`OPEN_BATCH × ~5.4M`) exceeds 16.7M and is **ACCEPTED by the USER** as statistically unreachable
  (whale-pass-boon rarity — a keeper would need every box in the batch to independently roll the
  weight-8 boon).
- The `OPEN_KNEE = 5` pro-rate (`AfKing.sol:890-891`) is the STRUCTURAL faucet-closer for the small-batch
  corner: a tiny mid-day open of `k < 5` boxes earns `unit * k / 5`, so a one-box self-crank earns
  `unit/5` — below a one-box tx's real gas (GAS-05 round-trip floor, proven by `CrankFaucetResistance`).

### 2(d) CR-01 application

Measure the per-box MARGINAL at N>=32 (`CrankOpenBoxWorstCaseGas.t.sol` Test D idiom), NEVER the
single-box total. 319 measured ~71,203 per-box marginal vs 137,944 single-box total — pegging to the
total was the CR-01 faucet defect. One open-box ~= one resolve spin neighborhood (~66-72k).

### 2(e) Worst-case-first prediction — CORRECTED

The TYPICAL per-box marginal lands ~89k (the resolve-spin neighborhood). The WHALE-PASS per-box cost is
~5.4M (the 100-iter loop). The OPEN leg is sized so the typical `autoOpen(OPEN_BATCH)` averages ~9M;
the all-whale-pass corner exceeds 16.7M and is USER-accepted (§2(c)).

**FILLED BY CORRECTION PASS:** [see §5 measured table — typical ~89,288, whale-pass ~5,396,350]

---

## 3. ADVANCE leg — `advanceGame()` mid-day partial-drain + new-day worst case (theory-first)

### 3(a) The structural driver

`doWork()`'s advance leg is `IGame.advanceGame()` (`AfKing.sol:881-884`); the router consumes the
returned `uint8 mult` (the USER-approved 330 collapse: a single `mult`, `mult == 0` = gameover/no-bounty
sentinel, NOT the 329-draft `(mult, rewardable)` tuple). The advance leg is a SINGLE call per `doWork`
(not a loop over N), so its calibration input is a single marginal, not a per-item amortized number.

### 3(b) The two rewardable advance shapes (USER 2026-05-26, CONTEXT)

Both count as router-rewardable advance-leg work:

1. **Mid-day partial-drain** (`day == dailyIdx`, tickets not fully processed): `advanceGame` runs
   `_runProcessTicketBatch(purchaseLevel)` and returns `mult = 1` (`AdvanceModule.sol:194-224`,
   `return mult` at `:218`; ADV-05/D-07 — no escalation mid-day). This drains a slice of the read-slot
   ticket queue — the per-call structural cost is one `processTicketBatch` budget slice.
2. **New-day advance** (`day != dailyIdx`): the daily-drain gate + the `rngGate` RNG request/finalize +
   the stage machine (`:226-283+`). The day-epoch stall multiplier writes `mult` straight into the
   return (`:229-242`): `mult = 2` after 20 min, `4` after 1 h, `6` after 2 h; default `1`. The router
   scales the re-homed advance bounty by this `mult` (`unit * 2 * mult`).

### 3(c) The worst case and WHY it is the maximum

The heaviest advance leg is the new-day path that runs the full daily-drain gate (`processTicketBatch`
to finish the read slot, `:247-270`) AND the `rngGate` request/finalize machinery. The mid-day
partial-drain is a strict subset (it runs only the read-slot drain, no RNG request). For the BREAK-EVEN
PEG the relevant marginal is the **base advance cost at `mult = 1`** — the `mult` ladder is a deliberate
multiplier ON TOP of the base, not part of the base gas, so the peg sizes the base and the ladder rides
on it (GAS-04: the stall ladder stays advance-only, faucet-bounded). The harness measures the largest
single advance step it can construct on the fresh fixture and asserts the day actually advanced
(non-vacuity) and that the step fits the 16.7M ceiling.

### 3(d) The `mult == 0` gameover sentinel

When `advanceGame` takes the gameover path it returns `mult = 0` (`AdvanceModule.sol:185-187`) and
`doWork` pays NO bounty (`AfKing.sol:883-884`) — the flip-credit coin is worthless at gameover. The
harness need not measure this (it pays zero); it is documented as the no-bounty sentinel.

### 3(e) Worst-case-first prediction

A single advance step (the heaviest realizable on the fresh fixture) is bounded well under 16.7M; the
305-winner daily-jackpot single-call ceiling was proven ~7.5M at v46 Phase 319 (JGAS-04), and the
advance leg here is the same machinery minus the removed split. Predicted single-step advance marginal
O(100k-1M) depending on how much queue drain the constructed step performs; the calibration uses the
measured base step.

**FILLED BY Task 2:** [see §5 measured table]

---

## 4. DISPATCH overhead — the bare `doWork()` router cost (theory-first)

### 4(a) The structural driver

`doWork()` (`AfKing.sol:868-904`) pays, EVERY call, regardless of which leg runs:

- `mintPrice()` read (`:869`) — one cross-contract STATICCALL into GAME.
- the `unit` arithmetic (`:870`).
- the O(1) routing predicates evaluated in priority order until the first hits:
  `_autoBuyDay != _currentDay() || _autoBuyCursor < _subscribers.length` (`:875`, two SLOADs + a
  `_currentDay` timestamp read), else `advanceDue()` (`:881`, a cross-contract view: `_simulatedDayIndex`
  vs `dailyIdx` + the `ticketQueue[...].length` read, `DegenerusGame.sol:1627-1639`), else
  `boxesPending()` (`:887`, `rngLockedFlag` + `lootboxRngWordByIndex[index]` + `boxPlayers[index].length`
  vs `boxCursor`, `:1645-1651`).
- the SINGLE `creditFlip(msg.sender, bountyEarned)` (`:901-902`), CEI-last, once per tx.

> NOTE on `keeperSnapshot`: the dispatch path itself does NOT call `keeperSnapshot` — the snapshot is
> read INSIDE `_resolveBuy` per buying subscriber (`AfKing.sol:807`), so its cost lives in the buy-leg
> per-player marginal (§1), not the dispatch overhead. The dispatch overhead's only GAME read is
> `mintPrice()` + the routing predicate views + the one `creditFlip`. (The PLAN's §4 mention of
> "keeperSnapshot mintPrice read" reconciles to this `mintPrice()` STATICCALL; the per-player snapshot
> is buy-leg, not dispatch.)

### 4(b) The cap and WHY it is the maximum

The dispatch overhead is O(1) — no loop. Its maximum is a `doWork()` call that evaluates all the cheap
predicates and pays the one `creditFlip`. The harness ISOLATES it by measuring a `doWork()` whose chosen
leg performs the minimum real work (so the measured number is dominated by the dispatch + the
once-per-tx `creditFlip`), and cross-checks it against the bare predicate + `creditFlip` cost. The
dispatch overhead is the per-tx fixed cost that the flat-per-tx bounty model AMORTIZES across the leg's
items (exactly why the per-item peg uses the N>=32 marginal, not the single-item total — CR-01).

### 4(c) Worst-case-first prediction

Dispatch overhead O(30k-60k) (a cold `creditFlip` ~20k+ plus the cross-contract `mintPrice` + predicate
views). It is the once-per-tx floor the keeper pays before any leg work; the break-even peg must keep
`leg_marginal + dispatch_share` reimbursable at 0.5 gwei without over-paying the small-batch corner
(the `OPEN_KNEE` closes that for opens; the flat 1.5x buy / 2x advance ratios are sized so a single-tx
keeper is break-even, not faucet-positive).

**FILLED BY CORRECTION PASS:** dispatch overhead rises to ~568,870 with a REAL landing buy (vs the
old 228,084 which folded in a revert-catch buy). [see §5 measured table]

---

## 5. MEASURED MARGINALS (CORRECTION PASS — `forge test --match-path test/gas/RouterWorstCaseGas.t.sol --isolate`, 7/7 PASS)

Measured against the live `63bc16ca` tree (foundry 1.6.0-nightly, `--isolate`; harness commit
`322fd972`). Every number is emitted as a `log_named_uint` the 331-04 calibration reads. **The buy +
whale-pass-open rows are the CORRECTED values; the old buy ~40,224 (revert-catch) and the
"no heavier per-box branch" claim are RETRACTED (see the §0 correction banner).**

| Calibration input | Measured gas | N | < 16.7M ceiling | Non-vacuity asserted (CORRECTED) |
|-------------------|--------------|---|-----------------|----------------------------------|
| `router_dowork_buy_per_player_marginal_gas`  | **261,809** (clean N32 255,614) | 32 | yes (whole leg 8,377,899 < 16.7M) | each sub's buy LANDED (`lootboxEthBase[index][player] > 0`) |
| `router_dowork_open_per_box_marginal_gas` (TYPICAL) | **89,288** | 32 | yes (whole leg 2,857,216 < 16.7M) | each box's first-deposit signal zeroed |
| `router_dowork_open_whale_pass_box_marginal_gas` (RARE WORST CASE) | **5,396,350** | 1 | yes for ONE box; `OPEN_BATCH × 5.4M` exceeds 16.7M (USER-ACCEPTED, §2(c)) | the type-28 `LootBoxWhalePassJackpot` event fired |
| `router_dowork_advance_marginal_gas`         | **210,689** | 1 (single advance step, no loop-N) | yes (211k < 16.7M) | game entered rngLock / day moved |
| `router_dowork_dispatch_overhead_gas`        | **568,870** | 1 (doWork + minimal LANDING buy + creditFlip) | yes (569k < 16.7M) | doWork ran the buy leg and the buy LANDED |

> **Dispatch-overhead note (conservative ceiling, CORRECTED):** `router_dowork_dispatch_overhead_gas =
> 568,870` is now the cost of a `doWork()` whose buy leg performs ONE REAL LANDING buy (slice >=
> LOOTBOX_MIN) over the fresh-day cursor walk + one `creditFlip`. The old 228,084 folded in a buy that
> REVERTED in the try/catch — i.e. it understated the real once-per-tx-plus-one-landing-buy cost. The
> figure remains an over-estimate of the PURE routing+creditFlip overhead (331-04 recovers it by
> subtracting the §1 single-player buy marginal) and never UNDER-states the dispatch floor.

### N-amortization gradient (CR-01 convergence evidence) — CORRECTION PASS

The single-item TOTAL (N=1) bundles the per-tx fixed overhead into one item; the converged marginal
(N>=32) amortizes it away. The CORRECTED buy gradient (every measured buy LANDS, verified via
`lootboxEthBase > 0`):

| Leg | N=1 (single-item total) | N=8 | N>=32 (converged marginal) | over-statement N1/N32 |
|-----|-------------------------|-----|----------------------------|------------------------|
| buy (LANDING) | 484,194 | 269,222 | 255,614 | ~1.89x |
| open (typical) | 180,221 | 105,947 | 85,967 | ~2.10x |

> The whole-set buy test divides by N=32 over a set that includes the 2 deploy subs, so its per-player
> number (261,809) is marginally above the clean N=32 gradient figure (255,614) — the conservative
> direction. 331-04 may use either; both sit in the ~256-262k LANDING buy-marginal band (the task's
> ~244,158 reference is the same order of magnitude; the small spread is fixture/measurement detail —
> all confirm BUY is ~6x the typical-open marginal, NOT below it).

---

## 5.1 SPLIT-CAP SIZING — the recommended `BUY_BATCH` + `OPEN_BATCH` (for the gated 331-05)

`AfKing.sol:847` currently has a SINGLE `DOWORK_BATCH = 100` used for BOTH `_autoBuy(DOWORK_BATCH)`
(`:876`) and `autoOpen(DOWORK_BATCH)` (`:888`). With the corrected marginals the two legs have very
different per-item costs (buy ~262k vs typical-open ~89k), so a single cap is wrong: a 100-deep buy
batch is ~26M (over the 16.7M HARD ceiling), while a 100-deep typical-open batch is ~9M (the target).
**Recommendation: SPLIT into two constants.**

| New constant | HARD/SOFT | Sizing rule | Math | **Recommended literal** |
|--------------|-----------|-------------|------|-------------------------|
| `BUY_BATCH`  | **HARD ≤ 16.7M** | `BUY_BATCH × buy_marginal ≤ 16.7M`; margin-safe | 16.7M / 261,809 ≈ 63.8 → margin-safe (~22% headroom) | **`50`** (50 × 261,809 ≈ 13.09M < 16.7M) |
| `OPEN_BATCH` | SOFT (~9M typical avg) | `OPEN_BATCH × typical_open_marginal ≈ 9M` | 9M / 89,288 ≈ 100.8 | **`100`** (100 × 89,288 ≈ 8.93M ≈ 9M target) |

- **`BUY_BATCH = 50` is HARD-bounded:** at the corrected ~261,809 marginal, 50 buys = ~13.09M, leaving
  ~3.6M (≈22%) headroom under 16.7M. The ceiling-touching N would be ~63; 50 is the margin-safe pick
  inside the requested ~50-60 band. **Buys must NEVER exceed 16.7M** (a reverting batch would brick
  the keeper's buy leg for the day), so the HARD bound is enforced by capping the per-call buy count.
- **`OPEN_BATCH = 100` sizes the TYPICAL open leg to ~9M:** 100 typical boxes ≈ 8.93M. The all-whale-
  pass corner (100 × ~5.4M ≈ 540M) blows the ceiling — but it is **USER-ACCEPTED as statistically
  unreachable** (each box must independently roll the weight-8 whale-pass boon; the probability of all
  100 doing so is vanishingly small, and a keeper batching into it would simply run out of gas and
  re-try a smaller count, which is liveness-safe — the open leg has no CEI debit that a partial open
  could strand). Documented here so 331-05's comment strike reflects the split.

> **Note for 331-05:** the split changes the §8 diff from "comment-only / NO-OP" to a REAL (still
> gated) edit — `DOWORK_BATCH` is replaced by `BUY_BATCH = 50` + `OPEN_BATCH = 100`, with the two call
> sites (`:876`, `:888`) re-pointed. This is a behavioral change (buy batches shrink from 100→50) and
> MUST land under the USER-approved 331-05 gate; it is NOT applied in this correction pass.

---

## 6. Slot-layout attestation (T-331-02, re-confirmed vs `63bc16ca` this session)

`forge inspect DegenerusGame storage` + `forge inspect AfKing storage` against the live tree confirm
the slot constants the harness injects (the 330 diff added the box cursors at NEW slots 62/63, NOT
the `:1548-1559` the PATTERNS comment guessed):

| Symbol | Contract | Slot | Note |
|--------|----------|------|------|
| `prizePoolsPacked`       | DegenerusGame | 2  | (future << 128) \| next |
| `claimableWinnings`      | DegenerusGame | 7  | mapping root |
| `lootboxEthBase`         | DegenerusGame | 22 | mapping(uint48 => mapping(address => uint256)) root |
| `lootboxRngPacked`       | DegenerusGame | 37 | low 48 bits = lootboxRngIndex |
| `lootboxRngWordByIndex`  | DegenerusGame | 38 | mapping root |
| `degeneretteBets`        | DegenerusGame | 45 | mapping root |
| `degeneretteBetNonce`    | DegenerusGame | 46 | mapping root |
| `boxCursor`              | DegenerusGame | 62 | uint48 @ offset 0 (NEW in 330) |
| `boxCursorIndex`         | DegenerusGame | 62 | uint48 @ offset 6 (NEW in 330) |
| `boxPlayers`             | DegenerusGame | 63 | mapping(uint48 => address[]) root (NEW in 330) |
| `_poolOf`                | AfKing | 0 | mapping root |
| `_subOf`                 | AfKing | 1 | mapping root (one packed Sub slot) |
| `_subscribers`           | AfKing | 2 | address[] |
| `_subscriberIndex`       | AfKing | 3 | mapping root (1-indexed) |
| `_autoBuyDay`            | AfKing | 4 | uint32 @ offset 0 |
| `_autoBuyCursor`         | AfKing | 4 | uint224 @ offset 4 |

A stale slot would write garbage and produce a fake marginal — every `vm.store`/`vm.load` in the harness
keys off this table.

---

## 7. Out of scope for THIS plan (331-01)

- Landing the calibrated constants in `AfKing.sol`/`DegenerusGame.sol` (the USER-gated contract diff) —
  that is 331-04/05 under the second USER-approved gate (the v46 Phase 319 precedent).
- The GAS-05 round-trip / faucet floor proof — `CrankFaucetResistance` (a separate plan).
- `RESOLVE_FLAT_BURNIE` (GAS-06) — a separate flat-literal re-peg, sized against real 3-resolution gas,
  not this router-marginal harness.

This plan MEASURES the four router marginals and records them as the 331-04 calibration input. Nothing
in this plan touches `contracts/*.sol`.
