---
phase: 271-delta-audit-findings-consolidation-terminal
plan: 01
milestone: v37.0
milestone_name: Degenerette Recalibration + Maintenance Bundle
head_anchor: <sha>
audit_baseline: 1c0f09132d7439af9881c56fe197f81757f8164a
audit_baseline_signal: MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
deliverable: audit/FINDINGS-v37.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
write_policy: "Pure-consolidation phase per D-271-APPROVAL-02 hard constraint #1. ZERO contracts/*.sol writes by agent during Phase 271; ZERO test/ writes by agent during Phase 271. All v37.0 contract + test commits already landed under USER-APPROVED batched review at Phase 267 (e1136071), Phase 268 (4b277aaf), and Phase 269 (8fd5c2e1) close. Audit deliverable + 271-01-ADVERSARIAL-LOG + 271-01-SUMMARY + ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flips AGENT-COMMITTED atomic-per-task with audit(271): or docs(271): prefix. READ-only flip on audit/FINDINGS-v37.0.md (chmod 444 + frontmatter status FINAL — READ-ONLY + read_only: true) is the terminal commit per feedback_manual_review_before_push.md final user-review gate."
supersedes: none
status: DRAFT
read_only: false
closure_signal: MILESTONE_V37_AT_HEAD_<sha>
generated_at: 2026-05-11T08:42:52Z
---

# v37.0 Findings — Degenerette Recalibration + Maintenance Bundle

**Audit Baseline.** The audit baseline is v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` carry-forward from `audit/FINDINGS-v36.0.md` §9c). v37.0 audit subject HEAD `<sha>` (resolved at Task 14 atomic-update per D-271-CLOSURE-01). v37.0 introduces TWO contract-tree commits since the v36.0 baseline: `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]` at commit `e1136071` (USER-APPROVED Phase 267 batched commit; +231/-196 LOC across `contracts/DegenerusTraitUtils.sol` and `contracts/modules/DegenerusGameDegeneretteModule.sol`); `feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]` at commit `8fd5c2e1` (USER-APPROVED Phase 269 commit; −14/+1 LOC in `contracts/modules/DegenerusGameLootboxModule.sol`; bytecode shrink 177 bytes 18,330 → 18,153). v37.0 introduces ONE test-tree commit since the v36.0 baseline: `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]` at commit `4b277aaf` (USER-APPROVED Phase 268 batched commit; +2,277/−1 LOC across 6 files in `test/stat/` + `test/gas/`). `contracts/libraries/EntropyLib.sol` is byte-identical between v36.0 baseline `1c0f0913` and v37 HEAD (Phase 268 SURF-04 grep-proof). `contracts/modules/DegenerusGameJackpotModule.sol` is byte-identical between v36.0 baseline `1c0f0913` and v37 HEAD (Phase 268 SURF-01 + SURF-02 + SURF-04 grep-proof; non-lootbox jackpot path untouched). `contracts/modules/DegenerusGameMintModule.sol` is byte-identical between v36.0 baseline `1c0f0913` and v37 HEAD (Phase 268 SURF-01 grep-proof). `contracts/libraries/JackpotBucketLib.sol` is byte-identical between v34.0 baseline `6b63f6d4` and v37 HEAD (REG-02 carry). `_pickSoloQuadrant` body + 4 ETH-distribution injection sites at L282 / L349 / L524 / L1147 byte-identical between v34.0 baseline `6b63f6d4` and v37 HEAD (Phase 268 SURF-02 grep-proof).

**Scope.** Single canonical milestone-closure deliverable for v37.0 per D-271-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-266-FILES-01 / D-265-FILES-01 / D-262 / D-257 carry-forward (9-section shape locked). v37.0 = 5-phase milestone shape per CONTEXT.md `<domain>`: Phase 267 (Degenerette producer + payout rewrite — contract impl), Phase 268 (statistical validation + cross-surface preservation — test impl), Phase 269 (lootbox dead-branch cleanup + SURF-05 gas-pin re-pinning — PARTIAL ship), Phase 270 (post-v32.0 deferred-commit adversarial sub-audit — zero source-tree mutations), Phase 271 (delta audit + findings consolidation — terminal). Terminal phase per D-271-FCITE-01 (carry of D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule) — zero forward-cites emitted from Phase 271 to any post-v37.0 milestone phases. Verified at §8 Forward-Cite Closure block.

**Write policy.** READ-only after Task 14 terminal atomic commit per D-271-APPROVAL-02 hard constraint #1 + D-266-APPROVAL-01 / D-265-CF-02 / D-262 / D-257 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at v37 close per D-271-PAYSPLIT-01 + D-271-KI-01 default zero-promotion path: PAY-SPLIT 3-tier rule boundary discontinuity at exactly 3.0× bet is documented as accepted-design via §4 surface (h) prose disclosure ONLY; no new KNOWN-ISSUES.md entry under Design Decisions. Zero F-37-NN finding blocks per D-271-FIND-01 carry default path (AUDIT-02 8-surface adversarial sweep verdicts SAFE_*). Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — all v37 contract + test commits already landed under USER-APPROVED batched gates at Phase 267 (`e1136071`) + Phase 268 (`4b277aaf`) + Phase 269 (`8fd5c2e1`) close per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md`. Per `feedback_manual_review_before_push.md`, the user reviews this deliverable's full diff before any push — final user-review gate at Task 14 before READ-only flip on `audit/FINDINGS-v37.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: TBD-by-Task-3 (§3.A delta-surface table covering all source-tree changes 1c0f0913 → v37 HEAD with hunk-level evidence + {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification per row)
- AUDIT-02: TBD-by-Task-5+6 (§4 8-surface adversarial sweep (a)..(h) with verdict bucket per row; default zero F-37-NN finding blocks per D-271-FIND-01; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass per D-271-ADVERSARIAL-01)
- AUDIT-03: TBD-by-Task-7 (§3 AUDIT-03 conservation re-proof: per-N table calibration math + ETH bonus EV + per-N hero EV-neutrality + solvency invariant + ethShare/lootboxShare sum invariant)
- AUDIT-04: TBD-by-Task-4 (§3 AUDIT-04 zero-new-state grep-proof attestation: zero new storage slots; zero new public/external mutation entry points; zero new admin functions; zero new modifiers; zero new upgrade hooks; `packedTraitsDegenerette` internal pure callout per DGN-15)
- AUDIT-05: TBD-by-Task-12 (§9c emits closure signal `MILESTONE_V37_AT_HEAD_<sha>` verbatim in 5 locations per D-271-CLOSURE-01; KNOWN-ISSUES.md UNMODIFIED per default path)
- AUDIT-06: TBD-by-Task-6 (`271-01-ADVERSARIAL-LOG.md` populated with 3 H2 sections — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` — per D-271-ADVERSARIAL-01; NOT `/degen-skeptic` per D-271-ADVERSARIAL-02)
- REG-01: TBD-by-Task-8 (§5a — v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f0913` NON-WIDENING at v37 HEAD per D-271-REG01-01)
- REG-02: TBD-by-Task-8 (§5b — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` NON-WIDENING at v37 HEAD per D-271-REG02-01)
- REG-03: TBD-by-Task-9 (§6b 4-row KI envelope re-verifications EXC-01..03 NEGATIVE-scope + EXC-04 RE_VERIFIED with NARROWS retained from v36.0; Phase 270 contributes 4 rows verbatim per D-271-KI-01)
- REG-04: TBD-by-Task-8 (§5c per-finding 6-col PASS/REGRESSED/SUPERSEDED row table walking audit/FINDINGS-v25.0.md → audit/FINDINGS-v36.0.md per D-271-REG04-01)
- Combined milestone closure: `MILESTONE_V37_AT_HEAD_<sha>`

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-37-NN: 0

Default expected per D-271-FIND-01 carry. The Degenerette producer + 5-table payout rewrite is mathematically well-bounded: per-quadrant producer `packedTraitsDegenerette` consumes VRF-derived high-entropy keccak bits via a `[16,16,16,16,16,16,16,8]/120` weight distribution (commons 13.33% each, gold 6.67%; uniform symbol 1/8 — player cannot bias post-VRF-fulfillment per `feedback_rng_commitment_window.md` + `feedback_rng_backward_trace.md`); 5-table per-N basePayout dispatch is `Fraction`-exact calibrated via `.planning/notes/degenerette-recalibration/derive_5_tables.py` and yields `basePayoutEV = 100 centi-x` per N ∈ {0..4} (Phase 268 STAT-01 ≥1M draws empirically validates 100.00 ± 0.50 centi-x per N); chi² uniformity empirically verified at Phase 268 STAT-02 over the 8-symbol × 8-color trait space (Wilson-Hilferty Z < 1.645); 3-tier ETH split (PAY-SPLIT-01..03) preserves `ethShare + lootboxShare = payout` invariant at every tier with PAY-SPLIT-03 pool-cap precedence enforcing `claimablePool ≤ 10% × futurePool`; cross-surface byte-identity preserved at Phase 268 SURF-01..04 (EntropyLib + BAF + MintModule + non-lootbox JackpotModule UNCHANGED vs v36.0 baseline); Phase 269 LBX-01 dead-branch removal is structurally provable byte-equivalent via caller-clamp triple-defense (Layer-1 `openLootBox` + Layer-2 `_resolveLootboxCommon` + Layer-3 (DELETED) inner branch); bytecode shrink 177 bytes confirms no-behavior-change cleanup. Severity ceiling for any v37-emitted F-37-NN: HIGH (no value extraction beyond the existing Degenerette prize space; `ethShare + lootboxShare = payout` invariant under the same total-payout mechanics as pre-recalibration; per-N table calibration analytically exact). Most likely severity for any inline-draft finding-candidate: MEDIUM/LOW. Severity counts reconcile to §4 F-37-NN block tally line by line per ROADMAP success criterion 1.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25–v36 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward (D-271-SEV-01 carry).

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-37-NN that may surface during §4 adversarial-pass disposition: HIGH ceiling (per-N table dispatch does not extract value; bucket-share-sum × pool invariant under the same total-payout mechanics as pre-recalibration; `ethShare + lootboxShare = payout` invariant preserved; per-pull entropy VRF-derived not player-controllable). MEDIUM/LOW likely for any inline-draft finding-candidate. INFO for documentation-only items. Per D-271-FIND-01 default path, zero F-37-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone: zero F-37-NN finding blocks emit (D-271-FIND-01 carry default path) → zero KI promotion candidates from new findings. KNOWN-ISSUES.md UNMODIFIED at v37 close per D-271-PAYSPLIT-01 + D-271-KI-01: the PAY-SPLIT 3-tier rule boundary discontinuity at exactly 3.0× bet is documented as accepted-design via §4 surface (h) prose disclosure ONLY (no new Design Decisions entry); total payout invariant preserved (`ethShare + lootboxShare = payout`); player receives same total value in different mix; Phase 268 STAT-07 empirically validates per-band frequency distribution. EXC-04 NARROWS retained from v36.0 (BAF-jackpot-only scope) — EntropyLib byte-identical at v37 HEAD; per-pull-level keccak path UNCHANGED in v37; lootbox-path consumes high-entropy keccak via `EntropyLib.hash2` + bit-slicing per v36.0 ENT-01..06. See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

D-271-FCITE-01 carry of D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 271 to any post-v37.0 milestone phases. Verified at §8 Forward-Cite Closure block. v37.0 = 5-phase milestone (Phases 267-271) per CONTEXT.md `<domain>`; §9.NN.iv v38+ Carry-Forward subsection contains 5 explicit deferred-handoff items (LBX-02 + GASPIN-02 + GASPIN-03 + SURF-03 re-baseline + STAT-03 v35.0 carry) per D-271-DEFERRED-02 — these are planner handoff registers tying into next-milestone pickup via `.planning/PROJECT.md` "Deferred to Future Milestones" single-source-of-truth lookup (D-271-DEFERRED-03), NOT forward-cites to in-flight Phase 272+ work. Future milestones (v38.0+) ingest via fresh delta-extraction phase, not via forward-cite from v37 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v37.0 milestone closure via signal `MILESTONE_V37_AT_HEAD_<sha>` (resolved at Task 14 atomic-update across 5 verbatim locations per D-271-CLOSURE-01).

---

## 3. Per-Phase Sections

### 3a. Phase 267 — Degenerette Producer + 5-Table Payout Rewrite

**Commit:** `e1136071` — `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`. USER-APPROVED batched commit per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md`. Files: `contracts/DegenerusTraitUtils.sol` (additive +45 LOC) + `contracts/modules/DegenerusGameDegeneretteModule.sol` (+231 / −196 LOC).

**Requirements:** 18 of 18 PASS — DGN-01..15 + PAY-SPLIT-01..03 (Phase 267 SUMMARY.md per-REQ tally).

**What IS at v37.0 close:**

- `contracts/DegenerusTraitUtils.sol` — NEW additive helper `packedTraitsDegenerette(uint256 seed) internal pure returns (uint32)` with private `_degTrait(uint64) private pure returns (uint8)` companion. Per-quadrant near-uniform color distribution `[16,16,16,16,16,16,16,8]/120` (commons 13.33% each, gold 6.67%); uniform 1/8 symbol; byte layout `[QQ][CCC][SSS]` preserved per DGN-01 + DGN-14. The existing 3 TraitUtils functions (`weightedColorBucket`, `traitFromWord`, `packedTraitsFromSeed`) byte-identical at v36.0 baseline `1c0f0913` per Phase 268 SURF-01 grep-proof.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — 5 per-N (gold-quadrant-count) payout / hero / WWXRP table dispatch indexed by NEW `_countGoldQuadrants(uint32 ticket) private pure returns (uint8 count)` operating on the packed `uint32` ticket via `((ticket >> (q*8 + 3)) & 7) == 7` for q∈{0..3} per DGN-03 strict-color boundary.
- `_evNormalizationRatio` body L808-851 at v36.0 baseline + single call site L965-969 DELETED per DGN-02; no runtime EV correction; payout schedule fully visible in storage.
- `_getBasePayoutBps(uint256 matchCount, uint8 N)` REWRITTEN with 5-table per-N dispatch (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + `QUICK_PLAY_PAYOUT_N{0..4}_M8`); `basePayoutEV = 100 centi-x` exact per N ∈ {0..4} per Fraction-exact derivation.
- `_applyHeroMultiplier(...)` REWRITTEN symbol-only per DGN-07 via `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)` reading only bits 0-2 of the hero quadrant byte; per-N hero boost dispatch via `HERO_BOOST_N{0..4}_PACKED`. P(hero match) = 1/8 exactly. Color bits 3-5 NOT read by equality comparison.
- `_wwxrpBonusRoiForBucket(...)` REWRITTEN with 5-table per-N WWXRP factor dispatch via `WWXRP_FACTORS_N{0..4}_PACKED` per DGN-09 + DGN-10.
- `_distributePayout(player, currency, betAmount, payout, rngWord)` REWRITTEN with 5-arg signature (uint128 `betAmount` inserted between `currency` and `payout`) and 3-tier ETH split rule per PAY-SPLIT-01..03:
  - **PAY-SPLIT-01** (≤3× bet → 100% ETH): strict inclusive at exactly 3.0× bet; no off-by-one ambiguity.
  - **PAY-SPLIT-02** (3× < payout ≤ 10× bet → 2.5× bet ETH floor + remainder lootbox): `ethShare = max(2.5 * betAmount, payout / 4)`.
  - **PAY-SPLIT-03** (pool-cap precedence): `ETH_WIN_CAP_BPS = 1_000 = 10% × futurePool`; excess flips to lootbox per existing L716-723 logic.
  - `CURRENCY_BURNIE` + `CURRENCY_WWXRP` branches UNCHANGED.
  - NatSpec documents 3-tier rule + pool-cap precedence per `feedback_no_history_in_comments.md` (describes what IS).
- Packed-constants delta: 11 → 24 net (5 + 5 + 5 + 5 add = 20 NEW per-N constants; 6 v36 constants DELETED per DGN-05/06/08/10/11 — `QUICK_PLAY_BASE_PAYOUTS_PACKED`, `QUICK_PLAY_BASE_PAYOUT_8_MATCHES`, `WWXRP_BONUS_FACTOR_BUCKET5..8` block, `HERO_BOOST_PACKED`, 2 normalizer constants). The 25 packed constants are byte-identical to `.planning/notes/degenerette-recalibration/derive_5_tables.py` Fraction-exact stdout (Phase 267 Task 2 evidence: `PASS_ALL_25`).
- 4 stale comment rewrites at L239 / L262 / L287-298 / L316 per DGN-13 (per `feedback_no_history_in_comments.md` describes per-N reality at v37.0).
- Producer call site at L607 (now L629 post-rewrite) SWAPPED from `packedTraitsFromSeed` to `packedTraitsDegenerette` per DGN-12.

Cross-cite `.planning/notes/degenerette-recalibration/derive_5_tables.py` (Fraction-exact derivation source of truth). Mint + Jackpot + Lootbox + EntropyLib + JackpotBucketLib + GameStorage `git diff 1c0f0913..e1136071` empty.

### 3b. Phase 268 — Degenerette Statistical Validation + Cross-Surface Preservation

**Commit:** `4b277aaf` — `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`. USER-APPROVED batched commit per `feedback_batch_contract_approval.md`. 6 files; +2,277 / −1 LOC; 3 NEW `test/stat/` files (`DegenerettePerNEvExactness.test.js`, `DegeneretteProducerChi2.test.js`, `DegeneretteBonusEv.test.js`) + 1 EXTENDED `test/stat/SurfaceRegression.test.js` v37.0 SURF-01..04 describe + 1 NEW `test/gas/Phase268GasRegression.test.js` (SURF-05 + SURF-06) + `package.json` `test:stat` wiring.

**Requirements:** 13 of 13 PASS — STAT-01..07 + SURF-01..06 (Phase 268 SUMMARY.md per-REQ tally).

**Empirical evidence:**

- **STAT-01** (per-N basePayoutEV exactness ≥ 1M draws/N): `basePayoutEV = 100.00 ± 0.50 centi-x` for each N ∈ {0..4}; Fraction-exact 100 centi-x per N is the analytical anchor.
- **STAT-02** (per-quadrant producer chi² uniformity ≥ 1M samples): color `[16,16,16,16,16,16,16,8]/120` + uniform 1/8 symbol passes within `CHI2_CRIT_05[7] = 14.067` / Wilson-Hilferty Z<1.645 at α=0.05.
- **STAT-03** (per-N hero-boost EV ±1% at ≥ 100K hero-active draws/N): per-N hero EV within ±1% analytical reference.
- **STAT-04** (per-N WWXRP factor EV ±1% at ≥ 100K WWXRP-active draws/N): per-N WWXRP factor EV within ±1% analytical reference; 5.000% ETH bonus per N (analytical).
- **STAT-05** (per-N match-count histogram derived from STAT-01 pool): bin-tolerance ±0.5% vs analytical binomial-convolution reference.
- **STAT-06** (reuse Phase 261/264/266 chi² infrastructure): `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` verbatim re-declared in all 3 stat files; no new statistical primitives.
- **STAT-07** (ETH payout 3-tier split rule distribution + thin-pool cap-flip): per-band frequency match within ±0.5% bin tolerance across all per-N basePayout × roiBps distributions; thin-pool cap-flip sub-case via `loadFixture(deployFullProtocol)` per D-268-THINPOOL-01.
- **SURF-01..04** (byte-identity grep-proof vs v36.0 baseline `1c0f0913`): `DegenerusTraitUtils.sol` existing 3 functions byte-identical; `DegenerusGameJackpotModule.sol` file-level zero-diff; `DegenerusGameLootboxModule.sol` file-level zero-diff (D-268-SURF03-01: Phase 269 owns post-cleanup re-baseline); `EntropyLib.sol` file-level zero-diff (ENT-04 v36.0 carry).
- **SURF-05** (worst-case quickPlay gas regression): theoretical worst-case derivation FIRST in NatSpec header (N=3 + M=8 + ETH tier-3 + ticketCount=10 single construction per D-268-WORSTGAS-01) per `feedback_gas_worst_case.md`; deterministic VRF-injection test hitting exactly that state via REF-CAPTURE pin protocol for `WORST_CASE_RNG_WORDS`.
- **SURF-06** (advanceGame ±2K gas envelope): `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` pinned; v36.0 envelope active.

`git diff e1136071 4b277aaf -- contracts/` returns empty (zero source-tree mutations at Phase 268 close).

### 3c. Phase 269 — Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning (PARTIAL ship)

**Commits:**
- USER-APPROVED contract commit `8fd5c2e1` — `feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]`. 1 file (`contracts/modules/DegenerusGameLootboxModule.sol`); −14 / +1 LOC; LBX-01 dead-branch deletion + user-approved cascade param cleanup.
- AGENT-COMMITTED RCA commit `009cbde3` — `docs(269): GASPIN-01 root-cause inline — fixture-loader caching`. `269-01-PLAN.md` +80 LOC "Root Cause (GASPIN-01)" section.

**Requirements:** 2 of 6 PASS — LBX-01 + GASPIN-01. 4 DEFERRED to v38+ maintenance per D-271-DEFERRED-02 (cross-cite §9.NN.iv): LBX-02 + LBX-03 (LBX-03 now anchored at §3.A) + GASPIN-02 + GASPIN-03 + SURF-03 re-baseline.

**LBX-01 shipped at v37.0 close:**

- Inner `if (targetLevel < currentLevel) { burnieOut = ... }` branch at `_resolveLootboxRoll` L1574-1578 (v36.0 baseline line numbers) DELETED with its 4-LOC body + matching cascade signature parameter drop (the unused `targetLevel` + `currentLevel` params from the signature + 2 callsites + 2 NatSpec `@param` lines).
- **Triple-defense caller-clamp invariant** proves byte-equivalence:
  - **Layer-1** `openLootBox` L557-559 unconditionally clamps `targetLevel = max(targetLevel, currentLevel)` before invocation.
  - **Layer-2** `_resolveLootboxCommon` L882-884 unconditionally clamps again before reaching `_resolveLootboxRoll`.
  - **Layer-3** (DELETED) inner `_resolveLootboxRoll` branch was structurally dead.
- Bytecode shrink: 177 bytes (18,330 → 18,153) measured via direct artifact inspection at Phase 269 Task 4 — confirms no-behavior-change cleanup.
- Per-open runtime savings: theoretical 20-50 gas on the 55%-tickets-path (~55% of opens); ~0.005% of typical 600K-1M-gas lootbox open. The shipped value is **audit cleanliness** (dead branch removed from auditor's reading path before Phase 271), not gas optimization.
- Game-theory neutrality: ETH-lootbox `day` snapshot at buy → seed fixed → no timing-grind window per `feedback_rng_commitment_window.md` backward-trace.

**PARTIAL-ship rationale (4 deferred to v38+):**

- **LBX-02** (empirical 55%-tickets-path gas-savings test): fixture-coverage gap; analytical worst-case in NatSpec is load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. Empirical pin requires fixture coverage of openable lootbox path which currently soft-skips in the harness (matches `AdvanceGameGas.test.js` L1014/L1027 precedent). Bytecode shrink confirmed empirically at Phase 269 Task 4.
- **GASPIN-02 + GASPIN-03** (combined-suite gas-pin stabilization): D-269-STAB-01 option (b) `before(hardhat_reset)` + `loadFixture(deployFullProtocol)` attempt FAILED structurally — Hardhat-toolbox error *"There was an error reverting the snapshot of the fixture. This might be caused by using hardhat_reset and loadFixture calls in a testcase"* AND introduced more failures than it resolved (Phase 261 SURF-05 payDailyJackpot regressed PASS drift −33 → FAIL drift −47,833; Phase 264 SURF-05 stage-9 regressed soft-skip → FAIL; Phase 268 SURF-06 fixture deployment broke). Options (a)/(c) violate GASPIN-03 hard ceiling or plan scope. Combined with negligible production-gas impact of LBX-01 (sub-0.01%), GASPIN-02 effort cannot be justified within v37.0 scope. RCA evidence inline at `269-01-PLAN.md` "Root Cause (GASPIN-01)" section (option (c) fixture-loader caching mechanism — Hardhat `loadFixture` + `evm_snapshot`/`evm_revert` semantics under multi-file combined-suite ordering).
- **v36.0 acceptance carries forward verbatim:** "User accepted the flaky behavior at the Wave 2 gate (`128k is fine approved`); future re-pinning pass deferred to v37.0 maintenance scope" → now deferred further to v38+ maintenance.
- **SURF-03 re-baseline** (D-269-SURF03-01): one-line `test/stat/SurfaceRegression.test.js` edit when v38+ test-tree work resumes; pure-consolidation hard constraint #1 prohibits Phase 271 from doing test-tree edits.

### 3d. Phase 270 — Post-v32.0 Deferred-Commit Adversarial Sub-Audit (cross-cite)

**Commits:**
- AGENT-COMMITTED working-file commit `4017b9ec` — `docs(270): post-v32.0 deferred-commit adversarial sub-audit working file [DELTA-01..04]`. `270-01-DELTA-SURFACE.md` NEW (305 LOC); canonical Phase-271-§3.A grep-cite anchor per D-270-FILES-01.
- AGENT-COMMITTED phase-close commit `5cd4f2bc` — `docs(270): phase 270 summary — post-v32.0 deferred-commit adversarial sub-audit complete [DELTA-01..04 PASS]`.

**Requirements:** 4 of 4 PASS — DELTA-01..04. Zero deferred.

**Scope:** FIRST FULL adversarial coverage of two specific post-v32.0 contract-tree commits whose adversarial coverage was carry-forward-deferred v33.0 → v34.0 → v35.0 → v36.0 close:
- **Commit A** `002bde55` (`feat(presale): auto-deactivate flag on per-mint cap crossing`, 2026-05-02; +14 / −10 LOC across 3 files) — Phase 270 verdict **SAFE_BY_STRUCTURAL_CLOSURE**.
- **Commit B** `2713ce61` (`chore(vault): remove dead setDecimatorAutoRebuy wrapper`, 2026-05-05; +3 / −20 LOC across 2 files) — Phase 270 verdict **SAFE_BY_DESIGN** (admin-entry-point-removal blast radius = zero; Phase 146 ABI cleanup `31ec2780` (Apr 9 2026) anchored as Commit B `2713ce61` unreachability cause via design-intent trace per `feedback_design_intent_before_deletion.md` PRIMARY governing memory).

**Verdict distribution across 8 surfaces:** SAFE_BY_STRUCTURAL_CLOSURE × 6 (surfaces i / iii / iv on Commit A side + surfaces v / vii / viii on Commit B side) + SAFE_BY_DESIGN × 2 (surface ii on Commit A buyer-receives-presale-terms-before-deactivation invariant + surface vi on Commit B decimator-vs-BURNIE auto-rebuy orthogonality). ZERO FINDING_CANDIDATE rows.

**4 RE_VERIFIED-NEGATIVE-scope KI envelope rows** (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift narrowed-to-BAF-only) feed Phase 271 §6b directly per D-271-KI-01.

**Cumulative zero source-tree mutations at Phase 270 close:** `git diff --stat -- contracts/ test/` returns EMPTY at both AGENT-COMMITTED commit boundaries. Both Commit A `002bde55` and Commit B `2713ce61` PREDATE v37.0 baseline `1c0f0913` (Phase 270 sub-audit subjects, not v37-introduced); rows enumerated at §3.A for milestone-completeness per CONTEXT.md `<domain>` AUDIT-01 source-tree-change inventory + Phase 270 D-270-FILES-01 cross-cite discipline.

Cross-cite full appendix at `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md`.

---

