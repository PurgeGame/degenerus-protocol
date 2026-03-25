# Unit 13: Admin + Governance -- Mad Genius Attack Report

**Phase:** 115
**Contract:** DegenerusAdmin.sol (L149-803)
**Agent:** Mad Genius (Opus)
**Date:** 2026-03-25

---

## CRITICAL TIER

---

## A-06: DegenerusAdmin::propose (L398-445)

### Call Tree
```
propose(newCoordinator, newKeyHash) [L398-445] -> returns proposalId
  |-- if subscriptionId == 0: revert NotWired [L402]
  |-- gameAdmin.gameOver() [L403] -> Game contract external view
  |     |-- if true: revert GameOver
  |-- if newCoordinator == address(0) || newKeyHash == bytes32(0): revert ZeroAddress [L404-405]
  |-- existing = activeProposalId[msg.sender] [L408]
  |-- if existing != 0: [L409]
  |     |-- ep = proposals[existing] [L410]
  |     |-- if ep.state == Active AND elapsed < PROPOSAL_LIFETIME: revert AlreadyHasActiveProposal [L411-413]
  |-- lastVrf = gameAdmin.lastVrfProcessed() [L417] -> Game contract external view
  |-- stall = block.timestamp - uint256(lastVrf) [L418]
  |-- if vault.isVaultOwner(msg.sender): [L421] -> Vault contract external view
  |     |-- if stall < ADMIN_STALL_THRESHOLD (20h): revert NotStalled [L422]
  |     |-- path = Admin [L423]
  |-- else: [L424]
  |     |-- if stall < COMMUNITY_STALL_THRESHOLD (7d): revert NotStalled [L425]
  |     |-- circ = circulatingSupply() [L426]
  |     |     |-- sDGNRS.totalSupply() [L521] -> sDGNRS external view
  |     |     |-- sDGNRS.balanceOf(SDGNRS) [L522] -> sDGNRS external view
  |     |     |-- sDGNRS.balanceOf(DGNRS) [L523] -> sDGNRS external view
  |     |-- if circ == 0 OR balance * BPS < circ * 50: revert InsufficientStake [L427-428]
  |     |-- path = Community [L429]
  |-- proposalId = ++proposalCount [L432]
  |-- p = proposals[proposalId] [L433]
  |-- p.proposer = msg.sender [L434]
  |-- p.coordinator = newCoordinator [L435]
  |-- p.keyHash = newKeyHash [L436]
  |-- p.createdAt = uint48(block.timestamp) [L437]
  |-- p.circulatingSnapshot = circulatingSupply() [L438]
  |     |-- sDGNRS.totalSupply() [L521]
  |     |-- sDGNRS.balanceOf(SDGNRS) [L522]
  |     |-- sDGNRS.balanceOf(DGNRS) [L523]
  |-- p.path = path [L439]
  |-- activeProposalId[msg.sender] = proposalId [L442]
  |-- emit ProposalCreated [L444]
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| proposalCount | L432 | ++proposalCount |
| proposals[id].proposer | L434 | msg.sender |
| proposals[id].coordinator | L435 | newCoordinator |
| proposals[id].keyHash | L436 | newKeyHash |
| proposals[id].createdAt | L437 | uint48(block.timestamp) |
| proposals[id].circulatingSnapshot | L438 | circulatingSupply() |
| proposals[id].path | L439 | Admin or Community |
| activeProposalId[msg.sender] | L442 | proposalId |

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| existing | L408 | activeProposalId[msg.sender] at L442 | NO -- existing is only used for the old-proposal check at L409-414, never re-used after L442 write |
| stall | L418 | (no writes to lastVrfProcessed from this contract) | NO -- read-only from Game |
| circ | L426 | (no writes to sDGNRS supply from this contract) | NO -- read-only |
| proposalId | L432 | proposalCount at L432 | NO -- proposalId IS the post-increment value |

No cached-local-vs-storage conflicts.

### Attack Analysis

**1. State Coherence (BAF Pattern)**
propose() reads lastVrfProcessed, isVaultOwner, sDGNRS balances, and circulatingSupply as external view calls. No function in the call tree writes to storage that another ancestor has cached locally. The circulatingSupply() is called TWICE (L426 for eligibility check, L438 for snapshot), but the result could differ if an external transaction modifies sDGNRS supply between these two calls. However, both calls happen atomically within the same transaction -- **no intervening external state change is possible**.
**VERDICT: SAFE**

**2. Access Control**
- Admin path: requires vault.isVaultOwner(msg.sender) at L421. This is a cross-contract call to the Vault. The Vault's isVaultOwner checks DGVE token balance. If an attacker acquires >50.1% DGVE, they ARE the legitimate owner. This is the intended trust model.
- Community path: requires 0.5% of circulating sDGNRS at L427-428. The check `sDGNRS.balanceOf(msg.sender) * BPS < circ * COMMUNITY_PROPOSE_BPS` correctly verifies minimum stake.
- No access control prevents anyone from calling propose -- the function self-gates via stall checks and stake requirements.
**VERDICT: SAFE**

**3. RNG Manipulation**
No RNG involved in propose().
**VERDICT: N/A**

**4. Cross-Contract State Desync**
- `gameAdmin.gameOver()` at L403: If gameOver transitions between the check and the proposal creation, the proposal is created for a game-over game. However, if VRF is stalled 20h+, game is not advancing. gameOver can only be set via advanceGame() which requires a VRF word. If VRF is stalled, advanceGame cannot progress, so gameOver cannot flip during the stall window. **SAFE** -- game-over and VRF stall are mutually exclusive during normal operation.
- `lastVrfProcessed` at L417: This is a timestamp that only advances when a VRF word is processed. During a VRF stall, it is frozen. Another tx cannot advance it unless a VRF callback arrives. If a callback arrives between propose checks and storage writes, the stall check was valid at check time -- the proposal just becomes stale (vote() will revert on stall re-check). **SAFE**.
**VERDICT: SAFE**

**5. Edge Cases**
- **circulatingSupply() == 0** (L427): Checked explicitly -- reverts InsufficientStake. **SAFE**.
- **First proposal** (proposalCount == 0): proposalId becomes 1. proposals[1] is a fresh struct. activeProposalId[msg.sender] was 0, so existing == 0 at L408, skips the active-proposal check. **SAFE**.
- **Expired old proposal**: If activeProposalId[msg.sender] points to an expired proposal, the check at L411-413 passes (either state != Active or elapsed >= PROPOSAL_LIFETIME), allowing a new proposal. **SAFE**.
- **uint48 truncation at L437**: block.timestamp cast to uint48. Max uint48 = 281474976710655 (year ~8.9 million). No practical overflow risk. **SAFE**.
**VERDICT: SAFE**

**6. Conditional Paths**
- Admin path vs Community path: Both paths correctly enforce their respective stall thresholds. Admin uses 20h, Community uses 7d. No way to bypass: the if/else at L421 checks isVaultOwner first, and only falls to community path if false.
- 1-per-address limit: An address with an active, non-expired proposal cannot create another. This prevents proposal spam per-address but does NOT prevent multiple addresses from creating proposals. This is intentional -- multiple addresses can propose different coordinators.
**VERDICT: SAFE**

**7. Economic Attacks / MEV**
- **Proposal spam**: Each proposer needs either DGVE ownership OR 0.5% sDGNRS + 7d stall. During a VRF stall, multiple community members could each create one proposal. The _voidAllActive loop in _executeSwap (called when any proposal is executed) kills all other proposals. Gas cost of _voidAllActive is O(proposalCount - voidedUpTo). In a 7-day stall, the number of unique community proposers with 0.5%+ sDGNRS is bounded by 200 (100% / 0.5%). So maximum loop iterations = ~200. **SAFE** -- bounded by sDGNRS distribution.
- **circulatingSupply manipulation**: An attacker could try to manipulate circulatingSnapshot by transferring sDGNRS to/from the SDGNRS or DGNRS contracts before calling propose. However, the exclusion addresses (SDGNRS, DGNRS) are compile-time constants. Transferring sDGNRS TO the SDGNRS contract increases the exclusion, lowering circulatingSupply, making the threshold easier to meet with fewer tokens. But: (a) the attacker must control 0.5% of the NEW lower circulating supply, and (b) transferring to SDGNRS is a one-way trip (the sDGNRS contract does not have a function to send tokens back to arbitrary addresses). **SAFE** -- the attack is self-defeating and irreversible.
**VERDICT: SAFE**

**8. Griefing**
- An attacker with 0.5% sDGNRS can create proposals pointing to a malicious coordinator. These proposals must still pass the vote threshold to execute. The defense is the voting system itself. **SAFE** -- governance is the mitigation.
**VERDICT: SAFE**

**9. Ordering/Sequencing**
- propose() must be called before vote(). The proposalId returned is 1-indexed and sequential. No re-ordering vulnerability.
**VERDICT: SAFE**

**10. Silent Failures**
- All failure paths revert with custom errors. No silent success paths.
**VERDICT: SAFE**

---

## A-07: DegenerusAdmin::vote (L452-517)

### Call Tree
```
vote(proposalId, approve) [L452-517]
  |-- lastVrf = gameAdmin.lastVrfProcessed() [L454] -> Game external view
  |-- if block.timestamp - uint256(lastVrf) < ADMIN_STALL_THRESHOLD: revert NotStalled [L455-456]
  |-- p = proposals[proposalId] [L458]
  |-- if p.state != Active OR p.createdAt == 0: revert ProposalNotActive [L459-460]
  |-- if block.timestamp - uint256(p.createdAt) >= PROPOSAL_LIFETIME: [L463]
  |     |-- p.state = Expired [L464]
  |     |-- revert ProposalExpired [L465]
  |-- weight = sDGNRS.balanceOf(msg.sender) [L470] -> sDGNRS external view
  |-- if weight == 0: revert InsufficientStake [L471]
  |-- currentVote = votes[proposalId][msg.sender] [L474]
  |-- if currentVote != None: [L475]
  |     |-- oldWeight = voteWeight[proposalId][msg.sender] [L476]
  |     |-- if Approve: p.approveWeight -= oldWeight [L477-478]
  |     |-- if Reject: p.rejectWeight -= oldWeight [L479-480]
  |-- newVote = approve ? Approve : Reject [L485]
  |-- votes[proposalId][msg.sender] = newVote [L486]
  |-- voteWeight[proposalId][msg.sender] = weight [L487]
  |-- if approve: p.approveWeight += weight [L489-490]
  |-- else: p.rejectWeight += weight [L491-493]
  |-- emit VoteCast [L495]
  |-- t = threshold(proposalId) [L498]
  |     |-- elapsed = block.timestamp - uint256(proposals[proposalId].createdAt) [L531]
  |     |-- returns step-function: 5000/4000/3000/2000/1000/500/0 [L532-538]
  |-- if p.approveWeight * BPS >= uint256(t) * p.circulatingSnapshot [L502]
  |     AND p.approveWeight > p.rejectWeight [L503]:
  |     |-- _executeSwap(proposalId) [L505] -> see A-10
  |     |-- return [L506]
  |-- if p.rejectWeight > p.approveWeight [L511]
  |     AND p.rejectWeight * BPS >= uint256(t) * p.circulatingSnapshot [L512]:
  |     |-- p.state = Killed [L514]
  |     |-- emit ProposalKilled [L515]
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| proposals[id].state | L464 | Expired (conditional: only if expired) |
| votes[id][msg.sender] | L486 | newVote (Approve or Reject) |
| voteWeight[id][msg.sender] | L487 | weight (current sDGNRS balance) |
| proposals[id].approveWeight | L478 (subtract old) or L490 (add new) | adjusted weight |
| proposals[id].rejectWeight | L480 (subtract old) or L492 (add new) | adjusted weight |
| proposals[id].state | L514 | Killed (conditional: if reject threshold met) |
| (via _executeSwap) | see A-10 | (conditional: if approve threshold met) |

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| lastVrf | L454 | (no writes to lastVrfProcessed from this contract) | NO |
| p (storage ref) | L458 | Direct writes to p.approveWeight/rejectWeight at L478-492 | NO -- p is a storage reference, not a cached local. All reads/writes go to storage. |
| weight | L470 | (no writes to sDGNRS from this contract) | NO |
| currentVote | L474 | votes[id][sender] at L486 | **POTENTIAL** -- currentVote read before write at L486 |
| oldWeight | L476 | voteWeight[id][sender] at L487 | **POTENTIAL** -- oldWeight read before write at L487 |
| t | L498 | proposals[id].createdAt (read by threshold()) | NO -- createdAt is never written in vote() |

**Analysis of potential conflicts:**
1. `currentVote` at L474 is read and used at L475-481 to subtract old weight. Then at L486, the NEW vote is written. The old currentVote is no longer needed after the subtraction. **SAFE** -- correct read-modify-write pattern.
2. `oldWeight` at L476 is read and used at L478/480 to subtract. Then at L487, the NEW weight is written. **SAFE** -- same pattern.

### Attack Analysis

**1. State Coherence (BAF Pattern)**
The `p` variable is a `storage` reference (L458: `Proposal storage p`), not a memory copy. Every read/write through `p` goes directly to storage. There is no stale-cache risk for the proposal data. The `weight` variable is a local from an external call (sDGNRS.balanceOf), and it's never re-read from storage after being cached -- it's used for the new vote weight and for the threshold check. No descendant writes to sDGNRS balance.
**VERDICT: SAFE**

**2. Access Control**
- Anyone with sDGNRS balance > 0 can vote. This is intentional -- sDGNRS represents governance participation rights.
- The stall re-check at L454-456 uses ADMIN_STALL_THRESHOLD (20h), not COMMUNITY_STALL_THRESHOLD. This means vote() blocks for ALL voters (admin and community) once VRF recovers (stall < 20h). This is the "auto-cancellation" mechanism described in the natspec.
**VERDICT: SAFE**

**3. RNG Manipulation**
No RNG involved.
**VERDICT: N/A**

**4. Cross-Contract State Desync -- INVESTIGATE: Vote Weight via sDGNRS Transfer**
The comment at L469 says "Safe: VRF dead = supply frozen (no advances, unwrapTo blocked)." Let me trace this claim:
- sDGNRS.balanceOf(msg.sender) at L470 reads the LIVE balance.
- During a VRF stall, can sDGNRS be transferred between addresses? YES -- sDGNRS is an ERC20, transfer() works regardless of VRF state.
- Scenario: Alice has 100 sDGNRS, Bob has 100 sDGNRS. Alice votes Approve with weight 100. Alice transfers 100 sDGNRS to Bob. Bob votes Approve with weight 200. Combined approveWeight = 300 from only 200 sDGNRS in circulation.
- HOWEVER: The code tracks `voteWeight[proposalId][msg.sender]` at L487. If Alice re-votes after transferring, her new weight is 0, and the old 100 is subtracted at L478. So Alice's contribution becomes 0. The double-counting only works if Alice does NOT re-vote.
- The threshold check at L502 compares against `p.circulatingSnapshot` which was set at proposal creation. If 200 sDGNRS circulating and snapshot is 200, then approveWeight 300 > 50% * 200 = 100. This exceeds the threshold.
- **BUT**: The comment says "VRF dead = supply frozen." Is this true? During a VRF stall, `advanceGame` cannot progress, so no new sDGNRS is minted via game rewards. However, sDGNRS can still be TRANSFERRED. The total supply does not change, but individual balances do. The circulatingSnapshot captures the total, not individual balances.
- **Net effect**: A voter's weight is their balance AT TIME OF VOTE. If Alice transfers to Bob, Alice's weight is "spent" (0 sDGNRS left). Bob's weight includes Alice's tokens. The total weight across all voters cannot exceed circulatingSupply (each token can only be counted once per voter, and a voter's weight is their full balance). The only issue is if Alice's OLD vote (100 weight) is still counted AND Bob votes with Alice's tokens (200 weight). Total approveWeight = 300, but total sDGNRS = 200.
- **This IS a vote-weight inflation vulnerability via transfer-and-vote.** Alice votes (100), transfers to Bob, Bob votes (200). Total approve = 300 vs 200 circulating. Alice must NOT re-vote for this to persist.

**VERDICT: INVESTIGATE** -- Vote weight inflation via sDGNRS transfer between votes. See dedicated analysis below.

**5. Edge Cases**
- **proposalId == 0**: proposals[0] is uninitialized. p.createdAt == 0, so L459 reverts ProposalNotActive. **SAFE**.
- **Last second of lifetime**: At elapsed == PROPOSAL_LIFETIME - 1, threshold returns 500 (5%). At elapsed == PROPOSAL_LIFETIME, L463 triggers, setting state to Expired. Race condition: if a voter submits at exactly the expiry second, they could set the proposal to Expired OR their vote could trigger execution at 5% threshold. The check at L463 uses `>=`, so exactly at PROPOSAL_LIFETIME it expires. The threshold() function at L532 returns 0 at `>= 168 hours`. So at exactly 168h, vote() reaches L463 first (because the expiry check happens before weight assignment). **SAFE** -- expiry check comes first.
- **Zero circulatingSnapshot**: If circulatingSnapshot == 0 in the proposal, then `uint256(t) * p.circulatingSnapshot` == 0, meaning ANY approveWeight > 0 meets the threshold. However, propose() at L427 checks `circ == 0` and reverts InsufficientStake for community path. For admin path, circulatingSnapshot is set at L438 -- if circulating is 0, the admin can still propose (admin path at L421-423 doesn't check circulating). If circulatingSnapshot == 0, then ANY single approve vote would execute the swap. **INVESTIGATE** -- admin-path proposal with zero circulating supply.
- **Vote change with same direction**: Alice votes Approve (weight 100), then votes Approve again (weight 150). At L475-478: old Approve weight (100) subtracted. At L489-490: new weight (150) added. Net: approveWeight += 50. **SAFE** -- correct.
**VERDICT: INVESTIGATE** (zero circulatingSnapshot edge case)

**6. Conditional Paths**
- Expire path (L463-465): Sets state to Expired, reverts. The state change persists (it's in storage). Next caller sees Expired state and reverts at L459. **SAFE**.
- Execute path (L501-506): Calls _executeSwap, returns. **Analyzed in A-10**.
- Kill path (L510-516): Sets state to Killed. Does not revert -- falls through to end. **SAFE**.
- No-action path (neither threshold met): Vote is recorded, neither execute nor kill triggered. Falls through. **SAFE**.
**VERDICT: SAFE**

**7. Economic Attacks / MEV**
- **Front-running a vote to hit threshold**: If a voter's vote would trigger execution, a miner/validator could front-run to: (a) change sDGNRS balances via DEX trades, (b) submit their own vote first. But: (a) sDGNRS has no external DEX; its supply is protocol-controlled. (b) Submitting a competing vote only changes the outcome if it changes whether the threshold is met. This is standard governance behavior, not an exploit.
- **Back-running an execution**: After _executeSwap changes the VRF coordinator, a back-running tx could try to exploit the new coordinator. But the coordinator is a Chainlink contract -- no exploit surface from back-running.
**VERDICT: SAFE**

**8. Griefing**
- **Reject to prevent execution**: A holder with significant sDGNRS can reject-vote to prevent execution. This is the intended governance model (reject > approve prevents execution at L503).
- **Proposal expiry griefing**: If no vote reaches threshold within 7 days, the proposal expires. A griefing voter could keep vote weights balanced. Mitigation: the decaying threshold (50% -> 5%) makes it progressively easier for the majority to execute.
**VERDICT: SAFE**

**9. Ordering/Sequencing**
- Voting on an already-executed or killed proposal: L459 reverts ProposalNotActive. **SAFE**.
- Voting after expiry: L463-465 marks as Expired and reverts. **SAFE**.
**VERDICT: SAFE**

**10. Silent Failures**
- All failure paths revert. The only "silent" outcome is when a vote is recorded but neither threshold is met -- the voter just cast their vote. This is expected behavior.
**VERDICT: SAFE**

### Dedicated Analysis: Vote Weight Inflation via sDGNRS Transfer

**Scenario:**
1. Proposal P created with circulatingSnapshot = 200 sDGNRS
2. Alice (100 sDGNRS) votes Approve -> approveWeight = 100
3. Alice transfers 100 sDGNRS to Bob
4. Bob (now 200 sDGNRS) votes Approve -> approveWeight = 100 + 200 = 300
5. Threshold at 50%: need 100 (50% * 200 snapshot). 300 >= 100. Proposal executes.

**Is this exploitable?**
- The proposal was created during a VRF stall (required by propose()).
- The VRF stall means the game is non-functional -- VRF is dead.
- The governance system EXISTS to swap VRF coordinators during stalls.
- The question is: does the inflated weight allow a minority to force through a malicious coordinator?

**Analysis of the actual risk:**
- For vote weight inflation to matter, the approval threshold must be met with fewer actual sDGNRS than the threshold requires. In the scenario above, Alice+Bob control 200 sDGNRS (the full circulating supply), so they would meet any threshold anyway. The inflation is irrelevant when the SAME tokens are being transferred.
- For inflation to CREATE a problem: Alice (100 sDGNRS, 50% of supply) votes, transfers to mallory (0 sDGNRS, now 100). Mallory votes. approveWeight = 200. Threshold at 50% = 100. They pass with 200 from 100 real tokens. But Alice+Mallory together control 100% of the supply -- they would pass at the 50% threshold with just one of them voting.
- For a REAL attack: Alice has 30 sDGNRS (15% of 200 circulating). She votes (weight 30). Transfers to Bob (15%). Bob votes (weight 30). approveWeight = 60. At 5% threshold (day 6+): need 10. They pass with 60, despite only 30 sDGNRS. But if reject voters hold 170 sDGNRS and any of them reject, rejectWeight > approveWeight (170 > 60 at L503 AND L511), so proposal is killed, not executed.
- **Key insight:** The execute condition at L502-503 requires BOTH `approveWeight * BPS >= t * snapshot` AND `approveWeight > rejectWeight`. Even with inflated approve weight, if reject voters hold more sDGNRS and all reject, rejectWeight will likely exceed approveWeight (because reject voters are NOT inflating their weights via transfers -- or they could equally inflate).
- The vulnerability is symmetric: reject voters could also inflate weights via transfers. The side with more participants willing to do the transfer dance has an advantage.
- **During a genuine VRF stall**, the community needs to act quickly to swap coordinators. The transfer-and-vote pattern requires coordination and is detectable on-chain. Honest majority assumption holds: if honest voters hold majority of sDGNRS and vote, their non-inflated weight exceeds inflated minority weight.

**VERDICT: INVESTIGATE -- DOWNGRADE TO INFO.** The vote weight inflation via sDGNRS transfer is real but: (1) symmetric (both sides can do it), (2) bounded by total supply (you can't create sDGNRS, only redistribute), (3) mitigated by the honest-majority assumption that is inherent in any token-weighted governance system, (4) only active during VRF stall when governance is critical. The design comment "VRF dead = supply frozen" is technically inaccurate (transfers still work), but the practical impact is negligible.

### Dedicated Analysis: Zero circulatingSnapshot Edge Case

**Scenario:** Admin (DGVE owner) proposes when circulatingSupply() == 0.
- propose() at L421-423: Admin path only checks stall, not circulating supply.
- L438: p.circulatingSnapshot = circulatingSupply() = 0.
- vote() at L502: `approveWeight * BPS >= uint256(t) * 0` -> `approveWeight * BPS >= 0` -> TRUE for any approveWeight > 0.
- vote() at L503: `approveWeight > rejectWeight` -> TRUE if approveWeight > 0 and rejectWeight == 0.
- So a single sDGNRS holder with balance > 0 can execute immediately.

**But can circulatingSupply() == 0?**
- circulatingSupply = totalSupply - balanceOf(SDGNRS) - balanceOf(DGNRS)
- For this to be 0: ALL sDGNRS must be held by the SDGNRS contract itself or the DGNRS wrapper.
- In practice, if any player has ever staked DGNRS (receiving sDGNRS), the circulating supply is > 0.
- Zero circulating supply means NO governance participants exist. If no one holds sDGNRS, no one can vote (L470-471 requires weight > 0).
- **Paradox:** If circulatingSupply == 0, then no one can vote, so no proposal can ever be executed (no one can call vote()). The proposal sits until it expires.
- The only exception: if sDGNRS balance changes between propose() and vote(). But propose() snapshots at L438. If snapshot is 0, the threshold math is trivially met, but still requires a voter with sDGNRS > 0. If someone acquires sDGNRS AFTER the proposal is created, they can vote with weight > 0, and the threshold is auto-met.
- **Risk**: This is an edge case with near-zero probability. If circulating supply drops to 0 and someone later acquires even 1 wei of sDGNRS, they can single-handedly execute a VRF swap proposal. But: (a) this requires an admin to have proposed, (b) the VRF must be stalled 20h+, (c) the person must hold sDGNRS. The admin already has to be the DGVE owner to propose on the admin path -- they could also be the one to vote.

**VERDICT: SAFE -- INFO.** Technically the threshold math divides by 0 denominator via the snapshot, but the consequence is that any voter can execute. In the zero-circulating-supply scenario, this is the only viable path to governance action, which is arguably correct behavior.

---

## A-10: DegenerusAdmin::_executeSwap (L566-627)

### Call Tree
```
_executeSwap(proposalId) [L566-627] -- called from vote() at L505
  |-- p = proposals[proposalId] [L567]
  |-- p.state = Executed [L568]
  |-- _voidAllActive(proposalId) [L571]
  |     |-- start = voidedUpTo + 1 [L632]
  |     |-- count = proposalCount [L633]
  |     |-- for i = start to count: [L634]
  |     |     |-- if i == exceptId: continue [L635]
  |     |     |-- if proposals[i].state == Active: [L636]
  |     |     |     |-- proposals[i].state = Killed [L637]
  |     |     |     |-- emit ProposalKilled(i) [L638]
  |     |-- voidedUpTo = count [L642]
  |-- newCoordinator = p.coordinator [L573]
  |-- newKeyHash = p.keyHash [L574]
  |-- oldSub = subscriptionId [L576]
  |-- oldCoord = coordinator [L577]
  |-- if oldSub != 0: [L580]
  |     |-- try IVRFCoordinatorV2_5Owner(oldCoord).cancelSubscription(oldSub, this) [L582-583]
  |     |     |-- catch {} [L588] -- silent catch
  |-- coordinator = newCoordinator [L592]
  |-- newSubId = IVRFCoordinatorV2_5Owner(newCoordinator).createSubscription() [L593-594]
  |-- subscriptionId = newSubId [L595]
  |-- vrfKeyHash = newKeyHash [L596]
  |-- IVRFCoordinatorV2_5Owner(newCoordinator).addConsumer(newSubId, GAME) [L601-603]
  |-- gameAdmin.updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash) [L608-612]
  |-- bal = linkToken.balanceOf(this) [L615]
  |-- if bal != 0: [L616]
  |     |-- try linkToken.transferAndCall(newCoordinator, bal, abi.encode(newSubId)) [L618-620]
  |     |     |-- catch {} [L623] -- silent catch
  |-- emit ProposalExecuted [L626]
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| proposals[id].state | L568 | Executed |
| proposals[i].state (loop) | L637 | Killed (for each active, via _voidAllActive) |
| voidedUpTo | L642 | proposalCount (via _voidAllActive) |
| coordinator | L592 | newCoordinator |
| subscriptionId | L595 | newSubId |
| vrfKeyHash | L596 | newKeyHash |

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| p (storage ref) | L567 | p.state at L568 | NO -- p is storage reference |
| newCoordinator | L573 | coordinator at L592 | NO -- newCoordinator is a local copy of p.coordinator. coordinator storage is written with the same value. No stale-cache. |
| newKeyHash | L574 | vrfKeyHash at L596 | NO -- same pattern as above |
| oldSub | L576 | subscriptionId at L595 | **POTENTIAL** -- oldSub read before subscriptionId overwritten |
| oldCoord | L577 | coordinator at L592 | **POTENTIAL** -- oldCoord read before coordinator overwritten |

**Analysis of potential conflicts:**
1. `oldSub` at L576: Used at L580-583 to cancel the OLD subscription. Then subscriptionId is overwritten at L595 with newSubId. The old value is correctly used for cancellation before being replaced. **SAFE** -- intentional pattern (read-old, cancel-old, write-new).
2. `oldCoord` at L577: Used at L582 to call cancelSubscription on the OLD coordinator. Then coordinator is overwritten at L592 with newCoordinator. **SAFE** -- same pattern.

### Attack Analysis

**1. State Coherence (BAF Pattern)**
The function reads proposal data via storage reference (not cached). It caches `oldSub` and `oldCoord` before overwriting coordinator and subscriptionId, which is the correct pattern for "replace old with new." No descendant writes to storage that an ancestor has cached for a different purpose.
**VERDICT: SAFE**

**2. Access Control**
_executeSwap is internal, only callable from vote() at L505. vote() is open to any sDGNRS holder, but execution requires passing the threshold check. The governance threshold IS the access control. The function cannot be called directly.
**VERDICT: SAFE**

**3. Malicious Coordinator Injection**
The newCoordinator address was set in propose() and stored in the proposal. If an attacker passes a malicious coordinator address:
- `createSubscription()` is called on the malicious contract (L593-594). It could return any subId.
- `addConsumer()` is called on the malicious contract (L601-603). It could no-op or trap.
- `gameAdmin.updateVrfCoordinatorAndSub()` is called on the GAME contract (L608-612), pushing the malicious coordinator address to the game. The game would then send VRF requests to the malicious coordinator.
- A malicious coordinator could: (a) never fulfill requests -> another VRF stall -> another governance round, (b) return predictable "random" words -> game manipulation.
- **However:** This requires the governance vote to PASS. The entire governance system is designed to prevent malicious coordinator swaps via majority voting. If a majority of sDGNRS holders approve a malicious coordinator, the protocol is compromised BY DESIGN (honest majority assumption).
**VERDICT: SAFE** -- the risk is inherent to governance-based coordinator swaps and is documented in KNOWN-ISSUES.md.

**4. CEI Compliance**
- L568: p.state = Executed (effects)
- L571: _voidAllActive (effects -- kills other proposals)
- L582-583: cancelSubscription on OLD coordinator (interaction)
- L592-596: write coordinator, subscriptionId, vrfKeyHash (effects)
- L601-603: addConsumer (interaction)
- L608-612: updateVrfCoordinatorAndSub (interaction)
- L615-623: LINK transfer (interaction)

The function interleaves effects and interactions. Specifically, coordinator/subscriptionId/vrfKeyHash are written at L592-596 BETWEEN the old subscription cancellation (L582) and the new consumer addition (L601).

Is this exploitable? The old coordinator's cancelSubscription at L582 could potentially call back into DegenerusAdmin. At that point:
- p.state is already Executed (L568)
- All other proposals are Killed (L571)
- subscriptionId still holds the OLD value
- coordinator still holds the OLD value

If the old coordinator calls back into vote(), the stall check and proposal state checks prevent any action. If it calls back into onTokenTransfer(), the subscriptionId is still the old one, which would be inconsistent after cancellation. But onTokenTransfer checks msg.sender == LINK_TOKEN, so a reentrant call from the VRF coordinator would be rejected.

The cancelSubscription is wrapped in try/catch (L581-588), so even if it fails or is malicious, execution continues. The function does NOT depend on the success of cancellation for correctness.
**VERDICT: SAFE** -- try/catch makes old coordinator interaction non-blocking. No reentry path.

**5. LINK Transfer Failure**
At L615-623, the function tries to transfer LINK to the new subscription via transferAndCall. If this fails (try/catch), the LINK stays in the Admin contract. On the next call to onTokenTransfer (LINK donation), the LINK would be forwarded to the new coordinator/subscription. No LINK is permanently stuck.
**VERDICT: SAFE**

**6. Silent Failures**
Two try/catch blocks silently swallow failures:
- L581-588: Old subscription cancellation failure is silent. The old subscription may remain active. This could mean LINK is still allocated to the old subscription. However, the old coordinator is replaced, and the game now uses the new coordinator. The old subscription is abandoned but not harmful -- it just holds stale LINK that can't be recovered.
- L618-623: LINK transfer failure is silent. LINK stays in Admin contract. Not lost, just not forwarded yet.

**VERDICT: SAFE -- INFO.** Silent catch on old subscription cancellation means LINK in the old subscription may be unrecoverable. This is a known tradeoff: the old coordinator may be malicious/broken, so cancellation is best-effort.

**7. Gas Exhaustion in _voidAllActive**
The _voidAllActive loop at L634 iterates from voidedUpTo+1 to proposalCount. In the worst case (no prior executions), this is all proposals ever created. Each iteration reads 1 storage slot (proposals[i].state) and potentially writes 1 slot + emits 1 event.
- Maximum proposals during a stall: bounded by unique addresses with 0.5%+ sDGNRS (max ~200) plus admin proposals. In practice, unlikely to exceed ~200.
- Gas per iteration: ~5000 (SLOAD) + ~5000 (SSTORE) + ~375 (LOG1) = ~10375 per active proposal.
- 200 iterations: ~2M gas. Within block gas limit (30M+). **SAFE**.
- The `voidedUpTo` watermark ensures the loop doesn't re-scan already-voided proposals on subsequent executions. **SAFE** -- bounded.
**VERDICT: SAFE**

---

## A-07 -> A-10: vote() triggering _executeSwap -- Combined Flow

### Full End-to-End Storage Writes
| Variable | Function | Line |
|----------|----------|------|
| proposals[id].state (Expired, conditional) | vote | L464 |
| votes[id][sender] | vote | L486 |
| voteWeight[id][sender] | vote | L487 |
| proposals[id].approveWeight | vote | L478/L490 |
| proposals[id].rejectWeight | vote | L480/L492 |
| proposals[id].state (Killed, conditional) | vote | L514 |
| proposals[id].state (Executed) | _executeSwap | L568 |
| proposals[i].state (Killed, loop) | _voidAllActive | L637 |
| voidedUpTo | _voidAllActive | L642 |
| coordinator | _executeSwap | L592 |
| subscriptionId | _executeSwap | L595 |
| vrfKeyHash | _executeSwap | L596 |

### End-to-End Cached-Local-vs-Storage
The vote() function creates local `p` as a storage reference, writes to it, then calls _executeSwap which also reads `p`. Since `p` is a storage reference, no stale-cache issue exists. The `t` (threshold) is read at L498, used at L502/L512, and not re-used after _executeSwap. No cross-function stale-cache.
**VERDICT: SAFE**

---

## HIGH TIER

---

## A-08: DegenerusAdmin::shutdownVrf (L651-674)

### Call Tree
```
shutdownVrf() [L651-674]
  |-- if msg.sender != GAME: revert NotAuthorized [L652]
  |-- subId = subscriptionId [L653]
  |-- if subId == 0: return [L654] -- silent no-op
  |-- subscriptionId = 0 [L656]
  |-- target = VAULT [L657]
  |-- try coordinator.cancelSubscription(subId, target) [L659] -> VRF Coordinator
  |     |-- emit SubscriptionCancelled(subId, target) [L660]
  |     |-- catch {} [L661]
  |-- bal = linkToken.balanceOf(this) [L663] -> LINK Token
  |-- if bal != 0: [L664]
  |     |-- try linkToken.transfer(target, bal) [L665] -> LINK Token
  |     |     |-- if ok: [L666]
  |     |     |     |-- emit SubscriptionShutdown(subId, target, bal) [L667]
  |     |     |     |-- return [L668]
  |     |-- catch {} [L670]
  |-- emit SubscriptionShutdown(subId, target, 0) [L673]
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| subscriptionId | L656 | 0 |

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| subId | L653 | subscriptionId at L656 | NO -- subId is used for cancelSubscription (L659) after subscriptionId is zeroed. This is the correct pattern: zero the state first, then use the cached old value for cleanup. |
| target | L657 | (none) | NO -- constant |
| bal | L663 | (no writes to LINK balanceOf from this contract, but transfer at L665 changes it) | **POTENTIAL** -- bal read before transfer |

**Analysis:** `bal` is read at L663, then used in `transfer(target, bal)` at L665. After transfer, the actual balance is 0 (or lower). But `bal` is only used as the transfer amount -- it's never re-read or re-used. **SAFE**.

### Attack Analysis

**1. Access Control**
Only `ContractAddresses.GAME` can call. This is a compile-time constant. Only the Game contract's handleFinalSweep can invoke this. No bypass possible.
**VERDICT: SAFE**

**2. Double-call**
If called twice: first call sets subscriptionId = 0 and cleans up. Second call: subId = 0 at L653, returns at L654 (no-op). **SAFE**.

**3. Silent Failures**
- cancelSubscription failure: Silent catch. Subscription remains active but subscriptionId is already 0 in Admin contract, so no future interactions reference it. The subscription may hold LINK that becomes unrecoverable via this contract. However, Chainlink V2.5 subscription owners can always cancel manually -- but Admin contract has lost its reference. **INFO** -- documented tradeoff.
- transfer failure: Falls through to emit SubscriptionShutdown(subId, target, 0). LINK stays in Admin contract. Not lost, just not swept. The Admin contract has no other function to sweep LINK after game-over (subscriptionId is 0, onTokenTransfer reverts at L692). **INFO** -- LINK stuck in Admin contract if transfer fails.

**VERDICT: SAFE** (with two INFO observations)

**4. LINK Recovery After Failed Transfer**
If linkToken.transfer fails at L665, LINK is stuck in Admin contract. There is NO recovery function. The Admin contract has no fallback, no sweep, no owner-withdrawal for LINK. If the Vault contract or LINK token has a bug that prevents transfer, the LINK is permanently stuck.
**VERDICT: INVESTIGATE** -- No LINK recovery path after failed shutdown transfer.

**5. State Coherence**
subscriptionId set to 0 at L656 BEFORE external calls. CEI pattern respected. Even if coordinator.cancelSubscription reenters, subscriptionId is already 0, so any reentrant call to shutdownVrf returns at L654.
**VERDICT: SAFE**

---

## MEDIUM TIER

---

## A-01: DegenerusAdmin::constructor (L331-349)

### Call Tree
```
constructor() [L331-349]
  |-- subId = vrfCoordinator.createSubscription() [L332] -> VRF Coordinator
  |-- coordinator = VRF_COORDINATOR [L334]
  |-- subscriptionId = subId [L335]
  |-- vrfKeyHash = VRF_KEY_HASH [L336]
  |-- emit SubscriptionCreated(subId) [L338]
  |-- emit CoordinatorUpdated(VRF_COORDINATOR, subId) [L339]
  |-- vrfCoordinator.addConsumer(subId, GAME) [L341] -> VRF Coordinator
  |-- emit ConsumerAdded(GAME) [L342]
  |-- gameAdmin.wireVrf(VRF_COORDINATOR, subId, VRF_KEY_HASH) [L344-348] -> Game
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| coordinator | L334 | ContractAddresses.VRF_COORDINATOR |
| subscriptionId | L335 | subId (from createSubscription) |
| vrfKeyHash | L336 | ContractAddresses.VRF_KEY_HASH |

### Attack Analysis

**1. Deployment Security**
Constructor runs once during deployment. All addresses are compile-time constants from ContractAddresses. No constructor parameters means no deployment-time manipulation. The VRF coordinator address, key hash, and Game address are hardcoded. If ContractAddresses is correct, deployment is deterministic and safe.
**VERDICT: SAFE**

**2. Ordering Dependencies**
The constructor calls gameAdmin.wireVrf at L344-348. This requires the Game contract to already be deployed AND accept admin-wiring from this Admin contract address. If Game is not yet deployed, this call reverts and Admin deployment fails. The deployment script must deploy Game first, then Admin.
**VERDICT: SAFE** -- deployment ordering is a deployment concern, not a contract vulnerability.

**3. State Coherence**
coordinator, subscriptionId, vrfKeyHash written at L334-336 before external calls at L341, L344. The addConsumer call at L341 uses `subId` (local) which matches `subscriptionId` (storage). No stale-cache risk.
**VERDICT: SAFE**

---

## A-09: DegenerusAdmin::onTokenTransfer (L683-727)

### Call Tree
```
onTokenTransfer(from, amount, data) [L683-727]
  |-- if msg.sender != LINK_TOKEN: revert NotAuthorized [L688]
  |-- if amount == 0: revert InvalidAmount [L689]
  |-- subId = subscriptionId [L691]
  |-- if subId == 0: revert NoSubscription [L692]
  |-- if gameAdmin.gameOver(): revert GameOver [L693] -> Game external view
  |-- coord = coordinator [L695]
  |-- (bal,,,,) = IVRFCoordinatorV2_5Owner(coord).getSubscription(subId) [L697-699] -> VRF Coordinator view
  |-- mult = _linkRewardMultiplier(uint256(bal)) [L700]
  |     |-- if subBal >= 1000e18: return 0 [L761]
  |     |-- if subBal <= 200e18: return 3e18 - (subBal * 2e18 / 200e18) [L762-766]
  |     |-- else: return 1e18 - ((subBal - 200e18) * 1e18 / 800e18) [L768-773]
  |-- try linkToken.transferAndCall(coord, amount, abi.encode(subId)) [L703] -> LINK Token
  |     |-- if !ok: revert InvalidAmount [L705]
  |     |-- catch: revert InvalidAmount [L707]
  |-- if mult == 0: return [L709] -- no reward
  |-- try this.linkAmountToEth(amount) [L712] -> self external view
  |     |-- feed = linkEthPriceFeed [L737]
  |     |-- if feed == 0 or amount == 0: return 0 [L738]
  |     |-- latestRoundData() [L746] -> Price Feed
  |     |-- health checks [L747-751]
  |     |-- ethAmount = (amount * answer) / 1e18 [L754]
  |-- catch: return [L715] -- no reward on feed failure
  |-- if ethEquivalent == 0: return [L717]
  |-- (,,,,priceWei) = gameAdmin.purchaseInfo() [L719] -> Game external view
  |-- if priceWei == 0: return [L720]
  |-- baseCredit = (ethEquivalent * PRICE_COIN_UNIT) / priceWei [L721]
  |-- credit = (baseCredit * mult) / 1e18 [L722]
  |-- if credit == 0: return [L723]
  |-- coinLinkReward.creditLinkReward(from, credit) [L725] -> Coin contract
  |-- emit LinkCreditRecorded(from, credit) [L726]
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| (none in DegenerusAdmin) | - | LINK forwarded via transferAndCall, reward credited via coinLinkReward |

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| subId | L691 | (no writes to subscriptionId in this function) | NO |
| coord | L695 | (no writes to coordinator in this function) | NO |
| bal (from getSubscription) | L697-699 | LINK transferred at L703 changes sub balance | **POTENTIAL** -- bal read before LINK forwarded |
| mult | L700 | (pure function, no storage dependency) | NO |
| amount | parameter | (immutable parameter) | NO |
| ethEquivalent | L712 | (view function) | NO |
| priceWei | L719 | (view function) | NO |

**Analysis:** `bal` at L697-699 is the subscription's LINK balance BEFORE the donation is forwarded. The multiplier is calculated based on this pre-donation balance. After L703 forwards the LINK, the subscription balance increases by `amount`. The multiplier was computed on the PRE-donation balance. This means the reward multiplier reflects the balance BEFORE the donation, which is the correct behavior: the donor gets a multiplier based on how depleted the subscription was before their donation, not after.
**VERDICT: SAFE** -- intentional design.

### Attack Analysis

**1. Access Control**
Only LINK_TOKEN contract can call (L688). This is an ERC-677 callback. Only triggered when LINK is transferred via `transferAndCall` to this contract. No external entity can call this directly.
**VERDICT: SAFE**

**2. Reward Manipulation**
An attacker could try to manipulate the reward by:
- Donating when sub balance is low (high multiplier): Legitimate behavior. The multiplier rewards donations when the subscription needs LINK most.
- Manipulating the LINK/ETH price feed: The feed is a Chainlink aggregator -- cannot be manipulated by a single user.
- Manipulating purchaseInfo().priceWei: This comes from the Game contract's current level pricing. During a VRF stall, pricing is frozen. No manipulation path.
- Donating 0 LINK: Rejected at L689.
- Donating to an invalid subscription: getSubscription reverts or returns 0 balance.
**VERDICT: SAFE**

**3. Re-entrancy via creditLinkReward**
coinLinkReward.creditLinkReward at L725 calls the Coin contract. If Coin has a callback or hook that calls back to Admin, what state could it exploit?
- onTokenTransfer: msg.sender must be LINK_TOKEN, not Coin. Blocked.
- shutdownVrf: msg.sender must be GAME. Blocked.
- vote/propose: These don't depend on onTokenTransfer's state.
- No reentrant path exists.
**VERDICT: SAFE**

**4. this.linkAmountToEth External Self-Call**
At L712, the function calls `this.linkAmountToEth(amount)` as an EXTERNAL call to itself. This is used to wrap the view function in try/catch (internal view calls can't be caught). The function is `external view`, so it cannot modify state. No reentry risk.
**VERDICT: SAFE**

**5. Edge Cases**
- **priceWei == 0**: Handled at L720 (silent return, no reward). This occurs if the game hasn't started or pricing is zero. **SAFE**.
- **Extreme multiplier**: At subBal == 0: mult = 3e18 (3x). At subBal == 200e18: mult = 1e18 (1x). At subBal == 1000e18: mult = 0 (no reward). Continuous and bounded. **SAFE**.
- **Large donation amount**: If amount is very large, `amount * uint256(answer)` could overflow uint256 at L754. LINK total supply is 1B tokens = 1e27. Max answer for LINK/ETH is ~0.01 ETH = 1e16. Product: 1e27 * 1e16 = 1e43. uint256 max is ~1.16e77. No overflow. **SAFE**.
**VERDICT: SAFE**

**6. Silent Failures**
Multiple early-return paths that silently skip rewards: mult == 0 (L709), feed failure (L715), ethEquivalent == 0 (L717), priceWei == 0 (L720), credit == 0 (L723). In all cases, the LINK has ALREADY been forwarded to the subscription at L703. The donor gets their LINK donation processed but no BURNIE reward. This is correct: the donation is the primary purpose, the reward is a bonus.
**VERDICT: SAFE**

---

## LOW TIER

---

## A-02: DegenerusAdmin::setLinkEthPriceFeed (L357-368)

### Call Tree
```
setLinkEthPriceFeed(feed) [L357-368]
  |-- onlyOwner modifier [L322-325]
  |     |-- vault.isVaultOwner(msg.sender) [L323] -> Vault external view
  |-- current = linkEthPriceFeed [L358]
  |-- if _feedHealthy(current): revert FeedHealthy [L359]
  |     |-- _feedHealthy(feed) [L777-802]
  |     |     |-- if feed == address(0): return false [L778]
  |     |     |-- try IAggregatorV3(feed).latestRoundData() [L779]
  |     |     |     |-- health checks: answer > 0, updatedAt != 0, answeredInRound >= roundId, not future, not stale [L786-791]
  |     |     |     |-- try IAggregatorV3(feed).decimals() [L793]
  |     |     |     |     |-- if dec != 18: return false [L794]
  |     |     |     |-- catch: return false [L796]
  |     |     |-- catch: return false [L800]
  |-- if feed != address(0) AND IAggregatorV3(feed).decimals() != 18: revert InvalidFeedDecimals [L360-365]
  |-- linkEthPriceFeed = feed [L366]
  |-- emit LinkEthFeedUpdated(feed) [L367]
```

### Storage Writes (Full Tree)
| Variable | Location | Written Value |
|----------|----------|---------------|
| linkEthPriceFeed | L366 | feed (new address or address(0)) |

### Attack Analysis

**1. Access Control**: onlyOwner (DGVE majority holder). **SAFE**.

**2. Feed Replacement Logic**
The function only allows replacement when the CURRENT feed is unhealthy (L359). This prevents replacing a working feed. If the current feed goes stale (>1 day old), becomes unreachable, or returns bad data, the owner can replace it. Setting feed to address(0) disables the reward system entirely.
**VERDICT: SAFE** -- defensive design prevents disrupting a working feed.

**3. Malicious Feed**
Owner could set a malicious feed that returns inflated LINK/ETH prices. This would inflate BURNIE rewards for LINK donations. However: (a) the owner IS the DGVE majority holder, (b) BURNIE inflation only affects the internal game economy, not ETH withdrawals, (c) the feed must pass the decimals check (returns 18). A malicious feed could still return manipulated prices.
**VERDICT: SAFE** -- owner trust assumption. A compromised owner can do worse things.

---

## A-03: DegenerusAdmin::swapGameEthForStEth (L374-377)

### Call Tree
```
swapGameEthForStEth() [L374-377]
  |-- onlyOwner modifier [L322-325]
  |-- if msg.value == 0: revert InvalidAmount [L375]
  |-- gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value) [L376] -> Game
```

### Storage Writes: None in DegenerusAdmin (delegates to Game).

### Attack Analysis
Pure pass-through. Owner sends ETH, Game swaps to stETH for the owner. Access control via onlyOwner. ETH amount is msg.value (cannot be manipulated). The recipient is msg.sender (the owner).
**VERDICT: SAFE**

---

## A-04: DegenerusAdmin::stakeGameEthToStEth (L379-381)

### Call Tree
```
stakeGameEthToStEth(amount) [L379-381]
  |-- onlyOwner modifier [L322-325]
  |-- gameAdmin.adminStakeEthForStEth(amount) [L380] -> Game
```

### Storage Writes: None in DegenerusAdmin.

### Attack Analysis
Pass-through to Game's adminStakeEthForStEth. Owner-only. The amount parameter is forwarded directly. Access control on the Game side also checks the caller is Admin contract.
**VERDICT: SAFE**

---

## A-05: DegenerusAdmin::setLootboxRngThreshold (L383-385)

### Call Tree
```
setLootboxRngThreshold(newThreshold) [L383-385]
  |-- onlyOwner modifier [L322-325]
  |-- gameAdmin.setLootboxRngThreshold(newThreshold) [L384] -> Game
```

### Storage Writes: None in DegenerusAdmin.

### Attack Analysis
Pass-through. Owner-only. Parameter forwarded directly.
**VERDICT: SAFE**

---

## Category D View/Pure Analysis

### A-D1: circulatingSupply (L520-524)
```solidity
return sDGNRS.totalSupply() - sDGNRS.balanceOf(SDGNRS) - sDGNRS.balanceOf(DGNRS);
```
Reads totalSupply and subtracts balances of two exclusion addresses (the sDGNRS contract itself and the DGNRS wrapper). This gives "tokens held by actual users/voters."
**Potential issue:** If totalSupply < balanceOf(SDGNRS) + balanceOf(DGNRS), this underflows. Solidity 0.8.34 reverts on underflow. This would make propose() revert (cannot create proposals). This is only possible if protocol sDGNRS accounting is broken (minted tokens exceed total supply). **SAFE** under normal operation.

### A-D2: threshold (L530-539)
Step function based on elapsed time from proposal creation. Returns 5000 (50%) for first 48h, decaying to 500 (5%) at 144-168h, then 0 after 168h.
**Note:** `proposals[proposalId].createdAt` could be 0 for an uninitialized proposal, making `elapsed = block.timestamp`. For current timestamps, this means elapsed > 168h, returning 0. Used in vote() where the proposal is already validated as Active with createdAt != 0. **SAFE**.

### A-D3: canExecute (L544-556)
View function that mirrors the execute condition in vote(). Does not modify state. Includes its own stall check. **SAFE**.

### A-D4: linkAmountToEth (L734-755)
External view. Converts LINK to ETH using Chainlink price feed with comprehensive staleness checks (answer > 0, updatedAt != 0, answeredInRound >= roundId, not future, not stale). **SAFE**.

### A-D5: _linkRewardMultiplier (L758-774)
Private pure. Piecewise linear: 3x at 0 LINK, 1x at 200 LINK, 0x at 1000 LINK.
- At subBal == 0: delta = 0, return 3e18. **Correct**.
- At subBal == 200e18: delta = 2e18, return 3e18 - 2e18 = 1e18. **Correct**.
- At subBal == 201e18: excess = 1e18, delta2 = 1e18/800e18 = 0.00125e18, return 1e18 - 0.00125e18 ~= 0.99875e18. **Correct** -- smooth transition.
- At subBal == 1000e18: returns 0. **Correct**.
- At subBal == 999e18: excess = 799e18, delta2 = 799e18*1e18/800e18 = 0.99875e18, return 1e18 - 0.99875e18 = 0.00125e18. Small but non-zero. **Correct**.
**SAFE** -- continuous, bounded, no discontinuities.

### A-D6: _feedHealthy (L777-802)
Private view. Comprehensive health check: null address, latestRoundData revert, bad answer, zero updatedAt, round mismatch, future timestamp, staleness, wrong decimals. All failure modes return false. **SAFE**.

---

## Findings Summary

| ID | Function | Angle | Verdict | Severity |
|----|----------|-------|---------|----------|
| F-01 | vote (A-07) | Cross-contract state desync | INVESTIGATE | INFO |
| F-02 | vote (A-07) | Zero circulatingSnapshot | INVESTIGATE | INFO |
| F-03 | shutdownVrf (A-08) | No LINK recovery path | INVESTIGATE | LOW |
| F-04 | _executeSwap (A-10) | Silent catch on old sub cancel | INVESTIGATE | INFO |
| F-05 | shutdownVrf (A-08) | LINK stuck after failed transfer | INVESTIGATE | INFO |

### F-01: Vote Weight Inflation via sDGNRS Transfer
**Function:** vote (L452-517)
**Line(s):** L470 (weight from live balance), L487 (weight recorded)
**Scenario:** Voter A (100 sDGNRS) votes, transfers to Voter B, B votes with combined weight. Total recorded approveWeight exceeds actual circulating sDGNRS.
**Impact:** Potential governance threshold bypass. Mitigated by: symmetry (both sides can do it), bounded by total supply, honest majority assumption, only during VRF stall.
**Suggested Severity:** INFO -- inherent to live-balance voting without snapshots.

### F-02: Zero circulatingSnapshot Allows Single-Voter Execution
**Function:** vote (L452-517), propose (L398-445)
**Line(s):** L438 (snapshot set), L502 (threshold check)
**Scenario:** Admin proposes when circulatingSupply() == 0. Any voter with sDGNRS > 0 can execute immediately.
**Impact:** Bypasses meaningful governance. Requires zero circulating supply (near-impossible in practice) AND a new sDGNRS holder to emerge.
**Suggested Severity:** INFO -- theoretical edge case, self-resolving.

### F-03: No LINK Recovery After Failed shutdownVrf Transfer
**Function:** shutdownVrf (L651-674)
**Line(s):** L665 (transfer wrapped in try/catch), L656 (subscriptionId zeroed before transfer attempt)
**Scenario:** LINK transfer to vault fails (contract issue, LINK token paused, etc.). subscriptionId is already 0. No function exists to retry or sweep LINK from Admin contract.
**Impact:** Permanent LINK lock in Admin contract. Amount: whatever LINK balance Admin holds at game-over.
**Suggested Severity:** LOW -- requires LINK transfer failure (unlikely with standard LINK token), but no recovery path exists.

### F-04: Silent Catch on Old Subscription Cancellation in _executeSwap
**Function:** _executeSwap (L566-627)
**Line(s):** L581-588
**Scenario:** Old VRF coordinator's cancelSubscription fails silently. Old subscription remains active with allocated LINK. Admin contract loses reference to old subscription.
**Impact:** LINK in old subscription is unrecoverable via this contract. Amount depends on old subscription balance.
**Suggested Severity:** INFO -- intentional defensive design for malicious/broken coordinators.

### F-05: LINK Stuck After Failed Shutdown Transfer
**Function:** shutdownVrf (L651-674)
**Line(s):** L664-671
**Scenario:** linkToken.transfer(VAULT, bal) fails. LINK stays in Admin. No sweep function. subscriptionId already 0, so onTokenTransfer reverts (L692). LINK is permanently stuck.
**Impact:** Same as F-03 -- permanent LINK lock. This is the specific failure mode.
**Suggested Severity:** INFO (part of F-03).

---

*Mad Genius attack analysis complete: 2026-03-25*
*All 11 state-changing functions analyzed with full call trees, storage write maps, and 10-angle attack analysis.*
*5 findings flagged for Skeptic review.*
