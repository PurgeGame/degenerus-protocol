# Phase 344 — Execution Summary

**Executed:** 2026-05-30 · **Mode:** inline sequential (no worktrees — `no_worktree_paths: [contracts]`; one accumulated diff held for hand-review per D-344-06).
**Commits (on `main`):**
- `d728263e` — `feat(344)`: v54 afking-funding ledger + AfKing de-custody (+ keeper→afking rename)
- `6d6aa424` — `perf(344)`: remove per-sender per-level affiliate commission cap

**Build:** `forge build` clean (66 sources, 0 errors). `forge test` NOT run; `test/` untouched (D-344-07 — ABI break is 346 TST's charge).

## What landed (the de-custody ledger)
- `afkingFunding` mapping on storage (no aggregate; rides in `claimablePool`; invariant comment names the component).
- `depositAfkingFunding` / `withdrawAfkingFunding` (GO_SWEPT guard line-1, checked-math `claimablePool` debit) / `afkingFundingOf` / extended `afkingSnapshot` (returns per-player funding).
- `batchPurchase` non-payable; per-slice `afkingFunding[b.funder]` debit (D-01, funder=src) + `claimablePool` release; `funder` added to both `BatchBuy` structs.
- `_claimWinningsInternal` Decision-B merge.
- AfKing fully de-custodied (no ETH; `subscribe` forwards `msg.value` → `depositAfkingFunding`; `funder:src`; non-value batch call; `_poolOf`/`receive`/`deposit`/`depositFor`/`withdraw`/`poolOf` deleted).
- CLEANUP-02 kill-set grep-confirmed empty.

## Deviations from the 343 SPEC / 344 plan (authored, surfaced, accepted)
1. **Decision-B merge gated on `gameOver` + sentinel preserved.** The EDIT-ORDER-MAP snippet omitted both; GAMEOVER-01/02 + PLAN-V54 §"Decision B" confirm the gate. Pre-gameOver `afkingFunding` stays its own bucket; the merge also allows keeper-only recovery post-gameOver (GAMEOVER-02).
2. **`_resolveBuy` snapshot made unconditional.** Was conditional on `reinvest/drainFirst`; now always reads the (extended) `afkingSnapshot` so the funding-skip has `afkingFunding[player]`. Net = exactly "ONE staticcall per player" (D-MR-01); pure-DirectEth subs needed the read anyway once local `_poolOf` is gone.
3. **4 collateral de-custody orphans removed beyond the 14-item kill-set** — `Withdrew` event + `EthSendFailed`/`InsufficientBalance`/`ZeroAddress` errors (dead after deleting `withdraw`/`depositFor`). Needed for the plan's `_poolOf == 0` acceptance.
4. **VAULT recovery (USER directive at the BLOCKING checkpoint).** `recoverAfKingPool` → `recoverKeeperFunding` → renamed `recoverAfkingFunding`, re-pointed to `game.withdrawAfkingFunding(game.afkingFundingOf(this))` — restores the vault's anytime pre-sweep recovery (§4.1 of the trace). sDGNRS proceeds via the existing `claimWinnings(0)` Decision-B merge (its v48 leg was gameOver-only; lazy recovery accepted).
5. **Repo-wide `keeper`→`afking` rename (USER directive).** All symbols + comments; `keeperSnapshot`→`afkingSnapshot` (pre-existing); spans 10 files.
6. **Per-sender affiliate cap removed (USER directive, gas).** Deleted `affiliateCommissionFromSender` + `MAX_COMMISSION_PER_REFERRER_PER_LEVEL` — score ∝ real ETH spent, no free farm to cap. Beyond original 344 scope (gas/345 territory, folded in this session).

## BLOCKING checkpoint outcome
344-05 Task 1 actor-consequence trace (`344-ACTOR-CONSEQUENCE-TRACE.md`) proved recoverability for VAULT + sDGNRS; user escalated §4.1 → VAULT keeps `withdrawAfkingFunding`. Recorded in the trace §6.

## NEXT — supersedes much of v54
USER decision: pursue the **afking-in-Game redesign** — fold AfKing's subscription state into the Game (frees the cross-contract staticcalls + the de-custody ledger), split per-sub work into a **process pass** (money + affiliate + quests + evict-if-insolvent, stamps box intent into the warm `Sub` slot) and a **once-daily open pass** (walk subs, derive each box on the fly from the frozen stamp, materialize against RNG — no per-box queue storage). Open design questions: the 218-byte Game code-size ceiling (move modules out), the lock/freeze window (stamp captures config; possibly anchor box-buy in the required advance path for uniform timing), EV-cap accumulation at open, the human-vs-sub two-path split. A dedicated redesign spec is the next artifact.
