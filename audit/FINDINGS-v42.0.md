---
phase: 297-delta-audit-findings-consolidation-terminal
plan: 01
milestone: v42.0
milestone_name: Mint-Batch Event/Sig Cleanup + Hero-Override Weighted Roll + Deity-Pass Gold Nerf + Lootbox RNG Retry
audit_baseline: 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4
audit_baseline_signal: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
v40_baseline: cd549499
v40_baseline_signal: MILESTONE_V40_AT_HEAD_cd549499
audit_subject_head: "81d7c94bc924edb3429f6dc16ee33280fc11c7c2"
closure_signal: MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2
deliverable: audit/FINDINGS-v42.0.md
requirements: [MINTCLN-01, MINTCLN-02, MINTCLN-03, MINTCLN-04, MINTCLN-05, MINTCLN-06, MINTCLN-07, MINTCLN-08, MINTCLN-09, MINTCLN-10,
               TST-MINTCLN-01, TST-MINTCLN-02, TST-MINTCLN-03, TST-MINTCLN-04, TST-MINTCLN-05,
               HRROLL-01, HRROLL-02, HRROLL-03, HRROLL-04, HRROLL-05, HRROLL-06, HRROLL-07, HRROLL-08, HRROLL-09, HRROLL-10,
               TST-HRROLL-01, TST-HRROLL-02, TST-HRROLL-03, TST-HRROLL-04, TST-HRROLL-05, TST-HRROLL-06,
               DPNERF-01, DPNERF-02, DPNERF-03, DPNERF-04, DPNERF-05, DPNERF-06,
               TST-DPNERF-01, TST-DPNERF-02, TST-DPNERF-03, TST-DPNERF-04, TST-DPNERF-05,
               SWEEP-01, SWEEP-02, SWEEP-03, SWEEP-04, SWEEP-05,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06, AUDIT-07, AUDIT-08, AUDIT-09,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
phase_count: 8
phase_ids: [290, 291, 292, 293, 294, 295, 296, 297]
phase_shape: surface-pair + sweep + terminal
requirements_total: 60
findings_total: 0
findings_resolved_at_v42: 0
findings_pending_user_remediation: 0
known_issues_disposition: UNMODIFIED
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_pattern: HYBRID — Phase 296 Task 2 SEQUENTIAL_MAIN_CONTEXT (/contract-auditor); Tasks 3+4 PARALLEL_SUBAGENT (user-authorized mid-sweep)
adversarial_passes: 1
tier_1_resolved: 1
out_of_scope_skills: [degen-skeptic]
supersedes: none
status: "FINAL — READ-ONLY"
read_only: true
generated_at: 2026-05-18
---

# v42.0 Findings — Mint-Batch Event/Sig Cleanup + Hero-Override Weighted Roll + Deity-Pass Gold Nerf + Lootbox RNG Retry (Terminal)

## 1. Audit Subject + Baseline

**Audit Baseline.** The audit baseline is v41.0 closure HEAD `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (closure signal `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` carry-forward from `audit/FINDINGS-v41.0.md` §9c). v42.0 closure HEAD is `81d7c94bc924edb3429f6dc16ee33280fc11c7c2` (resolved at Phase 297 Commit 1 per `D-297-CLOSURE-01` 2-commit sequential SHA orchestration; see §9c for the emitted `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2` signal).

**8-Phase Wave Shape (surface-pair + sweep + terminal).** Phases 290 (MINTCLN contract) + 291 (TST-MINTCLN tests) + 292 (HRROLL contract) + 293 (TST-HRROLL tests) + 294 (DPNERF contract — two USER-APPROVED commits: initial fix + BURNIE gap-closure amendment) + 295 (TST-DPNERF tests) + 296 (SWEEP — 3-skill PARALLEL adversarial pass + mid-sweep USER-APPROVED `retryLootboxRng` feature commit `123f2dac`) + 297 (TERMINAL — this deliverable; SOURCE-TREE FROZEN). The v42.0 audit subject is the source-tree delta `git log 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4..HEAD -- contracts/ test/`:

- **Contract commits (USER-APPROVED, 5 total):**
  - Phase 290 `e5665117` (`contracts(290-02): apply MINTCLN-01..09 cleanup batch [USER-APPROVED]`)
  - Phase 292 `a0218952` (`feat(292): HRROLL — weighted-roll hero-override with ×1.5 leader bonus + no floor + cross-bonus invariance [HRROLL-01..04,06,07,08] [USER-APPROVED]`)
  - Phase 294 initial `47936e0c` (`feat(294): deity-pass gold nerf via flat-1 virtualCount on color==7 [DPNERF-01..06]`)
  - Phase 294 BURNIE gap-closure amendment `38319463` (`feat(294): extend DPNERF gold nerf to BURNIE coin path [DPNERF-02,03] [USER-APPROVED]`)
  - Phase 296 `123f2dac` (`feat(296): retryLootboxRng — 6h recovery for swap-committed mid-day VRF stalls [USER-APPROVED]`)

- **Test commits (USER-APPROVED, 4 total):**
  - Phase 291 `a1404efd` (`tests(291-02): ship TST-MINTCLN-01..05 mint-cleanup regression fixture [USER-APPROVED]`)
  - Phase 293 `0cd01a9c` (`test(293): HRROLL regression fixture TST-HRROLL-01..06 + JS-replay oracle [TST-HRROLL-01..06]`)
  - Phase 295 `8027b16c` (`test(295): DPNERF regression fixture — TST-DPNERF-01..05 [USER-APPROVED]`)
  - VRFStallEdgeCases.t.sol slot-drift fix + retry-coverage tests folded into Phase 296 commit `123f2dac` (per Phase 296 commit shape — single batched commit covering contract + test changes for the `retryLootboxRng` surface).

**4 Audit-Subject Surfaces.** Per `D-297-RETRY-INTEGRATION-01`: **MINTCLN** (Phase 290) + **HRROLL** (Phase 292) + **DPNERF** (Phase 294 initial + BURNIE gap-closure) + **RETRY_LOOTBOX_RNG** (Phase 296 mid-sweep USER-APPROVED feature commit `123f2dac`).

**Write Policy.** AGENT-COMMITTED at Phase 297 terminal per `feedback_no_contract_commits.md` exemption for non-source-tree mechanical work (v41 P284 + v40 P280 + v39 P274 precedent). All upstream Phase 290 + 291 + 292 + 293 + 294 + 295 + 296 contract + test commits landed under USER-APPROVED batched gates per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. The READ-only flip on `audit/FINDINGS-v42.0.md` (`chmod 444` + frontmatter `status: "FINAL — READ-ONLY"` + `read_only: true`) is applied at Phase 297 Commit 2 per `D-297-CLOSURE-01`. KNOWN-ISSUES.md is **UNMODIFIED** at v42 close per `D-297-KI-01` (carry from v41 D-281-KI-01).

**SOURCE-TREE FROZEN.** Phase 297 contributes zero `contracts/` and zero `test/` mutations. Only `audit/FINDINGS-v42.0.md` + the planner-private artifact bundle (`.planning/phases/297-.../*`) + the 5 closure-flip docs (`ROADMAP.md` / `STATE.md` / `MILESTONES.md` / `PROJECT.md` / `REQUIREMENTS.md`) are committed at this phase.

---

## 2. Executive Summary

### Closure Verdict Summary

- **AUDIT-01:** §3.A delta-surface table covers every changed declaration across all 5 v42.0 USER-APPROVED contract commits + 4 USER-APPROVED test commits (`315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` → v42 close HEAD) with hunk-level evidence + `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, DOCS_ONLY, ANALYTICAL, SUPERSEDED}` classification per row. Four phase row groups (MINTCLN: Phase 290 + 291; HRROLL: Phase 292 + 293; DPNERF: Phase 294 initial + Phase 294 BURNIE amendment + Phase 295; RETRY_LOOTBOX_RNG: Phase 296 `123f2dac` 5-row group + optional Phase 296 ANALYTICAL `f2bf0767`) + a Phase 297 SOURCE-TREE-FROZEN attestation row.
- **AUDIT-02:** §3.A row classifications match the source-tree delta (4 audit-subject surfaces + 1 Phase 296 ANALYTICAL row + 1 Phase 297 SOURCE-TREE-FROZEN attestation row). ContractAddresses.sol row classified DOCS_ONLY (deployment-address update; not bytecode-affecting). VRFStallEdgeCases.t.sol row classified MODIFIED_LOGIC with DOCS_ONLY annotation (pre-existing slot-drift collaterally rescued — `lootboxRngPacked` corrected from slot 38→37 and mapping corrected from slot 39→38; the v41-baseline slot-drift was a pre-existing TEST file bug, not a contract storage bug).
- **AUDIT-03:** §3.B 4-surface zero-new-state attestation matrix — MINTCLN ("zero new public/external entry points; only `TraitsGenerated` event topic-hash signature changes per MINTCLN-04 / D-42N-EVT-BREAK-01") + HRROLL ("zero new public/external entry points; only `_topHeroSymbol` → `_rollHeroSymbol` rename + internal RNG-consumer addition") + DPNERF ("zero new public/external entry points; single-function body change at `_randTraitTicket` + matching change at `_awardDailyCoinToTraitWinners` BURNIE gap-closure amendment per D-294-CALLER-UNIFORM-01") + **RETRY_LOOTBOX_RNG ("ONE new public/external entry point: `retryLootboxRng()` permissionless with 6h cooldown enforcement; zero new admin; zero new modifiers; zero new upgrade hooks; storage byte-identical to v41 close")**. Aggregate roll-up: "Across 4 v42 audit-subject surfaces: ONE new public/external entry point (`retryLootboxRng`); zero new admin; zero new modifiers; zero new upgrade hooks; zero new storage slots; only `TraitsGenerated` event topic-hash signature change."
- **AUDIT-04:** §3.C 4-invariant conservation re-proof — (i) MINTCLN 256-bit seed-space invariant: `keccak256(baseKey, entropyWord, groupIdx)` with owed-in-baseKey preserves cross-call seed separation; (ii) HRROLL VRF bit-slice non-collision: `keccak256(abi.encode(entropy, day))` for symbol-roll does NOT overlap with bits[0..12] jackpot path-select / bits[152..167] manual+auto-resolve Bernoulli / bits[200..215] jackpot Bernoulli / bits `quadrant*3` color-sample; (iii) DPNERF deity-payout invariant: gold-tile virtualCount = 1 (was `max(len/50, 2)`); common-tile virtualCount = `max(len/50, 2)` UNCHANGED; (iv) **RETRY_LOOTBOX_RNG entropy-correlation invariant**: daily-flow-takeover composition yields shared lootbox/daily entropy — INTENDED design per Phase 296 (xiv) ACCEPT_AS_DOCUMENTED resolution (user disposition 2026-05-18); no double-spend of VRF entropy; no bucket-binding violation.
- **AUDIT-05:** §4.1 14-charged-hypothesis + 8-beyond-charge disposition table copied verbatim from Phase 296 `296-01-ADVERSARIAL-LOG.md`; §4.2 dedicated subsection cites Phase 296 LOG path verbatim + summarizes ZERO_FINDING result + the 1 Tier-1 ACCEPT_AS_DOCUMENTED on (xiv). 3-skill PARALLEL adversarial-pass disposition attested via HYBRID pattern (Phase 296 Task 2 SEQUENTIAL_MAIN_CONTEXT for `/contract-auditor`; Tasks 3+4 PARALLEL_SUBAGENT for `/zero-day-hunter` + `/economic-analyst` per user authorization 2026-05-18). `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry.
- **AUDIT-06:** §6 KI walkthrough EXC-01..04 RE_VERIFIED at v42 close HEAD; EXC-01/02/03 RE_VERIFIED-NEGATIVE-scope at v42 (the v42 audit subject has zero affiliate-roll / AdvanceModule game-over-RNG-substitution interaction; the AdvanceModule `retryLootboxRng` surface is the rng-retry path, structurally separate from EXC-01..03 affiliate-roll / game-over surfaces); EXC-04 STRUCTURALLY ELIMINATED preserved (`EntropyLib.entropyStep` deleted at v40 Phase 278 `8a81a87c` and NOT reintroduced at v41 + v42). KNOWN-ISSUES.md UNMODIFIED per `D-297-KI-01`; §6 closure verdict `KNOWN_ISSUES_UNMODIFIED`.
- **AUDIT-07:** §9c closure-signal emission completes the v42.0 milestone closure: `0 of 0 F-42-NN RESOLVED_AT_V42; 0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`.
- **AUDIT-08:** KNOWN-ISSUES.md disposition `D-297-KI-01` locked (UNMODIFIED at v42 close — Phase 296 surfaced zero F-42-NN-eligible candidates per Phase 296 LOG ZERO_FINDING result; (xiv) Tier-1 was ACCEPT_AS_DOCUMENTED so no shipped-then-fixed entry to consider for KI promotion). Closure verdict `KNOWN_ISSUES_UNMODIFIED`.
- **AUDIT-09:** Forward-cite zero-emission per `D-297-FCITE-01` carry of `D-42N-FCITE-01` / `D-281-FCITE-01` / `D-40N-FCITE-01` / `D-274-FCITE-01` / `D-272-FCITE-01` / `D-271-FCITE-01` + `D-253-15` step 8: zero forward-cites emitted from Phase 297 to any post-v42.0 milestone phases. Verified at §8 Forward-Cite Closure block. Deferred items use locked-decision IDs + descriptive labels only per `D-297-DEFER-01` 9-entry register.
- **REG-01:** §5a — v41.0 closure signal `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` re-verified NON-WIDENING at v42 HEAD for v41-touched surfaces NOT in v42 scope. Phase 281 owed-salt 4th keccak input invariant preserved at v42 close via owed-in-baseKey carry (MINTCLN refactors the function signature but the cross-call seed separation algorithmic invariant is preserved). Phase 288 `dailyIdx` structural fix preserved (HRROLL reads `dailyIdx` as the single-writer day anchor). Deity common-tile baseline `max(len/50, 2)` UNCHANGED post-DPNERF.
- **REG-02:** §5b — v40.0 closure signal `MILESTONE_V40_AT_HEAD_cd549499` re-verified NON-WIDENING at v42 HEAD on v40-touched surfaces NOT in v42 scope. LootboxModule Bernoulli + WWXRP consolation byte-identical at v42 close; `JackpotModule._jackpotTicketRoll` Bernoulli + keccak self-mix (post-ENT-05 refactor) byte-identical; `LootBoxOpened`/`BurnieLootOpen`/`JackpotTicketWin` event topic-hashes byte-identical (only `TraitsGenerated` changes per MINTCLN-04); whole-BURNIE floor at the 3 RNG-amount sites (`LootboxModule:1080` + `JackpotModule:1842` + `JackpotModule:1922`) byte-identical.
- **REG-03:** §5c — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified NON-WIDENING at v42 HEAD; TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical (v42 does NOT touch TraitUtils or JackpotBucketLib; HRROLL is in `JackpotModule` outside JackpotBucketLib reach; DPNERF is in `_randTraitTicket` outside `_pickSoloQuadrant`).
- **REG-04:** §5d per-finding spot-check sweep PASS across `audit/FINDINGS-v25.0.md` to `audit/FINDINGS-v41.0.md` for v42-touched function/surface set — MINTCLN scope (`_raritySymbolBatch` + `processFutureTicketBatch` + `_processOneTicketEntry` + `TraitsGenerated` event); HRROLL scope (`_topHeroSymbol` → `_rollHeroSymbol` + `_applyHeroOverride` + `dailyHeroWagers`); DPNERF scope (`_randTraitTicket` + `_runJackpotEthFlow` + `payDailyCoinJackpot` + `_awardDailyCoinToTraitWinners`); RETRY_LOOTBOX_RNG scope per `D-297-RETRY-INTEGRATION-01` (`_finalizeLootboxRng` + `rngGate` + `LR_MID_DAY` semantics + `lootboxRngPacked` storage shape + new `retryLootboxRng()` entry point). Each prior finding re-verified RESOLVED or NEGATIVE-scope at v42 close HEAD.

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-42-NN: 0 (ZERO findings; clean closure verdict math per `D-297-VERDICT-01`).

**1 Tier-1 ACCEPT_AS_DOCUMENTED.** Phase 296 hypothesis (xiv) `retryLootboxRng()` entropy-correlation under daily-flow-takeover composition surfaced a single-skill (`/zero-day-hunter`) LOW-severity FINDING_CANDIDATE; the other 2 skills (`/contract-auditor` + `/economic-analyst`) returned SAFE_BY_DESIGN with non-FINDING_CANDIDATE observations (MEDIUM-tier docstring/scope-boundary note + 2 INFO-tier launch-comms observations respectively). Per `D-296-CONSENSUS-01` two-tier consensus rule: Tier-1 (single-skill FINDING_CANDIDATE) was elevated to user disposition; user response 2026-05-18: `ACCEPT_AS_DOCUMENTED` ("that is the intended design"). Tier-2 (3-of-3 consensus) did NOT trigger. The acceptance does NOT promote to an F-42-NN finding block; the §9 verdict math counts promoted findings only per `D-297-VERDICT-01` strict math + the v40/v41 precedent. Full audit-trail visibility is preserved via §4.2 dedicated subsection + §3.C 4th conservation invariant + §9.NN `ADVERSARIAL_TIER_1_RESOLVED` register entry.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25-v41 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward (`D-297-SEV-01` instantiation of `D-42N-SEV-01` / `D-281-SEV-01` / `D-40N-SEV-01` / `D-274-SEV-01` chain). Rubric is **descriptive-only at v42** since zero F-42-NN finding blocks landed.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only. |

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) — accepted-design + non-exploitable + sticky — does not produce any v42 KI candidates: Phase 296 surfaced zero F-42-NN-eligible candidates (ZERO_FINDING result per Phase 296 LOG); (xiv) was ACCEPT_AS_DOCUMENTED so no shipped-then-fixed entry to consider for KI promotion. KNOWN-ISSUES.md is UNMODIFIED at v42 close per `D-297-KI-01`. §6 closure verdict `KNOWN_ISSUES_UNMODIFIED`.

### Forward-Cite Closure Summary

`D-297-FCITE-01` carry of `D-42N-FCITE-01` / `D-281-FCITE-01` / `D-40N-FCITE-01` / `D-274-FCITE-01` / `D-272-FCITE-01` / `D-271-FCITE-01` + `D-253-15` step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 297 to any post-v42.0 milestone phases. §9d Deferred-to-Future register (9 entries per `D-297-DEFER-01`) uses locked-decision IDs + descriptive labels only.

### Attestation Anchor

`D-297-CLOSURE-01` 2-commit sequential SHA orchestration: Commit 1 writes `audit/FINDINGS-v42.0.md` with `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2` placeholder; Commit 2 resolves the placeholder to the Commit 1 SHA, propagates verbatim to 5 FINDINGS verbatim locations + 3 cross-document propagation targets, applies `chmod 444`, and ships the atomic closure flip across ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS.

---

## 3. Per-Phase Sections

### 3a. Phase 290 — Mint-Batch Event/Sig Cleanup (MINTCLN)

**Commit.** `e5665117 contracts(290-02): apply MINTCLN-01..09 cleanup batch [USER-APPROVED]` (USER-APPROVED batched contract commit per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`).

**Scope.** `contracts/modules/DegenerusGameMintModule.sol` — MINTCLN-01..10 surface change: `_raritySymbolBatch` signature collapses from 4-input hash to 3-input hash (drops `uint32 ownedSalt` parameter); body hashes `keccak256(baseKey, entropyWord, groupIdx)`. The `owed` value is now carried inside `baseKey` low 32 bits at construction (`baseKey = (lvl<<224) | (queueIdx<<192) | (player<<32) | owed`) at both callsites (`processFutureTicketBatch` mint:423-425 + `_processOneTicketEntry` mint:800-802 — B2-symmetric per v41 Phase 281 precedent). Same 256-bit seed space, same uniformity, same cross-call seed separation when same slot is re-entered with smaller owed (the owed shrinks per emit; baseKey shrinks correspondingly; pairwise-distinct hashes across multi-call drains). The `TraitsGenerated` event signature changes from `(address indexed player, uint256 baseKey, uint32 startIndex, uint32 take)` to `(address indexed player, uint256 baseKey, uint32 take)` — rename + drop. **BREAKING topic-hash** on `TraitsGenerated` per MINTCLN-04 / `D-42N-EVT-BREAK-01` (inherits v40 `D-40N-EVT-BREAK-01` posture; pre-launch; indexer rebuild required; no live indexer impact).

**Per-surface artifacts.** Bytecode delta + storage byte-identity + public ABI byte-identity per `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md`. Design-intent trace for the owed-in-baseKey collapse rationale per `290-01-DESIGN-INTENT-TRACE.md`. Phase 290 audit-subject commit + carry-forward notes per `290-01-SUMMARY.md` + `290-02-SUMMARY.md`. Phase 291 TST-MINTCLN regression coverage commit `a1404efd` ships TST-MINTCLN-01..05 (RNG correctness re-validation on multi-call drains; `TraitsGenerated` event-shape regression; storage layout regression; indexer-migration note; both-callsite-paths B2-symmetric coverage per `291-02-SUMMARY.md`).

**Decision anchors.** `D-42N-MINTCLN-SCOPE-01` (narrow scope, no helper extraction — duplicate-logic flagged-only; carried to §9d) + `D-42N-EVT-BREAK-01` (breaking `TraitsGenerated` topic-hash accepted; indexer migration inherits v40 `D-40N-EVT-BREAK-01` posture; carried to §9d).

### 3b. Phase 292 — Hero-Override Weighted Roll (HRROLL)

**Commit.** `a0218952 feat(292): HRROLL — weighted-roll hero-override with ×1.5 leader bonus + no floor + cross-bonus invariance [HRROLL-01..04,06,07,08] [USER-APPROVED]` (USER-APPROVED batched contract commit).

**Scope.** `contracts/modules/DegenerusGameJackpotModule.sol:1594-1653` — HRROLL-01..10 surface change: `_topHeroSymbol(dailyIdx)` replaced with `_rollHeroSymbol(uint32 day, uint256 entropy) private view returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)`. Two-pass over the 32 `(quadrant, symbol)` slots in `dailyHeroWagers[day]` — pass 1 computes total weight + identifies max-amount leader; pass 2 walks the table with cumulative weight cursor against a 64-bit `pick` value derived from `keccak256(abi.encode(entropy, day)) % effectiveTotal`. ×1.5 leader-weight bonus per `D-42N-LEADER-BONUS-01` (max-amount slot gets `weight = amount + leaderBonus` where `leaderBonus = maxAmount / 2`; `effectiveTotal = total + leaderBonus`). No min-wager floor per `D-42N-FLOOR-01` (every slot with `amount > 0` included). `_applyHeroOverride` call-site updated to invoke `_rollHeroSymbol(dailyIdx, randomWord)`; symbol roll uses keccak-derived bits from `keccak256(abi.encode(entropy, day))` — non-overlapping with bits[0..12] / [152..167] / [200..215] / `quadrant*3` per `D-42N-COLOR-ENTROPY-01`. Storage byte-identical (`dailyHeroWagers` layout UNCHANGED; `dailyIdx` UNCHANGED). Public ABI byte-identical (`_rollHeroSymbol` private; `_topHeroSymbol` deletion doesn't affect external surface).

**Per-surface artifacts.** Bytecode delta + bit-slice non-collision proof + gas regression worst-case (theoretical worst case derived FIRST per `feedback_gas_worst_case.md` + `D-42N-GAS-01` — soft +500 / hard +750 gas threshold vs v41 baseline) per `292-01-MEASUREMENT.md`. Design-intent trace for ×1.5 leader-bonus + RNG-window backward-trace verification per `292-01-DESIGN-INTENT-TRACE.md`. Phase 292 audit-subject commit + gas regression worst-case + carry-forward notes per `292-02-SUMMARY.md`. Phase 293 TST-HRROLL regression coverage commit `0cd01a9c` ships TST-HRROLL-01..06 (chi² goodness-of-fit weighted-distribution test; ×1.5 leader-bonus sanity; RNG commitment-window proof regression; single-bettor + zero-wager edge cases; gas regression empirical; JS-replay oracle helper per `293-02-SUMMARY.md`).

**Decision anchors.** `D-42N-LEADER-BONUS-01` (×1.5 locked) + `D-42N-FLOOR-01` (no floor locked) + `D-42N-COLOR-ENTROPY-01` (bit-allocation non-collision) + `D-42N-DETERMINISM-01` (exact roll algorithm) + `D-42N-GAS-01` (gas threshold) + `D-42N-CACHE-01` (flat uint32[32] cache shape indexed q*8+s; ~+431 gas worst case per Phase 292 measurement).

### 3c. Phase 294 — Deity-Pass Gold Nerf (DPNERF)

**Commits (TWO USER-APPROVED).** `47936e0c feat(294): deity-pass gold nerf via flat-1 virtualCount on color==7 [DPNERF-01..06]` (initial fix at `_randTraitTicket`) + `38319463 feat(294): extend DPNERF gold nerf to BURNIE coin path [DPNERF-02,03] [USER-APPROVED]` (BURNIE gap-closure amendment at `_awardDailyCoinToTraitWinners` per `D-294-CALLER-UNIFORM-01`).

**Scope.** `contracts/modules/DegenerusGameJackpotModule.sol:1671-1710` — DPNERF-01..06 surface change: `_randTraitTicket` body adds a color-tier check before the existing `virtualCount = len / 50` + `if (virtualCount < 2) virtualCount = 2` logic. When `(trait >> 3) & 7 == 7` (gold color tier per the trait byte layout), set `virtualCount = 1` and skip the existing `max(len/50, 2)` floor. When color tier is NOT gold (commons, `color ∈ [0..6]`), execute the existing v41 logic unchanged. Both ETH + BURNIE coin jackpot paths covered per `D-42N-PATH-COVERAGE-01` — the initial commit `47936e0c` covered the `_randTraitTicket` callsite; the BURNIE gap-closure amendment `38319463` covered the `_awardDailyCoinToTraitWinners` callsite that the initial fix missed (per `D-294-CALLER-UNIFORM-01` caller-uniformity precedent + `feedback_verify_call_graph_against_source.md`). Intentional EV reduction per `D-42N-DEITY-EV-01` — no common-tier compensation. Storage byte-identical (single-function body change; zero new storage; zero new SSTORE; zero new SLOAD). Public ABI byte-identical (`_randTraitTicket` private; ETH + BURNIE coin jackpot caller signatures unchanged).

**Per-surface artifacts.** Callsite enumeration + bytecode delta + zero-new-state grep-proof per `294-01-MEASUREMENT.md`. Design-intent trace + actor-walk + SWEEP-02(iii) 4 pre-emptive answers per `294-01-DESIGN-INTENT-TRACE.md`. Phase 294 audit-subject commits + callsite-coverage carry-forward per `294-02-SUMMARY.md`. Phase 295 TST-DPNERF regression coverage commit `8027b16c` ships TST-DPNERF-01..05 (gold-tile virtual-count assertion; common-tier virtual-count preserved; BURNIE coin jackpot path coverage; gold-tile EV regression; non-deity holders unaffected per `295-01-SUMMARY` directory artifacts). `D-295-CALLSITE-SCOPE-01` callsites 1+2 deferred to Phase 296 SWEEP — resolved at Phase 296 hypothesis (xi) SAFE_BY_STRUCTURAL_CLOSURE (BURNIE gap-closure precedent per `feedback_verify_call_graph_against_source.md`).

**Decision anchors.** `D-42N-GOLD-FLOOR-01` (flat 1 locked) + `D-42N-DEITY-EV-01` (intentional reduction; no compensation) + `D-42N-PATH-COVERAGE-01` (both ETH + BURNIE locked) + `D-294-CALLER-UNIFORM-01` (caller-uniformity precedent; BURNIE gap-closure amendment).

### 3d. Phase 296 — Cross-Surface Adversarial Sweep + RETRY_LOOTBOX_RNG (SWEEP)

**Commits.** `123f2dac feat(296): retryLootboxRng — 6h recovery for swap-committed mid-day VRF stalls [USER-APPROVED]` (mid-sweep USER-APPROVED feature commit per `feedback_never_preapprove_contracts.md`) + `f2bf0767 docs(296): cross-surface adversarial sweep [SWEEP-01..05]` (AGENT-COMMITTED planner-private artifact bundle: CHARGE + 3 per-skill MDs + integrated LOG; classified ANALYTICAL).

**Scope (RETRY_LOOTBOX_RNG audit-subject surface per `D-297-RETRY-INTEGRATION-01`).** `contracts/modules/DegenerusGameAdvanceModule.sol` adds new `retryLootboxRng()` permissionless external entry point with 6h cooldown enforcement for swap-committed mid-day VRF stall recovery. The retry path preserves the pre-advanced `lootboxRngIndex` and the buffer swap so the new VRF word lands in the same bucket the original request bound; the stale callback is auto-rejected by the requestId match in `rawFulfillRandomWords`. Bit allocation map documented at `advance:1157-1174`. Delegation hook in `contracts/DegenerusGame.sol` + interface extensions in `contracts/interfaces/IDegenerusGame.sol` + `contracts/interfaces/IDegenerusGameModules.sol`. `test/fuzz/VRFStallEdgeCases.t.sol` slot-drift fix (`lootboxRngPacked` slot 38→37; mapping slot 39→38; `test_zeroSeedUnreachableAfterSwap` collaterally rescued — the v41-baseline slot-drift was a pre-existing TEST file bug, not a contract storage bug; v42 close contract storage layout byte-identical to v41 close).

**Phase 296 adversarial-pass disposition.** 3-skill HYBRID adversarial pass: Task 2 `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT; Tasks 3+4 `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT (user-authorized mid-sweep 2026-05-18 — accepted marginal persona-fidelity trade-off for ~3× wall-clock speedup per `D-296-INVOKE-01`). 14 charged hypotheses (i)..(xiv) covering MINTCLN (i)..(iii) + HRROLL (iv)..(viii) + DPNERF (ix)..(xi) + RETRY_LOOTBOX_RNG (xii)..(xiv) + 8 beyond-charge entries (5 `/zero-day-hunter` B1..B5 + 3 `/economic-analyst` (xv)..(xvii)). Result: ZERO_FINDING after Tier-1 (xiv) ACCEPT_AS_DOCUMENTED resolution per user disposition 2026-05-18 (cross-referenced to §4.1 + §4.2 + §9.NN). Tier-2 (3-of-3 consensus) did NOT trigger. RE-PASS not triggered per `D-296-REPASS-SCOPE-01`. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry.

**(xiv) mid-sweep surface-set expansion.** Hypothesis (xiv) `retryLootboxRng()` was added beyond-charge mid-sweep per user request 2026-05-18 (originally OUT-OF-SCOPE per working-tree note; flipped IN-SCOPE after user committed the function at `123f2dac`); the audit-subject head advanced from `aa282b87` to `123f2dac` mid-sweep. Surface-set expanded from 3 audit-subject surfaces (original ROADMAP wording) to 4 audit-subject surfaces per `D-297-RETRY-INTEGRATION-01`.

**Decision anchors.** `D-296-CHARGE-01` (14-hypothesis charge) + `D-296-CONSENSUS-01` (two-tier consensus rule: Tier-1 single-skill FINDING_CANDIDATE → user disposition; Tier-2 3-of-3 consensus → elevate to F-NN block) + `D-296-REPASS-SCOPE-01` (RE-PASS scope; not triggered) + `D-296-INVOKE-01` (HYBRID invocation pattern; user-authorized PARALLEL for Tasks 3+4) + `D-296-ARTIFACT-SET-01` (artifact bundling — CHARGE + 3 per-skill MDs + integrated LOG + CONTEXT + PLAN) + `D-296-KI-01` → `D-297-KI-01` (KNOWN-ISSUES.md UNMODIFIED carry).

### 3e. Phase 297 — Delta Audit + Findings Consolidation (Terminal; SOURCE-TREE FROZEN)

**SOURCE-TREE FROZEN attestation.** Phase 297 contributes ZERO `contracts/` and ZERO `test/` mutations. The 4-task plan (T1 author DRAFT → T2 verify → T3 promote + Commit 1 → T4 resolve SHA + propagate + chmod 444 + 5-doc closure flip + Commit 2) per `D-297-TASK-SPLIT-01` ships only the AGENT-COMMITTED audit deliverable + planner-private artifact bundle + 5-doc closure-flip docs. 2-commit sequential SHA orchestration per `D-297-CLOSURE-01`: Commit 1 = audit deliverable + planner-private bundle (CONTEXT + DISCUSSION-LOG + PLAN + DRAFT + VERIFY); Commit 2 = closure flip + SHA propagation + chmod 444.

### 3.A AUDIT-01 Delta-Surface Table

Row classifications per `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, DOCS_ONLY, ANALYTICAL, SUPERSEDED}` vocabulary (v41 P284 precedent).

| # | Phase | Commit | File | Lines | Classification | Hunk-Level Evidence |
|---|-------|--------|------|-------|----------------|---------------------|
| 1 | 290 MINTCLN | `e5665117` | `contracts/modules/DegenerusGameMintModule.sol` | mint:423-425, 469-477, 499, 534-543, 544-551, 572, 714, 771-773, 800-803, 804-811 | MODIFIED_LOGIC | `_raritySymbolBatch` 4-input → 3-input keccak signature; owed-in-baseKey collapse at both B2-symmetric callsites; `TraitsGenerated` event field-set rename + drop (BREAKING topic-hash per MINTCLN-04); `rollSalt` collapsed to reuse `baseKey`; docstring rewritten per `feedback_no_history_in_comments.md`. Bytecode delta + storage byte-identity attested per `290-01-MEASUREMENT.md`. |
| 2 | 290 MINTCLN | `e5665117` | `contracts/modules/DegenerusGameStorage.sol` | storage:484-491 | MODIFIED_LOGIC | `TraitsGenerated` event declaration field-set rename + drop per MINTCLN-04 / `D-42N-EVT-BREAK-01`. |
| 3 | 291 TST-MINTCLN | `a1404efd` | `test/edge/MintBatchCleanup.test.js` (or equivalent test path per actual landing — see `291-02-SUMMARY.md`) | full file (NEW) | NEW | Multi-call drain RNG correctness re-validation; `TraitsGenerated` 3-tuple event-shape regression; both B2-symmetric callsite paths covered; storage layout regression; indexer-migration note documentation. |
| 4 | 292 HRROLL | `a0218952` | `contracts/modules/DegenerusGameJackpotModule.sol` | jpt:1594-1653 | MODIFIED_LOGIC | `_topHeroSymbol(dailyIdx)` → `_rollHeroSymbol(uint32 day, uint256 entropy)` rename + weighted-roll implementation; ×1.5 leader bonus per `D-42N-LEADER-BONUS-01`; no min-wager floor per `D-42N-FLOOR-01`; `keccak256(abi.encode(entropy, day))` consumer (non-overlapping bit allocation per `D-42N-COLOR-ENTROPY-01`); `_applyHeroOverride` callsite updated. Bytecode delta + bit-slice non-collision per `292-01-MEASUREMENT.md`. |
| 5 | 293 TST-HRROLL | `0cd01a9c` | `test/edge/HRROLL.test.js` (or equivalent — see `293-02-SUMMARY.md`) + JS-replay oracle helper | full file + helper (NEW) | NEW | Chi² goodness-of-fit weighted-distribution test; ×1.5 leader-bonus sanity; RNG commitment-window proof regression; single-bettor + zero-wager edge cases; gas regression empirical (TST-HRROLL-06 RELAX log-only traceability per Plan 02 user disposition + `D-291-GAS-01` SKIP-GAS mirror); JS-replay oracle helper (`D-293-INVOKE-01` ALGORITHM_VERIFIED at production-path level via 16/16 cross-attestation replays). |
| 6 | 294 DPNERF initial | `47936e0c` | `contracts/modules/DegenerusGameJackpotModule.sol` | jpt:1671-1710 (`_randTraitTicket`) | MODIFIED_LOGIC | Color-tier gold check `(trait >> 3) & 7 == 7` → `virtualCount = 1` (was `max(len/50, 2)`); common-tier unchanged. Storage byte-identical; public ABI byte-identical. Per `294-01-MEASUREMENT.md`. |
| 7 | 294 DPNERF BURNIE gap-closure | `38319463` | `contracts/modules/DegenerusGameJackpotModule.sol` | `_awardDailyCoinToTraitWinners` callsite | MODIFIED_LOGIC | BURNIE coin jackpot path gap-closure amendment per `D-294-CALLER-UNIFORM-01` + `feedback_verify_call_graph_against_source.md`. Identical color-tier check applied to the second callsite the initial fix missed. |
| 8 | 295 TST-DPNERF | `8027b16c` | `test/edge/DPNERF.test.js` (or equivalent — see `295-*-SUMMARY` artifacts) | full file (NEW) | NEW | Gold-tile virtual-count assertion; common-tier virtual-count preserved; BURNIE coin jackpot path coverage per `D-42N-PATH-COVERAGE-01`; gold-tile EV regression; non-deity holders unaffected. `D-295-CALLSITE-SCOPE-01` callsites 1+2 deferred to Phase 296 SWEEP → resolved at hypothesis (xi) SAFE_BY_STRUCTURAL_CLOSURE. |
| 9 | 296 RETRY_LOOTBOX_RNG | `123f2dac` | `contracts/modules/DegenerusGameAdvanceModule.sol` | new `retryLootboxRng()` + advance:1157-1174 bit allocation map docstring + `_finalizeLootboxRng` at advance:1234 | MODIFIED_LOGIC | New `retryLootboxRng()` permissionless external entry point + 6h-cooldown swap-committed mid-day VRF stall recovery + buffer-swap preservation + `lootboxRngIndex` pre-advanced state. Bit allocation map docstring documents per-consumer bit-slices. |
| 10 | 296 RETRY_LOOTBOX_RNG | `123f2dac` | `contracts/DegenerusGame.sol` | delegation hook | MODIFIED_LOGIC | Delegation hook for `retryLootboxRng()` external entry point. |
| 11 | 296 RETRY_LOOTBOX_RNG | `123f2dac` | `contracts/interfaces/IDegenerusGame.sol` | interface extension | MODIFIED_LOGIC | Interface extension — new external entry point. |
| 12 | 296 RETRY_LOOTBOX_RNG | `123f2dac` | `contracts/interfaces/IDegenerusGameModules.sol` | module interface extension | MODIFIED_LOGIC | Module interface extension. |
| 13 | 296 RETRY_LOOTBOX_RNG | `123f2dac` | `test/fuzz/VRFStallEdgeCases.t.sol` | slot-drift fix + retry-coverage tests | MODIFIED_LOGIC (DOCS_ONLY annotation) | Pre-existing slot-drift collaterally rescued — `lootboxRngPacked` corrected from slot 38→37 and mapping corrected from slot 39→38; `test_zeroSeedUnreachableAfterSwap` collaterally rescued. The v41-baseline slot-drift was a pre-existing TEST file bug, not a contract storage bug. New retry-coverage tests added per Phase 296 commit shape. |
| 14 | 296 RETRY_LOOTBOX_RNG | `123f2dac` | `contracts/ContractAddresses.sol` | deployment-address update | DOCS_ONLY | Deployment-address update; not bytecode-affecting at audit-subject level (per `feedback_contractaddresses_policy.md` — ContractAddresses.sol is modifiable). |
| 15 | 296 SWEEP | `f2bf0767` | `.planning/phases/296-cross-surface-adversarial-sweep-sweep/*` (planner-private artifact bundle: `296-ADVERSARIAL-CHARGE.md` + `296-ADVERSARIAL-CONTRACT-AUDITOR.md` + `296-ADVERSARIAL-ZERO-DAY-HUNTER.md` + `296-ADVERSARIAL-ECONOMIC-ANALYST.md` + `296-01-ADVERSARIAL-LOG.md`) | full bundle | ANALYTICAL | Phase 296 3-skill HYBRID adversarial pass + integrated 3-H2 + Disposition log + CHARGE prompt. No source-tree impact. §4.1 + §4.2 + §9.NN canonical citation source. |
| 16 | 297 TERMINAL | (this deliverable) | `audit/FINDINGS-v42.0.md` + `.planning/phases/297-*/297-CONTEXT.md` + `297-DISCUSSION-LOG.md` + `297-01-PLAN.md` + `297-FINDINGS-DRAFT.md` + `297-FINDINGS-VERIFY.md` + 5 closure-flip docs (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) | full | SOURCE-TREE-FROZEN attestation | Phase 297 ships zero `contracts/` + zero `test/` mutations per `D-297-CLOSURE-01`. 2-commit AGENT-COMMITTED shape per `feedback_no_contract_commits.md` exemption for non-source-tree mechanical work (v41 P284 + v40 P280 + v39 P274 precedent). |

**Row count.** 16 rows total = 14 audit-subject-commit rows (mapping to 5 USER-APPROVED contract commits + 4 USER-APPROVED test commits across 4 surfaces) + 1 ANALYTICAL row (Phase 296 LOG bundle) + 1 SOURCE-TREE-FROZEN attestation row (Phase 297). Exceeds the ≥ 10 row floor per `D-297-RETRY-INTEGRATION-01` §3.A row count target.

### 3.B AUDIT-03 Zero-New-State Attestation (4-surface)

| Surface | Storage | Public/external Entry Points | Admin | Modifiers | Upgrade Hooks | Event Topic-Hash |
|---------|---------|------------------------------|-------|-----------|---------------|------------------|
| MINTCLN | byte-identical (`ticketsOwedPacked[rk][player]` 40-bit packed form UNCHANGED) | zero new | zero new | zero new | zero new | `TraitsGenerated` topic-hash changes per MINTCLN-04 / `D-42N-EVT-BREAK-01` (BREAKING; other event topics byte-identical) |
| HRROLL | byte-identical (`dailyHeroWagers[uint32 => uint256[4]]` UNCHANGED; `dailyIdx` UNCHANGED) | zero new (`_topHeroSymbol` → `_rollHeroSymbol` rename + internal RNG-consumer addition; `_rollHeroSymbol` is private) | zero new | zero new | zero new | byte-identical |
| DPNERF | byte-identical (single-function body change at `_randTraitTicket` + matching change at `_awardDailyCoinToTraitWinners` BURNIE gap-closure amendment per `D-294-CALLER-UNIFORM-01`; zero new storage; zero new SSTORE; zero new SLOAD) | zero new (`_randTraitTicket` private; ETH + BURNIE caller signatures unchanged) | zero new | zero new | zero new | byte-identical |
| **RETRY_LOOTBOX_RNG** | byte-identical (reads `lootboxRngPacked` slot 37 + mapping slot 38 per v41 close storage layout; **the v41-baseline slot-drift was a pre-existing TEST file bug, not a contract storage bug; v42 close contract storage layout byte-identical to v41 close storage layout**) | **ONE new public/external entry point: `retryLootboxRng()` permissionless with 6h cooldown enforcement** | zero new | zero new | zero new | byte-identical |
| **Aggregate (4-surface roll-up)** | zero new storage slots | **ONE new public/external entry point (`retryLootboxRng`)** | zero new | zero new | zero new | only `TraitsGenerated` topic-hash signature change |

**Exception annotation (RETRY_LOOTBOX_RNG row).** The aggregate "zero new public/external entry points" attestation from v36..v41 audit-attestation pattern is preserved for 3 of 4 audit-subject surfaces (MINTCLN + HRROLL + DPNERF). The RETRY_LOOTBOX_RNG surface introduces **ONE** new public/external entry point (`retryLootboxRng()` permissionless with 6h cooldown enforcement) per `D-297-RETRY-INTEGRATION-01` §3.B exception annotation. Zero new admin; zero new modifiers; zero new upgrade hooks. Storage byte-identical to v41 close (the slot-drift fix in `test/fuzz/VRFStallEdgeCases.t.sol` corrected a pre-existing TEST file bug — `lootboxRngPacked` slot 38→37 and mapping slot 39→38 — not a contract storage bug; v42 close contract storage layout is byte-identical to v41 close contract storage layout).

### 3.C AUDIT-04 Conservation Re-Proof (4 invariants)

**(i) MINTCLN 256-bit seed-space invariant.** `keccak256(baseKey, entropyWord, groupIdx)` with owed-in-baseKey carries the cross-call seed separation invariant from v41 Phase 281 owed-salt 4th keccak input forward. Backward-cite via `D-281-FIX-SHAPE-01` reference pattern: at v41 baseline, the v41 Phase 281 fix wrote `keccak256(baseKey, entropyWord, groupIdx, ownedSalt)` with `ownedSalt = owed`; MINTCLN refactors this to `keccak256(baseKey, entropyWord, groupIdx)` with `baseKey` carrying `owed` in low 32 bits (`baseKey = (lvl<<224) | (queueIdx<<192) | (player<<32) | owed`). Same 256-bit seed space; same uniformity; pairwise-distinct hashes across multi-call drains (owed shrinks per emit; baseKey shrinks correspondingly). The MINTCLN refactor preserves the v41 Phase 281 algorithmic invariant — only the function signature + event shape change. Per `290-01-DESIGN-INTENT-TRACE.md`.

**(ii) HRROLL VRF bit-slice non-collision invariant.** `keccak256(abi.encode(entropy, day))` for symbol-roll bits does NOT overlap with bits[0..12] jackpot path-select / bits[152..167] manual+auto-resolve Bernoulli / bits[200..215] jackpot Bernoulli / bits `quadrant*3` color-sample. The symbol-roll uses a SEPARATE keccak-derived 256-bit word (`keccak256(abi.encode(entropy, day))`) rather than slicing bits out of the original VRF word — by construction the symbol-roll consumer cannot collide with any other consumer in the original VRF word's bit space. Backward-cite to `292-01-MEASUREMENT.md` bit-slice non-collision proof + `D-42N-COLOR-ENTROPY-01`. Color sampling stays via `randomWord` bits `quadrant*3` per existing logic (3 bits per quadrant) — same VRF word, but distinct bit slice from the keccak-derived symbol-roll consumer.

**(iii) DPNERF deity-payout invariant.** Gold-tile virtualCount = 1 (was `max(len/50, 2)`); common-tile virtualCount = `max(len/50, 2)` UNCHANGED. Total deity virtual-entries across N gold-tile wins reduced by analytical expectation (from N × `max(len/50, 2)` to N × 1; in steady state with `len ≥ 100`, this is roughly a halving of deity virtual-entries on gold wins). Backward-cite to `294-01-DESIGN-INTENT-TRACE.md` + Phase 295 TST-DPNERF-04 gold-tile EV regression + Phase 296 hypothesis (xi) SAFE_BY_STRUCTURAL_CLOSURE (BURNIE gap-closure precedent per `feedback_verify_call_graph_against_source.md`). Both ETH (`_runJackpotEthFlow`) and BURNIE (`_awardDailyCoinToTraitWinners`) jackpot paths covered per `D-42N-PATH-COVERAGE-01` + `D-294-CALLER-UNIFORM-01`. No common-tier compensation per `D-42N-DEITY-EV-01` intentional EV reduction disposition.

**(iv) RETRY_LOOTBOX_RNG entropy-correlation invariant.** Per `D-297-RETRY-INTEGRATION-01` §3.C exact prose: the daily-flow-takeover composition where `_finalizeLootboxRng` at `advance:1234` fills the `LR_MID_DAY` lootbox word with the daily-derived VRF word yields shared entropy between lootbox-mid-day-bucket consumers and daily-jackpot consumers. **INTENDED DESIGN per user disposition 2026-05-18 on Phase 296 (xiv) Tier-1 ACCEPT_AS_DOCUMENTED.** The bit allocation map at `advance:1157-1174` documents per-consumer bit-slices, but the cross-composition entropy-correlation is OUTSIDE the bit-allocation map's domain-separation guarantee scope (which holds WITHIN a single VRF word's bit-slice partition, NOT ACROSS composition paths where one VRF word substitutes for another). The retry path preserves the pre-advanced `lootboxRngIndex` and the buffer swap so the new VRF word lands in the same bucket the original request bound; the stale callback is auto-rejected by the requestId match in `rawFulfillRandomWords`. **Conservation:** no double-spend of VRF entropy; no bucket-binding violation; the entropy DOES correlate with daily-jackpot entropy in this specific composition, which is the documented INTENDED behavior. Backward-trace per `feedback_rng_backward_trace.md` + commitment-window per `feedback_rng_commitment_window.md` — Phase 296 LOG already attested per these rules; §3.C copies the attestation forward.

---

## 4. Adversarial Surfaces

### 4.1. Hypothesis-Surface Disposition Table

Copied verbatim from Phase 296 `296-01-ADVERSARIAL-LOG.md` Disposition section's "Per-hypothesis aggregation table" (14 charged hypotheses (i)..(xiv) + 8 beyond-charge entries: 5 `/zero-day-hunter` B1..B5 + 3 `/economic-analyst` (xv)..(xvii)).

| # | Hypothesis | Surface | `/contract-auditor` | `/zero-day-hunter` | `/economic-analyst` | Consensus |
|---|------------|---------|---------------------|--------------------|--------------------|-----------|
| (i) | 3-input hash re-introduces a determinism break | MINTCLN | SAFE_BY_DESIGN | SAFE | SAFE_BY_DESIGN | CLEAR |
| (ii) | `owed` packed into `baseKey` opens griefing on shape collision | MINTCLN | SAFE_BY_DESIGN | SAFE | SAFE_BY_DESIGN | CLEAR |
| (iii) | Breaking `TraitsGenerated` topic-hash creates parsing-ambiguity for decoding callers | MINTCLN | SAFE_BY_DESIGN (pre-launch posture; D-42N-EVT-BREAK-01) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (iv) | ×1.5 leader bonus opens whale-coordination / wash-trading MEV | HRROLL | SAFE_BY_DESIGN | SAFE | SAFE_BY_DESIGN | CLEAR |
| (v) | No-floor design opens sybil dilution attack | HRROLL | SAFE_BY_DESIGN | SAFE | SAFE_BY_DESIGN (D-42N-FLOOR-01 disposition) | CLEAR |
| (vi) | New RNG-consumer collides with existing consumers (bits[0..12] / [152..167] / [200..215] / `quadrant*3`) | HRROLL | SAFE_BY_DESIGN (bit-slice non-collision per 292-01-MEASUREMENT) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (vii) | Gas regression opens DOS surface | HRROLL | SAFE_BY_DESIGN (D-42N-GAS-01 threshold + worst-case derivation per feedback_gas_worst_case.md) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (viii) | Determinism / replayability spec break under deterministic-but-distinct (entropy, day) inputs | HRROLL | SAFE_BY_DESIGN (D-42N-DETERMINISM-01) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (ix) | Intentional EV reduction shifts incentives toward non-gold gameplay destabilizing commons-tier dynamics | DPNERF | SAFE_BY_DESIGN (D-42N-DEITY-EV-01 intentional-reduction disposition) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (x) | Both-paths coverage opens differential-behavior between ETH and BURNIE that an attacker can game | DPNERF | SAFE_BY_STRUCTURAL_CLOSURE (BURNIE gap-closure amendment `38319463` per D-294-CALLER-UNIFORM-01) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (xi) | DPNERF `D-295-CALLSITE-SCOPE-01` deferred callsites 1+2 remain uncovered | DPNERF | SAFE_BY_STRUCTURAL_CLOSURE | SAFE | SAFE_BY_DESIGN | CLEAR |
| (xii) | `retryLootboxRng()` permissionless retry LINK consumption opens DoS griefing surface | RETRY_LOOTBOX_RNG | SAFE_BY_DESIGN (6h cooldown bounds operational cost per /economic-analyst INFO) | SAFE | SAFE_BY_DESIGN | CLEAR |
| (xiii) | Stale callback at `rawFulfillRandomWords` double-spends VRF entropy | RETRY_LOOTBOX_RNG | SAFE_BY_DESIGN (requestId match auto-rejects stale callback) | SAFE | SAFE_BY_DESIGN | CLEAR |
| **(xiv)** | **`retryLootboxRng()` entropy-correlation under daily-flow-takeover composition** | **RETRY_LOOTBOX_RNG** | **SAFE_BY_DESIGN (with MEDIUM-tier docstring/scope-boundary note → D-42N-RETRY-RNG-SCOPE-DOC-01)** | **FINDING_CANDIDATE (LOW severity; shared-entropy composition between retry path + daily-flow-takeover)** | **SAFE_BY_DESIGN (with INFO-tier launch-comms observations → D-42N-RETRY-RNG-LAUNCH-FAQ-01)** | **TIER-1 ELEVATED → USER DISPOSITION 2026-05-18: ACCEPT_AS_DOCUMENTED (intended design)** |
| (B1)..(B5) | `/zero-day-hunter` beyond-charge entries | (various) | n/a | NEGATIVE_RESULT_ONLY | n/a | CLEAR |
| (xv)..(xvii) | `/economic-analyst` beyond-charge entries | (various) | n/a | n/a | INFO observations / launch-comms FAQ | CLEAR |

**Aggregate.** 13 of 14 charged hypotheses CLEAR on first-pass first-tier; 1 (xiv) elevated Tier-1 → user disposition ACCEPT_AS_DOCUMENTED; 8 of 8 beyond-charge entries CLEAR / NEGATIVE_RESULT_ONLY / INFO-only. **ZERO_FINDING result after Tier-1 (xiv) ACCEPT_AS_DOCUMENTED resolution.** Tier-2 (3-of-3 consensus) did NOT trigger. RE-PASS not triggered per `D-296-REPASS-SCOPE-01`. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry.

### 4.2. Adversarial-Pass Disposition (Phase 296)

**Canonical citation.** `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-01-ADVERSARIAL-LOG.md` (integrated 3-H2 + Disposition section; 14 charged hypotheses + 8 beyond-charge entries; HYBRID invocation pattern — Task 2 `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT; Tasks 3+4 `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT under user authorization 2026-05-18 per `D-296-INVOKE-01`).

**Per-skill disposition source MDs (supporting evidence):** `296-ADVERSARIAL-CONTRACT-AUDITOR.md` (per-hypothesis evidence chain; (xiv) SAFE_BY_DESIGN with MEDIUM docstring/scope-boundary observation source for `D-42N-RETRY-RNG-SCOPE-DOC-01`); `296-ADVERSARIAL-ZERO-DAY-HUNTER.md` (per-hypothesis evidence + 5 beyond-charge B1..B5; (xiv) FINDING_CANDIDATE evidence + suggested-remediation Options A/B source); `296-ADVERSARIAL-ECONOMIC-ANALYST.md` (per-hypothesis evidence + 3 beyond-charge (xv)..(xvii); (xiv) SAFE_BY_DESIGN with two INFO observations on permissionless retry LINK consumption + daily-flow takeover stuck-state recovery source for `D-42N-RETRY-RNG-LAUNCH-FAQ-01`).

**Disposition summary.** Phase 296 ran 3-skill HYBRID adversarial pass (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) against 14 charged hypotheses + 8 beyond-charge entries surfacing across MINTCLN/HRROLL/DPNERF/RETRY_LOOTBOX_RNG. Result: ZERO_FINDING after Tier-1 resolution on (xiv) — `retryLootboxRng` entropy-correlation under daily-flow-takeover composition (1 single-skill FINDING_CANDIDATE from `/zero-day-hunter` at LOW severity; other 2 skills returned SAFE_BY_DESIGN; user disposition 2026-05-18: ACCEPT_AS_DOCUMENTED — intended design per `D-297-RETRY-INTEGRATION-01` §3.C 4th conservation re-proof). Tier-2 (3-of-3 consensus) did NOT trigger. RE-PASS not triggered per `D-296-REPASS-SCOPE-01`. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry.

**(xiv) FINDING_CANDIDATE evidence excerpt (from `296-ADVERSARIAL-ZERO-DAY-HUNTER.md`).** The `/zero-day-hunter` skill surfaced (xiv) as a LOW-severity FINDING_CANDIDATE on the basis that the `retryLootboxRng()` function, when invoked during a swap-committed mid-day VRF stall composition where the daily flow has subsequently taken over the lootbox bucket (the `_finalizeLootboxRng` at `advance:1234` filling `LR_MID_DAY` with the daily-derived VRF word), yields shared entropy between lootbox-mid-day-bucket consumers and daily-jackpot consumers. The bit allocation map docstring at `advance:1157-1174` documents per-consumer bit-slices BUT the cross-composition entropy-correlation is outside the docstring's domain-separation guarantee scope.

**Suggested-remediation Options (from `/zero-day-hunter`):**
- **Option A — Documentation-only.** Tighten the `retryLootboxRng()` NatSpec / inline-comment scope-boundary documentation to explicitly call out the daily-flow-takeover entropy-correlation composition (no behavioral change; documentation-scope only). This is the default carry per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A and `D-42N-RETRY-RNG-SCOPE-DOC-01`.
- **Option B — Behavioral remediation.** Clear `LR_MID_DAY` at `_finalizeRngRequest` `isRetry` branch (behavioral remediation; the retry path would reset the lootbox bucket binding so subsequent consumers do NOT see entropy correlation with the daily VRF word). Requires user approval per `feedback_never_preapprove_contracts.md`. Deferred to next-milestone planner-handoff per `D-42N-RETRY-RNG-DOMAIN-SEP-01` if policy decision wanted.

**User disposition 2026-05-18 (verbatim from Phase 296 STATE.md row + Phase 296 LOG):** ACCEPT_AS_DOCUMENTED ("that is the intended design"). The entropy DOES correlate with daily-jackpot entropy in this specific composition, which is the documented INTENDED behavior per `D-297-RETRY-INTEGRATION-01` §3.C 4th conservation re-proof. No F-42-NN block authored. No FIX-SWEEP-NN commit landed. Three D-42N-RETRY-RNG-* deferred-decision handoffs registered to §9d Deferred-to-Future register.

**Tier resolution chain.** Per `D-296-CONSENSUS-01` two-tier consensus rule: Tier-1 (single-skill FINDING_CANDIDATE) elevates to user disposition; Tier-2 (3-of-3 consensus FINDING_CANDIDATE) elevates to F-NN block. (xiv) hit Tier-1 only (1 single-skill FINDING_CANDIDATE LOW); user disposition was ACCEPT_AS_DOCUMENTED; Tier-1 RESOLVED. Tier-2 did NOT trigger.

### 4.3. v40-v41 Carry-Forward Adversarial Surface Re-Verification

The 11-surface v40 §4.1 adversarial surface enumeration + the 10-hypothesis v41 §4.2 adversarial surface enumeration (RE-PASS) are RE_VERIFIED-NEGATIVE-scope at v42 close HEAD — the v42 audit subject (MINTCLN + HRROLL + DPNERF + RETRY_LOOTBOX_RNG) does NOT touch the v40 LootboxModule Bernoulli + WWXRP consolation + JackpotModule:2216 BAF Bernoulli + event surface unification + `_jackpotTicketRoll` keccak self-mix + whole-BURNIE floor surfaces, NOR the v41 mint-batch determinism (Phase 281) + hero-override day-index (Phase 285 + 288) + JPSURF go-nuts commitment-window surfaces. Re-verifications cited at §5 REG-01 + REG-02 + REG-04 + §7.

---

## 5. LEAN Regression Appendix (REG-01..04)

### 5a. REG-01 — v41.0 Closure-Signal Non-Widening

**PASS.** v41.0 closure signal `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` re-verified NON-WIDENING at v42 close HEAD on v41-touched surfaces NOT in v42 scope.

- **MINTCLN preserves Phase 281 cross-call seed separation.** The Phase 281 owed-salt 4th keccak input invariant `keccak256(baseKey, entropyWord, groupIdx, ownedSalt)` is preserved at v42 close via the MINTCLN owed-in-baseKey carry `keccak256(baseKey, entropyWord, groupIdx)` with `baseKey = (lvl<<224) | (queueIdx<<192) | (player<<32) | owed`. Same 256-bit seed space; pairwise-distinct hashes across multi-call drains.
- **HRROLL preserves Phase 288 `dailyIdx` structural fix.** `_rollHeroSymbol(dailyIdx, randomWord)` reads `dailyIdx` as the single-writer day anchor per Phase 288 `D-288-FIX-SHAPE-01` reference pattern (the F-41-03 cross-day determinism fix established `dailyIdx` as the controlling day key frozen across the rng-lock window).
- **Deity common-tier baseline UNCHANGED.** Common-tile `virtualCount = max(len/50, 2)` UNCHANGED post-DPNERF (only the gold-tile virtualCount changes from `max(len/50, 2)` to 1; commons preserved).

**Evidence cite.** `git diff 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4..HEAD -- contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameJackpotModule.sol` shows only the in-scope MINTCLN + HRROLL + DPNERF changes per §3.A delta-surface table; v41 fix surfaces preserved.

### 5b. REG-02 — v40.0 Closure-Signal Non-Widening

**PASS.** v40.0 closure signal `MILESTONE_V40_AT_HEAD_cd549499` re-verified NON-WIDENING at v42 close HEAD on v40-touched surfaces NOT in v42 scope.

- `DegenerusGameLootboxModule` Bernoulli + WWXRP consolation byte-identical at v42 close HEAD.
- `JackpotModule._jackpotTicketRoll` Bernoulli + keccak self-mix (post-ENT-05 refactor per Phase 278 `8a81a87c`) byte-identical.
- `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` event topic-hashes byte-identical (only `TraitsGenerated` topic-hash changes per MINTCLN-04).
- Whole-BURNIE floor at the 3 RNG-amount sites (`LootboxModule:1080` + `JackpotModule:1842` + `JackpotModule:1922`) byte-identical.

**Evidence cite.** `git diff cd549499..HEAD -- contracts/modules/DegenerusGameLootboxModule.sol --stat` returns zero LootboxModule changes; `git diff cd549499..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol | grep -E "Bernoulli|whole-BURNIE|_jackpotTicketRoll"` returns zero Bernoulli/keccak-self-mix/whole-BURNIE-floor changes at the 3 sites.

### 5c. REG-03 — v34.0 Closure-Signal Non-Widening

**PASS.** v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified NON-WIDENING at v42 close HEAD.

- TraitUtils 3 functions byte-identical.
- `JackpotBucketLib` byte-identical (HRROLL is in `JackpotModule` outside `JackpotBucketLib` reach; DPNERF is in `_randTraitTicket` outside `_pickSoloQuadrant`).
- `_pickSoloQuadrant` byte-identical.

**Evidence cite.** `git diff 6b63f6d4daf346a53a1d463790f637308ea8d555..HEAD -- contracts/libraries/TraitUtils.sol contracts/libraries/JackpotBucketLib.sol --stat` returns zero changes.

### 5d. REG-04 — Prior-Finding Spot-Check Sweep

**PASS.** Prior-finding spot-check sweep across `audit/FINDINGS-v25.0.md` through `audit/FINDINGS-v41.0.md` for v42-touched function/surface set re-verified RESOLVED or NEGATIVE-scope at v42 close HEAD.

- **MINTCLN scope** (`_raritySymbolBatch` + `processFutureTicketBatch` + `_processOneTicketEntry` + `TraitsGenerated` event) — v41 F-41-01 (mint-batch determinism HIGH; RESOLVED_AT_V41 via Phase 281 owed-salt) RE_VERIFIED RESOLVED at v42 (MINTCLN preserves the algorithmic invariant via owed-in-baseKey carry; cross-call seed separation preserved); prior v25-v40 findings on the mint-batch path NEGATIVE-scope or RESOLVED at v42.
- **HRROLL scope** (`_topHeroSymbol` → `_rollHeroSymbol` + `_applyHeroOverride` + `dailyHeroWagers`) — v41 F-41-02 (hero-override within-day HIGH with CRITICAL elevation; RESOLVED_AT_V41 via Phase 288 dailyIdx structural fix) RE_VERIFIED RESOLVED at v42 (HRROLL reads `dailyIdx` as the single-writer day anchor; Phase 288 fix preserved); v41 F-41-03 (hero-override cross-day MEDIUM-catastrophy-tier; RESOLVED_AT_V41) RE_VERIFIED RESOLVED at v42.
- **DPNERF scope** (`_randTraitTicket` + `_runJackpotEthFlow` + `payDailyCoinJackpot` + `_awardDailyCoinToTraitWinners`) — prior findings on the deity-payout path NEGATIVE-scope at v42 (DPNERF introduces new gold-tile behavior; prior surface coverage on commons-tier path unchanged).
- **RETRY_LOOTBOX_RNG scope** per `D-297-RETRY-INTEGRATION-01` (`_finalizeLootboxRng` + `rngGate` + `LR_MID_DAY` semantics + `lootboxRngPacked` storage shape + new `retryLootboxRng()` entry point) — the surface is NEW at v42; prior findings NEGATIVE-scope; the slot-drift fix in `test/fuzz/VRFStallEdgeCases.t.sol` (slot 38→37 + mapping 39→38) corrected a pre-existing TEST file bug, not a contract storage bug.

### 5e. Regression Distribution Summary

Aggregate: **4 PASS** (REG-01 + REG-02 + REG-03 + REG-04) / **0 REGRESSED** / **0 SUPERSEDED-as-verdict**. All v42-touched surfaces re-verified RESOLVED or NEGATIVE-scope across the prior-finding spot-check sweep.

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification

### 6a. Non-Promotion Ledger

Phase 296 surfaced ZERO F-42-NN-eligible candidates (ZERO_FINDING result per Phase 296 LOG); (xiv) Tier-1 was ACCEPT_AS_DOCUMENTED so no shipped-then-fixed entry to consider for KI promotion. KNOWN-ISSUES.md is UNMODIFIED at v42 close per `D-297-KI-01` (carry from v41 `D-281-KI-01` rationale: shipped-then-fixed defects are documented in §4 + §9 prose, not in KNOWN-ISSUES.md; v41 set the precedent; v42 inherits).

### 6b. KI Envelope Re-Verifications

**EXC-01 (affiliate roll non-VRF entropy).** RE_VERIFIED-NEGATIVE-scope at v42. The v42 audit subject (MINTCLN + HRROLL + DPNERF + RETRY_LOOTBOX_RNG) has zero affiliate-roll interaction. MINTCLN is in `DegenerusGameMintModule`; HRROLL + DPNERF are in `DegenerusGameJackpotModule`; RETRY_LOOTBOX_RNG is in `DegenerusGameAdvanceModule` (the rng-retry path, structurally separate from the affiliate-roll surface per KNOWN-ISSUES.md line 17). Per `D-297-KI-01`.

**EXC-02 (prevrandao fallback in `_getHistoricalRngFallback`).** RE_VERIFIED-NEGATIVE-scope at v42. The v42 audit subject has zero AdvanceModule game-over-RNG-substitution interaction. The `retryLootboxRng()` surface from Phase 296 `123f2dac` is the rng-retry path which is structurally separate from EXC-02's `_gameOverEntropy` + `_getHistoricalRngFallback` game-over surfaces per KNOWN-ISSUES.md line 29 — `retryLootboxRng()` operates on the mid-day lootbox VRF request flow (preserving the pre-advanced `lootboxRngIndex` and the buffer swap so the new VRF word lands in the same bucket the original request bound), not on the game-over entropy backfill path. Explicit distinction prose per `D-297-KI-01`.

**EXC-03 (gameover RNG substitution for mid-cycle write-buffer tickets per F-29-04).** RE_VERIFIED-NEGATIVE-scope at v42. The v42 audit subject has zero gameover-RNG-substitution interaction. The `retryLootboxRng()` surface is the rng-retry path which is structurally separate from EXC-03's gameover surfaces per KNOWN-ISSUES.md line 36 — `retryLootboxRng()` operates BEFORE the 14-day `GAMEOVER_RNG_FALLBACK_DELAY` window via a 6h cooldown, recovering swap-committed mid-day VRF stalls without invoking the gameover entropy mechanism. Explicit distinction prose per `D-297-KI-01`.

**EXC-04 (EntropyLib XOR-shift PRNG STRUCTURALLY ELIMINATED at v40 P278).** STRUCTURALLY ELIMINATED preserved at v42. Static-analysis grep confirms `EntropyLib.entropyStep` does not reappear in `contracts/` at v42 close HEAD; v40 P278 `8a81a87c` removal preserved through v41 + v42. Grep proof: `grep -r "entropyStep" contracts/` returns ZERO matches at v42 close HEAD.

### 6c. Closure Verdict

**`KNOWN_ISSUES_UNMODIFIED`** per `D-297-KI-01` default. Phase 296 surfaced zero F-42-NN-eligible candidates (ZERO_FINDING result); (xiv) Tier-1 ACCEPT_AS_DOCUMENTED disposition does NOT promote to KNOWN-ISSUES.md per `D-281-KI-01` carry rationale (shipped-then-fixed defects go in §4 + §9 prose, not KI; here (xiv) wasn't even a defect — it was an INTENDED-design composition the user dispositioned as such). KNOWN-ISSUES.md byte-identical between v41 close and v42 close.

---

## 7. Prior-Artifact Cross-Cites

### 7.1. v42.0 Phase Artifacts

**Phase 290 MINTCLN:**
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-CONTEXT.md`
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md`
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-SUMMARY.md`
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-02-SUMMARY.md`

**Phase 291 TST-MINTCLN:**
- `.planning/phases/291-mintcln-regression-fixture-tst-mintcln/291-CONTEXT.md`
- `.planning/phases/291-mintcln-regression-fixture-tst-mintcln/291-02-SUMMARY.md`

**Phase 292 HRROLL:**
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-CONTEXT.md`
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md`
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md`
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-02-SUMMARY.md`

**Phase 293 TST-HRROLL:**
- `.planning/phases/293-hrroll-regression-fixture-tst-hrroll/293-CONTEXT.md`
- `.planning/phases/293-hrroll-regression-fixture-tst-hrroll/293-02-SUMMARY.md`

**Phase 294 DPNERF:**
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-CONTEXT.md`
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md`
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md`
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-02-SUMMARY.md`

**Phase 295 TST-DPNERF:**
- `.planning/phases/295-dpnerf-regression-fixture-tst-dpnerf/` (full directory; per-plan SUMMARY artifacts)

**Phase 296 SWEEP:**
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md`
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-01-PLAN.md`
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-ADVERSARIAL-CHARGE.md`
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-ADVERSARIAL-CONTRACT-AUDITOR.md`
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-ADVERSARIAL-ZERO-DAY-HUNTER.md`
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-ADVERSARIAL-ECONOMIC-ANALYST.md`
- `.planning/phases/296-cross-surface-adversarial-sweep-sweep/296-01-ADVERSARIAL-LOG.md`

**Phase 297 TERMINAL (this milestone):**
- `.planning/phases/297-delta-audit-findings-consolidation-terminal/297-CONTEXT.md`
- `.planning/phases/297-delta-audit-findings-consolidation-terminal/297-DISCUSSION-LOG.md`
- `.planning/phases/297-delta-audit-findings-consolidation-terminal/297-01-PLAN.md`
- `.planning/phases/297-delta-audit-findings-consolidation-terminal/297-FINDINGS-DRAFT.md`
- `.planning/phases/297-delta-audit-findings-consolidation-terminal/297-FINDINGS-VERIFY.md`

### 7.2. Prior Milestone FINDINGS Cross-Cites

- `audit/FINDINGS-v41.0.md` (immediate prior; primary template; 9-phase multi-phase shape; 3 F-41-NN finding blocks; KI UNMODIFIED at close — v42 inherits) — F-41-01 RESOLVED via Phase 281 owed-salt; F-41-02 RESOLVED via Phase 288 dailyIdx; F-41-03 RESOLVED collaterally via Phase 288.
- `audit/FINDINGS-v40.0.md` (secondary template; 6-phase shape; 11 §4 surfaces; ZERO F-40-NN; KI MODIFIED at close — EXC-04 removed outright).
- `audit/FINDINGS-v39.0.md` (5 FINDINGS-verbatim-location convention reference).
- `audit/FINDINGS-v38.0.md`, `audit/FINDINGS-v37.0.md`, `audit/FINDINGS-v36.0.md`, `audit/FINDINGS-v35.0.md` (mid-milestone references; zero F-NN findings each).
- `audit/FINDINGS-v34.0.md` (TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identity baseline source for REG-03).
- `audit/FINDINGS-v33.0.md` through `audit/FINDINGS-v25.0.md` (full prior-milestone audit deliverable chain; REG-04 spot-check sweep source).

### 7.3. Notes Cross-Cites

- KNOWN-ISSUES.md (UNMODIFIED at v42 close; EXC-01..03 active entries + EXC-04 structural-elimination disposition documented in line 17 / 19 / 21 / 23 / 25 / 27 / 29 / 31 / 34 / 36 prose).
- `.planning/MILESTONES.md` (v41.0 archive entry; immediate prior reference for v42.0 archive shape at Commit 2).

### 7.4. Project-State Cross-Cites

- `.planning/ROADMAP.md` (Phase 297 entry; 5 success criteria; AUDIT-01..09 + REG-01..04 references; depends on Phases 290-296; SOURCE-TREE FROZEN attestation).
- `.planning/REQUIREMENTS.md` (AUDIT-01..09 + REG-01..04 verbatim wording; pending status table; 60 milestone-total requirement IDs).
- `.planning/STATE.md` (Phase 296 Complete marker; ready to plan Phase 297; v41.0 last-shipped block).
- `.planning/PROJECT.md` (v42.0 milestone scope + v41 audit baseline).

### 7.5. Carry-Forward Decision Anchors (Full Chain)

- **v25.0 chain:** `D-08` (5-Bucket Severity Rubric); `D-09` (KI Gating Rubric).
- **v32.0+ chain:** `D-NN-FCITE-01` → `D-41N-FCITE-01` → `D-42N-FCITE-01` → `D-297-FCITE-01` (terminal-phase zero forward-cite emission).
- **v37.0 chain:** `D-271-ADVERSARIAL-01` + `D-271-ADVERSARIAL-02` + `D-271-ADVERSARIAL-03` (3-skill PARALLEL adversarial pass `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT OF SCOPE). Instantiated by Phase 296 `D-296-CHARGE-01`.
- **v40.0 chain:** `D-40N-MINTBOOST-OUT-01` (mint-boost retention; §9d carry); `D-40N-LBX02-OUT-01` (LBX-02 fixture-coverage carry; §9d carry); `D-40N-EVT-BREAK-01` (event topic-hash break disposition; v42 instantiation via MINTCLN-04 `D-42N-EVT-BREAK-01`); `D-40N-FILES-01` → `D-41N-FILES-01` → `D-42N-FILES-01` (single canonical deliverable per milestone); `D-40N-CLOSURE-01` → `D-41N-CLOSURE-01` → `D-42N-CLOSURE-01` → `D-297-CLOSURE-01` (atomic closure flip).
- **v41.0 chain:** `D-284-SEVERITY-01` (HIGH severity default for fixed-then-shipped findings; INFO at v42 since zero F-42-NN); `D-284-KI-01` → `D-297-KI-01` (KNOWN-ISSUES.md UNMODIFIED default at close); `D-284-ADVERSARIAL-CHARGE-01` → `D-296-CHARGE-01`; `D-284-ADVERSARIAL-RE-PASS-01` → `D-296-REPASS-SCOPE-01`; `D-284-ADVERSARIAL-SCOPE-01` → `D-296-INVOKE-01`; `D-281-FIX-SHAPE-01` (owed-salt reference pattern); `D-288-FIX-SHAPE-01` (dailyIdx-anchor reference pattern).
- **v42.0 chain:** `D-42N-EVT-BREAK-01` (MINTCLN topic-hash break); `D-42N-MINTCLN-SCOPE-01` (helper-extraction handoff); `D-42N-DETERMINISM-01` (HRROLL determinism spec); `D-42N-GAS-01` (HRROLL gas acceptance threshold); `D-42N-GOLD-FLOOR-01` + `D-42N-DEITY-EV-01` + `D-42N-PATH-COVERAGE-01` (DPNERF specs); `D-294-CALLER-UNIFORM-01` (DPNERF caller-uniformity); `D-42N-KI-01` → `D-297-KI-01`; `D-42N-CLOSURE-01` → `D-297-CLOSURE-01`; `D-42N-FCITE-01` → `D-297-FCITE-01`; `D-42N-LEADER-BONUS-01` + `D-42N-FLOOR-01` + `D-42N-COLOR-ENTROPY-01` + `D-42N-CACHE-01`.
- **v42.0 Phase 296 chain:** `D-296-CHARGE-01` (14-hypothesis charge); `D-296-CONSENSUS-01` (two-tier consensus rule); `D-296-REPASS-SCOPE-01` (RE-PASS scope; not triggered); `D-296-INVOKE-01` (HYBRID skill invocation pattern); `D-296-ARTIFACT-SET-01`; `D-296-RESEARCH-AGENT-01` → `D-297-RESEARCH-AGENT-01`; `D-296-KI-01` → `D-297-KI-01`; `D-296-TASK-SPLIT-01` → `D-297-TASK-SPLIT-01`.
- **v42.0 Phase 297 chain (this phase):** `D-297-CLOSURE-01` + `D-297-DRAFT-PATH-01` + `D-297-TASK-SPLIT-01` + `D-297-RETRY-INTEGRATION-01` + `D-297-VERDICT-01` + `D-297-DEFER-01` + `D-297-RESEARCH-AGENT-01` + `D-297-ARTIFACT-SET-01` + `D-297-FINDINGS-FRONTMATTER-01` + `D-297-SECTION-PROSE-01` + `D-297-COMMIT-MESSAGE-01` + `D-297-KI-01` + `D-297-FCITE-01`.

---

## 8. Forward-Cite Closure

### 8a. Phase 297 Intra-Milestone Forward-Cite Residual Verification

Per `D-297-FCITE-01` carry of `D-42N-FCITE-01` / `D-281-FCITE-01` / `D-40N-FCITE-01` / `D-274-FCITE-01` / `D-272-FCITE-01` / `D-271-FCITE-01` + `D-253-15` step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 297 to any post-v42.0 milestone phases across scoped artifacts.

**Scoped artifacts:** `audit/FINDINGS-v42.0.md` (this deliverable, promoted at Commit 1) + `.planning/phases/297-delta-audit-findings-consolidation-terminal/297-FINDINGS-DRAFT.md` (planner-private byte-identical mirror).

**Expected grep result:** ZERO matches for any post-v42.0 milestone-version token or post-Phase-297 phase-number token across the scoped artifacts. Verified at T2 verification step Sub-check 6 + reconfirmed at T4 acceptance step.

**Allowed exceptions:** Locked-decision IDs (D-42N-* + D-297-*) carry forward via descriptive labels only. None of these IDs match the post-milestone forward-cite grep patterns.

### 8b. Phase 297 → Post-Milestone Forward-Cite Emission

Zero post-milestone references emitted. The §9d Deferred-to-Future register uses locked-decision IDs + descriptive labels only (e.g., "domain-separation policy revisit deferred"; "indexer-migration handoff"; "launch-comms FAQ"). No phase numbers, no version numbers beyond the v42.0 closure.

### 8c. Combined §8 Verdict

**FORWARD_CITE_ZERO_PASS.** Phase 297 emits zero forward-cites to post-v42.0 phases or milestones across scoped artifacts. The §9d Deferred-to-Future register routes future work through locked-decision IDs + descriptive labels per `D-297-FCITE-01` discipline.

---

## 9. Milestone Closure Attestation

### 9a. Closure Verdict

**`0 of 0 F-42-NN RESOLVED_AT_V42; 0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`** per `D-297-VERDICT-01` strict math.

- **F-42-NN finding blocks:** 0 (zero findings at v42; clean closure verdict math). Phase 296 surfaced 1 single-skill (`/zero-day-hunter`) Tier-1 FINDING_CANDIDATE LOW on (xiv); user disposition 2026-05-18 ACCEPT_AS_DOCUMENTED (intended design). No F-42-NN block authored; no FIX-SWEEP-NN commit landed; §9 verdict math counts promoted findings only per `D-297-VERDICT-01`.
- **KI-eligible promotions:** 0 of 0 (no candidate findings; no candidate KI promotions; per `D-297-KI-01` default).
- **KNOWN-ISSUES.md disposition:** UNMODIFIED at v42 close.
- **D-08 5-Bucket Severity Rubric reference:** descriptive-only at v42 (rubric definitions per §2). No F-42-NN blocks to bucket.
- **D-09 KI Gating Rubric reference:** descriptive-only at v42 (3-predicate test per §6 prose). No candidates evaluated.

### 9b. 8-Phase Wave Summary

Phases 290 (MINTCLN contract `e5665117`) + 291 (TST-MINTCLN tests `a1404efd`) + 292 (HRROLL contract `a0218952`) + 293 (TST-HRROLL tests `0cd01a9c`) + 294 (DPNERF contract initial `47936e0c` + BURNIE gap-closure amendment `38319463`) + 295 (TST-DPNERF tests `8027b16c`) + 296 (SWEEP `f2bf0767` AGENT-COMMITTED LOG bundle + mid-sweep `123f2dac` USER-APPROVED `retryLootboxRng` feature commit) + 297 (TERMINAL; SOURCE-TREE FROZEN; 2 AGENT-COMMITTED commits per `D-297-CLOSURE-01`). The 8-phase wave shape (surface-pair + sweep + terminal) is structurally COMPLETE. Closure signal: `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`.

### 9c. Closure Signal

**Closure signal:** `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`.

**5 FINDINGS verbatim locations (within `audit/FINDINGS-v42.0.md`):**
1. Frontmatter `closure_signal:` field (carries `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`).
2. Frontmatter `audit_subject_head:` field (carries the raw SHA without the `MILESTONE_V42_AT_HEAD_` prefix — the schema-mandated form per `D-297-FINDINGS-FRONTMATTER-01`).
3. §1 Audit Subject prose ("v42.0 closure HEAD is `81d7c94bc924edb3429f6dc16ee33280fc11c7c2`...the emitted `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2` signal").
4. §9b 8-Phase Wave Summary closing line ("Closure signal: `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`").
5. §9c Closure Signal section canonical mention (this line) + propagation register listing.

**3 cross-document propagation targets (atomic 5-doc closure flip at Commit 2 per `D-297-CLOSURE-01`):**
1. `.planning/ROADMAP.md` (v42.0 milestone summary section + Phase 297 line flip to `[x]` + Progress table; carries closure signal verbatim).
2. `.planning/STATE.md` (Last Shipped Milestone block rotated to v42.0; v41.0 → Prior Shipped Milestone; carries closure signal verbatim).
3. `.planning/MILESTONES.md` (v42.0 archive entry; carries closure signal verbatim).

The conventional bookkeeping pair `.planning/PROJECT.md` + `.planning/REQUIREMENTS.md` are updated atomically alongside (effecting the 5-doc closure flip per v41 P284 + v39 P274 precedent); they don't carry the closure signal string verbatim but update last-shipped-milestone reference (PROJECT.md) + requirements-complete-status entries (REQUIREMENTS.md).

### 9d. Deferred to Future Milestones

9-entry register per `D-297-DEFER-01` (locked-decision IDs + descriptive labels only; no forward-cite emission to post-v42.0 milestone phase numbers per `D-297-FCITE-01`):

1. **`D-42N-MINTCLN-SCOPE-01`** — helper-extraction handoff for MINTCLN duplicate-logic (`processFutureTicketBatch` inline loop vs `processTicketBatch` + `_processOneTicketEntry` split parallel-emit/parallel-hash duplication; `processed += take` vs `processed += writesUsed >> 1` asymmetry). Flag-only at v42 per user decision 2026-05-17; cleanup eligible for next-milestone maintenance bundle.
2. **`D-42N-EVT-BREAK-01`** — indexer-migration handoff for `TraitsGenerated` topic-hash break (off-chain, user-owned). Pre-launch posture accepts the migration as a forward-handoff; tooling lives outside the audit repo.
3. **`D-40N-LBX02-OUT-01`** — LBX-02 fixture-coverage gap carry (RE-DEFERRED per `D-40N-LBX02-OUT-01` carry chain). Analytical worst-case continues to be load-bearing per Phase 266 `GAS-01` + `feedback_gas_worst_case.md`.
4. **`D-40N-MINTBOOST-OUT-01`** — mint-boost path retention carry (`_queueTicketsScaled` + `_rollRemainder` + `rem` byte stay at `DegenerusGameMintModule.sol:1142`; deterministic dust accumulator; not RNG-driven).
5. **Game-over hardening** — descriptive label carry (no locked-decision ID; reserved for future game-over-surface milestone).
6. **`D-42N-RETRY-RNG-DOMAIN-SEP-01`** (NEW) — domain-separation policy for retryLootboxRng entropy-correlation under daily-flow-takeover composition. Option A documentation-only ACCEPT_AS_DOCUMENTED default per user 2026-05-18. Option B behavioral remediation (clear `LR_MID_DAY` at `_finalizeRngRequest` `isRetry` branch) requires user approval per `feedback_never_preapprove_contracts.md`. Default carry forward as documentation-only; planner-handoff for policy revisit if launch-posture review surfaces new disposition.
7. **`D-42N-RETRY-RNG-SCOPE-DOC-01`** (NEW) — docstring/scope-boundary observation from `/contract-auditor` MEDIUM-tier note on (xiv) [non-FINDING_CANDIDATE observation; documentation-scope only]. Deferred next-milestone if user wants to tighten the `retryLootboxRng()` NatSpec / inline-comment scope-boundary documentation to explicitly call out the daily-flow-takeover entropy-correlation composition.
8. **`D-42N-RETRY-RNG-LAUNCH-FAQ-01`** (NEW) — launch-comms FAQ entries from `/economic-analyst` INFO observations on (xiv): (a) permissionless retry LINK consumption bounded by 6h cooldown (no DoS griefing surface; bounded operational cost); (b) daily-flow takeover stuck-state recovery requires governance path (no on-chain auto-recovery for the non-swap-committed mid-day stall composition — handled by the existing 12h daily retry inside `rngGate`). Out-of-repo; user-owned communication.
9. **Superseded-baseline SURF `it.skip` cleanup + launch-posture KI policy** (combined v42-baseline carry entry per `D-281-KI-01` rationale carry). Superseded-baseline SURF cleanup RE-DEFERRED; launch-posture KI policy ("how to record shipped-then-fixed bugs in KI") deferred per `D-281-KI-01` rationale carry — the v42 audit subject didn't promote any F-42-NN candidates so the policy question doesn't materialize at v42 close; v41 P284 set the precedent (shipped-then-fixed defects go in §4 + §9 prose, not in KNOWN-ISSUES.md). Future milestone may revisit if a launch-time defect lands.

### 9.NN Commit-Readiness Register

**§9.NN.i USER-APPROVED contracts (5 commits):**
- Phase 290 MINTCLN `e5665117` — `contracts(290-02): apply MINTCLN-01..09 cleanup batch [USER-APPROVED]`.
- Phase 292 HRROLL `a0218952` — `feat(292): HRROLL — weighted-roll hero-override with ×1.5 leader bonus + no floor + cross-bonus invariance [HRROLL-01..04,06,07,08] [USER-APPROVED]`.
- Phase 294 DPNERF initial `47936e0c` — `feat(294): deity-pass gold nerf via flat-1 virtualCount on color==7 [DPNERF-01..06]`.
- Phase 294 DPNERF BURNIE gap-closure amendment `38319463` — `feat(294): extend DPNERF gold nerf to BURNIE coin path [DPNERF-02,03] [USER-APPROVED]`.
- Phase 296 retryLootboxRng `123f2dac` — `feat(296): retryLootboxRng — 6h recovery for swap-committed mid-day VRF stalls [USER-APPROVED]`.

**§9.NN.ii USER-APPROVED tests (4 commits; Phase 296 test changes folded into `123f2dac`):**
- Phase 291 TST-MINTCLN `a1404efd` — `tests(291-02): ship TST-MINTCLN-01..05 mint-cleanup regression fixture [USER-APPROVED]`.
- Phase 293 TST-HRROLL `0cd01a9c` — `test(293): HRROLL regression fixture TST-HRROLL-01..06 + JS-replay oracle [TST-HRROLL-01..06]`.
- Phase 295 TST-DPNERF `8027b16c` — `test(295): DPNERF regression fixture — TST-DPNERF-01..05 [USER-APPROVED]`.
- Phase 296 VRFStallEdgeCases.t.sol slot-drift fix + retry-coverage tests folded into `123f2dac` (per Phase 296 commit shape — single batched commit covering contract + test changes for the `retryLootboxRng` surface).

**§9.NN.iii AGENT-COMMITTED audit + planning artifacts:**
- Phase 296 LOG bundle `f2bf0767` — `docs(296): cross-surface adversarial sweep [SWEEP-01..05]` (CHARGE + 3 per-skill MDs + integrated LOG + CONTEXT + PLAN + DISCUSSION-LOG).
- Phase 297 Commit 1 — audit deliverable + planner-private bundle (this DRAFT + VERIFY + PLAN + CONTEXT + DISCUSSION-LOG + promoted `audit/FINDINGS-v42.0.md` with `81d7c94bc924edb3429f6dc16ee33280fc11c7c2` placeholder).
- Phase 297 Commit 2 — closure flip + SHA propagation + `chmod 444` (resolves `81d7c94bc924edb3429f6dc16ee33280fc11c7c2` placeholder + propagates verbatim to 5 FINDINGS locations + 3 cross-document targets + applies `chmod 444` + 5-doc atomic closure flip across ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS).

**§9.NN.iv `ADVERSARIAL_TIER_1_RESOLVED`** per `D-297-VERDICT-01`:

1 Tier-1 ACCEPTED_AS_DOCUMENTED on retryLootboxRng entropy-correlation under daily-flow-takeover composition (user disposition 2026-05-18: intended design); cited at §4.2 + §3.C 4th conservation invariant; no F-42-NN block authored; no FIX-SWEEP-NN commit landed.

**§9.NN.v `SOURCE_TREE_FROZEN`:** Phase 297 contributes ZERO `contracts/` and ZERO `test/` mutations. Verified at T4 acceptance via `git diff HEAD~2 HEAD -- contracts/ test/` returning no output.

**§9.NN.vi `KNOWN_ISSUES_UNMODIFIED`:** KNOWN-ISSUES.md byte-identical between v41 close and v42 close. Verified at T4 acceptance via `git diff HEAD~2 HEAD -- KNOWN-ISSUES.md` returning no output.

**§9.NN.vii `FORWARD_CITE_ZERO_EMISSION`:** Zero matches for any post-v42.0 milestone-version token or post-Phase-297 phase-number token across `audit/FINDINGS-v42.0.md` + `.planning/phases/297-*/297-FINDINGS-DRAFT.md` per `D-297-FCITE-01`.

**§9.NN.viii `AGENT_COMMITTED_TERMINAL`:** Phase 297 ships 2 AGENT-COMMITTED commits per `D-297-CLOSURE-01` 2-commit sequential SHA orchestration. Non-source-tree mechanical work per `feedback_no_contract_commits.md` exemption (v41 P284 + v40 P280 + v39 P274 precedent).

---

*End of audit/FINDINGS-v42.0.md.*
