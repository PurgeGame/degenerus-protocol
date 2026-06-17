# Phase 422 — GAMEOVER (Terminal-Branch Liveness) — Findings

**Phase:** 422 GAMEOVER · **Date:** 2026-06-17 · **Reqs:** GAMEOVER-01..03
**Subject:** analysis ran on frozen tree `4a67209a` @ `0bb7deca`; conclusions hold at the current tree `4970ba5b` @ `73eb242a` (the MIDRNG-02 fix touches only the mid-day drain gate, not any terminal entrypoint).
**Method:** cross-model council (Gemini 3 Pro + Codex) = NET-1 · Claude NET-2 (5 break-attempt verifiers + completeness critic + adversarial refute; gas claim measured against the real `advanceGame` bytecode) · orchestrator crux. Honest admin/governance assumed; ordinary-player economic reachability in scope.

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MEDIUM real findings

Every GAMEOVER branch finalizes for any reachable pre-gameover state. The convergent **FLIP-tombstone CATASTROPHE candidate is REFUTED → INFO** (economically unreachable). One MEDIUM-by-design forfeit (ETH conserved, USER disposition). Worst-case terminal gas ~7.2M, well under the 16.7M ceiling.

## Leads adjudicated

| Lead | NET-1 (council) | NET-2 + crux | Disposition |
|------|-----------------|--------------|-------------|
| **GAMEOVER-01** terminal decimator no-alias / no-strand / no-underflow | gemini + codex REFUTED | **HOLDS** — `lvl+1` isolation (crux-confirmed in 420); uint24 level / uint96 poolWei / uint128 burn casts all economically unreachable; claim reads the same `lvl+1` slot; `handleFinalSweep` zeroes `claimablePool` by direct assignment (no underflow); pre/post-sweep claim paths guarded | **HOLDS** |
| **GAMEOVER-02a** FLIP `tombstoneAtGameOver` uint128 overflow → finalization wedge | **gemini + codex BOTH flagged CATASTROPHE**, both punting on reachability | **REFUTED → INFO** (see below) | **REFUTED (INFO)** |
| **GAMEOVER-02b** other terminal callees revert + worst-case gas | gemini + codex REFUTED | **HOLDS** — sDGNRS/GNRUS `burnAtGameOver` are pure storage-zeroing with permanent `totalSupply ≥ balanceOf[self]` invariants (no underflow, no external call); worst-case composite (305-winner jackpot + 32-cap deity loop + decimator + 3 burns) **measured 6.25M, composite ~7.2M < 16.78M**; all-or-nothing latch rolls back cleanly on any callee revert (retryable) | **HOLDS** |
| **GAMEOVER-03** trigger transition + liveness gate + sweep sinks | gemini + codex REFUTED | **HOLDS** — `_handleGameOverPath` reachable for every terminal state (post-gameover sweep runs BEFORE the liveness gate); the three sinks (VAULT/SDGNRS/GNRUS, trusted) always accept (sDGNRS `receive` gate passes since the sweep runs as the Game via delegatecall); a VRF stall in the `lastPurchaseDay`/`jackpotPhaseFlag` window is recoverable via the governed coordinator swap; no mid-gameover partial-state wedge | **HOLDS** |
| **GAMEOVER-MED** degenerette/lootbox positions forfeited at liveness gameover | codex flagged MEDIUM | **HOLDS / MEDIUM-by-design** — the ETH backing in-flight bets/boxes is prize-pool ETH in the Game balance (not separate escrow); `handleGameOverDrain` captures `balance + steth` and redistributes to terminal pools/sinks → **ETH conserved, solvency preserved**; the per-player forfeit (resolveBets reverts / openHumanBoxes no-ops) matches prior-milestone gameover forfeits | **MEDIUM-by-design (USER call)** |

## GAMEOVER-02a — FLIP tombstone CATASTROPHE → REFUTED (economically unreachable)

`flip.tombstoneAtGameOver` (`FLIP:559`) does `vaultAllowance = _toUint128(vaultAllowance + 1e36)`, which reverts on uint128 overflow inside `handleGameOverDrain` before `GO_JACKPOT_PAID` commits — a revert there *would* wedge finalization. Both external models flagged it CATASTROPHE but left reachability open. NET-2's emission-bound derivation closes it:
- **Invariant:** `supplyIncUncirculated = totalSupply + vaultAllowance` (FLIP:19-20), so `vaultAllowance ≤ total FLIP ever minted`. `vaultEscrow` (the only unbounded-add path) is GAME/VAULT-only with **zero in-scope callers** (only the god-mode test).
- **Boundary:** overflow needs `vaultAllowance > uint128.max − 1e36 ≈ 3.39e38 wei ≈ 3.4e20 FLIP`. Seed emission is 8M FLIP; the only multiplicative path (auto-rebuy) needs **~34 consecutive max-bonus coinflip wins on separate days (`P ≤ 2^-34`)**, and `autoRebuyCarry` / `claimableStored` are themselves **uint128-capped and truncate** — so no reachable claim can carry an amount large enough.
- The existing fuzz negative-control `test_BTOMB03_CheckedAddCapIsLive` reaches the boundary **only via `vm.prank(GAME) vaultEscrow(~uint128.max)`**.
- **Disposition:** the checked `_toUint128` revert is correct defensive behavior; the boundary is unreachable under honest economics → **INFO** ("headroom not formally reserved" — optional, no fix). FLIP already documents ~340× headroom.

## Completeness critic — 5 additional modalities, all HOLD
GNRUS `burnAtGameOver` (the omitted third burn — pure zeroing, no revert); terminal-jackpot internal checked-math (`bucketShares` BPS sum = exactly 10000 constant-driven; decimator uint96 cast unreachable); `_unfreezePool` post-drain re-population (cosmetic, no external call); `_gameOverEntropy`'s `processCoinflipPayouts`/`resolveRedemptionPeriod` (GAME-only recording, covered by 418); unresolved gambling-burn redemption period (CP-06 resolves the sentinel day in both live + VRF-dead branches; INV-13 single-pool; post-gameover `claimRedemption` pays from sDGNRS's own balance, independent of the Game sweep). No new findings.

## Routed forward (425)
- INFO: tombstone headroom not formally reserved (optional defense-in-depth; documented).
- INFO: `claimTerminalDecimatorJackpot` has no `GO_SWEPT` guard (documented forfeiture, doesn't strand sinks).
- USER disposition: the degenerette/lootbox liveness-gameover forfeit (MEDIUM-by-design, ETH conserved).
