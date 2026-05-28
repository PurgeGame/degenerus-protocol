# Phase 337: AUDIT-PROTOCOL — Model-Agnostic Multi-Round External-LLM RNG-Audit Kit (Package-Only) — Research

**Researched:** 2026-05-28
**Domain:** Documentation / deliverable authoring (NOT code implementation). Factual cataloging of the frozen post-v50 contract tree + practical LLM-packaging guidance.
**Confidence:** HIGH (all contract anchors grep-verified against current HEAD `f65fb0f1`; context-window numbers CITED to current sources; packaging precedent read in-repo)

---

## Summary

Phase 337 authors a **single self-contained markdown deliverable** (the "RNG-Audit Kit") that a human will later paste into Gemini / ChatGPT to drive an independent, multi-round, no-answer-key audit of the Degenerus RNG-freeze invariant. There are **ZERO `contracts/*.sol` edits** — the subject is byte-frozen at the v50.0 IMPL commit `e756a6f3` (`git diff e756a6f3 HEAD -- contracts/` is empty). The deliverable is consumed by a FUTURE cycle; running it is explicitly OUT of scope. Planning is therefore about (a) re-attesting every file:line anchor the kit's context pack cites against the current post-v50 tree, (b) drawing the answer-key vs context-pack boundary precisely, (c) sizing the contract corpus for chunking guidance, and (d) making the authored doc grep-checkable without an external model.

The 334 SPEC sketch (`334-RNGAUDIT-STRUCTURE-SKETCH.md`) already locks the structure: the freeze-invariant target (RNGAUDIT-01), the R1→R4 multi-round sequence (RNGAUDIT-02), the cold-start context-pack skeleton (RNGAUDIT-03), and the model-agnostic / package-only framing (RNGAUDIT-04). **337 fills the sketch's headings against the frozen post-v50 surface; it does not redesign the structure.** The repo already contains two relevant packaging precedents — `audit/EXTERNAL-AUDIT-PROMPT.md` (a single-master paste-and-go prompt) and `audit/C4A-CONTEST-README.md` (a scope/context doc) — which the kit should reuse the *tone* of (blind review, verify-from-source, no answer key) while being narrower (RNG-freeze only) and multi-round.

**Primary recommendation:** Plan 337 as a small wave set: (1) re-attest all anchors against HEAD into a fresh attestation table (the 334 table is vs the *pre-v50* `b0511ca2`; several anchors MOVED in the 5 touched files); (2) author the kit as a **two-file split** — `RNG-AUDIT-KIT.md` (protocol R1→R4 + cold-start context pack + freeze-invariant target + feeding recipe) and a `CHUNK-MANIFEST.md` (the contract-corpus chunking map), both under a new `audit/rng-audit-kit/` directory so they do NOT live in or reference `audit/FINDINGS-*.md`; (3) attach a grep-based self-validation checklist (every cited anchor resolves at HEAD, freeze-invariant wording matches the v45 north-star verbatim, no freeze verdicts present, no FINDINGS reference present).

---

## User Constraints (from phase scope — no CONTEXT.md authored yet at research time)

> No `337-CONTEXT.md` exists yet (this is standalone research ahead of discuss/plan). The binding constraints come from REQUIREMENTS.md RNGAUDIT-01..04, the 334 SPEC sketch (locked structure), and the phase objective. Treat these as locked:

### Locked Decisions (from REQUIREMENTS.md + 334 sketch)
- **ZERO `contracts/*.sol` edits.** Subject frozen at `e756a6f3`. Docs/planning + `audit/` deliverable only.
- **Structure is locked by the 334 sketch.** R1→R4 sequence; the cold-start context-pack skeleton (4a module/RNG-window map, 4b rngLock mechanics, 4c VRF entry/consume, 4d contract inventory, 4e cross-module variable-tracing method); the exempt-entry-point set; the freeze-invariant target wording. 337 AUTHORS these against the frozen post-v50 tree; it does not re-derive the structure.
- **No answer key.** "Drive the external model's OWN discovery — no answer key, no embedded internal findings." No freeze verdicts, no "we found no escape," no reference to `audit/FINDINGS-*.md`.
- **Package-only.** Running the kit through Gemini/ChatGPT and triaging output is a FUTURE cycle, OUT of v50.0.
- **Model-agnostic.** Usable in BOTH Gemini and ChatGPT, with context-window chunking guidance.
- **Self-contained.** The kit must NOT depend on access to `audit/FINDINGS-*.md` (RNGAUDIT-03).
- **Authored against the FROZEN post-v50 tree** — must reflect the shipped O(1) whale-pass claim + MintModule fix + AfKing pass-gating (RNGAUDIT-04), NOT the pre-v50 baseline.

### Claude's Discretion (to be settled at discuss/plan)
- Single-master-doc vs protocol+context-pack+chunk-manifest split (this research recommends the 2-file split; see §7).
- Exact directory location (`audit/rng-audit-kit/` recommended).
- Whether to ship the contracts inline (paste-into-prompt) vs reference-by-path (the human attaches files). Recommended: reference-by-path + a chunk manifest, since 257K tokens is too large to inline in a markdown doc but fits Gemini/GPT API context as attached files.
- Depth of the cross-module variable-tracing worked example (one neutral worked trace vs a method description only).

### Deferred Ideas (OUT OF SCOPE)
- Running the kit / triaging external-model output (FUTURE cycle).
- Any contract change surfaced by reading the tree.
- Re-deriving the R1→R4 structure (locked at 334).

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RNGAUDIT-01 | State the freeze invariant precisely as the auditor's target + exempt entry points, grounded in the v45 VRF-freeze invariant. | §1 (verbatim invariant text from the 334 sketch + v45 north-star), §3 (exempt-entry anchors re-attested at HEAD: advanceGame:154, rawFulfillRandomWords:1735, retryLootboxRng:1105, rngGate:1152). |
| RNGAUDIT-02 | MULTI-ROUND R1→R4 adversarial sequence; no answer key, no internal findings. | §4 (answer-key boundary rule — decisive), §6 (R3 mirrors the zero-day-hunter cross-composition + edge-of-lifecycle methodology). The R1→R4 wording is locked by the 334 sketch §3. |
| RNGAUDIT-03 | Self-contained cold-start context pack (module/RNG-window map, rngLock mechanics, VRF entry/consume, contract inventory, variable-tracing method); no dependence on FINDINGS. | §3 (full re-attested anchor set for 4b/4c), §5 (contract inventory + sizes for 4d), §6 (tracing method), §8 (self-containment lint: no FINDINGS reference). |
| RNGAUDIT-04 | Authored vs FROZEN post-v50 tree; model-agnostic (Gemini + ChatGPT, chunking guidance); explicitly package-only. | §2 (post-v50 deltas the read-graph must reflect), §5+§6 (token math + chunking strategy + per-model feeding recipe), §7 (packaging precedent + layout). |
</phase_requirements>

---

## Architectural Responsibility Map

> This is a documentation deliverable; the "tiers" are the kit's information layers, not code tiers.

| Capability (kit layer) | Primary owner | Secondary | Rationale |
|------------------------|---------------|-----------|-----------|
| Freeze-invariant target statement | Kit §1 (protocol) | v45 north-star (`v45-vrf-freeze-invariant`) | The single property the external model verifies; must match the v45 wording. |
| R1→R4 round prompts | Kit §2 (protocol) | zero-day-hunter skill (R3 tone) | The adversarial discovery driver; structure locked at 334. |
| Anchor catalog (slots, writers, readers, file:line) | Kit context pack | This RESEARCH §3 (internal grounding) | NEUTRAL FACTS the kit ships — file:line + writer/reader, NO verdicts. |
| Freeze verdicts ("slot X is frozen because…") | INTERNAL ONLY (this doc §3/§4, FINDINGS) | — | ANSWER KEY — withheld from the kit entirely. |
| Contract corpus + chunking map | Kit chunk-manifest | This RESEARCH §5 | Drives the human's file-attachment / paste recipe per model. |
| Per-model feeding recipe | Kit context pack | This RESEARCH §6 | Token math + Gemini vs ChatGPT-web differences. |

---

## Standard Stack

**Not applicable.** This is a markdown deliverable. No libraries, frameworks, packages, or dependencies are installed or referenced. There is **no Package Legitimacy Audit** (no external packages), **no Environment Availability audit** (the only tools are `git`/`grep`/`forge` already present and used by prior phases), and **no Standard Stack table** (no code is written).

The only "tooling" the kit's *future consumers* use is the external LLM web UI / API (Gemini, ChatGPT) — out of scope to install; the kit only documents how to feed them.

---

## Post-v50 Anchor Re-Attestation (Research Question 1) — HIGH confidence

**Why this matters:** the 334 sketch + 334-GREP-ATTESTATION cite anchors vs the *pre-v50* baseline `b0511ca2`. The v50 IMPL diff (`e756a6f3`) touched **exactly 5 files** — `AfKing.sol`, `BurnieCoin.sol`, `DegenerusGame.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`. **`AdvanceModule.sol` and `DegenerusGameStorage.sol` were NOT touched**, so every VRF/lock anchor in those two files is byte-identical to `b0511ca2`. Anchors in the 3 touched code files (Lootbox, Mint, Game) MOVED. Every line below was re-confirmed with `grep`/`sed` against the working tree at HEAD `f65fb0f1` (which == `e756a6f3` under `contracts/`).

### A. Lock lifecycle + write-time gate (Storage + AdvanceModule — UNCHANGED files)

| Anchor | Confirmed `file:line` (HEAD) | vs 334 sketch | Status |
|--------|------------------------------|---------------|--------|
| `rngLockedFlag` declaration | `DegenerusGameStorage.sol:279` | `:279` | ✅ unchanged |
| `rngLockedFlag` bit-doc | `DegenerusGameStorage.sol:55` (`[21:22] rngLockedFlag`) | `:55` | ✅ unchanged |
| lock set-true | `DegenerusGameAdvanceModule.sol:1640` (`rngLockedFlag = true;`) | `:1640` | ✅ unchanged |
| `_unlockRng` def | `DegenerusGameAdvanceModule.sol:1719` | `:1719` | ✅ unchanged |
| unlock set-false | `DegenerusGameAdvanceModule.sol:1721` (`rngLockedFlag = false;`) | `:1721` | ✅ unchanged |
| write-time gate `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` | `DegenerusGameStorage.sol:573` (`_queueTickets`), `:605` (`_queueTicketsScaled`), `:661` (`_queueTicketRange`) | `:573/:605/:661` | ✅ all 3 unchanged |
| `_livenessTriggered` def | `DegenerusGameStorage.sol:1213` (body `:1221`) | `:1213` | ✅ unchanged |
| `_livenessTriggered` gate call-sites | `DegenerusGameStorage.sol:571` / `:602` / `:655` | `:571/:602/:655` | ✅ unchanged |
| `_VRF_GRACE_PERIOD = 14 days` | `DegenerusGameStorage.sol:198` | `:198` | ✅ unchanged |
| the three queue fns | `_queueTickets` `Storage:560`, `_queueTicketsScaled` `:594`, `_queueTicketRange` `:647` | (defs) | ✅ unchanged |

### B. VRF entry + gate + consume driver (AdvanceModule — UNCHANGED file)

| Anchor | Confirmed `file:line` (HEAD) | vs sketch | Status |
|--------|------------------------------|-----------|--------|
| `advanceGame()` (consume driver — EXEMPT) | `DegenerusGameAdvanceModule.sol:154` | `:154` | ✅ unchanged |
| `rawFulfillRandomWords` (VRF callback — EXEMPT) | `DegenerusGameAdvanceModule.sol:1735` | `:1735` | ✅ unchanged |
| `retryLootboxRng()` failsafe (EXEMPT) | `DegenerusGameAdvanceModule.sol:1105` | `:1105` | ✅ unchanged |
| `rngGate(...)` (returns `rngWord`) | `DegenerusGameAdvanceModule.sol:1152` | `:1152` | ✅ unchanged |

### C. VRF facade dispatch (DegenerusGame.sol — TOUCHED file; verify shifts)

| Anchor | Confirmed `file:line` (HEAD) | 334 sketch said (vs b0511ca2) | Status |
|--------|------------------------------|-------------------------------|--------|
| `retryLootboxRng` facade dispatch | `DegenerusGame.sol:2177` (selector `:2182`) | `:2177` | ✅ same (additions were earlier, at ~1540) |
| `rawFulfillRandomWords` facade dispatch | `DegenerusGame.sol:2226` (selector `:2234`) | `:2226` | ✅ same |
| `rngLocked()` view def | `DegenerusGame.sol:2471` | (not in sketch) | ✅ confirmed |

### D. VRF-word consume sites (where `rngWord` flows — AdvanceModule UNCHANGED + module readers)

| Consume site | Confirmed `file:line` (HEAD) | Notes |
|--------------|------------------------------|-------|
| `_processFutureTicketBatch` | `DegenerusGameAdvanceModule.sol:1418` (called w/ `rngWord` at `:398`) | ✅ |
| `payDailyJackpot` | `DegenerusGameAdvanceModule.sol:888` + `DegenerusGameJackpotModule.sol:320` | ✅ both |
| `_distributeYieldSurplus` | `DegenerusGameAdvanceModule.sol:675` (called at `:407`) | ✅ |
| `quests.rollLevelQuest` | call at `DegenerusGameAdvanceModule.sol:426`; def `DegenerusQuests.sol:1781` | ✅ |
| `_emitDailyWinningTraits` | `DegenerusGameAdvanceModule.sol:955` | ✅ |
| `_gameOverEntropy` | `DegenerusGameAdvanceModule.sol:1241` | ✅ |
| lootbox path `lootboxRngWordByIndex[index]` | slot decl `DegenerusGameStorage.sol:1401`; readers `LootboxModule:510/587/616`, `MintModule:696` (the `processTicketBatch` box-trait consume), gate `MintModule:1414` (`if (lootboxRngWordByIndex[index] != 0) revert E()`) | ✅ |

### E. MintModule MINTDIV anchors (TOUCHED file — the fix landed; +17 lines)

| Anchor | Confirmed `file:line` (HEAD) | 334-GREP said (vs b0511ca2) | Status / drift |
|--------|------------------------------|-----------------------------|----------------|
| `processFutureTicketBatch` (reference-correct advance) | `DegenerusGameMintModule.sol:393`; `processed += take` at `:502` | `:393` / `:502` | ✅ unchanged |
| `processTicketBatch` (def) | `DegenerusGameMintModule.sol:671` | `:671` | ✅ unchanged |
| **the MINTDIV-02 fix** — within-player advance | `DegenerusGameMintModule.sol:720` (`processed += take;` — was `processed += writesUsed >> 1` at `:716` pre-v50) | sketch/seed cited `:716` `>>1` | ⚠️ **CHANGED BY v50.** The suspect `writesUsed >> 1` heuristic is GONE; replaced by `processed += take` at `:720` (aligned with `:502`). `_processOneTicketEntry` now returns `(writesUsed, take, advance)` (was `(writesUsed, advance)`). |
| `_processOneTicketEntry` | `DegenerusGameMintModule.sol:766` | (def) | ✅ signature widened (3-tuple) |
| `_raritySymbolBatch` (LCG/startIndex trait gen) | `DegenerusGameMintModule.sol:546` | `:546` | ✅ unchanged |

### F. Whale-pass O(1) claim anchors (Lootbox + Whale + Payout — Lootbox TOUCHED)

| Anchor | Confirmed `file:line` (HEAD) | 334-GREP said (vs b0511ca2) | Status / drift |
|--------|------------------------------|-----------------------------|----------------|
| `_activateWhalePass` (box-open record) | `DegenerusGameLootboxModule.sol:1250`; body = **`whalePassClaims[player] += 1;`** at `:1253` | sketch cited the inline 100-iter loop `:1250-1260` | ⚠️ **CHANGED BY v50.** The 100-iteration `_queueTickets` loop is RETIRED (WHALE-01). Now a single O(1) accumulator write. Signature changed: no longer returns `ticketStartLevel`. Two constants DELETED: `WHALE_PASS_BONUS_TICKETS_PER_LEVEL`, `WHALE_PASS_BONUS_END_LEVEL`. |
| `whalePassClaims` slot decl | `DegenerusGameStorage.sol:955` (`mapping(address => uint256) internal whalePassClaims;`) | (existing) | ✅ unchanged (Storage untouched) |
| `whalePassClaims` writers | `LootboxModule:1253` (`+= 1`), `PayoutUtils:52` (`+= fullHalfPasses`), `JackpotModule:1410` (`+= whalePassCount`) | (existing 2 + new box-open) | ✅ — box-open writer is the v50 addition; the other two pre-exist |
| `whalePassClaims` readers | `WhaleModule:1020` (read), `:1024` (zero), public getter `DegenerusGame.whalePassClaimAmount():2645` | (existing) | ✅ |
| `claimWhalePass(address player)` (materialize) | `DegenerusGameWhaleModule.sol:1018`; liveness gate `:1019`; `startLevel = level + 1` `:1030`; stats-at-claim `_applyWhalePassStats` `:1032`; `_queueTicketRange(player, startLevel, 100, halfPasses, false)` `:1034` | `:1018` | ✅ unchanged (WhaleModule NOT touched by v50) |
| `_applyWhalePassStats` def | `DegenerusGameStorage.sol:1111` | `:1111` | ✅ unchanged |
| `_applyWhalePassStats` call sites (the 3) | `LootboxModule` — **REMOVED** (the box-open caller is gone post-v50); `WhaleModule:1032` (the claim — untouched); `DecimatorModule:588` (immediate-apply — untouched) | sketch listed 3 incl. `LootboxModule:1247` | ⚠️ **CHANGED BY v50.** Pre-v50 there were 3 callers; the box-open caller (`LootboxModule:1247`) was DELETED with the loop. Now only 2 callers: `WhaleModule:1032` (claim) + `DecimatorModule:588`. |
| `_queueTicketRange` (the claim's far-future consume) | `DegenerusGameStorage.sol:647`; liveness `:655`; far-future+rngLock revert `:661` | `:647/:655/:661` | ✅ unchanged |

### G. WHALE-03 autoOpen + the new lazyPassHorizon view (DegenerusGame — TOUCHED)

| Anchor | Confirmed `file:line` (HEAD) | 334-GREP said (vs b0511ca2) | Status / drift |
|--------|------------------------------|-----------------------------|----------------|
| `autoOpen(uint256 maxCount)` | `DegenerusGame.sol:1695` | `:1687` | ⚠️ moved +8 (lazyPassHorizon added above it) |
| `enqueueBoxForAutoOpen` | `DegenerusGame.sol:1588` | `:1577` | ⚠️ moved +11 |
| `_autoOpenBox` | `DegenerusGame.sol:1762` | (not in sketch) | ✅ |
| `OPEN_NORMAL_GAS_UNIT = 90_000` (the WHALE-03 carve-out) | **REMOVED** | `:1561` (sketch said retire it) | ⚠️ **CHANGED BY v50** — retired as planned. The autoOpen budget is now flat (`opened < maxCount`), gas-weight constant deleted. |
| **NEW** `lazyPassHorizon(address)` view (D-11) | `DegenerusGame.sol:1540` | (new — not in pre-v50 tree) | ⚠️ **NEW IN v50.** Reads `mintPacked_` deity bit → `type(uint24).max` for deity, else `frozenUntilLevel`. AfKing reads it via `IGame` (`AfKing.sol:39`). NOT VRF-participating. |
| `level` (public auto-getter; AfKing calls `GAME.level()`) | `DegenerusGameStorage.sol:245` (`uint24 public level = 0;`) | (existing) | ✅ — no explicit `function level()`; it's the compiler-generated getter for the public slot |

### H. BurnieCoin rngLocked() mirror (BurnieCoin — TOUCHED but mirror preserved)

| Anchor | Confirmed `file:line` (HEAD) | Notes |
|--------|------------------------------|-------|
| `degenerusGame.rngLocked()` consume sites | `BurnieCoin.sol:455` (`_claimCoinflipShortfall` — returns early if locked), `:470` (`_consumeCoinflipShortfall` — reverts `Insufficient()` if locked) | ✅ both preserved. **Note:** v50 DELETED `burnForKeeper`/`onlyAfKing`/`KeeperBurn` from BurnieCoin (AFSUB-01), but the `rngLocked()` mirror reads are untouched. These gate coinflip-shortfall consumption during the lock — they do NOT feed a VRF-derived *output*; they protect coinflip claim timing. |

### Drift summary (anchors the kit's context pack MUST cite at the NEW line, not the sketch line)

1. **MINTDIV fix moved + changed:** `MintModule:716 (writesUsed>>1)` → `MintModule:720 (processed += take)`. The "suspect advance" no longer exists; cite the aligned `:720`.
2. **Whale box-open record changed:** the `LootboxModule:1250-1260` 100-iter loop → `LootboxModule:1253 (whalePassClaims[player] += 1)`. Cite the O(1) write.
3. **`_applyWhalePassStats` call sites: 3 → 2.** The `LootboxModule:1247` caller is gone. Only `WhaleModule:1032` + `DecimatorModule:588` remain.
4. **`OPEN_NORMAL_GAS_UNIT` deleted; `autoOpen` moved to `:1695`; `enqueueBoxForAutoOpen` to `:1588`.**
5. **NEW `lazyPassHorizon` view at `DegenerusGame:1540`** (non-VRF; AfKing pass-gating producer).
6. **Everything in AdvanceModule + Storage is unchanged** (those files were not in the v50 diff) — the entire lock-lifecycle + VRF-entry + consume-driver + write-gate anchor set is byte-identical to `b0511ca2`. This is the load-bearing simplification: the *VRF machinery itself* did not move.

---

## Post-v50 Deltas the Read-Graph Catalog Must Reflect (Research Question 2) — HIGH confidence

The kit is authored against the FROZEN post-v50 tree, so its contract inventory + variable-trace targets must reflect the shipped surface. The three contract items changed the read-graph as follows:

### WHALE (O(1) whalePassClaims + claimWhalePass)
- **New writer of `whalePassClaims`:** box-open boon now does `whalePassClaims[player] += 1` at `LootboxModule:1253` (replacing the inline 100-level `_queueTickets` mint). The slot `whalePassClaims` (`Storage:955`) gains a third writer.
- **`claimWhalePass` (WhaleModule:1018)** is the deferred materializer: reads+zeros `whalePassClaims`, then `_queueTicketRange(player, level+1, 100, halfPasses, false)` at `:1034`. The queued tickets target **future levels** (`level+1 .. level+100`), and `_queueTicketRange` carries the liveness gate `:655` + the far-future+rngLock revert `:661`.
- **Read-graph impact:** the deferred-claim path adds `whalePassClaims` as a *non-VRF-participating counter* (it gates how many future-level tickets get queued; it is never read by a resolution/consume site). The far-future tickets it queues land in the existing far-future key space the write-gate already protects. **The kit must catalog `whalePassClaims` (slot 955) as a new writer/reader cluster and let the external model classify it** — it must NOT tell the model the classification (that is the answer key; see §4).

### AFSUB (AfKing pass-gating, validThroughLevel)
- **AfKing is a keeper contract; it is NOT in the VRF read-graph.** Pass-gating reads `GAME.lazyPassHorizon(player)` (new view at `DegenerusGame:1540`) and `GAME.level()` (`Storage:245` public getter). Neither participates in any VRF-derived output. The `Sub.paidThroughDay` field was renamed in place to `validThroughLevel` (same uint32 slot offset 5). `burnForKeeper` and the BURNIE prepay window were deleted from both `AfKing.sol` and `BurnieCoin.sol`.
- **Read-graph impact:** essentially none. The AfKing buy path already carried no rngLock guard (buys are freeze-safe by construction; the orphan hazard is handled on the resolution side by the `autoOpen` word-gate). The kit's contract inventory should still INCLUDE `AfKing.sol` (it's a peripheral the external model traces), but the variable-trace targets there are `validThroughLevel`/`lazyPassHorizon`/`level`, none VRF-participating. The relevant freeze-adjacent fact the kit ships as NEUTRAL CONTEXT: `autoOpen` (`DegenerusGame:1695`) has a pre-loop rngLock + liveness entry-gate, and the box-open path reads `lootboxRngWordByIndex[index]`.

### MINTDIV (processed += take alignment)
- **This is the read-graph item with the most direct VRF relevance.** `processTicketBatch` (`MintModule:671`) consumes the committed `lootboxRngWordByIndex[...]` (`:696`) to derive per-ticket traits via `_raritySymbolBatch` (`:546`, the `startIndex`-driven LCG). v50 changed the within-player `startIndex` advance from `writesUsed >> 1` to `processed += take` (`:720`), aligning it with `processFutureTicketBatch:502`. **Read-graph impact:** the *consume* of the frozen word is unchanged; only the index-advance arithmetic that walks `startIndex` across budget slices changed (it now matches the reference loop). The kit must catalog `lootboxRngWordByIndex` (`Storage:1401`) → consumed at `MintModule:696` + `LootboxModule:510/587/616` as a VRF-participating slot, and the trait-derivation as a consume site — but, again, withhold the freeze verdict.

**Net:** the VRF *machinery* (lock lifecycle, VRF entry, consume driver, write-gates) is byte-identical to pre-v50. The deltas the catalog must NEWLY include are: (1) `whalePassClaims` third writer at `LootboxModule:1253` + the `claimWhalePass`→`_queueTicketRange` future-queue path; (2) the `lazyPassHorizon` view + `validThroughLevel` field (non-VRF, but in the inventory); (3) the realigned `processTicketBatch` index advance at `:720` (the consume of the frozen word is unchanged).

---

## The VRF Read-Graph (Research Question 3) — INTERNAL GROUNDING ONLY

> **⚠️ ANSWER-KEY WARNING.** This section is INTERNAL planning grounding. The *facts* (slot, writers, readers, file:line) are NEUTRAL CONTEXT the kit may ship. The *freeze verdicts* in the "Internal freeze status" column are ANSWER KEY and MUST NOT appear in the authored kit. See §4 for the boundary rule.

The slots that participate in (or gate) VRF-influenced output, reconciled against the read-graph evidence:

| Slot / variable | Decl | Writers (file:line) | Readers / consume (file:line) | Internal freeze status (DO-NOT-SHIP) |
|-----------------|------|---------------------|-------------------------------|--------------------------------------|
| `rngLockedFlag` | `Storage:279` | set `Advance:1640`, clear `Advance:1721` | gates `Storage:573/605/661`, `Advance:1017/1696/1745`, `BurnieCoin:455/470` | The lock variable itself — written only by advanceGame/_unlockRng (exempt) |
| `rngWordByDay` / `rngWordCurrent` | (Advance/Storage) | VRF callback path | consumed across `Advance:254/274/308/355/367/398/407/426/438/450` | Set by the VRF callback (exempt entry); consumed by the resolution flow |
| `lootboxRngWordByIndex` | `Storage:1401` | VRF/retry resolution path | `LootboxModule:510/587/616`, `MintModule:696`; gate `MintModule:1414` | The per-index committed word; consumed for box traits |
| ticket queue / `ticketsOwedPacked` / `ticketQueue` (far-future key) | Storage | `_queueTickets:560`, `_queueTicketsScaled:594`, `_queueTicketRange:647` | resolution reads via read-key | Far-future writes gated by `:573/605/661` during lock |
| `whalePassClaims` (v50 NEW writer) | `Storage:955` | `LootboxModule:1253`, `PayoutUtils:52`, `JackpotModule:1410` | `WhaleModule:1020/1024`, getter `Game:2645` | Counter; not read by any consume site — queued tickets are future-level, gated |
| `level` | `Storage:245` | advanceGame flow | everywhere (public getter) | Advanced only by the resolution flow |
| `_livenessTriggered` inputs (`rngStart`) | Storage | VRF lifecycle | `Storage:571/602/655`, `claimWhalePass:1019` | Terminal-freeze gate; `_VRF_GRACE_PERIOD:198` |

### Reconciliation with `.planning/RNGLOCK-CATALOG.md`

- `RNGLOCK-CATALOG.md` is **702.8 KB** (too large to read whole; it is a read-graph dump). Per `project_rnglock_audit_disposition` and REQUIREMENTS.md §"Out of Scope", it is a **maximalist catalog, NOT a list of live exploits** — "111 violations"/135 anchors is a catalog, not live vectors. **The kit must NOT frame it as live vectors, and should NOT ship it** (it would leak an internal framing + is far too large).
- **Stale vs catalog:** the catalog predates v50, so its `LootboxModule` whale-pass rows (the old inline 100-iter loop) are STALE; the post-v50 surface is the O(1) `whalePassClaims += 1` writer. The catalog will not contain the `claimWhalePass`→`_queueTicketRange` post-v50 wiring as the *box-open* path (it had the loop inline).
- **New post-v50:** the `whalePassClaims` third writer (`LootboxModule:1253`) and the `lazyPassHorizon` view (`Game:1540`) are not in the pre-v50 catalog.
- **Disposition for the kit:** do NOT reference or attach `RNGLOCK-CATALOG.md`. The kit ships the *neutral* per-slot writer/reader facts (re-derived fresh from HEAD, §3 + this table's first 4 columns) and lets the external model build its own R1 catalog. The internal catalog stays internal grounding.

---

## THE Answer-Key vs Context-Pack Boundary (Research Question 4) — DECISIVE FOR PLANNING

This is the single most important planning rule. The kit must ship **facts + methodology + the invariant target** and **withhold all verdicts**. Give the planner this rule verbatim:

### The Rule

> **SHIP a statement iff it is verifiable by the external model directly from the source you give it, AND it does not state or imply a freeze conclusion.**
> A neutral *locator* fact ("slot X is written by f() at A:nn and read by g() at B:mm") is SHIPPABLE — it points the model at code it can read itself. A *conclusion* about freeze status ("slot X is frozen", "no writer escapes", "this is safe because…", "we verified Y") is the ANSWER KEY — WITHHELD.

### SHIP (neutral context-pack facts)

- Where the VRF word ENTERS: "the VRF word arrives at `rawFulfillRandomWords` (`AdvanceModule:1735`); the lootbox failsafe is `retryLootboxRng` (`:1105`)."
- Where it is CONSUMED: the consume-site list (§3.D) as *locations*, e.g. "`rngGate` (`:1152`) returns the word to `advanceGame` (`:154`), which flows it into `_processFutureTicketBatch`, `payDailyJackpot`, `_distributeYieldSurplus`, `quests.rollLevelQuest`, `_emitDailyWinningTraits`, `_gameOverEntropy`, and the lootbox path via `lootboxRngWordByIndex`."
- The lock MECHANICS: "`rngLockedFlag` is declared at `Storage:279`, set true at `Advance:1640`, cleared in `_unlockRng` at `:1721`; far-future ticket writes pass through the gate `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()` at `Storage:573/605/661`."
- The EXEMPT entry points (4 of them) with a one-line *reason they are the resolution* (this is structural, not a verdict): advanceGame / rawFulfillRandomWords / retryLootboxRng / rngGate.
- The CONTRACT INVENTORY + file:line writer/reader map (§3, first 4 columns) — pure locators.
- The METHODOLOGY: "trace every participating variable across every module — what writes it, what reads it, what is locked during an RNG window. A slot is only frozen if EVERY writer cannot fire during the lock or reverts; a single escaping writer breaks the invariant." (This is *how to derive*, not the answer.)
- The freeze-invariant TARGET (the property to verify) — RNGAUDIT-01 text. Stating the target is the whole point; it is not the answer.

### WITHHOLD (answer key — INTERNAL only)

- Any **freeze verdict**: "slot X is frozen", "reverts-if-written-during-lock", "proven-non-participating" *as a stated conclusion for a specific slot*. (The model produces these in R2/R4; the kit must not pre-fill them.)
- "**We found no escape**" / "the invariant holds" / "this is safe by construction" — any reassurance.
- The **internal freeze-status column** of §3 (the DO-NOT-SHIP column).
- Any **reference to `audit/FINDINGS-*.md`**, the `RNGLOCK-CATALOG.md` dispositions, prior-milestone verdicts, or "the internal audit concluded…".
- The **WHALE-04 freeze proof** logic ("the queued tickets are future-level so they're gated") — that is exactly the conclusion the external model must reach on its own. Ship the *facts* (`claimWhalePass`→`_queueTicketRange(level+1, …)`, gate at `:661`); withhold the *because-therefore-safe*.
- Any **MINTDIV verdict** ("the realigned advance preserves frozen-word derivation"). Ship the location of the advance (`:720`) + that it consumes `lootboxRngWordByIndex`; withhold the safety conclusion.

### Edge cases (planner guidance)

- **"Exempt entry point" labeling is SHIPPABLE** even though it looks like a conclusion — it is a structural framing the auditor needs (otherwise they'd flag advanceGame as an escaping writer). It tells the model *where the legitimate resolution writes are* so it can verify nothing ELSE writes those slots. This is the one allowed "given." The 334 sketch already treats it this way.
- **Stating the invariant target is SHIPPABLE** — it is the question, not the answer.
- **The contract inventory with "this module owns the lock lifecycle" type structural notes are SHIPPABLE** — they orient, they don't conclude freeze status.
- When in doubt: if removing the sentence would force the external model to *do more independent work*, it was probably answer key — cut it.

---

## Contract Inventory + Sizes for Chunking (Research Question 5) — HIGH confidence

Measured at HEAD with `wc -l`/`wc -c`. Token estimate uses **Solidity ≈ 3.6 chars/token** (conservative; dense Solidity with long identifiers runs 3.4–3.8 — round up for safety).

### The kit-referenced contract set (the 11 modules + storage + facade + 5 peripherals)

| File | Lines | Chars | ~Tokens | Group |
|------|------:|------:|--------:|-------|
| `contracts/DegenerusGame.sol` (facade) | 2,908 | 137,384 | ~38,200 | Core-A |
| `contracts/storage/DegenerusGameStorage.sol` | 1,798 | 85,421 | ~23,700 | Core-A |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1,886 | 83,648 | ~23,200 | RNG-core |
| `contracts/modules/DegenerusGameLootboxModule.sol` | 1,896 | 91,613 | ~25,400 | RNG-core |
| `contracts/modules/DegenerusGameMintModule.sol` | 1,699 | 69,065 | ~19,200 | RNG-core |
| `contracts/modules/DegenerusGameJackpotModule.sol` | 2,149 | 86,605 | ~24,000 | Consume-B |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | 1,160 | 53,270 | ~14,800 | Consume-B |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | 951 | 37,938 | ~10,500 | Consume-B |
| `contracts/modules/DegenerusGameWhaleModule.sol` | 1,043 | 43,017 | ~11,900 | Consume-B |
| `contracts/modules/DegenerusGameBoonModule.sol` | 329 | 13,930 | ~3,900 | Consume-B |
| `contracts/modules/DegenerusGameGameOverModule.sol` | 264 | 12,185 | ~3,400 | Consume-B |
| `contracts/modules/DegenerusGameMintStreakUtils.sol` | 243 | 11,224 | ~3,100 | Consume-B |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | 62 | 2,718 | ~760 | Consume-B |
| `contracts/AfKing.sol` | 978 | 54,083 | ~15,000 | Peripheral-C |
| `contracts/BurnieCoin.sol` | 722 | 34,232 | ~9,500 | Peripheral-C |
| `contracts/BurnieCoinflip.sol` | 1,129 | 45,809 | ~12,700 | Peripheral-C |
| `contracts/DegenerusJackpots.sol` | 669 | 28,834 | ~8,000 | Peripheral-C |
| `contracts/GNRUS.sol` | 709 | 34,406 | ~9,600 | Peripheral-C |
| **SUBTOTAL (18-file core set)** | **20,595** | **925,382** | **~257,000** | |
| `contracts/DegenerusQuests.sol` (`rollLevelQuest` consumer) | 1,915 | 81,712 | ~22,700 | optional RNG-core |
| **TOTAL with Quests** | **22,510** | **1,007,094** | **~280,000** | |

> **Recommendation:** INCLUDE `DegenerusQuests.sol` — `rollLevelQuest(rngWord)` (`:1781`) is a named VRF consume site (`Advance:426`), so the read-graph would be incomplete without it. Total ≈ **280K tokens**.

### Chunking strategy (which files group so the read-graph survives the split)

The freeze invariant is a *cross-module* property — the delegatecall facade means a slot's writer and reader live in different files. Chunking must keep the **write-gate + consume + lock-lifecycle** files together. Recommended groups:

- **Group RNG-CORE (~114K tokens):** `DegenerusGameStorage.sol` (the slot layout + write-gates + `_livenessTriggered` + `_queueTicketRange`), `DegenerusGameAdvanceModule.sol` (lock lifecycle + VRF entry + consume driver), `DegenerusGameMintModule.sol` (trait derivation consume), `DegenerusGameLootboxModule.sol` (box RNG + whale O(1) record), `DegenerusQuests.sol` (`rollLevelQuest` consume). **This group is the irreducible core — never split it.** Storage MUST travel with every group because every freeze claim resolves against the slot layout + the 3 write-gates.
- **Group CONSUME-B (~73K tokens):** `DegenerusGameJackpotModule`, `DegenerusGameDegeneretteModule`, `DegenerusGameDecimatorModule`, `DegenerusGameWhaleModule` (the `claimWhalePass` materializer), `DegenerusGameBoonModule`, `DegenerusGameGameOverModule`, `DegenerusGameMintStreakUtils`, `DegenerusGamePayoutUtils`. The downstream consumers + the whale claim. **Re-attach Storage with this group.**
- **Group FACADE+PERIPHERAL-C (~93K tokens):** `DegenerusGame.sol` (dispatch + `lazyPassHorizon` + `autoOpen`), `AfKing.sol`, `BurnieCoin.sol`, `BurnieCoinflip.sol`, `DegenerusJackpots.sol`, `GNRUS.sol`.
- **Cross-group glue:** because Storage (~24K) must repeat in each chunked group, a 3-group chunking costs ~257K + 2×24K ≈ 305K *effective* tokens — still under a 1M window if done as one feed, but the grouping matters for the ChatGPT-web case (§6) where the human pastes in turns.

---

## Model-Agnostic Feeding Guidance (Research Question 6) — HIGH confidence (current sources)

Current (May 2026) context-window facts:

| Model | Context window | Notes |
|-------|---------------:|-------|
| Gemini 2.5 Pro | **1,048,576 tokens** (≈1M) | Some enterprise tiers reach 2M. Whole ~280K corpus fits in ONE context with ~720K to spare. `[CITED: ai.google.dev/gemini-api/docs/long-context]` |
| GPT-5.5 (API) | **1,000,000 tokens** | Released 2026-04-23. Whole corpus fits. Codex variant 400K. `[CITED: openai.com/index/introducing-gpt-5-5]` |
| GPT-4.1 (API) | **1,047,576 tokens** | Whole corpus fits. `[CITED: openai.com — GPT-4.1]` |
| GPT-5.4 (standard) | **272,000 tokens** | Corpus (~280K) JUST exceeds standard window; Codex config reaches 1M. >272K counts at 2× rate. `[CITED: developers.openai.com/api/docs/models/gpt-5.4]` |
| **ChatGPT web UI (the "paste into ChatGPT" path)** | effectively **far below** the model max — the chat product truncates/limits pasted content well under the API ceiling (practical single-paste limits are tens of thousands of tokens, not 1M) | This is THE reason chunking guidance is required even though the API windows are huge. `[ASSUMED — UI limits are not officially published as a token number; treat as the binding constraint for the paste-into-ChatGPT workflow]` |

### Token math conclusion

- The ~280K-token corpus **fits whole** in Gemini 2.5 Pro, GPT-5.5 API, GPT-4.1 API (one feed, no chunking).
- It **just exceeds** GPT-5.4's standard 272K window (chunk, or use Codex/1M config).
- The **ChatGPT web UI requires chunking** regardless of the underlying model's API ceiling — a human pasting 925K chars into the chat box will hit the product's per-message/attachment limits. This is the model-agnostic gap the kit must bridge.

### Concrete feeding recipe (the kit ships this)

- **Gemini 2.5 Pro (recommended primary):** attach the whole 18-file + Quests set as files (or paste) in one session — all ~280K tokens fit with ~720K headroom for the R1→R4 reasoning. No chunking needed. Run R1→R4 as 4 turns in one session so the model retains its R1 catalog.
- **GPT-5.5 / GPT-4.1 (API or Pro with file upload):** same — whole corpus fits; attach as files. Prefer file upload over inline paste.
- **ChatGPT web UI (chunked path):** feed in the 3 groups (RNG-CORE → CONSUME-B → FACADE+PERIPHERAL-C), re-attaching `DegenerusGameStorage.sol` with each group so every freeze claim resolves against the slot layout + write-gates. Do R1 (catalog) only after all 3 groups are loaded; if the session can't hold all 3, run R1 per-group and have the model merge catalogs in a reconciliation turn before R2.
- **General:** instruct the model to keep its R1 catalog as a persisted artifact (paste it back at the top of each later round) so context eviction doesn't lose it.

---

## Deliverable Packaging Precedent in This Repo (Research Question 7) — HIGH confidence

### Existing precedents (read in-repo)

1. **`audit/EXTERNAL-AUDIT-PROMPT.md` (293 lines)** — a **single-master paste-and-go prompt** for an independent auditor. Structure: THE PROMPT block → Non-Negotiable Rules (blind review, verify-from-source, don't inflate severity, state "no issue" explicitly) → Protocol Overview → Core Mechanics → Threat Model → Code Scope (start-here files + module list) → 12 Required Audit Coverage areas → Method Requirements → Severity Calibration → strict Output Format → Finding Quality Bar → Important Context → Do-Not list. **This is the closest precedent.** Reuse its *tone* (blind review, verify-from-source, no-anchor-on-prior-audits) — but note it is a *general* audit prompt and contains an "Important Context" section that, for the RNGAUDIT kit, would border on answer-key (e.g. it pre-states redemption-roll formulas). The RNG kit is narrower and must be stricter about not pre-stating conclusions.
2. **`audit/C4A-CONTEST-README.md` (~103+ lines)** — a **scope/context doc**: About → "I Care About Three Things" (RNG integrity first) → Out of Scope table → Known Issues pointer → Architecture → Key Contracts tables (14 core + 10 modules + libraries). Good model for the kit's *contract inventory* section (4d).
3. **`audit/STORAGE-WRITE-MAP.md`, `audit/ETH-FLOW-MAP.md`, `audit/ACCESS-CONTROL-MATRIX.md`** — neutral cross-reference maps. The kit's read-graph map (4a) should mirror these in style (tables of writers/readers, no verdicts).
4. **`audit/FINDINGS-v*.md`** — the 9-section findings reports (chmod 444 at closure). **The kit must NOT live in or reference these** (RNGAUDIT-03/SC3).
5. **`.planning/*.md` report style** — the milestone planning docs are heavy on tables + grep-attested anchors; the kit's context pack should match (every anchor a `file:line`).

### Candidate layouts (planner picks a default for the user)

| Layout | Files | Pros | Cons |
|--------|-------|------|------|
| **A. Single master doc** | `audit/rng-audit-kit/RNG-AUDIT-KIT.md` (protocol + context pack + chunk manifest + feeding recipe all in one) | Matches `EXTERNAL-AUDIT-PROMPT.md` precedent; one paste; nothing to lose track of | Long; mixes the paste-into-LLM protocol with the human-facing chunk manifest; harder to keep the "what the model sees" clean from "what the human does" |
| **B. Two-file split (RECOMMENDED)** | `audit/rng-audit-kit/RNG-AUDIT-KIT.md` (the protocol R1→R4 + cold-start context pack + freeze-invariant target — *this is what gets pasted into the model*) + `CHUNK-MANIFEST.md` (the contract-corpus chunking map + per-model feeding recipe — *this is the human's operating manual*) | Clean separation: the kit-the-model-sees has no human-ops noise; the manifest can list files+sizes+groups without polluting the prompt; matches the SC4 "chunking guidance" as a distinct artifact | Two files to keep in sync (mitigated by the validation checklist) |
| **C. Three-file split** | B + a separate `CONTEXT-PACK.md` distinct from the `PROTOCOL.md` | Maximally modular; protocol reusable across subjects | Over-engineered for a one-shot package; more sync surface; SC3 wants the context pack *with* the protocol (self-contained) |

**Default recommendation: Layout B.** It cleanly separates the paste-into-model artifact (protocol + self-contained context pack + invariant target) from the human-ops chunk manifest + feeding recipe, satisfies SC3's "self-contained" (the protocol file carries its own context pack), and satisfies SC4's "chunking guidance" as a first-class artifact. Place both under a NEW `audit/rng-audit-kit/` directory so they are physically separate from `FINDINGS-*.md`.

---

## Validation Architecture (Research Question 8) — HIGH confidence

> `workflow.nyquist_validation` is **false** in `.planning/config.json`, so there is no test-framework validation. BUT this docs deliverable has a concrete, fully-automatable correctness gate that does NOT require running the kit through an external model. The planner should attach these as task acceptance criteria.

### The deliverable is grep-checkable. Acceptance-criteria patterns:

| Check | Concrete command / assertion | Catches |
|-------|------------------------------|---------|
| **Every cited anchor resolves at HEAD** | For each `file:line` the kit cites, `sed -n 'Np' <file>` returns the expected symbol (e.g. `grep -n "whalePassClaims\[player\] += 1" contracts/modules/DegenerusGameLootboxModule.sol` returns `1253`). Build a script that extracts all `contracts/...:NNN` tokens from the kit and asserts each is in-range + the symbol matches. | Stale anchors copied from the pre-v50 sketch (the `:716`→`:720`, loop→`+=1`, etc. drift). |
| **Freeze-invariant wording matches the v45 north-star verbatim** | The kit's RNGAUDIT-01 statement must contain the exact string: *"while `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word + its deterministic derivations may be unknown"* — `grep -F` the canonical sentence against the kit. **WORDING MISMATCH to resolve at planning:** REQUIREMENTS RNGAUDIT-01 uses "VRF word + its deterministic derivations"; the 334 sketch §1 (line 15) uses "VRF word and its deterministic derivations" — otherwise identical. The planner must pick ONE canonical string for the kit (recommend the REQUIREMENTS `+` form, since RNGAUDIT-01 is the acceptance bar) and make the lint match that exact form — do not let the lint be brittle against the `and`/`+` variant. | Paraphrase drift weakening the target. |
| **Self-containment lint (no FINDINGS dependency)** | `grep -riE "FINDINGS-v[0-9]|audit/FINDINGS|RNGLOCK-CATALOG" audit/rng-audit-kit/` returns ZERO matches. | SC3 violation — the kit depending on internal reports. |
| **No-answer-key lint** | `grep -riE "is frozen because|we (found|verified|confirmed)|no (writer )?escape|safe by construction|the invariant holds|reverts-if-written" audit/rng-audit-kit/RNG-AUDIT-KIT.md` returns ZERO matches (allow the *exempt-entry* structural framing + the *methodology* sentence which uses "frozen if EVERY writer" as a conditional, not a verdict — write the lint to exclude those known-good phrasings, or hand-review the handful of hits). | A leaked freeze verdict / reassurance. |
| **All 4 exempt entries present + correctly anchored** | `grep` for `advanceGame`, `rawFulfillRandomWords`, `retryLootboxRng`, `rngGate` each with their re-attested `file:line`. | Missing/mis-anchored exempt set → the model flags resolution writes as escapes. |
| **R1→R4 rounds all present** | `grep -cE "^#+ *R[1-4]"` (or the round headings) == 4. | A dropped round → not multi-round (SC2). |
| **Cold-start context-pack sections all present** | The 4a/4b/4c/4d/4e skeleton headings present (module/RNG-window map, rngLock mechanics, VRF entry+consume, contract inventory, tracing method). | Incomplete context pack (SC3). |
| **Chunk manifest sums correct** | The manifest's per-file line/char counts match `wc -l`/`wc -c` at HEAD; group token sums add up. | Stale sizes if the tree changes. |
| **Model-agnostic + package-only framing present** | `grep` for the Gemini + ChatGPT feeding recipes and an explicit "PACKAGE-ONLY / running is a future cycle" statement. | SC4 omissions. |

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None (docs deliverable; `nyquist_validation: false`). Validation = grep/sed assertions against HEAD + the lints above. |
| Quick check | A `verify-kit.sh`-style script (planner may author as a task artifact, NOT a contract) that runs the anchor-resolution + the 3 lints. |
| Phase gate | All anchors resolve, freeze-invariant verbatim match, self-containment lint clean, no-answer-key lint clean (hand-reviewed). |

**Recommendation:** plan a dedicated "kit self-validation" task that runs these greps and records the output in a `337-KIT-VALIDATION.md` ledger (mirroring how 335 recorded `335-LOCAL-VERIFICATION.md`). This makes the docs deliverable's correctness CHECKABLE and auditable without ever touching an external model.

---

## Architecture Patterns (kit authoring)

### Pattern 1: Facts-not-verdicts cataloging
**What:** every context-pack entry is a *locator* (slot, writer file:line, reader file:line). **When:** all of §4a/4d. **Anti-pattern:** writing "slot X is frozen" (answer key).

### Pattern 2: Storage-travels-with-every-chunk
**What:** `DegenerusGameStorage.sol` is attached to every chunked group because every freeze claim resolves against the slot layout + the 3 write-gates. **When:** the chunk manifest. **Why:** the delegatecall architecture means writers/readers of one slot live in different files; the slot layout is the shared anchor.

### Pattern 3: Exempt-entry framing as the one allowed "given"
**What:** the kit tells the model the 4 exempt entries are the legitimate resolution writers (so it doesn't false-flag advanceGame), then asks it to confirm nothing ELSE writes those slots. **When:** §2 of the kit. This is the *only* near-conclusion the kit ships — it is structural orientation, not a freeze verdict.

### Anti-Patterns to avoid
- **Shipping `RNGLOCK-CATALOG.md` or any FINDINGS** — answer-key + self-containment violation + 700KB bloat.
- **Pre-stating the WHALE-04 / MINTDIV freeze proofs** — those are exactly the conclusions the external model must reach.
- **Copying anchors from the 334 sketch** — they are vs pre-v50 `b0511ca2`; several MOVED. Always re-attest at HEAD.
- **Inlining 925KB of Solidity into the markdown** — reference by path + chunk manifest; the human attaches files.

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Audit-prompt scaffolding | A prompt from scratch | The tone/structure of `audit/EXTERNAL-AUDIT-PROMPT.md` (blind review, verify-from-source, no-anchor) | A vetted in-repo precedent exists; the RNG kit is a narrower, stricter variant. |
| Contract inventory table | A fresh inventory | The `audit/C4A-CONTEST-README.md` Key Contracts tables + this §5 | Already enumerated; just re-scope to the RNG read-graph. |
| Read-graph map style | A novel format | The `audit/STORAGE-WRITE-MAP.md` writer/reader table style | Consistent house style; no verdicts. |
| Anchor verification | Manual eyeballing | grep/sed assertions (§8) | The whole correctness gate is automatable. |

**Key insight:** the structure is already locked (334 sketch) and the packaging precedent already exists (`EXTERNAL-AUDIT-PROMPT.md`). 337's value is (a) accurate re-attestation at HEAD and (b) disciplined answer-key withholding — not inventing a format.

---

## Common Pitfalls

### Pitfall 1: Citing pre-v50 anchors
**What goes wrong:** the kit cites `MintModule:716 (writesUsed>>1)` or the `LootboxModule:1250-1260` loop — both GONE in v50. **Why:** the 334 sketch + GREP-ATTESTATION are vs `b0511ca2`. **Avoid:** re-attest at HEAD (§3); attach the §8 anchor-resolution lint. **Warning signs:** any `file:line` not independently grep-confirmed at HEAD.

### Pitfall 2: Leaking a freeze verdict
**What goes wrong:** a sentence like "the deferred claim queues future-level tickets so it's freeze-safe" sneaks in. **Why:** it's the natural thing the author *knows*. **Avoid:** the §4 rule + the no-answer-key lint. **Warning signs:** "because", "safe", "we verified", "no escape", "holds".

### Pitfall 3: Treating RNGLOCK-CATALOG as live vectors
**What goes wrong:** the kit frames the maximalist catalog's "111 violations" as live exploits. **Why:** the catalog *looks* like a vuln list. **Avoid:** per `project_rnglock_audit_disposition` + REQUIREMENTS Out-of-Scope, it is a maximalist catalog, NOT live exploits; do not ship or reference it. **Warning signs:** any reference to the 135-anchor register in the kit.

### Pitfall 4: Assuming the whole corpus needs chunking (or that it never does)
**What goes wrong:** over-chunking for Gemini (which fits 280K in 1M easily) OR under-providing for the ChatGPT web UI (which truncates). **Why:** API ceilings ≠ web-UI paste limits. **Avoid:** the per-model recipe (§6) — Gemini/GPT-5.5/4.1 one feed; ChatGPT-web 3-group chunked. **Warning signs:** a single feeding instruction that ignores the web-UI constraint.

### Pitfall 5: Putting the kit under `audit/` next to FINDINGS
**What goes wrong:** SC3 self-containment is violated if the kit sits with / references FINDINGS. **Avoid:** new `audit/rng-audit-kit/` subdir; self-containment lint (§8). **Warning signs:** any `FINDINGS-v` substring in the kit dir.

---

## State of the Art

| Old (pre-v50 / 334 sketch) | Current (post-v50 HEAD) | When changed | Impact on kit |
|----------------------------|-------------------------|--------------|---------------|
| Whale box-open = inline 100-iter `_queueTickets` loop (`LootboxModule:1250-1260`) | O(1) `whalePassClaims[player] += 1` (`:1253`) + deferred `claimWhalePass` | v50 `e756a6f3` | Catalog the O(1) writer + the claim materializer, not the loop |
| MintModule within-player advance `writesUsed>>1` (`:716`) | `processed += take` (`:720`), aligned with `:502` | v50 | Cite `:720`; the "suspect advance" no longer exists |
| `_applyWhalePassStats` 3 callers (incl. `LootboxModule:1247`) | 2 callers (`WhaleModule:1032` + `DecimatorModule:588`) | v50 | The box-open caller is gone |
| `autoOpen` gas-weighted budget + `OPEN_NORMAL_GAS_UNIT=90_000` | flat `opened < maxCount`; constant deleted; `autoOpen` at `:1695` | v50 | Inventory the flat path; the carve-out is retired |
| AfKing `paidThroughDay` + `burnForKeeper` BURNIE window | `validThroughLevel` + `lazyPassHorizon` view (`Game:1540`); BURNIE window deleted | v50 | AfKing in inventory but non-VRF; new view is non-VRF |
| Context windows (training-era) | Gemini 2.5 Pro 1M, GPT-5.5 1M, GPT-4.1 1.05M, GPT-5.4 272K | 2026 | Whole 280K corpus fits Gemini/GPT-5.5/4.1 in one feed |

**Deprecated/outdated for the kit:** the 334 sketch's anchor line numbers for the 3 touched files; `EXTERNAL-AUDIT-PROMPT.md`'s "24 deployable contracts / 10 modules" framing predates the 11-module count this phase uses (the sketch §4d counts 11 game modules under `contracts/modules/`) — reconcile the module count to the actual `ls contracts/modules/` (11 files: Advance, Boon, Decimator, Degenerette, GameOver, Jackpot, Lootbox, Mint, MintStreakUtils, PayoutUtils, Whale).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | ChatGPT web UI single-paste limits are far below the model API ceiling (the binding reason for chunking guidance) | §6 | LOW — even if the web UI accepts more than assumed, chunking guidance is still correct for GPT-5.4's 272K standard window and is never harmful; the recipe degrades gracefully. |
| A2 | Solidity ≈ 3.6 chars/token (token estimates) | §5, §6 | LOW — estimates are rounded up; actual tokenizer counts vary ±10%; the conclusion (fits in 1M, exceeds 272K) holds with wide margin. |
| A3 | The kit should INCLUDE `DegenerusQuests.sol` (the `rollLevelQuest` consumer) in the corpus | §5 | LOW — it is a named consume site; omitting it would leave the read-graph incomplete. Including it is strictly safer; planner/user can drop it if they scope the kit to game-storage modules only. |
| A4 | Layout B (two-file split) is the right default | §7 | LOW — it's a recommendation for the user to review at discuss-phase; layouts A and C are documented alternatives. |
| A5 | No `337-CONTEXT.md` exists yet (standalone research) | header | NONE — verified by file listing; if discuss-phase runs first, its CONTEXT.md decisions override these discretion picks. |

**Note on the freeze verdicts in §3/§4:** the "internal freeze status" column and the WHALE-04/MINTDIV safety reasoning are stated here as INTERNAL grounding for the planner's confidence. They are NOT `[ASSUMED]` claims about the kit's content — they are the answer key the kit must WITHHOLD. They are derived from the v50 freeze proofs (WHALE-04 attested Complete in REQUIREMENTS; MINTDIV-02 landed at `:720`) and the structural fact that `_queueTicketRange` carries the `:661` gate. Do not ship them.

---

## Open Questions

1. **Should the kit ship the contracts inline or by reference?**
   - Known: 925KB is far too large to inline in markdown; Gemini/GPT API accept file attachments.
   - Unclear: whether the future operator will paste files or attach them (affects whether the chunk manifest lists paths only vs includes paste-ready fenced blocks).
   - Recommendation: reference-by-path + chunk manifest (paths + sizes + groups); do NOT inline. Settle at discuss-phase.

2. **Exact module count framing (11 vs "10 delegatecall modules").**
   - Known: `contracts/modules/` has 11 files; the legacy `EXTERNAL-AUDIT-PROMPT.md` / `C4A-README` say "10 delegatecall modules" (they don't count `PayoutUtils`/`MintStreakUtils` as standalone, or predate a split).
   - Recommendation: the kit uses the actual `ls contracts/modules/` set (11) per the 334 sketch §4d; note the legacy "10" framing is stale.

3. **Does the kit name a recommended primary model?**
   - Known: Gemini 2.5 Pro fits the whole corpus in one feed with the most headroom.
   - Recommendation: name Gemini as the recommended primary for the one-feed path, ChatGPT-web as the chunked path — but the kit stays model-agnostic (both fully documented). Settle the emphasis at discuss-phase.

---

## Sources

### Primary (HIGH confidence)
- Current repo working tree at HEAD `f65fb0f1` (== `e756a6f3` under `contracts/`) — every anchor in §3 grep/sed-verified.
- `git diff b0511ca2 HEAD -- contracts/` — the v50 IMPL delta (5 files) read in full (§2).
- `.planning/REQUIREMENTS.md` (RNGAUDIT-01..04 verbatim), `.planning/STATE.md` (336 complete, subject frozen).
- `.planning/phases/334-.../334-RNGAUDIT-STRUCTURE-SKETCH.md` (the locked structure), `334-GREP-ATTESTATION.md` (the pre-v50 anchor table to re-attest against).
- `audit/EXTERNAL-AUDIT-PROMPT.md`, `audit/C4A-CONTEST-README.md` (packaging precedents, read in full).
- `.planning/phases/335-.../335-06-SUMMARY.md`, `test/REGRESSION-BASELINE-v50.md` (the v50 IMPL deltas + frozen-subject SHA).
- `~/.claude/skills/zero-day-hunter/SKILL.md`, `~/.claude/skills/contract-auditor/SKILL.md` (R3 adversarial methodology to mirror).

### Secondary (MEDIUM-HIGH confidence — current context-window numbers)
- [Long context | Gemini API | Google AI for Developers](https://ai.google.dev/gemini-api/docs/long-context) — Gemini 2.5 Pro 1M tokens.
- [Introducing GPT-5.5 | OpenAI](https://openai.com/index/introducing-gpt-5-5/) — GPT-5.5 API 1M tokens (2026-04-23).
- [GPT-5.4 Model | OpenAI API](https://developers.openai.com/api/docs/models/gpt-5.4) — GPT-5.4 standard 272K, 1M via Codex.
- [Google Gemini Context Window: Token Limits (Late 2025/2026) | DataStudios](https://www.datastudios.org/post/google-gemini-context-window-token-limits-model-comparison-and-workflow-strategies-for-late-2025) — tier variation up to 2M.
- [ChatGPT Token Limit (2026) | ScriptByAI](https://www.scriptbyai.com/token-limit-openai-chatgpt/) — free/Plus/Pro/API limit differences.

### Tertiary (LOW confidence — flagged)
- ChatGPT web-UI single-paste practical limit (A1) — not officially published as a token number; treated as the binding chunking constraint.

---

## Metadata

**Confidence breakdown:**
- Anchor re-attestation (§3): HIGH — every line grep/sed-verified at HEAD; 5 touched files diffed in full.
- Post-v50 read-graph deltas (§2): HIGH — derived directly from the diff + grep of all writers/readers.
- Answer-key boundary rule (§4): HIGH — derived from RNGAUDIT-02 verbatim + the 334 sketch §5 constraint.
- Contract sizes + chunking (§5): HIGH — `wc` measured; token estimate MEDIUM (±10% on chars/token).
- Context-window numbers (§6): MEDIUM-HIGH — CITED to current sources; web-UI limit ASSUMED.
- Packaging precedent (§7): HIGH — both precedent docs read in full.
- Validation (§8): HIGH — all checks are concrete grep/sed assertions.

**Research date:** 2026-05-28
**Valid until:** ~2026-06-28 for anchors (re-attest if any `contracts/` commit lands after `e756a6f3`); ~7 days for context-window numbers (fast-moving model landscape).
