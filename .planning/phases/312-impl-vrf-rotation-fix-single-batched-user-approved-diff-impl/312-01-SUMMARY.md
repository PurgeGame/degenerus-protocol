---
phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl
plan: 01
subsystem: infra
tags: [solidity, chainlink-vrf, vrf-rotation, rng-lock, degenerus, foundry]

# Dependency graph
requires:
  - phase: 311-spec-vrf-rotation-liveness-fix-spec
    provides: Locked fix design (D-01..D-08), freeze-invariant disposition, wireVrf/updateVrf dispatch trace
provides:
  - "_requestVrfWord(uint16) private re-issue helper on the current VRF coordinator"
  - "_setVrfConfig(address,uint256,bytes32) internal shared config write (used by wireVrf + updateVrfCoordinatorAndSub)"
  - "updateVrfCoordinatorAndSub 3-case preserve+re-issue rework (mid-day-first; daily rngWordCurrent==0 short-circuit; nothing-in-flight no-op)"
  - "Structural elimination of the VRF-rotation orphan-index liveness defect (Scenario A entropy-0 traits + Scenario B post-rotation freeze)"
affects: [313-vtst-vrf-rotation, vrf, rng-lock, lootbox, advance-game]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Re-issue-in-flight on coordinator rotation (preserve flags + LR_INDEX, request fresh word, abandon old via :1761 requestId guard)"
    - "Shared internal config-write helper to dedup near-identical SSTORE blocks"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "VRF-04 wireVrf init-only lock OMITTED (user-approved deviation from 311 SPEC D-03): wireVrf is reachable only from the DegenerusAdmin constructor, so a runtime lock guards a topologically-unreachable path. Requirement met by construction, not by added code."
  - "No LINK precheck on the re-issue path (VER-01): the rotation request is accepted pre-funding and fulfilled at fund-time in the same _executeSwap tx; a precheck would brick rotation."
  - "Mid-day-first precedence in the 3-case branch (VER-03 defensive ordering)."
  - "Daily branch re-issues only when rngWordCurrent==0 (VER-02): an already-delivered word is preserved; a fresh callback would be rejected by the :1761 rngWordCurrent!=0 guard."

patterns-established:
  - "Coordinator rotation preserves the in-flight request rather than blanket-resetting RNG state."

requirements-completed: [VRF-01, VRF-02, VRF-03, VRF-04, VRF-05]

# Metrics
duration: ~25min
completed: 2026-05-23
---

# Phase 312: VRF-Rotation Fix Summary

**updateVrfCoordinatorAndSub now preserves and re-issues the in-flight VRF request across an emergency coordinator rotation (mid-day → lootboxRngWordByIndex[N], daily → rngWordCurrent), structurally eliminating the orphan-index liveness defect; adds _requestVrfWord + _setVrfConfig helpers.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-05-23T08:47:32Z
- **Tasks:** 5 (Tasks 1–4 auto; Task 5 USER-APPROVAL checkpoint)
- **Files modified:** 1 contract (`DegenerusGameAdvanceModule.sol`)

## Accomplishments
- **VRF-01:** Mid-day rotation branch re-issues on the new coordinator with `LR_INDEX` preserved, so the genuine VRF word lands in the same reserved slot `[N]` via `rawFulfillRandomWords:1772` — the entropy-0 path is eliminated structurally (the slot is filled), not by a runtime zero-guard.
- **VRF-02:** Post-rotation liveness preserved — re-issue fills `[N]` (mid-day) or `rngWordCurrent` (daily) so the advance-drain gate, `requestLootboxRng`, and `retryLootboxRng` all stay reachable; no permanent revert / ~120-day freeze.
- **VRF-03:** Freeze invariant intact — the old in-flight word is abandoned by the `:1761` requestId guard, the new word is unpredictable at re-issue time, admin rotation is EXEMPT-class vs players; no validator-influenceable entropy introduced.
- **VRF-04:** wireVrf one-shot property confirmed by construction (see Deviations) — requirement met without code.
- **VRF-05:** Vault/admin-routed dispatch terminates at the same AdvanceModule impl where the admin guard + safe-rotation sit; no wrapper bypass.
- Removed the blanket RNG-state reset (`rngLockedFlag=false; vrfRequestId=0; rngRequestTime=0; rngWordCurrent=0`) and the rotation-time `LR_MID_DAY=0` clear that together orphaned the reserved index.

## Edits Applied (mapped to RESEARCH section 3 anchors)
1. **`_requestVrfWord(uint16 confirmations) private returns (uint256 id)`** — RESEARCH 3.1 / D-06. Single `VRFRandomWordsRequest` with `requestConfirmations: confirmations`, `extraArgs: hex""`; the 4 existing inline request sites left untouched.
2. **`_setVrfConfig(address coord, uint256 sub, bytes32 key) internal`** — RESEARCH 3.2 / D-04, D-07. Three SSTOREs in order; `lastVrfProcessedTimestamp` + the `current` reads + both `VrfCoordinatorUpdated` emits kept OUTSIDE the helper.
3. **`wireVrf`** — routes its config write through `_setVrfConfig(coordinator_, subId, keyHash_)`; `current` read, `lastVrfProcessedTimestamp`, and emit preserved inline. (Init-only lock omitted — see Deviations.)
4. **`updateVrfCoordinatorAndSub`** — RESEARCH 3.4 / D-01, D-02. Config write → `_setVrfConfig(newCoordinator, newSubId, newKeyHash)`; blanket reset + `LR_MID_DAY=0` clear → verbatim 3-case preserve+re-issue branch (mid-day-first; daily `rngWordCurrent==0` short-circuit; nothing-in-flight no-op). Admin guard, `current` read, `totalFlipReversals` comment, and emit preserved.

## Pre-Patch Verification (VER-04)
- HEAD at patch time `41546f16`, a docs-only descendant of `bce6e243`: `git diff bce6e243 HEAD -- contracts/` was empty → **zero contract drift**.
- All SPEC anchors re-grepped live before patching: `VRF_REQUEST_CONFIRMATIONS=10@:122`, `VRF_MIDDAY_CONFIRMATIONS=4@:123`, `wireVrf@:498`, `updateVrfCoordinatorAndSub@:1688`, `rawFulfillRandomWords@:1756`, 4 `requestRandomWords(` sites at `:1102/:1143/:1587/:1605`, both helpers absent (0).

## Build / Scope / Self-Review Attestation
- **`forge build` → exit 0**, no new error lines (pre-existing `unsafe-typecast` lint notes unchanged).
- **Scope:** `git diff --stat` (contract scope) = ONLY `contracts/modules/DegenerusGameAdvanceModule.sol` (49 insertions, 17 deletions). No `DegenerusAdmin.sol` / `DegenerusGame.sol` / `Storage.sol` / `MintModule.sol` / `test/` change. **No new storage slot.**
- **Self-review vs RESEARCH 3.1/3.2/3.4:** helper signatures verbatim; updateVrf 3-case branch verbatim; PRESERVE set intact (admin guards, `current` reads, `lastVrfProcessedTimestamp`, `totalFlipReversals` comment, both emits, 4 untouched inline `VRFRandomWordsRequest` sites). Greps: `setVrfConfig=1, requestVrfWord=1, structs=5, requestRandomWords=5, midReissue=1, dailyReissue=1, verShortCircuit=1, blanketComment=0, flipReversals=1, historyWords=0, wireLock=0`.

## Task Commits
1. **Tasks 1–4 (single batched contract commit, USER-approved):** `a303ae18` — `fix(312-01): VRF-rotation orphan-index re-issue + _setVrfConfig dedup`
   - Per the batched-approval discipline, all contract edits accumulated in the working tree and were committed once after explicit USER approval, using the `CONTRACTS_COMMIT_APPROVED=1` bypass for the PreToolUse contract-commit guard.

**USER-approval evidence:** The complete one-file unified diff + `forge build` exit-0 evidence were presented at the Task-5 checkpoint. The user reviewed it, questioned the `wireVrf` lock (prompting the call-graph trace and the VRF-04 deviation below), then explicitly typed "approved" before any commit was made.

## Deviations from Plan

### 1. [User-approved scope decision] VRF-04 wireVrf init-only lock OMITTED

- **Plan/SPEC intent:** 311 SPEC §4.1 / D-03 mandated adding `if (address(vrfCoordinator) != address(0)) revert E();` to `wireVrf` to seal it post-init (closing VRF-04 / HANDOFF-86/88/90 + ADMA-01).
- **Finding (call-graph trace, per feedback_verify_call_graph_against_source):** `wireVrf` is reachable **only** from the DegenerusAdmin constructor:
  - `DegenerusGame.wireVrf` (`:308`) has no access guard of its own; all access control is the impl's `:503` `msg.sender != ContractAddresses.ADMIN` check.
  - In a delegatecall, `msg.sender` is preserved, so the only caller that passes is the **DegenerusAdmin contract** (`ContractAddresses.ADMIN`).
  - DegenerusAdmin calls `gameAdmin.wireVrf` **only at `:458`, inside its constructor**, and exposes **no** post-construction function and **no** arbitrary-call/`delegatecall`/`multicall` forwarder that could re-emit it.
  - Therefore a second `wireVrf` is topologically unreachable; the SPEC itself (§0.Y line 225, §4.1 line 528) acknowledged "structurally init-only … nothing calls wireVrf a second time." The SPEC's framing of `wireVrf` as a "live post-init mutator" was the overstated premise.
- **Decision (user-approved):** Omit the runtime lock — guarding an unreachable path is redundant on a frozen contract (feedback_frozen_contracts_no_future_proofing). `wireVrf` still routes its config write through `_setVrfConfig` (the D-04 dedup, which spans both functions, is retained).
- **Effect on requirement VRF-04:** Met by construction (wireVrf is one-shot) rather than by added code. The exploitable orphan vector was always the **rotation** path (`updateVrfCoordinatorAndSub`), which Edits 1 + 4 close.
- **Verification impact:** PLAN must_haves truth #3, artifact `provides`, and the `wireVrf` key_link were updated to reflect "one-shot by construction; lock omitted."

### 2. [Plan grep-constant correction] LINK-precheck count

- Task 3 acceptance asserted `grep -c "linkBal < MIN_LINK_FOR_LOOTBOX_RNG" == 1`. The true pre-existing count is **2** (one in `requestLootboxRng:1064`, one in `retryLootboxRng:1141`). The patch adds **none** to the re-issue path (VER-01), so the post-patch count is **2** (unchanged). The substantive requirement — no LINK precheck on the rotation re-issue — holds; only the plan's counted constant was off by one.

**Impact on plan:** No scope creep. Deviation 1 reduces code vs the SPEC (omits one guard line) on user-approved, source-verified grounds; Deviation 2 is a documentation correction. The CATASTROPHE-class fix (VRF-01/02/03) is delivered in full.

## Issues Encountered
None — build green throughout; the contract-commit guard behaved as designed (blocked until the `CONTRACTS_COMMIT_APPROVED=1` post-approval bypass).

## Next Phase Readiness
- **Phase 313 (VTST)** will exercise this thoroughly across edge cases: liveness-after-rotation (mid-day and daily branches), the freeze invariant under rotation, the `rngWordCurrent==0` short-circuit, the nothing-in-flight no-op, and the pre-funding/fund-at-`_executeSwap` re-issue timing (RESEARCH §5 Open Risk 1: real mainnet coordinator behavior on an unfunded request; `retryLootboxRng` is the documented failsafe).
- No external service configuration required.

---
*Phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl*
*Completed: 2026-05-23*
