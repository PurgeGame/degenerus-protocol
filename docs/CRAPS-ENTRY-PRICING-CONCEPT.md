# Equal entry terms after a short newcomer period

**Implemented and verified · 28 September 2026**

Craps now gives everyone standard entry terms after a modest amount of initial participation. Brand-new accounts pay a 5% surcharge for the same underlying entry. Accepted entries have fixed terms, and battle rankings use dice results without activity-score tie-breaking.

The user's latest clarification is that everyone should be on an even footing except brand-new accounts. Qualification should be easy to reach through ordinary participation, and further activity should confer no additional price, ranking, or payout advantage for equivalent entries. Some farming is acceptable. Quiet events and growing prizes can still become attractive to everyone; a universal negative-EV guarantee for fresh accounts is not required.

The participation requirement is deliberate: players should have to play a little before receiving standard subsidized entry terms. The entry-pricing rule is **minted this level or last level, OR more than two credited lifetime mint levels, OR holds a deity pass**. The user explicitly accepts credited passes and activity awards for qualification; buying a main-game pass should qualify immediately. This replaces the earlier suggestions of a score taper or a new permanent craps qualification flag.

## Qualification from existing mint history

Read the player's raw `mintPackedFor(player)` record and the current game level. Use the recorded last mint level and lifetime level count:

```text
established = creditedLifetimeLevels >= 3
recent = lastMintLevel != 0 AND lastMintLevel + 1 >= currentGameLevel
standardPrice = established OR recent OR hasDeityPass
```

Use widened arithmetic for the level comparison. The explicit nonzero check is required: an untouched wallet's zero-valued record must not qualify during the opening levels. Purchase-phase tickets target the next game level, so that forward mint also qualifies. Reusing the recorded last mint level preserves the normal whole-ticket qualification floor for ordinary mints; a sub-floor initial purchase only updates the units tally.

With fewer than three credited lifetime levels, a player gets standard prices while their mint remains recent. At three or more, the lifetime branch keeps them qualified after a break. A separate permanent qualification flag is unnecessary. All qualifying players receive exactly the same terms.

The mint fields and deity ownership bit are in one existing storage word; the current game level is one additional read if not already available. Craps reads the packed history directly through the existing Game getter. It calls `level()` only for an account with fewer than three credited levels, no deity flag, and a nonzero last mint level. Established players, deity holders and untouched wallets all short-circuit before that call. No new per-player storage writes or full activity-score computation are needed.

This is a proxy using the protocol's credited mint history. Lazy and whale pass activations, including awarded passes, and activity awards can increase the lifetime count; those pass activations can also update the last mint level. These credits are intentionally accepted under the user's clarification. Deity registration sets the ownership bit without necessarily increasing the raw lifetime count or recording a last mint level, so the explicit deity branch is required to qualify that buyer immediately. It adds only a bit test to the same player word. This is not proof of personally paying for three separate elapsed levels. ETH-side ticket, lootbox and foil participation feed the mint record; craps-only or FLIP-ticket-only play does not.

## Entry pricing: an upfront surcharge

Qualifying players keep the standard prices, including the 25k normal and 500k high future-day prices. Other players pay a disclosed surcharge for the same underlying entry. This is a binary price distinction; there is no score taper or further discount for more activity.

```text
price = standardPrice ? basePrice : basePrice * (1 + newcomerPremium)
```

The selected newcomer premium is **5%**, applied to paid single entries, whole-day entries, future-day purchases and cash upgrades:

| Activity | Normal | High roller |
| --- | ---: | ---: |
| No qualification condition met | 26,250 FLIP | 525,000 FLIP |
| Recent mint OR at least three credited lifetime levels OR deity pass | 25,000 FLIP | 500,000 FLIP |

For otherwise equivalent future-day entries and rewards, the unqualified buyer has 1,250 / 25,000 FLIP less pre-comp net EV than the qualifying buyer, entirely because of the higher price. A normal main-jackpot entry costs 8,400 instead of 8,000 FLIP. The premium is burned and adds no game capital, bonus budget or comp basis.

The premium buys no extra bankroll, bounty, prize weight, boon basis, or action-rebate credit. Track it separately from game capital. Existing comp formulas continue to use funded game capital, excluding the premium.

After entry, equivalent tickets follow the same settlement rules. Activity score is absent from stored slips, placement events, ranking tie-breaks, ordinary/high-lane bonus payouts and progressive payouts. Custom battle creation no longer accepts a minimum activity score. Dice-result ties use the committed random word.

## Growing prizes can remain attractive

A large progressive or high-roller incentive reserve may make entry positive EV for both fresh and established accounts. That is compatible with the clarified objective: established accounts share one standard price, while newcomers pay a premium for the same opportunity. The premium delays the point at which a fresh account finds entry attractive without imposing a permanent negative-EV requirement.

This design does not need a separate dynamic jackpot-access fee or activity-based prize haircut. Equivalent purchased entries receive the same prize rights, and a future pass retains its purchased entitlement when redeemed. Mint-history qualification determines the entry price; it is not re-read to reduce winnings at payout.

## Entry paths and wallet behavior

The premium applies to wallet-funded live windows, whole days, future-day purchases and cash upgrades. Pass redemption and pass-to-pass conversion consume existing entitlements without another charge. Vault-funded comp entries retain their budgeted base price; awarded seats are already funded grants. Donations retain their donated face value. Automatic protocol-body seating is unchanged. None of these entitlements grants extra weight for a newcomer surcharge.

Read qualification when quoting and charging the purchase. Mint history is not an identity check. Reaching the standard price through modest participation is intended; some farming is acceptable under the clarified goal. There should be no ongoing ladder of discounts or payout advantages after qualification.

The [implemented high-roller reserve](CRAPS-HIGH-ROLLER-INCENTIVE-PROPOSAL.md) retains the requested address rule: **vault eligible; sDGNRS excluded from triggering and winning**. Entry pricing replaces the separate standing gate in the earlier incentive proposal. Low-score high entrants who pay their quoted price can participate in the reserve on the same terms, subject to that address exclusion.

## Code anchors and verification

- [Entry pricing and score-free settlement](../contracts/CrapsBattle.sol): `_entryPrice`, `_burnForCraps`, `_upgradeDayWindows`, `_resolve`, `_laneBoost`, `_payout`, `_payProgressiveShare`.
- [Score-free slip layout](../contracts/storage/CrapsBattleStorage.sol): former score bits 190–205 remain unused; other packed-field positions and storage slots stay stable.
- [Newcomer regression tests](../test/craps/CrapsNewcomer.t.sol): recent/lifetime boundaries, deity qualification, genesis zero-record guard, skipped level calls, paid fees, preserved comp entitlements and absent score reads/packing.
- [Player EV report with graphs](CRAPS-ENTRY-PRICING-EV.md): participation sensitivity before comps and Coinflip.

The aggregate emissions report models standard-price entries. Each newcomer adds a separate 5%-of-base burn. No universal negative-EV bound for fresh accounts is required; a quiet field may be profitable for both prices.

Verification: **573 tests passed, zero failures** across the craps suites, real FLIP/Game wiring, comp donation, high-reserve sampling, jackpot draw/gas checks and RNG-sealing invariants. Eligibility fuzzing ran 1,000 cases; the skipped-level test makes `level()` revert to prove the shortcut. The deployed CrapsBattle runtime is 23,881 bytes, below the 24,576-byte EIP-170 limit. The entry-pricing economic model also passed its ledger reconciliation.
