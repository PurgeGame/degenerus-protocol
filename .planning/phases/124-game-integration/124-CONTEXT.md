# Phase 124: Game Integration - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire DegenerusCharity into the live game contracts — resolveLevel hook at level transitions and handleGameOver call at gameover. INTG-01 (yield surplus routing) and INTG-03 (stETH-first restriction) were pulled forward to Phase 123 and are complete. INTG-04 (claimYield) is dropped — the lazy pull in burn() is sufficient.

</domain>

<decisions>
## Implementation Decisions

### resolveLevel Hook
- **D-01:** Add `resolveLevel` call in `_finalizeRngRequest` inside the `if (isTicketJackpotDay && !isRetry)` block, after the level increment at AdvanceModule line 1349.
- **D-02:** No gas cap. Regular external call. RNG request path is low gas and resolveLevel iteration is bounded (max ~6-10 proposals per level).
- **D-03:** No try/catch. Direct call. These are our contracts — a revert is a bug we want to surface, not swallow.

### handleGameOver Wiring
- **D-04:** Call `DegenerusCharity.handleGameOver()` from the game's gameover path to burn all unallocated GNRUS and set finalized state.
- **D-05:** Place in `handleGameOverDrain` (GameOverModule) after game state is set but before fund distribution, since handleGameOver only burns GNRUS (no ETH flow).
- **D-06:** No try/catch. Direct call — same rationale as D-03.

### Scope Reduction
- **D-07:** INTG-01 (yield surplus routing to GNRUS via `_addClaimableEth`) already complete in Phase 123 — JackpotModule lines 912-916.
- **D-08:** INTG-03 (stETH-first restricted to VAULT-only) already complete in Phase 123 — DegenerusGame line 1353.
- **D-09:** INTG-04 (claimYield) dropped entirely. The `burn()` function on DegenerusCharity already calls `game.claimWinnings(address(this))` lazily when on-hand funds are insufficient (line 297). No separate permissionless pull function needed.

### Claude's Discretion
- Test design and organization
- NatSpec for the new hook calls
- Exact placement within handleGameOverDrain (before vs after specific state changes)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### resolveLevel Hook Target
- `contracts/modules/DegenerusGameAdvanceModule.sol` lines 1317-1379 — `_finalizeRngRequest()` where resolveLevel hook goes (inside `isTicketJackpotDay && !isRetry` block after line 1349)

### handleGameOver Hook Target
- `contracts/modules/DegenerusGameGameOverModule.sol` lines 68-163 — `handleGameOverDrain()` where handleGameOver call goes
- `contracts/modules/DegenerusGameGameOverModule.sol` lines 165-205 — `handleFinalSweep()` and `_sendToVault()` for context on gameover fund distribution

### DegenerusCharity Contract
- `contracts/DegenerusCharity.sol` lines 443-499 — `resolveLevel()` function being called
- `contracts/DegenerusCharity.sol` lines 331-343 — `handleGameOver()` function being called
- `contracts/DegenerusCharity.sol` lines 273-320 — `burn()` with lazy pull (confirms INTG-04 drop is safe)

### Already-Wired Integration (Phase 123)
- `contracts/modules/DegenerusGameJackpotModule.sol` lines 885-920 — `_distributeYieldSurplus()` already routes to GNRUS
- `contracts/DegenerusGame.sol` lines 1352-1355 — `claimWinningsStethFirst()` already VAULT-only

### Phase 123 Context
- `.planning/phases/123-degeneruscharity-contract/123-CONTEXT.md` — D-11 (resolveLevel called by game), D-14 (pull model)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DegenerusCharity.resolveLevel(uint24)` — already tested standalone in Phase 123, just needs game caller
- `DegenerusCharity.handleGameOver()` — already implemented with `onlyGame` modifier, burns unallocated GNRUS
- `ContractAddresses.GNRUS` — already defined at address 0x3C4293F66941ECa00f4950C10d4255d5c271bAeF

### Established Patterns
- try/catch on external calls from hot paths (see `_tryRequestRng` at AdvanceModule line 1288-1314 for pattern)
- `onlyGame` modifier on CHARITY for game-only hooks
- `dgnrs.burnRemainingPools()` call at GameOverModule line 162 — similar end-of-game cleanup hook

### Integration Points
- `_finalizeRngRequest` line 1349 (`level = lvl`) — resolveLevel goes right after this
- `handleGameOverDrain` line 162 (`dgnrs.burnRemainingPools()`) — handleGameOver goes alongside this
- GameOverModule `_sendToVault` line 204 already sends 34% to GNRUS — handleGameOver must fire before this

</code_context>

<specifics>
## Specific Ideas

- The user explicitly rejected gas caps — resolveLevel is bounded and advanceGame gas is not a concern here.
- The user explicitly dropped INTG-04 (claimYield) — the lazy pull in burn() handles it.
- This is pure wiring — two try/catch external calls, minimal contract changes.

</specifics>

<deferred>
## Deferred Ideas

- **INTG-04 claimYield()** — explicitly dropped by user. Lazy pull in burn() is sufficient. Could revisit if gas optimization of burn() becomes relevant.

</deferred>

---

*Phase: 124-game-integration*
*Context gathered: 2026-03-26*
