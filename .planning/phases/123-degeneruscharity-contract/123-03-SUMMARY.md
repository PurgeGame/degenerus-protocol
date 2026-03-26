---
phase: 123-degeneruscharity-contract
plan: "03"
subsystem: DegenerusCharity (GNRUS) unit tests
tags: [test, hardhat, governance, soulbound, burn, gnrus]
dependency_graph:
  requires: [123-01]
  provides: [CHAR-01, CHAR-02, CHAR-03, CHAR-04]
  affects: []
tech_stack:
  added: [MockSDGNRSCharity, MockGameCharity, MockVaultCharity]
  patterns: [hardhat_setCode mock injection, impersonation-based access control testing]
key_files:
  created:
    - test/unit/DegenerusCharity.test.js
    - contracts/mocks/MockSDGNRSCharity.sol
    - contracts/mocks/MockGameCharity.sol
    - contracts/mocks/MockVaultCharity.sol
  modified: []
decisions:
  - Used hardhat_setCode mock injection at ContractAddresses addresses instead of full protocol deploy -- DegenerusCharity is not yet in deploy pipeline
  - Created 3 minimal mock contracts (sDGNRS, Game, Vault) to isolate DegenerusCharity from 23-contract protocol stack
  - Tests cover actual contract (name "Degenerus Donations", symbol "GNRUS", 18 decimals) not original plan spec
metrics:
  duration: 5min
  completed: "2026-03-26T05:24:00Z"
---

# Phase 123 Plan 03: DegenerusCharity Unit Tests Summary

69 Hardhat unit tests covering all DegenerusCharity (GNRUS) contract behaviors -- soulbound enforcement, ETH-preferred burn redemption with lazy claim, sDGNRS-weighted governance lifecycle, and gameover finalization.

## What Was Done

### Task 1: Create DegenerusCharity Hardhat unit tests

Created `test/unit/DegenerusCharity.test.js` with 69 tests across 9 describe blocks:

**Token Metadata (8 tests):**
- name, symbol, decimals, totalSupply, unallocated pool balance, currentLevel, proposalCount, finalized

**Soulbound Enforcement (3 tests):**
- transfer, transferFrom, approve all revert with TransferDisabled

**Burn Redemption (11 tests):**
- InsufficientBurn on 0 and sub-MIN_BURN amounts
- totalSupply reduction, balanceOf zeroed on full burn
- Transfer + Burn events emitted
- Proportional ETH payout, proportional stETH payout
- Zero backing (no revert), ETH-preferred (stETH fills remainder)
- Last-holder sweep on exact balance burn
- Lazy claim: pulls from game.claimWinnings when on-hand insufficient
- Underflow revert on insufficient balance

**Governance -- Propose (11 tests):**
- ProposalCreated event with correct fields
- proposalCount and levelProposalCount increment
- sDGNRS totalSupply snapshot on first proposal
- ZeroAddress and RecipientIsContract reverts
- Community: InsufficientStake below 0.5%, AlreadyProposed on second attempt
- Vault owner: 5 proposals per level, ProposalLimitReached on 6th
- Vault owner does not consume community slot
- getProposal and getLevelProposals view functions

**Governance -- Vote (7 tests):**
- approveWeight/rejectWeight correctly incremented
- AlreadyVoted on double-vote, InvalidProposal on bad IDs
- InsufficientStake for 0-balance voter
- Vault owner 5% bonus applied
- Independent voting on multiple proposals

**Governance -- resolveLevel (11 tests):**
- 2% of unallocated GNRUS distributed to winner
- currentLevel increment, levelResolved flag set
- LevelNotActive on wrong level, LevelAlreadyResolved guard
- LevelSkipped: no proposals, all net-negative, all net-zero
- Tie-breaking: first-submitted (lower proposalId) wins
- 2% decay: second level distributes less than first
- Transfer event from contract to recipient
- Highest net-positive proposal selected

**handleGameOver (6 tests):**
- Burns all unallocated GNRUS, sets finalized=true
- Unauthorized revert for non-game caller
- AlreadyFinalized on second call
- Transfer event emitted
- Partial distribution: only burns remaining unallocated

**ETH Reception (2 tests):**
- Accepts ETH from anyone, accepts ETH from game

**Edge Cases (5 tests):**
- Previous-level proposals inaccessible for voting
- Community re-propose after level resolve
- Vault owner proposal count resets per level
- Supply conservation: unallocated + holders = totalSupply
- Vault owner snapshot locks on first action

### Test Infrastructure

Created 3 minimal mock contracts for isolated testing:

- **MockSDGNRSCharity.sol** (16 lines): Settable totalSupply and balanceOf for governance vote weight
- **MockGameCharity.sol** (28 lines): claimWinnings (sends ETH), claimableWinningsOf, gameOver for burn lazy-claim
- **MockVaultCharity.sol** (11 lines): Settable isVaultOwner for vault owner proposal/vote tests

Mocks deployed via `hardhat_setCode` at compile-time ContractAddresses positions, enabling isolated unit testing without deploying the full 23-contract protocol stack.

## Deviations from Plan

### Adjusted to match actual contract

**1. [Adjusted] Token metadata matches actual contract, not plan spec**
- Plan specified name "Degenerus Charity" -- actual contract uses "Degenerus Donations"
- Tests verify actual contract values: name="Degenerus Donations", symbol="GNRUS", decimals=18

**2. [Adjusted] No claimYield test -- function does not exist in contract**
- Plan listed claimYield() as a testable function but the actual DegenerusCharity.sol has no claimYield function
- The contract uses lazy claim inside burn() via game.claimWinnings() -- tested in burn redemption suite

**3. [Adjusted] RecipientIsContract check added to propose tests**
- Actual contract has `if (recipient.code.length != 0) revert RecipientIsContract()` -- not in original plan
- Added test verifying this behavior

**4. [Adjusted] Mock approach instead of full deploy fixture**
- DegenerusCharity is not yet in the DEPLOY_ORDER (N+23 pipeline) -- GNRUS address is placeholder
- Used hardhat_setCode mock injection instead of deployFullProtocol fixture

## Commits

| Task | Commit | Files |
|------|--------|-------|
| 1 (tests) | c2e5ee9a | test/unit/DegenerusCharity.test.js |
| 1 (mocks) | e3a03844 | contracts/mocks/MockSDGNRSCharity.sol, MockGameCharity.sol, MockVaultCharity.sol |

## Known Stubs

None -- all tests are fully wired with actual contract interactions via mocks.

## Self-Check: PASSED

- [x] test/unit/DegenerusCharity.test.js EXISTS
- [x] contracts/mocks/MockSDGNRSCharity.sol EXISTS
- [x] contracts/mocks/MockGameCharity.sol EXISTS
- [x] contracts/mocks/MockVaultCharity.sol EXISTS
- [x] Commit c2e5ee9a EXISTS
- [x] Commit e3a03844 EXISTS
- [x] 69 tests passing, 0 failures
