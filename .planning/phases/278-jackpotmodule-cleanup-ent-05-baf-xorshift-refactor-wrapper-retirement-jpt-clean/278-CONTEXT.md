# Phase 278: JackpotModule Cleanup + ENT-05 BAF Xorshift Refactor + Wrapper Retirement (JPT-CLEAN) - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Consolidate remaining `DegenerusGameJackpotModule.sol` maintenance now that Phases 275–277 have landed, and ship the cross-surface mixing regression test. Four contained workstreams:

1. **ENT-05 BAF xorshift refactor** — `_jackpotTicketRoll` (`contracts/modules/DegenerusGameJackpotModule.sol:2204`) currently calls `EntropyLib.entropyStep(entropy)` (3-op xorshift) at `:2210`, then reads **low bits** of the output for path/level selection (`entropy % 100` 30/65/5 split, `(entropy/100) % 4` near offset, `(entropy/100) % 46` far offset) plus `entropy >> 200` for the Phase-276 Bernoulli sub-roll. Refactor swaps `entropyStep` → `EntropyLib.hash2(...)` so the path/level rolls consume a full-diffusion keccak word. This is the exact xorshift→keccak choice `MintModule._rollRemainder` already made for the same reason. Demotes EXC-04 (KI envelope) from `NARROWS` to a candidate `NEGATIVE` at Phase 280 re-verification.

2. **`JackpotTicketWin` whole-ticket unification** — all 3 emit sites converge on emitting the **whole** ticket count. The "cosmetic xTICKET_SCALE cleanup" is realized as this unification (NOT a no-op comment touch).

3. **`_queueLootboxTickets` wrapper retirement** — the wrapper at `contracts/storage/DegenerusGameStorage.sol:687` has **zero callers** (Phase 276 swapped its only caller at `JackpotModule.sol:2216` to a direct `_queueTickets`). Pure dead-code deletion. `_queueTicketsScaled` (`DegenerusGameStorage.sol:596`) STAYS — still used by mint-boost per D-40N-MINTBOOST-OUT-01.

4. **`EntropyLib.entropyStep` deletion** — after workstream 1, `entropyStep` has zero production callers; delete it. `EntropyLib` keeps only `hash2`.

Plus the **TST-CROSS-01** cross-surface mixing regression test in this phase's test wave.

Storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `MILESTONE_V39_AT_HEAD_6a7455d1` for `DegenerusGameJackpotModule.sol`. Bytecode delta expected NET-NEGATIVE. Wave shape: 1 USER-APPROVED batched contract commit + 1 USER-APPROVED batched test commit per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`.

**Out of scope:** mint-boost surfaces (`MintModule` `_queueTicketsScaled` / `_rollRemainder` / `rem` byte / MintModule's own xorshift) — all retained per D-40N-MINTBOOST-OUT-01. Whole-BURNIE floor — Phase 279. Terminal delta audit — Phase 280.

</domain>

<decisions>
## Implementation Decisions

### ENT-05 BAF Xorshift Refactor

- **D-278-ENT05-01:** Swap `EntropyLib.entropyStep(entropy)` → `EntropyLib.hash2(...)` inside `_jackpotTicketRoll`. The path/level rolls (and the bits[200..215] Bernoulli sub-roll) then consume a full-diffusion keccak word instead of xorshift output.
  - **Why:** `_jackpotTicketRoll` reads *low bits* (`% 100`, `% 4`, `% 46`) of the entropy word. `EntropyLib.hash2`'s own NatSpec states keccak should be preferred "whenever low-bit diffusion of structured (high-bit) input is required" — exactly this consumption pattern. xorshift's weak low-bit diffusion produces a measurable (chi-square-detectable, ~0.5pp-scale) skew in the 30/65/5 split and the offset distributions. Not exploitable (entropy derives from the unpredictable VRF word — no prediction/grind vector), but a distribution-quality issue. `MintModule._rollRemainder` (`DegenerusGameMintModule.sol:652`) already made this identical xorshift→keccak choice for the identical reason. Practical effect: a *documented* known-issue (EXC-04 NARROWS) becomes a *fixed* non-issue at near-zero cost.
  - **Output semantics CHANGE intentionally** — v39→v40 BAF roll outputs differ for a given seed. Tests assert a new invariant, not byte-equivalence (D-278-ENT05-TEST-01). Roadmap SC2 explicitly permits this.

- **D-278-ENT05-CHAIN-01:** The 2-roll pattern in `_awardJackpotTickets` (`:2138`–`:2181`) preserves per-roll uniqueness by **chaining on the returned word** — `_jackpotTicketRoll` does `entropy = hash2(entropy, ...)` and returns it, so roll 2's input equals roll 1's output and the two rolls' words differ. Mirrors the existing return-and-rethread pattern; no new parameter threaded through `_awardJackpotTickets`. Per-roll uniqueness (the JPT-BR-03 carry from Phase 276) MUST be preserved and tested. Exact `hash2` second-arg (self-mix vs fixed salt) is plan-phase discretion provided uniqueness holds.

- **D-278-ENT05-TEST-01:** Test the refactor by asserting the **new post-refactor statistical invariant**, not byte-equivalence: chi-square uniformity of the 30/65/5 path roll + the +1–4 / +5–50 offset distributions, per-roll seed-uniqueness across the 2-roll pattern, and that the bits[200..215] Bernoulli sub-roll independence (Phase 276 JPT-BR-03 / TST-JPT-BR-03 carry) still holds under the keccak word.

### `JackpotTicketWin` Whole-Ticket Unification (xTICKET_SCALE cleanup)

- **D-278-EVT-UNIFY-01:** All **3** `JackpotTicketWin` emit sites converge on emitting the **whole** ticket count:
  - `DegenerusGameJackpotModule.sol:709` (trait-matched) — emit `ticketCount` directly instead of `ticketCount * uint32(TICKET_SCALE)`.
  - `DegenerusGameJackpotModule.sol:1013` (trait-matched, near/far coin path) — emit `units` directly instead of `uint32(units * TICKET_SCALE)`.
  - `DegenerusGameJackpotModule.sol:2254` (BAF `_jackpotTicketRoll`) — emit `whole` instead of `uint32(quantityScaled)`.
  - The field name `ticketCount` stays (it is now *accurate* — a real whole-ticket count). The `bool roundedUp` field (added Phase 277) is the **sole** retained pre-Bernoulli signal: consumers get the Bernoulli outcome direction but no longer the exact pre-roll fraction. This info-loss on the BAF site is accepted.
  - **Why:** user intent (2026-05-14, verbatim): "can we try to unify things as best we can so it is clear that other than purchases (and whale passes) we always award one ticket when awarding entries." The ×100 "scaled" representation is a leftover from the fractional-ticket model that Phases 275/276 retired; jackpot entry-awards now resolve to whole tickets and the event surface should read that way.
  - **SUPERSEDES:** D-276-EVT-STATUSQUO-01 ("`ticketCount` continues to emit the pre-Bernoulli scaled value") and D-277-NO-PREROLL-01 (Phase 277 declined to add `preRollTickets` *because* the scaled `ticketCount` already carried pre-roll info — that rationale is now retired along with the scaled emit).
  - **Consequence — event VALUES change** (signature/topic-hash unchanged; this is a field-value semantics shift). Violates Roadmap SC1's literal "no behavior change" wording → roadmap SC1 + REQUIREMENTS JPT-CLEAN text need correction (docs follow-up, see Deferred Ideas). Indexer value-semantics shift is consistent with the milestone's D-40N-EVT-BREAK-01 accepting stance.
  - **Consequence — test churn:** the Phase 276 (`JackpotBernoulliTester`-based) and Phase 277 (`EventSurfaceUnification.test.js`) jackpot-event assertions that expect scaled `ticketCount` MUST be updated to whole-ticket assertions in this phase's test wave.

### TST-CROSS-01 Cross-Surface Mixing Regression

- **D-278-TST-CROSS-ASSERT-01:** Prove independence via **direct `rem`-byte snapshot**. The 3 RNG-driven surfaces all call `_queueTickets` (whole-ticket path), which writes `ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) | uint40(rem)` — preserving the low-8-bit `rem` byte untouched. When all surfaces target the same future level for the same player they write the *same* slot. Assert: `rem` stays `0` through all 10 whole-ticket opens (5 manual lootbox + 3 auto-resolve lootbox + 2 jackpot ticket-roll), then flips non-zero **only** after the single mixed-in mint-boost open (which routes through `_queueTicketsScaled` → `_rollRemainder` per D-40N-MINTBOOST-OUT-01). Mirrors the Phase 275 rem-byte snapshot precedent.

- **D-278-TST-CROSS-DEPTH-01:** Drive the test **full-stack** — call the real `openLootBox` / `openBurnieLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox` / `_awardJackpotTickets` entry points so the genuinely-shared `ticketsOwedPacked[wk][buyer]` slot is exercised. The whole point of a cross-surface test is the real shared-storage interaction; direct-call helpers (Phase 275/276 precedent) would bypass it.

### `EntropyLib.entropyStep` Deletion

- **D-278-ENTROPYSTEP-DELETE-01:** Delete `entropyStep` from `contracts/libraries/EntropyLib.sol` **in this phase**. Post-D-278-ENT05-01 it has zero production callers (sole caller was `JackpotModule.sol:2210`). `EntropyLib` keeps only `hash2`.
  - Update the non-call references: NatSpec at `DegenerusGameJackpotModule.sol:43` + `:2189`; the design-rationale comment at `DegenerusGameMintModule.sol:649` (drop the dead-function name, KEEP the keccak-over-XOR rationale — it remains valid for `_rollRemainder`); and `contracts/test/JackpotBernoulliTester.sol` references (as part of the test wave).
  - **Why:** `feedback_no_dead_guards.md` + `feedback_frozen_contracts_no_future_proofing.md` — contracts are frozen at deploy; don't keep dead library code on future-extensibility grounds. Splitting the deletion to Phase 280 would fragment one logical change across phases for no sequencing benefit.

### Claude's Discretion

- Exact `hash2` second argument in `_jackpotTicketRoll` (self-mix `hash2(entropy, entropy)` vs a fixed salt constant) — plan-phase finalizes, provided per-roll uniqueness (D-278-ENT05-CHAIN-01) holds and is tested.
- Whether the bits[200..215] Bernoulli sub-roll slice offset stays at 200 — with a full keccak word any slice is full-entropy; keeping 200 preserves the Phase-276 NatSpec. Plan-phase confirms.
- Exact NatSpec / comment rewrites on `_awardJackpotTickets` / `_jackpotTicketRoll` / `EntropyLib` / `MintModule:649` per `feedback_no_history_in_comments.md` (describe what IS).
- Storage-layout byte-identity proof recipe (`forge inspect storage-layout` diff vs `git show 6a7455d1`) — planner picks the standard mechanic, mirroring Phase 275/276.
- Theoretical worst-case gas path derivation per `feedback_gas_worst_case.md` — derive FIRST, then benchmark; report bytecode + gas delta in the contract commit message.
- Exact test filenames + placement (Phase 275/276/277 precedent: `test/stat/`, `test/unit/`, `test/regression/`, `test/edge/` vs REQUIREMENTS.md §TST suggestions) — planner reconciles.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project + Milestone Anchors
- `.planning/PROJECT.md` — v40.0 milestone definition; D-40N-* decision anchors (D-40N-SILENT-01 silent-on-cold-bust, D-40N-GRANULARITY-01 TICKET granularity, D-40N-MINTBOOST-OUT-01 mint-boost retention, D-40N-EVT-BREAK-01 breaking topic-hashes accepted); v39.0 closure baseline `MILESTONE_V39_AT_HEAD_6a7455d1`; EXC-04 KI envelope (BAF-jackpot xorshift, currently `NARROWS`).
- `.planning/ROADMAP.md` §"Phase 278: JackpotModule Cleanup + ENT-05 BAF Xorshift Refactor + Wrapper Retirement (JPT-CLEAN)" — goal, dependencies (Phase 276 hard; 275 + 277 for TST-CROSS-01 surface-readiness), requirements list, success criteria 1–6. **NOTE — SC1's literal "no behavior change" on the xTICKET_SCALE cleanup is OVERRIDDEN by D-278-EVT-UNIFY-01** (event values change). NOTE — SC4 EXC-04 demotion is conditional on D-278-ENT05-01 landing.
- `.planning/REQUIREMENTS.md` §JPT-CLEAN (JPT-CLEAN-01..06) + §TST-CLEAN (TST-CLEAN-01..03) + §TST-CROSS (TST-CROSS-01) — requirement-level specs. JPT-CLEAN-01..03 (`xTICKET_SCALE` cleanup) text is reshaped by D-278-EVT-UNIFY-01 from "no behavior change" to whole-ticket unification.
- `.planning/MILESTONES.md` §v39.0 — v39.0 closure record; v36.0 P266 ENT-05 original deferral context.

### Prior Phase Context (carries)
- `.planning/phases/276-jackpotmodule-2216-baf-bernoulli-jpt-br/276-CONTEXT.md` — D-276-RNGBYPASS-01 (`_queueTickets(... true)` at the BAF call site — rngBypass stays `true`), D-276-INLINE-01 (Bernoulli math inlined in `_jackpotTicketRoll`), D-276-EVT-STATUSQUO-01 (**SUPERSEDED by D-278-EVT-UNIFY-01**), JPT-BR-03 per-roll uniqueness invariant (carries — must hold post-keccak-swap), `_queueLootboxTickets` dead-code basis.
- `.planning/phases/277-event-surface-unification-sentinel-retirement-evt-uni/277-CONTEXT.md` — D-277-ROUNDEDUP-01 (`bool roundedUp` added to `JackpotTicketWin` — the retained Bernoulli signal), D-277-NO-PREROLL-01 (**SUPERSEDED by D-278-EVT-UNIFY-01** — its "scaled field already carries pre-roll info" rationale retires with the scaled emit), `JackpotTicketWin` 3-emit-site map.

### v39 Carry Anchors
- `audit/FINDINGS-v39.0.md` §4 (b) — bit-slice pairwise independence via keccak output-entropy; the standard the post-refactor entropy must satisfy.

### Contract Files (audit subject — read from `contracts/` only per `feedback_contract_locations.md`)
- `contracts/modules/DegenerusGameJackpotModule.sol:2204-2265` — `_jackpotTicketRoll`: `EntropyLib.entropyStep` call at `:2210` (swap target, D-278-ENT05-01), low-bit path/level consumers at `:2213-2228`, bits[200..215] Bernoulli at `:2242`, `JackpotTicketWin` emit at `:2254` (whole-ticket swap, D-278-EVT-UNIFY-01), bit-allocation NatSpec at `:2188-2197`.
- `contracts/modules/DegenerusGameJackpotModule.sol:2138-2181` — `_awardJackpotTickets`: 2-roll split pattern (`:2164` / `:2173`); the entropy-chaining site for D-278-ENT05-CHAIN-01.
- `contracts/modules/DegenerusGameJackpotModule.sol:691-727` — trait-burn-ticket loop with `JackpotTicketWin` emit at `:709` (`ticketCount * uint32(TICKET_SCALE)` → whole, D-278-EVT-UNIFY-01).
- `contracts/modules/DegenerusGameJackpotModule.sol:1000-1029` — near/far coin-path loop with `JackpotTicketWin` emit at `:1013` (`uint32(units * TICKET_SCALE)` → whole, D-278-EVT-UNIFY-01).
- `contracts/modules/DegenerusGameJackpotModule.sol:80-95` — `JackpotTicketWin` event def + NatSpec (`ticketCount` semantics rewrite — now whole tickets).
- `contracts/modules/DegenerusGameJackpotModule.sol:43` — module NatSpec referencing `EntropyLib.entropyStep` (update on deletion).
- `contracts/libraries/EntropyLib.sol` — `entropyStep` at `:16-23` (DELETE, D-278-ENTROPYSTEP-DELETE-01); `hash2` at `:36-42` (the swap target — already present, no new function needed).
- `contracts/storage/DegenerusGameStorage.sol:687-700` — `_queueLootboxTickets` wrapper (DELETE — zero callers, JPT-CLEAN-05).
- `contracts/storage/DegenerusGameStorage.sol:562-589` — `_queueTickets` (the whole-ticket path; preserves the `rem` byte untouched — basis for D-278-TST-CROSS-ASSERT-01).
- `contracts/storage/DegenerusGameStorage.sol:596-641` — `_queueTicketsScaled` (STAYS — mint-boost accumulator; the `rem`-byte writer that TST-CROSS-01 isolates to the mint-boost open).
- `contracts/modules/DegenerusGameMintModule.sol:641-654` — `_rollRemainder` + the design-rationale comment at `:649` referencing `entropyStep` (update on deletion — keep the rationale, drop the dead name); `_rollRemainder` already uses `hash2` — the precedent for D-278-ENT05-01.
- `contracts/test/JackpotBernoulliTester.sol` — Phase 276 test helper referencing `EntropyLib.entropyStep` (update in the test wave alongside the deletion).

### Feedback / Discipline
- `feedback_no_contract_commits.md` — never commit `contracts/` or `test/` without explicit user approval.
- `feedback_batch_contract_approval.md` — batch all contract edits, present one diff, one approval at the end.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved.
- `feedback_manual_review_before_push.md` — final user-review gate on the diff before push.
- `feedback_no_dead_guards.md` — drives the `entropyStep` + `_queueLootboxTickets` deletions; no leftover unreachable code.
- `feedback_frozen_contracts_no_future_proofing.md` — contracts frozen at deploy; don't keep dead library code for hypothetical future use.
- `feedback_design_intent_before_deletion.md` — applied during this discussion (xorshift design-intent + game-theory traced before the ENT-05 decision); carries to plan-phase for the deletion shapes.
- `feedback_no_history_in_comments.md` — NatSpec/comment rewrites describe what IS, never what changed.
- `feedback_gas_worst_case.md` — derive theoretical worst-case gas FIRST, then benchmark.
- `feedback_skip_research_test_phases.md` — wrapper retirement + entropyStep deletion are mechanical; the ENT-05 refactor + event unification carry their design rationale in this CONTEXT.md — plan-phase may skip the research agent.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`EntropyLib.hash2(a, b)`** (`contracts/libraries/EntropyLib.sol:36`) — scratch-slot keccak, ~10× cheaper than `abi.encode` keccak; already the ENT-05 swap target, no new library function required.
- **`_rollRemainder` keccak precedent** (`DegenerusGameMintModule.sol:652`) — already does `EntropyLib.hash2(entropy, rollSalt)` for exactly the low-bit-diffusion reason ENT-05 targets; the canonical pattern to mirror.
- **`bool roundedUp` field on `JackpotTicketWin`** (Phase 277, D-277-ROUNDEDUP-01) — already live on all 3 emit sites; becomes the sole retained pre-Bernoulli signal after D-278-EVT-UNIFY-01.
- **`_queueTickets`** (`DegenerusGameStorage.sol:562`) — whole-ticket path; `ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) | uint40(rem)` preserves the `rem` byte. This preservation IS the TST-CROSS-01 invariant.

### Established Patterns
- **Return-and-rethread entropy chaining** — `_jackpotTicketRoll` returns the evolved entropy word and `_awardJackpotTickets` threads it into the next roll. D-278-ENT05-CHAIN-01 keeps this pattern; only the evolution primitive (`entropyStep` → `hash2`) changes.
- **`rem` byte at `ticketsOwedPacked` low 8 bits** — `_queueTicketsScaled` writes/accumulates it; `_queueTickets` never touches it. The structural basis for proving cross-surface independence.
- **Storage-layout byte-identity discipline** — every v40 phase asserts byte-identical layout vs `6a7455d1`; Phase 278 touches only function bodies + event values + a library function deletion (event signatures and storage slots unchanged).

### Integration Points
- **Mutations confined to:** `DegenerusGameJackpotModule.sol` (`_jackpotTicketRoll` body + `_awardJackpotTickets` chaining + 3 `JackpotTicketWin` emit sites + `JackpotTicketWin` NatSpec + module NatSpec), `EntropyLib.sol` (`entropyStep` deletion), `DegenerusGameStorage.sol` (`_queueLootboxTickets` deletion), `DegenerusGameMintModule.sol` (`:649` comment touch only — no code change).
- **No new state variables, no new events, no new modifiers, no new admin/external entry points** — storage layout byte-identical; `JackpotTicketWin` signature/topic-hash unchanged (only emitted values shift).
- **Cross-module byte-identity expected** for `DegenerusGameLootboxModule`, `JackpotBucketLib`, `TraitUtils`, `PriceLookupLib` (no shared-helper edits).
- **Test churn:** Phase 276 (`JackpotBernoulliTester`) + Phase 277 (`EventSurfaceUnification.test.js`) jackpot-event assertions that expect scaled `ticketCount` must be updated to whole-ticket assertions in this phase's test wave.

</code_context>

<specifics>
## Specific Ideas

- **User intent on event unification (2026-05-14, verbatim):** "can we try to unify things as best we can so it is clear that other than purchases (and whale passes) we always award one ticket when awarding entries." Drives D-278-EVT-UNIFY-01 — the whole-ticket award model should be legible in the event surface, not masked by legacy ×100 scaling.
- **ENT-05 practical-effect framing (discussed 2026-05-14):** the xorshift→keccak swap fixes a chi-square-detectable (~sub-percentage-point) distribution skew in the 30/65/5 path roll and offset distributions; it is NOT a security/exploit fix (VRF-seeded entropy is unpredictable). Value is audit cleanliness — converting EXC-04 from a *documented* known-issue to a *fixed* non-issue at near-zero gas cost.
- **TST-CROSS-01 shape (Roadmap SC5):** 5 manual lootbox opens + 3 auto-resolve lootbox opens + 2 jackpot ticket-roll awards + 1 mint-boost open, same player, same target future level. Full-stack invocation; direct `rem`-byte snapshot before/after each surface family.

</specifics>

<deferred>
## Deferred Ideas

- **ROADMAP.md + REQUIREMENTS.md text correction** — Roadmap §Phase 278 SC1 + JPT-CLEAN-01..03 say the `xTICKET_SCALE` cleanup is "no behavior change"; D-278-EVT-UNIFY-01 makes it a whole-ticket event-value unification (values change). Roadmap SC2's EXC-04 demotion is now firmly conditional on D-278-ENT05-01. These are docs-only follow-ups, not part of the contract/test waves. Flagged to user at context-close.
- **Whole-BURNIE floor at lootbox spin + near/far-future coin jackpot** — Phase 279 (BUR).
- **Terminal delta audit + EXC-04 RE_VERIFICATION (NARROWS → candidate NEGATIVE) + findings consolidation** — Phase 280.
- **MintModule's own xorshift / `_queueTicketsScaled` / `_rollRemainder` / `rem` byte** — explicitly OUT of scope per D-40N-MINTBOOST-OUT-01; retained as the deterministic mint-boost dust accumulator. Phase 278 touches only the stale `entropyStep`-referencing *comment* at `MintModule:649`, not MintModule code.

### Reviewed Todos (not folded)
None — `todo.match-phase` returned zero matches for Phase 278.

</deferred>

---

*Phase: 278-JackpotModule Cleanup + ENT-05 BAF Xorshift Refactor + Wrapper Retirement (JPT-CLEAN)*
*Context gathered: 2026-05-14*
