# Phase 97: Comment Cleanup - Research

**Researched:** 2026-03-25
**Domain:** Solidity NatSpec, inline comments, storage layout documentation
**Confidence:** HIGH

## Summary

Phase 97 addresses CMT-01: ensuring NatSpec and inline comments are accurate for all functions modified during chunk removal (Phase 95) and analyzed during gas optimization (Phase 96). The chunk removal commit (`e4b96aa4`) modified 3 Solidity files across 6 specific code regions, and the gas analysis documented behavior of 8 functions in the daily jackpot hot path.

The research found **10 specific comment issues** requiring correction. The most critical is the **storage layout header comment in DegenerusGameStorage.sol** (lines 34-66), which still describes the pre-removal Slot 0/1 layout -- placing `dailyEthPhase` and `compressedJackpotFlag` in Slot 1 when they actually packed into Slot 0 after `dailyEthBucketCursor` was removed. The authoritative layout from `forge inspect DegenerusGame storage` shows Slot 0 is now fully packed at 32 bytes (not "30 bytes used, 2 bytes padding") and Slot 1 starts with `purchaseStartDay` at 25 bytes used (not 27).

The remaining issues are: one stale "prior chunk" inline comment in `payDailyJackpot`, the function name `_processDailyEthChunk` retaining "Chunk" when chunking no longer exists, the section heading "Daily Jackpot ETH -- Distribution" which was partially updated but the function name was not, and two stale references to removed symbols in `audit/v3.8-commitment-window-inventory.md` (out of scope for contract comments but worth noting).

**Primary recommendation:** Fix all 10 comment issues in a single pass across the 3 affected contract files. The function rename (`_processDailyEthChunk` -> `_processDailyEth`) requires updating 3 call sites. Total scope is small -- approximately 40 lines of comment edits across 3 files.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CMT-01 | NatSpec and inline comments accurate for all modified functions | Research identified 10 specific comment issues across 3 contract files. All issues catalogued with exact line numbers, current text, and corrected text. |
</phase_requirements>

## Findings Inventory

### Complete List of Stale/Inaccurate Comments

Every issue below was found by cross-referencing the chunk removal diff (`e4b96aa4`) against the current contract source, verified against `forge inspect DegenerusGame storage` for storage layout claims.

#### Issue 1: Storage Layout Header -- Slot 0 (CRITICAL)

| Property | Value |
|----------|-------|
| **File** | `contracts/storage/DegenerusGameStorage.sol` |
| **Lines** | 34-52 |
| **Problem** | Header comment says Slot 0 has "30 bytes used (2 bytes padding)" and stops at `dailyJackpotCoinTicketsPending` at offset [29:30], with offsets [30:32] marked as padding. In reality, `dailyEthPhase` (uint8) now sits at Slot 0 offset 30 and `compressedJackpotFlag` (uint8) at offset 31. Slot 0 is now fully packed at 32 bytes, 0 bytes padding. |
| **Root cause** | Chunk removal deleted `dailyEthBucketCursor` (was at Slot 0 offset 30), causing `dailyEthPhase` and `compressedJackpotFlag` to shift up from Slot 1 into the freed Slot 0 space. The header comment was partially updated (removed `dailyEthBucketCursor` line) but the padding and total were left stale. |
| **Verification** | `forge inspect DegenerusGame storage` confirms: `dailyEthPhase` at Slot 0 offset 30, `compressedJackpotFlag` at Slot 0 offset 31. |
| **Fix** | Add `dailyEthPhase` and `compressedJackpotFlag` entries to Slot 0 map. Change total to "32 bytes used (0 bytes padding)". Remove padding line. |

#### Issue 2: Storage Layout Header -- Slot 1 (CRITICAL)

| Property | Value |
|----------|-------|
| **File** | `contracts/storage/DegenerusGameStorage.sol` |
| **Lines** | 54-66 |
| **Problem** | Header says Slot 1 starts with `dailyEthPhase` at [0:1] and `compressedJackpotFlag` at [1:2], then `purchaseStartDay` at [2:8], etc., totaling "27 bytes used (5 bytes padding)". In reality, Slot 1 starts with `purchaseStartDay` at offset 0, and totals 25 bytes used (7 bytes padding). |
| **Root cause** | `dailyEthPhase` and `compressedJackpotFlag` migrated to Slot 0. The header was not updated to reflect their departure from Slot 1. |
| **Verification** | `forge inspect` confirms: `purchaseStartDay` at Slot 1 offset 0, `price` at offset 6, `ticketWriteSlot` at offset 22, `ticketsFullyProcessed` at offset 23, `prizePoolFrozen` at offset 24. |
| **Fix** | Remove `dailyEthPhase` and `compressedJackpotFlag` from Slot 1 map. Shift remaining offsets: `purchaseStartDay` [0:6], `price` [6:22], `ticketWriteSlot` [22:23], `ticketsFullyProcessed` [23:24], `prizePoolFrozen` [24:25]. Total "25 bytes used (7 bytes padding)". |

#### Issue 3: Section Header Comment -- Slot 1 Variables

| Property | Value |
|----------|-------|
| **File** | `contracts/storage/DegenerusGameStorage.sol` |
| **Lines** | 283-285 |
| **Problem** | Comment says "EVM SLOT 1: ETH Phase, Price, and Double-Buffer Fields" and "Packs into EVM Slot 1: dailyEthPhase through prizePoolFrozen (27 bytes used, 5 bytes padding)." ETH Phase (`dailyEthPhase`) is now in Slot 0, and the byte counts are wrong. |
| **Fix** | Change to "EVM SLOT 1: Price and Double-Buffer Fields" and "Packs into EVM Slot 1: purchaseStartDay through prizePoolFrozen (25 bytes used, 7 bytes padding)." |

#### Issue 4: Slot 0 Tail Comment

| Property | Value |
|----------|-------|
| **File** | `contracts/storage/DegenerusGameStorage.sol` |
| **Lines** | 279-280 |
| **Problem** | Comment says "dailyJackpotCoinTicketsPending (1 byte) is the tail of Slot 0 (byte 30), followed by 2 bytes of padding." The tail is now `compressedJackpotFlag` at byte 31 with 0 bytes of padding. |
| **Fix** | Remove this comment entirely. The header comment (once fixed per Issue 1) already documents the layout completely. Or update to: "dailyEthPhase and compressedJackpotFlag fill the remaining Slot 0 bytes (offsets 30-31). No padding." |

#### Issue 5: Stale "prior chunk" Inline Comment

| Property | Value |
|----------|-------|
| **File** | `contracts/modules/DegenerusGameJackpotModule.sol` |
| **Line** | 322 |
| **Current** | `// Check if resuming from a prior chunk` |
| **Problem** | References "chunk" -- chunking no longer exists. The `isResuming` check now detects whether a Phase 1 carryover distribution was interrupted (the only remaining multi-call scenario). |
| **Fix** | `// Check if resuming an interrupted daily jackpot (Phase 1 carryover)` |

#### Issue 6: Function Name `_processDailyEthChunk`

| Property | Value |
|----------|-------|
| **File** | `contracts/modules/DegenerusGameJackpotModule.sol` |
| **Lines** | 1329, 495, 565 (definition + 2 call sites) |
| **Problem** | Function name contains "Chunk" but chunking was removed. The function now always processes all 4 buckets in a single call. |
| **Fix** | Rename to `_processDailyEth`. Update 3 locations: definition (line 1329), call in Phase 0 (line 495), call in Phase 1 (line 565). |

#### Issue 7: NatSpec on `_processDailyEthChunk`

| Property | Value |
|----------|-------|
| **File** | `contracts/modules/DegenerusGameJackpotModule.sol` |
| **Line** | 1328 |
| **Current** | `/// @dev Processes daily jackpot ETH winners across all 4 trait buckets.` |
| **Problem** | The NatSpec was updated during chunk removal (previously mentioned chunking), but the function name still says "Chunk". After rename, the NatSpec should match. Additionally, missing `@param` and `@return` annotations. |
| **Fix** | Add full NatSpec: `@param lvl`, `@param ethPool`, `@param entropy`, `@param traitIds`, `@param shareBps`, `@param bucketCounts`, `@return paidEth`. |

#### Issue 8: Section Heading in JackpotModule

| Property | Value |
|----------|-------|
| **File** | `contracts/modules/DegenerusGameJackpotModule.sol` |
| **Lines** | 1324-1325 |
| **Current** | `// Daily Jackpot ETH -- Distribution` (was "Daily Jackpot ETH -- Chunked Distribution") |
| **Problem** | This was partially updated during chunk removal (removed "Chunked"). The heading is now accurate but the function below it still has "Chunk" in its name. After the rename in Issue 6, this section is consistent. No further change needed to this heading. |
| **Status** | No action required -- will be consistent after Issue 6 rename. |

#### Issue 9: AdvanceModule Resume Comment

| Property | Value |
|----------|-------|
| **File** | `contracts/modules/DegenerusGameAdvanceModule.sol` |
| **Lines** | 361-363 |
| **Current** | `// Resume Phase 1 carryover ETH distribution.` / `// Must match payDailyJackpot's isResuming condition to avoid` / `// emitting STAGE_JACKPOT_DAILY_STARTED on what is actually a resume.` |
| **Problem** | This comment was correctly updated during chunk removal. It accurately describes the current behavior. |
| **Status** | No action required -- already accurate. |

#### Issue 10: Slot 0 Header Title

| Property | Value |
|----------|-------|
| **File** | `contracts/storage/DegenerusGameStorage.sol` |
| **Line** | 35 |
| **Current** | `EVM SLOT 0 (32 bytes) -- Timing, FSM, Cursors, Counters, Flags` |
| **Problem** | "Cursors" is stale. The only cursor that was in Slot 0 was `dailyEthBucketCursor`, which was removed. `ticketCursor` is in Slot 17, not Slot 0. Slot 0 now contains timing, FSM, counters, flags, and phase/compression state. |
| **Fix** | `EVM SLOT 0 (32 bytes) -- Timing, FSM, Counters, Flags, ETH Phase` |

### Summary of Required Changes

| File | Issues | Estimated Lines Changed |
|------|--------|-------------------------|
| `contracts/storage/DegenerusGameStorage.sol` | #1, #2, #3, #4, #10 | ~25 comment lines |
| `contracts/modules/DegenerusGameJackpotModule.sol` | #5, #6, #7 | ~12 lines (comment + rename) |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | (none -- already accurate) | 0 |
| **Total** | **8 actionable issues** | **~37 lines** |

### Out-of-Scope References (for documentation only)

These stale references exist outside contract code and are NOT in scope for CMT-01:

| File | Reference | Notes |
|------|-----------|-------|
| `audit/v3.8-commitment-window-inventory.md` lines 100-101, 3790 | `dailyEthBucketCursor`, `dailyEthWinnerCursor` documented as live storage variables | Audit doc from v3.8; stale after chunk removal. Future audit doc sync can address. |
| `test/poc/Phase26_GasGriefing.test.js` | Comment-only references to removed symbols | Test PoC file, comments only |
| `.planning/phases/96-gas-ceiling-optimization/96-OPTIMIZATION-AUDIT.md` line 135 | References `_winnerUnits` as "still in worktree" | Planning doc written during analysis; factually was wrong at time of writing since Phase 95 refactor already applied |

## Architecture Patterns

### NatSpec Standard for This Project

Based on examination of existing NatSpec across the 3 affected contracts, this project follows:

1. **`@notice`** on public/external functions only (user-facing summary)
2. **`@dev`** on all functions including private/internal (developer-facing detail)
3. **`@param`** on functions with non-obvious parameters (inconsistently applied to private functions)
4. **`@return`** on functions with return values (inconsistently applied to private functions)
5. **Storage variables** use `/// @dev` with multi-line descriptions for complex state
6. **Section headings** use `// =========================================================================` banner comments
7. **Inline comments** explain "why" not "what" -- e.g., `// Gas optimization: 20% = 1/5 (cheaper than * 2000 / 10000)`

### Rename Pattern

The function rename `_processDailyEthChunk` -> `_processDailyEth` follows the project's naming convention:
- Private functions prefixed with `_`
- Descriptive names matching their purpose
- No abbreviations in function names (the project uses full words: `_addClaimableEth`, `_processAutoRebuy`, `_clearDailyEthState`)

The rename requires updating exactly 3 locations:
1. Function definition: `DegenerusGameJackpotModule.sol` line 1329
2. Phase 0 call site: `DegenerusGameJackpotModule.sol` line 495
3. Phase 1 call site: `DegenerusGameJackpotModule.sol` line 565

No interface changes, no cross-file references, no test file references (private function, not testable via harness).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage layout verification | Manual byte counting | `forge inspect DegenerusGame storage` | Authoritative truth from the compiler. Manual counting is error-prone with packed structs. |
| Stale reference sweeps | Manual file reading | `grep -rn` with targeted patterns | Comprehensive, reproducible, catches references in all files |

## Common Pitfalls

### Pitfall 1: Updating Comments Without Verifying Against forge inspect

**What goes wrong:** Comment "fixes" introduce new errors because the developer calculates offsets manually instead of checking the compiler output.
**Why it happens:** Storage packing is subtle -- removing a 1-byte variable from a packed slot cascades offset changes through the entire slot and potentially into adjacent slots.
**How to avoid:** Run `forge inspect DegenerusGame storage` and use its output as the single source of truth for ALL offset claims in comments.
**Warning signs:** Any comment claiming a byte offset that doesn't match forge inspect output.

### Pitfall 2: Renaming a Function Without Updating All Call Sites

**What goes wrong:** Compilation fails with "undeclared identifier" errors.
**Why it happens:** The function is private so there are no interface references, but there are still internal call sites.
**How to avoid:** Search for the old name with grep before and after the rename. Verify with `forge build`.
**Warning signs:** `forge build` fails after rename.

### Pitfall 3: Over-Editing Accurate Comments

**What goes wrong:** Introducing new inaccuracies by "improving" comments that were already correct.
**Why it happens:** Phase scope creep -- comments in adjacent functions look like they could be better, but they accurately describe the current code.
**How to avoid:** Only modify comments that are PROVABLY wrong (reference removed concepts, cite wrong offsets, or describe behavior that no longer exists). Leave accurate comments alone even if they could be "improved."
**Warning signs:** Editing comments in functions that were NOT modified during chunk removal and were NOT analyzed during gas optimization.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat (mocha/chai) |
| Config files | `foundry.toml`, `hardhat.config.ts` |
| Quick run command | `forge build` (compilation check only -- comment changes don't affect runtime behavior) |
| Full suite command | `forge build && forge test --summary` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMT-01 | NatSpec and inline comments accurate for all modified functions | manual + compilation | `forge build` (verifies no syntax errors from edits) | N/A -- comment accuracy is verified by human review against forge inspect output |

### Sampling Rate

- **Per task commit:** `forge build` (compilation check)
- **Per wave merge:** `forge build` (same -- comment-only changes have no runtime effect)
- **Phase gate:** `forge build` green + manual review of diff against `forge inspect DegenerusGame storage` output

### Wave 0 Gaps

None -- no test infrastructure needed. Comment changes are verified by compilation (no syntax breaks) and manual review (content accuracy).

## Authoritative Storage Layout Reference

From `forge inspect DegenerusGame storage`, verified 2026-03-25:

**Slot 0 (32 bytes, fully packed):**

| Field | Type | Offset | Bytes |
|-------|------|--------|-------|
| levelStartTime | uint48 | 0 | 6 |
| dailyIdx | uint48 | 6 | 6 |
| rngRequestTime | uint48 | 12 | 6 |
| level | uint24 | 18 | 3 |
| jackpotPhaseFlag | bool | 21 | 1 |
| jackpotCounter | uint8 | 22 | 1 |
| poolConsolidationDone | bool | 23 | 1 |
| lastPurchaseDay | bool | 24 | 1 |
| decWindowOpen | bool | 25 | 1 |
| rngLockedFlag | bool | 26 | 1 |
| phaseTransitionActive | bool | 27 | 1 |
| gameOver | bool | 28 | 1 |
| dailyJackpotCoinTicketsPending | bool | 29 | 1 |
| dailyEthPhase | uint8 | 30 | 1 |
| compressedJackpotFlag | uint8 | 31 | 1 |

**Slot 1 (25 bytes used, 7 bytes padding):**

| Field | Type | Offset | Bytes |
|-------|------|--------|-------|
| purchaseStartDay | uint48 | 0 | 6 |
| price | uint128 | 6 | 16 |
| ticketWriteSlot | uint8 | 22 | 1 |
| ticketsFullyProcessed | bool | 23 | 1 |
| prizePoolFrozen | bool | 24 | 1 |

**Slot 17 (7 bytes used, 25 bytes padding):**

| Field | Type | Offset | Bytes |
|-------|------|--------|-------|
| ticketCursor | uint32 | 0 | 4 |
| ticketLevel | uint24 | 4 | 3 |

## Sources

### Primary (HIGH confidence)

- `forge inspect DegenerusGame storage` -- authoritative storage layout, run 2026-03-25
- `git show e4b96aa4` -- complete chunk removal diff (3 files, 156 lines removed / 28 added)
- Direct code reading of current `DegenerusGameStorage.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameAdvanceModule.sol`
- Phase 95 research (`.planning/phases/95-delta-verification/95-RESEARCH.md`) -- pre/post storage layout tables
- Phase 96 gas analysis (`.planning/phases/96-gas-ceiling-optimization/96-GAS-ANALYSIS.md`) -- function-level call graph
- Phase 96 optimization audit (`.planning/phases/96-gas-ceiling-optimization/96-OPTIMIZATION-AUDIT.md`) -- SLOAD inventory with line numbers

### Secondary (MEDIUM confidence)

- `grep` sweep of all contract files for stale references to removed symbols -- comprehensive but pattern-based (could miss semantic staleness)

## Metadata

**Confidence breakdown:**
- Comment issue inventory: HIGH -- every issue verified against forge inspect and git diff
- Storage layout reference: HIGH -- authoritative compiler output
- Function rename scope: HIGH -- private function, 3 locations confirmed by grep
- Out-of-scope assessment: HIGH -- CMT-01 explicitly scopes to "modified functions"

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable -- no external dependencies, code is frozen)
