# Project Research Summary

**Project:** Degenerus Protocol v6.0 — Test Cleanup + Storage/Gas Fixes + DegenerusCharity
**Domain:** Solidity smart contract protocol extension (GameFi + DeFi charity token)
**Researched:** 2026-03-25
**Confidence:** HIGH

## Executive Summary

This milestone delivers three tightly sequenced workstreams on a 23-contract immutable Solidity system already carrying five audit milestones of proven patterns. The first workstream (test cleanup) is a hard prerequisite for everything else: 13 Foundry tests are broken due to accumulated contract changes, and the dual Hardhat/Foundry suite has grown to 109 files with significant redundancy that should be documented now and pruned after all contract changes stabilize. The second workstream (storage/gas/event fixes) addresses five discrete audit findings — the most significant being `lastLootboxRngWord` removal (~15,000 gas saved per RNG cycle) and the I-12 degenerette freeze fix, which must be routed through the existing pending-pool side-channel rather than naively removing the guard, to avoid reintroducing the BAF cache-overwrite class of bug from v4.4. The third workstream (DegenerusCharity) is the only net-new contract and represents the bulk of implementation risk.

DegenerusCharity must be built as a standalone contract at deploy position N+23, using existing protocol patterns throughout: the soulbound ERC20 pattern from StakedDegenerusStonk, the proportional burn mechanics from `_deterministicBurnFrom`, and compile-time address injection via ContractAddresses. The protocol deliberately avoids OpenZeppelin ERC20 and Governor inheritance in favor of custom minimal implementations — DegenerusCharity follows this same pattern for consistency, bytecode efficiency, and to avoid importing transfer surfaces that would need to be overridden. Zero new npm or Foundry dependencies are required for the entire milestone.

The dominant risks are three: (1) the I-12 freeze fix, which looks like a one-line-safe change but silently reintroduces a critical class of bug if done without rerouting through `_setPendingPools`; (2) the `lastLootboxRngWord` removal, which must preserve the slot declaration (deprecate-not-delete) to avoid catastrophic delegatecall slot shift across all 10 modules; and (3) the `resolveLevel` hook added to `advanceGame`, which must carry an explicit gas cap (e.g., `{gas: 50_000}`) to protect the protocol's established gas budget headroom. All three risks are well-understood and have clear prevention strategies derived from prior audit deliverables in this repo.

---

## Key Findings

### Recommended Stack

The existing stack covers all v6.0 requirements with zero new dependencies. The protocol is pinned to Solidity 0.8.34, Foundry 1.5.1, forge-std 1.15.0, Hardhat 2.28.6, and OpenZeppelin 5.4.0 (used only for Base64/Strings in DeityPass). Upgrading OpenZeppelin to 5.6.x would introduce breaking Strings changes with no benefit, since DegenerusCharity uses no OZ contracts. All stETH integration relies on the existing minimal `IStETH.sol` interface (6 functions) and the existing `MockStETH.sol` with shares-based rebase modeling — both are already sufficient for all DegenerusCharity operations.

**Core technologies (all existing — no changes):**
- Solidity 0.8.34: All contracts including DegenerusCharity — locked; overflow protection built-in
- Foundry 1.5.1: Fuzz/invariant tests for Charity, fix verification — current stable, all cheatcodes present
- Hardhat 2.28.6: Integration tests, deploy scripts, coverage — current, no upgrade needed
- IStETH.sol + MockStETH.sol: stETH integration and testing — already sufficient for all Charity operations
- ContractAddresses.sol: Compile-time address injection — mechanical CHARITY constant append, established pattern

**What NOT to add (explicit scope traps):**
- OZ ERC20/Governor: protocol uses custom implementations throughout; inheriting OZ creates inconsistency and imports transfer surfaces to lock down
- wstETH: protocol is committed to rebasing stETH across StakedDegenerusStonk; mixing wstETH would create two Lido integration patterns
- OZ 5.6.x upgrade: breaking Strings changes with zero benefit for this milestone
- Any automated test deduplication tool: no production-quality tool compares Hardhat JS semantics to Foundry Solidity semantics; use LCOV-based manual coverage comparison

### Expected Features

**Must have (table stakes):**
- Fix 13 broken Foundry tests (3 TicketLifecycle, 4 LootboxRngLifecycle, 2 VRFCore, 1 VRFLifecycle, 3 VRFStallEdgeCases, 1 FuturepoolSkim) — CI must be green before any contract changes
- Green baseline established for both `forge test` and `npx hardhat test`
- Remove `lastLootboxRngWord` writes (3 sites in AdvanceModule: L162, L862, L1526) and swap the 1 read site in JackpotModule L1838 to `lootboxRngWordByIndex[lootboxRngIndex - 1]` — slot declaration kept as `// DEPRECATED`
- Fix double `_getFuturePrizePool()` SLOAD in earlybird/early-burn paths — cache first read, reuse local variable
- Fix `RewardJackpotsSettled` event emitting pre-reconciliation `futurePoolLocal` — emit `futurePoolLocal + rebuyDelta` instead
- Allow degenerette ETH resolution during prize pool freeze — route frozen-context payouts through `_setPendingPools` (not naive revert removal)
- Fix BitPackingLib NatSpec "bits 152-154" to "bits 152-153" — documentation only, zero bytecode change
- DegenerusCharity.sol: soulbound CHARITY token (no transfer function), burn-for-proportional-ETH/stETH redemption, per-level sDGNRS-weighted governance voting
- Yield surplus split routing a share to CHARITY via `_distributeYieldSurplus` in JackpotModule (BPS values TBD by economics team)
- `resolveLevel` hook in AdvanceModule notifying DegenerusCharity at each level transition (try/catch with explicit gas cap)
- CHARITY added to `claimWinningsStethFirst` allowlist in DegenerusGame

**Should have (differentiators):**
- Foundry invariant tests for CHARITY solvency: `sum(balanceOf) == totalSupply` and ETH/stETH backing invariant
- Hardhat integration test for the full CHARITY governance lifecycle (propose -> vote -> level transition -> yield distributed)
- Gas ceiling re-measurement of `advanceGame` after `resolveLevel` hook addition (same methodology as v3.5 Phase 57)
- Test delta audit after each storage/gas fix to detect regressions immediately

**Defer to v2+:**
- Test redundancy pruning: defer until after all contract changes stabilize (Phase 6); pruning now then adding new CHARITY tests wastes effort
- Formal verification (Halmos) of CHARITY burn math: follow-up milestone; fuzz tests are sufficient for v6.0
- stETH shares-based accounting (`transferShares()`): 1-2 wei stETH rounding is economically insignificant; document as accepted behavior and address in a dedicated shares-accounting milestone

### Architecture Approach

DegenerusCharity deploys as standalone contract N+23, never as a delegatecall module. All delegatecall modules execute in DegenerusGame's storage context — a charity contract needs its own balance sheet and must not touch the shared storage layout. The contract integrates at exactly four touch points: (1) ContractAddresses.CHARITY compile-time constant, (2) a yield share added to JackpotModule `_distributeYieldSurplus`, (3) addition to the `claimWinningsStethFirst` allowlist in DegenerusGame, and (4) a non-reverting `resolveLevel` hook in AdvanceModule. The deprecate-not-delete pattern governs storage variable retirements: `lastLootboxRngWord` keeps its slot declaration to prevent catastrophic slot shift across all 10 delegatecall modules.

**Major components:**
1. DegenerusGameStorage — canonical slot layout; `lastLootboxRngWord` deprecated-not-deleted to preserve slot positions
2. DegenerusGameAdvanceModule — removes 3 `lastLootboxRngWord` writes; gains a try/catch `resolveLevel{gas: 50_000}` hook post-level-bump
3. DegenerusGameJackpotModule — swaps 1 `lastLootboxRngWord` read to `lootboxRngWordByIndex[lootboxRngIndex - 1]`; caches `_getFuturePrizePool()` reads at 3 call sites; gains a CHARITY BPS share in `_distributeYieldSurplus`
4. DegenerusGameEndgameModule — emits `RewardJackpotsSettled` with post-reconciliation `futurePoolLocal + rebuyDelta`
5. DegenerusGameDegeneretteModule — routes frozen-context ETH payouts through `_setPendingPools` instead of reverting
6. DegenerusGame — adds CHARITY to `claimWinningsStethFirst` allowlist (single line)
7. DegenerusCharity (new, N+23) — soulbound CHARITY token, sDGNRS-weighted per-level governance, ETH/stETH pool, burn-for-proportional-yield redemption
8. ContractAddresses + deploy pipeline — CHARITY constant + nonce-prediction extension to N+23 across predictAddresses.js, patchForFoundry.js, DeployProtocol.sol, DeployScript.test.js

### Critical Pitfalls

1. **BAF cache-overwrite reintroduction via I-12 fix** — Removing `if (prizePoolFrozen) revert E()` without rerouting silently reintroduces the exact class of bug from v4.4 Phases 100-102, where a cached `futurePrizePool` local is written back and clobbers any modification made during the freeze window. Prevention: route frozen-context ETH payouts through `_setPendingPools` (matching lines 558-561 bet-placement pattern), re-run BAF cache-overwrite scan, add Foundry test verifying ETH conservation across resolution-during-freeze.

2. **Storage slot shift from `lastLootboxRngWord` declaration removal** — Deleting the variable declaration shifts every subsequent slot in the 78+ slot DegenerusGameStorage layout; all 10 delegatecall modules read wrong storage. Prevention: keep the slot declaration as `// DEPRECATED`, remove only the 3 write sites and update the 1 read site. Never delete storage variable declarations in this codebase.

3. **ContractAddresses nonce prediction failure for CHARITY** — Wrong nonce prediction bakes an incorrect CHARITY address into every contract at compile time; all cross-contract calls revert or send funds into the void. Prevention: update predictAddresses.js, patchForFoundry.js, and DeployProtocol.sol together; run DeployCanary.t.sol to verify all address predictions match actual deploys.

4. **`resolveLevel` hook gas regression in `advanceGame`** — The try/catch forwards nearly all remaining gas to the callee under EIP-150; without an explicit gas limit, a misbehaving charity contract can exhaust the transaction gas budget on the most gas-sensitive protocol path (~18.9M worst-case with 34.9% headroom). Prevention: `try ICharity(CHARITY).resolveLevel{gas: 50_000}(...) {} catch {}`; profile `advanceGame` gas ceiling before and after hook addition.

5. **Burn-for-proportional-yield rounding and last-holder dust trap** — Computing ETH and stETH payouts independently doubles rounding loss; small burns round to zero; stETH `transfer(X)` may move `X-1` wei; the last burner has dust permanently trapped. Prevention: enforce minimum burn amount; compute combined `totalValue * amount / supply` then split by ratio (matching sDGNRS pattern); add last-holder sweep that uses raw `address(this).balance` and `steth.balanceOf(this)` directly.

6. **CHARITY governance mint-vote-burn attack** — If minting is permissionless and governance uses current live balance, an attacker can mint, vote, and burn within the same block without capital lock-up. Prevention: delegate charity parameter governance to the existing sDGNRS mechanism in DegenerusAdmin (one governance system, one attack surface); or use snapshot-based voting where balance snapshot is taken at proposal creation block.

7. **Test pruning removes unique coverage** — Tests named vaguely or written for specific audit findings may look redundant but cover distinct branches. Prevention: generate LCOV reports from both suites before any pruning; verify coverage-before minus coverage-after equals zero lost lines; never prune a test whose filename references an audit finding ID.

---

## Implications for Roadmap

All four research files converge on the same six-phase dependency-driven structure. FEATURES.md derives it from feature ordering constraints, ARCHITECTURE.md from data-flow dependencies, and PITFALLS.md from which phase must address each critical pitfall. The convergence gives high confidence in this ordering.

### Phase 1: Test Suite Cleanup

**Rationale:** Green baseline is a hard prerequisite. The 4 LootboxRngLifecycle and 3 VRFStallEdgeCases tests reference `lastLootboxRngWord` — they must be fixed before the variable is removed, or regressions from Phase 2 changes will be invisible. No contract code changes in this phase eliminates regression risk entirely.
**Delivers:** Both `forge test` and `npx hardhat test` passing 100%; documented coverage map for safe Phase 6 pruning; identified (but not yet pruned) Hardhat/Foundry redundancies.
**Addresses:** 13 broken Foundry tests (fix, not remove); coverage-guided redundancy identification.
**Avoids:** Pitfall 7 (test pruning without coverage baseline). Fix broken tests first — broken tests covering unique code must be repaired, not removed.
**Research flag:** Standard patterns. Root causes fully diagnosed. No additional research needed.

### Phase 2: Storage and Gas Fixes

**Rationale:** Simpler, more surgical changes than CHARITY integration; establishes the delta-audit verification pattern for subsequent phases. `lastLootboxRngWord` removal must happen before CHARITY integration because both phases touch JackpotModule — doing them together risks merge conflicts and complicates delta analysis. Defer I-12 to Phase 3 to isolate its higher-risk BAF analysis.
**Delivers:** ~15,000 gas saved per RNG cycle; accurate `RewardJackpotsSettled` events for off-chain indexers; double SLOAD eliminated at 3 JackpotModule call sites; BitPackingLib NatSpec corrected.
**Implements:** Deprecate-not-delete pattern for storage, cache-and-reuse pattern for SLOAD elimination.
**Avoids:** Pitfall 1 (BAF reintroduction — I-12 is deferred), Pitfall 2 (slot shift — slot declaration kept).
**Research flag:** Standard patterns. All five fixes have exact line-level analysis in audit findings. Mechanical implementation.

### Phase 3: Degenerette Freeze Fix (I-12)

**Rationale:** Separated from Phase 2 because it requires a BAF cache-overwrite re-scan and a dedicated ETH conservation audit. Keeping it isolated means any conservation invariant failure is attributable to exactly this one change, not mixed with other fixes.
**Delivers:** ETH degenerette bets resolve during `advanceGame` without reverting; ETH conservation invariant preserved; Foundry test verifying resolution-during-freeze accounting.
**Implements:** `_setPendingPools` routing for frozen-context payouts (matching existing bet-placement pattern at lines 558-561).
**Avoids:** Pitfall 1 (BAF cache-overwrite reintroduction — the highest-consequence risk in the milestone).
**Research flag:** Needs BAF scan context. Before implementation, load v4.4 Phase 100-102 deliverables to bound the re-scan scope.

### Phase 4: DegenerusCharity Contract Core

**Rationale:** Purely additive — new contract only, no modifications to existing contracts. Lower risk than phases modifying audited contracts. ContractAddresses and deploy pipeline updates are sub-step zero: they must land before any integration points can reference the CHARITY address.
**Delivers:** DegenerusCharity.sol with soulbound token, proportional burn-for-ETH/stETH redemption, per-level sDGNRS-weighted governance; standalone Foundry fuzz tests for burn math and solvency invariants; updated DeployProtocol.sol at nonce N+23; DeployCanary.t.sol verification passing.
**Implements:** StakedDegenerusStonk soulbound pattern; `_deterministicBurnFrom` proportional burn; DegenerusAdmin governance pattern (adapted for per-level charity voting); ContractAddresses compile-time address injection.
**Avoids:** Pitfall 3 (nonce prediction failure — DeployCanary.t.sol is required gate), Pitfall 5 (burn rounding — combined value computation + last-holder sweep + minimum burn), Pitfall 6 (governance attack — use sDGNRS live balance governance or snapshot-based voting).
**Research flag:** Governance design sub-step needs explicit design doc before coding. The per-level voting mechanics (vote window, quorum, tie-breaking, reset on level transition) are novel with no prior audit coverage. CHARITY token mint trigger is also unspecified and affects governance attack surface.

### Phase 5: Game Integration

**Rationale:** Modifying three existing audited contracts (DegenerusGame, JackpotModule, AdvanceModule) requires CHARITY to exist first. Integration changes touch the most sensitive paths (advanceGame, yield surplus distribution) and must come after the standalone contract is fully tested.
**Delivers:** Yield surplus split routing to CHARITY; CHARITY added to `claimWinningsStethFirst` allowlist; `resolveLevel` hook in AdvanceModule; gas ceiling delta analysis for `advanceGame`; full integration test of end-to-end yield flow to CHARITY.
**Implements:** Game credit pull pattern (CHARITY accumulates claimable in DegenerusGame, then pulls via `claimWinningsStethFirst`); non-reverting external hook pattern (try/catch with explicit gas limit).
**Avoids:** Pitfall 4 (gas regression — explicit `{gas: 50_000}` cap on hook; gas ceiling profiling required before phase completion).
**Research flag:** BPS rebalance values require economics team sign-off before touching `_distributeYieldSurplus`. The buffer floor (~8%) must be preserved. Do not begin JackpotModule edits without confirmed target percentages.

### Phase 6: Audit, Polish, and Test Pruning

**Rationale:** Only meaningful after all contract changes are finalized. Test redundancy pruning against a stable codebase does not risk pruning tests that become relevant again due to later changes. Gas profiling is meaningful only against the final state.
**Delivers:** Full delta audit across all cumulative changes from Phases 2-5; LCOV-based coverage diff for safe redundancy pruning; NatSpec and documentation sync; final green suites for both Hardhat and Foundry.
**Avoids:** Pitfall 7 (coverage loss from pruning — coverage-before-and-after diff with zero-lines-lost success criterion).
**Research flag:** Standard. Coverage methodology well-understood. No additional research needed.

### Phase Ordering Rationale

- Phase 1 first: green baseline is the only way to distinguish regressions from pre-existing failures; the LootboxRng/VRFStall test fixes touch the same variable being removed in Phase 2.
- Phase 2 before Phase 3: storage/gas fixes are mechanically simpler; they establish the delta-audit workflow before tackling the BAF-sensitive freeze fix.
- Phase 3 isolated from Phase 2: the I-12 fix has a distinct BAF reintroduction risk warranting its own delta audit scope and BAF scan.
- Phase 4 before Phase 5: the CHARITY address must exist in ContractAddresses before any existing contract can reference it at compile time.
- Phase 5 after Phase 4: integration modifies 3 existing audited contracts and requires the Charity address and behavior to be stable.
- Phase 6 last: redundancy pruning and gas profiling are only meaningful against the final, stable codebase.

### Research Flags

Phases needing deeper research or external input before planning:
- **Phase 3 (I-12 Freeze Fix):** Load v4.4 Phase 100-102 deliverables to bound the BAF re-scan scope before implementation begins.
- **Phase 4 (CHARITY Governance Design):** Write an explicit governance design doc (vote window boundaries, quorum formula, tie-breaking, mint trigger, reset on level transition) before any governance code. This is the most novel element in the milestone with no prior audit coverage.
- **Phase 5 (BPS Rebalance):** Economics team must provide target CHARITY yield split BPS before touching `_distributeYieldSurplus`. The buffer floor (~8%) must be preserved in any rebalance.

Phases with standard patterns (no additional research needed):
- **Phase 1 (Test Cleanup):** Root causes fully diagnosed. LCOV-based coverage methodology well-understood.
- **Phase 2 (Storage/Gas Fixes):** All five fixes have exact line-level analysis in audit findings. Mechanical implementation.
- **Phase 4 (CHARITY Token Core):** Soulbound pattern, burn mechanics, and ContractAddresses integration all have working protocol exemplars to copy from.
- **Phase 6 (Audit + Pruning):** Coverage methodology well-established. No new research needed.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions verified against installed state. Zero new dependencies needed. "What not to add" guidance verified against OZ release notes and Lido docs. |
| Features | HIGH (storage/test fixes) / MEDIUM (CHARITY governance) | Test fixes and storage/gas changes have exact line-level analysis. CHARITY governance mechanics are partially unspecified — per-level voting design, mint trigger, and BPS split values are open questions requiring external input. |
| Architecture | HIGH | Six-phase build order derived from dependency analysis with clear rationale. All patterns have working codebase exemplars. Anti-patterns documented with specific failure scenarios (slot shift, nonce misprediction, BAF reintroduction). |
| Pitfalls | HIGH | Seven pitfalls all derived from direct codebase analysis or directly applicable prior audit findings (BAF from v4.4 Phases 100-102, slot shift from storage layout docs, stETH rounding from Lido issue #442, governance attacks from established Solidity security patterns). |

**Overall confidence:** HIGH

### Gaps to Address

- **CHARITY governance design spec:** Per-level voting mechanics (vote window boundaries, quorum formula, tie-breaking, vote reset on level transition) are unspecified. Resolve as the first sub-step of Phase 4 before any governance code is written.
- **CHARITY token mint trigger:** How and when CHARITY tokens are minted to players is not specified in the research. The mint trigger (game action, level reward, admin mint) affects the governance attack surface (Pitfall 6) and must be designed before governance implementation.
- **CHARITY yield split BPS values:** The target percentage to carve from the existing 23%/23%/46%/~8% split is unspecified. Economics team must provide this before Phase 5 can safely modify `_distributeYieldSurplus`. Buffer floor (~8%) must be preserved.
- **I-12 freeze fix BAF scan scope:** The exact set of code paths to re-scan for BAF cache-overwrite after the I-12 fix should be derived from v4.4 Phase 100-102 deliverables. Load those artifacts as context before Phase 3 planning.

---

## Sources

### Primary (HIGH confidence — verified against codebase)

- `contracts/storage/DegenerusGameStorage.sol` — canonical slot layout, `lastLootboxRngWord` position
- `contracts/StakedDegenerusStonk.sol` — soulbound pattern, `_deterministicBurnFrom` burn mechanics, BPS constants
- `contracts/DegenerusAdmin.sol` — existing governance propose/vote/execute lifecycle
- `contracts/ContractAddresses.sol` — compile-time address library (23 entries)
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_distributeYieldSurplus` (L883-913), earlybird double-read (L774-778), `processTicketBatch` entropy consumer (L1838)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `lastLootboxRngWord` write sites (L162, L862, L1526), `_finalizeRngRequest` hook target
- `contracts/modules/DegenerusGameEndgameModule.sol` — `RewardJackpotsSettled` event (L252)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — freeze guard (L685), pending pools pattern (L558-561)
- `contracts/libraries/BitPackingLib.sol` — NatSpec discrepancy (L59)
- `audit/FINDINGS.md` — I-07, I-09, I-12, I-26 consolidated findings
- `audit/unit-02/UNIT-02-FINDINGS.md` — `lastLootboxRngWord` staleness (F-04 INFO)
- `audit/unit-03/UNIT-03-FINDINGS.md` — double `_getFuturePrizePool` (F-04 INFO)
- `scripts/lib/predictAddresses.js` — DEPLOY_ORDER array (23 entries), nonce prediction chain
- `test/fuzz/helpers/DeployProtocol.sol` — Foundry 23-contract nonce-ordered deploy base
- Installed tools: `forge --version` (1.5.1), `npx hardhat --version` (2.28.6), `lib/forge-std/package.json` (1.15.0), `node_modules/@openzeppelin/contracts/package.json` (5.4.0)

### Secondary (MEDIUM confidence — external documentation)

- [Lido stETH integration guide](https://docs.lido.fi/guides/steth-integration-guide/) — shares vs balances, rebasing, wstETH alternative
- [Lido tokens integration guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/) — transferShares, rounding dust, rebase timing
- [Lido core issue #442](https://github.com/lidofinance/core/issues/442) — 1-2 wei stETH transfer imprecision (confirmed behavior)
- [OpenZeppelin Contracts releases](https://github.com/OpenZeppelin/openzeppelin-contracts/releases) — 5.6.0 breaking Strings changes confirmed; 5.4.0 is correct pin
- [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192) / [ERC-7787](https://eips.ethereum.org/EIPS/eip-7787) — reviewed and ruled out as anti-features for this protocol
- [Solidity storage layout docs](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html) — slot assignment rules, deletion consequences
- [OWASP Smart Contract Top 10 2025](https://owasp.org/www-project-smart-contract-top-10/) — CEI, reentrancy, governance attack classification

---
*Research completed: 2026-03-25*
*Ready for roadmap: yes*
