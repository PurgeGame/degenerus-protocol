---
phase: 208-module-cascade
verified: 2026-04-10T04:54:56Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
gaps:
  - truth: "forge build succeeds with zero errors for core game contracts and interfaces"
    status: failed
    reason: "GameTimeLib.sol has a compile error: arithmetic expression `currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1` promotes to uint48 because DEPLOY_DAY_BOUNDARY is uint48, but the function return type is uint32. This is a Phase 207 miss that 208-04 did not fix despite the summary claiming 'forge build passes with zero new errors'."
    artifacts:
      - path: "contracts/libraries/GameTimeLib.sol"
        issue: "Line 33: return type is uint32 but arithmetic resolves to uint48 — DEPLOY_DAY_BOUNDARY in ContractAddresses is uint48"
    missing:
      - "Cast DEPLOY_DAY_BOUNDARY to uint32 in the return expression: `return currentDayBoundary - uint32(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;`"
      - "Or change ContractAddresses.DEPLOY_DAY_BOUNDARY from uint48 to uint32 (ContractAddresses.sol is user-managed; use local cast instead)"
deferred:
  - truth: "forge build succeeds across the entire project (BurnieCoinflip, DegenerusJackpots, DegenerusQuests compile cleanly)"
    addressed_in: "Phase 209"
    evidence: "Phase 209 success criteria: 'BurnieCoinflip, DegenerusQuests, StakedDegenerusStonk, DegenerusJackpots, and DegenerusVault use uint32 for all day-index parameters and storage' and 'forge build succeeds across the entire project with zero errors'"
---

# Phase 208: Module Cascade + Interfaces — Verification Report

**Phase Goal:** Every module and interface that reads or writes day-index variables or claimablePool compiles cleanly with the narrowed types
**Verified:** 2026-04-10T04:54:56Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All function parameters, return types, local variables, and event parameters using day indices are uint32 across all game modules | VERIFIED | All 9 modules have zero uint48 day-index references; only legitimate timestamp uint48 remain (AdvanceModule: block.timestamp, rngRequestTime, etc.; DecimatorModule: burnLevel struct casts) |
| 2 | All claimablePool read/write sites cast or operate on uint128 without truncation risk | VERIFIED | 12 cast sites confirmed across GameOverModule (2), DecimatorModule (1), JackpotModule (2), DegeneretteModule (2), MintModule (1), PayoutUtils (1), DegenerusGame.sol (3) |
| 3 | The _maybeRequestLootboxRng inline (already committed) compiles with the new types | VERIFIED | Logic block in AdvanceModule uses _lrRead/_lrWrite with correct uint32 types; no module or DegenerusGame.sol errors in forge output |
| 4 | All interface signatures (IDegenerusGame, IDegenerusGameModules, IDegenerusGameStorage, IStakedDegenerusStonk, IDegenerusQuests, IBurnieCoinflip) match updated module signatures | VERIFIED | All 6 target interfaces have zero uint48; selector match confirmed: handleGameOverDrain(uint32), openLootBox(address,uint32), resolveRedemptionPeriod(uint16,uint32), rollDailyQuest(uint32,uint256), getCoinflipDayResult(uint32) |
| 5 | Packed slot access uses existing _read/_write helpers (no named wrappers) | VERIFIED | DegenerusGameStorage.sol exposes only generic shift/mask helpers: _lrRead/_lrWrite, _goRead/_goWrite, _djtRead/_djtWrite, _psRead/_psWrite — no named convenience wrappers |
| 6 | forge build succeeds with zero errors for core game contracts and interfaces | FAILED | GameTimeLib compile error: `currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1` promotes to uint48 (DEPLOY_DAY_BOUNDARY is uint48 constant in ContractAddresses.sol), but return type is uint32. External contract errors (BurnieCoinflip, DegenerusJackpots, DegenerusQuests) are deferred to Phase 209. |

**Score:** 5/6 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | External contracts compile (BurnieCoinflip autoRebuyStartDay uint48 struct field, DegenerusJackpots lastBafResolvedDay uint48 storage, DegenerusQuests DailyQuest.day uint48 struct field) | Phase 209 | Phase 209 success criteria 1: "BurnieCoinflip, DegenerusQuests, StakedDegenerusStonk, DegenerusJackpots, and DegenerusVault use uint32 for all day-index parameters and storage" |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `contracts/modules/DegenerusGameAdvanceModule.sol` | Day-index narrowing + packed lootboxRng/presale migration | VERIFIED | 18 _lrRead/_lrWrite calls, 0 uint48 day-index references, timestamps preserved |
| `contracts/modules/DegenerusGameGameOverModule.sol` | Packed gameOver state migration + claimablePool uint128 | VERIFIED | 7 _goRead/_goWrite calls, handleGameOverDrain(uint32 day), 0 uint48 |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | Day-index narrowing + uint128 claimablePool cast | VERIFIED | 0 uint48 day-index (burnLevel uint48 casts preserved), uint128(lootboxPortion) confirmed |
| `contracts/modules/DegenerusGameJackpotModule.sol` | Packed dailyJackpotTraits migration + claimablePool uint128 | VERIFIED | 10 _djtRead/_djtWrite calls, 0 uint48 questDay locals, 2 uint128 claimablePool casts |
| `contracts/modules/DegenerusGameLootboxModule.sol` | Day-index narrowing for all lootbox events and functions | VERIFIED | 0 uint48, 1 _psRead call, all event params uint32 |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | LootboxRng packed migration + day-index narrowing | VERIFIED | 3 _lrRead/_lrWrite calls, 0 uint48, 0 lootboxRngIndex bare references |
| `contracts/modules/DegenerusGameMintModule.sol` | Day-index narrowing + packed lootboxRng/presale + claimablePool | VERIFIED | 6 _lrRead/_lrWrite calls, 0 uint48, uint128(shortfall) cast confirmed |
| `contracts/modules/DegenerusGameWhaleModule.sol` | Day-index narrowing + packed lootboxRng/presale | VERIFIED | 2 _lrRead/_lrWrite calls, 0 uint48, constants narrowed to uint32 |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | uint128 claimablePool cast | VERIFIED | uint128(remainder) cast at claimablePool += site |
| `contracts/DegenerusGame.sol` | Proxy dispatcher with narrowed types and packed helpers | VERIFIED | currentDayView() returns uint32, openLootBox(uint32), 10 packed helper calls, 3 uint128 casts, timestamps remain uint48 |
| `contracts/interfaces/IDegenerusGame.sol` | External interface matching DegenerusGame signatures | VERIFIED | 0 uint48, currentDayView returns uint32, lootboxStatus/openLootBox use uint32 |
| `contracts/interfaces/IDegenerusGameModules.sol` | Module interfaces matching delegatecall module signatures | VERIFIED | 0 uint48, handleGameOverDrain(uint32), openLootBox(address,uint32), openBurnieLootBox(address,uint32) |
| `contracts/interfaces/IStakedDegenerusStonk.sol` | Narrowed resolveRedemptionPeriod signature | VERIFIED | resolveRedemptionPeriod(uint16,uint32 flipDay) — matches StakedDegenerusStonk.sol implementation |
| `contracts/interfaces/IDegenerusQuests.sol` | Narrowed quest day-index types | VERIFIED | rollDailyQuest(uint32,uint256), awardQuestStreakBonus(address,uint16,uint32), QuestInfo.day is uint32 |
| `contracts/interfaces/IBurnieCoinflip.sol` | Narrowed coinflip day-index types | VERIFIED | getCoinflipDayResult(uint32), epoch is uint32, startDay is uint32 |
| `contracts/libraries/GameTimeLib.sol` | currentDayIndexAt returns uint32 — no arithmetic type promotion | FAILED | Line 33: `currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1` evaluates to uint48 because DEPLOY_DAY_BOUNDARY is `uint48 internal constant` in ContractAddresses.sol |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| DegenerusGameAdvanceModule.sol | DegenerusGameStorage.sol | _lrRead/_lrWrite, _psRead/_psWrite helpers | WIRED | 18 lr calls, 3+ ps calls confirmed |
| DegenerusGameGameOverModule.sol | DegenerusGameStorage.sol | _goRead/_goWrite helpers | WIRED | 7 go calls confirmed |
| DegenerusGameJackpotModule.sol | DegenerusGameStorage.sol | _djtRead/_djtWrite helpers | WIRED | 10 djt calls confirmed |
| DegenerusGameDegeneretteModule.sol | DegenerusGameStorage.sol | _lrRead/_lrWrite helpers | WIRED | 3 lr calls confirmed |
| DegenerusGameMintModule.sol | DegenerusGameStorage.sol | _lrRead/_lrWrite, _psRead/_psWrite helpers | WIRED | 6 lr calls, 2 ps calls confirmed |
| DegenerusGameWhaleModule.sol | DegenerusGameStorage.sol | _lrRead/_lrWrite, _psRead helpers | WIRED | 2 lr calls confirmed |
| IDegenerusGameModules.sol | module .sol files | function selector matching (delegatecall dispatch) | WIRED | Selectors match: handleGameOverDrain(uint32), openLootBox(address,uint32) confirmed |
| IDegenerusGame.sol | DegenerusGame.sol | external interface | WIRED | currentDayView/openLootBox/lootboxStatus/getDailyHeroWager signatures match |

### Data-Flow Trace (Level 4)

Not applicable — this phase is a type-narrowing refactor, not a new data flow. All modules read from the same packed storage slots introduced in Phase 207.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| core game module files compile without errors | `forge build 2>&1 \| grep "contracts/modules/\|contracts/DegenerusGame\|contracts/interfaces/"` | No output (zero module/interface errors) | PASS |
| GameTimeLib has uint32 return type error | `forge build 2>&1 \| grep "GameTimeLib"` | `contracts/libraries/GameTimeLib.sol:33` type mismatch | FAIL |
| External contracts deferred to 209 | `forge build 2>&1 \| grep ".sol:" \| sort -u` | BurnieCoinflip, DegenerusJackpots, DegenerusQuests (Phase 209 scope) + GameTimeLib | FAIL (GameTimeLib) / DEFERRED (external) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TYPE-03 | 208-01, 208-02, 208-03, 208-04 | All day-index function parameters, return types, and local variables narrowed to uint32 across all modules | SATISFIED | All 9 modules verified at zero uint48 day-index; DegenerusGame.sol key functions use uint32 |
| TYPE-05 | 208-04 | All day-index types in interfaces and view contracts narrowed to match implementations | SATISFIED | All 6 target interfaces have zero uint48; selector matching confirmed for delegatecall dispatch |
| SLOT-04 | 208-01, 208-02, 208-03, 208-04 | All claimablePool read/write sites updated for uint128 type | SATISFIED | 12 uint128 cast sites confirmed across all modules and DegenerusGame.sol |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `contracts/libraries/GameTimeLib.sol` | 33 | Arithmetic promotion: `uint32 - uint48 + 1` returns uint48, not uint32 | Blocker | Prevents forge build success — core library used by all day-index calculations |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1437, 1588 | Comment references to `lootboxRngIndex` (string in comments, not code) | Info | Stale comment text only; no code impact |

### Human Verification Required

None — all required checks are automated.

### Gaps Summary

One gap blocks the phase goal: `contracts/libraries/GameTimeLib.sol` has a compiler error at line 33 where arithmetic between `uint32 currentDayBoundary` and `uint48 ContractAddresses.DEPLOY_DAY_BOUNDARY` promotes the expression to `uint48`, but the return type is `uint32`. This is a Phase 207 miss (GameTimeLib was modified in commit f5c86549 to return `uint32` but the arithmetic was not updated). Phase 208 plan 04 ran `forge build` and claimed it passed — the summary is incorrect on this point.

**Fix:** In `currentDayIndexAt`, change line 33 to:
```solidity
return currentDayBoundary - uint32(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
```

This is safe because `DEPLOY_DAY_BOUNDARY` is a deploy-time constant (currently 0) that will never exceed uint32 range.

Three external contract errors (BurnieCoinflip, DegenerusJackpots, DegenerusQuests) are correctly deferred to Phase 209 — they are outside the "core game contracts and interfaces" scope of Phase 208.

**Update (Phase 209):** This gap was closed during Phase 209 execution. The `uint32()` cast was applied to `ContractAddresses.DEPLOY_DAY_BOUNDARY` in GameTimeLib.sol, and `forge build` succeeds with zero errors across all contracts. The phase goal is now fully satisfied (6/6 truths verified).

---

_Verified: 2026-04-10T04:54:56Z_
_Verifier: Claude (gsd-verifier)_
