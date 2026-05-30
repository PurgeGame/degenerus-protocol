# 348 — ARCH-04 Producer-Before-Consumer IMPL Edit-Order Map (the single 349 batched diff)

**Plan:** 348-05 · **Requirement:** ARCH-04 · ROADMAP Phase 348 Success Criterion 5
**Authored:** 2026-05-30 · **Subject HEAD (`contracts/`):** byte-identical to the v54 de-custody HEAD **`20ca1f79`**
**Line source-of-truth:** [`348-GREP-ATTESTATION.md`](./348-GREP-ATTESTATION.md) (348-01, re-pinned vs the live tree `20ca1f79`).
**Code-size running-total source:** [`348-CODE-SIZE-PLAN.md`](./348-CODE-SIZE-PLAN.md) (348-02 — MEASURED 24,358 B / 218 B headroom; clean reclaim ~1.4–1.7 KB).
**Freeze spine + the no-interleave guard:** [`348-FREEZE-PROOF.md`](./348-FREEZE-PROOF.md) (348-03 — FREEZE-02 `subsFullyProcessed`; FREEZE-03 stamped-day).
**Corrected invariant set (no-valve):** [`348-INVARIANT-CARRY.md`](./348-INVARIANT-CARRY.md) (348-03 — obligations 1–3; D-348-04 try/catch DROPPED).
**Required-path STAGE placement:** [`348-PLACEMENT-DECISION.md`](./348-PLACEMENT-DECISION.md) (348-04 — D-348-01 USER override).

> **This doc is the DOWNSTREAM CONSUMER of all five upstream 348 deliverables.** It does NOT re-discover lines, re-prove
> the freeze, re-measure bytes, or re-decide the placement — every `file:line` below is the ACTUAL re-pinned anchor from
> `348-GREP-ATTESTATION.md`, every code-size figure is the MEASURED running-total from `348-CODE-SIZE-PLAN.md`, the
> `subsFullyProcessed` no-interleave guard is carried verbatim from `348-FREEZE-PROOF.md` FREEZE-02, the no-valve REVERT-02
> form is carried from `348-INVARIANT-CARRY.md` D-348-04, and the required-path STAGE is carried from
> `348-PLACEMENT-DECISION.md` D-348-01. Its job is to compose them into the **SINGLE 349 IMPL diff hand-off** as a
> **producer-before-consumer** edit-order, with **zero "by construction" assumptions**, **zero intermediate broken
> state**, and a running-total proving the Game never breaches **24,576** mid-flight.

> **This is the analog of [`343-IMPL-EDIT-ORDER-MAP.md`](../343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca/343-IMPL-EDIT-ORDER-MAP.md)** (343-04): FINAL reconciled shapes → producer-before-consumer edit order → the carried corrections → a re-pin-before-authoring caution. 343 mapped the de-custody fold; this maps the AfKing-in-Game fold + the box redesign.

> **Paper-only invariant honored:** this plan only READS the upstream docs + the live `contracts/*.sol` and WRITES this
> Markdown artifact. `git diff --name-only -- contracts/` is EMPTY — zero contract edits. The pre-existing unrelated
> `scope.txt` working-tree change is untouched.

> **Scope boundary (read first):** the 349-OWNED design (BOX-01..05 box redesign / REVERT-01/02 / EVCAP-01 / CONSENT-01/02
> / PLACE-02 bounty) is the **BUILD**. This map **SEQUENCES** that build — it does **NOT re-decide** it. Where a shape is
> already locked upstream (the no-valve REVERT-02, the EV-cap-at-open, the stamp fields, the `abi.encode` seed) it is
> carried here as a constraint on the edit, not re-litigated.

---

## Section 1 — Final reconciled shapes (the ARCH-04 lock for the fold)

These are the FINAL reconciled shapes the 349 IMPL diff writes against. Each carries its ACTUAL `file:line` from
`348-GREP-ATTESTATION.md`. No provisional shapes — the storage append, the `GameAfkingModule` contents, the two open
routes, and the `AfKing.sol` stub collapse are all pre-reconciled here so 349 writes them directly.

### 1.1 — `DegenerusGameStorage` append (layout-safe; the producer everything else consumes)

The fold appends — never reorders — into `contracts/storage/DegenerusGameStorage.sol` (pre-launch redeploy-fresh ⇒ a
storage break is fine, no migration; the exact packing is a 349 layout decision, §3-ii of `348-INVARIANT-CARRY.md`
confirms the widths are **2-slot-feasible**). The appended members:

```solidity
// APPENDED to contracts/storage/DegenerusGameStorage.sol (inherited by the Game + GameAfkingModule)

// --- the subscriber SET (relocated from AfKing) ---
mapping(address => Sub)     internal _subOf;          // per-subscriber record (incl. the (index,amount,day) stamp + markers)
address[]                   internal _subscribers;    // the iterable set (swap-pop tombstone on cancel — H-CANCEL-SWAP-MISS class)
mapping(address => uint256) internal _subscriberIndex; // membership ⟺ packed-index (swap-pop bookkeeping)

// --- the process / open CURSORS (chunked-drain bookkeeping) ---
uint256 internal _subCursor;          // process-STAGE cursor (drains the set across advanceGame calls; PLACEMENT §3b)
bool    internal subsFullyProcessed;  // FREEZE-02 chunk gate + no-interleave guard (CONFIRMED-NEW — authored at 349; §2.4)
// (open-leg cursor — the OPEN_BATCH-style post-RNG drain; its own router-category cursor)

// --- the v54 afkingFunding LEDGER (rides INSIDE claimablePool — NO new aggregate; carried from 344/20ca1f79) ---
// mapping(address => uint256) internal afkingFunding;  // ALREADY shipped at 20ca1f79 (Game-side, :1540 afkingFundingOf);
//                                                       // the fold REUSES it — confirm present, do NOT re-declare.
```

The per-sub **stamp** lives inside the `Sub` record (relocated from `AfKing.sol`, whose `Sub` carries `validThroughLevel`
`:103` + `fundingSource` `:106` today). Stamp fields + markers (`348-INVARIANT-CARRY.md` §3-ii):

| Stamp / marker field | Width | Source / role |
|---|---|---|
| `index` | `uint48` | the **pre-RNG** `LR_INDEX` at process (today's `openLootBox` takes `uint48 index`, `LB:503`; `_finalizeLootboxRng` uses `uint48`, `:1230`) |
| `amount` | full wei (`uint256`, or packed with a `purchaseLevel`-style headroom field à la `lootboxEth` `LB:505-509`) | the stamped spend; **boons OFF ⇒ `amount` = spend exactly** (no boosted-amount lever); feeds the seed `abi.encode` field (`LB:534`) at full 32-byte fidelity |
| `day` | `uint32` | the **boundary-pinned** process day (mirrors today's frozen `lootboxDay[index][player]`, `LB:514`); seeds the open (FREEZE-03), NEVER open-time `_simulatedDayIndex()` |
| `lastAutoBoughtDay` | `uint32` | success-marker (set atomically AFTER a successful `afkingFunding` debit → a failed/mid-cycle subscribe leaves no marker → no free box) |
| `lastOpenedIndex` | `uint48` | monotonic no-double-open guard (the open leg only materializes indices strictly past it) |

> **2-slot append (348-03 §3-ii):** one full slot for `amount` + one slot packing `index`(48) + `day`(32) +
> `lastAutoBoughtDay`(32) + `lastOpenedIndex`(48) ≈ 160 bits, comfortably under 256. Exact packing = 349 decision.

> **Storage adds ~0 B Game runtime** (slots, not deployed bytecode — `348-CODE-SIZE-PLAN.md` §3). The bytecode cost is
> entirely in the dispatch stubs (§1.4) + the `GameAfkingModule` (off-budget, §1.2).

### 1.2 — `GameAfkingModule` (the relocated logic — its bytecode is its OWN budget, NOT the Game's)

A new `delegatecall` module on the existing `GAME_*_MODULE` pattern (the same lane the existing `claimBingo` stub uses,
`DegenerusGame.sol:333`), inheriting `DegenerusGameStorage` (so it operates on the §1.1 appended state in-context — the
cross-contract `afkingSnapshot`/`afkingFundingOf` staticcalls + value plumbing of v54 collapse into in-context `SLOAD`s).
Its runtime size matters only vs its OWN 24,576 ceiling — **0 B to the Game** (`348-CODE-SIZE-PLAN.md` §3; AfKing today is
9,780 B runtime, ample headroom).

**Enumerated contents (what 349 writes into the module):**

| Module surface | What it is | Folded from |
|---|---|---|
| `subscribe` + the setters | `subscribe` (6 params) + `setDailyQuantity` / `setDrainGameCreditFirst` / `setMode` / `setReinvestPct` | `AfKing.sol:324` (subscribe) / `:392` / `:405` / `:414` / `:423` — incl. the OPEN-E SUB-02 `:338` + OPENE-04 `:343-352` consent gates + the AFSUB `validThroughLevel` write `:371` |
| the **required-path process STAGE** | the chunked pre-RNG stamp pass: per funded sub → build the `_resolveBuy` slice (obligation 1, verbatim) → stamp `(index, amount, day)` → debit `afkingFunding` → set `lastAutoBoughtDay`; cursor-chunked, `BUY_BATCH`-style | `AfKing.sol:_resolveBuy :727-863` (the slice-builder substrate) — this is the logic the AdvanceModule STAGE (§1.5 / Step 4) CALLS |
| the **open-pass** | the post-RNG `OPEN_BATCH`-style leg materializing the box from the stamp + `lootboxRngWordByIndex[stampedIndex]`, identical draw math to `openLootBox` (`LB:503`), seeding from the **stamped** day, routing the EV-cap through `_applyEvMultiplierWithCap(player, level+1, …)` (`LB:459`) exactly once | the afking open route (§1.3) |
| the **router** | the `doWork` / `autoBuy` / `autoOpen` dispatch (one-category early-return shape) | `AfKing.sol:864` (doWork) / `:904` (autoBuy) / `:910` (autoOpen) |

### 1.3 — The TWO open routes (producer-before-consumer; share no mutable-state hazard)

Per `348-FREEZE-PROOF.md` §10 there are **two open routes**, by design — they must be reconciled to share no mutable-state
hazard:

| Route | Day source | EV-cap RMW | What it reads |
|---|---|---|---|
| **afking-stamp open** (the new leg) | the **stamped** `day` in the Sub record (FREEZE-03; never open-time) | LIVE at open via `_applyEvMultiplierWithCap` (`LB:459`), keyed `[player][level+1]`, **buy-time write BYPASSED** | `lootboxRngWordByIndex[stampedIndex]`; score/baseLevel/EV-cap read LIVE (D-348-05 accepted window) |
| **human `openLootBox`** (existing, `LB:503`) | the **frozen** `lootboxDay[index][player]` (`LB:514`) snapshot | the existing frozen-snapshot path (`scorePlus1`/`adj`/`baseLevelPlus1` in `lootboxPurchasePacked`, `LB:529-532`) | `lootboxRngWordByIndex[index]` + the human's deposit-time snapshot |

**Shared-no-mutable-state-hazard note (the producer-before-consumer reconciliation):**
- The two routes share the **`lootboxEvBenefitUsedByLevel[player][level+1]`** EV-cap map — but that is exactly the
  intended **one shared per-level 10-ETH budget** (`LOOTBOX_EV_BENEFIT_CAP`, `Storage:1326`); each route does exactly-one
  RMW per open via the same `_applyEvMultiplierWithCap` helper, hard-clamped ≤ 10 ETH with a no-write 100%-EV short-circuit
  (`LB:478-481`) — no double-draw, no revert (`348-INVARIANT-CARRY.md` obligation 2 + §4-iii double-draw guard).
- The two routes share the **`lootboxRngWordByIndex`** word map — but read-only at open; the word for a stamped index is
  written **write-once** by `_finalizeLootboxRng` (`:1231`, `if (… != 0) return;`). No write contention.
- The afking route reads the stamp (produced by the process STAGE) — strict **producer (process STAGE) → consumer (open
  leg)** ordering, enforced by `lastAutoBoughtDay`/`lastOpenedIndex` markers + the post-RNG sequencing (the open only runs
  after the day's `rngGate` committed the word). The human route is untouched by the afking stamp (disjoint per-`index`
  state). **No mutable-state hazard between the two routes.**

### 1.4 — `AfKing.sol` thin-dispatch-stub collapse (the consumer; LAST)

AfKing proper collapses to **thin `delegatecall` dispatch stubs**, each shaped exactly like the existing `claimBingo`
void-dispatch (`DegenerusGame.sol:328-344`): selector + `abi.encodeWithSelector(args)` + CALL + `_revertDelegate` tail.
The external mutating surface that becomes stubs (`348-CODE-SIZE-PLAN.md` §3 — ~8 stubs):

| Stub | Current AfKing def | Note |
|---|---|---|
| `subscribe` | `AfKing.sol:324` | calldata-heavy (6 params) ≈ 130–200 B |
| `setDailyQuantity` | `:392` | calldata-light ≈ 60–110 B |
| `setDrainGameCreditFirst` | `:405` | calldata-light |
| `setMode` | `:414` | calldata-light |
| `setReinvestPct` | `:423` | calldata-light |
| `doWork` | `:864` | parameterless ≈ 60–110 B |
| `autoBuy` | `:904` | |
| `autoOpen` | `:910` | |

> **A delegatecall stub CANNOT be `view`** (`348-CODE-SIZE-PLAN.md` hand-off note 2) — irrelevant for these 8 (all
> mutating), but it is precisely WHY the reclaim targets R2/R3 (read-aggregators) must drop-`view`/→lens rather than
> become stubs (§2 / Step 1). **8 stubs × ~120 B avg ≈ ~1.0 KB; upper bound ~1.5 KB** (the Game-runtime cost that the
> reclaim-FIRST ordering must clear).

---

## Section 2 — Code-size running-total carry (reclaim FIRST; the < 24,576 invariant)

Carried verbatim from `348-CODE-SIZE-PLAN.md` (348-02). **Use the MEASURED 24,358 B / 218 B headroom + the corrected
~1.4–1.7 KB clean-reclaim — NOT the v55 PLAN doc's overstated ~2.8 KB** (the doc's 2.8 KB bundles R3's 953 B, which
requires a 5-caller retarget, and R2/R3's inherited-base bytes that do not come free; only R1 + the two thin wrappers are
clean = ~1.4–1.7 KB).

| Reclaim | Target | Site (re-pinned) | Mechanism | Clean bytes |
|---|---|---|---|---|
| **R1** (FIRST, zero-risk void) | `claimAffiliateDgnrs` | `DegenerusGame.sol:1553` | **MOVE → `BingoModule`** (delegatecalled; callable directly on the module → **NO Game stub left**) | **~1,200–1,350 B** |
| R2 (wrapper only) | `previewSellFarFutureTickets` | `DegenerusGame.sol:2113` | → lens / drop-`view` (drops its sole-caller `_quoteFarFutureSwap` body too) | ~120–220 B |
| R3 (wrapper only) | `playerActivityScore` | `DegenerusGame.sol:2676` | → lens / drop-`view` (⚠ NOT the clean 953 — 5 callers; full 953 needs a retarget, a 349 cost) | ~120–200 B |

**The running-total proof (worst-case stress, Scenario A of `348-CODE-SIZE-PLAN.md` §4) — every row < `24,576`:**

| Step | Action | Δ bytes | Running total | < `24,576`? | Margin |
|---|---|---|---|---|---|
| 0 | MEASURED baseline (live `20ca1f79`) | — | **24,358** | ✅ | 218 |
| 1 | **R1: `claimAffiliateDgnrs` → `BingoModule`** (FIRST; void, no stub) | **−1,200** | **23,158** | ✅ | 1,418 |
| 2 | Add the 8 Game dispatch stubs (worst-case high-end) | **+1,500** | **24,658** | ❌ **BREACH +82** | −82 |
| 2b | **R2 → lens/drop-`view`** (pull immediately) | **−120** | **24,538** | ✅ | 38 |
| 2c | **R3 wrapper → lens** (no caller-retarget) | **−120** | **24,418** | ✅ | 158 |

Central case (Scenario B): R1 (−1,283) then stubs (+1,200) lands at **24,275 < 24,576** (margin 301) with R2/R3 pure
insurance. **Bottom line for the edit-order:** R1 MUST precede the stub additions (Step 1 before Step 2), or the
running-total spikes through `24,576`; in the simultaneous worst case 349 ALSO lands R2 + the R3 wrapper to restore a
≥158 B margin. The **349 `forge build --sizes` after the diff is the FINAL authoritative verification** — these estimates
only prove the order is *feasible* under `24,576` so 349 never discovers mid-flight that it overshot. If the measured
post-fold size still exceeds these, 349 pulls the reserve set (`decClaimable`/`getTickets`/`getDailyHeroWinner`, ~650 B
unmeasured) and/or completes the R3 caller-retarget (up to ~953 B). The literal ceiling — **24,576** — is the invariant
the running-total guards at every row.

---

## Section 3 — Producer-before-consumer edit-order map (the single 349 diff)

A numbered, ordered list of edits for the SINGLE 349 IMPL diff such that **no file ships an intermediate broken state**
and the Game never breaches **24,576** mid-flight. This is ONE batched diff — "before / atomically-with" constraints are
satisfied by **authoring order within the single diff**; no sub-file is committed in isolation. Every anchor is the ACTUAL
re-pinned line from `348-GREP-ATTESTATION.md`.

**Producer → consumer dependency direction:** the **code-size reclaim** (R1) must land FIRST (the running-total invariant)
→ the **`DegenerusGameStorage` append** (the state) must exist before any logic reads/writes it → the **`GameAfkingModule`**
(the logic, incl. the process STAGE callee + the open-pass + the router) must exist before the AdvanceModule STAGE calls it
and before the interfaces declare it → the **AdvanceModule STAGE insertion** consumes the module's process-pass + authors
the `subsFullyProcessed` guard → the **interfaces** declare the new/changed ABI → the **`AfKing.sol` thin stubs** (the
consumer) dispatch into the module.

### Step 1 — Code-size reclaim FIRST (the running-total producer; clears the 218 B margin)

1a. `contracts/DegenerusGame.sol:1553` — **MOVE `claimAffiliateDgnrs` → `BingoModule`** (R1), wired on the existing
    `GAME_BINGO_MODULE` delegatecall lane (mirror `claimBingo` `:328-344`). Callable directly on the module → leave **NO
    Game stub** (a true void). **This is the FIRST contract edit** (running-total Step 1: 24,358 → 23,158; §2). It is
    zero-risk: 0 external solidity callers, no `view` (no lens issue).

1b. (worst-case insurance, pull if Step 3's stub additions approach the ceiling) `DegenerusGame.sol:2113`
    `previewSellFarFutureTickets` (R2) + `:2676` `playerActivityScore` (R3) → lens / drop-`view`. R2 drops its sole-caller
    `_quoteFarFutureSwap` body too; **R3 reclaims only the ~120–200 B wrapper** (its 5 callers — `WhaleModule.sol:875`,
    `DecimatorModule.sol:704`, `BurnieCoin.sol:620`, `StakedDegenerusStonk.sol:913` — keep the inherited body; the full
    953 B needs a caller-retarget, decided at 349).

> Reclaim first: the Game must drop below the stub budget BEFORE the stubs are added, or the running-total breaches
> `24,576` (§2 Step 2 worst case). R1 alone suffices in the central case; R2/R3 wrappers are the worst-case insurance.

### Step 2 — `DegenerusGameStorage` append (the state producer; everything below reads it)

2a. `contracts/storage/DegenerusGameStorage.sol` — APPEND the subscriber set (`_subOf` / `_subscribers` /
    `_subscriberIndex`), the process/open cursors (`_subCursor` + the open-leg cursor) + **`subsFullyProcessed`**
    (CONFIRMED-NEW — does NOT exist in source; §2.4 / FREEZE-02), the per-sub `(index, amount, day)` stamp + the
    `lastAutoBoughtDay` / `lastOpenedIndex` markers inside the `Sub` record, and confirm the v54 `afkingFunding` ledger is
    present (shipped at `20ca1f79`, `DegenerusGame.sol:1540` `afkingFundingOf`) — **REUSE it; NO new aggregate** (rides in
    `claimablePool`). Layout-safe append, 2-slot Sub extension (§1.1). **~0 B Game runtime.**

> Storage producers first: the set + cursors + stamp + `subsFullyProcessed` must exist before the `GameAfkingModule`
> logic or the AdvanceModule STAGE reads/writes them.

### Step 3 — `GameAfkingModule` (the logic producer; consumes the storage, produces the ABI + the STAGE callee)

3a. NEW `contracts/modules/GameAfkingModule.sol` — author the relocated logic (inherits `DegenerusGameStorage`,
    delegatecall module on the `GAME_*_MODULE` pattern; §1.2): `subscribe` + the 4 setters (carrying the OPEN-E SUB-02
    `:338` + OPENE-04 `:343-352` consent gates + the AFSUB `validThroughLevel` write `:371` — CONSENT-01/02, 349-owned),
    the **required-path process STAGE** logic (the `_resolveBuy` slice-builder folded VERBATIM — obligation 1; §4 carried
    correction), the **open-pass** (afking-stamp route; §1.3 — seeds the stamped day, single `_applyEvMultiplierWithCap`
    RMW), and the router (`doWork`/`autoBuy`/`autoOpen`). **Its bytecode is its OWN ~10–24 KB budget — 0 B to the Game**
    (§1.2 / §2). The running-total is UNAFFECTED by this step (off-budget).

> The module before the AdvanceModule STAGE + the interfaces: the process-pass callee + the dispatch targets must exist
> before the STAGE calls them and before the interfaces/stubs reference them.

### Step 4 — `AdvanceModule` STAGE insertion (consumes the module's process-pass; AUTHORS the FREEZE-02 guard)

4a. `contracts/modules/DegenerusGameAdvanceModule.sol:272-273` — INSERT the new chunked process **STAGE** immediately
    **before** the `rngGate(` call (`:274`), on the new-day path only (D-348-01; `348-PLACEMENT-DECISION.md` §3a). The
    STAGE sits inside the `do { … } while` block, AFTER the daily ticket-drain gate (`:247-270`) and `_enforceDailyMintGate`
    (`:191`, inherited — ZERO new gate code, D-348-03), BEFORE `rngGate(:274)`. It drives the `GameAfkingModule` process
    pass across the subscriber set via `_subCursor`, draining a `BUY_BATCH`-style per-call budget.

4b. `DegenerusGameAdvanceModule.sol` — AUTHOR the **`subsFullyProcessed` / `_subCursor` chunk gate** (FREEZE-02b — read
    `LR_INDEX` ONCE at pass start into a uniform-epoch local, stamp every sub to that same value; mirror the existing
    `ticketsFullyProcessed` partial-drain discipline `:196/:247/:269` + the `STAGE_TICKETS_WORKING` partial-drain status
    `:216-218/:264-266` — `break` and return while `!subsFullyProcessed`, set `true` only at cursor end, then fall through
    to `rngGate`).

4c. `DegenerusGameAdvanceModule.sol:1016` — AUTHOR the **`requestLootboxRng` no-interleave guard** (FREEZE-02c, the
    load-bearing D-348-02 obligation): while `subsFullyProcessed == false`, block the mid-day index-advance — add an early
    `revert` mirroring the existing reroll-block at `:1020` (`if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert
    E();`). The two index-advance sites (`:1089` mid-day, `:1629` daily) both then sit OUTSIDE/AFTER the STAGE — the daily
    advance fires downstream of `rngGate(:274)` (after the STAGE), and the mid-day advance is blocked for the pass
    duration. **`subsFullyProcessed` is CONFIRMED-NEW** (`348-FREEZE-PROOF.md` §2.4: grep of `subsFullyProcessed` in the
    AdvanceModule returns ZERO matches) — 349 AUTHORS it; it cannot be assumed to exist.

4d. `DegenerusGameAdvanceModule.sol` — VERIFY (no edit unless needed) the STAGE cannot block the **game-over routing**
    (REVERT-02 class C, no-valve; D-348-04): game-over is a separate advance path (`_handleGameOverPath` runs and returns
    at `:182`, BEFORE the STAGE block at `:272-273` is reached) — confirm the STAGE does not sit on the path that reaches
    it.

> The STAGE consumes the `GameAfkingModule` process-pass (Step 3) + the `subsFullyProcessed`/cursor state (Step 2). The
> FREEZE-02 guard is AUTHORED here against the re-pinned `:1016`/`:1089`/`:1629`/`:274` lines — it does NOT survive
> un-specified into 349.

### Step 5 — Interfaces (declare the new/changed ABI the AfKing stubs consume)

5a. `contracts/interfaces/IDegenerusGame*.sol` + the `GameAfkingModule` selector interface — ADD the relocated mutating
    surface (`subscribe`, the 4 setters, `doWork`/`autoBuy`/`autoOpen`) so the Game-proper dispatch stubs (Step 6) and the
    AdvanceModule STAGE call (Step 4) resolve against a real ABI. Mirror the existing module-interface pattern.

> Interfaces before the AfKing stubs: the stubs' `delegatecall` selectors must resolve against a declared ABI before the
> stub call sites are authored.

### Step 6 — `AfKing.sol` thin dispatch stubs (the consumer; LAST)

6a. `contracts/AfKing.sol` — collapse the external mutating surface to thin `delegatecall` dispatch stubs (§1.4),
    each shaped like `claimBingo` (`DegenerusGame.sol:328-344`): `subscribe` (`:324`), `setDailyQuantity` (`:392`),
    `setDrainGameCreditFirst` (`:405`), `setMode` (`:414`), `setReinvestPct` (`:423`), `doWork` (`:864`), `autoBuy`
    (`:904`), `autoOpen` (`:910`). DELETE the relocated bodies (subscriber set, `_resolveBuy` slice builder `:727-863`, the
    open logic) — they now live in `GameAfkingModule`. **~1.0–1.5 KB of Game-runtime stub cost** (the additions the Step 1
    reclaim cleared; running-total §2 Step 2).

> AfKing stubs LAST: they consume the new ABI (Step 5) + dispatch into the module (Step 3); deleting the relocated bodies
> only after the module + storage + interfaces exist means no intermediate file holds a dangling reference.

### Edit-order summary table

| Step | File:line (actual, re-pinned) | Edit | Producer/consumer role | Code-size running-total |
|---|---|---|---|---|
| 1 | `DegenerusGame.sol:1553` (+ `:2113`/`:2676` insurance) | **R1 reclaim FIRST**: `claimAffiliateDgnrs` → `BingoModule` (void); R2/R3 → lens/drop-`view` | producer (running-total) | 24,358 → **23,158** (R1) |
| 2 | `DegenerusGameStorage.sol` | APPEND set + cursors + `subsFullyProcessed` + stamp + markers; REUSE `afkingFunding` (no aggregate) | producer (state) | ~0 B (slots) |
| 3 | NEW `modules/GameAfkingModule.sol` | subscribe/setters + process STAGE callee + open-pass + router (consent gates carried) | producer (logic + ABI + STAGE callee) | **0 B to Game** (own budget) |
| 4 | `DegenerusGameAdvanceModule.sol:272-273` (+ `:1016`) | INSERT process STAGE before `rngGate(:274)`; AUTHOR `subsFullyProcessed`/`_subCursor` gate + the `requestLootboxRng` no-interleave guard; VERIFY game-over routing unblocked | consumer of module; AUTHORS FREEZE-02 guard | (Game runtime; small) |
| 5 | `interfaces/IDegenerusGame*.sol` + module iface | declare the relocated mutating ABI | consumer of module; producer for stubs | — |
| 6 | `AfKing.sol` (`:324`/`:392`/`:405`/`:414`/`:423`/`:864`/`:904`/`:910`; delete `:727-863` etc.) | collapse to thin dispatch stubs; delete relocated bodies | consumer (dispatch) | **+1.0–1.5 KB** Game (cleared by Step 1) → **≤ 24,418 worst case** |

**No file ships an intermediate broken state:** every consumer (the AdvanceModule STAGE call, the interfaces, the AfKing
stubs) is authored AFTER its producer (the storage append, the `GameAfkingModule`, the interfaces) within the single 349
diff; the reclaim (Step 1) precedes every stub addition (Step 6) so the running-total stays **< 24,576** at every row. The
unchanged spine (the solvency accounting that reserves the `afkingFunding` total via `claimablePool` under SOLVENCY-01, the
human `openLootBox` path, the VRF index machinery outside the STAGE) is NOT structurally touched beyond the STAGE
insertion + the no-interleave guard.

---

## Section 4 — Carried corrections threaded into the edit-order

The four upstream corrections are bound here to the specific edit step each lands at, so none is lost into 349 (the
documentation-integrity threat T-348-12). These are CARRIED faithfully from the upstream docs — NOT re-derived.

### 4.1 — Box-seed `abi.encode` re-pin (348-01 §1a) → the open-pass step (Step 3a / §1.3)

**The afking open seed is `keccak256(abi.encode(rngWord, player, day, amount))` at `LB:534` — `abi.encode`, NOT
`abi.encodePacked`.** `abi.encodePacked` appears at exactly ONE site in the module: `:644`, the **PRESALE** box seed
(`abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)`), a distinct path the afking open does NOT copy.
The encoding is load-bearing: `abi.encode` (32-byte left-padded fields) vs `abi.encodePacked` (tight-packed) produce
**different hash preimages** → copying the packed form would compute a different seed and break box-outcome equivalence
with `openLootBox`. **Lands at:** the `GameAfkingModule` open-pass (Step 3a) — the box materialization MUST mirror the
`:534` `abi.encode` construction exactly, seeding from the **stamped** `day` (FREEZE-03), not `:644` and not open-time.

> Recorded correction: the afking open seed = `abi.encode(rngWord, player, day, amount)` (`LB:534`); the `abi.encodePacked`
> form (`LB:644`) is the PRESALE box, the WRONG pattern to copy.

### 4.2 — No-try/catch REVERT-02 correction (348-03 INVARIANT-CARRY D-348-04) → the process/open STAGE (Steps 3a + 4)

**The try/catch valve is DROPPED (obligation 4 → DROPPED).** REVERT-02's corrected no-valve form (a REWRITE of
REQUIREMENTS.md REVERT-02 + proof §5 obligation 4, the parallel to 343's D-01 `AUTOBUY-02` correction):
- **Healthy path: revert-free-by-construction** (obligation 1 — the `_resolveBuy` slice-builder invariants preserved
  VERBATIM; the SOLE no-brick guarantor). Nothing to catch — a try/catch would be dead code.
- **Class B (solvency-violation): FAIL LOUD** — the `claimablePool -= uint128(…)` subtractions (`Game:1010`,
  `Game:1912`, `Storage:847`) revert only if SOLVENCY-01 is already violated; **catching would MASK a catastrophic
  solvency bug** → it MUST propagate.
- **Class C (liveness-timeout): TERMINAL — routing-unblocked** — fires only ≥120-day-dead; the SPEC requires 349 VERIFY
  the STAGE cannot block the game-over routing (Step 4d), not a valve.

**Lands at:** the `GameAfkingModule` process STAGE (Step 3a — fold `_resolveBuy` `:727-863` verbatim, NO valve wrapper)
+ the AdvanceModule STAGE (Step 4d — verify game-over routing unblocked). **Two §10 knock-ons threaded:** §10 rule (2)
"mint slice fails → SKIP" becomes a **pre-emptive** skip (the slice builder declines to build an unbuildable slice; the
only pre-emptive skip is the `LOOTBOX_MIN` transient `:772-774` — sub STAYS + retries); the optional per-cycle eviction
cap is **DROPPED** (lost its revert-driven rationale). Rule (1) unfunded eviction is UNAFFECTED.

> Recorded correction: REVERT-02 → NO valve (revert-free-by-construction + fail-loud-on-solvency +
> terminal-routing-unblocked); obligation 1 is the SOLE no-brick guarantor; the eviction cap is dropped.

### 4.3 — Required-path override (348-04 PLACEMENT D-348-01) → the AdvanceModule STAGE step (Step 4)

**The §4 placement is DECIDED = REQUIRED-PATH** (a DELIBERATE USER OVERRIDE of the design doc's separate-legs
recommendation — PLAN-V55 §4/§9 are SUPERSEDED on the placement point). The process-pass is a chunked STAGE inserted in
`advanceGame` immediately before `rngGate` (new-day path only), guarded by `subsFullyProcessed` + `_subCursor`, inheriting
`_enforceDailyMintGate` (`:191`/`:973`) standing with **ZERO new gate code** (D-348-03, ACCEPTED). The **open** stays a
NORMAL post-RNG `OPEN_BATCH`-style leg — NOT folded into advance. Decision basis = **guaranteed-every-day** (NOT
revert-safety; the REVERT-FREE-CHAIN proof made required-path VIABLE, then the choice rested on guaranteed-every-day vs
minimal-surface). **Lands at:** the AdvanceModule STAGE insertion (Step 4a — `:272-273` before `rngGate(:274)`), the
inherited mint-gate (Step 4 note — ZERO new gate code), and the open as a separate router category (Step 3a open-pass, not
Step 4).

> Recorded correction: placement = required-path STAGE before `rngGate` (D-348-01 USER override); §4/§9 separate-legs
> SUPERSEDED; mint-gate inherited (ZERO new code); open stays a separate post-RNG leg.

### 4.4 — EV-cap-at-open, buy-time write BYPASSED (348-03 INVARIANT-CARRY obligation 2) → the open-pass step (Step 3a / §1.3)

**The afking open routes the box through `_applyEvMultiplierWithCap(player, level+1, amount, mult)` (`LB:459-495`)
exactly once at open** — the same shape `resolveLootboxDirect`/`resolveRedemptionLootbox` use — doing the cap READ
(`:473`) + WRITE (`:488`) atomically at open, keyed on the SAME `lootboxEvBenefitUsedByLevel[player][level+1]` map
MintModule uses at buy (`MintModule:1298/1303`, `:1321/1327`, both `[buyer][cachedLevel+1]`). One shared per-level 10-ETH
budget (`LOOTBOX_EV_BENEFIT_CAP = 10 ether`, `Storage:1326`), hard-clamped ≤ 10 ETH with a no-write 100%-EV short-circuit
(`LB:478-481`) — NO revert (not a class-B site). **The buy-time write at `MintModule:1303/1327` is BYPASSED for afking
boxes** (the double-draw guard, §4-iii): with boons OFF and the process-pass *stamping* `(index, amount, day)` instead of
routing through `_callTicketPurchase`'s lootbox tally (`MintModule:1496` / `:1261`), the buy-time EV write must NOT also
fire — the open does the single live RMW. **Lands at:** the `GameAfkingModule` open-pass (Step 3a) — single
`_applyEvMultiplierWithCap` RMW at open; the process STAGE (Step 3a / Step 4) stamps only, never touching
`MintModule:1303/1327`.

> Recorded correction: EV-cap = one live `_applyEvMultiplierWithCap` RMW at open keyed `[player][level+1]`, ≤10 ETH
> no-revert; the buy-time write is BYPASSED (no double-draw). This is part of the D-348-05 live-read window (accepted).

---

## Section 5 — Re-pin before authoring (the 343 hand-off precedent)

> **Every grep in `348-GREP-ATTESTATION.md` (and therefore every `file:line` carried into this map) is a point-in-time
> snapshot of `20ca1f79`.** As of `f353a50b` the working tree's `contracts/` is byte-identical to `20ca1f79`
> (`git diff --numstat 20ca1f79 HEAD -- contracts/` is EMPTY; the commits since are docs-only), so this map is current.
> **If the subject HEAD's `contracts/` moves off `20ca1f79` before 349 IMPL — i.e. if ANY `contracts/*.sol` commit lands
> between now and the 349 diff — the 349 author MUST re-run `348-GREP-ATTESTATION.md`** (`git diff --numstat 20ca1f79
> <new HEAD> -- contracts/` + re-grep every anchor) and re-derive the code-size running-total
> (`forge build --sizes --skip "test/**" --skip "*.t.sol"` + the `forge inspect … deployedBytecode` cross-check), then
> cite the re-pinned successor lines — **NEVER trust the lines transcribed here once the tree has drifted.** The lines
> WILL drift the moment a contract is edited. (This is the exact 343 hand-off discipline: "the 344 author MUST re-run the
> greps (or cite a re-pinned successor), never trust the upstream doc-cited lines.")

**The 349-owned design is the BUILD; this map SEQUENCES it.** BOX-01..05 (the box redesign), REVERT-01/02 (preserve the
slice-builder invariants verbatim + the no-valve placement + the game-over-routing verification), EVCAP-01 (the
`_applyEvMultiplierWithCap`-at-open), CONSENT-01/02 (the OPEN-E / AFSUB consent carry-over), and PLACE-02 (the bounty fold
— `2×·mult` advance bounty, `OPEN_KNEE` pro-rate, farm-by-splitting watch; NOTED not decided per
`348-PLACEMENT-DECISION.md` §6) are DECIDED upstream and BUILT at 349. This edit-order map fixes the *sequence* (reclaim
FIRST → storage append → `GameAfkingModule` → AdvanceModule STAGE → interfaces → AfKing stubs) and threads the carried
corrections — it does **not** re-decide the build.

---

## Section 6 — ARCH-04 hand-off verdict

- **Final reconciled shapes LOCKED** (Section 1): the `DegenerusGameStorage` 2-slot append (set + cursors +
  `subsFullyProcessed` + the `(index, amount, day)` stamp + markers + the reused `afkingFunding` ledger); the
  `GameAfkingModule` contents (subscribe/setters + process STAGE callee + open-pass + router — own budget, 0 B to Game);
  the TWO open routes (afking-stamp + human `openLootBox`) with the shared-no-mutable-state-hazard reconciliation; the
  `AfKing.sol` thin-dispatch-stub collapse.
- **Code-size running-total CARRIED** (Section 2): MEASURED 24,358 B / 218 B headroom + corrected ~1.4–1.7 KB clean
  reclaim (NOT the overstated ~2.8 KB); R1 reclaim FIRST; every running-total row **< 24,576** (worst case 24,418).
- **Edit-order FIXED producer-before-consumer** (Section 3): reclaim FIRST → storage append → `GameAfkingModule` →
  AdvanceModule STAGE insertion (authoring the FREEZE-02 `subsFullyProcessed` no-interleave guard) → interfaces → AfKing
  thin stubs; no intermediate broken state; the Game never breaches 24,576 mid-flight.
- **Four carried corrections THREADED** (Section 4): box-seed `abi.encode` re-pin → open-pass; no-try/catch REVERT-02 →
  process/open STAGE; required-path override → AdvanceModule STAGE; EV-cap-at-open buy-time-write-bypassed → open-pass.
- **Re-pin-before-authoring caution PRESENT** (Section 5).

**349 IMPL is sequencing-complete from this map.** The author writes ONE fully-reconciled, code-size-safe
`contracts/*.sol` diff against the actual lines above, with zero "by construction" assumptions and zero intermediate
broken state — re-running the greps + the size measurement first if the tree has drifted off `20ca1f79`.

---

*Zero `contracts/*.sol` edits — `git diff --name-only -- contracts/` is EMPTY. Paper-only SPEC edit-order map; the only
CLI used was `git diff` + `grep`/read (read-only). The pre-existing unrelated `scope.txt` working-tree change is
untouched. Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-05 · Requirement: ARCH-04.*
