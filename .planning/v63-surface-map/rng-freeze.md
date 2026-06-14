# v63 Surface Map — Dimension: RNG-freeze spine (VRF word freshness & freeze window)

BASELINE: `77580320` (last formally audited frozen point)
SUBJECT (HEAD): `a8b702a7`
Scope: ~60 commits — gas rounds 3-8, storage-packing phase, BURNIE emission rework, EVM-target bumps, lootbox/Degenerette/decimator/redemption feature changes.

North-star invariant under test: every variable that interacts with a VRF word must be frozen between rng-request and unlock relative to players. For each RNG consumer in the changed code, the word must have been unknown when the player committed their input, and no player-controllable non-VRF SLOAD inside the rng-window may change between request and fulfillment.

This is READ-ONLY analysis. Findings below are LEADS for an adversarial sweep, not confirmed bugs. The headline conclusion: the freeze spine is intact across the change set; the new feature paths (box-spins, survival flip, redemption legs) are keyed off words that are committed before player input, and the EntropyLib migrations are byte-identical preimages. The one genuinely behavior-changing item that touches an RNG distribution is the decimator claim-word narrowing to 32 bits (freeze-safe, but a real entropy reduction worth a closer look).

---

## 1. EntropyLib hash migration (byte-identity)

`contracts/libraries/EntropyLib.sol` — added `hash1(uint256)` (single-word keccak, scratch-slot). The existing `hash2(uint256,uint256)` is unchanged.

- `hash1(a) == keccak256(abi.encode(a))` — `abi.encode(uint256)` is exactly 32 bytes, so this is byte-identical to the documented equivalent. CORRECT.
- `hash2(a,b) == keccak256(abi.encode(a,b))` for full-width words — 64 bytes, no padding ambiguity.

Migration sites verified byte-identical against baseline preimages (full-width inputs only, so `abi.encodePacked == abi.encode` for the migrated 2-word cases):
- AdvanceModule:969 `FUTURE_KEEP_TAG` keep-roll seed — was `keccak256(abi.encodePacked(rngWord, FUTURE_KEEP_TAG))`, now `hash2(rngWord, uint256(FUTURE_KEEP_TAG))`. Identical.
- AdvanceModule:1400 gameover historical-word combine — was `keccak256(abi.encodePacked(combined, w))`, now `hash2(combined, w)`. Identical.
- AdvanceModule:~470 `BONUS_TRAITS` daily-coin salt — the inline `keccak256("BONUS_TRAITS")` became the precomputed `BONUS_TRAITS_TAG` constant; same value.
- JackpotModule — multiple `hash2(randWord, lvl)` / `keccak256(abi.encode(randWord, lvl, COIN_JACKPOT_TAG))` sites consolidated into helpers (`_rollWinningTraitsPair`, `_emitDailyWinningTraits`, `_soloAdjustedEntropy`). The `COIN_JACKPOT_TAG` derivation is preserved verbatim at JackpotModule:1806-1809. All consume the day's frozen `randWord`.
- StakedDegenerusStonk:879 redemption lootbox entropy — was `keccak256(abi.encode(rngWord, player))`, now `hash2(rngWord, uint256(uint160(player)))`. An `address` ABI-encodes as a left-padded 32-byte word == `uint256(uint160(player))`, so byte-identical.

No freshness impact: all migrated sites consume already-committed words.

## 2. `resolveLootboxDirect` seed change (NOT byte-identical) — intended behavior change

`contracts/modules/DegenerusGameLootboxModule.sol:872`. The auto-resolve direct-open seed changed from
`keccak256(abi.encode(rngWord, player, amount))` (baseline) to `EntropyLib.hash2(rngWord, uint256(uint160(player)))` — **`amount` dropped from the seed**.

- The manual open path (`_openLootBoxLegWith`:560) STILL uses `keccak256(abi.encode(rngWord, player, amount))`. So two distinct seed schemes now coexist (manual vs auto-resolve). Both are freeze-safe.
- Freeze property holds: `rngWord` is the per-index VRF anchor (fixed at index advance, unknown at deposit) and `player` is fixed. No live, post-reveal input enters the seed (the comment explicitly calls out that neither claim timing nor a futurePrizePool nudge can re-roll the outcome).
- Caller-side domain separation is now load-bearing: callers pass a per-resolution domain-separated word — Degenerette passes `hash2(rngWord, betId)`, decimator passes the narrowed `round.rngWord`, redemption passes `hash2(rngWordForDay(day+1), player)`, ETH-spin recirc passes `hash2(seed, BOX_RECIRC_TAG)`. Because the seed is `hash2(callerWord, player)`, two of a player's resolutions at the same index with the same caller-word would collide — but every caller already domain-separates, so collisions are avoided BY THE CALLER, not by the seed function. Worth confirming in the sweep that no caller path can feed two same-amount/same-word resolutions for one player (the dropped `amount` term no longer disambiguates them).

## 3. NEW FEATURE — lootbox Degenerette box-spins (the largest RNG surface added)

`DegenerusGameLootboxModule.sol` `_resolveLootboxRoll` now dispatches 3 roll outcomes into the Degenerette module as "box-spins": WWXRP spin (15%), triple-BURNIE spins under a survival flip (10%), ETH spin (5%, direct boxes only). New resolvers in `DegenerusGameDegeneretteModule.sol`: `resolveWwxrpSpinFromBox`, `resolveBurnieSpinsFromBox`, `resolveEthSpinFromBox` (lines ~1290-1430 current).

Seed derivation: each spin gets `hash2(seed, BOX_*_SPIN_TAG)` where `seed` is the box's per-resolution seed (itself derived from the committed index/anchor word). Counter-tagged so the spins consume no primary-chunk bits and never collide with the box's own draws. Within a resolver, per-reel seeds use `packedTraitsDegenerette(ss)` / `packedTraitsDegenerette(hash2(ss,1))`, and the BURNIE survival flip uses `hash2(seed, BOX_SURVIVAL_TAG) & 1`.

Freeze assessment:
- All spin entropy descends from `seed`, which descends from the box's committed VRF anchor word — unknown when the player committed (deposited the box / placed the bet). Freeze-safe.
- `activityScore` threaded into spin EV is the FROZEN snapshot unpacked from the lootbox record (written at deposit, `_openLootBoxLegWith` passes `score`; the bet path passes the bet's snapshot). Confirmed not a live read. Freeze-safe.
- The ETH-spin recirc (`resolveEthSpinFromBox`) flushes its pool/claimable writes to storage BEFORE opening the recirc box, and the recirc box is opened with `allowEthSpin=false` so no ETH-spin can cascade. This is a solvency/ordering guard, not a freshness one, but it bounds recursion (no unbounded spin chain that could re-read RNG).
- The WWXRP spin's S==9 whale-halfpass award reads live `level` for the bracket index (DegeneretteModule:~1330). This is an OUTPUT gate (which 10-level bracket gets the one-per-bracket pass), not a seed input, and matches the existing regular-bet WWXRP jackpot behavior (the unchanged bet path reads `level` live at line 750). Not a freshness regression.

Lead for the sweep: the box-spin path is a NEW consumer reachable from the permissionless lootbox-open / bet-resolution surface. Confirm there is no path where a player can OBSERVE a spin outcome and then re-trigger a fresh spin with a now-known word — i.e., that the box seed is fully bound to the committed anchor and the spin can only be resolved once (the lootbox record is zeroed before resolution; the bet is `delete`d at resolution start). The dispatch is delegatecall into a module that guards `address(this) != GAME` — confirm that guard plus the one-shot record-clear fully prevents replay.

## 4. NEW FEATURE — BURNIE survival flip on Degenerette bets

`DegenerusGameDegeneretteModule.sol:772-780`. Every BURNIE bet payout double-or-nothings on `EntropyLib.hash2(rngWord, betId) & 1`.

- `rngWord` is `lootboxRngWordByIndex[index]` (committed at index swap, after the bet was placed). `betId` is the bet nonce assigned at placement, before the word lands. Both committed before fulfillment → outcome fixed at fulfillment.
- The seed is the per-bet lootbox seed, which BURNIE bets never otherwise consume (lootbox-share is ETH-only), so no bit reuse / cross-draw correlation.
- A losing bet pays zero whether resolved or abandoned, so selective resolution earns nothing (no resolution-timing edge). The accumulator math (`acc.burnieMint += / -=`) is internally consistent (the per-spin sum is added once, then the flip doubles or zeroes it).
- EV-neutral (x2 at 50/50). Confirm in the sweep that the flip is single-shot per bet and that `acc.burnieMint -=` cannot underflow (the per-spin additions for this bet are exactly `totalPayout`, so the subtraction nets to zero for this bet — but acc is shared across bets in the batch; confirm cross-bet accumulator ordering can't transiently underflow an unsigned running total).

## 5. NEW FEATURE — coinflip-seeded BURNIE emission (BurnieCoinflip)

`contracts/BurnieCoinflip.sol`. Constructor pre-seeds 200k BURNIE/day flip stakes for days 1-20 to VAULT and sDGNRS; an sDGNRS perpetual auto-rebuy latch (`sdgnrsAutoRebuyArmed`) arms once day 20 settles. Daily storage repacked: `coinflipStakePacked` (2 days/slot, 128-bit lossless wei lanes), `coinflipDayResultPacked` (32 days/slot, 8-bit 3-state byte). Added `claimCoinflipCarry`.

- Win/loss is `(rngWord & 1) == 1` (BurnieCoinflip:822) — keyed off the VRF word, unchanged. The bonus reward% is `keccak256(abi.encodePacked(rngWord, epoch)) % 20` etc. — also unchanged shape.
- `processCoinflipPayouts` is `onlyDegenerusGameContract` and is only called from the advance chain (AdvanceModule:1245/1309/1344/1844) with the day's `currentWord`/`fallbackWord`/`derivedWord` — i.e., inside the RNG-locked daily resolution window, with the day's own fresh word. Stakes for that day are committed earlier via `_addDailyFlip` and gated by the `flipsBlocked` / `rngLocked` checks.
- The constructor-seeded days 1-20 are resolved by the same `processCoinflipPayouts(bonus, dayWord, day)` path using each day's own VRF word — the pre-seeded stakes are committed at deploy (long before any day's word), so they cannot be steered. Freeze-safe.
- `claimCoinflipCarry` reverts on `rngLocked` (BurnieCoinflip:752) — the carry is the pending day's stake whose word may already be on-chain before the resolution walk; the lock blocks the claim during that window. Same posture as the rebuy toggle.
- The 8-bit day-result packing is lossy by design (a resolved loss reads back as sentinel `1`; reward% on a loss is discarded as functionally unused). Confirm in the sweep that win days always store reward >= 50 (so `win = b >= 50` never misclassifies a low-reward win) — the reward range is [50..156], so the threshold is safe by construction, but it depends on the +bonus path never producing a sub-50 reward on a win (`COINFLIP_EXTRA_MIN_PERCENT` + range, plus a 50/150 extreme split; the normal floor is 78, the extreme-unlucky is exactly 50). The exactly-50 case maps to `b=50 >= 50 == win` — correct.

Removed: `claimCoinflipsForRedemption` and the sDGNRS arm of `onlyBurnieCoin`. sDGNRS now sources redemption BURNIE entirely through its flip position + the submit-time settle, not a special skip-RNG-lock claim. This removes an RNG-lock-bypass surface — a tightening, not a loosening.

## 6. Redemption pre-draw RNG gate (`BurnsBlockedBeforeDailyRng`) — the v62 / pre-C4A fix

`contracts/StakedDegenerusStonk.sol`. Burn-side gate at `_submitGamblingClaimFrom`:991 — `if (game.rngWordForDay(currentPeriod) == 0) revert BurnsBlockedBeforeDailyRng();`. Day computed locally via `GameTimeLib.currentDayIndex()` (a pure fn of `block.timestamp`, identical to the game's `_simulatedDayIndex`).

Backward trace of the redemption lootbox consumer:
- Burn admitted only once `currentPeriod`'s word is recorded → pins the stamp to a DRAWN day (`currentPeriod == dailyIdx`).
- Pool is stamped to `currentPeriod` and resolves on the NEXT day's draw (`pendingResolveDay` → AdvanceModule reads it and resolves with `currentWord`).
- The lootbox leg reads `game.rngWordForDay(day + 1)` (`_claimRedemptionFor`:878) — `day+1` is NOT yet drawn at burn time, so a post-advance burn cannot grind a known draw.
- The redemption ROLL (`(currentWord >> 8) % 151 + 25`, AdvanceModule:1259) and the lootbox draw both use `day+1`'s word — consistent and fresh.
- The request→fulfillment window is independently blocked by the `rngLocked` guard in `burn()`/`burnWrapped()`.

This closes the v62 REDEMPTION-ZERO-SEED gap (window-(a) burn → claimRedemption lootbox reads zero `rngWordForDay(day+1)` → grindable). The gate plus the local-day-calc is the documented fix. The freeze property is sound on this path. Lead for the sweep: confirm `GameTimeLib.currentDayIndex()` cannot diverge from the game's `dailyIdx` at a day boundary in a way that lets a burn stamp a day whose `day+1` word is already on-chain (the gate requires `rngWordForDay(currentPeriod) != 0`, which by construction means `currentPeriod <= dailyIdx`; if a wall-day has rolled past `dailyIdx` but the advance hasn't run, `rngWordForDay(currentPeriod)` would be 0 for the new day and the burn reverts — so the stamp can only be the drawn day. Worth a concrete boundary test).

New payable redemption legs: `resolveRedemptionLootbox` / `creditRedemptionDirect` (Game.sol stubs are `payable`, forward `msg.data` via delegatecall preserving callvalue; lootbox-module bodies pull the stETH remainder via `transferFrom`). These move VALUE, not RNG — out of scope for freshness except that `resolveRedemptionLootbox` is the consumer of the `day+1` word covered above. `resolveLootboxDirect` is `payable` because it's reachable from the redemption ETH-spin recirc; the in-flight `msg.value` survives the delegatecall chain.

## 7. Decimator offset-key isolation (DEC-ALIAS fix) + rngWord narrowing

`contracts/modules/DegenerusGameDecimatorModule.sol`.

(a) Terminal offset key moved to `lvl + 1` (`decBucketOffsetPacked[lvl + 1]`, lines 1014/1063/1095). Rationale: `level` lags the active purchase level by one, so a gameover terminal write keyed at `lvl` could alias a live unclaimed regular round's `decBucketOffsetPacked[lvl]` and corrupt its winning-subbucket selection. Keying terminal at `lvl+1` isolates it. This is a CORRECTNESS fix for winner selection (the v62 DEC-ALIAS remediation), and the winning subbuckets are selected from the FULL VRF word at snapshot — it does not touch RNG freshness, but it does change which storage slot a VRF-derived winner-selection word lands in. Confirm in the sweep that the regular claim path reads `decBucketOffsetPacked[lvl]` and terminal reads `[lvl+1]` consistently across all readers (validate/consume/view), with no remaining reader of the old `[lvl]` for terminal.

(b) `DecClaimRound.rngWord` narrowed from `uint256` (baseline) to `uint32` (`round.rngWord = uint32(rngWord)`, line 277; struct now packs into one slot). This is the claim-time LOOTBOX seed ONLY — winners were already selected from the full word (`decSeed`) and packed into `decBucketOffsetPacked`. At claim, `round.rngWord` flows to `_awardDecimatorLootbox` → `resolveLootboxDirect(winner, amount, rngWord, evScore, false)` → seed becomes `hash2(uint32-word, uint160(player))`.
- Freeze-safe: the 32-bit word is fixed at decimator resolution (before any claim); the outcome cannot be ground or predicted (the player can't choose the word, and the seed is domain-separated by the frozen winner address). The struct comment reasons through this explicitly.
- BUT it is a genuine entropy reduction: the VRF contribution to the per-claim lootbox draw is now 32 bits across the whole winning-bucket population. Because each winner's seed is mixed with their 160-bit address via hash2, the per-player draw is still effectively full-entropy and independent. The reduction matters only if some aggregate distribution property (e.g., the joint distribution of tier outcomes across many winners of one level) becomes biased or correlated. This is the single most distribution-affecting RNG change in the set and the prime lead for the adversarial sweep — confirm no per-bucket reward-distribution bias is exploitable.

## 8. Mid-day RNG threshold gate simplification (dd09cb99)

`DegenerusGameAdvanceModule.sol` `requestLootboxRng` — removed the 40k `BURNIE_RNG_TRIGGER` bypass; the gate is now solely the owner-tunable threshold over `pendingEth + BURNIE-ETH-equivalent`. The freeze mechanism is unchanged: on request, the lootbox index is advanced (`_lrAdvanceIndexClearPending`) and pending ETH/BURNIE zeroed, so tickets purchased after VRF delivery target the NEXT index and cannot be resolved by this word. Removing a bypass makes RNG requests STRICTER (harder to trigger), not looser — it cannot widen the freeze window. No freshness impact.

`_lrAdvanceIndexClearPending` is a single-RMW packing of the prior 3 `_lrWrite` calls (index+1, pending-eth=0, pending-burnie=0). Same effect, one SSTORE. The mid-day-swap-pending check now reads the packed slot once (`lootboxRngPacked` shift/mask) instead of two `_lrRead` calls — behavior-identical.

## 9. reverseFlip nudge (storage narrowed, semantics unchanged)

`DegenerusGame.sol:1817` `reverseFlip` still gates on `if (rngLockedFlag) revert RngLocked()` — nudges only before the VRF request is in-flight. `totalFlipReversals` narrowed `uint256 → uint64` (packed with `lastVrfProcessedTimestamp`); bounded by supply/1e20 << 2^64. The nudge is added to the raw word in `_applyDailyRng` (and zeroed) and to the lootbox word in the inlined daily-drain finalize (AdvanceModule:291, `cw += totalFlipReversals`). Baseline did the identical `cw += totalFlipReversals; _finalizeLootboxRng(cw)` — the HEAD inlines the body (same `LR_INDEX-1` slot, same emit). Behaviorally identical for the freeze concern. The gameover fallback path pre-subtracts `totalFlipReversals` (AdvanceModule:1340) to cancel nudges against the VRF-dead historical+prevrandao word — unchanged.

## 10. Far-future mint salvage seed (dedup, settled-word)

`DegenerusGameMintStreakUtils.sol:232` `_farFutureSeed` extracted: `keccak256(abi.encodePacked(player, rngWordByDay[_simulatedDayIndex() - 1]))`, computed once and shared by the swap quote and the BURNIE split (previously duplicated). Uses the SETTLED prior-day word (already revealed, immutable) — intentional for a pricing quote so preview and execution derive the same offer. Not a payout RNG; the settled word being known to the player is by-design (no reveal to front-run). The dedup REMOVES a preview/execution-mismatch risk. No freshness regression.

---

## Summary of RNG consumers in changed code, backward-traced

| Consumer | Word source | Committed before player input? | Verdict |
|---|---|---|---|
| Daily jackpot traits/coin (JackpotModule) | day's `randWord` | yes (daily VRF, rngLocked window) | freeze-safe (refactor only) |
| Coinflip win/loss + bonus (BurnieCoinflip) | day's `rngWord` via advance | yes (stake committed pre-word) | freeze-safe (seed-emission rework, win shape unchanged) |
| Lootbox manual open | per-index anchor word | yes (index advance post-deposit) | freeze-safe (seed unchanged) |
| Lootbox auto-resolve (`resolveLootboxDirect`) | caller-domain-separated word | yes | freeze-safe; `amount` dropped from seed (caller now disambiguates) |
| Box-spins (WWXRP/BURNIE/ETH) | `hash2(boxSeed, TAG)` | yes (boxSeed from committed anchor) | freeze-safe; NEW surface, confirm one-shot/no-replay |
| BURNIE survival flip | `hash2(rngWord, betId)` | yes (both pre-fulfillment) | freeze-safe; confirm cross-bet acc no underflow |
| Redemption roll + lootbox | `rngWordForDay(day+1)` | yes (day+1 undrawn at burn; burn-gate pins drawn day) | freeze-safe; v62 gap closed |
| Decimator claim lootbox | `uint32(round.rngWord)` | yes (fixed at resolution) | freeze-safe; 32-bit ENTROPY REDUCTION — prime sweep lead |
| Far-future mint salvage quote | settled prior-day word | n/a (public quote, by-design) | not a payout RNG |
| reverseFlip nudge | adds to raw word pre-lock | gated by rngLockedFlag | freeze-safe (semantics unchanged) |

## Top leads for the adversarial sweep
1. **Decimator 32-bit claim-word narrowing** (§7b) — confirm the reduced VRF entropy can't bias the per-bucket lootbox reward distribution exploitably. MED.
2. **`resolveLootboxDirect` seed dropped `amount`** (§2) — confirm no caller path feeds two same-word/same-player resolutions that would now collide (the `amount` term used to disambiguate). LOW-MED.
3. **Box-spin replay/one-shot** (§3) — confirm the record-clear + `address(this)!=GAME` guard fully prevent observing a spin outcome and re-triggering with a known word. INFO-LOW.
4. **Survival-flip cross-bet accumulator** (§4) — confirm `acc.burnieMint -=` cannot transiently underflow across a multi-bet batch. LOW.
5. **Redemption day-boundary** (§6) — concrete boundary test that the burn-gate's local day calc can't stamp a day whose `day+1` word is already on-chain. LOW.
