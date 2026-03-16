# Phase 20: Correctness Verification -- Docs, Comments, Tests - Research

**Researched:** 2026-03-16
**Domain:** Solidity NatDoc verification, audit doc accuracy, test coverage, fuzz test correctness
**Confidence:** HIGH

## Summary

This phase is a correctness sweep across documentation, NatDoc comments, test coverage, and fuzz test compilation for all contracts changed in the sDGNRS/DGNRS split. The scope is bounded: 2 core contracts (StakedDegenerusStonk.sol, DegenerusStonk.sol), 1 interface (IStakedDegenerusStonk.sol), ~30 audit docs, and 2 primary test files. The work is verification and gap-filling, not new code development.

Phase 19 completed the adversarial security audit of the split with a SOUND rating (0 Critical/High/Medium, 1 Low, 4 Informational). The current phase addresses the "documentation debt" accumulated during the split: stale comments, missing NatDoc on DGNRS ERC20 functions, line number drift in the parameter reference, and the need for a StakedDegenerusStonk section in the state-changing-function-audits.md. Test-wise, DGNRSLiquid.test.js (38 tests) and DegenerusStonk.test.js (37 tests) already exist with strong coverage. The primary test gap is ensuring all DGNRS wrapper functions are covered (some ERC20 functions may lack NatDoc but are tested).

The research identified several concrete findings: (1) DegenerusStonk.sol has 6 external functions without NatDoc comments (transfer, transferFrom, approve, receive, previewBurn, plus error/event declarations missing NatDoc), (2) the parameter reference has minor line number discrepancies from the split (e.g., `CREATOR_BPS` documented at line 153, actual at 155; `AFFILIATE_DGNRS_LEVEL_BPS` documented in `DegenerusGame.sol:201` but actually in `EndgameModule.sol:99`), (3) the stale earlybird comment at DegenerusGameStorage.sol:1086 flagged by DELTA-I-04 has not been fixed, (4) state-changing-function-audits.md has a DegenerusStonk.sol section but no StakedDegenerusStonk.sol section.

**Primary recommendation:** Structure the phase as three sequential plans: (1) NatDoc + stale comment fixes in contracts, (2) audit doc verification sweep across all 30 audit docs, (3) test coverage gap analysis and any new tests needed.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CORR-01 | All NatDoc comments match implementation across changed contracts | Concrete gaps identified: 6 undocumented external functions in DegenerusStonk.sol, 1 stale comment (line 1086 DegenerusGameStorage.sol). StakedDegenerusStonk.sol is fully documented. IStakedDegenerusStonk.sol is fully documented. |
| CORR-02 | All 10 audit docs verified against current code (no stale refs) | Specific stale refs identified: parameter reference line numbers (CREATOR_BPS 153->155, AFFILIATE_DGNRS_LEVEL_BPS wrong file), state-changing-function-audits.md missing sDGNRS section. Full audit doc inventory of 30 files ready for sweep. |
| CORR-03 | Test coverage for new/changed functions (sDGNRS, DGNRS, bounty, degenerette) | Existing coverage: DGNRSLiquid.test.js (38 tests), DegenerusStonk.test.js (37 tests). Tests cover: constructor, ERC20, unwrapTo, burn, previewBurn, soulbound enforcement, pool operations, supply accounting. Potential gap: no dedicated test for `resolveCoinflips`, `gameClaimWhalePass` internals, `burnieReserve` with actual BURNIE backing. |
| CORR-04 | Fuzz test compilation and correctness for changed contracts | Foundry compiles cleanly (warnings only, no errors). Fuzz tests reference correct contract names (StakedDegenerusStonk, DegenerusStonk). DeployCanary.t.sol verifies all 23 addresses including SDGNRS and DGNRS. AffiliateDgnrsClaim.t.sol imports StakedDegenerusStonk correctly. |
</phase_requirements>

## Standard Stack

This is a verification/documentation phase -- no new libraries needed. Uses the existing project stack.

### Core (Existing Project Stack)
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Solidity | 0.8.34 | Contract language | NatDoc comments are Solidity feature |
| Hardhat | (project) | Test runner (JS) | 1065 passing tests as baseline |
| Foundry/Forge | (project) | Fuzz test compilation | foundry.toml configured, `forge build` clean |

### Audit Approach
| Method | Purpose | When to Use |
|--------|---------|-------------|
| NatDoc line-by-line review | CORR-01: verify every external/public function has accurate NatDoc | StakedDegenerusStonk.sol, DegenerusStonk.sol |
| Stale reference grep | CORR-02: find IDegenerusStonk, old burnForGame, wrong line numbers | All 30 audit docs |
| Test inventory | CORR-03: catalog test coverage per function | DGNRSLiquid.test.js, DegenerusStonk.test.js |
| Forge compilation | CORR-04: verify fuzz tests compile with correct contract refs | `forge build --force` |

## Architecture Patterns

### Contract NatDoc Coverage Map

**StakedDegenerusStonk.sol (sDGNRS) -- 520 lines:**
All external/public functions have NatDoc. Fully documented:
- `wrapperTransferTo` (line 234-251): `@notice`, `@dev`, `@param`, `@custom:reverts`
- `gameAdvance` (line 258-261): `@notice`
- `gameClaimWhalePass` (line 263-266): `@notice`
- `resolveCoinflips` (line 268-273): `@notice`, `@dev`
- `receive()` (line 279-284): `@notice`, `@dev`, `@custom:reverts`
- `depositSteth` (line 286-294): `@notice`, `@dev`, `@param`, `@custom:reverts`
- `poolBalance` (line 300-305): `@notice`, `@param`, `@return`
- `transferFromPool` (line 307-332): `@notice`, `@dev`, `@param`, `@return`, `@custom:reverts`
- `transferBetweenPools` (line 334-355): `@notice`, `@dev`, `@param`, `@return`
- `burnRemainingPools` (line 357-367): `@notice`, `@dev`
- `burn` (line 373-441): `@notice`, `@dev`, `@param`, `@return`
- `previewBurn` (line 447-476): `@notice`, `@dev`, `@param`, `@return`
- `burnieReserve` (line 479-485): `@notice`, `@return`
- Private helpers: `_claimableWinnings`, `_poolIndex`, `_mint` all documented

**DegenerusStonk.sol (DGNRS) -- 177 lines:**
NatDoc GAPS (6 external functions without NatDoc):
1. `receive()` (line 79) -- no NatDoc at all
2. `transfer()` (line 85) -- no NatDoc
3. `transferFrom()` (line 89) -- no NatDoc
4. `approve()` (line 100) -- no NatDoc
5. `previewBurn()` (line 148) -- no NatDoc
6. Error declarations (lines 29-32) -- no NatDoc (Unauthorized, Insufficient, ZeroAddress, TransferFailed)

Functions WITH NatDoc:
- `unwrapTo()` (line 110): `@notice`
- `burn()` (line 123): `@notice`, `@dev`
- Contract-level: `@title`, `@notice`, `@dev`

**IStakedDegenerusStonk.sol -- 82 lines:**
Fully documented. All interface functions have `@notice`, `@dev`, `@param`, `@return`.

### Audit Doc Inventory (30 files)

The success criteria mentions "10 audit docs" -- this likely refers to the 10 docs that were updated during the sDGNRS/DGNRS doc sync (v1.3). However, the full audit directory has 30 files. For CORR-02, the verification sweep should cover ALL docs but focus on the ones most likely to contain stale references:

**High-priority (directly reference DGNRS architecture):**
1. `v1.1-dgnrs-tokenomics.md` -- Already updated to dual-contract architecture
2. `v1.1-parameter-reference.md` -- Line numbers may be stale
3. `state-changing-function-audits.md` -- Has DegenerusStonk.sol section, MISSING StakedDegenerusStonk.sol section
4. `v2.0-delta-core-contracts.md` -- New, from Phase 19
5. `v2.0-delta-consumer-callsites.md` -- New, from Phase 19
6. `v2.0-delta-findings-consolidated.md` -- New, from Phase 19
7. `KNOWN-ISSUES.md` -- Needs DELTA-L-01 addition per Phase 19 recommendation
8. `FINAL-FINDINGS-REPORT.md` -- May need update to reference v2.0 findings
9. `EXTERNAL-AUDIT-PROMPT.md` -- Must reference current architecture

**Medium-priority (may have indirect refs):**
10. `v1.1-affiliate-system.md` -- References DGNRS pool operations
11. `v1.1-burnie-coinflip.md` -- References DGNRS bounty
12. `v1.1-deity-system.md` -- References DGNRS whale/affiliate rewards
13. `v1.1-endgame-and-activity.md` -- References DGNRS endgame distribution
14. `v1.1-steth-yield.md` -- References stETH in DGNRS reserves

**Low-priority (unlikely to have stale DGNRS refs):**
15-30. RNG docs, level progression, quest rewards, etc.

### Concrete Stale References Found

| File | Issue | Details |
|------|-------|---------|
| `DegenerusGameStorage.sol:1086` | Stale comment | Says "reward pool", code uses Lootbox (DELTA-I-04) |
| `v1.1-parameter-reference.md:53` | Line number drift | `CREATOR_BPS` documented at `StakedDegenerusStonk.sol:153`, actual is line 155 |
| `v1.1-parameter-reference.md:54-58` | Line number drift | `WHALE_POOL_BPS` through `EARLYBIRD_POOL_BPS` documented at lines 156-160, actual at 158-162 |
| `v1.1-parameter-reference.md:59` | Wrong file reference | `AFFILIATE_DGNRS_LEVEL_BPS` documented at `DegenerusGame.sol:201`, actual is `DegenerusGameEndgameModule.sol:99` |
| `state-changing-function-audits.md` | Missing section | No `StakedDegenerusStonk.sol` section (the 13K-line doc covers DegenerusStonk.sol but not sDGNRS) |
| `KNOWN-ISSUES.md` | Missing finding | DELTA-L-01 (transfer-to-self lock) recommended for addition per Phase 19 consolidated report |

### Test Coverage Inventory

**DGNRSLiquid.test.js (38 tests) -- covers DegenerusStonk.sol (DGNRS wrapper):**
- Constructor: name, symbol, decimals, totalSupply, creator balance, sDGNRS backing
- ERC20: transfer, transfer events, zero address revert, insufficient balance, free transfer, approve+transferFrom, max approval, allowance exceed, Approval event
- unwrapTo: success, event, non-creator revert, zero address revert, exceed balance revert
- burn: zero amount, exceed balance, ETH forwarding, totalSupply decrease, sDGNRS supply decrease, BurnThrough event
- previewBurn: delegates to sDGNRS
- sDGNRS soulbound: no transfer function, burn from msg.sender, wrapperTransferTo auth
- sDGNRS features: burnRemainingPools auth+execution, gameAdvance, gameClaimWhalePass, resolveCoinflips
- Supply accounting: sync after unwrap/burn, total supply after burn

**DegenerusStonk.test.js (37 tests) -- covers StakedDegenerusStonk.sol (sDGNRS):**
- Initial state: name, symbol, decimals, totalSupply, creator allocation, pool balances (5 pools)
- transferFromPool: auth, success, cap to available, zero amount
- transferBetweenPools: auth, success, supply unchanged
- burnRemainingPools: auth, success
- depositSteth: auth, success
- receive (ETH deposit): auth, success
- burn: zero/exceed revert, player-only, ETH proportional payout, event, supply decrease
- previewBurn: zero, exceed supply, proportional with ETH
- burnieReserve: initial value
- gameAdvance: permissionless

**Coverage gaps to investigate:**
1. No test for `transferFromPool` with zero address recipient (should revert ZeroAddress)
2. No test for `wrapperTransferTo` with zero address (should revert ZeroAddress)
3. No test for `wrapperTransferTo` with amount > wrapper balance (should revert Insufficient)
4. No test for `depositSteth` with zero amount
5. No test for burn with stETH + BURNIE backing (only ETH tested)
6. `burnieReserve` only tested with zero backing, not with actual BURNIE deposits

### Fuzz Test Status

**Compilation:** `forge build --force` succeeds with only typecast lint warnings (not errors).

**Contract references verified:**
- `test/fuzz/helpers/DeployProtocol.sol` correctly imports and deploys both StakedDegenerusStonk and DegenerusStonk
- `test/fuzz/DeployCanary.t.sol` verifies SDGNRS and DGNRS addresses match ContractAddresses
- `test/fuzz/AffiliateDgnrsClaim.t.sol` imports StakedDegenerusStonk and uses Pool.Affiliate enum
- `test/fuzz/ShareMathInvariants.t.sol` has a NatDoc comment mentioning "DegenerusStonk" generically (line 7) but this is informational only

**No fuzz test issues found.** All references are correct.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NatDoc accuracy checking | Manual reading | Systematic function-by-function checklist | Easy to miss private function NatDoc or stale @param names |
| Stale reference detection | Ad-hoc grepping | Structured multi-pattern grep (IDegenerusStonk, old line numbers, burnForGame) | Pattern combinatorics are error-prone |
| Test coverage measurement | Manual test counting | Function inventory cross-referenced with test `describe` blocks | Coverage gaps hide in plain sight |

**Key insight:** The verification must be systematic, not exploratory. The concrete findings list above provides the starting point, but the plans must also perform defensive sweeps for patterns not yet discovered.

## Common Pitfalls

### Pitfall 1: Line Number Drift in Documentation
**What goes wrong:** Parameter reference and state-changing-function-audits documents reference exact line numbers that shift when code is modified. The sDGNRS/DGNRS split renumbered many lines.
**Why it happens:** Line numbers are hard-coded in docs, not auto-updated.
**How to avoid:** Verify every `File:Line` reference in the parameter reference against actual code. Use `grep -n` on the actual contract.
**Warning signs:** Any doc referencing `DegenerusStonk.sol` line numbers should be checked -- the file was completely rewritten.

### Pitfall 2: Missing sDGNRS Section in state-changing-function-audits.md
**What goes wrong:** The 13K-line state-changing-function-audits.md has an entry for DegenerusStonk.sol (the DGNRS wrapper) but no entry for StakedDegenerusStonk.sol. Any external auditor reading this doc would miss the sDGNRS contract's function-level audit.
**Why it happens:** The file predates the split. When DegenerusStonk was rewritten, the section was updated but no new section was added for the new soulbound contract.
**How to avoid:** Add a comprehensive StakedDegenerusStonk.sol section covering all 13 external/public functions.
**Warning signs:** An auditor asking "where's the sDGNRS function audit?"

### Pitfall 3: NatDoc on Standard ERC20 Functions
**What goes wrong:** Standard ERC20 functions (transfer, transferFrom, approve) in DegenerusStonk.sol lack NatDoc. While C4A wardens may not flag this, it creates inconsistency with the sDGNRS contract which is fully documented.
**Why it happens:** ERC20 functions are "obvious" so developers skip documenting them.
**How to avoid:** Add standard NatDoc to all 6 undocumented external functions in DegenerusStonk.sol.
**Warning signs:** `forge doc` or Etherscan verification showing empty NatDoc for public functions.

### Pitfall 4: KNOWN-ISSUES.md Not Updated for v2.0
**What goes wrong:** The Phase 19 consolidated report recommended adding DELTA-L-01 to KNOWN-ISSUES.md, but this was deferred. If not done in Phase 20, the pre-disclosure document will be incomplete for external auditors.
**Why it happens:** Phase 19 explicitly deferred KNOWN-ISSUES.md updates to Phase 20.
**How to avoid:** Include KNOWN-ISSUES.md update as an explicit task.
**Warning signs:** KNOWN-ISSUES.md only referencing v1.0-v1.2 findings, missing the DELTA-L-01 finding.

### Pitfall 5: Inconsistent Variable Naming in Audit Docs
**What goes wrong:** Some audit docs use `dgnrs` to refer to sDGNRS (because game contracts use `dgnrs` as their variable name for the sDGNRS interface). This can confuse readers into thinking the docs reference the DGNRS wrapper.
**Why it happens:** The game contract variable `dgnrs` points to `ContractAddresses.SDGNRS`. The naming is historical.
**How to avoid:** Audit docs should always clarify: "the variable `dgnrs` in game contracts refers to the sDGNRS contract (StakedDegenerusStonk), NOT the DGNRS wrapper (DegenerusStonk)."
**Warning signs:** Docs that say `dgnrs.poolBalance()` without clarifying which contract.

## Code Examples

### NatDoc Format for Missing DGNRS Functions

The following NatDoc should be added to DegenerusStonk.sol functions. Pattern matches the existing sDGNRS documentation style:

```solidity
/// @notice Accepts ETH from sDGNRS during burn-through; no other use
/// @dev Anyone can send ETH here but it is permanently locked (no sweep function)
receive() external payable {}

/// @notice Transfer DGNRS tokens to a recipient
/// @param to Recipient address
/// @param amount Amount to transfer
/// @return True on success
function transfer(address to, uint256 amount) external returns (bool) {

/// @notice Transfer DGNRS tokens from one address to another (requires allowance)
/// @param from Source address
/// @param to Destination address
/// @param amount Amount to transfer
/// @return True on success
function transferFrom(address from, address to, uint256 amount) external returns (bool) {

/// @notice Approve a spender to transfer DGNRS tokens
/// @param spender Address authorized to spend
/// @param amount Allowance amount
/// @return True on success
function approve(address spender, uint256 amount) external returns (bool) {

/// @notice Preview ETH, stETH, and BURNIE output for burning DGNRS
/// @dev Delegates to sDGNRS previewBurn
/// @param amount Amount of DGNRS to simulate burning
/// @return ethOut ETH that would be received
/// @return stethOut stETH that would be received
/// @return burnieOut BURNIE that would be received
function previewBurn(uint256 amount) external view returns (...) {
```

### Stale Comment Fix (DegenerusGameStorage.sol:1086)

```solidity
// BEFORE (stale):
// One-shot: dump remaining earlybird pool into reward pool

// AFTER (correct):
// One-shot: dump remaining earlybird pool into lootbox pool
```

### Parameter Reference Line Number Fix Example

```markdown
// BEFORE (stale):
| CREATOR_BPS | 2000 | BPS | StakedDegenerusStonk.sol | 153 |

// AFTER (correct):
| CREATOR_BPS | 2000 | BPS | StakedDegenerusStonk.sol | 155 |

// BEFORE (wrong file):
| AFFILIATE_DGNRS_LEVEL_BPS | 500 | BPS | DegenerusGame.sol | 201 |

// AFTER (correct file):
| AFFILIATE_DGNRS_LEVEL_BPS | 500 | BPS | DegenerusGameEndgameModule.sol | 99 |
```

## State of the Art

| Phase 19 State | Phase 20 Requirement | Gap |
|----------------|---------------------|-----|
| sDGNRS fully NatDoc documented | CORR-01 verified | Already complete |
| DGNRS has 6 undocumented functions | CORR-01 fix needed | Add NatDoc to 6 functions |
| Stale earlybird comment (DELTA-I-04) | CORR-01 fix needed | Fix line 1086 |
| Parameter reference has line drift | CORR-02 fix needed | Verify all line numbers |
| state-changing-function-audits missing sDGNRS | CORR-02 addition needed | Add sDGNRS section |
| KNOWN-ISSUES.md missing DELTA-L-01 | CORR-02 addition needed | Add DELTA-L-01 |
| DGNRSLiquid.test.js: 38 tests | CORR-03 verified | Already strong, minor gaps |
| DegenerusStonk.test.js: 37 tests | CORR-03 verified | Already strong, minor gaps |
| Foundry fuzz tests compile clean | CORR-04 verified | Already passing |

## Open Questions

1. **Which "10 audit docs" does the success criteria reference?**
   - What we know: The success criteria says "all 10 audit docs verified." The audit directory has 30 files. The v1.3 doc sync (from PROJECT.md "Audit doc sync -- all 10 docs updated for sDGNRS/DGNRS split") likely refers to the 10 v1.1 economics docs.
   - What's unclear: Exactly which 10 were synced in v1.3 vs which 20 were not changed.
   - Recommendation: Verify all 30 docs but prioritize the 14 high/medium-priority ones listed above. The 3 v2.0 docs were written fresh in Phase 19, so they should be accurate.

2. **Should the state-changing-function-audits.md get a full sDGNRS section?**
   - What we know: This is a 13K-line reference doc. Adding a full section for sDGNRS (13 external/public functions) would add ~1K-2K lines.
   - What's unclear: Is this the right phase to add it, or is it too large for a "correctness verification" scope?
   - Recommendation: Yes, add it. The doc explicitly covers every contract. Omitting sDGNRS is a gap that C4A wardens would notice. The sDGNRS functions are well-understood from Phase 19.

3. **Test coverage: should we add tests for stETH/BURNIE burn paths?**
   - What we know: Current tests only cover ETH-backed burns. The stETH and BURNIE paths are exercised indirectly in integration tests but not unit-tested for sDGNRS/DGNRS specifically.
   - What's unclear: Whether the mock stETH and mock BURNIE in the test fixture support the full burn-through flow.
   - Recommendation: Investigate test fixture capabilities and add targeted tests if possible without fixture changes. Do not modify the deploy fixture.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (Mocha/Chai) + Foundry (Forge) |
| Config file | hardhat.config.js + foundry.toml |
| Quick run command | `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CORR-01 | NatDoc matches implementation | manual-only: visual inspection of NatDoc vs code | N/A | N/A |
| CORR-02 | Audit docs match current code | manual-only: grep + visual verification against code | N/A | N/A |
| CORR-03 | Test coverage for new functions | unit | `npx hardhat test test/unit/DGNRSLiquid.test.js test/unit/DegenerusStonk.test.js` | Yes |
| CORR-04 | Fuzz tests compile and reference correct names | compile | `forge build --force` | Yes |

### Sampling Rate
- **Per task commit:** `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js`
- **Per wave merge:** `npm test`
- **Phase gate:** Full suite green + `forge build` clean before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. CORR-01 and CORR-02 are documentation verification tasks (manual review). CORR-03 and CORR-04 use existing test infrastructure. Any new tests will extend existing test files, not require new framework setup.

## Sources

### Primary (HIGH confidence)
- `contracts/StakedDegenerusStonk.sol` -- full read, 520 lines, NatDoc audit complete
- `contracts/DegenerusStonk.sol` -- full read, 177 lines, NatDoc gaps identified
- `contracts/interfaces/IStakedDegenerusStonk.sol` -- full read, 82 lines, fully documented
- `contracts/storage/DegenerusGameStorage.sol:1086` -- stale comment confirmed
- `audit/v1.1-parameter-reference.md` -- line number discrepancies verified against actual code
- `audit/state-changing-function-audits.md` -- confirmed missing sDGNRS section
- `audit/KNOWN-ISSUES.md` -- confirmed no DELTA-L-01 entry
- `audit/v2.0-delta-findings-consolidated.md` -- Phase 19 findings and recommendations
- `test/unit/DGNRSLiquid.test.js` -- 38 tests, coverage inventory complete
- `test/unit/DegenerusStonk.test.js` -- 37 tests, coverage inventory complete
- `test/fuzz/DeployCanary.t.sol` -- address verification confirmed correct
- `test/fuzz/helpers/DeployProtocol.sol` -- imports and deploy order confirmed correct
- `forge build --force` output -- compilation success confirmed
- `npx hardhat compile` output -- compilation success confirmed

### Secondary (MEDIUM confidence)
- `.planning/phases/19-delta-security-audit/19-RESEARCH.md` -- callsite inventory, BPS constants
- `.planning/REQUIREMENTS.md` -- CORR-01 through CORR-04 definitions
- `.planning/STATE.md` -- Phase 19 completion status and decisions

### Tertiary (LOW confidence)
- None. All findings based on direct source code and document analysis.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tooling needed, existing project infrastructure
- Architecture: HIGH -- all contracts and docs read in full, gaps catalogued precisely
- Pitfalls: HIGH -- every finding is backed by specific file:line evidence
- Test coverage: HIGH -- function-by-function inventory against test describe blocks

**Research date:** 2026-03-16
**Valid until:** Indefinite (source code and docs are the authoritative references; valid until code changes)
