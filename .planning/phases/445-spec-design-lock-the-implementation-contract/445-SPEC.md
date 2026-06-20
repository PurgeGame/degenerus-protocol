# SPEC — v71.0 Foil Pack Design-Lock (economics · storage · entrypoints · threat model)

> **Baseline (frozen subject):** the v70.0 closure subject — `contracts/` tree `99f2e53f` @ `ffbd7796`
> (closure `MILESTONE_V70_AT_HEAD_25ff6aaed0e9209e2003f467a3607056bfac9c03`; origin/main `0bc8cf72`). Every
> contract anchor cited below is grounded on `ffbd7796` (the byte-frozen v70 subject the v71 feature resets).
> `contracts/*.sol` is CLEAN at milestone start.
>
> **Role.** This is the single SPEC deliverable for Phase 445. It translates the locked
> `V71-FOILPACK-FINAL-SPEC.md` into the exact build surface — every rarity coefficient, the boost curve, the
> packed storage layout, the two entrypoint bodies, the winning-set re-derivation, the isolated payout, and
> the calibration — so that Phase 446 authors the ONE batched `contracts/*.sol` diff **mechanically**: no
> "by construction" assumptions, no mid-diff re-grep, no unsettled decision beyond the two USER pins below.
>
> **Scope discipline.** PAPER-ONLY. This phase edits ZERO `contracts/*.sol`. The contract requirements
> (FOIL-01..05 · RARE-01..04 · MATCH-01..09 · SEC-03) are authored at Phase 446 as the single batched diff
> (the sole approval gate); MATCH-10 is proven empirically at 447; SEC-01 / SEC-02 / SEC-04 are attested at
> 448–449 per the audit-milestone pattern.
>
> **Inputs (source of truth).** `445-RESEARCH.md` (authoritative — every coefficient adversarially
> V1/V2/V3-verified) · `445-CONTEXT.md` (`<decisions>` D-01..D-05) · `V71-FOILPACK-FINAL-SPEC.md`
> ("this file wins" — the locked design) · `REQUIREMENTS.md` (the 20 phase-445 REQ-IDs). The three
> section files `445-SPEC-A-economics.md` / `445-SPEC-D-storage.md` / `445-SPEC-E-entrypoints.md` are
> consolidated into §A / §D / §E below; this document is self-contained for an IMPL-446 author.
>
> **Convention.** No fenced Solidity function bodies anywhere. A **foil signature** is a packed `uint32`
> `[QQ][CCC][SSS]`×4 in the **identical byte layout** as `packedTraitsFromSeed` / `packWinningTraits`, so
> every match predicate is a direct byte compare. `level` = the raw `uint24 public level`
> (`DegenerusGameStorage.sol:236`); `_activeTicketLevel()` = the rng-lock-aware variant used only for
> ticket queueing.

---

## 0. Decisions Locked (D-01..D-05) + the Two Pins

> Mirroring the house SPEC-V61 "Locked Knobs" form: each decision restates its LOCKED value and the affected
> REQ-IDs. The genuine open SPEC decisions are the two layout pins (§D.6) plus the single-slot player-loss
> edge — all three are pulled forward into the **USER Decisions** callout in §T below.

- **D-01 — Design-lock only (no `.sol`).** Phase 445 produces this SPEC; `V71-FOILPACK-FINAL-SPEC.md` +
  `REQUIREMENTS.md` are authoritative. ZERO `contracts/*.sol` edits in this phase. The contract diff lands
  ONCE at 446 (the sole approval gate).
- **D-02 — `foilBoostBps` shape; boundaries `{0, 300, 500, 30000}`; `350` NOT pinned.** The activity curve
  reuses the two existing shared knees and delivers ×2→×6 over `[20000, 60000]` bps (§A.2). "~×5 @ 350" is
  honored BY SHAPE (×5.0 lands at `K = 300`); `350` is illustrative, not a breakpoint.
- **D-03 — Tapered rarity PMF; `p_gold = (2/256)·M` exact; commons 0/1/2 the sole funding sink** (§A.1).
- **D-04 — New `GAME_FOILPACK_MODULE` (engineering EIP-170 call).** Body ≈8–11 KB starts at 0 → comfortable
  headroom; `MintModule` is excluded (SEC-03 + ~1,116 B free) (§F).
- **D-05 — ≈2 faces/pack/30d payout target; CONFIRM-and-REPORT, never silently retune** (§E.7). Realized
  **1.9376** lands 3.1% low → no recalibration flag; the locked table stays LOCKED.

**The two pins (§D.6):** PIN 1 — `foilRecord` level-keying (LOCKED single-slot `mapping(address => uint256)`,
USER-sign-off on the player-loss edge); PIN 2 — the packed bit-offset (LOCKED stamp `[144-167]` / payload
`[0-143]`).

---

## 1. Corrected Anchors (carry verbatim into 446)

> The four V3-corrected anchors. Each was mis-stated in an earlier draft and re-grounded on the `ffbd7796`
> subject; the IMPL diff MUST use the corrected value everywhere — a stale value steers 446 to wrong code.

| # | Anchor | Earlier (wrong) | CORRECTED (carry into 446) | Why it matters |
| --- | --- | --- | --- | --- |
| 1 | foil-ticket queue scale | `_queueTicketsScaled(..., 4, ...)` | **`400`** (= 4 × `TICKET_SCALE = 100`) | the third arg is `quantityScaled` in `TICKET_SCALE = 100` units (`DegenerusGameStorage.sol:157, :663`); passing `4` queues **0.04** of a ticket, not 4. The load-bearing pin of E.1 step 7. |
| 2 | whale-pass deferred grant | (declare a new mapping) | **`whalePassClaims` already exists at `:1122`** (`mapping(address => uint256)`) | do **NOT** re-declare; the 4-of-4 tier does `whalePassClaims[player] += 1` against the existing slot. |
| 3 | ETH-cap spin clone source | `:402-446` | **`DegenerusGameDegeneretteModule.sol:877-915`** (`maxEth` `:889`, lootbox-resolve `:915`) | the ETH lane clones this capped-spin path (10% `futurePrizePool` clamp + lootbox spill), not the previously-cited `:402-446`. |
| 4 | double-claim marker name | `foilClaimed` | **`foilMatchClaimed`** (unified) | V3 DEFECT E-γ name unification — the storage marker and the claim-side guard use ONE name. |

Adjacent corrected anchors carried inline in the sections: `dailyHeroWagers[day-1]` (the hero pool index is
the prior-day slot — `dailyIdxFor(day) == day - 1`, §E.3); the E.6 168-bit `foilRecord` superset adopted over
the D.1 24-bit variant (V3 DEFECT D-α, §D.1.2).

---

## §A — Economics (rarity PMF + `foilBoostBps` curve)

> Build-ready economics. Every coefficient is the RESEARCH §A/§C reconciled-and-corrected value (V1 PASS).
> The v70-frozen shared producers (`weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed`) are NOT
> edited (RARE-01); the foil tickets route to a **new sibling** producer.

### A.1 Sibling-producer rarity PMF (RARE-01 / RARE-02 / RARE-04 / FOIL-05)

**A.1.1 Two new sibling producers (RARE-01 — frozen producers untouched).** Cloned structurally from
`packedTraitsDegenerette` / `_degTrait` (`DegenerusTraitUtils.sol:201-223`):

- `traitFromWordFoil(uint64 rnd, uint256 multBps) internal pure returns (uint8)` — the per-quadrant 6-bit
  `[CCC][SSS]` producer: **color** from the tapered ladder of A.1.4 (`multBps` enters here, `10000 = 1×`),
  **symbol** uniform `1/8` from `rnd >> 32 & 7` (byte-identical to `_degTrait`'s symbol stage). Quadrant bits
  added by the caller.
- `packedTraitsFoil(uint256 rand, uint256 multBps) internal pure returns (uint32)` — the 4-quadrant packer:
  calls `traitFromWordFoil` on each 64-bit lane (`uint64(rand)`, `>>64`, `>>128`, `>>192`), OR's in the
  quadrant identifiers (`| 64`, `| 128`, `| 192`), and packs four bytes in the **identical
  `[QQ][CCC][SSS]`-per-byte layout** as `packedTraitsFromSeed` / `packedTraitsDegenerette`.

**ONLY the color stage changes** vs the Degenerette sibling; the symbol stage and pack layout are copied
verbatim. **RARE-01:** the frozen producers `weightedColorBucket`, `traitFromWord`, `packedTraitsFromSeed`
(`DegenerusTraitUtils.sol:115`, `:143`, `:169`) are NOT edited, retyped, or moved — the foil path is purely
additive (a new sibling, exactly as `packedTraitsDegenerette` already coexists beside the frozen heavy-tail
producer). `multBps` is the `foilBoostBps` output (A.2), **frozen at buy** from `cachedScore` and passed in
at resolve — never live-read (RARE-03; A.2.4).

**A.1.2 Baseline color widths** (verified at `weightedColorBucket` `:115-126`, `/256`):

| color           | 0  | 1  | 2  | 3  | 4  | 5 | 6 | 7 (gold) |
| --------------- | -- | -- | -- | -- | -- | - | - | -------- |
| `base[c]` /256  | 64 | 64 | 64 | 32 | 16 | 8 | 6 | **2**    |

Colors 0/1/2 are the three **25% commons** (`64/256`). Gold (color 7) is `2/256 = 0.78125%` per quadrant —
the `p_gold` floor the multiplier scales (FOIL-05).

**A.1.3 The taper rule (RARE-04 — tapered, NOT flat ×M).** The boost is **linear in the rare-rank**: gold
takes the full multiplier `M`, each less-rare tier tapers toward `1×`. With `M = multBps / 10000`:
`boost(c) = 1 + (M − 1)·w_c`, rare-rank weights `w_7 = 5/5` (full ×M), `w_6 = 4/5`, `w_5 = 3/5`, `w_4 = 2/5`,
`w_3 = 1/5`, `w_0 = w_1 = w_2 = 0` (the three 25% commons — the **SOLE funding sink**, never boosted).
Per-tier: `p_c = (base[c]/256)·(1 + (M−1)·w_c)` for `c ∈ {3..7}`; the commons absorb the redistributed mass
`Δ = Σ_{c∈3..7} p_c − Σ_{c∈3..7} base[c]/256`, split three ways. Invariants (re-verified exactly in V1):
`p_gold = (2/256)·M` exactly (`w_7 = 1`; at `M=6 ⇒ 12/256 = 4.6875% ≈ 4.7%`, FOIL-05); monotone-decreasing
boost down the tail (`boost(7) > … > boost(3) > 1` for all `M > 1`; factors `[6,5,4,3,2]` at M=6, RARE-04);
commons the sole shrink; symbol uniform `1/8` unchanged (RARE-02).

**A.1.4 Resolve mechanism — the `/15360` integer cutoff ladder (build-ready, exact).** 256-resolution is too
coarse for the taper. Compute cutoffs in a `/15360` super-ladder (`15360 = 256 × 60`; `×60` clears both the
`/5` taper denominator and the 3-way common split), then walk the running sum like `weightedColorBucket`'s
`if (scaled < …)` chain. Per rare tier `c ∈ {3,4,5,6,7}` with `w5 = {3:1, 4:2, 5:3, 6:4, 7:5}`:
`width15360[c] = base[c]·60 · (50000 + (multBps − 10000)·w5[c]) / 50000`; `rare = Σ width15360[c]`;
`rem = 15360 − rare`; the three commons each get `rem / 3`, and **color 0 additionally absorbs `rem mod 3`**.
Gold lands exactly on `width15360[7] = 2·60·M = 120·M` (exactly `baseline×M`). A draw scaled into `[0, 15360)`
walks the cutoff chain in fixed order and returns the first tier under its cumulative cutoff — identical
control flow to `weightedColorBucket`.

**A.1.5 Validity (V1: exhaustive).** Over the 40,001-point integer grid `multBps ∈ [20000, 60000]`: the
ladder sums to **exactly 15360** with **all 8 widths ≥ 0**, gold `= 120·M` — 0 sum-mismatches, 0 negative
widths; robust off-grid (the residual-to-first-common rule keeps the sum exact at every continuous `multBps`).
PMF non-negativity: redistributed mass `Δ(M) = (M−1)·24.4/256`; valid up to the true common-zero-crossing
**M ≈ 8.8689** — well beyond the locked `[2,6]` range. At M=6 (top of range, NOT the zero-crossing):
`Δ = 122/256 < 192/256`, each common `= 9.1146% > 0`. Valid at every M ∈ [2, 6].

**A.1.6 Per-tier probability (RESEARCH §A verbatim; V1: all fractions reproduce exactly).**

| color        | M=2.0      | M=2.5      | M=5.0      | M=6.0      |
| ------------ | ---------- | ---------- | ---------- | ---------- |
| 0/1/2 (each) | 21.8229%   | 20.2344%   | 12.2917%   | 9.1146%    |
| 3            | 15.0000%   | 16.2500%   | 22.5000%   | 25.0000%   |
| 4            | 8.7500%    | 10.0000%   | 16.2500%   | 18.7500%   |
| 5            | 5.0000%    | 5.9375%    | 10.6250%   | 12.5000%   |
| 6            | 4.2188%    | 5.1562%    | 9.8438%    | 11.7188%   |
| **7 (gold)** | **1.5625%**| **1.9531%**| **3.9062%**| **4.6875%**|
| **Σ**        | **1.0000** | **1.0000** | **1.0000** | **1.0000** |

Gold `= 0.78125% × M` at every column (FOIL-05). M=2.5 is illustrative of the ~×2.5 tie point, NOT a pinned
breakpoint.

**A.1.7 Gold-odds-vs-10-tickets anchors (sanity, V1: PASS; unaffected by the taper weights).** Score 0 (×2):
`1 − (1 − 2/256·2)^16 = 22.27%` vs baseline `26.93%` (worse at the bottom). ~×2.485: `≈ 27.06%` (≈ tie,
`multBps ≈ 24,854`). Max (×6): `53.61%` (~2× baseline).

### A.2 `foilBoostBps(score)` activity curve (RARE-02 / RARE-03 / FOIL-05)

A 4-anchor / 3-segment piecewise-linear bps curve `foilBoostBps(uint256 score) internal pure returns
(uint256)`, **added to `ActivityCurveLib`**, modeled on `decMultBps` / `centuryBps` (`ActivityCurveLib.sol:42-61`,
`:74-90`). `10000 = 1.0×`; range locked **[20000, 60000] = [×2.0, ×6.0]**. **Reuses the two existing shared
knees** — `ACTIVITY_SEG_B_KNEE_POINTS = 500` (`:26`), `ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000` (`:29`) — so it
carries the identical shape signature as the two existing curves (RARE-02, D-02).

**A.2.1 The 5 constants to add** (mirroring the `MULT_*` / `CENTURY_*` blocks):

| constant         | value      | meaning                                                                |
| ---------------- | ---------- | ---------------------------------------------------------------------- |
| `FOIL_MIN_BPS`   | `20_000`   | ×2.0 @ score 0 (floor)                                                 |
| `FOIL_K_POINTS`  | `300`      | seg-A knee (inside the established 235/305 K band)                     |
| `FOIL_VA_BPS`    | `50_000`   | ×5.0 @ K (75% of the gain)                                             |
| `FOIL_VB_BPS`    | `55_000`   | ×5.5 @ `ACTIVITY_SEG_B_KNEE_POINTS = 500` (87.5% of gain)             |
| `FOIL_MAX_BPS`   | `60_000`   | ×6.0 @ `ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000` (saturates flat)       |

Total gain `40_000` bps. Anchors: `MIN→VA` over `[0, K]` (steep early ramp), `VA→VB` over `[K, 500]` (shallow
middle), `VB→MAX` over `[500, 30000]` (long near-flat crawl), flat at `MAX` beyond.

**A.2.2 The 4 segment closed forms** (integer floor division; explicit endpoint guards → no rounding at
endpoints): `score == 0 ⇒ 20000`; seg A `0 < score ≤ 300`: `20000 + 100·score`; seg B `300 < score ≤ 500`:
`50000 + 25·(score − 300)`; seg C `500 < score < 30000`: `55000 + (score − 500)·5000/29500`;
`score ≥ 30000 ⇒ 60000`. The interpolation form is `decMultBps`-identical:
`V_lo + (score − knee_lo)·(V_hi − V_lo)/(knee_hi − knee_lo)`, the two guards short-circuiting before interp.

**A.2.3 Value table** (exact, integer-floor; V1: all reproduce):

| score        | bps    | multiplier | segment                          |
| ------------ | ------ | ---------- | -------------------------------- |
| 0            | 20000  | ×2.0000    | floor (guard)                    |
| 50           | 25000  | ×2.5000    | A — the ~×2.5 tie anchor         |
| 100          | 30000  | ×3.0000    | A                                |
| 300 (K)      | 50000  | ×5.0000    | A→B knee                         |
| 350          | 51250  | ×5.1250    | B — ILLUSTRATIVE, NOT pinned     |
| 500          | 55000  | ×5.5000    | B knee                           |
| 5000         | 55762  | ×5.5762    | C                                |
| 30000 (max)  | 60000  | ×6.0000    | cap (guard)                      |

`350 → 51250` honors "~×5 @ 350" **BY SHAPE only** — ×5.0 lands at `K = 300`; pinned boundaries are
`{0, 300, 500, 30000}`. **350 is NOT a pinned breakpoint** (D-02, user-confirmed).

**A.2.4 Frozen-at-buy / apply-at-resolve / never-live-read (RARE-03).** At `buyFoilPack`,
`score = _playerActivityScore(buyer, …)` is read ONCE from the **same `cachedScore` source the mint path
freezes** (`DegenerusGameMintModule.sol:1709`; whole-point score). `multBps =
uint16(ActivityCurveLib.foilBoostBps(score))` (range `20000..60000`) is stored into `foilRecord` as the
frozen 16-bit field. The jackpot resolve path and the match re-derivation read the frozen `multBps` from the
record — they do NOT re-read the activity score. The `/15360` ladder of A.1.4 consumes exactly this frozen
value. **RARE-03.**

**A.2.5 Invariants (V1: exhaustive over `[0, 30001]` + saturation tail).** Bounds (never < ×2, never > ×6);
monotone non-decreasing at every adjacent integer (0 violations); saturation (exactly 60000 for every
`score ≥ 30000`; tested 30000/30001/50000/1e9); endpoints exact via guards; ~×2.5 tie:
`foilBoostBps(50) = 25000` exactly.

---

## §D — Storage Layout (`foilRecord` + folded cap + `foilMatchClaimed`)

> Build-ready storage. Every layout choice is the RESEARCH §D reconciled-and-corrected form (V3 PASS, the E.6
> 168-bit superset). Three storage items append at the tail of `DegenerusGameStorage`: ONE packed `foilRecord`
> slot per player, the folded per-raw-level cap (no separate slot), and the sparse `foilMatchClaimed` marker.
> No existing slot moves (SEC-04).

### D.0 Grounded baseline facts (V3: all PASS)

| Fact | Source | Value |
| --- | --- | --- |
| Canonical game level type | `DegenerusGameStorage.sol:236` | `uint24 public level = 0` (≤ 16,777,215) |
| Whale-pass deferred grant (**already exists**) | `whalePassClaims:1122` | `mapping(address => uint256)` — do NOT re-declare |
| Century level-stamp idiom (template) | `centuryBonusUsed:1857-1876` | `(level << 224) \| payload`; `_centuryUsedFor` returns payload ONLY when `(packed >> 224) == level`, else `0` (auto-reset) |
| Retained daily RNG (claim re-derivation source) | `rngWordByDay:462` | `mapping(uint24 => uint256)` — claim re-derives from this, no draw-time scan |
| `TICKET_SCALE` | `:157, :663` | **100** (4 whole foil tickets = `quantityScaled = 400`) |
| Append point (next free slot) | `:2393` | `mapping(uint48 => address[]) internal boxPlayers;` is the LAST state var; closing `}` at `:2394`. New state appends after `:2393`, before `:2394`. |

A foil signature carries 4 quadrants × the full 6-bit `[CCC][SSS]` (color AND symbol — MATCH-03: color-only
does NOT count), packed `uint32` in the **identical `[QQ][CCC][SSS]`-per-byte layout** as
`packedTraitsFromSeed` / `packedTraitsFoil` (direct byte compare).

### D.1 `foilRecord` — ONE packed slot per player (FOIL-01, MATCH-01, MATCH-02, SEC-03)

**LOCKED form:** one packed `uint256` per player — `mapping(address => uint256) internal foilRecord` appended
after `:2393` (before `:2394`), with an embedded level stamp (the century idiom), NOT a `level => player`
outer map. The record stores the **full packed `uint32` per ticket PLUS the frozen 16-bit `multBps`** — the
reconciled E.6 168-bit superset. Buy = ONE SSTORE; claim = ONE SLOAD.

**D.1.1 The packed 168-bit superset (the LOCKED bit layout):**

| field | width | bit range (LSB→MSB) | meaning |
| --- | --- | --- | --- |
| `sig0` | 32 bits | `[0-31]`    | ticket-0 packed `uint32` signature |
| `sig1` | 32 bits | `[32-63]`   | ticket-1 packed `uint32` signature |
| `sig2` | 32 bits | `[64-95]`   | ticket-2 packed `uint32` signature |
| `sig3` | 32 bits | `[96-127]`  | ticket-3 packed `uint32` signature |
| `multBps` | 16 bits | `[128-143]` | the frozen `foilBoostBps` output (`20000..60000`); RARE-03 |
| `rawLevel` stamp | 24 bits | `[144-167]` | the raw `uint24 level` (`:236`) at buy; doubles as the cap flag |
| reserved | 88 bits | `[168-255]` | unused, always `0` |

**Bit budget:** `4×32 + 16 + 24 = 168 ≤ 256`. One slot.

**D.1.2 E.6 superset adopted OVER the D.1 24-bit variant (V3 DEFECT D-α resolved).** The frozen `multBps` is
**REQUIRED** in the record by RARE-03 / MATCH-09: the jackpot resolve path consumes the frozen multiplier (the
`/15360` ladder, A.1.4) and the match re-derivation reads it back, so the multiplier must live in the slot
rather than be live-recomputed. Storing the full packed `uint32` per ticket (not a narrower match-only
signature) is the robust superset and matches the `packedTraitsFoil` output byte layout (direct byte compare).

**D.1.3 The five private-constant masks/shifts (no storage footprint)** — `private constant`, inlined like
`_CENTURY_USED_MASK:1864`, keyed to D.1.1:

| constant | value | role |
| --- | --- | --- |
| `_FOIL_SIG_MASK`    | `(uint256(1) << 32) - 1` | extract any one 32-bit packed signature |
| `_FOIL_MULT_SHIFT`  | `128`                    | shift to the `multBps` field |
| `_FOIL_MULT_MASK`   | `(uint256(1) << 16) - 1` | mask the 16-bit `multBps` |
| `_FOIL_STAMP_SHIFT` | `144`                    | shift to the 24-bit raw-level stamp |
| `_FOIL_STAMP_MASK`  | `(uint256(1) << 24) - 1` | mask the 24-bit stamp |

**D.1.4 `_foilRecordFor(player, lvl)` accessor (per-level auto-reset).** A `view` accessor
`_foilRecordFor(address player, uint256 lvl)` returns `(present, multBps, sigs[4])` for `player` at raw `lvl`,
or `(false, 0, [0,0,0,0])` when the stored stamp ≠ the queried raw level — the century auto-reset, identical
in spirit to `_centuryUsedFor` (`:1868-1871`): read `packed = foilRecord[player]` (one SLOAD); if
`((packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) != lvl` return absent; else unpack
`sigs[i] = uint32((packed >> (32·i)) & _FOIL_SIG_MASK)`,
`multBps = uint16((packed >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK)`, `present = true`.

**MATCH-01 (sigs frozen per `(player, level)`):** the four signatures and `multBps` are written once at buy,
stamped to the buy level, and never mutated until the player's NEXT foil buy. **MATCH-02 (whole-level
window):** eligibility is read **from the stamp, not a live `level` compare** — every day within the stamped
level stays eligible. One cold slot per player who ever bought, not one per player-per-level.

### D.2 Per-raw-level one-pack cap — folded into the stamp (FOIL-01; no separate slot)

Presence in `foilRecord` at the current raw level **is** the cap. `_foilBoughtThisLevel(player, lvl)` is a
`view` predicate returning **true iff `((foilRecord[player] >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) == lvl`**.
`buyFoilPack` reverts when `_foilBoughtThisLevel(msg.sender, level)` is true, then the record write stamps the
current `level`. A stale stamp reads "not bought" (a fresh allowance at the new level), exactly the century-flag
semantics. **Keyed on raw `uint24 level` (`:236`), NEVER `_activeTicketLevel()`.** Because sigs (low bits),
`multBps` (mid bits), and the cap (stamp, high bits) share **one slot**, there is no "bought-but-no-record"
or "record-but-no-cap" desync — written and read atomically.

### D.3 Sparse double-claim marker — `foilMatchClaimed` (MATCH-05; collision-free)

**LOCKED: `mapping(bytes32 => bool) internal foilMatchClaimed`** appended at the tail (the unified marker name —
**`foilMatchClaimed`, NOT `foilClaimed`**; V3 DEFECT E-γ). Each realized winning tuple is claimable **at most
once**.

**D.3.1 Key composition (five distinct positional `abi.encode` fields).**
**Key = `keccak256(abi.encode(player, uint256(level), uint256(day), uint256(drawKind),
uint256(ticketIndex)))`** — each 32-byte padded; no concatenation ambiguity, no field-boundary collision:

| field | type at encode | domain | role |
| --- | --- | --- | --- |
| `player`      | `address`         | the claimant      | isolates callers — a forged tuple cannot replay another player's claim |
| `level`       | `uint256(level)`  | raw `uint24`      | binds the marker to the record's stamp → no `L`/`L+1` replay |
| `day`         | `uint256(day)`    | the eligible day  | spans the whole-level window (MATCH-02) |
| `drawKind`    | `uint256(drawKind)` | `{0=main, 1=bonus}` | 2 draws/day; a ticket is claimed independently against each |
| `ticketIndex` | `uint256(ticketIndex)` | `{0..3}`     | 4 independent tickets per pack (MATCH-04) |

A single ticket is claimable independently against **main (drawKind 0)** and **bonus (drawKind 1)** of each
eligible day, but **never twice per draw**.

**D.3.2 Mark-before-payout (CEI).** `claimFoilMatch` **reverts if `foilMatchClaimed[key]` is already set**,
then pays the tier, then sets `foilMatchClaimed[key] = true` — **the marker is set BEFORE any external
transfer**, so a reentrant re-call sees the set marker and reverts. **Sparse** — only realized winning claims
write a slot; no draw-time scan, so `advanceGame` stays flat.

### D.4 MATCH-05 persist-per-level griefing-resistance (§5)

A record written at level *L* is **overwritten ONLY by the SAME player's next foil buy** (gated by `level++`).
It is **never touched by `advanceGame` or by another player**. A fast `level++` does **NOT** strand an
unclaimed match: the sigs + `multBps` + stamp `L` persist in the slot, and `claimFoilMatch` re-derives
eligibility from the stamp `L` and the retained `rngWordByDay[day]` (`:462`), so matches for days within *L*
stay claimable until the player's own NEXT foil buy. The whole-level window (MATCH-02) is read from the stamp,
not a live `level` compare. This is the §5 "records persist per-level" property.

The single-slot player-loss edge (a player's OWN re-buy at *L+1* overwrites their unclaimed *L* signatures) is
the one residual surface — **NOT** a griefing vector (no third party can trigger it) — surfaced for explicit
USER sign-off in **PIN 1** (§D.6).

### D.5 No-collision / no-reorder attestation (SEC-04, SEC-03)

- **Append-only at the tail.** Both new mappings (`foilRecord`, `foilMatchClaimed`) go **after `boxPlayers`
  (`:2393`), before the `:2394` closing brace**. No existing declaration moved/retyped/reordered/removed.
- **Constants consume no slots.** The five `_FOIL_*` masks/shifts are `private constant` (inlined, like
  `_CENTURY_USED_MASK:1864`); `_foilRecordFor` / `_foilBoughtThisLevel` are `internal` view helpers, no
  storage footprint.
- **Two new base mapping slots ONLY** take the next two slots after `boxPlayers`'s. All prior slot indices are
  unchanged → the layout goldens are byte-preserved (SEC-04, re-attested by the layout-golden re-pass at 448).
- **Storage lives ONLY in `DegenerusGameStorage`** (the delegatecall-shared base; SEC-03), never in the foil
  module or the facade.
- **`whalePassClaims` already exists at `:1122`** — do NOT re-declare; the 4-of-4 tier does
  `whalePassClaims[player] += 1` against the existing slot.
- **Net storage cost:** 2 new base mapping slots (`foilRecord` = 1 packed slot per player who ever bought,
  cap + sigs + `multBps` co-resident; `foilMatchClaimed` = 1 slot per realized winning claim, sparse).

### D.6 Pinned Layout Decisions (LOCKED)

> Mirroring the house SPEC-V61 "Locked Knobs" form. Two genuine SPEC decisions are pinned; the rest of §D is
> mechanically determined. PIN 1 carries a **USER-SIGN-OFF FLAG** surfaced in the §T USER-decisions callout.

**PIN 1 — `foilRecord` level-keying (LOCKED: single-slot `mapping(address => uint256)`).** The single-slot
form (the §5-compliant minimum), level stamp embedded in bits `[144-167]` (the century idiom). One cold slot
per player, auto-reset per level via the stamp. **Rationale:** one packed slot per player gives the per-level
auto-reset for free, keeps the cap + sigs + `multBps` co-resident (no desync), and is the minimal storage that
satisfies §5; a `level++` ALONE never strands a match (§D.4). **The precise edge (the LOCKED form's only loss
surface):** a player's **OWN re-buy at level *L+1* overwrites their unclaimed level-*L* signatures**. A level
advance ALONE never strands a match — only the player's own next foil buy does. No third party
(`advanceGame`, another player) can trigger this; not a griefing vector. The `foilMatchClaimed` key includes
`level` (§D.3.1), so *L* and *L+1* markers never collide even across the overwrite. **Documented alternative
(NOT chosen):** `mapping(uint24 level => mapping(address => uint256))` — keys the record by level then player,
so *L*'s unclaimed signatures **survive** an *L+1* re-buy; an additive widening (still appendable at the tail,
no existing slot moved) at the cost of **+1 storage slot per (level, player) that ever buys**. The single-slot
form is the §5-compliant minimum and is chosen. **Affected REQ-IDs:** FOIL-01, MATCH-01, MATCH-05.

**PIN 2 — exact packed bit-offset (LOCKED: stamp at `[144-167]`, payload at `[0-143]`).** `sig0..sig3` at
`[0-127]`, `multBps` at `[128-143]`, `rawLevel` stamp at `[144-167]`, `[168-255]` reserved `0`; with
`_FOIL_STAMP_SHIFT = 144`, `_FOIL_MULT_SHIFT = 128`. The self-stamp cap read is
`(packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK == lvl`. **Rationale:** the four 32-bit sigs and the 16-bit
`multBps` stay **contiguous in the low 144 bits** (a clean unpack loop), and the stamp is a high-field
self-stamp read identical in spirit to `centuryBonusUsed`'s `(packed >> 224) == level`. Total 168 bits ≤ 256,
one slot, one SSTORE / one SLOAD. **Documented alternative (NOT chosen):** the `centuryBonusUsed`-mirroring
form with the **stamp at bit 224** (mirroring `:1875`), `multBps` at `[128-143]`, sigs at `[0-127]` — also one
slot, ≤ 256 bits; the only difference is the stamp offset (224 vs 144). The `[144-167]` form is chosen so the
payload is contiguous in the low 144 bits. **Affected REQ-IDs:** SEC-03, SEC-04.

### D.7 Acceptance — IMPL can declare with zero further layout decision

An IMPL-446 author declares `foilRecord` (the packed `mapping(address => uint256)`, the D.1.1 168-bit layout),
`foilMatchClaimed` (the sparse `mapping(bytes32 => bool)`, the D.3.1 keccak key), the five `_FOIL_*`
masks/shifts, and the `_foilRecordFor` / `_foilBoughtThisLevel` accessors — appended after `:2393`, no
existing slot moved — with **ZERO further layout decision**, beyond confirming the two pins of §D.6 (PIN 2 is
locked outright; PIN 1 carries the one USER sign-off on the single-slot loss edge before the 446 IMPL gate).

---

## §E — Entrypoints + Match + Payout + Calibration + Placement

> Build-ready entrypoints. Every signature, ordered body, match predicate, payout lane, calibration figure,
> and module-placement call is the RESEARCH §E/§B/§F/§G reconciled-and-corrected form (V2/V3 PASS, with the §1
> corrected anchors). No fenced Solidity bodies; all identifiers are named in directive prose.

### E.1 `buyFoilPack()` — facade stub + module body (FOIL-02, FOIL-03, FOIL-04, MATCH-03 record write)

**Facade stub (thin, on `DegenerusGame`).** Pin **`function buyFoilPack() external payable`** — **no
parameters**. The pack is fully determined by `(msg.sender, level, msg.value)`: one fixed SKU (4 foil tickets)
at one fixed price for the current raw level. `payable` carries the fresh-ETH leg; a zero-value call is the
claimable-funded path. The stub follows the established thin-facade pattern — **template `buyPresaleBox` at
`DegenerusGame.sol:614-629`**: resolve the player, then
`GAME_FOILPACK_MODULE.delegatecall(abi.encodeWithSelector(...))`, then `_revertDelegate(data)` on failure. All
foil logic lives in the module; the facade carries no state and no branching.

**Module body `_buyFoilPack(address buyer, uint256 ethSent)` — IN ORDER:**

1. **Liveness / phase gate.** First statement: `if (_livenessTriggered()) revert E();` — the same guard
   `_queueTicketsScaled` enforces at `:649`. No foil buy after liveness.
2. **One-per-RAW-level cap (FOIL-01).** Load `uint24 lvl = level;` then revert when
   `_foilBoughtThisLevel(buyer, lvl)` (§D: the `foilRecord` stamp read; a stale stamp reads "not bought"). The
   stamp write happens in step 6, AFTER the price settles, so a reverting buy leaves no flag behind. Keyed on
   **raw `level`**, never `_activeTicketLevel()`.
3. **Price + payment classification (FOIL-02, FOIL-03).** Price is
   **`uint256 cost = 10 * PriceLookupLib.priceForLevel(lvl);`** — the 10× foil price (FOIL-02). Reuse the
   `_processMintPayment` accounting **shape** (`DegenerusGameMintModule.sol:236-299`) but **REJECT the afking
   leg** via the residual: `uint256 ethUsed = ethSent < cost ? ethSent : cost;` (overpay ignored);
   `uint256 remaining = cost - ethUsed;`; if `remaining != 0`:
   `uint256 claimable = _claimableOf(buyer); uint256 avail = claimable > 1 ? claimable - 1 : 0;
   if (remaining > avail) revert E();` — **this `revert E()` IS the afking-rejection guard.** The normal mint
   path silently taps afking principal at `:288`; the foil path requires the entire residual be covered by the
   claimable half and **rejects** any reliance on afking funds (FOIL-03, T-445-E3). **Storage write:**
   `_debitClaimable(buyer, remaining);` then a separate `claimablePool -= uint128(remaining);` statement.
   `_debitClaimable` (`:941`) touches **only the claimable half — never `_debitAfking` (`:956`)**.
4. **Pool split — fork to 75 / 25 (FOIL-04).** The foil leg routes **75% next / 25% future** (inverse of the
   normal 90/10 ticket split). Introduce the NEW constant **`FOIL_TO_FUTURE_BPS = 2500`** — **NOT** the shared
   `PURCHASE_TO_FUTURE_BPS = 1000`: `uint256 prizeContribution = cost; uint256 futureShare =
   (prizeContribution * FOIL_TO_FUTURE_BPS) / 10_000; uint256 nextShare = prizeContribution - futureShare;`.
   **Storage write** through the frozen/unfrozen branch of `_recordMintPayment`
   (`DegenerusGameMintModule.sol:201-217`) **verbatim**: `prizePoolFrozen` ⇒ `_setPendingPools(...)`, else
   `_setPrizePools(...)`. **Only the bps constant is forked; the routing branch is reused unchanged.**
5. **Boost freeze (RARE-03).** `score = _playerActivityScore(buyer, ...)` — the **same source the mint path
   freezes as `cachedScore`** (`DegenerusGameMintModule.sol:1709`; def `DegenerusGameMintStreakUtils.sol:267`,
   whole points). `uint16 multBps = uint16(ActivityCurveLib.foilBoostBps(score));` (range `20000..60000`,
   §A.2). **Frozen into `foilRecord` at step 6, NEVER live-read at resolve** (RARE-03).
6. **Roll 4 foil signatures + write the record (MATCH-01, RARE-01/04).** The rarity boost is applied **HERE,
   at buy**, against the sibling producer: `uint256 seed = uint256(keccak256(abi.encode(buyer, lvl,
   FOIL_SEED_TAG)));` — a **deterministic, frozen seed** (`FOIL_SEED_TAG` a new domain constant). **No live RNG
   at buy.** For `i in 0..3`: `uint32 sig_i = DegenerusTraitUtils.packedTraitsFoil(uint256(keccak256(abi.encode(
   seed, i))), multBps);` (the §A sibling; tapered color, symbol uniform 1/8). **Storage write:**
   `foilRecord[buyer] = pack(stamp = lvl, multBps, sig0..3);` — a **single SSTORE** in the §D layout. This one
   slot is **both** the per-RAW-level cap flag (step 2 reads its stamp) **and** the frozen signature/boost
   record (claim reads its sigs + `multBps`).
7. **Enter the 4 tickets into the REGULAR jackpot (FOIL-05).** Queue at the active ticket level so the foil
   tickets share `traitBurnTicket[level][traitId]` eligibility (`:442`):
   **`_queueTicketsScaled(buyer, _activeTicketLevel(), 400, false);`**. **CORRECTION (V3 DEFECT E-α,
   off-by-scale):** the third argument is `quantityScaled` in **`TICKET_SCALE = 100`** units (`:157, :663`), so
   4 whole foil tickets require **`400` (= 4 × 100)`, NOT `4`** — `4` would queue 0.04 of a ticket. This
   corrected `400` is the load-bearing pin. **External effects:** emits `TicketsQueuedScaled`; pushes
   `ticketQueue[wk]`; writes `ticketsOwedPacked[wk][buyer]`. **Trait-resolution note for IMPL** (mechanism is a
   446 detail; the producer is pinned here): the queue-resolution path that today calls `packedTraitsFromSeed`
   (heavy-tail) MUST, for foil-owed entries, resolve via `packedTraitsFoil(seed, multBps)` so the on-chain
   jackpot traits carry the boosted gold odds (real `color == 7`). The frozen `multBps` is the input; the
   v70-frozen producers are NOT edited (foil entries route to the sibling). Whether IMPL uses a parallel
   foil-owed queue or a per-entry boost tag is a 446 choice; the SPEC fixes producer = `packedTraitsFoil` and
   multiplier = the frozen `multBps`.
8. **No FLIP / WWXRP / whale-pass mint at buy.** `buyFoilPack` is pure cost-in; all rewards flow only through
   `claimFoilMatch`. **External calls in `buyFoilPack`: none beyond the facade→module delegatecall.**

### E.2 `claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind)` — pull/claim (MATCH-03)

**Signature.** Pin **`function claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind) external`**,
keyed per `(day, drawKind, ticketIndex)` with `drawKind ∈ {0 = main, 1 = bonus}` taken **explicitly** (no
internal loop). 2 draws × 4 tickets ⇒ 8 independent claimables/day; the sparse `foilMatchClaimed` marker is
1:1 with each claim. (A multi-claim batcher is an additive, out-of-scope nicety.)

**Module body — IN ORDER:**

1. **Bounds + record load.** `require(ticketIndex < 4); require(drawKind < 2);` Resolve `recLevel` and load
   `(bool present, uint16 multBps, uint32[4] sigs) = _foilRecordFor(msg.sender, recLevel);` then
   `require(present);`. Records persist per-level (MATCH-05); a fast `level++` cannot grief — the record is not
   auto-wiped until the SAME player re-buys, itself gated by E.1 step 2.
2. **Eligibility window (MATCH-02).** `require(day` falls within `recLevel`'s draw-day span`)`. Claimable
   across the WHOLE level; the window is read from the stamp, never a live `level` compare.
3. **RNG availability.** `uint256 rw = rngWordByDay[uint24(day)]; require(rw != 0);` (`:462`; the retained
   daily VRF — the re-derivation source, never live-read elsewhere).
4. **Double-claim guard (MATCH-05) — set BEFORE payout (CEI).** Compute the unified marker
   **`bytes32 mk = keccak256(abi.encode(msg.sender, recLevel, day, drawKind, ticketIndex));`** then
   `require(!foilMatchClaimed[mk]); foilMatchClaimed[mk] = true;`. **Use the unified name `foilMatchClaimed`
   (NOT `foilClaimed`)** — V3 DEFECT E-γ. Written before any payout effect (CEI).
5. **Re-derive the day's winning sets (E.3).** Build the LIVE (hero-overridden) set and the HERO-FREE pure-VRF
   set for the requested `drawKind`.
6. **Count positional matches (MATCH-03).** Quadrant `q` matches **iff `foilQuad_q == winQuad_q` as the full
   6-bit `[CCC][SSS]`** — color AND symbol. **Color-only does NOT count; a wrong-quadrant match does NOT count**
   (both sides carry `[QQ]`). Compute `liveCount` (vs LIVE) and `heroFreeCount` (vs HERO-FREE).
7. **Tier resolution (MATCH-09 — steer-proof gate; E.3).** Gated on `heroFreeCount` for the 4-of-4 tier.
   `if (tier == 0) revert E();`.
8. **Pay the tier (E.5)** via the isolated foil schedule; for the 4-of-4 tier also
   `whalePassClaims[msg.sender] += 1;` (`:1122`, the EXISTING slot — do NOT re-declare).

REQ tags locked here: **FOIL-02** (10× price), **FOIL-03** (afking-rejection guard), **FOIL-04**
(`FOIL_TO_FUTURE_BPS = 2500`, the 75/25 fork), **MATCH-03** (full 6-bit positional count, color-only excluded).

### E.3 The crux — winning-set re-derivation (LIVE vs HERO-FREE) (MATCH-09, SEC-01 basis)

**Producer substrate — `getRandomTraits`, flat uniform 6-bit slice.** The daily winning set is produced by
**`JackpotBucketLib.getRandomTraits(uint256 rw)` (`JackpotBucketLib.sol:281-286`)** — a flat uniform 6-bit
slice per quadrant: each quadrant is `(rw >> 6q) & 0x3F` with quadrant bits OR'd in, packed `[QQ][CCC][SSS]`.
**Both color (high 3 bits) and symbol (low 3 bits) are uniform `1/8`.** The winning set does **NOT** apply
`weightedColorBucket` (heavy-tail) nor `_degTrait` (degenerette) — it is a third, pure-uniform model on all 6
bits.

**Consequence — the foil rarity boost CANCELS in the match channel.** Per-quadrant exact `[color | symbol]`
match probability is `(1/8 color) × (1/8 symbol) ≈ 1/64 ≈ 1.5625%`, **independent of `multBps`**: the boosted
color distribution sums to 1 against a flat `1/8` winning-color weight, so the boost factors out. The boost
changes the tickets' own jackpot-gold participation (§A) but **does NOT change match-lottery odds**
(MATCH-10 / §E.7 — `q = 1/64` for all M).

**Per-`drawKind` base word** (mirroring `_rollWinningTraits` `:1760-1769`):
`r = (drawKind == 1) ? EntropyLib.hash2(rw, uint256(BONUS_TRAITS_TAG)) : rw;`. Main uses `rw`; bonus uses the
keccak-domain-separated `hash2(rw, BONUS_TRAITS_TAG)` → independent base traits and hero colors (two
i.i.d.-distributed winning sets/day, correlated only through the shared hero symbol).

**The two re-derived sets:**

1. **HERO-FREE pure-VRF set — NO `_applyHeroResult`:** `uint8[4] heroFreeW =
   JackpotBucketLib.getRandomTraits(r);` then `uint32 heroFreeSet = JackpotBucketLib.packWinningTraits(
   heroFreeW);`. The un-steerable substrate; `heroFreeW[heroQuadrant]` still holds the VRF symbol, never the
   steered one.
2. **LIVE (hero-overridden) set — HERO-FREE with `_applyHeroResult`:** `(bool hasHero, uint8 hQ, uint8 hSym) =
   _rollHeroSymbol(dailyIdxFor(day), rw);` (hero entropy is the unsalted day word `rw`, `:1768`), then start
   from a copy `uint8[4] liveW = heroFreeW;` and apply `_applyHeroResult(liveW, r, hasHero, hQ, hSym);`
   (`DegenerusGameJackpotModule.sol:1316-1341`). The override rewrites **ONLY `liveW[heroQuadrant]`** — color
   re-sampled from `r`'s low bits, symbol set to the steered `heroSymbol`. **Every non-hero quadrant byte is
   identical to HERO-FREE.** Pack `uint32 liveSet = JackpotBucketLib.packWinningTraits(liveW);`. When
   `total == 0` (no wagers), `_applyHeroResult` is a no-op and LIVE collapses to HERO-FREE.

**CRITICAL IMPL anchor — read `dailyHeroWagers[day-1]`.** `_rollHeroSymbol` reads `dailyHeroWagers[dailyIdx]`
where **`dailyIdx == day - 1`** — the prior-day wager pool, because the index is frozen at the previous day's
slot when the jackpot is processed (verified `DegenerusGameJackpotModule.sol:1290-1291`, set at AdvanceModule).
**Therefore `claimFoilMatch(D)` MUST read `dailyHeroWagers[D-1]`.** The pool is retained storage (`:1841`), so
the hero `(quadrant, symbol)` is **fully reconstructible** at claim. Pin `dailyIdxFor(day) == day - 1`.

**Main vs bonus — shared hero symbol.** `_rollWinningTraitsPair` (`:1778-1795`) forces the **same hero
`(quadrant, symbol)`** onto both main and bonus via ONE `_rollHeroSymbol(dailyIdx, randWord)`; only the base
word `r` differs and the hero *color* is re-sampled per roll. The re-derivation reuses the same `(hQ, hSym)`
for both `drawKind` values of a given day.

**Tier gate (MATCH-09 — steer-proof):**

| Tier | Condition | Channel |
| --- | --- | --- |
| 2-of-4 | `liveCount == 2` | LIVE (bounded hero edge KEPT) |
| 3-of-4 | `liveCount == 3` | LIVE (bounded hero edge KEPT) |
| 4-of-4 | **`heroFreeCount == 4` ONLY** | HERO-FREE pure-VRF (steer-proof) |
| none | else | `tier == 0 ⇒ revert E();` |

- 2-of-4 / 3-of-4 are taken off `liveCount` — the bounded hero edge is intentionally KEPT (a steered hero can
  carry one quadrant on LIVE).
- 4-of-4 is gated ONLY on `heroFreeCount == 4` — a steered hero shifts at most **one** quadrant's symbol on
  LIVE, so a steerer reaches at most **3-of-4** on LIVE and **never** `heroFreeCount == 4`.
- **Edge case:** if `liveCount == 4` arises only via the hero override but `heroFreeCount == 3`, the claim pays
  the **3-of-4** tier — the 4-of-4 gate is `heroFreeCount`, never `liveCount`.

**SEC-01 consequence (design basis).** A steerer controls only the `heroSymbol` of `liveW[hQ]` — one quadrant's
symbol on the LIVE set; `heroFreeCount` is computed on pure VRF (untouchable). Maximum steered contribution is
`+1` to `liveCount`. The 4-of-4 whale-pass moonshot (gated on `heroFreeCount == 4`) is un-steerable and
non-stackable (T-445-E1). This is the **SEC-01 design basis**, attested downstream at phase 448. REQ tags:
**MATCH-09**, **SEC-01** (design basis).

### E.5 Isolated payout lanes (MATCH-04, MATCH-06, MATCH-07, MATCH-08, SEC-02 basis)

**(A) Isolated tier→faces schedule — MUST NOT route through Degenerette `quickPlay`.** The foil claim **owns
its own tier→faces table.** It **MUST NOT** route through the EV-flat Degenerette `quickPlay` tables — those
become **+EV under boosted foil gold** and would break the calibration. **`1 face = 1,000 FLIP =
priceForLevel(recLevel) ETH`** (fixed FLIP peg; ETH-per-face floats with level).

| Tier | Faces | Extra |
| --- | --- | --- |
| 2-of-4 | **5 faces** | — |
| 3-of-4 | **65 faces** | — |
| 4-of-4 | bonus spin (~1,000 faces) | **`whalePassClaims[player] += 1`** (the EXISTING `:1122` slot) |

The 4-of-4 tier grants a half whale pass via `whalePassClaims[msg.sender] += 1;` (`:1122`, pool-neutral
deferred grant, settled later via `DegenerusGameWhaleModule.sol:991-995`) **PLUS** a bonus spin. **No ETH
leaves at claim for the pass leg** (MATCH-07). These base values are the locked D-05 calibration target (§E.7
confirms ≈2 faces/pack/30d) (MATCH-04).

**(B) Disjoint entropy lanes off `rw` (MATCH-08).** Three separate keccak domains, independent of each other
AND of the match lane (which consumes `getRandomTraits(r)` bit-slices + the `_rollHeroSymbol` keccak in E.3):
`magnitudeLane = uint256(keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_MAG_TAG)))`;
`currencyLane = uint256(keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_CCY_TAG)))`. Per-tuple
salting (the `(day, drawKind, ticketIndex)` fields) independently rolls each of the 8 daily claim-units.
**`FOIL_MAG_TAG ≠ FOIL_CCY_TAG ≠ BONUS_TRAITS_TAG ≠ FLIP_JACKPOT_TAG`** — distinct keccak domains ⇒ provably
disjoint lanes (T-445-E4). Derived from the retained `rw` at claim, **never live-read**. Magnitude-first /
currency-second reveal is **UI-only** ordering; both fixed atomically on-chain.

**(C) Currency split — 40 / 40 / 20 (FLIP / ETH / WWXRP), every spin, all tiers (MATCH-06).**
`uint256 c = currencyLane % 100;` ⇒ `c < 40` FLIP `[0,40)`; `c < 80` ETH `[40,80)`; else WWXRP `[80,100)`.
Magnitude `faces = baseFacesForTier`; FLIP / WWXRP `= faces * 1000e18`; ETH `= faces * priceForLevel(recLevel)`.

- **FLIP (40%)** — `coin.mintForGame(msg.sender, flipAmount)` (`IDegenerusCoin.sol:20`). **Free mint, no
  solvency impact.**
- **WWXRP (20%)** — `wwxrp.mintPrize(msg.sender, wwxrpAmount)` (`WrappedWrappedXRP.sol:229`). **Free mint, no
  solvency impact.**
- **ETH (40%)** — the EXISTING capped-spin path: clamp `ethShare` to **`ETH_WIN_CAP_BPS = 1000`** (10% of
  `futurePrizePool`); over-cap spills to the lootbox; credit the capped ETH via
  `_creditClaimable(msg.sender, cappedEth)` (`:933`) and decrement `runningFuture` / `pendingFuture` exactly as
  `:884-903`. **CLONE SOURCE — the corrected anchor (V3 DEFECT F-β):**
  **`DegenerusGameDegeneretteModule.sol:877-915`** (`maxEth` `:889`, lootbox-resolve `:915`) — **NOT** the
  previously-stated `:402-446`. Writes: prize-pool decrement + `balancesPacked[msg.sender]` claimable-half +
  `claimablePool`; external call: a possible lootbox-resolve delegatecall on the cap spill.

**SEC-02 basis (design).** `ethShare ≤ 10% · futurePrizePool` (the `ETH_WIN_CAP_BPS = 1000` clamp + lootbox
spill); FLIP and WWXRP are **mints** (no pool draw); the whale pass is **pool-neutral**. Structurally solvent
(T-445-E2). The **SEC-02 design basis**, attested downstream at phase 448. **All payout effects come AFTER
`foilMatchClaimed[mk] = true` (CEI).** External calls in `claimFoilMatch`: at most one of
`{coin.mintForGame, wwxrp.mintPrize}` plus, on the ETH lane, the claimable credit and a possible
lootbox-resolve delegatecall on the cap spill — all after the marker write.

### E.7 Calibration confirm (MATCH-10, D-05)

All figures are **closed-form exact binomials** — Monte-Carlo unnecessary because the per-quadrant match
probability collapses to the constant `q = 1/64` (the uniform winning color cancels the foil boost; E.3). V2
independently reproduced every figure to full precision.

- **Per-quadrant match `q = 1/64 ≈ 1.5625%`, M-invariant** (flat across all `multBps`).
- Per ticket-draw, `k ~ Binomial(4, q = 1/64)`: `P(2-of-4) = 0.00141943`; `P(3-of-4) = 0.00001502`;
  `P(4-of-4) = 5.960e-08`.
- `E[faces/draw] = 5·P(2-of-4) + 65·P(3-of-4) = 0.0080736`.
- **`E[faces/pack/30d] = 240 · 0.0080736 = 1.9376`** over 240 ticket-draws (4 tickets × 2 draws/day × 30 days),
  **FLAT across all scores** (M-invariant — no "calibrate-at-which-score" decision).
- **Tier split 87.9% / 12.1%** (2-of-4 / 3-of-4) — the build-time comment should cite **87.9%**, NOT the spec's
  illustrative ~85%.
- **Gold-odds crossover at M ≈ 2.4854** (`multBps ≈ 24,854`) — ties 10 normal tickets at roughly score ~30–50.
- **4-of-4 ≈ 1-in-69,906 per pack** (gated HERO-FREE; EV-negligible ~0.0014%/pack, steer-proof).

**D-05 policy verdict — CONFIRM and REPORT, no recalibration.** The realized **1.94 faces/pack/30d** lands on
the D-05 ~2-face target (**3.1% low**) → **NOT materially off → no recalibration flag**. The payout table stays
**LOCKED**. Because the per-quadrant match collapses to a constant, the §E.7 figures are **closed-form exact** —
a Monte-Carlo is optional confirmation, not a gating recompute. **Per D-05: if phase 447's empirical run lands
materially off ≈2, flag it to the USER — never silently retune the locked table.** (Reporting notes,
non-blocking: tier split 87.9%/12.1% vs the illustrative ~85%/~12%; 4-of-4 per-pack rarity ≈1-in-69,906 vs the
spec's illustrative ≈1-in-300k which folds a narrower per-level window — documentation footnotes, no number
changed.)

### F. Module placement + EIP-170 (SEC-03, D-04)

**F.1 Recommendation — a NEW `GAME_FOILPACK_MODULE`** (mirrors the existing 12-module delegatecall dispatch),
**NOT** an existing module. **D-04 is the engineering EIP-170 call** — the measured live headroom drives it.
Estimated foil body **≈8–11 KB deployed** (buyFoilPack ~2.5–3.5 KB + claimFoilMatch ~2.5–3.5 KB + the isolated
spin payout ~3–4 KB; the library pieces `traitFromWordFoil` / `packedTraitsFoil` / `foilBoostBps` are
`internal pure` and inline, ~0.6–1.1 KB). An ~8–11 KB body does not fit any single roomy live module with
comfortable margin plus the re-audit / slither / layout-golden re-pass cost. **`MintModule` is excluded** —
SEC-03 excludes it AND it is physically near-full (~1,116 B free of 23,460 B). The very-roomy Bingo / Boon /
GameOver modules could absorb it physically but would couple an unrelated payable purchase + lottery feature
into unrelated bodies. A fresh `GAME_FOILPACK_MODULE` starts at 0 → ~8–11 KB lands inside 24,576 B with
**~13.5–16.5 KB headroom**. No EIP-170 risk.

**F.2 Facade stubs + the constant.** Two thin facade stubs on `DegenerusGame`: `payable buyFoilPack()` +
`claimFoilMatch(day, ticketIndex, drawKind)`. Each ~250–450 B; two ≈ 0.5–0.9 KB against the facade's measured
**4,188 B free** → the facade lands at ~3.3–3.7 KB free. **One new constant** `address internal constant
GAME_FOILPACK_MODULE = …;` in `ContractAddresses.sol` (alongside the existing 12 `GAME_*_MODULE` at `:13-35`).

**F.3 Storage placement (SEC-03).** New storage appends in `DegenerusGameStorage` ONLY (the shared base), never
in the foil module or facade — `foilRecord` + `foilMatchClaimed` tail-appended after `boxPlayers` (`:2393`), no
slot moves (SEC-04, §D).

**F.4 Re-measure-at-IMPL caveat (HARD-REQ §6.7).** All §F sizes are measured on the **current** artifacts (no
foil code yet). The real `GAME_FOILPACK_MODULE` body and the facade-after-stubs size **MUST be re-measured on
the post-IMPL build** (HARD-REQ §6.7). Estimated body 8–11 KB; estimated headroom 13.5–16.5 KB — to be
confirmed at 446/449.

REQ tags across E.5 / E.7 / F: **MATCH-04**, **MATCH-06**, **MATCH-07**, **MATCH-08**, **MATCH-10**, **SEC-02**
(design basis), **SEC-03**.

---

## R. REQ-Coverage Map (all 20 phase-445 REQ-IDs)

> Every one of the 20 phase-445 REQ-IDs (FOIL-01..05, RARE-01..04, MATCH-01..10, SEC-03), with its locking
> section and the phase that attests it. SEC-01 / SEC-02 / SEC-04 have their **design basis** locked here but
> are **ATTESTED downstream** at 447/448/449 (the audit-milestone pattern).

| REQ-ID | Requirement (one line) | Locking section | Attested |
| --- | --- | --- | --- |
| **FOIL-01** | ≤1 foil pack/account/raw-level (level-stamped cap, auto-reset) | §D.1.4 / §D.2 / §E.1 step 2 | 446 |
| **FOIL-02** | pack costs `10 × priceForLevel(level)`, delivers 4 tickets | §E.1 step 3 | 446 |
| **FOIL-03** | payable fresh-ETH or claimable; afking leg REJECTED | §E.1 step 3 (the `revert E()` guard) | 446 |
| **FOIL-04** | foil spend routes 75% next / 25% future (`FOIL_TO_FUTURE_BPS = 2500`) | §E.1 step 4 | 446 |
| **FOIL-05** | foil tickets enter the regular jackpot; boosted traits write real gold | §A.1 / §E.1 step 7 | 446 |
| **RARE-01** | NEW sibling producer; v70-frozen producers NOT modified | §A.1.1 | 446 |
| **RARE-02** | multiplier scales with score ×2→~×5→×6 via `foilBoostBps` | §A.2 | 446 |
| **RARE-03** | multiplier frozen at buy, applied at resolve, never live-read | §A.2.4 / §D.1.2 / §E.1 step 5 | 446 |
| **RARE-04** | all rarer tiers lifted (tapered); ×6 ⇒ gold ≈ 4.7%/quadrant | §A.1.3 / §A.1.6 | 446 |
| **MATCH-01** | each pack's 4 sigs frozen at buy, stored per `(player, level)` | §D.1.4 / §E.1 step 6 | 446 |
| **MATCH-02** | each ticket eligible the whole level vs both daily sets | §D.1.4 / §E.2 step 2 | 446 |
| **MATCH-03** | re-derive from `rngWordByDay[day]`, exact positional count, 2/3/4 tier | §E.2 step 6 / §E.3 | 446 |
| **MATCH-04** | isolated payout table; never routes through Degenerette per-N | §E.5 (A) | 446 |
| **MATCH-05** | pull/claim only; ≤1 claim/tuple; records persist per-level | §D.3 / §D.4 | 446 |
| **MATCH-06** | 2/3 tiers pay one spin split 40 FLIP / 40 ETH / 20 WWXRP | §E.5 (C) | 446 |
| **MATCH-07** | 4-of-4 grants half whale pass + a 40/40/20 bonus spin | §E.5 (A) | 446 |
| **MATCH-08** | magnitude + currency from `rngWordByDay[day]` (disjoint lanes); reveal UI-only | §E.5 (B) | 446 |
| **MATCH-09** | 2/3 vs LIVE (bounded hero edge KEPT); 4-of-4 vs HERO-FREE (steer-proof) | §E.3 | 446 |
| **MATCH-10** | currency ladder calibrated to ≈2 faces/pack/30d | §E.7 (≈1.9376) | **447 TST** |
| **SEC-03** | new code fits EIP-170 (new `GAME_FOILPACK_MODULE`, not `MintModule`; storage in base) | §F / §D.5 | 446 |

**Design-basis-here / attested-downstream (NOT in the phase-445 set but locked here):**

| REQ-ID | Design basis (locked here) | Attested |
| --- | --- | --- |
| **SEC-01** | 4-of-4 steer-proof (gated `heroFreeCount == 4`; steered hero ≤ 3-of-4) | §E.3 | **448 REAUDIT** |
| **SEC-02** | no solvency hole (ETH ≤10% cap + spill; FLIP/WWXRP mints; pass pool-neutral) | §E.5 (SEC-02 basis) | **448 REAUDIT** |
| **SEC-04** | full forge green; layout goldens / RNG-freeze re-pass on the foil subject | §D.5 (append-only/no-slot-move) | **448 / 449** |

---

## H. §6 Hard-Floor Map (the 8 FINAL-SPEC §6 floor items → SPEC section + attest phase)

> Each of the 8 `V71-FOILPACK-FINAL-SPEC.md` §6 floor items mapped to the SPEC section(s) that satisfy it and
> the phase that attests it. Every change in the 446 diff sits above this floor.

| # | §6 floor item | Satisfied by (SPEC section) | Attested at |
| --- | --- | --- | --- |
| 6.1 | No exploit / no farm beyond the bounded §4 hero edge; 4-of-4 moonshot steer-proof | §E.3 (steer-proof gate; ≤ 3-of-4 via steer) | **448** (SEC-01) |
| 6.2 | No solvency hole — ETH ≤ 10%-pool cap; FLIP/WWXRP mints; whale pass pool-neutral | §E.5 (C) + SEC-02 basis | **448** (SEC-02) |
| 6.3 | Isolated match payout table — no coupling to the EV-flat Degenerette per-N tables | §E.5 (A) | **447 / 448** |
| 6.4 | Frozen shared trait producers untouched; foil uses a NEW sibling producer | §A.1.1 (RARE-01) | **448** (SEC-04 layout/golden) |
| 6.5 | Buy-time freeze of score(→boost) + ticket signatures; claim re-derives from retained RNG — never live-read | §A.2.4 + §E.1 steps 5–6 + §E.2 step 3 / §E.3 | **448** (RNG-freeze re-attest) |
| 6.6 | Pull/claim only — no draw-time scan; `advanceGame` gas stays flat | §D.3.2 (sparse) + §E.2 (per-tuple claim) | **447 / 448** |
| 6.7 | EIP-170 fits after the new module + facade stub (re-measure; via_ir + optimizer_runs=1000) | §F (placement + re-measure caveat) | **446 / 449** |
| 6.8 | Full forge suite green; layout goldens / RNG-freeze proofs re-pass on the new subject | §D.5 + the test/re-audit phases | **447 / 448 / 449** (SEC-04) |

---

## S. Consolidated Threat Model

> Consolidates the per-plan `<threat_model>` blocks T-445-D1..D3 (storage, Plan 02) and T-445-E1..E4
> (entrypoint/payout, Plan 03), plus the standing supply-chain row T-445-SC. Every threat carries a
> disposition (`mitigate` / `accept`) and a specific mitigation referencing the SPEC section. The two headline
> floor items — SEC-01 (steer-proof 4-of-4) and SEC-02 (no solvency hole) — are stated as
> **design-locked-here / attested-downstream**.

### S.1 Trust Boundaries

| # | From → To | Boundary asset | Crossing |
| --- | --- | --- | --- |
| TB-1 | client → `buyFoilPack` | fresh ETH / claimable half / the per-level cap | the payable buy entrypoint (§E.1) |
| TB-2 | top-wagerer → the LIVE hero symbol | one quadrant's symbol of the LIVE winning set | the `dailyHeroWagers` ETH-bet board → `_applyHeroResult` (§E.3) |
| TB-3 | claimant → the ETH prize pool | up to 10% of `futurePrizePool` per ETH spin | the capped ETH lane (§E.5 C) |
| TB-4 | player → their own `foilRecord` slot | the player's frozen sigs + `multBps` + stamp | the single-slot record (§D.1) — only the player's own re-buy mutates it |
| TB-5 | claimant → `foilMatchClaimed` | the per-tuple double-claim marker | the CEI mark-before-payout guard (§D.3.2) |

### S.2 STRIDE Register (T-445-D* + T-445-E* + T-445-SC)

| ID | STRIDE | Threat | Disposition | Mitigation (SPEC section) |
| --- | --- | --- | --- | --- |
| T-445-D1 | Tampering | `foilRecord` slot collision with an existing slot | **mitigate** | append-only after `boxPlayers` (`:2393`); two new base mapping slots; no existing slot moved/retyped (§D.5; SEC-04 layout-golden re-pass at 448) |
| T-445-D2 | Repudiation | double-claim of the same `(player, level, day, drawKind, ticketIndex)` | **mitigate** | sparse `foilMatchClaimed[key]` set BEFORE payout (CEI); five distinct positional `abi.encode` fields → collision-free (§D.3) |
| T-445-D3 | Denial of Service | a fast `level++` strands an unclaimed match (grief) | **accept** (by-design, §5) | record persists per-level via the stamp; overwritten ONLY by the SAME player's next buy; the single-slot loss edge is surfaced for USER sign-off (PIN 1, §D.6 / §T) (§D.4) |
| T-445-E1 | Elevation of Privilege | 4-of-4 whale-pass moonshot via hero steering | **mitigate** | 4-of-4 gated on `heroFreeCount == 4` (pure VRF); a steered hero reaches at most 3-of-4 (SEC-01) (§E.3); proven at 448 |
| T-445-E2 | Denial of Service / solvency | ETH lane drains `futurePrizePool` | **mitigate** | `ETH_WIN_CAP_BPS = 1000` (10%) clamp + lootbox spill, cloned from `DegenerusGameDegeneretteModule.sol:877-915`; FLIP/WWXRP are mints; whale pass pool-neutral (SEC-02) (§E.5 C); proven at 448 |
| T-445-E3 | Tampering | afking principal spent on a foil buy | **mitigate** | the foil payment path REJECTS the afking leg (the `remaining > avail` `revert E()`); only fresh-ETH/claimable accepted (FOIL-03) (§E.1 step 3) |
| T-445-E4 | Information disclosure / grind | magnitude/currency steered via the match lane | **mitigate** | disjoint keccak domains (`FOIL_MAG_TAG` / `FOIL_CCY_TAG` ≠ the match lane); derived from retained `rw` at claim, never live-read (MATCH-08) (§E.5 B) |
| T-445-SC | Tampering (supply chain) | a malicious or hallucinated npm / pip / cargo package enters via a new dependency | **accept** | no new package installs in this paper-only phase; the v71 IMPL adds NO new dependency — all reuse is in-repo audited rails (`packedTraitsDegenerette`, `ActivityCurveLib`, the capped-spin path, `whalePassClaims`) |

### S.3 The two headline floor items (design-locked-here / attested-downstream)

- **SEC-01 — 4-of-4 steer-proof (gated HERO-FREE).** A steerer controls only the `heroSymbol` of the LIVE
  hero quadrant — at most `+1` to `liveCount`; `heroFreeCount` is computed on pure VRF (untouchable). The
  4-of-4 whale-pass tier is gated **ONLY on `heroFreeCount == 4`**, so a steered hero reaches **at most
  3-of-4** and **never** the moonshot. The 2-of-4 / 3-of-4 bounded hero edge is intentionally KEPT (LIVE).
  **Design-locked at §E.3; attested at 448.**
- **SEC-02 — no solvency hole.** The ETH lane is bounded to **≤ 10% of `futurePrizePool`** via
  `ETH_WIN_CAP_BPS = 1000` + lootbox spill (cloned from `:877-915`); FLIP and WWXRP are **mints** (no pool
  draw); the whale pass is a **pool-neutral** deferred grant against the existing `whalePassClaims:1122` slot.
  Structurally solvent. **Design-locked at §E.5; attested at 448.**

---

## T. USER Decisions to Confirm Before the 446 IMPL Gate

> The single genuine open decision surface for the v71 design-lock — three items the USER signs off in one
> read before any Phase 446 contract work begins. Everything else in §A / §D / §E is mechanically determined.
> Reply to confirm the locks (or specify a change); a requested change updates the corresponding SPEC section
> (and `445-SPEC-D-storage.md`) to the chosen variant and re-presents.

**Decision 1 — PIN 1: `foilRecord` level-keying (LOCKED: single-slot `mapping(address => uint256)`).**
The locked single-slot form means **a player who RE-BUYS a foil pack at level *L+1* BEFORE claiming level-*L*'s
matches LOSES *L*'s unclaimed signatures.** A level advance ALONE never strands a match — **only the player's
OWN next foil buy does**; no third party (`advanceGame`, another player) can trigger it, so this is **not a
griefing vector**. The documented alternative is `mapping(uint24 level => mapping(address => uint256))` — *L*'s
unclaimed signatures **survive** an *L+1* re-buy, at the cost of **+1 storage slot per (level, player) that
ever buys** (one slot per level per buyer instead of one slot per buyer). → **Reply "single-slot OK"** to keep
the lock, or **"switch to level=>player"** to adopt the surviving-record variant.

**Decision 2 — PIN 2: packed bit-offset (LOCKED: stamp `[144-167]`, payload `[0-143]`).** `sig0..sig3` at
`[0-127]`, `multBps` at `[128-143]`, the `rawLevel` stamp at `[144-167]`, `[168-255]` reserved `0`
(`_FOIL_STAMP_SHIFT = 144`, `_FOIL_MULT_SHIFT = 128`). The payload is contiguous in the low 144 bits (a clean
unpack loop); the stamp is a high-field self-stamp read in the spirit of `centuryBonusUsed`'s
`(packed >> 224) == level`. The documented alternative is the `centuryBonusUsed`-mirroring **stamp at bit 224**
(sigs `[0-127]`, `multBps` `[128-143]`) — also one slot, ≤ 256 bits; the only difference is the stamp offset
(224 vs 144). This is a pure-engineering pin. → **Reply "bit-offset OK"** to accept the locked layout, or
request the bit-224 mirror.

**Decision 3 — the single-slot player-loss edge (the residual surface of Decision 1).** This is the one
residual loss surface of the LOCKED PIN 1 form, called out explicitly so the sign-off is informed: it is
folded into Decision 1 (confirming "single-slot OK" accepts this edge; "switch to level=>player" eliminates
it). It is **not** a separate switch — it is the consequence of the PIN 1 choice, surfaced here for clarity.

**Spot-check before signing:** the §R REQ-Coverage Map lists all 20 REQ-IDs (FOIL-01..05, RARE-01..04,
MATCH-01..10, SEC-03); the §E.7 calibration reports **≈1.94 faces/pack/30d** (on the D-05 ~2-face target, 3.1%
low → no recalibration). → **Reply "single-slot OK, bit-offset OK"** (or specify changes) to approve the SPEC
and unblock Phase 446.
