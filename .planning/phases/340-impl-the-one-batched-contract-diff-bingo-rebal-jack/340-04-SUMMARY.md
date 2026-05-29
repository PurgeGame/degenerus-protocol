---
phase: 340-impl-the-one-batched-contract-diff-bingo-rebal-jack
plan: 04
status: complete
requirements: [BATCH-02]
---

# Phase 340 Plan 04: forge build + BATCH-02 HARD STOP Summary

## What Was Built

The IMPL-bar verification (D-340-03: `forge build` clean ONLY) for the full v51.0 batched
diff, plus the diff inventory and the contract-commit hand-review hand-off. NO test runs
(folded to v52 per USER — see below).

### Task 1 — forge build (the IMPL bar)
`forge build` exits **0** ("Compiler run successful"). Two real errors were caught and
fixed during this gate:
1. `ContractAddresses.sol:34` — the 340-01 `GAME_BINGO_MODULE` placeholder address had a
   bad EIP-55 checksum (Error 9429). Corrected to the checksummed form (freely-modifiable
   file, `feedback_contractaddresses_policy`).
2. `DegenerusGameJackpotModule.sol` — a third `_processDailyEth` call site still passed the
   removed `isFinalDay` arg (Error 6160, 8 args vs 7). Fixed.

**No NEW warnings attributable to the diff** (the D-340-03 bar). The new
`DegenerusGameBingoModule.sol` is warning-free. The `isFinalDay` parameter was removed
ENTIRELY from the daily-eth chain (USER directive — see Deviations), so there is NO
unused-parameter warning from the JACK deletion. All remaining `contracts/` warnings
(the `:425/426` shadow pair, the pre-existing unused `entropy` param in `_payNormalBucket`)
are PRE-EXISTING (untouched by the diff, git-diff-confirmed).

### Task 2 — Diff inventory
`git diff --name-only -- contracts/` = exactly the 8 SPEC files (7 modified + 1 new),
no other `contracts/` file, no incidental edit:
- `storage/DegenerusGameStorage.sol` — 3 bingo bitfield mappings appended (tail)
- `modules/DegenerusGameBingoModule.sol` — NEW: the 3-tier `claimBingo` body
- `ContractAddresses.sol` — `GAME_BINGO_MODULE` constant
- `DegenerusGame.sol` — the `claimBingo` delegatecall entrypoint + iface import
- `interfaces/IDegenerusGame.sol` — `claimBingo` facade sig
- `interfaces/IDegenerusGameModules.sol` — `IDegenerusGameBingoModule` selector iface
- `StakedDegenerusStonk.sol` — REBAL (AFFILIATE 3500→3000 / REWARD 500→1000)
- `modules/DegenerusGameJackpotModule.sol` — JACK deletion + full isFinalDay-param removal

Freeze-safety (BINGO-06): the diff adds **NO** write to `traitBurnTicket` (grep-confirmed);
the MintModule writer `:603-643` is untouched. `claimBingo` is a strict read-only consumer.

### Task 3 — BATCH-02 contract-commit HARD STOP
The full batched `contracts/*.sol` diff is applied + `forge build`-clean + held UNCOMMITTED
in the working tree, PRESENTED to the user for explicit hand-review. NOT committed without
approval (`feedback_no_contract_commits` + `feedback_never_preapprove_contracts` +
`feedback_pause_at_contract_phase_boundaries`). Never auto-approved despite
`workflow.auto_advance=true`.

## Deviations from Plan (USER-directed, mid-execution 2026-05-28)

1. **Level guard REMOVED** (340-01 module). Locked SPEC had `require(level <= currentLevel)`;
   user identified it as a defect (traits pre-resolve to `currentLevel+5`, so the gate
   wrongly blocked the pre-resolved near-future window). The 8-color ownership check
   self-gates (empty bucket → fail-closed). Freeze-safe: read-only on `traitBurnTicket`.
   The 339-BINGO06 freeze proof + 340-CONTEXT D-01 need a one-line re-attestation dropping
   the level-gate premise — flagged for the v52 audit.
2. **Signature `uint24 level`** (not `uint256`). With the guard gone, the uint256
   "ABI-convenience" width was pointless; taking `uint24` drops the recast and fail-closes
   on oversized input (no silent truncation aliasing). Applied across all 4 selector sites.
3. **`isFinalDay` param removed ENTIRELY** from the JackpotModule daily-eth chain
   (`_processDailyEth` → `_processBucket` → `_handleSoloBucketWinner`), instead of leaving a
   dangling unnamed `bool`. It was dead end-to-end after the JACK Pool.Reward deletion. The
   3 `_processDailyEth` call sites dropped the arg; `isFinalPhysicalDay_` stays (still used
   for share-select + pool accounting); the separate `:606/609` lvl+1 ticket-index gate is
   untouched.

## v52 fold (USER, 2026-05-28)
Per USER ("move this along and fold tests and shit into v52"): the Phase 341 TST work
(TST-01..06: per-tier / precedence / dedup / empty-pool / jackpot-regression + the
NON-WIDENING full-suite regression) is **deferred into the v52 consolidated audit** rather
than run as a standalone v51 phase. v51.0 IMPL = applied + compiles; behavior verification
+ regression move to v52 (alongside the already-deferred 3-skill sweep + delta-audit +
FINDINGS-v51.0). The freeze-proof re-attestation (dev #1 above) rides along to v52.

## Self-Check: PASSED (forge build exit 0; 8-file diff; no traitBurnTicket write; held for hand-review)
