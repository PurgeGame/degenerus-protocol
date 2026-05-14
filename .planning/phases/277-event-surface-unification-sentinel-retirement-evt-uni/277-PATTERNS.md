# Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI) - Pattern Map

**Mapped:** 2026-05-14
**Files analyzed:** 3 contract files modified + test files (new)
**Analogs found:** 3 / 3 (all in-file precedent + Phase 274/275/276 test precedent)

> Authoritative source: `277-CONTEXT.md` "Implementation Decisions" only.
> ROADMAP.md / REQUIREMENTS.md EVT-UNI-02/-03/-06 texts are STALE and OVERRIDDEN.
> No RESEARCH.md — mechanical event-surface refactor, research intentionally skipped.

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `contracts/modules/DegenerusGameLootboxModule.sol` | module (event defs + resolution logic) | event-driven / transform | itself — Phase 275 hoisted Bernoulli locals (`:1038-1044`) pre-stage this retirement; sibling event defs `:100-132` | exact (in-file precedent) |
| `contracts/modules/DegenerusGameJackpotModule.sol` | module (event def + 3 emit sites + roll fn) | event-driven / transform | `DegenerusGameLootboxModule._resolveLootboxCommon` Bernoulli `roundedUp` capture (`:1041-1044`) | role-match (cross-module Bernoulli pattern) |
| `contracts/interfaces/IDegenerusGameModules.sol` | interface (event mirror) | declaration-only | sibling event defs in same `IDegenerusGameLootboxModule` block | exact (deletion only) |
| Test files (new) — see Test Pattern section | test | source-structural + tester-direct | `test/unit/LootboxWholeTicket.test.js`, `test/edge/LootboxAutoResolveRegression.test.js`, `test/unit/JackpotTicketRollSilentColdBust.test.js` | exact (Phase 274/275/276 precedent) |

## Pattern Assignments

### `contracts/modules/DegenerusGameLootboxModule.sol` (module, event-driven/transform)

**Analog:** itself — sibling events + Phase-275-hoisted Bernoulli locals.

---

#### Change 1 — DELETE `LootboxTicketRoll` event def (EVT-UNI-01)

**Target:** `:134-159` (NatSpec block + event def). Delete entirely — no emission sites remain after Change 5.

Current (to delete):
```solidity
/// @notice Emitted on a manual lootbox open that resolved on the ticket-path with a
///         non-zero pre-Bernoulli scaled ticket count. ...
event LootboxTicketRoll(
    address indexed player,
    uint48 indexed lootboxIndex,
    uint32 preRollTickets,
    bool roundedUp
);
```

---

#### Change 2 — RESTRUCTURE `LootBoxOpened` (EVT-UNI-02, D-277-EVT-WIDE-01, D-277-ROUNDEDUP-01)

**Target:** `:58-74` (NatSpec + event def).

Current def (note 2nd field named `index` but the emit at `:1081-1089` passes `day`):
```solidity
event LootBoxOpened(
    address indexed player,
    uint32 indexed index,        // MISLABEL: emit passes `day`
    uint256 amount,
    uint24 futureLevel,
    uint32 futureTickets,
    uint256 burnie,
    uint256 bonusBurnie
);
```

Required changes:
- Fix the mislabel: split into a real `lootboxIndex` + a separate `day` field.
- Add `bool roundedUp` (the ONLY new field — `preRollTickets` is NOT added per D-277-NO-PREROLL-01).
- Fields stay WIDE: `amount`, `burnie`, `bonusBurnie` stay `uint256` wei. NO `uint32`/`uint16` narrowing (D-277-EVT-WIDE-01 REJECTS EVT-UNI-02's literal signature). `futureLevel`/`futureTickets` keep current `uint24`/`uint32`.
- **Planner discretion:** `lootboxIndex` indexed-topic vs. data-field; whether `day` is a 3rd indexed topic (+375 gas); final field order. Manual `openLootBox` is NOT on the advanceGame chain — lower-stakes. Sibling-event indexed-topic convention to copy from `:100-108` (`LootBoxWhalePassJackpot` indexes `player` + `day`):
  ```solidity
  event LootBoxWhalePassJackpot(
      address indexed player,
      uint32 indexed day,
      uint256 lootboxAmount,
      ...
  );
  ```

**Emit site (Change 2b):** `:1080-1090`. Current emit passes `day` into the `index`-named slot:
```solidity
if (emitLootboxEvent) {
    emit LootBoxOpened(
        player,
        day,                 // currently lands in the mislabeled `index` slot
        amount,
        targetLevel,
        futureTickets,       // scaled pre-Bernoulli — stays as-is
        burnieAmount,
        bonusBurnie
    );
}
```
After restructure: pass a real `index` (the `uint48 index` param, now event-identifier only), `day`, and `roundedUp` (the live local from `:1041-1044`). Values fed wide as `uint256` wei — NO `/ 1 ether` divisions in the hot path.

---

#### Change 3 — ADD `bool roundedUp` to `BurnieLootOpen` (EVT-UNI-03, D-277-NO-PREROLL-01)

**Target def:** `:76-90`. Add ONLY `bool roundedUp`; `preRollTickets` NOT added; existing fields unchanged.
```solidity
event BurnieLootOpen(
    address indexed player,
    uint32 indexed index,
    uint256 burnieAmount,
    uint24 ticketLevel,
    uint32 tickets,
    uint256 burnieReward
    // + bool roundedUp
);
```

**Emit site (Change 3b):** `:688-695` in `openBurnieLootBox`. `_resolveLootboxCommon` must surface `roundedUp` to this caller — it currently returns `(uint32 futureTickets, uint256 burnieAmount, uint256 bonusBurnie)` at `:922-926`. `openBurnieLootBox` already destructures the tuple at `:671` (`(uint32 tickets, uint256 burnieReward, )`). Planner finalizes the threading mechanism (extend the return tuple, or thread differently). Current emit:
```solidity
emit BurnieLootOpen(
    player,
    uint32(index),
    burnieAmount,
    targetLevel,
    tickets,
    burnieReward
);
```

---

#### Change 4 — RETIRE the `index != type(uint48).max` sentinel branch (EVT-UNI-05)

**Target:** `:1046-1066` inside the `if (futureTickets != 0)` block.

The Phase-275-hoisted shared Bernoulli locals at `:1038-1044` stay (D-275-HOIST-01) — they already sit OUTSIDE the sentinel gate:
```solidity
uint32 scaledPre = futureTickets;
uint32 whole = futureTickets / uint32(TICKET_SCALE);
uint32 frac = futureTickets % uint32(TICKET_SCALE);
bool roundedUp = false;
if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
    unchecked { whole += 1; }
    roundedUp = true;
}
```

Current sentinel branch (to retire):
```solidity
if (index != type(uint48).max) {
    // Manual path
    if (whole != 0) {
        _queueTickets(player, targetLevel, whole, false);
    } else {
        wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
        emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
    }
    emit LootboxTicketRoll(player, index, scaledPre, roundedUp);   // DELETE — EVT-UNI-01
} else {
    // Auto-resolve path
    _queueTickets(player, targetLevel, whole, false);
}
```

Post-retirement structure (D-277-CONSOLATION-GATE-01, D-277-AR-SILENT-01):
- Unconditional `_queueTickets(player, targetLevel, whole, false)` — early-returns on `whole == 0` (silent auto-resolve cold-bust). Confirmed: `_queueTickets` at `DegenerusGameStorage.sol:562` early-returns on `quantity == 0`, emits `TicketsQueued` unconditionally otherwise.
- Manual cold-bust consolation (`whole == 0` → `wwxrp.mintPrize` + `LootBoxWwxrpReward`) moves under the existing `if (emitLootboxEvent)` gate — joining the `LootBoxOpened` emit at `:1080`. `emitLootboxEvent` is already `true` for both manual callers, `false` for both auto-resolve callers — 1:1 with the consolation asymmetry. No new parameter.
- Delete the `emit LootboxTicketRoll` line — zero remaining emission sites (satisfies EVT-UNI-01).
- No leftover unreachable branch (`feedback_no_dead_guards.md`).

---

#### Change 5 — Auto-resolve callers stop passing the sentinel (EVT-UNI-05, EVT-UNI-06, D-277-AR-INDEX-01, D-277-AR-SILENT-01)

**Targets:** `resolveLootboxDirect` `:714-729` and `resolveRedemptionLootbox` `:750-765`. Both currently pass `type(uint48).max` as the `index` arg:
```solidity
_resolveLootboxCommon(
    player,
    day,
    type(uint48).max,      // → change to 0 (D-277-AR-INDEX-01: clean default; gates nothing, emitted nowhere)
    scaledAmount,
    targetLevel,
    currentLevel,
    seed,
    false,
    true,
    true,
    true,        // emitLootboxEvent stays false — see below
    false,       // <-- emitLootboxEvent (this is the 4th bool, value `false`)
    0,
    0
);
```
> NOTE: confirm exact arg position — the `_resolveLootboxCommon` signature at `:905-920` is `(player, day, index, amount, targetLevel, currentLevel, seed, presale, allowWhalePass, allowLazyPass, emitLootboxEvent, allowBoons, distressEth, totalPackedEth)`. Auto-resolve callers keep `emitLootboxEvent = false` → emits NO `LootBoxOpened` (D-277-AR-SILENT-01). Only the `index` arg changes: `type(uint48).max` → `0`.

Manual callers `openLootBox` (`:616-631`) and `openBurnieLootBox` (`:671-686`) already pass a real `index` and `emitLootboxEvent = true` — UNCHANGED.

---

#### Change 6 — NatSpec / comment cleanup (Claude's Discretion in CONTEXT.md)

Per `feedback_no_history_in_comments.md` — describe what IS, never what changed:
- `:865-875` — `_resolveLootboxCommon` `@param index` NatSpec: drop the sentinel/dual-purpose description; `index` is event-identifier only on the manual `LootBoxOpened` emit.
- `:898` — `@param emitLootboxEvent` NatSpec: now gates `LootBoxOpened` emit AND the manual cold-bust consolation.
- `:1030-1037`, `:1046-1053`, `:1061-1064` — inline comments referencing the sentinel and `LootboxTicketRoll` — delete/rewrite.
- `:880-892` — bit-allocation NatSpec: `bits[152..167]` still consumed on both paths (D-275-NATSPEC-01 already covers this — verify still accurate, no edit if so).
- `LootBoxOpened` / `BurnieLootOpen` event-doc NatSpec — update `@param` list for the new/renamed fields.

---

### `contracts/modules/DegenerusGameJackpotModule.sol` (module, event-driven/transform)

**Analog:** `DegenerusGameLootboxModule._resolveLootboxCommon` `roundedUp` capture pattern at `:1041-1044`.

---

#### Change 7 — ADD `bool roundedUp` to `JackpotTicketWin` (EVT-UNI-04, D-277-ROUNDEDUP-01)

**Target def:** `:87-94` (NatSpec at `:79-86`). `traitId` is already the 3rd indexed topic → `roundedUp` MUST be non-indexed data.
```solidity
event JackpotTicketWin(
    address indexed winner,
    uint24 indexed ticketLevel,
    uint16 indexed traitId,
    uint32 ticketCount,
    uint24 sourceLevel,
    uint256 ticketIndex
    // + bool roundedUp  (non-indexed)
);
```

---

#### Change 8 — Capture `roundedUp` in `_jackpotTicketRoll` + thread to emit (EVT-UNI-04)

**Target:** `:2232-2253`. The Bernoulli predicate currently has NO `roundedUp` bool — `if (...) { whole += 1; }` bare. Apply the SAME capture shape as `DegenerusGameLootboxModule.sol:1041-1044`:

Current:
```solidity
uint32 scaledTickets = uint32(quantityScaled);
uint32 whole = scaledTickets / uint32(TICKET_SCALE);
uint32 frac = scaledTickets % uint32(TICKET_SCALE);
if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) {
    unchecked {
        whole += 1;
    }
}
_queueTickets(winner, targetLevel, whole, true);
...
emit JackpotTicketWin(
    winner,
    targetLevel,
    BAF_TRAIT_SENTINEL,
    uint32(quantityScaled),
    minTargetLevel,
    0
    // + roundedUp
);
```
Required: add `bool roundedUp = false;` before the predicate, set `roundedUp = true;` inside the `if` (mirror the Lootbox pattern), thread it as the new `JackpotTicketWin` arg. Planner finalizes capture mechanics.

#### Change 9 — Trait-matched emit sites pass `roundedUp = false` (EVT-UNI-04)

**Targets:** `:705-712` (bonus-trait path) and `:1008-1015` (near/far-future coin path). Both award integer `ticketCount`/`units` then emit a scaled `× TICKET_SCALE` value — zero fractional part by construction → pass `false`.
```solidity
// :705
emit JackpotTicketWin(winner, lvl, traitId, ticketCount * uint32(TICKET_SCALE), lvl, ticketIndexes[i] /* , false */);
// :1008
emit JackpotTicketWin(winner, queueLvl, traitId, uint32(units * TICKET_SCALE), sourceLvl, ticketIndexes[i] /* , false */);
```

> advanceGame-chain note: `JackpotTicketWin` is emitted on the advanceGame chain (`_jackpotTicketRoll` runs in the advanceGame window per Phase 276). The +1 data word is unavoidable — `roundedUp` is genuinely new information — but it is the minimum addition.

---

### `contracts/interfaces/IDegenerusGameModules.sol` (interface, declaration-only)

**Analog:** sibling event defs in the same `IDegenerusGameLootboxModule` interface block.

#### Change 10 — DELETE `LootboxTicketRoll` from the interface (EVT-UNI-01)

**Target:** `:267-281` — the NatSpec block + `event LootboxTicketRoll(...)` def inside the `IDegenerusGameLootboxModule` interface (`:264-...`). Delete entirely.
> NOTE: roadmap/requirements call this file `IDegenerusGameLootboxModule.sol`; the interface actually lives in `IDegenerusGameModules.sol`.
> The interface block does NOT mirror `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` — those live only on the contracts — so no interface edits are needed for Changes 2/3/7. Confirm via grep that the interface declares only `LootboxTicketRoll`.

## Shared Patterns

### Bernoulli `roundedUp` capture
**Source:** `contracts/modules/DegenerusGameLootboxModule.sol:1038-1044`
**Apply to:** `DegenerusGameJackpotModule._jackpotTicketRoll` (`:2232-2239`)
```solidity
uint32 whole = scaled / uint32(TICKET_SCALE);
uint32 frac  = scaled % uint32(TICKET_SCALE);
bool roundedUp = false;
if (frac != 0 && (uint16(seed >> SLICE) % uint16(TICKET_SCALE)) < uint16(frac)) {
    unchecked { whole += 1; }
    roundedUp = true;
}
```
The Lootbox path uses `seed >> 152`; the Jackpot path uses `entropy >> 200`. Only the `roundedUp` flag is new in JackpotModule — math is byte-identical otherwise.

### `emitLootboxEvent` as the manual-vs-auto gate
**Source:** `contracts/modules/DegenerusGameLootboxModule.sol:1080` (`if (emitLootboxEvent)`)
**Apply to:** Change 4 — the manual cold-bust consolation moves under this same gate. `emitLootboxEvent` is already `true`/`false` 1:1 with manual/auto-resolve callers; no new parameter, no decoupling.

### Wide event fields — no narrowing, no `/ 1 ether`
**Source:** D-277-EVT-WIDE-01 Key Premise — event non-indexed data fields are ABI-encoded as full 32-byte words regardless of declared type; narrowing saves zero `LOG` gas.
**Apply to:** `LootBoxOpened.amount/burnie/bonusBurnie` stay `uint256` wei. Sibling events (`LootBoxDgnrsReward`, `LootBoxWwxrpReward` at `:115-132`) already use `uint256` for token amounts — consistent precedent.

### Indexed-topic convention
**Source:** `LootBoxWhalePassJackpot` (`:100-108`) and `LootBoxDgnrsReward` (`:115-120`) — both index `player` + `day`.
**Apply to:** `LootBoxOpened` restructure (Change 2) — planner's `lootboxIndex`/`day` indexed-vs-data decision should weigh this sibling convention.

## Test Pattern

The Phase 274/275/276 precedent is **source-structural assertions + tester-direct EV proofs** (no full end-to-end fixture for the resolution paths — documented fixture-coverage gap). Test directory layout: `test/stat/`, `test/edge/`, `test/unit/` (no `test/regression/` dir exists despite the name — regression tests live in `test/edge/` and `test/unit/`).

**Planner reconciles:** Phase 275/276 precedent (`test/stat/` + `test/edge/` + `test/unit/`) vs. REQUIREMENTS.md §TST-EVT-UNI suggestion (`test/lootbox/` + `test/jackpot/` + `test/regression/`). The on-disk precedent is the established pattern.

### Analog: `test/edge/LootboxAutoResolveRegression.test.js` — source-structural proof idiom
For "event X no longer emitted / no longer declared" properties (EVT-UNI-01, EVT-UNI-05):
```js
const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
const emits = (source.match(/emit LootboxTicketRoll\(/g) || []).length;
expect(emits).to.equal(0);
```
The existing TST-REG-03 block at `:243-262` already asserts `emit LootboxTicketRoll` count and `wwxrp.mintPrize`+`LootBoxWwxrpReward` placement — Phase 277 updates these assertions (`LootboxTicketRoll` count goes 1→0; consolation moves from the sentinel branch to the `emitLootboxEvent` gate).

### Analog: `test/unit/LootboxWholeTicket.test.js` — tester-direct + drift-detection grep
`LootboxBernoulliTester` is a stand-alone `external pure` mirror of the manual-branch arithmetic; a source-grep test asserts production contains the exact instruction sequence. For Phase 277: the sentinel retirement changes the branch structure around the (unchanged) Bernoulli math — update the drift-grep patterns to match the post-retirement source.

### Analog: `test/unit/JackpotTicketRollSilentColdBust.test.js` — already flags Phase 277
This file's header explicitly states: *"Phase 277 EVT-UNI-04 adds the `roundedUp` field; the Phase 277 test wave updates that assertion."* `JackpotBernoulliTester` mirrors the inline `_jackpotTicketRoll` Bernoulli — extend it / its drift-grep for the new `roundedUp` capture. The silent-cold-bust scope (queue surface) is unchanged; only `JackpotTicketWin`'s signature gains `roundedUp`.

### Topic-hash change tests (TST-EVT-UNI)
Breaking event topic-hashes are accepted (D-40N-EVT-BREAK-01 / EVT-UNI-08). Tests should assert the NEW signatures (`LootBoxOpened`, `BurnieLootOpen`, `JackpotTicketWin`) and the absence of `LootboxTicketRoll` from both the contract and `IDegenerusGameModules.sol`.

## No Analog Found

None. Every change has either in-file precedent (Phase 275 hoisted locals, sibling event defs) or cross-module/cross-phase precedent (Phase 274/275/276 test idioms).

## Metadata

**Analog search scope:** `contracts/modules/`, `contracts/interfaces/`, `contracts/storage/`, `test/stat/`, `test/edge/`, `test/unit/`
**Files scanned:** 3 contract files (targeted reads of all change sites per CONTEXT.md `<canonical_refs>`), 4 precedent test files, test directory listing
**Pattern extraction date:** 2026-05-14
**Authority note:** built exclusively on `277-CONTEXT.md` "Implementation Decisions" (D-277-EVT-WIDE-01, D-277-NO-PREROLL-01, D-277-AR-SILENT-01, D-277-ROUNDEDUP-01, D-277-CONSOLATION-GATE-01, D-277-AR-INDEX-01). ROADMAP.md/REQUIREMENTS.md EVT-UNI-02/-03/-06 texts are stale and were NOT used.
