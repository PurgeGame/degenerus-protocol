# Degenerus Protocol — Audit Repository

## What This Is

Smart contract audit repository for the Degenerus Protocol — an on-chain ETH game with repeating levels, prize pools, BURNIE token economy, DGNRS/sDGNRS governance tokens, and a comprehensive deity pass system. Contains all protocol contracts, deploy scripts, tests (Hardhat + Foundry fuzz), and audit documentation.

## Core Value

Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Current Milestone: v29.0 Post-v27 Contract Delta Audit

**Goal:** Full adversarial audit of all `contracts/` changes since the v27.0 (2026-04-13) audit baseline. v28.0 audited the sibling `database/` repo only, so contract code has been unaudited since v27.0. Covers 8 contract-touching commits: entropy passthrough refactor, earlybird finalize-at-transition + trait-alignment rewrite, decimator burn-key + event emission + terminal-claim passthrough, BAF trait-sentinel, `mint_ETH` quest wei fix, and `boonPacked` mapping exposure.

**Target features:**
- Delta extraction & scope map (8 commits, 12 contract/interface files)
- Earlybird jackpot path audit (both the purchase-phase refactor and today's trait-roll/queue-level rewrite)
- Decimator changes (burn-key by resolution level, event emission, terminal-claim passthrough, consolidated jackpot block)
- Jackpot/BAF + entropy refactors (traitId=420 sentinel, explicit entropy passthrough to `processFutureTicketBatch`)
- Quest/boon/interface drift (`mint_ETH` wei credit, `boonPacked` exposure, `IDegenerusQuests` + `IDegenerusGame` alignment)
- ETH / BURNIE conservation + RNG commitment-window re-proof across the delta
- Regression sweep against v25.0/v26.0/v27.0 findings
- Findings consolidation → `audit/FINDINGS-v29.0.md` + KNOWN-ISSUES.md sync

## Completed Milestone: v28.0 Database & API Intent Alignment Audit

**Status:** Complete (2026-04-15)

**Result:** 6 phases (224–229), 13 plans. 69 findings consolidated into `audit/FINDINGS-v28.0.md` (0 CRITICAL, 0 HIGH, 0 MEDIUM, 27 LOW, 42 INFO). Phase 224 paired all 27 openapi endpoints with 27 implemented routes and 27 `API.md` headings (PAIRED-BOTH). Phase 225 swept handler JSDoc, response shapes, and request schemas across three plans (22 findings). Phase 226 diffed Drizzle schema vs applied SQL migrations (10 findings). Phase 227 audited indexer event-processor coverage + arg-mapping + comment drift (31 findings, including F-28-56 inverse-orphan — handler registered for an event no contract emits). Phase 228 verified cursor/reorg/view-refresh state machines and absorbed 4 Phase 227 deferrals via the D-227-10 scope-guard handoff pattern (5 findings). Phase 229 consolidated all findings under canonical flat `F-28-01..F-28-69` numbering with zero HIGH promotions (D-229-05), marked 48 DEFERRED to a future v29+ remediation backlog and 21 INFO-ACCEPTED retained in-document per D-229-10 (KNOWN-ISSUES.md untouched this milestone per user directive — v28 audits the sim/database/indexer layer, not contracts). All 17/17 requirements satisfied (API-01..05, SCHEMA-01..04, IDX-01..05, FIND-01..03). Cross-repo READ-only audit pattern formalized: writes confined to `audit/` + `.planning/`; no `contracts/`, `database/`, or `test/` changes. Deliverable: `audit/FINDINGS-v28.0.md`.

## Completed Milestone: v27.0 Call-Site Integrity Audit

**Status:** Complete (2026-04-13)

**Goal / Target scope / Incident context:**

**Goal:** Systematically surface runtime call-site-to-implementation mismatches that static compilation does not catch — the same class of bug as the `mintPackedFor` regression, where a call passes compile, may pass superficial tests, but reverts at runtime because selector/target/path alignment is wrong.

**Target scope:**
- Delegatecall target alignment across all `<ADDR>.delegatecall(abi.encodeWithSelector(IFACE.fn.selector, ...))` sites
- Raw selector and calldata literals (`bytes4(0x...)`, `bytes4(keccak256(...))`, manual abi encoders)
- External/public function test coverage gaps (unexercised surface = potential undetected mintPackedFor-class bugs)
- Findings consolidation into audit/FINDINGS-v27.0.md

**Prior incident context:** `mintPackedFor(address)` was declared in `IDegenerusGame` and called via staticcall from `DegenerusQuests._isLevelQuestEligible`, but had no implementation on `DegenerusGame`. Level-quest completion during purchase silently reverted under the narrow condition where accumulated progress crossed threshold on that single call, surfacing as generic `E()`. Fixed in commit `a0bf328b`. Makefile gate `check-interfaces` added in commit `23bbd671`. v27.0 extends this coverage.

**Result:** 4 phases (220-223), 9 plans. Phase 220 wired `scripts/check-delegatecall-alignment.sh` with 1:1 interface↔address mapping preflight (43 delegatecall sites verified ALIGNED). Phase 221 wired `scripts/check-raw-selectors.sh` with 5-pattern coverage and produced the 221-01-AUDIT.md catalog (5 JUSTIFIED INFO sites). Phase 222 classified all 308 external/public functions (19 COVERED / 177+1 CRITICAL_GAP / 112 EXEMPT after matrix refresh), shipped `scripts/coverage-check.sh` with three failure modes, and closed every CRITICAL_GAP via `test/fuzz/CoverageGap222.t.sol` (76 integration tests); Plan 222-03 strengthened test assertions and scoped drift detection to contract sections (commits ef83c5cd + e0a1aa3e). Phase 223 consolidated 16 INFO findings into `audit/FINDINGS-v27.0.md` with a full v25.0 regression appendix (all 13 prior findings verified). Zero exploitable vulnerabilities. All 14/14 requirements satisfied.

## Completed Milestone: v26.0 Bonus Jackpot Split

**Status:** Complete (2026-04-12)

**Result:** 2 phases (218-219), 4 plans. Phase 218 parameterized `_rollWinningTraits` with keccak256 domain separation for independent bonus traits, rewired all 6 jackpot caller sites, removed DJT storage infrastructure, added `DailyWinningTraits` event, and introduced level-1 double coin jackpot branch. Phase 219 delta audit: 10 code path sections, 13 verdicts, 0 findings. Main ETH path proven EQUIVALENT at all 5 sub-paths. Event correctness verified at all 3 emission sites. Entropy independence proven (E1 != E2 via keccak256 preimage resistance). Gas: +1,523 gas/drawing (0.022%), 1.993x headroom PRESERVED. All 11/11 requirements satisfied.

## Completed Milestone: v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)

**Status:** Complete (2026-04-11)

**Result:** 5 phases (213-217), 18 plans. Delta extraction (99 cross-module chains mapped). Adversarial audit (700+ verdicts, 0 VULNERABLE). RNG fresh-eyes (VRF/RNG proven SOUND from first principles). ETH conservation proof (20 flow chains, 75 SSTORE sites). Findings consolidation (13 INFO, 31-item regression with zero regressions). 3 design decisions promoted to KNOWN-ISSUES.md. All 18/18 requirements satisfied. Deliverable: `audit/FINDINGS-v25.0.md`.

## Completed Milestone: v24.0 Gameover Flow Audit & Fix

**Status:** Complete (2026-04-09)

**Result:** 4 phases (203-206), 5 plans. handleGameOverDrain restructured so RNG check gates ALL side effects; reverts with E() when funds > 0 but rngWord unavailable. All 7 trigger+drain requirements verified PASS. Sweep audit: 30-day delay, 33/33/34 split, stETH-first hard-revert, VRF shutdown all verified. Cross-module interaction audit: 5 IXNR requirements PASS. Delta audit: Phase 203 commit proven behaviorally equivalent.

## Completed Milestone: v23.0 Redemption Coinflip Fix

**Status:** Complete (2026-04-09)

**Result:** 2 phases (201-202), 2 plans. Phase 201 removed phantom `creditFlip(SDGNRS, burnieToCredit)` from all 3 redemption resolution paths in AdvanceModule — eliminated BURNIE coinflip pool inflation during resolution. `resolveRedemptionPeriod` changed to void (return value unused). Phase 202 delta audit: EQUIVALENT verdict, supply conservation proven (mint only at claim time via mintForGame), pool consistency verified (1 legitimate SDGNRS creditFlip remains at line 781), reservation/release symmetric, zero test regressions (Hardhat 1296, Foundry 150). All 4/4 requirements satisfied (RCA-01 through RCA-04).

## Completed Milestone: v22.0 Delta Audit & Payout Reference Rewrite

**Status:** Complete (2026-04-08)

## Completed Milestone: v21.0 Jackpot Two-Call Split & Skip-Split Optimization

**Status:** Complete (2026-04-08)

## Completed Milestone: v20.0 Pool Consolidation & Write Batching

**Status:** Complete (2026-04-05)

**Result:** 2 phases (186-187), 6 plans. Phase 186 inlined consolidatePrizePools + runRewardJackpots + _drawDownFuturePrizePool into AdvanceModule as single `_consolidatePoolsAndRewardJackpots` flow with batched SSTOREs. JackpotModule exposes `runBafJackpot` as external entry point with self-call guard. Dead code removed (5 functions + 2 helpers). Quest entropy fixed. All modules under 24KB (JackpotModule 22,858B, AdvanceModule 18,196B). Phase 187 delta audit: full variable sweep across normal/x10/x100 paths, 9/9 correctness checks pass, pool ETH conservation proven algebraically, all peripheral changes verified (self-call guard, passthrough, entropy, dead code, interfaces). Foundry 149/29, Hardhat 1304/5 — zero new regressions. 1 INFO finding (F-187-01: x100 yield dump/keep roll trigger shifted — design improvement). All 13/13 requirements satisfied.

## Completed Milestone: v19.0 Pool Accounting Fix & Sweep

**Status:** Complete (2026-04-04)

**Result:** 3 phases (183-185), 6 plans. Phase 183 fixed the jackpot payout path to defer the futurePool SSTORE and capture paidEth, refunding unspent ETH from empty trait buckets. Phase 184 swept all 81 pool mutation sites across 9 contracts — 0 accounting gaps. Phase 185 delta audit found F-185-01 HIGH (deferred SSTORE overwrote whale pass + auto-rebuy futurePool additions) — fixed by re-reading storage after _executeJackpot (+100 gas warm SLOAD). Foundry + Hardhat: zero unexpected regressions. All 9/9 requirements satisfied.

## Completed Milestone: v18.0 Delta Audit (v16.0-v17.1)

**Status:** Complete (2026-04-04)

## Completed Milestone: v17.1 Comment Correctness Sweep

**Status:** Complete (2026-04-03)

## Completed Milestone: v17.0 Affiliate Bonus Cache

**Status:** Complete (2026-04-03)

**Result:** 2 phases (173-174), 3 plans. Affiliate bonus cached in mintPacked_ bits [185-214] — eliminates 5 cold SLOADs (~10,500 gas) from every activity score computation. Cache write piggybacks on existing SSTORE in recordMintData. Bonus rate doubled to 1 point per 0.5 ETH (cap remains 50). 105 mintPacked_ operations audited across 8 contracts (0 collisions). Storage layout identical across 10 contracts. Foundry 176/27 and Hardhat 1267/42 — zero regressions vs v16.0. All 9/9 requirements satisfied.

## Completed Milestone: v16.0 Module Consolidation & Storage Repack

**Status:** Complete (2026-04-03)

**Result:** 5 phases (168-172), 6 plans. Storage repack: slot 0 filled to 32/32 bytes, currentPrizePool downsized to uint128 in slot 1, old slot 2 eliminated. EndgameModule fully deleted — rewardTopAffiliate inlined into AdvanceModule, runRewardJackpots migrated to JackpotModule, claimWhalePass moved to WhaleModule. All 15 Foundry test files updated for new layout. forge inspect confirms identical layout across 11 contracts. 3 fuzz test invariants repaired (TicketLifecycle double-buffer, RedemptionHandler supply tracking, VRFPathHandler gap backfill). All 14/14 requirements satisfied.

## Completed Milestone: v15.0 Delta Audit (v11.0-v14.0)

**Status:** Complete (2026-04-02)

**Result:** 6 phases (162-167), 11 plans. Function-level changelog (134 items across 21 contracts), level system reference (462 lines), jackpot carryover audit (11 functions SAFE), per-function adversarial audit (76 functions, 76 SAFE, 0 VULNERABLE, 3 INFO), RNG commitment window verification (5 paths, 4 SAFE, 1 KNOWN TRADEOFF), gas ceiling analysis (advanceGame 7,023,530 gas, 1.99x margin), call graph audit (36/36 CLEAN), test baseline (1455 passing, 124 expected failures, 0 unexpected). All 11/11 requirements satisfied.

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

### Validated

- ✓ v7.0 Delta Adversarial Audit (v6.0 Changes) — 4 phases (126-129), 65 changed functions across 12 contracts, 3 FIXED (GOV-01 onlyGame guard, GH-01/GH-02 burnAtGameOver reorder), 4 INFO, 0 open actionable findings, all 11 changed contract storage layouts verified via forge inspect — v7.0 Phases 126-129
- ✓ v8.0 Pre-Audit Hardening — 5 phases (130-134), 13 plans. Bot race (Slither + 4naly3er, 113 categories triaged), ERC-20 compliance (4 tokens, 5 deviations documented), event correctness (30 findings, all DOCUMENT), comment re-scan (72 fixes applied), consolidation (KNOWN-ISSUES.md 5→30+ entries, C4A README drafted, 1 dead code fix, BurnieCoinflip immutable→constant refactor). 14/14 requirements satisfied. — v8.0 Phases 130-134
- ✓ v8.1 Final Audit Prep — 3 phases (135-137), 5 plans. Delta adversarial audit (29 functions, 0 VULNERABLE, 6 INFO), test hygiene (5 files committed, suites green), documentation finalized (KNOWN-ISSUES.md +4 entries, C4A README finalized). 10/10 requirements satisfied. — v8.1 Phases 135-137

### Validated

- ✓ v9.0 Contest Dry Run — 3 phases (138-140), 8 plans. 5 fresh-eyes wardens, 152 attack surfaces, 0 Medium+ findings, $0 projected payout — v9.0 Phases 138-140
- ✓ v10.0 Audit Submission Ready — 3 phases (141-143). Delta audit of dailyIdx/backfill/turbo changes, documentation finalized, vault sDGNRS burn/claim verified — v10.0 Phases 141-143
- ✓ v10.1 ABI Cleanup — 3 phases (144-146). 9 forwarding wrappers removed, 16 unused views removed, 3 bonus removals, BurnieCoinflip creditors expanded, vault-owner access control on Game, ~238 lines removed — v10.1 Phases 144-146
- ✓ v11.0 BURNIE Endgame Gate — gameOverPossible flag, drip projection, MintModule/LootboxModule enforcement — v11.0 Phases 151-152
- ✓ v12.0 Level Quests — core design, integration mapping, economic + gas analysis — v12.0 Phases 153-155
- ✓ v13.0 Level Quests Implementation — interfaces, storage, quest logic, handler integration, carryover redesign — v13.0 Phases 156-158.1
- ✓ v14.0 Activity Score & Quest Gas Optimization — compute-once score, handler consolidation, price removal, SLOAD dedup — v14.0 Phases 159-161
- ✓ v15.0 Delta Audit — 76 functions audited (all SAFE), RNG commitment windows verified, gas ceiling 1.99x margin, call graph clean, 1455 tests passing — v15.0 Phases 162-167
- ✓ v16.0 Module Consolidation & Storage Repack — EndgameModule eliminated (3 functions redistributed), storage slots 0-2 repacked (slot 0 32/32, currentPrizePool uint128 in slot 1, slot 2 killed), 14/14 requirements satisfied — v16.0 Phases 168-172
- ✓ v17.0 Affiliate Bonus Cache — cached affiliate bonus in mintPacked_ bits [185-214] eliminating 5 cold SLOADs from activity score, rate doubled to 1 point per 0.5 ETH, 105 mintPacked_ operations audited (0 collisions), both test suites zero regressions, 9/9 requirements satisfied — v17.0 Phases 173-174
- ✓ v17.1 Comment Correctness Sweep — 40 contracts swept, 72 findings (30 LOW, 42 INFO), 56 fixed, 0 regressions from v3.1/v3.5, WWXRP decimal scaling added — v17.1 Phases 175-178
- ✓ v18.0 Delta Audit (v16.0-v17.1) — 4 phases (179-182), full delta audit of v16.0-v17.1 changes — v18.0 Phases 179-182
- ✓ v19.0 Pool Accounting Fix & Sweep — jackpot payout ETH fix, 81-site pool sweep, HIGH finding fixed — v19.0 Phases 183-185
- ✓ v20.0 Pool Consolidation & Write Batching — consolidatePrizePools + runRewardJackpots inlined, batched SSTOREs, 13/13 requirements — v20.0 Phases 186-187
- ✓ v21.0 Jackpot Two-Call Split & Skip-Split Optimization — v21.0 Phases 195-198
- ✓ v22.0 Delta Audit & Payout Reference Rewrite — purchase phase jackpot redesign, event catalog — v22.0 Phases 199-200
- ✓ v23.0 Redemption Coinflip Fix — phantom creditFlip removed from 3 resolution paths, EQUIVALENT delta audit, 4/4 requirements — v23.0 Phases 201-202
- ✓ v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG) — 5 phases, 18 plans, 18/18 requirements. Delta extraction (99 chains), adversarial (700+ verdicts, 0 VULNERABLE), RNG fresh-eyes (SOUND), ETH conservation (algebraic proof), findings consolidation (13 INFO, 31 regressions checked, 0 regressed) — v25.0 Phases 213-217

## Completed Milestone: v8.1 Final Audit Prep

**Status:** Complete (2026-03-28)

**Result:** 3 phases (135-137), 5 plans. Delta adversarial audit of 5 changed contracts (29 functions, 0 VULNERABLE, 6 INFO). Price feed governance (~400 new lines) verified safe. Boon multi-category coexistence verified. Recycling bonus house edge maintained. Storage layouts 5/5 PASS via forge inspect. 5 test files committed (Hardhat 1351 passing, Foundry 6/6 new tests passing). KNOWN-ISSUES.md updated with 4 new entries. C4A contest README finalized (DRAFT removed). All 10/10 requirements satisfied (DELTA-01-04, TEST-01-03, DOC-01-03).

## Completed Milestone: v8.0 Pre-Audit Hardening

**Status:** Complete (2026-03-27)

**Result:** 5 phases (130-134), 13 plans. Slither 1,959 findings + 4naly3er 4,453 instances triaged (0 FIX, 27 DOCUMENT, 84 FP by category). ERC-20 compliance verified across 4 tokens. Event correctness audit across 29 contracts (30 INFO findings). NatSpec delta sweep (72 fixes). KNOWN-ISSUES.md expanded from 5 to 30+ entries with detector IDs. C4A contest README drafted. Dead code removed (_lootboxBpsToTier). BurnieCoinflip 4 immutables converted to constants via ContractAddresses.

## Completed Milestone: v7.0 Delta Adversarial Audit (v6.0 Changes)

**Status:** Complete (2026-03-26)

**Result:** 4 phases (126-129), 11 plans. Delta extraction (17 files, 65 functions, 23/29 MATCH, 5 DRIFT). DegenerusCharity full adversarial audit (17 functions, 0 VULNERABLE). Changed contract audit (48 functions across 11 contracts, 0 VULNERABLE). Consolidated: 3 FIXED (GOV-01, GH-01, GH-02), 4 INFO, 0 open actionable findings. All storage layouts verified via forge inspect.

## Completed Milestone: v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity

**Status:** Complete (2026-03-26)

**Result:** 6 phases (120-125). Test suite cleanup (green baseline), storage/gas fixes (lastLootboxRngWord deletion, double-SLOAD elimination, NatSpec fixes, deity boon downgrade prevention, advanceBounty rewrite), degenerette freeze fix (frozen-context ETH routed through pending pools), DegenerusCharity contract (soulbound GNRUS token with burn redemption and sDGNRS governance), game integration (resolveLevel + handleGameOver hooks), test suite pruning (13 redundant tests deleted, zero unique coverage lost).

## Completed Milestone: v5.0 Ultimate Adversarial Audit

**Status:** Complete (2026-03-25)

**Result:** 17 phases (103-119), 29 contracts, 693 functions, ~15,000+ lines Solidity. Three-agent adversarial system (Taskmaster/Mad Genius/Skeptic) with mandatory call-tree expansion, storage-write mapping, and BAF cache-overwrite checks on every state-changing function. 100% Taskmaster coverage in all 16 units. Zero actionable findings (0 CRITICAL/HIGH/MEDIUM/LOW, 29 INFO). BAF-class bugs comprehensively eliminated. ETH conservation PROVEN. All 4 master deliverables produced (FINDINGS.md, ACCESS-CONTROL-MATRIX.md, STORAGE-WRITE-MAP.md, ETH-FLOW-MAP.md).

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
- New: Creator DGNRS vesting — 50B (25%) at deploy to CREATOR, 5B per game level claimable by vault owner via claimVested(). Fully vested at level 30. unwrapTo guard changed from 5h lastVrfProcessed timestamp to rngLocked() boolean.

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
| unwrapTo blocked while rngLocked | Prevents vote-stacking via DGNRS→sDGNRS conversion during VRF request/fulfillment window (replaced 5h timestamp check with rngLocked boolean) | ✓ v9.0 |
| Creator DGNRS vesting (50B + 5B/level) | Creator gets 25% at deploy, vault owner claims 5B per level up to 200B total at level 30. Prevents governance domination at launch. | ✓ v9.0 |
| Remove death clock pause for governance | Chainlink death + game death + 256 proposals is unrealistic; reduces complexity | ✓ Post-v2.1 |
| Remove activeProposalCount tracking | No on-chain consumer after death clock pause removal; eliminates uint8 overflow surface | ✓ Post-v2.1 |
| Move _voidAllActive before external calls | CEI compliance in _executeSwap; prevents theoretical sibling-proposal reentrancy | ✓ Post-v2.1 |
| Flag-only comment audit (no auto-fix) | Findings list is the deliverable — protocol team decides which to fix before C4A | ✓ Good — 84 findings produced, 5 cross-cutting patterns identified |
| CP-08 fix: subtract pending reservations in _deterministicBurnFrom | Post-gameOver burns must not consume ETH reserved for gambling claimants | ✓ Fixed v3.3, invariant tested |
| CP-06 fix: resolveRedemptionPeriod in _gameOverEntropy | Pending gambling claims must resolve even at game-over boundary | ✓ Fixed v3.3, invariant tested |
| Seam-1 fix: gameOver() guard on DGNRS.burn() | Prevent gambling claims under unreachable contract address | ✓ Fixed v3.3, verified by warden simulation |
| CP-07 fix: split-claim design for coinflip dependency | ETH pays immediately; BURNIE deferred until coinflip resolves | ✓ Fixed v3.3, invariant tested |
| Remove BurnieCoin forwarding wrappers (creditFlip, creditFlipBatch, etc.) | Callers pay extra gas for hop; all contracts are same-owner so access control between them is redundant routing | ✓ v10.1 — 7 wrappers removed, 18 call sites rewired |
| Vault-owner access control on Game (replacing Admin middleman) | Admin.stakeGameEthToStEth and Admin.setLootboxRngThreshold were pure forwards; Game checks vault owner directly | ✓ v10.1 |
| Merge mintForCoinflip into mintForGame | Two identical mint functions with different caller checks; merged to single function accepting COINFLIP + GAME | ✓ v10.1 |
| Replace 30-day BURNIE ban with gameOverPossible flag | Static elapsed-time ban replaced by dynamic drip-projection check; flag set at L10+ purchase-phase entry when futurePool drip cannot cover nextPool deficit | ✓ v11.0 Phase 151 |
| WAD-scale geometric drip projection (0.9925 decay) | Conservative 0.75% daily decay rate via closed-form series futurePool*(1-0.9925^n); ~700 gas for _wadPow | ✓ v11.0 Phase 151 |
| BURNIE lootbox far-future redirect (bit 22) when flag active | Current-level tickets redirect to far-future key space; near-future rolls (currentLevel+1..+6) land normally | ✓ v11.0 Phase 151 |
| Repack slot 0 to 32/32 bytes (add ticketsFullyProcessed + gameOverPossible) | Fill 2-byte padding in slot 0 to eliminate wasted space | ✓ v16.0 Phase 168 |
| Downsize currentPrizePool from uint256 to uint128 | 340B ETH exceeds total supply; uint128 saves a full slot | ✓ v16.0 Phase 168 |
| Eliminate EndgameModule entirely | 3 functions redistributed to existing modules; reduces delegatecall overhead and deploy complexity | ✓ v16.0 Phases 169-171 |
| claimWhalePass to WhaleModule (not JackpotModule) | WhaleModule already has whale-related logic; better semantic fit | ✓ v16.0 Phase 171 |
| NonceBurner placeholder in fuzz test deploy | Empty contract preserves nonce ordering after EndgameModule deletion | ✓ v16.0 Phase 171 |
| Cache affiliate bonus in mintPacked_ bits [185-214] | Eliminate 5 cold SLOADs (~10,500 gas) from every activity score read; write piggybacks on existing SSTORE | ✓ v17.0 Phase 173 |
| Affiliate bonus rate 1 point per 0.5 ETH (was 1 per 1 ETH) | Easier to reach cap; doubles reward for moderate affiliates | ✓ v17.0 Phase 173 |
| Remove phantom creditFlip from redemption resolution | creditFlip(SDGNRS, burnieToCredit) inflated coinflip pool without backing; removed from all 3 resolution paths | ✓ v23.0 Phase 201 |
| resolveRedemptionPeriod changed to void return | No caller uses the return value; prevents future accidental credit | ✓ v23.0 Phase 201 |

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

v26.0 Bonus Jackpot Split milestone started (2026-04-11). Splitting jackpot system into two independent drawings: main (ETH, current-level tickets, main traits) and bonus (BURNIE, future-level tickets, independent trait roll with hero preserved). Both `payDailyCoinJackpot` (purchase phase) and `payDailyJackpotCoinAndTickets` coin+carryover portions (jackpot phase) affected. No storage for bonus traits — emit event only.

## Completed Milestone: v17.1 Comment Correctness Sweep

**Status:** Complete (2026-04-03)

**Result:** 4 phases (175-178), 14 plans. Full comment sweep of all 40 production contracts (modules, core game, tokens, infrastructure, libraries, interfaces, misc). 72 findings identified (30 LOW, 42 INFO), 56 fixed in commit 9c3e31bd. 0 regressions from v3.1/v3.5 prior sweeps. Key fixes: DGNRS→sDGNRS recipient corrections, stale module lists (EndgameModule removed), mintPacked_ bit layout updated for v17.0 cache fields, affiliate bonus tiered rate docs, WWXRP decimal scaling for real 6-decimal wXRP. All 8/8 requirements satisfied.

## Completed Milestone: v12.0 Level Quests

**Status:** Complete (2026-04-01)

**Result:** 3 phases (153-155), 3 plans. Planning-only milestone — produced design specification for per-level quest system. 536-line spec (eligibility, mechanics, 10x targets, storage, completion flow). 852-line integration map (10 contracts, 6 handler sites). Economic analysis: BURNIE inflation bounded at 12M/month worst-case (<16% ticket volume). Gas analysis: +22.4K quest roll (0.32%), eligibility 150-280 hot. 1.99x safety margin preserved. gameOverPossible interaction disproven (disjoint state domains). All 14 requirements satisfied.

## Completed Milestone: v11.0 BURNIE Endgame Gate

**Status:** Complete (2026-03-31)

**Result:** 2 phases (151-152), 4 plans. 30-day BURNIE ban replaced with gameOverPossible flag — dynamic drip-projection-based endgame detection at L10+ purchase-phase. WAD-scale geometric series (_wadPow + _projectedDrip) in AdvanceModule. MintModule reverts with GameOverPossible when flag active; LootboxModule redirects current-level BURNIE tickets to far-future key space (bit 22). Delta audit: 10 functions, 10 SAFE, 0 VULNERABLE, 1 INFO (V11-001 stale comment). RNG commitment window: 3 paths SAFE. Gas ceiling: +21K gas worst-case (0.3% increase), 2.0x margin preserved. All 13 requirements satisfied.

**Grand total across all milestones:** 148+ findings (16 LOW, 129+ INFO), 0 MEDIUM/HIGH outstanding. KNOWN-ISSUES.md comprehensive with 35+ entries.

## Completed Milestone: v10.3 Delta Adversarial Audit (v10.1 Changes)

**Status:** Complete (2026-03-30)

**Result:** 2 phases (149-150). 38 functions audited across 12 contracts: 30 SAFE, 8 INFO, 0 VULNERABLE. BurnieCoinflip creditor expansion, vault-owner access control, mintForGame merger all verified safe. Storage layouts clean (12 contracts via forge inspect). No KNOWN-ISSUES updates needed.

## Completed Milestone: v10.2 Ticket Mint Gas Optimization

**Status:** Complete (2026-03-30)

**Result:** 1 phase (147). Static gas analysis of advanceGame ticket-processing loop confirmed WRITES_BUDGET_SAFE=550 is optimal. 2.0x safety margin under worst-case adversarial conditions (7M vs 14M ceiling). Cap could safely go to 800 (1.39x margin) but per-ticket gas is nearly identical — more calls just spreads bounty wider. No code changes needed. Phase 148 (implementation) skipped.

## Completed Milestone: v10.1 ABI Cleanup

**Status:** Complete (2026-03-30)

**Result:** 3 phases (144-146), 5 plans. Scanned 25 production contracts (~225 functions). Removed 9 forwarding wrappers (7 BurnieCoin + 2 Admin), 16 unused views from DegenerusGame, plus 3 bonus removals (creditCoin, onlyFlipCreditors, mintForCoinflip merge). BurnieCoinflip creditors expanded to GAME+COIN+AFFILIATE+ADMIN. Admin middleman replaced with vault-owner access control on Game. ~238 lines removed, 1319 Hardhat tests passing.

## Completed Milestone: v10.0 Audit Submission Ready

**Status:** Complete (2026-03-29)

**Result:** 3 phases (141-143), 3 plans. Delta adversarial audit of dailyIdx init, backfill cap, turbo-at-L0 removal (all SAFE, 2 INFO). Documentation + submission readiness finalized. Vault sDGNRS burn/claim + self-win burn delta audit verified safe. votingSupply on sDGNRS, vault excluded from governance.

v9.0 Contest Dry Run shipped (2026-03-28). 5 wardens, 152 attack surfaces, 0 Medium+ findings, $0 projected payout. dailyIdx init + backfill cap committed post-milestone.

**Grand total across all milestones:** 147+ findings (16 LOW, 128+ INFO), 0 MEDIUM/HIGH outstanding. KNOWN-ISSUES.md comprehensive with 35+ entries. C4A contest README finalized.

Prior milestones: v1.0-v1.2 (RNG), v1.3 (sDGNRS split), v2.0 (C4A prep), v2.1 (governance), v3.0 (full audit), v3.1 (comments), v3.2 (delta + re-scan), v3.3 (gambling burn audit), v3.4 (skim + lootbox audit), v3.5 (final polish), v3.6 (VRF stall resilience), v3.7 (VRF path audit), v3.8 (VRF commitment window), v3.9 (far-future ticket fix), v4.0 (ticket lifecycle + RNG re-audit), v4.1 (ticket lifecycle integration tests), v4.2 (daily jackpot chunk removal), v4.3 (prizePoolsPacked — closed early), v4.4 (BAF cache-overwrite fix), v5.0 (ultimate adversarial audit), v6.0 (test cleanup + fixes + charity), v7.0 (delta adversarial audit), v8.0 (pre-audit hardening), v8.1 (final audit prep), v9.0 (contest dry run), v10.0 (audit submission ready), v10.1 (ABI cleanup), v10.2 (writes cap analysis — no change needed), v10.3 (v10.1 delta audit), v11.0 (BURNIE endgame gate), v12.0 (level quests design), v13.0 (level quests implementation), v14.0 (activity score + gas optimization), v15.0 (delta audit), v16.0 (module consolidation + storage repack).

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
*Last updated: 2026-04-13 — v28.0 Database & API Intent Alignment Audit milestone started. Audit target: sibling `database/` repo (API handlers, DB schema + migrations, indexer) against API.md + openapi.yaml + in-source comments. Deliverable: audit/FINDINGS-v28.0.md.*
