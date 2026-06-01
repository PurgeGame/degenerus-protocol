# Phase 344: IMPL — The ONE Batched Contract Diff (ledger + de-custody + CLEANUP-02 orphan removal) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 344-impl-the-one-batched-contract-diff-ledger-de-custody-cleanup
**Areas discussed:** Cleanup shape, Planning (Verify depth + Events presented, locked to defaults by user choice)

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Verify depth | Build-only HOLD vs also attempt the (ABI-broken) suite | |
| Events | KeeperFunded/KeeperWithdrew names + indexing; Deposited disposition; AfKing subscribe event | |
| Cleanup shape | Deletion shape + design-intent trace + 344/345 boundary | ✓ |
| Planning | Skip-research vs research; where the re-grep lives | ✓ |

**User's choice:** Discuss "Planning" and "Cleanup shape". Verify depth + Events locked to recommended defaults.

---

## Cleanup shape

### Recovery-leg removal safety gate

| Option | Description | Selected |
|--------|-------------|----------|
| Pure removal + traced equivalence | Remove all three legs; author MUST first run the actor-consequence trace and DOCUMENT that game.withdrawKeeperFunding + sDGNRS receive() GAME-allowance (5c) + Decision-B merge fully replace v48 recovery for BOTH VAULT and sDGNRS; escalate on any gap before deleting | ✓ |
| Keep a thin recovery shim | Retain a minimal recovery path rather than the generic withdraw | |
| Defer the trace to 346 TST | Remove on grep-orphan proof alone; prove recoverability empirically later | |

**User's choice:** Pure removal + traced equivalence.
**Notes:** Honors [[feedback_design_intent_before_deletion]] — grep-orphan (proven in 343) is necessary but not sufficient; the actor-consequence trace (VAULT-can-receive + sDGNRS-GAME-allowance + Decision-B merge) is the gate, with escalation on any recoverability gap.

### Deletion shape

| Option | Description | Selected |
|--------|-------------|----------|
| Pure delete + one NatSpec line | Clean delete + one current-state invariant NatSpec line | |
| Pure delete, no comment | Clean delete, rely on the structural no-receive guarantee, no added comment | ✓ |
| Delete + defensive assert | Delete + a balance==0 assert | |

**User's choice:** Pure delete, no comment.
**Notes:** Leanest diff. Stale `_poolOf` comments (#12/#13) + the `sum(_poolOf) <= balance` invariant doc are removed, not replaced. No dead guard against the unreachable receive state.

### 344/345 cleanup boundary

Locked (not a question): de-custody orphans = 344 CLEANUP-02; codebase-wide unrelated dead-code sweep = 345 CLEANUP-03 — per the 343 inventory scope.

---

## Planning

### Research posture

| Option | Description | Selected |
|--------|-------------|----------|
| Skip research, plan directly | Plan straight off 343-IMPL-EDIT-ORDER-MAP.md (--skip-research) | ✓ |
| Light pattern-map only | Skip research agent but run pattern-mapper | |
| Full research pass | Run gsd-phase-researcher | |

**User's choice:** Skip research, plan directly.
**Notes:** SPEC is design-gating-complete (the SPEC IS the research output); per [[feedback_skip_research_test_phases]].

### Where the mandatory pre-author re-grep lives

| Option | Description | Selected |
|--------|-------------|----------|
| Executor's first action | Re-run every grep vs live tree + re-pin anchors as the FIRST executor step | ✓ |
| Planner pre-flight re-pin | Planner bakes fresh lines into the PLAN | |
| Both (planner + executor) | Belt-and-suspenders | |

**User's choice:** Executor's first action.
**Notes:** Plan cites SPEC anchors as the starting reference; executor re-confirms against live tree before any edit (contracts/ currently == baseline 83a84431, clean — re-grep is the discipline floor).

### Plan structure

| Option | Description | Selected |
|--------|-------------|----------|
| Plans per edit-order step | ~5 plans following producer-before-consumer steps → one combined diff → one approval → atomic per-plan commits | ✓ |
| One monolithic plan | Single 344-01 plan → one commit | |
| Let the planner decide | Leave plan count to gsd-planner | |

**User's choice:** Plans per edit-order step.
**Notes:** Per [[feedback_batch_contract_approval]] — all edits authored first, one approval at the end, then split into per-plan commits for clean SUMMARY mapping. Executor subagents never commit (hook-enforced).

---

## Locked-by-default areas (presented, user chose not to discuss)

- **Verify depth:** `forge build`-clean only → HOLD; the ABI change breaks test compilation → 346 TST repairs it.
- **Events:** `KeeperFunded(address indexed player, uint256)` / `KeeperWithdrew(address indexed player, uint256)`; AfKing `Deposited` event removed (orphaned); `SubscriptionUpdated` (indexed fundingSource) unchanged.

## Claude's Discretion

- Per-plan split within the 5 edit-order steps; the wording of the actor-consequence trace doc; whether the re-grep results are recorded inline in a SUMMARY or a scratch attestation.

## Deferred Ideas

- CLEANUP-03 codebase-wide sweep → 345. GAS-02/03 + packing eval → 345. Test-suite repair → 346 TST. Generalized operator-spend-claimable → out of v54.
