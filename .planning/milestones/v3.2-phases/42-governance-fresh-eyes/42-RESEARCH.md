# Phase 42: Governance Fresh Eyes - Research

**Researched:** 2026-03-19
**Domain:** VRF swap governance security audit -- DegenerusAdmin.sol, sDGNRS-weighted voting, propose/vote/execute flow, cross-contract state consistency
**Confidence:** HIGH

## Summary

Phase 42 is a "fresh eyes" re-verification of the VRF coordinator swap governance system. The governance mechanism was comprehensively audited in Phase 24 (v2.1, 8 plans, 26 requirements) and produced three known accepted-risk findings (WAR-01, WAR-02, WAR-06) plus two fixed findings (GOV-07 CEI violation, VOTE-03 proposalCount overflow). Since v2.1, three significant code changes have been applied: (1) death clock pause removed (commit 73c50cb3), (2) `activeProposalCount` removed and replaced with per-address `activeProposalId` mapping plus `voidedUpTo` watermark (commit df1e9f78), and (3) `_executeSwap` CEI ordering fixed so `_voidAllActive` runs before external calls. The threshold initial value was also lowered from 60% to 50% (commit fd9dbad1).

The governance system is scoped narrowly: it only controls VRF coordinator rotation during extended VRF stalls. It cannot move ETH, modify game rules, or change prize pool accounting. The attack surface is therefore limited to: (a) swapping to a malicious VRF coordinator that returns predictable randomness, and (b) blocking legitimate VRF rotation when one is needed. The key security properties are that the system requires genuine community participation (sDGNRS-weighted voting), enforces meaningful stall thresholds (20h admin / 7d community), auto-invalidates on VRF recovery, and uses a decaying threshold to prevent indefinite lockout.

This phase must independently verify these properties hold against the current code (post-v2.1 changes), re-validate the three accepted-risk findings (WAR-01, WAR-02, WAR-06) as still accurate, and catalogue any new attack surfaces introduced by the code changes.

**Primary recommendation:** Structure the audit as three focused investigations: (1) full governance flow attack surface catalogue covering propose/vote/execute/timelock/veto, (2) timing attack re-evaluation against current code with post-v2.1 change analysis, (3) cross-contract state consistency verification across the four governance-relevant contracts. Produce a single findings document with severity classifications per requirement.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GOV-01 | VRF swap governance flow audited from fresh perspective -- all attack surfaces catalogued | DegenerusAdmin.sol governance flow analysis (800 lines), propose/vote/execute/kill/expire paths, access control verification, sDGNRS vote weight integrity |
| GOV-02 | Governance edge cases and timing attacks re-evaluated against current code | Post-v2.1 change analysis (death clock removal, activeProposalCount replacement, CEI fix, threshold change), stall timing windows, threshold decay exploitation scenarios |
| GOV-03 | Cross-contract governance interactions verified (Admin, GameStorage, AdvanceModule, DegenerusStonk) | updateVrfCoordinatorAndSub state reset verification, lastVrfProcessedTimestamp lifecycle, unwrapTo vote-stacking guard, circulatingSupply accounting, sDGNRS soulbound invariant |
</phase_requirements>

## Standard Stack

This is a security audit phase, not an implementation phase. The "stack" is the audit methodology and the contracts under review.

### Contracts Under Review (Primary)
| Contract | File | Lines | Governance Role |
|----------|------|-------|-----------------|
| DegenerusAdmin | `contracts/DegenerusAdmin.sol` | 800 | Core governance logic: propose, vote, execute, kill, expire, threshold, circulatingSupply |

### Contracts Under Review (Cross-Contract)
| Contract | File | Governance Interaction |
|----------|------|----------------------|
| DegenerusGameAdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` | `updateVrfCoordinatorAndSub` target (resets rngLockedFlag, vrfCoordinator, vrfSubscriptionId, vrfKeyHash, vrfRequestId, rngRequestTime, rngWordCurrent), `wireVrf` (deploy-only), `lastVrfProcessedTimestamp` setter |
| DegenerusGameStorage | `contracts/storage/DegenerusGameStorage.sol` | Storage layout for VRF state variables: vrfCoordinator, vrfSubscriptionId, vrfKeyHash, rngLockedFlag, lastVrfProcessedTimestamp |
| DegenerusStonk | `contracts/DegenerusStonk.sol` | `unwrapTo` vote-stacking guard (blocked when VRF stall > 5h); DGNRS->sDGNRS conversion path |
| StakedDegenerusStonk | `contracts/StakedDegenerusStonk.sol` | Vote weight source (sDGNRS.balanceOf), circulatingSupply calculation (totalSupply - self-held - DGNRS-held), soulbound property (no transfer function) |
| DegenerusGame | `contracts/DegenerusGame.sol` | Delegatecall dispatcher for `updateVrfCoordinatorAndSub`, `lastVrfProcessed()` view |

### Audit Tooling
| Tool | Purpose |
|------|---------|
| Manual code trace | Primary method -- follow all governance state transitions |
| Prior audit reference | Phase 24 findings (WAR-01, WAR-02, WAR-06, GOV-07, VOTE-03) as baseline |
| v3.1/v3.2 comment scan results | DegenerusAdmin comment audit from Phase 40 P01 (all NatSpec verified, 1 new INFO finding) |

## Architecture Patterns

### Governance Flow State Machine

```
IDLE (no stall)
    |
    | VRF stall > 20h (admin) or > 7d (community)
    v
PROPOSE --> Proposal created (Active state)
    |           |-- proposer must hold DGVE (admin) or 0.5%+ circulating sDGNRS (community)
    |           |-- 1-per-address active proposal limit
    |           |-- circulatingSnapshot recorded at creation time
    v
VOTE --> sDGNRS holders approve/reject
    |       |-- votes changeable (old weight subtracted, new weight added)
    |       |-- live sDGNRS balance used as weight (not snapshot)
    |       |-- stall re-checked every vote (auto-invalidation if VRF recovers)
    |       |-- expiry checked every vote (168h from creation)
    |       |-- after each vote: check execute/kill thresholds
    v
RESOLVE --> One of:
    |-- EXECUTE: approveWeight * BPS >= threshold * circulatingSnapshot AND approveWeight > rejectWeight
    |       |-- _voidAllActive kills all other proposals (CEI: before external calls)
    |       |-- Cancel old VRF subscription (try/catch)
    |       |-- Create new subscription on proposed coordinator
    |       |-- Add Game as consumer
    |       |-- Push config to Game (updateVrfCoordinatorAndSub)
    |       |-- Transfer LINK balance to new subscription
    |
    |-- KILL: rejectWeight > approveWeight AND rejectWeight * BPS >= threshold * circulatingSnapshot
    |
    |-- EXPIRE: 168h elapsed since creation (set on next vote attempt)
    |
    |-- AUTO-INVALIDATE: VRF recovers (stall < 20h, checked on next vote)
```

### Threshold Decay Schedule

```
Time since proposal creation:
  0-48h:   50% (5000 BPS)
  48-72h:  40% (4000 BPS)
  72-96h:  30% (3000 BPS)
  96-120h: 20% (2000 BPS)
  120-144h: 10% (1000 BPS)
  144-168h: 5% (500 BPS)
  168h+:   0 (expired)
```

### Vote Weight Source: sDGNRS (Soulbound)

```
Vote weight = sDGNRS.balanceOf(voter)

sDGNRS is SOULBOUND -- no transfer() function exists.
Weight can only change via:
  1. Game reward pool distributions (transferFromPool, onlyGame)
  2. Burning sDGNRS to claim backing assets
  3. DGNRS.unwrapTo() -- BLOCKED when VRF stall > 5h
  4. Pool burn at game over (burnRemainingPools, onlyGame)

circulatingSupply = sDGNRS.totalSupply()
                  - sDGNRS.balanceOf(SDGNRS)    // undistributed pools held by contract itself
                  - sDGNRS.balanceOf(DGNRS)     // DGNRS wrapper allocation
```

### Post-v2.1 Changes (Must Verify)

| Change | What was removed/changed | What replaced it | Security implication |
|--------|--------------------------|------------------|---------------------|
| Death clock pause | `anyProposalActive()` function, death clock interaction | Nothing -- feature deleted | Proposals no longer affect game liveness timer. Simplification, removes complexity. |
| activeProposalCount | `uint8 activeProposalCount` state variable, increment/decrement logic | Per-address `activeProposalId` mapping, 1-per-address limit check in `propose()` | Eliminates VOTE-03 (uint8 overflow at 256) entirely. Limits spam but does not eliminate it (each address can still have 1 active). |
| _executeSwap CEI | `_voidAllActive` ran after some external calls | `_voidAllActive` runs immediately after state change (line 568), before all external calls | Fixes GOV-07. State mutations complete before external interactions. |
| Threshold decay | 60% starting value, 24h first tier | 50% starting, no 24h tier | Lower initial barrier. Community needs less participation to pass proposals. |
| voidedUpTo watermark | `_voidAllActive` scanned from proposal 1 every time | `_voidAllActive` scans from `voidedUpTo + 1` | Gas optimization for WAR-06 spam-propose scenario. Does not eliminate WAR-06 but reduces its gas impact. |

### Access Control Matrix

```
propose()       -- public: DGVE holder (admin path) or 0.5%+ sDGNRS holder (community path)
vote()          -- public: any sDGNRS holder (weight > 0)
canExecute()    -- view: anyone
threshold()     -- view: anyone
circulatingSupply() -- view: anyone
shutdownVrf()   -- GAME only
onTokenTransfer() -- LINK_TOKEN only
setLinkEthPriceFeed() -- onlyOwner (DGVE >50.1%)
swapGameEthForStEth() -- onlyOwner
stakeGameEthToStEth() -- onlyOwner
setLootboxRngThreshold() -- onlyOwner
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Governance attack surface enumeration | Ad-hoc reading of propose/vote | Systematic state transition analysis covering all 4 terminal states (Executed, Killed, Expired, auto-invalidated) | Missing a transition path could miss an attack vector |
| Vote weight manipulation analysis | Checking only direct transfer | Full sDGNRS movement audit (game rewards, burn, unwrapTo, pool operations) during VRF stall conditions | The soulbound property is the key security assumption; must verify it holds completely |
| Cross-contract state consistency | Checking updateVrfCoordinatorAndSub in isolation | Trace full state reset (6 variables) and verify no stale state persists across the swap | A partial reset could leave rngLockedFlag or vrfRequestId in exploitable state |

## Common Pitfalls

### Pitfall 1: Assuming sDGNRS Supply Changes During VRF Stall
**What goes wrong:** Analyst assumes vote weights can be manipulated by acquiring sDGNRS during a stall.
**Why it happens:** sDGNRS is soulbound but the analyst forgets to check all movement paths.
**How to avoid:** Enumerate ALL sDGNRS balance-changing operations: (1) game pool distributions -- require `advanceGame` which needs VRF, so blocked during stall, (2) burn -- reduces supply, helps defenders not attackers, (3) `unwrapTo` -- blocked at 5h, before 20h governance threshold, (4) pool operations -- onlyGame. During a genuine stall, sDGNRS balances are effectively frozen.
**Warning signs:** Not explicitly verifying the unwrapTo 5h guard vs 20h governance threshold.

### Pitfall 2: Treating circulatingSnapshot as a Snapshot of Individual Balances
**What goes wrong:** Analyst confuses `circulatingSnapshot` (aggregate supply at proposal time) with per-voter balance snapshots.
**Why it happens:** The name "snapshot" suggests ERC20Snapshot-style per-address snapshots.
**How to avoid:** Recognize that `circulatingSnapshot` is a single `uint256` stored once at proposal creation. Vote weights use LIVE `sDGNRS.balanceOf(msg.sender)` -- the snapshot is only for the threshold denominator. This is safe because sDGNRS is soulbound and effectively frozen during stalls.
**Warning signs:** Analyst looking for snapshot mechanisms that don't exist.

### Pitfall 3: Missing the Auto-Invalidation Check Location
**What goes wrong:** Analyst thinks proposals persist after VRF recovery because there's no explicit "cancel all" function.
**Why it happens:** The auto-invalidation is embedded IN the `vote()` function's stall re-check (line 454-456), not in a separate function.
**How to avoid:** Recognize that every `vote()` call re-checks the stall condition. If VRF has recovered (stall < 20h), the vote reverts with `NotStalled()`. No one can vote or execute, so Active proposals become effectively dead (eventually expiring after 168h).
**Warning signs:** Looking for a standalone cancellation mechanism.

### Pitfall 4: Overlooking the voidedUpTo Watermark Off-by-One
**What goes wrong:** Analyst assumes `_voidAllActive` correctly voids ALL proposals but misses edge cases in the watermark logic.
**Why it happens:** The watermark (`voidedUpTo`) is set to `count` after voiding, and scanning starts from `voidedUpTo + 1`. If a proposal is created between the voiding and the watermark update, it could be missed.
**How to avoid:** Verify that `_voidAllActive` runs atomically (no external calls between the loop and the watermark update at line 639). In the current code, the entire function is a simple loop + assignment with no external calls, so this is safe.
**Warning signs:** Not checking whether the loop + watermark update can be interrupted.

### Pitfall 5: Confusing DGVE Owner vs sDGNRS Voter Roles
**What goes wrong:** Analyst conflates the admin path (DGVE >50.1% holder via vault.isVaultOwner) with governance voting (sDGNRS holders).
**Why it happens:** Both involve token-weighted participation but use different tokens and different mechanisms.
**How to avoid:** Keep the two paths clearly separated: (1) Admin path: `vault.isVaultOwner(msg.sender)` at line 421, requires DGVE majority, only gate is the stall threshold (20h), no voting needed; (2) Community path: requires 0.5%+ circulating sDGNRS, stall threshold 7d. BOTH paths create proposals that require sDGNRS-weighted voting to execute.
**Warning signs:** Assuming DGVE holders can unilaterally execute proposals.

## Code Examples

### Governance State Transitions (from DegenerusAdmin.sol)

```solidity
// Source: contracts/DegenerusAdmin.sol

// PROPOSE (line 398-445):
// - Checks: subscriptionId != 0, !gameOver, newCoordinator != 0, newKeyHash != 0
// - 1-per-address check: activeProposalId[msg.sender] must be 0 or non-active/expired
// - Stall check: admin path (20h) or community path (7d + 0.5% sDGNRS)
// - Creates: Proposal with state=Active (default 0), records circulatingSnapshot

// VOTE (line 452-517):
// - Stall re-check (auto-invalidation gate)
// - Proposal must be Active and not expired
// - Weight from live sDGNRS.balanceOf(msg.sender)
// - Handle vote change: subtract old weight, add new weight
// - After recording: check execute condition (approve >= threshold% AND approve > reject)
// - After recording: check kill condition (reject > approve AND reject >= threshold%)

// EXECUTE (line 563-624):
// 1. p.state = Executed
// 2. _voidAllActive(proposalId)  -- CEI: all state changes before external calls
// 3. Cancel old subscription (try/catch)
// 4. Create new subscription on proposed coordinator
// 5. Add Game as consumer
// 6. Push config to Game via updateVrfCoordinatorAndSub
// 7. Transfer LINK to new subscription (try/catch)
```

### updateVrfCoordinatorAndSub State Reset (from AdvanceModule)

```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol, lines 1258-1276

function updateVrfCoordinatorAndSub(
    address newCoordinator,
    uint256 newSubId,
    bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(newCoordinator);  // New coordinator
    vrfSubscriptionId = newSubId;                       // New sub ID
    vrfKeyHash = newKeyHash;                            // New key hash

    // Reset RNG state to allow immediate advancement
    rngLockedFlag = false;           // Unlock RNG
    vrfRequestId = 0;                // Clear pending request
    rngRequestTime = 0;              // Clear request time
    rngWordCurrent = 0;              // Clear any pending word
    emit VrfCoordinatorUpdated(current, newCoordinator);
}
// NOTE: Does NOT update lastVrfProcessedTimestamp -- stall timer continues until
// new coordinator successfully processes a VRF request via advanceGame/wireVrf
```

### unwrapTo Vote-Stacking Guard (from DegenerusStonk)

```solidity
// Source: contracts/DegenerusStonk.sol, lines 149-158

function unwrapTo(address recipient, uint256 amount) external {
    if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();
    if (recipient == address(0)) revert ZeroAddress();
    // Block unwrap during VRF stall (prevents creator vote-stacking)
    if (block.timestamp - IDegenerusGame(ContractAddresses.GAME).lastVrfProcessed() > 5 hours)
        revert Unauthorized();
    _burn(msg.sender, amount);
    stonk.wrapperTransferTo(recipient, amount);
    emit UnwrapTo(recipient, amount);
}
// SECURITY: 5h threshold < 20h admin governance threshold
// Creator cannot convert DGNRS->sDGNRS to gain vote weight once governance becomes eligible
```

## Known Issues to Re-Verify

These three findings from Phase 24 must be confirmed still accurate against current code:

### WAR-01: Compromised Admin + 7-Day Inattention
**Original finding (MEDIUM, Accepted Risk):** A compromised admin key (DGVE >50.1% holder) can propose a malicious VRF coordinator after 20h stall. If the sDGNRS community does not vote to reject within the 7-day proposal lifetime AND the threshold decays below whatever approve weight the attacker accumulates, the swap executes.
**What to verify:** (1) Admin path still requires 20h stall and DGVE majority, (2) community can still kill proposals with reject > approve + threshold met, (3) no new path bypasses the vote requirement, (4) threshold decay schedule unchanged (50%->5%), (5) proposal lifetime still 168h.

### WAR-02: Colluding Voter Cartel at Day-6 Threshold
**Original finding (MEDIUM, Accepted Risk):** A cartel holding >= 5% circulating sDGNRS can approve a malicious swap at day 6 (threshold = 5%) if no opposition votes. Requires genuine VRF stall (20h+) and enough sDGNRS to meet the decayed threshold.
**What to verify:** (1) Threshold at 144-168h is indeed 500 BPS (5%), (2) approve > reject requirement still exists (cartel needs STRICTLY more than reject weight), (3) circulatingSnapshot is from proposal creation (cannot be manipulated), (4) sDGNRS is still frozen during stall (unwrapTo blocked, game distributions require VRF).

### WAR-06: Admin Spam-Propose Gas Griefing
**Original finding (LOW, Known Issue):** An admin (DGVE holder) can create many proposals, bloating the `_voidAllActive` loop. When a legitimate proposal executes, the loop must iterate over all active proposals.
**What to verify:** (1) voidedUpTo watermark mitigates gas cost (scans from watermark, not 1), (2) 1-per-address limit constrains spam per address (attacker needs multiple DGVE-holding addresses), (3) gas cost is still bounded by proposalCount, (4) no new mitigation exists beyond watermark.

## Previously Fixed Findings to Confirm Still Fixed

### GOV-07: _executeSwap CEI Violation (LOW, Fixed)
**Original:** External calls (cancelSubscription, createSubscription) happened before `_voidAllActive`.
**Current code:** `_voidAllActive(proposalId)` at line 568 runs IMMEDIATELY after `p.state = ProposalState.Executed` (line 565), before any external calls. CEI fix confirmed in current code.

### VOTE-03: uint8 activeProposalCount Overflow (LOW, Fixed)
**Original:** `uint8 activeProposalCount` would overflow to 0 at 256 proposals.
**Current code:** `activeProposalCount` variable does not exist. Replaced by `activeProposalId` mapping with per-address 1-proposal limit. Fix confirmed in current code.

## Attack Surface Catalogue (For Planner Reference)

### Propose Phase Attack Surfaces
1. **Stall fabrication:** Can an attacker cause a VRF stall? No -- VRF is Chainlink-external, stall = coordinator failure. Attacker cannot control Chainlink uptime.
2. **Stall measurement manipulation:** Can `lastVrfProcessed()` be manipulated? Only set in `_applyDailyRng` (line 1360) and `wireVrf` (line 402), both via AdvanceModule. No external manipulation path.
3. **Community proposal with insufficient stake:** `circulatingSupply()` could return 0 if all sDGNRS is undistributed or in DGNRS wrapper. Check: `if (circ == 0 || ...)` at line 427 handles this (reverts).
4. **Malicious coordinator address:** Proposer provides arbitrary address. No validation that it's a real VRF coordinator. This is by-design: governance assumes sDGNRS voters vet the proposal.

### Vote Phase Attack Surfaces
5. **Vote weight inflation via sDGNRS acquisition:** During stall, can an attacker acquire sDGNRS? Checked above: game distributions blocked (need VRF), unwrapTo blocked (5h guard), burn reduces supply. sDGNRS is effectively frozen.
6. **Double-voting via vote change:** Voter changes from approve to reject. Old weight subtracted, new weight added. Arithmetic checked: `p.approveWeight -= oldWeight` uses checked arithmetic (Solidity 0.8.34). No underflow possible if accounting is correct.
7. **Front-running execute with reject vote:** Attacker sees approve threshold about to be met, front-runs with a large reject vote. This is a feature (reject voters can block execution).
8. **Flash loan sDGNRS:** sDGNRS is soulbound -- no transfer function, no lending/borrowing possible.

### Execute Phase Attack Surfaces
9. **Reentrancy during execution:** `_voidAllActive` runs before external calls (CEI fixed). External calls use try/catch. No callback to DegenerusAdmin from VRF coordinator creation. updateVrfCoordinatorAndSub is a delegatecall on Game, which checks `msg.sender == ADMIN` -- no reentrant path back to Admin.
10. **Partial execution failure:** try/catch on cancelSubscription and LINK transfer. If old coordinator is malicious and cancelSubscription reverts, execution continues. If new coordinator is malicious and createSubscription reverts... this is unrecoverable (no try/catch on createSubscription at line 590-591). This is intentional: if the proposed coordinator is non-functional, the swap should fail.
11. **State consistency after swap:** Check that ALL 6 state variables in AdvanceModule are reset (vrfCoordinator, vrfSubscriptionId, vrfKeyHash, rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent). Note: `lastVrfProcessedTimestamp` is NOT reset, which means the stall timer continues until the new coordinator actually processes a request. This could trigger another governance round if the new coordinator also fails.

### Timing Attack Surfaces
12. **Threshold decay manipulation:** Attacker creates proposal, waits for threshold to decay to 5% (day 6), then votes with small sDGNRS holding. Requires genuine stall persisting for 144+ hours AND sDGNRS holding >= 5% circulating. This IS WAR-02.
13. **Proposal expiry race:** At exactly 168h, proposal expires. A voter calling vote() at T-1 second executes; at T the vote reverts with ProposalExpired. Block timestamp granularity is ~12 seconds on XRPL EVM. Not exploitable beyond normal block timing.
14. **Stall recovery race:** VRF recovers at exactly 20h mark. A voter calling vote() at block with timestamp < 20h after lastVrfProcessed gets NotStalled. This is correct behavior.

## State of the Art

| Old Approach (v2.1) | Current Approach (post-v2.1) | When Changed | Impact |
|----------------------|------------------------------|--------------|--------|
| uint8 activeProposalCount | Per-address activeProposalId mapping | commit df1e9f78 | Eliminates VOTE-03 overflow |
| _voidAllActive scans from 1 | voidedUpTo watermark optimization | commit df1e9f78 | Reduces WAR-06 gas impact |
| _executeSwap: CEI violation | _voidAllActive before external calls | commit df1e9f78 | Fixes GOV-07 |
| Death clock pause on active proposals | Feature removed entirely | commit 73c50cb3 | Simplification, removes attack surface |
| 60% initial threshold (24h first tier) | 50% initial threshold (48h first tier) | commit fd9dbad1 | Lower barrier for governance participation |

## Open Questions

1. **lastVrfProcessedTimestamp not reset on governance swap**
   - What we know: `updateVrfCoordinatorAndSub` resets 6 VRF state variables but NOT `lastVrfProcessedTimestamp`.
   - What's unclear: If the new coordinator is valid but slow to respond, the stall timer continues from the ORIGINAL stall. This means governance could immediately trigger again for the new coordinator even though it just swapped.
   - Recommendation: Verify whether this is intentional or a gap. It may be by-design: if the new coordinator also doesn't respond, governance should be able to swap again. But it also means a successful swap that takes time to fund/configure could face premature governance activity.
   - Confidence: MEDIUM -- likely intentional but worth explicit verification

2. **createSubscription not wrapped in try/catch**
   - What we know: In `_executeSwap`, `cancelSubscription` (line 578-585) and `linkToken.transferAndCall` (line 615-620) use try/catch, but `createSubscription` (line 590-591) and `addConsumer` (line 598-601) do NOT.
   - What's unclear: If the proposed coordinator's `createSubscription` reverts, the entire `_executeSwap` reverts. The proposal state has already been set to Executed and `_voidAllActive` has killed other proposals -- but since the entire transaction reverts, none of those state changes persist.
   - Recommendation: Confirm this is intentional. A reverting `createSubscription` means the proposed coordinator is non-functional, so the swap SHOULD fail and all state changes SHOULD revert. This is correct behavior.
   - Confidence: HIGH -- this is the correct design

3. **circulatingSupply can change between propose and execute**
   - What we know: `circulatingSnapshot` is recorded at proposal creation time. But `circulatingSupply()` changes if sDGNRS is burned (totalSupply decreases). During a long stall, holders might burn sDGNRS for backing assets.
   - What's unclear: If circulating supply decreases after snapshot, the threshold becomes EASIER to meet (fixed snapshot denominator, lower circulating supply means fewer tokens needed). Is this an attack vector?
   - Recommendation: Analyze whether burning sDGNRS during a stall can meaningfully lower the effective threshold. Burning sDGNRS removes voting weight from the burner while keeping the threshold denominator unchanged. This HELPS attackers only if the burned sDGNRS was from OPPOSING voters. If an attacker burns their own sDGNRS, they lose voting power while the snapshot stays the same.
   - Confidence: MEDIUM -- need explicit analysis of who benefits from burns during stall

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (JS tests) + Foundry (Solidity fuzz/invariant) |
| Config file | `hardhat.config.js` + `foundry.toml` |
| Quick run command | `npx hardhat test test/unit/DegenerusGame.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GOV-01 | Attack surface catalogue for governance flow | manual-only | N/A -- security audit producing written catalogue | N/A |
| GOV-02 | Timing attacks re-evaluated against current code | manual-only | N/A -- code trace audit with post-v2.1 change analysis | N/A |
| GOV-03 | Cross-contract governance interactions verified | manual-only | N/A -- state consistency trace across 5 contracts | N/A |

**Justification for manual-only:** This phase is a security audit producing written findings. The deliverables are attack surface catalogues, timing attack analyses, and cross-contract state consistency proofs -- not code changes that need automated testing. Existing tests provide baseline coverage; this phase verifies correctness through independent analysis.

### Sampling Rate
- **Per task commit:** Verify audit document covers all required attack surfaces and scenarios
- **Per wave merge:** Cross-reference findings against all 3 requirement IDs (GOV-01, GOV-02, GOV-03)
- **Phase gate:** All GOV-01 through GOV-03 have explicit verdicts, WAR-01/02/06 re-verified

### Wave 0 Gaps
None -- this is an audit phase producing documents, not code. Existing test infrastructure is sufficient for validation reference.

## Sources

### Primary (HIGH confidence)
- **Contract source code** (current HEAD): DegenerusAdmin.sol (800 lines), DegenerusGameAdvanceModule.sol (updateVrfCoordinatorAndSub, wireVrf, lastVrfProcessedTimestamp), DegenerusGameStorage.sol (VRF state variables), DegenerusStonk.sol (unwrapTo), StakedDegenerusStonk.sol (soulbound mechanics)
- **DegenerusGame.sol**: Delegatecall dispatcher for updateVrfCoordinatorAndSub
- **v3.1 findings**: audit/v3.1-findings-31-core-game-contracts.md (4 DegenerusAdmin findings: CMT-001, CMT-002, DRIFT-001, DRIFT-002)
- **v3.2 findings**: audit/v3.2-findings-40-core-game-contracts.md (DegenerusAdmin: all 4 v3.1 fixes verified, 1 new INFO finding NEW-001)
- **Prior audit**: PAYOUT-SPECIFICATION.html (WAR-01, WAR-02, WAR-06, GOV-07, VOTE-03 from Phase 24)

### Secondary (MEDIUM confidence)
- **Phase 38 research**: RNG delta security context, rngLocked consumer inventory (relevant for updateVrfCoordinatorAndSub state reset verification)
- **KNOWN-ISSUES.md**: VRF swap governance is documented as intentional design

### Tertiary (LOW confidence)
- None -- all findings based on direct code analysis

## Metadata

**Confidence breakdown:**
- Governance flow analysis: HIGH -- full source code available, 800-line contract fully read, all state transitions traced
- Post-v2.1 changes: HIGH -- all four code changes verified in current source (death clock removal, activeProposalCount replacement, CEI fix, threshold change)
- Cross-contract interactions: HIGH -- all 5 contracts read, updateVrfCoordinatorAndSub state reset fully traced (6 variables), unwrapTo guard verified
- Known issues re-verification: HIGH -- WAR-01, WAR-02, WAR-06 conditions all verifiable from current source code

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (30 days -- contract code is stable, no expected changes during audit)
