# 322-03 SUMMARY — LOOT (BURNIE-lootbox removal + boon/pass unification)

**Plan:** `322-03-PLAN.md` (Phase 322 IMPL, executor #3 of 7). **Requirements:** LOOT-01..06.
**Status:** FULLY APPLIED. Contract edits only — NOT committed (single batched diff, user reviews at wave 8).
**Date:** 2026-05-25.

---

## What was applied

### LOOT-01 — BURNIE-lootbox surface removed entirely (terminal-paradox closed)
Removed symbols (each one), grep-verified zero non-test selector/decl references remain:

| Symbol | File | Action |
|---|---|---|
| `openBurnieLootBox` (fn) | LootboxModule | DELETED (whole fn + NatSpec) |
| `event BurnieLootOpen` (decl + emit) | LootboxModule | DELETED |
| BURNIE→ETH conversion `amountEth = burnieAmount*priceWei*80/(PRICE_COIN_UNIT*100)` | LootboxModule | DELETED (was inside `openBurnieLootBox`) |
| `purchaseBurnieLootbox` (external fn) | MintModule | DELETED |
| `_purchaseBurnieLootboxFor` (private fn) | MintModule | DELETED |
| `purchaseCoin` `lootBoxBurnieAmount` param + `if (lootBoxBurnieAmount != 0)` branch | MintModule (`purchaseCoin`/`_purchaseCoinFor`) | param dropped, branch removed → tickets-only |
| `event BurnieLootBuy` (decl) | MintModule | DELETED (orphaned by `_purchaseBurnieLootboxFor` removal) |
| `BURNIE_LOOTBOX_MIN` const (decl) | MintModule | DELETED (orphaned) |
| `purchaseBurnieLootbox` (wrapper) | DegenerusGame.sol | DELETED |
| `openBurnieLootBox` + `_openBurnieLootBoxFor` (wrapper + private) | DegenerusGame.sol | DELETED |
| `purchaseCoin` `lootBoxBurnieAmount` param (wrapper) | DegenerusGame.sol | DROPPED → tickets-only delegatecall |
| `purchaseBurnieLootbox` (interface decl) | DegenerusVault.sol | DELETED |
| `gamePurchaseBurnieLootbox` (vault fn) | DegenerusVault.sol | DELETED |
| `purchaseCoin` interface `lootBoxBurnieAmount` param | DegenerusVault.sol | DROPPED |
| `purchaseCoin` `lootBoxBurnieAmount` + `purchaseBurnieLootbox` decls | IDegenerusGameModules.sol | DROPPED / DELETED |
| `openBurnieLootBox` decl | IDegenerusGameModules.sol (IDegenerusGameLootboxModule) | DELETED |
| `purchaseCoin` `lootBoxBurnieAmount` param | IDegenerusGame.sol | DROPPED |

**Orphaned storage (left in place, not deleted):** `mapping lootboxBurnie` (Storage:1402) is now write-only-dead (its only writer `_purchaseBurnieLootboxFor` was deleted, its only reader `openBurnieLootBox` was deleted). Left as-is — out of this plan's `files_modified` scope (Storage) and harmless; flag for a downstream storage-prune if desired. Shared `_lr*` reserve machinery (`LR_PENDING_BURNIE`/`LR_PENDING_ETH`, `_packBurnieToWhole`, `_packEthToMilliEth`) is STILL used by ETH-lootbox + Degenerette paths → KEPT.

### LOOT-02 — BURNIE→tickets KEPT
- `purchaseCoin(address buyer, uint256 ticketQuantity)` is tickets-only across MintModule + Game wrapper + Vault interface + both interface files, lock-step arity.
- ENF-01 guard `if (gameOverPossible) revert GameOverPossible();` PRESERVED on the tickets path.
- `gamePurchaseTicketsBurnie` KEPT; now calls `gamePlayer.purchaseCoin(address(this), ticketQuantity)` (trailing `0` dropped).

### LOOT-04 + LOOT-05 + R2 — `_resolveLootboxCommon` 5→2 bools (haircut fixed)
**Final signature** (the 2 surviving bools, KEEP per C1):
```solidity
function _resolveLootboxCommon(
    address player,
    uint32 day,
    uint48 index,
    uint256 amount,
    uint24 targetLevel,
    uint24 currentLevel,
    uint256 seed,
    bool emitLootboxEvent,
    bool payColdBustConsolation,
    uint256 distressEth,
    uint256 totalPackedEth
) private returns (uint32 futureTickets, uint256 burnieAmount, bool roundedUp)
```
Removed: `presale` (pos 8 — already had no body reader after 322-02 deleted the +62% block; `applyPresaleMultiplier` is an independent roll-outcome label inside `_resolveLootboxRoll`, not this param), `allowPasses` (pos 9), `allowBoons` (pos 12).

Body changes:
- Deleted the `if (allowBoons)` gate → `_rollLootboxBoons` + the activity-boon consume delegatecall ALWAYS run.
- Deleted the `allowPasses` gates threaded into `_rollLootboxBoons`/`_boonPoolStats`/`_boonFromRoll` (removed the param from all three private helpers). Pass-type boons now gated ONLY by real game-state: `lazyPassValue != 0` (lazy-pass weights) and `deityEligible` (deity weights). Whale-pass jackpot weight now always included.
- **Haircut FIXED (LOOT-04):** `mainAmount = amount - _lootboxBoonBudget(amount)` was always carved (unconditionally, outside the old gate), but on the two formerly-`allowBoons=false` paths the boon roll never ran → the carved ~10% silently vanished. Now the same `_lootboxBoonBudget(amount)` is always passed into `_rollLootboxBoons`, so the carved budget is actually spent on a boon draw. Confirmed: budget consumed, no silent drop.

### LOOT-03 + LOOT-06 — 3 surviving ETH callers unified to the 2-bool tail
- `openLootBox` → `(emit=true, coldBust=true)` (also dropped its now-dead `bool presale` local + the `_psRead(...)` that fed it).
- `resolveLootboxDirect` → `(emit=false, coldBust=false)` — shared by Degenerette (`_resolveLootboxDirect` wrapper :783) AND Decimator (:601). Both now roll full boons+passes (D1 uniform). External signature `(player, amount, rngWord, activityScore)` UNCHANGED → Decimator/Degenerette delegatecall args still line up (the bool reduction is internal to the private `_resolveLootboxCommon`).
- `resolveRedemptionLootbox` (LootboxModule:881) → `(emit=false, coldBust=false)`. Left NON-payable here; the always-roll satisfies R1's boon-flag behavior with no call-site flag.

NatSpec/comments updated to describe current behavior (no history); stale `openBurnieLootBox` mentions in `_resolveLootboxCommon` doc + cold-bust comments removed.

---

## Game-side note for 322-04 (REDEEM, R1)
`resolveRedemptionLootbox` on the **Game side** (`DegenerusGame.sol`, the payable wrapper) — its `payable` modifier + the unchecked `claimableWinnings[SDGNRS] -= amount` debit removal + `futurePrizePool`-from-`msg.value` credit are OWNED BY 322-04 (REDEEM-03, R1). I did NOT make it payable. The LootboxModule-side common resolver it delegates into now always rolls boons (R2 always-roll), so 322-04 needs NO call-site `allowBoons` flag.

---

## forge build error set (classified)

`forge build` → **3 errors total**, all the documented pre-existing 322-06-owned dangling refs:

**(a) Known 3 WhaleModule errors (NOT mine — 322-06 resolves):**
- `Error (7576) Undeclared identifier` `_awardEarlybirdDgnrs` at `DegenerusGameWhaleModule.sol:263`, `:476`, `:587` (body deleted by 322-02 / R6; call sites land on 322-06).

**(b) New expected cross-file refs for later executors:** NONE. My BURNIE-box removal + bool reduction introduced zero new dangling references (interface decls updated in lock-step; no downstream caller of a removed selector survives).

**(c) Unexpected:** NONE. None of my 6 touched files (LootboxModule, MintModule, DegenerusGame, DegenerusVault, IDegenerusGameModules, IDegenerusGame) appear in any error or warning.

Pre-existing non-error noise (not mine, not introduced here): 2 `Warning (2519)` shadow declarations in `DegenerusGameJackpotModule.sol:432/433` (untouched file).

---

## Deviations / notes
- `contracts/test/LootboxBernoulliTester.sol:76` has a stale *comment* mentioning `openBurnieLootBox` (and other `_resolveLootboxCommon` doc references). It is a standalone Bernoulli reimplementation tester with NO live call to any removed selector → does not break the build. Left untouched (test file, outside this plan's `files_modified`; flag for an optional doc-comment cleanup in the TST phase).
- `lootboxBurnie` storage mapping is now orphaned (see LOOT-01 table) — intentionally left in place; not in this plan's storage scope.

## Verification
- `_resolveLootboxCommon` has exactly 2 bool params (`emitLootboxEvent` + `payColdBustConsolation`); 0 remaining `presale`/`allowPasses`/`allowBoons` bool decls.
- Zero non-test `openBurnieLootBox` / `BurnieLootOpen` / `purchaseBurnieLootbox` / `_purchaseBurnieLootboxFor` / `gamePurchaseBurnieLootbox` / `BurnieLootBuy` references in `contracts/`.
- BURNIE→tickets + `gamePurchaseTicketsBurnie` preserved; ENF-01 guard preserved.
- `forge build` error set = exactly the known 3 WhaleModule `_awardEarlybirdDgnrs` (322-06).
- No git operation performed.
