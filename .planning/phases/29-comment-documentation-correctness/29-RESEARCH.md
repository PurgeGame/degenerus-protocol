# Phase 29: Comment/Documentation Correctness - Research

**Researched:** 2026-03-18
**Domain:** Solidity NatSpec/inline comment verification against audited behavior
**Confidence:** HIGH

## Summary

Phase 29 is a documentation correctness pass across all 25,326 lines of Solidity in 27 contract files (14 core + 12 modules + 1 storage). The task is purely analytical: compare every comment in the contracts against the verified behavior established in Phases 26-28 (GAMEOVER paths, payout/claim paths, cross-cutting verification). No code changes are made -- only comments are corrected or flagged.

The codebase has approximately 3,066 NatSpec tag lines (`@notice`, `@dev`, `@param`, `@return`), plus thousands of inline `//` comments. The storage layout file (DegenerusGameStorage.sol, 1,631 lines) contains an extensive packed-slot layout diagram in the header block comment (lines 31-105) plus per-variable annotations. The parameter reference document (audit/v1.1-parameter-reference.md, 789 lines) tracks every named constant with File:Line references and has 8 known stale entries from removed constants (FINDING-INFO-CHG04-01).

Prior phases have already identified several documentation issues that Phase 29 must address: 8 stale parameter reference entries (CHG-04), a stale earlybird pool comment (DELTA-I-04, possibly already fixed), stale test comments about 912d timeouts (GO-03-I01), and a coinflip claim window asymmetry not documented in natspec (PAY-07-I01).

**Primary recommendation:** Organize work by contract file size (largest first: DegenerusGame.sol, JackpotModule.sol, LootboxModule.sol, Storage.sol), with separate tasks for storage layout verification and parameter reference doc spot-check. Use prior audit reports as the ground truth source -- do not re-audit behavior, only verify that comments accurately describe the behavior already proven.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOC-01 | Every natspec comment on every external/public function verified -- description matches actual behavior | ~288 external/public functions across 27 contracts. Prior audit reports (Phases 26-28) establish ground truth for all behavior. Verification approach: read each function's NatSpec, cross-reference against audit verdict for that function's subsystem. |
| DOC-02 | Every inline comment verified -- no stale comments from prior code versions | ~6,000+ inline comments across 25,326 lines. Known stale items: DELTA-I-04 (earlybird pool comment, possibly fixed), GO-03-I01 (test file 912d). Approach: systematic file-by-file review checking inline comments against current code logic. |
| DOC-03 | Storage layout comments verified -- comments match actual storage positions | Storage layout diagram (lines 31-105 of DegenerusGameStorage.sol) documents EVM Slot 0, 1, 2, and 3+ with byte offsets. Per-variable natspec (lines 189-360+) describes each storage variable. Approach: verify slot diagram byte offsets match actual variable declaration order and types. |
| DOC-04 | Constants comments verified -- comment values match actual contract values | ~627 constant/immutable declarations across all contracts. Many already verified by Phase 28 CHG-04 (30 active constants matched). Approach: verify natspec on constant declarations describes the correct value, purpose, and scale (BPS vs half-BPS vs PPM). |
| DOC-05 | Parameter reference doc spot-checked -- every value verified against contract source | 789-line document with ~200+ entries. Phase 28 already verified 30 active constants and identified 8 stale removals. Approach: verify remaining entries (File:Line references, values, human-readable descriptions) against current contract source. Fix or mark the 8 known stale entries. |
</phase_requirements>

## Standard Stack

This phase does not introduce any libraries or tools. It is a purely manual audit task using existing project infrastructure.

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source files | Primary verification target | contracts/ directory is source of truth |
| Prior audit reports (audit/*.md) | Ground truth for verified behavior | Phases 26-28 establish what each function actually does |
| Parameter reference (audit/v1.1-parameter-reference.md) | DOC-05 verification target | Master constant lookup document |

### Verification Sources (Ground Truth)
| Source Document | Phase | What It Proves |
|----------------|-------|---------------|
| v3.0-gameover-audit-consolidated.md | 26 | GAMEOVER paths: GO-01 through GO-09 behavior |
| v3.0-gameover-ancillary-paths.md | 26 | Death clock, distress mode, deity refunds |
| v3.0-gameover-core-distribution.md | 26 | Terminal decimator, handleGameOverDrain |
| v3.0-gameover-safety-properties.md | 26 | Reentrancy, revert safety, VRF fallback |
| v3.0-payout-jackpot-distribution.md | 27 | PAY-01, PAY-02, PAY-16 |
| v3.0-payout-scatter-decimator.md | 27 | PAY-03, PAY-04, PAY-05, PAY-06 |
| v3.0-payout-coinflip-economy.md | 27 | PAY-07, PAY-08, PAY-18, PAY-19 |
| v3.0-payout-lootbox-quest-affiliate.md | 27 | PAY-09, PAY-10, PAY-11 |
| v3.0-payout-yield-burns.md | 27 | PAY-12, PAY-13, PAY-14, PAY-15, PAY-17 |
| v3.0-cross-cutting-recent-changes.md | 28 | CHG-01 through CHG-04, 8 stale param entries |
| v3.0-cross-cutting-invariants-pool.md | 28 | INV-01, INV-02 pool accounting |
| v3.0-cross-cutting-invariants-supply.md | 28 | INV-03, INV-04, INV-05 |
| v3.0-cross-cutting-edge-cases.md | 28 | EDGE-01 through EDGE-07 |
| v3.0-cross-cutting-vulnerability-ranking.md | 28 | VULN-01 through VULN-03 |
| FINAL-FINDINGS-REPORT.md | All | Consolidated severity distribution |
| KNOWN-ISSUES.md | All | Known findings for C4A wardens |

## Architecture Patterns

### Contract File Inventory (by size, for work ordering)

```
Tier 1 - Large (>1500 lines, highest NatSpec density):
  contracts/DegenerusGame.sol               2856 lines  (603 /// comments, 52 ext/pub functions)
  contracts/modules/JackpotModule.sol       2819 lines  (241 /// comments, 5 ext/pub functions)
  contracts/modules/LootboxModule.sol       1778 lines  (324 /// comments, 5 ext/pub functions)
  contracts/storage/DegenerusGameStorage.sol 1631 lines (450 /// comments, storage layout diagram)
  contracts/DegenerusQuests.sol             1598 lines  (35 /// comments, 3 ext/pub functions)

Tier 2 - Medium (800-1500 lines):
  contracts/modules/AdvanceModule.sol       1383 lines  (119 /// comments, 4 ext/pub functions)
  contracts/modules/MintModule.sol          1195 lines  (42 /// comments, 1 ext/pub function)
  contracts/modules/DegeneretteModule.sol   1179 lines  (181 /// comments, 2 ext/pub functions)
  contracts/BurnieCoinflip.sol              1154 lines  (67 /// comments, 7 ext/pub functions)
  contracts/BurnieCoin.sol                  1065 lines  (236 /// comments, 30 ext/pub functions)
  contracts/DegenerusVault.sol              1061 lines  (294 /// comments, 53 ext/pub functions)
  contracts/modules/DecimatorModule.sol     1027 lines  (189 /// comments, 2 ext/pub functions)
  contracts/DegenerusAffiliate.sol           847 lines  (78 /// comments, 11 ext/pub functions)
  contracts/modules/WhaleModule.sol          839 lines  (68 /// comments, 4 ext/pub functions)

Tier 3 - Small (<800 lines):
  contracts/DegenerusAdmin.sol               778 lines  (55 /// comments, 23 ext/pub functions)
  contracts/DegenerusJackpots.sol            689 lines  (87 /// comments, 3 ext/pub functions)
  contracts/modules/EndgameModule.sol        540 lines  (40 /// comments, 3 ext/pub functions)
  contracts/StakedDegenerusStonk.sol         514 lines  (107 /// comments, 18 ext/pub functions)
  contracts/DegenerusDeityPass.sol           392 lines  (15 /// comments, 20 ext/pub functions)
  contracts/WrappedWrappedXRP.sol            389 lines  (111 /// comments, 11 ext/pub functions)
  contracts/modules/BoonModule.sol           359 lines  (16 /// comments, 5 ext/pub functions)
  contracts/modules/GameOverModule.sol       233 lines  (32 /// comments, 6 ext/pub functions)
  contracts/DegenerusStonk.sol               223 lines  (39 /// comments, 12 ext/pub functions)
  contracts/modules/MintStreakUtils.sol      (utility, 5 /// comments)
  contracts/modules/PayoutUtils.sol          (utility, 7 /// comments)
  contracts/DeityBoonViewer.sol              (view-only, 10 /// comments)
  contracts/DegenerusTraitUtils.sol          (utility, 38 /// comments)
  contracts/Icons32Data.sol                  (data, 50 /// comments)
  contracts/ContractAddresses.sol            (addresses, compile-time constants)
```

### Verification Methodology Per Requirement

**DOC-01 (NatSpec on external/public functions):**
1. For each contract, list all `external` and `public` functions
2. Read the `@notice`/`@dev`/`@param`/`@return` tags
3. Cross-reference the described behavior against the corresponding audit report
4. Flag discrepancies: wrong description, missing parameters, stale references to removed features

**DOC-02 (Inline comments):**
1. Read through each file systematically
2. For each inline `//` comment, verify it describes the current code on or near that line
3. Watch for: references to old variable names, old constant values, old feature behavior, TODO/FIXME items, references to removed code
4. Known starting points: DELTA-I-04 earlybird comment (appears fixed), GO-03-I01 test file comments

**DOC-03 (Storage layout):**
1. Verify the header block diagram (lines 31-105) of DegenerusGameStorage.sol
2. Check each byte offset claim: [0:6] levelStartTime uint48 etc.
3. Verify the slot boundary claims (Slot 0 = 32 bytes, Slot 1 = 27 bytes + 5 padding)
4. Cross-reference per-variable natspec against actual type and declared order
5. Verify that the variable declaration order matches the slot diagram

**DOC-04 (Constants comments):**
1. For each `constant` declaration with a `///` comment, verify the comment value matches the code value
2. Pay special attention to BPS vs half-BPS vs PPM scale annotations
3. Verify human-readable descriptions (e.g., "10%" for 1000 BPS)
4. Check for constants with changed values that have stale comments

**DOC-05 (Parameter reference doc):**
1. Fix the 8 known stale entries identified in FINDING-INFO-CHG04-01
2. For all remaining entries, verify File:Line references still point to the correct location
3. Spot-check values against current contract source (Phase 28 already verified 30)
4. Verify human-readable column is correct
5. Check cross-reference index for completeness

### Anti-Patterns to Avoid
- **Re-auditing behavior:** This phase verifies comments, not code. Do not re-derive whether functions are correct -- that was done in Phases 26-28. Only check that comments accurately describe the proven behavior.
- **Scope creep into code changes:** If a real bug is found during comment review, document it separately but do not attempt code fixes. This is a documentation pass.
- **Superficial scanning:** Each comment needs genuine cross-referencing against the audit report, not just "does this look reasonable."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding all public/external functions | Manual grep | `grep -rn 'function.*external\|function.*public'` across contracts/ | Ensures no function is missed |
| Verifying storage slot offsets | Manual byte counting | Compare declared types against the slot diagram systematically | Type sizes: bool=1, uint8=1, uint24=3, uint48=6, uint128=16, uint256=32, address=20 |
| Checking constant values | Reading constants one by one | Prior Phase 28 CHG-04 work already verified 30 constants -- build on that baseline | Avoid duplicating completed work |

## Common Pitfalls

### Pitfall 1: Line Number Drift
**What goes wrong:** The parameter reference doc (DOC-05) cites specific File:Line references. Code changes since the reference was written cause line numbers to drift.
**Why it happens:** Any code addition/deletion above the referenced line shifts all subsequent line numbers.
**How to avoid:** Search by constant NAME rather than trusting line numbers. Verify the name exists at the cited line; if not, find the correct line.
**Warning signs:** File:Line reference points to a blank line, comment, or different constant.

### Pitfall 2: Scale Confusion (BPS vs Half-BPS vs PPM)
**What goes wrong:** A comment says "10%" but the constant is 1000 in BPS scale (correct) vs 1000 in half-BPS scale (would be 5%) vs 1000 in PPM scale (would be 0.1%).
**Why it happens:** The codebase uses three different scaling conventions (BPS /10000, half-BPS /20000, PPM /1000000), sometimes in adjacent code.
**How to avoid:** For every percentage in a comment, verify which scale the constant uses. The parameter reference doc notes scale conventions in its header.
**Warning signs:** Half-BPS constants are marked in the parameter reference with a specific warning box. PPM constants have their own subsection.

### Pitfall 3: Delegatecall Module Comment Context
**What goes wrong:** A module's natspec says "this contract" when the code executes via delegatecall in DegenerusGame's storage context.
**Why it happens:** Module functions are written as if standalone but execute in the caller's storage context.
**How to avoid:** Verify that module natspec correctly describes the delegatecall execution model where relevant, especially for storage access and msg.sender semantics.
**Warning signs:** Module natspec referencing "contract balance" when it means the game contract's balance.

### Pitfall 4: Previously Fixed Items
**What goes wrong:** Spending time investigating items that were already fixed in commits after the audit reports were written.
**Why it happens:** Phase 28 CHG-01 categorized 113 commits, some of which fixed stale comments.
**How to avoid:** Check the current contract source, not the audit report's quoted source. The DELTA-I-04 earlybird comment appears to have been fixed (now says "lootbox pool" at line 1070).
**Warning signs:** Audit report cites a stale comment but the current code shows the correct comment.

### Pitfall 5: ContractAddresses.sol Template Values
**What goes wrong:** Flagging ContractAddresses.sol constants as "wrong" when they are compile-time template values populated by the deploy script.
**Why it happens:** The file contains placeholder addresses (0xa0Cb88...) that are replaced at deploy time.
**How to avoid:** The file header explicitly says "Compile-time constants populated by the deploy script." Accept these as template values, not production addresses.

## Code Examples

### Storage Slot Verification Pattern

When verifying DOC-03, use this type-size reference:

```
Type sizes for EVM slot packing:
  bool     = 1 byte
  uint8    = 1 byte
  uint24   = 3 bytes
  uint48   = 6 bytes
  uint128  = 16 bytes
  uint256  = 32 bytes (own slot)
  address  = 20 bytes
  bytes32  = 32 bytes (own slot)
```

Example verification for Slot 0:
```
Claimed layout:
  [0:6]   levelStartTime    uint48  = 6 bytes  -> cumulative: 6
  [6:12]  dailyIdx          uint48  = 6 bytes  -> cumulative: 12
  [12:18] rngRequestTime    uint48  = 6 bytes  -> cumulative: 18
  [18:21] level             uint24  = 3 bytes  -> cumulative: 21
  [21:22] jackpotPhaseFlag  bool    = 1 byte   -> cumulative: 22
  [22:23] jackpotCounter    uint8   = 1 byte   -> cumulative: 23
  [23:24] earlyBurnPercent  uint8   = 1 byte   -> cumulative: 24
  [24:25] poolConsolidationDone bool = 1 byte  -> cumulative: 25
  [25:26] lastPurchaseDay   bool    = 1 byte   -> cumulative: 26
  [26:27] decWindowOpen     bool    = 1 byte   -> cumulative: 27
  [27:28] rngLockedFlag     bool    = 1 byte   -> cumulative: 28
  [28:29] phaseTransitionActive bool = 1 byte  -> cumulative: 29
  [29:30] gameOver          bool    = 1 byte   -> cumulative: 30
  [30:31] dailyJackpotCoinTicketsPending bool = 1 byte -> cumulative: 31
  [31:32] dailyEthBucketCursor uint8 = 1 byte  -> cumulative: 32

Total: 32 bytes = exactly 1 EVM slot. PASS.
```

Verify that the actual variable declarations in the source code appear in exactly this order.

### NatSpec Cross-Reference Pattern

For DOC-01, the verification pattern is:

```
1. Read function signature and NatSpec:
   /// @notice Processes coinflip payouts for a player.
   /// @param player The player address.
   function claimCoinflips(address player) external { ... }

2. Find corresponding audit verdict:
   Phase 27 PAY-07 PASS: "claimCoinflips routes to _claimCoinflipsInternal"

3. Verify NatSpec matches:
   - Does the function actually process coinflip payouts? YES (per PAY-07)
   - Is the @param description accurate? YES (player address)
   - Are there missing @params or @returns? CHECK

4. Record verdict: MATCH or DISCREPANCY with details.
```

## State of the Art

This is not applicable to a documentation verification phase. No libraries, frameworks, or evolving standards are involved.

## Open Questions

1. **Line number accuracy in parameter reference**
   - What we know: Phase 28 verified 30 constant VALUES are correct. It did NOT verify all 200+ File:Line references are still accurate after recent commits.
   - What's unclear: How many File:Line references in the parameter reference have drifted from code changes since the doc was last fully updated.
   - Recommendation: Use constant NAME search rather than trusting line numbers. Update drifted line numbers as part of DOC-05.

2. **Scope of "every inline comment" (DOC-02)**
   - What we know: There are ~6,000+ inline comments across 25,326 lines. Reviewing every single one is the stated requirement.
   - What's unclear: Whether trivial comments (e.g., `// increment counter`) need the same rigor as behavioral comments (e.g., `// 50/50 split between vault and DGNRS`).
   - Recommendation: Prioritize behavioral comments that describe distribution logic, formulas, pool splits, and security properties. Trivial code-structure comments can receive lighter review.

3. **DELTA-I-04 status**
   - What we know: The original stale comment ("reward pool" instead of "lootbox pool") was at DegenerusGameStorage.sol ~line 1086. Current code at line 1070 says "lootbox pool."
   - What's unclear: Whether this was an intentional fix or whether line number drift makes it appear fixed.
   - Recommendation: Verify during DOC-02 that no other stale earlybird/reward pool references remain.

## Known Documentation Issues (Pre-Identified)

These were flagged in prior phases and MUST be addressed in Phase 29:

| ID | Source | Issue | Status |
|----|--------|-------|--------|
| FINDING-INFO-CHG04-01 | Phase 28 | 8 stale constants in parameter reference (removed in f71b6382 and 9b0942af) | Must fix in DOC-05 |
| DELTA-I-04 | Phase 20 | Stale earlybird "reward pool" comment in Storage.sol | Appears fixed, verify in DOC-02 |
| GO-03-I01 | Phase 26 | Stale test comments (912d vs 365d) in test files | Verify in DOC-02 (test/ directory) |
| PAY-07-I01 | Phase 27 | Coinflip claim window asymmetry (30d/90d) absent from contract natspec | Document during DOC-01 |
| PAY-11-I01 | Phase 27 | Affiliate DGNRS allocation: v1.1 doc says sequential depletion, code uses fixed allocation | Note in DOC-05 or separate |
| PAY-03-I01 | Phase 27 | Unused winnerMask variable | Verify comment accuracy in DOC-02 |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual audit verification (no automated tests) |
| Config file | N/A |
| Quick run command | N/A (documentation review, not code execution) |
| Full suite command | N/A |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-01 | NatSpec matches behavior on all ext/pub functions | manual-only | N/A -- requires reading and cross-referencing | N/A |
| DOC-02 | Inline comments match current code | manual-only | N/A -- requires reading each comment in context | N/A |
| DOC-03 | Storage layout comments match actual layout | manual-only | N/A -- requires byte-offset arithmetic verification | N/A |
| DOC-04 | Constants comments match actual values | manual-only | N/A -- requires reading constant declarations | N/A |
| DOC-05 | Parameter reference doc values correct | manual-only | N/A -- requires cross-referencing doc vs source | N/A |

**Justification for manual-only:** This phase verifies the semantic accuracy of human-written English comments against proven code behavior. There is no automated tool that can determine whether a NatSpec description correctly captures the intent and behavior of a function. The verification requires understanding the audit verdicts from Phases 26-28 and comparing them against natural-language descriptions.

### Sampling Rate
- **Per task commit:** Review output document for completeness and accuracy
- **Per wave merge:** Cross-check that all contracts are covered, no files missed
- **Phase gate:** All 5 DOC requirements have explicit verdicts with evidence

### Wave 0 Gaps
None -- no test infrastructure needed. This is a documentation audit phase producing markdown reports.

## Sources

### Primary (HIGH confidence)
- contracts/ directory -- all 27 Solidity files read and line-counted
- contracts/storage/DegenerusGameStorage.sol -- storage layout diagram verified present (lines 31-105)
- audit/v1.1-parameter-reference.md -- 789 lines, structure and scope verified
- audit/v3.0-cross-cutting-recent-changes.md -- FINDING-INFO-CHG04-01 details (8 stale constants)
- audit/KNOWN-ISSUES.md -- all known findings enumerated
- audit/FINAL-FINDINGS-REPORT.md -- severity distribution and informational findings listed

### Secondary (MEDIUM confidence)
- audit/v2.0-delta-consumer-callsites.md -- DELTA-I-04 stale comment details
- audit/v3.0-gameover-ancillary-paths.md -- GO-03-I01 stale test comment details

## Metadata

**Confidence breakdown:**
- Scope assessment: HIGH -- all contract files enumerated, line counts verified, comment density measured
- Known issues: HIGH -- all prior FINDING-INFO items traced to source documents
- Verification methodology: HIGH -- standard NatSpec/inline review approach, well-established in prior phases
- Completeness estimate: MEDIUM -- the sheer volume (25,326 lines, 3,066 NatSpec tags) means some items may be missed; systematic coverage by file mitigates this

**Research date:** 2026-03-18
**Valid until:** 2026-04-17 (30 days -- stable domain, no external dependencies)
