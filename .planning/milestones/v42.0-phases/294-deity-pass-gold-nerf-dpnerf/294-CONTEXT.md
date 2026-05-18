# Phase 294: Deity-Pass Gold Nerf (DPNERF) - Context

**Gathered:** 2026-05-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Single-function body change to `_randTraitTicket` (`contracts/modules/DegenerusGameJackpotModule.sol:1707-1757`) — add a color-tier check BEFORE the existing `virtualCount = len / 50` + `if (virtualCount < 2) virtualCount = 2` logic: when `(trait >> 3) & 7 == 7` (gold color tier per the trait byte layout `(quadrant << 6) | (color << 3) | symIdx`) set `virtualCount = 1` and skip the existing `max(len/50, 2)` floor; when color tier is NOT gold (commons, `color ∈ [0..6]`) execute the v41 logic unchanged. Ship DPNERF-01..06 with intentional EV reduction (no common-tier compensation per D-42N-DEITY-EV-01); storage byte-identical (zero new slots / SSTORE / SLOAD); public ABI byte-identical (`_randTraitTicket` private; ALL 4 caller selectors / parameter types / return shapes unchanged; zero new admin / modifiers / upgrade hooks). Decision anchors D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01 + D-42N-PATH-COVERAGE-01 recorded BEFORE patch lands per `feedback_design_intent_before_deletion.md`. Wave shape: 1 USER-APPROVED batched contract commit at phase close per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. Structurally independent of Phases 290/292 but sequenced after per user ordering preference.

</domain>

<decisions>
## Implementation Decisions

### Caller-Uniformity Disposition (extends D-42N-PATH-COVERAGE-01)
- **D-294-CALLER-UNIFORM-01:** **All 4 `_randTraitTicket` callsites covered uniformly by the single-function body change.** The roadmap entry for Phase 294 names only "ETH + BURNIE coin jackpot paths" — the literal scope of the function-body change is broader. The 4 actual callsites are: (i) **L698 `_runEarlyBirdLootboxJackpot`** — early-bird lootbox jackpot trait winners (3% of `futurePrizePool` distributed at `lvl+1`; 100 winners across 4 traits = 25/trait via `_randTraitTicket(bucket, rngWord, traitId, 25, t)`); (ii) **L988 `_distributeTicketsToBucket`** (helper called by `_distributeTicketJackpot` from L637 daily ticket distribution + L652 carryover ticket distribution + L883 early-bird-post-purchase ticket distribution) — trait-bucket ticket winner selection; (iii) **L1296 `_processDailyEth`** — daily ETH jackpot trait winners (matches roadmap's "ETH jackpot trait winners via `_runJackpotEthFlow`" intent — note: `_runJackpotEthFlow` (L1142) calls `_processDailyEth` (L1232), so the roadmap's named-path resolves through L1296); (iv) **L1399 `_resolveTraitWinners`** — ETH trait-winner resolution sub-flow called from the ETH jackpot ticket-payout path. The BURNIE near-future coin jackpot path named in the roadmap resolves via `payDailyCoinJackpot` → `_awardDailyCoinToTraitWinners` → `_randTraitTicket` (the same function-body change applies). **Why:** by-construction caller-uniform — no callsite flag, no path-discrimination logic; matches REQUIREMENTS.md DPNERF-03 framing "deity earns less total EV across all 8 colors" (the "total EV" measure would not hold if the early-bird lootbox or ticket-distribution paths leaked un-nerfed gold EV). Matches roadmap's explicit "no callsite flag or path-discrimination logic" wording. **How to apply:** Plan-phase MUST enumerate all 4 callsites in `294-01-MEASUREMENT.md` §3 (Callsite Enumeration) so Phase 296 SWEEP red-teams every caller path and Phase 297 §3.A delta-surface table cites every caller path. Phase 296 SWEEP hypothesis surface MUST expand the roadmap's DPNERF hypothesis from "ETH vs BURNIE differential-behavior" to "all-4-callsite uniformity attestation" — does the gold nerf produce any incentive shift in the early-bird lootbox path (where deity-pass holders might game the lootbox window differently than the daily-jackpot window) or in the carryover-ticket-distribution path (where the gold contribution to deity's bucket-share moves across levels). Phase 297 §3.A delta-surface table MUST cite all 4 callsites by line number under the DPNERF row. Phase 297 §3.B zero-new-state grep-proof attestation already covers all 4 callsites by construction (the function body is the storage-touching surface; callers don't introduce new SSTOREs in DPNERF scope).

### Plan-Artifact Sidecar Shape
- **D-294-SIDECARS-01:** **Full 3-sidecar pattern matching Phase 290 (MINTCLN) + Phase 292 (HRROLL) precedent.** Ship `294-01-PLAN.md` (executable plan + task breakdown + USER-APPROVED contract-commit gate at close) + `294-01-DESIGN-INTENT-TRACE.md` (DPNERF-06 4-section trace: §(i) original `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2` rationale — why 2% with min-2 floor was the initial v41 design; §(ii) gold-tile concentration issue — small-bucket × 2% floor disproportionately rewards deity-pass holders on the smallest bucket tier; §(iii) compensation trade-offs — keep EV constant via commons-bump vs intentional reduction vs intentional rebias-toward-commons; §(iv) path-coverage trade-offs — both paths symmetric vs ETH-only vs all-caller-uniform per D-294-CALLER-UNIFORM-01) + `294-01-MEASUREMENT.md` (§2 storage byte-identity attestation via `forge inspect storageLayout` EMPTY diff vs v41 + Phase 292 close; §3 callsite enumeration — all 4 `_randTraitTicket` callsites cited by line number with their upstream call paths traced to top-level entry points; §4 public ABI byte-identity attestation via `forge inspect methodIdentifiers` EMPTY diff for all public/external selectors; §5 theoretical bytecode-delta estimate for the single-branch addition; §6 zero-new-state grep-proof for `_randTraitTicket` function body in DPNERF scope). All three sidecars AGENT-COMMITTED BEFORE the contract patch lands per `feedback_design_intent_before_deletion.md`. **Why:** Phase 290/292 precedent is consistent and produces clean artifact citations for Phase 296 SWEEP adversarial pass + Phase 297 §3.A delta-surface table. DPNERF is mechanically simpler than HRROLL (single-branch add vs full function replacement) but the sidecar shape symmetry across the 3 v42.0 surface phases is the more important coherence anchor. **How to apply:** Plan-phase MUST commit all 3 sidecars AGENT-COMMITTED before the USER-APPROVED contract patch lands. Decision-rationale lock-in is sidecar 1 + 2 (PLAN + DESIGN-INTENT-TRACE); attestation lock-in is sidecar 3 (MEASUREMENT). Single USER-APPROVED batched contract commit at phase close per `feedback_batch_contract_approval.md`.

### Research at Plan-Phase Disposition
- **D-294-RESEARCH-SKIP-01:** **Skip research per `feedback_skip_research_test_phases.md`.** Phase 294 has fully-specified mechanical scope: exact file path + line range (`DegenerusGameJackpotModule.sol:1707-1757`), exact branch shape (gold-tier color check before existing virtualCount logic), exact 3 decision anchors locked in roadmap (D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01 + D-42N-PATH-COVERAGE-01), exact 6 requirements DPNERF-01..06 in REQUIREMENTS.md, exact storage/ABI byte-identity invariants, and all 4 callsites enumerated in D-294-CALLER-UNIFORM-01 above. Research agents add latency with no value here. **Why:** the codebase-scout work already done in this discussion (4-callsite enumeration + upstream trace + gold-color semantic confirmation via `DegenerusTraitUtils.sol:50,97,112` + the existing `((traits[i] >> 3) & 7) == 7` idiom precedent at `DegenerusGameJackpotModule.sol:1105`) covers every input the planner would otherwise commission research to gather. **How to apply:** Run `/gsd:plan-phase 294 --skip-research`. Planner produces `294-01-PLAN.md` directly without spawning `gsd-phase-researcher`.

### NatSpec Wording for the Post-Patch Virtual-Count Comment Block
- **D-294-NATSPEC-01:** **Explicit two-tier description in the post-patch comment block.** The current comment at `DegenerusGameJackpotModule.sol:1721-1723` (`// Virtual deity entries: floor(2% of bucket tickets), minimum 2, if a deity exists for this symbol.` + the traitId layout note) becomes stale after the gold-tier branch lands (only describes the v41 common-tier path). Replace with an explicit two-tier "what IS" description per `feedback_no_history_in_comments.md`:

  ```
  // Virtual deity entries (if a deity exists for this symbol):
  //   Gold tier (color == 7): flat 1 virtual entry.
  //   Common tier (color in [0..6]): floor(2% of bucket), minimum 2.
  // traitId layout: (quadrant << 6) | (color << 3) | symIdx
  // fullSymId = quadrant * 8 + symIdx
  ```

  No "previously" / "v41 used to" / "was max(len/50, 2)" wording. No reference to D-42N-GOLD-FLOOR-01 / D-42N-DEITY-EV-01 / DPNERF / Phase 294 in the source comment. Comment describes current behavior only. **Why:** clearest "what IS" framing; both branches self-documenting at the call site; downstream readers (future audit-pass, indexer-team, junior engineer) understand the full behavior from the comment alone without cross-referencing audit artifacts. **How to apply:** Plan-phase records the exact two-tier comment shape in `294-01-PLAN.md`; executor implements verbatim. The planner may make minor formatting adjustments (e.g., line wrap, indentation matching surrounding style) but does NOT add history references or audit-decision-ID citations. The wording above is the locked target shape; deviations require checkpoint surfacing to user.

### Claude's Discretion (planner & executor latitude)

The following gray areas were considered but NOT raised for user disposition — the planner uses the sister Phase 290 + Phase 292 contract-phase patterns and resolves details at plan-phase without re-asking the user:

- **Color-extraction idiom.** Default disposition: **inline `((trait >> 3) & 7) == 7`** matching the existing precedent at `DegenerusGameJackpotModule.sol:1105` (`if (((traits[i] >> 3) & 7) == 7)` in `_pickSoloQuadrant`). Do NOT introduce a `uint8 GOLD_COLOR = 7` named constant — `feedback_frozen_contracts_no_future_proofing.md` rejects extensibility-style refactors at deploy-frozen contracts; the magic-`7` is well-established across the codebase (`DegenerusTraitUtils.sol:50,97,112,185,193,194,214` + `DegenerusGameDegeneretteModule.sol:854,855` + `DegenerusGameJackpotModule.sol:1089,1105`). Do NOT introduce a `uint8 color = (trait >> 3) & 7;` local variable cache — the gold-tier check fires once per `_randTraitTicket` invocation (not in a hot loop); the inline expression has identical bytecode cost and matches the precedent idiom. Branch shape: `if (((trait >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; }` — branch fires inside the existing `if (deity != address(0))` block (gold-tier nerf only applies when a deity exists for the symbol, matching the v41 conditional shape). Branch placement: BEFORE the `effectiveLen = len + virtualCount` computation at L1735 (the new gold branch + the existing common branch both produce `virtualCount`; the downstream `effectiveLen` arithmetic is path-uniform).

- **Bytecode-delta estimate methodology.** Default disposition: **theoretical-first attestation per `feedback_gas_worst_case.md`** — `294-01-MEASUREMENT.md` §5 derives the bytecode-delta estimate analytically (one additional `EQ` + `JUMPI` + `PUSH1` + a small constant pool entry for the new `if` branch + the gold-tier `MSTORE` for `virtualCount = 1`); expected delta ~10-30 bytes. Empirical confirmation deferred to Phase 295 TST-DPNERF (which doesn't include a gas-regression test per TST-DPNERF-01..05 enumeration — TST-DPNERF-04 is an EV regression at N=1000, not a gas regression). DPNERF runtime gas cost is negligible — single comparison + conditional store; well below any practical measurement noise floor. NO empirical-second attestation needed at Phase 294 contract phase.

- **`_pickSoloQuadrant` adjacency.** Default disposition: `_pickSoloQuadrant` at L1080-1130 is an UNRELATED gold-tier code path (it picks among gold-quadrants when multiple winning traits are gold; orthogonal to `_randTraitTicket`'s deity-virtual-count behavior). The DPNERF patch DOES NOT touch `_pickSoloQuadrant`. Plan-phase MUST verify by `forge inspect storageLayout` + line-by-line diff confirmation that the `_pickSoloQuadrant` body is byte-identical post-patch — sister-function adjacency to the patch scope, not in-scope.

- **NatSpec on `_randTraitTicket` function-level docstring.** Default disposition: keep the existing function-level docstring at L1706 (`/// @dev Selects random winners from a trait's ticket pool, returning both addresses and indices.`) unchanged. The DPNERF change is internal-behavior-only; the function's contract (input/output shape, return values, semantic role) is preserved. No NatSpec change at the function header; only the inline comment block describing virtual-entry semantics changes per D-294-NATSPEC-01.

- **Decision-anchor citation in source comments.** Default disposition: NO citation of D-42N-GOLD-FLOOR-01 / D-42N-DEITY-EV-01 / D-42N-PATH-COVERAGE-01 / D-294-CALLER-UNIFORM-01 in `contracts/` source files. Per `feedback_no_history_in_comments.md`: comments describe what IS, not why-it-was-decided. Audit-decision IDs live in the planning artifacts (`.planning/`) + the v42.0 audit deliverable (`audit/FINDINGS-v42.0.md`); not in source.

- **`KNOWN-ISSUES.md` posture for Phase 294.** Default disposition: UNMODIFIED at Phase 294 (mirrors D-281-KI-01 + D-291-KI-01 + D-293-STALE-VIEW-01 disposition for surface-mutation phases that don't surface new known-issue candidates). The DPNERF nerf is intentional EV reduction (not a bug fix), so no KI promotion candidates surface from Phase 294 contract-commit. Phase 296 SWEEP may surface KI candidates from the all-caller adversarial pass; if so, those land at Phase 297 terminal closure-flip per D-42N-KI-01 disposition.

- **Single USER-APPROVED batched contract commit at phase close.** Per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`: ONE batched commit at close (single-function body change + the inline comment-block rewrite in one diff). No `git push`. Executor presents the diff to the user for explicit review before commit. Commit message format mirrors Phase 290 + Phase 292 contract commits: `feat(294): deity-pass gold nerf via flat-1 virtualCount on color==7 [DPNERF-01..06]`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Goal & Requirements
- `.planning/ROADMAP.md` line 41 — Phase 294 entry (success criteria 1–5; DPNERF-01..06 algorithm spec; D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01 + D-42N-PATH-COVERAGE-01 anchors; storage/ABI byte-identity invariants; structurally independent of Phases 290/292)
- `.planning/ROADMAP.md` lines 197-210 — Phase 294 detail block (Goal + Depends + Requirements + 5 Success Criteria)
- `.planning/REQUIREMENTS.md` lines 80-87 — DPNERF-01..06 detail (locked requirement set; do NOT expand scope)
- `.planning/REQUIREMENTS.md` lines 22-27 — DPNERF out-of-scope items (common-tier compensation excluded; storage/ABI excluded; boon distribution unchanged; deity-pass purchase pricing unchanged; soulbound NFT minting unchanged)
- `.planning/PROJECT.md` — v42.0 milestone goal + audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`
- `.planning/STATE.md` — Phase 294 stopped_at marker + last_activity 2026-05-17

### Contract Source (load-bearing for the patch)
- `contracts/modules/DegenerusGameJackpotModule.sol:1707-1757` — `_randTraitTicket(address[][256] storage traitBurnTicket_, uint256 randomWord, uint8 trait, uint8 numWinners, uint8 salt) private view returns (address[] memory, uint256[] memory)` — patch target. Body adds the gold-tier branch BEFORE the existing `virtualCount = len / 50` + `if (virtualCount < 2) virtualCount = 2` logic at L1729-1732.
- `contracts/modules/DegenerusGameJackpotModule.sol:1721-1733` — current virtual-entry comment block + the `fullSymId` + `deity` + `virtualCount` computation; comment block rewritten per D-294-NATSPEC-01; virtualCount computation gains the gold-tier branch
- `contracts/modules/DegenerusGameJackpotModule.sol:1105` — existing gold-tier extraction idiom (`if (((traits[i] >> 3) & 7) == 7)` in `_pickSoloQuadrant`) — reuse exact bit-extraction pattern for the new DPNERF branch
- `contracts/modules/DegenerusGameJackpotModule.sol:698` — `_runEarlyBirdLootboxJackpot` callsite of `_randTraitTicket` (callsite 1 of 4 per D-294-CALLER-UNIFORM-01)
- `contracts/modules/DegenerusGameJackpotModule.sol:988` — `_distributeTicketsToBucket` callsite of `_randTraitTicket` (callsite 2 of 4; helper called by `_distributeTicketJackpot` from L637/L652/L883)
- `contracts/modules/DegenerusGameJackpotModule.sol:1296` — `_processDailyEth` callsite of `_randTraitTicket` (callsite 3 of 4; the daily ETH jackpot trait-winner selection)
- `contracts/modules/DegenerusGameJackpotModule.sol:1399` — `_resolveTraitWinners` callsite of `_randTraitTicket` (callsite 4 of 4; ETH trait-winner resolution sub-flow)
- `contracts/modules/DegenerusGameJackpotModule.sol:1816+` — `_awardDailyCoinToTraitWinners` (the BURNIE near-future coin jackpot path that ultimately reaches `_randTraitTicket` via its trait-bucket sampling)
- `contracts/storage/DegenerusGameStorage.sol` — storage layout target for byte-identity attestation (zero new slots per DPNERF-04)
- `contracts/DegenerusTraitUtils.sol:50,97,112,214` — gold = color 7 semantic confirmation (codebase canonical reference for the trait byte layout; `scaled == 14 → gold (color 7)` mapping)
- `contracts/modules/DegenerusGameDegeneretteModule.sol:854-859` — gold-tier extraction idiom precedent (`Counts gold (color == 7) quadrants in a packed ticket. Color tier occupies bits 5-3 of each per-quadrant byte; gold is the highest...`)

### Sister Phase Artifacts (pattern reference)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-PLAN.md` — pattern for `294-01-PLAN.md` shape (executable plan + task breakdown + USER-APPROVED contract-commit gate at close)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` — pattern for `294-01-DESIGN-INTENT-TRACE.md` (DPNERF-06 4-section trace shape; AGENT-COMMITTED pre-patch gate per `feedback_design_intent_before_deletion.md`; planning-doc historical-rationale exemption noted at top)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` — pattern for `294-01-MEASUREMENT.md` (storage byte-identity attestation via `forge inspect storageLayout` diff + public ABI byte-identity via `forge inspect methodIdentifiers` diff + theoretical bytecode-delta estimate + callsite-enumeration table)
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md` — sister HRROLL design-intent trace template; reference for the DPNERF-06 4-section trace structure (i orig-rationale + ii issue + iii compensation-trade-offs + iv path-coverage)
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md` — sister HRROLL measurement template; reference for storage-byte-identity attestation methodology + callsite-enumeration section
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-CONTEXT.md` — sister HRROLL context; D-42N-GAS-01 + D-42N-COLOR-ENTROPY-01 + D-42N-DETERMINISM-01 precedent for the decision-anchor recording pattern
- `.planning/phases/293-hrroll-regression-fixture-tst-hrroll/293-CONTEXT.md` — sister TST-HRROLL context (Phase 293 is the test surface for HRROLL; Phase 295 will follow the same pattern for TST-DPNERF — Phase 294 should leave clean handoff artifacts)

### Inherited Decision Anchors (carry-forward; do NOT re-derive)
- **v41 Phase 281 D-281-FIX-SHAPE-01** — owed-salt cross-call seed-separation pattern (referenced in DPNERF audit-story for completeness; DPNERF doesn't touch the mint-batch determinism path)
- **v41 Phase 288 D-288-FIX-SHAPE-01** — `dailyIdx` structural anchor as single-writer day key (referenced for completeness; DPNERF doesn't touch the hero-override day-index path)
- **v40 D-40N-EVT-BREAK-01** — breaking-topic-hash precedent (NOT applicable to Phase 294 — DPNERF changes no events; cite for completeness)
- **v34 D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03** — 3-skill PARALLEL adversarial spawn pattern (Phase 296 SWEEP will red-team DPNERF alongside MINTCLN + HRROLL; per D-294-CALLER-UNIFORM-01 the SWEEP MUST cover ALL 4 callsites, not just the 2 named in the roadmap)
- **v34 D-271-ADVERSARIAL-02** — `/degen-skeptic` OUT OF SCOPE (carry-forward to Phase 296)
- **v42 D-42N-MILESTONE-OPEN-01** — v42.0 milestone open at v41 close HEAD `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`

### Audit Methodology Feedback (enforce at plan-phase)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_skip_research_test_phases.md` — D-294-RESEARCH-SKIP-01: skip research; plan directly
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md` — single USER-APPROVED batched contract commit at phase close
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md` — `contracts/` mutation requires USER approval per `feedback_never_preapprove_contracts.md`
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md` — DPNERF contract patch NOT pre-approved; executor surfaces the diff for explicit user review before commit
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md` — executor presents the contract diff for explicit user approval before commit
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md` — DPNERF-06 4-section trace REQUIRED in `294-01-DESIGN-INTENT-TRACE.md` BEFORE contract patch lands
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_dead_guards.md` — no extensibility-style refactors (no `GOLD_COLOR` named constant; no `color` local-var cache)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_frozen_contracts_no_future_proofing.md` — no extensibility hooks; ship the locked branch shape
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md` — D-294-NATSPEC-01: comment describes what IS (both branches); no "previously" / "v41 used to" / "was max(len/50, 2)" wording
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md` — bytecode-delta theoretical-first attestation in `294-01-MEASUREMENT.md` §5; no empirical-second attestation needed (no gas-regression test in TST-DPNERF-01..05 scope)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md` — NOT applicable to Phase 294 (DPNERF doesn't introduce a new RNG consumer; `_randTraitTicket`'s `randomWord` consumption pattern unchanged)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md` — NOT applicable to Phase 294 (DPNERF doesn't change any RNG commitment-window invariant; the gold-tier branch is deterministic on `trait` which is already committed at VRF-request time by the upstream `_rollWinningTraits` consumer)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_contract_locations.md` — read contracts from `contracts/` directory only (stale copies exist elsewhere)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_contractaddresses_policy.md` — `ContractAddresses.sol` modifiable; every other `contracts/*.sol` needs explicit approval (DPNERF patch lands in `contracts/modules/DegenerusGameJackpotModule.sol` — explicit USER approval required)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`((trait >> 3) & 7) == 7` idiom** — established at `DegenerusGameJackpotModule.sol:1105` in `_pickSoloQuadrant`; reuse verbatim for the new DPNERF branch
- **Trait byte layout** `(quadrant << 6) | (color << 3) | symIdx` — documented at `DegenerusGameJackpotModule.sol:1722-1723` (existing comment block) + reaffirmed in DPNERF-01 success criterion 1; gold = color 7 confirmed via `DegenerusTraitUtils.sol:50,97,112,214` + `DegenerusGameDegeneretteModule.sol:854-859`
- **3-sidecar plan-artifact pattern** — Phase 290 + Phase 292 precedent: PLAN + DESIGN-INTENT-TRACE + MEASUREMENT, all AGENT-COMMITTED pre-patch; reuse for Phase 294 per D-294-SIDECARS-01
- **Single USER-APPROVED batched contract commit** — `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`; reuse verbatim
- **`forge inspect storageLayout` + `forge inspect methodIdentifiers` byte-identity attestation** — Phase 290 + Phase 292 measurement pattern; reuse for Phase 294 §2 + §4

### Established Patterns
- **Inline gold-tier check** — `_pickSoloQuadrant` (L1105) uses `if (((traits[i] >> 3) & 7) == 7)` inline (no local variable cache, no named constant); reuse pattern for DPNERF branch
- **Decision-anchor recording BEFORE patch** — `feedback_design_intent_before_deletion.md` + DPNERF-06; 3 anchors locked in roadmap + 4 sub-anchors locked in this CONTEXT (D-294-CALLER-UNIFORM-01 + D-294-SIDECARS-01 + D-294-RESEARCH-SKIP-01 + D-294-NATSPEC-01); planner produces the design-intent trace sidecar before the contract patch lands
- **Theoretical-first bytecode/gas attestation** — `feedback_gas_worst_case.md`; analytical derivation in `294-01-MEASUREMENT.md` §5; no empirical-second confirmation at Phase 294 (no gas-regression test in Phase 295 TST-DPNERF scope)
- **Comment-block "what IS" rewrite** — `feedback_no_history_in_comments.md`; D-294-NATSPEC-01 locks the two-tier explicit description shape
- **Phase 296 SWEEP coverage extension** — D-294-CALLER-UNIFORM-01 extends the SWEEP hypothesis surface from "ETH vs BURNIE differential-behavior" to "all-4-callsite uniformity attestation"; Phase 296 PLAN MUST cite this CONTEXT.md when expanding the DPNERF hypothesis list

### Integration Points
- **Patch lands in** `contracts/modules/DegenerusGameJackpotModule.sol` (single file mutation per DPNERF scope)
- **Comment-block rewrite** at L1721-1723 (3 lines current → 5 lines target per D-294-NATSPEC-01)
- **Branch addition** inside the `if (deity != address(0))` block at L1729 (BEFORE the existing `virtualCount = len / 50` + `if (virtualCount < 2) virtualCount = 2` logic); gold branch `if (((trait >> 3) & 7) == 7) { virtualCount = 1; } else { ... existing v41 logic ... }`
- **No callsite mutations** — single function-body change reaches all 4 callsites by construction per D-294-CALLER-UNIFORM-01
- **Storage layout** — zero changes per DPNERF-04; `forge inspect storageLayout` EMPTY diff vs v41 close + Phase 292 close attested in `294-01-MEASUREMENT.md` §2
- **Public ABI** — zero changes per DPNERF-05; `forge inspect methodIdentifiers` EMPTY diff vs v41 close + Phase 292 close attested in `294-01-MEASUREMENT.md` §4
- **Downstream Phase 295** — TST-DPNERF-01..05 regression fixture references Phase 294 audit-subject commit + the 4-callsite enumeration from D-294-CALLER-UNIFORM-01 (TST-DPNERF-01 + TST-DPNERF-02 + TST-DPNERF-03 implicitly cover callsites 3 + 4 + the BURNIE path via natural production-path invocation; TST-DPNERF-05 covers the non-deity branch which is path-uniform across all 4 callsites; the early-bird-lootbox callsite (1) and the ticket-distribution callsite (2) are NOT explicitly covered by TST-DPNERF — Phase 296 SWEEP attests their behavior per D-294-CALLER-UNIFORM-01 SWEEP scope expansion)
- **Downstream Phase 296** — SWEEP 3-skill PARALLEL adversarial pass red-teams ALL 4 callsites per D-294-CALLER-UNIFORM-01; hypothesis surface expanded from roadmap's "ETH vs BURNIE differential-behavior" to "all-4-callsite uniformity + incentive-shift across early-bird lootbox + carryover-ticket-distribution paths"
- **Downstream Phase 297** — §3.A delta-surface table cites all 4 callsites under the DPNERF row; §3.B zero-new-state grep-proof attestation covers the function body (the storage-touching surface) by construction; §3.C conservation re-proof for DPNERF: "gold-tile virtualCount = 1; common-tile UNCHANGED at `max(len/50, 2)`; all 4 callsites uniform"

### Out-of-Scope Source-Tree Surfaces (planner MUST NOT touch)
- `contracts/modules/DegenerusGameJackpotModule.sol:1080-1130` `_pickSoloQuadrant` — UNRELATED gold-tier code path (picks among gold-quadrants when multiple winning traits are gold); orthogonal to `_randTraitTicket`'s deity-virtual-count behavior; byte-identical post-patch attestation required in `294-01-MEASUREMENT.md`
- `contracts/modules/DegenerusGameJackpotModule.sol` (everything outside L1721-1733) — adjacent code paths byte-identical
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — out of DPNERF scope (the boon distribution + deity-pass tier-shift flow `BP_DEITY_PASS_TIER_SHIFT` is explicitly excluded per REQUIREMENTS.md line 25)
- `contracts/modules/DegenerusGameWhaleModule.sol` — out of DPNERF scope (deity-pass purchase pricing `DEITY_PASS_BASE` excluded per REQUIREMENTS.md line 26)
- `contracts/DegenerusDeityPass.sol` — out of DPNERF scope (soulbound NFT minting excluded per REQUIREMENTS.md line 27)
- `contracts/modules/DegenerusGameBoonModule.sol` — out of DPNERF scope (boon distribution flow excluded per REQUIREMENTS.md line 25)
- `contracts/storage/DegenerusGameStorage.sol` — zero storage layout changes per DPNERF-04
- `contracts/interfaces/IDegenerusGameModules.sol` — zero public ABI changes per DPNERF-05
- `test/` (entire tree) — zero `test/` mutations at Phase 294 (TST-DPNERF ships at Phase 295)
- `KNOWN-ISSUES.md` — UNMODIFIED per D-281-KI-01 + D-291-KI-01 + D-293-STALE-VIEW-01 disposition pattern for surface-mutation phases
- `audit/FINDINGS-v42.0.md` — does not yet exist; closure-flip happens at Phase 297 terminal phase

</code_context>

<specifics>
## Specific Ideas

- **Exact branch shape** (locked at D-294-NATSPEC-01 + Claude's-Discretion color-extraction idiom): inside the `if (deity != address(0))` block at current L1729, replace the two lines `virtualCount = len / 50;` + `if (virtualCount < 2) virtualCount = 2;` with the branched form:
  ```solidity
  if (((trait >> 3) & 7) == 7) {
      virtualCount = 1;
  } else {
      virtualCount = len / 50;
      if (virtualCount < 2) virtualCount = 2;
  }
  ```
  Gold-tier executes the `virtualCount = 1` branch; commons execute the unchanged v41 logic.

- **Exact comment-block shape** (locked at D-294-NATSPEC-01): replace the current 3-line block at L1721-1723 with the 5-line "what IS" two-tier description:
  ```
  // Virtual deity entries (if a deity exists for this symbol):
  //   Gold tier (color == 7): flat 1 virtual entry.
  //   Common tier (color in [0..6]): floor(2% of bucket), minimum 2.
  // traitId layout: (quadrant << 6) | (color << 3) | symIdx
  // fullSymId = quadrant * 8 + symIdx
  ```

- **All 4 callsite enumeration for `294-01-MEASUREMENT.md` §3** (locked at D-294-CALLER-UNIFORM-01):
  | Callsite | Function | Path | Top-Level Entry |
  |---|---|---|---|
  | L698 | `_runEarlyBirdLootboxJackpot` | Early-bird lootbox jackpot | Daily jackpot cycle (purchase-phase tickets) |
  | L988 | `_distributeTicketsToBucket` (helper) | Trait-bucket ticket distribution | `_distributeTicketJackpot` via L637 daily-tickets / L652 carryover-tickets / L883 early-bird-post-purchase-tickets |
  | L1296 | `_processDailyEth` | Daily ETH jackpot trait winners | `_runJackpotEthFlow` (L1142) → `_processDailyEth` (L1232) → `_randTraitTicket` (L1296) |
  | L1399 | `_resolveTraitWinners` | ETH trait-winner resolution sub-flow | Called from `_processDailyEth` ticket-payout sub-path |

- **BURNIE near-future coin jackpot path** named in the roadmap resolves via `payDailyCoinJackpot` (L1767) → `_awardDailyCoinToTraitWinners` (L1816+) → trait-bucket sampling → ultimately `_randTraitTicket` (the same function-body change applies; resolves through callsite 2 or 3 depending on the BURNIE distribution sub-shape).

- **`_pickSoloQuadrant` adjacency** (Claude's Discretion): the function at L1080-1130 uses `((traits[i] >> 3) & 7) == 7` for gold-tier extraction (the exact idiom DPNERF reuses); body byte-identical post-patch; `294-01-MEASUREMENT.md` §2 attests this via the storage layout EMPTY diff + line-by-line confirmation.

- **Decision-anchor citation** in the source comment block: NONE per D-294-NATSPEC-01 + `feedback_no_history_in_comments.md`. No `// D-42N-GOLD-FLOOR-01` / `// DPNERF-01` / `// Phase 294` markers in the source comment.

- **Bytecode-delta estimate** for `294-01-MEASUREMENT.md` §5: theoretical ~10-30 byte addition (one `EQ` + `JUMPI` + small constant for the gold-color check; one `MSTORE` for the gold-tier `virtualCount = 1`; remaining v41 logic preserved verbatim in the `else` branch). No empirical second-pass needed; runtime gas cost is negligible (single comparison + conditional store; well below practical measurement noise).

- **Commit message format**: `feat(294): deity-pass gold nerf via flat-1 virtualCount on color==7 [DPNERF-01..06]` (mirrors Phase 290 + Phase 292 contract commit patterns).

</specifics>

<deferred>
## Deferred Ideas

- **Common-tier compensation logic** — explicitly excluded per D-42N-DEITY-EV-01 + REQUIREMENTS.md line 22. The DPNERF nerf is intentional EV reduction (not internal redistribution); deity-pass holders lose total EV across all 8 colors with no commons-bump compensation. NOT a Phase 294 in-scope item; NOT a Phase 296 SWEEP candidate; NOT a Phase 297 finding candidate.

- **Deity-pass holder economic adjustment** — if Phase 296 SWEEP surfaces that the intentional EV reduction destabilizes deity-pass holder behavior in unintended ways (e.g., secondary-market deity-pass price collapses; deity-pass holders pivot to non-gold gameplay strategies that destabilize commons-tier dynamics), the SWEEP finding lands as a F-42-NN candidate at Phase 297 §3 + 296 ADVERSARIAL-LOG.md per D-284-ADVERSARIAL-RE-PASS-01 RE-PASS posture. Default zero-finding outcome assumed at this CONTEXT-recording stage.

- **`GOLD_COLOR = 7` named constant extraction** — explicitly NOT introduced per `feedback_frozen_contracts_no_future_proofing.md`. Magic-`7` is well-established (10+ source citations across the codebase). If a v43+ maintenance bundle proliferates gold-tier extraction sites, a named constant + a refactor pass could be considered; not a v42.0 milestone candidate.

- **`color` local-variable cache** — explicitly NOT introduced (Claude's Discretion). The gold-tier check fires once per `_randTraitTicket` invocation (not in a hot loop); inline expression has identical bytecode cost; precedent at L1105 uses inline. v43+ if `_randTraitTicket` evolves to need multiple color-derived branches.

- **`_pickSoloQuadrant` refactor** — orthogonal v43+ candidate. The function shares the gold-tier extraction idiom but the deity-virtual-count adjustment doesn't apply to its scope. Not a Phase 294 / Phase 296 / Phase 297 surface.

- **Empirical gas/bytecode regression test** — not in Phase 295 TST-DPNERF-01..05 scope (TST-DPNERF-04 is an EV regression at N=1000, not a gas regression). Theoretical-first attestation in `294-01-MEASUREMENT.md` §5 is sufficient; no escalation path needed (unlike Phase 292's D-42N-GAS-01 ~+5-8K worst-case where empirical confirmation matters). v43+ if a future deity-virtual-count change has non-negligible gas impact.

- **Phase 296 SWEEP hypothesis expansion beyond D-294-CALLER-UNIFORM-01** — the SWEEP DPNERF hypothesis surface MAY widen during execution if the 3-skill PARALLEL pass surfaces novel attack vectors. Default zero-widening assumed; D-294-CALLER-UNIFORM-01 fixes the all-4-callsite scope expansion; further widening (e.g., cross-symbol incentive shifts, multi-day deity-pass holder behavior models) is SWEEP-discretion at Phase 296 execution.

- **`_runEarlyBirdLootboxJackpot` independent regression** — the early-bird lootbox callsite (1 of 4) is NOT explicitly covered by Phase 295 TST-DPNERF-01..05. Phase 296 SWEEP attests its behavior per D-294-CALLER-UNIFORM-01. If a v43+ test-maintenance bundle expands TST-DPNERF to include early-bird-specific regression coverage, that's a future-phase candidate; not v42.0 scope.

</deferred>

---

*Phase: 294-deity-pass-gold-nerf-dpnerf*
*Context gathered: 2026-05-17*
