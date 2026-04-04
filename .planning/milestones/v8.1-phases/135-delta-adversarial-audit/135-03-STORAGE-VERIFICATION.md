# Storage Layout Verification (v8.1 Delta)

**Date:** 2026-03-28
**Tool:** `forge inspect <Contract> storage-layout`
**Scope:** All 5 changed contracts per D-03

---

## DegenerusAdmin

```
| Name                 | Type                                                             | Slot | Offset | Bytes |
|----------------------+------------------------------------------------------------------+------+--------+-------|
| coordinator          | address                                                          | 0    | 0      | 20    |
| subscriptionId       | uint256                                                          | 1    | 0      | 32    |
| vrfKeyHash           | bytes32                                                          | 2    | 0      | 32    |
| proposalCount        | uint256                                                          | 3    | 0      | 32    |
| proposals            | mapping(uint256 => struct DegenerusAdmin.Proposal)               | 4    | 0      | 32    |
| votes                | mapping(uint256 => mapping(address => enum DegenerusAdmin.Vote)) | 5    | 0      | 32    |
| voteWeight           | mapping(uint256 => mapping(address => uint40))                   | 6    | 0      | 32    |
| activeProposalId     | mapping(address => uint256)                                      | 7    | 0      | 32    |
| voidedUpTo           | uint256                                                          | 8    | 0      | 32    |
| feedProposalCount    | uint256                                                          | 9    | 0      | 32    |
| feedProposals        | mapping(uint256 => struct DegenerusAdmin.FeedProposal)           | 10   | 0      | 32    |
| feedVotes            | mapping(uint256 => mapping(address => enum DegenerusAdmin.Vote)) | 11   | 0      | 32    |
| feedVoteWeight       | mapping(uint256 => mapping(address => uint40))                   | 12   | 0      | 32    |
| activeFeedProposalId | mapping(address => uint256)                                      | 13   | 0      | 32    |
| feedVoidedUpTo       | uint256                                                          | 14   | 0      | 32    |
| linkEthPriceFeed     | address                                                          | 15   | 0      | 20    |
```

### Analysis

**Existing VRF governance storage (slots 0-8):** Unchanged from v8.0. `coordinator` (slot 0), `subscriptionId` (slot 1), `vrfKeyHash` (slot 2), `proposalCount` (slot 3), `proposals` mapping (slot 4), `votes` (slot 5), `voteWeight` (slot 6), `activeProposalId` (slot 7), `voidedUpTo` (slot 8). No regressions.

**New feed governance storage (slots 9-15):** Seven new variables appended after existing VRF governance storage. No overlap with VRF governance slots. Feed governance uses its own parallel set of proposal/vote/weight/void tracking, avoiding cross-contamination with VRF governance state.

**Slot collision check:** No collisions. Each variable occupies its own slot (all are either 32-byte types or mappings). The `coordinator` (20 bytes at slot 0) and `linkEthPriceFeed` (20 bytes at slot 15) leave 12 unused bytes in their respective slots, but no other variables are packed into those slots.

**Gap check:** Sequential slots 0-15 with no gaps. No evidence of deleted variables.

**VERDICT: PASS**

---

## DegenerusGameLootboxModule

```
| Name                           | Type                                                   | Slot | Offset | Bytes |
|--------------------------------+--------------------------------------------------------+------+--------+-------|
| levelStartTime                 | uint48                                                 | 0    | 0      | 6     |
| dailyIdx                       | uint48                                                 | 0    | 6      | 6     |
| rngRequestTime                 | uint48                                                 | 0    | 12     | 6     |
| level                          | uint24                                                 | 0    | 18     | 3     |
| jackpotPhaseFlag               | bool                                                   | 0    | 21     | 1     |
| jackpotCounter                 | uint8                                                  | 0    | 22     | 1     |
| poolConsolidationDone          | bool                                                   | 0    | 23     | 1     |
| lastPurchaseDay                | bool                                                   | 0    | 24     | 1     |
| decWindowOpen                  | bool                                                   | 0    | 25     | 1     |
| rngLockedFlag                  | bool                                                   | 0    | 26     | 1     |
| phaseTransitionActive          | bool                                                   | 0    | 27     | 1     |
| gameOver                       | bool                                                   | 0    | 28     | 1     |
| dailyJackpotCoinTicketsPending | bool                                                   | 0    | 29     | 1     |
| dailyEthPhase                  | uint8                                                  | 0    | 30     | 1     |
| compressedJackpotFlag          | uint8                                                  | 0    | 31     | 1     |
| ...                            | (slots 1-76: game state, mappings, packed fields)      | 1-76 | ...    | ...   |
| boonPacked                     | mapping(address => struct DegenerusGameStorage.BoonPacked) | 77 | 0    | 32    |
```

(Full layout: 78 slots, slot 0 densely packed with 14 variables, slots 1-76 contain game state and mappings, slot 77 is boonPacked.)

### Analysis

**Boon storage for multi-category coexistence:** `boonPacked` at slot 77 is a mapping to `BoonPacked` struct, which is a 2-slot struct (slot0: uint256, slot1: uint256). Each boon category uses isolated bit ranges within these 2 slots:
- Slot0: coinflip tier/day, lootbox tier/day, purchase tier/day, decimator tier/day, whale tier/day fields
- Slot1: activity tier/day, deity pass tier/day, whale pass tier/day, lazy pass tier/day fields

The removal of boon exclusivity (deleted `_activeBoonCategory` and `_boonCategory` functions) did NOT change the storage layout. Those were pure application-level functions that read from `boonPacked` -- they had no storage variables of their own. The `boonPacked` struct was always designed for multi-category storage (v3.8 Phase 73).

**Slot collision check:** No collisions. Slot 0 is fully packed (32/32 bytes used). All other variables occupy their expected slots without overlap.

**Gap check:** No gaps detected. The deleted exclusivity constants (`BOON_CAT_NONE`, etc.) were compile-time constants, not storage variables -- their removal does not affect the storage layout.

**VERDICT: PASS**

---

## BurnieCoinflip

```
| Name              | Type                                                          | Slot | Offset | Bytes |
|-------------------+---------------------------------------------------------------+------+--------+-------|
| coinflipBalance   | mapping(uint48 => mapping(address => uint256))                | 0    | 0      | 32    |
| coinflipDayResult | mapping(uint48 => struct BurnieCoinflip.CoinflipDayResult)    | 1    | 0      | 32    |
| playerState       | mapping(address => struct BurnieCoinflip.PlayerCoinflipState) | 2    | 0      | 32    |
| currentBounty     | uint128                                                       | 3    | 0      | 16    |
| biggestFlipEver   | uint128                                                       | 3    | 16     | 16    |
| bountyOwedTo      | address                                                       | 4    | 0      | 20    |
| flipsClaimableDay | uint48                                                        | 4    | 20     | 6     |
| coinflipTopByDay  | mapping(uint48 => struct BurnieCoinflip.PlayerScore)          | 5    | 0      | 32    |
```

### Analysis

**Recycling bonus changes:** The changes to `_recyclingBonus` and `_depositCoinflip` modified function logic (BPS constants and rollAmount source) but did NOT add or remove any storage variables. `RECYCLE_BONUS_BPS` and `AFKING_RECYCLE_BONUS_BPS` are compile-time constants, not storage variables.

**Slot collision check:** No collisions. Slot 3 packs `currentBounty` (16 bytes, offset 0) and `biggestFlipEver` (16 bytes, offset 16) -- correct uint128+uint128 packing. Slot 4 packs `bountyOwedTo` (20 bytes, offset 0) and `flipsClaimableDay` (6 bytes, offset 20) -- correct address+uint48 packing.

**Gap check:** No gaps. Sequential slots 0-5.

**VERDICT: PASS**

---

## DegenerusStonk

```
| Name        | Type                                            | Slot | Offset | Bytes |
|-------------+-------------------------------------------------+------+--------+-------|
| totalSupply | uint256                                         | 0    | 0      | 32    |
| balanceOf   | mapping(address => uint256)                     | 1    | 0      | 32    |
| allowance   | mapping(address => mapping(address => uint256)) | 2    | 0      | 32    |
```

### Analysis

**ERC-20 Approval event addition:** The `transferFrom` change only added an `emit Approval(...)` -- no storage variable changes. The `allowance` mapping at slot 2 is the same as before.

**Ownership model change:** The `unwrapTo` ownership check moved from `ContractAddresses.CREATOR` (a compile-time constant) to `vault.isVaultOwner(msg.sender)` (an external view call). Neither approach uses storage variables in DegenerusStonk -- the old approach read a constant, the new approach calls an external contract. No storage impact.

**Slot collision check:** No collisions. Three clean slots (0-2).

**Gap check:** No gaps. Minimal 3-slot layout unchanged from v8.0.

**VERDICT: PASS**

---

## DegenerusDeityPass

```
| Name                  | Type                        | Slot | Offset | Bytes |
|-----------------------+-----------------------------+------+--------+-------|
| _owners               | mapping(uint256 => address) | 0    | 0      | 32    |
| _balances             | mapping(address => uint256) | 1    | 0      | 32    |
| renderer              | address                     | 2    | 0      | 20    |
| _outlineColor         | string                      | 3    | 0      | 32    |
| _backgroundColor      | string                      | 4    | 0      | 32    |
| _nonCryptoSymbolColor | string                      | 5    | 0      | 32    |
```

### Analysis

**Ownership model change:** The `_contractOwner` storage variable was removed. Previously the layout was:
- Slot 0: `_owners` mapping
- Slot 1: `_balances` mapping
- Slot 2: `_contractOwner` (address)
- Slot 3: `renderer` (address)
- Slot 4-6: color strings

Now the layout is:
- Slot 0: `_owners` mapping
- Slot 1: `_balances` mapping
- Slot 2: `renderer` (address) -- shifted up from slot 3
- Slot 3-5: color strings -- shifted up from slots 4-6

**Storage layout shift:** `renderer` moved from slot 3 to slot 2, and the color strings shifted accordingly. This IS a storage layout change. However, per the protocol's deployment model (fresh CREATE deployment via nonce prediction, no proxy upgrades), this is a non-issue. The contract is deployed fresh with empty storage, so there is no state to corrupt from slot reordering.

**Slot collision check:** No collisions. `renderer` at slot 2 occupies 20 bytes; the remaining 12 bytes are unused (no other variable packed into that slot). All string variables are in their own slots.

**Gap check:** No gaps in the new layout. Sequential slots 0-5.

**Finding DP-01 (INFO) confirmed:** Storage shift is real but non-exploitable due to fresh deployment model.

**VERDICT: PASS**

---

## Summary

| Contract | Slots | Collisions | Gaps | Layout Shift | VERDICT |
|----------|-------|------------|------|--------------|---------|
| DegenerusAdmin | 16 (0-15) | 0 | 0 | No -- new slots appended | **PASS** |
| DegenerusGameLootboxModule | 78 (0-77) | 0 | 0 | No -- deleted code was constants, not storage | **PASS** |
| BurnieCoinflip | 6 (0-5) | 0 | 0 | No -- changes were to function logic, not storage | **PASS** |
| DegenerusStonk | 3 (0-2) | 0 | 0 | No -- changes were event emission and external calls | **PASS** |
| DegenerusDeityPass | 6 (0-5) | 0 | 0 | Yes -- _contractOwner removed, renderer shifted (non-exploitable: fresh deploy) | **PASS** |

**All 5 contracts PASS storage layout verification.** Zero slot collisions. Zero storage regressions. One layout shift (DegenerusDeityPass) confirmed non-exploitable per protocol's fresh deployment model.
