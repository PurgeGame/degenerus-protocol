# Storage Layout & Packing Correctness — Change-Surface Map (v63)

BASELINE 77580320 → SUBJECT a8b702a7

Scope: verify slot assignments do not collide/alias across delegatecall-shared modules,
packed widths cannot overflow real-world maxima, narrowing casts cannot truncate legitimate
values, and cross-module read/write packing conventions match. READ-ONLY.

## Method

- `git diff 77580320 a8b702a7` on each primary file.
- Authoritative `forge inspect <C> storageLayout --json` for DegenerusGame, StakedDegenerusStonk,
  BurnieCoinflip, DegenerusAdmin at BOTH revisions; diffed slot-by-slot (script output captured).
- Traced every packed field's readers/writers + their value maxima.
- Confirmed clean compile (`forge inspect` succeeds = compiles).

## Trust-boundary classification (CRITICAL framing)

Only **DegenerusGameStorage** is the delegatecall-shared layout. Every Game module
(`DegenerusGame.sol` + `contracts/modules/*.sol`) inherits the SAME `DegenerusGameStorage`
abstract contract, so all modules agree on slot assignments **by construction** — there is no
way for two modules to disagree on a slot as long as they all inherit the one storage base
(verified: 13 modules + Game all `is DegenerusGameStorage`). A delegatecall aliasing/collision
across modules is therefore not structurally possible here; the residual risk is **internal**
packing-helper correctness (masked RMW, width bounds, sign/zero extension).

**DegenerusAdmin, BurnieCoinflip, StakedDegenerusStonk are standalone** (regular CALL, own
storage space). Their slot reshuffles (uniform downward shifts shown below) are internal-only —
the only external risk is a consumer that hardcodes a slot (vm.store/vm.load) rather than using
the ABI getter. All on-chain cross-contract reads go through interface getters (verified), so the
ABI is what matters; all three preserved their public getter ABI.

## Layout diffs (forge inspect, authoritative)

### DegenerusGame (delegatecall-shared)
- slot 5: `totalFlipReversals` uint256 → **uint64 @off0**, NEW `lastVrfProcessedTimestamp` uint48 @off8
  (moved up from a former dedicated slot 50). Co-resident pair, both written in `_applyDailyRng`.
- slots 26-27: `levelDgnrsAllocation` + `levelDgnrsClaimed` (2 mappings) → **`levelDgnrsPacked`**
  (1 mapping, alloc[0:128)/claimed[128:256)). Net −1 slot; everything below shifts up −1.
- slots 37-38: `deityBoonDay` + `deityBoonUsedMask` (2 mappings) → **`deityBoonPacked`** uint32
  (day[0:24)/mask[24:32)). Net −1.
- slot 42: `lootboxEvBenefitUsedByLevel` (mapping(addr→mapping(lvl→uint256))) →
  **`lootboxEvCapPacked`** (mapping(addr→uint256), two level-stamped windows). Net −1.
- slots 56-57: `firstQuadrant` (uint8) + `firstSymbol` (uint32) → **`bingoFirsts`** uint64
  (symbol[0:32)/quadrant[32:36)). Net −1.
- `DecClaimRound` struct: `poolWei` uint256→uint96, `totalBurn` uint232→uint128, `rngWord`
  uint256→uint32; now 1 slot (96+128+32=256).
- Net effect: Game storage tail shifted up ~4 slots (BASE max slot 63 → SUBJ max slot 59). All
  modules see the new layout uniformly — fine. Slot-hardcoded TEST harnesses WILL need recalibration
  (known repo issue; not a contract defect).

### StakedDegenerusStonk (standalone)
- slot 0: `totalSupply` uint256 → **`_totalSupply` uint128 @0 + `_pendingRedemptionEthValue` uint96
  @16 + `_pendingResolveDay` uint24 @28** (248/256 bits). The two pending scalars moved up from
  former dedicated slots 9 and 11.
- slot 2: `poolBalances` uint256[5] → **uint128[5]** (5 lanes in 3 slots).
- Net −3 slots; `pendingRedemptionEthValue`/`pendingResolveDay`/`totalSupply` are now PRIVATE packed
  fields exposed via explicit `external view` getters (ABI preserved — interface decls unchanged).

### BurnieCoinflip (standalone)
- slot 0: `coinflipBalance` (mapping→uint256) → **`coinflipStakePacked`** (2 days/slot, 128-bit
  lossless wei lanes).
- slot 1: `coinflipDayResult` (struct{uint16,bool}) → **`coinflipDayResultPacked`** uint256
  (32 days/slot, 8-bit 3-state lanes).
- slot 4 @off23: NEW `sdgnrsAutoRebuyArmed` bool (packs into the `flipsClaimableDay`/`bountyOwedTo`
  region's free bytes).

### DegenerusAdmin (standalone)
- slots 5-6: `votes` (mapping→Vote enum) + `voteWeight` (mapping→uint40) → **`voterRecords`**
  (mapping→struct{Vote v; uint40 w}) — 6 bytes/slot. Same for `feedVotes`/`feedVoteWeight` →
  `feedVoterRecords`. `votes()`/`voteWeight()`/`feedVotes()`/`feedVoteWeight()` re-exposed as
  explicit view functions (ABI preserved). `ProposalState` enum dropped `Expired` (3 states,
  still 1 byte; expiry computed live from `createdAt`).

## Per-pack correctness verdict

### SOUND (verified)

1. **slot-5 `totalFlipReversals` uint64 + `lastVrfProcessedTimestamp` uint48** — separate field
   assignments (compiler-managed masked RMW), NOT manual packing. Reversals bound: every nudge
   burns ≥100 BURNIE, supply uint128-capped → count < supply/1e20 << 2^64. Timestamp uint48 holds
   year-8.9M. Reset to 0 (line 1888) is a plain field write. No manual pack = no pack bug.

2. **`levelDgnrsPacked`** (alloc[0:128)/claimed[128:256)) — DGNRS base units bounded by sDGNRS
   supply ~1e30 << uint128 (3.4e38). `_addLevelDgnrsClaimed` adds to high half; claimed is monotone
   toward allocation (≤uint128) so high half never overflows. `_setLevelDgnrsAllocation` preserves
   claimed half via mask. Callers: Bingo/Whale/Advance — all read/write via the helpers (consistent).

3. **`deityBoonPacked`** (day[0:24)/mask[24:32)) — BOTH readers (Game.sol:884, Lootbox:1146) use
   the IDENTICAL convention (`uint24(packed)` day, `uint8(packed>>24)` mask, stale-day mask reads 0).
   `slot` gated `< DEITY_DAILY_BOON_COUNT (3)` so `1<<slot ≤ 4` fits the 8-bit mask. Cross-module
   read/write convention MATCHES.

4. **`bingoFirsts`** (symbol[0:32)/quad[32:36)) — single module (Bingo). `qMask = 1<<quadrant`,
   quadrant 0-3 → ≤0xF (4 bits, no bleed past bit 35). Symbol mask uint32 (32 symbols). Reads
   `uint8(bf>>32)`/`uint32(bf)`; writes mask the correct half. Sound.

5. **`lootboxEvCapPacked` two-window** — live key set proven to be exactly {currentLevel,
   currentLevel+1}: all resolve/open sites call `_applyEvMultiplierWithCap(player, currentLevel,…)`
   (Lootbox:887/974/1097) and all deposit sites use `level+1`/`currentLevel+1` (Whale:852,
   Afking:970, Mint:1685/1706). Each window: used uint64 (clamped to CAP=10 ether=1e19 < 2^64) +
   level uint24. Eviction discards the smaller-level window when neither matches → always strictly
   older than a live adjacent pair. See focus area FA-1 (robustness under multi-level jumps is the
   one thing worth an adversarial poke, though single-level advance is provably safe).

6. **`DecClaimRound.rngWord` uint32** — winner selection uses the FULL VRF word (`decSeed = rngWord`
   at line 242, `_decWinningSubbucket`) and stores results in `decBucketOffsetPacked`. `round.rngWord`
   (narrowed) is ONLY the claim-time lootbox draw seed, consumed by `_creditDecJackpotClaimCore`
   (line 410) keccak-mixed with frozen winner/amount/score. RNG-freeze invariant intact: 32 bits of
   post-fulfillment entropy, no player-controllable input at claim. Sound.

7. **`DecClaimRound.poolWei` uint96 / `totalBurn` uint128** — poolWei is real-ETH bounded
   (7.9e10 ETH headroom). totalBurn accumulates RAW per-player burns (`delta` is uint192 `e.burn`,
   not the 2.35x effective amount), summed across ≤11 winning subbuckets, total ≤ BURNIE supply
   (uint128-capped). Narrowing safe. NOTE: storage comment says "sum of effective amounts (≤2.35x)"
   but the accumulator stores raw burns — comment imprecision, bound still holds (see FA-3, INFO).

8. **BurnieCoinflip 8-bit 3-state day result** — 0=unresolved, 1=loss sentinel, 50..156=win.
   Win max = lucky 150 + bonus 6 = 156 < 255; normal win min = 78. Loss sentinel 1. Win-detection
   `b >= 50` never collides (all wins ≥50, sentinel=1<50). `bonus` proven ∈{0,2,6} (Advance:377).
   Resolution-detection `rewardPercent != 0` still works (loss reads 1). Sound.

9. **BurnieCoinflip 128-bit lossless stake lanes** — stake stored in WEI (sub-1-BURNIE credits
   preserved), masked RMW preserving sibling day. Bound: stake ≤ supply ≤ uint128 (BurnieCoin
   supply cap). Constructor seed 200k ether = 2e23 << uint128. Sound.

10. **StakedStonk `_totalSupply` uint128** — INITIAL_SUPPLY 1e30 << uint128 (3.4e38, ~3e8x).
    Monotonically non-increasing post-construction (only `_mint` adds, constructor-only). All
    `uint128(_totalSupply - amount)` casts on values ≤ prior supply → cannot truncate. Sound.

11. **StakedStonk `_pendingRedemptionEthValue` uint96** — real-ETH bounded (7.9e10 ETH vs ~1.2e8
    actual ETH supply, ~658x). Casts on checked-subtraction results = segregated ETH. See FA-2 (the
    cast itself does not revert on >uint96, relies on the economic bound; INFO).

12. **StakedStonk `poolBalances` uint128[5]** — sum conserved = constructor total ≤ INITIAL_SUPPLY
    < uint128. `transferBetweenPools` dest add is checked arithmetic on a sum bounded by pool total.
    Constructor narrowing casts on BPS slices of 1e30. Sound (cast-truncation relies on conservation
    invariant; same INFO class as FA-2).

13. **DegenerusAdmin `VoterRecord{Vote v; uint40 w}`** — co-locates the PRE-EXISTING uint40 weight
    (already uint40 at baseline) with the 1-byte Vote enum. No new truncation. Weight = whole tokens
    `uint40(raw/1e18)` max ~1.1e12 fits uint40. ProposalState 3-state still 1 byte. Sound.

14. **`_debitClaimableAndAfking`** (balancesPacked low=claimable/high=afking) — guards EACH half
    explicitly before the combined `packed - claimable - (afking<<128)`: low-half borrow (invisible
    to 0.8 full-word check) and oversized afking (would truncate in `<<128`) both closed. Matches
    sequential debit. Sound.

15. **`subStreakLatch` 0x7f→0xff widening** — field always occupied its own dedicated byte; only the
    in-byte usage widened (bit 7 was "unused"). No co-resident collision. `recordAfkingSecondary`
    +1 clamps at 255. Sound.

16. **`ticketsOwedPacked` read** `if (owed==0 && rem==0)` → `if (packed==0)` — packed=(owed<<8)|rem,
    so packed==0 iff both halves 0. Semantically identical. Sound.

17. **`lootboxRngPacked` field removal** (`lootboxRngMinLinkBalance` @[176:183) deleted) — ZERO
    stale readers (grep clean). Bits [176:183) now genuinely unused. `_lrAdd` re-masks the sum before
    merge (wrap-on-mask, same as read-add-write); callers add to PENDING_ETH (64b) / PENDING_BURNIE
    (40b), accumulated-then-zeroed, bounded under width. Sound.

## Candidate focus areas (leads for adversarial sweep — NOT confirmed findings)

- **FA-1 (LOW)** `lootboxEvCapPacked` two-window eviction. The {currentLevel, currentLevel+1}
  invariant is proven for the call sites today and robust to single-level advances. A closer poke:
  is there any path that records EV-cap usage at a level that is NOT in {currentLevel, currentLevel+1}
  at the moment of the write (e.g. a deferred/queued resolve that runs after two level transitions,
  or a far-future ticket path)? If a third distinct level key is ever live, eviction silently zeroes
  a live window → player's accrued EV-benefit resets → they re-earn up to the 10 ETH cap, exceeding
  the intended per-level cap. Worth confirming the resolve cursor cannot lag >1 level behind a deposit.

- **FA-2 (INFO)** `_pendingRedemptionEthValue = uint96(...)` and `poolBalances[toIdx] = uint128(...)`:
  the explicit narrowing cast does NOT revert if the (checked) intermediate exceeds the target width —
  it silently truncates. Safety rests entirely on the economic bound (real-ETH < uint96; pool
  conservation < uint128). Adversarial lens: any path that could inflate segregated ETH or a pool
  beyond its width (it shouldn't exist, but confirm no double-credit / accounting drift accumulates
  `_pendingRedemptionEthValue` unboundedly). Truncation here would understate segregated ETH →
  solvency-accounting drift.

- **FA-3 (INFO)** `DecClaimRound.totalBurn` storage comment claims "sum of effective amounts
  (≤2.35x BURNIE burned)" but the accumulator `decBucketBurnTotal` stores RAW burns (`delta` =
  uint192 `e.burn`). Bound still holds (raw < effective < supply < uint128). Comment-only mismatch;
  flagging so the sweep doesn't waste time re-deriving a non-existent overflow, and in case a future
  reader trusts the (wrong) "effective amount" framing.

- **FA-4 (LOW)** Test-harness slot recalibration. The Game tail shifted ~4 slots and StakedStonk
  −3 / Coinflip / Admin all shifted. Any `vm.store`/`vm.load` harness hardcoding pre-shift slots will
  silently read/write the WRONG field at RUNTIME (compile stays green) — a known repo landmine. Not a
  contract defect, but a regression-oracle integrity risk: a packing bug could hide behind a harness
  that's now writing the wrong slot. Sweep should confirm the regression baseline was recalibrated
  against `forge inspect` (per the storage-packing-breaks-slot-hardcoded-tests memory).

## Bottom line

No collision/aliasing is structurally possible in the delegatecall-shared layout (single inherited
storage base). All narrowed widths verified against documented real-world maxima with healthy
headroom; all narrowing casts sit on values bounded by economic invariants (supply caps, ETH supply,
pool conservation). Cross-module packing conventions (deityBoonPacked, levelDgnrsPacked) match between
their distinct readers/writers. The RNG-touching narrowing (DecClaimRound.rngWord uint32) preserves
the freeze invariant — winner selection stays on the full word. Highest-value adversarial lead is
FA-1 (two-window EV-cap eviction under any multi-level lag), then FA-2/FA-4 accounting/harness drift.
