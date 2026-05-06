# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ✅ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (shipped 2026-04-15) — see [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md)
- ✅ **v29.0 Post-v27 Contract Delta Audit** — Phases 230-236 (shipped 2026-04-18) — see [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md)
- ✅ **v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit** — Phases 237-242 (shipped 2026-04-20) — see [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md)
- ✅ **v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit** — Phases 243-246 (shipped 2026-04-24) — see [milestones/v31.0-ROADMAP.md](milestones/v31.0-ROADMAP.md)
- ✅ **v32.0 Backfill Idempotency + purchaseLevel Underflow Audit** — Phases 247-253 (shipped 2026-05-02)
- ✅ **v33.0 Charity Allowlist Governance** — Phases 254-257 (shipped 2026-05-06; closure signal `MILESTONE_V33_AT_HEAD_dcb70941`)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

<details>
<summary>✅ v27.0 Call-Site Integrity Audit (Phases 220-223) — SHIPPED 2026-04-13</summary>

- [x] Phase 220: Delegatecall Target Alignment (2/2 plans) — completed 2026-04-12
- [x] Phase 221: Raw Selector & Calldata Audit (2/2 plans) — completed 2026-04-12
- [x] Phase 222: External Function Coverage Gap (3/3 plans) — completed 2026-04-13
- [x] Phase 223: Findings Consolidation (2/2 plans) — completed 2026-04-13

</details>

<details>
<summary>✅ v28.0 Database & API Intent Alignment Audit (Phases 224-229) — SHIPPED 2026-04-15</summary>

- [x] Phase 224: API Route & OpenAPI Alignment (1/1 plans) — completed 2026-04-13
- [x] Phase 225: API Handler Behavior & Validation Schema Alignment (3/3 plans) — completed 2026-04-13
- [x] Phase 226: Schema, Migration & Orphan Audit (4/4 plans) — completed 2026-04-15
- [x] Phase 227: Indexer Event Processing Correctness (3/3 plans) — completed 2026-04-15
- [x] Phase 228: Cursor, Reorg & View Refresh State Machines (2/2 plans) — completed 2026-04-15
- [x] Phase 229: Findings Consolidation (2/2 plans) — completed 2026-04-15

**Findings:** 69 total (0 CRITICAL/HIGH/MEDIUM, 27 LOW, 42 INFO). See [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md) and [audit/FINDINGS-v28.0.md](../audit/FINDINGS-v28.0.md).

</details>

<details>
<summary>✅ v29.0 Post-v27 Contract Delta Audit (Phases 230-236) — SHIPPED 2026-04-18</summary>

- [x] Phase 230: Delta Extraction & Scope Map (1/1 plans) — completed 2026-04-17
- [x] Phase 231: Earlybird Jackpot Audit (3/3 plans) — completed 2026-04-17
- [x] Phase 232: Decimator Audit (3/3 plans) — completed 2026-04-18
- [x] Phase 232.1: RNG-Index Ticket Drain Ordering Enforcement (3/3 plans) — completed 2026-04-18
- [x] Phase 233: Jackpot/BAF + Entropy Audit (3/3 plans) — completed 2026-04-19
- [x] Phase 234: Quests / Boons / Misc Audit (1/1 plans) — completed 2026-04-19
- [x] Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition (5/5 plans) — completed 2026-04-18
- [x] Phase 236: Regression + Findings Consolidation (2/2 plans) — completed 2026-04-18

**Findings:** 4 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 32 prior findings re-verified (31 PASS + 1 SUPERSEDED + 0 REGRESSED). See [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md) and [audit/FINDINGS-v29.0.md](../audit/FINDINGS-v29.0.md).

</details>

<details>
<summary>✅ v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit (Phases 237-242) — SHIPPED 2026-04-20</summary>

- [x] Phase 237: VRF Consumer Inventory & Call Graph (3/3 plans) — completed 2026-04-19
- [x] Phase 238: Backward & Forward Freeze Proofs (3/3 plans) — completed 2026-04-19
- [x] Phase 239: rngLocked Invariant & Permissionless Sweep (3/3 plans) — completed 2026-04-19
- [x] Phase 240: Gameover Jackpot Safety (3/3 plans) — completed 2026-04-19
- [x] Phase 241: Exception Closure (1/1 plans) — completed 2026-04-19
- [x] Phase 242: Regression + Findings Consolidation (1/1 plans) — completed 2026-04-20

**Findings:** 17 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 31 prior findings re-verified (31 PASS + 0 REGRESSED + 0 SUPERSEDED). 0 of 17 candidates promoted to KNOWN-ISSUES.md (D-05 default path). See [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md) and [audit/FINDINGS-v30.0.md](../audit/FINDINGS-v30.0.md).

</details>

<details>
<summary>✅ v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit (Phases 243-246) — SHIPPED 2026-04-24</summary>

- [x] Phase 243: Delta Extraction & Per-Commit Classification (3/3 plans) — completed 2026-04-23
- [x] Phase 244: Per-Commit Adversarial Audit (EVT + RNG + QST + GOX) (4/4 plans) — completed 2026-04-24
- [x] Phase 245: sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification (2/2 plans) — completed 2026-04-24
- [x] Phase 246: Findings Consolidation + Lean Regression Appendix (1/1 plan) — completed 2026-04-24

**Findings:** Zero F-31-NN findings (0 CRITICAL/HIGH/MEDIUM/LOW/INFO across 142 V-rows / 33 REQs). LEAN regression: 6 PASS REG-01 + 1 SUPERSEDED REG-02. KI EXC-02 + EXC-03 envelopes RE_VERIFIED non-widening; KNOWN-ISSUES.md UNMODIFIED per D-07 default. Closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`. See [milestones/v31.0-ROADMAP.md](milestones/v31.0-ROADMAP.md) and [audit/FINDINGS-v31.0.md](../audit/FINDINGS-v31.0.md).

</details>

<details>
<summary>✅ v32.0 Backfill Idempotency + purchaseLevel Underflow Audit (Phases 247-253) — SHIPPED 2026-05-02</summary>

- [x] Phase 247: Delta Extraction & Classification (1/1 plans) — completed 2026-05-01
- [x] Phase 248: Backfill Idempotency Proof (1/1 plans) — completed 2026-05-02
- [x] Phase 249: purchaseLevel Correctness Proof (1/1 plans) — completed 2026-05-02
- [x] Phase 250: Sibling-Pattern Sweep (1/1 plans) — completed 2026-05-02
- [x] Phase 251: Reproduction Tests (1/1 plans) — completed 2026-05-02
- [x] Phase 252: Post-v31.0 Landed-Commit Sanity (1/1 plans) — completed 2026-05-02
- [x] Phase 253: Findings Consolidation + Lean Regression (1/1 plans) — completed 2026-05-02

**Findings:** 2 HIGH SUPERSEDED-at-HEAD F-32-NN disclosure blocks (F-32-01 productive-pause / turbo race + F-32-02 `_backfillGapDays` double-execution; both closed by L173 + L1174 guards committed in `acd88512`). 134 V-rows across 25 REQs (Phases 247-252) all SAFE / NON-WIDENING / NON-INTERFERING with 0 FINDING_CANDIDATE rows surfaced. LEAN regression: 13 PASS REG-01 + zero-row REG-02. KI envelopes EXC-01..04 all RE_VERIFIED non-widening; KNOWN-ISSUES.md UNMODIFIED per D-253-FIND03-01. Closure signal `MILESTONE_V32_AT_HEAD_acd88512`. See [milestones/v32.0-ROADMAP.md](milestones/v32.0-ROADMAP.md) and [audit/FINDINGS-v32.0.md](../audit/FINDINGS-v32.0.md).

</details>

<details>
<summary>✅ v33.0 Charity Allowlist Governance (Phases 254-257) — SHIPPED 2026-05-06</summary>

- [x] Phase 254: GNRUS Allowlist Storage, Admin Op & Storage Repack (3/3 plans) (completed 2026-05-06)
- [x] Phase 255: Vote Rewrite, Resolve Flush & Event/Error Cleanup (3/3 plans) (completed 2026-05-06)
- [x] Phase 256: Charity Allowlist Test Coverage (6/6 plans) (completed 2026-05-06)
- [x] Phase 257: Delta Audit & Findings Consolidation (1/1 plans) (completed 2026-05-06; closure signal `MILESTONE_V33_AT_HEAD_dcb70941`)

**Audit baseline:** v32.0 HEAD `acd88512` (closure signal `MILESTONE_V32_AT_HEAD_acd88512`). Mixed shape — Phases 254-256 modify `contracts/GNRUS.sol` + add tests under `test/governance/`; Phase 257 delta-audits the result and emits closure signal `MILESTONE_V33_AT_HEAD_<sha>`. Per `feedback_no_contract_commits.md`, all `contracts/` + `test/` changes require explicit per-commit user approval. 25/25 v33.0 requirements mapped (ALW + VOTE + RES + CLEAN + TST + AUDIT). Deliverable: `audit/FINDINGS-v33.0.md` with regression appendix verifying v32.0 closure signal still holds, conservation re-proof of GNRUS unallocated pool flow, KI EXC-01..04 RE_VERIFIED NEGATIVE-scope. See [REQUIREMENTS.md](REQUIREMENTS.md) and detail sections below.

</details>

## Phase Details

### Phase 254: GNRUS Allowlist Storage, Admin Op & Storage Repack
**Goal**: `GNRUS.sol` exposes a single vault-owner-gated `setCharity(uint8 slot, address recipient)` admin entry point backed by a 20-slot current slate + pending edit queue, with all dead proposal-flow state removed and the storage layout repacked for tightest layout post-removal.
**Depends on**: Nothing (first impl phase; baseline is v32.0 HEAD `acd88512`)
**Requirements**: ALW-01, ALW-02, ALW-03, ALW-04, CLEAN-01
**Success Criteria** (what must be TRUE):
  1. `GNRUS.sol` compiles with the new `setCharity(uint8, address)` admin entry point + view helpers (`getCharity`, `getActiveSlots`, `getPendingEdits`, `activeCount`, `activeCountAfterFlush`); old `propose(address)` function is structurally absent.
  2. Vault-owner gating is enforced — `setCharity` reverts `Unauthorized` when called by any address that fails `vault.isVaultOwner(msg.sender)`; reverts `InvalidSlot` for `slot >= 20`; reverts `SlotLocked` on a locked-slot replace/remove attempt; reverts `SlotAlreadyEmpty` on the no-op admin remove path. Contract recipients (multisig / DAO treasuries) are accepted by design — vault-owner curation is the trust boundary.
  3. Locked-slot rule is enforced — `setCharity(slot, ·)` for `slot ∈ {0, 1, 2}` reverts `SlotLocked` whenever `currentSlate[slot] != address(0)` (including remove attempts), checked before queue/instant-apply branching so locked slots cannot be mutated through the pending queue either; first-fill of an empty locked slot succeeds via the instant-apply branch.
  4. Two-branch write semantics work as designed — instant-apply branch writes directly to current slate when `currentSlate[slot] == address(0)`; queue branch writes to pending when `currentSlate[slot] != address(0)`; pending overwrite for the same slot replaces (no separate cancel API); `CapExceeded` fires when post-flush active count would exceed 20 from either branch.
  5. Dead state is functionally removed (not commented-out) per `feedback_no_history_in_comments.md` — `Proposal` struct, `proposals`, `proposalCount`, `levelProposalStart`, `levelProposalCount`, `hasProposed`, `creatorProposalCount`, `levelVaultOwner`, `levelSdgnrsSnapshot` all deleted; new storage layout documented vs the v32.0 baseline; storage repacked for tightest layout post-removal.
**Plans**: 3 plans
- [x] 254-01-PLAN.md — Demolish v32-shape governance + lay v33.0 storage skeleton (CLEAN-01) [Wave 1]
- [x] 254-02-PLAN.md — Implement setCharity admin op + _popcount32 internal helper (ALW-01, ALW-02, ALW-03) [Wave 2, depends on 254-01]
- [x] 254-03-PLAN.md — Implement five v33.0 view helpers + _flushedBitmap internal helper (ALW-04) [Wave 3, depends on 254-01 + 254-02]
**Write policy**: `contracts/GNRUS.sol` modifications require explicit per-commit user approval per `feedback_no_contract_commits.md`. Storage-layout / packing-strategy gas comparison documented in plan output before committing.

### Phase 255: Vote Rewrite, Resolve Flush & Event/Error Cleanup
**Goal**: `vote(uint8 slot)` casts the voter's full sDGNRS balance toward the named slot (approve-only, no bonus weight, no proposal threshold), and `pickCharity(uint24 level)` atomically flushes the pending edit queue → current slate before iterating slots 0 → 19 with strict `>` to pick the lowest-index slot holding the maximum approve weight, while events `Voted` + `LevelResolved` are rewritten to slot-based signatures and dead errors `ProposalLimitReached` / `AlreadyProposed` / `InvalidProposal` are removed.
**Depends on**: Phase 254 (vote rejects empty slots, so the slate storage + setCharity admin op must exist before vote/pickCharity can be rewritten against it)
**Requirements**: VOTE-01, VOTE-02, VOTE-03, VOTE-04, RES-01, RES-02, RES-03, RES-04, CLEAN-02, CLEAN-03
**Success Criteria** (what must be TRUE):
  1. `vote(uint8 slot)` rejects empty slots (current-slate address-zero), rejects double-voting per `hasVoted[currentLevel][msg.sender][slot]`, computes weight as `sdgnrs.balanceOf(msg.sender) / 1e18`, rejects zero-weight voters, and emits `Voted(uint24 indexed level, uint8 indexed slot, address indexed voter, uint256 weight)`. A voter can vote on multiple slots independently with full weight applied to each.
  2. NO vault-owner +5%-of-snapshot bonus weight code path exists (verifiable via grep), and NO sDGNRS proposal-threshold check gates `vote()` entry; `levelVaultOwner` and `levelSdgnrsSnapshot` storage absence (from Phase 254) is consistent with the new vote function.
  3. `pickCharity(uint24 level)` atomically applies every queued edit to the current slate before computing the winner, emits per-edit (or one aggregate) flush events for indexer reconstructability, and the flush itself does not revert on bad pending state (admin-side validation in `setCharity` makes the queue trustable).
  4. Winner selection iterates slots 0 → 19 with strict `>`; ties resolve to lowest active slot index; `LevelSkipped(level)` emits exactly once on each of three paths — (a) zero active slots after flush, (b) zero votes cast, (c) post-flush distribution amount rounds to zero — and consumes the level (`levelResolved[level] = true`, `currentLevel = level + 1`). Distribution semantics unchanged (2% of remaining unallocated GNRUS to winning slot recipient via balance write + `Transfer` event + `LevelResolved(uint24 indexed level, uint8 indexed slot, address recipient, uint256 gnrusDistributed)` event with `slot` replacing the prior `proposalId` indexed arg).
  5. Cleanup is functional removal (not commenting-out) per `feedback_no_history_in_comments.md` — event `ProposalCreated` removed; events `Voted` and `LevelResolved` rewritten to the slot-based signatures; errors `ProposalLimitReached`, `AlreadyProposed`, `InvalidProposal` removed (Phase 254 already removed `InsufficientStake`, `AlreadyVoted`, `LevelAlreadyResolved`, `LevelNotActive`, `RecipientIsContract`); new error `VoteRejected(uint8 reason)` added in Phase 255 covering empty-slot / already-voted / zero-weight vote rejections via reason codes; existing `Unauthorized` reused for vault-owner gating; existing `InvalidSlot` reused for `vote(slot)` bounds check (`slot >= 20`). No orphaned `revert` statements remain per `feedback_no_dead_guards.md`.
**Plans**: 3 plans
- [x] 255-01-PLAN.md — Land Phase 255 declarations: delete ProposalCreated; rewrite Voted + LevelResolved to v33 signatures; add CharityFlushed event; add VoteRejected + PickCharityRejected errors with reason-code constants; add slotApproveWeight storage (CLEAN-02, CLEAN-03) [Wave 1]
- [x] 255-02-PLAN.md — Implement vote(uint8 slot) external with locked revert order (InvalidSlot → REJECT_EMPTY_SLOT → REJECT_ALREADY_VOTED → REJECT_ZERO_WEIGHT) and CEI-clean state writes (VOTE-01, VOTE-02, VOTE-03, VOTE-04) [Wave 2, depends on 255-01]
- [x] 255-03-PLAN.md — Implement pickCharity(uint24 level) external onlyGame with idempotence-first ordering, inline atomic flush emitting CharityFlushed per-edit, strict-> winner loop, 3 LevelSkipped paths, and v32 distribution math preserved verbatim (RES-01, RES-02, RES-03, RES-04) [Wave 3, depends on 255-01 + 255-02]
**Write policy**: `contracts/GNRUS.sol` modifications require explicit per-commit user approval per `feedback_no_contract_commits.md`.

### Phase 256: Charity Allowlist Test Coverage
**Goal**: A new Hardhat test surface under `test/governance/` (or similar) covers every behaviorally observable v33.0 surface — setCharity branches (instant-apply / queue / overwrite / locked-slot / sad-paths / cap), edit-queue level-boundary semantics, vote weighting / multi-slot / double-vote / empty-slot / zero-weight, pickCharity winner selection / tie-break / three LevelSkipped paths, conservation across the level transition, and post-gameover inertness — with all tests passing against the Phase 254 + 255 contract HEAD.
**Depends on**: Phase 254, Phase 255 (tests exercise the full new admin-op + vote + resolve surface)
**Requirements**: TST-01, TST-02, TST-03, TST-04, TST-05, TST-06
**Success Criteria** (what must be TRUE):
  1. `setCharity` Hardhat unit tests pass — instant-apply branch (empty slot → directly votable in same level), queue branch (filled slot → old address still votable until flush), removal queueing, pending overwrite (queue A then B → only B applies on flush), locked slots 0/1/2 (first-fill instant-applies; subsequent replace OR remove on filled locked slot reverts `SlotLocked`), and all sad paths (vault-owner gating, `InvalidSlot`, `SlotAlreadyEmpty` admin no-op, `CapExceeded` on 21st add via either branch — interpreted post-Phase-256-revision-iter1 as: CapExceeded is defensively guarded but mathematically unreachable from external calls because `_popcount32(_futureBitmapAfter(...))` is structurally capped at 20; the verdict is recorded inline in `256-03a-PLAN.md` and Phase 257 audit cites it as a SAFE row in AUDIT-02). Contract recipients accepted by design — no `RecipientIsContract` revert path to test.
  2. Edit-queue level-boundary semantics tests pass — instant-apply slot is votable in the same level; queued replace / remove keep OLD address votable until flush; after `pickCharity` advances the level, queued edits are visible in current slate and dead pending entries are cleared.
  3. `vote(uint8 slot)` tests pass — single-slot vote applies full sDGNRS weight; multi-slot vote applies full weight independently to each slot; double-vote on same `(level, voter, slot)` reverts; vote on empty slot reverts; vote with zero whole-token sDGNRS reverts. `pickCharity` winner-selection tests pass — single-active-slot wins; multi-vote highest-weight wins; tie → lowest slot index wins (concrete weights wired); zero votes / zero active slots / 2%-rounds-to-zero all emit `LevelSkipped` exactly once.
  4. Conservation tests pass across the level transition — total ETH/stETH/GNRUS balance changes match the expected 2% distribution per resolved level; sDGNRS / DGNRS / BURNIE supplies unchanged; soulbound enforcement intact (transfer / transferFrom / approve still revert).
  5. Post-gameover inertness tests pass — after `burnAtGameOver`, subsequent calls to `setCharity` / `vote` either revert or are inert (chosen behavior post-Phase-256-revision-iter1: INERT — v33 contract has no `finalized` guard on these functions, and a positive smoke it-block in `256-03c` empirically asserts setCharity + vote do NOT revert post-burnAtGameOver; the inertness comes from absence of game-side caller, not contract-level guards); `pickCharity` not callable post-gameover (verify GNRUS-side consistency with game-side flow).
**Plans**: 6 plans
- [x] 256-01-PLAN.md — Factor `test/helpers/charityFixture.js` shared helper (impersonate / giveSDGNRS / deployGNRUSFixture / runLevelTransitionViaGame); v33 voter sizing (100/100/200) [Wave 1]
- [x] 256-02-PLAN.md — Prune `test/unit/DegenerusCharity.test.js` to v33 shape: delete 3 stale Governance describes + 3 stale constants + proposalCount assertion + 3 v32 Edge Cases; rewrite local distributeGNRUS to v33 setCharity+vote+pickCharity; switch in-file helpers to imports (TST-01) [Wave 2, depends on 256-01]
- [x] 256-03a-PLAN.md — Build NEW `test/governance/CharityAllowlist.test.js` (sections 1-5): setCharity instant-apply + queue branches + locked-slot parametric 0/1/2 + pending-overwrite + 20-slot fill smoke + CapExceeded structural unreachability verdict (parallel to D-256-CANCEL-QUEUED-01) + edit-queue level-boundary semantics + contract-recipient acceptance (TST-01, TST-02) [Wave 2, depends on 256-01]
- [x] 256-03b-PLAN.md — Append Section 6 to `test/governance/CharityAllowlist.test.js`: vote() with all 4 reject reason codes (InvalidSlot, REJECT_EMPTY_SLOT, REJECT_ALREADY_VOTED, REJECT_ZERO_WEIGHT via sub-1e18 sDGNRS integer-floor) + multi-slot vote independence (D-256-MULTI-VOTE-01) + hasVoted state + revert-order verification (TST-03) [Wave 3, depends on 256-01 + 256-03a]
- [x] 256-03c-PLAN.md — Append Sections 7+8+9 to `test/governance/CharityAllowlist.test.js`: pickCharity winner + tie-break (D-256-TIEBREAK-01 cases A+B) + 3 LevelSkipped paths (path C via deterministic `keccak256(abi.encode(charityAddress, 1))` setStorageAt for balanceOf) + both PickCharityRejected reason codes (REJECT_LEVEL_NOT_ACTIVE direct + REJECT_LEVEL_ALREADY_RESOLVED via `keccak256(abi.encode(level, 3))` setStorageAt for levelResolved) + TST-06 post-gameover smoke (GNRUS-side state + positive inertness assertion) + D-256-GAS-01 single-assertion gas guardrail (`pickCharity` full-slate < 700_000 gas) (TST-04, TST-06) [Wave 4, depends on 256-01 + 256-03a + 256-03b]
- [x] 256-04-PLAN.md — Extend `test/integration/CharityGameHooks.test.js` with TST-05 conservation it-block driven via REAL game flow (`charityResolve.pickCharity(lvl - 1)` from `DegenerusGameAdvanceModule:1634`); rewrite stale `LevelSkipped(0) when no proposals exist` to v33 `LevelSkipped(0) when no active slots in slate` (TST-05) [Wave 2, depends on 256-01]
**Write policy**: `test/governance/CharityAllowlist.test.js` (or similar) additions require explicit per-commit user approval per `feedback_no_contract_commits.md`. Per `feedback_test_rnglock.md`, deploy-blocking tests must run before any deploy; per `feedback_gas_worst_case.md`, any gas analysis derives theoretical worst case FIRST then tests it.

### Phase 257: Delta Audit & Findings Consolidation
**Goal**: Publish `audit/FINDINGS-v33.0.md` proving the v33.0 charity-allowlist design closes the original collusion attack on the v32.0 propose/vote design, with every changed function / state variable / event / error in `GNRUS.sol` classified, every adversarial surface (admin front-runs, edit-queue ordering, tie-break gaming, DGVE float gaming, instant-apply branch abuse, active-count accounting, locked-slot poisoning, locked-slot lock-bypass) verdicted SAFE or FINDING_CANDIDATE with evidence, the GNRUS unallocated-pool conservation re-proven, the v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening, and a new closure signal `MILESTONE_V33_AT_HEAD_<sha>` emitted.
**Depends on**: Phase 254, Phase 255, Phase 256 (audit baseline is the post-test HEAD with all impl + tests landed)
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v33.0.md` published as FINAL READ-only at HEAD `<sha>` — mirrors v32.0 9-section deliverable shape (executive summary, per-phase sections, F-33-NN finding blocks under D-08 5-bucket severity rubric, regression appendix, KI gating walk, closure attestation), with explicit closure signal `MILESTONE_V33_AT_HEAD_<sha>` emitted in §9.
  2. AUDIT-01 delta surface complete — every changed function / state variable / event / error in `GNRUS.sol` vs v32.0 baseline `acd88512` enumerated with hunk-level evidence and classified as {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}; every downstream caller of changed functions inventoried across `contracts/` (grep-reproducible commands documented).
  3. AUDIT-02 adversarial sweep complete — original collusion attack on v32.0 propose/vote design re-derived; 8 new attack surfaces verdicted SAFE or FINDING_CANDIDATE with evidence: (a) admin front-run at level boundary, (b) edit-queue ordering / overflow, (c) tie-break gaming via slot ordering, (d) DGVE float gaming to flip vault-owner status mid-level, (e) instant-apply branch abuse (admin fills empty slot mid-level after observing votes), (f) active-count accounting drift across both branches, (g) locked-slot poisoning during seeding window (disclosed as trust-asymmetry note — operational mitigation, not code-level defense), (h) locked-slot lock-bypass (no pending-queue path, no flush-time mutation, no constructor/migration backdoor).
  4. AUDIT-03 conservation re-proof complete — GNRUS unallocated pool flow still 2% of remaining per resolved level; supply invariants for GNRUS / sDGNRS / DGNRS / BURNIE intact across the level transition; soulbound enforcement (transfer / transferFrom / approve) intact; `burn()` proportional redemption math unchanged. Each invariant gets a SAFE row with grep-cited proof.
  5. Regression appendix verifies v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` still holds (REG-01 PASS — backfill / purchaseLevel guards intact at HEAD `<sha>`); KI envelopes EXC-01..04 all RE_VERIFIED NEGATIVE-scope (charity governance does not touch any RNG-consuming path); KNOWN-ISSUES.md UNMODIFIED expected unless any new F-33-NN finding passes the D-09 3-predicate KI gating walk.
**Plans**: 1 plan
- [ ] 257-01-PLAN.md — Author audit/FINDINGS-v33.0.md (9-section deliverable; AUDIT-01..04 + adversarial validation parallel-spawn + closure signal MILESTONE_V33_AT_HEAD_<sha>) [Wave 1]
**Write policy**: `audit/FINDINGS-v33.0.md` writeable freely per write policy (D-257-FILES-01: single deliverable, no `audit/v33-*.md` working files). READ-only flip on terminal-task atomic commit per v32.0 Phase 253 precedent.

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 254. GNRUS Allowlist Storage, Admin Op & Storage Repack | 3/3 | Complete    | 2026-05-06 |
| 255. Vote Rewrite, Resolve Flush & Event/Error Cleanup | 3/3 | Complete    | 2026-05-06 |
| 256. Charity Allowlist Test Coverage | 6/6 | Completed 2026-05-06 | 4 commits (b1f84a8c → 644af631) |
| 257. Delta Audit & Findings Consolidation | 1/1 | Completed 2026-05-06 | Closure signal `MILESTONE_V33_AT_HEAD_dcb70941` |

## Active Milestone

_(none — v33.0 shipped 2026-05-06; ready for next milestone planning)_

## Last Shipped Milestone

**v33.0 Charity Allowlist Governance** — SHIPPED 2026-05-06. 4 phases (254-257), 25 requirements satisfied (ALW + VOTE + RES + CLEAN + TST + AUDIT). Audit baseline v32.0 HEAD `acd88512` → v33.0 contract-tree HEAD `dcb70941`. Mixed shape: Phases 254-256 modified `contracts/GNRUS.sol` + added tests; Phase 257 delta-audited the result. Result: 8 of 8 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY; zero F-33-NN finding blocks; 1 PASS REG-01 + zero-row REG-02; 4 NEGATIVE-scope KI envelope re-verifications; KNOWN-ISSUES.md UNMODIFIED. Deliverable: `audit/FINDINGS-v33.0.md` (FINAL READ-only). Closure signal: `MILESTONE_V33_AT_HEAD_dcb70941`. See [REQUIREMENTS.md](REQUIREMENTS.md) for v33.0 scope.
