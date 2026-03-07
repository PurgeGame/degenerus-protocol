# Degenerus Protocol — Contract Hardening & Parity Verification

## What This Is

22-contract on-chain gaming protocol (Degenerus Protocol) with 10 delegatecall game modules. Currently undergoing comprehensive testing and parity verification after a series of contract changes — admin governance, advance module gating, affiliate economics, and game-over mechanics.

## Current Milestone: v6.0 Contract Hardening & Parity Verification

**Goal:** Comprehensive testing of all recent contract changes and systematic verification that every constant, NatSpec comment, and game theory paper number matches actual contract behavior.

**Target features:**
- Full test coverage for all post-audit contract changes (admin, advance, affiliate, game-over, whale, deity, etc.)
- NatSpec comment accuracy audit — every comment checked against actual code logic
- Game theory paper (website/theory/index.html) → contract constant parity verification
- Sanity-check test suite exercising every magic number, BPS split, price tier, and threshold

## Previous: Off-Chain Simulation Engine (v1.0 IN PROGRESS)

Simulation engine milestone paused — phases 36, 39, 41 complete; phases 37, 38, 40, 42 pending.

## Previous: Security Audit (v1.0-v5.0 COMPLETE)

Five milestone audits delivered: 0 Critical, 0 High, 0 Medium, 6 Low (acknowledged), 46 QA/Info. Protocol assessed LOW RISK. 121 plans across 35 phases. See `.planning/MILESTONES.md` for details.

## Milestone: v4.0 Pre-C4A Adversarial Stress Test (COMPLETE)

**Result:** 0 Critical, 0 High, 0 Medium. 5 Low, 30 QA/Info. 10/10 agents unanimous. Protocol assessed LOW RISK.

## Milestone: v3.0 Adversarial Hardening (COMPLETE)

**Result:** 0 Critical, 0 High, 0 Medium. 48 invariant tests, 53 adversarial vectors, 10 symbolic properties.

## Milestone: v2.0 Adversarial Audit (COMPLETE)

**Result:** 0 Critical, 0 High, 0 Medium, 1 Low, 8 QA. 48 requirements satisfied.

## Core Value

Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor — whale, Sybil group, or block proposer — can extract value beyond what the game mechanics intend.

## Requirements

### Validated

- ✓ 22-contract protocol deployed via nonce-predicted addresses — existing
- ✓ Delegatecall module pattern with shared storage layout — existing
- ✓ Chainlink VRF V2.5 integration for randomness — existing
- ✓ RNG lock state machine (request → fulfill → unlock) — existing
- ✓ Ticket purchase with price escalation curves — existing
- ✓ Prize pool split (90% current / 10% future) — existing
- ✓ Pull-pattern ETH/stETH withdrawals — existing
- ✓ Whale bundles, lazy passes, deity passes with pricing formulas — existing
- ✓ Lootbox EV multiplier based on activity score — existing
- ✓ Degenerette betting and resolution — existing
- ✓ BurnieCoin ERC20 with coinflip mechanics — existing
- ✓ Affiliate referral tracking and bonus points — existing
- ✓ Quest streak system with activity score component — existing
- ✓ 884 tests passing (unit, integration, access control, edge cases) — existing
- ✓ Storage layout verified: zero slot collisions across all 10 delegatecall modules — v1.0
- ✓ VRF lifecycle confirmed safe: rngLockedFlag, callback gas, requestId matching, entropy derivation — v1.0
- ✓ FSM transition graph: all legal transitions enumerated, illegal transitions proved unreachable — v1.0
- ✓ Stuck-state recovery: all 5 recovery mechanisms confirmed reachable and premature-trigger resistant — v1.0
- ✓ ETH module flow: MintModule, JackpotModule, EndgameModule, LootboxModule, GameOverModule audited — v1.0
- ✓ Supporting modules: WhaleModule, BoonModule, DecimatorModule, DegeneretteModule, MintStreakUtils audited — v1.0
- ✓ Input validation confirmed across all external-facing parameters — v1.0
- ✓ DoS resistance confirmed: all loops bounded, bucket cursor griefing-resistant, trait burn bounded — v1.0
- ✓ Economic attack surface modeled: Sybil, MEV, block proposer, whale, affiliate all bounded — v1.0
- ✓ Access control matrix: all 22 contracts privilege-mapped, delegation safety proofs complete — v1.0
- ✓ Delegatecall return values: all 30 call sites confirmed using uniform checked pattern — v1.0
- ✓ Constructor ordering: all 22 constructors confirmed safe relative to deploy sequence — v1.0
- ✓ Token math: PriceLookupLib, deity pass T(n), lazy pass, lootbox EV, BitPackingLib, coinflip range all verified — v1.0
- ✓ stETH rebasing: no cached balance found, handling confirmed correct — v1.0
- ✓ ETH solvency invariant verified across all game states (ACCT-01 through ACCT-10) — v2.0
- ✓ advanceGame() worst-case gas bounded at 39.3% of 16M limit; Sybil DoS infeasible — v2.0
- ✓ Admin power map complete: wireVrf constructor-only, no post-deployment RNG manipulation — v2.0
- ✓ Assembly SSTORE slot calculations verified correct for JackpotModule and MintModule — v2.0
- ✓ Token security: no mint bypass, no EV > 1.0, VRF-only entropy, 30-day guard complete — v2.0
- ✓ Vault and Stonk: floor-division safe, no donation attack, no partial-burn extraction — v2.0
- ✓ Timestamp ±900s tolerance: no double-jackpot, no streak griefing — v2.0
- ✓ Cross-function reentrancy matrix: 8 ETH-transfer sites all CEI-safe — v2.0
- ✓ 40 JackpotModule unchecked blocks verified safe; 3 fix commits tested for bypass — v2.0
- ✓ Code4rena-format findings report delivered (0 Critical, 0 High, 0 Medium, 1 Low, 8 QA) — v2.0
- ✓ Foundry invariant fuzzing harnesses — ETH solvency, BurnieCoin supply, ticket queue, vault shares, game FSM (48 tests) — v3.0
- ✓ 4 blind adversarial attack sessions — 53 vectors explored, 0 Medium+ — v3.0
- ✓ 10 Halmos symbolic properties verified — v3.0
- ✓ 10 independent blind threat model analyses — all unanimous zero Medium+ — v4.0
- ✓ Game theory adversarial analysis — resilience thesis verified, all 4 propositions confirmed — v4.0
- ✓ 97 PoC defense validation tests — all passing — v4.0
- ✓ C4A-ready synthesis report — zero contradictions, LOW RISK assessment — v4.0
- ✓ Novel zero-day attack surface analysis (composition, precision, temporal, EVM, economic) — v5.0
- ✓ Foundry deep fuzzing with 10K+ fuzz runs, Slither full triage (630 findings, 0 TP), Halmos symbolic verification (24 properties) — v5.0
- ✓ Cross-contract composition: 31 delegatecall sites, 45 module pairs, zero composition bugs — v5.0
- ✓ Precision audit: 222 division ops classified, zero-rounding impossible, dust extraction infeasible — v5.0

### Active

(Defined in REQUIREMENTS.md — v6.0 hardening milestone)

### Out of Scope

- Gas optimization — separate concern
- Simulation engine — paused, separate milestone
- Testnet-specific contracts — mainnet deployment is the target
- Mock contracts — test infrastructure only
- Deployment scripts — operational, not testing surface

## Context

### Current State (v6.0 Contract Hardening)

- Contracts have been significantly modified since the v1.0-v5.0 audits
- Recent changes: CREATOR gate removed, DGVE majority governance, tiered mint gate, affiliate commission caps, lootbox activity taper, auto VRF shutdown, compressed jackpots, game-over redesign
- 951 tests passing but many recent changes lack dedicated test coverage
- Known miss: level 90 price change was in PriceLookupLib but not caught by any test across 30+ rounds
- Game theory paper (website/theory/index.html) is the canonical source of truth for protocol numbers

### Technical Stack

- Solidity 0.8.34 with viaIR, optimizer runs=200
- All contracts under 24KB (DegenerusGame largest at 19KB)
- Storage layout shared via DegenerusGameStorage
- ContractAddresses compile-time constants, patched at deploy
- Chainlink VRF V2.5, Lido stETH, LINK token as external dependencies
- Test stack: Hardhat/Mocha (951 tests), Foundry invariant fuzzing, Halmos symbolic verification

## Constraints

- **Threat model**: 10,000 ETH whale + coordinated Sybil group + block proposer/validator + compromised admin
- **Scope**: All 22 mainnet contracts, all 10 delegatecall modules
- **Output**: Prioritized findings report with severity ratings and remediation guidance
- **Compiler**: Solidity 0.8.x with built-in overflow protection (no SafeMath needed)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full protocol scope (not targeted) | Cross-contract interactions are where bugs hide | ✓ Good — surfaced deityBoonSlots staticcall bug |
| Validator-level threat model | Strongest realistic attacker for on-chain game | ✓ Good — block proposer analysis thorough |
| Parallel module execution (3a/3b/3c) | Phase 2 independence enables parallelism | ✓ Good — accelerated audit velocity |
| Accepted Phase 4 gap for v1.0 | ETH accounting incomplete but other surfaces covered | ✓ Resolved — v2.0 Phase 8 closed all ACCT gaps |
| False positive classification methodology | Two-pass Slither + manual triage for all HIGH/MEDIUM | ✓ Good — prevented false-finding noise |
| Skip final synthesis report in v1.0 | Known gap accepted as tech debt | ✓ Resolved — v2.0 Phase 13 delivered full report |
| v2.0: 4 MEDIUM findings withdrawn | Source verification confirmed admin access control patterns properly gate all investigated paths | ✓ Good — prevented false positives in C4 report |
| v2.0: Parallel Phases 8/9 | ETH accounting and gas analysis are independent streams | ✓ Good — reduced critical path |
| v2.0: VAULT+TIME folded into Phase 11 | Too small for standalone phases, natural fit with TOKEN analysis | ✓ Good — efficient scoping |

| v3.0: 0 PoC tests needed | 0 Medium+ findings across all adversarial sessions | Correct — no false confidence from empty PoCs |
| v3.0: Honest limitations section | 7 explicit limitations including same-auditor bias | Builds trust with C4 judges |
| v4.0: 10 parallel blind agents | Maximize coverage diversity, avoid anchoring on prior findings | ✓ Good — zero contradictions, unanimous consensus |
| v4.0: Contradiction-framed attack briefs | Each agent gets adversarial prompt to find exploits, not confirm safety | ✓ Good — genuine blind analysis |
| v4.0: Game theory adversarial analysis | Attack the resilience thesis paper, not just the code | ✓ Good — all 4 propositions verified, yield split more favorable than claimed |
| v4.0: No code fixes during analysis | Blind methodology requires unchanged codebase | ✓ Correct — findings preserved without contamination |
| v5.0: Three-tool cross-reference (Foundry + Slither + Halmos) | Multi-tool convergence increases confidence | ✓ Good — 4 multi-flag functions investigated to resolution |
| v5.0: Per-finding Slither triage (not bulk dismissal) | Avoid missing true positives in noise | ✓ Good — 630 findings triaged, 0 TP, 22 led to investigation |
| v5.0: Halmos swap procedure for foundry.toml | Halmos incompatible with fuzz/invariant sections | ✓ Good — documented workaround, 24 properties executed |
| v5.0: ShareMath timeout accepted honestly | 256-bit bvudiv intractable for SMT solvers | ✓ Correct — reported as coverage gap, not as "verified" |
| v5.0: Same-auditor bias as primary limitation | Honest confidence requires naming weaknesses | ✓ Good — builds trust with C4A judges |

---
*Last updated: 2026-03-06 after v6.0 contract hardening milestone start*
