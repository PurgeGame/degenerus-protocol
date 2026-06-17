# Adversarial Liveness Review — Degenerus Protocol spinal column (v67.0 phase 418 BRICK)

You are an independent senior smart-contract auditor doing a **liveness / permanent-halt** review of a real-money on-chain ETH game. Read-only; the subject is the FROZEN `contracts/` tree at git `0dd445a6` in this repo. Cite `file:line` for every claim. Assume **honest admin / governance** (a legitimate config change is allowed, but admin key-compromise is OUT of scope).

## The invariant under test (try to break it)

The game's "spinal column" is the `mintFlip()` / `purchase` mint chain and the `advanceGame()` core state machine in `contracts/DegenerusGame.sol`, which dispatches via **delegatecall** to 13 modules in `contracts/modules/*` (each runs in the Game's storage), and synchronously calls `FLIP`, `Coinflip`, `DegenerusVault`, `sDGNRS`, `DegenerusAffiliate`.

**CLAIM (find any reachable counterexample):** No reachable transaction can
1. **Permanently brick** the state machine — drive it into a state where *every* future `advanceGame()` reverts (a day/level/phase that can never advance), `gameOver` can never finalize (terminal decimator / terminal jackpot / `handleGameOverDrain` always reverts), or the daily VRF word can never be obtained; OR
2. **Cross the ~16.7M block-gas ceiling** anywhere in the advance/finalization chain (a tx that always exceeds the ceiling = unminable = permanent brick = game over).

A *transient* revert that another actor or a later call can clear is NOT a brick. A *permanent* wedge — no actor, no sequence, ever recovers it — is a CATASTROPHE.

## The map (read it)

The full current-HEAD column map is in this repo:
- `.planning/phases/417-colmap-re-derive-call-graph/417-COLMAP.md` (authoritative: call graph, 393 revert sites tagged transient/permanent, 81 loops [17 unbounded], delegatecall-write→slot table)
- Per-slice detail: `.planning/phases/417-colmap-re-derive-call-graph/417-colmap-*.md`
- Game storage layout: `.planning/phases/417-colmap-re-derive-call-graph/417-game-storage-layout.json`

## Priority leads to adjudicate (REAL or REFUTED, with reachability + trigger)

**L1 — sDGNRS `resolveRedemptionPeriod` uint96 underflow (TOP CANDIDATE).** In `contracts/sDGNRS.sol` (~:756, called from `advanceGame` every advance with a stamped pool), a `uint96` subtraction. Does the telescoping-delta submit math (`Coinflip`/redemption ~:1108) + gwei-snap + the single-pool (INV-13) guarantee the cumulative scalar can NEVER drift below the day's reconstructed `segregatedMax`? If it can underflow/revert, `advanceGame` wedges forever on that stamped day = CATASTROPHE. Construct the exact deposit/redeem/advance sequence or prove it impossible.

**L2 — Unbounded loops vs the 16.7M ceiling (BRICK-04).** Derive the WORST CASE first, then check it: `_backfillOrphanedLootboxIndices:1894` co-running with up to 120 `_backfillGapDays` in one `advanceGame` tx; `runBafJackpot` winner loop (cross-contract cap in `DegenerusJackpots`); `resolveRedemptionLootbox:951` (claimed no budget cap); `handleGameOverDrain:106` deity-refund loop. For each: is the iteration count hard-bounded, and is the worst-case composition provably < 16.7M? The known prior worst case (v62-02) was subscriber-evict + gap-backfill ≈ 20.25M before a fix — re-verify the fix holds for the column at HEAD.

**L3 — gameOver finalization all-or-nothing.** `handleGameOverDrain` latches `gameOver=true` (~:135) BEFORE burning (GNRUS/sDGNRS/FLIP ~:139-142) and the nested terminal jackpot/decimator (~:177/:191). Can any sink reject (stETH/ETH transfer to VAULT/SDGNRS/GNRUS at `_sendStethFirst:253/257/261`), any callee revert (`sDGNRS.burnAtGameOver:614`, `FLIP.tombstoneAtGameOver:563`), or any arithmetic fault permanently block finalization — or does every revert cleanly roll back the latch for a retry?

**L4 — Liveness-bailout deadlock window.** `_livenessTriggered` (the stall recovery, fires after the timeout with `rngRequestTime!=0`) is GATED OFF while `lastPurchaseDay || jackpotPhaseFlag` (Storage ~:1437-1446). Is there a reachable (lastPurchaseDay/jackpotPhaseFlag, VRF-stalled) combination where the stall recovery is disabled AND normal advance can't proceed = permanent deadlock?

**L5 — Post-liveness stranded reverts.** `_queueTicketsScaled:650` / degenerette `resolveBets:435` revert permanently post-liveness. Does the gameOver drain settle every pending degenerette bet + lootbox/redemption claim into `claimable`, or can value/state strand such that finalization can't complete?

**L6 — RNG word never obtainable.** Across the daily request → `rawFulfillRandomWords` → seal path and the retry/rotation paths: is there any reachable state where the day's word can be requested but never fulfilled/sealed AND no recovery (retry/rotation) is reachable? (`advanceGame:283` RngNotReady pre-RNG gate — is the documented 12h/14d recovery always reachable?)

Also surface **any NEW permanent-brick or gas-ceiling vector** not in L1-L6 (sweep the 58 permanent-revert candidates + 17 unbounded loops in the map).

## Output

For each lead L1-L6 and each new vector: verdict (REAL / REFUTED / UNCERTAIN), severity (CATASTROPHE for a permanent brick, HIGH for a conditional/expensive one, else MED/LOW/INFO), whether it is reachable under honest governance, the exact trigger sequence (a PoC sketch) if REAL, and the reasoning with `file:line`. Default to REFUTED only when you can show why no sequence reaches it. Be concrete and skeptical.
