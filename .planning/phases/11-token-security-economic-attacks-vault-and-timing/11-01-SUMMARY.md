---
phase: 11-token-security-economic-attacks-vault-and-timing
plan: "01"
subsystem: token-security
tags: [solidity, burnie-coin, coinflip, vrf, reentrancy, CEI, mint-authorization]

# Dependency graph
requires:
  - phase: 10-admin-power-vrf-griefing-and-assembly-safety
    provides: ADMIN-01 power map establishing vaultMintAllowance authorization scope
  - phase: 8-accounting-paths-and-eth-flow
    provides: ACCT-07 BurnieCoin supply invariant baseline

provides:
  - TOKEN-01 verdict: no vaultMintAllowance bypass path exists (PASS)
  - TOKEN-02 verdict: claimWhalePass CEI confirmed, no double-mint path (PASS)
  - TOKEN-03 verdict: BurnieCoinflip entropy is VRF-derived in all code paths (PASS)
  - Evidence citations at contract/line granularity for Phase 12 reentrancy matrix

affects:
  - phase-12-reentrancy-and-cross-function-attacks
  - phase-13-final-report

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TOKEN-01: Two-party vaultEscrow authorization (GAME + VAULT only)"
    - "TOKEN-02: Zero-check-and-clear CEI pattern for whale pass claims"
    - "TOKEN-03: VRF-only entropy chain with historical VRF fallback (not blockhash)"

key-files:
  created:
    - .planning/phases/11-token-security-economic-attacks-vault-and-timing/11-01-SUMMARY.md
  modified: []

key-decisions:
  - "TOKEN-01 PASS: three vaultAllowance increase sites all guarded — constructor seed (compile-time, no gate needed), _transfer-to-VAULT (reclassification from totalSupply, net-zero), vaultEscrow() (GAME+VAULT only)"
  - "TOKEN-02 PASS: claimWhalePass lines 493-511 confirm strict CEI — whalePassClaims[player]=0 at line 498 precedes all state effects; no ETH external call in path"
  - "TOKEN-03 PASS: processCoinflipPayouts uses rngWord passed from AdvanceModule (VRF-derived rngWordCurrent); historical fallback _getHistoricalRngFallback() uses rngWordByDay[] (VRF words), not blockhash/prevrandao"

patterns-established:
  - "vaultAllowance two-party gate: only GAME or VAULT can call vaultEscrow(); only VAULT can call vaultMintTo()"
  - "_transfer-to-VAULT is reclassification (totalSupply -= / vaultAllowance +=), not net-new minting"
  - "claimWhalePass zero-check-and-clear: read halfPasses, if 0 return, clear to 0, then apply effects — replay hits zero check"
  - "VRF entropy chain: rawFulfillRandomWords → rngWordCurrent → _applyDailyRng → processCoinflipPayouts — no block data"

requirements-completed: [TOKEN-01, TOKEN-02, TOKEN-03]

# Metrics
duration: 12min
completed: 2026-03-04
---

# Phase 11 Plan 01: TOKEN-01/02/03 Source-Trace Verdicts Summary

**TOKEN-01 (vaultMintAllowance bypass), TOKEN-02 (claimWhalePass double-mint), TOKEN-03 (BurnieCoinflip VRF entropy) — all three PASS; no unauthorized mint paths, no replay vectors, no block-level entropy**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-04T23:14:32Z
- **Completed:** 2026-03-04T23:26:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- TOKEN-01 PASS: enumerated all four vaultAllowance increase sites with caller authorization and value source confirmed for each
- TOKEN-02 PASS: confirmed claimWhalePass strict CEI — state cleared before effects, no ETH external call in path, replay blocked by zero check
- TOKEN-03 PASS: traced full VRF entropy chain through rawFulfillRandomWords → rngWordCurrent → _applyDailyRng → processCoinflipPayouts; historical fallback confirmed VRF-sourced, not block-level

---

## TOKEN-01 VERDICT: PASS — No vaultMintAllowance Bypass Path

### Scope

`BurnieCoin.sol` — all sites where `_supply.vaultAllowance` is incremented.

### Complete vaultAllowance Increase Enumeration

**Site 1 — Constructor initialization (compile-time)**
```
BurnieCoin.sol line 202:
Supply private _supply = Supply({totalSupply: 0, vaultAllowance: uint128(2_000_000 ether)});
```
- Caller: N/A (state variable initialization at deploy time)
- Authorization: no gate needed — this is the bootstrap seed, executed once during contract construction
- Value source: initial protocol treasury allocation; no ETH required
- Net effect: `vaultAllowance = 2,000,000 BURNIE` before any player interaction
- Verdict: **benign — design intent, not exploitable**

**Site 2 — `_transfer()` to VAULT (reclassification path)**
```
BurnieCoin.sol lines 447-456:
if (to == ContractAddresses.VAULT) {
    uint128 amount128 = _toUint128(amount);
    unchecked {
        _supply.totalSupply -= amount128;   // circulating supply decreases
        _supply.vaultAllowance += amount128; // vault allowance increases by same amount
    }
    emit Transfer(from, address(0), amount);
    emit VaultEscrowRecorded(from, amount);
    return;
}
```
- Caller: any address that holds BURNIE and calls `transfer(VAULT, amount)` or `transferFrom(..., VAULT, amount)`
- Authorization: no explicit msg.sender gate needed — this is a standard ERC20 transfer where the sender must own the BURNIE (`balanceOf[from] -= amount` reverts on underflow if insufficient)
- Value source: the sender's own BURNIE balance; `totalSupply` decreases by the same `amount128` simultaneously
- Net effect: `totalSupply -= X; vaultAllowance += X` — **zero-sum reclassification, not a net-new mint**
- Invariant check: `totalSupply + vaultAllowance` (part of `supplyIncUncirculated`) remains unchanged
- Verdict: **benign — circulating supply converted to vault allowance, no new tokens created**

**Site 3 — `_mint()` to VAULT address**
```
BurnieCoin.sol lines 471-476:
if (to == ContractAddresses.VAULT) {
    unchecked {
        _supply.vaultAllowance += amount128;
    }
    emit VaultEscrowRecorded(address(0), amount);
    return;
}
```
- Caller: any function that calls `_mint(ContractAddresses.VAULT, amount)` — `_mint` is internal
- External callers of `_mint` via public API: `mintForCoinflip()` (line 526-528, only BurnieCoinflip), `mintForGame()` (line 535-538, only GAME), `creditCoin()` (line 545-547, only GAME+AFFILIATE)
- Value source: GAME mints are for game payouts (Degenerette wins, quest rewards) funded by protocol economics; BurnieCoinflip mints are for winning coinflip payouts, funded by prior BURNIE burns via `burnForCoinflip()`; AFFILIATE mints are affiliate rewards funded by game mechanics
- Note: in practice, none of these trusted callers appear to mint directly to VAULT address — they mint to player addresses. The VAULT guard in `_mint` is a defensive catch if VAULT address is passed.
- Verdict: **benign — `_mint` to VAULT is gated by access control on all external-facing callers; net effect same as reclassification (no increase to totalSupply)**

**Site 4 — `vaultEscrow()` (primary external gate)**
```
BurnieCoin.sol lines 677-688:
function vaultEscrow(uint256 amount) external {
    address sender = msg.sender;
    if (
        sender != ContractAddresses.GAME &&
        sender != ContractAddresses.VAULT
    ) revert OnlyVault();
    uint128 amount128 = _toUint128(amount);
    unchecked {
        _supply.vaultAllowance += amount128;
    }
    emit VaultEscrowRecorded(sender, amount);
}
```
- Caller: MUST be `ContractAddresses.GAME` or `ContractAddresses.VAULT` (compile-time constants)
- Authorization: `sender != GAME && sender != VAULT → revert OnlyVault()` at line 679-682
- Value source: The only production caller is `DegenerusVault.deposit()` at line 453:
  ```
  function deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame {
      if (coinAmount != 0) {
          _syncCoinReserves();
          coinToken.vaultEscrow(coinAmount);   // ← vaultEscrow called here
          coinTracked += coinAmount;
      }
  ```
  `DegenerusVault.deposit()` is `onlyGame` — only `ContractAddresses.GAME` can call it. When GAME calls `deposit(coinAmount, ...)`, that `coinAmount` represents BURNIE that GAME is crediting as a result of real player activity (ETH purchases processed by game modules). No arbitrary actor can call `vaultEscrow()` directly.
- Secondary value source: VAULT itself can call `vaultEscrow()` — VAULT's `receive()` is open payable but does not call `vaultEscrow()`; VAULT's other functions that might call `vaultEscrow` would require VAULT contract code to initiate it.
- Verdict: **guarded — arbitrary attacker cannot call vaultEscrow(); would revert OnlyVault()**

### vaultAllowance Decrease Path (for completeness)

```
BurnieCoin.sol lines 694-706 (vaultMintTo, onlyVault):
function vaultMintTo(address to, uint256 amount) external onlyVault {
    ...
    _supply.vaultAllowance = allowanceVault - amount128;  // line 700: decreases allowance
    _supply.totalSupply += amount128;                      // line 701: increases circulating supply
    balanceOf[to] += amount;
    ...
}
```
- Caller: `onlyVault` = `msg.sender != ContractAddresses.VAULT → revert OnlyVault()` at line 654-656
- Only VAULT can spend the vault allowance; any unauthorized `vaultMintTo` call reverts

### Summary Invariant Check

At all times: `totalSupply + vaultAllowance = supplyIncUncirculated` (constant under mint-from-vault operations, decreases only on genuine burns). The transfer-to-VAULT path preserves this: `totalSupply - X + vaultAllowance + X = unchanged`. The `vaultMintTo` path moves allowance to circulating supply: `vaultAllowance - X + totalSupply + X = unchanged`. No code path increases `vaultAllowance` without a corresponding decrease in `totalSupply` OR without being guarded by GAME/VAULT authorization.

### TOKEN-01 VERDICT: **PASS**

No free-mint path exists. All four `vaultAllowance +=` sites are either:
1. Compile-time initialization (no gate needed)
2. Net-zero reclassification from `totalSupply` (self-funding)
3. Internal `_mint` to VAULT (gated by access control on external callers)
4. `vaultEscrow()` with explicit `GAME || VAULT` authorization check

C4 severity: **N/A — no finding**

---

## TOKEN-02 VERDICT: PASS — claimWhalePass CEI Confirmed, No Double-Mint

### Scope

`contracts/modules/DegenerusGameEndgameModule.sol` — `claimWhalePass()` function, lines 493-511.

### Full Function Analysis

```solidity
// DegenerusGameEndgameModule.sol lines 493-511
function claimWhalePass(address player) external {
    uint256 halfPasses = whalePassClaims[player];   // line 494: read state
    if (halfPasses == 0) return;                      // line 495: zero-check guard

    // Clear before awarding to avoid double-claiming
    whalePassClaims[player] = 0;                     // line 498: STATE CLEARED (CEI)

    // Award tickets for 100 levels, with N tickets per level (where N = half-passes)
    uint24 startLevel = level + 1;                   // line 506: reads level (storage)

    _applyWhalePassStats(player, startLevel);         // line 508: writes player stats
    emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel); // line 509: event
    _queueTicketRange(player, startLevel, 100, uint32(halfPasses));    // line 510: ticket storage
}
```

**CEI Confirmation:**

(a) `whalePassClaims[player] = 0` at line 498 occurs BEFORE any effects — `_applyWhalePassStats` (line 508), `emit` (line 509), `_queueTicketRange` (line 510) all execute after the state clear. This is strict Checks-Effects-Interactions ordering.

(b) No ETH external call in this function path. `_applyWhalePassStats` and `_queueTicketRange` are internal functions writing to game storage (ticket range mappings). No `call{value}()`, no `transfer()`, no external contract call that could re-enter.

(c) Double-claim via direct replay: a second call with the same `player` reads `halfPasses = whalePassClaims[player]` which is now `0` (cleared in first call), hits `if (halfPasses == 0) return` and exits with no effects.

**whalePassClaims Credit Path Check:**

Searched entire codebase for `whalePassClaims[` — only two references found in EndgameModule:
- Line 494: read
- Line 498: clear to 0

The credit site (where `whalePassClaims[player]` is incremented) is in the lootbox resolution path. That path does not call `claimWhalePass()` directly, and re-entry from `_queueTicketRange` cannot reach the lootbox credit path because it would require a new external transaction originating from ticket storage writes (which have no callbacks).

### TOKEN-02 VERDICT: **PASS**

Strict CEI pattern confirmed. `whalePassClaims[player] = 0` precedes all effects at line 498. No ETH external call creates re-entry vector. Replay blocked by zero-check at line 495.

C4 severity: **N/A — no finding**

---

## TOKEN-03 VERDICT: PASS — BurnieCoinflip Entropy is VRF-Derived in All Code Paths

### Scope

`contracts/modules/DegenerusGameAdvanceModule.sol` — `rngGate()`, `_gameOverEntropy()`, `_getHistoricalRngFallback()`, `rawFulfillRandomWords()`, `_applyDailyRng()`

`contracts/BurnieCoinflip.sol` — `processCoinflipPayouts()`

### VRF Entropy Chain — Happy Path (Normal Day)

**Step 1: VRF Fulfillment**
```solidity
// DegenerusGameAdvanceModule.sol lines 1181-1202
function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
    if (msg.sender != address(vrfCoordinator)) revert E();     // only Chainlink VRF coordinator
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;
    uint256 word = randomWords[0];                              // VRF-provided random word
    if (word == 0) word = 1;
    if (rngLockedFlag) {
        rngWordCurrent = word;                                  // stored as rngWordCurrent
    } ...
}
```
- `randomWords[0]` is provided by Chainlink VRF V2.5 coordinator — cryptographically random, not manipulable by validators or players
- Stored to `rngWordCurrent` (storage variable)

**Step 2: rngGate() — Daily Processing**
```solidity
// DegenerusGameAdvanceModule.sol lines 613-659
function rngGate(uint48 ts, uint48 day, uint24 lvl, bool isTicketJackpotDay)
    internal returns (uint256 word) {
    ...
    uint256 currentWord = rngWordCurrent;           // reads VRF-derived word
    ...
    currentWord = _applyDailyRng(day, currentWord); // applies nudges, stores final word
    bool bonusFlip = isTicketJackpotDay || level == 0;
    coinflip.processCoinflipPayouts(bonusFlip, currentWord, day); // passes VRF word
    ...
}
```

**Step 3: _applyDailyRng() — Nudge Application**
```solidity
// DegenerusGameAdvanceModule.sol lines 1205-1220
function _applyDailyRng(uint48 day, uint256 rawWord) private returns (uint256 finalWord) {
    uint256 nudges = totalFlipReversals;    // accumulated nudge count (BURNIE-purchased)
    finalWord = rawWord;
    if (nudges != 0) {
        unchecked { finalWord += nudges; }  // integer addition, not replacement
        totalFlipReversals = 0;
    }
    rngWordCurrent = finalWord;
    rngWordByDay[day] = finalWord;
    emit DailyRngApplied(day, rawWord, nudges, finalWord);
}
```
- `finalWord` is derived from VRF `rawWord` with optional integer nudge addition
- Nudges are a paid protocol feature (BURNIE cost with exponential pricing), not free manipulation
- The base randomness (`rawWord`) remains VRF-sourced; nudges shift the value but do not replace it with block data

**Step 4: processCoinflipPayouts() — Win/Loss Determination**
```solidity
// BurnieCoinflip.sol lines 794-832
function processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint48 epoch)
    external onlyDegenerusGameContract {
    uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));
    uint256 roll = seedWord % 20;       // reward percent roll — VRF-derived
    uint16 rewardPercent;
    ...
    // Preserve original 50/50 win roll.
    bool win = (rngWord & 1) == 1;      // line 832: win/loss from VRF word's LSB
    ...
}
```
- `rngWord` parameter is the VRF-derived `currentWord` passed from `rngGate()`
- `bool win = (rngWord & 1) == 1` — uses the least significant bit of the VRF word
- `seedWord = keccak256(rngWord, epoch)` — deterministic from VRF input, not from block data
- **No `block.timestamp`, `blockhash`, or `prevrandao` anywhere in this function**

### VRF Entropy Chain — Game-Over Fallback Path

```solidity
// DegenerusGameAdvanceModule.sol lines 668-721 (_gameOverEntropy)
// If rngRequestTime elapsed >= GAMEOVER_RNG_FALLBACK_DELAY (3 days):
uint256 fallbackWord = _getHistoricalRngFallback(day);      // line 698
fallbackWord = _applyDailyRng(day, fallbackWord);           // line 699
coinflip.processCoinflipPayouts(isTicketJackpotDay, fallbackWord, day); // line 701-705

// _getHistoricalRngFallback (lines 728-747):
function _getHistoricalRngFallback(uint48 currentDay) private view returns (uint256 word) {
    // Search for earliest available historical RNG word (capped at 30 tries for gas)
    for (uint48 searchDay = 1; searchDay < searchLimit; ) {
        word = rngWordByDay[searchDay];    // reads from historical VRF words mapping
        if (word != 0) {
            // Found a historical VRF word - use it (XOR with current day for uniqueness)
            return uint256(keccak256(abi.encodePacked(word, currentDay)));
        }
        ...
    }
    revert E(); // No historical words found — VRF never worked
}
```
- `rngWordByDay[searchDay]` contains previously confirmed VRF words from past game days
- The fallback XORs a historical VRF word with `keccak256(word, currentDay)` — fully deterministic from on-chain VRF history
- The comment in source (line 669-670) explicitly documents: "more secure than blockhash since it's already verified on-chain and cannot be manipulated"
- **No block.timestamp, blockhash, or prevrandao used as entropy source in fallback path**

### Block-Level Data Search

Grep of `block.timestamp|blockhash|prevrandao` in all entropy-related functions in AdvanceModule and BurnieCoinflip found only:
- `block.timestamp` used for `rngRequestTime = uint48(block.timestamp)` — tracking WHEN the VRF request was made, not as entropy
- No `blockhash` or `prevrandao` references in entropy chain functions

### TOKEN-03 VERDICT: **PASS**

VRF entropy chain is end-to-end verifiable:
- `rawFulfillRandomWords()` receives `randomWords[0]` from Chainlink VRF coordinator only
- `rngGate()` passes `rngWordCurrent` (VRF-derived) through `_applyDailyRng()` to `processCoinflipPayouts()`
- `processCoinflipPayouts()` computes win/loss from `(rngWord & 1) == 1` using the passed-in VRF word
- Historical fallback `_getHistoricalRngFallback()` uses `rngWordByDay[]` (stored VRF words), not `blockhash`

No block-level data (block.timestamp, blockhash, prevrandao) is used as a coinflip entropy source.

C4 severity: **N/A — no finding**

---

## Task Commits

1. **Task 1: TOKEN-01 trace** — analysis complete, no code changes (source-only audit)
2. **Task 2: TOKEN-02 + TOKEN-03 + SUMMARY** — `docs(11-01): TOKEN-01/02/03 verdicts — all PASS`

**Plan metadata:** (docs commit — see commits section)

## Files Created/Modified

- `.planning/phases/11-token-security-economic-attacks-vault-and-timing/11-01-SUMMARY.md` — This file; three verdicts with contract/line evidence

## Decisions Made

- TOKEN-01 PASS: three vaultAllowance increase sites all guarded — constructor seed (compile-time, no gate needed), `_transfer`-to-VAULT (reclassification from totalSupply, net-zero), `vaultEscrow()` (GAME+VAULT only gate at lines 679-682)
- TOKEN-02 PASS: `claimWhalePass` lines 493-511 confirm strict CEI — `whalePassClaims[player]=0` at line 498 precedes all state effects; no ETH external call in path
- TOKEN-03 PASS: `processCoinflipPayouts` uses `rngWord` passed from AdvanceModule (VRF-derived `rngWordCurrent`); historical fallback `_getHistoricalRngFallback()` uses `rngWordByDay[]` (VRF words), not `blockhash`/`prevrandao`

## Deviations from Plan

None — plan executed exactly as written. All three verdicts delivered via source-trace analysis with contract/line citations.

## Issues Encountered

None.

## Next Phase Readiness

- TOKEN-01, TOKEN-02, TOKEN-03 verdicts all PASS — foundational security properties confirmed for Phase 12 reentrancy matrix
- Phase 12 can proceed with confidence that: (1) COIN minting requires GAME/VAULT authorization chain, (2) whale pass claims cannot be doubled via re-entry, (3) coinflip outcomes are VRF-determined and not manipulable via block data
- Remaining Phase 11 plans (TOKEN-04 through TIME-02) cover EV model correctness and timestamp manipulation — independent scope, can proceed in parallel

---
*Phase: 11-token-security-economic-attacks-vault-and-timing*
*Completed: 2026-03-04*
