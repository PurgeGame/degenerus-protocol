# Phase 44: Delta Audit + Redemption Correctness - Research

**Researched:** 2026-03-20
**Domain:** Smart contract security audit -- gambling burn / sDGNRS redemption system delta (6 files, +383 lines)
**Confidence:** HIGH

## Summary

This phase requires a targeted security audit of 6 changed Solidity files that implement a two-phase gambling burn / sDGNRS redemption mechanism. The system allows players to burn sDGNRS during active gameplay for a randomized payout (25-175% of base ETH value via VRF roll, plus a BURNIE coinflip multiplier). Prior research identified 5 specific findings (CP-08, CP-06, Seam-1, CP-02, CP-07) that must be confirmed or refuted with severity classifications.

The 6 files under audit are: `StakedDegenerusStonk.sol` (797 lines, primary orchestrator), `DegenerusStonk.sol` (243 lines, wrapper), `BurnieCoinflip.sol` (~1100 lines, coinflip mechanics), `DegenerusGameAdvanceModule.sol` (~900 lines, RNG resolution), `interfaces/IStakedDegenerusStonk.sol` (93 lines), and `interfaces/IBurnieCoinflip.sol` (183 lines). The audit scope is the delta between prior-audited code and the current gambling burn additions.

**Primary recommendation:** Execute finding-first: confirm/refute all 5 flagged findings with severity classifications, then trace the full redemption lifecycle, then verify segregation solvency, then verify CEI compliance. Each finding has a specific code location and can be confirmed by direct source comparison. No external tools or libraries are needed -- this is pure code analysis.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DELTA-01 | Redemption accounting -- verify `pendingRedemptionEthValue` segregation reconciles at submit, resolve, and claim | Direct code trace of 3 mutation paths in StakedDegenerusStonk.sol (lines 552-553, 599, 712-713); rounding analysis of per-player vs aggregate computation |
| DELTA-02 | Cross-contract interaction audit -- 4-contract state consistency + reentrancy | CEI analysis of claimRedemption (lines 598-610), _payEth (lines 730-751), _payBurnie (lines 755-765); BURNIE transfer->_claimCoinflipShortfall interaction |
| DELTA-03 | Confirm/refute CP-08 -- deterministic burn double-spend | Direct comparison: _deterministicBurnFrom line 477 vs previewBurn line 633 and _submitGamblingClaimFrom line 695 |
| DELTA-04 | Confirm/refute CP-06 -- stuck claims at game-over | Code trace: _gameOverEntropy (AdvanceModule lines 813-862) does NOT call resolveRedemptionPeriod; only rngGate does (lines 772-779) |
| DELTA-05 | Confirm/refute Seam-1 -- DGNRS.burn() fund trap | Code trace: DegenerusStonk.burn() calls stonk.burn() where msg.sender=DGNRS contract; _submitGamblingClaim records beneficiary=DGNRS address |
| DELTA-06 | Confirm/refute CP-02 -- periodIndex zero sentinel | GameTimeLib.currentDayIndexAt returns `boundary - DEPLOY_DAY_BOUNDARY + 1`, so day 1 is first day; zero sentinel is safe |
| DELTA-07 | Confirm/refute CP-07 -- coinflip resolution stuck-claim | Code trace: claimRedemption requires getCoinflipDayResult(period.flipDay) resolved; flipDay=day+1 set in rngGate line 774; if game ends before day+1 resolves, claim stuck |
| CORR-01 | Full redemption lifecycle trace | Submit (lines 675-727) -> Resolve (lines 545-570) -> Claim (lines 575-613); each state transition documented |
| CORR-02 | Segregation solvency invariant | Prove: pendingRedemptionEthValue <= (ethBal + stethBal + claimableEth) at every step |
| CORR-03 | CEI compliance | claimRedemption deletes claim (line 602) before _payEth (line 605) and _payBurnie (line 609); all external call paths verified |
| CORR-04 | Period state machine -- monotonicity, resolution ordering, 50% supply cap | redemptionPeriodIndex tracks currentDayView(); resolveRedemptionPeriod is called once per period from rngGate; cap uses snapshot (line 682-686) |
| CORR-05 | burnWrapped() supply invariant | burnForSdgnrs decrements DGNRS totalSupply (DegenerusStonk line 238-241); _submitGamblingClaimFrom decrements sDGNRS totalSupply (line 707); both supplies decrease correctly |
</phase_requirements>

## Standard Stack

No new tools are needed. This is a pure code analysis phase.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Solidity 0.8.34 | 0.8.34 | Source language | Project compiler version |
| Foundry | v1.0 | Compilation + test execution | Already installed, foundry.toml configured |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| forge build | Verify compilation after any fix recommendations | After code changes are proposed |
| forge test | Run existing tests to verify no regressions | After any code modification |

### Alternatives Considered
None. This phase is analytical (code reading + reasoning), not tool-driven. Slither and fuzz testing belong to later phases (45-46).

## Architecture Patterns

### Redemption System Architecture (4-Contract Interaction)

```
Player
  |
  v
StakedDegenerusStonk (sDGNRS) [Primary Orchestrator]
  |-- burn() / burnWrapped()
  |     |-- gameOver? -> _deterministicBurnFrom()
  |     |-- !gameOver? -> _submitGamblingClaimFrom()
  |-- claimRedemption()
  |     |-- _payEth() -> game.claimWinnings(), ETH send
  |     |-- _payBurnie() -> coinflip.claimCoinflipsForRedemption(), coin.transfer()
  |-- resolveRedemptionPeriod() [called by Game/AdvanceModule]
  |     |-- Adjusts ETH/BURNIE segregation by roll
  |
DegenerusStonk (DGNRS) [Wrapper]
  |-- burn() -> stonk.burn()  [CAUTION: Seam-1 - beneficiary = DGNRS contract]
  |-- burnForSdgnrs() [called by sDGNRS for burnWrapped path]
  |
DegenerusGameAdvanceModule [Resolution Trigger]
  |-- rngGate() -> coinflip.processCoinflipPayouts() then sdgnrs.resolveRedemptionPeriod()
  |-- _gameOverEntropy() -> coinflip.processCoinflipPayouts() ONLY [CAUTION: CP-06]
  |
BurnieCoinflip [BURNIE Gamble Source]
  |-- processCoinflipPayouts() [resolves daily flip, sets rewardPercent/win]
  |-- getCoinflipDayResult() [view: rewardPercent, win for a day]
  |-- claimCoinflipsForRedemption() [sDGNRS-only, mints BURNIE]
  |-- creditFlip() [credits BURNIE stake for resolved period]
```

### Gambling Burn Lifecycle (3-Phase Commit/Reveal)

**Phase 1 - Submit (Day N):**
- Player calls `burn(amount)` or `burnWrapped(amount)` during active game
- `_submitGamblingClaimFrom` computes proportional ETH/BURNIE share
- ETH/BURNIE values segregated into `pendingRedemptionEthValue/Burnie` accumulators
- Per-player claim stored in `pendingRedemptions[beneficiary]`
- 50% supply cap enforced per period via `redemptionPeriodSupplySnapshot`

**Phase 2 - Resolve (Day N+1, inside advanceGame):**
- `rngGate()` processes VRF word
- Calls `coinflip.processCoinflipPayouts()` first (resolves day N+1 flip)
- Checks `sdgnrs.hasPendingRedemptions()` -- if true:
  - Computes `redemptionRoll = (currentWord >> 8) % 151 + 25` (range [25, 175])
  - Sets `flipDay = day + 1` (day N+2 for coinflip dependency)
  - Calls `sdgnrs.resolveRedemptionPeriod(roll, flipDay)` which adjusts ETH and returns BURNIE to credit
  - Credits BURNIE via `coin.creditFlip(SDGNRS, burnieToCredit)`

**Phase 3 - Claim (Day N+2+, after coinflip resolves):**
- Player calls `claimRedemption()`
- Requires: `claim.periodIndex != 0` (has claim), `period.roll != 0` (period resolved), coinflip day resolved
- ETH payout = `(ethValueOwed * roll) / 100`
- BURNIE payout = flipWon ? `(burnieOwed * roll * (100 + rewardPercent)) / 10000` : 0
- `pendingRedemptionEthValue -= ethPayout` then delete claim then pay

### State Variable Map

| Variable | Scope | Mutations | Invariant |
|----------|-------|-----------|-----------|
| `pendingRedemptionEthValue` | Total segregated ETH across all periods | += submit, adjust at resolve, -= claim | Must equal sum of all pending ethPayouts |
| `pendingRedemptionBurnie` | Total reserved BURNIE | += submit, -= resolve (released to coinflip credit) | Must track BURNIE owed before resolution |
| `pendingRedemptionEthBase` | Current unresolved period ETH base | += submit, = 0 at resolve | Accumulated ETH for current period only |
| `pendingRedemptionBurnieBase` | Current unresolved period BURNIE base | += submit, = 0 at resolve | Accumulated BURNIE for current period only |
| `redemptionPeriodSupplySnapshot` | Supply at period start | = totalSupply on first burn of new period | Static within a period |
| `redemptionPeriodIndex` | Current period identifier | = currentDayView() on first burn of new period | Monotonically advances |
| `redemptionPeriodBurned` | Tokens burned in current period | += amount on each burn, = 0 on period change | Must not exceed snapshot/2 |
| `pendingRedemptions[addr]` | Per-player claim | Stacks within same period, deleted on claim | One active claim per address per period |
| `redemptionPeriods[idx]` | Per-period resolution result | Set once by resolveRedemptionPeriod | roll == 0 means unresolved |

### Anti-Patterns to Avoid in Audit
- **Assuming code paths are symmetric:** `previewBurn` and `_deterministicBurnFrom` MUST compute identically -- they currently do NOT (CP-08)
- **Treating game-over as simple mode switch:** Game-over terminates the VRF loop, orphaning any in-flight two-phase mechanisms
- **Confusing the wrapper and underlying:** DGNRS.burn() and sDGNRS.burn() have different msg.sender contexts
- **Trusting zero-sentinel patterns without verifying domain:** `periodIndex == 0` works only if day index never starts at 0

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CEI verification | Manual read-through only | Structured external-call-graph trace with state-at-call-point annotation | Complex cross-contract call chains (sDGNRS -> BURNIE transfer -> _claimCoinflipShortfall -> coinflip) require systematic tracing |
| Rounding analysis | Informal "looks fine" | Concrete numerical examples with worst-case player counts | Integer division rounding dust accumulates; must prove bounded |
| Finding severity classification | Ad-hoc severity | C4A severity framework: HIGH = direct fund loss or theft; MEDIUM = indirect fund loss or protocol malfunction; LOW/QA = everything else | Consistent classification needed for protocol team decision-making |

## Common Pitfalls

### Pitfall 1: Missing Segregation Deduction in Deterministic Burn (CP-08)
**What goes wrong:** `_deterministicBurnFrom` (line 477) computes `totalMoney = ethBal + stethBal + claimableEth` WITHOUT subtracting `pendingRedemptionEthValue`. `previewBurn` (line 633) correctly subtracts it. Post-gameOver deterministic burns include reserved ETH in their proportional share, creating a double-spend.
**Why it happens:** The deterministic burn path predates the gambling burn system. When gambling burns were added, `previewBurn` was updated but `_deterministicBurnFrom` was not.
**How to avoid:** Line-by-line comparison of every code path that computes totalMoney or totalBurnie. Two paths must be identical in their deduction logic.
**Warning signs:** Different formulas for `totalMoney` in different functions within the same contract.

### Pitfall 2: No Resolution Path at Game-Over (CP-06)
**What goes wrong:** `_gameOverEntropy` (AdvanceModule line 813) calls `coinflip.processCoinflipPayouts()` but does NOT call `sdgnrs.resolveRedemptionPeriod()`. Only `rngGate()` (line 772) calls it. Players with pending gambling burns at game-over have permanently burned sDGNRS with no way to claim.
**Why it happens:** `_gameOverEntropy` was a pre-existing path. The redemption resolution was added to `rngGate()` only, not to the parallel game-over entropy path.
**How to avoid:** Map every code path that processes VRF results and verify each one handles redemption resolution.
**Warning signs:** `Ctrl+F resolveRedemptionPeriod` returns only one call site when there should be two.

### Pitfall 3: DGNRS.burn() Beneficiary Mismatch (Seam-1)
**What goes wrong:** When `DegenerusStonk.burn(amount)` is called, it calls `stonk.burn(amount)` where `msg.sender` = DGNRS contract address. Inside `StakedDegenerusStonk.burn()`, the gambling path records `_submitGamblingClaim(msg.sender, amount)` with `beneficiary = msg.sender = DGNRS contract`. The DGNRS contract has no `claimRedemption()` function, so the claim is permanently orphaned.
**Why it happens:** `burn()` in sDGNRS assumes `msg.sender` is the player. This is true for direct calls but not for proxy calls from DGNRS.
**How to avoid:** Trace `msg.sender` through every cross-contract call chain that reaches `burn()`.
**Warning signs:** Different `msg.sender` values reaching the same function from different entry points.

### Pitfall 4: Coinflip Resolution Dependency (CP-07)
**What goes wrong:** `claimRedemption` requires `getCoinflipDayResult(period.flipDay)` to be resolved, where `flipDay = day + 1`. This coinflip is resolved during the NEXT day's `advanceGame`. If the game ends between period resolution (day N+1) and coinflip resolution (day N+2), the ETH payout is blocked despite not depending on the coinflip outcome.
**Why it happens:** The BURNIE payout depends on the coinflip result, and the check blocks the entire claim (including ETH) rather than allowing partial claims.
**How to avoid:** Analyze every forward dependency in the claim path and verify it can be resolved at boundary conditions (game-over, VRF stall).
**Warning signs:** Claim function requiring data from a future resolution step.

### Pitfall 5: Period Index Zero Sentinel (CP-02) -- LIKELY SAFE
**What goes wrong:** `claimRedemption` uses `claim.periodIndex == 0` as "no claim" sentinel. If `currentDayView()` could return 0, first-day burns would be unclaimable.
**Analysis from code:** `GameTimeLib.currentDayIndexAt()` (line 31-34) computes `currentDayBoundary - DEPLOY_DAY_BOUNDARY + 1`. The `+ 1` ensures day 1 is the first day. `currentDayView()` will NEVER return 0 unless the timestamp is before the deploy boundary (impossible since contract didn't exist). **This finding is LIKELY SAFE** but must be formally verified by checking that `DEPLOY_DAY_BOUNDARY` is set correctly in the deploy pipeline and that no underflow occurs.
**How to verify:** Confirm `(block.timestamp - JACKPOT_RESET_TIME) / 1 days >= DEPLOY_DAY_BOUNDARY` holds for all valid timestamps after deploy.

### Pitfall 6: CEI in _payEth with stETH Fallback
**What goes wrong:** `_payEth` (line 730-751) sends ETH via `player.call{value:}("")` which gives control to the player. However, at this point `pendingRedemptionEthValue` is already decremented and the claim is deleted (lines 599-602). A reentrant `claimRedemption()` would revert with `NoClaim`. Safe -- but must verify no other reentrant path exists.
**How to avoid:** Draw the full state graph at the point of each external call.
**Warning signs:** External calls to player-controlled addresses after state mutations.

### Pitfall 7: BURNIE Transfer Triggers _claimCoinflipShortfall
**What goes wrong:** When `_payBurnie` calls `coin.transfer(player, payBal)`, BURNIE's `transfer()` internally calls `_claimCoinflipShortfall(msg.sender, amount)`. Since `msg.sender` is sDGNRS, this could trigger additional coinflip claims for sDGNRS if balance is insufficient. However, in the `_payBurnie` flow, `payBal = min(amount, burnieBal)`, so sDGNRS always has sufficient balance for step 1. For step 2, coinflip already minted the tokens before the transfer. Safe -- but the interaction must be explicitly documented.
**How to avoid:** Trace every internal callback triggered by external calls (ERC20 transfer hooks, shortfall claims, etc.).

## Code Examples

### CP-08: The Double-Spend Discrepancy

**_deterministicBurnFrom (line 477) -- MISSING deduction:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth;
// ^^^ No subtraction of pendingRedemptionEthValue
uint256 totalBurnie = burnieBal + claimableBurnie;
// ^^^ No subtraction of pendingRedemptionBurnie
```

**previewBurn (line 633) -- CORRECT:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
// ^^^ Correctly subtracts
uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
// ^^^ Correctly subtracts
```

**_submitGamblingClaimFrom (line 695) -- CORRECT:**
```solidity
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
```

### CP-06: Missing Resolution in _gameOverEntropy

**rngGate (lines 770-779) -- HAS resolution:**
```solidity
if (sdgnrs.hasPendingRedemptions()) {
    uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25);
    uint48 flipDay = day + 1;
    uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
    if (burnieToCredit != 0) {
        coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);
    }
}
```

**_gameOverEntropy (lines 822-832) -- MISSING resolution:**
```solidity
currentWord = _applyDailyRng(day, currentWord);
if (lvl != 0) {
    coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day);
}
_finalizeLootboxRng(currentWord);
return currentWord;
// ^^^ No sdgnrs.resolveRedemptionPeriod() call anywhere
```

### Seam-1: DGNRS.burn() Beneficiary = Contract Address

**DegenerusStonk.burn() (line 164-167):**
```solidity
function burn(uint256 amount) external returns (...) {
    _burn(msg.sender, amount);          // Burns DGNRS from player
    (ethOut, stethOut, burnieOut) = stonk.burn(amount);
    // ^^^ msg.sender to sDGNRS.burn() = address(DGNRS), NOT the player
```

**StakedDegenerusStonk.burn() (line 435-441):**
```solidity
function burn(uint256 amount) external returns (...) {
    if (game.gameOver()) {
        return _deterministicBurn(msg.sender, amount);
        // ^^^ msg.sender = DGNRS contract; works for deterministic (sends assets to DGNRS, which forwards)
    }
    _submitGamblingClaim(msg.sender, amount);
    // ^^^ msg.sender = DGNRS contract; records claim under DGNRS address
    // DGNRS has no claimRedemption() -- claim is permanently orphaned
```

### CP-02: Day Index is 1-Based (LIKELY SAFE)

**GameTimeLib.currentDayIndexAt (line 31-34):**
```solidity
function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
    uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
    return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    //                                                                 ^^^
    // The +1 ensures first day = 1, not 0. Zero sentinel is safe.
}
```

### CEI Compliance in claimRedemption

```solidity
function claimRedemption() external {
    // CHECKS
    if (claim.periodIndex == 0) revert NoClaim();            // line 578
    if (period.roll == 0) revert NotResolved();              // line 581
    if (rewardPercent == 0 && !flipWon) revert FlipNotResolved(); // line 585

    // EFFECTS
    pendingRedemptionEthValue -= ethPayout;                  // line 599
    delete pendingRedemptions[player];                       // line 602

    // INTERACTIONS
    _payEth(player, ethPayout);                              // line 605
    if (burniePayout != 0) _payBurnie(player, burniePayout); // line 608-609
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Deterministic-only burn path | Two-phase gambling burn + deterministic post-gameOver | v3.3 gambling burn addition | New attack surface: segregation, stuck claims, cross-contract state |
| No `pendingRedemptionEthValue` | Virtual ETH segregation via accounting variables | v3.3 | Must track through all code paths |
| `stonk.burn()` always instant | `stonk.burn()` deferred during game (gambling), instant after gameOver | v3.3 | DGNRS.burn() proxy call creates beneficiary mismatch |

## Rounding Analysis (Critical for DELTA-01)

The rounding risk in the redemption system:

**At submit:** `ethValueOwed = (totalMoney * amount) / supplyBefore` -- per-player
**At resolve:** `rolledEth = (pendingRedemptionEthBase * roll) / 100` -- aggregate
**At claim:** `ethPayout = (claim.ethValueOwed * roll) / 100` -- per-player

The key invariant: after resolution, does `sum(individual ethPayouts) == rolledEth`?

- `pendingRedemptionEthBase = sum(ethValueOwed_i)` (exact, no rounding)
- `rolledEth = (pendingRedemptionEthBase * roll) / 100`
- Individual payouts: `(ethValueOwed_i * roll) / 100`
- Due to integer division: `sum((x_i * roll) / 100)` may differ from `(sum(x_i) * roll) / 100` by up to N-1 wei (where N = number of claimants)

At resolve, `pendingRedemptionEthValue` is adjusted: `= old - base + rolledEth`. This sets the aggregate. But claims decrement by individual payouts. If individual payouts sum to LESS than rolledEth (due to floor division), the final claimant's `-= ethPayout` leaves residual dust in `pendingRedemptionEthValue`. This dust is harmless (reduces pool for future gamblers by a few wei) but monotonically accumulates. Over many periods with many claimants, it could grow to detectable amounts.

**Severity:** LOW (theoretical dust accumulation, no fund loss). But the invariant test in Phase 45 should bound this.

## Finding Pre-Assessment (to be confirmed/refuted)

| ID | Finding | Pre-Assessment | Severity | Fix Complexity |
|----|---------|----------------|----------|----------------|
| CP-08 | `_deterministicBurnFrom` missing `pendingRedemptionEthValue` deduction | CONFIRMED by code comparison | HIGH | One-line fix x2 |
| CP-06 | `_gameOverEntropy` missing `resolveRedemptionPeriod` call | CONFIRMED by code comparison | HIGH | 5-line addition to _gameOverEntropy |
| Seam-1 | `DGNRS.burn()` records gambling claim under DGNRS address | CONFIRMED by msg.sender trace | HIGH | Revert DGNRS.burn() during active game, or pass player address |
| CP-02 | Period index zero sentinel collision | LIKELY SAFE -- day 1 is first day | LOW/INFO | No fix needed if DEPLOY_DAY_BOUNDARY set correctly |
| CP-07 | Coinflip resolution dependency blocks ETH claim | CONFIRMED by code trace | MEDIUM | Allow partial ETH-only claims or add emergency resolution |

## Cross-Contract Interaction Map

### External Calls from claimRedemption Path

```
claimRedemption()
  |
  +-- coinflip.getCoinflipDayResult(flipDay)  [STATICCALL - safe]
  |
  +-- pendingRedemptionEthValue -= ethPayout   [STATE CHANGE]
  +-- delete pendingRedemptions[player]        [STATE CHANGE]
  |
  +-- _payEth(player, ethPayout)
  |     +-- game.claimWinnings(address(0))     [external call - sends ETH to sDGNRS receive()]
  |     +-- player.call{value: amount}("")     [external call - ETH send to player]
  |     +-- steth.transfer(player, stethOut)   [external call - ERC20 transfer]
  |
  +-- _payBurnie(player, burniePayout)
        +-- coin.transfer(player, payBal)      [external call - triggers _claimCoinflipShortfall]
        |     +-- coinflip.claimCoinflipsFromBurnie(sDGNRS, shortfall)  [only if sDGNRS balance < payBal; won't fire since payBal <= burnieBal]
        +-- coinflip.claimCoinflipsForRedemption(sDGNRS, remaining)  [mints BURNIE to sDGNRS]
        +-- coin.transfer(player, remaining)   [external call - sDGNRS now has sufficient balance]
```

### Reentrancy Analysis

| External Call | Can Reenter claimRedemption? | Why |
|--------------|----------------------------|-----|
| player.call{value:}("") | No | Claim already deleted at line 602 -- reentering hits NoClaim revert |
| steth.transfer() | No | stETH has no callback mechanism |
| coin.transfer() | Possible but safe | BURNIE transfer triggers _claimCoinflipShortfall which calls coinflip.claimCoinflipsFromBurnie -- but this does not call back to sDGNRS. And the claim is already deleted. |
| coinflip.claimCoinflipsForRedemption() | No | Mints BURNIE to sDGNRS; no callback to claimRedemption |
| game.claimWinnings() | No | Sends ETH to sDGNRS receive() which is onlyGame gated |

**CEI verdict: COMPLIANT.** All state modifications occur before external calls. Reentrancy is structurally prevented by claim deletion.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry v1.0 (forge test) |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-path "test/fuzz/*" -v` |
| Full suite command | `forge test -v` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DELTA-01 | pendingRedemptionEthValue reconciles at submit/resolve/claim | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| DELTA-02 | Cross-contract state consistency + reentrancy | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| DELTA-03 | CP-08 confirmed/refuted | manual-only (code comparison) | N/A -- pure audit analysis | N/A |
| DELTA-04 | CP-06 confirmed/refuted | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| DELTA-05 | Seam-1 confirmed/refuted | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| DELTA-06 | CP-02 confirmed/refuted | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| DELTA-07 | CP-07 confirmed/refuted | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| CORR-01 | Full lifecycle trace | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| CORR-02 | Segregation solvency | manual-only (proof) | N/A -- pure audit analysis | N/A |
| CORR-03 | CEI compliance | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| CORR-04 | Period state machine | manual-only (code trace) | N/A -- pure audit analysis | N/A |
| CORR-05 | burnWrapped supply invariant | manual-only (code trace) | N/A -- pure audit analysis | N/A |

**Justification for manual-only:** This phase is an analytical audit producing verdicts (CONFIRMED/REFUTED with severity), not an implementation phase. Automated tests (invariant tests) are Phase 45's scope, deliberately sequenced after this phase's findings are resolved.

### Sampling Rate
- **Per task commit:** `forge build` (compilation check after any proposed fix)
- **Per wave merge:** N/A (audit phase, no code changes planned)
- **Phase gate:** All 12 requirements have verdicts with evidence

### Wave 0 Gaps
None -- this phase produces audit analysis documents, not code. The Foundry infrastructure is already present for Phase 45.

## Open Questions

1. **DEPLOY_DAY_BOUNDARY production value**
   - What we know: Set to 0 in ContractAddresses.sol (placeholder for deploy script)
   - What's unclear: The deploy script patches this. Need to verify the deployed value ensures `currentDayIndexAt >= 1` for all post-deploy timestamps.
   - Recommendation: CP-02 verdict should note dependency on correct deploy pipeline configuration. Mark as SAFE with caveat.

2. **Fix design for CP-06 and CP-07**
   - What we know: Both require protocol team decisions (emergency claim vs game-over hook, partial ETH-only claims vs full block)
   - What's unclear: Which fix the protocol team prefers
   - Recommendation: Document both options with tradeoffs. The audit's job is to confirm the finding and propose fixes; the team chooses.

3. **Fix design for Seam-1**
   - What we know: DGNRS.burn() calling stonk.burn() during active game creates orphaned claim
   - Options: (a) Revert DGNRS.burn() during active game, (b) Route through burnWrapped logic, (c) Pass player address parameter
   - Recommendation: Option (a) is simplest -- DGNRS holders can use burnWrapped() instead during active game. Post-gameOver deterministic path is unaffected.

4. **_payBurnie partial fulfillment**
   - What we know: `claimCoinflipsForRedemption` returns `min(requested, available)`. If it returns less than `remaining`, the subsequent `coin.transfer(player, remaining)` will revert because sDGNRS doesn't have enough BURNIE.
   - What's unclear: Can this actually happen? The BURNIE was credited via `creditFlip` at resolution, then the coinflip day resolved (required for claim). The sDGNRS address's coinflip winnings should cover the amount. But another code path claiming sDGNRS's coinflips (e.g., deterministic burn's `coinflip.claimCoinflips`) could reduce available.
   - Recommendation: Trace the BURNIE solvency path in detail during the audit. This is covered by DELTA-02 and CORR-02.

## Sources

### Primary (HIGH confidence)
- Direct code analysis: `contracts/StakedDegenerusStonk.sol` (797 lines, full review)
- Direct code analysis: `contracts/DegenerusStonk.sol` (243 lines, full review)
- Direct code analysis: `contracts/BurnieCoinflip.sol` (key functions: lines 344-396, 776-860, 867-890, 897-988)
- Direct code analysis: `contracts/modules/DegenerusGameAdvanceModule.sol` (key functions: lines 414-464, 739-799, 813-862)
- Direct code analysis: `contracts/modules/DegenerusGameGameOverModule.sol` (full review, 235 lines)
- Direct code analysis: `contracts/libraries/GameTimeLib.sol` (35 lines, full review)
- Direct code analysis: `contracts/interfaces/IStakedDegenerusStonk.sol` (93 lines)
- Direct code analysis: `contracts/interfaces/IBurnieCoinflip.sol` (183 lines)
- Prior research: `.planning/research/SUMMARY.md`, `.planning/research/PITFALLS.md`

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- requirement definitions and traceability
- `.planning/ROADMAP.md` -- phase ordering rationale
- `foundry.toml` -- test infrastructure configuration

### Tertiary (LOW confidence)
None. All findings are code-derived from direct source analysis.

## Metadata

**Confidence breakdown:**
- Finding pre-assessments: HIGH - based on direct line-by-line code comparison
- Architecture patterns: HIGH - based on full contract read of all 6 files + GameOverModule
- CEI analysis: HIGH - complete external-call-graph trace with state annotation
- Rounding analysis: MEDIUM - theoretical analysis, needs numerical verification in Phase 45 invariant tests
- CP-02 (zero sentinel): MEDIUM - code analysis shows LIKELY SAFE but depends on deploy pipeline correctness

**Research date:** 2026-03-20
**Valid until:** Indefinite (analysis is tied to current code state, not external library versions)
