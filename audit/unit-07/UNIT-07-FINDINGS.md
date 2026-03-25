# Unit 7: Decimator System -- Findings Report

**Contract:** DegenerusGameDecimatorModule.sol (930 lines)
**Inherited:** DegenerusGamePayoutUtils.sol (92 lines)
**Phase:** 109-decimator-system
**Date:** 2026-03-25

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 1 |
| LOW | 0 |
| INFO | 0 |
| **TOTAL** | **1** |

**Coverage:** 100% -- All 32 functions analyzed (7 external state-changing, 13 internal helpers, 12 view/pure). Taskmaster coverage review: PASS.

**BAF Pattern Status:** The #1 priority investigation (auto-rebuy BAF pattern in claimDecimatorJackpot) returned **SAFE**. The futurePrizePool read at line 336 is a fresh storage read, not a cached local. No stale-cache overwrite occurs.

---

## Confirmed Findings

### FINDING-01: decBucketOffsetPacked Collision Between Regular and Terminal Decimator

**Severity:** MEDIUM

**Affected Functions:**
- `runDecimatorJackpot()` (L205-256, specifically L248)
- `runTerminalDecimatorJackpot()` (L783-825, specifically L817)
- `_consumeDecClaim()` (L270-293, specifically L281)
- `_consumeTerminalDecClaim()` (L869-893, specifically L881)

**Description:**

Both `runDecimatorJackpot` and `runTerminalDecimatorJackpot` write to the same storage mapping `decBucketOffsetPacked[lvl]` to store their winning subbucket selections. Both `_consumeDecClaim` and `_consumeTerminalDecClaim` read from this same mapping to validate claims.

When GAMEOVER occurs at a level where the regular decimator has already been resolved (levels where `lvl % 100 == 0` or `lvl % 10 == 5 && lvl % 100 != 95`), the terminal decimator resolution overwrites the regular decimator's winning subbucket selections. This is because:

1. `runDecimatorJackpot` writes `decBucketOffsetPacked[lvl]` at L248 during normal jackpot phase.
2. `runTerminalDecimatorJackpot` writes `decBucketOffsetPacked[lvl]` at L817 during GAMEOVER.
3. Both use different RNG words and different burn aggregate sources to select winning subbuckets.
4. After the overwrite, regular decimator claims at that level use the terminal decimator's winning selections.

**Impact:**

At the GAMEOVER level (if regular decimator had previously fired):
- Original regular decimator winners for that level can no longer claim (their subbucket no longer matches the overwritten winning subbucket).
- Non-winners may gain access to the pool if their subbucket happens to match the new terminal selections.
- The `totalBurn` in `decClaimRounds[lvl]` was computed from the ORIGINAL winning subbuckets but claims now validate against the OVERWRITTEN subbuckets, creating a mismatch between the pro-rata denominator and the actual qualifying claimants.

The impact is limited to:
- A single level (the GAMEOVER level)
- Only if regular decimator also fired at that level
- Only affecting unclaimed regular decimator prizes at that specific level

Terminal decimator claims are also affected but in the opposite direction: they would coincidentally use the correct offsets (since B6 wrote last), so terminal claims function correctly.

**Recommendation:**

Store terminal decimator winning subbuckets in a separate storage variable:

```solidity
// Add to DegenerusGameStorage.sol:
mapping(uint24 => uint64) internal terminalDecBucketOffsetPacked;
```

Update `runTerminalDecimatorJackpot` (L817) to write to `terminalDecBucketOffsetPacked[lvl]` instead of `decBucketOffsetPacked[lvl]`.

Update `_consumeTerminalDecClaim` (L881) to read from `terminalDecBucketOffsetPacked[lvl]` instead of `decBucketOffsetPacked[lvl]`.

This eliminates the shared-slot collision with zero gas overhead (the mapping access pattern is identical).

**Evidence:**
- `runDecimatorJackpot` L248: `decBucketOffsetPacked[lvl] = packedOffsets;`
- `runTerminalDecimatorJackpot` L817: `decBucketOffsetPacked[lvl] = packedOffsets;`
- `_consumeDecClaim` L281: `uint64 packedOffsets = decBucketOffsetPacked[lvl];`
- `_consumeTerminalDecClaim` L881: `uint64 packedOffsets = decBucketOffsetPacked[lvl];`
- GameOverModule L139: `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` -- same `lvl` as current level
- EndgameModule L215/L231: `runDecimatorJackpot(decPoolWei, lvl, rngWord)` -- same `lvl` during jackpot phase

---

## Informational Notes

### BAF Pattern: claimDecimatorJackpot Auto-Rebuy Chain

The priority investigation found that the auto-rebuy chain in `claimDecimatorJackpot` (L316-338) is correctly designed to avoid the BAF cache-overwrite pattern. The `_getFuturePrizePool()` read at L336 occurs AFTER all subordinate calls (including auto-rebuy writes to futurePrizePool) have completed. No local variable caches the value before the subordinate call. This is a fresh storage read.

### claimablePool Pre-Reservation

The comment at L397 ("Decimator pool was pre-reserved in claimablePool") was verified: `runRewardJackpots` in EndgameModule adds the decimator spend to `claimableDelta` at L218/L235, which is applied to `claimablePool` at L249. This means the decimator prize pool is correctly reserved in `claimablePool` before any player claims.

### Terminal Decimator Death Clock

The 120-day death clock and 365-day idle timeout produce correct time multiplier values at all boundary conditions. The 1-day burn deadline at L715 prevents burns in the final 24 hours, which is an intentional design choice to prevent last-second gaming of the time multiplier.

---

## Audit Methodology

- **Three-Agent System:** Taskmaster (coverage checklist) -> Mad Genius (adversarial analysis) -> Skeptic (finding validation)
- **Per ULTIMATE-AUDIT-DESIGN.md:** Every state-changing function received full call tree expansion, storage write mapping, cached-local-vs-storage check, and 10-angle attack analysis
- **Anti-Shortcuts:** No function was dismissed as "similar to above." Every call tree was fully expanded. Every storage write was explicitly listed.
- **Coverage:** 100% of state-changing functions in DegenerusGameDecimatorModule.sol analyzed. Taskmaster coverage review: PASS.

---

*Unit 7 findings report completed: 2026-03-25*
*Phase: 109-decimator-system*
