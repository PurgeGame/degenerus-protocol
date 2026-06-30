# Roadmap — Milestone v75.0 — Ticket/Entry Correctness + Disambiguation

> **Subject (RESETS the audit subject — contract LOGIC change):** baseline = local HEAD `cdd32fe9` (clean `contracts/` tree; not pushed). Resets off v74.0 closure `MILESTONE_V74_AT_HEAD_93d17288…` (`contracts/` tree `f06b1ef6`). **Numbering continues 478 → 479.**
> **The defect:** `ticketsOwedPacked.owed` is in ENTRIES (4 per whole ticket, each worth price/4). Two prize legs queue a whole-ticket count (`amount/price`, no `<<2`) into the entries sink → ¼ delivery: `JackpotModule._jackpotTicketRoll` (~2143) + `LootboxModule._lootboxTicketCount` (~2188)→queue (~1383, also reached via `DecimatorModule:673`). USER-confirmed (matched live RTP sim). Conservation-safe; winners under-paid.
> **Posture:** three contract-touching phases (479/480/481) each ship as ONE batched `.sol` diff behind the contract-commit approval gate (the sole gates). All test/golden/ABI/docs/verify/re-audit work commits autonomously.
> **ABI decision (LOCKED):** rename misleading event fields + normalize emitted units to entries; KEEP view selectors (natspec-only). No live indexer decodes these events.
> **Threat weighting (locked):** DOMINANT RNG/freeze · HIGH gas-DoS in advanceGame (>16.7M = game-over) · SPINE solvency/backing · LOWER access/reentrancy/MEV.
> **Grounding:** finding memory `prize-ticket-legs-whole-vs-entries-2026-06-29`; discovery maps in `.planning/v75-grounding/`.

---

## Phase 479: CONV + VALUE-FIX (GATED contract diff #1 — behavior change)

**Goal:** Fix the ¼ under-delivery in both prize legs by routing them through one canonical whole-ticket→entries conversion, and document the ticket/entry convention so the bug class can't recur — without disturbing the Bernoulli round-up's EV-neutrality.

**Requirements:** CONV-01, CONV-02, FIX-01, FIX-02, FIX-03, FIX-04, FIX-05

**Success criteria:**
1. `_jackpotTicketRoll` and `_lootboxTicketCount`/`_resolveLootboxRoll` both queue `(amount<<2)/price` entries via the canonical helper; no award leg open-codes `amount/price` into the entries sink (the lootbox fix covers the decimator-recirc path).
2. The Bernoulli round-up stays on whole-ticket granularity (`×4` applied to the queued entries, not inside the Bernoulli expression); the grep-pinned Bernoulli line + EV testers are byte-identical/green.
3. A regression test proves owed-entries delivered == `(B<<2)/price` per award leg and uniform entries-per-ETH across purchase/daily/prize; `emit == queue` holds and the stale `CrossSurfaceTicketMixing` [03a]/[03b]/[03c] assertions are reconciled.
4. Convention NatSpec lands at `_queueTickets`, `ticketsOwedPacked`, and the canonical helper.
5. ONE batched `.sol` diff presented and approved before commit.

**Plans:** 2 plans
- [x] 479-01-PLAN.md — `wholeTicketsToEntries` helper + both queue-site value fixes + Jackpot emit==queue + convention NatSpec (ONE batched `.sol` diff, gated) — committed `b2ab3e9f`
- [x] 479-02-PLAN.md — deterministic forge regression (FIX-04) + `CrossSurfaceTicketMixing` reconciliation + emit==queue (FIX-05) — `33239b1d`/`d0718702`; +FIX-05 gap-closure of 7 missed structural-assertion suites `7844ee7f`

## Phase 480: RENAME-SWEEP (GATED contract diff #2 — no behavior change)

**Goal:** Make the ticket/entry distinction unmistakable in identifiers: rename the entries-denominated storage, sink functions, constants, and locals; resolve the Decimator "entry"=record collision; keep storage layout byte-stable.

**Requirements:** RN-01, RN-02, RN-03, RN-04, RN-05, RN-06, RN-07

**Success criteria:**
1. `traitBurnTicket`→`lvlTraitEntry`, `ticketsOwedPacked`→`entriesOwedPacked`, `_queueTickets*`→`_queueEntries*` (+params), `_budgetToTicketUnits`→`_budgetToEntries`, `*_TICKETS_PER_LEVEL`/`VAULT_PERPETUAL_TICKETS`→`*_ENTRIES_*` (values unchanged), and the misleading local `whole`-into-entries vars renamed — across all files incl. the 2 inline-asm `.slot` reads.
2. Decimator "entry" (burn record) → `record`/`burnRecord`; "entry" now means only the price/4 unit protocol-wide.
3. `forge inspect storageLayout` proves NO slot/offset/type move; all ~13 layout goldens recaptured (`--capture`) and `--check` green (label-only diff).
4. By-name test harnesses updated in lockstep (`DeityPassGoldNerfRegression` name string + `.t.sol` inheritors); full build green.
5. ONE batched `.sol` diff presented and approved before commit.

## Phase 481: EVENT-SURFACE + DOCS (GATED contract diff #3 — ABI field names)

**Goal:** Align the event surface with the entries convention — rename misleading event fields, normalize emitted units to entries — and update the tests, generated ABIs, and docs; keep external view selectors stable.

**Requirements:** EVT-01, EVT-02, EVT-03, EVT-04, EVT-05

**Success criteria:**
1. `JackpotTicketWin.ticketCount`→`entryCount`, `LootBoxOpened.futureTickets`→`futureEntries`, `TicketsQueued.quantity`→`entries`; every path emits entries consistently (BAF path no longer emits whole tickets on a shared field).
2. View selectors unchanged; `ticketsOwedView`/`sampleTraitTicketsAtLevel`/`getTickets`/`getPlayerPurchases` get natspec/return-var corrections only.
3. `EventSurfaceUnification` test updated and green; deployment ABIs regenerated; `docs/JACKPOT-EVENT-CATALOG.md` + `docs/JACKPOT-PAYOUT-REFERENCE.md` updated to the entries basis.
4. ONE batched `.sol` diff presented and approved before commit.

## Phase 482: VERIFY + CLOSE

**Goal:** Prove the fix lands the intended economy, the refactor is behavior-preserving, and close the milestone.

**Requirements:** VER-01, VER-02, VER-03, VER-04

**Success criteria:**
1. Full forge + Hardhat suite green (≥893/0 floor); layout golden `--check` green; Bernoulli EV testers green.
2. RTP re-sim confirms prize-leg ticket EV now lands at ~0.786× of budget (under-delivery resolved); before/after entries-per-roll recorded.
3. Cross-model adversarial re-audit of the v75.0 diff dispositioned clean; contracts git-verified after read-capable fan-outs.
4. `audit/FINDINGS-v75.0.md` (444) + closure `MILESTONE_V75_AT_HEAD_<sha>`; tag `v75.0`; archive `milestones/v75.0-{ROADMAP,REQUIREMENTS}.md`; PROJECT.md → SHIPPED; this file collapsed to the index.

---

## Prior Milestones (index)

> **Canonical milestone record = `.planning/milestones/` + git tags + `.planning/MILESTONES.md`.** This file holds the ACTIVE milestone's full roadmap above; on close it collapses to this index and the full roadmap moves to `milestones/v<X.Y>-ROADMAP.md`. Next milestone authors a fresh roadmap BY HAND (repo convention — gsd-sdk state mutators avoided).

- ✅ **v74.0 As-Built Milestone Audit + C4A Package** — Phases 466-478 (shipped 2026-06-27, tag `v74.0`) — 0 open findings
- ✅ **v73.0 Degenerette "Variant-2" Color-Gated Rescore** — Phases 452-456 (shipped 2026-06-21, tag `v73.0`)
- ✅ **v72.0 As-Built Audit — Foil Pack + Degenerette WWXRP-Rig** — (shipped 2026-06-21, tag `v72.0`)
- 📋 Earlier milestones — see `.planning/MILESTONES.md` + `.planning/milestones/`

<details>
<summary>✅ v74.0 As-Built Milestone Audit + C4A Package (Phases 466-478) — SHIPPED 2026-06-27</summary>

Full milestone audit of the `v73.0 → HEAD` contract batch (29 .sol, +1873/−1032) + complete C4A package. **0 open findings**; the sole conditional contract gate (475) fired once → 1 MEDIUM (DegenerusAdmin recovery-spanning VRF-swap proposal) owner-approved-fixed `93d17288`. Subject byte-frozen `contracts/` tree `f06b1ef6` @ `93d17288`; closure `MILESTONE_V74_AT_HEAD_93d17288…`.

- [x] Phase 466: SUBJECT-FREEZE-CONFIRM
- [x] Phase 467: HARNESS-GREEN-GATE (test-only)
- [x] Phase 468: AUDIT-SOLV-FOLD
- [x] Phase 469: AUDIT-RNG-LIVENESS
- [x] Phase 470: AUDIT-ACCESS-PERMISSIONLESS
- [x] Phase 471: AUDIT-EV-RTP
- [x] Phase 472: AUDIT-RENAME-WIRING-STORAGE
- [x] Phase 473: AUDIT-GAS-FAUCET
- [x] Phase 474: MANIFEST-REPOINT
- [x] Phase 475: CROSS-MODEL-REAUDIT (sole conditional contract gate — fired once, resolved)
- [x] Phase 476: AGENT-SOAK-REATTEST
- [x] Phase 477: C4A-PACKAGE
- [x] Phase 478: TERMINAL

Full roadmap + success criteria: `milestones/v74.0-ROADMAP.md`. Requirements: `milestones/v74.0-REQUIREMENTS.md`. Findings: `audit/FINDINGS-v74.0.md`. Phase execution record: `milestones/v74.0-phases/`.

</details>
