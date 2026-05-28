# Phase 334 — IMPL-335 Producer-Before-Consumer Edit-Order Map + Shared-Surface Reconciliation (SC1 integration)

**Authored:** 2026-05-27
**Plan:** 334-04 (SPEC — Wave-2 integration)
**Requirement:** BATCH-01 (D-18 — the producer-before-consumer edit order + the shared `_queueTickets` surface reconciliation, so the single batched IMPL-335 diff ships with no intermediate broken state)
**Audit baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`
**Anchor attestation note:** Every `file:line` below is grep-attested in `334-GREP-ATTESTATION.md` vs the frozen baseline `b0511ca2` (`git diff b0511ca2 HEAD -- contracts/` is EMPTY — the working tree under `contracts/` is byte-identical to the frozen baseline).

> This is the SC1 **integration** slice. It RECORDS (does not re-derive) the IMPL-335 edit order established in `334-RESEARCH.md` ("IMPL-335 Edit-Order Map (D-18)") + the settled signatures in `334-DESIGN-LOCK-WHALE-MINTDIV.md` / `334-DESIGN-LOCK-AFKING.md` + the REACHABLE verdict in `334-MINTDIV01-REACHABILITY-VERDICT.md`. The whale/MintModule/AfKing signatures it sequences are FINAL; this map only fixes the ORDER they are re-authored in.

---

## 0. Why a producer-before-consumer edit order at all (D-18)

IMPL 335 lands the three v50.0 contract items as **ONE batched `contracts/*.sol` diff** (BATCH-02), HELD at the contract-commit boundary for explicit USER hand-review (`feedback_wait_for_approval` / `feedback_batch_contract_approval`). Even though the diff is committed atomically, the **re-author order matters** so that:

1. A producer (the slot/view/interface a later edit depends on) is written **before** its consumer, so no reviewer reads a forward-reference to something that does not yet exist in the diff narrative.
2. No intermediate file in the diff narrative implies a broken-compile state if read in isolation (the `feedback_security_over_gas` floor demands the reviewer can trust the diff compiles as a coherent whole).
3. The two RNG-adjacent edits (WHALE writer-side, MINTDIV reader-side) on the shared `_queueTickets`/`ticketsOwedPacked` surface are shown to be **independent** so the reviewer is not forced to reason about a hidden interaction.

The **producer-before-consumer** principle: edit the storage/shared surface (the producers) first, then the facade that exposes the new view + retires the carve-out, then the LootboxModule consumer that writes the producer's slot, then the independent MintModule one-liner, then the mutually-dependent AfKing+BurnieCoin cluster last. This map is the IMPL planner's authoring order.

---

## 1. The 5-step producer-before-consumer order

### Step 1 — Storage / shared surface FIRST (the producers)

**File:** `contracts/storage/DegenerusGameStorage.sol`

- **No structural change is required** if WHALE reuses the EXISTING machinery (D-20): the pending-claim counter `whalePassClaims[beneficiary]` lives in inherited state (read/zeroed in the claim at `WhaleModule:1020`/`:1024`, written by the jackpot/payout path `PayoutUtils.sol:52` / `JackpotModule.sol:1410`), and `_queueTicketRange` (`Storage:647`) + `_applyWhalePassStats` (`Storage:1111`) stay **UNCHANGED** — the box-open writer reuses them verbatim.
- **The producer-first action:** confirm the `whalePassClaims` declaration location (the inherited mapping) so the LootboxModule box-open writer (Step 3) has a verified slot to `+=` into. This is a "confirm the producer exists" step, not an edit — `whalePassClaims` is already deployed (relabel of D-02's `pendingWhalePasses`, NOT a new map — `334-DESIGN-LOCK-WHALE-MINTDIV.md §1`).
- **No `Storage` slot is added or repurposed** by the WHALE slice (the AfKing `Sub` slot repurpose is in `AfKing.sol`, Step 5 — a peripheral contract, not Game storage).

> Producer-before-consumer rationale: the LootboxModule consumer (Step 3) writes `whalePassClaims`; confirming its declaration first means Step 3 never forward-references an unverified slot.

### Step 2 — Game facade (the new view + the autoOpen carve-out retirement)

**File:** `contracts/DegenerusGame.sol`

- **Add the `lazyPassHorizon` level-horizon view (D-11):** a new per-pass-type view alongside `hasAnyLazyPass` at `DegenerusGame.sol:1520`, exposed via the `IGame` interface AfKing reads — deity → `type(uint24).max` (permanent sentinel), lazy/whale → the covered-through `frozenUntilLevel` (`334-DESIGN-LOCK-AFKING.md §3`). This view is the **producer** the AfKing cluster (Step 5) consumes at subscribe + at the crossing — so it MUST be authored before Step 5.
- **Retire the autoOpen gas-weight → flat `OPEN_BATCH` (WHALE-03):** remove the 331 whale-pass-weighted budget — `OPEN_NORMAL_GAS_UNIT = 90_000` (`DegenerusGame.sol:1561`), the `autoOpen` weighting (`:1687`), and the `weighted += used / OPEN_NORMAL_GAS_UNIT` math (`:1728`) — so `OPEN_BATCH` returns to flat per-box sizing (re-confirmed under the worst-case uniform open). This follows from D-02/D-04 (uniform O(1) opens) — `334-DESIGN-LOCK-WHALE-MINTDIV.md §6`.
- **Add/confirm the `claimWhalePass` external entrypoint home (Claude's Discretion, D-01):** the claim function ALREADY exists at `WhaleModule:1018`. The discretion is only the facade routing — either (a) a `DegenerusGame` external fn delegating to `WhaleModule`, or (b) expose the existing module-direct fn at `WhaleModule:1018`. SPEC leaves this to IMPL; this step records that the entrypoint home is settled at the facade layer (a producer for any caller), before the box-open consumer relies on the claim path being reachable.

> Producer-before-consumer rationale: `lazyPassHorizon` is consumed by AfKing (Step 5); the `claimWhalePass` entrypoint home is the deferred-materialization endpoint the box-open record (Step 3) defers to. Both are producers → facade is authored before the consumers.

### Step 3 — LootboxModule (the WHALE-01 consumer of the storage + the box-open record)

**File:** `contracts/modules/DegenerusGameLootboxModule.sol`

- **Replace `_activateWhalePass:1240`'s 100-loop + its `_applyWhalePassStats:1247` call** with the O(1) record: `whalePassClaims[beneficiary] += grant;` (mirroring the reference writer `PayoutUtils.sol:52`) — `334-DESIGN-LOCK-WHALE-MINTDIV.md §2`. The inline 100-iteration `for (uint24 i = 0; i < 100; )` loop (`:1250-1260`, the ~5.4M-gas monster) is deleted.
- **The grant shape converges to the existing flat per-level shape (D-21, the locked Q1 resolution):** the early-game ≤level-10 `WHALE_PASS_BONUS_TICKETS_PER_LEVEL = 40` bonus band (`:207`/`:209`) is DROPPED — a single counter, no grant-shape param, no second counter. This is a deliberate economic reduction; the value delta is routed to the 338 SWEEP economic-analyst (D-06/D-21) — `334-DESIGN-LOCK-WHALE-MINTDIV.md §3`.
- **Box-open writes NO `mintPacked_`** — stats move entirely to claim-time (D-04). The box-open record is a pure O(1) counter increment touching no freeze/levelCount slot.

> Producer-before-consumer rationale: this step WRITES the `whalePassClaims` slot confirmed in Step 1 and DEFERS materialization to the `claimWhalePass` endpoint settled in Step 2 — both producers exist before this consumer is authored.

### Step 4 — MintModule (independent — no ordering dependency with WHALE; REACHABLE per the verdict)

**File:** `contracts/modules/DegenerusGameMintModule.sol`

- **The one-liner IS in the diff** (MINTDIV-01 is **PROVEN REACHABLE** — D-22; `334-MINTDIV01-REACHABILITY-VERDICT.md`). The D-16 NEGATIVE branch ("no change, documented NEGATIVE") does **NOT** apply.
- At `:716`, change `processed += writesUsed >> 1;` → `processed += take;` to match the reference-correct contiguous advance at `processFutureTicketBatch:502` — `334-DESIGN-LOCK-WHALE-MINTDIV.md §7`. This makes `processTicketBatch` advance its within-player `startIndex` exactly like `processFutureTicketBatch`, so a player's owed tickets generate contiguous per-ticket LCG trait indices across a `WRITES_BUDGET_SAFE` (`:93`, `= 550`) budget-slice split.
- **The two near-duplicate loops STAY separate** (full dedup explicitly rejected, D-15). The fix is exactly this one line; no defensive change anywhere else.
- **Independent within the diff:** this edit has **no ordering dependency** with the WHALE steps (1–3) or the AfKing cluster (Step 5). It is an isolated within-module index-arithmetic one-liner. It is placed at Step 4 only by convention (after the WHALE consumer, before the AfKing cluster); it could be authored at any point in the diff without affecting the others.

### Step 5 — AfKing + BurnieCoin (the AFSUB cluster, mutually dependent on D-09) — LAST

**Files:** `contracts/AfKing.sol` + `contracts/BurnieCoin.sol`

**`AfKing.sol`:**
- Remove `burnForKeeper` (the `IBurnie` iface decl `:57`; the subscribe-time PAID burn call `:437`; the day-31 PAID burn call `:641`) — `334-DESIGN-LOCK-AFKING.md §5.1`.
- Remove the `paidThroughDay`/`WINDOW_DAYS` window accounting (the anchor math `:414-416`/`:424`; `WINDOW_DAYS = 30` at `:220`) and the `FLAG_WINDOW_PAID` semantics (flags bit 0; set/cleared `:433/:442/:634/:650`; bit freed, no future-proofing reservation).
- Repurpose the `Sub.paidThroughDay` slot (offset 5, `AfKing.sol:89`) → `validThroughLevel` (in-place reinterpretation; `uint24`-or-`uint32`, IMPL picks) — `334-DESIGN-LOCK-AFKING.md §2`.
- Rewrite `subscribe` (`:374`) to set `validThroughLevel = IGame(GAME).lazyPassHorizon(subscriber)` (consuming the Step-2 producer view), removing the `:430-443` pass-OR-pay block; preserve the SUB-02 self-consent check (`:385-391`) and the OPENE-04 gate (`:393-403`).
- Rewrite the `_autoBuy:630` per-iter validity check to `currentLevel <= sub.validThroughLevel` (a pure stored-field compare — NO per-iter external pass read; GASOPT-05 preserved).
- Rewrite the crossing (`currentLevel > validThroughLevel`, the level-denominated analog of the frozen day-31 branch `:630-631`) to **re-read `lazyPassHorizon` EXACTLY ONCE → refresh-or-evict** (refresh `validThroughLevel` if still covered; else evict via the existing `setDailyQuantity(0)` tombstone + the `_autoBuy:605` swap-pop reclaim — NOT an unconditional kick) — `334-DESIGN-LOCK-AFKING.md §4`.
- **Preserve OPEN-E `fundingSource`** (offset 11) + the 4 structural protections (`334-DESIGN-LOCK-AFKING.md §6.1`) and the **SUB-07 cancel-tombstone + v49 swap-pop membership invariant** (membership ⟺ packed != 0) so eviction does NOT reproduce H-CANCEL-SWAP-MISS (`§6.2`/`§6.3`).
- No proactive `refreshPass()` entrypoint (D-10) — the crossing re-check is the only refresh path.

**`BurnieCoin.sol`:**
- Delete the now-dead `burnForKeeper` implementation `:472` (gate `:475`), the `KeeperBurn` event `:85`, and the `onlyAfKing` modifier `:549` (confirmed `burnForKeeper` is its ONLY user — grep 2026-05-27; `334-DESIGN-LOCK-AFKING.md §5.2`).

**Within-cluster ordering (D-09 — the mutual dependency):**

AfKing is `burnForKeeper`'s **only** caller, and `onlyAfKing` gates **only** `burnForKeeper`. Removing the AfKing call sites and the BurnieCoin implementation must not leave an interface mismatch that compiles broken. Two acceptable orderings:

1. **Delete the AfKing call sites (`:437`, `:641`) + the `IBurnie.burnForKeeper` iface decl (`:57`) BEFORE the BurnieCoin impl (`:472`)** — so at no intermediate point does AfKing reference a `burnForKeeper` that BurnieCoin no longer implements (the iface-mismatch never compiles broken); OR
2. **Delete both atomically in the single diff** — the batched-diff model (BATCH-02 is one diff applied as a whole) makes the intermediate-state concern a **non-issue**: the diff compiles as a coherent whole, so there is no real intermediate compile. The producer-before-consumer narrative still PREFERS deleting the caller side first for reviewer clarity, but the atomic-diff property means either ordering is safe.

> Producer-before-consumer rationale: the AfKing cluster CONSUMES the `lazyPassHorizon` view (Step 2 producer) — so it is authored after the facade. Within the cluster, the caller-side deletion precedes (or is atomic with) the implementation deletion so no iface mismatch ships.

---

## 2. The shared `_queueTickets` surface reconciliation (D-18)

The single subtle integration item: both WHALE and MINTDIV are RNG-adjacent edits that touch the **same ticket-queue data** (`ticketsOwedPacked`, written via the `_queueTickets`/`_queueTicketRange` family, read by `processTicketBatch`). The map reconciles them as follows:

| Edit | Which end of the shared data | What it changes | When/How |
|------|------------------------------|-----------------|----------|
| **WHALE** (WHALE-01, Step 3 + the existing claim) | the **WRITER** end | moves **WHEN** the queue is written | box-open no longer queues at open; the queue write happens at **claim-time** via `_queueTicketRange(player, startLevel, 100, ...)` inside `claimWhalePass` (`WhaleModule:1034`). WHALE touches the queue **indirectly** (through the existing `_queueTicketRange`), and only changes the timing/trigger of the write. |
| **MINTDIV** (MINTDIV-02, Step 4) | the **READER** end | fixes **HOW** the reader advances its within-player index | `processTicketBatch:716` `processed += writesUsed >> 1` → `+= take` — the consumer (`processTicketBatch` reads `ticketsOwedPacked` and advances `startIndex`). MINTDIV does not touch the writer side at all. |

**They are INDEPENDENT within the diff — no conflict:**

- WHALE and MINTDIV are on **opposite ends of the same data**: WHALE is the **writer** (WHEN the queue is written — claim-time), MINTDIV is the **reader** (HOW the reader advances — `+= take`).
- WHALE does not change the queue's **storage shape** (`_queueTicketRange` writes the same `ticketsOwedPacked` slots, just at claim-time instead of box-open-time). MINTDIV does not change **what is queued** — it only fixes the within-player `startIndex` advance arithmetic in the consumer.
- Therefore neither edit can perturb the other: a reader-side advance fix is invariant to whether the writer queued at open-time or claim-time, and a writer-side timing change is invariant to how the reader advances its index. The two edits **commute** within the single diff.

This independence is the SC1 integration result: the shared `_queueTickets`/`ticketsOwedPacked` surface is reconciled (writer-vs-reader) with no hidden interaction the IMPL reviewer must reason about.

---

## 3. The contract-commit-boundary HARD STOP (BATCH-02 at 335)

The single batched diff is **applied to `contracts/`** (and `ContractAddresses.sol` is freely modifiable) and **locally compiled/tested** at IMPL 335 — but it is **NOT committed without explicit USER hand-review of the single batched diff** (`feedback_wait_for_approval` / `feedback_manual_review_before_push` / `feedback_no_contract_commits`). The IMPL phase is autonomous up to the diff; it then **HARD STOPs at the contract-commit boundary** for the USER's hand-review (BATCH-02). The auto-advance is HELD at this contract-phase boundary. This map governs the **re-author order**; the commit gate is the USER's.

---

## 4. Summary — the IMPL-335 edit-order at a glance

| Step | File(s) | Role | Producer/Consumer | Key anchors |
|------|---------|------|-------------------|-------------|
| 1 | `DegenerusGameStorage.sol` | confirm `whalePassClaims` decl; `_queueTicketRange`/`_applyWhalePassStats` unchanged | **producer** (the slot Step 3 writes) | `whalePassClaims` (inherited); `Storage:647`/`:1111` |
| 2 | `DegenerusGame.sol` | add `lazyPassHorizon` view (D-11); retire autoOpen gas-weight → flat `OPEN_BATCH` (WHALE-03); confirm `claimWhalePass` entrypoint home (D-01) | **producer** (view for Step 5; claim endpoint for Step 3) | `DegenerusGame:1520`; `:1561`/`:1687`/`:1728`; `WhaleModule:1018` |
| 3 | `DegenerusGameLootboxModule.sol` | replace `_activateWhalePass:1240` 100-loop + `_applyWhalePassStats:1247` with O(1) `whalePassClaims += grant`; flat shape (D-21); no `mintPacked_` at open | **consumer** (writes Step-1 slot; defers to Step-2 claim) | `LootboxModule:1240-1260`; mirror `PayoutUtils:52` |
| 4 | `DegenerusGameMintModule.sol` | `:716` `processed += writesUsed >> 1` → `+= take` (REACHABLE per verdict; one-liner IS in the diff) | **independent** (no WHALE/AFSUB dependency) | `MintModule:716` → match `:502` |
| 5 | `AfKing.sol` + `BurnieCoin.sol` | remove `burnForKeeper`/window; repurpose `Sub` slot → `validThroughLevel`; rewrite subscribe + `_autoBuy:630` + crossing refresh-or-evict (reads `lazyPassHorizon`); preserve OPEN-E + tombstone/swap-pop; BurnieCoin delete `:472`/`:85`/`:549` | **consumer** (reads Step-2 `lazyPassHorizon`); cluster: delete AfKing call sites before/atomic-with BurnieCoin impl | `AfKing:57/89/220/374/430-443/605/630-631`; `BurnieCoin:85/472/549` |

**Shared `_queueTickets` surface:** WHALE = writer (WHEN, claim-time, indirect via `_queueTicketRange`); MINTDIV = reader (HOW, `+= take` advance). Opposite ends — INDEPENDENT, they commute within the single diff.

**HARD STOP:** the whole diff is HELD at the contract-commit boundary for explicit USER hand-review (BATCH-02 at 335).

*Phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu — Plan 334-04 Task 1 (SC1 integration).*
