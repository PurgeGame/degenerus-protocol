# Phase 311: SPEC — VRF-Rotation Liveness Fix - Context

**Gathered:** 2026-05-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Lock the DESIGN (not code) for how emergency VRF rotation handles an in-flight mid-day lootbox request, closing the CONFIRMED CATASTROPHE-class orphan-index liveness defect in `updateVrfCoordinatorAndSub` plus the §9d governance-VRF freeze cluster it overlaps. Output is `.planning/phases/311-*/311-SPEC.md`: a design-intent backward-trace across both orphan scenarios, the locked fix shape, the freeze-invariant disposition, the `wireVrf` lock, and a grep-verified call-graph manifest. **Zero `contracts/` and zero `test/` mutations this phase** — the fix lands at Phase 312 (single batched USER-APPROVED diff), regression at 313.

**Root cause (verified against HEAD 2026-05-22):** `updateVrfCoordinatorAndSub` (`AdvanceModule:1688`) repoints config then unconditionally force-sets `rngLockedFlag=false` + zeroes `vrfRequestId`/`rngRequestTime`/`rngWordCurrent` (`:1701-1704`) + clears `LR_MID_DAY=0` (`:1709`), but never re-requests or backfills `lootboxRngWordByIndex[N]`. Scenario A (same-day advance): `MintModule:686` reads that index with NO zero-guard → entropy-0 deterministic traits. Scenario B (next-day): the drain gate reverts (`:269`/`:238`) before reaching the existing `_backfillOrphanedLootboxIndices` call at `:1208` → ~120-day freeze + forced game-over.

**Maps to:** VRF-01..05 (REQUIREMENTS.md) + §9d cluster HANDOFF-78/85/87/89/91 (freeze) + 86/88/90 + ADMA-01 (wireVrf lock) + ADMA-02 (vault reach).

</domain>

<decisions>
## Implementation Decisions

> These four decisions are the locked INPUTS to the 311 SPEC. The SPEC performs the rigorous design-intent backward-trace per `feedback_design_intent_before_deletion` and grep-verifies every cited line per `feedback_verify_call_graph_against_source` before locking; it must not silently reverse a decision below, only refine the mechanics or escalate with explicit rationale.

### Fix shape — re-issue in-flight (Area 1)
- **D-01 (re-issue on the new coordinator):** When `updateVrfCoordinatorAndSub` fires with a VRF request pending, re-fire the request on the NEW coordinator for the same index — set fresh `vrfRequestId`/`rngRequestTime`, preserve the in-flight flag — so the existing `rawFulfillRandomWords` path fills the slot when the new coordinator delivers. `retryLootboxRng` (`:1133`, ≥6h cooldown) stays as the failsafe. Rejected alternative: **queue+apply split** (`pendingVrfRotationPacked`) — cleaner "zero mid-window config mutation" narrative but two-step UX and ADDS recovery latency (the old coordinator is dead, so the in-flight word never resolves; you'd wait the full timeout before recovery). Re-issue is freeze-safe: the old request's word is abandoned (`requestId != vrfRequestId` rejects its callback) and the new word is unpredictable; admin rotation is an EXEMPT-class operation, not a player-discretionary write, and the §9d governance rows are maximalist-catalog entries (per `project_rnglock_audit_disposition`), not live player vectors.

### Rotation unlock policy — surgical preserve+re-issue (Area 2)
- **D-02 (drop the unconditional force-unlock; preserve+re-issue both paths):** Rotation detects what is in flight and preserves that flag while re-issuing on the new coordinator:
  - **Daily** (`rngLockedFlag == true`): keep `rngLockedFlag=true`, re-request the daily word (flows through the `rawFulfillRandomWords` daily branch → `rngWordCurrent`).
  - **Mid-day** (`LR_MID_DAY == 1`): keep `LR_MID_DAY=1`, re-request for the reserved index (flows through the mid-day branch → `lootboxRngWordByIndex[index]`).
  - **Nothing in flight:** just re-point config — no re-issue, no flag change.
  Uniform "rotation re-issues whatever was pending." Eliminates the Scenario-A entropy-0 path AND the edge case where a just-delivered-but-unprocessed word gets zeroed by the current blanket reset. Note the daily path self-heals under the *current* force-unlock too — the uniform treatment is the chosen design for a single coherent rotation behavior, not because the daily path is independently broken.

### wireVrf lock + dedup (Area 3)
- **D-03 (wireVrf init-only lock):** `wireVrf` (`:498`) reverts once VRF is wired; `updateVrfCoordinatorAndSub` becomes the SOLE post-init VRF-config mutator (now safe via D-01/D-02). Closes HANDOFF-86/88/90 + ADMA-01. Detection mechanism (a `vrfWired` bool vs. `address(vrfCoordinator) != address(0)`) is SPEC discretion — prefer the no-new-slot check unless it conflicts with a legitimate re-wire-before-first-request init flow.
- **D-04 (dedup into a shared internal):** Both `wireVrf` and `updateVrfCoordinatorAndSub` route their 3-field config write through one `internal` `_setVrfConfig(coord, sub, key)` helper — single-source-of-truth, matching the Phase 310 D-01/D-02 precedent (consolidate shared logic into the base; avoid the inline-duplication drift bug class per `feedback_verify_call_graph_against_source`).

### Orphan-recovery breadth — narrow + verify (Area 4)
- **D-05 (narrow fix; SPEC verifies gate-reachability is restored):** Do NOT add new backfill wiring. Re-issue (D-01) fills the single in-flight index AND un-blocks the drain gate (`:269`/`:238`), which restores reachability of the EXISTING `_backfillOrphanedLootboxIndices` (`:1208`, VRF-derived `keccak(word,i)`, not front-runnable) for any residual orphans. The `LR_MID_DAY` single-in-flight gate (`:1048`) means at most one orphaned index per rotation, and repeated rotations re-cover the same index. **SPEC obligation:** explicitly trace and confirm that re-issue restores the `:1208` backfill path so the helper is not left stranded. If the trace finds a residual orphan path that re-issue + `:1208` do not cover, escalate to the rejected belt-and-suspenders option (gate-independent backfill / dedicated recovery entry point) with rationale.

### Claude's Discretion
- Exact re-issue mechanics: how `requestRandomWords` is called on the new coordinator, `rngRequestTime = block.timestamp` for the liveness/timeout machinery, and the daily-vs-mid-day branch structure inside `updateVrfCoordinatorAndSub`.
- The `wireVrf` wired-detection mechanism (D-03) and the exact signature/visibility of `_setVrfConfig` (D-04).
- **Preserve existing behavior:** `totalFlipReversals` is NOT reset on rotation (the `:1711-1714` carry-over comment) — re-issue must keep this; nudges purchased with burned BURNIE apply to the first post-rotation daily word.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### v45.0 milestone scope (read first)
- `.planning/ROADMAP.md` §Phase 311 — the SPEC scope statement + 5 success criteria + §9d-anchor→closing-change mapping.
- `.planning/REQUIREMENTS.md` — VRF-01..05 (the requirements this milestone delivers), the fix-shape directive, posture, and Out-of-Scope (V-081 rides on delta-audit; ~115 non-VRF backlog anchors deferred).
- `.planning/PROJECT.md` ## Current Milestone — consolidate-forward framing, headline-finding writeup, audit baseline → subject.
- `.planning/STATE.md` — baseline `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`.
- `.planning/phases/310-*/310-CONTEXT.md` — the D-01/D-02 single-source-of-truth precedent that grounds D-04 here.

### §9d VRF-cluster source (the anchors this fix closes)
- `audit/FINDINGS-v44.0.md` §9d.2 — HANDOFF-78 (V-137, "split updateVrfCoordinatorAndSub into queue+apply" — the rejected tactic; closes 78/85/87/89/91), HANDOFF-84 (V-153 RECLASSIFIED), HANDOFF-86 (V-156 wireVrf one-shot lock, closes 86/88/90).
- `audit/FINDINGS-v44.0.md` §9d.4 — ADMA-01 (`wireVrf` seal) + ADMA-02 (`updateVrfCoordinatorAndSub` vault-routed reach, `DegenerusVault`).
- `.planning/RNGLOCK-FIXREC.md` + `.planning/RNGLOCK-CATALOG.md` + `.planning/ADMIN-AUDIT.md` — upstream per-VIOLATION detail for the cluster (consult only as needed; the §9d roll-up is the load-bearing summary).

### Contract HEAD sites (re-grep-verify pre-SPEC per `feedback_verify_call_graph_against_source`)
- `contracts/modules/DegenerusGameAdvanceModule.sol:498` — `wireVrf` (D-03/D-04 init-only lock + shared write).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1044` — `requestLootboxRng` (`:1048` LR_MID_DAY single-in-flight gate; `:1097` sets LR_MID_DAY=1).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1133` — `retryLootboxRng` (`:1134` reverts if LR_MID_DAY==0; the failsafe).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1688` — `updateVrfCoordinatorAndSub` (D-01/D-02; `:1701-1704` resets, `:1709` LR_MID_DAY=0, `:1711-1714` totalFlipReversals carry-over comment).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1756` — `rawFulfillRandomWords` (`:1766-1768` daily branch → rngWordCurrent; `:1769-1776` mid-day branch → lootboxRngWordByIndex[index]; `:1761` requestId/word guard that abandons the old word).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1208` — the existing `_backfillOrphanedLootboxIndices` call (D-05 reachability).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1817` — `_backfillOrphanedLootboxIndices` definition (backward scan, VRF-derived keccak).
- `contracts/modules/DegenerusGameAdvanceModule.sol:209-238,269` — the advance-flow drain gate (Scenario B revert site; D-05 must confirm re-issue un-blocks it).
- `contracts/modules/DegenerusGameMintModule.sol:686` — `entropy = lootboxRngWordByIndex[...-1]` with NO zero-guard (Scenario A consumer).
- `contracts/storage/DegenerusGameStorage.sol:244` `rngRequestTime` · `:373` `rngWordCurrent` · `:1287/1291/1295` `vrfCoordinator`/`vrfKeyHash`/`vrfSubscriptionId` · `:1328-1329` `LR_MID_DAY` shift/mask · `:1431` `lootboxRngWordByIndex` — the VRF-participating slots.

### Memory / methodology (must apply)
- `project_vrf_rotation_midday_orphan_index` — the CONFIRMED finding + recommended re-issue shape (now D-01).
- `v45-vrf-freeze-invariant` — every variable interacting with a VRF word frozen [rng request→unlock] vs PLAYERS; advanceGame/admin exempt; verify consumed-this-cycle.
- `project_rnglock_audit_disposition` — §9d anchors are a maximalist catalog, NOT live player vectors; don't over-fix governance rows beyond the real liveness defect.
- `feedback_design_intent_before_deletion`, `feedback_verify_call_graph_against_source`, `feedback_security_over_gas` (validator-influenceable entropy backfill REJECTED), `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_no_contract_commits` + `feedback_manual_review_before_push` (Phase 312 posture).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `rawFulfillRandomWords` (`:1756`) already has BOTH a daily branch (→ `rngWordCurrent`) and a mid-day branch (→ `lootboxRngWordByIndex[index]`). Re-issue (D-01/D-02) reuses these unchanged — re-firing the request just makes a fresh `vrfRequestId` the callback matches against. No new fulfillment path.
- `_backfillOrphanedLootboxIndices` (`:1817`) already exists with VRF-derived `keccak(vrfWord, i)` entropy (not front-runnable) and a backward scan. D-05 keeps it; re-issue restores its reachability rather than adding new wiring.
- `retryLootboxRng` (`:1133`) is the standing failsafe for a mid-day request that never delivers — covers "new coordinator also stalls" without new code.

### Established Patterns
- VRF-config writes are admin-only (`ContractAddresses.ADMIN`). `wireVrf` (`:498`) and `updateVrfCoordinatorAndSub` (`:1688`) both write the same 3 slots — the near-duplication D-04 collapses into `_setVrfConfig`.
- The `(index)` reservation uses `LR_INDEX`; `LR_MID_DAY` gates a single in-flight mid-day request at a time (`:1048`) — bounds orphans to one per rotation (grounds D-05's narrow scope).
- Shared logic belongs in the base contract or a shared internal, per the Phase 310 D-01/D-02 precedent (single-source-of-truth; avoids inline-duplication drift).

### Integration Points
- All four decisions land inside `DegenerusGameAdvanceModule.sol` (+ possibly one new `pendingVrf*` slot only if SPEC ever reversed D-01 to queue+apply — NOT expected). No other module changes anticipated for the fix; `MintModule:686`'s zero-guard-absence is *mitigated structurally* by D-01/D-02 (the index is always filled), not by adding a guard — SPEC confirms.
- ADMA-02 vault reach: `DegenerusVault` dispatch to the admin VRF functions must be checked so the lock (D-03) + safe-rotation (D-01/D-02) cover the vault-routed path (VRF-05).

</code_context>

<specifics>
## Specific Ideas

- Strong preference (carried from Phase 310 + reaffirmed here): **single-source-of-truth over duplication** — drove D-04 (`_setVrfConfig`).
- Audit-narrative awareness: the user accepts re-issue's "old word abandoned, new word unpredictable" freeze story over queue+apply's "zero mid-window mutation" story, because the latter sacrifices recovery liveness when the old coordinator is dead — and liveness is the whole point of the emergency procedure.
- Decision-anchor convention (D-NN) is used in SPECs here; the SPEC should carry D-01..D-05 forward and assign any new sub-decisions fresh anchors.

</specifics>

<deferred>
## Deferred Ideas

- **Belt-and-suspenders gate-independent orphan backfill** — considered (Area 4) and deferred in favor of D-05's narrow fix; revisit ONLY if the SPEC's reachability trace finds a residual orphan path re-issue + `:1208` don't cover.
- **Queue+apply rotation (`pendingVrfRotationPacked`)** — the §9d HANDOFF-78 tactic; rejected as the fix shape (D-01) but recorded as the documented alternative for the SPEC's rejected-options section.
- Non-VRF v44 backlog (~115 anchors), V-081 dedicated regression, jackpot pending-pool new work — out of scope for v45.0 per `.planning/REQUIREMENTS.md`; not this phase.

</deferred>

---

*Phase: 311-spec-vrf-rotation-liveness-fix-spec*
*Context gathered: 2026-05-22*
