# 350-TST06-MEASUREMENT-SPEC — the 351 marginal-gas measurement spec

**Phase:** 350 — GAS · **Plan:** 350-01 · **Task:** 2 · **Authored:** 2026-05-31
**Subject HEAD (`contracts/`):** the LIVE committed tree at **HEAD `902f3fbf`** (contracts == **349.2 `453f8073`**).
**Consumer:** Phase **351 TST (TST-06)** runs this spec. **350 writes the SPEC; 350 runs NO test or gas harness.** All `file:line` below are live `git grep` anchors against `453f8073`.
**Paper-only:** READ-only on `contracts/`; `git diff --name-only -- contracts/` is EMPTY.

> **TST-06 (REQUIREMENTS.md):** the GAS-01/02/03 wins are measured **per-buy + per-open marginal under the 16.7M HARD per-tx ceiling**, proven **same-results**. This doc names the exact function/tx/marginal + the comparison oracle for each; 351 authors + runs the harness (its Wave 0).

---

## 0. The MARGINAL rule (v46 Phase 319 CR-01 — load-bearing, verbatim)

**Peg/report the loop-N-divide MARGINAL, NEVER a single-item total.** A single-box total over-states the per-item cost and (if a reward were pegged to it) re-introduces the Phase-319 self-crank faucet. Every unit below is **(gas for N items − gas for N−1 items)**, NOT a single-tx total divided by N. (350 introduces NO peg change — this rule governs the measurement reporting; it would also govern any future per-item reward peg.)

---

## 1. GAS-01 — per-BUY marginal (the box-ledger → warm Sub-stamp collapse)

| Field | Value |
|-------|-------|
| **Instrument** | `GameAfkingModule.processSubscriberStage` (`GameAfkingModule.sol:539`) — the per-sub stamp loop (lootbox branch `:735-833`, stamp writes `:793 sub.scorePlus1`, `:794 sub.amount`, `:840 sub.lastAutoBoughtDay`). |
| **Invoked by** | `advanceGame`'s new-day STAGE block (`DegenerusGameAdvanceModule.sol:305-312`), via `_runSubscriberStage(day)` (`:754` → delegatecall `processSubscriberStage(SUB_STAGE_BATCH)` `:759-761`). The STAGE runs strictly PRE-RNG (before `rngGate` writes `rngWordByDay[day]`) — the freeze property. |
| **Exercising tx** | A new-day `advanceGame()` (or `mintBurnie()`'s advance leg, `GameAfkingModule.sol:993-996`) with **N ≥ 2 funded LOOTBOX-mode subs** queued in `_subscribers` (`useTickets` flag clear; each funded via `afkingFunding` or claimable so `:708-711` debits). |
| **Marginal unit** | **Per-sub stamp marginal = (gas for N funded lootbox subs − gas for N−1) / 1.** Report this single per-sub number (the loop-N-divide MARGINAL). |
| **Comparison oracle** | The **v54 cold-ledger box-buy (~120–130k)** — ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` (the SCAV-348-01 OLD path, still live on the HUMAN path at `MintModule.sol:1142,:1159,:1306,:1328,:1473`). The afking per-sub marginal must collapse to the warm-Sub-stamp band (one 232-bit Sub slot, `DegenerusGameStorage.sol:1867`). Confirms GAS-01's "≈6 cold SSTOREs → one warm-dirty stamp". |
| **⚠ post-349.2 note** | The per-sub marginal now INCLUDES the 349.2-restored BURNIE side-effects on the lootbox branch — `quests.handlePurchase` (`:760`), conditional `recordMintQuestStreak` (`:773`), both `affiliate.payAffiliate` branches (`:806`/`:816`), one `coinflip.creditFlip` (`:831`). These are BURNIE flip-credit (no cold box-ledger SSTORE, no new ETH/pool write; the `:710` `claimablePool` debit is byte-unchanged). So the measured per-sub marginal = **(warm Sub-stamp + the restored per-sub BURNIE calls)**, which is the CORRECT same-results target for a lootbox sub (it matches a manual lootbox buy's BURNIE side-effects MINUS the cold ledger). It is still far below the v54 cold-ledger ~120–130k. 351 reports the marginal as-is against the v54 cold-ledger oracle; it does NOT subtract the restored calls (they are intended behavior, not a GAS-01 regression). |

**Same-results assertion (351):** the box materialized at open from the stamp (§2) is byte-identical to the box a manual `openLootBox` would yield for the same `(amount, level, rngWord, score)` — the warm-stamp path changes WHERE the freeze lives (the Sub slot vs the cold ledger), not the resolved traits.

---

## 2. GAS-01 — per-OPEN marginal (the stamp-derived open vs the cold-ledger walk)

| Field | Value |
|-------|-------|
| **Instrument** | `GameAfkingModule._openAfkingBox` (`:888`) → delegatecall `LootboxModule.resolveAfkingBox` (`:877`), seeded `(uint256(sub.amount), day, rngWordByDay[day], uint16(sub.scorePlus1)-1)` (`GameAfkingModule.sol:901-907`); the no-double-open marker `sub.lastOpenedDay = day` is set effects-first (`:892`). EV-cap RMW reads LIVE in the callee. |
| **Invoked by** | `_autoOpen(maxCount)` (`:938`) — driven by `_subOpenCursor` over `_subscribers`, opening up to `maxCount` materializable boxes (`_afkingBoxReady` `:918` gates on `lastOpenedDay < lastAutoBoughtDay && rngWordByDay[lastAutoBoughtDay] != 0`). |
| **Exercising tx** | `autoOpen(count)` (`:1023`, the UNREWARDED standalone clear) OR `mintBurnie()`'s open leg (`:1000-1009`, calling `_autoOpen(OPEN_BATCH)` `:1001`) — over **N ready stamped boxes** AFTER their frozen-stamp-day word `rngWordByDay[day]` has landed. |
| **Marginal unit** | **Per-open marginal = (gas for N opens − gas for N−1 opens) / 1.** |
| **Comparison oracle** | The **human `openLootBox` (`LootboxModule.sol:503`)** which walks the cold ledger + zeroes: reads `:505 lootboxEth` / `:529 lootboxPurchasePacked` / `:553 lootboxDistressEth`, zeroes `:555`/`:558`/`:560`. The afking open does NONE of those (no `boxPlayers` walk, no ledger read/zero — `boxPlayers` is human-only at `DegenerusGame.sol:1672/:1682/:1806`). Confirms the afking open is a cheap stamp-derived resolve, uniform O(1) per box (the anti-gas-DoS property). |

---

## 3. GAS-02 — no-STATICCALL trace assertion (not a marginal number)

| Field | Value |
|-------|-------|
| **Instrument** | The SAME process STAGE call (`processSubscriberStage`) AND the open leg (`_openAfkingBox`). |
| **Assertion** | A **TRACE assertion** that **NO `STATICCALL` opcode targets a DIFFERENT address** on the process/open path. The in-context SLOADs (`afkingFunding[player]` `:464`, `afkingFunding[src]` funding-skip `:662` + debit `:709`, `claimableWinnings[player]` `:463`) REPLACED the old cross-contract `GAME.afkingSnapshot`/`GAME.afkingFundingOf` STATICCALLs (`AfKing.sol` deleted). |
| **Carve-out (do NOT flag)** | The in-context DELEGATECALLs to module addresses on the SAME-contract storage are expected and NOT a violation: `purchaseWith` (ticket mode, `:718-730`), `resolveAfkingBox` (open, `:901`), and the 349.2-restored `quests`/`affiliate`/`coinflip` calls (`:760`/`:806`/`:816`/`:831`). The assertion targets a STATICCALL of afking funding STATE across a contract boundary — that is what vanished. The surviving `afkingFundingOf`/`afkingSnapshot` Game view-helpers (`DegenerusGame.sol:1579`/`:2645`) are called ONLY by the external `DegenerusVault.sol:518` — OFF this path, NOT measured here. |
| **Unit** | Boolean trace pass/fail (no marginal gas number). |

---

## 4. GAS-03 — CONDITIONAL on plan 350-03 landing an Outcome-B diff

**This row is N/A under Outcome A (no diff).** GAS-03 (the `claimablePool` same-slot flush, `GameAfkingModule.sol:710`) is the only residual candidate, adjudicated by plan 350-02 (`/gas-skeptic`); the 350-RESEARCH direction is NEGATIVE/marginal (warm SSTORE ~100 gas × (N−1)). **Only if 350-03 produces an Outcome-B diff** (the memory-accumulator flush) does 351 author this measurement:

| Field | Value (Outcome B ONLY) |
|-------|------------------------|
| **Behavior oracle** | Assert **byte-identical `claimablePool` before/after a multi-sub batch** vs the per-slice oracle (the un-batched `claimablePool -= ethValue_i` running path). The accumulator is `Σ ethValue_i`; `-=` is associative → identity holds IFF no code reads `claimablePool` between the first per-slice debit and the flush (a mandatory re-grep obligation, not a test). |
| **Fail-loud (class B)** | A **forced-underflow test** that confirms the checked `uint128 -=` flush STILL REVERTS (no `unchecked`). A single batched underflow revert is equivalent to the first per-slice underflow that would have reverted. SOLVENCY-01 invariant: `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` (`DegenerusGameStorage.sol:358`). |
| **NOT batched** | `afkingFunding[src] -=` (`:709`) stays per-iteration (per-key, the per-account underflow guard). `quests.*` (`:760`) stays per-sub, in order (non-linear — §4 carve-out REJECT). |
| **Under Outcome A** | **N/A** — record "no diff produced; GAS-03 measurement not exercised" in the 351 TST-06 results. |

---

## 5. The 16.7M HARD per-tx ceiling (with SUB_STAGE_BATCH = 50)

- `SUB_STAGE_BATCH = 50` (`DegenerusGameAdvanceModule.sol:149`) chunks the STAGE across advance calls (BUY_BATCH-style partial-drain: break + return `mult` while `_subCursor < _subscribers.length`, `:313-317`; set `subsFullyProcessed = true` only at cursor end). The comment (`:147`, `GameAfkingModule.sol:189`) budgets the chunk to stay **well under the 16.7M advance-chain gas ceiling** (a landed buy ≈ 262k → 50 ≈ 13.1M).
- The OPEN leg is chunked by `OPEN_BATCH` (`_autoOpen` default `:939`), each afking box uniform O(1).
- **351 confirms:** a 50-chunk STAGE (`processSubscriberStage(50)`) AND the open leg each stay **under 16.7M per tx**, measured on the worst-case funded-lootbox-sub mix (post-349.2, i.e. including the restored BURNIE quest/affiliate per-sub calls).

---

## 6. Wave-0 harness gaps (for 351 to build)

- [ ] An afking gas-measurement harness: per-buy marginal (instrument `processSubscriberStage` via a new-day `advanceGame()` with N vs N−1 funded lootbox subs) + per-open marginal (instrument `_openAfkingBox`/`resolveAfkingBox` via `autoOpen` over N vs N−1 ready boxes), each under 16.7M. (Stale AfKing.sol-import / `_afkingEpoch` / ABI test reds are EXPECTED now and are 351 TST-05's sweep, NOT a 350/351-06 blocker.)
- [ ] A no-STATICCALL trace assertion over the process/open path (§3).
- [ ] (Outcome B ONLY) a `claimablePool` per-slice-vs-batch oracle + a forced-underflow revert test (§4).

**350 itself needs no test infrastructure** — its output is this spec + the 350-02 verdict + (conditionally) a 350-03 held diff. The same-results proof is owned by 351 (TST-06) by design (ROADMAP Phase 351 depends-on 350).

---

## 7. Validity

**Valid until** the next `contracts/` mutation (a 350 Outcome-B `claimablePool`-flush diff — at which point `:709/:710` and the downstream stamp/open anchors shift and the instrumentation `file:line` must be re-pinned). Stable otherwise (committed at `453f8073`). `git diff --name-only -- contracts/` is EMPTY in this plan.

*Phase: 350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam · Plan: 350-01 · Task 2. Only CLI used: `git grep`/read (read-only, no test run, no package install).*
