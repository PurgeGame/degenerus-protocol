---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 01
artifact: recalibration-key
subject: v61 HEAD (b97a7a2e batched diff + 056481ea 377 Outcome-A)
authority: forge inspect DegenerusGame storageLayout (foundry default profile; storageLayout forces emission)
captured: 2026-06-07
---

# 378-01 — Authoritative v61 Storage Layout + Slot-Shift Recalibration Key

This is the SINGLE SOURCE OF TRUTH for the v61 DegenerusGame storage layout. Plans 378-02
(gas-harness recalibration) and 378-03 (behavior fixes) cite this file. Every slot here is
taken VERBATIM from `forge inspect DegenerusGame storageLayout` against the v61 HEAD subject —
none are guessed, and the plan's `-1 hypothesis` is treated as a hypothesis only (the measured
delta is recorded below, and it is NOT a uniform -1; see §3).

## 0. How this was captured

```
forge clean && forge build           # regenerate artifacts (no other forge process running)
forge inspect DegenerusGame storageLayout
```

`include_storage = true` is set on the `[invariant]`/`[deep.invariant]` profiles, but
`forge inspect ... storageLayout` emits the layout regardless of profile. Build was clean
(only pre-existing lint warnings). contracts/ fingerprint unchanged throughout
(`fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf`).

## 1. The v61 PACK fold (what changed in storage)

v61 replaced two balance mappings with one:

| Tree | Balance mappings | Net |
|------|------------------|-----|
| pre-v61 (e18af451 / pre-376) | `claimableWinnings` (slot 7) + `afkingFunding` (separate slot) | 2 slots |
| v61 HEAD | `balancesPacked` (slot 7) `[afking:high128 \| claimable:low128]` | 1 slot |

Net **−1 storage slot in the balances region**. The fold sits early in
`DegenerusGameStorage` (decl L418), so:
- slots **at/before** the balances mapping root (slot 7) are UNSHIFTED;
- slots **after** the removed `afkingFunding` mapping shift down.

Accessor semantics (DegenerusGameStorage.sol:892-928) — load-bearing for the redemption recal:
- `_claimableOf(p) = uint128(balancesPacked[p])`  → **low 128 bits = the old `claimableWinnings` semantics**
- `_afkingOf(p)    = balancesPacked[p] >> 128`     → high 128 bits = the old `afkingFunding` semantics
- `_creditClaimable`/`_debitClaimable` touch the low half; `_creditAfking`/`_debitAfking` the high half.

## 2. Authoritative v61 layout (verbatim — affected + asserted symbols)

### Slot 0 packed flags (bit offsets — CHANGED by the v61 fold's two new bools)

```
slot 0  offset 24  bool   ticketsFullyProcessed
slot 0  offset 25  bool   gameOverPossible
slot 0  offset 26  bool   ticketWriteSlot
slot 0  offset 27  bool   prizePoolFrozen
slot 0  offset 28  bool   presaleOver          <-- present in v61
slot 0  offset 29  bool   subsFullyProcessed   <-- present in v61
```

NOTE: `presaleOver` (offset 28) + `subsFullyProcessed` (offset 29) occupy the two HIGH byte
slots of slot 0. The flags `StorageFoundation.testSlot0FieldOffsets` asserts (`ticketWriteSlot`,
`prizePoolFrozen`, `ticketsFullyProcessed`) sit at offsets 26/27/24 — i.e. **shifted down by 2
byte-positions** from the offsets that test hardcoded (28/29/26 → bit 224/232/208). This is a
within-slot-0 bit-offset shift, distinct from the post-balances slot-index shift in §3.

### Balances region + neighbours (slot indices)

```
slot 1  offset 0   uint128  currentPrizePool
slot 1  offset 16  uint128  claimablePool          <-- UNSHIFTED (pre-balances)
slot 2  offset 0   uint256  prizePoolsPacked       <-- UNSHIFTED (StorageFoundation asserts)
slot 7  offset 0   mapping(address=>uint256)  balancesPacked   <-- root AT old claimableWinnings slot 7
slot 8  offset 0   mapping  traitBurnTicket
slot 9  offset 0   mapping(address=>uint256)  mintPacked_      <-- was 10 pre-fold (-1)
slot 10 offset 0   mapping(uint24=>uint256)   rngWordByDay     <-- was 11 pre-fold (-1)
slot 11 offset 0   uint256  prizePoolPendingPacked <-- UNSHIFTED (StorageFoundation asserts)
slot 12 offset 0   mapping  ticketQueue
```

### Subscriber region (slot indices)

```
slot 62 offset 0   mapping(address=>Sub)      _subOf
slot 64 offset 0   address[]                  _subscribers      (slot holds length)
slot 65 offset 0   mapping(address=>uint256)  _subscriberIndex
slot 66 offset 0   uint16                     _subCursor
slot 66 offset 2   uint16                     _subOpenCursor
slot 66 offset 4   uint24                     _afkingResetDay
```

### Lootbox / Degenerette region (slot indices — for the gas-harness ledger)

```
slot 14 offset 0   uint32   ticketCursor
slot 15 offset 0   mapping  lootboxEth
slot 17 offset 0   mapping  presaleBoxCredit
slot 21 offset 0   mapping  whalePassClaims
slot 22 offset 0   mapping  lootboxEthBase
slot 36 offset 0   mapping  lootboxRngPacked
slot 37 offset 0   mapping  lootboxRngWordByIndex
slot 38 offset 0   mapping  lootboxPurchasePacked
slot 39 offset 0   mapping  lootboxBurnie
slot 43 offset 0   mapping  degeneretteBets
slot 44 offset 0   mapping  degeneretteBetNonce
slot 45 offset 0   mapping  lootboxEvBenefitUsedByLevel
```

## 3. Measured slot-shift delta (NOT a uniform -1)

The plan's hypothesis was `-1` for the post-balances symbols, measured against the gas
harnesses' pinned constants (`_subOf=65, _subscribers=67, _subCursor=69`). **The measured
delta is region-dependent and is NOT -1 vs those constants** — because the in-code gas-harness
constants (65/67/69) were stale even before v61 (their own NatSpec comments document the
e18af451 truth as `_subOf=66/_subscribers=68/_subCursor=70`, never applied to the constants).

The recalibration target is therefore the **authoritative v61 value** (col 3), not a delta:

| Symbol | gas-harness in-code constant (HEAD) | v61 authoritative | delta vs constant |
|--------|--------------------------------------|-------------------|-------------------|
| balancesPacked (root) | 7 (`claimableWinnings`) | **7** | 0 (root unmoved; SEMANTIC change only) |
| mintPacked_ | 10 | **9** | −1 |
| rngWordByDay | 11 | **10** | −1 |
| _subOf | 65 | **62** | −3 |
| _subscribers | 67 | **64** | −3 |
| _subscriberIndex | 68 | **65** | −3 |
| _subCursor | 69 | **66** | −3 |
| lootboxEthBase | 23 | **22** | −1 |
| lootboxRngPacked | 38 | **36** | −2 |
| lootboxRngWordByIndex | 39 | **37** | −2 |
| degeneretteBets | 45 | **43** | −2 |
| degeneretteBetNonce | 46 | **44** | −2 |

The `claimablePool` (slot 1 off 16), `prizePoolsPacked` (slot 2), `prizePoolPendingPacked`
(slot 11), and `PRIZE_POOLS_SLOT=2` (KeeperResolveBet) are all UNSHIFTED — confirmed authoritative.

**Conclusion:** the balances mapping ROOT did not move (still slot 7), so the redemption
harnesses' slot-7 pokes need only the SEMANTIC fix (write the low-128 half). The post-balances
gas-harness symbols must be set to the §2 authoritative values (not a uniform delta). The
plan's "-1" holds ONLY for the symbols immediately after the removed mapping (`mintPacked_`,
`rngWordByDay`) and only relative to the pre-376 tree — not relative to the already-stale
harness constants.

## 4. Per-harness recalibration ledger

Classification:
- **Game-resident** = `vm.store(address(game), …)` → AFFECTED by the fold → recalibrate.
- **sDGNRS-resident** = `vm.store(address(sdgnrs), …)` → UNAFFECTED → leave byte-identical.

| Harness | Owner plan | Game-resident pokes | Action |
|---------|-----------|---------------------|--------|
| `test/fuzz/StorageFoundation.t.sol` | **378-01 (this)** | slot-0 bit offsets in `testSlot0FieldOffsets` (224/232/208) | **Recalibrate** offsets to 208/216/192 (off 26/27/24). slot 2 / slot 11 asserts already authoritative — UNCHANGED. |
| `test/fuzz/StakedStonkRedemption.t.sol` | **378-01 (this)** | `keccak256(abi.encode(sdgnrs, uint256(7)))` on `address(game)` (7 sites) + slot 1 upper-128 | **Semantic**: root slot 7 is correct; write the LOW-128 half only (preserve afking high half). slot 1 poke unchanged. sDGNRS slots (10/7/11) UNCHANGED. |
| `test/fuzz/RedemptionGas.t.sol` | **378-01 (this)** | setUp slot-7 claimable + slot 1 upper-128 | **Semantic**: low-128 write at slot 7; slot 1 unchanged. |
| `test/fuzz/RedemptionStethFallback.t.sol` | **378-01 (this)** | `GAME_CLAIMABLE_SLOT=7` + `GAME_SLOT1=1` | **Semantic**: `_setGameClaimableSdgnrs` writes low-128 half at slot 7; `_setGameClaimablePool` unchanged (slot 1 upper-128). |
| `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` | **378-01 (this)** | NONE (all slots read `address(sdgnrs)`) | **No change** — all pokes are sDGNRS-resident. Any red here is class-(b)/(c), carried to 378-03. |
| `test/gas/V56AfkingGasMarginal.t.sol` | 378-02 | SUBOF=65→**62**, SUBSCRIBERS=67→**64**, SUBCURSOR=69→**66**, MINTPACKED=10→**9**, RNG_WORD_BY_DAY=11→**10** | 378-02 applies. (Sub field byte-offsets within the 1-slot Sub are layout-internal; re-verify against §2 if a field read mis-resolves.) |
| `test/gas/SweepPerPlayerWorstCaseGas.t.sol` | 378-02 | SUBOF=65→**62**, SUBSCRIBERS=67→**64**, SUBSCRIBER_INDEX=68→**65**, MINTPACKED=10→**9** | 378-02 applies. |
| `test/gas/RouterWorstCaseGas.t.sol` | 378-02 | SUBOF=65→**62**, SUBSCRIBERS=67→**64**, SUBSCRIBER_INDEX=68→**65**, SUBCURSOR=69→**66**, RNG_WORD_BY_DAY=11→**10**, MINTPACKED=10→**9** | 378-02 applies. |
| `test/gas/KeeperResolveBetWorstCaseGas.t.sol` | 378-02 | LOOTBOX_RNG_PACKED=38→**36**, LOOTBOX_RNG_WORD=39→**37**, DEGENERETTE_BETS=45→**43**, DEGENERETTE_BET_NONCE=46→**44**, PRIZE_POOLS=2 (unchanged) | 378-02 applies. |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | 378-02 | SUBOF=65→**62**, SUBSCRIBERS=67→**64**, RNG_WORD_BY_DAY=11→**10**, MINTPACKED=10→**9** | 378-02 applies. |
| `test/gas/KeeperLeversAndPacking.t.sol` | 378-02 | LOOTBOX_RNG_PACKED=38→**36**, LOOTBOX_RNG_WORD=39→**37**, LOOTBOX_ETH_BASE=23→**22** | 378-02 applies. |

11 slot-hardcoded harnesses total: 5 owned here (378-01), 6 owned by 378-02.

## 5. sDGNRS-resident slot constants — DO NOT TOUCH (proven unaffected)

These live on `address(sdgnrs)` (`StakedDegenerusStonk`), not `DegenerusGame`, so the Game
fold cannot move them. Left byte-identical:

- `StakedStonkRedemption.t.sol`: `SLOT_PENDING_BY_DAY=10`, `SLOT_PENDING_REDEMPTIONS=7`, `SLOT_PENDING_RESOLVE_DAY=11`
- `RedemptionInvariants.inv.t.sol`: `SLOT_PENDING_BURNIE=10`, `SLOT_SUPPLY_SNAPSHOT=13`, `SLOT_PERIOD_INDEX=14`, `SLOT_PERIOD_BURNED=15`
