# V71.0 Foil Pack — FINAL LOCKED SPEC

> Authoritative, user-locked design for the v71.0 milestone. Grounding/history + all `file:line`
> citations live in `.planning/V71-FOILPACK-DESIGN-CONTEXT.md` (§1–§7). This file is the spec the
> roadmap/plan phases build from. Where the exploratory sections of the context doc conflict with
> this file, **this file wins.**
>
> One-line: a one-per-level premium gold-chase pack (10× price for 4 boosted-rarity tickets) with a
> pull/claim multi-currency match lottery against the daily jackpot draws over the whole level.

## 1. Purchase
- **One foil pack per account per RAW game-level** (level-stamped flag, century idiom `DegenerusGameStorage.sol:1857-1876`; keyed on raw `level`, not `_activeTicketLevel()`).
- **Price = `10 × priceForLevel(level)`**; the pack delivers **4 whole tickets** (16 quadrant entries) → effective **+150% premium** over the 4-ticket face (pay-for-10, get-4). The premium is the low-activity penalty.
- **Payment: fresh ETH or claimable** (reject the afking leg).
- **Spend routes 75% next-pool / 25% future-pool** (normal ticket is 90/10) — fork the pool split for the foil leg only.
- **Foil tickets are NORMAL regular-jackpot entries** — same `traitBurnTicket` eligibility as normal tickets; their boosted-rarity traits write **real color tiers (incl. `color==7` gold)**, so they participate in the jackpot gold channels with no new wiring.

## 2. Activity-scaled rarity boost
- **New sibling producer** `traitFromWordFoil(rnd, multBps)` (+ `packedTraitsFoil`) modeled on `packedTraitsDegenerette` (`DegenerusTraitUtils.sol:201-223`). **The v70-frozen shared producers (`weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed`) are NOT edited.**
- **Multiplier ×2 @ score 0 → ~×5 @ score 350 → ×6 @ max**, via a new `foilBoostBps(score)` 4-segment curve in `ActivityCurveLib` (reuse the 500/30000 knees). **Frozen at buy** from `cachedScore` (`DegenerusGameMintModule.sol:1709`); applied at resolve, never live-read.
- "All rarer tiers lifted by the factor" (mix-to-rare-tail); **×6 gold ≈ 4.7%/quadrant**.
- Gold-odds vs spending the same ETH on 10 normal tickets (16 boosted quadrants vs 40 baseline): **worse at score 0** (≈22.3% vs 26.9% chance of ≥1 gold), **~tie at ×2.5** (~score 30–50), **~2× at max** (53.6%). The pack is a deliberately worse gold hunt at the bottom and a ~2× better one at the top.

## 3. Match lottery (the value channel)
- **4 ticket signatures** (each a frozen 4-quadrant `[color|symbol]` signature) stored per `(player, level)`; eligible the **WHOLE level** against **both** daily winning sets (main + bonus = 2 draws/day).
- **`claimFoilMatch(day, ticketIndex)`** — pull/claim, never a draw-time scan (keeps `advanceGame` flat). Re-derives that day's winning traits from retained `rngWordByDay[day]`, counts **exact positional quadrant matches** (full 6-bit color+symbol; color-only does NOT count) for that ticket, pays the tier. Each `(day, drawKind, ticketIndex)` claimable at most once (sparse `keccak(player,level,day,drawKind,ticketIndex)` marker).
- **4 tickets independent** — no pooling; a pack can pay multiple tickets separately.

### Tiers (per ticket)
| Tier | reward |
|---|---|
| **2 of 4 matches** | **5 faces**, paid as one spin |
| **3 of 4 matches** | **65 faces**, paid as one spin |
| **4 of 4 matches** | **half a whale pass** (`whalePassClaims[player] += 1`) **+ a bonus spin** (~1,000 faces) |

`1 face = 1 whole ticket = 1,000 FLIP = the level's ticket price in ETH` (fixed FLIP peg; ETH-per-face floats with level).

### Spin currency — 40% FLIP / 40% ETH / 20% WWXRP, on EVERY spin (all tiers)
- **FLIP (40%)** — minted, `coin.mintForGame`. Free to the protocol.
- **ETH (40%)** — the existing **capped** ETH-degenerette-spin: clamp to `ETH_WIN_CAP_BPS = 1000` (10% of `futurePrizePool`), over-cap spills to lootbox; credit via `claimablePool`/`_creditClaimable`. Structurally solvent (`ethShare ≤ 10%·pool`).
- **WWXRP (20%)** — minted, **worthless joke token** (`wwxrp.mintPrize`); the comedic "you won big… in WWXRP" letdown.
- **Magnitude + currency both derived deterministically from `rngWordByDay[day]` at claim** (disjoint entropy lanes; currency lane disjoint from the match lane). Reveal = **magnitude first, currency second** (pure UI ordering; both fixed atomically on-chain). UI shows the **post-cap realizable** ETH as the magnitude.
- **Isolated payout table** — the tier→faces schedule is the foil claim's OWN; it MUST NOT route through the EV-flat Degenerette per-N `quickPlay` tables (those become +EV under boosted foil gold).

### Calibration
- **Expected nominal currency payout ≈ 2 ticket-faces per pack over 30 days** (240 trials = 4 tickets × 2 draws/day × 30 days). The **2-of-4 tier carries ~85%**; 3-of-4 ~12%; the 4-of-4 whale-pass+spin is EV-negligible (≈1-in-300k) and rides free.
- Eligibility = the level's duration (activity-driven, 0–120 days; typical ~7 draw-days). So the payout is **deliberately bad in a fast level, a real score in a slow one** (implied break-even ≈ a 90-day level).
- With the 20% worthless WWXRP and the bounded hero-steer edge (§4), realized **real** EV ≈ 1.6 faces (passive) → ~2.3 faces (active steerer) — the ~2-face target effectively lands on active players.

## 4. Manipulation policy (hero-symbol)
- The daily winning **hero quadrant's SYMBOL** is the only player-steerable component: the draw overwrites it from the prior day's Degenerette ETH-bet board `dailyHeroWagers` (top wagerer +1.5× bias; same hero forced onto both main+bonus). Everything else — all colors, the other symbols, the hero quadrant's color — is pure VRF (`DegenerusGameJackpotModule.sol:1316-1341`; `JackpotBucketLib.sol:281-286`).
- **2-of-4 & 3-of-4: matched against the LIVE (hero-overridden) traits** → the slight, bounded, rewards-activity edge is KEPT (≈+0.35 face/pack typical, not clearly +EV, throttled by the contested public wager auction).
- **4-of-4: gated on the HERO-FREE pure-VRF traits** (re-derive via `getRandomTraits(rngWordByDay[day])` + bonus counterpart WITHOUT `_applyHeroResult`; substitute the pre-override VRF symbol for the hero quadrant). The whale-pass moonshot therefore **cannot be steered or collusion-stacked** — a steered hero can carry a player to at most a 3-of-4. Un-steerable, fair 1-in-millions.

## 5. Storage & integration
- **`foilRecord` per `(player, level)`**: 4 × 24-bit signatures + level stamp (auto-resets per level). Records persist per-level so a fast `level++` can't grief an unclaimed match. Sparse per-`(day,drawKind,ticketIndex)` claimed marker for the multi-draw window.
- **Body in a roomy module or a new `GAME_FOILPACK_MODULE`** (NOT `MintModule`, ~1,116 B free); thin `payable buyFoilPack(...)` facade stub (facade has ~4,188 B). New storage **appended in `DegenerusGameStorage`** (delegatecall-shared), never in a module.

## 6. Hard requirements (the floor — must all hold)
1. No exploit / no farm beyond the bounded §4 hero edge; the 4-of-4 moonshot is steer-proof.
2. No solvency hole — ETH leg bounded by the 10%-pool cap; FLIP/WWXRP are mints; whale pass is pool-neutral deferred.
3. **Isolated match payout table** — no coupling to the EV-flat Degenerette per-N tables.
4. Frozen shared trait producers untouched; foil uses a new sibling producer.
5. Buy-time freeze of score (→ boost) and ticket signatures; claim re-derives from retained RNG — never live-read.
6. Pull/claim only — no draw-time scan; `advanceGame` gas stays flat.
7. EIP-170 fits after the new module + facade stub (re-measure; via_ir + optimizer_runs=1000).
8. Full forge suite green; layout goldens / RNG-freeze proofs re-pass on the new subject.
