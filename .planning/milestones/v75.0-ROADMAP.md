# Roadmap — Milestone v75.0 — Ticket/Entry Correctness + Disambiguation

> **Subject (RESETS the audit subject — contract LOGIC change):** baseline = local HEAD `cdd32fe9` (clean `contracts/` tree; not pushed). Resets off v74.0 closure `MILESTONE_V74_AT_HEAD_93d17288…` (`contracts/` tree `f06b1ef6`). **Numbering continues 478 → 479.**
> **The defect (FIXED in 479):** `ticketsOwedPacked.owed` is in ENTRIES (4 per whole ticket, each worth price/4). Two prize legs queued a whole-ticket count (`amount/price`, no `<<2`) into the entries sink → ¼ delivery: `JackpotModule._jackpotTicketRoll` (~2143) + `LootboxModule._lootboxTicketCount` (~2188)→queue (~1383, also reached via `DecimatorModule:673`). USER-confirmed (matched live RTP sim). Conservation-safe; winners under-paid. Fixed `b2ab3e9f` (canonical `wholeTicketsToEntries(w)=w<<2`).
> **Posture:** FOUR remaining contract-touching phases (480/481/482/483) each ship as ONE batched `.sol` diff behind the contract-commit approval gate (the sole gates). All test/golden/ABI/docs/verify/re-audit work commits autonomously.
> **ABI decision (LOCKED):** rename misleading event names/fields + normalize emitted units to entries (481); RENAME the 3 entries-returning view selectors; KEEP mechanism selectors. No live indexer decodes these events.
> **Threat weighting (locked):** DOMINANT RNG/freeze · HIGH gas-DoS in advanceGame (>16.7M = game-over) · SPINE solvency/backing · LOWER access/reentrancy/MEV.
> **Binding scope:** `.planning/v75-grounding/v75.0-ticket-entry-disambiguation-ledger.md` **§10** (owner decisions applied; governing principle §10.1: rename only entry-COUNT/VALUE holders; KEEP mechanism/subsystem names). Finding memory `prize-ticket-legs-whole-vs-entries-2026-06-29`.

---

## Phase 479: CONV + VALUE-FIX (GATED contract diff #1 — behavior change) — ✅ COMPLETE

**Goal:** Fix the ¼ under-delivery in both prize legs by routing them through one canonical whole-ticket→entries conversion, and document the ticket/entry convention so the bug class can't recur — without disturbing the Bernoulli round-up's EV-neutrality.

**Requirements:** CONV-01, CONV-02, FIX-01, FIX-02, FIX-03, FIX-04, FIX-05

**Success criteria (all met):**
1. `_jackpotTicketRoll` and `_lootboxTicketCount`/`_resolveLootboxRoll` both queue `(amount<<2)/price` entries via the canonical helper; no award leg open-codes `amount/price` (the lootbox fix covers the decimator-recirc path).
2. The Bernoulli round-up stays on whole-ticket granularity (`×4` applied to the queued entries, not inside the Bernoulli expression); the grep-pinned Bernoulli line + EV testers byte-identical/green.
3. A regression test proves owed-entries == `(B<<2)/price` per award leg and uniform entries-per-ETH; `emit == queue` holds; the stale `CrossSurfaceTicketMixing` assertions reconciled (incl. the 7 missed hardhat suites).
4. Convention NatSpec lands at `_queueTickets`, `ticketsOwedPacked`, and the canonical helper.

**Plans:** 2 plans
- [x] 479-01-PLAN.md — `wholeTicketsToEntries` helper + both queue-site value fixes + Jackpot emit==queue + convention NatSpec (ONE batched `.sol` diff, gated) — committed `b2ab3e9f`
- [x] 479-02-PLAN.md — deterministic forge regression (FIX-04) + `CrossSurfaceTicketMixing` reconciliation + emit==queue (FIX-05) — `33239b1d`/`d0718702`/`a8629448`; +FIX-05 gap-closure of 7 missed structural-assertion suites `7844ee7f`

## Phase 480: RENAME-SWEEP (GATED contract diff #2 — no behavior change)

**Goal:** Make the ticket/entry distinction unmistakable in identifiers: rename every entry-COUNT/VALUE holder (storage, sink functions + params, constants, helper, locals, the Decimator burn-BET set, the Degenerette ticket-relics, and `ticketQuantity`=scaled-entries) per the ledger §10 binding scope; KEEP mechanism/subsystem/leg names; keep storage layout byte-stable; land the comment-only F2/F3/F5 + NFT-scrub doc fixes.

**Requirements:** RN-01 … RN-10

**Success criteria:**
1. The full §10 rename lands: `traitBurnTicket`→`lvlTraitEntry`, `ticketsOwedPacked`→`entriesOwedPacked`, `_queueTickets*`→`_queueEntries*` (+params incl. the `_activate10LevelPass` param), the four `*_TICKETS_PER_LEVEL` constants (incl. the lootbox mirror `WHALE_PASS_TICKETS_PER_LEVEL`) + `VAULT_PERPETUAL_TICKETS`→`*_ENTRIES_*` (values unchanged), `_budgetToTicketUnits`→`_budgetToEntries` + the entries locals (+ `bonusEntries`/`standardEntries`), the F1-scoped bug-site `wholeTicketsScaled` disambiguation, the Decimator `DecBet`/`dec`-prefixed bet set, the Degenerette `amountPerSpin`/`spinCount`/`customTraits`/`*Traits`/`_degenerettePayout` (+ Vault/interface lockstep), and `ticketQuantity`→`entryQuantityScaled` (67 param/local refs; the `TicketsBought` event field stays for 481) — across all files incl. the 2 inline-asm `.slot` reads.
2. KEEP-set survives: the activation-queue cluster, the Jackpot "Ticket Jackpot" mechanism names, `AFKING_TICKET_SCALE`, the whole-ticket-leg wei/level labels, the "External Entry Points" comments, every event field/name (481), and the mechanism selectors. `TICKET_SCALE`→`QTY_SCALE` (owner-chosen unit-neutral 2026-06-29 — NOT `ENTRY_SCALE`; the two `*BernoulliTester.sol` mirrors follow with Bernoulli math byte-identical).
3. Comment-only F2/F3/F5 NatSpec fixes + the NFT scrub (4 Storage refs + grounding docs) land here; no behavior change.
4. `forge inspect storageLayout` proves NO slot/offset/type move; all ~25 layout goldens recaptured (`--capture`) — the ~13 Storage-touching change label/typeLabel name strings only, the 12 standalone byte-identical — and `--check` green.
5. By-name test harnesses updated in lockstep — the compile-break Solidity set (`forge build` green) AND the runtime by-name `.test.js` source-string class (the FIX-05 forge-invisible trap); full Hardhat/forge/stat green at/above the 479-close floor, Bernoulli/EV testers UNCHANGED.
6. ONE batched `.sol` diff presented and approved before commit.

**Plans:** 2 plans
- [x] 480-01-PLAN.md — Gated contract rename sweep (RN-01…RN-09) + RN-10 compile-break/golden half across all `contracts/*.sol` + lockstep compile-break Solidity harness (`forge build` green) + layout golden recapture (label/typeLabel-only, `--check` green) — ONE batched gated diff (Wave 1, autonomous:false) ✅ `bcc47ccc` (contract diff, USER-approved) + `6e181d37` (harness/goldens/scrub); 502/502 rename-only; cross-model council reviewed (`480-COUNCIL-REVIEW.md`)
- [x] 480-02-PLAN.md — Runtime by-name `test/` literal sweep (the FIX-05 forge-invisible trap, RN-10) + full Hardhat/forge/stat green floor proving no behavior change (Wave 2, autonomous) ✅ `848a56fe`+`53716830`; `npm test` 1362/0, EV testers UNCHANGED; 35 test/ files swept. NOTE: full `forge test` blocked by a foundry-1.6.0-nightly `vm.warp` setUp flake (environmental, NOT the rename — suites pass in isolation; reproduce 1003/0/107 on stable foundry/CI). **Phase 480 ✅ COMPLETE.**

## Phase 481: EVENT/ABI SURFACE + VIEW SELECTORS + DOCS (GATED contract diff #3 — ABI)

**Goal:** Align the event + view surface with the entries convention — rename misleading event names/fields, normalize emitted units to entries, rename the three entries-returning view selectors — and update the tests, generated ABIs, and docs; keep mechanism selectors and `futureTickets` stable.

**Requirements:** EVT-01 … EVT-06

**Success criteria:**
1. The three queue events → `Entries*` (+fields); `JackpotTicketWin`→`JackpotEntryWin` (+fields), `JackpotEthWin`/`JackpotFlipWin.ticketIndex`→`entryIndex`, `LootBoxWhalePassJackpot.tickets`→`entriesPerLevel` (event field only — the WHALE_PASS constant renamed in 480), `FoilMatchClaimed.ticketIndex`→`foilSlotIndex` (NOT `entryIndex`); Degenerette `FullTicket*`→`Degenerette*` (+fields); `TicketsBought.ticketQuantity`→`entryQuantityScaled` (+ event-name owner decision).
2. Entries-returning view selectors renamed (`ticketsOwedView`→`entriesOwedView`, `sampleTraitTicketsAtLevel`→`sampleTraitEntriesAtLevel`, `getTickets`→`getEntries`) interface+impl+caller lockstep; mechanism selectors + `LootBoxOpened.futureTickets` KEPT.
3. `EventSurfaceUnification` test updated and green; the FIX-05 forge-invisible `test/**/*.js` literal sweep done; deployment ABIs regenerated; `docs/JACKPOT-EVENT-CATALOG.md` + `docs/JACKPOT-PAYOUT-REFERENCE.md` updated to the entries basis + current event shape.
4. ONE batched `.sol` diff presented and approved before commit.

## Phase 482: DEGENERETTE DEAD-MODE REPACK (GATED contract diff #4 — behavior)

**Goal:** Remove the dead fractional-bet "Full Ticket" mode — strip the dead bits, re-pack `degeneretteBets`, rename `FT_*_SHIFT`→`DEGEN_*_SHIFT` (values shift) and `_packFullTicketBet`→`_packDegeneretteBet` (body) — with new packed-bet goldens and an EV/resolution re-test. Sequenced after 480/481 (consumes the renamed degenerette identifiers).

**Requirements:** DGN-01, DGN-02, DGN-03

**Success criteria:**
1. The `mode`/`isRandom`/`hasCustom` bits stripped; `degeneretteBets` re-packed; `FT_*_SHIFT`→`DEGEN_*_SHIFT` with the new offsets; `_packFullTicketBet`→`_packDegeneretteBet` body re-pack; the `Storage:1750-1760` layout comment rewritten. Mapping name `degeneretteBets` unchanged.
2. Regenerated packed-bet goldens + a Degenerette EV/resolution re-test confirm one-bet-path equivalence; any hardcoded-shift bet decoder in `test/` updated.
3. ONE batched `.sol` diff presented and approved before commit.

## Phase 483: FF-SALVAGE ENTRY-GRANULARITY (GATED contract diff #5 — behavior)

**Goal:** Close the sole remaining entry-granularity gap — make far-future salvage entry-granular via the 5-site coupled change (changing only the `×4` would mis-value 4×) and rename the FF-salvage surface to entries.

**Requirements:** FF-01, FF-02, FF-03, FF-04

**Success criteria:**
1. The 5 coupled sites changed (`MintModule:1162`, `MintStreakUtils:196/207`, `MintModule:1134`, + NatSpec) so FF salvage debits/credits at entry granularity; whole-ticket valuation halves stay coupled (no 4× over/under-pay).
2. `sellFarFutureTickets`/`previewSellFarFutureTickets`/`_removeFarFutureTickets`→`*Entries` + Vault/`IGamePlayer`/`Game` wrappers in lockstep.
3. `FarFutureSalvageSwap`/`FarFutureIntegration`/`BafFarFutureTickets` tests updated + a new sub-whole-ticket (whale-pass 2-entry) sell case green.
4. ONE batched `.sol` diff presented and approved before commit.

## Phase 484: VERIFY + CLOSE

**Goal:** Prove the milestone lands the intended economy, the refactor is behavior-preserving, and close out.

**Requirements:** VER-01, VER-02, VER-03, VER-04

**Success criteria:**
1. Full forge + Hardhat suite green (≥893/0 floor; ≥1003/0/107 forge); layout golden `--check` green; Bernoulli EV testers green.
2. RTP re-sim confirms prize-leg ticket EV now lands at ~0.786× of budget (479 under-delivery resolved); before/after entries-per-roll recorded.
3. Cross-model adversarial re-audit of the full v75.0 diff dispositioned clean; contracts git-verified after read-capable fan-outs.
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
