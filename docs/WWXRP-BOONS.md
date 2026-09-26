# WWXRP boons

WWXRP boons keep award IDs **38 / 39 / 40**, bonuses **4% / 8% / 12%**, and
their existing packed lane in Game storage. Each tier retains weight 200 in
the boon table. They are separate from ETH and FLIP Degenerette stake boons.

## Daily burn and century incinerator

`WWXRP.enter(amount)` consumes the player's live WWXRP boon once. It applies
the bonus to the entry's activity-weighted burn amount. It first reads the
player's WWXRP lane through the Game's read-only `extsload` and calls the Game's
consume only when the lane holds a tier; an empty lane would consume nothing
anyway, so the skip saves the dispatch without changing any outcome:

```text
weightedWei = floor(amount * activityMultiplierBps * (10_000 + boonBps) / 100_000_000)
dailyWeight = floor(weightedWei / 1 ether)
centuryWeight = weightedWei
```

The century entry is recorded only during level x99, as before. The same
consumed boon boosts both entries from that burn. The token balance and total
supply decrease by exactly `amount`; the bonus does not mint tokens or enlarge
the prize pool. Existing weight caps saturate. A failed entry rolls back the
burn, boon consumption and draw records together.

A lootbox boon remains valid through award day + 2. A deity boon is valid only
on its award day. An empty or expired boon gives no bonus. Automatic WWXRP box
and foil reward spins do not consume this boon or award whale passes.

## Future ecosystem applications

An application can consume the same boon for another WWXRP action through:

```solidity
function consumeBoon(address player) external returns (uint16 boostBps);
```

The only permission is the existing trusted-minter registry: when the vault
owner calls `WWXRP.setTrustedMinter(application, true)`, the application may
also consume WWXRP boons, and revoking it removes that right as well. There is
no per-player approval. A trusted minter can already mint any amount and burn
any balance through `burnForGame`, so spending a player's boon gives it no new
power. The hook reaches only the WWXRP boon lane, never the ETH, FLIP,
coinflip or craps lanes.

The application receives 0, 400, 800 or 1200 BPS and applies that value to its
own action in the same transaction. Consumption clears the boon once; it does
not itself burn tokens, so future uses can include actions other than burns.
If the application reverts the transaction, consumption rolls back too.

The token calls the pinned Game boon dispatcher. Game never calls the
application, and WWXRP minting, daily claims and century settlement do not
invoke boon consumption. Adding an application requires no new Game code.
