# Phase 319 — GAS-01 Worst-Case-FIRST Gas Derivation (paper-first)

**Authored:** 2026-05-24
**Contract HEAD:** `0d9d321f` (contracts/ clean; every cited `file:line` source-verified this session)
**Methodology rule:** `feedback_gas_worst_case` — derive the theoretical worst case from SOURCE (enumerate SLOADs / SSTOREs / external-call depth / loop bounds / events) BEFORE any measurement. Measurement is Wave-2 (Plans 02/03); this doc is the "derive" half and it CONSTRAINS the harnesses by writing each harness's assert-is-worst-case precondition into the derivation up front.
**Security floor:** `feedback_security_over_gas` — no number in this doc justifies weakening a guard. The structural costs below INCLUDE the load-bearing guards (RngNotReady freeze, one-reward delete/zero, per-item try/catch) precisely because they are mandatory; they are never the optimization target.

> **Precedent format.** This mirrors the JGAS-03 "Worst-Case Gas Derivation" section in `.planning/phases/318-*/318-06-SUMMARY.md` (the 305-winner daily-ETH derivation, measured 7,503,715 gas), which itself follows the `306-05-GAS-BASELINE.md` derivation-doc precedent cited in `319-PATTERNS.md` §"No Analog Found". Structure per work-type: (a) cost-center `file:line` chain, (b) structural cost as a count of cold/warm SLOAD/SSTORE + delegatecall depth + loop bound + events (NOT a benchmarked number), (c) WHY the constructed scenario IS the maximum + the assert-is-worst-case precondition the Wave-2 harness checks BEFORE bracketing the call, (d) the named harness.

> **Structural floor caveat (applies to all three sections).** A structural opcode/SLOAD/SSTORE count UNDER-counts wall-clock gas: it omits viaIR codegen overhead, memory expansion, calldata cost, event topic/data byte cost, and the warm/cold transitions the surrounding loop state induces. So **measured > structural is EXPECTED** — the derivation is the lower-bound floor that fixes the SCENARIO (the 10-spin all-match, the single materialization, the reinvest sweep player), and the Wave-2 harness measures the actual gas of THAT scenario. The derivation's job is to guarantee the harness measures the true maximum, not to predict the exact number.

---

## Constants the worst cases are pinned to (source-verified)

| Constant | Value | Source | Role in the worst case |
|----------|-------|--------|------------------------|
| `MAX_SPINS_PER_BET` | `10` | `DegenerusGameDegeneretteModule.sol:226` | Hard upper bound on the resolve-bet spin loop `_resolveFullTicketBet` — the resolve-bet worst case is a single bet with `ticketCount == 10`, every spin winning. |
| `DAILY_ETH_MAX_WINNERS` | `305` | JackpotModule (cited 318-06) | Hard cap on the daily-ETH jackpot single call — the JGAS-04 worst case is the 305-winner max-scale call (buckets 159/95/50/1). |
| `CRANK_RESOLVE_BET_GAS_UNITS` | `120_000` (PLACEHOLDER) | `DegenerusGame.sol:1501` | The bet reward peg — calibrated in Plan 05 to the **per-1-spin-item MARGINAL**, NOT the 10-spin worst case (see §1 calibration-target distinction). |
| `CRANK_OPEN_BOX_GAS_UNITS` | `120_000` (PLACEHOLDER) | `DegenerusGame.sol:1502` | The box reward peg — calibrated to the **single-box marginal** (flat). |
| `CRANK_GAS_PRICE_REF` | `0.5 gwei` | `DegenerusGame.sol:1495` | FINAL/locked — never touched. The reward is `gasUnits · 0.5 gwei → BURNIE`, a FIXED constant (REW-03), never `gasleft()`/`tx.gasprice`. |
| `MAINNET_BLOCK_GAS_LIMIT` | `30_000_000` | harness constant (clone `JackpotSingleCallCorrectness.t.sol:80-82`) | The REAL fit bound. `foundry.toml` inflates `block_gas_limit` to `30_000_000_000` (30B) so multi-level integration tests run; every worst-case-fit assertion must use the real **30M**, not the inflated config. |

---

## §1 — RESOLVE-BET worst case (the headline cost center)

### (a) Cost-center `file:line` chain

`crankBets(address[] players, uint64[] betIds)` — `DegenerusGame.sol:1543`
- reads `lvl = _activeTicketLevel()` **ONCE** before the loop — `DegenerusGame.sol:1555` (GAS-02 read-once)
- probe item 0: `if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken()` — `DegenerusGame.sol:1552` (G5 double-crank short-circuit; reuses the SLOAD item 0 needs anyway)
- per item: `try this._crankResolveBet(players[i], betIds[i])` — `DegenerusGame.sol:1562` (onlySelf, `:1641` — G7/G9 per-item isolation + authority)
  - delegatecall `resolveBets(player, [betId])` — `DegenerusGameDegeneretteModule.sol:389`
    - `_resolveBet` — `DegenerusGameDegeneretteModule.sol:553`
      - `_resolveFullTicketBet` — `DegenerusGameDegeneretteModule.sol:561`
        - `rngWord = lootboxRngWordByIndex[index]`; `if (rngWord == 0) revert RngNotReady()` — `:578` (**G1 RNG-freeze guard — load-bearing, never removed**)
        - `delete degeneretteBets[player][betId]` — `:580` (**G3 one-reward-per-item — load-bearing**)
        - **spin loop `0 .. ticketCount-1`**, `ticketCount <= MAX_SPINS_PER_BET = 10` — `DegenerusGameDegeneretteModule.sol:226`
          - per WINNING spin: `_distributePayout(...)` — `DegenerusGameDegeneretteModule.sol:705`
            - ETH tier split → future-prize-pool SSTORE + `_addClaimableEth(beneficiary, weiAmount)` (2-arg, post-RM-02) — `DegenerusGameDegeneretteModule.sol:1117` → `claimablePool += ...` SSTORE + `_creditClaimable` SSTORE
            - if lootboxShare > 0: `_resolveLootboxDirect(...)` — `DegenerusGameDegeneretteModule.sol:783`
              - DELEGATECALL `resolveLootboxDirect` — `DegenerusGameLootboxModule.sol:628`
                - `_resolveLootboxCommon` — `DegenerusGameLootboxModule.sol:917`
                  - targetLevel roll + EV-cap (`_applyEvMultiplierWithCap`)
                  - **nested DELEGATECALL → BoonModule `consumeActivityBoon`** — `DegenerusGameLootboxModule.sol:992`
                  - `_queueTickets(player, targetLevel, whole, false)` SSTORE — `DegenerusGameLootboxModule.sol:1024`
                  - events: `LootBoxOpened` / `LootBoxReward`
- after loop: `if (reward != 0) coinflip.creditFlip(msg.sender, reward)` — `DegenerusGame.sol:1578` (**ONE creditFlip/tx — GAS-02**)

### (b) Structural per-item cost (the constructed maximum: one bet, `ticketCount = 10`, EVERY spin wins ETH above the lootbox-conversion threshold)

| Component | Count per worst-case item | Notes |
|-----------|---------------------------|-------|
| Spin-loop iterations | **10** (`= MAX_SPINS_PER_BET`) | the loop bound; each iteration is a full winning spin |
| `delete degeneretteBets[player][betId]` (G3) | 1 SSTORE (slot → 0) | one-reward guard, once per bet |
| future-prize-pool SSTORE | 10 (1 per winning spin) | ETH tier split |
| `_addClaimableEth` → `claimablePool` SSTORE + `_creditClaimable` SSTORE | 10 × 2 = 20 SSTORE | 2-arg post-RM-02 path falls straight to `_creditClaimable` |
| `_resolveLootboxDirect` delegatecall depth | 10 × **2-level** (`_resolveLootboxDirect` → LootboxModule, then nested BoonModule) | the deep cost — up to a 2-3-level delegatecall chain per spin |
| `_queueTickets` SSTORE | 10 (1 per materialization) | the ticket-queue write inside `_resolveLootboxCommon` |
| events | 10 × (`FullTicketResult` + `LootBoxOpened`/`LootBoxReward`) | event data/topic bytes (uncounted structurally, inflate measured) |
| `creditFlip` | 1 (after the loop) | GAS-02 one-per-tx |

So the resolve-bet worst case = **10 lootbox materializations** (10× a single open-box, see §2) plus 10× the ETH-credit SSTOREs plus the bet-delete plus one creditFlip. It is THE cost center: ~10× a single box.

### (c) Why this IS the maximum + the assert-is-worst-case precondition

- The spin loop cannot exceed `MAX_SPINS_PER_BET = 10` (`:226`) — `ticketCount` is a `uint8` decoded from packed bet data and the placement path caps it. So 10 is the structural ceiling per bet.
- Each spin's most expensive branch is the ETH-win-above-threshold path that triggers `_resolveLootboxDirect` (the 2-level delegatecall + `_queueTickets` SSTORE + nested BoonModule call). A losing spin or a sub-threshold win skips that branch. Therefore "every spin wins ETH above the lootbox-conversion threshold" is the per-spin maximum, and 10 of them is the per-bet maximum.
- A multi-item `crankBets` call scales linearly (each item independent under the per-item try/catch), so the per-ITEM worst case is the unit that bounds any batch; the harness measures one worst-case item to isolate it.
- **Assert-is-worst-case precondition (the harness checks BEFORE bracketing the call):** decode the placed bet and `assertEq(ticketCount, MAX_SPINS_PER_BET)` (i.e. `== 10`), and assert the bet is crafted all-match so every spin takes the ETH-above-threshold lootbox branch (per RESEARCH lines 99-128). Only after both hold does the harness bracket `crankBets` with `gasleft()` and assert `gasUsed < MAINNET_BLOCK_GAS_LIMIT`.

### (d) Named harness

`CrankResolveBetWorstCaseGas` (`test/gas/CrankResolveBetWorstCaseGas.t.sol`, Plan 02) — live `DeployProtocol` fixture (the crank writes Game storage, so a module-extending harness will not work here, unlike the jackpot). Clones the `CrankFaucetResistance.t.sol` crank fixture (RNG-index seed + post-placement word inject + self-operator-approval) + the `RedemptionGas.t.sol` `gasleft()`-delta idiom.

### (e) CALIBRATION-TARGET DISTINCTION (load-bearing — Plan 05 calibrates against THIS, not the worst case)

The 10-spin all-match is the GAS-01 worst case to **MEASURE**. It is NOT the peg-calibration target. The contract pays a **FLAT per-item reward** (`DegenerusGame.sol:1567-1570`: `reward += _ethToBurnieValue(CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF, priceForLevel(lvl))`) regardless of how many spins won — so a 10-spin all-match bet UNDER-reimburses the cranker. This is the deliberate REW-03 reading ("the bet reward is pegged to per-spin gas… accepting big-win under-reimbursement; those resolves are owner-motivated anyway").

Therefore `CRANK_RESOLVE_BET_GAS_UNITS` is calibrated (Plan 05) to the **per-1-spin-item MARGINAL** gas — the marginal cost of adding one typical (1-spin) resolve item to `crankBets` (RESEARCH Open Question A4, RESOLVED: per-1-spin-item marginal). Pegging to the 10-spin worst case would OVER-reimburse and risk opening the SAFE-01 self-crank Sybil faucet (the hard floor: `gasUnits · 0.5 gwei → BURNIE` reward must NOT exceed the cranker's marginal gas cost; self-crank round-trip ≤ 0). The 318-02 `CrankFaucetResistance` round-trip-≤0 proof must stay green at the calibrated value. Plan 02 supplies BOTH numbers: the 10-spin worst case (fit-check) and the per-1-spin-item marginal (Test B, the calibration input).

---

## §2 — OPEN-BOX worst case

### (a) Cost-center `file:line` chain

`crankBoxes(uint256 maxCount)` — `DegenerusGame.sol:1592`
- `index = _lrRead(...)`; day/index-reset cursor — `DegenerusGame.sol:1593-1598`
- `if (lootboxRngWordByIndex[index] == 0) return` — `DegenerusGame.sol:1603` (**G2 orphan-index / RngNotReady skip — the v45 VRF-rotation landmine; load-bearing, never removed**)
- reads `lvl = _activeTicketLevel()` **ONCE** before the loop — `DegenerusGame.sol:1610` (GAS-02 read-once)
- `while (cursor < qlen && opened < maxCount)` — `DegenerusGame.sol:1612` (caller-bounded by `maxCount`, anti-DoS)
  - `if (lootboxEthBase[index][player] == 0) continue` — `DegenerusGame.sol:1618` (**G4 already-opened/one-reward skip — load-bearing**)
  - `try this._crankOpenBox(index, player)` — `DegenerusGame.sol:1620` (onlySelf `:1662` — G7/G9 isolation + authority)
    - `_openLootBoxFor(player, index)` → the SAME `_resolveLootboxCommon` body — `DegenerusGameLootboxModule.sol:917` (targetLevel roll + EV-cap + nested BoonModule delegatecall `:992` + `_queueTickets` SSTORE `:1024` + events)
- `boxCursor = uint48(cursor)` — `DegenerusGame.sol:1631` (one SSTORE)
- `if (reward != 0) coinflip.creditFlip(msg.sender, reward)` — `DegenerusGame.sol:1632` (**ONE creditFlip/tx — GAS-02**)

### (b) Structural per-box cost (the constructed maximum: one ready box, one materialization)

| Component | Count per worst-case box | Notes |
|-----------|--------------------------|-------|
| `_resolveLootboxCommon` body | 1 | identical body to the bet path's per-spin materialization |
| targetLevel roll + EV-cap | 1 | `_applyEvMultiplierWithCap` |
| nested BoonModule delegatecall | 1 (1-level) | `consumeActivityBoon` — `:992` |
| `_queueTickets` SSTORE | 1 | the ticket-queue write |
| events | `LootBoxOpened` / `LootBoxReward` | |
| `boxCursor` SSTORE | 1 (after the loop) | cursor advance |
| `creditFlip` | 1 (after the loop) | GAS-02 one-per-tx |

The per-box materialization is exactly **one** `_resolveLootboxCommon` execution — so a single resolve-bet spin (§1) ≈ one open-box, and the resolve-bet worst case (10 spins) ≈ **10× a single box**. The two peg constants therefore differ markedly, and the per-spin/per-box lens is the correct calibration framing.

### (c) Why this IS the maximum + the assert-is-worst-case precondition

- The reward per box is FLAT (`CRANK_OPEN_BOX_GAS_UNITS · 0.5 gwei`), so there is no multi-spin amplification inside a single box — one materialization is the per-box maximum by construction.
- A box that the RngNotReady (G2) or already-opened (G4) guards skip costs only the cheap SLOAD skip, which is strictly less than a real materialization; so a single READY, un-opened box that materializes is the per-box worst case.
- **Assert-is-worst-case precondition (the harness checks BEFORE bracketing the call):** assert the box is queued (`boxPlayers[index]` non-empty at the cursor) AND `lootboxRngWordByIndex[index] != 0` (word present so the open is NOT skipped) AND `lootboxEthBase[index][player] != 0` (un-opened so the materialization actually runs). Only then bracket `crankBoxes(1)` with `gasleft()`.

### (d) Named harness + calibration target

`CrankOpenBoxWorstCaseGas` (`test/gas/CrankOpenBoxWorstCaseGas.t.sol`, Plan 02) — same live `DeployProtocol` fixture + `CrankFaucetResistance` index-seed/word-inject helpers; place a real lootbox-mode deposit so the box enqueues at the first-deposit signal. The **per-box marginal** (one materialization) is the calibration target for `CRANK_OPEN_BOX_GAS_UNITS` (flat reward, REW-03), with the same SAFE-01 faucet floor: the calibrated value must keep the self-crank round-trip ≤ 0.

---

## §3 — SWEEP-PER-PLAYER worst case (AfKing keeper)

### (a) Cost-center `file:line` chain

`AfKing.sweep(uint256 maxCount)` — `AfKing.sol:522`
- `if (game.rngLocked()) revert SweepAborted()` — `AfKing.sol:523` (**G13 whole-batch abort before any work — load-bearing**)
- reads `mp = game.mintPrice()` **ONCE** per sweep — `AfKing.sol:527` (GAS-02 read-once)
- `cursor = _sweepDay == today ? _sweepCursor : 0` — `AfKing.sol:532` (**G11 cursor self-partition / bounded tombstone overhead — load-bearing**)
- bountyMultiplier from elapsed-time stall escalation (1/2/4/6)
- `while (processed < maxCount && cursor < _subscribers.length)` — caller-bounded by `maxCount`
  - per player: `lastSweptDay >= today` cheap-SLOAD skip — `AfKing.sol:567`
  - day-31 auto-extract: `hasAnyLazyPass(player)` view OR `burnForKeeper` all-or-nothing — `AfKing.sol:587-600` (**G8 burnForKeeper all-or-nothing — load-bearing**); on shortfall: `dailyQuantity = 0` + `_removeFromSet` swap-pop + emit tombstone, then `continue` WITHOUT `++cursor` — `AfKing.sol:594-599` (**G10 swap-pop integrity — the swapped-in occupant must be processed — load-bearing**)
  - `isOperatorApproved(player)` gate — `AfKing.sol:610` (**G9 address gating — load-bearing**)
  - `effectiveQty = max(dailyQuantity, floor(claimable * reinvestPct / mp))` — reads `claimableWinningsOf` (twice if reinvest + drainGameCreditFirst)
  - lootbox-floor transient skip (cost < `LOOTBOX_MIN`)
  - funding waterfall (DirectEth / Claimable / Combined / InsufficientPool skip)
  - accumulate into `players[] / amounts[] / modes[]` memory buffers
- **ONE** `game.batchPurchase{value: totalValue}(players, amounts, modes)` after the accounting loop — (**ONE batch value transfer — GAS-02**; `batchPurchase` does ONE refund of unspent value, `DegenerusGame.sol:1717-1721`; per-player try/catch slice-refund G6)
- **ONE** `coinflip.creditFlip` bounty, gas-pegged + stall-scaled — (**ONE creditFlip/tx — GAS-02**)

### (b) Structural per-player cost (the constructed maximum: a reinvest sub whose effective buy triggers multiple lootbox materializations)

| Component | Count per worst-case player | Notes |
|-----------|------------------------------|-------|
| cross-contract views | `hasAnyLazyPass` (1-2 SLOAD) + `isOperatorApproved` + `claimableWinningsOf` ×2 (reinvest + drainGameCreditFirst) | the dominant non-buy per-player cost |
| `_subOf` SLOAD | 1 (`Sub` is one slot, `AfKing.sol:195`) | maximally packed; no tighter packing (GAS-04 — 19 free padding bytes, the floor) |
| memory-buffer writes | players/amounts/modes append | accumulate for the single batch |
| per-player buy slice (deferred into the ONE batchPurchase) | `_batchPurchaseUnit → _purchaseFor`: full mint → lootbox → prize-pool → EV-cap → quest | the worst per-player slice is a reinvest sub whose effective buy triggers MULTIPLE lootbox materializations (each ≈ one open-box from §2) |

The per-player cost is NOT a fixed single materialization (unlike open-box) — the `batchPurchase` slice for a large reinvest can itself drive several lootbox materializations, so the per-player worst case is "a reinvest sub with a large effective buy."

### (c) Why this IS the maximum + the assert-is-worst-case precondition

- The per-sweep loop is `maxCount`-bounded (anti-DoS), so the per-PLAYER cost is the unit that bounds the sweep; the harness measures the per-successful-player marginal (`gasUsed / N` over N healthy subs).
- The most expensive per-player path is a reinvest sub (reads `claimableWinningsOf` twice, computes the reinvest effective quantity) whose effective buy is large enough to trigger multiple lootbox materializations inside its `batchPurchase` slice. A renewal-not-due / cheap-skip / tombstoned player costs strictly less.
- **Assert-is-worst-case precondition (the harness checks BEFORE bracketing the call):** seed N subscribers that are operator-approved, pool-funded, renewal-due THIS sweep, reinvest-mode with non-zero claimable so the reinvest branch runs, and an effective quantity large enough to materialize lootboxes. Assert each sub is in the "will buy" state (not the cheap-skip / tombstone branch) before bracketing `sweep(N)`.

### (d) Named harness + calibration target

`SweepPerPlayerWorstCaseGas` (`test/gas/SweepPerPlayerWorstCaseGas.t.sol`, Plan 03) — live `DeployProtocol` fixture; clones `AfKingConcurrency.t.sol` subscriber seeding (`subscribe()` public API + the pinned `_subOf` slot-1 / `_subscriberIndex` slot-3 layout) + the `RedemptionGas.t.sol` gasleft idiom; measure `gasUsed / N`.

The per-successful-player marginal calibrates **`BOUNTY_ETH_TARGET`** — which is an **AfKing constructor immutable** (`AfKing.sol:252`, set `:268` from `_bountyEthTarget`), NOT a frozen Game `*_GAS_UNITS` constant. AfKing holds NO frozen sweep gas constant. So this calibration lands as a **DEPLOY-SCRIPT parameter** (the test-fixture `DeployProtocol.sol:126` `new AfKing(subCost, bounty, lootboxMin)` 2nd arg, and the production keeper deploy's constructor args) — **AGENT-editable, NOT behind the USER-APPROVED contract gate** that the two `DegenerusGame.sol` `*_GAS_UNITS` constants require. The same SAFE-01 faucet floor applies (flat per-player bounty, REW-03; round-trip ≤ 0).

---

## §4 — JGAS-04 cross-reference (305-winner daily-ETH single call — already structurally derived)

JGAS-04 is the empirical confirmation gate for the JGAS-01 theoretical derivation, and it is ~90% already done by Plan 318-06.

| Item | Theory (316-RESEARCH §J4.2, design-time) | Measured (318-06 `JackpotSingleCallCorrectness.t.sol`) | What Plan 02 (JGAS-04) adds |
|------|------------------------------------------|--------------------------------------------------------|-----------------------------|
| Worst-case scenario | 305 winners (max scale 63_600 bps, buckets 159/95/50/1) in ONE call | same — `bucketCountsForPoolCap` pre-checked as {159,95,50,1} summing to 305 | re-frame worst-case-FIRST; confirm 305 IS the true max (`DAILY_ETH_MAX_WINNERS = 305` hard cap; `MAX_BUCKET_WINNERS = 250` never clips a 159 bucket) |
| Single-call gas | ~9-12M (structural, ±30%) | **7,503,715 gas** (`testWorstCaseSingleCallFitsBlockGasLimit`) | confirm `< 30M` (MAINNET, not the inflated 30B) with ~22.5M (~75%) margin |
| Enabling delta | RM-02 removed the per-winner cold `autoRebuyState` SLOAD + `_processAutoRebuy` branch | not yet attributed empirically | **ATTRIBUTE the ~1.3M delta** — the one new piece beyond 318-06 |

**Delta-attribution method (the new JGAS-04 work, RESEARCH option (a) — preferred, no dead code).** The 2-arg `_addClaimableEth(beneficiary, weiAmount)` post-RM-02 (`DegenerusGameDegeneretteModule.sol:1117`, and the jackpot-module equivalent) falls straight to `claimablePool += ...` + `_creditClaimable` (source-verified this session — no `autoRebuyState` read remains). The OLD 3-arg form did a cold `autoRebuyState[beneficiary]` SLOAD + a `_processAutoRebuy` branch per winner. Structural attribution: 1 cold SLOAD ≈ 2100 (cold slot) + 2100 (cold account) ≈ **4.2k × 305 ≈ 1.28M** freed off the path. Plan 02 asserts the measured 7.5M sits in the `theory − freed`-consistent band; it does NOT re-introduce the dead SLOAD. Confidence: HIGH on the mechanism (source-traced), MEDIUM on the exact 1.3M figure (EIP-2929 cold-access constants are fixed, but the surrounding warm/cold loop state shifts the exact number — RESEARCH Assumption A2). The harness is the module-EXTENDING `JackpotSingleCallHarness extends DegenerusGameJackpotModule` (no DeployProtocol, no nested-array vm.store) — the inverse of the §1-§3 crank/sweep harnesses, which need the live Game storage.

---

## Cite set (the authoritative source lines used above — all verified at HEAD `0d9d321f`)

- `contracts/DegenerusGame.sol` — `:1495` (`CRANK_GAS_PRICE_REF`), `:1501-1502` (`*_GAS_UNITS`), `:1543` (`crankBets`), `:1552` (G5 probe), `:1555` (lvl read-once), `:1562` (`_crankResolveBet` try), `:1567-1570` (flat per-item reward), `:1578` (one creditFlip), `:1592` (`crankBoxes`), `:1603` (G2 orphan-index skip), `:1610` (lvl read-once), `:1618` (G4 already-opened skip), `:1620` (`_crankOpenBox` try), `:1631-1632` (boxCursor SSTORE + one creditFlip), `:1641`/`:1662` (onlySelf), `:1717-1721` (batchPurchase refund)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `:226` (`MAX_SPINS_PER_BET = 10`), `:389` (`resolveBets`), `:553`/`:561` (`_resolveBet`/`_resolveFullTicketBet`), `:578` (G1 RngNotReady), `:580` (G3 delete), `:705` (`_distributePayout`), `:783` (`_resolveLootboxDirect`), `:1117` (2-arg `_addClaimableEth`)
- `contracts/modules/DegenerusGameLootboxModule.sol` — `:628` (`resolveLootboxDirect`), `:917` (`_resolveLootboxCommon`), `:992` (nested BoonModule delegatecall), `:1024` (`_queueTickets` SSTORE)
- `contracts/AfKing.sol` — `:195` (`_subOf` slot), `:252`/`:268` (`BOUNTY_ETH_TARGET` immutable), `:522` (`sweep`), `:523` (G13 rngLocked abort), `:527` (mintPrice read-once), `:532` (G11 cursor self-partition), `:567` (lastSweptDay skip), `:587-600` (G8 burnForKeeper), `:594-599` (G10 swap-pop), `:610` (G9 isOperatorApproved)
- `.gas-snapshot`, `foundry.toml` (inflated `block_gas_limit = 30_000_000_000`), `test/fuzz/JackpotSingleCallCorrectness.t.sol:80-82` (`MAINNET_BLOCK_GAS_LIMIT = 30_000_000`)
- Precedent: `.planning/phases/318-*/318-06-SUMMARY.md` §"Worst-Case Gas Derivation" (7,503,715 gas); `319-PATTERNS.md` (`306-05-GAS-BASELINE.md` derivation-doc format)
