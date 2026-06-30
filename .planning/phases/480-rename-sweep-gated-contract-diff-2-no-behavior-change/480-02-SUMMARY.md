---
phase: 480-rename-sweep-gated-contract-diff-2-no-behavior-change
plan: 02
subsystem: tests
tags: [tickets, entries, rename, harness, by-name, regression, rn-10]

# Dependency graph
requires:
  - phase: 480-01 (bcc47ccc)
    provides: the shipped ticket→entry contract identifier rename (the source-strings the test sweep must now match)
provides:
  - "Every renamed internal-identifier literal swept from test/ (the forge-invisible runtime by-name class — 479's FIX-05 trap closed for the rename)"
  - "479-reconciled source-string suites moved to the _queueEntries(...) call form (wholeTicketsToEntries(whole) preserved)"
  - "B-1 stat sync: production-source regexes pin QTY_SCALE + scaledWholeTickets; EV math/samples byte-identical"
  - "DegeneretteV73Invariants reconciled to the post-480 namespace (logic-drift invariant preserved)"
affects: [481-event-surface, 482-degenerette-repack, 484-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Rename-normalized historical-baseline byte-compare: normalize an audited no-behavior identifier rename into the git-historical baseline so a source-byte invariant still detects real logic drift"

key-files:
  created:
    - .planning/phases/480-rename-sweep-gated-contract-diff-2-no-behavior-change/480-02-SUMMARY.md
  modified:
    - test/edge/DeityPassGoldNerfRegression.test.js
    - test/edge/LootboxAutoResolveRegression.test.js
    - test/edge/MintCleanupRegression.test.js
    - test/integration/CrossSurfaceTicketMixing.test.js
    - test/stat/JackpotTicketRollBernoulliEv.test.js
    - test/stat/DegeneretteV73Invariants.test.js
    - test/fuzz/QueueDoubleBuffer.t.sol
    - "(+ 28 more test/ files — 35 total)"

key-decisions:
  - "DegeneretteV73Invariants INV-04 was the rare degenerette source-string assertion the plan said to sweep (a git-historical byte-compare). 480-01's amountPerTicket→amountPerSpin broke it. Reconciled by normalizing that one audited rename into the v72 baseline inside preV73Source() — the byte-compare still catches any real logic drift; no logic/EV edit."
  - "B-1 production-vs-tester split: production _jackpotTicketRoll/_settleLootboxRoll regexes → scaledWholeTickets + QTY_SCALE; the JackpotBernoulliTester regexes KEEP scaledTickets (its param name, unrenamed) + QTY_SCALE. EV samples/Monte-Carlo/expected-values byte-identical."
  - "F1 gate scoped to production modules: Jackpot/Lootbox carry ZERO scaledTickets/countScaled (all → scaledWholeTickets/wholeTicketsScaled). The single contracts/ scaledTickets is the JackpotBernoulliTester param mirror (intentional, matches the kept tester-targeting test regexes)."

patterns-established:
  - "normalize480Rename in a held-fixed source-byte invariant: apply the audited rename pair to the historical baseline before comparison"

requirements-completed: [RN-10]

# Metrics
duration: ~3h (dominated by full-suite runs + forge environmental diagnosis)
completed: 2026-06-30
---

# Phase 480 / Plan 02: Runtime by-name + source-string rename sweep (RN-10) Summary

**Every renamed internal identifier from the 480-01 ticket→entry contract diff was swept out of `test/` across 35 files (the forge-invisible runtime by-name class that `forge build` cannot see) — storage labels (`lvlTraitEntry`, `entriesOwedPacked`), queue sinks (`_queueEntries`/`_queueEntriesScaled`/`_queueEntryRange`), the `_budgetToEntries` helper, the entries constants, the Decimator-BET names, `_degenerettePayout`, plus the 479-reconciled `_queueEntries(...)` source-string call form and the B-1 `QTY_SCALE`/`scaledWholeTickets` production-source regexes — proven behavior-preserving end-to-end by the FULL Hardhat suite (1362 passing, 0 failing) with the Bernoulli/EV testers green and their numeric content byte-identical.**

## Accomplishments

### Task 1 — exhaustive `test/` literal sweep — commit `848a56fe`

35 `test/` files updated. The grep-gated renamed identifiers were eliminated entirely from `test/` (assertions **and** comments, per council M-2/M-5):

- **Storage labels:** `traitBurnTicket`→`lvlTraitEntry` (incl. the 6× `deriveStorageSlot("lvlTraitEntry")` in `DeityPassGoldNerfRegression.test.js` and the JS slot-helper names in `DegenerusJackpots.test.js`); `ticketsOwedPacked`→`entriesOwedPacked` (incl. `.includes`/`===` reads in `LootboxAutoResolveRegression.test.js` and `MintCleanupRegression.test.js`).
- **Queue sinks:** `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange`→`_queueEntries`/`_queueEntriesScaled`/`_queueEntryRange` (incl. the `QueueDoubleBuffer.t.sol` `exposed_queue*` harness wrappers + their callers — the only `.t.sol` code-level rename; forge build green).
- **Helper / constants / Decimator / degenerette:** `_budgetToTicketUnits`→`_budgetToEntries`; `WHALE_BONUS/STANDARD/PASS/LAZY_*_TICKETS_PER_LEVEL` + `VAULT_PERPETUAL_TICKETS`→`*_ENTRIES_*`; `DecEntry`→`DecBet`; `_fullTicketPayout`→`_degenerettePayout`.
- **479-FIX-05-reconciled suites** (`CrossSurfaceTicketMixing`, `LootboxAutoResolveRegression`, `LootboxAutoResolveRemByte`, `LootboxConsolation`, `LootboxAutoResolveSilentColdBust`, `EventSurfaceUnification`, `JackpotTicketRollSilentColdBust`, `LootboxWholeTicket`, `LootboxAutoResolveMintBoostRegression`): every `_queueTickets(..., wholeTicketsToEntries(whole), ...)` source-string moved to the `_queueEntries(...)` form, `wholeTicketsToEntries(whole)` preserved exactly; the `if (quantity == 0) return;` early-return assertions synced to the renamed param (`if (entries == 0) return;`).
- **B-1 (BLOCKING) EV-tripwire sync** — `test/stat/JackpotTicketRollBernoulliEv.test.js`: the production-source regexes (`_jackpotTicketRoll` `[00a]`) now pin `scaledWholeTickets` + `QTY_SCALE`; the `JackpotBernoulliTester` regexes (`[00b]`) keep `scaledTickets` (its param) + `QTY_SCALE`. **No sample / Monte-Carlo / expected-value / EV-math edit** — only the contract-source-string literals moved. Same `QTY_SCALE`/`scaledWholeTickets` production-source sync applied in `LootboxWholeTicket.test.js` and `EventSurfaceUnification.test.js`.
- **H-2 negative-polarity** — `LootboxAutoResolveRemByte.test.js:97`, `CrossSurfaceTicketMixing.test.js` `% TICKET_SCALE` / `/TICKET_SCALE/.test(args[3])` → `% QTY_SCALE` / `/QTY_SCALE/` so the invariants stay tested, not vacuously green.
- **TICKET_SCALE triage honored:** the independent JS value mirrors (`const TICKET_SCALE = 100n`, `TICKET_SCALE_NUM`), the JS EV math (`scaled / TICKET_SCALE`), and the off-chain `futureTickets / TICKET_SCALE` derivation were left UNCHANGED; only `uint32(TICKET_SCALE)` contract-source-string forms became `uint32(QTY_SCALE)`.
- **481-scope UNTOUCHED:** event-field assertions (`ticketCount`/`futureTickets`/`TicketsQueued.quantity`/`TicketsBought.ticketQuantity`), the agent bet-input, and the degenerette harness-local `.t.sol` identifiers (`playerTicket`/`resultTicket`/`customTicket`/`_resultTicketForSpin`).

**Verify (all clean):**
- `! rg "traitBurnTicket|ticketsOwedPacked|_budgetToTicketUnits|TicketUnits|DecEntry|TerminalDecEntry|_decClaimableFromEntry|terminalDecEntries|_fullTicketPayout" test/` → empty
- `! rg "_queueTickets\b|_queueTicketsScaled\b|_queueTicketRange\b" test/` → empty
- `! rg "..._TICKETS_PER_LEVEL|VAULT_PERPETUAL_TICKETS" test/` → empty
- F1 (M-4): `! rg "\b(scaledTickets|countScaled)\b"` in `DegenerusGameJackpotModule.sol`/`DegenerusGameLootboxModule.sol` → empty; `wholeTicketsScaled` present in both; `_queueEntriesScaled` sink param is `entriesScaled`. (The only `contracts/` `scaledTickets` is the `JackpotBernoulliTester` param mirror — intentional.)

### Task 2 — full green-floor proof

| Gate | Result |
|------|--------|
| `npm test` (full Hardhat — the runtime by-name class) | **1362 passing, 0 failing, 19 pending** ✅ |
| `npm run test:stat` (Bernoulli/EV testers + invariants) | **164 passing, 7 failing, 17 pending** — INV-04 (rename-induced) FIXED; 7 carried pre-existing/non-rename |
| `npx hardhat compile` / `forge build` | exit 0 (the renamed `.t.sol` harnesses compile) |
| `forge test` (full) | **blocked by a foundry-1.6.0-nightly environmental flake — NOT the rename** (see below) |

The Bernoulli/EV testers (`JackpotTicketRollBernoulliEv` 16, `LootboxBernoulliEv` 8, `LootboxAutoResolveBernoulliEv` 13) pass with **EV math / samples / expected values UNCHANGED** — only the B-1 contract-source-string literals were synced. `LootboxBernoulliEv`/`LootboxAutoResolveBernoulliEv` required **zero** edits (no production-source assertions). The trailing `MODULE_NOT_FOUND` after both Hardhat runs is the known cosmetic mocha file-unloader bug (exit 0), documented in 479-02.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2/3 — missing critical functionality] DegeneretteV73Invariants INV-04 (rare degenerette source-string assertion not in the plan's named-file list)**
- **Found during:** Task 2 (`npm run test:stat`).
- **Issue:** `test/stat/DegeneretteV73Invariants.test.js` INV-04 byte-compares the current degenerette source against the v72 baseline (`git show 64ec993e^`). 480-01's `amountPerTicket`→`amountPerSpin` rename (RN-07) moved the current source away from the baseline, turning INV-04 red. It passed at the 479-close (`amountPerTicket` matched the baseline); 480-01 broke it. This is exactly the "rare test that asserts a renamed identifier as a contract SOURCE STRING" the plan said to sweep — it was simply not in the named-file list.
- **Fix:** `preV73Source()` now normalizes the single audited rename (`amountPerTicket`→`amountPerSpin`) into the historical baseline before the byte-compare. The logic-drift invariant is preserved (everything except the deliberate identifier rename still byte-compares); no EV/sample/value/logic edit. INV-01/02/03 already passed (no renamed identifier in those regions).
- **Files modified:** `test/stat/DegeneretteV73Invariants.test.js`
- **Commit:** `848a56fe`

## Carried pre-existing / non-rename failures (NOT 480 regressions)

`npm run test:stat` ends at **7 failing**, all confirmed present at the base HEAD `179dff99` independent of the rename and of this plan's edits:

1–5. **SurfaceRegression byte-layout guards** (the documented "5 SurfaceRegression failures") — guard `DegenerusTraitUtils.sol` / `EntropyLib.sol` byte-ranges vs frozen anchors. Those trait/entropy files are byte-identical to baseline and were untouched by 479/480. My edits to `SurfaceRegression.test.js` were comment/label-only (the `name:` reporting label; the `lo/hi` byte-ranges unchanged).
6. **PerPullEmptyBucketSkip STAT-03** ("empty-bucket skip rate ... over N>=50 lifecycle calls") — a behavior-driven simulation statistic. A pure rename cannot change it; my edit to that file was a single comment line.
7. **WholeFlipFloorInvariant [03a]** — pins `creditFlip(buyer, lootboxFlipCredit)` in `_purchaseForWithCached`. Verified ABSENT in the pre-480 contract (`git show cdd32fe9:...MintModule.sol`); the flip-credit path is batched (`flipAmounts[0] = lootboxFlipCredit`). Pre-existing, no rename involvement.

## Forge floor — environmental blocker (foundry 1.6.0-nightly), NOT the rename

The full `forge test` runs to `223 passed / 116 failed / 339 total` in ~1.2s. This is **not** a rename regression — it is the foundry-nightly issue the repo already documents in `foundry.toml:23-28` (the protocol constructor's day-arithmetic panicking 0x11) and works around in `AutoOpenCursorRing.t.sol` ("the Foundry block.timestamp caching workaround"). Diagnosis:

- The `-vvvvv` trace shows `setUp()` runs `vm.warp(86400)`, deploys **all 17 modules successfully**, then the **final genesis CREATE** (the `DegenerusGame` facade constructor) reverts `0x11`. Under **`forge 1.6.0-nightly`**, `vm.warp` does not propagate to that nested CREATE's constructor, so genesis sees the wrong timestamp and underflows. The repo's CI uses stable foundry via `foundry-toolchain@v1`.
- **Conclusive proof it is not the contract / the rename:** `npm test` (Hardhat) deploys the SAME post-480 contracts at the SAME fixed timestamp 86400 and plays the full game lifecycle — **1362 passing, 0 failing**. If genesis genuinely underflowed, Hardhat would fail at deploy.
- The forge-failing test files (`DeployProtocol.sol`, `ActivityScorePointFloor`, `AutoOpenCursorRing`, `Composition.inv`, `EthSolvency.inv`, etc.) are **byte-identical to the 479-close** (where `forge test` was 1003/0/107), and the 480-01 rename is byte-neutral (forge build green, layout byte-stable).
- Every forge suite **passes in isolation / small batches**; the failure only appears for full-game-deploy suites under this nightly.

**Recommendation (out of this rename's scope, owner/tooling call):** run `forge test` on the repo's expected stable foundry (`foundryup` to the `foundry-toolchain@v1` stable line, as CI does) to reproduce the 1003/0/107 floor. Logged to `deferred-items.md`.

## Self-Check: PASSED
- `848a56fe` (test sweep) — FOUND in `git log`.
- No-stale grep (storage/sink/const/dec/helper) under `test/` — empty.
- `deriveStorageSlot("lvlTraitEntry")` ×6 in `DeityPassGoldNerfRegression.test.js`; `entriesOwedPacked` in `LootboxAutoResolveRegression.test.js` (5) + `MintCleanupRegression.test.js` (6) — FOUND.
- `npm test` 1362/0; `npm run test:stat` 164/7 (INV-04 fixed) — confirmed.
- F1 production modules clean; the sole `contracts/` `scaledTickets` is the intentional BernoulliTester param mirror.
