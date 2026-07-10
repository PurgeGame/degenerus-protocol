# ✅ CLOSED 2026-07-09 — all 4 fixes verified SHIPPED in frozen tree d5e9f58a (grep-verified: 90-145%/9000-14500 present, zero stale 80-135/8000-13500/presale-lootbox strings). Original note below.
# Pending comment-only .sol fixes — APPLY AFTER v75 mutation campaign completes

Blocked while the campaign runs: it mutates `contracts/` in place, its EXIT trap runs
`git checkout -- contracts/` (would discard these edits), and the runner FATALs on
subject-tree drift. Apply with the Edit tool once `audit/mutation/PROGRESS-v75.log`
shows the final DONE (or the campaign is otherwise confirmed stopped).

Three stale EV-multiplier range comments (constants are LOOTBOX_EV_MIN_BPS=9000 →
LOOTBOX_EV_MAX_BPS=14500, i.e. 90–145%; comments predate the recalibration).
Comment-only — no build needed (natspec/comment-only .sol edits skip full build).

## 1. contracts/modules/DegenerusGameDegeneretteModule.sol:1002
old:
    ///      Applies activity-score EV multiplier (80-135%) to match regular lootbox opens.
new:
    ///      Applies activity-score EV multiplier (90-145%) to match regular lootbox opens.

## 2. contracts/modules/DegenerusGameLootboxModule.sol:480
old:
    /// @param evMultiplierBps EV multiplier in basis points (8000-13500)
new:
    /// @param evMultiplierBps EV multiplier in basis points (9000-14500)

## 3. contracts/modules/DegenerusGameLootboxModule.sol:571
old:
        // Apply the activity score EV multiplier to the reward amount (80% to 135%).
new:
        // Apply the activity score EV multiplier to the reward amount (90% to 145%).

## 4. contracts/DegenerusGame.sol:816 (whale-pass doc)
old:
    ///      Includes lootbox (20% of price during presale, 10% after).
new:
    ///      Includes lootbox (10% of price).
Verified: WHALE_LOOTBOX_BPS / LAZY_PASS_LOOTBOX_BPS / DEITY_LOOTBOX_BPS are all flat
1000 with no presale branch (WhaleModule:385/530/692; no PS_ACTIVE read in the module).

Grep-verified 2026-07-03 that items 1-3 are the only EV-multiplier occurrences
(`grep -rn "80-135\|8000-13500\|80% to 135" contracts/`). Commit only after USER
diff review per the contract-commit gate.
