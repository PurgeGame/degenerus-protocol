---
phase: 388-foundation-subject-freeze-green-baseline
plan: 01
artifact: layout-key
subject: a8b702a7 (v63.0 audit subject — byte-frozen at FOUNDATION)
authority: forge inspect <C> storageLayout --json (foundry default profile; storageLayout forces emission)
captured: 2026-06-14
contracts_tree_hash: 2934d3d8987a09c5f073549a0cb499f6c5f28620
prior_key: .planning/milestones/v62.0-phases/380-foundation-test-fix-green-baseline/380-01-LAYOUT-KEY.md (subject c4d48008)
contracts: [DegenerusGame, StakedDegenerusStonk, BurnieCoinflip, DegenerusAdmin]
---

# 388-01 — Authoritative a8b702a7 Storage Layout (4 reshuffled contracts) + Per-Harness Reconciliation Ledger

THE single source of truth for the storage layout of the four contracts the post-v62 packing phase
reshuffled, at the byte-frozen v63 audit subject. Every slot/offset/width below is taken VERBATIM
from `forge inspect <C> storageLayout --json` run against the current working tree (the subject tree
is byte-identical to `a8b702a7` — `git diff a8b702a7 -- contracts` is EMPTY; the post-`a8b702a7`
commits are docs/planning only). Nothing is assumed; the packing shifts are REGION-DEPENDENT, not a
uniform -1.

## 0. How this was captured

```
forge build                                         # clean (only pre-existing nightly lint warnings)
forge inspect DegenerusGame         storageLayout --json
forge inspect StakedDegenerusStonk  storageLayout --json
forge inspect BurnieCoinflip        storageLayout --json
forge inspect DegenerusAdmin        storageLayout --json
```

- `git status --porcelain contracts` is EMPTY before and after (ContractAddresses.sol NOT
  regenerated — hardhat was never invoked, per the plan landmine). Build clean.
- `git diff a8b702a7 -- contracts` is EMPTY (subject byte-frozen; subject tree fingerprint
  `git rev-parse a8b702a7:contracts` = `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
- HEAD is `aeb7c0b5` (a docs(388) commit on top of the subject); the subject-frozen tree is the
  source surface — verified byte-identical to `a8b702a7` above.

## 1. DegenerusGame (delegatecall-shared layout) — authoritative slots

The Game module suite all inherits the one `DegenerusGameStorage` base, so all modules agree on
slots by construction. Max slot 59 (BASE 77580320 max 63 → SUBJ 59, the ~4-slot tail compaction).

### Slot 0 packed flags (bit offsets — verbatim; UNCHANGED from the v62 key)

```
slot 0  offset 3   uint24  dailyIdx
slot 0  offset 6   uint48  rngRequestTime          (bit 48)
slot 0  offset 12  uint24  level                   (bit 96)   <-- AffiliateDgnrsClaim _setLevel poke
slot 0  offset 19  bool    rngLockedFlag           (bit 152)
slot 0  offset 21  bool    gameOver                (bit 168)  <-- DecimatorBountyRegression _setGameOver
slot 0  offset 24  bool    ticketsFullyProcessed   (bit 192)  <-- StorageFoundation asserts
slot 0  offset 25  bool    gameOverPossible        (bit 200)
slot 0  offset 26  bool    ticketWriteSlot         (bit 208)  <-- StorageFoundation asserts
slot 0  offset 27  bool    prizePoolFrozen         (bit 216)  <-- StorageFoundation asserts
slot 0  offset 28  bool    presaleOver             (bit 224)
slot 0  offset 29  bool    subsFullyProcessed      (bit 232)
slot 0  offset 30  bool    presaleDrained          (bit 240)
```

### Balances region + slot-5 co-resident pair + neighbours

```
slot 1  offset 0   uint128  currentPrizePool
slot 1  offset 16  uint128  claimablePool             <-- DecimatorBountyRegression _setClaimablePool (slot 1 high half)
slot 2  offset 0   uint256  prizePoolsPacked          <-- StorageFoundation asserts
slot 3  offset 0   uint256  rngWordCurrent
slot 4  offset 0   uint256  vrfRequestId
slot 5  offset 0   uint64   totalFlipReversals        <-- RngLockDeterminism / VRFStallEdgeCases SLOT_TOTAL_FLIP_REVERSALS=5 (masked RMW)
slot 5  offset 8   uint48   lastVrfProcessedTimestamp (bit 64; co-resident, preserved by the reversals masked store)
slot 7  offset 0   mapping(address=>uint256)  balancesPacked   <-- root unmoved; claimable mapping poked via keccak(addr,7)
slot 9  offset 0   mapping(address=>uint256)  mintPacked_
slot 10 offset 0   mapping(uint24=>uint256)   rngWordByDay      <-- V55RevertFreeEvCap RNG_WORD_BY_DAY_SLOT=10
slot 11 offset 0   uint256  prizePoolPendingPacked    <-- StorageFoundation asserts
```

### Lootbox / presale / Degenerette region

```
slot 15 offset 0   mapping  lootboxEth
slot 16 offset 0   uint96   presaleBoxEthSold
slot 19 offset 0   uint256  presaleStatePacked
slot 21 offset 0   mapping  whalePassClaims
slot 34 offset 0   uint256  lootboxRngPacked          <-- VRFStallEdgeCases SLOT_LOOTBOX_RNG_PACKED=34 (was 36 pre-v62)
slot 35 offset 0   mapping(uint48=>uint256)  lootboxRngWordByIndex   <-- VRFStallEdgeCases (mapping at slot 35)
slot 38 offset 0   mapping  degeneretteBets
slot 39 offset 0   mapping  degeneretteBetNonce
```

### Consolidated tail packs (the post-v62 moves — THE delta-bearing rows)

```
slot 26 offset 0   mapping(uint24=>uint256)  levelDgnrsPacked   <-- alloc[0:128) | claimed[128:256); AffiliateDgnrsClaim SLOT_LEVEL_DGNRS_PACKED=26
slot 36 offset 0   mapping(address=>uint32)  deityBoonPacked    <-- day[0:24) | mask[24:32); no slot-hardcoded poke
slot 40 offset 0   mapping(address=>uint256) lootboxEvCapPacked <-- two level-stamped windows; V55RevertFreeEvCap EV_CAP_PACKED_SLOT=40
slot 41 offset 0   mapping(uint24=>mapping(address=>DecEntry))  decBurn   <-- DecimatorBountyRegression SLOT_DEC_BURN=41
slot 42 offset 0   mapping(uint24=>uint256[13][13])  decBucketBurnTotal
slot 43 offset 0   mapping(uint24=>DecClaimRound)    decClaimRounds      <-- DecimatorBountyRegression SLOT_DEC_CLAIM_ROUNDS=43
slot 44 offset 0   mapping(uint24=>uint64)           decBucketOffsetPacked <-- DecimatorBountyRegression / DecimatorOffsetIsolation SLOT_DEC_OFFSET_PACKED=44
slot 49 offset 0   mapping(bytes32=>uint256)         terminalDecBucketBurnTotal  <-- DecimatorOffsetIsolation SLOT_TERMINAL_BUCKET_BURN=49
slot 53 offset 0   mapping(uint24=>uint64)           bingoFirsts        <-- symbol[0:32) | quadrant[32:36); no slot-hardcoded poke
```

#### DecClaimRound struct (single 32-byte slot at keccak256(abi.encode(lvl, 43)))

```
offset 0    uint96   poolWei
offset 12   uint128  totalBurn   (bit 96)
offset 28   uint32   rngWord     (bit 224)
```

96 + 128 + 32 = 256 bits = exactly one slot. `DecimatorBountyRegression._setClaimRound` packs
`poolWei | (totalBurn<<96) | (rngWord<<224)` — matches the inspected offsets.

### Subscriber region (slot indices)

```
slot 54 offset 0   mapping(address=>Sub)      _subOf
slot 55 offset 0   mapping(address=>address)  _fundingSourceOf
slot 56 offset 0   address[]                  _subscribers   (slot holds length)
slot 57 offset 0   mapping(address=>uint256)  _subscriberIndex
slot 58 offset 0   uint16                     _subCursor
slot 58 offset 2   uint16                     _subOpenCursor
slot 58 offset 4   uint24                     _afkingResetDay
slot 58 offset 19  uint48                     presaleCloseIndex
```

#### Sub struct (single 32-byte slot at keccak256(abi.encode(addr, 54)))

```
byte 0   uint8   dailyQuantity
byte 1   uint24  validThroughLevel
byte 4   uint8   reinvestPct
byte 5   uint8   flags
byte 6   uint16  score
byte 8   uint24  amount
byte 11  uint24  lastAutoBoughtDay
byte 14  uint24  lastOpenedDay
byte 17  uint24  afkCoveredThroughDay
byte 20  uint24  afkingStartDay
byte 23  uint32  affiliateBase
byte 27  uint32  pendingBurnie
byte 31  uint8   subStreakLatch
```

## 2. StakedDegenerusStonk (standalone) — authoritative slots

```
slot 0  offset 0   uint128  _totalSupply
slot 0  offset 16  uint96   _pendingRedemptionEthValue   (bit 128)
slot 0  offset 28  uint24   _pendingResolveDay           (bit 224)   <-- StakedStonkRedemption _storePendingResolveDay (lane [224:247])
slot 1  offset 0   mapping(address=>uint256)  balanceOf
slot 2  offset 0   uint128[5]                 poolBalances   (5 lanes across slots 2,3,4)
slot 5  offset 0   mapping  pendingRedemptions   <-- StakedStonkRedemption SLOT_PENDING_REDEMPTIONS=5
slot 6  offset 0   mapping  redemptionPeriods
slot 7  offset 0   mapping(uint24=>DayPending)  pendingByDay   <-- StakedStonkRedemption SLOT_PENDING_BY_DAY=7
```

The slot-0 pack (`_totalSupply` u128 / `_pendingRedemptionEthValue` u96 / `_pendingResolveDay` u24,
248/256 bits) is the post-v62 consolidation; the pending scalars moved up from former dedicated slots
9/11 (net −3). All fields exposed via explicit external view getters (ABI preserved).

## 3. BurnieCoinflip (standalone) — authoritative slots

```
slot 0  offset 0   mapping(uint24=>mapping(address=>uint256))  coinflipStakePacked   <-- 2 days/slot, 128-bit wei lanes (key day>>1 then player)
slot 1  offset 0   mapping(uint24=>uint256)                    coinflipDayResultPacked <-- 32 days/slot, 8-bit 3-state lanes
slot 2  offset 0   mapping(address=>PlayerCoinflipState)       playerState
slot 3  offset 0   uint128  currentBounty
slot 3  offset 16  uint128  biggestFlipEver
slot 4  offset 0   address  bountyOwedTo
slot 4  offset 20  uint24   flipsClaimableDay     (bit 160)
slot 4  offset 23  bool     sdgnrsAutoRebuyArmed  (bit 184)   <-- NEW post-v62 bool packed into slot-4 free bytes
slot 5  offset 0   mapping  coinflipTopByDay
```

`coinflipStakePacked@0` / `coinflipDayResultPacked@1` are the post-v62 repacks (former
`coinflipBalance` mapping / `coinflipDayResult` struct); `sdgnrsAutoRebuyArmed` is the new bool
in the slot-4 `bountyOwedTo`/`flipsClaimableDay` region's free bytes.

## 4. DegenerusAdmin (standalone) — authoritative slots

```
slot 5  offset 0   mapping(uint256=>mapping(address=>VoterRecord))  voterRecords      <-- post-v62 fold of votes + voteWeight
slot 10 offset 0   mapping(uint256=>mapping(address=>VoterRecord))  feedVoterRecords  <-- post-v62 fold of feedVotes + feedVoteWeight
```

#### VoterRecord struct (6 bytes/slot)

```
offset 0   Vote   v   (1 byte enum)
offset 1   uint40 w   (5 bytes)
```

`votes`/`voteWeight`/`feedVotes`/`feedVoteWeight` re-exposed as explicit view functions (ABI
preserved). No slot-hardcoded harness pokes Admin storage (all reads go through getters).

## 5. Delta column vs the v62 380-01 key (subject c4d48008) — the post-v62 packing moves

c4d48008 → a8b702a7 = c4d48008 + the post-v62 packing phase (storage-packing.md). The slot-0 roots
and the early mapping roots are CONFIRMED unchanged; the tail packs moved.

| Symbol | c4d48008 slot (380-01) | a8b702a7 slot (this key) | moved? | note |
|--------|------------------------|--------------------------|--------|------|
| slot-0 ticketWriteSlot/prizePoolFrozen/ticketsFullyProcessed | off 26/27/24 | off 26/27/24 | no | CONFIRMED unchanged (StorageFoundation passes) |
| slot-0 level (AffiliateDgnrsClaim) | off 12 | off 12 | no | |
| prizePoolsPacked | 2 | 2 | no | CONFIRMED unchanged |
| totalFlipReversals | 5 (full uint256) | 5 (uint64 @off0) | width | now packed with lastVrfProcessedTimestamp @off8 |
| lastVrfProcessedTimestamp | (moved up from slot 50) | 5 @off8 | yes | co-resident with reversals |
| balancesPacked (root) | 7 | 7 | no | CONFIRMED unchanged |
| mintPacked_ | 9 | 9 | no | |
| rngWordByDay | 10 | 10 | no | |
| prizePoolPendingPacked | 11 | 11 | no | CONFIRMED unchanged |
| lootboxRngPacked | 36 | 34 | yes | v62 lootbox repack (−2) |
| lootboxRngWordByIndex | 37 | 35 | yes | v62 lootbox repack (−2) |
| degeneretteBets | 43 | 38 | yes | tail compaction (−5) |
| degeneretteBetNonce | 44 | 39 | yes | tail compaction (−5) |
| levelDgnrsAllocation + levelDgnrsClaimed (2 maps) | 26-27 | levelDgnrsPacked @26 (1 map) | yes | folded alloc[0:128)/claimed[128:256), net −1 |
| deityBoonDay + deityBoonUsedMask (2 maps) | 37-38 | deityBoonPacked @36 (1 map) | yes | folded day[0:24)/mask[24:32), net −1 |
| lootboxEvBenefitUsedByLevel (nested map) | 45 | lootboxEvCapPacked @40 (1 map) | yes | folded to two-window single map, net −1 |
| firstQuadrant + firstSymbol (2 scalars) | (separate) | bingoFirsts @53 (1 map) | yes | folded symbol[0:32)/quad[32:36) |
| DecClaimRound struct | (multi-slot) | 1 slot @43 (u96/u128/u32) | yes | narrowed to one slot |
| _subOf | 62 | 54 | yes | tail compaction (−8) |
| _subscribers | 64 | 56 | yes | tail compaction (−8) |
| _subscriberIndex | 65 | 57 | yes | tail compaction (−8) |
| _subCursor | 66 | 58 | yes | tail compaction (−8) |

StakedDegenerusStonk: slot-0 pack (`_totalSupply`/`_pendingRedemptionEthValue`/`_pendingResolveDay`)
+ `poolBalances` uint128[5] @2 (net −3 vs the c4d48008-era layout, the pending scalars folded up from
former slots 9/11). BurnieCoinflip: `coinflipStakePacked`@0 + `coinflipDayResultPacked`@1 +
`sdgnrsAutoRebuyArmed`@4-off23 (the post-v62 repacks). DegenerusAdmin: `voterRecords`@5 +
`feedVoterRecords`@10 (the votes+weight folds). All standalone-contract ABI getters preserved.

## 6. Per-harness reconciliation ledger (slot-hardcoded pokes targeting a MOVED field)

Classification: **Game-resident** = `vm.store/vm.load(address(game), …)` → must match §1.
**sDGNRS-resident** = `…(address(sdgnrs), …)` → §2. **Coinflip-resident** = `…(address(coinflip), …)` → §3.
The full forge suite runs green at the subject; every poke below was checked literal-by-literal
against the `forge inspect` value and is **confirmed correct** — no re-derivation required.

| Harness | Poke / constant | Target (moved) field | Authoritative slot | Verdict |
|---------|-----------------|----------------------|--------------------|---------|
| `AffiliateDgnrsClaim.t.sol` | `SLOT_LEVEL_DGNRS_PACKED = 26`; alloc low-128 / claimed high-128 RMW | `levelDgnrsPacked` (Game) | slot 26 | confirmed correct @ slot 26 (inspected) |
| `AffiliateDgnrsClaim.t.sol` | `_setLevel` slot-0 off-12 RMW | `level` (Game slot-0) | slot 0 off 12 | confirmed correct @ slot 0 off 12 (inspected; root unchanged) |
| `DecimatorBountyRegression.t.sol` | `SLOT_DEC_BURN = 41` (`decBurn[lvl][player]`) | `decBurn` (Game) | slot 41 | confirmed correct @ slot 41 (inspected) |
| `DecimatorBountyRegression.t.sol` | `SLOT_DEC_CLAIM_ROUNDS = 43`; `poolWei|totalBurn<<96|rngWord<<224` | `decClaimRounds` / DecClaimRound (Game) | slot 43; off 0/12/28 | confirmed correct @ slot 43 (inspected; struct offsets match) |
| `DecimatorBountyRegression.t.sol` | `SLOT_DEC_OFFSET_PACKED = 44` (4-bit subbucket lanes) | `decBucketOffsetPacked` (Game) | slot 44 | confirmed correct @ slot 44 (inspected) |
| `DecimatorBountyRegression.t.sol` | `SLOT_POOLS_1 = 1` (claimablePool high half); `SLOT_HEADER = 0` (gameOver byte 21) | `claimablePool` / `gameOver` (Game) | slot 1 off 16; slot 0 off 21 | confirmed correct (inspected; roots unchanged) |
| `DecimatorOffsetIsolation.t.sol` | `SLOT_DEC_OFFSET_PACKED = 44` | `decBucketOffsetPacked` (Game) | slot 44 | confirmed correct @ slot 44 (inspected) |
| `DecimatorOffsetIsolation.t.sol` | `SLOT_TERMINAL_BUCKET_BURN = 49` | `terminalDecBucketBurnTotal` (Game) | slot 49 | confirmed correct @ slot 49 (inspected) |
| `V55RevertFreeEvCap.t.sol` | `EV_CAP_PACKED_SLOT = 40`; `(lvl<<64)|used` two-window | `lootboxEvCapPacked` (Game) | slot 40 | confirmed correct @ slot 40 (inspected) |
| `V55RevertFreeEvCap.t.sol` | `RNG_WORD_BY_DAY_SLOT = 10` | `rngWordByDay` (Game) | slot 10 | confirmed correct @ slot 10 (inspected; root unchanged) |
| `RngLockDeterminism.t.sol` | `SLOT_TOTAL_FLIP_REVERSALS = 5`; mask to low uint64 | `totalFlipReversals` (Game, now uint64 @off0) | slot 5 off 0 | confirmed correct @ slot 5 (inspected; co-resident timestamp preserved by mask) |
| `VRFStallEdgeCases.t.sol` | `SLOT_TOTAL_FLIP_REVERSALS = 5`; `SLOT_LOOTBOX_RNG_PACKED = 34` | `totalFlipReversals` / `lootboxRngPacked` (Game) | slot 5; slot 34 | confirmed correct (inspected; comment notes "was 36" — already recalibrated for v62) |
| `VRFStallEdgeCases.t.sol` | `lootboxRngWordByIndex` @ slot 35 | `lootboxRngWordByIndex` (Game) | slot 35 | confirmed correct @ slot 35 (inspected) |
| `BurnieEmissionSeeds.t.sol` | `coinflipStakePacked` root slot `0`; key `day>>1` then player; 128-bit lanes | `coinflipStakePacked` (Coinflip) | slot 0 | confirmed correct @ slot 0 (inspected; Coinflip-resident) |
| `CoinflipDeepClaimWorstCaseGas.t.sol` | stake@0, dayResult@1, playerState@2, flipsClaimableDay@4-off20 | Coinflip packs | slots 0/1/2/4 | confirmed correct (inspected; Coinflip-resident) |
| `StakedStonkRedemption.t.sol` | `_storePendingResolveDay` slot-0 lane [224:247] masked RMW | `_pendingResolveDay` (sDGNRS slot-0 pack) | slot 0 off 28 (bit 224) | confirmed correct @ slot 0 off 28 (inspected; sDGNRS-resident) |
| `StakedStonkRedemption.t.sol` | `SLOT_PENDING_BY_DAY = 7`; `SLOT_PENDING_REDEMPTIONS = 5`; balancesPacked @ Game slot 7 | sDGNRS pendingByDay/pendingRedemptions; Game balancesPacked | sDGNRS 7/5; Game 7 | confirmed correct (inspected; Game balances root unchanged) |
| `RedemptionStethFallback.t.sol` | `GAME_CLAIMABLE_SLOT = 7` (balancesPacked); `GAME_SLOT1 = 1` | Game balancesPacked / pools | slot 7; slot 1 | confirmed correct (inspected; roots unchanged) |
| `RedemptionAccounting.t.sol` | `GAME_CLAIMABLE_SLOT = 7`; `SLOT_PENDING_BY_DAY` via handler | Game balancesPacked / sDGNRS pendingByDay | Game 7; sDGNRS 7 | confirmed correct (inspected; roots unchanged) |

**No bare stale slot literal targeting a moved field remains.** Every Game-tail / sDGNRS / Coinflip
poke cites a slot that matches the authoritative `forge inspect` value at the subject. The
DegenerusAdmin folds (`voterRecords`@5 / `feedVoterRecords`@10) have NO slot-hardcoded harness poke
(all Admin reads go through the preserved view getters) — nothing to reconcile there.

## 7. StorageFoundation canary — extended

The `StorageFoundation.t.sol` canary asserts the slot-0 roots (ticketWriteSlot off26 / prizePoolFrozen
off27 / ticketsFullyProcessed off24) + prizePoolsPacked@2 + prizePoolPendingPacked@11 — all CONFIRMED
unchanged. This plan EXTENDS it with a `levelDgnrsPacked@26` tail-pack assertion (vm.store a sentinel
into the alloc/claimed halves of `levelDgnrsPacked[lvl]` and read both halves back) so a future packing
drift on a consolidated tail pack is caught by the canary rather than silently masked. See Task 2.

## 8. No contract change needed

This is verify-confirm-and-record. No `## CONTRACT-CHANGE-NEEDED` row — the subject is byte-frozen and
every moved-field poke already hits the right field under the new layout.
