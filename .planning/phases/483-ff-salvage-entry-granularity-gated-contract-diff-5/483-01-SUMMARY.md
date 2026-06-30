---
phase: 483-ff-salvage-entry-granularity-gated-contract-diff-5
plan: 01
subsystem: far-future-salvage
tags: [ff-salvage, entry-granularity, sellFarFutureEntries, gated-diff-5, behavior-change, mint-module]

# Dependency graph
requires:
  - phase: 480-01
    provides: entry/ticket identifier rename (entriesOwedPacked, _queueEntries, QTY_SCALE)
  - phase: 481-01
    provides: event/ABI + view-selector entries rename (uncommitted contracts in working tree)
  - phase: 482-01
    provides: degenerette dead-mode repack (uncommitted contracts in working tree)
provides:
  - FF-salvage now operates at ENTRY granularity (4 entries = 1 whole ticket); sub-whole-ticket salvage enabled
  - sellFarFutureTickets -> sellFarFutureEntries (+ preview / internal helper / Vault wrapper) rename
  - byte-identical value at whole-ticket-aligned points (no-regression proven)
affects: [484-verify-and-close, ff-salvage, mint-module]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "5-site coupled value change: input-meaning + valuation half move together to avoid a 4x mis-value"
    - "byte-identity guard normalization extended per audited gated diff (FIX-05 reconciliation pattern)"

key-files:
  created:
    - .planning/phases/483-ff-salvage-entry-granularity-gated-contract-diff-5/483-01-PLAN.md
    - .planning/phases/483-ff-salvage-entry-granularity-gated-contract-diff-5/483-01-SUMMARY.md
  modified:
    - contracts/modules/DegenerusGameMintModule.sol (UNCOMMITTED — sites 1 & 4 + renames + NatSpec)
    - contracts/modules/DegenerusGameMintStreakUtils.sol (UNCOMMITTED — sites 2 & 3 + NatSpec)
    - contracts/DegenerusGame.sol (UNCOMMITTED — external rename + selector + NatSpec)
    - contracts/DegenerusVault.sol (UNCOMMITTED — IGamePlayer decl + owner wrapper + forwarder)
    - contracts/interfaces/IDegenerusGame.sol (UNCOMMITTED — preview decl)
    - contracts/interfaces/IDegenerusGameModules.sol (UNCOMMITTED — sell + preview decls)
    - test/fuzz/FarFutureSalvageSwap.t.sol
    - test/fuzz/FarFutureVaultFallback.t.sol
    - test/unit/LootboxAutoResolveMintBoostRegression.test.js

key-decisions:
  - "Input quantities[] reinterpreted whole-tickets -> ENTRIES; faceWei = price * n / 4 couples the valuation so aligned points stay byte-identical"
  - "Floors (budget revert + ticket leg) drop from one whole ticket to one entry = oneTicketWei / 4"
  - "gameSellFarFutureTickets (Vault owner wrapper) renamed to gameSellFarFutureEntries — only referenced inside the Vault"
  - "oneTicketWei kept (whole-ticket price per ledger 10.6 KEEP); the /4 derives one entry inline"

patterns-established:
  - "Test no-regression transform: a whole-ticket count W becomes W*4 entries -> byte-identical face/budget + same full sell-out"
  - "Byte-identity guard folds each audited gated diff via exact .replace() normalization, staying strict on any other drift"

requirements-completed: [FF-SALVAGE-GRAN-01]

# Metrics
duration: ~80min
completed: 2026-06-30
---

# Phase 483 Plan 01: FF-Salvage Entry-Granularity Summary

**Far-future salvage made entry-granular via the 5-site coupled change (input now ENTRIES, faceWei = price·n/4, floors at one entry = oneTicketWei/4), with `sellFarFutureTickets`→`sellFarFutureEntries` renamed across the surface; sub-whole-ticket salvage now works and whole-ticket-aligned values stay byte-identical.**

## Performance

- **Duration:** ~80 min
- **Tasks:** 4 (author plan, apply 5-site coupled change + rename, verify, commit + summary)
- **Files modified:** 6 contracts (uncommitted) + 3 test + 2 docs

## Accomplishments
- Applied the 5-site coupled entry-granularity change with verified unit algebra (no 4× mis-value).
- Renamed the FF-salvage surface `sellFarFutureTickets`→`sellFarFutureEntries` (+ preview, internal `_removeFarFutureEntries`, Vault/IGamePlayer/Game wrappers, owner `gameSellFarFutureEntries`).
- Updated the FF-salvage forge suites to the new granular expectations + added two new tests proving sub-whole-ticket salvage and whole-ticket-aligned no-regression.
- Reconciled the MintModule byte-identity guard (FIX-05 class) to fold the audited 483 diff.
- Floors held: full forge **1005/0/107** (1003 + 2 new) and the FF salvage suites green; Hardhat back to floor after the guard fix.

## The 5 coupled sites (unit algebra)

`quantities[i]` changed meaning whole-tickets → ENTRIES (4 entries = 1 whole ticket). `priceForLevel(L)` is the WHOLE-ticket price; one entry's face = `priceForLevel(L)/4`.

1. `DegenerusGameMintModule.sol` — `uint32 entries = uint32(quantities[i]) * 4;` → `= uint32(quantities[i]);` (input IS entries; debit/queue use it directly).
2. `DegenerusGameMintStreakUtils.sol` — `faceWei = priceForLevel(L) * n;` → `= (priceForLevel(L) * n) / 4;` (coupled valuation half: per-entry face).
3. `DegenerusGameMintStreakUtils.sol` — ticket-leg floor `if (ticketWei < oneTicketWei)` → floors at `oneTicketWei/4` (one entry); the `ticketWei > totalBudget` preview-safety clamp unchanged (still underflow-safe).
4. `DegenerusGameMintModule.sol` — too-small revert `if (totalBudget < oneTicketWei)` → `if (totalBudget < oneTicketWei / 4)` (one entry).
5. NatSpec/comments + rename surface (Game external + selector, MintModule impl + event/preview NatSpec, both interfaces, Vault `IGamePlayer` decl + owner wrapper + forwarder).

**No 4× mis-value (proof):** at the aligned point `E = 4W`, NEW faceWei = `price·4W/4 = price·W` = OLD faceWei; NEW budget = OLD budget; NEW entries debited = `4W` = OLD. The "only change site 1" trap (faceWei = price·E treating entries as whole tickets) is exactly what site 2's `/4` cancels.

**Granularity-agnostic, left unchanged (verified):** `_purchaseFor` mint-qty (ticketWei↔scaled-units ratio; floors to 1 entry = QTY_SCALE), `_quoteFarFutureFlipSplit` (ETH↔FLIP price ratio), `_removeFarFutureEntries`/`_queueEntries` (take entries directly), the FF jackpot samplers / `_tqFarFutureKey` / `TICKET_FAR_FUTURE_BIT` (KEEP; membership `<=> packed != 0` preserved).

## Test changes

- **FarFutureSalvageSwap.t.sol / FarFutureVaultFallback.t.sol:** all call sites `game.sellFarFutureTickets(`/`previewSellFarFutureTickets(` → `...Entries(`. Every `qtys` whole-ticket count → `×4` entries (seed helpers already store `whole*4` entries), so face/budget stay byte-identical and full sell-outs still fully clear.
- **Floor test redesign** (`test_SWAP09_TicketFloorEnforced` → `test_SWAP09_EntryFloorEnforced`): a 1-entry quote at d=100 yields budget < `oneTicketWei/4` → revert; the floor-clearing case asserts the ticket leg delivers ≥ one entry.
- **New `test_SWAP09_SubWholeTicketSalvage`:** seed 4 entries (1 whole) at a milestone far level (L=100, 0.24 ETH), sell 2 entries → seller 4→2 (partial, NOT popped), buyer +2; preview linearity (face1=price/4, face2=price/2, face4=price, face4=4·face1) proves correct proration.
- **New `test_SWAP09_WholeTicketAlignedNoRegression`:** previewing 4 entries reproduces the pre-granularity whole-ticket value byte-for-byte — `faceWei == priceForLevel(L)` and `budget == face·fractionBps(d)·jitterMult/1e8` swept across distances.

## Task Commits

1. **Tests + plan (FF-salvage suites + byte-identity guard + 483-01-PLAN.md)** — `7d2c3a43` (test)
2. **Plan metadata (SUMMARY + this commit)** — see final docs commit below

Contracts (the 5-site coupled change + rename) are left **UNCOMMITTED** per the gated contract-diff #5 rule; the orchestrator captures the incremental 483 patch from snapshots.

## Decisions Made
- Kept `oneTicketWei` named (whole-ticket price per ledger §10.6 KEEP); one entry derived inline as `/4`.
- Renamed the Vault owner wrapper `gameSellFarFutureTickets` → `gameSellFarFutureEntries` (only self-referenced; no interface/test/off-chain caller).
- Ratio/preview tests (SWAP08 a/c) use `qtys=4` (one whole far ticket = 4 entries) so `faceWei` is byte-identical to the pre-change whole-ticket test and the exact `fractionBps` equality assertions still hold.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Byte-identity guard tripped by the audited MintModule diff**
- **Found during:** Task 3 (verification — full `npm test`)
- **Issue:** `LootboxAutoResolveMintBoostRegression.test.js` [03a] asserts `DegenerusGameMintModule.sol` is byte-identical to committed HEAD except the audited Phase-481 ABI rename. The audited 483 FF-salvage rename + 5-site value change legitimately drifts MintModule further → 1 failing (the FIX-05 class flagged in project memory: contract edits break source-string/byte-identity guards, invisible to forge).
- **Fix:** Extended the [03a] normalization to fold the 483 FF-salvage renames (3 global `.replace()`) + the 4 residual non-rename hunks (the doc `/4`, the "Mass-sells ENTRIES" NatSpec, site-4, the site-1 comment+`*4` removal) — mirroring how the test already folds the 481 rename. The guard stays strict against any OTHER drift.
- **Files modified:** test/unit/LootboxAutoResolveMintBoostRegression.test.js
- **Verification:** Isolated run 9/9 passing; full Hardhat returns to the 1362/0 floor.
- **Committed in:** `7d2c3a43`

---

**Total deviations:** 1 auto-fixed (Rule 1 — test-guard reconciliation, no contract impact)
**Impact on plan:** Necessary; no scope creep. The byte-identity guard is brittle during an active multi-phase gated-diff milestone (HEAD pinned at 480 while 481/482/483 accumulate uncommitted) — each audited MintModule diff must be folded into its normalization. Flagged for 484 close.

## Issues Encountered
- **Mocha `dispose()` teardown crash:** after a full `npm test`, mocha's `unloadFile` throws `MODULE_NOT_FOUND` for a relative test path during cleanup. This fires AFTER all tests pass (the passing count is printed first) and is a pre-existing harness/version artifact — NOT a test failure and unrelated to 483. The `tail`-piped first run masked the passing count behind this crash; re-running with full capture revealed the real result.
- **NO flake attribution:** the one genuine failure (byte-identity guard) was localized to its real cause and fixed; no toolchain/setUp flake was invoked.

## Next Phase Readiness
- 483 is the last entry-granularity gap closed. Ready for **484 (verify + close)**: full suite + layout goldens + RTP re-sim + cross-model re-audit + milestone closure.
- Open item for 484: the MintModule byte-identity guard's normalization should be retired/re-anchored once the v75 contracts are finally committed at milestone close (it currently carries 481 + 483 folds).

## Verification Results

- **Full forge:** 1005 passed / 0 failed / 107 skipped (1003 floor + `test_SWAP09_SubWholeTicketSalvage` + `test_SWAP09_WholeTicketAlignedNoRegression`).
- **FF salvage suites:** FarFutureSalvageSwap 11/0, FarFutureVaultFallback 19/0.
- **Full Hardhat:** 1362 passing / 0 failing / 19 pending (floor restored after the byte-identity guard fix).
- **Build:** `npx hardhat compile` + `forge build` green.

## Self-Check: PASSED

- FOUND: 483-01-PLAN.md
- FOUND: 483-01-SUMMARY.md
- FOUND: commit `7d2c3a43` (test + plan)
- Contracts left UNCOMMITTED (12 dirty: 481+482+483 cumulative); ContractAddresses.sol compile-artifact restored.

---
*Phase: 483-ff-salvage-entry-granularity-gated-contract-diff-5*
*Completed: 2026-06-30*
