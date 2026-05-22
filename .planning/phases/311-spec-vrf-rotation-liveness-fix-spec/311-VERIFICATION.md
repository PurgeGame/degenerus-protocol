---
phase: 311-spec-vrf-rotation-liveness-fix-spec
verified: 2026-05-22T21:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
resolution:
  - item: "VRF-01..05 were flipped [ ]->[x] (traceability -> Complete) by the 311-02 executor at commit 30e305e6 — a premature runtime-complete claim for a SPEC-only phase."
    action_taken: "Orchestrator reverted VRF-01..05 to [ ] and traceability to Pending. These are runtime guarantees delivered at Phase 312 (IMPL) and proven by VTST-01..04 at Phase 313 (TST); Phase 311 only LOCKS the design. State is now consistent with the binary table convention (VRF Pending <-> VTST Pending) and the 311-01 executor's deliberate choice. Reversible to 'design-closed' semantics if the project later prefers that convention."
---

# Phase 311: SPEC — VRF-Rotation Liveness Fix — Verification Report

**Phase Goal:** Lock the VRF-rotation fix design BEFORE any contract change and grep-verify the call-graph. Produce `311-SPEC.md` covering the design-intent backward-trace of `updateVrfCoordinatorAndSub` + `wireVrf` across Scenario A + Scenario B; the LOCKED fix shape (re-issue-in-flight, D-01/D-02); the wireVrf one-shot lock (VRF-04); and a vault-routed reach trace (VRF-05). Every cited file:line grep-verified against contract HEAD; zero by-construction claims; zero `contracts/` + zero `test/` mutations.
**Verified:** 2026-05-22T21:00:00Z
**Status:** passed (the one human-judgment item was resolved by the orchestrator — see Resolution below)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria → must_haves)

| # | Truth (ROADMAP SC) | Status | Evidence |
|---|--------------------|--------|----------|
| 1 | `311-SPEC.md` exists with a design-intent backward-trace of `updateVrfCoordinatorAndSub` + `wireVrf` across Scenario A + Scenario B, and the LOCKED fix shape (re-issue-in-flight vs queue+apply) chosen with rationale | VERIFIED | 718-line `311-SPEC.md` confirmed. §1 covers both scenarios: §1.3 Scenario A (same-day advance → entropy-0 traits via MintModule:686) + §1.4 Scenario B (next-day → drain-gate revert at :213/:238/:271 → ~120d freeze). §2 locks re-issue-in-flight D-01/D-02 with explicit rationale vs queue+apply (§2.4, §6.1). All assertions cite §0 rows. |
| 2 | The design closes the orphan-index defect — VRF-01 (real VRF word lands in `lootboxRngWordByIndex[N]`) + VRF-02 (post-rotation liveness — `requestLootboxRng`/`retryLootboxRng`/daily-drain reachable) specified precisely | VERIFIED | §2.2 specifies the three-case preserve+re-issue design (daily/mid-day/nothing-in-flight). §2.3 traces VRF-01 closure (real word lands at :1772 via unchanged mid-day fulfillment branch; old word abandoned by :1761 guard) and VRF-02 closure (gate un-block per §5.1). §5 traces full backfill reachability with CONCLUSION: CONFIRMED-COVERED. |
| 3 | The freeze-invariant disposition is locked — no VRF-participating slot mutated mid-window in a way that changes an in-flight VRF-derived output (VRF-03 closing HANDOFF-78/85/87/89/91); validator-influenceable entropy backfill explicitly rejected | VERIFIED | §3.1 enumerates all VRF-participating slots (§0.C rows). §3.2 shows no consumed-this-cycle output changes (old word abandoned, new word unpredictable, admin rotation EXEMPT-class). §3.3 explicitly rejects block.timestamp/newKeyHash/blockhash/caller-supplied entropy per `feedback_security_over_gas`; only keccak-of-a-real-VRF-word (:1817) sanctioned. §3.4 addresses MintModule:686 zero-guard absence via structural guarantee. |
| 4 | The `wireVrf` one-shot lock is specified (VRF-04 closing HANDOFF-86/88/90 + ADMA-01) and the vault-routed reach backward-traced (VRF-05 / ADMA-02) | VERIFIED | §4.1 specifies D-03 one-shot lock with chosen detection mechanism (address(vrfCoordinator) != address(0)) + rationale (§0.Y confirms single constructor call, no re-wire init flow). §4.2 specifies D-04 `_setVrfConfig` dedup (3-field write only; `:509` stays inline). §4.3 traces VRF-05 using §0.Y actual dispatch sites (DegenerusAdmin.sol:458/:901 + DegenerusGame.sol:308/:1874); confirms DegenerusVault.sol has zero VRF dispatch. |
| 5 | Every cited file:line grep-verified against contract HEAD; each §9d VRF-cluster anchor mapped to a closing change; zero by-construction claims; zero contract/test mutations | VERIFIED | §0 manifest covers 23 AdvanceModule sites + MintModule:686 + 7 Storage slots — all VERIFIED or DRIFTED (ADMA-02 +11 drift recorded). §0.X maps all 10 cluster anchors (HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02) to D-01..D-05 + VRF-01..05. §0.H attestation: zero by-construction claims. `git diff --quiet -- contracts/ test/` returns clean. 4 task commits confirmed: d43dc8b2, d2826eb6, d27e8afd, b2c9ab2c. |

**Score: 5/5 truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` | Complete VRF-rotation fix SPEC: §0 manifest + §1–§7 design narrative | VERIFIED | 718 lines. §0 through §7 all present and authored. Zero "authored in Plan 02" placeholders remain (grep count: 0). All must_haves sections present. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| 311-SPEC.md §0 manifest | `contracts/modules/DegenerusGameAdvanceModule.sol` | grep-verified line citations | VERIFIED | `wireVrf:498`, `updateVrfCoordinatorAndSub:1688`, `requestLootboxRng:1044`, `retryLootboxRng:1133`, `rawFulfillRandomWords:1756`, `_backfillOrphanedLootboxIndices:1208/:1817`, drain-gate `:213/:238/:271` — all re-grepped against HEAD and confirmed. ADMA-02 drift (+11 lines, :1677→:1688) recorded, not silently propagated. |
| 311-SPEC.md §0.X mapping table | `audit/FINDINGS-v44.0.md` §9d cluster | anchor → closing-change rows | VERIFIED | All 10 anchors present: HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02. Each maps to decision ID (D-01..D-05) + requirement (VRF-01..05) + §9d.2/:9d.4 source row. |
| 311-SPEC.md §0.Y vault-reach trace | `contracts/DegenerusAdmin.sol` + `contracts/DegenerusGame.sol` | dispatch site enumeration | VERIFIED | DegenerusAdmin.sol:458 (constructor wireVrf) + :901 (_executeSwap updateVrfCoordinatorAndSub). DegenerusGame.sol:308 (wireVrf delegatecall) + :1874 (updateVrfCoordinatorAndSub delegatecall). DegenerusVault.sol confirmed zero VRF dispatch. CONTEXT "DegenerusVault" naming drift reconciled. |
| 311-SPEC.md §2 fix shape | VRF-01 + VRF-02 closure | re-issue lands real word in `lootboxRngWordByIndex[N]` + preserves liveness | VERIFIED | §2.2 mid-day re-issue → :1772 write (§0.F Mid-day row). Old word abandoned by :1761 guard. §5.1 drain-gate un-block traced. `lootboxRngWordByIndex` appears throughout §2/§5. |
| 311-SPEC.md §5 reachability trace | `:1208` `_backfillOrphanedLootboxIndices` call + `:269`/:271 drain gate | re-issue un-blocks gate → backfill reachable + escalation clause | VERIFIED | §5.1 traces both mid-day and daily re-issue drain-gate un-block paths. §5.3 records CONCLUSION: CONFIRMED-COVERED. Escalation NOT triggered. `_backfillOrphanedLootboxIndices` appears in §5 with cite to §0.A :1208/:1817 rows. |

---

### Data-Flow Trace (Level 4)

Not applicable — this is a SPEC (design-document) phase. The deliverable is a document, not runtime code. Artifact Level 4 applies to components rendering dynamic data; the SPEC renders static design prose.

---

### Behavioral Spot-Checks

Step 7b SKIPPED — no runnable entry points. This is a SPEC-only phase (zero `contracts/` mutations, zero `test/` mutations). Spot-checks require executable code paths.

---

### Probe Execution

No probes declared in PLAN.md or SUMMARY.md. Step 7c SKIPPED.

---

### Requirements Coverage

| Requirement | Source Plan | Description (abbreviated) | Status | Evidence |
|-------------|-------------|----------------------------|--------|----------|
| VRF-01 | 311-01 + 311-02 | Orphaned `lootboxRngWordByIndex[N]` resolves to real VRF word after rotation | DESIGN-CLOSED (runtime proof via VTST-01 @ Phase 313) | §2.2/§2.3: mid-day re-issue → :1772 fill; old word abandoned by :1761 guard; MintModule:686 reads non-zero entropy |
| VRF-02 | 311-01 + 311-02 | Post-rotation liveness — `requestLootboxRng`/`retryLootboxRng`/daily-drain reachable | DESIGN-CLOSED (runtime proof via VTST-02 @ Phase 313) | §2.3: flags preserved, drain-gate un-blocked per §5.1; retryLootboxRng remains failsafe |
| VRF-03 | 311-01 + 311-02 | Freeze invariant — no VRF slot mutated mid-window in freeze-breaking way (HANDOFF-78/85/87/89/91) | DESIGN-CLOSED (runtime proof via VTST-03 @ Phase 313) | §3: all slots enumerated; re-issue freeze-safe (old word abandoned, new unpredictable, admin EXEMPT); validator backfill rejected |
| VRF-04 | 311-01 + 311-02 | wireVrf one-shot lock (HANDOFF-86/88/90 + ADMA-01) | DESIGN-CLOSED (runtime proof via VTST-04 @ Phase 313) | §4.1: D-03 address(vrfCoordinator)!=address(0) detection; updateVrfCoordinatorAndSub becomes SOLE post-init mutator |
| VRF-05 | 311-01 + 311-02 | Rotation + wire protections cover vault-routed admin dispatch (ADMA-02) | DESIGN-CLOSED (runtime proof via VTST-04 @ Phase 313) | §4.3: guards at delegatecall targets (:498/:1688) downstream of all wrappers; no DegenerusVault bypass (§0.Y) |

**Note on VRF-01..05 checkbox state in REQUIREMENTS.md:** The executor flipped these from `[ ]` to `[x]` at commit `30e305e6`. See Human Verification Required below.

---

### Spot-Check: §0 Manifest Anchor Re-verification (Selected)

The following anchors were re-grepped by the verifier against `contracts/` HEAD to confirm the SPEC's VERIFIED claims hold:

| SPEC Claim | Re-grep Result | Matches |
|------------|----------------|---------|
| `wireVrf` at AdvanceModule:498 | `grep -n "function wireVrf"` → line 498 | CONFIRMED |
| `updateVrfCoordinatorAndSub` at AdvanceModule:1688 | `grep -n "function updateVrfCoordinatorAndSub"` → line 1688 | CONFIRMED |
| Force-unlock block at :1701-1704 | `sed -n '1700,1714p'` → `rngLockedFlag = false` at :1701, `vrfRequestId = 0` at :1702, `rngRequestTime = 0` at :1703, `rngWordCurrent = 0` at :1704 | CONFIRMED |
| `LR_MID_DAY` clear at :1709 | Line 1709 is `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)` | CONFIRMED |
| `totalFlipReversals` carry-over comment at :1711-1714 | "Intentional: totalFlipReversals is NOT reset here" present at :1711 | CONFIRMED |
| `rawFulfillRandomWords` at :1756; daily branch :1768; mid-day branch :1772 | `sed -n '1756,1778p'` → daily write `rngWordCurrent = word` at :1768, mid-day write `lootboxRngWordByIndex[index] = word` at :1772 | CONFIRMED |
| MintModule:686 entropy read with NO zero-guard | `sed -n '683,695p'` → `uint256 entropy = lootboxRngWordByIndex[...] - 1]` at :686, no `== 0` check before `_processOneTicketEntry` | CONFIRMED |
| `_backfillOrphanedLootboxIndices` call at :1208 | `sed -n '1204,1212p'` → call present at line 1208 | CONFIRMED |
| `_backfillOrphanedLootboxIndices` definition at :1817; keccak at :1826 | `sed -n '1815,1830p'` → function at :1817, `keccak256(abi.encodePacked(vrfWord, i))` at :1826 | CONFIRMED |
| `requestLootboxRng` at :1044; LR_MID_DAY gate at :1048 | `grep -n "function requestLootboxRng"` → :1044; `sed -n '1044,1052p'` → `if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert E()` at :1048 | CONFIRMED |
| `_setVrfConfig` — TO-BE-CREATED (zero matches) | `grep -n "_setVrfConfig" contracts/modules/DegenerusGameAdvanceModule.sol` → zero matches | CONFIRMED |
| DegenerusVault.sol — zero VRF admin dispatch | `grep -n "wireVrf\|updateVrfCoordinatorAndSub\|gameAdmin" contracts/DegenerusVault.sol` → zero matches | CONFIRMED |
| DegenerusAdmin.sol dispatch sites :458 + :901 | `grep -n "wireVrf\|updateVrfCoordinatorAndSub"` → interface decls at :99/:109, call at :458, call at :901 | CONFIRMED |
| DegenerusGame.sol dispatch sites :308 + :1874 | `grep -n "wireVrf\|updateVrfCoordinatorAndSub"` → :308 + :1874 | CONFIRMED |

All spot-checked anchors match the SPEC's VERIFIED claims. Drain-gate CONTEXT/SPEC drift (CONTEXT cited :238/:269; SPEC refined to :213/:238/:271) also confirmed correct at source.

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| 311-SPEC.md | None | — | No TBD/FIXME/XXX/TODO/PLACEHOLDER markers. No stub patterns. This is a design document; the only "TO-BE-CREATED" marker is `_setVrfConfig` in §0.D, which is correctly labeling a future artifact, not deferring work undone. |
| contracts/ and test/ | No modifications | — | `git diff --quiet -- contracts/ test/` is clean. The zero-mutation invariant holds. |

---

### Locked Decision Integrity (CONTEXT D-01..D-05)

All five locked decisions verified carried forward without silent reversal:

| Decision | CONTEXT requirement | §SPEC treatment | Status |
|----------|---------------------|-----------------|--------|
| D-01 re-issue on new coordinator | LOCKED | §2.1: re-issue mechanic specified (mirrors retryLootboxRng :1143); fresh vrfRequestId + rngRequestTime=block.timestamp | HONORED |
| D-02 preserve+re-issue both paths | LOCKED | §2.2: three cases (daily/mid-day/nothing-in-flight) each specified | HONORED |
| D-03 wireVrf init-only lock | LOCKED (detection = SPEC discretion) | §4.1: chosen address(vrfCoordinator)!=address(0) with rationale (no re-wire init flow in §0.Y) | HONORED |
| D-04 _setVrfConfig shared internal | LOCKED (signature/visibility = SPEC discretion) | §4.2: internal _setVrfConfig(coord, sub, key) collapsing 3-field write; :509 lastVrfProcessedTimestamp stays inline; TO-BE-CREATED per §0.D | HONORED |
| D-05 narrow + verify reachability | LOCKED (escalation clause = sanctioned reversal path) | §5: full reachability trace, CONCLUSION: CONFIRMED-COVERED, escalation NOT triggered | HONORED |
| totalFlipReversals preserve | LOCKED | §2.5: carry-over preserved, :1711-1714 untouched | HONORED |

---

### Human Verification — RESOLVED (orchestrator, 2026-05-22)

#### 1. VRF-01..05 Checkbox State in REQUIREMENTS.md — RESOLVED

**Resolution:** The orchestrator reverted VRF-01..05 to `[ ]` (and traceability status `Complete` → `Pending`) at the corrective commit. These are runtime guarantees delivered at Phase 312 (IMPL) and proven by VTST-01..04 at Phase 313 (TST) — Phase 311 only LOCKS the design — so the accurate state is `[ ]`/Pending, consistent with the binary table convention (VRF Pending ↔ VTST Pending) and the 311-01 executor's deliberate choice. Reversible to "design-closed" semantics if the project later prefers that. The original finding is preserved below for the audit trail.

**Test:** Inspect REQUIREMENTS.md lines 51-55 (the `[x] **VRF-01..05**` checkboxes) and decide whether the `[x]` state is appropriate for a SPEC-only phase or should remain `[ ]` until Phase 313 VTST proves them at runtime.

**Expected:** One of two outcomes:
- (A) If `[x]` is intentional design-closure marking: add a note such as `<!-- design-closed Phase 311; runtime proven by VTST-01 @ Phase 313 -->` immediately after each checkbox line, or accept the current state knowing the traceability table's "proven by VTST-NN" wording preserves the dependency chain.
- (B) If `[x]` is premature: revert lines 51-55 to `[ ]` and plan to re-flip after VTST-01..04 pass at Phase 313.

**Why human:** The `phase_type_critical` instruction says "confirm REQUIREMENTS.md was NOT falsely flipped to complete." The executor flipped VRF-01..05 from `[ ]` to `[x]` at commit `30e305e6` (the plan-metadata commit). The traceability table still correctly says "proven by VTST-NN" and VTST-01..04 remain `[ ]` Pending — so the dependency chain is auditable. Whether the checkbox flip constitutes a "false complete" vs an intentional "design-closed" marking is a human judgment call. If left as-is, Phase 313 verifier will need to know these were flipped at Phase 311 SPEC, not at Phase 313 TST.

---

## Gaps Summary

No gaps block the phase goal. All five ROADMAP Success Criteria are satisfied by the SPEC content. The one human-judgment item (REQUIREMENTS.md checkbox semantics) was resolved by the orchestrator — VRF-01..05 reverted to `[ ]`/Pending (design-locked at 311; runtime-proven at 312/313). The SPEC is complete and unambiguous as the Phase 312 IMPL input.

---

## SPEC Completeness Summary

`311-SPEC.md` is a substantive, self-consistent 718-line design document:

- §0 Call-Graph Manifest (grep-verified): 23 AdvanceModule anchors + MintModule:686 + 7 Storage slots — all VERIFIED or DRIFTED (with delta recorded). Four `requestRandomWords` call sites enumerated individually. Daily/mid-day fulfillment branch boundary explicit. ADMA-02 line drift (+11) recorded. DegenerusVault naming drift reconciled. TO-BE-CREATED `_setVrfConfig` correctly flagged.
- §0.X: all 10 §9d cluster anchors (HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02) mapped to D-01..D-05 + VRF-01..05 with §9d source row citations and maximalist-catalog framing.
- §0.Y: actual vault/admin-routed dispatch verified (DegenerusAdmin.sol:458/:901 + DegenerusGame.sol:308/:1874); naming drift from CONTEXT's "DegenerusVault" reconciled.
- §1: design-intent backward-trace of both functions + both scenarios (Scenario A entropy-0 HIGH, Scenario B ~120d freeze) citing precise revert lines :213/:238/:271.
- §2: re-issue-in-flight fix shape locked (D-01/D-02) with three-case branch structure, freeze-safety narrative, VRF-01/VRF-02 closure explanation, rejected-alternative rationale, totalFlipReversals preservation.
- §3: freeze-invariant disposition (VRF-03) with all slots enumerated, no consumed-this-cycle change shown, validator backfill explicitly rejected, :1817 keccak-of-VRF-word as sole sanctioned entropy source.
- §4: wireVrf one-shot lock (D-03/VRF-04) with chosen detection mechanism + rationale; `_setVrfConfig` dedup (D-04/VRF-05) with scope boundary precision (:509 stays inline); vault-routed reach disposition using §0.Y actual sites.
- §5: D-05 orphan-recovery reachability trace with CONCLUSION: CONFIRMED-COVERED; escalation evaluated and NOT triggered; ≤1-orphan bound per rotation established.
- §6: both rejected options documented with rationale (queue+apply pendingVrfRotationPacked; belt-and-suspenders backfill).
- §7: self-check passes all six obligation assertions.

Zero contracts/ + zero test/ mutations confirmed.

---

_Verified: 2026-05-22T21:00:00Z_
_Verifier: Claude (gsd-verifier)_
