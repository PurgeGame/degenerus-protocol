# VERIFY-match — Multi-currency MATCH lottery + payouts + RNG/solvency (Phase 447)

**Subject:** as-built diff `ffbd7796` (v70 freeze) → HEAD across
`DegenerusGameFoilPackModule.sol`, `DegenerusGameJackpotModule.sol`,
`DegenerusGameDegeneretteModule.sol`, `DegenerusGameAdvanceModule.sol`
(+ supporting `DegenerusGameStorage.sol`, `ActivityCurveLib.sol`, `DegenerusTraitUtils.sol`).

**Posture:** read-only correctness + solvency review. Neutral defensive-engineering framing
(value-conservation, steer-resistance, bounds, freeze-at-commitment). Method: direct code trace +
two isolated top-model subagents (T=8 steerability math; WWXRP rig apex-invariance).

**Authoritative design:** `.planning/V71-FOILPACK-FINAL-SPEC.md` (§3–§6) as superseded by the v72
`REQUIREMENTS.md` RIG-03 rescore (Variant-2, faces `{4→2,5→6,6→35,7→400,8→10000+½ pass}`). The
`FOIL-EV-ANALYSIS.md` `{2→7,3→65,4→1000}` table is an EARLIER design and is NOT the as-built table.

---

## Per-requirement verdict table

| Req | Verdict | Evidence (file:line) |
|---|---|---|
| MATCH-01 (4 sigs frozen at buy, per (player,level)) | **MATCH (variant)** | `FoilPackModule:303-322`, `Storage:2507-2517`. Lines are NOT stored as 4×24-bit sigs; only `(resolveDay, multBps, score)` is frozen and the 4 lines are **re-derived** at drain/claim from `rngWordByDay[resolveDay]+multBps+(buyer,lvl)`. Equivalent + steering-safe (FOIL-REDESIGN-SPEC). Keyed per `(lvl, buyer)`. |
| MATCH-02 (each ticket eligible whole level vs both daily sets) | **MATCH** | Claim accepts any `day ≥ resolveDay` (`:466`) and `drawKind ∈ {0,1}` (`:444`, `:491`); 4 ticketIndexes independent (`:443`). |
| MATCH-03 (`claimFoilMatch(day,ticketIndex)` re-derives winners, counts quadrant matches, pays tier) | **MATCH** | `:352-360`, `_tryClaimFoilMatch:437-524`; winners read from sealed `dailyFoilDraw[day]` (`Storage:2563-2573`), line re-derived (`:478-483`), graded score loop (`:493-500`), tier pay (`:506-522`). |
| MATCH-04 (OWN isolated payout table, never the EV-flat per-N pick tables) | **MATCH** | Faces are module constants `FOIL_FACES_T4..T8` (`:65-69`); the per-N pick tables only set the spin's EV-neutral RTP on the staked face magnitude. The face→stake schedule is foil-local. |
| MATCH-05 (pull/claim only; ≤once per (day,drawKind,ticketIndex); records persist per-level) | **MATCH** | Pull/claim (`:352`, batch `:376`); marker `keccak(player,L,day,drawKind,ticketIndex)` set BEFORE payout (CEI, `:470-504`); `day>uint24.max` rejected to stop marker aliasing (`:449`); record keyed per-level survives `level++` (`Storage:2545-2547`). |
| MATCH-06 (2/3 tiers: one 40/40/20 spin; FLIP mintForGame, ETH 10%-pool-capped, WWXRP mintPrize) | **MATCH** | `_payFoilTier:572-636`; currency split `% 100` → `<40` ETH / `<80` FLIP / else WWXRP. ETH via `resolveEthSpinFromBox`→`_distributePayout` capped at `ETH_WIN_CAP_BPS=1000` (`Degenerette:943`); FLIP `coin.mintForGame` (`:1569`); WWXRP `wwxrp.mintPrize` (`:1498`). |
| MATCH-07 (4-of-4 → `whalePassClaims += 1` + a 40/40/20 bonus spin) | **MATCH** | `_payFoilTier:583-585` grants `whalePassClaims[player] += 1` when `tier==8`, then runs the same 40/40/20 spin. |
| MATCH-08 (magnitude AND currency from `rngWordByDay[day]`; disjoint lanes; ordering UI-only) | **MATCH** | `_payFoilTier:590-597`: `c = keccak(rw,…,FOIL_CCY_TAG)%100` (currency), `seed = keccak(rw,…,FOIL_SPIN_TAG)` (spin) — distinct keccak domains off the same retained word. Magnitude (`faces`) is tier-deterministic. Reveal order is not on-chain. |
| MATCH-09 (2/3 vs live hero set; 4-of-4 gated on HERO-FREE pure-VRF) | **DELTA** | **The T=8 path scores against the hero-OVERRIDDEN set** (`winSet`=`mainSet`/`bonusSet` from `dailyFoilDraw`, `:491`,`:517`). No pure-VRF re-derivation for `score==8`. The prescribed hero-free gate is NOT implemented. See **Issue 1** — bounded to an 8× edge (1/2.1M vs 1/16.8M); economically negligible. |
| MATCH-10 (ladder ≈2 ticket-faces EV/pack/30d) | **MATCH (static)** | Faces `{2,6,35,400,10000}` documented to hold `E[faces/comparison]=0.010972 → 2.633/pack/30d`, byte-EV-identical to the prior `{7,65,1000}` table (`:57-69`). Empirical proof deferred to 449 (TST-EV-01) — out of static scope. |
| PILLAR-RNG (frozen-at-commitment; 4-of-4 unsteerable; hero edge bounded) | **MATCH w/ DELTA** | Lines derive from `rngWordByDay[resolveDay]`, provably future at buy (`:176-177` `day>dailyIdx+1` revert; `:290-297` resolveDay). No live read. Hero edit is one quadrant's symbol only (`Jackpot:1342-1346`), color stays VRF → edge bounded. **The T=8 "hero-free" gate is the one DELTA (Issue 1).** |
| PILLAR-SOLV (foil legs) | **MATCH** | ETH leg `≤10% futurePrizePool` unfrozen (`Degenerette:943-952`) / `pendingFuture ≥ ethShare` revert frozen (`:936-937`); FLIP/WWXRP are mints; whale pass is a pool-neutral deferred grant; no double-claim (CEI marker); claimable debit can't borrow afking principal (`Foil:193-196`). No path pays unbacked value. |

---

## Ranked issues

### Issue 1 — T=8 moonshot scores against the hero-overridden set (MATCH-09 literal deviation) — **LOW**
**Where:** `DegenerusGameFoilPackModule.sol:491` (`winSet = mainSet/bonusSet`), `:493-500` (score loop),
`:517` (`FOIL_FACES_T8`); winning sets are hero-overridden at `DegenerusGameJackpotModule.sol:1342-1346`,
persisted to `dailyFoilDraw` at `:1590`/`:1850`.

**What the design requires:** MATCH-09 / SPEC §4 — the 4-of-4 (T=8) moonshot MUST be gated on the
**hero-free pure-VRF** winning traits (re-derive without `_applyHeroResult`, substituting the
pre-override VRF symbol for the hero quadrant) so the whale-pass moonshot "cannot be steered or
collusion-stacked." The 2/3 tiers are explicitly allowed to match the live (hero-overridden) set.

**As-built:** ALL tiers, including `score==8`, score against the single hero-overridden `winSet`.
There is no second, hero-free re-derivation for the T=8 gate.

**Why it is LOW, not HIGH (decisive math):** the hero override changes exactly ONE quadrant's
**symbol**; that quadrant's **color** is still pure VRF (`p=1/8`), and the other 3 quadrants are
fully VRF. A full double (the T=8 ingredient) needs symbol AND color to match. So a best-case
steerer who wins the wager auction and forces a hero `(quadrant, symbol)` that matches a quadrant
of a line they already hold gains only one `1/8` factor:

- Passive: `P(T=8) = (1/8·1/8)^4 = 1/16,777,216`.
- Steerer: hero quad `1/8` (color only) × three quads `1/64` = `(1/8)·(1/64)^3 = 1/2,097,152`.
- **Edge = exactly 8×**, both astronomically rare; 7 unsteerable VRF `1/8` hits remain, and the
  steerer pays the contested public wager-auction cost each attempt for, at most, half a whale
  pass (a pool-neutral deferred grant; the spin itself is EV-bounded and frozen at buy).

No profitable collusion-stacking vector is realized. The violation is of the **letter** of MATCH-09,
not the **spirit** ("cannot be steered or collusion-stacked"), which holds in practice.

**Suggested fix (choose one; do NOT apply at 447 — gate is FREEZE/448):**
- (a) Implement the prescribed hero-free gate: for `score==8`, re-derive a pure-VRF winning set for
  `day` (re-roll `getRandomTraits` from the day's word WITHOUT `_applyHeroResult`) and require the
  line to be a full-double on all 4 quadrants of THAT set before granting the whale pass. (Cost: one
  extra re-derivation on the ~1-in-millions path only; needs the day's raw VRF word, which is
  retained as `rngWordByDay[day]`.) OR
- (b) Formally accept the bounded 8× edge: amend MATCH-09 to read "the T=8 edge is bounded by-design
  to a single hero-symbol factor (8×)" and document the half-whale-pass economics as the bound —
  matching how the 2/3 hero edge is already accepted.

### Issue 2 — A foil WWXRP spin can independently trip the shared S==9 bracket whale-halfpass — **INFO**
**Where:** `DegenerusGameDegeneretteModule.sol:1500-1509` inside `resolveWwxrpSpinFromBox`.
On the 20% WWXRP currency leg, the box-spin is a full Degenerette game and can roll `s==9`,
which grants the per-10-level-bracket whale halfpass via the **shared, deduped**
`wwxrpJackpotWhalePassBracketAwarded[bracket]` flag. So a T=8 foil claim that also lands the WWXRP
lane could grant the bracket's one halfpass on top of the T=8 `whalePassClaims += 1`.
**Bounded + intended:** the bracket flag caps this at one award per 10-level bracket across ALL
WWXRP paths (ordinary bets + box spins), the whale pass is pool-neutral, and the WWXRP rig provably
**cannot** manufacture an `s==9` it would not otherwise have (apex M=7 cap — see below). No
value-conservation or solvency concern. Noting only for the indexer/economics record.

### Issue 3 — `FOIL-EV-ANALYSIS.md` faces table is stale vs the as-built rescore — **INFO (docs)**
`FOIL-EV-ANALYSIS.md:17` cites `{2→7,3→65,4→1000}` (the pre-rescore liveCount table). The as-built
table is the Variant-2 `{4→2,5→6,6→35,7→400,8→10000}` (`FoilPackModule:65-69`), documented as
byte-EV-identical. Not a contract issue; flag so 449's EV proof targets the correct table and the
analysis doc is reconciled.

---

## Corroborated NON-issues (checked, clean)

- **Zero-seed grind (claim before RNG committed):** `dailyFoilDraw[day]` is written only inside
  jackpot resolution, AFTER `rngWordByDay[day]` is sealed; `_foilDrawFor` requires `drawPresent`
  (`Storage:2569`), and `_payFoilTier` re-asserts `rngWordByDay[day] != 0` (`:590-591`). A day with
  no sealed word has no draw to claim. **No grind.**
- **Buy-time forward-commit:** `:176-177` blocks `day > dailyIdx + 1` (multi-day stall gap-backfill),
  and `resolveDay` (`:290-297`) is the next genuinely-future word — same guarantee as a normal ticket.
- **Double-claim / replay:** marker set before payout (CEI, `:504`); `day` truncation-aliasing
  closed (`:449`); marker binds `L` (draw's level), separating cross-cycle wins.
- **Mint == claim invariant:** `_deriveFoilLines` is the single shared producer for both the drain
  (files jackpot entries, `:754-759`) and the claim (`:478-483`), same `(buyer,L,rngWordByDay[resolveDay],multBps)`.
- **ETH cap solvency:** unfrozen caps at `pool×10%`; frozen reverts if `pendingFuture < ethShare`;
  `claimFoilMatchMany` try/catch isolates an unpayable ETH tier so one stale tuple can't poison the
  batch and the spine can't brick.
- **Disjoint entropy lanes (MATCH-08):** match line uses `rngWordByDay[resolveDay]`+`FOIL_SEED_TAG`;
  currency uses `rngWordByDay[day]`+`FOIL_CCY_TAG`; spin uses `…+FOIL_SPIN_TAG` — three disjoint
  keccak domains.
- **WWXRP rig apex invariance (subagent-verified):** `_rigWwxrpResult` flips at most one ordinary
  (non-hero) cell, only at `M≤6`, 60% gate; post-rig `M≤7`, so `s==9` (needs M=8) is structurally
  unreachable — the rig cannot inflate the whale-pass-granting jackpot. ETH/FLIP paths byte-identical
  (no rig, honest tables). (Detail in the RIG verify scope.)
- **Frozen shared trait producers untouched:** `weightedColorBucket`/`traitFromWord`/
  `packedTraitsFromSeed` unchanged in the diff; foil uses the new sibling `foilTrait`/`foilCuts`/
  `packedTraitsFoil` (RARE-01). `foilBoostBps` ramps ×2→×5(@300)→×5.5→×6 (RARE-02), clamped
  `[20000,60000]`, frozen at buy (RARE-03).

---

## Summary

- **MATCH: 11** (MATCH-01..08, MATCH-10, PILLAR-SOLV, PILLAR-RNG-core) · **DELTA: 1** (MATCH-09 /
  PILLAR-RNG T=8 hero-free gate) · **UNSURE: 0**.
- **Top issues:** (1) **LOW** — T=8 moonshot scores against the hero-overridden set, not pure-VRF
  (literal MATCH-09 deviation; bounded to an 8× edge, ~1-in-2.1M, economically negligible — fix or
  formally accept the bound); (2) **INFO** — foil WWXRP spin can trip the shared, deduped, pool-neutral
  S==9 bracket halfpass; (3) **INFO (docs)** — `FOIL-EV-ANALYSIS.md` faces table is stale vs the
  as-built rescore.
- No CAT / HIGH / MED. No double-claim, no zero-seed grind, ETH leg within the 10% cap, entropy lanes
  disjoint, mint==claim invariant intact.

*Reviewed 2026-06-21 (phase 447). No `.sol`/test edits made; this file is the only write.*
