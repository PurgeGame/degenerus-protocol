# Milestones

## v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit (Shipped: 2026-03-23)

**Phases completed:** 10 phases, 21 plans, 36 tasks

**Key accomplishments:**

- Both ticket processing functions fully traced with 241 file:line citations, two distinct VRF-derived entropy chains documented, mid-day divergence confirmed by design, LCG PRNG algorithm verified identical across modules
- Complete cursor state machine with 30 write sites and 13 read sites enumerated, traitBurnTicket storage layout verified at slot 11 with assembly pattern confirmed, 13 v3.8 claims cross-referenced yielding 4 DISCREPANCY and 6 INFO findings
- Exhaustive trace of 20 ticketQueue and 14 traitBurnTicket read sites for winner selection across 5 jackpot types with file:line citations verified against Solidity source
- Winner index formulas documented for 9 jackpot types with 200+ file:line citations, 23 prior audit claims cross-referenced (15 CONFIRMED, 6 DISCREPANCY, 2 STALE), 0 new findings
- Daily ETH jackpot entry points, BPS allocation table (5 days x 3 modes), Phase 0 vs Phase 1 comparison (14 properties), early-burn path, and budget split logic documented with 286 file:line citations; 10 cross-reference discrepancies found against prior audit documentation
- JackpotBucketLib 8 functions traced, _processDailyEthChunk line-by-line with determinism proof, carryover source selection decision tree, pre-deduction loss path flagged (INFO), 13-entry RNG catalog verified safe, comprehensive cross-reference (13 items, 11 INFO findings), all 5 DETH requirements VERIFIED
- Both coin jackpot entry points traced end-to-end (payDailyCoinJackpot + payDailyJackpotCoinAndTickets) with 218 file:line citations, far-future _tqFarFutureKey winner selection and near-future _randTraitTicketWithIndices documented, jackpotCounter lifecycle traced across GS/AM/JM/MM (8 touchpoints), v3.8 Category 3 claims verified (1 DISCREPANCY), 3 INFO findings
- _distributeTicketJackpot traced end-to-end with 139 citations: 3 callers, 4-bucket winner selection via _randTraitTicket from traitBurnTicket with deity virtual entries, tickets queued to lvl+1 via _queueTickets, budget chain via _budgetToTicketUnits and pack/unpack pair
- Early-bird lootbox trigger, 3% futurePrizePool allocation, 100-winner loop with EntropyLib.entropyStep, and final-day DGNRS 1% Reward pool distribution traced with 122 file:line citations; 8 INFO findings (EB-01 through EB-04, FD-01 through FD-04), DSC-02 confirmed non-applicable
- BAF two-contract jackpot traced across DegenerusJackpots and EndgameModule: 7-slice prize distribution (100% verified), 50-round scatter mechanics, large/small payout split, DSC-02 impact assessed (~10% recycled), winnerMask confirmed dead code; 161 file:line citations, 2 INFO findings + 1 cross-ref
- Regular decimator (burn/resolution/claim with bucket migration and packed subbucket offsets) and terminal decimator (activity-score bucket, time multiplier, GAMEOVER resolution) fully traced with 323 file:line citations; DEC-01 decBucketOffsetPacked collision analyzed and withdrawn as FALSE POSITIVE; 7 INFO findings (DEC-02 through DEC-08)
- Degenerette bet/resolve/payout lifecycle traced with 133 file:line citations: 3 currency types, lootbox RNG binding, 8-attribute match counting, 25/75 ETH/lootbox split with 10% pool cap, _addClaimableEth confirmed NO auto-rebuy (vs JM/EM/DM versions), sDGNRS rewards for 6+ matches, consolation WWXRP; DGN-01 off-by-one withdrawn as FALSE POSITIVE; 6 Informational findings (DGN-02 through DGN-07)
- 55/55 v3.8 commitment window verdict rows re-verified against current Solidity: all SAFE, 27 DGS slot shifts from boon packing, 2 protection descriptions updated for v3.9 FF key space
- 18 CW-01-but-not-CW-04 candidate variables assessed (15 DGS + 2 CF + 1 v3.9 guard): all correctly excluded, CW-04 inventory confirmed complete, findings-consolidated updated with Phase 88 results (0 new findings)
- Status:
- Created 4 SUMMARY files and 1 VERIFICATION report for Phase 87 (other jackpots) from existing audit artifacts: 739 file:line citations verified across 2,152 lines, all 6 OJCK requirements SATISFIED, closing the gap in GSD tracking
- 84-VERIFICATION.md created with 6/6 must-haves verified, all PPF-01 through PPF-06 SATISFIED with evidence citations from audit/v4.0-prize-pool-flow.md (601 lines, 148 file:line citations)
- Corrected 12 stale traceability rows in REQUIREMENTS.md -- OJCK-01-06 mapped to Phase 87, PPF-01-06 mapped to Phase 84, coverage counts updated from 31/15 to 44/2
- Complete FINAL v4.0-findings-consolidated.md with 51 INFO findings across 8 phases (81-88), DEC-01/DGN-01 documented as withdrawn false positives, grand total 134
- KNOWN-ISSUES.md v4.0 entry rewritten from 3 Phase-81 findings to 51 INFO across all 8 phases with DEC-01/DGN-01 withdrawn as false positives
- 6-dimension cross-phase consistency check across all 8 phases (81-88) with 51 finding IDs verified against 13 source documents, no contradictions found, 89-VERIFICATION.md created

---

## v3.9 Far-Future Ticket Fix (Shipped: 2026-03-23)

**Phases completed:** 7 phases, 8 plans, 14 tasks

**Key accomplishments:**

- TICKET_FAR_FUTURE_BIT constant (1 << 22) and _tqFarFutureKey pure helper with Foundry fuzz proof of three-way key space collision-freedom
- Far-future ticket routing via conditional _tqFarFutureKey selection with rngLocked guard and phaseTransitionActive exemption in all three queue functions
- Dual-queue drain in processFutureTicketBatch with FF-bit cursor encoding and _prepareFutureTickets resume fix
- Combined pool winner selection reading frozen read buffer + FF key in _awardFarFutureCoinJackpot, eliminating TQ-01 write-buffer vulnerability
- 5 Foundry tests + formal proof document proving EDGE-01 (no double-counting between FF and write buffer) and EDGE-02 (no re-processing after FF key drain) are SAFE -- zero contract changes
- Formal proof that no permissionless action during VRF commitment window can influence far-future coin jackpot winner selection -- 12 mutation paths enumerated with SAFE verdicts, combined pool length invariant proven, all 5 research pitfalls addressed
- 34 existing Foundry tests across 4 files formally verified as satisfying TEST-01 through TEST-04: routing, processing, jackpot selection, and rngLocked guard requirements all SATISFIED
- Full protocol integration test deploying 23 contracts via DeployProtocol, driving 9 level transitions with prize pool seeding, and proving zero FF ticket stranding via vm.load storage inspection

---

## v3.8 VRF Commitment Window Audit (Shipped: 2026-03-23)

**Phases completed:** 6 phases, 13 plans, 21 tasks

**Key accomplishments:**

- Forward-trace and backward-trace catalogs of 297 table rows covering all VRF-touched storage variables across 3 contract domains and 7 outcome categories, with authoritative slot numbers from forge inspect
- Exhaustive mutation surface mapping of 51 VRF-touched variables across 121 external mutation paths with call-graph depth, access control, and ticket queue double-buffer commitment boundary analysis
- 51/51 variables SAFE with zero vulnerabilities -- five layered defense mechanisms (rngLockedFlag, prizePoolFrozen, double-buffer, lootboxRngIndex keying, coinflip day+1 keying) proven to fully protect both commitment windows
- Exhaustive enumeration of all 87 permissionless mutation paths across 7 protection mechanisms -- CW-04 proof, MUT-02 zero-vulnerability report, MUT-03 depth verification (D0-D3+), and verdict summary statistics confirming 51/51 SAFE
- Complete coinflip lifecycle trace with 5 state transitions, 4 resolution paths, backward-traced outcome purity proof, and all 10 entry points assessed SAFE across both commitment windows
- 7 multi-TX attack sequences modeled against coinflip commitment window: 7/7 SAFE, 0 VULNERABLE, 3 Informational findings, day+1 keying proven as primary defense mechanism
- Daily VRF word traced through 10 consumers with bit allocation map, dual sub-window commitment window proof (Periods A/B/C all SAFE), 11 permissionless actions tabulated, both research open questions resolved with verified line citations
- DAYRNG-03 proves no cross-day contamination: 5 isolation mechanisms (_unlockRng reset, rngWordByDay write-once, totalFlipReversals consumed-and-cleared, 4 key-based isolation, gap day keccak256 derivation) with 6 carry-over state items classified as legitimate context
- Complete exploitation scenario for _awardFarFutureCoinJackpot _tqWriteKey bug (MEDIUM severity) with 5-step attack sequence, Phase 69 verdict correction, and Fix Option A recommendation backed by global swap proof
- Systematic scan of all 10 VRF-dependent outcome categories: 37 variables analyzed, 1 VULNERABLE (TQ-01 at JM:2544), 36 SAFE across five protection layers
- BoonPacked 2-slot struct with 14 day fields + 7 tier fields in DegenerusGameStorage, all 5 BoonModule functions rewritten from 29 SLOADs to 2 SLOADs per checkAndClearExpiredBoon call
- All 7 boon functions across LootboxModule, WhaleModule, and MintModule rewritten from 29 individual mapping reads to packed BoonPacked struct with single-tier lootbox boost (BOON-05)

---

## v3.7 VRF Path Audit (Shipped: 2026-03-22)

**Phases completed:** 5 phases, 10 plans, 18 tasks

**Key accomplishments:**

- 22 Foundry fuzz/unit tests proving VRF callback revert-safety, gas budget, requestId lifecycle, rngLockedFlag mutual exclusion, and 12h timeout retry correctness across all 4 VRFC requirements
- v3.7 VRF core findings document with Slot 0 assembly audit (SAFE), gas budget analysis (6-10x margin), all 4 VRFC requirements VERIFIED, 0 HIGH/MEDIUM/LOW and 2 INFO findings cataloged with C4A severity
- 21 Foundry fuzz/unit tests proving lootbox RNG index lifecycle correctness: 1:1 index-to-word mapping, zero-state guards at all VRF injection points, per-player entropy uniqueness via keccak256 preimage analysis, and full purchase-to-open lifecycle trace
- C4A-ready findings document with 2 INFO findings (V37-003: _getHistoricalRngFallback missing zero guard, V37-004: mid-day lastLootboxRngWord design note), all 5 LBOX requirements VERIFIED with 21-test evidence, and KNOWN-ISSUES.md updated with Phase 64 results
- 17 Foundry fuzz/unit tests proving all 7 STALL requirements: gap backfill entropy uniqueness, manipulation window identity, gas ceiling (120-day < 25M), coordinator swap state completeness, zero-seed unreachability, V37-001 guard branches, and dailyIdx timing consistency
- C4A-format findings document with 3 INFO findings (V37-005 manipulation window, V37-006 prevrandao 1-bit bias, V37-007 level-0 fallback) covering all 7 STALL requirements VERIFIED, grand total 87 findings (16 LOW, 71 INFO)
- Foundry invariant handler (7 actions, 9 ghost vars) and 6 parametric fuzz tests proving no arbitrary operation sequence can violate VRF path lifecycle invariants (index monotonicity, stall recovery, gap backfill)
- Halmos symbolic proof that uint16((word >> 8) % 151 + 25) always produces [25, 175] with safe uint16 cast, verified for complete 2^256 input space
- Independent verification of all Phase 66 VRF path test coverage deliverables: 10/10 truths verified via fresh forge test and Halmos runs, all 4 requirements (TEST-01 through TEST-04) satisfied
- V37-001 annotated RESOLVED at all 3 locations, Phase 66 cross-references added to all 3 findings docs, KNOWN-ISSUES.md updated -- closes BF-01, MC-01, MC-04 milestone audit gaps

---

## v3.6 VRF Stall Resilience (Shipped: 2026-03-22)

**Phases completed:** 4 phases, 6 plans, 9 tasks

**Key accomplishments:**

- Gap day RNG backfill via keccak256(vrfWord, gapDay) with per-day coinflip resolution in DegenerusGameAdvanceModule
- Orphaned lootbox index backfill via keccak256(lastLootboxRngWord, orphanedIndex) + midDayTicketRngPending clearing in coordinator swap
- LootboxRngApplied event added to orphaned index backfill for indexer parity, plus totalFlipReversals carry-over NatSpec for C4A warden visibility
- 3 Foundry integration tests proving VRF stall-to-recovery cycle: gap day RNG backfill, coinflip resolution across gap days, and lootbox opens after orphaned index recovery
- 8 attack surfaces SAFE with code-level reasoning across ~75 lines of v3.6 VRF stall resilience Solidity in DegenerusGameAdvanceModule.sol
- v3.6 consolidated findings with 2 INFO (V36-001/V36-002), 78 prior findings carried forward, KNOWN-ISSUES and FINAL-FINDINGS-REPORT updated for VRF stall automatic recovery

---

## v3.5 Final Polish — Comment Correctness + Gas Optimization (Shipped: 2026-03-22)

**Phases completed:** 8 phases, 23 plans, 37 tasks

**Key accomplishments:**

- 5 arithmetic verdicts (4 SAFE, 1 INFO) for futurepool skim pipeline: overshoot surcharge monotonicity proven, ratio adjustment bounded +/-400 bps, bit-field overlap documented as INFO, triangular variance underflow-safe via halfWidth clamp, 80% take cap confirmed post-variance
- Algebraic ETH conservation proof (T and I cancel in sum_before = sum_after) and insurance skim precision verified exact above 100 wei with sub-100 unreachable
- Three economic verdicts (ECON-01/02/03 all SAFE) proving overshoot acceleration, stall independence, and level-1 safety with phase 50 findings consolidation (3 INFO, 0 HIGH/MEDIUM/LOW)
- 50/50 sDGNRS redemption split proven correct with algebraic conservation proof; gameOver bypass confirmed pure ETH/stETH routing with no lootbox or BURNIE; pendingRedemptionEthValue underflow impossible via floor-division inequality
- REDM-03 SAFE (160 ETH cap enforced via cumulative uint256 check before uint96 cast, period gating prevents cross-period stacking) and REDM-05 SAFE (96+96+48+16=256 bits, all cast sites within bounds with INFO-01 noting burnieOwed has no explicit cap)
- REDM-04 SAFE: activity score snapshotted once per period via guard condition, captured locally before struct delete, +1 encoding correctly reversed, passed unchanged through sDGNRS -> Game -> LootboxModule chain; no uint16 overflow (max 30501 vs 65535)
- Cross-contract access control chain (sDGNRS->Game->LootboxModule) verified SAFE at every hop; lootbox reclassification confirmed as pure internal accounting with MEDIUM-severity unchecked subtraction underflow finding (REDM-06-A)
- 4 INV-named fuzz tests proving skim conservation and 80% take cap invariants across 4000 total fuzz runs, covering Phase 50 edge cases (lastPool=0, R=50 overshoot, 50 ETH level-1 bootstrap)
- INV-03 redemption lootbox split conservation proven at two levels: pure arithmetic fuzz (3 tests x 1000 runs) and lifecycle invariant (INV-08, 256 runs x 128 depth) via RedemptionClaimed event ghost tracking
- v3.4 consolidated findings deliverable with 6 new findings (1 MEDIUM, 5 INFO), 30 v3.2 carry-forward (6 LOW, 24 INFO), severity-sorted master table, fix priority guide flagging REDM-06-A for pre-C4A fix
- 7 findings (1 LOW, 6 INFO) across DegenerusGame.sol, StakedDegenerusStonk.sol, DegenerusStonk.sol -- 3 are regressions from v3.1 fixes overwritten by v3.3/v3.4 code changes
- 5 new comment findings (1 LOW, 4 INFO) across AdvanceModule and LootboxModule; all 4 prior findings confirmed fixed; 3,267 lines and 388 NatSpec tags verified
- 5 contracts (2,902 lines) audited for NatSpec accuracy: 5 new findings (2 LOW, 3 INFO), 8 prior findings verified FIXED
- 4 new findings (2 LOW, 2 INFO) across DegenerusAdmin, DegenerusVault, DegenerusGameStorage; all 4 prior fixes verified accurate; full storage slot diagram verified
- NatSpec verification across 10 game module contracts (~8,327 lines): 5 prior v3.2 findings confirmed FIXED, 2 new INFO findings (missing step in JackpotModule flow overview, duplicate stale @notice in DegeneretteModule)
- NatSpec audit of 21 peripheral contracts/interfaces/libraries (~5,028 lines): all 10 v3.2 prior findings FIXED, 3 new INFO findings
- 49 DegenerusGameStorage variables (Slots 0-24) liveness-traced across all 13 inheriting contracts; 2 DEAD variables found (earlyBurnPercent never read, lootboxEthTotal never read)
- 85 storage variables in DegenerusGameStorage Slots 25-109 analyzed for liveness: 84 ALIVE, 1 DEAD (lootboxIndexQueue write-only finding saves ~20k gas per purchase)
- 70 standalone storage variables all ALIVE across 11 contracts; dead code sweep of 34 contracts found 5 INFO findings (1 dead error, 4 dead events)
- 13 gas findings (3 LOW, 10 INFO) consolidated into master document with storage packing analysis covering 10 boon mapping pairs and 7 structurally wasted scalar slots
- All 12 advanceGame stages profiled with worst-case gas: 8 SAFE, 1 TIGHT, 3 AT_RISK under 14M ceiling; all code-bounded winner constants fit within budget; deity loop confirmed bounded at 32
- Complete gas ceiling analysis covering 18 paths (12 advanceGame + 6 purchase) with O(1) ticket queuing confirmation, master headroom table, and 4 INFO findings

---

## v3.3 Gambling Burn Audit + Full Adversarial Sweep (Shipped: 2026-03-21)

**Phases completed:** 6 phases, 15 plans, 30 tasks

**Key accomplishments:**

- 5 finding verdicts confirmed/refuted: 3 HIGH (CP-08 double-spend, CP-06 stuck claims, Seam-1 fund trap), 1 MEDIUM (CP-07 coinflip dependency), 1 INFO (CP-02 safe sentinel)
- Full redemption lifecycle trace (submit/resolve/claim) with period state machine proofs and burnWrapped supply invariant verification across StakedDegenerusStonk, DegenerusStonk, AdvanceModule, and BurnieCoinflip
- ETH/BURNIE accounting reconciliation with solvency proofs, 26-entry cross-contract interaction map, CEI verification for all entry points, and consolidated Phase 44 summary with 4 fixes-required ordered by severity
- Applied 4 Phase 44 confirmed fixes (3 HIGH, 1 MEDIUM) and resolved QueueDoubleBuffer compilation blocker for clean invariant test baseline
- RedemptionHandler with 4 actions (burn, advanceDay, claim, triggerGameOver), 11 ghost variables tracking all 7 redemption invariants, and multi-actor sDGNRS pre-distribution
- 7 invariant tests proving ETH solvency, no double-claim, period monotonicity, supply consistency, 50% cap, roll bounds, and aggregate tracking -- all passing at 256 runs x 128 depth
- 3-persona adversarial sweep of all 29 contracts: 4 deep (sDGNRS, DGNRS, BurnieCoinflip, AdvanceModule) + 25 quick delta sweep -- 0 new HIGH/MEDIUM findings, all Phase 44 fixes verified, 1 QA observation
- 13 cross-contract composability attack sequences tested SAFE with file:line evidence, plus 4 new entry point access controls verified CORRECT with immutable guard analysis
- Rational actor strategy catalog (4 strategies, all UNPROFITABLE/NEUTRAL) with ETH EV-neutral proof, BURNIE 1.575% house-edge derivation, and bank-run solvency proof under worst-case all-max-rolls scenario
- Variable liveness analysis confirming all 7 sDGNRS gambling burn variables ALIVE, with 3 storage packing opportunities saving up to 66,300 gas per call
- Foundry gas benchmark tests for 7 redemption functions with forge snapshot baseline (burn: 283K, claimRedemption: 309K, resolveRedemptionPeriod: 257K gas)
- Error rename (OnlyBurnieCoin to semantic names), VRF bit allocation map above rngGate, and full NatSpec verification across 6 changed files with CP-08/CP-06/Seam-1 traceability
- Updated 12 audit docs with v3.3 gambling burn findings (3H/1M fixed), PAY-16 payout path, RNG consumer addendum, design mechanics for wardens, and version stamps across all findings docs
- Corrected all stale line references across BIT ALLOCATION MAP, v3.3 addendum, and gas analysis document -- 60+ line numbers updated to match current source
- Activated ghost_totalBurnieClaimed with balance-delta tracking and added INV-07b monotonic boundedness invariant; verified all 7 gas benchmarks and 10 invariant tests pass

---

## v3.1 — Pre-Audit Polish — Comment Correctness + Intent Verification

**Completed:** 2026-03-19
**Phases:** 31-37 (7 phases, 16 plans)
**Timeline:** 1 day (2026-03-18 → 2026-03-19)
**Commits:** 46 | **Audit:** 11/11 requirements passed

- Full comment audit across all 29 protocol contracts (~25,000 lines): every NatSpec tag, inline comment, and block comment verified against current code behavior
- 84 findings produced (80 CMT + 4 DRIFT, 11 LOW + 73 INFO) — each with what/where/why/suggestion for C4A warden consumption
- 5 cross-cutting patterns identified: orphaned NatSpec from feature removal, stale BurnieCoin refs from coinflip split, post-Phase-29 NatSpec gaps, onlyCoin naming ambiguity, error reuse without documentation
- Post-Phase-29 code changes independently verified (keep-roll tightening, future dump removal, burn deadline shift, level-0 guard simplification)
- Consolidated findings deliverable with severity index, master summary table, and per-contract grouping

---

## v2.1 — VRF Governance Audit + Doc Sync

**Completed:** 2026-03-18
**Phases:** 24-25 (2 phases, 12 plans)
**Timeline:** 12 days (2026-03-05 → 2026-03-17)
**Commits:** 42 | **Audit:** 33/33 requirements passed

- 26 governance security verdicts: storage layout, access control, vote arithmetic, reentrancy, cross-contract interactions, war-game scenarios
- M-02 closure: emergencyRecover eliminated, severity downgraded Medium→Low
- 6 war-game scenarios assessed (compromised admin, cartel voting, VRF oscillation, timing attacks, governance loops, spam-propose)
- Post-audit hardening: CEI fix in _executeSwap, removed unnecessary death clock pause + activeProposalCount
- All audit docs synced for governance: zero stale references after full grep sweep

---

## v1.0 — Initial RNG Security Audit

**Completed:** 2026-03-14
**Phases:** 1-5

- RNG storage variable audit
- RNG function audit
- RNG data flow audit
- Manipulation window analysis
- Ticket selection deep dive

## v1.1 — Economic Flow Audit

**Completed:** 2026-03-15
**Phases:** 6-15

- 13 reference documents covering all economic subsystems
- State-changing function audits for all contracts
- Parameter reference consolidation
- Known issues documentation

## v1.2 — RNG Security Audit (Delta)

**Completed:** 2026-03-15
**Phases:** 16-18

- Delta attack reverification after code changes
- New attack surface analysis
- Impact assessment

## v1.3 — sDGNRS/DGNRS Split + Doc Sync

**Completed:** 2026-03-16
**Phases:** N/A (implementation, not audit)

- Split DegenerusStonk into StakedDegenerusStonk + DegenerusStonk wrapper
- Pool BPS rebalance, coinflip bounty tightening, degenerette DGNRS rewards
- All 10 audit docs updated for new architecture

## v2.0 — C4A Audit Prep

**Completed:** 2026-03-17
**Phases:** 19-23

- Delta security audit of sDGNRS/DGNRS split
- Correctness verification (docs, comments, tests)
- Novel attack surface deep creative analysis
- Warden simulation + regression check
- Gas optimization and dead code removal
