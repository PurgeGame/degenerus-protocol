---
phase: 311-spec-vrf-rotation-liveness-fix-spec
plan: 02
subsystem: audit
tags: [vrf-rotation, spec, freeze-invariant, lootbox-rng, design-intent-trace, re-issue-in-flight, wirevrf-lock]

# Dependency graph
requires:
  - phase: 311-01
    provides: "the §0 grep-verified call-graph manifest (§0.A–§0.Y) every §1–§7 design assertion cites — incl. the §0.X §9d→D-01..D-05 map and the §0.Y DegenerusAdmin/DegenerusGame vault-reach trace"
provides:
  - "311-SPEC.md §1–§7 — the complete VRF-rotation fix DESIGN: §1 design-intent backward-trace (Scenario A entropy-0 + Scenario B ~120d freeze), §2 LOCKED re-issue-in-flight fix shape (D-01/D-02) closing VRF-01/VRF-02, §3 freeze-invariant disposition (VRF-03) with validator-influenceable backfill rejected, §4 wireVrf one-shot lock + _setVrfConfig dedup + vault reach (D-03/D-04/VRF-04/VRF-05), §5 D-05 orphan-recovery reachability CONFIRMED-COVERED + escalation gate, §6 rejected options, §7 self-check"
  - "The single load-bearing SPEC input that drives Phase 312 IMPL (the re-issue mechanic, the wired-detection choice, the _setVrfConfig signature/visibility)"
affects: [312-IMPL (implements the locked design; re-grep-verifies against HEAD pre-patch), 313-TST (orphan-index reproduction + liveness-after-rotation + freeze fuzz target the §2/§3/§5 design elements), 314-SWEEP, 315-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Manifest-cited design prose: every §1–§7 call-path/line claim references a §0 row (no by-construction claims) per feedback_verify_call_graph_against_source"
    - "Decision-anchor carry (D-01..D-05) refined-not-reversed; the only sanctioned reversal (D-05 escalation) evaluated and explicitly NOT triggered"
    - "Structural mitigation over runtime guard (MintModule:686 zero-guard absence mitigated by always-filled index, not a new == 0 check)"

key-files:
  created: []
  modified:
    - .planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md

key-decisions:
  - "D-03 wired-detection: chose the no-new-slot check address(vrfCoordinator) != address(0) — §0.Y confirms the ONLY routed wireVrf reach is the single :458 constructor call, so no legitimate re-wire-before-first-request init flow exists; a dedicated vrfWired bool rejected as redundant per feedback_maximal_variable_packing"
  - "D-04 _setVrfConfig collapses ONLY the 3-field config write (:506-508 / :1696-1698); wireVrf's :509 lastVrfProcessedTimestamp stays inline (wireVrf-specific, absent from updateVrfCoordinatorAndSub) so the dedup does not move wireVrf-only behavior into the rotation path"
  - "D-05 orphan-recovery: CONCLUSION CONFIRMED-COVERED — re-issue's :1772 direct fill covers the in-flight index; :1208 backfill (reachable once :269/:271 un-blocks) + the :1817 backward scan over [1..LR_INDEX-1] cover any earlier residual; :1048 caps orphans at ≤1/rotation; escalation NOT triggered, D-05 stays NARROW"
  - "VRF-05 disposition: D-03 lock + D-01/D-02 safe-rotation sit at the delegatecall targets (:498/:1688) downstream of every Admin wrapper + Game selector-router; no DegenerusVault-routed bypass exists (§0.Y), so all routed reach is covered"
  - "§3 VRF-03: re-issue is freeze-safe (old word abandoned by the :1761 requestId guard, new word unpredictable, admin rotation EXEMPT-class vs PLAYERS); validator/timestamp/newKeyHash-influenceable entropy backfill EXPLICITLY REJECTED per feedback_security_over_gas — only keccak-of-a-real-VRF-word (:1817) sanctioned"

patterns-established:
  - "SPEC §7 self-check enumerates the six locked-decision/requirement obligations (§0-anchor tracing, D-05 confirmed-or-escalated, validator backfill rejected, D-01..05 carried forward, VRF-01..05 mapped, zero contract/test mutations) as a discrete checkable close"

requirements-completed: [VRF-01, VRF-02, VRF-03, VRF-04, VRF-05]

# Metrics
duration: 14min
completed: 2026-05-22
---

# Phase 311 Plan 02: VRF-Rotation Fix Design Narrative (§1–§7) Summary

**Authored the complete VRF-rotation fix DESIGN in `311-SPEC.md` §1–§7 — the design-intent backward-trace across both orphan scenarios, the LOCKED re-issue-in-flight fix shape (D-01/D-02) closing VRF-01/VRF-02, the freeze-invariant disposition (VRF-03) with validator-influenceable backfill rejected, the wireVrf one-shot lock + `_setVrfConfig` dedup + vault-routed reach (D-03/D-04/VRF-04/VRF-05), the D-05 orphan-recovery reachability trace (CONFIRMED-COVERED, escalation not triggered), and the rejected-options record — every assertion cited to a Plan-01 §0 manifest row, zero by-construction claims, zero contract/test mutations.**

## Performance

- **Duration:** ~14 min
- **Completed:** 2026-05-22
- **Tasks:** 2
- **Files modified:** 1 (`311-SPEC.md`, §1–§7 placeholders → authored; 277 → 718 lines, +441)

## Accomplishments

- **§1 Design-Intent Backward-Trace** — traced the original intent of `wireVrf` (§0.A `:498`; §0.Y single `:458` constructor reach) and `updateVrfCoordinatorAndSub` (§0.A `:1688`; §0.Y `:901` `_executeSwap` reach), then walked both orphan combos: Scenario A (same-day advance — `:1709` clears `LR_MID_DAY` so the `:209`/`:213` guard is skipped → `MintModule:686` reads orphaned `[N]==0` with no zero-guard → entropy-0 traits, HIGH) and Scenario B (next-day — `:269`/`:271` `RngNotReady()` revert before the `:1202` gap branch can reach the `:1208` backfill → ~120d freeze). Included the EXEMPT-class actor note (`v45-vrf-freeze-invariant`) and the maximalist-catalog framing (`project_rnglock_audit_disposition`).
- **§2 LOCKED Fix Shape (D-01/D-02)** — re-issue the in-flight request on the new coordinator, mirroring the existing `retryLootboxRng` re-issue precedent (§0.A `:1133`; §0.E call site #2 `:1143`, fresh `vrfRequestId`/`rngRequestTime` at `:1154-1155`); preserve+re-issue for daily (keep `rngLockedFlag=true` → `:1768` `rngWordCurrent`) and mid-day (keep `LR_MID_DAY=1` → `:1772` `lootboxRngWordByIndex[N]`); nothing-in-flight re-point-only. Closes VRF-01 (real word lands in `[N]`, old word abandoned by the `:1761` guard) and VRF-02 (`requestLootboxRng`/`retryLootboxRng`/daily-drain stay reachable; retry remains the ≥`MIDDAY_RNG_RETRY_TIMEOUT` failsafe). `totalFlipReversals` carry-over (§0.A `:1711-1714`) explicitly preserved.
- **§3 Freeze-Invariant Disposition (VRF-03)** — enumerated all VRF-participating slots (§0.C `:1287`/`:1295`/`:1291`/`:244`/`:373`/`:1328-1329`/`:1431` + `LR_INDEX`); showed no consumed-this-cycle output changes (old word abandoned, new word unpredictable, admin rotation EXEMPT vs PLAYERS); EXPLICITLY REJECTED validator/timestamp/newKeyHash-influenceable backfill per `feedback_security_over_gas`, sanctioning only keccak-of-a-real-VRF-word (§0.A `:1817`/`:1826`); `MintModule:686` zero-guard absence mitigated STRUCTURALLY (always-filled index), not by a new guard.
- **§4 wireVrf Lock + Dedup + Vault Reach (VRF-04/VRF-05)** — D-03 one-shot lock with the chosen no-new-slot detection `address(vrfCoordinator) != address(0)` (justified by §0.Y: only the single `:458` constructor call reaches `wireVrf`, no re-wire init flow); D-04 `_setVrfConfig(coord, sub, key)` internal helper collapsing the 3-field write (§0.A `:506-508` / `:1696-1698`; §0.C dual-writer rows) with `:509` `lastVrfProcessedTimestamp` left inline, grounded in the Phase 310 D-01/D-02 single-source-of-truth precedent; VRF-05 disposition — guards sit at the delegatecall targets downstream of all wrappers (§0.Y), no `DegenerusVault`-routed bypass.
- **§5 Orphan-Recovery Breadth (D-05)** — traced re-issue → drain-gate un-block (`:269`/`:271`) → restored `:1208` backfill reachability (gated branch `:1193`/`:1202`); stated the `≤1`-orphan bound (§0.A `:1048`); the `:1817` backward scan (`:1822-1829`) covers `[1..LR_INDEX-1]`; **CONCLUSION: CONFIRMED-COVERED**, escalation clause evaluated and NOT triggered, D-05 stays NARROW.
- **§6 Rejected Options** — queue+apply `pendingVrfRotationPacked` REJECTED (old coordinator dead → in-flight word never resolves → recovery-latency, sacrifices liveness; the §9d HANDOFF-78 tactic per §0.X); belt-and-suspenders gate-independent backfill DEFERRED (redundant given §5 CONFIRMED-COVERED; the standing fallback the escalation clause would have invoked).
- **§7 SPEC Self-Check** — asserted all six obligations (every anchor traces to a §0 row / zero by-construction; D-05 confirmed-or-escalated; validator backfill rejected; D-01..D-05 carried forward without silent reversal; VRF-01..05 each mapped to a closing section; zero contract/test mutations).

## Task Commits

Each task was committed atomically (force-added — `.planning/` is gitignored):

1. **Task 1: §1 backward-trace + §2 locked fix shape + §3 freeze disposition** — `d27e8afd` (docs)
2. **Task 2: §4 wireVrf lock + dedup + vault reach, §5 orphan-recovery + escalation gate, §6 rejected options, §7 self-check** — `b2c9ab2c` (docs)

_The plan-metadata commit (STATE/ROADMAP/REQUIREMENTS + this SUMMARY) lands as the final metadata commit below._

## Files Created/Modified

- `.planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` — §1–§7 authored (replacing the Plan-01 placeholders): §1 backward-trace, §2 re-issue-in-flight fix shape, §3 freeze disposition, §4 wireVrf lock + `_setVrfConfig` dedup + vault reach, §5 D-05 reachability + escalation gate, §6 rejected options, §7 self-check. 277 → 718 lines.

## Decisions Made

- **D-03 wired-detection = `address(vrfCoordinator) != address(0)` (no new slot).** §0.Y proves the only routed `wireVrf` reach is the single `DegenerusAdmin.sol:458` constructor call (after `createSubscription()`), so there is no legitimate re-wire-before-first-request init flow that would force a dedicated `vrfWired` bool. The no-new-slot check permits exactly one call (when `vrfCoordinator == address(0)`) and reverts every subsequent call — consistent with `feedback_maximal_variable_packing`.
- **D-04 `_setVrfConfig` collapses ONLY the 3-field config write.** `wireVrf`'s `:509` `lastVrfProcessedTimestamp` write is wireVrf-specific (absent from `updateVrfCoordinatorAndSub`) and stays inline, so the dedup does not silently relocate wireVrf-only behavior into the rotation path. `internal` visibility matches the Phase 310 D-01/D-02 single-source-of-truth precedent. Recorded as TO-BE-CREATED (§0.D) — created at Phase 312, never treated as an existing node.
- **D-05 CONCLUSION: CONFIRMED-COVERED (escalation NOT triggered).** The in-flight index is filled directly by re-issue (`:1772`); any earlier residual zero index is covered by the `:1208` backfill's `:1817` backward scan over `[1..LR_INDEX-1]` (reachable once `:269`/`:271` un-blocks); the `:1048` gate bounds orphans at ≤1/rotation. No residual orphan path exists → D-05 stays NARROW, no new backfill wiring added.
- **VRF-05 covered by guard placement at the delegatecall targets.** D-03 lock at the `wireVrf` impl (`:498`) and D-01/D-02 safe-rotation at the `updateVrfCoordinatorAndSub` impl (`:1688`) sit downstream of every Admin wrapper + Game selector-router (§0.Y), so no wrapper can bypass them; there is no `DegenerusVault`-routed dispatch to either function.
- **§3 entropy source: keccak-of-a-real-VRF-word ONLY.** Validator/timestamp/`newKeyHash`/blockhash/caller-supplied entropy explicitly rejected per `feedback_security_over_gas`; the only sanctioned backfill source is the existing `:1817` `keccak256(abi.encodePacked(vrfWord, i))` pattern (VRF-seeded, not front-runnable). Re-issue's primary mechanic does not backfill at all — it lands a genuine VRF word in `[N]` directly.

## Deviations from Plan

None — plan executed exactly as written. No deviation rules fired: no bugs, no missing critical functionality, no blocking issues, no architectural changes. This is a read-only design-document phase (the only file written is `311-SPEC.md`; all contract reads were read-only from `contracts/` per `feedback_contract_locations`).

The D-05 escalation clause (the ONLY sanctioned locked-decision reversal) was explicitly evaluated in §5.3 and **not** triggered — the reachability trace found no residual orphan path that re-issue + the `:1208` backfill do not cover, so D-05 stays NARROW as locked. This is the planned outcome, not a deviation.

## Issues Encountered

None blocking. One precision point surfaced during source re-confirmation and was handled in §4.2: the Plan-01 §0.A `wireVrf` row summarizes the config writes at `:506-508`, but `wireVrf` also writes `lastVrfProcessedTimestamp` at `:509` (a 4th, wireVrf-specific write absent from `updateVrfCoordinatorAndSub:1696-1698`). §4.2 explicitly scopes `_setVrfConfig` to the 3 shared config slots and keeps `:509` inline in `wireVrf`, so the D-04 dedup is precise and does not move wireVrf-only behavior into the rotation path. No §0 fact changed; this is a refinement of where the dedup boundary sits.

## User Setup Required

None — no external service configuration. This is a design-document (SPEC) phase: zero `contracts/` and zero `test/` mutations. The contract changes the SPEC designs land at Phase 312 IMPL as a single batched USER-APPROVED diff per the milestone posture.

## Next Phase Readiness

- `311-SPEC.md` is COMPLETE (§0 manifest + §1–§7 design narrative). It is the single load-bearing input for **Phase 312 IMPL**, which implements: the re-issue mechanic in `updateVrfCoordinatorAndSub` (preserve+re-issue both paths, mirroring `retryLootboxRng`), the `wireVrf` one-shot lock (`address(vrfCoordinator) != address(0)` revert), and the `_setVrfConfig(coord, sub, key)` internal helper (3-field write; `:509` stays inline).
- `_setVrfConfig` is flagged TO-BE-CREATED (§0.D) — Phase 312 creates it.
- Phase 312 should re-grep-verify against HEAD pre-patch (the §0 manifest is verified at `3153149a`; re-confirm the ADMA-02 `:1677`→`:1688` drift and the no-DegenerusVault-dispatch fact still hold).
- **Phase 313 TST** targets the §2/§3/§5 design elements: orphan-index reproduction (pre-fix entropy-0 → post-fix real word in `[N]`), liveness-after-rotation (`requestLootboxRng`/`retryLootboxRng`/daily-drain reachable), rotation-perturbation freeze fuzz (byte-identical VRF-derived output), and the `wireVrf` one-shot lock.
- No blockers. Tree is clean (`git diff --quiet -- contracts/ test/` returns no output).

## Self-Check: PASSED

- **Modified file exists + complete:** `FOUND` `311-SPEC.md` (718 lines); zero `authored in Plan 02` placeholders remain (grep count 0); `CONFIRMED-COVERED` present (3 occurrences).
- **Task commits exist:** `FOUND: d27e8afd` (§1–§3) · `FOUND: b2c9ab2c` (§4–§7) — both confirmed via `git log --oneline --all`.
- **Clean-tree invariant:** `git diff --quiet -- contracts/ test/` returns no output (zero source/test mutations) — re-verified at both task commits and after the final edit.
- **Requirement closure:** VRF-01 (§2.2/§2.3), VRF-02 (§2.3/§5.1), VRF-03 (§3), VRF-04 (§4.1/§4.2), VRF-05 (§4.3) each mapped to a named section in the §7 self-check.
- **Decision integrity:** D-01..D-05 carried forward without silent reversal; the only sanctioned reversal (D-05 escalation) evaluated and explicitly NOT invoked; `totalFlipReversals` carry-over preserved.

---
*Phase: 311-spec-vrf-rotation-liveness-fix-spec*
*Completed: 2026-05-22*
