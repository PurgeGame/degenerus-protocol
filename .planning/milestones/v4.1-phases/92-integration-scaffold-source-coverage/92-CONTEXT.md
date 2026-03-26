# Phase 92: Integration Scaffold + Source Coverage - Context

**Gathered:** 2026-03-23
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Write a comprehensive Foundry integration test suite (test/fuzz/TicketLifecycle.t.sol) that deploys the full 23-contract protocol via DeployProtocol and exercises all 6 ticket sources end-to-end through multiple level transitions. Verify that tickets queued by each source are eventually fully processed (queue length drops to zero, ticketsOwedPacked zeroed) with no stranding across level transitions.

Ticket sources: direct ETH purchase (purchase phase, jackpot phase, last-day), lootbox open (near and far rolls), whale bundle. Edge cases: constructor-queued FF tickets drain one-per-transition, _prepareFutureTickets only touches +1..+4 read range (not FF), read-slot queues empty after full level cycle, write-slot tickets survive swapAndFreeze.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP phase goal, success criteria, and existing test patterns (FarFutureIntegration.t.sol, TicketRouting.t.sol) to guide decisions.

Key constraints from user:
- advanceGame is NOT considered permissionless (it's the resolver, not a manipulation vector)
- Purchase routing should ALWAYS write to write slot regardless of rngLocked state — double-buffer is the structural guarantee
- Test patterns: DeployProtocol base, vm.store prize pool seeding (slot 3), vm.load queue inspection (slot 15)
- Note: test/fuzz/TicketLifecycle.t.sol may already exist from a prior attempt — review and extend or replace as needed

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `test/fuzz/helpers/DeployProtocol.sol` — full 23-contract protocol deployment with mock VRF/stETH/LINK
- `test/fuzz/FarFutureIntegration.t.sol` — level-driving loop, _seedNextPrizePool, _buyTickets, _fulfillVrfIfPending, _ffQueueLength via vm.load
- `test/fuzz/TicketRouting.t.sol` — TicketRoutingHarness with queue inspection helpers
- `test/fuzz/TicketEdgeCases.t.sol` — TLKeyComputer-equivalent with tqWriteKey/tqReadKey/tqFarFutureKey

### Established Patterns
- Storage slot inspection via vm.load(address(game), keccak256(abi.encode(key, slot)))
- Prize pool seeding: prizePoolsPacked at slot 3, [future:128][next:128] layout
- Ticket queue: mapping at slot 15, ticketsOwedPacked at slot 16
- Level driving: warp 1 day, seed pool to 49.9 ETH, buy tickets, loop advanceGame + VRF fulfillment
- ticketWriteSlot at storage slot 24 (byte offset 0)

### Integration Points
- DegenerusGame.purchase() — direct ticket purchase (routes via MintModule._processDirectPurchase)
- DegenerusGame.purchaseInfo() — returns (level, inJackpotPhase, lastPurchaseDay, rngLocked, priceWei)
- MintModule: jackpotPhaseFlag ? level : level+1 routing, with last-day override
- LootboxModule._rollTargetLevel: 90% near (0-4), 10% far (5-50), base = level+1
- AdvanceModule._prepareFutureTickets: +1..+4 from base level (read queues only)
- AdvanceModule phase transition: FF drain at purchaseLevel+4 = level+5

</code_context>

<specifics>
## Specific Ideas

- Existing TicketLifecycle.t.sol from prior session attempt — review for reuse
- The near/far boundary is > level + 5 (unified), meaning level+5 = near, level+6 = far
- Constructor pre-queues 2 addresses (sDGNRS + VAULT) per level 1-100, FF at levels 6+
- Vault perpetual tickets queued at purchaseLevel+99 (always FF)
- _swapAndFreeze toggles ticketWriteSlot via XOR, so write becomes read

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
