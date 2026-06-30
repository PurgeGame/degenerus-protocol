# Phase 480 RESEARCH — RENAME-SWEEP (no behavior change)

**Authored:** 2026-06-29 · **Re-scoped:** 2026-06-29 from the disambiguation ledger **§10** (owner decisions applied; supersedes the earlier broad survey + the pre-§10 480 plan).
**Baseline:** local HEAD `cdd32fe9` = phase-479 close (`contracts/` tree carries `wholeTicketsToEntries` + the entries value fix; `main`, not pushed).
**Binding source:** `.planning/v75-grounding/v75.0-ticket-entry-disambiguation-ledger.md` §10 — read it; this RESEARCH is its distillation for the 480 executor. §10.4/§10.6/§10.7 ref sets were grep-run and re-verified against source at this HEAD (see §5 below).

## RESEARCH COMPLETE

---

## 0. Phase boundary (read first — do NOT bleed scope)

Phase 480 ships **selector-safe, layout-stable identifier renames + comment-only doc fixes only**, as ONE batched gated `.sol` diff + autonomous test/golden updates. **Behavior is byte-identical: no logic line changes, no values change, no event field/name, no external view selector, no `.slot` offset, no Bernoulli/EV expression. Storage layout is byte-stable (label/typeLabel name strings only).**

**Governing principle (§10.1):** rename ONLY identifiers that HOLD / RETURN / DENOMINATE an entry COUNT or VALUE (where "ticket" is the dangerous 4× unit lie). **KEEP** mechanism/subsystem/function names, indices, ETH-budgets, flags, modes, winner-caps, scale factors, and whole-ticket-leg labels — even when they contain "ticket".

**OUT of 480 (later gated diffs — do NOT start here):**
- **Event NAMES/fields** (`JackpotTicketWin`→`JackpotEntryWin`, the three queue events, Degenerette events, `TicketsBought.ticketQuantity` field, the `ticketIndex`/`tickets` event fields) → **Phase 481**.
- **External view selectors** (`ticketsOwedView`/`sampleTraitTicketsAtLevel`/`getTickets` → entries) → **Phase 481**. (480 fixes their @return NatSpec only — F3.)
- **Degenerette packed-bet repack** (`FT_*_SHIFT`→`DEGEN_*_SHIFT`, `_packFullTicketBet` body, the dead `mode`/`isRandom`/`hasCustom` bits) → **Phase 482**.
- **FF-salvage entry-granularity + `sellFarFutureTickets`→`sellFarFutureEntries`** → **Phase 483**.

If a rename appears to require editing logic, a value, an event, a selector, a `.slot` offset, or a Bernoulli expression — STOP; that is out of 480.

---

## 1. Canonical name table (LOCKED in ledger §10 — use these EXACT targets)

### 1A. Entries plumbing (the core — RN-01…RN-05)

| Old identifier | New identifier | Req | Kind |
|---|---|---|---|
| `traitBurnTicket` (storage `mapping`) | `lvlTraitEntry` | RN-01 | storage label |
| `traitBurnTicket_` (Jackpot helper param) | `lvlTraitEntry_` | RN-01 | param |
| `ticketsOwedPacked` (storage `mapping`) | `entriesOwedPacked` | RN-02 | storage label |
| `_queueTickets` (param `quantity`) | `_queueEntries` (param `entries`) | RN-03 | fn + param |
| `_queueTicketsScaled` (param `quantityScaled` = **scaled-ENTRIES**) | `_queueEntriesScaled` (param **`entriesScaled`**) | RN-03 | fn + param (F1) |
| `_queueTicketRange` (param `ticketsPerLevel`) | `_queueEntryRange` (param `entriesPerLevel`) | RN-03 | fn + param |
| `_activate10LevelPass` (param `ticketsPerLevel`, Storage:1298) | param `entriesPerLevel` | RN-03 | param (§10.7) |
| `WHALE_BONUS_TICKETS_PER_LEVEL` (=40) | `WHALE_BONUS_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED) |
| `WHALE_STANDARD_TICKETS_PER_LEVEL` (=2) | `WHALE_STANDARD_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED) |
| `WHALE_PASS_TICKETS_PER_LEVEL` (=2, Lootbox mirror of WHALE_STANDARD; Lootbox:210/1919) | `WHALE_PASS_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED; ledger §4 → 480 const, 481 event field) |
| `LAZY_PASS_TICKETS_PER_LEVEL` (=4) | `LAZY_PASS_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED) |
| `VAULT_PERPETUAL_TICKETS` (=16) | `VAULT_PERPETUAL_ENTRIES` | RN-04 | const (value UNCHANGED) |
| `_budgetToTicketUnits` | `_budgetToEntries` | RN-05 | fn (canonical budget→entries) |
| `ticketUnits` / `dailyTicketUnits` / `carryoverTicketUnits` / `baseUnits` (hold ENTRIES) | `entries` / `dailyEntries` / `carryoverEntries` / `baseEntries` | RN-05 | locals (+ bitfield comment labels Storage:437-438, Jackpot:403-404) |
| `bonusTickets` / `standardTickets` (WhaleModule locals, = const×qty entries) | `bonusEntries` / `standardEntries` | RN-05 | locals (§10.7) |
| bug-site `quantityScaled` / `scaledTickets` / `countScaled` (hold **scaled-WHOLE**, F1 sites ONLY) | `wholeTicketsScaled` / `scaledWholeTickets` | RN-05 | locals (§3 collision) |

### 1B. Decimator burn-BET set (RN-06 — §10.7 owner: BET not "Record", `dec` prefix, `subBucket` not `sub`)

| Old identifier | New identifier | Kind |
|---|---|---|
| `DecEntry` (struct type, Storage:1833) | `DecBet` | struct |
| `TerminalDecEntry` (struct type, Storage:1939) | `TerminalDecBet` | struct |
| `terminalDecEntries` (mapping, Storage:1947) | `terminalDecBets` | storage label |
| `_decClaimableFromEntry` (private view) | `_decClaimableFromBet` | fn |
| `levelEntries` (local, Decimator:342,346) | `decLevelBets` | local |
| `entryBurn` (local, Decimator:551,554,561) | `decBetBurn` | local |
| `entryBucket` (local, Decimator:806-847) | `decBetBucket` | local |
| `entrySub` (local = `e.subBucket`, Decimator:807-848) | `decBetSubBucket` | local |

KEEP `decBurn` (mapping already says "burn"; only its `DecEntry` value type follows to `DecBet`). KEEP `e.subBucket` (struct field name — already canonical). KEEP the "External Entry Points" / "entry points" delegatecall comments (Decimator:122,382 — function entry points, NOT the unit).

### 1C. Degenerette ticket-relics → spin / traits (RN-07 — §2A LOCKED + §10.2)

| Old identifier | New identifier | Kind | Lockstep |
|---|---|---|---|
| `amountPerTicket` (ext+priv param/local) | `amountPerSpin` | param/local | Vault inline IGamePlayer:50 + forwarder:597 + IDegenerusGameModules:422 |
| `ticketCount` (degenerette ext+priv param/local) | `spinCount` | param/local | Vault inline IGamePlayer:51 + forwarder:598 |
| `customTicket` (ext+priv param/local) | `customTraits` | param/local | Vault inline IGamePlayer:52 + forwarder:599 |
| `_fullTicketPayout` (private fn) | `_degenerettePayout` | fn | calls 797/1605/1671/1728 |
| `playerTicket` (local) | `playerTraits` | local | Degenerette:745 + many |
| `resultTicket` (local) | `resultTraits` | local | Degenerette:775,790 + many |
| `firstResultTicket` (local) | `firstResultTraits` | local | Degenerette:754,790,898 |
| `_countGoldQuadrants(ticket)` param | `_countGoldQuadrants(traits)` | param | Degenerette:1077,1080 |

**OUT of RN-07 (later phases):** the Degenerette EVENTS `FullTicketResolved`/`FullTicketResult` + their fields → 481; the `FT_*_SHIFT` constants + `_packFullTicketBet` body + the dead mode bits → 482. In 480, the `customTicket` LOCAL renames to `customTraits` but the read expression `(packed >> FT_TICKET_SHIFT)` keeps `FT_TICKET_SHIFT` (renamed only in 482). These are independent identifiers.

### 1D. `ticketQuantity` → `entryQuantityScaled` (RN-08 — §10.6 owner correction)

`ticketQuantity` is **scaled ENTRIES (×100)**, NOT whole tickets: `ticketCost = (priceWei × ticketQuantity)/(4×TICKET_SCALE)`, so `ticketQuantity=100` buys exactly 1 entry, `400` = 1 whole ticket. (It was wrongly §3-KEEP.) Rename the 67 PARAM/local refs to `entryQuantityScaled` (consistent with `entriesScaled`/`EntriesQueuedScaled`): Mint (29, purchase/redeemFlip/buyTickets paths incl. the 3 `@param` NatSpec + the emit arg :1380), Game (15), Vault (10 incl. `gamePurchaseTicketsFlip` + inline `IGamePlayer`), `IDegenerusGameModules` (7), `IDegenerusGame` (6). Selector-safe (param names not in selectors — the off-chain agent's positional call needs no edit; its event-arg read is 481. `sDGNRS` holds ZERO `ticketQuantity` refs — nothing to do there).
**OUT of 480 — exactly ONE `ticketQuantity` survives 480:** the `TicketsBought` event FIELD decl at `MintModule:165` (`event TicketsBought(address indexed buyer, uint256 ticketQuantity, uint256 weiIn)` — an off-chain ETH-in telemetry event, no on-chain consumer; the field is scaled-entries). The field + event name → 481 (EVT-04). The acceptance gate must NOT flag this surviving field (see §7 / the F1-class verify note).
**KEEP (audited whole-ticket-leg labels):** `ticketCost`/`ticketWei` (wei), `oneTicketWei` (one whole-ticket wei price), `ticketFreshFlip`/`ticketRecycledFlip`/`ticketNextShare`/`ticketFutureShare` (wei funding-splits), `_activeTicketLevel` (level), `_callTicketPurchase` (mechanism fn).

---

## 2. KEEP set (do NOT rename — §10.1 / §3 of the ledger)

- **Activation-queue mechanism cluster (§3/R1):** `ticketQueue`, `ticketCursor`, `ticketLevel`, `ticketsFullyProcessed`, `ticketWriteSlot`, `ticketRedemptionOpen`, `_tqWriteKey`/`_tqReadKey`/`_tqFarFutureKey`, `processTicketBatch`, `processFutureTicketBatch`, and the Advance wrappers `_runProcessTicketBatch`/`_processFutureTicketBatch`/`_prepareFutureTickets`/`_swapTicketSlot`. Holds addresses/index/level (no entry count), selector-coupled to the un-renamed external `processTicketBatch(uint24)`. (Fix the `ticketQueue` comment only, not the name.)
- **Jackpot "Ticket Jackpot" subsystem (§10.2):** `_distributeTicketJackpot`, `_distributeTicketsToBuckets`, `_distributeTicketsToBucket`, `_distributeLootboxAndTickets`, `_awardJackpotTickets`, `_jackpotTicketRoll`, `_randTraitTicket`, `_packDailyTicketBudgets`/`_unpackDailyTicketBudgets`, `dailyTicketBudgetsPacked` (ETH budgets), `dailyJackpotCoinTicketsPending` (flag), `isTicketJackpotDay`, `PURCHASE_PHASE_TICKET_MAX_WINNERS` (winner cap), locals `ticketIndex`/`ticketIdx`/`ticketBasis`/`ticketConversionBps` (indices/bps). Only the entry-VALUE locals `ticketUnits`/`dailyTicketUnits`/`carryoverTicketUnits` rename (RN-05).
- **Scale factors KEPT:** `AFKING_TICKET_SCALE` (=400; the 400 literally = one whole ticket in afking units — comment ref to the inherited scale updates to `QTY_SCALE`), `TICKET_LCG_MULT`, `TICKET_MIN_BUYIN_WEI`, `TICKET_SLOT_BIT`, `TICKET_FAR_FUTURE_BIT`. (**`TICKET_SCALE` itself RENAMES → `QTY_SCALE`** — owner 2026-06-29, RN-04; see §5/§8.)
- **The 479 helper:** `wholeTicketsToEntries` (whole<<2 — already correctly named; do NOT alter logic).
- **The `whole` local** at the two bug sites — post-479 it genuinely holds whole tickets (converted via `wholeTicketsToEntries(whole)`); NOT misleading.
- **Whole-ticket counts/labels:** `FOIL_PACK_TICKETS` (=10, ten ticket prices), `ticketPrice`/`whole`/`frac`/`roundedUp` (Bernoulli), the Lootbox whole-ticket reward path (`LOOTBOX_TICKET_*_BPS`, `DISTRESS_TICKET_BONUS_BPS`, `_ticketBudget`/`ticketBudget` (ETH), `_ticketVarianceBps`, `_lootboxTicketCount`), and the Mint whole-ticket-leg labels (`ticketCost`/`ticketWei`/`oneTicketWei`/`ticketQuantity`-leg wei fields kept per 1D, `_callTicketPurchase`, `_removeFarFutureTickets`/`sellFarFutureTickets` [481/483], `_activeTicketLevel`).
- **Flags/modes:** `useTickets`, `FLAG_USE_TICKETS`, `isTicket` (buy-MODE flag — KEEP; renaming to "entries" would be wrong, the mode buys whole tickets).
- **`FOIL_PACK_ENTRIES` (=16)** — already correctly entry-named.
- **`decBurn`** mapping name; `e.subBucket` struct field.
- **Comments that are NOT the unit:** "External Entry Points"/"entry point"/"loop entry" (Mint/Jackpot/Decimator/Lootbox/Degenerette/Storage), deity "virtual entry" raffle-slot comments, `EntropyLib`/"entropy" (RNG term — exclude from any entry-token grep).
- **Unpromoted §2A GAP rows (NOT adopted by §10) — KEEP:** `ticketsOut` (→`wholeTicketsScaledOut` not adopted; out of the F1 two-site scope), `_processOneTicketEntry` (queue-slot mechanism fn).

---

## 3. LANDMINE — F1: the `quantityScaled` two-unit collision (HARD GUARD)

The same token denotes opposite units:
- **`_queueTicketsScaled` param `quantityScaled` (Storage:693) = scaled-ENTRIES** (`owed += quantityScaled / TICKET_SCALE`) → **`entriesScaled`**.
- **Bug-site `quantityScaled` (Jackpot:2127) / `scaledTickets` (Jackpot:2133, Lootbox:1356) / `countScaled` (Lootbox:2177) = scaled-WHOLE-tickets** → **`wholeTicketsScaled`/`scaledWholeTickets`**.

Scope the `wholeTicketsScaled` rule to the **two module bug-sites ONLY** (Jackpot:2127/2133, Lootbox:1356/2177). There must be **ZERO blanket `quantityScaled→wholeTicketsScaled`** — that would mislabel scaled-entries as scaled-whole (a 4× unit lie). The `whole` local stays `whole`. Fix the Lootbox:2176 NatSpec ("Number of tickets × TICKET_SCALE") → "scaled whole-ticket count (whole × TICKET_SCALE), collapsed to entries at queue via wholeTicketsToEntries".

---

## 4. LANDMINE — Decimator "entry point" ≠ burn bet; "bet" ≠ "ticket/entry unit"

`DegenerusGameDecimatorModule.sol` uses "entry" in two unrelated senses:
- **Burn BET record (RN-06 target):** `DecEntry`/`TerminalDecEntry`/`levelEntries`/`entryBurn`/`entrySub`/`entryBucket`/`_decClaimableFromEntry`/`terminalDecEntries` → the `DecBet`/`dec`-prefixed names (§1B). A decimator "bet" is NEITHER a ticket NOR an entry — it is the side-game per-player burn wager. The `dec` prefix + `Bet` disambiguates it from the degenerette bet.
- **Function entry point (KEEP):** `// External Entry Points (delegatecall targets)` (:122) and `/// … the single and batch entry points.` (:382). A blind `entry`→`bet`/`record` sed would corrupt these. **Rename by identifier, never by substring.**

Generic burn-record prose ("every claimable entry costs a real …", :116/135/385-386) updates to "bet" for the convention, but they are comments, not identifiers.

---

## 5. Complete lockstep ref sets (ledger §10.4 — grep-run; re-verified at HEAD)

These are the authoritative compile-break sets (renaming the decl breaks the build if any ref is missed). Re-grep before claiming green; `forge build`/`hardhat compile` are the final oracles.

- **`traitBurnTicket→lvlTraitEntry` (code):** Storage:472(decl); DegenerusGame:2434,2517; Bingo:140; FoilPack:782(.slot); Mint:569(.slot); Jackpot:867,931,1130,1432,1442,1454,1467,1479,1626 (+param `traitBurnTicket_`→`lvlTraitEntry_`). NatSpec: Game:321, IDegenerusGame:387, IDegenerusGameModules:493, Bingo:19/117/123/135, FoilPack:667/776, Jackpot:631/805, Mint:561/752, Storage:107/463.
- **`ticketsOwedPacked→entriesOwedPacked` (code):** Storage:524(decl),660,669,704,732,763,772; Mint:336,640,1252,1263,1265; DegenerusGame:2092,2539. (**Advance has ZERO** — the old §2 attribution was wrong.)
- **`_queueTicketRange→_queueEntryRange` calls:** Storage:1382; Decimator:660; Whale:328,336,652,660,1024.
- **`_queueTickets→_queueEntries` calls:** Game:225; Whale:506; Advance:1620,1626; Jackpot:887,2143; Lootbox:1383; Mint:1164.
- **`_queueTicketsScaled→_queueEntriesScaled` calls:** Mint:1021,1637; Afking:830.
- **RN-04 constants:** `WHALE_BONUS_TICKETS_PER_LEVEL` Whale:141(decl),320,656; `WHALE_STANDARD_TICKETS_PER_LEVEL` Whale:144(decl),322,664; `WHALE_PASS_TICKETS_PER_LEVEL` Lootbox:210(decl),1919 (the lootbox mirror; the `LootBoxWhalePassJackpot.tickets` event FIELD it feeds stays for 481); `LAZY_PASS_TICKETS_PER_LEVEL` Whale:126(decl),502; `VAULT_PERPETUAL_TICKETS` Advance:131(decl),1623,1629. Genesis literal `16` at Game:225 (comment → "16 entries (= 4 whole tickets) per level").
- **RN-04 scale factor `TICKET_SCALE → QTY_SCALE` (73 refs):** decl `Storage:157` (`internal constant TICKET_SCALE = 100`) + production refs Game(1)/Lootbox(9)/FoilPack(2)/Jackpot(6)/GameAfking(9; the dual-scale comment block :164-172,663-664 — **LANDMINE (council M-3): `:164` semantically denotes `AFKING_TICKET_SCALE = 400`, NOT the inherited scale; it becomes "`AFKING_TICKET_SCALE = 400`", do NOT write "QTY_SCALE = 400". ONLY the lines referencing the inherited `TICKET_SCALE = 100` (:167/:170/:172/:664) become "`QTY_SCALE = 100`"**)/Mint(13, incl. the cost-formula comments :162,1188). Plus the two test mirrors `contracts/test/LootboxBernoulliTester.sol`(14, own decl :21) + `JackpotBernoulliTester.sol`(12, own decl :29) — rename in lockstep, Bernoulli collapse byte-identical. KEEP `AFKING_TICKET_SCALE`(=400, comment-only update).
- **RN-05 (Jackpot):** `_budgetToTicketUnits` decl:705, calls 358/396/638/748, NatSpec 626/889; locals `dailyTicketUnits`(358-1894), `carryoverTicketUnits`(373-1895), `ticketUnits`(638-825), `baseUnits`(818). `bonusTickets`/`standardTickets` Whale:320,321,332,340,463,469,505,506.
- **`ticketQuantity→entryQuantityScaled` (RN-08, 67 refs):** Mint(29), Game(15), Vault(10: inline IGamePlayer:50, forwarder `gamePurchaseTicketsFlip`:551 + :597-599 + 605/612, `amountPerTicket`-leg), IDegenerusGameModules(7), IDegenerusGame(6) + off-chain agent caller. (The `TicketsBought.ticketQuantity` field stays for 481.)
- **NEW lockstep targets the synthesis missed (§10.4):** the Vault inline `IGamePlayer` Degenerette params (`amountPerTicket`:50, `ticketCount`:51, `customTicket`:52 + forwarder :597-599) rename with the RN-07 Degenerette renames; re-check `sDGNRS`/`Vault`/`Coinflip` ticket surface (KEEP whole-ticket-leg: `useTickets`, the `ticketQuantity`-leg wei labels, `gamePurchaseTicketsFlip`). `getTickets`(Game:2510) is an entries-returning view → its @return doc fixes here (F3), the SELECTOR renames in 481.
- **F1 guard (HARD):** `_queueTicketsScaled` param + `TicketsQueuedScaled` field → `entriesScaled`; `wholeTicketsScaled` is the two module bug-sites ONLY.

**Interfaces requiring lockstep decl edits:** `IDegenerusGameModules.sol` (traitBurnTicket NatSpec:493; the Degenerette params:422; `ticketQuantity` decls), `IDegenerusGame.sol` (traitBurnTicket NatSpec:387; `ticketQuantity` decls). KEEP the selectors (481).

**Thin-coverage files to re-grep before executing (ledger §5):** WhaleModule, FoilPackModule, GameAfkingModule, DegenerusGame facade, DegenerusJackpots, PayoutUtils, MintStreakUtils, all interface files, `contracts/test/*Tester.sol` (Bernoulli/Solo testers mirror the queue helpers — rename in lockstep).

---

## 6. Layout stability — proof + goldens (RN-04 constants are private → not in layout)

- Oracle: `scripts/layout/storage_layout_oracle.sh` (`--capture` regenerates, `--check` verifies); normalizer `scripts/layout/normalize_layout.py` emits `{slot, offset, label, typeLabel, bytes, encoding}`; ~25 goldens in `scripts/layout/golden/`.
- A rename is **label/typeLabel-name-string-only**:
  - Renaming a storage MAPPING VARIABLE (`traitBurnTicket`/`ticketsOwedPacked`/`terminalDecEntries`) changes its `label` string only.
  - Renaming a STRUCT TYPE (`DecEntry`/`TerminalDecEntry`) changes the `typeLabel` STRING of the mappings referencing it (`decBurn`, `terminalDecBets`) — layout-NEUTRAL but a typeLabel string move. The gate is: **ONLY `label` and `typeLabel` name strings may differ; `slot`/`offset`/`bytes`/`encoding` byte-identical.**
  - Constants (RN-04) are `private constant` — NOT in storage layout — so they do NOT touch goldens.
- Sequence: rename `.sol` → `hardhat compile` → `forge build` (after the harness lockstep) → `storage_layout_oracle.sh --capture` → `git diff scripts/layout/golden/` shows ONLY `label`/`typeLabel` string changes → `--check` green. Only `DegenerusGame.json` + the 12 Storage-inheriting module goldens may change; the 12 standalone-contract goldens (Coinflip/DGNRS/sDGNRS/FLIP/GNRUS/WrappedWrappedXRP/DegenerusAffiliate/DegenerusQuests/DegenerusVaultShare/DegenerusDeityPass/DegenerusJackpots/DegenerusAdmin) must be byte-identical. **If any non-name field moves, or a standalone golden changed — STOP: a rename hit layout.**

---

## 7. Test blast radius (RN-10 — the FIX-05 forge-invisible trap)

479's FIX-05 proved: a contract symbol-shape change breaks `indexOf`/`includes`/`===`/`match` source-string assertions across many `*.test.js`, which **forge does NOT catch**. A rename is the same hazard, larger (RN-03 renames the sinks; RN-08 renames `ticketQuantity` across the purchase surface). Three distinct surfaces:

**(a) Compile-break — Solidity `.t.sol`/`.sol` with real code refs (`forge build` RED until lockstep).** The class is `traitBurnTicket[...]` AND `_queueTickets*(...)` calls AND `ticketsOwedPacked[...]` AND any test calling the renamed Degenerette/ticketQuantity surface. Re-derive deterministically BEFORE claiming green:
- `rg -n '\b_queue(Tickets|TicketsScaled|TicketRange)\s*\(' test/ --glob '*.sol'`
- `rg -n 'traitBurnTicket\[|ticketsOwedPacked\[' test/ --glob '*.sol'`
- `rg -n '\b(DecEntry|TerminalDecEntry)\b|_decClaimableFromEntry\s*\(|terminalDecEntries\[' test/ --glob '*.sol'`
- `rg -n '_budgetToTicketUnits|_fullTicketPayout|amountPerTicket|customTicket\b' test/ --glob '*.sol'`
Known starting set (grep-verified; do NOT trust as static — `forge build` is the oracle): `test/fuzz/JackpotSingleCallCorrectness.t.sol`, `test/fuzz/QueueDoubleBuffer.t.sol`, `test/fuzz/TicketEdgeCases.t.sol`, `test/fuzz/TicketRouting.t.sol`, `test/gas/AdvanceGasCeiling.sol`, `test/gas/AdvanceStageWorstCaseGas.t.sol`, `test/gas/GameOverCompositionAdvanceGas.t.sol`, `contracts/test/LootboxBernoulliTester.sol` (NatSpec mirror :71 — comment-only; Bernoulli expression byte-identical).

**(b) Runtime-break — JS by-name string assertions (forge-invisible; only `npm test` catches):**
- `test/edge/DeityPassGoldNerfRegression.test.js` — `deriveStorageSlot("traitBurnTicket")` ×6 → `"lvlTraitEntry"`.
- `test/edge/LootboxAutoResolveRegression.test.js:402,403` — `.includes("ticketsOwedPacked")` → `"entriesOwedPacked"`.
- `test/edge/MintCleanupRegression.test.js:550,553` — `cells[k] === "ticketsOwedPacked"` → `"entriesOwedPacked"`.
- The 479-reconciled source-string suites that pin the `_queueTickets(…, wholeTicketsToEntries(whole), …)` call form (CrossSurfaceTicketMixing + the 7 FIX-05 gap-closure suites in 479-02-SUMMARY) → move each `_queueTickets(…)` literal to `_queueEntries(…)`, keep `wholeTicketsToEntries(whole)`.
- `rg test/` for EVERY renamed identifier as a quoted string / `.includes(` / `=== "` / regex, then run the FULL Hardhat suite.

**(c) Comment-only refs (no break; refresh for consistency):** `MintModuleDivergenceAcrossSplit.t.sol` (slot-8 hardcoder comment — the slot NUMBER survives), `DecimatorBountyRegression.t.sol` (`DecEntry`), `KeeperRewardRoutingSameResults.t.sol`, `TicketLifecycle.t.sol`, `randTraitTicketRef.mjs`, `Phase264GasRegression.test.js`, `MintBatchDeterminism.test.js`, `DegenerusJackpots.test.js`, `PerPullEmptyBucketSkip.test.js`.

**DO NOT TOUCH (481 scope / EV tripwire):** event field-name assertions (`ticketCount`, `futureTickets`, `TicketsQueued.quantity`, `TicketsQueuedRange.ticketsPerLevel`); the agent's Degenerette `ticketCount` bet-input param; any `test/stat/*BernoulliEv*` tester (the 37 EV assertions stay UNCHANGED).

**479-close floor (do not regress):** forge 1003/0/107; the 37 Bernoulli EV assertions green UNCHANGED; the pre-existing `SurfaceRegression.test.js` 5 failures are unrelated (guard byte-identical trait files) — confirm same set, not a 480 regression.

---

## 8. Comment-only doc fixes (RN-09 — no behavior, land in 480)

- **F2:** stale `JackpotTicketWin` NatSpec `Jackpot:72-77` "whole-ticket count" → "entries count" (all 3 paths emit entries post-479). (The event RENAME is 481; only the doc text moves in 480.)
- **F3:** `ticketsOwedView`/`getPlayerPurchases`/`getTickets` @return mislabel (`Game:2087,2533,2510`) "whole tickets owed" → "entries". (The selector RENAMES are 481.)
- **F5:** `whalePassClaims` doc `Storage:1155` "100 tickets = 50 levels × 2 tickets" → "100 entries (100 levels × 1 entry per half-pass)".
- **NFT scrub (§10.7):** the 4 CONV-02 NatSpec refs `Storage:522,634,674,679` "1 entry = 1 minted NFT" → "price/4 = ¼ of a whole ticket (4 entries per whole ticket)". Also scrub "NFT" from the grounding docs (ledger / map / this RESEARCH / VALIDATION / the HTML view) — an entry is a "jackpot entry", not an NFT. (No deity-pass cosmetic-NFT comment exists in these files to preserve.)
- **`TICKET_SCALE` disposition (§10.7) — RESOLVED (owner 2026-06-29): RENAME → `QTY_SCALE`** (unit-neutral — a dual-use 2-decimal scale factor used for BOTH whole tickets and entries, so "ticket" is a misnomer; `ENTRY_SCALE` is forbidden, would mislabel the whole-ticket usages). Scope: the canonical `internal constant TICKET_SCALE = 100` decl at `Storage:157` + all ~47 production refs (Game/Lootbox/FoilPack/Jackpot/GameAfking/Mint) + the two `contracts/test/*BernoulliTester.sol` local mirrors (each has its own `TICKET_SCALE = 100`: Lootbox:21, Jackpot:29). PURE-identifier rename — the Bernoulli `/ QTY_SCALE` math is byte-identical (same value 100); EV testers stay green UNCHANGED. **`\bTICKET_SCALE\b` does NOT match `AFKING_TICKET_SCALE`** (the `_` blocks the word boundary). KEEP `AFKING_TICKET_SCALE` (=400); only its dual-scale comment (GameAfking:164-167,663-664) referencing the inherited "TICKET_SCALE = 100" updates to "QTY_SCALE = 100".

---

## 9. Landmines (condensed)

- **Rename by identifier, never substring/sed** — `entry`→`bet` would corrupt Decimator "entry point" comments (§4); `Tickets`→`Entries` would hit the 481 event fields + `AFKING_TICKET_SCALE` (keep); `ticket`→`entry` would hit the KEEP mechanism cluster. (`TICKET_SCALE`→`QTY_SCALE` is by whole-token identifier; `\bTICKET_SCALE\b` excludes `AFKING_TICKET_SCALE`.)
- **F1 collision (HARD)** — sink param → `entriesScaled`; bug-sites (Jackpot:2127/2133, Lootbox:1356/2177) → `wholeTicketsScaled`; ZERO blanket `quantityScaled`→`wholeTicketsScaled`.
- **Decimator is BET, not Record** — §10.7 owner reversed the earlier "Record" proposal; use `DecBet`/`dec`-prefixed locals/`subBucket`.
- **`ticketQuantity` is the silent KEEP→RENAME flip** (§10.6) — it holds scaled-entries; 67 refs; the event field stays for 481.
- **Degenerette scope split** — 480 renames identifiers/params; 481 the events; 482 the `FT_*` constants + `_packFullTicketBet` body. Keep `FT_TICKET_SHIFT` etc. in 480.
- **`.slot` reads bind by name** — the 2 inline-asm sites update automatically; verify they read `lvlTraitEntry.slot` and the slot number is unchanged.
- **Storage layout is the hard floor** — `--check` label/typeLabel-only; any slot/offset/bytes/encoding move = a rename hit logic; STOP.
- **Bernoulli/EV testers stay GREEN UNCHANGED** — NatSpec mirrors may update; expressions byte-identical.
- **No event/value/selector changes** — 481 owns events + the entries-returning view selectors.
- **The test sweep is the FIX-05 trap** — forge green ≠ done; the FULL Hardhat suite is the only signal for the runtime by-name class.
- **Comments describe what IS** — no "renamed from"/history; no phase/plan IDs in `contracts/*.sol`.
- **Contract-commit gate** — the `.sol` rename hunk is ONE batched diff for USER approval before commit (success criterion 6); `.sol` edits + all golden/test commits are autonomous.
