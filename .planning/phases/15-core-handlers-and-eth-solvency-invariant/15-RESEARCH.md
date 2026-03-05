# Phase 15 Research: Core Handlers and ETH Solvency Invariant

**Phase:** 15 of 18
**Researched:** 2026-03-05
**Depends on:** Phase 14 (Foundry Infrastructure -- completed)
**Confidence:** HIGH

## Context

Phase 14 delivered: `DeployProtocol.sol` (22 contracts + 5 mocks), `VRFHandler.sol` (fulfill + time warp), `patchForFoundry.js` (address prediction), Makefile (`make invariant-test`), and `VRFLifecycle.t.sol` proving game advances past level 0 inside Foundry. The infrastructure is validated.

Phase 15 builds the fuzzing pipeline on top of that infrastructure: handler contracts that drive randomized call sequences, ghost variables for ETH flow tracking, and the ETH solvency invariant that validates the entire system end-to-end.

## Handler Architecture

### Why Three Handlers (Not One)

Foundry distributes calls uniformly across all functions registered via `targetContract()`. With a single monolithic handler containing 10+ functions, each gets ~10% of the call budget. Critical low-frequency actions (VRF fulfillment, whale purchases) get drowned out by high-frequency actions (ticket purchases).

Three focused handlers ensure each domain gets adequate coverage:

| Handler | Functions | Domain |
|---------|-----------|--------|
| GameHandler | purchase, advanceGame, claimWinnings | Core game loop + ETH in/out |
| VRFHandler | fulfillVrf, warpPastVrfTimeout, warpTime | RNG lifecycle + time |
| WhaleHandler | purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass | Whale mechanics |

VRFHandler already exists from Phase 14. GameHandler and WhaleHandler are new.

### Actor Management

Each handler maintains its own actor pool (10 addresses per handler). Actors are pre-funded with ETH via `vm.deal()`. The `useActor` modifier selects an actor deterministically from the fuzz seed and sets `vm.prank()` so the call appears to come from that actor.

No separate ActorManager contract needed -- the actor logic is simple enough to embed in each handler (3 lines: array, modifier, constructor loop).

### Ghost Variable Design

Ghost variables are handler-side accounting that shadows protocol state. They track cumulative ETH flows:

| Variable | Location | Tracks |
|----------|----------|--------|
| `ghost_totalDeposited` | GameHandler | ETH sent to game via purchase() |
| `ghost_totalClaimed` | GameHandler | ETH received via claimWinnings() |
| `ghost_whaleBundleDeposited` | WhaleHandler | ETH sent via purchaseWhaleBundle() |
| `ghost_lazyPassDeposited` | WhaleHandler | ETH sent via purchaseLazyPass() |
| `ghost_deityPassDeposited` | WhaleHandler | ETH sent via purchaseDeityPass() |
| `ghost_vrfFulfillments` | VRFHandler | Count of successful VRF fulfillments |

**Design principle:** Ghost variables must be trivially simple -- just accumulate amounts on success. If the ghost logic itself has a bug that matches a protocol bug, the invariant gives a false pass. Keep ghost update logic to a single `+=` statement after successful `try` calls.

## ETH Flow Paths

All ETH enters and exits the game contract through these paths:

### Inflows (ETH enters `address(game)`)
1. `purchase{value: X}(...)` -- ticket + lootbox purchases
2. `purchaseWhaleBundle{value: X}(...)` -- whale bundle
3. `purchaseLazyPass{value: X}(...)` -- lazy pass
4. `purchaseDeityPass{value: X}(...)` -- deity pass
5. `receive()` / direct ETH transfers (stETH rebasing can add wei)

### Outflows (ETH leaves `address(game)`)
1. `claimWinnings(player)` -- pull-pattern jackpot/endgame claims
2. `claimWinningsStethFirst()` -- vault/dgnrs stETH-first claims
3. `refundDeityPass(buyer)` -- deity pass refund after 24 months
4. Admin fee withdrawal (via admin contract)

### Internal Pool Accounting
The game tracks ETH obligations in four pools:
- `currentPrizePool` -- active jackpot distribution source
- `nextPrizePool` -- accumulating for next level
- `claimablePool` -- reserved for player withdrawals
- `futurePrizePool` -- unified reserve for future levels

**Solvency invariant:** `address(game).balance + steth.balanceOf(game) >= currentPrizePool + nextPrizePool + claimablePool + futurePrizePool`

This says the contract always holds enough ETH/stETH to cover all its obligations. If this ever fails, the protocol is insolvent.

## Invariant Assertion Design

### Primary: ETH Solvency
```
assert(address(game).balance + steth.balanceOf(game) >=
       game.currentPrizePoolView() + game.nextPrizePoolView() +
       game.claimablePoolView() + game.futurePrizePoolTotalView())
```

Uses view functions that expose the internal pool values. The `>=` accounts for yield surplus (stETH appreciation) and any untracked dust.

### Secondary: Ghost Accounting Reconciliation
```
totalGhostDeposited = gameHandler.ghost_totalDeposited()
                    + whaleHandler.ghost_whaleBundleDeposited()
                    + whaleHandler.ghost_lazyPassDeposited()
                    + whaleHandler.ghost_deityPassDeposited()

assert(totalGhostDeposited >= gameHandler.ghost_totalClaimed())
```

This says: total ETH deposited across all handlers must be >= total ETH claimed. A violation means either (a) ghost accounting is wrong, or (b) the protocol paid out more than it received.

### Tertiary: Balance Matches Ghost Delta
```
assert(address(game).balance >= totalGhostDeposited - totalGhostClaimed)
```

This is a weaker form that catches cases where ETH escapes the contract through unexpected paths.

## Handler Function Design

### GameHandler.purchase()
- Bound `qty` to [100, 4000] (0.25 to 10 tickets)
- Bound `lootboxAmt` to [0, 2 ether]
- Query `purchaseInfo()` for current price to compute cost
- Skip if cost > actor balance or game is over
- Ghost: `ghost_totalDeposited += msg.value` on success

### GameHandler.advanceGame()
- No input bounding needed (parameterless)
- Any actor can call
- Skip if game is over
- No ghost update (no ETH flows)

### GameHandler.claimWinnings()
- Track balance delta before/after
- Ghost: `ghost_totalClaimed += delta` on success
- Use try/catch (reverts if nothing to claim)

### WhaleHandler.purchaseWhaleBundle()
- Bound qty to [1, 5]
- Cost varies by level: use fixed 2.4 ETH * qty for levels 0-3
- Skip if cost > actor balance

### WhaleHandler.purchaseLazyPass()
- Cost: 0.24 ETH at levels 0-2, variable at level 3+
- Skip if insufficient balance

### WhaleHandler.purchaseDeityPass()
- Bound symbolId to [0, 31]
- Cost: 24 + T(n) ETH where T(n) = n*(n+1)/2
- Expensive -- actors need large ETH balance
- Skip if insufficient balance

## What Must Work

1. `make invariant-test` passes with zero invariant violations
2. `show_metrics = true` confirms >60% non-reverting call rate
3. Ghost accounting reconciles after every call
4. Game advances past level 0 in at least some fuzzer runs (confirmed by checking `game.level()` in a summary invariant)
5. All three handlers are registered as `targetContract()` and receive calls

## Suggested Plan Structure

- **15-01:** GameHandler + base EthSolvency invariant test scaffold
  - Implement GameHandler with purchase/advanceGame/claimWinnings
  - Create EthSolvency.inv.t.sol with primary solvency assertion
  - Register GameHandler + existing VRFHandler as targets
  - Verify: `make invariant-test` passes

- **15-02:** WhaleHandler + ghost variable reconciliation
  - Implement WhaleHandler with whale bundle/lazy/deity pass
  - Add ghost accounting invariant and balance reconciliation
  - Register all three handlers
  - Verify: invariant holds, ghost accounting reconciles

- **15-03:** Tuning + metrics verification
  - Adjust bound ranges based on revert rates
  - Add call counters for coverage analysis
  - Verify: >60% non-reverting calls, game advances past level 0
  - Add `invariant_callSummary()` to log metrics

---
*Research completed: 2026-03-05*
