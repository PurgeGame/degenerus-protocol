# Phase 271: Delta Audit + Findings Consolidation (Terminal) - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Publish `audit/FINDINGS-v37.0.md` as the v37.0 milestone-closure deliverable, mirroring v32.0 / v33.0 / v34.0 / v35.0 / v36.0 9-section shape and emitting closure signal `MILESTONE_V37_AT_HEAD_<sha>` in §9c. Phase 271 is the **terminal** audit phase of v37.0 (v37.0 = Phases 267-271 — 1 Degenerette contracts phase + 1 stat/surf phase + 1 partial-ship maintenance phase + 1 sub-audit feeder + 1 audit phase).

**Audit baseline:** v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`).

**v37.0 source-tree HEAD at Phase 271 entry:** `8fd5c2e1` (Phase 269 LBX-01 contract commit; Phase 270 emitted zero source-tree mutations so source-tree HEAD unchanged from Phase 269 close). Docs-tree HEAD at Phase 271 entry: `71e7633c` (Phase 270 close).

**Contract-tree commits since baseline (2 total):**

- `e1136071` — Phase 267 (`feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`; `contracts/DegenerusTraitUtils.sol` additive +45 LOC + `contracts/modules/DegenerusGameDegeneretteModule.sol` rewrite +231/-196 LOC)
- `8fd5c2e1` — Phase 269 (`feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]`; `contracts/modules/DegenerusGameLootboxModule.sol` −14/+1 LOC; pure LBX-01 deletion + user-approved cascade param cleanup; bytecode shrink 177 bytes 18,330→18,153)

**Test-tree commits since baseline (1 batched + tooling):**

- `4b277aaf` — Phase 268 (`test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`; +2,277/-1 LOC across 6 files; 3 NEW `test/stat/` files + 1 EXTENDED `test/stat/SurfaceRegression.test.js` v37.0 SURF-01..04 describe + 1 NEW `test/gas/Phase268GasRegression.test.js` + package.json wiring)

All test files USER-APPROVED batched per `feedback_batch_contract_approval.md`. ZERO awaiting-approval files at Phase 271 plan-start (mirrors v34/v35/v36 §9.NN absence).

**Ten v37.0 audit requirements** (per ROADMAP §"Phase 271" success criteria — REQUIREMENTS.md AUDIT-01..06 + REG-01..04):

- **AUDIT-01** — §3.A delta-surface table covers all source-tree changes v36.0 audit-subject HEAD `1c0f0913` → v37.0 closure HEAD with hunk-level evidence + {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification:
  - **Phase 267 Degenerette contract changes:**
    - `DegenerusTraitUtils.packedTraitsDegenerette` (NEW; library `internal pure`, inlined into consumer at compile time — does NOT widen public ABI)
    - `DegenerusGameDegeneretteModule._evNormalizationRatio` (DELETED at L808-851 + single call site at L965-969)
    - `DegenerusGameDegeneretteModule._countGoldQuadrants` (NEW)
    - `DegenerusGameDegeneretteModule._getBasePayoutBps` (REWRITTEN — 5-table per-N dispatch)
    - `DegenerusGameDegeneretteModule._applyHeroMultiplier` (REWRITTEN — symbol-only hero match + per-N hero boost dispatch)
    - `DegenerusGameDegeneretteModule._wwxrpBonusRoiForBucket` (REWRITTEN — 5-table per-N factor dispatch)
    - `DegenerusGameDegeneretteModule._distributePayout` (REWRITTEN — 3-tier ETH split rule per PAY-SPLIT-01..03; `betAmount` threaded as 5th argument; CURRENCY_BURNIE + CURRENCY_WWXRP branches UNCHANGED)
    - 25 packed constants delta (11 → 24 net): 5 payout PACKED + 5 jackpot M8 + 5 hero boost PACKED + 5 WWXRP factors PACKED − 4 single-table constants − 2 normalizer constants
    - 4 stale comments rewritten (L239 / L262 / L287-298 / L316)
    - `packedTraitsFromSeed` callsite at L607 SWAPPED to `packedTraitsDegenerette`
  - **Phase 269 LootboxModule dead-branch deletion:**
    - `_resolveLootboxRoll` inner `if (targetLevel < currentLevel)` branch DELETED (L1574-1578 pre-deletion line numbers); replaced with direct `ticketsOut = ticketsScaled;` assignment
    - Cascade signature cleanup: `targetLevel` + `currentLevel` params dropped from `_resolveLootboxRoll` signature + 2 callsites + 2 NatSpec @param lines
    - **LBX-03 audit-trail row** — Phase 271 author records v36.0 ENT-02 callsite numbering at HEAD post-LBX-01 line shift; bit-slice budget UNAFFECTED; 4 hash2/bit-slice callsites at v36.0 line numbers L1548 / L1569 / L1585 / L1599 survive byte-identical at the structural level (line numbers shift downward by ~14 LOC after dead-branch removal)
  - **Phase 270 post-v32.0 carry-forward declarations:** 2-row commit-summary entries grep-citable from Phase 270 working-file appendix (canonical path `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md`):
    - `002bde55` (presale auto-deactivate) — 5 declaration rows: AdvanceModule cap-OR arm DELETED + AdvanceModule constant DELETED + GameStorage constant NEW + MintModule inlined SLOAD/mask/SSTORE MODIFIED_LOGIC + MintModule per-mint cap-clear predicate NEW
    - `2713ce61` (setDecimatorAutoRebuy removal) — 2 declaration rows: vault wrapper DELETED + fuzz coverage entry DELETED

- **AUDIT-02** — §4 adversarial sweep verdicts every identified surface SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with explicit row-level evidence covering at minimum 8 surfaces:
  - **(a)** per-N table dispatch correctness vs match-count distribution P_N(M) — Phase 268 STAT-01 + STAT-05 empirical evidence
  - **(b)** symbol-only hero match preserves uniformity, no color-channel info leak — DGN-07 design contract
  - **(c)** `_countGoldQuadrants` boundary `color == 7` strict (not `>= 7`) — overflow / off-by-one immune
  - **(d)** producer `[16,16,16,16,16,16,16,8]/120` byte-layout consistency with downstream consumers — DGN-01 + DGN-14 surface preservation
  - **(e)** WWXRP factor table-dispatch composition with hero boost — no double-counting in `_fullTicketPayout` per DGN-09
  - **(f)** lootbox dead-branch removal byte-equivalence via caller-clamp invariant at L882-884 — Layer-1 `openLootBox` L557-559 + Layer-2 `_resolveLootboxCommon` L882-884 unconditionally clamp `targetLevel = max(targetLevel, currentLevel)` before `_resolveLootboxRoll` is reached; deleted branch was Layer-3 unreachable defense
  - **(g)** hero × per-N composition skill-expression channel preserved (v34.0 surface (f) carry-forward)
  - **(h)** ETH payout split-rule monotonicity + boundary-gaming check — `_distributePayout` 3-tier rule (PAY-SPLIT-01 ≤3× all-ETH + PAY-SPLIT-02 2.5× floor on 3-10× band + PAY-SPLIT-03 pool-cap precedence) composes correctly across all per-N × roiBps × hero × WWXRP-bonus combinations; boundary discontinuity at exactly 3.0× bet documented as accepted (3.0× → 2.5× ETH drop at 3.01× under min-2.5× floor); thin-pool cap-flip path preserves `ethShare + lootboxShare = payout` invariant; Phase 268 STAT-07 empirically validates per-band frequency distribution

- **AUDIT-03** — Conservation re-proof:
  - **Degenerette payout flow conservation:** per-N table calibration math algebraically verified to hold `basePayoutEV = 100 centi-x ± rounding`; ETH bonus EV = exactly 5.000% per N; per-N hero EV-neutrality holds within `P(hero|M,N) × boost(M,N) + (1-P) × HERO_PENALTY ≈ HERO_SCALE` 0.05% tolerance per Phase 268 STAT-01 + STAT-03
  - **Solvency invariant:** `claimablePool ≤ ETH balance + stETH balance` PRESERVED. Degenerette payout-recalibration touches per-quadrant payout schedule only — no ETH/stETH balance mutations beyond existing `_distributePayout` mechanics; PAY-SPLIT 3-tier rule is intra-`_distributePayout` redistribution between ethShare and lootboxShare, total sum invariant
  - **No new mint sites:** `coinflip.creditFlip` + lootbox crediting paths byte-identical; Degenerette path uses pre-existing `mintForGame` route only
  - **BURNIE / lootbox conservation:** `ethShare + lootboxShare = payout` invariant (PAY-SPLIT-02 floor + PAY-SPLIT-03 pool-cap-flip preserve)

- **AUDIT-04** — Zero-new-state scan attests:
  - Zero new storage slots (existing storage layout byte-identical at v37.0 closure HEAD vs v36.0 baseline `1c0f0913`; slot-by-slot grep proof)
  - Zero new public/external mutation entry points
  - Zero new external pure entry points (`packedTraitsDegenerette` is `internal pure` library helper, inlined into the consumer at compile time — does NOT widen the public ABI)
  - Zero new admin functions
  - Zero new modifiers
  - Zero new upgrade hooks

- **AUDIT-05** — `audit/FINDINGS-v37.0.md` published as milestone deliverable; FINAL READ-only at v37.0 closure HEAD; closure signal `MILESTONE_V37_AT_HEAD_<sha>` emitted in §9c; KNOWN-ISSUES.md walkthrough records the disposition explicitly (default zero-promotion path per D-262-KI-01 carry; deviation requires user disposition).

- **AUDIT-06** — Adversarial pass via `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL after full §4 draft per D-271-ADVERSARIAL-01 (extends D-NN-ADVERSARIAL-02 carry with `/economic-analyst` addition). Real captured output logged in `271-NN-ADVERSARIAL-LOG.md`; any surfaced novel-composition surfaces folded into §4 prose or §3.A finding blocks per user disposition. `/degen-skeptic` explicitly DEFERRED per D-271-ADVERSARIAL-02 (pre-launch posture mutes practitioner-burned angle; mechanism-design content covered by `/economic-analyst`).

- **REG-01..04** — Regression appendix:
  - **REG-01** v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f0913` non-widening at v37.0 HEAD. `EntropyLib` byte-identical (`hash2` + `entropyStep` bodies UNCHANGED); `_rollTargetLevel` / `_resolveLootboxRoll` / `_lootboxTicketCount` v36.0-refactored bodies byte-identical EXCEPT for LBX-01 dead-branch deletion (no-behavior-change cleanup, audit-trail row at AUDIT-01 §3.A; bit-slice budget UNAFFECTED).
  - **REG-02** v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` non-widening at v37.0 HEAD. `_pickSoloQuadrant` injection sites + `JackpotBucketLib` + `weightedColorBucket` byte-identical. Degenerette path uses NEW `packedTraitsDegenerette`; gold-solo Mint/Jackpot path uses unchanged `packedTraitsFromSeed`; **surfaces strictly disjoint**, no widening.
  - **REG-03** KI envelopes EXC-01..04 RE_VERIFIED:
    - **EXC-01..03** NEGATIVE-scope at v37 (Degenerette + lootbox-cleanup + post-v32 commits have zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction) — Phase 270 contributes 4 RE_VERIFIED-NEGATIVE-scope rows ready to drop into §6b
    - **EXC-04** RE_VERIFIED with NARROWS retained from v36.0 (BAF-jackpot-only scope unchanged)
  - **REG-04** prior-finding spot-check sweep across `audit/FINDINGS-v25..v36.0.md` for findings referencing the v37-touched function set: `DegenerusGameDegeneretteModule` (`_evNormalizationRatio`, `_getBasePayoutBps`, `_applyHeroMultiplier`, `_wwxrpBonusRoiForBucket`, `_distributePayout`), `DegenerusTraitUtils.packedTraitsFromSeed`, `DegenerusGameLootboxModule._resolveLootboxRoll`, presale-flag handling, `setDecimatorAutoRebuy`. Default expectation: ALL rows PASS. SUPERSEDED rows allowed with explicit successor cite (e.g., F-25-NN normalization-related rows replaced by 5-table design).

**Pre-decided / locked from prior phases (carry-forward — no re-discussion):**

- **9-section deliverable shape** — v25 → v36 carry-forward via D-253-15 / D-257-CF / D-262-CF / D-265-CF / D-266-CF chain. §1 Frontmatter / §2 Executive Summary / §3 Per-Phase Sections / §4 F-37-NN Finding Blocks (default zero) / §5 Regression Appendix / §6 KI Gating Walk + Non-Promotion Ledger / §7 Prior-Artifact Cross-Cites / §8 Forward-Cite Closure / §9 Milestone Closure Attestation.
- **D-08 5-Bucket Severity Rubric** — CRITICAL / HIGH / MEDIUM / LOW / INFO carry-forward from v25 onward.
- **D-09 3-Predicate KI Gating Rubric** — accepted-design + non-exploitable + sticky carry-forward.
- **Severity ceiling for any v37-emitted F-37-NN: HIGH** — no value extraction beyond per-N table-dispatch math; equal-EV invariant satisfied within statistical tolerance per Phase 268 STAT-01; PAY-SPLIT 3-tier rule preserves total-payout invariant; lootbox dead-branch removal is structurally byte-equivalent. MOST LIKELY bucket for any v37 F-37-NN: MEDIUM/LOW.
- **Skip research-agent dispatch** per `feedback_skip_research_test_phases.md` — phase is comprehensive but documented; AUDIT methodology fully specified by ROADMAP + REQUIREMENTS + Phase 257/262/265/266 precedents. Plan directly. Mirrors prior terminal-phase mechanical posture.
- **Pure-consolidation phase** — ZERO `contracts/` writes by agent + ZERO `test/` writes by agent (carry-forward from Phase 253 D-253-CF-04 / Phase 257 D-257 / Phase 262 D-262-APPROVAL-02 / Phase 265 D-265-APPROVAL-02). All writes confined to `.planning/phases/271-*/` + `audit/FINDINGS-v37.0.md` + KNOWN-ISSUES.md (only if D-09 PASS-promoted, default zero) + ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flips.
- **Atomic-commit per task** — single-plan multi-task pattern (Phase 253 / 257 / 262 / 265 / 266 carry). Each task = one commit with `audit(271):` or `docs(271):` prefix; READ-only flip is the terminal commit.
- **Forward-cite zero-emission** — terminal-phase invariant per Phase 257 D-257-FCITE-01 / Phase 253 D-253-09 / Phase 262 D-262-FCITE-01 / Phase 265 D-265-FCITE-01 carry. §8 grep-recipe verifies zero forward-cite emission across Phase 267-270 plan/summary/context artifacts; zero forward-cites emitted from Phase 271 to v38.0+ phases.
- **§9.NN format: THREE subsections** — i USER-APPROVED contracts + ii USER-APPROVED tests + iii AGENT-COMMITTED audit + planning artifacts; NO awaiting-approval subsection (all v37 contract + test commits already landed under user-approved batched review). Plus NEW iv subsection for v38+ carry-forward items per D-271-DEFERRED-02 (extends v34/v35/v36 §9.NN format with deferred-items register).
- **HEAD anchor for closure signal** — current HEAD `71e7633c` (post-Phase-270 close docs commit; source-tree HEAD `8fd5c2e1` unchanged). If Phase 271 plan-close adds further commits to HEAD before signal-emission, signal SHA updates to that mutation-inclusive HEAD per Phase 257 D-257-CLOSURE-01 / Phase 262 D-262-CLOSURE-01 / Phase 265 D-265-CLOSURE-01 / Phase 266 D-266-CLOSURE-01 carry. Docs-tree HEAD captured separately in attestation `git rev-parse HEAD` block.
- **Write policy** — `audit/FINDINGS-v37.0.md` writeable freely during plan execution; READ-only flip on terminal-task commit per Phase 253 / 257 / 262 / 265 / 266 carry. Per `feedback_no_contract_commits.md`, ZERO `contracts/` or `test/` writes by agent in Phase 271.

**Phase 271 boundary state at close:**

- `audit/FINDINGS-v37.0.md` published as FINAL READ-only at HEAD `<sha>`.
- ROADMAP updated with closure signal `MILESTONE_V37_AT_HEAD_<sha>`.
- STATE.md updated; v37.0 milestone marked closed.
- MILESTONES.md updated with v37.0 row promoted to SHIPPED with closure signal.
- PROJECT.md "Deferred to Future Milestones" updated with the 5-item v38+ carry-forward register per D-271-DEFERRED-03.
- Zero `contracts/` writes. Zero `test/` writes by agent.
- KNOWN-ISSUES.md UNMODIFIED expected per default path (D-262-KI-01 zero-promotion carry; deviation requires user disposition during D-271-ADVERSARIAL-04 escalation).

</domain>

<decisions>
## Implementation Decisions

### Adversarial-Skill Expansion (USER-DECIDED Phase 271 discuss)

- **D-271-ADVERSARIAL-01 (skill set: 3 skills parallel after full §4 draft):** `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL pass after full §4 inline draft. Extends Phase 265 D-265-ADVERSARIAL-02 / Phase 262 D-262-ADVERSARIAL-02 / Phase 266 inline-execution carry by adding `/economic-analyst`.
  - **Why /economic-analyst added:** v37.0 is the first milestone with mechanism-design content (Degenerette payout recalibration + PAY-SPLIT 3-tier ETH split with explicit 3.0× boundary discontinuity + per-N × hero × WWXRP composition surface). `/contract-auditor` covers game-theory at the surface-Hypothesis level only; `/economic-analyst` brings the dedicated mechanism-design lens for §4 (h) PAY-SPLIT review + (g) hero × per-N composition + (a) per-N table dispatch correctness.
  - **Full §4 scope for all 3 skills:** Each skill red-teams ALL surfaces (a)-(h), not scoped subsets. Rationale: avoids blinkering /economic-analyst to a single surface; cross-surface composition issues (e.g., hero × WWXRP × per-N table interaction) span surfaces and benefit from one skill seeing the whole picture.
  - **Parallel-spawn batch (single message, 3 parallel skill invocations):** Mirror Phase 265 / Phase 262 parallel-spawn pattern. Phase 266 / Phase 270 inline-execution carry applies if subagent .md-write guard interferes — see D-271-EXEC-01.

- **D-271-ADVERSARIAL-02 (`/degen-skeptic` deferred):** `/degen-skeptic` explicitly NOT in scope for Phase 271. Rationale:
  - Pre-launch posture (no live volume, no migration concerns, no honeypot risk) mutes the practitioner-burned-by-this-pattern angle that is /degen-skeptic's design center.
  - Mechanism-design content (PAY-SPLIT boundary, equal-EV invariants, payout-multiple gaming) is covered by /economic-analyst.
  - Carry-forward default from Phase 262/265/266 = exclude /degen-skeptic.
  - Defer condition: if a future milestone surfaces post-launch incident data or community-trust concerns, /degen-skeptic becomes in-scope at that milestone's discuss-phase.

- **D-271-ADVERSARIAL-03 (timing — sequential after full §4 draft):** Phase 262 D-262-ADVERSARIAL-02 / Phase 265 D-265-ADVERSARIAL-02 carry. Plan author writes full §4 inline draft (all 8 surfaces a-h verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence). Sequential validation pass after full draft is written. Spawn `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` in parallel as a single message, ALL THREE red-teaming the FINISHED §4 draft (not re-deriving from scratch). All adversarial-pass artifacts logged in `271-01-ADVERSARIAL-LOG.md` (Phase 265 265-01-ADVERSARIAL-LOG.md format carry).

- **D-271-ADVERSARIAL-04 (disagreement disposition — escalate to user inline):** Phase 262 D-262-ADVERSARIAL-03 / Phase 265 D-265-ADVERSARIAL-03 carry, extended:
  - If any of the 3 skills flags a candidate the plan author verdicted SAFE, plan author surfaces the disagreement to the user inline in plan output.
  - If `/zero-day-hunter` surfaces a new attack surface (a 9th-surface novel composition beyond a-h), surface inline.
  - If `/economic-analyst` flags PAY-SPLIT boundary discontinuity OR per-N composition issue as candidate KI Design Decisions promotion (revisiting the §3-prose-only default per D-271-KI-01), surface inline — user decides KI promotion before deliverable READ-only flip per `feedback_wait_for_approval.md`.
  - User decides verdict + KI disposition before deliverable READ-only flip per `feedback_wait_for_approval.md`.

### Phase 269 Deferred-Items Disposition (USER-DECIDED Phase 271 discuss)

- **D-271-DEFERRED-01 (LBX-03 absorbed inline at §3.A):** Phase 269 SUMMARY explicit handoff: "LBX-03 — Phase 271 author computes anchors at audit-trail-authoring time". Phase 271 §3.A delta-surface row for the LootboxModule dead-branch deletion includes:
  - Pre-LBX-01 v36.0 ENT-02 callsite line numbers: L1548 / L1569 / L1585 / L1599 (4 hash2/bit-slice callsites in `_resolveLootboxRoll` v36.0-refactored body)
  - Post-LBX-01 line numbers at v37.0 HEAD `<sha>` (planner runs `grep -nE "hash2|bit-slice" contracts/modules/DegenerusGameLootboxModule.sol` at audit-trail-authoring time; line numbers shift downward by ~14 LOC after dead-branch removal)
  - Bit-slice budget UNAFFECTED attestation (only the inner conditional was dead; the 4 hash2/bit-slice callsites survive byte-identical at the structural level)
  - Cross-cite to Phase 269 SUMMARY's "What shipped" section + `8fd5c2e1` commit-hash anchor
  - Cascade signature change documented (drop `targetLevel` + `currentLevel` params from signature + 2 callsites + 2 NatSpec @param lines)

- **D-271-DEFERRED-02 (5 deferred items → §9.NN.iv "v38+ Carry-Forward" subsection + §3c per-phase prose):** New §9.NN.iv subsection appended to the existing §9.NN three-subsection commit-readiness register (i USER-APPROVED contracts + ii USER-APPROVED tests + iii AGENT-COMMITTED audit/planning artifacts). §9.NN.iv enumerates each deferred item with one-line v38+ rationale:
  - **LBX-02** (empirical worst-case 55%-tickets-path gas-savings test) — fixture-coverage gap; analytical worst-case in NatSpec is the load-bearing audit-trail evidence per `feedback_gas_worst_case.md` and Phase 266 GAS-01 precedent. Empirical pin requires fixture coverage of openable lootbox path which currently soft-skips in harness (matches `AdvanceGameGas.test.js` L1014/L1027 precedent). Bytecode shrink (177 bytes) confirmed empirically via direct artifact inspection at Phase 269 Task 4. Carry to v38+ maintenance phase.
  - **GASPIN-02** (stabilize Phase 261/264 SURF-05 gas-pin tests under combined `npm run test:stat` ordering) — Phase 269 RCA identified mechanism = D-269-RCA-01 option (c) fixture-loader caching (Hardhat `loadFixture` + `evm_snapshot`/`evm_revert` semantics under multi-file combined-suite ordering). D-269-STAB-01 option (b) `hardhat_reset`+`loadFixture` attempt FAILED structurally with side-effect regressions; options (a) re-pin to combined-suite values violates GASPIN-03 hard ceiling; option (c) split test files violates plan scope. Carry to v38+ maintenance phase with RCA evidence inline at `269-01-PLAN.md` for next attempt.
  - **GASPIN-03** (`npm run test:stat` runs cleanly start-to-finish in CI-equivalent fresh-checkout) — depends on GASPIN-02; carry as a paired deferral.
  - **SURF-03 re-baseline** (`DegenerusGameLootboxModule.sol` v36.0 entropy refactor surface re-baseline post-LBX-01) — one-line `test/stat/SurfaceRegression.test.js` edit when picked up; pure-consolidation hard constraint #1 prohibits Phase 271 from doing test-tree edits. Carry to v38+ maintenance phase. Note: SURF-03 in REQUIREMENTS.md table is marked Complete (Phase 268-pinned baseline at HEAD `4b277aaf`); the re-baseline carry is the post-Phase-269-LBX-01 update needed at the next test-tree-touching opportunity.
  - **STAT-03 v35.0** (`test/stat/PerPullEmptyBucketSkip.test.js` 88% sparse-fixture skip rate, failing on main since Phase 264 commit `7dcfeb0c`) — Phase 265 D-265-STAT03-01 reframed as fixture-calibration error, NOT a finding (deity-backed dense fixture proves helper correctness); v37.0 audit surface (Degenerette + lootbox-cleanup + post-v32 commits) has zero intersection with the per-pull-level coin-jackpot path so v37.0 audit conclusion stands without revisit. Carry to v38+ maintenance phase as test-suite hygiene (retune fixture density per Phase 264 D-IMPL-07 mid/late-game spec, OR document actual production-floor rate). Note: this is v35.0 STAT-03 (the per-pull empty-bucket skip test); v37.0 STAT-03 (Hero bonus EV per-N) is a DIFFERENT requirement, marked Complete by Phase 268.

  §3c per-phase prose for Phase 269 documents the PARTIAL-ship rationale (LBX-01 + GASPIN-01 RCA shipped; rest deferred per Phase 269 SUMMARY's "What deferred to v37+ maintenance" section). §9.NN.iv is the structured single-source-of-truth lookup for the next-milestone planner.

- **D-271-DEFERRED-03 (PROJECT.md "Deferred to Future Milestones" updated with same 5 items):** Per user disposition — append to existing PROJECT.md "Deferred to Future Milestones" subsection (mirror of how v37.0 picked up post-v32.0 commits + lootbox dead-branch + SURF-05 from v36.0 close). Single-source-of-truth for next-milestone planner; loops back automatically when v38.0 milestone opens. Format matches existing v37.0-pickup entries:
  - "Lootbox empirical 55%-tickets-path gas-savings test pin (LBX-02 carry from v37.0 Phase 269) — fixture-coverage gap; analytical worst-case is load-bearing"
  - "SURF-05 gas-pin stabilization under combined `npm run test:stat` ordering (GASPIN-02/03 carry from v37.0 Phase 269) — Phase 269 RCA at `.planning/phases/269-*/269-01-PLAN.md` 'Root Cause (GASPIN-01)' section identifies fixture-loader caching mechanism"
  - "SURF-03 re-baseline post-LBX-01 (test/stat/SurfaceRegression.test.js carry from v37.0 Phase 269) — one-line edit when v38+ test-tree work resumes"
  - "PerPullEmptyBucketSkip.test.js fixture density retune (STAT-03 v35.0 carry from v35.0 Phase 264 / re-flagged v37.0 Phase 269) — deity-backed dense fixture proves helper correctness; failing test reflects sparse-fixture pre-organic-activity holder density per v35.0 Phase 265 D-265-STAT03-01 reframe; retune per Phase 264 D-IMPL-07 spec or document production-floor rate"

### File Decomposition — DEFAULT-APPLIED (single-file deliverable)

- **D-271-FILES-01 (single canonical deliverable, no intermediate working files):** Author `audit/FINDINGS-v37.0.md` directly with all 9 sections embedded. No `audit/v37-*.md` per-AUDIT-NN working files. Mirrors Phase 257 D-257-FILES-01 / Phase 262 D-262-FILES-01 / Phase 265 D-265-FILES-01 / Phase 266 D-266-FILES-01. Rationale: v37.0 has only one audit phase (Phase 271) — same shape as v33/v34/v35/v36 — so v32's per-phase working-file pattern (`audit/v32-247-DELTA.md` ... `audit/v32-252-POST31.md` → consolidate) does not apply structurally.

### F-37-NN Disclosure Posture — DEFAULT-APPLIED (zero-block expectation)

- **D-271-FIND-01 (default expectation: zero F-37-NN finding blocks):** Per Phase 262 D-262-FIND-01 / Phase 265 D-265-FIND-01 / Phase 266 D-266-FIND-01 carry-forward.
  - v37.0 Degenerette payout-recalibration is mathematically well-bounded: 5-table per-N dispatch calibrated via `Fraction`-exact derivation (`.planning/notes/degenerette-recalibration/derive_5_tables.py`); equal-EV invariant satisfied across all 16,384 player-pick configurations within statistical tolerance per Phase 268 STAT-01 (basePayoutEV = 100.00 ± 0.50 centi-x for each N ∈ {0..4}); producer chi² uniformity within Wilson-Hilferty Z<1.645 / `CHI2_CRIT_05[7]=14.067` per STAT-02; PAY-SPLIT 3-tier rule preserves total-payout invariant per STAT-07; `_countGoldQuadrants` boundary `color == 7` strict (DGN-03 design contract); symbol-only hero match preserves uniformity (DGN-07).
  - v37.0 Lootbox dead-branch removal is structurally byte-equivalent: Phase 269 caller-clamp invariant proof + bytecode shrink confirmed.
  - v37.0 post-v32.0 carry-forward declarations: Phase 270 sweep verdicted 8 of 8 surfaces SAFE_BY_STRUCTURAL_CLOSURE × 6 + SAFE_BY_DESIGN × 2; zero FINDING_CANDIDATE rows.
  - Pre-disclosed trust-asymmetry items (none expected at v37 — no admin trust boundary in Degenerette path) would route to **§4 sub-row prose**, NOT full F-37-NN finding-block format. Mirror Phase 253 D-253-FIND01-04 / Phase 257 D-257-FIND-01 / Phase 262 D-262-FIND-01 / Phase 265 D-265-FIND-01.
  - F-37-NN namespace reserved for: (i) any FINDING_CANDIDATE surfacing from inline draft + surviving validation pass, OR (ii) any /economic-analyst, /zero-day-hunter, or /contract-auditor novel-surface candidate user upgrades from "speculative" to "candidate" during D-271-ADVERSARIAL-04 disposition.
  - Severity-of-discovery ceiling: HIGH; MEDIUM/LOW likely for any inline-draft finding-candidate; INFO for documentation-only items.
  - **Default outcome:** §4 emits ZERO F-37-NN finding blocks; v37 ships with 8 SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE rows (a-h) + zero finding-candidates. KNOWN-ISSUES.md UNMODIFIED. Closure signal emits without disclosure-block content. Deviations escalate to user per D-271-ADVERSARIAL-04.

### REG-NN Scopes — DEFAULT-APPLIED (Phase 262/265/266 carry)

- **D-271-REG01-01 (REG-01 = single-row PASS for v36.0 closure signal):** v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f0913` re-verifies as NON-WIDENING at HEAD `<sha>`. v37.0 modifies `contracts/DegenerusTraitUtils.sol` (additive `packedTraitsDegenerette` only — `weightedColorBucket` + `traitFromWord` + `packedTraitsFromSeed` byte-identical), `contracts/modules/DegenerusGameDegeneretteModule.sol` (rewrite for 5-table dispatch + 3-tier ETH split), `contracts/modules/DegenerusGameLootboxModule.sol` (LBX-01 dead-branch deletion + cascade param cleanup). `EntropyLib.hash2` + `EntropyLib.entropyStep` BYTE-IDENTICAL (ENT-04 v36.0 carry preserved). `_rollTargetLevel` + `_lootboxTicketCount` + `_resolveLootboxRoll` (post-cleanup) hash2/bit-slice patterns preserved (LBX-01 deletion is dead-branch removal, not entropy-pattern change). REG-01 row format: 6-col verbatim from v32/v33/v34/v35/v36 `Row ID | Source Finding | Delta SHA | Subject Surface at HEAD <sha> | Re-Verification Evidence | Verdict`. Single PASS row covering lootbox-path entropy refactor closure-signal supersedence chain (`MILESTONE_V36_AT_HEAD_1c0f0913`); explicit LBX-01 caller-clamp byte-equivalence note inline.

- **D-271-REG02-01 (REG-02 = single-row PASS for v34.0 closure signal):** v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` re-verifies as NON-WIDENING at HEAD `<sha>`. `_pickSoloQuadrant` body + 4 ETH-distribution injection sites at L282/L349/L524/L1147 byte-identical between baseline `6b63f6d4` and HEAD `<sha>` per Phase 268 SURF-02 grep-proof. `JackpotBucketLib` + `weightedColorBucket` byte-identical. **Surfaces strictly disjoint:** Degenerette path uses NEW `packedTraitsDegenerette`; gold-solo Mint/Jackpot path uses unchanged `packedTraitsFromSeed`. REG-02 row format: 6-col matching REG-01.

- **D-271-KI-01 (REG-03 KI envelope re-verification: EXC-01..03 NEGATIVE-scope; EXC-04 RE_VERIFIED with NARROWS retained):**
  - **EXC-01** — pre-roll RNG envelope (NEGATIVE-scope at v37; Degenerette + lootbox-cleanup + post-v32 commits do not consume affiliate-roll RNG). Phase 270 contributes NEGATIVE-scope row.
  - **EXC-02** — backfill / prevrandao fallback envelope (NEGATIVE-scope at v37; AdvanceModule untouched in v37 except for Commit A `002bde55` which Phase 270 verdicted SAFE_BY_STRUCTURAL_CLOSURE). Phase 270 contributes NEGATIVE-scope row.
  - **EXC-03** — F-29-04 mid-cycle write-buffer substitution envelope (NEGATIVE-scope at v37; gameover-RNG-substitution path untouched). Phase 270 contributes NEGATIVE-scope row.
  - **EXC-04 — EntropyLib XOR-shift PRNG (RE_VERIFIED with NARROWS retained from v36.0).** Per-pull-level keccak path UNCHANGED in v37 (Degenerette path uses `packedTraitsDegenerette` which consumes high-entropy bits via `EntropyLib.hash2` + bit-slicing — not XOR-shift). EXC-04 NARROWS scope (BAF-jackpot-only after v36.0 Phase 266 lootbox-path xorshift consumption removal) carried verbatim. Phase 270 contributes RE_VERIFIED NARROWS-retained row.
  - §6 emits 4-row table with NEGATIVE-scope verdict for EXC-01..03 + RE_VERIFIED verdict for EXC-04 with NARROWS-retained note. Mirror Phase 253 §6b / Phase 257 §6b / Phase 262 §6b / Phase 265 §6b / Phase 266 §6b format.
  - §6a Non-Promotion Ledger: zero rows by default (zero F-37-NN finding blocks expected). If F-37-NN block emits during D-271-ADVERSARIAL-04 disposition, each block routes to §6a with D-09 3-predicate verdict.
  - §6c Verdict Summary: explicit closure verdict string `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED` (default path; PAY-SPLIT boundary discontinuity is §3 prose only per D-271-PAYSPLIT-01).

- **D-271-REG04-01 (REG-04 = per-finding 6-col PASS/REGRESSED/SUPERSEDED row table):** Walk every prior FINDINGS-vNN.md (v25 / v27 / v28 / v29 / v30 / v31 / v32 / v33 / v34 / v35 / v36) for any finding referencing the v37-touched function set: `DegenerusGameDegeneretteModule._evNormalizationRatio` / `_getBasePayoutBps` / `_applyHeroMultiplier` / `_wwxrpBonusRoiForBucket` / `_distributePayout`, `DegenerusTraitUtils.packedTraitsFromSeed`, `DegenerusGameLootboxModule._resolveLootboxRoll`, presale-flag handling, `setDecimatorAutoRebuy`. Per-finding row format mirrors REG-01: 6-col `Row ID | Source Finding | Delta SHA | Subject Surface at HEAD <sha> | Re-Verification Evidence | Verdict (PASS / REGRESSED / SUPERSEDED)`. Row count expected ~5-15. Default expectation: ALL rows PASS. SUPERSEDED rows allowed with explicit successor cite (e.g., F-25-NN normalization-related rows replaced by 5-table design — `_evNormalizationRatio` DELETED supersedes any prior normalization finding).

### PAY-SPLIT Boundary KI Disposition — DEFAULT-APPLIED (zero-promotion)

- **D-271-PAYSPLIT-01 (§3 prose only; default zero-KI-promotion):** PAY-SPLIT 3-tier rule's boundary discontinuity at exactly 3.0× bet (3.0× → 2.5× ETH drop at 3.01× under min-2.5× floor) documented as accepted-design via §3 prose disclosure ONLY. NO new KNOWN-ISSUES.md entry under Design Decisions. Rationale:
  - Default carry per Phase 262 D-262-KI-01 / Phase 265 D-265-KI-01 zero-promotion expectation.
  - PAY-SPLIT design is internal redistribution between ethShare and lootboxShare; total payout invariant preserved (`ethShare + lootboxShare = payout`); player receives the same total value, just in different mix.
  - Phase 268 STAT-07 empirically validates per-band frequency distribution within ±0.5% bin tolerance — boundary behavior is well-characterized.
  - Off-chain analytics impact (parallel to v35.0 AUDIT-06 indexer semantic-shift) is not present here: the ABI-emitted event is unchanged; only the on-chain `_distributePayout` math shifts.
  - Deviation condition: if `/economic-analyst` flags PAY-SPLIT boundary discontinuity as candidate KI Design Decisions promotion during D-271-ADVERSARIAL-04 escalation, user disposition decides KI promotion before READ-only flip per `feedback_wait_for_approval.md`.

### Closure Attestation (§9) — DEFAULT-APPLIED

- **D-271-CLOSURE-01 (signal SHA = HEAD at audit-pass-close commit):** Mirror v34 D-262-CLOSURE-01 / v35 D-265-CLOSURE-01 / v36 D-266-CLOSURE-01 — emit `MILESTONE_V37_AT_HEAD_<sha>` referencing the post-Phase-270 docs-tree HEAD (currently `71e7633c`); source-tree HEAD `8fd5c2e1` unchanged from Phase 269 close (Phase 270 emitted zero source-tree mutations). If any docs/audit-tree commits land during Phase 271 plan execution, signal SHA updates to that commit-inclusive HEAD per the carry-forward rule. Both HEADs captured separately in attestation `git rev-parse HEAD` block.

- **D-271-CLOSURE-02 (commit-readiness register §9.NN — FOUR subsections):** Extends v34 D-262-CLOSURE-02 / v35 D-265-CLOSURE-02 / v36 D-266-CLOSURE-02 three-subsection format with NEW iv subsection per D-271-DEFERRED-02:
  - **§9.NN.i USER-APPROVED contracts** — cites:
    - `e1136071` (Phase 267 Degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03])
    - `8fd5c2e1` (Phase 269 LBX-01 dead-branch deletion + cascade param cleanup)
  - **§9.NN.ii USER-APPROVED tests** — cites `4b277aaf` (Phase 268 Degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]) + any further test commits authored during Phase 271 (none expected per pure-consolidation hard constraint).
  - **§9.NN.iii AGENT-COMMITTED audit + planning artifacts** — cites Phase 271 plan-close commits (`audit/FINDINGS-v37.0.md` + `.planning/phases/271-*/*` + ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flips + KNOWN-ISSUES.md modifications if any). Plus all Phase 267-270 AGENT-COMMITTED docs-tree commits cited via `git log --oneline 1c0f0913..HEAD -- .planning/ audit/` at audit-pass-close time.
  - **§9.NN.iv v38+ Carry-Forward** — enumerates the 5 deferred items per D-271-DEFERRED-02 with one-line v38+ rationale each: LBX-02 / GASPIN-02 / GASPIN-03 / SURF-03 re-baseline / STAT-03 v35.0. Cross-cites PROJECT.md "Deferred to Future Milestones" entries per D-271-DEFERRED-03 (single-source-of-truth lookup for next-milestone planner).
  - **NO AWAITING-APPROVAL subsection.**

### Plan Decomposition (Claude's Discretion within Phase 262/265/266 precedent)

- **D-271-PLAN-01 (single multi-task plan vs N plans — planner final call; default single):** ROADMAP says "Plans: TBD". Phase 257 v33 + Phase 262 v34 + Phase 265 v35 + Phase 266 v36 precedent = single plan with multi-task atomic-commit ordering. Phase 271 has natural seams at 6 AUDIT-NN + 4 REG-NN + 8-surface §4 sweep + closure attestation.
  - Suggested single-plan ordering (planner final call):
    1. §1 frontmatter + §2 executive summary skeleton
    2. §3 per-phase sections covering Phases 267/268/269/270 (Phase 269 includes PARTIAL-ship rationale per D-271-DEFERRED-02; Phase 270 references the working-file appendix at canonical path per Phase 270 D-270-FILES-01)
    3. AUDIT-01 §3.A delta-surface table (Phase 267 Degenerette changes + Phase 269 LBX dead-branch deletion with LBX-03 line-anchor recording per D-271-DEFERRED-01 + Phase 270 post-v32.0 carry-forward declarations)
    4. AUDIT-04 §3 zero-new-state grep proof
    5. §4 inline 8-surface adversarial sweep draft (AUDIT-02 surfaces a-h with grep-cited evidence per row)
    6. AUDIT-06 adversarial-skill validation: `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL spawn per D-271-ADVERSARIAL-01; disagreement escalation per D-271-ADVERSARIAL-04 if any; log to `271-01-ADVERSARIAL-LOG.md`
    7. AUDIT-03 conservation re-proof embedded in §4 / §5 (per-N table calibration math + solvency invariant + no-new-mint-sites + ethShare/lootboxShare-sum invariant)
    8. §5 regression appendix (REG-01 v36.0 + REG-02 v34.0 + REG-04 prior-finding spot-check sweep)
    9. §6 KI gating walk (REG-03 KI envelope re-verification with Phase 270 4-row NEGATIVE-scope contribution + EXC-04 NARROWS-retained note + §6a Non-Promotion Ledger zero-row default + §6c verdict summary)
    10. §7 prior-artifact cross-cites (Phase 267-270 SUMMARY/CONTEXT/PLAN cites + audit/FINDINGS-v25..v36.0 cites for REG-04 spot-check)
    11. §8 forward-cite closure (zero forward-cites — terminal phase; grep recipe)
    12. §9 milestone closure attestation + closure-signal emission `MILESTONE_V37_AT_HEAD_<sha>` + §9.NN four-subsection commit-readiness register per D-271-CLOSURE-02 + KNOWN-ISSUES.md modifications if any per D-271-PAYSPLIT-01 default zero
    13. PROJECT.md "Deferred to Future Milestones" update per D-271-DEFERRED-03
    14. ROADMAP / STATE.md / MILESTONES.md / REQUIREMENTS.md flips + READ-only deliverable flip + atomic close commit
  - **Multi-plan alternative:** N plans (one per AUDIT-NN + one per REG-NN). Cleaner ownership boundaries; costs N× plan-creation overhead.
  - Planner picks based on Phase 257 / 262 / 265 / 266 single-plan-multi-task precedent unless decomposition surfaces a clear seam.

### Execution Mode (Claude's Discretion)

- **D-271-EXEC-01 (subagent-orchestrator vs inline-execution — planner picks):** Phase 257 / 262 / 265 used subagent-orchestrator; Phase 266 v36 close + Phase 270 used inline-execution due to global `.md`-write guard pattern-matching FINDINGS/SUMMARY/ADVERSARIAL-LOG filenames blocking subagent writes. Phase 271 has the same `.md`-write guard concern (`audit/FINDINGS-v37.0.md` + `271-01-ADVERSARIAL-LOG.md` + `271-01-SUMMARY.md` all match the guard).
  - **Suggested default:** Inline-execution mode (Phase 266 / Phase 270 carry). All atomic-commit tasks executed by orchestrator; adversarial-pass `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawned via Skill tool in parallel (skills load into orchestrator context for review work — no .md-write guard interference).
  - **Subagent-orchestrator alternative:** Per-task subagent dispatch via gsd-executor; cleaner separation of concerns but requires .md-write guard workaround (e.g., post-subagent orchestrator-side write or `--bypass-guards` invocation if available).
  - Planner picks at execute-phase open; carry-forward default = inline.

### Severity Rubric Reference — DEFAULT-APPLIED

- **D-271-SEV-01 (D-08 5-bucket severity rubric carry-forward):** Inherited from Phase 253 D-08 / Phase 257 D-257-SEV-01 / Phase 262 D-262-SEV-01 / Phase 265 D-265-SEV-01 / Phase 266 D-266-SEV-01 (which inherited from v25 onward). No re-derivation. Reference paragraph in §2 per v32 / v33 / v34 / v35 / v36 mirror.

### Approval & Commit Posture — DEFAULT-APPLIED

- **D-271-APPROVAL-01:** All `audit/FINDINGS-v37.0.md` + `.planning/phases/271-*/*` writes are agent-author per Phase 257 / 262 / 265 / 266 precedent. ROADMAP / STATE.md / MILESTONES.md / PROJECT.md / REQUIREMENTS.md updates land in atomic-commit-per-task chain. User reviews `audit/FINDINGS-v37.0.md` diff before any push per `feedback_manual_review_before_push.md`; READ-only flip locks the deliverable post-approval.
- **D-271-APPROVAL-02:** Zero `contracts/` or `test/` writes by agent in Phase 271 (hard constraint #1 per pure-consolidation phase). Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change — vacuous this phase since no contract changes are proposed by agent. KNOWN-ISSUES.md modification under D-271-PAYSPLIT-01 deviation path (only if /economic-analyst escalation passes user disposition) follows the same agent-author pattern as `audit/FINDINGS-v37.0.md`; PROJECT.md modification under D-271-DEFERRED-03 follows same agent-author pattern.

### Claude's Discretion

- **Plan decomposition** — D-271-PLAN-01 single-plan multi-task vs N plans. Planner picks based on Phase 257 / 262 / 265 / 266 precedent unless decomposition surfaces a clear seam.
- **Execution mode** — D-271-EXEC-01 inline-execution (Phase 266 / 270 carry default) vs subagent-orchestrator (Phase 257 / 262 / 265 precedent). Inline default given .md-write guard concerns.
- **§3 per-phase section length** — Phase 257/262/265/266 §3a..§3c had ~30-50 lines per impl/test phase. Phase 271 has 4 impl/test/maintenance/sub-audit phases (267/268/269/270). Planner picks per-phase length.
- **§4 inline-draft surface (a)..(h) row format** — concrete row shape (verdict bucket / grep recipe / line cites / prose justification). Planner picks per row; suggested format mirrors v36 §4 row-table style with one row per surface + cross-cite to Phase 268 STAT/SURF empirical evidence where applicable.
- **REG-04 row count + grep-walk presentation** — D-271-REG04-01 sets per-finding 6-col format. Planner picks whether to fold KI envelope re-verifications (REG-03) into REG-04 row table OR keep as §6b standalone subsection (Phase 257 / 262 / 265 / 266 left this open; suggested: keep §6b standalone for KI-rubric clarity).
- **Whether to commit deliverable in stages (per-section atomic commits) or one final commit at READ-only flip** — single-plan multi-task atomic-commit pattern from Phase 253 / 257 / 262 / 265 / 266 carry, but planner can pick per-section vs single-flip.
- **Cross-cite shape for Phase 268 STAT-01..07 → §4 (a)/(d)/(e)/(g)/(h) evidence** — line cite to specific test files (`test/stat/DegenerettePerNEvExactness.test.js` STAT-01, `test/stat/DegeneretteProducerChi2.test.js` STAT-02, `test/stat/DegeneretteBonusEv.test.js` STAT-03/04, `test/stat/DegenerettePerNEvExactness.test.js` STAT-07 ETH-split block). Planner picks brevity vs verbosity.
- **Cross-cite shape for Phase 270 working-file appendix → §3.A two-row commit-summary** — single-paragraph cite vs full sub-table. Phase 270 working-file is the structured input; Phase 271 §3.A absorbs as commit-summary rows + cross-cite. Planner picks.
- **§3c per-phase prose for Phase 269 PARTIAL-ship documentation** — D-271-DEFERRED-02 says "§3c per-phase prose for Phase 269 documents the PARTIAL-ship rationale". Planner picks: standalone Phase 269 paragraph in §3c, OR fold into §9.NN.iv with §3c brief mention only.
- **Whether to add `/degen-skeptic` mid-plan** — explicitly NOT in scope per D-271-ADVERSARIAL-02. Planner must NOT spawn this without a new explicit user opt-in.
- **§4 sub-row format for any trust-asymmetry items that emerge** — full F-37-NN block vs short prose disclosure; D-271-FIND-01 default says prose (not F-37-NN namespace) but planner has ~5-15 lines of prose-formatting discretion per item.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 271 Anchors

- `.planning/ROADMAP.md` §"Phase 271: Delta Audit + Findings Consolidation (Terminal)" — 5 success criteria; depends-on = Phase 267 + 268 + 269 + 270; write policy = `audit/FINDINGS-v37.0.md` writeable freely + READ-only flip on terminal-task commit; all 8 attack surfaces (a-h) explicitly enumerated; PAY-SPLIT-01..03 boundary-gaming + cap-flip-invariant call-out; closure signal `MILESTONE_V37_AT_HEAD_<sha>` target; §9.NN three-subsection commit-readiness register.
- `.planning/REQUIREMENTS.md` AUDIT-01..06 + REG-01..04 — 10 v37.0 audit requirements; spot-check function list for REG-04 (`DegenerusGameDegeneretteModule._evNormalizationRatio` / `_getBasePayoutBps` / `_applyHeroMultiplier` / `_wwxrpBonusRoiForBucket` / `_distributePayout` / `DegenerusTraitUtils.packedTraitsFromSeed` / `DegenerusGameLootboxModule._resolveLootboxRoll` / presale-flag handling / `setDecimatorAutoRebuy`).
- `.planning/STATE.md` — milestone v37.0 status; Phase 270 SHIPPED 2026-05-11 (4/4 DELTA-01..04 PASS; zero source-tree mutations; 4 RE_VERIFIED-NEGATIVE-scope KI rows feed Phase 271 §6b); v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` carry-forward context; v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` second-prior carry-forward.
- `.planning/PROJECT.md` §"Current Milestone: v37.0" — design lock + current focus + phase-decomposition narrative + "Deferred to Future Milestones" subsection (Phase 271 will append the 5 v38+ carry-forward items per D-271-DEFERRED-03).
- `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` — Seed note for v37.0 payout-recalibration content.

### v32.0 Phase 253 + v33.0 Phase 257 + v34.0 Phase 262 + v35.0 Phase 265 + v36.0 Phase 266 Precedent (deliverable shape + audit methodology)

- `audit/FINDINGS-v32.0.md` — v32.0 9-section deliverable; closure signal `MILESTONE_V32_AT_HEAD_acd88512`; severity rubric D-08 + KI gating rubric D-09; Phase 253 multi-section finding-block format (D-253-FIND01-03); REG-01 6-col + REG-02 5-col zero-row format; §6 KI gating walk format. Phase 271 deliverable mirrors this shape.
- `audit/FINDINGS-v33.0.md` — v33.0 9-section deliverable; closure signal `MILESTONE_V33_AT_HEAD_4ce3703d`; 9-of-9 §4 surfaces SAFE; zero F-33-NN; v33 §9.NN three-subsection format (USER-APPROVED contracts + USER-APPROVED tests + AGENT-COMMITTED audit artifacts).
- `audit/FINDINGS-v34.0.md` — v34.0 9-section deliverable; closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4`; 5-of-5 §4 surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-34-NN; KNOWN-ISSUES.md UNMODIFIED. Phase 271 §9.NN format extends this shape with iv subsection per D-271-DEFERRED-02.
- `audit/FINDINGS-v35.0.md` — v35.0 9-section deliverable; closure signal `MILESTONE_V35_AT_HEAD_5db8682b`; 6-of-6 §4 surfaces SAFE_BY_STRUCTURAL_CLOSURE; zero F-35-NN; KNOWN-ISSUES.md UNMODIFIED at HEAD per v35.0 Phase 265 D-265-AUDIT06-01 venue-mismatch reversal (AUDIT-06 indexer semantic-shift documented in §3c, NOT KNOWN-ISSUES.md). Closure verdict `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`.
- `audit/FINDINGS-v36.0.md` — v36.0 9-section deliverable; closure signal `MILESTONE_V36_AT_HEAD_1c0f0913`; 6-of-6 §4 surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-36-NN; KNOWN-ISSUES.md modified by 1 entry rephrase (EXC-04 NARROWS to BAF-jackpot-only; REPHRASE under D-09 Design Decisions, not new promotion). Closure verdict `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_REPHRASED (1 entry rephrased to BAF-only scope)`.
- `.planning/milestones/v34.0-phases/262-delta-audit-findings-consolidation/262-CONTEXT.md` — Phase 262 carry-forward decision chain. **Primary template for Phase 271 decision shape.** Phase 271 inherits the consolidation-phase pattern + terminal-phase forward-cite invariant + 2-skill (now 3-skill per D-271-ADVERSARIAL-01) adversarial-pass discipline.
- `.planning/milestones/v34.0-phases/262-delta-audit-findings-consolidation/262-01-PLAN.md` — Phase 262 single-plan multi-task atomic-commit ordering precedent for Phase 271 D-271-PLAN-01.
- `.planning/milestones/v35.0-phases/265-delta-audit-findings-consolidation/265-CONTEXT.md` — Phase 265 carry-forward decision chain (D-265-FILES-01 / D-265-ADVERSARIAL-01..03 / D-265-PLAN-01 / D-265-FIND-01 / D-265-REG01-01 / D-265-REG02-01 / D-265-KI-01 / D-265-REG04-01 / D-265-CLOSURE-01..02 / D-265-FCITE-01 / D-265-SEV-01 / D-265-APPROVAL-01..02 / D-265-STAT03-01..02 / D-265-AUDIT06-01). Phase 271 carries v35-precedent forward.
- `.planning/milestones/v35.0-phases/265-delta-audit-findings-consolidation/265-01-PLAN.md` — Phase 265 single-plan multi-task plan precedent.
- `.planning/milestones/v33.0-phases/257-delta-audit-findings-consolidation/257-01-ADVERSARIAL-LOG.md` — v33 adversarial-pass log format precedent for `271-01-ADVERSARIAL-LOG.md`.
- `.planning/milestones/v32.0-phases/253-findings-consolidation-lean-regression/253-CONTEXT.md` — Phase 253 carry-forward decision chain.

### Phase 267 Predecessor Artifacts (Degenerette contract changes — audit subject)

- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-CONTEXT.md` — Phase 267 locked decisions including PAY-SPLIT-01..03 boundary design + 5-table per-N dispatch + 25-constant delta + symbol-only hero match.
- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-PLAN.md` — Phase 267 plan; 4 atomic-commit tasks.
- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-SUMMARY.md` — Phase 267 SUMMARY; **byte-identity sweep + DGN-01..15 + PAY-SPLIT-01..03 PASS attestation** is the source of truth for the §3.A delta-surface row count + classification feeding Phase 271 AUDIT-01.
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — Fraction-exact derivation script for all 25 constants; cross-cited by Phase 271 AUDIT-03 conservation re-proof.

### Phase 268 Predecessor Artifacts (statistical validation + cross-surface preservation — audit cross-cite)

- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-CONTEXT.md` — Phase 268 locked decisions including STAT-07 ETH payout-split distribution validation + SURF-06 advanceGame gas-envelope preservation.
- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-PLAN.md` — Phase 268 plan; 3 tasks (Degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression).
- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-SUMMARY.md` — Phase 268 SUMMARY; **STAT-01..07 + SURF-01..06 PASS attestation** + per-test pass/fail summary. Source of truth for §4 surface (a)/(d)/(e)/(g)/(h) empirical evidence + REG-01/02 surface-preservation grep-proof results.
- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/VERIFICATION.md` — Phase 268 verifier PASS (13/13 must-haves).

### Phase 269 Predecessor Artifacts (lootbox dead-branch cleanup + GASPIN PARTIAL ship — audit subject + deferred-items source)

- `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-CONTEXT.md` — Phase 269 locked decisions including LBX-01 caller-clamp invariant + GASPIN-01 RCA scope.
- `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-01-PLAN.md` — Phase 269 plan; **`## Root Cause (GASPIN-01)` section** documents fixture-loader caching mechanism (D-269-RCA-01 option (c)). Cross-cited by Phase 271 §3c per-phase prose for Phase 269 PARTIAL-ship documentation + §9.NN.iv carry-forward rationale.
- `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-01-SUMMARY.md` — Phase 269 SUMMARY; **PARTIAL-ship rationale + 5 deferred items + LBX-03 explicit handoff to Phase 271** are the source of truth for Phase 271 D-271-DEFERRED-01..03 disposition. The "What deferred to v37+ maintenance" section enumerates each deferred item with technical rationale.

### Phase 270 Predecessor Artifacts (post-v32.0 sub-audit feeder — §3.A + §6b inputs)

- `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-CONTEXT.md` — Phase 270 locked decisions (D-270-FILES-01 / D-270-COHERENCE-01 dual-evidence shape / D-270-DEPTH-01 / D-270-FCFORMAT-01 / D-270-PLAN-01 / D-270-KI-01 / D-270-DESIGN-INTENT-METHOD-01 / D-270-ADVERSARIAL-01 pure-grep-sweep posture). Phase 271 inherits the design-intent-trace + actor-game-theory walk methodology when reviewing the Phase 270 working-file for §3.A authoring.
- `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-PLAN.md` — Phase 270 plan precedent.
- `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md` — **Phase 270 working-file appendix (canonical filename per D-270-FILES-01).** Phase 271 §3.A grep-cite anchor. Two-commit sub-audit working file with 8 surface verdicts (SAFE_BY_STRUCTURAL_CLOSURE × 6 + SAFE_BY_DESIGN × 2; zero FINDING_CANDIDATE) + 4-row KI envelope walk (RE_VERIFIED-NEGATIVE-scope × 4). Feeds directly into Phase 271 §3.A delta-surface 2-row commit-summary entries + §6b KI envelope re-verification table.
- `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-SUMMARY.md` — Phase 270 SUMMARY; per-commit verdict summary + Phase 271 hand-off attestation.
- `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-VERIFICATION.md` — Phase 270 verifier PASS.

### Live Contract State (audit subject — HEAD `<sha>`)

- `contracts/DegenerusTraitUtils.sol` (current HEAD `<sha>`, vs baseline `1c0f0913`):
  - `packedTraitsDegenerette(uint256 seed) internal pure returns (uint32)` — NEW helper (per-quadrant producer `[16,16,16,16,16,16,16,8]/120`; library `internal pure`; inlined at compile time — does NOT widen public ABI).
  - `weightedColorBucket` + `traitFromWord` + `packedTraitsFromSeed` — UNCHANGED (additive change only per DGN-14).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` (current HEAD `<sha>`, vs baseline `1c0f0913`):
  - `_evNormalizationRatio` — DELETED (L808-851 per Phase 267 commit `e1136071`).
  - `_countGoldQuadrants(uint32 ticket) private pure returns (uint8)` — NEW helper (DGN-03; counts color==7 across 4 player-pick quadrants strictly via `((ticket >> (q*8 + 3)) & 7) == 7`).
  - `_getBasePayoutBps` — REWRITTEN (5-table per-N dispatch).
  - `_applyHeroMultiplier` — REWRITTEN (symbol-only hero match + per-N hero boost dispatch).
  - `_wwxrpBonusRoiForBucket` — REWRITTEN (5-table per-N factor dispatch).
  - `_distributePayout` — REWRITTEN (3-tier ETH split rule per PAY-SPLIT-01..03; `betAmount` threaded as 5th argument; CURRENCY_BURNIE + CURRENCY_WWXRP branches UNCHANGED).
  - 25 packed constants delta (11 → 24 net).
  - 4 stale comments rewritten (L239 / L262 / L287-298 / L316).
  - L607 `packedTraitsFromSeed` callsite SWAPPED to `packedTraitsDegenerette`.
- `contracts/modules/DegenerusGameLootboxModule.sol` (current HEAD `<sha>`, vs baseline `1c0f0913`):
  - `_resolveLootboxRoll` — inner `if (targetLevel < currentLevel)` branch DELETED (L1574-1578 pre-deletion line numbers at v36.0 baseline; line numbers may shift downward by ~14 LOC at HEAD); cascade signature change drops `targetLevel` + `currentLevel` params from signature + 2 callsites + 2 NatSpec @param lines.
  - 4 hash2/bit-slice callsites in `_resolveLootboxRoll` body — byte-identical structurally (LBX-03 anchor recording at audit-trail-authoring time per D-271-DEFERRED-01); v36.0 baseline line numbers L1548 / L1569 / L1585 / L1599; HEAD line numbers determined at audit-pass-close time.
- `contracts/libraries/EntropyLib.sol` — UNCHANGED. KI EXC-04 XOR-shift envelope re-verified at REG-03 with NARROWS retained; lootbox-path consumes high-entropy keccak via `EntropyLib.hash2` + bit-slicing per v36.0 Phase 266 ENT-01..06 (byte-identical at v37.0 HEAD).
- `contracts/libraries/JackpotBucketLib.sol` — UNCHANGED. v34.0 gold-solo path byte-identical (REG-02 single-PASS-row).
- `contracts/storage/DegenerusGameStorage.sol` — UNCHANGED at v37.0 HEAD vs v36.0 baseline (`LOOTBOX_PRESALE_ETH_CAP` constant moved at Phase 270 Commit A `002bde55` predates v36.0 baseline).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — UNCHANGED at v37.0 HEAD vs v36.0 baseline (Phase 270 Commit A `002bde55` AdvanceModule cap-OR arm DELETED predates v36.0 baseline).
- `contracts/modules/DegenerusGameMintModule.sol` — UNCHANGED at v37.0 HEAD vs v36.0 baseline (Phase 270 Commit A `002bde55` MintModule inlined SLOAD/mask/SSTORE predates v36.0 baseline).
- `contracts/DegenerusVault.sol` — UNCHANGED at v37.0 HEAD vs v36.0 baseline (Phase 270 Commit B `2713ce61` vault wrapper DELETED predates v36.0 baseline).

### Test Surfaces (audit cross-cite — HEAD `<sha>`)

- `test/stat/DegenerettePerNEvExactness.test.js` (Phase 268, NEW) — STAT-01 per-N basePayoutEV exactness (≥ 1M draws per N; 100.00 ± 0.50 centi-x) + STAT-07 ETH payout-split distribution validation (3-tier rule per-band frequency). Cross-cited by §4 surface (a) per-N table dispatch correctness + (h) PAY-SPLIT 3-tier rule monotonicity.
- `test/stat/DegeneretteProducerChi2.test.js` (Phase 268, NEW) — STAT-02 producer chi² uniformity (`packedTraitsDegenerette` empirical distribution within Wilson-Hilferty Z<1.645 / `CHI2_CRIT_05[7]=14.067`; ≥ 1M samples). Cross-cited by §4 surface (d) producer byte-layout consistency.
- `test/stat/DegeneretteBonusEv.test.js` (Phase 268, NEW) — STAT-03 hero bonus EV per-N (≥ 100K draws per N; ±1%) + STAT-04 WWXRP bonus EV per-N (≥ 100K draws per N; ±1%). Cross-cited by §4 surface (b) symbol-only hero match + (e) WWXRP composition + (g) hero × per-N composition.
- `test/stat/SurfaceRegression.test.js` (Phase 268 EXTENSION) — SURF-01..04 v37.0 grep-proof against baseline `1c0f0913`. 13+ protected ranges asserted byte-identical. Cross-cited by §3 delta-surface enumeration + REG-01/02 single-PASS-row attestation. **Note:** SURF-03 baseline pinned at HEAD `4b277aaf` (Phase 268-close); post-LBX-01 re-baseline carry per D-271-DEFERRED-02 v38+ pickup.
- `test/gas/Phase268GasRegression.test.js` (Phase 268, NEW) — SURF-06 worst-case gas regression at HEAD; advanceGame per-day gas envelope ±2K vs v36.0 baseline. Cross-cited by §4 surface (h) gas-bound preservation.
- `test/gas/AdvanceGameGas.test.js` (Phase 268 EXTENSION) — `it('preserves XX% margin at v37.0 HEAD')`. Cross-cited by §3 conservation re-proof (gas-bound preservation).
- `test/gas/LootboxOpenGas.test.js` (existing Phase 266 file) — LBX-02 empirical 55%-tickets-path gas-savings test deferred per D-271-DEFERRED-02 (fixture-coverage gap).

### Memory / Feedback Governing This Phase

- `feedback_no_contract_commits.md` — explicit per-commit user approval for `contracts/` + `test/` changes. Phase 271 has zero `contracts/*.sol` writes + zero `test/` writes by agent (pure-consolidation hard constraint).
- `feedback_batch_contract_approval.md` — batch all phase edits, present one diff at the end. Vacuous this phase since no contract/test writes are proposed.
- `feedback_never_preapprove_contracts.md` — orchestrator must NOT tell agents anything is pre-approved. Vacuous this phase.
- `feedback_no_history_in_comments.md` — `audit/FINDINGS-v37.0.md` prose describes what IS, never what changed or what it used to be (semantic-shift / boundary-design disclosures describe current properties, NOT "this changed from X to Y"). PAY-SPLIT 3-tier prose follows this discipline (describe each tier's behavior, not the pre-/post-recalibration delta — except where Phase 270 design-intent-trace methodology requires landing-time evidence per Phase 270 D-270-DESIGN-INTENT-METHOD-01).
- `feedback_skip_research_test_phases.md` — skip research-agent dispatch (D-271-PLAN-01 skip; mirrors Phase 257 / 262 / 265 / 266).
- `feedback_gas_worst_case.md` — analytical worst-case derivation FIRST, then test it. Applied at Phase 268 SURF-06 + Phase 269 LBX-02 NatSpec; Phase 271 §4 surface (h) cites the theoretical worst-case derivation already landed in Phase 268 test headers; Phase 269 LBX-02 deferred to v38+ per D-271-DEFERRED-02 (analytical is load-bearing; empirical fixture-coverage gap).
- `feedback_wait_for_approval.md` — D-271-ADVERSARIAL-04 escalation rule: present any verdict-disagreement OR `/economic-analyst` PAY-SPLIT KI promotion candidate to user before deliverable READ-only flip.
- `feedback_manual_review_before_push.md` — user reviews `audit/FINDINGS-v37.0.md` diff before any push.
- `feedback_rng_backward_trace.md` — REG-03 EXC-04 RE_VERIFIED uses backward-trace methodology cited inline; Degenerette path `packedTraitsDegenerette` consumes VRF-derived high-entropy keccak bits (NOT XOR-shift output) — backward-trace per memory.
- `feedback_rng_commitment_window.md` — Phase 271 §4 surface (a) addresses commitment-window check (player cannot bias the per-N randomWord post-commit).
- `feedback_design_intent_before_deletion.md` — Phase 270 PRIMARY governing memory; Phase 271 inherits the design-intent-trace + actor-game-theory walk evidence in §3.A delta-surface rows for Phase 270 carry-forward declarations + Phase 269 LBX-01 dead-branch deletion (caller-clamp triple-defense rationale).

### Prior-Phase Context (carry-forward for milestone narrative)

- `.planning/MILESTONES.md` — v25.0 / v27.0 / ... / v36.0 closure-signal chain; v37.0 in-progress (will flip to SHIPPED with closure signal `MILESTONE_V37_AT_HEAD_<sha>` at Phase 271 close).
- `.planning/RETROSPECTIVE.md` — milestone-level retrospectives.
- `audit/FINDINGS-v25.0.md` through `audit/FINDINGS-v36.0.md` — REG-04 spot-check sweep targets.

### Active KI Envelope

- `KNOWN-ISSUES.md` — current state at HEAD `<sha>` (modified by 1 entry rephrase at v36.0 close — EXC-04 XOR-shift NARROWED to BAF-jackpot-only). EXC-01..04 envelopes targeted by REG-03; default Phase 271 zero-modification path per D-271-PAYSPLIT-01 + D-271-KI-01. Deviation only if `/economic-analyst` D-271-ADVERSARIAL-04 escalation passes user disposition.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (audit working-draft prose / format infrastructure)

- **9-section template prose** — copy structural skeleton from `audit/FINDINGS-v36.0.md` §1-§9 (most recent precedent). Substitute v36→v37 milestone identifiers, v36→v37 closure-signal SHAs, v36→v37 phase IDs.
- **§4 row-table format** — copy from v36.0 §4 (6 surfaces a-f); extend to 8 surfaces (a-h) for v37.0. Surface (a)-(g) parallel v36.0 / v34.0 carries; surface (h) PAY-SPLIT 3-tier rule + boundary-gaming check is v37.0 NEW.
- **§6 KI gating walk format** — copy from v36.0 §6a/§6b/§6c three-subsection format (Non-Promotion Ledger / KI envelope re-verification with EXC-04 NARROWS row / Verdict Summary). Phase 270 contributes 4 NEGATIVE-scope rows ready to drop into §6b.
- **REG-01..04 6-col row format** — copy from v36.0 §5 regression appendix.
- **§9.NN three-subsection format** — copy from v36.0 §9 (USER-APPROVED contracts + USER-APPROVED tests + AGENT-COMMITTED audit artifacts; NO awaiting-approval subsection); extend with NEW iv subsection per D-271-DEFERRED-02 (v38+ Carry-Forward register).
- **Closure-signal emission paragraph** — copy from v36.0 §9c; substitute `MILESTONE_V36` → `MILESTONE_V37` and HEAD SHA.
- **Phase 270 working-file appendix** — `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md` provides the post-v32.0 carry-forward declarations directly. Phase 271 §3.A absorbs as 2-row commit-summary entries + cross-cite to the working-file canonical path; Phase 271 §6b absorbs the 4-row KI envelope walk verbatim.

### Established Patterns

- **Pure-consolidation phase discipline** — Phase 257 / 262 / 265 / 266 all confined writes to `audit/FINDINGS-vNN.md` + `.planning/phases/{N}-*/*` + ROADMAP/STATE/MILESTONES flips. Zero `contracts/` or `test/` writes by agent. Phase 271 inherits.
- **Atomic-commit per task** — Phase 257 / 262 / 265 / 266 single-plan multi-task pattern. Each task = one commit. READ-only flip is the terminal commit (typically a chmod or `audit/FINDINGS-vNN.md` final-content commit).
- **Adversarial-pass logging** — Phase 257 / 262 / 265 wrote `{padded_phase}-01-ADVERSARIAL-LOG.md` capturing full red-team output from `/contract-auditor` + `/zero-day-hunter` parallel-spawn. Phase 266 / Phase 270 used inline-execution for the same logging shape. Phase 271 mirrors via `271-01-ADVERSARIAL-LOG.md` with 3-skill batch (`/economic-analyst` added per D-271-ADVERSARIAL-01).
- **Forward-cite zero-emission** — terminal-phase invariant. §8 grep-recipe verifies zero forward-cite emission across phase artifacts.
- **Single-source-of-truth deferred-items register** — D-271-DEFERRED-02 + D-271-DEFERRED-03 establish §9.NN.iv FINDINGS register + PROJECT.md "Deferred to Future Milestones" subsection as parallel single-source-of-truth lookups for next-milestone planner. Mirrors how v37.0 picked up post-v32.0 commits + lootbox dead-branch + SURF-05 from v36.0 close.

### Integration Points

- **`audit/FINDINGS-v37.0.md`** — sole canonical deliverable (single-file per D-271-FILES-01). Lives in `audit/` directory alongside FINDINGS-v25.0..v36.0.
- **`KNOWN-ISSUES.md`** — UNMODIFIED expected per default path (D-271-PAYSPLIT-01 zero-promotion; D-271-KI-01 zero-promotion). Modification ONLY if D-271-ADVERSARIAL-04 escalation passes user disposition for /economic-analyst PAY-SPLIT KI promotion candidate (deviation requires explicit user approval before READ-only flip).
- **`ROADMAP.md`** — closure-signal emission paragraph updated; v37.0 section flipped to COMPLETE; closure-signal `MILESTONE_V37_AT_HEAD_<sha>` recorded; Phase 271 row PROGRESS table updated to 1/1.
- **`MILESTONES.md`** — v37.0 entry flipped from IN-PROGRESS to SHIPPED with closure-signal recorded; full phase-rollup populated.
- **`STATE.md`** — milestone v37.0 marked closed; current focus shifts to between-milestones state per gsd workflow.
- **`PROJECT.md`** — current milestone block flipped to "Last shipped"; "Deferred to Future Milestones" subsection appended with 5 v38+ carry-forward items per D-271-DEFERRED-03; "Active milestone" set to NULL or v38.0-pending.
- **`REQUIREMENTS.md`** — AUDIT-01..06 + REG-01..04 status flip Pending → PASS at Phase 271 close; LBX-02 + GASPIN-02 + GASPIN-03 status flip Pending → DEFERRED (or DEFERRED-V38+) per D-271-DEFERRED-02; archived to `.planning/milestones/v37.0-REQUIREMENTS.md` at milestone close.
- **`.planning/phases/271-delta-audit-findings-consolidation-terminal/`** — phase artifacts: 271-CONTEXT.md (this file), 271-DISCUSSION-LOG.md (sibling), 271-01-PLAN.md (planner output), 271-01-SUMMARY.md (executor output), 271-01-ADVERSARIAL-LOG.md (executor output).

</code_context>

<specifics>
## Specific Ideas

### §4 Surface (h) PAY-SPLIT 3-tier rule prose sketch

```
Surface (h): ETH payout split-rule monotonicity + boundary-gaming check

Verdict: SAFE_BY_DESIGN (with /economic-analyst escalation hook per D-271-ADVERSARIAL-04)

Evidence:
- PAY-SPLIT-01 (≤3× bet → 100% ETH): _distributePayout L<post-Phase-267-line> branch
  guards `payout <= 3 * betAmount` strictly inclusive at exactly 3.0×. No off-by-one
  (≤ vs <) ambiguity per Phase 267 D-PAY-SPLIT-01 design contract.
- PAY-SPLIT-02 (3× < payout ≤ 10× → 2.5× bet ETH floor + remainder lootbox):
  `ethShare = max(2.5 * betAmount, payout / 4)` evaluated at L<line>.
  Boundary discontinuity at exactly 3.0× bet documented as ACCEPTED-DESIGN:
  player at payout = 3.0× bet receives 3.0× bet ETH (PAY-SPLIT-01 path);
  player at payout = 3.01× bet receives 2.5× bet ETH + 0.51× bet lootbox
  (PAY-SPLIT-02 path); 0.5× bet ETH-share drop at the 3.0× → 3.01× transition.
  Total payout invariant preserved (`ethShare + lootboxShare = payout`).
- PAY-SPLIT-03 (pool-cap precedence): if computed `ethShare > 10% × futurePool`,
  excess flips to lootbox per existing L716-723 logic. Verified to compose
  correctly with PAY-SPLIT-01/02 (pool cap takes precedence over small-payout
  passthrough AND 2.5× floor). NatSpec on _distributePayout documents the
  precedence rule per Phase 267 DGN-13 stale-comments rewrite.
- Empirical evidence: Phase 268 STAT-07 (`test/stat/DegenerettePerNEvExactness.test.js`
  describe("ETH payout split rule")) validates per-band frequency match within
  ±0.5% bin tolerance for the 3-tier split across all per-N basePayout × roiBps
  distributions; pool-cap excess-flip path tested separately under thin-pool fixture.
- Composition with hero × WWXRP: hero boost + WWXRP factor table dispatch
  applies BEFORE _distributePayout receives the final payout amount; the 3-tier
  split rule sees the post-hero-post-WWXRP amount; no double-counting (cross-cite
  surface (e) WWXRP composition + (g) hero × per-N composition).

Boundary-gaming analysis:
- Player CANNOT control the payout amount post-VRF-fulfillment (payout is a
  deterministic function of (player picks, VRF-derived match count, hero,
  WWXRP-bonus) — all inputs committed before VRF reveal).
- Player CAN choose betAmount and currency, but the 3-tier split is
  structurally bounded by the payout-multiple distribution; no actor can
  precisely target the 3.0× boundary because the player-side parameter is
  betAmount, not payout-multiple.
- Pool-cap precedence (PAY-SPLIT-03) ensures protocol solvency dominates
  payout-shape preferences; thin-pool conditions cap-flip excess to lootbox
  preserving claimablePool ceiling.
```

### §3.A delta-surface row sketch for LBX-01 (with LBX-03 anchor)

```
Row: contracts/modules/DegenerusGameLootboxModule.sol — _resolveLootboxRoll
     dead-branch deletion + cascade signature cleanup

Commit:    8fd5c2e1 (Phase 269)
Class:     DELETED (inner BURNIE-conversion branch) + REFACTOR_ONLY
           (cascade signature parameter removal)
File:      contracts/modules/DegenerusGameLootboxModule.sol
Lines:     L1574-1578 deletion (pre-deletion line numbers at v36.0 baseline)
           Cascade: signature L<post-LBX-01-line> + 2 callsites + 2 NatSpec @param

Evidence (v37.0 HEAD invariant cite per Phase 270 D-270-COHERENCE-01 inheritance):
- Caller-clamp triple-defense at HEAD <sha> (D-271-DEFERRED-01):
  Layer-1 openLootBox L<HEAD-line> unconditionally clamps targetLevel = max(targetLevel, currentLevel)
  Layer-2 _resolveLootboxCommon L<HEAD-line> unconditionally clamps targetLevel = max(targetLevel, currentLevel)
  Layer-3 (DELETED) inner _resolveLootboxRoll branch — was structurally dead
- Bytecode shrink: 177 bytes (18,330 → 18,153) measured at Phase 269 Task 4
  via direct artifact inspection.
- Per-open runtime savings: theoretical 20-50 gas on the 55%-tickets-path
  (~55% of opens); ~0.005% of typical 600K-1M-gas lootbox open. Empirical pin
  DEFERRED to v38+ maintenance per D-271-DEFERRED-02 (LBX-02 fixture-coverage gap;
  analytical worst-case in NatSpec is load-bearing).
- LBX-03 audit-trail: v36.0 ENT-02 callsite numbering at HEAD <sha>:
  4 hash2/bit-slice callsites in _resolveLootboxRoll body survive byte-identical
  at the structural level. v36.0 baseline line numbers L1548 / L1569 / L1585 / L1599;
  HEAD line numbers L<post-LBX-01-line-1> / L<-2> / L<-3> / L<-4> (line numbers shift
  downward by ~14 LOC after dead-branch removal). Bit-slice budget UNAFFECTED.

Verdict: SAFE_BY_STRUCTURAL_CLOSURE (caller-clamp invariant proves byte-equivalence)
```

### §6b KI envelope re-verification table sketch (Phase 270 4-row contribution)

```
| EXC | Surface | v37.0 Disposition | Evidence |
|---|---|---|---|
| EXC-01 | Affiliate roll RNG | RE_VERIFIED-NEGATIVE-scope | Phase 270 grep recipe: neither 002bde55 nor 2713ce61 touches affiliate-roll path; Degenerette + LBX-01 + Phase 270 commits zero affiliate-roll interaction. (Cross-cite Phase 270 270-01-DELTA-SURFACE.md KI walk row 1.) |
| EXC-02 | Backfill / prevrandao fallback | RE_VERIFIED-NEGATIVE-scope | Phase 270 grep recipe: AdvanceModule untouched in v37 except for 002bde55 SAFE_BY_STRUCTURAL_CLOSURE Phase 270 verdict. (Cross-cite row 2.) |
| EXC-03 | F-29-04 mid-cycle write-buffer substitution | RE_VERIFIED-NEGATIVE-scope | Phase 270 grep recipe: gameover-RNG-substitution path untouched. (Cross-cite row 3.) |
| EXC-04 | EntropyLib XOR-shift PRNG (BAF-jackpot-only at v36) | RE_VERIFIED with NARROWS retained | EntropyLib byte-identical at v37.0 HEAD vs v36.0 baseline; per-pull-level keccak path UNCHANGED in v37; lootbox-path consumes high-entropy keccak via EntropyLib.hash2 + bit-slicing per v36.0 ENT-01..06 (byte-identical). NARROWS scope (BAF-jackpot-only) carried verbatim from v36 AUDIT-05. (Cross-cite row 4.) |
```

### §9.NN.iv "v38+ Carry-Forward" subsection sketch

```
### 9.NN.iv. v38+ Carry-Forward Items

Five items deferred to v38+ maintenance milestone (cross-cite PROJECT.md "Deferred to Future Milestones" for next-milestone planner pickup):

| Item | Source Phase | Rationale | v38+ Pickup Path |
|---|---|---|---|
| LBX-02 | Phase 269 | Fixture-coverage gap; analytical worst-case in NatSpec is load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. Bytecode shrink (177 bytes) confirmed empirically at Phase 269 Task 4. | Add empirical 55%-tickets-path gas-savings test once fixture provides reliable coverage of openable lootbox path (matches AdvanceGameGas.test.js L1014/L1027 precedent). |
| GASPIN-02 | Phase 269 | RCA at `269-01-PLAN.md` "Root Cause (GASPIN-01)" identifies fixture-loader caching mechanism (Hardhat `loadFixture` + `evm_snapshot`/`evm_revert` semantics). D-269-STAB-01 option (b) attempt FAILED structurally with side-effect regressions; (a)/(c) violate GASPIN-03 or plan scope. | Re-attempt option (b) with refined `hardhat_reset` sequencing, OR pursue option (d) test-isolation via dedicated mocha config, OR widen tolerance ceiling (last resort). |
| GASPIN-03 | Phase 269 | Depends on GASPIN-02. | Verify clean `npm run test:stat` start-to-finish in CI-equivalent fresh-checkout. |
| SURF-03 re-baseline | Phase 269 | One-line `test/stat/SurfaceRegression.test.js` edit when v38+ test-tree work resumes; pure-consolidation hard constraint #1 prohibits Phase 271 from doing test-tree edits. | Update SURF-03 baseline to post-LBX-01 HEAD; verify byte-identity at the cascade-cleaned `_resolveLootboxRoll` signature. |
| STAT-03 v35.0 carry | Phase 264 (re-flagged Phase 269) | Phase 265 D-265-STAT03-01 reframed as fixture-calibration error (deity-backed dense fixture proves helper correctness); failing test reflects sparse-fixture pre-organic-activity holder density. v37.0 audit surface zero intersection with per-pull-level coin-jackpot path. | Retune `test/stat/PerPullEmptyBucketSkip.test.js` fixture density per Phase 264 D-IMPL-07 mid/late-game holder-density spec, OR document actual production-floor rate. |
```

### §9.NN.iii AGENT-COMMITTED audit + planning artifacts sketch

```
- audit/FINDINGS-v37.0.md (this file) — agent-authored at HEAD <sha>; READ-only after Task <N>
- .planning/phases/267-degenerette-producer-5-table-payout-rewrite/* (Phase 267 artifacts; 267-CONTEXT.md, 267-01-PLAN.md, 267-01-SUMMARY.md + chore commits; SHA list via `git log --oneline 1c0f0913..HEAD -- .planning/phases/267-*`)
- .planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/* (Phase 268 artifacts; SHA list)
- .planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/* (Phase 269 artifacts; SHA list including 009cbde3 GASPIN-01 RCA inline)
- .planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/* (Phase 270 artifacts; SHA list including 4017b9ec working-file commit)
- .planning/phases/271-delta-audit-findings-consolidation-terminal/* (Phase 271 artifacts; SHA list at audit-pass-close time)
- ROADMAP.md / STATE.md / MILESTONES.md / PROJECT.md / REQUIREMENTS.md flips (SHA list at audit-pass-close time)
- KNOWN-ISSUES.md (default UNMODIFIED per D-271-PAYSPLIT-01; modification only if D-271-ADVERSARIAL-04 escalation passes user disposition)
```

</specifics>

<deferred>
## Deferred Ideas

### v38+ Maintenance Phase (TARGET PICKUP for the 5 §9.NN.iv items)

LBX-02 / GASPIN-02 / GASPIN-03 / SURF-03 re-baseline / STAT-03 v35.0 carry — all carried via D-271-DEFERRED-02 §9.NN.iv subsection + D-271-DEFERRED-03 PROJECT.md "Deferred to Future Milestones" subsection. Next-milestone planner reads either source and folds into v38+ scope.

### `/degen-skeptic` adversarial-skill expansion

Explicitly DEFERRED for Phase 271 per D-271-ADVERSARIAL-02. Defer condition: if a future milestone surfaces post-launch incident data, community-trust concerns, or other practitioner-burned-by-this-pattern angles, /degen-skeptic becomes in-scope at that milestone's discuss-phase.

### PAY-SPLIT KI Design Decisions promotion candidate

DEFAULT-APPLIED zero-promotion per D-271-PAYSPLIT-01. Deviation only via D-271-ADVERSARIAL-04 escalation if /economic-analyst flags PAY-SPLIT boundary discontinuity as candidate KI Design Decisions promotion. Carried as a deferred-decision (revisited only if /economic-analyst surfaces it).

### `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry)

Out of v37.0 scope per `.planning/REQUIREMENTS.md` Out of Scope table. Tracked for future milestone (v38+ candidate per the EXC-04 NARROWS-to-BAF-only entry posture).

### BURNIE-lootbox `lootboxDay = 0` fallback at `openBurnieLootBox` L623-626 (v38+ candidate; carry from Phase 269)

Carried from Phase 269 deferred-ideas. NOT a Phase 271 concern (orthogonal to v37.0 audit subject; not a lootbox-cleanup or Degenerette surface).

### `runrewardjackpots` module-misplacement (2026-04-02 stale backlog note)

Out of v37.0 scope per PROJECT.md.

### Game-over thorough hardening (`gameover-thorough-test.md`)

Out of v37.0 scope per PROJECT.md.

### TST-FILE-01 + TST-FILE-02 (v32.0 Phase 251 untracked test files)

`test/edge/LastPurchaseDayRace.test.js` + `test/edge/BackfillIdempotency.test.js` remain untracked permanently per D-253-FIND04-04. Not a v37.0 audit concern.

</deferred>

---

*Phase: 271-delta-audit-findings-consolidation-terminal*
*Context gathered: 2026-05-11*
