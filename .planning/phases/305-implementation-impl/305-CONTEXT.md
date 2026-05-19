# Phase 305: Implementation (IMPL) — Context

**Gathered:** 2026-05-19
**Status:** Ready for planning
**Spec lock:** `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` (960 lines, 35 requirements LOCKED — INV-01..12 + SPEC-01..05 + EDGE-01..18)

<spec_lock>
## Locked Requirements (304-SPEC.md)

Phase 304 SPEC ships every load-bearing input for Phase 305 IMPL. The planner and executor MUST read 304-SPEC.md and treat the following as non-negotiable inputs:

- **§1 INV-01..12** — Formal accounting invariants the post-refactor `StakedDegenerusStonk.sol` must satisfy. Proven at Phase 306 TST, attested at Phase 308 §3.F.
- **§2 SPEC-01..05** — Design decisions LOCKED (commit `6edc3967`):
    - **SPEC-01:** `struct DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }`; `mapping(uint32 => DayPending) internal pendingByDay`; 3 slots per active day.
    - **SPEC-02:** `mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions` (composite key); `claimRedemption(uint32 day) external` signature; `UnresolvedClaim` revert at `:796-797` REMOVED; `NotResolved` revert at `:624` PRESERVED; inner `periodIndex` field REMOVED.
    - **SPEC-03:** `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external`; `function hasPendingRedemptions(uint32 day) external view returns (bool)`; both call sites pass identical `dayToResolve = currentDayView() - 1` (or AdvanceModule-side equivalent `day - 1`).
    - **SPEC-04:** Four sub-locks: (a) `pendingByDay[D]` SURVIVES `game.gameOver`; no separate `gameOver` branch in `resolveRedemptionPeriod`; existing `:638-643` split logic handles post-gameOver payout; (b) zero-rounded `ethValueOwed` burns PROCEED with zero claim; existing `amount == 0` revert at `:754` preserved; no new round-to-zero branch; (c) `delete pendingByDay[dayToResolve]` fires AFTER `redemptionPeriods[D]` written + `RedemptionResolved` event emitted; (d) `delete pendingRedemptions[msg.sender][day]` fires AFTER `_payEth` + `_payBurnie` + `RedemptionClaimed` on full-claim path only; partial-claim branch at `:659-665` preserved VERBATIM.
    - **SPEC-05:** `pendingByDay[D].supplySnapshot` lazy-initialized on first burn of day D — predicate `pendingByDay[currentDay].supplySnapshot == 0 && pendingByDay[currentDay].burned == 0`; pre-decrement `totalSupply` captured (`supplyBefore` semantic preserved); cap check `pendingByDay[currentDay].burned + amount > pendingByDay[currentDay].supplySnapshot / 2`.
- **§2.7 — 7 deletions** (each design-intent + actor game-theory traced at §4):
    1. `redemptionPeriodIndex` slot at `:230`
    2. `redemptionPeriodSupplySnapshot` slot at `:229`
    3. `redemptionPeriodBurned` slot at `:231`
    4. `pendingRedemptionEthBase` slot at `:226`
    5. `pendingRedemptionBurnieBase` slot at `:227`
    6. `UnresolvedClaim` revert at `:796-797`
    7. `redemptionPeriodIndex` reset block at `:757-762` (replaced by SPEC-05 lazy-init)
- **§3 EDGE-01..18** — Exhaustive scenario enumeration with positive + negative assertions. Phase 306 mechanizes one fuzz function per EDGE; EDGE-07 is the headline V-184 negative test.
- **§5 source-verified citation manifest** — 61 citations grep-verified at v43.0 closure HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2` (50 `StakedDegenerusStonk.sol` + 11 `DegenerusGameAdvanceModule.sol`). All THREE AdvanceModule `resolveRedemptionPeriod` call sites attested at `:1230` + `:1293` + `:1323`.

**Posture:** pre-launch, frozen-at-deploy per `feedback_frozen_contracts_no_future_proofing.md`. Storage layout breaks ACCEPTED; redeploy-fresh; no migration scaffolding.

**Requirements:** IMPL-01..04 (4). SPEC requirements 100% delivered (commit `6edc3967` + downstream Plans 03–05). No re-litigation in IMPL.

</spec_lock>

<domain>
## Phase Boundary

Single batched USER-APPROVED contract diff per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Refactors `contracts/StakedDegenerusStonk.sol` per the Phase 304 SPEC §2 locks; updates the three `contracts/modules/DegenerusGameAdvanceModule.sol` call sites at `:1230`, `:1293`, `:1323` to pass the new `dayToResolve` arg; updates the `contracts/interfaces/IStakedDegenerusStonk.sol` interface to match the two new signatures; updates existing test files that reference the old signatures so `forge build` PASS (mandatory per success criterion #1).

### In scope (single batched USER-APPROVED diff at end of phase)

**`contracts/StakedDegenerusStonk.sol` (12 source mutations per SPEC §2 locks):**
- DELETE `pendingRedemptionEthBase` slot declaration at `:226`.
- DELETE `pendingRedemptionBurnieBase` slot declaration at `:227`.
- DELETE `redemptionPeriodSupplySnapshot` slot declaration at `:229`.
- DELETE `redemptionPeriodIndex` slot declaration at `:230`.
- DELETE `redemptionPeriodBurned` slot declaration at `:231`.
- ADD `struct DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }` declaration (in contract scope, near the existing storage block).
- ADD `mapping(uint32 => DayPending) internal pendingByDay` declaration (replaces the 5 deleted slots).
- CHANGE `mapping(address => PendingRedemption) public pendingRedemptions` at `:221` to `mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions` (composite key per SPEC-02).
- REMOVE inner `uint32 periodIndex` field from `PendingRedemption` struct (`:212` per SPEC §1 storage-table — composite outer key carries the day).
- DELETE `UnresolvedClaim` error declaration at `:108` (revert no longer used per SPEC-02).
- REPLACE `:757-762` reset block in `_submitGamblingClaimFrom` with SPEC-05 lazy-init: `if (pendingByDay[currentDay].supplySnapshot == 0 && pendingByDay[currentDay].burned == 0) { pendingByDay[currentDay].supplySnapshot = uint128(totalSupply); }`.
- RE-KEY all writes in `_submitGamblingClaimFrom` (`:789-792`) to `pendingByDay[currentDay].*` + `pendingRedemptions[beneficiary][currentDay]` composite; DELETE the `UnresolvedClaim` block at `:796-797`.

**`contracts/StakedDegenerusStonk.sol` (function-level signature + body changes):**
- `function hasPendingRedemptions() external view returns (bool)` at `:577` → `function hasPendingRedemptions(uint32 day) external view returns (bool)`; body returns `pendingByDay[day].ethBase != 0 || pendingByDay[day].burnieBase != 0`.
- `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external` at `:585` → `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external`; body reads `pendingByDay[dayToResolve].*`; writes `redemptionPeriods[dayToResolve]`; emits `RedemptionResolved`; then `delete pendingByDay[dayToResolve]` per SPEC-04 (c).
- `function claimRedemption() external` at `:618` → `function claimRedemption(uint32 day) external`; reads `pendingRedemptions[msg.sender][day]` + `redemptionPeriods[day]`; `NotResolved` revert preserved at `:624`; partial-claim branch at `:659-665` preserved VERBATIM; `delete pendingRedemptions[msg.sender][day]` on full-claim path per SPEC-04 (d).

**`contracts/modules/DegenerusGameAdvanceModule.sol` (3 call-site updates):**
- `:1225 + :1230` (rngGate primary path) — update `hasPendingRedemptions()` → `hasPendingRedemptions(day - 1)`; update `resolveRedemptionPeriod(redemptionRoll, flipDay)` → `resolveRedemptionPeriod(redemptionRoll, flipDay, day - 1)`.
- `:1288 + :1293` (`_gameOverEntropy` stale-VRF path) — same dual update.
- `:1318 + :1323` (`_gameOverEntropy` fallback path) — same dual update.

**`contracts/interfaces/IStakedDegenerusStonk.sol` (2 signature updates, mandatory for build):**
- `:86` `function hasPendingRedemptions() external view returns (bool)` → `function hasPendingRedemptions(uint32 day) external view returns (bool)`.
- `:96` `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external` → `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external`.

**Existing test compile-break fixes (AGENT-COMMITTED per `D-43N-TEST-COMMITS-AUTO-01` + `feedback_no_contract_commits.md` test policy):**
- `test/fuzz/RedemptionGas.t.sol` — `:78`, `:94`, `:127`, `:134` (and the `IStakedDegenerusStonk` cast at `:9-10` doc-comment update). All references to the old 2-arg `resolveRedemptionPeriod(100, currentDay)` rewrite to 3-arg `resolveRedemptionPeriod(100, currentDay, currentDay - 1)` (or SPEC-locked-equivalent literal); all `hasPendingRedemptions()` rewrite to `hasPendingRedemptions(currentDay - 1)`. Function bodies otherwise byte-identical; gas-benchmark intent preserved.
- `test/fuzz/CoverageGap222.t.sol:948` — `"resolveRedemptionPeriod(uint16,uint32)"` selector string updates to `"resolveRedemptionPeriod(uint16,uint32,uint32)"`. Assertion text at `:973` byte-identical.

These test edits land in the same end-of-phase batched diff alongside the contract changes per the user-explicit policy that mainnet `contracts/*.sol` need user approval and `test/` is AGENT-COMMITTED inside the same atomic commit (`feedback_no_contract_commits.md` clarified policy).

### Out of scope (Phase 306 TST + Phase 307 SWEEP + Phase 308 TERMINAL deliverables)

- New Foundry coverage at `test/fuzz/StakedStonkRedemption.t.sol` + `test/invariant/RedemptionAccounting.t.sol` + `test/fuzz/RedemptionEdgeCases.t.sol` (TST-01..03 — Phase 306).
- `test/fuzz/RngLockDeterminism.t.sol` HANDOFF-111..117 `vm.skip(true)` → strict-byte-identity flip (TST-05 — Phase 306).
- Gas regression bench (`burn ≤ +5% v43`, `claim ≤ +0% v43`) — TST-06 Phase 306.
- 3-skill adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) — SWP-01..05 Phase 307.
- `audit/FINDINGS-v44.0.md` 9-section TERMINAL deliverable — AUDIT-01..09 + REG-01 + CLS-01..02 Phase 308.
- 135 v43 backlog anchors deferred to v45.0+ per `audit/FINDINGS-v43.0.md` §9d handoff register.
- Storage migration scaffolding — REJECTED per pre-launch posture.
- `claimMultipleRedemptions` batch helper — REJECTED per REQUIREMENTS.md Out-of-Scope table (immediate-claim UX assumed; players call `claimRedemption(day)` N times for stacked claims).
- `IDegenerusGamePlayer` interface expansion — UNCHANGED (`currentDayView` already exposed at `:32`; no new methods required).

</domain>

<decisions>
## Implementation Decisions

### Research Dispatch
- **D-305-RESEARCH-01:** Skip `gsd-phase-researcher` dispatch per `feedback_skip_research_test_phases.md`. 304-SPEC.md is 960 lines with every cited file:line grep-verified (Plan 05 manifest, 61 citations); SPEC-01..05 LOCKED with sub-locks (a–d); 7 deletions design-intent + actor game-theory traced at §4; 18 EDGE scenarios enumerated with positive + negative assertions. Research adds no new information. Plan directly. Mirrors Phase 263 D-APPROVAL-02 + Phase 259 D-11 + Phase 260 D-11 mechanical-phase precedent.

### Plan Slicing
- **D-305-PLAN-01:** Single-plan atomic shape recommended; planner picks final slicing. Reference shape: P1 = (storage-layout deletions + struct/mapping additions + `_submitGamblingClaimFrom` rewrite + `resolveRedemptionPeriod` signature + body + `claimRedemption(uint32)` signature + body + `hasPendingRedemptions(uint32)` signature + body + interface delta + 3 AdvanceModule call-site updates + existing test compile-break fixes), all in one commit per the ROADMAP's "Single batched contract diff" anchor + `feedback_batch_contract_approval.md`. Storage layout breaks atomically; partial landing breaks `forge build`. Multi-plan acceptable ONLY if all plans' commits stay co-batched at the end-of-phase USER-APPROVED gate (i.e., plans land internally as AGENT-COMMITTED `.planning/` artifacts, but the contract diff itself stays single + atomic). Mirrors Phase 263 D-PLAN-01.

### Pre-patch Grep Re-verification
- **D-305-GREP-01:** First task of the IMPL plan re-verifies every cited file:line in 304-SPEC.md §5 against CURRENT working-tree HEAD per `feedback_verify_call_graph_against_source.md`. Phase 304 Plan 05 grep-verified all 61 citations at v43.0 baseline HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`; the working tree at Phase 305 start could have drifted (Phase 304 itself produced 5 SPEC-doc commits but zero source-tree mutations, so drift is structurally bounded — but verify, don't assume). If any line drifted, the planner updates the IMPL plan's per-mutation citation block before any source edit; the plan does NOT proceed to patching with stale line numbers. Mirrors Phase 304 Plan 05 + the `feedback_verify_call_graph_against_source.md` recurring-pattern guard.

### Test File Compile-break Handling
- **D-305-TESTBREAK-01:** Update existing test files inside Phase 305's batched diff to match new signatures. The two existing files referencing the old 2-arg `resolveRedemptionPeriod` + 0-arg `hasPendingRedemptions` — `test/fuzz/RedemptionGas.t.sol` + `test/fuzz/CoverageGap222.t.sol` — must compile under the post-refactor interface for `forge build` to PASS (success criterion #1). Defer-to-Phase-306 with `vm.skip` shims REJECTED: (a) `forge build` is the failure mode, not test execution, so `vm.skip` doesn't help; (b) the function-selector string at `CoverageGap222.t.sol:948` would still compile (string literal) but the assertion at `:973` then mis-detects the wrong-signature rejection. Update inline. Test edits AGENT-COMMITTED inside the same atomic commit per `feedback_no_contract_commits.md` clarified policy (mainnet `contracts/*.sol` need user approval; `test/` is autonomous within the same commit envelope). Mirrors `D-43N-TEST-COMMITS-AUTO-01` lineage.

### Approval & Commit Posture (carried forward)
- **D-305-APPROVAL-01:** All `contracts/` edits in this phase batched and presented as ONE diff at the end of the phase per `feedback_batch_contract_approval.md`. Explicit user approval before commit per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. ROADMAP's "Single batched USER-APPROVED contract commit" anchor for Phase 305 is satisfied by this discipline.
- **D-305-APPROVAL-02:** No history comments per `feedback_no_history_in_comments.md`. Header comment blocks above refactored functions describe the POST-refactor behavior as what IS; no "previously was" / "changed from" / "v43.0 used to". `_submitGamblingClaimFrom` header describes the per-day-keyed write semantics directly; `resolveRedemptionPeriod` header describes the `dayToResolve` arg + per-day mapping read + delete-at-resolve; `claimRedemption(uint32)` header describes the day-arg read + composite-key delete. Cross-references to INV-NN / SPEC-NN / EDGE-NN IDs are PERMITTED (informational anchors, not history).
- **D-305-APPROVAL-03:** Pre-launch frozen-at-deploy posture per `feedback_frozen_contracts_no_future_proofing.md`. No future-extensibility scaffolding; no migration prose in comments; no compatibility shim on the `resolveRedemptionPeriod` 2-arg → 3-arg or `hasPendingRedemptions` 0-arg → 1-arg signature changes; no `IStakedDegenerusStonkLegacy` interface; the v43→v44 break is the storage-layout break, NOT a public ABI migration story.
- **D-305-APPROVAL-04:** Manual diff review before push per `feedback_manual_review_before_push.md` + `feedback_wait_for_approval.md`. Plan execution presents the final diff to the user; user reviews and explicitly approves before the commit lands. No `git push` until separate approval.

### `dayToResolve` Derivation at AdvanceModule Call Sites
- **D-305-DAYTORESOLVE-01:** At each of the three AdvanceModule call sites (`:1230` rngGate, `:1293` gameOver-stale-VRF, `:1323` gameOver-fallback), `day` is the local in scope (function arg of `_advanceGame` at `:1216` and `_gameOverEntropy` at `:1267`). Pass `dayToResolve = day - 1` directly — this is the AdvanceModule-side equivalent of the SPEC-03-locked `currentDayView() - 1` (both expressions resolve to the same wall-clock value at the call site; `currentDayView()` IS `day` inside `_advanceGame`'s context). Identical expression at all three sites so a future grep on `dayToResolve = day - 1` enumerates all three call sites cleanly. The `hasPendingRedemptions(day - 1)` gate at `:1225`, `:1288`, `:1318` uses the same expression.

### Storage Slot Layout Posture
- **D-305-STORAGE-01:** The new `DayPending` struct + `mapping(uint32 => DayPending) internal pendingByDay` declarations land in the storage block roughly where the 5 deleted slots were (the `:224-231` region). Specific position: `pendingByDay` declaration immediately after `pendingRedemptionBurnie` at `:225` (the surviving cumulative scalar), replacing the 5-slot run at `:226-231`. The `DayPending` struct declaration sits alongside the existing `PendingRedemption` + `RedemptionPeriod` struct declarations (current location ~`:210-220`). Pre-launch posture means slot order is purely cosmetic; the reviewer-facing intent is to make the storage block read as "two cumulative scalars + one day-keyed mapping" rather than a sprinkle of removed slots with the new mapping appended at the contract tail.

### Claude's Discretion
- **Plan structure within single-plan shape** — D-305-PLAN-01 recommends single plan; if the planner finds a clean 2-plan split (e.g., P1 = pre-patch grep re-verification AGENT-COMMITTED state file, P2 = the batched USER-APPROVED contract+interface+test diff), that is acceptable provided P2's diff stays atomic. Default to single P1 with grep-verification as task 1.
- **Comment verbosity** — Header comment blocks for the four refactored functions (`_submitGamblingClaimFrom`, `hasPendingRedemptions`, `resolveRedemptionPeriod`, `claimRedemption`) plus the `DayPending` struct: planner picks length. Reference SPEC IDs (e.g., "writes per SPEC-01 + SPEC-05") permitted as anchors. Avoid restating INV proofs in source — those belong in SPEC.md + Phase 306 tests, not contract comments.
- **Local variable naming inside refactored bodies** — `currentDay` vs `today` for the `game.currentDayView()` read; `dayPool` vs `pool` for the storage-pointer alias to `pendingByDay[currentDay]`; etc. Planner picks; semantic locked.
- **Whether to introduce a `DayPending storage pool = pendingByDay[currentDay]` alias inside `_submitGamblingClaimFrom`** — gas-neutral / cosmetic. Planner decides based on readability; no SPEC requirement either way.
- **Test edit ordering inside the same commit** — whether contract edits, interface delta, and test fixups appear interleaved or grouped in the final diff is cosmetic. User reviews the diff as a whole; planner picks the presentation that minimizes review surface area.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, executor) MUST read these before planning or implementing.**

### Locked SPEC (load-bearing input)
- `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` — Phase 304 SPEC. §1 INV-01..12 + §2 SPEC-01..05 (with sub-locks a–d) + §2.7 7 deletions + §3 EDGE-01..18 + §4 design-intent + game-theory walks + §5 source-verified citation manifest (61 citations grep-verified at v43.0 closure HEAD). **MUST read before planning.**
- `.planning/REQUIREMENTS.md` — v44.0 block. IMPL-01..04 + their primary-delivery-phase mapping (all Phase 305). SPEC-01..05 status: Complete (commit `6edc3967`).
- `.planning/ROADMAP.md` §"Phase 305: Implementation (IMPL)" — Goal statement + 5 success criteria + Depends-on (Phase 304 SPEC).

### Contracts under change
- `contracts/StakedDegenerusStonk.sol` — Primary refactor target. Storage layout breaks accepted (pre-launch posture). Mutations enumerated in `<domain>` "In scope" above.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 3 call-site updates at `:1225+:1230`, `:1288+:1293`, `:1318+:1323`. Each site updates both `hasPendingRedemptions()` and `resolveRedemptionPeriod(...)` calls.
- `contracts/interfaces/IStakedDegenerusStonk.sol` — 2 signature updates at `:86` (`hasPendingRedemptions` 0-arg → 1-arg) and `:96` (`resolveRedemptionPeriod` 2-arg → 3-arg).

### Test files that compile-break (must update inside the batched diff)
- `test/fuzz/RedemptionGas.t.sol` — references old `resolveRedemptionPeriod` 2-arg at `:78`, `:94` and old `hasPendingRedemptions` 0-arg at `:127`, `:134`. Update inline; gas-benchmark intent preserved.
- `test/fuzz/CoverageGap222.t.sol` — references old function-selector string `"resolveRedemptionPeriod(uint16,uint32)"` at `:948`. Update to `"resolveRedemptionPeriod(uint16,uint32,uint32)"`.

### Audit findings cited by the refactor
- `audit/FINDINGS-v43.0.md` §9d — HANDOFF-111..117 register (the 7 sStonk catalog rows closed by v44.0). 304-SPEC §0 load-bearing input.
- `.planning/RNGLOCK-FIXREC.md` §103 — V-184 mechanic + game-theory walk (lines 5410-5520) + cross-day-boundary subtlety at line 5517. EDGE-07 verbatim reproduction reference.

### Memory / feedback governing this phase
- `feedback_security_over_gas.md` — security/RNG-non-manipulability is the hard floor; reject any gas optimization that weakens an invariant. SPEC §2.0 Priority Statement clause 3.
- `feedback_contract_locations.md` — only read contracts from `contracts/` directory; stale copies exist elsewhere.
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing.
- `feedback_manual_review_before_push.md` — never push contract changes without explicit user diff review.
- `feedback_no_contract_commits.md` — only mainnet `contracts/*.sol` hard-blocked; `test/` + `.planning/` + docs commit autonomously per the clarified policy (`D-43N-TEST-COMMITS-AUTO-01` lineage). Foundational for D-305-TESTBREAK-01.
- `feedback_contractaddresses_policy.md` — `ContractAddresses.sol` is modifiable; Phase 305 does not touch it (not in scope).
- `feedback_no_history_in_comments.md` — comments describe what IS, never what changed. D-305-APPROVAL-02.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved. D-305-APPROVAL-01.
- `feedback_batch_contract_approval.md` — batch all contract edits in a phase, present one diff, get one approval at the end. D-305-APPROVAL-01.
- `feedback_design_intent_before_deletion.md` — design-intent + actor game-theory traced BEFORE deletion. Already executed at Phase 304 §4 for all 7 deletions; Phase 305 IMPL consumes the locked decisions; no re-trace required.
- `feedback_frozen_contracts_no_future_proofing.md` — pre-launch frozen-at-deploy; no migration scaffolding; no compatibility shims. D-305-APPROVAL-03.
- `feedback_rng_backward_trace.md` — every RNG audit must trace backward. Already executed inline at SPEC §1 INV-06 + INV-07 + at EDGE-06 negative assertion. Phase 305 IMPL does not change RNG inputs (the `roll` derivation at AdvanceModule `:1226-1228` / `:1289-1291` / `:1319-1321` is BYTE-IDENTICAL — only the third arg gets appended to the resolver call); Phase 307 SWEEP will re-trace if any RNG-input change leaks in.
- `feedback_rng_commitment_window.md` — Phase 305 introduces NO new player-controllable state inside the RNG-derivation window; the per-day refactor moves state from `redemptionPeriodIndex` (a writer's-perspective slot) to `pendingByDay[day]` (a wall-clock-keyed slot), and the writer's day is set by the AdvanceModule (`day - 1`), not by a player-controllable input. Phase 307 SWEEP `/contract-auditor` re-verifies.
- `feedback_rng_window_storage_read_freshness.md` — Phase 305 does not add new SLOADs inside the RNG-derivation window of the AdvanceModule writer (`_applyDailyRng` body at `:1216`). The new `hasPendingRedemptions(day - 1)` call at `:1225` reads the `pendingByDay[day-1]` slot — but this read happens AFTER `_applyDailyRng` returns `currentWord`, NOT inside the RNG-derivation window. The relative ordering is preserved from v43 (the v43 `hasPendingRedemptions()` call at `:1225` was also post-`_applyDailyRng`). Phase 307 SWEEP `/contract-auditor` re-verifies the F-41-02/03 class of bugs is not reintroduced.
- `feedback_verify_call_graph_against_source.md` — planning "by construction" / "single fn reaches all paths" claims must be grep-verified against source pre-patch. D-305-GREP-01.
- `feedback_skeptic_pass_before_catastrophe.md` — Phase 307 SWEEP discipline; Phase 305 IMPL does not produce findings (it produces source mutations).
- `feedback_skip_research_test_phases.md` — skip research for obvious/mechanical phases. D-305-RESEARCH-01.
- `feedback_gas_worst_case.md` — Phase 306 TST-06 derives worst case FIRST then tests. Phase 305 IMPL ships the refactor without gas bench; the SPEC §2.0 soft target is `+5% burn / +0% claim` and is aspirational, not a Phase 305 deliverable.

### Prior-phase context
- `.planning/phases/304-spec-invariant-model-spec/304-VERIFICATION.md` — Phase 304 closure verification (5/5 plans shipped; SPEC.md 960 lines; 35 requirements covered).
- `.planning/phases/304-spec-invariant-model-spec/304-0[1-5]-SUMMARY.md` — Phase 304 per-plan summaries (Plan 01 INV model, Plan 02 SPEC locks, Plan 03 EDGE enumeration, Plan 04 design-intent walks, Plan 05 citation manifest).
- `.planning/milestones/v42.0-phases/29[0-7]-*/29[0-7]-CONTEXT.md` — recent IMPL/refactor phase precedents for atomic-diff posture (esp. Phase 290 mint-batch event/sig cleanup, Phase 292 hero-override weighted roll, Phase 294 deity-pass gold nerf, Phase 297 v42.0 TERMINAL).
- `.planning/milestones/v35.0-phases/263-per-pull-level-resample-implementation/263-CONTEXT.md` — single-plan IMPL precedent (D-PLAN-01 = "Defer plan slicing to planner; reference shape: single plan with all changes in one commit").

### Milestone & state
- `.planning/PROJECT.md` — v44.0 milestone goal anchor + v43.0 audit baseline HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2`.
- `.planning/STATE.md` — current focus (planning Phase 305).
- `KNOWN-ISSUES.md` — UNMODIFIED at v44.0 close per `D-44N-KI-01`. Phase 305 IMPL does NOT touch KNOWN-ISSUES.md (Phase 308 TERMINAL §6 re-verifies EXC-01..04 RE_VERIFIED-NEGATIVE-scope without modification).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_payEth` + `_payBurnie` flows** (`StakedDegenerusStonk.sol:649-674` region) — UNCHANGED. SPEC-02 + SPEC-04 (d) preserve the partial-claim branch verbatim; the only delta at `claimRedemption` is the `(player)` → `(player, day)` storage key and the `delete pendingRedemptions[msg.sender][day]` site at the full-claim path.
- **`game.currentDayView()` external call** (`StakedDegenerusStonk.sol:32` interface + `:757` consumer) — UNCHANGED. The `IDegenerusGamePlayer.currentDayView()` interface method at `:32` is the only currentDayView reader inside sStonk; SPEC-05 replaces the `redemptionPeriodIndex != currentPeriod` predicate with the SPEC-05 lazy-init predicate, but `currentDayView()` itself is unchanged.
- **`coinflip.getCoinflipDayResult(period.flipDay)` external call** (`:649-654`) — UNCHANGED. SPEC-04 (d) preserves the partial-claim branch verbatim under composite keying.
- **`game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` external call** (`:672`) — UNCHANGED. SPEC-04 (a) preserves the existing `:638-643` 50/50 split + lootbox routing.
- **`RedemptionPeriod` struct** (`:215-218` region, current source has `roll` + `flipDay` fields) — UNCHANGED. SPEC-02 + SPEC-03 do not re-key this struct; the outer `mapping(uint32 => RedemptionPeriod) public redemptionPeriods` at `:222` is structurally unchanged (already per-day-keyed; v43 used `redemptionPeriodIndex` to index it indirectly, v44 indexes it directly via the explicit `dayToResolve` arg).
- **`pendingRedemptionEthValue` + `pendingRedemptionBurnie` cumulative scalars** (`:224` + `:225`) — UNCHANGED. SPEC-01 explicitly preserves both as the cumulative-sum invariants (INV-02 ETH conservation + INV-03 BURNIE conservation reference these).

### Established Patterns
- **Per-id keyed commitment pattern** — the existing lootbox + coinflip flows already use this pattern (e.g., `lootboxRngWordByIndex[index]` + per-coinflip-day keying). SPEC-01's `pendingByDay[uint32]` follows the same shape; the planner can lean on familiar reviewer mental model for the new mapping declaration.
- **Composite-key mapping pattern** — `mapping(address => mapping(uint32 => X))` is already used elsewhere in the codebase for `(player, day)` composite scoping (the planner may grep for analogous declarations to confirm the canonical syntax). The Solidity 0.8.34 syntax for both declaration and access (`pendingRedemptions[msg.sender][day]`) is unambiguous.
- **`delete` for storage refund** — already used at `:661` for `delete pendingRedemptions[player]` (under v43 single-key shape). SPEC-04 (c) + (d) introduce two new `delete` sites: `delete pendingByDay[dayToResolve]` inside `resolveRedemptionPeriod` after the write + emit; `delete pendingRedemptions[msg.sender][day]` inside `claimRedemption` after payout + emit. The pattern is reviewer-familiar.
- **Early-return guard** — pre-refactor `:589` `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;` is preserved per SPEC-04 (c) rationale text, just re-keyed to `if (pendingByDay[dayToResolve].ethBase == 0 && pendingByDay[dayToResolve].burnieBase == 0) return;`.
- **Header comment block style** — existing function header comments (e.g., `:478-480` `previewBurn`, `:526-528` `_payEth` doc-block region) describe POST-state behavior with `///` natspec; Phase 305 headers follow the same style with SPEC-NN / INV-NN / EDGE-NN cross-references where useful.

### Integration Points
- **AdvanceModule `_advanceGame` (`:1216-1235` region)** — the rngGate primary path; calls the sStonk resolver after `_applyDailyRng` returns. `day` local at `:1191` is the wall-clock day; `day - 1` is the SPEC-03-locked `dayToResolve`. The `hasPendingRedemptions(day - 1)` gate replaces the v43 `hasPendingRedemptions()` zero-arg form; both reads execute at the same source location.
- **AdvanceModule `_gameOverEntropy` stale-VRF path (`:1273-1297` region)** — the secondary advance path; `day` arg of `_gameOverEntropy` is the wall-clock day; same `day - 1` derivation.
- **AdvanceModule `_gameOverEntropy` fallback-VRF path (`:1302-1325` region)** — the tertiary advance path; same `day - 1` derivation.
- **AdvanceModule `:1772` documentation comment** — `"resolveRedemptionPeriod is NOT called for backfilled gap days"` — UNCHANGED. The backfill path (`_backfillGapDays` at `:1203`) does not call `resolveRedemptionPeriod`, so the per-day refactor does not affect gap-day behavior. SPEC-03 + INV-09 (skipped-advance recovery) preserve oldest-first ordering for the post-backfill catch-up; the backfill itself does not advance the redemption resolver, so gap days never have a redemption pool to resolve.
- **Test file `test/fuzz/RedemptionGas.t.sol`** — calls `sdgnrs.resolveRedemptionPeriod(100, currentDay)` (2-arg) + `sdgnrs.hasPendingRedemptions()` (0-arg). Both updates inline per D-305-TESTBREAK-01.
- **Test file `test/fuzz/CoverageGap222.t.sol:948`** — function-selector string for ACL-rejection test; selector text updates to 3-arg form.

</code_context>

<deferred>
## Deferred Ideas

- **New Foundry coverage** (`test/fuzz/StakedStonkRedemption.t.sol` + `test/invariant/RedemptionAccounting.t.sol` + `test/fuzz/RedemptionEdgeCases.t.sol`) — Phase 306 TST. EDGE-01..18 mechanized one fuzz function per scenario; INV-01..12 mechanized as `invariant_*` functions. 10k runs per case under `FOUNDRY_PROFILE=deep`.
- **TST-05 vm.skip flip** — `test/fuzz/RngLockDeterminism.t.sol` HANDOFF-111..117 `vm.skip(true)` removal + strict byte-identity assertion. Phase 306 TST. The 7 previously-skipped cases (the V-184 mechanic demonstrations at v43.0 HEAD) must PASS at v44.0 close — the load-bearing closure assertion.
- **Gas regression bench (`burn ≤ +5% v43 / claim ≤ +0% v43`)** — TST-06 Phase 306. Worst case derived FIRST per `feedback_gas_worst_case.md`, then tested.
- **3-skill adversarial sweep** (`/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` PARALLEL_SUBAGENT + `/economic-analyst` PARALLEL_SUBAGENT) — Phase 307 SWEEP per `D-302-INVOKE-01` precedent. Pre-authorized per `D-44N-SWEEP-PREAUTH-01`. Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` BEFORE any Tier-1 user-pause.
- **9-section TERMINAL** (`audit/FINDINGS-v44.0.md`) — Phase 308. AUDIT-01..09 + REG-01 + CLS-01..02. 2-commit sequential SHA orchestration per `D-44N-CLOSURE-01`.
- **135 v43 backlog anchors** — v45.0+ per `audit/FINDINGS-v43.0.md` §9d handoff register (119 D-43N-V44-HANDOFF-NN + 22 D-43N-V44-ADMA-NN + 1 D-43N-V44-ADMA-ERRATUM-01 + carry-forward items per `.planning/REQUIREMENTS.md` Future Requirements).
- **Mint-boost fractional retirement** + **LBX-02 fixture-coverage gap** + **MINTCLN helper-extraction handoff** + **EVT-BREAK indexer-migration handoff** + **Game-over thorough hardening** + **retryLootboxRng launch-comms/docstring items** + **Phase 302 SWEEP coverage-gap** (3 missing FUZZ edge-case functions) — all v45.0+ per REQUIREMENTS.md Future Requirements.
- **`claimMultipleRedemptions` batch helper** — REJECTED in REQUIREMENTS.md Out-of-Scope table. Players call `claimRedemption(day)` N times for stacked claims; immediate-claim UX assumed.

</deferred>

---

*Phase: 305-implementation-impl*
*Context gathered: 2026-05-19*
