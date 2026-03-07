# DegenerusGameBoonModule.sol -- Function-Level Audit

**Contract:** DegenerusGameBoonModule
**File:** contracts/modules/DegenerusGameBoonModule.sol
**Lines:** 359
**Solidity:** 0.8.34
**Inherits:** DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame (and nested delegatecall from LootboxModule)
**Audit date:** 2026-03-07

## Summary

Handles boon consumption for coinflip, purchase, and decimator boosts. Provides expired boon cleanup via `checkAndClearExpiredBoon` (called during lootbox resolution from LootboxModule via nested delegatecall). Applies activity boons to player mint stats and quest streaks. All 5 functions are external. Deity-granted boons expire when `deityDay != currentDay` (same-day only). Lootbox-rolled boons expire after a type-specific number of days (`stampDay + N`). Decimator boost is unique: lootbox-rolled variant has no expiry (intentional -- no stamp day variable exists).

**Constants defined:**

| Constant | Value | Usage |
|----------|-------|-------|
| `COINFLIP_BOON_EXPIRY_DAYS` | 2 | Coinflip boon and activity boon lootbox-rolled expiry |
| `LOOTBOX_BOOST_EXPIRY_DAYS` | 2 | Lootbox boost (5%/15%/25%) lootbox-rolled expiry |
| `PURCHASE_BOOST_EXPIRY_DAYS` | 4 | Purchase boost lootbox-rolled expiry |
| `DEITY_PASS_BOON_EXPIRY_DAYS` | 4 | Deity pass boon lootbox-rolled expiry |
| `quests` | `IDegenerusQuests(ContractAddresses.QUESTS)` | External quest contract for streak bonus |

## Function Audit

### `consumeCoinflipBoon(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeCoinflipBoon(address player) external returns (uint16 boonBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to consume boon for |
| **Returns** | `boonBps` (uint16): The bonus in basis points (0 if no boon, 500/1000/2500 otherwise) |

**State Reads:**
- `deityCoinflipBoonDay[player]` -- deity-granted day stamp
- `coinflipBoonDay[player]` -- lootbox-rolled day stamp
- `coinflipBoonBps[player]` -- boon value in BPS

**State Writes:**
- `coinflipBoonBps[player] = 0` -- clears boon value
- `coinflipBoonDay[player] = 0` -- clears stamp day
- `deityCoinflipBoonDay[player] = 0` -- clears deity day

**Callers:**
- `DegenerusGame.consumeCoinflipBoon(player)` via delegatecall (access-restricted to COIN or COINFLIP contracts)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None. This function does not move ETH.

**Logic Flow:**
1. Early return 0 if `player == address(0)`
2. Read `currentDay` from `_simulatedDayIndex()`
3. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- deity-granted boon expired. Clear all 3 variables, return 0.
4. **Lootbox expiry check:** If `stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS (2)` -- lootbox-rolled boon expired. Clear all 3, return 0.
5. Read `boonBps`. If 0, early return 0.
6. Clear all 3 variables, return `boonBps` (consumed successfully).

**Invariants:**
- After function returns, all 3 storage variables for this player are always zeroed (boon is single-use).
- If boon is expired (deity day mismatch or lootbox day + 2 exceeded), return value is 0.
- address(0) never has boons consumed.

**NatSpec Accuracy:** Accurate. NatSpec says "Consume a player's coinflip boon and return the bonus BPS" with values "0 if no boon, 500/1000/2500 otherwise". The code returns exactly those possible values from `coinflipBoonBps[player]` which are set by LootboxModule at those tiers.

**Gas Flags:**
- On the expired-deity path (line 42-46), the function writes all 3 storage slots even if some were already 0. This is acceptable since SSTOREs to 0 get gas refund and the code prioritizes simplicity.
- The function always clears `deityCoinflipBoonDay` even for lootbox-rolled boons where it's already 0. Minor redundancy but no correctness impact.

**Verdict:** CORRECT

---

### `consumePurchaseBoost(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumePurchaseBoost(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to consume boost for |
| **Returns** | `boostBps` (uint16): The bonus in basis points (0 if no boost, 500/1500/2500 otherwise) |

**State Reads:**
- `deityPurchaseBoostDay[player]` -- deity-granted day stamp
- `purchaseBoostDay[player]` -- lootbox-rolled day stamp
- `purchaseBoostBps[player]` -- boost value in BPS

**State Writes:**
- `purchaseBoostBps[player] = 0` -- clears boost value
- `purchaseBoostDay[player] = 0` -- clears stamp day
- `deityPurchaseBoostDay[player] = 0` -- clears deity day

**Callers:**
- `DegenerusGame.consumePurchaseBoost(player)` via delegatecall (access-restricted to `address(this)` -- i.e., self-call from delegate modules)
- `DegenerusGameMintModule.purchase()` calls `IDegenerusGame(address(this)).consumePurchaseBoost(buyer)` (line 831)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None.

**Logic Flow:**
1. Early return 0 if `player == address(0)`
2. Read `currentDay` from `_simulatedDayIndex()`
3. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- expired. Clear all 3, return 0.
4. **Lootbox expiry check:** If `stampDay > 0 && currentDay > stampDay + PURCHASE_BOOST_EXPIRY_DAYS (4)` -- expired. Clear all 3, return 0.
5. Read `boostBps`. If 0, early return 0.
6. Clear all 3 variables, return `boostBps` (consumed successfully).

**Invariants:**
- Identical pattern to `consumeCoinflipBoon` but with 4-day expiry instead of 2-day.
- After function returns, all 3 storage variables for this player are zeroed.
- Single-use consumption.

**NatSpec Accuracy:** Accurate. NatSpec says "Consume a player's purchase boost and return the bonus BPS" with values "0 if no boost, 500/1500/2500 otherwise". Matches the tiers set in LootboxModule.

**Gas Flags:**
- Same minor redundancy as `consumeCoinflipBoon`: always clears `deityPurchaseBoostDay` even for lootbox-rolled boons where it's 0. Acceptable.

**Verdict:** CORRECT

---

### `consumeDecimatorBoost(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeDecimatorBoost(address player) external returns (uint16 boostBps)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to consume boost for |
| **Returns** | `boostBps` (uint16): The bonus in basis points (0 if no boost, 1000/2500/5000 otherwise) |

**State Reads:**
- `deityDecimatorBoostDay[player]` -- deity-granted day stamp
- `decimatorBoostBps[player]` -- boost value in BPS

**State Writes:**
- `decimatorBoostBps[player] = 0` -- clears boost value
- `deityDecimatorBoostDay[player] = 0` -- clears deity day

**Callers:**
- `DegenerusGame.consumeDecimatorBoon(player)` via delegatecall (access-restricted to COIN contract only)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None.

**Logic Flow:**
1. Early return 0 if `player == address(0)`
2. Read `currentDay` from `_simulatedDayIndex()`
3. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- deity-granted boon expired. Clear 2 variables, return 0.
4. Read `boostBps`. If 0, early return 0.
5. Clear 2 variables, return `boostBps` (consumed successfully).

**Key Difference: No Stamp Day Check**

Unlike `consumeCoinflipBoon` and `consumePurchaseBoost`, this function has **no lootbox stamp day expiry check**. This is **intentional by design**:

1. There is no `decimatorBoostDay` storage variable in `DegenerusGameStorage`. The storage comment for `decimatorBoostBps` explicitly says: "one-time, **no expiry**" (line 781).
2. In `LootboxModule._applyBoon()` (line 1435): `deityDecimatorBoostDay[player] = isDeity ? day : uint48(0)` -- lootbox-rolled decimator boosts set the deity day to 0, and no stamp day is set.
3. Therefore: lootbox-rolled decimator boosts persist indefinitely until consumed. Only deity-granted decimator boosts expire (when `deityDay != currentDay`).

This makes game-design sense: decimator boosts encourage BURNIE burning (deflationary action), so giving them no expiry incentivizes players to use them rather than pressuring them with a time window.

**Invariants:**
- After function returns, both `decimatorBoostBps` and `deityDecimatorBoostDay` are zeroed.
- Only 2 storage variables (vs 3 for coinflip/purchase) since there is no stamp day variable.
- Single-use consumption.

**NatSpec Accuracy:** Accurate. NatSpec says "Consume a player's decimator boost and return the bonus BPS" with values "0 if no boost, 1000/2500/5000 otherwise".

**Gas Flags:** None. Simpler than the other consume functions due to no stamp day check.

**Verdict:** CORRECT

---

### `checkAndClearExpiredBoon(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function checkAndClearExpiredBoon(address player) external returns (bool hasAnyBoon)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): The player address to check and clear expired boons for |
| **Returns** | `hasAnyBoon` (bool): True if the player has at least one active (non-expired) boon |

**State Reads (all per-player):**
- `coinflipBoonBps[player]` -- coinflip boon value
- `deityCoinflipBoonDay[player]` -- deity coinflip day
- `coinflipBoonDay[player]` -- lootbox coinflip stamp day
- `lootboxBoon25Active[player]` -- 25% lootbox boost flag
- `deityLootboxBoon25Day[player]` -- deity 25% lootbox day
- `lootboxBoon25Day[player]` -- lootbox 25% stamp day
- `lootboxBoon15Active[player]` -- 15% lootbox boost flag
- `deityLootboxBoon15Day[player]` -- deity 15% lootbox day
- `lootboxBoon15Day[player]` -- lootbox 15% stamp day
- `lootboxBoon5Active[player]` -- 5% lootbox boost flag
- `deityLootboxBoon5Day[player]` -- deity 5% lootbox day
- `lootboxBoon5Day[player]` -- lootbox 5% stamp day
- `purchaseBoostBps[player]` -- purchase boost value
- `deityPurchaseBoostDay[player]` -- deity purchase day
- `purchaseBoostDay[player]` -- lootbox purchase stamp day
- `decimatorBoostBps[player]` -- decimator boost value
- `deityDecimatorBoostDay[player]` -- deity decimator day
- `whaleBoonDay[player]` -- whale boon day
- `deityWhaleBoonDay[player]` -- deity whale day
- `whaleBoonDiscountBps[player]` -- whale boon discount (read for clearing only)
- `lazyPassBoonDay[player]` -- lazy pass boon day
- `deityLazyPassBoonDay[player]` -- deity lazy pass day
- `lazyPassBoonDiscountBps[player]` -- lazy pass discount (read for clearing only)
- `deityPassBoonTier[player]` -- deity pass boon tier
- `deityDeityPassBoonDay[player]` -- deity-granted deity pass day
- `deityPassBoonDay[player]` -- lootbox deity pass stamp day
- `activityBoonPending[player]` -- pending activity boon amount
- `deityActivityBoonDay[player]` -- deity activity day
- `activityBoonDay[player]` -- lootbox activity stamp day

**State Writes (conditional -- only when expired):**
- Coinflip: `coinflipBoonBps`, `coinflipBoonDay`, `deityCoinflipBoonDay` set to 0
- Lootbox 25%: `lootboxBoon25Active` set to false, `deityLootboxBoon25Day` set to 0; note: `lootboxBoon25Day` is NOT cleared (only deity day is zeroed)
- Lootbox 15%: `lootboxBoon15Active` set to false, `deityLootboxBoon15Day` set to 0; note: `lootboxBoon15Day` is NOT cleared
- Lootbox 5%: `lootboxBoon5Active` set to false, `deityLootboxBoon5Day` set to 0; note: `lootboxBoon5Day` is NOT cleared
- Purchase: `purchaseBoostBps`, `purchaseBoostDay`, `deityPurchaseBoostDay` set to 0
- Decimator: `decimatorBoostBps`, `deityDecimatorBoostDay` set to 0 (deity-expired only)
- Whale: `whaleBoonDay`, `deityWhaleBoonDay`, `whaleBoonDiscountBps` set to 0
- Lazy pass: `lazyPassBoonDay`, `lazyPassBoonDiscountBps`, `deityLazyPassBoonDay` set to 0
- Deity pass: `deityPassBoonTier`, `deityPassBoonDay`, `deityDeityPassBoonDay` set to 0
- Activity: `activityBoonPending`, `activityBoonDay`, `deityActivityBoonDay` set to 0

**Callers:**
- `DegenerusGameLootboxModule` via nested delegatecall (line 1002): `abi.encodeWithSelector(IDegenerusGameBoonModule.checkAndClearExpiredBoon.selector, player)` -- called during lootbox resolution to determine if player has any active boon (for `hasBoon` flag)

**Callees:** None (reads `_simulatedDayIndex()` from DegenerusGameStorage)

**ETH Flow:** None.

**Logic Flow (10 boon type blocks):**

The function processes each boon type sequentially, checking expiry and clearing if expired. For each type, local variables shadow the storage values to track whether the boon survived expiry checks. The final return aggregates all local variables with OR.

**Block 1: Coinflip Boon** (lines 117-134)
- Skip if `coinflipBps == 0`
- Deity expiry: `deityDay != 0 && deityDay != currentDay` -> clear all 3, local = 0
- Lootbox expiry: `stampDay > 0 && currentDay > stampDay + 2` -> clear all 3, local = 0

**Block 2: Lootbox Boost 25%** (lines 136-156)
- If active: deity expiry or lootbox expiry -> deactivate + clear deity day
- If NOT active but `deityLootboxBoon25Day != 0 && deityDay != currentDay`: clean up stale deity day
- Note: The `else` block (lines 151-156) handles a corner case where the active flag is false but a stale deity day entry remains. This is defensive cleanup.

**Block 3: Lootbox Boost 15%** (lines 158-178)
- Identical pattern to Block 2.

**Block 4: Lootbox Boost 5%** (lines 180-200)
- Identical pattern to Block 2.

**Block 5: Purchase Boost** (lines 202-219)
- Skip if `purchaseBps == 0`
- Deity expiry: same pattern as coinflip
- Lootbox expiry: `stampDay > 0 && currentDay > stampDay + 4`

**Block 6: Decimator Boost** (lines 221-229)
- Skip if `decimatorBps == 0`
- **Only deity expiry check** (no stamp day exists for decimator boost)
- If `deityDay != 0 && deityDay != currentDay`: clear `decimatorBoostBps` and `deityDecimatorBoostDay`
- No lootbox expiry block -- consistent with storage design (decimator boost has no expiry for lootbox-rolled)

**Block 7: Whale Boon** (lines 231-238)
- **No active flag check** -- uses `whaleBoonDay` as the indicator
- Deity expiry: `deityWhaleDay != 0 && deityWhaleDay != currentDay` -> clear day, deity day, and discount BPS
- NOTE: No lootbox stamp expiry here. The whale boon expiry is handled in WhaleModule when consumed. This function only handles deity expiry for whale boons.

**Block 8: Lazy Pass Boon** (lines 239-253)
- Guard: `lazyDay != 0`
- Deity expiry: `deityDay != 0 && deityDay != currentDay` -> clear day, discount, deity day
- Lootbox expiry: `currentDay > lazyDay + 4` (hardcoded 4 days, matches `DEITY_PASS_BOON_EXPIRY_DAYS` value but not using the constant -- acceptable since lazy pass has its own semantics)

**Block 9: Deity Pass Boon** (lines 255-273)
- Guard: `deityTier != 0`
- **Different deity expiry logic:** If `deityDay != 0` (deity-granted), check `currentDay > deityDay` (expires AFTER the deity day, not on mismatch). This means deity-granted deity pass boons last until end of their granted day (inclusive of that day).
- If `deityDay == 0` (lootbox-rolled): check `stampDay > 0 && currentDay > stampDay + DEITY_PASS_BOON_EXPIRY_DAYS (4)`

**Block 10: Activity Boon** (lines 275-292)
- Guard: `activityPending != 0`
- Deity expiry: standard `deityDay != 0 && deityDay != currentDay`
- Lootbox expiry: `stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS (2)` -- reuses the 2-day coinflip constant

**Return value (lines 294-303):**
```solidity
return (whaleDay != 0 || lazyDay != 0 || coinflipBps != 0 || lootbox25 || lootbox15 || lootbox5 || purchaseBps != 0 || decimatorBps != 0 || activityPending != 0 || deityTier != 0);
```
Returns true if ANY boon type survived the expiry checks.

**Invariants:**
- Every expired boon is cleared from storage. Non-expired boons are left untouched.
- The return value accurately reflects whether any active boon remains.
- The function is idempotent: calling it twice produces the same result (expired boons are already cleared on first call).
- No boon is consumed (only expired ones are cleared).

**NatSpec Accuracy:** Accurate. NatSpec says "Clear all expired boons for a player and report if any remain active." and "Called via nested delegatecall from LootboxModule during lootbox resolution." Both are correct.

**Gas Flags:**
- **Lootbox boost blocks do not clear `lootboxBoonXXDay` on expiry** (only clear the active flag and deity day). The stale stamp day remains in storage. This is harmless because the active flag is the primary indicator, but it means a dead stamp day occupies storage. Minor gas inefficiency (missed refund on clearing the day), but no correctness issue.
- **Whale boon block has no lootbox stamp expiry logic** -- whale boon lootbox expiry is handled in WhaleModule consumption. This is consistent with the design (BoonModule only does deity-expiry cleanup for whale boons during lootbox resolution).
- The function performs up to 30 SLOADs and up to 30 SSTOREs in the worst case (all boon types active and all expired). This is expensive but acceptable since it's called once per lootbox resolution and cleans up all boon state.

**Verdict:** CORRECT

---

### `consumeActivityBoon(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function consumeActivityBoon(address player) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Player address |
| **Returns** | None (void) |

**State Reads:**
- `activityBoonPending[player]` -- pending activity boon amount (uint24)
- `deityActivityBoonDay[player]` -- deity-granted day stamp
- `activityBoonDay[player]` -- lootbox-rolled stamp day
- `mintPacked_[player]` -- bit-packed mint data (reads LEVEL_COUNT_SHIFT field)

**State Writes:**
- `activityBoonPending[player] = 0` -- clears pending amount
- `activityBoonDay[player] = 0` -- clears stamp day
- `deityActivityBoonDay[player] = 0` -- clears deity day
- `mintPacked_[player]` -- updates LEVEL_COUNT field via `BitPackingLib.setPacked()` (only if changed)

**Callers:**
- `DegenerusGameLootboxModule` via nested delegatecall (line 945): `abi.encodeWithSelector(IDegenerusGameBoonModule.consumeActivityBoon.selector, player)` -- called during lootbox resolution

**Callees:**
- `quests.awardQuestStreakBonus(player, bonus, currentDay)` -- external call to `IDegenerusQuests` at `ContractAddresses.QUESTS` to award quest streak bonus days
- `BitPackingLib.setPacked()` -- library call for bit-packed field manipulation

**ETH Flow:** None.

**Logic Flow:**
1. Read `pending = activityBoonPending[player]`. If 0 or `player == address(0)`, early return.
2. **Deity expiry check:** If `deityDay != 0 && deityDay != currentDay` -- expired. Clear all 3 activity boon vars, return (boon wasted).
3. **Lootbox expiry check:** If `stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS (2)` -- expired. Clear all 3, return.
4. **Consume the boon:** Clear all 3 activity boon vars.
5. **Update mintPacked_:** Read `prevData`, extract `levelCount` (24-bit field at LEVEL_COUNT_SHIFT=24). Add `pending` to `levelCount`, saturating at `uint24.max` (16,777,215). Write back via `BitPackingLib.setPacked()` only if data changed.
6. **Award quest streak:** Downcast `pending` to uint16 (saturating at `uint16.max` = 65,535). If `currentDay != 0 && bonus != 0`, call `quests.awardQuestStreakBonus(player, bonus, currentDay)`.

**Saturation Behavior:**
- `levelCount` saturates at `uint24.max` (16,777,215). This prevents overflow in the 24-bit packed field.
- `bonus` for quest streak saturates at `uint16.max` (65,535). This matches the `awardQuestStreakBonus` parameter type (`uint16 amount`).
- If `pending > 65,535`, the level count gets the full `pending` amount (up to uint24.max) but the quest streak bonus is capped at 65,535. This discrepancy is acceptable since quest streak amounts that large are unrealistic in practice.

**Invariants:**
- After function returns, `activityBoonPending`, `activityBoonDay`, and `deityActivityBoonDay` are always zeroed (consumed or expired).
- `mintPacked_` levelCount can only increase or stay the same (never decrease).
- External call to `quests.awardQuestStreakBonus` is the only external interaction in the entire module.
- The `currentDay != 0` guard on the quest call prevents calling during day 0 (genesis). This is a defensive check since `_simulatedDayIndex()` should never return 0 in practice.

**NatSpec Accuracy:** Mostly accurate. NatSpec says "Consume a pending activity boon and apply it to player stats." and "Called via nested delegatecall from LootboxModule during lootbox resolution." Both correct. However, the NatSpec does not mention the quest streak bonus side effect -- minor omission but not a discrepancy.

**Gas Flags:**
- The `if (data != prevData)` guard (line 350) avoids an unnecessary SSTORE when the level count doesn't change (e.g., if pending is 0, which is already guarded earlier). Good optimization.
- The external call to `quests.awardQuestStreakBonus` adds ~2600 gas for the cross-contract call overhead. Acceptable.

**Verdict:** CORRECT

---

## Boon Expiry Matrix

| Boon Type | Storage Variables | Lootbox-Rolled Expiry | Deity-Granted Expiry | Consume Function |
|-----------|-------------------|----------------------|---------------------|------------------|
| Coinflip Boost | `coinflipBoonBps`, `coinflipBoonDay`, `deityCoinflipBoonDay` | stampDay + 2 days | deityDay != currentDay (same-day only) | `consumeCoinflipBoon` |
| Purchase Boost | `purchaseBoostBps`, `purchaseBoostDay`, `deityPurchaseBoostDay` | stampDay + 4 days | deityDay != currentDay (same-day only) | `consumePurchaseBoost` |
| Decimator Boost | `decimatorBoostBps`, `deityDecimatorBoostDay` | **No expiry** (no stamp day variable exists) | deityDay != currentDay (same-day only) | `consumeDecimatorBoost` |
| Lootbox Boost 25% | `lootboxBoon25Active`, `lootboxBoon25Day`, `deityLootboxBoon25Day` | stampDay + 2 days | deityDay != currentDay (same-day only) | N/A (cleared in `checkAndClearExpiredBoon`, consumed by LootboxModule) |
| Lootbox Boost 15% | `lootboxBoon15Active`, `lootboxBoon15Day`, `deityLootboxBoon15Day` | stampDay + 2 days | deityDay != currentDay (same-day only) | N/A (cleared in `checkAndClearExpiredBoon`, consumed by LootboxModule) |
| Lootbox Boost 5% | `lootboxBoon5Active`, `lootboxBoon5Day`, `deityLootboxBoon5Day` | stampDay + 2 days | deityDay != currentDay (same-day only) | N/A (cleared in `checkAndClearExpiredBoon`, consumed by LootboxModule) |
| Whale Boon | `whaleBoonDay`, `deityWhaleBoonDay`, `whaleBoonDiscountBps` | No lootbox expiry in BoonModule (handled in WhaleModule) | deityWhaleDay != currentDay (same-day only) | N/A (consumed in WhaleModule) |
| Lazy Pass Boon | `lazyPassBoonDay`, `lazyPassBoonDiscountBps`, `deityLazyPassBoonDay` | lazyDay + 4 days (hardcoded) | deityDay != currentDay (same-day only) | N/A (consumed in WhaleModule) |
| Deity Pass Boon | `deityPassBoonTier`, `deityPassBoonDay`, `deityDeityPassBoonDay` | stampDay + 4 days (`DEITY_PASS_BOON_EXPIRY_DAYS`) | currentDay > deityDay (inclusive -- lasts through granted day) | N/A (consumed in WhaleModule) |
| Activity Boon | `activityBoonPending`, `activityBoonDay`, `deityActivityBoonDay` | stampDay + 2 days (`COINFLIP_BOON_EXPIRY_DAYS`) | deityDay != currentDay (same-day only) | `consumeActivityBoon` |

### Expiry Pattern Summary

**Standard deity expiry** (8 of 10 boon types): `deityDay != 0 && deityDay != currentDay` -- boon is valid only on the day it was granted. Expires at day rollover.

**Special deity expiry** (deity pass boon only): `currentDay > deityDay` -- boon is valid through the end of the granted day (inclusive). Uses `>` instead of `!=`.

**Lootbox expiry tiers:**
- 2-day: Coinflip, Lootbox boosts (5/15/25%), Activity boon
- 4-day: Purchase boost, Lazy pass, Deity pass
- No expiry: Decimator boost (intentional -- incentivizes deflationary BURNIE burns)
- N/A: Whale boon (expiry handled in WhaleModule, not BoonModule)

## Storage Mutation Map

| Function | Variables Written | Write Type | Condition |
|----------|------------------|------------|-----------|
| `consumeCoinflipBoon` | `coinflipBoonBps`, `coinflipBoonDay`, `deityCoinflipBoonDay` | delete (set to 0) | Always (on any path except address(0) early return) |
| `consumePurchaseBoost` | `purchaseBoostBps`, `purchaseBoostDay`, `deityPurchaseBoostDay` | delete (set to 0) | Always (on any path except address(0) early return) |
| `consumeDecimatorBoost` | `decimatorBoostBps`, `deityDecimatorBoostDay` | delete (set to 0) | Always (on any path except address(0) early return) |
| `checkAndClearExpiredBoon` | Up to 30 boon storage variables | conditional delete (set to 0/false) | Only expired boons are cleared |
| `consumeActivityBoon` | `activityBoonPending`, `activityBoonDay`, `deityActivityBoonDay` | delete (set to 0) | Always when pending > 0 |
| `consumeActivityBoon` | `mintPacked_[player]` | update (bit-packed LEVEL_COUNT field) | Only if data changed |

### checkAndClearExpiredBoon Detailed Mutation Map

| Boon Block | Variables Cleared on Expiry | Variables NOT Cleared |
|------------|----------------------------|----------------------|
| Coinflip | `coinflipBoonBps`, `coinflipBoonDay`, `deityCoinflipBoonDay` | -- |
| Lootbox 25% | `lootboxBoon25Active` (->false), `deityLootboxBoon25Day` | `lootboxBoon25Day` (stale day remains) |
| Lootbox 15% | `lootboxBoon15Active` (->false), `deityLootboxBoon15Day` | `lootboxBoon15Day` (stale day remains) |
| Lootbox 5% | `lootboxBoon5Active` (->false), `deityLootboxBoon5Day` | `lootboxBoon5Day` (stale day remains) |
| Purchase | `purchaseBoostBps`, `purchaseBoostDay`, `deityPurchaseBoostDay` | -- |
| Decimator | `decimatorBoostBps`, `deityDecimatorBoostDay` | -- (deity expiry only) |
| Whale | `whaleBoonDay`, `deityWhaleBoonDay`, `whaleBoonDiscountBps` | -- (deity expiry only) |
| Lazy Pass | `lazyPassBoonDay`, `lazyPassBoonDiscountBps`, `deityLazyPassBoonDay` | -- |
| Deity Pass | `deityPassBoonTier`, `deityPassBoonDay`, `deityDeityPassBoonDay` | -- |
| Activity | `activityBoonPending`, `activityBoonDay`, `deityActivityBoonDay` | -- |

**Stale lootboxBoonXXDay note:** When lootbox boost boons expire, the `lootboxBoonXXDay` stamp day is NOT cleared (only the active flag and deity day are zeroed). This is harmless because the `active` flag is the authoritative indicator, but means up to 3 stale uint48 values may persist in storage per player. Gas cost: ~3 missed SSTORE-to-zero refunds per player per lootbox resolution. Correctness impact: none.

## ETH Mutation Path Map

| Path | Source | Destination | Trigger | Function |
|------|--------|-------------|---------|----------|
| (none) | -- | -- | This module does not move ETH directly | -- |

BoonModule does not directly move ETH. It modifies boon state that affects ETH flows in other modules:
- **Coinflip boost** -> affects coinflip stake bonus in BurnieCoinflip
- **Purchase boost** -> affects ticket purchase bonus in MintModule
- **Decimator boost** -> affects BURNIE burn bonus in DegenerusStonk (via COIN)
- **Whale/Lazy/Deity pass boons** -> affect pricing discounts in WhaleModule
- **Activity boon** -> affects level count stats and quest streaks (no ETH)

## External Call Map

| Function | Target | Call Type | Method | Gas Risk |
|----------|--------|-----------|--------|----------|
| `consumeActivityBoon` | `ContractAddresses.QUESTS` | External call | `awardQuestStreakBonus(player, bonus, currentDay)` | Low (~2600 gas overhead) |

This is the **only external call** in the entire BoonModule. All other functions are pure storage manipulation.

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | -- |
| CONCERN | 0 | -- |
| GAS | 3 | See below |
| CORRECT | 5 | All 5 functions verified correct |

### GAS-01: Redundant SSTORE-to-zero on deity day for lootbox-rolled boons

**Functions:** `consumeCoinflipBoon`, `consumePurchaseBoost`
**Description:** These functions always clear `deityXXXDay[player] = 0` even when the boon was lootbox-rolled (deity day is already 0). The SSTORE to 0 when already 0 costs ~100 gas (warm slot, no-op). Negligible impact.
**Recommendation:** None required. Code clarity outweighs micro-optimization.

### GAS-02: Stale lootboxBoonXXDay not cleared on expiry

**Function:** `checkAndClearExpiredBoon`
**Description:** When lootbox boost boons (5%/15%/25%) expire, the `lootboxBoonXXDay` stamp day is not zeroed. This misses a ~4,800 gas refund per stale variable (3 possible = ~14,400 gas total). The active flag being authoritative means this has zero correctness impact.
**Recommendation:** Low priority. Could add `lootboxBoonXXDay[player] = 0` to each expiry block for the gas refund, but the code is already 190 lines.

### GAS-03: Whale boon deity-only expiry in BoonModule

**Function:** `checkAndClearExpiredBoon`
**Description:** Whale boon lootbox expiry is handled in WhaleModule during consumption, not in BoonModule during cleanup. This means an expired (but not deity-expired) whale boon will persist in storage until next whale bundle purchase attempt. No correctness issue since WhaleModule checks expiry on use. The `checkAndClearExpiredBoon` return value may indicate `hasAnyBoon = true` for an expired (but not yet cleaned up) whale boon, causing the `hasBoon` flag to persist longer than necessary. This is a minor UX/gas concern only.
**Recommendation:** None required. Current design keeps WhaleModule's expiry logic self-contained.

## Cross-Module Integration Points

| This Module Function | Called By | Call Pattern | Notes |
|---------------------|-----------|-------------|-------|
| `consumeCoinflipBoon` | `DegenerusGame` -> `BurnieCoinflip.performFlip()` | delegatecall | Access: COIN or COINFLIP only |
| `consumePurchaseBoost` | `DegenerusGame` -> `MintModule.purchase()` | delegatecall (self-call) | Access: address(this) only |
| `consumeDecimatorBoost` | `DegenerusGame` -> `DegenerusStonk.burn()` | delegatecall | Access: COIN only |
| `checkAndClearExpiredBoon` | `LootboxModule` | nested delegatecall | During lootbox resolution |
| `consumeActivityBoon` | `LootboxModule` | nested delegatecall | During lootbox resolution |
