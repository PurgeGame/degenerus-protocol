---
phase: 322-impl-the-one-batched-contract-diff-all-7-items
verification: goal-backward
verdict: PASSED (IMPL deliverable; behavioral proof → Phase 323)
date: 2026-05-25
contract-commit: fb29ed51
---

# Phase 322 — VERIFICATION (IMPL — The ONE Batched Contract Diff)

**Verdict: PASSED for the IMPL deliverable.** The single batched `contracts/*.sol` diff for all
7 v47.0 work items is applied, USER-reviewed, and committed (`fb29ed51`, 17 files, +1146/−716).
Mainnet src builds clean (`forge build --skip 'test/**' --skip 'script/**'` → exit 0). The
empirical behavioral/gas proof is the explicit scope of Phase 323 (TST) — see below.

## ROADMAP success criteria (6)
1. ✅ **Rake-free + presale boxes** — 20% vault skim + 62% BURNIE bonus deleted (grep-clean);
   `Pool.Earlybird`→`PresaleBox`; `_awardEarlybirdDgnrs`/`_finalizeEarlybird`/`EARLYBIRD_*`
   removed; credit-gated boon-less boxes (25% credit, 50/40/10, 80/20, 50-ETH clamp + sweep +
   `presaleOver` latch).
2. ✅ **BURNIE lootbox removed / 3 callers unified** — full surface gone (terminal-paradox
   closed), BURNIE→tickets kept; `_resolveLootboxCommon` 5→2 bools, 10% haircut fixed.
3. ✅ **Degenerette write-batched same-results** — cross-bet flush, ETH cap on running-pool
   local, lootbox per `betId`, DGNRS per-spin, RNG/freeze untouched; caps 25/15/5.
   *(Byte-identical empirical proof = DGAS-05/DSPIN-02, Phase 323.)*
4. ✅ **Universal claimable-pay** — 3 whale buys + presale box + external-payable sweep; the
   strict-1-wei sentinel + paired claimable/pool debit now centralized in
   `_settleClaimableShortfall` (one audited definition; `claimablePool == Σ claimableWinnings`).
5. ✅ **sDGNRS redemption airtight + AfKing tombstone** — ETH hard-segregated
   (`pullRedemptionReserve` checked, fail-closed), `resolveRedemptionLootbox` payable with the
   unchecked SDGNRS debit deleted, gameOver double-count dropped, BURNIE settled at submit
   (net new BURNIE == 0, via `burnForCoinflip`), reserve apparatus deleted; AfKing in-place
   cancel-tombstone + in-sweep reclaim (+ `didWork` revert-fix) — H-CANCEL-SWAP-MISS resolved.
   *(Two-claimant/conservation empirical proof = REDEEM-08; tombstone = TOMB-04, Phase 323.)*
6. ✅ **Reconciled + committed** — manifest §2 reconciliation (single `resolveRedemptionLootbox`
   signature, single `DegeneretteModule` edit, presale-param removal with the bonus removal)
   held at the contract-commit boundary and committed only after explicit USER hand-review.

## Build / joint-checks (322-08 gate)
- Mainnet build exit 0. Wave-8 caught + fixed a real bug (`buyPresaleBox` missing `payable`).
- Removals grep-clean: `_awardEarlybirdDgnrs`, `Pool.Earlybird`, `MAX_SPINS_PER_BET`,
  `openBurnieLootBox`, `purchaseBurnieLootbox`, `LOOTBOX_PRESALE_BURNIE_BONUS_BPS`,
  `burnForRedemption`, `flipDay`.
- No `unchecked` claimable subtraction survives the redemption path.

## Deferred to Phase 323 (TST) — NOT a gap, by design
The 55 `test/` compile errors (RedemptionEdgeCases tuple-arity, removed `gamePurchaseBurnieLootbox`)
are intentional consequences of the REDEEM/LOOT changes. Phase 323 repairs them and proves:
REDEEM-08 (repro-first), DGAS-05/DSPIN-02 (same-results gas), TOMB-04/05 (cancel-tombstone +
the new `didWork` cases) — plus coverage for the 4 session refinements (322-08-SUMMARY).

**Phase 322: COMPLETE (IMPL).** Audit subject frozen at `fb29ed51` for the Phase 324 delta-audit.
