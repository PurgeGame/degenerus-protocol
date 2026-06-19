# Milestone v71.0 — Foil Pack — Requirements

> Scoped requirements for the v71.0 Foil Pack feature. Full locked design: `.planning/V71-FOILPACK-FINAL-SPEC.md`
> (grounding/history: `.planning/V71-FOILPACK-DESIGN-CONTEXT.md`). Traceability (phase mapping) is filled by the roadmap.

## v71.0 Requirements

### FOIL — Purchase & economics
- [ ] **FOIL-01**: A player can buy at most one foil pack per account per raw game-level (level-stamped cap, auto-resets per level).
- [ ] **FOIL-02**: A foil pack costs `10 × priceForLevel(level)` and delivers 4 whole tickets (16 quadrant entries).
- [ ] **FOIL-03**: A foil pack is payable with fresh ETH or claimable balance (the afking leg is rejected).
- [ ] **FOIL-04**: Foil spend routes 75% next-pool / 25% future-pool.
- [ ] **FOIL-05**: Foil tickets enter the regular jackpot as normal tickets; their boosted-rarity traits write real color tiers (incl. `color==7` gold).

### RARE — Activity-scaled rarity boost
- [ ] **RARE-01**: Foil tickets roll traits via a NEW sibling producer (`traitFromWordFoil`/`packedTraitsFoil`); the v70-frozen shared producers are not modified.
- [ ] **RARE-02**: The rarity multiplier scales with activity score ×2 @ 0 → ~×5 @ 350 → ×6 @ max, via a new `foilBoostBps` curve in `ActivityCurveLib`.
- [ ] **RARE-03**: The rarity multiplier is frozen at buy from the buyer's activity score and applied at resolve (never live-read).
- [ ] **RARE-04**: All rarer color tiers are lifted by the factor (mix-to-rare-tail); ×6 ⇒ gold ≈ 4.7%/quadrant.

### MATCH — Multi-currency match lottery
- [ ] **MATCH-01**: Each pack's 4 ticket signatures (4 quadrants each) are frozen at buy and stored per `(player, level)`.
- [ ] **MATCH-02**: Each ticket is eligible the whole level against both daily winning sets (main + bonus, 2/day).
- [ ] **MATCH-03**: `claimFoilMatch(day, ticketIndex)` re-derives the day's winning traits from `rngWordByDay[day]`, counts exact positional quadrant matches, and pays the 2/3/4 tier (color-only and single matches do not pay).
- [ ] **MATCH-04**: The match payout uses its OWN isolated table; it never routes through the EV-flat Degenerette per-N pick tables.
- [ ] **MATCH-05**: Settlement is pull/claim only (no draw-time scan); each `(day, drawKind, ticketIndex)` is claimable at most once; records persist per-level so a fast level advance cannot grief an unclaimed match.
- [ ] **MATCH-06**: The 2-of-4 (5 faces) and 3-of-4 (65 faces) tiers each pay one spin split 40% FLIP / 40% ETH / 20% WWXRP — FLIP minted (`mintForGame`), ETH via the existing 10%-of-`futurePrizePool`-capped spin, WWXRP minted (`mintPrize`).
- [ ] **MATCH-07**: The 4-of-4 tier grants half a whale pass (`whalePassClaims += 1`) plus a 40/40/20 bonus spin.
- [ ] **MATCH-08**: The spin magnitude and currency are both derived deterministically from `rngWordByDay[day]` at claim (disjoint entropy lanes); the magnitude-first/currency-second reveal is UI-only.
- [ ] **MATCH-09**: The 2-of-4 / 3-of-4 tiers match against the live (hero-overridden) winning traits (the bounded, by-design hero-symbol edge is retained); the 4-of-4 moonshot is gated on the hero-free pure-VRF winning traits (steer-proof / non-stackable).
- [ ] **MATCH-10**: The currency-payout ladder is calibrated to ≈2 ticket-faces of expected payout per pack over 30 days.

### SEC — Security & integration floor
- [ ] **SEC-01**: No exploit beyond the bounded hero edge; the 4-of-4 moonshot cannot be steered or collusion-stacked.
- [ ] **SEC-02**: No solvency hole — ETH leg ≤10% of `futurePrizePool`, FLIP/WWXRP are mints, the whale pass is a pool-neutral deferred grant.
- [ ] **SEC-03**: New code fits EIP-170 (body in a roomy module or a new `GAME_FOILPACK_MODULE`, not `MintModule`; thin facade stub; storage appended in `DegenerusGameStorage`).
- [ ] **SEC-04**: The full forge suite is green and the storage-layout goldens / RNG-freeze proofs re-pass on the new (foil) subject.

## Future Requirements (deferred)
- Indexer parity events for the foil buy and the match claim (additive; can land after the feature).
- (carried from v70) mutation + Halmos formal on the new foil module; `roi`/`wwxrp` direct-body coverage.

## Out of Scope
- Adding WWXRP / the 40/40/20 split to the *existing* Degenerette game — this milestone touches only the foil match spins.
- Any change to the v70-frozen shared trait producers or the existing lootbox/jackpot magnitude tables.
- Frontend/UI implementation of the reveal (on-chain provides the deterministic result; the UI lives in a separate repo).

## Traceability
_(filled by the roadmap)_
