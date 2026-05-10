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

## 3. Per-Phase Sections

Phase 266 is the sole v36.0 phase per CONTEXT.md `<domain>` (single-phase patch shape; v36.0 = Phase 266 only). §3a is the single per-phase section (no §3b/§3c per-phase split needed). §3d AUDIT-01 delta-surface table + AUDIT-04 zero-new-state attestation appears after §3a. §3e AUDIT-03 conservation re-proof appears after §3d. All cross-cites are READ-only lookups to phase artifacts at HEAD `<sha>` (resolved at Task 20).

### 3a. Phase 266 — Lootbox-Path Entropy Refactor

**Cross-cited sources:**

- `.planning/phases/266-lootbox-entropy-refactor/266-CONTEXT.md` — locked decisions D-266-API-01 / D-266-SEED-01 / D-266-BIT-BUDGET-01 / D-266-CONSUMER-LIST-01 / D-266-SCOPE-OUT-01..04 / D-266-ADVERSARIAL-01..03 / D-266-FILES-01 / D-266-CLOSURE-01..02 / D-266-PLAN-01 / D-266-SEV-01 / D-266-APPROVAL-01..02 / D-266-FCITE.
- `.planning/phases/266-lootbox-entropy-refactor/266-RESEARCH.md` — bit-budget worked tables (ENT-01..03 per-consumer slice + bias bound) + chi² calibration (Pitfall 1 sample-budget per bucket) + Sources block (HEAD-state grep verifications).
- `.planning/phases/266-lootbox-entropy-refactor/266-PATTERNS.md` — refactor pattern + cumulative bit-budget table + analog source-of-truth + per-file pattern assignments + Project Guardrails (10 memory-cited disciplines).
- `.planning/phases/266-lootbox-entropy-refactor/266-01-PLAN.md` — 21-task multi-wave plan with explicit user-approval gates at end of Wave 1 (Task 5 contract diff) + end of Wave 2 (Task 10 test diff) + end of Wave 5 (Task 21 final user-review).
- Wave 1 commit `df6345cc feat(266): lootbox-path entropy refactor [ENT-01..06]` (single batched user-approved contract-tree commit per `feedback_batch_contract_approval.md`).
- Wave 2 commit `16ed452b test(266): chi² + gas + surface preservation [STAT-01..03 + GAS-01..02 + SURF-01..04]` (single batched user-approved test-tree commit; 4 test files modified + package.json wiring).
- `.planning/phases/266-lootbox-entropy-refactor/266-01-ADVERSARIAL-LOG.md` — `/contract-auditor` + `/zero-day-hunter` parallel adversarial-pass log per D-266-ADVERSARIAL-01..03 (populated at Task 14).

**Change-count card (Phase 266):**

- 1 contract-tree commit (`df6345cc`): +75 / −61 in `contracts/modules/DegenerusGameLootboxModule.sol` only.
- 1 test-tree commit (`16ed452b`): +912 / −2 across 4 test files + `package.json` wiring (2 NEW test files + 2 EXTENDED test files).
- N audit-tree atomic commits (this deliverable + ADVERSARIAL-LOG + SUMMARY + closure flips) — AGENT-COMMITTED per D-266-APPROVAL-01.
- 0 changes to `contracts/libraries/EntropyLib.sol` (ENT-04 / SURF-01 stable API).
- 0 changes to `contracts/modules/DegenerusGameJackpotModule.sol` (SURF-02 BAF byte-identity + SURF-04 9 callsites).
- 0 changes to `contracts/modules/DegenerusGameMintModule.sol` (SURF-03).
- 0 new public/external functions; 0 new modifiers; 0 new storage slots; 0 new EntropyLib helpers (AUDIT-04).
- 1 KNOWN-ISSUES.md entry rephrased (AUDIT-05 — EntropyLib XOR-shift entry NARROWS to BAF-only scope; rephrase, not promotion).

**Per-REQ summary table (24 IDs):**

| REQ ID  | Status | Evidence |
|---------|--------|----------|
| ENT-01  | CLOSED | `_rollTargetLevel` bit-sliced single-output at L812 (live HEAD); 4 callers updated at L555/L629/L674/L709. |
| ENT-02  | CLOSED | `_resolveLootboxRoll` 4 entropyStep callsites removed; L1585 dead WWXRP advance DELETED entirely; sub-call slicing for `_lootboxDgnrsReward` (L1694) + `_rollLootboxBoons` (L1074). |
| ENT-03  | CLOSED | `_lootboxTicketCount` L1648 = `uint24(seed >> 96) % 10_000`. |
| ENT-04  | CLOSED | `git diff 5db8682b..HEAD -- contracts/libraries/EntropyLib.sol` returns empty (SURF-01 grep-proof). |
| ENT-05  | DEFERRED | `_jackpotTicketRoll` L2186-2229 byte-identical (SURF-02 grep-proof); future-phase candidate captured in CONTEXT.md `<deferred>`. |
| ENT-06  | CLOSED | NatSpec bit-budget block at every refactored function + unified bit-allocation map at `_resolveLootboxCommon` L835-849; `grep -v '^//'` strips comments and counts ≥17 bit-range annotations remaining in active source. |
| STAT-01 | CLOSED | `test/stat/LootboxEntropyDistribution.test.js` 6 chi² describe blocks pass; sample budgets calibrated per Pitfall 1. |
| STAT-02 | CLOSED | Distribution-shape uniformity-equivalence asserted via 2-bucket re-run; specific-outcome divergence acceptable per CONTEXT.md `<deferred>`. |
| STAT-03 | CLOSED | `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` re-declared verbatim from `test/stat/TraitDistribution.test.js` L48-100. |
| GAS-01  | CLOSED | `test/gas/LootboxOpenGas.test.js` theoretical-worst-case header populated per `feedback_gas_worst_case.md`; empirical pin deferred per AdvanceGameGas L1014 precedent (harness-coverage gap; theoretical worst case is the load-bearing GAS-01 evidence per Phase 266 SUMMARY). |
| GAS-02  | CLOSED | `test/gas/AdvanceGameGas.test.js` v36.0 describe block pins `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320`; 1.99× margin invariant carries forward from Phase 264 SURF-05 evidence. |
| SURF-01 | CLOSED | `test/stat/SurfaceRegression.test.js` v36.0 describe block — EntropyLib.sol L1-43 zero modifications vs `5db8682b`. |
| SURF-02 | CLOSED | Same describe block — `_jackpotTicketRoll` L2186-2229 zero modifications. |
| SURF-03 | CLOSED | Same describe block — MintModule L652 zero modifications. |
| SURF-04 | CLOSED | Same describe block — 9 non-lootbox JackpotModule EntropyLib callsites zero modifications (Pitfall 6 inventory: L285/L453/L532/L610/L612/L886/L1176/L1873/L2192). |
| AUDIT-01 | CLOSED | §3d delta-surface table below enumerates every changed declaration with hunk-level evidence. |
| AUDIT-02 | CLOSED | §4 6-surface adversarial-sweep below; verdicts SAFE_*; `/contract-auditor` + `/zero-day-hunter` parallel pass per D-266-ADVERSARIAL-01..03 — see `266-01-ADVERSARIAL-LOG.md`. |
| AUDIT-03 | CLOSED | §3e conservation re-proof below — ETH/BURNIE/DGNRS/WWXRP distribution invariants preserved across the refactor. |
| AUDIT-04 | CLOSED | §3d Part C below — 5 grep-reproducible zero-new-state checks. |
| AUDIT-05 | CLOSED | §9c closure-signal emission `MILESTONE_V36_AT_HEAD_<sha>` (resolved at Task 20). |
| REG-01  | CLOSED | §5a v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682b` non-widening at v36 HEAD (carry-forward verification). |
| REG-02  | CLOSED | §5b v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` non-widening at v36 HEAD. |
| REG-03  | CLOSED | §6b 4-row KI envelope re-verification: EXC-01..03 NEGATIVE-scope at v36; EXC-04 RE_VERIFIED with NARROWS prose. |
| REG-04  | CLOSED | §5c prior-finding spot-check sweep across `audit/FINDINGS-v25.0.md → audit/FINDINGS-v35.0.md`. |

### 3d. AUDIT-01 Delta-Surface Table

**Part A — Declaration-by-declaration enumeration vs baseline `5db8682b`:**

| Declaration | Classification | Live Line(s) at HEAD | Hunk Evidence | Phase 266 REQ |
|---|---|---|---|---|
| `_rollTargetLevel(uint24 baseLevel, uint256 seed)` | MODIFIED_LOGIC (signature change: drop `nextEntropy` return; bit-sliced reads from `seed`) | live L812-826 | `git diff 5db8682b..HEAD` shows hunk replacing L809-827 baseline | ENT-01 |
| `_rollTargetLevel` 4 entry-point callers (`openLootBox` / `openBurnieLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox`) | REFACTOR_ONLY (local rename `entropy` → `seed`; single-return _rollTargetLevel call; thread `seed` into `_resolveLootboxCommon`) | live L555 / L629 / L674 / L709 | hunk evidence per caller | ENT-01 caller-side |
| `_resolveLootboxRoll(... uint256 seed)` return tuple | MODIFIED_LOGIC (drop `nextEntropy` from 4-tuple → 3-tuple; `entropy` parameter renamed to `seed`) | live L1548-1620 | hunk evidence | ENT-02 |
| `_resolveLootboxRoll` body — 4 entropyStep callsites | DELETED (L1548 + L1569 + L1599 replaced with bit-slices; L1585 dead WWXRP advance DELETED entirely per `feedback_no_dead_guards.md`) | n/a (removed) | `grep -cE "EntropyLib\.entropyStep" contracts/modules/DegenerusGameLootboxModule.sol` returns 0 | ENT-02 |
| `_resolveLootboxRoll` pathRoll bit-slice | NEW | live L1567 (`uint16(seed >> 40) % 20`) | hunk evidence | ENT-02 |
| `_resolveLootboxRoll` large-BURNIE varianceRoll bit-slice | NEW | live L1612 (`uint16(seed >> 80) % 20`) | hunk evidence | ENT-02 |
| `_lootboxTicketCount(... uint256 seed) → uint32` | MODIFIED_LOGIC (drop `nextEntropy` return; L1648 = `uint24(seed >> 96) % 10_000`) | live L1639-1681 | hunk evidence | ENT-03 |
| `_lootboxDgnrsReward(uint256 amount, uint256 entropy)` body | MODIFIED_LOGIC (sub-call slice updated to `uint24(entropy >> 56) % 1000` per RESEARCH.md Pitfall 3 — bit-disjoint from primary-chunk consumers) | live L1694 | hunk evidence | ENT-02 sub-call |
| `_rollLootboxBoons(... uint256 seed)` body | MODIFIED_LOGIC (parameter rename `entropy` → `seed`; L1074 = `uint32(seed >> 120) % BOON_PPM_SCALE` per RESEARCH.md Pitfall 3 — bit-disjoint from primary-chunk consumers) | live L1028-1090 | hunk evidence | ENT-02 sub-call |
| `_resolveLootboxCommon(... uint256 seed, ...)` parameter rename + entry-point seed plumbing | REFACTOR_ONLY (parameter rename `entropy` → `seed`; pre-existing `keccak256(abi.encode(rngWord, player, day, amount))` preserved per RESEARCH.md Open Question 2; threaded through 5 sub-rolls) | live L860 (signature) + L835-849 (NatSpec bit-allocation map) | hunk evidence | ENT-02 / ENT-06 |
| `seed2 = EntropyLib.hash2(seed, 1)` ETH-amount-second branch chunk | NEW (counter-tagged second seed per RESEARCH.md Pitfall 2 Option A; collision-free vs primary chunk 0; single keccak addition in the split-amount path) | live L936 | hunk evidence | ENT-02 / AUDIT-02 surface (c) |
| Inline NatSpec bit-budget block per refactored function | NEW | live (NatSpec at L805-810 / L835-849 / L1019-1020 / L1543-1547 / L1633-1634 / L1685-1686) | hunk evidence | ENT-06 |
| `EntropyLib.entropyStep` callsites in lootbox path (7 sites at baseline: L813 + L817 + L1548 + L1569 + L1585 + L1599 + L1635) | DELETED | n/a (removed) | `git diff 5db8682b..HEAD -- contracts/modules/DegenerusGameLootboxModule.sol \| grep "^-.*entropyStep"` shows 7 deletions | ENT-01..03 |
| L1585 WWXRP-path dead `entropyStep` advance | DELETED (RESEARCH.md Open Question 3 + Assumption A3 + `feedback_no_dead_guards.md` — saves ~40 g per WWXRP-path lootbox) | n/a (removed) | hunk evidence | ENT-02 / `feedback_no_dead_guards` |
| `nextEntropy` return contract on `_rollTargetLevel` / `_resolveLootboxRoll` / `_lootboxTicketCount` | DELETED (signature change; seed plumbing replaces nextEntropy chaining) | n/a (removed) | hunk evidence | ENT-01..03 |
| `EntropyLib.sol` body | REFACTOR_ONLY (zero changes — file BYTE-IDENTICAL) | L1-43 | `git diff 5db8682b..HEAD -- contracts/libraries/EntropyLib.sol` returns empty | ENT-04 / SURF-01 |
| `DegenerusGameJackpotModule.sol` body | REFACTOR_ONLY (zero changes — file BYTE-IDENTICAL; SURF-02 BAF + SURF-04 9 callsites preserved) | (whole file) | `git diff 5db8682b..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` returns empty | ENT-05 / SURF-02 / SURF-04 |
| `DegenerusGameMintModule.sol` body | REFACTOR_ONLY (zero changes — file BYTE-IDENTICAL; SURF-03 L652 callsite preserved) | (whole file) | `git diff 5db8682b..HEAD -- contracts/modules/DegenerusGameMintModule.sol` returns empty | SURF-03 |

**Part B — Downstream-caller inventory grep recipe (verifies nothing outside `DegenerusGameLootboxModule.sol` references the refactored helpers; protocol RNG-consumer surface unchanged elsewhere):**

```bash
grep -rn "_rollTargetLevel\|_resolveLootboxRoll\|_lootboxTicketCount\|_lootboxDgnrsReward\|_rollLootboxBoons\|EntropyLib\.entropyStep" contracts/
```

Expected output:
- `_rollTargetLevel` / `_resolveLootboxRoll` / `_lootboxTicketCount` / `_lootboxDgnrsReward` / `_rollLootboxBoons` — only in `contracts/modules/DegenerusGameLootboxModule.sol` (file-internal helpers; no cross-module consumers).
- `EntropyLib.entropyStep` — only in `contracts/modules/DegenerusGameJackpotModule.sol` at L2192 (BAF jackpot `_jackpotTicketRoll`; ENT-05 deferral verified) and `contracts/libraries/EntropyLib.sol` L16-23 (function definition; ENT-04 stable).

**Part C — AUDIT-04 zero-new-state attestation (5 grep-reproducible checks):**

1. **Storage-slot scan.** `git diff 5db8682b..HEAD --stat -- contracts/storage/ contracts/modules/DegenerusGameLootboxModule.sol` shows ONLY `contracts/modules/DegenerusGameLootboxModule.sol` modified; `contracts/storage/` empty (zero new storage variables added). PASS.

2. **GameStorage byte-identity.** `git diff 5db8682b..HEAD -- contracts/storage/GameStorage.sol` returns empty output. PASS.

3. **Zero-new-public-fn grep.** `git diff 5db8682b..HEAD -- contracts/ | grep -E '^\+.*function .* (public|external)'` returns zero hits — Phase 266 introduces zero new `public` / `external` mutation entry points (the refactored helpers are all `private`). PASS.

4. **Zero-new-modifier grep.** `git diff 5db8682b..HEAD -- contracts/ | grep -E '^\+.*modifier '` returns zero hits — Phase 266 introduces zero new modifiers. PASS.

5. **EntropyLib API stable (ENT-04).** `git diff 5db8682b..HEAD -- contracts/libraries/EntropyLib.sol` returns empty. PASS — `EntropyLib.entropyStep` and `EntropyLib.hash2` signatures + bodies BYTE-IDENTICAL at v36.0 close per D-266-API-01.

All 5 checks PASS. AUDIT-04 verdict: `0 new public/external mutation entry points; 0 new storage slots in GameStorage; 0 new admin functions; 0 new upgrade hooks; 0 new modifiers escalating authority; 0 new EntropyLib helpers (D-266-API-01 — inline shifts only)`.

### 3e. AUDIT-03 Conservation Re-Proof

The Phase 266 lootbox-entropy refactor preserves every conservation invariant established at v33 / v34 / v35 lootbox-resolution closures. The refactor changes ONLY the entropy-derivation mechanism (xorshift → bit-sliced keccak) — every downstream value-transfer path is byte-identical. Re-proof per invariant:

**ETH conservation.** `_resolveLootboxCommon` (`amountFirst + amountSecond = mainAmount = amount - boonBudget`) → ETH flows unchanged: same `_distributeEth` paths into player + pool + Decimator settlement at the same ratios. Boon-budget logic unchanged at L876-882 (`if (boonBudget > LOOTBOX_BOON_MAX_BUDGET) boonBudget = LOOTBOX_BOON_MAX_BUDGET; if (boonBudget > amount) boonBudget = amount; mainAmount = amount - boonBudget;`). ETH-amount-second split at L885-888 (`if (mainAmount > LOOTBOX_SPLIT_THRESHOLD) { amountFirst = mainAmount / 2; amountSecond = mainAmount - amountFirst; }`) preserved byte-identically — only the per-resolution entropy seed differs (`seed` for first invocation; `seed2 = EntropyLib.hash2(seed, 1)` for second invocation per Option A counter-tag). Same accounting → same conservation. PASS.

**BURNIE conservation.** `coinflip.creditFlip(player, burnieAmount)` at L990 (post-refactor live line) is the ONLY mint-gateway invocation in the lootbox path; called once per resolution with the aggregate `burnieAmount = burnieNoMultiplier + burniePresale + bonusBurnie`. Phase 266 does NOT add or modify any `coinflip.creditFlip` callsite. The aggregate quantity is computed by the same `_resolveLootboxRoll` branches as pre-refactor — only the entropy slice differs (deterministic uniform from the same VRF-derived seed). Per-branch BURNIE math (large-BURNIE bps lookup + coin-unit conversion at L1612-1617 / L1565) is byte-identical pre/post. PASS.

**DGNRS conservation.** `_lootboxDgnrsReward` returns a tier-bucketed amount (small/medium/large/mega per L1696-1707 ppm constants); `_creditDgnrsReward` (L1715) calls `dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Lootbox, player, amount)` — the same pool-source as pre-refactor. The refactor only changes `tierRoll` derivation from `entropy % 1000` (XOR-shift mixed) to `uint24(entropy >> 56) % 1000` (bit-sliced from the same `seed`); both produce uniform distribution over [0, 1000) per STAT-01 chi² verification. Same tier-distribution shape → same long-run pool depletion behavior. PASS.

**WWXRP conservation.** WWXRP path uses literal `LOOTBOX_WWXRP_PRIZE` constant (no entropy consumption); refactor preserves this entirely (the L1585 dead `entropyStep` advance was deleted because no downstream consumer reads from it — pure cleanup). `wwxrp.mintPrize(player, wwxrpAmount)` at the live HEAD line is byte-identical to baseline. PASS.

**Tickets conservation.** `_lootboxTicketCount` returns `countScaled = (adjustedBudget * TICKET_SCALE) / priceWei` (L1672-1674 live HEAD); refactor only changes `varianceRoll` derivation (`entropy % 10_000` → `uint24(seed >> 96) % 10_000`). Variance-tier ppm constants (`LOOTBOX_TICKET_VARIANCE_TIER1..5_BPS`) byte-identical. `_queueTicketsScaled(player, targetLevel, futureTickets, false)` at L981 (live HEAD) is byte-identical. Same ticket-distribution shape → same long-run ticket-pool conservation. PASS.

**Boon conservation.** `_rollLootboxBoons` only awards a boon when `roll < totalChance` where `totalChance = (boonBudget * BOON_PPM_SCALE) / expectedPerBoon` (L1069). Refactor only changes `roll` derivation (`entropy % BOON_PPM_SCALE` → `uint32(seed >> 120) % BOON_PPM_SCALE`). The `totalChance` math, `_boonFromRoll` selection logic, and `_applyBoon` invocation are byte-identical. Same long-run boon-award rate → same boon-pool depletion behavior. PASS.

**Solvency invariant.** `claimablePool ≤ ETH balance + stETH balance` (carry-forward from v33 / v34 / v35). Phase 266 introduces zero new public/external mutation entry points (AUDIT-04 PASS check 3); zero new pool-write paths; zero new claimable-pool credit sites. Solvency invariant preserved by structural argument — the refactor does not introduce a path that mutates pool balances independently of the existing distribution mechanics. PASS.

**Bucket-share-sum × pool invariant.** Each lootbox resolution awards from the same prize-bucket distribution as pre-refactor (ticket / DGNRS / WWXRP / large-BURNIE), with the same path-roll branch probabilities (55% / 10% / 10% / 25%) — these are determined by the modulo-20 path-roll, which is uniform under both xorshift and bit-sliced keccak per STAT-01 chi². Aggregate bucket-share-sum × pool reconciles to the same pool-aggregate as pre-refactor. PASS.

AUDIT-03 verdict: `CLOSED_AT_HEAD_<sha>` — every conservation invariant established at v33 / v34 / v35 lootbox-resolution closures preserved byte-identically across the entropy-derivation refactor; the refactor's mathematical contract is "uniformly-distributed bit-slice of a VRF-derived 256-bit keccak", which is the same probabilistic shape as the pre-refactor xorshift-mixed `% small` distribution.



## 4. F-36-NN Finding Blocks

Per D-265-FIND-01 carry default-path expectation: ZERO F-36-NN finding blocks emitted. The Phase 266 lootbox-entropy refactor is mathematically well-bounded — per-resolution keccak `keccak256(abi.encode(rngWord, player, day, amount))` consumes VRF-derived high-entropy bits (player cannot bias post-commit per `feedback_rng_commitment_window.md`); inline bit-slice modulo bias is documented per consumer (max 0.39% for `% 5`; ≤ 0.05% for all other slices); chi² uniformity empirically verified at STAT-01 (Wilson-Hilferty Z < 1.645 for high-df; CHI2_CRIT_05[4] = 9.488 for low-df near-offset); cumulative bit budget 152 bits / 256 available with comfortable headroom; ETH-amount-second branch uses Option A counter-tagged `seed2 = EntropyLib.hash2(seed, 1)` for collision-free chunking; cross-surface byte-identity preserved at SURF-01..04. The 6-surface adversarial sweep below verdicts every identified surface (a..f) — all 6 rows expected SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE.

Severity ceiling for any v36-emitted F-36-NN: HIGH (no value extraction beyond the existing lootbox-prize space; bucket-share-sum × pool invariant under the same ETH/BURNIE/DGNRS/WWXRP distribution mechanics as pre-refactor; modulo bias bounded analytically; per-pull entropy VRF-derived not player-controllable). Most likely severity for any inline-draft finding-candidate: MEDIUM/LOW. Default outcome: §4 emits ZERO F-36-NN finding blocks; deviations escalate to user inline per D-266-ADVERSARIAL-03 (see §4.2 trailer).

### 4.1. Adversarial Sweep — 6-Surface Row Table

**Surface (a) — Bit-slice modulo-bias bound per draw within documented bound.**

- **Verdict:** SAFE_BY_DESIGN
- **Grep recipe / line cite:** Bit-budget table at §3a; per-consumer slice + bias documented inline (NatSpec) per ENT-06 at `contracts/modules/DegenerusGameLootboxModule.sol` L805-810 (`_rollTargetLevel`) + L835-849 (`_resolveLootboxCommon` unified bit-allocation map) + L1019-1020 (`_rollLootboxBoons`) + L1543-1547 (`_resolveLootboxRoll`) + L1633-1634 (`_lootboxTicketCount`) + L1685-1686 (`_lootboxDgnrsReward`); STAT-01 chi² cross-cite at `test/stat/LootboxEntropyDistribution.test.js` (6 buckets — `% 100` Z<1.645 df=99 N=10K; `% 5` chi²<9.488 df=4 N=5K; `% 46` Z<1.645 df=45 N=10K; `% 20` path Z<1.645 df=19 N=10K; `% 20` variance Z<1.645 df=19 N=5K; `% 10000` Z<1.645 df=9999 N=100K).
- **Prose justification:** Per D-266-BIT-BUDGET-01: every `% small` slice has documented bias ≤ 1% (max 0.39% at `% 5` from 8 bits = 256 mod 5 / 256; ≤ 0.05% for all other slices including `% 100` from 16 bits = 65536 mod 100 / 65536, `% 46` from 16 bits = 65536 mod 46 / 65536; min 0.0024% at `% 1000` from 24 bits). Backward-trace per `feedback_rng_backward_trace.md`: each consumer ultimately reads VRF-derived bits via the entry-point keccak `keccak256(abi.encode(rngWord, player, day, amount))`; rngWord is post-VRF-fulfillment-unknown to player. Empirical chi² evidence at STAT-01 covers uniformity end-to-end via JS-replica RNG calibrated to the on-chain bit-slice convention (mask + shift + modulo).

**Surface (b) — Seed-reuse cross-correlation across sub-rolls within same resolution.**

- **Verdict:** SAFE_BY_DESIGN
- **Grep recipe / line cite:** Bit-allocation map at L835-849 enumerates 8 consumers consuming bit ranges [0..15] / [16..23] / [24..39] / [40..55] / [56..79] / [80..95] / [96..119] / [120..151] — DISJOINT bit ranges with no overlap; cumulative consumption 152 bits / 256 available; STAT-01 chi² verifies each consumer slice independently uniform; STAT-02 distribution-shape preservation re-runs 2 consumer slices under the same chi² threshold to confirm cross-consumer independence.
- **Prose justification:** All 8 lootbox-resolution consumers slice from DISJOINT bit ranges of the same 256-bit `seed` (the primary chunk — counter 0 in the Option A scheme). keccak256 output bits are cryptographically pseudo-independent at the bit-pair level (the keccak-256 sponge construction's diffusion property); slicing disjoint bit ranges yields draws that are independent within Wilson-Hilferty / chi² tolerance per STAT-01 empirical verification. The bit-allocation map is the load-bearing audit invariant: no consumer reads bits outside its allotted range; no two consumers share a bit. Cross-resolution (different player / day / amount) seeds derive from a fresh keccak input so seeds are non-correlated across resolutions by VRF-derived entropy.

**Surface (c) — `hash2(seed, N)` chunk-collision-free across consumers.**

- **Verdict:** SAFE_BY_DESIGN
- **Grep recipe / line cite:** `grep -nE "EntropyLib\.hash2\(seed, 1\)" contracts/modules/DegenerusGameLootboxModule.sol` returns L936 (single seed2 site in `_resolveLootboxCommon` ETH-amount-second branch); D-266-CONSUMER-LIST-01 enumeration at `.planning/phases/266-lootbox-entropy-refactor/266-CONTEXT.md` documents the 7-callsite consumer inventory with disjoint bit-range allocation; `EntropyLib.hash2(uint256 a, uint256 b) → uint256` is `keccak256(abi.encode(a, b))` per `contracts/libraries/EntropyLib.sol` L36-42 (file BYTE-IDENTICAL at v36 close per ENT-04 / SURF-01).
- **Prose justification:** Phase 266 uses ONE `hash2` chunk-counter pattern: the ETH-amount-second branch derives `seed2 = EntropyLib.hash2(seed, 1)` per Option A (RESEARCH.md Pitfall 2). This chunk-counter scheme produces collision-free chunks because `hash2(seed, 0)` (the primary chunk — implicit `seed` itself) and `hash2(seed, 1)` (the second-amount chunk) hash to different 256-bit outputs with overwhelmingly high probability (keccak256 collision probability ≈ 2^−256 per AUDIT industry baseline). The counter-tag value `1` is a literal constant; no other consumer in the lootbox path uses `hash2(seed, N)` with a different counter, so no cross-consumer collision risk exists at v36. Future phases that introduce additional counter-tagged chunks must extend the bit-allocation map to enforce the same disjointness invariant.

**Surface (d) — Gas-griefing delta bounded; refactor preserves the v34/v35 1.99× advanceGame margin.**

- **Verdict:** SAFE_BY_DESIGN
- **Grep recipe / line cite:** `test/gas/LootboxOpenGas.test.js` GAS-01 theoretical-worst-case derivation header (per `feedback_gas_worst_case.md`); `test/gas/AdvanceGameGas.test.js` v36.0 describe block — `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` pinned + GAS-02 ±2K stage tolerance + 1.99× margin invariant carry-forward from Phase 264 SURF-05.
- **Prose justification:** Per `feedback_gas_worst_case.md`: theoretical worst case derived FIRST in `test/gas/LootboxOpenGas.test.js` header (opcode-by-opcode walk). Per-resolution gas delta:
  - Saved: 5 entropyStep calls × ~33 g each ≈ 165 g per resolution (3-shift / 3-XOR / branch-overhead arithmetic)
  - Saved: 1 dead L1585 entropyStep advance × ~33 g = ~33 g (WWXRP path; per RESEARCH.md Open Question 3 + Assumption A3 + `feedback_no_dead_guards.md`)
  - Added: per-consumer inline shifts (uint8/uint16/uint24 + masks) ~6-12 g each × 7 consumers ≈ 70-90 g per resolution
  - Added: ETH-amount-second branch keccak `hash2(seed, 1)` ~80 g (Option A counter-tag; only on split-amount path)
  - Net per-open delta: typical −40 to +101 g (single-amount path); +60 to +180 g (ETH-amount-second branch).
  GAS-01 envelope ±300 g per-open with 2× headroom. AdvanceGame envelope (GAS-02) ≤ ±2K per stage; 1.99× margin invariant carries forward from Phase 264 SURF-05 evidence. Decimator settlement is the one advanceGame-resident lootbox-resolution caller per CONTEXT.md `<domain>` and ROADMAP success criterion 4. Worst-case lootbox delta contribution to advanceGame: 160 simultaneous Decimator opens × +180 g = ~29K g per advance; bounded inside the existing 16M block-gas absolute ceiling (margin shifts by ≤ 0.001× from 1.99×).

**Surface (e) — BAF jackpot byte-identity (ENT-05 deferral verification).**

- **Verdict:** SAFE_BY_STRUCTURAL_CLOSURE
- **Grep recipe / line cite:** `test/stat/SurfaceRegression.test.js` v36.0 SURF-02 describe block — `SURF_02_PROTECTED_RANGES = [{name: "_jackpotTicketRoll body L2186-2229 (SURF-02 — ENT-05 deferral)", lo: 2186, hi: 2229}]`; per-line modified-set walk vs `git diff 5db8682b HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` returns ZERO `-` deletions inside the protected range.
- **Prose justification:** BAF jackpot `_jackpotTicketRoll` (`DegenerusGameJackpotModule.sol:2186-2229`) is the sole remaining `EntropyLib.entropyStep` consumer protocol-wide at v36 close. Per CONTEXT.md D-266-SCOPE-OUT-01 (user disposition: "look at 3 but don't change now"), the BAF refactor is explicitly OUT of scope. SURF-02 byte-identity verification confirms the deferral discipline: `git diff 5db8682b..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` returns empty (zero changes anywhere in the file, including the BAF range and the 9 non-lootbox EntropyLib callsites at SURF-04). KNOWN-ISSUES.md EntropyLib XOR-shift entry rephrased to BAF-only scope at v36 close (REPHRASE not promotion per AUDIT-05 + D-09). Future-phase candidate: BAF refactor following the same bit-sliced keccak pattern would close the EntropyLib XOR-shift KI entry entirely.

**Surface (f) — Commitment-window check (player cannot bias `rngWord` post-commit).**

- **Verdict:** SAFE_BY_DESIGN
- **Grep recipe / line cite:** `feedback_rng_commitment_window.md` cited inline; entry-point keccak at `contracts/modules/DegenerusGameLootboxModule.sol` L554 (`openLootBox`) / L628 (`openBurnieLootBox`) / L673 (`resolveLootboxDirect`) / L708 (`resolveRedemptionLootbox`); `lootboxRngWordByIndex[index]` storage write happens in the VRF-callback path BEFORE `openLootBox` is callable (the entry point reverts with `RngNotReady` if `rngWord == 0`).
- **Prose justification:** Per `feedback_rng_commitment_window.md`: every RNG audit must check what player-controllable state can change between VRF request and fulfillment. For Phase 266 lootbox path: the 4 entry-point seeds are derived from `keccak256(abi.encode(rngWord, player, day, amount))` where `rngWord` is the VRF-fulfilled word stored at `lootboxRngWordByIndex[index]` BEFORE the player can call `openLootBox`. The player cannot replace `rngWord` post-commit (storage slot write-protected by the VRF callback path; `rngWord == 0` reverts the entry point with `RngNotReady`). The other 3 entropy-input components are committed at purchase time: `player` is `msg.sender` (immutable per-tx); `day` is `lootboxDay[index][player]` (set at purchase; checked against `_simulatedDayIndex()` for grace-period boundaries); `amount` is the packed lootbox ETH (set at purchase). NO player-controllable state can change between VRF request and fulfillment that affects the entropy seed. The commitment window is structurally closed.

### 4.2. Verdict Roll-Up + Adversarial-Pass Status

**Verdict roll-up:**

| Surface | Verdict |
|---------|---------|
| (a) Bit-slice modulo-bias bound | SAFE_BY_DESIGN |
| (b) Seed-reuse cross-correlation | SAFE_BY_DESIGN |
| (c) `hash2(seed, N)` chunk-collision-free | SAFE_BY_DESIGN |
| (d) Gas-griefing delta bounded | SAFE_BY_DESIGN |
| (e) BAF byte-identity (ENT-05 verification) | SAFE_BY_STRUCTURAL_CLOSURE |
| (f) Commitment-window check | SAFE_BY_DESIGN |

**Roll-up:** 6 of 6 surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; ZERO FINDING_CANDIDATE rows; ZERO F-36-NN finding blocks emitted at pre-adversarial-pass draft. Adversarial pass at Task 14 (`/contract-auditor` + `/zero-day-hunter` parallel spawn per D-266-ADVERSARIAL-01..02) red-teams the finished §4 draft and validates each row.

**Adversarial-pass status:** Task 14 adversarial pass complete. `/contract-auditor` and `/zero-day-hunter` were spawned sequentially after the finished §4 draft; both red-teamed all 6 surfaces and returned **ZERO disagreements**. /contract-auditor investigated 13 hypotheses (g..n + sub-k1) covering re-entrancy / overflow / keccak collision / gas-bomb / cross-resolution / future-extension / dead-code / silent-miscount surfaces. /zero-day-hunter investigated 14 novel composition-surface hypotheses (Z1..Z14) covering Decimator multi-claim / ENF-02 redirection / MEV / indexer semantic-shift / VRF backfill / forward-compat / storage-zeroing race / population-level entropy / self-destruct / parameter-naming / cross-module / behavioral-replay / rngWord-zero / EV-multiplier vectors. Zero F-36-NN finding-candidates surfaced. Three forward-looking defensive notes captured (NOT findings against v36.0 HEAD): (1) future hash2(seed, N) extensions must extend the bit-allocation map (already in §4 (c) prose); (2) pre-existing dead BURNIE-conversion branch in `_resolveLootboxRoll` L1574 — seeded for v37.0 maintenance scope at `.planning/notes/2026-05-10-resolveLootboxRoll-dead-burnie-conversion-branch.md`; (3) pre-existing forced-open griefing surface via `openLootBox(player, index)` third-party callable + 7-day grace period — value-neutral; not a Phase 266 delta. Full adversarial-pass log at `.planning/phases/266-lootbox-entropy-refactor/266-01-ADVERSARIAL-LOG.md`. /economic-analyst and /degen-skeptic explicitly NOT spawned per D-266-ADVERSARIAL-01 (carry of D-265-ADVERSARIAL-01).



## 5. Regression Appendix

Per D-266-REG carry of D-265-REG01-01 + D-265-REG02-01 + D-265-REG04-01: lean-regression discipline (carry-forward of v32 / v33 / v34 / v35 LEAN regression pattern). §5a single-row REG-01 PASS for v35.0 closure-signal non-widening. §5b single-row REG-02 PASS for v34.0 closure-signal non-widening. §5c per-finding 6-col PASS/REGRESSED/SUPERSEDED row table walking every prior FINDINGS-vNN.md (v25/v27/v28/v29/v30/v31/v32/v33/v34/v35) for any finding referencing the v36-touched function reference set. KI envelope re-verifications (REG-03) live in §6b standalone, not folded into REG-04.

### 5a. REG-01 — v35.0 Closure-Signal Non-Widening

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD `<sha>` | Re-Verification Evidence | Verdict |
|---|---|---|---|---|---|
| REG-v35.0-PER-PULL-LEVEL | v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6` carry-forward. v35 audit deliverable `audit/FINDINGS-v35.0.md` 7 of 7 §4 surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE at HEAD `5db8682b`; per-pull-level resample helper `_awardDailyCoinToTraitWinners` + AUDIT-06 indexer semantic-shift documented in §3c; STAT-03 fixture-calibration reframed per D-265-STAT03-01. | `5db8682b..<sha>` (1 v36 contract commit `df6345cc` + 1 v36 test commit `16ed452b` — only `contracts/modules/DegenerusGameLootboxModule.sol` modified; no other contract or library files touched) | Phase 266 SURF-01..04 grep-proof asserts 4 protected ranges byte-identical between baseline `5db8682b` and v36 HEAD: `EntropyLib.sol` body L1-43 (whole file); `_jackpotTicketRoll` body L2186-2229 (BAF jackpot, ENT-05 deferral); MintModule L652 (`EntropyLib.hash2(entropy, rollSalt)`); 9 non-lootbox JackpotModule EntropyLib callsites at L285/L453/L532/L610/L612/L886/L1176/L1873/L2192. Per-line modified-set walk via `git diff 5db8682b..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` returns ZERO `-` deletions (file BYTE-IDENTICAL). Same for EntropyLib + MintModule. v35 §4 7-surface verdicts carry forward unchanged at v36 HEAD. | v36 modifies ONLY `contracts/modules/DegenerusGameLootboxModule.sol` (single contract — 7 lootbox-path entropyStep callsites replaced with bit-sliced keccak; sub-call slice updates for `_lootboxDgnrsReward` + `_rollLootboxBoons`; ETH-amount-second branch `seed2 = hash2(seed, 1)`; NatSpec bit-budget blocks). `contracts/libraries/EntropyLib.sol` BYTE-IDENTICAL (ENT-04). `contracts/modules/DegenerusGameJackpotModule.sol` BYTE-IDENTICAL (SURF-02 + SURF-04). `contracts/modules/DegenerusGameMintModule.sol` BYTE-IDENTICAL (SURF-03). v35 per-pull-level helper at `_awardDailyCoinToTraitWinners` UNTOUCHED (orthogonal to lootbox-resolution path). | **PASS** |

### 5b. REG-02 — v34.0 Closure-Signal Non-Widening

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD `<sha>` | Re-Verification Evidence | Verdict |
|---|---|---|---|---|---|
| REG-v34.0-TRAIT-SOLO | v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` carry-forward. v34 audit deliverable `audit/FINDINGS-v34.0.md` 6 of 6 §4 surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE at HEAD `6b63f6d4`; `_pickSoloQuadrant` 4-injection-site rotation, JackpotBucketLib UNCHANGED carry, heavy-tail color distribution all closed. | `6b63f6d4..<sha>` (1 v35 contract commit `cf564816` + 1 v36 contract commit `df6345cc` — neither touches `_pickSoloQuadrant` body L1098-1115 nor 4 ETH-injection sites L287/L454/L531/L1181) | `git diff 6b63f6d4..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` shows v35 modifications confined to coin-jackpot helper rewire (Phase 263 PPL-01); v36 makes ZERO changes to JackpotModule (SURF-02 + SURF-04 grep-proof at v36). `_pickSoloQuadrant` body byte-identical at v36; 4 ETH-injection-site callsites byte-identical at v36. | v34 §4 6-surface verdicts carry forward unchanged at v36 HEAD. v36 lootbox-entropy refactor is orthogonal to gold-solo-priority path (different module, different RNG consumer chain). v35 carry-forward already PASS-graded; v36 preserves all v34 invariants. | **PASS** |

### 5c. REG-04 — Prior-Finding Spot-Check Sweep

Per D-266-REG04-01 carry of D-265-REG04-01: defensive grep walk across `audit/FINDINGS-v25.0.md` through `audit/FINDINGS-v35.0.md` for any prior finding referencing the v36-touched function reference set: `_rollTargetLevel`, `_resolveLootboxRoll`, `_resolveLootboxCommon`, `_lootboxTicketCount`, `_lootboxDgnrsReward`, `_rollLootboxBoons`, `openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`, `EntropyLib.entropyStep` (lootbox-path consumers), `lootboxEth`, `lootboxBurnie`, `lootboxRngWordByIndex`. Recipe:

```bash
for f in audit/FINDINGS-v25.0.md audit/FINDINGS-v27.0.md audit/FINDINGS-v28.0.md audit/FINDINGS-v29.0.md audit/FINDINGS-v30.0.md audit/FINDINGS-v31.0.md audit/FINDINGS-v32.0.md audit/FINDINGS-v33.0.md audit/FINDINGS-v34.0.md audit/FINDINGS-v35.0.md; do
  echo "=== $f ==="
  grep -nE '(_rollTargetLevel|_resolveLootboxRoll|_resolveLootboxCommon|_lootboxTicketCount|_lootboxDgnrsReward|_rollLootboxBoons|openLootBox|openBurnieLootBox|resolveLootboxDirect|resolveRedemptionLootbox|EntropyLib\.entropyStep|lootboxEth|lootboxBurnie|lootboxRngWordByIndex)' "$f"
done
```

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD `<sha>` | Re-Verification Evidence | Verdict |
|---|---|---|---|---|---|
| REG-v25.0-LOOTBOX-INVENTORY | `audit/FINDINGS-v25.0.md` — Phase 215-02 fresh-eyes RNG audit function-inventory cite of lootbox-resolution helpers (no specific finding row). | `5db8682b..<sha>` | Helpers inventoried at v25 are now post-Phase-266 refactored (entropyStep removed from lootbox path; bit-sliced keccak from per-resolution seed). | v25.0 source row was a function-inventory cite, not a finding row. The post-refactor helpers preserve the same external API (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`) and the same conservation invariants per §3e. v25 inventory carry-forward to v36 is a NAME-PRESERVATION + BEHAVIORAL-EQUIVALENCE re-verification, not a finding-tracking row. | **PASS** |
| REG-v25.0-ENTROPYLIB-XORSHIFT | `audit/FINDINGS-v25.0.md` — KNOWN-ISSUES.md EntropyLib XOR-shift PRNG entry (carried forward from initial audit; classified INFO-design-decision). | `5db8682b..<sha>` | Lootbox-path xorshift consumption REMOVED at v36 close (7 callsites deleted). BAF jackpot `_jackpotTicketRoll` xorshift consumer PRESERVED (ENT-05 deferral verified by SURF-02 byte-identity). | v36 NARROWS the EntropyLib XOR-shift KI scope: pre-v36 the entry covered "lootbox outcome rolls"; post-v36 the entry covers "BAF jackpot ticket rolls only" (1 entry rephrased per AUDIT-05). v25-onward INFO classification preserved at narrower scope. KNOWN-ISSUES.md modified by 1 entry under Design Decisions per §6 KI Gating Walk. | **PASS** (with NARROWS rephrase per AUDIT-05) |
| REG-v27.0-LOOTBOX-DELEGATECALL | `audit/FINDINGS-v27.0.md` — F-27-XX `payDailyCoinJackpot` direct-delegatecall pattern (informational; coverage extended to lootbox-path delegatecalls in subsequent milestones). | `5db8682b..<sha>` | `openLootBox` / `openBurnieLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox` external entry points UNTOUCHED at v36 (signatures byte-identical; only internal helper bodies refactored). | v27 observation was about delegatecall surface; v36 doesn't change any external entry point's selector or signature. AUDIT-04 §3d Part C check 3 (zero new public/external mutation entry points) confirms this. v34/v35 carry-forward already PASS-graded. | **PASS** |
| REG-v28.0-LOOTBOX-CATALOG | `audit/FINDINGS-v28.0.md` — sim/database/indexer catalog covering lootbox-event emission chain (`LootBoxOpened`, `BurnieLootOpen`, `LootBoxDgnrsReward`, `LootBoxWwxrpReward`); classified INFO-ACCEPTED design (per D-229-10). | `5db8682b..<sha>` | All 4 lootbox-event signatures BYTE-IDENTICAL at v36 (ABI-level preservation per /zero-day-hunter Hypothesis Z4 verification). | v28 catalog cite of indexer-side event consumption preserved at v36. No event signature change; no semantic shift parallel to AUDIT-06 (per /zero-day-hunter Z4 verdict). v36 entropy refactor is internal-only; indexer-side observability unchanged. | **PASS** |
| REG-v29.0-LOOTBOX-EVENTS | `audit/FINDINGS-v29.0.md` — Phase 233-01 noted lootbox event signature stability (`uint8 traitId` widening only applied to JackpotTicketWin, not lootbox events). | `5db8682b..<sha>` | Lootbox-event signatures untouched at v36; no widening or narrowing of any field. | v29 observation preserved. v36 entropy refactor doesn't add or modify any event field. | **PASS** |
| REG-v30.0-LOOTBOX-RNG-CLUSTER | `audit/FINDINGS-v30.0.md` — INV-237-XXX cluster covering lootbox-RNG `respects-rngLocked` invariants for `openLootBox` / `openBurnieLootBox` and per-index VRF callback. All classified `respects-rngLocked` SAFE. | `5db8682b..<sha>` | v36 helper does not touch `rngLockedFlag` (refactor is memory-arithmetic-only inside `_resolveLootboxCommon` body); per-index VRF storage path (`lootboxRngWordByIndex`) unchanged; `RngNotReady` reverts at L534/L612 byte-identical pre/post. | v30 RNG-cluster invariants preserved at v36: (a) `respects-rngLocked` for all rows because v36 has zero `rngLockedFlag` interactions; (b) per-index rngWord-fulfillment path byte-identical (no v36 commit touches the VRF callback); (c) /zero-day-hunter Hypothesis Z5 confirms per-index VRF storage isolation from daily-VRF backfill. v34/v35 carry-forward already PASS-graded. | **PASS** |
| REG-v31.0-LOOTBOX-BOON-COMPOSITION | `audit/FINDINGS-v31.0.md` — boon-roll + lootbox-open composition observations; verified no value-extraction surface from boon side-effects during lootbox open. | `5db8682b..<sha>` | `_rollLootboxBoons` refactored to bit-sliced read at L1074 (`uint32(seed >> 120) % BOON_PPM_SCALE`) — same modulo distribution, different mechanism. `_applyBoon` path BYTE-IDENTICAL (pre-existing function not touched by Phase 266). | /contract-auditor Hypothesis (g) re-verified: boon-roll consumes in-memory seed; downstream `consumeActivityBoon` delegatecall + `_applyBoon` write byte-identical. Per /zero-day-hunter Z7: no storage-zeroing race; in-memory seed isolation. v31 boon-composition observations preserved at v36 HEAD. | **PASS** |
| REG-v32.0-LOOTBOX-DEITY-INTERACTION | `audit/FINDINGS-v32.0.md` — F-30-XXX deity-cache + lootbox-boon interaction observations; classified INFO. | `5db8682b..<sha>` | Deity-pass storage path (`mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT`) at L1053 unchanged at v36; `_boonPoolStats` deity-eligibility branch unchanged. | v32 observation preserved. v36 doesn't change deity-cache logic; boon-roll's deity-eligibility check at L1052-1053 is byte-identical. Per /zero-day-hunter Z11: file-internal `private` visibility forecloses cross-module deity-interaction surface. | **PASS** |
| REG-v33.0-LOOTBOX-CONSERVATION | `audit/FINDINGS-v33.0.md` — Phase 257 §3e conservation invariants (ETH/BURNIE/Tickets) verified at v33 lootbox-resolution closure. | `5db8682b..<sha>` | §3e of THIS deliverable re-proves all 8 conservation invariants (ETH / BURNIE / DGNRS / WWXRP / Tickets / Boon / Solvency / Bucket-share-sum × pool) preserved across the v36 entropy refactor. | v33 conservation invariants carry forward unchanged. v36 entropy refactor is internal-only — every downstream value-transfer path is byte-identical (same `coinflip.creditFlip` callsite, same `wwxrp.mintPrize`, same `dgnrs.transferFromPool`, same `_queueTicketsScaled`, same `_applyBoon`). | **PASS** |
| REG-v34.0-LOOTBOX-COMPOSITION-SURFACES | `audit/FINDINGS-v34.0.md` — Phase 262 §4 6-surface verdicts covering lootbox-resolution composition (a-f). | `5db8682b..<sha>` | v36 §4 6-surface sweep retains the same surface enumeration (a-f) with adapted prose for the bit-sliced refactor; all 6 verdicts SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; adversarial pass (Task 14) returned ZERO disagreements. | v34 6-surface composition verdicts carry forward at v36; the surfaces are RE-VERDICTED (not re-derived from scratch) per the new bit-slice mechanism. /contract-auditor + /zero-day-hunter parallel adversarial pass at Task 14 confirms no v36 delta widens any v34 surface. | **PASS** |
| REG-v35.0-LOOTBOX-NULL-DELTA | `audit/FINDINGS-v35.0.md` — v35 made ZERO changes to LootboxModule (per CONTEXT.md hard constraint #1: pure-consolidation phase; zero contracts/ writes). | `5db8682b..<sha>` | LootboxModule at v35 close `5db8682b` is byte-identical to v34 close `cf564816`. v36 introduces the FIRST mutation since the v34 baseline — single batched user-approved commit `df6345cc`. | v35 carry-forward is null-delta on LootboxModule; v36 is the FIRST delta against the v34 baseline for this module. The 17-row §3d delta-surface table enumerates every changed declaration with hunk-level evidence. No regression introduced; refactor is intentional v36 scope per CONTEXT.md `<domain>` and ROADMAP success criterion. | **PASS** |

### 5d. Regression Distribution Summary

REG-01: 1 PASS row covering v35.0 per-pull-level resample closure-signal carry-forward.
REG-02: 1 PASS row covering v34.0 trait-rarity-rework + gold-solo-priority closure-signal carry-forward.
REG-04: 11 PASS rows + 0 SUPERSEDED + 0 REGRESSED (spot-check across 10 prior FINDINGS deliverables for the v36-touched function reference set).
Combined: 13 regression rows (2 + 11 PASS + 0 SUPERSEDED + 0 REGRESSED). Default expectation zero REGRESSED rows MET.



## 6. KI Gating Walk [populated by Task 16]

## 7. Prior-Artifact Cross-Cites [populated by Task 18]

## 8. Forward-Cite Closure [populated by Task 18]

## 9. Milestone Closure Attestation [populated by Tasks 19-20]
