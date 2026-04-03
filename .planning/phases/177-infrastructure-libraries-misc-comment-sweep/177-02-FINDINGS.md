# Phase 177 Comment Audit — Plan 02 Findings
**Contracts:** DegenerusQuests, DegenerusJackpots, DeityBoonViewer
**Requirement:** CMT-04
**Date:** 2026-04-03
**Total findings this plan:** 1 LOW, 4 INFO

---

## DegenerusQuests

### Finding 177-02-001 [INFO] — Contract-level @notice understates authorized callers

**Location:** `DegenerusQuests.sol` line 12 (NatSpec `@notice`)

**Comment says:**
> "called by the Degenerus ContractAddresses.COIN contract"

**Code does:** The `onlyCoin` modifier at lines 306-315 allows four callers: `ContractAddresses.COIN`, `ContractAddresses.COINFLIP`, `ContractAddresses.GAME`, and `ContractAddresses.AFFILIATE`. The contract-level NatSpec singles out only COIN, leaving COINFLIP, GAME, and AFFILIATE undocumented.

**Note:** The `@dev` Architecture Overview at line 21 does document the broader call surface (`onlyCoin` vs `onlyCoinOrGame`), so the contract-level `@notice` is the only mismatch. A reader skimming the top-level description would underestimate the trust surface.

---

### Finding 177-02-002 [INFO] — OnlyCoin error @notice describes two callers; modifier allows four

**Location:** `DegenerusQuests.sol` lines 54-55

**Comment says:**
```solidity
/// @notice Thrown when caller is not the authorized COIN or COINFLIP contract.
error OnlyCoin();
```

**Code does:** `onlyCoin` at lines 306-315 accepts `ContractAddresses.COIN`, `ContractAddresses.COINFLIP`, `ContractAddresses.GAME`, and `ContractAddresses.AFFILIATE`. `OnlyCoin` is thrown when none of these four match. The error notice names only two of the four authorized callers.

---

### Finding 177-02-003 [LOW] — `_handleLevelQuestProgress` @dev references stale variable name `levelQuestGlobal`

**Location:** `DegenerusQuests.sol` lines 1838-1842

**Comment says:**
```solidity
///      Reads levelQuestGlobal (single SLOAD, shares slot with questVersionCounter)
///      to get both level and type.
```

**Code does:** No storage variable named `levelQuestGlobal` exists in the contract. The code reads `levelQuestType` (line 1853) and `levelQuestVersion` (line 1858), which are declared as separate `uint8` variables at lines 291-295. `levelQuestType` shares a storage slot with `levelQuestVersion` and `questVersionCounter` (uint24), not as a combined `levelQuestGlobal` struct. The comment describes a refactored-away single-variable design; the implementation uses three individual named variables.

**Severity justification:** LOW because this misleads a reader about the storage layout and variable names, making it harder to trace level quest reads and gas cost reasoning. A reader following the comment would not find `levelQuestGlobal` anywhere.

---

### Finding 177-02-004 [INFO] — `getPlayerLevelQuestView` @dev references stale variable name `levelQuestGlobal`

**Location:** `DegenerusQuests.sol` line 1894

**Comment says:**
```solidity
/// @dev Reads levelQuestGlobal and levelQuestPlayerState for the player's current level.
```

**Code does:** Reads `levelQuestType` (line 1902), `levelQuestPlayerState[player]` (line 1904), `levelQuestVersion` (line 1907), and `questGame.mintPrice()` (line 1912). No `levelQuestGlobal` variable exists. This is the same stale name as Finding 177-02-003.

---

### Finding 177-02-005 [LOW] — `handlePurchase` reward routing comment contradicts lootbox return behavior

**Location:** `DegenerusQuests.sol` lines 877-888

**Comment says (lines 877-880):**
```solidity
// Reward routing (match standalone handler behavior):
// - BURNIE mint rewards: creditFlip internally (handleMint behavior for !paidWithEth)
// - Lootbox rewards: creditFlip internally (handleLootBox behavior)
// - ETH mint rewards: returned to caller (handleMint behavior for paidWithEth)
```
And at line 887:
```solidity
// Return ETH mint reward + lootbox reward (caller adds lootbox to lootboxFlipCredit)
```

**Code does:** `lootboxReward` is creditFlipped at line 885 (`IBurnieCoinflip(ContractAddresses.COINFLIP).creditFlip(player, lootboxReward)`) AND is also added to `totalReturned` at line 888 (`uint256 totalReturned = ethMintReward + lootboxReward`). The block comment at lines 877-880 says lootbox rewards are "creditFlip internally" (matching `handleLootBox` standalone behavior), which implies they are NOT returned. The inline comment at line 887 contradicts this by explicitly including lootboxReward in the return. These two comments give opposite descriptions of the lootbox reward path, making the intended routing ambiguous.

**Note:** The actual call sites of `handlePurchase` determine whether this double-path is intentional or a double-payment. This finding documents the comment inconsistency; behavior analysis is a separate concern. A reader cannot determine from comments alone whether lootboxReward is returned to caller in addition to being creditFlipped.

---

**Explicit verification (per plan requirements):**

- Quest roll chain sequence: `rollDailyQuest` → `_seedQuestType` × 2 → events. Accurate.
- Carryover redesign comments: `clearLevelQuest` / `rollLevelQuest` comments at lines 1782-1780 describe zeroing at level transition and setting when RNG arrives. Accurate.
- Access control on `handleAffiliate` (line 641): `onlyCoin` — four callers allowed; NatSpec @custom:reverts says `OnlyCoin When caller is not COIN or COINFLIP contract` — same gap as Finding 177-02-002 applies here.
- Access control on `handleMint` (line 400): same gap as 177-02-002.
- Level quest BURNIE inflation bounded comment (not present in source — this was in design doc, not the contract itself).

---

## DegenerusJackpots

### Explicit checks (per plan requirements):

**runTerminalJackpot caller attribution:** `DegenerusJackpots.sol` has no `runTerminalJackpot` function. This contract is the standalone BAF accounting and resolution contract, not JackpotModule. The stale `EndgameModule` attribution found in Phase 175-02 was in `DegenerusGameJackpotModule.sol` at the `runTerminalJackpot` NatSpec; that finding does not apply to `DegenerusJackpots.sol`. No discrepancy here.

**_runRewardJackpots timing comment:** `DegenerusJackpots.sol` has no `_runRewardJackpots` function or comment about it. No discrepancy.

**Jackpot bucket comments:** Prize distribution table at lines 188-207 describes 10%+5%+5%+5%+5%+45%+25%=100%. Code confirms: `P/10` (line 243), `P/20` (line 254), `P/20` (line 271), `(P*3)/100 + P/50` (lines 290-291, Slice D), `(P*3)/100 + P/50` (lines 327-328, Slice D2), `(P*45)/100` (line 373), `P/4` (line 374). The 5% far-future slices are each 3%+2% = `(P*3)/100 + P/50 = 3%+2% = 5%`. All match.

**Access control comments:** `recordBafFlip` @custom:access says "Restricted to coin contract via onlyCoin modifier" (line 165) and @dev (line 161) says "Called by coin contract on every manual coinflip." The modifier at line 141-143 allows both `ContractAddresses.COIN` and `ContractAddresses.COINFLIP`. The @dev and @custom:access narrow the description to just "coin contract" where both COIN and COINFLIP are authorized callers.

### Finding 177-02-006 [INFO] — `recordBafFlip` @dev and @custom:access describe only "coin contract"; COINFLIP is also authorized

**Location:** `DegenerusJackpots.sol` lines 161, 165

**Comment says:**
- Line 161: `/// @dev Called by coin contract on every manual coinflip.`
- Line 165: `/// @custom:access Restricted to coin contract via onlyCoin modifier.`

**Code does:** `onlyCoin` modifier at lines 141-143 allows `ContractAddresses.COIN || ContractAddresses.COINFLIP`. The COINFLIP contract is an equal authorized caller. The comments imply only "coin contract" has access.

---

No additional discrepancies found in `DegenerusJackpots.sol`. NatSpec on `runBafJackpot` accurately describes parameters, return values, and access control. The `_clearBafTop`, `_updateBafTop`, `_bafTop`, `_bafScore`, `_score96`, and `_creditOrRefund` helper NatSpec are all consistent with implementation. The BAF_SCATTER_ROUNDS = 50 and "50 rounds x 4 multi-level trait tickets" description in the prize distribution comment (line 195) matches the loop at line 381. The winner array pre-allocation comment at line 231 (`1 + 1 + 1 + 4 + 50 + 50 = 107`) is arithmetically correct.

---

## DeityBoonViewer

No discrepancies found.

**Verification details:**

- **Weight arithmetic:** `W_TOTAL = 1298` verified by summing all weight constants: 200+40+8+200+30+8+400+80+16+40+8+2+28+10+2+28+10+2+100+30+8+8+30+8+2 = 1298 ✓
- **W_TOTAL_NO_DECIMATOR = 1248:** 1298 − (W_DECIMATOR_10 + W_DECIMATOR_25 + W_DECIMATOR_50) = 1298 − 50 = 1248 ✓
- **W_DEITY_PASS_ALL = 40:** W_DEITY_PASS_10 (28) + W_DEITY_PASS_25 (10) + W_DEITY_PASS_50 (2) = 40 ✓
- **deityPassAvailable logic:** `if (!deityPassAvailable) total -= W_DEITY_PASS_ALL` at line 111, then `if (deityEligible)` block skips deity pass boons in `_boonFromRoll`. Total and cursor are consistent — roll is modulo correct reduced total, and the skipped cursor steps match the subtracted weight.
- **Dependency comments:** `IDeityBoonDataSource` interface at lines 5-20 accurately describes the five return values from `deityBoonData`: `dailySeed`, `day`, `usedMask`, `decimatorOpen`, `deityPassAvailable`. These are consumed correctly in `deityBoonSlots` at lines 97-106.
- **Boon resolution NatSpec:** `deityBoonSlots` @return says "Array of 3 boon type IDs for today's slots" — matches `uint8[3] memory slots` and DEITY_DAILY_BOON_COUNT = 3.
- **Seed derivation comment:** No explicit comment on seed derivation formula. The code at line 109 uses `keccak256(abi.encode(dailySeed, deity, d, i))` — this is per-slot, per-deity, per-day entropy, providing independent rolls per slot. No comment claims otherwise.
- **`_boonFromRoll` fallback:** Returns `DEITY_BOON_ACTIVITY_50` if roll falls through all cursor checks (line 182). This is the correct unreachable fallback for an exhaustive weighted selection.
