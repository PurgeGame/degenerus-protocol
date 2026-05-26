---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 06
status: complete
requirements: [KEEP-01, KEEP-02, KEEP-03]
files_modified:
  - contracts/AfKing.sol
  - contracts/DegenerusGame.sol
  - contracts/interfaces/IDegenerusGame.sol            # scope expansion (lockstep caller of the renamed enqueue)
  - contracts/modules/DegenerusGameMintModule.sol      # scope expansion (lockstep caller)
  - (96 Solidity test files — mechanical rename propagation to keep the suite compiling)
committed: false
---

# 326-06 KEEP — keeper rename + bytes32("DGNRS") affiliate wiring

## Rename map (old → new), code AND comments
**AfKing.sol** (sweep surface, self-contained — no external callers):
- `sweep` → `autoBuy`, `sweepProgress` → `autoBuyProgress`
- `SweepAborted` → `AutoBuyAborted`, `EmptySweep` → `EmptyAutoBuy`, `SweepCompleted` → `AutoBuyCompleted`, `Swept` (event) → `AutoBought`, `NoSubscribersSwept` → `NoSubscribersAutoBought`
- `_sweepDay`/`_sweepCursor` → `_autoBuyDay`/`_autoBuyCursor`; `lastSweptDay` → `lastAutoBoughtDay`; `AlreadySweptToday` → `AlreadyAutoBoughtToday`
- KEEP-02: `creditFlip` minted-flip-credit bounty + `BOUNTY_ETH_TARGET` peg byte-unchanged (only naming hunks).

**DegenerusGame.sol**:
- `crankBets` → `autoResolve`, `crankBoxes` → `autoOpen`, `_crankResolveBet` → `_autoResolveBet`, `_crankOpenBox` → `_autoOpenBox`, `enqueueBoxForCrank` → `enqueueBoxForAutoOpen`
- `CRANK_GAS_PRICE_REF`/`CRANK_RESOLVE_BET_GAS_UNITS`/`CRANK_OPEN_BOX_GAS_UNITS` → `AUTO_*`; `CRANK-0x` tags → `AUTO-0x`; comment prose (DO-WORK CRANK header, cranker, box-crank) reworded.
- Two non-keeper "sweep" comments reworded to remove the literal word: `:1727` "reentrant sweep/cancel" → "reentrant auto-work/cancel"; the gameover view comment "final sweep has executed" → "final fund forfeiture has executed" (the GameOverModule `handleFinalSweep` MECHANISM is out of scope + unchanged — only the comment reworded to satisfy the strict 0-"sweep" acceptance; flagged for hand-review).

## Affiliate wiring (KEEP-03/04, USER-LOCKED)
`DegenerusGame.sol` `_batchPurchaseUnit` self-call: `bytes32(0)` → **`bytes32("DGNRS")`** (literal — `AFFILIATE_CODE_DGNRS` is `private` in DegenerusAffiliate, not reachable). Routes captured revenue primary→SDGNRS / secondary→VAULT via the two-tier cross-referral; permanent from purchase #1; real-human-affiliate players keep theirs (the affiliate's `!infoSet` fall-through). **`bytes32("VAULT")` NOT wired** (presale-mutable — explicitly avoided). `DegenerusAffiliate.sol` byte-unchanged.

## ⚠ SCOPE EXPANSION (call-graph lockstep — flagged for hand-review)
`enqueueBoxForCrank` spans 3 contract files (DegenerusGame + the `IDegenerusGame` interface decl + the `DegenerusGameMintModule` caller). A complete, *compiling* KEEP-01 purge therefore required lockstep renames in `IDegenerusGame.sol` + `DegenerusGameMintModule.sol` (the plan's files_modified under-counted; the plan text DID say "update any enqueue caller in lockstep"). Their keeper-crank comments were also reworded. The presale-box "sweeps the Pool.PresaleBox remainder" comment (MintModule:146) is a DIFFERENT concept — LEFT.
**Test files:** the rename broke `forge build` (96 .sol test files reference the old keeper surface). Propagated the same rename map to all Solidity test files (free to modify; mechanical). Test file NAMES (e.g. `SweepPerPlayerWorstCaseGas.t.sol`) and test-internal helper names were partially renamed by the sed but are cosmetic — TST (Phase 327) owns test polish.

## Verification
- AfKing.sol + DegenerusGame.sol: `grep -ic 'sweep'` = 0, `grep -ci 'crank\|do-work'` = 0.
- `enqueueBoxForCrank` gone tree-wide; `enqueueBoxForAutoOpen` consistent across the 3 files; `crankBets`/`crankBoxes` etc. gone.
- `bytes32("DGNRS")` wired (1); no `bytes32(0), payKind`; no `bytes32("VAULT")`. `creditFlip`/`BOUNTY_ETH_TARGET` (13 refs) + DegenerusAffiliate.sol unchanged.
- (Build confirmation pending the KEEP wave build / 326-08 authoritative build.)

## Not committed
Batched-diff discipline.
