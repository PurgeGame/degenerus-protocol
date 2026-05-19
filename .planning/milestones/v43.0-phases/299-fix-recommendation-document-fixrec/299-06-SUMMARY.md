---
phase: 299-fix-recommendation-document-fixrec
plan: 06
subsystem: rngLock-fixrec-cluster-F
tags: [fixrec, rng-lock, audit-only, cluster-F, pendingRedemption, deityPass, eth-balance, stETH-balance, game-over-drain]
requires:
  - .planning/RNGLOCK-CATALOG.md (Phase 298 §14/§15/§16 rows S-17..S-21 / writers / V-066..V-080)
  - .planning/phases/299-fix-recommendation-document-fixrec/299-CONTEXT.md
provides:
  - .planning/phases/299-fix-recommendation-document-fixrec/299-06-FIXREC-cluster.md
affects: []
tech-stack:
  added: []
  patterns:
    - "Per-VIOLATION 4-sub-section analytical entry (D-299-FIXREC-LAYOUT-01)"
    - "Tactic-(b) snapshot-at-_gameOverEntropy (Phase 281 owed-salt precedent)"
    - "Tactic-(a) gated-revert verification (BurnsBlockedDuringLiveness / _livenessTriggered patterns)"
    - "Subsumption anchor preservation for v44.0 traceability"
key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-06-FIXREC-cluster.md
    - .planning/phases/299-fix-recommendation-document-fixrec/299-06-SUMMARY.md
  modified: []
decisions:
  - "Single `gameOverFundsSnapshot` field at _gameOverEntropy covers BOTH V-071 (ETH receive/selfdestruct/coinbase) and V-080 (stETH external IN-transfer) via the totalFunds = balance + steth.balanceOf summation in handleGameOverDrain:84"
  - "V-070 subsumed by V-069 — both writes co-located inside _purchaseDeityPass body at WhaleModule.sol:595/:596; single function-head gate covers both"
  - "V-073 subsumed by V-063 (Cluster E / FIXREC 299-05) — both writes inside _claimWinningsInternal at DegenerusGame.sol:1408 / :1410-:1414; single function-head gate at :1400 covers both claimablePool and address(this).balance writers"
  - "V-068 subsumed by V-184 (S-56 redemptionPeriodIndex re-resolution lock, FIXREC 299-K, H-111) — subtraction direction race surface evaporates once upstream re-arm is closed"
  - "V-066 + V-072 + V-074 are tactic-(a) verification-only rows; existing BurnsBlockedDuringLiveness / _livenessTriggered / rngLockedFlag gates already cover; FUZZ-301 branch-reach attestation is the v44.0 deliverable"
  - "V-069 requires new gate condition: `purchaseDeityPass` reverts when any lootbox's RNG word is fresh-but-unconsumed in the open window (extends existing rngLockedFlag + _livenessTriggered pair at WhaleModule.sol:543-:544)"
metrics:
  duration_minutes: 35
  tasks_completed: 1
  files_created: 2
  files_modified: 0
  completed_date: 2026-05-18
---

# Phase 299 Plan 06: FIXREC Cluster F (pendingRedemption + deityPass + ETH/stETH balance) Summary

**One-liner:** Authors per-VIOLATION FIXREC analytical entries for the 9 game-over-magnitude-input VIOLATIONs (V-066/V-068/V-069/V-070/V-071/V-072/V-073/V-074/V-080) spanning slots S-17/S-18/S-19/S-20/S-21, recommending tactic-(b) `gameOverFundsSnapshot` for the ungateable balance inflow class (V-071+V-080) and tactic-(a) verification/extended-gate for the gateable writers, with explicit subsumption documentation for V-070→V-069, V-073→V-063, V-068→V-184.

## Work completed

**Authored `.planning/phases/299-fix-recommendation-document-fixrec/299-06-FIXREC-cluster.md`** — 9 per-VIOLATION §N analytical entries (§1 V-066 through §9 V-080), each with the 4 sub-sections (§N.A design-intent backward-trace + §N.B actor game-theory walk + §N.C recommended tactic + rationale + impact estimate + §N.D v44.0 handoff anchor) per `D-299-FIXREC-LAYOUT-01`.

Cluster-preamble documents the unifying theme: every slot in Cluster F is a live-SLOAD consumed inside `GameOverModule.handleGameOverDrain:84-:134` (the terminal-day game-over magnitude consumer that computes `preRefundAvailable`, the deity-refund-per-holder pass, and the terminal-payout magnitude). The two balance inputs (V-071 ETH; V-080 stETH) share a single tactic-(b) snapshot field at `_gameOverEntropy` commitment moment — the snapshot captures `totalFunds = address(this).balance + steth.balanceOf(address(this))` as one value, eliminating the inflation race for the universal inflow class (receive + selfdestruct + coinbase-payout + Lido external transfer).

Subsumption relationships preserved per v44.0 traceability discipline:

- **V-070 (`deityPassPurchasedCount += 1`) subsumed by V-069 (`deityPassOwners.push`)** — both writes co-located inside `_purchaseDeityPass` at `WhaleModule.sol:595` / `:596`. Single function-head gate extension at `:543-:544` (adding fresh-lootbox-rng-window revert) closes both. H-37 anchor preserved; H-36 is the operational target.
- **V-073 (`address(this).balance` via `call{value:}`) subsumed by V-063 (`claimablePool -=`)** — cross-cluster coordination with Cluster E / FIXREC 299-05. Both writes inside `_claimWinningsInternal` at `DegenerusGame.sol:1408` / `:1410-:1414`. Single gate at `:1400` (`_livenessTriggered() && !gameOver`) closes both. H-40 anchor preserved; H-31 is the operational target.
- **V-068 (`pendingRedemptionEthValue -=`) subsumed by V-184 (S-56 `redemptionPeriodIndex` re-resolution lock)** — cross-cluster coordination with FIXREC 299-K. Pre-V-184 cross-day re-roll exploit is the root cause; closing the upstream re-arm at `StakedDegenerusStonk._submitGamblingClaimFrom` eliminates the V-068 race surface. H-35 anchor preserved; H-111 is the operational target.

## Tactic mix (Cluster F)

| VIOLATION | Slot | Writer | Tactic | EV-tier | Disposition |
|-----------|------|--------|--------|---------|-------------|
| V-066 | S-17 | sStonk `burn`/`burnWrapped` `+=` | (a) | NONE | Existing `BurnsBlockedDuringLiveness` covers — verification |
| V-068 | S-17 | sStonk `claimRedemption` `-=` | (a) | LOW | Subsumed by V-184 (H-111) |
| V-069 | S-18 | `_purchaseDeityPass` `.push` | (a) | HIGH | Extend `_purchaseDeityPass` gate (fresh-lootbox-rng) |
| V-070 | S-19 | `_purchaseDeityPass` `+= 1` | (a) | HIGH | Subsumed by V-069 (H-36) |
| V-071 | S-20 | `receive()` + selfdestruct + coinbase | (b) | HIGH | `gameOverFundsSnapshot` at `_gameOverEntropy` |
| V-072 | S-20 | payable purchase functions | (a) | NONE | Existing per-fn gates cover — verification |
| V-073 | S-20 | `claimWinnings` `call{value:}` | (a) | HIGH | Same gate as V-063 (H-31, Cluster E) |
| V-074 | S-20 | sDGNRS / vault / GNRUS callbacks | (a) | NONE | Transitive sister-contract gate — verification |
| V-080 | S-21 | Lido `IStETH.transfer(game, _)` | (b) | MEDIUM | Same `gameOverFundsSnapshot` field as V-071 (H-38) |

**Tactic distribution:** 5× (a) verification + 2× (a) new gate + 2× (b) snapshot. **EV distribution:** 3× HIGH (V-069 / V-071 / V-073) + 1× MEDIUM (V-080) + 1× LOW (V-068) + 4× NONE-already-defended (V-066 / V-072 / V-074 / V-070-via-V-069).

## Handoff anchors (9)

`D-43N-V44-HANDOFF-34` (V-066 verification), `D-43N-V44-HANDOFF-35` (V-068 → H-111 subsumption), `D-43N-V44-HANDOFF-36` (V-069 extended `_purchaseDeityPass` gate), `D-43N-V44-HANDOFF-37` (V-070 → H-36 subsumption), `D-43N-V44-HANDOFF-38` (V-071 `gameOverFundsSnapshot`), `D-43N-V44-HANDOFF-39` (V-072 verification), `D-43N-V44-HANDOFF-40` (V-073 → H-31 subsumption / shared gate), `D-43N-V44-HANDOFF-41` (V-074 transitive sister-contract gate verification), `D-43N-V44-HANDOFF-42` (V-080 → H-38 shared snapshot).

## Cross-cluster coordination required at v44.0

- H-35 (V-068, Cluster F) blocks on H-111 (V-184, Cluster K).
- H-37 (V-070, Cluster F) blocks on H-36 (V-069, Cluster F) — intra-cluster.
- H-40 (V-073, Cluster F) blocks on / coordinates with H-31 (V-063, Cluster E).
- H-42 (V-080, Cluster F) blocks on / coordinates with H-38 (V-071, Cluster F) — intra-cluster.

The v44.0 plan-phase MUST sequence these dependencies OR merge into single sub-phases where anchor-pairs share gate / snapshot infrastructure.

## Deviations from Plan

None — plan executed exactly as written. All 9 V-NNN entries authored with all 4 sub-sections. All 9 H-NN handoff anchors present (H-34..H-42). Zero `contracts/` / `test/` mutations. Zero SAFE_BY_DESIGN tokens. No stale-phantom rows detected — all 9 writer call sites grep-verified against current source per `feedback_verify_call_graph_against_source.md`.

## Methodology compliance

- `feedback_design_intent_before_deletion.md` — every §N.A traces the original design intent of the slot (slot introduction phase + economic function + "what would break if frozen") BEFORE the tactic recommendation.
- `feedback_verify_call_graph_against_source.md` — every writer call site grep-verified against `contracts/StakedDegenerusStonk.sol`, `contracts/modules/DegenerusGameWhaleModule.sol`, `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameGameOverModule.sol`. Key finding: `_claimWinningsInternal` at `DegenerusGame.sol:1399-:1416` has NO `_livenessTriggered()` gate — only `GO_SWEPT` check — confirming V-073's catalog verdict "NO — EOA; no liveness gate".
- `feedback_no_history_in_comments.md` — every §N describes what the recommended state IS and what the current VIOLATION state IS, never what changed.
- `feedback_rng_window_storage_read_freshness.md` — every entry traces backward from the consumer SLOAD inside the rng-window to verify the slot is consumed alongside (not after) the resolution.
- `feedback_frozen_contracts_no_future_proofing.md` — V-071's "structurally impossible to gate" rationale cites that contracts are frozen at deploy and adding receive-fallback reverts would not eliminate the `selfdestruct` / coinbase-payout inflow class.

## Self-Check: PASSED

- `.planning/phases/299-fix-recommendation-document-fixrec/299-06-FIXREC-cluster.md` — EXISTS
- `.planning/phases/299-fix-recommendation-document-fixrec/299-06-SUMMARY.md` — EXISTS
- 9 V-NNN entries (V-066, V-068, V-069, V-070, V-071, V-072, V-073, V-074, V-080) — VERIFIED via grep
- 9 H-NN anchors (HANDOFF-34..HANDOFF-42) — VERIFIED via grep
- ≥9 per sub-section markers (§N.A / §N.B / §N.C / §N.D) — VERIFIED (12 / 13 / 12 / 9 respectively; extras from preamble/summary cross-references)
- Zero SAFE_BY_DESIGN tokens — VERIFIED
- Zero `contracts/` + `test/` source-tree mutations — VERIFIED (`git status --porcelain contracts/ test/` is empty)
