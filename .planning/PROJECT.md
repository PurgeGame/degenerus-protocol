# Degenerus Protocol — Audit Repository

## What This Is

Smart contract audit repository for the Degenerus Protocol — an on-chain ETH game with repeating levels, prize pools, BURNIE token economy, DGNRS/sDGNRS governance tokens, and a comprehensive deity pass system. Contains all protocol contracts, deploy scripts, tests (Hardhat + Foundry fuzz), and audit documentation.

## Core Value

Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Requirements

### Validated

- ✓ v1.0 RNG security audit — VRF integration, manipulation windows, ticket selection
- ✓ v1.1 Economic flow audit — 13 reference docs covering all subsystems
- ✓ v1.2 RNG storage/function/data-flow deep dive
- ✓ v1.2 Delta attack reverification after code changes
- ✓ State-changing function audit — all external/public functions across all contracts
- ✓ Parameter reference — every named constant consolidated
- ✓ sDGNRS/DGNRS split implementation — soulbound + liquid wrapper architecture
- ✓ Audit doc sync — all 10 docs updated for sDGNRS/DGNRS split
- ✓ v2.1 Governance security audit — 26 verdicts covering all attack vectors — v2.1
- ✓ v2.1 M-02 closure — emergencyRecover eliminated, governance replaces single-admin authority — v2.1
- ✓ v2.1 War-game scenarios — 6 adversarial scenarios assessed with severity ratings — v2.1
- ✓ v2.1 Audit doc sync — all docs updated for governance, zero stale references — v2.1
- ✓ v2.1 Post-audit hardening — CEI fix, removed death clock pause + activeProposalCount — v2.1

### Validated

- ✓ v3.0 Full contract audit + payout specification — 5 phases, 58 requirements — v3.0
- ✓ v3.1 Comment correctness + intent verification — 84 findings (80 CMT + 4 DRIFT) across all 29 contracts — v3.1
- ✓ v3.2 RNG delta + comment re-scan — 30 deduplicated findings (6 LOW, 24 INFO), governance fresh eyes (14 surfaces, 0 new), v3.1 fix verification (76/3/4/1) — v3.2
- ✓ v3.3 Gambling burn delta audit — 3 HIGH + 1 MEDIUM confirmed and fixed (CP-08 double-spend, CP-06 stuck claims, Seam-1 fund trap, CP-07 split-claim) — v3.3
- ✓ v3.3 Redemption correctness — full lifecycle trace, segregation solvency proven, CEI verified, period state machine proven — v3.3
- ✓ v3.3 Invariant test suite — 7 Foundry invariants passing (solvency, double-claim, supply, cap, roll bounds, aggregate tracking) — v3.3
- ✓ v3.3 Adversarial sweep — 29/29 contracts swept, 0 new HIGH/MEDIUM, 13 composability sequences SAFE — v3.3
- ✓ v3.3 Economic analysis — ETH EV=100% (fair), BURNIE EV=0.98425x, bank-run solvency proven, 4 rational actor strategies unprofitable — v3.3
- ✓ v3.3 Gas optimization — 7 variables ALIVE, 3 packing opportunities documented, gas baseline captured — v3.3
- ✓ v3.3 Documentation sync — NatSpec verified, error renames, bit allocation map, 12 audit docs updated, PAY-16 payout path — v3.3
- ✓ v3.5 Gas optimization — 204 variables analyzed (201 ALIVE, 3 DEAD), 5 dead code items, 8 packing opportunities, 13 findings (3 LOW, 10 INFO) — v3.5 Phase 55
- ✓ v3.5 Comment correctness — 46 files (~26,300 lines) swept, 26 findings (7 LOW, 19 INFO), 34 prior findings verified FIXED, 3 regressions documented — v3.5 Phase 54
- ✓ v3.5 Gas ceiling analysis — 18 paths profiled (12 advanceGame + 6 purchase), 15 SAFE, 1 TIGHT, 2 AT_RISK, 4 INFO findings — v3.5 Phase 57
- ✓ v3.5 Final Polish — 43 findings consolidated (10 LOW, 33 INFO) from comment correctness (26), gas optimization (13), and gas ceiling analysis (4) — v3.5 Phase 58

### Validated

- ✓ v3.6 VRF Stall Resilience — gap day RNG backfill, orphaned lootbox recovery, midDayTicketRngPending clearing, stall→swap→resume test coverage, delta audit (8 surfaces SAFE), 2 INFO findings — v3.6 Phases 59-62

### Validated

- ✓ v3.7 VRF Request/Fulfillment Core — rawFulfillRandomWords revert-safety proven, 300k gas budget 6-10x sufficient, vrfRequestId lifecycle verified, rngLockedFlag mutual exclusion airtight, 12h timeout retry correct, Slot 0 assembly SAFE, 22 Foundry fuzz tests, 0 HIGH/MEDIUM/LOW, 2 INFO — v3.7 Phase 63
- ✓ v3.7 Lootbox RNG Lifecycle — all 5 LBOX requirements VERIFIED, index-to-word 1:1 mapping proven across daily/mid-day/retry/backfill/gameover paths, zero-state guards verified (4/5 guarded, 1 INFO-level 2^-256), per-player entropy uniqueness proven, full purchase-to-open lifecycle traced, 21 Foundry fuzz tests, 0 HIGH/MEDIUM/LOW, 2 INFO (V37-003, V37-004) — v3.7 Phase 64
- ✓ v3.7 VRF Stall Edge Cases — all 7 STALL requirements VERIFIED, gap backfill entropy unique via keccak256 preimage, gas ceiling 18.9M (< 30M block limit), coordinator swap resets all 8 VRF state vars, zero-seed unreachable after swap, gameover fallback prevrandao 1-bit bias INFO, dailyIdx timing consistent, 17 Foundry fuzz tests, 0 HIGH/MEDIUM/LOW, 3 INFO (V37-005, V37-006, V37-007) — v3.7 Phase 65
- ✓ v3.7 VRF Path Test Coverage — 7 invariant assertions (256 runs/depth 128), 6 parametric fuzz tests (1000 runs each), 4 Halmos symbolic proofs (0 counterexamples), redemption roll [25,175] bounds verified for all 2^256 inputs — v3.7 Phase 66
- ✓ v3.7 Verification + Doc Sync — 66-VERIFICATION.md (10/10 must-haves), V37-001 RESOLVED, Phase 66 cross-references in all findings docs, KNOWN-ISSUES.md updated — v3.7 Phase 67

### Validated

- ✓ v3.8 VRF commitment window audit — 55 variables, 87 permissionless paths, 51/51 SAFE general proof, coinflip + daily RNG path-specific proofs, 1 MEDIUM vulnerability (TQ-01 _tqWriteKey bug) with fix recommendation — v3.8 Phases 68-72
- ✓ v3.8 Boon storage packing — 29 per-player boon mappings packed into 2-slot struct, all 12 boon functions rewritten, lootbox boost simplified to single tier — v3.8 Phase 73

### Validated

- ✓ v3.9 Far-future ticket fix — third key space (bit 22), central routing for all 6 callers, dual-queue drain, combined pool jackpot selection, rngLocked guard, 35 Foundry tests, RNG commitment window proof — v3.9 Phases 74-80

### Validated

- ✓ v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit — 10 phases (81-91), 51 INFO findings (0 HIGH/MEDIUM/LOW), DEC-01/DGN-01 withdrawn as false positives, 134 cumulative total. Ticket creation (16 entry points), processing (RNG/cursor), consumption (9 jackpot types), prize pool flow (storage layout), daily ETH/coin/ticket jackpots, other jackpots (earlybird/BAF/decimator/degenerette/finalday), RNG re-verification (55 vars, 27 slot shifts), consolidated findings, cross-phase consistency verified — v4.0 Phases 81-91
- ✓ v4.1 Ticket Lifecycle Integration Tests — 3 phases (92-94), 24 Foundry integration tests deploying full 23-contract protocol, all 6 ticket sources verified (direct purchase x3, lootbox near/far, whale bundle), boundary routing (L+5 write vs L+6 FF), FF drain timing proven, zero-stranding sweeps across all key spaces, RNG commitment window formal proof (9/9 paths SAFE), rngLocked guard verified, 1 bug fix (requestLootboxRng mid-day gating) — v4.1 Phases 92-94

### Validated

- ✓ v4.2 Daily Jackpot Chunk Removal + Gas Optimization — 4 phases (95-98), chunk removal delta verified (behavioral equivalence + zero stale refs), gas ceiling profiled (all 3 stages SAFE with 34.9-42.3% headroom), 24 SLOADs audited + 7 loops analyzed, comment cleanup (8 issues fixed, function rename), documentation gap closure (13/13 requirements verified), 0 new findings — v4.2 Phases 95-98
- ✓ v4.3 prizePoolsPacked Batching Optimization — closed early after Phase 99 callsite audit revealed H14 gas savings was 25x overestimate (~63.8K actual vs ~1.6M estimated). Optimization abandoned as not cost-effective. — v4.3 Phase 99
- ✓ v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan — 3 phases (100-102), protocol-wide cache-overwrite scan (1 VULNERABLE / 11 SAFE across 29 contracts), delta reconciliation fix applied to `runRewardJackpots`, Foundry fix-proof test, zero regressions — v4.4 Phases 100-102

## Current Milestone: v5.0 Ultimate Adversarial Audit

**Goal:** Exhaustive three-agent adversarial audit of every state-changing function in the protocol, with mandatory call-tree expansion, storage-write mapping, and coverage enforcement — designed to catch BAF-class bugs that survived 24 prior milestones.

**Target features:**
- 16-unit full-protocol sweep with Mad Genius (attacker) / Skeptic (validator) / Taskmaster (coverage enforcer) agents
- Mandatory recursive call-tree expansion and storage-write map for every function
- Explicit stale-cache-vs-storage check (the BAF pattern) on every function
- 100% coverage enforcement with no shortcuts
- All agents on Opus at maximum effort (GSD quality profile)
- Focus: state coherence, RNG manipulation, cross-contract desync, rare conditional paths, access control, ordering attacks, silent failures, economic/MEV attacks, griefing
- Excluded (already covered in v3.0-v4.4): pure arithmetic, classic reentrancy

**Design doc:** `.planning/ULTIMATE-AUDIT-DESIGN.md`

## Completed Milestone: v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan

**Status:** Complete (2026-03-25)

**Result:** 3 phases (100-102). Protocol-wide scan for cache-then-overwrite pattern found 1 VULNERABLE instance (`runRewardJackpots` in EndgameModule) and 11 SAFE across 29 contracts. Delta reconciliation fix: `rebuyDelta = _getFuturePrizePool() - baseFuturePool` added before write-back, preserving auto-rebuy contributions. Foundry integration test (`BafRebuyReconciliation.t.sol`) proves the fix. Foundry 355/14, Hardhat 1208/34 — zero regressions.

## Completed Milestone: v4.3 prizePoolsPacked Batching Optimization

**Status:** Closed early (2026-03-25)

**Result:** Phase 99 callsite audit completed. Key finding: H14's ~1.6M gas savings estimate used cold SSTORE pricing (5,000/write) but subsequent writes to the same dirty slot cost only 100 gas (EIP-2200). Actual savings: ~63,800 gas (0.46% of 14M ceiling). Phases 100-102 abandoned — architectural complexity not justified for ~$0.13/execution savings at 1 gwei.

## Completed Milestone: v4.2 Daily Jackpot Chunk Removal + Gas Optimization

**Status:** Complete (2026-03-25)

**Result:** 4 phases (95-98). Chunk removal delta verified (behavioral equivalence proof, zero stale refs across all Solidity files). Gas ceiling profiled — all 3 daily jackpot stages reclassified from AT_RISK/TIGHT to SAFE with 34.9-42.3% headroom. 24 SLOADs audited, 7 loops analyzed, 1 actionable optimization identified (deferred as architectural). Comment cleanup: 8 issues fixed, `_processDailyEthChunk` renamed to `_processDailyEth`, full NatSpec added. Gap closure: all 13 requirements verified and tracked, EVM SLOT 1 banner corrected.

## Completed Milestone: v4.1 Ticket Lifecycle Integration Tests

**Status:** Complete (2026-03-24)

**Result:** 24 Foundry integration tests across 3 phases (92-94). All 22 requirements satisfied. Full-protocol deployment via DeployProtocol exercising all 6 ticket sources, edge cases, zero-stranding sweeps, and RNG commitment window proofs. 1 contract bug fix discovered (requestLootboxRng blocked during mid-day ticket processing).

## Completed Milestone: v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit

**Status:** Complete (2026-03-23)

**Result:** 51 INFO findings across 8 audit phases (81-88), consolidated in v4.0-findings-consolidated.md. No HIGH, MEDIUM, or LOW findings. DEC-01 and DGN-01 withdrawn as false positives. Grand total across all milestones: 134 (51 v4.0 + 83 prior).

### Deferred (v3.3+)

- [ ] Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- [ ] Formal verification of vote counting arithmetic via Halmos
- [ ] Monte Carlo simulation of governance outcomes under various voter distributions
- [ ] Storage packing implementation — 3 opportunities documented in v3.3 gas analysis (up to 66,300 gas savings)

### Out of Scope

- Frontend code — not in audit scope
- Off-chain infrastructure — VRF coordinator is external
- Gas optimization beyond correctness — C4A QA findings are low-cost
- Governance UI/frontend — not in audit scope
- Off-chain vote aggregation — on-chain only governance
- Governance upgrade mechanisms — contract is immutable per spec

## Context

- Solidity 0.8.34, Hardhat + Foundry dual test stack
- 23 protocol contracts deployed in deterministic order via CREATE nonce prediction
- All contracts use immutable `ContractAddresses` library (addresses baked at compile time)
- VRF via Chainlink VRF v2 for randomness
- DegenerusStonk split into StakedDegenerusStonk (soulbound, holds reserves) + DegenerusStonk (transferable ERC20 wrapper)
- VRF governance: emergencyRecover replaced with sDGNRS-holder propose/vote/execute (M-02 mitigation). Touches DegenerusAdmin, AdvanceModule, GameStorage, Game, DegenerusStonk.
- Post-v2.1: death clock pause removed (unnecessary complexity), activeProposalCount removed (no on-chain consumer), _executeSwap CEI fixed
- New: Gambling burn / redemption system on sDGNRS — during-game burns enter a pending queue resolved by RNG roll (25-175) during advanceGame. Post-gameOver burns remain deterministic. Touches StakedDegenerusStonk, DegenerusStonk, BurnieCoinflip, AdvanceModule, and their interfaces.

## Constraints

- **Audit target:** Code4rena competitive audit — findings cost real money
- **Compiler:** Solidity 0.8.34 (overflow protection built-in)
- **EVM target:** Paris (no PUSH0)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Split DGNRS into sDGNRS + DGNRS wrapper | Enable secondary market for creator allocation while keeping game rewards soulbound | ✓ Good |
| Pool BPS rebalance (Whale 10%, Affiliate 35%, Lootbox 20%, Reward 5%, Earlybird 10%) | Better distribution alignment with game mechanics | ✓ Audited v2.0 |
| Coinflip bounty DGNRS gating (min 50k bet, 20k pool) | Prevent dust-amount bounty claims draining reward pool | ✓ Audited v2.0 |
| burnRemainingPools replacing burnForGame | Cleaner game-over cleanup, removes per-address burn authority | ✓ Audited v2.0 |
| Replace emergencyRecover with sDGNRS governance | M-02 mitigation: compromised admin key can no longer unilaterally control RNG | ✓ Audited v2.1, M-02 downgraded to Low |
| VRF retry timeout 18h → 12h | Faster recovery from stale VRF requests | ✓ Audited v2.1 |
| unwrapTo blocked during VRF stall | Prevents creator vote-stacking via DGNRS→sDGNRS conversion during governance | ✓ Audited v2.1 |
| Remove death clock pause for governance | Chainlink death + game death + 256 proposals is unrealistic; reduces complexity | ✓ Post-v2.1 |
| Remove activeProposalCount tracking | No on-chain consumer after death clock pause removal; eliminates uint8 overflow surface | ✓ Post-v2.1 |
| Move _voidAllActive before external calls | CEI compliance in _executeSwap; prevents theoretical sibling-proposal reentrancy | ✓ Post-v2.1 |
| Flag-only comment audit (no auto-fix) | Findings list is the deliverable — protocol team decides which to fix before C4A | ✓ Good — 84 findings produced, 5 cross-cutting patterns identified |
| CP-08 fix: subtract pending reservations in _deterministicBurnFrom | Post-gameOver burns must not consume ETH reserved for gambling claimants | ✓ Fixed v3.3, invariant tested |
| CP-06 fix: resolveRedemptionPeriod in _gameOverEntropy | Pending gambling claims must resolve even at game-over boundary | ✓ Fixed v3.3, invariant tested |
| Seam-1 fix: gameOver() guard on DGNRS.burn() | Prevent gambling claims under unreachable contract address | ✓ Fixed v3.3, verified by warden simulation |
| CP-07 fix: split-claim design for coinflip dependency | ETH pays immediately; BURNIE deferred until coinflip resolves | ✓ Fixed v3.3, invariant tested |

## Known Issues (Documented, Not Blocking)

| ID | Severity | Description |
|----|----------|-------------|
| WAR-01 | Medium | Compromised admin + 7-day community inattention enables coordinator swap |
| WAR-02 | Medium | Colluding voter cartel at day 6 (5% threshold) |
| WAR-06 | Low | Admin spam-propose gas griefing (no per-proposer cooldown) |
| ~~TQ-01~~ | ~~Medium~~ | ~~RESOLVED v3.9 Phase 77: combined pool replaces _tqWriteKey with _tqReadKey + _tqFarFutureKey~~ |

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Bit 22 reserved for far-future key space | Collision-free third key space for tickets > level+6, reduces max level to 2^22-1 (still millennia) | Good |
| Combined pool approach over simple TQ-01 one-line fix | Reads both _tqReadKey + _tqFarFutureKey, eliminates _tqWriteKey from jackpot entirely | Good — TQ-01 resolved |
| rngLocked guard with phaseTransitionActive exemption | Prevents permissionless FF writes during VRF window while allowing advanceGame-origin writes | Good — proven safe by RNG commitment window proof |
| Fix sampleFarFutureTickets to use _tqFarFutureKey | Was reading wrong key space (_tqWriteKey), BAF FF slices were always empty | Good — DSC-02 resolved |
| BAF scatter: per-round fixed payout, empty rounds return | Prevents few winners from splitting full 70% scatter pool; unfilled rounds recycle to future pool | Good |
| BAF scatter: 20% from current level, 80% random near-future | Better distribution — current level holders get guaranteed share, near-future spread evenly across +1..+6 | Good |

## Current State

v5.0 started (2026-03-25) — Ultimate Adversarial Audit. Three-agent system (Mad Genius / Skeptic / Taskmaster) attacking every state-changing function with mandatory call-tree expansion and storage-write mapping. Motivated by BAF cache-overwrite bug surviving 12 prior audit rounds.

v4.3 closed early (2026-03-25) — prizePoolsPacked batching optimization investigated and abandoned. Phase 99 callsite audit revealed H14's ~1.6M gas savings estimate was a 25x overestimate: warm dirty-slot SSTOREs cost 100 gas (EIP-2200), not 5,000. Actual savings: ~63,800 gas (0.46% of 14M ceiling, ~$0.13/execution at 1 gwei). Not worth the architectural complexity of refactoring `_processAutoRebuy`'s return signature across all callers.

v4.2 complete (2026-03-25) — Daily Jackpot Chunk Removal + Gas Optimization. 4 phases (95-98). Gas ceiling profiled — all 3 daily jackpot stages SAFE with 34.9-42.3% headroom. 24 SLOADs audited, 7 loops analyzed. `_processDailyEthChunk` renamed to `_processDailyEth`.

**Code fixes applied during v4.1:**
- `requestLootboxRng`: blocked while mid-day ticket processing is active (prevents RNG race)
- Near/far-future ticket boundary unified at +5 with jackpot-phase routing fix

**Grand total across all milestones:** 134 findings (16 LOW, 118 INFO), 0 MEDIUM/HIGH outstanding. All confirmed HIGHs/MEDIUMs from v3.3 were fixed and verified. TQ-01 (MEDIUM) resolved in v3.9.

Prior milestones: v1.0-v1.2 (RNG), v1.3 (sDGNRS split), v2.0 (C4A prep), v2.1 (governance), v3.0 (full audit), v3.1 (comments), v3.2 (delta + re-scan), v3.3 (gambling burn audit), v3.4 (skim + lootbox audit), v3.5 (final polish), v3.6 (VRF stall resilience), v3.7 (VRF path audit), v3.8 (VRF commitment window), v3.9 (far-future ticket fix), v4.0 (ticket lifecycle + RNG re-audit), v4.1 (ticket lifecycle integration tests).

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-25 after v5.0 milestone started*
