# Phase 24: Core Governance Security Audit - Research

**Researched:** 2026-03-17
**Domain:** Solidity smart contract security audit -- governance, vote arithmetic, storage layout, cross-contract interactions, adversarial scenarios
**Confidence:** HIGH

## Summary

Phase 24 is a comprehensive security audit of the VRF governance system added in v2.1 (the M-02 mitigation). The audit domain spans five contracts: DegenerusAdmin (governance hub), DegenerusGameAdvanceModule (death clock pause, `lastVrfProcessedTimestamp` writes, `updateVrfCoordinatorAndSub`), DegenerusGameStorage (storage layout), DegenerusGame (delegatecall routing, `lastVrfProcessed()` view), and DegenerusStonk (unwrapTo stall guard). The audit must be adversarial -- the same team wrote this code, so confirmation bias (CP-01) is the top procedural risk.

There are 26 requirements across 5 categories: governance core (GOV-01 through GOV-10), cross-contract interactions (XCON-01 through XCON-05), vote integrity (VOTE-01 through VOTE-03), war-game scenarios (WAR-01 through WAR-06), and M-02 closure (M02-01, M02-02). Each requires a written verdict with evidence. The audit produces no code changes -- it produces written analysis, test verdicts, and severity ratings.

**Primary recommendation:** Structure the audit in waves: storage/layout verification first (GOV-01, blocking), then function-by-function verdicts (GOV-02 through GOV-10, VOTE-*), then cross-contract traces (XCON-*), then war-game scenarios (WAR-*), and finally M-02 closure. Each verdict must cite specific code lines and test evidence.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GOV-01 | Storage layout -- `lastVrfProcessedTimestamp` at safe slot, no collisions | Storage layout analysis below; slot computation methodology; `storageLayout` compiler output available |
| GOV-02 | `propose()` access control -- admin/community paths correctly gated | Code analysis of lines 394-431 DegenerusAdmin.sol; existing tests in VRFGovernance.test.js |
| GOV-03 | `vote()` arithmetic -- changeable votes, no double-counting or weight leakage | Vote change logic at lines 461-481; requires adversarial weight-tracking analysis |
| GOV-04 | Threshold decay -- discrete daily steps match spec | `threshold()` function at lines 524-534; 8 test cases already exist |
| GOV-05 | Execute condition -- overflow/truncation analysis | Line 489: `approveWeight * BPS >= uint256(t) * circulatingSnapshot && approveWeight > p.rejectWeight` |
| GOV-06 | Kill condition -- symmetric with execute | Line 498-500: symmetric structure, same overflow analysis needed |
| GOV-07 | `_executeSwap()` CEI compliance, reentrancy via malicious coordinator | Lines 558-619; state set to Executed before external calls; 5 external calls follow |
| GOV-08 | `_voidAllActive()` correctness | Lines 622-632; sets `activeProposalCount = 0` directly |
| GOV-09 | Proposal expiry -- state transition and counter decrement | Lines 449-453; expiry triggered on vote attempt |
| GOV-10 | `circulatingSupply()` exclusion correctness | Lines 514-518; subtracts SDGNRS and DGNRS self-balances |
| XCON-01 | `lastVrfProcessedTimestamp` write paths exhaustive | Only in `_applyDailyRng()` (line 1374) and `wireVrf()` (line 407) of AdvanceModule |
| XCON-02 | Death clock pause via `anyProposalActive()` | `_handleGameOverPath()` lines 430-436; try/catch handles Admin revert |
| XCON-03 | `unwrapTo` stall guard boundary analysis | DegenerusStonk.sol line 151: `> 20 hours` (strict greater-than) |
| XCON-04 | `updateVrfCoordinatorAndSub` -- `_threeDayRngGap` removal verified | AdvanceModule lines 1272-1290; no `_threeDayRngGap` check, only ADMIN gate |
| XCON-05 | VRF retry timeout 18h->12h verification | `rngGate()` line 786: `elapsed >= 12 hours` |
| VOTE-01 | sDGNRS supply frozen during VRF stall | Must enumerate all balance-mutation paths and verify blocked |
| VOTE-02 | `circulatingSnapshot` immutable after proposal creation | Stored in Proposal struct at creation, never written again |
| VOTE-03 | `activeProposalCount` uint8 overflow analysis | `unchecked { activeProposalCount++; }` at line 428 |
| WAR-01 | Compromised admin key scenario | Admin proposes malicious coordinator; community threshold decay enables rejection |
| WAR-02 | Colluding voter cartel at low threshold | Day 6 = 5% threshold; practical exploitability depends on sDGNRS distribution |
| WAR-03 | VRF oscillation attack -- stall/recovery/repeat DoS | Stall -> governance -> recovery -> proposals invalidated -> repeat |
| WAR-04 | Creator unwrapTo timing attack | Exact 20h boundary analysis; DGNRS->sDGNRS conversion blocked during stall |
| WAR-05 | Post-execute governance loop | `lastVrfProcessedTimestamp` not reset in `updateVrfCoordinatorAndSub`; `_executeSwap` only resets RNG state |
| WAR-06 | Admin spam-propose gas griefing | No per-proposer cooldown; `_voidAllActive` gas with N proposals |
| M02-01 | Original M-02 attack mitigated by governance | `emergencyRecover` replaced by propose/vote/execute |
| M02-02 | Severity re-assessment with residual risk | Governance adds community path; threshold decay limits attacker window |
</phase_requirements>

## Standard Stack

### Core Audit Toolchain
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Hardhat | project-installed | Test execution, storage layout output | Already configured with `storageLayout` output selection |
| Chai/Mocha | project-installed | Assertion framework for test verdicts | 414+ existing tests use this stack |
| Solidity 0.8.34 | compiler | Source of truth for overflow behavior, storage layout rules | Project compiler version |

### Supporting Analysis Tools
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `hardhat compile` with `storageLayout` | Verify exact slot positions for GOV-01 | First task -- blocking all other work |
| Manual code trace | CEI verification, state transition analysis | GOV-07, XCON-* requirements |
| Existing test suite | Evidence for verdicts | Run specific test files per requirement |

**No additional libraries needed.** This is a pure audit phase -- analysis and documentation, no code changes.

## Architecture Patterns

### Audit Verdict Format
Each requirement needs a structured verdict document. Recommended pattern:

```markdown
### [REQ-ID]: [Title]
**Verdict:** PASS / FAIL / KNOWN-ISSUE
**Severity:** N/A / Low / Medium / High / Critical
**Evidence:**
- Code: [file:line references]
- Tests: [test file:describe:it references]
- Traces: [cross-contract interaction trace]
**Analysis:** [detailed reasoning]
**Adversarial check:** [what attack was attempted, why it fails/succeeds]
```

### Adversarial Persona Protocol (CP-01 Mitigation)
The auditor must actively attempt to break each function before concluding it is correct:

1. **Assume the code is wrong** -- look for the bug first
2. **Attempt boundary violations** -- off-by-one in thresholds, exactly-at-boundary conditions
3. **Look for missing checks** -- what input validations are absent?
4. **Trace state changes** -- does every state mutation have the correct precondition?
5. **Question the "obvious"** -- re-derive any mathematical relationship from first principles
6. **Document the attack attempt** -- even failed attacks are evidence

### Audit Wave Structure
```
Wave 1: Storage Layout (GOV-01) -- BLOCKING
  |
Wave 2: Function Verdicts (GOV-02..GOV-10, VOTE-01..VOTE-03)
  |
Wave 3: Cross-Contract Traces (XCON-01..XCON-05)
  |
Wave 4: War Games (WAR-01..WAR-06)
  |
Wave 5: M-02 Closure (M02-01, M02-02)
```

### Anti-Patterns to Avoid
- **Confirmation bias audit:** Reading code to verify it works rather than trying to break it. Every verdict must document what attack was attempted.
- **Incomplete state transition analysis:** Checking only the happy path. Each function must have its full state space explored.
- **Trusting test coverage as proof:** Tests passing proves the tested paths work. An audit must identify untested paths.
- **Scope creep into non-governance code:** The audit scope is governance-related code only. Non-governance contracts were audited in v1.0-v2.0.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage slot computation | Manual byte counting | `hardhat compile` storageLayout JSON output | Compiler output is authoritative; manual counting is error-prone across 1600+ lines |
| Overflow analysis | Mental arithmetic | Solidity 0.8.34 overflow semantics + worst-case input ranges | Document max values: sDGNRS totalSupply fits uint256, BPS=10000, threshold max=6000 |
| CEI verification | Reading code once | Systematic trace: mark each SSTORE, mark each external CALL, verify ordering | `_executeSwap` has 5+ external calls; needs systematic approach |

## Common Pitfalls

### Pitfall 1: Ignoring the `unchecked` blocks
**What goes wrong:** Missing overflow vulnerabilities in `unchecked { activeProposalCount++; }` (line 428) and `unchecked { activeProposalCount--; }` (line 451).
**Why it happens:** `unchecked` is often used for gas optimization of "obviously safe" operations, but the safety assumption may be wrong.
**How to avoid:** Explicitly compute max values. `activeProposalCount` is uint8 (max 255). If 256 proposals are created without any being executed/killed/expired, `++` wraps to 0. This makes `anyProposalActive()` return false, potentially unpausing the death clock. This is VOTE-03 and must be analyzed in detail.
**Warning signs:** Any `unchecked` arithmetic on governance-critical counters.

### Pitfall 2: Confusing `>` and `>=` in boundary conditions
**What goes wrong:** The unwrapTo guard uses `> 20 hours` (DegenerusStonk line 151) while the vote stall check uses `< ADMIN_STALL_THRESHOLD` (20 hours, line 441). These create a 1-second window analysis.
**Why it happens:** Different contracts use different comparison operators for related time checks.
**How to avoid:** Map every time comparison across all 5 contracts. Document the exact boundary behavior at t=20h exactly.
**Warning signs:** `>` vs `>=` vs `<` vs `<=` inconsistencies across contracts for the same threshold.

### Pitfall 3: `_voidAllActive` sets `activeProposalCount = 0` directly
**What goes wrong:** `_voidAllActive` (line 632) hard-sets `activeProposalCount = 0` instead of decrementing. If the executed proposal was already decremented elsewhere, the count could be wrong.
**Why it happens:** The Executed proposal's state is set before `_voidAllActive` runs (line 560), but `activeProposalCount` is not decremented for it -- `_voidAllActive` handles all cleanup by setting to 0.
**How to avoid:** Trace the exact state of `activeProposalCount` through the `_executeSwap` -> `_voidAllActive` sequence. Verify no path exists where the count ends up non-zero when it should be zero, or vice versa.

### Pitfall 4: Reentrancy in `_executeSwap` via malicious coordinator
**What goes wrong:** `_executeSwap` calls `createSubscription()`, `addConsumer()`, and `updateVrfCoordinatorAndSub()` on user-supplied coordinator address. A malicious coordinator could reenter DegenerusAdmin.
**Why it happens:** The proposal's `coordinator` field is user-supplied (from `propose()`). If executed, this address receives external calls.
**How to avoid:** Verify that `p.state = ProposalState.Executed` (line 560) is set BEFORE any external calls. Verify that reentering `vote()` or `propose()` with the new state would be blocked.
**Warning signs:** State changes after external calls; missing state guards in reentrant paths.

### Pitfall 5: `circulatingSupply()` called twice in `propose()` with potentially different results
**What goes wrong:** `propose()` calls `circulatingSupply()` at line 412 (for community stake check) and again at line 424 (for snapshot). If a state change occurs between these calls, the values could differ.
**Why it happens:** Two calls to the same view function in the same transaction, but the function reads external state (sDGNRS balances).
**How to avoid:** Verify that no state mutation occurs between the two `circulatingSupply()` calls. In `propose()`, no external calls happen between lines 412 and 424 that could change sDGNRS balances.

### Pitfall 6: Vote weight uses live balances, not snapshots
**What goes wrong:** `vote()` reads `sDGNRS.balanceOf(msg.sender)` live (line 457). If sDGNRS is not truly frozen during a stall, a voter could transfer sDGNRS between accounts and vote multiple times.
**Why it happens:** The system relies on the invariant that sDGNRS supply is frozen during VRF stall (VOTE-01). If this invariant is broken, the entire vote integrity collapses.
**How to avoid:** VOTE-01 is the most critical verification. Must exhaustively enumerate every sDGNRS balance-mutation path and prove each is blocked during VRF stall.

## Code Examples

### Storage Layout Verification (GOV-01)
```bash
# Extract storage layout from compiler output
npx hardhat compile
# Then inspect artifacts/build-info/*.json for storageLayout
# Look for DegenerusGameStorage and find lastVrfProcessedTimestamp slot
```

`lastVrfProcessedTimestamp` is declared at line 1616 of DegenerusGameStorage.sol as the LAST variable in the contract. It is `uint48` (6 bytes). Since it follows several mappings (which each consume a full slot for their root), it will occupy its own slot. The exact slot number must be verified via compiler output.

Key concern: DegenerusGameStorage is inherited by DegenerusGame (which adds no storage) and all delegatecall modules. The `lastVrfProcessedTimestamp` variable is written by `_applyDailyRng()` and `wireVrf()`, both in DegenerusGameAdvanceModule, which executes in DegenerusGame's storage context via delegatecall. No collision risk from the module itself since modules inherit the same storage layout. But the slot must be verified as not overlapping with any DegenerusGame-declared storage.

### Vote Arithmetic Verification (GOV-03)
```solidity
// DegenerusAdmin.sol lines 461-481
// Adversarial trace for vote-change:
// 1. Voter votes Approve with weight=100
//    approveWeight += 100 (now 100)
//    votes[id][voter] = Approve, voteWeight[id][voter] = 100
//
// 2. Voter changes to Reject:
//    currentVote = Approve, oldWeight = 100
//    approveWeight -= 100 (back to 0) -- SUBTRACTION BEFORE ADD
//    votes[id][voter] = Reject, voteWeight[id][voter] = weight (live balance)
//    rejectWeight += weight
//
// Key question: if voter's sDGNRS balance changed between votes,
// oldWeight (from previous vote) != current weight. This is correct --
// the old weight is properly subtracted, new weight properly added.
// No double-counting possible IF sDGNRS is truly frozen.
```

### Cross-Contract Trace Template (XCON-01)
```
lastVrfProcessedTimestamp WRITE paths:
1. DegenerusGameAdvanceModule._applyDailyRng() [line 1374]
   - Called from: rngGate() [line 776] and two gameover RNG paths [lines 820, 837]
   - Trigger: successful VRF word processing
   - Sets to: uint48(block.timestamp)

2. DegenerusGameAdvanceModule.wireVrf() [line 407]
   - Called from: DegenerusAdmin constructor only
   - Access: msg.sender == ContractAddresses.ADMIN
   - Sets to: uint48(block.timestamp)

3. DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub() [line 1272-1290]
   - DOES NOT write lastVrfProcessedTimestamp
   - Only resets rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent
   - This is INTENTIONAL: after coordinator swap, the stall clock keeps running
     until the new coordinator fulfills a request and _applyDailyRng runs

READ paths (governance-relevant):
1. DegenerusGame.lastVrfProcessed() [line 2227-2228]
   - Pure view returning lastVrfProcessedTimestamp
   - Called by: DegenerusAdmin.propose(), DegenerusAdmin.vote(), DegenerusAdmin.canExecute()
   - Called by: DegenerusStonk.unwrapTo()
```

## State of the Art

| Old Approach (M-02 original) | Current Approach (v2.1 governance) | When Changed | Impact |
|------------------------------|-----------------------------------|--------------|--------|
| `emergencyRecover` -- single admin call after 3-day stall | propose/vote/execute -- sDGNRS-holder governance after 20h stall | v2.1 (current audit) | Admin cannot unilaterally swap VRF coordinator; community oversight required |
| 3-day VRF gap detection (`_threeDayRngGap`) | Time-based detection (`lastVrfProcessedTimestamp`) | v2.1 | More precise stall detection; 20h for admin, 7d for community |
| No death clock pause | `anyProposalActive()` pauses liveness guard | v2.1 | Governance has time to operate without game-over risk |
| No unwrapTo guard | `unwrapTo` blocked during VRF stall (>20h) | v2.1 | Prevents creator vote-stacking via DGNRS->sDGNRS conversion |
| 18h VRF retry timeout | 12h VRF retry timeout | v2.1 | Faster recovery from VRF failures |

**Deprecated/outdated:**
- `emergencyRecover`: Removed, replaced by governance. References must not remain in audit docs (DOCS-07, Phase 25 scope).
- `_threeDayRngGap` for governance: Retained for monitoring but governance uses `lastVrfProcessedTimestamp` instead.

## Open Questions

1. **`updateVrfCoordinatorAndSub` does NOT reset `lastVrfProcessedTimestamp`**
   - What we know: After a governance-executed coordinator swap, `lastVrfProcessedTimestamp` retains its old value. The stall clock keeps running.
   - What's unclear: Is this intentional to prevent immediate re-proposal after swap? Or is it a bug that could cause the death clock to trigger?
   - Recommendation: This is WAR-05. Analyze whether the stall condition persists after swap, and whether a new proposal can be created immediately. The death clock is paused by `anyProposalActive()` but after `_voidAllActive` sets `activeProposalCount = 0`, the pause lifts. If `lastVrfProcessedTimestamp` is stale, the death clock could immediately trigger. This needs deep analysis.

2. **uint8 `activeProposalCount` overflow at 256 proposals**
   - What we know: `unchecked { activeProposalCount++; }` wraps 255->0. This would make `anyProposalActive()` return false.
   - What's unclear: Practical exploitability. Each `propose()` requires a VRF stall and either DGVE ownership or 0.5% sDGNRS. Gas cost for 256 proposals during a single stall.
   - Recommendation: This is VOTE-03. Calculate exact gas cost. Even if gas is feasible, the attacker needs sDGNRS or DGVE for each call. May be LOW severity but must be documented.

3. **Malicious coordinator reentrancy in `_executeSwap`**
   - What we know: `p.state = ProposalState.Executed` is set at line 560 BEFORE external calls. This should prevent re-execution.
   - What's unclear: Whether a reentrant call to `vote()` on a different proposal could trigger a second `_executeSwap` for a sibling proposal, leading to state corruption.
   - Recommendation: This is GOV-07. Trace: reenter `vote()` -> proposal 2 meets execute threshold -> `_executeSwap(2)` -> state conflict with ongoing `_executeSwap(1)`. The second swap would try to cancel the subscription that was already cancelled in the first, plus `_voidAllActive` would run twice with conflicting `activeProposalCount` states.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Mocha + Chai (project-installed) |
| Config file | hardhat.config.js |
| Quick run command | `npx hardhat test test/unit/VRFGovernance.test.js` |
| Full suite command | `npx hardhat test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GOV-01 | Storage layout collision-free | manual | `npx hardhat compile` (inspect storageLayout JSON) | N/A -- compiler output |
| GOV-02 | `propose()` access control | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Yes -- 8 tests in "propose" describe |
| GOV-03 | `vote()` arithmetic | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Partial -- vote revert tests exist, but no weight-tracking test |
| GOV-04 | Threshold decay | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Yes -- 8 tests in "threshold decay" describe |
| GOV-05 | Execute condition | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Partial -- `canExecute` view tested, no execute-with-weight test |
| GOV-06 | Kill condition | unit | N/A | No -- kill path not tested |
| GOV-07 | `_executeSwap` CEI | unit + manual | N/A | No -- no execution test exists |
| GOV-08 | `_voidAllActive` | unit | N/A | No -- only tested indirectly |
| GOV-09 | Proposal expiry | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Yes -- 1 test in "proposal expiry" |
| GOV-10 | `circulatingSupply` | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Yes -- 1 test |
| XCON-01 | Write path enumeration | manual | Code trace | N/A |
| XCON-02 | Death clock pause | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Partial -- `anyProposalActive` tested, not death clock integration |
| XCON-03 | `unwrapTo` stall guard | unit | `npx hardhat test test/unit/VRFGovernance.test.js` | Yes -- 2 tests |
| XCON-04 | `_threeDayRngGap` removal | manual | Code trace | N/A |
| XCON-05 | VRF retry 12h timeout | unit | `npx hardhat test test/edge/RngStall.test.js` | Yes -- verified 12h works |
| VOTE-01 | sDGNRS frozen during stall | manual + unit | Code trace + test | Partial -- needs enumeration |
| VOTE-02 | `circulatingSnapshot` immutable | manual | Code trace | N/A |
| VOTE-03 | uint8 overflow analysis | manual | Arithmetic analysis | N/A |
| WAR-01 through WAR-06 | War-game scenarios | manual + POC | Written assessments | No dedicated tests |
| M02-01 | M-02 mitigated | manual | Cross-reference with original M-02 | N/A |
| M02-02 | Severity re-assessment | manual | Written analysis | N/A |

### Sampling Rate
- **Per task commit:** `npx hardhat test test/unit/VRFGovernance.test.js test/unit/DegenerusAdmin.test.js test/unit/GovernanceGating.test.js`
- **Per wave merge:** `npx hardhat test test/unit/ test/access/ test/edge/RngStall.test.js test/poc/NationState.test.js test/poc/Coercion.test.js`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] No test for vote execution path (GOV-05, GOV-06, GOV-07 need execution tests)
- [ ] No test for kill condition (GOV-06)
- [ ] No test for `_voidAllActive` with multiple proposals (GOV-08)
- [ ] No dedicated VOTE-01 test (sDGNRS frozen proof)
- [ ] No WAR-* tests (these may be manual-only verdict documents)

Note: This phase is primarily a documentation/analysis audit, not a code-change phase. Missing tests may be added as evidence for verdicts but are not Wave 0 blockers. The audit can proceed with manual code trace for requirements where tests are impractical.

## Key Technical Findings

### Finding 1: `_executeSwap` CEI Analysis (GOV-07)
**Confidence:** HIGH (direct code reading)

State change at line 560: `p.state = ProposalState.Executed` -- BEFORE all external calls.

External call sequence:
1. `IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription()` [line 571] -- try/catch
2. `IVRFCoordinatorV2_5Owner(newCoordinator).createSubscription()` [line 582]
3. `IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer()` [line 590]
4. `gameAdmin.updateVrfCoordinatorAndSub()` [line 597]
5. `linkToken.transferAndCall()` [line 608] -- try/catch
6. `_voidAllActive()` [line 618] -- internal, no external calls

The critical question is: can a malicious `newCoordinator` at call #2 or #3 reenter `vote()` for a sibling proposal and trigger a second `_executeSwap`?

Answer: The reentering `vote()` would pass the stall check (stall is still active). If it hits the execute condition for proposal 2, `_executeSwap(2)` would run. At this point:
- `coordinator` state variable was already updated to `newCoordinator` (line 581)
- `subscriptionId` was already updated (line 584)
- `_executeSwap(2)` would try to cancel the subscription created in step 1... which is the new subscription
- This is a real reentrancy concern that needs deep analysis

### Finding 2: `lastVrfProcessedTimestamp` NOT updated in `updateVrfCoordinatorAndSub` (WAR-05/XCON-01)
**Confidence:** HIGH (direct code reading)

`updateVrfCoordinatorAndSub()` at AdvanceModule lines 1272-1290 resets `rngLockedFlag`, `vrfRequestId`, `rngRequestTime`, and `rngWordCurrent` -- but NOT `lastVrfProcessedTimestamp`. This means:

After a governance-executed VRF swap:
- The stall timer keeps counting from the last successful RNG processing
- A new `propose()` call would still pass the stall check (stall > 20h)
- But `_voidAllActive()` just set `activeProposalCount = 0`, lifting the death clock pause
- The death clock would resume with the stale `lastVrfProcessedTimestamp`
- If the new coordinator is slow to produce a word, the death clock could trigger

This appears to be an intentional design choice -- the clock should only reset when RNG actually works (via `_applyDailyRng`). But the gap between swap-execution and first successful RNG from the new coordinator is a vulnerability window.

### Finding 3: uint8 `activeProposalCount` overflow (VOTE-03)
**Confidence:** HIGH (direct code reading)

`activeProposalCount` is `uint8` (max 255). `unchecked { activeProposalCount++; }` in `propose()` wraps at 256.

Impact: If `activeProposalCount` overflows to 0, `anyProposalActive()` returns false, which:
1. Unpauses the death clock (could trigger gameover during VRF stall)
2. Allows the game to die while governance is supposedly active

Exploitability: Each `propose()` requires passing the stall check and access control. The admin path needs >50.1% DGVE. The community path needs 0.5% sDGNRS + 7-day stall. Creating 256 proposals during a single stall:
- Admin: ~256 * ~100k gas = ~25.6M gas total. Feasible in multiple transactions during a multi-day stall.
- Community: Needs 7-day stall + 0.5% sDGNRS. Barely feasible if attacker has enough sDGNRS.
- Severity: Likely LOW-MEDIUM. Requires sustained VRF failure AND motivated attacker.

### Finding 4: `unwrapTo` Boundary at Exactly 20 Hours (XCON-03/WAR-04)
**Confidence:** HIGH (direct code reading)

DegenerusStonk line 151: `block.timestamp - lastVrfProcessed() > 20 hours`
- At exactly 20h: `20h - lastVrf = 72000 seconds`. `72000 > 72000` is FALSE. **unwrapTo is ALLOWED.**
- At 20h + 1s: `72001 > 72000` is TRUE. unwrapTo is BLOCKED.

DegenerusAdmin line 441: `block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD`
- ADMIN_STALL_THRESHOLD = 20 hours = 72000 seconds
- At exactly 20h: `72000 < 72000` is FALSE. Vote proceeds (stall confirmed).
- At 20h + 1s: `72001 < 72000` is FALSE. Vote proceeds.

This means at t=20h exactly:
- unwrapTo is ALLOWED (creator can convert DGNRS -> sDGNRS)
- Voting is ALSO allowed (governance is active)
- This is a 1-second race condition: creator can perform one unwrapTo in the exact second that governance activates

Impact: Creator could front-run the first governance vote by converting DGNRS to sDGNRS at the exact boundary. However, the amount is limited by their DGNRS balance, and sDGNRS is soulbound -- it goes to a specific recipient, not back to the creator's voting weight. Still needs WAR-04 analysis.

### Finding 5: `_voidAllActive` Gas with Many Proposals (WAR-06)
**Confidence:** HIGH (direct code reading)

`_voidAllActive` iterates from 1 to `proposalCount` (line 624). With N total proposals, this is O(N) storage reads. Even if most are already non-Active, each `proposals[i].state` read costs ~2100 gas (cold SLOAD). With 256 proposals: ~538K gas just for the loop. This is well within block gas limits but adds meaningful execution cost.

The real griefing vector is the gas cost of `propose()` itself being called many times. No per-proposer cooldown exists. An admin with DGVE could create proposals continuously during a stall, bloating `proposalCount` and increasing `_voidAllActive` cost for legitimate executions.

## Sources

### Primary (HIGH confidence)
- DegenerusAdmin.sol -- complete contract source (793 lines), read in full
- DegenerusGameAdvanceModule.sol -- governance-relevant sections (wireVrf, updateVrfCoordinatorAndSub, _handleGameOverPath, rngGate, _applyDailyRng)
- DegenerusGameStorage.sol -- full storage layout (1617 lines), lastVrfProcessedTimestamp at line 1616
- DegenerusStonk.sol -- unwrapTo function with VRF stall guard
- DegenerusGame.sol -- delegatecall routing functions, lastVrfProcessed view
- test/unit/VRFGovernance.test.js -- 32 passing tests covering propose, vote, threshold, expiry, circulatingSupply, death clock, unwrapTo guard
- test/unit/DegenerusAdmin.test.js -- 30+ tests covering constructor, price feed, onTokenTransfer, governance basics, shutdownVrf
- test/unit/GovernanceGating.test.js -- 20+ tests covering DGVE ownership, vault owner boundary, shutdownVrf access, advanceGame mint gate
- test/access/AccessControl.test.js -- systematic unauthorized caller checks
- test/edge/RngStall.test.js -- 18h->12h timeout, retry mechanics, stale request handling
- test/poc/Coercion.test.js -- admin key compromise threat model
- test/poc/NationState.test.js -- nation-state attacker with admin compromise + VRF failure

### Secondary (MEDIUM confidence)
- audit/FINAL-FINDINGS-REPORT.md -- M-02 original finding description, severity assessment, existing mitigations
- .planning/REQUIREMENTS.md -- Phase 24 requirement definitions
- .planning/STATE.md -- Project context, accumulated context, risk flags

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- this is an audit phase using existing project toolchain, no new dependencies
- Architecture: HIGH -- audit verdict format is well-defined, wave structure follows from dependency analysis
- Pitfalls: HIGH -- all pitfalls derived from direct code reading of the contracts under audit
- Technical findings: HIGH -- all from direct code analysis, not external sources

**Research date:** 2026-03-17
**Valid until:** Indefinite (contract source is immutable; findings are based on current code state)
