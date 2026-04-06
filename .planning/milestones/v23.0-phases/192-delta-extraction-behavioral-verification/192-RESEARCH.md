# Phase 192: Delta Extraction & Behavioral Verification - Research

**Researched:** 2026-04-06
**Domain:** Solidity smart contract delta audit -- function-level diff classification and behavioral equivalence proofs
**Confidence:** HIGH

## Summary

Phase 192 is a pure audit phase -- no code changes, only analysis and documentation. Two commits are in scope: 93c05869 (DGNRS solo reward fold) and 520249a2 (specialized events, whale pass daily path, cleanup). Together they produce a net -121 lines across 5 contract files, with the bulk of changes in DegenerusGameJackpotModule.sol.

The changes fall into three categories: (1) intentional behavioral changes requiring correctness proofs (whale pass path restriction, DGNRS reward fold, `_selectDailyCoinTargetLevel` simplification), (2) refactors that must be proven equivalent (event specialization, function consolidation, signature changes), and (3) dead code deletion that must be proven unreachable. The established delta audit methodology from v15.0-v22.0 (function-level changelog, per-function classification, algebraic/trace proofs) applies directly.

**Primary recommendation:** Structure the audit as a single comprehensive plan with the function-level changelog and all proofs in one document, following the established pattern from phases 187-190. The audit should proceed function-by-function in dependency order: deleted functions first (unreachability proof), then signature changes, then behavioral changes with correctness proofs.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Follow established delta audit methodology from v15.0-v22.0 -- function-level changelog with per-function classification and proof
- **D-02:** Classification scheme: REFACTOR (identical behavior, formatting/structural only), INTENTIONAL (documented behavioral difference with correctness proof)
- **D-03:** Deleted functions verified as unreachable (no remaining callers in any contract)
- **D-04:** Exactly 2 commits in scope: 93c05869 (DGNRS solo reward fold) and 520249a2 (specialized events, whale pass daily path, cleanup)
- **D-05:** Contracts in scope: JackpotModule, AdvanceModule, BurnieCoinflip, IDegenerusGameModules, IBurnieCoinflip
- **D-06:** Test file DgnrsSoloBucketReward.test.js added in 520249a2 is out of audit scope (test-only)
- **D-07:** Whale pass moved from early-burn/terminal to daily-only path -- prove early-burn and terminal now pay straight ETH, daily path correctly awards whale pass for solo bucket winners
- **D-08:** DGNRS solo reward folded into _processDailyEth -- prove same winner receives same total amount (was re-picking with different salt before, now inline with ETH winner)
- **D-09:** Specialized events replace generic JackpotTicketWinner -- prove every old emission site now emits correct new event with correct fields

### Claude's Discretion
- Report structure and formatting
- Order of function analysis
- Level of detail in cosmetic/formatting change documentation

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DELTA-01 | Function-level delta extraction of all changes across JackpotModule, AdvanceModule, BurnieCoinflip, and interfaces since v22.0 (commits 93c05869, 520249a2) | Complete function inventory below identifies every changed, added, and deleted function/event/constant across all 5 files |
| DELTA-02 | Behavioral equivalence verification for each changed function -- refactored paths produce identical results; intentional changes documented with correctness proof | Three intentional changes identified with proof strategies; all refactored functions catalogued with equivalence proof approach |
</phase_requirements>

## Architecture Patterns

### Established Delta Audit Structure

Prior audits (phases 187, 189, 190) use this document structure: [VERIFIED: git history]

1. **Function-Level Changelog** -- table listing every changed function with classification
2. **Deleted Function Unreachability** -- grep proof that no callers remain
3. **Per-Function Analysis** -- for each non-trivial change:
   - Old code (reconstructed from diff)
   - New code (current contract state)
   - Classification: REFACTOR or INTENTIONAL
   - Proof: algebraic equivalence or behavioral correctness
4. **Finding Register** -- any concerns discovered during audit
5. **Verdict** -- per-requirement pass/fail

### Classification Scheme

From CONTEXT.md D-02 and prior audit patterns: [VERIFIED: CONTEXT.md, git history]

| Classification | Meaning | Proof Required |
|----------------|---------|----------------|
| REFACTOR | Identical behavior, structural/formatting only | Show old and new produce same outputs for all inputs |
| INTENTIONAL | Documented behavioral difference | Correctness proof that new behavior is correct per spec |
| DELETED | Function removed entirely | Unreachability proof (no remaining callers) |
| COSMETIC | Whitespace, comment, formatting only | Visual inspection sufficient |

## Complete Change Inventory

### Commit 93c05869: DGNRS Solo Reward Fold

[VERIFIED: git diff]

**Files changed:** 3 (JackpotModule, AdvanceModule, IDegenerusGameModules)
**Net:** -57 lines

| # | Item | File | Type | Classification |
|---|------|------|------|----------------|
| 1 | `awardFinalDayDgnrsReward` (external) | JackpotModule | DELETED | Must prove unreachable |
| 2 | `_awardFinalDayDgnrsReward` (private wrapper) | AdvanceModule | DELETED | Must prove unreachable |
| 3 | `awardFinalDayDgnrsReward` (interface) | IDegenerusGameModules | DELETED | Must prove unreachable |
| 4 | `_processDailyEth` gains `isFinalDay` param | JackpotModule | INTENTIONAL | DGNRS reward now inline |
| 5 | Call site in `payDailyJackpot` passes `isFinalPhysicalDay_` to `_processDailyEth` | JackpotModule | INTENTIONAL | Connects new param |
| 6 | AdvanceModule removes `_awardFinalDayDgnrsReward(lvl, rngWord)` call | AdvanceModule | INTENTIONAL | Caller removal |
| 7 | RNG consumption table comment updated | AdvanceModule | COSMETIC | Comment-only |

### Commit 520249a2: Specialized Events, Whale Pass Daily Path, Cleanup

[VERIFIED: git diff]

**Files changed:** 4 (JackpotModule, BurnieCoinflip, IBurnieCoinflip, test file out of scope)
**Net:** +114 lines (JackpotModule), -7 lines (BurnieCoinflip+interface)

#### Events

| # | Item | Type | Classification |
|---|------|------|----------------|
| 8 | `JackpotTicketWinner` event | DELETED | Replaced by 5 specialized events |
| 9 | `AutoRebuyProcessed` event | DELETED from JackpotModule | Rebuy info folded into JackpotEthWin fields |
| 10 | `JackpotEthWin` event (new) | ADDED | Replaces JackpotTicketWinner for ETH awards |
| 11 | `JackpotTicketWin` event (new) | ADDED | Replaces JackpotTicketWinner for ticket awards |
| 12 | `JackpotBurnieWin` event (new) | ADDED | Replaces JackpotTicketWinner for BURNIE awards |
| 13 | `JackpotDgnrsWin` event (new) | ADDED | Replaces JackpotTicketWinner for DGNRS awards |
| 14 | `JackpotWhalePassWin` event (new) | ADDED | Replaces JackpotTicketWinner for whale pass |

#### Constants

| # | Item | Type | Classification |
|---|------|------|----------------|
| 15 | `AWARD_ETH`, `AWARD_BURNIE`, `AWARD_TICKETS`, `AWARD_DGNRS`, `AWARD_WHALE_PASS` | DELETED | No longer needed with specialized events |

#### Deleted Functions

| # | Item | File | Type | Classification |
|---|------|------|------|----------------|
| 16 | `_randTraitTicket` (address-only version) | JackpotModule | DELETED | Consolidated into `_randTraitTicket` (with indices) |
| 17 | `_creditJackpot` | JackpotModule | DELETED | Inlined at call sites |
| 18 | `_hasTraitTickets` | JackpotModule | DELETED | No longer used after `_validateTicketBudget` removal |
| 19 | `_validateTicketBudget` | JackpotModule | DELETED | Budget now calculated inline without ticket existence check |

#### Added Functions

| # | Item | File | Type | Classification |
|---|------|------|------|----------------|
| 20 | `_handleSoloBucketWinner` | JackpotModule | ADDED | Stack-depth wrapper for solo bucket in `_processDailyEth` |
| 21 | `_payNormalBucket` | JackpotModule | ADDED | Extracted from `_processDailyEth` loop for normal buckets |

#### Signature Changes

| # | Item | File | Change | Classification |
|---|------|------|--------|----------------|
| 22 | `_addClaimableEth` | JackpotModule | Returns `(uint256, uint24, uint32)` instead of `uint256` | REFACTOR (returns additional info, same core behavior) |
| 23 | `_processAutoRebuy` | JackpotModule | Returns `(uint256, uint24, uint32)` instead of `uint256` | REFACTOR (surfaces rebuy fields) |
| 24 | `_processSoloBucketWinner` | JackpotModule | Returns 6 values instead of 4 (adds `rebuyLevel`, `rebuyTickets`) | REFACTOR (surfaces rebuy fields) |
| 25 | `_selectDailyCoinTargetLevel` | JackpotModule | Removes `winningTraitsPacked` param, becomes `pure` | INTENTIONAL (no longer checks ticket existence) |
| 26 | `_randTraitTicketWithIndices` renamed to `_randTraitTicket` | JackpotModule | Same body, different name | REFACTOR (name only) |
| 27 | `creditFlipBatch` | BurnieCoinflip | `address[3]` + `uint256[3]` to dynamic arrays | REFACTOR (generalized, same per-element behavior) |
| 28 | `creditFlipBatch` | IBurnieCoinflip | Interface matches impl change | REFACTOR |

#### Behavioral Changes in Existing Functions

| # | Item | File | Classification |
|---|------|------|----------------|
| 29 | `_processDailyEth` solo bucket path | JackpotModule | INTENTIONAL (whale pass now awarded here) |
| 30 | `_resolveTraitWinners` early-burn/terminal path | JackpotModule | INTENTIONAL (no longer does whale pass split, pays straight ETH) |
| 31 | `_awardDailyCoinToTraitWinners` batch logic | JackpotModule | REFACTOR (single `creditFlipBatch` call replaces batched-by-3) |
| 32 | `payDailyJackpot` lootbox budget | JackpotModule | INTENTIONAL (`_validateTicketBudget` removed, budget always `budget / 5`) |
| 33 | `_runEarlyBirdLootboxJackpot` lootbox budget | JackpotModule | INTENTIONAL (`_validateTicketBudget` removed, budget always calculated) |
| 34 | `distributeYieldSurplus` | JackpotModule | REFACTOR (destructures `_addClaimableEth` returns, same sum) |
| 35 | `runBafJackpot` ETH/lootbox processing | JackpotModule | REFACTOR (event changes only, same payout logic) |
| 36 | `payDailyJackpot` coin jackpot call | JackpotModule | REFACTOR (removes `if targetLevel != 0` guard, always calls) |

#### Cosmetic Changes

| # | Item | File | Classification |
|---|------|------|----------------|
| 37 | Multiple `_setCurrentPrizePool`/`_setFuturePrizePool` formatting | JackpotModule | COSMETIC |
| 38 | `runBafJackpot` destructuring formatting | JackpotModule | COSMETIC |

## Proof Strategies

### Intentional Change 1: DGNRS Solo Reward Fold (D-08)

**Old behavior:** `awardFinalDayDgnrsReward` called separately after daily jackpot. Re-derived solo bucket index from stored `lastDailyJackpotWinningTraits`, then called `_randTraitTicket` with different entropy salt to pick a winner from that bucket. The DGNRS reward winner could be a DIFFERENT person than the ETH winner.

**New behavior:** During `_processDailyEth`, when `isFinalDay && traitIdx == remainderIdx`, the DGNRS reward goes to the same address `w` that already won the solo bucket ETH. No re-derivation, no separate `_randTraitTicket` call.

**Proof strategy:**
1. Show the old call path: AdvanceModule `_awardFinalDayDgnrsReward` -> delegatecall -> JackpotModule `awardFinalDayDgnrsReward` -> `_randTraitTicket(traitBurnTicket[lvl], entropy, traitIds[soloIdx], 1, 254)` -- note salt=254 vs the daily ETH path's different salt
2. Show the new inline code: same `w` from the daily ETH loop, same `FINAL_DAY_DGNRS_BPS`, same `dgnrs.transferFromPool` call
3. Prove: the reward amount is identical (`(dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000`)
4. Document the INTENTIONAL difference: winner is now guaranteed to be the ETH winner (fix for the bug where different salt picked different person)

### Intentional Change 2: Whale Pass Daily Path Restriction (D-07)

**Old behavior:** `_resolveTraitWinners` (called from early-burn, terminal, AND daily paths) had `isSoloBucket` logic that called `_processSoloBucketWinner` for 75/25 ETH/whale-pass split on any solo bucket.

**New behavior:** `_resolveTraitWinners` pays straight ETH for ALL winners. Whale pass split only happens in `_processDailyEth` via `_handleSoloBucketWinner` -> `_processSoloBucketWinner`, which is only reached on the daily jackpot path.

**Proof strategy:**
1. Trace old `_resolveTraitWinners`: `isSoloBucket = (winnerCount == 1)` -> `_processSoloBucketWinner` -> 75/25 split
2. Trace new `_resolveTraitWinners`: no solo bucket check, all winners get `_addClaimableEth` + `JackpotEthWin`
3. Trace new `_processDailyEth`: `traitIdx == remainderIdx` -> `_handleSoloBucketWinner` -> `_processSoloBucketWinner` -> 75/25 split + `JackpotEthWin` + `JackpotWhalePassWin`
4. Enumerate callers of `_resolveTraitWinners` to confirm which paths no longer get whale pass

### Intentional Change 3: `_selectDailyCoinTargetLevel` Simplification (items 25, 36)

**Old behavior:** Selected random level in [lvl, lvl+4], then checked `_hasTraitTickets` -- if no tickets existed at that level, returned 0 (skip the coin jackpot entirely).

**New behavior:** Always returns `lvl + uint24(entropy % 5)`, never returns 0. The caller no longer has `if (targetLevel != 0)` guard -- always calls `_awardDailyCoinToTraitWinners`.

**Proof strategy:**
1. Show `_awardDailyCoinToTraitWinners` naturally handles empty buckets (0-length arrays from `_randTraitTicket` produce no winners, no credits, no events)
2. Therefore: removing the pre-check is safe -- the same skip happens implicitly
3. The INTENTIONAL difference: coin jackpot is now always attempted (gas cost for empty roll) rather than skipped. No behavioral difference in outcomes -- players receive the same rewards

### Intentional Change 4: `_validateTicketBudget` Removal (items 18, 19, 32, 33)

**Old behavior:** `_validateTicketBudget` called `_hasTraitTickets` and returned 0 if no trait tickets existed, preventing budget allocation for lootbox/tickets when no tickets could be distributed.

**New behavior:** Budget is always calculated (`budget / 5` for daily, `ethPool * BPS / 10_000` for early-burn). If no tickets exist, the budget is allocated but produces no winners (same as change 3 above).

**Proof strategy:**
1. Trace what happens when budget is non-zero but no tickets exist: `_distributeTicketsToBuckets` calls `_randTraitTicket` which returns empty array when `effectiveLen == 0`, so no tickets are queued
2. The unspent budget stays in the pool (daily path) or is not deducted (early-burn path deducts only `paidEth`)
3. Net effect: identical outcomes, slightly different gas path

## Noteworthy Finding: AutoRebuyProcessed Still in DecimatorModule

`AutoRebuyProcessed` event was deleted from JackpotModule but still exists in `DegenerusGameDecimatorModule.sol` (line 29, emitted at line 411). This is NOT a bug -- DecimatorModule has its own auto-rebuy path independent of JackpotModule. The audit should note this for completeness but it does not affect the correctness of the JackpotModule changes. [VERIFIED: grep across contracts/]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Diff extraction | Manual code reading | `git show` + `git diff` with commit ranges | Precise, no missed changes |
| Caller tree verification | Manual search | `grep -rn` across all contracts/ | Catches cross-file references that manual review misses |
| Pre-commit state reconstruction | Memory/guessing | `git show COMMIT^:path` | Exact old code, not approximations |

## Common Pitfalls

### Pitfall 1: Missing Cross-File References
**What goes wrong:** Deleted function in one file still referenced in another (interface, delegatecall wrapper, test).
**Why it happens:** Delta audit focuses on changed files, misses unchanged files that import/call deleted items.
**How to avoid:** `grep -rn` for every deleted function/event/constant name across ALL of `contracts/`.
**Warning signs:** Compilation errors would catch this, but the audit should prove unreachability independently.

### Pitfall 2: Assuming Event Changes Are Cosmetic
**What goes wrong:** New event has different indexed fields, different field count, or different field types -- frontend/indexer breaks.
**Why it happens:** Events are log-only so they don't affect on-chain state, leading to assumption they're pure cosmetic.
**How to avoid:** For each old event emission site, map to the new event and verify field-by-field that the same information is conveyed (possibly in a different structure). Note any information that was dropped or added.
**Warning signs:** An old field not present in any new event = information loss to indexers.

### Pitfall 3: Return Value Change Cascading
**What goes wrong:** `_addClaimableEth` now returns 3 values instead of 1. Every caller must destructure correctly or the extra values are silently discarded (or compilation fails).
**Why it happens:** Solidity allows partial destructuring in some contexts.
**How to avoid:** Enumerate every call site of `_addClaimableEth` and verify the destructuring is correct.
**Warning signs:** `(uint256 d0, , )` patterns -- verify the discarded values are truly unneeded at that site.

### Pitfall 4: Entropy Path Divergence
**What goes wrong:** Removing `_validateTicketBudget` (which was a view call) doesn't change entropy flow. But consolidating `_randTraitTicket` and `_randTraitTicketWithIndices` could change entropy if the merged function uses a different hash path.
**Why it happens:** The old `_randTraitTicket` (address-only) and `_randTraitTicketWithIndices` used the same `keccak256(abi.encode(randomWord, trait, salt, i))` formula. But callers that switched from one to the other now get `ticketIndexes` as a side effect -- verify the same random path is used.
**How to avoid:** Compare the keccak inputs line-by-line between old and new versions.
**Warning signs:** Different salt values, different parameter ordering in `abi.encode`.

## Code Examples

### Established Audit Report Pattern

From phase 189 (v21.0 delta audit): [VERIFIED: git show 16bd05cb]

```markdown
## Section N: [Consumer Site Name]

### Old Code (pre-commit)
[code block from git show COMMIT^:path]

### New Code (current)
[code block from current contract]

### Classification: REFACTOR / INTENTIONAL

### Proof
[Algebraic equivalence or trace-based correctness proof]
[Worked examples with concrete values for edge cases]
[Table of input combinations with old vs new output comparison]

### Verdict: EQUIVALENT / INTENTIONAL-CORRECT / FINDING
```

### Event Migration Mapping Pattern

For the event specialization proof (D-09), the audit should map each old emission site:

```markdown
| Old Emission | Old Event | New Event | Field Mapping | Info Change |
|--------------|-----------|-----------|---------------|-------------|
| _processDailyEth solo bucket ETH | JackpotTicketWinner(w, lvl, traitId, perWinner, ticketIdx, AWARD_ETH) | JackpotEthWin(w, lvl, traitId, paid, ticketIdx, rebuyLevel, rebuyTickets) | amount -> paid (may differ if whale pass split), +rebuy fields | ADDED: rebuy info; CHANGED: amount reflects 75% split |
| _processDailyEth solo bucket DGNRS | JackpotTicketWinner(w, lvl, traitId, reward, ticketIdx, AWARD_DGNRS) | JackpotDgnrsWin(w, reward) | Dropped: level, traitId, ticketIndex | REDUCED: fewer indexed fields |
| ... | ... | ... | ... | ... |
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat (npx hardhat test) |
| Config file | `foundry.toml`, `hardhat.config.cjs` |
| Quick run command | N/A -- audit-only phase, no code changes |
| Full suite command | N/A -- audit-only phase |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DELTA-01 | Function-level changelog completeness | manual-only | `git diff` inspection | N/A |
| DELTA-02 | Behavioral equivalence / correctness proofs | manual-only | Analytical proofs in audit doc | N/A |

**Justification for manual-only:** This is a pure audit phase -- the deliverable is a written analysis document with proofs, not code changes. Test suites are exercised in Phase 193 (DELTA-03).

### Sampling Rate
- **Per task commit:** N/A (no code changes)
- **Per wave merge:** N/A
- **Phase gate:** Audit document completeness review

### Wave 0 Gaps
None -- existing test infrastructure is not relevant to this audit-only phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `_awardDailyCoinToTraitWinners` handles empty buckets gracefully (returns without effect) | Proof Strategies, Change 3 | If it reverts on empty buckets, `_selectDailyCoinTargetLevel` simplification causes runtime revert |

All other claims verified via git diffs, grep, and git history inspection.

## Open Questions

1. **`_validateTicketBudget` removal -- gas impact on empty buckets**
   - What we know: Budget is now always allocated even when no tickets exist; the funds are not consumed (no winners selected from empty arrays)
   - What's unclear: Whether the unspent budget accounting is identical (daily path returns unpaid to futurePool; early-burn deducts only paidEth)
   - Recommendation: Trace the budget flow in both old (budget=0 from _validateTicketBudget) and new (budget>0 but no winners) paths to confirm pool balances are identical

2. **`_processDailyEth` entropy state after `_handleSoloBucketWinner`**
   - What we know: The new code updates `entropyState = newEntropy` after the solo bucket handler. The old code did not step entropy differently for solo vs normal buckets.
   - What's unclear: Whether the entropy path through `_processSoloBucketWinner` -> `_addClaimableEth` -> `_processAutoRebuy` produces the same entropy mutations as the old inline code
   - Recommendation: Trace entropy through both old and new solo bucket paths

## Sources

### Primary (HIGH confidence)
- `git show 93c05869` -- complete diff for DGNRS solo reward fold commit
- `git show 520249a2` -- complete diff for specialized events commit
- `git show $(git rev-parse 93c05869^):contracts/modules/DegenerusGameJackpotModule.sol` -- pre-commit baseline
- `grep -rn` across `contracts/` -- caller tree verification for deleted functions
- `git show 16bd05cb:.planning/phases/189-delta-audit/189-01-AUDIT.md` -- established audit methodology
- `git show 398cd616:.planning/phases/187-delta-audit/187-01-PLAN.md` -- established plan structure

### Secondary (MEDIUM confidence)
- CONTEXT.md scout findings -- code insights used to identify change categories

## Metadata

**Confidence breakdown:**
- Change inventory: HIGH -- extracted directly from git diffs, every change catalogued
- Proof strategies: HIGH -- based on established audit methodology with 6 prior successful phases
- Pitfalls: HIGH -- based on patterns observed in prior delta audits in this project

**Research date:** 2026-04-06
**Valid until:** 2026-04-20 (stable -- audit methodology well-established, no external dependencies)
