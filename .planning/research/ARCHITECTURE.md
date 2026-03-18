# Architecture: v3.0 Full Contract Audit + Payout Specification

**Domain:** Smart contract security audit integration + payout specification document
**Researched:** 2026-03-17
**Confidence:** HIGH (all source artifacts directly inspected, all contract code reviewed)

---

## 1. Audit Scope: Value-Transfer Surface Map

The v3.0 audit covers every code path that moves ETH, stETH, BURNIE, DGNRS, sDGNRS, or WWXRP. This is the complete value-transfer surface across 23 contracts.

### 1a. ETH Exit Points (10 total)

| Location | Function | Destination | Trigger |
|----------|----------|-------------|---------|
| DegenerusGame.sol:1993 | `_payoutWithStethFallback` | Player (ETH-first) | claimWinnings |
| DegenerusGame.sol:2010 | `_payoutWithStethFallback` | Player (ETH leftover) | claimWinnings fallback |
| DegenerusGame.sol:2031 | `_payoutWithEthFallback` | Player (ETH fallback) | claimWinningsStethFirst |
| GameOverModule.sol:210 | `_sendToVault` | Vault | GAMEOVER final sweep |
| GameOverModule.sol:227 | `_sendToVault` | sDGNRS | GAMEOVER final sweep |
| MintModule.sol:760 | vault share send | Vault | Purchase (creator share) |
| DegenerusVault.sol:1043 | `_sendEth` | Player | Vault redemption |
| DegenerusStonk.sol:176 | `burn` | Player | DGNRS burn for ETH/stETH |
| StakedDegenerusStonk.sol:437 | `burn` | Player | sDGNRS burn for ETH/stETH |
| MockVRFCoordinator.sol:42 | (mock only) | N/A | Test infrastructure |

### 1b. stETH Transfer Points (11 total)

| Location | Function | Direction | Trigger |
|----------|----------|-----------|---------|
| DegenerusGame.sol:1834 | `_adminStethTransfer` | Game -> recipient | Admin stETH transfer |
| DegenerusGame.sol:1974 | `_payoutWithStethFallback` | Game -> sDGNRS (approve+deposit) | Vault/sDGNRS claim |
| DegenerusGame.sol:1978 | `_payoutWithStethFallback` | Game -> player | stETH fallback |
| GameOverModule.sol:201 | `_sendToVault` | Game -> Vault | GAMEOVER sweep |
| GameOverModule.sol:205 | `_sendToVault` | Game -> Vault (partial) | GAMEOVER sweep |
| GameOverModule.sol:218-223 | `_sendToVault` | Game -> sDGNRS (approve+deposit) | GAMEOVER sweep |
| DegenerusStonk.sol:173 | `burn` | sDGNRS -> player | DGNRS burn |
| StakedDegenerusStonk.sol:292 | `depositSteth` | depositor -> sDGNRS | stETH deposit |
| StakedDegenerusStonk.sol:433 | `burn` | sDGNRS -> player | sDGNRS burn |
| DegenerusVault.sol:1051 | `_sendSteth` | Vault -> player | Vault redemption |
| DegenerusVault.sol:1059 | `_receiveSteth` | Game -> Vault | Vault deposit |

### 1c. Token Transfer Points

| Token | Contract | Key Functions |
|-------|----------|---------------|
| BURNIE | BurnieCoin.sol | `_burn`, `_mint`, `mintForCoinflip`, `mintForGame`, `_consumeCoinflipShortfall` |
| sDGNRS | StakedDegenerusStonk.sol | `transferFromPool` (5 pools), `burnRemainingPools`, `_distributionMint` |
| DGNRS | DegenerusStonk.sol | standard ERC20 `transfer`/`transferFrom`, `wrapFrom`/`unwrapTo` |
| WWXRP | WrappedWrappedXRP.sol | `vaultMintTo`, standard ERC20 transfers |
| DGVE/DGVB | DegenerusVault.sol | `deposit` (share minting), `redeem` (share burning) |

---

## 2. Six Priority Audit Areas and Their Dependencies

### Dependency Graph

```
                 GAMEOVER PATH (Area 1)
                      |
          +-----------+-----------+
          |                       |
   Payout/Claim Paths      Recent Changes
      (Area 2)               (Area 3)
          |                       |
          +-----------+-----------+
                      |
            Invariant Verification
                  (Area 4)
                      |
          +-----------+-----------+
          |                       |
   Comment Correctness      Edge Cases
      (Area 5)               (Area 6)
```

### Area 1: GAMEOVER Path (CRITICAL -- highest fund concentration)

**What it covers:**
- `handleGameOverDrain()` in GameOverModule -- terminal distribution of ALL remaining funds
- `handleFinalSweep()` -- 30-day forfeiture sweep
- Death clock three-stage escalation (imminent -> distress -> GAMEOVER)
- RNG fallback for dead VRF at GAMEOVER
- Terminal decimator 10% allocation and claim path (NEW -- uncommitted code)
- Terminal jackpot 90% allocation to next-level ticketholders
- Deity pass refund (20 ETH/pass, levels 0-9, FIFO, budget-capped)
- `_sendToVault` 50/50 split (vault + sDGNRS), stETH-first ordering
- `burnRemainingPools()` on sDGNRS

**Why first:** This is where ALL remaining protocol funds converge into a single code path. A bug here means total loss. The terminal decimator is new code (uncommitted) that directly modifies this path.

**Dependencies:** None -- this is the root of the audit.

**Contracts touched:** GameOverModule, GameStorage, AdvanceModule (death clock), DecimatorModule (terminal decimator), JackpotModule (terminal jackpot), StakedDegenerusStonk (burnRemainingPools), DegenerusAdmin (shutdownVrf).

### Area 2: Payout/Claim Paths (HIGH -- every user-facing withdrawal)

**What it covers (17+ distribution systems):**

| System | Entry Point | Payout Type |
|--------|-------------|-------------|
| Daily jackpot (5 draws) | JackpotModule._distributeJackpotEth | ETH to claimableWinnings |
| Regular decimator | DecimatorModule.claimDecimatorJackpot | ETH + lootbox tickets |
| Terminal decimator | DecimatorModule.claimTerminalDecimatorJackpot | ETH only (NEW) |
| BAF jackpot | DegenerusJackpots.runBafJackpot | ETH + lootbox tickets |
| Coinflip claim | BurnieCoinflip.claimCoinflips | BURNIE |
| Coinflip take-profit | BurnieCoinflip.claimCoinflipsTakeProfit | BURNIE |
| Lootbox opening | LootboxModule | Future tickets + BURNIE |
| Quest rewards | DegenerusQuests (via BurnieCoin) | BURNIE |
| Affiliate ETH | JackpotModule via _addClaimableEth | ETH to claimableWinnings |
| Affiliate DGNRS | DegenerusGame.claimAffiliateDgnrs | sDGNRS from Affiliate pool |
| stETH yield | AdvanceModule yield surplus | Pool amplification at x00 |
| Deity refunds | GameOverModule | ETH to claimableWinnings |
| Whale pass claim | EndgameModule.claimWhalePass | Whale bundle purchase |
| Auto-rebuy | PayoutUtils._calcAutoRebuy | Tickets for future levels |
| Degenerette payout | DegeneretteModule | ETH to claimableWinnings |
| ETH claim (pull) | DegenerusGame.claimWinnings | ETH (stETH fallback) |
| stETH-first claim | DegenerusGame.claimWinningsStethFirst | stETH (ETH fallback) |
| Vault redemption | DegenerusVault.redeem | ETH + stETH |
| sDGNRS burn | StakedDegenerusStonk.burn | ETH + stETH |
| DGNRS burn | DegenerusStonk.burn | ETH + stETH (via sDGNRS) |
| WWXRP mint | DegenerusVault.vaultMintTo | WWXRP |
| Bounties | EndgameModule BAF/Dec bounties | BURNIE via BurnieCoin |

**Why second:** Each path must be individually verified, and Area 1 delegates to several of these. Understanding GAMEOVER first gives context for how terminal paths differ from normal gameplay paths.

**Dependencies:** Area 1 establishes the terminal context. Payout paths during normal gameplay operate independently.

### Area 3: Recent Changes Verification

**What it covers:**
- VRF governance (DegenerusAdmin rewrite) -- already audited in v2.1, verify no regressions
- Terminal decimator (NEW uncommitted code) -- 490 lines across 7 files
- Deity non-transferability -- verify still enforced
- Post-v2.1 hardening -- CEI fix, death clock pause removal, activeProposalCount removal
- Any parameter changes since last audit

**Why third:** Recent changes are where bugs live. New code has not been adversarially tested. The terminal decimator touches 7 files including the critical GAMEOVER path.

**Dependencies:** Areas 1-2 provide the baseline understanding of what the code should do. Area 3 verifies that recent modifications do not break those expectations.

### Area 4: Invariant Verification

**What it covers:**

| Invariant | Description | Mutation Sites |
|-----------|-------------|----------------|
| Solvency | `address(this).balance + steth.balanceOf(this) >= claimablePool` | All 16+ credit/debit sites |
| claimablePool accounting | Every `claimableWinnings[x] += y` has matching `claimablePool += y` | All payout modules |
| sDGNRS supply | `sum(pool balances) + sum(holder balances) == totalSupply` | transferFromPool, _distributionMint, burnRemainingPools |
| BURNIE mint/burn | Only `onlyTrustedContracts` can mint; no free-mint path | mintForCoinflip, mintForGame |
| Pool BPS conservation | All pool BPS splits sum to 10,000 | MintModule purchase splits |
| Unclaimable funds | `finalSwept` gates all claims; 30-day window | GameOverModule, DegenerusGame |

**Why fourth:** Invariants are the mathematical backbone. Verifying them after understanding all paths (Areas 1-3) is more effective than trying to verify in isolation.

**Dependencies:** Areas 1-3 must map all mutation sites before invariant verification can be exhaustive.

### Area 5: Comment and Documentation Correctness

**What it covers:**
- NatSpec accuracy on all state-changing functions (already audited for many in state-changing-function-audits.md -- verify new/changed functions)
- Inline comment accuracy (especially in terminal decimator new code)
- Storage layout comments in DegenerusGameStorage.sol
- Constants in parameter reference vs actual code values
- `EXTERNAL-AUDIT-PROMPT.md` accuracy after new changes

**Why fifth:** Comment correctness matters for C4A auditors who will read documentation. But comments cannot be wrong if you have not first established what the code actually does (Areas 1-4).

**Dependencies:** Areas 1-4 establish ground truth. Area 5 compares documentation against that truth.

### Area 6: Edge Cases and Griefing Analysis

**What it covers:**
- GAMEOVER at level 0 (365-day timeout, no deity refunds -- level < 10 check applies)
- GAMEOVER at levels 1-9 (deity refund fires, limited pool size)
- Single player scenario (one ticketholder gets everything)
- Gas griefing in `handleGameOverDrain` (large deityPassOwners array)
- Timing attacks (last-second burns before GAMEOVER)
- Rounding in terminal decimator weighted burns (uint80/uint88 precision)
- Auto-rebuy during GAMEOVER (gameOver=true prevents rebuy in `_addClaimableEth`)
- stETH rounding at GAMEOVER (strengthens invariant but verify)
- Terminal decimator with 0 participants (no burns for current level)
- Decimator bucket edge cases (bucket=2 with single player)

**Why last:** Edge cases are combinatorial. They require deep understanding of all 5 prior areas to reason about correctly. Starting here without full system knowledge produces speculative rather than verified findings.

**Dependencies:** All prior areas.

---

## 3. Recommended Phase Structure

### Phase 26: GAMEOVER Path Audit (Area 1)

```
26-01: handleGameOverDrain full trace
       - Deity refund loop: FIFO ordering, budget cap, claimablePool update
       - Terminal decimator 10% allocation: runTerminalDecimatorJackpot call
       - Terminal jackpot 90%: runTerminalJackpot call
       - _sendToVault 50/50 split with stETH-first ordering
       - burnRemainingPools on sDGNRS
       - Zero-available early return (claimablePool >= totalFunds)

26-02: handleFinalSweep full trace
       - 30-day timer correctness
       - finalSwept latch preventing double-sweep
       - claimablePool zeroed (forfeiture)
       - shutdownVrf fire-and-forget (try/catch)
       - _sendToVault with full remaining balance

26-03: Death clock three-stage escalation
       - _handleGameOverPath in AdvanceModule
       - gameOverImminent flag (decimator burn window)
       - distressMode flag (lootbox 100% to nextPool, 25% ticket bonus)
       - VRF fallback: _getHistoricalRngFallback (3-day wait, 5 words + prevrandao)

26-04: Terminal decimator integration
       - runTerminalDecimatorJackpot: bucket selection, weighted burn shares, claim credits
       - claimTerminalDecimatorJackpot: winner verification, payout calculation
       - Storage: TerminalDecEntry packing (232/256 bits), TerminalDecClaimRound
       - Lazy reset on level change
       - recordTerminalDecBurn: time multiplier, cap enforcement, bucket assignment
```

### Phase 27: Payout/Claim Path Audit (Area 2)

```
27-01: ETH claim pipeline
       - claimWinnings / claimWinningsStethFirst / _claimWinningsInternal
       - 1-wei sentinel pattern
       - CEI: claimablePool decremented before external call
       - ETH-first vs stETH-first ordering
       - finalSwept gate

27-02: Jackpot distribution paths
       - Daily jackpot 5-draw system (JackpotModule._distributeJackpotEth)
       - Terminal jackpot (JackpotModule.runTerminalJackpot)
       - BAF jackpot (DegenerusJackpots.runBafJackpot)
       - _addClaimableEth with auto-rebuy logic (gameOver skips rebuy)

27-03: Decimator claim paths
       - Regular decimator: claimDecimatorJackpot, ETH + lootbox split
       - Terminal decimator: claimTerminalDecimatorJackpot, ETH only
       - Decimator bounty DGNRS gating
       - consumeDecClaim internal routing

27-04: Auxiliary payout systems
       - Coinflip claims (BurnieCoinflip: claimCoinflips, claimCoinflipsTakeProfit)
       - Affiliate DGNRS claims (claimAffiliateDgnrs, pool allocation, score denominator)
       - Whale pass claims (claimWhalePass, half-pass price, deferred queue)
       - Quest rewards (BURNIE credit via coinflip)
       - Degenerette payouts (_addClaimableEth in DegeneretteModule)

27-05: sDGNRS/DGNRS/Vault redemption paths
       - sDGNRS burn: ETH + stETH proportional
       - DGNRS burn: unwrap to sDGNRS then burn
       - Vault redeem: DGVE share redemption
       - stETH yield distribution at x00 milestones
```

### Phase 28: Recent Changes + Invariants (Areas 3-4)

```
28-01: Terminal decimator code review (490 new lines)
       - BurnieCoin.terminalDecimatorBurn entry point
       - DegenerusGame routing (terminalDecWindow, recordTerminalDecBurn)
       - DecimatorModule: recordTerminalDecBurn, time multiplier, resolution, claims
       - GameOverModule: runTerminalDecimatorJackpot call change
       - Interface additions (IDegenerusGame, IDegenerusGameModules)
       - Storage additions (TerminalDecEntry, mappings, TerminalDecClaimRound)

28-02: VRF governance regression check
       - Verify v2.1 changes still intact (propose/vote/execute, unwrapTo guard)
       - Post-v2.1 hardening (CEI fix, death clock pause removal, activeProposalCount removal)
       - Parameter reference accuracy for governance constants

28-03: Invariant verification
       - Solvency invariant across all 16+ mutation sites
       - claimablePool accounting (every credit has matching pool update)
       - sDGNRS supply conservation
       - BURNIE mint authority verification
       - Pool BPS sum to 10,000
       - Terminal decimator: weighted burn totals match individual entries
```

### Phase 29: Comments + Edge Cases (Areas 5-6)

```
29-01: Comment and documentation correctness
       - NatSpec on all new/changed functions (terminal decimator, GAMEOVER changes)
       - Storage layout comments in DegenerusGameStorage
       - Parameter reference cross-check for new constants
       - EXTERNAL-AUDIT-PROMPT update for terminal decimator

29-02: Edge case and griefing analysis
       - GAMEOVER scenarios at various levels (0, 1-9, 10+)
       - Single player, zero participants in terminal decimator
       - Gas griefing (deityPassOwners loop, large bucket arrays)
       - Timing attacks, rounding, stETH edge cases
       - Interaction between auto-rebuy and GAMEOVER state
```

### Phase 30: Payout Specification Document

```
30-01: PAYOUT-SPECIFICATION.html structure and core content
       - 17+ distribution systems documented with exact code references
       - ETH flow diagrams for each system
       - Pool accounting diagrams
       - Cross-references to existing audit docs

30-02: Payout specification completeness review
       - Verify all systems covered
       - Verify all code references are accurate
       - Verify diagrams match code
```

---

## 4. Integration with Existing Audit Documents

### 4a. Documents the v3.0 Audit Consumes (READ dependency)

| Document | What v3.0 Uses From It |
|----------|----------------------|
| `v1.1-ECONOMICS-PRIMER.md` | System overview, pool architecture, game structure |
| `v1.1-parameter-reference.md` | All constant values for verification |
| `v1.1-endgame-and-activity.md` | Death clock, terminal distribution, activity scores |
| `v1.1-transition-jackpots.md` | BAF and decimator trigger schedules, pool splits |
| `v1.1-jackpot-phase-draws.md` | Daily jackpot mechanics |
| `v1.1-steth-yield.md` | stETH payout ordering, yield surplus |
| `v1.1-deity-system.md` | Deity pass refund mechanics |
| `v1.1-affiliate-system.md` | Affiliate DGNRS claims |
| `v1.1-quest-rewards.md` | Quest BURNIE rewards |
| `v1.1-burnie-coinflip.md` | Coinflip claim mechanics |
| `v1.1-dgnrs-tokenomics.md` | sDGNRS pool structure, burn mechanics |
| `state-changing-function-audits.md` | Existing function-level audit verdicts |
| `FINAL-FINDINGS-REPORT.md` | Existing finding IDs, severity distribution |
| `KNOWN-ISSUES.md` | Known issues to cross-reference |
| `v2.1-governance-verdicts.md` | Governance audit results for regression check |

### 4b. Documents v3.0 May Update (WRITE dependency)

| Document | What Changes | Trigger |
|----------|-------------|---------|
| `FINAL-FINDINGS-REPORT.md` | New phase entries (26-30), updated scope, new findings if any | Always (new phases) |
| `KNOWN-ISSUES.md` | New known issues if terminal decimator audit reveals design tradeoffs | Only if findings |
| `state-changing-function-audits.md` | New entries for terminal decimator functions (terminalDecimatorBurn, recordTerminalDecBurn, terminalDecWindow, claimTerminalDecimatorJackpot, runTerminalDecimatorJackpot) | Always (new functions) |
| `v1.1-parameter-reference.md` | Terminal decimator constants (DECIMATOR_MULTIPLIER_CAP, time multiplier curve, bucket rules) | Always (new constants) |
| `EXTERNAL-AUDIT-PROMPT.md` | Terminal decimator in protocol overview | Always |

### 4c. New Documents Created by v3.0

| Document | Purpose | Created In |
|----------|---------|------------|
| `audit/PAYOUT-SPECIFICATION.html` | Comprehensive payout specification covering all 17+ distribution systems | Phase 30 |
| `audit/v3.0-gameover-audit.md` | GAMEOVER path audit findings | Phase 26 |
| `audit/v3.0-payout-paths-audit.md` | Payout/claim path audit findings | Phase 27 |
| `audit/v3.0-terminal-decimator-audit.md` | Terminal decimator code review | Phase 28-01 |
| `audit/v3.0-invariant-verification.md` | Invariant verification results | Phase 28-03 |

---

## 5. Payout Specification Architecture

### 5a. Document Structure

`audit/PAYOUT-SPECIFICATION.html` should be a standalone HTML document (no external dependencies beyond inline CSS) that covers every system paying out value to any address.

**Recommended sections:**

```
1. Overview
   - Total systems count
   - Token types (ETH, stETH, BURNIE, sDGNRS, DGNRS, WWXRP, DGVE, DGVB)
   - Pull vs push patterns

2. ETH Inflows (how ETH enters)
   - 9 purchase types with pool split BPS
   - Lido stETH yield

3. ETH Outflows (how ETH exits)
   - claimWinnings pipeline (ETH-first and stETH-first variants)
   - GAMEOVER distribution (deity refund + terminal decimator + terminal jackpot + sweep)
   - Vault redemption
   - sDGNRS/DGNRS burn

4. Per-System Payout Details (17+ systems)
   - For each: trigger, source pool, recipient, amount formula, claim window, code reference
   - Diagrams showing ETH flow from pool to player

5. Pool Accounting
   - currentPrizePool -> claimablePool transitions
   - claimableWinnings[address] credit/debit lifecycle
   - Pool BPS conservation proof

6. Terminal Distribution (GAMEOVER)
   - Three-stage death clock
   - handleGameOverDrain step-by-step
   - handleFinalSweep

7. Invariants
   - Solvency invariant
   - claimablePool <= balance + stETH
   - Supply conservation for each token
```

### 5b. How Payout Specification References Existing Docs

| Payout Spec Section | References |
|---------------------|------------|
| ETH Inflows | `v1.1-ECONOMICS-PRIMER.md` (pool splits), `v1.1-purchase-phase-distribution.md` |
| Daily Jackpots | `v1.1-jackpot-phase-draws.md` (5-draw system) |
| BAF/Decimator | `v1.1-transition-jackpots.md` (trigger schedule, pool percentages) |
| Coinflip | `v1.1-burnie-coinflip.md` (mechanics, bounty gating) |
| Affiliate | `v1.1-affiliate-system.md` (score, DGNRS allocation) |
| stETH Yield | `v1.1-steth-yield.md` (yield surplus, payout ordering) |
| Deity Refund | `v1.1-deity-system.md` (20 ETH/pass, FIFO) |
| Death Clock | `v1.1-endgame-and-activity.md` (three-stage escalation) |
| Quest Rewards | `v1.1-quest-rewards.md` (BURNIE credit) |
| Activity Score | `v1.1-endgame-and-activity.md` (score consumers: lootbox EV, degenerette ROI) |
| Constants | `v1.1-parameter-reference.md` (all BPS values, timing, caps) |
| DGNRS/sDGNRS | `v1.1-dgnrs-tokenomics.md` (pool structure, burn) |
| Findings | `FINAL-FINDINGS-REPORT.md` (relevant findings impacting payouts) |

The payout specification should **not duplicate** existing docs. It should reference them by filename and section, adding only the unified view that no single existing doc provides.

### 5c. Data Flow: Audit Findings -> Payout Specification

```
Phase 26 (GAMEOVER audit)
  |
  +--> Finding IDs (if any)
  +--> Verified GAMEOVER flow description
  |
Phase 27 (Payout paths audit)
  |
  +--> Per-system verified descriptions
  +--> Exact code references (file:line)
  |
Phase 28 (Invariants)
  |
  +--> Verified invariant statements
  +--> Mutation site inventory
  |
Phase 29 (Comments)
  |
  +--> Corrected descriptions where NatSpec was wrong
  |
  v
Phase 30 (Payout Specification)
  |
  Consumes all above to produce accurate, complete specification
```

The payout specification MUST be written last because it needs to reference verified (not assumed) behavior from phases 26-29. Writing it speculatively before the audit would risk encoding incorrect assumptions.

---

## 6. Component Boundaries

### 6a. Core Game (DegenerusGame.sol -- dispatcher)

| Responsibility | Delegates To |
|---------------|-------------|
| Purchase routing | MintModule |
| Level advancement | AdvanceModule |
| Jackpot distribution | JackpotModule |
| Lootbox mechanics | LootboxModule |
| Decimator burns/claims | DecimatorModule |
| BAF/endgame rewards | EndgameModule |
| Whale/deity pass | WhaleModule |
| Degenerette betting | DegeneretteModule |
| Boon effects | BoonModule |
| GAMEOVER | GameOverModule |
| ETH claims | Direct (no delegatecall) |

All module delegatecalls share DegenerusGameStorage. Slot alignment is guaranteed by identical inheritance.

### 6b. Cross-Contract Value Flows

```
BurnieCoin ----mint/burn----> Players
    |
    +--decimatorBurn--------> DegenerusGame (recordDecBurn via delegatecall to DecimatorModule)
    +--terminalDecBurn------> DegenerusGame (recordTerminalDecBurn via delegatecall to DecimatorModule)
    +--coinflip-------------> BurnieCoinflip
    +--quest-----------------> DegenerusQuests

DegenerusGame
    |
    +--claimWinnings---------> Players (ETH, stETH fallback)
    +--claimWinningsStethFirst-> Vault/sDGNRS (stETH first)
    +--GAMEOVER--------------> GameOverModule
    |     +--10%: terminal dec -> DecimatorModule
    |     +--90%: terminal jkpt -> JackpotModule
    |     +--remainder: vault/sDGNRS 50/50
    |
    +--level advance---------> AdvanceModule
    |     +--yield surplus----> yieldAccumulator -> pool amplification at x00
    |     +--deity refund-----> claimableWinnings (levels 0-9)
    |     +--BAF/decimator----> EndgameModule -> JackpotModule/DecimatorModule
    |
    +--affiliate DGNRS-------> sDGNRS.transferFromPool(Affiliate, ...)

StakedDegenerusStonk (sDGNRS)
    |
    +--burn------------------> Players (ETH + stETH)
    +--transferFromPool-------> Players (5 pools: Whale, Affiliate, Lootbox, Reward, Earlybird)
    +--depositSteth-----------> From Game/GameOverModule
    +--burnRemainingPools-----> Zeroes pool balances at GAMEOVER

DegenerusStonk (DGNRS)
    |
    +--burn------------------> Unwrap to sDGNRS then sDGNRS.burn
    +--unwrapTo (blocked during VRF stall)

DegenerusVault
    |
    +--redeem DGVE-----------> ETH + stETH proportional
    +--redeem DGVB-----------> BURNIE proportional
    +--vaultMintTo WWXRP-----> WWXRP tokens
```

---

## 7. Anti-Patterns and Architectural Risks

### Risk 1: GAMEOVER Module Runs in Game's Context but Uses Untrusted Data

`handleGameOverDrain` reads `rngWordByDay[day]` which is populated by VRF callback or historical fallback. If fallback is used, the RNG quality is weaker (validator can influence 1 bit via prevrandao). This is documented and accepted but must be verified in the audit.

### Risk 2: Terminal Decimator Adds New State to GAMEOVER Critical Path

The uncommitted terminal decimator changes `handleGameOverDrain` to call `runTerminalDecimatorJackpot` instead of `runDecimatorJackpot`. This is a direct modification of the most critical code path. The new function must handle:
- Zero participants (no burns for current level) -- must refund full 10% to remaining
- Bucket selection with VRF word from dead coordinator (fallback RNG)
- uint80/uint88 overflow in weighted burns (verify time multiplier * cap stays within range)

### Risk 3: claimablePool is the Solvency Sentinel

Every function that credits `claimableWinnings[address]` MUST also increment `claimablePool` by the same amount. Every function that debits (claim) MUST decrement both. A single missed update breaks the solvency invariant. This invariant has 16+ mutation sites across 6+ modules.

### Risk 4: stETH Rounding at Scale

Lido stETH transfers can lose 1-2 wei per operation. At GAMEOVER with large balances, the `_sendToVault` function does multiple stETH transfers (vault share + sDGNRS share). Verify that cumulative rounding does not exceed the safety margin maintained by the solvency invariant.

### Risk 5: Deity Refund Loop Gas

`handleGameOverDrain` iterates `deityPassOwners.length` to process refunds. If many deity passes are purchased, this loop could exceed block gas limit. Verify that practical limits (deity pass quadratic pricing means few purchasers) keep this bounded.

---

## 8. Build Order Rationale

**Phase 26 (GAMEOVER) before Phase 27 (Payouts):** GAMEOVER is the highest-stakes path and also delegates to payout subsystems. Understanding the terminal context first means you can identify which payout paths have dual behavior (normal gameplay vs GAMEOVER).

**Phase 27 (Payouts) before Phase 28 (Invariants):** You cannot verify the solvency invariant without first mapping every site that credits/debits claimablePool. Phase 27 produces this exhaustive map.

**Phase 28 (Invariants) before Phase 29 (Comments):** Invariants are mathematical truth. Comments are human-readable descriptions. Fix truth first, then verify descriptions match.

**Phase 29 (Comments) before Phase 30 (Payout Spec):** The payout spec must describe verified behavior. Phase 29 corrects any NatSpec that was wrong, so phase 30 has accurate descriptions to draw from.

**Phase 30 (Payout Spec) last:** The specification document is a synthesis of all prior phases. It cannot be accurate until all audit phases complete. Writing it earlier would require rework.

---

## 9. Key Patterns to Follow

### Pattern: Credit-Then-Pool

Every ETH credit follows this pattern:
```solidity
claimableWinnings[player] += amount;
claimablePool += amount;
emit PlayerCredited(player, player, amount);
```
Verify this three-step pattern at every credit site. Any deviation is a potential finding.

### Pattern: Claim-Then-Send (CEI)

Every ETH withdrawal follows:
```solidity
// Check
uint256 amount = claimableWinnings[player];
if (amount <= 1) revert E();
// Effects
claimableWinnings[player] = 1; // sentinel
claimablePool -= payout;
// Interaction
payable(player).call{value: payout}("");
```

### Pattern: Budget-Capped Distribution

GAMEOVER deity refund uses:
```solidity
uint256 budget = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
// Loop: min(refund, budget), decrement budget
```
This prevents over-allocation. Verify the budget calculation accounts for ALL prior obligations (claimablePool includes all existing claims).

### Pattern: Delegatecall Self-Call for Module Routing

GAMEOVER uses `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(...)` -- a regular external call to self that then delegatecalls to the module. This means the module executes in Game's storage context. Verify msg.sender == address(this) guards are present.

---

## Sources

All findings based on direct inspection of:
- All 23 contract source files in `contracts/`
- All 12 module files in `contracts/modules/`
- All 42 audit documents in `audit/`
- Uncommitted terminal decimator changes (7 files, 490 lines) via `git diff HEAD`
- `.planning/PLAN-TERMINAL-DECIMATOR.md` (terminal decimator specification)
- `.planning/PROJECT.md` (v3.0 milestone definition)
- `.planning/MILESTONES.md` (prior milestone history)
- `.planning/STATE.md` (current state)
- Prior research `ARCHITECTURE.md` (v2.1 governance audit integration)
