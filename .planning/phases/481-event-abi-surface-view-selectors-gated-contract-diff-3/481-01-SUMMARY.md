---
phase: 481-event-abi-surface-view-selectors-gated-contract-diff-3
plan: 01
subsystem: events-abi-surface
tags: [tickets, entries, abi, events, view-selectors, rename, gated-diff, no-behavior-change, fix-05]

# Dependency graph
requires:
  - phase: 480-01 (bcc47ccc) — internal ticket→entry identifier rename
  - phase: 480-02 (848a56fe) — test by-name sweep (1362 green floor)
provides:
  - "Public event/ABI surface aligned to the entries convention: 4 entry-accounting event NAMES renamed (Tickets*→Entries*, FullTicket*→Degenerette*), all misleading entry-count FIELDS renamed, 3 entries-returning view SELECTORS renamed"
  - "ABI-consumer sweep closed across test/ (25 files) + the off-chain agent runtime/oracle/manifest (4 files) + the canonical JackpotTicketWin doc shape"
  - "Mechanism event/selector NAMES + LootBoxOpened.futureTickets KEPT (topic0/selector-stable for the Ticket-Jackpot mechanism + the scaled-WHOLE field)"
affects: [482-degenerette-repack, 484-verify-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FIX-05 byte-baseline normalization: when a gated contract rename is intentionally uncommitted, a byte-identity-vs-HEAD (or vs a fixed historical ref) source guard is made tolerant of the AUDITED rename by normalizing the rename into the baseline before cmp — the guard still detects any OTHER drift (carries the 480-02 normalize480Rename precedent)"

key-files:
  created:
    - .planning/phases/481-event-abi-surface-view-selectors-gated-contract-diff-3/481-01-PLAN.md
    - .planning/phases/481-event-abi-surface-view-selectors-gated-contract-diff-3/481-01-SUMMARY.md
    - .planning/phases/481-event-abi-surface-view-selectors-gated-contract-diff-3/deferred-items.md
  modified:
    - "contracts/ (9 files, UNCOMMITTED — gated diff #3; captured to 481-CONTRACT-DIFF.patch)"
    - "test/ (25 files — event-NAME/selector/field by-name sweep + 3 FIX-05 byte-baseline normalizations)"
    - agent/src/actions.js
    - agent/src/oracle.js
    - agent/manifest/invariants.json
    - agent/manifest/MAIN-INVARIANTS.md
    - docs/JACKPOT-EVENT-CATALOG.md

key-decisions:
  - "JackpotTicketWin event NAME KEPT (mechanism), only its fields renamed (ticketCount→entryCount, ticketLevel→entryLevel, ticketIndex→entryIndex) — per task KEEP-set + ledger §10.1 mechanism-name principle. This DIVERGES from the ROADMAP §481 criterion-1 wording 'JackpotTicketWin→JackpotEntryWin' — FLAGGED for AM."
  - "Degenerette event NAMES renamed FullTicketResolved→DegeneretteResolved, FullTicketResult→DegeneretteResult (ledger §2B) — FLAGGED target-name choice for AM (alt: DegeneretteBetResolved/DegeneretteSpinResult)."
  - "FoilMatchClaimed.ticketIndex→foilSlotIndex (event FIELD only, in-scope). The feeding claimFoilMatch/claimFoilMatchMany params stay ticketIndex (selector-safe 480-internal GAP, out of strict 481 event-field scope) — FLAGGED for AM."
  - "JACKPOT-EVENT-CATALOG.md §B (JackpotTicketWin) updated to current ABI shape; the rest of both jackpot docs carry pre-existing structural staleness (ancient fa2b9c39 baseline, phantom fields/events, 480 storage names, 479 value-semantics) deferred to a 484 doc-reconciliation (D-481-DOCS-01)."

requirements-completed: [EVT-01, EVT-02, EVT-03, EVT-04, EVT-05, EVT-06]

# Metrics
duration: ~2.5h
completed: 2026-06-30
---

# Phase 481 / Plan 01: Event/ABI Surface + View Selectors + Docs Summary

**The public event + view surface was aligned to the `entries` convention shipped internally in Phase 480 — a pure ABI rename (event names / fields / 3 view-selector names), provably NOT a behavior change (67 insertions / 67 deletions, symmetric; no logic/value/ordering/emitted-value change) — with the by-name ABI-consumer hazard swept across test/ (25 files) AND the off-chain agent runtime/oracle/manifest (4 files), proven green end-to-end by the full Hardhat suite (1362 passing, 0 failing).**

## Rename map applied (derived from frozen post-480 source @ `39919230`)

### A. Event NAME renames (topic0 CHANGES) + their fields
| OLD event | NEW event | field renames |
|---|---|---|
| `TicketsQueued` | `EntriesQueued` | `quantity`→`entries` |
| `TicketsQueuedScaled` | `EntriesQueuedScaled` | `quantityScaled`→`entriesScaled` |
| `TicketsQueuedRange` | `EntriesQueuedRange` | `ticketsPerLevel`→`entriesPerLevel` |
| `TicketsBought` | `EntriesBought` | `ticketQuantity`→`entryQuantityScaled` (§10.6) |
| `FullTicketResolved` | `DegeneretteResolved` | `ticketCount`→`spinCount`, `resultTicket`→`resultTraits` |
| `FullTicketResult` | `DegeneretteResult` | `ticketIndex`→`spinIndex`, `playerTicket`→`playerTraits` |

### B. Event FIELD-only renames (NAME kept — mechanism/win events; topic0 UNCHANGED)
| event (NAME kept) | field renames |
|---|---|
| `JackpotTicketWin` (mechanism KEEP) | `ticketLevel`→`entryLevel`, `ticketCount`→`entryCount`, `ticketIndex`→`entryIndex` |
| `JackpotEthWin` | `ticketIndex`→`entryIndex` |
| `JackpotFlipWin` | `ticketIndex`→`entryIndex` |
| `LootBoxWhalePassJackpot` | `tickets`→`entriesPerLevel` |
| `FoilMatchClaimed` | `ticketIndex`→`foilSlotIndex` (NOT `entryIndex` — draw-slot 0-3) |

### C. View SELECTOR renames (interface + impl + caller lockstep)
| OLD | NEW | refs |
|---|---|---|
| `ticketsOwedView` | `entriesOwedView` | IDegenerusGame:115 (decl) + DegenerusGame:2088 (impl) + NatSpec |
| `sampleTraitTicketsAtLevel` | `sampleTraitEntriesAtLevel` | IDegenerusGame:327 + DegenerusGame:2429 (return `tickets`→`entries`) + DegenerusJackpots:389 (caller) |
| `getTickets` | `getEntries` | DegenerusGame:2510 (facade-only) |

### KEEP (verified intact)
`LootBoxOpened.futureTickets` (scaled-WHOLE, unit-correct); event NAMES `JackpotTicketWin`/`JackpotEthWin`/`JackpotFlipWin`/`LootBoxWhalePassJackpot`/`FoilMatchClaimed`/`LootBoxOpened`; mechanism selectors `processTicketBatch`/`processFutureTicketBatch`/`payDailyJackpotCoinAndTickets`/`initPerpetualTickets`/`sampleFarFutureTickets`/`getPlayerPurchases`; everything 480 shipped.

## Accomplishments

- **contracts/ (9 files, UNCOMMITTED):** event decls + emit-site names + NatSpec (A); event fields + NatSpec (B); view selectors + interface + caller + NatSpec (C). 3 in-module comment references to the renamed Degenerette events updated. `npx hardhat compile` exit 0; `forge build` exit 0 (harnesses compile with renamed event topics). Diff is **67/67 symmetric** = rename-only.
- **ABIs regenerated:** `deployments/localhost-abis/*.json` rebuilt from fresh artifacts (15 changed; gitignored build artifacts — confirmed reflecting the new event/selector names). No tracked ABI JSON exists under `deployments/`.
- **test/ ABI-consumer sweep (25 files):** event-NAME/selector string literals (incl. keccak topic `EntriesBought(address,uint256,uint256)`, `iface.getEvent("DegeneretteResult")`, `.includes("emit EntriesQueued(")`, source-string assertions) + the one runtime field consumer `JackpotFlipWin.entryIndex` (`PerPullLevelDistribution.test.js`). Degenerette `.t.sol` harness-LOCALS (`resultTicket`/`playerTicket`/`_resultTicketForSpin`) left untouched (test-internal reel derivation, not ABI consumers — per 480-02).
- **Off-chain agent (4 files — the runtime by-name hazard NOT covered by npm test):** `agent/src/actions.js` (`iface.getEvent("DegeneretteResult")`, `a.playerTraits`/`a.spinIndex` field reads, method `_decodeDegeneretteResults`); `agent/src/oracle.js` (`game.entriesOwedView(...)` selector call + payload doc); `agent/manifest/invariants.json` + `MAIN-INVARIANTS.md` (oracle recipe selector/event/field tokens — JSON re-validated).
- **docs:** `JACKPOT-EVENT-CATALOG.md` §B `JackpotTicketWin` updated to the current ABI shape (entries field labels + `traitId uint16` + 7th `roundedUp` field).

## Verification

| Gate | Result |
|------|--------|
| `npx hardhat compile` | exit 0 |
| `forge build` | exit 0 (renamed `.t.sol` topics/selectors compile) |
| `npm test` (full Hardhat — the runtime by-name gate) | **1362 passing, 0 failing, 19 pending** ✅ (== 480-02 floor) |
| `forge test --match-contract TicketRouting` (non-deploy, exercises renamed `_queueEntriesScaled`) | **12 passed, 0 failed** ✅ |
| `test/stat` touched files (`PerPullLevelDistribution` + `DegeneretteProducerChi2`) | **13 passing, 0 failing, 1 pending** (pending = pre-existing soft-skip) |
| no-stale grep (event names + selectors) under contracts/ + test/ + agent/ | clean |
| KEEP-set (`futureTickets`, mechanism names/selectors) | intact |

**Full-protocol-deploy `forge test` suites (EthInEvents, TicketQueue.inv, Degenerette*) fail at `setUp()` with `panic 0x11`** — the documented foundry-1.6.0-nightly `vm.warp`/genesis-underflow flake (carried from 480-02), NOT a rename regression. The same post-481 contracts deploy + play the full lifecycle under Hardhat (1362/0). Reproduce the forge floor on stable foundry/CI.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — FIX-05 source-baseline guards] 3 byte/signature-baseline tests pinned the contracts to a pre-481 state**
- **Found during:** `npm test` (the catching signal). 3 failing: `LootboxAutoResolveMintBoostRegression [03a]/[03b]` (cmp MintModule/Storage vs committed `HEAD`) + `CrossSurfaceTicketMixing [03d]` (`JackpotTicketWin` event-def vs fixed pre-278 ref).
- **Root cause:** byte/signature-identity guards. `[03a]/[03b]` use `BASELINE="HEAD"` and report the (intentional, gated-uncommitted) 481 drift; `[03d]` pins the `JackpotTicketWin` field labels to `8a81a87c~1`.
- **Fix:** normalized the AUDITED 481 rename into each guard's baseline before comparison (the 480-02 `normalize480Rename` precedent) — `[03a]` token-normalizes `TicketsBought→EntriesBought`/`ticketQuantity→entryQuantityScaled`; `[03b]` normalizes the 3 queue-event names + fields + 3 NatSpec phrases; `[03d]` normalizes the JackpotTicketWin field labels. Each guard STILL detects any OTHER drift; post-commit-safe (renames become no-ops once HEAD includes 481).
- **Files modified:** `test/unit/LootboxAutoResolveMintBoostRegression.test.js`, `test/integration/CrossSurfaceTicketMixing.test.js`
- **Verify:** all 3 → green; 0 new failures.

### Auth gates
None.

## FLAGS for AM review (naming/judgment calls — renames are cheap to adjust)

1. **`JackpotTicketWin` NAME kept** (only fields renamed) — per the task KEEP-set ("the event NAME is the mechanism") + ledger §10.1 (KEEP mechanism names). This **diverges from the ROADMAP §481 criterion-1 wording `JackpotTicketWin→JackpotEntryWin`**. If AM prefers the full name rename, it's a one-line decl + 2 emit-site + topic0 change (and a `JackpotEntryWin` test-name sweep).
2. **Degenerette event target names** — `FullTicketResolved→DegeneretteResolved`, `FullTicketResult→DegeneretteResult` (ledger §2B). Consistent-form alternatives: `DegeneretteBetResolved` / `DegeneretteSpinResult`. These interplay with Phase 482's `_packFullTicketBet→_packDegeneretteBet` repack.
3. **FoilPack `claimFoilMatch`/`claimFoilMatchMany` params** `ticketIndex`/`ticketIndexes` (+ `_tryClaimFoilMatch`, the `NoClaimableMatch` comment) remain `ticketIndex` — they feed the now-`foilSlotIndex` event field. Selector-safe 480-internal GAP, left out of the strict 481 event-field scope. Rename to `foilSlotIndex*` in a follow-up for full consistency if AM wants.
4. **Docs (D-481-DOCS-01):** both jackpot docs carry pre-existing structural staleness beyond the rename (deferred to 484 — see `deferred-items.md`).

## Gated-diff handoff
- **contracts/ left UNCOMMITTED** (9 files). Patch: `…/scratchpad/overnight-481-483/patches/481-CONTRACT-DIFF.patch` (399 lines, 67/67 symmetric).
- `ContractAddresses.sol` restored to HEAD (compile-regen artifact, not part of the rename).
- Commit-guard + `.git/hooks/pre-commit` untouched; STATE.md / ROADMAP.md untouched.
