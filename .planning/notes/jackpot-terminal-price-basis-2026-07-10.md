# Finding: terminal-jackpot ticket price/award basis lags delivery (2026-07-10)

USER-confirmed (external reviewer + independent trace). MEDIUM. Value-adverse to buyers / stranded ETH.

## Mechanism
On the last jackpot day, once the daily RNG is requested (`jackpotPhaseFlag && rngLockedFlag && jackpotCounter+step >= JACKPOT_LEVEL_CAP`), ticket DELIVERY reroutes to `level+1` (this level seals no further draw). But the QUOTE / CHARGE / AWARD basis does NOT:
- Canonical `_activeTicketLevel()` (MintStreakUtils:143) = `jackpotPhaseFlag ? level : level+1` — NO terminal reroute.
- Inline twins same formula: `_purchaseCostInputs` (MintModule:1314, ticketCost + EntriesBought event + affiliate/quest basis), `_purchaseWithFoil` (Game:645, foil+ticket combined quote), Decimator:379, FoilPack:425, Afking:484/555/1769, Game views 2214/2396.
- ONLY `_queueEntriesScaled` (MintModule:1970-1973, targetLevel) and foil `buyFoilPack` (FoilPack:165) apply the terminal reroute.

## Consequence (DirectEth `_processMintPayment` MintModule:210,234-237)
`ethUsed = min(ethForLeg, amount)`; amount = costWei @ targetLevel (rerouted), ethForLeg sized @ quote level. "overage ignored for accounting":
- DOWN boundary (century 100->101, price 0.24->0.04): buyer's ethForLeg (high) > costWei (low) -> overpay STRANDED in contract (not pooled/refunded/afking-credited). Finding's "extra 2 ETH neither refunded nor credited."
- UP boundary (normal N->N+1, price rises): ethForLeg (low) < costWei (high) -> shortfall drawn from afking/claimable unexpectedly, or revert (DirectEth).
- Affiliate/quest/recycle/EntriesBought event all record the wrong (pre-reroute) level basis.

Reachable: the reroute code at 1970 + foil terminal handling prove ETH buys execute in this window.

## Reroute condition (to centralize)
step = compressedJackpotFlag==2 ? JACKPOT_LEVEL_CAP : (compressedJackpotFlag==1 && cnt>0 && cnt<CAP-1 ? 2 : 1); reroute iff jackpotPhaseFlag && rngLockedFlag && jackpotCounter+step >= JACKPOT_LEVEL_CAP.

## Fix direction (USER: "shift to lvl+1 price AND ticket award after RNG request on last jackpot day")
Centralize the routed level into ONE helper (`_activeTicketLevel()` folds in the terminal reroute, or a new `_routedTicketLevel()`), used by BOTH quote and delivery so they can never diverge. Blast radius: decimator price, afking finalize price, mint-price views, mint-streak base also shift to level+1 in that window (correct — all are "ticket bought now" bases). VERIFY afking finalize (484/555) and decimator (379) don't need the un-rerouted level for a settlement/historical basis. Then quote==award==delivery; overpay-stranding and unexpected-draw both vanish. Regression: terminal-jackpot century-boundary buy asserts charged==delivered==level+1, no stranded ETH.

---

## SHIPPED (commit 4df23844, 2026-07-10) — full foundry suite green (1029/0 pre-test-fix + CoverageGap222 updated)

Single source of truth: `_activeTicketLevel()` now folds in the final-jackpot-day reroute (rngLocked + jackpotCounter+step >= CAP -> level+1). `_routedTicketLevel` helper was merged away (one function). Consumers routed: quote (`_purchaseCostInputs` MintModule, `_purchaseWithFoil` Game), ticket delivery (`_callTicketPurchase`), foil delivery (`buyFoilPack`), mint-price views (`mintPrice`/`purchaseInfo`/`afkingSnapshot`), participation/streak recording (MintModule:1592, `_recordLootboxUnits`), foil/activity score (`_playerActivityScore` streakBaseLevel), ethMintStats streak. Removed 2 duplicate inline reroute blocks. JACKPOT_LEVEL_CAP added to MintStreakUtils.

Downstream regressions found by reviewer + fixed IN THIS COMMIT:
- **purchaseInfo().lvl now = ACTUAL level** (was active-ticket-level). Both Coinflip consumers (BAF `_claimCoinflipsInternal` + `_coinflipLockedDuringTransition`) read it from the one snapshot, DROPPING a redundant `game.level()` call (gas win, USER's design). priceWei stays routed (buy quote). Interface + NatSpec updated.
- **Coinflip BAF bracket** simplified to `_bafBracketLevel(cachedLevel + 1)` on the actual game level — fixes the level-9-terminal "skip a BAF bracket" regression (routed lvl=10 was treated as game level, 10%10==0 pushed bracket 10->20) AND deletes the phase-branched bafLevel logic (proven equivalent to ceil10(level+1) in all cases = USER's decade rule 0-9->10, 10-19->20).
- CoverageGap222.t.sol: checks entriesOwedView at the ROUTED target level (where a buy queues) not purchaseInfo.lvl (now actual).

Left AS-IS (out of scope / immune): keeper-bounty ETH->FLIP divisors (Decimator:379, FoilPack foil-claim bounty — inline, negligible), afking auto-buys (Afking:484/555, pre-RNG immune).

**FREEZE:** contracts tree now 249d69b0 (HEAD 4df23844), past tag 9777a3f7. Re-pin PENDING (accumulate-then-refreeze at campaign end). Commits this session: f85aa9b8 (F3 PoC) -> 6f9b8de6 (F3+F6) -> 4df23844 (price-basis).
