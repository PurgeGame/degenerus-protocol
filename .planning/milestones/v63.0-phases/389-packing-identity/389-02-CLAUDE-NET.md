# 389-02 — NET 2 (Claude adversarial net) — PACKING-IDENTITY (STORAGE + GASID)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after this pass).
**Net:** NET 2 = the deep Claude adversarial net, run INDEPENDENTLY of NET 1 (the council). The
attack attempts and slot verifications below were derived by reading the frozen source directly
(`git show a8b702a7:contracts/<File>.sol`) and re-running `forge inspect <C> storageLayout --json`
against the subject tree — NOT by starting from the council outputs. The council leads are folded in
at the end of this document (§ "Council fold").
**Method:** for each of the 12 reqs (STORAGE-01..07, GASID-01..05) and 9 leads (FC-389-01..09) I
attempted to BREAK the identity/safety claim with a concrete reachable call sequence, then recorded
PROPERTY · attack tried · state var + file:line at `a8b702a7` · the bound/cite that settles it · a
provisional verdict. Authoritative slots come from `forge inspect` at the subject (captured fresh this
pass; `forge clean` was required to force storageLayout emission). Neutral defensive-engineering terms
throughout. No contract source was modified — read-only over the frozen subject.

**Authoritative slot capture (this pass, `forge inspect DegenerusGame storageLayout --json`):**

```
slot   9 off  0  mintPacked_
slot  10 off  0  rngWordByDay
slot  26 off  0  levelDgnrsPacked
slot  34 off  0  lootboxRngPacked
slot  35 off  0  lootboxRngWordByIndex
slot  36 off  0  deityBoonPacked
slot  40 off  0  lootboxEvCapPacked
slot  43 off  0  decClaimRounds            (DecClaimRound: poolWei@0 / totalBurn@12 / rngWord@28)
slot  53 off  0  bingoFirsts
slot  58 off  0  _subCursor   off 2 _subOpenCursor   off 4 _afkingResetDay
slot  58 off  7  boxCursor    off 13 boxCursorIndex   off 19 presaleCloseIndex
slot  59 off  0  boxPlayers
```

These match the 388-01 LAYOUT-KEY §1 verbatim and are the truth I check every harness/slot claim
against below. The one new datum 388-01 did not enumerate is `boxCursor`/`boxCursorIndex`/`boxPlayers`
(slot 58 off 7/13 + slot 59) — directly relevant to a council STORAGE-06 candidate.

---

## STORAGE adjudication (STORAGE-01..07 + FC-389-01..04)

### STORAGE-01 — narrowing casts cannot truncate a legitimate value

PROPERTY: every narrowing cast in the changed packs is bounded below the target width by a
real-world maximum.
ATTACK: enumerate each narrowing cast and try to find a reachable path that inflates the value past
the width so the silent `uintN(...)` truncation drops high bits.

| narrowed field | width | real-world bound | settling cite (`a8b702a7`) |
|---|---|---|---|
| `DecClaimRound.poolWei` | uint96 | real ETH (~1.2e26 wei) ≪ 7.9e28 | DegenerusGameStorage.sol:1760; written `uint96(poolWei)` Decimator:275 |
| `DecClaimRound.totalBurn` | uint128 | effective burn < ~2.35× BURNIE supply ≤ uint128 | DegenerusGameStorage.sol:1764; written `uint128(totalBurn)` Decimator:276 |
| `DecClaimRound.rngWord` | uint32 | seed-only (no magnitude meaning) | DegenerusGameStorage.sol:1772 |
| sDGNRS `_totalSupply` | uint128 | INITIAL_SUPPLY 1e30 ≪ 3.4e38, monotone non-increasing | StakedDegenerusStonk.sol:213 |
| sDGNRS `_pendingRedemptionEthValue` | uint96 | segregated ETH ≪ real ETH supply ≪ 7.9e28 | StakedDegenerusStonk.sol (slot-0 off 16) |
| sDGNRS `poolBalances[5]` | uint128 | sum conserved = INITIAL_SUPPLY ≪ uint128 | StakedDegenerusStonk.sol slot 2 |
| `levelDgnrsPacked` alloc/claimed | uint128 each | DGNRS base units ≤ sDGNRS supply ~1e30 ≪ 3.4e38 | DegenerusGameStorage.sol:1132-1137 |
| `bingoFirsts` symbol/quad | uint32 / 4-bit | 32 symbols / quadrant 0-3 | DegenerusGameStorage.sol:53 |
| `deityBoonPacked` day/mask | uint24 / uint8 | day index uint24 / `slot < 3 → 1<<slot ≤ 4` | DegenerusGameStorage.sol:36 |
| EV-cap `used` | uint64 each window | clamped to LOOTBOX_EV_BENEFIT_CAP = 10 ether = 1e19 ≪ 2^64 | DegenerusGameStorage.sol:1686 |

No reachable path inflates any of these past its width — the truncation never fires on a legitimate
value. The sDGNRS narrowings are the only ones where the *cast itself* does not revert on >width (it
silently truncates); safety rests on the economic bound (the lead FC-389-02/-08 — folded below).
**Provisional verdict: REFUTED (no truncation defect).**

### STORAGE-02 — masked read-modify-write preserves co-resident fields

PROPERTY: each `_set`/`_add` helper preserves the sibling lane in the same slot.
ATTACK: round-trip each consolidated pack — set lane X, read lane Y, check Y unchanged; look for a
mask that clears too many / too few bits.

- **EV-cap `_setLootboxEvUsedFor`** (DegenerusGameStorage.sol:1709-1738): replacing window B uses
  `(packed & ~_EV_WINDOW_B_MASK) | (windowA << 88)` where `_EV_WINDOW_B_MASK = ((1<<88)-1)<<88`
  clears exactly bits [88:176) and leaves window A [0:88) intact; replacing window A uses
  `~_EV_WINDOW_A_MASK` = clears [0:88). Round-trips cleanly. (Eviction correctness is STORAGE-04.)
- **`levelDgnrsPacked`** (`_setLevelDgnrsAllocation` :1148, `_addLevelDgnrsClaimed` :1158): allocation
  set uses `(w & (type(uint128).max << 128)) | uint128(allocation)` — preserves claimed half; claimed
  add uses `uint128(w) | (newClaimed << 128)` — preserves allocation half. (Unclamped high-half is
  FC-389-07.)
- **`deityBoonPacked`** day/mask, **`bingoFirsts`** symbol/quad: single-module masked writes; the
  storage-map §SOUND-3/-4 traced both decompositions; quadrant `1<<q` with q∈0-3 ≤ 0xF cannot bleed
  past bit 35 / the symbol mask is uint32. Co-residents preserved.
- **slot-5 `totalFlipReversals`(uint64)+`lastVrfProcessedTimestamp`(uint48)**: separate FIELD
  assignments (compiler-managed masked RMW), not manual packing — the green `RngLockDeterminism` /
  `VRFStallEdgeCases` harnesses mask to low uint64 and the co-resident timestamp survives.
- **`_debitClaimableAndAfking`** (balancesPacked low=claimable/high=afking): guards EACH half before
  the combined subtraction (low-half borrow + oversized-afking both closed) — the green-baseline
  `RedemptionStethFallback` / `RedemptionAccounting` poke `balancesPacked@7` and pass.

No mask clears a live sibling. **Provisional verdict: REFUTED (no RMW defect).**

### STORAGE-03 — cross-module shift/mask conventions agree

PROPERTY: every module that reads/writes a shared pack uses the identical decode.
ATTACK: find two modules that disagree on a slot's bit layout (a write-with-convention-X read-with-
convention-Y aliasing).
- All 13 Game modules + Game inherit the ONE `DegenerusGameStorage` base (verified: every module
  `is DegenerusGameStorage`), so slots agree by construction — a cross-module slot DISagreement is
  not structurally reachable. The residual risk is two READERS of a pack using different shifts.
- The two genuinely cross-module-read packs: `deityBoonPacked` (read at Game.sol:884 + Lootbox:1146)
  both use `uint24(packed)` day / `uint8(packed>>24)` mask; `levelDgnrsPacked` (written by Bingo/
  Whale/Advance via the SAME `_setLevelDgnrsAllocation`/`_addLevelDgnrsClaimed`/`_getLevelDgnrs`
  helpers — no inline duplicate). The EV-cap windows are read/written only through `_lootboxEvUsedFor`/
  `_setLootboxEvUsedFor`, so the [0:64)/[88:152) used + [64:88)/[152:176) level decode is single-
  sourced.
**Provisional verdict: REFUTED (conventions agree by construction + single-sourced helpers).**

### STORAGE-04 / FC-389-01 — two-window `lootboxEvCapPacked` eviction under resolve-cursor lag (PRIME TARGET — rigorous treatment)

PROPERTY: the live EV-cap key set for any player is always a subset of `{currentLevel,
currentLevel+1}`, so the two windows hold the full live set and eviction (which discards the
smaller-level window when neither matches) NEVER zeroes a live window. If a THIRD distinct live level
key were reachable at a write, eviction would silently zero a live window → the 10 ETH per-level EV
benefit cap could be re-earned for that level.

ATTACK (the cursor-lag thesis): find a path where `_setLootboxEvUsedFor(player, K, …)` runs with a
level key `K ∉ {liveLevel, liveLevel+1}` while the player simultaneously holds two windows stamped at
the live pair — e.g. a deferred/queued resolve, a far-future ticket path, or a redemption-lootbox
path that carries a STALE stored level into the cap write after the live `level` advanced ≥2.

Trace of EVERY EV-cap write key and the level it reads:

| site | key passed to `_setLootboxEvUsedFor` / `_applyEvMultiplierWithCap` | level provenance | cite |
|---|---|---|---|
| Mint deposit | `cachedLevel + 1` | `cachedLevel` = live `level` cached this tx | DegenerusGameMintModule.sol:1685/1706 |
| Whale deposit | `capKey = level + 1` | live storage `level` | DegenerusGameWhaleModule.sol:852 |
| Afking cover-box deposit | `capKey = currentLevel + 1` where `currentLevel = level` | live storage `level` | GameAfkingModule.sol:970 |
| `resolveLootboxDirect` | `currentLevel = level + 1` | live storage `level` | DegenerusGameLootboxModule.sol:877 |
| `resolveAfkingBox` | `currentLevel = level + 1` | live storage `level` | DegenerusGameLootboxModule.sol:966 |
| `_resolveRedemptionChunk` | `currentLevel = level + 1` | live storage `level` | DegenerusGameLootboxModule.sol:1089 |
| deferred human `openBoxes` leg | **NO EV-cap SSTORE** — "the cap was drawn at deposit" | n/a | DegenerusGameLootboxModule.sol:567-579 |

Two load-bearing facts that close the cursor-lag thesis:

1. **The deferred/queued human open (`openBoxes`) does NOT write the EV cap.** The deferred leg reads
   the frozen `adj` from the packed `lootboxEth` word and applies it WITHOUT a cap SLOAD/SSTORE
   (DegenerusGameLootboxModule.sol:567-579: "No cap SLOAD/SSTORE here — the cap was drawn at deposit").
   So the ONLY thing a deferred open could "lag" — a stale stored purchase-level used as a cap key —
   does not exist: deferred opens never key the cap. Every cap write is a DEPOSIT (keyed live
   `level+1`) or a DIRECT/auto resolve (keyed live `level+1`). There is no path that carries a
   purchase-time stored level into a cap write.

2. **`level` is monotone-increasing by exactly +1 per ticket-jackpot-day advance.** The sole writer is
   `advanceGame`: `level = lvl` where `lvl = level + 1`, gated `isTicketJackpotDay && !isDailyRetry`
   (DegenerusGameAdvanceModule.sol:1701-1709). `level` never decrements and never jumps by >1 within a
   single advance. Therefore between any two cap writes for the same player, the live `level` can only
   have advanced by some k ≥ 0, and the live key window at write time is exactly `{level, level+1}`.

Composing (1)+(2): every cap write keys `level+1` against the THEN-LIVE `level`. Two consecutive
writes for the same player key `level_t + 1` and `level_{t'} + 1` with `level_{t'} ≥ level_t`. The
two-window store can hold at most two distinct keys; a write of a NEW (higher) key evicts the
SMALLER-level window (`lvlA <= lvlB` branch at :1727). The evicted key is strictly the smallest held
— and since deposits key `level+1` and resolves key `level+1` against a monotone `level`, the smallest
held key is always ≤ the older of the live pair, i.e. NEVER a key that a future write at the current
live level still needs. A third *simultaneously-live* key is unreachable because there is no write
that uses a key disconnected from the current live `level` (no stored-purchase-level cap write
exists, fact 1). The worst case — `level` advances by 2+ between two of a player's writes — evicts a
window stamped at a level that is now strictly below `{liveLevel, liveLevel+1}`, i.e. a genuinely dead
key. That is correct eviction, not a live-window loss.

Adversarial corner I specifically checked: could a player accumulate a window at level L, let the
game advance to L+5, then trigger a `resolveLootboxDirect`/`_resolveRedemptionChunk` that writes at
L+6 (live+1) while a DIFFERENT in-flight path writes at some intermediate level? No — there is no
write path that keys an intermediate (non-live) level; redemption/decimator resolves all read the
LIVE `level` (cite table above, "live storage level"), NOT a stored snapshot level. The activity
SCORE and the rngWord are frozen at submission, but the CAP KEY (`currentLevel = level + 1`) is a live
read at resolve. So the resolve always keys the live pair; it can never re-open an old level's cap.

**Provisional verdict: REFUTED.** The live key set is provably `⊆ {currentLevel, currentLevel+1}` at
every write because (a) deferred opens never write the cap, (b) every cap write keys `live level + 1`,
(c) `level` is +1-monotone. No third live key is reachable; eviction only ever discards a dead key.
The 10 ETH per-level cap cannot be re-earned via cursor lag. Settling cites:
DegenerusGameLootboxModule.sol:567-579 (deferred open, no cap write) + :877/:966/:1089 (resolves key
live `level+1`) + DegenerusGameMintModule.sol:1685/1706 / WhaleModule:852 / GameAfkingModule:970
(deposits key live `level+1`) + DegenerusGameAdvanceModule.sol:1701-1709 (`level` +1-monotone) +
DegenerusGameStorage.sol:1709-1738 (eviction discards the smaller/older key).

### STORAGE-05 — ABI getters preserved

PROPERTY: every privatized/packed field keeps a same-name external view getter (no interface break).
ATTACK: find a packed/privatized field whose external getter was dropped or changed signature.
- sDGNRS: `totalSupply()` returns uint256 (ERC-20 intact) StakedDegenerusStonk.sol:513;
  `pendingRedemptionEthValue()` :518; `pendingResolveDay()` :524; `poolBalance()` :509.
- DegenerusAdmin: `votes()`/`voteWeight()`/`feedVotes()`/`feedVoteWeight()` re-exposed as explicit
  view functions over the folded `voterRecords`/`feedVoterRecords` (storage-map §SOUND-13).
No external view getter was dropped. **Provisional verdict: REFUTED (ABI preserved).**

### STORAGE-06 / FC-389-04 — no harness hardcodes a moved slot (the 3 council candidates verified vs `forge inspect`)

PROPERTY: every slot-hardcoded `vm.store`/`vm.load`/`setStorageAt` poke targets the LIVE field; a
stale slot is an oracle-integrity risk (a packing bug could hide behind a harness writing the wrong
slot while the test stays green).
ATTACK: take each of the 3 council-named candidates (outside the 388-01 §6 reconciled poke set) and
check its hardcoded constant against the fresh `forge inspect` truth.

| candidate | harness constant | authoritative slot | verdict |
|---|---|---|---|
| **(1) Composition `mintPacked_`** | `MINT_PACKED_SLOT = 10`, reads `keccak256(player,10)` (CompositionHandler.sol:37, :210) | `mintPacked_` is **slot 9**; slot 10 is `rngWordByDay` | **CONFIRMED stale** — the gap-bit check reads `rngWordByDay`'s mapping space (`keccak(player,10)`), never the real `mintPacked_` gap bits → vacuous canary. LOW / oracle-integrity. |
| **(2) box-cursor 58/59** (`SweepWorstCaseDrain` SLOT_BOX_CURSORS=58 boxCursor@byte7/boxCursorIndex@byte13, SLOT_BOX_PLAYERS=59; `RngLockDeterminism` SLOT_BOX_CURSORS=58) | 58 (off 7/13) + 59 | `boxCursor` **slot 58 off 7**, `boxCursorIndex` **slot 58 off 13**, `boxPlayers` **slot 59** | **REFUTED** — the harnesses are CORRECT. The codex premise ("boxCursor/boxPlayers moved to 59/60") is contradicted by `forge inspect`: the box cursors live in slot 58's free bytes above the subscriber cursors, and `boxPlayers` is slot 59. No stale poke. |
| **(3) HeroOverride*.test.js `lootboxRngPacked`** | `LOOTBOX_RNG_PACKED_SLOT = 35`, seeds the low-48 `lootboxRngIndex` via `setStorageAt(game, 35)` (HeroOverrideDayIndex.test.js:62/82-94; HeroOverrideWeightedRoll.test.js:202-205) | `lootboxRngPacked` is **slot 34**; slot 35 is `lootboxRngWordByIndex`'s mapping root | **CONFIRMED stale** — `seedLootboxRngIndex` writes slot 35 (the `lootboxRngWordByIndex` root) instead of slot 34, so the intended `lootboxRngIndex` seeding silently no-ops; the bet-gate-open the test relies on (`:451 if index==0 revert`) is not actually satisfied by the write. LOW / oracle-integrity (JS edge tests = corroborating, in the documented Hardhat carried-drift family; forge primary oracle unaffected). The in-test comment ("slot index 35 … resolved via the hardhat storage-layout artifact") is also stale. |

Plus the already-known legacy `RedemptionInvariants.inv.t.sol` hole (388-02 ORACLE-HOLES #2; stale
slots 10/13/15, un-wired, superseded by `RedemptionStethFallback`+`RedemptionAccounting`, routed 390).
The 388-01 §6 reconciliation ledger (every poke for the 4 reshuffled contracts) is independently
confirmed correct against this pass's `forge inspect`.
**Provisional verdict: CONFIRMED (2 of 3 candidates are real stale-slot harnesses) — but oracle-
integrity (LOW), not a contract defect. The forge GREEN primary baseline is unaffected; these are
JS/handler harnesses whose state-seeding silently no-ops or reads the wrong field.**

### STORAGE-07 — `capBucketCounts` <= maxTotal+4 exactness (folded debt; concrete equivalence)

PROPERTY: `capBucketCounts` cannot over-distribute past the intended winner cap, and any residual
imprecision is fully absorbed by documented downstream clamps.
ATTACK: derive whether the summed `capped[]` can exceed `maxTotal`, then check whether a consumer
ever trusts `capBucketCounts` as an EXACT cap (vs clamping again).

Concrete derivation over the bounded domain (`JackpotBucketLib.sol:140-204`):
- The solo bucket contributes exactly 1 (`soloBucketIndex`); the non-solo budget is
  `nonSoloCap = maxTotal - 1`.
- Each non-solo bucket with `count>1` gets `scaled = floor(count * nonSoloCap / nonSoloTotal)`, then
  bumped to 1 if it floored to 0. The proportional sum `Σ floor(...) ≤ nonSoloCap` by construction;
  the only inflation is the `if (scaled==0) scaled=1` bumps, ≤ 3 of them (at most 3 non-solo buckets).
- If `scaledTotal > nonSoloCap`, the TRIM loop (`:166-183`) zeroes count-1 buckets one at a time
  until `excess==0`. Each bump-to-1 created at most +1 excess and is itself a `capped[idx]==1 &&
  counts[idx]>1` candidate the trim can zero, so the trim can always clear the entire bump-excess.
  After trim, `Σ capped ≤ nonSoloCap` exactly.
- If `scaledTotal < nonSoloCap`, the remainder loop (`:186-202`) adds back to buckets with
  `capped>1`, capped by `remainder`, so it never overshoots `nonSoloCap`.
- Hence total capped (solo + non-solo) `≤ maxTotal`. The "+4" slack referenced in memory is a
  TEST-side slack constant (`204a91bb`), NOT a contract property — the contract `capBucketCounts` is
  byte-identical to baseline (gas-identity §2) and bounds to `≤ maxTotal`.

Downstream defense (so even residual count-1 slack is harmless): the production consumers are the ETH
jackpot paths (DegenerusGameJackpotModule.sol:248-267, :417-440); `_processBucket` clamps each bucket
to `MAX_BUCKET_WINNERS = 250` before the `uint8` cast (:1141-1152), and `bucketShares` assigns the
remainder bucket `pool - distributed` (JackpotBucketLib.sol:214-240) — so over-count cannot
over-distribute ETH. The ticket paths do NOT consume `capBucketCounts`; they split exact `maxWinners`
in `_computeBucketCounts` (:796-804, :969-985).
**Provisional verdict: REFUTED as an overflow/over-distribution risk; the cap bounds to ≤ maxTotal by
the trim/remainder construction and is double-defended by the 250-clamp + remainder-share. (No "+4"
contract imprecision — that is a test-slack constant.)**

### FC-389-02 / FC-389-08 — sDGNRS uint96/uint128 narrowings (silent truncation; cross-ref 390)

PROPERTY: no path inflates segregated ETH / a pool beyond the narrowed width (truncation would
UNDERSTATE segregated ETH → solvency-accounting drift).
ATTACK: find a double-credit / unbounded accumulation that grows `_pendingRedemptionEthValue` or a
`poolBalances` lane past uint96/uint128.
- `_pendingRedemptionEthValue` increments ONLY after `pullRedemptionReserve()` succeeds
  (StakedDegenerusStonk.sol:1061-1066; game side DegenerusGame.sol:1572-1599) — each increment is
  backed by value actually segregated, capped per wallet/day (160 ETH base × 175% max), with a single
  unresolved-day sentinel; the sum is bounded by real ETH ≪ uint96.
- `poolBalances[5]` lanes are debited/clamped before transfer (:548-570) and conserved on pool-to-pool
  moves (:579-592); the sum equals the constructor total ≤ INITIAL_SUPPLY ≪ uint128.
The narrowings are reachable-overflow-free. The FULL solvency-conservation lens (whether an
adversarial multi-tx sequence strands ETH) is FC-390-01/-02/-03 / FC-393-03 in the 390/393 SOLVENCY
sweep — cross-ref recorded.
**Provisional verdict: REFUTED for the narrowing-equivalence half (no truncation reachable); solvency-
conservation half cross-ref 390.**

### FC-389-03 — `DecClaimRound.totalBurn` raw-vs-effective comment framing

PROPERTY: pin whether the decimator burn accumulator stores RAW or EFFECTIVE burns, and which comment
(if any) is imprecise.
ATTACK / direct trace (`DegenerusGameDecimatorModule.sol:178-200`, :252-276): `_recordDecimatorBurn`
computes `effectiveAmount = _decEffectiveAmount(prevBurn, baseAmount, multBps)`, sets
`e.burn = prevBurn + effectiveAmount`, and adds `delta = newBurn - prevBurn = effectiveAmount` to the
subbucket via `_decUpdateSubbucket` → `decBucketBurnTotal`. The round snapshot sums the winning
subbuckets into `totalBurn` (:262-266) → `round.totalBurn = uint128(totalBurn)`. So the accumulator
stores **EFFECTIVE** amounts, NOT raw. This CONTRADICTS the storage-map FA-3 framing ("accumulator
stores RAW burns, `delta = e.burn`") — the map is wrong on raw-vs-effective. The `DecClaimRound.
totalBurn` comment ("Sum of per-burn effective amounts") is therefore **CORRECT**. The imprecise
comment is on **`DecEntry.burn`** ("Total BURNIE burned this level" at DegenerusGameStorage.sol:1748)
— it actually stores the EFFECTIVE burn (raw × multBps), not the raw token burn. Either framing keeps
the uint128 bound sound (effective < ~2.35× supply ≤ uint128).
**Provisional verdict: BY-DESIGN bound sound + INFO comment-accuracy item on `DecEntry.burn`
(not `DecClaimRound.totalBurn`, whose comment is correct). The storage-map FA-3 raw-vs-effective
framing is itself the imprecision and should not be re-derived as an overflow risk.**

---

## GASID adjudication (GASID-01..05 + FC-389-05..09)

### GASID-01 / FC-389-09 — `delegatecall(msg.data)` selector + ABI identity

PROPERTY: each thin wrapper's selector == its module function's selector, and the typed wrapper keeps
the same Solidity ABI decoder so short/dirty/malformed calldata reverts identically.
ATTACK: find a wrapper whose signature (hence selector) diverges from the module, or a dynamic-array
wrapper whose decoder corner differs from the module's.
- The 30 wrappers keep typed (unnamed) parameters, so the Solidity-generated external ABI decoder
  validates calldata on ENTRY (short calldata, dirty high bits on narrow types, malformed array
  offsets all revert at the wrapper before forwarding) — identical revert surface to the re-encode
  path. The forwarded `msg.data` carries the wrapper's own selector, which the module routes on.
- Selector identity: the gas-identity map computed all 30 wrapper selectors == module selectors
  (independently recomputed via keccak); spot-confirmed against the council's recomputed 30-row table
  (e.g. `advanceGame 0x75b5e924`, `claimBingo 0x039349d9`, `rawFulfillRandomWords 0x1fe543e3`). All 30
  match.
- The 3 dynamic-array wrappers (`previewSellFarFutureTickets`, `claimAfkingBurnie`,
  `rawFulfillRandomWords`): the module shares the wrapper's typed signature, so the same ABI schema
  decodes the same payload — no alternate interpretation of a non-canonical offset (the wrapper's
  entry decode already validated bounds; the module re-decodes the SAME typed values).
- Wrapper-resident gates (`consumeCoinflipBoon` COIN/COINFLIP check, `run*Jackpot` self-call
  `msg.sender != address(this)`) are PRESERVED before the delegate; module-resident gates
  (`rawFulfillRandomWords` coordinator-only) were already module-side at baseline — none relocated.
**Provisional verdict: REFUTED (selector + ABI identity holds; no decoder divergence).**

### GASID-02 — `hash1`/`hash2` keccak-preimage identity (concrete)

PROPERTY: `EntropyLib.hash1/hash2` scratch-space layout == the `abi.encode`/`abi.encodePacked`
preimage ONLY when every operand is a full 32-byte type (a sub-word operand under `encodePacked`
would tightly-pack and diverge).
ATTACK: find a migrated site with a sub-word operand under what was `encodePacked`.
- Applied the operand-width rule to each migrated site (gas-identity §5): `hash1(rngWord)` (uint256),
  `hash2(entropy, salt)` (both uint256), `hash2(rngWord, FUTURE_KEEP_TAG)` (uint256+bytes32),
  `hash2(combined, w)` (both uint256), `hash2(randWord, BONUS_TRAITS_TAG)` (uint256+bytes32),
  `hash2(rngWord, uint256(uint160(player)))` (uint256+uint256) — EVERY operand is a full 32-byte type.
- The load-bearing address case: `hash2(rngWord, uint256(uint160(player)))` vs the prior
  `keccak256(abi.encode(rngWord, player))`. `abi.encode(address)` zero-pads the high 12 bytes;
  `uint256(uint160(player))` also has zero high 12 bytes → identical 64-byte preimage. Numerically
  re-confirmed: for the same `rngWord` and `player`, both preimages are the byte string
  `rngWord(32) || 0x00…00 || addr(20)` = identical. The team correctly did NOT migrate the 3-arg
  `keccak256(abi.encode(randWord, lvl, COIN_JACKPOT_TAG))` (hash2 is 2-arg).
- The `encodePacked` migrations: all replaced `keccak256(abi.encode(...))` (already 32-B-padded), so
  identical regardless of arg width — no `encodePacked` sub-word divergence exists in HEAD.
**Provisional verdict: REFUTED (every migrated operand is 32-byte; preimages byte-identical).**

### GASID-03 — `PriceLookupLib` nibble-table output identity (concrete)

PROPERTY: the nibble-table `priceForLevel` equals the baseline branch chain over the full domain.
ATTACK: find a (level, cycleOffset) where the nibble table `0x4333222111 >> ((cycleOffset/10)*4) & 0xF`
diverges from the baseline explicit 10-99 branches.
- Decade-multiplier map: cycleOffset/10 ∈ {0,1,2}→1×, {3,4,5}→2×, {6,7,8}→3×, {9}→4× (nibbles of
  `0x4333222111` low→high: 1,1,1,2,2,2,3,3,3,4). Intro tiers 0-4→0.01, 5-9→0.02, milestone
  cycleOffset==0→0.24 preserved verbatim. `unchecked` safe (`0.04 ether * 15 ≪ 2^256`).
- Re-derived the equivalence over the representative bounded domain (all decade buckets + the
  milestone boundary cycleOffset==0 + intro tiers 0-9) and cross-checked against the council's
  exhaustive recomputation over `level ∈ [0, 99999]` = **0 mismatches** (both gemini and codex
  independently recomputed 0 mismatches). The removed explicit 10-99 branches are subsumed because for
  level∈[10,99], `cycleOffset == level` and is never 0, so the single cycle chain reproduces them.
**Provisional verdict: REFUTED (output-identical over the full domain; differential = 0 mismatches).**

### GASID-04 — trait-roll + `_farFutureSeed` equivalence (concrete)

PROPERTY: `_rollWinningTraitsPair` is value-identical to the baseline `_rollWinningTraits(w,false)` +
`(w,true)`, and `_farFutureSeed` is a literal extraction.
ATTACK: find a case where the consolidated single-hero roll produces a different hero/color/trait than
the two-call baseline, or where `_farFutureSeed` differs from the inlined expression.
- Baseline `_rollWinningTraits(w, isBonus)` passed `w` as the 3rd `heroEntropy` arg to
  `_applyHeroOverride` in BOTH calls, so `_rollHeroSymbol(dailyIdx, w)` produced the SAME hero for
  main and bonus; only per-quadrant `heroColor` derived from `r` (= `w` for main, `hash2(w,
  BONUS_TRAITS_TAG)` for bonus). HEAD computes `_rollHeroSymbol(dailyIdx, randWord)` ONCE then applies
  the same hero to main (`_applyHeroResult(traits, randWord, hero…)`) and bonus (`_applyHeroResult(
  traits, rBonus, hero…)`) with `rBonus = hash2(randWord, BONUS_TRAITS_TAG)` == baseline bonus `r`.
  `_rollHeroSymbol` body is byte-identical (`keccak256(abi.encode(entropy, day))`); the two `dailyIdx`/
  `dailyHeroWagers` reads collapse to one but no write intervenes intra-tx so values match.
- `_soloAdjustedEntropy(traitIds, entropy)` reproduces the inlined `(entropy & ~uint256(3)) |
  uint256((3 - _pickSoloQuadrant(traitIds, entropy)) & 3)` exactly.
- `_farFutureSeed(player)` (MintStreakUtils:232) = `keccak256(abi.encodePacked(player,
  rngWordByDay[_simulatedDayIndex()-1]))` — a literal extraction of the baseline-inlined expression at
  the two call sites (MintModule:1185, :1227); one computation vs two, same value intra-tx.
- Boundary/revert paths: inputs unchanged (same `randWord`, `dailyIdx`); no new revert introduced by
  the consolidation.
**Provisional verdict: REFUTED (value-identical hero/color/trait + literal seed extraction).**

### GASID-05 — no externally-observable behavior change

PROPERTY: the gas/refactor set changes no external output, revert, or event.
ATTACK: scan the refactor set for an output/revert/event delta.
- Anchored on GASID-01..04 above (selector/ABI, preimage, nibble-table, trait-roll all identical) +
  the storage Stage-B packs (value-identical) + the green-baseline empty expected-red name set
  (REGRESSION-BASELINE-v63 854/0/110). No observable delta found.
**Provisional verdict: REFUTED (behavior-identical).**

### FC-389-05 — `DecClaimRound.rngWord` uint32 narrowing (gas-half)

PROPERTY: the narrowing changes ONLY the claim-time lootbox SEED width; winner selection uses the
full word.
ATTACK: find a consumer that reads `round.rngWord` expecting full width.
- Winner selection uses the FULL VRF word at snapshot (`decSeed = rngWord`, Decimator:242/:269) and
  stores results in `decBucketOffsetPacked`. The narrowed `round.rngWord` (uint32) is ONLY the claim-
  time lootbox draw seed, sole consumer `_creditDecJackpotClaimCore` (:410) → `resolveLootboxDirect`,
  keccak-mixed with frozen winner/amount/score. No other caller expects full width.
- The DISTRIBUTION-BIAS half (whether 32 bits can bias per-bucket reward distribution across many
  winners) is RNG-02 / FC-391-04 in the 391 RNG sweep — cross-ref recorded; this row adjudicates only
  the narrowing-equivalence half.
**Provisional verdict: REFUTED for the narrowing-equivalence half (seed-only narrowing; winner
selection on full word); distribution-bias half cross-ref 391.**

### FC-389-06 — `lootboxEvCapPacked` level-0 stamp collision

PROPERTY: a window whose level stamp is its initial 0 reads as level-0 `used`, diverging from the
baseline nested map; reachable only if `level==0` is passed.
ATTACK: find a caller path that keys the EV cap at level 0 (or a uint24 `level+1` wrap to 0).
- All callers key `level + 1` / `cachedLevel + 1` / `currentLevel + 1` (cites in STORAGE-04 table),
  so the key is ≥ 1. `level` starts at 0 and Solidity 0.8 checked arithmetic reverts a uint24 wrap
  (would require level == 2^24-1, unreachable). Level 0 is never a cap key, so the initial-0-stamp
  divergence is never observed.
**Provisional verdict: REFUTED (level 0 unreachable as a cap key; +1 keying + 0.8 checked arithmetic).**

### FC-389-07 — `_addLevelDgnrsClaimed` unclamped high-half

PROPERTY: `newClaimed << 128` has no uint128 clamp; relies on the caller invariant
`claimed + add <= allocation <= 2^128`.
ATTACK: find a claim path where `claimed + add` exceeds `allocation` (or 2^128) so the high half
bleeds into the low (allocation) half.
- Bingo direct writer pays `paid <= reward`; aggregate per-level rewards are bounded by
  `allocation * score / totalScore` summed over claimants, with one claim per player
  (DegenerusGameBingoModule.sol:235/:247/:263; affiliate denominator DegenerusAffiliate.sol:692/:703).
  Whale/deity paths reserve `allocation - claimed` before spending the affiliate pool
  (DegenerusGameWhaleModule.sol:735/:804). So `Σ claimed ≤ allocation ≤ uint128` is enforced
  upstream; `newClaimed << 128` never overflows into the allocation half.
**Provisional verdict: REFUTED (caller invariant `claimed ≤ allocation ≤ uint128` enforced at every
claim site).**

---

## Council fold (NET 1 leads compared to NET 2 — read AFTER the independent pass)

After completing the independent attack pass above, I read the council outputs
(389-01-COUNCIL-NET.md + council/{storage,gasid}.{gemini,codex}.txt). Convergence/divergence per item:

| item | NET 2 (this doc) | NET 1 council | convergent? |
|---|---|---|---|
| STORAGE-01/02/03/05 | REFUTED (sound) | both models SOUND/IDENTICAL | ✓ convergent |
| STORAGE-04 / FC-389-01 | REFUTED (cursor-lag proof: deferred opens don't write cap + live-`level+1` keying + +1-monotone level) | both SOUND; gemini traces deferred opens draw from live level, codex cites deferred opens do NOT SSTORE cap | ✓ convergent (codex's "deferred opens do not SSTORE cap" = my load-bearing fact 1) |
| STORAGE-06 cand (1) Composition slot-10 | CONFIRMED stale (mintPacked_ @9, not 10) | codex CONFIRMED (slot 10 is rngWordByDay); gemini said active harnesses clean | ✓ convergent with codex; gemini did not check this handler |
| STORAGE-06 cand (2) box-cursor 58/59 | REFUTED (forge inspect: boxCursor@58 off7, boxPlayers@59 — harness correct) | codex FINDING (claimed moved to 59/60) | ✗ DIVERGENT — codex premise refuted by `forge inspect` this pass |
| STORAGE-06 cand (3) HeroOverride JS slot 35 | CONFIRMED stale (lootboxRngPacked @34, slot 35 is lootboxRngWordByIndex root) | codex CONFIRMED (35 is the word-by-index root) | ✓ convergent with codex |
| STORAGE-07 capBucketCounts | REFUTED as overflow; ≤maxTotal by trim/remainder + 250-clamp double-defense | both DEFENDED (codex traces the 250 clamp + remainder share; gemini "defended") | ✓ convergent |
| FC-389-03 totalBurn raw/effective | accumulator stores EFFECTIVE; DecClaimRound.totalBurn comment CORRECT; imprecision on DecEntry.burn; storage-map FA-3 framing wrong | BOTH models: accumulator stores EFFECTIVE; imprecision on DecEntry.burn | ✓ convergent (all three lenses agree the map's "raw" framing is the error) |
| GASID-01..05 + FC-389-05/06/07/08/09 | all REFUTED (identical/sound) | both models all VERIFIED IDENTICAL/SOUND | ✓ convergent |

Net: convergent on all items except STORAGE-06 candidate (2), where my fresh `forge inspect` REFUTES
the codex stale-slot premise (the box cursors are correctly poked at slot 58's free bytes + slot 59).
Two STORAGE-06 candidates ((1) Composition slot-10, (3) HeroOverride JS slot 35) are CONFIRMED stale
oracle-integrity items (LOW), convergent with codex. No council lead surfaces a contract defect that
NET 2 missed; NET 2's STORAGE-04 cursor-lag proof and the fresh-inspect refutation of candidate (2)
are the two places NET 2 adds precision over the raw council capture.

---

## Byte-freeze attestation

`git diff a8b702a7 -- contracts/` EMPTY and `git status --porcelain contracts/` EMPTY before and after
this pass (a `forge clean` + `forge build` + `forge inspect` ran to capture the authoritative slots;
`ContractAddresses.sol` was NOT regenerated — hardhat was never invoked, per the landmine guard). All
source read via `git show a8b702a7:`. T-389-04 (tampering of the byte-frozen subject) mitigation
satisfied.
