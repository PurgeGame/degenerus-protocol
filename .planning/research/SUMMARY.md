# Project Research Summary

**Project:** Degenerus Protocol v3.0 -- Invariant Fuzzing and Blind Adversarial Hardening
**Domain:** Security hardening for a 22-contract DeFi/GameFi protocol via Foundry invariant testing and independent adversarial attack sessions
**Researched:** 2026-03-05
**Supersedes:** SUMMARY.md dated 2026-03-04 (v2.0 audit)
**Confidence:** HIGH

## Executive Summary

The Degenerus Protocol has completed two audit milestones (v1.0 module-by-module, v2.0 adversarial C4-prep) covering all 22 contracts and 10 delegatecall modules with zero Critical/High/Medium findings. The v3.0 milestone shifts from static/manual analysis to dynamic invariant fuzzing and blind adversarial attack sessions. The goal is to find sequence-dependent bugs that unit tests structurally cannot reach -- multi-step state transitions, cross-function interactions under random ordering, and edge cases in the VRF-gated game state machine. Foundry invariant testing is the right tool: it is already partially set up in the project (3 stateless fuzz tests, forge-std 1.15.0, foundry.toml configured), the community patterns are mature, and no additional toolchain is needed beyond a solc version alignment fix.

The recommended approach deploys the full 22-contract protocol inside Foundry's test EVM using the existing `patchContractAddresses.js` pipeline adapted for Foundry's deterministic deployer. Four focused handler contracts (GameHandler, VRFHandler, WhaleHandler, CoinHandler) drive the fuzzer through valid state transitions while ghost variables track ETH flows and token balances for invariant assertions. Five invariant harnesses cover the critical properties: ETH solvency, BurnieCoin supply conservation, game FSM transitions, vault share math, and ticket queue ordering. In parallel, four blind adversarial attack sessions with distinct attacker personas (whale, block proposer, Sybil group, protocol insider) target specific attack surfaces with contradiction-framed briefs designed to overcome anchoring bias from prior audits.

The primary risk is the ContractAddresses compile-time constant problem -- Foundry cannot deploy the real protocol without address patching. The research converged on a patch-compile-deploy strategy using the existing infrastructure (`patchContractAddresses.js`, `predictAddresses.js`), not mock-only isolation. This is more work upfront but produces dramatically higher-value invariant tests that exercise real cross-contract interactions. The secondary risk is poor state coverage: without a VRF fulfillment handler, the game gets permanently stuck at level 0 and all deep-state invariants are vacuously true. Both risks have clear, validated mitigations.

## Key Findings

### Recommended Stack

The project already has a working Foundry setup (v1.5.1, forge-std 1.15.0) alongside the existing Hardhat suite (884 tests). No additional libraries or tools are needed -- not Echidna, Medusa, Halmos, or any Hardhat-Foundry bridge plugin. The critical blocker is that production contracts now use `pragma solidity 0.8.34`, which Foundry's built-in version resolver cannot download. The workaround -- pointing `foundry.toml` at the Hardhat-cached solc binary at `~/.cache/hardhat-nodejs/compilers-v2/linux-amd64/solc-linux-amd64-v0.8.34+commit.80d5c536` -- has been verified locally. Existing fuzz test files need a one-line pragma fix (`0.8.26` to `^0.8.26`).

**Core technologies:**
- **Foundry invariant testing (v1.5.1)**: stateful sequence-based fuzzing with handler contracts, ghost variables, and multi-target support -- already installed, needs solc config and `[invariant]` section in `foundry.toml`
- **forge-std 1.15.0**: cheatcodes (`bound()`, `vm.prank`, `vm.deal`, `vm.warp`, `vm.startPrank`) -- already installed at `lib/forge-std`, current
- **Existing patch pipeline** (`patchContractAddresses.js` + `predictAddresses.js`): adapted for Foundry deployer address prediction via new `patchForFoundry.js` -- eliminates ContractAddresses blocker without FFI

**Explicitly not needed:** Echidna, Medusa, Halmos, Slither re-run, hardhat-foundry plugin, solmate, PRBMath, Certora.

### Expected Features

**Must have (table stakes):**
- ETH solvency invariant harness -- `address(game).balance + steth.balanceOf(game) >= claimablePool` across all game states
- Game FSM transition invariant -- level only increases, gameOver is terminal, rngLocked follows request-fulfill-unlock cycle
- BurnieCoin supply conservation invariant -- totalSupply + vaultAllowance == constant across all mint/burn/transfer/vault operations
- Handler contracts with bounded inputs (`bound()`), ghost variables (ETH in/out tracking), and multi-actor support (`vm.prank` cycling)
- VRF fulfillment handler as separate `targetContract` -- without this, game permanently stalls at RNG-locked state
- 4 independent blind adversarial attack sessions with focused briefs and PoC tests for any Medium+ findings
- Consolidated C4-format findings report from all attack sessions

**Should have (differentiators):**
- Vault share accounting invariant -- share math bugs are a top C4 finding category (Yearn yETH exploit, Dec 2025)
- Ticket queue ordering invariant -- FIFO integrity under interleaved purchase/advance sequences
- Cross-handler sequencing -- multiple handlers as `targetContract` entries for cross-function interaction
- Conditional (phase-aware) invariants -- different assertions for purchase phase vs game-over phase
- Differential testing against v2.0 manual proofs -- dynamically verify ACCT-01 through ACCT-10 claims

**Defer:**
- Lootbox EV invariant -- statistical property, harder to assert deterministically per-call
- Full formal verification (Certora/Halmos) -- different methodology, possible v4.0 milestone
- Gas optimization invariants -- out of scope for security milestone

### Architecture Approach

The architecture deploys the full 22-contract protocol inside Foundry using a shared `DeployProtocol.sol` abstract contract. A new `patchForFoundry.js` script predicts addresses using Foundry's deterministic deployer and nonce sequence, then calls the existing `patchContractAddresses()` function. A Makefile target automates the patch-build-test-restore pipeline. Handlers are separated by domain to ensure each action domain gets adequate fuzzer coverage -- critically, VRF fulfillment lives in its own handler so the fuzzer independently decides when to deliver randomness, naturally creating realistic interleaving of game actions and oracle responses.

**Major components:**
1. **`patchForFoundry.js` + Makefile target** -- address prediction for Foundry deployer, patch-compile-test-restore automation
2. **`DeployProtocol.sol`** -- abstract contract deploying all 22 contracts + 5 mocks in `setUp()`, mirroring `deployFixture.js`
3. **GameHandler** -- purchase/advance/claim wrappers with ETH ghost variables (`ghost_totalDeposited`, `ghost_totalClaimed`)
4. **VRFHandler** -- VRF fulfill + time warping (`warpPastVrfTimeout`, `warpTime`); separate targetContract for independent call scheduling
5. **WhaleHandler** -- whale bundle (2.4 ETH), lazy pass (0.24 ETH), deity pass (24 + T(n) ETH) actions
6. **CoinHandler** -- BURNIE mint/burn/transfer/coinflip operations
7. **5 invariant harnesses** -- EthSolvency, CoinSupply, GameFSM, VaultShares, TicketQueue

### Critical Pitfalls

1. **ContractAddresses compile-time constants block real testing** -- Foundry compiles contracts with `address(0)` constants; all cross-contract calls silently fail. Must solve with patch-compile-deploy pipeline before writing any system-level harness. Add canary invariant `assert(game.owner() != address(0))` to detect broken deployment.

2. **Poor state coverage produces false confidence** -- without VRF-aware handlers and bounded inputs, >90% of fuzzer calls revert silently with `fail_on_revert = false`. Game never advances past level 0; invariants hold vacuously. Monitor revert rates with `show_metrics = true`; target >60% non-reverting calls; add phase-advancing helper functions.

3. **Compiler version mismatch** -- production contracts use 0.8.34; foundry.toml and existing fuzz tests use 0.8.26. Must point `foundry.toml` at Hardhat-cached solc binary and fix test pragmas to caret syntax.

4. **Anchoring bias in adversarial sessions** -- same auditor conducted v1.0 and v2.0. Mitigate with contradiction-framed briefs ("prove X CAN be violated"), varied information per session, distinct attacker personas, strict time-boxing, and severity threshold enforcement (no QA/informational findings from adversarial sessions).

5. **Delegatecall modules must never be targeted directly** -- calling a module at its standalone address gives it empty storage, producing meaningless results. All handler functions must call through DegenerusGame's external API. Use `targetContract(handler)` only, never `targetContract(module)`.

## Implications for Roadmap

Based on research, suggested phase structure (5 phases):

### Phase 1: Foundry Infrastructure and Compiler Alignment

**Rationale:** Everything depends on being able to compile and deploy the full protocol in Foundry. The ContractAddresses blocker is the single most dangerous dependency -- until addresses are correct, nothing else works. This phase must be validated before any invariant harness can be written.
**Delivers:** `patchForFoundry.js`, updated `foundry.toml` (solc path, `auto_detect_solc = false`, `[invariant]` section), pragma fixes on 3 existing fuzz tests, `DeployProtocol.sol` deploying all 22 contracts + 5 mocks, Makefile target for patch-build-test-restore, canary test asserting all addresses match ContractAddresses constants.
**Addresses:** Setup infrastructure (FEATURES: handler contracts prerequisite), compiler alignment (STACK: solc 0.8.34 blocker)
**Avoids:** Pitfall 1 (ContractAddresses blocking), Pitfall 3 (compiler mismatch), Pitfall 7 (remapping conflicts), Pitfall 13 (artifact collision)

### Phase 2: Core Handlers and ETH Solvency Invariant

**Rationale:** ETH solvency is the single most important invariant for any ETH-holding protocol. Building it first validates the entire pipeline end-to-end (patch -> compile -> deploy -> fuzz -> assert). The GameHandler, VRFHandler, WhaleHandler, and ActorManager are shared dependencies for all subsequent invariants.
**Delivers:** ActorManager, GameHandler (purchase/advance/claim with ghost ETH tracking), VRFHandler (fulfill/time-warp), WhaleHandler (bundle/lazy/deity), `EthSolvency.inv.t.sol` with solvency and ghost accounting assertions.
**Addresses:** FEATURES: ETH solvency invariant, handler contracts, ghost variables, multi-actor support, VRF simulation, bounded input generation
**Avoids:** Pitfall 2 (poor state coverage), Pitfall 4 (VRF stuck), Pitfall 6 (delegatecall targeting), Pitfall 11 (fail_on_revert hiding handler bugs)

### Phase 3: Remaining Invariant Harnesses

**Rationale:** With infrastructure and core handlers proven, the remaining four invariants reuse existing handlers and follow the same patterns. CoinHandler is the only new handler needed. These invariants cover the remaining critical protocol properties.
**Delivers:** CoinHandler (BURNIE operations), `CoinSupply.inv.t.sol`, `GameFSM.inv.t.sol`, `VaultShares.inv.t.sol`, `TicketQueue.inv.t.sol`.
**Addresses:** FEATURES: BurnieCoin supply conservation, game FSM transitions, vault share accounting, ticket queue ordering, conditional invariants
**Avoids:** Pitfall 8 (tautological invariants), Pitfall 12 (insufficient depth), Pitfall 14 (only normal actors)

### Phase 4: Attack Briefs and Blind Adversarial Sessions

**Rationale:** Adversarial sessions should run after invariant infrastructure is complete so any bugs found can be confirmed/denied by the invariant suite. All 4 briefs must be written before any session begins to enforce independence and prevent anchoring.
**Delivers:** 4 attack briefs (ETH extraction, advanceGame bricking, claim overflow, delegatecall storage corruption), 4 independent adversarial sessions with distinct attacker personas, PoC tests for any Medium+ findings.
**Addresses:** FEATURES: all 4 adversarial sessions, PoC tests, C4-format findings
**Avoids:** Pitfall 5 (anchoring bias), Pitfall 9 (scope creep), Pitfall 10 (confirmation bias), Pitfall 16 (information overlap)

### Phase 5: Tuning, Hardening, and Consolidated Report

**Rationale:** After all harnesses and sessions complete, tune invariant parameters based on coverage analysis, increase runs/depth for CI, and consolidate all findings into a single C4-format report. This phase cannot start until Phases 3 and 4 are both complete.
**Delivers:** Tuned invariant configs (bound ranges, `targetSelector()` weighting), increased CI parameters (512-1024 runs, 128 depth), consolidated C4-format findings report, honest confidence reporting with metrics.
**Addresses:** FEATURES: consolidated report, cross-handler sequencing, differential testing against v2.0
**Avoids:** Pitfall 15 (treating passing invariants as proof of correctness)

### Phase Ordering Rationale

- **Phase 1 must be first** because every other phase depends on Foundry being able to compile and deploy the protocol. The ContractAddresses blocker is a hard dependency.
- **Phase 2 must follow Phase 1** because it validates the entire pipeline end-to-end and produces the highest-value invariant. If this phase works, the pattern is proven.
- **Phase 3 follows Phase 2** because it reuses Phase 2's handlers and infrastructure. Building 4 invariants in one phase is efficient once patterns are established.
- **Phase 4 can partially overlap with Phase 3** -- attack briefs can be written while Phase 3 invariants are being built, and adversarial sessions can begin once briefs are ready, independent of invariant completion.
- **Phase 5 must be last** because coverage metrics from Phase 3 and adversarial findings from Phase 4 are both needed to make informed tuning decisions and write the consolidated report.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** The `patchForFoundry.js` script and `DeployProtocol.sol` are novel components translating the Hardhat deploy fixture into Foundry. Address prediction for Foundry's deployer nonce sequence needs careful validation. Research-phase recommended.
- **Phase 4:** Attack brief design requires deliberate bias mitigation. Should research specific entry points and defense claims from v2.0 to frame contradiction-based briefs. Low-effort but high-impact research.

Phases with standard patterns (skip research-phase):
- **Phase 2:** Handler patterns are canonical (horsefacts WETH example, Foundry official docs, RareSkills guide). Standard implementation.
- **Phase 3:** Same handler patterns as Phase 2. Standard implementation.
- **Phase 5:** Tuning is empirical, driven by `show_metrics` output. No research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Foundry already installed and verified; solc 0.8.34 workaround confirmed locally; no new tools needed; forge-std 1.15.0 is current |
| Features | HIGH | Invariant categories well-scoped from official Foundry docs and C4 methodology; existing fuzz tests validate the mock/handler pattern; adversarial session structure follows established C4 practice |
| Architecture | HIGH | Patch-compile-deploy strategy uses existing infrastructure; handler patterns are canonical; component boundaries are clear; `vm.etch` alternative was evaluated and rejected for valid reasons (constructor state loss) |
| Pitfalls | HIGH | 16 pitfalls identified from project-specific codebase analysis corroborated with community experience and official docs; all have concrete mitigations; critical pitfalls (1-6) have detection steps |

**Overall confidence:** HIGH

### Gaps to Address

- **Foundry deployer nonce prediction accuracy:** The `patchForFoundry.js` script must correctly predict the deployer address and starting nonce in Foundry's test EVM. Foundry uses `address(uint160(uint256(keccak256("foundry default caller"))))` as the default `msg.sender` in tests, but `setUp()` may alter nonce counting. Must validate empirically in Phase 1.

- **Invariant depth sufficiency:** 256 runs x 64 depth may not reach deep game states (level 5+, jackpot hits, game-over). Start at these defaults but be prepared to increase to 512 runs x 128 depth based on `show_metrics` output. Consider batching handler functions (e.g., `advanceThroughLevel()`) to compress effective depth needed.

- **VRF fulfillment interleaving quality:** The separate VRFHandler approach is theoretically sound but untested for this specific protocol. If the fuzzer rarely calls `fulfillVrf()` relative to `purchase()`, game progression will stall. May need `targetSelector()` weighting to ensure adequate VRF fulfillment frequency. Detection: check if `game.currentLevel()` ever exceeds 0 across all runs.

- **Adversarial session independence:** With a single AI auditor conducting all sessions, true information isolation is impossible. The mitigation (varied briefs, contradiction framing, strict scoping, distinct attacker personas) reduces but does not eliminate anchoring bias. This limitation must be acknowledged honestly in the final report.

## Sources

### Primary (HIGH confidence)
- [Foundry Invariant Testing Documentation](https://getfoundry.sh/forge/invariant-testing) -- handler patterns, targetContract, ghost variables, configuration
- [Foundry Config Reference: Testing](https://getfoundry.sh/reference/config/testing) -- all [invariant] and [fuzz] config options
- [Foundry Config Reference: Solidity Compiler](https://www.getfoundry.sh/config/reference/solidity-compiler) -- solc path, auto_detect_solc
- [horsefacts WETH Invariant Testing](https://github.com/horsefacts/weth-invariant-testing) -- canonical handler pattern, ETH solvency ghost variables, bounded fuzzing
- [forge-std v1.15.0 releases](https://github.com/foundry-rs/forge-std/releases) -- latest release, installed at lib/forge-std
- [Solidity 0.8.34 Release](https://www.soliditylang.org/blog/2026/02/18/solidity-0.8.34-release-announcement/) -- confirms compiler version and release date
- [Hardhat + Foundry Integration](https://v2.hardhat.org/hardhat-runner/docs/advanced/hardhat-and-foundry) -- coexistence patterns
- Local verification: `forge build --use <solc-0.8.34-path>` confirmed working on this project
- Direct codebase inspection: foundry.toml, ContractAddresses.sol, patchContractAddresses.js, predictAddresses.js, deployFixture.js, MockVRFCoordinator.sol, BurnieCoinInvariants.t.sol, PriceLookupInvariants.t.sol, ShareMathInvariants.t.sol

### Secondary (MEDIUM confidence)
- [RareSkills Invariant Testing Guide](https://rareskills.io/post/invariant-testing-solidity) -- handler examples, actor management, DeFi invariant categories
- [Cyfrin Invariant Testing Guide](https://medium.com/cyfrin/invariant-testing-enter-the-matrix-c71363dea37e) -- multi-handler campaigns, handler design principles
- [ThreeSigma Foundry Cheatcodes](https://threesigma.xyz/blog/foundry/foundry-cheatcodes-invariant-testing) -- revert handling, call distribution issues
- [Patrick Collins: Fuzz/Invariant Tests as Bare Minimum](https://patrickalphac.medium.com/fuzz-invariant-tests-the-new-bare-minimum-for-smart-contract-security-87ebe150e88c) -- false confidence patterns from shallow coverage
- [Sigma Prime Forge Testing Leveling](https://blog.sigmaprime.io/forge-testing-leveling.html) -- unit-to-invariant progression methodology
- [Audited, Tested, Still Broken (2025)](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- Yearn yETH share math exploit as motivation for vault invariants
- [Cyfrin VRF Mock Guide](https://updraft.cyfrin.io/courses/foundry/smart-contract-lottery/deploy-mock-chainlink-vrf) -- deterministic VRF mock patterns

---
*Research completed: 2026-03-05*
*Supersedes: SUMMARY.md dated 2026-03-04 (v2.0 audit)*
*Ready for roadmap: yes*
