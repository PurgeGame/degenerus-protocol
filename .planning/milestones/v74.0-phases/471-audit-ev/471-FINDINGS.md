# Phase 471 — AUDIT-EV-RTP (economy / behaviour-equivalence)

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27 (isolated neutral-prompt reviewer, Workflow wf_00bd2866-d0b; adversarial-verify pipeline)
**Subject:** frozen contracts/ tree 280bdb19 @ impl 3986926c (git-verified unmodified after the read-only fan-out)
**Gate:** none

## Verdict

All seven EV requirements HOLD against the frozen tree (3986926c). The v73→HEAD economy changes are behaviour-preserving: (EV-01) the foil score basis moved from `effectiveBaseStreak(buyer)` to a `streakSnapshot` captured inside `handleFoilPurchase` at the identical logical point (post-primary `_handlePurchase`, pre-`_handleFoilPackQuest`/`_foilStreakFloor`); since `_effectiveBaseStreak` returns the synced `baseStreak` and the secondary/floor mutate only quest-streak state (not units/mintPacked_ read by `_playerActivityScore`), `foilBoostBps`, the frozen `foilRecord`, and the claim-spin RTP are byte-equivalent. (EV-02) the Degenerette `_resolveBet` merge performs only SLOADs + memory decode before the `packed==0`/`rngWord==0` gates — the first storage write (`delete`) and the `acc` accumulation occur strictly after both, so a non-strict trailing skip is a clean no-op; the `ResolveAcc` flush is unchanged (only `E()`→`Insolvent`), only `lootboxRngWordByIndex[index]` is consumed, the placement freeze-gate is intact, and the WWXRP rig is a pure rename. (EV-03) `payAffiliateCombined` reproduces four `payAffiliate` calls exactly: `_resolveReferral` is a verbatim extraction, per-leg `_scaleLeg` floors scale+taper+kickback identically and sums (floor-of-sum-of-floors), all legs share lvl=cachedLevel+1 and the same (day,sender,storedCode) entropy that the four-call model also converged on (one winner), and the single `handleAffiliate(sumShareBase)` hop is exactly reward-equal because quest rewards are fixed-per-completion and idempotent within scope (100-ether daily via completionMask, 800-ether level via the bit-136 latch) with associative progress accumulation. (EV-04) the `cachedScore=0` skip on ticket-only non-century buys is behaviour-preserving: every consumer is gated by `lootBoxAmount!=0` or `targetLevel%100==0` (the exact compute condition), and the `lbFreshScore` leg is a no-op when `lbFreshFlip==0`; v73 already passed score 0 to ticket-leg affiliate calls so the skip is a pure gas optimization. (EV-05) the streak-bonus 1→5 + boon-while-afking route through `recordAfkingSecondary` (no shield grant), the century shield is granted once per threshold via the `shieldCenturyHighWater` re-arm, and `finalizeAfking` reconciles once (`state.streak=finalStreak` then one `_grantCenturyShield`). (EV-06) `reinvestPct` has zero references anywhere in contracts/ (no orphaned read). (EV-07) `_handlePurchase` and `_resolveReferral` are verbatim extractions behind their access-tiered wrappers. No candidate survives the skeptic filter.

**Result: 7/7 requirements HOLD; 0 candidates raised; 0 confirmed findings.**

## Per-requirement dispositions

### EV-01 — HOLDS

**Evidence:** contracts/DegenerusQuests.sol:1009-1021 (handleFoilPurchase: _handlePurchase → streakSnapshot=_effectiveBaseStreak → _handleFoilPackQuest → _foilStreakFloor, same order as v73 handlePurchase→effectiveBaseStreak read→handleFoilPack→foilStreakBoost); :1352-1365 (_effectiveBaseStreak returns synced baseStreak when lastSyncDay==currentDay); contracts/modules/DegenerusGameFoilPackModule.sol:267-292 (score=_playerActivityScore(buyer,streakSnapshot); multBps=foilBoostBps(score) — same 2-arg overload as v73); :584-589 (claim-spin keccak(rw,day,drawKind,ticketIndex,FOIL_CCY_TAG)%100 unchanged, only E()→Invariant); contracts/modules/DegenerusGameMintStreakUtils.sol:383-407 (_playerActivityScore 2-arg overload, streak passed as arg, units/mintPacked_ read separately and unaffected by secondary/floor)

**Note:** streakSnapshot is captured at the byte-identical timing v73 read effectiveBaseStreak; secondary/floor running before the module's score call does not change the result because the streak is passed as a frozen arg and the other score inputs are untouched.

### EV-02 — HOLDS

**Evidence:** contracts/modules/DegenerusGameDegeneretteModule.sol:696-730 (_resolveBet: SLOAD packed → packed==0 gate (strict revert / non-strict return) → memory decode → SLOAD rngWord → rngWord==0 gate → only then delete + resolve; first mutation strictly after both gates, acc untouched on skip); :604-606 (placement freeze gate index!=0 + lootboxRngWordByIndex[index]!=0 intact, only E()→NotStarted); :960-981 (ResolveAcc poolLoaded/poolFrozen/runningPool/pendingFuture flush unchanged, only E()→Insolvent); :978 (single word lootboxRngWordByIndex[index] consumed); :32-37,1582,1651,1713 (IWrappedWrappedXRP→IWWXRP pure rename + box-spin E()→OnlyDelegatecall only; _wwxrpRoi/WWXRP_FLOOR_BPS/_roiBpsFromScore untouched)

**Note:** Strict/non-strict only changes batch failure semantics (liveness/UX), not per-bet payout EV. quests.handleDegenerette(funder,...) quest-credit reassignment is intended and only diverges on the new gift branch; non-gift bets are byte-identical (funder==player) — that reassignment is an ACCESS-02 concern, not an EV regression.

### EV-03 — HOLDS

**Evidence:** contracts/DegenerusAffiliate.sol:592-664 (payAffiliateCombined): _resolveReferral verbatim vs payAffiliate :423-475; _scaleLeg :688-702 floors scale+taper+kickback per leg identical to :486-532; sumShareBase=sumScaled-playerKickback=Σ(scaled_i-kickback_i); one leaderboard RMW (newTotal=earned+sumScaled, _totalAffiliateScore+=sumScaled) == four sequential adds; entropy keccak(AFFILIATE_ROLL_TAG,currentDayIndex,sender,storedCode) :631-639 identical and code-invariant across legs so all four calls converged on one winner; roll%2 / roll%20 distribution identical to :549-567. Linearity of handleAffiliate: contracts/DegenerusQuests.sol:2006-2017 (fixed QUEST_RANDOM_REWARD/QUEST_SLOT0_REWARD=100 ether, completionMask-dedup per day), :2287,2302-2323 (level quest bit-136 latch, fixed creditFlip 800 ether once per level), :915-919 (_clampedAddU16 associative accumulation). MintModule call site contracts/modules/DegenerusGameMintModule.sol:1698-1714 passes lvl=cachedLevel+1, ticketFreshFlip/ticketRecycledFlip from :2046-2052, lbFreshFlip/lbRecycledFlip; ticket basis equivalence :2034-2052 (freshFlip 0 when freshEth 0, recycledEth=costWei-freshEth)

**Note:** Pooled hop is exactly reward-equal (not merely conservative): both quest rewards are fixed per completion and idempotent within day/level, so distributing the same total amount across one vs four calls yields one completion either way. Floor-of-sum kickback matches because each leg is floored independently then summed.

### EV-04 — HOLDS

**Evidence:** contracts/modules/DegenerusGameMintModule.sol:1613-1615 (cachedScore computed iff lootBoxAmount!=0 || targetLevel%100==0); consumers: :1619-1621 century bonus gated targetLevel%100==0; :1642-1690 lootbox EV write (lbScore/_lootboxEvMultiplierFromScore) gated lootBoxAmount!=0; :1714 payAffiliateCombined lbFreshScore only feeds _scaleLeg(lbFreshFlip,...) which no-ops when lbFreshFlip==0 (requires lootboxFreshEth!=0 ⊂ lootBoxAmount!=0). grep confirms exactly 7 cachedScore references (2 decl/compute, 2 century, 2 lootbox, 1 affiliate) — no fourth/ungated consumer

**Note:** v73 computed cachedScore unconditionally but ticket-leg affiliate calls passed score 0 and the century/lootbox consumers were already gated, so on a ticket-only non-century buy the score was computed-but-unused; the skip is a pure gas optimization, behaviour-identical.

### EV-05 — HOLDS

**Evidence:** contracts/DegenerusQuests.sol:451-454 (awardQuestStreakBonus afking early-route to recordAfkingSecondary(player,amount), no shield); :456-460 (off-run saturating add + _grantCenturyShield); :2314-2320 (level-quest completion: afking→recordAfkingSecondary(player,LEVEL_QUEST_STREAK_BONUS=5), off-run→saturating +5 then _grantCenturyShield); :2002-2003 (slot-1 secondary recordAfkingSecondary(player,1)); :529-547 (_grantCenturyShield highWater re-arm = once per threshold); :595-616 (finalizeAfking sets state.streak=finalStreak then one _grantCenturyShield); contracts/modules/GameAfkingModule.sol:1794-1800 (recordAfkingSecondary bumps streak base only, no shield)

**Note:** While afking, every bonus path routes into the Sub streak base (no shield); the shield is granted once off the reconciled earned streak at finalizeAfking. The 8c28a55d fix eliminates the orphan/re-grant the dormant-state.streak write would have caused. 1→5 is an intended economy change.

### EV-06 — HOLDS

**Evidence:** grep -rn 'reinvestPct|reinvest' contracts/ returns NONE (zero references / no orphaned read across subscribe/afking/quest paths); contracts/modules/DegenerusGameMintStreakUtils.sol diff = named-error + bundle→pass rename only (no reinvest residue)

**Note:** reinvestPct funding leg fully excised; the sDGNRS self-sub 2%-reinvest removal and vault signature-only change are intended. The Sub 48→40 within-slot repack and _resolveBuy funding-split correctness are WIRE-01/SOLV-08 concerns, not EV.

### EV-07 — HOLDS

**Evidence:** contracts/DegenerusQuests.sol:958-960 (handlePurchase now delegates: return _handlePurchase(...)); :1025+ (_handlePurchase private body = the original handlePurchase body, unchanged in the diff context); :1009-1011 (handleFoilPurchase calls the same _handlePurchase with identical args buyer,cost,0,0,priceWei,priceWei); contracts/DegenerusAffiliate.sol:604-661 (_resolveReferral) byte-matches payAffiliate :423-475

**Note:** _handlePurchase and _resolveReferral are verbatim extractions; only difference is named-return declarations vs inline locals (behaviour-identical). The COIN-gated handlePurchase and GAME-gated handleFoilPurchase share the same modifier-less core.

## Candidates

None — clean as-built result (the expected outcome for this already-pre-push-audited batch).
