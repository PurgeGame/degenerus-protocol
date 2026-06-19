# Phase 445: SPEC — Design-Lock the Implementation Contract - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 445 produces a **build-ready implementation contract** (the SPEC) for the v71.0 Foil Pack — **no `.sol`**. It translates the already-locked `V71-FOILPACK-FINAL-SPEC.md` into the exact implementation surface so that Phase 446 (IMPL) is mechanical: entrypoint signatures, storage layout + packing, the `foilBoostBps` curve coefficients, the sibling-producer rarity PMF, the isolated payout table + currency lane, the match algorithm (LIVE vs HERO-FREE), module placement under EIP-170, and a Monte-Carlo confirm of the ≈2-faces/30d calibration.

**Requirements are LOCKED, not open.** The 23 REQ-IDs (FOIL-01..05, RARE-01..04, MATCH-01..10, SEC-01..04) are fixed in `.planning/REQUIREMENTS.md`, and the design is fixed in `.planning/V71-FOILPACK-FINAL-SPEC.md` ("where the exploratory context conflicts with this file, this file wins"). This discussion did **not** re-open the design — it locked the handful of engineering coefficients the FINAL-SPEC delegates to engineering.

**In scope:** pin the coefficients/signatures/layout/algorithm/placement so IMPL is mechanical; Monte-Carlo-confirm the calibration.
**Out of scope:** any `.sol` edit (that is 446); adding 40/40/20 to the *existing* Degenerette game; any change to the v70-frozen shared trait producers or the lootbox/jackpot magnitude tables; the frontend reveal UI (separate repo).
</domain>

<decisions>
## Implementation Decisions

### Process / phase shape
- **D-01:** Phase 445 is a **design-lock only** — its output is the build-ready spec, no contract code. The FINAL-SPEC + REQUIREMENTS are the authoritative inputs; the SPEC research/plan pins what they leave to engineering, with the locked targets below as the acceptance test.

### `foilBoostBps(score)` activity curve (RARE-02)
- **D-02:** A smooth, **monotone ×2 → ×6** multiplier: floor **×2 @ score 0**, ceiling **×6 @ max**, fitted over the **existing** `ActivityCurveLib` knees (`ACTIVITY_SEG_B_KNEE_POINTS = 500` at `ActivityCurveLib.sol:26`; the 500/30000 knee pair). **"~×5 @ score 350" is ILLUSTRATIVE of the shape only — it is NOT a pinned breakpoint** (user-confirmed). The researcher fits the cleanest ×2→×6 curve on the existing knees and writes the exact segment bps; 350 is not written as a segment boundary.

### Sibling-producer rarity PMF — the "mix-to-rare-tail" transform (RARE-01, RARE-04)
- **D-03:** The boost is **tapered down the rarity tail, not a flat ×M on every tier** (user-refined). Shape:
  - **Gold (color 7) takes the FULL multiplier:** `p_gold = baseline_gold × M`, where baseline_gold = **2/256 = 0.78125%/quadrant** (verified at `weightedColorBucket`, `DegenerusTraitUtils.sol:115`). At M=6 ⇒ **4.69% ≈ the spec's 4.7%** ✓.
  - **Tiers below gold (colors 6 → 3) get a progressively SMALLER lift** as the tier becomes less rare — "the less rare traits don't need full weight." Gold = full ×M; each lower tier tapers toward 1×.
  - **Funded by reducing the three 25% commons** — colors 0/1/2 (each 64/256 baseline) absorb the redistributed mass.
  - **Symbol stays uniform 1/8** (unchanged from the frozen producers); the boost is **color-tier only**.
  - **Acceptance (researcher pins the exact taper schedule + Monte-Carlo-verifies):** valid PMF (Σ = 1, all tiers ≥ 0) at **every** M ∈ [2, 6]; `p_gold` exactly `baseline×M`; boost monotone-decreasing down the tail; commons 0/1/2 are the sole funding source; gold-odds-vs-10-tickets anchors hold (≈ tie at ~×2.5, ~2× at max — these follow automatically from `p_gold = baseline×M` over 16 boosted vs 40 baseline quadrants and so are **not** disturbed by the taper).

### Module placement (SEC-03)
- **D-04:** New `GAME_FOILPACK_MODULE` **vs** a roomy existing module + thin facade stub — **the researcher measures live EIP-170 headroom and decides** (engineering call, not a vision call). Hard constraints: **NOT** `MintModule`; the body lives in a module; new storage is **appended in `DegenerusGameStorage`** (delegatecall-shared, never in a module); a thin `payable buyFoilPack(...)` facade stub on the facade.

### Calibration policy (MATCH-10)
- **D-05:** The payout table (**2-of-4 = 5 faces / 3-of-4 = 65 faces / 4-of-4 = half whale pass + bonus spin**) and the 40/40/20 lane are **LOCKED**. The phase-445 Monte-Carlo **confirms** ≈2 faces/pack/30d and **reports** the realized number; if it lands **materially off** ≈2, **flag it to the user** — never silently retune the locked table.

### Claude's Discretion (delegated to SPEC research, bounded by the acceptance above)
- The exact functional form of the rare-tail taper (D-03) — geometric, linear-in-rank, or per-threshold-bucket reallocation — provided it satisfies the D-03 acceptance constraints.
- The exact segment bps of `foilBoostBps` (D-02).
- The module-placement decision (D-04), driven by the live EIP-170 measurement.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The locked design (read first, in order)
- `.planning/V71-FOILPACK-FINAL-SPEC.md` — **THE authoritative locked design.** "This file wins" on any conflict with the exploratory context. §1 Purchase, §2 rarity boost, §3 match lottery + tiers + currency + calibration, §4 hero-manipulation policy, §5 storage/integration, §6 hard-requirements floor.
- `.planning/REQUIREMENTS.md` — the 23 locked REQ-IDs (FOIL-01..05, RARE-01..04, MATCH-01..10, SEC-01..04) + Future/Out-of-Scope.
- `.planning/V71-FOILPACK-DESIGN-CONTEXT.md` — grounding/history §1–§7; every `file:line` citation behind the FINAL-SPEC (8 read-only design passes).
- `.planning/ROADMAP.md` — v71.0 section (~lines 35–105): phase 445 goal + the 4 success criteria.

### Code anchors (the surface 445 specs against)
- `contracts/DegenerusTraitUtils.sol` — **frozen, DO NOT EDIT:** `weightedColorBucket`:115 (baseline color PMF; gold = 2/256 = 0.781%/quadrant), `traitFromWord`:143, `packedTraitsFromSeed`:169. **Sibling model to CLONE** for `traitFromWordFoil`/`packedTraitsFoil`: `packedTraitsDegenerette`:201 + `_degTrait`:218 (per-quadrant `[QQ][CCC][SSS]`, 4×uint32 pack).
- `contracts/libraries/ActivityCurveLib.sol` — home of the new `foilBoostBps(score)`; existing knee `ACTIVITY_SEG_B_KNEE_POINTS = 500`:26; segment-bps idioms to model on: `decMultBps`:42, `centuryBps`:74.
- `contracts/storage/DegenerusGameStorage.sol` — append the `foilRecord` mapping (4×24-bit sigs + level stamp) + the sparse per-`(day,drawKind,ticketIndex)` claimed marker; century level-stamp idiom at `:1857-1876`.
- `contracts/modules/DegenerusGameJackpotModule.sol` — the hero override `_applyHeroResult` / `getRandomTraits` at `:1316-1341`, for the LIVE (2/3) vs HERO-FREE pure-VRF (4-of-4) re-derivation.
- `contracts/libraries/JackpotBucketLib.sol` — `:281-286` hero/VRF trait derivation.
- `contracts/modules/DegenerusGameMintModule.sol` — `cachedScore` at `:1709` (the buy-time activity-score freeze source for RARE-03).
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`packedTraitsDegenerette` / `_degTrait`** (`DegenerusTraitUtils.sol:201`) — exact structural template for the new `packedTraitsFoil` / `traitFromWordFoil` sibling: per-quadrant 6-bit `[CCC][SSS]`, quadrant bits OR'd in, 4 bytes packed into a `uint32`. Clone-and-modify the color stage; keep the symbol stage uniform.
- **Existing ETH-capped degenerette spin** — `ETH_WIN_CAP_BPS = 1000` (10% of `futurePrizePool`), over-cap spills to lootbox, credited via `claimablePool`/`_creditClaimable`. Reused verbatim for the **40% ETH** lane (structural solvency: ethShare ≤ 10%·pool).
- **`coin.mintForGame`** (FLIP) and **`wwxrp.mintPrize`** (WWXRP) — the **40% FLIP** and **20% WWXRP** mint lanes; free to the protocol.
- **`whalePassClaims[player] += 1`** — the pool-neutral deferred grant for the 4-of-4 tier.
- **`rngWordByDay[day]`** — retained daily RNG; the claim-time re-derivation source for both the winning traits and the disjoint magnitude/currency lanes (no draw-time scan).

### Established Patterns
- **Century level-stamp flag idiom** (`DegenerusGameStorage.sol:1857-1876`) — drives the one-foil-pack-per-RAW-level cap and the `foilRecord` per-level auto-reset (keyed on raw `level`, not `_activeTicketLevel()`).
- **4-segment bps curve** in `ActivityCurveLib` (`decMultBps`/`centuryBps`) — the form for `foilBoostBps`, reusing the 500/30000 knees.
- **Pull/claim + sparse `keccak` marker** — `claimFoilMatch(day, ticketIndex)` settles via a sparse `keccak(player,level,day,drawKind,ticketIndex)` claimed marker; each `(day,drawKind,ticketIndex)` claimable at most once; keeps `advanceGame` flat.

### Integration Points
- **Foil tickets enter the regular jackpot as NORMAL entries** — same `traitBurnTicket` eligibility; boosted traits write real color tiers incl. `color==7` gold → participate in jackpot gold channels with **no new jackpot wiring**.
- **New storage appended only in `DegenerusGameStorage`** (delegatecall-shared); the foil body in a module + a thin `payable` facade stub.
- **Foil spend pool-split forks to 75% next / 25% future** (normal ticket is 90/10) — foil leg only.
</code_context>

<specifics>
## Specific Ideas

- **Verified self-consistency:** baseline gold = `2/256 = 0.78125%/quadrant` (`weightedColorBucket`); `×6 ⇒ 4.69% ≈` the spec's 4.7% gold target. The gold-odds-vs-10-tickets anchors (≈22.3% vs 26.9% chance of ≥1 gold @ score 0; 53.6% @ max) reproduce exactly from `p_gold = baseline×M` over 16 boosted quadrants vs 40 baseline — confirming the rarity targets hold under the tapered transform (the taper touches only the intermediate tiers).
- **Face peg:** `1 face = 1 whole ticket = 1,000 FLIP = the level's ticket price in ETH` (fixed FLIP peg; ETH-per-face floats with level). UI shows the **post-cap realizable** ETH as the magnitude; reveal is magnitude-first / currency-second (pure UI ordering; both fixed atomically on-chain).
</specifics>

<deferred>
## Deferred Ideas

- **Indexer parity events** for the foil buy and the match claim — additive, can land after the feature (per REQUIREMENTS "Future Requirements").
- **(carried from v70)** mutation + Halmos formal on the new foil module; `roi`/`wwxrp` direct-body coverage.
- **Out of scope (per REQUIREMENTS):** adding WWXRP / the 40/40/20 split to the *existing* Degenerette game; any change to the v70-frozen shared trait producers or the existing lootbox/jackpot magnitude tables; the frontend reveal UI (separate repo).

None of the above belongs in v71.0 IMPL — discussion stayed within phase scope.
</deferred>

---

*Phase: 445-spec-design-lock-the-implementation-contract*
*Context gathered: 2026-06-19*
