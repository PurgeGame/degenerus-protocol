# Adversarial Terminal-Branch (GAMEOVER) Review — Degenerus Protocol spinal column (v67.0 phase 422 GAMEOVER)

You are an independent senior smart-contract auditor reviewing **terminal-branch (gameover) liveness** on a real-money on-chain ETH game. Read-only. Subject = the **frozen `contracts/` working tree at commit `0bb7deca` / tree `4a67209a`** (clean — read files under `contracts/` directly; cite `file:line`). Assume **honest admin/governance** (key-compromise out of scope). The general permanent-brick / liveness proof was done in phase 418 (BRICK); THIS phase drills the SPECIFIC terminal entrypoints — proving every GAMEOVER branch finalizes for any reachable pre-gameover state.

## The structure under test

When the game ends, `advanceGame` (`DegenerusGameAdvanceModule.sol`) enters `_handleGameOverPath` (~:605/662) which delegatecalls the GameOver module (`DegenerusGameGameOverModule.sol`): `handleGameOverDrain` (~:73) and `handleFinalSweep` (~:203). Terminal payouts: `runTerminalJackpot` + `runTerminalDecimatorJackpot` (level keyed at `lvl+1` per the DEC-ALIAS fix). Final sweep sends stETH-first/ETH to the three sinks VAULT / SDGNRS / GNRUS and zeroes `claimablePool`. `gameOverStatePacked` (slot 20): `GO_TIME | GO_JACKPOT_PAID | GO_SWEPT`. `gameOver` bool (slot 0) is GameOver-module-only.

## CLAIMS (find any reachable counterexample)

### GAMEOVER-01 — Terminal decimator resolves without aliasing a live round / no stranded payout
`runTerminalDecimatorJackpot` (~Decimator:1024, keyed `decBucketOffsetPacked[lvl+1]`) resolves without aliasing a live regular round (the `lvl+1` isolation) and without a reachable revert that strands the terminal payout. Verify: no reachable revert in the terminal-decimator path on the finalization leg; the terminal claim path reads the same `lvl+1` slot; the lazy-afking-merge / post-gameover claim depends on the final sweep zeroing `claimablePool` with no underflow — verify that subtraction is safe.

### GAMEOVER-02 — Terminal jackpot + handleGameOverDrain finalize within the gas ceiling for ANY reachable state
`runTerminalJackpot` and `handleGameOverDrain` (~:73) finalize for any reachable pre-gameover state — any pending pool, any winner-set size, any number of deity-pass owners (the `:106` deity-refund loop). Derive the WORST-CASE gas composition (largest winner set, max deity owners, full pending pools) and show it holds under the 16.7M (EIP-7825 16,777,216) per-tx cap. Verify the post-gameover claim path that ALSO pays prepaid afking ETH finalizes. Note `gameOver=true` is latched at `:135` BEFORE the external burns (`:139-142`), nested terminal jackpot/decimator (`:177/:191`), and the RNG-word gate (`:94`) — confirm any revert there rolls back the whole finalization including the latch (all-or-nothing), so a failed attempt is cleanly retryable, not a permanent wedge.

### GAMEOVER-03 — The gameOver-trigger transition cannot wedge a downstream terminal entrypoint
The conditions that set `gameOver` (`lastPurchaseDay` etc.) leave every downstream terminal entrypoint callable; no mid-gameover partial state blocks finalization. Verify the liveness-bailout interaction: `_livenessTriggered()` fires after 14d with `rngRequestTime!=0` but is GATED OFF while `lastPurchaseDay || jackpotPhaseFlag` (the Storage:1437-1446 deadlock-window) — confirm `_handleGameOverPath` is reachable for every terminal state (not permanently gated off in a window where gameover is the only way forward), AND that the final-sweep hard-revert path (a sink rejecting stETH/ETH at `_sendStethFirst` ~:253/:257/:261) cannot permanently wedge the sweep (GO_SWEPT written before transfers but rolls back on revert → retries cleanly; confirm the three sinks always accept). Also verify the gameOver callee invariants: sDGNRS `burnAtGameOver` (~:614) and FLIP `tombstoneAtGameOver` (~:563) checked over/underflow cannot revert the finalization.

## Priority hotspots
- The `:106` deity-refund loop bound (`deityPassOwners.length` ≤ ~32 symbols?) vs the gas ceiling.
- Post-liveness `_queueTickets` / `resolveBets` revert permanently — does the gameOver drain actually settle every pending degenerette bet + lootbox/redemption claim into claimable (no stranded funds)?
- `handleFinalSweep` zeroing `claimablePool` while the three sinks are debited — underflow / ordering / a sink that reverts.
- The unbounded-ish terminal jackpot winner set + terminal decimator bucket iteration — worst-case gas.

## Output
For EACH of GAMEOVER-01..03 and each hotspot: verdict (**REAL / REFUTED / UNCERTAIN**), severity (**CATASTROPHE** for a terminal wedge that strands all funds or blocks finalization; else HIGH/MED/LOW/INFO), `reachable` under honest governance, the concrete trigger if REAL, and reasoning with `file:line`. For any gas claim, derive the worst-case composition first. Default to REFUTED only when the path provably finalizes across the whole reachable pre-gameover state space. Report any **newVectors**. Be concrete and skeptical.
