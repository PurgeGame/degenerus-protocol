# Level-Semantics Correctness Review — Degenerus Protocol (cross-model council, NET-1)

You are reviewing a Solidity codebase for **`level` vs `level + 1` correctness** — a focused, mechanical review of every site that computes or branches on the game `level`. Frozen subject: the `contracts/` tree at this checkout (read-only; do not modify any file).

## Background: the level/phase model

The game runs repeating **levels**. Each level has two phases, tracked by `jackpotPhaseFlag`:
- **PURCHASE phase** (`jackpotPhaseFlag == false`): players buy tickets into the *next* level being filled.
- **JACKPOT phase** (`jackpotPhaseFlag == true`): the *current* level is resolved.

The canonical helper is:
```solidity
function _activeTicketLevel() internal view returns (uint24) {
    return jackpotPhaseFlag ? level : level + 1;
}
```
So a **direct ticket purchase targets `level + 1` during purchase phase, `level` during jackpot phase.**

## The rules to verify each site against

1. **Purchase target:** direct/whale/afking ticket buys target `_activeTicketLevel()` (or its open-coded `jackpotPhaseFlag ? level : level + 1`). Every such site must use this, not a bare `level` or bare `level + 1`.
2. **Mint streak basis:** the mint-streak is RECORDED against `_activeTicketLevel()`; the activity-score reader compares against a `streakBaseLevel` argument. If the record level and the read level disagree by one, a streak is silently zeroed (`_mintStreakEffectiveFromPacked` resets when `currentMintLevel > lastCompleted + 1`).
3. **Jackpot:** resolves the current `level`; the next-level prize pool accrues to `level + 1`.
4. **Lootbox:** resolves at the OPEN level; the EV-cap key and resolver open level are `currentLevel + 1` during purchase. Far-future salvage distance `d = targetLevel - _activeTicketLevel()`.
5. **Affiliate leaderboard (per-level):** `payAffiliate(lvl)` is called with the buy's level; the afking affiliate `claim()` writes the leaderboard at `afkingDrain.level() + 1`; `affiliateBonusPointsBest(currLevel, …)` reads `currLevel - 1 .. currLevel - 5`. **Verify the level basis is consistent** between the producers (`payAffiliate`, `claim`) and the consumer (the bonus reader). A producer writing level N and a reader expecting N±1 is a real divergence.
6. **Boundaries:** level 0 (a `< level` compare is vacuously false at 0 — confirm a passless or zero-streak case cannot slip through), century `x00` levels, and the gameover/terminal level (the decimator's lagged-gameover offset keying).

## Your task

Across these files (the level-arithmetic hotspots):
- `contracts/modules/DegenerusGameMintModule.sol`, `DegenerusGameMintStreakUtils.sol`
- `contracts/modules/DegenerusGameLootboxModule.sol`
- `contracts/modules/DegenerusGameJackpotModule.sol`, `contracts/DegenerusJackpots.sol`
- `contracts/modules/DegenerusGameAdvanceModule.sol`
- `contracts/modules/GameAfkingModule.sol`
- `contracts/modules/DegenerusGameWhaleModule.sol`, `DegenerusGameDecimatorModule.sol`, `DegenerusGameDegeneretteModule.sol`
- `contracts/DegenerusAffiliate.sol`, `contracts/DegenerusQuests.sol`, `contracts/DegenerusGame.sol`, `contracts/storage/DegenerusGameStorage.sol`, `contracts/libraries/PriceLookupLib.sol`

For every `level` / `level + 1` / `_activeTicketLevel` / `streakBaseLevel` / `.level() + 1` / `jackpotPhaseFlag ? level : level + 1` site:
1. State the site's **role** and the **intended** level per the rules above.
2. Verify the **actual** level the code uses matches.
3. Report any **divergence** — a site where the level differs from what its role requires AND the difference is observable (wrong purchase target, a silently-zeroed streak a real player hits, a mis-keyed leaderboard / EV-cap that changes payouts, a boundary slip). For each, give `file:line`, expected-vs-actual, and the concrete observable effect.

Prioritise the **affiliate-score level asymmetry** (`payAffiliate` vs `claim()`'s `+1` vs the bonus reader) and the **streak record-vs-read basis** — these are the two most likely real divergences. Default to "correct" for a `level` vs `level + 1` pair that is the intended purchase-vs-jackpot distinction. Cite line numbers. A clean (no-divergence) result is a valid outcome if that is what the source shows.
