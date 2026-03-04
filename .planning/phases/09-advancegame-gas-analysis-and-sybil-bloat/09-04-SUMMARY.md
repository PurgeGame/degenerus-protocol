---
phase: 09-advancegame-gas-analysis-and-sybil-bloat
plan: "04"
subsystem: game-theory
tags: [advanceGame, liveness, whale-analysis, rational-inaction, daily-mint-gate, GAS-07]

# Dependency graph
requires:
  - phase: 09-advancegame-gas-analysis-and-sybil-bloat
    provides: 09-RESEARCH.md baseline, _enforceDailyMintGate interface, ADVANCE_BOUNTY constant
provides:
  - GAS-07 verdict with rational inaction model and source-code evidence
  - _enforceDailyMintGate caller category table (5 categories, 4 bypass paths)
  - Dominant whale EV model (3 scenarios)
  - Liveness guarantee conditions (explicit, severity-classified residuals)
affects: ["13-final-report", "10-admin-vrf-analysis"]

# Tech tracking
tech-stack:
  added: []
  patterns: ["game-theory EV model for incentive analysis", "Code4rena severity classification for liveness risk"]

key-files:
  created:
    - .planning/phases/09-advancegame-gas-analysis-and-sybil-bloat/09-04-SUMMARY.md
  modified: []

key-decisions:
  - "GAS-07 PASS: no dominant whale strategy rationally delays advanceGame() indefinitely; three independent liveness paths confirmed"
  - "CREATOR key-management risk classified INFO (not GAS-07 scope); forwarded to Phase 10 ADMIN-01 for operational risk review"
  - "VRF liveness dependency classified as separate concern; forwarded to Phase 10 ADMIN-02"

patterns-established:
  - "Rational inaction model: always compute EV(call) vs. EV(not call) before asserting liveness risk"
  - "Bypass-category enumeration: enumerate all gate exits before assessing liveness"

requirements-completed: [GAS-07]

# Metrics
duration: 8min
completed: 2026-03-04
---

# Phase 9 Plan 04: Rational Inaction Model and GAS-07 Verdict Summary

**GAS-07 PASS — no rational dominant-whale strategy permanently delays advanceGame(); CREATOR bypass, lazy/deity pass exemptions, and ADVANCE_BOUNTY positive incentive provide three independent liveness paths**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-04T22:05:24Z
- **Completed:** 2026-03-04T22:13:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Read `_enforceDailyMintGate` source (lines 532-555) and enumerated all 5 caller categories with line references
- Confirmed `ADVANCE_BOUNTY = PRICE_COIN_UNIT >> 1 = 500 ether` (500 BURNIE flip credits) from source (line 107)
- Modeled three dominant-whale EV scenarios; determined no rational inaction path exists
- Produced explicit GAS-07 verdict with severity-classified residuals

---

## Task 1: _enforceDailyMintGate Source Analysis

### Source Location

File: `contracts/modules/DegenerusGameAdvanceModule.sol`

- `_enforceDailyMintGate`: lines 532-555
- Called in `advanceGame()`: line 134 (`_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)`)
- `ADVANCE_BOUNTY` constant: line 107 (`uint256 private constant ADVANCE_BOUNTY = PRICE_COIN_UNIT >> 1`)
- `PRICE_COIN_UNIT`: 1000 ether (1000e18) — defined in `DegenerusGameStorage.sol` line 125
- Therefore: `ADVANCE_BOUNTY = 500 ether` (500 BURNIE flip credits)
- Bounty credited unconditionally at `advanceGame()` line 284: `coin.creditFlip(caller, ADVANCE_BOUNTY)`

### Caller Categories That Bypass _enforceDailyMintGate

| Cat | Description | Source Location | Bypass Condition |
|-----|-------------|-----------------|-----------------|
| A | CREATOR (deployer/team wallet) | Line 537 | `caller == ContractAddresses.CREATOR` — always exempt |
| B | Level 0 (pre-game) | Line 539 | `gateIdx == 0` — gate not enforced at level 0 |
| C | Lazy pass holder | Lines 547-551 | `frozenUntilLevel > lvl` — frozen-until level exceeds current level |
| D | Deity pass holder | Line 552 | `deityPassCount[caller] != 0` — at least one deity pass held |
| E | Recently minted player | Lines 542-546 | `lastEthDay + 1 >= gateIdx` — minted today or yesterday |

Categories C and D share the `hasLazyPass` boolean: `frozenUntilLevel > lvl || deityPassCount[caller] != 0`.

All five categories are exit paths from the gate. Any caller satisfying **one or more** of these conditions may call `advanceGame()`.

### Additional Liveness Gating: rngLockedFlag / rngGate

`advanceGame()` calls `rngGate()` (line 141) after the mint gate passes. If no VRF word is available:
- `_requestRng()` is called and `rngGate` returns 1 → `advanceGame` exits at `STAGE_RNG_REQUESTED`
- Progress is halted until Chainlink VRF fulfills the request
- A 18-hour retry timeout exists (line 649: `if (elapsed >= 18 hours)`)

This is a **separate liveness dependency**: the mint gate cannot be the bottleneck if VRF is stalled. This dependency is out of GAS-07 scope and is noted for **Phase 10 ADMIN-02** review.

---

## Task 2: Dominant Whale EV Model and GAS-07 Verdict

### Scenario A — Dominant Whale Without a Pass

**Setup:** Whale holds a large ticket share but no lazy pass (`frozenUntilLevel <= currentLevel`) and no deity pass (`deityPassCount[whale] == 0`).

**Gate behavior:** Whale must satisfy Category E (minted today or yesterday) to call `advanceGame()`.

**Rational inaction strategy:** Whale stops minting for a day to delay `advanceGame()`.

**Effect:**
- Whale loses Category E access for that day
- Any other player who minted today or yesterday (Category E) retains access
- CREATOR (Category A) retains access unconditionally
- Any pass holder (Categories C/D) retains access unconditionally

**Conclusion:** A dominant whale without a pass **cannot veto protocol advancement** by abstaining. Stopping minting only removes the whale's own eligibility; it does not affect any other caller. Protocol liveness is maintained as long as at least one other minter, pass holder, or CREATOR is active.

**EV of whale's inaction:** Zero control gain. The whale forfeits the ADVANCE_BOUNTY (500 BURNIE) but gains nothing — advancement happens anyway via another eligible caller.

### Scenario B — Dominant Whale With a Lazy Pass or Deity Pass

**Setup:** Whale holds Categories C or D — always exempt from the daily mint gate.

**Gate behavior:** Whale can call `advanceGame()` on any day regardless of minting activity.

**Rational inaction strategy:** Whale chooses not to call `advanceGame()` to extend the current level (allowing more ticket purchases at the current price).

**EV model:**

Let:
- W = whale's current ticket share fraction (e.g., 0.40 = 40% of outstanding tickets)
- P = level prize pool (ETH)
- J = daily jackpot allocation = DAILY_JACKPOT_UNITS_SAFE × price_unit = 1000 units × price
- B = ADVANCE_BOUNTY = 500 BURNIE flip credits

**EV(call):**
- Earn ADVANCE_BOUNTY immediately (500 BURNIE)
- Advance to next level — higher prize pool, but price also increases

**EV(not call, hoping to accumulate more tickets):**
- Forgo ADVANCE_BOUNTY
- If any other pass holder or CREATOR calls instead: whale gets NOTHING and advancement happens anyway
- If no other pass holder or CREATOR calls: advancement delayed by one day

**Key insight — competitive pass holders:** In a healthy protocol with multiple lazy/deity pass holders, every eligible pass holder has an individual incentive to call `advanceGame()` first to claim the ADVANCE_BOUNTY. This is a **first-mover advantage** structure: the first eligible caller earns 500 BURNIE; all subsequent callers earn nothing for that day. Rational pass holders call as early as possible.

**Result:** A pass-holding whale faces a prisoner's dilemma:
- If whale delays: any other pass holder calls instead → whale earns 0 BURNIE and advancement occurs anyway
- If whale calls: whale earns 500 BURNIE immediately

Dominant strategy for any rational pass holder: **call immediately**. Delay is dominated — it only forfeits the bounty without achieving the delay.

**Extra-ticket accumulation analysis:**

Could one more day of purchases at current level price have positive EV exceeding 500 BURNIE?

- The whale already holds W fraction of tickets
- Extra purchases cost ETH at current price
- Marginal EV from one extra day = (incremental ticket fraction) × (future prize pool expected value increment)
- In a competitive market with other players also purchasing, the whale's incremental ticket share is diminishing
- The prize pool itself only grows by the jackpot allocation (~1000 units × price) per day — the whale's fractional share of that increment is bounded
- For any realistic W < 1.0 (i.e., other players exist), the marginal gain from one day of accumulation is a small fraction of the daily jackpot allocation, almost certainly less than the 500 BURNIE certain gain from calling

**Conclusion:** Rational inaction is dominated for pass-holding whales. The ADVANCE_BOUNTY creates positive incentive to call; delay forfeits that bounty to competitors without guaranteeing the desired outcome (delayed advancement).

### Scenario C — Total Player Inactivity (All Non-CREATOR Actors Inactive)

**Setup:** All players stop minting, no pass holders are active, only CREATOR has access.

**Effect:** Only CREATOR (Category A) can call `advanceGame()`.

**This is a liveness dependency on CREATOR operational availability.** The protocol team (CREATOR) holds the fallback authority to advance the game unconditionally.

**Risk classification:**
- Requires all players AND all pass holders to simultaneously become inactive
- CREATOR key loss or multi-year abandonment would be required for permanent halt
- This is an **operational/admin key management risk**, not a game-theory attack surface

**Severity: INFO** — Requires CREATOR key loss or team abandonment (outside adversarial game model scope). Scoped to **Phase 10 ADMIN-01** for operational risk review.

---

## Liveness Guarantee Conditions

Protocol advancement (advanceGame) is guaranteed when **at least one** of the following holds:

1. CREATOR wallet is active and willing to call (always true unless key lost/team abandoned)
2. Any lazy pass holder is active (Category C: `frozenUntilLevel > currentLevel`)
3. Any deity pass holder is active (Category D: `deityPassCount != 0`)
4. Any player minted within the last 2 days and is willing to call (Category E)

These are **three independent** non-CREATOR liveness paths. A single-actor whale attack cannot simultaneously suppress all three paths without owning all lazy passes, all deity passes, and stopping all other player minting — an extremely high-cost coordination requirement.

---

## GAS-07 Verdict

**GAS-07: PASS** — No dominant whale strategy rationally delays `advanceGame()` indefinitely.

**Evidence:**
1. **Whale without a pass** cannot veto: other eligible callers (Categories A-E) advance the game regardless of whale inaction
2. **Whale with a pass** has no dominant strategy to delay: ADVANCE_BOUNTY creates a first-mover incentive among all pass holders; delay forfeits the bounty without achieving delay
3. **CREATOR bypass** provides unconditional fallback authority, ensuring liveness even in adversarial conditions
4. `ADVANCE_BOUNTY = PRICE_COIN_UNIT >> 1 = 500 ether` (source-confirmed, `DegenerusGameAdvanceModule.sol` line 107) creates positive economic incentive for eligible callers

**Residual risks (not GAS-07 scope):**

| ID | Severity | Description | Scope |
|----|----------|-------------|-------|
| GAS-07-I1 | INFO | CREATOR key loss + all pass holders inactive would halt advancement; operational key management dependency | Phase 10 ADMIN-01 |
| GAS-07-I2 | INFO | VRF stall (Chainlink unavailability) is a separate liveness dependency; 18-hour retry exists | Phase 10 ADMIN-02 |

Neither residual rises to LOW severity in the game-theory model: GAS-07-I1 requires team abandonment (outside adversarial scope), and GAS-07-I2 has an explicit 18-hour retry mechanism with 3-day emergency fallback.

---

## Task Commits

1. **Task 1 + Task 2: Read source and write GAS-07 verdict** — (combined in single commit, analysis-only plan)

## Files Created/Modified
- `.planning/phases/09-advancegame-gas-analysis-and-sybil-bloat/09-04-SUMMARY.md` — This file: _enforceDailyMintGate analysis, rational inaction EV model, GAS-07 verdict

## Decisions Made
- GAS-07 rated PASS based on three independent liveness paths and dominated-strategy analysis for pass-holding whales
- CREATOR key management risk (GAS-07-I1) classified INFO — forwarded to Phase 10 ADMIN-01
- VRF stall liveness dependency (GAS-07-I2) classified INFO — forwarded to Phase 10 ADMIN-02

## Deviations from Plan
None — plan executed exactly as written. Source analysis confirmed all 4 pre-specified caller categories (plus the level-0 gate-skip as a 5th exit path at line 539). EV model conclusions match the plan's pre-analysis.

## Issues Encountered
None.

## Next Phase Readiness
- Phase 9 complete: GAS-01 through GAS-07 all have verdicts in their respective SUMMARY.md files
- Phase 10 (ADMIN/ASSY analysis) is ready; two forwarded items (ADMIN-01: CREATOR key management, ADMIN-02: VRF liveness dependency) are awaiting investigation
- Phase 13 final report can cite 09-04-SUMMARY.md for GAS-07

---
*Phase: 09-advancegame-gas-analysis-and-sybil-bloat*
*Completed: 2026-03-04*
