# WWXRP boons

WWXRP boons use award IDs **38 / 39 / 40** (bonuses **4% / 8% / 12%**, tier x 400 BPS) in a
dedicated 24-bit lane of `boonPacked` slot 1 (bits 232-255, `BP_WWXRP_LANE_SHIFT`). Each ID has
weight 200 of 2,856 in the boon roll table (`GameBoonActions._boonFromRoll`, mirrored by
`DeityBoonViewer`). They are separate from ETH and FLIP Degenerette stake boons (IDs 32-37), which
have their own lanes.

## Whole-token awards

Positive WWXRP prizes below one token award **1 WWXRP**. This applies to skipped-BAF
consolation (`score / 1000`) and the shared reward-spin resolver used by lootboxes
and foil rewards. Zero scores and losing spins still pay zero. Larger awards floor to
whole tokens: 1.9 pays 1, and 2.9 pays 2.

The minimum applies before the vault owner's `gameMintScale`. That whole-number
multiplier applies when the prize is credited or minted, including scale 0 disabling game minting.
Coinflip loss prizes (1 per loss), the Degenesis consolation and the zero-gold golden-ticket consolation (100) are
whole-token constants; the lootbox cold-bust award has a one-token minimum.

The Degenesis consolation is a fixed 1 WWXRP credit (`WWXRP.creditPrize`, before `gameMintScale`).
An order pays it when it rolls the 10% WWXRP category, when its FLIP-valued result rounds below one
whole FLIP, when a pass denomination loses its fractional pass, and when an sDGNRS award is zero or
the Degenesis pool cannot pay it. Such an order pays no other award.

## Daily burn and century incinerator

WWXRP has zero decimals: `amount` and both weights are whole tokens.

`WWXRP.enterDraw(id, amount)` consumes the player's live WWXRP boon once. It applies
the bonus to the entry's activity-weighted burn amount. It first reads the
player's WWXRP lane through the Game's read-only `extsload` and calls the Game's
consume only when the lane holds a tier; an empty lane would consume nothing
anyway, so the skip saves the dispatch without changing any outcome:

```text
weightedTokens = floor(amount * activityMultiplierBps * (10_000 + boonBps) / 100_000_000)
dailyWeight = weightedTokens
centuryWeight = weightedTokens
```

`amount` is at least `MIN_BURN` (25). The century entry is recorded only while the current level is
x99. The same consumed boon boosts both entries from that burn. The burn consumes the account's
claimable WWXRP credit first and burns held tokens from the payee for the shortfall; the bonus does
not mint tokens or enlarge the prize pool. The bucket total saturates at `uint96` and the century
weight at `uint192`. A failed entry rolls back the burn, boon consumption and draw records together.

A lootbox-rolled boon is valid through award day + 2 (`BOON_LANE_EXPIRY_DAYS`). A deity boon is
valid only on its award day. An empty or expired boon gives no bonus; consuming an expired lane
clears it. Automatic WWXRP box and foil reward spins do not consume this boon.

## Future ecosystem applications

An application can consume the same boon for another WWXRP action through:

```solidity
function consumeBoon(uint32 playerId) external returns (uint16 boostBps);
```

The only permission is the trusted-minter registry (`WWXRP.setTrustedMinter`, vault owner;
revoking removes every power below). There is no per-player approval. A trusted address holds
three separate powers:

- **Mint or credit** any amount to any recipient (`mintPrize`, `creditPrize`; unscaled by
  `gameMintScale`).
- **Burn** any holder's tokens (`burnForGame`) or spend any account's claimable WWXRP then its
  payee's tokens (`burnForAccount`).
- **Consume another player's WWXRP boon** (`consumeBoon`), which removes that player's bonus on
  their own next draw entry.

The boon hook reaches only the WWXRP boon lane, never the ETH, FLIP, coinflip or craps lanes.

The application receives 0, 400, 800 or 1200 BPS and applies that value to its
own action in the same transaction. Consumption clears the boon once; it does
not itself burn tokens, so future uses can include actions other than burns.
If the application reverts the transaction, consumption rolls back too.

The token calls the pinned Game boon dispatcher. Game never calls the
application, and WWXRP minting, daily claims and century settlement do not
invoke boon consumption. Adding an application requires no new Game code.
