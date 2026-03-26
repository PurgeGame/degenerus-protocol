# Phase 46: Adversarial Sweep + Economic Analysis - Research

**Researched:** 2026-03-21
**Domain:** Multi-contract adversarial security audit + gambling burn economic analysis
**Confidence:** HIGH

## Summary

Phase 46 is the final security sweep for the v3.3 milestone. It requires two distinct workstreams: (1) a fresh-eyes adversarial sweep of all 29 contracts targeting High/Medium C4A findings, including composability attacks and access control verification for the 4 new gambling burn entry points, and (2) an economic analysis proving the gambling burn mechanism has no rational actor exploits and is resilient to bank-run scenarios.

The project has already completed thorough delta audits (Phase 44: 3 HIGH + 1 MEDIUM confirmed, all fixed in Phase 45), invariant testing (Phase 45: 7 Foundry invariants passing), and gas optimization (Phase 47: all 7 variables confirmed alive). A prior warden simulation (Phase 22, v2.0) covered the pre-gambling-burn codebase with 3 independent agents, producing 21 classified findings (6 KNOWN, 5 EXTENDS, 10 NEW -- all Low/QA). The v3.1 and v3.2 comment scans found 30 deduplicated findings (6 LOW, 24 INFO) across all contracts. The FINAL-FINDINGS-REPORT.md currently shows "No open findings." Phase 46 must now sweep with fresh eyes, accounting for the new gambling burn code paths added since the Phase 22 warden simulation.

The critical insight for planning is that this phase combines pure analysis (no code changes) with documentation deliverables. All 5 requirements (ADV-01 through ADV-03, ECON-01, ECON-02) produce audit documents, not code changes. The Phase 22 research and methodology provide a proven template for the warden simulation (same 3-agent persona approach), but the sweep must now include the gambling burn system's 4 new entry points and the economic analysis is entirely new scope.

**Primary recommendation:** Structure as 3-4 plans: (1) Warden simulation covering all 29 contracts with explicit verdicts (ADV-01), (2) Composability attack catalog + access control audit of new entry points (ADV-02, ADV-03), (3) Rational actor strategy catalog with EV calculations (ECON-01), and (4) Bank-run scenario analysis (ECON-02). Plans 3 and 4 could be combined if scope permits.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADV-01 | Warden simulation -- fresh-eyes read of all 29 contracts targeting High/Medium C4A findings | Phase 22 provides proven 3-agent methodology; EXTERNAL-AUDIT-PROMPT.md is ready-made prompt; must now include gambling burn entry points; output is per-contract verdict (finding or "clean") |
| ADV-02 | Cross-contract composability attacks -- multi-contract interaction sequences that bypass individual contract guards | Phase 44 mapped 26 cross-contract calls and 4-contract state consistency; gambling burn adds sDGNRS-DGNRS-BurnieCoinflip-AdvanceModule composition surface; must catalog multi-step sequences tested with outcomes |
| ADV-03 | Access control audit of new entry points -- claimCoinflipsForRedemption, burnForSdgnrs, resolveRedemptionPeriod, hasPendingRedemptions | All 4 functions have msg.sender checks traced in Phase 44; this requirement demands explicit standalone verification as separate deliverable |
| ECON-01 | Rational actor strategy catalog -- timing attacks, cap manipulation, stale accumulation, multi-address splitting with cost-benefit analysis | Must cover: (a) timing burn to manipulate roll, (b) burning exactly at 50% cap boundary, (c) accumulating claims without claiming, (d) Sybil multi-address burns to circumvent cap; each with EV calculation |
| ECON-02 | Bank-run scenario analysis -- what happens when many players burn simultaneously near supply cap | Must model: mass simultaneous burns approaching 50% cap per period, sequential period exhaustion, multi-period cumulative reservation approaching total holdings, and whether the contraction mapping proof from Phase 44 holds under adversarial conditions |
</phase_requirements>

## Standard Stack

This phase is an analysis and documentation phase, not a code implementation phase. The "stack" is the analysis methodology and verification tooling.

### Core Analysis Framework
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| C4A warden methodology | Blind adversarial audit with structured findings | Industry standard for competitive audits; proven in Phase 22; EXTERNAL-AUDIT-PROMPT.md provides base prompt |
| Foundry invariant test suite | Regression safety for any claims about invariant violations | 7 redemption invariants + 12 pre-existing invariant tests provide automated verification |
| Manual code tracing | Line-by-line attack path verification with file:line citations | Every finding must trace to specific code; Phase 44 demonstrated methodology |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| Phase 44 deliverables | Lifecycle trace, accounting reconciliation, solvency proof as reference | Starting point for composability and economic analysis -- don't re-derive proven results |
| Phase 22 warden reports | Prior blind review findings for regression/delta comparison | Cross-reference new warden findings against prior corpus |
| Phase 47 gas analysis | Variable liveness, storage layout reference | Context for any gas-related warden observations |
| forge test | Quick validation if any warden claims an invariant violation | `forge test --match-path test/fuzz/invariant/RedemptionInvariants.inv.t.sol` |

## Architecture Patterns

### Phase Decomposition

```
Phase 46: Adversarial Sweep + Economic Analysis
  |
  |-- Plan 46-01: Warden Simulation (ADV-01)
  |   |-- Task 1: Contract Auditor Agent (access control, CEI, state machine, storage)
  |   |-- Task 2: Zero-Day Hunter Agent (composition, unchecked, temporal, novel vectors)
  |   |-- Task 3: Economic Analyst Agent (MEV, flash loan, pricing, solvency)
  |   |-- Task 4: Consolidated per-contract verdict table (29 contracts, finding or "clean")
  |
  |-- Plan 46-02: Composability + Access Control (ADV-02, ADV-03)
  |   |-- Task 1: Cross-contract composability attack catalog
  |   |-- Task 2: Access control verification for 4 new entry points
  |
  |-- Plan 46-03: Economic Analysis (ECON-01, ECON-02)
  |   |-- Task 1: Rational actor strategy catalog (4 strategies with EV)
  |   |-- Task 2: Bank-run scenario analysis
```

### Warden Agent Personas

Follow the Phase 22 proven pattern. Each agent receives EXTERNAL-AUDIT-PROMPT.md plus role-specific focus. Agents operate BLIND -- they must not anchor on Phase 44 findings.

**Agent 1: Contract Auditor**
- Focus: Storage layout, reentrancy, CEI patterns, access control, state machine correctness
- Key delta from Phase 22: gambling burn state machine (submit/resolve/claim), 7 new state variables, 2 new mappings, PendingRedemption struct
- Must specifically sweep: StakedDegenerusStonk (802 lines), BurnieCoinflip (1127 lines), DegenerusGameAdvanceModule (1423 lines), DegenerusStonk (247 lines)

**Agent 2: Zero-Day Hunter**
- Focus: EVM-level exploits, unchecked arithmetic, assembly correctness, composition attacks, temporal edge cases
- Key delta: rngGate vs _gameOverEntropy parallel paths, `unchecked` blocks in sDGNRS, CP-07 split claim partial/full state management
- Must specifically check: all `unchecked` blocks in sDGNRS, the flipResolved/!flipResolved branching in claimRedemption, _payEth fallback-to-stETH logic

**Agent 3: Economic Analyst**
- Focus: MEV, flash loans, sandwich attacks, pricing manipulation, solvency invariants, game theory
- Key delta: gambling roll EV ([25,175] uniform = 100 mean), coinflip dependency on BURNIE payout, 50% supply cap per period, multi-period cumulative reservation convergence
- Must specifically analyze: timing between burn and advanceGame for roll prediction, sequential burn dilution effects, BURNIE coinflip bonus stacking

### Report Structure (per finding)
```
ID: [ADV-W1-XX / ADV-W2-XX / ADV-W3-XX]
Severity: [HIGH / MEDIUM / LOW / QA]
Contract: [file:line]
Title: [concise description]
Attack Path: [step-by-step with file:line references]
Impact: [what the attacker gains / what's lost]
Prerequisite: [what the attacker needs]
Cost/Profit: [is it economically viable?]
```

### Composability Attack Catalog Structure
```
Attack Sequence: [contract1.func -> contract2.func -> ...]
Guard Bypass: [what individual guard is circumvented by the sequence]
Tested: [YES/NO]
Outcome: [EXPLOITABLE / SAFE / GRIEFABLE]
Evidence: [file:line citations]
```

### Access Control Verification Structure (for ADV-03)
```
Function: [name]
Contract: [file:line]
Guard: [msg.sender check or modifier]
Expected Caller: [who should be able to call]
Verified Callers: [all call sites found in codebase]
Verdict: [CORRECT / OVERPERMISSIVE / UNDERPERMISSIVE]
```

### Economic Analysis Structure (for ECON-01)
```
Strategy: [name]
Description: [what the rational actor does]
Steps: [1. 2. 3. ...]
Cost: [gas + capital required]
Expected Return: [EV calculation]
Repeatability: [one-time / per-period / per-transaction]
Verdict: [EXPLOITABLE (positive EV) / NEUTRAL / UNPROFITABLE]
```

### Anti-Patterns to Avoid
- **Anchoring on Phase 44 findings:** Warden agents must operate blind. The composability plan can reference Phase 44 as validation, but the warden sweep must not.
- **Theoretical-only attacks:** Every attack must trace to specific file:line code paths and include economic viability assessment.
- **Severity inflation:** C4A wardens who inflate severity get downgraded by judges. Only classify HIGH if direct fund loss is provable.
- **Re-reporting known issues:** WAR-01 (compromised admin + inattention), WAR-02 (colluding cartel), WAR-06 (spam griefing) are documented known issues. Do not re-report.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Solvency proof | New mathematical derivation from scratch | Phase 44's contraction mapping proof (P_new = 0.125*P_old + 0.875*H) | Already proven; verify it holds under adversarial conditions, don't re-derive |
| Invariant validation | Manual arithmetic checking | `forge test --match-path test/fuzz/invariant/RedemptionInvariants.inv.t.sol` (7 invariants) | Automated coverage exceeds manual checking |
| Roll distribution analysis | Custom simulation script | Analytical: (currentWord >> 8) % 151 + 25 gives uniform [25, 175], mean=100 | Simple enough for closed-form; Monte Carlo deferred to EV-02 |
| Prior finding regression | Re-derive prior verdicts | Phase 22 regression check (48/48 PASS) + Phase 44 verdicts | Already verified; only delta since Phase 22 needs checking |

**Key insight:** This phase validates existing proofs under adversarial conditions rather than creating new proofs from scratch. Phase 44 proved solvency; Phase 46 asks "can an adversary break the assumptions that proof relies on?"

## Common Pitfalls

### Pitfall 1: Blind Spot on Split Claim (CP-07 Fix)
**What goes wrong:** The CP-07 fix split `claimRedemption` into ETH-always and BURNIE-conditional paths. The partial claim (`claim.ethValueOwed = 0` but struct not deleted) creates a state where a player has a "BURNIE-only" pending claim.
**Why it happens:** Auditors unfamiliar with the fix may not trace the partial claim state.
**How to avoid:** Warden agents must specifically check what happens when a player calls `claimRedemption` twice -- once for ETH (partial), once for BURNIE (full). Verify `claim.ethValueOwed = 0` prevents double ETH withdrawal.
**Warning signs:** Finding a "double claim" vector without checking the `claim.ethValueOwed = 0` assignment at line 606.

### Pitfall 2: Roll Uniformity Assumption
**What goes wrong:** Assuming the roll range [25, 175] is uniformly distributed without verifying the entropy source.
**Why it happens:** `(currentWord >> 8) % 151 + 25` uses modular arithmetic which has slight bias when 2^248 is not evenly divisible by 151.
**How to avoid:** Calculate the actual bias: `2^248 mod 151 = ?`. If the bias is < 1 in 10^72 (it is), document as negligible.
**Warning signs:** Claiming the roll is biased without quantifying the actual magnitude.

### Pitfall 3: Confusing EV-Neutral with Exploitable
**What goes wrong:** Identifying that a rational actor can time their burn to target a specific roll, and classifying it as a finding.
**Why it happens:** The roll depends on VRF (unpredictable). An actor who sees the VRF word can choose whether to call advanceGame (which resolves their burn), but they can't choose which day to submit for a specific roll.
**How to avoid:** Carefully distinguish pre-commit (before burn submission) vs post-commit (after burn, before resolution) information asymmetry. The burn is committed during VRF lock, so the player cannot see the roll before committing.
**Warning signs:** Attack scenarios that assume the player knows the VRF word before burning.

### Pitfall 4: Ignoring the RNG Lock Guard
**What goes wrong:** Proposing MEV attacks that require burning during the VRF resolution window.
**Why it happens:** `game.rngLocked()` blocks burns during VRF resolution (line 437/454 in sDGNRS). This guard prevents front-running the VRF word.
**How to avoid:** Any timing attack must account for the rngLocked guard. Burns can only occur when rngLocked is false, which is BEFORE the VRF request is made.
**Warning signs:** Attack paths that assume burns and VRF resolution can happen in the same transaction or block.

### Pitfall 5: Bank-Run Solvency Confusion
**What goes wrong:** Claiming that simultaneous mass burns can drain the contract below reserved amounts.
**Why it happens:** Each burn computes its share against `totalMoney - pendingRedemptionEthValue`. Sequential burns see progressively smaller available pools and reduced supply.
**How to avoid:** Use the Phase 44 proof that P_new <= H is maintained inductively for sequential burns. The 50% supply cap further limits per-period exposure.
**Warning signs:** Bank-run analysis that doesn't account for the sequential nature of EVM transactions (no true simultaneity).

## Code Examples

### New Entry Point Access Control (for ADV-03 verification)

**1. claimCoinflipsForRedemption** (BurnieCoinflip.sol:344-350)
```solidity
// Source: contracts/BurnieCoinflip.sol:344-350
function claimCoinflipsForRedemption(
    address player,
    uint256 amount
) external returns (uint256 claimed) {
    if (msg.sender != ContractAddresses.SDGNRS) revert OnlyBurnieCoin();
    // ^^^ Guard: only sDGNRS can call. Error name is misleading (DOC-03).
    return _claimCoinflipsAmount(player, amount, true);
}
```
Expected caller: StakedDegenerusStonk (via `_payBurnie` at line 768).

**2. burnForSdgnrs** (DegenerusStonk.sol:237-246)
```solidity
// Source: contracts/DegenerusStonk.sol:237-246
function burnForSdgnrs(address player, uint256 amount) external {
    if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized();
    // ^^^ Guard: only sDGNRS can call.
    uint256 bal = balanceOf[player];
    if (amount == 0 || amount > bal) revert Insufficient();
    // ... burn logic
}
```
Expected caller: StakedDegenerusStonk (via `burnWrapped` at line 450).

**3. resolveRedemptionPeriod** (StakedDegenerusStonk.sol:543-570)
```solidity
// Source: contracts/StakedDegenerusStonk.sol:543-544
function resolveRedemptionPeriod(uint16 roll, uint48 flipDay) external returns (uint256 burnieToCredit) {
    if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
    // ^^^ Guard: only game contract can call.
```
Expected caller: DegenerusGameAdvanceModule (via rngGate at line 775 and _gameOverEntropy post-fix).

**4. hasPendingRedemptions** (StakedDegenerusStonk.sol:534-536)
```solidity
// Source: contracts/StakedDegenerusStonk.sol:534-536
function hasPendingRedemptions() external view returns (bool) {
    return pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0;
}
```
No access control needed -- view function, no state change. Anyone can call.

### Key Economic Formulas (for ECON-01/02)

**Roll distribution:**
```
roll = (currentWord >> 8) % 151 + 25
Range: [25, 175], mean = 100, uniform (bias < 10^-72)
```

**ETH payout formula:**
```
ethValueOwed = (totalMoney * amount) / supplyBefore        // at submit
ethPayout = (ethValueOwed * roll) / 100                     // at claim
E[ethPayout] = ethValueOwed * E[roll] / 100 = ethValueOwed  // EV-neutral
```

**BURNIE payout formula (on flip win):**
```
burniePayout = (burnieOwed * roll * (100 + rewardPercent)) / 10000
Where rewardPercent: 5% chance of 50%, 5% chance of 150%, 90% chance of [78,115]
Flip win: 50% probability
E[burniePayout] = burnieOwed * E[roll]/100 * E[(100+rewardPercent)/100] * P(win)
                = burnieOwed * 1.0 * E[1+rewardPercent/100] * 0.5
```

**50% supply cap per period:**
```
redemptionPeriodBurned + amount <= redemptionPeriodSupplySnapshot / 2
```

### Solvency Invariant (from Phase 44)
```
pendingRedemptionEthValue <= address(this).balance + steth.balanceOf(this) + claimableWinnings()
Proof: P_new = 0.125 * P_old + 0.875 * H  (contraction mapping, converges to H from below)
```

## State of the Art

| Old Approach (Phase 22) | Current Approach (Phase 46) | When Changed | Impact |
|---|---|---|---|
| Warden sweep of pre-gambling-burn codebase | Must include gambling burn delta (4 new entry points, 7 new state vars, 2 new mappings) | Phase 44 code changes (v3.3) | Warden agents need updated scope covering sDGNRS gambling burn paths |
| DegenerusStonk.burn() allowed during active game | DegenerusStonk.burn() reverts with GameNotOver during active game (Seam-1 fix) | Phase 45-01 fix | Attack paths through DGNRS.burn() during active game are now blocked |
| claimRedemption was all-or-nothing (CP-07 issue) | claimRedemption has split claim: ETH-always + BURNIE-conditional | Phase 45-01 fix | Partial claim state (ethValueOwed=0, burnieOwed>0) is new -- must verify no double-claim |
| _gameOverEntropy lacked redemption resolution (CP-06 issue) | _gameOverEntropy now includes resolveRedemptionPeriod block | Phase 45-01 fix | Game-over path now correctly resolves pending redemptions |
| _deterministicBurnFrom excluded pending reservations (CP-08 issue) | _deterministicBurnFrom now subtracts pendingRedemptionEthValue and pendingRedemptionBurnie | Phase 45-01 fix | Deterministic burns no longer double-spend reserved funds |

**Key implication:** The warden sweep must validate that all 4 Phase 45 fixes are correctly implemented and introduce no new attack surfaces.

## Open Questions

1. **BURNIE coinflip EV calculation**
   - What we know: Flip win is 50%. Reward percent has a complex distribution (5%/5%/90% split). Roll is uniform [25,175].
   - What's unclear: The exact E[burniePayout] requires computing E[(100+rewardPercent)/100] across the rewardPercent distribution. This needs the ECON-01 plan to derive analytically.
   - Recommendation: Compute expected reward multiplier from BurnieCoinflip.sol rewardPercent formula (lines 787-798). The 90% band [78,115] midpoint is ~96.5%, so E[rewardPercent] ~ 0.05*50 + 0.05*150 + 0.90*96.5 = 96.85%. E[burniePayout] = burnieOwed * 1.0 * (1 + 0.9685) * 0.5 = burnieOwed * 0.984. This is slightly below 1.0 -- the house has a small edge on BURNIE. Verify analytically in plan.

2. **Multi-address splitting circumvention of 50% cap**
   - What we know: 50% cap is per-period, enforced by `redemptionPeriodBurned + amount <= snapshot/2`. All burns in the same period share the same cap.
   - What's unclear: Whether splitting burns across multiple addresses within the same period can bypass the cap (it cannot -- each address burns from its own balance, and `redemptionPeriodBurned` is a global accumulator, not per-address).
   - Recommendation: Verify in ECON-01 that `redemptionPeriodBurned` is global (line 687: `redemptionPeriodBurned += amount`), making multi-address splitting ineffective for cap bypass.

3. **Stale accumulation (never claiming)**
   - What we know: A player can delay claiming indefinitely after resolution. `pendingRedemptionEthValue` retains their share. They cannot submit a new claim in a different period while holding an unclaimed one (`UnresolvedClaim` revert at line 720).
   - What's unclear: Whether a player who never claims causes any system-wide issue beyond occupying segregated ETH.
   - Recommendation: Document in ECON-01 that stale claims block the individual player (cannot burn more in new periods) but do not affect other players or solvency. No systemic risk.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge 0.8.34 compatible), configured in foundry.toml |
| Config file | foundry.toml (invariant: 256 runs, depth 128) |
| Quick run command | `forge test --match-path test/fuzz/invariant/RedemptionInvariants.inv.t.sol -vvv` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADV-01 | Warden simulation report covering 29 contracts | manual-only | N/A -- document review | N/A |
| ADV-02 | Composability attack catalog | manual-only | N/A -- document review + selective `forge test` for claimed violations | N/A |
| ADV-03 | Access control verification for 4 new entry points | manual-only | N/A -- code review with file:line citations | N/A |
| ECON-01 | Rational actor strategy catalog | manual-only | N/A -- EV calculations documented | N/A |
| ECON-02 | Bank-run scenario analysis | manual-only | N/A -- analytical modeling | N/A |

**Justification for manual-only:** Phase 46 is a pure analysis phase. Its deliverables are audit documents, not code changes. The existing invariant test suite (Phase 45) provides automated regression coverage. If any warden agent claims an invariant violation, the invariant tests serve as automated verification: `forge test --match-path test/fuzz/invariant/RedemptionInvariants.inv.t.sol -vvv`.

### Sampling Rate
- **Per task commit:** Review document structure and citation count
- **Per wave merge:** Cross-reference findings against prior audit corpus
- **Phase gate:** All 29 contracts have explicit verdicts; all 4 entry points verified; all 4 rational actor strategies documented; bank-run analysis complete

### Wave 0 Gaps
None -- this is an analysis phase. No new test files or framework changes needed. Existing invariant tests provide regression safety for any claimed violations.

## Sources

### Primary (HIGH confidence)
- Phase 44 deliverables: `44-01-finding-verdicts.md`, `44-02-lifecycle-correctness.md`, `44-03-accounting-solvency-interaction.md` -- complete delta audit with 4 confirmed findings (all fixed)
- Phase 45 deliverables: 7 invariant tests passing (256 runs, depth 128, 0 failures)
- Phase 47 deliverables: `47-01-gas-analysis.md` -- all 7 variables alive, 3 packing opportunities
- Source code: `contracts/StakedDegenerusStonk.sol` (802 lines), `contracts/BurnieCoinflip.sol` (1127 lines), `contracts/modules/DegenerusGameAdvanceModule.sol` (1423 lines), `contracts/DegenerusStonk.sol` (247 lines)

### Secondary (MEDIUM confidence)
- Phase 22 warden simulation: 3 independent agents, 21 classified findings (6 KNOWN, 5 EXTENDS, 10 NEW), 48/48 regression PASS -- provides proven methodology and baseline
- `audit/EXTERNAL-AUDIT-PROMPT.md` -- ready-made prompt for warden agents
- `audit/KNOWN-ISSUES.md` -- 3 known issues (WAR-01, WAR-02, WAR-06) to exclude from warden findings

### Tertiary (LOW confidence)
- BURNIE EV calculation (open question 1) -- requires analytical derivation not yet performed; preliminary estimate E[burniePayout] ~ 0.984 * burnieOwed needs verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- methodology proven in Phase 22, reused with gambling burn delta
- Architecture: HIGH -- decomposition follows established pattern; each requirement maps to clear deliverable
- Pitfalls: HIGH -- all pitfalls derived from actual code review of Phase 44/45 changes and personal understanding of the gambling burn mechanism
- Economic analysis approach: MEDIUM -- preliminary EV estimates need formal derivation in ECON-01

**Research date:** 2026-03-21
**Valid until:** 2026-04-07 (stable -- no code changes expected before Phase 48)
