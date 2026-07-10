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
