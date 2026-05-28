<!--
================================================================================
RNG-AUDIT-KIT.md — the paste-into-model artifact (Layout B).

AUTHORING STATUS (Phase 337):
  - Plan 337-01 (this commit) authored ONLY the cold-start CONTEXT PACK below
    (sections "Context Pack 4a" through "Context Pack 4e").
  - Plan 337-02 PREPENDS the protocol head into the RESERVED block immediately
    below this comment: the freeze-invariant TARGET (RNGAUDIT-01), the EXEMPT
    entry-point set, and the R1->R4 multi-round sequence (RNGAUDIT-02). Do not
    author those here.
  - Plan 337-03 authors the companion CHUNK-MANIFEST.md (the human-ops feeding
    manual) as a separate file in this directory.

DISCIPLINE (binding on every plan that edits this file) — see RESEARCH section 4
for the full SHIP/WITHHOLD rule:
  - LOCATORS ONLY. Ship file:line + writer/reader facts + the methodology + the
    invariant target + the structural exempt-entry framing. WITHHOLD every freeze
    conclusion about any specific slot; ship the facts and let the reader derive.
  - SELF-CONTAINED. Carry no pointer to any internal milestone report or internal
    read-graph dump, and no prior-milestone conclusion. This file stands alone on
    the attached source.
  - All anchors are sourced from the companion 337-ANCHOR-ATTESTATION.md in this
    directory, re-resolved against the frozen post-v50 tree.
================================================================================
-->

<!-- ============================================================ -->
<!-- RESERVED FOR PLAN 337-02 — PROTOCOL HEAD                      -->
<!--   Freeze-invariant TARGET (RNGAUDIT-01)                       -->
<!--   Exempt entry-point set (the 4 legitimate VRF-window writers)-->
<!--   R1 -> R2 -> R3 -> R4 multi-round sequence (RNGAUDIT-02)      -->
<!-- 337-02 prepends here; 337-01 leaves this block empty.         -->
<!-- ============================================================ -->

# Degenerus Protocol — RNG-Audit Kit

> **What this file is.** A self-contained cold-start package for an independent model to audit the Degenerus RNG-freeze property against the source you attach. It gives you the codebase orientation — which storage slots participate in VRF-derived output, how the daily RNG lock works mechanically, where the VRF word enters and is consumed, the full contract inventory, and the method for tracing a variable across modules — and asks you to build your OWN read-graph and reach your OWN conclusions from the attached `contracts/` source. It deliberately ships no conclusions of its own.
>
> **How to read the locators.** Every `file:line` below points at code in the attached source. Resolve each one yourself; do not take any locator on faith. All anchors were resolved against a frozen contract tree — the companion `CHUNK-MANIFEST.md` (authored separately) describes how to attach the source per model and which files must travel together so the cross-module read-graph survives a chunked feed.

---

## Context Pack 4a — Module / RNG-Window Map

The storage slots/variables that participate in (or gate) VRF-derived output, the owning area, and where each is declared. These are LOCATORS — resolve each declaration and trace its writers/readers yourself (the method is in 4e). The daily RNG window is the interval the `rngLockedFlag` mechanics (4b) describe.

| Slot / variable | Declaration (`file:line`) | One-line role | RNG-window relevance to trace |
|-----------------|---------------------------|---------------|-------------------------------|
| `rngLockedFlag` | `contracts/storage/DegenerusGameStorage.sol:279` (bit-doc `:55`) | The daily RNG lock flag itself. | The flag the write-time gate (4b) reads. |
| `rngWordCurrent` | `contracts/storage/DegenerusGameStorage.sol:374` | The current-cycle VRF word. | Set on the VRF callback path; flows to the consume sites (4c). |
| `rngWordByDay[day]` | `contracts/storage/DegenerusGameStorage.sol:436` | Per-day VRF word keyed by game day. | Day-keyed record of the resolution word. |
| `lootboxRngWordByIndex[index]` | `contracts/storage/DegenerusGameStorage.sol:1401` | Per-index committed lootbox word. | Consumed for box traits (4c); a `!= 0` gate sits at `DegenerusGameMintModule.sol:1414`. |
| far-future ticket queue (`_queueTickets` / `_queueTicketsScaled` / `_queueTicketRange`) | defs `contracts/storage/DegenerusGameStorage.sol:560` / `:594` / `:647` | The three functions that enqueue tickets; far-future writes pass the write-time gate. | Write-time gates at `:573` / `:605` / `:661` (4b). |
| `whalePassClaims[player]` | `contracts/storage/DegenerusGameStorage.sol:955` | Per-player whale-pass claim counter. | Box-open writes `+= 1` at `DegenerusGameLootboxModule.sol:1253` (the third writer); other writers at `DegenerusGamePayoutUtils.sol:52` and `DegenerusGameJackpotModule.sol:1410`; read+zeroed by `claimWhalePass` at `DegenerusGameWhaleModule.sol:1020`/`:1024`. |
| `level` | `contracts/storage/DegenerusGameStorage.sol:245` (`uint24 public level = 0;`) | Current game level (public auto-getter). | Read by the claim path (`level + 1` at `DegenerusGameWhaleModule.sol:1030`). |
| `_livenessTriggered` (terminal-freeze input) | def `contracts/storage/DegenerusGameStorage.sol:1213` | Terminal-freeze predicate. | Gate call-sites `:571` / `:602` / `:655`; grace `_VRF_GRACE_PERIOD = 14 days` at `:198`. |

## Context Pack 4b — rngLock Mechanics

These are the mechanical facts of the daily RNG lock. Resolve each line and trace the readers/writers yourself.

- **Declaration:** `rngLockedFlag` is declared at `contracts/storage/DegenerusGameStorage.sol:279`; the packed-slot bit-doc is at `:55`.
- **Set true at lock:** `contracts/modules/DegenerusGameAdvanceModule.sol:1640` (`rngLockedFlag = true;`).
- **Cleared in `_unlockRng`:** def at `contracts/modules/DegenerusGameAdvanceModule.sol:1719`; set false at `:1721` (`rngLockedFlag = false;`).
- **The write-time gate**, present verbatim in all three ticket-queue functions:
  ```solidity
  if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
  ```
  at `contracts/storage/DegenerusGameStorage.sol:573` (in `_queueTickets`), `:605` (in `_queueTicketsScaled`), and `:661` (in `_queueTicketRange`).
- **The terminal freeze:** `_livenessTriggered` is defined at `contracts/storage/DegenerusGameStorage.sol:1213`; its gate call-sites are `:571` / `:602` / `:655`; the grace period constant is `_VRF_GRACE_PERIOD = 14 days` at `:198`.
- **Coinflip-timing mirror:** `BurnieCoin.sol` reads `degenerusGame.rngLocked()` at `contracts/BurnieCoin.sol:455` (claim-shortfall path) and `:470` (consume-shortfall path); the Game-side `rngLocked()` view is at `contracts/DegenerusGame.sol:2471`. These are coinflip-timing gate locators.

(These are mechanics. Whether any given slot is or is not frozen during the window is exactly what you derive in your own rounds — this file does not state it.)

## Context Pack 4c — Where the VRF Word Enters and Is Consumed

- **Entry (VRF callback):** `rawFulfillRandomWords` at `contracts/modules/DegenerusGameAdvanceModule.sol:1735` (facade dispatch `contracts/DegenerusGame.sol:2226`, selector `:2234`).
- **Failsafe entry:** `retryLootboxRng` at `contracts/modules/DegenerusGameAdvanceModule.sol:1105` (facade dispatch `contracts/DegenerusGame.sol:2177`, selector `:2182`).
- **Gate:** `rngGate(...)` at `contracts/modules/DegenerusGameAdvanceModule.sol:1152` returns `(uint256 word, uint32 gapDays)`.
- **Consume driver:** `advanceGame()` at `contracts/modules/DegenerusGameAdvanceModule.sol:154`.
- **Consume sites the word flows into** (LOCATIONS — trace each):
  - `_processFutureTicketBatch` — def `contracts/modules/DegenerusGameAdvanceModule.sol:1418` (called with the word at `:398`).
  - `_emitDailyWinningTraits` — def `contracts/modules/DegenerusGameAdvanceModule.sol:955` (called at `:355`).
  - `payDailyJackpot` — def `contracts/modules/DegenerusGameAdvanceModule.sol:888` (called at `:367` / `:450`); module body `contracts/modules/DegenerusGameJackpotModule.sol:320`.
  - `_distributeYieldSurplus` — def `contracts/modules/DegenerusGameAdvanceModule.sol:675` (called at `:407`).
  - `quests.rollLevelQuest` — call at `contracts/modules/DegenerusGameAdvanceModule.sol:426`; def `contracts/DegenerusQuests.sol:1781` (`function rollLevelQuest(uint256 entropy)`).
  - `_gameOverEntropy` — def `contracts/modules/DegenerusGameAdvanceModule.sol:1241` (called at `:531`).
  - **Lootbox path** via `lootboxRngWordByIndex[index]` — read at `contracts/modules/DegenerusGameLootboxModule.sol:510` / `:587` / `:616` and consumed for traits at `contracts/modules/DegenerusGameMintModule.sol:696`; the within-player trait-batch advance is at `contracts/modules/DegenerusGameMintModule.sol:720` (`processed += take;`), matching the reference loop `processFutureTicketBatch` advance at `:502`; the `!= 0` gate is at `contracts/modules/DegenerusGameMintModule.sol:1414`.

## Context Pack 4d — Contract Inventory

The Degenerus game executes through a delegatecall facade: `contracts/DegenerusGame.sol` dispatches into specialized module files that all share one storage layout (`contracts/storage/DegenerusGameStorage.sol`). **A consequence you must keep in mind while tracing: the writer and the reader of a single storage slot frequently live in different module files.** The slot layout in `DegenerusGameStorage.sol` is the shared anchor every cross-module trace resolves against.

**There are 11 game modules under `contracts/modules/`** (the legacy "10 modules" framing in older repo docs is stale):

| Module file | One-line role (neutral) |
|-------------|--------------------------|
| `DegenerusGameAdvanceModule.sol` | Level advancement; VRF request/callback entry; the consume driver and the lock lifecycle. |
| `DegenerusGameBoonModule.sol` | Deity-boon effects. |
| `DegenerusGameDecimatorModule.sol` | Decimator mechanics. |
| `DegenerusGameDegeneretteModule.sol` | Degenerette betting and resolution. |
| `DegenerusGameGameOverModule.sol` | Game-over distribution. |
| `DegenerusGameJackpotModule.sol` | Daily jackpot drawings. |
| `DegenerusGameLootboxModule.sol` | Lootbox opening / EV; the box-open whale-pass record. |
| `DegenerusGameMintModule.sol` | Ticket purchasing; trait derivation from the committed lootbox word. |
| `DegenerusGameMintStreakUtils.sol` | Mint-streak helper utilities. |
| `DegenerusGamePayoutUtils.sol` | Payout helper utilities. |
| `DegenerusGameWhaleModule.sol` | Whale bundles / lazy passes / deity passes; the `claimWhalePass` materializer. |

Plus the storage + facade + named consume site + peripherals the read-graph touches:

| File | One-line role (neutral) |
|------|--------------------------|
| `contracts/storage/DegenerusGameStorage.sol` | The shared storage layout, the three ticket-queue functions + write-time gates, `_livenessTriggered`, and the slot declarations. |
| `contracts/DegenerusGame.sol` | The delegatecall facade/dispatcher; also hosts `lazyPassHorizon` (`:1540`), `autoOpen` (`:1695`), `enqueueBoxForAutoOpen` (`:1588`), the `rngLocked()` view (`:2471`), and the VRF-callback dispatch. |
| `contracts/DegenerusQuests.sol` | Quest system; the named VRF consume site `rollLevelQuest` (`:1781`). |
| `contracts/AfKing.sol` | Keeper contract; reads `lazyPassHorizon` and `level` for pass-gating (trace whether anything it touches is VRF-participating). |
| `contracts/BurnieCoin.sol` | BURNIE token; mirrors `degenerusGame.rngLocked()` at `:455` / `:470` for coinflip-shortfall timing. |
| `contracts/BurnieCoinflip.sol` | Coinflip resolution. |
| `contracts/DegenerusJackpots.sol` | Jackpot state/helper logic. |
| `contracts/GNRUS.sol` | Soulbound charity token. |

## Context Pack 4e — Cross-Module Variable-Tracing Methodology

Apply this back-and-forth method to every participating variable:

> **Trace every participating variable across every module — what writes it, what reads it, and what is locked during an RNG window.** Because of the delegatecall facade, the writers and readers of one storage slot can live in different module files; follow the slot, not the file. A slot qualifies as frozen during the window only if EVERY writer either cannot fire during the lock or reverts when it tries; a single writer that can still fire and mutate the slot during the window breaks the invariant.

This is a method for YOU to derive each slot's status from the attached source — it is stated as a conditional ("frozen only if EVERY writer…"), not as a claim about any particular slot. For each slot in 4a:

1. Enumerate every writer (search the attached source across all module files — do not assume the writer is in the same file as the declaration).
2. For each writer, determine from the code whether it can execute while `rngLockedFlag` is set (4b), and whether it reverts if it tries (e.g. via the write-time gate).
3. Enumerate every reader / consume site (4c) and check what it reads relative to the lock window.
4. Decide the slot's status for yourself, and record the file:line evidence for each writer/reader so your conclusion is reproducible from source.

The exempt entry points (supplied in the protocol head reserved above) are the only writes you may take as the legitimate resolution; your job for those slots is to confirm from source that nothing OTHER than an exempt entry writes them.
