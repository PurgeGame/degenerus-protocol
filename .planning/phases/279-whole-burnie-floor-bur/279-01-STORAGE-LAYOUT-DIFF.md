# Phase 279 / Plan 01 — Storage-Layout Byte-Identity Proof

**Requirement:** BUR-04 (storage layout byte-identical to v39 baseline `6a7455d1` for both modified modules).
**Decisions:** D-279-INLINE-01 (inline `(x / 1 ether) * 1 ether` floor at 3 RNG-amount sites), D-279-BUR01-SITE-01 (`_resolveLootboxCommon` `burnieAmount` accumulator floored once), D-279-BUR02-DEADVAR-01 (`extra`/`cursor` cursor-rotation machinery fully removed from `_awardDailyCoinToTraitWinners`), D-279-BUR03-ORDER-01 (`_awardFarFutureCoinJackpot` `perWinner` floored before the `== 0` early-bail), D-279-DISAMBIG-01 (the OUT-OF-SCOPE ticket-award cursor-rotation near `:1003` left untouched).

## Baseline vs HEAD

| Side | Commit | File state |
|------|--------|------------|
| v39 baseline | `6a7455d1` (`audit(274): §9 closure attestation block + 274-01-SUMMARY.md`) | `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/modules/DegenerusGameJackpotModule.sol` at v39.0 close |
| Phase 279 pre-commit | working tree + Plan 01 Tasks 1–2 edits (uncommitted) | Same two files with the 3 inline whole-BURNIE floors, the `extra`/`cursor` dead-var removal in `_awardDailyCoinToTraitWinners`, the `_resolveLootboxCommon` burnie-accumulation reorder (stack-depth fix — see note), and the NatSpec/comment rewrites |

`6a7455d1` is the `MILESTONE_V39_AT_HEAD_6a7455d1` baseline. Phases 275–278 between the v39 baseline and Phase 279 did not move any `DegenerusGameLootboxModule.sol` or `DegenerusGameJackpotModule.sol` state variable — Phase 279 touches only function bodies + NatSpec, so `6a7455d1` is the correct and valid storage-layout baseline for both files.

## Extraction Recipe

Standard `forge inspect ... storage-layout` mechanic, mirroring the Phase 275/278 artifact convention. The v39 baseline tree was materialized read-only via `git archive 6a7455d1 | tar -x` into a temp directory (no commit, no working-tree checkout):

1. `forge inspect contracts/modules/DegenerusGameLootboxModule.sol:DegenerusGameLootboxModule storage-layout` at the current working tree (Tasks 1–2 applied) → `/tmp/p279-lootbox-head.txt` (171 lines).
2. `forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule storage-layout` at the current working tree → `/tmp/p279-jackpot-head.txt` (171 lines).
3. `git archive 6a7455d1 | tar -x -C /tmp/p279-baseline` → `forge inspect ... storage-layout` for both modules inside the baseline tree → `/tmp/p279-lootbox-baseline.txt`, `/tmp/p279-jackpot-baseline.txt` (171 lines each).
4. `diff` each baseline vs HEAD + `sha256sum` cross-check.

`forge inspect ... storage-layout` emits the resolved `{slot, offset, label, type, contract}` table directly — no `astId` normalization needed (the `forge` table view, unlike the raw Hardhat `storageLayout` JSON, does not embed compiler-internal AST node IDs).

## Verdict

**PASS — storage byte-identical to v39 baseline `6a7455d1` for BOTH modules.**

### `DegenerusGameLootboxModule.sol`

- Layout line count: **baseline = 171**, **HEAD = 171**.
- `diff /tmp/p279-lootbox-baseline.txt /tmp/p279-lootbox-head.txt`: **empty (exit 0)**.
- `sha256sum` cross-check — identical hashes:

```
a26ef648c71114a311189533faaeed66b741f8ae429c73dba8345e7a1434c4c3  /tmp/p279-lootbox-baseline.txt
a26ef648c71114a311189533faaeed66b741f8ae429c73dba8345e7a1434c4c3  /tmp/p279-lootbox-head.txt
```

### `DegenerusGameJackpotModule.sol`

- Layout line count: **baseline = 171**, **HEAD = 171**.
- `diff /tmp/p279-jackpot-baseline.txt /tmp/p279-jackpot-head.txt`: **empty (exit 0)**.
- `sha256sum` cross-check — identical hashes:

```
fc0e173c4d7e8f59575b6ffb2981439563f2f961b5aac5fb5ea3ee5ac35d2ce8  /tmp/p279-jackpot-baseline.txt
fc0e173c4d7e8f59575b6ffb2981439563f2f961b5aac5fb5ea3ee5ac35d2ce8  /tmp/p279-jackpot-head.txt
```

(The `DegenerusGameJackpotModule.sol` baseline hash `fc0e173c…` matches the Phase 278 storage-layout artifact's recorded hash — independent corroboration that the JackpotModule storage layout has been stable across Phases 275–279.)

## BUR-04 Satisfaction Note

Phase 279's two-file contract surface change introduces **zero** storage-layout effect:

- **`_resolveLootboxCommon` BUR-01 floor + burnie-accumulation reorder** — the `burnieAmount = (burnieAmount / 1 ether) * 1 ether;` floor is a function-body arithmetic statement on a named return local; the accompanying reorder (moving the `burnieAmount` accumulation block from after the ticket-handling block to immediately after `_accumulateLootboxRolls` returns) only relocates function-body statements within the same function and shortens the live-range of the `burniePresale` / `burnieNoMultiplier` stack locals. No contract-level state added or moved.
- **`_awardDailyCoinToTraitWinners` BUR-02 floor + `extra`/`cursor` removal** — `baseAmount` is floored via an arithmetic expression change; the `extra` / `cursor` removal **only deletes function-scope stack locals** (`uint256 extra`, `uint256 cursor`) and their `++cursor`/wrap update sites. Stack locals are never storage — their deletion cannot alter the storage layout.
- **`_awardFarFutureCoinJackpot` BUR-03 floor** — `perWinner` floored via an arithmetic expression change inside the function body, before the unchanged `if (perWinner == 0) return;`.
- **NatSpec / comment rewrites** — comment-only; no codegen, no storage effect.

No contract-level state variables, mappings, structs, events, modifiers, or admin/external entry points were added, removed, or reordered in either file. BUR-04's storage byte-identity requirement is satisfied for both `DegenerusGameLootboxModule.sol` and `DegenerusGameJackpotModule.sol`.
