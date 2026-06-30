# Overnight run — Phases 481 / 482 / 483 (morning review brief)

**Date:** 2026-06-30 (overnight, autonomous) · **Owner directive:** run the remaining v75 change phases in sequence UNCOMMITTED; approve in the morning.

## TL;DR
All three remaining change phases are **done, verified, and captured as separate reviewable patches** — **nothing is committed to `contracts/`**. The working tree holds 481+482+483 stacked (12 contract files dirty). Review the three patches, settle the naming flags below, and we commit one gated phase at a time.

**Verification floor (the whole stacked tree):** full `forge test` **1005 / 0 / 107** (1003 milestone floor + 2 new FF tests) · `npm test` **1362 / 0**. Phases 479+480 already committed (`bcc47ccc` etc.).

## The three diffs to review

| Phase | Patch (in `scratchpad/overnight-481-483/patches/`) | Size | What it is | Verified |
|---|---|---|---|---|
| **481** EVENT/ABI + view selectors | `481-CONTRACT-DIFF.patch` | 399 ln, 9 files, 67/67 | FULL event-name rename (`Tickets*→Entries*`, `FullTicket*→Degenerette*`), misleading event fields, 3 view selectors (`getTickets→getEntries`, `ticketsOwedView→entriesOwedView`, `sampleTraitTicketsAtLevel→sampleTraitEntriesAtLevel`). KEEP `futureTickets` + mechanism names. | full forge + npm test + degenerette suites |
| **482** DEGENERETTE repack | `482-CONTRACT-DIFF.patch` | 209 ln, 3 files | Strip dead Full-Ticket mode (mode/isRandom/hasCustom bits), repack `degeneretteBets`, `FT_*_SHIFT→DEGEN_*_SHIFT`, `_packFullTicketBet→_packDegeneretteBet`. **EV byte-identical** (65/65 lines); dead-mode **proven** (the `packed==0` sentinel now carried by `spinCount≥1`). No slot move. | EV-identical + mutation-kills 7/0 + full forge |
| **483** FF-salvage granularity | `483-CONTRACT-DIFF.patch` | 291 ln, 6 files | Entry-granular far-future salvage via the 5-site coupled change (the `×4` cancelled by site 2's `/4` — byte-identical at whole-ticket-aligned points); `sellFarFutureTickets→sellFarFutureEntries`. **Intended** new value: sub-whole-ticket salvage now possible; floor drops whole-ticket→one entry. | new sub-whole-ticket + no-regression cases + full forge |

To view a patch: `git apply --stat <patch>` or just open it. The working tree already has all three applied cumulatively, so `git diff contracts/` shows 481+482+483 together; the per-phase patches isolate each.

## ⚠ The big overnight finding — the "foundry flake" was fictional
Three executors (480-02, 481, 482) repeatedly blamed forge failures on a "foundry-1.6.0-nightly `vm.warp` setUp flake" and waved them away. **It does not exist.** The real cause: 481 renamed the degenerette events (`FullTicketResult→DegeneretteResult`), changing their topic0, but **6 forge test files held hardcoded `FULL_TICKET_RESULT_SIG`/`FULL_TICKET_RESOLVED_SIG` topic constants** the name-grep couldn't catch (the old name isn't a string in the file). I diagnosed it from the revert trace, replaced the stale hex with self-documenting `keccak256("Degenerette*(...)")`, and the **full forge suite went green at 1003/0/107** — which none of the executors achieved. Fix committed: `6510a4b7`. **Lesson for the commit phase:** trust the suites, not the "flake" claims; I re-verified everything independently.

## 🟡 Naming flags needing your call (cheap to adjust before commit)
1. **`JackpotTicketWin` event NAME kept** (only its fields → `entryLevel`/`entryCount`/`entryIndex`). This **diverges from the ROADMAP §481 criterion-1 wording `JackpotTicketWin→JackpotEntryWin`** — I treated it as a "Ticket Jackpot" *mechanism* name (consistent with 480's KEEP of the mechanism cluster). **Your call:** keep the name (mechanism) or do the full `→JackpotEntryWin` (1 decl + 2 emit + topic0 change).
2. **Degenerette event target names:** `FullTicketResolved→DegeneretteResolved`, `FullTicketResult→DegeneretteResult`. Alternatives: `DegeneretteBetResolved`/`DegeneretteSpinResult`.
3. **FoilPack `claimFoilMatch`/`claimFoilMatchMany` params** `ticketIndex`/`ticketIndexes` left as-is while the event field became `foilSlotIndex` — rename the feeding params too for full consistency, if you want.
4. **Jackpot docs (D-481-DOCS-01):** the two jackpot docs carry pre-existing structural staleness beyond the rename — deferred to the Phase 484 doc pass.

## How to commit in the morning (one gated phase at a time)
For each approved phase: `mv .git/hooks/pre-commit` aside, stage that phase's contract files, `CONTRACTS_COMMIT_APPROVED=1 git commit -F <msg>`, `mv` the hook back. (Because they're stacked, committing 481 then 482 then 483 in order gives three clean commits; or, if you want each as an isolated diff on top of HEAD, we apply them sequentially.) I'll drive this once you've reviewed + settled the flags.

## Test/doc commits already on `main` (no contracts)
481: `046dd24b`,`934a7583` · sig-fix: `6510a4b7` · 482: `27c113c4`,`2da18e6c` · 483: `7d2c3a43`,`0e31e50d`. Plans + summaries under each `.planning/phases/48{1,2,3}-*/`.
