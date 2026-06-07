---
phase: 380-foundation-test-fix-green-baseline
plan: 01
artifact: layout-key
subject: c4d48008 (b97a7a2e v61 closure HEAD + the forgiving-funding feat)
authority: forge inspect DegenerusGame storageLayout (foundry default profile; storageLayout forces emission)
captured: 2026-06-07
contracts_tree_hash: bbffe99ede11adadcabcc9b81295566176575d47
---

# 380-01 — Authoritative c4d48008 Storage Layout + Per-Harness Recalibration Ledger

THE single source of truth for the DegenerusGame storage layout at audit subject `c4d48008`.
Every slot/offset below is taken VERBATIM from `forge inspect DegenerusGame storageLayout` run
against the current working tree (contracts == `c4d48008`, tree hash
`bbffe99ede11adadcabcc9b81295566176575d47`). Nothing is guessed.

## 0. How this was captured

```
forge clean && forge build                       # clean (only pre-existing lint warnings)
forge inspect DegenerusGame storageLayout --json # emits the layout regardless of profile
```

`git status --porcelain contracts/` is EMPTY before and after (ContractAddresses.sol NOT
regenerated — hardhat was never invoked, per the plan landmine). Build clean.

## 1. Subject delta vs the 378-01 v61-HEAD key — STORAGE IS BYTE-IDENTICAL

`c4d48008 = b97a7a2e + feat(payments): forgiving funding`. The forgiving-funding commit
(`git show --stat c4d48008`) changed:

| File | What |
|------|------|
| `contracts/DegenerusGame.sol` | combined-buy split + receive() routes stray ETH to afking |
| `contracts/modules/DegenerusGameMintModule.sol` | `_mintCost` de-dup, overpay→afking |
| `contracts/modules/DegenerusGameWhaleModule.sol` | whale/lazy/deity overpay→afking |
| `contracts/storage/DegenerusGameStorage.sol` | **+15 lines: `_settleShortfall`, `_creditAfkingValue`, the `_claimableOf`/`_afkingOf`/`_credit*`/`_debit*` accessors + `AfkingFunded` event** |

The +15 lines in `DegenerusGameStorage.sol` are **functions and an event — NO new storage
variable**. Therefore **every storage slot is identical to the 378-01 v61-HEAD key.** The
`forge inspect` dump below confirms this symbol-for-symbol against `378-01-RECALIBRATION-KEY.md`
§2/§3: zero rows moved. The 378 key's spot-check note (balancesPacked@7, prizePoolPendingPacked@11,
ticketWriteSlot@slot0-off26, deityPassPricePaid@29 unchanged) is corroborated and EXTENDED to the
full poked-symbol set here.

## 2. Authoritative c4d48008 layout (verbatim — affected + asserted symbols)

### Slot 0 packed flags (bit offsets — verbatim from forge inspect)

```
slot 0  offset 12  uint24  level                  (bit 96)   <-- _setLevel poke (V56Sub/Keeper)
slot 0  offset 19  bool    rngLockedFlag          (bit 152)
slot 0  offset 21  bool    gameOver               (bit 168)
slot 0  offset 24  bool    ticketsFullyProcessed  (bit 192)  <-- StorageFoundation asserts
slot 0  offset 25  bool    gameOverPossible       (bit 200)
slot 0  offset 26  bool    ticketWriteSlot        (bit 208)  <-- StorageFoundation asserts
slot 0  offset 27  bool    prizePoolFrozen        (bit 216)  <-- StorageFoundation asserts
slot 0  offset 28  bool    presaleOver            (bit 224)
slot 0  offset 29  bool    subsFullyProcessed     (bit 232)
```

rngRequestTime is uint48 @ slot 0 offset 6 (bit 48). dailyIdx is uint24 @ slot 0 offset 3 (bit 24).

### Balances region + neighbours (slot indices)

```
slot 1  offset 0   uint128  currentPrizePool
slot 1  offset 16  uint128  claimablePool          <-- StorageFoundation slot-1 / KeeperNonBrick poke
slot 2  offset 0   uint256  prizePoolsPacked       <-- StorageFoundation asserts
slot 3  offset 0   uint256  rngWordCurrent         <-- VRFCore/VRFStall SLOT_RNG_WORD_CURRENT
slot 4  offset 0   uint256  vrfRequestId           <-- VRFCore/VRFStall SLOT_VRF_REQUEST_ID
slot 5  offset 0   uint256  totalFlipReversals     <-- VRFStall SLOT_TOTAL_FLIP_REVERSALS
slot 7  offset 0   mapping(address=>uint256)  balancesPacked   <-- root unmoved (semantic fold)
slot 8  offset 0   mapping                    traitBurnTicket  <-- (NOTE: NOT afkingFunding — that mapping is GONE)
slot 9  offset 0   mapping(address=>uint256)  mintPacked_
slot 10 offset 0   mapping(uint24=>uint256)   rngWordByDay
slot 11 offset 0   uint256  prizePoolPendingPacked <-- StorageFoundation asserts
slot 12 offset 0   mapping  ticketQueue
slot 13 offset 0   mapping  ticketsOwedPacked
slot 14 offset 0   uint32   ticketCursor
slot 14 offset 4   uint24   ticketLevel
```

### Lootbox / presale / Degenerette region (slot indices)

```
slot 15 offset 0   mapping  lootboxEth
slot 16 offset 0   uint96   presaleBoxEthSold
slot 17 offset 0   mapping  presaleBoxCredit
slot 18 offset 0   mapping  presaleBoxEth
slot 21 offset 0   mapping  whalePassClaims
slot 22 offset 0   mapping  lootboxEthBase
slot 36 offset 0   uint256  lootboxRngPacked       <-- LR_INDEX low 48 bits, LR_MID_DAY bit 224
slot 37 offset 0   mapping  lootboxRngWordByIndex  (lootboxRngWordByIndex[i] @ keccak256(abi.encode(i, 37)))
slot 38 offset 0   mapping  lootboxPurchasePacked
slot 39 offset 0   mapping  lootboxBurnie
slot 43 offset 0   mapping  degeneretteBets
slot 44 offset 0   mapping  degeneretteBetNonce
slot 45 offset 0   mapping  lootboxEvBenefitUsedByLevel
```

### Subscriber region (slot indices)

```
slot 62 offset 0   mapping(address=>Sub)      _subOf
slot 63 offset 0   mapping(address=>address)  _fundingSourceOf
slot 64 offset 0   address[]                  _subscribers      (slot holds length)
slot 65 offset 0   mapping(address=>uint256)  _subscriberIndex
slot 66 offset 0   uint16                     _subCursor
slot 66 offset 2   uint16                     _subOpenCursor
slot 66 offset 4   uint24                     _afkingResetDay
```

### Sub struct (single 32-byte slot at keccak256(abi.encode(addr, 62)))

```
byte 0   uint8   dailyQuantity
byte 1   uint24  validThroughLevel
byte 4   uint8   reinvestPct
byte 5   uint8   flags
byte 6   uint16  scorePlus1
byte 8   uint24  amount
byte 11  uint24  lastAutoBoughtDay
byte 14  uint24  lastOpenedDay
byte 17  uint24  afkCoveredThroughDay
byte 20  uint24  afkingStartDay
byte 23  uint32  affiliateBase
byte 27  uint32  pendingBurnie
byte 31  uint8   subStreakLatch
```

## 3. Delta column vs the 378-01 key — ALL UNCHANGED

| Symbol | 378-01 v61-HEAD slot | c4d48008 slot | moved? |
|--------|----------------------|---------------|--------|
| balancesPacked (root) | 7 | 7 | no |
| mintPacked_ | 9 | 9 | no |
| rngWordByDay | 10 | 10 | no |
| prizePoolPendingPacked | 11 | 11 | no |
| ticketQueue | 12 | 12 | no |
| lootboxEth | 15 | 15 | no |
| lootboxEthBase | 22 | 22 | no |
| lootboxRngPacked | 36 | 36 | no |
| lootboxRngWordByIndex | 37 | 37 | no |
| degeneretteBets | 43 | 43 | no |
| degeneretteBetNonce | 44 | 44 | no |
| _subOf | 62 | 62 | no |
| _subscribers | 64 | 64 | no |
| _subscriberIndex | 65 | 65 | no |
| _subCursor | 66 | 66 | no |
| slot-0 ticketWriteSlot/prizePoolFrozen/ticketsFullyProcessed | off 26/27/24 | off 26/27/24 | no |

**Conclusion:** the c4d48008 forgiving-funding feat added accessor functions only; storage is
byte-identical to the v61 HEAD. No slot moved between the 378 recalibration and this subject.

## 4. Per-harness recalibration ledger (this plan's 10 files)

Classification: **Game-resident** = `vm.store/vm.load(address(game), …)` → must match this layout.
The v61 recalibration (378-01..03, committed inside the b97a7a2e→c4d48008 range) ALREADY moved the
VRFCore / VRFStallEdgeCases / V56SubHardening slot constants to the authoritative values — those
files are already correct at c4d48008. KeeperNonBrick was NOT in that batch and still carries the
v54-era (pre-v55-append) layout.

| Harness | Game-resident slot constants | State at c4d48008 | Action (this plan) |
|---------|------------------------------|-------------------|--------------------|
| `StorageFoundation.t.sol` | slot-0 offsets 208/216/192; slot 2; slot 11 | AUTHORITATIVE (24/24 green) | none — already correct |
| `VRFCore.t.sol` | slot 36 (lootboxRngPacked), 3, 4, 0 (rng time off 48) | AUTHORITATIVE (recalibrated in the c4d48008 range) | none — slots correct; 1 carried behavioral red (§5) |
| `VRFStallEdgeCases.t.sol` | slot 36, 37, 3, 4, 5, 0 (off 48/24) | AUTHORITATIVE (recalibrated in range) | none — slots correct; 3 carried behavioral reds (§5) |
| `VrfRotationLiveness.t.sol` | slot 36, 37, 3, 0 | AUTHORITATIVE (6/6 green) | none — already correct |
| `LootboxRngLifecycle.t.sol` | (via getters / authoritative reads) | AUTHORITATIVE (21/21 green) | none — already correct |
| `KeeperNonBrick.t.sol` | LOOTBOX_RNG_PACKED 38→**36**, LOOTBOX_RNG_WORD 39→**37**, DEGENERETTE_BETS 45→**43**, DEGENERETTE_BET_NONCE 46→**44**, LOOTBOX_ETH 16→**15**, LOOTBOX_ETH_BASE 23→**22**, MINTPACKED 10→**9**, RNG_WORD_BY_DAY 11→**10**, SUBOF 65→**62**, SUBSCRIBERS 67→**64**, SUBSCRIBER_INDEX 68→**65**, RNG_LOCKED_SHIFT 168→**152** (off 19), GAME_OVER_SHIFT 184→**168** (off 21); AFKING_FUNDING_SLOT 8 = dead (mapping folded) | **STALE (v54-era)** | **RECALIBRATE all** (2 active tests stay green; removes the stale literals; the dead afkingFunding constant removed) |
| `V56SubHardening.t.sol` | SUBOF **62**, SUBSCRIBER_INDEX **65**, MINTPACKED **9**, LEVEL_OFF **12** | AUTHORITATIVE (recalibrated in range) | none — slots correct; 1 carried behavioral red (§5) |
| `QueueDoubleBuffer.t.sol` | NONE (pure harness extends DegenerusGameStorage; no vm.store/load) | n/a | **FIXTURE FIX** — setUp missing `vm.warp` past JACKPOT_RESET_TIME → 5 `Panic(0x11)` reds (§5) |
| `FarFutureIntegration.t.sol` | (warps in setUp; queue via exposed fns) | green | none — already green |
| `FarFutureSalvageSwap.t.sol` | (DegenerusGame vs StakedDegenerusStonk pokes) | green | none — already green |

## 5. The 10 c4d48008 reds in this plan's named set — root-caused

`forge test --match-contract <the 10> --no-match-test invariant_` at c4d48008 = **121 passed /
10 failed / 13 skipped**. The 10 reds split into:

**(a) FIXABLE — fixture (5 reds, → GREEN this plan):** `QueueDoubleBuffer` —
`testQueueTicketsUsesWriteKey`, `testQueueTicketsScaledUsesWriteKey`,
`testQueueTicketRangeUsesWriteKey`, `testWriteReadIsolation`, `testQueueAfterSwapUsesNewWriteKey`.
Root cause: `QueueHarness` extends `DegenerusGameStorage`; the queue-write fns call
`_livenessTriggered()` → `_simulatedDayIndex()` → `GameTimeLib.currentDayIndexAt(block.timestamp)`.
At foundry default `block.timestamp = 1`, `ts - JACKPOT_RESET_TIME (82620)` underflows →
`Panic(0x11)`. `QueueDoubleBufferTest.setUp` never warps. The green sibling suites (FarFuture*,
KeeperNonBrick, V56Sub) all `vm.warp(block.timestamp + 1 days)` in setUp. FIX = add that warp.
NOT slot-drift, NOT a contract bug (mainnet deploys at a real timestamp ≫ JACKPOT_RESET_TIME).

**(b) CARRIED behavioral reds (5, NOT this plan's target — documented):**
`V56SubHardening::testChurnSameDayAccruesSlot0Once`,
`VRFCore::test_midDayRequest_doesNotBlockDaily`,
`VRFStallEdgeCases::test_gapBackfillEntropyUnique_fuzz`,
`VRFStallEdgeCases::test_gapBackfillSingleDayGap`,
`VRFStallEdgeCases::test_gapDaysSkipResolveRedemptionPeriod`.
These are in the v61 NON-WIDENING union (`test/REGRESSION-BASELINE-v61.md` §3 lines 92/138/139/162
+ §7 final verdict NON-WIDENING HOLDS). EVIDENCE they are carried (pre-existing, NOT introduced by
the c4d48008 delta):
  - The reds' code paths (gap-backfill / mid-day VRF gating / subscribe-churn) live in
    `DegenerusGameAdvanceModule.sol` + the subscribe path; `git diff b97a7a2e c4d48008 --
    contracts/modules/DegenerusGameAdvanceModule.sol` = EMPTY (untouched).
  - The slot literals in these 3 test files were already recalibrated to the authoritative
    c4d48008 values inside the b97a7a2e→c4d48008 range (`git diff b97a7a2e c4d48008 -- <files>`
    shows ONLY slot-constant + offset edits — 65→62, 10→9, 37→36, off 64→48 — the v61 378
    recalibration). The remaining reds survived that recalibration → they are behavioral, not slot.
  - They assert a specific entropy FORMULA (`keccak256(vrfWord, day)`), a mid-day-RNG setup
    precondition, and a churn-idempotency `pendingBurnie` value that the frozen contract realizes
    differently. Re-deriving the contract's actual behavior into the test expectations is OUT of
    this plan's slot-recalibration scope and was already adjudicated ACCEPTED-CARRIED by the v61
    milestone close. Per the hard constraint: do NOT change `contracts/` to match a stale test.

No `## CONTRACT-CHANGE-NEEDED` — none of the 10 reds require a contract change.
