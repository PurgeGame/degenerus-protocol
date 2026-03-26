# Plan: Emergency VRF Coordinator Swap Governance

**Status:** Draft
**Spec:** `.planning/VRF-GOVERNANCE-SPEC.md` (save spec there too)

## Context

M-02 (the only Medium finding): if Chainlink VRF dies AND the admin key is compromised, the attacker controls all RNG. This replaces unilateral admin recovery with sDGNRS-holder governance.

## Architecture

**All governance logic in DegenerusAdmin.sol.** No new contract. Admin already has VRF subscription lifecycle, game interface, DGVE ownership, and a known address in ContractAddresses. Execution is an internal call — no cross-contract auth needed.

**Changes: DegenerusAdmin.sol (bulk), AdvanceModule (5 changes), GameStorage (1 var), Game.sol (1 view), DegenerusStonk.sol (1 guard).**

---

## DegenerusAdmin.sol — Governance Addition

### New Storage

```solidity
uint256 public proposalCount;
mapping(uint256 => Proposal) public proposals;
mapping(uint256 => mapping(address => Vote)) public votes;   // None/Approve/Reject
mapping(uint256 => mapping(address => uint256)) public voteWeight; // weight at time of vote
uint8 public activeProposalCount;

struct Proposal {
    address proposer;
    address coordinator;
    bytes32 keyHash;
    uint48 createdAt;
    uint256 approveWeight;
    uint256 rejectWeight;
    uint256 circulatingSnapshot; // snapshotted at creation, prevents burn manipulation
    ProposalPath path;           // Admin | Community
    ProposalState state;         // Active | Executed | Killed | Expired
}

enum Vote { None, Approve, Reject }
enum ProposalPath { Admin, Community }
enum ProposalState { Active, Executed, Killed, Expired }
```

### Functions

**`propose(address coordinator, bytes32 keyHash) external returns (uint256)`**
- Reads `game.lastVrfProcessed()`, computes elapsed time
- Admin path (DGVE >50.1%): requires 20h+ stall
- Community path (0.5%+ circulating sDGNRS): requires 7d+ stall
- Community path opens at 7d regardless of admin activity (independent)
- Validates coordinator != 0, keyHash != 0
- Snapshots `circulatingSupply` at creation time
- Increments `activeProposalCount`

**`vote(uint256 proposalId, bool approve) external`**
- Requires Active state, not expired (< 168h old)
- **Votes are changeable.** Voters can swap between Approve and Reject on the same proposal. This lets voters react to new information (e.g., learning a proposed coordinator is malicious). Old weight is subtracted before new weight is added.
- **Approval voting:** voters can vote on multiple proposals independently
- Weight = live `sDGNRS.balanceOf(msg.sender)` (safe: VRF dead = supply frozen, unwrapTo disabled)
- After recording vote, checks execute/kill:
  - **Execute:** `approve% >= threshold(t) AND approve% > reject%`
    → Internal `_executeSwap()`, void all other active proposals
  - **Kill:** `reject% > approve% AND reject% >= threshold(t)`
    → Mark Killed
- "Poke" mechanic: previous voter calls `vote()` again → no-op on vote, re-checks conditions as threshold decays
- **Stall re-check:** reverts if VRF recovered (stall < 20h). This IS the auto-cancellation.

**`_executeSwap(Proposal storage p) internal`**
- Same subscription lifecycle as old `emergencyRecover()`:
  1. Cancel old subscription (try/catch)
  2. Create new subscription on proposed coordinator
  3. Add Game as consumer
  4. Push config to Game via `gameAdmin.updateVrfCoordinatorAndSub()`
  5. Transfer LINK to new subscription
- Void all other active proposals, reset `activeProposalCount`

**`anyProposalActive() external view returns (bool)`**
- `activeProposalCount > 0` — used by death clock pause

**`circulatingSupply() public view returns (uint256)`**
- `sDGNRS.totalSupply() - sDGNRS.balanceOf(SDGNRS) - sDGNRS.balanceOf(DGNRS)`

**`threshold(uint256 proposalId) public view returns (uint16)`**
- Discrete daily decay, same for admin and community proposals

**`canExecute(uint256 proposalId) external view returns (bool)`**
- View: checks stall + threshold + approve > reject

### Threshold Decay (unified, all proposals)

| Hours since proposal | Required % |
|---|---|
| 0-24 | 60% |
| 24-48 | 50% |
| 48-72 | 40% |
| 72-96 | 30% |
| 96-120 | 20% |
| 120-144 | 10% |
| 144-168 | 5% (floor, expires at 168h) |

### Removed

- `emergencyRecover()` — replaced by propose/vote/execute flow

---

## DegenerusGameAdvanceModule.sol — 5 Changes

**a.** `_applyDailyRng()` line 1363 — add `lastVrfProcessedTimestamp = uint48(block.timestamp);` after `rngWordByDay[day] = finalWord;`

**b.** `rngGate()` line 773 — change `18 hours` → `12 hours`

**c.** `updateVrfCoordinatorAndSub()` line 1265 — remove `_threeDayRngGap` check (Admin enforces stall via timestamp governance). Keep `msg.sender == ADMIN` check unchanged.

**d.** `_handleGameOverPath()` line 421-425 — death clock pauses during VRF stall:
```solidity
bool livenessTriggered = ...;
if (livenessTriggered) {
    // Pause death clock during VRF stall (governance may be active)
    try IDegenerusAdmin(ContractAddresses.ADMIN).anyProposalActive()
        returns (bool active) {
        if (active) livenessTriggered = false;
    } catch {}
}
```

**e.** `wireVrf()` line 397 — init `lastVrfProcessedTimestamp = uint48(block.timestamp);`

---

## DegenerusGameStorage.sol — 1 Change

Append after line 1607 (tail of storage — safe for delegatecall layout):
```solidity
uint48 internal lastVrfProcessedTimestamp;
```

---

## DegenerusGame.sol — 1 Change

Add view function:
```solidity
function lastVrfProcessed() external view returns (uint48) {
    return lastVrfProcessedTimestamp;
}
```

---

## DegenerusStonk.sol — 1 Change

Disable `unwrapTo` during VRF stall to prevent creator from converting DGNRS → voting sDGNRS:
```solidity
function unwrapTo(address recipient, uint256 amount) external {
    if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized();
    if (recipient == address(0)) revert ZeroAddress();
    // Block unwrap during VRF stall (prevents creator vote-stacking)
    if (block.timestamp - IDegenerusGame(ContractAddresses.GAME).lastVrfProcessed() > 20 hours)
        revert Unauthorized();
    _burn(msg.sender, amount);
    stonk.wrapperTransferTo(recipient, amount);
    emit UnwrapTo(recipient, amount);
}
```

---

## Cancellation Design (simplified)

No manual cancel function. **VRF recovery auto-invalidates all proposals:**
- Every `vote()` call re-checks the stall condition (20h+ since last VRF processed)
- If VRF recovers (a word is processed), the stall check fails and `vote()` reverts
- Proposals become inert — they expire naturally at 168h
- `_applyDailyRng` updates `lastVrfProcessedTimestamp`, so one successful VRF cycle kills governance eligibility

---

## Security Properties

| Property | Mechanism |
|---|---|
| No flash-loan attacks | sDGNRS soulbound, no market |
| No vote buying | sDGNRS non-transferable |
| No admin unilateral control | Admin proposes only, can't self-approve |
| No creator vote-stacking | `unwrapTo` disabled during stall |
| No passive approval | Requires approve > reject AND approve >= threshold |
| No panic voting | Death clock paused during VRF stall |
| No denominator manipulation | Circulating supply snapshotted at proposal creation |
| No vote-splitting | Approval voting across proposals |
| No governance upgrade | Contract immutable |
| Auto-cancel on VRF recovery | Stall re-check in every vote() |
| Admin key loss | Community path at 7d, independent of admin |

---

## Verification

1. `npx hardhat compile` — clean
2. `npx hardhat test` — no regressions
3. New test file: propose, vote, threshold decay, execute, kill, expiry, death clock pause, multi-proposal approval voting, unwrapTo block during stall, VRF recovery invalidation
