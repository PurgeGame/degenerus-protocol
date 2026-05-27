# 331 GAS-01 — Keeper-Router Worst-Case Marginal Gas Derivation

**Phase:** 331 (GAS — worst-case marginal derivation + break-even @0.5 gwei peg calibration)
**Plan:** 331-01
**Subject:** the committed 330 IMPL keeper-router diff (`63bc16ca`) — `AfKing.doWork()` (`AfKing.sol:868`) + `_autoBuy` (`:561`) + `DegenerusGame.autoOpen` (`:1666`) + `DegenerusGameAdvanceModule.advanceGame` (`:154`).
**Method:** theory-FIRST (this document), then measure (`test/gas/RouterWorstCaseGas.t.sol`) per `feedback_gas_worst_case`.
**Analog:** v46 Phase 319 `319-GAS-DERIVATION.md` — this is the same derive-then-measure pass repeated one phase up for the v49 router.

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
  loop runs at most `maxCount = DOWORK_BATCH = 100` subscribers per call (`:562`), and each subscriber
  contributes one slice. So the worst per-subscriber marginal is the heaviest single iteration, NOT a
  loop-amplified quantity.
- The reinvest+drain-first shape is the structural maximum because it is the ONLY shape that runs the
  extra `keeperSnapshot` read AND the richest `Combined` payment mode. A renewal-not-due / cheap-skip /
  tombstoned / lootbox-floor-skipped subscriber costs strictly less (each is an early `continue`).

### 1(d) EMPIRICAL CORRECTION carried from 319 (Rule 1 — measured mechanism vs paper claim)

`SweepPerPlayerWorstCaseGas.t.sol` (319) empirically FALSIFIED the paper claim that the reinvest path
is "strictly heavier": the keeper's lootbox-mode buy is gas-FLAT in the slice (materialization is at
crank-OPEN time, a separate leg), and the SUB-04 `claimableWinningsOf`/`keeperSnapshot` read pre-WARMS
the `claimableWinnings[player]` slot the buy re-reads, making the reinvest sub marginally CHEAPER. The
faithful claim is therefore that the per-player buy marginal is **shape-insensitive** (reinvest within
~5% of typical). The buy harness here re-confirms this and uses the (over-estimating, conservative)
whole-set average divided by the test-sub count, so the calibration floor is never under-stated.

### 1(e) Worst-case-first prediction

The per-successful-player buy marginal lands in the ticket/lootbox mint-path neighborhood — a single
mint slice through `_purchaseFor` with its affiliate-write chain. Predicted O(150k-300k) gas per player
(an order above a bare resolve spin because it crosses the full mint->affiliate->prize-pool path), and
the WHOLE `_autoBuy(N)` of N healthy subs is far below the 30M mainnet block bar at any realizable N
the keeper would batch.

**FILLED BY Task 2:** [see §5 measured table]

---

## 2. OPEN leg — per-box `autoOpen` worst case (theory-first)

### 2(a) The structural driver

`doWork()`'s open leg is `IGame.autoOpen(DOWORK_BATCH)` (`AfKing.sol:888`). `DegenerusGame.autoOpen`
(`:1666-1704`) walks `boxPlayers[index]` from the self-partitioning `boxCursor`, opening each ready box
via `_autoOpenBox -> _openLootBoxFor` (the SAME `_resolveLootboxCommon` body as the bet path). The
per-tx fixed overhead (the `boxCursorIndex`/`boxCursor` SLOAD + conditional SSTORE `:1675-1678`, the
`lootboxRngWordByIndex[index]` gate SLOAD `:1683`, the final `boxCursor` SSTORE `:1703`) is paid ONCE
per call regardless of N. Plus the once-per-tx `creditFlip` in `doWork` itself (the dispatch leg).

### 2(b) The max-laden per-box branch

The per-box reward is FLAT (one box per queue entry), so there is no multi-spin amplification inside a
single box. The per-box maximum is a single READY, un-opened box that actually MATERIALIZES (the
first-deposit signal `lootboxEthBase[index][player] != 0` present so the `:1695` cheap-skip does NOT
fire, the index RNG-ready so the `:1683` whole-index early-return does NOT fire). A box the
`RngNotReady` (`:1683`) or already-opened (`:1695`) guards skip costs only a cheap SLOAD, strictly less
than a real open.

### 2(c) The cap and WHY it is the maximum

- `autoOpen` opens at most `maxCount = DOWORK_BATCH = 100` boxes per call (caller-bounded, anti-DoS).
- A single materialization is the per-box maximum by construction: there is no heavier per-box branch
  (the box reward is flat; the lootbox-conversion body is the same regardless of which box).
- The `OPEN_KNEE = 5` pro-rate (`AfKing.sol:890-891`) is the STRUCTURAL faucet-closer for the small-batch
  corner: a tiny mid-day open of `k < 5` boxes earns `unit * k / 5`, so a one-box self-crank earns
  `unit/5` — below a one-box tx's real gas (GAS-05 round-trip floor, proven by `CrankFaucetResistance`).

### 2(d) CR-01 application

Measure the per-box MARGINAL at N>=32 (`CrankOpenBoxWorstCaseGas.t.sol` Test D idiom), NEVER the
single-box total. 319 measured ~71,203 per-box marginal vs 137,944 single-box total — pegging to the
total was the CR-01 faucet defect. One open-box ~= one resolve spin neighborhood (~66-72k).

### 2(e) Worst-case-first prediction

The per-box marginal lands ~70k (the resolve-spin neighborhood), materially below the single-box total.
The WHOLE `autoOpen(N)` of N ready boxes is far below 30M for any N the keeper batches.

**FILLED BY Task 2:** [see §5 measured table]

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
(non-vacuity) and that the step fits 30M.

### 3(d) The `mult == 0` gameover sentinel

When `advanceGame` takes the gameover path it returns `mult = 0` (`AdvanceModule.sol:185-187`) and
`doWork` pays NO bounty (`AfKing.sol:883-884`) — the flip-credit coin is worthless at gameover. The
harness need not measure this (it pays zero); it is documented as the no-bounty sentinel.

### 3(e) Worst-case-first prediction

A single advance step (the heaviest realizable on the fresh fixture) is bounded well under 30M; the
305-winner daily-jackpot single-call ceiling was proven ~7.5M < 30M at v46 Phase 319 (JGAS-04), and the
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

**FILLED BY Task 2:** [see §5 measured table]

---

## 5. MEASURED MARGINALS (FILLED BY Task 2)

> Populated from `test/gas/RouterWorstCaseGas.t.sol` `--isolate` emitted `log_named_uint` values.
> Until Task 2 runs this section is a placeholder.

| Calibration input | Measured gas (N) | < 30M mainnet | Non-vacuity asserted |
|-------------------|------------------|---------------|----------------------|
| `router_dowork_buy_per_player_marginal_gas`  | _PENDING (Task 2)_ | _PENDING_ | _PENDING_ |
| `router_dowork_open_per_box_marginal_gas`    | _PENDING (Task 2)_ | _PENDING_ | _PENDING_ |
| `router_dowork_advance_marginal_gas`         | _PENDING (Task 2)_ | _PENDING_ | _PENDING_ |
| `router_dowork_dispatch_overhead_gas`        | _PENDING (Task 2)_ | _PENDING_ | _PENDING_ |

### N-amortization gradient (CR-01 convergence evidence) — FILLED BY Task 2

| Leg | N=1 (single-item total) | N=8 | N>=32 (converged marginal) |
|-----|-------------------------|-----|----------------------------|
| buy  | _PENDING_ | _PENDING_ | _PENDING_ |
| open | _PENDING_ | _PENDING_ | _PENDING_ |

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
