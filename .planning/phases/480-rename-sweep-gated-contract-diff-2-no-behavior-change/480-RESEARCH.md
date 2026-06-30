# Phase 480 RESEARCH — RENAME-SWEEP (no behavior change)

**Authored:** 2026-06-29 (distilled from the verified grounding map + a fresh grep-verified reference inventory by the main loop — USER chose "plan directly, grounding map suffices"; the exact-site inventory below is the main-loop's de-risking pass, not a researcher-agent spawn)
**Baseline:** local HEAD = phase-479 close (`contracts/` tree carries `wholeTicketsToEntries` helper + the entries value fix; `main`, not pushed)
**Sources (all re-verified against source at this HEAD by the main loop):**
- `.planning/v75-grounding/v75.0-ticket-entry-map.md` — rename map + blast radius (counts were approximate; **understated the test blast radius — see §6**)
- `.planning/REQUIREMENTS.md` — RN-01 … RN-07
- `.planning/ROADMAP.md` — Phase 480 goal + success criteria
- `.planning/phases/479-*/479-02-SUMMARY.md` — the FIX-05 lesson (source-string assertions break across many `*.test.js`, NOT caught by forge)

## RESEARCH COMPLETE

---

## Phase boundary (read first — do NOT bleed scope)

Phase 480 ships **identifier renames only**, as ONE batched gated `.sol` diff + autonomous test/golden updates. **Behavior is byte-identical: no logic line changes, no values change, storage layout is byte-stable (label-only).**

**IN scope (RN-01 … RN-07):**
1. Rename entries-denominated storage, sink functions (+ params), constants (values unchanged), and the misleading locals.
2. Resolve the Decimator "entry" (= burn *record*) collision so "entry" means only the price/4 unit protocol-wide.
3. Recapture all layout goldens (`--capture`), prove `--check` green (label-only diff).
4. Update by-name test harnesses (compile-break `.t.sol`/`.sol` + runtime-break `.test.js` string assertions) in lockstep.

**Explicitly OUT of scope (later gated diff — do NOT start here):**
- **Event-field renames** (`JackpotTicketWin.ticketCount`→`entryCount`, `LootBoxOpened.futureTickets`→`futureEntries`, `TicketsQueued.quantity`→`entries`), ABI regen, doc rewrites → **Phase 481**. Leave every `event …`/`emit …` field name and emitted value exactly as 479 left them.
- **External view selectors** — unchanged (no selector churn in any phase).
- **Any value or logic change** — if a `--check` layout diff shows anything but a label change, or any Bernoulli/EV tester needs editing, STOP: a rename touched logic.

This phase touches **no event field, no value, no selector, no `.slot` offset** — only names + their goldens/harnesses.

---

## 1. Canonical name decisions (LOCKED in the grounding map + RN reqs)

| Old identifier | New identifier | Req | Kind |
|---|---|---|---|
| `traitBurnTicket` (storage mapping) | `lvlTraitEntry` | RN-01 | storage label |
| `traitBurnTicket_` (Jackpot helper *param*, trailing `_`) | `lvlTraitEntry_` | RN-01 | param |
| `ticketsOwedPacked` (storage mapping) | `entriesOwedPacked` | RN-02 | storage label |
| `_queueTickets` (param `quantity`) | `_queueEntries` (param `entries`) | RN-03 | fn + param |
| `_queueTicketsScaled` (param `quantityScaled` = **scaled-ENTRIES**) | `_queueEntriesScaled` (param `entriesScaled`) | RN-03 | fn + param |
| `_queueTicketRange` (param `ticketsPerLevel`) | `_queueEntryRange` (param `entriesPerLevel`) | RN-03 | fn + param |
| `WHALE_BONUS_TICKETS_PER_LEVEL` (=40) | `WHALE_BONUS_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED) |
| `WHALE_STANDARD_TICKETS_PER_LEVEL` (=2) | `WHALE_STANDARD_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED) |
| `LAZY_PASS_TICKETS_PER_LEVEL` (=4) | `LAZY_PASS_ENTRIES_PER_LEVEL` | RN-04 | const (value UNCHANGED) |
| `VAULT_PERPETUAL_TICKETS` (=16) | `VAULT_PERPETUAL_ENTRIES` | RN-04 | const (value UNCHANGED) |
| `_budgetToTicketUnits` | `_budgetToEntries` | RN-05 | fn (canonical budget→entries basis) |
| `*TicketUnits` / `ticketUnits` locals (hold ENTRIES) | `*Entries` / `entries` | RN-05 | locals |
| bug-site `quantityScaled`/`scaledTickets`/`countScaled` (hold **scaled-WHOLE-tickets**) | `wholeTicketsScaled`/`scaledWholeTickets` | RN-05 | locals (see §3 collision) |
| Decimator `DecEntry`/`TerminalDecEntry`/`levelEntries`/`entryBurn`/`entrySub`/`entryBucket`/`_decClaimableFromEntry` (= burn RECORD) | `*Record`/`burnRecord`/… (see §4) | RN-06 | struct/locals/fn |

**KEEP (do NOT rename — confirmed correct/intentional):**
- `ticketQueue` (holds addresses — fix the comment only, not the name; per grounding map).
- `AFKING_TICKET_SCALE` (=400; well-documented dual-scale; grounding map says keep).
- `wholeTicketsToEntries` (the 479 helper — already correctly named; the canonical post-Bernoulli whole→entries converter).
- `TICKET_SCALE` (=100; a scaling factor, not a unit name).
- `whole` local at the two bug sites — after 479 it genuinely holds whole tickets (converted via `wholeTicketsToEntries(whole)`); it is NOT misleading. **Do not rename `whole`.**
- The Decimator `decBurn` mapping name (already "burn", layout-stable) — keep; only its `DecEntry` *value type* is the collision.

---

## 2. Exact reference inventory — contracts (grep-verified at this HEAD)

### RN-01 `traitBurnTicket` → `lvlTraitEntry` (30 refs across 8 files)
- Storage decl: `contracts/storage/DegenerusGameStorage.sol:472` (`mapping(uint24 => address[][256]) internal traitBurnTicket;`) + NatSpec :107,:463.
- **2 inline-asm `.slot` reads (LANDMINE — must rename the identifier the assembler reads):** `DegenerusGameFoilPackModule.sol:782` (`mstore(0x20, traitBurnTicket.slot)`) + `DegenerusGameMintModule.sol:569` (`mstore(0x20, traitBurnTicket.slot)`). `.slot` resolves the variable by name at compile time → rename the variable and these lines update to `lvlTraitEntry.slot`. Layout is unaffected (same slot number).
- Code refs: `DegenerusGame.sol:2434,2517`; `DegenerusGameBingoModule.sol:140`; `DegenerusGameJackpotModule.sol:867,931,1130,1626` + **helper param `traitBurnTicket_`** at `:1432,:1442,:1454,:1467,:1479` (rename param → `lvlTraitEntry_`).
- NatSpec/comment refs (update for consistency, comments describe what IS): `DegenerusGame.sol:321`; `IDegenerusGameModules.sol:493`; `IDegenerusGame.sol:387`; `DegenerusGameBingoModule.sol:19,117,123,135`; `DegenerusGameFoilPackModule.sol:667,776`; `DegenerusGameJackpotModule.sol:631,805`; `DegenerusGameMintModule.sol:561,752`; `DegenerusGameStorage.sol:107,463`.

### RN-02 `ticketsOwedPacked` → `entriesOwedPacked` (15 refs across 3 files)
- Storage decl: `DegenerusGameStorage.sol:524`; sink reads/writes :660,:669,:704,:732,:763,:772; NatSpec :673.
- `DegenerusGame.sol:2092,2539`; `DegenerusGameMintModule.sol:336,640,1252,1263,1265`.

### RN-03 sink fns (decls in `DegenerusGameStorage.sol`)
- `_queueTickets` decl `:641` (param `quantity` `:644`; early-return `if (quantity == 0)`); callers: `DegenerusGame.sol:225` (genesis literal `16` — see RN-04), `AdvanceModule:1620,1626`, `JackpotModule:887,2143`, `LootboxModule:1383`, `MintModule:1164`, `WhaleModule:506`.
- `_queueTicketsScaled` decl `:690` (param `quantityScaled` `:693` = **scaled-ENTRIES**); callers: `MintModule:1021,1637`, `GameAfkingModule:830`.
- `_queueTicketRange` decl `:742` (param `ticketsPerLevel` `:746`; emits `TicketsQueuedRange(...,ticketsPerLevel)` `:750` — **`TicketsQueuedRange` is an EVENT; its field name is a 481 concern — do NOT rename the event or its field here, only the local/param feeding it**); callers: `Storage:1382` (local `ticketsPerLevel`), `DecimatorModule:660`, `WhaleModule:328,336,652,660,1024`.
- Stale NatSpec mirror of the old call form: `contracts/test/LootboxBernoulliTester.sol:71` (`_queueTickets(player, rollLevel, whole, false)` in a `///` comment). Comment-only; update to `_queueEntries(...)` for consistency. **Do NOT touch the Bernoulli expression in that tester (EV tripwire).**

### RN-04 constants (`DegenerusGameWhaleModule.sol` + `DegenerusGameAdvanceModule.sol`)
- `WHALE_BONUS_TICKETS_PER_LEVEL` decl Whale:141; refs :320,:656.
- `WHALE_STANDARD_TICKETS_PER_LEVEL` decl Whale:144; refs :322,:664.
- `LAZY_PASS_TICKETS_PER_LEVEL` decl Whale:126; ref :502.
- `VAULT_PERPETUAL_TICKETS` decl Advance:131; refs :1623,:1629.
- **Genesis literal `16`:** `DegenerusGame.sol:225` `_queueTickets(who, i, 16, false)` — the `16` is entries (=4 whole tickets/level). RN-04 wants the comment corrected to "16 entries (= 4 whole tickets) per level". The call itself becomes `_queueEntries(who, i, 16, false)` via RN-03.

### RN-05 `_budgetToTicketUnits` → `_budgetToEntries` + entries locals (`DegenerusGameJackpotModule.sol`)
- Fn decl `:705`; calls :358,:396,:638,:748; NatSpec :626.
- Entries-holding locals to rename `*Entries`: `dailyTicketUnits` (:358,:362,:407,:567,:584,:589,:1870,:1888,:1894), `carryoverTicketUnits` (:373,:396,:408,:568,:600,:607,:1871,:1889,:1895), `ticketUnits` (:638,:639,:644,:748,:749,:754,:767,:772,:778,:795,:813,:818,:819,:825), `baseUnits` (:818). Also the **packed-bitfield comment labels** at `Storage:437-438` and `Jackpot:403-404` (`dailyTicketUnits (64 bits @ 8)` / `carryoverTicketUnits (64 bits @ 72)`) — comment labels only; rename for consistency, **no packing/offset change**.
- NatSpec :889 references `_budgetToTicketUnits` — update to `_budgetToEntries`.

### RN-06 Decimator "entry" = burn RECORD (`DegenerusGameDecimatorModule.sol` + struct decls in `DegenerusGameStorage.sol`)
- Struct **types** (decls in Storage): `DecEntry` (`DegenerusGameStorage.sol:1833`, used by `decBurn` mapping :1866) → e.g. `DecRecord`; `TerminalDecEntry` (`:1939`, used by `terminalDecEntries` mapping :1947) → e.g. `TerminalDecRecord`. Renaming a struct *type* and the mapping's value type is **layout-neutral** (slot is the mapping's, struct field order/types unchanged). Mapping variable names `decBurn`/`terminalDecEntries` are storage labels — `terminalDecEntries`→`terminalDecRecords` is label-only (golden recapture covers it); `decBurn` already says "burn" → keep its name.
- Locals/fn in the module: `levelEntries` (:342,:346) → `levelRecords`; `entryBurn` (:551,:554,:561) → `recordBurn`; `entrySub` (:807,:810,:814,:848) → `recordSub`; `entryBucket` (:806,:808,:809,:811,:847) → `recordBucket`; `_decClaimableFromEntry` (:310,:348,:543,:582 + NatSpec :535,:540) → `_decClaimableFromRecord`; `DecEntry storage e`/`DecEntry memory m` locals (:153,:154,:306,:390,:546,:578) update to the new type name.

---

## 3. LANDMINE — RN-05 identifier collision (`quantityScaled`: two opposite units)

The same token `quantityScaled` denotes **scaled-ENTRIES** in the sink (`_queueTicketsScaled` param, `Storage:693`) but **scaled-WHOLE-tickets** at the Jackpot bug site (`JackpotModule:2127`). The lootbox analog is `countScaled` (`LootboxModule:2181/2186`, NatSpec `:2176` "Number of tickets × TICKET_SCALE" — whole-ticket basis) and `scaledTickets` (`Jackpot:2133`, `Lootbox:1356,1363,1366,1369,1374,1375,1376,1402`).

Resolution (LOCKED by RN-03 + RN-05):
- Sink param `quantityScaled` → **`entriesScaled`** (it IS scaled-entries; `owed += quantityScaled / TICKET_SCALE`).
- Bug-site `quantityScaled`/`scaledTickets`/`countScaled` (scaled-whole) → **`wholeTicketsScaled`/`scaledWholeTickets`** to disambiguate. `whole` stays `whole`.
- After this, "scaled" alone is ambiguous → every renamed scaled local must carry `entries` or `wholeTickets` in its name. Fix the `LootboxModule:2176` NatSpec ("Number of tickets × TICKET_SCALE") to "scaled whole-ticket count (whole × TICKET_SCALE), collapsed to entries at queue via wholeTicketsToEntries".

---

## 4. LANDMINE — Decimator "entry point" ≠ burn record (do NOT rename)

`DegenerusGameDecimatorModule.sol` uses "entry" in two unrelated senses:
- **Burn record** (RN-06 target): `DecEntry`, `levelEntries`, `entryBurn`, `entrySub`, `entryBucket`, `_decClaimableFromEntry`, `TerminalDecEntry`/`terminalDecEntries`.
- **Function entry point** (KEEP — unrelated to the unit): `// External Entry Points (delegatecall targets)` (`:122`) and `/// … the single and batch entry points.` (`:382`). These describe delegatecall dispatch, NOT the price/4 unit. **Do NOT rename "entry point" → "record point".** A blind `entry`→`record` sed would corrupt these. Rename by identifier, not by substring.

Also generic prose uses of "entry" (e.g. `:116` "every claimable entry costs a real …", `:135`, `:385-386`) refer to a burn-record claim — update those *comments* to "record" for the protocol-wide convention, but they are not code identifiers.

---

## 5. Layout stability — proof + goldens (RN-01, RN-03 success criterion 3)

- Oracle: `scripts/layout/storage_layout_oracle.sh` (`--capture` regenerates, `--check` verifies); normalizer `scripts/layout/normalize_layout.py`; goldens in `scripts/layout/golden/` (`DegenerusGame.json` + per-contract JSONs — DGNRS, sDGNRS, Coinflip, FLIP, GNRUS, WrappedWrappedXRP, DegenerusAffiliate, DegenerusQuests, DegenerusVaultShare, … ~13 total).
- A rename is **label-only**: `forge inspect storageLayout` reports the same slot/offset/type, with only the variable `label` string changed. The DegenerusGame golden (the only contract whose storage holds `traitBurnTicket`/`ticketsOwedPacked`/`decBurn`/`terminalDecEntries`) is the one whose labels move; the others should be byte-identical.
- Sequence: rename `.sol` → compile → `storage_layout_oracle.sh --capture` → `git diff scripts/layout/golden/` shows ONLY `"label"` string changes (no `"slot"`/`"offset"`/`"type"` move) → `storage_layout_oracle.sh --check` green. **If a non-label field moves, STOP — a rename touched a storage slot.** Commit the recaptured goldens autonomously (not gated; not `contracts/`).

---

## 6. LANDMINE — the grounding map UNDERSTATED the test blast radius (RN-07 + the FIX-05 lesson)

479's FIX-05 gap-closure proved: a contract symbol-shape change breaks `indexOf`/`includes`/`===`/`match` **source-string assertions across many `*.test.js`**, which **forge does NOT catch**. A rename is the same hazard, larger. The grounding map's RN-07 named only 2 compile-break files; the grep inventory finds more. The planner MUST do a **fresh exhaustive `test/` sweep for every renamed literal** (the names in the §1 table), not just the files below.

**(a) Compile-break — Solidity `.t.sol`/`.sol` with real code refs (`traitBurnTicket[...]`):**
- `test/fuzz/JackpotSingleCallCorrectness.t.sol:27,52` (named in map)
- `test/gas/AdvanceGasCeiling.sol:101` (named in map)
- `test/gas/AdvanceStageWorstCaseGas.t.sol:45` — **NOT in map (missed)**
- `test/gas/GameOverCompositionAdvanceGas.t.sol:75` — **NOT in map (missed)**
- Sweep ALL of: the `.t.sol`/`.sol` set under `test/fuzz/`, `test/gas/` that references any renamed production identifier as code (full build catches these — `forge build` must be green).

**(b) Runtime-break — JS by-name string assertions (forge/`forge build` does NOT catch; only the JS test run does):**
- `test/edge/DeityPassGoldNerfRegression.test.js` — `deriveStorageSlot("traitBurnTicket")` ×6 (:441,:552,:666,:790,:1109,:1244) — update the string literal (named in map).
- `test/edge/LootboxAutoResolveRegression.test.js:402,403` — `.includes("ticketsOwedPacked")` source-string assertion — **NOT in map (missed)**.
- `test/edge/MintCleanupRegression.test.js:550,553` — storage-layout-by-name `cells[k] === "ticketsOwedPacked"` — **NOT in map (missed)**.
- The planner must `rg` `test/` for each renamed name as a quoted string / `.includes(` / `=== "` / regex literal and update every hit, then run the FULL Hardhat suite (these only surface at runtime).

**(c) Comment-only refs in `.t.sol`/`.test.js`/`.mjs`** (no break, update for consistency per repo comment rules): `MintModuleDivergenceAcrossSplit.t.sol` (slot-8 hardcoder — comment refresh, the slot-8 *number* survives since layout is stable), `randTraitTicketRef.mjs`, `Phase264GasRegression.test.js`, `MintBatchDeterminism.test.js`, `DegenerusJackpots.test.js`, `PerPullEmptyBucketSkip.test.js`, etc.

---

## 7. Validation Architecture (Nyquist Dimension 8)

| Requirement | Validation signal (sampling > Nyquist) |
|---|---|
| RN-01 (`traitBurnTicket`→`lvlTraitEntry`, incl. 2 `.slot`) | `forge build` green; `! rg traitBurnTicket contracts/`; layout golden `--check` green (label-only) |
| RN-02 (`ticketsOwedPacked`→`entriesOwedPacked`) | `! rg ticketsOwedPacked contracts/`; layout `--check` green |
| RN-03 (sinks + params) | `! rg "_queueTickets\b|_queueTicketsScaled\b|_queueTicketRange\b" contracts/`; `_queueEntries`/`_queueEntriesScaled`/`_queueEntryRange` present; compile green |
| RN-04 (constants, values unchanged) | new names present; `rg "= 40;|= 2;|= 4;|= 16;"` values intact at the decl sites; layout `--check` green |
| RN-05 (`_budgetToEntries` + entries locals + scaled-whole disambig) | `! rg _budgetToTicketUnits contracts/`; no `TicketUnits` local remains; bug-site scaled locals carry `wholeTickets`; compile green |
| RN-06 (Decimator record) | `DecEntry`/`TerminalDecEntry`/`_decClaimableFromEntry` gone; "entry point" comments intact (`rg "Entry Points"` still present); layout `--check` green |
| RN-07 (harness lockstep) | `forge build` green (compile-break set); FULL Hardhat suite green (runtime by-name set); no renamed literal remains as a stale string in `test/` |
| No-behavior-change (global) | layout golden `--check` label-only; Bernoulli/EV testers green UNCHANGED; full forge+Hardhat ≥ the 479-close floor |

## 8. File / symbol reference (for `<read_first>`)

| File | Why |
|---|---|
| `contracts/storage/DegenerusGameStorage.sol` | decls: `traitBurnTicket`:472, `ticketsOwedPacked`:524, sinks :641/:690/:742, `wholeTicketsToEntries`:680, `DecEntry`:1833/`decBurn`:1866, `TerminalDecEntry`:1939/`terminalDecEntries`:1947; bitfield comment labels :437-438 |
| `contracts/modules/DegenerusGameJackpotModule.sol` | `traitBurnTicket_` param + refs; `_budgetToTicketUnits`:705 + `*TicketUnits` locals; bug-site `quantityScaled`/`scaledTickets` :2127-2135 |
| `contracts/modules/DegenerusGameLootboxModule.sol` | bug-site `scaledTickets`/`countScaled` :1356-1402,:2176-2186 |
| `contracts/modules/DegenerusGameMintModule.sol` | `traitBurnTicket.slot` :569; `ticketsOwedPacked` :336/:640/:1252-1265; `_queueTicketsScaled` callers |
| `contracts/modules/DegenerusGameFoilPackModule.sol` | `traitBurnTicket.slot` :782 |
| `contracts/modules/DegenerusGameWhaleModule.sol` | RN-04 constants + `_queueTicketRange`/`_queueTickets` callers |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | `VAULT_PERPETUAL_TICKETS` :131 + `_queueTickets` callers :1620,:1626 |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | RN-06 record renames; "entry point" comments :122,:382 (KEEP) |
| `contracts/modules/DegenerusGameBingoModule.sol`, `DegenerusGame.sol`, `IDegenerusGame*.sol` | `traitBurnTicket`/`ticketsOwedPacked` read refs + NatSpec; genesis `16` :225 |
| `scripts/layout/storage_layout_oracle.sh` + `golden/` | `--capture`/`--check`; ~13 goldens |
| `test/fuzz/JackpotSingleCallCorrectness.t.sol`, `test/gas/AdvanceGasCeiling.sol`, `test/gas/AdvanceStageWorstCaseGas.t.sol`, `test/gas/GameOverCompositionAdvanceGas.t.sol` | compile-break code refs |
| `test/edge/DeityPassGoldNerfRegression.test.js`, `test/edge/LootboxAutoResolveRegression.test.js`, `test/edge/MintCleanupRegression.test.js` | runtime by-name string assertions (forge-invisible) |

## 9. Landmines (condensed)

- **Rename by identifier, never by substring/sed** — `entry`→`record` would corrupt Decimator "entry point" comments (§4); `Tickets`→`Entries` would hit `TicketsQueuedRange`/`JackpotTicketWin` event fields (481 scope) and `AFKING_TICKET_SCALE` (keep).
- **`.slot` reads bind by name** — the 2 inline-asm sites update automatically when the variable is renamed; verify they read `lvlTraitEntry.slot` and the slot number is unchanged (layout golden).
- **Storage layout is the hard floor** — `--check` must be label-only. Any slot/offset/type move = a rename hit logic; STOP.
- **Bernoulli/EV testers stay GREEN UNCHANGED** — a rename must not require editing `test/stat/*BernoulliEv*` or `contracts/test/*BernoulliTester.sol` logic (NatSpec mirrors may update; expressions byte-identical).
- **No event/value/selector changes** — 481 owns events; leave `ticketCount`/`futureTickets`/`TicketsQueued.quantity`/`TicketsQueuedRange.ticketsPerLevel` field names and all emitted values as 479 left them.
- **The test sweep is the 479-FIX-05 trap** — forge green ≠ done. Grep `test/` for every old literal as a string; run the FULL Hardhat suite (runtime by-name class).
- **Comments describe what IS** — no "renamed from"/history; no phase/plan IDs in `contracts/*.sol` (repo rule).
- **Contract-commit gate** — the `.sol` rename hunk is ONE batched diff for USER approval before commit (success criterion 5). `.sol` edits + all golden/test commits are autonomous.
