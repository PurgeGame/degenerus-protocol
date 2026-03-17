# Phase 23: Gas Optimization -- Dead Code Removal - Research

**Researched:** 2026-03-16
**Domain:** Solidity gas optimization, dead code analysis, delegatecall module architecture
**Confidence:** HIGH

## Summary

Phase 23 targets behavior-preserving dead code removal across the Degenerus Protocol's ~25,600 lines of Solidity (0.8.34). The codebase uses a delegatecall module pattern where `DegenerusGame` dispatches to 10+ modules sharing a single storage layout (`DegenerusGameStorage.sol`, 1,608 lines). This architecture makes storage variable removal extremely dangerous -- removing or reordering any variable shifts slot alignment for all modules, causing catastrophic storage corruption.

The project has a built-in Scavenger/Skeptic dual-agent skill system (`~/.claude/skills/gas-{scavenger,skeptic,audit}/`) designed exactly for this phase. The Scavenger aggressively identifies removal candidates with JSON-formatted recommendations, and the Skeptic rigorously validates each one with counterexample-driven analysis. The gas-audit coordinator skill defines the orchestration workflow: Inventory, Scavenger Pass, Skeptic Review, Final Report.

**Primary recommendation:** Execute the Scavenger/Skeptic workflow in dependency order (Storage first, leaf modules up, core last), focusing on semantic dead code (unreachable branches, redundant checks, impossible triggers) since static analysis (Slither dead-code detector) reports 0 findings. The JackpotModule at 95% of the 24,576-byte EVM limit is the highest-priority target for bytecode savings.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GAS-01 | Remove unreachable checks (guards on variables that can never be zero/overflow) | Scavenger type `redundant_require` and `defensive_check_impossible`. Solidity 0.8.34 provides automatic overflow checks, making manual overflow guards redundant. The codebase has `unchecked` blocks that are intentional optimizations -- Skeptic must verify each is safe. |
| GAS-02 | Remove dead storage variables and unused state from all contracts | **CRITICAL CONSTRAINT:** Storage variables in `DegenerusGameStorage.sol` CANNOT be removed or reordered without breaking delegatecall slot alignment. Only non-storage dead variables (locals, memory, stack) and mappings at the END of storage layout can potentially be zeroed. One explicitly deprecated variable found: `_deprecated_deityTicketBoostDay` (line 1440). Quest struct has `difficulty` field marked "Unused; retained for storage compatibility" (line 228). |
| GAS-03 | Remove dead code paths and unreachable branches | Scavenger type `unreachable_branch` and `dead_code_path`. Game state machine (SETUP=1, PURCHASE=2, BURN=3, GAMEOVER=86) constrains which branches can execute. Module-level analysis required since modules share storage via delegatecall. |
| GAS-04 | Identify redundant external calls and storage reads that can be cached | Scavenger type `redundant_sload`. With viaIR=true and optimizer runs=200 (Hardhat), the compiler already performs some SLOAD caching. Focus on cross-function SLOAD patterns the optimizer cannot deduplicate, and repeated external calls to the same view function within a single execution path. |
</phase_requirements>

## Standard Stack

### Core Tools
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Solidity | 0.8.34 | Contract language | Exact pragma in all contracts; bugfix for IR storage clearing (0.8.28-0.8.33 affected) |
| Hardhat | (project) | Compilation + testing | Primary build tool; optimizer runs=200, viaIR=true |
| Foundry/Forge | (project) | Fuzz testing | Secondary; optimizer runs=2 for fuzz compilation |
| Slither | 0.11.5 | Static analysis | Installed; dead-code detector reports 0 findings (semantic analysis needed) |

### Gas Audit Skills (Project-Specific)
| Skill | Location | Purpose | When to Use |
|-------|----------|---------|-------------|
| gas-audit | `~/.claude/skills/gas-audit/SKILL.md` | Orchestrator for Scavenger/Skeptic workflow | Phase coordinator role |
| gas-scavenger | `~/.claude/skills/gas-scavenger/SKILL.md` | Aggressive removal candidate identification | Per-contract analysis pass |
| gas-skeptic | `~/.claude/skills/gas-skeptic/SKILL.md` | Rigorous validation of Scavenger recommendations | Review pass after Scavenger batch |

### Testing Infrastructure
| Suite | Command | Count | Purpose |
|-------|---------|-------|---------|
| Full Hardhat | `npm test` | ~1,065 passing | Behavior regression gate |
| Unit tests | `npm run test:unit` | 18 files | Per-contract coverage |
| Integration | `npm run test:integration` | 2 files | Cross-contract flows |
| Edge cases | `npm run test:edge` | 5 files | Boundary conditions |
| Gas benchmarks | `npx hardhat test test/gas/AdvanceGameGas.test.js` | 15 scenarios | Gas measurement |
| Fuzz tests | `npm run fuzz` | 15+ files | Foundry property tests |

## Architecture Patterns

### Delegatecall Module System (CRITICAL for Dead Code Analysis)

```
DegenerusGame (main, 21,372 bytes deployed)
  |-- inherits DegenerusGameStorage (1,608 lines, canonical slot layout)
  |-- delegatecall --> AdvanceModule (14,073 bytes)
  |-- delegatecall --> MintModule (15,084 bytes)
  |-- delegatecall --> JackpotModule (23,583 bytes -- 95% of 24,576 limit!)
  |-- delegatecall --> LootboxModule (19,382 bytes)
  |-- delegatecall --> DecimatorModule (5,678 bytes)
  |-- delegatecall --> DegeneretteModule (8,676 bytes)
  |-- delegatecall --> EndgameModule (6,233 bytes)
  |-- delegatecall --> GameOverModule (3,132 bytes)
  |-- delegatecall --> WhaleModule (11,760 bytes)
  |-- delegatecall --> BoonModule (5,447 bytes)

External Contracts (independent storage):
  |-- BurnieCoin (9,074 bytes)
  |-- BurnieCoinflip (18,044 bytes)
  |-- DegenerusVault (10,557 bytes)
  |-- StakedDegenerusStonk (5,245 bytes)
  |-- DegenerusStonk (2,551 bytes)
  |-- DegenerusAffiliate (5,090 bytes)
  |-- DegenerusJackpots (5,989 bytes)
  |-- DegenerusQuests (12,284 bytes)
  |-- DegenerusDeityPass (9,910 bytes)
```

### Scavenger/Skeptic Workflow Pattern

The gas-audit skill defines a 5-phase workflow:

1. **Inventory** -- Catalog all production contracts by priority
2. **Scavenger Pass** -- Per-contract aggressive analysis producing JSON recommendations
3. **Skeptic Review** -- Validate each recommendation with counterexamples
4. **Final Report** -- Compile approved/rejected/escalated verdicts
5. **Implementation** -- Apply approved removals, run tests

The Scavenger produces structured JSON with fields: `id`, `file`, `location`, `type`, `code`, `reasoning`, `confidence` (high/medium/low), `gas_estimate`, `cross_contract_check_needed`, `files_checked`.

The Skeptic produces verdicts: `APPROVED`, `REJECTED`, `PARTIAL`, `NEEDS_HUMAN_REVIEW`.

### Contract Processing Order (from gas-audit skill)

1. **DegenerusGameStorage.sol** -- FIRST (canonical layout, all modules depend on it)
2. **Leaf modules** -- GameOverModule, EndgameModule (fewest dependencies)
3. **Mid-tier modules** -- DecimatorModule, BoonModule, WhaleModule, DegeneretteModule
4. **Core modules** -- MintModule, AdvanceModule, JackpotModule, LootboxModule
5. **Main contract** -- DegenerusGame.sol (needs all module context)
6. **Libraries** -- Check for unused exports after all contract analysis
7. **External contracts** -- BurnieCoin, BurnieCoinflip, Vault, sDGNRS/DGNRS, etc.
8. **Interfaces** -- Check for orphaned function signatures

### Anti-Patterns to Avoid

- **Removing storage variables from DegenerusGameStorage.sol** -- Shifts slot alignment for all modules. Even "unused" variables must remain as slot placeholders. The ONLY safe pattern is renaming to `_deprecated_*` (already done for `_deprecated_deityTicketBoostDay` at line 1440).
- **Removing public/external functions** -- Must check all interfaces (`IDegenerusGame.sol`, `IDegenerusGameModules.sol`, etc.) and all cross-contract callers before removing.
- **Removing event emissions** -- Part of the external API even if no on-chain consumer exists.
- **Ignoring compiler optimizer effects** -- With viaIR=true and runs=200, the optimizer already eliminates some dead code at the bytecode level. Manual removal saves source readability but may not always reduce bytecode.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dead code detection | Manual grep/search | Scavenger skill + Slither | Scavenger has domain-specific game state knowledge |
| Cross-contract validation | Manual trace | Skeptic skill + interface checks | Skeptic has structured edge case checklist |
| Storage slot analysis | Manual slot counting | Hardhat storageLayout output + Slither | Compiler provides canonical layout |
| Behavior verification | Manual testing | Full test suite (`npm test` + `npm run fuzz`) | 1,065+ tests cover all paths |

**Key insight:** Semantic dead code (branches unreachable due to game state machine logic) cannot be detected by any static tool. The Scavenger/Skeptic dual-agent approach is specifically designed for this kind of domain-specific analysis where understanding the game's state machine is required to prove code is unreachable.

## Common Pitfalls

### Pitfall 1: Storage Slot Corruption via Variable Removal
**What goes wrong:** Removing a storage variable from `DegenerusGameStorage.sol` shifts all subsequent slot assignments, causing every module to read/write wrong storage locations.
**Why it happens:** Delegatecall modules share the exact storage layout. EVM assigns slots sequentially.
**How to avoid:** NEVER remove storage variables. Instead, rename to `_deprecated_*` and leave the slot occupied. The `difficulty` field in DegenerusQuests.sol struct (line 228) already follows this pattern: "Unused (fixed to 0); retained for storage compatibility."
**Warning signs:** Any Scavenger recommendation targeting `DegenerusGameStorage.sol` storage variables must be flagged for Skeptic cross-contract validation.

### Pitfall 2: Removing "Dead" Functions Still Called via Interface
**What goes wrong:** A function appears unused in the contract but is called by external contracts through interfaces.
**Why it happens:** External contracts call via interface (`IDegenerusGame(addr).functionName()`), which doesn't show up as a direct reference in the target contract.
**How to avoid:** Check ALL interfaces before removing any public/external function. The Skeptic skill has a specific cross-contract trace checklist for this.
**Warning signs:** Any function that appears in `IDegenerusGame.sol` (450 lines), `IDegenerusGameModules.sol` (390 lines), or other interface files.

### Pitfall 3: Confusing Hardhat and Foundry Optimizer Settings
**What goes wrong:** Estimating gas savings based on wrong optimizer settings.
**Why it happens:** Hardhat uses runs=200 (deployment config), Foundry uses runs=2 (fuzz testing only). The Scavenger skill text mentions runs=2, which is stale/incorrect for deployment.
**How to avoid:** All gas estimates must use runs=200 (Hardhat) as the reference since that is the actual deployment configuration. Bytecode savings per removed code byte are approximately 200 gas/byte at runs=200 (less aggressive inlining than runs=2).
**Warning signs:** Gas estimates that seem very high for small code removals.

### Pitfall 4: Breaking Behavior While "Just Removing Dead Code"
**What goes wrong:** A branch that appears unreachable actually executes under rare game conditions (level 100 decimator, gameover + concurrent burns, VRF timeout).
**Why it happens:** The game state machine has many states (SETUP, PURCHASE, BURN, GAMEOVER) with edge conditions at boundaries (level 0, level 100, day 5 of jackpot, etc.).
**How to avoid:** The Skeptic's edge case checklist covers 10 specific conditions: Level 0, Level 100, Gameover (state 86), RNG locked, Extermination, Prize target reached, Empty arrays, Max values, Zero values, First/last.
**Warning signs:** Medium or low confidence Scavenger recommendations. Any recommendation touching game state transitions.

### Pitfall 5: EVM Contract Size Limit Regression
**What goes wrong:** Code changes inadvertently increase bytecode of a contract already near the 24,576 byte limit.
**Why it happens:** JackpotModule is at 23,583 bytes (95.9% of limit). Even small additions could push it over.
**How to avoid:** Track bytecode sizes before and after changes. Dead code removal should only decrease sizes, but verify.
**Warning signs:** Compilation warnings about contract size exceeding limit.

## Code Examples

### Scavenger JSON Output Format (from skill definition)
```json
{
  "id": "SCAV-001",
  "file": "contracts/modules/DegenerusGameAdvanceModule.sol",
  "location": "line 245-250",
  "type": "unreachable_branch",
  "code": "if (gameState == 4) { ... }",
  "reasoning": "gameState can only be 1, 2, 3, or 86 per GAME_STATE_* constants. Value 4 is never assigned anywhere in the codebase.",
  "confidence": "high",
  "gas_estimate": {
    "bytecode_bytes": 45,
    "deployment_gas": 9000
  },
  "cross_contract_check_needed": false,
  "files_checked": ["DegenerusGameAdvanceModule.sol", "DegenerusGameStorage.sol"]
}
```

### Skeptic Verdict Format (from skill definition)
```json
{
  "scavenger_id": "SCAV-001",
  "verdict": "APPROVED",
  "reasoning": "Confirmed: gameState only ever holds values 1, 2, 3, or 86. Checked all assignments in all modules and storage.",
  "edge_cases_checked": [
    "gameover transition (86)",
    "level 0 initial state",
    "VRF callback during state change"
  ],
  "files_analyzed": ["DegenerusGame.sol", "DegenerusGameStorage.sol", "modules/*.sol"],
  "risk_assessment": "none",
  "implementation_notes": "Safe to remove entire if block. No downstream effects."
}
```

### Test Verification Command
```bash
# After each removal, verify no behavior change:
npm test 2>&1 | tail -5           # Full Hardhat suite (1,065+ tests)
npm run fuzz 2>&1 | tail -5       # Foundry fuzz tests (1,000 runs each)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual dead code grep | Scavenger/Skeptic dual-agent | Project-specific skill system | Structured analysis with JSON output and formal verdicts |
| Slither dead-code only | Slither + semantic analysis | Always (Slither catches syntactic only) | Slither found 0 results; semantic analysis needed for game-state-dependent dead code |
| Remove storage vars | Rename to `_deprecated_*` | Delegatecall pattern requirement | Preserves slot alignment; already used in codebase (line 1440) |
| Generic gas tips | Domain-specific Scavenger | gas-scavenger skill built for this exact codebase | Awareness of state machine, VRF, delegatecall patterns |

**Compiler context:**
- Solidity 0.8.34 with viaIR=true already performs Yul-level dead code elimination
- Optimizer runs=200 (Hardhat deployment) balances deployment vs runtime cost
- Solidity 0.8+ built-in overflow checks make many manual overflow guards redundant
- The 0.8.34 release specifically fixes an IR pipeline bug with storage/transient storage clearing (affects 0.8.28-0.8.33); this codebase is safe on 0.8.34

**Known dead/deprecated items already identified:**
1. `_deprecated_deityTicketBoostDay` (DegenerusGameStorage.sol:1440) -- explicitly deprecated mapping
2. DegenerusQuests.sol:228 `difficulty` field -- "Unused (fixed to 0); retained for storage compatibility"
3. BitPackingLib.sol:17,19 -- reserved/unused bit ranges [154-159] and [184-227]
4. DegenerusGame.sol:239 -- deprecated bit at position [244]
5. Slot 1 padding (DegenerusGameStorage.sol:65) -- 5 bytes unused in packed slot

## Open Questions

1. **How much bytecode do `_deprecated_*` storage mappings cost?**
   - What we know: Mappings don't occupy sequential slots (root slot is just for the mapping key derivation). The deprecated mapping at line 1440 adds a slot to the layout but costs zero bytecode if never accessed.
   - What's unclear: Whether any code still reads/writes `_deprecated_deityTicketBoostDay` anywhere.
   - Recommendation: Grep for all references; if zero, it costs nothing in bytecode and can remain as-is.

2. **What is the actual bytecode reduction per removed source line?**
   - What we know: With viaIR + runs=200, the compiler performs significant optimization. Not every removed source line maps 1:1 to bytecode reduction.
   - What's unclear: The exact multiplier varies by code pattern (branch elimination vs SLOAD removal vs function removal).
   - Recommendation: Measure before/after bytecode for each batch of removals. Focus on high-confidence Scavenger findings first.

3. **Can JackpotModule (95% of limit) be brought under 90%?**
   - What we know: 23,583 / 24,576 bytes. Need to remove ~993+ bytes to reach 90%.
   - What's unclear: How much dead code exists specifically in JackpotModule.
   - Recommendation: Prioritize JackpotModule in the Scavenger pass to assess potential savings.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Chai (JS) / Foundry (Solidity fuzz) |
| Config file | `hardhat.config.js` / `foundry.toml` |
| Quick run command | `npm run test:unit` |
| Full suite command | `npm test && npm run fuzz` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GAS-01 | Unreachable check removal preserves behavior | regression | `npm test` | Existing suite covers all paths |
| GAS-02 | Dead storage variable identification (no removal, just identification) | manual analysis | Scavenger/Skeptic workflow | N/A -- analysis only |
| GAS-03 | Dead code path removal preserves behavior | regression | `npm test && npm run fuzz` | Existing suite covers all paths |
| GAS-04 | Redundant call/SLOAD caching preserves behavior | regression | `npm test && npm run fuzz` | Existing suite covers all paths |

### Sampling Rate
- **Per task commit:** `npm run test:unit` (quick feedback, ~30s)
- **Per wave merge:** `npm test && npm run fuzz` (full suite, ~5-10 min)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. The 1,065+ Hardhat tests and Foundry fuzz tests serve as the behavior-preservation gate. No new tests need to be written; the entire phase is about removing code while keeping all existing tests green.

## Sources

### Primary (HIGH confidence)
- Project contracts: `contracts/storage/DegenerusGameStorage.sol` (1,608 lines, canonical storage layout analyzed)
- Project config: `hardhat.config.js` (Solidity 0.8.34, viaIR=true, optimizer runs=200)
- Project config: `foundry.toml` (Solidity 0.8.34, viaIR=true, optimizer runs=2)
- Project skills: `~/.claude/skills/gas-{audit,scavenger,skeptic}/SKILL.md` (workflow, JSON formats, edge case checklists)
- Slither 0.11.5 dead-code analysis: 0 findings on production contracts
- Bytecode sizes: measured from `artifacts/` (JackpotModule 23,583/24,576 bytes = 95.9%)

### Secondary (MEDIUM confidence)
- [Solidity 0.8.34 Release Announcement](https://www.soliditylang.org/blog/2026/02/18/solidity-0.8.34-release-announcement/) - IR pipeline bugfix for storage/transient storage clearing
- [Solidity Optimizer Documentation](https://docs.soliditylang.org/en/latest/internals/optimizer.html) - Dead code elimination behavior with viaIR
- [RareSkills Gas Optimization Guide](https://rareskills.io/post/gas-optimization) - General Solidity gas patterns

### Tertiary (LOW confidence)
- Gas-scavenger skill mentions "runs=2" -- this is INCORRECT for deployment (Hardhat uses runs=200). Foundry uses runs=2 for fuzz testing only.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - directly verified from project configs and artifacts
- Architecture: HIGH - storage layout and delegatecall pattern fully analyzed from source
- Pitfalls: HIGH - derived from project-specific architecture constraints (delegatecall, storage slots)
- Scavenger/Skeptic workflow: HIGH - skill definitions read directly from `~/.claude/skills/`

**Research date:** 2026-03-16
**Valid until:** 2026-04-15 (stable codebase, no expected compiler changes)
