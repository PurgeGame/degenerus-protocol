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
