# Feature Landscape: v3.0 Full Contract Audit + Payout Specification

**Domain:** Comprehensive smart contract security audit (all value-transfer paths) + payout specification deliverable for C4A competitive audit
**Researched:** 2026-03-17
**Confidence:** HIGH (based on full codebase review, 87 prior audit plans, established C4A methodology, and industry-standard audit deliverables)

---

## Table Stakes

Audit coverage and deliverables every C4A-targeting audit must include. Missing any of these means a warden will find it first.

### GAMEOVER Path Audit (Critical Priority)

The GAMEOVER path is the highest-severity audit target because it is the terminal ETH distribution event -- all remaining protocol funds flow through it exactly once, with no ability to retry if logic is wrong.

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| Terminal jackpot distribution correctness (lvl+1 targeting) | Wrong level = wrong winners get all remaining ETH. Wardens always check terminal distribution. | High | v1.1 endgame docs, JackpotModule audit | `handleGameOverDrain` targets `lvl+1`, not `level`. Only next-level ticketholders win. Must verify this is enforced in both the jackpot call AND the bucket selection logic. |
| Deity pass refund ordering and budget cap (levels 0-9) | FIFO refund of 20 ETH/pass could exceed available funds or skip passes. Off-by-one in owner iteration = stuck funds. | Med | v1.1 deity system docs | Budget = `totalFunds - claimablePool`. Loop iterates `deityPassOwners.length`. Must verify purchased count vs owner count, budget exhaustion break, and claimablePool update after refunds. |
| Decimator 10% allocation and refund recycling | Terminal decimator gets 10%, refund flows back to terminal jackpot. Wrong accounting = fund leak or stuck ETH. | Med | v1.1 transition jackpots docs, terminal decimator plan | `decRefund` returned from `runTerminalDecimatorJackpot`, added back to `remaining`. Must verify no double-counting with `claimablePool += decSpend`. |
| Final sweep mechanics (30-day forfeiture) | All unclaimed winnings forfeited. 50/50 vault/sDGNRS split. Wrong timing = premature or impossible sweep. | Med | -- | `block.timestamp < gameOverTime + 30 days` guard. `finalSwept` latch. `claimablePool = 0` before fund distribution. Verify stETH priority ordering in `_sendToVault`. |
| Death clock stage transitions (normal/imminent/distress/gameOver) | Wrong stage = premature GAMEOVER or missed distress bonuses. Timing boundaries at 120d/5d/6h. | Med | v1.1 endgame docs | Level 0 uses 365-day timeout. Level 1+ uses 120-day from `levelStartTime`. Distress bonus is proportional (only tickets bought during distress get 25% boost). |
| RNG fallback for dead-VRF GAMEOVER | If VRF is dead when GAMEOVER fires, jackpot needs entropy. Historical VRF word fallback after 3-day wait. | High | v1.0 RNG audit, v1.2 RNG deep dive | `_getHistoricalRngFallback` combines early VRF words + `currentDay` + `block.prevrandao`. Must verify validator influence is bounded (1-bit propose/skip). |
| gameOver flag permanence and state cleanup | `gameOver = true` must be irreversible. Pool variables zeroed. No re-entry to game functions post-gameOver. | Low | State-changing function audit | `gameOverTime`, `gameOverFinalJackpotPaid`, `finalSwept` -- three latch variables. Verify no reset path. |
| _sendToVault stETH/ETH split correctness | stETH transfer priority, ETH fallback. 50/50 split between vault and sDGNRS. Rounding in `amount / 2`. | Med | -- | Vault gets stETH first (transfer), sDGNRS gets stETH via approve+depositSteth. ETH fallback for remainder. Verify no value leak at the stETH/ETH boundary. |

### Payout/Claim Path Audits (All 17+ Systems)

Each distribution system is an independent value-transfer path that wardens audit for stuck funds, value leaks, and incorrect recipients.

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| Daily jackpot ETH distribution (purchase phase) | 1% futurePool daily drip. 25% as ETH to trait winners, 75% as lootbox tickets. Wrong split or wrong winners = value leak. | Med | v1.1 purchase-phase distribution docs | Verify BPS split (2500/7500), winner selection from trait matching, bounded winner count (`DAILY_ETH_MAX_WINNERS`). |
| 5-day jackpot phase draws (Days 1-5) | Core prize distribution. Days 1-4: 6-14% random slice, 4 trait buckets. Day 5: 100% remainder, weighted split. | High | v1.1 jackpot-phase draws docs | Most complex distribution in the protocol. 50%/150%/78-115% payout multiplier tiers. 25/15/8/1 winners per bucket (scaled 1-6.67x). Must verify bucket isolation, multiplier tier boundaries, and remainder handling. |
| BAF payout distribution (every 10 levels) | 10% futurePool (20% at L50, x00). Complex prize split: top BAF bettor, top coinflip bettor, random 3rd/4th, far-future ticketholders, scatter. | High | v1.1 transition jackpots docs | 7 independent distribution buckets. 50 sampling rounds for scatter. Large winners get 50% ETH / 50% lootbox. Must verify no double-spending across buckets and that `baseFuturePool` snapshot is used consistently. |
| Decimator payout (every 10 levels offset by 5) | Pro-rata based on BURNIE burned. Multiplier tiers up to 200k cap. Bucket/sub-bucket VRF selection. | High | v1.1 transition jackpots docs | Level 95 exclusion (`lvl % 100 != 95`). x00 decimator uses `baseFuturePool` (30%), normal uses post-BAF `futurePoolLocal` (10%). Claim expiry when next decimator resolves. |
| Terminal decimator (GAMEOVER-only) | Always-open death bet. Time-weighted BURNIE burns. 10% of remaining GAMEOVER funds. | High | PLAN-TERMINAL-DECIMATOR.md | NEW CODE -- highest priority for audit. Verify: time multiplier correctness, 200k cap enforcement, lazy reset on level change, bucket aggregate accounting, claim window (GAMEOVER to final sweep). |
| Coinflip mechanics (BURNIE wager) | 50/50 odds, ~1.97x payout, ~1.575% house edge. Losses permanently burn BURNIE. | Med | v1.1 coinflip docs | Verify payout tier boundaries, burn-on-loss permanence, vault drain protection, bounty DGNRS gating (50k bet, 20k pool minimums). |
| Coinflip bounty (daily BURNIE accumulator) | 1,000 BURNIE/day accumulates, 50% to coinflip winner. DGNRS-gated (50k min bet, 20k pool). Separate value-transfer path from regular coinflip. | Low | v1.1 coinflip docs, v2.0 DELTA-05 | Already audited in v2.0 (DELTA-05: 8 gating conditions, 3 constants). Verify no regression. Payout spec must cover as distinct system. |
| Lootbox resolution (EV based on activity score) | 58-590% of purchase value (random tier). Activity score drives EV from 80% (0 score) to 135% (25.5k). 2x over-collateralization. | Med | v1.1 endgame docs, v1.1 level-progression docs | Verify EV curve breakpoints, 2x over-collat math, lootbox ticket crediting to correct pools. |
| Quest rewards (daily streak system) | Slot 0: mandatory MINT_ETH, 100 BURNIE. Slot 1: weighted random, 200 BURNIE. Streak up to 100 days. | Low | v1.1 quest rewards docs | Verify streak increment/reset logic, quest type selection weights, BURNIE mint authorization. |
| Affiliate rewards (3-tier referral) | Direct: 25% (L0-3) / 20% (L4+) / 5% recycled. Upline1: 20% of direct. Upline2: 4% of direct. | Med | v1.1 affiliate system docs | All rewards credited as coinflip stakes via `creditFlip()`. Activity taper on lootbox (25-100% based on 10K-25.5K score range). DGNRS claim: 5% of affiliate pool per level (sequential depletion, not reserved). |
| stETH yield distribution (per level transition) | 23% sDGNRS claimable, 23% vault claimable, 46% accumulator, ~8% buffer. x00 release: 50% accumulator to futurePool. | Med | v1.1 stETH yield docs | Verify payout ordering (players get ETH first, vault/sDGNRS get stETH first). stETH 1-2 wei rounding error handling. Accumulator monotonicity. |
| Deity pass refunds (early GAMEOVER) | 20 ETH/pass, levels 0-9 only, FIFO, budget-capped. | Med | v1.1 deity system docs | Covered under GAMEOVER path above. Cross-reference here for completeness. |
| Whale bundle DGNRS distribution (PPM-based) | 1% of whale pool per bundle purchase. PPM scale (1,000,000), not BPS (10,000). | Low | v1.1 dgnrs tokenomics docs | PPM vs BPS confusion is a known agent pitfall. Verify correct scale in whale bundle math. |
| Degenerette bet resolution | 0.01 ETH min bet. ROI 90-110% based on activity score. 10% pool cap on ETH payouts. | Med | v1.1 endgame docs | Activity score is the fulcrum. Verify pool cap enforcement, ETH vs lootbox payout split, bet limits. |
| sDGNRS burn-for-backing | Proportional claim on `(ethBal + stethBal + claimable) * burnAmount / totalSupply`. | Med | v2.0 delta audit (DELTA-01 through DELTA-08) | Either token can burn. DGNRS burn delegates to sDGNRS.burn(). Verify no value extraction via timing between preview and execution. |
| BURNIE ticket purchases | 1,000 BURNIE burned per ticket. Virtual ETH calculated, no actual ETH enters. | Low | v1.1 burnie supply docs | Verify virtual ETH contribution to pools is correctly calculated and that no actual ETH is moved. |
| Earlybird DGNRS distribution | 10% of total sDGNRS supply to early players. Dumps to lootbox pool when earlybird target met. | Low | v2.0 delta audit (DELTA-07) | Already audited in v2.0. Verify no regression from recent code changes. |
| WWXRP prize minting and unwrap | Joke token. `mintPrize()` mints unbacked WWXRP. `unwrap()` gives wXRP on FCFS basis. No collateralization guarantee. | Low | -- | Simple ERC20 with CEI (burn before transfer). Low value-at-risk. Include in payout spec for completeness. Verify `mintPrize` authorization and `unwrap` drain safety. |
| DegenerusVault share redemption | Vault holders redeem shares for ETH/stETH proportionally. Floor division prevents extraction. | Low | v1.0 ACCT-06 | Already audited. Verify no regression. Include in payout spec. |
| claimWinnings pull-pattern withdrawal | CEI pattern. Sentinel value. stETH fallback when ETH insufficient. | Low | State-changing function audit (48 entry points verified) | Already thoroughly audited. Verify no regression. |

### Recent Changes Verification

Changes since v2.1 that have not been individually audited yet.

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| VRF governance integration verification | Verify governance code changes from v2.1 have not introduced regressions in any payout path | Low | v2.1 governance audit (26 verdicts) | Already audited at code level. This is regression-check, not new audit. |
| Terminal decimator code (NEW) | Entirely new code path -- storage, time multiplier, burn flow, resolution, claims | High | PLAN-TERMINAL-DECIMATOR.md | Not yet implemented at time of audit planning. Must be audited from scratch when code lands. |
| Deity pass non-transferability (soulbound) | DeityPass ERC-721 `transferFrom`, `safeTransferFrom` all revert. Soulbound enforcement must be verified. | Low | v1.1 deity system docs | Recent change. All transfer functions are `pure` and revert unconditionally. Verify no bypass via `approve` + operator pattern. Include in payout spec as security property. |
| Death clock pause removal | `activeProposalCount`-based death clock pause removed post-v2.1. VOTE-03 uint8 overflow now moot. | Low | v2.1 post-audit hardening | Verify removal is clean -- no dangling references to `anyProposalActive()` in game-over paths. |
| `_executeSwap` CEI fix | `_voidAllActive` moved before external calls (GOV-07 fix). | Low | v2.1 post-audit hardening | Verify the fix does not break execution semantics (voiding before external call means no reentrant proposal interaction). |

### Comment and Documentation Correctness

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| NatSpec accuracy across all contracts | Incorrect NatSpec is a QA finding in C4A. Wardens submit these as bulk QA reports. | Med | All prior audits | Systematic sweep of all 24 deployable contracts. Check every `@notice`, `@dev`, `@param`, `@return` against actual code behavior. |
| Inline comment correctness | Stale comments after code changes mislead wardens and developers. | Med | v2.1 doc sync | Especially check comments in modified files: BurnieCoin.sol, DegenerusGame.sol, DecimatorModule.sol, GameOverModule.sol, GameStorage.sol. |
| Storage layout documentation | Storage slot documentation must match compiler output exactly. | Low | v2.1 GOV-01 (slot 114 verified) | Verify new terminal decimator storage (if added) is correctly positioned and documented. |
| Constants and parameter reference | Parameter reference doc must include all new constants from terminal decimator and any post-v2.1 changes. | Low | v1.1 parameter reference | Append new constants. Verify no stale values from prior versions. |

### Invariant Verification

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| claimablePool solvency: `balance + stETH >= claimablePool` | Core solvency invariant. If violated, players cannot withdraw. 16 mutation sites identified in prior audit. | High | v1.0 ACCT-01 through ACCT-10 | Re-verify across ALL mutation sites including new terminal decimator paths. This invariant is the protocol's heartbeat. |
| Pool accounting: `futurePrizePool + nextPrizePool + currentPrizePool` conservation | Value must not leak between pools or to nowhere. Every pool transition must be accounted. | Med | v1.1 pool architecture docs | Trace every pool write across AdvanceModule, MintModule, EndgameModule, GameOverModule. |
| sDGNRS supply invariant: `sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply` | Wrapper must never have more supply than backing. Cross-contract supply conservation. | Med | v2.0 DELTA-03 | 6 modification paths identified in v2.0 audit. Re-verify no new paths from terminal decimator or governance changes. |
| BURNIE supply: `totalSupply + vaultAllowance = supplyIncUncirculated` | 6 authorized mint paths. No free-mint path. | Low | v1.0 ACCT-07 | Verify terminal decimator burn path does not break supply accounting. |
| Unclaimable funds: no ETH permanently stuck | Every ETH entering the protocol must have a path to exit (claim, sweep, burn-for-backing, vault). | High | All prior audits | This is what wardens look for hardest. Enumerate every entry path and trace to an exit. The 30-day final sweep is the backstop. |

### Edge Case and Griefing Analysis

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| GAMEOVER at level 0 | Edge case: 365-day timeout at level 0. No level transitions have occurred. Terminal jackpot targets level 1 with no next-level tickets purchased. | High | -- | If no tickets exist at level 1, terminal jackpot has no winners. All funds go to final sweep (30 days). Verify this path handles gracefully (no division by zero, no stuck funds). |
| GAMEOVER at level 1-9 (early, with deity refunds) | Deity refund budget could exceed available funds. FIFO ordering matters. | Med | -- | Budget = `totalFunds - claimablePool`. If insufficient for all deity refunds, later purchases get nothing. Verify no underflow. |
| GAMEOVER at x00 level (after 50% futurePool drain) | BAF + Decimator already consumed 50% of futurePool at the last transition. Terminal funds may be much smaller than expected. | Med | -- | Not a bug, but wardens will model this scenario. Document expected behavior. |
| Single-player GAMEOVER | Only one player exists. All distributions go to one address. Winner selection with pool of 1. | Low | -- | Verify no division-by-zero when bucket has 1 ticket. Verify claim aggregation works with single address. |
| Gas griefing on GAMEOVER distribution | Large number of deity pass owners in refund loop. Many ticketholders in terminal jackpot. | Med | -- | `deityPassOwners.length` bounded at 32 (max deity passes). Terminal jackpot uses chunked processing. Verify gas bounds. |
| Rounding in BPS/PPM splits | Remainder pattern used throughout. Dust routed to `futurePrizePool`. | Low | v1.0 MATH-03 | Already verified. Re-confirm no new remainder leaks in terminal decimator code. |
| Timing attacks on death clock extension | Purchase during distress resets `levelStartTime`. Strategic timing to extend/shorten death clock. | Med | v1.1 endgame docs | Safety valve: if purchase target met during distress, clock resets. Verify no manipulation where clock is extended infinitely or reset is missed. |
| Terminal decimator: level reset during burn window | Player burns BURNIE for terminal decimator, then level advances (burns are total loss). Lazy reset must correctly zero state. | Med | PLAN-TERMINAL-DECIMATOR.md | `burnLevel != lvl` triggers reset. Verify no stale aggregates persist across level boundaries. |

---

## Differentiators

Features that separate this audit from a baseline pass. These are what make C4A wardens unable to find anything new.

### Payout Specification Document (HTML)

The single most impactful deliverable for C4A preparation. No competitor audit produces this. It makes every distribution system visually traceable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Complete payout specification covering all 17+ distribution systems** | Single document a C4A warden can read to understand every ETH/stETH/BURNIE/DGNRS flow. Eliminates "I didn't understand the protocol" as a finding source. | High | HTML format with embedded diagrams, code references, and invariant annotations. Self-contained (no external dependencies). |
| **Per-system flow diagrams** | ASCII or SVG diagrams showing exact fund flow: entry point, BPS splits, pool movements, exit points. | Med | One diagram per distribution system. Consistent visual language across all 17+ systems. |
| **Exact code references for every distribution** | Every BPS constant, every pool write, every claim path traced to `file:line`. | Med | Makes wardens' job easier (they verify your references rather than discovering paths). Reduces false positives. |
| **Invariant annotations per system** | Each distribution system annotated with its conservation invariant and the mutation sites that could violate it. | Med | Cross-references ACCT-01 through ACCT-10 from prior audit. |
| **Edge case documentation per system** | Per-system: what happens at boundary conditions (zero funds, single winner, max winners, rounding). | Med | Preempts warden "what if?" submissions. |
| **Token flow matrix** | Single table showing which tokens (ETH, stETH, BURNIE, sDGNRS, DGNRS, WWXRP) flow through which systems, in which directions, and which contracts they touch. | Low | Quick reference for wardens to verify coverage completeness. |

### Cross-System Interaction Audit

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Pool transition atomicity verification** | At level advance, `futurePool -> nextPool -> currentPool -> claimablePool`. Verify no intermediate state is observable by external callers. | Med | All transitions happen within single delegatecall. But `stakeExcessEth` (admin) could theoretically interleave. Verify admin timing. |
| **Concurrent claim + GAMEOVER race** | Player claims winnings while GAMEOVER distribution is processing. claimablePool being written by both paths simultaneously. | Med | CEI should prevent this (single-threaded EVM), but verify no cross-transaction race where partial GAMEOVER state + claim creates inconsistency. |
| **stETH rebase during multi-step GAMEOVER** | stETH balance changes between deity refund calculation and terminal jackpot distribution due to Lido rebase. | Low | stETH rebases are continuous. `steth.balanceOf()` reads are live. Verify total funds calculation is consistent within the GAMEOVER transaction. |
| **BURNIE supply integrity across payout paths** | 6 mint paths + coinflip burns + decimator burns + BURNIE ticket burns. Verify supply accounting holds across all concurrent operations. | Med | Cross-reference ACCT-07. Especially verify terminal decimator BURNIE burns are properly reflected in supply tracking. |

### War-Game Scenario Expansion

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **10K ETH whale GAMEOVER manipulation** | Whale buys maximum tickets at level N+1, then forces GAMEOVER by abstaining from purchases. All terminal funds flow to them. | High | This is BY DESIGN (forward-looking players rewarded). Document as known economic property, not vulnerability. Verify that one whale cannot prevent others from also buying level N+1 tickets. |
| **Coordinated GAMEOVER timing attack** | Group of players times purchases to trigger distress mode exactly when they want, then stops purchasing to trigger GAMEOVER. | Med | Death clock is 120 days from last level advance. Players cannot accelerate it, only extend it via purchases. Verify no mechanism to artificially accelerate GAMEOVER. |
| **Terminal decimator early-conviction cartel** | Group burns BURNIE at high time multiplier (120 days remaining, 30x). If GAMEOVER fires, they dominate payout. If level completes, total loss. | Med | BY DESIGN (risk/reward tradeoff). Verify that the 200k cap prevents monopolization and that bucket selection provides fair distribution. |

---

## Anti-Features

Audit work to explicitly NOT include. Including these wastes time or produces findings that are already known/documented.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Re-audit VRF randomness from scratch** | Already completed in v1.0 (10 requirements PASS) and v1.2 (deep dive with manipulation windows). 0 findings. | Reference v1.0/v1.2 findings. Only audit NEW VRF-adjacent code (terminal decimator resolution, GAMEOVER fallback). |
| **Re-audit delegatecall safety from scratch** | 46/46 sites verified in prior phases. Zero deviations from safe pattern. | Reference prior findings. Only audit NEW delegatecall sites (if any added for terminal decimator). |
| **Re-audit governance from scratch** | 26 verdicts in v2.1, 3 known issues documented. | Reference v2.1 verdicts. Only verify recent post-v2.1 changes (CEI fix, death clock pause removal, activeProposalCount removal). |
| **Flash loan attack analysis** | No AMM pool for sDGNRS (soulbound). DGNRS has no price oracle. BURNIE has no flash loan target. Structurally impossible. | One-line note in known properties. |
| **Formal verification of all arithmetic** | Path explosion makes Halmos/SMT infeasible for 16,500 lines. Deferred to v3.1+. | Document as limitation. Rely on remainder-pattern proofs and fuzz testing. |
| **Gas optimization beyond correctness** | C4A QA gas findings are low-value. Phase 23 already performed dead code removal. | Reference Phase 23 results. Only flag new gas issues that affect correctness (e.g., unbounded loops that could hit block gas limit). |
| **Frontend or off-chain infrastructure audit** | Not in scope. No smart contract security impact. | Explicitly state as out of scope in payout specification. |
| **Testnet-specific behavior analysis** | `TESTNET_ETH_DIVISOR = 1,000,000` makes testnet findings non-transferable. | Audit mainnet logic only. Note divisor as a testnet artifact. |
| **Comprehensive Monte Carlo simulation of game outcomes** | Deferred to v3.1+. Not needed for security audit. | Document as future work. Current audit covers invariant verification, which is sufficient for security. |
| **Re-audit ERC20 compliance of DGNRS/sDGNRS** | Already covered in v2.0 delta audit (DELTA-01 through DELTA-08). | Reference v2.0 findings. Only check for regressions in modified files. |

---

## Feature Dependencies

```
v1.0-v2.1 Audit Foundation (87 plans, 90 requirements)
    |
    +-- v1.0 RNG audit (10 requirements) --------> GAMEOVER RNG fallback trust
    |
    +-- v1.1 Economic flow (13 reference docs) --> Every payout system's specification basis
    |
    +-- v1.2 RNG deep dive ----------------------> Manipulation window analysis
    |
    +-- v2.0 Delta audit (8 requirements) -------> sDGNRS/DGNRS supply invariants
    |
    +-- v2.0 Warden simulation (3 agents) -------> Known attack surface baseline
    |
    +-- v2.1 Governance audit (26 verdicts) -----> Cross-contract interaction patterns
    |
    +-- State-changing function audit -----------> CEI patterns for all 48 entry points
    |
    v
v3.0 Full Contract Audit (this milestone)
    |
    +-- GAMEOVER Path Audit
    |     Depends on: endgame docs, JackpotModule, GameOverModule, RNG fallback
    |     Produces: Terminal distribution correctness proof
    |
    +-- Payout/Claim Path Audits (17+ systems)
    |     Depends on: v1.1 economic flow docs (all 13), pool architecture
    |     Produces: Per-system invariant verification
    |
    +-- Terminal Decimator Audit (NEW CODE)
    |     Depends on: PLAN-TERMINAL-DECIMATOR.md, existing decimator audit
    |     Produces: New code security verification
    |
    +-- Invariant Verification (cross-cutting)
    |     Depends on: ALL prior ACCT requirements, ALL payout path audits
    |     Produces: Global solvency proof
    |
    +-- Edge Case & Griefing Analysis
    |     Depends on: GAMEOVER path audit, payout path audits
    |     Produces: Boundary condition documentation
    |
    +-- Payout Specification HTML Document
    |     Depends on: ALL payout path audits (provides verified content)
    |     Produces: Single deliverable for C4A wardens
    |
    +-- Comment & Documentation Correctness
    |     Depends on: ALL other audit work (must be last -- comments must reflect final code)
    |     Produces: QA-clean codebase
    |
    v
C4A Submission Ready
    |
    +-- KNOWN-ISSUES.md updated with all v3.0 findings
    +-- FINAL-FINDINGS-REPORT.md updated with v3.0 coverage
    +-- Payout Specification HTML document complete
    +-- Parameter reference updated with new constants
```

---

## MVP Recommendation

### Phase 1: GAMEOVER + Terminal Decimator (Highest Risk)

Prioritize these because they involve the most ETH and the newest code:

1. **GAMEOVER path audit** -- Terminal distribution of ALL remaining protocol funds. One bug here = Critical finding.
2. **Terminal decimator audit** -- Entirely new code. No prior audit coverage. High complexity (time multiplier, bucket aggregates, lazy reset).
3. **Death clock and distress mode verification** -- Guards the GAMEOVER trigger. Wrong timing = premature or impossible GAMEOVER.

### Phase 2: Payout Path Audits (Systematic Coverage)

Cover every distribution system, ordered by complexity and ETH at risk:

4. **5-day jackpot phase draws** -- Most complex distribution. Multiple buckets, multiplier tiers, winner scaling.
5. **BAF distribution** -- 7 independent distribution buckets. Scatter sampling. 50 rounds.
6. **Decimator payout** -- Pro-rata with multiplier tiers. Bucket/sub-bucket VRF selection. Claim expiry.
7. **Daily jackpot, coinflip, lootbox, affiliate, stETH yield, quest rewards, bounties** -- Medium complexity, well-documented.
8. **Degenerette, whale DGNRS, BURNIE tickets, earlybird, WWXRP, vault redemption, claimWinnings** -- Lower complexity, prior audit coverage exists.

### Phase 3: Invariants + Edge Cases + Cross-System

9. **claimablePool solvency invariant** -- Re-verify across ALL mutation sites including new paths.
10. **Pool accounting conservation** -- Full pool transition trace.
11. **Edge case matrix** -- GAMEOVER at level 0, single player, x00 level, etc.
12. **Recent changes verification** -- Deity non-transferability, governance regression, death clock pause removal.

### Phase 4: Payout Specification Document

13. **Payout specification HTML** -- Depends on all prior phases for verified content.

### Phase 5: Documentation Correctness + Final Sync

14. **NatSpec sweep** -- All 24 contracts.
15. **Comment correctness** -- Modified files from v2.1+.
16. **KNOWN-ISSUES.md and FINAL-FINDINGS-REPORT.md updates** -- Include v3.0 findings.

### Defer to v3.1+

- **Foundry fuzz invariant tests for governance** -- Valuable but not blocking C4A submission.
- **Formal verification via Halmos** -- Infeasible for this codebase size.
- **Monte Carlo simulation** -- Not needed for security audit.

---

## C4A Severity Context

Understanding C4A severity criteria drives audit prioritization. Per C4A standardized severity:

| C4A Severity | Definition | What Wardens Look For in This Protocol |
|--------------|------------|----------------------------------------|
| **High** | Assets can be stolen/lost/compromised directly | Stuck ETH in GAMEOVER, claimablePool insolvency, terminal jackpot going to wrong recipients, unclaimable deity refunds |
| **Medium** | Function of protocol impacted, or value leak with hypothetical attack path | Rounding accumulation in high-frequency paths, pool accounting drift over many levels, timing attacks on death clock, BURNIE supply inflation via edge case |
| **QA (Low + NC)** | Assets not at risk, code quality | NatSpec inaccuracies, stale comments, event emission gaps, redundant checks, naming inconsistencies |

The payout specification document directly reduces warden findings by:
1. Eliminating "protocol not documented" QA findings
2. Making intended behavior explicit (wardens cannot claim design choices as bugs)
3. Providing exact code references (wardens verify rather than discover)
4. Documenting known edge cases (preempts "what if?" submissions)

---

## Sources

- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/PROJECT.md` -- v3.0 milestone definition
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/FINAL-FINDINGS-REPORT.md` -- 87 plans, 90 requirements, severity distribution
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/KNOWN-ISSUES.md` -- Known issues and design notes
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/v1.1-ECONOMICS-PRIMER.md` -- All 13 economic subsystem references
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/v1.1-endgame-and-activity.md` -- Death clock and terminal distribution
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/v1.1-transition-jackpots.md` -- BAF and decimator mechanics
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/v2.1-governance-verdicts.md` -- 26 governance verdicts
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameGameOverModule.sol` -- Terminal distribution code
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusDeityPass.sol` -- Soulbound deity pass (transfer functions revert)
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/WrappedWrappedXRP.sol` -- Joke token with unbacked minting
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/PLAN-TERMINAL-DECIMATOR.md` -- Terminal decimator spec
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/research/FEATURES.md` (v2.1) -- Prior governance audit features (template reference)
- [Code4rena severity standardization](https://medium.com/code4rena/severity-standardization-in-code4rena-1d18214de666) -- C4A severity criteria (MEDIUM confidence -- paywalled, verified via search summaries)
- [OpenZeppelin audit readiness guide](https://learn.openzeppelin.com/security-audits/readiness-guide) -- Pre-audit documentation requirements (HIGH confidence)
- [Cyfrin audit methodology](https://www.cyfrin.io/blog/10-steps-to-systematically-approach-a-smart-contract-audit) -- 10-step systematic audit approach (HIGH confidence)
- [Hacken smart contract audit process](https://hacken.io/discover/smart-contract-audit-process/) -- Audit preparation and fund flow analysis (MEDIUM confidence)
