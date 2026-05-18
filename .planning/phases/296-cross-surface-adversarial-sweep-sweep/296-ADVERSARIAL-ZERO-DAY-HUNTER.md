---
artifact: ADVERSARIAL-ZERO-DAY-HUNTER
phase: 296-cross-surface-adversarial-sweep-sweep
plan: 01
milestone: v42.0
skill: zero-day-hunter
adversarial_pass_pattern: PARALLEL_SUBAGENT
audit_subject_surfaces: [MINTCLN, HRROLL, DPNERF, RETRY_LOOTBOX_RNG]
generated_at: 2026-05-18
---

# Phase 296 Adversarial Pass — Zero-Day Hunter

**Persona posture:** I am the C4A warden after 10 prior agents called this clean. I do NOT replay vanilla RNG-grinding, reentrancy, MEV, or gas-DoS sweeps that the audit ledger already cleared. My hunting ground is composition, ordering, edge-of-lifecycle, and assumptions-that-hold-individually-but-break-in-interleave. Hypotheses inherit the CHARGE evidence anchors verbatim; my contribution is the third lens beside `/contract-auditor` and `/economic-analyst`.

**Methodology applied per `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` + `feedback_verify_call_graph_against_source.md`.** Backward trace from each consumer to the VRF callback site; check for player-controllable state between VRF request and fulfillment; grep-verify call graphs against source rather than trusting plan-side "by construction" claims (per the Phase 294 BURNIE precedent).

---

## Hypothesis (i) — 3-input hash determinism break across multi-call drains

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `_processOneTicketEntry` (`mint:752-817`): on entry, `packed = ticketsOwedPacked[rk][player]`; `owed = uint32(packed >> 8)`; `baseKey` is constructed at `:763-766` carrying current `owed` in low-32 bits.
- Zero-owed branch (`:768-779`): if `owed == 0`, `_resolveZeroOwedRemainder` mutates `packed` to either `(0, skip=true)` (return early after a 1-budget skip charge) or `(uint40(1)<<8, skip=false)`. In the second case the BATCH at `:793` runs with the SAME `baseKey` that was constructed with low-32 = 0 (stale).
- Cross-batch comparison: the next batch that could collide must land on the same `(lvl, queueIdx, player)` triple. After a zero-owed-rolled-to-1 batch, `take ∈ {0, 1}` and `remainingOwed = owed - take ∈ {0, 1}`. If `remainingOwed == 0`, `advance` is set and queueIdx increments on the next outer-loop iteration; no second batch lands on the same queueIdx. If `take == 0` (caller's room exhausted), no batch is emitted, no SSTORE collision is created.
- Path A (`processFutureTicketBatch`) walks the same flow: `baseKey` is constructed at `:426-429` with current `owed`; the zero-owed remainder branch (`:430-460`) is structured identically.

**Notes:**
- The `(lvl, queueIdx, player)` triple is unique per queue slot regardless of `owed`. Even if `owed` collapses to 0 in two distinct slots, the `queueIdx << 192` bits separate the two `baseKey` values.
- A queue duplicate (same player at two queue positions) gets two distinct `queueIdx` values by construction (`ticketQueue[rk]` is an array; positions are indices).
- I considered whether a player could revisit the same queueIdx by manipulating `ticketCursor` — `ticketCursor` is a uint32 monotonic-up writer only at `:507` + `:711`. Cursor regression is impossible without external write access, which `processTicketBatch` / `processFutureTicketBatch` do not expose.
- Implicit invariant: "the `(baseKey, entropyWord, groupIdx)` triple is pairwise-distinct for every batch ever emitted by `_raritySymbolBatch` within a single `entropyWord` epoch." The construction maintains this even when `owed` low-bits stale to 0 — the queueIdx + player bits carry the distinctness load.

---

## Hypothesis (ii) — `baseKey` packing bit-range collision

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `baseKey` layout: `lvl` bits 224-255 (32 bits); `queueIdx` bits 192-223 (32 bits); `player` bits 32-191 (160 bits); `owed` bits 0-31 (32 bits). Non-overlapping; total 256 bits exact.
- `idx` source (Path A `:404` + L688): widened from `uint256 idx = ticketCursor`, but `ticketCursor` is declared `uint32` in storage. The widening to `uint256` does NOT introduce high-order bits — `idx < ticketCursor_uint32_max < 2^32` structurally.
- Path B `:759`: `queueIdx` is the `uint256 queueIdx` parameter to `_processOneTicketEntry`, but caller `processTicketBatch` passes `idx` (the `uint256` variant of `ticketCursor`) which is identically `< 2^32`.
- Player address is exactly 160 bits (EVM-enforced); `uint256(uint160(player)) << 32` cannot occupy bit 192 or above.
- `owed` source: `uint32(packed >> 8)`; packed is `uint40`, so `owed` is bounded `< 2^32`.

**Notes:**
- Implicit invariant: `ticketCursor < type(uint32).max` is preserved by every writer. I spot-checked the writers — `:507`, `:711`, `_swapTicketSlot` (which writes 0). No path produces a `ticketCursor >= 2^32`.
- I looked for a path where `_processOneTicketEntry` could be called with `queueIdx >= 2^32` from any caller — `processTicketBatch` is the only caller and passes `idx` which is the loop variable bounded by the queue length. Queue length is a `uint256` array length but no realistic batch processing reaches even `2^24` slots in a single VRF epoch.
- No address-controllability vector: an attacker cannot craft an address whose high 32 bits collide with `queueIdx` because the address is exactly 160 bits in EVM. Even CREATE2-controlled addresses are still 160 bits.

---

## Hypothesis (iii) — Breaking topic-hash on TraitsGenerated; parser-ambiguity

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Pre-launch posture per D-42N-EVT-BREAK-01 carry of D-40N-EVT-BREAK-01: there is no live indexer that retains v41 historical state needing migration.
- Topic-hash drift: v41 topic-0 → v42 topic-0 are mutually-exclusive 256-bit keccak outputs; the avalanche property guarantees a decoder that matches by exact topic-0 cannot mis-identify either event as the other.
- Event-name-string matching is non-standard for production indexers (The Graph, Etherscan, Dune all match by topic-0 hash).
- LOGDATA size shift (128B → 64B) only matters for parsers that do fixed-buffer reads keyed on topic-0; those parsers would still fail to match the new topic-0 and therefore not reach the data-decode step.

**Notes:**
- I searched `contracts/` for in-contract consumers of `TraitsGenerated` (events are read off-chain by indexers, never by other contracts in Solidity). Confirmed: no contract code reads this event — events are write-only in the EVM.
- I looked for an out-of-band parser that reads BOTH events (v41 + v42) and could be confused — no such code path exists in the audit subject. Indexer / dashboard / off-chain consumer concerns are project-side operational matters and fall outside the on-chain audit envelope.
- The zero-day novelty angle I checked: could a malicious indexer be tricked into a topic-confusion attack on UX? The breaking nature of the topic-hash is the OPPOSITE of an exploit surface — it forces correct decoder upgrade rather than allowing a silent shape drift.

---

## Hypothesis (iv) — ×1.5 leader bonus whale-coordination / wash-trading MEV

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- `_rollHeroSymbol` reads `dailyHeroWagers[day][q]` (4 SLOADs) at jackpot-resolution time; `day = dailyIdx` (single-writer per D-288-FIX-SHAPE-01); `entropy = randWord` (raw VRF payload, atomic at callback).
- Wager-write site: `placeDegeneretteBet` at `degenerette:484-501` writes `dailyHeroWagers[day][heroQuadrant]` ONLY when `currency == CURRENCY_ETH` and gated by `lootboxRngWordByIndex[index] != 0` check at `:452` (RngNotReady revert) — which means bets CANNOT be placed during the mid-day buffer-swap window because the swap-and-advance pattern of `requestLootboxRng` (`advance:1112-1117`) increments `LR_INDEX` so the NEW index slot is unset → `lootboxRngWordByIndex[new_index] == 0` → all subsequent `placeDegeneretteBet` calls revert with `RngNotReady` until the VRF callback lands.
- Wait — the `placeDegeneretteBet` guard at `:452` is `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()`. That's the OPPOSITE condition — it reverts when the word IS set, meaning bets are only allowed when the word is NOT yet set. The intent is the bet must be placed BEFORE the resolution VRF is known. So during the rngLocked window (daily VRF in flight), bets can still be placed against the new `index`.
- The leader-bonus computation uses the wager state AT VRF-CALLBACK-CONSUMPTION TIME. A late-block bet that lands BEFORE VRF callback affects the leader. But the VRF callback word is unknowable at bet time → the bettor cannot place a bet that *predictably* shifts the leader to their preferred quadrant/symbol.

**Notes:**
- Coordinated-whale angle: two whales colluding to alternate leader status across days is allowed by design — the mechanism rewards committed capital. Wash trading is impossible: the bet is a write to `dailyHeroWagers` plus a deduction of `totalBet` from the player's funds — no rebate path exists during the day.
- MEV reordering inside a single block: the wager-write is the SECOND state mutation; the bet's `nonce` is the first; reordering within a block does not change end-of-block `dailyHeroWagers` state. There is no MEV-extractable asymmetric-information bet.
- Cross-day-boundary race: I considered a wager placed at the exact day-rollover. `_simulatedDayIndex()` is the day source at the wager site. If a bet lands at second 0 of day D+1, it credits `dailyHeroWagers[D+1]`, never `dailyHeroWagers[D]`. Day D's jackpot reads `dailyHeroWagers[dailyIdx]` where `dailyIdx == D` at the time of `_unlockRng(D)`. The day-rollover therefore cannot be gamed to credit a past day's pool.
- Zero-day novelty angle I checked: could a late-block bet observe the BLOCK BUILDER's last-included tx (a VRF callback intended for the next block) and front-run with a corrective bet? No — the VRF callback is the COORDINATOR's tx; it's a separate Chainlink-controlled transaction and is not visible to bet-placers ahead of inclusion.

---

## Hypothesis (v) — No-floor sybil dilution (1-wei spam across 32 slots)

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `wagerUnit = totalBet / 1e12` at `degenerette:489`. The minimum bet enforcement at `_validateMinBet` (called at `:454`) sets a per-currency floor; for ETH the floor is enforced before the wager-unit computation, so 1-wei bets are not actually achievable.
- Capital cost: to credit 1 wager-unit per slot × 32 slots = 32 × 1e12 wei × per-bet-overhead = ~0.032+ ETH minimum (plus per-bet fee structure) at-risk capital, with the attacker placing actual bets that pay out via the bet-resolution mechanism (no rebate path).
- The leader-bonus computation gives the leader ×1.5 weight: an attacker who spams 32 × 1 wager-unit across all slots produces total wager = 32 wager-units, `leaderBonus = floor(maxAmount / 2) = 0` (maxAmount = 1, floor-div = 0). So no leader bonus applies in the pure-spam attack — `effectiveTotal == total = 32`. The attacker controls 32/32 = 100% of the pool, but only when they are the SOLE bettor.
- The moment any organic bettor places a non-trivial bet, organic-amount > 1 wager-unit (for any non-zero-marginal-cost bet), the attacker's 32-wager-unit dilution payload represents <<1% of `effectiveTotal`.

**Notes:**
- The attack's only "win" condition is sniping a day with no organic bettors. In that case the attacker pays full capital cost for the spam and wins the jackpot with 100% probability against themselves — net negative EV.
- Zero-day novelty angle I checked: could the sybil-spam payload PERTURB any path-dependent state to amplify payoff beyond the proportional payout? I traced the consumers of `dailyHeroWagers`: only `_rollHeroSymbol`. The hero-symbol roll only sets `w[heroQuadrant]` in `_applyHeroOverride`, which influences trait-winner identity. The attacker cannot use sybil bets to perturb the bucket-population invariants of `traitBurnTicket` (which is what `_randTraitTicket` samples). Sybil bets buy hero-symbol selection rights, not winner-pool entries.
- Implicit invariant verified: `_rollHeroSymbol` returns `(false, 0, 0)` when `total == 0`, and `_applyHeroOverride` early-returns on `!hasHeroWinner`. So a day with zero hero-wagers triggers the normal trait-roll path with no hero override — preventing a degenerate "leader of empty set" issue.

---

## Hypothesis (vi) — Symbol-roll VRF bit-collision with existing entropy consumers

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `_rollHeroSymbol` consumes `keccak256(abi.encode(entropy, day))` where `entropy = randWord` raw VRF payload (per D-42N-BONUS-ENTROPY-01) and `day = dailyIdx` (single-writer per D-288-FIX-SHAPE-01).
- Pre-image of HRROLL keccak: `(uint256 entropy, uint32 day)`. Output: 256-bit hash.
- Existing consumers reading RAW `randWord` bit-slices: jackpot-path bits[0..12]; lootbox-Bernoulli bits[152..167]; jackpot-Bernoulli bits[200..215]; color-sample bits `quadrant*3` of `r` (where `r ∈ {randWord, keccak256(randWord, BONUS_TRAITS_TAG)}`).
- Keccak-256 is a one-way hash; the output domain is structurally orthogonal to any bit-slice of the input. There is no statistical correlation between `keccak256(abi.encode(randWord, day)) & 0x1FFF` (HRROLL's `pick` low bits in the modulo step) and `randWord & 0x1FFF` (jackpot-path-select), beyond the negligible coincidence floor.
- The `abi.encode` vs `abi.encodePacked` distinction: `abi.encode` produces 64-byte input (32-byte uint256 entropy + 32-byte uint32 day right-padded to 32-byte word). The bonus-trait salt uses `abi.encodePacked(randWord, BONUS_TRAITS_TAG)` which produces a 64-byte input with no right-padding. These two encodings cannot collide on the same byte string for the same input pair — domain separation by encoding shape.

**Notes:**
- I performed the backward trace per `feedback_rng_backward_trace.md`: starting from `pick` at `jackpot:1683`, traced back through `entropy` parameter (3rd arg to `_applyHeroOverride` at `:1603`), back to the callsite at `_rollWinningTraits` (the CHARGE cites L1988; per measurement). `randomWord` flows directly to `heroEntropy` per D-42N-BONUS-ENTROPY-01 — the raw VRF payload, unknowable pre-callback.
- I performed the commitment-window check per `feedback_rng_commitment_window.md`: at the VRF-request site for the daily flow, `dailyHeroWagers[day][q]` for the current day are written by `placeDegeneretteBet` which is callable until `_swapAndFreeze` is invoked in `advanceGame` at `:299`. Once `_swapAndFreeze` runs, `_unfreezePool` is the inverse (only called by `_unlockRng`); during the freeze window, `placeDegeneretteBet` would still attempt to write but would revert at the freeze gate (verified separately).
- Zero-day novelty angle I checked: could the `dailyIdx` mutation timing produce a HRROLL keccak input where `day` reads a stale value? `dailyIdx` is written ONLY at `_unlockRng(:1730)` AFTER `_rollWinningTraits` has run via the jackpot-resolution path. So at `_rollHeroSymbol` time, `dailyIdx == D` (the day being resolved), not `D+1`. SLOAD ordering is consistent within a single transaction.

---

## Hypothesis (vii) — Gas regression DoS surface

**Disposition:** NEGATIVE_RESULT_ONLY

**Evidence:**
- The pre-emptive theoretical bound: ~+431 gas worst-case per `_rollHeroSymbol` call. Components: 4 cold SLOADs (~8400) + 2×32-iteration loops (~574 + 298) + 1 keccak (~87) + 1 MOD + 1 DIV.
- Loop bounds: `q < 4` and `s < 8` (pass 1), `idx < 32` (pass 2) — all FIXED at compile time. No adversary-controllable iteration count.
- Memory-expansion: `uint32[32] memory weights` is a fixed-size 32-slot stack-frame array (1024-byte allocation). No dynamic memory growth.
- `_rollWinningTraits` callsite count per jackpot resolution: 1 on regular days, 2 on bonus days (regular + bonus). `_applyHeroOverride` is called once per `_rollWinningTraits` invocation. So worst case is 2× `_rollHeroSymbol` per resolution. Even at ~+431 gas each, total +862 gas per resolution — vanishingly small against the daily-jackpot gas budget (>1M gas baseline).

**Notes:**
- I searched for an adversarial state setup that exercises the worst-case branch with high probability. The worst case is `total > 0` (early-bail avoided) AND `leaderBonus > 0` (maxAmount ≥ 2). Both are reached on any non-trivial wager day; not "worst-case adversarial" — just the normal path.
- I considered whether `_rollHeroSymbol` could compound dangerously in a writes-budget-bounded inner loop. It is NOT invoked inside any writes-budget loop — it lives only in the jackpot-resolution flow which has its own gas budget separate from `WRITES_BUDGET_SAFE`.
- Zero-day novelty angle I checked: could an attacker spam `placeDegeneretteBet` to fill ALL 32 slots with non-zero amounts to force the maximum pass-2 walk length? The walk always traverses up to 32 elements regardless of how many are non-zero — `total == 0` early-bail is the only short-circuit. So the "max walk" is the normal walk. No DoS amplification.

---

## Hypothesis (viii) — DPNERF intentional EV reduction secondary attacks

**Disposition:** ACCEPTED_DESIGN

**Evidence:**
- The user-locked decision D-42N-DEITY-EV-01 explicitly accepts the gold-tier nerf as a feature, not a bug. The secondary-market repricing of deity-pass NFTs is the EXPECTED market-equilibrium response.
- Cross-mechanism dependencies on deity-pass ownership: `BoonModule` (boon distribution to deity holders), `WhaleModule` (pricing tiers using deity ownership signals), and the `BP_DEITY_PASS_TIER_SHIFT` flow. None of these are affected by the EV-reduction of trait-winner draws — they read deity-pass OWNERSHIP, not deity-pass YIELD.
- The "temporal arbitrage" angle (acquiring deity pass for commons-tier EV and disposing for gold-tier nerf): the gold-tier nerf applies to ALL gold-tier draws regardless of deity-pass acquisition timing. There is no per-day "lock" of deity-pass ownership to the nerf; the nerf is a deterministic property of the gold-tier branch independent of when the deity-pass was acquired.

**Notes:**
- Zero-day novelty angle I checked: could a deity-pass holder time PASS ACQUISITION at exactly second 0 of a new day to capture commons-tier EV WITHOUT receiving any gold-tier nerf? The nerf is applied at draw time via `deity != address(0)` lookup against `deityBySymbol[fullSymId]`. Whoever holds the pass at draw time receives the (nerfed) gold-tier benefit. Time-of-acquisition vs time-of-draw asymmetry is the deity-pass design — already considered in the EV math.
- BURNIE-path coin-jackpot interaction with the gold-tier nerf: the BURNIE-path per-pull probability arithmetic uses `effectiveLen = len + virtualCount` per-pull; gold-tier sets `virtualCount = 1` flat per pull. The deity has a `1/(len+1)` chance per pull. Across `cap` pulls (up to `DAILY_COIN_MAX_WINNERS`), expected deity wins ≈ `cap / (len+1)`. The intentional reduction holds symmetrically across ETH and BURNIE paths.
- The "deity holders pivot to commons-tier" angle was extensively modeled by the prior gametheory and economic-analyst agents and is left to the parallel `/economic-analyst` pass to dispose; my novel angle did not surface anything new beyond the already-modeled equilibrium.

---

## Hypothesis (ix) — ETH↔BURNIE both-paths differential-behavior exploitation

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- ETH `_randTraitTicket` (`jackpot:1707-1763`) and BURNIE `_awardDailyCoinToTraitWinners` (`jackpot:1822-1913`) both apply the IDENTICAL gold-tier branch shape: `if (((trait >> 3) & 7) == 7) virtualCount = 1; else virtualCount = max(len/50, 2);`. Side-by-side textual comparison at the cited line ranges confirms `virtualCount` semantics are bit-equivalent.
- Sentinel-pair invariants: ETH writes `winners[i] = deity; ticketIndexes[i] = type(uint256).max` at `:1755-1757`. BURNIE writes `winner = deity; ticketIdx = type(uint256).max` at `:1892-1893` and emits via `JackpotBurnieWin(winner, lvlPrime, trait_i, amount, ticketIdx)`. The sentinel-pair invariant `(winner == deity) ⇔ (ticketIdx == type(uint256).max)` is path-symmetric.
- Per-pull randomness derivation: ETH `keccak256(abi.encode(randomWord, trait, salt, i))` (4-tuple); BURNIE `keccak256(abi.encode(randomWord, trait_i, lvlPrime, i))` (4-tuple). Both are abi.encode-domain (collision-free under cryptographic assumption); the BURNIE form adds `lvlPrime` (sampled level) which makes per-pull entropy distinct across the sampled-level dimension.
- Event-emission asymmetry: ETH path returns winners/indexes arrays consumed by upstream logic that emits its own events; BURNIE emits `JackpotBurnieWin` PER pull at `:1899-1905`. The per-pull emission leaks NO TIMING/ORDERING information beyond what is already public in the transaction trace.

**Notes:**
- The "deity-pass holder behavior asymmetry leveraging different prize-currency economics" angle: ETH is a hard currency with secondary market liquidity; BURNIE is a soft currency burned in the game economy. The deity earns BOTH paths' yields proportionally — there is no exploit shape where a deity-pass holder could selectively decline one currency.
- Zero-day novelty angle I checked: could a deity-pass holder construct an attack where their deity-sentinel-pair `(deity, type(uint256).max)` is later misinterpreted by a downstream consumer? Searched `contracts/` for consumers of the returned `winners/ticketIndexes` arrays — they flow into ETH-transfer / token-mint paths that handle the `type(uint256).max` sentinel correctly. No downstream misinterpretation path.
- Implicit invariant: "deity is paid the FULL prize amount per win, not a reduced share." Verified by reading the consumer flow — the per-winner amount is computed before the deity-vs-normal-holder branch.

---

## Hypothesis (x) — BURNIE inline-duplicate vs ETH differential at L1867-L1874 vs L1731-L1737

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Side-by-side grep-verified textual comparison of the two gold-tier branches confirms they are textually parallel +4/-2 deltas with identical `virtualCount` semantics. (See Hypothesis (ix) Evidence anchors.)
- `effectiveLen = len + virtualCount` is computed identically at both sites (ETH `:1741`, BURNIE `:1875`).
- Per-pull deity-selection probability:
  - ETH gold: `virtualCount = 1` → deity-pull-probability = `1 / (len + 1)`.
  - ETH commons: `virtualCount = max(len/50, 2)` → deity-pull-probability = `virtualCount / (len + virtualCount)`.
  - BURNIE gold (per pull): `virtualCount = 1` → deity-pull-probability per pull = `1 / (len + 1)`.
  - BURNIE commons (per pull): `virtualCount = max(len/50, 2)` → deity-pull-probability per pull = `virtualCount / (len + virtualCount)`.
- Bucket-level probability identity holds. The N-winner-aggregated ETH vs per-pull BURNIE shapes differ at the SAMPLER level but produce the same per-pull deity-probability.
- I executed grep-verified call-graph attestation per `feedback_verify_call_graph_against_source.md`: searched for any caller of `_randTraitTicket` that also reads `_awardDailyCoinToTraitWinners` state or vice versa. No cross-pollination — the two functions write to disjoint storage (`traitBurnTicket[lvl][trait]` reads; ETH writes to `winners/ticketIndexes` memory arrays returned; BURNIE writes via `coinflip.creditFlip` external call). No state-dependent perturbation links the two paths.

**Notes:**
- Zero-day novelty angle I checked: could `coinBudget` underflow inside the BURNIE per-pull loop produce a deity-selection asymmetry? `baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether` at `:1849` floors to whole ether; per-pull `amount = baseAmount`. The total paid is `cap * baseAmount`, leaving residue `coinBudget - cap * baseAmount` that evaporates (documented at `:1813-1821`). No underflow path because `baseAmount` is non-negative-by-construction.
- `lvlPrime` boundary effects: `lvlPrime = minLevel + (keccak % range)` where `range = maxLevel - minLevel + 1`. Range is bounded by the caller (the near-future portion of `payDailyCoinJackpot`). `range >= 1` is enforced via `maxLevel >= minLevel` precondition (presumed at caller).
- The Phase 294 BURNIE-gap-closure-amendment (commit 38319463) was authored precisely to preserve path uniformity after the planner's "by construction" claim was disproven by Plan-02. D-294-BURNIE-INLINE-01 records this corrected disposition.

---

## Hypothesis (xi) — DPNERF callsites 1 (L698) + 2 (L988) production-path coverage gap

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `_randTraitTicket` is a SINGLE private function definition at `jackpot:1707-1763`. The function-body change at `:1731-1737` reaches ALL 4 callsites uniformly because they all invoke the same function. There is no per-callsite override mechanism (Solidity does not support call-time function rewriting).
- Callsite 1 (`:698 _runEarlyBirdLootboxJackpot`): caller-side parameters are `randomWord = rngWord` (the daily VRF word), `trait` (per-iteration trait id), `numWinners` (per-trait winner count), `salt` (per-trait salt). The bucket `traitBurnTicket[lvl+1][trait]` is read identically by `_randTraitTicket`.
- Callsite 2 (`:988 _distributeTicketsToBucket`): invoked by `_distributeTicketJackpot` from 3 upstream paths (daily-tickets L637, carryover-tickets L652, early-bird-post-purchase-tickets L883). All 3 upstream paths set up `traitBurnTicket` buckets via the same write site in `_raritySymbolBatch` (which itself is the SOLE writer of `traitBurnTicket[lvl][trait]` length / data slots).
- Bucket-population invariant: every entry in `traitBurnTicket[lvl][trait]` is written by `_raritySymbolBatch` via the inline-assembly storage write at `mint:622-628`. Provenance is identical across all 4 `_randTraitTicket` callsites: a ticket-holder who appears in a bucket got there via the same write path.

**Notes:**
- I grep-verified the call graph per `feedback_verify_call_graph_against_source.md` against the source pre-patch: `_randTraitTicket` is invoked exactly 4 times in `DegenerusGameJackpotModule.sol` (the 4 callsites cited in the CHARGE) and 0 times elsewhere. No inline-duplicated business logic for the ETH-path 25-winner draw shape.
- Zero-day novelty angle I checked: could the carryover-ticket level-crossing behavior (tickets from level N enter level N+1's bucket distribution) produce a `traitBurnTicket[lvl+1]` bucket where the player addresses have semantic meaning different from the daily-ETH path? Verified: `_raritySymbolBatch` writes `player` (the ticket purchaser) regardless of source level. The level-crossing only affects WHICH bucket the entry lands in, not the ENTRY's properties.
- Early-bird-post-purchase commitment-window: `_distributeTicketJackpot` is called from `_runEarlyBirdLootboxJackpot` which runs in the same advanceGame flow that consumed `rngWord` from VRF callback. The VRF word is already committed by the time `_randTraitTicket` runs. No commitment-window asymmetry.
- TST-DPNERF fixture coverage gap is a documentation / regression-fixture concern — not a behavioral-divergence concern. The Phase 296 SWEEP is the attestation site per D-295-CALLSITE-SCOPE-01.

---

## Hypothesis (xii) — MINTCLN owed-in-baseKey collapse vs v41 Phase 281 reference pattern

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- v41 reference shape: `keccak256(abi.encode(baseKey_4_input, entropyWord, groupIdx, ownedSalt))` with `ownedSalt = uint32(owed)` as the 4th positional argument to `_raritySymbolBatch`.
- v42 collapsed shape: `keccak256(abi.encode(baseKey_5_input, entropyWord, groupIdx))` with `owed` packed into `baseKey` bits 0-31.
- Algebraic equivalence: the bit-string fed to keccak in v41 was `[baseKey_4 (256b)] [entropyWord (256b)] [groupIdx (256b)] [ownedSalt (256b)] = 1024 bits`. In v42 the bit-string is `[baseKey_5 (256b)] [entropyWord (256b)] [groupIdx (256b)] = 768 bits`. Different total lengths → keccak outputs differ across versions BY DESIGN; the question is whether the v42 form preserves the v41 INVARIANT (pairwise-distinct keccak inputs across multi-call drains on the same `(rk, player)` pair).
- v42 invariant: two batches at the same `(rk, player)` with distinct `owed` values produce distinct `baseKey` values (low 32 bits differ); identical `entropyWord` and `groupIdx`; identical concatenation length 768 bits BUT distinct content → keccak outputs are distinct under collision resistance.
- The zero-owed-rolled-to-1 branch (Hypothesis (i) edge case): same `baseKey` (low 32 = 0) is used for the batch emit. But within a single `(lvl, queueIdx, player)` triple, the zero-owed-rolled-to-1 branch emits AT MOST ONE batch before advance, so there is no within-triple second batch to collide with.

**Notes:**
- I re-tested the v41 owed-salt invariant verbatim at v42: every adversarial trace v41 attestation classified as SAFE remains SAFE under the v42 packing.
- `_rollRemainder` consumer of `baseKey` via `EntropyLib.hash2(entropy, baseKey, rem)`: at the 4 callsites `:443, :489, :746, :824`, `baseKey` carries the same `(lvl, queueIdx, player, owed)` packing. Across distinct queueIdx, `baseKey` differs → `_rollRemainder` outcomes are pairwise-independent. Within the same queueIdx, the `_rollRemainder` calls happen at distinct positions in `_processOneTicketEntry`: `:444` (zero-owed-rolled-to-1 attempt) vs `:483` (post-take residue roll). These two calls use the SAME `baseKey` and SAME `entropy` but DIFFERENT `rem` values; `EntropyLib.hash2` mixes `rem` in. Outcome: distinct rolls.
- Zero-day novelty angle I checked: could two distinct `(lvl, queueIdx, player, owed)` tuples produce identical keccak inputs by exploiting bit-range edge cases (e.g., `owed == queueIdx`)? `owed` lives at bits 0-31; `queueIdx` lives at bits 192-223. Same numerical value at different bit positions produces different 256-bit `baseKey` → no collision.
- v40 baseline collision class (pre-Phase-281): the `owed > writesBudget/2` multi-call drain class. At v42 close, the multi-call drain within the same queueIdx is bounded by `take ≤ owed` per call, and the SECOND call's `owed' = owed - take` differs from the FIRST call's `owed`, so the SECOND call's `baseKey'` differs in bits 0-31. The v41 owed-salt invariant is preserved verbatim.

---

## Hypothesis (xiii) — HRROLL leader-bonus + rngLocked window interaction

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Commitment-window backward trace per `feedback_rng_commitment_window.md`:
  - `_rollHeroSymbol` reads `dailyHeroWagers[day][q]` where `day = dailyIdx`.
  - Writer of `dailyHeroWagers`: `placeDegeneretteBet` (`degenerette:484-501`).
  - VRF request site (daily): `_requestRng` at `advance:1574-1587` → sets `rngRequestTime = block.timestamp` + `rngLockedFlag = true` via `_finalizeRngRequest`.
  - VRF callback site: `rawFulfillRandomWords` (`advance:1745-1766`) → when `rngLockedFlag = true`, stores word into `rngWordCurrent`.
  - Consumption site: `rngGate` (`advance:1192+`) → `currentWord` is used to drive `payDailyJackpot` → `_rollWinningTraits` → `_applyHeroOverride` → `_rollHeroSymbol`.
- During the rngLocked window (VRF request → callback), `placeDegeneretteBet` continues to be callable (no `rngLockedFlag` check at the bet site). BUT — `dailyIdx` is NOT mutated during this window; `dailyIdx` is only written at `_unlockRng(:1730)` which runs AFTER the jackpot resolution consumes the entropy.
- Therefore, bets placed during the rngLocked window write to `dailyHeroWagers[dailyIdx]` where `dailyIdx == D` (the day being resolved). These late-window bets DO affect the leader computation. BUT the VRF callback word is UNKNOWABLE pre-callback (Chainlink VRF property), so the bettor cannot predict whether their bet shifts the leader to a winning quadrant/symbol.
- Cross-day boundary: a bet placed near `JACKPOT_RESET_TIME` reads `_simulatedDayIndex()` which is `block.timestamp`-derived. If the bet's block timestamp is BEFORE day-rollover, the bet credits day D's pool; AFTER day-rollover, day D+1's pool. No race opens — `_simulatedDayIndex()` is a deterministic function of `block.timestamp` minus the deploy boundary.

**Notes:**
- Zero-day novelty angle I checked: could the rngLocked-window timing be exploited by a bettor who observes the VRF coordinator's request transaction in the mempool? Chainlink VRF requests are submitted by the coordinator in a separate transaction — once submitted, the request is committed. The bettor sees `rngRequestTime != 0` via a view function (if any). But the bettor still cannot predict the VRF word. So observing the request DOES enable the bettor to bet during the window, but provides no information advantage about the outcome.
- I checked whether `_unlockRng` could fail to clear `dailyIdx`-related state in any path. `_unlockRng` at `:1729-1736` is the SOLE writer of `dailyIdx`. Verified single-writer invariant per D-288-FIX-SHAPE-01.
- Implicit invariant: "no two distinct `_rollHeroSymbol` invocations within the same VRF epoch produce different `leaderIdx` outputs." Pass-1 scan reads `dailyHeroWagers[day][q]` four times; if `day` and `dailyHeroWagers[day]` are stable across the two pass-1 + pass-2 phases of a single invocation, the output is deterministic. SLOAD ordering within a single tx is consistent (no re-entry between SLOADs because the function is `view`).

---

## Hypothesis (xiv) — `retryLootboxRng()` behavior + exploit surface

**Disposition:** FINDING_CANDIDATE (LOW)

**Evidence:**
- `retryLootboxRng` at `advance:1132-1155`:
  - Guards: `LR_MID_DAY != 0` (mid-day swap committed), `rngRequestTime != 0` (request outstanding), `block.timestamp ≥ rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT` (6h timeout).
  - LINK balance check (~`:1137-1140`).
  - VRF request fires (`:1142-1151`).
  - State updates: `vrfRequestId = id` + `rngRequestTime = block.timestamp` (at `:1153-1154`).
- Buffer-state preservation: `_swapTicketSlot` was called by the original `requestLootboxRng` at `:1095`; `retryLootboxRng` does NOT re-swap. ✓
- LR_INDEX preservation: original `requestLootboxRng` already advanced LR_INDEX at `:1112-1117`; retry does NOT re-advance. ✓
- Stalled requestId auto-rejection: `rawFulfillRandomWords` at `:1750` `if (requestId != vrfRequestId || rngWordCurrent != 0) return`. After `retryLootboxRng` overwrites `vrfRequestId`, the OLD callback fails the equality check and returns early. ✓
- LINK consumption rate: 6h between retries; LINK cost per retry is the Chainlink subscription's per-request fee. Griefing surface bounded: an attacker who repeatedly triggers retries pays nothing themselves (the LINK is debited from the project's subscription), but the attacker also cannot accelerate the retry rate beyond once-per-6h.
- **Daily-flow interaction (the subtle composition):** scenario — `LR_MID_DAY=1` is committed; mid-day VRF stalls past the daily-RNG-trigger time. The next `advanceGame` call enters the new-day path (because `day != dailyIdx`). The new-day path's `rngGate` at `:1189` reads `currentWord = rngWordCurrent`. Since the mid-day VRF has not yet delivered, `rngWordCurrent == 0`. `rngRequestTime != 0` from the mid-day request. The `rngGate` enters the "Waiting for VRF" branch at `:1238-1246`: if `elapsed >= 12 hours` it calls `_requestRng` (which sets `vrfRequestId` to a NEW id via `_finalizeRngRequest`). The mid-day stalled requestId is now overwritten by the daily flow.
- **`_finalizeRngRequest` isRetry detection:** at `:1615-1617` detects retry via `vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0`. After the original `requestLootboxRng`, all three conditions hold. So when daily flow calls `_finalizeRngRequest`, `isRetry == true` and LR_INDEX is NOT advanced again (good — it was already advanced by mid-day).
- **rngLockedFlag set by daily takeover:** `_finalizeRngRequest` at `:1634` sets `rngLockedFlag = true`. When the daily VRF callback eventually lands at `rawFulfillRandomWords`, it enters the `rngLockedFlag == true` branch at `:1755-1757`, storing the word in `rngWordCurrent` (NOT directly into `lootboxRngWordByIndex[index]`).
- **Orphan-bucket repair via `_finalizeLootboxRng`:** in the next `advanceGame` call, `rngGate` enters the "Have a fresh VRF word ready" branch at `:1192`. At `:1234`, `_finalizeLootboxRng(currentWord)` is called, which writes `lootboxRngWordByIndex[LR_INDEX-1] = currentWord` if not already set. ✓ The orphaned mid-day bucket IS repaired.
- **LR_MID_DAY clearing:** the daily-takeover composition does NOT clear `LR_MID_DAY`. After `_unlockRng`, `LR_MID_DAY == 1` persists. On the next `advanceGame`, the mid-day path at `:204-238` is entered when `day == dailyIdx`. At `:209`, the LR_MID_DAY != 0 check triggers a read of `lootboxRngWordByIndex[LR_INDEX-1]`. Since `_finalizeLootboxRng` already wrote the daily-derived word there, `word != 0` and the path PROCEEDS to ticket-batch processing at `:218-235`. Eventually `ticketsFinished` becomes true, and at `:225` `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)` clears the flag. ✓
- **Mid-day-lootbox entropy provenance after daily takeover:** the lootbox word at the mid-day index is now `_applyDailyRng(day, currentWord)` — the daily-VRF word with `totalFlipReversals` applied. This is the SAME WORD that drives the daily jackpot resolution.

**Description (LOW finding):** When `retryLootboxRng` is called but the daily-RNG flow takes over the in-flight VRF before the retry's callback lands, the lootbox word at the mid-day index is filled with the daily-derived VRF word via `_finalizeLootboxRng` at `:1234`. This means:
1. The lootbox word at the mid-day index becomes IDENTICAL to the daily jackpot's entropy word (post-`_applyDailyRng`).
2. Any consumer of the mid-day lootbox bucket and any consumer of the daily-jackpot path now share entropy via the same raw word, in addition to the existing within-day shared raw word (jackpot-path-select bits, lootbox-Bernoulli bits, etc.).
3. The mid-day lootbox bettors who placed bets BEFORE the buffer-swap-commit got entropy that is the daily VRF (with nudges), not a fresh mid-day VRF. The mid-day VRF callback (when it eventually arrives, stale-rejected by requestId) does NOT influence the bucket.

This is a CORRECTNESS observation rather than an exploit: the protocol handles the orphan-repair case gracefully and the bettors do get a valid entropy word. The novelty is that the entropy DOES correlate with daily-jackpot entropy in this composition, which the existing entropy-register documentation (the BIT ALLOCATION MAP at `advance:1157-1174`) does NOT explicitly call out as a possible composition.

**Severity estimate:** LOW — no value extraction, no DoS, no integrity violation. The bettor receives valid entropy and the bucket resolves correctly. The only concern is the implicit shared-entropy invariant: lootbox consumers and daily-jackpot consumers can land on the SAME raw VRF word in this specific composition, which mildly weakens the conceptual "lootbox RNG is separate from daily-jackpot RNG" intuition for downstream auditors / future-state-change reviewers. No on-chain exploit follows from this correlation under the existing keccak-domain-separation guarantees that other consumers apply.

**Suggested remediation (descriptive only — no contract code):**
1. **Documentation-only option:** Extend the BIT ALLOCATION MAP comment at `advance:1157-1174` to explicitly note that in the `retryLootboxRng → daily-flow-takeover` composition, the mid-day lootbox index inherits the daily VRF word. This makes the implicit shared-entropy invariant explicit for downstream readers and would suffice for the audit-envelope close.
2. **Behavioral option (if the user prefers stronger separation):** clear `LR_MID_DAY` at the start of `_finalizeRngRequest`'s isRetry branch and let the orphan-bucket repair happen explicitly via `_backfillOrphanedLootboxIndices` (which uses `keccak256(currentWord, lootbox_index)` domain-separated derivation). This would re-establish entropy domain separation between the daily jackpot's raw word and the mid-day lootbox bucket's effective word. NOTE: this is a behavior change requiring user approval per `feedback_never_preapprove_contracts.md` — included here as a remediation OPTION, not a recommendation.

**Notes:**
- Re-entrancy via VRF coordinator external call at `:1142`: the state updates at `:1153-1154` happen AFTER the external call, but the VRF coordinator is a trusted Chainlink contract that does not re-enter. The standard CEI deviation here is the same as elsewhere in the codebase and is covered by the prior reentrancy audit.
- I considered the `rngLockedFlag=true` interaction: if `retryLootboxRng` were called while `rngLockedFlag=true` (i.e., daily VRF already in flight), the function does NOT explicitly check `rngLockedFlag`. But `LR_MID_DAY != 0` guard at `:1133` is the gating invariant: `LR_MID_DAY=1` is set ONLY by `requestLootboxRng` at `:1096` which itself reverts if `rngLockedFlag==true` at `:1044`. So `LR_MID_DAY=1 ∧ rngLockedFlag=true` can only arise if daily flow took over an in-flight mid-day request via `_finalizeRngRequest`'s isRetry branch. In that case, calling `retryLootboxRng` would over-write `vrfRequestId` with a new id while `rngLockedFlag=true` — this WOULD orphan the daily-takeover VRF request (callback rejected by requestId match) and force another 12h daily-VRF-stall recovery. This is a real griefing surface IF a player can trigger `retryLootboxRng` after daily takeover, but the `block.timestamp ≥ rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT` guard prevents this within 6h of any daily takeover (since daily takeover refreshes `rngRequestTime`). The griefing surface collapses to "permissionless caller forces a 6h additional delay after daily takeover" — bounded and economically uninteresting given the LINK cost is paid by the project's subscription.
- Stuck-state edge: if daily flow zeroes `rngRequestTime` via `_unlockRng` while `LR_MID_DAY == 1`, then `retryLootboxRng` is locked out (`rngRequestTime == 0` guard). But the mid-day path at `advance:204-238` is the recovery: it processes the remaining tickets and clears LR_MID_DAY at `:225`. So the "stuck state" self-heals on the next mid-day advanceGame.
- I performed grep-verified call-graph attestation: `retryLootboxRng` is invoked only externally; no internal callers. `_finalizeRngRequest` is invoked by `_requestRng`, `_tryRequestRng`, and is the SOLE writer of `rngLockedFlag = true`. Verified no other path sets `rngLockedFlag=true` without `_finalizeRngRequest`.

---

## Beyond-Charge Hypothesis (B1) — `retryLootboxRng` LINK-drain griefing through "stall→retry→stall→retry" cycles

**Disposition:** ACCEPTED_DESIGN

**Evidence:**
- Permissionless `retryLootboxRng` allows ANY caller to re-fire a stalled mid-day VRF after 6h.
- Each call consumes Chainlink LINK from the project's subscription (`vrfSubscriptionId`).
- An attacker who somehow induces repeated VRF stalls could re-fire the request every 6h indefinitely, draining LINK from the subscription.
- BUT: VRF stalls are NOT under attacker control — they are caused by Chainlink coordinator unavailability or LINK exhaustion at the request-side. An attacker cannot induce a stall.
- The retry timeout guard at `:1135` (`block.timestamp < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT`) caps the attack rate at once-per-6h.
- The LINK-balance check at `:1137-1140` (`if (linkBal < MIN_LINK_FOR_LOOTBOX_RNG) revert E()`) prevents the attack from completing when LINK is critically low.

**Notes:**
- The attack reduces to "permissionless caller refills the VRF request slot every 6h when Chainlink is unavailable" — which is a FEATURE, not a bug. This is the entire purpose of the function.
- The "drain" angle: in the worst case (perpetual Chainlink unavailability + attacker spam), LINK depletes at a rate of MIN_LINK_FOR_LOOTBOX_RNG / 6h. The project's subscription refill cadence dominates this rate by orders of magnitude under normal operations.
- This is an ACCEPTED_DESIGN trade-off: permissionless retry > admin-gated retry for liveness reasons, even at the cost of a bounded LINK-spend exposure.

---

## Beyond-Charge Hypothesis (B2) — HRROLL `dailyHeroWagers[day][q]` cross-day leakage via day-rollover timing

**Disposition:** NEGATIVE_RESULT_ONLY

**Evidence:**
- Hypothesis: a bettor places a bet at exactly the day-rollover boundary; the bet credits day D's pool but the jackpot for day D was already resolved earlier in the same block (or vice versa).
- `_simulatedDayIndex()` is a deterministic function of `block.timestamp` minus the deploy boundary; within a single block, all calls to `_simulatedDayIndex()` return the same value.
- `dailyIdx` is the persistent day-of-last-resolution; written at `_unlockRng`. Across blocks, `dailyIdx` lags behind `_simulatedDayIndex()` by at least 0 (when up-to-date) and at most some recovery period.
- Within a single block, the ordering of `placeDegeneretteBet` and `advanceGame` calls is determined by the block-builder. If `advanceGame` runs FIRST (resolves day D, sets `dailyIdx = D`, then `_simulatedDayIndex()` for subsequent calls returns D+1 if past the boundary), then the subsequent `placeDegeneretteBet` writes to `dailyHeroWagers[D+1]`. If `placeDegeneretteBet` runs FIRST (writes to `dailyHeroWagers[D]`), then `advanceGame` runs, resolving day D using the just-updated `dailyHeroWagers[D]`.
- Conclusion: within-block ordering can shift the bet's credit between day D and day D+1, but ONLY when the wall-clock time is past the boundary AND `dailyIdx` is still D AND the bet's block hasn't yet had `advanceGame` called.

**Notes:**
- The bettor cannot predict the VRF word for day D+1 at bet-placement time (VRF for D+1 has not yet been requested). So even if the bet lands in `dailyHeroWagers[D+1]` and influences D+1's leader, the bettor has no information edge.
- The bettor's PREFERENCE for one day vs the other is bounded by their KNOWLEDGE of who else has bet. Public bet state is visible on-chain, so the bettor can choose to bet at the rollover with knowledge of D's leader (already resolved or about to resolve) and influence D+1's leader. This is the normal leader-bonus mechanic, not an exploit.
- I checked whether the block-builder could profitably reorder transactions to favor a specific bettor. The block-builder has fee-extraction incentives but no protocol-specific extraction path here — the bet outcome is determined by future VRF, not by the block-builder's reordering.

---

## Beyond-Charge Hypothesis (B3) — `_resolveZeroOwedRemainder` SSTORE-of-zero gas accounting under EIP-3529

**Disposition:** SAFE_BY_DESIGN (informational)

**Evidence:**
- `_resolveZeroOwedRemainder` at `mint:723-749` may write `ticketsOwedPacked[rk][player] = 0` (`:733, :740`) — these are SSTOREs writing zero to an existing-or-zero slot.
- Under EIP-2200 / EIP-3529, an SSTORE from non-zero to zero refunds gas (up to a per-tx cap). An SSTORE from zero to zero costs ~2100 gas (cold) or ~100 gas (warm) with no refund.
- The function guards: `if (packed != 0) { ticketsOwedPacked[rk][player] = 0; }` at `:732-734`. This prevents the no-op zero-to-zero SSTORE.

**Notes:**
- No exploit; the guard is the standard idiom and prevents gas-griefing via zero-to-zero writes.
- Zero-day novelty angle I checked: could an attacker repeatedly queue-then-zero entries to manipulate gas refunds? The refund cap is per-transaction (EIP-3529 limits refunds to 20% of total gas used in the tx), so any attempted refund-farming hits the cap. No exploit.

---

## Beyond-Charge Hypothesis (B4) — `_rollHeroSymbol` 32-slot underflow in `cumulative > pick` exit

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- `_rollHeroSymbol` pass-2 walks `idx ∈ [0, 32)` with `cumulative += uint64(weights[idx])` and an additional `cumulative += leaderBonus` when `idx == leaderIdx`. The exit condition is `cumulative > pick`.
- `effectiveTotal = total + leaderBonus` and `pick = uint64(keccak % effectiveTotal)`, so `pick ∈ [0, effectiveTotal)`.
- After all 32 iterations, `cumulative == total + leaderBonus == effectiveTotal > pick` strictly. So the loop ALWAYS finds an exit in pass 2 when `total > 0`.
- Edge case: `total == 0` is short-circuited at `:1677-1679` returning `(false, 0, 0)` — pass 2 is never reached.
- What if `total > 0` but all the weight is concentrated in slot 0, and `leaderBonus == 0` (because `maxAmount / 2 == 0` when `maxAmount == 1`)? Then `cumulative[0] = 1 > pick ∈ [0, 1)` — exit at idx 0. ✓
- What if `total > 0` and `maxAmount` overflows into `leaderBonus` computation? `maxAmount` is `uint32` so max `0xFFFFFFFF`. `leaderBonus = uint64(maxAmount) / 2 = 0x7FFFFFFF`. `effectiveTotal = total + leaderBonus` where `total <= 32 * 0xFFFFFFFF = ~32 * 4.3B = ~137B`. `total` is `uint64` so up to `~1.8e19`. No overflow within `uint64` arithmetic.

**Notes:**
- Pass-2 termination is structurally guaranteed by the algebraic invariant `cumulative_after_32_iterations == effectiveTotal > pick`. No infinite-loop or fall-through edge case.
- I checked the implicit-return path: if pass 2 completes without finding an exit (algebraically impossible but a defense-in-depth concern), the function returns `(false, 0, 0)` by Solidity's default-return semantics. This would silently disable the hero-override for the day — a benign failure mode, not an exploit.

---

## Beyond-Charge Hypothesis (B5) — `TraitsGenerated` baseKey leakage of player address bits

**Disposition:** ACCEPTED_DESIGN

**Evidence:**
- The v42 `TraitsGenerated(address indexed player, uint256 baseKey, uint32 take)` event includes `baseKey` as a non-indexed parameter.
- `baseKey` packs `(lvl << 224) | (queueIdx << 192) | (uint256(uint160(player)) << 32) | uint256(owed)`. The `player` bits are bits 32-191.
- The event ALSO emits `player` as an indexed topic. So `baseKey` redundantly carries the player address.

**Notes:**
- This is not a privacy concern: the indexed `player` topic already exposes the player address.
- Could an off-chain consumer mistake the `baseKey` payload for a non-player-address opaque key? Possibly, but the comment at `mint:530-533` documents the `baseKey` semantics clearly.
- The redundant emission is intentional per the MINTCLN design: downstream consumers can decode `baseKey` to recover the EXACT `(lvl, queueIdx, owed)` triple without separate event emissions for each. This is the documented v42 event-signature cleanup goal.

---

## Cross-cutting observations

1. **The mid-day-VRF / daily-VRF interaction is the highest-novelty surface in this audit subject.** Hypothesis (xiv) FINDING_CANDIDATE (LOW) captures the only finding I surface in this pass. The orphan-repair mechanism via `_finalizeLootboxRng` at `advance:1234` is correct but produces a shared-entropy state that the existing BIT ALLOCATION MAP comment does not explicitly enumerate. Documentation-only remediation is sufficient.

2. **All other hypotheses (i)-(xiii) dispose to SAFE-class outcomes.** The audit subject is genuinely clean against the novel-attack-surface lens.

3. **Beyond-charge entries B1-B5** surface nothing exploitable; they are documented for completeness so the integrator pass has a record of the surfaces I examined and cleared.

4. **No future-milestone forward-cite tokens used.** No contract code emitted. All remediation descriptions are descriptive only per `feedback_never_preapprove_contracts.md`.

---

*Phase: 296-cross-surface-adversarial-sweep-sweep — Adversarial Pass — Zero-Day Hunter*
*14 hypothesis surfaces (i)..(xiv) disposed + 5 beyond-charge entries (B1..B5)*
*1 FINDING_CANDIDATE: (xiv) at LOW severity, documentation-only remediation*
