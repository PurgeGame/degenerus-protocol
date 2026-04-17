# Phase 231: Earlybird Jackpot Audit - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of every earlybird-related change between v27.0 baseline (`14cb45e1`) and HEAD. Two commits own this surface: **`f20a2b5e`** ("refactor(earlybird): finalize at level transition, unify award call per purchase") and **`20a951df`** ("feat(earlybird): align trait roll with coin jackpot, fix queue level"). Produces per-function verdicts (PASS / FAIL / DEFER) for every function touched across §1.1 (AdvanceModule), §1.2 (JackpotModule), §1.4 (MintModule), §1.5 (WhaleModule), §1.6 (DegenerusGame core), and §1.9 (Storage `_awardEarlybirdDgnrs`) of the Phase 230 catalog, plus an end-to-end trace of the combined purchase-phase-finalize + jackpot-phase-run state machine (EBD-03).

This phase is strictly READ-only. Catalog-only deliverables under `.planning/phases/231-earlybird-jackpot-audit/`. No writes to `contracts/` or `test/`. No `F-29-NN` finding IDs are emitted — findings-candidate blocks are collected for Phase 236 FIND-01 consolidation, which owns ID assignment.

This phase is NOT: (a) the RNG commitment-window re-proof of the earlybird bonus-trait roll — that is Phase 235 RNG-01 / RNG-02; (b) the ETH conservation proof across the delta — that is Phase 235 CONS-01; (c) findings-severity classification or `FINDINGS-v29.0.md` consolidation — that is Phase 236. Phase 231 surfaces candidate concerns and evidence, nothing more.

</domain>

<decisions>
## Implementation Decisions

### Deliverable Shape
- **D-01:** Three plan files under this phase directory — `231-01-PLAN.md` (EBD-01 purchase-phase finalize, `f20a2b5e`), `231-02-PLAN.md` (EBD-02 trait-alignment, `20a951df`), `231-03-PLAN.md` (EBD-03 combined state machine). One plan per requirement per auto-rule 6. EBD-01 and EBD-02 touch different commits, different files, and different invariants; EBD-03 is an end-to-end cross-commit trace that reads cleanest as its own plan. Each plan produces its own `231-0N-AUDIT.md` artifact following the v25.0 Phase 214 per-class audit file precedent (`214-01-REENTRANCY-CEI.md`, `214-02-ACCESS-OVERFLOW.md`, `214-03-STATE-COMPOSITION.md`).
- **D-02:** Each `231-0N-AUDIT.md` contains a per-function verdict table using locked columns `Function | File:Line | Attack Vector Considered | Verdict (PASS/FAIL/DEFER) | Evidence | Owning SHA` (auto-rule 4). Multiple attack vectors per function produce multiple rows. A findings-candidate block (free-form prose, no `F-29-NN` IDs) follows the table.

### Audit Methodology
- **D-03:** Fresh read from HEAD source — no reuse of v25.0 Phase 214 or v27.0 Phase 223 verdicts as pre-approved. Carries forward the v25.0 Phase 214 D-02 convention: audit every function as if no prior work exists. Prior-phase conclusions may be cited as regression anchors only, never as exemption.
- **D-04:** Scope source is `230-01-DELTA-MAP.md` §4 Consumer Index rows for EBD-01, EBD-02, EBD-03 exclusively. Each plan enumerates its target functions by citing the anchor rows (`§1.2 / §2.1 / IM-NN / commit SHA`) before writing any verdict.
- **D-05:** Every verdict row cites the 7-char commit SHA (auto-rule 5). For MODIFIED functions owned by both in-scope commits (e.g., if any function were touched by both `f20a2b5e` and `20a951df`), both SHAs are cited. The SHA citation is what makes the verdict traceable back to the delta.

### Scope Guard
- **D-06:** `230-01-DELTA-MAP.md` is READ-only per Phase 230 D-06. If this phase discovers a function or chain that affects earlybird behavior but is not anchored in §4 Consumer Index EBD-01/02/03 rows, the finding is recorded as a **scope-guard deferral** in `231-0N-AUDIT.md` → "Scope-guard Deferrals" subsection citing Phase 236 REG-01 / FIND-01 as the receiver. Phase 230 is not edited in-place. Follows the v28.0 D-227-10 / D-228-09 precedent.
- **D-07:** If this phase identifies a concern that overlaps Phase 235's territory (RNG commitment, ETH conservation), it is recorded as a **downstream hand-off** in the findings-candidate block with the target Phase 235 requirement ID (RNG-01 / RNG-02 / CONS-01 / TRNX-01). The concern is not re-proved here.

### Attack Vector Coverage
- **D-08:** Attack vector enumeration per requirement is fixed — planner MUST include at minimum:
  - **EBD-01 (purchase finalize, `f20a2b5e`):** (a) CEI ordering at `_finalizeEarlybird` + `_purchaseFor` unified award call, (b) reentrancy across `recordMint` no-longer-awards path, (c) storage read/write ordering for pool SLOADs before `_awardEarlybirdDgnrs`, (d) budget conservation at level-transition dump (Earlybird → Lootbox via DGNRS contract), (e) signature-contraction correctness (3-arg → 2-arg: dropped `passLevel` / `startLevel` / `currentLevel` must not be load-bearing downstream), (f) gas delta vs v27.0 worst-case purchase path, (g) double-award prevention (`recordMint` no longer calls `_awardEarlybirdDgnrs` — verify no regression path where it fires twice or zero times).
  - **EBD-02 (trait-alignment, `20a951df`):** (a) bonus-trait parity with coin jackpot (same 4 traits from same VRF word via `_rollWinningTraits(rngWord, true)`), (b) salt-space isolation — the `true` bonus branch and the `false` main branch must keccak-separate (this is the invariant Phase 233 JKP-03 also cares about; Phase 231 surfaces candidates, Phase 233 owns the cross-path proof), (c) fixed-level queueing at `lvl+1` (the "queue-level fix" per commit message — verify the queue index writes to the resolution level, not the current level), (d) futurePool → nextPool budget conservation across the rewritten jackpot block.
  - **EBD-03 (combined state machine):** (a) no double-spend across the (purchase finalize) → (jackpot-phase run) handoff, (b) no orphaned reserves when `_finalizeEarlybird` fires at `EARLYBIRD_END_LEVEL`, (c) no missed emissions across normal / skip-split / gameover transitions, (d) cross-commit invariant: the pool balance the purchase-phase finalize dumps is exactly what the jackpot-phase trait roll operates on (no drift between the two commits).

### Finding-ID Deferral
- **D-09:** No `F-29-NN` finding IDs are emitted in Phase 231. Verdicts with `FAIL` or `DEFER` become finding-candidate entries referenced by Phase 236 FIND-01, which performs severity classification and ID assignment. This aligns with the v25.0 Phase 217 / v27.0 Phase 223 consolidation pattern.

### Claude's Discretion
- Exact AUDIT.md section ordering (per-function table first vs. attack-vector preamble first) — planner chooses most readable
- Whether to use a single consolidated verdict table per plan or separate tables by function (v25.0 Phase 214 used single tables per pass)
- How to depict the combined state machine in 231-03 (ASCII state diagram vs. numbered path walk vs. table). ASCII diagrams are allowed if they clarify; no hard requirement
- Whether to commit each plan atomically or bundle into one commit at phase close — defer to executor's GSD workflow standard

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope source (MANDATORY)
- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md` — specifically:
  - §1.1 DegenerusGameAdvanceModule rows for `_finalizeRngRequest` + `_finalizeEarlybird` (NEW by `f20a2b5e`)
  - §1.2 DegenerusGameJackpotModule rows for `_runEarlyBirdLootboxJackpot` (MODIFIED by `20a951df`)
  - §1.4 DegenerusGameMintModule rows for `_purchaseFor` + `_callTicketPurchase` (MODIFIED by `f20a2b5e`)
  - §1.5 DegenerusGameWhaleModule rows for `_purchaseWhaleBundle` / `_purchaseLazyPass` / `_purchaseDeityPass` (MODIFIED by `f20a2b5e`)
  - §1.6 DegenerusGame rows for `recordMint` (MODIFIED by `f20a2b5e` — award-block removed)
  - §1.9 DegenerusGameStorage rows for `_awardEarlybirdDgnrs` (MODIFIED by `f20a2b5e`, 3-arg → 2-arg)
  - §2.1 Earlybird-related chains IM-01..IM-05 (all `f20a2b5e`)
  - §2.3 IM-16 (Jackpot-phase `_runEarlyBirdLootboxJackpot` → `_rollWinningTraits`, `20a951df`)
  - §4 Consumer Index rows for EBD-01, EBD-02, EBD-03 — the authoritative scope anchor
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md` — known non-issues #1 (boonPacked interface gap — NOT earlybird), #5 (forge build warnings — not delta-introduced). Neither blocks this phase.

### Milestone
- `.planning/REQUIREMENTS.md` — EBD-01, EBD-02, EBD-03 definitions
- `.planning/ROADMAP.md` — Phase 231 block: Goal, Depends on Phase 230, Success Criteria 1-4
- `.planning/PROJECT.md` — Key Decisions log + milestone context (v29.0 READ-only rule)
- `.planning/STATE.md` — current project position

### Owning commits (verify at HEAD)
- `f20a2b5e` refactor(earlybird): purchase-phase finalize refactor — unified award call per purchase + NEW `_finalizeEarlybird` level-transition hook
- `20a951df` feat(earlybird): trait-roll alignment with coin jackpot + `lvl+1` queue fix

### Target files (derived from §1 subsections touched — read from these at HEAD, never from stale copies outside `contracts/`)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — hosts `_finalizeRngRequest`, NEW `_finalizeEarlybird`, EARLYBIRD_END_LEVEL constant
- `contracts/modules/DegenerusGameJackpotModule.sol` — hosts `_runEarlyBirdLootboxJackpot`, `_rollWinningTraits`
- `contracts/modules/DegenerusGameMintModule.sol` — hosts `_purchaseFor`, `_callTicketPurchase`
- `contracts/modules/DegenerusGameWhaleModule.sol` — hosts `_purchaseWhaleBundle`, `_purchaseLazyPass`, `_purchaseDeityPass`
- `contracts/DegenerusGame.sol` — hosts `recordMint` (award block removed per `f20a2b5e`)
- `contracts/storage/DegenerusGameStorage.sol` — hosts `_awardEarlybirdDgnrs` (2-arg form)

### Methodology precedent
- `.planning/milestones/v25.0-phases/214-adversarial-audit/214-CONTEXT.md` — adversarial phase CONTEXT shape (per-function verdict discipline, "fresh-from-scratch" D-02 rule)
- `.planning/milestones/v25.0-phases/214-adversarial-audit/214-01-REENTRANCY-CEI.md` / `214-02-ACCESS-OVERFLOW.md` / `214-03-STATE-COMPOSITION.md` — per-audit-class artifact structure to mirror in 231-0N-AUDIT.md files
- `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` — RNG commitment-window approach (Phase 231 surfaces earlybird-roll concerns, Phase 235 RNG-01/02 finalizes them)
- `.planning/phases/230-delta-extraction-scope-map/230-CONTEXT.md` — CONTEXT.md layout this file mirrors (Phase Boundary / Implementation Decisions / Canonical References / Existing Code Insights / Specific Ideas / Deferred Ideas)

### Downstream dependencies
- **Phase 233 JKP-03** will re-prove cross-path bonus-trait consistency (purchase / jackpot / earlybird produce identical 4-trait sets for identical VRF word). Phase 231 EBD-02 surfaces the salt-space-isolation concern; Phase 233 owns the cross-path proof.
- **Phase 235 RNG-01** will back-trace that the VRF word consumed in `_runEarlyBirdLootboxJackpot._rollWinningTraits(rngWord, true)` was unknown at its input-commitment time. Phase 231 surfaces candidate concerns only.
- **Phase 235 RNG-02** will enumerate player-controllable state between VRF request and the earlybird consumer's fulfillment. Phase 231 records candidate variables; Phase 235 finalizes.
- **Phase 235 CONS-01** will close the ETH conservation proof across every pool-mutating SSTORE in the delta, including the `_finalizeEarlybird` dump and the `_runEarlyBirdLootboxJackpot` pool arithmetic. Phase 231 verifies CEI position of these SSTOREs; Phase 235 proves algebraic sum-before = sum-after.
- **Phase 236 FIND-01** consolidates all `FAIL` / `DEFER` verdicts from this phase into `F-29-NN` IDs in `audit/FINDINGS-v29.0.md`.

</canonical_refs>

<code_context>
## Existing Code Insights

Observations derived from `230-01-DELTA-MAP.md` — these are the scope anchors, not fresh code reads (fresh reads belong in the plans):

- **Unified award call (f20a2b5e).** `§2.1 IM-01..IM-04` — four caller sites (`_purchaseFor`, `_purchaseWhaleBundle`, `_purchaseLazyPass`, `_purchaseDeityPass`) were updated to the 2-arg `_awardEarlybirdDgnrs(buyer, wei)` signature. The previous pair of calls (one in `recordMint`, one inline in the lootbox branch of `_purchaseFor`) is collapsed to a single bottom-of-purchase call per entry point. Double-award regression and missed-award regression are both in scope for EBD-01.
- **NEW level-transition hook (f20a2b5e).** `§2.1 IM-05` — `_finalizeRngRequest` calls the NEW `_finalizeEarlybird` exactly once when `lvl == EARLYBIRD_END_LEVEL`. The hook flips a sentinel and dumps the remaining Earlybird pool into Lootbox via the DGNRS external contract (`dgnrs.transferBetweenPools`). The DGNRS call itself is out-of-scope (external contract — per §2 preamble excluded-chains note), but the sentinel flip, the pool-balance read, and the one-shot-idempotency are IN scope for EBD-01.
- **recordMint award-block removed (f20a2b5e).** `§1.6` — `DegenerusGame.recordMint` MODIFIED; external ABI unchanged (per `§3.1 ID-11 PASS`), but the earlybird-award block was removed from the body. EBD-01 must verify no downstream caller still expects `recordMint` to award, and that the removal doesn't create a gap on the `recordMintQuestStreak` / quest-credit path adjacent to the removal.
- **Signature contraction (f20a2b5e).** `§1.9` — `_awardEarlybirdDgnrs` dropped the `currentLevel` / `passLevel` / `startLevel` third argument. EBD-01 must verify the function's body no longer branches on the level (the caller no longer supplies it) AND that no internal read substitutes an incorrect live-state read for the dropped argument (e.g., `storageGetter().level()` mid-purchase vs. the previously-passed `passLevel` for whale bundles).
- **Earlybird trait-roll parity (20a951df).** `§2.3 IM-16` — `_runEarlyBirdLootboxJackpot` NEW call to `_rollWinningTraits(rngWord, true)`. The `true` parameter is the bonus-branch salt flag established in v26.0 Phase 218 (BonusJackpotSplit). EBD-02 must verify (a) `_rollWinningTraits` still honors the salt-flag keccak separation, (b) the same `rngWord` entering this path produces the same 4-trait output as the coin-jackpot path consuming the same `rngWord` with `bonus=true`.
- **Fixed-level queueing at lvl+1 (20a951df).** Commit message says "fix queue level" — EBD-02 must identify the pre-fix queue-index expression, confirm it wrote to the wrong level (likely the current level, not the resolution level), and verify the post-fix write targets `lvl+1` (consistent with DCM-01's `decimatorBurn` keying-by-resolution-level convention at `§1.8`).
- **futurePool → nextPool conservation (20a951df).** EBD-02's Phase 235 hand-off concern: the earlybird-rewrite's pool arithmetic must not introduce a drift between futurePool and nextPool at the jackpot boundary. Phase 231 verifies CEI position and write ordering; Phase 235 CONS-01 proves algebraic closure.
- **Cross-commit state machine (f20a2b5e + 20a951df).** EBD-03 traces (purchase-phase level progression → `_finalizeEarlybird` at EARLYBIRD_END_LEVEL → jackpot-phase `_runEarlyBirdLootboxJackpot` → `_rollWinningTraits(rngWord, true)`). The sentinel flipped in `_finalizeEarlybird` must prevent re-entry of the finalize path on subsequent level transitions. The pool dumped to Lootbox must be the same pool the jackpot-phase run consumes — no drift, no orphaned reserve, no missed emission.
- **Interface drift — none.** `§3.1` rows ID-11 (recordMint) etc. all PASS at HEAD. No interface was re-shaped by `f20a2b5e` or `20a951df`, so EBD-01/02/03 need not re-verify ABI alignment (that is DELTA-03's territory, already closed by Phase 230).
- **Automated-gate corroboration.** `§3.4` records `make check-interfaces` PASS and `forge build` PASS at HEAD. `§3.5` records `make check-delegatecall` PASS (44/44 sites, +1 vs. v27.0 baseline from IM-08 — not an earlybird chain). Phase 231 does not need to re-run these gates; it cites them.

</code_context>

<specifics>
## Specific Ideas

Three plans (one per EBD requirement per D-01):

1. **`231-01-PLAN.md` — EBD-01 Purchase-Phase Finalize Refactor (`f20a2b5e`).** Produces `231-01-AUDIT.md` with a per-function verdict table covering `_finalizeRngRequest`, `_finalizeEarlybird` (NEW), `_purchaseFor`, `_callTicketPurchase`, `_purchaseWhaleBundle`, `_purchaseLazyPass`, `_purchaseDeityPass`, `recordMint` (award-block removed), `_awardEarlybirdDgnrs` (2-arg). Attack vectors per D-08 EBD-01 (CEI, reentrancy, storage ordering, budget conservation at level-transition dump, signature-contraction correctness, gas, double/zero-award regression). Cites `§2.1 IM-01..IM-05` and commit `f20a2b5e` rows.

2. **`231-02-PLAN.md` — EBD-02 Trait-Alignment Rewrite (`20a951df`).** Produces `231-02-AUDIT.md` with a per-function verdict table covering `_runEarlyBirdLootboxJackpot`, `_rollWinningTraits` (read-only re-verification of bonus-branch keccak separation). Attack vectors per D-08 EBD-02 (bonus-trait parity, salt-space isolation, `lvl+1` queue, futurePool → nextPool conservation). Cites `§2.3 IM-16` and commit `20a951df` rows. Hands off algebraic pool-conservation to Phase 235 CONS-01 per D-07.

3. **`231-03-PLAN.md` — EBD-03 Combined State Machine.** Produces `231-03-AUDIT.md` with a numbered path walk (no per-function table — this plan is cross-function tracing) + a verdict block. Attack vectors per D-08 EBD-03 (no double-spend, no orphaned reserves, no missed emissions, cross-commit invariant). Cites `§1.1 IM-05 + §1.2 + §1.9 + §2.1 + §2.3 IM-16`. Normal / skip-split / gameover transitions enumerated from `DegenerusGameAdvanceModule.advanceGame` phase-branching structure (consistent with how v24.0 Phase 203 traced game-over paths).

Each AUDIT.md ends with a "Findings-Candidate Block" (no `F-29-NN` IDs per D-09) plus a "Scope-guard Deferrals" subsection (per D-06) and a "Downstream Hand-offs" subsection (per D-07).

</specifics>

<deferred>
## Deferred Ideas

Intentionally OUT of scope for Phase 231 (do not pursue in-place here):

- **RNG backward trace for the earlybird bonus-trait roll.** The proof that `rngWord` feeding `_rollWinningTraits(rngWord, true)` in `_runEarlyBirdLootboxJackpot` was unknown at its input-commitment time → **Phase 235 RNG-01**.
- **RNG commitment-window analysis for the earlybird consumer.** Enumeration of player-controllable state that can change between VRF request and earlybird-path fulfillment → **Phase 235 RNG-02**.
- **ETH conservation algebraic closure.** Sum-before = sum-after proof for every pool-mutating SSTORE in `_finalizeEarlybird` (dump to Lootbox) and `_runEarlyBirdLootboxJackpot` (futurePool → nextPool) → **Phase 235 CONS-01**.
- **BURNIE conservation across earlybird.** Not currently believed to be a surface (earlybird handles DGNRS, not BURNIE), but if EBD-01 surfaces an unexpected BURNIE mint/burn, the algebraic proof → **Phase 235 CONS-02**.
- **Cross-path bonus-trait consistency proof.** Purchase-phase path vs. jackpot-phase path vs. earlybird path all producing identical 4-trait set for identical `rngWord` → **Phase 233 JKP-03**. Phase 231 EBD-02 verifies the earlybird path's call to `_rollWinningTraits` is correctly formed; Phase 233 owns the cross-path identity proof.
- **Finding-ID assignment and severity classification.** `F-29-NN` numbering, severity (CRITICAL/HIGH/MEDIUM/LOW/INFO), `audit/FINDINGS-v29.0.md` consolidation → **Phase 236 FIND-01**.
- **v25.0 / v26.0 / v27.0 regression re-verification against earlybird changes.** Whether any prior finding regresses due to `f20a2b5e` / `20a951df` → **Phase 236 REG-01 / REG-02**.
- **Gas-only benchmarking sweep.** Per `REQUIREMENTS.md` Out-of-Scope: "Gas changes in the delta are verified within the audit; no standalone gas-only phase." EBD-01 may note gas deltas as part of its verdict; no standalone profiling.

</deferred>

---

*Phase: 231-earlybird-jackpot-audit*
*Context gathered: 2026-04-17*
