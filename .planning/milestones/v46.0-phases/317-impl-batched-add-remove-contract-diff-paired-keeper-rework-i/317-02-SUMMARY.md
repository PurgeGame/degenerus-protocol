---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 02
subsystem: infra
tags: [solidity, burnie, coinflip, keeper, afking-removal, access-control, all-or-nothing-burn]

# Dependency graph
requires:
  - phase: 317-01
    provides: confirmed pre-patch file:line ledger (RM-03 KEEP/DELETE value distinction, onlyFlipCreditors :194, onlyVault :485 / _burn :390 / vaultMintTo :518 analogs, ContractAddresses const block)
provides:
  - "ContractAddresses.AF_KING — pinned (deploy-script-patched address(0) placeholder) keeper identity constant (PROTO-05)"
  - "BurnieCoin.burnForKeeper(user, amount) returns (uint256 burned) — all-or-nothing keeper subscription charge gated onlyAfKing (PROTO-02)"
  - "BurnieCoin.onlyAfKing modifier + OnlyAfKing error + KeeperBurn event"
  - "BurnieCoinflip.onlyFlipCreditors extended with the AF_KING clause (PROTO-03, no new interface decl)"
  - "BURNIE flip recycle collapsed to flat RECYCLE_BONUS_BPS=75; afKing/deity tier removed (RM-03); win/loss RNG path byte-unmodified (RM-06)"
affects: [317-03, 317-04, 317-05, 317-keeper-rework-utilities, 318-tst, 320-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pinned-constant keeper gate (onlyAfKing) mirroring onlyVault — gates on ContractAddresses.AF_KING, never a settable flag"
    - "All-or-nothing burn: capacity decision (balanceOf + previewClaimCoinflips) precedes any state change; shortfall burns nothing and returns 0"

key-files:
  created: []
  modified:
    - contracts/ContractAddresses.sol
    - contracts/BurnieCoin.sol
    - contracts/BurnieCoinflip.sol
    - contracts/interfaces/IBurnieCoinflip.sol

key-decisions:
  - "AF_KING pinned as address(0) placeholder — the deploy pipeline patches it to the deploy-predicted keeper address (D-01b cross-repo reconciliation; ContractAddresses is deploy-script-patched per the file header)"
  - "burnForKeeper sources balance-first then pending coinflip via the existing _consumeCoinflipShortfall + _burn idiom (mirrors burnCoin); the all-or-nothing capacity guard uses balanceOf[user] + coinflip.previewClaimCoinflips(user) before any mutation"
  - "Added a KeeperBurn event in the house gameplay-signal style (the vaultMintTo gated-fn idiom emits at the end); the all-or-nothing return is the contract's authoritative signal the keeper consumes"
  - "Removed the now-unused `IDegenerusGame game` local from _depositCoinflip after collapsing the afKing branch (Rule 3 — avoids an unused-local compile warning); kept it in _claimCoinflipsInternal where the BAF section still uses it"

patterns-established:
  - "onlyAfKing: if (msg.sender != ContractAddresses.AF_KING) revert OnlyAfKing(); — single-line pinned-constant guard"
  - "All-or-nothing privileged burn: read spendable total → compare to amount → return 0 (no state change) on shortfall, else burn exactly amount"

requirements-completed: [PROTO-02, PROTO-03, PROTO-05, RM-03]

# Metrics
duration: ~10min
completed: 2026-05-23
---

# Phase 317 Plan 02: BURNIE-Side PROTO Additions + RM-03 Flat-75bps Recycle Collapse Summary

**Pinned the AF_KING keeper identity, added BurnieCoin.burnForKeeper all-or-nothing charge (onlyAfKing), authorized the keeper in BurnieCoinflip.onlyFlipCreditors, and collapsed the BURNIE flip recycle to flat RECYCLE_BONUS_BPS=75 with the win/loss RNG path left byte-unmodified — across the four BURNIE-side files, left UNCOMMITTED for the Wave-5 batched approval.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-23T18:02Z (approx)
- **Completed:** 2026-05-23T18:12:29Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- **PROTO-05:** `AF_KING` pinned in `ContractAddresses.sol` in the two-line `address internal constant … = address(0x…);` form (deploy-script-patched `address(0)` placeholder, aligned with the D-01b cross-repo deploy-predicted keeper address).
- **PROTO-03:** `BurnieCoinflip.onlyFlipCreditors` extended by ONE clause (`sender != ContractAddresses.AF_KING`); `@dev` allowed-callers list updated to describe what IS (GAME/QUESTS/AFFILIATE/ADMIN + AF_KING). No new interface decl — `creditFlip`/`creditFlipBatch` already exist; the keeper's gas-pegged bounty flows through the existing `creditFlip :898` zero-guarded impl.
- **PROTO-02:** `BurnieCoin.burnForKeeper(address user, uint256 amount) external onlyAfKing returns (uint256 burned)` — ALL-OR-NOTHING burn sourcing `balanceOf[user]` + pending coinflip (`previewClaimCoinflips`); on shortfall burns nothing and returns 0, otherwise burns exactly `amount` (balance-first via `_consumeCoinflipShortfall` then `_burn`) and returns `amount`. Added `onlyAfKing` modifier, `OnlyAfKing` error, and `KeeperBurn` event.
- **RM-03:** BURNIE flip recycle collapsed to flat 75bps — deleted `settleFlipModeChange` (+ its interface decl), the afKing/deity rebet branches, the `syncAfKingLazyPassFromCoin` sync, the deity-bonus block, the `deactivateAfKingFromCoin` cross-calls + `AFKING_KEEP_MIN_COIN` floor checks, the two helpers (`_afKingRecyclingBonus`, `_afKingDeityBonusHalfBpsWithLevel`), and all 5 deity/afKing consts. KEPT byte-identical: `RECYCLE_BONUS_BPS = 75`, `_recyclingBonus`, and the win/loss RNG path (`processCoinflipPayouts` / `bool win = (rngWord & 1) == 1;`).

## Task Commits

**NO per-task commits.** This plan touches `contracts/*.sol`; per the deferred-commit protocol and the repo's PreToolUse commit-guard hook, all commits are intentionally DEFERRED to the single batched USER-APPROVED contract diff at the Phase-317 Wave-5 approval gate. The working tree is left dirty:

1. **Task 1: PROTO-05 pin AF_KING + PROTO-03 authorize keeper** — UNCOMMITTED (`contracts/ContractAddresses.sol`, `contracts/BurnieCoinflip.sol`)
2. **Task 2: PROTO-02 burnForKeeper + onlyAfKing** — UNCOMMITTED (`contracts/BurnieCoin.sol`)
3. **Task 3: RM-03 collapse recycle to flat 75bps** — UNCOMMITTED (`contracts/BurnieCoinflip.sol`, `contracts/interfaces/IBurnieCoinflip.sol`)

## Files Created/Modified
- `contracts/ContractAddresses.sol` — added `AF_KING` pinned constant (deploy-script-patched placeholder).
- `contracts/BurnieCoin.sol` — added `burnForKeeper` (all-or-nothing keeper charge), `onlyAfKing` modifier, `OnlyAfKing` error, `KeeperBurn` event; updated the modifier-hierarchy comment table.
- `contracts/BurnieCoinflip.sol` — extended `onlyFlipCreditors` with the AF_KING clause; collapsed the recycle to flat 75bps and removed the afKing/deity tier (functions, branches, helpers, 5 consts).
- `contracts/interfaces/IBurnieCoinflip.sol` — removed the `settleFlipModeChange` decl; kept `creditFlip`/`creditFlipBatch`.

## Decisions Made
- **AF_KING placeholder = `address(0)`:** `ContractAddresses.sol` is the deploy-script-patched config file (header: "Compile-time constants populated by the deploy script") and is freely modifiable per `feedback_contractaddresses_policy`. The deploy pipeline patches `AF_KING` to the deploy-predicted keeper address; PROTO-05 + D-01b require it to equal the address the `degenerus-utilities` deploy produces/consumes for the keeper.
- **burnForKeeper source ordering:** balance-first then pending coinflip, reusing the exact `_consumeCoinflipShortfall(...)` + `_burn(...)` idiom `burnCoin` uses. The all-or-nothing capacity check (`balanceOf[user] + coinflip.previewClaimCoinflips(user) >= amount`) runs before any state change so a shortfall never partially burns. Both `_consumeCoinflipShortfall` paths revert atomically before any `_burn` (rngLock guard / final solvency check), so there is no path that burns a partial amount and returns — the all-or-nothing invariant (threat T-317-02-02) holds.
- **KeeperBurn event:** added to mirror the house gameplay-signal event style (the `vaultMintTo` gated-fn idiom emits at the end). The keeper's authoritative all-or-nothing signal is the `burned` return value, which the keeper consumes strictly (`AfKing.sol :1000` `if (burned != extractCost)`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed the now-unused `IDegenerusGame game` local in `_depositCoinflip`**
- **Found during:** Task 3 (RM-03 collapse)
- **Issue:** After collapsing the afKing rebet branch to a single `_recyclingBonus(rebetAmount)` call, the `IDegenerusGame game = degenerusGame;` local declared at the top of that block had no remaining reference — an unused local declaration (compile warning) and dead code.
- **Fix:** Deleted the now-orphaned `game` local from `_depositCoinflip` only. Left the distinct `game` local in `_claimCoinflipsInternal` intact (the surviving BAF section still calls `game.level()` / `game.purchaseInfo()` / `game.gameOver()`).
- **Files modified:** `contracts/BurnieCoinflip.sol`
- **Verification:** `forge build` produces no warning/error referencing any of the 4 owned files; the surviving `game`/`cachedLevel`/`levelCached` locals in `_claimCoinflipsInternal` are all still used.
- **Committed in:** UNCOMMITTED (folds into the Wave-5 batched contract commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — orphaned-local cleanup intrinsic to the RM-03 collapse). No scope creep — the change is confined to the function the plan directs collapsing.
**Impact on plan:** Minimal; keeps the BURNIE-side surgery warning-clean. The win/loss RNG path and the KEEP set were not touched.

## Issues Encountered

- **Cross-plan compile coupling (EXPECTED, not a defect):** A full `forge build` fails with ONE error — `Member "settleFlipModeChange" not found … in IBurnieCoinflip` at `DegenerusGame.sol:1603` and `:1678`. Those two call sites live inside the RM-01-deleted `_setAfKingMode` / `_deactivateAfKing` functions in `DegenerusGame.sol`, which is owned by sibling Wave-2 Plan 03 (RM-01) and removed in the SAME batched diff (317-LEDGER RM-01 table rows `:1603`/`:1678` marked REMOVE). This is exactly the LEDGER's "dependency-safe IFF PROTO-01/RM-01 ship in the same batched Phase-317 diff" note (LEDGER §Live Keeper Transitional-State Table, conclusion line 290). No compile diagnostic references any of the 4 plan-02-owned files; the batched diff compiles as a whole once Wave-2 Plans 03/04/05 land. Per the deferred-commit protocol, this plan did NOT touch `DegenerusGame.sol`.
- A pre-existing `_pickSoloQuadrant`/`effectiveEntropy` shadow warning in `DegenerusGameJackpotModule.sol` (lines 457-458) is unrelated to this plan and out of scope (not an owned file).

## Verification

- `git diff --stat -- contracts/` shows EXACTLY the four owned files (`ContractAddresses.sol`, `BurnieCoin.sol`, `BurnieCoinflip.sol`, `interfaces/IBurnieCoinflip.sol`) and nothing else — `+56 / -97`.
- **RM-06 hard floor — win/loss RNG path byte-unmodified:** no `+`/`-` diff line touches `processCoinflipPayouts`, `(rngWord & 1)`, the `_recyclingBonus` body, or `RECYCLE_BONUS_BPS = 75` (verified by grepping the diff for the KEEP-set core — zero matches). `RECYCLE_BONUS_BPS = 75` survives at `BurnieCoinflip.sol:129`.
- **SC#4 RM-03 grep set (non-comment):** `grep -v '^[[:space:]]*//' contracts/BurnieCoinflip.sol | grep -cE "settleFlipModeChange|_afKingRecyclingBonus|_afKingDeityBonusHalfBpsWithLevel|AFKING_RECYCLE_BONUS_BPS|AFKING_KEEP_MIN_COIN|deactivateAfKingFromCoin"` = **0**. The full afKing/deity symbol family (incl. `AFKING_DEITY_BONUS_*`, `DEITY_RECYCLE_CAP`, `afKingModeFor`, `syncAfKingLazyPassFromCoin`, `afKingActivatedLevelFor`, `hasDeityPass`, `deityBonus`) returns zero matches even including comments.
- **Value distinction respected:** kept `RECYCLE_BONUS_BPS = 75`; deleted `AFKING_RECYCLE_BONUS_BPS = 100` (and the other 4 consts). No wrong-value misdeletion.
- `IBurnieCoinflip.sol`: `settleFlipModeChange` decl count = 0; `function creditFlip` count = 2 (`creditFlip` + `creditFlipBatch` kept).
- Task grep verifies: `AF_KING` present in ContractAddresses and referenced in BurnieCoinflip; `burnForKeeper`/`onlyAfKing`/`OnlyAfKing` present in BurnieCoin.
- **NO git commit made; STATE.md / ROADMAP.md untouched; `contracts/` left dirty** (deferred to Wave-5 batched approval).

## Threat-Model Confirmation
- **T-317-02-01 (Spoofing):** `burnForKeeper` gated `onlyAfKing` (pinned `ContractAddresses.AF_KING`); `onlyFlipCreditors` gains the same pinned-constant clause — never a settable flag. Mitigated.
- **T-317-02-02 (Partial-burn shortfall):** all-or-nothing capacity check precedes any `_burn`; shortfall returns 0 with zero state change; both consume paths revert atomically before any burn. Mitigated.
- **T-317-02-03 (RNG payout drift):** `processCoinflipPayouts` / `(rngWord & 1)` byte-unmodified (RM-06); grep gate confirms the KEEP set survives. Deep adversarial review of the `burnForKeeper` authority routed to 318 TST / 320 AUDIT (contract-auditor). Mitigated.
- **T-317-02-SC:** no package installs (Solidity edits only). Accepted.

## Known Stubs
- `ContractAddresses.AF_KING = address(0)` is a deploy-time placeholder by design (this is the deploy-script-patched config file). It is patched to the deploy-predicted keeper address by the deploy pipeline (PROTO-05 / D-01b). NOT a code stub — it is the intended pre-deploy state of every address in this file (matching `DEPLOY_DAY_BOUNDARY = 0` and the other deploy-patched literals). Resolution: the `degenerus-utilities` deploy + `PatchAddressesForFork.sh` alignment (paired keeper-rework track).

## Next Phase Readiness
- BURNIE-side keeper authority surface is in place: the keeper has its all-or-nothing charge (`burnForKeeper`), its bounty path (`creditFlip` via the extended gate), and the pinned `AF_KING` identity every gate resolves to.
- **Blocker for full compile:** the batched diff only compiles once sibling Wave-2 plans land their RM-01/RM-05 removals (the `DegenerusGame.sol` `settleFlipModeChange` callers + the keeper interface succession). This is the intended batched-diff coupling; not a blocker for this plan's deliverable.
- The `burnForKeeper` authority + the RM-03 collapse + the win/loss-RNG byte-equivalence are the surfaces 318 TST and the 320 AUDIT contract-auditor pass will exercise.

---
*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Plan: 02*
*Completed: 2026-05-23*
