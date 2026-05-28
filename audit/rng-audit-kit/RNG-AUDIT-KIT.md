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

# Degenerus Protocol — RNG-Audit Kit

## 1 — The Freeze Invariant (Your Target)

This kit drives YOU — an independent model with no prior exposure to this codebase — to verify ONE property of the Degenerus RNG machinery, from the attached source alone. You are not asked to grade our work; there is no "our work" in this kit. You are asked to re-derive the answer yourself.

Your single target is this property, stated verbatim as the acceptance bar:

> while `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word + its deterministic derivations may be unknown

An equivalent restatement, in operational terms: no player-reachable path may write a slot that feeds a VRF-derived output after the VRF word that resolves it becomes requestable/known, until the lock clears. The terminal-jackpot variant of this property is enforced through a separate mechanism — the `_livenessTriggered` terminal freeze (see the Context Pack 4b for both the lock gate and the terminal-freeze gate) — so treat the terminal case as a distinct sub-question rather than folding it into the daily-lock analysis.

The mechanics this property ranges over — the lock lifecycle, the write-time gate, where the VRF word enters and is consumed, the participating slots, and the cross-module tracing method — are all in the **Context Pack** below (sections 4a–4e). Resolve every locator there against the source yourself.

This kit does NOT tell you whether the property above is satisfied. Reaching that verdict — per slot, with evidence — is your entire job, carried out through the four rounds in section 3.

## 2 — Exempt Entry Points (the legitimate VRF-window writers)

Four entry points legitimately write VRF-window slots **because they ARE the resolution** — they constitute the daily settlement that consumes the VRF word and writes the derived outputs. You are TOLD these four are exempt so you do not mis-classify the resolution itself as an offending writer. You must then independently confirm, from the attached source, that nothing OTHER than an exempt entry writes the participating slots. Everything outside this set must be frozen during the lock; whether it actually is, is for you to determine in section 3.

| Exempt entry | Anchor (`file:line` at the audited HEAD) | Why exempt (structural, one line) |
|--------------|------------------------------------------|-----------------------------------|
| `advanceGame()` + the reachable resolution flow it drives | `contracts/modules/DegenerusGameAdvanceModule.sol:154` | The consume driver — it IS the daily resolution that writes the VRF-derived outputs. |
| `rawFulfillRandomWords` (VRF coordinator callback) | `contracts/modules/DegenerusGameAdvanceModule.sol:1735` (facade dispatch `contracts/DegenerusGame.sol:2226`) | Delivers the VRF word — the entropy source itself. |
| `retryLootboxRng()` failsafe | `contracts/modules/DegenerusGameAdvanceModule.sol:1105` (facade dispatch `contracts/DegenerusGame.sol:2177`) | The lootbox-RNG retry path — part of the resolution machinery. |
| `rngGate(...)` (returns the `rngWord`) | `contracts/modules/DegenerusGameAdvanceModule.sol:1152` | The gate that hands the consumed word to the resolution flow. |

This exempt-entry framing is the ONLY near-conclusion this kit gives you: it is structural orientation telling you WHERE the legitimate resolution writes live, NOT a statement about the freeze status of any other slot. Do not read it as a verdict. Your task is precisely to check whether any writer outside these four can mutate a participating slot during the lock.

## 3 — The Protocol (Multi-Round, Self-Driven)

This is a **blind review.** Verify every claim from the source you are given — never from a comment, never from this kit's prose, never from memory of any other protocol. Treat each `file:line` as a pointer to resolve, not a fact to accept.

Run the four rounds **in order, in a single multi-turn session.** Each round builds on the previous one's output. Because a long session can evict earlier context, **persist your R1 catalog as an artifact** and paste it back at the top of each later round, so R2/R3/R4 always have the full read-graph in front of them.

The discipline that makes this an external audit:

> You are given the codebase, the methodology, and the invariant target — and nothing about what the answer should be. Re-derive everything from source. A different perspective is the entire point.

Concretely, this kit embeds no per-slot freeze classification, no statement of what we concluded, and no pointer to our internal findings or catalog documents. Where a sentence here looks like it is telling you an outcome, it is not — it is telling you what to DO. The outcomes are yours to produce, in your own words, in R4.

### R1 — Catalog the VRF Read-Graph

Build the catalog yourself — you are not handed a pre-built answer. Enumerate EVERY storage slot that participates in any VRF-influenced output, and for each slot list its **writers AND readers** across the full surface: all 11 game modules under `contracts/modules/`, the shared `contracts/storage/DegenerusGameStorage.sol`, the `contracts/DegenerusGame.sol` facade, and the peripheral contracts (see the Context Pack 4d inventory). Use the **Context Pack** below (4a–4e) as your starting set of locators and the tracing method — then expand it by searching the attached source for every additional writer/reader the locators lead you to. Record a `file:line` for every writer and reader so the catalog is reproducible from source. The delegatecall facade means a slot's writer and its reader frequently live in different module files — follow the slot, not the file.

### R2 — Independently Re-Derive Each Slot's Freeze Status

For each slot in your R1 catalog, classify it — re-derived from the source, not copied from anywhere — into exactly one of these three output categories:

- **frozen** — no path can change the slot while the lock is set;
- **reverts-if-written-during-lock** — a write attempt during the lock is rejected by a gate (e.g. the write-time gate in 4b);
- **proven-non-participating** — the slot does not actually feed any VRF-derived output, so the freeze property does not apply to it.

These three labels are YOUR output categories — the choice you make per slot. This kit deliberately leaves every slot unclassified; do not treat any locator above or in the Context Pack as pre-assigning a category. For each slot, record the writers you found, whether each writer can fire while `rngLockedFlag` is set (and whether it reverts if it tries), and the `file:line` evidence that justifies the category you chose.

### R3 — Adversarially Challenge the Catalog

Now attack your own R1/R2. This is the zero-day-hunting leg: assume your classifications are wrong and try to break them. Hunt for two things specifically:

1. **A single writer that evades the lock** — any path that mutates a participating slot while the lock is set, without reverting.
2. **A cross-module composition that does the same** — a sequence of calls across different modules that, individually, each look fine, but together perturb a frozen input (the delegatecall modules share one storage layout, so module A's write can change what module B's later call reads).

Emulate the **zero-day-hunter** methodology as a METHOD to apply against THIS subject — explicitly NOT as a list of pre-existing findings (this kit ships none). Apply these two lenses:

- **Cross-contract / cross-module state composition** — state assumptions that hold for each module individually but break when modules interact through the shared Game storage; ordering and interleaving dependencies; a delegatecall to one module leaving storage in a state that makes the next module's call behave differently.
- **Edge-of-lifecycle states** — pre-first-purchase, exact level-boundary transitions, post-gameover residual calls, empty-level processing (a resolution over a level with zero tickets), and partial multi-step gameOver (the advance → VRF request → fulfill → advance sequence) where something executes between the steps.

For every candidate evasion you construct, either carry it forward to R4 as a discrepancy to resolve, or record the specific mechanism that defeats it (with `file:line`) so R4 can confirm your reasoning.

### R4 — Reconcile and Report

Reconcile your R2 classifications against your R3 challenges. Resolve every discrepancy — if R3 surfaced a candidate evasion that R2 had classified as frozen, run it down to a definite outcome. Then report, in your OWN words:

- the verified freeze status per slot (the category from R2, after R3's scrutiny), each with its `file:line` evidence;
- any writer or composition you found that mutates a participating slot during the lock;
- and, for every area where you found nothing wrong, state "no issue found" explicitly — do not inflate a non-issue into a finding, and do not stay silent (an explicit "no issue found, here is why" is a result).

Cite `file:line` for every claim. The report is your independent verdict on the target property in section 1 — produced from the source, by you.

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
