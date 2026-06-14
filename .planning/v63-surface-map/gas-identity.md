# v63 Surface Map — Dimension: Gas / packing behavior-identity claims

BASELINE `77580320` → SUBJECT `a8b702a7` (~60 commits: gas rounds 3-8, storage-packing
Stage A/B, BURNIE emission rework, EVM-target bumps, gameplay/economic features).

This dimension audits the claims that many edits are **behavior-identical** or
**RNG-byte-identical**: raw `msg.data` dispatch, delegatecall round-trip elision,
nibble-table library migrations, `hash1`/`hash2` keccak-preimage migrations,
JackpotBucketLib changes, and the Stage B storage packing. Goal: find any place where a
"behavior-identical" claim is actually a silent behavior change.

Method: per-file `git diff 77580320 a8b702a7`, read current + baseline source, and
**independently recompute** the load-bearing identities (selectors, keccak preimages,
nibble tables, bit layouts) in Python rather than trusting the commit prose.

Overall result: **every identity claim I could verify holds.** The two changes that are
genuinely NOT byte-identical (DecClaimRound.rngWord narrowed to uint32; the StakedStonk
solvency-scalar narrowings) are openly declared as narrowings in the commit messages, not
as byte-identity claims, and are defensible under documented magnitude bounds. They are
recorded below as focus areas for the later adversarial / solvency sweep, not as
gas-identity defects.

---

## 1. PriceLookupLib nibble-table migration — VERIFIED IDENTICAL

`contracts/libraries/PriceLookupLib.sol:21-41`. Baseline had explicit 10-99 branches
before the modulo plus a 5-arm cycle chain; HEAD collapses to one cycle chain plus a
branch-free nibble table:

```solidity
return 0.04 ether * ((0x4333222111 >> ((cycleOffset / 10) * 4)) & 0xF);
```

I exhaustively compared old vs new `priceForLevel` over the full domain `level ∈ [0, 99999]`
(covers all decade buckets and milestone boundaries) and over `cycleOffset ∈ [0,99]`:
**0 mismatches.** The removed explicit 10-99 branches are subsumed because for `level ∈
[10,99]`, `cycleOffset == level` and is never 0, so the single cycle chain reproduces them.
The `unchecked` is safe (max product `0.04 ether * 15` ≪ 2^256). Intro tiers (0-4 → 0.01,
5-9 → 0.02) and the milestone arm (`cycleOffset==0 → 0.24`) are preserved verbatim.

## 2. JackpotBucketLib — VERIFIED IDENTICAL (one `unchecked` wrap, no cap change)

`contracts/libraries/JackpotBucketLib.sol:293-311`. The ONLY contract change is wrapping
`bucketOrderLargestFirst` in `unchecked`. `k` increments at most 3 times (the 3 indices !=
largestIdx), so `order[k++]` touches indices 1..3 — no array OOB, and `++i` on `uint8 i<4`
never overflows. Output unchanged for all inputs.

NOTE: the "JackpotBucketLib cap change (≤maxTotal+2/+4)" referenced in memory is a
TEST-side slack recalibration (`204a91bb`), **not** a contract change — `capBucketCounts`
and `bucketShares` are byte-identical to baseline.

## 3. BitPackingLib — VERIFIED IDENTICAL (dead-constant removal only)

`contracts/libraries/BitPackingLib.sol`. Removed `MASK_1`/`MASK_2`. Grep confirms no code
references `BitPackingLib.MASK_1` or `BitPackingLib.MASK_2` (the `MASK_2` hits in
DegeneretteModule are a LOCAL constant). No logic touched.

## 4. `delegatecall(msg.data)` dispatch refactor — VERIFIED SELECTOR-SAFE (30 sites)

`contracts/DegenerusGame.sol` — 30 thin wrappers changed from
`delegatecall(abi.encodeWithSelector(IModule.fn.selector, args...))` to
`delegatecall(msg.data)`. The wrappers keep their **typed (unnamed) parameters**, so:

- The Solidity-generated external ABI decoder still validates calldata on entry (short
  calldata, dirty high bits on narrow types, malformed array offsets all still revert at
  the wrapper before forwarding) — identical revert surface to the re-encode path.
- The forwarded `msg.data` carries the wrapper's own selector, which the module routes on.

I extracted all 30 wrapper signatures and the matching module function signatures from
source and computed both selectors with keccak. **All 30 wrapper selectors == module
selectors** (full table below). This is the load-bearing identity, and it holds:

| fn | sel | fn | sel |
|---|---|---|---|
| advanceGame | 0x75b5e924 | claimDecimatorJackpot | 0x57f5faf5 |
| wireVrf | 0x06349d97 | claimDecimatorJackpotMany | 0x1961741f |
| claimBingo | 0x039349d9 | claimTerminalDecimatorJackpot | 0x4a18a7de |
| subscribe | 0x51224ba5 | claimAffiliateDgnrs | 0x92060938 |
| mintBurnie | 0xfe617549 | resolveRedemptionLootbox | 0xcf78fe26 |
| claimAfkingBurnie | 0xa95b5052 | creditRedemptionDirect | 0x83cbf60c |
| drainAffiliateBase | 0xe8c83c90 | previewSellFarFutureTickets | 0x78857860 |
| decurse | 0xc0d7e31c | updateVrfCoordinatorAndSub | 0x049d4020 |
| smite | 0x8a70a1cc | requestLootboxRng | 0xb9073281 |
| recordAfkingSecondary | 0xbdfaeaf3 | retryLootboxRng | 0x342535bb |
| consumeCoinflipBoon | 0x9a0e1436 | rawFulfillRandomWords | 0x1fe543e3 |
| recordDecBurn | 0xbd225b88 | runDecimatorJackpot | 0x275d3a40 |
| recordTerminalDecBurn | 0x397c1a5d | runBafJackpot | 0x4181af8e |
| boostTerminalDecimator | 0x04ed6823 | runTerminalDecimatorJackpot | 0x59207bfc |
| runTerminalJackpot | 0xa56efd97 | emitDailyWinningTraits | 0x1fe49a5a |

Access gates that live in the wrapper (e.g. `consumeCoinflipBoon` COIN/COINFLIP check,
`runTerminalJackpot`/`run*Jackpot` self-call `msg.sender != address(this)`) are PRESERVED
in the wrapper bodies before the delegate; gates that live in the module body
(`rawFulfillRandomWords` coordinator-only) were ALREADY module-side in baseline — no access
check was relocated or dropped. The non-canonical-array-offset edge for the two
dynamic-array wrappers (`previewSellFarFutureTickets`, `claimAfkingBurnie`,
`rawFulfillRandomWords`) is moot: the module shares the same ABI decoder, decoding the same
typed values the wrapper already validated.

Also folded out in this refactor (genuine code REMOVAL, intended): `recordMint` /
`recordMintQuestStreak` / `_processMintPayment` / `_recordMintDataModule` /
`consumePurchaseBoost` moved into modules (the mint-payment path is now module-resident).
These are dead-entrypoint removals, not identity refactors — flagged for the change-class
inventory, but the payment math itself was relocated, not altered (separate dimension).

## 5. EntropyLib `hash1` / `hash2` keccak-preimage migrations — VERIFIED IDENTICAL

`contracts/libraries/EntropyLib.sol` gains `hash1(a) = keccak(mstore 32-byte a)`.

The migration rule that MUST hold: `keccak256(abi.encode(...))` and
`keccak256(abi.encodePacked(...))` both equal the `hash1`/`hash2` scratch layout **only when
every operand is a full 32-byte type** (uint256 / bytes32). A sub-word operand under
`abi.encodePacked` would tightly-pack to fewer bytes and diverge. I checked every migrated
site's operand types:

- `hash1(rngWord)` (LootboxModule:955, redemption chunk re-seed) replaced
  `uint256(keccak256(abi.encode(rngWord)))`. `abi.encode(uint256)` = the 32-byte word =
  `hash1` preimage. IDENTICAL.
- `hash2(entropy, salt)` (DegenerusJackpots:298/317/374) replaced `encodePacked(entropy,
  salt)` — both are `uint256` (salt declared `uint256` at line 243). IDENTICAL.
- `hash2(rngWord, FUTURE_KEEP_TAG)` (AdvanceModule:969) — uint256 + bytes32, both 32B.
  IDENTICAL.
- `hash2(combined, w)` (AdvanceModule:1400) — both uint256. IDENTICAL.
- `hash2(randWord, BONUS_TRAITS_TAG)` (JackpotModule:1572/1765/1791) — uint256 + bytes32,
  both 32B. IDENTICAL.
- `hash2(rngWord, uint256(uint160(player)))` (LootboxModule:883/1227-area) replaced
  `keccak256(abi.encode(rngWord, player))`. `abi.encode(address)` zero-pads the high 12
  bytes; `uint256(uint160(player))` also has zero high 12 bytes — same 64-byte preimage.
  IDENTICAL.
- All remaining `hash2(randWord, lvl)` / `hash2(seed, TAG)` sites replaced
  `keccak256(abi.encode(...))` (non-packed) — `abi.encode` always pads each arg to 32B, so
  identical regardless of arg width.

I confirmed the keccak preimage equalities numerically. The team also correctly DID NOT
migrate the 3-arg `keccak256(abi.encode(randWord, lvl, COIN_JACKPOT_TAG))` (JackpotModule
:1806) — it stays as-is since `hash2` is 2-arg. Stage B's commit notes a "hash2 1-liner
dropped as not byte-identical" — this was a PLANNED migration that was correctly NOT
applied (not a revert of shipped code); no stray non-identical hash2 exists in HEAD.

## 6. JackpotModule trait-roll consolidation — VERIFIED IDENTICAL (non-trivial)

The largest identity-claim refactor. Baseline called `_rollWinningTraits(randWord, false)`
(main) and `_rollWinningTraits(randWord, true)` (bonus); HEAD consolidates into
`_rollWinningTraitsPair(randWord)` that rolls the hero ONCE and applies it to both.

Verified equivalent by reading both:
- Baseline `_rollWinningTraits(w, isBonus)` computed `r = isBonus ?
  keccak(encodePacked(w, BONUS_TRAITS_TAG)) : w`, then `_applyHeroOverride(traits, r, w)`.
  Crucially `_applyHeroOverride`'s 3rd arg (`heroEntropy`) is `w` in BOTH calls, so
  `_rollHeroSymbol(dailyIdx, w)` produced the SAME hero for main and bonus; only the
  per-quadrant `heroColor` was derived from `r`.
- HEAD computes `_rollHeroSymbol(dailyIdx, randWord)` once, then `_applyHeroResult(traits,
  randWord, hero...)` for main and `_applyHeroResult(traits, rBonus, hero...)` for bonus.
  `_applyHeroResult` derives `heroColor` from its 2nd arg with the identical quadrant
  switch. `rBonus = hash2(randWord, BONUS_TRAITS_TAG)` == the baseline bonus `r`.
- `_rollHeroSymbol` body is byte-identical baseline↔HEAD (still
  `keccak256(abi.encode(entropy, day))`). The two storage reads of `dailyIdx` /
  `dailyHeroWagers` collapse to one, but no write intervenes intra-tx so values match.

`_soloAdjustedEntropy(traitIds, entropy)` exactly reproduces the inlined `(entropy &
~uint256(3)) | uint256((3 - _pickSoloQuadrant(traitIds, entropy)) & 3)`. IDENTICAL.

## 7. MintModule `_farFutureSeed` extraction — VERIFIED IDENTICAL

`_farFutureSeed(player)` (MintStreakUtils:232) returns
`keccak256(abi.encodePacked(player, rngWordByDay[_simulatedDayIndex() - 1]))`. Baseline
inlined this exact expression at TWO sites (MintStreakUtils:162, 212 in baseline). Literal
extraction; one computation per call vs two, same value intra-tx. IDENTICAL.

## 8. Stage B storage packing — VERIFIED VALUE-IDENTICAL (with 1 declared narrowing)

`contracts/storage/DegenerusGameStorage.sol` + module RMW sites:

- **`bingoFirsts`** (BingoModule): `firstQuadrant`(uint8)+`firstSymbol`(uint32) → uint64,
  quadrant in bits[32:36), symbol in [0:32). Read/write decompositions checked; the
  symbol-first branch `(bf & ~uint64(0xFFFFFFFF)) | uint64(fs|sMask)` correctly preserves
  the co-resident quadrant mask. IDENTICAL to the old two-mapping writes.
- **`deityBoonPacked`** (LootboxModule:1145-1153, Game:883): `deityBoonDay`(uint24)+
  `deityBoonUsedMask`(uint8) → uint32, day[0:24)/mask[24:32). The day-match gate
  `uint24(packed)==day ? mask : 0` reproduces the baseline `deityBoonDay==day` gate; the
  single packed write replaces the baseline "reset day+mask, then OR slot" sequence with
  the same net stored value. No width truncation (24+8 fit). IDENTICAL.
- **`levelDgnrsPacked`**: allocation[0:128)/claimed[128:256) with accessors. Get/set
  arithmetic correct. Relies on `claimed <= allocation <= 2^128` (no explicit clamp on
  `_addLevelDgnrsClaimed`'s `newClaimed << 128`) — defensible (sDGNRS supply ~1e30 ≪ 2^128,
  claims monotone toward allocation) but see Focus Area F-3.
- **`lootboxEvCapPacked`**: nested mapping `[player][level]→used` → single two-window slot
  (A: used[0:64)/lvl[64:88); B: used[88:152)/lvl[152:176)). Masks/shifts verified. Eviction
  evicts the smaller-level window when neither matches. See Focus Area F-2 (level-0 stamp
  collision — baseline nested map returned 0 for unwritten [player][0]; packed returns
  window A's `used` whenever its stamp is its initial 0). Live keys are always
  `currentLevel`/`currentLevel+1` = gameLevel+1 ≥ 1, so level 0 is unreachable in practice,
  but the divergence exists by construction.
- **`totalFlipReversals`(uint64)+`lastVrfProcessedTimestamp`(uint48) share slot 5** —
  masked RMW; the reverseFlip RNG-lock gate and VRF freeze are untouched.
- **`DecClaimRound.rngWord` narrowed uint256→uint32** — see Focus Area F-1. This is the one
  genuinely-non-byte-identical RNG change; openly declared. Winners are selected from the
  FULL VRF word at snapshot (stored in `decBucketOffsetPacked`); only the claim-time
  lootbox re-seed keeps 32 bits, fed through `hash2(rngWord, uint160(player))`.

## 9. StakedDegenerusStonk solvency-scalar packing (2e41c618) — narrowings, not identity

`totalSupply` uint256→uint128, `pendingRedemptionEthValue` uint256→uint96,
`poolBalances` uint256[5]→uint128[5]; `public` vars → `private` + same-name external
getters (ERC-20 `totalSupply()` still returns uint256). Arithmetic unchanged; casts narrow
post-add (no intermediate-overflow). All bounded by INITIAL_SUPPLY (1e30) ≪ uint128 and
total-ETH-supply ≪ uint96. NOT an RNG path. Recorded for the solvency sweep (F-4); the
gas-identity dimension finds nothing wrong here.

---

## Candidate focus areas for the later adversarial sweep

- **F-1 (INFO/LOW)** `DecClaimRound.rngWord` uint32 narrowing —
  DegenerusGameStorage.sol:1772 + DecimatorModule:277/410. 32 bits of post-fulfillment
  entropy seed the claim-time lootbox draw via `hash2(rngWord, uint160(player))`. Player
  and rngWord are both frozen at snapshot, the claim is deterministic and permissionless,
  so a winner cannot grind/retry the outcome — predictability without control. Defensible
  by-design but worth a grinding/retry-timing check.
- **F-2 (LOW)** `lootboxEvCapPacked` level-0 stamp collision —
  DegenerusGameStorage.sol:1698-1707. A window whose level stamp is its initial 0 will be
  read as level-0 `used`, diverging from the baseline nested map (which returned 0 for
  unwritten [player][0]). Reachable only if `level==0` is ever passed (callers pass
  gameLevel+1 ≥ 1, or a uint24 `level+1` wrap). Verify no caller path reaches level 0.
- **F-3 (LOW)** `_addLevelDgnrsClaimed` unclamped high-half — DegenerusGameStorage.sol:1160.
  `newClaimed << 128` has no uint128 clamp; relies on the caller invariant `claimed <=
  allocation <= 2^128`. Confirm every claim path enforces `claimed + add <= allocation`.
- **F-4 (LOW/INFO)** StakedStonk `pendingRedemptionEthValue` uint96 + `totalSupply` uint128
  narrowings — StakedDegenerusStonk.sol. Solvency accounting; bounds make overflow
  unreachable but worth a solvency-sweep confirmation that no path can exceed 2^96 wei
  segregated.
- **F-5 (INFO)** Dynamic-array `msg.data` wrappers (`previewSellFarFutureTickets`,
  `claimAfkingBurnie`, `rawFulfillRandomWords`) — DegenerusGame.sol. Forwarding raw
  calldata with non-canonical ABI offsets; benign because the module shares the wrapper's
  decoder and the wrapper validates on entry, but a fuzz of malformed/oversized calldata
  against these three confirms no decoder-divergence corner.
