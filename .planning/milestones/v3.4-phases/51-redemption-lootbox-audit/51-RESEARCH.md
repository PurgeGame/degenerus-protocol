# Phase 51: Redemption Lootbox Audit - Research

**Researched:** 2026-03-21
**Domain:** Solidity smart contract security audit -- sDGNRS gambling burn redemption with 50/50 lootbox split
**Confidence:** HIGH

## Summary

The 50/50 sDGNRS redemption lootbox system spans three contracts: `StakedDegenerusStonk.sol` (sDGNRS -- entry point, burn logic, claim logic), `DegenerusGame.sol` (routing, access control, internal ETH reclassification), and `DegenerusGameLootboxModule.sol` (lootbox resolution via delegatecall). The feature was added in commit `3ebd43b5` and incorporates fixes for four HIGH/MEDIUM findings from v3.3 Phase 44 (CP-08, CP-06, Seam-1, CP-07).

The audit scope covers seven requirements (REDM-01 through REDM-07) spanning the 50/50 split routing, gameOver bypass, 160 ETH daily cap enforcement, PendingRedemption slot packing, activity score snapshot immutability, cross-contract access control, and lootbox reclassification accounting. Each requirement maps to specific code sections that have been identified in this research.

**Primary recommendation:** Structure the audit as four plans: (1) 50/50 split routing and gameOver bypass (REDM-01, REDM-02), (2) daily cap enforcement and slot packing (REDM-03, REDM-05), (3) activity score snapshot immutability (REDM-04), and (4) cross-contract access control and lootbox reclassification (REDM-06, REDM-07).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REDM-01 | 50/50 split correctly routes half to direct ETH, half to lootbox | `claimRedemption()` lines 583-595 in StakedDegenerusStonk.sol: `ethDirect = totalRolledEth / 2; lootboxEth = totalRolledEth - ethDirect;` |
| REDM-02 | GameOver burns bypass lootbox (pure ETH/stETH, no BURNIE) | `_deterministicBurnFrom()` lines 470-521: no BURNIE payout (`emit Burn(..., 0)`); `claimRedemption()` line 590: `isGameOver -> ethDirect = totalRolledEth` (no lootbox split) |
| REDM-03 | 160 ETH daily cap per wallet enforced correctly | `_submitGamblingClaimFrom()` line 753: cap check before uint96 cast; `MAX_DAILY_REDEMPTION_EV = 160 ether` (line 227) |
| REDM-04 | Activity score snapshot at submission is immutable through resolution | `_submitGamblingClaimFrom()` lines 759-762: `claim.activityScore` set once (guarded by `== 0`); `claimRedemption()` line 581: reads `claimActivityScore` before delete |
| REDM-05 | PendingRedemption slot packing correct (uint96+uint96+uint48+uint16=256) | Struct definition lines 182-187; cast sites at lines 755-756 |
| REDM-06 | Lootbox reclassification has no ETH transfer (internal accounting only) | Game.sol `resolveRedemptionLootbox()` lines 1808-1822: debits claimableWinnings, credits futurePrizePool; LootboxModule `_resolveLootboxCommon()` awards tickets/BURNIE only |
| REDM-07 | Cross-contract call chain sDGNRS -> Game -> LootboxModule has correct access control at every hop | sDGNRS calls Game (Game checks `msg.sender == SDGNRS` at line 1805); Game calls LootboxModule via delegatecall (runs in Game's context) |
</phase_requirements>

## Standard Stack

### Core (Audit Tooling)
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | Latest | Test framework, invariant fuzzing | Project standard per foundry.toml |
| Solidity | 0.8.34 | Contract language | Project constant |

### Existing Test Infrastructure
| File | Purpose | Coverage |
|------|---------|----------|
| `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` | 7 invariants (INV-01 through INV-07b) on gambling burn lifecycle | ETH segregation, double-claim, period monotonicity, supply, 50% cap, roll bounds, aggregate tracking |
| `test/fuzz/RedemptionGas.t.sol` | Gas benchmarks for burn/resolve/claim lifecycle | Full lifecycle coverage |
| `test/fuzz/handlers/RedemptionHandler.sol` | Fuzz handler for multi-actor redemption scenarios | Burn, resolve, claim operations |

## Architecture Patterns

### Redemption Flow (Full Lifecycle)

```
DURING GAME:
1. Player calls sDGNRS.burn(amount) or sDGNRS.burnWrapped(amount)
2. sDGNRS._submitGamblingClaimFrom():
   - Computes proportional ethValueOwed and burnieOwed
   - Enforces 50% supply cap per period
   - Enforces 160 ETH daily cap per wallet
   - Snapshots activity score (first burn only per period)
   - Burns sDGNRS tokens
   - Segregates ETH/BURNIE in pending tracking variables
   - Stores PendingRedemption struct (1 slot)
3. Next advanceGame -> rngGate (or _gameOverEntropy) resolves the period:
   - Rolls [25-175]% multiplier
   - Adjusts segregated ETH by roll
   - Computes rolled BURNIE, credits to coinflip
   - Stores RedemptionPeriod with roll and flipDay
4. Player calls sDGNRS.claimRedemption():
   - Computes totalRolledEth = (ethValueOwed * roll) / 100
   - 50/50 split: ethDirect = totalRolledEth / 2, lootboxEth = remainder
   - Calls game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)
   - Game debits from sDGNRS's claimableWinnings (internal accounting)
   - Game credits to futurePrizePool (internal accounting)
   - Game delegates to LootboxModule in 5 ETH chunks
   - LootboxModule resolves: awards tickets + BURNIE (no ETH transfer)
   - BURNIE payout conditional on coinflip win
   - Direct ETH paid last

POST-GAMEOVER:
1. Player calls sDGNRS.burn(amount) -> _deterministicBurnFrom()
   - Pure ETH/stETH payout (no BURNIE, no lootbox)
   - Subtracts pendingRedemptionEthValue from totalMoney
2. OR: Player calls claimRedemption() with gameOver=true
   - ethDirect = totalRolledEth (100%, no lootbox split)
```

### Contract Interaction Map

```
StakedDegenerusStonk (sDGNRS)
  |
  |-- burn()/burnWrapped() --> _submitGamblingClaimFrom()
  |       [stores PendingRedemption]
  |
  |-- claimRedemption() --> game.resolveRedemptionLootbox()
  |       [50/50 split calculation]      |
  |                                       |
  DegenerusGame                           |
  |-- resolveRedemptionLootbox() <--------+
  |       [access: msg.sender == SDGNRS]
  |       [debit claimableWinnings[SDGNRS]]
  |       [credit futurePrizePool]
  |       [delegatecall to LootboxModule in 5 ETH chunks]
  |
  DegenerusGameLootboxModule (delegatecall)
  |-- resolveRedemptionLootbox()
  |       [computes EV multiplier from snapshotted activity score]
  |       [applies EV cap (10 ETH per account per level)]
  |       [calls _resolveLootboxCommon: tickets + BURNIE]
  |       [no ETH transfer -- pure internal accounting]
```

### Key Storage Layout

```
StakedDegenerusStonk:
  pendingRedemptions[player]        -> PendingRedemption (1 slot = 256 bits)
  redemptionPeriods[periodIndex]    -> RedemptionPeriod (roll + flipDay)
  pendingRedemptionEthValue         -> total segregated ETH
  pendingRedemptionBurnie           -> total reserved BURNIE
  pendingRedemptionEthBase          -> current unresolved period ETH
  pendingRedemptionBurnieBase       -> current unresolved period BURNIE
  redemptionPeriodSupplySnapshot    -> totalSupply at period start
  redemptionPeriodIndex             -> current period index
  redemptionPeriodBurned            -> tokens burned in current period
```

### PendingRedemption Slot Packing (REDM-05)

```
struct PendingRedemption {
    uint96  ethValueOwed;   // bits [0:95]    - max ~79B ETH
    uint96  burnieOwed;     // bits [96:191]  - max ~79B ETH-equiv
    uint48  periodIndex;    // bits [192:239] - day index
    uint16  activityScore;  // bits [240:255] - score + 1 (0 = not set)
}
// Total: 96 + 96 + 48 + 16 = 256 bits (exactly 1 EVM slot)
```

### Anti-Patterns to Avoid in Audit

- **Examining code in isolation:** The 50/50 split, daily cap, and lootbox reclassification span three contracts. Each hop must be verified end-to-end.
- **Ignoring the uint96 truncation:** `ethValueOwed` is computed as uint256 then cast to uint96. The 160 ETH cap (1.6e20) fits in uint96 (max 7.9e28), but the arithmetic must be verified.
- **Conflating period and day:** A "period" is a `currentDayView()` value (day index from deploy time with 22:57 UTC boundary), not a calendar day. Cross-day boundary analysis must use the actual 22:57 UTC reset time.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Slot packing verification | Manual bit counting | Static analysis of struct + test that `type(PendingRedemption).storageSize == 32` | Compiler handles packing; verify layout empirically |
| Access control verification | Ad hoc caller tracing | Systematic call-chain enumeration with line-ref evidence | Three-hop chains need each hop verified independently |
| Daily cap bypass testing | Manual boundary math | Foundry fuzz tests with bounded timestamps near 22:57 UTC | Fuzzer explores boundary conditions more thoroughly |

## Common Pitfalls

### Pitfall 1: uint96 Truncation in ethValueOwed/burnieOwed
**What goes wrong:** The cap check on line 753 uses uint256 values, but the storage on line 755-756 casts to uint96. If `ethValueOwed` exceeds `uint96.max` (~79B ETH), the truncated value stored could be much smaller than expected.
**Why it happens:** Mixing uint256 arithmetic with packed storage.
**How to avoid:** Verify that the 160 ETH daily cap (1.6e20) combined with reasonable supply and ETH balance cannot produce values exceeding uint96.max (7.9e28). The cap check on line 753 bounds the sum at 160 ETH, which is safe. But also verify `burnieOwed` cannot exceed uint96.max independently -- BURNIE has no explicit cap.
**Warning signs:** Any scenario where BURNIE balance * burn amount / totalSupply exceeds uint96.max.

### Pitfall 2: Unchecked Subtraction in Game.resolveRedemptionLootbox
**What goes wrong:** Line 1811 in DegenerusGame.sol uses `unchecked { claimableWinnings[SDGNRS] = claimable - amount; }`. If `amount > claimable`, this silently underflows.
**Why it happens:** The unchecked block is a gas optimization. The assumption is that sDGNRS always has sufficient claimable balance.
**How to avoid:** Verify that sDGNRS's claimable winnings on Game are always >= the lootbox ETH amount being resolved. The lootbox ETH comes from the segregated `pendingRedemptionEthValue` which was originally computed from sDGNRS's proportional backing. The checked `claimablePool -= amount` on line 1813 provides a secondary guard.
**Warning signs:** Any scenario where claimable debits from other paths reduce sDGNRS's claimable below the pending segregated amount.

### Pitfall 3: Activity Score Mutation Between Submit and Claim
**What goes wrong:** If the activity score could change between `_submitGamblingClaimFrom` (where it's snapshotted) and `claimRedemption` (where it's consumed), the lootbox EV multiplier could be different than intended.
**Why it happens:** Activity score is a live game metric that changes with player actions.
**How to avoid:** Verify the snapshot is read-once-then-frozen. In `_submitGamblingClaimFrom`, `claim.activityScore` is set only when `== 0` (first burn in period). In `claimRedemption`, `claimActivityScore` is read from the struct before `delete`. The snapshot is immutable.
**Warning signs:** Any path that modifies `claim.activityScore` after initial snapshot.

### Pitfall 4: Cross-Day Boundary Abuse for Daily Cap
**What goes wrong:** A player burns 160 ETH at 22:56:59 UTC, then another 160 ETH at 22:57:01 UTC (different periods). This gives 320 ETH in 2 seconds.
**Why it happens:** Day boundary resets at 22:57 UTC, not midnight. Period transitions create a new cap window.
**How to avoid:** This is by-design (one cap per period). The audit should verify this is intentional and document it. The `UnresolvedClaim` check prevents stacking: if the first claim's period is unresolved, the second burn reverts. So this exploit only works if the first period resolves before the second burn -- which requires an `advanceGame` call between them.
**Warning signs:** Automated bots that call advanceGame + burn in quick succession across boundaries.

### Pitfall 5: Rounding in 50/50 Split
**What goes wrong:** `ethDirect = totalRolledEth / 2` loses 1 wei on odd amounts. `lootboxEth = totalRolledEth - ethDirect` captures the extra wei.
**Why it happens:** Integer division truncation.
**How to avoid:** Verify that `ethDirect + lootboxEth == totalRolledEth` always holds. The current code achieves this: `(x/2) + (x - x/2) == x` is always true.
**Warning signs:** None -- this is correctly handled.

### Pitfall 6: gameOver Transition During Active Claims
**What goes wrong:** A player submits a gambling burn during active game, then gameOver triggers before they claim. `claimRedemption()` checks `game.gameOver()` and routes 100% to direct ETH (no lootbox split). This is intentional but must be verified.
**Why it happens:** The gameOver flag can change between burn submission and claim.
**How to avoid:** Verify line 590: `if (isGameOver) { ethDirect = totalRolledEth; }` -- gives 100% direct ETH. Also verify that `rngWordForDay(claimPeriodIndex)` returns a valid word when gameOver (needed for entropy in lootbox path, but if gameOver, the lootbox path is skipped so this is moot).
**Warning signs:** `lootboxEth` is always 0 when `isGameOver == true`, so `resolveRedemptionLootbox` is never called post-gameOver.

## Code Examples

### 50/50 Split (StakedDegenerusStonk.sol:583-595)
```solidity
// Source: StakedDegenerusStonk.sol lines 583-595
uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;

bool isGameOver = game.gameOver();
uint256 ethDirect;
uint256 lootboxEth;
if (isGameOver) {
    ethDirect = totalRolledEth;
} else {
    ethDirect = totalRolledEth / 2;
    lootboxEth = totalRolledEth - ethDirect;
}
```

### Daily Cap Enforcement (StakedDegenerusStonk.sol:747-756)
```solidity
// Source: StakedDegenerusStonk.sol lines 747-756
PendingRedemption storage claim = pendingRedemptions[beneficiary];
if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) {
    revert UnresolvedClaim();
}

// Enforce 160 ETH daily EV cap per wallet
if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

claim.ethValueOwed += uint96(ethValueOwed);
claim.burnieOwed += uint96(burnieOwed);
```

### Access Control Chain (Game.sol:1799-1805)
```solidity
// Source: DegenerusGame.sol lines 1799-1805
function resolveRedemptionLootbox(
    address player,
    uint256 amount,
    uint256 rngWord,
    uint16 activityScore
) external {
    if (msg.sender != ContractAddresses.SDGNRS) revert E();
    if (amount == 0) return;
    // ...
}
```

### Lootbox Reclassification -- No ETH Transfer (Game.sol:1808-1822)
```solidity
// Source: DegenerusGame.sol lines 1808-1822
// Debit from sDGNRS's claimable (ETH stays in Game's balance)
uint256 claimable = claimableWinnings[ContractAddresses.SDGNRS];
unchecked {
    claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount;
}
claimablePool -= amount;

// Credit to future prize pool (respects freeze state)
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext, pFuture + uint128(amount));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next, future + uint128(amount));
}
```

### Activity Score Snapshot (StakedDegenerusStonk.sol:759-762)
```solidity
// Source: StakedDegenerusStonk.sol lines 759-762
// Snapshot activity score on first burn of period (0 = not yet set, stored as score + 1)
if (claim.activityScore == 0) {
    claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Deterministic burn only | Gambling burn with RNG roll [25-175]% | v3.3 (commit 3ebd43b5) | Burns during active game enter gambling path |
| 100% direct ETH payout | 50/50 split (direct + lootbox) | v3.3 (commit 3ebd43b5) | Half of rolled ETH routed to lootbox rewards |
| No daily cap | 160 ETH daily cap per wallet | v3.3 (commit 3ebd43b5) | Prevents single-wallet bank runs |
| No activity score in redemption | Snapshotted activity score for lootbox EV | v3.3 (commit 3ebd43b5) | Lootbox EV scaled by player engagement |

**Fixed v3.3 Findings (Verified in Current Code):**
- **CP-08 (HIGH):** `_deterministicBurnFrom` now subtracts `pendingRedemptionEthValue` (line 487). Fixed.
- **CP-06 (HIGH):** `_gameOverEntropy` now resolves pending redemptions (lines 862, 891 in AdvanceModule). Fixed.
- **Seam-1 (HIGH):** `DGNRS.burn()` requires `gameOver()` (line 171 in DegenerusStonk.sol). Fixed.
- **CP-07 (MEDIUM):** Split-claim design: ETH paid immediately, BURNIE deferred to coinflip. Fixed (lines 611-617 in sDGNRS).

## Open Questions

1. **burnieOwed uint96 overflow without explicit cap**
   - What we know: `ethValueOwed` is capped at 160 ETH via `MAX_DAILY_REDEMPTION_EV`. `burnieOwed` has no explicit cap -- it's computed as `(totalBurnie * amount) / supplyBefore`.
   - What's unclear: Can `burnieOwed` exceed uint96.max (7.9e28)? This depends on the BURNIE/sDGNRS ratio. Initial BURNIE supply is ~1 trillion (1e30). If sDGNRS supply decreases significantly while BURNIE balance remains high, a large burn could theoretically produce a burnieOwed exceeding uint96.max.
   - Recommendation: Audit should compute the maximum possible `burnieOwed` given initial token economics. If overflow is possible, this is a truncation vulnerability (stored value wraps, player claims wrong amount).

2. **unchecked claimableWinnings debit in Game.resolveRedemptionLootbox**
   - What we know: Line 1811 uses unchecked subtraction. The checked `claimablePool -= amount` on line 1813 provides a safety net.
   - What's unclear: Can `claimableWinnings[SDGNRS]` be less than `amount` while `claimablePool` is >= `amount`? This would cause `claimablePool` to succeed but `claimableWinnings[SDGNRS]` to silently underflow to a massive value.
   - Recommendation: Audit should trace all paths that debit sDGNRS's claimableWinnings and verify they maintain `claimableWinnings[SDGNRS] >= pendingRedemptionEthValue / 2` (the lootbox portion). The `claimWinnings` call in `_payEth` could reduce `claimableWinnings[SDGNRS]` before `resolveRedemptionLootbox` is called in the same transaction.

3. **uint128 cast for futurePrizePool credit**
   - What we know: In `resolveRedemptionLootbox` line 1818/1821, `uint128(amount)` is used. If `amount` exceeds uint128.max, this truncates.
   - What's unclear: Maximum lootbox ETH per claim is 160 ETH / 2 = 80 ETH, which fits trivially in uint128. But verify this path is the only source of `amount`.
   - Recommendation: Verify `amount` is bounded by the 160 ETH cap upstream.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with Solidity 0.8.34, via-ir=true |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract RedemptionInvariants -vv` |
| Full suite command | `forge test -vv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REDM-01 | 50/50 split routes correctly | manual (code audit) | N/A -- static analysis of lines 583-595 | N/A |
| REDM-02 | gameOver burns bypass lootbox | manual (code audit) | N/A -- static analysis of lines 470-521, 590 | N/A |
| REDM-03 | 160 ETH daily cap enforced | manual + existing invariant | `forge test --match-test invariant_fiftyPercentCap -vv` | Yes (partial) |
| REDM-04 | Activity score immutable through resolution | manual (code audit) | N/A -- static analysis of lines 759-762, 581 | N/A |
| REDM-05 | PendingRedemption slot packing correct | manual (code audit) | N/A -- struct verification: 96+96+48+16=256 | N/A |
| REDM-06 | Lootbox reclassification no ETH transfer | manual (code audit) | N/A -- static analysis of Game.sol lines 1808-1822 | N/A |
| REDM-07 | Cross-contract access control correct | manual (code audit) | N/A -- call-chain enumeration | N/A |

### Sampling Rate
- **Per task commit:** `forge test --match-contract RedemptionInvariants -vv`
- **Per wave merge:** `forge test -vv`
- **Phase gate:** All audit verdicts documented with line-ref evidence

### Wave 0 Gaps
None -- this is a code audit phase, not an implementation phase. Existing test infrastructure in `RedemptionInvariants.inv.t.sol` and `RedemptionGas.t.sol` provides the test baseline. New invariant tests for the redemption lootbox split specifically are deferred to Phase 52 (INV-03).

## Sources

### Primary (HIGH confidence)
- `contracts/StakedDegenerusStonk.sol` -- Full read (835 lines). Redemption entry point, burn logic, claim logic, PendingRedemption struct, daily cap enforcement.
- `contracts/DegenerusGame.sol` -- Targeted read of `resolveRedemptionLootbox` (lines 1791-1845), `currentDayView`, `rngWordForDay`, `playerActivityScore`.
- `contracts/modules/DegenerusGameLootboxModule.sol` -- Read of `resolveRedemptionLootbox` (lines 717-750), `_lootboxEvMultiplierFromScore` (lines 476-501), `_applyEvMultiplierWithCap` (lines 503-545), `_resolveLootboxCommon` (lines 849-1025).
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Verified CP-06 fix: `_gameOverEntropy` now calls `hasPendingRedemptions`/`resolveRedemptionPeriod` (lines 862, 891).
- `contracts/DegenerusStonk.sol` -- Full read (249 lines). DGNRS wrapper, burn-through, Seam-1 fix.
- `contracts/libraries/GameTimeLib.sol` -- Full read. Day index calculation: resets at 22:57 UTC.

### Secondary (HIGH confidence)
- `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` -- 7 invariants from v3.3 Phase 44.
- `test/fuzz/RedemptionGas.t.sol` -- Gas benchmarks for full lifecycle.
- `.planning/milestones/v3.3-phases/44-delta-audit-redemption-correctness/44-01-finding-verdicts.md` -- v3.3 findings (CP-08, CP-06, Seam-1, CP-07).
- `audit/KNOWN-ISSUES.md` -- Documented design decisions (gambling burn mechanism, split-claim design, 50% supply cap, RNG-locked burn rejection).

## Metadata

**Confidence breakdown:**
- 50/50 split routing (REDM-01): HIGH -- directly readable from code, simple integer arithmetic
- gameOver bypass (REDM-02): HIGH -- clear conditional branching, two separate code paths
- Daily cap (REDM-03): HIGH -- explicit constant and check, but uint96 truncation needs attention
- Activity score snapshot (REDM-04): HIGH -- guard condition (`== 0`) is unambiguous
- Slot packing (REDM-05): HIGH -- struct definition is explicit, compiler enforces layout
- Lootbox reclassification (REDM-06): HIGH -- no ETH transfer instructions in the code path
- Access control (REDM-07): HIGH -- msg.sender checks at each hop, delegatecall runs in Game's context

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (30 days -- stable codebase, no expected changes before C4A)
