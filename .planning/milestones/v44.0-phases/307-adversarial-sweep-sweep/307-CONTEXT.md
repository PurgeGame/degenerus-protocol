# Phase 307: Adversarial Sweep (SWEEP) — Context

**Gathered:** 2026-05-19
**Status:** Ready for planning
**Posture:** Audit-leaning FIX milestone (v44.0). Pre-authorized 3-skill HYBRID invocation per `D-44N-SWEEP-PREAUTH-01` (locked at Phase 304 SPEC signoff). Tier-1 single-skill FINDING_CANDIDATE still triggers AskUserQuestion user-pause per `D-302-CONSENSUS-01` carry; Tier-2 3-of-3 consensus auto-elevates + RE-PASS.

<domain>
## Phase Boundary

3-skill HYBRID adversarial pass per `D-302-INVOKE-01` carry against the v44.0 source post-IMPL (Phase 305) + post-TST (Phase 306). Skill composition: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` PARALLEL_SUBAGENT + `/economic-analyst` PARALLEL_SUBAGENT. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry. `/economic-analyst` IN SCOPE per `D-271-ADVERSARIAL-03` carry.

Charged with `SWP-01..05` verbatim (`.planning/REQUIREMENTS.md`):
- **SWP-01** `/contract-auditor`: find any state transition violating `INV-01..13`; any (burn, advance, claim, gameOver) interleaving producing exploitable outcome; any storage-collision or packing bug in the new v44 layout (esp. 1-slot `DayPending` packing per `D-305-STRUCT-TIGHTEN-01`).
- **SWP-02** `/zero-day-hunter`: novel attack surfaces — composition with lootbox/coinflip flows; ERC20 callback-induced re-entry on transfer paths; cross-module read/write races between sStonk and `DegenerusGame` storage.
- **SWP-03** `/economic-analyst`: game-theoretic write-induced effects under the per-day model; coordinated-burn scenarios; timing arbitrage between gap burns vs post-advance burns; MEV surfaces on the new state machine.
- **SWP-04** Two-tier consensus per `D-302-CONSENSUS-01`: Tier-1 any-skill FINDING_CANDIDATE → AskUserQuestion PAUSE; Tier-2 3-of-3 consensus → automatic elevation + RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` against any FIXREC-augment diff.
- **SWP-05** Per-skill disposition table with `NEGATIVE-VERIFIED` / `FINDING_CANDIDATE` / `SAFE_BY_DESIGN` classification — skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` MUST be applied BEFORE any user-pause.

Wave shape: 1 AGENT-COMMITTED `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md` artifact bundle = `307-ADVERSARIAL-CHARGE.md` + 3 per-skill MDs + integrated LOG + Disposition section.

### In scope (single AGENT-COMMITTED artifact-bundle commit at end of phase)

- **`307-ADVERSARIAL-CHARGE.md`** authored with `SWP-01..05` verbatim + 5 v44-specific carry-forward augment hypotheses (see `D-307-CHARGE-01` below).
- **`307-ADVERSARIAL-CONTRACT-AUDITOR.md`** — `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass against charge with disposition table.
- **`307-ADVERSARIAL-ZERO-DAY-HUNTER.md`** — `/zero-day-hunter` PARALLEL_SUBAGENT pass (or HYBRID-fallback to sequential main per ROADMAP allowance; persona fidelity preserved via dedicated MD).
- **`307-ADVERSARIAL-ECONOMIC-ANALYST.md`** — `/economic-analyst` PARALLEL_SUBAGENT pass with charged + beyond-charge hypothesis rows; game-theoretic + MEV surface enumeration.
- **`307-01-ADVERSARIAL-LOG.md`** integrated artifact: 3 H2 sections (one per skill) + skeptic-filter-discarded findings table (inline citations) + integrated Disposition section applying two-tier consensus rule.
- **`307-01-SUMMARY.md`** AGENT-COMMITTED.
- **Conditional `307-FIXREC-AUGMENT.md`** — only authored if a Tier-1 (user-approved) or Tier-2 (auto-elevated) `FINDING_CANDIDATE` lands per `D-307-ELEVATION-ROUTING-01`.

### Out of scope (Phase 308 TERMINAL handles)

- `audit/FINDINGS-v44.0.md` 9-section TERMINAL deliverable + `§4` adversarial-pass disposition table — Phase 308 reads Phase 307's LOG + Disposition and writes the TERMINAL §4.
- `KNOWN-ISSUES.md` modifications — UNMODIFIED per `D-44N-KI-01`; Phase 308 §6 re-verifies EXC-01..04 RE_VERIFIED-NEGATIVE-scope without mutation.
- Direct `contracts/*.sol` mutations EXCEPT as required by a Tier-1 user-approved or Tier-2 auto-elevated FINDING_CANDIDATE with a FIXREC-augment commit per `D-307-ELEVATION-ROUTING-01`.
- Direct `test/*.sol` mutations EXCEPT to augment coverage if a `FINDING_CANDIDATE` elevation requires a new fuzz/invariant function (USER-APPROVED test-commit ping per `feedback_no_contract_commits.md` clarified policy lineage — `test/` autonomy applies, but a finding-driven test addition still surfaces via the FIXREC-augment commit envelope).

</domain>

<decisions>
## Implementation Decisions

### Inherited from Phase 302 (D-302-* carries) — non-negotiable

- **D-302-INVOKE-01 (carry)** — 3-skill HYBRID: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT, `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT via single-message multi-Task block. HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT acceptable per ROADMAP allowance if executor's Task tool dispatch is unreliable; persona fidelity preserved via dedicated per-skill MD with verbatim CHARGE.
- **D-302-CONSENSUS-01 (carry)** — Two-tier consensus rule verbatim. Tier-1 any-skill `FINDING_CANDIDATE` = AskUserQuestion user-pause. Tier-2 3-of-3 consensus `FINDING_CANDIDATE` = automatic elevation + RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01`.
- **D-302-REPASS-SCOPE-01 (carry)** — Candidate-fix-only RE-PASS. If a FIXREC-augment commit lands, RE-PASS dispatches the 3 skills against the augment diff + the affected hypothesis subset only; other hypotheses keep original-pass disposition.
- **D-302-ARTIFACT-SET-01 (carry)** — Full artifact shape at `.planning/phases/307-*/` (CHARGE + 3 per-skill MDs + integrated LOG + SUMMARY + conditional FIXREC-AUGMENT + conditional RE-PASS-* files mirroring v42 P296 convention).
- **D-302-RESEARCH-AGENT-01 (carry)** — Plan-phase SKIPS `gsd-phase-researcher` dispatch per `feedback_skip_research_test_phases.md`. Methodology locked by this CONTEXT.md + REQUIREMENTS SWP-01..05 + v42 P296 + v43 P302 precedents.
- **D-302-TASK-SPLIT-01 (carry, lightly amended for v44 — see `D-307-PLAN-01`)** — Plan-phase task structure (7 tasks).

### Phase 307 — New Decisions

#### D-307-PLAN-01: Single-plan, 7-task verbatim D-302-TASK-SPLIT-01 carry

- **D-307-PLAN-01:** Single plan `307-01-PLAN.md` with 7 tasks:
  1. Author `307-ADVERSARIAL-CHARGE.md` (SWP-01..05 verbatim + 5 v44-specific augments per `D-307-CHARGE-01`).
  2. Dispatch `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT — produce `307-ADVERSARIAL-CONTRACT-AUDITOR.md` with per-hypothesis disposition + skeptic-filter self-check section.
  3. Dispatch `/zero-day-hunter` PARALLEL_SUBAGENT (single-message multi-Task block alongside Task 4) — produce `307-ADVERSARIAL-ZERO-DAY-HUNTER.md` with per-hypothesis disposition + skeptic-filter self-check section.
  4. Dispatch `/economic-analyst` PARALLEL_SUBAGENT — produce `307-ADVERSARIAL-ECONOMIC-ANALYST.md` with per-hypothesis disposition + skeptic-filter self-check section.
  5. Integrate dispositions + apply orchestrator-side skeptic-reviewer filter re-application (dual-gate per `D-307-SKEPTIC-FILTER-01`) + write `307-01-ADVERSARIAL-LOG.md` (3 H2 sections + skeptic-filter-discarded inline table + integrated Disposition section + two-tier consensus verdict).
  6. **Conditional** — elevation routing per `D-307-ELEVATION-ROUTING-01` (Task 6 fires only if a Tier-1 user-approved or Tier-2 auto-elevated `FINDING_CANDIDATE` survives the dual-gate skeptic filter): author `307-FIXREC-AUGMENT.md`; if the recommendation requires a contract diff, batch + present for USER approval per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`; RE-PASS the affected hypothesis subset per `D-302-REPASS-SCOPE-01`; produce conditional RE-PASS-* files mirroring v42 P296.
  7. AGENT-COMMIT artifact bundle (`307-ADVERSARIAL-CHARGE.md` + 3 per-skill MDs + `307-01-ADVERSARIAL-LOG.md` + `307-01-SUMMARY.md` + conditional `307-FIXREC-AUGMENT.md` + conditional RE-PASS files) + `.planning/STATE.md` update.

  **Why:** Wave shape "1 AGENT-COMMITTED artifact bundle" in ROADMAP maps cleanly onto single-plan-7-tasks. v42 P296 + v43 P302 both shipped single-plan; the conditional Task 6 (elevation) lives inside the same plan so the artifact bundle stays atomic. Multi-plan splits introduce coordination boundaries that don't fit the single-artifact-bundle wave shape.

  **How to apply:** Planner authors `307-01-PLAN.md` with these 7 tasks. Task 6's conditional gate documented as a precondition check at task start: "if and only if dual-gate skeptic-filter (orchestrator integration-time re-application) surfaces at least one surviving FINDING_CANDIDATE, run Task 6; else skip Task 6 and proceed to Task 7."

#### D-307-DISPATCH-01: Sequential auditor → parallel hunter+economist

- **D-307-DISPATCH-01:** Task 2 `/contract-auditor` runs SEQUENTIAL_MAIN_CONTEXT to completion FIRST. Tasks 3 + 4 (`/zero-day-hunter` + `/economic-analyst`) spawn together via a single-message multi-Task block AFTER Task 2 completes. The auditor MD is available as additional context for the hunter + economist subagents; they read it to anchor their own hypotheses (avoids redundant rediscovery; ensures cross-skill coverage divergence rather than overlap).

  **Why:** D-302-INVOKE-01 verbatim carry. Strict reading: "Task N+1 `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT; Task N+2 + Task N+3 `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT via single-message multi-Task block." Phase 302 + Phase 296 ran exactly this shape.

  **How to apply:** Plan Task 2 = single sequential dispatch with full main-context fidelity. Plan Task 3 + 4 = a single message containing two `Task` tool calls in one block, both spawning PARALLEL_SUBAGENT. If Task tool subagent dispatch fails or returns degraded output, fall back to SEQUENTIAL_MAIN_CONTEXT for the failing skill per ROADMAP HYBRID-fallback allowance; document the fallback in the per-skill MD's `[invocation]` frontmatter.

#### D-307-CHARGE-01: 5 v44-specific carry-forward augment hypotheses (enumerate in plan, planner expands)

- **D-307-CHARGE-01:** Beyond `SWP-01..05` verbatim, the CHARGE document enumerates the following 5 v44-specific carry-forward augment hypotheses tied to v44 audit subjects (mirroring `D-302-CHARGE-01` pattern (i)..(iv)):

  - **(i) 1-slot DayPending packing edges** — `D-305-STRUCT-TIGHTEN-01` packs 4 fields into one storage slot via mixed denominations (gwei for `ethBase`/`burnieBase`, whole-tokens for `supplySnapshot`/`burned`, all `uint64`). Probe: uint64 overflow boundaries under maximally-pessimal whale-day burn aggregation; denomination-conversion edge cases at small/large/zero values; gwei-to-wei conversion ordering inside `_payEth`/`_payBurnie`; sub-gwei dust loss; corruption via misaligned bit-shift on a packed-load.
  - **(ii) pendingResolveDay sentinel race/collision** — `D-305-SENTINEL-01` introduces a 32-bit slot enforcing the single-pool invariant (`INV-13`) via `PriorDayUnresolved` revert. Probe: sentinel-vs-pool desync attacks; multi-day stall recovery semantics with the sentinel reader at `AdvanceModule:1228, :1294, :1327`; sentinel staleness under `gameOver` mid-stall; cross-actor sentinel races (one player's burn sets the sentinel; another player's claim reads it); sentinel clear-on-resolve ordering (`StakedDegenerusStonk.sol:665`) under reverts.
  - **(iii) gwei-snap precision interaction with cap arithmetic** — `D-305-GWEI-SNAP-01` snaps `ethValueOwed`/`burnieOwed` to gwei at source for exact `× roll / 100` arithmetic (`gcd(1e9, 100) = 100`). Probe: precision edge cases where snap-truncation interacts with the 160 ETH `MAX_DAILY_REDEMPTION_EV` cap (`INV-11`); per-(player, day) accumulation across multiple sub-claims; rounding semantics at the boundary where `ethValueOwed % 1e9 != 0`; whether the snap creates a manipulable surplus or deficit between snapshot and payout.
  - **(iv) Phase 306 INV harness perturbation-class gaps** — The 5-action `RedemptionHandler` (`action_burn`, `action_advance`, `action_claim`, `action_gameOver`, `action_burnOnPreviousDay`) and the 13-invariant + 20-edge mechanization PROVED `INV-01..13` at 256k+ calls. Probe: perturbation classes the harness misses — transfer mid-pending; approve mid-stall; multi-actor sentinel race; ERC20-callback-induced state mutation during the burn/claim path; coinflip pool drain mid-multi-day-claim; the partial-claim BURNIE branch under sentinel-stall conditions; admin-class actions (governance, charity-allowlist) during rngLock window mid-pending.
  - **(v) Vault scope-expansion ACL surface** — `DegenerusVault.sdgnrsClaimRedemption(uint32 day)` was added during Phase 305 IMPL (scope-expansion the planner missed). Probe: vault-managed claim flow ACL coverage; `onlyVaultOwner` modifier semantics; interaction with `DegenerusVault`'s own pending-state machine; reentrancy on the vault claim path; cross-actor vault-claim manipulation (vault owner vs ultimate beneficiary).

  Each augment is enumerated in `307-01-PLAN.md` Task 1; the planner expands each with evidence anchors (file:line + INV/EDGE/SPEC IDs + Phase 305/306 SUMMARY citations) and any sub-hypotheses surfaced during expansion. Charging additional augments beyond these 5 is permitted if the planner identifies a v44 surface not covered above (e.g., `INV-13` emergent invariant soundness as a standalone augment if the planner finds it deserves separate treatment).

  **Why:** v42 P296 + v43 P302 added 4 augments tied to milestone-specific audit subjects. v44.0 ships ~5 new emergent surfaces (per `D-305-*` decision lineage) that didn't exist at v43 audit baseline; the adversarial pass must charge against them explicitly, not rely on SWP-01..05 verbatim to imply coverage.

  **How to apply:** Plan Task 1 enumerates the 5 augments verbatim from this CONTEXT.md and adds per-augment evidence anchors. Each per-skill MD has at minimum one disposition row per augment (i)..(v) in addition to the rows for SWP-01..05.

#### D-307-SKEPTIC-FILTER-01: Dual-gate filter; strict structural-protection; (a)-only hard discard

- **D-307-SKEPTIC-FILTER-01:** Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` operationalized as:

  - **Filter location: dual gate.**
    1. **Per-skill self-filter** — each skill (`/contract-auditor`, `/zero-day-hunter`, `/economic-analyst`) applies the filter to its own `FINDING_CANDIDATE` set BEFORE writing its per-skill MD. The skill documents discards in a "Skeptic-Filter Self-Discarded" subsection within its MD.
    2. **Orchestrator integration-time re-application** — at Plan Task 5 (integration), the orchestrator (executor) re-applies the filter against the aggregated `FINDING_CANDIDATE` set across all 3 skill MDs. Discards at integration time are documented inline in `307-01-ADVERSARIAL-LOG.md` Disposition section per `D-307-AUDIT-TRAIL-01`. The integration-time pass catches cross-skill weighting issues and uniformly applies the filter across all 3 skills' outputs.
  - **Structural-protection check: STRICT.** A finding is discarded under the structural-protection arm only if the code path makes the attack **literally physically unreachable** — e.g., `delete pendingByDay[D]` after resolve makes the V-184 overwrite primitive unreachable; the `PriorDayUnresolved` revert at `StakedDegenerusStonk.sol:820` makes cross-day pool accumulation unreachable; type system forbids the input. Defense-in-depth alone (ACL gate + downstream secondary check) does NOT pass the filter — those findings surface to user-pause.
  - **3-condition EV lens:** (a) attacker controls the necessary state; (b) the manipulation produces a measurable economic gain; (c) the gain exceeds gas cost + opportunity cost + risk cost.
    - **(a) is the ONLY hard discard condition.** If the attacker does NOT control the necessary state, the filter discards the finding (no exploitable scenario can be constructed).
    - **(b) measurability + (c) gain-vs-cost** are **severity-downgrade** signals — they do NOT discard but they DOWNGRADE the severity tag (CATASTROPHE → HIGH → MEDIUM → LOW) and document the downgrade rationale. Memory's "reject CATASTROPHE-labeling without rigor" applies here as severity-downgrade, not as discard.

  **Why:** `feedback_skeptic_pass_before_catastrophe.md` is the load-bearing memory anchor. Strict structural-protection prevents defense-in-depth from silently dismissing real exposures. (a)-only hard discard surfaces every reachable-by-attacker finding to user-pause; (b)/(c) downgrade-only preserves the audit trail for small-EV findings (real but tiny) rather than dropping them silently.

  **How to apply:** Per-skill MDs include explicit `[skeptic-filter]` frontmatter section with `discarded: []` array (each entry: `hypothesis-id`, `structural-protection-citation` (file:line), `ev-lens-failed-condition` (always "a" for discards), `note`). Orchestrator at Task 5 reads all 3 skills' `[skeptic-filter]` blocks, re-applies the dual-gate filter against the union, and writes the integrated discard table in `307-01-ADVERSARIAL-LOG.md` Disposition section. Surviving findings get severity tags applied based on (b)/(c) signals — documented in a "Severity-Downgrade Rationale" table alongside the Disposition section.

#### D-307-AUDIT-TRAIL-01: Inline LOG Disposition for all discards

- **D-307-AUDIT-TRAIL-01:** All skeptic-filter-discarded findings — both per-skill self-discards and orchestrator integration-time discards — are enumerated inline in `307-01-ADVERSARIAL-LOG.md` Disposition section under a "Skeptic-Filter Discarded" table with columns:

  | Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |

  Surviving (post-filter) findings appear in the main Disposition table with columns:

  | Hypothesis-ID | Source skill | Verdict (NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN) | Severity tag (CATASTROPHE / HIGH / MEDIUM / LOW / N-A) | (b)+(c) downgrade rationale | Cross-skill consensus state (Tier-1 / Tier-2 / unanimous-NEGATIVE) |

  **Why:** Reviewer-auditable trail. Future-Phase-308 §4 disposition table cites this directly. Memory's "audit-finding discipline" is explicit that the filter must be applied AND its application must be auditable.

  **How to apply:** Plan Task 5 integration step produces both tables. The `307-01-ADVERSARIAL-LOG.md` template includes both as MANDATORY sections regardless of zero/non-zero candidate counts.

#### D-307-ELEVATION-ROUTING-01: Route to 307-FIXREC-AUGMENT.md + Phase 308 §4 stub

- **D-307-ELEVATION-ROUTING-01:** Any Tier-1 user-approved or Tier-2 auto-elevated `FINDING_CANDIDATE` routes to:
  1. Author `.planning/phases/307-adversarial-sweep-sweep/307-FIXREC-AUGMENT.md` capturing: the VIOLATION class; the recommended structural close (preferred) or defense-in-depth mitigation (fallback); per-hypothesis evidence anchors; v44 handoff anchor `D-44N-V44-AUGMENT-NN` (or equivalent ID per `.planning/REQUIREMENTS.md` convention).
  2. If the recommendation requires a `contracts/*.sol` diff: present a USER-APPROVED batched diff per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. The contract diff lands as a separate user-approved commit; the FIXREC-augment doc is AGENT-COMMITTED.
  3. If the recommendation requires a `test/*.sol` augmentation: bundle the test edit with the FIXREC-augment commit per `feedback_no_contract_commits.md` clarified policy (`test/` is autonomous within the same envelope; new test functions to cover the elevated VIOLATION ship in the FIXREC-augment commit).
  4. Trigger RE-PASS per `D-302-REPASS-SCOPE-01`: dispatch the 3 skills against the FIXREC-augment diff + the affected hypothesis subset only; produce RE-PASS-* files mirroring v42 P296 convention; integrate into a second-pass Disposition section in `307-01-ADVERSARIAL-LOG.md`.
  5. Cross-cite from Phase 308 TERMINAL `audit/FINDINGS-v44.0.md` §4 (forward-cite placeholder in the LOG — Phase 308 resolves the cross-cite at TERMINAL).

  **Why:** v44.0 is a FIX-milestone (unlike v43.0's audit-only posture which routed all elevations to `RNGLOCK-FIXREC.md`). Phase 305 IMPL already shipped the load-bearing contract diff; Phase 307 SWEEP is the post-IMPL adversarial gate. An elevated `FINDING_CANDIDATE` here means a real exposure that survived the SPEC + IMPL + TST passes — it should land as a discrete FIXREC-augment artifact (auditable + cross-cite-able from Phase 308), not get silently folded into Phase 308 or merged into Phase 305's existing diff post-hoc.

  **How to apply:** Plan Task 6 (conditional) executes this routing. Task 6's preconditions: (a) at least one surviving FINDING_CANDIDATE in the integrated Disposition table; (b) Tier-1 user-approval OR Tier-2 3-of-3 consensus. If neither precondition holds, Task 6 is skipped and Plan execution proceeds directly from Task 5 to Task 7.

### Claude's Discretion (planner & executor latitude)

- **Plan-level vs Task-level boundary for the conditional elevation** — D-307-PLAN-01 locks Task 6 as a conditional task inside Plan 01. Planner may at execution time decide whether Task 6's RE-PASS sub-step (item 4 in `D-307-ELEVATION-ROUTING-01`) deserves a separate sub-task or stays inline — purely a presentation choice; the artifact set is locked.
- **HYBRID-fallback trigger** — D-307-DISPATCH-01 prefers parallel-subagent dispatch for hunter+economist. If executor's first parallel attempt fails (subagent crash, malformed output, timeout), planner/executor falls back to SEQUENTIAL_MAIN_CONTEXT for the failing skill — no need to re-ask at runtime. Document the fallback in the per-skill MD's `[invocation]` frontmatter.
- **Charge augment expansion** — D-307-CHARGE-01 enumerates 5 augments (i)..(v). Planner expands each with evidence anchors AT PLAN TIME (Task 1 deliverable). If during expansion the planner identifies a 6th v44-specific surface deserving its own augment row (e.g., `INV-13` emergent invariant soundness as standalone), the planner adds it AND documents the addition in `307-01-PLAN.md` task-1 description; no re-ask required.
- **Severity tag enumeration** — D-307-SKEPTIC-FILTER-01 + D-307-AUDIT-TRAIL-01 use {CATASTROPHE, HIGH, MEDIUM, LOW, N-A}. Planner may add fine-grain sub-tags if useful; the 5-level baseline is the minimum.
- **Per-skill MD frontmatter additions** — D-307-SKEPTIC-FILTER-01 mandates `[skeptic-filter]` frontmatter + `[invocation]` frontmatter; planner may add additional structured frontmatter fields (e.g., `[charge-augment-coverage]` per-hypothesis-id-touched array) for orchestrator integration convenience.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, executor, subagent skills) MUST read these before planning or dispatching.**

### Phase 307 Anchors
- `.planning/ROADMAP.md` §"Phase 307: Adversarial Sweep (SWEEP)" — Goal statement + 5 success criteria + 3-skill HYBRID composition + Depends-on (Phases 305 + 306) + pre-authorized per D-44N-SWEEP-PREAUTH-01.
- `.planning/REQUIREMENTS.md` §"Adversarial Sweep (SWP)" — SWP-01..05 verbatim charges + post-pivot routing notes.

### Locked SPEC + v44 IMPL surfaces (load-bearing for adversarial probes)
- `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` — Phase 304 SPEC (960 lines, 35 LOCKED requirements: INV-01..12 + SPEC-01..05 + EDGE-01..18). **MUST read before authoring CHARGE.**
- `.planning/phases/305-implementation-impl/305-01-SUMMARY.md` — Phase 305 IMPL summary; v44 emergent surfaces: D-305-SENTINEL-01 (`pendingResolveDay` sentinel + INV-13 + PriorDayUnresolved revert); D-305-STRUCT-TIGHTEN-01 (1-slot DayPending 4×uint64 packing with mixed denominations); D-305-GWEI-SNAP-01 (gwei-at-source for exact `× roll / 100`); D-305-DUST-FLOOR-01 (MIN_BURN_AMOUNT 1e18 + BurnTooSmall revert); D-305-DAYTORESOLVE-01 (AdvanceModule reads sentinel, not `day - 1`); Vault scope-expansion (sdgnrsClaimRedemption(uint32 day)).
- `.planning/phases/305-implementation-impl/305-CONTEXT.md` — Phase 305 IMPL CONTEXT.
- `.planning/phases/306-test-tst/306-VERIFICATION.md` — Phase 306 TST verification; 13 INV + 20 EDGE + 8 per-function fuzz + V-184 strict-byte-identity + 2 gas regression assertions all PROVEN at deep × 256×128.

### Contracts under adversarial probe (post-Phase 305 IMPL HEAD)
- `contracts/StakedDegenerusStonk.sol` — Primary target. Key v44 surfaces: `:119` PriorDayUnresolved error; `:125` BurnTooSmall error; `:247` struct DayPending; `:259` pendingByDay mapping; `:269` pendingResolveDay sentinel; `:298` MIN_BURN_AMOUNT constant; `:636` DayPending storage read in `resolveRedemptionPeriod`; `:665` sentinel clear-on-resolve; `:812-823` `_submitGamblingClaimFrom` mint-floor + sentinel write.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 3 call sites: `:1228, :1294, :1327` read `sdgnrs.pendingResolveDay()`; `:1234, :1300, :1333` call `resolveRedemptionPeriod(redemptionRoll, flipDay, toResolve)`.
- `contracts/DegenerusVault.sol` — `:729` `sdgnrsClaimRedemption(uint32 day) external onlyVaultOwner` (scope-expansion).
- `contracts/interfaces/IStakedDegenerusStonk.sol` — `:87` `hasPendingRedemptions(uint32 day)`; `:92` `pendingResolveDay()`; `:104` `resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve)`.

### Test coverage proven at Phase 306 (must be re-considered for adversarial gap analysis)
- `test/invariant/RedemptionAccounting.t.sol` — 13 invariant_INV_NN_* fns; PROVEN at deep × 256×128. **Coverage gap probe per CHARGE augment (iv).**
- `test/fuzz/handlers/RedemptionHandler.sol` — 5 action selectors (burn, advance, claim, gameOver, burnOnPreviousDay) + 10 per-day ghost mappings.
- `test/fuzz/RedemptionEdgeCases.t.sol` — 20 testFuzz_EDGE_NN_* fns; PROVEN at 10k runs. EDGE-07 V-184 byte-identity at line 687.
- `test/fuzz/StakedStonkRedemption.t.sol` — 8 per-function fuzz tests.
- `test/fuzz/RngLockDeterminism.t.sol` — vm.skip flipped at line 1278 (TST-05); strict byte-identity asserted.
- `test/fuzz/RedemptionGas.t.sol` — 2 gas regression assertions (burn -29.8%; claim -57.5% vs v43).

### Skill source definitions (for sub-agent dispatch + persona fidelity)
- `~/.claude/skills/contract-auditor/SKILL.md` — `/contract-auditor` skill definition. SEQUENTIAL_MAIN_CONTEXT invocation per D-302-INVOKE-01 carry.
- `~/.claude/skills/zero-day-hunter/SKILL.md` — `/zero-day-hunter` skill definition. PARALLEL_SUBAGENT invocation (HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT per ROADMAP allowance).
- `~/.claude/skills/economic-analyst/SKILL.md` — `/economic-analyst` skill definition. PARALLEL_SUBAGENT invocation (HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT per ROADMAP allowance).

### Methodology precedents (Phase 302 + Phase 296 — load-bearing for shape inheritance)
- `.planning/milestones/v43.0-phases/302-cross-surface-adversarial-sweep-sweep/302-CONTEXT.md` — D-302-INVOKE-01 + D-302-CONSENSUS-01 + D-302-REPASS-SCOPE-01 + D-302-ARTIFACT-SET-01 + D-302-RESEARCH-AGENT-01 + D-302-TASK-SPLIT-01 + D-302-CHARGE-01 all carried verbatim into Phase 307.
- `.planning/milestones/v43.0-phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-CHARGE.md` — charge document format template.
- `.planning/milestones/v43.0-phases/302-cross-surface-adversarial-sweep-sweep/302-01-ADVERSARIAL-LOG.md` — integrated log format template (3 H2 sections + Disposition section).
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md` — v42 original of the inherited decision set (D-296-* = upstream of D-302-*).
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` — RE-PASS report shape template (load-bearing if elevation triggers RE-PASS per D-302-REPASS-SCOPE-01).

### Audit findings cross-cited
- `audit/FINDINGS-v43.0.md` §9d — HANDOFF-111..117 register (the 7 sStonk catalog rows closed by v44.0). Cross-cited for context only; not directly probed.
- `.planning/RNGLOCK-FIXREC.md` §103 — V-184 mechanic + game-theory walk (the original CATASTROPHE the refactor closes structurally). Probe target for SWP-01 invariant-violation hypotheses.

### Memory / feedback governing this phase
- `feedback_security_over_gas.md` — security/RNG-non-manipulability is the hard floor; reject any gas optimization that weakens an invariant. Adversarial-pass discipline: do NOT discard a finding because the fix would cost gas.
- `feedback_contract_locations.md` — only read contracts from `contracts/` directory; stale copies exist elsewhere.
- `feedback_wait_for_approval.md` — Phase 307 conditional Task 6 elevation: present FIXREC-augment + (if applicable) contract diff and wait for explicit user approval.
- `feedback_manual_review_before_push.md` — never push FIXREC-augment commits without explicit user diff review.
- `feedback_no_contract_commits.md` — `test/` autonomous within the FIXREC-augment envelope; `contracts/*.sol` need explicit user approval.
- `feedback_no_history_in_comments.md` — adversarial-pass artifacts describe what IS; cross-reference SPEC/INV/EDGE IDs as anchors not as history.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved (applies to FIXREC-augment contract diffs if any land at Task 6).
- `feedback_batch_contract_approval.md` — batch all contract edits in a single user-approved commit (applies to FIXREC-augment contract diffs).
- `feedback_design_intent_before_deletion.md` — applies if a FIXREC-augment proposes a deletion; trace design-intent + actor game-theory BEFORE proposing.
- `feedback_frozen_contracts_no_future_proofing.md` — adversarial-pass artifacts do not propose future-extensibility scaffolding.
- `feedback_rng_backward_trace.md` — RNG audit must trace backward from each consumer; relevant for SWP-01 + augment (ii) sentinel race + augment (iv) coverage-gap probes.
- `feedback_rng_commitment_window.md` — RNG audit must check what player-controllable state can change between VRF request and fulfillment; relevant for augment (ii) sentinel state-machine probes.
- `feedback_rng_window_storage_read_freshness.md` — enumerate ALL SLOADs inside rng-window; relevant for augment (iv) Phase 306 INV harness coverage gap probe.
- `feedback_verify_call_graph_against_source.md` — planning claims must be grep-verified against source; Plan Task 1 grep-verifies all v44 surfaces cited in this CONTEXT.md before authoring CHARGE.
- `feedback_skeptic_pass_before_catastrophe.md` — load-bearing. Operationalized via D-307-SKEPTIC-FILTER-01 (dual-gate + strict structural-protection + (a)-only hard discard + (b)/(c) severity-downgrade).
- `feedback_skip_research_test_phases.md` — D-302-RESEARCH-AGENT-01 carry: skip gsd-phase-researcher dispatch for Phase 307.

### Milestone & state
- `.planning/PROJECT.md` — v44.0 milestone goal + v43.0 audit baseline HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`.
- `.planning/STATE.md` — current focus (Phase 307 SWEEP; Phase 306 closed at commit `b102bc0f` + `e0f7d77e`).
- `KNOWN-ISSUES.md` — UNMODIFIED per `D-44N-KI-01`. Phase 307 does NOT touch KNOWN-ISSUES.md; Phase 308 §6 re-verifies EXC-01..04 RE_VERIFIED-NEGATIVE-scope.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **v42 P296 + v43 P302 ADVERSARIAL-CHARGE.md template** — direct inheritance; substitute v44 audit-subject anchors (D-305-SENTINEL-01 / D-305-STRUCT-TIGHTEN-01 / D-305-GWEI-SNAP-01 / D-305-DUST-FLOOR-01 / D-305-DAYTORESOLVE-01 / Vault scope-expansion) for v43 anchors (Phase 298 CATALOG / Phase 299 FIXREC / Phase 300 ADMA / Phase 301 FUZZ).
- **v42 P296 + v43 P302 ADVERSARIAL-LOG.md 3-H2-section structure** — direct template inheritance plus Phase 307-specific additions: Skeptic-Filter Discarded inline table (per D-307-AUDIT-TRAIL-01) + Severity-Downgrade Rationale table (per D-307-SKEPTIC-FILTER-01) alongside the integrated Disposition table.
- **Two-tier consensus rule (D-302-CONSENSUS-01)** — verbatim carry from v42 P296 / v43 P302.
- **Skeptic-reviewer filter pattern** — first formal operationalization for Phase 307 (memory `feedback_skeptic_pass_before_catastrophe.md` predated formal operationalization in v43 P302); Phase 307 establishes the dual-gate + strict-structural-protection + (a)-hard-discard / (b)+(c)-severity-downgrade pattern.

### Established Patterns
- **AGENT-COMMITTED adversarial-log artifact bundle** — Phase 283 + Phase 296 + Phase 302 precedent.
- **HYBRID invocation pattern** — Phase 296 + Phase 302 ran sequential `/contract-auditor` + parallel `/zero-day-hunter` + `/economic-analyst`.
- **Single-plan, 7-task structure** — D-302-TASK-SPLIT-01 verbatim carry.
- **Conditional Task 6 elevation routing** — pattern: precondition gate at task start; if gate fails, skip the task and proceed to Task 7. Phase 302 inherited the pattern from v42 P296.

### Integration Points
- **Phase 305 IMPL (commit `213f9184`) → Phase 307 SWEEP** — Phase 305 ships the v44 source under adversarial probe; D-305-SENTINEL-01 + D-305-STRUCT-TIGHTEN-01 + D-305-GWEI-SNAP-01 + D-305-DUST-FLOOR-01 + D-305-DAYTORESOLVE-01 + Vault scope-expansion are the v44 surfaces the augment hypotheses target.
- **Phase 306 TST (commits `de75f620`..`e0f7d77e`) → Phase 307 SWEEP** — Phase 306 proves 13 INV + 20 EDGE coverage; augment (iv) probes the harness for perturbation-class gaps (transfer mid-pending, approve mid-stall, multi-actor sentinel race, ERC20-callback re-entry, admin-class actions during rngLock, partial-claim BURNIE under sentinel-stall).
- **Phase 307 SWEEP → Phase 308 TERMINAL** — `307-01-ADVERSARIAL-LOG.md` Disposition section + Skeptic-Filter Discarded table + Severity-Downgrade Rationale table feed `audit/FINDINGS-v44.0.md` §4 adversarial-pass disposition (AUDIT-06). Forward-cite placeholder in the LOG; Phase 308 resolves the cross-cite at TERMINAL.

</code_context>

<specifics>
## Specific Ideas

- **Pre-authorized invocation** — Phase 307 fires the 3-skill HYBRID without re-pinging at plan kickoff per `D-44N-SWEEP-PREAUTH-01`. Tier-1 single-skill `FINDING_CANDIDATE` still triggers AskUserQuestion user-pause per `D-302-CONSENSUS-01` carry; Tier-2 3-of-3 auto-elevates without intermediate user checkpoint.
- **Dual-gate skeptic filter** — first formal operationalization of the filter mandated by `feedback_skeptic_pass_before_catastrophe.md`; per-skill self-filter + orchestrator integration-time re-application.
- **(a)-only hard discard, (b)+(c) severity-downgrade** — small-EV findings survive as MEDIUM/LOW (not silently dropped) so the LOG captures every reachable-by-attacker exposure for audit-trail completeness.
- **Augment (ii) sentinel probe is high-priority** — `pendingResolveDay` is brand-new in v44 (no v43 precedent); the sentinel writer + reader semantics across `_submitGamblingClaimFrom`/`resolveRedemptionPeriod`/`AdvanceModule._gameOverEntropy`/`AdvanceModule._advanceGame` deserve concentrated attention.
- **Augment (iv) harness gap probe ties Phase 307 directly to Phase 306** — the 13 INV + 20 EDGE harness PROVED its target invariants but cannot prove the absence of perturbation-class blind spots; Phase 307's `/zero-day-hunter` is uniquely positioned to surface them.

</specifics>

<deferred>
## Deferred Ideas

- **`/degen-skeptic` re-inclusion** — OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry; revisit only if v45.0+ adversarial-pass policy changes.
- **4th+ skill addition (e.g., `/zeneca`, `/doug-polk`)** — defer to milestone-level decision; v44 stays at 3-skill HYBRID.
- **Cross-milestone adversarial RE-PASS (re-run v43 SWEEP against v44 surfaces)** — Phase 308 §5 REG-01 non-widening attestation + KI walkthrough already covers v43-surface integrity; explicit re-run not needed.
- **Direct `contracts/*.sol` augment within Phase 307 without FIXREC-augment artifact** — REJECTED per `D-307-ELEVATION-ROUTING-01`. Even if an elevation lands and triggers a contract diff, the diff is preceded by an AGENT-COMMITTED `307-FIXREC-AUGMENT.md` to preserve the audit trail.
- **Defer all elevation to Phase 308 TERMINAL** — REJECTED per `D-307-ELEVATION-ROUTING-01`. Phase 307 handles elevation in-phase so the RE-PASS discipline + skeptic-filter re-application can run against the augment diff before Phase 308 closure; Phase 308 §4 cross-cites the resolved Phase 307 outcome.
- **6th+ CHARGE augment surface** — at planner's discretion per `D-307-CHARGE-01` "Claude's Discretion" clause; not pre-locked in CONTEXT.md.
- **Adversarial RE-PASS against Phase 308 §3.F formal invariant attestation matrix** — Phase 308 itself is a planning + writing phase, not a contract-mutation phase; no RE-PASS needed against §3.F.

</deferred>

---

*Phase: 307-adversarial-sweep-sweep*
*Context gathered: 2026-05-19*
