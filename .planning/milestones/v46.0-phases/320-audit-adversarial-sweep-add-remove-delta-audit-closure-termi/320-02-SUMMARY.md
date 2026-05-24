---
phase: 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi
plan: 02
status: complete
verdict: delta-clean-except-SUB07-divergence-deferred-v47
source_tree_frozen: true
---

# 320-02 SUMMARY — Add/Remove + OPEN-E + JGAS Delta-Audit

## Subject commit set (v45 baseline 62fb514b… → subject HEAD)
6 commits: `df4ef365` (317 batch — keeper/slot reconciliation folded inside) + `e4014f91`/`795e679d` (GAS pegs + CR-01) + `42140ceb`/`e1baa978` (OPEN-E + WR-01) + `745cd63d` (fixture). The "317-08 keeper family" landed INSIDE `df4ef365` (only df4ef365/42140ceb/e1baa978 touch AfKing.sol).

## Delta-surface table — disposition
PROTO/CRANK/REW/SUB(01-06,08,09)/RM/JGAS/OPENE all NEGATIVE-VERIFIED — match the 316-SPEC lock. **EXCEPTION: SUB-07 (lapsed/cancelled lifecycle) DIVERGES** — the IMPL swap-pops on external cancel (`AfKing.sol:459`) instead of the locked "moves nothing" in-place tombstone (`316-SPEC.md:152`) → H-CANCEL-SWAP-MISS (320-01 §8), USER-adjudicated DEFER-to-v47.0.

## Grep-clean gates (re-run at HEAD)
- **RM kill-set: ZERO** dead legacy symbols (setAutoRebuy/autoRebuyState/_processAutoRebuy/_calcAutoRebuy/settleFlipModeChange/_afKingRecyclingBonus/deactivateAfKingFromCoin/syncAfKingLazyPassFromCoin). Only afKing-named survivors = the NEW SUB-09 keeper wiring (Vault/sDGNRS `afKing.subscribe(...,address(0))`) + the kept `hasAnyLazyPass` (DegenerusGame.sol:1472).
- **JGAS kill-set: ZERO** (SPLIT_CALL1/2, resumeEthPool, _resumeDailyEth, STAGE_JACKPOT_ETH_RESUME, call1Bucket).

## Composition attestations
- **(a) ADD×REMOVE clean** — ETH winnings always credit to claimable (`_addClaimableEth`, claimablePool balanced); flip-autorebuy flat 75bps unconditional; `_hasAnyLazyPass` the only retained afKing symbol; no orphaned/double-credit.
- **(b) JGAS single-call** — daily ETH jackpot completes in ONE advanceGame stage at the 305 ceiling (buckets 159/95/50/1, `DegenerusGameJackpotModule.sol:229`), no resume stage, nothing stranded by the dropped resumeEthPool carry; re-attests 318-06 conservation.
- **(c) OPEN-E default-self** — `fundingSource==0` short-circuits to self (`:439`/`:697`), same single `_poolOf` slot (`:728`), per-draw gas unchanged; Vault/sDGNRS pass address(0)=self; no cross-account spend without `isOperatorApproved` at subscribe() only (`:397-403`). Re-attests 319.1 13/13.

## Self-Check: PASSED
Doc exists + verify PASS (df4ef365/42140ceb/62fb514b + single-call/305/resumeEthPool + default-self + 75bps/claimable tokens present); RM+JGAS grep-clean; `git diff 30b5c89c -- contracts/ test/` empty.
