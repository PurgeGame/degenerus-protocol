# Phase 468 — AUDIT-SOLV-FOLD (SPINE: solvency / backing conservation)

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27 (isolated neutral-prompt reviewer, Workflow wf_00bd2866-d0b; adversarial-verify pipeline)
**Subject:** frozen contracts/ tree 280bdb19 @ impl 3986926c (git-verified unmodified after the read-only fan-out)
**Gate:** none

## Verdict

As-built audit of the v73.0->HEAD (3986926c, tree 280bdb19 — verified frozen, only the exempt ContractAddresses.sol is dirty) purchase/mint/afking solvency fold. Every per-player claimable/afking debit in the folded purchase path is captured into a single combined claimablePool decrement; the per-leg prize-pool splits sum into one _addPrizeContribution; the boon-consume delegatecall in the deferral window makes no external call and the window is over-reserved (solvency-safe) at every boundary; payAffiliateCombined credits only leaderboard SCORE and returns FLIP winnerCredit (coin, not ETH-backed) for collision-safe accumulating creditFlipBatch; the sDGNRS bonus box debits claimable and routes it 1:1 into the box prize pool with the 1-wei sentinel provably preserved by the cl>mp guard + mp floor; partial claimWinnings caps the debit exactly and keeps the sentinel; the single game-over freeze-clear runs before _unfreezePool (which then no-ops); and the _resolveBuy/_settleShortfallNoPool rewrite is revert-free by construction across the 2 cover-buys + the STAGE loop. All 8 requirements HOLD; candidates[] is empty — the expected clean result.

**Result: 8/8 requirements HOLD; 0 candidates raised; 0 confirmed findings.**

## Per-requirement dispositions

### SOLV-01 — HOLDS

**Evidence:** contracts/modules/DegenerusGameMintModule.sol:293-301; :1408-1415; :1562-1565; :2030-2034; contracts/storage/DegenerusGameStorage.sol:907-929,984-993

**Note:** On every payKind branch (DirectEth claimableUsed=0/afking-only; Claimable ethForLeg==0; Combined) and with/without a lootbox leg, the single decrement claimablePool-=totalClaimableDraw equals the exact sum of per-player claimable+afking debits (ticketClaimableDraw from _recordMintPayment + lootboxPoolDraw from _settleShortfallNoPool). Sequential _claimableOf re-reads (after the lootbox debit) prevent double-draw; claimablePool>=buyer balance so no underflow. Coin path (_redeemFlipFor payInCoin=true at :990) skips _recordMintPayment so ticketClaimableDraw=0 — no leak.

### SOLV-02 — HOLDS

**Evidence:** contracts/modules/DegenerusGameMintModule.sol:215-218; :1537-1538; :1543-1552; contracts/storage/DegenerusGameStorage.sol:800-808

**Note:** Both legs' next/future splits are computed into locals then summed into ONE _addPrizeContribution, which reads prizePoolFrozen atomically and routes both to the same accumulator — the freeze cannot split them, and the only in-window external call (boon delegatecall) cannot flip it. LOOTBOX_SPLIT 9000+1000=10000 (rake-free); the lootbox leg's two floor divisions can leave <=1 wei in contract balance vs pool — pre-existing v73 behavior, solvency-SAFE over-backing, not unbacked credit.

### SOLV-03 — HOLDS

**Evidence:** contracts/modules/DegenerusGameBoonModule.sol:68-92; window bounded by contracts/modules/DegenerusGameMintModule.sol:1408..1564

**Note:** consumePurchaseBoost only reads/writes boonPacked + a view + an event — NO external call, no claimablePool access, so the deferral window is non-reentrant. Even a hypothetical mid-window read sees an OVER-reservation (pool not yet decremented while per-player claimable already reduced); the decrement is always strictly after the debits, so no drainable under-reservation is ever exposed.

### SOLV-04 — HOLDS

**Evidence:** contracts/DegenerusAffiliate.sol:604-682 (returns winner/winnerCredit; leaderboard SCORE writes only; winner==sender->winnerCredit=0 at :676-679; sumScaled==0 early-return :643); contracts/modules/DegenerusGameMintModule.sol:1706-1716,1745-1753; contracts/Coinflip.sol:997-1012 + :690-694

**Note:** winnerCredit is RETURNED not paid; the MintModule does one batched creditFlipBatch([buyer,affWinner]). Collision-safe: referrer-branch winner==buyer => credit 0 (skipped); _addDailyFlip accumulates (prevStake+deposit) so duplicate addresses sum with no overwrite. All credited value is FLIP coin (DegenerusAffiliate.sol:774 'no ETH/claimablePool touch') — no ETH-backed unbacked credit. Doc-only nit (not a finding): Coinflip.sol:995 comment says 'Array of 3' but loop is players.length-driven and caller passes length 2.

### SOLV-05 — HOLDS

**Evidence:** contracts/modules/GameAfkingModule.sol:1170-1197 (cl>mp guard; box=cl/20 cap 6 ether floor mp; _deliverAfkingBuy ethValue=0/claimableUse=box; _routeAfkingPoolEth(box,0); latch stamped only on fire); :790-793 (_debitClaimable(SDGNRS,box)+claimablePool-=box tandem); :1425-1456 (full box routed, complement split); :917 (lastAutoBoughtDay stamp -> loop skips SDGNRS)

**Note:** Conservation exact (claimable down box == pool up box). Sentinel box<=cl-1 for every cl: cl/20<=cl-1 (cl>=2); mp floor with cl>mp gives mp<=cl-1; 6 ether cap with cl>120 ether. claimablePool>=Σ claimable preserved. Once-per-level latch + pinned-sub loop-skip => exactly one larger day-keyed box at level start, no double debit across chunks/txs; swept => cl=0 => no box.

### SOLV-06 — HOLDS

**Evidence:** contracts/DegenerusGame.sol:1317-1336; :1354-1387 (claimDebit=amount-1 capped to maxClaim pre-gameOver; afking=gameOver?_afkingOf:0; payout=claimDebit+afking; NothingToClaim if 0; _debitClaimableAndAfking(player,claimDebit,afking); claimablePool-=payout)

**Note:** claimDebit<=amount-1 always preserves the 1-wei sentinel (pre and post gameOver); pre-gameOver the maxClaim cap binds, post-gameOver it is ignored and afking fully drained. Pool decrement equals the per-player debit exactly and cannot underflow. Zero/under-min partial claim reverts NothingToClaim. Payout always pays the resolved player (CEI), so an operator cannot redirect value (curse-grief is ACCESS-cluster, not solvency).

### SOLV-07 — HOLDS

**Evidence:** contracts/modules/DegenerusGameGameOverModule.sol:135 (sole gameOver=true site), :145-147, :152-153 (prizePoolPendingPacked=0; prizePoolFrozen=false), :182/:196 (terminal resolution AFTER the clear); contracts/modules/DegenerusGameAdvanceModule.sol:754-761 (handleGameOverDrain before _unlockRng), :1769-1776 (_unfreezePool no-op when !prizePoolFrozen)

**Note:** Single game-over path. The freeze-clear runs before the terminal jackpot/decimator resolution AND before _unlockRng/_unfreezePool; with prizePoolFrozen false and pending zeroed, _unfreezePool cannot resurrect the drained pools and no post-gameOver resolution can draw from a phantom pending pool.

### SOLV-08 — HOLDS

**Evidence:** contracts/modules/GameAfkingModule.sol:680-728 (_resolveBuy: frozen dailyQuantity; need=cost-fundingUse>=0; claimableUse<=cost; ethValue=cost-claimableUse>=0; spendableClaimable=claimable-1 only when claimable>0); gates srcFunding>=ethValue at :476,:545,:1342; :783-793; contracts/storage/DegenerusGameStorage.sol:907-929; contracts/DegenerusGame.sol:18-23 (>= invariant doc)

**Note:** All arithmetic underflow-free by construction; the funding-skip predicate srcFunding<ethValue dominates every revert-prone afking debit (skip/kill not revert) and the claimable leg always leaves the 1-wei sentinel — no-brick/no-underflow across the 2 cover-buys, the STAGE loop, and the sDGNRS box (ethValue=0). Code only ever over-reserves, matching the >= doc. Minor doc inconsistency (not a code defect): DegenerusGameStorage.sol:390 still phrases the invariant as == with a temporary-break NOTE while DegenerusGame.sol:18-23 uses >=.

## Candidates

None — clean as-built result (the expected outcome for this already-pre-push-audited batch).
