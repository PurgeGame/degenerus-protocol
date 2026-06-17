# Council Sweep 391 — RNG-FREEZE SPINE: VRF-word freshness & freeze-window correctness slice (RNG-01..06)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top).
Be concrete and reachable: a finding needs a real ordered call sequence (multi-tx / observe-then-retrigger
where the ordering matters) and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the **RNG-FREEZE spine** of the post-v62 change set: the freshness and freeze-window
correctness of every NEW and CHANGED RNG consumer — the lootbox Degenerette box-spins (WWXRP / BURNIE /
ETH), the BURNIE survival flip on Degenerette bets, the `resolveLootboxDirect` seed change (the `amount`
term dropped), the decimator claim-word narrowed to 32 bits, the redemption `day+1` pre-draw leg, the
EntropyLib `hash1`/`hash2` migrations, and the SLOADs consumed inside the rng-windows over the repacked
storage slots. We believe the freeze spine is **intact** across the change set — every new consumer
descends from a word committed BEFORE the player's input, the migrations are byte-identical preimages,
and the one genuinely distribution-affecting change (the decimator 32-bit narrowing) is freeze-safe.
Your job is to find where that belief breaks.

**Threat priority (USER-locked for this slice):** **DOMINANT = RNG/freeze — and this IS the RNG slice, so
the freshness / freeze / entropy-adequacy properties below ARE the dominant target here. A confirmed
RNG-manipulability or freeze break is the HIGHEST-severity class in this engagement — weigh it
accordingly.** HIGH = gas-DoS only in the `advanceGame` chain (16,777,216 gas = brick); SPINE = solvency
(audited in the 390 slice); LOW/confirmatory = access-control / reentrancy / MEV. A finding that lets a
player learn or steer a VRF-derived outcome at or after their input-commitment, or that admits a fresh
re-roll of an already-revealed word, is the prize here — charge for it.

## The freeze doctrine this slice rests on (the north-star to break)

The master invariant: **every variable that interacts with a VRF word must be FROZEN between the rng
request and the unlock, relative to players.** Concretely, for EVERY RNG consumer on the changed surface:

1. **Backward-trace to the commitment point.** The VRF word that seeds the outcome must have been UNKNOWN
   on-chain when the player committed the input that the outcome pays out against (the deposit that
   created the lootbox; the bet placement that minted the `betId`; the burn that stamped the redemption
   day). Trace BACKWARD from each consumer's seed to the exact transaction where the player committed,
   and confirm the word had not yet landed at that point.
2. **No live, post-reveal, player-controllable input may enter the seed.** Once the word is on-chain, no
   value the player can still choose (claim timing, a `futurePrizePool` nudge, a second deposit, a chosen
   `amount`/`betId`/`level`) may change the seed or the outcome.
3. **Enumerate EVERY SLOAD inside the rng-window — not just the VRF-derived seed.** A non-VRF storage
   read consumed ALONGSIDE the word, that a player can change between the request and the fulfillment, is
   a distinct freshness-bug class. Walk every read inside the daily-resolution and lootbox-resolution
   windows over the repacked slots (RNG-06 below) and confirm each is either constant or a frozen snapshot.
4. **One-shot / replay-safe.** A consumer that can be re-triggered after its outcome is observable lets a
   player resolve again with a now-known word. Confirm each new consumer is single-shot by construction
   (the record is zeroed / the bet is `delete`d before resolution).

`advanceGame` itself is exempt (it IS the privileged resolver). The question is always whether a PLAYER
can learn or steer the word relative to their own committed input.

## Trust-boundary framing (so you do not waste passes)

`DegenerusGame.sol` + `contracts/modules/*.sol` all inherit the SAME `DegenerusGameStorage` base, so the
RNG-window storage slots (`rngWordByDay`, `lootboxRngPacked`, `lootboxRngWordByIndex`, `dailyIdx`) are one
shared layout across the modules — the box-spin / survival-flip / decimator resolvers are `delegatecall`
targets reading that one base, NOT separate storage. `StakedDegenerusStonk` and `BurnieCoinflip` are
standalone (regular CALL, own storage); they reach the game's words through the `rngWordForDay(day)` /
`rngLocked()` interface reads only. The box-spin resolvers guard `address(this) != GAME` so they execute
only inside a delegatecall from the Game. The residual risk is therefore **freshness / freeze / entropy
adequacy of the consumed word and of every co-read SLOAD**, NOT cross-module layout aliasing (that is the
389 slice).

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- **Lootbox / redemption claim/open TIMING as a player edge.** The open is permissionless and
  economically-incentivized; the seed is frozen at the request / index advance. Do NOT flag day/level/
  wait-to-open steering as a freshness bug — the word is fixed before the open, so when you choose to open
  cannot re-roll it. (A path where the word is NOT yet fixed at the player's commitment, or can be
  re-resolved fresh, IS in scope — that is a freshness break, not a timing edge.)
- **Degenerette RTP > 100% and the deliberately-near-worthless WWXRP token are by-design economics.** This
  slice cares ONLY about whether the RNG that drives them is fresh and adequately-entropic — NOT whether an
  EV is desirable. Do not flag "RTP too high" or "WWXRP worthless".
- **The documented reward rebalances** (EV-multiplier lift floor 90% / ceiling 145% / score-to-ceiling
  40,000; recycle-bonus ≥3-ticket relaxation; the EV-neutral redistributions where a spin stakes the value
  it replaces) are economics audited in the 392 slice. Here we care ONLY whether the RNG driving them is
  fresh and adequately-entropic, not whether the EV change is intended.
- **The far-future mint salvage quote being publicly known is by-design** — it is a deterministic PRICING
  quote off the SETTLED prior-day word (already revealed, immutable), shared by preview and execution so
  they agree; it is NOT a payout RNG and there is nothing to front-run. Do not flag the settled-word
  salvage seed as a freshness break.
- Operator-approval as the trust boundary; afking inclusive eviction; `claimBingo` no level guard
  (these are settled rulings — do not re-litigate).

## The thesis to BREAK (mapped to RNG-01..06)

We believe ALL of the following hold. Find a concrete counterexample to any one:

1. **(RNG-01) Every new/changed RNG consumer descends from a word committed BEFORE the player's input.**
   The per-index lootbox anchor word is fixed at the index advance AFTER the deposit; the per-bet nonce
   `betId` is fixed at placement BEFORE the word lands; the day's VRF word is consumed inside the
   `rngLocked` window. No consumer's seed admits a live, post-reveal, player-controllable input.
2. **(RNG-02) The decimator `uint32` claim-seed retains an adequate entropy floor, is non-grindable, AND
   yields an UNBIASED aggregate per-bucket reward distribution across many winners of one level.** The
   32-bit word is fixed at decimator resolution before any claim; the per-player `hash2(word, address)`
   mix decorrelates winners; the permissionless deterministic claim is non-grindable.
3. **(RNG-03) The box-spin resolvers (WWXRP / BURNIE / ETH) are ONE-SHOT and replay-safe.** A player
   cannot observe a spin outcome and re-trigger a fresh spin with a now-known word — the lootbox record is
   zeroed / the bet is `delete`d before resolution, and the `address(this) != GAME` guard plus the
   record-clear together fully prevent replay.
4. **(RNG-04) `resolveLootboxDirect` + every caller's spin seed are domain-separated** so no two
   same-word / same-player resolutions collide on the seed (the dropped `amount` term no longer
   disambiguates them; each caller supplies a per-resolution domain-separated word instead).
5. **(RNG-05) The redemption `day+1` pre-draw gate holds on the BURN side** — no zero-seed grind, and the
   local `GameTimeLib.currentDayIndex()` day calc cannot diverge from the game's `dailyIdx` at a day
   boundary to stamp a day whose `day+1` word is already on-chain.
6. **(RNG-06) Every SLOAD inside an rng-window over the repacked slots is freeze-invariant** — no
   player-controllable non-VRF read is consumed alongside the word between request and fulfillment.

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

- `contracts/libraries/EntropyLib.sol`: `hash2(a,b)` @23 (`keccak256(abi.encode(a,b))`, full-width
  64-byte preimage); `hash1(a)` @38 (single-word keccak).
- `contracts/modules/DegenerusGameLootboxModule.sol`: manual-open seed
  `keccak256(abi.encode(rngWord, player, amount))` @560 (STILL includes `amount`); `resolveLootboxDirect`
  @874 (`payable`; seed = `EntropyLib.hash2(rngWord, uint160(player))` @883 — `amount` DROPPED vs
  baseline); `resolveAfkingBox` live-level twin seed
  `keccak256(abi.encode(rngWord, player, day, amount))` @1084 (STILL includes `amount`); `_resolveLootboxRoll`
  @1965 (dispatches the 3 box-spin rolls; `allowEthSpin` gate @1245/@1973); recirc entry
  `allowEthSpin=false` @889; redemption ETH-spin `allowEthSpin=true` pool-pre-flush @976.
- `contracts/modules/DegenerusGameDegeneretteModule.sol`: BURNIE survival flip `hash2(rngWord, betId) & 1`
  @773 (`acc.burnieMint +=` @774 / `-=` @777); the spin seed/event `hash2(rngWord, betId)` @791; bet
  `delete degeneretteBets[player][betId]` @655; `acc.burnieMint` struct field @413, `mintForGame` @447;
  `resolveWwxrpSpinFromBox` @1292 (guard `address(this) != GAME` @1298; `S==9` bracket = `level/10` @1324
  live OUTPUT gate); `resolveBurnieSpinsFromBox` @1347 (guard @1353; survival
  `hash2(seed, BOX_SURVIVAL_TAG 0x537572766976616c) & 1` @1385); `resolveEthSpinFromBox` @1402
  (guard @1408); regular-bet WWXRP bracket `level/10` @750 (the unchanged twin).
- `contracts/modules/DegenerusGameDecimatorModule.sol`: winner-select `decBucketOffsetPacked[lvl]` write
  @269 (winners selected from the FULL word at snapshot); the claim-seed narrowing
  `round.rngWord = uint32(rngWord)` @277; `claimDecimatorJackpot` permissionless @293 (reads
  `decBucketOffsetPacked[lvl]` @312); `claimDecimatorJackpotMany` @325 (caches `packedOffsets` @338,
  `over = gameOver` ONCE @341); `_claimDecimatorJackpotFor` @385 (over branch @401, passes
  `round.rngWord` @410); `_awardDecimatorLootbox` @645 (delegatecalls `resolveLootboxDirect.selector` @673
  with `round.rngWord`).
- `contracts/StakedDegenerusStonk.sol`: `rngWordForDay(day)` iface @43; `BurnsBlockedBeforeDailyRng` error
  @120; `_claimRedemptionFor` @821 (lootbox leg reads `game.rngWordForDay(day + 1)` @878, entropy =
  `hash2(rngWord, uint160(player))` @879); `_submitGamblingClaimFrom` @976
  (`currentPeriod = GameTimeLib.currentDayIndex()` @983; gate `if rngWordForDay(currentPeriod)==0 revert`
  @991; `stamp != currentPeriod -> PriorDayUnresolved` @997; `_pendingResolveDay = currentPeriod` @998).
- `contracts/BurnieCoinflip.sol`: win/loss `(rngWord & 1) == 1` path; `processCoinflipPayouts`
  `onlyDegenerusGameContract` @204 modifier; `autoRebuyCarry` uint128 @154; `sdgnrsAutoRebuyArmed` @174;
  settle carry-roll application @412-417; `claimCoinflipCarry` @754 (`rngLocked` guard @759, carry @770).
- `contracts/modules/DegenerusGameAdvanceModule.sol`: `hash2(rngWord, FUTURE_KEEP_TAG)` keep-roll @~969;
  gameover historical combine `hash2(combined, w)` @~1400; redemption roll `(currentWord >> 8) % 151 + 25`
  @~1259; `processCoinflipPayouts` calls @1245/1309/1344/1844; `requestLootboxRng` index-advance +
  pending-clear (mid-day gate).
- `contracts/RngWindowFreezeHandler.sol` authoritative in-window slots @`a8b702a7` (from `forge inspect`):
  `rngWordByDay` slot 10; `lootboxRngPacked` slot 34 (low 48 = index cursor); `lootboxRngWordByIndex`
  slot 35; `dailyIdx` slot 0 byte 3 (uint24). These are the freeze-spine slots to enumerate for RNG-06.

## Concrete break-targets (the prime target — charge it HARD)

### 1. (PRIME — RNG-02 / FC-391-04, MED) Decimator `uint32` claim-seed distribution bias (the dedicated distribution-bias target)

`DecClaimRound.rngWord` was narrowed `uint256 → uint32` (`round.rngWord = uint32(rngWord)`,
`DegenerusGameDecimatorModule.sol:277`). **This is the claim-time LOOTBOX seed ONLY** — the winning
subbuckets were already selected from the FULL word at snapshot (`decBucketOffsetPacked` write @269). At
claim, the `uint32` word flows `_claimDecimatorJackpotFor` (@385, passes `round.rngWord` @410) →
`_awardDecimatorLootbox` (@645) → `resolveLootboxDirect` (delegatecall @673) → seed =
`hash2(uint32-word, uint160(player))` (`LootboxModule:883`).

The narrowing is **freeze-safe** — the 32-bit word is fixed at decimator resolution, before any claim; the
player cannot choose it; the per-player address mix makes each draw effectively independent. **DO NOT
re-litigate freeze-safety on this item.**

INSTEAD demand a REAL distribution argument. Across the WHOLE winning-bucket population of ONE level
(potentially MANY winners sharing the SAME 32-bit word, differing only by their 160-bit address in
`hash2(word, address)`), is the JOINT distribution of per-claim lootbox tier outcomes **biased,
correlated, or grindable**? Specifically find:
- **(i)** any aggregate per-bucket reward-distribution bias the 32-bit floor introduces — e.g. a
  correlation across winners sharing the word that a multi-account actor (controlling several winning
  addresses on the same level) could exploit; or a tier-outcome skew vs the full-word baseline (does the
  mapping from `hash2(word, addr)` to a lootbox tier concentrate, given only 2^32 distinct words across
  the population?);
- **(ii)** any grinding / retry-timing edge given the permissionless deterministic claim (can a winner or
  a third party choose WHICH address claims, or in what order, to bias the realized tier?);

OR state **VERIFIED SOUND** with the CONCRETE reason: the per-player `hash2(word, address)` decorrelates
winners because <reason>; the 32-bit floor over the bucket population is adequate because <reason>. A
hand-wave ("address-mixed so fine") is NOT acceptable — require the distribution reasoning (how the
2^32-word entropy floor interacts with the per-address mix across the joint population, and whether a
multi-account actor gains any tier-selection edge).

## The remaining owned leads + inherited cross-refs (numbered break-targets at map severity)

### 2. (RNG-04 / FC-391-01, LOW-MED) `resolveLootboxDirect` dropped the `amount` term — caller domain-separation now load-bearing

`resolveLootboxDirect` (`LootboxModule:874`) dropped `amount` — the seed is now
`hash2(rngWord, uint160(player))` (@883), while the manual open (@560) and `resolveAfkingBox` (@1084)
STILL include `amount`. Caller-side domain separation is now the ONLY thing preventing a collision:
Degenerette passes `hash2(rngWord, betId)`, decimator passes the narrowed `round.rngWord`, redemption
passes `hash2(rngWordForDay(day+1), player)`, ETH-spin recirc passes `hash2(seed, BOX_RECIRC_TAG)`.
**Find ANY caller path that feeds TWO same-word / same-player resolutions through `resolveLootboxDirect`
that would now collide on the seed** (where the dropped `amount` term used to disambiguate them) — e.g. a
player with two distinct boxes at the same index resolving with the same caller-word, or two decimator
claims for the same winner+level reaching `resolveLootboxDirect` with the same `round.rngWord`. Prove
no-collision by enumerating the per-caller domain term, OR surface the colliding path.

### 3. (RNG-03 / FC-391-02, INFO-LOW) Box-spin replay / one-shot

The box-spins (WWXRP 15% / BURNIE 10% / ETH 5%) are a NEW consumer off the permissionless lootbox-open /
bet-resolution surface (resolvers `DegeneretteModule:1292/1347/1402`, each guarded `address(this) != GAME`
@1298/@1353/@1408). **Find ANY path where a player can OBSERVE a spin outcome and then re-trigger a fresh
spin with a now-known word** — confirm the lootbox record is zeroed / the bet is `delete`d (@655) BEFORE
resolution so the spin resolves only once, and that the module guard + record-clear TOGETHER fully prevent
replay (e.g. a partial-resolution revert that leaves the record intact for a re-call after the word is
known; a delegatecall path that reaches a resolver with the guard satisfied but the record not yet
cleared). Prove single-shot-by-construction or surface the replay path.

### 4. (RNG-03 / RNG-01 / FC-391-03, LOW) BURNIE survival flip — freeze + cross-bet accumulator underflow

The BURNIE survival flip (`DegeneretteModule:773`) double-or-nothings every BURNIE bet payout on
`hash2(rngWord, betId) & 1` (`acc.burnieMint +=` @774 / `-=` @777, summed then `mintForGame` @447). Both
`rngWord` (the committed per-index anchor) and `betId` (the placement nonce) are committed before
fulfillment. Charge the council to **(i)** confirm the flip is single-shot per bet and freeze-safe (the
seed binds the committed anchor + the placement nonce; no live input), and **(ii)** confirm
`acc.burnieMint -=` cannot TRANSIENTLY underflow the unsigned running total across a multi-bet batch —
`acc` is SHARED across bets in the batch; the per-bet additions net to zero for the same bet, but confirm
no cross-bet ordering can drive the running total negative before a later `+=` (e.g. a losing bet's `-=`
applied before the matching `+=` of its own spins, or interleaved across bets). Prove no underflow path or
surface it.

### 5. (RNG-05 / FC-391-05, LOW) Redemption `day+1` pre-draw gate — day-boundary divergence

The burn is admitted only once `currentPeriod`'s word is recorded
(`if game.rngWordForDay(currentPeriod) == 0 revert BurnsBlockedBeforeDailyRng`,
`StakedDegenerusStonk:991`; `currentPeriod = GameTimeLib.currentDayIndex()` @983). The lootbox leg reads
`game.rngWordForDay(day + 1)` (@878) — `day+1` is NOT yet drawn at burn time. **Find ANY day-boundary
where `GameTimeLib.currentDayIndex()` can diverge from the game's `dailyIdx` so a burn stamps a day whose
`day+1` word is ALREADY on-chain** (a zero-seed / known-draw grind). Spell out the wall-day-vs-advance-lag
interleavings to try:
- a wall day rolled past `dailyIdx` but the advance has not yet run (does `currentDayIndex()` return the
  NEW day while `rngWordForDay(newDay)` is still 0, forcing the revert? confirm the gate pins a DRAWN day);
- a same-block burn racing the `advanceGame` that draws the next word (ordering within the block);
- any path where `currentPeriod` could resolve to a day for which both `rngWordForDay(currentPeriod) != 0`
  AND `rngWordForDay(currentPeriod + 1) != 0` already hold (so the lootbox leg reads an already-on-chain
  `day+1` word).

Prove the gate pins a not-yet-drawn `day+1` by construction (`currentPeriod <= dailyIdx`, and `dailyIdx+1`
undrawn until the next advance), OR surface a concrete boundary interleaving.

### 6. (Inherited cross-ref FC-389-05, INFO/LOW — the RNG-consumption half of the decimator `uint32` narrowing)

The narrowing-equivalence half (the gas-identity counterpart of break-target 1). Confirm
`round.rngWord = uint32(rngWord)` is a deterministic value FIXED-AT-RESOLUTION with
**predictability-WITHOUT-control** (player + word both frozen; permissionless deterministic claim — a
third party can compute the outcome but cannot change it), and that the narrowed word's grind / retry-timing
posture is sound (no actor can re-resolve to get a different `uint32` word; the claim is idempotent on the
fixed word). The storage-packing correctness of the `uint32` into the `DecClaimRound` slot (no co-resident
field corruption) couples to the 389 STORAGE slice — but the RNG-consumption half (grind/retry posture of
the consumed narrowed word) is OWNED here; confirm it.

### 7. (Inherited cross-ref FC-392-11, MED — the RNG-lock-coverage half; backing/EV half owned by 392)

`claimCoinflipCarry` (`BurnieCoinflip:754`) reverts on `degenerusGame.rngLocked()` (@759) and reads the
carry (@770); `processCoinflipPayouts` is `onlyDegenerusGameContract` (@204) and applies the win/loss roll
in the advance walk (settle carry-roll application @412-417). **VERIFY the `rngLocked` guard FULLY covers
the roll application** — i.e. that there is NO window where the pending day's stake word is already
on-chain (resolvable) yet a carry claim / settle can read or act on the roll outcome BEFORE the lock
blocks it (the v62 RNG-lock-bypass class). Trace the exact interval between the word landing and the
`rngLocked` flag covering it, and the interval over which `claimCoinflipCarry` / the settle can read the
carry. The backing / EV half (whether a loss sequence drops sDGNRS backing below obligations) is 392's;
**here confirm ONLY that the RNG-lock window over the carry roll is airtight** — no read-or-act on a known
roll outcome before the lock.

## RNG-06 sweep — in-window SLOAD enumeration over the repacked slots

Over the repacked freeze-spine slots — `rngWordByDay` slot 10, `lootboxRngPacked` slot 34 (low 48 = index
cursor), `lootboxRngWordByIndex` slot 35, `dailyIdx` slot 0 byte 3 (the authoritative `forge inspect`
slots at `a8b702a7`) — **enumerate EVERY SLOAD consumed alongside a VRF word** in the daily-resolution and
lootbox-resolution windows and confirm none is a player-controllable NON-VRF read that can change between
the request and the fulfillment. In particular, break these two specific claims:
- the EntropyLib `hash1` / `hash2` migrations are claimed to be **byte-identical preimages** (full-width
  inputs, so `abi.encodePacked == abi.encode` at the migrated 2-word sites; `hash1(a) == keccak256(abi.encode(a))`
  for a single 32-byte word) — find ANY migrated site where the preimage bytes DIFFER from the baseline
  (a width mismatch, a padding ambiguity, an `address`-vs-`uint256` encoding gap, a tag-derivation drift);
- the `activityScore` threaded into the box-spin EV is claimed to be a **FROZEN snapshot** unpacked from
  the lootbox / bet record (written at deposit / placement), NOT a live read — find ANY spin path that
  reads a LIVE `activityScore` (or any other live player-controllable field) inside the resolution rather
  than the frozen record snapshot.

State VERIFIED SOUND with the concrete reason for each SLOAD (constant / frozen-snapshot / VRF-derived),
or surface the live-read.

## Output (per item)

For each break-target AND each thesis point (RNG-01..06), state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (multi-tx / observe-then-retrigger where
  the ordering matters) · STATE VAR + `file:line` at `a8b702a7` · SEVERITY (per the threat priority above
  — RNG/freeze breaks are the dominant, highest-severity class here) · WHY the existing freeze / one-shot /
  domain-separation / `rngLocked` / day-gate protections do NOT stop it.
- **VERIFIED SOUND / IDENTICAL:** the property and the SPECIFIC reason it holds — cite the commitment
  point, the domain-separation tag, the one-shot record-clear / `delete`, the `rngLocked` window, the
  day-gate bound, or the preimage-byte equivalence — so the adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7` via
`git show`. The council finds; the adjudicator (Claude) reconciles at 391-02.
