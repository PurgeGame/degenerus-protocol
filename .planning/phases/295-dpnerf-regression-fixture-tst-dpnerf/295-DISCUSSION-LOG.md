# Phase 295: DPNERF Regression Fixture (TST-DPNERF) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 295-dpnerf-regression-fixture-tst-dpnerf
**Areas discussed:** EV methodology (TST-DPNERF-04), BURNIE coverage (TST-DPNERF-03), Gas scope, Callsite scope

---

## EV Methodology (TST-DPNERF-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid: 1000 JS-replay + small-N production cross-attest | Mirror Phase 293 D-293-INVOKE-01: JS-reference impl of `_randTraitTicket` drives the 1,000 iterations (deterministic, ~sec-scale); ~16-32 production-path replays via natural jackpot resolution attest JS↔EVM bit-identity (`virtualCount` is private so no direct read — assert by counting deity wins in returned winners[] across 25-winner draws and cross-attesting with JS replay). Fast + audit-grade evidence. | ✓ |
| Pure JS-replay (no on-chain replay) | Skip production-path cross-attestation; rely on Phase 294 §6 zero-new-state grep-proof + §2/§4 byte-identity attestations as the EVM↔JS bridge. Fastest path; weakest evidence link to runtime EVM behavior. | |
| Pure production-path (all 1000 on-chain) | Invoke the natural jackpot resolution path 1000 times against worst-case-seeded state. Strongest direct evidence; test runtime could be tens of minutes to hours; bucket-setup cost per iteration is significant. | |

**User's choice:** Hybrid (Recommended)
**Notes:** Recorded as D-295-EV-METHODOLOGY-01. Mirrors Phase 293 D-293-INVOKE-01 lineage. JS-reference helper mirrors BOTH `_randTraitTicket` 25-winner ETH draw AND `_awardDailyCoinToTraitWinners` inline-duplicate 1-winner BURNIE draw; cross-attestation N (16-32) is planner-chosen within band per chi² goodness-of-fit threshold.

---

## BURNIE Coverage (TST-DPNERF-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Natural production-path BURNIE invocation | Set up a BURNIE coin-jackpot scenario (mint deity-pass, populate near-future ticketQueue, fund coin budget), invoke `payDailyCoinJackpot` against worst-case-seeded gold-tier holder buckets, assert `virtualCount == 1` semantics via the resulting winners[] selection. Provides direct natural-flow evidence for the BURNIE half of D-42N-PATH-COVERAGE-01. | ✓ |
| JS-replay only, with structural argument | Cite D-294-CALLER-UNIFORM-01 as the structural proof; attest in test JSDoc that production-path replay is unnecessary because the function body is the SOLE delivery mechanism. Saves significant test scaffolding for the BURNIE coin-jackpot flow. | |
| Both: JS-replay primary + 1 production-path smoke check | JS-replay for the assertion bulk; one production-path `payDailyCoinJackpot` invocation as a smoke check. Middle ground. | |

**User's choice:** Natural production-path BURNIE invocation (Recommended)
**Notes:** Recorded as D-295-BURNIE-PATH-01. Roadmap success criterion 3 explicitly mandates the natural-production-flow invocation shape (`payDailyCoinJackpot` → `_awardDailyCoinToTraitWinners` → `_randTraitTicket`). The BURNIE path is NOT a literal caller of `_randTraitTicket`; the gold-tier branch logic is inline-duplicated at L1867-L1874 per the Phase 294 BURNIE gap-closure amendment commit `38319463` — JSDoc MUST grep-verify the inline-duplicate site explicitly per `feedback_verify_call_graph_against_source.md`.

---

## Gas Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Skip entirely — mirror D-291-GAS-01 | No gas requirement, no gas helper, no assertion, no informational `console.log`. Phase 294 §5 attestation (+86 byte deployment-size; ~20-50 gas per-call runtime) is load-bearing for Phase 297 §3.A. Tightest scope; matches Phase 291 precedent. | ✓ |
| Informational `console.log` per-call gas only | Add a single `console.log` measuring gas of one gold-tier `_randTraitTicket` invocation vs one common-tier — no hard assertion, no regression bound. Lightweight signal without scope expansion. | |
| Hard regression assertion against +50 gas per-call worst-case | Adds a TST-DPNERF-06-equivalent gas regression bound. Expands locked requirement set; would surface to user for scope authorization at plan-phase. | |

**User's choice:** Skip entirely (Recommended)
**Notes:** Recorded as D-295-GAS-01. Phase 295 roadmap success criteria are silent on gas; theoretical-first attestation per `feedback_gas_worst_case.md` already shipped at Phase 294 §5. DPNERF per-call runtime gas (~20-50 gas) is negligible; +86 byte runtime bytecode delta is deployment-size cost, not per-call. Plan-phase MUST NOT add gas helper / assertion / informational log.

---

## Callsite Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Hold scope — callsites 3+4+BURNIE only | TST-DPNERF-01..05 cover callsites 3 (L1296 `_processDailyEth`) + 4 (L1399 `_resolveTraitWinners`) + BURNIE path; callsites 1+2 deferred to Phase 296 SWEEP per D-294-CALLER-UNIFORM-01 SWEEP-scope expansion. Matches Phase 294 §3 callsite enumeration handoff. | ✓ |
| Expand scope — add TST-DPNERF-06 + TST-DPNERF-07 for callsites 1 + 2 | Adds explicit production-path coverage for early-bird lootbox jackpot + ticket distribution to bucket callsites. Doubles test scaffolding (both paths have non-trivial state setup). Expands locked requirement set. | |
| Hold scope + add a JSDoc callsite-coverage table | Same as recommended, but add a JSDoc table in test header explicitly enumerating all 5 callsites (4 ETH + 1 BURNIE) with coverage disposition per test. Documentation-only addition; no test logic. | |

**User's choice:** Hold scope (Recommended)
**Notes:** Recorded as D-295-CALLSITE-SCOPE-01. Selected the documentation-augmentation from option 3 implicitly as a Claude's-discretion add — TST-DPNERF JSDoc MUST include the callsite-coverage table (5 rows: 1 L698 deferred, 2 L988 deferred, 3 L1296 covered-by-TST-DPNERF-01/02, 4 L1399 covered-by-TST-DPNERF-04, BURNIE L1867 inline-duplicate covered-by-TST-DPNERF-03+04) per `feedback_verify_call_graph_against_source.md` enforcement. Phase 296 SWEEP adversarially attests callsites 1+2 per the Phase 294 SUMMARY carry-forward.

---

## Claude's Discretion

The following gray areas were resolved as defaults at discuss-phase WITHOUT raising for user disposition (Phase 291 + Phase 293 + Phase 282 sister-phase patterns provide the established defaults):

- **D-295-INVOKE-01** — Test-invocation strategy for `_randTraitTicket`: JS-replay oracle ALGORITHM_VERIFIED per Phase 282 → 291 → 293 lineage. Visibility-flip escalation path is NOT pre-approved.
- **TST-DPNERF-01 + TST-DPNERF-02 single-call assertion shape**: production-path replay via natural jackpot resolution; one invocation each.
- **TST-DPNERF-05 non-deity branch assertion**: production-path replay with `deityBySymbol[fullSymId] == address(0)`; assert ZERO deity-sentinel entries in 25-winner draw.
- **Test file location**: `test/edge/DeityPassGoldNerfRegression.test.js` per Phase 291/293 adjacency.
- **JS-reference helper file**: `test/helpers/randTraitTicketRef.mjs` per Phase 282/291/293 file-separation discipline.
- **Test fixture deployment shape**: `test/helpers/deployFixture.js` reuse verbatim; natural production-path seeding preferred over `hardhat_setStorageAt` synthetic seeding (acceptable fallback if scaffolding cost dominates).
- **Single USER-APPROVED batched test commit** at phase close per `feedback_batch_contract_approval.md`.
- **KNOWN-ISSUES.md UNMODIFIED** per implicit Phase 295 default mirroring D-281-KI-01 + D-291-KI-01 + D-293-KI-01.

## Deferred Ideas

- D-295-INVOKE-01 visibility-flip Phase 294 amendment (NOT pre-approved escalation path)
- Empirical gas regression bench (skipped per D-295-GAS-01, not deferred to future test phase)
- Hard regression assertion against +50 gas per-call (TST-DPNERF-06 candidate, out of scope)
- Callsites 1 + 2 explicit production-path coverage (TST-DPNERF-06 + TST-DPNERF-07 candidates, deferred to Phase 296 SWEEP)
- Helper extraction to `test/helpers/jackpotEVMath.mjs` (deferred to v43+ test-maintenance if consumer count grows)
- `rollHeroSymbolRef.mjs` + `raritySymbolBatchRef.mjs` in-place extension with DPNERF (explicitly NOT done; new helper file per audit-subject-per-file convention)
- KNOWN-ISSUES.md modification at v42 close (Phase 297 terminal handles disposition)
