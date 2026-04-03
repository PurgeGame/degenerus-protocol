# Phase 175 Comment Audit — Plan 04 Findings
**Contracts:** DegenerusGameBoonModule, DegenerusGameDegeneretteModule, DegenerusGameDecimatorModule
**Requirement:** CMT-01
**Date:** 2026-04-03
**Total findings this plan:** 4 LOW, 5 INFO

---

## DegenerusGameBoonModule

### Finding B-01 — LOW — line 12
**Comment says:** `@notice Delegatecall module for boon consumption and lootbox view functions.`
**Code does:** The contract contains only boon consumption functions (`consumeCoinflipBoon`, `consumePurchaseBoost`, `consumeDecimatorBoost`, `checkAndClearExpiredBoon`, `consumeActivityBoon`). There are no lootbox view functions anywhere in the 329-line contract. The "lootbox view functions" claim in the @notice is incorrect.
**Fix:** Change to `@notice Delegatecall module for boon consumption.`

### Finding B-02 — INFO — line 14
**Comment says:** `@dev Split from DegenerusGameLootboxModule to stay under EIP-170 size limit.`
**Code does:** The comment describes historical origin (how the file came to exist), not what the module currently is. Per coding conventions, comments must describe what IS, not what changed.
**Fix:** Replace with a present-tense description such as `@dev Companion module to DegenerusGameLootboxModule; kept separate to stay under EIP-170 size limit.`

### Finding B-03 — INFO — lines 221, 296
**Comment says:** (implicitly, via constant name) Activity boon expiry is governed by `COINFLIP_BOON_EXPIRY_DAYS`.
**Code does:** At line 221 in `checkAndClearExpiredBoon` and line 296 in `consumeActivityBoon`, the Activity boon time-expiry check uses `COINFLIP_BOON_EXPIRY_DAYS` (defined as 2 days). There is no `ACTIVITY_BOON_EXPIRY_DAYS` constant. Using a constant named for a different boon type makes the intent ambiguous — a reader cannot tell whether the shared value is intentional or an accidental reuse.
**Fix:** Introduce `uint24 private constant ACTIVITY_BOON_EXPIRY_DAYS = 2;` and replace both occurrences, or add a comment at each use site: `// activity boon expires after same window as coinflip boon`.

---

## DegenerusGameDegeneretteModule

### Finding D-01 — LOW — lines 364–365
**Comment says:**
```
/// @notice Places Full Ticket bets using pending affiliate Degenerette credit.
/// @notice Resolves one or more pending bets for a player.
```
(Two `@notice` tags on `resolveBets`; the first belongs to a different function.)
**Code does:** `resolveBets` loops over an array of bet IDs and calls `_resolveBet` for each. It has nothing to do with placing bets or affiliate credit. The first `@notice` is a paste artifact from a different function and completely misrepresents this function's purpose.
**Fix:** Remove the first `@notice` line entirely. The second `@notice` accurately describes `resolveBets`.

### Finding D-02 — INFO — lines 257–263
**Comment says:**
```
// Factors below are derived from uniform-ticket probabilities (all weights=10)
// and the new payout table (0, 0, 1.78x, 4.75x, 15x, 54x, 248x, 1280x, 100000x).
```
**Code does:** The `QUICK_PLAY_BASE_PAYOUTS_PACKED` constant at lines 240–248 encodes 2-match = 190 centi-x (1.90x), not 1.78x. The comment references a "new payout table" with 1.78x for 2 matches, but this table does not appear in the contract. The WWXRP bonus factors were derived against a payout table that differs from the one currently in the code.
**Fix:** Update the comment payout table to match the actual `QUICK_PLAY_BASE_PAYOUTS_PACKED` values, or verify whether the factors are still correct and update accordingly.

### Finding D-03 — INFO — line 956
**Comment says:** `// basePayout is in "centi-x" (178 = 1.78x), roiBps is in bps (9000 = 90%)`
**Code does:** The base payout for 2 matches is 190 (1.90x), not 178 (1.78x). The example value "178 = 1.78x" is stale — it corresponds to the removed WWXRP payout table, not the current `QUICK_PLAY_BASE_PAYOUTS_PACKED` values.
**Fix:** Change the example to a correct current value, e.g., `(190 = 1.90x for 2 matches)`.

### Finding D-04 — INFO — line 592–593
**Comment says:**
```
// For backwards compatibility, spin 0 uses the legacy seed (no spinIdx mixed in).
```
**Code does:** The comment correctly describes the behavior — spin 0 is seeded without `spinIdx` while spins 1+ include `spinIdx`. However, the phrase "For backwards compatibility" describes the historical reason (legacy migration), not what the code is doing or why the difference is intentional in the current design. Readers who don't know the history see a forward reference to undefined legacy behavior.
**Fix:** Reword to describe current intent: `// Spin 0 seed uses only rngWord and index; spins 1+ additionally mix in spinIdx for independence.`

---

## DegenerusGameDecimatorModule

### Finding C-01 — LOW — lines 119–120
**Comment says:** (in `recordDecBurn` NatSpec)
`On improvement, previous burn is removed from old aggregate, player burn resets, and entry migrates.`
**Code does:** When a better bucket is selected (lines 148–154), the code:
1. Calls `_decRemoveSubbucket` to subtract `prevBurn` from the old subbucket aggregate.
2. Assigns the new bucket and deterministic subbucket.
3. Calls `_decUpdateSubbucket` with `prevBurn` to seed the new subbucket with the carried-over burn.
The player's accumulated burn (`e.burn = prevBurn`) is **not reset**; it is carried over to the new subbucket. "Player burn resets" is wrong — the total burn carries over intact. Only the aggregate slot it contributes to changes.
**Fix:** Change to: `On improvement, previous burn is migrated to the new subbucket aggregate, and the player's entry moves to the better denominator.`

### Finding C-02 — LOW — lines 655–658
**Comment says:**
```
|  Always-open burn for GAMEOVER. Time multiplier rewards early        |
|  conviction. 200k cap equalizes bankroll — timing differentiates.   |
```
**Code does:** `recordTerminalDecBurn` at line 715 blocks burns when `daysRemaining <= 7` with `revert TerminalDecDeadlinePassed()`. The terminal decimator is therefore NOT always open — it closes 7 days before the death clock expires.
**Fix:** Change "Always-open burn" to "Burn open until 7 days before the death clock expires."

### Finding C-03 — INFO — lines 899–906
**Comment says:**
```
/// @dev Time multiplier based on days remaining on death clock.
///      > 10 days: linear 20x (day 120) to 1x (day 10)
///      7-10 days: flat 1x
///      <= 7 days: blocked by caller
```
**Code does:** The function returns `10000` (flat 1x) for all `daysRemaining <= 10`, including day 10 itself. The boundary condition is subtle: at exactly 10 days remaining, the code returns 1x (matching `<= 10`), not the linear formula. "7-10 days: flat 1x" implicitly excludes 10 from the "> 10 days" linear range, which is correct, but the wording "7-10 days" could be read as covering only 7, 8, 9, and 10 exclusively. The block condition "blocked by caller" at `<= 7` means 8, 9, 10 all get the 1x multiplier from this function — wording is precise enough but slightly ambiguous about day 10.
**Assessment:** The comment is broadly correct. Noting as INFO for the slightly ambiguous boundary description at day 10.
