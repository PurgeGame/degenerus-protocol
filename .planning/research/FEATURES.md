# Feature Landscape: v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity

**Domain:** Smart contract maintenance, gas optimization, and new charity token for GameFi protocol
**Researched:** 2026-03-25
**Overall confidence:** MEDIUM-HIGH (codebase analysis HIGH, DeFi charity pattern research MEDIUM)

## Executive Summary

This milestone has three distinct feature categories with different risk profiles:

1. **Test suite cleanup** (13 broken Foundry tests + redundancy pruning) -- mechanical work with well-understood root causes. The broken tests stem from contract changes that invalidated test helpers (double-buffer slot assertions, VRF state assumptions after `lastLootboxRngWord` removal). No production code changes required for fixes.

2. **Storage/gas/event fixes** (5 specific findings) -- surgical edits to existing audited contracts. Each fix addresses a single INFO-level finding with a well-understood scope. Risk is in delta regressions, not in the fix logic itself.

3. **DegenerusCharity contract** -- a net-new soulbound token with governance voting and burn-for-proportional-yield redemption. This is the heaviest feature and the only one requiring new contract architecture. It follows the established sDGNRS pattern closely but introduces per-level governance and dual-asset (ETH + stETH) redemption from a yield-funded pool.

---

## Table Stakes

Features that are expected and necessary. Missing these means the milestone is incomplete.

### Test Suite Cleanup

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Fix 13 broken Foundry tests | 355/369 passing (96.2%). CI must be green before any contract changes | LOW-MED | None -- test-only changes | Root causes: 3 TicketLifecycle tests (wrong buffer slot in `_readKeyForLevel` helper, I-03), 4 LootboxRngLifecycle tests (assume `lastLootboxRngWord` state that will be removed), 2 VRFCore tests (stale VRF request assumption), 1 VRFLifecycle test (level advancement assertion), 3 VRFStallEdgeCases tests (2 assert `lastLootboxRngWord != 0`, 1 mid-day pending assertion), 1 FuturepoolSkim test (80% cap precision boundary) |
| Identify redundant Foundry tests | ~12,000 lines of Foundry tests accumulated over 19 milestones. Overlap is inevitable | LOW | Must complete test fixes first | Compare coverage maps between fuzz tests and invariant tests. Identify tests superseded by later, more comprehensive test files |
| Identify redundant Hardhat tests | 19 Hardhat test files (~1208 tests). Some may duplicate Foundry coverage | LOW | None | Cross-reference Hardhat unit tests against Foundry fuzz/invariant coverage. Flag tests that are strict subsets of fuzz test coverage |
| Establish green baseline | Both `forge test` and `npx hardhat test` must pass 100% before contract changes begin | LOW | Test fixes must land first | Current: Foundry 355/14 failing, Hardhat presumably passing (1208 prior baseline). Baseline needed for regression detection |
| Document test coverage map | Which contract functions are covered by which test files | MED | Test analysis complete | Needed to identify pruning candidates safely. Map each `.t.sol` to the contract functions it exercises |

### Storage/Gas/Event Fixes

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Remove `lastLootboxRngWord` storage variable | Redundant: all consumers use `lootboxRngWordByIndex[index]` directly. Saves 3 SSTOREs per RNG cycle (~60K gas/day). Identified as dead variable across v5.0 adversarial audit | MED | Test fixes must land first (4+ tests reference this variable). Must update: DegenerusGameStorage.sol (declaration), AdvanceModule (3 write sites), JackpotModule (1 read site, must switch to `lootboxRngWordByIndex`) | **3 write sites:** AdvanceModule L162 (mid-day ticket processing), L862 (`_finalizeLootboxRng`), L1526 (`_backfillOrphanedLootboxIndices`). **1 read site:** JackpotModule L1838 (`processTicketBatch` entropy source). Read site must be changed to use `lootboxRngWordByIndex[lootboxRngIndex]` or equivalent. Delta audit needed post-change |
| Fix double `_getFuturePrizePool()` SLOAD in earlybird/early-burn (I-07/F-04) | Gas waste: reads same storage slot twice with no intervening write. Costs 100 gas per occurrence (warm SLOAD) | LOW | None | JackpotModule L774-778: `reserveContribution = (_getFuturePrizePool() * 300) / 10_000` then `_setFuturePrizePool(_getFuturePrizePool() - reserveContribution)`. Fix: cache in local, use cached value for subtraction. Already have `reserveContribution` computed from the first read |
| Fix `RewardJackpotsSettled` event stale value (I-09) | Event emits pre-reconciliation `futurePoolLocal` instead of post-reconciliation value. Off-chain indexers see wrong pool value | LOW | None | EndgameModule L252: `emit RewardJackpotsSettled(lvl, futurePoolLocal, claimableDelta)`. Fix: emit after reconciliation with `futurePoolLocal + rebuyDelta` (or read fresh storage). Single-line change |
| Allow degenerette ETH resolution during prize pool freeze (I-12) | Currently reverts with `E()` when `prizePoolFrozen` is true. ETH bets resolved during `advanceGame` fail transiently. Other currencies (BURNIE, WWXRP) unaffected | MED | Requires understanding of prize pool freeze lifecycle | DegeneretteModule L685: `if (prizePoolFrozen) revert E()`. The freeze is transient (within single `advanceGame` tx). Fix options: (a) queue ETH payouts during freeze for later distribution, (b) use pending pool mechanism, (c) allow resolution from the non-frozen pool. Must verify no corruption of jackpot math snapshot |
| Fix BitPackingLib NatSpec "bits 152-154" to "bits 152-153" (I-26) | Documentation error: whale bundle type is 2 bits (mask = 3), spanning bits 152-153, not 152-154. 3 bits would be mask = 7 | LOW | None | BitPackingLib.sol L59: `/// @notice Bit position for whale bundle type (bits 152-154)` should be `(bits 152-153)`. Pure NatSpec fix, zero bytecode change |

### DegenerusCharity Contract

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Soulbound CHARITY token (ERC20-like, no transfer) | Core token for the charity system. Must be non-transferable to prevent secondary market gaming. Follows sDGNRS pattern (soulbound, balance tracking, burn mechanics) | MED | ContractAddresses.sol must include CHARITY address | Pattern exists: sDGNRS is already a soulbound ERC20-like token. CHARITY follows the same no-`transfer()` approach. Must emit `Transfer` events for indexer compatibility despite soulbinding |
| Per-level sDGNRS governance for charity distributions | sDGNRS holders vote on which charity receives yield distributions each level. Not the existing DegenerusAdmin governance (VRF swap) -- this is a separate voting mechanism | HIGH | sDGNRS balance queries, level transition hook from game | Novel: existing governance (DegenerusAdmin) is for VRF coordinator swaps only. Charity governance is per-level, simpler (no time-decay threshold, no stall prerequisite). Must define: voting mechanism, quorum, vote counting, winner selection, vote window |
| Burn-for-proportional-ETH/stETH redemption | CHARITY holders burn tokens to claim proportional share of accumulated ETH + stETH backing. Follows sDGNRS deterministic burn pattern | HIGH | ETH/stETH reserves must be tracked, supply must be accurate for proportional math | Pattern exists: sDGNRS `_deterministicBurnFrom` does exactly this. `ethOut = (amount * ethBal) / supplyBefore`, `stethOut = (amount * stethBal) / supplyBefore`. Must handle: dust accumulation, zero-supply edge case, stETH rebase during burn |
| Yield surplus split integration | Game's `_distributeYieldSurplus` currently splits: 23% sDGNRS, 23% Vault, 46% yield accumulator, ~8% buffer. A slice must route to DegenerusCharity | MED | JackpotModule `_distributeYieldSurplus` must be modified. Requires delta audit of yield math | Currently at JackpotModule L883-914. Adding a CHARITY recipient means rebalancing BPS allocations. Must preserve the ~8% buffer for stETH rebase protection |
| ContractAddresses integration | CHARITY contract address must be a compile-time constant in ContractAddresses.sol. Deploy order must be predicted via CREATE nonce | LOW | Deploy script update needed | Pattern exists: all 23 contracts use this same mechanism. CHARITY is contract #24 (or wherever it falls in deploy order). Nonce prediction is deterministic |
| `resolveLevel` hook / level transition trigger | CHARITY token distribution or governance action triggered on each level transition during `advanceGame` | MED | AdvanceModule level transition code path | Must integrate into the existing level transition flow. The `advanceGame` call is already the most gas-intensive path (~14M ceiling). Adding a cross-contract call to CHARITY during level transition adds gas. Must measure impact against the 30M block limit |

---

## Differentiators

Features that add value beyond the basic requirements. Not strictly expected but improve quality.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| stETH-first allowlist for charity | Allow the charity contract to hold stETH directly (yield-bearing) rather than converting to ETH | LOW | IStETH interface already defined | sDGNRS already holds stETH directly and distributes proportionally on burn. CHARITY should follow the same pattern. `steth.balanceOf(address(this))` for balance, `steth.transfer(recipient, amount)` for distribution |
| Test delta audit for each contract change | After each storage/gas fix, run full test suite and document which tests were affected | LOW | Green baseline established | Standard audit methodology for this repo. Prevents regression accumulation. Each fix should be a discrete commit with its own delta verification |
| Gas ceiling re-measurement after CHARITY integration | The `advanceGame` path is the most gas-intensive (~14M current ceiling). Adding CHARITY hook could push it closer to block limit | MED | CHARITY contract deployed and integrated | v3.5 Phase 57 measured gas ceilings. Any new cross-contract call in `advanceGame` needs re-measurement. If CHARITY hook exceeds ~5M gas headroom, it must be optimized or deferred to a separate transaction |
| Invariant tests for CHARITY solvency | Foundry invariant test proving: `sum(balanceOf) == totalSupply`, and `address(this).balance + steth.balanceOf(address(this)) >= sum(ethOwed)` | MED | CHARITY contract implemented | Follows the pattern from RedemptionInvariants.inv.t.sol and EthSolvency.inv.t.sol. Solvency proof is the single most valuable test for a burn-for-yield contract |
| Hardhat test for CHARITY governance lifecycle | Full lifecycle test: propose charity -> vote -> level transition -> winner announced -> yield distributed | MED | CHARITY governance implemented | Integration-level test exercising the full charity voting flow. Important because per-level governance is novel (no prior audit coverage) |

---

## Anti-Features

Features to explicitly NOT build. These are scope traps or bad patterns.

| Anti-Feature | Why It Seems Valuable | Why Avoid | What to Do Instead |
|--------------|----------------------|-----------|-------------------|
| ERC-5192 NFT-based soulbound implementation | Standard for soulbound tokens. Widely referenced | ERC-5192 is for NFTs (ERC-721 extension). CHARITY is fungible (ERC-20-like). Using ERC-721 adds per-token tracking overhead with no benefit for a fungible charity token | Follow the sDGNRS pattern: custom ERC20-like with no `transfer()` function. Simpler, cheaper, and already proven in this codebase |
| ERC-7787 degradable governance | Novel standard for soulbound governance with vote decay | Adds unnecessary complexity. CHARITY governance is simple (one vote per level, winner gets yield). Time-decay makes sense for long-running DAOs, not per-level game votes that resolve in hours | Simple approval voting with sDGNRS-weighted votes. No decay. Vote once per level, resolved at level transition |
| Separate governance contract for CHARITY | DegenerusAdmin pattern: dedicated governance contract with proposals, thresholds, execution | Over-engineered. DegenerusAdmin governance exists for VRF emergency swaps (high-stakes, rare). CHARITY voting is routine (every level) and low-stakes (yield distribution direction, not protocol control) | Inline governance within DegenerusCharity.sol itself. `vote(charityId)` + `resolveLevel()` pattern. No proposal lifecycle needed |
| Wrapping CHARITY in a transferable token (like DGNRS wraps sDGNRS) | Allows secondary market trading for charity tokens | Defeats the purpose of soulbound. Charity tokens should represent participation, not a tradeable financial instrument. Secondary market creates perverse incentives (buy votes instead of earn them) | Keep CHARITY strictly soulbound. No wrapper. No transferability |
| Optimistic burn (burn first, verify later) | Reduce gas by skipping some checks during burn | Violates CEI pattern and creates reentrancy surface. sDGNRS gambling burn already required a fix for CP-08 (double-spend when pending reservations not subtracted) | Full checks-effects-interactions. Verify balance, compute proportional share, burn tokens, then transfer assets. Same pattern as sDGNRS `_deterministicBurnFrom` |
| Multi-token backing (ETH + stETH + BURNIE + other) | More assets = more value backing CHARITY | Adds complexity without proportional value. BURNIE backing in sDGNRS required coinflip integration, pending redemption tracking, gambling burn lifecycle -- enormous surface area. CHARITY should be simple | ETH + stETH only. Two assets, proportional burn. No BURNIE, no coinflip, no gambling burn lifecycle |
| Automated test generation from coverage maps | AI-assisted test generation to fill coverage gaps | Generated tests are brittle, hard to maintain, and often test implementation details rather than behavior. This repo already has 12,000 lines of hand-written, semantically meaningful tests | Manual identification of coverage gaps. Write targeted tests for actual behavioral gaps, not mechanical line coverage |
| Prune tests to minimize total count | Fewer tests = faster CI | Wrong optimization target. Test speed matters, test count does not. A 100ms fuzz test covering 1000 runs is more valuable than removing 10 unit tests that take 50ms total | Prune by redundancy (tests that are strict subsets of other tests), not by count. Focus on removing tests whose assertions are fully covered by invariant tests |

---

## Feature Dependencies

```
                    ContractAddresses update
                           |
          +----------------+----------------+
          |                                 |
  DegenerusCharity.sol               Deploy script update
          |
    +-----+-----+-----+
    |           |     |
  Soulbound  Per-level  Burn-for-
  token      governance  yield
    |           |         |
    |     resolveLevel    |
    |     hook in         |
    |     AdvanceModule   |
    |           |         |
    +-----+-----+-----+--+
          |
  Yield surplus split
  (JackpotModule)
          |
  Gas ceiling re-measurement

  ---

  Test fixes (independent track)
          |
  Green baseline
          |
  +-------+-------+
  |               |
  Redundancy    Storage/Gas/Event
  analysis      fixes (I-07, I-09,
  + pruning     I-12, I-26,
                lastLootboxRngWord)
                  |
                Delta audit per fix
```

Key ordering constraints:

1. **Test fixes BEFORE contract changes.** Must have a green baseline to detect regressions. The 4 LootboxRngLifecycle tests and 3 VRFStallEdgeCases tests reference `lastLootboxRngWord` -- they must be fixed BEFORE the variable is removed, or they must be rewritten as part of the removal.

2. **`lastLootboxRngWord` removal BEFORE DegenerusCharity.** The removal touches AdvanceModule and JackpotModule. CHARITY's yield surplus integration also touches JackpotModule. Do the removal first to avoid merge conflicts and double delta audits.

3. **ContractAddresses update BEFORE DegenerusCharity deployment.** The CHARITY address must be a compile-time constant. All other contracts that reference CHARITY (JackpotModule for yield split, AdvanceModule for resolveLevel hook) need the address baked in.

4. **Yield surplus split AFTER DegenerusCharity core.** The charity contract must exist and have its receive/deposit functions before the yield surplus can route funds to it.

5. **Gas ceiling measurement LAST.** Only meaningful after all contract changes are finalized. Adding measurements mid-stream wastes effort on intermediate states.

---

## MVP Recommendation

**Phase 1 -- Test Cleanup (low risk, high value):**
1. Fix 13 broken Foundry tests (addresses known root causes per I-03 and `lastLootboxRngWord` assumptions)
2. Verify Hardhat suite still green
3. Document coverage map for later pruning

**Phase 2 -- Storage/Gas/Event Fixes (medium risk, discrete changes):**
1. Remove `lastLootboxRngWord` (3 write sites, 1 read site swap)
2. Fix double `_getFuturePrizePool()` SLOAD (I-07)
3. Fix `RewardJackpotsSettled` stale event value (I-09)
4. Fix degenerette ETH resolution during freeze (I-12) -- requires most careful analysis
5. Fix BitPackingLib NatSpec (I-26) -- trivial
6. Delta audit each fix

**Phase 3 -- DegenerusCharity Contract (high complexity, new code):**
1. ContractAddresses update with CHARITY address
2. DegenerusCharity.sol core: soulbound token + burn-for-ETH/stETH
3. Per-level governance voting
4. Yield surplus split integration in JackpotModule
5. resolveLevel hook in AdvanceModule
6. Gas ceiling re-measurement

**Defer:**
- Test redundancy pruning: do after all contract changes stabilize. Pruning now then adding new tests for CHARITY is counterproductive.
- Formal verification of CHARITY burn math: can be a follow-up milestone if the protocol team wants the same Halmos coverage as sDGNRS.

---

## Complexity Budget

| Feature Area | Est. Lines Changed | Risk Level | Audit Depth Needed |
|-------------|-------------------|------------|-------------------|
| Test fixes (13 tests) | ~200-400 test lines | LOW | Verify fixes match root cause analysis |
| `lastLootboxRngWord` removal | ~20 contract lines, ~100 test lines | MEDIUM | Delta audit: verify no consumer remains, test all VRF paths |
| Double SLOAD fix (I-07) | ~3 contract lines | LOW | Mechanical: cache local, reuse |
| Event stale value fix (I-09) | ~1 contract line | LOW | Verify post-reconciliation value is correct |
| Degenerette freeze fix (I-12) | ~10-30 contract lines | MEDIUM | Must verify prize pool snapshot integrity. This is the riskiest storage fix |
| BitPackingLib NatSpec (I-26) | 1 line | TRIVIAL | NatSpec only, zero bytecode |
| DegenerusCharity.sol | ~300-500 new contract lines | HIGH | Full audit: solvency proof, governance attack vectors, burn math, stETH rebase handling |
| Yield surplus split | ~20-30 changed lines in JackpotModule | MEDIUM | Must preserve buffer, verify no obligation undershoot |
| resolveLevel hook | ~10-20 changed lines in AdvanceModule | MEDIUM | Gas ceiling impact, failure isolation |
| Test redundancy analysis | ~0 lines (documentation) | LOW | Cross-reference coverage maps |

**Total new/changed contract code:** ~400-650 lines
**Total new/changed test code:** ~500-800 lines

---

## Sources

### Codebase Analysis (HIGH confidence)
- `contracts/StakedDegenerusStonk.sol` -- soulbound token pattern, burn mechanics, governance interface
- `contracts/DegenerusStonk.sol` -- liquid wrapper pattern (anti-pattern for CHARITY)
- `contracts/DegenerusAdmin.sol` -- existing governance (propose/vote/execute) as reference
- `contracts/ContractAddresses.sol` -- compile-time address library pattern
- `contracts/modules/DegenerusGameJackpotModule.sol` L883-914 -- yield surplus distribution
- `contracts/modules/DegenerusGameEndgameModule.sol` L240-253 -- event emission timing
- `contracts/modules/DegenerusGameDegeneretteModule.sol` L680-688 -- prize pool freeze behavior
- `contracts/libraries/BitPackingLib.sol` L59 -- NatSpec error
- `contracts/storage/DegenerusGameStorage.sol` L1231 -- `lastLootboxRngWord` declaration
- `audit/FINDINGS.md` -- v5.0 adversarial audit findings (I-02, I-07, I-09, I-12)
- Foundry test output: 355 pass / 14 fail across test/fuzz/ and test/fuzz/invariant/

### External Research (MEDIUM confidence)
- [ERC-5192: Minimal Soulbound NFTs](https://eips.ethereum.org/EIPS/eip-5192) -- NFT-based soulbound standard (not applicable to fungible tokens)
- [ERC-7787: Soulbound Degradable Governance](https://eips.ethereum.org/EIPS/eip-7787) -- vote decay model (over-engineered for per-level voting)
- [Lido stETH Token Integration Guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/) -- stETH balance is rebasing, transfers may lose 1-2 wei due to share rounding
- [Solidity Gas Optimization (RareSkills)](https://rareskills.io/post/gas-optimization) -- SSTORE costs, storage removal patterns, EIP-2200/EIP-3529 refund rules
- [Solidity Event Emission Risks (Vibranium Audits)](https://www.vibraniumaudits.com/post/incorrect-event-emission-in-solidity-risks-and-best-practices) -- stale value emission patterns, CEI ordering for events
- [Foundry Testing (RareSkills)](https://rareskills.io/post/foundry-testing-solidity) -- test organization, independence, naming conventions
