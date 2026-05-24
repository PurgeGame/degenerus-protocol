---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 03
subsystem: contracts
tags: [solidity, do-work-crank, batchPurchase, afking-removal, vrf-orphan-index, coinflip-credit]

# Dependency graph
requires:
  - phase: 317-01
    provides: confirmed pre-patch file:line ledger (live anchors over stale SPEC) + pre-deletion baseline
  - phase: 316-spec
    provides: PROTO-01/04 + CRANK-01..04/REW-01..04 + RM-01/04 + SUB-09 design lock; OPEN-B/OPEN-C/OPEN-D resolutions
provides:
  - "hasAnyLazyPass(address) external view (PROTO-01 KEEP+EXPOSE; the keeper's sole pass gate) + IDegenerusGame mirror decl"
  - "batchPurchase(players[], amounts[], modes[]) keeper-gated on AF_KING, per-player slice-refund try/catch, ONE batch value transfer, CEI-proof (no guard)"
  - "permissionless do-work crank: crankBets (caller-list + BatchAlreadyTaken short-circuit) + crankBoxes (parameterless cursor following the a303ae18 re-issue coupling)"
  - "RM-01 deletion of the 13 afKing-mode fns + 3 events + AfKingLockActive error + 3 consts + 2 settleFlipModeChange cross-calls; SUB-09 ctor Deity grant preserved byte-unmodified"
affects: [317-04, 317-05, 318, 319, 320]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-item fault isolation via onlySelf self-external-call + try/catch (SAFE-02)"
    - "Gas-pegged BURNIE bounty via fixed gasUnits constants -> _ethToBurnieValue -> ONE creditFlip/tx (REW-01..04)"
    - "Box cursor keyed on lootbox index, gated on lootboxRngWordByIndex != 0 (a303ae18 orphan-index coupling)"

key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/interfaces/IDegenerusGame.sol

key-decisions:
  - "OPEN-C reentrancy: CEI-proof, NO explicit guard added — the only external call in the per-player mint->lootbox path before the day-stamp is the fixed-recipient VAULT value-hop (MintModule:1066), made after the prize-pool state writes (CEI); VAULT cannot pass the AF_KING gate, so no re-entrant double-buy path exists."
  - "Box-cursor storage (boxCursor/boxCursorIndex/boxPlayers) declared in DegenerusGame.sol-local layout + an onlySelf enqueueBoxForCrank hook; the MintModule first-deposit producer call-site is a cross-plan wiring follow-on (file not owned by this plan)."
  - "Authored a local zero-guarded _ethToBurnieValue private pure in DegenerusGame.sol (the MintModule one is not inherited) — same idiom, OPEN-B zero-guard."

patterns-established:
  - "Crank reward = fixed RESERVED gasUnits constants (CRANK_RESOLVE_BET_GAS_UNITS / CRANK_OPEN_BOX_GAS_UNITS placeholders, calibrated at Phase 319) · CRANK_GAS_PRICE_REF (0.5 gwei); never gasleft()/tx.gasprice."
  - "WWXRP currency==3 explicit zero-reward branch in the crank reward path (CRANK-04)."

requirements-completed: [PROTO-01, PROTO-04, CRANK-01, CRANK-02, CRANK-03, CRANK-04, REW-01, REW-02, REW-03, REW-04, RM-01, RM-04, SUB-09]

# Metrics
duration: ~40min
completed: 2026-05-23
---

# Phase 317 Plan 03: DegenerusGame Crank + batchPurchase + AfKing-Mode Removal Summary

**Exposed `hasAnyLazyPass`, added the keeper-gated `batchPurchase` + the permissionless do-work crank (bets caller-list + box cursor following the a303ae18 VRF orphan-index re-issue coupling), and deleted the entire afKing-mode surface — all on `DegenerusGame.sol` + `IDegenerusGame.sol`, left UNCOMMITTED for the Wave-5 batched contract approval.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3 (all `auto`; Tasks 2 & 3 marked `tdd="true"` but TST coverage is Phase 318's owner — see Deviations)
- **Files modified:** 2 (the two files this plan exclusively owns)
- **Compile:** `FOUNDRY_PROFILE=default forge build` exit 0, zero compilation errors (only pre-existing unrelated `unsafe-typecast` lint warnings)

## Accomplishments

- **PROTO-01 / RM-04 KEEP+EXPOSE:** renamed the kept `_hasAnyLazyPass` private view to `hasAnyLazyPass` external view, body byte-identical (`DegenerusGame.sol:1472`); added the mirror decl in `IDegenerusGame.sol` next to `hasDeityPass`.
- **RM-01 deletion:** removed the 13 afKing-mode functions (keeping ONLY `hasAnyLazyPass`), the 3 events (`AutoRebuyToggled`/`AutoRebuyTakeProfitSet`/`AfKingModeToggled`), the `AfKingLockActive` error, the 3 consts (`AFKING_KEEP_MIN_ETH`/`AFKING_KEEP_MIN_COIN`/`AFKING_LOCK_LEVELS`), and the 2 `coinflip.settleFlipModeChange` cross-calls (plus the `coinflip.setCoinflipAutoRebuy` call that died with `_setAfKingMode`). Grep-clean: zero non-comment afKing-mode-symbol matches; zero `AutoRebuyState`/`autoRebuyState` references remain in the file.
- **IDegenerusGame.sol RM-05 share:** removed the 4 afKing decls (`afKingModeFor`/`afKingActivatedLevelFor`/`deactivateAfKingFromCoin`/`syncAfKingLazyPassFromCoin`); kept `hasDeityPass`; added `hasAnyLazyPass`.
- **SUB-09 preservation:** the constructor Deity grant on SDGNRS/VAULT is byte-unmodified (now at `:213/:214` after upstream deletions shifted the line numbers — the `git diff` shows ZERO `+`/`-` lines touching the `setPacked … HAS_DEITY_PASS_SHIFT` statements). No new Deity-bit setter authored.
- **PROTO-04 batchPurchase:** `batchPurchase(address[], uint256[], uint8[]) payable` keeper-gated on `ContractAddresses.AF_KING` (`:1692`), no per-player approval; once-at-entry `rngLocked` + `gameOver` pre-check; ONE batch value transfer with per-player `try this._batchPurchaseUnit{value: slice}(...) catch {}` slice-refund (`_batchPurchaseUnit` is onlySelf, skips the approval gate, forwards the per-player `msg.value` slice into the mint module); a single post-loop refund of all unspent value to the keeper.
- **Do-work crank (CRANK-01..04 / REW-01..04):**
  - `crankBets(address[] players, uint64[] betIds)` — parallel-array caller-list; CRANK-02 `BatchAlreadyTaken` short-circuit probes item 0 (`degeneretteBets[players[0]][betIds[0]] == 0`); items 1..N isolated via `try this._crankResolveBet(...) catch {}` (onlySelf, reuses the degenerette `resolveBets` machinery with the approval gate relaxed for resolve); WWXRP `currency == 3` explicit zero-reward branch (`:1564`); reward accumulated in memory, paid as ONE `coinflip.creditFlip(msg.sender, sum)` (`:1578`).
  - `crankBoxes(uint256 maxCount)` — parameterless self-partitioning cursor (`boxCursor` + `boxCursorIndex` day/index-reset); per-item `try this._crankOpenBox(...) catch {}` (onlySelf, reuses `openLootBox` which preserves the `RngNotReady` guard + the one-reward-per-item box-zeroing untouched); ONE batched `creditFlip` at end.
- **REW-03 no-measured-gas:** zero non-comment `gasleft()` / `tx.gasprice` matches anywhere in `DegenerusGame.sol`. Reward = fixed RESERVED `CRANK_RESOLVE_BET_GAS_UNITS` / `CRANK_OPEN_BOX_GAS_UNITS` (placeholder 120_000, calibrated at Phase 319) · `CRANK_GAS_PRICE_REF` (0.5 gwei) → BURNIE via the zero-guarded `_ethToBurnieValue`.

## Box-cursor a303ae18 re-issue coupling (the milestone's single biggest landmine — LIVE line citations)

The box cursor keys on the lootbox index, re-coupling to the v45 VRF-rotation orphan-index keyspace (`project_vrf_rotation_midday_orphan_index`). The authored crank box-cursor path follows the v45 `a303ae18` detect-preserve-re-issue path, demonstrated in-code (NOT merely "documented for 320"):

- **`contracts/DegenerusGame.sol:1603`** — `if (lootboxRngWordByIndex[index] == 0) return;` — the orphan-index gate: a box is openable only once its index has a VRF word. A zero word means the index is not ready OR was orphaned by a mid-day emergency rotation; either way the walk skips the whole index until `updateVrfCoordinatorAndSub` (`AdvanceModule:1726-1740`) re-issues the in-flight request (keeping `LR_MID_DAY`/`LR_INDEX`) and the re-issued word lands in the reserved slot. This mirrors the `LootboxModule:485` `RngNotReady` guard exactly — the cursor cannot open an orphaned index, so a raw-index walk WITHOUT this gate (which would re-introduce the catastrophe) is structurally avoided.
- **`contracts/DegenerusGame.sol:1618`** — `if (lootboxEthBase[index][player] == 0) continue;` — the first-deposit signal (written `MintModule:1004-1008`, zeroed on open `LootboxModule:531`) used as the per-player dequeue check inside the walk.
- **`contracts/DegenerusGame.sol:1526-1528`** — `enqueueBoxForCrank(uint48 index, address player)` (onlySelf) pushing to `boxPlayers[index]`, keyed on the same lootbox index; the enqueue trigger is the `lootboxEthBase == 0` first-deposit signal.

The DEEP freeze-under-rotation adversarial re-attestation is routed to **Phase 320 AUDIT** (zero-day-hunter), blocking if the coupling is absent — it is present and grep-confirmed (`lootboxRngWordByIndex` + `lootboxEthBase` both appear in the crank box-cursor path).

## OPEN-C reentrancy trace (mandatory IMPL obligation; routed to contract-auditor at 318/320)

The `batchPurchase` per-player path runs `_purchaseFor` → `MintModule.purchase` (delegatecall). External calls in that chain before the post-loop refund/day-stamp:

| Call site | Recipient | Disposition |
|-----------|-----------|-------------|
| `MintModule:1066` `payable(VAULT).call{value: vaultShare}` | pinned `ContractAddresses.VAULT` | Made AFTER the prize-pool state writes (`_setPrizePools` `:1054-1063`) = CEI. Recipient is the pinned VAULT, which CANNOT pass the `msg.sender == AF_KING` gate → no re-entrant `batchPurchase`. |
| `MintModule:1229` `coinflip.creditFlip(buyer, …)` | pinned COINFLIP | bookkeeping credit, no value out; not a re-entrancy double-buy vector. |
| `MintModule:1408/1429` `coin.burnCoin(...)` | pinned COIN | BURNIE-path only (the DirectEth `purchase` slice does not reach it); pinned recipient, not AF_KING. |

**Disposition: CEI-proof, NO explicit reentrancy guard added.** The per-player slice moves into the sub-call frame on each `try`; a failed slice stays in the contract (refunded once after the loop), so there is no stored batch-debit a reentrant sweep/cancel could replay. This matches the SPEC OPEN-C lock ("CEI-proof WITH a guard-fallback note … add an explicit guard only if a re-entrant path is found"). The CEI-vs-guard proof is the highest-scrutiny ADD surface; the DEEP adversarial audit is routed to `contract-auditor` at Phase 318/320 (NOT attempted inline here, per the plan).

## Files Created/Modified

- `contracts/DegenerusGame.sol` — RM-01 afKing-mode deletion (keeping `hasAnyLazyPass`); PROTO-01 view rename; PROTO-04 `batchPurchase` + `_batchPurchaseUnit`; the do-work crank (`crankBets`/`crankBoxes`/`_crankResolveBet`/`_crankOpenBox`); the box-cursor storage (`boxCursor`/`boxCursorIndex`/`boxPlayers`) + `enqueueBoxForCrank` hook; local zero-guarded `_ethToBurnieValue`; `BatchAlreadyTaken` error added, `AfKingLockActive` error removed; SUB-09 ctor grant preserved byte-unmodified.
- `contracts/interfaces/IDegenerusGame.sol` — removed the 4 afKing decls; kept `hasDeityPass`; added `hasAnyLazyPass` + `enqueueBoxForCrank`.

## Decisions Made

- **OPEN-C → CEI-proof, no guard** (see trace above).
- **Box-cursor storage home = DegenerusGame.sol-local** (the controller). The crank lives in-game by construction; the cursor state (`boxCursor`/`boxCursorIndex`/`boxPlayers`) is declared in the concrete `DegenerusGame` layout (appended after inherited `DegenerusGameStorage` slots — pre-launch redeploy-fresh makes the layout break a non-issue; RM-06 slot re-derivation is sibling Plan 05's owner). The `enqueueBoxForCrank` onlySelf hook is the producer entry the MintModule first-deposit path calls via `IDegenerusGame(address(this))`.
- **Local `_ethToBurnieValue`** authored in `DegenerusGame.sol` (the MintModule one is `private` and not inherited) — same shape, OPEN-B zero-guard, mirroring the inline idiom already at the affiliate-deity-bonus path (`:1456-1458`).
- **batchPurchase per-player unit calls `_purchaseFor(player, 0, msg.value, bytes32(0), payKind)`** — a lootbox-only subscription buy (ticketQuantity 0, lootBoxAmount = the slice); the keeper supplies the per-player slice as the per-call `msg.value`. (The keeper's ticket/lootbox split semantics are Plan 04's concern; this is the locked PROTO-04 entry shape the keeper call-site is authored against.)

## Deviations from Plan

### Auto-fixed / structural-boundary items

**1. [Rule 3 - Cross-plan structural seam] Box-cursor enqueue producer call-site is a follow-on (file not owned by this plan)**
- **Found during:** Task 3 (box cursor)
- **Issue:** The OPEN-D box cursor needs an enqueue write at the MintModule first-deposit (`lootboxEthBase == 0`) path. `contracts/modules/DegenerusGameMintModule.sol` is NOT owned by Plan 03 (and no Wave-2/3 plan owns the crank-enqueue call-site). The cursor + the `onlySelf enqueueBoxForCrank` hook + the `IDegenerusGame` decl are fully authored here (the consumer side, which is what prevents the catastrophe via the `lootboxRngWordByIndex` gate); the one-line MintModule producer call (`IDegenerusGame(address(this)).enqueueBoxForCrank(lbIndex, buyer)` inside the `lbFirstDeposit` block at `MintModule:990`) is left as a documented wiring follow-on for the batched diff.
- **Why not done here:** strict file-ownership (the deferred-commit protocol forbids touching files this plan does not own). The absence of the producer call does NOT re-introduce the v45 catastrophe — the consumer's `lootboxRngWordByIndex[index] != 0` gate is the structural protection; an un-enqueued box is simply not box-crankable (it remains openable via the permissionless `openLootBox`, unchanged).
- **Routing:** flag for the Wave-5 batched-diff assembly + Phase 320 AUDIT to confirm the producer wiring lands. If a sibling plan does not pick it up, the orchestrator must add the one MintModule call before the batched commit.

**2. [Rule 2 - Spec fidelity] WWXRP branch authored as explicit `if (currency == 3)` zero-reward fork**
- **Found during:** Task 3 (crank reward)
- **Issue:** the SPEC asks for "an explicit `currency == 3 → reward 0` branch"; the initial draft used the equivalent `if (currency != 3)` reward-add form.
- **Fix:** restructured to the explicit `if (currency == 3) { /* zero reward */ } else { reward += … }` fork (`:1564`) to match the locked design verbatim.
- **Verification:** verify gate `grep -qE "currency *== *3"` matches the code (not just the comment); behavior unchanged (WWXRP earns zero).

---

**Total deviations:** 2 (1 cross-plan structural seam documented for follow-on; 1 spec-fidelity restructure).
**Impact on plan:** No scope creep. The crank/batchPurchase/RM-01/PROTO-01/SUB-09 surface is complete and compiles; the single cross-plan seam (MintModule enqueue producer) is the only out-of-file follow-on and is structurally non-catastrophic.

## TDD Gate Compliance

Tasks 2 & 3 carry `tdd="true"`, but **no test commits exist** — by design. Per ROADMAP/STATE, Phase 318 (TST) is the primary owner of SAFE-01..04 + the testable acceptance of CRANK/REW/RM/PROTO; this Wave-2 IMPL plan authors the contract surface only and leaves ALL commits deferred to the Wave-5 batched contract approval (the commit-guard hook blocks commits while `contracts/*.sol` is dirty). The RED/GREEN gate is therefore NOT applicable in this phase — there is no per-task commit at all (deferred-commit protocol). Behavioral correctness proofs land in Phase 318.

## Routing for 318/320 security review

- **OPEN-C (reentrancy):** CEI-proof disposition recorded above; route the deep CEI-vs-guard proof to `contract-auditor` at 318/320.
- **OPEN-D (box-cursor ↔ VRF orphan-index):** coupling present + live-line-cited (`DegenerusGame.sol:1603` + `:1618` + `:1526`); route the DEEP freeze-under-rotation re-attestation to `zero-day-hunter` at 320 (blocking if absent).
- **SAFE-01 (faucet resistance):** reward pegged below gas via fixed `gasUnits · 0.5 gwei`, paid as illiquid coinflip credit, WWXRP excluded; faucet-resistance proof routed to 318 TST.

## Issues Encountered

None blocking. The box-cursor enqueue producer seam (Deviation 1) was the only structural decision requiring an out-of-file follow-on note.

## User Setup Required

None - no external service configuration. NOTE: this plan's edits are intentionally UNCOMMITTED — the single batched contract commit happens at the Phase-317 Wave-5 USER-APPROVAL gate.

## Next Phase Readiness

- `DegenerusGame.sol` + `IDegenerusGame.sol` surface complete + compiling.
- Wave-5 batched-diff assembly must include the one-line MintModule `enqueueBoxForCrank` producer call (Deviation 1) before the batched commit.
- Plan 04 (`AfKing.sol`) calls `batchPurchase` against the locked PROTO-04 shape authored here; Plan 05 owns the RM-02/JGAS-02 storage + module deletions and the RM-06 slot re-derivation (which must account for the new `DegenerusGame`-local box-cursor slots appended here).

## Self-Check: PASSED

- `317-03-SUMMARY.md` present on disk (uncommitted; `.planning/` is gitignored).
- No git commit made; `HEAD` unchanged at `471cb4ac`; `STATE.md` / `ROADMAP.md` untouched.
- `contracts/` left dirty with exactly the 2 owned files (`DegenerusGame.sol`, `interfaces/IDegenerusGame.sol`) authored by this plan + sibling Plan 02's 4 files (`BurnieCoin.sol`, `BurnieCoinflip.sol`, `ContractAddresses.sol`, `interfaces/IBurnieCoinflip.sol`) left untouched.
- `FOUNDRY_PROFILE=default forge build` exit 0, zero compilation errors.
- All three verify-gate greps pass: `hasAnyLazyPass` exposed; afKing-mode symbol set = 0 non-comment matches; ctor `HAS_DEITY_PASS_SHIFT` grant byte-unmodified; `batchPurchase` + `AF_KING` + `BatchAlreadyTaken` + `boxCursor`/`boxPlayers` + `lootboxRngWordByIndex`/`lootboxEthBase` + `currency == 3` present; `gasleft()`/`tx.gasprice` = 0 non-comment matches.

---
*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Plan: 03*
*Completed: 2026-05-23*
