# ❌ DROPPED (USER 2026-07-07): the C4A contest is based on the CURRENT version —
# the flat 25% presale-box credit in the frozen tree (5ba80659) IS the intended design.
# Do not apply. Kept for historical context only. Original proposal below.
#
# PROPOSED (awaiting USER lock): presale-box credit 25% -> 10% for TICKETS + deity pass;
# lootbox buys STAY 25% (USER 2026-07-03)

Whale pass, lazy pass, and lootbox buys STAY at 25%. Blocked until the v75 mutation
campaign completes (same reason as the other pending notes). Comment-only lines updated
alongside (describe what IS, no history).

## Rate table after the change
- tickets:                    **10%**   (was 25%)
- deity pass:                 **10%**   (was 25%)
- mint-leg lootbox buys:       25%      (unchanged — USER explicit)
- whale pass:                  25%      (unchanged)
- lazy pass:                   25%      (unchanged)
- afking pending-FLIP trickle: scaled to the 10% ticket basis (see item 3) — the constant
  is explicitly derived as "25% of the approximated afking mint spend", and afking buys
  ARE ticket purchases, so it tracks the ticket rate.

## 1. contracts/modules/DegenerusGameMintModule.sol:1715 (split the joint site: tickets
##    10%, lootbox leg 25%)
old:            presaleBoxCredit[buyer] += (ticketCost + lootBoxAmount) / 4;
new:            presaleBoxCredit[buyer] += ticketCost / 10 + lootBoxAmount / 4;
comment 1712: "ticket + lootbox spend (fresh + recycled) earns 25% spendable box credit"
  -> "ticket spend (fresh + recycled) earns 10% and lootbox spend 25% spendable box credit"
comment 1761: "(earning 25% presale-box credit)" -> "(earning 10%-ticket / 25%-lootbox presale-box credit)"
comment 1795: "accrues the 25% presale-box credit" -> "accrues the presale-box credit"

## 2. contracts/modules/DegenerusGameWhaleModule.sol:611 (deity pass)
old:            presaleBoxCredit[buyer] += totalPrice / 4;
new:            presaleBoxCredit[buyer] += totalPrice / 10;
comment 609: "25% of the committed ETH" -> "10% of the committed ETH"
(Whale :266-269 and lazy :497-500 untouched at / 4.)

## 3. contracts/modules/GameAfkingModule.sol:1094 (afking FLIP trickle — ticket-basis)
old:            uint256 credit = (owed * 0.0025 ether) / 100;
new:            uint256 credit = (owed * 0.001 ether) / 100;
comments 1077 + 1754: "25% of that spend" -> "10% of that spend"
(The /2 and /3 ticket-mode divisors stay — they correct the buyer-bonus overstatement,
independent of the rate.)

## 4. Doc comments quoting the flat 25%
- contracts/DegenerusGame.sol:703  "(earned 25% on prior ETH buys)" ->
  "(earned 10-25% of prior ETH buys by source)"
- contracts/DegenerusGame.sol:763  "The mint leg earns 25% presale-box credit" -> "10%"
- contracts/storage/DegenerusGameStorage.sol:1080
  "(presaleBoxCredit += 0.25 * purchaseEth)" ->
  "(10% of ticket/deity spend, 25% of lootbox/whale/lazy spend)"

## Effect + design intent (USER 2026-07-03)
Credit needed to unlock the full 50-ETH box cap: 500 ETH of ticket/deity spend, or
200 ETH of lootbox/whale/lazy spend (or any mix). INTENT: lootbox buys and whale/lazy
passes keep 25% because they are a bigger investment in the future of the game; deity
stays at 10% despite being the biggest commitment because a 25% deity rate would
concentrate too much presale-box credit in one hand (one whale, one purchase).

## Resolved with USER
- (a) RESOLVED 2026-07-03: lootbox buys STAY 25% — mint site splits into
  `ticketCost / 10 + lootBoxAmount / 4`.
- (b) Afking trickle scaled to 10% (item 3) — assumed yes for consistency (afking spend
  is ticket spend); drop item 3 to keep it at the old flat rate.
