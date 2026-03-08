# XCON-01: Delegatecall Return Value Audit -- DegenerusGame.sol

**Audit Date:** 2026-03-01
**Auditor:** Automated source trace (READ-ONLY)
**Scope:** All delegatecall and staticcall sites in `contracts/DegenerusGame.sol`
**Requirement:** XCON-01 -- All delegatecall return values are checked; no failing module silently succeeds

---

## 1. _revertDelegate Implementation Verification

**Location:** DegenerusGame.sol line 1123

```solidity
function _revertDelegate(bytes memory reason) private pure {
    if (reason.length == 0) revert E();
    assembly ("memory-safe") {
        revert(add(32, reason), mload(reason))
    }
}
```

**Verification:**
- [x] If `reason.length == 0`, reverts with `E()` -- no silent success path
- [x] If `reason.length > 0`, uses assembly to bubble up original revert reason from `data` bytes
- [x] `add(32, reason)` skips the length prefix to get the raw error data
- [x] `mload(reason)` reads the length of the reason bytes
- [x] `revert(ptr, len)` reverts with the original error -- faithful propagation
- [x] Function is `private pure` -- cannot modify state, no hidden side effects
- [x] **No code path in `_revertDelegate` silently succeeds.** Every path reverts.

**Verdict:** CORRECT. `_revertDelegate` is a sound revert-bubbling mechanism.

---

## 2. Delegatecall Site Verification Table

Every delegatecall site in DegenerusGame.sol is enumerated below. For each site, the table confirms:
- Line number of `.delegatecall(`
- The wrapping function name
- The target module (from ContractAddresses)
- Whether `(bool ok, bytes memory data)` captures the return
- Whether `if (!ok) _revertDelegate(data)` follows
- Whether the `data` bytes are decoded for a return value

### 2.1 GAME_ADVANCE_MODULE (6 sites)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 1 | 320 | `advanceGame()` | YES | YES (L325) | No | Void function |
| 2 | 348 | `wireVrf(...)` | YES | YES (L356) | No | Void function |
| 3 | 1903 | `updateVrfCoordinatorAndSub(...)` | YES | YES (L1913) | No | Void function |
| 4 | 1922 | `requestLootboxRng()` | YES | YES (L1927) | No | Void function |
| 5 | 1940 | `reverseFlip(...)` | YES | YES (L1946) | No | Void function |
| 6 | 1961 | `rawFulfillRandomWords(...)` | YES | YES (L1968) | No | Void function |

**All 6 sites: PASS.** Pattern is uniform `(bool ok, bytes memory data) = ... .delegatecall(...); if (!ok) _revertDelegate(data);`.

### 2.2 GAME_MINT_MODULE (4 sites)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 7 | 566 | `_purchaseFor(...)` (purchase) | YES | YES (L576) | No | Void delegatecall |
| 8 | 593 | `purchaseCoin(...)` | YES | YES (L601) | No | Void delegatecall |
| 9 | 614 | `purchaseBurnieLootbox(...)` | YES | YES (L621) | No | Void delegatecall |
| 10 | 1143 | `_recordMintDataModule(...)` (recordMintData) | YES | YES (L1151) | YES: `abi.decode(data, (uint256))` (L1153) | Also checks `data.length == 0` (L1152) |

**All 4 sites: PASS.**

**Site #10 return value detail:** `_recordMintDataModule` decodes `uint256 coinReward` from `data`. The interface `IDegenerusGameMintModule.recordMintData` returns `uint256 coinReward` (interface line 231). Types match exactly. Additional safety: `if (data.length == 0) revert E()` at line 1152 guards against empty return data.

### 2.3 GAME_WHALE_MODULE (4 sites)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 11 | 651 | `_purchaseWhaleBundleFor(...)` (purchaseWhaleBundle) | YES | YES (L658) | No | Void delegatecall |
| 12 | 673 | `_purchaseLazyPassFor(...)` (purchaseLazyPass) | YES | YES (L679) | No | Void delegatecall |
| 13 | 737 | `_purchaseDeityPassFor(...)` (purchaseDeityPass) | YES | YES (L744) | No | Void delegatecall |
| 14 | 754 | `onDeityPassTransfer(...)` (handleDeityPassTransfer) | YES | YES (L761) | No | Void delegatecall; gated by `msg.sender == DEITY_PASS` (L751) |

**All 4 sites: PASS.**

### 2.4 GAME_LOOTBOX_MODULE (3 delegatecall + 1 staticcall)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 15 | 783 | `_openLootBoxFor(...)` (openLootBox) | YES | YES (L790) | No | Void delegatecall |
| 16 | 799 | `_openBurnieLootBoxFor(...)` (openBurnieLootBox) | YES | YES (L806) | No | Void delegatecall |
| 17 | 1009 | `issueDeityBoon(...)` | YES | YES (L1017) | No | Void delegatecall |
> **POST-AUDIT UPDATE:** Site #18 `deityBoonSlots` was replaced with `deityBoonData()` (DegenerusGame.sol line 929). The new function computes all values directly in DegenerusGame's storage context without delegatecall or staticcall, resolving the XCON-F01 finding. The staticcall site no longer exists.

| 18 | 985 | `deityBoonSlots(...)` | YES | `revert E()` (L991) | YES: `abi.decode(data, (uint8[3], uint8, uint48))` (L992) | **STATICCALL** -- see Section 4 |

**All 4 sites: PASS** (ok is checked at every site). **Site #18 has a FINDING** -- see Section 4.

### 2.5 GAME_DEGENERETTE_MODULE (3 sites)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 19 | 826 | `placeFullTicketBets(...)` | YES | YES (L839) | No | Void delegatecall |
| 20 | 857 | `placeFullTicketBetsFromAffiliateCredit(...)` | YES | YES (L869) | No | Void delegatecall |
| 21 | 881 | `resolveDegeneretteBets(...)` (resolveBets) | YES | YES (L888) | No | Void delegatecall |

**All 3 sites: PASS.**

### 2.6 GAME_BOON_MODULE (3 sites)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 22 | 905 | `consumeCoinflipBoon(...)` | YES | YES (L913) | YES: `abi.decode(data, (uint16))` (L914) | Returns `uint16 boostBps` |
| 23 | 928 | `consumeDecimatorBoon(...)` (consumeDecimatorBoost) | YES | YES (L936) | YES: `abi.decode(data, (uint16))` (L937) | Returns `uint16 boostBps` |
| 24 | 951 | `consumePurchaseBoost(...)` | YES | YES (L959) | YES: `abi.decode(data, (uint16))` (L960) | Returns `uint16 boostBps` |

**All 3 sites: PASS.**

**Return value type verification:**
- `consumeCoinflipBoon` interface returns `uint16 boonBps` (interface line 334). Decoded as `uint16`. MATCH.
- `consumeDecimatorBoost` interface returns `uint16 boostBps` (interface line 344). Decoded as `uint16`. MATCH.
- `consumePurchaseBoost` interface returns `uint16 boostBps` (interface line 339). Decoded as `uint16`. MATCH.

Note: If the module were to return a different type (e.g., `uint256` instead of `uint16`), `abi.decode` would NOT silently corrupt. ABI encoding pads to 32 bytes; decoding `uint16` from a `uint256`-encoded value truncates to the lower 16 bits, which matches Solidity's ABI specification. In practice the types match exactly, so this is moot.

### 2.7 GAME_DECIMATOR_MODULE (6 sites)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 25 | 1178 | `creditDecJackpotClaimBatch(...)` | YES | YES (L1188) | No | Void delegatecall |
| 26 | 1205 | `creditDecJackpotClaim(...)` | YES | YES (L1215) | No | Void delegatecall |
| 27 | 1239 | `recordDecBurn(...)` | YES | YES (L1249) | YES: `abi.decode(data, (uint8))` (L1251) | Also checks `data.length == 0` (L1250) |
| 28 | 1268 | `runDecimatorJackpot(...)` | YES | YES (L1276) | YES: `abi.decode(data, (uint256))` (L1278) | Also checks `data.length == 0` (L1277); self-call gated (L1265) |
| 29 | 1290 | `consumeDecClaim(...)` | YES | YES (L1297) | YES: `abi.decode(data, (uint256))` (L1299) | Also checks `data.length == 0` (L1298); self-call gated (L1287) |
| 30 | 1307 | `claimDecimatorJackpot(...)` | YES | YES (L1313) | No | Void delegatecall |

**All 6 sites: PASS.**

**Return value type verification:**
- `recordDecBurn` interface returns `uint8 bucketUsed` (interface line 165). Decoded as `uint8`. MATCH.
- `runDecimatorJackpot` interface returns `uint256 returnAmountWei` (interface line 176). Decoded as `uint256`. MATCH.
- `consumeDecClaim` interface returns `uint256 amountWei` (interface line 182). Decoded as `uint256`. MATCH.

### 2.8 GAME_ENDGAME_MODULE (1 site)

| # | Line | Function | ok Checked? | _revertDelegate? | Return Decoded? | Notes |
|---|------|----------|-------------|-------------------|-----------------|-------|
| 31 | 1789 | `_claimWhalePassFor(...)` (claimWhalePass) | YES | YES (L1795) | No | Void delegatecall |

**1 site: PASS.**

---

## 3. Summary: Delegatecall Sites

| Module | Expected Sites | Found Sites | All Checked? |
|--------|---------------|-------------|--------------|
| GAME_ADVANCE_MODULE | 6 | 6 | YES |
| GAME_MINT_MODULE | 4 | 4 | YES |
| GAME_WHALE_MODULE | 4 | 4 | YES |
| GAME_LOOTBOX_MODULE | 3 delegatecall + 1 staticcall | 3 + 1 | YES |
| GAME_DEGENERETTE_MODULE | 3 | 3 | YES |
| GAME_BOON_MODULE | 3 | 3 | YES |
| GAME_DECIMATOR_MODULE | 6 | 6 | YES |
| GAME_ENDGAME_MODULE | 1 | 1 | YES |
| **TOTAL** | **30 delegatecall + 1 staticcall** | **30 + 1** | **YES** |

All 30 delegatecall sites use the uniform pattern:
```solidity
(bool ok, bytes memory data) = ContractAddresses.MODULE.delegatecall(
    abi.encodeWithSelector(IModule.function.selector, args)
);
if (!ok) _revertDelegate(data);
```

Zero deviations from this pattern across all 30 delegatecall sites.

---

## 4. Staticcall Site Verification: deityBoonSlots

> **POST-AUDIT UPDATE:** The `deityBoonSlots` function was replaced with `deityBoonData()` (DegenerusGame.sol line 929). The new function reads all state (rngWord, usedMask, decWindowOpen, deityPassOwners) directly from Game storage without any delegatecall or staticcall. XCON-F01 is resolved -- the storage context mismatch no longer exists. The analysis below is retained for historical reference only.

**Location:** DegenerusGame.sol lines 968-993

```solidity
function deityBoonSlots(address deity)
    external view returns (uint8[3] memory slots, uint8 usedMask, uint48 day)
{
    day = _simulatedDayIndex();                          // Line 976: Game's view context
    if (deityBoonDay[deity] != day) {                    // Line 977: Game's storage
        return (slots, 0, day);                          // Line 979: Early return
    }
    usedMask = deityBoonUsedMask[deity];                 // Line 981: Game's storage
    (bool ok, bytes memory data) = ContractAddresses
        .GAME_LOOTBOX_MODULE
        .staticcall(                                     // Line 985: STATICCALL
            abi.encodeWithSelector(
                IDegenerusGameLootboxModule.deityBoonSlots.selector,
                deity
            )
        );
    if (!ok) revert E();                                 // Line 991: Checked
    return abi.decode(data, (uint8[3], uint8, uint48));  // Line 992: Overwrites locals
}
```

### 4.1 Is staticcall appropriate here?

`deityBoonSlots` is a `view` function that should not modify state. Using `staticcall` is correct for preventing state modifications. However, `staticcall` executes in the **target contract's storage context**, not the caller's. This is the fundamental difference from `delegatecall`.

### 4.2 Storage Context Analysis

The module's `deityBoonSlots` function (LootboxModule line 715) reads the following storage variables:

| Storage Variable | Module's Value (staticcall) | Game's Value (delegatecall) | Impact |
|-----------------|----------------------------|----------------------------|--------|
| `_simulatedDayIndex()` | Correct (pure computation from `block.timestamp` + constant) | Same | None |
| `deityBoonDay[deity]` | 0 (never written in module) | Current day if deity has boons | Incorrect `usedMask` logic |
| `deityBoonUsedMask[deity]` | 0 (never written in module) | Actual mask of used slots | Incorrect mask returned |
| `decWindowOpen` | false (default) | Actual decimator window state | Incorrect boon type pool |
| `deityPassOwners.length` | 0 (empty in module) | Actual count of deity pass owners | Incorrect availability check |
| `rngWordByDay[day]` | 0 (never written in module) | Actual VRF word for the day | Incorrect seed |
| `rngWordCurrent` | 0 (never written in module) | Current VRF word | Incorrect seed |

Additionally, `address(this)` in the module's fallback seed computation (`keccak256(abi.encodePacked(day, address(this)))`) evaluates to the module's address, not Game's address, further changing the deterministic seed.

### 4.3 FINDING: XCON-F01 -- deityBoonSlots staticcall reads module's storage, not Game's storage

**Severity:** MEDIUM

**Description:** The `deityBoonSlots` function in DegenerusGame.sol uses `staticcall` to the LootboxModule to compute boon slot types. Since `staticcall` executes in the target's storage context (not the caller's via delegatecall), the module reads its own empty/default storage values instead of DegenerusGame's actual game state. This causes three incorrect behaviors:

1. **Wrong slot types:** The boon slots are computed using the module's empty `rngWordByDay` and `rngWordCurrent` (both 0), falling back to `keccak256(day, MODULE_ADDRESS)` instead of `keccak256(day, GAME_ADDRESS)`. The slots shown to the caller will not match the slots used during actual `issueDeityBoon` execution (which uses delegatecall and reads Game's storage).

2. **Wrong `usedMask`:** The Game function computes `usedMask` correctly from its own storage at line 981, but then discards it by returning the module's `abi.decode` output at line 992. The module always returns `usedMask = 0` because `deityBoonDay[deity]` in module storage is always 0.

3. **Wrong availability flags:** `decWindowOpen` defaults to `false` and `deityPassOwners.length` defaults to 0 in module storage, regardless of actual game state. This changes which boon types are eligible in the returned slots.

**Root Cause:** Line 992 returns ALL three values from the module's response (`return abi.decode(data, (uint8[3], uint8, uint48))`), overwriting the locally-computed `day` and `usedMask` values from lines 976 and 981. The function should either:
- Use `delegatecall` instead of `staticcall` (but this is incompatible with `view` function modifier), OR
- Only decode the `slots` array from the module response and return the locally-computed `usedMask` and `day`, OR
- Compute slots directly in DegenerusGame without delegating to the module

**Impact:** This is a VIEW-ONLY function used for UI display. It does not affect state-changing operations. The `issueDeityBoon` function uses `delegatecall` (site #17, line 1009) which correctly reads Game's storage. Therefore:
- **No fund loss possible** -- boon issuance logic is unaffected
- **UI/frontend will show incorrect boon slots** -- deity pass holders may see wrong available boons
- **UI will show `usedMask = 0`** even after using boon slots -- stale display

**Remediation:** Decode only the `slots` array from the module's staticcall response and return the locally-computed `usedMask` and `day`:
```solidity
(uint8[3] memory moduleSlots, , ) = abi.decode(data, (uint8[3], uint8, uint48));
return (moduleSlots, usedMask, day);
```
However, this still has the wrong-seed problem for slot computation. The correct fix is to replicate the slot computation logic in DegenerusGame.sol or use a different view pattern. Alternatively, the function could be changed from `view` to non-`view` and use `delegatecall`, though this is a less conventional pattern for read-only queries.

**Note on `day` return value:** The `day` value returned by the module IS correct because `_simulatedDayIndex()` is a pure computation from `block.timestamp` and a compile-time constant, so it produces the same result in both contexts.

---

## 5. Return Value Decoding Sites -- Type Correctness

Eight functions decode return values from delegatecall/staticcall `data` bytes:

| # | Function | Decode Type | Interface Return Type | Match? | Extra Guard |
|---|----------|-------------|----------------------|--------|-------------|
| 10 | `_recordMintDataModule` | `uint256` | `uint256 coinReward` | YES | `data.length == 0` check (L1152) |
| 18 | `deityBoonSlots` | `(uint8[3], uint8, uint48)` | `(uint8[3], uint8, uint48)` | YES | N/A (see Finding XCON-F01) |
| 22 | `consumeCoinflipBoon` | `uint16` | `uint16 boonBps` | YES | None needed |
| 23 | `consumeDecimatorBoon` | `uint16` | `uint16 boostBps` | YES | None needed |
| 24 | `consumePurchaseBoost` | `uint16` | `uint16 boostBps` | YES | None needed |
| 27 | `recordDecBurn` | `uint8` | `uint8 bucketUsed` | YES | `data.length == 0` check (L1250) |
| 28 | `runDecimatorJackpot` | `uint256` | `uint256 returnAmountWei` | YES | `data.length == 0` check (L1277) |
| 29 | `consumeDecClaim` | `uint256` | `uint256 amountWei` | YES | `data.length == 0` check (L1298) |

**All 8 decode sites: types match interface return types exactly.**

**ABI decode safety note:** If a module were to return a mismatched type, `abi.decode` would either revert (if data is too short) or silently truncate (if decoding a smaller type from a larger ABI-encoded value). Since all types match exactly, this is not a concern.

---

## 6. Non-Game Delegatecalls to Modules

Searched all `.sol` files in `contracts/` for delegatecall usage outside DegenerusGame.sol:

**Module-internal delegatecalls (expected, safe):**
- `DegenerusGameAdvanceModule.sol` -- 10 delegatecall sites to GAME_GAMEOVER_MODULE, GAME_JACKPOT_MODULE, and GAME_MINT_MODULE. These are nested delegatecalls from within the already-delegated AdvanceModule executing in Game's context. Each follows the same `(bool ok, bytes memory data)` + `_revertDelegate(data)` pattern.
- `DegenerusGameLootboxModule.sol` -- 2 delegatecall sites to GAME_BOON_MODULE (lines 934, 991). Nested delegatecalls for boon consumption/cleanup within lootbox resolution. Both check `ok`.
- `DegenerusGameDecimatorModule.sol` -- 1 delegatecall site to GAME_LOOTBOX_MODULE (line 736). Nested delegatecall for lootbox resolution during decimator claims. Checks `ok`.
- `DegenerusGameDegeneretteModule.sol` -- 1 delegatecall to GAME_BOON_MODULE (line 763). Nested delegatecall for activity boon consumption. Checks `ok`.

**No non-Game contract delegatecalls to game modules found.** All module delegatecalls occur either directly from DegenerusGame.sol or from within modules that are themselves executing in Game's context via the top-level delegatecall chain.

---

## 7. Low-Level Call Sites (ETH Transfers)

Three `.call{value: ...}` sites found in DegenerusGame.sol for ETH transfers:

| Line | Function | Boolean Checked? | Revert on Failure? |
|------|----------|-------------------|-------------------|
| 2000 | `_payoutWithStethFallback` | YES: `(bool okEth, )` | YES: `if (!okEth) revert E()` (L2001) |
| 2017 | `_payoutWithStethFallback` | YES: `(bool ok, )` | YES: `if (!ok) revert E()` (L2018) |
| 2038 | `_payoutWithEthFallback` | YES: `(bool ok, )` | YES: `if (!ok) revert E()` (L2039) |

**All 3 ETH transfer sites: PASS.** Boolean return values are checked and revert on failure.

---

## 8. XCON-01 Verdict

### Findings Summary

| ID | Severity | Description |
|----|----------|-------------|
| XCON-F01 | MEDIUM | `deityBoonSlots` staticcall reads module's storage context, returning incorrect slot types, usedMask, and availability flags. View-only impact -- no state corruption possible. **(POST-AUDIT: RESOLVED -- function replaced with `deityBoonData()` which reads Game storage directly)** |

### Metrics

| Metric | Value |
|--------|-------|
| Total delegatecall sites | 30 |
| Total staticcall sites | 1 |
| Total low-level .call sites | 3 |
| Sites with ok boolean check | 34/34 (100%) |
| Sites with _revertDelegate bubble | 30/30 delegatecall (100%) |
| Staticcall sites with revert on failure | 1/1 (100%) |
| .call sites with revert on failure | 3/3 (100%) |
| Return-value-decoding sites | 8 |
| Type-correct decodes | 8/8 (100%) |
| Non-Game delegatecalls to modules | 0 (only nested module-to-module within Game's context) |

### Verdict

**XCON-01: PASS**

All 30 delegatecall sites in DegenerusGame.sol use the uniform `(bool ok, bytes memory data) = MODULE.delegatecall(...); if (!ok) _revertDelegate(data);` pattern with zero deviations. No failing delegatecall module can silently succeed. All return-value-decoding sites use correct types matching their interface definitions. All low-level `.call` sites for ETH transfers check their boolean return values.

One finding (XCON-F01) documents a storage context mismatch in the single `staticcall` site (`deityBoonSlots`). This is a view-only function that does not affect state-changing operations, so the core XCON-01 invariant -- that no failing module can silently succeed and corrupt state -- remains upheld. The finding is rated MEDIUM because it affects UI correctness for deity pass holders.

---

## Appendix: Module-to-Module Nested Delegatecall Audit

For completeness, the nested delegatecall sites within modules (executing in Game's context) are also verified:

### DegenerusGameAdvanceModule.sol (10 nested sites)

| Line | Target Module | Function | ok Checked? |
|------|--------------|----------|-------------|
| 341 | GAME_GAMEOVER_MODULE | handleGameOverDrain | YES |
| 357 | GAME_GAMEOVER_MODULE | handleFinalSweep | YES |
| 403 | GAME_MINT_MODULE | (selector-based) | YES |
| 416 | GAME_MINT_MODULE | (selector-based) | YES |
| 441 | GAME_JACKPOT_MODULE | consolidatePrizePools | YES |
| 457 | GAME_JACKPOT_MODULE | (selector-based) | YES |
| 481 | GAME_JACKPOT_MODULE | payDailyJackpot | YES |
| 499 | GAME_JACKPOT_MODULE | (selector-based) | YES |
| 518 | GAME_JACKPOT_MODULE | (selector-based) | YES |
| 536 | GAME_JACKPOT_MODULE | (selector-based) | YES |
| 902 | GAME_MINT_MODULE | (selector-based) | YES |
| 966 | GAME_JACKPOT_MODULE | processTicketBatch | YES |

### DegenerusGameLootboxModule.sol (2 nested sites)

| Line | Target Module | Function | ok Checked? |
|------|--------------|----------|-------------|
| 934 | GAME_BOON_MODULE | consumeActivityBoon | YES (checked via `okAct`) |
| 991 | GAME_BOON_MODULE | clearExpiredBoons | YES (checked via `okClr`) |

### DegenerusGameDecimatorModule.sol (1 nested site)

| Line | Target Module | Function | ok Checked? |
|------|--------------|----------|-------------|
| 736 | GAME_LOOTBOX_MODULE | (lootbox resolution) | YES |

### DegenerusGameDegeneretteModule.sol (1 nested site)

| Line | Target Module | Function | ok Checked? |
|------|--------------|----------|-------------|
| 763 | GAME_BOON_MODULE | (activity boon) | YES |

**All 14+ nested delegatecall sites: PASS.** Every nested delegatecall within module code also checks the boolean return value.
