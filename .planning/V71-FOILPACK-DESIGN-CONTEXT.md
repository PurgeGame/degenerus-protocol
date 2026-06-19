# V71 Foil Pack — Design Context

> Durable, code-grounded design context for a NEW purchasable "foil pack" product.
> Synthesized from 6 parallel subsystem maps, **re-verified against HEAD source** (citations are `file:line`).
> Status: pre-design. This document fixes the facts; the open decisions are listed at the end.

## Feature intent (the brief)
A purchasable "foil pack" with three constraints:
1. **At most ONE foil pack per account per level.**
2. **EV crosses over with activity score**: WORSE than a normal ticket at LOW activity score, slightly BETTER than a lootbox at HIGH activity score.
3. **HIGHER odds of "gold" traits** than a normal ticket / lootbox.

Everything below is what the code already fixes, and where the design must supply a number.

---

## 1. Mechanics map (6 subsystems, grounded)

### 1.1 Activity Score & Consumer Curves
Activity score is a single per-player integer in **whole points**, computed on-read by `_playerActivityScoreAt` (`contracts/modules/DegenerusGameMintStreakUtils.sol:282`). It sums: mint-streak `min(streak,50)`; mint-count `min(25, …)`; quest-streak `floor(questStreak/2)` **UNCAPPED**; cached affiliate bonus (≤50); whale pass +10/+40 or deity pass fixed 155; minus a curse penalty (≤20); clamped to `ACTIVITY_SCORE_HARD_CAP_POINTS = 65,534` (`DegenerusGameStorage.sol:142`). Min is 0.

That raw score feeds six readers. **Five are value curves** (centralized in `contracts/libraries/ActivityCurveLib.sol`, verified `:42-90` + `:114-146`, plus the lootbox EV curve in `DegenerusGameStorage.sol:1640-1677`): decimator burn multiplier, century mint/afking bonus, degenerette ROI, WWXRP high ROI, lootbox EV multiplier. They share a v70 shape: **steep early ramp to ~90% of the gain at a low knee K (235/305/400), 98% by score 500, then a near-flat tail to MAX at score 30,000** (`ActivityCurveLib.sol:25-29`). A **sixth reader moves the OPPOSITE way**: the affiliate lootbox taper.

- Score is **frozen at commit**, never live-read at claim, for every consumer (anti-gaming). Lootbox: 16-bit `score` packed into `lootboxEth` at deposit (`DegenerusGameStorage.sol:1616-1631`). Decimator: re-derived via `minScoreForBucket` (`ActivityCurveLib.sol:134-146`).

### 1.2 Normal ticket (the low-AS floor)
- Fixed per-level price, **activity-score-INVARIANT**: `PriceLookupLib.priceForLevel` — 0.01 ETH (L<5), 0.02 (5–9), then a 100-level cycle 0.04 / 0.08 / 0.12 / 0.16 and **0.24 at x00 milestones** (`contracts/libraries/PriceLookupLib.sol:21-41`).
- Cost formula: `priceWei * ticketQuantity / (4*TICKET_SCALE)`; one whole ticket = `priceWei/4`; `TICKET_SCALE=100` (`DegenerusGameMintModule.sol:1456`, `DegenerusGameStorage.sol:157`).
- Spend routes 90% next-pool / 10% future-pool, **0% rake** (`DegenerusGameMintModule.sol:117,201-218`).
- A ticket has **no fixed payout** — value is the trait-bearing entry's jackpot eligibility + FLIP/affiliate/bulk/recycle side-rewards.
- The **only** score-sensitive ticket lever: the x00 **century bonus-ticket** grant (`DegenerusGameMintModule.sol:1712-1726`), `ActivityCurveLib.centuryBps` 0%→90%@305→98%@500→100%@30000, capped at `20 ETH/(priceWei/4)` per (buyer,level). Fires only on `targetLevel%100==0`.

### 1.3 Lootbox (the high-AS ceiling)
- **No fixed price** — a variable ETH deposit `>= LOOTBOX_MIN = 0.01 ETH` (`DegenerusGameMintModule.sol:100`); 100% rake-free to pools.
- **One activity lever**: the frozen EV multiplier on the resolution amount, `_lootboxEvMultiplierFromScore` (`DegenerusGameStorage.sol:1640-1677`, re-verified): **90%@0 → 100%@60 (neutral) → 139.5%@400 → 143.9%@500 → 145%@30000 (flat)**.
- **Bonus-only cap**: penalty/neutral boxes (mult ≤100%) scale the FULL amount; only the >100% bonus draws against a per-(player,level) **10-ETH** benefit accumulator (`LOOTBOX_EV_BENEFIT_CAP`, `DegenerusGameStorage.sol:1568`; logic `DegenerusGameLootboxModule.sol:473-509`). Max bonus benefit ≈ +45% on 10 ETH = **+4.5 ETH/level**.
- 6-way reward roll (`DegenerusGameLootboxModule.sol:1974-2044`): 40% tickets / 15% DGNRS / 15% WWXRP-spin / 15% large-FLIP / 10% triple-FLIP / 5% ETH-spin.
- **The lootbox confers NO per-ticket gold uplift** — its tickets queue through the SAME heavy-tail path as normal tickets (0.781%/quadrant).

### 1.4 Traits & gold
- A trait byte = `[QQ][CCC][SSS]` (quadrant, color tier 0-7, symbol 0-7); 4 packed per uint32 (`DegenerusTraitUtils.sol:15-37`).
- "**Gold**" is NOT a separate item — it is **color tier == 7**, the top of an 8-tier heavy-tail distribution. Checked as `((trait>>3)&7)==7`.
- Heavy-tail (ticket + lootbox-awarded ticket) gold = `scaled>=254` of 256 = **2/256 = 0.78125% per quadrant** (`DegenerusTraitUtils.sol:115-127`, re-verified).
- Degenerette near-uniform producer: gold = `scaled==14` of 15 = **6.667% per quadrant** (`DegenerusTraitUtils.sol:201-223`, re-verified) — a SECOND distribution used only by Degenerette spins.
- Gold value sinks: jackpot solo-bucket rotation + reduced deity dilution (`DegenerusGameJackpotModule.sol:1009-1027`); Degenerette per-N payout tables EV-calibrated per gold-quadrant-count N∈{0..4} (`DegenerusGameDegeneretteModule.sol:1069-1131,281-301`).

### 1.5 Per-level caps, payment & buy flow
- Level counter `level` (uint24, slot 0); phase via `jackpotPhaseFlag`; `_activeTicketLevel() = jpFlag ? level : level+1` (`DegenerusGameMintStreakUtils.sol:139`).
- Main entry `purchase()` (`DegenerusGame.sol:548`) → delegatecall `MintModule.purchase` → `_purchaseForWithCached` (`DegenerusGameMintModule.sol:1490`). Payment waterfall: fresh ETH → claimable → afking, selected by `MintPaymentKind`. FLIP only via in-jackpot `redeemFlip`.
- **Per-level cap precedent** (the model for "one foil pack per level"): `centuryBonusUsed[player]` packs `(level<<224 | used)`; `_centuryUsedFor` returns 0 unless the stamp equals the queried level → **free per-level reset, no global sweep** (`DegenerusGameStorage.sol:1857-1876`, re-verified). The lootbox EV cap uses the same level-stamp idiom with two live windows (`lootboxEvCapPacked`).
- Score is computed ONCE per buy at `DegenerusGameMintModule.sol:1709` (`cachedScore = _playerActivityScore(...)`) — the exact value/point a foil leg should freeze.

### 1.6 Module architecture & EIP-170
- Thin facade `DegenerusGame` delegatecalls ~12 constant-address modules (no proxy/registry); all inherit `DegenerusGameStorage` for slot alignment (`DegenerusGame.sol:277`).
- **Measured deployed bytecode (this build, re-verified against forge-out):**

| Contract | Bytes | Headroom (limit 24,576) |
|---|---:|---:|
| DegenerusGame (facade) | 20,388 | **4,188** |
| MintModule | 23,460 | **1,116** (effectively full) |
| LootboxModule | 19,690 | 4,886 |
| DecimatorModule | 11,006 | **13,570** |
| BoonModule | 3,760 | 20,816 |
| BingoModule | 3,161 | 21,415 |
| GameOverModule | 4,721 | 19,855 |

- **MintModule cannot host a foil body** (1,116 free). Only a thin stub (~80-150 B) can touch the facade. The body belongs in a roomy existing module or a new `GAME_FOILPACK_MODULE` constant in `ContractAddresses`. New storage must be appended in `DegenerusGameStorage`, never declared in a module.

---

## 2. THE EV LADDER (the crux)

Treat all EV as a multiplier on **1 ETH of spend** (rake-free into pools for every product, so "EV" = expected realizable value of the entry, score-frozen at buy). The two anchors:

### normal-ticket EV(activity score) — FLAT
A ticket's price, pool routing, gold odds, and jackpot eligibility are all **score-invariant** (§1.2). Define **`TICKET_EV` = its score-flat baseline = 100%** by construction (it IS the baseline). The only deviation is the x00 century bonus (extra tickets on milestone levels only). So:
```
ticket EV(s) = TICKET_EV  (≈ flat 100%, +century step on x00 levels only)
```
NOTE: a ticket's *realized* EV is emergent (jackpot pool sizes, `DAILY_ETH_MAX_WINNERS=305`, `JACKPOT_LEVEL_CAP=5`, cohort competition) — there is no constant in code. Use 100%-of-face as the normalizing reference, not a guaranteed payout.

### lootbox EV(activity score) — RISING, 90%→145%, capped
From `_lootboxEvMultiplierFromScore` (`DegenerusGameStorage.sol:1640-1677`):

| activity score | lootbox EV | vs ticket (100%) |
|---:|---:|---|
| 0 | 90.0% | worse |
| 60 | 100.0% (neutral) | tie |
| 235 | ~120.4% | better |
| 400 | 139.5% (seg-A knee) | better |
| 500 | 143.9% (seg-B knee) | better |
| 30,000 | 145.0% (max) | better |

Caveat: the >100% bonus applies only to the first **10 ETH/account/level**; beyond the cap the lootbox reverts to 100% EV (`DegenerusGameLootboxModule.sol:473-509`). So "145%" is realized only on capped volume; marginal lootbox EV above the cap is 1.00x.

### Where the foil pack must sit
The brief = **`foil EV(s) < ticket EV` at LOW s**, and **`foil EV(s) > lootbox EV(s)` at HIGH s**, with a crossover region in between. The ticket line is flat ~100%; the lootbox line ceilings at 145%. So the foil pack needs its **own score-rising EV curve** with:
- a **low-end floor BELOW 100%** (below ticket) — e.g. 80–90% at s=0, AND
- a **high-end ceiling ABOVE 145%** (above the lootbox cap) — e.g. 148–155% in the tail.

```
        EV
 155% ┤                                   ░░░ foil (proposed: higher cap)
 145% ┤··················____●●●●●●●●●●●●● lootbox (HARD 145% ceiling)
 100% ┤━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ticket (flat baseline)
  90% ┤●        ░ foil floor (< ticket)
  80% ┤░
       └┬────┬────┬────┬────┬─────────────  activity score
        0   60   235  400  500          30000
        ▲low (foil<ticket)        ▲high (foil>lootbox)
```

**Two facts the design must internalize:**
1. **A foil curve that REUSES `_lootboxEvMultiplierFromScore` verbatim can never beat a lootbox** — it would tie at 145%, not exceed it (`DegenerusGameStorage.sol:1566`). "Slightly better than a lootbox at high score" REQUIRES either a higher MAX (>145%) or a higher/absent benefit cap, or both. (Re-confirmed: lootbox MAX = `LOOTBOX_EV_MAX_BPS = 14500`.)
2. **The meaningful crossover band is roughly score 60–500, not 30,000.** ~90% of every curve's gain lands by the low knee and 98% by 500; the 500→30,000 tail is the final ~2% (`ActivityCurveLib.sol:25-29`). Tuning the crossover into the flat tail makes the foil-vs-lootbox margin sub-1% and effectively invisible/ungameable. The **realistic crossover target is ~score 250–500.**

### The natural construction
Give the foil pack a sibling 4-segment curve in `ActivityCurveLib.sol` (reuse `ACTIVITY_SEG_B_KNEE_POINTS=500`, `ACTIVITY_EFFECTIVE_CAP_POINTS=30000`) with:
- floor `FOIL_MIN_BPS ≈ 8000–9000` (foil < ticket at s=0),
- it crosses 100% (ticket) somewhere in s ∈ [60, 250] — a tunable knob,
- it crosses the lootbox curve in s ∈ [250, 500] and ends `FOIL_MAX_BPS ≈ 14800–15500` (> lootbox 145%).

The exact `FOIL_MIN_BPS`, the two crossover scores, and `FOIL_MAX_BPS` are **knobs the design must set** (see Decisions §A, §C below). Real anchors to price against: ticket=100% flat; lootbox = the table above; benefit cap = 10 ETH/level (decide share vs separate vs none).

---

## 3. Gold-trait odds

| Path | Gold (color==7) per quadrant | Source |
|---|---:|---|
| Heavy-tail (normal ticket, lootbox-awarded ticket) | **0.78125%** (2/256) | `DegenerusTraitUtils.sol:115-127` |
| Degenerette / box-spin near-uniform | **6.667%** (1/15) | `DegenerusTraitUtils.sol:201-223` |
| Jackpot WINNING-trait draw (uniform) | 12.5% (1/8) | `JackpotBucketLib.sol:281-286` |

**Whole-ticket gold math (verified — resolves a map discrepancy):** the trait batch loop assigns **one trait per index with quadrant offset `(uint8(i & 3) << 6)`** (`DegenerusGameMintModule.sol:754-768`), so a **whole ticket (4 indices) rolls 4 independent quadrant traits**, each 0.781% gold. Therefore:
- per-quadrant gold = 0.781%,
- **P(≥1 gold across a whole ticket's 4 quadrants) = 1−(127/128)^4 ≈ 3.087%**.

(One subsystem map said "1 trait per whole ticket / 0.781%" — that is INCORRECT; the loop clearly rolls 4. Use 3.087% as the whole-ticket "ticket gold" baseline the foil must beat, and 0.781% as the per-quadrant rate.)

### The lever to raise gold odds — and its cost
`weightedColorBucket` / `packedTraitsFromSeed` / `traitFromWord` are **byte-frozen and shared by mint AND jackpot winner comparison** (`DegenerusTraitUtils.sol:115-178`). **Editing them changes gold rarity for ALL products and breaks the frozen-bytecode invariant — do NOT touch them.** The clean lever:
- **Add a NEW sibling pure producer** (e.g. `packedTraitsFoil(seed)` modeled on `packedTraitsDegenerette`, `DegenerusTraitUtils.sol:201-223`) with a wider gold band, AND
- a **foil-aware trait-write path** (`_raritySymbolBatch` calls `traitFromWord` today, `DegenerusGameMintModule.sol:759`) — a parallel batch path or a per-queue "foil" flag.

Concrete band options (decision §B): match Degenerette 6.667% (reuse the existing producer directly), a new intermediate band (e.g. `scaled>=248` = 8/256 = **3.125%**, 4× baseline; or `scaled>=240` = 16/256 = 6.25%), a guaranteed-≥1-gold floor, or best-of-N on the standard draw.

### Side-effects of more gold (must be bounded)
- **Degenerette per-N tables are EV-calibrated to current gold rarity for equal base EV across picks** (`DegenerusGameDegeneretteModule.sol:1069-1131`). Feeding higher-gold foil tickets into Degenerette WITHOUT retuning makes gold-heavy picks strictly +EV → exploit.
- **Jackpot gold confers solo-bucket rotation + reduced deity dilution** assuming gold ≈ 0.781% rare (`DegenerusGameJackpotModule.sol:1009-1027`). Cheap high-gold foil supply dilutes that advantage and could let a foil buyer farm solo buckets.
- → The design must **declare whether foil gold counts** as color==7 in jackpot and/or Degenerette, or is an isolated tier (decision §B follow-on).

---

## 4. Integration sketch

| Concern | Where it attaches | Note |
|---|---|---|
| Entrypoint | `DegenerusGame.sol:548` style stub — `payable buyFoilPack(address buyer, …)` → `_resolvePlayer` → delegatecall module | ~80–150 B of the facade's 4,188 free |
| Interface | `IDegenerusGameModules.sol` (new `IFoilPackModule` or extend Mint) | so the facade resolves a real ABI |
| Body home | DecimatorModule (13,570 free) / Boon / Bingo, OR a NEW `GAME_FOILPACK_MODULE` | **NOT MintModule (1,116 free)** |
| Buy plumbing model | `DegenerusGameMintModule.sol:1490-1832` (`_purchaseForWithCached`) | payment waterfall, pool split, single score read at `:1709`, quest/affiliate |
| Score freeze | copy lootbox: read `_playerActivityScore` at buy, pack into the foil word, apply curve at resolve | anti-gaming; never live-read at resolve |
| EV curve | new sibling fn in `ActivityCurveLib.sol` (reuse 500/30000 knees) or a forked `_lootboxEvMultiplierFromScore` with higher cap | must exceed 145% to beat lootbox |
| Gold producer | new `packedTraitsFoil` sibling in `DegenerusTraitUtils.sol` (do NOT edit shared fns) + foil-aware batch path | |
| "One per level" cap | **level-stamped flag mirroring `_centuryUsedFor`** (`DegenerusGameStorage.sol:1857-1876`); a 1-bit degenerate of it | new `mapping(address=>uint256)` in storage base; auto-resets per level |
| Benefit cap | share `LOOTBOX_EV_BENEFIT_CAP` (10 ETH) accumulator, own cap, or none (one-per-level is itself a throttle) | decision §F |
| Guards | replicate `_livenessTriggered`/`gameOver`/`rngLockedFlag` gates | or it can mint into a terminal/locked state |

**EIP-170 feasibility: GREEN.** A new module trivially fits; the facade has 4,188 B for a stub. The only "red" path is putting any real body in MintModule. Re-measure after adding stub+body (via_ir + optimizer_runs=1000, osaka — sizes are profile-sensitive).

**Per-level cap key choice** (decision §E): `_activeTicketLevel()` (= `level+1` in purchase phase, matches century/lootbox-EV) vs raw `level`. Keying on `_activeTicketLevel()` allows one pack per phase-target (potentially 2 per game-level across purchase+jackpot phases); keying on raw `level` allows exactly one per game-level.

---

## 5. Open risks & feasibility notes (for roadmapping)

1. **Flat-tail trap.** Curves are near-flat 500→30,000 (`ActivityCurveLib.sol:25-29`). Target the crossover at score ~250–500, not the saturation point, or the foil-vs-lootbox edge is sub-1% and ungameable.
2. **Can't beat the lootbox by reuse.** Lootbox MAX is hard 145% (`DegenerusGameStorage.sol:1566`). "Better than lootbox at high score" needs a foil-specific higher MAX and/or higher benefit cap.
3. **Shared trait fns are frozen.** Raising gold REQUIRES a new sibling producer; editing `weightedColorBucket`/`packedTraitsFromSeed` would change gold for ALL products and break the audited bytecode invariant.
4. **EV-calibration coupling.** Degenerette per-N tables and jackpot deity dilution assume current gold rarity. Decide whether foil gold counts there; if yes, those tables/weights need re-tuning to preserve equal-EV / distribution assumptions.
5. **Quest-streak dominates score.** Quest-streak is the ONLY uncapped component (`floor(q/2)`); all else caps ≤50/25/20. "Better at high score" effectively means "better for heavy quest-streak grinders" — and the affiliate taper already penalizes that cohort (see §6). A foil pack could undo that counterweight.
6. **Affiliate taper interaction.** Rising score REDUCES the buyer's affiliate payout on fresh-ETH lootbox buys: 100% at score <100, linear to 25% floor at score ≥255 (`DegenerusAffiliate.sol:187-189,875-889`). Decide whether a foil buy invokes fresh-ETH affiliate payout (and is thus tapered for high-AS buyers).
7. **Freeze BOTH score and resolve-level.** Lootbox freezes score at deposit and reads open-level live (non-timable). A foil pack must replicate both freezes or become grindable.
8. **Storage width.** Score cap is 65,534 → a frozen foil score needs ≥16 bits; do not collide with existing packed slots. New vars MUST be appended in `DegenerusGameStorage` (delegatecall-shared), never in a module.
9. **mintPacked_ has no clean 24-bit run** for a level stamp; a dedicated level-stamped `mapping(address=>uint256)` (century-style) is the safe storage, not squeezing fragmented `mintPacked_` bits.
10. **Combined-buy ETH accounting.** A foil leg added to a combined purchase must split `msg.value` explicitly (cf. `buyLootboxAndPresaleBox`) or overpay/short-pay accounting drifts.
11. **Realized ticket EV is emergent.** "Ticket EV" used for pricing is not a code constant — it depends on jackpot pool sizes, winner caps, and cohort competition. Fix the comparison assumptions explicitly when pricing.

### Documentation-drift to ignore (use the CONSTANTS, not the comments)
- `DegenerusGameLootboxModule.sol:471` docstring says EV range "8000-13500 / 80%-135%"; the live constants are **9000–14500 (90%–145%)** (`DegenerusGameStorage.sol:1558,1566`). Same stale "80%-135%" appears at `IDegenerusGameModules.sol` resolver comments and `LootboxModule:562`.
- `DegenerusAffiliate.sol:874` comment says taper "100% at score 10000 → 25% at 25500+"; the live constants are **START=100, END=255** (`DegenerusAffiliate.sol:187-188`). The `:396` doc and the actual code use 100/255 — the inline `:874` comment is stale.

(These are pre-existing comment-only drifts in a frozen tree, not logic bugs — noted so foil pricing is not anchored to wrong numbers.)

---

## 6. REVISED DIRECTION (per user) — trait-value EV via activity-score-scaled rarity

> **SUPERSEDES §2.** The EV-multiplier-curve framing in §2 (a foil-specific `_lootboxEvMultiplierFromScore`-style curve that scales the *resolution amount*) is **no longer the design**. The foil pack does **not** multiply ETH or grant extra tickets. §2's curve math is retained only as a useful study of curve shape/knees; the live EV lever is now **trait rarity**, not an amount multiplier. §1, §3, §4 facts remain valid; §3 is now load-bearing (it is the actual lever). Where §6 and §2 conflict, §6 wins.

### 6.0 The revised brief in one paragraph
A foil pack buys the **same current-level tickets a normal ETH purchase would buy** — same count, same price-per-ticket face, same `traitBurnTicket[level][traitId]` jackpot eligibility (`DegenerusGameMintModule.sol:754-768`). Its **only** advantage is **trait rarity**: the rarer color tiers (and "gold", color==7) are more common by a factor **determined by the buyer's activity score** (low score → small/no uplift; high score → large uplift). A **fixed price premium over the tickets' face** is what makes the low-score case a *penalty* (you pay more for tickets whose rarity edge has not yet kicked in). EV is **deliberately emergent/fuzzy** — a rare trait's worth is set by live jackpot dynamics (pool sizes, bucket competition, solo-rotation), not a code constant — so there is **no foil EV curve to write**; the curve we write is the **rarity-boost** curve, and EV crossover is a *calibration target*, not a hard-coded multiplier. One pack per account per **raw game-level**; **fresh ETH only**. Candidate add-on (a "maybe"): record each pack's 4-trait signature and pay a bonus if a daily jackpot draw matches it.

### 6.1 The revised mechanism (concrete)

**What changes at buy vs a normal purchase:** exactly two things — (a) the trait-producer call on the foil queue is swapped for a rarity-boosted sibling, and (b) a price premium is charged. Everything else (ticket count, pool routing 90/10, jackpot eligibility) is identical to §1.2.

**The rarity-boost producer (the single lever).** The shared trait fns `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` (`DegenerusTraitUtils.sol:115-178`) are **byte-frozen and shared by mint AND jackpot winner derivation** (v70.0 FREEZE `ffbd7796`, contracts tree `99f2e53f`, covered by `RngFreezeAndRemovalProofs`) — **they MUST NOT be edited.** A **new sibling pure producer** `traitFromWordFoil(uint64 rnd, uint16 boostBps)` (+ a `packedTraitsFoil` pack wrapper) is added in `DegenerusTraitUtils.sol`, exactly mirroring the existing sibling precedent `packedTraitsDegenerette`/`_degTrait` (`DegenerusTraitUtils.sol:201-223`) which already coexists with the frozen heavy-tail fns and feeds a different consumer. The foil queue's write path swaps the single `traitFromWord(s)` call at `DegenerusGameMintModule.sol:759` for the boost-aware variant; nothing else in the batch loop changes (per-quadrant independence via `(i&3)<<6` preserved).

**PMF at boost=0 vs high boost (the recommended LEVER, "mix-to-rare-tail").** Frozen baseline heavy-tail PMF (`DegenerusTraitUtils.sol:115-127`, widths /256): `c0=c1=c2=25.000%`, `c3=12.500%`, `c4=6.250%`, `c5=3.125%`, `c6=2.34375%`, `c7(gold)=0.78125%` (widths `64/64/64/32/16/8/6/2`, sum 256 exact). The boost is a **single mixing weight `w∈[0,1]` (bps 0..10000)** frozen at buy. Roll a gate slice `g` (top 8 bits of an entropy lane disjoint from the color/symbol lanes); if `g < (w*256)/10000` draw from the **conditional rare-tail distribution** (c3..c7 ∝ `16:8:4:3:1`), else fall through to the frozen `weightedColorBucket`. This lifts **all** the rarer tiers together (matching the brief phrase "all of the rarer traits more common by a factor"):

| boost w | gold c7 | c5 | c4 | c3 | commons c0-c2 | note |
|---:|---:|---:|---:|---:|---:|---|
| 0 (baseline) | 0.781% | 3.125% | 6.25% | 12.5% | 75.0% | == normal ticket PMF |
| 0.25 | ~1.37% | ~5.08% | ~10.2% | ~20.3% | ~56.3% | mild |
| 0.50 | ~1.95% (×2.5) | ~7.81% | ~15.6% | ~31.25% | ~37.5% | mid |
| 1.0 | ~3.125% (×4.0) | 12.5% | 25.0% | 50.0% | 0% | max (commons vanish) |

(Mix-to-rare-tail caps gold at ×4. If the design instead wants a large **gold-only** ceiling, the alternative "mix-to-pure-gold" component — boost rolls c7 directly — gives `gold = (1-w)*0.781% + w*100%`: w=0.05→5.74% (×7.4), w=0.10→10.7% (×13.7), unbounded to 100%. That is a §6.5 decision.)

**Activity-score → boost mapping (crossover ~score 300).** Add a sibling 4-segment piecewise-linear curve `foilBoostBps(score)` in `ActivityCurveLib.sol` (templates: `decMultBps` `:22-43`, `centuryBps` `:54-67`; reuse `ACTIVITY_SEG_B_KNEE_POINTS=500`, `ACTIVITY_EFFECTIVE_CAP_POINTS=30000`). Shape, identical to the v70 family (`ActivityCurveLib.sol:25-29`): **`FOIL_BOOST_MIN_BPS=0` at score 0** (boost=0 ⇒ foil PMF == normal-ticket PMF, so the *only* low-score difference is the price premium = the penalty), steep ramp so ~90% of the gain lands by the seg-A knee (~250-305), 98% by score 500, flat `FOIL_BOOST_MAX_BPS` from 500→30000. Because the curves are near-flat past 500, the **meaningful uplift must land by ~score 250-500** — tuning into the tail makes the edge sub-1% and invisible (§5.1 flat-tail trap). Score is read once at buy (`cachedScore`, `DegenerusGameMintModule.sol:1709`), frozen into the foil word, and `foilBoostBps` applied at resolve — **never live-read** (anti-gaming; same freeze discipline as lootbox/decimator).

### 6.2 EV-crossover calibration (given emergent value)

**There is NO fixed gold-payout constant in code (confirmed)** — so there is no foil EV multiplier to set. Calibration is a *targeting* exercise: pick the price premium and the boost magnitude so that realized EV lands worse-than-ticket at low score and better-than-lootbox at ~score 300.

**Which value channels back the EV (only two, both heavy-tail jackpot):**
1. **Solo-bucket gold rotation** (`DegenerusGameJackpotModule.sol:1009-1037`) — the **dominant** lever. The daily/terminal jackpot draws 4 **uniform** winning traits (gold 12.5%/quadrant, `JackpotBucketLib.sol:281-286`); `_pickSoloQuadrant` forces the oversized solo share (60% terminal / 20% daily, count=1) onto a gold quadrant whenever any winning trait is gold (P≈41.4%). A holder sitting in that (typically tiny) gold bucket wins an oversized near-solo share. The 16× asymmetry between the **uniform 12.5%-gold winning draw** and the **heavy-tail 0.781%-gold burn side** is *exactly* what makes a gold burn-bucket valuable.
2. **Reduced deity dilution** (`_deityVirtualCount`, `DegenerusGameJackpotModule.sol:1423-1436`) — secondary. A gold bucket gives a present deity a flat **1** virtual entry vs `max(2, len/50)` for commons; gold roughly halves deity dilution at small bucket sizes. Only fires when a deity owns the winning symbol (≤32 of 256 trait-ids) and shrinks at large bucket sizes — treat as a multiplier on channel 1, not a primary source.

**The NON-channel (do not price against it):** Degenerette per-N payout tables (`DegenerusGameDegeneretteModule.sol:281-301`) are **EV-flat by calibration** (`basePayoutEV=100 centi-x` per N; the N=4 S=9 ladder rises to 209,164× but exactly compensates lower hit-probability). A foil ticket is a **burn entry, not a Degenerette pick**, so there is no coupling today — and there must remain none. Foil gold gives Degenerette **zero** base-EV uplift; anyone reading those multipliers as free EV mis-prices the pack.

**The premium needed (anchors):**
- **Low-score < normal ticket:** at score 0, boost=0 ⇒ identical PMF ⇒ identical realized EV *before* premium. So the premium ALONE supplies the low-score penalty: `foil EV(0) = ticket_face_EV − premium < 100%`. A premium of e.g. **+15-25% over face** makes a low-score pack a clear loss vs buying the same tickets normally.
- **Score~300 > lootbox:** the high-AS ceiling to beat is the lootbox at ~score 300 = **127.88% EV** with the bonus capped at **10 ETH/level (+4.5 ETH/level max)** (`DegenerusGameStorage.sol:1640-1677`, `DegenerusGameLootboxModule.sol:473-509`; flat-cap MAX 145% at saturation). The boost magnitude at score 300 must make `4 × U(300) × goldValuePerQuadrant(channels 1+2) − premium` exceed the lootbox's marginal EV there. Because `goldValuePerQuadrant` is emergent, **calibrate it empirically (Monte-Carlo against expected/historical pool sizes), not from a closed form.**

**Side-effect bounds (which channels assume current gold rarity):** Both backing channels are **POSITIONAL/RELATIVE** — their value assumes gold buckets stay tiny (a specific gold trait-id is ~0.0977%/index, ~8× rarer than a color-0/1/2 per-symbol bucket). **A flood of cheap foil gold fills those buckets and erodes the very edge it sells** — solo-share-per-winner and reduced-deity-dilution both collapse toward the common baseline. Therefore **calibrate the crossover against a SATURATED-supply equilibrium, not the current 0.781% scarcity**, or the pack over-promises at high adoption. The one-per-account-per-level cap + the price premium are the natural throttles (§6.4). If foil-boosted gold writes real color==7 traitIds into `traitBurnTicket`, it **also dilutes organic-gold holders'** solo-rotation and reduced-deity edge — a decision the design must own (§6.5).

### 6.3 Jackpot-match add-on feasibility ("daily jackpot ticket matches your foil ticket")

**The blunt fact:** the daily jackpot does **NOT** draw one 4-trait "winning ticket." Each resolution rolls **4 uniform per-quadrant winning trait IDs** (`getRandomTraits`, `JackpotBucketLib.sol:281-286`), packed into `mainTraitsPacked` and already **emitted** as `DailyWinningTraits(day, mainTraitsPacked, bonusTraitsPacked, bonusTargetLevel)` (`DegenerusGameJackpotModule.sol:97-103,1799-1816`). And a game "ticket" is **NOT an NFT** and carries **NO stored 4-trait signature** — each whole ticket = one buyer-address entry in **one** quadrant bucket (`_raritySymbolBatch`, `DegenerusGameMintModule.sol:754-768`); `packedTraitsFromSeed` (the only 4-trait producer) has **zero production call sites**. So "your foil ticket matches the daily jackpot ticket" has **no native referent** — BOTH a 4-trait foil signature AND a per-player record of it are **new constructs**.

**What "match" can concretely mean, with probabilities** (each quadrant a uniform 6-bit `[CCC][SSS]`, 1/64):

| Match definition | P(hit) | Source |
|---|---:|---|
| Full 4-trait exact (synthetic foil sig vs `mainTraitsPacked`) | (1/64)⁴ = **1-in-16.7M** | `JackpotBucketLib.sol:281-286` |
| **≥1 of 4 quadrants exact** (recommended) | 1−(63/64)⁴ = **~6.15%** | derived |
| One fixed-quadrant exact byte | 1/64 = **1.5625%** | `JackpotBucketLib.sol:282` |
| Color-tier (gold) match in a given quadrant | 1/8 = **12.5%** (uniform draw side) | `JackpotBucketLib.sol:281-286` |
| Main **+** bonus, ≥1 across 8 quadrants | ~**11.9%** | derived |

Full 4-trait exact (~5.96e-8) is **unpayable as a product**. The clean, non-positional, codeable definition is **per-quadrant against `mainTraitsPacked`** (~6.15% for ≥1 of 4) — this gives a **deterministic EV term** (`fixed bonus × match-probability`) that, unlike channels 1+2, **does not saturate**, which is useful to anchor the high-score side without leaning on emergent pool dynamics.

**Storage & gas to record signatures + pay a bonus:**
- **Signature record:** append a per-(player,level) packed record in `DegenerusGameStorage` (century idiom, `DegenerusGameStorage.sol:1857-1876`): `mapping(address=>uint256) foilPackRecord` packing `(level<<224 | signature32 | flags)` — **auto-resets per level for free** (the one-per-level cap is the throttle), no global sweep. Signature = `packedTraitsFromSeed(keccak(buyer, level, buyEntropy))` **frozen at buy**, stored as 32 bits — never recomputed live (else grindable once the VRF word is known).
- **Payout path — pull/claim, NOT push.** A per-draw on-chain loop over all foil signatures is **unbounded by foil sales** and runs inside the jackpot resolution that is explicitly engineered to stay under the 15M-gas block limit (Phase-1/Phase-2 split) — a naive push-match could **brick `advanceGame`**. The strongly-preferred model: the player **claims** by submitting `(day, quadrant)`; the contract re-derives the day's winning traits from the retained `rngWordByDay[day]` (`DegenerusGameStorage.sol:462`) and verifies against the stored signature, then credits via existing rails (`_creditClaimable` ETH or `coinflip.creditFlipBatch` FLIP, already used at `DegenerusGameJackpotModule.sol:1230,1678`). **Draw gas stays flat.** Cheapest of all: match fully **off-chain** against the already-emitted `DailyWinningTraits` event, settle via the same claim verification.

**Recommended definition + bonus sizing:** **≥1-of-4 per-quadrant match against `mainTraitsPacked` only** (~6.15%), **pull/claim** settlement, bonus paid as **bonus tickets via `_queueTickets`** (no new ETH liability, keeps solvency clean) OR a small fixed ETH bonus from `futurePrizePool` if a cash feel is wanted. Sizing: pick `bonus` so the deterministic term `0.0615 × bonus` is a meaningful but minor slice of the high-score EV (e.g. covers a fraction of the premium), leaving channels 1+2 as the headline. This add-on is **independent of channels 1+2** and is the only **non-emergent** EV knob — its value is exactly `P(match) × bonus`.

### 6.4 Integration sketch — deltas vs §4

§4's table stays valid (entrypoint stub, body home NOT MintModule, score freeze, per-level cap). The revised deltas:

| §4 row | REVISED |
|---|---|
| **EV curve** | **REMOVED.** No foil `_lootboxEvMultiplierFromScore` / no amount-multiplier curve. Replace with **`foilBoostBps(score)`** in `ActivityCurveLib.sol` (rarity-boost magnitude, NOT EV). |
| **Gold producer** | Now the **core** lever (was secondary). New `traitFromWordFoil(rnd, boostBps)` + `packedTraitsFoil` sibling in `DegenerusTraitUtils.sol`; do NOT edit the frozen shared fns. |
| **Foil-aware trait-write path** | Swap the single `traitFromWord(s)` call at `DegenerusGameMintModule.sol:759` on the foil queue for `traitFromWordFoil(s, frozenBoost)`; preserve per-quadrant independence `(i&3)<<6` and disjoint color/symbol/gate entropy lanes. |
| **Pricing** | **Premium model, not amount-scaled.** Charge `ticketFace + premium` (fixed % over face). Tickets bought = the same count a normal `ticketFace` ETH spend buys; the premium is pure rake-to-pools above face (decide routing). |
| **Match-record storage** (NEW) | If the add-on is in scope: append `mapping(address=>uint256) foilPackRecord` (century idiom) for the frozen 32-bit signature; pull/claim verification against `rngWordByDay[day]`. |
| **Per-level cap** | Unchanged: level-stamped flag mirroring `_centuryUsedFor` (`DegenerusGameStorage.sol:1857-1876`); key on **raw `level`** (one pack per game-level, per the brief). |
| **Score freeze** | Unchanged but now freezes the **boost input**: `cachedScore` at `:1709` → `foilBoostBps` at resolve. Plus freeze the signature seed at buy if the add-on is in. |

Net new on-chain surface vs §4: one sibling producer fn + one boost curve fn + one foil queue path + (optional) one signature mapping + one claim fn. **MintModule has only ~1,116 B headroom** — neither the foil body nor the match-claim body can live there; put them in the JackpotModule (claim-side re-derivation) or a new `GAME_FOILPACK_MODULE`, with only a thin facade stub. Re-measure EIP-170 after adding code.

### 6.5 Updated risks (for roadmapping)

1. **Positional/saturation collapse (NEW headline risk).** Channels 1+2 are *relative* — value assumes gold buckets stay tiny. Cheap foil gold fills them and erodes the edge it sells. **Calibrate the crossover against saturated-supply equilibrium**, not current 0.781% scarcity, or over-promise at high adoption. (`DegenerusGameJackpotModule.sol:1009-1037,1423-1436`).
2. **Frozen shared producers (unchanged, still hard).** `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` are byte-frozen (v70.0 `ffbd7796` / tree `99f2e53f`) and shared by mint AND jackpot winner derivation. A **sibling producer is mandatory**; editing them breaks the audited bytecode invariant and changes gold for ALL products.
3. **Does foil gold COUNT as color==7 in the jackpot?** If `traitFromWordFoil` writes real color-7 traitIds into shared `traitBurnTicket`, foil gold auto-inherits channels 1+2 (zero new wiring) **but dilutes organic-gold holders** and is the saturation vector. Isolating it needs a parallel solo-rotation/deity path. **Decision §6.5-Q3.**
4. **Degenerette EV-flat trap (hard boundary).** Per-N tables are EV-neutral to current rarity (`DegenerusGameDegeneretteModule.sol:281-301`). Foil tickets are burn entries, not Degenerette picks — keep them decoupled. If a future variant fed foil gold into Degenerette picks, the N=4 multipliers become strictly +EV → exploit.
5. **Emergent-EV ungovernability.** No code constant gives a gold trait's payout; channels 1+2 swing with pool size, `DAILY_ETH_MAX_WINNERS=305`, `JACKPOT_LEVEL_CAP=5`. "Crossover at ~300" is only as stable as the stated pool assumptions — state them explicitly; Monte-Carlo, don't derive.
6. **Flat-tail invisibility (carried).** ~98% of every curve's gain lands by score 500 (`ActivityCurveLib.sol:25-29`). Tune the boost ramp into the **60-500 band**; tuning into 500→30000 makes the edge sub-1%.
7. **Score AND signature must be frozen at buy.** Boost from `cachedScore` (`:1709`), signature from a buy-time seed. Any live-read at resolve/claim is grindable once the VRF word lands (same class the lootbox score-freeze guards).
8. **Match add-on draw-gas brick (if push).** A per-draw scan over foil signatures is unbounded by sales inside the gas-sensitive jackpot resolution — **pull/claim only**; keeps `advanceGame` flat.
9. **Enumerable-list leak.** If the add-on keeps a per-level signature *list* (instead of the pull/claim mapping), it must be cleared/ignored after the level or it leaks storage/gas across levels. The mapping + level-stamp idiom avoids this.
10. **Storage append discipline (unchanged).** Frozen foil score/boost-word + one-per-level stamp + (optional) signature must be **appended in `DegenerusGameStorage`** (delegatecall-shared), never in a module, or slot alignment breaks.
11. **Premium routing & combined-buy accounting.** Decide where the premium-over-face routes (next/future pool vs a dedicated bonus pool funding the match add-on). A foil leg in a combined purchase must split `msg.value` explicitly (cf. `buyLootboxAndPresaleBox`) or accounting drifts.
12. **Symbol/gate entropy disjointness.** `traitFromWord` pulls color from low 32 bits, symbol from high 32 bits of one 64-bit word; the foil variant's boost-gate slice must be disjoint from both, or gold correlates with a fixed symbol and the pack-feel CIs (`PackFeel.test.js`) shift.

---

## 7. LOCKED PARAMETERS + DEGENERETTE-STYLE FLIP CLAIM (v71 final design)

> **This section is the FINAL design surface.** It supersedes the open knobs in §6.5 wherever they conflict: price premium, routing, payment source, per-level cap key, and the value-channel set are now LOCKED (user-decided). §6.0-§6.4 trait-rarity mechanics remain load-bearing and valid. The one genuinely-new construct is the **Degenerette-STYLE FLIP claim** (replaces the §6.3 "daily-match add-on" framing with a concrete, code-grounded payout).

### 7.1 Locked parameter table

| Parameter | LOCKED value | Mechanism / how it lands in code | Citation |
|---|---|---|---|
| **Price** | **10× a normal current-level ticket's price**, pack delivers **4 whole tickets** ⇒ effective **+150% premium** over the 4-ticket face (pay-for-10, get-4 = 2.5× per ticket) | Charge `10 × priceForLevel(level)`; queue `ticketQuantity = 1600` (= 4 whole tickets, see §7.2) onto the foil write-path | `PriceLookupLib.sol:21-41`; `DegenerusGameMintModule.sol:1453-1456` |
| **Rarity multiplier** | **×2 @ score 0 → ~×5 @ score ~350 → ×6 @ max score**, on the rare/gold color tiers; **FROZEN at buy** from activity score | A 4-segment `foilBoostBps(score)` curve in `ActivityCurveLib.sol` whose output drives the sibling producer's rare-tail mixing weight; baseline boost is **×2, not ×1** (see §7.2) | `ActivityCurveLib.sol:22-43,54-67`; score read `DegenerusGameMintModule.sol:1709` |
| **Spend pool routing** | **75% next-pool / 25% future-pool** (normal ticket is 90/10) | Fork the mint pool split (`DegenerusGameMintModule.sol:117,201-218`) for the foil leg only; the +150% premium rides the same 75/25 split unless a dedicated bonus pool is chosen for the FLIP claim (§7.3) | `DegenerusGameMintModule.sol:117,201-218` |
| **Payment source** | **Fresh ETH OR claimable** (NOT afking) | Restrict the foil leg's payment waterfall to `MintPaymentKind` ∈ {fresh-ETH, claimable}; reject the afking leg of `_purchaseForWithCached` | `DegenerusGameMintModule.sol:1490-1832` |
| **Per-account cap** | **ONE pack per account per RAW game-level** | Level-stamped flag mirroring `_centuryUsedFor`, keyed on **raw `level`** (NOT `_activeTicketLevel()`); auto-resets per level, no global sweep | `DegenerusGameStorage.sol:1857-1876` |
| **NEW value channel** | **Degenerette-STYLE FLIP payout** foil tickets can claim, gated at **min "4 matches"**, paid in **FLIP** (the coinflip token, formerly BURNIE) | Isolated claim table + producer (§7.3); settle via `coin.mintForGame` (Degenerette-faithful) or `coinflip.creditFlipBatch` (rides daily-flip accounting) | `DegenerusGameDegeneretteModule.sol:445,770-778`; `Coinflip.sol:981-996` |

### 7.2 Ticket-unit exactness + the per-quadrant rarity mechanism

**"10× price / 4 tickets" resolved exactly.** Ticket cost is `ticketCost = priceWei * ticketQuantity / (4 * TICKET_SCALE)`, `TICKET_SCALE = 100` so the divisor is **400** (`DegenerusGameMintModule.sol:1456`, `DegenerusGameStorage.sol:157`). `ticketQuantity` is in **hundredths of a whole ticket**: one WHOLE 4-quadrant ticket = `ticketQuantity 400` ⇒ cost `priceWei * 400 / 400 = priceWei` = exactly `priceForLevel(level)`. The mint loop expands each whole ticket into **4 independent quadrant trait-entries** via offset `(i & 3) << 6` (`DegenerusGameMintModule.sol:754-768`). Therefore:
- **1 whole ticket** = `priceForLevel(level)` ETH = **4 quadrant burn-entries**.
- **The foil pack delivers 4 whole tickets** = `ticketQuantity 1600` = **16 quadrant burn-entries**, for a price of **10 × priceForLevel(level)**.
- "pay-for-10, get-4" = **4 whole tickets (16 quadrant entries) for the price of 10 whole tickets** = **+150% premium over the 4-ticket face**. (NOT one 4-quadrant ticket — that is what 1× already buys.) **The premium IS the low-score penalty** (you overpay 2.5×/ticket for tickets whose rarity edge has not yet ramped in).

**Per-quadrant rarity multiplier (×2 → ×6) on the sibling producer.** The shared frozen producers (`weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed`, `DegenerusTraitUtils.sol:115-178`) MUST NOT be edited (v70.0 FREEZE `ffbd7796`, tree `99f2e53f`, `RngFreezeAndRemovalProofs`). The foil queue swaps the single `traitFromWord(s)` call at `DegenerusGameMintModule.sol:759` for a new sibling `traitFromWordFoil(rnd, multBps)` (+ `packedTraitsFoil` wrapper), modeled on the existing `packedTraitsDegenerette`/`_degTrait` precedent (`DegenerusTraitUtils.sol:201-223`).

The multiplier `M ∈ [2, 6]` (frozen at buy) scales the rare-tier probability mass relative to the frozen baseline PMF (`c7=0.78125%`, `c6=2.344%`, `c5=3.125%`, `c4=6.25%`, `c3=12.5%`, `c0-c2=75%`; widths `64/64/64/32/16/8/6/2` of 256, `DegenerusTraitUtils.sol:115-127`). "All rarer traits more common by a factor M" ⇒ the rare tiers (c3..c7) each scale ≈×M with commons absorbing the deficit:

| Activity score | Rarity mult M | gold c7 (≈ M × 0.781%) | note |
|---:|---:|---:|---|
| 0 | **×2** | **~1.56%** | baseline boost is ×2, NOT ×1 — even a score-0 pack has 2× gold odds; the penalty is the **price premium**, not the trait floor |
| ~350 | **~×5** | **~3.9%** | mid |
| max (≥30000) | **×6** | **~4.7%** | ceiling — **x6 gold ≈ 4.7%/quadrant** (still well below Degenerette's near-uniform 6.667% and the jackpot draw's 12.5%) |

Implementation note: at ×6 the rare tail (c3..c7 baseline mass = 25%) scales to ~150% of its baseline weight — past ~×4 the commons (c0-c2) are exhausted, so the producer must clamp by re-normalizing the rare-tail conditional (the §6.1 "mix-to-rare-tail" `w` gate, where `w` is derived from `M` so that `c7(w) ≈ M × 0.781%`), not by a naive per-tier multiply that would overflow the PMF. **`foilBoostBps(score)` outputs `w` (or `M`), frozen into the foil word at `:1709`, applied at resolve — never live-read** (anti-gaming, same discipline as lootbox/decimator score-freeze).

### 7.3 The Degenerette-STYLE FLIP claim (the new value channel)

**Recommended "min 4 matches" definition — grounded in the real Degenerette structure.** The Degenerette engine scores a player pick vs a freshly-drawn near-uniform result ticket as `S = A + 2H`, `A` = matched ordinary axes (4 color + 3 non-hero symbol), `H` = hero-symbol match, `S ∈ {0..9}` (`_score`, `DegenerusGameDegeneretteModule.sol:999-1026`). The indexer already labels this `S` field "matches" (`FullTicketResult.matches`). The code-faithful reading of **"min 4 matches" = a composite Degenerette score S ≥ 4** on a foil-ticket spin against a freshly-drawn near-uniform result.

- **Probability:** P(S ≥ 4) ≈ **3.5%** (≈3.47% for an N=0 pick down to ≈1.76% for an all-gold N=4 pick), computed against the near-uniform result distribution. P(S ≥ 6) ≈ 0.09%→0.02%.
- **Why this, not the alternatives:** "all 4 quadrants exact vs the daily jackpot draw" = `(1/64)⁴` = **1-in-16.7M (unpayable)**; "N=4 gold quadrants" is a player CHOICE (P=1, degenerate) or an all-gold result draw (`(1/15)⁴`≈2e-5, too rare); cross-pack "4-of-a-kind" has **no native referent** (tickets are independent address-keyed burn entries with no stored signature). S ≥ 4 is the only definition that is payable, codeable, and literally reads the existing "matches" field.

**ISOLATED payout table — DECOUPLED from the EV-flat Degenerette pick tables (MANDATORY).** The five per-N Degenerette base tables (`_getBasePayoutBps`, `DegenerusGameDegeneretteModule.sol:264-301,1069-1131`) are EV-flat (`basePayoutEV = 100 centi-x` per N, numerically verified, max dev 0.0006 centi-x) **only because** the RESULT draw is near-uniform (gold 6.667%) and the higher-N bigger-jackpot exactly offsets the lower pick hit-rate. **Routing foil tickets — whose gold is CHEAP and BOOSTED to ~1.56-4.7% — through those N-indexed tables makes a max-gold (N=4) foil pick strictly +EV** against the 209,164× S=9 tier whose rarity assumes honest scarcity. Therefore the foil FLIP claim **MUST use its OWN producer + its OWN flat (or independently re-calibrated per-N) FLIP schedule + its OWN min-4 (S≥4) predicate**, never `_getBasePayoutBps` and never the live `quickPlay` tables. Foil gold must also NOT be read as `color==7` into the jackpot solo-rotation/deity paths unless those are independently re-tuned (§7.5).

**Claim / settlement path (pull, FLIP rail).** Settlement is **pull/claim**, never a push-scan (a per-draw on-chain loop over foil signatures is unbounded by sales and would brick the 15M-gas `advanceGame`). Two FLIP rails exist:
- **`coin.mintForGame(player, amount)`** — immediate mint, the **Degenerette-faithful** path (Degenerette flushes `acc.flipMint` this way after an optional 50/50 survival flip, `DegenerusGameDegeneretteModule.sol:445,770-778`; `coin = IDegenerusCoin → FLIP.mintForGame`). Recommended.
- **`coinflip.creditFlipBatch(players, amounts)`** (`Coinflip.sol:981-996`, `onlyFlipCreditors`) — pushes into the coinflip's daily-flip accounting via `_addDailyFlip` (the rail the JACKPOT module uses for daily winners, `DegenerusGameJackpotModule.sol:1619-1678,1752`). Use this if the foil claim should ride coinflip daily-settlement like jackpot winnings.

The foil-ticket spin re-derives its result from the retained lootbox/daily RNG word at claim time (`lootboxRngWordByIndex[index]` / `rngWordByDay[day]`, frozen score + frozen spin index in the foil word), so the draw is non-grindable.

**Required claim EV magnitude (from the economics map).** The +150% premium is a **0.4× multiplicative tax** on the whole pack's value (4 delivered / 10-face price): `foil_value_per_ETH = 0.4 × (1 + φ·(M−1))`, where `φ` = gold's share of a normal ticket's EV. To **tie the lootbox at score 300 (= 127.88% EV, byte-exact, `DegenerusGameStorage.sol:1640-1677`)** on rarity ALONE needs `φ ≥ 0.44` (gold would have to be 44%+ of a normal ticket's whole EV). Since gold is only 0.781%/quadrant and ~3.1% of tickets hold ANY gold, the defensible `φ ≈ 0.05-0.20` ⇒ the rarity multiplier needed to cross is **×12 to ×45 — far above the locked ×6 ceiling.** **Rarity alone cannot make the crossover.** The FLIP claim is therefore load-bearing: with `S≥4` at P≈3.5% it must supply essentially the **entire** high-score edge — on the order of **~117 ticket-faces of EV per qualifying match** (≈7 ETH-equivalent FLIP at level 300; ≈1.2 ETH at mid-level) to lift foil@×5/×6 over the lootbox@300 in the base case (φ=0.10). That magnitude **exceeds the 10-face pack price** — see the §7.5 knob-tension flag.

### 7.4 Crossover verdict (does it hold with these knobs?)

**Low-score (foil < ticket): HOLDS, structurally.** At score 0, a 4-ticket foil pack (×2 gold) holds **0.250 expected gold quadrants vs 0.3125 for 10 normal tickets**, AND **6 fewer ticket-faces of common EV** — a strict, unambiguous loss on BOTH channels regardless of how rarity "feels". The premium sets the floor; even at ×2 baseline gold the buyer is worse off than spending the same ETH on normal tickets. ✅

**High-score (foil > lootbox @ ~300-350): does NOT hold on rarity alone; HOLDS ONLY via the FLIP claim.** Verdict from the economics reconciliation: the +150% premium is too steep for ×2→×6 rarity to ever cross a lootbox on rarity alone (needs φ≥0.44 / ×12-45 boost). **The FLIP Degenerette-STYLE claim is the ONLY channel that can close the gap, and it is fully load-bearing.** Stated plainly: **rarity is cosmetic at high score; the FLIP claim is the product.** To land the crossover at ~score 300-350 the claim must contribute ~117 ticket-faces/match at P≈3.5-6% — which is larger than the pack price (a knob-tension red flag, §7.5).

Both rarity channels (solo-rotation + reduced-deity-dilution) additionally **SATURATE**: as cheap foil gold fills gold buckets, per-gold-quad value falls ≈1/occupancy, so even the ×6 edge erodes from ~60% → ~43% of face per ETH as occupancy rises 1×→8×. **Calibrate against a saturated equilibrium, not today's 0.781% scarcity.**

**Calibration = Monte-Carlo (not closed form).** `φ` and per-gold-quad value `V` are emergent (depend on pool sizes, `DAILY_ETH_MAX_WINNERS=305`, `JACKPOT_LEVEL_CAP=5`, cohort competition) — every crossover number is conditional on `φ ∈ [0.05, 0.50]`. **Plan:** simulate cohorts at stated pool-size assumptions; for each, sweep (rarity M-curve, FLIP claim bonus, claim cadence) and locate where realized foil EV (a) < normal-ticket EV at score 0 and (b) > lootbox marginal EV at score 300-350, evaluated at **saturated** gold-bucket occupancy (2×-8× baseline), NOT current scarcity. Output: the FLIP `bonus` magnitude and the `foilBoostBps` curve knees that place the crossover in the 250-500 band (past 500 the curve is flat and the edge is sub-1%, `ActivityCurveLib.sol:25-29`).

### 7.5 Updated integration deltas + risks (FLIP claim + steep premium)

**Integration deltas vs §6.4:**
| Concern | Delta |
|---|---|
| **Price/queue** | Charge `10×priceForLevel(level)`; queue `ticketQuantity=1600` (4 whole tickets) on the foil write-path. Single-ticket math unchanged (`:1456`). |
| **Routing** | Foil leg splits **75/25** (next/future), not 90/10 — fork the pool split for the foil queue only. Decide if the +150% premium also rides 75/25 or funds a dedicated FLIP-claim bonus pool. |
| **Payment** | Restrict to fresh-ETH **or claimable**; **reject afking** for the foil leg. |
| **Per-level cap** | Level-stamped flag on **raw `level`** (one pack/game-level), century idiom (`DegenerusGameStorage.sol:1857-1876`). |
| **Rarity curve** | `foilBoostBps(score)` outputs the multiplier ∈ [2,6] (baseline ×2 at score 0, ~×5 @ 350, ×6 @ max), drives `traitFromWordFoil` mixing weight; frozen at `:1709`. |
| **FLIP claim (NEW)** | Isolated producer + isolated FLIP payout table + `S≥4` predicate; pull/claim re-deriving from retained RNG word; settle via `coin.mintForGame` (or `creditFlipBatch`). NOT routed through `_getBasePayoutBps`. Body in JackpotModule or a new `GAME_FOILPACK_MODULE` (MintModule has only ~1,116 B). |

**Risks specific to the FLIP claim + steep premium:**
1. **KNOB-TENSION RED FLAG (headline).** Under the locked +150% premium, rarity is cosmetic at high score and the FLIP claim becomes ~100% of the pack's value proposition (claim EV ~117 faces > 10-face pack price). The pack is effectively a "lottery-ticket-with-cosmetic-rarity", not a "rarer-tickets" product. If that is not the intended feel, the premium is the lever to revisit (out of scope — LOCKED), so size the FLIP claim deliberately and accept that the claim is the product.
2. **EV-flat coupling (hard boundary).** The FLIP claim is "Degenerette-STYLE" but MUST NOT reuse the per-N quickPlay tables (`DegenerusGameDegeneretteModule.sol:264-301`) — those are EV-flat to honest 6.667% near-uniform result gold; boosted foil gold at N=4 makes the 209,164× tier strictly +EV. Claim EV must be its own isolated `P(match) × bonus` term.
3. **Sub-100% RTP if `roiBps` reused.** Degenerette's `_roiBpsFromScore` is strictly <100% by construction (90.00%→99.90%, the house edge, `DegenerusGameDegeneretteModule.sol:1143-1168`). A foil claim that reuses it inherits the house edge — if the claim is meant to be the net-positive high-score lever it needs its OWN roi/EV curve, not Degenerette's.
4. **Saturation collapse.** Channels 1+2 are positional; cheap foil gold fills buckets and erodes foil@×6 EV/ETH from ~60% → ~43% as occupancy rises 1×→8×. Size the claim at saturated equilibrium, not current scarcity.
5. **Foil-gold dilution of organic holders.** If `traitFromWordFoil` writes real `color==7` into shared `traitBurnTicket`, foil buyers compete in and dilute organic-gold holders' solo-rotation/reduced-deity edge — a fairness decision the design must own (§7.5-Q below).
6. **Draw-gas brick if push-matched.** A per-draw on-chain scan over foil signatures is unbounded by sales inside the gas-sensitive jackpot resolution (15M Phase-1/Phase-2 split) — **pull/claim only**, against retained `rngWordByDay[day]` / `lootboxRngWordByIndex[index]`.
7. **Score (and spin/signature) must be frozen at buy.** Rarity multiplier from `cachedScore` (`:1709`); any claim-side re-derivation must read a buy-frozen seed/index, never a live VRF word — grindable otherwise.
8. **Anchor-1 floor is set by the premium.** The low-score loss holds because the pack delivers 4 faces vs 10 AND fewer gold quads at ×2 — structural, not "felt". Safe under the locked premium.

**Open design choices to confirm (the only genuinely-remaining ones):** (Q1) the exact "min 4 matches" predicate if more than S≥4 is in play; (Q2) whether foil gold counts as real `color==7` in the jackpot solo-rotation/deity channels (auto-inherits value but dilutes organic holders) or is an isolated tier; (Q3) the FLIP claim payout magnitude + cadence (one-shot vs per-eligible-daily-draw) and whether it settles via `mintForGame` or `creditFlipBatch`. See the briefing for framing.

---

## 7.6 MATCH PREDICATE — USER-PINNED (OVERRIDES the §7.3 "S≥4 Degenerette spin" recommendation)

> The §7.3 `S≥4` reading was the "reads existing engine state" interpretation. The USER pinned a DIFFERENT, simpler predicate. §7.3's payout-isolation, pull/claim rail, and FLIP-settlement guidance all still apply; ONLY the match predicate changes. This §7.6 is the LOCKED predicate.

**Locked predicate — "exact quadrant matches vs the day's winning jackpot traits, 2/3/4 ladder, per-ticket independent":**
- The pack delivers 4 whole tickets. **Each ticket's frozen 4-quadrant signature** is compared **positionally** to the day's 4 winning jackpot traits (`mainTraitsPacked`, uniform 1/64 per quadrant, `JackpotBucketLib.sol:281-286`): for quadrant `i`, an **exact match** = `ticket.q[i] == winning.q[i]` (full 6-bit trait = color AND symbol; a color-tier-only / "solo" match does NOT count).
- Count exact matches per ticket → `m ∈ {0..4}`. **Pay a tiered FLIP bonus at m = 2, 3, 4** (nothing at 0 or 1).
- **Each of the 4 tickets is evaluated independently** — no pooling across tickets; a pack can have multiple tickets pay separately.
- The crossover-feel is decoupled from this: the daily draw is **uniform**, so a quadrant matches at **1/64 regardless of the foil rarity boost**. Rarity (jackpot gold positioning) and the FLIP match-lottery are **orthogonal value channels**.

**Per-quadrant match = 1/64; per-ticket match count ~ Binomial(4, 1/64):**

| Exact matches (per ticket) | Probability | per ticket ~1 in | per PACK (≥1 of 4 tickets) |
|---|---:|---:|---:|
| **2 of 4** | ~0.1421% | ~704 | ~0.567% (~1 in 176) |
| **3 of 4** | ~0.001504% | ~66,500 | ~0.0060% |
| **4 of 4** | ~0.0000060% (1/64⁴) | ~16.7M | ~0.0000239% (moonshot) |

So a pack pays *anything* from the claim ~0.57% of the time (2-of-4 is the realistic tier); 4-of-4 is a true headline moonshot. The per-tier FLIP amounts must therefore be **large** to feel worth chasing (and are sized for FUN, not to force an EV crossover — see below).

**Storage (one packed `uint256` per player, century idiom, level-stamped):**
```
mapping(address => uint256) foilRecord
 [ level stamp 32b | sig0 24b | sig1 24b | sig2 24b | sig3 24b | claimed flags 4b | spare ]
   anti-stale reset   four independent 4-quadrant (4×6b) ticket signatures   double-claim guard
```
~132 bits used; one SSTORE at buy, one SLOAD/SSTORE per claim. Auto-resets per level (the one-pack-per-level cap is the throttle). Signatures frozen at buy from a buy-time seed; never recomputed live.

**Eligibility window / cadence:** which day's `mainTraitsPacked` each pack's tickets check against is the remaining cadence knob (§7.5-Q3): one-shot against the pack-level's resolution-day draw (cleanest, bounded) vs re-attemptable per eligible daily draw (more shots, smaller per-tier sizing). Claim re-derives the winning traits from retained `rngWordByDay[day]` — non-grindable.

**Crossover stance (LOCKED, per user "it doesn't have to be good value"):** the worse-than-ticket-at-low / better-than-lootbox-at-high crossover is **directional intent, NOT a proof obligation.** §7.4 shows it cannot hold on rarity alone under the +150% premium; we do **not** inflate the FLIP claim to force it. The FLIP claim is sized for a fun, juicy, rare lottery feel. The pack is a premium gold-chase + FLIP lottery that is deliberately -EV at most scores. Hard requirements remain: no exploit, no solvency hole, isolated FLIP table (no EV-flat coupling), frozen shared producers, buy-time freeze of score + signatures, pull/claim only.

---

## 7.7 MATCH-ELIGIBILITY WINDOW = LEVEL DURATION (activity-driven)

> Resolves the §7.6 open cadence knob ("which day's `mainTraitsPacked` each pack checks against"). LOCKED design: **all 4 tickets are eligible for the ENTIRE level they were bought in** — every daily jackpot draw that resolves while the game sits at that level, against BOTH winning sets per draw (main + bonus). The window is the level's duration in physical draw-days, which is **variable and activity-driven**. Reconciled from the two advance/jackpot subsystem maps against HEAD source.

### 7.7.1 Draws-per-level model (the eligibility window)

A "level" is a PURCHASE phase (`jackpotPhaseFlag=false`) followed by a JACKPOT phase (`jackpotPhaseFlag=true`). A foil ticket's burn-entry lives in `traitBurnTicket[level]` and is matched against **every daily winning-trait set drawn while the game is at that level** — so the eligibility window = the number of daily jackpot resolutions the game runs at one level.

**The unit that matters for matching is the PHYSICAL draw-day, not the logical jackpot-day.** Each physical `advanceGame` new-day pass consumes exactly one VRF word `rngWordByDay[day]` and calls `payDailyJackpot(..., randWord)` once, which rolls ONE main+bonus pair via `_rollWinningTraitsPair(randWord)` (`DegenerusGameJackpotModule.sol:291-302`). The day clock is hard real-time (one productive new-day pass per wall-clock day, rollover 22:57 UTC; `day==dailyIdx ⇒ NotTimeYet`, `DegenerusGameAdvanceModule.sol:219-251`, `GameTimeLib.sol:31-34`). So:

```
distinct (main+bonus) draws per level  =  (purchase-phase physical days, variable ≥1)
                                        +  (jackpot-phase PHYSICAL days, 1–5)
```

- **Purchase phase:** one daily draw per physical day, runs until the prize-pool target fills — `targetMet = _getNextPrizePool() >= levelPrizePool[purchaseLevel-1]` (`DegenerusGameAdvanceModule.sol:494-501`). Variable, floor 1, bounded above only by the 120-day abandonment timeout (`DegenerusGameStorage.sol:1469`).
- **Jackpot phase:** ALWAYS 5 *logical* jackpot-days (`JACKPOT_LEVEL_CAP=5`), but those 5 logical days are credited via `counterStep` and can collapse into **fewer PHYSICAL days**: turbo (`compressedJackpotFlag=2`) ⇒ `counterStep=5` ⇒ **1 physical day = 1 draw**; compressed (`=1`) ⇒ `counterStep=2` ⇒ **~3 physical days = ~3 draws**; uncompressed ⇒ **5 physical days = 5 draws** (`DegenerusGameJackpotModule.sol:304-324`).

**Map reconciliation (which map is right):** Map 1 framed the jackpot phase as "always 5 logical draws / 10 winning sets" for the eligibility window; Map 2 flagged that under turbo/compressed the 5 logical days resolve from a SINGLE `rngWordByDay[day]` word with `counterStep` advancing the counter, so they are NOT 5 independent winning-trait sets. **Map 2 is correct for match-eligibility.** `payDailyJackpot(true, lvl, rngWord)` is called once per PHYSICAL day (`DegenerusGameAdvanceModule.sol:566`); the counter advances by 5/2/1, but only ONE main+bonus pair is rolled per physical call. A turbo jackpot phase therefore exposes a foil ticket to **1 distinct draw**, not 5. Map 1 remains right that 5 *logical* jackpot days are always credited — that governs pool PAYOUT splits, not the count of distinct winning-trait sets a foil signature can match against. **For the foil window, count physical draw-days.**

### 7.7.2 Activity interaction — and the tension to flag

**Higher activity SHORTENS the window ⇒ FEWER match shots.** Both gates push the same direction: (1) faster purchases fill the pool target sooner ⇒ fewer purchase-phase draws; (2) hitting the target within 1 day sets turbo (5 logical jackpot days → 1 physical draw), within 3 days sets compressed (→3). Low activity ⇒ slow fill ⇒ many purchase draws + uncompressed 5 jackpot draws ⇒ a LONG window with many shots.

> **TENSION FLAG — "better at high activity" inverts on THIS channel.** The foil pack's brief direction is "worse than a ticket at low activity score, slightly better than a lootbox at high activity score." The FLIP match-lottery's *number of shots* moves the OPPOSITE way: a high-activity cohort sits in fast/turbo levels with as few as ~2 draw-days, while a low-activity cohort sits in slow levels with 15–20+ draw-days and thus ~10× the match expectation per pack. **The match-lottery channel is structurally better for LOW-activity (slow) levels.** This does NOT break the design — per §7.6 the crossover is directional intent, not a proof obligation, and the activity-score EV crossover is carried by the *rarity boost* (frozen at buy, ×2→×6), which is orthogonal to and unaffected by window length. But the match-lottery should be understood and communicated as a **flat-feel lottery whose shot-count tracks level duration (inverse to activity)**, not as a high-activity reward. If a high-activity holder is meant to get MORE match shots, the cadence must be decoupled from level duration (e.g. a fixed per-pack shot budget) — a knob the user can still set.

### 7.7.3 Realistic per-pack odds table (trials = 4 tickets × 2 sets × draw-days)

Per-quadrant exact match vs a uniform daily winning trait = 1/64. Per ticket (4 quadrants) ~ Binomial(4, 1/64): P(≥2)=0.14345%, P(≥3)=0.0015080%, P(4)=5.96e-8. A pack = 4 tickets; each physical draw-day carries 2 winning sets (main+bonus). Trials per level = `4 × 2 × draw-days`.

| Scenario | draw-days | trials | tier | P(≥1 hit / pack / level) | E[hits / pack / level] |
|---|---:|---:|---|---:|---:|
| **(a) TYPICAL** (~3 purchase + ~4 jackpot physical) | 7 | 56 | 2+ | **7.72%** (1 in 13) | 0.0803 |
| | | | 3+ | 0.0844% (1 in 1,185) | 0.000844 |
| | | | 4 | 0.0003% (1 in ~300k) | 0.0000033 |
| **(b) SHORT / high-activity** (1 purchase + 1 turbo jackpot) | 2 | 16 | 2+ | **2.27%** (1 in 44) | 0.0230 |
| | | | 3+ | 0.0241% (1 in 4,145) | 0.000241 |
| | | | 4 | 0.0001% (1 in ~1.05M) | 0.00000095 |
| **(c) LONG / low-activity** (~15 purchase + 5 jackpot) | 20 | 160 | 2+ | **20.52%** (1 in 5) | 0.2295 |
| | | | 3+ | 0.2410% (1 in 415) | 0.002413 |
| | | | 4 | 0.0010% (1 in ~105k) | 0.0000095 |

*Reference — ONE-SHOT cadence (single resolution-day, main+bonus only, 8 trials):* 2+ = 1.14% (1 in 88), 3+ = 0.0121% (1 in 8,290), 4 = 1 in ~2.1M. (This is the alternative if the cadence is decoupled to a single bounded draw rather than the whole level.)

**Read:** the 2-of-4 tier is the only one a typical buyer realistically ever sees (≈1-in-13 per pack at a typical level, up to ≈1-in-5 at a long level); 3-of-4 is a ~once-per-thousand-packs event; 4-of-4 is a true moonshot (1-in-100k to 1-in-millions depending on window). Window length swings the headline 2+ odds ~9× between the short (2.3%) and long (20.5%) extremes.

### 7.7.4 Storage / claim implication (whole-level eligibility, bounded gas)

The locked §7.6 record — one packed `uint256` per player, level-stamped (century idiom, `DegenerusGameStorage.sol:1857-1876`) holding the 4 frozen 24-bit ticket signatures — **already supports whole-level eligibility without unbounded gas**, with one adjustment to the claimed-flag layout:

- **Eligibility = read-only re-derivation, no per-draw storage.** A claim submits `(day, ticketIndex)`; the contract re-derives that day's `mainTraitsPacked` + `bonusTraitsPacked` from the retained `rngWordByDay[day]` via the same `_rollWinningTraitsPair` (`DegenerusGameJackpotModule.sol:291-302`) and compares positionally to the stored signature. The day's word is already retained, so EVERY draw of the level is re-derivable on demand — no per-draw write, no list, no enumeration. **Draw-side `advanceGame` gas is unaffected (flat); the foil match never touches the resolution loop (pull/claim only).**
- **Double-claim guard for a multi-draw window.** The §7.6 sketch reserved only 4 claimed-flag bits (one per ticket) — that suffices for a one-shot cadence but NOT for whole-level eligibility, where a single ticket could legitimately hit (and claim) on multiple distinct draw-days. Replace the per-ticket flag with a **per-(record, day) claimed marker** so each `(ticketIndex, day)` pair is claimable at most once. Cheapest bounded form: a small `mapping(bytes32 => bool) foilClaimed` keyed by `keccak(player, level, day, ticketIndex)`, or a per-player `mapping(uint => uint256)` bitmap over day-offsets within the level. Either is O(1) per claim and self-bounds because the level-stamp invalidates the whole record at level advance.
- **Expiry at level advance = free.** The `level<<224` stamp means once `level` increments (`_finalizeRngRequest`, `DegenerusGameAdvanceModule.sol:1728-1732`) the entire `foilRecord` reads as stale → all 4 tickets stop being eligible automatically, no sweep. Claims for the just-ended level must therefore either (i) be required before the level advances, or (ii) carry an explicit `claimUntil`/grace window keyed on the stamped level so a player isn't griefed out of an earned match by a fast turbo advance. **Decision needed:** grace window vs claim-before-advance (see §7.7.5 / briefing).

### 7.7.5 New risk (window-specific)

- **Turbo-advance claim griefing (NEW).** Whole-level eligibility + free per-level expiry means a high-activity cohort can collapse the entire jackpot phase into a single turbo physical day and advance the level in ~2 real days. A foil holder who matched on an early draw but hasn't claimed before `level++` loses the claim when the stamp invalidates the record (§7.7.4). Mitigate with an explicit stamped grace window (claim the *previous* level's record for N days after advance) or require claim-before-advance. Without one, the shortest (high-activity) windows are also the most claim-hostile — compounding the §7.7.2 inversion against high-activity holders.
- **Calendar-days ≠ draw-days (carried).** VRF stalls / `_backfillGapDays` (`DegenerusGameAdvanceModule.sol:1879`) fill `rngWordByDay` for skipped days but those days run no fresh distribution; re-derivation from the retained word is still correct, but do not equate elapsed real days with eligible draws when sizing or displaying odds.

---

## 7.8 FLIP MATCH-PAYOUT SIZING ANCHORS

> Sizes the §7.6/§7.7 2/3/4 FLIP bonus against real, code-grounded FLIP payouts that already exist in the game. The match predicate (exact quadrant matches vs the day's winning jackpot traits) and the whole-level eligibility window are LOCKED (§7.6, §7.7); this section sizes ONLY the FLIP amounts. FLIP = the coinflip token (formerly BURNIE).

### 7.8.1 FLIP value anchor (what 1 FLIP is worth)

FLIP is pegged protocol-wide to **exactly 1/1000 of a whole ticket**: every FLIP↔ETH conversion uses `FLIP-per-ETH = PRICE_COIN_UNIT / mintPrice = 1000 ether / priceForLevel(level)` (`sDGNRS.sol:350-351,822`; daily-jackpot budget `DegenerusGameJackpotModule.sol:1828`; deity-pass conversion `DegenerusGameBingoModule.sol:69`). So **1,000 FLIP == 1 whole-ticket face**, and 1 FLIP == 1/1000 of a ticket-face at every level. In ETH that floats with the level price:

| Level price | 1 FLIP in ETH | 1,000 FLIP (1 face) | 5,000 FLIP (5 faces) |
|---|---:|---:|---:|
| 0.01 (L<5) | 0.00001 | 0.01 ETH | 0.05 ETH |
| 0.04 (cycle base) | 0.00004 | 0.04 ETH | 0.20 ETH |
| 0.08 (cycle ×2) | 0.00008 | 0.08 ETH | 0.40 ETH |
| 0.24 (x00 milestone) | 0.00024 | 0.24 ETH | 1.20 ETH |

FLIP is **backed/redeemable, not a pure points token**: sDGNRS holds a real FLIP reserve and burning sDGNRS pays a proportional whole-FLIP share alongside ETH+stETH (`sDGNRS.sol:101,1070-1077`), and most circulating FLIP first survived a 50/50 coinflip (won supply, not free emission). Sizing implication: a flat FLIP tier auto-scales **24× in ETH** between an L<5 level (0.01 ETH/face) and an x00 milestone (0.24 ETH/face) — quote tiers in **ticket-faces** (FLIP/1000) to keep the *feel* level-stable, and accept the ETH float, OR denominate per-level if a fixed-ETH feel is wanted (decision §7.8.6-D2).

### 7.8.2 Emission baseline (what "normal" FLIP emission looks like)

There is **no single "FLIP per day" constant** — emission is demand-driven:
- **Daily FLIP jackpot (game-wide):** budget = 0.5% of the level prize-pool target repriced to FLIP = `levelPrizePool[lvl-1] × 1000 / (priceWei × 200)` (`DegenerusGameJackpotModule.sol:1822-1828`), ≈ **25,000–50,000 FLIP/day game-wide**, split across ≤50 near-future + ≤10 far-future winners. **Per winner ≈ 375–750 FLIP (near) / 625–1,250 FLIP (far)** — this is the most common FLIP a holder ever receives (`:201,204,1550,1613`).
- **Affiliate FLIP:** ~**200 FLIP per whole ticket** sold on fresh ETH (20% L4+, `DegenerusAffiliate.sol:183-185`); volume-driven, paid as a staked flip credit.
- **Bingo (fixed):** regular **1,000 FLIP** (1 face), symbol-first **2,000 FLIP** (2 faces), quadrant-first **5,000 FLIP** (5 faces) (`DegenerusGameBingoModule.sol:56-60`).
- **Bootstrap seed (one-time):** 200k FLIP/day × 20 days × {VAULT, sDGNRS} = 8M FLIP **staked** (≈4M realized after the 50/50), but largely **non-circulating** (VAULT escrow + sDGNRS rebuy-lock) (`Coinflip.sol:154-207`).

**Net character:** outside the bootstrap window the circulating supply is near-zero-sum to mildly deflationary (every coinflip/decimator/Degenerette wager burns principal up front). The foil FLIP claim mints to **ordinary player wallets via `coin.mintForGame` — fully circulating, immediate, no survival-flip haircut** (§7.3) — so each foil FLIP has a larger circulating-inflation footprint per token than seed FLIP. **Judge foil emission against the ~25–50k FLIP/day daily-jackpot baseline.**

### 7.8.3 Typical-payout anchor table (the comparables, smallest → biggest)

| Anchor (real, in-game) | FLIP amount | ETH-equiv (faces) | Frequency | Source |
|---|---:|---|---|---|
| Daily FLIP jackpot — near winner | ~375–750 | ~0.4–0.75 faces | daily, ≤50 winners | `JackpotModule.sol:201,1550` |
| Daily FLIP jackpot — far winner | ~625–1,250 | ~0.6–1.3 faces | daily, ≤10 winners | `JackpotModule.sol:204,1613` |
| **Bingo regular** | **1,000** | **1.00 face** | per first-fill claim/level | `BingoModule.sol:56` |
| **Bingo symbol-first** | **2,000** | **2.00 faces** | rarer per-level | `BingoModule.sol:57-58` |
| **Bingo quadrant-first** (bingo top tier) | **5,000** | **5.00 faces** | rarest per-level | `BingoModule.sol:59-60` |
| Degenerette S=4 small (100-FLIP spin) | ~777 | ~0.8 face | P(S≥4)~3.5%/spin | `DegeneretteModule.sol:281` |
| Degenerette S=6 nice (100-FLIP spin) | ~10,130 | ~10 faces | P(S≥6)~0.09%/spin | `DegeneretteModule.sol:281` |
| Degenerette S=7 big (100-FLIP spin) | ~51,940 | ~52 faces | rare | `DegeneretteModule.sol:289` |
| Degenerette S=9 jackpot (100-FLIP spin) | ~10.6M (N0) – 20.9M (N4) | ~10,600–20,900 faces | true moonshot | `DegeneretteModule.sol:289-293` |
| Coinflip win (multiplier, not fixed) | stake × ~2 | doubles stake | daily 50/50 | `Coinflip.sol:864-883` |

**The fixed-amount anchors to size against are Bingo (1k/2k/5k) and the daily jackpot (375–1,250).** Degenerette is used only for the *shape* of the high tiers (its per-N tables are EV-flat by calibration and MUST NOT be reused — §7.3).

### 7.8.4 PROPOSED 2/3/4 FLIP ladder

Match frequencies are **fixed by the uniform 1/64 daily draw** and are **orthogonal to the rarity boost** (§7.6): a quadrant matches at 1/64 no matter the foil multiplier. Per §7.6/§7.7.2 these tiers are sized **for FUN (a juicy, rare lottery feel), NOT to force the EV crossover** — that is carried separately by the ×2→×6 rarity boost. The realistically-paid tier is **2-of-4** (~1-in-13/pack at a typical level, up to ~1-in-5 long, §7.7.3); 3-of-4 is ~once-per-thousand-packs; 4-of-4 is a true moonshot.

| Tier | Per-pack odds (typical→long) | **PROPOSED FLIP** | ETH-equiv @0.01 / @0.08 / @0.24 | Anchored to | Feel |
|---|---|---:|---|---|---|
| **2 of 4** | 1-in-13 → 1-in-5 | **3,000** | 0.03 / 0.24 / 0.72 ETH | Bingo regular→symbol (1–2k) + a few daily-jackpot wins | "nice small win, see it most levels" |
| **3 of 4** | 1-in-1,185 → 1-in-415 | **40,000** | 0.40 / 3.2 / 9.6 ETH | Degenerette S=6/S=7 big pop (10k–52k) | "rare pop, talked about" |
| **4 of 4** | 1-in-300k → 1-in-105k | **3,000,000** | 30 / 240 / 720 ETH | Degenerette S=9 jackpot class (10–20M) | "headline moonshot" |

Ratio = **1 : 13.3 : 1,000** (2:3:4). This keeps the realistically-paid 2-of-4 tier at the **Bingo / few-daily-jackpot-wins** scale (so routine foil emission stays small), 3-of-4 at the **rare-but-seen Degenerette-big** scale, and 4-of-4 at the **S=9-jackpot moonshot** scale — all three sit **inside the band of FLIP payouts that already exist** in the game.

**Bracketing alternatives** (if the product owner wants tamer or juicier):
- **Conservative ("A"):** 2,000 / 25,000 / 1,000,000 — 2-of-4 = a single bingo claim, 4-of-4 capped at ~the seed-emission scale.
- **Juicy ("C"):** 5,000 / 75,000 / 10,000,000 — 2-of-4 = bingo quadrant-first (5 faces), 4-of-4 = full S=9 N=0 jackpot. Higher variance; the 4-of-4 alone = a full day of game-wide emission.

All amounts are **whole FLIP** (every FLIP credit floors to 1 ether — sub-1-FLIP payouts evaporate; the tiers are far above the floor).

### 7.8.5 Per-pack EXPECTED FLIP cost (the real emission driver)

The headline tier amounts are large, but the **expected** FLIP per pack is tiny because the odds are long. Using exact-tier probabilities (binomial(4, 1/64) per ticket-trial; trials = 4 tickets × 2 sets × draw-days, §7.7.3) and the **proposed mid ladder (3,000 / 40,000 / 3,000,000)**:

| Level scenario | draw-days | trials | **E[FLIP / pack]** | in faces |
|---|---:|---:|---:|---:|
| **SHORT** (high-activity, 2 dd) | 2 | 16 | **~81 FLIP** | 0.08 |
| **TYPICAL** (~7 dd) | 7 | 56 | **~282 FLIP** | 0.28 |
| **LONG** (low-activity, ~20 dd) | 20 | 160 | **~806 FLIP** | 0.81 |

For the bracketing ladders, typical-level E[FLIP/pack] = **~183** (conservative A) / **~282** (mid B) / **~494** (juicy C). **Even the juicy ladder costs < 0.5 ticket-faces of expected FLIP per pack at a typical level** — small next to the 10-face pack price (which is paid in ETH and routed to pools, not refunded as FLIP). Note the **inversion** flagged in §7.7.2: a LONG (low-activity) level costs ~3× the expected FLIP of a SHORT (high-activity) level, because it has more draw-days and thus more shots — the match-lottery emits MORE to slow/low-activity levels.

### 7.8.6 AGGREGATE emission vs the daily baseline — is this material to FLIP supply?

**Assumption (stated):** foil packs are capped at **one per account per level** (§7.1), so cohort size = number of distinct buyers per level. Adoption tiers modeled: **50 / 200 / 1,000 packs per level**, at a TYPICAL ~7-draw-day level, expected FLIP spread over the level's draw-days, compared to the **25,000–50,000 FLIP/day** game-wide daily-jackpot baseline (§7.8.2):

| Packs/level | Ladder | E[foil FLIP]/level | /day | **% of 25–50k/day baseline** |
|---:|---|---:|---:|---|
| 50 | mid (B) | ~14,100 | ~2,000 | **4–8%** |
| 50 | juicy (C) | ~24,700 | ~3,500 | **7–14%** |
| 200 | mid (B) | ~56,400 | ~8,060 | **16–32%** |
| 200 | juicy (C) | ~98,800 | ~14,100 | **28–56%** |
| 1,000 | mid (B) | ~282,100 | ~40,300 | **81–161%** |
| 1,000 | juicy (C) | ~493,900 | ~70,600 | **141–282%** |

**Verdict:** at **modest adoption (≤200 packs/level)** the proposed mid ladder adds **a few-to-30% on top of the daily-jackpot baseline** — material but not dominant, and partly offset by coinflip/decimator burns. At **heavy adoption (1,000 packs/level)** the mid ladder **roughly equals or exceeds** the entire daily jackpot — it becomes a primary FLIP emission source, and the juicy ladder 2–3×'s the baseline. **The 2-of-4 tier drives ~all of the expected cost** (it fires ~100× more often than 3-of-4); 3-of-4 and 4-of-4 are negligible in *expectation* but carry **tail variance**: a single 4-of-4 hit pays 3M (mid) or 10M (juicy) FLIP = roughly a **full day** of game-wide emission in one claim. P(any 4-of-4 in a level) ≈ 0.017% (50 packs) → 0.33% (1,000 packs) — rare, but a lumpy supply event when it lands.

**Sizing levers if the aggregate is judged too rich:**
1. **Lower the 2-of-4 tier** (it is ~all the expected cost): 3,000 → 2,000 cuts aggregate ~33%.
2. **Cap the 4-of-4** (e.g. 1M instead of 3–10M) to bound the tail-variance lump without touching the routine tier.
3. **One-shot cadence** instead of whole-level eligibility (§7.7.3 reference row): collapses trials from `4×2×dd` to 8, cutting expected emission **~7× at a typical level** and removing the low-activity-level inversion — at the cost of far fewer match shots (2-of-4 drops to ~1-in-88/pack).
4. **`creditFlipBatch` rail instead of `mintForGame`** (§7.3): a staked credit only realizes on a winning coinflip day (~50%), roughly **halving** realized emission and inheriting the recycle/burn dynamics — at the cost of the Degenerette-faithful immediate-mint feel.

---
