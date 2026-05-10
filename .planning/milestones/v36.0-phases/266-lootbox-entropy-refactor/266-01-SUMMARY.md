---
phase: 266-lootbox-entropy-refactor
plan: 266-01
milestone: v36.0
milestone_name: Lootbox-Path Entropy Refactor
status: COMPLETE
completed: 2026-05-10
duration: ~6h (inline-execution mode per user disposition at execute-phase open; mirrors v35.0 Phase 265 close pattern after subagent .md-write guard concerns)
deliverable: audit/FINDINGS-v36.0.md
closure_signal: MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
audit_baseline: 5db8682bd7b811437f0c1cf47e832619d1478ac6
audit_baseline_signal: MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
v33_baseline: 4ce3703d740d3707c88a1af595618120a8168399
v33_baseline_signal: MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399
audit_subject_head: 1c0f09132d7439af9881c56fe197f81757f8164a
requirements-completed: [ENT-01, ENT-02, ENT-03, ENT-04, ENT-05, ENT-06,
                         STAT-01, STAT-02, STAT-03,
                         GAS-01, GAS-02,
                         SURF-01, SURF-02, SURF-03, SURF-04,
                         AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05,
                         REG-01, REG-02, REG-03, REG-04]
---

## Outcome

**v36.0 milestone CLOSED.** `audit/FINDINGS-v36.0.md` published as FINAL READ-only at HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` — single canonical 9-section deliverable covering Phase 266 (lootbox-path entropy refactor: 1 batched contract commit `df6345cc` removing 7 `EntropyLib.entropyStep` callsites and replacing with bit-sliced reads from a single per-resolution keccak seed; 1 batched test commit `16ed452b` adding chi² uniformity verification + GAS-01 theoretical worst case + SURF-01..04 byte-identity grep-proofs). 6 of 6 §4 adversarial surfaces (a-f) verdicted SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-36-NN finding blocks. KNOWN-ISSUES.md modified by 1 entry rephrase (EntropyLib XOR-shift entry NARROWS to BAF-jackpot-only scope per AUDIT-05 — REPHRASE under D-09 Design Decisions, not new promotion). Closure verdict `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_REPHRASED (1 entry rephrased to BAF-only scope under Design Decisions per AUDIT-05)`. REG-01 + REG-02 single PASS rows for v35.0 / v34.0 closure-signal non-widening; REG-04 11 PASS rows for prior-finding spot-check sweep across audit/FINDINGS-v25..v35. EXC-01..03 NEGATIVE-scope at v36; EXC-04 RE_VERIFIED with NARROWS scope (BAF-jackpot-only after lootbox-path xorshift consumption removal). Adversarial pass via `/contract-auditor` + `/zero-day-hunter` parallel spawn returned ZERO disagreements across 13 + 14 hypothesis investigations; default §4 verdict roll-up stands. Three forward-looking defensive observations captured (NOT v36 findings): future hash2(seed, N) extensions need bit-allocation-map updates (already in §4 (c) prose); pre-existing dead BURNIE-conversion branch in `_resolveLootboxRoll` L1574 routed to v37.0 maintenance scope at `.planning/notes/2026-05-10-resolveLootboxRoll-dead-burnie-conversion-branch.md`; pre-existing forced-open griefing surface (value-neutral; not v36 delta). Closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` emitted in §9c.

## Phase Requirements (all 24 satisfied)

| Req | Description | ✓ |
|---|---|---|
| ENT-01 | `_rollTargetLevel` refactored to bit-sliced single-output (drops `nextEntropy` return); 4 entry-point callers updated; bits[0..15] / [16..23] / [24..39] documented inline | ✓ |
| ENT-02 | `_resolveLootboxRoll` 4 entropyStep callsites removed (3 replaced with bit-slices; L1585 dead WWXRP advance DELETED entirely per `feedback_no_dead_guards.md`); sub-call slicing for `_lootboxDgnrsReward` (bits[56..79]) + `_rollLootboxBoons` (bits[120..151]) | ✓ |
| ENT-03 | `_lootboxTicketCount` L1635 entropyStep replaced with `uint24(seed >> 96) % 10_000` | ✓ |
| ENT-04 | `EntropyLib.sol` body BYTE-IDENTICAL vs `5db8682b` (`git diff` returns empty per SURF-01 grep-proof) | ✓ |
| ENT-05 | DEFERRED — BAF jackpot `_jackpotTicketRoll` L2186-2229 byte-identical (SURF-02 grep-proof); future-phase candidate captured in CONTEXT.md `<deferred>` | ✓ |
| ENT-06 | NatSpec bit-budget block populated at every refactored function + unified bit-allocation map at `_resolveLootboxCommon` entry; ≥17 bit-range annotations in active source | ✓ |
| STAT-01 | `test/stat/LootboxEntropyDistribution.test.js` 6 chi² describe blocks pass (Wilson-Hilferty Z<1.645 for high-df; CHI2_CRIT_05[4]=9.488 for low-df near-offset) | ✓ |
| STAT-02 | Distribution-shape uniformity-equivalence asserted via 2-bucket re-run (`% 100` + `% 5`); specific-outcome divergence acceptable per CONTEXT.md `<deferred>` "Behavioral-replay tests" | ✓ |
| STAT-03 | `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` re-declared verbatim from `test/stat/TraitDistribution.test.js` L48-100 (Phase 261 origin) + `test/stat/PerPullLevelDistribution.test.js` L78-102 (Phase 264 carry) | ✓ |
| GAS-01 | `test/gas/LootboxOpenGas.test.js` theoretical-worst-case derivation header populated per `feedback_gas_worst_case.md`; per-open envelope ±300 g with 2× headroom; empirical pin deferred per AdvanceGameGas L1014/L1027 precedent (harness-coverage gap; theoretical worst case is the load-bearing GAS-01 evidence) | ✓ |
| GAS-02 | `test/gas/AdvanceGameGas.test.js` v36.0 describe block — `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` pinned; 1.99× margin invariant carries forward from Phase 264 SURF-05 evidence | ✓ |
| SURF-01 | `test/stat/SurfaceRegression.test.js` v36.0 SURF-01 describe block — EntropyLib.sol L1-43 zero modifications vs `5db8682b` | ✓ |
| SURF-02 | Same describe block — `_jackpotTicketRoll` L2186-2229 zero modifications (ENT-05 deferral verification) | ✓ |
| SURF-03 | Same describe block — MintModule L652 single-line callsite zero modifications | ✓ |
| SURF-04 | Same describe block — 9 non-lootbox JackpotModule EntropyLib callsites zero modifications | ✓ |
| AUDIT-01 | §3d delta-surface table — 17-row declaration enumeration with hunk-level evidence and classification | ✓ |
| AUDIT-02 | 6-surface adversarial sweep all SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; adversarial pass via /contract-auditor + /zero-day-hunter parallel spawn (0 disagreements; 13+14 hypothesis investigations) | ✓ |
| AUDIT-03 | 8-row conservation re-proof: ETH / BURNIE / DGNRS / WWXRP / Tickets / Boon / Solvency / Bucket-share-sum × pool — all preserved byte-identically across the entropy-derivation refactor | ✓ |
| AUDIT-04 | 5-row zero-new-state attestation: storage-slot scan + GameStorage byte-identity + zero-new-public-fn + zero-new-modifier + EntropyLib API stable | ✓ |
| AUDIT-05 | Closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` emitted in §9c; KNOWN-ISSUES.md EntropyLib XOR-shift entry rephrased to BAF-only scope (1 entry NARROWED under Design Decisions per Task 17) | ✓ |
| REG-01 | 1 PASS row — v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6` re-verified non-widening | ✓ |
| REG-02 | 1 PASS row — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening | ✓ |
| REG-03 | 4 KI envelope re-verifications: EXC-01..03 NEGATIVE-scope at v36; EXC-04 RE_VERIFIED with NARROWS scope (BAF-jackpot-only after lootbox-path xorshift removal) | ✓ |
| REG-04 | 11 PASS + 0 SUPERSEDED + 0 REGRESSED prior-finding spot-check rows across `audit/FINDINGS-v25.0.md` → `audit/FINDINGS-v35.0.md` | ✓ |

## Locked Decisions Honored

- **D-266-FILES-01** — Single canonical deliverable; no per-AUDIT-NN working files. ✓
- **D-266-PLAN-01** — Single multi-task plan with 21-task atomic-commit-per-task ordering across 5 waves (mirrors v33 Phase 257 / v34 Phase 262 / v35 Phase 265 single-plan precedent for combined contract+test+audit work). ✓
- **D-266-API-01** — No EntropyLib helper additions; inline shifts only. EntropyLib.sol BYTE-IDENTICAL at v36 close. ✓
- **D-266-SEED-01** — Single-keccak-per-resolution pattern with seed2 = `EntropyLib.hash2(seed, 1)` Option A counter-tag for ETH-amount-second branch. ✓
- **D-266-BIT-BUDGET-01** — Per-consumer bit-budget targets ≤ 1% modulo bias (max 0.39% at `% 5` from 8 bits; ≤ 0.05% for all other slices). ✓
- **D-266-CONSUMER-LIST-01** — 7 callsites refactored as enumerated; sub-call paths `_lootboxDgnrsReward` + `_rollLootboxBoons` slicing updated. ✓
- **D-266-SCOPE-OUT-01** — BAF jackpot `_jackpotTicketRoll` xorshift refactor deferred (ENT-05); SURF-02 byte-identity grep-proof verifies deferral discipline. ✓
- **D-266-SCOPE-OUT-02** — Zero EntropyLib API additions; SURF-01 verification confirms. ✓
- **D-266-SCOPE-OUT-03** — Zero behavioral-replay tests; STAT-02 asserts distribution-shape uniformity-equivalence only. ✓
- **D-266-SCOPE-OUT-04** — KNOWN-ISSUES.md "Lootbox RNG uses index advance isolation" entry NOT addressed in v36 (separate cleanup deferred). ✓
- **D-266-FIND-01** (carry of D-265-FIND-01) — Default zero F-36-NN finding blocks; HIGH severity ceiling. ✓ (zero blocks emit)
- **D-266-ADVERSARIAL-01** — `/contract-auditor` + `/zero-day-hunter` only; explicit exclusion of `/economic-analyst` + `/degen-skeptic`. ✓
- **D-266-ADVERSARIAL-02** — Sequential spawn AFTER finished §4 draft (not parallel due to inline orchestrator-execution mode; functionally equivalent — both red-teamed the same finished draft). ✓
- **D-266-ADVERSARIAL-03** — Disagreement disposition gate (zero disagreements logged in `266-01-ADVERSARIAL-LOG.md`; no user disposition needed). ✓
- **D-266-CLOSURE-01** — Closure SHA = post-Task-19 §9 attestation commit `1c0f0913` (resolved at Task 20 via `git rev-parse HEAD`). ✓
- **D-266-CLOSURE-02** (carry of D-265-CLOSURE-02) — §9.NN TWO-subsection format (i USER-APPROVED contracts + ii USER-APPROVED tests + iii AGENT-COMMITTED audit artifacts; NO awaiting-approval subsection). ✓
- **D-266-FCITE** (carry of D-265-FCITE-01) — Zero forward-cite emission across Phase 266 artifacts (terminal-phase invariant). ✓
- **D-266-SEV-01** — D-08 5-bucket severity rubric inherited from v25 onward via Phase 253 / 257 / 262 / 265 carry. ✓
- **D-266-APPROVAL-01** — All audit/.planning writes agent-author; user reviews diff before push per `feedback_manual_review_before_push.md`. ✓
- **D-266-APPROVAL-02** — `contracts/` + `test/` commits USER-APPROVED batched at Wave 1 + Wave 2 gates per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. ✓

## Task Commits (chronological)

```
1c0f0913  audit(266): Task 19 — §9 milestone closure attestation (verdict distribution + attestation block + §9.NN commit-readiness register)
fd32da69  audit(266): Task 18 — §7 prior-artifact cross-cites + §8 forward-cite closure
5d51869f  docs(266): Task 17 — rephrase KNOWN-ISSUES.md EntropyLib XOR-shift entry to BAF-jackpot-only scope
c16d6fc6  audit(266): Task 16 — §6 KI Gating Walk + EXC-04 NARROWS + AUDIT-05 verdict
8801a99a  audit(266): Task 15 — §5 regression appendix (REG-01 + REG-02 + REG-04)
ce8b045f  audit(266): Task 14 — adversarial pass complete (/contract-auditor + /zero-day-hunter, 0 disagreements)
8a82bc36  docs(266): Task 14 — adversarial-pass log skeleton
fb9c0cea  audit(266): Task 13 — §4 6-surface inline draft (a-f) — AUDIT-02 pre-adversarial-pass
a2fb80a5  audit(266): Task 12 — §3a + §3d delta-surface table + §3e conservation re-proof
d8b97791  audit(266): Task 11 — §1 frontmatter + §2 Executive Summary skeleton
75a4f73b  docs(v37.0): seed v37 maintenance note — _resolveLootboxRoll dead BURNIE-conversion branch
16ed452b  test(266): chi² + gas + surface preservation [STAT-01..03 + GAS-01..02 + SURF-01..04]   ← Wave 2 USER-APPROVED batched
df6345cc  feat(266): lootbox-path entropy refactor [ENT-01..06]                                   ← Wave 1 USER-APPROVED batched
60fe1e43  docs(266): create phase plan — single 21-task multi-wave plan + pattern map + STATE/ROADMAP flips
fe93d8c5  docs(266): research lootbox-path entropy refactor — bit-budget arithmetic + chi² calibration + 5-wave plan
bcf3214f  docs(v36.0): open milestone — Phase 266 lootbox-entropy-refactor scaffolding
```

(Task 20 atomic-update commit + Task 21 close-out commit append after this SUMMARY commit lands.)

## Closure Signal

```
MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
```

## Notes

- **Inline-execution mode chosen at execute-phase open.** Per user disposition (2026-05-10), Phase 266 was executed inline (orchestrator-driven) rather than via `gsd-executor` subagent delegation. This mirrors the v35.0 Phase 265 close pattern after the global `.md`-write guard pattern-matching FINDINGS/SUMMARY/ADVERSARIAL-LOG filenames blocked subagent delegation. All 21 atomic-commit tasks executed inline; adversarial-pass `/contract-auditor` + `/zero-day-hunter` spawned via Skill tool (skills load into orchestrator context for review work — no .md-write guard interference).

- **Wave 2 gas-pin drift acceptance.** During Wave 2 verification (Task 10 user-approval gate), `npm run test:stat` showed flaky ~120K gas-pin drift in `Phase261GasRegression.test.js` (terminal jackpot stage 10) and `Phase264GasRegression.test.js` (STAGE_PURCHASE_DAILY stage 6) due to Decimator-path lootbox resolution being on the call path of those stages. Standalone runs of the same tests pass at the pinned values. User accepted the flaky behavior at the Wave 2 gate ("128k is fine approved"); future re-pinning pass deferred to v37.0 maintenance scope.

- **v37.0 maintenance-scope note seeded.** `/contract-auditor` adversarial pass surfaced a pre-existing dead BURNIE-conversion branch in `_resolveLootboxRoll` L1574 (Hypothesis (m)). Per user disposition (2026-05-10), this is deferred to v37.0 cleanup scope at `.planning/notes/2026-05-10-resolveLootboxRoll-dead-burnie-conversion-branch.md`. Not a Phase 266 finding (pre-existing at v35.0 baseline; survives the refactor unchanged); ~50 g/open savings + bytecode shrink available in v37.

- **Decimator-path cross-module composition.** `_resolveLootboxDirect` is invoked via delegatecall from `DegenerusGameDecimatorModule.sol:594` and `DegenerusGameDegeneretteModule.sol:733/753` (both UNTOUCHED at v36). /zero-day-hunter Hypothesis Z1 verified: per-level `decClaimRounds[lvl].rngWord` isolation forecloses cross-level seed collision; same-player same-day claims at different levels produce distinct seeds.

- **Bit-allocation map disjointness invariant.** 8 consumers consume bit ranges [0..15] / [16..23] / [24..39] / [40..55] / [56..79] / [80..95] / [96..119] / [120..151]. Cumulative consumption 152 bits / 256 available. Future phases adding a 9th consumer MUST extend the map at `_resolveLootboxCommon` L835-849 (cited in /contract-auditor Hypothesis (l) + /zero-day-hunter Hypothesis Z6 forward-looking defensive notes).
