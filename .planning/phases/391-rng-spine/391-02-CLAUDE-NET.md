# 391-02 — NET 2 (Claude Adversarial Net) — RNG-FREEZE SPINE (RNG-01..06 + FC-391-01..05 + cross-refs)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
`git diff a8b702a7 -- contracts/` EMPTY before and after this task. All source read via
`git show a8b702a7:contracts/<File>.sol` — the working tree was ignored. No `hardhat` invoked.
**Net:** NET 2 = the deep Claude adversarial net, run INDEPENDENTLY of the council. Each item below
was attacked first against frozen source (backward-trace to the player's input-commitment point +
a concrete reachable call-sequence attempt); the NET-1 council leads (`391-01-COUNCIL-NET.md` +
`council/rng.{gemini,codex}.txt`) were folded in only at the END of this pass (§F).
**Doctrine (v45 north-star + the RNG-audit rules):** every variable that interacts with a VRF word
must be frozen between rng-request and unlock relative to players; trace BACKWARD from each consumer to
the commitment point and confirm the word was UNKNOWN then; enumerate EVERY in-window SLOAD (not just
VRF-derived seeds); check what player-controllable state can change between request and fulfillment.
**Posture:** AUDIT-ONLY — a CONFIRMED finding is DOCUMENTED + ROUTED, never fixed here.
**Green oracle:** `test/REGRESSION-BASELINE-v63.md` — forge 854/0/110. RNG-window freeze authority =
`RngWindowFreeze.inv.t.sol` (EXERCISED + non-vacuous `afterInvariant` gate + FALSIFIABLE seeded-mutation
test) + the 7/7 GREEN VRFPath suite + `DecimatorOffsetIsolation.t.sol` (slot-isolation EXERCISED). The
decimator uint32 per-bucket DISTRIBUTION is the one MISSING oracle property (388-02 ORACLE-HOLES) — built
here as a real argument (§B), routed as a test-hardening note (NOT relied on as already-netted).

---

## A. RNG-01 — backward-trace EVERY new/changed consumer to the commitment point

The break attempt for each consumer: is there ANY live, post-reveal, player-controllable input that
enters the seed? For each I cite the commitment point (where the player's input is fixed) and confirm the
VRF word was unknown then.

| Consumer | Seed (frozen line @ `a8b702a7`) | Word source | Commitment point (player input fixed) | Word unknown at commitment? | Attack tried / result |
|----------|----------------------------------|-------------|----------------------------------------|------------------------------|------------------------|
| Lootbox manual open | `keccak256(abi.encode(rngWord, player, amount))` (LootboxModule:560) | per-index VRF anchor `lootboxRngWordByIndex[index]` | deposit binds `index` (index advanced at the rng request, `_lrAdvanceIndexClearPending` Advance:1690) | YES — the index's word lands at fulfillment AFTER the index advance; a buy after fulfillment targets the NEXT index | observe-then-rebuy: a buy after the word lands maps to index+1 (cleared pending), cannot resolve against the revealed word. REFUTED-sound. |
| Lootbox auto-resolve `resolveLootboxDirect` | `hash2(rngWord, uint160(player))` (LootboxModule:883) — **amount dropped** | caller-domain-separated word (per §D) | the caller's commitment (decimator burn / bet placement / redemption submit) — each predates the word | YES — every caller passes a word fixed before its own commitment | feed a live word: no live read enters the seed (only `rngWord` + `player`); claim timing / futurePrizePool nudge cannot re-roll (comment :880-882). REFUTED-sound. |
| Box-spins WWXRP/BURNIE/ETH | `hash2(boxSeed, BOX_*_TAG)` via `_boxBetId`; per-reel `packedTraitsDegenerette(hash2(ss,i))` (DegeneretteModule:1292/1347/1402) | `boxSeed` = the box's per-resolution seed (descends from the committed anchor word) | the box deposit / bet placement (anchor index committed pre-word) | YES | re-trigger a spin: the box record is zeroed / bet `delete`d before resolution (§C) + `address(this)!=GAME` guard — one-shot. REFUTED-sound. |
| BURNIE survival flip (bet path) | `hash2(rngWord, betId) & 1` (DegeneretteModule:773) | `lootboxRngWordByIndex[index]` | `betId` nonce assigned at `placeDegeneretteBet` (BEFORE the word lands; placement reverts on an already-worded index) | YES | place-then-observe: the bet binds `betId` + `index` before fulfillment; a losing bet pays zero resolved-or-abandoned (no resolution-timing edge). REFUTED-sound. |
| Redemption lootbox leg | `entropy = hash2(rngWordForDay(day+1), uint160(player))`, per-chunk rehash `hash1(rngWord)` (StakedStonk:878-882, LootboxModule:1053/1014) | `rngWordForDay(day+1)` — the NEXT day's word | the burn submit stamps `currentPeriod` (=`day`); the gate admits the burn only after `currentPeriod`'s word exists (§E) | YES — `day+1` is UNDRAWN at burn time (advanceGame never draws future words) | grind a known draw: `rngWordForDay(day+1)==0` at burn time pins it. REFUTED-sound (the v62 REDEMPTION-ZERO-SEED class — now gated). |
| Decimator claim lootbox | `hash2(uint32(round.rngWord), uint160(player))` (DecimatorModule:277/410 → LootboxModule:883) | `round.rngWord = uint32(rngWord)` fixed at `runDecimatorJackpot` resolution | the decimator burn `recordDecBurn` (during the level, BEFORE the resolution word) | YES — winners selected from the FULL word at snapshot, claim word fixed at resolution | grind/retry-time the claim: permissionless deterministic claim credits the winner only; the word is fixed at resolution. REFUTED-sound (entropy-floor + cross-round collision analyzed in §B/§D). |
| Coinflip win/loss + carry roll | `(rngWord & 1)==1`; bonus `keccak256(abi.encodePacked(rngWord, epoch))` (BurnieCoinflip:822/796) | the day's VRF word via the advance walk | the stake is committed earlier via `_addDailyFlip` (days 1-20 = deploy-time seed stakes) — all pre-word | YES | settle-time steer: `processCoinflipPayouts` is `onlyDegenerusGameContract`, inside the rng-locked daily window with the day's own fresh word; `claimCoinflipCarry` reverts on `rngLocked()` (§F4). REFUTED-sound. |
| EntropyLib migration sites | `hash2`/`hash1` (EntropyLib:23/38) | already-committed words at each site | n/a (preimage-identity, not a new consumer) | n/a | preimage-divergence attack: byte-identity confirmed §B(iii) / RNG-06. REFUTED-sound. |
| reverseFlip nudge | adds `totalFlipReversals` to the raw word PRE-lock (Game:1817, Advance:291) | n/a (nudge to the word, gated by `rngLockedFlag`) | the nudge is blocked once the VRF request is in-flight (`if (rngLockedFlag) revert RngLocked()`) | YES (nudge only allowed before request) | nudge-during-window: reverts under the lock. REFUTED-sound (semantics unchanged vs baseline). |
| Far-future mint salvage quote | `keccak256(abi.encodePacked(player, rngWordByDay[day-1]))` (MintStreakUtils:232) | the SETTLED prior-day word (already revealed) | n/a — this is a PRICING QUOTE, not a payout RNG | settled word is known by-design (preview==execution offer) | this is not a payout draw; the dedup REMOVES a preview/execution mismatch. REFUTED (not a freshness path). |

**RNG-01 provisional verdict: REFUTED across the whole changed consumer set.** No consumer admits a
live, post-reveal, player-controllable seed input; every seed binds to a word committed before the
player's input. The single nuance is the redemption `day+1` read (RNG-05) — settled separately and
sound. The dropped-`amount` (resolveLootboxDirect) shifts disambiguation to the caller (RNG-04, §D).

---

## B. RNG-02 / FC-391-04 — decimator uint32 claim-seed DISTRIBUTION (§6 PRIME — dedicated real argument)

**The narrowing pinned at source:** `round.rngWord = uint32(rngWord)` (DecimatorModule:277). Winners are
selected BEFORE the narrowing from the FULL word (`decSeed = rngWord`, `_decWinningSubbucket(decSeed,
denom)` :241-269) and packed into `decBucketOffsetPacked[lvl]`. ONLY the claim-time lootbox seed is
narrowed. At claim, `round.rngWord` (uint32) flows through `_creditDecJackpotClaimCore` →
`_awardDecimatorLootbox(winner, amount, rngWord, evScore)` (:645) → `resolveLootboxDirect(winner,
amount, rngWord, ...)` whose seed becomes `hash2(uint32_word, uint160(player))` = `keccak256(abi.encode(
uint32_word, address_as_uint256))` (LootboxModule:883). The seed drives `_rollTargetLevel` (bits 0-39 =
rangeRoll%100 / near-offset%5 / far-offset%46) AND `_resolveLootboxRoll` (bits 40+ = pathRoll%20, the
reward-type draw) — see the bit-layout comment LootboxModule:1217-1222.

Do NOT re-assert "address-mixed so fine." The real distribution argument over the WHOLE winning-bucket
population of ONE level (many winners potentially sharing the SAME 32-bit word `W`, differing only by
their 160-bit address inside `hash2`):

(i) **Joint distribution across winners of one level.** Each winner `i` draws `seed_i = keccak256(W ||
addr_i)`. keccak256 is modeled as a random oracle: distinct inputs map to independent uniform 256-bit
outputs. Since `addr_i` differ across winners, the `seed_i` are distinct random-oracle inputs ⇒ the
outputs are mutually independent and uniform, EVEN THOUGH they share the 32-bit prefix `W`. keccak
diffuses every input bit across every output bit (the avalanche property over a single permutation), so
the shared `W` does NOT survive as a correlation in the low bits that the tier moduli read. The joint
distribution of `(tier_i)` over the winner population is therefore the product of N independent uniform
tier draws — NOT biased and NOT correlated by the shared word. The full-word baseline would have given
each winner an independent draw too; the only difference is that the SET of possible `W` values across
the universe of all levels is bounded to 2^32 instead of 2^256. Within one level, all winners share one
`W` regardless — so the within-level distribution is IDENTICAL to the full-word case (the per-winner
draw was always conditioned on the single level word).

(ii) **Multi-account actor controlling N winning addresses for one level.** Each controlled address
gets an independent uniform tier draw (i). There is no correlation introduced by the shared `W` to
exploit: the attacker cannot make address A's outcome predict address B's outcome, because keccak
decorrelates them. The attacker ALSO cannot grind `W`: the word is drawn via VRF at decimator resolution
AFTER all burns (address commitments) are recorded (the burn `recordDecBurn` predates
`runDecimatorJackpot`). So even with N accounts the actor faces N independent uniform draws conditioned
on a word they could not choose — strictly the same EV per draw as a single account, no aggregate edge.

(iii) **32-bit floor adequacy for the realistic population size.** The 32-bit floor matters only if an
actor could ENUMERATE candidate `W` values to find a favorable one (grind), or if a birthday-style
collision across LEVELS yielded extractable value. (a) Grind is impossible — the word is VRF-fixed at
resolution, not chooseable. (b) Birthday/collision across levels: with K decimator levels over the game
lifetime, P(two levels share a uint32 word) ~ K^2 / 2^33; for any realistic K (hundreds) this is
~10^-5..10^-4. A collision means: for the SAME player winning at both levels, the two CLAIM seeds
`hash2(W, addr)` are identical ⇒ identical tier-draw OUTCOME TYPE at the two claims. This is the RNG-04
cross-round item (§D) — and it is benign: (1) the player cannot steer either `W`; (2) the reward
MAGNITUDE still scales by each claim's own `amount` (the seed sets only the tier/level outcome, not the
ETH amount); (3) an identical outcome TYPE across two of a player's own claims yields no value
extraction — it is the same uniform draw realized twice, not a bias toward higher tiers. The tier-skew
question: a fixed `W` does NOT skew the population's tier histogram because each address re-randomizes
the full 256-bit seed (i); the histogram converges to the uniform tier weights as N grows.

**RNG-02 / FC-391-04 provisional verdict: REFUTED (distribution unbiased + non-grindable).** The
per-claim `keccak256(W || addr)` is an independent uniform draw per winner; the shared 32-bit word does
not correlate or bias the population's tier distribution; the word is VRF-fixed after address commitment
so it is non-grindable; the 32-bit floor only bounds the cross-LEVEL word space (the §D collision case,
benign). **Routed test-hardening note (NOT a contract change):** `DecimatorOffsetIsolation.t.sol` proves
slot-isolation + claim-path-reached but NO oracle asserts the per-bucket tier DISTRIBUTION is unbiased
across a winner population. A later test phase COULD add a statistical/property test that draws many
`hash2(W, addr)` over a synthetic winner population and asserts the tier histogram is within tolerance of
uniform (an oracle-completeness item; the property is proven above by the random-oracle argument).

---

## C. RNG-03 / FC-391-02 + FC-391-03 — box-spin one-shot/replay + survival-flip accumulator

**One-shot record-clear (attack: observe a spin, revert, retry with the now-known word):**
- Manual open zeroes `lootboxEth[index][player] = 0` (LootboxModule:579) BEFORE `_resolveLootboxCommon`.
- Degenerette bet `delete degeneretteBets[player][betId]` (DegeneretteModule:655) at resolution start,
  before the spin loop and before the survival flip.
- Decimator `e.claimed = 1` (DecimatorModule:399) BEFORE `_creditDecJackpotClaimCore` awards the lootbox.
- Box-spin resolvers (`resolveWwxrpSpinFromBox` / `resolveBurnieSpinsFromBox` / `resolveEthSpinFromBox`)
  each guard `if (address(this) != ContractAddresses.GAME) revert E()` (DegeneretteModule:1298/1353/1408)
  — they are delegatecall-only from the Game frame, not independently callable.
Attack result: a revert-to-observe restores the cleared record (the whole tx unwinds), but the seed is
fixed (bound to the committed anchor word), so any retry produces the IDENTICAL outcome — no re-roll.
The record-clear-before-resolution + the module guard together prevent observing-then-re-triggering with
a known word. **RNG-03 / FC-391-02 provisional verdict: REFUTED-sound (one-shot by construction).**

**FC-391-03 survival-flip accumulator transient-underflow (attack: cross-bet ordering drives
`acc.burnieMint -=` below zero):** For a BURNIE bet, `_distributePayout` does `acc.burnieMint += payout`
PER SPIN (DegeneretteModule:907) — so by the time the survival flip runs, `acc.burnieMint` already holds
exactly THIS bet's `totalPayout`. On WIN: `acc.burnieMint += totalPayout` (now 2×, :774); on LOSS:
`acc.burnieMint -= totalPayout` (:777) which subtracts exactly the amount THIS bet just added, netting to
zero for this bet. The subtraction can never underflow because the matching `+=` for this same bet is
already in `acc.burnieMint` before the `-=` executes — cross-bet ordering is irrelevant since each bet's
own `+=` precedes its own `-=` within the same iteration. The box-spin BURNIE variant
(`resolveBurnieSpinsFromBox`) uses a LOCAL `total` (DegeneretteModule:1357) with no shared accumulator —
`total = survived ? total*2 : 0` (:1393) — strictly underflow-free. **FC-391-03 provisional verdict:
REFUTED-sound (no transient underflow; per-bet `+=` always precedes its `-=`).**

---

## D. RNG-04 / FC-391-01 — domain-separation (the dropped-`amount` term; the codex divergence PRIORITY)

`resolveLootboxDirect` dropped `amount` (seed = `hash2(rngWord, uint160(player))`, LootboxModule:883)
while manual open (`keccak256(abi.encode(rngWord, player, amount))`, :560) and the redemption chunk
(`keccak256(abi.encode(rngWord, player, amount))`, :1053) keep `amount`. The dropped term is now
disambiguated caller-side.

**Every caller of resolveLootboxDirect + its domain-separated word:**
| Caller path | word passed | domain-separator |
|-------------|-------------|-------------------|
| Decimator claim (`_awardDecimatorLootbox`, DecimatorModule:673) | `round.rngWord` (uint32, per-level) | the per-level decimator word + the winner address inside `hash2` |
| Degenerette regular bet-win recirc (`_resolveLootboxDirect`, DegeneretteModule:786) | `hash2(rngWord, betId)` | the immutable per-bet `betId` nonce |
| Degenerette ETH-spin recirc (`resolveEthSpinFromBox` → `_resolveLootboxDirect`) | `hash2(boxSeed, BOX_*_TAG)`-derived | the box tag + boxSeed |
| Redemption ETH-spin recirc (reaches `resolveLootboxDirect` via the ETH-spin, `allowEthSpin=false`) | the chunk's `hash2(...)` word | per-chunk rehashed redemption word |

**Attack 1 — same-word/same-player collision WITHIN one caller (the dropped-`amount` concern):** two of
a player's resolutions at the same caller with the same `(rngWord, player)` but different `amount` now
produce the SAME `seed` ⇒ same `_rollTargetLevel` + same reward-TYPE. BUT (a) within decimator,
`e.claimed=1` blocks a second claim for the same (level, player) — only ONE claim per level word; (b)
within Degenerette, every bet has a distinct `betId` so `hash2(rngWord, betId)` differs per bet; (c)
recirc paths derive distinct per-resolution words. So no single caller feeds two same-word/same-player
resolutions in the same round. The reward MAGNITUDE still scales by each call's `amount` independently
(the seed sets the tier/level OUTCOME, not the ETH amount applied). REFUTED within-round.

**Attack 2 — the codex CROSS-ROUND uint32 collision (the divergence PRIORITY):** a single player `P`
wins at two decimator levels `L`, `L2` where `uint32(VRF_L2) == uint32(VRF_L)`. Then both claims'
direct-lootbox seeds are `hash2(uint32_word, uint160(P))` — IDENTICAL ⇒ identical tier-draw outcome TYPE
at the two claims. `e.claimed=1` is per (level, player) so it blocks same-round replay, NOT the
cross-round 32-bit equality. Skeptic dual-gate:
- (a) **Reachable?** YES but with P ~ K^2/2^33 ≈ 10^-5..10^-4 over the game lifetime (§B-iii-b). A
  single P would need to win at two specific levels whose uint32 words happen to collide.
- (b) **Player-influenceable (grindable)?** NO. P cannot choose either `VRF_L` or `VRF_L2` (both fixed
  by VRF at each level's resolution, AFTER P's burn commitments). P cannot even predict the collision at
  burn time (the words are undrawn). So this is predictability-WITHOUT-control, not manipulability.
- (c) **Value extraction?** NO. An identical tier OUTCOME TYPE across two of P's OWN claims yields no
  extra value: (1) the reward magnitude scales by each claim's own `amount` (not the seed); (2) an
  identical draw realized twice is the SAME uniform-distributed reward, not a bias toward higher tiers
  (the unconditional distribution of each draw is still uniform — conditioning two of P's draws to be
  equal does not raise their expectation); (3) the lootbox tier is BURNIE-credit/ticket-adjacent, OFF
  the ETH/`claimablePool` solvency spine.
**RNG-04 / FC-391-01 provisional verdict: REFUTED as a freeze/manipulability break; the cross-round
collision is INFO/LOW (benign, no-player-control correlation) — convergent with codex's own
"not a freeze/manipulability break" rating and reconciles gemini's within-level SOUND ruling.** No
contract change warranted; a doc-only KNOWN-ISSUES disposition is the likely outcome IF the USER wants
the correlation recorded — routed, not fixed.

---

## E. RNG-05 / FC-391-05 — redemption day+1 pre-draw gate + day-boundary divergence

**Pinned at source:** burn gate `if (game.rngWordForDay(currentPeriod) == 0) revert
BurnsBlockedBeforeDailyRng()` (StakedStonk:991), `currentPeriod = GameTimeLib.currentDayIndex()` (:983).
`currentDayIndexAt(ts) = (ts - JACKPOT_RESET_TIME)/1 days - DEPLOY_DAY_BOUNDARY + 1` is a PURE function
of `block.timestamp` (GameTimeLib:31-33) — it does NOT read `dailyIdx`. The lootbox leg reads
`rngWordForDay(day + 1)` (:878, `day == currentPeriod`).

**Attack — can `currentDayIndex()` DIVERGE from the game's `dailyIdx` so a burn stamps a day whose
`day+1` word is already on-chain?** `rngWordByDay[d]` is written ONLY by (i) `_unlockRng(d)` after the
day's word is stored (Advance:1786, sets `dailyIdx = d`) or (ii) the gap-backfill `rngWordByDay[gapDay]
= derivedWord` (Advance:1841). Both write words for days `<= dailyIdx`. Interleavings:
- **Wall day rolled past `dailyIdx`, advance not yet run:** `currentPeriod = dailyIdx + k` (k≥1) but
  `rngWordByDay[currentPeriod] == 0` (no advance for the new day) ⇒ the burn REVERTS
  (`BurnsBlockedBeforeDailyRng`). The stamp can NEVER be a not-yet-advanced day.
- **Burn admitted (`rngWordForDay(currentPeriod) != 0`):** this forces `currentPeriod <= dailyIdx`. The
  highest admissible `currentPeriod` is `dailyIdx`. Then `day+1 = dailyIdx+1`, whose word is NOT on-chain
  (advanceGame never draws future words — `rngWordByDay[dailyIdx+1] == 0` until the next advance). So the
  redemption draw reads an UNDRAWN word, resolved on the next advance.
- **Same-block burn racing the advance:** within one tx the state is consistent; across txs in one block
  ordering is total — either the advance ran first (dailyIdx bumped, the new day's word set, the burn can
  stamp it and day+1 is still undrawn) or the burn ran first (stamps the prior drawn day, day+1 undrawn).
The gate pins a DRAWN day by construction (`currentPeriod <= dailyIdx`), so `day+1` is never on-chain at
burn time. The independent `rngLocked` guard in `burn()`/`burnWrapped()` is a SECOND wall over the
request→fulfillment window. **RNG-05 / FC-391-05 provisional verdict: REFUTED-sound (day+1 undrawn by
construction; the v62 REDEMPTION-ZERO-SEED gap is closed).**

---

## F. RNG-06 — in-window SLOAD enumeration over the repacked freeze-spine slots

Freeze-spine slots at `a8b702a7` (388-02 authoritative `forge inspect`): `rngWordByDay` slot 10;
`lootboxRngPacked` slot 34 (low 48 = index cursor); `lootboxRngWordByIndex` slot 35; `dailyIdx` slot 0
byte 3. For each read consumed ALONGSIDE a VRF word in the resolution windows, confirm it is VRF-derived
OR a frozen snapshot (written before the word landed), NOT a player-controllable non-VRF live read.

**Daily-resolution window (advanceGame, rng-locked):**
- JackpotModule traits/coin draw: consumes the day's `randWord` (VRF) + the level `lvl` (a protocol
  counter, not player-flippable mid-window) — `hash2(randWord, lvl)` / `COIN_JACKPOT_TAG` derivations.
  VRF-derived seed; `lvl` is frozen for the window. FROZEN.
- Redemption roll `(currentWord >> 8) % 151 + 25` (Advance:1259): VRF-derived from `day+1`'s word. FROZEN.
- Coinflip resolution `processCoinflipPayouts(bonus, dayWord, day)`: `bonus` precomputed by the caller
  from frozen protocol state (not a player flag), `dayWord` = the day's VRF word, stakes committed pre-
  word. VRF-derived + frozen snapshot. FROZEN.

**Lootbox-resolution window (box draws + spins):**
- The box draws read `rngWord = lootboxRngWordByIndex[index]` (slot 35) — the VRF anchor written at the
  mid-day fulfillment; the box's `amount`/`adj`/`score`/`distress` ride in the single packed `lootboxEth`
  word written at deposit. Frozen snapshot + VRF anchor. FROZEN.
- `activityScore` threaded into spin EV: provenance traced — the manual open passes `score` unpacked from
  the lootbox record (LootboxModule:541, written at deposit); the bet path passes the bet's snapshot
  (`activityScore` from the packed bet, DegeneretteModule:649); the decimator passes
  `_minScoreForBucket(winBucket, lvl)` (the score SEALED at burn-bucket time, DecimatorModule:410). NONE
  is a live read. FROZEN snapshot.

**Two load-bearing claims attacked independently:**
- (i) **EntropyLib byte-identical preimages:** `hash2(a,b)` does `mstore(0x00,a); mstore(0x20,b);
  keccak256(0x00,0x40)` (EntropyLib:23-27) = `keccak256(abi.encode(a,b))` for full-width 32-byte
  operands; `hash1(a) = keccak256(0x00,0x20) = keccak256(abi.encode(a))` for one word (:38-41). Every
  migrated operand is 32-byte: `rngWord`/`combined`/`w` are uint256; the address operand is
  `uint256(uint160(player))` (StakedStonk:879, LootboxModule:883) — an address ABI-encodes as a
  left-padded 32-byte word == `uint256(uint160(player))`, byte-identical. `betId`/`epoch`/tags are widened
  to uint256. No short-operand `abi.encodePacked` ambiguity. CONFIRMED byte-identical.
- (ii) **activityScore is the frozen snapshot, not a live read:** traced above — every resolver receives
  the score as a value parameter sourced from a deposit/burn-time snapshot, never reads a live player
  score inside the window. CONFIRMED frozen.

**Independent attack beyond the RngWindowFreeze handler's action set:** the handler enumerates slots
10/34/35 + dailyIdx and its seeded-mutation test fires (FALSIFIABLE). Beyond its action set I checked the
box-spin reads (slot 35 anchor + packed `lootboxEth` snapshot), the decimator claim reads
(`decBucketOffsetPacked` slot 44 — winners packed from the FULL word at snapshot, read-only at claim;
`round.rngWord` uint32 fixed at resolution), and the redemption `day+1` read (§E) — all VRF-derived or
frozen-snapshot, none a player-controllable in-window live read. **RNG-06 provisional verdict:
REFUTED-sound (every in-window SLOAD is VRF-derived or a frozen snapshot; preimage byte-identity +
activityScore-snapshot both confirmed; RngWindowFreeze falsifiable anchor holds).**

---

## G. Inherited cross-refs

- **FC-389-05 (gas-identity narrowing-equivalence half of the decimator uint32 — RNG-consumption +
  grind/retry-timing half owned here):** `round.rngWord = uint32(rngWord)` (DecimatorModule:277) is a
  deterministic value fixed at resolution — predictability WITHOUT control (player address committed at
  burn, word fixed by VRF at resolution, permissionless deterministic claim credits only the winner so
  claim timing cannot grind). The uint32 packs into the `DecClaimRound` slot alongside `poolWei` (uint96)
  + `totalBurn` (uint128) = 256 bits, one slot; no co-resident-field corruption (the STORAGE-attestation
  half is 389's; couple there). The RNG-consumption + grind/retry-timing half: REFUTED — non-grindable
  (§B/§D). **FC-389-05 provisional verdict: REFUTED (RNG half); STORAGE half → 389.**
- **FC-392-11 (RNG-lock-coverage half — backing/EV dynamics half owned by 392):** `claimCoinflipCarry`
  reverts on `degenerusGame.rngLocked()` at the TOP (BurnieCoinflip:759), BEFORE settling resolved days
  or reading `autoRebuyCarry` (:770). The lock window: `rngLockedFlag = true` at the daily request
  (Advance:1699), the callback stores `rngWordCurrent` while KEEPING the lock (Advance:1808),
  `_unlockRng` clears it only AFTER processing (Advance:1779-1781). `processCoinflipPayouts` is
  `onlyDegenerusGameContract` (:204) applying the win/loss roll `(rngWord & 1)==1` inside this locked
  window. Attack — a window where the pending day's stake word is on-chain (resolvable) yet a carry claim
  reads the roll before the lock blocks it: NONE — the word is stored (`rngWordCurrent`) only while the
  lock is held, and `claimCoinflipCarry` reverts for the entire locked window, so no carry claim or
  settle can act on the roll outcome before the lock releases (post-processing). The lock fully covers the
  roll application. **FC-392-11 provisional verdict: REFUTED (RNG-lock half airtight); backing-solvency
  dynamics (loss zeroes pending; carry excluded from redemption backing) → 392.**

---

## H. Fold-in: NET-1 council leads (read AFTER the independent pass above)

Now comparing the council outputs (`391-01-COUNCIL-NET.md` + `council/rng.{gemini,codex}.txt`):

| Item | council (NET 1) | NET 2 (above) | convergent / divergent |
|------|------------------|----------------|--------------------------|
| RNG-01 | both SOUND (commitment-before-word) | REFUTED-sound (§A) | CONVERGENT |
| RNG-02 / FC-391-04 | both SOUND (keccak-diffusion, non-grindable) | REFUTED (§B real argument + routed oracle note) | CONVERGENT |
| RNG-03 / FC-391-02 | both SOUND (record-clear + guards) | REFUTED-sound (§C) | CONVERGENT |
| FC-391-03 survival accumulator | both SOUND (no transient underflow) | REFUTED-sound (§C, per-bet `+=` precedes `-=`) | CONVERGENT |
| RNG-04 / FC-391-01 | **codex INFO/LOW cross-round uint32 collision** vs **gemini SOUND** (the divergence) | REFUTED as freeze/manip break; cross-round collision INFO/LOW benign (§D skeptic dual-gate) | NET 2 RECONCILES: gemini's within-level SOUND holds; codex's cross-round collision is real-but-benign INFO/LOW (no player control, no value extraction) — both sides correct on their scope |
| RNG-05 / FC-391-05 | both SOUND (day+1 gate, backfill ≤ wall day) | REFUTED-sound (§E day-boundary divergence bound) | CONVERGENT |
| RNG-06 | both SOUND (slot enum + byte-identity + frozen activityScore) | REFUTED-sound (§F enumeration + 2 claims attacked) | CONVERGENT |
| FC-389-05 | both SOUND (predictability-without-control) | REFUTED (§G RNG half; STORAGE → 389) | CONVERGENT |
| FC-392-11 | both SOUND (rngLocked covers the roll) | REFUTED (§G lock airtight; backing → 392) | CONVERGENT |

**No council-only lead surfaces a new item NET 2 missed.** The single material divergence (RNG-04) is the
codex INFO/LOW cross-round collision vs gemini's within-level SOUND — §D's skeptic dual-gate reconciles
both: the within-level distribution is SOUND (gemini), and the cross-round identical-seed collision is a
REAL but BENIGN INFO/LOW correlation (codex), failing all three EV-lens conditions for a freeze/manip
break (not grindable, no value extraction). gemini's `boon-interpretation live reads` observation
(`level`, `decWindowOpen`) matches the by-design timing ruling ([[lootbox-resolution-timing-by-design]])
— an OUTPUT gate choosing which already-fixed bracket lands, not a seed input (confirmed §A box-spins).

---

## I. NET 2 provisional verdict summary (independent, council folded)

| Item | Provisional verdict | Settling cite (`a8b702a7`) |
|------|---------------------|-----------------------------|
| RNG-01 | REFUTED-sound | per-consumer commitment points (§A table) |
| RNG-02 / FC-391-04 | REFUTED (unbiased + non-grindable) + routed oracle note | DecimatorModule:241-277, LootboxModule:883; §B |
| RNG-03 / FC-391-02 | REFUTED-sound (one-shot) | LootboxModule:579, DegeneretteModule:655/1298/1353/1408, DecimatorModule:399 |
| FC-391-03 | REFUTED-sound (no underflow) | DegeneretteModule:907/774/777, :1357/1393 |
| RNG-04 / FC-391-01 | REFUTED as freeze/manip break; cross-round collision INFO/LOW benign | LootboxModule:560/883/1053, DecimatorModule:277/673; §D |
| RNG-05 / FC-391-05 | REFUTED-sound (day+1 undrawn) | StakedStonk:983/991/878, GameTimeLib:31-33, Advance:1786/1841 |
| RNG-06 | REFUTED-sound (in-window SLOADs frozen/VRF) | slots 10/34/35 + dailyIdx; EntropyLib:23-41; §F |
| FC-389-05 | REFUTED (RNG half); STORAGE → 389 | DecimatorModule:277 |
| FC-392-11 | REFUTED (RNG-lock half airtight); backing → 392 | BurnieCoinflip:759/770, Advance:1699/1808/1779 |

**0 CONFIRMED freeze/manipulability breaks.** The single non-SOUND nuance (RNG-04 cross-round uint32
collision) is INFO/LOW benign (no player control, no value extraction, off the ETH spine). One routed
test-hardening item: a decimator uint32 distribution/grinding statistical oracle (NOT a contract change).
`git diff a8b702a7 -- contracts/` EMPTY at the end of this task — subject byte-frozen.
