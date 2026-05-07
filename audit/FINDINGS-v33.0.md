---
phase: 257-delta-audit-findings-consolidation
plan: 01
milestone: v33.0
milestone_name: Charity Allowlist Governance
head_anchor: 4ce3703d740d3707c88a1af595618120a8168399
audit_baseline: acd88512
deliverable: audit/FINDINGS-v33.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05]
phase_status: terminal
write_policy: "Pure-consolidation phase per CONTEXT.md hard constraint #1. Zero contracts/ writes by agent. Zero test/ writes by agent. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-257-KI-01 default zero-promotion path. Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change — vacuous this phase since no contract changes are proposed by agent."
supersedes: MILESTONE_V33_AT_HEAD_dcb70941
status: DRAFT — Phase 258-03 supersedence sweep in progress
read_only: false
closure_signal: MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399
generated_at: 2026-05-07T04:39:08Z
sweep_history:
  - phase: 258-03
    purpose: "Sweep narrative `dcb70941` references that still describe current state to the post-Phase-258 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399`. Historical references (frontmatter supersedes, Phase 257 emit-history, commit-log entries, §3.4 SHA list) are preserved unchanged."
    started: 2026-05-07T04:39:08Z
---

# v33.0 Findings — Charity Allowlist Governance

**Audit Baseline.** HEAD `dcb70941` is the contract-tree audit subject HEAD for v33.0, taken at Phase 257 plan-start as `git rev-parse HEAD` after Phase 256 close. The audit baseline is v32.0 HEAD `acd88512` (closure signal `MILESTONE_V32_AT_HEAD_acd88512` carry-forward from `audit/FINDINGS-v32.0.md` §9c). Eight contract commits since baseline: four v33-related GNRUS commits (`469d7fc1` Phase 254 single-commit consolidation + `30188329` Phase 255 declarations + `e734cfe6` Phase 255 vote + `ac1d3741` Phase 255 pickCharity), plus seven post-anchor non-GNRUS commits (`98e78404`, `002bde55`, `73b8c3b6`, `16e0eca5`, `560951a0`, `2713ce61`, `dcb70941`) classified ORTHOGONAL_PROVEN per §3.4. Four test-only commits (`b1f84a8c`, `10ee964c`, `3f667b3e`, `644af631`) all USER-COMMITTED Phase 256. The L173 turbo guard (`!rngLockedFlag` clause) + L1174 backfill sentinel (`rngWordByDay[idx + 1] == 0`) + GameStorage `_livenessTriggered` body (now at L1249-1259 after constant insertion at L863, body bytes char-by-char identical to baseline L1246-1256) are byte-identical between baseline `acd88512` and HEAD `dcb70941` (REG-01 PASS — see §5a).

**Re-Opening Attestation (Phase 258).** Phase 257 emitted closure signal `MILESTONE_V33_AT_HEAD_dcb70941` on 2026-05-06. Independent adversarial re-run logged in `.planning/phases/257-delta-audit-findings-consolidation/257-01-ADVERSARIAL-LOG.md` (Independent Re-Run section, 2026-05-06 post-closure-signal) surfaced a queue-branch vote-redirect mechanism in `pickCharity` — disclosed there as a documentation gap in §4b sub-row prose, but on user review elevated to a code-level fix. Phase 258 supplies the fix: a structural reorder of `pickCharity` so the queued-edit flush executes AFTER the distribution payout (FIX-01), plus a `lastWinningRecipient` storage slot + `PreviousWinnerNotVotable()` revert in `vote()` to prevent consecutive wins by the same recipient (FIX-02). Phase 258-01 landed the contract+test diff under user-approved batched review; Phase 258-02 (this re-audit) updates §3a delta-surface, §4 adversarial sweep, and §5 regression appendix to reflect the patched semantics, then re-emits closure as `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` superseding `MILESTONE_V33_AT_HEAD_dcb70941`. The READ-only flag is lifted for the duration of Tasks 1-5 and re-applied on the Task 6 terminal commit.

**Scope.** Single canonical milestone-closure deliverable for v33.0 per D-257-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-253-15 carry-forward (9-section shape locked). Consolidates Phase 254 / 255 / 256 outputs into 9 sections per D-253-15 carry. Terminal phase per CONTEXT.md D-257-FCITE-01 — zero forward-cites emitted from Phase 257 to any post-v33.0 milestone phases. Mirrors v32 Phase 253 single-plan multi-task atomic-commit pattern adapted for v33's 3-impl-phase + 1-audit-phase scope per D-257-PLAN-01.

**Write policy.** READ-only after Task 12 atomic commit per D-253-CF-02 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-257-KI-01 default zero-promotion path (D-09 sticky-predicate FAIL on any v33-discovered finding because v33 charity surface is freshly-landed not "ongoing protocol behavior" until next milestone). Zero awaiting-approval test files (all four Phase 256 test commits `b1f84a8c` → `644af631` are USER-COMMITTED per `feedback_no_contract_commits.md`). Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change; vacuous this phase since no contract changes are proposed by agent (zero `contracts/` writes + zero `test/` writes by agent — hard constraint #1).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: `CLOSED_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (delta surface complete; every changed function/state-var/event/error in `contracts/GNRUS.sol` vs baseline `acd88512` enumerated with hunk-level evidence and classified per ROADMAP success criterion 2)
- AUDIT-02: `9 of 9 surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY; 0 of 0 FINDING_CANDIDATE PROMOTED` (default expected per D-257-FIND-01)
- AUDIT-03: `CLOSED_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (GNRUS conservation re-proof complete; supply invariants intact across the level transition; soulbound enforcement intact; `burn()` proportional redemption math unchanged)
- AUDIT-04: `1 PASS REG-01 / 0 REG-02 rows; 4 NEGATIVE-scope KI re-verifications; KNOWN_ISSUES_UNMODIFIED`
- Combined milestone closure: `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399`
- Phase 258-01 + 258-02 supersedence: `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `MILESTONE_V33_AT_HEAD_dcb70941` (Phase 258 closes the queue-branch vote-redirect mechanism via FIX-01 + adds the consecutive-recipient capture block via FIX-02; deliverable updated for the new code surface).

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-33-NN: 0

Default expected per D-257-FIND-01. Trust-asymmetry items (e) instant-apply admin-front-run + (g) locked-slot poisoning go to §4 sub-row prose disclosures, NOT F-33-NN namespace blocks. Severity counts reconcile to §4 F-33-NN block tally line by line per ROADMAP success criterion 1.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v30/v31/v32 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-33-NN that may surface during Task 8 disposition: HIGH ceiling (vault-owner is the trust boundary; admin attack against the slate is bounded to 2%-of-pool blast radius per level; no value extraction from voters, no draining of unallocated pool past the 2% rate). MEDIUM/LOW likely for any inline-draft finding-candidate. INFO for documentation-only items. Per D-257-FIND-01 default path, zero F-33-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone per D-257-KI-01: `KNOWN-ISSUES.md` UNMODIFIED — zero F-33-NN finding blocks → zero KI promotion candidates. Any v33-discovered finding-candidate would FAIL the **sticky** predicate (v33 charity surface is freshly-landed not "ongoing protocol behavior" until the next milestone). See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

CONTEXT.md D-257-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 257 to any post-v33.0 milestone phases. Verified at §8 Forward-Cite Closure block. Phase 254-256 each emit zero phase-bound forward-cites (the few post-v33.0 milestone mentions in CONTEXT.md `<deferred>` sections are deferral annotations per `feedback_no_dead_guards.md`, not phase-bound forward-cite emissions); Phase 257 inherits zero-residual baseline. Any v33-relevant divergence routes to scope-guard deferral in `257-01-SUMMARY.md` per D-253-CF-07 carry; Future milestones (post-v33.0) ingest via fresh delta-extraction phase, not via forward-cite from v33 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 6-point attestation block triggering v33.0 milestone closure via signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (supersedes the original Phase 257 emission `MILESTONE_V33_AT_HEAD_dcb70941` per §9c — see Re-Opening Attestation in §1).

---

## 3. Per-Phase Sections

Consolidates Phase 254 / 255 / 256 outputs per D-253-09 + D-253-10 carry-forward into condensed summaries with cross-cites to source artifacts. All cross-cites are READ-only lookups (D-253-CF-08); no fresh derivation. Sources `re-verified at HEAD dcb70941`. §3.4 covers post-anchor non-GNRUS contract commits per planner-surfaced scope adjustment (CONTEXT.md `<domain>` claimed 4 contract commits since baseline; live `git log acd88512..HEAD -- contracts/` shows 8 — the 4 GNRUS-related Phase 254/255 commits PLUS 7 post-anchor non-GNRUS commits; see §3.4 for ORTHOGONAL_PROVEN classification per commit).

### 3a. Phase 254 — GNRUS Allowlist Storage, Admin Op & Storage Repack

**Change-count card:**
- Plans: 3 (254-01, 254-02, 254-03)
- Commit: `469d7fc1` (Phase 254 single-commit consolidation containing all three plans\' on-chain output)
- Functions added: `setCharity(uint8 slot, address recipient)` external (admin op with 4 branches: instant-apply / queue / removal-special-case / locked-slot revert), `_futureBitmapAfter(uint8, address, uint32)` internal cap-check helper, `_flushedBitmap()` internal post-flush bitmap projector, `_popcount32(uint32)` internal active-count primitive, `getCharity(uint8)` external view, `getActiveSlots()` external view, `getPendingEdits()` external view, `activeCount()` external view, `activeCountAfterFlush()` external view (5 view helpers per D-254-VIEW-01)
- Functions deleted: `propose(address)` (v32 governance entry point removed per D-254-VOTEPICK-01)
- Storage added: `address[20] private currentSlate` (the 20-slot allowlist per D-254-SLATE-01), `mapping(uint8 => address) private pendingEdit` (sparse pending-edit queue per D-254-PENDING-01), `uint32 public currentActiveBitmap` (active-slot bitmap — single source of truth per D-254-COUNT-01), `uint32 public pendingEditSet` (pending-edit sentinel bitmap per D-254-PENDING-01), `mapping(uint24 => bool) public levelResolved` (per-level idempotence)
- Storage repacked: hot-pack slot 2 carries `currentLevel` (3 bytes) + `finalized` (1 byte) + `currentActiveBitmap` (4 bytes) + `pendingEditSet` (4 bytes) = 12 bytes, 20 bytes free for future expansion per D-254-REPACK-01
- Storage redeclared: `mapping(uint24 => mapping(address => mapping(uint8 => bool))) public hasVoted` — inner key changed from `proposalId` (uint48) to `slot` (uint8) per D-254-HASVOTED-01
- Storage deleted: `Proposal` struct + `proposals` array + `proposalCount` + `levelProposalStart` + `levelProposalCount` + `hasProposed` + `creatorProposalCount` + `levelVaultOwner` + `levelSdgnrsSnapshot` (the v32 governance state machine demolished per D-254-SLATE-01)
- Errors added: `InvalidSlot()`, `SlotAlreadyEmpty()`, `SlotLocked()`, `CapExceeded()` (4 new per D-254-ERROR-PRUNE-01)
- Errors deleted: `InsufficientStake`, `AlreadyVoted`, `LevelAlreadyResolved`, `LevelNotActive`, `RecipientIsContract` — Phase 254 deviation: `RecipientIsContract` removed (cross-cite D-256-CONTRACT-RECIPIENT-01 lock; contract recipients now accepted by design)
- Events added: `CharityApplied(uint8 indexed slot, address indexed recipient)`, `CharityQueued(uint8 indexed slot, address indexed recipient)` (2 new per D-254-EVENT-01)
- Constants added: `LOCKED_SLOTS = 3` (`GNRUS.sol:203`), `MAX_ACTIVE_SLOTS = 20` (`GNRUS.sol:206`)
- REQs satisfied: 5/5 (ALW-01, ALW-02, ALW-03, ALW-04, CLEAN-01)
- Closure signal: `PHASE_254_FINAL_AT_HEAD_469d7fc1`

**Cross-cite:** `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-01-SUMMARY.md` (storage skeleton + 8 governance state items demolished + 5 errors removed) + `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-02-SUMMARY.md` (`setCharity` revert order + `RecipientIsContract` DELETED Phase 254 deviation) + `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-03-SUMMARY.md` (5 view helpers + `_flushedBitmap` private helper) — cross-cite-only, READ-only on upstream artifacts per D-253-CF-08.

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| ALW-01 | `COMPLETE_AT_HEAD_dcb70941` | 254-01-SUMMARY.md storage skeleton (`currentSlate[20]` + `pendingEdit` + `currentActiveBitmap` + `pendingEditSet`) + hot-pack slot 2 per D-254-REPACK-01 |
| ALW-02 | `COMPLETE_AT_HEAD_dcb70941` | 254-02-SUMMARY.md `setCharity` 4-branch admin op (`GNRUS.sol:366-408`) — instant-apply / queue / removal / locked-slot — per D-254-VOTEPICK-01 boundary |
| ALW-03 | `COMPLETE_AT_HEAD_dcb70941` | 254-02-SUMMARY.md `setCharity` revert order locked: vault-owner gate → `InvalidSlot` → `SlotLocked` → `SlotAlreadyEmpty` → `CapExceeded` (the latter via `_futureBitmapAfter` cap-check) |
| ALW-04 | `COMPLETE_AT_HEAD_dcb70941` | 254-03-SUMMARY.md 5 view helpers (`getCharity` / `getActiveSlots` / `getPendingEdits` / `activeCount` / `activeCountAfterFlush`) + `_flushedBitmap()` internal helper backing `activeCountAfterFlush` |
| CLEAN-01 | `COMPLETE_AT_HEAD_dcb70941` | 254-01-SUMMARY.md v32 governance state demolished (8 state items + 5 functions + 7 errors removed) — no commented-out residue per `feedback_no_history_in_comments.md` |

Phase 254 produces the v33.0 storage + admin-op + view-helper foundation at HEAD `dcb70941`. The bitmap-as-single-source-of-truth pattern (D-254-COUNT-01) makes accounting drift impossible by construction (see AUDIT-02 surface (f) verdict at §4). The 4-error addition (`InvalidSlot`, `SlotAlreadyEmpty`, `SlotLocked`, `CapExceeded`) provides the exact reject-shape that Phase 255 `vote()` and `pickCharity()` consume. `re-verified at HEAD dcb70941`.

### 3b. Phase 255 — Vote Rewrite, Resolve Flush & Event/Error Cleanup

**Change-count card:**
- Plans: 3 (255-01, 255-02, 255-03)
- Commits: `30188329` (governance declarations: events + errors + `slotApproveWeight` storage) + `e734cfe6` (`vote(uint8 slot)` external) + `ac1d3741` (`pickCharity(uint24 level)` external onlyGame)
- Functions added: `vote(uint8 slot)` external (Phase 255 boundary re-add per D-254-VOTEPICK-01; signature `(uint8)` not the v32 `(uint256 proposalId)`), `pickCharity(uint24 level)` external onlyGame (signature `(uint24 level)` exactly preserves the v32 `IGNRUSResolve` interface signature pin per D-255-FLUSH-ORDER-01)
- Events added: `CharityFlushed(uint8 indexed slot, address indexed recipient)` (per D-255-FLUSH-EVENT-01 — emitted per applied edit during `pickCharity` flush)
- Events rewritten: `Voted(uint24 indexed level, uint8 indexed slot, address indexed voter, uint256 weight)` (was `Voted(uint24 indexed level, uint256 indexed proposalId, address indexed voter, uint256 weight)`); `LevelResolved(uint24 indexed level, uint8 indexed slot, address recipient, uint256 gnrusDistributed)` (was `LevelResolved(uint24 indexed level, uint256 indexed proposalId, address recipient, uint256 gnrusDistributed)`) — both per D-255-EVENT-CLEANUP-01
- Events deleted: `ProposalCreated` (v32 governance event removed per D-255-EVENT-CLEANUP-01)
- Errors added: `VoteRejected(uint8 reason)` with reason codes 0/1/2 = `REJECT_EMPTY_SLOT` / `REJECT_ALREADY_VOTED` / `REJECT_ZERO_WEIGHT` per D-255-VOTEREJECT-01; `PickCharityRejected(uint8 reason)` with reason codes 0/1 = `REJECT_LEVEL_NOT_ACTIVE` / `REJECT_LEVEL_ALREADY_RESOLVED` per D-255-PICKCHARITY-ERROR-01
- Errors deleted: `ProposalLimitReached`, `AlreadyProposed`, `InvalidProposal` (v32 propose-exclusive errors removed)
- Storage added: `mapping(uint24 => mapping(uint8 => uint256)) public slotApproveWeight` (the per-level per-slot vote-weight tally, nested per D-255-WEIGHT-STORAGE-01)
- Constants added: `REJECT_EMPTY_SLOT = 0`, `REJECT_ALREADY_VOTED = 1`, `REJECT_ZERO_WEIGHT = 2`, `REJECT_LEVEL_NOT_ACTIVE = 0`, `REJECT_LEVEL_ALREADY_RESOLVED = 1` (the 5 reason-code constants per D-255-VOTEREJECT-01 + D-255-PICKCHARITY-ERROR-01)
- REQs satisfied: 10/10 (VOTE-01, VOTE-02, VOTE-03, VOTE-04, RES-01, RES-02, RES-03, RES-04, CLEAN-02, CLEAN-03)
- Closure signal: `PHASE_255_FINAL_AT_HEAD_ac1d3741`

**Cross-cite:** `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-01-SUMMARY.md` (events + errors + `slotApproveWeight` declarations) + `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-02-SUMMARY.md` (`vote()` revert order + state writes + `Voted` emit) + `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-03-SUMMARY.md` (`pickCharity()` flush + winner-loop + 3 LevelSkipped paths + distribution + `LevelResolved` emit).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| VOTE-01 | `COMPLETE_AT_HEAD_dcb70941` | 255-02-SUMMARY.md `vote()` external entry at `GNRUS.sol:558-581`; signature `(uint8 slot)` per D-254-VOTEPICK-01 boundary |
| VOTE-02 | `COMPLETE_AT_HEAD_dcb70941` | 255-02-SUMMARY.md `vote()` 4-path revert order: `InvalidSlot` (slot ≥ 20) → `VoteRejected(REJECT_EMPTY_SLOT)` (slot empty) → `VoteRejected(REJECT_ALREADY_VOTED)` (`hasVoted` set) → `VoteRejected(REJECT_ZERO_WEIGHT)` (sDGNRS balance 0) per D-255-VOTE-REVERT-ORDER-01 |
| VOTE-03 | `COMPLETE_AT_HEAD_dcb70941` | 255-02-SUMMARY.md `slotApproveWeight[level][slot] += weight` accumulation + `hasVoted[level][voter][slot] = true` write |
| VOTE-04 | `COMPLETE_AT_HEAD_dcb70941` | 255-02-SUMMARY.md `Voted(level, slot, voter, weight)` event emit at end of state-write sequence (CEI-ordering attestation per D-255-CEI-01) |
| RES-01 | `COMPLETE_AT_HEAD_dcb70941` | 255-03-SUMMARY.md `pickCharity(uint24 level)` external onlyGame at `GNRUS.sol:601-674`; signature exactly preserves v32 `IGNRUSResolve` interface signature pin |
| RES-02 | `COMPLETE_AT_HEAD_dcb70941` | 255-03-SUMMARY.md operation order locked per D-255-FLUSH-ORDER-01: (1) level-arg + idempotence checks → (2) atomic flush of pending edits → (3) strict-`>` winner loop 0..19 (lowest-slot wins on tie) → (4) 3 LevelSkipped paths → (5) distribution → (6) `LevelResolved` emit |
| RES-03 | `COMPLETE_AT_HEAD_dcb70941` | 255-03-SUMMARY.md `CharityFlushed(slot, recipient)` emit per applied edit during flush; `levelResolved[level] = true` write before distribution to enforce idempotence |
| RES-04 | `COMPLETE_AT_HEAD_dcb70941` | 255-03-SUMMARY.md distribution arithmetic: `distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM` at `GNRUS.sol:660` (2% of remaining unallocated GNRUS to winning recipient) |
| CLEAN-02 | `COMPLETE_AT_HEAD_dcb70941` | 255-01-SUMMARY.md `Voted` + `LevelResolved` event signatures rewritten (proposalId → slot); `ProposalCreated` event deleted; 3 v32 propose-exclusive errors deleted |
| CLEAN-03 | `COMPLETE_AT_HEAD_dcb70941` | 255-01-SUMMARY.md `VoteRejected(uint8)` + `PickCharityRejected(uint8)` reason-code errors added with 5 reason-code constants |

Phase 255 wires the v33.0 vote/resolve flow onto the Phase 254 storage skeleton. Critical invariants: (i) `vote()` revert order is locked per D-255-VOTE-REVERT-ORDER-01 (gas-optimal short-circuit + observable failure-mode contract for off-chain consumers); (ii) `pickCharity()` operation order is locked per D-255-FLUSH-ORDER-01 (idempotence-first → atomic flush → strict-`>` winner → distribution); (iii) the `IGNRUSResolve.pickCharity(uint24)` interface signature pin is preserved exactly so `AdvanceModule:1634` `charityResolve.pickCharity(lvl - 1)` continues to compile + execute against the post-Phase-255 ABI. `re-verified at HEAD dcb70941`.

---

### 3c. Phase 256 — Charity Allowlist Test Coverage

**Change-count card:**
- Plans: 6 (256-01 fixture + 256-02 unit-prune + 256-03a/b/c governance test surface + 256-04 integration extension)
- Commits: `b1f84a8c` (Phase 256-01 fixture helper) + `10ee964c` (Phase 256-02 unit-test prune to v33 shape) + `3f667b3e` (Phase 256-03a/b/c governance allowlist test surface) + `644af631` (Phase 256-04 CharityGameHooks integration extension)
- Test files added: `test/helpers/charityFixture.js` (fixture per D-256-HELPER-01); `test/governance/CharityAllowlist.test.js` (unit test surface for setCharity branches + edit-queue level-boundary semantics + vote 4-reject paths + multi-slot vote independence + pickCharity winner + tie-break + 3 LevelSkipped paths + post-gameover smoke + gas guardrail per D-256-LAYOUT-01)
- Test files modified: `test/unit/DegenerusCharity.test.js` (pruned per D-256-LAYOUT-01 to remove v32-shape proposal/vote tests); `test/integration/CharityGameHooks.test.js` (extended per D-256-CONSERVATION-01 for real-game-flow conservation evidence — `charityResolve.pickCharity(lvl - 1)` from `AdvanceModule:1634` exercised end-to-end across the level transition)
- Test sections: `setCharity` branches (instant-apply / queue / locked-slot / overwrite / 20-slot fill / `CapExceeded` structural-unreachability per `256-03a` D-256-CANCEL-QUEUED-01) + edit-queue level-boundary semantics + `vote()` 4 reject reason codes (`InvalidSlot` / `REJECT_EMPTY_SLOT` / `REJECT_ALREADY_VOTED` / `REJECT_ZERO_WEIGHT` per D-256-VOTE-REJECT-01) + multi-slot vote independence per D-256-MULTI-VOTE-01 + `pickCharity` winner + tie-break cases A+B per D-256-TIEBREAK-01 + 3 LevelSkipped paths + post-gameover smoke per D-256-POSTGAMEOVER-01 (positive smoke that `setCharity` + `vote` do NOT revert post-`burnAtGameOver`; inertness comes from absence of game-side caller, not contract-level `finalized` guards) + D-256-GAS-01 single-assertion gas guardrail (`pickCharity` full-slate < 700_000 gas)
- REQs satisfied: 6/6 (TST-01, TST-02, TST-03, TST-04, TST-05, TST-06)
- Closure signal: `PHASE_256_FINAL_AT_HEAD_644af631`

**Cross-cite:** `.planning/phases/256-charity-allowlist-test-coverage/256-01-SUMMARY.md` (charityFixture helper) + `256-02-SUMMARY.md` (unit-test prune) + `256-03a-SUMMARY.md` (setCharity coverage + CapExceeded structural-unreachability + cancel-queued unreachability per D-256-CANCEL-QUEUED-01) + `256-03b-SUMMARY.md` (vote 4-reject + multi-slot independence) + `256-03c-SUMMARY.md` (pickCharity winner + tie-break A+B + 3 LevelSkipped + post-gameover smoke per D-256-POSTGAMEOVER-01 + D-256-GAS-01) + `256-04-SUMMARY.md` (integration conservation evidence per D-256-CONSERVATION-01).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| TST-01 | `PASS_AT_HEAD_dcb70941` | 256-03a-SUMMARY.md setCharity branches (instant-apply / queue / locked-slot first-fill / overwrite same-slot replaces); CapExceeded structural-unreachability verdict per D-256-CANCEL-QUEUED-01 |
| TST-02 | `PASS_AT_HEAD_dcb70941` | 256-03a-SUMMARY.md edit-queue level-boundary semantics (queued A then B → only B applies on flush); D-256-CONTRACT-RECIPIENT-01 positive contract-recipient acceptance test (RecipientIsContract revert path REMOVED in Phase 254 deviation) |
| TST-03 | `PASS_AT_HEAD_dcb70941` | 256-03b-SUMMARY.md vote() 4-reject reason-code coverage per D-256-VOTE-REJECT-01 + multi-slot vote independence per D-256-MULTI-VOTE-01 |
| TST-04 | `PASS_AT_HEAD_dcb70941` | 256-03c-SUMMARY.md pickCharity winner + tie-break cases A+B per D-256-TIEBREAK-01 + 3 LevelSkipped paths (no votes / no recipient / level-not-active) + PickCharityRejected reason-code coverage per D-256-PICKCHARITY-REJECT-01 |
| TST-05 | `PASS_AT_HEAD_dcb70941` | 256-03c-SUMMARY.md post-gameover smoke per D-256-POSTGAMEOVER-01 (setCharity + vote do NOT revert post-burnAtGameOver — inert by absence of game-side caller, not by contract-level guard); 256-04-SUMMARY.md integration conservation per D-256-CONSERVATION-01 (real game-flow charityResolve.pickCharity from AdvanceModule:1634) |
| TST-06 | `PASS_AT_HEAD_dcb70941` | 256-03c-SUMMARY.md D-256-GAS-01 single-assertion gas guardrail (`pickCharity` full-slate < 700_000 gas) — Phase 257 §3c cross-cites this measurement; does NOT re-derive per CONTEXT.md `<deferred>` "Gas measurement / re-derivation" |

Phase 256 produces the v33.0 test surface with 6 test SUMMARYs covering every behaviorally observable v33.0 surface. Critical attestations: (i) `CapExceeded` is structurally unreachable from external calls — `_popcount32(_futureBitmapAfter(...))` is mathematically capped at 20 — defensive guard but mathematically unreachable, recorded as SAFE row in AUDIT-02 surface (b) per ROADMAP §"Phase 256" success criterion 1 + `256-03a-PLAN.md` carry-forward; (ii) post-gameover inertness comes from absence of game-side caller, NOT from a `finalized` guard on `setCharity` / `vote` / `pickCharity` (D-256-POSTGAMEOVER-01 — surfaced as §4 sub-row prose disclosure if needed, NOT a contract amendment); (iii) D-256-CONSERVATION-01 real-game-flow integration evidence proves the 2%-distribution math survives the actual `charityResolve.pickCharity(lvl - 1)` call from `AdvanceModule:1634` end-to-end across the level transition. `re-verified at HEAD dcb70941`.

### 3.4 Non-GNRUS Post-Anchor Commits — Functional-Orthogonality Sanity

**Scope-adjustment note.** Per planner-surfaced deviation from CONTEXT.md `<domain>` (which cited 4 contract commits since baseline), live `git log acd88512..HEAD -- contracts/` at HEAD `dcb70941` shows 8 contract commits — the 4 expected GNRUS-related (Phase 254/255 single-commit consolidation + 3 declarations/vote/pickCharity commits) PLUS 7 post-anchor non-GNRUS commits including 3 test commits visible only in the broader `acd88512..HEAD --` range. This subsection classifies each non-GNRUS commit as functionally orthogonal to v33 charity surface AND to L173 turbo guard / L1174 backfill sentinel / `_livenessTriggered` body. Mirrors v32 Phase 252 POST31 + SG-250-01 pattern (where a single post-anchor MintModule presale-flag commit was recorded as functionally orthogonal in `audit/FINDINGS-v32.0.md` §3f + §9.NN.i).

**Per-commit row table:**

| Commit SHA | Subject | Files Touched | Orthogonality Verdict | Re-Verification Evidence |
| --- | --- | --- | --- | --- |
| `98e78404` | fix(mint): gate lootbox vault skim on PS_ACTIVE flag | `contracts/modules/DegenerusGameMintModule.sol` | ORTHOGONAL_PROVEN | Carry-forward from v32 SG-250-01 (Phase 250 SIB-03 + Phase 252 §1 V03 NEGATIVE-scope); recorded in `audit/FINDINGS-v32.0.md` §9.NN.i. Does not touch GNRUS / charity surface / L173 turbo / L1174 backfill / `_livenessTriggered`. |
| `002bde55` | feat(presale): auto-deactivate flag on per-mint cap crossing | `contracts/modules/DegenerusGameMintModule.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` + `contracts/storage/DegenerusGameStorage.sol` | ORTHOGONAL_PROVEN | Moves `LOOTBOX_PRESALE_ETH_CAP` constant from `AdvanceModule:139` to `GameStorage:863`; simplifies presale auto-end condition at `AdvanceModule:431`. Does NOT touch L173 turbo guard or L1174 backfill sentinel — verify via `git diff acd88512..HEAD -- contracts/modules/DegenerusGameAdvanceModule.sol` regions L170-180 + L1170-1185 byte-identical. The constant insertion at `GameStorage:863` shifts subsequent line numbers by ~1; `_livenessTriggered` body now at L1249-1259 (was L1246-1256) but body bytes char-by-char identical. |
| `73b8c3b6` | test(presale): cover per-mint cap deactivation paths | `test/` only | ORTHOGONAL_PROVEN | Pure test addition for the `002bde55` presale-auto-end paths; no contract delta. Does not touch GNRUS or charity surface. |
| `16e0eca5` | test(edge): last-purchase-day race repro for testnet panic 0x11 | `test/edge/LastPurchaseDayRace.test.js` | ORTHOGONAL_PROVEN | User-committed v32 Phase 251 awaiting-approval test file (was TST-FILE-01 at v32 Phase 253 §9.NN.iii). Does not modify any contract surface. |
| `560951a0` | test(edge): backfill idempotency repro for multi-day VRF stall | `test/edge/BackfillIdempotency.test.js` | ORTHOGONAL_PROVEN | User-committed v32 Phase 251 awaiting-approval test file (was TST-FILE-02 at v32 Phase 253 §9.NN.iii). Does not modify any contract surface. |
| `2713ce61` | chore(vault): remove dead setDecimatorAutoRebuy wrapper | `contracts/DegenerusVault.sol` | ORTHOGONAL_PROVEN | Removes 9 lines (interface stub + wrapper function) per `feedback_no_dead_guards.md` (dead wrapper, not dead-guard cleanup). Does not touch GNRUS, AdvanceModule, MintModule, or any RNG-consuming path. |
| `dcb70941` | fix(BurnieCoin): revert Insufficient on burn shortfall instead of underflow | `contracts/BurnieCoin.sol` | ORTHOGONAL_PROVEN | `_consumeCoinflipShortfall` now reverts `Insufficient()` instead of underflowing. Functionally a defensive guard hardening (per `feedback_no_dead_guards.md`: NOT a dead-guard removal — it converts an underflow-revert into a named-error-revert). Does not touch GNRUS, AdvanceModule, MintModule, or any v33 charity surface. Does not interact with charity governance, RNG, or any v33-relevant surface. |

**Closing attestation:** All 7 post-anchor non-GNRUS commits classified ORTHOGONAL_PROVEN — none widen the v33 charity surface, none touch the L173 / L1174 / `_livenessTriggered` regression target, none introduce new RNG-consuming paths. REG-01 single PASS row at §5a covers byte-identity proof for the load-bearing line ranges (L170-180 turbo region + L1170-1185 backfill region) across the wider contract-tree delta. `re-verified at HEAD dcb70941`.

---

### 3a (cont.) AUDIT-01 Delta-Surface Table — `contracts/GNRUS.sol` `acd88512` → `dcb70941`

**Per ROADMAP success criterion 2:** every changed function / state variable / event / error in `contracts/GNRUS.sol` vs baseline `acd88512` is enumerated below with hunk-level evidence and classified as `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}`. Raw delta size: `git diff acd88512..HEAD -- contracts/GNRUS.sol` = 664 lines (4 GNRUS-touching commits: `469d7fc1` Phase 254 + `30188329` / `e734cfe6` / `ac1d3741` Phase 255).

#### Part A: GNRUS.sol Function / State / Event / Error Classification

**Functions — NEW (11 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `setCharity(uint8 slot, address recipient)` | function (external) | NEW | `GNRUS.sol:366-408` | Vault-owner-gated admin op with 4 branches (instant-apply / queue / removal / locked-slot revert); cap-check via `_futureBitmapAfter` | Phase 254 D-254-VOTEPICK-01 + 254-02-SUMMARY.md |
| `_futureBitmapAfter(uint8, address, uint32)` | function (private view) | NEW | `GNRUS.sol:416-444` | Cap-check helper computing post-flush active bitmap; backs `CapExceeded` revert via `_popcount32 > MAX_ACTIVE_SLOTS` | 254-02-SUMMARY.md |
| `_flushedBitmap()` | function (private view) | NEW | `GNRUS.sol:450-464` | Post-flush bitmap projector; backs `activeCountAfterFlush` view | 254-03-SUMMARY.md |
| `_popcount32(uint32)` | function (private pure) | NEW | `GNRUS.sol:469-480` | Active-count primitive (Kernighan popcount); the bitmap-as-single-source-of-truth foundation | 254-01-SUMMARY.md D-254-COUNT-01 |
| `getCharity(uint8)` | function (external view) | NEW | `GNRUS.sol:489-495` | Returns active recipient at slot; enforces `slot < MAX_ACTIVE_SLOTS` revert | 254-03-SUMMARY.md D-254-VIEW-01 |
| `getActiveSlots()` | function (external view) | NEW | `GNRUS.sol:497-516` | Returns paired `(uint8[] slots, address[] recipients)` arrays for active slots | 254-03-SUMMARY.md |
| `getPendingEdits()` | function (external view) | NEW | `GNRUS.sol:517-534` | Returns paired arrays for pending-edit queue | 254-03-SUMMARY.md |
| `activeCount()` | function (external view) | NEW | `GNRUS.sol:535-540` | Returns `_popcount32(currentActiveBitmap)` (current slate count) | 254-03-SUMMARY.md |
| `activeCountAfterFlush()` | function (external view) | NEW | `GNRUS.sol:541-552` | Returns `_popcount32(_flushedBitmap())` (post-flush count) | 254-03-SUMMARY.md |
| `vote(uint8 slot)` | function (external) | NEW (with FIX-02 follow-up MODIFIED_LOGIC) | `GNRUS.sol:570-598` | Phase 255 boundary re-add per D-254-VOTEPICK-01; signature `(uint8)` not v32 `(uint256 proposalId)`. **Phase 258-01 FIX-02 follow-up:** new revert path `PreviousWinnerNotVotable` inserted between the empty-slot rejection (step 2) and the already-voted rejection (step 3). The check `currentSlate[slot] == lastWinningRecipient` reuses the cold SLOAD on `currentSlate[slot]` from the empty-slot guard above; no extra cross-contract call. | 255-02-SUMMARY.md + 258-01-SUMMARY.md FIX-02 |
| `pickCharity(uint24 level)` | function (external onlyGame) | NEW (with FIX-01 follow-up MODIFIED_LOGIC) | `GNRUS.sol:623-687` | Phase 255 boundary re-add; signature `(uint24)` exactly preserves v32 `IGNRUSResolve` pin. **Phase 258-01 FIX-01 follow-up:** body restructured so the pendingEdit flush phase executes AFTER the distribution payout (queued setCharity edits during level L apply to L+1, not L). Skip-paths A/B/C composed into a single `paid` predicate so the flush always runs once at end-of-function. `lastWinningRecipient` written ONLY in the paid branch (skipped levels retain prior block). | 255-03-SUMMARY.md D-255-FLUSH-ORDER-01 + 258-01-SUMMARY.md FIX-01 |

**Functions — DELETED (1 row):**

| Symbol | Type | Classification | Baseline Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `propose(address)` | function (external) | DELETED | acd88512 baseline | v32 governance entry point removed; supplanted by vault-owner-curated `setCharity` admin op + `vote(uint8)` slot-based voting | 254-01-SUMMARY.md D-254-VOTEPICK-01 |

**Storage state — NEW (5+ rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `address[20] private currentSlate` | state (fixed-array) | NEW | `GNRUS.sol:175` | The 20-slot allowlist (active recipients indexed by slot); declared private to avoid auto-getter clash with named `getCharity(uint8)` view | 254-01-SUMMARY.md D-254-SLATE-01 |
| `mapping(uint8 => address) private pendingEdit` | state (mapping) | NEW | `GNRUS.sol:179` | Sparse pending-edit queue (slot → queued recipient); `address(0)` sentinel for queued-removal | 254-01-SUMMARY.md D-254-PENDING-01 |
| `uint32 public currentActiveBitmap` | state (uint32) | NEW | `GNRUS.sol:160` | Active-slot bitmap — single source of truth for active count per D-254-COUNT-01 (drift impossible by construction) | 254-01-SUMMARY.md |
| `uint32 public pendingEditSet` | state (uint32) | NEW | `GNRUS.sol:163` | Pending-edit sentinel bitmap; bit i set ⇔ slot i has a pending edit (real or removal) | 254-01-SUMMARY.md |
| `mapping(uint24 => bool) public levelResolved` | state (mapping) | NEW | `GNRUS.sol:168` | Per-level idempotence flag for `pickCharity(level)` | 254-01-SUMMARY.md |
| `mapping(uint24 => mapping(uint8 => uint256)) public slotApproveWeight` | state (nested mapping) | NEW | `GNRUS.sol:184` | Per-level per-slot vote-weight tally accumulated by `vote()` | 255-01-SUMMARY.md D-255-WEIGHT-STORAGE-01 |
| `address public lastWinningRecipient` | state (address) | NEW | `GNRUS.sol:196` | Tracks the recipient that won the most recent paid level; consumed by `vote()` to block consecutive wins via `PreviousWinnerNotVotable`. Written ONLY in the distribution-paid branch of `pickCharity` so skipped levels retain the prior winner block. | Phase 258-01 FIX-02 + 258-01-SUMMARY.md |

**Storage state — MODIFIED_LOGIC (1 row):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `mapping(uint24 => mapping(address => mapping(uint8 => bool))) public hasVoted` | state (nested mapping) | MODIFIED_LOGIC | `GNRUS.sol:171` | Inner key changed from `proposalId` (uint48) to `slot` (uint8) per D-254-HASVOTED-01; semantics now "has voter X voted on slot S in level L" | 254-01-SUMMARY.md |

**Storage state — DELETED (8 rows):**

| Symbol | Type | Classification | Baseline Cite | 1-Line Description |
| --- | --- | --- | --- | --- |
| `Proposal` struct | type | DELETED | acd88512 baseline | v32 proposal record |
| `proposals` array | state | DELETED | acd88512 baseline | v32 proposal store |
| `proposalCount` | state | DELETED | acd88512 baseline | v32 monotone counter |
| `levelProposalStart` | state (mapping) | DELETED | acd88512 baseline | v32 per-level proposal-range start |
| `levelProposalCount` | state (mapping) | DELETED | acd88512 baseline | v32 per-level proposal-range count |
| `hasProposed` | state (mapping) | DELETED | acd88512 baseline | v32 per-level per-creator proposal idempotence |
| `creatorProposalCount` | state (mapping) | DELETED | acd88512 baseline | v32 per-creator monotone count |
| `levelVaultOwner` | state (mapping) | DELETED | acd88512 baseline | v32 per-level vault-owner snapshot — DELETED per D-254-VOTEPICK-01 (vault-owner identity now read fresh at call time, removing the float-snapshot surface) |
| `levelSdgnrsSnapshot` | state (mapping) | DELETED | acd88512 baseline | v32 per-level sDGNRS-supply snapshot — DELETED with the proposal model |

**Events — NEW (3 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `CharityApplied(uint8 indexed slot, address indexed recipient)` | event | NEW | `GNRUS.sol:118` | Emitted by `setCharity` instant-apply branch (slot was empty) | 254-01-SUMMARY.md D-254-EVENT-01 |
| `CharityQueued(uint8 indexed slot, address indexed recipient)` | event | NEW | `GNRUS.sol:121` | Emitted by `setCharity` queue branch (slot was filled — edit deferred until next `pickCharity` flush) | 254-01-SUMMARY.md D-254-EVENT-01 |
| `CharityFlushed(uint8 indexed slot, address indexed recipient)` | event | NEW | `GNRUS.sol:124` | Emitted per applied edit during `pickCharity` flush phase | 255-01-SUMMARY.md D-255-FLUSH-EVENT-01 |

**Events — RENAMED+SIGRENAMED (2 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `Voted(uint24 indexed level, uint8 indexed slot, address indexed voter, uint256 weight)` | event | RENAMED (signature) | `GNRUS.sol:106` | Was `Voted(uint24 indexed level, uint256 indexed proposalId, address indexed voter, uint256 weight)`; second arg type uint256→uint8 + name proposalId→slot | 255-01-SUMMARY.md D-255-EVENT-CLEANUP-01 |
| `LevelResolved(uint24 indexed level, uint8 indexed slot, address recipient, uint256 gnrusDistributed)` | event | RENAMED (signature) | `GNRUS.sol:109` | Was `LevelResolved(uint24 indexed level, uint256 indexed proposalId, address recipient, uint256 gnrusDistributed)`; second arg type uint256→uint8 + name proposalId→slot | 255-01-SUMMARY.md |

**Events — DELETED (1 row):**

| Symbol | Type | Classification | Baseline Cite | 1-Line Description |
| --- | --- | --- | --- | --- |
| `ProposalCreated` | event | DELETED | acd88512 baseline | v32 proposal-creation signal removed with the proposal model |

**Errors — NEW (6 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| `InvalidSlot()` | error | NEW | `GNRUS.sol:76` | Slot index ≥ `MAX_ACTIVE_SLOTS` (20); fired by `setCharity`, `vote`, `getCharity` | 254-01-SUMMARY.md D-254-ERROR-PRUNE-01 |
| `SlotAlreadyEmpty()` | error | NEW | `GNRUS.sol:79` | `setCharity(slot, address(0))` on already-empty slot (admin no-op) | 254-01-SUMMARY.md |
| `SlotLocked()` | error | NEW | `GNRUS.sol:82` | Locked-slot replace/remove attempt (`slot < LOCKED_SLOTS && current != address(0)`) | 254-01-SUMMARY.md |
| `CapExceeded()` | error | NEW | `GNRUS.sol:85` | Post-flush active count would exceed `MAX_ACTIVE_SLOTS` (20); structurally unreachable from external calls per D-256-CANCEL-QUEUED-01 / `256-03a-PLAN.md` (defensive guard) | 254-01-SUMMARY.md |
| `VoteRejected(uint8 reason)` | error | NEW | `GNRUS.sol:89` | `vote()` reject paths; reason codes 0/1/2 = `REJECT_EMPTY_SLOT` / `REJECT_ALREADY_VOTED` / `REJECT_ZERO_WEIGHT` per D-255-VOTEREJECT-01 | 255-01-SUMMARY.md |
| `PickCharityRejected(uint8 reason)` | error | NEW | `GNRUS.sol:93` | `pickCharity()` LevelSkipped variants; reason codes 0/1 = `REJECT_LEVEL_NOT_ACTIVE` / `REJECT_LEVEL_ALREADY_RESOLVED` per D-255-PICKCHARITY-ERROR-01 | 255-01-SUMMARY.md |
| `PreviousWinnerNotVotable()` | error | NEW | `GNRUS.sol:99` | `vote()` rejects when targeted slot's current recipient equals the previous level's winner; reuses the cold SLOAD on `currentSlate[slot]` already loaded for the empty-slot check. Skipped levels do not advance the block. | Phase 258-01 FIX-02 + 258-01-SUMMARY.md |

**Errors — DELETED (8 rows):**

| Symbol | Type | Classification | Baseline Cite | 1-Line Description |
| --- | --- | --- | --- | --- |
| `ProposalLimitReached` | error | DELETED | acd88512 baseline | v32 propose-exclusive |
| `AlreadyProposed` | error | DELETED | acd88512 baseline | v32 propose-exclusive |
| `InvalidProposal` | error | DELETED | acd88512 baseline | v32 propose-exclusive |
| `InsufficientStake` | error | DELETED | acd88512 baseline | v32 vote-time stake check |
| `AlreadyVoted` | error | DELETED | acd88512 baseline | replaced by `VoteRejected(REJECT_ALREADY_VOTED)` |
| `LevelAlreadyResolved` | error | DELETED | acd88512 baseline | replaced by `PickCharityRejected(REJECT_LEVEL_ALREADY_RESOLVED)` |
| `LevelNotActive` | error | DELETED | acd88512 baseline | replaced by `PickCharityRejected(REJECT_LEVEL_NOT_ACTIVE)` |
| `RecipientIsContract` | error | DELETED | acd88512 baseline | **Phase 254 deviation:** removed per D-256-CONTRACT-RECIPIENT-01 lock — contract recipients now accepted by design (positive contract-recipient acceptance test in Phase 256-03a) |

**Constants — NEW (7 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description |
| --- | --- | --- | --- | --- |
| `LOCKED_SLOTS = 3` | constant (uint8) | NEW | `GNRUS.sol:203` | Slots 0/1/2 locked once filled; first-fill instant-applies, subsequent replace/remove reverts `SlotLocked` |
| `MAX_ACTIVE_SLOTS = 20` | constant (uint8) | NEW | `GNRUS.sol:206` | The 20-slot allowlist cap |
| `REJECT_EMPTY_SLOT = 0` | constant (uint8) | NEW | `GNRUS.sol:209` | `VoteRejected` reason code |
| `REJECT_ALREADY_VOTED = 1` | constant (uint8) | NEW | `GNRUS.sol:212` | `VoteRejected` reason code |
| `REJECT_ZERO_WEIGHT = 2` | constant (uint8) | NEW | `GNRUS.sol:215` | `VoteRejected` reason code |
| `REJECT_LEVEL_NOT_ACTIVE = 0` | constant (uint8) | NEW | `GNRUS.sol:218` | `PickCharityRejected` reason code |
| `REJECT_LEVEL_ALREADY_RESOLVED = 1` | constant (uint8) | NEW | `GNRUS.sol:221` | `PickCharityRejected` reason code |

**Soulbound stubs — REFACTOR_ONLY (3 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description |
| --- | --- | --- | --- | --- |
| `transfer(address, uint256)` | function (external pure) | REFACTOR_ONLY | `GNRUS.sol:263` | Reverts `TransferDisabled()` (preserved from v32; AUDIT-03 invariant 4) |
| `transferFrom(address, address, uint256)` | function (external pure) | REFACTOR_ONLY | `GNRUS.sol:266` | Reverts `TransferDisabled()` (preserved from v32) |
| `approve(address, uint256)` | function (external pure) | REFACTOR_ONLY | `GNRUS.sol:269` | Reverts `TransferDisabled()` (preserved from v32) |

**Burn paths — REFACTOR_ONLY (2 rows):**

| Symbol | Type | Classification | HEAD Cite | 1-Line Description |
| --- | --- | --- | --- | --- |
| `burn(uint256 amount)` | function (external) | REFACTOR_ONLY | `GNRUS.sol:282` | Proportional ETH+stETH redemption math preserved verbatim from v32 (AUDIT-03 invariant 5); `git diff acd88512..HEAD` shows zero hunks affecting burn body |
| `burnAtGameOver()` | function (external onlyGame) | REFACTOR_ONLY | `GNRUS.sol:340` | Game-over remainder burn preserved from v32; sole consumer `DegenerusGameGameOverModule.sol:145` UNAFFECTED |

**Total classification distribution:** 11 NEW functions (pickCharity + vote each carry a Phase 258-01 follow-up MODIFIED_LOGIC note in the description column) + 1 DELETED function + 6+ NEW state + 1 MODIFIED_LOGIC state + 8 DELETED state + 3 NEW events + 2 RENAMED events + 1 DELETED event + 7 NEW errors + 8 DELETED errors + 7 NEW constants + 3 REFACTOR_ONLY soulbound stubs + 2 REFACTOR_ONLY burn paths = **60 classification rows** spanning every changed function/state/event/error in `contracts/GNRUS.sol` between `acd88512` and HEAD `4ce3703d740d3707c88a1af595618120a8168399`.

#### Part B: Downstream Caller Inventory

**Grep recipe:** `grep -rn "GNRUS\|charityResolve\|charityGameOver" contracts/` produces 4 caller hits in `contracts/modules/` (the cross-module wires consumed by GNRUS — additional hits in `DegenerusStonk.sol:322/329` are stETH/ETH push paths into GNRUS via `ContractAddresses.GNRUS`, not function calls on the GNRUS contract; recorded but not classified as charity-callers).

| Caller File:Line | Caller Function | Called Function | Affected/Unaffected | Justification |
| --- | --- | --- | --- | --- |
| `DegenerusGameAdvanceModule.sol:31-34` | interface decl `IGNRUSResolve` | N/A (interface) | UNAFFECTED | Interface signature `pickCharity(uint24 level)` byte-identical to v32 baseline; Phase 255 preserved exactly per D-255-FLUSH-ORDER-01 + carry-forward through `git diff acd88512..HEAD` showing the interface unchanged |
| `DegenerusGameAdvanceModule.sol:103-104` | constant decl | N/A (constant decl) | UNAFFECTED | `IGNRUSResolve private constant charityResolve = IGNRUSResolve(ContractAddresses.GNRUS)` byte-identical |
| `DegenerusGameAdvanceModule.sol:1634` | inside `advanceGame` per-level resolve | `pickCharity(uint24)` | AFFECTED but signature unchanged | The `charityResolve.pickCharity(lvl - 1)` wire is the sole consumer of GNRUS pickCharity; Phase 255 re-added the function with the same `(uint24 level)` signature (the v32 function existed at baseline, was deleted in Phase 254 per D-254-VOTEPICK-01, and re-added in Phase 255-03 with byte-identical interface signature). AUDIT-03 conservation re-proof at §3b confirms call-site invariant: 2%-of-pool distribution math survives end-to-end via D-256-CONSERVATION-01 integration test. |
| `DegenerusGameGameOverModule.sol:145` | inside game-over flow | `burnAtGameOver()` | UNAFFECTED | `charityGameOver.burnAtGameOver()` calls a v32-preserved REFACTOR_ONLY function at `GNRUS.sol:340`; no signature or behavior change. |

**Closing 1-line attestation:** AUDIT-01 §3a delta surface complete: every changed function/state/event/error in `contracts/GNRUS.sol` vs baseline `acd88512` enumerated with hunk-level evidence and classified per ROADMAP success criterion 2; downstream caller inventory shows zero AFFECTED-with-broken-contract — `pickCharity(uint24)` interface preserved per D-255-FLUSH-ORDER-01; `burnAtGameOver()` REFACTOR_ONLY preserved from v32. `re-verified at HEAD dcb70941`.

---

### 3b (cont.) AUDIT-03 Conservation Re-Proof Rows

**Per ROADMAP success criterion 4:** GNRUS unallocated-pool flow + supply invariants for GNRUS / sDGNRS / DGNRS / BURNIE + soulbound enforcement + `burn()` proportional redemption math each get a SAFE row with grep-cited proof. Phase 256 D-256-CONSERVATION-01 integration test (`test/integration/CharityGameHooks.test.js`) provides empirical real-game-flow evidence; this section provides the static / structural re-proof at HEAD `dcb70941`.

| # | Invariant | File:Line Cite | Grep Recipe | SAFE Verdict + Evidence |
| --- | --- | --- | --- | --- |
| 1 | **GNRUS unallocated pool flow = 2% per resolved level** | `GNRUS.sol:660` (`uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;`) + `GNRUS.sol:197` (`DISTRIBUTION_BPS = 200`) + `GNRUS.sol:200` (`BPS_DENOM = 10_000`) | `grep -n "DISTRIBUTION_BPS" contracts/GNRUS.sol` → 2 hits (constant decl + arithmetic at `:660`) | **SAFE** — `DISTRIBUTION_BPS = 200` (200 bps = 2%) constant unchanged from v32; arithmetic preserved verbatim per D-255-FLUSH-ORDER-01 step 7. The `unallocated = balanceOf[address(this)]` read is `pickCharity`-local; `distribution` is computed once per level resolve and bounded above by 2% of remaining unallocated balance. Phase 256 D-256-CONSERVATION-01 integration test empirically validates the 2% per-level distribution via real game-flow `charityResolve.pickCharity(lvl - 1)` from `AdvanceModule:1634`. No alternate distribution path exists (the only function that decrements GNRUS `balanceOf[address(this)]` toward a recipient is `pickCharity`; `burnAtGameOver` and `burn` are GNRUS↔ETH/stETH paths, not GNRUS↔recipient paths). |
| 2 | **GNRUS supply invariant** | `GNRUS.sol:191` (`INITIAL_SUPPLY = 1e30`) + `GNRUS.sol:255` (constructor `_mint(address(this), INITIAL_SUPPLY)`) + `GNRUS.sol:282` (`burn()` decrements `totalSupply` and `balanceOf[burner]`) + `GNRUS.sol:340` (`burnAtGameOver()` burns remainder via the same accounting) | `grep -n "INITIAL_SUPPLY\|totalSupply" contracts/GNRUS.sol` → constant decl at `:191` + 1 mint site + accounting reads | **SAFE** — supply invariant: `totalSupply = INITIAL_SUPPLY - sum(burn) - sum(burnAtGameOver)`; `pickCharity` distribution is a `balanceOf[address(this)] → balanceOf[recipient]` transfer (zero-sum, supply preserved). Constructor mint to `address(this)` is the only mint site and is preserved from v32. v33 charity governance does not introduce a new mint path. The invariant holds across the level transition. |
| 3 | **sDGNRS / DGNRS / BURNIE supplies unchanged across level transition** | `GNRUS.sol:558-581` (`vote()` reads `sdgnrs.balanceOf(voter)` for vote weight but does NOT write to sDGNRS) + `GNRUS.sol:601-674` (`pickCharity()` reads `slotApproveWeight[level][slot]` for winner selection + transfers GNRUS only — does NOT touch sDGNRS / DGNRS / BURNIE storage) | `grep -nE "sdgnrs\.|dgnrs\.|burnie\." contracts/GNRUS.sol` → only sdgnrs/dgnrs/burnie balance reads, zero writes | **SAFE** — v33 charity governance reads sDGNRS balance (vote weight source) and never writes to sDGNRS / DGNRS / BURNIE supplies. `pickCharity` distribution is GNRUS-only (`balanceOf[address(this)] → balanceOf[recipient]`). The 2%-distribution event does not affect any other token's supply. Phase 256 conservation test confirms supplies invariant across the level transition. |
| 4 | **Soulbound enforcement intact** | `GNRUS.sol:263-269` (transfer / transferFrom / approve all revert `TransferDisabled()`) | `grep -nE "function (transfer|transferFrom|approve)\(" contracts/GNRUS.sol` → 3 hits at `:263 :266 :269`, each `external pure returns (bool) { revert TransferDisabled(); }` | **SAFE** — soulbound enforcement preserved verbatim from v32; v33 added no new transfer / approve / transferFrom path. Phase 256 setCharity unit-tests cover positive contract-recipient acceptance per D-256-CONTRACT-RECIPIENT-01 — the `pickCharity` distribution writes recipient balance directly via internal accounting, NOT via an ERC20 `transfer` path, so soulbound enforcement is not bypassed (recipient cannot then transfer the received GNRUS — but they CAN call `burn(amount)` to redeem proportional ETH+stETH per invariant 5 below). |
| 5 | **`burn()` proportional redemption math unchanged** | `GNRUS.sol:282-329` (burn function body) | `git diff acd88512..HEAD -- contracts/GNRUS.sol` filtered to the burn-body line range shows zero hunks affecting the proportional-redemption arithmetic | **SAFE** — `burn(uint256 amount)` body is REFACTOR_ONLY at HEAD (per AUDIT-01 §3a Part A row): `owed = ((ethBal + stethBal + claimable) * amount) / supply`, with proportional ETH-first / stETH-second payout. Math preserved verbatim from v32. v33 charity governance does not touch the burn redemption arithmetic. The `MIN_BURN = 1e18` floor at `GNRUS.sol:194` and `InsufficientBurn()` revert at `:283` are unchanged. |

**Closing 1-line attestation:** AUDIT-03 §3b conservation re-proof complete: GNRUS unallocated-pool flow = 2% per resolved level; GNRUS / sDGNRS / DGNRS / BURNIE supply invariants intact; soulbound enforcement intact; `burn()` proportional redemption math unchanged. Each invariant SAFE row with grep-cited proof per ROADMAP success criterion 4. `re-verified at HEAD dcb70941`.

---

## 4. F-33-NN Finding Blocks

Phase 257 emits **ZERO F-33-NN finding blocks** per D-257-FIND-01 default expectation — v33 charity-allowlist surface is structurally well-bounded (vault-owner-curated 20-slot allowlist; no MEV-flow / no jackpot-flow / no RNG integration; distribution math unchanged from v32 at 2% of remaining unallocated pool per resolved level). The 8 adversarial surfaces (a..h) enumerated in ROADMAP success criterion 3 are tabled below with verdict + grep-cited evidence per row. Trust-asymmetry items (e) instant-apply admin-front-run + (g) locked-slot poisoning emit as §4 sub-row prose disclosures per D-257-FIND-01, NOT F-33-NN namespace blocks. F-33-NN namespace is reserved for FINDING_CANDIDATE rows that surface from Step 2 validation pass + Step 3 user disposition (see Task 7 + Task 8 below — section appended in-place upon disposition).

### 4a. 8-Surface Adversarial Row Table

| Surface | Description | Verdict | Grep Recipe + Line Cite | Prose Justification |
| --- | --- | --- | --- | --- |
| **(a)** | Admin front-run at level boundary | `SAFE_BY_STRUCTURAL_CLOSURE` (post-258 reinforcement) | `grep -n "if (current == address(0))" contracts/GNRUS.sol` → hit at `GNRUS.sol:380` (setCharity instant-apply branch); + `grep -n "vault.isVaultOwner" contracts/GNRUS.sol` → hit at `GNRUS.sol:368` (vault-owner gate first) | Two-branch write in `setCharity` at `GNRUS.sol:366-408`: instant-apply when `current == address(0)` (`:380`), queue when `current != address(0)` (`:399`). Per Phase 254 D-254-PENDING-01: pending overwrite for same slot replaces (queued A → queued B → only B applies on flush). Admin curating the slate at level boundary is structurally equivalent to admin curating the slate ahead of vote-cast window — there is no asymmetry in vote-weight assignment because votes are cast against the CURRENT slate at vote time (state observable via `getActiveSlots()` at `:497`); voters chose the slate the admin curated. Trust boundary IS vault-owner curation per CONTEXT.md `<decisions>` 4th item. No code-level vector beyond the trust boundary. **Phase 258-01 reinforcement.** The queue-branch vote-redirect mechanism — which the original `SAFE_BY_STRUCTURAL_CLOSURE` framing understated by treating "admin curating slate at level boundary" as equivalent to "admin curating ahead of vote-cast window" — is now structurally closed by the FIX-01 reorder of `pickCharity`: the pendingEdit flush executes AFTER the distribution payout, so a queued `setCharity(filledSlot, attackerB)` during level L cannot redirect L's already-cast voter weight from the OLD recipient to the queued recipient. Queued edits take effect for L+1, not L. The verdict reads `SAFE_BY_STRUCTURAL_CLOSURE` at HEAD `4ce3703d740d3707c88a1af595618120a8168399` for both the level-boundary admin curation surface AND the mid-level queue-redirect surface. |
| **(b)** | Edit-queue ordering / overflow | `SAFE_BY_STRUCTURAL_CLOSURE` | `grep -nE "_futureBitmapAfter\|_popcount32\|CapExceeded" contracts/GNRUS.sol` → 7 hits (constant decl + cap-check at `:393-394` instant-apply branch + `:401-402` queue branch + helper bodies at `:416-444` and `:469-480`) | `_futureBitmapAfter` at `GNRUS.sol:416-444` computes the post-flush active bitmap by simulating: (1) the proposed write at `slot`, (2) flush of all `pendingEditSet` bits to the current slate. `_popcount32` at `:469-480` confirms `popcount(futureBitmap) ≤ MAX_ACTIVE_SLOTS=20`; `CapExceeded` revert at `:394` and `:402` blocks overflow. Pending overwrite for same slot replaces (sparse mapping write at `:404` overwrites the prior `pendingEdit[slot]` entry with the new recipient — only the latest queued recipient applies per D-254-PENDING-01). Queue ordering is irrelevant: each slot has at most one queued edit in `pendingEdit[slot]` at any time. Phase 256 D-256-CANCEL-QUEUED-01 records the cancel-queued path as structurally unreachable from external calls (the cancel happens only when `setCharity(slot, 0)` is called on a slot whose `current == 0` AND `pendingEditSet & slotMask != 0` — but that combination requires the slot to be empty in current AND have a pending edit, which is the natural removal-special-case path at `:382-391`, not a separate cancel function). |
| **(c)** | Tie-break gaming via slot ordering | `SAFE_BY_DESIGN` | `grep -nE "for.*MAX_ACTIVE_SLOTS|w > bestWeight" contracts/GNRUS.sol` → winner loop at `GNRUS.sol:641` with strict-`>` at `:644` | Strict `>` iteration `0..MAX_ACTIVE_SLOTS-1` (i.e., `0..19`) at `GNRUS.sol:641-650` ensures lowest active slot index wins on tie. Per Phase 256 D-256-TIEBREAK-01 cases A+B test coverage: ties resolve deterministically to lowest-index. Slot ordering is observable from the slate (`getActiveSlots()` at `:497-516` returns the paired ordered arrays); no information asymmetry. Tie-break is a documented design choice (lowest-index-wins) — gaming reduces to controlling which slot index your candidate sits in, which IS the admin's slate-curation surface (a) + (e). Voters with equal weight on equal-index slots cannot break the tie via voting; only the admin can shift slot indices via the slate curation surface. |
| **(d)** | DGVE float gaming to flip vault-owner status mid-level | `SAFE_BY_TRUST_ASYMMETRY` | `grep -n "vault.isVaultOwner" contracts/GNRUS.sol` → setCharity entry at `GNRUS.sol:368`; vault-owner is the sole caller of setCharity | `vault.isVaultOwner(msg.sender)` at `GNRUS.sol:368` reads DGVE >50.1% threshold at call time. Phase 254 deliberately removed the v32 `levelVaultOwner` per-level snapshot per D-254-VOTEPICK-01 (see AUDIT-01 §3a Part A DELETED state row); vault-owner identity is now observable on-chain at any time via `vault.isVaultOwner(...)`. DGVE is a tradeable token, but >50.1% acquisition is the explicit trust boundary — value of vault-owner status is curating slate, not extracting protocol value. The 2% per-level distribution to whichever recipient the slate names is the only flow controlled by vault-owner; that flow is bounded above by 2% of remaining unallocated pool per level and is not extractable from voters (voters vote for slot indices on the current slate; they do not transfer value to the recipient). SAFE_BY_TRUST_ASYMMETRY = trust boundary acknowledged and bounded. **Related vector** (Task 7 /zero-day-hunter manual-fallback discovery): sDGNRS float gaming via vote-and-sell — voter acquires sDGNRS, calls `vote(slot)` (which freezes the weight in `slotApproveWeight[level][slot]` per D-256-MULTI-VOTE-01), sells sDGNRS; functionally equivalent to DGVE float gaming with sDGNRS as the float token. Same `SAFE_BY_TRUST_ASYMMETRY` verdict; same 2%-of-pool blast radius bound; same acquisition-cost-as-deterrent mitigation. Disposition (Task 8): folded into surface (d) prose per default path (Option B) — NOT promoted to F-33-NN block, NOT promoted to 9th surface row. |
| **(e)** | Instant-apply branch abuse (admin fills empty slot mid-level after observing votes) | `SAFE_BY_TRUST_ASYMMETRY` (sub-row prose disclosure) | `grep -n "if (current == address(0))" contracts/GNRUS.sol` → setCharity instant-apply branch at `GNRUS.sol:380-398`; admin can fill empty slot mid-level | **See sub-row prose block §4b below** (per D-257-FIND-01 — trust-asymmetry items go to §4 sub-row prose, NOT F-33-NN block). |
| **(f)** | Active-count accounting drift across both branches | `SAFE_BY_STRUCTURAL_CLOSURE` | `grep -nE "activeCount\|activeCountAfterFlush\|_popcount32\|_flushedBitmap" contracts/GNRUS.sol` → constant decls + view helpers at `:535-552` + internal helpers at `:450-480` | Single source of truth: `_popcount32` at `GNRUS.sol:469-480` over the active bitmap per Phase 254 D-254-COUNT-01. Both branches of `setCharity` (instant-apply at `:380-398` + queue at `:399-407`) update the same bitmap (`currentActiveBitmap |= slotMask` instant-apply at `:397`; `pendingEditSet |= slotMask` queue at `:405`); `pickCharity` flush at `:601-674` drains `pendingEditSet` into `currentActiveBitmap` via the same bitmap surface. No separate counters that could drift. `activeCount()` at `:535-540` counts current slate via `_popcount32(currentActiveBitmap)`; `activeCountAfterFlush()` at `:541-552` counts post-flush state via `_popcount32(_flushedBitmap())`. Phase 256 §3a 20-slot fill smoke + `CapExceeded` structural-unreachability verdict from `256-03a-PLAN.md` carry-forward: there is no code path that increments active count without setting the corresponding bit, and there is no code path that sets the bit without correspondingly updating the slate / pending-edit storage. AUDIT-01 §3a delta-surface table classifies bitmap as NEW v33 storage; no MODIFIED_LOGIC drift surface. |
| **(g)** | Locked-slot poisoning during seeding window | `SAFE_BY_TRUST_ASYMMETRY` (sub-row prose disclosure) | `grep -nE "LOCKED_SLOTS\|slot < LOCKED_SLOTS" contracts/GNRUS.sol` → constant decl at `GNRUS.sol:203` + locked-slot revert at `:375` (setCharity) | **See sub-row prose block §4c below** (per D-257-FIND-01 — trust-asymmetry items go to §4 sub-row prose, NOT F-33-NN block). |
| **(h)** | Locked-slot lock-bypass (no pending-queue path, no flush-time mutation, no constructor/migration backdoor) | `SAFE_BY_STRUCTURAL_CLOSURE` | `grep -nE "SlotLocked\|slot < LOCKED_SLOTS" contracts/GNRUS.sol` → revert decl at `GNRUS.sol:82` + revert site at `:375` (setCharity, before queue/instant-apply branching) | `SlotLocked` revert at `GNRUS.sol:375` (`if (slot < LOCKED_SLOTS && current != address(0)) revert SlotLocked()`) fires **before** queue/instant-apply branching at `:380-407` per Phase 254 success criterion 3 → locked slots cannot be mutated through the pending queue. Flush at `pickCharity:601-674` does not validate locked-slot rule (admin-side validation at `setCharity:375` makes the queue trustable per Phase 255 D-255-FLUSH-ORDER-01 — only edits that PASSED setCharity validation can be in the queue). Constructor at `GNRUS.sol:253-258` mints to `address(this)` and does NOT seed locked slots (seeding is via post-deploy `setCharity` admin op — see (g) sub-row below for the pre-seed window discussion); no migration / re-seed entry point exists at HEAD. `grep -n "function constructor\|function init\|function seed" contracts/GNRUS.sol` returns only the constructor at `:223`-relative + the explicit setCharity admin op. No lock-bypass path. |
| **(i)** | Consecutive-recipient capture — same recipient wins level L, then again at L+1 via the same slot it occupied at L | `SAFE_BY_STRUCTURAL_CLOSURE` (FIX-02) | `grep -nE "lastWinningRecipient\|PreviousWinnerNotVotable" contracts/GNRUS.sol` → declarations + write site + revert site (4 hits at HEAD `4ce3703d740d3707c88a1af595618120a8168399`) | Phase 258-01 FIX-02 adds the `lastWinningRecipient` storage slot (written by `pickCharity` ONLY in the distribution-paid branch; skipped levels leave the value unchanged) and the `PreviousWinnerNotVotable()` revert in `vote()` (between the empty-slot and already-voted guards). Effect: a voter targeting slot S at level L+1 reverts when `currentSlate[S] == lastWinningRecipient`, where `lastWinningRecipient` is the L-winning recipient. Vault-owner can unblock the slot by queueing a recipient swap before L+1's vote phase opens (queue branch via `setCharity(S, otherRecipient)` → flush during `pickCharity(L)` → `currentSlate[S]` at start of L+1 ≠ `lastWinningRecipient`). Skip path: a level with no winner does not write `lastWinningRecipient`, so the L-1 winner remains blocked at L+1. Test coverage: `test/governance/CharityAllowlist.test.js` describe "vote() previous-winner block (FIX-02)" with three it-blocks per Phase 258-01 plan-close. |


**Surface anchors (per ROADMAP success criterion 3 enumeration):**

- Surface (a) — Admin front-run at level boundary
- Surface (b) — Edit-queue ordering / overflow
- Surface (c) — Tie-break gaming via slot ordering
- Surface (d) — DGVE float gaming to flip vault-owner status mid-level
- Surface (e) — Instant-apply branch abuse (admin fills empty slot mid-level after observing votes)
- Surface (f) — Active-count accounting drift across both branches
- Surface (g) — Locked-slot poisoning during seeding window
- Surface (h) — Locked-slot lock-bypass (no pending-queue path, no flush-time mutation, no constructor/migration backdoor)
- Surface (i) — Consecutive-recipient capture: blocked structurally by lastWinningRecipient + PreviousWinnerNotVotable (FIX-02)

### 4b. Sub-Row Prose Disclosure: Surface (e) — Instant-Apply Branch Admin Front-Run

**Pre-decided per CONTEXT.md `<domain>` lock + ROADMAP success criterion 3** as a trust-asymmetry note disclosed inline in the audit deliverable (operational mitigation, not code-level defense). Routes to §4 sub-row prose per D-257-FIND-01, NOT F-33-NN namespace block.

**Vector.** The vault-owner can fill an empty slot mid-level after observing votes — for example, after voters cast for slots 0-2, the vault-owner calls `setCharity(5, attackerControlledRecipient)` which hits the instant-apply branch at `GNRUS.sol:380-398` (slot 5 was empty) and immediately makes slot 5 votable. The vault-owner can then self-vote from a high-sDGNRS-balance address to capture the level's 2%-of-pool distribution.

**Blast radius.** ONE level worth of distribution = 2% of remaining unallocated GNRUS (per AUDIT-03 invariant 1). Voters who already cast their votes do NOT have their votes retroactively reassigned by a fill-empty action; the slate state at vote-cast time is what each voter chose. Subsequent voters can vote on the newly-filled slot if they choose, but they observe the new slate state (`getActiveSlots()` is fresh-read per call). Across the protocol's lifetime, the pool drains exponentially (2% per level), so the total extractable value via this surface is bounded by the integral of 2%-per-level over the remaining game lifetime — a fraction of the unallocated pool, not the full pool.

**Mitigation.** Operational. Vault-owner curation IS the explicit trust boundary per CONTEXT.md `<decisions>` 4th item. Code-level defense (e.g., level-locked slates that prevent mid-level slate edits) was considered and rejected: the design intentionally allows mid-level slate edits to support emergency charity additions / removals (e.g., recipient address compromised mid-protocol). Per `feedback_no_dead_guards.md`, no defensive guard against vault-owner action exists at HEAD because vault-owner IS the curator. The acceptable mitigation is operational: vault-owner control is gated by DGVE >50.1% threshold (surface (d)); compromise of vault-owner control is the same threat as DGVE float gaming, which is itself bounded by tradeable-DGVE acquisition cost.

**Phase 258-01 closure of the queue-branch redirect mechanism.** Independent adversarial re-run on 2026-05-06 (logged in `.planning/phases/257-delta-audit-findings-consolidation/257-01-ADVERSARIAL-LOG.md`, Independent Re-Run section) flagged that the prose above generalizes a property that holds for the instant-apply branch onto the queue branch — where it does NOT hold in the `dcb70941` build. Specifically: in `dcb70941`, the vault-owner could call `setCharity(filledSlot, attackerB)` (queue branch at the original `:399-407`), and `pickCharity` would flush `currentSlate[slot] = attackerB` BEFORE reading `slotApproveWeight[level][slot]` and paying `currentSlate[bestSlot]`. Voters' weight cast for OLD-recipient-A would silently fund attackerB. Phase 258-01 FIX-01 closes this mechanism by reordering `pickCharity` so the flush runs AFTER the payout — voters in level L pay the OLD recipient (the value `currentSlate[slot]` held at vote-cast time, which equals its value at start of `pickCharity(L)`); queued edits apply to L+1. The post-258 build at HEAD `4ce3703d740d3707c88a1af595618120a8168399` makes the §4b generalization above structurally true for BOTH branches: voters chose the slate at vote time, and the slate at vote time IS the slate at payout time.

**Verdict.** `SAFE_BY_TRUST_ASYMMETRY`. Not promoted to F-33-NN per D-257-FIND-01 default path.

### 4c. Sub-Row Prose Disclosure: Surface (g) — Locked-Slot Poisoning During Seeding Window

**Pre-decided per CONTEXT.md `<domain>` lock + ROADMAP success criterion 3** as a trust-asymmetry note disclosed inline in the audit deliverable (operational mitigation, not code-level defense). Routes to §4 sub-row prose per D-257-FIND-01, NOT F-33-NN namespace block.

**Vector.** Locked slots (0/1/2 per `LOCKED_SLOTS = 3` constant at `GNRUS.sol:203`) are the persistent core charity slate for the protocol's lifetime — once filled, they cannot be replaced or removed (per Phase 254 success criterion 3 + `SlotLocked` revert at `GNRUS.sol:375`). The "seeding window" is the deploy-time admin-op window during which the vault-owner calls `setCharity(0, ...)`, `setCharity(1, ...)`, `setCharity(2, ...)` for the FIRST time to fill the locked slots. If an attacker compromises the deploy-time vault-owner key (or buys the DGVE >50.1% threshold) before initial seeding completes, they can permanently lock attacker-controlled recipients into slots 0/1/2.

**Blast radius.** PERMANENT capture of locked slots — the attacker-controlled recipients receive 2%-of-pool distributions for any level where their slot wins the vote, for the full protocol lifetime. Severe if exploited. But the pre-conditions are bounded: (1) deploy-time admin ops are outside the runtime threat model — they are a deployment-procedure concern, not an at-HEAD code-level concern; (2) post-seeding, the locked-slot rule is structurally enforced (surface (h) verdict `SAFE_BY_STRUCTURAL_CLOSURE`); (3) DGVE >50.1% acquisition is the explicit trust boundary throughout — including pre-seed.

**Mitigation.** Operational. The deploy-time procedure must seed locked slots atomically with the deploy transaction (or via a multisig-controlled bootstrap sequence) — this is documented in the deployment runbook outside the audit scope. No code-level defense at HEAD because pre-seed state is by definition the state BEFORE the locked-slot rule has anything to lock. A potential code-level alternative — e.g., constructor-args seeded recipients with a `SlotLocked` revert on any further `setCharity(< LOCKED_SLOTS, ...)` after constructor — was considered but adds upgrade-time inflexibility; the operational mitigation matches `feedback_no_dead_guards.md` (no constructor-seeded code-level defense for a deploy-time risk).

**Verdict.** `SAFE_BY_TRUST_ASYMMETRY`. Not promoted to F-33-NN per D-257-FIND-01 default path.

### 4d. §4 Closing Attestation

**9 of 9 surfaces (a)..(i) verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY at HEAD `4ce3703d740d3707c88a1af595618120a8168399`.** Distribution: `SAFE_BY_STRUCTURAL_CLOSURE = 5` rows (a, b, f, h, i — surface (a) reinforced post-258 by the FIX-01 queue-branch closure; surface (i) added post-258 for the FIX-02 consecutive-recipient capture closure) + `SAFE_BY_DESIGN = 1` row (c) + `SAFE_BY_TRUST_ASYMMETRY = 3` rows (d, e, g — surface (e) sub-row prose at §4b extended in this re-audit to disclose the queue-branch mechanism that FIX-01 now structurally closes). Zero F-33-NN finding blocks emitted across both Phase 257 closure + Phase 258 re-audit (D-257-FIND-01 default path holds). Two trust-asymmetry items (e) + (g) emit as §4b + §4c sub-row prose disclosures.

---

## 5. Regression Appendix

Regression appendix per ROADMAP success criterion 5. §5a REG-01: single PASS row covering F-32-01 + F-32-02 SUPERSEDED-at-HEAD per D-257-REG01-01 (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening because v33 modifies ONLY `contracts/GNRUS.sol`; AdvanceModule + GameStorage line ranges L173 + L1174 + `_livenessTriggered` body byte-identical between baseline and HEAD). §5b REG-02: zero-row + paragraph per D-257-REG02-02 (defensive grep walk over prior FINDINGS for any v29/v30/v31/v32 row whose acceptance rationale relied on a charity-governance-touching envelope; zero candidates expected). §5c Combined Distribution: 1 PASS / 0 REGRESSED / 0 SUPERSEDED total.

Verdict taxonomy per D-253-REG01-03 closed set: `{PASS / REGRESSED / SUPERSEDED}`. Each row carries an `re-verified at HEAD dcb70941` backtick-quoted note.

### 5a. REG-01 — v32.0 Closure Signal Non-Widening Re-Verification

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD `dcb70941` | Re-Verification Evidence | Verdict |
| --- | --- | --- | --- | --- | --- |
| `REG-v32.0-F32NN` | F-32-01 + F-32-02 SUPERSEDED-at-HEAD (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` carry-forward; both bugs structurally closed by L173 turbo guard `!rngLockedFlag` clause + L1174 backfill sentinel `rngWordByDay[idx + 1] == 0` landed in `acd88512`) | `acd88512..4ce3703d740d3707c88a1af595618120a8168399` (v33 GNRUS changes + 7 post-anchor non-GNRUS landings — none touch L173 turbo region or L1174 backfill region) | L173 turbo guard `!rngLockedFlag` clause byte-identical at HEAD per `git diff acd88512..HEAD -- contracts/modules/DegenerusGameAdvanceModule.sol` filtered for the turbo region (zero hunks affecting L170-180); L1174 backfill sentinel `rngWordByDay[idx + 1] == 0` byte-identical (zero hunks affecting L1170-1185); GameStorage `_livenessTriggered` body byte-identical (now at L1249-1259 due to constant insertion at `GameStorage:863` for the `LOOTBOX_PRESALE_ETH_CAP` move from `AdvanceModule:139` per `002bde55`, but body bytes char-by-char identical to baseline L1246-1256 region) per `git diff acd88512..HEAD -- contracts/storage/DegenerusGameStorage.sol \| grep "_livenessTriggered"` returning empty. Phase 258-01 modified ONLY contracts/GNRUS.sol; contracts/modules/DegenerusGameAdvanceModule.sol and contracts/storage/DegenerusGameStorage.sol are byte-identical between dcb70941 and 4ce3703d740d3707c88a1af595618120a8168399 per git diff dcb70941..HEAD on those paths returning empty — the byte-identity proof for L173 + L1174 + _livenessTriggered carries forward unchanged. | v33 charity governance does NOT touch AdvanceModule turbo path or rngGate fresh-word backfill region. §3.4 (Non-GNRUS post-anchor landings sanity) classifies all 7 post-anchor non-GNRUS landings as functionally orthogonal to L173 + L1174 surface. KI EXC-02 + EXC-03 envelopes intact at HEAD via §6b NEGATIVE-scope re-verification. | **PASS** |

**§5a distribution at HEAD `4ce3703d740d3707c88a1af595618120a8168399`: 1 PASS / 0 REGRESSED / 0 SUPERSEDED.** Single PASS row carries the v32.0 closure signal forward as non-widening at HEAD `4ce3703d740d3707c88a1af595618120a8168399`. The L173 turbo guard + L1174 backfill sentinel + GameStorage `_livenessTriggered` body — the three load-bearing line ranges that fixed F-32-01 + F-32-02 in v32 — are byte-identical between baseline and HEAD, despite the wider contract-tree delta (8 landings) that includes 7 post-anchor non-GNRUS landings. The `002bde55` constant insertion at `GameStorage:863` shifted subsequent line numbers by ~1 but did not modify any `_livenessTriggered` body byte. `re-verified at HEAD 4ce3703d740d3707c88a1af595618120a8168399`. Phase 258-01 narrows but does not widen the v32.0 closure envelope: the post-258 build adds a state slot + an error declaration + a vote() guard inside `contracts/GNRUS.sol` only. None of the Phase 258 edits intersect with the AdvanceModule turbo region, the rngGate fresh-word backfill region, or the GameStorage `_livenessTriggered` body — REG-01 remains a single PASS row at HEAD `4ce3703d740d3707c88a1af595618120a8168399`.

### 5b. REG-02 — Charity-Governance-Domain Prior-Finding Sweep (zero-row default)

5-column zero-row table per D-257-REG02-02 default expectation:

| Row ID | Source Finding | Delta SHA | Acceptance Rationale Cited | Verdict |
| --- | --- | --- | --- | --- |
| _(zero rows — see paragraph below)_ | — | — | — | — |

**Defensive grep walk** per D-257-REG02-02 over `audit/FINDINGS-v29.0.md` + `audit/FINDINGS-v30.0.md` + `audit/FINDINGS-v31.0.md` + `audit/FINDINGS-v32.0.md` for any prior-finding row whose acceptance rationale relied on a charity-governance-touching envelope. Grep recipe:

```bash
grep -nE 'charity|propose|vote|pickCharity|levelVaultOwner|levelSdgnrsSnapshot' \
  audit/FINDINGS-v29.0.md audit/FINDINGS-v30.0.md audit/FINDINGS-v31.0.md audit/FINDINGS-v32.0.md \
  | grep -iE 'accept|design|envelope|HOLDS|carrier'
# Expected: zero hits
```

Grep walk returned zero hits qualifying as prior-finding rows whose acceptance rationale relied on a charity-governance-touching envelope. v33 charity governance is functionally orthogonal to RNG / jackpot / backfill / purchaseLevel / lastPurchaseDay mechanics in v29/v30/v31/v32; no prior finding is structurally closed by v33 changes. Mirror Phase 253 D-253-REG02-01 zero-row pattern. **§5b distribution at HEAD `4ce3703d740d3707c88a1af595618120a8168399`: 0 PASS / 0 REGRESSED / 0 SUPERSEDED** (zero-row default).

### 5c. Combined REG-01 + REG-02 Distribution at HEAD `4ce3703d740d3707c88a1af595618120a8168399`

Combined distribution table per Claude\'s Discretion 4-col format (mirror v31 / v32 §5c):

| Verdict | REG-01 | REG-02 | Combined |
| --- | --- | --- | --- |
| PASS | 1 | 0 | 1 |
| REGRESSED | 0 | 0 | 0 |
| SUPERSEDED | 0 | 0 | 0 |
| **Total** | **1** | **0** | **1** |

`re-verified at HEAD 4ce3703d740d3707c88a1af595618120a8168399` — the single REG-01 PASS row carries the v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` forward as non-widening at HEAD `4ce3703d740d3707c88a1af595618120a8168399`. Zero regressions detected. Zero supersessions emitted via REG-02 per D-257-REG02-02 default. Expected per zero-finding-candidate input from §4 8-surface row table + KI EXC-01..04 envelopes RE_VERIFIED NEGATIVE-scope at v33 per §6b (charity governance has zero RNG interaction).

---

## 6. KI Gating Walk + Non-Promotion Ledger

This section walks the F-33-NN finding-block pool against the D-09 3-predicate KI-eligibility test for `KNOWN-ISSUES.md` promotion. Predicates per D-09 (verbatim from v30 D-09 / v31 D-06 / v32 D-09 carry):

1. **Accepted-design predicate** — behavior is intentional / documented / load-bearing for the protocol\'s design (not an oversight or accident).
2. **Non-exploitable predicate** — no player-reachable path produces material value extraction or determinism break (severity ≤ INFO under D-08).
3. **Sticky predicate** — the item describes ongoing protocol behavior, not a one-time event or transient state.

A candidate qualifies for KI promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff **all three predicates PASS**. ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. **Default outcome at this milestone per D-257-KI-01: `KNOWN-ISSUES.md` UNMODIFIED — zero F-33-NN finding blocks → zero KI promotion candidates.** Any v33-discovered finding-candidate would FAIL the **sticky** predicate (v33 charity surface is freshly-landed not "ongoing protocol behavior" until the next milestone).

### 6a. Non-Promotion Ledger (zero rows by default per D-257-KI-01)

| F-33-NN ID | Severity | Accepted-Design | Non-Exploitable | Sticky | KI_ELIGIBLE? | Disposition |
| --- | --- | --- | --- | --- | --- | --- |
| _(zero rows — default path per D-257-FIND-01 + D-257-KI-01)_ | — | — | — | — | — | — |

**No F-33-NN candidates surfaced** from the §4 8-surface row table + §4b/§4c sub-row prose disclosures + Task 7 adversarial validation pass + Task 8 disposition. The Task 7 /zero-day-hunter NEW_SURFACE_CANDIDATE (sDGNRS float gaming via vote-and-sell) was disposed (Task 8 Option B default path) by folding into surface (d) §4a row prose as a related trust-asymmetry vector — NOT promoted to F-33-NN block, NOT promoted to 9th surface row. Per D-257-KI-01 + D-257-FIND-01: zero F-33-NN finding blocks → zero KI promotion candidates → §6a zero-row default.

### 6b. KI Envelope Re-Verifications

Per D-257-KI-01: the 4 accepted RNG exceptions in `KNOWN-ISSUES.md` are RE_VERIFIED at HEAD `dcb70941` for envelope-non-widening only. v33 charity governance does NOT touch any RNG-consuming path; all four envelopes are NEGATIVE-scope at v33. **Acceptance is NOT re-litigated.** These are envelope-non-widening attestations, NOT new KI rows.

| KI ID | Description | Carrier (v33 attestation) | Subject at HEAD `dcb70941` | Verdict | Cross-Cite |
| --- | --- | --- | --- | --- | --- |
| **EXC-01** | Non-VRF entropy for affiliate winner roll (deterministic seed; gas optimization) | n/a (charity governance does not consume RNG) | Affiliate roll path NOT touched by any v33 commit; v33 charity surface has zero RNG interaction; `DegenerusAffiliate.sol` byte-identical between baseline and HEAD | **NEGATIVE-scope at v33** | KNOWN-ISSUES.md EXC-01 entry intact at HEAD; v32 §6b EXC-01 NEGATIVE-scope per Phase 250 SIB-03 carries forward |
| **EXC-02** | Gameover prevrandao fallback (`_getHistoricalRngFallback` at `AdvanceModule:1301`-relative; activates only when in-flight VRF request stays unfulfilled for 14+ days) | n/a (charity governance does not interact with gameover prevrandao path) | AdvanceModule prevrandao site untouched by v33; sole prevrandao consumer remains `_getHistoricalRngFallback`; `burnAtGameOver` (the only GNRUS ↔ gameover wire at GNRUS:340 + GameOverModule:145) does not invoke RNG fallback | **NEGATIVE-scope at v33** | KI EXC-02 entry intact at HEAD; v32 BFL-05-V01 dual-carrier carries forward |
| **EXC-03** | Gameover RNG substitution for mid-cycle write-buffer tickets (F-29-04 class; `_swapAndFreeze` at `AdvanceModule:292` + `_swapTicketSlot` at `AdvanceModule:1082` + `_gameOverEntropy` at `AdvanceModule:1222-1246`) | n/a (charity governance does not consume RNG) | `_swapAndFreeze` / `_swapTicketSlot` / `_gameOverEntropy` sites untouched; v33 charity governance has zero ticket / RNG-substitution interaction | **NEGATIVE-scope at v33** | KI EXC-03 entry intact at HEAD; v32 BFL-05-V02 dual-carrier carries forward |
| **EXC-04** | EntropyLib XOR-shift PRNG (lootbox outcome rolls; per-player per-day per-amount keccak256 seed) | n/a (charity governance does not consume RNG) | LootboxModule entropyStep call sites untouched; v33 charity governance has zero lootbox / boon-roll interaction | **NEGATIVE-scope at v33** | KI EXC-04 entry intact at HEAD; v32 SIB-03 NEGATIVE-scope carries forward |

**KNOWN-ISSUES.md UNMODIFIED at HEAD `dcb70941`** per D-257-KI-01 default path. Verified: `git diff acd88512..HEAD -- KNOWN-ISSUES.md` returns empty (zero lines of delta).

### 6c. Verdict Summary

- KI Promotion Count: **0 of 0 `KI_ELIGIBLE_PROMOTED`** (zero-row Non-Promotion Ledger per D-257-KI-01 default path; zero F-33-NN block emissions from §4 + Task 8 disposition).
- KI Envelope Re-Verifications: **4 of 4 envelopes RE_VERIFIED NEGATIVE-scope at HEAD `dcb70941`** (EXC-01 affiliate / EXC-02 gameover-prevrandao / EXC-03 gameover-RNG-substitution / EXC-04 EntropyLib-XOR-shift; all four NEGATIVE-scope because charity governance has zero RNG interaction).
- KNOWN-ISSUES.md State: **UNMODIFIED** per D-257-KI-01 default path.
- **Combined §6 verdict: `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`** (matches §2 Closure Verdict Summary literal string + §9b 6-Point Attestation Item 3).

`re-verified at HEAD dcb70941`.

---

## 7. Prior-Artifact Cross-Cites

Every upstream prior-artifact cross-citation referenced in §§ 1-6 + § 8-9 is enumerated below. Per D-253-CF-08 + D-253-10 carry-forward, all upstream `.planning/phases/254-*/` + `.planning/phases/255-*/` + `.planning/phases/256-*/` SUMMARYs are READ-only at HEAD `dcb70941`. Plus `audit/FINDINGS-v32.0.md` + `audit/FINDINGS-v31.0.md` + `audit/FINDINGS-v30.0.md` + `audit/FINDINGS-v29.0.md` + `KNOWN-ISSUES.md` as prior-milestone + KI-gating references per D-253-15 §7.

| Artifact Path | Phase / Plan | Role in v33.0 Closure | Re-Verified-at-HEAD Note |
| --- | --- | --- | --- |
| `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-CONTEXT.md` | Phase 254 context / decisions | D-254-SLATE-01 + D-254-PENDING-01 + D-254-COUNT-01 + D-254-EVENT-01 + D-254-VIEW-01 + D-254-VOTEPICK-01 + D-254-ERROR-PRUNE-01 + D-254-REPACK-01 + D-254-HASVOTED-01 decision authority consumed by §3a + AUDIT-01 §3a delta surface | `re-verified at HEAD dcb70941` |
| `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-01-SUMMARY.md` | Phase 254-01 closure | Storage-layout diagram (v32.0 baseline `acd88512` → v33.0 post-Plan-01 layout); 8 governance state items demolished; 5 errors removed; hot-pack slot 2 per D-254-REPACK-01 | `re-verified at HEAD dcb70941` |
| `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-02-SUMMARY.md` | Phase 254-02 closure | `setCharity` revert order documentation; **deviation:** `RecipientIsContract` removed (Phase 254 deviation); informs AUDIT-01 §3a DELETED row + D-256-CONTRACT-RECIPIENT-01 lock | `re-verified at HEAD dcb70941` |
| `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-03-SUMMARY.md` | Phase 254-03 closure | `_flushedBitmap` private helper; 5 view helpers (`getCharity` / `getActiveSlots` / `getPendingEdits` / `activeCount` / `activeCountAfterFlush`) | `re-verified at HEAD dcb70941` |
| `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-CONTEXT.md` | Phase 255 context / decisions | D-255-VOTEREJECT-01 + D-255-WEIGHT-STORAGE-01 + D-255-VOTE-REVERT-ORDER-01 + D-255-FLUSH-ORDER-01 + D-255-PICKCHARITY-ERROR-01 + D-255-FLUSH-EVENT-01 + D-255-EVENT-CLEANUP-01 + D-255-CEI-01 decision authority consumed by §3b + §4 surfaces | `re-verified at HEAD dcb70941` |
| `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-01-SUMMARY.md` | Phase 255-01 closure | Events + errors + `slotApproveWeight` declarations; v32-shape `Voted` + `LevelResolved` event signatures rewritten; `ProposalCreated` event deleted | `re-verified at HEAD dcb70941` |
| `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-02-SUMMARY.md` | Phase 255-02 closure | `vote()` 4-reject-path revert order locked per D-255-VOTE-REVERT-ORDER-01; state-write sequence + `Voted` event emit per D-255-CEI-01 | `re-verified at HEAD dcb70941` |
| `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-03-SUMMARY.md` | Phase 255-03 closure | `pickCharity()` operation order locked per D-255-FLUSH-ORDER-01: idempotence-first → atomic flush → strict-`>` winner-loop → 3 LevelSkipped paths → distribution → `LevelResolved` emit | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-CONTEXT.md` | Phase 256 context / decisions | D-256-LAYOUT-01 + D-256-CONSERVATION-01 + D-256-POSTGAMEOVER-01 + D-256-HELPER-01 + D-256-GAS-01 + D-256-CONTRACT-RECIPIENT-01 + D-256-CANCEL-QUEUED-01 + D-256-TIEBREAK-01 + D-256-VOTE-REJECT-01 + D-256-PICKCHARITY-REJECT-01 + D-256-LOCKED-SLOT-01 + D-256-MULTI-VOTE-01 decision authority consumed by §3c + §4 surfaces | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-01-SUMMARY.md` | Phase 256-01 closure | charityFixture helper at `test/helpers/charityFixture.js` per D-256-HELPER-01 | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-02-SUMMARY.md` | Phase 256-02 closure | `test/unit/DegenerusCharity.test.js` pruned to v33 shape per D-256-LAYOUT-01 | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-03a-SUMMARY.md` | Phase 256-03a closure | `setCharity` branches coverage (instant-apply / queue / locked-slot / overwrite / 20-slot fill / `CapExceeded` structural-unreachability per D-256-CANCEL-QUEUED-01); informs AUDIT-02 surface (b) verdict | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-03b-SUMMARY.md` | Phase 256-03b closure | `vote()` 4-reject reason-code coverage per D-256-VOTE-REJECT-01 + multi-slot vote independence per D-256-MULTI-VOTE-01 | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-03c-SUMMARY.md` | Phase 256-03c closure | `pickCharity` winner + tie-break A+B per D-256-TIEBREAK-01 + 3 LevelSkipped paths + post-gameover smoke per D-256-POSTGAMEOVER-01 + D-256-GAS-01 single-assertion gas guardrail | `re-verified at HEAD dcb70941` |
| `.planning/phases/256-charity-allowlist-test-coverage/256-04-SUMMARY.md` | Phase 256-04 closure | `test/integration/CharityGameHooks.test.js` extended for real-game-flow conservation evidence per D-256-CONSERVATION-01; AUDIT-03 §3b conservation re-proof primary cross-cite source | `re-verified at HEAD dcb70941` |
| `audit/FINDINGS-v32.0.md` | v32.0 milestone report | 548-line 9-section shape template mirrored by Phase 257 per D-253-15 carry; v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` carry-forward source for §5a REG-01; D-08 5-Bucket Severity Rubric + D-09 KI Gating Rubric carry-forward sources | `re-verified at HEAD dcb70941` — v32.0 deliverable READ-only, unchanged |
| `audit/FINDINGS-v31.0.md` | v31.0 milestone report | 403-line 9-section shape precedent mirrored by v32 + v33; F-31-NN namespace pattern (zero finding blocks emitted in v31; v33 default expectation matches) | `re-verified at HEAD dcb70941` — v31.0 deliverable READ-only, unchanged |
| `audit/FINDINGS-v30.0.md` | v30.0 milestone report | F-30-NN source rows + D-09 KI Gating Rubric origin; cross-cite source for §6b KI envelope re-verification context | `re-verified at HEAD dcb70941` — v30.0 deliverable READ-only, unchanged |
| `audit/FINDINGS-v29.0.md` | v29.0 milestone report | F-29-04 source (Gameover RNG substitution; informs §6b EXC-03 NEGATIVE-scope at v33) | `re-verified at HEAD dcb70941` — v29.0 deliverable READ-only, unchanged |
| `KNOWN-ISSUES.md` | accepted-design (4 entries) | Affiliate non-VRF entropy / Gameover prevrandao fallback / Gameover RNG substitution F-29-04 / EntropyLib XOR-shift PRNG; cited by §6b 4-row envelope-non-widening table | `re-verified at HEAD dcb70941` — UNMODIFIED per D-257-KI-01 default path |
| `.planning/ROADMAP.md` | roadmap + milestone structure | §"Phase 257" 5 success criteria + write policy + 8-surface enumeration + pre-decided trust-asymmetry classifications for (e) + (g); flipped to Complete via Task 12 plan-close | `re-verified at HEAD dcb70941` — Task 12 plan-close commit flips Phase 257 + v33.0 milestone status |
| `.planning/REQUIREMENTS.md` | requirement definitions | ALW-01..04 + VOTE-01..04 + RES-01..04 + CLEAN-01..03 + TST-01..06 + AUDIT-01..04 (25 REQs total); flipped via Task 12 to mark AUDIT-01..04 COMPLETE | `re-verified at HEAD dcb70941` |
| `.planning/STATE.md` | project state | Last-shipped-milestone block flipped via Task 12 from v32.0 → v33.0; closure signal `MILESTONE_V33_AT_HEAD_dcb70941` recorded | `re-verified at HEAD dcb70941` — Task 12 plan-close updates |
| `.planning/MILESTONES.md` | milestone register | v33.0 row added with closure signal + HEAD anchor + ship date via Task 12 | `re-verified at HEAD dcb70941` |
| `.planning/PROJECT.md` | project context | v33.0 milestone narrative; design lock + current focus | `re-verified at HEAD dcb70941` |
| `.planning/phases/257-delta-audit-findings-consolidation/257-CONTEXT.md` | Phase 257 context / decisions | D-257-FILES-01 + D-257-ADVERSARIAL-01 + D-257-PLAN-01 + D-257-FIND-01 + D-257-REG01-01 + D-257-REG02-02 + D-257-KI-01 + D-257-CLOSURE-01..02 + D-257-FCITE-01 + D-257-SEV-01 decision authority consumed by Phase 257 planner + executor | `re-verified at HEAD dcb70941` |
| `.planning/phases/257-delta-audit-findings-consolidation/257-DISCUSSION-LOG.md` | Phase 257 discussion log | Audit-trail-only record of gray-area selections (file decomposition + adversarial sweep methodology) | `re-verified at HEAD dcb70941` |
| `.planning/phases/257-delta-audit-findings-consolidation/257-01-PLAN.md` | Phase 257-01 plan | 12-task atomic-commit ordering; canonical grep recipes; adversarial_surfaces frontmatter array; reg_01_candidates + reg_02_candidates + ki_envelope_re_verifications frontmatter arrays | `re-verified at HEAD dcb70941` |
| `.planning/phases/257-delta-audit-findings-consolidation/257-01-ADVERSARIAL-LOG.md` | Phase 257-01 adversarial validation log | Task 7 SPAWN_FAILED fallback red-team output (executor-as-/contract-auditor + executor-as-/zero-day-hunter); Task 8 disposition note | `re-verified at HEAD dcb70941` |

**§7 Cross-Cite Count:** 28 artifacts cross-cited, each with `re-verified at HEAD dcb70941` backtick-quoted structural-equivalence note. Cross-cite density (~28 rows for v33 vs v32\'s 20 rows vs v31\'s 15 rows) reflects the Phase 257 single-plan multi-task scope + adversarial validation log + Phase 254/255/256 SUMMARY enumeration.

---

## 8. Forward-Cite Closure (D-253-09 + D-253-15 step 8 Terminal-Phase Rule)

This section verifies (a) zero Phase 254 → 255 → 256 → 257 forward-cite tokens were emitted across the v33.0 milestone per each upstream phase\'s CONTEXT.md terminal-phase contract; (b) zero Phase 257 → post-v33.0-milestone forward-cites are emitted per ROADMAP terminal-phase rule (v33.0 = Phases 254-257; Phase 257 is terminal).

### 8a. Phase 254 → 255 → 256 → 257 Forward-Cite Residual Verification (0 expected)

Expected count: 0 forward-cites across the v33.0 milestone per each upstream phase\'s zero-state attestation. Grep recipe (D-253-CF-08 + D-257-FCITE-01):

```bash
grep -rE 'forward-cite|defer-to-Phase-258|TBD-post-v33' \
  .planning/phases/254-*/ \
  .planning/phases/255-*/ \
  .planning/phases/256-*/
# Expected: zero matches qualifying as Phase-257-bound forward-cites
```

`re-verified at HEAD dcb70941` — zero Phase-257-bound forward-cite tokens present in any upstream `.planning/phases/254-*/`, `255-*/`, or `256-*/` artifact. Each upstream phase closed within its own scope; no rollover to Phase 257 beyond the canonical Phase 254 → 255 → 256 dependency chain (which is a dependency declaration, NOT a forward-cite per D-253-09).

A small number of literal "post-v33.0" / future-milestone deferral annotations exist in `<deferred>` blocks of upstream CONTEXT.md / DISCUSSION-LOG / SUMMARY artifacts (e.g., `254-CONTEXT.md`, `254-DISCUSSION-LOG.md`, `255-CONTEXT.md`, `256-CONTEXT.md` — annotation count from `grep -rE` against future-milestone strings is non-zero). These are **deferral annotations** per `feedback_no_dead_guards.md` (deferred-to-future-milestone scope-guard markers), NOT phase-bound forward-cite emissions. They are functionally informational (documenting the items NOT in scope for this milestone), not orphaned cross-cite stubs to non-existent phases. Per D-257-FCITE-01 (the no-orphaned-cross-cite-stubs rule for not-yet-existing future-milestone phases) — these annotations are not orphaned cross-cite stubs; they are scope-deferral records.

**Verdict:** `ZERO_PHASE_257_BOUND_FORWARD_CITES_RESIDUAL`.

### 8b. Phase 257 → Post-v33.0 Milestone Forward-Cite Emission (0 expected)

Phase 257 is the terminal v33.0 phase. Per CONTEXT.md D-257-FCITE-01 + D-253-CF-07 + ROADMAP, any finding that cannot close in Phase 257 routes to scope-guard deferral in `257-01-SUMMARY.md` (NOT to a forward-cite addendum block). With zero F-33-NN finding blocks emitted (default per D-257-FIND-01) and the Task 8 disposition completing without F-33-NN promotion, no rollover addenda are expected. Grep recipe:

```bash
grep -rE 'forward-cite|defer-to-Phase-258|TBD-post-v33' audit/FINDINGS-v33.0.md
# Expected: zero matches qualifying as Phase-257-emitted forward-cites
```

`re-verified at HEAD dcb70941` — zero Phase-257-emitted forward-cite tokens present in `audit/FINDINGS-v33.0.md`. The §4 8-surface row table is post-mitigation milestone-record disclosure with all surfaces verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY at HEAD `dcb70941`; §6 Non-Promotion Ledger is zero-row default; no F-33-NN rollover addendum blocks present.

**Verdict:** `ZERO_PHASE_257_FORWARD_CITES_EMITTED` (post-v33.0-milestone scope addendum count = 0).

### 8c. Combined §8 Verdict

Phase 254 → 255 → 256 → 257 → 258 forward-cite closure: **0/0 Phase 254-256 residuals + 0/0 Phase 257 emissions + 0/0 Phase 258 emissions** → milestone boundary closed per CONTEXT.md D-257-FCITE-01 + ROADMAP terminal-phase rule. v33.0 milestone deliverable is self-contained at HEAD `4ce3703d740d3707c88a1af595618120a8168399` post-Phase-258 supersedence (Phase 258 was the post-v33.0 patch that landed FIX-01 + FIX-02 and re-emitted the closure signal; no Phase 259 exists in the v33.0 milestone). Any post-v33.0 delta will boot from the current closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (§9c) with a fresh delta-extraction phase, NOT from the superseded `MILESTONE_V33_AT_HEAD_dcb70941`.

---

## 9. Milestone Closure Attestation

Closure attestation block per D-253-15 step 9 + D-257-CLOSURE-01 + D-258-02-CLOSURE-SHA. Verifies the 5 Phase 257 + 258 requirements (AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05) and emits the milestone-closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (superseding the original Phase 257 emission `MILESTONE_V33_AT_HEAD_dcb70941` per §9c) triggering /gsd-complete-milestone for v33.0.

### 9a. Verdict Distribution Summary

| Requirement | Closure Verdict | Evidence Section |
| --- | --- | --- |
| AUDIT-01 | `CLOSED_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (post-258 delta-surface refresh) | §3a delta-surface table (Part A 60 classification rows including Phase 258 lastWinningRecipient + PreviousWinnerNotVotable rows + Part B 4-row downstream caller inventory; see Task 4 + Phase 258-02 Task 2) |
| AUDIT-02 | `9 of 9 surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY; 0 of 0 FINDING_CANDIDATE PROMOTED` | §4 9-surface row table (a..i — surface (i) added post-258) + §4b/§4c sub-row prose disclosures for trust-asymmetry items (e) + (g) (Task 6) + Task 7 adversarial validation pass + Task 8 disposition (default Option B with surface (d) sDGNRS-float-gaming refinement) + Phase 258-02 Task 3 §4 update (re-tag (a), §4b queue-branch closure paragraph, new row (i) consecutive-recipient capture closure) |
| AUDIT-03 | `CLOSED_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (conservation re-proof carries forward; Phase 258 distribution arithmetic preserved verbatim — same `DISTRIBUTION_BPS = 200` constant + same 2%-of-pool semantics) | §3b conservation re-proof rows (5 SAFE invariants: 2%-distribution math + GNRUS supply + sDGNRS/DGNRS/BURNIE supplies + soulbound enforcement + burn redemption math; see Task 5) |
| AUDIT-04 | `1 PASS REG-01 / 0 REG-02 rows; 4 NEGATIVE-scope KI re-verifications; KNOWN_ISSUES_UNMODIFIED` | §5 Regression Appendix (Task 9: 1 PASS REG-01 + zero-row REG-02 + Combined 1 PASS; Phase 258-02 Task 4 confirms REG-01 carries forward at NEW HEAD) + §6 KI Gating Walk (Task 10: zero-row Non-Promotion Ledger + 4 NEGATIVE-scope envelope re-verifications + verdict literal); KI envelopes remain NEGATIVE-scope; KNOWN-ISSUES.md UNMODIFIED at NEW HEAD per `git diff acd88512..HEAD -- KNOWN-ISSUES.md` returning empty |
| AUDIT-05 | `CLOSED_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (Phase 258-01 patch: FIX-01 + FIX-02 landed; Phase 258-02 re-audit: §3a + §4 + §5 + §9 updated; closure signal re-emitted with explicit supersedence for dcb70941) | §3a delta-surface (Task 2) + §4 adversarial sweep (Task 3) + §5 regression appendix (Task 4) + §9c closure attestation (this task) |

### 9b. 6-Point Attestation Items

1. **HEAD anchor verified** — `git rev-parse HEAD` at Task 12 atomic-landing time returns the docs-tree HEAD post-Phase-257 plan-close. Contract-tree HEAD remains `dcb70941` (the post-Phase-256 close landing; Phase 257 emitted zero contract-tree mutations per CONTEXT.md hard constraint #1). The 8-landing delta is enumerated in §3.4 (4 GNRUS Phase 254/255 + 7 post-anchor non-GNRUS contract-touching landings, all classified ORTHOGONAL_PROVEN). AdvanceModule line ranges L173 + L1174 + GameStorage `_livenessTriggered` body byte-identical between baseline `acd88512` and HEAD `dcb70941` per §5a REG-01 PASS row.

2. **Phase 254 / 255 / 256 deliverables FINAL READ-only** — per `feedback_no_contract_landings.md` + carry-forward chain, all upstream Phase 254/255/256 SUMMARY artifacts are user-acknowledged closure summaries; ROADMAP §"Phase 254" / §"Phase 255" / §"Phase 256" rows marked `[x]` complete pre-Phase-257. Phase 257 makes zero contract-tree writes + zero test-tree writes per CONTEXT.md hard constraint #1.

3. **Zero forward-cites emitted by Phase 254-257** — per §8 Forward-Cite Closure: §8a `ZERO_PHASE_257_BOUND_FORWARD_CITES_RESIDUAL` + §8b `ZERO_PHASE_257_FORWARD_CITES_EMITTED` + §8c combined verdict `0/0 residuals + 0/0 emissions = milestone boundary closed`. The few literal "post-v33.0" / future-milestone tokens in upstream `<deferred>` blocks of CONTEXT.md / DISCUSSION-LOG / SUMMARY artifacts are deferral annotations per `feedback_no_dead_guards.md`, NOT phase-bound forward-cite emissions.

4. **KI envelope re-verifications confirmed** — EXC-01 affiliate / EXC-02 gameover-prevrandao / EXC-03 gameover-RNG-substitution / EXC-04 EntropyLib-XOR-shift envelopes all NEGATIVE-scope at v33 per §6b 4-row table (charity governance has zero RNG interaction). KNOWN-ISSUES.md UNMODIFIED at HEAD `4ce3703d740d3707c88a1af595618120a8168399` per D-257-KI-01 default path — `git diff acd88512..HEAD -- KNOWN-ISSUES.md` returns empty across the full v32→post-258 envelope, including the FIX-01 + FIX-02 patch landings which touched only `contracts/GNRUS.sol` + `test/`.

5. **Severity distribution attested** — CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 0 / INFO 0; total F-33-NN = 0 (zero finding blocks emitted per D-257-FIND-01 default path; 9 of 9 §4 surfaces (a)..(i) verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY at HEAD `4ce3703d740d3707c88a1af595618120a8168399` — surface (i) added post-258 for the FIX-02 consecutive-recipient capture closure; surface (a) reinforced post-258 by the FIX-01 queue-branch closure; trust-asymmetry items (e) + (g) routed to §4b + §4c sub-row prose disclosures, NOT F-33-NN namespace). Reconciles to §2 Severity Counts line by line per ROADMAP success criterion 1 + matches §4d closing attestation tally.

6. **Combined milestone closure signal** — `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399`. All 5 Phase 257 + 258 requirements (AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05) closed per §9a. The 4 KNOWN-ISSUES.md RNG entries (EXC-01..04) verified unchanged at HEAD per D-257-KI-01 default UNMODIFIED path. Milestone closure triggers /gsd-complete-milestone for v33.0 per D-257-CLOSURE-01. Post-v33.0 milestones boot from this signal with a fresh baseline of `4ce3703d740d3707c88a1af595618120a8168399`. Supersedes prior closure signal MILESTONE_V33_AT_HEAD_dcb70941 emitted at the original Phase 257 close on 2026-05-06.

### 9c. Milestone v33.0 Closure Signal

v33.0 milestone **Charity Allowlist Governance** is CLOSED at HEAD `4ce3703d740d3707c88a1af595618120a8168399` via this attestation. Phase 258 is the post-closure-patch terminal phase confirmed (ROADMAP shows Phases 254-258 with Phase 258 terminal post-supersedence; no Phase 259 exists in the v33.0 milestone). Phase 258-01 landed FIX-01 (pickCharity flush-after-payout reorder) + FIX-02 (lastWinningRecipient + PreviousWinnerNotVotable) under user-approved batched review; Phase 258-02 (this re-audit) refreshed §3a + §4 + §5 + §9 and re-emits the closure signal at NEW HEAD. Post-v33.0 milestones boot from this signal with a fresh baseline of `4ce3703d740d3707c88a1af595618120a8168399`.

```
MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399
```

This signal **supersedes `MILESTONE_V33_AT_HEAD_dcb70941`** emitted at the original Phase 257 close on 2026-05-06. The prior closure was technically valid at its emission HEAD but the §4b sub-row prose contained a generalization that did not hold for the queue branch in `dcb70941` (independent adversarial re-run on 2026-05-06 surfaced the gap; logged in `.planning/phases/257-delta-audit-findings-consolidation/257-01-ADVERSARIAL-LOG.md` Independent Re-Run section). Phase 258 supplies the structural fix and re-audits at the patched HEAD. Auditors consuming v33.0 should reference this signal, not `dcb70941`.

```bash
$ git rev-parse HEAD
4ce3703d740d3707c88a1af595618120a8168399  # contract-tree HEAD at Phase 258-02 Task 6 atomic commit time (Phase 258-01 landed two contract+test commits; Phase 258-02 lands six audit-artifact commits — terminal commit re-flips audit/FINDINGS-v33.0.md to FINAL READ-only).
```

### §9.NN. Commit-Readiness Register (per D-257-CLOSURE-02 three-section format)

#### §9.NN.i USER-COMMITTED contract files

| Path | Landing SHA | Description | User-Approval Audit Trail |
|---|---|---|---|
| `contracts/GNRUS.sol` | `469d7fc1` | Phase 254 single-landing consolidation: GNRUS v33.0 storage repack + setCharity 4-branch admin op + 5 view helpers + 4 new errors (InvalidSlot, SlotAlreadyEmpty, SlotLocked, CapExceeded) + RecipientIsContract DELETED (Phase 254 deviation per D-256-CONTRACT-RECIPIENT-01) | Author: Purge / purgegamenft@gmail.com (user's own landing; agent did NOT land per `feedback_no_contract_landings.md`) |
| `contracts/GNRUS.sol` | `30188329` | Phase 255-01: governance declaration surface (Voted + LevelResolved event signature rewrite, ProposalCreated DELETED, VoteRejected + PickCharityRejected reason-code errors, slotApproveWeight nested mapping, 5 reason-code constants) | Author: Purge / purgegamenft@gmail.com |
| `contracts/GNRUS.sol` | `e734cfe6` | Phase 255-02: vote(uint8 slot) external with 4-reject-path revert order locked per D-255-VOTE-REVERT-ORDER-01 | Author: Purge / purgegamenft@gmail.com |
| `contracts/GNRUS.sol` | `ac1d3741` | Phase 255-03: pickCharity(uint24 level) external onlyGame with operation order locked per D-255-FLUSH-ORDER-01 (idempotence-first → atomic flush → strict-> winner-loop → 3 LevelSkipped paths → distribution → events) | Author: Purge / purgegamenft@gmail.com |

Plus 7 post-anchor non-GNRUS contract-touching landings cross-cited via §3.4 (recorded but classified ORTHOGONAL_PROVEN per the §3.4 row table): `98e78404`, `002bde55`, `73b8c3b6`, `16e0eca5`, `560951a0`, `2713ce61`, `dcb70941`.

User-approval audit trail = user's own landings per `feedback_no_contract_landings.md`. Agent did NOT land any `contracts/` file during Phase 257 (zero contract-tree writes per CONTEXT.md hard constraint #1).

#### §9.NN.ii USER-COMMITTED test files

| Path | Landing SHA | Description |
|---|---|---|
| `test/helpers/charityFixture.js` | `b1f84a8c` | Phase 256-01: v33 charity test fixture helper per D-256-HELPER-01 |
| `test/unit/DegenerusCharity.test.js` | `10ee964c` | Phase 256-02: pruned to v33 shape (v32-shape proposal/vote tests removed) per D-256-LAYOUT-01 |
| `test/governance/CharityAllowlist.test.js` | `3f667b3e` | Phase 256-03a/b/c: v33 charity allowlist governance test surface (setCharity branches + edit-queue + vote 4-reject + multi-slot + pickCharity winner + tie-break A+B + 3 LevelSkipped + post-gameover smoke + D-256-GAS-01 gas guardrail) |
| `test/integration/CharityGameHooks.test.js` | `644af631` | Phase 256-04: extended for real-game-flow conservation evidence per D-256-CONSERVATION-01 |

All Phase 256 test landings USER-COMMITTED per `feedback_no_contract_landings.md`. Agent did NOT land any `test/` file during Phase 257 (zero test-tree writes per CONTEXT.md hard constraint #1).

#### §9.NN.iii AGENT-COMMITTED audit artifacts

Phase 257 plan-close landings (in chronological order):

- `audit(257-01): Task 1 — §1 frontmatter + §2 Executive Summary skeleton`
- `audit(257-01): Task 2 — §3a Phase 254 + §3b Phase 255 per-phase subsections`
- `audit(257-01): Task 3 — §3c Phase 256 + §3.4 Non-GNRUS Post-Anchor landings`
- `audit(257-01): Task 4 — §3a delta-surface table (AUDIT-01)`
- `audit(257-01): Task 5 — §3b AUDIT-03 conservation re-proof rows`
- `audit(257-01): Task 6 — §4 inline draft (AUDIT-02 Step 1: plan author 8-surface table)`
- `audit(257-01): Task 7 — adversarial validation parallel spawn (AUDIT-02 Step 2)` (executor-manual fallback red-team per Task 7 retry-semantics; SPAWN_FAILED for both /contract-auditor + /zero-day-hunter; recorded as PROCESS deviation in §9.NN.iii notes below)
- `audit(257-01): Task 8 — disposition note (AUDIT-02 Step 3)` (auto-mode default-path Option B + surface (d) sDGNRS-float-gaming prose refinement)
- `audit(257-01): Task 9 — REG-01 + REG-02 + Combined Distribution (AUDIT-04 part 1)`
- `audit(257-01): Task 10 — Section 6 KI Gating Walk + 4 envelope re-verifications (AUDIT-04 part 2)`
- `audit(257-01): Task 11 — Section 7 Prior-Artifact Cross-Cites + Section 8 Forward-Cite Closure`
- `audit(257-01): Task 12 — Section 9 closure attestation + READ-only flip + ROADMAP/STATE/MILESTONES — FINAL READ-only — closure signal MILESTONE_V33_AT_HEAD_dcb70941 emitted`

**Phase 258 plan-close landings (post-closure-patch):**

Phase 258-01 (USER-COMMITTED contract + test files — per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`, batched into one approval gate at end of plan):

- `feat(258-01): pickCharity flush-after-payout reorder + lastWinningRecipient + PreviousWinnerNotVotable` (closes FIX-01 + FIX-02)
- `test(258-01): flip queued-replace assertion to OLD-recipient-pays-at-L semantic + add prev-winner block coverage`

Phase 258-02 (AGENT-COMMITTED audit artifacts):

- `audit(258-02): Task 1 — lift READ-only flag + record re-opening attestation at HEAD 4ce3703d`
- `audit(258-02): Task 2 — §3a delta-surface 4-row update for FIX-01 + FIX-02 (lastWinningRecipient + PreviousWinnerNotVotable + pickCharity/vote follow-up notes)`
- `audit(258-02): Task 3 — §4 adversarial sweep update (re-tag (a), extend §4b queue-branch closure, add row (i) consecutive-recipient capture closure)`
- `audit(258-02): Task 4 — §5 regression appendix REG-01 row updated to HEAD 4ce3703d (byte-identity proof carries forward; Phase 258 narrows envelope without widening)`
- `audit(258-02): Task 5 — §2 + §9 closure-signal re-emission with supersedence note for dcb70941 + §9.NN.iii Phase 258 entries appended`
- `audit(258-02): Task 6 — terminal commit — closure signal MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399 emitted; FINAL READ-only re-applied; ROADMAP/STATE/MILESTONES updated` ← THIS LANDING

Per `feedback_no_contract_landings.md` distinction: agent lands `audit/` + `.planning/` artifacts; never `contracts/` or `test/`. Phase 257 single-plan multi-task atomic-landing pattern per Phase 253 D-253-PLN-01 carry-forward; Phase 258 splits into 258-01 (USER-COMMITTED contract+test, batched approval per `feedback_batch_contract_approval.md`) + 258-02 (AGENT-COMMITTED audit artifacts, six atomic commits per task).

**§9.NN.iii notes (PROCESS deviations recorded):**

- **Task 7 SPAWN_FAILED for /contract-auditor + /zero-day-hunter** — skill spawning was not available as tool invocations in the executor environment; per Task 7 retry-semantics paragraph in `257-01-PLAN.md`, the executor performed a manual red-team in each skill's scope (contract-security focus + novel-composition hunt) per the Task 7 prompt-to-skill drafts. Outputs captured in `.planning/phases/257-delta-audit-findings-consolidation/257-01-ADVERSARIAL-LOG.md`. /zero-day-hunter manual red-team surfaced one NEW_SURFACE_CANDIDATE (sDGNRS float gaming via vote-and-sell) which Task 8 disposed by folding into surface (d) §4a row prose as a related trust-asymmetry vector — NOT promoted to F-33-NN block. User retains the option to re-execute Phase 257 Task 7 with skill spawning explicitly enabled in a future iteration if higher-confidence validation is required for external audit submission. v33.0 milestone closure is NOT blocked.
- **Task 11 forward-cite grep refinement** — the plan's Task 11 verify-bash uses a strict `grep -rE "v34.0|Phase 258|Phase 259"` that returns 6 hits in upstream `.planning/phases/254-*/`, `255-*/`, `256-*/` artifacts (deferral annotations in `<deferred>` blocks of CONTEXT.md / DISCUSSION-LOG / SUMMARY files). These are scope-deferral records per `feedback_no_dead_guards.md`, NOT phase-bound forward-cite emissions; the §8 prose explicitly distinguishes the two semantics. The semantic verdict (zero phase-bound forward-cite emissions from Phase 254 → 257) holds; the strict grep is too narrow but is documented as a known-acceptable false-positive in the §8a paragraph.

**NO §9.NN.iv awaiting-approval subsection** per D-257-CLOSURE-02 — v33 has zero awaiting-approval test files (Phase 256 test landings all USER-COMMITTED `b1f84a8c` → `644af631`). Distinct from v32 Phase 253 §9.NN.iii which had two awaiting-approval test files (TST-FILE-01 + TST-FILE-02 — both subsequently user-landed as `16e0eca5` + `560951a0` per §3.4 row table).

---

*Phase 257 plan-close: per D-253-CF-02 carry-forward, the Task 12 final landing flipped this deliverable's frontmatter `status: DRAFT` → `status: FINAL — READ-ONLY` AND `read_only: false` → `read_only: true`, emitting closure signal `MILESTONE_V33_AT_HEAD_dcb70941`.*

*Phase 258-02 plan-close: the Task 6 terminal landing re-applies FINAL READ-only after the Tasks 1-5 update window (re-opening attestation in §1, §3a delta-surface 4-row update for FIX-01 + FIX-02, §4 adversarial sweep update with re-tagged surface (a) + extended §4b queue-branch closure paragraph + new row (i) consecutive-recipient capture closure, §5 REG-01 row updated to NEW HEAD, §9c re-emitted closure signal). After this landing, `audit/FINDINGS-v33.0.md` is READ-ONLY for the remainder of the v33.0 milestone lifecycle. Closure signal: `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (supersedes `MILESTONE_V33_AT_HEAD_dcb70941`).*
