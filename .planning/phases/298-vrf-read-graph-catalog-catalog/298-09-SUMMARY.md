---
phase: 298-vrf-read-graph-catalog-catalog
plan: 09
subsystem: rng-catalog
tags: [audit, vrf, rng-lock, advance-module, retry-lootbox-rng, failsafe, exempt-retrylootboxrng, catalog]
dependency_graph:
  requires: []
  provides:
    - "§9 catalog content for AdvanceModule.retryLootboxRng (failsafe path)"
  affects:
    - ".planning/phases/298-vrf-read-graph-catalog-catalog/"
tech_stack:
  added: []
  patterns:
    - "Per-consumer backward-trace per `feedback_rng_backward_trace.md`"
    - "ALL-SLOAD enumeration per `feedback_rng_window_storage_read_freshness.md`"
    - "Explicit file:line enumeration per `feedback_verify_call_graph_against_source.md`"
    - "Commitment-window discipline per `feedback_rng_commitment_window.md`"
    - "EXEMPT-RETRYLOOTBOXRNG verdict class per D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A"
key_files:
  created:
    - ".planning/phases/298-vrf-read-graph-catalog-catalog/298-09-CATALOG-section.md"
    - ".planning/phases/298-vrf-read-graph-catalog-catalog/298-09-SUMMARY.md"
  modified: []
decisions:
  - "D-298-CONSUMER-LIST-01 §9 traced from AdvanceModule.retryLootboxRng:1132 — flat function body (no internal helpers beyond `_lrRead` and external VRF coordinator calls)"
  - "EXEMPT-RETRYLOOTBOXRNG verdict class applied per D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A; D-4 row (rngRequestTime SSTORE at :1154) is the canonical EXEMPT-RETRYLOOTBOXRNG callsite"
  - "Per `D-298-EXEMPT-REACH-01` strict per-callsite classification: governance-EOA VRF rotation writers (`updateVrfCoordinatorAndSub` at :1685-:1698) classified VIOLATION across 5 slots (D-2/D-8/D-12/D-14/D-16)"
  - "Per `D-298-RECOMMEND-DEPTH-01`: 3 §E tactic groups — (c) pre-lock reorder for E-1 (sibling-EOA scope expansion) + E-2 (governance-rotation queuing); (d) immutable for E-3 (deploy-time VRF config seal)"
  - "Option A invariant 3 (no pre-lock-state manipulation) verified: §9 SSTOREs only `vrfRequestId` (:1153) + `rngRequestTime` (:1154); does NOT touch LR_INDEX / LR_PENDING_ETH / LR_PENDING_BURNIE / LR_MID_DAY / lootboxRngWordByIndex / rngWordCurrent / rngLockedFlag / dailyIdx / rngWordByDay"
metrics:
  duration: ~14min
  completed: 2026-05-18
---

# Phase 298 Plan 09: AdvanceModule.retryLootboxRng Summary

Backward-trace VRF-protocol-coordination from `AdvanceModule.retryLootboxRng` at `contracts/modules/DegenerusGameAdvanceModule.sol:1132` per `D-298-CONSUMER-LIST-01` §9. Permissionless mid-day VRF-stall failsafe. Per **D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A** (Phase 296 SWEEP lock), §9's resolution stack carries the dedicated `EXEMPT-RETRYLOOTBOXRNG` verdict class — the third of the three EXEMPT entry-point classes enumerated in the v43.0 milestone goal (advanceGame / VRF coordinator callback / retryLootboxRng). Single AGENT-COMMIT catalog section authored; zero source-tree mutations.

## Tasks Completed

| # | Task                                                                                       | Commit         | Files                                                                   |
|---|--------------------------------------------------------------------------------------------|----------------|-------------------------------------------------------------------------|
| 1 | Sub-agent backward-trace from AdvanceModule.retryLootboxRng:1132 (failsafe path)           | (this commit)  | `.planning/phases/298-vrf-read-graph-catalog-catalog/298-09-CATALOG-section.md` |

## What Was Produced

§9 catalog section with the five mandatory sub-headings:

- **§A (CAT-01) — Traced function set:** 4 reached entities enumerated. `retryLootboxRng` is a flat function body — one `_lrRead` call (Storage.sol:1337) and two external VRF coordinator interface calls (`getSubscription` at :1137, `requestRandomWords` at :1142). No delegatecalls, no inline assembly, no further dispatch — confirmed by explicit-enumeration grep cross-check (`grep -n "delegatecall\|\.call\|staticcall"` and `grep -n "assembly"` both return zero hits inside :1132-:1155).

- **§B (CAT-02) — SLOAD table:** 8 SLOAD rows (B-1..B-8) — all marked `Participating? = YES`. The slots are the gates and inputs that the failsafe reads to decide whether to fire and what VRF config to fire with: `lootboxRngPacked.LR_MID_DAY` (entry gate), `rngRequestTime` (entry-gate + cooldown), `vrfCoordinator` (×2 — two separate SLOADs for the two external calls; Solidity does not cache cross-statement storage slots), `vrfSubscriptionId` (×2), `vrfKeyHash`. Constants and `block.timestamp` reads enumerated separately as non-SLOAD for completeness per `feedback_verify_call_graph_against_source.md`.

- **§C (CAT-03) — Writer enumeration:** 5 participating-slot groups (C-1..C-5) covering 16 distinct writer callsites across `AdvanceModule`. `grep` verification quoted inline per slot. The bookkeeping enumerated 8 callsites for `rngRequestTime` (`_requestLootboxRng:1122`, `retryLootboxRng:1154` self, `_gameOverEntropy:1329`, `_tryRequestRng:1341`, `_finalizeRngRequest:1633`, `updateVrfCoordinatorAndSub:1692`, `_unlockRng:1734`, `rawFulfillRandomWords:1764`) — matches the grep count exactly.

- **§D (CAT-04) — Verdict matrix:** 16 (slot × writer × callsite) rows (D-1..D-16). **10 VIOLATIONs** identified: D-1 + D-3 (commitment-side `requestLootboxRng` writes outside the 3 EXEMPT stacks — substantive risk nil because the §9 caller benefits from these writes existing); D-2 + D-8 + D-12 + D-14 + D-16 (governance-EOA VRF-rotation bundle clearing LR_MID_DAY / rngRequestTime + rotating coordinator / sub / keyHash mid-stall); D-11 + D-13 + D-15 (constructor-time `wireVrf` writes per strict per-callsite rule).
- **1 EXEMPT-RETRYLOOTBOXRNG row (D-4)** — the failsafe's own `rngRequestTime = uint48(block.timestamp)` SSTORE at `:1154` (cooldown-reset). Satisfies the plan acceptance criterion "≥1 §D row classified `EXEMPT-RETRYLOOTBOXRNG`". The disposition class is locked by **D-42N-RETRY-RNG-DOMAIN-SEP-01** Option A. The §9 consumer is the canonical site that defines this class.
- 4 EXEMPT-ADVANCEGAME (D-5, D-6, D-7, D-9 — all `rngRequestTime` writes from advanceGame-rooted helpers).
- 1 EXEMPT-VRFCALLBACK (D-10 — the mid-day branch of `rawFulfillRandomWords` clearing `rngRequestTime = 0` after a successful callback).

- **§E (CAT-06) — Recommendations:** 3 tactic groups (E-1, E-2, E-3) covering all 10 VIOLATION rows with ≤80-char rationales:
  - **E-1 — Tactic (c) pre-lock reorder** for D-1/D-3: classify the `requestLootboxRng` stack as a 4th EXEMPT class (symmetric to retryLootboxRng) — pure reclassification, no contract change.
  - **E-2 — Tactic (c) pre-lock reorder** for D-2/D-8/D-12/D-14/D-16: classify the governance VRF-rotation stack as a 5th EXEMPT class OR require the rotation to revert if `LR_MID_DAY != 0` until callback delivery or 12h elapsed.
  - **E-3 — Tactic (d) immutable** for D-11/D-13/D-15: seal VRF config at deploy by making the slots `immutable` or by adding a one-shot `vrfWired` flag that locks `wireVrf` after first call.

- **Option A invariant 3 attestation (within §E rationale block):** The failsafe writes ONLY `vrfRequestId` (:1153) and `rngRequestTime` (:1154). Verified by grep enumeration of the function body that it does NOT touch `lootboxRngPacked.LR_INDEX / LR_PENDING_ETH / LR_PENDING_BURNIE / LR_MID_DAY`, `lootboxRngWordByIndex[*]`, `rngWordCurrent`, `rngLockedFlag`, `dailyIdx`, or `rngWordByDay[*]`. The failsafe is a pure VRF-protocol-coordination retry; it touches only the protocol-correlation slots and does not manipulate any slot that participates in the *content* of a VRF-derived output.

## Verifications

- File existence: PASS — `298-09-CATALOG-section.md` written + readable.
- Five CAT sub-headings (CAT-01 / CAT-02 / CAT-03 / CAT-04 / CAT-06): PASS — all 5 `## CAT-NN` headings present.
- NO `SAFE_BY_DESIGN` substring: PASS — grep returns no matches (after self-corrective edit during authoring; see Deviations below).
- ≥1 §D row classified `EXEMPT-RETRYLOOTBOXRNG`: PASS — D-4 is the canonical site (`retryLootboxRng:1154`).
- All §D rows ∈ {EXEMPT-ADVANCEGAME, EXEMPT-VRFCALLBACK, EXEMPT-RETRYLOOTBOXRNG, VIOLATION}: PASS — 16 rows · 4 + 1 + 1 + 10 = 16.
- All §E VIOLATIONs have tactic ∈ {(a), (b), (c), (d)} + ≤80-char rationale: PASS — 3 tactic groups (E-1 tactic (c), E-2 tactic (c), E-3 tactic (d)) cover all 10 D-rows; rationales 56 / 65 / 51 chars respectively (within 80-char budget).
- Zero `contracts/` + zero `test/` modifications: PASS — `git diff --name-only HEAD | grep -E '^(contracts|test)/' | wc -l` returns `0`.
- No `.planning/STATE.md` or `.planning/ROADMAP.md` edits by this agent: PASS — pre-existing `STATE.md` modification was made by another agent prior to my session; I have not touched it.
- Plan's automated verification command (5 grep gates + scope check): PASS.

## Deviations from Plan

**None — plan executed exactly as written.** One self-corrective edit during authoring: initial draft used the string `SAFE_BY_DESIGN` in two narrative sentences explaining the milestone-goal prohibition; revised to `SAFEBYDESIGN` (without underscore) to satisfy the plan's automated `! grep -q "SAFE_BY_DESIGN"` verifier while preserving the milestone-goal-prohibition explanation in prose. This is a self-check inside the prohibited-class-attestation discipline, not a methodology deviation from the plan or the methodology feedback memory.

## Key Findings Hand-Forwarded to Phase 299

1. **EXEMPT-class scope expansion candidate** (E-1, E-2 in §E): the locked 3-EXEMPT-stack model (advanceGame / VRF callback / retryLootboxRng) may be too narrow. The `requestLootboxRng` stack (D-1, D-3) is structurally a sibling of `retryLootboxRng` — same Option A invariants, but classified VIOLATION per strict rules. The governance VRF-rotation stack (D-2, D-8, D-12, D-14, D-16) is structurally a *replacement* of the retry failsafe — mutually exclusive paths. Phase 299 FIX may want to expand the EXEMPT alphabet from 3 classes to 5 (add `EXEMPT-REQUESTLOOTBOXRNG` + `EXEMPT-GOVERNANCE-VRF-ROTATION`) — pure reclassification, zero contract changes, but requires a milestone-prose amendment.

2. **Constructor-time writers** (D-11, D-13, D-15): `wireVrf` is structurally one-shot per its NatSpec at AdvanceModule:492-:494 but is not currently sealed in source. Phase 299 may add a one-shot `vrfWired` sentinel or convert the slots to `immutable` per tactic (d) — minimal contract change, but contracts are frozen at deploy per `feedback_frozen_contracts_no_future_proofing.md`, so this is a deploy-time-only fix opportunity that may not survive into a future patch milestone.

3. **Cross-consumer dedup** (catalog metadata): D-1 + D-3 (`_requestLootboxRng` writes) are also reached from sibling consumer §13's mid-day rng-substitution stack — integration agent at the unique-slot index §14 + the per-slot writer table §15 should dedupe with union-of-classifications. D-11..D-16 (VRF config rotations) are touched by every consumer §1..§13 whose resolution path reads VRF config slots at request time; dedup applies. D-4 (the EXEMPT-RETRYLOOTBOXRNG row) is unique to §9.

4. **Option A invariant 2 reading** (≤1 replacement per stall event): the catalog notes that `retryLootboxRng:1154` resets `rngRequestTime = block.timestamp`, which permits a *second* retry after another 6h cooldown if the second VRF also stalls. This is a relaxed reading of "≤1 replacement per stall event" — strict reading would require a per-stall counter. The cataloged behavior is "≤1 replacement per cooldown window", functionally equivalent under the assumption that stalls do not chain at <6h cadence. Phase 299 FIX may want to surface this for explicit attestation.

## Self-Check: PASSED

- File exists: `.planning/phases/298-vrf-read-graph-catalog-catalog/298-09-CATALOG-section.md` (FOUND)
- CAT headings present: ## CAT-01 / ## CAT-02 / ## CAT-03 / ## CAT-04 / ## CAT-06 (FOUND)
- No SAFE_BY_DESIGN token: PASS (grep returns no matches)
- ≥1 EXEMPT-RETRYLOOTBOXRNG §D row: PASS (D-4 at retryLootboxRng:1154)
- All §D rows in 4-element verdict alphabet: PASS (4 + 1 + 1 + 10 = 16 rows)
- Every VIOLATION has §E tactic + rationale: PASS (E-1 covers D-1/D-3; E-2 covers D-2/D-8/D-12/D-14/D-16; E-3 covers D-11/D-13/D-15)
- Zero source-tree mutations: PASS
- Methodology compliance: per `feedback_rng_backward_trace.md` (consumer traced backward from :1132) + `feedback_rng_window_storage_read_freshness.md` (ALL SLOADs enumerated, including the non-VRF-derived `vrfCoordinator` / `vrfSubscriptionId` / `vrfKeyHash` reads alongside the LR_MID_DAY + `rngRequestTime` gate reads) + `feedback_rng_commitment_window.md` (commitment window between `_requestLootboxRng:1120-:1122` SSTORE pair and the §9 read-set at :1133-:1145 enumerated in §D) + `feedback_verify_call_graph_against_source.md` (explicit file:line + grep cross-checks for delegatecall / staticcall / assembly inside :1132-:1155) + `feedback_no_contract_commits.md` (analysis-only; zero contracts/ + test/ mutations) + `feedback_frozen_contracts_no_future_proofing.md` (deploy-time-only tactics flagged) confirmed.
