# Phase 28: Cross-Cutting Verification - Research

**Researched:** 2026-03-18
**Domain:** Smart contract security audit -- regression verification, protocol-wide invariants, boundary analysis, adversarial vulnerability ranking
**Confidence:** HIGH

## Summary

Phase 28 is the cross-cutting verification layer that operates across the full audited system established in Phases 26 (GAMEOVER, 9 requirements, 8 PASS + 1 FINDING-MEDIUM) and Phase 27 (Payout/Claim, 19 requirements, 19 PASS). It addresses 19 requirements across 4 distinct workstreams: recent changes regression (CHG-01 through CHG-04), protocol-wide invariant verification (INV-01 through INV-05), edge case and griefing analysis (EDGE-01 through EDGE-07), and top-10 vulnerability deep audit (VULN-01 through VULN-03).

The protocol codebase comprises 25,326 lines of Solidity across 14 core contracts, 10 delegatecall modules, 7 libraries, and 3 shared abstract contracts. There are 113 commits touching the contracts/ directory in the last month (since 2026-02-17), spanning features such as the terminal decimator, VRF governance replacement, sDGNRS/DGNRS split, gas optimizations, deity/whale gameplay stripping, and numerous parameter changes. The cumulative audit through Phase 27 covers 97 plans examining 118 requirements across 17 phases with 0 Critical, 0 High, 3 Medium, 4 Low, and 16+ Informational findings.

Phase 28 is unique in that it does not audit new code paths -- instead, it synthesizes and cross-references everything already audited, looking for gaps that per-path analysis cannot detect: accounting desynchronization across systems, regression from recent commits, boundary conditions at extreme parameter values, and the identification of the highest-risk functions through systematic vulnerability ranking. The claimablePool invariant has already been verified at 14 unique mutation sites (6 GAMEOVER + 8 normal-gameplay), but INV-01 requires re-verification including the terminal decimator paths explicitly. INV-02 through INV-05 address pool accounting, sDGNRS supply conservation, BURNIE lifecycle, and permanently unclaimable funds -- all partially covered in prior phases but never consolidated with explicit proofs in a single document.

**Primary recommendation:** Organize into 5 waves: (1) recent changes regression with git diff analysis, (2) protocol-wide invariant consolidation with exhaustive proofs, (3) boundary condition and edge case analysis, (4) top-10 vulnerability ranking and deep adversarial audit, (5) consolidation of all verdicts with findings report update. Each wave produces an audit document with explicit PASS/FINDING verdicts and file:line references.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CHG-01 | All commits in last month verified -- git log reviewed, each change assessed for correctness | 113 commits touching contracts/ since 2026-02-17; git log available; many already audited in Phases 19-27 but need explicit regression assessment |
| CHG-02 | VRF governance mechanism verified -- propose/vote/execute paths still correct after recent changes | DegenerusAdmin.sol (778 lines); 73c50cb3 removed death clock pause + fixed _executeSwap CEI; Phase 24 audit covers pre-change state; need delta verification |
| CHG-03 | Deity non-transferability changes verified -- soulbound enforcement, edge cases checked | DegenerusDeityPass.sol (392 lines); 50dbefcc made DGNRS soulbound; aa83cdb7 stripped deity/whale gameplay; Phase 19 covered sDGNRS split |
| CHG-04 | Parameter changes verified -- any constant modifications cross-referenced against parameter reference doc | v1.1-parameter-reference.md (updated 2026-03-17); f71b6382 removed 5 unused constants; multiple feat commits changed parameters |
| INV-01 | claimablePool <= balance + stETH verified at every mutation site including terminal decimator | 14 mutation sites already verified (Phase 26: 6 GAMEOVER, Phase 27: 8 normal); need unified proof with terminal decimator paths explicit |
| INV-02 | Pool accounting verified -- all pool additions and subtractions balance across all paths | Pool transition chain: futurePrizePool -> nextPrizePool -> currentPrizePool -> claimablePool; verified per-path in Phase 27; need cross-path proof |
| INV-03 | sDGNRS total supply = sum of all balances verified | Formally proven in novel-03-invariants-privilege.md (NOVEL-05); need confirmation still holds after recent changes |
| INV-04 | BURNIE mint/burn accounting verified -- coinflip lifecycle accounting correct | Coinflip economy audited in Phase 27 (PAY-07/08/18/19); BurnieCoinflip.sol 1154 lines; need lifecycle proof across all mint/burn sites |
| INV-05 | No permanently unclaimable funds path exists (outside intentional expiry) | Multiple claim paths with different expiry semantics; need exhaustive path enumeration |
| EDGE-01 | GAMEOVER at level 0, level 1, level 100 boundaries analyzed | GameOverModule level aliasing (lvl=0 -> 1), terminal jackpot targets lvl+1, safety valve at lvl>0; need boundary-specific walkthroughs |
| EDGE-02 | Single-player GAMEOVER scenario analyzed | All distribution paths must handle 1 player; winner selection, pro-rata shares, whale passes with 1 recipient |
| EDGE-03 | advanceGame gas griefing and state manipulation analyzed | AdvanceModule ~1400 lines; tiered gating; batched processing; need gas limit analysis |
| EDGE-04 | Decimator lastDecClaimRound overwrite timing analyzed | DecimatorModule:297-547; lastDecClaimRound overwrites on each resolution; claim bricking analysis |
| EDGE-05 | Coinflip auto-rebuy carry during known-RNG windows analyzed | BurnieCoinflip auto-rebuy carry; RNG lock during VRF callback; need extraction analysis |
| EDGE-06 | Affiliate self-referral loop analysis | DegenerusAffiliate:386-623; 3-tier commission; self-referral check exists but need completeness proof |
| EDGE-07 | Rounding accumulation analysis | Multiple BPS divisions, unchecked arithmetic; need compound rounding analysis across repeated operations |
| VULN-01 | All state-changing functions ranked by vulnerability likelihood using weighted criteria | state-changing-function-audits.md provides function inventory; need new ranking with weighted criteria |
| VULN-02 | Top 10 most vulnerable functions receive deep adversarial audit | Each function needs dedicated finding or explicit PASS with adversarial trace |
| VULN-03 | Vulnerability ranking document produced with rationale | Ranking document with criteria weights, scoring, and rationale for each position |
</phase_requirements>

## Standard Stack

This is a security audit phase, not an implementation phase. The "stack" is the audit methodology, source contracts, and prior audit artifacts.

### Core: Contracts Under Audit (Full Protocol Scope)

| Contract | Location | Lines | Phase 28 Focus | Prior Coverage |
|----------|----------|-------|----------------|----------------|
| DegenerusGame.sol | contracts/ | 2856 | CHG-01/04, INV-01/02, VULN ranking | Phases 1-27 (extensive) |
| DegenerusGameAdvanceModule.sol | contracts/modules/ | 1383 | CHG-01, EDGE-03, VULN ranking | Phases 26-27 (GAMEOVER + bounty) |
| DegenerusGameJackpotModule.sol | contracts/modules/ | 2819 | INV-01/02, EDGE-01, VULN ranking | Phase 27 (jackpot distribution) |
| DegenerusGameDecimatorModule.sol | contracts/modules/ | 1027 | INV-01, EDGE-01/04, VULN ranking | Phase 26 (terminal dec) + 27 (normal dec) |
| DegenerusGameEndgameModule.sol | contracts/modules/ | 540 | INV-02, VULN ranking | Phase 27 (scatter/BAF) |
| DegenerusGameGameOverModule.sol | contracts/modules/ | 233 | EDGE-01/02, INV-01 | Phase 26 (complete) |
| DegenerusGameLootboxModule.sol | contracts/modules/ | 1778 | INV-05, VULN ranking | Phase 27 (PAY-09) |
| DegenerusGameMintModule.sol | contracts/modules/ | ~800 | CHG-01, VULN ranking | Phase 1-15 (economic flow) |
| DegenerusGamePayoutUtils.sol | contracts/modules/ | 94 | INV-01, VULN ranking | Phase 26-27 (shared infrastructure) |
| BurnieCoinflip.sol | contracts/ | 1154 | INV-04, EDGE-05 | Phase 27 (PAY-07/08/18/19) |
| BurnieCoin.sol | contracts/ | ~860 | INV-04, EDGE-05 | Phase 27 (creditFlip routing) |
| DegenerusAdmin.sol | contracts/ | 778 | CHG-02, VULN ranking | Phase 24 (governance audit) |
| DegenerusDeityPass.sol | contracts/ | 392 | CHG-03 | Partially covered in Phases 1-15 |
| DegenerusAffiliate.sol | contracts/ | 847 | EDGE-06 | Phase 27 (PAY-11) |
| StakedDegenerusStonk.sol | contracts/ | 514 | INV-03, VULN ranking | Phases 19-21 (delta) + 27 (PAY-14) |
| DegenerusStonk.sol | contracts/ | 223 | CHG-03 (soulbound), INV-03 | Phases 19-21 (delta) + 27 (PAY-15) |
| WrappedWrappedXRP.sol | contracts/ | 389 | INV-05 | Phase 27 (PAY-18) |
| DegenerusQuests.sol | contracts/ | 1598 | CHG-01, INV-05 | Phase 27 (PAY-10) |
| DegenerusVault.sol | contracts/ | ~300 | INV-05 | Phases 1-15 |

### Supporting: Audit Reference Documents

| Document | Location | Phase 28 Use |
|----------|----------|-------------|
| v3.0-gameover-audit-consolidated.md | audit/ | INV-01 cross-reference, EDGE-01/02 base |
| v3.0-payout-audit-consolidated.md | audit/ | INV-01/02 cross-reference, VULN ranking input |
| FINAL-FINDINGS-REPORT.md | audit/ | Cumulative findings context, update target |
| KNOWN-ISSUES.md | audit/ | Design decisions context, update target |
| v1.1-parameter-reference.md | audit/ | CHG-04 cross-reference |
| state-changing-function-audits.md | audit/ | VULN-01 function inventory |
| v2.1-governance-verdicts.md | audit/ | CHG-02 base state |
| novel-01-economic-amplifier-attacks.md | audit/ | VULN ranking input |
| novel-02-composition-griefing-edges.md | audit/ | VULN ranking input |
| novel-03-invariants-privilege.md | audit/ | INV-03 formal proof base |
| novel-04-timing-race-conditions.md | audit/ | VULN ranking input |

### Git History for CHG-01

113 commits touching contracts/ since 2026-02-17. Notable categories:

| Category | Count | Key Commits |
|----------|-------|-------------|
| Terminal decimator | 1 | 726195ff (death bet + daily sDGNRS flip) |
| VRF governance | 3 | 73c50cb3, aa83cdb7, ed77733f |
| sDGNRS/DGNRS split | 3 | 0c15c34b, 50dbefcc, c93ac862 |
| Gas optimizations | 3 | c354f81a, f71b6382, 0895d445 |
| Deity/whale strip | 2 | aa83cdb7, 2b3c390d |
| Pool mechanics | 6+ | f2a30060, 7e81599a, 126a4153, b3da98e9, etc. |
| Bug fixes | 5+ | 9c59e7c2, bac742ec, 288fae9e, 6cd91438, f643be20 |
| Audit doc sync | 3 | fae259ba, ffde3f50, 7a204af3 |
| Parameter changes | 4+ | e93139e9, 73fddf3e, e59f9a32, f2a30060 |

## Architecture Patterns

### Workstream Organization

Phase 28's 19 requirements organize into 4 distinct workstreams, each with different methodology:

**Workstream 1: Recent Changes Regression (CHG-01, CHG-02, CHG-03, CHG-04)**
```
Methodology: Git-diff-driven analysis
  |
  +-- CHG-01: Review all 113 commits in last month
  |     Approach: Categorize by prior audit coverage
  |     - Commits covered by Phase 19-27 audits -> mark as VERIFIED
  |     - Commits NOT covered by any phase -> full assessment needed
  |     - Bug fix commits -> verify fix correctness
  |
  +-- CHG-02: VRF governance delta verification
  |     Approach: Diff against Phase 24 audited state
  |     - 73c50cb3 removed death clock pause + activeProposalCount + fixed CEI
  |     - Verify governance verdicts (GOV-01 through GOV-09) still hold
  |
  +-- CHG-03: Deity non-transferability
  |     Approach: Verify soulbound enforcement in DeityPass + DGNRS
  |     - 50dbefcc made DGNRS soulbound (stripped transfers)
  |     - aa83cdb7 stripped deity/whale gameplay
  |     - Verify no remaining transfer/approval paths
  |
  +-- CHG-04: Parameter changes
        Approach: Cross-reference v1.1-parameter-reference.md against current code
        - f71b6382 removed 5 unused constants
        - Any BPS/timing/ETH constant changes since reference was updated
```

**Workstream 2: Protocol-Wide Invariants (INV-01 through INV-05)**
```
Methodology: Exhaustive proof by path enumeration
  |
  +-- INV-01: claimablePool solvency
  |     Source: 14 mutation sites (Phase 26: 6, Phase 27: 8)
  |     Approach: Unified proof document with algebraic verification
  |     Terminal decimator paths explicitly included
  |
  +-- INV-02: Pool accounting balance
  |     Source: Pool transition chain
  |     futurePrizePool -> nextPrizePool -> currentPrizePool -> claimablePool
  |     Approach: Trace every pool increment/decrement across all paths
  |
  +-- INV-03: sDGNRS supply conservation
  |     Source: novel-03-invariants-privilege.md (NOVEL-05)
  |     Approach: Verify formal proof still holds after recent changes
  |     Key: Only _mint (constructor-only) and burn() modify supply
  |
  +-- INV-04: BURNIE mint/burn lifecycle
  |     Source: BurnieCoinflip + BurnieCoin
  |     Approach: Enumerate all mint paths and burn paths
  |     Verify: No path creates unbacked BURNIE or destroys tracked BURNIE
  |
  +-- INV-05: No permanently unclaimable funds
        Source: All claim paths
        Approach: For each claim mechanism, verify either:
          (a) No expiry -- permanently claimable, or
          (b) Expiry exists but is intentional (documented in KNOWN-ISSUES)
```

**Workstream 3: Edge Cases and Griefing (EDGE-01 through EDGE-07)**
```
Methodology: Boundary condition walkthrough + adversarial analysis
  |
  +-- EDGE-01: GAMEOVER boundary levels
  |     Level 0: 365d timeout, lvl aliased to 1, terminal jackpot targets lvl 2
  |     Level 1: 120d timeout, safety valve check, terminal jackpot targets lvl 2
  |     Level 100: x00 century mechanics, large populated ticket pools
  |
  +-- EDGE-02: Single-player GAMEOVER
  |     One player in entire game -> all distributions go to 1 address
  |     Winner selection must handle pool of 1, pro-rata must not divide by zero
  |
  +-- EDGE-03: advanceGame gas griefing
  |     Can attacker block advanceGame by making it exceed block gas limit?
  |     Loops: ticket queue processing, lootbox resolution, decimator burns
  |
  +-- EDGE-04: Decimator claim timing / bricking
  |     lastDecClaimRound overwrite -> old claims expire
  |     Can attacker trigger new decimator round to brick victim's claims?
  |
  +-- EDGE-05: Coinflip auto-rebuy during known-RNG
  |     After VRF word is committed but before day advances
  |     Can player see outcome and auto-rebuy into known-winning day?
  |
  +-- EDGE-06: Affiliate self-referral loops
  |     3-tier: direct 20%, indirect 4%, indirect-indirect 0%
  |     Self-referral: can player be own affiliate at any tier?
  |
  +-- EDGE-07: Rounding accumulation
        BPS divisions truncate (Solidity default)
        Across 1000+ small operations, can rounding compound to material?
```

**Workstream 4: Top-10 Vulnerability Ranking (VULN-01, VULN-02, VULN-03)**
```
Methodology: Weighted scoring + adversarial deep audit
  |
  +-- VULN-01: Rank ALL state-changing functions
  |     Criteria: (1) ETH/value moved, (2) complexity/LOC,
  |               (3) external interaction count, (4) prior coverage depth,
  |               (5) novelty of code, (6) access control surface
  |     Output: Ranked list with scores
  |
  +-- VULN-02: Deep adversarial audit of top 10
  |     For each: dedicated finding or explicit PASS
  |     Approach: Think like a C4A warden -- what exploit hypothesis?
  |
  +-- VULN-03: Ranking document with rationale
        Output: Standalone document suitable for manual review
```

### claimablePool Mutation Inventory (Complete Protocol)

From Phases 26-27 consolidated reports, the complete inventory is:

**GAMEOVER Path (6 sites, verified Phase 26):**

| ID | Location | Mutation | Direction |
|----|----------|----------|-----------|
| G1 | GameOverModule:105 | `claimablePool += totalRefunded` | UP (deity refunds) |
| G2 | GameOverModule:143 | `claimablePool += decSpend` | UP (terminal decimator) |
| G3 | JackpotModule:1573 | `claimablePool += ctx.liabilityDelta` | UP (terminal jackpot) |
| G4 | GameOverModule:177 | `claimablePool = 0` | ZERO (final sweep) |
| G5 | DecimatorModule:936 | `_addClaimableEth` -> `_creditClaimable` | UP (terminal dec claims) |
| G6 | DegenerusGame:1440 | `claimablePool -= payout` | DOWN (player withdrawal) |

**Normal Gameplay (8 sites, verified Phase 27):**

| ID | Location | Mutation | Direction |
|----|----------|----------|-----------|
| N1 | JackpotModule:1572-1573 | `claimablePool += ctx.liabilityDelta` | UP (purchase-phase jackpot) |
| N2 | JackpotModule:1529-1531 | `claimablePool += liabilityDelta` | UP (jackpot-phase draws) |
| N3 | PayoutUtils:90 | `claimablePool += remainder` | UP (whale pass remainder) |
| N4 | EndgameModule:226 | `claimablePool += claimableDelta` | UP (BAF scatter) |
| N5 | EndgameModule:275 | `claimablePool += calc.reserved` | UP (auto-rebuy take-profit) |
| N6 | DecimatorModule:478/490/519 | claim credit | UP (decimator claims) |
| N7 | JackpotModule:940-958 | `claimablePool += claimableDelta` | UP (yield distribution) |
| N8 | DegenerusGame:1440 | `claimablePool -= payout` | DOWN (player withdrawal) |

**Note:** G3 overlaps N1 (same code path), G5 overlaps _creditClaimable path, G6 overlaps N8. Total unique code locations: ~11-12.

### Key Functions for Vulnerability Ranking

Based on the complete audit history, the highest-risk state-changing functions are candidates for the VULN-01 ranking. The inventory from state-changing-function-audits.md provides the function-level map, but the ranking criteria should weight:

1. **Value moved (40%):** Functions that directly move ETH, stETH, BURNIE, or DGNRS
2. **Complexity (20%):** Lines of code, branching, loops, delegatecall chains
3. **External interaction count (15%):** Cross-contract calls, especially to Lido/VRF
4. **Prior coverage depth (15%):** Functions with shallow prior audit receive higher risk
5. **Novelty of code (10%):** Recently written or recently modified code

Candidate high-risk functions (to be formally ranked in VULN-01):
- `advanceGame()` / AdvanceModule.advanceGame -- orchestrates the entire game state machine
- `handleGameOverDrain()` -- terminal distribution of all funds
- `handleFinalSweep()` -- final forfeiture and sweep
- `recordMint()` / MintModule -- ETH entry point, pool routing
- `_distributeJackpotEth()` -- jackpot ETH distribution to winners
- `claimWinnings()` / `_claimWinningsInternal()` -- ETH withdrawal
- `burn()` in StakedDegenerusStonk -- proportional redemption
- `claimDecimatorJackpot()` -- decimator claim with expiry mechanics
- `_executeSwap()` in DegenerusAdmin -- VRF coordinator swap
- `_claimCoinflipsInternal()` -- coinflip claim with mint/burn
- `_addClaimableEth()` variants -- auto-rebuy interaction
- `claimWhalePass()` -- deferred whale pass payout

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Git change review | Manual commit-by-commit reading | Categorize commits by prior audit coverage first, then only deeply review uncovered commits | 113 commits -- most already covered by Phases 19-27; systematic triage prevents wasted effort |
| Invariant proofs | Ad-hoc spot checks | Exhaustive path enumeration with algebraic proof per mutation site | Phases 26-27 demonstrated this methodology with verified results; extend it |
| Vulnerability ranking | Gut feeling | Weighted multi-criteria scoring with documented rationale | VULN-03 requires ranking document "suitable for manual review" with explicit rationale |
| Boundary analysis | Pick random boundaries | Systematic boundary matrix: level 0/1/100, 1 player, empty pools, max values | EDGE requirements specify exact boundaries to analyze |
| Rounding analysis | Theoretical reasoning | Concrete numerical walkthrough with worst-case accumulation | EDGE-07 specifically asks about compounding rounding -- needs concrete numbers |

## Common Pitfalls

### Pitfall 1: Regression Completeness Theater (CP-01)
**What goes wrong:** Auditor reviews 113 commits line-by-line, runs out of time, produces shallow coverage of everything
**Why it happens:** Treating all commits equally despite most being already audited in prior phases
**How to avoid:** First categorize all 113 commits by audit coverage: (a) covered by Phase 19-27 audit, (b) covered by earlier phases, (c) uncovered. Only deeply review category (c). For (a) and (b), verify the audit verdict still holds given any subsequent changes.
**Warning signs:** CHG-01 assessment that lists commits without connecting them to prior audit phases

### Pitfall 2: Invariant Proof by Reference Only (CP-02)
**What goes wrong:** INV-01 through INV-05 just say "verified in Phase 26/27" without independent proof
**Why it happens:** Prior phases did verify these invariants per-path, but cross-cutting verification requires a unified proof
**How to avoid:** Produce a new standalone proof for each invariant. Can reference prior phase evidence but must present a complete argument. The value of Phase 28 is the cross-cutting synthesis, not a summary of prior work.
**Warning signs:** Invariant verdicts that cite only prior phase documents without presenting own analysis

### Pitfall 3: Edge Case Analysis Without Concrete Parameters (CP-03)
**What goes wrong:** EDGE-01 says "level 0 GAMEOVER works correctly" without walking through specific values
**Why it happens:** Auditor reasons about behavior abstractly instead of with concrete state
**How to avoid:** For each EDGE requirement, construct a specific scenario with concrete values: "At level 0 with 50 ETH balance, 10 ETH claimablePool, 3 deity pass holders..." and trace the entire execution with actual numbers.
**Warning signs:** Edge case analysis with no concrete numerical examples

### Pitfall 4: Vulnerability Ranking Without Consistent Criteria (CP-04)
**What goes wrong:** Top-10 list is based on auditor intuition rather than systematic evaluation
**Why it happens:** VULN-01 requires "weighted criteria" but auditor skips the scoring step
**How to avoid:** Define criteria weights BEFORE ranking. Score every state-changing function against all criteria. Rank by total score. The ranking document must show the math, not just the result.
**Warning signs:** VULN ranking without a scoring table

### Pitfall 5: Missing the "Cross" in Cross-Cutting (CP-05)
**What goes wrong:** Each requirement is analyzed in isolation, missing interactions between systems
**Why it happens:** Prior phases audited systems independently -- Phase 28 must look at how they interact
**How to avoid:** Explicitly trace cross-system interactions: How does GAMEOVER interact with active coinflip claims? How does sDGNRS burn interact with pending decimator claims? How does advanceGame interact with concurrent claimWinnings?
**Warning signs:** Phase 28 verdicts that read like Phase 26/27 verdicts -- per-system rather than cross-system

### Pitfall 6: Overcounting Covered Commits (CP-06)
**What goes wrong:** CHG-01 marks commits as "verified" because they were made DURING an audit phase, when actually the audit phase happened before or after the commit
**Why it happens:** Temporal proximity confused with causal coverage
**How to avoid:** Verify that each commit was either (a) the subject of an audit phase, or (b) existed in the codebase when an audit phase ran and the relevant code was reviewed. Use commit dates vs. audit dates.
**Warning signs:** Commits marked as covered by Phase X when Phase X was completed before the commit was made

## Code Examples

### Example 1: claimablePool Invariant Verification Pattern (from Phase 26)

The established pattern for verifying the claimablePool solvency invariant at each mutation site:

```
For each claimablePool mutation site:
  1. Record pre-mutation values:
     - claimablePool_before
     - balance_before = address(this).balance + stETH.balanceOf(this)
  2. Identify the mutation:
     - claimablePool += delta (UP), or
     - claimablePool -= delta (DOWN), or
     - claimablePool = 0 (ZERO)
  3. Prove invariant holds after mutation:
     - For UP: delta comes from balance (already held) or external deposit
       balance_after >= balance_before (no ETH leaves)
       claimablePool_after = claimablePool_before + delta
       If delta <= balance_before - claimablePool_before, invariant holds
     - For DOWN: delta leaves via external call
       balance_after = balance_before - delta
       claimablePool_after = claimablePool_before - delta
       balance_after - claimablePool_after = (balance_before - delta) - (claimablePool_before - delta) = balance_before - claimablePool_before >= 0
     - For ZERO: claimablePool = 0 and balance >= 0 trivially
  4. Deliver verdict: PASS (invariant preserved) or FINDING (violation path exists)
```

### Example 2: Vulnerability Ranking Scoring Template

```markdown
| Rank | Function | Value Moved (40%) | Complexity (20%) | Interactions (15%) | Coverage Depth (15%) | Novelty (10%) | Total |
|------|----------|-------------------|------------------|--------------------|---------------------|---------------|-------|
| 1 | handleGameOverDrain | 10 | 9 | 8 | 7 | 9 | 8.85 |
| 2 | advanceGame (full) | 8 | 10 | 9 | 6 | 6 | 7.80 |
| ... | ... | ... | ... | ... | ... | ... | ... |

Scoring: 1-10 per criterion, weighted by percentage shown.
```

### Example 3: Boundary Condition Walkthrough Template

```markdown
### EDGE-01: GAMEOVER at Level 0

**Scenario:** Game deployed, 365 days of inactivity at level 0, 50 ETH balance.

**State before:**
- level = 0
- lastSomething timestamp > 365 days ago
- claimablePool = 10 ETH (from early activity)
- deityPassOwners = [Alice, Bob] (2 passes)
- address(this).balance = 45 ETH
- stETH.balanceOf(this) = 5 ETH

**Execution trace:**
1. advanceGame() called
2. _handleGameOverPath: lvl == 0 -> aliased to lvl = 1
3. Safety valve: SKIPPED (lvl == 0 -> original currentLevel == 0 -> skip)
4. RNG acquisition: ...
5. handleGameOverDrain(day):
   - totalFunds = 45 + 5 = 50 ETH
   - Deity refunds: budget = 50 - 10 = 40 ETH
     Alice: 20 ETH (within budget)
     Bob: 20 ETH (40 - 20 = 20 remaining, within budget)
     totalRefunded = 40 ETH
     claimablePool = 10 + 40 = 50 ETH
   - available = 50 - 50 = 0 ETH
   - [CRITICAL PATH] remaining = 0 -> decPool = 0, terminal jackpot = 0
   ...

**Verdict:** [PASS/FINDING with explanation]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact on Phase 28 |
|--------------|------------------|--------------|---------------------|
| Per-path invariant verification | Cross-cutting invariant consolidation | Phase 28 (new) | Must unify 14 mutation sites into single proof |
| Single-pass GAMEOVER review | Multi-pass GAMEOVER + boundary analysis | Phase 26 | Phase 28 EDGE-01/02 extend with boundary conditions |
| Intuitive vulnerability assessment | Weighted multi-criteria ranking | Phase 28 (new) | First systematic vulnerability ranking in project |
| Git review by reading all code | Prior-coverage-aware regression triage | Phase 28 (new) | 113 commits categorized by audit coverage before review |

## Open Questions

1. **Commit Coverage Mapping Completeness**
   - What we know: Most of the 113 commits fall within the timeframe of Phases 19-27. Many were explicitly the subject of audit plans.
   - What's unclear: Exactly which commits were covered by which audit phase. Some commits may have been made after the audit phase that ostensibly covers them.
   - Recommendation: Build a commit-to-phase mapping table as the first task of CHG-01. Use commit dates and phase completion dates to determine actual coverage.

2. **DegeneretteModule Coverage Gap**
   - What we know: DegenerusGameDegeneretteModule.sol exists (~1100+ lines) and has a claimablePool mutation site at line 704. It was NOT explicitly in scope for Phase 26 or 27.
   - What's unclear: Whether degenerette interactions have been fully audited in prior phases (1-15, 19-23).
   - Recommendation: Include DegeneretteModule in INV-01 mutation trace and VULN-01 ranking. If coverage is shallow, flag for deeper review in VULN-02.

3. **BoonModule and WhaleModule Coverage**
   - What we know: DegenerusGameBoonModule.sol and DegenerusGameWhaleModule.sol (839 lines) exist as separate modules.
   - What's unclear: Depth of prior audit coverage for these modules.
   - Recommendation: Include in VULN-01 ranking assessment. If low coverage, these are candidates for top-10 vulnerability list.

4. **Lido stETH Pause Scenario for INV-01**
   - What we know: GO-05-F01 (Medium) identifies that _sendToVault hard reverts if Lido pauses stETH transfers. This is accepted risk.
   - What's unclear: Does INV-01 need to consider the Lido-paused scenario explicitly, or only normal operation?
   - Recommendation: INV-01 should verify the invariant under normal operation. The Lido-paused scenario is already documented as GO-05-F01 and does not affect the accounting invariant (it affects execution, not accounting).

5. **BURNIE Total Supply Tracking for INV-04**
   - What we know: BURNIE uses a mint-and-burn model. creditFlip creates virtual stakes (not token minting). Token minting happens at claim time.
   - What's unclear: Whether the virtual stake ledger (coinflip pending stakes) needs to be included in the BURNIE lifecycle accounting proof.
   - Recommendation: INV-04 should cover both the token supply (physical mints/burns) AND the virtual stake ledger. The proof must show that the coinflip system is internally consistent AND that physical token operations are correct.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hardhat + Chai (JavaScript), Foundry for fuzz |
| Config file | hardhat.config.ts |
| Quick run command | `npx hardhat test test/edge/GameOver.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CHG-01 | All commits in last month verified | manual audit | `git log --oneline --since="2026-02-17" -- contracts/` | N/A |
| CHG-02 | VRF governance still correct after changes | manual audit | N/A (code review) | N/A |
| CHG-03 | Deity non-transferability verified | manual audit | N/A (code review) | N/A |
| CHG-04 | Parameter changes verified | manual audit + cross-reference | N/A (code review + v1.1-parameter-reference.md) | N/A |
| INV-01 | claimablePool solvency at all mutation sites | manual audit | N/A (exhaustive proof) | N/A |
| INV-02 | Pool accounting balance | manual audit | N/A (exhaustive proof) | N/A |
| INV-03 | sDGNRS supply conservation | manual audit | N/A (formal proof verification) | N/A |
| INV-04 | BURNIE mint/burn lifecycle | manual audit | N/A (exhaustive proof) | N/A |
| INV-05 | No permanently unclaimable funds | manual audit | N/A (path enumeration) | N/A |
| EDGE-01 | GAMEOVER boundary levels | manual audit | N/A (scenario walkthrough) | N/A |
| EDGE-02 | Single-player GAMEOVER | manual audit | N/A (scenario walkthrough) | N/A |
| EDGE-03 | advanceGame gas griefing | manual audit | N/A (gas analysis) | N/A |
| EDGE-04 | Decimator claim timing | manual audit | N/A (timing analysis) | N/A |
| EDGE-05 | Coinflip auto-rebuy during known-RNG | manual audit | N/A (extraction analysis) | N/A |
| EDGE-06 | Affiliate self-referral loops | manual audit | N/A (code review) | N/A |
| EDGE-07 | Rounding accumulation | manual audit | N/A (numerical analysis) | N/A |
| VULN-01 | Vulnerability ranking by weighted criteria | manual audit | N/A (scoring exercise) | N/A |
| VULN-02 | Top 10 deep adversarial audit | manual audit | N/A (deep code review) | N/A |
| VULN-03 | Ranking document produced | manual audit | N/A (document creation) | N/A |

### Sampling Rate
- **Per task commit:** Verify audit verdicts are internally consistent with Phases 26-27 findings (no contradictions)
- **Per wave merge:** Cross-reference all verdicts within the wave against prior phase evidence
- **Phase gate:** All 19 requirements have PASS/FINDING verdicts; FINAL-FINDINGS-REPORT.md and KNOWN-ISSUES.md updated; vulnerability ranking document produced

### Wave 0 Gaps
This is an audit phase, not a code implementation phase. No new automated tests are required as deliverables. Findings may recommend new tests.

## Audit-Specific Methodology

### Approach Per Workstream

**CHG (Recent Changes):**
1. Build commit-to-phase coverage map
2. Identify uncovered commits
3. For each uncovered commit: read diff, assess correctness, verify no invariant violation
4. For CHG-02/03/04: targeted verification against specific prior audit state

**INV (Invariants):**
1. State the invariant formally
2. Enumerate ALL code paths that modify the relevant state variables
3. For each path, prove the invariant is preserved (algebraic proof or reasoning)
4. Deliver PASS if all paths preserve, FINDING if any path violates

**EDGE (Edge Cases):**
1. Construct concrete scenario with specific parameter values
2. Trace execution step-by-step with actual numbers
3. Check for: division by zero, overflow, gas exhaustion, empty array, single element
4. Deliver explicit verdict with scenario details

**VULN (Vulnerability Ranking):**
1. Define scoring criteria and weights
2. Score every state-changing function (from state-changing-function-audits.md inventory)
3. Rank by total weighted score
4. For top 10: construct adversarial hypothesis, trace attack path, deliver PASS/FINDING
5. Produce ranking document with full rationale

### Audit Output Format

Each requirement produces a verdict:
```
### [REQ-ID]: [Title]
**Verdict:** PASS | FINDING-[severity]
**Files:** [file:line-range]
**Summary:** [1-2 sentences]
**Evidence:** [proof, scenario trace, or cross-reference to specific prior audit evidence]
**Cross-System Interaction:** [any interaction with other systems noted]
**Recommendation:** [fix if FINDING, or "None" if PASS]
```

### Suggested Wave Organization

**Wave 1 (CHG-01, CHG-02, CHG-03, CHG-04): Recent Changes Regression**
- Build commit coverage map, assess uncovered changes
- Targeted VRF governance delta, deity soulbound, parameter cross-reference
- Priority: HIGH (establishes baseline for all subsequent waves)
- Estimated: ~120 lines audit output per CHG requirement

**Wave 2 (INV-01, INV-02, INV-03, INV-04, INV-05): Protocol-Wide Invariants**
- Exhaustive proofs for 5 invariants
- INV-01 builds on the 14-site inventory from Phases 26-27
- INV-03 extends the formal proof from novel-03
- Priority: HIGH (these are the protocol's safety guarantees)
- Estimated: ~200 lines audit output per INV requirement

**Wave 3 (EDGE-01 through EDGE-07): Edge Cases and Griefing**
- 7 specific edge case scenarios with concrete parameters
- Each requires step-by-step walkthrough with numbers
- Priority: MEDIUM-HIGH (finding probability is moderate)
- Estimated: ~150 lines audit output per EDGE requirement

**Wave 4 (VULN-01, VULN-02, VULN-03): Vulnerability Ranking**
- Systematic scoring of all state-changing functions
- Deep adversarial audit of top 10
- Ranking document production
- Priority: HIGH (highest finding probability for new discoveries)
- Estimated: VULN-01 ~200 lines (scoring table), VULN-02 ~100 lines per function, VULN-03 document

**Wave 5: Consolidation**
- Cross-reference all 19 verdicts
- Update FINAL-FINDINGS-REPORT.md and KNOWN-ISSUES.md
- Verify no contradictions with Phases 26-27
- Priority: Required (phase gate)

### Priority Ordering

1. **Wave 4 (VULN)** has highest finding probability -- deep adversarial audit of top-10 functions is most likely to uncover new issues
2. **Wave 2 (INV)** is the most rigorous -- unified proofs are the primary deliverable for protocol confidence
3. **Wave 1 (CHG)** is the baseline -- establishes what's changed and what's been verified
4. **Wave 3 (EDGE)** fills specific gaps -- boundary conditions and griefing vectors
5. **Wave 5 (Consolidation)** is required -- synthesizes everything

However, Wave 1 should execute FIRST because CHG-01 establishes the commit coverage baseline that informs all other waves. If a commit changed a critical path after Phase 26/27 audited it, that changes the invariant proof strategy.

**Recommended execution order:** Wave 1 -> Wave 2 -> Wave 3 -> Wave 4 -> Wave 5

## Sources

### Primary (HIGH confidence)
- audit/v3.0-gameover-audit-consolidated.md -- Phase 26 consolidated report with 9 requirement verdicts and 6 claimablePool mutation sites
- audit/v3.0-payout-audit-consolidated.md -- Phase 27 consolidated report with 19 requirement verdicts and 8 claimablePool mutation sites
- audit/FINAL-FINDINGS-REPORT.md -- cumulative findings (97 plans, 118 requirements, 17 phases, 0C/0H/3M/4L/16+I)
- audit/KNOWN-ISSUES.md -- all known findings and intentional design decisions
- audit/state-changing-function-audits.md -- complete state-changing function inventory
- audit/novel-03-invariants-privilege.md -- formal invariant proofs (sDGNRS supply conservation)
- audit/v2.1-governance-verdicts.md -- VRF governance audit verdicts (GOV-01 through GOV-09)
- audit/v1.1-parameter-reference.md -- master constant lookup (updated 2026-03-17)
- git log --since="2026-02-17" -- contracts/ -- 113 commits in last month

### Secondary (MEDIUM confidence)
- audit/novel-01-economic-amplifier-attacks.md -- economic attack vectors (all SAFE)
- audit/novel-02-composition-griefing-edges.md -- composition attacks and griefing
- audit/novel-04-timing-race-conditions.md -- timing and race conditions
- audit/warden-01-contract-auditor.md through warden-03-economic-analyst.md -- adversarial warden simulation results

## Metadata

**Confidence breakdown:**
- Recent changes scope: HIGH -- git log provides exact commit inventory; prior phase reports provide audit coverage baseline
- Invariant verification approach: HIGH -- extending proven Phase 26/27 methodology with complete mutation site inventory
- Edge case analysis scope: HIGH -- EDGE requirements are precisely specified; boundary values are deterministic
- Vulnerability ranking approach: HIGH -- state-changing-function-audits.md provides complete function inventory; weighted criteria methodology is well-defined
- Potential gaps: MEDIUM -- DegeneretteModule (line 704 mutation), BoonModule, and WhaleModule coverage depth uncertain

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (30 days -- contracts are stable post-Phase 27, no major changes expected during v3.0 audit completion)
