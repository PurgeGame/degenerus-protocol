# Phase 481 — Deferred items (out of the ABI-rename scope)

## D-481-DOCS-01 — JACKPOT-EVENT-CATALOG.md / JACKPOT-PAYOUT-REFERENCE.md full reconciliation

The two jackpot docs carry **pre-existing structural staleness that predates 481** and spans multiple phases — a focused 481 label-rename cannot make them fully correct without a dedicated doc-audit:

- `docs/JACKPOT-EVENT-CATALOG.md` header says **"Last verified against commit `fa2b9c39`"** (many phases stale). Concrete drift vs the frozen contract:
  - `JackpotEthWin` documented with **7 fields incl. phantom `rebuyLevel`/`rebuyTickets`**; the contract event has **5 fields** (`winner, level, traitId, amount, entryIndex`).
  - `traitId` documented `uint8`; contract is **`uint16`** (sentinels ≥256).
  - `JackpotBurnieWin` section documents an event that **does not exist** in the current contract (the real third event is `JackpotFlipWin`).
  - Emit-site line numbers are stale (the contract has drifted +many lines).
- `docs/JACKPOT-PAYOUT-REFERENCE.md` carries the **480-era storage name `traitBurnTicket`** (renamed `lvlTraitEntry` in 480-01) and **whole-ticket-vs-entries value-semantics prose** (e.g. `ticketCount = (totalBudget/100)/priceForLevel(...)` computes WHOLE tickets; post-479 the award is entries = ×4) that needs a 479-entries-basis value review, not a label swap.

**Done in 481:** `JACKPOT-EVENT-CATALOG.md` §B `JackpotTicketWin` updated to the current ABI shape (entries field labels `entryLevel`/`entryCount`/`entryIndex`, `traitId uint16`, added 7th `roundedUp` field, entries-basis descriptions).

**Deferred:** a full catalog/payout-reference reconciliation (correct `JackpotEthWin`/`JackpotFlipWin` field sets + types, drop the phantom `JackpotBurnieWin`, refresh line numbers, 480 storage names, 479 entries value-semantics, re-pin "Last verified"). Belongs in the Phase 484 verify/close doc pass (ledger F2). Not a behavior or ABI change.
