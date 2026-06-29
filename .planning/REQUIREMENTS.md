# Requirements — Milestone v75.0 — Ticket/Entry Correctness + Disambiguation

**Defined:** 2026-06-29
**Core Value:** Prize legs deliver the intended ticket value, and the "ticket (whole unit = `priceForLevel`) vs entry (= price/4, 1 NFT, 4 entries per ticket)" distinction is unmistakable in code so this bug class cannot recur.

> **Subject (RESETS the audit subject — contract LOGIC change):** baseline = local HEAD `cdd32fe9` (clean `contracts/` tree; `main`, not pushed; push stays separately gated). Resets off the v74.0 closure `MILESTONE_V74_AT_HEAD_93d17288…` (`contracts/` tree `f06b1ef6`). **Numbering continues 478 → 479.**
> **Origin:** cross-contract council finding (Workflow `wf_1a689688`, re-verified end-to-end against source + discovery `wf_701237c0`). The under-delivery matched the live RTP sim — USER-confirmed real.
> **The defect (verified two ways):** `ticketsOwedPacked.owed` is denominated in ENTRIES (1 NFT = 1 entry = price/4; 4 entries = 1 whole ticket). EXACTLY TWO prize legs queue a WHOLE-TICKET count (`amount/price`, no `<<2`) into the entries sink → ¼ of the ETH-warranted value: `JackpotModule._jackpotTicketRoll` (~2143) and `LootboxModule._lootboxTicketCount` (~2188)→queue (~1383). The lootbox site is also reached via `DecimatorModule:673 resolveLootboxDirect` — one fix covers both. Conservation-safe (the undelivered ¾ stays in the pool, over-collateralized, RTP-suppressing); no attacker gain — winners under-paid.
> **By-design (do NOT change values — USER-confirmed intentionally entries; rename-only):** `WHALE_BONUS_TICKETS_PER_LEVEL`(40), `WHALE_STANDARD_TICKETS_PER_LEVEL`(2), `LAZY_PASS_TICKETS_PER_LEVEL`(4), `VAULT_PERPETUAL_TICKETS`/genesis `16`. Correct entries legs (leave logic): `_budgetToTicketUnits` paths, normal purchase, far-future swap, `WhaleModule:469`.
> **Threat weighting (locked):** DOMINANT RNG/freeze · HIGH gas-DoS in advanceGame (>16.7M = game-over) · SPINE solvency/backing · LOWER access/reentrancy/MEV. This finding is a **value-correctness** item (winners under-paid; conservation holds).
> **Posture:** contract LOGIC change. Three contract-touching phases (479 fix, 480 rename, 481 events) each ship as ONE batched `.sol` diff behind the standard contract-commit approval gate (the sole gates). All test / golden / ABI-regen / docs / verify / re-audit work commits autonomously.
> **ABI decision (LOCKED, USER):** "events too" — rename misleading event fields + normalize emitted units to entries; KEEP external view selectors (natspec/return-var fixes only, no selector churn). No live indexer/subgraph decodes these events (the in-repo agent uses `ticketCount` only as a Degenerette bet-input param).
> **Grounding:** finding memory `prize-ticket-legs-whole-vs-entries-2026-06-29`; discovery maps in `.planning/v75-grounding/` (correctness sites + naming map + blast radius).

---

## v1 Requirements

Requirements for v75.0. Each maps to exactly one roadmap phase (479–482).

### CONV — convention lock + canonical conversion (Phase 479)

- [ ] **CONV-01**: A single canonical whole-ticket→entries conversion is the only way an award leg produces entries from a budget. Both prize legs route their queued count through the established `(budget<<2)/price` entries basis (`_budgetToTicketUnits`) or an explicit `wholeTicketsToEntries(x) = x << 2` helper — no award leg open-codes `amount/price` into the entries sink.
- [ ] **CONV-02**: The convention is documented in NatSpec at the entries sink (`_queueTickets`), the ledger (`ticketsOwedPacked`), and the canonical helper: **ticket** = whole unit (`priceForLevel(level)`); **entry** = price/4 (1 owed unit, 1 minted NFT, 4 entries per ticket). The two unit domains are unmistakable at every call site.

### FIX — prize-leg under-delivery (Phase 479)

- [ ] **FIX-01**: `_jackpotTicketRoll` queues the entries basis (`(amount<<2)/price`), restoring full-value BAF / per-winner ticket prizes (≈4× the pre-fix entries for a given `amount`).
- [ ] **FIX-02**: `_lootboxTicketCount` / `_resolveLootboxRoll` queue the entries basis — fixing the normal lootbox AND the decimator-recirc (`resolveLootboxDirect`) path in the one shared site.
- [ ] **FIX-03**: The Bernoulli round-up stays on whole-ticket granularity — the `×4` is applied to the queued entries, NOT inside the Bernoulli expression — so the EV-neutrality identity `E[whole]·100 == scaled` and the grep-pinned Bernoulli line stay byte-identical (the existing Bernoulli EV testers stay green unchanged).
- [ ] **FIX-04**: A regression test pins, per award leg, that the owed-entries delivered for a budget `B` equals `(B<<2)/price` (≈4× the pre-fix value, minus at most one sub-ticket from the round-up) and that entries-per-ETH is uniform across the purchase / daily / prize legs.
- [ ] **FIX-05**: `emit == queue` holds post-fix; the pre-existing failing `CrossSurfaceTicketMixing` assertions [03a]/[03b] (stale since `58556895` merged 3 emit sites → 2) and the [03c] emit==queue equality are reconciled to the entries semantics.

### RN — internal rename sweep, no behavior change (Phase 480)

- [ ] **RN-01**: `traitBurnTicket` → `lvlTraitEntry` across all referencing contract files including the 2 inline-asm `.slot` reads (`FoilPackModule:782`, `MintModule:569`) and NatSpec; storage layout proven unchanged (slot order/type identical) and all ~13 layout goldens recaptured via `storage_layout_oracle.sh --capture` (label-only change), `--check` green.
- [ ] **RN-02**: `ticketsOwedPacked` → `entriesOwedPacked` (all refs); NatSpec states the field is denominated in entries.
- [ ] **RN-03**: `_queueTickets` / `_queueTicketsScaled` / `_queueTicketRange` → `_queueEntries` / `_queueEntriesScaled` / `_queueEntryRange`, with params (`quantity`→`entries`, `quantityScaled`→`entriesScaled`, `ticketsPerLevel`→`entriesPerLevel`) and the misleading "Queues whole tickets" NatSpec corrected.
- [ ] **RN-04**: `WHALE_BONUS_TICKETS_PER_LEVEL` / `WHALE_STANDARD_TICKETS_PER_LEVEL` / `LAZY_PASS_TICKETS_PER_LEVEL` / `VAULT_PERPETUAL_TICKETS` → `*_ENTRIES_*` (values UNCHANGED — confirmed intentionally entries); the genesis literal `16` comment corrected to "16 entries (= 4 whole tickets) per level".
- [ ] **RN-05**: Misleading local `whole`-into-entries variables and the `*TicketUnits` locals renamed to reflect entries; `_budgetToTicketUnits` → `_budgetToEntries` (the canonical helper from CONV-01).
- [ ] **RN-06**: Decimator terminology collision resolved — its "entry" (a player burn RECORD, not the price/4 unit) renamed to `record`/`burnRecord` so "entry" is reserved protocol-wide for the ticket sub-unit. Values/logic unchanged.
- [ ] **RN-07**: By-name test harnesses updated in lockstep: `DeityPassGoldNerfRegression` `deriveStorageSlot("traitBurnTicket")` name string; the `.t.sol` inheritors `JackpotSingleCallCorrectness.t.sol` + `AdvanceGasCeiling.sol` (compile-break on rename); slot-8 hardcoders' comments refreshed (no runtime change).

### EVT — event / view surface + docs (Phase 481)

- [ ] **EVT-01**: Event fields renamed to entries semantics — `JackpotTicketWin.ticketCount` → `entryCount`, `LootBoxOpened.futureTickets` → `futureEntries`, `TicketsQueued.quantity` → `entries` — and emitted values normalized so every path emits entries consistently (the BAF path previously emitted whole tickets on a field whose trait paths emitted entries).
- [ ] **EVT-02**: `test/unit/EventSurfaceUnification.test.js` updated to the new field names / units; the event-shape pins pass.
- [ ] **EVT-03**: Deployment ABIs regenerated (`deployments/testnet-abis/*.json`, `deployments/localhost-abis/*.json`) for the modules whose events changed.
- [ ] **EVT-04**: External view selectors KEPT (no churn) — `ticketsOwedView`, `sampleTraitTicketsAtLevel`, `getTickets`, `getPlayerPurchases` get NatSpec / return-variable corrections only (return values documented as entries).
- [ ] **EVT-05**: Docs updated to the entries basis + current event shape — `docs/JACKPOT-EVENT-CATALOG.md`, `docs/JACKPOT-PAYOUT-REFERENCE.md`; the agent's `ticketCount` Degenerette bet-input param noted as unrelated (no change).

### VER — verification + closure (Phase 482)

- [ ] **VER-01**: Full `forge` + Hardhat suite green (target the established ≥893/0 floor); the layout golden `--check` green after recapture; the Bernoulli EV testers green (unchanged).
- [ ] **VER-02**: An RTP re-sim confirms the prize-leg ticket EV now lands at the intended ~0.786× of the ticket budget (the under-delivery that matched the prior live sim is resolved); a before/after entries-per-roll comparison is recorded.
- [ ] **VER-03**: Cross-model adversarial re-audit of the v75.0 diff (Codex primary; Gemini if available — re-check liveness) — every candidate dispositioned; contracts git-verified after any read-capable fan-out.
- [ ] **VER-04**: `audit/FINDINGS-v75.0.md` (chmod 444) + closure baseline `MILESTONE_V75_AT_HEAD_<sha>`; tag `v75.0`; archive `milestones/v75.0-{ROADMAP,REQUIREMENTS}.md`; PROJECT.md evolved to SHIPPED; ROADMAP.md collapsed to the index.

## Future Requirements (deferred)

- None identified. (External view-selector renames `ticketsOwedView`→`entriesOwedView` etc. were explicitly deferred — selector churn not worth it; natspec-only fix in EVT-04.)

## Out of Scope (explicit exclusions)

- **Re-calibrating the ~0.786× ticket variance EV** — the variance tiers are intended; v75.0 only restores the entries basis so the realized EV matches the documented one. NOT a re-tune.
- **Whale/perpetual entry VALUES** — confirmed intentionally entries; rename-only, no `×4`.
- **External view selector changes** — kept for off-chain compatibility (natspec/return-var only).
- **The `_queueTicketsScaled` purchase basis / `_budgetToTicketUnits` legs / far-future swap** — already correct; not touched beyond the rename.
- **Any new game feature** — this is a correctness + disambiguation milestone only.

## Traceability

| REQ | Phase | Status |
|-----|-------|--------|
| CONV-01, CONV-02 | 479 | pending |
| FIX-01 … FIX-05 | 479 | pending |
| RN-01 … RN-07 | 480 | pending |
| EVT-01 … EVT-05 | 481 | pending |
| VER-01 … VER-04 | 482 | pending |
