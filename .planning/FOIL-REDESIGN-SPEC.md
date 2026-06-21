# Foil Pack — day-bucket / daily-RNG / re-derive redesign (locked design)

Supersedes the §V.8/V.9 drain-stamps-sigs mechanism for the MATCH LINES. The jackpot
filing, the box-spin payout, the boost, the affiliate/quest/streak parity, and the relocation
(orchestration in the facade) are UNCHANGED. This only changes how a pack's 4 match lines are
produced, seeded, stored, and claimed — mirroring the flip / degenerette / ticket per-period
bucket pattern.

## Principle
A foil pack is a ticket: you commit on day D, it resolves against a FUTURE daily VRF word you
cannot know at buy. Bucket by buy-day, mint at the next daily RNG, re-derive on claim. No
double-buffer, no rngLocked guard, no mid-day RNG — because stamping the WALL day makes the
resolving word provably future.

## Why it's steering-safe (no guard needed)
- buyDay = `_simulatedDayIndex()` (the WALL day, not the processed `dailyIdx`).
- The pack's traits derive from `rng[buyDay+1]` = `rngWordByDay[buyDay+1]`.
- The engine only ever requests RNG up to the current wall day, so `rng[buyDay+1]` (next wall
  day) cannot exist at buy — nothing to read, nothing to steer. Same guarantee as a normal
  ticket. The processed-day lag / fulfilled-but-unsealed window only bit the *dailyIdx*-stamp
  variant; the wall-day stamp avoids it entirely. (Confirmed by the buyday-guard analysis:
  the dailyIdx-stamp + restamp-to-day-1 variants were unsafe; the mirror-tickets / future-word
  binding is the safe one.)

## State
- `mapping(uint24 => address[]) foilBuyers;` — buyers bucketed by buyDay (the per-day queue),
  the coinflip-by-day / degenerette-bucket analog. Replaces the level-write-key `foilTicketQueue`.
- `foilRecord[lvl][buyer]` = `multBps (cap+boost) | buyDay`. DROP the 128-bit sig lanes and the
  separate lineDay. (`buyDay` is the seed-day + the no-look-back floor + cap presence.)
- `foilCursor` (per active bucket) for batched/resumable minting — unchanged in spirit.

## Buy (`buyFoilPack`, facade-orchestrated)
1. `uint24 buyDay = _simulatedDayIndex();`
2. cap: `foilRecord[lvl][buyer] != 0` reverts (one pack/cycle) — unchanged.
3. payment / 75-25 pool / 20-5 affiliate / 10 mint-units / daily+level quest / streak /
   recycle / boost-freeze / `handleFoilPack` / `foilStreakBoost` — all UNCHANGED.
4. `foilRecord[lvl][buyer] = (multBps << _FOIL_MULT_SHIFT) | buyDay;`
5. `foilBuyers[buyDay].push(buyer);`  (no sig roll at buy)

## Mint (at day D+1's sealed daily RNG, during advance)
When `rngWordByDay[D+1]` is sealed, process `foilBuyers[D]` (batched by `foilCursor`, same
35-unit/buyer budget + leftover-budget hook as today):
- `entropy = rngWordByDay[D+1]` (the daily word — recoverable, NOT the lootbox-indexed word).
- For each buyer: `lines = _deriveFoilLines(buyer, lvl, entropy, multBps)` (the existing roll:
  4 tuples × 4 quadrants via `keccak(entropy, buyer, lvl, FOIL_SEED_TAG, i)` + `foilTrait`/`foilCuts`).
- File the 16 traits into `traitBurnTicket[lvl]` (jackpot exposure; gold→solo bucket = the ++EV
  rarity channel) — unchanged batch writer.
- NO sig stamp. (The mint computes lines only to file the jackpot entries; the claim re-derives.)
- After draining `foilBuyers[D]`, `delete foilBuyers[D]; foilCursor = 0;`.

## Claim (`claimFoilMatch(day, ticketIndex, drawKind)`)
1. read `(multBps, buyDay)` from `foilRecord[lvl][buyer]`; `require` present.
2. `require(day > buyDay)` — first claimable draw is buyDay+1 (allowed: rng[buyDay+1] is VRF-
   unbiasable and the buyer committed before it; domain-separated keccak makes the line and the
   day-(buyDay+1) draw independent — claiming from buyDay+1 is safe).
3. `(drawPresent, mainSet, bonusSet, L) = _foilDrawFor(day); require(drawPresent);`
4. `sel = _deriveFoilLines(player, L, rngWordByDay[buyDay+1], multBps)[ticketIndex];` — re-derive
   (SAME shared helper + same seed the mint filed with → the jackpot sampled exactly this line).
5. double-claim marker, quadrant compare, tier gate, `_payFoilTier` — UNCHANGED.

## Load-bearing invariant
`_deriveFoilLines(buyer, lvl, rngWordByDay[buyDay+1], multBps)` MUST be the single shared
function called by BOTH the mint (to file jackpot entries) and the claim (to compare). Same
inputs → identical 16 traits → the jackpot samples exactly what's claimable.

## Net vs current
- Drop: level-write-key `foilTicketQueue`, the lootbox-word entropy coupling, the `_foilStampRoll`
  sig+lineDay write, the `lineDay != 0` / un-rolled-record gating.
- Add: `foilBuyers[day]`, `buyDay` in `foilRecord`, claim-time re-derivation.
- Saves one SSTORE/buyer in the mint; removes stored match-line state; resolution is the
  recoverable daily word; no buffers/guards.

## EV (separate, informational)
- Match-draw: p=1/64/quadrant, ~2 tickets realized value/pack at N=30 (per FOIL-EV-ANALYSIS.md).
- Rarity/jackpot: boost → rarer/gold buckets → fewer co-holders → bigger per-winner slice;
  gold→solo bucket = ++EV (quantification in progress). This is the +EV channel that offsets the
  10× pack cost. WWXRP lane = worthless by design.
