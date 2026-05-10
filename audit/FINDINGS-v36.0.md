---
phase: 266-lootbox-entropy-refactor
plan: 01
milestone: v36.0
milestone_name: Lootbox-Path Entropy Refactor
head_anchor: <sha>
audit_baseline: 5db8682bd7b811437f0c1cf47e832619d1478ac6
audit_baseline_signal: MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
v33_baseline: 4ce3703d740d3707c88a1af595618120a8168399
v33_baseline_signal: MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399
deliverable: audit/FINDINGS-v36.0.md
requirements: [ENT-01, ENT-02, ENT-03, ENT-04, ENT-05, ENT-06,
               STAT-01, STAT-02, STAT-03,
               GAS-01, GAS-02,
               SURF-01, SURF-02, SURF-03, SURF-04,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
write_policy: "Phase 266 introduces 1 batched contract commit (LootboxModule refactor) + 1 batched test commit (chi² + gas + surface), both USER-APPROVED per feedback_no_contract_commits.md + feedback_batch_contract_approval.md. KNOWN-ISSUES.md modified by 1 entry per AUDIT-05 (EntropyLib XOR-shift entry rephrased to BAF-jackpot-only scope). Audit deliverable + 266-01-ADVERSARIAL-LOG + 266-01-SUMMARY + ROADMAP/STATE/MILESTONES updates AGENT-COMMITTED atomic-per-task per D-266-APPROVAL-01."
supersedes: none
status: FINAL — READ-ONLY
read_only: true
closure_signal: MILESTONE_V36_AT_HEAD_<sha>
generated_at: 2026-05-10T<HH>:<MM>:<SS>Z
---

# v36.0 Findings — Lootbox-Path Entropy Refactor

**Audit Baseline.** The audit baseline is v35.0 audit-subject HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6` (closure signal `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6` carry-forward from `audit/FINDINGS-v35.0.md` §9c). v36.0 audit subject HEAD `<sha>` (post-Phase-266 close commit; resolved at Task 20 atomic-update per RESEARCH.md Pitfall 4). Phase 266 introduces ONE contract-tree commit since the v35 baseline: `feat(266): lootbox-path entropy refactor [ENT-01..06]` (single batched user-approved commit per `feedback_batch_contract_approval.md`). Phase 266 introduces ONE test-tree commit since the v35 baseline: `test(266): chi² + gas + surface preservation [STAT-01..03 + GAS-01..02 + SURF-01..04]` (single batched user-approved commit). `contracts/libraries/EntropyLib.sol` is byte-identical between v35.0 baseline `5db8682b` and v36 HEAD (ENT-04 / SURF-01 PASS — see §4 surface (e) + §5 REG-01). `contracts/modules/DegenerusGameJackpotModule.sol` is byte-identical between v35.0 baseline `5db8682b` and v36 HEAD (SURF-02 + SURF-04 PASS — ENT-05 deferral verification). `contracts/modules/DegenerusGameMintModule.sol` is byte-identical between v35.0 baseline `5db8682b` and v36 HEAD (SURF-03 PASS).

**Scope.** Single canonical milestone-closure deliverable for v36.0 per D-266-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-265-FILES-01 / D-262 / D-257 carry-forward (9-section shape locked). Phase 266 is the sole v36.0 phase per CONTEXT.md `<domain>` (single-phase patch shape mirroring lightweight v3.x patch precedent; NOT the multi-phase v34/v35 milestone shape). Terminal phase per CONTEXT.md D-266-FCITE carry of D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 — zero forward-cites emitted from Phase 266 to any post-v36.0 milestone phases.

**Write policy.** READ-only after Task 21 atomic commit per D-266-APPROVAL-01 + D-265-CF-02 / D-262 / D-257 carry-forward chain. KNOWN-ISSUES.md modified by 1 entry per AUDIT-05: the EntropyLib XOR-shift entry is rephrased from "lootbox outcome rolls" scope to "BAF jackpot ticket rolls only" scope, reflecting the v36 lootbox-path consumption removal while preserving the BAF-jackpot xorshift consumer (ENT-05 deferral). Zero F-36-NN finding blocks per D-265-FIND-01 carry default path (default expected; AUDIT-02 6-surface adversarial sweep verdicts SAFE_*). Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — Wave 1 contract commit + Wave 2 test commit USER-APPROVED batched gates per `feedback_batch_contract_approval.md`. Per `feedback_manual_review_before_push.md`, the user reviews this deliverable's full diff before any push — final user-review gate at Task 21 before READ-only flip.

---

## 2. Executive Summary

### Closure Verdict Summary

- ENT-01: `CLOSED_AT_HEAD_<sha>` (`_rollTargetLevel` refactored to bit-sliced single-output; nextEntropy return dropped; 4 entry-point callers updated; bits[0..15] / [16..23] / [24..39] documented inline)
- ENT-02: `CLOSED_AT_HEAD_<sha>` (`_resolveLootboxRoll` 4 entropyStep callsites removed: L1548 + L1569 + L1599 replaced with bit-slices; L1585 dead WWXRP advance DELETED entirely per `feedback_no_dead_guards.md`; sub-call `_lootboxDgnrsReward` slice updated to bits[56..79])
- ENT-03: `CLOSED_AT_HEAD_<sha>` (`_lootboxTicketCount` L1635 entropyStep replaced with bits[96..119]; `_rollLootboxBoons` L1059 sub-call updated to bits[120..151])
- ENT-04: `CLOSED_AT_HEAD_<sha>` (EntropyLib.sol body BYTE-IDENTICAL vs `5db8682b` — `git diff` returns empty per SURF-01 grep-proof at §5)
- ENT-05: `DEFERRED_VERIFIED_AT_HEAD_<sha>` (BAF jackpot `_jackpotTicketRoll` L2186-2229 BYTE-IDENTICAL — SURF-02 grep-proof; future-phase candidate)
- ENT-06: `CLOSED_AT_HEAD_<sha>` (per-consumer NatSpec inline bit-budget block populated at every refactored function + unified bit-allocation map at `_resolveLootboxCommon` entry; ≥17 bit-range annotations in the final contract source)
- STAT-01: `CLOSED_AT_HEAD_<sha>` (chi² uniformity over 6 sub-roll buckets — `test/stat/LootboxEntropyDistribution.test.js`; all 6 high-df Wilson-Hilferty / low-df CHI2_CRIT_05 assertions pass)
- STAT-02: `CLOSED_AT_HEAD_<sha>` (distribution-shape uniformity-equivalence pre-/post-refactor — both pass identical chi² thresholds; specific-outcome divergence acceptable per CONTEXT.md `<deferred>` "Behavioral-replay tests")
- STAT-03: `CLOSED_AT_HEAD_<sha>` (Phase 261/264 chi² infrastructure verbatim re-declaration — `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` cross-cited from `test/stat/TraitDistribution.test.js` L48-100 + `test/stat/PerPullLevelDistribution.test.js` L78-102 origins)
- GAS-01: `CLOSED_AT_HEAD_<sha>` (per-open envelope ±300 g — theoretical worst-case derivation populated in `test/gas/LootboxOpenGas.test.js` header per `feedback_gas_worst_case.md`; empirical pin deferred per AdvanceGameGas L1014 precedent — harness-coverage gap; theoretical worst case is the load-bearing GAS-01 evidence)
- GAS-02: `CLOSED_AT_HEAD_<sha>` (advanceGame envelope ±2K — v36.0 1.99× margin invariant carries forward from Phase 264 SURF-05 evidence; `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` pinned in `test/gas/AdvanceGameGas.test.js`)
- SURF-01: `CLOSED_AT_HEAD_<sha>` (EntropyLib.sol body L1-43 byte-identical vs `5db8682b` — empty diff)
- SURF-02: `CLOSED_AT_HEAD_<sha>` (BAF jackpot `_jackpotTicketRoll` body L2186-2229 byte-identical vs `5db8682b` — empty diff; ENT-05 deferral discipline verified)
- SURF-03: `CLOSED_AT_HEAD_<sha>` (MintModule L652 `EntropyLib.hash2(entropy, rollSalt)` callsite byte-identical vs `5db8682b` — empty diff)
- SURF-04: `CLOSED_AT_HEAD_<sha>` (9 non-lootbox JackpotModule EntropyLib callsites byte-identical vs `5db8682b` — per-line modified-set walk emits zero modifications across `test/stat/SurfaceRegression.test.js` v36.0 PROTECTED_RANGES)
- AUDIT-01: `CLOSED_AT_HEAD_<sha>` (delta surface complete; every changed declaration in `contracts/modules/DegenerusGameLootboxModule.sol` vs baseline `5db8682b` enumerated with hunk-level evidence and classified per ROADMAP success criterion 1 — see §3d)
- AUDIT-02: `6 of 6 surfaces SAFE_*; 0 of 0 FINDING_CANDIDATE PROMOTED` (default expected per D-265-FIND-01 carry; `/contract-auditor` + `/zero-day-hunter` parallel adversarial pass per D-266-ADVERSARIAL-01..03 — see §4 + `266-01-ADVERSARIAL-LOG.md`)
- AUDIT-03: `CLOSED_AT_HEAD_<sha>` (lootbox payouts conservation re-proof: ETH/BURNIE/DGNRS/WWXRP distribution invariants preserved across the refactor; same bucket-share-sum × pool invariant as pre-refactor — see §3e)
- AUDIT-04: `0 new public/external mutation entry points; 0 new storage slots; 0 new admin functions; 0 new modifiers; 0 new EntropyLib helpers (ENT-04 / D-266-API-01)`
- AUDIT-05: `MILESTONE_V36_AT_HEAD_<sha>` emitted in §9c; KNOWN-ISSUES.md EntropyLib XOR-shift entry rephrased to BAF-only scope (1 entry modified under Design Decisions per `feedback_no_history_in_comments.md` discipline)
- REG-01: `1 PASS row — v35.0 closure signal MILESTONE_V35_AT_HEAD_5db8682b NON-WIDENING at v36 HEAD`
- REG-02: `1 PASS row — v34.0 closure signal MILESTONE_V34_AT_HEAD_6b63f6d4 NON-WIDENING at v36 HEAD`
- REG-03: `4 KI envelope re-verifications: EXC-01..03 NEGATIVE-scope at v36; EXC-04 RE_VERIFIED with NARROWS prose (BAF-jackpot-only after lootbox-path xorshift removal); KNOWN_ISSUES_REPHRASED (1 entry rephrased to BAF-only scope per AUDIT-05)`
- REG-04: `<N> PASS / 0 REGRESSED / 0 SUPERSEDED prior-finding spot-check rows across audit/FINDINGS-v25.0.md → audit/FINDINGS-v35.0.md`
- Combined milestone closure: `MILESTONE_V36_AT_HEAD_<sha>`

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-36-NN: 0

Default expected per D-265-FIND-01 carry. The lootbox-path entropy refactor is mathematically well-bounded: per-resolution keccak `keccak256(abi.encode(rngWord, player, day, amount))` consumes VRF-derived high-entropy bits (player cannot bias post-commit per `feedback_rng_commitment_window.md`); inline bit-slice modulo bias is documented per consumer (max 0.39% for `% 5`; ≤ 0.05% for all other slices); chi² uniformity empirically verified at STAT-01 over 6 sub-roll buckets (Wilson-Hilferty Z < 1.645 for high-df; CHI2_CRIT_05[4] = 9.488 for low-df near-offset); cumulative bit budget 152 bits / 256 available with comfortable headroom; ETH-amount-second branch uses Option A counter-tagged `seed2 = EntropyLib.hash2(seed, 1)` for collision-free chunking; cross-surface byte-identity preserved at SURF-01..04 (EntropyLib + BAF + MintModule + non-lootbox JackpotModule UNCHANGED). Severity ceiling for any v36-emitted F-36-NN: HIGH (no value extraction beyond the existing lootbox-prize space; bucket-share-sum × pool invariant under the same ETH/BURNIE/DGNRS/WWXRP distribution mechanics as pre-refactor; modulo bias bounded analytically). Most likely severity for any inline-draft finding-candidate: MEDIUM/LOW. Severity counts reconcile to §4 F-36-NN block tally line by line per ROADMAP success criterion 1.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25–v35 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-36-NN that may surface during §4 adversarial-pass disposition: HIGH ceiling (per-resolution bit-slice does not extract value; bucket-share-sum × pool invariant under the same lootbox distribution mechanics as pre-refactor; modulo bias analytically bounded; per-pull entropy VRF-derived not player-controllable). MEDIUM/LOW likely for any inline-draft finding-candidate. INFO for documentation-only items. Per D-265-FIND-01 default path, zero F-36-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone: zero F-36-NN finding blocks emit (D-265-FIND-01 carry default path) → zero KI promotion candidates from new findings. The existing KNOWN-ISSUES.md EntropyLib XOR-shift entry is REPHRASED (not promoted; not removed): scope narrows to BAF-jackpot-only after the v36 lootbox-path consumption removal (per AUDIT-05 + RESEARCH.md / CONTEXT.md `<specifics>` proposed prose). The rephrase is a SCOPE-NARROWING edit under D-09 Design Decisions, not a new promotion. See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

CONTEXT.md D-266-FCITE carry of D-265-FCITE-01 + D-262-FCITE-01 + D-257-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 266 to any post-v36.0 milestone phases. Verified at §8 Forward-Cite Closure block. Phase 266 is the sole v36.0 phase per CONTEXT.md `<domain>` (single-phase patch shape); v36.0 = Phase 266 only. Future milestones (v37.0+) ingest via fresh delta-extraction phase, not via forward-cite from v36 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v36.0 milestone closure via signal `MILESTONE_V36_AT_HEAD_<sha>`.

---

## 3. Per-Phase Sections [populated by Task 12]

## 4. Adversarial Sweep — 6-Surface Verdict Roll-Up [populated by Tasks 13-14]

## 5. Regression Appendix [populated by Task 15]

## 6. KI Gating Walk [populated by Task 16]

## 7. Prior-Artifact Cross-Cites [populated by Task 18]

## 8. Forward-Cite Closure [populated by Task 18]

## 9. Milestone Closure Attestation [populated by Tasks 19-20]
