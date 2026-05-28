# Phase 334: SPEC — Design-Lock + MINTDIV Reachability Proof + RNGAUDIT Structure + Call-Graph Attestation - Context

**Gathered:** 2026-05-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Settle, **in writing**, the shared signatures for the three v50.0 contract items so the IMPL phase (335) re-authors one reconciled `contracts/*.sol` diff with zero "by construction" assumptions; **PROVE or REFUTE** the MINTDIV-01 divergence reachability with traced evidence; **PROVE on paper** the WHALE-04 RNG-freeze safety of the deferred whale-pass claim; fix the RNGAUDIT external-protocol structure (the R1→R4 sequence + cold-start context-pack skeleton that Phase 337 authors against); and **grep-attest every cited `file:line`** against the v49.0-closure HEAD `b0511ca2`, correcting any drift.

**Paper-only — zero `contracts/*.sol` edits in this phase.** Requirements: BATCH-01, WHALE-04, MINTDIV-01. The contract changes these decisions govern land at IMPL 335 (WHALE/AFSUB/MINTDIV-if-real) under the single-batched-diff HARD STOP.

**Audit baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`.

</domain>

<decisions>
## Implementation Decisions

### Whale-pass claim — shape, anchoring, signature (governs WHALE-01/02/04 at IMPL)
- **D-01 — Access model: permissionless with beneficiary arg.** `claimWhalePass(address beneficiary)` — anyone may call it, the caller pays the gas. (User chose this over caller-is-beneficiary.) It is coherent **only because the claim is decoupled from box-open**: open just records O(1); nothing is *forced* to claim. **HARD CONSTRAINT: the claim must NEVER be auto-triggered by box-open or autoOpen** — if it were, the keeper would again involuntarily eat the materialization gas, re-creating the exact misallocation this refactor exists to kill (the seed rationale). Permissionless adds optional flexibility (self-claim is the norm; a third party *may* gift-claim; a future keeper could be wired to claim-for-bounty).
- **D-02 — Pending storage = a COUNT.** `pendingWhalePasses[beneficiary]` (a uint counter), NOT a stored `startLevel` and NOT a list. Box-open increments it (O(1)); `claimWhalePass` materializes `count × (100-level grant)` and zeroes it. Multi-roll (rolling `BOON_WHALE_PASS` again before claiming) is just another increment.
- **D-03 — CLAIM-TIME anchoring (the key semantic).** The 100-level grant is anchored at **claim-time `currentLevel + 1`**, not roll-time. User rationale (verbatim): *"whale passes (after the very beginning) always give 100 levels of tickets which is worth the same whenever; whenever they claim the whale pass is fine."* This (a) eliminates `startLevel` storage, (b) makes multi-roll a trivial count, and (c) makes the deferred claim **freeze-safe by construction** — claim always queues `currentLevel+1 .. +100`, all future levels, so it can never write a slot in the current RNG window. The early-game ≤level-10 bonus band (40 tickets/lvl, `WHALE_PASS_BONUS_END_LEVEL=10`) is the one regime where anchor timing changes value — the user's "worth the same" holds *after the very beginning*.
- **D-04 — Stats apply AT CLAIM.** `_applyWhalePassStats` (freeze-extension to `anchor+99` + `levelCount` boost) runs inside `claimWhalePass`, anchored to the same claim-time `currentLevel+1` as the tickets. Box-open therefore writes **no** `mintPacked_` state — it is a pure O(1) count increment. **Only the LootboxModule box-open caller changes**; the two other `_applyWhalePassStats` callers — `DegenerusGameWhaleModule.sol:1032` (bundle purchase) and `DegenerusGameDecimatorModule.sol:588` (Decimator win) — keep immediate-apply, **untouched**.
- **D-05 — TST-01 equivalence is reinterpreted.** Because of claim-time anchoring, "same materialized tickets/traits/stats as the old inline mint" becomes **"correct claim-time 100-level grant + correct claim-time stats"** — NOT byte-identical to the old roll-time inline mint. The 336 test must assert the new intended behavior, not diff against the old absolute levels.
- **D-06 — Economic basis is an assertion to re-attest, not a given.** The "worth the same whenever" claim + the new claim-timing degree of freedom (a player picks when to anchor) are recorded as the **user's design assertion** and MUST be re-attested by the SWEEP economic-analyst at 338 (could a chosen claim level ever be advantageous/abusable?). Not silently assumed.
- **D-07 — WHALE-03 (autoOpen carve-out retirement) stands unchanged.** Uniform O(1) opens → retire the 331 whale-pass-weighted `autoOpen` budget; `OPEN_BATCH` returns to flat per-box sizing (re-confirmed under the worst-case uniform open). This is IMPL-335 work; SPEC just confirms it follows from D-02/D-04.

### AfKing pass-gated subs (governs AFSUB-01..05 at IMPL)
- **D-08 — Pass-gating scope = the autoBuy sub window ONLY (architecture-resolved).** The subscription window only gates **autoBuy** (the daily box-buying leg, cursor-driven, `_autoBuyCursor`). `autoOpen` is a permissionless router leg (boxes are openable by anyone — there is no "window" to gate) and stays **unchanged**. So the seed's "autoBuy / autoOpen / both?" resolves to autoBuy by construction.
- **D-09 — `burnForKeeper` removed ENTIRELY from BOTH contracts.** Delete the call + the `paidThroughDay`/`WINDOW_DAYS` window accounting in `AfKing.sol`, AND the now-dead `BurnieCoin.sol:472` `burnForKeeper` implementation (AfKing is its only, `onlyAfKing`-gated caller). **The batched IMPL diff (335) therefore touches `BurnieCoin.sol`** — folded into the one USER-approved diff. No dead code, no future-proofing.
- **D-10 — Lazy-only refresh; NO `refreshPass()` entrypoint.** The crossing re-check (`currentLevel > validThroughLevel` → re-read pass → refresh-or-evict) already catches a post-subscribe upgrade: an upgrader is re-read and refreshed **at** the crossing and is never wrongly evicted. A proactive `refreshPass()` would be pure convenience with no functional necessity — skip it (smallest surface).
- **D-11 — A new level-horizon pass view is required (SPEC/IMPL design note).** Today's free-extend uses the **boolean** `hasAnyLazyPass` (`AfKing.sol:432`, also `:631`). The `validThroughLevel` model needs a per-pass-type **level horizon** instead: **deity = `type.max`/permanent sentinel** (never crosses, cheapest case), **lazy/whale = the covered-through level**. SPEC confirms each pass type exposes a determinable horizon readable both at subscribe and at the crossing re-check.
- **D-12 — Preserved invariants (acceptance criteria the pass-gated model must satisfy).** `validThroughLevel` encoded at subscribe; per-iter check is the cheap stored-field compare `currentLevel <= validThroughLevel` (NO per-iteration external pass read on the non-crossing path — no GASOPT-05 regression); the crossing is the ONLY external pass read on the hot path; refresh-or-evict is NOT an unconditional kick. OPEN-E `fundingSource` + the 4 structural protections STAY (pass-gating does not moot OPEN-E). The SUB-07 in-place cancel-tombstone + the v49 swap-pop membership invariant (membership ⟺ packed != 0) hold, so eviction does not reproduce the H-CANCEL-SWAP-MISS missed-day class.
- **D-13 — No migration.** Pre-launch redeploy-fresh (storage-layout break fine, no live state) → the seed's "in-flight BURNIE-paid window at cutover / refund / grandfather" question is **moot**.

### MINTDIV — confirm-then-fix posture (governs MINTDIV-01 proof + MINTDIV-02 scope)
- **D-14 — MINTDIV-01 is a PROOF, not an assertion.** SPEC must establish with a traced argument whether `processTicketBatch`'s within-player advance `processed += writesUsed >> 1` (`DegenerusGameMintModule.sol:716`) can diverge from `processFutureTicketBatch`'s `processed += take` (`:502`) — i.e., (a) can a single player's `owed` split across a `WRITES_BUDGET_SAFE` slice (`owed > take`)? AND (b) does the split yield divergent per-ticket LCG `startIndex` → wrong/gapped traits? Reachability gate: dead branch unless `owed > take`. Verdict recorded with evidence.
- **D-15 — If reachable → minimal one-liner fix.** Change `processTicketBatch:716` `processed += writesUsed >> 1` → `processed += take` (match the correct `processFutureTicketBatch:502` contiguous advance). Smallest blast radius on the trait-critical path; easiest byte-identical-traits-across-split proof (TST-03). The two near-duplicate loops STAY separate (the pre-existing maintenance risk is unchanged — **full dedup was explicitly rejected** as a larger, security-floor-gated change to a critical path with no gas win).
- **D-16 — If refuted → no change, documented NEGATIVE.** Ship the proof only; the frozen critical path stays untouched. **No defensive `+= take` one-liner** (rejected — no future-proofing of an unreachable branch).

### RNGAUDIT structure (sketch only at SPEC; authored at 337)
- **D-17 — Structure is locked by the requirements, not a gray area.** SPEC sketches the authoring target: the R1→R4 multi-round sequence (R1 catalog the VRF read-graph → R2 independently re-derive each slot's freeze status → R3 adversarially challenge → R4 reconcile/report) and the self-contained cold-start context-pack skeleton (module/RNG-window map · `rngLock` mechanics · VRF word entry/consume points · contract inventory · cross-module variable-tracing methodology), with the **"drive the external model's OWN discovery — no answer key, no embedded internal findings"** constraint and the **package-only / model-agnostic** framing recorded. Full authoring against the FROZEN post-v50 tree is Phase 337.

### Cross-cutting (BATCH-01)
- **D-18 — Producer-before-consumer edit-order map.** SPEC confirms the IMPL re-author order so no intermediate file ships a broken state, and reconciles the shared `_queueTickets` surface (touched by WHALE, audited near by MINTDIV) across the two RNG-adjacent edits.
- **D-19 — Grep-attest EVERY anchor vs `b0511ca2`.** No "by construction" survives unchecked (the DegenerusGame mint/jackpot inline-duplication precedent). All anchors below were spot-confirmed during discussion (lines drifted slightly from the seeds' `~` approximations); SPEC formalizes the full attestation.

### Claude's Discretion
- Exact home of the `claimWhalePass` entrypoint (a `DegenerusGame` external fn delegating to the LootboxModule vs module-direct), the precise pending-counter storage slot, the exact name/signature of the new level-horizon pass view, and the `validThroughLevel` field placement within the `Sub` layout — all left to the planner/researcher, constrained by the decisions above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (read first)
- `.planning/ROADMAP.md` — Phase 334 goal + Success Criteria 1–5; the v50.0 cross-cutting rule (re-attest every `file:line` vs `b0511ca2`; security/RNG-freeze floor; one batched diff + HARD STOP).
- `.planning/REQUIREMENTS.md` — BATCH-01, WHALE-01..04, AFSUB-01..05, MINTDIV-01/02, RNGAUDIT-01..04, TST-01..04, SWEEP-01..03, BATCH-02/03.

### Whale-pass (WHALE)
- `contracts/modules/DegenerusGameLootboxModule.sol` — `_activateWhalePass:1240` (passLevel = level+1, the future-level proof anchor), the 100-iter `_queueTickets` loop `:1250-1260`, `BOON_WHALE_PASS:378`, bonus constants `:205-209` (`WHALE_PASS_TICKETS_PER_LEVEL=2`, `WHALE_PASS_BONUS_TICKETS_PER_LEVEL=40`, `WHALE_PASS_BONUS_END_LEVEL=10`), jackpot event `:1638`.
- `contracts/storage/DegenerusGameStorage.sol` — `_applyWhalePassStats:1111` (writes `mintPacked_` frozenUntilLevel/levelCount, delta-based no-double-dip), `_livenessTriggered:571` (the rngLock liveness gate `_queueTickets` hits).
- `contracts/modules/DegenerusGameWhaleModule.sol:1032` + `contracts/modules/DegenerusGameDecimatorModule.sol:588` — the two `_applyWhalePassStats` callers that stay immediate-apply (must NOT change).

### AfKing (AFSUB)
- `contracts/AfKing.sol` — `burnForKeeper` iface `:57`, `Sub` layout `:79-92` (`paidThroughDay` offset 5, `fundingSource` offset 11), `WINDOW_DAYS:220`, `subscribe:374`, OPENE-04 gate `:397-399`, free-extend `hasAnyLazyPass:432`, day-31 `hasAnyLazyPass:631`, `setDailyQuantity` reclaim/tombstone `:458`, autoBuy cursor `_autoBuyCursor:214`.
- `contracts/BurnieCoin.sol:472` — the `burnForKeeper` implementation to delete (D-09).

### MintModule (MINTDIV)
- `contracts/modules/DegenerusGameMintModule.sol` — `processFutureTicketBatch:393` with the correct `processed += take:502`; `processTicketBatch:671` with the suspect `processed += writesUsed >> 1:716`; the `_raritySymbolBatch` LCG consumer (the `startIndex`-driven trait generator).

### Memory / prior-decision sources (background — not files in repo)
- Seeds: `v49-whale-pass-claim-refactor-seed`, `v50-afking-pass-only-sub-simplify-seed`, `mintmodule-processed-advance-divergence-seed`.
- Invariants/feedback: `v45-vrf-freeze-invariant`, `open-e-operator-approval-trust-boundary`, `afking-cancel-tombstone-streak-finding`, `feedback_security_over_gas`, `feedback_frozen_contracts_no_future_proofing`, `feedback_verify_call_graph_against_source`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_applyWhalePassStats` (Storage:1111) is a shared internal already called from 3 sites — the claim path reuses it verbatim (just relocated to claim-time for the box-open caller); the other two callers prove it is safe to keep immediate elsewhere.
- The `processFutureTicketBatch` inlined loop (`:393`, `+= take` at `:502`) is the **reference-correct** advance the MINTDIV fix copies — no new logic to author.
- AfKing's existing `setDailyQuantity(0)` reclaim/tombstone path (`:458`) is the eviction mechanism the refresh-or-evict crossing reuses (no new tombstone infra).

### Established Patterns
- Queue-then-materialize (`project_lootbox_delayed_finalization_intentional`) + claimable-everywhere (`universal-claimable-pay`) — the whale-pass O(1)-record + player-paid-claim fits the existing idiom.
- The retired `paidThroughDay >= today` day-denominated compare is the exact shape the new `currentLevel <= validThroughLevel` level-denominated compare mirrors (same cheap per-iter cost; GASOPT-05 win preserved).
- `_livenessTriggered`/rngLock gate: a claim during `rngLock` reverts (same gate autoOpen respects) — the pending count persists, so the pass is never marooned; it claims after the window.

### Integration Points
- New `claimWhalePass(address)` entrypoint + the `pendingWhalePasses` counter slot + the box-open record (replacing the inline loop) — the only LootboxModule/Game whale-pass surface change.
- AfKing `Sub` gains `validThroughLevel`; the new level-horizon pass view on the Game/interface side; `BurnieCoin.sol` loses `burnForKeeper`.
- MintModule: the single `:716` advance line.

</code_context>

<specifics>
## Specific Ideas

- User's verbatim anchoring rule: *"whale passes (after the very beginning) always give 100 levels of tickets which is worth the same whenever, I don't think this matters. whenever they claim the whale pass is fine."* → claim-time anchoring (D-03).
- "Deity passes are good forever" → `validThroughLevel = type.max`/permanent sentinel (D-11).
- Permissionless claim chosen deliberately (D-01) despite the seed recommending caller-is-beneficiary — the decoupling-from-open constraint is what keeps it safe.

</specifics>

<deferred>
## Deferred Ideas

- **gameOver-forfeit rule for unclaimed whale passes** — pending claims unclaimed at `gameOver` almost certainly forfeit (no future levels to materialize); consistent with "claim whenever is fine" + rarity. NOT discussed as a decision — **SPEC should record the explicit rule** (forfeit vs auto-claim-at-gameOver) when authoring the claim path. Low-stakes edge case.
- **Full dedup of the two MintModule loops** — rejected for v50 (D-15); remains a standing maintenance idea (security-floor-gated, no gas win) for a future cycle.
- **Running the external RNG-audit protocol** through Gemini/ChatGPT + triaging output — already out of v50 scope (RNGAUDIT is package-only; future cycle).

### Reviewed Todos (not folded)
None — no pending todos matched Phase 334.

</deferred>

<research_reconciliation>
## Post-Research Reconciliation (334-RESEARCH.md, 2026-05-27)

Research (`334-RESEARCH.md`, HIGH confidence) materially reshaped two items and surfaced one new decision (now locked). These ADD to / refine the decisions above:

- **D-20 — WHALE is a CONVERGENCE refactor onto EXISTING deployed machinery (not greenfield).** `claimWhalePass(address player)` already exists and is deployed (`DegenerusGameWhaleModule.sol:1018`), already permissionless-with-beneficiary-arg (D-01), already claim-time-anchored to `level+1` (D-03), already backed by a `whalePassClaims[player]` count (D-02), already applies `_applyWhalePassStats` at claim (D-04) — fed today by the jackpot/payout path (`DegenerusGamePayoutUtils.sol:45` `_queueWhalePassClaimCore`, `DegenerusGameJackpotModule.sol:1410`). **WHALE-01's job is to route the box-open boon (`_activateWhalePass:1240` inline 100-loop) onto this SAME machinery** — an O(1) `whalePassClaims[beneficiary] += grant` mirroring `PayoutUtils:45`. **D-02's `pendingWhalePasses` is a RELABEL of the existing `whalePassClaims` — do NOT build a parallel map/claim** (the "Pitfall 1" anti-pattern). This makes the WHALE-04 freeze proof largely a re-attestation of existing gates.
- **D-21 — Q1 RESOLVED: box-open whale pass CONVERGES to the existing FLAT grant shape.** Routing box-open onto the existing claim, the box-open whale pass adopts the existing flat per-level half-pass shape — **the early-game ≤level-10 `40/lvl` bonus band is DROPPED** and the per-level rate aligns to the existing claim. This is a **deliberate economic reduction** of the box-open whale-pass reward (single counter, simplest IMPL — no grant-shape param, no second counter). The value delta is routed to the **338 SWEEP economic-analyst** to sign off (per D-06). USER decision 2026-05-27.
- **D-22 — MINTDIV-01 is PROVEN REACHABLE (verdict, not open).** `processed += writesUsed >> 1` (`:716`) diverges from the correct `+= take` (`:502`) by arithmetic fact (−17 warm against the real `WRITES_BUDGET_SAFE = 550`); the `take < owed` not-finished branch is LIVE on two confirmed callers — `AdvanceModule:561` (gameover terminal-drain) and `:1496` (advance drain); a single player can accumulate `owed > maxT (~292 warm)`. Concrete scenario the SPEC records: `owed = 300` at level L, warm budget 550 → `maxT = 292`, `take = 292 < 300` → `processed += 275` (should be 292) → `_raritySymbolBatch` resumes at `startIndex = 275` → overlapped/skipped LCG indices → **divergent per-ticket traits**. → **MINTDIV-02 SHIPS the D-15 one-liner** (`>>1` → `+= take`) at IMPL 335; the not-reachable NEGATIVE branch (D-16) does NOT apply.
- **D-23 — gameOver-forfeit (Q2, record-only).** Unclaimed `whalePassClaims` at `gameOver` are **forfeit** (no future levels to materialize) — SPEC records this as one sentence; consistent with the existing claim machinery and "claim whenever is fine."
- **Anchor corrections vs `b0511ca2`** (working tree is byte-identical to the frozen baseline — `git diff` empty): `_livenessTriggered` *definition* is `DegenerusGameStorage.sol:1213` (the `:571` in Canonical References is a call-site, not the def); the AfKing `Sub` struct is `:86-93`; `processFutureTicketBatch` is `:393`. The grep-attestation table in `334-RESEARCH.md` is complete and authoritative.

</research_reconciliation>

---

*Phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu*
*Context gathered: 2026-05-27 (research reconciliation appended same day)*
