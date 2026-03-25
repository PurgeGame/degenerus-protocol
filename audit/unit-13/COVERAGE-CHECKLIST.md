# Unit 13: Admin + Governance -- Taskmaster Coverage Checklist

**Phase:** 115
**Contract:** DegenerusAdmin.sol (803 lines)
**Generated:** 2026-03-25

---

## Contract: DegenerusAdmin (L149-803)

### Function Inventory

| # | Function | Lines | Visibility | State-Changing | Category | Risk Tier |
|---|----------|-------|------------|----------------|----------|-----------|
| A-01 | constructor() | L331-349 | internal (deploy) | YES | B | MEDIUM |
| A-02 | setLinkEthPriceFeed(feed) | L357-368 | external onlyOwner | YES | B | LOW |
| A-03 | swapGameEthForStEth() | L374-377 | external payable onlyOwner | YES | B | LOW |
| A-04 | stakeGameEthToStEth(amount) | L379-381 | external onlyOwner | YES | B | LOW |
| A-05 | setLootboxRngThreshold(newThreshold) | L383-385 | external onlyOwner | YES | B | LOW |
| A-06 | propose(newCoordinator, newKeyHash) | L398-445 | external | YES | B | CRITICAL |
| A-07 | vote(proposalId, approve) | L452-517 | external | YES | B | CRITICAL |
| A-08 | shutdownVrf() | L651-674 | external | YES | B | HIGH |
| A-09 | onTokenTransfer(from, amount, data) | L683-727 | external | YES | B | MEDIUM |
| A-10 | _executeSwap(proposalId) | L566-627 | internal | YES | C* | CRITICAL |
| A-11 | _voidAllActive(exceptId) | L631-643 | internal | YES | C | MEDIUM |

*A-10 elevated to standalone analysis per D-05 (most dangerous internal function)*

### View/Pure Functions (Category D -- no attack analysis)

| # | Function | Lines | Notes |
|---|----------|-------|-------|
| A-D1 | circulatingSupply() | L520-524 | public view, reads sDGNRS.totalSupply - 2 exclusions |
| A-D2 | threshold(proposalId) | L530-539 | public view, step-function decay by elapsed time |
| A-D3 | canExecute(proposalId) | L544-556 | external view, combines state + stall + threshold checks |
| A-D4 | linkAmountToEth(amount) | L734-755 | external view, Chainlink price feed conversion |
| A-D5 | _linkRewardMultiplier(subBal) | L758-774 | private pure, piecewise-linear multiplier 3x->0x |
| A-D6 | _feedHealthy(feed) | L777-802 | private view, price feed health check |

### Storage Write Map

| Function | Storage Variables Written |
|----------|--------------------------|
| constructor (A-01) | coordinator, subscriptionId, vrfKeyHash |
| setLinkEthPriceFeed (A-02) | linkEthPriceFeed |
| swapGameEthForStEth (A-03) | (none in this contract -- delegates to Game) |
| stakeGameEthToStEth (A-04) | (none in this contract -- delegates to Game) |
| setLootboxRngThreshold (A-05) | (none in this contract -- delegates to Game) |
| propose (A-06) | proposalCount, proposals[id].*, activeProposalId[msg.sender] |
| vote (A-07) | proposals[id].state (expired), proposals[id].approveWeight, proposals[id].rejectWeight, votes[id][voter], voteWeight[id][voter], proposals[id].state (killed) |
| _executeSwap (A-10) | proposals[id].state, coordinator, subscriptionId, vrfKeyHash, voidedUpTo, proposals[*].state (via _voidAllActive) |
| _voidAllActive (A-11) | proposals[i].state (for each active), voidedUpTo |
| shutdownVrf (A-08) | subscriptionId |
| onTokenTransfer (A-09) | (none in this contract -- LINK forwarded, reward credited externally) |

### Cross-Contract Call Map

| Function | External Calls | Target | Line |
|----------|---------------|--------|------|
| constructor (A-01) | createSubscription() | VRF Coordinator | L332 |
| constructor (A-01) | addConsumer(subId, GAME) | VRF Coordinator | L341 |
| constructor (A-01) | wireVrf(coordinator, subId, keyHash) | Game | L344-348 |
| setLinkEthPriceFeed (A-02) | _feedHealthy(current) -> latestRoundData() | Price Feed | L779 |
| setLinkEthPriceFeed (A-02) | decimals() | Price Feed | L362 |
| swapGameEthForStEth (A-03) | adminSwapEthForStEth{value}(sender, amount) | Game | L376 |
| stakeGameEthToStEth (A-04) | adminStakeEthForStEth(amount) | Game | L380 |
| setLootboxRngThreshold (A-05) | setLootboxRngThreshold(newThreshold) | Game | L384 |
| propose (A-06) | gameOver() | Game | L403 |
| propose (A-06) | lastVrfProcessed() | Game | L417 |
| propose (A-06) | isVaultOwner(msg.sender) | Vault | L421 |
| propose (A-06) | totalSupply() | sDGNRS | L521 (via circulatingSupply) |
| propose (A-06) | balanceOf(SDGNRS) | sDGNRS | L522 (via circulatingSupply) |
| propose (A-06) | balanceOf(DGNRS) | sDGNRS | L523 (via circulatingSupply) |
| propose (A-06) | balanceOf(msg.sender) | sDGNRS | L427 |
| vote (A-07) | lastVrfProcessed() | Game | L454 |
| vote (A-07) | balanceOf(msg.sender) | sDGNRS | L470 |
| vote (A-07) | threshold(proposalId) | self (view) | L498 |
| vote (A-07) -> _executeSwap | (see A-10 below) | multiple | - |
| _executeSwap (A-10) | cancelSubscription(oldSub, this) | Old VRF Coordinator | L582-583 |
| _executeSwap (A-10) | createSubscription() | New VRF Coordinator | L593-594 |
| _executeSwap (A-10) | addConsumer(newSubId, GAME) | New VRF Coordinator | L601-603 |
| _executeSwap (A-10) | updateVrfCoordinatorAndSub(coord, subId, keyHash) | Game | L608-612 |
| _executeSwap (A-10) | balanceOf(this) | LINK Token | L615 |
| _executeSwap (A-10) | transferAndCall(newCoord, bal, subId) | LINK Token | L618-620 |
| shutdownVrf (A-08) | cancelSubscription(subId, VAULT) | VRF Coordinator | L659 |
| shutdownVrf (A-08) | balanceOf(this) | LINK Token | L663 |
| shutdownVrf (A-08) | transfer(VAULT, bal) | LINK Token | L665 |
| onTokenTransfer (A-09) | gameOver() | Game | L693 |
| onTokenTransfer (A-09) | getSubscription(subId) | VRF Coordinator | L697-699 |
| onTokenTransfer (A-09) | transferAndCall(coord, amount, subId) | LINK Token | L703 |
| onTokenTransfer (A-09) | linkAmountToEth(amount) | self (external view) | L712 |
| onTokenTransfer (A-09) | purchaseInfo() | Game | L719 |
| onTokenTransfer (A-09) | creditLinkReward(from, credit) | Coin | L725 |

### Coverage Summary

| Metric | Count |
|--------|-------|
| Total functions | 17 |
| State-changing (Categories B+C) | 11 |
| Category B (full attack analysis) | 9 |
| Category C (standalone due to D-05) | 1 (_executeSwap) |
| Category C (traced via parent) | 1 (_voidAllActive) |
| View/pure (Category D) | 6 |
| CRITICAL-tier | 3 (propose, vote, _executeSwap) |
| HIGH-tier | 1 (shutdownVrf) |
| MEDIUM-tier | 3 (constructor, onTokenTransfer, _voidAllActive) |
| LOW-tier | 3 (setLinkEthPriceFeed, swapGameEthForStEth, stakeGameEthToStEth, setLootboxRngThreshold) |
| External call sites | 30+ |

---

### Governance State Machine

```
PROPOSAL LIFECYCLE:
  propose() -> ProposalState.Active (default 0)
  vote() -> if expired -> ProposalState.Expired
  vote() -> if approve threshold met -> _executeSwap() -> ProposalState.Executed
  vote() -> if reject threshold met -> ProposalState.Killed
  _voidAllActive() -> ProposalState.Killed (for all other Active proposals)

ACCESS PATHS:
  Admin (DGVE owner): propose after 20h stall -> vote -> execute
  Community (0.5% sDGNRS): propose after 7d stall -> vote -> execute
  Any sDGNRS holder: vote on any active proposal
  Game contract only: shutdownVrf (game-over)
  LINK token only: onTokenTransfer (ERC-677)
  Owner only: setLinkEthPriceFeed, swapGameEthForStEth, stakeGameEthToStEth, setLootboxRngThreshold
```

---

*Taskmaster checklist generated: 2026-03-25*
*Ready for Mad Genius attack analysis*
