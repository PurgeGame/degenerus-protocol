# Phase 334 — RNGAUDIT External-Protocol Structure Sketch (SC4)

**Authored:** 2026-05-27
**Requirement:** BATCH-01 (fix the RNGAUDIT structure); the authoring target for RNGAUDIT-01..04 (Phase 337).
**Status:** STRUCTURE SKETCH ONLY. This document fixes the Phase-337 authoring target — the R1→R4 sequence, the cold-start context-pack skeleton, and the no-answer-key / package-only / model-agnostic framing. **Full authoring of the external RNG-audit kit happens at Phase 337, against the FROZEN post-v50 contract tree** (i.e. after the IMPL 335 batched diff lands and is frozen). This sketch does NOT author the kit and ships NO internal audit conclusions.

> Every VRF / lock anchor cited here is grep-attested in `334-GREP-ATTESTATION.md` §3 vs the frozen baseline `b0511ca2`.

---

## 1. The freeze invariant — the external auditor's target (RNGAUDIT-01 input)

The single property the external model is driven to independently verify, grounded in `v45-vrf-freeze-invariant`:

> **While `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word and its deterministic derivations may be unknown.**

Equivalently: no player-reachable path may write a slot that feeds a VRF-derived output after the VRF word that resolves it becomes requestable/known, until the lock clears. The terminal-jackpot variant is enforced separately by the `_livenessTriggered` freeze.

---

## 2. Exempt entry points (the legitimate VRF-window writers)

These four legitimately write VRF-window slots **because they ARE the resolution** — the external model must be told they are exempt, then must independently confirm nothing ELSE writes those slots:

| Exempt entry | Anchor | Why exempt |
|--------------|--------|------------|
| `advanceGame()` + the reachable resolution flow it drives | `AdvanceModule.sol:154` | The consume driver — it IS the daily resolution that writes the VRF-derived outputs. |
| VRF coordinator callback `rawFulfillRandomWords` | `AdvanceModule.sol:1735` (+ `DegenerusGame.sol:2226`) | Delivers the VRF word — the entropy source itself. |
| `retryLootboxRng()` failsafe | `AdvanceModule.sol:1105` (+ `DegenerusGame.sol:2177`) | The lootbox-RNG retry path — part of the resolution machinery. |
| `rngGate(...)` (returns the `rngWord`) | `AdvanceModule.sol:1152` | The gate that hands the consumed word to the resolution flow. |

Everything outside this set must be frozen during `rngLock`.

---

## 3. The R1→R4 multi-round sequence (D-17 — the sketch headings 337 fills)

The external protocol is a four-round adversarial discovery driven by the model itself:

### R1 — Catalog the VRF read-graph
Enumerate every storage slot that participates in any VRF-influenced output, with its **writers and readers across all 11 modules** + Storage + the facade + peripherals. The model builds this catalog from the context pack (§4) — it is not handed a pre-built answer.

### R2 — Independently re-derive each slot's freeze status
For each catalogued slot, the model independently classifies it as one of: **frozen** (cannot change during the lock), **reverts-if-written-during-lock** (a write attempt reverts via a gate), or **proven-non-participating** (does not feed any VRF-derived output). The classification must be re-derived from source, not copied.

### R3 — Adversarially challenge the catalog
Hunt for any writer that **escapes the freeze** (a path that mutates a participating slot during the lock without reverting), and any **cross-module composition** that does (a sequence of calls across modules that together perturb a frozen input). This is the zero-day-hunter leg: the model attacks its own R1/R2 conclusions.

### R4 — Reconcile and report
Reconcile R2 vs R3, resolve every discrepancy, and report the verified freeze status per slot + any escape found. The report is the model's OWN findings.

---

## 4. The self-contained cold-start context-pack skeleton (the sections 337 fills)

The kit must be runnable from a cold start by a model with NO prior knowledge of the codebase. The skeleton sections:

### 4a. Module / RNG-window map
The set of slots that participate in VRF-derived outputs and which module owns each, mapped to the daily RNG window. (337 fills the per-slot rows against the frozen post-v50 tree.)

### 4b. `rngLock` mechanics
- `rngLockedFlag` declaration `DegenerusGameStorage.sol:279` (bit-doc `:55`); set `true` at lock `AdvanceModule.sol:1640`, set `false` in `_unlockRng` `AdvanceModule.sol:1719`/`:1721`.
- The **write-time gate**: `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` present in `_queueTickets` (`Storage:573`), `_queueTicketsScaled` (`Storage:605`), `_queueTicketRange` (`Storage:661`).
- The terminal freeze: `_livenessTriggered` def `Storage:1213` (gate call-sites `:571`/`:602`/`:655`), `_VRF_GRACE_PERIOD = 14 days` `Storage:198`.
- `BurnieCoin.rngLocked()` mirrors the Game flag for coinflip paths.

### 4c. Where the VRF word enters and is consumed
- **Entry:** `rawFulfillRandomWords` (`AdvanceModule:1735` / `DegenerusGame:2226`); failsafe `retryLootboxRng` (`AdvanceModule:1105` / `DegenerusGame:2177`).
- **Gate:** `rngGate` (`AdvanceModule:1152`) returns the `rngWord`; **consume driver** `advanceGame` (`AdvanceModule:154`).
- **Consume sites the word flows into:** `_processFutureTicketBatch`, `payDailyJackpot`, `_distributeYieldSurplus`, `quests.rollLevelQuest`, `_emitDailyWinningTraits`, `_gameOverEntropy`, and the lootbox path via `lootboxRngWordByIndex[index]` (consumed in `processTicketBatch:696` and the box-open seed).

### 4d. Contract inventory
The 11 game modules under `contracts/modules/` (Advance, Boon, Decimator, Degenerette, GameOver, Jackpot, Lootbox, Mint, MintStreakUtils, PayoutUtils, Whale) + `contracts/storage/DegenerusGameStorage.sol` + the `DegenerusGame.sol` facade + the peripheral contracts (AfKing, BurnieCoin, BurnieCoinflip, DegenerusJackpots, GNRUS).

### 4e. Cross-module variable-tracing methodology
The back-and-forth method the model applies: **trace every variable across modules — what writes it, what reads it, what is locked during an RNG window.** A slot is only "frozen" if EVERY writer either cannot fire during the lock or reverts; a single escaping writer breaks the invariant. The model is instructed to follow each participating variable through every module that touches it (the delegatecall facade means writers and readers can live in different module files for the same storage slot).

---

## 5. The constraints (D-17) — what makes this an EXTERNAL audit

1. **No answer key.** The constraint, verbatim: "drive the external model's OWN discovery — no answer key, no embedded internal findings." No pre-built freeze conclusions, no "we already found X." The entire point is a **different perspective**: a model that re-derives the freeze status from source will surface things the internal audit's framing might miss. The kit ships the codebase + the methodology + the invariant target, and nothing about what the answer "should" be.
2. **Package-only.** Phase 337 authors the deliverable PACKAGE. Actually running it through Gemini / ChatGPT and triaging the output is a **FUTURE cycle, OUT of v50.0 scope** (RNGAUDIT is package-only).
3. **Model-agnostic.** The kit must be usable in BOTH Gemini and ChatGPT, with **context-window chunking guidance** for feeding the contracts (the codebase exceeds a single context window; the kit specifies how to chunk the modules so the read-graph survives the split).

---

## 6. Scope marker

This is a **STRUCTURE SKETCH**. It fixes the R1→R4 sequence, the cold-start context-pack skeleton, the exempt entry points, the freeze-invariant target, and the no-answer-key / package-only / model-agnostic framing. **Full authoring of the RNGAUDIT external kit is Phase 337, against the FROZEN post-v50 contract tree** — i.e. after the IMPL 335 batched diff lands, so the kit audits the actual shipped surface (the O(1) whale-pass claim + the MintModule fix + the AfKing pass-gating), not the pre-v50 baseline. This sketch records no internal audit conclusions and is not the kit.

*Phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu — Task 3 (SC4).*
