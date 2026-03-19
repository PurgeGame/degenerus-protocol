# Phase 38: RNG Delta Security - Research

**Researched:** 2026-03-19
**Domain:** Smart contract RNG security audit -- Solidity 0.8.34, Chainlink VRF V2.5, delegatecall module architecture
**Confidence:** HIGH

## Summary

This phase audits all RNG-adjacent code changes since v3.1 for security: the removal of `rngLocked` guards from four coinflip claim paths, the deletion of `claimCoinflipsTakeProfit`, the replacement of single-slot decimator claim tracking with per-level persistent claims, and the cross-contract implications of these changes combined.

The core safety argument for removing `rngLocked` from claim paths rests on **carry isolation**: `autoRebuyCarry` (the bankroll that bets on future flips) and `claimableStored` (take-profit amounts available for withdrawal) are separate storage fields with separate write paths. Claims only expose `claimableStored` + `mintable` (which is populated from take-profit portions during `_claimCoinflipsInternal`). The carry is never added to `mintable` unless auto-rebuy is being disabled (a path that retains the `rngLocked` guard). The BAF epoch-based guard within `_claimCoinflipsInternal` (lines 551-563) remains as targeted protection during BAF resolution windows.

The decimator change from `lastDecClaimRound` to `decClaimRounds[lvl]` is a storage layout change with no RNG security implications -- it simply allows claims from any historical level rather than only the most recent. Double-claim prevention uses `e.claimed` (set to 1 on claim). The research below provides the detailed code traces, invariants, and attack scenarios needed for the planner.

**Primary recommendation:** Structure the audit as four focused investigations (carry isolation trace, BAF guard enumeration, decimator correctness check, cross-contract dependency matrix) producing a single findings document with severity classifications per requirement.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Attack model**: Two attacker scenarios modeled separately: (1) MEV-aware attacker who can see VRF word in mempool before fulfillRandomWords executes, and (2) compromised VRF operator who knows the word early. Attacker budget: 1000 ETH. Multi-block attacks: Claude's discretion based on per-scenario relevance.
- **Carry isolation verification**: Full code trace of every write to autoRebuyCarry and claimableStored to prove they never cross. Plus a written formal invariant: "carry ETH is never reachable from any claim path". Both the trace and invariant are required deliverables.
- **BAF guard analysis**: Full enumeration of all bypass scenarios (timing, reentrancy, state manipulation). sDGNRS path: verify sDGNRS is ineligible for BAF entirely (not just that the guard is skipped). If sDGNRS is truly ineligible for BAF, no further BAF guard analysis needed for that path.
- **Cross-contract scope**: Audit ALL rngLocked consumers across all contracts (not just the 4 removed paths). Produce a dependency matrix: contract, function, whether it assumed claims were blocked during RNG lock, whether it's still safe without that assumption. Decimator claim persistence: correctness check only (double-claim prevention, ETH accounting works across rounds). Not treated as a new attack vector -- same security posture as before, just different storage layout.

### Claude's Discretion
- Deliverable structure and finding grouping
- Whether to model multi-block MEV attacks (per-scenario judgment)
- Depth of decimator correctness checks beyond double-claim and ETH accounting

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RNG-01 | Removing rngLocked from coinflip claim paths does not open manipulation windows (carry never enters claimable pool verified) | Carry isolation code trace (autoRebuyCarry vs claimableStored write paths); formal invariant documentation |
| RNG-02 | BAF epoch-based guard is sufficient as sole coinflip claim protection during resolution windows | BAF guard enumeration (lines 551-563 of BurnieCoinflip), sDGNRS BAF ineligibility proof, bypass scenario analysis |
| RNG-03 | Persistent decimator claims across rounds do not create RNG-exploitable state | DecClaimRound correctness analysis, double-claim prevention via `e.claimed`, ETH accounting trace |
| RNG-04 | Cross-contract RNG data flow remains safe with all recent changes combined | rngLocked consumer dependency matrix across 6 contracts, combined-change interaction analysis |
</phase_requirements>

## Standard Stack

This is a security audit phase, not an implementation phase. The "stack" is the audit methodology and the contracts under review.

### Contracts Under Review (Primary)
| Contract | File | RNG Relevance |
|----------|------|---------------|
| BurnieCoinflip | `contracts/BurnieCoinflip.sol` | Claim functions, BAF guard, carry isolation, sDGNRS path |
| DegenerusGameAdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` | rngLockedFlag set/clear, VRF request/fulfill, coinflip payout trigger |
| DegenerusGameDecimatorModule | `contracts/modules/DegenerusGameDecimatorModule.sol` | Per-level decClaimRounds, _consumeDecClaim, terminal decimator |

### Contracts Under Review (Cross-Contract)
| Contract | File | rngLocked Usage |
|----------|------|-----------------|
| DegenerusGame | `contracts/DegenerusGame.sol` | rngLocked() view, mint/purchase guards (4 sites), auto-rebuy toggle guards |
| BurnieCoin | `contracts/BurnieCoin.sol` | balanceOfWithClaimable() uses rngLocked to exclude claimable |
| DegenerusGameWhaleModule | `contracts/modules/DegenerusGameWhaleModule.sol` | purchaseDeityPass rngLocked guard |
| DegenerusGameStorage | `contracts/storage/DegenerusGameStorage.sol` | rngLockedFlag storage (EVM slot 0, byte 27) |

### Interfaces (Changed)
| Interface | Change | Impact |
|-----------|--------|--------|
| IBurnieCoinflip | `claimCoinflipsTakeProfit` removed | Function + implementation deleted |
| IDegenerusGame | `futurePrizePoolTotalView` removed | View function deleted |

### Audit Tooling
| Tool | Purpose |
|------|---------|
| Manual code trace | Primary method -- follow every write to carry/claimable storage |
| Hardhat tests | Validation tests exist in `test/unit/BurnieCoinflip.test.js` |
| Foundry fuzz | Invariant tests in `test/fuzz/invariant/` for solvency and composition |

## Architecture Patterns

### Carry Isolation Architecture

The core safety argument rests on the separation of two storage fields in `PlayerCoinflipState`:

```solidity
struct PlayerCoinflipState {
    uint128 claimableStored;     // Take-profit: withdrawable at any time
    uint48 lastClaim;
    uint48 autoRebuyStartDay;
    bool autoRebuyEnabled;
    uint128 autoRebuyStop;
    uint128 autoRebuyCarry;      // Rolling bankroll: bets on future flips
}
```

**Isolation invariant:** "autoRebuyCarry is never reachable from any claim path while auto-rebuy is enabled."

Write paths for `autoRebuyCarry`:
1. `_claimCoinflipsInternal` line 578: `state.autoRebuyCarry = uint128(carry)` -- only when `rebuyActive` and carry changed
2. `_claimCoinflipsInternal` line 420: `state.autoRebuyCarry = 0` -- only when `!rebuyActive` (auto-rebuy OFF), carry moves to `mintable`
3. `_setCoinflipAutoRebuy` line 722: `state.autoRebuyCarry = 0` -- when disabling auto-rebuy, carry moves to `mintable` (this path still has rngLocked guard)

Write paths for `claimableStored`:
1. `settleFlipModeChange` line 219: `state.claimableStored += mintable` -- mintable from _claimCoinflipsInternal
2. `_depositCoinflip` line 260: `state.claimableStored += mintable` -- mintable from _claimCoinflipsInternal
3. `_claimCoinflipsAmount` line 374: `state.claimableStored = uint128(stored - toClaim)` -- deduction on claim

**Critical question:** Can `mintable` from `_claimCoinflipsInternal` ever contain carry?
- When `rebuyActive = true`: carry stays in local `carry` variable, written to `state.autoRebuyCarry` at line 578. `mintable` only receives take-profit reserved amounts (line 503: `mintable += reserved`).
- When `rebuyActive = false` and `oldCarry != 0`: carry is added to mintable at line 419. BUT this path is only reachable when auto-rebuy is already disabled. And auto-rebuy toggling requires rngLocked to be false (line 691).

### BAF Guard Architecture

The BAF (Big Ass Flip) guard is the remaining RNG-sensitive protection in `_claimCoinflipsInternal`:

```solidity
// Lines 542-563 of BurnieCoinflip.sol
if (winningBafCredit != 0 && player != ContractAddresses.SDGNRS) {
    // ... get purchaseInfo ...
    if (
        !inJackpotPhase &&
        !over &&
        lastPurchaseDay_ &&
        rngLocked_ &&
        (purchaseLevel_ % 10 == 0)
    ) {
        revert RngLocked();
    }
    // ... record BAF flip ...
}
```

This guard triggers only when ALL of:
1. Player has winning BAF credit to record
2. Player is NOT sDGNRS
3. Game is NOT in jackpot phase
4. Game is NOT over
5. It IS the last purchase day
6. RNG IS locked
7. Purchase level is a multiple of 10 (BAF resolution levels)

**sDGNRS BAF ineligibility:** `recordBafFlip` in DegenerusJackpots (line 175) returns early for `ContractAddresses.SDGNRS`. The `_claimCoinflipsInternal` check at line 542 (`player != ContractAddresses.SDGNRS`) skips the entire BAF section. Both the caller-side skip and the callee-side early-return confirm sDGNRS cannot participate in BAF.

### Decimator Claim Persistence Architecture

Old (pre-v3.1):
```solidity
// Single claim round tracked
DecClaimRound internal lastDecClaimRound;
```

New (current):
```solidity
// Per-level claim rounds -- persistent, no expiry
mapping(uint24 => DecClaimRound) internal decClaimRounds;
```

Double-claim prevention:
```solidity
// _consumeDecClaim line 371:
if (e.claimed != 0) revert DecAlreadyClaimed();
// ... calculate share ...
e.claimed = 1;  // line 385
```

Terminal decimator uses `e.weightedBurn = 0` as claimed flag (line 993).

### rngLocked Lifecycle

```
_requestRng() / _finalizeRngRequest() --> rngLockedFlag = true
                                          (level incremented if lastPurchaseDay)
    |
    v
rawFulfillRandomWords() --> rngWordCurrent = word (stored, NOT unlocked yet)
    |
    v
advanceGame() --> rngGate() processes word
    |             --> _applyDailyRng() records word
    |             --> coinflip.processCoinflipPayouts() resolves flips
    |             --> _finalizeLootboxRng() records lootbox word
    |
    v
_unlockRng(day) --> rngLockedFlag = false
                    rngWordCurrent = 0
                    vrfRequestId = 0
                    rngRequestTime = 0
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Carry/claimable isolation verification | Ad-hoc reasoning | Systematic code trace of ALL writes to both fields | Missing a single write path invalidates the safety argument |
| BAF bypass enumeration | Checking obvious paths only | Full condition matrix (7 conditions, all must be true to trigger) | Any single condition being false is a bypass -- must verify each is correct |
| rngLocked dependency analysis | Checking removed paths only | Full consumer audit across all 6 contracts | Combined changes may create emergent vectors not visible in isolation |

## Common Pitfalls

### Pitfall 1: Confusing "Carry Enters Mintable" with "Carry Enters Claimable"
**What goes wrong:** Analyst sees carry being added to mintable (line 419) and concludes carry leaks to claims.
**Why it happens:** Line 419 runs when `!rebuyActive`, but the claim paths call `_claimCoinflipsInternal(player, false)` which doesn't change `rebuyActive`. The carry-to-mintable transfer only happens when auto-rebuy is already disabled.
**How to avoid:** Trace the exact state of `rebuyActive` at each call site. When called from `_claimCoinflipsAmount`, the player's `state.autoRebuyEnabled` determines `rebuyActive` -- it's the player's stored state, not an argument.
**Warning signs:** Claiming "carry leaks to claimable during RNG lock" without checking whether auto-rebuy is active at that moment.

### Pitfall 2: Missing the sDGNRS processCoinflipPayouts Path
**What goes wrong:** Analyst overlooks that `processCoinflipPayouts` calls `_claimCoinflipsInternal(ContractAddresses.SDGNRS, false)` at line 846, during active RNG lock (called from advanceGame via rngGate).
**Why it happens:** This path runs during RNG resolution. If BAF guard applied to sDGNRS, it would always revert because rngLocked is true during processing.
**How to avoid:** Verify the sDGNRS skip at line 542 and the recordBafFlip early return at DegenerusJackpots line 175.
**Warning signs:** Analyst doesn't address this path in their BAF guard analysis.

### Pitfall 3: Decimator Double-Claim Across Storage Migration
**What goes wrong:** Analyst assumes old `lastDecClaimRound` data could be orphaned, allowing claims from the old single-round that overlap with new per-level rounds.
**Why it happens:** Storage layout change from single struct to mapping.
**How to avoid:** Verify that the old `lastDecClaimRound` field is no longer referenced anywhere in the codebase (it was replaced entirely). The `TerminalDecClaimRound` struct still uses a single slot `lastTerminalDecClaimRound` for terminal decimator.
**Warning signs:** Focusing on storage migration rather than current code paths.

### Pitfall 4: Assuming rngLocked Removal Affects ETH Decimator Auto-Rebuy
**What goes wrong:** Analyst confuses coinflip auto-rebuy (BURNIE, BurnieCoinflip) with decimator auto-rebuy (ETH, DegenerusGame). The rngLocked removal only affects BurnieCoinflip claim paths.
**Why it happens:** Both systems have auto-rebuy with take-profit, but they operate on different assets via different contracts.
**How to avoid:** Keep the two auto-rebuy systems clearly separated: DegenerusGame.setAutoRebuy (ETH, still has rngLocked guard at line 1563) vs BurnieCoinflip._setCoinflipAutoRebuy (BURNIE, still has rngLocked guard at line 691).
**Warning signs:** Conflating the two systems in the dependency matrix.

### Pitfall 5: Missing the _depositCoinflip BAF Transition Lock
**What goes wrong:** Analyst overlooks that `_coinflipLockedDuringTransition()` (line 985-998) blocks deposits during BAF resolution levels, separate from the rngLocked guards on claims.
**Why it happens:** This is a different lock mechanism using `purchaseInfo()` conditions, not the simple `rngLockedFlag` check.
**How to avoid:** Recognize that BAF protection has two layers: (1) `_coinflipLockedDuringTransition` blocks deposits that would trigger auto-claim, and (2) BAF guard in `_claimCoinflipsInternal` reverts if claims would record BAF credit during resolution.
**Warning signs:** Only analyzing the inline BAF guard without noting the deposit lock.

## Code Examples

### Carry Isolation Proof Trace

```solidity
// === When rebuyActive = true (auto-rebuy ON) ===
// _claimCoinflipsInternal processes days:

// On WIN:
if (rebuyActive) {
    if (takeProfit != 0) {
        uint256 reserved = (payout / takeProfit) * takeProfit;
        mintable += reserved;  // <-- ONLY take-profit goes to mintable
        carry = payout - reserved;  // <-- remainder stays in carry
    } else {
        carry = payout;  // <-- ALL goes to carry
    }
}

// On LOSS:
if (rebuyActive) {
    carry = 0;  // <-- carry zeroed, nothing to mintable
}

// After loop:
if (rebuyActive && oldCarry != carry) {
    state.autoRebuyCarry = uint128(carry);  // <-- carry saved back to storage
}

// === Claim path: _claimCoinflipsAmount ===
uint256 mintable = _claimCoinflipsInternal(player, false);
uint256 stored = state.claimableStored + mintable;
// ^^ Only claimableStored + mintable (take-profit). Carry never appears here.

// === When rebuyActive = false (auto-rebuy OFF) ===
// Entry point: lines 418-421
if (oldCarry != 0) {
    mintable += oldCarry;         // carry moves to mintable
    state.autoRebuyCarry = 0;    // carry zeroed
}
// BUT: toggling auto-rebuy OFF requires rngLocked = false (line 691)
// So carry can only enter mintable when RNG is unlocked.
```

### BAF Guard Condition Matrix

```
BAF guard reverts when ALL conditions are true:
  1. winningBafCredit != 0     -- player has winning flips to record
  2. player != SDGNRS          -- not the sDGNRS address
  3. !inJackpotPhase           -- in purchase phase
  4. !over                     -- game not over
  5. lastPurchaseDay_          -- target met, transitioning
  6. rngLocked_                -- VRF request in flight
  7. purchaseLevel_ % 10 == 0  -- BAF resolution level

If ANY condition is false, the guard does NOT revert.

Key bypass paths (legitimate, not attack vectors):
  - Player has no wins to record -> condition 1 false -> no BAF credit, no guard needed
  - Game in jackpot phase -> condition 3 false -> BAF already resolved
  - Not a BAF level (e.g., level 13) -> condition 7 false -> no BAF to protect
  - RNG not locked -> condition 6 false -> no pending VRF word to front-run
```

### rngLocked Consumer Inventory

```
rngLockedFlag SET:
  AdvanceModule._finalizeRngRequest() line 1207 -- on VRF request

rngLockedFlag CLEARED:
  AdvanceModule._unlockRng() line 1283 -- after daily processing
  AdvanceModule.updateVrfCoordinatorAndSub() line 1271 -- governance emergency

rngLocked() VIEW consumers (DegenerusGame.rngLocked()):
  DegenerusGame.setDecimatorAutoRebuy() line 1542 -- guards toggle
  DegenerusGame._setAutoRebuy() line 1563 -- guards ETH auto-rebuy toggle
  DegenerusGame._setAutoRebuyTakeProfit() line 1578 -- guards ETH take-profit change
  DegenerusGame._setAfKingMode() line 1643 -- guards afKing toggle
  BurnieCoin.balanceOfWithClaimable() line 273 -- excludes claimable when locked
  BurnieCoinflip._setCoinflipAutoRebuy() line 691 -- guards coin auto-rebuy toggle
  BurnieCoinflip._setCoinflipAutoRebuyTakeProfit() line 741 -- guards coin take-profit change

rngLockedFlag DIRECT consumers (via DegenerusGameStorage inheritance):
  AdvanceModule.requestLootboxRng() line 673 -- blocks during daily RNG
  AdvanceModule.reverseFlip() line 1295 -- blocks nudges during lock
  AdvanceModule.advanceGame() line 138 -- level calc depends on flag
  WhaleModule._purchaseDeityPass() line 470 -- blocks deity pass purchase
  BurnieCoinflip._claimCoinflipsInternal() lines 551-562 -- BAF guard (inline)
  BurnieCoinflip._coinflipLockedDuringTransition() line 997 -- deposit lock
  BurnieCoinflip._addDailyFlip() line 630 -- bounty record guard

REMOVED from (the v3.1 changes under audit):
  BurnieCoinflip.claimCoinflips() -- WAS: if (degenerusGame.rngLocked()) revert
  BurnieCoinflip.claimCoinflipsFromBurnie() -- WAS: if (degenerusGame.rngLocked()) revert
  BurnieCoinflip.consumeCoinflipsForBurn() -- WAS: if (degenerusGame.rngLocked()) revert
  BurnieCoinflip.claimCoinflipsTakeProfit() -- DELETED entirely (function + interface)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| rngLocked on ALL claim paths | rngLocked only on carry-exposing paths + BAF guard | v3.1 (pre-current) | Players can transfer/burn BURNIE during RNG lock |
| claimCoinflipsTakeProfit (separate function) | Removed -- use claimCoinflips with amount | v3.1 (pre-current) | Simpler interface, one fewer function |
| lastDecClaimRound (single slot) | decClaimRounds[lvl] (per-level mapping) | v3.1 (pre-current) | Claims persist across rounds, no expiry |
| TerminalDecAlreadyClaimed error | weightedBurn=0 as claimed flag | v3.1 (pre-current) | Terminal dec uses implicit flag, no separate error |

## Open Questions

1. **Interface NatSpec stale on claim functions**
   - What we know: IBurnieCoinflip.sol still has `@custom:reverts RngLocked` on claimCoinflips, claimCoinflipsFromBurnie, consumeCoinflipsForBurn (lines 34, 42, 52)
   - What's unclear: These revert tags are now incorrect -- these functions no longer revert with RngLocked
   - Recommendation: Flag as comment correctness finding (LOW severity) -- may also be caught by Phase 41 comment scan

2. **balanceOfWithClaimable behavior during RNG lock**
   - What we know: BurnieCoin.balanceOfWithClaimable (line 273) still excludes coinflip claimable when rngLocked. But claims now succeed during RNG lock.
   - What's unclear: Whether this creates a UX inconsistency (view returns less than actually claimable)
   - Recommendation: Document as INFO finding -- view function is conservative, no security impact

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (JS tests) + Foundry (Solidity fuzz/invariant) |
| Config file | `hardhat.config.js` + `foundry.toml` |
| Quick run command | `npx hardhat test test/unit/BurnieCoinflip.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RNG-01 | Carry never enters claimable pool during RNG lock | manual-only | N/A -- code trace audit, not runtime test | N/A |
| RNG-02 | BAF guard sufficient as sole protection | manual-only | N/A -- bypass enumeration audit | N/A |
| RNG-03 | Persistent decimator claims safe across rounds | manual-only | N/A -- correctness trace audit | N/A |
| RNG-04 | Cross-contract RNG flow safe with combined changes | manual-only | N/A -- dependency matrix audit | N/A |

**Justification for manual-only:** This phase is a security audit producing written verdicts and findings. The deliverables are code traces, invariants, bypass enumerations, and dependency matrices -- not code changes that need automated testing. Existing tests in `test/unit/BurnieCoinflip.test.js` and fuzz invariants provide baseline coverage; this phase verifies correctness through analysis.

### Sampling Rate
- **Per task commit:** Verify audit document covers all required scenarios
- **Per wave merge:** Cross-reference findings against all 4 requirement IDs
- **Phase gate:** All RNG-01 through RNG-04 have explicit verdicts before verification

### Wave 0 Gaps
None -- this is an audit phase producing documents, not code. Existing test infrastructure is sufficient for validation reference.

## Sources

### Primary (HIGH confidence)
- **Contract source code** (current HEAD): BurnieCoinflip.sol, DegenerusGameAdvanceModule.sol, DegenerusGameDecimatorModule.sol, DegenerusGame.sol, BurnieCoin.sol, DegenerusGameWhaleModule.sol, DegenerusGameStorage.sol, DegenerusJackpots.sol
- **Git diff** (HEAD): Verified exact changes -- 4 rngLocked removals, claimCoinflipsTakeProfit deletion, decimator storage migration, comment updates
- **Interfaces**: IBurnieCoinflip.sol (claimCoinflipsTakeProfit removed), IDegenerusGame.sol (futurePrizePoolTotalView removed)

### Secondary (MEDIUM confidence)
- **Project memory**: `feedback_test_rnglock.md` -- prior analysis of why rngLocked removal is safe (carry isolation rationale)
- **Prior audit context**: v2.1 governance audit verdicts (26 verdicts) provide baseline for cross-contract understanding

### Tertiary (LOW confidence)
- None -- all findings based on direct code analysis

## Metadata

**Confidence breakdown:**
- Carry isolation: HIGH -- direct code trace of all write paths to both fields, invariant is provable from code
- BAF guard: HIGH -- all 7 conditions enumerated from source, sDGNRS exclusion verified at both caller and callee
- Decimator correctness: HIGH -- simple mapping change with clear double-claim prevention
- Cross-contract matrix: HIGH -- all rngLocked consumers enumerated via grep, each analyzed

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (30 days -- contract code is stable, no expected changes during audit)
