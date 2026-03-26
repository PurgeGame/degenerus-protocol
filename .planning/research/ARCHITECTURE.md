# Architecture Research

**Domain:** Solidity protocol extension -- new contract + storage/gas fixes + test cleanup for 23-contract immutable system
**Researched:** 2026-03-25
**Confidence:** HIGH

## Existing System Overview

```
+==============================================================================+
|                        DEPLOYMENT LAYER (CREATE nonce N+0..N+22)             |
+==============================================================================+
|  ContractAddresses.sol  -- compile-time constant library, patched per deploy |
|  23 addresses baked into every contract as immutable constants               |
+==============================================================================+

+==============================================================================+
|                        GAME CORE (DegenerusGame @ N+13)                     |
+===================+==================+=======================================+
| DelegateCall      | Module           | Slot Source                           |
| Modules           |                  |                                       |
+-------------------+------------------+---------------------------------------+
| N+1  MintModule   | ticket purchase  | DegenerusGameStorage (inherited)      |
| N+2  AdvanceModule | advanceGame/VRF | DegenerusGameStorage (inherited)      |
| N+3  WhaleModule  | whale bundles    | DegenerusGameStorage (inherited)      |
| N+4  JackpotModule| prize pools/yield| DegenerusGameStorage (inherited)      |
| N+5  DecimatorMod | decimator logic  | DegenerusGameStorage (inherited)      |
| N+6  EndgameModule| reward jackpots  | DegenerusGameStorage (inherited)      |
| N+7  GameOverMod  | terminal state   | DegenerusGameStorage (inherited)      |
| N+8  LootboxModule| lootbox open     | DegenerusGameStorage (inherited)      |
| N+9  BoonModule   | deity boons      | DegenerusGameStorage (inherited)      |
| N+10 Degenerette  | roulette bets    | DegenerusGameStorage (inherited)      |
+-------------------+------------------+---------------------------------------+

+==============================================================================+
|                        STANDALONE CONTRACTS                                  |
+===================+==========================================================+
| N+0  Icons32Data  | On-chain icon bitmap storage                             |
| N+11 BurnieCoin   | BURNIE ERC20 token                                       |
| N+12 Coinflip     | BURNIE gambling coinflip                                 |
| N+14 WWXRP        | Wrapped Wrapped XRP (meme layer)                         |
| N+15 Affiliate    | Referral tracking + commissions                          |
| N+16 Jackpots     | Historical jackpot records                               |
| N+17 Quests       | Player quest state machine                               |
| N+18 DeityPass    | ERC721 deity passes                                      |
| N+19 Vault        | ETH/stETH/BURNIE vault (DGVE + DGVB shares)             |
| N+20 sDGNRS       | Soulbound governance token                               |
| N+21 DGNRS        | Liquid wrapper for sDGNRS                                |
| N+22 Admin        | VRF governance, emergency admin                          |
+===================+==========================================================+

+==============================================================================+
|                        EXTERNAL DEPENDENCIES                                 |
+===================+==========================================================+
| Chainlink VRF v2  | Randomness oracle (coordinator + LINK subscription)      |
| Lido stETH        | ETH yield via staked ETH rebasing                        |
+===================+==========================================================+
```

### Component Responsibilities Relevant to v6.0

| Component | Responsibility | v6.0 Touch Point |
|-----------|----------------|-------------------|
| DegenerusGameStorage | Canonical slot layout for Game + all delegatecall modules | `lastLootboxRngWord` removal (slot reclamation) |
| DegenerusGameAdvanceModule | VRF request/fulfill, daily advance, lootbox RNG finalization | Writes `lastLootboxRngWord` in 3 paths (L162, L862, L1526); add resolveLevel hook in `_finalizeRngRequest` |
| DegenerusGameJackpotModule | Prize pool consolidation, yield surplus distribution, earlybird | Reads `lastLootboxRngWord` (L1838), double `_getFuturePrizePool` (L774/778, L601/604), yield split target for Charity |
| DegenerusGameEndgameModule | Reward jackpots, BAF reconciliation | `RewardJackpotsSettled` stale event (L252) |
| DegenerusGameDegeneretteModule | Roulette bets and resolution | ETH resolution blocked during freeze (L685) |
| ContractAddresses | Compile-time address constants for all 23 contracts | Must add `CHARITY` constant for DegenerusCharity |
| DegenerusGame | Core router, claimWinnings, stETH-first allowlist | `claimWinningsStethFirst` allowlist expansion (L1354-1357) |
| BitPackingLib | Bit-field pack/unpack utilities | NatSpec fix (I-26, L59) |

## DegenerusCharity Integration Architecture

### Why Standalone (NOT a Delegatecall Module)

DegenerusCharity MUST be a standalone contract, not a delegatecall module, because:

1. **No shared storage needed.** Charity has its own state (CHARITY token balances, burn accounting, sDGNRS governance) that is independent of `DegenerusGameStorage`.
2. **Delegatecall modules cannot hold their own ETH/stETH.** All delegatecall modules execute in DegenerusGame's storage context. A charity contract needs its own balance sheet.
3. **Simpler security surface.** Adding storage variables to `DegenerusGameStorage` for a non-game feature risks slot collision and increases the audit surface of all 10 existing modules.
4. **Deployment flexibility.** As N+23, it deploys after all existing contracts. No nonce reordering.

### Integration Points (4 Touch Points)

```
DegenerusCharity (N+23, standalone)
    |
    |-- [1] ContractAddresses.CHARITY
    |       Added as compile-time constant at nonce N+23.
    |       Consumed by DegenerusGame and DegenerusCharity itself.
    |
    |-- [2] Yield surplus split (_distributeYieldSurplus in JackpotModule)
    |       Current: 23% DGNRS, 23% Vault, 46% accumulator, ~8% buffer
    |       New: carve out share for CHARITY from the yield pool.
    |       Requires: _addClaimableEth(ContractAddresses.CHARITY, share, rngWord)
    |       Impact: JackpotModule L883-913 modified (BPS rebalance).
    |
    |-- [3] claimWinningsStethFirst allowlist (DegenerusGame)
    |       Current: only VAULT and SDGNRS can call.
    |       New: add CHARITY to the allowlist.
    |       Impact: DegenerusGame L1354-1357 (add one address check).
    |
    |-- [4] resolveLevel hook in _finalizeRngRequest (AdvanceModule)
    |       New: notify DegenerusCharity at level transition time.
    |       Impact: AdvanceModule L1320+ (add external call after level bump).
    |       Security: must be non-reverting (try/catch or fire-and-forget).
```

### Data Flow: Yield to Charity

```
stETH rebase
    |
    v
DegenerusGame balance increases (stETH appreciation)
    |
    v
consolidatePrizePools() called at level transition (via delegatecall to JackpotModule)
    |
    v
_distributeYieldSurplus() calculates: totalBal - obligations = yieldPool
    |
    +---> 23% to SDGNRS via _addClaimableEth     (existing)
    +---> 23% to VAULT via _addClaimableEth       (existing)
    +---> 46% to yieldAccumulator                  (existing)
    +---> X% to CHARITY via _addClaimableEth       (NEW -- carved from existing split)
    +---> ~8% buffer (unextracted)                 (existing, percentage may shift)
    |
    v
DegenerusCharity calls game.claimWinningsStethFirst()
    |
    v
Charity receives stETH, manages burn-for-ETH/stETH economy
```

### DegenerusCharity Internal Architecture

```
DegenerusCharity
+------------------------------------------------------------------+
| CHARITY Token (soulbound ERC20, no transfer)                     |
|   - Minted to players via game rewards or direct actions         |
|   - Burned to redeem proportional ETH/stETH from charity pool   |
+------------------------------------------------------------------+
| sDGNRS Governance                                                |
|   - Reuses governance patterns from StakedDegenerusStonk         |
|   - sDGNRS holders vote on charity disbursement parameters       |
+------------------------------------------------------------------+
| ETH/stETH Pool                                                   |
|   - Funded by yield surplus split from DegenerusGame             |
|   - Drained by CHARITY token burns (proportional redemption)     |
+------------------------------------------------------------------+
| External Calls                                                   |
|   - game.claimWinningsStethFirst() to pull accrued yield         |
|   - steth.transfer() for stETH payouts                          |
|   - ETH transfers for ETH payouts                               |
+------------------------------------------------------------------+
```

## Storage Fix: lastLootboxRngWord Removal

### Current State

`lastLootboxRngWord` is declared at `DegenerusGameStorage.sol` L1231 in the Lootbox Module Storage section.

**Writers (3 paths in AdvanceModule):**
- L162: `lastLootboxRngWord = word` (mid-day ticket processing)
- L862: `lastLootboxRngWord = rngWord` (daily `_finalizeLootboxRng`)
- L1526: `lastLootboxRngWord = fallbackWord` (gap backfill)

**Reader (1 path in JackpotModule):**
- L1838: `uint256 entropy = lastLootboxRngWord` (processTicketBatch trait entropy)

### Why Removable

The v5.0 audit proved `lastLootboxRngWord` is a convenience cache. Every actual lootbox resolution uses `lootboxRngWordByIndex[index]` (the per-index mapping). The only consumer is `processTicketBatch` for trait-assignment entropy, where any recent VRF-derived value suffices. This was confirmed as INFO finding F-04 in Unit 2 (AdvanceModule audit): "No functional impact -- lastLootboxRngWord is only used as a convenience entropy source."

### Removal Strategy

| Item | Action |
|------|--------|
| Storage slot | Keep declaration in DegenerusGameStorage. Add `// DEPRECATED: no longer written` comment. NEVER remove the declaration -- this would shift all subsequent slots and corrupt every delegatecall module. |
| AdvanceModule L162 | Delete `lastLootboxRngWord = word;` (saves 1 SSTORE per mid-day RNG) |
| AdvanceModule L862 | Delete `lastLootboxRngWord = rngWord;` (saves 1 SSTORE per daily advance) |
| AdvanceModule L1526 | Delete `lastLootboxRngWord = fallbackWord;` (saves 1 SSTORE per gap backfill) |
| JackpotModule L1838 | Replace `lastLootboxRngWord` with `lootboxRngWordByIndex[lootboxRngIndex - 1]`. Both are warm SLOADs (mapping key lookup + value read). Gas-neutral for the reader. |
| Foundry tests | Any test asserting `lastLootboxRngWord != 0` must be updated to check `lootboxRngWordByIndex` instead. |
| Hardhat tests | Likely no direct assertions on this internal variable, but verify. |

**Gas savings:** 3 SSTOREs removed per RNG cycle. At warm write cost (5,000 gas each post-EIP-2929), saves ~15,000 gas per cycle. Cold first-write saves are larger (~20,000 each).

## Gas Fix: Double _getFuturePrizePool() in JackpotModule

### Current Pattern (Unit 3 F-04 / consolidated I-07)

Two paths in `DegenerusGameJackpotModule.sol` read `_getFuturePrizePool()` twice with no intervening write:

**Path 1: _runEarlyBirdLootboxJackpot (L774-778)**
```solidity
uint256 reserveContribution = (_getFuturePrizePool() * 300) / 10_000; // SLOAD #1
_setFuturePrizePool(_getFuturePrizePool() - reserveContribution);     // SLOAD #2
```

**Path 2: Daily jackpot early-burn path (L601-604)**
```solidity
ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000;            // SLOAD #1
_setFuturePrizePool(_getFuturePrizePool() - ethDaySlice);            // SLOAD #2
```

### Fix Pattern

Cache the first read in a local variable:
```solidity
uint256 fp = _getFuturePrizePool();                                   // SLOAD #1 only
uint256 reserveContribution = (fp * 300) / 10_000;
_setFuturePrizePool(fp - reserveContribution);                        // No SLOAD #2
```

All `_setFuturePrizePool(_getFuturePrizePool() - X)` call sites in JackpotModule (L415/418, L601/604, L774/778) follow this same double-read pattern. Each saves ~100 gas (warm SLOAD under EIP-2929).

**Important:** `_getFuturePrizePool()` reads from a packed `prizePoolsPacked` slot (two uint128 values). The getter unpacks via assembly. The setter repacks. Each round-trip is 2 SLOADs (one for the packed slot, one for the function call overhead). Caching eliminates one of those round-trips per call site.

## Event Fix: RewardJackpotsSettled (I-09)

### Current State

```solidity
// EndgameModule L252
emit RewardJackpotsSettled(lvl, futurePoolLocal, claimableDelta);
```

`futurePoolLocal` is the cached future pool value at function entry. After the BAF cache-overwrite fix (v4.4), `rebuyDelta` is computed at L245 and applied at L246 via `_setFuturePrizePool(futurePoolLocal + rebuyDelta)`. The event emits the pre-reconciliation value, which is incorrect for off-chain indexers.

### Fix

```solidity
emit RewardJackpotsSettled(lvl, futurePoolLocal + rebuyDelta, claimableDelta);
```

Single-line change. No state impact -- purely cosmetic event correction. The `rebuyDelta` variable is already in scope.

## Degenerette Freeze Fix (I-12)

### Current State

`_distributePayout` in DegeneretteModule (L685) reverts with `E()` when `prizePoolFrozen` is true. The freeze is transient (only within `advanceGame` execution), so this only blocks ETH degenerette resolution during the same transaction as `advanceGame`. BURNIE and WWXRP resolutions are unaffected.

### Architecture Decision: Allow Resolution During Freeze

The fix must separate the timing concern (pool snapshot integrity) from the user-facing action. The payout flow currently deducts from `_getFuturePrizePool()` at L687-703. During freeze, this would corrupt the snapshot that `runRewardJackpots` is operating on.

**Option A (recommended):** Queue the ETH payout into the player's `claimableWinnings` directly, bypassing the `_getFuturePrizePool()` deduction when frozen. The ETH is already in the contract from the bet deposit, so crediting claimable is safe. This requires:
1. Check if `prizePoolFrozen` at L685
2. If frozen: credit full payout to `claimableWinnings[player]` and `claimablePool`, skip pool deduction
3. If not frozen: existing logic (25/75 ETH/lootbox split with 10% pool cap)

**Impact:** Changes the payout behavior during the transient freeze window only. ETH conservation invariant must be re-verified. The bet deposit ETH is already in the contract's balance; routing it to claimable instead of through the pool split is a different accounting path but preserves total obligations.

**Risk assessment:** MEDIUM -- requires careful ETH conservation re-verification. The freeze window is very narrow (within a single `advanceGame` tx), so the practical impact is minimal, but the accounting change touches a critical path.

## BitPackingLib NatSpec Fix (I-26)

Single-line NatSpec comment change at `BitPackingLib.sol` L59: "bits 152-154" should read "bits 152-153" (2-bit field, mask=3). No code change. No test impact.

## Test Architecture

### Current State

| Framework | File Count | Location | Role |
|-----------|-----------|----------|------|
| Hardhat (JS) | 44 `.test.js` files | `test/{access,adversarial,deploy,edge,gas,integration,poc,simulation,unit,validation}/` | Unit tests, integration, adversarial, simulation |
| Foundry (Sol) | 46 `.t.sol` files | `test/fuzz/` + `test/fuzz/{handlers,helpers,invariant}/` | Fuzz, invariant, integration, Halmos proofs |

**Configuration:**
- Hardhat: `hardhat.config.js` -- ordered directory execution (access -> deploy -> unit -> integration -> edge -> validation -> gas -> adversarial -> simulation), Solidity 0.8.34, optimizer runs=200
- Foundry: `foundry.toml` -- `src=contracts`, `test=test/fuzz`, via_ir, Paris EVM, optimizer runs=2, 1000 fuzz runs, 256 invariant runs/128 depth

**Key infrastructure:**
- `test/fuzz/helpers/DeployProtocol.sol` -- Foundry base: deploys 5 mocks + 23 protocol contracts with nonce-predicted addresses
- `test/fuzz/helpers/VRFHandler.sol` -- VRF mock interaction helper
- `test/fuzz/helpers/NonceCheck.t.sol` -- Validates Foundry deploy addresses match predictions
- `test/helpers/deployFixture.js` -- Hardhat `loadFixture` for full protocol
- `test/helpers/testUtils.js` -- Common JS utilities

### Overlap Assessment

Both frameworks test overlapping domains:

| Domain | Hardhat Coverage | Foundry Coverage | Redundancy Risk |
|--------|-----------------|------------------|-----------------|
| Contract deployment | `test/deploy/DeployScript.test.js` | `DeployProtocol.sol` + `NonceCheck.t.sol` | LOW -- both needed (JS deploy vs Sol deploy) |
| VRF lifecycle | `test/integration/VRFIntegration.test.js` | `VRFCore.t.sol`, `VRFLifecycle.t.sol`, `VRFPathCoverage.t.sol`, `VRFStallEdgeCases.t.sol` | HIGH -- Foundry is far more comprehensive |
| Ticket processing | `test/unit/DegenerusGame.test.js` (partial) | `TicketLifecycle.t.sol`, `TicketRouting.t.sol`, `TicketProcessingFF.t.sol`, `TicketEdgeCases.t.sol` | HIGH -- Foundry fuzz > Hardhat unit |
| Prize pool arithmetic | `test/edge/PriceEscalation.test.js` | `PrizePoolFreeze.t.sol`, `FuturepoolSkim.t.sol` | MEDIUM -- different angles |
| Gas profiling | `test/gas/AdvanceGameGas.test.js` | (inline in various `.t.sol`) | LOW -- different purpose |
| Adversarial scenarios | `test/adversarial/*.test.js` (3 files) | N/A (v5.0 was agent-based, not test-based) | LOW -- unique coverage |
| PoC tests | `test/poc/Phase24-28*.test.js` (5 files) | N/A | AUDIT -- one-shot proofs from specific audit phases, may be archivable |
| Simulation | `test/simulation/simulation-*.test.js` (2 files) | N/A | LOW -- unique multi-level sims |

### Test Cleanup Strategy

**Principle:** Foundry owns correctness/fuzz. Hardhat owns integration/deployment/simulation.

**Phase 1: Fix broken tests (13 Foundry failures)**
- Identify which `.t.sol` files fail and why
- Likely causes: storage layout drift from v3.8-v4.4 changes, missing mock updates
- Fix without changing test intent

**Phase 2: Audit for redundancy**
- `test/poc/` -- Phase 24-28 PoC tests proved specific audit points. Move to `test/archived/` if they duplicate Foundry coverage.
- `test/edge/RngStall.test.js` -- Likely duplicated by `VRFStallEdgeCases.t.sol` and `StallResilience.t.sol`
- `test/validation/` -- Parity checks between simulation and contracts. If one-shot, archive.
- `test/adversarial/` -- Keep if covering scenarios not in v5.0 deliverables.

**Phase 3: Establish green baseline**
- Both `npx hardhat test` and `forge test` pass with zero failures
- Document the expected test counts in a baseline file

### Adding DegenerusCharity Tests

New tests belong in Foundry (`test/fuzz/`) because:
1. Burn/redemption math needs fuzz testing
2. Integration with yield split requires `DeployProtocol.sol` extension
3. All post-v3.3 contract tests have been Foundry-first

**DeployProtocol.sol changes:**
- Add `DegenerusCharity public charity;` to protocol contract declarations
- Deploy at nonce N+23 in `_deployProtocol()`
- `patchForFoundry.js` must predict the N+23 address and patch `ContractAddresses.sol`
- `DeployScript.test.js` -- update "deployer nonce advances by exactly 23" to "exactly 24"

## Deployment Impact

### ContractAddresses.sol Changes

Adding DegenerusCharity as the 24th contract:

```solidity
// New line in ContractAddresses.sol
address internal constant CHARITY = address(0x...); // N+23, patched by deploy script
```

**Full cascade of files requiring changes:**

| File | Change | Risk |
|------|--------|------|
| `contracts/ContractAddresses.sol` | Add `CHARITY` constant | LOW -- append only |
| `scripts/lib/predictAddresses.js` | Add `"CHARITY"` to `DEPLOY_ORDER` at index 23; add to `KEY_TO_CONTRACT` | LOW -- append only |
| `scripts/lib/patchContractAddresses.js` | Handle CHARITY constant patching | LOW |
| `scripts/deploy.js` | Add constructor args for DegenerusCharity | LOW |
| `scripts/deploy-local.js` | Mirror deploy.js changes | LOW |
| `test/fuzz/helpers/DeployProtocol.sol` | Deploy charity at N+23 | MEDIUM -- must get nonce right |
| `patchForFoundry.js` (or equivalent) | Predict N+23 address | MEDIUM |
| `test/deploy/DeployScript.test.js` | Update nonce count: 23 -> 24 | LOW |
| `contracts/DegenerusGame.sol` L1354-1357 | Add CHARITY to stethFirst allowlist | LOW -- single line |
| `contracts/modules/DegenerusGameJackpotModule.sol` L883-913 | Add CHARITY share to yield split | MEDIUM -- BPS arithmetic change |
| `contracts/modules/DegenerusGameAdvanceModule.sol` L1320+ | Add resolveLevel hook | MEDIUM -- new external call in critical path |

### Deploy Order Safety

DegenerusCharity at N+23 has no ordering conflict:
- No constructor-time cross-contract calls to contracts that must exist first
- ADMIN at N+22 is the last contract with constructor-time dependencies
- CHARITY deploys last, can reference all existing contracts

If DegenerusCharity's constructor reads from any existing contract, those contracts exist at N+0..N+22.

## Architectural Patterns

### Pattern 1: Standalone Contract with Game Credit Pull

**What:** DegenerusCharity accumulates ETH/stETH credit in `DegenerusGame.claimableWinnings[CHARITY]`, then pulls via `claimWinningsStethFirst()`.
**When to use:** Any new contract receiving a share of game yield/prizes.
**Trade-offs:** Simple (reuses existing pull pattern), introduces claim lag (funds sit in Game until pulled). Acceptable for yield accumulation where timing is not critical.

### Pattern 2: Deprecate-Not-Delete for Storage Variables

**What:** Mark storage variables as deprecated with comments, stop writing to them, but never remove the declaration.
**When to use:** Any storage variable removal in the DegenerusGameStorage hierarchy.
**Trade-offs:** Wastes one slot of "dead" storage, but prevents catastrophic slot shift in all 10 delegatecall modules. The only correct trade-off for immutable contracts with shared storage.

### Pattern 3: Non-Reverting External Hook

**What:** Level-transition notification to DegenerusCharity uses try/catch.
**When to use:** Any new external call from AdvanceModule to a standalone contract during critical game flow.
**Trade-offs:** Charity contract failure cannot brick `advanceGame`. Gas overhead of try/catch is ~2,000 gas. Must never pass mutable state or delegate authority in the hook.

```solidity
// In AdvanceModule._finalizeRngRequest, after level bump:
try IDegenerusCharity(ContractAddresses.CHARITY).onLevelResolved(lvl) {} catch {}
```

## Anti-Patterns

### Anti-Pattern 1: Adding State to Delegatecall Modules

**What people do:** Declare new storage variables in a module contract (e.g., EndgameModule).
**Why it is wrong:** Module code executes in DegenerusGame's storage context via delegatecall. Any variable declared in the module shadows/collides with DegenerusGameStorage slots. Result: catastrophic data corruption.
**Do this instead:** All shared storage goes in DegenerusGameStorage. Module-specific state goes in standalone contracts.

### Anti-Pattern 2: Reordering DEPLOY_ORDER

**What people do:** Insert the new contract in the middle of the deploy order for "logical grouping."
**Why it is wrong:** Every contract after the insertion point gets a different nonce, different address, and all compile-time ContractAddresses constants become wrong. Requires full redeployment of all contracts.
**Do this instead:** Always append new contracts at the end of DEPLOY_ORDER.

### Anti-Pattern 3: Synchronous Expensive Operations in advanceGame

**What people do:** Make advanceGame call DegenerusCharity.someExpensiveOperation() synchronously.
**Why it is wrong:** advanceGame is already gas-heavy (worst case ~18.9M gas with 34.9% headroom to 30M block limit per v4.2 audit). Adding synchronous external calls risks exceeding the block gas limit on edge paths.
**Do this instead:** Use lightweight notification hooks (resolveLevel) that do O(1) work. Let Charity handle complex logic in its own transactions, pulled by external callers.

### Anti-Pattern 4: Removing Storage Variable Declarations

**What people do:** Delete `uint256 internal lastLootboxRngWord;` from DegenerusGameStorage to "clean up."
**Why it is wrong:** All subsequent variable slots shift by 1 (256 bits). Every mapping, array, and uint256 declared after it now occupies a different slot. Every delegatecall module (10 contracts) reads the wrong storage. Unrecoverable corruption.
**Do this instead:** Keep the declaration, add `// DEPRECATED` comment, remove all writers. The slot remains allocated but unused.

## Suggested Build Order

Based on dependency analysis:

```
Phase 1: Test Suite Cleanup (no contract changes)
    - Fix 13 broken Foundry tests
    - Audit Hardhat/Foundry overlap
    - Prune redundant tests
    - Establish green baseline: both suites pass

Phase 2: Storage + Gas + Event + NatSpec Fixes (minimal contract changes)
    - lastLootboxRngWord deprecation (AdvanceModule writes x3, JackpotModule read x1, Storage)
    - Double _getFuturePrizePool fix (JackpotModule x3 call sites)
    - RewardJackpotsSettled event fix (EndgameModule L252)
    - BitPackingLib NatSpec fix (L59)
    - Delta audit: verify no behavioral change except gas savings + event accuracy
    - Run both test suites

Phase 3: Degenerette Freeze Fix (small contract change, needs ETH conservation audit)
    - Allow ETH resolution during freeze via claimable routing
    - ETH conservation invariant re-verification
    - New Foundry test for resolution-during-freeze scenario

Phase 4: DegenerusCharity Contract (new contract, no integration yet)
    - ContractAddresses.sol: add CHARITY constant
    - Deploy infrastructure: predictAddresses, deploy scripts, patchForFoundry
    - DegenerusCharity.sol: soulbound CHARITY token, governance, burn-for-ETH/stETH
    - Standalone tests: Foundry fuzz for burn/redemption math
    - DeployProtocol.sol: add Charity to Foundry deploy helper
    - DeployScript.test.js: update nonce count to 24

Phase 5: Game Integration (existing contract modifications)
    - JackpotModule._distributeYieldSurplus: add CHARITY BPS share
    - DegenerusGame.claimWinningsStethFirst: add CHARITY to allowlist
    - AdvanceModule._finalizeRngRequest: add resolveLevel hook (try/catch)
    - Full integration test: yield flows through to Charity, claim works
    - ETH conservation re-verification (invariant tests)
    - RNG commitment window re-verification (new external call in AdvanceModule)

Phase 6: Audit + Polish
    - Delta audit of all cumulative contract changes
    - Full test suite green (Hardhat + Foundry)
    - Documentation sync (NatSpec, audit docs, parameter reference)
```

**Ordering rationale:**
- Phase 1 first: green baseline is prerequisite for validating all subsequent changes via delta testing.
- Phase 2 before 3: storage/gas fixes are simpler, establish the delta verification pattern.
- Phase 3 before 4: degenerette fix modifies existing module behavior (risk), while Phase 4 is purely additive (lower risk).
- Phase 4 before 5: Charity contract must exist before integration points can reference its address.
- Phase 5 after 4: integration modifies 3 existing contracts (Game, JackpotModule, AdvanceModule) and requires the Charity address in ContractAddresses.
- Phase 6 last: delta audit must cover all cumulative changes from Phases 2-5.

## Sources

- `contracts/ContractAddresses.sol` -- 23-contract address library (38 lines)
- `contracts/storage/DegenerusGameStorage.sol` -- canonical slot layout, `lastLootboxRngWord` at L1231
- `contracts/DegenerusGame.sol` -- core router, `claimWinningsStethFirst` allowlist at L1352-1357
- `contracts/modules/DegenerusGameJackpotModule.sol` -- `_distributeYieldSurplus` L883-913, `processTicketBatch` L1838, earlybird double-read L774-778, daily early-burn L601-604
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- `_finalizeRngRequest` L1320+, `lastLootboxRngWord` writes at L162, L862, L1526
- `contracts/modules/DegenerusGameEndgameModule.sol` -- `RewardJackpotsSettled` event at L252, `_addClaimableEth` at L267
- `contracts/modules/DegenerusGameDegeneretteModule.sol` -- `_distributePayout` freeze guard at L685
- `contracts/libraries/BitPackingLib.sol` -- NatSpec discrepancy at L59
- `scripts/lib/predictAddresses.js` -- `DEPLOY_ORDER` array (23 entries), nonce prediction
- `scripts/deploy.js` -- deploy pipeline: predict -> patch -> compile -> deploy
- `test/fuzz/helpers/DeployProtocol.sol` -- Foundry 23-contract deployment base
- `test/deploy/DeployScript.test.js` -- nonce count assertion ("exactly 23")
- `foundry.toml` -- Foundry config (via_ir, Paris EVM, 1000 fuzz runs)
- `hardhat.config.js` -- Hardhat config (ordered test directory execution, 9 directories)
- `audit/FINDINGS.md` -- I-07 (double read), I-09 (stale event), I-12 (freeze), I-26 (NatSpec)
- `audit/unit-02/UNIT-02-FINDINGS.md` -- `lastLootboxRngWord` staleness (F-04 INFO)
- `audit/unit-03/UNIT-03-FINDINGS.md` -- double `_getFuturePrizePool` (F-04 INFO)

---
*Architecture research for: Degenerus Protocol v6.0 -- DegenerusCharity + storage/gas fixes + test cleanup*
*Researched: 2026-03-25*
