# 445 SPEC — Section E: Entrypoints + Match + Payout + Calibration + Placement

> Build-ready entrypoint half of the v71.0 Foil Pack design-lock. Every signature, ordered body,
> match predicate, payout lane, calibration figure, and module-placement call below is the
> RESEARCH.md §E/§B/§F/§G reconciled-and-corrected form (V2/V3 PASS, with the corrected anchors:
> the 400-scale ticket queue, `dailyHeroWagers[day-1]`, the ETH-cap clone at `:877-915`, and the
> unified `foilMatchClaimed` marker). An IMPL-446 author writes `buyFoilPack` + `claimFoilMatch`,
> the LIVE/HERO-FREE predicate, the 40/40/20 payout, and stands up `GAME_FOILPACK_MODULE` with
> **zero** further decision. Consumed by Plan 04's consolidation.
>
> Scope: this section is paper-only. It pins the two entrypoint signatures, their ordered module
> bodies, the winning-set re-derivation, the isolated payout schedule, the ≈2-faces/pack/30d
> calibration confirm, and the new-module placement under EIP-170. HARD CONSTRAINT:
> `contracts/*.sol` is read-only; nothing here edits a `.sol`. All Solidity identifiers below are
> named in directive prose — no fenced contract bodies.
>
> Conventions: a **foil signature** is a packed `uint32` `[QQ][CCC][SSS]`×4 in the **identical byte
> layout** as `packedTraitsFromSeed` / `packWinningTraits`, so the match predicate is a direct byte
> compare. `level` = the raw `uint24 public level` (`DegenerusGameStorage.sol:236`);
> `_activeTicketLevel()` = the rng-lock-aware variant used only for ticket queueing.

---

## E.1 `buyFoilPack()` — facade stub + module body (FOIL-02, FOIL-03, FOIL-04, MATCH-03 record write)

### Facade stub (thin, on `DegenerusGame`)

Pin the facade entrypoint **`function buyFoilPack() external payable`** — **no parameters**. The
pack is fully determined by `(msg.sender, level, msg.value)`: one fixed SKU (4 foil tickets) at one
fixed price for the current raw level. The `payable` modifier carries the fresh-ETH leg; a
zero-value call is the claimable-funded path. The stub follows the established thin-facade pattern
verbatim — **template `buyPresaleBox` at `DegenerusGame.sol:614-629`**: resolve the player, then
`GAME_FOILPACK_MODULE.delegatecall(abi.encodeWithSelector(...))`, then `_revertDelegate(data)` on
failure. All foil logic lives in the module; the facade carries no state and no branching.

### Module body `_buyFoilPack(address buyer, uint256 ethSent)` — IN ORDER

1. **Liveness / phase gate.** First statement: `if (_livenessTriggered()) revert E();` — the same
   guard `_queueTicketsScaled` enforces at `:649`. No foil buy after liveness.

2. **One-per-RAW-level cap (FOIL-01).** Load `uint24 lvl = level;` then revert when
   `_foilBoughtThisLevel(buyer, lvl)` (Section D: the `foilRecord` stamp read — a stale stamp from a
   prior level reads "not bought", giving a fresh allowance at the new level, century-flag
   semantics). **The stamp write happens in step 6, AFTER the price settles**, so a reverting buy
   leaves no flag behind. Keyed on **raw `level`**, never `_activeTicketLevel()`.

3. **Price + payment classification (FOIL-02, FOIL-03).** Price is
   **`uint256 cost = 10 * PriceLookupLib.priceForLevel(lvl);`** — the 10× foil price (FOIL-02).
   Reuse the `_processMintPayment` accounting **shape** (`DegenerusGameMintModule.sol:236-299`) but
   **REJECT the afking leg** via the residual:
   - `uint256 ethUsed = ethSent < cost ? ethSent : cost;` (overpay is ignored).
   - `uint256 remaining = cost - ethUsed;`
   - If `remaining != 0`: `uint256 claimable = _claimableOf(buyer); uint256 avail = claimable > 1 ? claimable - 1 : 0; if (remaining > avail) revert E();`
     — **this `revert E()` IS the afking-rejection guard.** The normal mint path silently taps the
     afking principal at `:288`; the foil path requires the entire residual be covered by the
     claimable half (`claimableUsed == remaining`) and **rejects** any reliance on afking funds
     (FOIL-03, threat T-445-E3).
   - **Storage write:** `_debitClaimable(buyer, remaining);` then a separate
     `claimablePool -= uint128(remaining);` statement. `_debitClaimable` (`:941`) touches **only the
     claimable half — never `_debitAfking` (`:956`)**. The `claimablePool` decrement is its own
     statement per the `:898-899` precedent.

4. **Pool split — fork to 75 / 25 (FOIL-04).** The foil leg routes **75% to the next pool / 25% to
   the future pool**, the inverse of the normal 90/10 ticket split. Introduce the NEW constant
   **`FOIL_TO_FUTURE_BPS = 2500`** — **NOT** the shared `PURCHASE_TO_FUTURE_BPS = 1000`:
   - `uint256 prizeContribution = cost; uint256 futureShare = (prizeContribution * FOIL_TO_FUTURE_BPS) / 10_000; uint256 nextShare = prizeContribution - futureShare;`
   - **Storage write** through the frozen/unfrozen branch of `_recordMintPayment`
     (`DegenerusGameMintModule.sol:201-217`) **verbatim**: when `prizePoolFrozen` route to
     `_setPendingPools(...)`, else `_setPrizePools(...)`. **Only the bps constant is forked
     (`FOIL_TO_FUTURE_BPS`); the routing branch is reused unchanged.**

5. **Boost freeze (RARE-03).** Compute the buy-time activity score ONCE and freeze the multiplier:
   - `score = _playerActivityScore(buyer, ...)` — the **same `_playerActivityScore` source the mint
     path freezes as `cachedScore`** (`DegenerusGameMintModule.sol:1709`; definition
     `DegenerusGameMintStreakUtils.sol:267`, returns whole points).
   - `uint16 multBps = uint16(ActivityCurveLib.foilBoostBps(score));` (range `20000..60000`,
     Section C). **Frozen into `foilRecord` at step 6 and NEVER live-read at resolve** (RARE-03).

6. **Roll 4 foil signatures + write the record (MATCH-01, RARE-01/04).** The rarity boost is applied
   **HERE, at buy**, against the sibling producer:
   - `uint256 seed = uint256(keccak256(abi.encode(buyer, lvl, FOIL_SEED_TAG)));` — a **deterministic,
     frozen seed** (`FOIL_SEED_TAG` is a new domain constant). **No live RNG at buy.**
   - For `i in 0..3`:
     `uint32 sig_i = DegenerusTraitUtils.packedTraitsFoil(uint256(keccak256(abi.encode(seed, i))), multBps);`
     (the §A/E.4 sibling of `packedTraitsDegenerette` `:201`; tapered color, symbol uniform 1/8).
   - **Storage write:** `foilRecord[buyer] = pack(stamp = lvl, multBps, sig0..3);` — a **single
     SSTORE** in the Section D layout. This one slot is **both** the per-RAW-level cap flag (step 2
     reads its stamp) **and** the frozen signature/boost record (claim reads its sigs + `multBps`).

7. **Enter the 4 tickets into the REGULAR jackpot (FOIL-05).** Queue at the active ticket level so
   the foil tickets share `traitBurnTicket[level][traitId]` eligibility (`:442`):
   - **`_queueTicketsScaled(buyer, _activeTicketLevel(), 400, false);`**
   - **CORRECTION — STATE EXPLICITLY (V3 DEFECT E-α, off-by-scale):** the third argument is
     `quantityScaled` in **`TICKET_SCALE = 100` units** (`DegenerusGameStorage.sol:157, :663`), so 4
     whole foil tickets require **`400` (= 4 × 100)`, NOT `4`**. Passing `4` would queue 0.04 of a
     ticket. This corrected `400` is the load-bearing pin of this step.
   - **External effects:** emits `TicketsQueuedScaled`; pushes `ticketQueue[wk]`; writes
     `ticketsOwedPacked[wk][buyer]`.
   - **Trait-resolution note for IMPL (mechanism is a 446 detail, the producer is pinned here):** the
     queue-resolution path that today calls `packedTraitsFromSeed` (heavy-tail) MUST, for foil-owed
     entries, resolve via `packedTraitsFoil(seed, multBps)` so the on-chain jackpot traits carry the
     boosted gold odds (real `color == 7`). The frozen `multBps` is the input; the v70-frozen
     producers are **NOT edited** (foil entries route to the sibling). Whether IMPL uses a parallel
     foil-owed queue or a per-entry boost tag is a 446 choice; the SPEC fixes producer =
     `packedTraitsFoil` and multiplier = the frozen `multBps`.

8. **No FLIP / WWXRP / whale-pass mint at buy.** `buyFoilPack` is pure cost-in. All rewards flow
   only through `claimFoilMatch`. **External calls in `buyFoilPack`: none beyond the
   facade→module delegatecall** — every effect is a local storage write.

---

## E.2 `claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind)` — pull/claim (MATCH-03)

### Signature decision

Pin **`function claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind) external`**, keyed
per `(day, drawKind, ticketIndex)` with `drawKind ∈ {0 = main, 1 = bonus}` taken **explicitly** (no
internal loop). 2 draws × 4 tickets ⇒ 8 independent claimables per day; the sparse `foilMatchClaimed`
marker is 1:1 with each claim, keeping gas bounded. (A multi-claim batcher is an additive,
out-of-scope nicety.)

### Module body — IN ORDER

1. **Bounds + record load.** `require(ticketIndex < 4); require(drawKind < 2);` Resolve the
   record-of-level `recLevel` and load
   `(bool present, uint16 multBps, uint32[4] sigs) = _foilRecordFor(msg.sender, recLevel);` then
   `require(present);`. Records persist per-level (MATCH-05): keyed by player and stamped `recLevel`;
   a fast `level++` cannot grief — the record is not auto-wiped until the SAME player re-buys, itself
   gated by E.1 step 2.

2. **Eligibility window (MATCH-02).** `require(day` falls within `recLevel`'s draw-day span`)`. A
   foil pack is claimable across the WHOLE level (the day's level-of-record equals `recLevel`); the
   window is read from the stamp, never a live `level` compare.

3. **RNG availability.** `uint256 rw = rngWordByDay[uint24(day)]; require(rw != 0);` (`:462`; the
   retained daily VRF — the re-derivation source, **never live-read** elsewhere).

4. **Double-claim guard (MATCH-05) — set BEFORE payout (CEI).** Compute the unified marker
   **`bytes32 mk = keccak256(abi.encode(msg.sender, recLevel, day, drawKind, ticketIndex));`** then
   `require(!foilMatchClaimed[mk]); foilMatchClaimed[mk] = true;`. **Use the unified name
   `foilMatchClaimed` (NOT `foilClaimed`)** — V3 DEFECT E-γ name unification. The mark is written
   before any payout effect (checks-effects-interactions).

5. **Re-derive the day's winning sets (E.3).** Build both the LIVE (hero-overridden) set and the
   HERO-FREE pure-VRF set for the requested `drawKind`. (Section E.3 below.)

6. **Count positional matches (MATCH-03).** Quadrant `q` matches **iff
   `foilQuad_q == winQuad_q` as the full 6-bit `[CCC][SSS]`** — color AND symbol. **Color-only does
   NOT count; a positional / wrong-quadrant match does NOT count** (both sides carry `[QQ]` so a
   same-trait-different-quadrant pair never collides). Compute `liveCount` (against LIVE) and
   `heroFreeCount` (against HERO-FREE).

7. **Tier resolution (MATCH-09 — steer-proof gate).** (Section E.3 below; gated on `heroFreeCount`
   for the 4-of-4 tier.) `if (tier == 0) revert E();`.

8. **Pay the tier (E.5)** via the isolated foil schedule; for the 4-of-4 tier also
   `whalePassClaims[msg.sender] += 1;` (`:1122`, the EXISTING slot — do NOT re-declare).

REQ tags locked in this section: **FOIL-02** (10× price), **FOIL-03** (afking-rejection guard),
**FOIL-04** (`FOIL_TO_FUTURE_BPS = 2500`, the 75/25 fork), **MATCH-03** (full 6-bit positional
count, color-only excluded).

---

## E.3 The crux — winning-set re-derivation (LIVE vs HERO-FREE) (MATCH-09, SEC-01 basis)

### Producer substrate — `getRandomTraits`, flat uniform 6-bit slice

The daily winning set is produced by **`JackpotBucketLib.getRandomTraits(uint256 rw)`
(`JackpotBucketLib.sol:281-286`)** — a **flat uniform 6-bit slice per quadrant**: each quadrant is
`(rw >> 6q) & 0x3F` with the quadrant bits OR'd in, packed `[QQ][CCC][SSS]`. **Both the color
(`CCC`, high 3 bits) and the symbol (`SSS`, low 3 bits) are uniform `1/8`.** This is materially
different from the producers the foil **tickets** use: the winning set does **NOT** apply
`weightedColorBucket` (the heavy-tail color ladder) and does **NOT** apply `_degTrait` (near-uniform
degenerette). It is a third, pure-uniform model on all 6 bits.

**Consequence — the foil rarity boost CANCELS in the match channel.** Per-quadrant exact
`[color | symbol]` match probability is `(1/8 color) × (1/8 symbol) ≈ 1/64 ≈ 1.5625%`, **independent
of `multBps`**: the ticket's boosted color distribution sums to 1 against a flat `1/8` winning-color
weight, so the boost factors out. The rarity boost changes the tickets' own jackpot-gold
participation (§1) but **does NOT change match-lottery odds** (key MATCH-10 / §G calibration fact —
`q = 1/64` for all M).

### Per-`drawKind` base word

Pin the base word per draw, mirroring `_rollWinningTraits` (`:1760-1769`):

```
r = (drawKind == 1) ? EntropyLib.hash2(rw, uint256(BONUS_TRAITS_TAG)) : rw;
```

Main (`drawKind == 0`) uses `rw` directly; bonus (`drawKind == 1`) uses the keccak-domain-separated
`hash2(rw, BONUS_TRAITS_TAG)` → independent base traits and hero colors. (Two i.i.d.-distributed
winning sets per day, correlated only through the shared hero symbol; see below.)

### The two re-derived sets (mirroring `_rollWinningTraits`, `:1760-1769`)

1. **HERO-FREE pure-VRF set — NO `_applyHeroResult`:**
   `uint8[4] heroFreeW = JackpotBucketLib.getRandomTraits(r);` then
   `uint32 heroFreeSet = JackpotBucketLib.packWinningTraits(heroFreeW);`. This is the un-steerable
   substrate; `heroFreeW[heroQuadrant]` still holds the VRF symbol, **never** the steered one.

2. **LIVE (hero-overridden) set — HERO-FREE with `_applyHeroResult`:**
   `(bool hasHero, uint8 hQ, uint8 hSym) = _rollHeroSymbol(dailyIdxFor(day), rw);` (hero entropy is
   the unsalted day word `rw`, `:1768`), then start from a copy `uint8[4] liveW = heroFreeW;` and
   apply `_applyHeroResult(liveW, r, hasHero, hQ, hSym);` (`DegenerusGameJackpotModule.sol:1316-1341`).
   The override rewrites **ONLY `liveW[heroQuadrant]`** — color re-sampled from `r`'s low bits,
   symbol set to the steered `heroSymbol`. **Every non-hero quadrant byte is identical to
   HERO-FREE.** Pack `uint32 liveSet = JackpotBucketLib.packWinningTraits(liveW);`. When `total == 0`
   (no wagers), `_applyHeroResult` is a no-op and LIVE collapses to HERO-FREE.

### CRITICAL IMPL anchor — read `dailyHeroWagers[day-1]`

`_rollHeroSymbol` reads `dailyHeroWagers[dailyIdx]` where **`dailyIdx == day - 1`** — the prior-day
wager pool, because the index is frozen at the previous day's slot when the jackpot is processed
(verified `DegenerusGameJackpotModule.sol:1290-1291`, set at AdvanceModule). **Therefore
`claimFoilMatch(D)` MUST read `dailyHeroWagers[D-1]`.** The pool is retained storage
(`:1841`), so the hero `(quadrant, symbol)` is **fully reconstructible** at claim time. Pin
`dailyIdxFor(day) == day - 1` as the IMPL anchor.

### Main vs bonus — shared hero symbol

`_rollWinningTraitsPair` (`:1778-1795`) forces the **same hero `(quadrant, symbol)`** onto both main
and bonus via ONE `_rollHeroSymbol(dailyIdx, randWord)`; only the base word `r` differs (main `rw` /
bonus `hash2(rw, BONUS_TRAITS_TAG)`) and the hero *color* is re-sampled per roll. The re-derivation
must reuse the same `(hQ, hSym)` for both `drawKind` values of a given day.

### Tier gate (MATCH-09 — steer-proof)

Pin the tier resolution from `liveCount` / `heroFreeCount`:

| Tier | Condition | Channel |
| --- | --- | --- |
| 2-of-4 | `liveCount == 2` | LIVE (bounded hero edge KEPT) |
| 3-of-4 | `liveCount == 3` | LIVE (bounded hero edge KEPT) |
| 4-of-4 | **`heroFreeCount == 4` ONLY** | HERO-FREE pure-VRF (steer-proof) |
| none | else | `tier == 0 ⇒ revert E();` |

- **2-of-4 / 3-of-4 are taken off `liveCount`** — the bounded hero edge is intentionally KEPT (a
  steered hero symbol can carry one quadrant on LIVE).
- **4-of-4 is gated ONLY on `heroFreeCount == 4`** — a steered hero shifts at most **one** quadrant's
  symbol on LIVE, so a steerer reaches at most **3-of-4** on LIVE and **never** `heroFreeCount == 4`.
- **Edge case:** if `liveCount == 4` arises only via the hero override but `heroFreeCount == 3`, the
  claim pays the **3-of-4** tier — the 4-of-4 gate is `heroFreeCount`, never `liveCount`.

### SEC-01 consequence (design basis)

A steerer controls only the **`heroSymbol` of `liveW[hQ]`** — one quadrant's symbol on the LIVE set;
`heroFreeCount` is computed on pure VRF (untouchable). Maximum steered contribution is `+1` to
`liveCount`. The **4-of-4 whale-pass moonshot (gated on `heroFreeCount == 4`) is un-steerable and
non-stackable** (threat T-445-E1). This is the **SEC-01 design basis** (steer-proof 4-of-4); the
property is attested downstream at phase 448.

REQ tags locked in this section: **MATCH-09** (the LIVE/HERO-FREE split + steer-proof tier gate),
**SEC-01** (design basis — the 4-of-4 `heroFreeCount == 4` gate, at-most-3-of-4-via-steer bound).

---

## E.5 Isolated payout lanes (MATCH-04, MATCH-06, MATCH-07, MATCH-08, SEC-02 basis)

### (A) Isolated tier→faces schedule — MUST NOT route through Degenerette `quickPlay`

The foil claim **owns its own tier→faces table**. It **MUST NOT** route through the EV-flat
Degenerette `quickPlay` tables — those become **+EV under boosted foil gold** and would break the
calibration. **`1 face = 1,000 FLIP = priceForLevel(recLevel) ETH`** (fixed FLIP peg; ETH-per-face
floats with level).

| Tier | Faces | Extra |
| --- | --- | --- |
| 2-of-4 | **5 faces** | — |
| 3-of-4 | **65 faces** | — |
| 4-of-4 | bonus spin (~1,000 faces) | **`whalePassClaims[player] += 1`** (the EXISTING `:1122` slot) |

The 4-of-4 tier grants a half whale pass via `whalePassClaims[msg.sender] += 1;` (`:1122`,
pool-neutral deferred grant, settled later via `DegenerusGameWhaleModule.sol:991-995`) **PLUS** a
bonus spin. **No ETH leaves at claim for the pass leg** (MATCH-07). These base values are the locked
D-05 calibration target (§G confirms ≈2 faces/pack/30d) (MATCH-04).

### (B) Disjoint entropy lanes off `rw` (MATCH-08)

Pin three separate keccak domains, independent of each other AND of the match lane (which consumes
`getRandomTraits(r)` bit-slices + the `_rollHeroSymbol` keccak in E.3):

```
magnitudeLane = uint256(keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_MAG_TAG)))
currencyLane  = uint256(keccak256(abi.encode(rw, day, drawKind, ticketIndex, FOIL_CCY_TAG)))
```

Per-tuple salting (the `(day, drawKind, ticketIndex)` fields) independently rolls each of the 8 daily
claim-units. **`FOIL_MAG_TAG ≠ FOIL_CCY_TAG ≠ BONUS_TRAITS_TAG ≠ FLIP_JACKPOT_TAG`** — distinct
keccak domains ⇒ the lanes are **provably disjoint** (threat T-445-E4). The lanes are derived from
the retained `rw` at claim, **never live-read**. Magnitude-first / currency-second reveal is
**UI-only** ordering; both are fixed atomically on-chain.

### (C) Currency split — 40 / 40 / 20 (FLIP / ETH / WWXRP), every spin, all tiers (MATCH-06)

```
uint256 c = currencyLane % 100;
if (c < 40)       currency = FLIP;    // [0,40)
else if (c < 80)  currency = ETH;     // [40,80)
else              currency = WWXRP;   // [80,100)
```

Magnitude `faces = baseFacesForTier`; convert FLIP / WWXRP `= faces * 1000e18`; ETH
`= faces * priceForLevel(recLevel)`.

- **FLIP (40%)** — `coin.mintForGame(msg.sender, flipAmount)` (`IDegenerusCoin.sol:20`). **Free
  mint, no solvency impact.**
- **WWXRP (20%)** — `wwxrp.mintPrize(msg.sender, wwxrpAmount)` (`WrappedWrappedXRP.sol:229`). **Free
  mint, no solvency impact.**
- **ETH (40%)** — the EXISTING capped-spin path: clamp `ethShare` to **`ETH_WIN_CAP_BPS = 1000`**
  (10% of `futurePrizePool`); over-cap spills to the lootbox; credit the capped ETH via
  `_creditClaimable(msg.sender, cappedEth)` (`:933`) and decrement `runningFuture` / `pendingFuture`
  exactly as `:884-903`. **CLONE SOURCE — STATE THE CORRECTED ANCHOR EXPLICITLY (V3 DEFECT F-β):**
  **`DegenerusGameDegeneretteModule.sol:877-915`** (`maxEth` at `:889`, lootbox-resolve at `:915`) —
  **NOT** the previously-stated `:402-446`. Writes: prize-pool decrement +
  `balancesPacked[msg.sender]` claimable-half + `claimablePool`; external call: a possible
  lootbox-resolve delegatecall on the cap spill.

### SEC-02 basis (design)

`ethShare ≤ 10% · futurePrizePool` (the `ETH_WIN_CAP_BPS = 1000` clamp + lootbox spill); FLIP and
WWXRP are **mints** (no pool draw); the whale pass is **pool-neutral**. Structurally solvent
(threat T-445-E2). This is the **SEC-02 design basis**, attested downstream at phase 448. **All
payout effects come AFTER `foilMatchClaimed[mk] = true` (CEI).** External calls in `claimFoilMatch`:
at most one of `{coin.mintForGame, wwxrp.mintPrize}` plus, on the ETH lane, the claimable credit and
a possible lootbox-resolve delegatecall on the cap spill — all after the marker write.

---

## E.7 Calibration confirm (MATCH-10, D-05)

All figures are **closed-form exact binomials** — a Monte-Carlo is unnecessary because the
per-quadrant match probability collapses to the constant `q = 1/64` (the uniform winning color
cancels the foil boost; §E.3). V2 independently reproduced every figure to full precision.

### Closed-form results

- **Per-quadrant match `q = 1/64 ≈ 1.5625%`, M-invariant** (flat across all `multBps`).
- Per ticket-draw, `k ~ Binomial(4, q = 1/64)`:
  - `P(2-of-4) = C(4,2)·q²·(1−q)² = 0.00141943`
  - `P(3-of-4) = C(4,3)·q³·(1−q) = 0.00001502`
  - `P(4-of-4) = q⁴ = 5.960e-08`
- `E[faces/draw] = 5·P(2-of-4) + 65·P(3-of-4) = 0.0080736`.
- **`E[faces/pack/30d] = 240 · 0.0080736 = 1.9376`** over 240 ticket-draws (4 tickets × 2 draws/day
  × 30 days), **FLAT across all scores** (M-invariant — no "calibrate-at-which-score" decision).
- **Tier split 87.9% / 12.1%** (2-of-4 / 3-of-4) — the build-time comment should cite **87.9%**, NOT
  the spec's illustrative ~85%.
- **Gold-odds crossover at M ≈ 2.4854** (`multBps ≈ 24,854`) — the foil pack ties 10 normal tickets
  on gold odds at roughly score ~30–50 on the `foilBoostBps` curve.
- **4-of-4 ≈ 1-in-69,906 per pack** (gated HERO-FREE; EV-negligible ~0.0014%/pack, steer-proof).

### D-05 policy verdict — CONFIRM and REPORT, no recalibration

The realized **1.94 faces/pack/30d** lands on the D-05 ~2-face target (**3.1% low**) → **NOT
materially off → no recalibration flag**. The payout table stays **LOCKED**. Because the per-quadrant
match collapses to a constant, the §G figures are **closed-form exact** — a Monte-Carlo is optional
confirmation, **not** a gating recompute. **Per D-05: if phase 447's empirical run lands materially
off ≈2, flag it to the USER — never silently retune the locked table.** (Reporting notes, both
non-blocking: the tier split is 87.9%/12.1% vs the illustrative ~85%/~12%; the 4-of-4 per-pack
rarity ≈1-in-69,906 is rarer than the spec's illustrative ≈1-in-300k, which folds a narrower
per-level window — documentation footnotes, no number changed.)

---

## F. Module placement + EIP-170 (SEC-03, D-04)

### F.1 Recommendation — a NEW `GAME_FOILPACK_MODULE`

Pin the placement: **a new `GAME_FOILPACK_MODULE`** (mirrors the existing 12-module delegatecall
dispatch), **NOT** an existing module. **D-04 is the engineering EIP-170 call** — the measured live
headroom drives it:

- The estimated foil body is **≈8–11 KB deployed** (buyFoilPack ~2.5–3.5 KB + claimFoilMatch
  ~2.5–3.5 KB + the isolated spin payout ~3–4 KB; the two library pieces `traitFromWordFoil` /
  `packedTraitsFoil` and `foilBoostBps` are `internal pure` and inline into callers, ~0.6–1.1 KB).
- An ~8–11 KB body **does not fit any single roomy live module with comfortable EIP-170 margin** plus
  the re-audit / slither / layout-golden re-pass cost. **`MintModule` is excluded** — SEC-03 excludes
  it AND it is physically near-full (**~1,116 B free** of its measured 23,460 B). The very-roomy
  Bingo / Boon / GameOver modules could absorb it physically but would couple an unrelated payable
  purchase + lottery feature into unrelated bodies.
- A fresh `GAME_FOILPACK_MODULE` starts at 0 → ~8–11 KB lands inside the 24,576 B cap with
  **~13.5–16.5 KB headroom**. No EIP-170 risk.

### F.2 Facade stubs + the constant

- **Two thin facade stubs** on `DegenerusGame`: `payable buyFoilPack()` + `claimFoilMatch(day,
  ticketIndex, drawKind)`. Each ~250–450 B; two ≈ 0.5–0.9 KB against the facade's measured **4,188 B
  free** → the facade lands at **~3.3–3.7 KB free**.
- **One new constant** `address internal constant GAME_FOILPACK_MODULE = …;` in
  `ContractAddresses.sol` (alongside the existing 12 `GAME_*_MODULE` constants at `:13-35`).

### F.3 Storage placement (SEC-03)

**New storage appends in `DegenerusGameStorage` ONLY** (the delegatecall-shared base), never in the
foil module or the facade — `foilRecord` + `foilMatchClaimed` tail-appended after `boxPlayers`
(`:2393`), no slot moves (SEC-04, see Section D).

### F.4 Re-measure-at-IMPL caveat (HARD-REQ §6.7)

All Section F sizes are measured on the **current** artifacts (no foil code yet). The real
`GAME_FOILPACK_MODULE` body and the facade-after-stubs size **MUST be re-measured on the post-IMPL
build** (HARD-REQ §6.7). Estimated body 8–11 KB; estimated headroom 13.5–16.5 KB — **to be confirmed
at 446/449**.

REQ tags locked across E.5 / E.7 / F: **MATCH-04** (isolated tier→faces table, no Degenerette
routing), **MATCH-06** (40/40/20 split), **MATCH-07** (4-of-4 whale pass + bonus spin), **MATCH-08**
(disjoint `FOIL_MAG_TAG` / `FOIL_CCY_TAG` lanes), **MATCH-10** (the 1.9376 calibration confirm),
**SEC-02** (design basis — ETH ≤ 10%-pool cap + lootbox spill cloned from `:877-915`), **SEC-03**
(new `GAME_FOILPACK_MODULE` + shared storage).
