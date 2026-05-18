---
artifact: ADVERSARIAL-ECONOMIC-ANALYST
phase: 296-cross-surface-adversarial-sweep-sweep
plan: 01
milestone: v42.0
skill: economic-analyst
adversarial_pass_pattern: PARALLEL_SUBAGENT
audit_subject_surfaces: [MINTCLN, HRROLL, DPNERF, RETRY_LOOTBOX_RNG]
generated_at: 2026-05-18
---

# Phase 296 Adversarial Pass — `/economic-analyst` Persona

Independent disposition over the 14 CHARGE hypotheses, viewed through the lens of rational-actor modeling, incentive compatibility, capital-cost reasoning, and equilibrium / death-spiral analysis. Source files inspected for this pass: `DegenerusGameMintModule.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameAdvanceModule.sol`, `DegenerusGameDegeneretteModule.sol`. Design-intent context: `292-01-DESIGN-INTENT-TRACE.md`, `294-01-DESIGN-INTENT-TRACE.md`. Decision anchors honored: `D-42N-LEADER-BONUS-01`, `D-42N-FLOOR-01`, `D-42N-BONUS-ENTROPY-01`, `D-42N-DETERMINISM-01`, `D-42N-COLOR-ENTROPY-01`, `D-42N-GAS-01`, `D-42N-GOLD-FLOOR-01`, `D-42N-DEITY-EV-01`, `D-42N-PATH-COVERAGE-01`, `D-294-CALLER-UNIFORM-01`, `D-294-BURNIE-INLINE-01`, `D-294-NATSPEC-01`, `D-281-FIX-SHAPE-01`, `D-288-FIX-SHAPE-01`.

---

## Hypothesis (i) — MINTCLN 3-input hash determinism break

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor of concern: the "Determinism Forensic" EV-maximizer who wants to predict trait emission for arbitrage on secondary-market mint flips. For that actor, the only way to derive positive EV is to find two `_raritySymbolBatch` calls within or across drains that hash to an identical `(baseKey, entropyWord, groupIdx)` seed — collision lets them precompute future trait outputs from a single observed batch.
- Actor-walk Path A (multi-call drain on same `(rk, player)`): the seed input differs across batches because the `owed` field decreases monotonically as a player's tickets are drained. The packed `baseKey` low-32-bit slot reflects `owed-at-call-entry`, not a stale snapshot. The `entropyWord` is fixed for the level's drain window (sourced from `lootboxRngWordByIndex[index - 1]`), but `owed` flips at every batch boundary because the previous batch wrote `(uint40(remainingOwed) << 8) | uint40(rem)` back to `ticketsOwedPacked[rk][player]`. Subsequent re-entry reads the new value before constructing `baseKey`. Seeds are pairwise-distinct by construction.
- Actor-walk Path B (`_resolveZeroOwedRemainder` zero-owed → rolled-to-1): the `baseKey` constructed at entry carries `owed == 0`. When the helper rolls `rem` to a win and bumps owed to 1, the `_raritySymbolBatch` call in that same iteration uses the original (`owed=0`) `baseKey` — but this call processes exactly one ticket, and the very next iteration's `baseKey` will carry `owed=0` again only if the player has zero remaining owed (in which case nothing else gets emitted). Critically, no second `_raritySymbolBatch` invocation on the same `(rk, player)` is reachable in a single drain cycle with both `baseKey-at-call-time` carrying the same `owed` value AND a non-trivial emission; the rolled-to-1 path is a single-emission terminal branch. There is no exploitable collision.
- Actor-walk Path C (queue-time owed bumps): `ticketsOwedPacked[rk][player]` is bumped at purchase/queue time, not mid-drain. Mid-drain reads always re-fetch `packed` at the top of each iteration; thus the next batch's `baseKey` will reflect the bumped `owed` if a bump landed between batches.

**Notes:**
- The EV-maximizer's expected return from predicting trait outputs is bounded by the secondary-market arbitrage spread on identified-vs-blind trait reveals. Pre-launch, there is no secondary market, so the immediate exploit EV is zero. Post-launch, the structural non-collision means even a sophisticated forensic adversary derives no information that materially predicts a player's next batch.
- This is the same invariant v41 Phase 281 closed via the explicit `ownedSalt` 4th argument; the v42 packing is an algebraically equivalent rearrangement (low-32-bits-of-baseKey-carry-owed vs separate-argument-carry-owed). Both produce pairwise-distinct keccak inputs across batches.

---

## Hypothesis (ii) — `owed`-in-baseKey shape collision griefing

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor of concern: the Griefer who wants to engineer a collision-causing address or queue-state that forces two distinct `(lvl, queueIdx, player, owed)` tuples to produce identical `baseKey`. If achievable, the griefer could either (a) force LCG seeds to align across two players (no direct profit but UX damage) or (b) trigger uniform trait emission that distorts the trait-bucket distribution against organic players.
- Bit-range layout: `lvl[224-255]` (32 bits), `queueIdx[192-223]` (32 bits), `player[32-191]` (160 bits), `owed[0-31]` (32 bits). The 32+32+160+32 = 256 bits exactly fill the slot with zero overlap.
- `queueIdx >= 2^32` reachability: at the construction site, `queueIdx` is `uint256` typed but supplied from `ticketCursor` (typed `uint32` per the cursor's storage slot). Structural upper bound: 2^32 - 1. No path lets `queueIdx` overflow into the `player` range.
- Player address overflow: `uint160(player)` truncates to 160 bits; the shift `<< 32` lands the address into bits 32-191 exactly. EVM addresses are by definition 160 bits; no oversized address is constructable.
- Zero-owed branch distinctness: the only way two distinct `(lvl, queueIdx, player, owed)` triples could collide is by violating the bit-range non-overlap. The packed shape is injective on the 4-tuple.
- Griefer capital cost: $\infty$ — there is no constructable input that produces a collision, so no capital outlay yields the attack.

**Notes:**
- Even if the griefer could find a soft "near-collision" (e.g., two players with similar emission patterns), the actual LCG seed is `keccak256(baseKey, entropyWord, groupIdx)`. Keccak's avalanche property means even a 1-bit difference in `baseKey` produces a uniformly-distributed output. There is no economic surface here.

---

## Hypothesis (iii) — `TraitsGenerated` topic-hash break parsing ambiguity

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Economic actor of concern: a downstream indexer operator who paid to build infrastructure against the v41 event shape and would be silently mis-fed under v42, then make false attestations about player trait distribution that feed back into UX or wallet displays. The harm vector is reputational (wrong data displayed) rather than direct value extraction.
- Pre-launch posture: no live indexer state exists. Any indexer build is consuming the v42 ABI from day one. Per the operational template D-40N-EVT-BREAK-01 (v40 precedent), the event-signature break is acceptable in this window.
- Keccak avalanche separation between old topic `0x5e96bf2d…` and new topic `0x279edf1c…` means any decoder matching by topic-hash will simply not match the wrong shape — they will silently drop, not mis-parse. There is no shared-prefix attack surface (keccak does not preserve prefix structure).
- No in-contract reader of `TraitsGenerated`: this is an emit-only event consumed externally. No internal economic flow depends on it.

**Notes:**
- The remaining concern would be a downstream tool that matches by event-NAME string (rare; most production indexers match by topic-hash). Even so, such a tool would fail to decode the 3-field shape with 6-field schemas — the decoder error surfaces immediately, not silently mis-attribute value.
- The LOG3 → LOG2 transition saves ~893 gas per emit; the gas savings flow proportionally to all `processFutureTicketBatch` / `processTicketBatch` callers. Marginal economic positive.

---

## Hypothesis (iv) — `×1.5` leader bonus whale-coordination / MEV / wash-trading

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Economic actor: the Whale + the EV Maximizer + the Coordinating-Whale-Cartel. This is my load-bearing analysis surface.
- **Actor-walk A — final-block-vault-into-leader:** A whale observes the public on-chain wager state for day D, sees a runner-up at amount X on `(q_r, s_r)` and current leader at amount Y on `(q_L, s_L)`. The whale wants to vault into leader status on `(q_w, s_w)` (their preferred slot, where they have downstream payoff). The whale needs to deposit `>Y` of wager-units on their slot AND ensure no one else outbids them before the day rollover. Cost of attack: the whale must place an ETH bet whose `wagerUnit = totalBet / 1e12` exceeds Y. At Y = 10,000 wager-units (realistic mid-game pool size), the bet requires `1e16 wei = 0.01 ETH` at risk. But — this is the *mechanic working as designed*. The whale is paying full capital cost for the leader advantage; the `×1.5` bonus on their bet returns them weighted probability `1.5 × (Y+ε) / effectiveTotal` ≈ `1.5 × Y / (Y+othertotal)` — only positive EV when the prize-pool divided by the slot odds exceeds their bet cost. The whale's bet is fully at-risk capital. This is not MEV; it is paying for an in-game advantage with real bet capital.
- **Actor-walk B — cross-account leader rotation:** Two whales agree to alternate leader status on adjacent days, each paying capital cost to be leader on their "turn." Each whale's bet is independent at-risk capital staked into the daily pool. There is no coordination dividend — the daily-jackpot resolution does not give "alternating leaders" any structural advantage over a single whale who dominates every day. The cartel earns the same per-whale-day EV as a solo whale would over the same number of days. No emergent positive EV from coordination.
- **Actor-walk C — wash-trading via cross-account bet rotation:** Suppose a single attacker controls accounts A and B. A places a 100-wager-unit bet on `(q, s) = (2, 5)`; B places a 100-wager-unit bet on `(q, s) = (2, 5)`. Total contribution to `dailyHeroWagers[D][2]` at symbol 5: 200 wager-units. The attacker has placed 200 units of *real ETH* into the betting pool with no rebate path — each bet is an independent Degenerette resolution with normal odds. The "wash" gives them no extra signal in the hero-symbol pool because the slot already accumulates additively; one 200-unit bet from a single account would produce identical state. Wash-trading buys nothing.
- **Actor-walk D — mempool reordering / final-block races:** The wager-write at `placeDegeneretteBet:484-501` lands at bet-placement time. The hero-symbol roll consumes wager state *atomically at VRF callback time*, which is on a separate block from any wager-placement transaction (VRF coordinator confirmation requirement: VRF_MIDDAY_CONFIRMATIONS / equivalent for daily). A mempool searcher cannot reorder a wager into the same block as the VRF callback because the VRF callback is delivered by Chainlink's signed VRF response — the searcher does not control its arrival block. Practical commitment-window: ≥ 3 confirmations (typical Chainlink VRF), so the wager must commit ≥ 3 blocks before resolution. No mempool-reordering attack achievable.
- **Asymmetric-information question:** Is there a state read between VRF request and VRF callback that a wagerer could exploit? Following the design-intent trace §(iv) backward-trace: the symbol-roll entropy `keccak256(abi.encode(randWord, day))` is UNKNOWN at any wager-time. Wagers commit before randomness lands. No information asymmetry.

**Notes:**
- **Counter-argument considered:** "What if the bet-placement TX and the VRF callback share a mempool window, and a sophisticated searcher front-runs the callback?" — Falls apart because VRF callbacks come from `vrfCoordinator` (a privileged sender per the `if (msg.sender != address(vrfCoordinator)) revert E()` gate at `rawFulfillRandomWords:1749`); the searcher cannot inject a callback. They can place a wager seconds before the callback lands, but doing so is just a normal bet — they have no advance knowledge of `randWord`.
- **Mechanism-design assessment:** The `×1.5` magnitude was deliberately chosen per D-42N-LEADER-BONUS-01 to reward capital commitment without monopolizing. Leader-win probability ~50-60% at typical organic distributions; runner-up retains meaningful probability. This is exactly the "size matters but doesn't monopolize" signal the design intends. Per the design-intent trace §(ii) the alternatives `×2` and pure-proportional were considered and rejected at user disposition.
- **Death-spiral analysis:** If only whales win, small bettors stop placing hero wagers, total pool collapses, jackpot signal degrades. Does `×1.5` produce this? With 6 organic mid-bettors at ~1000 wager-units each and one whale at 5000, leader-prob ≈ `5000 × 1.5 / (6 × 1000 + 5000 + 2500) = 7500 / 13500 ≈ 56%`. Each mid-bettor still wins ~7% of days. This is enough variance to keep smaller players engaged. Death-spiral risk: LOW.

---

## Hypothesis (v) — No-floor sybil dilution

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor: the Sybil-Spam Griefer who wants to perturb organic outcomes by spamming small bets. This is my load-bearing analysis.
- **Capital-cost calculation:** `wagerUnit = totalBet / 1e12` at `DegenerusGameDegeneretteModule.sol:489`. To deposit 1 wager-unit on a single slot, the attacker must place `1e12 wei = 1e-6 ETH` of actual at-risk capital. The Degenerette bet is real money. The `placeDegeneretteBet` flow at L444-501 takes a `totalBet = amountPerTicket × ticketCount` with `MAX_SPINS_PER_BET` enforced and `_collectBetFunds(player, currency, totalBet, msg.value)` collecting the ETH.
- **Single-slot dilution payload at minimum wager:** To deposit 1 wager-unit on a single slot requires the bet to pass `_validateMinBet` (min-bet enforced by the contract). At realistic minimum-bet floors, the actual cost per wager-unit may be substantially higher than 1e12 wei — the min-bet floor sets the lower bound. Even at 1e12 wei per unit, the spam cost is non-zero.
- **32-slot dilution payload:** To touch all 32 `(q, s)` slots with 1 wager-unit each requires 32 separate `placeDegeneretteBet` transactions (each bet targets a single `heroQuadrant`; the `customTicket >> (heroQuadrant * 8) & 7` determines the symbol within the quadrant). 32 × `1e12 wei` = `3.2e13 wei` = **0.032 ETH** minimum at-risk capital before considering min-bet floors or gas costs. Gas cost for 32 tx: ~32 × 80k gas = 2.56M gas × ~30 gwei = `~7.7e16 wei` = **0.077 ETH** at moderate gas prices — dominating the bet cost.
- **Effect on `effectiveTotal`:** With organic daily wager-volume realistically in the 100,000-1,000,000 wager-unit range (per the §(iii) backward-trace: a single 0.001 ETH bet creates 1000 wager-units), 32 attacker units represent `32 / 1,000,000 = 0.0032%` of `effectiveTotal`. The shift in any organic bettor's win probability is sub-basis-point. The attacker has paid ~0.1 ETH (0.032 stake + 0.077 gas) for a negligible probabilistic effect.
- **Rebate paths:** None. The Degenerette bet is settled via `_resolveBet` against the lootbox RNG word; the spam bet is just a real bet with normal expected return (with the attacker holding tickets whose payoff is determined by the lootbox-bound symbol, not by the hero-symbol pool perturbation). The attacker does not recover the bet through the hero-roll mechanic itself; their bet is at risk in the normal Degenerette payout flow.
- **Amplification surfaces searched:** (i) `traitBurnTicket` perturbation — the hero-symbol roll outcome is independent of `traitBurnTicket` since `_applyHeroOverride` only writes to a stack-local `uint8[4]`; no storage side-effect cascades to bucket population. (ii) Quest-streak / activity-score multiplier interaction at `_placeDegeneretteBetCore` L457-460 — the spam bet does award activity-score and quest progress (per L426-434), but those rewards flow to the *attacker's own future bets*, not to organic players. There is no negative externality on organic players via the activity-score path. (iii) Multi-day persistence — `dailyHeroWagers[day][q]` resets per-day (the `day = _simulatedDayIndex()` key rotates daily). The attacker cannot accumulate spam units over multiple days into a single day's pool.

**Notes:**
- **Equilibrium analysis:** The Nash equilibrium for spam-attacks under this capital-cost structure is: defect from attacking. The attacker is strictly better off placing their 0.032+ ETH on a non-spam bet with normal positive variance.
- **Counter-argument considered:** "What about a pre-launch zero-volume day where 32 wager-units represent 100% of the pool?" — In that edge case, the attacker would indeed dominate the hero-symbol roll. But (a) they would also be the *only* bettor — the prize pool they're chasing is empty of organic capital, so there's nothing to dilute or steal; (b) the hero-symbol mechanic's payoff is bounded by the daily prize pool which is empty in this scenario; (c) post-launch organic volumes rapidly exceed the spam threshold. The edge case has no economic surface.
- **Adverse-selection check:** Does no-floor attract bad-faith small bettors? Marginally — the no-floor design lets anyone with 1e-6 ETH participate, which is good for inclusivity but admits dust spam. The capital-cost analysis above shows dust spam is unprofitable, so the equilibrium settles to "real bettors only." Adverse selection: NEGLIGIBLE.

---

## Hypothesis (vi) — Symbol-roll VRF bit-collision with existing consumers

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Economic actor: an EV-Maximizer who has reverse-engineered the bit-allocation map and is hunting for cross-consumer correlations to predict one consumer's outcome from another's.
- The HRROLL symbol-roll consumes `uint256(keccak256(abi.encode(heroEntropy, day))) % effectiveTotal`. `heroEntropy = randWord` (raw, pre-bonus-tag, per D-42N-BONUS-ENTROPY-01).
- Existing consumers per the bit-allocation table at AdvanceModule L1157-1174:
  - Bit 0: Coinflip win/loss, BAF fire gate
  - Bits 8+: Redemption roll
  - Full word (modular/keccak-mixed): Coinflip reward percent, Jackpot winner selection, Coin jackpot, Lootbox RNG, Future-take variance, Prize-pool consolidation, Reward jackpots
  - `r`-derived bit-slices: color-sample bits `quadrant*3` of `r`; lootbox/jackpot Bernoulli bits[152..167] / bits[200..215] are read off `r` (or `randWord` for non-bonus paths).
- Keccak avalanche: the hash `keccak256(abi.encode(randWord, day))` is computationally indistinguishable from a random function applied to the 2-tuple. Knowing any specific bit-slice of `randWord` provides no advantage in predicting any specific bit of the keccak output beyond brute-force.
- **Cross-consumer correlation test:** Can the attacker observe the color-sample outcome (which reveals bits `quadrant*3` of `r`) and use it to predict the symbol-roll outcome? `r` for the non-bonus path equals `randWord`; the symbol-roll input is `keccak256(abi.encode(randWord, day))`. Even with full knowledge of `randWord` AND `day`, the symbol-roll is deterministic (the attacker can compute it). But this is post-callback knowledge — `randWord` is only revealed at VRF callback time, which is *also* when the symbol-roll resolves. There is no temporal window where the attacker knows `randWord` before the roll commits.
- **Pre-callback prediction:** No actor knows `randWord` until VRF delivers. Therefore no cross-consumer information leaks back into a pre-resolution betting decision.

**Notes:**
- D-42N-COLOR-ENTROPY-01 records this as "structural, not probabilistic" non-collision. Confirmed: keccak output domain is orthogonal to any input bit-slice by hash-function design.
- Edge case: `abi.encode` vs `abi.encodePacked` domain separation. The HRROLL keccak uses `abi.encode` (per D-42N-DETERMINISM-01), giving an ABI-tagged 64-byte preimage `(uint256, uint32)`. The bonus-path `r = keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG))` uses `abi.encodePacked` with a constant tag. The two preimages are distinct by both content (tag vs day) and encoding (packed vs encoded). No collision surface.

---

## Hypothesis (vii) — HRROLL gas regression DOS

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Economic actor: a DOS griefer who wants to brick daily jackpot resolution by inflating per-call gas to exceed the block gas limit.
- **Bounded computation:** `_rollHeroSymbol` performs (a) 4 × SLOAD on `dailyHeroWagers[day][q]`, (b) 2 × 32-iteration loops (pass-1 cache build + pass-2 cursor walk), (c) 1 × keccak256 on 64-byte input, (d) 1 × MOD + 1 × DIV. All loop bounds are constants (`q < 4`, `s < 8`, `idx < 32`). No unbounded computation.
- **Memory expansion:** `uint32[32] memory weights` allocates 32 × 32 bytes = 1024 bytes = 32 words. Memory expansion cost is constant and small (~96 gas for the allocation per Solidity's memory model).
- **Bonus-active-day compounding:** `_rollWinningTraits` is invoked twice on bonus-active days (regular + bonus). Each invocation calls `_applyHeroOverride` which calls `_rollHeroSymbol`. Total per-day overhead: `2 × 9925 = 19850 gas` for the symbol roll vs `2 × 9494 = 18988 gas` for the v41 baseline. Delta: ~862 gas/day. Trivial against the daily-jackpot transaction's existing gas budget (millions of gas for trait-winner draws + payouts).
- **Writes-budget-bounded inner loops:** The writes-budget mechanism lives in `processTicketBatch` / `_processOneTicketEntry` (the mint flow), NOT in the jackpot resolution path. `_rollHeroSymbol` does not run inside any writes-budget-bounded loop; it runs once per `_applyHeroOverride` invocation.
- **No state-dependent gas escalation:** The function is `view`. It performs no SSTORE. The gas profile is constant across all `dailyHeroWagers` states.

**Notes:**
- An attacker cannot inflate gas by pre-arranging `dailyHeroWagers` state because the loop iterates fixed-32-times regardless of state contents.
- D-42N-GAS-01 soft threshold +500, hard upper-bound +750; theoretical +431 is well below.

---

## Hypothesis (viii) — DPNERF intentional EV reduction secondary attacks

**Disposition:** ACCEPTED_DESIGN

**Evidence:**
- Economic actor: the Deity-Pass Holder (whale-tier capital commitment) confronting reduced gold-tier EV; the Commons-Tier Organic Player whose EV could be perturbed by deity behavioral shift; the Secondary-Market Speculator hedging deity-pass price decay. This is my load-bearing analysis.
- **Direct EV impact on deity holder:** Per design-intent §(ii), gold-tier deity-win probability drops from `2/(len+2)` to `1/(len+1)`. At `len=30`: 6.25% → 3.23% (−48%). At `len=50`: 3.85% → 1.96% (−49%). Total daily deity EV across 4 ETH + 4 BURNIE trait-winner selections falls by ~25-30% depending on the bucket-size distribution (gold buckets are smaller; the relative weight of gold-tier wins in the deity's total EV is significant).
- **Actor-walk: Deity pivots to commons betting strategies.** Suppose the deity-pass holder responds by placing higher Degenerette bets on common-color symbols, hoping to elevate the trait-bucket population on commons (their preferred tier) and capture commons-tier deity virtual entries (`max(len/50, 2)`). This is a *normal player action* — they are paying real bet capital to shift bucket distributions. Their pivot does not extract extra value from the deity-virtual-entry mechanic; the commons formula `max(len/50, 2)` was unchanged. They simply place more bets, paying full bet price for normal payout expected return.
  - Effect on organic commons-tier players: commons buckets grow modestly due to extra deity-driven activity. `virtualCount = max(len/50, 2)` grows linearly with `len`, so the deity's marginal commons-tier share *stays at ~2%* — the deity-EV-share-of-bucket is the design invariant. Organic players in a larger commons bucket see (a) reduced per-winner share if the bucket grows but the winner count stays fixed, balanced by (b) the deity-share *stays constant at 2%* of bucket. Net effect on organic commons EV: NEUTRAL.
- **Actor-walk: Secondary-market deity-pass price decay.** The deity-pass purchase price is fixed at `DEITY_PASS_BASE` per the WhaleModule (out-of-scope per Phase 294 §(f)). Holders who paid the v41-era price now hold an asset with strictly lower forward EV. Two outcomes:
  - (a) Some holders sell, depressing secondary-market price. This is the intended outcome per D-42N-DEITY-EV-01.
  - (b) The BoonModule `BP_DEITY_PASS_TIER_SHIFT` flow (out-of-scope per Phase 294 §(e)) reads deity-pass ownership signals for boon distribution. If deity-pass turnover increases, boon-distribution beneficiaries may shift. But the boon-distribution code is unchanged and treats current deity-pass ownership at the resolution moment — no temporal exploit window.
  - Cascade check: does deity-pass price collapse trigger a death-spiral in any other mechanism? Deity-pass is a soulbound NFT (per §(g)) — non-transferable. There is no live secondary market in the protocol's deployed shape. "Secondary-market price collapse" is a theoretical concern that does not manifest in the deployed code. Verified: the deity-pass is acquired-only-from-protocol, not transferable. No cascade.
- **Actor-walk: Temporal arbitrage on pass acquisition/disposal across daily cycles.** The deity-pass is soulbound, so disposal is impossible. Acquisition timing: a player could in principle delay acquiring the deity pass to a level where projected winning traits skew commons-heavy. But (a) the deity-pass purchase economics at `WhaleModule.DEITY_PASS_BASE` are unchanged, and (b) the winning-trait roll is RNG-driven, unknowable in advance. Players cannot reliably target levels with commons-favorable rolls. Arbitrage window: NONE.
- **Actor-walk: ETH↔BURNIE sampler-shape arithmetic differences (cross-cited to (ix)).** The gold-tier branch produces `virtualCount = 1` identically in both surfaces. The per-pull arithmetic differs (ETH N-winner aggregated vs BURNIE 1-winner-per-iteration with `lvlPrime` resampling), but the gold-tier *deity share* per pull is `1/(len+1)` on both. Total deity EV reduction is symmetric across currencies.

**Notes:**
- **Equilibrium analysis:** Post-nerf equilibrium for deity-pass holders: continue holding the pass (it's soulbound; no exit), accept reduced gold-tier EV, optionally shift discretionary bet capital toward commons-tier participation. New equilibrium for the deity capital base: slightly lower total revenue per holder per cycle, no contagion to commons-tier organic players, no destabilization of any downstream mechanism.
- **Counter-argument considered:** "What if deity pivoting depletes commons-bucket EV for organic players?" — Resolved above: the commons `max(len/50, 2)` formula keeps the deity's commons share at ~2% of bucket regardless of bucket size. Organic-player commons EV is invariant under deity activity scaling.
- **Risk matrix:**
  | Risk | Likelihood | Impact | Mitigation |
  |------|------------|--------|------------|
  | Deity-pass price decay (psychological) | High | Low | User-accepted per D-42N-DEITY-EV-01 |
  | Commons-tier perturbation from deity pivot | Low | Negligible | `max(len/50, 2)` scales with bucket; ~2% invariant |
  | BoonModule cascade | None | N/A | Deity-pass soulbound; ownership-signal stable |
  | Cross-currency asymmetric extraction | None | N/A | Gold-tier `virtualCount = 1` symmetric |
- **Mechanism-design assessment:** This is the user's intentional EV reduction per D-42N-DEITY-EV-01. The economic walk confirms it does not create incentive misalignments or secondary destabilization. The "intentional nerf" is exactly what it claims to be: a targeted reduction in gold-tier deity over-extraction.

---

## Hypothesis (ix) — ETH↔BURNIE differential-behavior exploitation

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Economic actor: an EV-Maximizer running parallel ETH-path and BURNIE-path strategies, hunting for differential-behavior arbitrage. This is my load-bearing analysis on prize-currency economics.
- **Deity-sentinel emission shape asymmetry:**
  - ETH path (`_randTraitTicket` L1755-1757): `winners[i] = deity; ticketIndexes[i] = type(uint256).max`. The aggregated array is returned; consumer at the caller uses sentinel `ticketIndex == max` to identify deity wins.
  - BURNIE path (`_awardDailyCoinToTraitWinners` L1888-1893): `winner = deity; ticketIdx = type(uint256).max`. The single-pull result emits `JackpotBurnieWin` event with the deity sentinel.
  - The asymmetry is *event-emission topology* (ETH emits via downstream caller after array processing; BURNIE emits per-pull). An attacker cannot exploit the asymmetry because both produce deterministic, public emissions consumable by any observer with equal information access.
- **Per-pull randomness derivation:**
  - ETH: `idx = keccak256(abi.encode(randomWord, trait, salt, i)) % effectiveLen`. Per-trait, all `numWinners` use the same `(trait, salt)`.
  - BURNIE: `lvlPrime = minLevel + keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i)) % range`; then `idx = keccak256(abi.encode(randomWord, trait_i, lvlPrime, i)) % effectiveLen`. The level is resampled per pull; trait rotates `i % 4`.
  - **Commitment-window symmetry:** Both consume `randomWord` at the same jackpot-resolution moment. No temporal asymmetry. Both keccak inputs are committed at the same time. Player wagers cannot influence either after commitment.
  - **Bias-symmetry check:** Both surfaces use `% effectiveLen` modular reduction. `effectiveLen` ranges in single-digit-thousands at most (bucket sizes); the keccak output is 256 bits. Modular bias is `<< 2^-220`, structurally negligible on both surfaces.
- **`coinBudget` ↔ `ethPool` prize-currency economic differential:**
  - ETH wins pay in ETH (real, externally-fungible). BURNIE wins pay in BURNIE (in-game utility token with separate burn mechanics).
  - Deity holder receiving 1 ETH-path win = 1 ETH-denominated payout. Deity holder receiving 1 BURNIE-path win = 1 BURNIE-denominated payout (whole-BURNIE-floored per `baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether`).
  - **Cross-currency arbitrage attempt:** Could a deity holder time their bet activity to skew gold-tier wins toward ETH days (higher-fungibility payout) vs BURNIE days? Days are not currency-segregated — `payDailyJackpot` (ETH) and `payDailyCoinJackpot` (BURNIE) both run on the same daily cycle in different phases. The deity-pass holder cannot redirect their gold-tier wins to one currency; the gold-tier `virtualCount = 1` applies symmetrically on both surfaces.
  - **Sub-1-BURNIE evaporation:** `_awardDailyCoinToTraitWinners:1849` floors `baseAmount` to whole-BURNIE. Sub-1-BURNIE residue evaporates per the natspec at L1818. This evaporation is symmetric across all winners (deity and organic alike) — no deity-specific disadvantage.

**Notes:**
- **Counter-argument:** "What if a BURNIE-deity-win at a small bucket where `effectiveLen = 1` (only the deity exists) gives the deity 100% win-probability deterministically?" — Resolved: with `len = 0` and `virtualCount = 1` (gold), `effectiveLen = 1`; the modulo produces 0; `idx < len` is false (0 < 0 false); deity wins. This is the *intended* edge-case behavior — when only the deity is in the bucket, the deity wins. Same behavior in v41 with `len = 0` and `virtualCount = 2`: `idx ∈ {0, 1}` both → `idx >= len = 0`, deity wins both pulls. Pre/post-patch: deity wins empty-bucket pulls in both regimes. NEUTRAL.
- **Event-emission information leak:** Could an observer use the `JackpotBurnieWin` event with sentinel `ticketIdx = max` to time their bets? The event fires *after* jackpot resolution; the information is post-VRF. No pre-resolution exploit window.
- **Equilibrium assessment:** The ETH/BURNIE currency split is part of the protocol's bi-currency economic design. Deity holders accept exposure to both currencies; their gold-tier EV reduction is symmetric across both. No incentive misalignment introduced.

---

## Hypothesis (x) — BURNIE inline-duplicate vs ETH differential at gold-tier branch

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Economic actor: an attacker hunting for subtle algebraic divergence between the textually-parallel +4/-2 source deltas at L1731-1737 (ETH) and L1867-1874 (BURNIE).
- **Source-pattern comparison (read against the contract):**
  - ETH (`_randTraitTicket`): `if (deity != address(0)) { if (((trait >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; } }`
  - BURNIE (`_awardDailyCoinToTraitWinners`): `if (deity != address(0)) { if (((trait_i >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; } }`
  - Only difference: variable name `trait` vs `trait_i`. Algebraic structure identical. `effectiveLen = len + virtualCount` identical at both sites.
- **Sentinel-pair invariants:**
  - ETH (L1755-1757): `winners[i] = deity; ticketIndexes[i] = type(uint256).max`.
  - BURNIE (L1888-1893): `winner = deity; ticketIdx = type(uint256).max`.
  - Both write the deity address as the winner and `max` as the index sentinel. Algebraically equivalent — the only difference is array (ETH) vs scalar (BURNIE) storage, which is a function of the surrounding sampler shape (N-winner aggregated vs 1-winner-per-iteration), not the gold-tier semantic.
- **Per-pull deity-selection probability:**
  - ETH: `P(deity win on pull i) = virtualCount / effectiveLen = 1 / (len + 1)` for gold.
  - BURNIE: `P(deity win on pull i | trait_i is gold and bucket lvlPrime selected) = virtualCount / effectiveLen = 1 / (len + 1)` for gold.
  - Identical per-pull conditional probability. The BURNIE surface has the additional `lvlPrime` resampling which spreads pulls across `[minLevel, maxLevel]`, but conditional on a given `lvlPrime`, the gold-tier deity probability matches the ETH path's per-pull probability.
- **State-dependent perturbation:**
  - `coinBudget` underflow at BURNIE: `_awardDailyCoinToTraitWinners` floors `cap = DAILY_COIN_MAX_WINNERS`, capped down to `coinBudget` if smaller; sub-1-BURNIE residue evaporates. No underflow; bounded by `coinBudget`.
  - `lvlPrime` boundary effects: `range = maxLevel - minLevel + 1`; `lvlPrime = minLevel + uint24(...) % range`. If `range == 0` (maxLevel == minLevel), modulo by zero would revert. But callers enforce `maxLevel >= minLevel` (range >= 1) by construction.

**Notes:**
- The Phase 294 Plan 02 verification surfaced the "by construction" reach-claim was wrong (per `D-294-BURNIE-INLINE-01`); the corrective gap-closure commit `38319463` produced the parallel +4/-2 delta. This pass confirms the parallel deltas are algebraically equivalent.
- No subtle differential. The duplication is intentional (architectural incompatibility between single-bucket / N-winner and multi-bucket / 1-winner-per-iteration samplers) and faithful (both branches carry identical algebraic semantics).

---

## Hypothesis (xi) — DPNERF callsites 1 + 2 production-path coverage gap

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor: an EV-Maximizer hunting for a state-dependent path where the gold-tier nerf doesn't reach uniformly, hoping to find an un-nerfed extraction surface.
- **Callsite 1 — `_runEarlyBirdLootboxJackpot` (L698):** Calls `_randTraitTicket(bucket, rngWord, traitId, 25, t)` with `bucket = traitBurnTicket[lvl]`, `numWinners = 25`, `salt = t ∈ {0,1,2,3}`. This is a *direct call to the same `_randTraitTicket` function body* that carries the gold-tier branch. The branch fires for any gold-tier `traitId` regardless of caller. No flag, no parameter, no per-caller divergence — the branch is in the callee.
- **Callsite 2 — `_distributeTicketsToBucket` (L988):** Calls `_randTraitTicket(traitBurnTicket[sourceLvl], entropy, traitId, uint8(count), salt)`. Same direct call to the same function body. The gold-tier branch fires identically.
- **State-dependent behavior search:**
  - (a) Early-bird 25-winner shape: The 25-winner draw on a small gold bucket produces 25 modular samples against `effectiveLen = len + 1` (gold) instead of `len + 2` (v41). Reduces deity wins per gold-bucket-draw from `25 × 2/(len+2)` to `25 × 1/(len+1)`. Symmetric to all other callsites' nerf.
  - (b) Carryover-ticket level-crossing leakage: Carryover tickets that move from level N to level N+1 retain their trait IDs but are sampled at level N+1's bucket. At sampling time, the `_randTraitTicket` body computes `virtualCount` from the *current* trait (not the originating-level trait), so the gold-tier nerf applies based on the trait at sampling time. There is no path where a gold-trait ticket sampled at level N+1 escapes the level-N+1 application of the gold-tier branch — the branch is in the function body, not in a per-level parameter.
  - (c) Early-bird-post-purchase timing vs `_unlockRng`: Early-bird-post-purchase tickets are queued at purchase time and drained later. The drain happens through `_distributeTicketJackpot → _distributeTicketsToBucket → _randTraitTicket`. The `_unlockRng` write of `dailyIdx` happens at the day-rollover boundary; the drain's `_randTraitTicket` invocation reads from the new bucket state at drain time, with the gold-tier branch firing on the current trait. No commitment-window asymmetry — the branch is state-independent.
- **Capital-cost / EV analysis:** The total deity EV reduction is the sum over all 5 surfaces (4 `_randTraitTicket` callsites + 1 `_awardDailyCoinToTraitWinners` inline). Since all 5 surfaces apply the same `virtualCount = 1` on gold, the deity's total daily EV reduction is uniform across all paths. No un-nerfed extraction surface exists.

**Notes:**
- The "coverage gap" per D-295-CALLSITE-SCOPE-01 is a *regression-fixture coverage gap* (TST-DPNERF-01..05 exercises 3 of the 5 surfaces; callsites 1 + 2 are not in the fixture). The Phase 296 SWEEP is the structural attestation site. This pass confirms the by-construction uniformity argument — the branch lives in the function body, not the callsites.
- An attacker would have to discover a *new* `_randTraitTicket` callsite to escape the nerf. Grep on the v42 close tree returns exactly 4 callsites (L698, L988, L1296, L1399). No hidden callsite.

---

## Hypothesis (xii) — `owed`-in-baseKey vs v41 owed-salt reference pattern

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor: same as (i) — the Determinism Forensic EV-maximizer.
- **Equivalence-class proof:** v41 Phase 281 shape: `keccak256(abi.encode(baseKey_v41, entropyWord, groupIdx, ownedSalt))` where `baseKey_v41 = (lvl << 224) | (queueIdx << 192) | player << 32` and `ownedSalt = owed`. v42 MINTCLN shape: `keccak256(abi.encode(baseKey_v42, entropyWord, groupIdx))` where `baseKey_v42 = baseKey_v41 | uint256(owed)` (the low 32 bits previously zero now carry `owed`).
- For any pair of distinct `(lvl, queueIdx, player, owed)` 4-tuples:
  - v41 produces distinct keccak preimages because the 4-tuple is part of the 4-argument hash input.
  - v42 produces distinct keccak preimages because the 4-tuple is encoded into `baseKey` (via bit-packing) which is the first argument of the 3-argument hash input.
  - Both preimages differ on at least one byte → keccak outputs are pairwise-distinct.
- `_rollRemainder` consumers: both v41 and v42 pass `baseKey` (with v42 carrying `owed` in low bits) into `EntropyLib.hash2(entropy, baseKey)`. The `hash2` call inherits whatever distinctness `baseKey` provides. Same equivalence class.
- Zero-owed → rolled-to-1 path (per §(i) Path B): the stale-baseKey concern was addressed in (i). The path is a single-emission terminal branch; no second collision-eligible call follows.

**Notes:**
- The v40 collision class (pre-Phase-281) was: when `owed > writesBudget/2`, multi-call drains produced collidable seeds because `owed` was absent from the seed. v41 added `ownedSalt`; v42 packed it into `baseKey` low bits. Both close the v40 class; v42 is an algebraic rearrangement of v41's fix.
- Economic surface: zero. An attacker who could predict trait emissions from collidable seeds would still have to derive secondary-market value from that prediction, which (a) is pre-launch zero, (b) requires the collision the structural argument rules out.

---

## Hypothesis (xiii) — HRROLL leader-bonus + rngLocked window interaction

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor: an EV-Maximizer trying to write to `dailyHeroWagers[D][q]` during the window between day D's VRF request and the VRF callback — hoping to influence leader identity after randomness commits to be processed but before the actual roll executes.
- **Commitment-window state machine:**
  - Day D wager-writes via `placeDegeneretteBet` at `DegenerusGameDegeneretteModule.sol:484-501` land throughout day D. The write site is gated only by `lootboxRngWordByIndex[index] != 0 → RngNotReady` (L452), meaning ETH bets require the current lootbox RNG to be unconsumed.
  - Day D+1's jackpot resolution triggers a VRF request that produces `randWord`. Per the daily-flow trace, `_unlockRng(day)` runs at the end of day D+1's processing — this sets `dailyIdx = day` AFTER the jackpot has resolved against `dailyHeroWagers[D][q]` (the prior `dailyIdx` value).
  - Concretely: when `_applyHeroOverride` runs during day D+1's `_rollWinningTraits`, it reads `dailyIdx` which still points to day D (the previous day's tag). It reads `dailyHeroWagers[D][q]` — the pool that wagerers built during day D. After resolution, `_unlockRng` updates `dailyIdx` to D+1, freezing day D's pool from further reads in this same context.
- **rngLocked window for wager-writes:** Wager-writes at `placeDegeneretteBet` do NOT check `rngLockedFlag`. They proceed during the rngLocked window. But the writes target `dailyHeroWagers[currentDay][q]` where `currentDay = _simulatedDayIndex()` (wall-clock derived). On day D+1, `currentDay = D+1`, so any wager placed during day D+1's rngLocked window writes to `dailyHeroWagers[D+1]` — NOT to the day-D pool being consumed by the in-flight jackpot.
- **Cross-day boundary races at JACKPOT_RESET_TIME:** The day rollover happens at a wall-clock boundary (82_620 seconds past midnight, per the contract). A wager placed near the boundary lands in either day D's slot (if `_simulatedDayIndex()` returns D at the bet's block.timestamp) or day D+1's slot. There is no window where a wager could be misattributed *across* the boundary — the day-key is single-valued per block.timestamp. The VRF callback for day D's jackpot, when it lands, consumes the *closed* day-D pool because `dailyIdx` was set at day-D's `_unlockRng`.
- **`dailyIdx` single-writer invariant (D-288-FIX-SHAPE-01):** `dailyIdx = day` writes ONLY at `_unlockRng:1730` (verified via the search). No mid-jackpot mutation. The pool the symbol-roll consumes is the pool committed *before* day D+1's VRF request fired.

**Notes:**
- **Counter-argument considered:** "What if a sophisticated whale places a massive bet just before the day rollover, vaulting into leader status with one block of awareness about who else has bet?" — They can do this, but the symbol-roll entropy is unknown at bet-time. Their bet shifts the leader identity for day D's pool, but the symbol roll happens during day D+1's jackpot resolution against unknown entropy. They are paying full bet capital for an *unknown-outcome* leader position. This is the mechanic working as designed; not an exploit.
- **Edge case: bet at exactly `JACKPOT_RESET_TIME - 1 second`.** `_simulatedDayIndex()` returns D at this moment; the bet lands in `dailyHeroWagers[D][q]`. Day D+1 begins at +1 second; the VRF for day D's jackpot may not request until later. Wagerer cannot retroactively change their bet; it's locked. No race.
- Confirmed: commitment-window invariant holds. Wager state for day D is fully committed before day D+1's VRF callback fires.

---

## Hypothesis (xiv) — `retryLootboxRng()` correctness + exploit surface

**Disposition:** SAFE_BY_DESIGN with two minor INFO observations (recorded below)

**Evidence:**
- Economic actor: (a) the Griefer attempting to spam-retry to burn LINK; (b) the Stuck-State Inducer who wants to brick mid-day RNG progression; (c) the Reentrant Attacker abusing the VRF coordinator external-call site; (d) the Liveness Maintainer who legitimately needs to recover from a stalled mid-day VRF.
- **Function gates:**
  - L1133: `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) == 0) revert E();` — only fires when a mid-day buffer-swap is committed.
  - L1134: `if (rngRequestTime == 0) revert E();` — only fires when a request is in-flight.
  - L1135: `if (uint48(block.timestamp) < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT) revert E();` — 6-hour cooldown.
  - L1137-1140: LINK balance check.
  - L1142: VRF request (the only external call).
  - L1153-1154: state updates (`vrfRequestId`, `rngRequestTime`).
- **Docstring correctness check:**
  - (a) "Only reachable when LR_MID_DAY=1": confirmed by L1133 gate.
  - (b) "Re-fires VRF with same parameters": confirmed by L1143-1150 (`vrfKeyHash`, `vrfSubscriptionId`, `VRF_MIDDAY_CONFIRMATIONS`, `VRF_CALLBACK_GAS_LIMIT`, `numWords: 1`, empty extraArgs — identical to `requestLootboxRng`).
  - (c) "Stalled requestId auto-rejected via requestId match in `rawFulfillRandomWords`": at `rawFulfillRandomWords:1750` the gate is `if (requestId != vrfRequestId || rngWordCurrent != 0) return;`. After retry, `vrfRequestId` is overwritten with the new ID; the stalled callback (if it ever arrives) carries the old ID and silently drops. CONFIRMED.
  - (d) "Buffer state and pre-advanced lootboxRngIndex preserved": LR_INDEX is NOT touched by retry. The `_lrWrite(LR_INDEX_SHIFT, ...)` only fires in `requestLootboxRng:1113-1117` and `_finalizeRngRequest:1620-1624` (fresh-request branch). Retry skips both. CONFIRMED.
- **Re-entrancy at L1142:** The external call to `vrfCoordinator.requestRandomWords` happens before the state updates at L1153-1154. Is this a re-entrancy hazard?
  - The VRF coordinator is a Chainlink contract; its `requestRandomWords` returns a request ID and does NOT call back into the caller during the request flow. The only callback is `rawFulfillRandomWords`, delivered asynchronously by a separate transaction.
  - Even if the coordinator could re-enter, the only state mutation between L1142 and L1153-1154 is local to the function (the `id` return). Re-entering `retryLootboxRng` would re-check the gates: `rngRequestTime` is still the old value (so the cooldown check would re-pass *only if 6 hours have elapsed*, which is a separate transaction concern); LR_MID_DAY is unchanged. The function is effectively idempotent on re-entry; it would just fire another VRF request.
  - Cost-of-attack: each re-entry burns LINK. The griefer pays the LINK cost themselves only if they control the coordinator (they don't — Chainlink does).
  - Re-entrancy assessment: SAFE (no harmful state read/write between external call and state updates).
- **Griefing surface — permissionless retry + LINK consumption:**
  - The function is permissionless. After the 6-hour timeout, anyone can fire a retry, which costs the protocol LINK from the subscription.
  - Cap on griefing: 1 retry per 6-hour window (the cooldown check requires `block.timestamp >= rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT`; after retry, `rngRequestTime` is reset to current). Maximum 4 retries per day per stuck VRF.
  - **Capital cost to griefer:** ETH gas for the retry transaction (~80k gas × gwei). Marginal cost.
  - **LINK cost to protocol per retry:** A few LINK at typical gas prices (Chainlink VRF subscription cost per request, ~0.25 LINK on Ethereum mainnet for the 200 callback-gas range).
  - **Steady-state griefing:** A griefer could in theory fire 4 retries/day on a stuck VRF. But the function only fires when there's actually a stuck VRF (LR_MID_DAY=1 AND rngRequestTime != 0). If the VRF is healthy, no retry can fire. So the griefer is bounded to the window when the protocol genuinely needs a retry — exactly the window the function is designed for.
  - **Net griefing assessment:** The "griefer" is functionally identical to a "liveness maintainer" — the only reason to call the function is to attempt to unstick mid-day RNG. The retry is exactly what the protocol wants in that situation. There is no harm vector unless the LINK subscription budget is depleted faster than expected — bounded by 4 retries × `stuckdays` per stuck-VRF window.
- **Stuck-state edge case: daily-flow takes over while LR_MID_DAY=1.**
  - Trace: suppose mid-day RNG is requested at noon (LR_MID_DAY=1, rngRequestTime set). Before VRF delivers, the daily jackpot resolution time arrives. Daily flow calls `_requestRng` → `_finalizeRngRequest` which sets `isRetry = vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0`. With the mid-day request in flight, `isRetry == true`; the daily flow re-uses the in-flight VRF and sets `vrfRequestId = requestId` (overwriting), `rngLockedFlag = true`. The mid-day callback (if it ever arrives) would carry the old `vrfRequestId` and silently drop at `rawFulfillRandomWords:1750`.
  - Now: the daily VRF callback delivers. `rawFulfillRandomWords:1755` checks `if (rngLockedFlag)`: true → stores `rngWordCurrent = word`, daily flow consumes it. `_unlockRng` is called at the end of daily processing, which sets `rngRequestTime = 0`, `vrfRequestId = 0`, `rngLockedFlag = false`. CRITICALLY: `_unlockRng` does NOT clear LR_MID_DAY.
  - Post-`_unlockRng` state: `LR_MID_DAY = 1` (set during the original mid-day request, never cleared), `rngRequestTime = 0` (cleared by `_unlockRng`), `rngLockedFlag = false`.
  - Next call to `retryLootboxRng`: gate at L1134 `if (rngRequestTime == 0) revert E();` REVERTS. The retry function is locked out.
  - Next call to `requestLootboxRng`: gate at L1057 `if (rngRequestTime != 0) revert E();` — passes (rngRequestTime IS 0). But gate at L1047 `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert E();` — REVERTS (LR_MID_DAY is still 1). Locked out.
  - **Stuck-state result:** Mid-day lootbox RNG is bricked. The mid-day buffer swap is committed (a write→read swap moved post-swap purchases to a fresh write slot), the LR_INDEX is advanced, but no `lootboxRngWordByIndex[LR_INDEX - 1]` ever gets written. Players who purchased lootboxes in the post-swap window have their tickets bound to an empty RNG index. The `advanceGame:209-214` path on the next day will see `_lrRead(LR_MID_DAY_SHIFT, ...) != 0` AND `lootboxRngWordByIndex[index-1] == 0` → reverts `RngNotReady`. Daily progression is STUCK.
  - **Mitigation paths in the deployed code:** `updateVrfCoordinatorAndSub:1697-1698` explicitly clears LR_MID_DAY via `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);`. This is the governance-gated emergency exit. The natspec at L1696-1697 documents the specific scenario: "Clear mid-day lootbox RNG pending flag to prevent post-swap deadlock. Without this, advanceGame can revert with NotTimeYet if a mid-day requestLootboxRng was in-flight when the coordinator stalled." CONFIRMED: the governance-recovery path already handles this case.

**Notes:**
- **Two INFO-level observations (NOT findings — recorded for the record):**

  **INFO-1: Daily-flow overrides mid-day VRF, then `_unlockRng` clears `rngRequestTime` but leaves LR_MID_DAY=1, locking out `retryLootboxRng`.** The scenario is fully handled by the `updateVrfCoordinatorAndSub` admin path. No autonomous (permissionless) recovery is available, but this is consistent with the protocol's stance that coordinator-stall recovery requires governance. The condition is rare (requires mid-day VRF + daily-flow takeover + post-takeover VRF actually delivering — at which point the daily VRF resolution succeeds but the mid-day buffer remains semantically orphaned). Documenting the recovery path in the function-level natspec would aid future operators but is not a blocking concern.

  **INFO-2: Permissionless retry consumes LINK from the protocol subscription with no rate-limit beyond the 6-hour timeout.** Bounded griefing surface: 4 retries/day per stuck VRF × LINK-per-request. At typical mainnet costs, ~1 LINK/day of avoidable burn in the worst case (4 retries × 0.25 LINK), and only in the actual stuck-VRF window. The mechanism design treats this as acceptable because the only call-path is "VRF is genuinely stuck" — the griefer's cost-to-protocol equals the legitimate maintainer's. No bad-faith dominant strategy exists.

- Both observations are operational rather than economic-exploit; logged for completeness, not as FINDING_CANDIDATE.
- **Equilibrium:** The permissionless retry path's Nash equilibrium is "call when stuck, ignore when healthy." No actor benefits from spam-calling on a healthy VRF (reverts at L1133/L1134/L1135). The function is incentive-compatible.

---

## Beyond-Charge Hypothesis (xv) — Hero-symbol leader bonus rounding floor at small leader amounts

**Disposition:** NEGATIVE_RESULT_ONLY

**Evidence:**
- Economic actor: a small-bettor griefer noticing that `leaderBonus = maxAmount / 2` performs integer division.
- At `maxAmount = 1` (the smallest possible non-zero leader, i.e., a sole 1-wager-unit bet), `leaderBonus = 0`. The leader gets no bonus; `effectiveTotal = total`. The roll is pure-proportional in this degenerate case.
- At `maxAmount = 2`, `leaderBonus = 1`. `effectiveTotal = total + 1`. Bonus is marginal.
- At `maxAmount >= 10` (realistic floor), `leaderBonus >= 5` (50% of `maxAmount`), as designed.
- **Economic surface:** is there a strategy exploiting the rounding-to-zero at `maxAmount = 1`? A whale could in principle ensure their bet is `maxAmount = 1` (a pseudo-leader with no bonus). But this would require their bet to be the *largest single slot bet at* 1 wager-unit — meaning the entire pool has at most 1 wager-unit per slot. In that scenario, the whale and every other bettor have identical odds (pure-proportional). No exploit — they've just opted out of the bonus by being the smallest possible leader.
- **No actor can benefit** from forcing `leaderBonus = 0`. The mechanic still resolves correctly (any winner is chosen proportionally).

**Notes:**
- This is a curiosity, not a vulnerability. The integer-division floor at `maxAmount = 1` produces a degenerate pure-proportional roll, which is a valid outcome of the mechanism. The design-intent §(ii) records that pure-proportional was REJECTED as the *default* design, but as a degenerate edge case at `maxAmount = 1` it is harmless.

---

## Beyond-Charge Hypothesis (xvi) — Activity-score farming via Degenerette spam under HRROLL no-floor

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Economic actor: an EV-Maximizer who notices Degenerette ETH bets at L426-434 award quest progress via `quests.handleDegenerette`, which contributes to the player's quest-streak — a component of `activityScore` consumed at L457-460. The attacker hopes to spam tiny bets to farm activity-score without proportional bet capital.
- `quests.handleDegenerette(player, totalBet, currency == CURRENCY_ETH, priceWei)` is the quest progress sink. Quest progress is gated by `totalBet` (the actual ETH-denominated stake), not by `wagerUnit` (the down-scaled hero-wager amount). To earn meaningful quest progress, the attacker must place real ETH bets at full bet capital.
- The activity-score elevates the player's lootbox-bound payout multiplier. Earning the multiplier costs the player ETH bet capital with normal expected return on each bet. The attacker cannot earn elevated multipliers without committing the corresponding bet capital.
- **Capital-cost calculation:** Suppose the attacker wants to reach the top-tier activity score. They must place enough bets to satisfy the quest-streak thresholds. Each bet pays the standard Degenerette expected return (~0.95-1.0 EV depending on bet shape). The attacker pays full bet capital with normal house-edge. No subsidized path to high activity-score.

**Notes:**
- The Degenerette quest progress is correctly bet-capital-gated. No farming path. SAFE_BY_STRUCTURAL_CLOSURE on the cross-cited HRROLL no-floor surface (the attacker cannot use sub-bet-floor dust to farm quest progress).

---

## Beyond-Charge Hypothesis (xvii) — Deity-pass holder commons-tier capital crowding effect on organic Degenerette EV

**Disposition:** ACCEPTED_DESIGN

**Evidence:**
- Cross-cited from (viii) walk. If deity-pass holders shift Degenerette bet capital from gold-tier symbols to commons-tier symbols in response to DPNERF, the per-bucket organic-bettor odds shift accordingly.
- Specifically: commons-color organic bettors face elevated competition for trait-bucket positioning if deity-pass capital floods commons-color slots. Their per-bettor win-probability declines proportionally to the new bucket size.
- This is the natural mechanic operating: more competition for a fixed prize-pool slice → lower per-bettor share. It is not an exploit; it is the protocol's price-discovery mechanism for bet allocation.
- The deity-pass holder cannot extract value above-and-beyond their bet capital. They pay full bet price for the position; their commons-tier wins return the standard payout. They cannot "double-dip" using the virtual entries (the virtual entries are tied to the deity's symbol, not to where they place bets).

**Notes:**
- Equilibrium: organic commons-tier bettors and deity-pass holders share the commons buckets proportionally to capital committed. No actor extracts more than they commit. Per D-42N-DEITY-EV-01, this rebalance is accepted as a feature of the nerf.
- **Counter-argument considered:** "Could deity-pass holders coordinate to flood specific commons buckets, then deity-virtual their way to a 'free' win?" — The deity virtual entries fire only on the deity's *symbol*, not on arbitrary commons buckets. Flooding a commons bucket where the deity has no symbol-ownership produces no extra deity-virtual entries. Coordination attack: NEGATIVE.

---

## Cross-Cutting Notes (Persona Output)

1. **Load-bearing hypotheses (iv), (v), (viii), (ix), (xiv) — all disposition SAFE** (with two INFO observations on xiv). The economic walk confirms no incentive-misalignment vectors are introduced by the v42 audit subject.

2. **Death-spiral analysis across the audit subject:** None of the three core changes (MINTCLN event-cleanup, HRROLL weighted-roll, DPNERF gold-tier nerf) introduce negative feedback loops. HRROLL's `×1.5` is bounded; DPNERF's nerf is targeted and accepted; MINTCLN is event-shape only.

3. **Variance-filter integrity:** The HRROLL change deliberately shifts the hero-override mechanic from deterministic (whale-always-wins) to probabilistic (whales-mostly-win). This *strengthens* the variance-filter design intent — more variance to attract degens, fewer guaranteed extraction paths for capital-only whales who don't engage with the game.

4. **Activity-score system integrity:** No path through the audit subject introduces a metric-gaming surface. All bet-driven progressions remain bet-capital-gated.

5. **Affiliate / FLIP / vault mechanisms:** Untouched by the audit subject. No cross-cutting risk.

6. **Adverse selection check:** The DPNERF change re-equilibrates deity-pass economics modestly downward. Holders who acquired the pass for gold-tier extraction face reduced EV; the equilibrium rebalances toward broader-color participation. This is consistent with the protocol's stated "select for engaged players, not extractors" design intent.

---

*Phase 296 adversarial pass; `/economic-analyst` skill; produced 2026-05-18 against v42.0 audit subject (MINTCLN + HRROLL + DPNERF + retryLootboxRng). 14 charged hypotheses + 3 beyond-charge hypotheses. Zero FINDING_CANDIDATE dispositions. Two INFO-level observations on (xiv) recorded as operational notes, not findings.*
