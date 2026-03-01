---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-03-01T13:09:14.978Z"
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 52
  completed_plans: 43
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-28)

**Core value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor can extract value beyond what the game mechanics intend.
**Current focus:** Phase 2 — Core State Machine and VRF Lifecycle

## Current Position

Phase: 2 of 9 (Core State Machine and VRF Lifecycle)
Plan: 6 of 6 in current phase (02-01, 02-02, 02-03, 02-04, 02-05, 02-06 complete)
Status: Executing
Last activity: 2026-03-01 — Completed 02-04 FSM transition graph audit (FSM-01/FSM-03 PASS)

Progress: [██░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 7
- Average duration: 5min
- Total execution time: 32min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | 4min | 2min |
| 02 | 5 | 27min | 5min |

**Recent Trend:**
- Last 5 plans: 01-02 (2min), 01-04 (2min), 02-03 (5min)
- Trend: stable

*Updated after each plan completion*
| Phase 02 P04 | 7min | 2 tasks | 1 files |
| Phase 02 P05 | 4min | 2 tasks | 1 files |
| Phase 02 P02 | 6min | 2 tasks | 1 files |
| Phase 02 P03 | 5min | 2 tasks | 1 files |
| Phase 01 P04 | 2min | 2 tasks | 1 files |
| Phase 01 P03 | 3min | 2 tasks | 1 files |
| Phase 03a P05 | 3min | 2 tasks | 1 files |
| Phase 03a P04 | 3min | 2 tasks | 1 files |
| Phase 03c P06 | 3min | 1 tasks | 1 files |
| Phase 03c P05 | 3min | 1 tasks | 1 files |
| Phase 03c P03 | 5min | 1 tasks | 1 files |
| Phase 03b P06 | 5min | 2 tasks | 1 files |
| Phase 03c P02 | 3min | 1 tasks | 1 files |
| Phase 03a P01 | 4min | 2 tasks | 1 files |
| Phase 03c P01 | 4min | 1 tasks | 1 files |
| Phase 03b P04 | 5min | 2 tasks | 1 files |
| Phase 03b P05 | 5min | 2 tasks | 1 files |
| Phase 03b P03 | 6min | 2 tasks | 1 files |
| Phase 03a P02 | 6min | 2 tasks | 1 files |
| Phase 03c P04 | 4min | 1 tasks | 1 files |
| Phase 03b P01 | 7min | 2 tasks | 1 files |
| Phase 03a P03 | 4min | 2 tasks | 1 files |
| Phase 03b P02 | 8min | 2 tasks | 1 files |
| Phase 03a P07 | 12min | 2 tasks | 1 files |
| Phase 05 P04 | 3min | 1 tasks | 1 files |
| Phase 05 P03 | 4min | 1 tasks | 1 files |
| Phase 05 P01 | 5min | 1 tasks | 1 files |
| Phase 05 P02 | 5min | 1 tasks | 1 files |
| Phase 05 P05 | 3min | 1 tasks | 1 files |
| Phase 05 P06 | 4min | 1 tasks | 1 files |
| Phase 05 P07 | 9min | 1 tasks | 1 files |
| Phase 06 P03 | 3min | 1 tasks | 1 files |
| Phase 06 P02 | 4min | 1 tasks | 1 files |
| Phase 06 P06 | 4min | 1 tasks | 1 files |
| Phase 06 P07 | 4min | 1 tasks | 1 files |
| Phase 06 P04 | 4min | 1 tasks | 1 files |
| Phase 06 P05 | 6min | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Init]: Full protocol scope (22 contracts) — cross-contract interactions are where bugs hide
- [Init]: Validator-level threat model — strongest realistic attacker for on-chain game
- [Init]: Findings report without code fixes — assessment first, fixes separately
- [Phase 01]: Used dual grep patterns (visibility-keyword + precise type-visibility-name) for defense-in-depth source scanning
- [Phase 01]: STOR-04 PASS: TESTNET_ETH_DIVISOR has zero occurrences in mainnet contracts/
- [Phase 02]: Both VRF V2.5 checklist deviations (18h re-requesting, no VRFConsumerBaseV2Plus) are well-justified with equivalent security
- [Phase 02]: Lootbox RNG index 0 unreachable by design (1-based indexing with defense-in-depth guard)
- [Phase 02]: _threeDayRngGap duplication is identical and correct but creates future maintenance risk
- [Phase 02]: Static opcode analysis sufficient for VRF callback gas measurement given ~85% headroom margin
- [Phase 02]: Coordinator rotation revert against stale fulfillment is correct defensive behavior, not a vulnerability
- [Phase 02]: Non-standard xorshift constants (7,9,8) accepted as safe; VRF seed quality dominates PRNG properties for <30 iterations
- [Phase 02]: FSM-02 rated PASS conditional due to two theoretical edge cases at intersection of multiple simultaneous failures
- [Phase 02]: RNG-06 rated unconditional PASS -- liveness timeout serves as ultimate escape valve clearing rngLockedFlag even with ADMIN key loss
- [Phase 02]: Intra-transaction VRF-before-lock ordering classified as Informational (not exploitable with async Chainlink VRF V2.5)
- [Phase 02]: FSM-01 PASS: All 7 legal transitions enumerated; 7 illegal transitions proved unreachable
- [Phase 02]: FSM-03 PASS: Multi-step game-over handles all intermediate states; VRF 3-day historical fallback ensures completion
- [Phase 02]: LOW finding FSM-F02: handleGameOverDrain receives stale dailyIdx, may skip BAF/Decimator distribution (funds preserved for final sweep)
- [Phase 03a]: MATH-02 PASS: Deity pass T(n) overflow impossible -- max intermediate value 53 orders of magnitude below uint256 max
- [Phase 03a]: Saw-tooth price pattern (0.24->0.04 at x00->x01) documented as intentional game design
- [Phase 03a]: price state variable (AdvanceModule) and PriceLookupLib are independent pricing systems -- Informational, not a defect
- [Phase 03c]: MATH-08 PASS: All 9 mintPacked_ fields verified correct across 32 setPacked and 34 read sites; three INFORMATIONAL doc findings only
- [Phase 03a]: INPT-01 through INPT-04 all PASS: no input validation gaps across MintModule, JackpotModule, EndgameModule
- [Phase 03c]: MATH-07 PASS conditional: base coinflip range [50,150] correct; presale/EV adjustments exceeding 150% are intentional separate mechanics
- [Phase 03c]: Lootbox boon stale timestamps are deliberate gas optimization; _decEffectiveAmount L565 guard is dead code (defense-in-depth); Decimator bucket validation externalized to coin contract
- [Phase 03b]: DOS-03 PASS: All trait-related iteration bounded by explicit caps; worst-case ~13M gas within 30M block limit
- [Phase 03b]: deityPassOwners actual cap is 32 (symbol ID uniqueness), not 24 (DEITY_PASS_MAX_TOTAL is boon-eligibility only); Informational
- [Phase 03c]: PRICING-F01: lazyPassBoonDiscountBps is dead code (never written non-zero anywhere in codebase)
- [Phase 03c]: All pricing formulas (whale/lazy/deity) arithmetically safe -- max boon discount 5000 BPS, no overflow at boundary values
- [Phase 03a]: MATH-01 PASS: Ticket cost formula max product ~1.03e27, 50 orders below uint256 max; lootbox BPS split remainder provably non-negative
- [Phase 03a]: All 15 unchecked blocks in MintModule individually verified safe; affiliate rakeback confirmed BURNIE-only (no ETH pool impact)
- [Phase 03c]: F01 HIGH: Whale bundle lacks level eligibility guard -- NatSpec says levels 0-3/x49/x99 but code allows any level at 4 ETH; needs design confirmation
- [Phase 03c]: F02 MEDIUM: _currentMintDay vs _simulatedDayIndex inconsistency in whale vs lazy pass boon validity checks
- [Phase 03b]: MATH-06 PASS: No bet timing creates advantaged positions; commit-reveal pattern is sound
- [Phase 03b]: futurePrizePool cannot reach 0 through degenerette payouts (geometric decay with 10% cap converges to 1 wei)
- [Phase 03b]: DOS-02 PASS: Daily ETH cursor system griefing-resistant -- all writes within delegatecall chain, deterministic resume, unitsBudget=1000 constant
- [Phase 03b]: MATH-05 PASS: No activity score creates guaranteed positive-EV extraction exceeding investment cost; 3.5 ETH max benefit per level at 135% EV with 10 ETH raw-input cap
- [Phase 03b]: Cap tracks raw input (not benefit delta) -- confirmed conservative design, 2.86x faster depletion than benefit-tracking alternative
- [Phase 03b]: Only deity pass holders (24+ ETH) can reach 305% activity / 135% EV; non-deity max is 265% / ~129% EV
- [Phase 03a]: DOS-01 PASS: All 32 loops in JackpotModule bounded by explicit constants or gas budgets
- [Phase 03a]: consolidatePrizePools verified wei-exact via subtraction-remainder conservation proof
- [Phase 03a]: JackpotModule vs EndgameModule _addClaimableEth functionally equivalent despite different claimablePool update patterns
- [Phase 03c]: Hero boost integer rounding (max 0.005% deviation) rated Informational -- always rounds against player, not exploitable
- [Phase 03c]: ETH pool cap per-spin enforcement means worst-case 10-spin extraction is 65% of pool (geometric decay), not 100%
- [Phase 03c]: Activity score max 30500 BPS matches ACTIVITY_SCORE_MAX_BPS constant exactly -- no uncapped component
- [Phase 03b]: openBurnieLootBox intentionally bypasses EV multiplier -- hardcoded 80% rate is always sub-neutral, no cap bypass
- [Phase 03b]: Boon fallback DEITY_BOON_ACTIVITY_50 (line 1269) confirmed unreachable dead code via weight consistency proof across all 16 flag combinations
- [Phase 03b]: BURNIE low-path actual range is 58.08-129.63% (not 58-134% as documented) -- Informational documentation discrepancy
- [Phase 03a]: Level 50 BAF 25% bonus is one-time only (not every 50th level) -- classified as design intent
- [Phase 03a]: DOS-01 PASS for EndgameModule: all loops bounded (106 BAF winners max, 100 ticket range)
- [Phase 03a]: Dual _addClaimableEth implementations diverge in claimablePool management but both correct -- maintenance risk documented
- [Phase 03b]: GO-F01 MEDIUM: double refund possible via refundDeityPass + handleGameOverDrain at level 0
- [Phase 03b]: deityPassOwners bounded by symbolId<32 (max 32), not DEITY_PASS_MAX_TOTAL=24
- [Phase 03b]: MATH-05 terminal settlement: PASS conditional on GO-F01 assessment
- [Phase 03a]: Slither 0.11.5: 17 HIGH all FALSE POSITIVE (uninitialized-state on delegatecall storage), 60 MEDIUM all triaged (57 FP, 3 INFO)
- [Phase 03a]: Aderyn unavailable (Rust 1.89 required, system has 1.86); Slither coverage sufficient
- [Phase 03a]: Static analysis confirms all 9 Phase 3a requirement PASSes; no contradictions with manual audit
- [Phase 05]: ECON-04 PASS: rngLockedFlag set atomically with price update eliminates all sandwich windows; step-function pricing has zero price impact; per-level pool isolation eliminates cross-level arbitrage
- [Phase 05]: Deity pass frontrunning rated INFORMATIONAL (24+ ETH commitment, one-per-address, 32-pass cap, no profitable exit)
- [Phase 05]: ECON-03 PASS: affiliate rewards are BURNIE mints (not ETH transfers), circular referral pairs structurally negative-sum
- [Phase 05]: Weighted winner roll determinism classified Informational: EV-preserving, max +24% single-tx variance, irrelevant for sybil sets
- [Phase 05]: ECON-01 PASS: All 6 prize channels at most proportional to ticket ownership; BAF leaderboard sub-proportional; activity score dilution penalizes splitting
- [Phase 05]: Lootbox per-account cap expansion via multi-account splitting is irrelevant -- total lootbox volume bounded by total deposit, not account count
- [Phase 05]: ECON-02 PASS: No activity score inflation vector produces cost-to-inflate less than EV-benefit-unlocked; quest streak cheapest at 0.25 ETH/100 days
- [Phase 05]: ECON-05 PASS: Block proposer's only lever is WHEN (delay by 12s), not WHAT -- all outcomes deterministic from VRF word + game state; rawFulfillRandomWords does NOT clear rngLockedFlag
- [Phase 05]: ECON-06 PASS: Whale bundle extraction model proves no level produces extractable value exceeding deposit; F01 level guard absence economically benign (constant 4.50x nominal face value at all levels 10+)
- [Phase 05]: ECON-07 PASS: Three-layer protection (settleFlipModeChange, rngLockedFlag, 5-level lock) prevents all double-spend/double-credit windows in afKing mode transitions
- [Phase 05]: ECON-07-F01 INFORMATIONAL: Level 0 afKing activation bypasses 5-level lock (no economic impact)
- [Phase 06]: AUTH-02 PASS: rawFulfillRandomWords coordinator check first statement, msg.sender preserved through delegatecall, all update paths dual-gated
- [Phase 06]: AUTH-01 PASS: All admin functions correctly gated; DegenerusAdmin dual-owner model safe for vault-owner callers
- [Phase 06]: Vault ownership threshold (balance*10 > supply*3) verified correct, overflow-safe, manipulation-resistant
- [Phase 06]: setLootboxRngThreshold rated LOW: no upper bound allows temporary stall but no fund extraction
- [Phase 06]: AUTH-04 PASS: operator delegation is non-escalating, non-extractive, and immediately revocable across all 5 consumer contracts
- [Phase 06]: AUTH-06 PASS: No external caller can grief VRF subscription management; vault owner coordinator rotation is accepted trust assumption
- [Phase 06]: subscriptionId uint64 truncation in DegenerusAdmin rated Informational (safe with current Chainlink ID range)
- [Phase 06]: AUTH-03 PASS: All 43 external functions across 10 modules either gated or harmless on direct call; DecimatorModule claimDecimatorJackpot reverts DecNotWinner
- [Phase 06]: AUTH-05 PASS: All 32 _resolvePlayer call sites across 6 contracts route value to resolved player; no operator extraction vectors

### Pending Todos

None yet.

### Blockers/Concerns

- [RESOLVED by 02-01]: Nudge window timing — whether `rngLockedFlag` covers the full window between VRF fulfillment and `advanceGame` word consumption is the highest-risk open question; pass/fail determines if a critical finding exists
- [Research flag]: Medusa Hardhat ESM compatibility — verify `--build-system hardhat` flag works before fuzzing campaigns; fall back to Echidna if crytic-compile integration fails
- [Research flag]: stETH cached balance (Phase 4) — presence or absence of cached `steth.balanceOf(this)` in state variables is unconfirmed until code inspection

## Session Continuity

Last session: 2026-03-01
Stopped at: Completed 06-07-PLAN.md (DegenerusAdmin VRF subscription griefing resistance -- AUTH-06 PASS)
Resume file: None
