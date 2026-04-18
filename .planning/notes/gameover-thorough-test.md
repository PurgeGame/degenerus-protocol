# Note: Thorough Game-Over Path Test (future phase)

**Captured:** 2026-04-18 during Phase 232.1 session
**Originator:** User directive
**Status:** Backlog — add to upcoming phase

## Motivation

Phase 232.1 Plan 02 shipped two focused game-over tests:
1. `testGameOverDrainsQueuedTickets` — verifies the best-effort dual-round drain fires when user tickets are queued.
2. `testGameOverCompletesWithoutUserPurchases` — verifies game-over transition completes even without user-queued tickets.

These cover the happy path and the best-effort-with-seeded-tickets path. A **thorough end-to-end regression test** is needed to prove:

## Coverage to add

1. **Catastrophic drain failure tolerance.** Manufacture a scenario where `processTicketBatch` reverts (e.g., queue over the block-gas limit) and verify `handleGameOverDrain` STILL runs and releases funds. The swallow-failure branch in `_handleGameOverPath` should be exercised — currently only covered by review, not by a forge test.

2. **Both-buffers-drain verification.** Pre-populate tickets in BOTH the read slot and the write slot (via careful swap timing or direct vm.store), then trigger game-over and verify all tickets are drained — round 1 empties read, swap moves write→read, round 2 drains.

3. **Liveness-trigger ticket-block audit.** Explicit negative tests for every ticket-adding path:
   - `purchase` (ETH)
   - `purchaseCoin` (BURNIE)
   - `openLootBox` (lootbox resolution produces tickets via `_queueTicketsScaled`)
   - Whale pass claim (via `_queueTicketRange`)
   - Vault perpetual ticket (check path)
   - Affiliate reward tickets (check path)
   Each should revert `E()` once `_livenessTriggered()` returns true. Must verify the block is comprehensive — no bypass paths exist.

4. **RNG manipulation attempt.** Simulate an attacker who observes the game-over VRF word becoming known on-chain, then attempts to add tickets. Verify the attempt reverts (liveness block). Optionally: verify that pre-liveness tickets still receive fair entropy (non-manipulable).

5. **Terminal jackpot eligibility audit.** Trace a winning path end-to-end: tickets purchased before liveness → drained with game-over entropy → `runTerminalJackpot` selects winners from the queue → winners' `claimableWinnings` updated. Assert the ticket-holder at the right `queueIdx` with the right traits actually received the correct share.

6. **Lootbox-origin ticket behavior at game-over.** Pre-purchase a lootbox. Trigger liveness. Attempt to open the lootbox — should revert. Verify the `lootboxEth` for that player is still part of `totalFunds` and gets swept into the pro-rata distribution in `handleGameOverDrain`.

7. **Multi-advance transition.** Drive game-over over many `advanceGame` calls with VRF retries, coordinator swaps mid-flight, mid-day RNG state, far-future tickets, and phase transitions active at trigger time. Verify the transition always converges to `gameOver=true` and no funds are locked.

8. **Non-determinism documentation test.** Capture the "game-over entropy substitution" known issue explicitly: a test that puts tickets in the read buffer under one RNG, triggers game-over before drain, and verifies the tickets receive game-over entropy rather than their "intended" RNG. Documents the behavior as a regression check so any future change that alters it gets flagged.

## Constraints

- Test file lives under `test/fuzz/GameOverRegression.t.sol` or similar (`test/fuzz/` root — matches the existing convention).
- Reuses Plan 02's event-capture instrumentation (`TraitsGenerated` topic + `vm.recordLogs`).
- Uses `vm.store` sparingly — prefer state-driving via real entry points (purchase, advance, VRF fulfillment) to keep tests production-realistic.
- Every assertion ties back to a CONTEXT.md D-X reference or a SPEC.md AC-N reference so traceability is preserved.

## Owner

To be scoped into a future phase (target: 232.2 or the next milestone cycle's game-over hardening pass). Not blocking for Phase 232.1 completion.
