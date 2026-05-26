---
phase: 322-impl-the-one-batched-contract-diff-all-7-items
plan: 08
subsystem: verification
status: AWAITING-USER-REVIEW
committed: false
note: contracts/ applied + mainnet-clean, HELD at the contract-commit boundary (no commit without user hand-review)
---

# Phase 322 — Plan 08 (Verification Gate) SUMMARY

**The batched v47.0 contract diff is APPLIED to `contracts/` and HELD at the commit boundary.**
Nothing in `contracts/` is committed. The single USER hand-review of the batched diff is the gate.

## Build verdict
- **Mainnet src (`forge build --skip 'test/**' --skip 'script/**'`): CLEAN, exit 0.**
  - One real error was caught at this gate that the per-plan agents missed (their error-classification
    grep keyed on the `Error (...)` line, but solc puts the path on the `-->` line, and the full
    build's test-compile failures masked it): `DegenerusGameMintModule.sol` `buyPresaleBox` was
    declared `external` but uses `msg.value` → `Error (5887)`. **Fixed** by adding `payable`
    (`buyPresaleBox(address,uint256) external payable`). Re-build clean, no further masked errors.
- **`test/` compile errors: 55, ALL in test/ → Phase 323 (TST) repair scope** (not mainnet code):
  - `test/fuzz/RedemptionEdgeCases.t.sol` ×54 — tuple-arity vs the new REDEEM structs (BURNIE-leg removal).
  - `test/fuzz/RngLockDeterminism.t.sol` ×1 — references removed `gamePurchaseBurnieLootbox`.
  - These are intentional consequences of the REDEEM/LOOT signature+removal changes; TST repairs them.

## Diff scope
17 `contracts/*.sol` files, +1094 / −648 (one more than the SPEC's 16-file estimate:
`interfaces/IDegenerusGameModules.sol` for signature lockstep). All edits attributable to a v47 work item.

## Joint-check verdict (BATCH-01 design invariants — grep-attested)
- **Removals fully gone (0 residuals):** `_awardEarlybirdDgnrs`, `Pool.Earlybird`, `_finalizeEarlybird`,
  `MAX_SPINS_PER_BET`, `openBurnieLootBox`, `purchaseBurnieLootbox`, `LOOTBOX_PRESALE_BURNIE_BONUS_BPS`.
- **R1:** `resolveRedemptionLootbox` is `external payable` (DegenerusGame.sol:1835); the unchecked
  `claimableWinnings[SDGNRS] -= amount` debit is DELETED; futurePrizePool credited from msg.value.
- **R3:** `_creditBoxProceeds` (PayoutUtils) + CHECKED `pullRedemptionReserve` (Game:1888) present;
  `pullRedemptionReserve` is the ONLY surviving `claimableWinnings[SDGNRS]` debit and it is checked;
  no `unchecked` claimable subtraction survives the redemption path (grep-attested by exec #4 +
  re-confirmed here). FULL conservation proof is REDEEM-08 (Phase 323).
- **R5:** per-currency caps `MAX_SPINS_ETH=25 / MAX_SPINS_BURNIE=15 / MAX_SPINS_WWXRP=5`;
  `resolveBets` stays void (no interface change). Same-results is argued (additive Tier-1 +
  running-pool-local Tier-2); byte-identical EMPIRICAL proof is DGAS-05/DSPIN-02 (Phase 323).
- **R6:** `Pool.Earlybird`→`Pool.PresaleBox` (ordinal 4); rake removed (20% skim + 62% bonus gone).
- **R7:** AfKing in-place tombstone + in-sweep reclaim (no-++cursor); H-CANCEL-SWAP-MISS resolved.
- **BURNIE/redemption:** `redeemBurnieShare` (Coinflip) + `burnForRedemption` (BurnieCoin),
  SDGNRS in both `onlyFlipCreditors` + the consume gate (C4); BURNIE reserve apparatus deleted.

## Deviations / dispositions flagged for the USER hand-review (none block the build)
1. **MintModule `buyPresaleBox` missing `payable`** — caught + fixed at this gate (see Build verdict).
2. **PRESALE dead-flags KEPT** (`presaleStatePacked`/`PS_ACTIVE`/`LOOTBOX_PRESALE_ETH_CAP`/200-ETH
   auto-end/level-3-clear) — exec #2 grep-found LIVE consumers (WhaleModule pass-%, BurnieCoinflip
   +6pp, Affiliate VAULT-referral, Game views); R6 mandates "keep + note why". `presaleOver` is a
   DISTINCT coin-box terminal, not a replacement for `PS_ACTIVE`.
3. **`buyLootboxAndPresaleBox` funds the box leg from claimable only** (standalone `buyPresaleBox`
   takes fresh ETH + shortfall, satisfying CPAY-02); all-fresh combined funding was out of scope
   (the `_purchaseFor` hot path reverts on overfund).
4. **`_boonFromRoll` missed call site** — exec #3 reduced the fn's params but left a stale 4-arg
   call at `LootboxModule:1894` (`_deityBoonForSlot`); exec #6 caught + applied the 1-line fix.
   CONFIRM this fix at review.
5. **REDEEM dead-but-harmless leftovers** — `resolveRedemptionPeriod` keeps `flipDay` as an
   accepted-but-unused param (ABI-stable for out-of-scope AdvanceModule call sites);
   `claimCoinflipsForRedemption` + `IDegenerusCoinPlayer.transfer` now dead (left in place).
6. **New event reason code** — AfKing reclaim emits `SubscriptionExpired(player, 2)` (2 = CancelReclaim)
   rather than a duplicate `SubscriptionUpdated(...,0,...)`, for indexer clarity.
7. **322-02 removed the redundant `presaleBoxRngWordByIndex`** that 322-01 added — the box shares
   `lootboxRngWordByIndex` per R4 (one committed word, two domain-separated draws).
8. **Tooling note:** the editor's bundled NIGHTLY solc (0.8.35) flags pragma-version diagnostics on
   AfKing.sol / BurnieCoin.sol ("strictly less than released"); `forge build` with the project solc
   passes exit 0 — false positive, not a contract defect.

## Post-execution refinements (this session, on USER direction — all mainnet-clean, behavior-preserving or pure cleanup)
R1. **`BurnieCoin.burnForRedemption` deleted** — redundant with the existing COINFLIP-gated `burnForCoinflip` (COINFLIP can already burn any holder, so the `from != SDGNRS` guard added no security). `redeemBurnieShare` now calls `burnForCoinflip(SDGNRS, burnFromHeld)`; the orphaned `OnlySdgnrs` error removed.
R2. **AfKing cancel-tombstone `didWork` revert-fix** — the sweep tail (`batchLen == 0 → revert NoSubscribersSwept`) used to roll back reclaim/auto-pause/renewal removals, stranding tombstones for re-griefing. Now reverts ONLY when nothing happened (`!didWork`); buy-less chunks that did set work commit it (0 bounty). `bountyMultiplier` computation relocated past the loop (stack-depth budget under via_ir; behavior-identical).
R3. **`_settleClaimableShortfall(buyer, basis, shortfall)` helper** (in `DegenerusGameStorage`) — the canonical R3 strict-1-wei sentinel + paired `claimableWinnings`/`claimablePool` debit, defined ONCE; 5 inline copies (3 WhaleModule + 2 MintModule) now route through it. Behavior-identical (each passes its own basis — fresh read or `initialClaimable` snapshot).
R4. **`flipDay` param removed from `resolveRedemptionPeriod`** — was a dead arg kept "for ABI stability" (irrelevant under pre-launch redeploy-fresh). Removed at the decl, the interface, and all 3 AdvanceModule call sites (+ the 3 `flipDay = day + 1` locals).

## NOT done here (by design — later phases)
- Behavioral/gas/repro proofs: REDEEM-08, DGAS-05, DSPIN-02, TOMB-04, + the 55 test-file repairs
  (incl. TOMB-05 stale gas-test) → Phase 323 (TST).
- **NEW test surface from the refinements above (Phase 323):** TOMB-04 must add the `didWork` revert-fix
  case (a reclaim-only / renewal-only chunk COMMITS instead of reverting; no tombstone stranding under
  spam-cancel); REDEEM-08 covers the `burnForCoinflip` redemption-burn path (net BURNIE == 0 unchanged)
  + the shortfall helper's invariant across all 5 callers; a `resolveRedemptionPeriod` 2-arg call-path check.
- Secure-phase re-verification of the presale-box RNG freeze (R4) + the 3-skill adversarial sweep
  + delta audit → Phase 324 (TERMINAL).

**Phase 322 status: APPLIED + MAINNET-CLEAN (incl. 4 USER-directed refinements), HELD for USER hand-review of the batched diff.**
