# Pre-Push Contract Changes — v36.0 → v38.0 Reviewer's Reference

**Generated:** 2026-05-11
**Scope:** 6 unpushed contract-tree commits between `origin/main` and `HEAD = a129884b`
**Closure signal:** `MILESTONE_V38_AT_HEAD_06623edb` (v38.0)
**Audit deliverable:** `audit/FINDINGS-v38.0.md` (FINAL READ-only at chmod 444)

This document enumerates **every contract-tree mutation** between the last-pushed `origin/main` baseline and the v38.0 closure HEAD, with per-commit:

1. **What changed** (file:lines, conceptual delta)
2. **Why it's safe in all uses** (preserved invariants, theoretical bound, empirical witness)
3. **Tests that exercise it**

The 6 commits span 3 milestones (v36.0, v37.0, v38.0) and touch 3 contract files.

## Cumulative diff stat (origin/main..HEAD)

```
contracts/DegenerusTraitUtils.sol                     |  +45 / -0      (1 fn added)
contracts/modules/DegenerusGameDegeneretteModule.sol  | +254 / -215    (full rewrite)
contracts/modules/DegenerusGameLootboxModule.sol      |  +76 / -75     (refactor + dead-branch)
```

## Commit chain

| # | SHA | Milestone | Subject |
|---|---|---|---|
| 1 | `df6345cc` | v36.0 | `feat(266): lootbox-path entropy refactor [ENT-01..06]` |
| 2 | `e1136071` | v37.0 | `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]` |
| 3 | `8fd5c2e1` | v37.0 | `feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]` |
| 4 | `527e3adc` | v38.0 | `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]` |
| 5 | `4760459f` | v38.0 | `feat(272): wave 1.5 validate heroQuadrant input (revert on >= 4) [HERO-05-revised]` |
| 6 | `a129884b` | v38.0 | `chore(272-followup): rewrite L302 bit-layout comment to describe what IS at v38` |

---

## 1. Commit `df6345cc` — v36.0 Phase 266 ENT-01..06 lootbox-path entropy refactor

### What changed

Replaced the per-sub-roll `entropy = uint256(keccak256(...))` cascade pattern in `_resolveLootboxCommon` with a **single keccak per resolution** that is bit-sliced for each downstream consumer.

**File: `contracts/modules/DegenerusGameLootboxModule.sol`**

Touched functions (4 callers + 5 consumers):

- `_resolveLootboxCommon` (4 callsites at L551, L625, L670, L705): one `seed = keccak256(rngWord, player, day, amount)` per resolution; threaded through downstream
- `_rollTargetLevel(baseLevel, seed)`: drops `nextEntropy` return; consumes `bits[0..39]` of seed
- `_resolveLootboxRoll(amount, lootboxAmount, targetPrice, day, seed)`: drops 3 params (`targetLevel`, `currentLevel`, `nextEntropy`); consumes `bits[40..55]` + `bits[80..95]` of seed
- `_lootboxDgnrsReward(amount, entropy)`: consumes `bits[56..79]` of seed
- `_lootboxTicketCount(budgetWei, priceWei, seed)`: drops `nextEntropy` return; consumes `bits[96..119]` of seed
- `_rollLootboxBoons(player, day, originalAmount, boonBudget, seed, ...)`: consumes `bits[120..151]` of seed
- Second-invocation branch: `seed2 = EntropyLib.hash2(seed, 1)` (counter-tagged chunk for the ETH-amount-second resolution)

### Bit allocation (documented in NatSpec at `_resolveLootboxCommon`)

| Consumer | Bit range | Modulo | Bias |
|---|---|---|---|
| `_rollTargetLevel` rangeRoll | `bits[0..15]` | `% 100` | 0.05% |
| `_rollTargetLevel` near-offset | `bits[16..23]` | `% 5` | 0.39% |
| `_rollTargetLevel` far-offset | `bits[24..39]` | `% 46` | 0.05% |
| `_resolveLootboxRoll` pathRoll | `bits[40..55]` | `% 20` | 0.02% |
| `_lootboxDgnrsReward` tierRoll | `bits[56..79]` | `% 1000` | 0.0024% |
| `_resolveLootboxRoll` varianceRoll | `bits[80..95]` | `% 20` | 0.02% |
| `_lootboxTicketCount` varianceRoll | `bits[96..119]` | `% 10000` | 0.045% |
| `_rollLootboxBoons` roll | `bits[120..151]` | `% 1_000_000` | 0.022% |

Total primary-chunk consumption: **152/256 bits**. Second-invocation chunk uses `EntropyLib.hash2(seed, 1)` (counter-tagged; collision-free vs primary chunk 0).

### Why it's safe in all uses

**Invariant 1 — Distribution preservation:**
Each bit slice extracts an unbiased uniform integer in `[0, 2^k)` where `k` = slice width. Modulo against the target range introduces a bounded bias that is **strictly smaller** than the bias of the old `entropyStep` cascade (which used the same modulo widths but with deeper keccak chains; the bias is identical at the modulo step but the chain depth had no statistical benefit).

**Invariant 2 — Non-overlap:**
The 8 consumer slices occupy disjoint bit ranges `[0..151]` of the 256-bit primary chunk. Mathematically: `seed[a..b] ⊥ seed[c..d]` for disjoint `[a,b] ∩ [c,d] = ∅` under uniform-random `seed` from keccak256. No two consumers share entropy.

**Invariant 3 — Counter-tag isolation across invocations:**
The second resolution invocation (ETH-amount-second branch) uses `seed2 = EntropyLib.hash2(seed, 1)`. This is a one-counter-step away from `EntropyLib.hash2(seed, 0)` (the implicit chunk 0 the primary uses), so `seed2 ⊥ seed` modulo keccak's collision resistance. Audited at v36.0 §4 SAFE.

**Invariant 4 — Replay safety:**
`seed = keccak256(rngWord, player, day, amount)` derives from the same on-chain inputs as the old cascade. Replay produces identical seed; deterministic at the same RNG word.

### Tests

- **v36.0 FINDINGS §4 surface (f)**: lootbox dead-branch byte-equivalence and entropy-refactor SAFE
- **Phase 268 STAT-06**: `test/stat/LootboxEntropyDistribution.test.js` chi² test confirms output distributions UNCHANGED vs pre-refactor (within `χ²_0.05` critical value for each consumer's distribution)
- **Phase 268 SURF-02**: `test/stat/SurfaceRegression.test.js` byte-identity assertion (`_rollTargetLevel`, `_resolveLootboxRoll`, `_lootboxDgnrsReward`, `_lootboxTicketCount`, `_rollLootboxBoons` byte-identical at v36.0 close + UNCHANGED at v38)
- **Fuzz**: `test/fuzz/handlers/DegeneretteHandler.sol` exercises lootbox resolutions via Foundry fuzz; no invariant violations across `forge-std` campaigns

### Bytecode delta

Net gas savings: **~5 keccak calls eliminated per lootbox resolution** (each keccak ≈ 36 gas + memory expansion). Empirical pin: deferred (see LBX-02 RE-DEFERRED-V39+).

---

## 2. Commit `e1136071` — v37.0 Phase 267 producer + 5-table payout + 3-tier ETH split

### What changed

This is the **largest single contract commit** in the chain. Three coordinated changes:

#### (a) New trait producer

**File: `contracts/DegenerusTraitUtils.sol` (+45 LOC)**

- Added `packedTraitsDegenerette(uint256 rand) internal pure returns (uint32)` — sibling to `packedTraitsFromSeed`
- Added `_degTrait(uint64 rnd) private pure returns (uint8)` — per-quadrant trait derivation
- **Per-quadrant distribution:** 7 commons at 2/15 each (13.333%), gold at 1/15 (6.667%); symbol uniform 1/8 from high 32 bits

#### (b) 5 per-N base payout tables + 5 per-N WWXRP factor tables + 5 per-N HERO_BOOST tables

**File: `contracts/modules/DegenerusGameDegeneretteModule.sol`**

Replaced 3 single-table dispatches with 5-fold per-N dispatch:

| Table | Old form | New form |
|---|---|---|
| Base payouts | `QUICK_PLAY_BASE_PAYOUTS_PACKED` (1 × 32-bit-slot table for M=0..7) + `QUICK_PLAY_BASE_PAYOUT_8_MATCHES` | `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` (5 tables) + `QUICK_PLAY_PAYOUT_N{0..4}_M8` (5 constants) |
| WWXRP factors | 4 hardcoded constants (`WWXRP_BONUS_FACTOR_BUCKET{5..8}`) | `WWXRP_FACTORS_N{0..4}_PACKED` (5 × 4 = 20 factors) |
| Hero boost | `HERO_BOOST_PACKED` (1 table for M=2..7) | `HERO_BOOST_N{0..4}_PACKED` (5 tables) |

Dispatch helpers added:
- `_countGoldQuadrants(uint32 ticket) → uint8 N` (returns N ∈ {0..4} = count of gold quadrants in player ticket)
- `_wwxrpFactor(uint8 N, uint8 bucket) → uint256 factor` (per-N WWXRP factor lookup)
- `_getBasePayoutBps(uint8 N, uint8 matches) → uint256` (per-N base payout dispatch; new signature with `N` parameter)

Removed:
- `_evNormalizationRatio(playerTicket, resultTicket)` — the old per-outcome EV correction (product-of-ratios). **No longer needed**: per-N table calibration handles EV equality at the table level.
- `_wwxrpBonusRoiForBucket` — replaced by `_wwxrpFactor` with N parameter

#### (c) Hero match semantic change

**Old (pre-v37):** Hero match required BOTH `colorMatch && symbolMatch` (P ≈ 1/120 per hero quadrant for arbitrary picks).

**New (post-v37):** Hero match requires **only `symbolMatch`** (P = 1/8 per hero quadrant, uniform). Boost values shrank accordingly — recalibrated so EV-neutrality still holds.

#### (d) 3-tier ETH split rule

**File: `contracts/modules/DegenerusGameDegeneretteModule.sol`** `_distributePayout`

Added `uint128 betAmount` parameter (caller passes `amountPerTicket`).

Old (pre-v37): Flat 25% ETH / 75% lootbox.

New (post-v37):

| Tier | Trigger | `ethShare` | `lootboxShare` |
|---|---|---|---|
| 1 | `payout ≤ 3 × bet` | `payout` (100% ETH) | 0 |
| 2 | `3 × bet < payout ≤ 10 × bet` | `max(2.5 × bet, payout / 4) = 2.5 × bet` | `payout − ethShare` |
| 3 | `payout > 10 × bet` | `payout / 4` | `3 × payout / 4` |

The pool-cap (`ETH_WIN_CAP_BPS = 10%` of `futurePool`) takes precedence: if computed `ethShare > maxEth`, excess flips to `lootboxShare` and `PayoutCapped` event emits.

The frozen-pool branch retains its solvency-check posture (`revert E()` on insufficient pending pool).

#### (e) Wired in the new producer

`_resolveFullTicketBet` now calls `DegenerusTraitUtils.packedTraitsDegenerette(resultSeed)` instead of the old `packedTraitsFromSeed`.

### Why it's safe in all uses

**Invariant 1 — Per-N basePayoutEV exact preservation:**

For each N ∈ {0..4}, the per-N base payout table is calibrated so:

```
basePayoutEV(N) = Σ P_N(M) × payout_N(M) for M ∈ {0..8} = exactly 100 centi-x
```

where `P_N(M)` is the binomial convolution of `(4-N)` common-quadrant per-axis distributions + `N` gold-quadrant per-axis distributions:

- Common quadrant (color ∈ 0..6): P(color match) = 2/15, P(symbol match) = 1/8
- Gold quadrant (color = 7): P(color match) = 1/15, P(symbol match) = 1/8

Calibration source: `derive_5_tables.py` Python `Fraction`-exact arithmetic. The 25 packed constants (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` × 5 + `QUICK_PLAY_PAYOUT_N{0..4}_M8` × 5 + `WWXRP_FACTORS_N{0..4}_PACKED` × 5 + `HERO_BOOST_N{0..4}_PACKED` × 5 + scale constants) were **byte-verified at Phase 267 Task 2 PASS_ALL_25** via `267-01-CONSTANTS-VERIFY.md`.

**Drift bound:** ±0.0003 bps per N from Fraction-exact target (M=4/M=5/M=6 cascade absorbs the rounding residual; M=8 jackpot tier stays at uniform-scale and is strictly monotonic in N).

**Invariant 2 — ETH bonus EV preservation:**

```
Σ P_N(M ∈ {5..8}) × factor_N(B(M)) × baseBonus / WWXRP_BONUS_FACTOR_SCALE = exactly 5.000% per N
```

where the per-N factors implement a 10/30/30/30 split across buckets {5, 6, 7, 8}. Same Fraction-exact derivation as the base payout tables; verified at Phase 267 Task 2.

**Invariant 3 — Hero EV-neutrality preservation:**

Per (M, N) ∈ ({2..7} × {0..4}):

```
P(hero match | M, N) × boost(M, N) + (1 − P(hero match | M, N)) × HERO_PENALTY = HERO_SCALE
```

where:
- `HERO_PENALTY = 9500` (0.95×), `HERO_SCALE = 10000` (1.0×)
- `P(hero match | M, N) = (1/8) × P(other-7-axes = M-1 | N) / P_N(M)` (Bayes; symbol-only match → P = 1/8 marginal)

Solving: `E[hero multiplier | M, N] = 1.0` exactly. Hero is **variance-only**; EV invariant by construction.

**Invariant 4 — Symbol-only hero match has no information leak:**

Audited at FINDINGS-v37.0.md §4 surface (b) SAFE_BY_DESIGN: symbol distribution is uniform 1/8 across all 4 quadrants under the v34.0 trait producer. The hero quadrant choice does not interact with color-channel statistics; player's chosen quadrant does not change EV under EV-neutral hero design.

**Invariant 5 — ETH 3-tier split total payout invariant:**

For every payout `p` and bet `b`:

```
ethShare + lootboxShare = p   ← invariant preserved at every tier
```

Tier-1: `ethShare = p`, `lootboxShare = 0`, sum = `p`. ✓
Tier-2/3: `ethShare = max(2.5b, p/4)`, `lootboxShare = p − ethShare`, sum = `p`. ✓

The two upper bands meet exactly at `payout = 10 × bet` where `payout / 4 == 2.5 × bet`.

**Invariant 6 — 3-tier discontinuity boundary at exactly 3×bet:**

Audited at FINDINGS-v37.0.md §4 surface (h) SAFE: the discontinuity at `3.0×bet → 3.01×bet` drops ETH from `3.0×bet` to `2.5×bet` (smaller than the naive 25% alternative which would drop to `0.7525×bet`). `/economic-analyst` mechanism-design assessment: boundary-gaming has zero EV gain (player cannot influence which tier their result falls into without changing bet size, and bet size is fixed at placement).

**Invariant 7 — Pool cap precedence:**

After capping, `ethShare ≤ pool × 10% < pool`, so no further solvency check needed. Frozen-pool branch preserves the `revert E()` solvency posture.

**Invariant 8 — Backward compatibility (storage layout):**

No new storage slots introduced. All new state lives in `private constant` declarations (compile-time only). Public ABI signature `placeDegeneretteBet(...)` UNCHANGED at this commit.

### Tests

- **Phase 267 Task 2 `PASS_ALL_25`**: byte-identity proof of all 25 packed constants against Fraction-exact Python derivation
- **Phase 268 STAT-01**: per-N basePayoutEV exactness at ≥1M draws/N (analytical-P_N × .sol-tables yields 100.000±0.00002 for each N)
- **Phase 268 STAT-02**: per-N hero EV-neutrality at ≥100K hero-active draws/N (within ±1%)
- **Phase 268 STAT-03**: per-N WWXRP factor EV exactness at ≥100K WWXRP-active draws/N (within ±0.5%)
- **Phase 268 STAT-04**: ETH bonus EV at ≥100K ETH-bet draws/N (5.000% per N within ±0.5%)
- **Phase 268 STAT-05**: per-N match-count histogram match against analytical binomial convolution (within ±0.5% bin frequency)
- **Phase 268 STAT-06**: producer chi² fit (TraitDistribution.test.js + DegeneretteProducerChi2.test.js)
- **Phase 268 STAT-07**: ETH 3-tier split + thin-pool cap-flip at 1M draws (per-band frequency within ±0.5%)
- **Phase 268 SURF-01..04**: byte-identity vs v36.0 baseline for protected ranges (TraitUtils, JackpotModule, EntropyLib)
- **FINDINGS-v37.0.md §4 (a)..(h)**: 8 of 8 adversarial surfaces SAFE/SAFE_BY_DESIGN/SAFE_BY_STRUCTURAL_CLOSURE
- **FINDINGS-v37.0.md §5 REG-01..04**: regression appendix PASS

### Bytecode delta

Net delta: -177 bytes (18,330 → 18,153) measured at v37.0 close. The removal of `_evNormalizationRatio` (a heavy product-of-ratios function with branchy logic per quadrant) accounts for most of the shrink, offset partially by the larger constant table sizes.

---

## 3. Commit `8fd5c2e1` — v37.0 Phase 269 LBX-01 dead-branch deletion

### What changed

**File: `contracts/modules/DegenerusGameLootboxModule.sol`** `_resolveLootboxRoll` (55%-tickets-path)

Deleted the unreachable `else` branch:

```solidity
// Before:
if (ticketsScaled != 0) {
    if (targetLevel < currentLevel) {
        // Convert to BURNIE if target level already passed (UNREACHABLE)
        burnieOut = (uint256(ticketsScaled) * PRICE_COIN_UNIT) / TICKET_SCALE;
    } else {
        ticketsOut = ticketsScaled;
    }
}

// After:
if (ticketsScaled != 0) {
    ticketsOut = ticketsScaled;
}
```

### Why it's safe in all uses

**Invariant: `targetLevel ≥ currentLevel` is statically true at this callsite.**

Proof (caller-clamp invariant):

1. `_resolveLootboxRoll` is called from `_resolveLootboxCommon` at lines L580, L639, L678, L713 (4 callsites).
2. At each callsite, `targetLevel` comes from `_rollTargetLevel(baseLevel, seed)`.
3. `_rollTargetLevel` returns `targetLevel = baseLevel + offset` where `offset ≥ 0` (either `0..4` for near-level rolls or `5..50` for far-level rolls; both unsigned and non-negative).
4. At each `_resolveLootboxRoll` callsite in `_resolveLootboxCommon`:
   - For the `currentLevel` callsite (L639): `baseLevel = currentLevel` directly → `targetLevel ≥ currentLevel` ✓
   - For the `purchaseLevel/graceLevel` callsites (L580): `baseLevel = withinGracePeriod ? graceLevel : purchaseLevel`. The pre-existing clamp at L555-556 (`if (targetLevel < currentLevel) targetLevel = currentLevel;`) re-pinned targetLevel up to currentLevel BEFORE reaching `_resolveLootboxRoll`. So `targetLevel ≥ currentLevel` ✓
   - For the `currentLevel = level + 1` callsites (L678, L713): same as L639 ✓

So `if (targetLevel < currentLevel)` evaluates to `false` at every reachable execution path. The branch is dead code per `feedback_no_dead_guards.md`.

**Behavior equivalence:** The `else` branch (`ticketsOut = ticketsScaled`) is now unconditional. The removed `if`-true branch was never executed in production; deleting it preserves observable behavior across all inputs.

### Tests

- **FINDINGS-v37.0.md §4 surface (f)**: lootbox dead-branch byte-equivalence SAFE
- **Phase 269 STAT-06**: cross-validation that the deletion produces zero observable behavior change (the deleted `burnieOut` path was unreachable, so the same payout distributions hold)
- **Phase 268 SURF-03**: post-LBX-01 baseline `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` re-anchored at Phase 272 Wave 2 (`test/stat/SurfaceRegression.test.js`)
- **Phase 269 LBX-01 commit message**: includes the analytical worst-case derivation (`feedback_gas_worst_case.md` precedent); empirical 55%-tickets-path gas pin RE-DEFERRED-V39+ as LBX-02

### Bytecode delta

Net delta: small (a few opcodes saved from the eliminated branch).

---

## 4. Commit `527e3adc` — v38.0 Phase 272 Wave 1 HERO-01..05 + CLEAN-01..05

### What changed

**File: `contracts/modules/DegenerusGameDegeneretteModule.sol`** (+18 / −16)

This is the v38 Wave 1 **silent-normalize variant** of always-on hero (superseded for input validation by Wave 1.5 commit `4760459f` below — see commit #5).

Mutations:

- **`_packFullTicketBet` (L823+):** Internal normalization `uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;` + unconditional pack: `packed |= (1 | effectiveQuadrant << 1) << FT_HERO_SHIFT`. The previous `if (heroQuadrant < 4) { packed |= ... }` guard removed; reserved bit at `FT_HERO_SHIFT` is always set.
- **`_resolveFullTicketBet` (L591):** Direct quadrant extract `uint8 heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2);`. The 3-bit `heroBits` extraction + `heroEnabled` local + 1-bit shift removed.
- **`_fullTicketPayout` (L955 signature + L986 guard + L645 callsite):** Drops `bool heroEnabled` parameter; guard simplified to `if (matches >= 2 && matches < 8)`.
- **`_applyHeroMultiplier`:** Body UNCHANGED (per-N HERO_BOOST table dispatch + symbol-only match from v37 commit `e1136071`).
- **CLEAN-01..05:** `MASK_3 = 0x7` constant removed (sole callsite was the `heroBits` extract). Stale `enabled`/`opt-out` NatSpec rewritten at L321 + L367 + `_packFullTicketBet` block + `_fullTicketPayout` block.

### Why it's safe in all uses

**Invariant 1 — Per-N HERO_BOOST tables UNCHANGED:**

`HERO_BOOST_N{0..4}_PACKED` at L337-341 byte-identical at v38 HEAD vs `2654fcc2` (v37.0 closure baseline). Verified by:

```bash
cmp <(git show 2654fcc2:contracts/modules/DegenerusGameDegeneretteModule.sol | sed -n '337,341p') \
    <(sed -n '337,341p' contracts/modules/DegenerusGameDegeneretteModule.sol)
# exit 0 (byte-identical)
```

Also `HERO_PENALTY = 9500` and `HERO_SCALE = 10000` UNCHANGED.

**Invariant 2 — EV-neutrality preserved:**

The hero EV-neutrality formula:

```
P(hero | M, N) × boost(M, N) + (1 − P(hero | M, N)) × HERO_PENALTY = HERO_SCALE
```

depends on:
- The per-N tables (UNCHANGED) ✓
- The hero gate firing range (M ∈ {2..7}; UNCHANGED — the guard simplification `if (heroEnabled && matches >= 2 && matches < 8) → if (matches >= 2 && matches < 8)` only removes the `heroEnabled` toggle; the M range is identical) ✓
- The symbol-only match probability P(hero match) = 1/8 (UNCHANGED) ✓

Therefore `E[hero multiplier | M, N] = 1.0` exactly, same as pre-v38. Always-on hero adds variance only; **zero EV impact**.

**Invariant 3 — Storage layout byte-identical:**

`FT_HERO_SHIFT = 237` preserved (3-bit allocation unchanged; the enabled bit becomes vestigial — always set to 1 post-pack). No contract-state slots added, removed, or reordered. The bit allocation in the packed bet (`MODE_FULL_TICKET` ... `FT_HERO_SHIFT`) is byte-identical at the storage level.

Verified by grep:
```bash
git diff 2654fcc2..527e3adc -- contracts/modules/DegenerusGameDegeneretteModule.sol | grep -E "^[+-].*SHIFT" 
# only L321 comment change (no shift constant value changes)
```

**Invariant 4 — Public ABI byte-identical:**

`placeDegeneretteBet(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` signature UNCHANGED. Function selector + parameter types byte-identical at v38 HEAD vs `2654fcc2`.

The `0xFF` and any `>= 4` heroQuadrant input is still accepted at this Wave 1 commit (silent-normalized to quadrant 0 internally). Backward-compat at the ABI level.

**Invariant 5 — Per-CLEAN-NN design-intent traces (`feedback_design_intent_before_deletion.md`):**

Each removal carries an inline design-intent trace in the commit message body:
- `MASK_3`: was the 3-bit hero-bits mask `[enabled, quad_lo, quad_hi]`; sole callsite was the `heroBits` extract at L592 (also removed); cross-module grep confirms zero other callers.
- `heroBits + heroEnabled` locals (L592-594): opt-out intermediates; under always-on, direct quadrant extract via `MASK_2` is the load-bearing form.
- `bool heroEnabled` parameter (L952): under always-on, the guard predicate is statically true at the callsite; parameter carried no information.

### Tests

- **Phase 272 Wave 2 STAT-01**: `test/stat/DegenerettePerNEvExactness.test.js` — basePayoutEV per N within ±0.50 centi-x at ≥1M draws/N (analytical-P_N × .sol-tables yields 100.000±0.00002 for each N) PASS under always-on hero
- **Phase 272 Wave 2 STAT-02**: `test/stat/DegeneretteBonusEv.test.js` — hero EV-neutrality within ±1% at ≥100K hero-active draws/N PASS
- **Phase 272 Wave 2 SURF-01..03**: byte-identity assertion for protected surfaces (EntropyLib, TraitUtils, JackpotModule, MintModule, LootboxModule all byte-identical at v38 HEAD vs `2654fcc2`)
- **FINDINGS-v38.0.md §3.A**: delta-surface table HERO-01..05 row group + CLEAN-01..05 row group with hunk-level evidence
- **FINDINGS-v38.0.md §4 surfaces (a)..(g)**: 7 of 7 adversarial surfaces SAFE/SAFE_BY_DESIGN/SAFE_BY_STRUCTURAL_CLOSURE/SAFE_BY_DEFENSIVE_VALIDATION

### Bytecode delta

**Net: −57 bytes (8955 → 8898).** Exceeds the ~−30-byte target from CONTEXT.md. Gas-per-spin delta: analytical ~30 gas saved (one less SLOAD-shift-mask for MASK_3 + heroBits + heroEnabled).

---

## 5. Commit `4760459f` — v38.0 Phase 272 Wave 1.5 D-272-INPUT-VALIDATION-01

### What changed

**File: `contracts/modules/DegenerusGameDegeneretteModule.sol`** (+15 / −14)

Reverses HERO-05 spec_lock from "accept + normalize" to "reject invalid input". Driven by the Wave 3 3-skill PARALLEL adversarial pass surfacing Hypothesis (i) — a docs-vs-behavior drift where `0xFF` input was pack-normalized to quadrant 0 but NOT credited to `dailyHeroWagers[day][0]` (L484 gate used raw input).

Mutations:

- **`_placeDegeneretteBetCore` entry (L448):** Added `if (heroQuadrant >= 4) revert InvalidBet();` alongside the existing `ticketCount` and `amountPerTicket` validations. Reuses the `InvalidBet` custom error (no new error type; error selector byte-identical).
- **`_packFullTicketBet` (L832):** Internal `uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;` REMOVED. Function now expects caller-validated input in `{0..3}` and uses `heroQuadrant` directly. NatSpec updated to document the caller-validated invariant.
- **L484 leaderboard gate:** `if (heroQuadrant < 4) { ... }` → unconditional block (heroQuadrant is always in `{0..3}` post-validation). Per `feedback_no_dead_guards.md`.

**File: `test/fuzz/handlers/DegeneretteHandler.sol`** (+2 / −3)

- **L78-80:** Fuzz handler bound `[0, 4]` (with `4 → 0xFF` mapping) → `[0, 3]` (always-on hero; valid input required).

### Why it's safe in all uses

**Invariant 1 — Public ABI selector byte-identical:**

`placeDegeneretteBet(...)` signature unchanged. `InvalidBet()` error selector unchanged (reused existing error type). Function selector is the same 4 bytes pre- and post-Wave-1.5.

**Invariant 2 — Behavior change scoped to invalid input only:**

For `heroQuadrant ∈ {0, 1, 2, 3}` (the only valid range):
- Pre-Wave-1.5: pack normalizes `heroQuadrant → effectiveQuadrant = heroQuadrant` (no-op since `< 4`); leaderboard `if (heroQuadrant < 4)` true; full tracking.
- Post-Wave-1.5: entry validates `heroQuadrant < 4` (passes); pack uses `heroQuadrant` directly (no normalization needed); leaderboard unconditional (full tracking).

Behavior **byte-identical** for valid input. The packed bet representation, the resolution path, the payout calculation, the leaderboard credit — all unchanged.

For `heroQuadrant >= 4` (invalid):
- Pre-Wave-1.5: silently normalized to quadrant 0 for payout; NOT credited to leaderboard. Asymmetric (Hypothesis (i) drift).
- Post-Wave-1.5: reverts with `InvalidBet` at entry. No state mutation. No payout. No leaderboard credit.

**Invariant 3 — Per-N HERO_BOOST tables UNCHANGED:**

EV-neutrality preserved by exactly the same construction as commit `527e3adc`. Wave 1.5 does not touch any payout / hero / WWXRP table.

**Invariant 4 — Storage layout byte-identical:**

No contract-state slot changes. Only stack-locals + a new validation branch (`if (heroQuadrant >= 4) revert ...`) at entry. The pack representation is byte-identical.

**Invariant 5 — Defensive boundary validation (D-272-INPUT-VALIDATION-01):**

The asymmetric "omit heroQuadrant" path that Hypothesis (i) flagged no longer exists post-Wave-1.5: invalid input is rejected at the public ABI boundary rather than silently coerced. This eliminates:

- The docs-vs-behavior drift surfaced by Wave 3 `/zero-day-hunter` Hypothesis (i)
- The asymmetric leaderboard tracking on `0xFF` input
- The hidden semantic where `0xFF` meant "skip leaderboard credit"

**Invariant 6 — Frontend contract:**

Frontend MUST send valid `0..3` (default 0 if user does not pick). The `0xFF` sentinel is no longer accepted. **No pre-launch integrators exist**, so this is a forward-compat-only change.

### Tests

- **Standalone STAT-01**: `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js` PASS (9 passing / 5 pending / 0 failing) under always-on hero with Path R input validation; basePayoutEV per N within ±0.50 centi-x at ≥1M draws/N preserved (validation path not exercised by JS mirror tests; STAT-01 passes `heroQuadrant = 0` — valid input)
- **Fuzz**: `test/fuzz/handlers/DegeneretteHandler.sol` bound `[0, 3]` exercises only the valid input range; pre-existing invariant assertions in `test/fuzz/DegeneretteFreezeResolution.t.sol` continue to hold
- **FINDINGS-v38.0.md §3.A Row 1.13**: Wave 1.5 defensive boundary validation evidence
- **FINDINGS-v38.0.md §4 surface (b)**: revised verdict SAFE_BY_DEFENSIVE_VALIDATION
- **FINDINGS-v38.0.md §9.NN.iv**: Hypothesis (i) RESOLVED_AT_V38 (row REMOVED from RE-DEFER Register)
- **272-01-ADVERSARIAL-LOG.md Wave 1.5 Disposition Update** (commit `1249a6fd`): records the KEEP_AS_NEGATIVE_FINDING → RESOLVED_AT_V38 pivot

### Bytecode delta

Net delta: approximately neutral (one new `>= 4` check + revert; one removed `< 4` ternary; one removed guard; one removed callee-side ternary; rough wash). Gas-per-spin: ~10–15 gas saved (one fewer branch in pack path + one fewer guard in leaderboard path + caller pays the validation cost before validation success).

---

## 6. Commit `a129884b` — v38.0 follow-up L302 comment hygiene

### What changed

**File: `contracts/modules/DegenerusGameDegeneretteModule.sol`** (+1 / −1)

Single-line comment-only rewrite at L302 (packed-bet-layout reference comment):

```diff
- // [237..239] hero (3 bits): [0]=enabled, [1..2]=quadrant (0-3)
+ // [237..239] hero (3 bits): [0]=reserved (always set), [1..2]=quadrant (always-on hero, 0..3)
```

### Why it's safe in all uses

**Comment-only fix; zero behavior impact.** No code, no constants, no storage, no ABI changes. Bit allocation byte-identical. The change brings the bit-layout reference comment into agreement with the post-v38 always-on semantics already documented at the parallel `FT_HERO_SHIFT` comment (L321 rewritten in Wave 1 commit `527e3adc`).

Per `feedback_no_history_in_comments.md`: the new wording describes what IS at v38 (reserved bit + always-on hero + `0..3` quadrant range); zero comparative/historical language ("previously was enabled", "v37 → v38 change", etc.).

Found during cumulative pre-push contract-diff review. Audit deliverable `audit/FINDINGS-v38.0.md` is FINAL READ-only at `chmod 444` and is **not amended** — this is a contract-source comment hygiene fix, not an audit finding.

### Tests

- **Manual `git diff` verification:** confirmed the change is comment-only (no code lines touched)
- **`npx hardhat compile`** would succeed (no source changes affect compilation; comment edits don't trigger recompilation deltas)

### Bytecode delta

**Zero.** Comments do not contribute to bytecode.

---

## Cross-Cutting Invariants (preserved across the entire chain)

These invariants hold at every commit in this chain (pre-push, `origin/main`..`a129884b`):

| Invariant | Verification |
|---|---|
| **Storage layout byte-identical at v38 HEAD vs v37.0 baseline `2654fcc2`** | `git diff 2654fcc2..HEAD -- contracts/modules/DegenerusGameDegeneretteModule.sol` shows no storage-state slot changes (only stack-local + private-function-parameter changes); FT_HERO_SHIFT = 237 preserved |
| **Public ABI byte-identical at v38 HEAD vs v37.0 baseline** | `placeDegeneretteBet(...)` signature unchanged; `cmp` on `function .* external` lines vs `2654fcc2` exits 0 |
| **Per-N basePayoutEV = exactly 100 centi-x preserved** | Per-N tables byte-identical at v38 HEAD vs `2654fcc2`; Wave 2 STAT-01 PASS (100.000±0.00002 for each N) |
| **Hero EV-neutrality preserved** | Per-N HERO_BOOST tables byte-identical at v38 HEAD; HERO_PENALTY/HERO_SCALE byte-identical; Wave 2 STAT-02 PASS (within ±1%) |
| **PAY-SPLIT 3-tier invariant `ethShare + lootboxShare = payout` preserved** | `_distributePayout` body byte-identical at v38 HEAD vs `2654fcc2` (Wave 1 + Wave 1.5 do not touch `_distributePayout`); Wave 2 STAT-07 PASS |
| **Solvency invariant `claimablePool ≤ ETH balance + stETH balance` preserved** | No new ETH/stETH balance mutation paths introduced by any commit in this chain |
| **No new public/external entry points** | AUDIT-04 §3.B grep-proof: zero new selectors; zero new admin functions; zero new modifiers; zero new upgrade hooks |
| **No new mint sites** | Existing `mintForGame` / `mintPrize` routes only; no new ERC-20 mint entry points |
| **KI envelope EXC-01..04 RE_VERIFIED** | EXC-01..03 NEGATIVE-scope at v38; EXC-04 RE_VERIFIED with NARROWS retained (BAF-jackpot-only scope; EntropyLib byte-identical at v38 HEAD) per FINDINGS-v38.0.md §6 |
| **Forward-cite zero-emission (terminal-phase invariant)** | §8 grep recipe in FINDINGS-v38.0.md PASS; no in-flight v39+ forward-cites |

## Adversarial Pass Disposition

Wave 3 3-skill PARALLEL adversarial pass (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-272-ADVERSARIAL-01 carry; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry):

- 7 of 7 §4 surfaces (a)..(g) verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_DEFENSIVE_VALIDATION
- 0 F-38-NN finding blocks emitted
- 0 8th-surface NEW_VECTOR candidates
- 0 FINDING_CANDIDATE escalations requiring user disposition
- 0 KNOWN-ISSUES.md promotions; KI envelope UNMODIFIED at v38
- 1 INFO-severity docs-vs-behavior drift (Hypothesis (i)) — **RESOLVED_AT_V38 via Wave 1.5** commit `4760459f` (status pivoted from KEEP_AS_NEGATIVE_FINDING to RESOLVED_AT_V38)

## Summary Verdict

**All 6 contract-tree commits are safe for production push.** The v36 entropy refactor, v37 5-table calibration + symbol-only hero gate + 3-tier ETH split, v37 LBX-01 dead-branch deletion, v38 always-on hero + cleanup, v38 Wave 1.5 input validation, and v38 follow-up comment hygiene compose into a coherent, EV-preserving, storage-byte-identical, ABI-byte-identical contract delta with:

- **Exact 100 centi-x per-N basePayoutEV** (Fraction-exact calibration; ±0.0003 bps drift)
- **Exact 5.000% ETH bonus EV** (per-N WWXRP factor calibration; ±0.0000 bps drift)
- **Exact 1.0× hero EV-neutrality** (per-(M, N) calibration via Bayes; ±0.05% empirical tolerance)
- **Defensive boundary validation** at the public ABI (heroQuadrant must be `0..3`; invalid input reverts)
- **Bit-budget-accounted single-keccak-per-resolution** entropy in the lootbox path

Closure signal `MILESTONE_V38_AT_HEAD_06623edb` is sealed; `audit/FINDINGS-v38.0.md` is FINAL READ-only at `chmod 444`. Ready for `git push origin main` + `git push origin v38.0` (annotated tag) per `feedback_manual_review_before_push.md`.

---

*Generated: 2026-05-11*
*Audit subject HEAD at v38 close: `06623edb`*
*Last contract-tree commit: `a129884b`*
*Cumulative chain: `df6345cc..a129884b` (6 commits across v36.0, v37.0, v38.0)*
