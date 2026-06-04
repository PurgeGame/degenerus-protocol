---
phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl
plan: 01
subsystem: contracts
tags: [solidity, degenerus-quests, burnie-flip-credit, reward-routing, gas, handlePurchase]

# Dependency graph
requires:
  - phase: 358-spec-design-lock
    provides: "BATCH-01/02 design-lock (return-don't-credit-inline convention; RNG-Freeze §1 + SOLVENCY §1 — BURNIE-accounting only, ETH/pool byte-unchanged); BURNIE-03 D-23 producer-before-consumer co-design"
provides:
  - "DegenerusQuests.handlePurchase folds burnieMintReward into the returned reward (no inline creditFlip); the returned-reward contract the BURNIE coin caller (plan 02) consumes"
  - "Corrected quest-TYPE-semantics reward-routing comment (no reward is paid in ETH; all are BURNIE flip stake, returned + credited once by the caller)"
  - "Read-attestation that the sole ETH caller fold (MintModule:1220 → single credit :1355) absorbs the now-larger return byte-unchanged"
affects: [359-02 (BURNIE/SALVAGE — the consumer that nets this return against a deferred burn), 360 (GAS), 361 (TST SEC-01/02 byte-diff), 362 (TERMINAL delta-audit)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Return-don't-credit-inline reward routing extended from the lootbox leg to burnieMintReward (single caller-side creditFlip)"

key-files:
  created: []
  modified:
    - contracts/DegenerusQuests.sol

key-decisions:
  - "burnieMintReward now follows the existing lootbox-reward convention: returned in totalReturned, not credited inline — saving one cross-contract creditFlip per MINT_BURNIE-quest-completing buy"
  - "Comments rewritten to quest-TYPE semantics (MINT_ETH/LOOTBOX/MINT_BURNIE are quest TYPES; every reward is a BURNIE flip stake) — no comment claims an ETH payout"
  - "MintModule left BYTE-UNCHANGED by this plan (read-attested only; behavior on the coin path is owned by plan 02)"

patterns-established:
  - "Producer-before-consumer reward contract: handlePurchase RETURNS the full earned amount (ETH + lootbox + burnie quest legs); the caller folds it into lootboxFlipCredit (one credit). Plan 02's BURNIE coin caller nets the same return against a deferred burn."

requirements-completed: [BATCH-01, BATCH-02]

# Metrics
duration: ~7min
completed: 2026-06-04
---

# Phase 359 Plan 01: BATCH-01/02 — handlePurchase Reward-Return Fold Summary

**`DegenerusQuests.handlePurchase` stops crediting `burnieMintReward` inline and folds it into the returned `totalReturned`, following the existing return-don't-credit-inline lootbox convention; the misleading ETH-mint-reward comments are corrected to quest-TYPE semantics. Behavior-equivalent (same recipient, same amount, one fewer `creditFlip`).**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-06-04T12:46:20Z
- **Completed:** 2026-06-04T12:48:24Z
- **Tasks:** 3 (2 edits + 1 read-attestation)
- **Files modified:** 1 contract (`DegenerusQuests.sol`, uncommitted) + docs

## Accomplishments

- **BATCH-01** — deleted the inline `if (burnieMintReward != 0) { coinflip.creditFlip(player, burnieMintReward); }` and folded `burnieMintReward` into the `totalReturned` sum, which now carries `ethMintReward + lootboxReward + burnieMintReward`. The 4-tuple return signature and both return paths are byte-unchanged. This saves one cross-contract `creditFlip` per MINT_BURNIE-quest-completing buy and establishes the returned-reward contract the BURNIE coin caller (plan 02) consumes (producer-before-consumer, SPEC D-02 / D-23).
- **BATCH-02** — rewrote the reward-routing comment so it reflects quest-TYPE semantics: `MINT_ETH`/`LOOTBOX`/`MINT_BURNIE` are quest TYPES, not payout currencies; every quest reward is a BURNIE flip stake, returned to the caller and credited exactly once. No comment claims an ETH payout. Lean-comment rule applied (no plan IDs, req tags, spec citations, milestone history). Zero logic change in this task.
- **Task 3 read-attestation** — confirmed the sole ETH caller fold in `DegenerusGameMintModule.sol` absorbs the now-larger return with NO code change (same recipient `buyer`, same total via the additive `lootboxFlipCredit` accumulator, one credit).

## Exact lines changed (`contracts/DegenerusQuests.sol`)

The reward-routing block (formerly `:942-955` @ frozen subject `1e7a646d`) was replaced:

**Removed:**
- The 5-line `// Reward routing:` comment claiming "BURNIE mint rewards: credited here" / "ETH mint rewards: returned to the caller".
- `if (burnieMintReward != 0) { coinflip.creditFlip(player, burnieMintReward); }` (the inline credit).
- The `// Return ETH mint reward + lootbox reward ...` comment line.
- `uint256 totalReturned = ethMintReward + lootboxReward;` (two-term sum).

**Added:**
- A 4-line quest-TYPE-semantics comment (all rewards are BURNIE flip stake, returned + credited once by the caller).
- `uint256 totalReturned = ethMintReward + lootboxReward + burnieMintReward;` (three-term sum, now at `:946`).

Net diff: `@@ -939,16 +939,11 @@` — 5 lines removed net, confined entirely to the routing block. No ETH/`claimablePool` debit code touched (grep `claimablePool` against the hunk: zero hits). The `handlePurchase` 4-tuple return signature `(uint256 reward, uint8 questType, uint32 streak, bool completed)` at `:825` is byte-unchanged.

## MintModule caller-fold read-attestation (Task 3)

`contracts/modules/DegenerusGameMintModule.sol` — **byte-unchanged by this plan**, read-attested:

- Exactly ONE `handlePurchase` call site: `:1210` (`quests.handlePurchase(buyer, ethMintSpendWei, burnieMintUnits, lootBoxAmount, priceWei, ...)`).
- The full return folds into the accumulator at `:1220` (`lootboxFlipCredit += questReward;`) and is credited exactly once at `:1355` (`if (lootboxFlipCredit != 0) coinflip.creditFlip(buyer, lootboxFlipCredit);`). Both present, unchanged.
- The ONLY `creditFlip` on this ETH caller path is the single `:1355` credit — there is NO separate inline `creditFlip` of any burnie portion (the inline credit lived only in `DegenerusQuests`, now deleted). Because the return now ALSO carries `burnieMintReward`, the caller folds the larger value with NO code change: same recipient (`buyer`), same total (additive accumulator), one credit. **Behavior-equivalent, confirmed.**
- Repo-wide there is NO other `handlePurchase` caller. The "BURNIE coin caller" plan 02 will touch is the `_purchaseCoinFor` → `_callTicketPurchase` coin path (BURNIE-01/02), which does NOT currently call `handlePurchase` — so there is no stale separate burnie-portion handling to flag on that path today.

### Discrepancy handed to plan 02 (NOT patched here — MintModule is owned by plan 02)

A now-stale comment exists at `DegenerusGameMintModule.sol:1712`:

```
///      BURNIE mints: reward creditFlipped internally by handler (nothing to batch).
```

This describes the OLD behavior. After this plan the handler no longer creditFlips internally — the reward is RETURNED. This comment sits on the BURNIE coin path that plan 02 (BURNIE-01/02) rewires, so it is left for plan 02 to correct as part of authoring that path (and/or the HYG comment-hygiene lane at 361). No behavior is affected by the stale comment; it is documentation drift only.

## Decisions Made

- None beyond the plan. `burnieMintReward` made to follow the existing lootbox-reward "return, don't credit inline" convention exactly as specified; comment rewritten to quest-TYPE semantics; MintModule confirmed unchanged.

## Deviations from Plan

None — plan executed exactly as written. Tasks 1 and 2 were applied in a single contiguous edit of the routing block (the comment and the `totalReturned` line are adjacent), which is equivalent to the two separately-specified edits and keeps the hunk minimal.

## Issues Encountered

None.

## NO CONTRACT COMMIT MADE

Per the contract-commit boundary (this plan is `autonomous: false`; project rule: only contract commits need USER approval), `contracts/DegenerusQuests.sol` is left **UNCOMMITTED** in the working tree. It accumulates across plans 01–04 and is committed as ONE batched diff ONLY after explicit USER hand-review at the plan-04 HARD STOP. `git status` was confirmed to show only `DegenerusQuests.sol` (M, uncommitted contract) plus the docs files this plan commits. No `git add -A`/`git add .`/`git add contracts` was run; no `contracts/*.sol` was staged. No `forge build` was run (SPEC D-03 = two build checkpoints only: post-features at end of plan 03, post-UDVT in plan 04); verification was source-assertion + targeted grep.

## Next Phase Readiness

- The returned-reward contract is established: `handlePurchase` returns `ethMintReward + lootboxReward + burnieMintReward`. Plan 02 (BURNIE-01/02) consumes this return on the coin path — netting it against the deferred net-burn (D-23 producer-before-consumer order satisfied: this PRODUCER lands first).
- Plan 02 should also correct the stale `MintModule:1712` "creditFlipped internally by handler" comment as part of rewiring that path.
- SEC-01 (byte-diff of the handlePurchase/caller fold) and SEC-02 (ETH/pool debit byte-identical) are deferred to TST 361; the change is BURNIE-accounting only and touches no ETH/`claimablePool` debit code.

## Self-Check: PASSED

- `contracts/DegenerusQuests.sol` exists and contains the three-term `totalReturned = ethMintReward + lootboxReward + burnieMintReward` (`:946`); the inline `coinflip.creditFlip(player, burnieMintReward)` is removed (grep count 0).
- `contracts/modules/DegenerusGameMintModule.sol` exists, unchanged, with the fold `:1220` and single credit `:1355` present.
- SUMMARY file written at `.planning/phases/359-impl-the-one-carefully-sequenced-batched-contract-diff-handl/359-01-SUMMARY.md`.

---
*Phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl*
*Completed: 2026-06-04*
