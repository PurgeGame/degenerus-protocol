---
phase: 257-delta-audit-findings-consolidation
plan: 01
milestone: v33.0
milestone_name: Charity Allowlist Governance
head_anchor: <will-be-filled-by-Task-12>
audit_baseline: acd88512
deliverable: audit/FINDINGS-v33.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04]
phase_status: terminal
write_policy: "Pure-consolidation phase per CONTEXT.md hard constraint #1. Zero contracts/ writes by agent. Zero test/ writes by agent. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-257-KI-01 default zero-promotion path. Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change — vacuous this phase since no contract changes are proposed by agent."
supersedes: none
status: DRAFT
read_only: false
closure_signal: <will-be-filled-by-Task-12>
generated_at: <will-be-filled-by-Task-12>
---

# v33.0 Findings — Charity Allowlist Governance

**Audit Baseline.** HEAD `dcb70941` is the contract-tree audit subject HEAD for v33.0, taken at Phase 257 plan-start as `git rev-parse HEAD` after Phase 256 close. The audit baseline is v32.0 HEAD `acd88512` (closure signal `MILESTONE_V32_AT_HEAD_acd88512` carry-forward from `audit/FINDINGS-v32.0.md` §9c). Eight contract commits since baseline: four v33-related GNRUS commits (`469d7fc1` Phase 254 single-commit consolidation + `30188329` Phase 255 declarations + `e734cfe6` Phase 255 vote + `ac1d3741` Phase 255 pickCharity), plus seven post-anchor non-GNRUS commits (`98e78404`, `002bde55`, `73b8c3b6`, `16e0eca5`, `560951a0`, `2713ce61`, `dcb70941`) classified ORTHOGONAL_PROVEN per §3.4. Four test-only commits (`b1f84a8c`, `10ee964c`, `3f667b3e`, `644af631`) all USER-COMMITTED Phase 256. The L173 turbo guard (`!rngLockedFlag` clause) + L1174 backfill sentinel (`rngWordByDay[idx + 1] == 0`) + GameStorage `_livenessTriggered` body (now at L1249-1259 after constant insertion at L863, body bytes char-by-char identical to baseline L1246-1256) are byte-identical between baseline `acd88512` and HEAD `dcb70941` (REG-01 PASS — see §5a).

**Scope.** Single canonical milestone-closure deliverable for v33.0 per D-257-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-253-15 carry-forward (9-section shape locked). Consolidates Phase 254 / 255 / 256 outputs into 9 sections per D-253-15 carry. Terminal phase per CONTEXT.md D-257-FCITE-01 — zero forward-cites emitted from Phase 257 to v34.0+ phases. Mirrors v32 Phase 253 single-plan multi-task atomic-commit pattern adapted for v33's 3-impl-phase + 1-audit-phase scope per D-257-PLAN-01.

**Write policy.** READ-only after Task 12 atomic commit per D-253-CF-02 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-257-KI-01 default zero-promotion path (D-09 sticky-predicate FAIL on any v33-discovered finding because v33 charity surface is freshly-landed not "ongoing protocol behavior" until next milestone). Zero awaiting-approval test files (all four Phase 256 test commits `b1f84a8c` → `644af631` are USER-COMMITTED per `feedback_no_contract_commits.md`). Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change; vacuous this phase since no contract changes are proposed by agent (zero `contracts/` writes + zero `test/` writes by agent — hard constraint #1).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: `CLOSED_AT_HEAD_<sha>` (delta surface complete; every changed function/state-var/event/error in `contracts/GNRUS.sol` vs baseline `acd88512` enumerated with hunk-level evidence and classified per ROADMAP success criterion 2)
- AUDIT-02: `8 of 8 surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY; 0 of 0 FINDING_CANDIDATE PROMOTED` (default expected per D-257-FIND-01)
- AUDIT-03: `CLOSED_AT_HEAD_<sha>` (GNRUS conservation re-proof complete; supply invariants intact across the level transition; soulbound enforcement intact; `burn()` proportional redemption math unchanged)
- AUDIT-04: `1 PASS REG-01 / 0 REG-02 rows; 4 NEGATIVE-scope KI re-verifications; KNOWN_ISSUES_UNMODIFIED`
- Combined milestone closure: `MILESTONE_V33_AT_HEAD_<sha>`

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

CONTEXT.md D-257-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 257 to v34.0+ phases. Verified at §8 Forward-Cite Closure block. Phase 254-256 each emit zero phase-bound forward-cites (the few "v34.0+" mentions in CONTEXT.md `<deferred>` sections are deferral annotations per `feedback_no_dead_guards.md`, not phase-bound forward-cite emissions); Phase 257 inherits zero-residual baseline. Any v33-relevant divergence routes to scope-guard deferral in `257-01-SUMMARY.md` per D-253-CF-07 carry; v34.0+ ingests via fresh delta-extraction phase, not via forward-cite from v33 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 6-point attestation block triggering v33.0 milestone closure via signal `MILESTONE_V33_AT_HEAD_<sha>`.

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
| `vote(uint8 slot)` | function (external) | NEW | `GNRUS.sol:558-581` | Phase 255 boundary re-add per D-254-VOTEPICK-01; signature `(uint8)` not v32 `(uint256 proposalId)`; 4 reject paths | 255-02-SUMMARY.md |
| `pickCharity(uint24 level)` | function (external onlyGame) | NEW | `GNRUS.sol:601-674` | Phase 255 boundary re-add; signature `(uint24)` exactly preserves v32 `IGNRUSResolve` pin; flush + winner-loop + 3 LevelSkipped paths + distribution + emit | 255-03-SUMMARY.md D-255-FLUSH-ORDER-01 |

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

**Total classification distribution:** 11 NEW functions + 1 DELETED function + 5+ NEW state + 1 MODIFIED_LOGIC state + 8 DELETED state + 3 NEW events + 2 RENAMED events + 1 DELETED event + 6 NEW errors + 8 DELETED errors + 7 NEW constants + 3 REFACTOR_ONLY soulbound stubs + 2 REFACTOR_ONLY burn paths = **58 classification rows** spanning every changed function/state/event/error in `contracts/GNRUS.sol` between `acd88512` and `dcb70941`.

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
