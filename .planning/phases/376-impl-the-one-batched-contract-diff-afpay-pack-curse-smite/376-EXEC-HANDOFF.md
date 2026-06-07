# Phase 376 IMPL — Execution Handoff (EIP-170 RESOLVED; HELD for hand-review)

**Status (UPDATED 2026-06-06):** ALL 17 reqs applied to `contracts/*.sol`; **EIP-170 blocker RESOLVED**; **full `forge build` (contracts + tests) exits 0** — the test compile sweep is complete. **Nothing committed (contracts HELD).** Baseline = `2bee6d6f`. SPEC = `.planning/SPEC-V61-DESIGN-LOCK.md`. CONTRACT-BOUNDARY HARD STOP — **NEVER commit `contracts/*.sol`** without USER hand-review. Gate evidence in `376-03-SUMMARY.md`. NEXT = USER hand-reviews the batched `contracts/*.sol` diff.

## The ONE open blocker — ✅ RESOLVED

`DegenerusGame` was **25,205 B (629 B over 24,576)**. Now **24,342 B (234 B under)**; MintModule **24,356 B (220 B under)**. Resolved via the USER-selected **de-view-read-getters** approach (NOT the afking deposit/withdraw move below — that nets ~nothing once stub overhead is counted), in TWO surgical relocations:
1. **`decClaimable` → delegatecall stub** (de-dup: DecimatorModule already implements it `:367`, interface `:162`; Game copy had no internal callers; behavior verified guard-for-guard identical). Deleted the orphaned Game-private `_unpackDecWinningSubbucket`.
2. **`previewSellFarFutureTickets` → MintModule** (the high-yield move: the Game's sole referencer of `_quoteFarFutureSwap`/`_quoteFarFutureBurnieSplit`, so converting to a stub drops those helpers from the Game bytecode, ~862 B).

Two hero-getter relocations were applied then reverted (~40 B, unnecessary churn). Final reclaim diff = the 2 moves above. See `376-03-SUMMARY.md`.

**Original (now-superseded) plan that did NOT pan out:** relocate afking `depositAfkingFunding`/`withdrawAfkingFunding` → `GameAfkingModule` (~150-240 B, net-negative — small fns, stub ≈ body). The v55 reclaim menu's big wins were already spent (`claimAffiliateDgnrs` 1.3 KB) or off-limits (`playerActivityScore` 953 B — 5 on-chain callers incl. the sDGNRS redemption snapshot).

## USER-approved deviations from the locked SPEC/plan (do NOT re-litigate)

1. **PACK = pure-packing accessors (Option A, USER-approved 2026-06-06).** The 6 accessors in `DegenerusGameStorage` (`_claimableOf`/`_afkingOf`/`_creditClaimable`/`_debitClaimable`/`_creditAfking`/`_debitAfking`) are **balance-only**; `claimablePool` pairing stays at the CALL SITES (every existing `claimablePool +=/-=` line kept exactly). Deviates from must_have "pairing inside the accessor"; SOLVENCY-01 still holds + re-proven at SEC-02/378. Jackpot/Advance/Decimator NOT touched (they already use `_creditClaimable` + keep their pool lines, incl. the decimator reserve-then-credit).
2. **Accessor math = naive `+=`/`-=` (USER-approved).** NOT the SPEC's split/recombine. Safe by the supply bound (per-player ETH ≤ ~1.2e26 wei ≪ 2^128): credits never carry into the other half; `_debitAfking` (high half) is naturally fail-loud via 0.8; `_debitClaimable` (low half) has a `if (uint128(slot) < amt) revert E();` guard (a low-half borrow is invisible to 0.8's full-word check).
3. **Curse SET = delegatecall (overrides PLACE-01 "inline", USER-approved for EIP-170).** `claimWinnings` delegatecalls `IGameAfkingModule.maybeCurse(player)`; impl `maybeCurse` lives in `GameAfkingModule` (not `_maybeCurse` in the base — that was removed).

## Deviations to FLAG at hand-review (benign, document — do not "fix")

- Routing `GameOverModule:131` deity-refund + `MintModule:1027` sDGNRS→player relabel through `_creditClaimable` adds a `PlayerCredited` emit where the raw writes were silent. Arguably-correct consistency; zero state/solvency change.

## What's implemented (all 17 reqs; contracts compile modulo the size blocker)

- **PACK-01/02**: accessor layer in Storage; two mappings folded into ONE `mapping(address=>uint256) balancesPacked` `[afking:high128 | claimable:low128]`; every raw `claimableWinnings[]`/`afkingFunding[]` access routed through accessors (verified zero raw access outside accessor bodies); gameOver zeroing preserves the afking half via `_debitClaimable`.
- **AFPAY-01/07**: `_settleClaimableShortfall` → `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)` in Storage; `event AfkingSpent(address indexed player, uint256 amount)` declared in Storage, emitted at every afking debit.
- **AFPAY-02..06**: afking tier in `_processMintPayment` (all 3 pay-kinds; `prizeContribution = ethUsed + claimableUsed + afkingUsed`); lootbox shortfall via `_settleShortfall(…, payKind != DirectEth)` (DirectEth revert lifted); presale + 3 whale sites via `_settleShortfall(…, true)`; Degenerette ETH bet afking tier inline (keeps `InvalidBet()`); affiliate split `freshEth = costWei − (claimableBefore − _claimableOf(buyer))` (afking = fresh-rate; byte-identical for no-afking cases; Claimable `else` branch now splits fresh/recycled).
- **CURSE-01**: `BitPackingLib.CURSE_COUNT_SHIFT = 215` + `MASK_8`; layout doc `[215-222]`.
- **CURSE-02**: APPLY in `_playerActivityScore` (rides the `:248` packed SLOAD; `curse*100` bps floored at 0 before `scoreBps = bonusBps`).
- **CURSE-07**: `CURSE_COUNT_CAP = 20`, `_applyCurseStack` (saturating +2), `_clearCurse`, `curseCountOf` external view — in `MintStreakUtils`.
- **CURSE-03**: SET = `maybeCurse(player)` in `GameAfkingModule`, delegatecalled from `claimWinnings` after a successful `_claimWinningsInternal` (cheapest-first bails: infra/gameOver/non-stale `lastEthDay+5 > _currentMintDay()`/deity/whale-pass/active-afker/cap). NOT on `claimWinningsStethFirst`.
- **CURSE-04**: CURE `_clearCurse(buyer)` when `totalCost >= priceWei` before the score calc in `_purchaseForWith`.
- **CURSE-05**: `_recordLootboxMintDay` relocated `WhaleModule` → `MintStreakUtils` base; plain lootbox leg in `_purchaseForWith` now stamps it.
- **CURSE-06/SMITE-01**: `decurse(target)` (100 BURNIE) + `smite(deityId, smitee)` (200 BURNIE; gate `ownerOf==msg.sender` via file-scoped `IDegenerusDeityPassOwner`; bails active-afker/≥10-pts/protocol; self-smite allowed) impls in `GameAfkingModule`; thin Game dispatch stubs; events `Decursed`/`Smited`; selectors in `IGameAfkingModule`.

## Test compile sweep (test-side, committable; needed for the `forge build` gate)

Done: `contracts/test/SettleClaimableShortfallTester.sol` (rewritten to new `settle(buyer, shortfall, allowClaimable)` + accessors + `setAfking`/`getAfking`); `test/fuzz/YieldSurplusSolvency.t.sol` + `test/fuzz/JackpotSingleCallCorrectness.t.sol` (getters → `_claimableOf`); `test/fuzz/StakedStonkRedemption.t.sol` (R3 `settle` calls → new sig).
TODO: run full `forge build` and fix any remaining `test/` compile breaks — the repack REMOVED the `afkingFunding` mapping so **storage slots shifted**; vm.load slot-hardcoded redemption tests + any harness inheriting Storage may break. Compile-only for 376; runtime/assertion correctness is 378 TST.

## Files modified (production `contracts/*.sol` = held for hand-review)

Storage.sol · PayoutUtils.sol · GameOverModule.sol · LootboxModule.sol · DegeneretteModule.sol · MintModule.sol · DegenerusGame.sol · WhaleModule.sol · BitPackingLib.sol · MintStreakUtils.sol · GameAfkingModule.sol · IDegenerusGameModules.sol · ContractAddresses unchanged. Test-side: SettleClaimableShortfallTester.sol + 3 `test/fuzz/*.t.sol`.

## Done-definition + HOLD protocol (376-03 Task 2)

After the EIP-170 reclaim + clean `forge build`: produce hand-review evidence — `forge build` tail (exit 0), `forge build --sizes` DegenerusGame line (< 24,576), `git diff -- contracts/` summarized per REQ-ID group (PACK/AFPAY/CURSE/SMITE), RNG-freeze grep (`git grep -n rngWord -- contracts/` → no new read on AFPAY/PACK/CURSE/SMITE surface), SOLVENCY-01 spot-check (every afking/claimable debit pairs a `claimablePool` delta). Write `376-01/02/03-SUMMARY.md`. Commit ONLY planning docs (`git add -f` the .planning paths; NEVER stage `contracts/`). PAUSE. **The contract commit is the USER's gated action** (move `.git/hooks/pre-commit` aside → commit → restore; the env-var `CONTRACTS_COMMIT_APPROVED` bypass is DEAD in the current hook).
