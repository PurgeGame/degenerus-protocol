# Phase 277: Event Surface Unification + Sentinel Retirement (EVT-UNI) - Pattern Map

**Mapped:** 2026-05-14
**Files analyzed:** 3 source modified + ~3-5 test files (new + updated; planner reconciles)
**Analogs found:** 3 / 3 source files (all analogs are in-file siblings or prior-phase commits)

This is a mechanical event-surface refactor — no RESEARCH.md (skipped per
`feedback_skip_research_test_phases.md`). Every pattern below is an **in-file sibling**
(another event in the same module, another emit site of the same event) or a
**prior-phase commit** (Phase 274 introduced `LootboxTicketRoll` + the sentinel;
Phase 275 hoisted the Bernoulli math OUTSIDE the sentinel gate, pre-staging this
retirement; Phase 276 mirrored it onto the jackpot surface). The closest analogs are
literally the lines being deleted/restructured plus their already-committed siblings.

The planner should treat:
- **`LootBoxWwxrpReward` / `LootBoxDgnrsReward` / `BurnieLootOpen`** (`DegenerusGameLootboxModule.sol:83-132`) as the **event-definition style template** (NatSpec `@param` per field, `indexed` placement).
- **The Phase 275 committed `_resolveLootboxCommon` hoist** (`b6ed8fce`, current `DegenerusGameLootboxModule.sol:1038-1066`) as the **sentinel-retirement template** — the `if (index != type(uint48).max)` gate at `:1046` is the deletion target; the shared locals at `:1038-1045` already survive it.
- **`test/unit/LootboxWholeTicket.test.js`** (Phase 274 TST-WT, currently 740 lines) as the **event-structural-test template** AND a **mandatory update target** — its TST-WT-06/07 blocks assert `LootboxTicketRoll` exists; they break when EVT-UNI-01 deletes it.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `contracts/modules/DegenerusGameLootboxModule.sol` (event defs `LootBoxOpened` `:66-74` / `BurnieLootOpen` `:83-90`, DELETE `LootboxTicketRoll` `:134-159`; `_resolveLootboxCommon` body `:1020-1091`; 4 callers `:559` `:671` `:704` `:739`) | module / contract logic | event-emit + transform (scaled→whole collapse) | in-file: sibling events `:83-132`, Phase-275-committed hoist `:1038-1066` | exact (in-file sibling + prior-phase commit) |
| `contracts/modules/DegenerusGameJackpotModule.sol` (event def `JackpotTicketWin` `:87-94`; 3 emit sites `:705` `:1008` `:2246`; `_jackpotTicketRoll` `roundedUp` capture `:2232-2239`) | module / contract logic | event-emit + transform | in-file: sibling event `JackpotBurnieWin` `:97+`, the 2 trait-matched emit sites `:705`/`:1008`, the Phase-276-committed Bernoulli block `:2229-2240` | exact (in-file sibling + prior-phase commit) |
| `contracts/interfaces/IDegenerusGameModules.sol` (DELETE `LootboxTicketRoll` event `:276-281` from `IDegenerusGameLootboxModule` block) | interface | event-declaration | in-file: the contract-level `LootboxTicketRoll` def at `DegenerusGameLootboxModule.sol:154-159` (must delete in lock-step) | exact (mirror declaration) |
| `test/unit/LootboxWholeTicket.test.js` (UPDATE — TST-WT-06/07 reference deleted `LootboxTicketRoll`) | test (unit / structural) | request-response (emit presence/absence + field consistency) | itself (Phase 274 TST-WT); Phase 275 updated it in `bb1b1abd` | exact (self; prior-phase precedent for updating it) |
| `test/unit/` or `test/edge/` event-topic-hash + field-consistency tests (new — TST-EVT-UNI-01..06) | test (unit + edge / structural) | request-response (topic-hash, emit-absence, field consistency) | `test/unit/LootboxWholeTicket.test.js` (full; structural-grep idiom) + `test/unit/LootboxAutoResolveSilentColdBust.test.js` + `test/unit/LootboxAutoResolveRemByte.test.js` | role-match (structural-proof idiom) |

> **Test placement:** `test/regression/` does NOT exist on disk. `test/` has:
> `access deploy edge fuzz gas governance halmos helpers integration stat unit validation`.
> REQUIREMENTS.md §TST-EVT-UNI suggests `test/lootbox/` + `test/jackpot/` + `test/regression/` —
> none exist. Phase 275/276 precedent: structural + silent-cold-bust + regression →
> `test/unit/`; heavy-MC + chi-square → `test/stat/`; boundary → `test/edge/`.
> Planner should follow the Phase 275/276 placement scheme (`test/unit/` + `test/edge/`),
> NOT create new top-level dirs. The existing `LootboxWholeTicket.test.js` /
> `LootboxConsolation.test.js` already live in `test/unit/`.

## Pattern Assignments

### `contracts/modules/DegenerusGameLootboxModule.sol` (module — event defs + `_resolveLootboxCommon` + 4 callers)

**Analogs:** in-file sibling events (`:83-132`); the Phase 275 committed `_resolveLootboxCommon` hoist (`b6ed8fce`, current `:1038-1066`).

#### EVT-UNI-01 — DELETE `LootboxTicketRoll` event def + NatSpec

**Deletion target** (`DegenerusGameLootboxModule.sol:134-159`):
```solidity
    /// @notice Emitted on a manual lootbox open that resolved on the ticket-path with a
    ///         non-zero pre-Bernoulli scaled ticket count. Exposes the pre-collapse scaled
    ///         ... (26-line NatSpec block) ...
    event LootboxTicketRoll(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint32 preRollTickets,
        bool roundedUp
    );
```
Delete the entire `:134-159` block (NatSpec + event). The only emit site is `:1060`
(removed by EVT-UNI-05) — after that, zero remaining references. Mirror-delete the
interface copy (see `IDegenerusGameModules.sol` section below).

#### EVT-UNI-02 — restructure `LootBoxOpened`

**Current def (the mislabel target)** (`DegenerusGameLootboxModule.sol:58-74`):
```solidity
    /// @notice Emitted when an ETH lootbox is successfully opened
    /// @param player The player who opened the lootbox
    /// @param index The day index when the lootbox was opened   // <-- field NAMED index, emits day
    /// @param amount The ETH amount of the lootbox
    /// @param futureLevel The target level for future tickets
    /// @param futureTickets The number of future tickets awarded
    /// @param burnie The total BURNIE tokens awarded
    /// @param bonusBurnie The bonus BURNIE from presale multiplier
    event LootBoxOpened(
        address indexed player,
        uint32 indexed index,        // <-- mislabel: emit at :1081 passes `day`
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint256 burnie,
        uint256 bonusBurnie
    );
```

**Event-definition style template** — copy the `indexed` placement + per-field
`@param` NatSpec discipline from the sibling `BurnieLootOpen` (`:76-90`):
```solidity
    /// @notice Emitted when a BURNIE lootbox is successfully opened
    /// @param player The player who opened the lootbox
    /// @param index The RNG index of the lootbox
    /// @param burnieAmount The BURNIE amount used to open the lootbox
    /// @param ticketLevel The target level for tickets
    /// @param tickets The number of tickets awarded
    /// @param burnieReward The BURNIE reward amount
    event BurnieLootOpen(
        address indexed player,
        uint32 indexed index,
        uint256 burnieAmount,
        uint24 ticketLevel,
        uint32 tickets,
        uint256 burnieReward
    );
```

**Restructured `LootBoxOpened` per EVT-UNI-02 + D-277 overrides** — separate the
fused `index`/`day`, add a real indexed `lootboxIndex`, add `(uint32 preRollTickets,
bool roundedUp)`; `burnie`/`bonus` → whole-token `uint32` (D-277-EVT-WHOLE-BURNIE-01 +
D-277-BONUS-WIDTH-01); `amount` stays wei `uint128`. Field order is **planner
discretion** (CONTEXT.md §Claude's Discretion). Shape:
```solidity
    event LootBoxOpened(
        address indexed player,
        uint48 indexed lootboxIndex,   // real index (NOT day); auto-resolve passes 0 — D-277-AR-INDEX-01
        uint48 day,                    // split out of the old fused field
        uint128 amount,                // stays WEI (uint128 has headroom — D-277-EVT-WHOLE-BURNIE-01)
        uint24 futureLevel,
        uint32 preRollTickets,         // pre-Bernoulli scaled count (= old LootboxTicketRoll.preRollTickets)
        bool roundedUp,                // = old LootboxTicketRoll.roundedUp
        uint32 burnie,                 // WHOLE-token count: burnieAmount / 1 ether — D-277-EVT-WHOLE-BURNIE-01
        uint32 bonus                   // WHOLE-token count, uint32 NOT uint16 — D-277-BONUS-WIDTH-01
    );
```
> The NatSpec must document the unit semantics explicitly (whole-token vs wei) per
> `feedback_no_history_in_comments.md` — describe what IS. The `LootboxTicketRoll`
> 26-line NatSpec at `:134-159` has good wording for `preRollTickets`/`roundedUp`
> derivation (`(preRollTickets / 100) + (roundedUp ? 1 : 0)`) — fold that into the
> `LootBoxOpened` NatSpec rather than discarding it.

#### EVT-UNI-03 — add 2 fields to `BurnieLootOpen`

Append `(uint32 preRollTickets, bool roundedUp)` to the `:83-90` def above; existing
fields **unchanged** (`burnieAmount`/`burnieReward` stay wei `uint256` — deliberate
asymmetry vs `LootBoxOpened`, CONTEXT.md §Claude's Discretion + §deferred. If the
planner thinks the asymmetry is wrong, FLAG to user — do NOT silently widen scope).

#### EVT-UNI-05 — retire the `index != type(uint48).max` sentinel in `_resolveLootboxCommon`

**The sentinel branch to retire** (`DegenerusGameLootboxModule.sol:1020-1067`):
```solidity
        if (futureTickets != 0) {
            // Distress-mode ticket bonus ... (:1021-1029, UNCHANGED)
            // --- Phase 275 hoisted shared locals (D-275-HOIST-01) — survive the retirement ---
            uint32 scaledPre = futureTickets;
            uint32 whole = futureTickets / uint32(TICKET_SCALE);
            uint32 frac = futureTickets % uint32(TICKET_SCALE);
            bool roundedUp = false;
            if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
                unchecked { whole += 1; }
                roundedUp = true;
            }
            if (index != type(uint48).max) {                       // <-- :1046 SENTINEL — DELETE this gate
                if (whole != 0) {
                    _queueTickets(player, targetLevel, whole, false);
                } else {
                    wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
                    emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
                }
                emit LootboxTicketRoll(player, index, scaledPre, roundedUp);   // <-- DELETE (EVT-UNI-01)
            } else {
                _queueTickets(player, targetLevel, whole, false);   // <-- auto-resolve else-arm
            }
        }
```

**Post-retirement shape** — the sentinel gated TWO things; EVT-UNI-01 removes the
`LootboxTicketRoll` emit; D-277-CONSOLATION-GATE-01 moves the cold-bust consolation
to the existing `emitLootboxEvent` parameter. Collapsed:
```solidity
        if (futureTickets != 0) {
            // ... distress bonus (unchanged) ...
            uint32 scaledPre = futureTickets;          // feeds LootBoxOpened/BurnieLootOpen.preRollTickets
            uint32 whole = futureTickets / uint32(TICKET_SCALE);
            uint32 frac = futureTickets % uint32(TICKET_SCALE);
            bool roundedUp = false;                    // feeds LootBoxOpened/BurnieLootOpen.roundedUp
            if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
                unchecked { whole += 1; }
                roundedUp = true;
            }
            if (whole != 0) {
                _queueTickets(player, targetLevel, whole, false);
            } else if (emitLootboxEvent) {             // D-277-CONSOLATION-GATE-01: emitLootboxEvent
                wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);   //  = "manual, player-initiated open"
                emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
            }
            // (whole == 0 && !emitLootboxEvent) → silent cold-bust — D-40N-SILENT-01
        }
```
> **Exact wiring is planner discretion** — the sketch above is one valid shape.
> Hard constraints: (1) auto-resolve cold-bust stays silent (no consolation), (2)
> `scaledPre`/`roundedUp` must remain live for the `LootBoxOpened`/`BurnieLootOpen`
> emits, (3) no leftover unreachable branch (`feedback_no_dead_guards.md`).
> The `index` parameter keeps ONLY its event-identifier role — `_resolveLootboxCommon`
> NatSpec at `:865-892` must be rewritten to drop the "dual-purpose sentinel" language
> (`feedback_no_history_in_comments.md`).

#### `LootBoxOpened` emit site + the `emitLootboxEvent` gate (`:1069-1091`)

```solidity
        burnieAmount = burnieNoMultiplier + burniePresale;
        bonusBurnie = 0;
        if (presale && burniePresale != 0) {
            bonusBurnie = (burniePresale * LOOTBOX_PRESALE_BURNIE_BONUS_BPS) / 10_000;
            burnieAmount += bonusBurnie;
        }
        if (burnieAmount != 0) { coinflip.creditFlip(player, burnieAmount); }

        if (emitLootboxEvent) {                  // <-- :1080 gate — currently gates ONLY this emit
            emit LootBoxOpened(
                player, day, amount, targetLevel, futureTickets, burnieAmount, bonusBurnie
            );
        }
        return (futureTickets, burnieAmount, bonusBurnie);
```
The restructured emit must supply the new fields: `lootboxIndex` (the `index` param),
`preRollTickets` (`scaledPre`), `roundedUp`, `burnie = burnieAmount / 1 ether`,
`bonus = bonusBurnie / 1 ether`. Note `scaledPre`/`roundedUp` are declared inside the
`if (futureTickets != 0)` block — they must be **hoisted to function scope** (default
`0` / `false`) so the `LootBoxOpened` emit below the block can read them. This is a
new hoist beyond Phase 275's.

#### EVT-UNI-06 / D-277-AR-EMIT-01 — auto-resolve `LootBoxOpened` emission

`resolveLootboxDirect` (`:703-730`) and `resolveRedemptionLootbox` (`:739-766`) currently
pass `type(uint48).max` (arg 3) + `false` for `emitLootboxEvent` (arg 11) — see
`:717` / `:753` and `:726` / `:762`. Both must change:
- arg 3 `type(uint48).max` → `0` (D-277-AR-INDEX-01).
- They must now emit `LootBoxOpened` — but **NOT** by flipping `emitLootboxEvent` to
  `true` (that re-enables auto-resolve cold-bust consolation, violating D-40N-SILENT-01).
  **Wiring is planner discretion** (caller-side emit using the `_resolveLootboxCommon`
  return tuple `(futureTickets, burnieAmount, bonusBurnie)`, or a dedicated
  emit-without-consolation code path). The manual `openLootBox` `_resolveLootboxCommon`
  call (`:616-631`) keeps arg 11 `= true`; `openBurnieLootBox` (`:671-686`) keeps `true`.

> **Gas:** D-277-AR-EMIT-01 adds a `LootBoxOpened` `LOGn` to the high-volume
> decimator-claim path. Planner reports the per-op gas delta + bytecode delta in the
> contract commit message (`feedback_gas_worst_case.md`) — derive the theoretical worst
> case FIRST (manual `openLootBox`: `LootboxTicketRoll` LOG3 removal vs. larger
> `LootBoxOpened` payload; plus decimator-claim's new `LootBoxOpened` LOGn), then bench.

---

### `contracts/modules/DegenerusGameJackpotModule.sol` (module — `JackpotTicketWin` def + 3 emit sites + `_jackpotTicketRoll`)

**Analogs:** in-file sibling event `JackpotBurnieWin` (`:97+`); the 2 trait-matched
emit sites (`:705`, `:1008`); the Phase-276-committed Bernoulli block (`:2229-2240`).

#### EVT-UNI-04 — add `bool roundedUp` to `JackpotTicketWin`

**Current def** (`DegenerusGameJackpotModule.sol:79-94`):
```solidity
    /// @dev Ticket jackpot win. See JackpotEthWin for traitId sentinel semantics.
    ///      ticketCount carries the scaled ×TICKET_SCALE (=100) value for all
    ///      paths; ... BAF lootbox rolls (traitId = BAF_TRAIT_SENTINEL)
    ///      Bernoulli-collapse the scaled count to a whole-ticket count ...
    event JackpotTicketWin(
        address indexed winner,
        uint24 indexed ticketLevel,
        uint16 indexed traitId,
        uint32 ticketCount,
        uint24 sourceLevel,
        uint256 ticketIndex
    );
```
Append `bool roundedUp` (field order planner discretion — keep `indexed` topics
first per the in-file convention). Update the `@dev` NatSpec to document `roundedUp`
per `feedback_no_history_in_comments.md` — describe what IS (trait-matched paths emit
`false`; the BAF `_jackpotTicketRoll` path emits the real bool).

#### 3 emit sites — all must supply the new field

**Trait-matched site 1** (`:705-712`) — pass `roundedUp = false`:
```solidity
                        emit JackpotTicketWin(
                            winner, lvl, traitId,
                            ticketCount * uint32(TICKET_SCALE),
                            lvl, ticketIndexes[i]
                        );
```
**Trait-matched site 2** (`:1008-1015`) — pass `roundedUp = false`:
```solidity
                emit JackpotTicketWin(
                    winner, queueLvl, traitId,
                    uint32(units * TICKET_SCALE),
                    sourceLvl, ticketIndexes[i]
                );
```
> Per CONTEXT.md §Claude's Discretion: trait-matched paths have a zero fractional
> part, so `roundedUp = false` is correct for both. Both already carry the
> `// ticketCount emitted scaled ×TICKET_SCALE for UI consistency.` comment — leave
> it; just add the arg.

**BAF `_jackpotTicketRoll` site** (`:2229-2253`) — capture the real `roundedUp`:
```solidity
        // Bernoulli-collapse the scaled count to a whole-ticket count ...
        uint32 scaledTickets = uint32(quantityScaled);
        uint32 whole = scaledTickets / uint32(TICKET_SCALE);
        uint32 frac = scaledTickets % uint32(TICKET_SCALE);
        if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) {
            unchecked { whole += 1; }       // <-- :2236 — currently NO roundedUp bool
        }
        _queueTickets(winner, targetLevel, whole, true);
        ...
        emit JackpotTicketWin(
            winner, targetLevel, BAF_TRAIT_SENTINEL,
            uint32(quantityScaled), minTargetLevel, 0   // <-- :2246 emit — thread roundedUp here
        );
```
**`roundedUp` capture pattern** — mirror the Phase 275 lootbox-surface shape exactly
(`DegenerusGameLootboxModule.sol:1041-1045`): declare `bool roundedUp = false;` above
the predicate, set `roundedUp = true;` inside the `unchecked` block alongside
`whole += 1;`:
```solidity
        uint32 frac = scaledTickets % uint32(TICKET_SCALE);
        bool roundedUp = false;
        if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) {
            unchecked { whole += 1; }
            roundedUp = true;
        }
```
Then pass `roundedUp` to the `:2246` emit. The bit-allocation NatSpec at `:2186-2191`
(`bits[200..215] jackpotTicketRoundUp`) is unchanged — no new slice consumed.

---

### `contracts/interfaces/IDegenerusGameModules.sol` (interface — DELETE `LootboxTicketRoll`)

**Analog:** the contract-level `LootboxTicketRoll` def at
`DegenerusGameLootboxModule.sol:154-159` — the two declarations are mirror copies and
must be deleted in lock-step.

**Deletion target** (`IDegenerusGameModules.sol:267-281`, inside the
`interface IDegenerusGameLootboxModule` block at `:264-`):
```solidity
    /// @notice Emitted on a manual lootbox open whose ticket-path produced non-zero
    ///         pre-Bernoulli scaled tickets. Off-chain consumers derive the awarded
    ///         whole-ticket count as `(preRollTickets / 100) + (roundedUp ? 1 : 0)`
    ///         and infer the WWXRP consolation case as `whole == 0 && preRollTickets > 0`.
    ///         Auto-resolve paths never emit this event.
    /// @param player The player whose lootbox was opened
    /// @param lootboxIndex The per-player storage index of the opened lootbox
    /// @param preRollTickets Post-distress, pre-Bernoulli scaled ticket count
    /// @param roundedUp True iff the Bernoulli round-up incremented the whole-ticket count
    event LootboxTicketRoll(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint32 preRollTickets,
        bool roundedUp
    );
```
Delete the full `:267-281` block. The interface does NOT declare `LootBoxOpened` /
`BurnieLootOpen` / `JackpotTicketWin` (only `LootboxTicketRoll` is mirrored here, plus
the `openLootBox` / `openBurnieLootBox` function selectors at `:283+`), so EVT-UNI-02/03/04
require **no interface edits** — only EVT-UNI-01 touches this file.

> **NOTE** (carried from CONTEXT.md §canonical_refs): roadmap/REQUIREMENTS call this
> file `IDegenerusGameLootboxModule.sol` — the interface actually lives in
> `IDegenerusGameModules.sol`. The planner should use the real path.

---

### `test/unit/LootboxWholeTicket.test.js` (UPDATE — existing structural test breaks)

**Analog:** itself. Phase 275 already updated this file in commit `bb1b1abd` (the
`27 +--` / `154 +++++` diff lines) when it hoisted the Bernoulli math — the same
update discipline applies here.

This 740-line file (Phase 274 TST-WT-01..07) is the **canonical event-structural-test
template** AND a **mandatory update target**. Blocks that break under EVT-UNI:
- **TST-WT-06** (`:590-680`) — `[06a]`/`[06b]`/`[06d]`/`[06e]` assert `emit
  LootboxTicketRoll(player, index, scaledPre, roundedUp)` exists on the contract AND
  the interface; `[06f]` asserts auto-resolve passes `type(uint48).max`. ALL break:
  EVT-UNI-01 deletes the event, EVT-UNI-05 retires the sentinel, D-277-AR-INDEX-01
  changes the sentinel to `0`.
- **TST-WT-07** (`:682-739`) — `[07a]`/`[07b]`/`[07c]` assert `LootboxTicketRoll` field
  consistency + emit ordering vs the sentinel gate. ALL break.
- **TST-WT-03** (`:367-407`) — `[03-static]` asserts `if (index != type(uint48).max)`
  appears AFTER the Bernoulli slice (`:385`, `:170-174`). The gate is deleted — this
  assertion must be rewritten to the post-retirement structural shape.

The planner must **rewrite these blocks** to assert the NEW surface: `LootBoxOpened`
carries `preRollTickets`/`roundedUp`, `BurnieLootOpen` carries them too, the sentinel
gate is gone, the consolation is gated on `emitLootboxEvent`, auto-resolve passes `0`.
This is naturally TST-EVT-UNI-01..06 territory — planner reconciles whether the new
requirements live as rewrites-in-place or as a new sibling file.

**Structural-grep idiom to copy** (`LootboxWholeTicket.test.js:45-54`, `:125-175`):
```javascript
import fs from "node:fs";
import path from "node:path";
const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(), "contracts/modules/DegenerusGameLootboxModule.sol"
);
// inside a test:
const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
const emits = [...source.matchAll(/emit LootboxTicketRoll\(/g)];
expect(emits.length, "...").to.equal(1);
```

---

### New TST-EVT-UNI-01..06 tests (`test/unit/` + `test/edge/` — planner reconciles)

**Analogs:** `test/unit/LootboxWholeTicket.test.js` (structural-grep), `test/unit/
LootboxAutoResolveSilentColdBust.test.js` (emit-absence / silent-cold-bust),
`test/unit/LootboxAutoResolveRemByte.test.js` (`fs`/`path`/`execSync` source-grep +
git-baseline diff).

**Topic-hash assertion pattern** — ethers computes the event topic from the
canonical signature. The new tests can assert the topic-hash CHANGED (D-40N-EVT-BREAK-01
explicitly accepts breaking topic-hashes) and that the NEW signature is well-formed:
```javascript
import hre from "hardhat";
// canonical-signature topic hash:
const topic = hre.ethers.id(
  "LootBoxOpened(address,uint48,uint48,uint128,uint24,uint32,bool,uint32,uint32)"
);
// assert the deployed contract's interface exposes the new shape:
const iface = (await hre.ethers.getContractFactory("DegenerusGameLootboxModule")).interface;
const ev = iface.getEvent("LootBoxOpened");
expect(ev.inputs.map(i => i.type)).to.deep.equal([...]);
expect(ev.topicHash).to.equal(topic);
```

**Emit-absence pattern (TST-EVT-UNI: `LootboxTicketRoll` fully removed)** — copy the
silent-cold-bust posture from `test/unit/LootboxAutoResolveSilentColdBust.test.js`:
assert via source-grep that `emit LootboxTicketRoll` appears **zero** times in
`DegenerusGameLootboxModule.sol` AND that `event LootboxTicketRoll` appears zero times
in both `DegenerusGameLootboxModule.sol` and `IDegenerusGameModules.sol`:
```javascript
const lootboxSrc = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
const ifaceSrc = fs.readFileSync(IFACE_SOURCE_PATH, "utf8");
expect((lootboxSrc.match(/LootboxTicketRoll/g) || []).length).to.equal(0);
expect((ifaceSrc.match(/LootboxTicketRoll/g) || []).length).to.equal(0);
```

**Sentinel-retirement structural proof** — assert `type(uint48).max` no longer appears
in `_resolveLootboxCommon` body / the 4 callers (the Phase 274 `[06f]` test at
`:659-679` did the inverse — asserting it appeared `>= 2` times; this becomes `== 0`):
```javascript
expect((source.match(/type\(uint48\)\.max/g) || []).length).to.equal(0);
```

## Shared Patterns

### Event-definition style (in-file convention)
**Source:** `contracts/modules/DegenerusGameLootboxModule.sol:76-132` (`BurnieLootOpen`,
`LootBoxWhalePassJackpot`, `LootBoxDgnrsReward`, `LootBoxWwxrpReward`) +
`DegenerusGameJackpotModule.sol:79-94` (`JackpotTicketWin`).
**Apply to:** all 3 restructured event defs.
- `indexed` topics come FIRST in the field list; `address indexed player` /
  `... indexed day` / `uint16 indexed traitId` are the established indexed picks.
- Every field gets a `@param` NatSpec line; the event gets a `@notice` (Lootbox module)
  or `@dev` (Jackpot module) one-liner.
- Comments describe what IS — no "changed from" history (`feedback_no_history_in_comments.md`).

### Hoisted Bernoulli locals + `roundedUp` capture
**Source:** `contracts/modules/DegenerusGameLootboxModule.sol:1038-1045` (Phase 275
committed `b6ed8fce`).
**Apply to:** the `_jackpotTicketRoll` `roundedUp` capture (`DegenerusGameJackpotModule.sol:2232-2239`)
AND the function-scope hoist of `scaledPre`/`roundedUp` in `_resolveLootboxCommon` so
the post-block `LootBoxOpened` emit can read them.
```solidity
uint32 scaledPre = futureTickets;             // or scaledTickets on the jackpot surface
uint32 whole = scaledPre / uint32(TICKET_SCALE);
uint32 frac  = scaledPre % uint32(TICKET_SCALE);
bool roundedUp = false;
if (frac != 0 && (uint16(seed >> N) % uint16(TICKET_SCALE)) < uint16(frac)) {
    unchecked { whole += 1; }
    roundedUp = true;
}
```
`N = 152` lootbox surface, `N = 200` jackpot surface (`entropy` is the seed var name
on the jackpot side). `TICKET_SCALE` is compile-time inlined (no storage slot).

### `emitLootboxEvent` as the manual-vs-auto-resolve discriminator
**Source:** `contracts/modules/DegenerusGameLootboxModule.sol` — arg 11 of the 4
`_resolveLootboxCommon` callsites: `openLootBox:625` (`true`), `openBurnieLootBox:683`
(`true`), `resolveLootboxDirect:723` (`false`), `resolveRedemptionLootbox:759` (`false`).
**Apply to:** D-277-CONSOLATION-GATE-01 — `emitLootboxEvent` becomes the cold-bust
consolation gate (replacing the retired sentinel's role b). It is already exactly 1:1
with the manual/auto-resolve split — no new parameter on the already-14-arg signature.
**Constraint:** auto-resolve `LootBoxOpened` emission (D-277-AR-EMIT-01) must be wired
WITHOUT flipping these `false` args to `true` — see the `resolveLootboxDirect` /
`resolveRedemptionLootbox` notes above.

### Multi-emit-site field addition (touch every site)
**Source:** `JackpotTicketWin` has 3 emit sites (`:705`, `:1008`, `:2246`); adding
`roundedUp` forces all 3 to supply it. Same discipline as the Phase 275/276 waves.
**Apply to:** `JackpotTicketWin` (3 sites) and `LootBoxOpened` (1 emit site at
`DegenerusGameLootboxModule.sol:1081`, but also the new auto-resolve emit sites from
D-277-AR-EMIT-01) and `BurnieLootOpen` (1 emit site at `:688`).

### Source-level structural-proof idiom (`fs.readFileSync` + regex; `execSync` + git baseline)
**Source:** `test/unit/LootboxWholeTicket.test.js:45-54` + `:125-175` +
`test/unit/LootboxAutoResolveRemByte.test.js` (the `fs`/`path`/`execSync` import block
+ `git show <baseline>:<path> | grep -c` baseline-diff assertions).
**Apply to:** all TST-EVT-UNI structural tests — `LootboxTicketRoll` zero-occurrence,
sentinel `type(uint48).max` zero-occurrence, event-shape assertions, and any
storage-layout byte-identity check vs v39 baseline `6a7455d1` (no storage change
expected — event signature changes don't touch layout).

### ethers interface topic-hash assertion
**Source:** standard hardhat/ethers — `iface.getEvent(name).topicHash` /
`hre.ethers.id("EventName(type,type,...)")`.
**Apply to:** TST-EVT-UNI-01 (the breaking-topic-hash acceptance test) — assert the
NEW canonical signature's topic hash and the new field type list, per D-40N-EVT-BREAK-01.

## No Analog Found

None. Every change is an in-file sibling pattern (another event in the same module,
another emit site of the same event) or a prior-phase committed template (Phase 274
introduced the deletion targets; Phase 275 hoisted the Bernoulli math out of the
sentinel gate, pre-staging this retirement; Phase 276 mirrored it onto the jackpot
surface). The phase is a deliberate consolidation of surfaces those phases built.

## Metadata

**Analog search scope:** `contracts/modules/`, `contracts/interfaces/`, `test/unit/`,
`test/edge/`, `test/stat/`; git commits `bb1b1abd` (Phase 275 tests), `1568fd5c`
(Phase 276 tests).
**Files scanned:**
`DegenerusGameLootboxModule.sol` (events `:40-188`, `openLootBox` `:553-632`,
`openBurnieLootBox` `:634-696`, `resolveLootboxDirect` `:698-730`,
`resolveRedemptionLootbox` `:732-766`, `_resolveLootboxCommon` `:865-1092`),
`DegenerusGameJackpotModule.sol` (`JackpotTicketWin` def `:79-94`, emit sites `:695-714` /
`:998-1016`, `_jackpotTicketRoll` `:2186-2255`),
`IDegenerusGameModules.sol` (`IDegenerusGameLootboxModule` block `:264-289`),
`test/unit/LootboxWholeTicket.test.js` (full, 740 lines),
`test/` directory listing (no `regression/`, `lootbox/`, or `jackpot/` dirs),
Phase 275/276 test-commit file lists.
**Pattern extraction date:** 2026-05-14
