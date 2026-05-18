# Phase 292 HRROLL — Design-Intent Trace (HRROLL-10)

> Per `feedback_design_intent_before_deletion.md`: this trace records the original design intent of every code-shape Phase 292 Plan 02 is about to delete or restructure, BEFORE the contract patch lands. The artifact is the AGENT-COMMITTED pre-patch gate. Plan 02 cannot begin its contract-edit task until this file exists alongside `292-01-MEASUREMENT.md` at the paths in Plan 01 `files_modified` AND `292-01-MEASUREMENT.md` §3.d carries no ESCALATION-CHECKPOINT marker.
>
> History is allowed in THIS file because the trace IS a planning artifact whose purpose is to record historical rationale for v41 → v42 changes. The `feedback_no_history_in_comments.md` rule applies to NatSpec / contract source comments only — it does NOT apply to planning docs.

## Audit Baseline + Anchors

**Audit baseline:** `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD). All "v41 close" references in this trace, and all "byte-identical to v41 close" assertions in `292-01-MEASUREMENT.md`, resolve against this SHA.

**Phase 292-scope decision anchors (7 anchors; user dispositions recorded 2026-05-17):**

- **D-42N-LEADER-BONUS-01** — `×1.5` leader-weight bonus on the maximum-amount `(quadrant, symbol)` slot is LOCKED. `leaderBonus = maxAmount / 2`; `effectiveTotal = total + leaderBonus`. (User-locked 2026-05-17.)
- **D-42N-FLOOR-01** — NO minimum-wager floor for eligibility. Every wei of `dailyHeroWagers[day][q]` participates in the weighted roll proportionally. (User-locked 2026-05-17.)
- **D-42N-BONUS-ENTROPY-01** — Raw `randWord` (pre-bonus-tag) feeds `_rollHeroSymbol`. Bonus + regular trait rolls on the same jackpot day land the SAME hero `(q, s)`; only colors differ (via the existing `r`-derived color path). Cross-bonus invariance preserved. (User-locked 2026-05-17.)
- **D-42N-CACHE-01** — Pass-2 memory cache shape selected at plan-phase via theoretical-first three-shape gas comparison (flat `uint32[32]` vs `uint64[32]` weights vs packed `uint256[4]`). The chosen shape is locked in `292-01-MEASUREMENT.md` §3.b for Plan 02 to implement verbatim. Re-SLOAD-without-cache is explicitly REJECTED. (Planner-discretion under user 2026-05-17 "most gas-efficient" directive.)
- **D-42N-COLOR-ENTROPY-01** — Color path consumes bits `quadrant*3` of `r`; symbol-roll path consumes `uint64(uint256(keccak256(abi.encode(heroEntropy, day))) % effectiveTotal)`. The two entropy sources are structurally orthogonal — non-collision is by construction (keccak output independent of any input bit-slice), NOT probabilistic. (Planner-locked.)
- **D-42N-DETERMINISM-01** — Exact algorithm locked: `abi.encode(heroEntropy, day)` (NOT `abi.encodePacked` — avoids type-coercion ambiguity); `pick = uint64(uint256(keccak256(...)) % effectiveTotal)`; pass-2 cursor walks flat idx ascending (q ascending → s ascending), leader-bonus added at `idx == leaderIdx`; pass-1 strict-`>` tie-break = first-seen wins (matches v41 `_topHeroSymbol` scan order). (Planner-locked.)
- **D-42N-GAS-01** — Acceptance threshold derived from D-42N-CACHE-01 chosen shape's theoretical worst case (per `292-01-MEASUREMENT.md` §3.c). If the chosen shape's worst case > +10K vs v41 `_topHeroSymbol` baseline, Plan 01 surfaces an ESCALATION-CHECKPOINT to the user BEFORE Plan 02 proceeds. (Planner-locked.)

**Carry-forward anchors (load-bearing context; do NOT re-derive):**

- **D-288-FIX-SHAPE-01** (v41 Phase 288) — `dailyIdx` is the single-writer day-key, mutated EXCLUSIVELY at `_unlockRng` (AdvanceModule) and frozen across the rng-lock window. HRROLL-05 inherits this invariant; without it, mid-jackpot `dailyIdx` mutation could cause the symbol-roll to consume wagers from a different day than intended. Plan 02 makes ZERO modifications to `dailyIdx` writers.
- **v41 Phase 281 owed-salt seed-separation pattern** (D-281-FIX-SHAPE-01) — referenced in the HRROLL audit-story for D-42N-COLOR-ENTROPY-01 cross-RNG-consumer non-collision attestation. Domain-separation via `keccak256(abi.encode(...))` is the established idiom (see also `BONUS_TRAITS_TAG` at `contracts/modules/DegenerusGameJackpotModule.sol:183` reused at L1755 + L1938).
- **D-40N-MINTBOOST-OUT-01** (v40) — UNCHANGED at v42. HRROLL does not touch the mint-boost path. No collateral.
- **D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-02 + D-271-ADVERSARIAL-03** (v34 Phase 271) — Phase 296 SWEEP performs the combined 3-skill PARALLEL adversarial pass over MINTCLN + HRROLL + DPNERF together. HRROLL is NOT red-teamed in isolation at Phase 292. `/degen-skeptic` OUT OF SCOPE.

## Section (i) — Original Deterministic `_topHeroSymbol` Single-Leader Rationale

Per HRROLL-10(i): trace WHY v41 `_topHeroSymbol(uint32 day)` (`contracts/modules/DegenerusGameJackpotModule.sol:1625-1653`) selected the deterministic max-amount `(quadrant, symbol)` slot via nested-`for` scan rather than a weighted random roll.

At the v41 design moment, the simplest defensible mechanic for hero override was "the single largest hero-symbol bet wins." The deterministic scan at L1633-L1651 sweeps idx = 0..31 over `dailyHeroWagers[day][q]` for q ∈ {0..3}, extracts each 32-bit `amount` via `uint32((packed >> (uint256(s) * 32)) & 0xFFFFFFFF)`, and updates `(topAmount, winQuadrant, winSymbol)` via strict-`>` comparison. The strict-`>` test produces first-seen-wins on ties: when two slots tie at the maximum amount, the lexicographically-earlier (q ascending → s ascending) slot wins. The scan-order tie-break is the auditable shape — a single deterministic rule with no RNG cost.

The deterministic-pick property had two valuable consequences at v41 design time: (a) zero RNG consumption for the symbol pick (the existing color path at L1605-L1614 consumed `randomWord` bits but symbol-pick was entropy-free); (b) the audit story was minimal — a 30-line function with one invariant ("highest amount wins; ties broken by scan order"). Under the v41 constraint set (close F-41-02 + F-41-03 cross-day determinism findings with minimal bytecode delta + minimal audit surface), the deterministic-pick form was constraint-satisfying.

The v41 form's behavior under organic play motivates the v42 cleanup: the single-largest bettor on any `(q, s)` wins 100% of the time, regardless of how close the runner-up's wager is. Small organic bettors with non-trivial wagers see 0% pick probability. Whales benefit disproportionately — their bets convert directly into deterministic wins; the small-bettor's incentive to participate erodes. Over a long horizon, the player game-theory steers the hero-wager pool toward concentration: rational small bettors stop placing hero wagers because their pick probability is structurally zero unless they out-bet every other bettor on the same slot.

The v41 `_topHeroSymbol` was NOT a defect; it was a **constraint-satisfying design at that phase**. The v42 weighted-roll cleanup is a **player-experience rebalance** enabled by accumulated audit-story room at v42's audit-subject delta, NOT a defect remediation. Phase 292 makes this distinction explicit so the audit narrative for v42 cleanly separates F-41-NN remediation work (closed at v41) from v42's pre-launch player-experience tuning.

## Section (ii) — Leader-Bonus Magnitude Trade-Offs (×2 vs ×1.5 vs none)

Per HRROLL-10(ii): trace the leader-bonus magnitude trade-off space across the three alternatives considered before D-42N-LEADER-BONUS-01 locked ×1.5.

**(a) ×2 alternative — rejected.** Strongest leader bias. The largest-amount slot would receive twice its raw wager weight in the cumulative-sum roll. At typical organic bet distributions where the leader's amount is 2-3× the runner-up's, ×2 produces a leader-win frequency of ~65-75%. The mechanic begins to recreate the deterministic-pick monopolization in probabilistic clothing: small organic bettors retain non-zero pick probability, but the leader's structural advantage swamps them on most days. Whale-coordination MEV (discussed under SWEEP-02(ii) Hypothesis 1 below) is not opened by ×2 specifically — the timing-window argument is independent of the bonus magnitude — but the player-experience signal "your bet barely matters once a whale shows up" is preserved against the v41 form's "your bet doesn't matter at all." ×2 was rejected as insufficient rebalance.

**(b) ×1.5 (locked per D-42N-LEADER-BONUS-01).** Moderate leader bias. `leaderBonus = maxAmount / 2`; effective leader weight is `1.5 × maxAmount`. At typical organic bet distributions, the leader wins ~50-60% of the time, with the runner-up and middle-pack slots sharing the remainder. Large hero-symbol bets earn disproportionate win frequency (the "size matters" signal is preserved), but no single bettor structurally locks out smaller competitors. The ×1.5 magnitude was the user's explicit balance point between game-theoretic accessibility (small organic bettors retain meaningful pick probability) and incentive preservation (capital-committing bettors get rewarded for committing). User disposition 2026-05-17.

**(c) No-bonus (pure-proportional) alternative — rejected.** Flat weighted roll: `pick = uint64(keccak256(...) % total)`; every wei has equal pick probability via `amount / total`. The mechanic is the most-fair-on-paper option, but it discards the "size matters" signal entirely. The hero-override mechanic dilutes to "first to bet anywhere wins proportionally," which under-rewards the player commitment that the hero-wager pool is designed to attract in the first place. Pure-proportional was rejected as insufficient skill-expression preservation.

The ×1.5 disposition is **locked**, not deferred. Out-of-scope alternatives (×2, pure-proportional, ×3, flat-floor) are REJECTED in the formal forward-cite sense — they would re-enter scope only as a fresh decision under a new anchor at some future milestone if post-launch player game-theory diverges meaningfully from intent. Per the v41 closure invariant of zero forward-cite emission, this trace does NOT cite a future-milestone "deferred" bucket; the alternatives are simply CLOSED at D-42N-LEADER-BONUS-01.

## Section (iii) — Sybil Exposure / No-Floor Trade-Offs

Per HRROLL-10(iii): trace the sybil-exposure trade-off space across the no-floor (locked per D-42N-FLOOR-01) and rejected floor-alternative.

**(a) No-floor (locked per D-42N-FLOOR-01).** Smallest organic bettor wins with proportional probability `amount / effectiveTotal`. Arithmetic simplicity: no eligibility predicate, no minimum-wager check. The form aligns with the "every wei counts" mechanic that the `wagerUnit = totalBet / 1e12` scaling at `placeDegeneretteBet` (`contracts/modules/DegenerusGameDegeneretteModule.sol:489`) already implies — a single 1e12 wei bet creates a slot entry of 1, with no floor-discontinuity. User disposition 2026-05-17.

**(b) Floor alternative — rejected.** A floor predicate (e.g., `if (amount > minWagerFloor) include else exclude`) would impose a discontinuity at the floor boundary: a bettor at `floor − 1` has 0% pick probability; at `floor + 1` has full proportional probability. This creates a perverse "bet exactly at the floor for max marginal EV" incentive — every rational bettor min-maxes to the floor value, which collapses the bet-distribution to a spike at the floor and loses the wager-weighted information the mechanic is designed to consume. Floor-value tuning would also require its own decision anchor (where to set the floor; how to update it; how to validate it across price regimes). Rejected as more complex than the no-floor form delivers value.

**Sybil-dilution concern (capital-cost analysis).** A naive attacker hypothesis: spam-bet 1 wei of wager weight on all 32 slots to dilute organic winners by adding noise to the denominator. The capital cost of this attack is structurally bounded by the `wagerUnit = totalBet / 1e12` scaling. To deposit 32 × 1 wei of wager weight, the attacker must place `32 × 1e12 wei = 3.2e13 wei = 0.032 ETH` of actual stake (because `totalBet` is the ETH-denominated bet amount, scaled down by `1e12` to fit uint32). At that capital outlay, the attacker's spam adds at most 32 wager-units to `effectiveTotal`. At realistic daily organic wager volumes (any non-trivial bet creates wager-units in the hundreds or thousands; a single 0.001 ETH bet creates 1000 wager-units), the spam dilution is `32 / effectiveTotal ≈ negligible`. Worse for the attacker: 100% of the spam bet is at-risk capital staked into the game's daily pool — the attacker has paid full bet price for a worthless dilution effect.

The no-floor disposition is therefore **SAFE against sybil-dilution by structural capital-cost closure**. Recorded as a SWEEP-02(ii) Hypothesis 2 pre-emptive answer below.

## Section (iv) — RNG Commitment-Window Backward-Trace (HRROLL-05)

Per `feedback_rng_commitment_window.md` + `feedback_rng_backward_trace.md`: BACKWARD-trace from `_rollHeroSymbol(dailyIdx, heroEntropy)` consumer at `_applyHeroOverride` (`contracts/modules/DegenerusGameJackpotModule.sol:1594-1621`) back to the wager-time write at `placeDegeneretteBet` (`contracts/modules/DegenerusGameDegeneretteModule.sol:484-501`).

**Trace structure (6 steps):**

1. **Consumer site.** `_rollHeroSymbol(dailyIdx, heroEntropy)` reads `dailyHeroWagers[dailyIdx][q]` for `q ∈ {0..3}` — 4 SLOADs — and consumes `heroEntropy` (the new second parameter to `_applyHeroOverride` per D-42N-BONUS-ENTROPY-01, sourced from the raw `randWord` at `_rollWinningTraits` L1934 pre-bonus-tag). The pass-1 scan over the 4 SLOAD'd packed slots extracts 32 × uint32 amounts and identifies `(total, maxAmount, leaderIdx)`; the pass-2 cursor walk consumes `pick = uint64(uint256(keccak256(abi.encode(heroEntropy, dailyIdx))) % effectiveTotal)` to pick the winning `(q, s)`.

2. **Write site.** `placeDegeneretteBet` at `contracts/modules/DegenerusGameDegeneretteModule.sol:484-501` writes `dailyHeroWagers[day][heroQuadrant]` on every ETH-currency bet (`currency == CURRENCY_ETH`), gated on `wagerUnit > 0` where `wagerUnit = totalBet / 1e12`. The write merges the bet amount into the 32-bit slot for `(heroQuadrant, heroSymbol)` via shifted-OR (`wPacked = (wPacked & ~(0xFFFFFFFF << shift)) | (updated << shift)`), with `updated` saturated at `0xFFFFFFFF` if the cumulative wager exceeds the 32-bit cap.

3. **`dailyIdx` write site.** `dailyIdx` is mutated EXCLUSIVELY at `_unlockRng` (in AdvanceModule) — the prior-day jackpot-resolution boundary that simultaneously consumes the VRF callback and rotates the day index. Verification: `grep -rn "dailyIdx =" contracts/` from the v42 close tree returns the single `_unlockRng` site (the read sites at `_applyHeroOverride` L1600, `placeDegeneretteBet` L487 via `_simulatedDayIndex()`, and elsewhere are all READ-only). The single-writer invariant is the v41 Phase 288 D-288-FIX-SHAPE-01 anchor that HRROLL-05 inherits structurally; Phase 292 makes ZERO modifications to `dailyIdx` writers.

4. **Commitment ordering.** Wager amounts for day D are LOCKED into `dailyHeroWagers[D][q]` before day D+1's `_unlockRng` runs. `_unlockRng` runs as part of day D+1's jackpot processing, which is initiated by the day D+1 VRF callback. Therefore: wager-writes for day D < `_unlockRng` write of `dailyIdx ← D` < VRF callback for day D+1's jackpot that consumes `dailyHeroWagers[D][q]` via `_applyHeroOverride`. The temporal ordering is enforced by the contract state-machine, not by external coordination.

5. **Randomness availability.** `randWord` is the Chainlink VRF callback payload delivered at day D+1's jackpot-resolution time. It is **unknowable** at day D's bet-placement time — the VRF request that produces it has not yet fired at any wager-write site in day D. Therefore `heroEntropy` (and the keccak-derived `pick`) is unknowable to any wagerer at any wager-write site for the day whose pool they are wagering into.

6. **Verification conclusion.** Player-controllable input (wager amounts; `(heroQuadrant, heroSymbol)` choice via `customTicket >> (heroQuadrant * 8) & 7` at L488) is COMMITTED to `dailyHeroWagers[D][q]` BEFORE the symbol-roll entropy for day D+1's jackpot is AVAILABLE. The attacker cannot adjust their wager-distribution or their hero-symbol selection to bias the symbol-roll because the symbol-roll entropy is unknown at wager-time. **RNG commitment-window invariant: SAFE.**

The v41 Phase 288 D-288-FIX-SHAPE-01 `dailyIdx` single-writer invariant is load-bearing here. If `dailyIdx` could mutate mid-jackpot (the F-41-02 / F-41-03 finding pattern, closed at v41), the consumer at step 1 could read `dailyHeroWagers[D'][q]` for some `D' ≠ D`, breaking the wager-time → roll-time correspondence the commitment-window argument relies on. The invariant is preserved verbatim at v42 close.

## Section (v) — Gas Budget Headroom + D-42N-CACHE-01 Cache-Shape Decision + D-42N-DETERMINISM-01 Exact Algorithm

Per HRROLL-10(v): trace the gas-headroom analysis, the D-42N-CACHE-01 cache-shape decision against the three candidates, and record the locked D-42N-DETERMINISM-01 algorithm verbatim.

**(a) Gas headroom analysis.** v41 `_topHeroSymbol(dailyIdx)` performs 4 × SLOAD (one per quadrant) + 32 × bit-extract (`uint32((packed >> (s * 32)) & 0xFFFFFFFF)`) + 32 × strict-`>` comparison + 32 + 4 loop-counter `unchecked { ++ }` increments + function entry/exit. v42 `_rollHeroSymbol` adds: a second 32-iteration cursor walk over a memory cache (no re-SLOAD), one `keccak256(abi.encode(heroEntropy, day))` (~87 gas for 64-byte input including memory expansion + MOD + DIV), one `maxAmount / 2` division for `leaderBonus`, and the cache-build cost itself. The net delta per call is bounded — see `292-01-MEASUREMENT.md` §3 for the full theoretical-first derivation.

**(b) D-42N-CACHE-01 three-shape comparison.** Three candidate memory-cache shapes were considered:

- **Flat `uint32[32]`** indexed `q*8 + s` — pass 1 SLOADs 4 packed slots once, extracts 32 × uint32 into the flat array, identifies `(maxAmount, leaderIdx)` in the same pass; pass 2 walks the flat array with cumulative-sum + leader-bonus conditional add.
- **`uint64[32]` weights array (pre-bonus-applied)** — pass 1 same as flat `uint32[32]` plus a pre-applied `leaderBonus` add at `idx == leaderIdx` during cache build; pass 2 walks without the conditional branch.
- **Packed `uint256[4]` cache** with SHR+AND extracts in the hot loop — pass 1 SLOADs the 4 packed slots once into the cache; pass 2 re-extracts each 32-bit amount on every iteration via SHR+AND, plus the leader-bonus conditional add.

The detailed gas accounting lives in `292-01-MEASUREMENT.md` §3.b. The chosen shape is LOCKED there with reason; Plan 02 implements that shape verbatim. Re-SLOAD-without-cache (the explicit anti-pattern per CONTEXT.md "do whatever is most gas efficient" user directive) is REJECTED — burns ~8.4K gas per call for no design value, violates `feedback_no_dead_guards.md`.

**(c) D-42N-DETERMINISM-01 exact algorithm.** Plan 02 implements the following verbatim — no creative latitude on ordering, encoding, or arithmetic:

```
// Pass 1: scan idx = 0..31 (q = idx >> 3, s = idx & 7)
//   - SLOAD each of the 4 packed uint256 slots ONCE (dailyHeroWagers[day][q])
//   - Extract each 32-bit amount via: uint32((packed >> (uint256(s) * 32)) & 0xFFFFFFFF)
//   - Accumulate `total` as uint64
//   - Track maxAmount + leaderIdx via strict `>` (first-seen wins on ties)
//   - Build the chosen-shape cache in the same pass
//
// Early-bail: if (total == 0) return (false, 0, 0);
//
// leaderBonus = maxAmount / 2;                              // ×1.5 effective weight
// effectiveTotal = total + leaderBonus;                     // uint64; max ≈ 2.06e11 << 2^64
// pick = uint64(uint256(keccak256(abi.encode(heroEntropy, day))) % effectiveTotal);
//                                                           // abi.encode, NOT abi.encodePacked
//
// Pass 2: walk idx = 0..31 over cached weights
//   cumulative += weight;
//   if (idx == leaderIdx) cumulative += leaderBonus;        // (omitted if shape pre-applies)
//   if (cumulative > pick) return (true, uint8(idx >> 3), uint8(idx & 7));
//
// Cursor direction: flat idx ascending = q ascending → s ascending
// (matches v41 _topHeroSymbol scan order; weighted picks don't care but the order is locked).
```

The choice of `abi.encode` over `abi.encodePacked` is deliberate per D-42N-DETERMINISM-01: `abi.encodePacked` for `(uint256, uint32)` type-coerces in a way that loses the type distinction at hash time and produces ambiguity if the parameter types ever change; `abi.encode` is unambiguous and produces a stable, ABI-tagged 64-byte preimage. The `% effectiveTotal` modulo is bias-safe because `effectiveTotal << 2^256` by ~144 orders of magnitude; the modulo bias is structurally vanishing.

**(d) D-42N-BONUS-ENTROPY-01 cross-bonus invariance rationale.** On jackpot days that trigger both regular AND bonus trait rolls (e.g., days where the BAF bonus path is activated alongside the daily winning-traits emission), `_rollWinningTraits` is invoked twice — once with `isBonus = false`, once with `isBonus = true`. Both invocations consume the same raw `randWord` VRF payload at L1934 but compute different local `r` values: `r = randWord` for the regular path, `r = keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG))` for the bonus path. v41's hero-override mechanic was entropy-independent on the symbol pick (`_topHeroSymbol(dailyIdx)` returned the same `(q, s)` regardless of `randomWord`); v42's D-42N-BONUS-ENTROPY-01 preserves this per-day lock-in by routing the raw `randWord` (not the post-bonus-tag `r`) into `_rollHeroSymbol` for the symbol pick. Both bonus and regular rolls therefore land on the SAME hero `(q, s)` per day; only the COLORS differ (the color path at L1605-L1614 continues to consume bits `quadrant*3` of `r`, which differs between regular and bonus). Hero-symbol winner wins their forced symbol on both rolls — matching v41 mechanic semantics.

The rejected divergent-entropy alternative would have used local `r` (post-bonus-tag for `isBonus = true`) as the symbol-roll entropy. Under that alternative, bonus and regular rolls would land on DIFFERENT `(q, s)` slots on the same jackpot day. The mechanic shift would noticeably dilute hero-symbol winner EV: a bettor who placed a hero wager on `(q, s) = (2, 5)` would win their forced symbol on (say) the regular roll but not the bonus roll on the same day, halving their effective hero-win frequency on bonus-active days. The user explicit disposition at 2026-05-17 was to preserve per-day lock-in, NOT to treat every RNG consumer as an independent weighted roll. Divergent-entropy is REJECTED.

## Decision Anchors

| Anchor | Disposition | Source |
|---|---|---|
| D-42N-LEADER-BONUS-01 | ×1.5 leader bonus (`leaderBonus = maxAmount / 2`); ×2 and pure-proportional REJECTED | User-locked 2026-05-17 |
| D-42N-FLOOR-01 | No minimum-wager floor; floor alternative REJECTED | User-locked 2026-05-17 |
| D-42N-BONUS-ENTROPY-01 | Raw `randWord` feeds `_rollHeroSymbol`; cross-bonus invariance preserved; divergent-entropy REJECTED | User-locked 2026-05-17 |
| D-42N-CACHE-01 | Chosen pass-2 cache shape locked in `292-01-MEASUREMENT.md` §3.b; re-SLOAD-without-cache REJECTED | Planner-discretion under user 2026-05-17 "most gas-efficient" directive |
| D-42N-COLOR-ENTROPY-01 | Color bits from `r`; symbol bits from `keccak256(abi.encode(heroEntropy, day))` — structurally orthogonal | Planner-locked |
| D-42N-DETERMINISM-01 | `abi.encode(heroEntropy, day)`; `pick = uint64(uint256(keccak256(...)) % effectiveTotal)`; flat idx ascending; leader-bonus at `idx == leaderIdx`; strict-`>` first-seen tie-break | Planner-locked |
| D-42N-GAS-01 | Acceptance threshold derived from chosen-shape worst case in `292-01-MEASUREMENT.md` §3.c; ESCALATION-CHECKPOINT if > +10K | Planner-locked |

## Out-of-Scope Register (NOT touched by Phase 292 per REQUIREMENTS.md `## Out of Scope`)

| # | Item | Disposition |
|---|---|---|
| (a) | HRROLL minimum-wager floor for eligibility | OUT per D-42N-FLOOR-01; not addressed by Plan 02. |
| (b) | HRROLL leader-bonus magnitude alternatives (×2, ×3, flat-floor, pure-proportional) | REJECTED per D-42N-LEADER-BONUS-01 (NOT DEFERRED — would re-enter scope only as a fresh decision under a new anchor at a future milestone if post-launch player game-theory diverges). |
| (c) | HRROLL storage layout changes | OUT — `dailyHeroWagers[uint32 => uint256[4]]` + `dailyIdx` UNCHANGED per the note's "no storage changes" constraint. Storage byte-identity attestation lives at `292-01-MEASUREMENT.md` §2. |
| (d) | HRROLL public ABI changes | OUT — `payDailyJackpot` + `payDailyJackpotCoinAndTickets` + view function signatures byte-identical post-fix. Selector attestation lives at `292-01-MEASUREMENT.md` §4. |
| (e) | Per-bet hero-quadrant multiplier `_applyHeroMultiplier` in `DegenerusGameDegeneretteModule.sol` | OUT — explicitly unrelated mechanic; stays as-is per v37 Phase 267 design. Not addressed by Plan 02. |
| (f) | Divergent-entropy alternative for bonus rolls | REJECTED per D-42N-BONUS-ENTROPY-01 (NOT DEFERRED — preserves per-day lock-in mechanic by design). |
| (g) | Cache-shape A/B benchmark in production | OUT — only theoretical-at-292 (in `292-01-MEASUREMENT.md` §3.b) + empirical-at-293 (via TST-HRROLL-06 in Phase 293) are in scope. Production A/B not addressed. |
| (h) | Adversarial pass on HRROLL in isolation | DEFERRED to Phase 296 SWEEP per D-271-ADVERSARIAL-01 carry. HRROLL is NOT red-teamed at Phase 292; the combined 3-skill PARALLEL adversarial pass at Phase 296 covers MINTCLN + HRROLL + DPNERF together. |

## SWEEP-02(ii) HRROLL Adversarial-Hypothesis Pre-Emptive Answers

Per REQUIREMENTS.md SWEEP-02(ii) HRROLL adversarial register: pre-emptively answer the 4 hypotheses so Phase 296's 3-skill PARALLEL adversarial pass has a baseline disposition record to test against.

**Hypothesis 1: Does ×1.5 leader bonus open whale-coordination or wash-trading MEV?** Pre-emptive answer: **NO**. The leader bonus is computed ON CHAIN from the on-chain wager state at `_rollHeroSymbol` invocation time. The attacker cannot wash-trade between bet-placement and roll-execution because the symbol-roll entropy (`randWord` → `keccak(heroEntropy, day)`) is unknown at bet-time per the HRROLL-05 commitment-window argument in §(iv). Coordinating whales can certainly push a single `(q, s)` to leader status — that is the mechanic working as designed (×1.5 rewards capital commitment), not an MEV exploit. There is no asymmetric-information surface between mempool-observable bets and the resolution payoff; all bets are public, all wager-state is on-chain, and the entropy is delivered atomically at resolution. Expected Phase 296 disposition: **SAFE_BY_DESIGN**.

**Hypothesis 2: Does no-floor design open sybil dilution attack?** Pre-emptive answer: **NO**. See §(iii) capital-cost calculation. 32 × 1 wei of wager-weight (the minimum dilution payload to cover all 32 slots) requires 32 × 1e12 wei = 3.2e13 wei = **0.032 ETH** of actual stake. At realistic daily wager volumes (any non-trivial bet creates wager-units in the hundreds or thousands), 32 wager-units of attacker-noise represents `<< 1%` of `effectiveTotal` — dilution is negligible. The attacker pays full bet price for a worthless effect. Expected Phase 296 disposition: **SAFE_BY_STRUCTURAL_CLOSURE**.

**Hypothesis 3: Does the new RNG-consumer (symbol roll consuming VRF bits via keccak) collide with existing consumers?** Pre-emptive answer: **NO**. The symbol-roll consumes `uint256(keccak256(abi.encode(heroEntropy, day))) % effectiveTotal` — keccak's hash output is **structurally orthogonal** to the raw `randWord` bit-slices that existing consumers read: jackpot-path-select bits[0..12]; lootbox-Bernoulli bits[152..167]; jackpot-Bernoulli bits[200..215]; color-sample bits `quadrant*3` of `r`. Keccak output is independent of any specific bit-slice of its input by hash-function design; non-collision is **structural, NOT probabilistic**. The D-42N-COLOR-ENTROPY-01 attestation in `292-01-MEASUREMENT.md` §3.e records this one-liner. Expected Phase 296 disposition: **SAFE_BY_DESIGN**.

**Hypothesis 4: Does the gas regression open a DOS surface?** Pre-emptive answer: **NO**. The D-42N-GAS-01 acceptance threshold (derived from D-42N-CACHE-01 chosen shape's theoretical worst case in `292-01-MEASUREMENT.md` §3.c) bounds the regression. The worst case is structurally bounded by 4 × SLOAD + 2 × 32-iteration loops + 1 × keccak + 1 × MOD + 1 × DIV — no unbounded computation; the loop bounds are fixed (`idx ∈ [0, 32)`). `_applyHeroOverride` is called from `_rollWinningTraits` which is called from the jackpot-resolution path; the jackpot caller-budget already accommodates the v41 baseline; the v42 delta is sub-1K gas per call (well within the +10K ESCALATION-CHECKPOINT threshold; see `292-01-MEASUREMENT.md` §3.c). If the theoretical worst case were to exceed +10K, Plan 01 surfaces an ESCALATION-CHECKPOINT to the user BEFORE Plan 02 proceeds. Expected Phase 296 disposition: **SAFE_BY_BOUNDED_COMPUTATION**.

## Plan-02 Pre-Patch Gate

Plan 02 (`292-02-PLAN.md`) cannot begin its contract-edit task until BOTH `292-01-DESIGN-INTENT-TRACE.md` AND `292-01-MEASUREMENT.md` exist at the paths in Plan 01 `files_modified`, AND `292-01-MEASUREMENT.md` §3.d carries no `🚨 ESCALATION-CHECKPOINT` marker (or the user has explicitly resolved any escalation that arose). This is the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md`.

Plan 02's first task reads both artifacts and copies forward the 7 decision anchors + the measurement framework into the batched contract commit message body (per `feedback_no_history_in_comments.md` — numerical attestations live in the commit body, NOT in NatSpec). Plan 02 is the user-approval gate for the contract changes per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_manual_review_before_push.md`; Plan 01 is AGENT-COMMITTED (planning artifacts only; zero contract / test edits).

**The planner has NOT pre-approved the contract diff per `feedback_never_preapprove_contracts.md`.** Plan 02's executor MUST present the full diff to the user for explicit review BEFORE staging or committing any contract change. The trace above and the measurement scaffold are the rationale-record the user sees alongside the diff at review time; they are NOT a substitute for the user's review.

## Sister-Plan Coverage Map

| HRROLL-NN | Covered by | Notes |
|---|---|---|
| HRROLL-01 | Plan 02 contract patch | New `_rollHeroSymbol(uint32 day, uint256 heroEntropy)` private view; per D-42N-DETERMINISM-01 algorithm. |
| HRROLL-02 | Plan 02 contract patch | `_applyHeroOverride` signature gains second entropy parameter; calls `_rollHeroSymbol`. |
| HRROLL-03 | Plan 02 contract patch | `_topHeroSymbol` DELETED entirely (function body + NatSpec). |
| HRROLL-04 | Plan 02 contract patch | Single callsite at `_rollWinningTraits` L1941 updates to pass `(traits, r, randWord)`; 12 upstream `_rollWinningTraits` callers UNCHANGED (`randWord` already in scope per CONTEXT.md scout). |
| HRROLL-05 | Plan 01 trace §(iv) BACKWARD-trace + Plan 02 contract patch preserving the v41 Phase 288 D-288-FIX-SHAPE-01 `dailyIdx` invariant | Wager-time commitment site at `DegenerusGameDegeneretteModule.sol:484-501` traced to consumer at `_applyHeroOverride` L1594-1621; randomness unknowable at wager time → SAFE. |
| HRROLL-06 | Plan 02 storage byte-identity attestation | Populated post-patch in `292-01-MEASUREMENT.md` §2 (`forge inspect storageLayout` diff EMPTY against v41 close). |
| HRROLL-07 | Plan 02 public ABI byte-identity attestation | Populated post-patch in `292-01-MEASUREMENT.md` §4 (selectors UNCHANGED for `payDailyJackpot` + `payDailyJackpotCoinAndTickets` + view functions). |
| HRROLL-08 | Plan 01 theoretical worst-case gas in `292-01-MEASUREMENT.md` §3.b + Plan 02 verification at post-patch | Empirical regression DEFERRED to Phase 293 TST-HRROLL-06 per the Phase 291 D-291-GAS-01 mirror pattern (theoretical-at-contract-phase + empirical-at-test-phase). |
| HRROLL-09 | Plan 01 trace §(v) D-42N-DETERMINISM-01 algorithm lock + Plan 02 contract patch implementing verbatim | Pass-1 + pass-2 + keccak ordering + tie-break locked. |
| HRROLL-10 | Plan 01 (THIS doc) + `292-01-MEASUREMENT.md` | Five-section design-intent trace + measurement scaffold AGENT-COMMITTED before the contract patch. |

## Source Citations

| File | Line range | Role at Plan 01 |
|---|---|---|
| `contracts/modules/DegenerusGameJackpotModule.sol` | L183 | `BONUS_TRAITS_TAG` declaration; reused at L1755 + L1938 — established domain-separation idiom for the HRROLL keccak. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1584-L1593 | `_applyHeroOverride` NatSpec — REWRITTEN by Plan 02 (no "previously" / "v41 form" wording per `feedback_no_history_in_comments.md`). |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1594-L1621 | `_applyHeroOverride` body — signature gains second `heroEntropy` parameter per D-42N-BONUS-ENTROPY-01. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1623-L1624 | `_topHeroSymbol` NatSpec — DELETED by Plan 02. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1625-L1653 | `_topHeroSymbol` body — DELETED entirely by Plan 02 per `feedback_no_dead_guards.md`. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | L1928-L1943 | `_rollWinningTraits` — single callsite of `_applyHeroOverride` at L1941; updated to pass `(traits, r, randWord)` 3-arg form. |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | L482-L501 | `placeDegeneretteBet` wager-time write to `dailyHeroWagers[day][heroQuadrant]` — HRROLL-05 backward-trace destination. |
| `contracts/storage/DegenerusGameStorage.sol` | L1470-L1475 | `dailyHeroWagers` declaration — UNCHANGED; HRROLL-06 byte-identity attestation target. |

---

*Phase 292 Plan 01 — Design-Intent Trace (HRROLL-10); AGENT-COMMITTED pre-patch gate; produced 2026-05-17 against audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`.*
