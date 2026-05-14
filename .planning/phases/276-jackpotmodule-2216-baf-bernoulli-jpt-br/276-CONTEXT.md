# Phase 276: JackpotModule:2216 BAF Bernoulli (JPT-BR) - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply Bernoulli round-up to the JackpotModule small-lootbox ticket-roll path — the JackpotModule mirror of Phase 275's auto-resolve LootboxModule work. `_jackpotTicketRoll` (`contracts/modules/DegenerusGameJackpotModule.sol:2186`) reads `bits[200..215]` of the existing `entropy` chain (16-bit slice for <0.10% relative bias; 180+ bits separated from the existing `bits[0..12]` path/bucket-selection consumers at `:2195-2210`) and Bernoulli-collapses scaled tickets to whole tickets at award time. Predicate: `frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)` → `roundedUp = true`; assign `whole = (scaledTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)`. The `_queueLootboxTickets(winner, targetLevel, quantityScaled, true)` wrapper call at `:2216` swaps to a direct `_queueTickets(winner, targetLevel, whole, true)` call (rngBypass stays `true` — see D-276-RNGBYPASS-01; this OVERRIDES the roadmap/requirements JPT-BR-02 text that says `false`). The `_queueLootboxTickets` wrapper function itself is NOT retired in this phase — Phase 278 JPT-CLEAN-05 retires it (`:2216` is its only caller; this phase makes it dead code). Jackpot cold-bust is SILENT per D-40N-SILENT-01 — when `whole == 0` post-Bernoulli, `_queueTickets` early-returns at `DegenerusGameStorage.sol:568` and no `wwxrp.mintPrize(...)` / `LootBoxWwxrpReward` fires. Bit-allocation NatSpec on `_awardJackpotTickets` / `_jackpotTicketRoll` updated to document the new `bits[200..215]` sub-roll. `JackpotTicketWin` event surface UNCHANGED this phase (Phase 277 EVT-UNI-04 adds the `roundedUp` field); `ticketCount` continues to carry the pre-Bernoulli scaled value. Storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `MILESTONE_V39_AT_HEAD_6a7455d1`. Net gas-NEGATIVE expected after factoring `_queueTickets(whole)` smaller storage write + eliminated `_rollRemainder` consumption at trait-assignment time.

Wave shape: 1 USER-APPROVED batched contract commit `feat(276): jackpot ticket-roll Bernoulli whole-ticket [JPT-BR-01..06]` + 1 USER-APPROVED batched test commit `test(276): jackpot ticket-roll Bernoulli + silent cold-bust + bit-slice independence + 2-roll uniqueness [TST-JPT-BR-01..04]` (`feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`).

</domain>

<decisions>
## Implementation Decisions

### `rngBypass` Argument on the New `_queueTickets` Call Site

- **D-276-RNGBYPASS-01:** The new `_queueTickets` call at `:2216` passes `rngBypass = true` — `_queueTickets(winner, targetLevel, whole, true)`. This OVERRIDES the literal roadmap/requirements JPT-BR-02 text, which says `false` (a copy-paste artifact carried over from Phase 275 LBX-AR's surface, where `false` IS correct).
  - **Why:** `_jackpotTicketRoll` runs inside the `advanceGame` processing window — `payDailyJackpot` / `payDailyJackpotCoinAndTickets` (`DegenerusGameAdvanceModule.sol:452-473`) call `_awardJackpotTickets` → `_jackpotTicketRoll` BEFORE `_unlockRng(day)` fires (`:466`, `:401`, `:330`). So `rngLockedFlag == true` is the live state on every invocation. `_jackpotTicketRoll` picks `targetLevel = minTargetLevel + 1..50` (`:2199-2210`); the 5%-branch (`+5..+50`) and the upper part of the 65%-branch yield `isFarFuture == true` (`targetLevel > level + 5`). The `_queueTickets` guard at `DegenerusGameStorage.sol:575` is `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` — passing `false` would revert `advanceGame` on every far-future jackpot ticket roll, freezing the game state machine. The current `_queueLootboxTickets(... true)` wrapper passes `rngBypass = true` BY DESIGN for exactly this reason.
  - **Design principle (user, 2026-05-14, verbatim intent):** Far-future tickets awarded as part of the `advanceGame` chain are part of the *deterministic sequence of jackpot awards that must happen for the game to move forward* → they bypass the RNG lock. Far-future tickets that are *claimable on demand* (lootboxes, whale passes) must revert during RNG-lock — otherwise they could influence jackpot outcomes. This is the exact asymmetry that makes Phase 275 LBX-AR's `false` correct for its surface (auto-resolve lootbox callers run OUTSIDE the lock, post-VRF-callback) and `true` correct here.
  - **Roadmap-text follow-up:** ROADMAP.md §Phase 276 SC1 + REQUIREMENTS.md JPT-BR-02 still say `false`. They should be corrected to `true` to keep source docs aligned with this decision-anchor. Flagged to user at context-close; not edited mid-discuss.

### Bernoulli Code Shape Inside `_jackpotTicketRoll`

- **D-276-INLINE-01:** Bernoulli round-up math (~4 lines: derive `frac`, roll `bits[200..215]`, compute `whole`) is inlined directly before the `_queueTickets` call inside `_jackpotTicketRoll`. NO `_bernoulliWhole(...)` helper extraction.
  - **Why:** `_jackpotTicketRoll` is a single-path private function — no sentinel-gated dual branch like Phase 275's `_resolveLootboxCommon` (which needed the D-275-HOIST-01 hoist). A helper would have exactly one call site. The slice offsets differ across surfaces (`bits[152..167]` lootbox vs `bits[200..215]` jackpot), so a shared helper would need the slice as a parameter anyway, and extracting a cross-module helper would mean re-touching Phase 275's already-committed `_resolveLootboxCommon` — scope creep. Phase 275 explicitly deferred the helper (option A3) for the same structural reason.

### `JackpotTicketWin` Event Field Semantics (Carried — Not Re-Discussed)

- **D-276-EVT-STATUSQUO-01:** `JackpotTicketWin.ticketCount` continues to emit the pre-Bernoulli scaled value (`uint32(quantityScaled)`), and the event surface is otherwise UNCHANGED this phase. Phase 277 EVT-UNI-04 adds the `bool roundedUp` field; EVT-UNI-04's own text states `JackpotTicketWin` "already emits scaled values ... the existing `preRollTickets`-equivalent semantics live in current event fields" — i.e. `ticketCount` is meant to stay pre-Bernoulli scaled. The event-doc NatSpec at `DegenerusGameJackpotModule.sol:79-93` and the inline comment at `:2218-2219` need wording updates to reflect that BAF lootbox rolls no longer carry a fractional remainder into `_rollRemainder` (per `feedback_no_history_in_comments.md` — describe what IS, not what changed).

### Claude's Discretion

- Exact bit-allocation NatSpec wording on `_awardJackpotTickets` / `_jackpotTicketRoll` per JPT-BR-06 — planner finalizes consistent with v39/Phase-275 style; must document the `bits[200..215] jackpotTicketRoundUp % 100` sub-roll and the 180+ bit separation from the `bits[0..12]` consumers.
- Exact wording of the updated `JackpotTicketWin` event-doc NatSpec (`:79-93`) and the inline comment at `:2218-2219`.
- Storage-layout byte-identity proof recipe (`forge inspect storage-layout` diff vs `git show 6a7455d1` artifact) — planner picks the standard mechanic, mirroring Phase 275's D-275 discretion item.
- Exact test filenames + function names + folder placement within the test tree — planner finalizes consistent with Phase 275 / v39 TST naming conventions (REQUIREMENTS.md §TST-JPT-BR header suggests `test/jackpot/` or `test/edge/`; Phase 275 precedent put EV-neutrality + chi-square in `test/stat/` and silent-cold-bust + regression in `test/unit/` — planner reconciles).
- Theoretical worst-case gas path derivation per `feedback_gas_worst_case.md` — derive FIRST, then benchmark. Likely candidate: the 5%-branch (`+5..+50` levels) producing max `isFarFuture` target → far-future queue key path (`_tqFarFutureKey`) → cold queue (`ticketQueue` push) → single `_queueTickets(whole)` write. Planner finalizes and reports bytecode + gas delta in the contract commit message, head-to-head comparable with the v39 manual-path number.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project + Milestone Anchors
- `.planning/PROJECT.md` — v40.0 milestone definition; D-40N-* decision anchors (silent-on-cold-bust D-40N-SILENT-01, sentinel retirement D-40N-SENTINEL-RETIRE-01, granularity D-40N-GRANULARITY-01, mint-boost retention D-40N-MINTBOOST-OUT-01); v39.0 closure baseline `MILESTONE_V39_AT_HEAD_6a7455d1`.
- `.planning/ROADMAP.md` §"Phase 276: JackpotModule:2216 BAF Bernoulli (JPT-BR)" — goal, dependencies, requirements list, success criteria 1–6. NOTE: SC1 + JPT-BR-02 say `_queueTickets(... false)` — OVERRIDDEN to `true` by D-276-RNGBYPASS-01.
- `.planning/REQUIREMENTS.md` §JPT-BR (JPT-BR-01..06) + §TST-JPT-BR (TST-JPT-BR-01..04) — requirement-level specifications. JPT-BR-02 `false` overridden per D-276-RNGBYPASS-01.
- `.planning/MILESTONES.md` §v39.0 — Phase 274 manual-path Bernoulli reference (mirror-the-pattern); v39.0 closure record.
- `.planning/phases/275-auto-resolve-lootboxmodule-bernoulli-lbx-ar/275-CONTEXT.md` — Phase 275 LBX-AR precedents: D-275-HOIST-01 (code-shape rationale), D-275-GAS-WC-01 (worst-case-first gas discipline), D-275-TST-04-01 / D-275-TST-05-01 (direct-call test approach + rem-byte snapshot), D-275-TST-PLACEMENT-01 (test folder scheme), helper-extraction deferral (option A3).

### v39 Carry Anchors (manual-path Bernoulli baseline)
- `audit/FINDINGS-v39.0.md` §4 (a) — EV-neutrality identity `E[whole_post] = scaledPre / TICKET_SCALE` proof; carries to the jackpot ticket-roll surface verbatim.
- `audit/FINDINGS-v39.0.md` §4 (b) — bit-slice pairwise independence via keccak output-entropy; carries to the `bits[200..215]` jackpot slice (per-roll distinct keccak input via `EntropyLib.entropyStep`).

### Contract Files (audit subject)
- `contracts/modules/DegenerusGameJackpotModule.sol:2186` — `_jackpotTicketRoll` function entry (Bernoulli inline site per D-276-INLINE-01).
- `contracts/modules/DegenerusGameJackpotModule.sol:2192-2210` — existing entropy chain: `EntropyLib.entropyStep` + `bits[0..12]` consumers (`% 100` path roll, `% 4` / `% 46` level offsets).
- `contracts/modules/DegenerusGameJackpotModule.sol:2215-2216` — `quantityScaled` compute + `_queueLootboxTickets(... true)` call site (swap target per JPT-BR-02 / D-276-RNGBYPASS-01).
- `contracts/modules/DegenerusGameJackpotModule.sol:2218-2227` — inline comment + `JackpotTicketWin` emit (comment update per D-276-EVT-STATUSQUO-01; event fields unchanged).
- `contracts/modules/DegenerusGameJackpotModule.sol:79-93` — `JackpotTicketWin` event-doc NatSpec (wording update per D-276-EVT-STATUSQUO-01).
- `contracts/modules/DegenerusGameJackpotModule.sol:2131-2174` — `_awardJackpotTickets`: the 2-roll split pattern (L2157 / L2166) for the medium-amount branch; `EntropyLib.entropyStep` evolves entropy between rolls (JPT-BR-03 per-roll uniqueness; bit-allocation NatSpec update per JPT-BR-06).
- `contracts/modules/DegenerusGameJackpotModule.sol:2075` / `:2106` — `_awardJackpotTickets` call sites inside the BAF winner-payout loop.
- `contracts/storage/DegenerusGameStorage.sol:562` — `_queueTickets(buyer, targetLevel, quantity, rngBypass)` (new target; early-returns at `:568` on `quantity == 0` → satisfies silent cold-bust; rngLocked guard at `:575`).
- `contracts/storage/DegenerusGameStorage.sol:687` — `_queueLootboxTickets` wrapper (current call target; NOT retired this phase — Phase 278 JPT-CLEAN-05 retires it).
- `contracts/storage/DegenerusGameStorage.sol:596` — `_queueTicketsScaled` (the rem-byte / `_rollRemainder` accumulator that the jackpot path stops feeding after this phase; still used by MintModule mint-boost).

### rngBypass Timing Trace (D-276-RNGBYPASS-01 evidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol:452-473` — `advanceGame` jackpot-phase block: `payDailyJackpot` / `payDailyJackpotCoinAndTickets` invoked before `_unlockRng(day)`.
- `contracts/modules/DegenerusGameAdvanceModule.sol:1696-1703` — `_unlockRng` clears `rngLockedFlag` AFTER jackpot processing.
- `contracts/modules/DegenerusGameAdvanceModule.sol:1601` — `_finalizeRngRequest` sets `rngLockedFlag = true` at RNG request time.
- `contracts/storage/DegenerusGameStorage.sol:575` — the `isFarFuture && rngLockedFlag && !rngBypass` revert guard inside `_queueTickets`.

### Feedback / Discipline
- `feedback_no_contract_commits.md` — never commit contracts/ or test/ without explicit user approval.
- `feedback_batch_contract_approval.md` — batch all contract edits, present one diff, one approval at the end.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved.
- `feedback_manual_review_before_push.md` — final user-review gate on the diff before push.
- `feedback_gas_worst_case.md` — derive theoretical worst case FIRST, then benchmark (drives the gas-delta discretion item).
- `feedback_no_history_in_comments.md` — comments describe what IS, never what changed (drives the NatSpec/comment-update discretion items).
- `feedback_no_dead_guards.md` — context for Phase 278 wrapper retirement; not actioned this phase (no deletions in Phase 276).
- `feedback_skip_research_test_phases.md` — this is a mechanical mirror of Phase 275; plan-phase may skip the research agent.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_queueTickets(buyer, targetLevel, quantity, rngBypass)` at `DegenerusGameStorage.sol:562`** — whole-ticket helper with `if (quantity == 0) return;` early-return at `:568` before any event emit or storage write. Silent cold-bust (JPT-BR-04) is satisfied for free by calling `_queueTickets(winner, targetLevel, whole, true)` unconditionally — no extra `whole == 0` guard needed. Same property Phase 275 LBX-AR relied on.
- **Phase 275 / v39 manual-path Bernoulli predicate** — `frac != 0 && (uint16(seed >> N) % uint16(TICKET_SCALE)) < uint16(frac)` carries verbatim with `N = 200` and `seed = entropy`.
- **`TICKET_SCALE` constant** — compile-time inlined (no storage slot), already used at `:2215` for `quantityScaled`.

### Established Patterns
- **`EntropyLib.entropyStep` per-roll evolution** — `_jackpotTicketRoll` calls `entropy = EntropyLib.entropyStep(entropy)` at `:2192` on entry; in the medium-amount 2-roll branch, `_awardJackpotTickets` threads the evolved `entropy` return value between L2157 and L2166, so each roll's `bits[200..215]` slice is from a distinct keccak output (JPT-BR-03 / TST-JPT-BR-04 basis).
- **`bits[0..12]` low-bit consumers in `_jackpotTicketRoll`** — `entropy % 100` (path roll, `:2196`), `entropyDiv100 % 4` / `% 46` (level offsets, `:2204` / `:2208`). The new `bits[200..215]` slice is 180+ bits separated — the JPT-BR-06 NatSpec must document this gap; TST-JPT-BR-03 chi-square verifies independence.
- **`_queueLootboxTickets` wrapper** at `DegenerusGameStorage.sol:687` is a thin pass-through to `_queueTicketsScaled` — `JackpotModule.sol:2216` is its ONLY caller (Phase 278 dead-code retirement basis).
- **rem-byte at `ticketsOwedPacked` low 8 bits** — `_queueTicketsScaled` writes/accumulates `rem`; `_queueTickets` never touches it. After this phase the jackpot path stops feeding `rem` → eliminated `_rollRemainder` consumption is the gas-negative driver (JPT-BR-05).

### Integration Points
- **Only mutation:** `_jackpotTicketRoll` body — inline Bernoulli math + call-site swap at `:2216` (`_queueLootboxTickets(... scaled, true)` → `_queueTickets(... whole, true)`) + inline-comment update at `:2218-2219`; plus the bit-allocation NatSpec on `_awardJackpotTickets` / `_jackpotTicketRoll` (JPT-BR-06) and the `JackpotTicketWin` event-doc NatSpec at `:79-93`.
- **No new state variables, no new events, no new modifiers, no new external/admin entry points** — storage layout byte-identical (JPT-BR-06 / Phase 278 JPT-CLEAN-06 scope).
- **`_queueLootboxTickets` wrapper stays in place** this phase (becomes dead code; Phase 278 retires it).
- **Cross-module byte-identity expected** for LootboxModule, MintModule, EntropyLib, JackpotBucketLib, TraitUtils, DegenerusGameStorage helpers (no shared-helper edits — D-276-INLINE-01 keeps the change local to JackpotModule).

</code_context>

<specifics>
## Specific Ideas

- **rngBypass asymmetry rule (user, 2026-05-14):** "far future tickets awarded as part of the advancegame chain need to bypass the rng lock because they are a part of the deterministic sequence of jackpot awards that must happen for the game to move forward. far future tickets that are claimable on demand like lootboxes or whale passes need to revert during RNGlock or else they could influence jackpot outcomes." This is the canonical rationale for D-276-RNGBYPASS-01 and the design distinction from Phase 275 LBX-AR.
- **Worst-case gas benchmark target:** `_jackpotTicketRoll` on the 5%-branch — max far-future `targetLevel` (`minTargetLevel + 50`) → `_tqFarFutureKey` write path → cold `ticketQueue` push → single `_queueTickets(whole)` whole-ticket write. Derive analytically per `feedback_gas_worst_case.md`, then benchmark.
- **Chi-square / EV sample sizes:** ≥10K seeded invocations per TST-JPT-BR-01 (EV-neutrality) and TST-JPT-BR-03 (bit-slice independence) — matches v39 TST-WT + Phase 275 TST-LBX-AR precedent.

</specifics>

<deferred>
## Deferred Ideas

- **`_queueLootboxTickets` wrapper retirement** — Phase 278 JPT-CLEAN-05. `JackpotModule.sol:2216` is the wrapper's only caller; this phase makes it dead code but does not delete it.
- **`xTICKET_SCALE` cosmetic cleanup at `JackpotModule.sol:702/835/1005`** — Phase 278 JPT-CLEAN-01..03.
- **ENT-05 BAF xorshift refactor** — Phase 278 JPT-CLEAN-04 (deferred since v36.0 P266).
- **`JackpotTicketWin.roundedUp` field addition** — Phase 277 EVT-UNI-04. This phase leaves the event surface untouched; TST-JPT-BR test wave uses the pre-EVT-UNI event shape, Phase 277's test wave updates the assertions.
- **`_bernoulliWhole` shared helper extraction** — considered and rejected per D-276-INLINE-01 (single call site, slice-offset divergence across surfaces, would require re-touching Phase 275's committed `_resolveLootboxCommon`). Same disposition as Phase 275 option A3.
- **Cross-surface mixing regression (TST-CROSS-01)** — Phase 278; requires all 3 RNG-driven surfaces in their final state.
- **Full-stack 4-caller seed-uniqueness exercise** — TST-JPT-BR-04 uses the direct-call approach (mirror of Phase 275 D-275-TST-04-01); full-stack exercise remains a deferred option if the Phase 279 adversarial pass surfaces a concern.

</deferred>

---

*Phase: 276-JackpotModule:2216 BAF Bernoulli (JPT-BR)*
*Context gathered: 2026-05-14*
