# Phase 176 Comment Audit — Plan 02 Findings
**Contracts:** BurnieCoin, BurnieCoinflip
**Requirement:** CMT-03
**Date:** 2026-04-03
**Total findings this plan:** 5 LOW, 7 INFO

---

## BurnieCoin

### Finding BC-01 — INFO
**Location:** `BurnieCoin.sol` lines 183–189
**Comment says:** Two orphaned doc blocks appear between the `allowance` mapping declaration and the `WIRED CONTRACTS` section:
```
/// @notice Leaderboard entry for tracking top day flip bettors.
/// @dev Packed into single slot: address (20 bytes) + uint96 (12 bytes) = 32 bytes.
///      Score is stored in whole BURNIE tokens (divided by 1 ether) to fit uint96.

/// @notice Outcome record for a single coinflip day window.
/// @dev Packed into single slot: uint16 (2 bytes) + bool (1 byte) = 3 bytes.
///      rewardPercent is the bonus percentage (not total), e.g., 150 = 150% bonus = 2.5x total payout.
```
**Code does:** Neither struct (`PlayerScore` nor `CoinflipDayResult`) is declared in `BurnieCoin.sol`. Both structs live in `BurnieCoinflip.sol`. These comment blocks are orphaned references to structs in a different contract. No code follows them in BurnieCoin.
**Impact:** Confuses readers about BurnieCoin's storage layout. The DATA TYPES section banner (lines 176–181) implies struct definitions exist here when they do not.

---

### Finding BC-02 — INFO
**Location:** `BurnieCoin.sol` lines 265–279
**Comment says:** A full `BOUNTY STATE` section banner with storage layout table describing `currentBounty`, `biggestFlipEver`, and `bountyOwedTo` (slots 17 and 18).
**Code does:** None of these storage variables exist in `BurnieCoin.sol`. All three (`currentBounty`, `biggestFlipEver`, `bountyOwedTo`) are declared in `BurnieCoinflip.sol`. The slot numbers (17, 18) refer to BurnieCoinflip's layout, not BurnieCoin's. In BurnieCoin, slots 0–2 contain `_supply`, `balanceOf`, and `allowance`. The section header and slot table are orphaned artifacts.
**Impact:** A reader auditing BurnieCoin's storage layout would incorrectly believe it contains a bounty subsystem with three slots.

---

### Finding BC-03 — LOW
**Location:** `BurnieCoin.sol` lines 559–562 (NatSpec for `burnCoin`)
**Comment says:**
```
/// @dev Access: DegenerusGame, game, or affiliate.
///      Used for purchases, fees, and affiliate utilities.
```
**Code does:** `burnCoin` has `external onlyGame`, and the `onlyGame` modifier (line 505–507) allows only `ContractAddresses.GAME`. No affiliate or any other contract can call it. The description "DegenerusGame, game, or affiliate" lists three things where the first two are the same address and the third ("affiliate") has no access.
**Impact:** Misleads a reader into thinking affiliates have burn authority. This is a meaningful access-control misstatement — exactly the category a C4A warden would flag.

---

### Finding BC-04 — LOW
**Location:** `BurnieCoin.sol` line 448 (`burnForCoinflip` guard)
**Comment says:** `/// @dev Only callable by the BurnieCoinflip contract.`
**Code does:** `if (msg.sender != ContractAddresses.COINFLIP) revert OnlyGame();` — the function correctly restricts to COINFLIP only, but reverts with the `OnlyGame` error. The error name `OnlyGame` is semantically wrong for a COINFLIP-only gate.
**Impact:** When this function reverts, the error returned to callers is `OnlyGame()`, which implies the game contract is the gating party. A developer integrating this would receive a misleading error name. This does not affect security (the guard is correct) but the error name is incorrect for this function.

---

### Finding BC-05 — LOW
**Location:** `BurnieCoin.sol` lines 452–460 (NatSpec for `mintForGame`)
**Comment says:**
```
/// @notice Mint BURNIE to a player (coinflip claims, degenerette wins).
/// @dev Only callable by COINFLIP or GAME.
```
**Code does:** `if (msg.sender != ContractAddresses.COINFLIP && msg.sender != ContractAddresses.GAME) revert OnlyGame();` — Access is correctly limited to COINFLIP or GAME, but the revert uses `OnlyGame()`, which implies only GAME may call. For a function callable by two different contracts, the error name `OnlyGame` misidentifies the expected caller.
**Impact:** Same class as BC-04. Error name mismatch creates confusion during debugging and integration. The `OnlyGame` error is used in three different access contexts: (1) GAME-only (`burnCoin`, via `onlyGame` modifier), (2) COINFLIP-only (`burnForCoinflip`), (3) COINFLIP or GAME (`mintForGame`).

---

### Finding BC-06 — INFO
**Location:** `BurnieCoin.sol` lines 82–84 (`VaultAllowanceSpent` event NatSpec)
**Comment says:**
```
/// @param spender The contract spending from allowance.
```
**Code does:** `vaultMintTo` (line 555) emits `VaultAllowanceSpent(address(this), amount)` — passing `address(this)` (i.e., BurnieCoin itself) as the spender, not the VAULT caller. So the `spender` parameter always receives the BurnieCoin contract address, not the actual spending contract.
**Impact:** The event's `spender` field is always the BurnieCoin contract address, never the actual vault that triggered the spend. An indexer using this event to track which contract consumed allowance would receive incorrect data.

---

### Finding BC-07 — INFO
**Location:** `BurnieCoin.sol` line 525–528 (NatSpec for `vaultEscrow`)
**Comment says:**
```
/// @dev Called by game contract and modules to credit virtual BURNIE to the vault.
```
**Code does:** Lines 530–533 check `sender != ContractAddresses.GAME && sender != ContractAddresses.VAULT` — the VAULT itself is also an authorized caller. The comment omits VAULT as a caller, describing only "game contract and modules."
**Impact:** INFO — the full set of authorized callers is not stated. A developer reading NatSpec would not know VAULT can call this function.

---

### Mint/Burn Access Control Accuracy Confirmation

The following access control checks were explicitly verified:

| Function | Modifier/Check | Allowed Callers | Comment Accurate? |
|----------|---------------|-----------------|-------------------|
| `burnForCoinflip` | inline check | COINFLIP only | Yes (but error name wrong — BC-04) |
| `mintForGame` | inline check | COINFLIP or GAME | Yes (but error name wrong — BC-05) |
| `burnCoin` | `onlyGame` | GAME only | No — comment says affiliate too (BC-03) |
| `vaultMintTo` | `onlyVault` | VAULT only | Yes |
| `vaultEscrow` | inline check | GAME or VAULT | Partially — VAULT omitted from comment (BC-07) |
| `decimatorBurn` | no modifier | Any address (operator-approved) | Yes — open by design |
| `terminalDecimatorBurn` | no modifier | Any address (operator-approved) | Yes — open by design |

---

## BurnieCoinflip

### Finding BCF-01 — LOW
**Location:** `BurnieCoinflip.sol` lines 192–203 (`onlyFlipCreditors` modifier NatSpec)
**Comment says:**
```
/// @dev Allowed callers: GAME (delegatecall modules), BURNIE, AFFILIATE, ADMIN, QUESTS (level quest rewards).
```
**Code does:** The actual check in the modifier allows: `GAME`, `QUESTS`, `AFFILIATE`, `ADMIN`. The address `ContractAddresses.COIN` (BURNIE) is **not included**. The comment incorrectly lists BURNIE as an authorized caller when the code does not permit it.
**Impact:** A reader relying on this NatSpec would believe BurnieCoin can call `creditFlip`/`creditFlipBatch` directly, which is false. An integrator expecting BURNIE to be a creditor would receive `OnlyFlipCreditors` reverts.

---

### Finding BCF-02 — INFO
**Location:** `BurnieCoinflip.sol` line 892–893 (NatSpec for `creditFlip`)
**Comment says:**
```
/// @notice Credit flip to a player (called directly by GAME modules, AFFILIATE, or ADMIN).
```
**Code does:** Uses `onlyFlipCreditors` which allows GAME, QUESTS, AFFILIATE, ADMIN. `QUESTS` is missing from the NatSpec description — level quest completion triggers `creditFlip` through QUESTS contract, which is an important call site.
**Impact:** The QUESTS contract's ability to credit flips (for level quest rewards) is not documented in the function NatSpec.

---

### Finding BCF-03 — INFO
**Location:** `BurnieCoinflip.sol` lines 903–904 (NatSpec for `creditFlipBatch`)
**Comment says:**
```
/// @notice Credit flips to multiple players (called directly by GAME modules, AFFILIATE, or ADMIN).
```
**Code does:** Uses `onlyFlipCreditors` which allows GAME, QUESTS, AFFILIATE, ADMIN. QUESTS is missing from the NatSpec.
**Impact:** Same as BCF-02 — incomplete NatSpec for authorized callers.

---

### Finding BCF-04 — LOW
**Location:** `BurnieCoinflip.sol` lines 352–364 (NatSpec for `claimCoinflipsForRedemption`)
**Comment says:**
```
/// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
```
**Code does:** The function calls `_claimCoinflipsAmount` → `_claimCoinflipsInternal`. Within `_claimCoinflipsInternal`, the `rngLocked_` guard (lines 583–593) only fires when `winningBafCredit != 0` AND `player != ContractAddresses.SDGNRS`. For a non-sDGNRS player calling this path with BAF credits, the RNG lock revert (`revert RngLocked()`) can still trigger. The comment "skips RNG lock" is only accurate for the sDGNRS caller — general players can still be blocked.
**Impact:** A developer building sDGNRS redemption flows for non-sDGNRS players would incorrectly assume this path never reverts on RNG lock. The "skips RNG lock" claim is overstated.

---

### Finding BCF-05 — LOW
**Location:** `BurnieCoinflip.sol` lines 813–814 (inline comment in `processCoinflipPayouts`)
**Comment says:**
```
// ~5% each for extreme bonus outcomes (50% or 150%), rest is [78%, 115%]
// Presale bonus adds +6pp, so max is 156% during presale
```
**Code does:** `rewardPercent = 50` when `roll == 0`. This gives a 50% **bonus**, making total payout 150% of stake (1.5x). The label "50% bonus (1.5x total)" is shown in the code comment at line 817. The higher tier "150% bonus (2.5x total)" matches. However, the outer comment at line 813 says "50% or 150%" as the extreme outcomes without clarifying these are bonus percents, not total-return percents. A reader seeing "50% or 150%" alongside "rewardPercent = 50 / 150" would understand correctly — but "50%" at line 815-816 also has `// Unlucky: 50% bonus (1.5x total)` which is accurate. The presale max: rewardPercent normal max = 115, presale +6 = 121 (not 156). The 150% tier +6 = 156. So "max is 156% during presale" is only reachable on the 1/20 lucky outcome, not the typical range. The comment is technically accurate for the absolute maximum but may mislead about typical presale bonus range.
**Impact:** INFO-level ambiguity — the 156% maximum is accurate only for the lucky (1/20) roll combined with presale. Typical presale max is 121%.

Re-evaluating: the comment says "max is 156% during presale" which is accurate (150 + 6 = 156) for the rare lucky roll. This is not a discrepancy; it states the absolute max. Downgrading to INFO.

**Revised severity: INFO**

---

### Finding BCF-06 — INFO
**Location:** `BurnieCoinflip.sol` line 519 (inline comment in `_claimCoinflipsInternal`)
**Comment says:**
```
// Winnings = principal + (principal * rewardPercent%) where rewardPercent already in percent (not bps).
```
**Code does:**
```solidity
uint256 payout = stake + (stake * uint256(rewardPercent)) / 100;
```
The comment is accurate — rewardPercent is a plain percent (78 means 78%), not basis points. And the formula is correct. However the parenthetical "(not bps)" might mislead readers into thinking bps would mean 7800 — but the actual constants `COINFLIP_EXTRA_MIN_PERCENT = 78` and `COINFLIP_EXTRA_RANGE = 38` confirm this. No discrepancy — comment is accurate.

**Revised: No finding — removing BCF-06.**

---

### Creditor Expansion (v10.1) Verification

The creditor expansion in v10.1 changed from a single creditor to multiple creditors. The following was explicitly checked:

- `onlyFlipCreditors` modifier (lines 192–203): Allows GAME, QUESTS, AFFILIATE, ADMIN. No single-creditor pattern remains in the code.
- No comment describes the creditor as "the creditor" (singular) or references a single-creditor limit.
- Finding BCF-01 documents that BURNIE is incorrectly listed as a creditor in the NatSpec when the code does not include it.
- `creditFlip` and `creditFlipBatch` both use `onlyFlipCreditors` (multi-creditor). Comments on these functions describe them as callable by "GAME modules, AFFILIATE, or ADMIN" — missing QUESTS (BCF-02, BCF-03) but not stale single-creditor language.

**Conclusion:** No stale single-creditor comments remain. The v10.1 expansion is reflected in code. The only issue is BCF-01 (BURNIE listed in NatSpec but not in code).

---

### mintForGame Merger Verification

The `mintForGame` function in BurnieCoin (lines 452–460) was explicitly checked:

- `mintForGame` accepts both COINFLIP and GAME as callers via `if (msg.sender != ContractAddresses.COINFLIP && msg.sender != ContractAddresses.GAME) revert OnlyGame()`.
- In BurnieCoinflip, `burnie.mintForGame(player, mintable)` is called directly (lines 767, 786, 409). No comment in BurnieCoinflip refers to a separate `mintForCoinflip` entry point.
- No stale comment describes `mintForGame` and `mintForCoinflip` as separate functions.
- The merger is cleanly reflected. No comment discrepancy on this point.

---

### VRF / RNG Integration Verification

- `processCoinflipPayouts` (lines 798–886): RNG word used for both win/loss (`rngWord & 1`) and reward percent (`keccak256(rngWord, epoch) % 20`). Comment at line 808 (`// Mix entropy with epoch for unique per-day randomness`) is accurate.
- `flipsClaimableDay` (line 173): Tracks the latest resolved day. Comment absent but variable name is self-documenting.
- RNG lock behavior in `_claimCoinflipsInternal` (lines 583–593): Correctly prevents BAF recording during locked period. Comment at line 569 (`// sDGNRS is excluded from BAF in jackpots`) is accurate.
- `_coinflipLockedDuringTransition` (lines 1024–1041): Comment accurately describes the condition.
- No VRF integration comment discrepancies found beyond what is captured in BCF-04.

---

### Payout Math Verification

The payout formula `payout = stake + (stake * rewardPercent) / 100` appears at lines 518–520 and lines 1007–1009 (view helper). Both are consistent. The comment at line 517 accurately describes the formula.

The recycling bonus: RECYCLE_BONUS_BPS = 75 (0.75%), bonusCap = 1000 ether (1000 BURNIE). Comment at line 1043 says "0.75% bonus, capped at 1000 BURNIE" — accurate.

The afKing recycling bonus: AFKING_RECYCLE_BONUS_BPS = 100 (1.0%). The comment at line 1055 says "Calculate recycling bonus for afKing flip deposits." — accurate.

---

## Summary

**Total findings: 5 LOW, 7 INFO**

*(BCF-05 downgraded to INFO after re-check; BCF-06 removed as no discrepancy found)*

| ID | Severity | Contract | Location | Description |
|----|----------|----------|----------|-------------|
| BC-01 | INFO | BurnieCoin | Lines 183–189 | Orphaned struct doc blocks (PlayerScore, CoinflipDayResult) — structs live in BurnieCoinflip |
| BC-02 | INFO | BurnieCoin | Lines 265–279 | Orphaned BOUNTY STATE section with slot table — bounty state lives in BurnieCoinflip |
| BC-03 | LOW | BurnieCoin | Lines 559–562 | `burnCoin` NatSpec says "DegenerusGame, game, or affiliate" — only GAME has access |
| BC-04 | LOW | BurnieCoin | Line 448 | `burnForCoinflip` uses `revert OnlyGame()` for a COINFLIP-only gate |
| BC-05 | LOW | BurnieCoin | Lines 452–460 | `mintForGame` uses `revert OnlyGame()` for a COINFLIP-or-GAME gate |
| BC-06 | INFO | BurnieCoin | Lines 82–84 | `VaultAllowanceSpent` event emits `address(this)` as spender, not the actual caller |
| BC-07 | INFO | BurnieCoin | Lines 525–528 | `vaultEscrow` NatSpec omits VAULT as authorized caller |
| BCF-01 | LOW | BurnieCoinflip | Lines 192–203 | `onlyFlipCreditors` NatSpec lists BURNIE as allowed — BURNIE is not in the code check |
| BCF-02 | INFO | BurnieCoinflip | Lines 892–893 | `creditFlip` NatSpec omits QUESTS as authorized caller |
| BCF-03 | INFO | BurnieCoinflip | Lines 903–904 | `creditFlipBatch` NatSpec omits QUESTS as authorized caller |
| BCF-04 | LOW | BurnieCoinflip | Lines 352–364 | `claimCoinflipsForRedemption` says "skips RNG lock" — only true for sDGNRS caller |
| BCF-05 | INFO | BurnieCoinflip | Lines 813–814 | Presale max comment (156%) is accurate for lucky roll only; typical presale max is 121% |
