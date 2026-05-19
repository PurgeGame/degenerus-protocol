# Requirements: Degenerus Protocol — Audit Repository

**Defined:** 2026-05-18
**Milestone:** v43.0 Total rngLock Determinism Audit — Every VRF Input Frozen at Commitment
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01` (user-authorization 2026-05-18); contract remediations deferred to v44.0 FIX-MILESTONE
**Audit baseline:** v42.0 closure HEAD `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

---

## v43.0 Goal (precise statement)

At `rngLockedFlag = true`, every storage slot that participates in deriving any VRF-influenced output is **frozen** until `rngLockedFlag = false`. The only values that may be unknown at lock time are the incoming VRF word and its deterministic derivations from that word. No external/public function call (including admin/owner) may mutate any participating slot during the rngLock window, with three explicit exempt entry points.

**Exempt entry points (may mutate participating slots during the window):**
1. `advanceGame()` and every function reachable from it — the resolution orchestrator itself.
2. The VRF coordinator callback that delivers `randomness` — the VRF-word arrival path.
3. `retryLootboxRng()` failsafe — ≥6h cooldown gate + ≤1 VRF-replacement per stall event + does not manipulate any pre-lock state (`D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A accepted).

**No SAFE_BY_DESIGN escape hatch for participating slots.** "Could possibly affect" = theoretical reachability; eliminate even if economic likelihood is LOW. Game-theoretic analysis is not a substitute for structural elimination.

**AUDIT-ONLY posture (`D-43N-AUDIT-ONLY-01`):** v43.0 catalogs every VIOLATION + produces per-VIOLATION FIXREC + per-admin-function ADMA + Foundry fuzz harness (with `vm.skip` on CATALOG VIOLATIONs to keep CI green) + 3-skill HYBRID adversarial sweep + 9-section terminal findings deliverable. **Zero `contracts/` mutations.** Single `test/` mutation at Phase 301 FUZZ harness. Actual contract remediations land in v44.0 FIX-MILESTONE consuming v43.0 CATALOG + FIXREC + ADMA artifacts as load-bearing input.

---

## v43.0 Requirements

### Catalog (CAT) — VRF Read-Graph Enumeration

- [x] **CAT-01**: Enumerate every code site that consumes VRF-derived entropy (every read of `randomness`, every keccak/xorshift chain rooted at the VRF word). Output: complete consumer-site list with file:line citations, grep-verified against source per `feedback_verify_call_graph_against_source.md`.
- [x] **CAT-02**: For each VRF consumer site, walk every reachable SLOAD inside the resolution code path. Output: complete per-consumer SLOAD list with slot-name + module + file:line. No "by construction" or "covered by single fn" claims — every SLOAD enumerated explicitly per `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE gap precedent).
- [x] **CAT-03**: For each unique participating slot identified in CAT-02, enumerate every external/public function (any contract in `contracts/`) that writes that slot. Includes ERC20/ERC721 inherited writers (transfer, transferFrom, approve, _mint, _burn) where applicable; admin/owner functions; affiliate registration writers; anything reachable from a non-internal entry point.
- [x] **CAT-04**: Per-(slot × writer) verdict table. Classifications: `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION`. Every non-exempt writer = VIOLATION. No discretionary classifications.
- [x] **CAT-05**: Output `.planning/RNGLOCK-CATALOG.md` artifact: per-consumer SLOAD list + per-slot writer enumeration + (slot × writer) verdict table + remediation-tactic recommendation per violation pair (a/b/c/d menu per FIX-01). Catalog table is load-bearing input for downstream FIX phases.
- [x] **CAT-06**: Catalog completeness gate — independent grep sweep of `contracts/` confirms no participating slot or writer is missed (grep patterns: `function .*external`, `function .*public`, `slot:`, `assembly { sstore`, every storage variable declaration). Recorded as attestation in CAT-05 artifact.

### Fix Recommendation (FIXREC) — Per-VIOLATION Analysis-Only Documentation

> **AUDIT-ONLY repurpose** per `D-43N-AUDIT-ONLY-01`. Pre-pivot FIX-01..05 (structural-elimination contract changes) deferred to **v44.0 FIX-MILESTONE**. FIXREC-01..05 produce per-VIOLATION analytical documentation that v44.0 plan-phase consumes.

- [x] **FIXREC-01**: For each VIOLATION tuple in CAT-04, recommend one tactic from the menu — (a) `rngLockedFlag`-gated revert; (b) snapshot/anchor (Phase 288 `dailyIdx` + Phase 281 owed-salt precedents); (c) re-order to pre-lock; (d) immutable. Output: recommendation entry with 1-line rationale per `D-298-RECOMMEND-DEPTH-01`.
- [x] **FIXREC-02**: For each VIOLATION, design-intent backward-trace per `feedback_design_intent_before_deletion.md` — cite the original phase that introduced the slot/writer (Phase 281 owed-salt / Phase 288 dailyIdx / Phase 290 MINTCLN / Phase 292 HRROLL / Phase 294 DPNERF / Phase 296 RETRY_LOOTBOX_RNG / pre-v25 baseline / etc.); document why the slot exists + what behavior would break if naively gated.
- [x] **FIXREC-03**: For each VIOLATION, actor game-theory walk — who would exploit this VIOLATION (player class, MEV bot, admin, external contract), how (specific action sequence during rngLock window), EV magnitude estimate (LOW / MEDIUM / HIGH / CATASTROPHE-tier), economic-likelihood disposition.
- [x] **FIXREC-04**: For each VIOLATION, impact estimate for the recommended tactic — bytecode delta direction (saves / adds / neutral; rough byte count); storage layout impact (byte-identical / new slot added / slot moved); public ABI impact (event topic-hash change / new error / unchanged); BREAKING-vs-NON-BREAKING classification per `D-40N-EVT-BREAK-01` + `D-42N-EVT-BREAK-01` precedent.
- [x] **FIXREC-05**: For each VIOLATION, v44.0 FIX-MILESTONE handoff anchor — locked-decision ID `D-43N-V44-HANDOFF-NN` per VIOLATION + file:line cite into RNGLOCK-FIXREC.md + cross-reference to RNGLOCK-CATALOG.md verdict-matrix row. v44.0 plan-phase consumes these anchors as load-bearing input for FIX-NN sub-phase planning.

### Admin Path Enumeration Audit (ADMA) — Admin/Owner Sweep (Analysis-Only)

> **AUDIT-ONLY repurpose** per `D-43N-AUDIT-ONLY-01`. Pre-pivot ADM-01..04 (contract revert-gating + regression tests) deferred to **v44.0 FIX-MILESTONE**. ADMA-01..04 produce per-admin-function enumeration + recommendation.

- [x] **ADMA-01**: Enumerate every `onlyOwner` / `onlyAdmin` / role-gated external function across all modules in `contracts/`. Output: complete function list with file:line + role-gate annotation.
- [x] **ADMA-02**: For each admin function, identify slot writes (cross-reference with CAT-03 writer table). Mark which functions write participating slots at any non-EXEMPT callsite.
- [x] **ADMA-03**: For each admin function reaching a participating slot, recommended gating mechanism = `RngLocked` custom error revert (preferred per existing MintModule:1221 / BurnieCoinflip:730 / sStonk:492 convention). Document per-admin-function rationale + governance / parameter-update / charity-allowlist / decimator-config / presale-config classification.
- [x] **ADMA-04**: For each ADMA recommendation, v44.0 FIX-MILESTONE handoff anchor — locked-decision ID `D-43N-V44-ADMA-NN` per admin function + cross-reference to RNGLOCK-CATALOG.md verdict-matrix rows. v44.0 plan-phase consumes these anchors for ADM-NN contract-change sub-phase planning.

### Fuzz (FUZZ) — State-Shuffle Determinism Harness

> **AUDIT-ONLY posture:** test-tree only (no `contracts/` mutations). `vm.skip` strategy per `D-43N-FUZZ-VMSKIP-01` keeps CI green at v43.0 close — v44.0 flips skips to assertions as fixes land. **AGENT-COMMITTED** per `D-43N-TEST-COMMITS-AUTO-01` (only mainnet `.sol` files require explicit approval per `feedback_no_contract_commits.md` clarified policy).

- [x] **FUZZ-01**: Foundry harness `test/fuzz/RngLockDeterminism.t.sol` (or equivalent name) — fuzzes randomized action sequences mid-rngLock window (between VRF request and fulfillment). Runs count: 10k per fuzz case per `D-43N-FUZZ-RUNS-01`. **SHIPPED Phase 301 plan 06 — FOUNDRY_PROFILE=deep 10k runs PASS on RetryLootboxRng (the 1 non-skipped opposite-direction test); 17 vm.skip blocks at FIXREC sec_N + HANDOFF-NN cross-references.**
- [x] **FUZZ-02**: Action set includes — bets, mints, claims, ERC20/ERC721 transfers, approvals, affiliate registration, every admin/owner function (ADMA-01 enumeration as input), `retryLootboxRng` invocations. **SHIPPED Phase 301 plan 06 — `_perturb(seed)` covers 9 actions (0-8); `_perturbAdminOnly(seed)` covers ADMA R-01..R-22.**
- [x] **FUZZ-03**: For each randomized perturbation sequence, asserts every VRF-derived output (jackpot recipients, jackpot amounts, trait awards, lootbox tickets, hero-override outcome) is byte-identical to the no-perturbation baseline. **`vm.skip` strategy per `D-43N-FUZZ-VMSKIP-01`:** fuzz cases that reproduce a CATALOG VIOLATION at current contract state are `vm.skip`-gated (CI green); v44.0 FIX-MILESTONE flips each `vm.skip` to a strict assertion as the corresponding fix lands per the FIXREC-05 handoff anchors. **SHIPPED Phase 301 plan 06 — `_assertVrfOutputByteIdentity(perturbed, baseline, label)` shared assertion site; 17 vm.skip blocks per D-301-VMSKIP-MECHANISM-01 Option C.**
- [x] **FUZZ-04**: Coverage: every VRF-influenced output surface enumerated in CAT-01 (whole 13-consumer set) is exercised by at least one fuzz case. **SHIPPED Phase 301 plan 06 — all 13 CAT-01 surfaces covered by `testFuzz_RngLockDeterminism_*` functions.**
- [x] **FUZZ-05**: Edge cases — admin-during-lock perturbations, near-end-of-window perturbations (last block before unlock), multi-tx-batch perturbations, multi-block perturbations within the window, retryLootboxRng-during-lock perturbations (failsafe path). **SHIPPED Phase 301 plan 06 — 5 `testFuzz_EdgeCase_*` functions per D-301-EDGE-CASES-01.**

### Adversarial Sweep (SWP) — 3-Skill HYBRID Pass

- [x] **SWP-01**: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass charged with finding any storage path violating the freeze invariant. Output: hypothesis-disposition table. **COMPLETE 2026-05-19** — `.planning/phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-CONTRACT-AUDITOR.md` ships full disposition table (9 charged hypotheses + 2 beyond-charge).
- [x] **SWP-02**: `/zero-day-hunter` PARALLEL_SUBAGENT pass on novel attack surfaces (composition attacks, cross-module read/write races, ERC-callback-induced state mutations, multi-block window exploits). Output: hypothesis-disposition table. **COMPLETE 2026-05-19** — `.planning/phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-ZERO-DAY-HUNTER.md` ships full disposition table (9 charged hypotheses + 3 beyond-charge). HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT per v42 P296 precedent (executor lacked Task tool for PARALLEL_SUBAGENT spawn); persona fidelity preserved via verbatim CHARGE prompt application.
- [x] **SWP-03**: `/economic-analyst` PARALLEL_SUBAGENT pass on game-theoretic write-induced effects (incentive-compatible adversarial actions during window). Output: hypothesis-disposition table. **COMPLETE 2026-05-19** — `.planning/phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-ECONOMIC-ANALYST.md` ships full disposition table (9 charged hypotheses + 2 beyond-charge). HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT per v42 P296 precedent.
- [x] **SWP-04**: Disposition: any FINDING_CANDIDATE routes to an appended FIXREC entry (Phase 299 artifact augmentation; no contract change at v43 per audit-only posture). Any SAFE_BY_DESIGN candidate is REJECTED — milestone goal precludes SAFE_BY_DESIGN dispositions for participating slots. Two-pass re-pass discipline per D-284-ADVERSARIAL-RE-PASS-01 carry if any FIXREC-augment commit lands after initial pass. **COMPLETE 2026-05-19** — ZERO_FINDING_ELEVATION outcome; user fast-path disposition 2026-05-19 accept-as-documented for all 5 Tier-1 items; Task 6 elevation routing SKIPPED per `D-302-AUDIT-ONLY-ROUTING-01` conditional gating; NO FIXREC-augment authored; NO RE-PASS required.
- [x] **SWP-05**: `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. `/economic-analyst` IN SCOPE per D-271-ADVERSARIAL-03 carry. **Invocation pre-authorized** per `D-43N-SWEEP-PREAUTH-01` (user-authorization 2026-05-18) — Phase 302 fires the 3-skill HYBRID without re-pinging; Tier-1 any-skill FINDING_CANDIDATE still pings per D-296-CONSENSUS-01 user-review checkpoint discipline. **COMPLETE 2026-05-19** — `/degen-skeptic` OUT OF SCOPE attestation in 302-01-ADVERSARIAL-LOG.md header + footer; `/economic-analyst` IN SCOPE delivered SWP-03; pre-authorization documented in LOG; Tier-1 user-review ping discipline preserved (5 items batched into single AskUserQuestion).

### Audit Deliverable (AUDIT) — FINDINGS-v43.0.md Terminal

- [ ] **AUDIT-01**: `audit/FINDINGS-v43.0.md` 9-section terminal deliverable. §3.A delta-surface table enumerates every AGENT-COMMITTED test/audit/planning commit across v43.0 phases (Phase 301 FUZZ test commit AGENT-COMMITTED per `D-43N-TEST-COMMITS-AUTO-01`). `contracts/` delta row count = 0 per audit-only posture per `D-43N-AUDIT-ONLY-01`.
- [ ] **AUDIT-02**: §3.B per-exempt-entry-point attestation matrix — for each of the 3 exempt entry points, per-participating-slot row proves the exempt write does not violate downstream invariants.
- [ ] **AUDIT-03**: §3.C conservation re-proof for the freeze invariant — every participating slot has a 4-tuple attestation (slot identity / writer-set / freeze gate / consumer-set).
- [ ] **AUDIT-04**: §3.D Phase 299 FIXREC roll-up — per-VIOLATION recommendation table (tactic + impact estimate + v44.0 handoff anchor); cross-references `.planning/RNGLOCK-FIXREC.md`.
- [ ] **AUDIT-05**: §3.E Phase 300 ADMA roll-up — per-admin-function gating recommendation table; cross-references `.planning/ADMIN-AUDIT.md`.
- [ ] **AUDIT-06**: §4 adversarial-pass disposition table — every hypothesis (charged + beyond-charge) from SWP-01..03 with verdict.
- [ ] **AUDIT-07**: §5 LEAN regression — REG-01 (v42.0 non-widening) + REG-02 (v41.0 non-widening) + REG-03 (v40.0 non-widening) + REG-04 (prior-finding spot-check across v25..v42).
- [ ] **AUDIT-08**: §6 KI walkthrough — EXC-01..03 RE_VERIFIED-NEGATIVE-scope at v43; EXC-04 STRUCTURALLY ELIMINATED preserved. KNOWN-ISSUES.md UNMODIFIED per `D-43N-KI-01` default zero-promotion lineage.
- [ ] **AUDIT-09**: §9 closure attestation — AUDIT-only verdict + 6-phase wave summary + closure signal + Deferred-to-Future register (v44.0 FIX-MILESTONE entry MANDATORY with consolidated handoff-anchor list).

### Regression (REG) — Cross-Milestone Non-Widening Proofs

- [ ] **REG-01**: v42.0 closure non-widening — every v42.0 audit-subject surface (MINTCLN, HRROLL, DPNERF, RETRY_LOOTBOX_RNG) is byte-identical at v43.0 close. **No exceptions per `D-43N-AUDIT-ONLY-01`** (zero `contracts/` mutations across v43.0).
- [ ] **REG-02**: v41.0 closure non-widening — F-41-01/02/03 fix sites preserved (owed-salt at mint-batch; `dailyIdx` anchor at hero-override; cross-day determinism). Byte-identical.
- [ ] **REG-03**: v40.0 closure non-widening — whole-ticket Bernoulli sites + ENT-05 keccak refactor + `_queueLootboxTickets` retirement + whole-BURNIE floor preserved. Byte-identical.
- [ ] **REG-04**: Prior-finding spot-check across `audit/FINDINGS-v25..v42.0.md` for any v43-touched surface set — no regression of prior-milestone fixes. Audit-only posture makes this REG-04 trivially PASS (no contract surface touched).

### Closure (CLS) — Terminal Closure-Flip

- [ ] **CLS-01**: 2-commit sequential SHA orchestration per D-297-CLOSURE-01 + D-284-CLOSURE-01 precedent — Commit 1 ships audit deliverable with `<commit-1-sha>` placeholder; Commit 2 resolves placeholder + propagates verbatim + chmod 444 + atomic 5-doc closure flip (ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS). **Pre-authorized** per `D-43N-CLOSURE-PREAUTH-01`.
- [ ] **CLS-02**: Closure signal `MILESTONE_V43_AT_HEAD_<sha>` propagated atomically across all 5 docs. `audit/FINDINGS-v43.0.md` chmod 444 (read-only at closure).

---

## Deferred to Future Milestones

Items explicitly out of v43.0 scope; carried forward via locked-decision IDs per `D-297-DEFER-01` + `D-281-FCITE-01` carry chain:

- **v44.0 FIX-MILESTONE (MANDATORY follow-up)** — actual contract remediations for every Phase 298 CATALOG VIOLATION. Consumes Phase 299 FIXREC + Phase 300 ADMA artifacts as load-bearing input. One sub-phase per FIXREC entry (or per-slot grouping per v44 plan-phase discretion). Locked-decision anchors: `D-43N-V44-HANDOFF-NN` (one per FIXREC entry) + `D-43N-V44-ADMA-NN` (one per ADMA recommendation).
- **`D-42N-MINTCLN-SCOPE-01`** — MINTCLN helper-extraction handoff. Not freeze-invariant-related.
- **`D-42N-EVT-BREAK-01`** — indexer-migration handoff for `TraitsGenerated` topic-hash break. Off-chain, user-owned.
- **`D-40N-LBX02-OUT-01`** — LBX-02 fixture-coverage gap carry. Analytical worst-case load-bearing.
- **`D-40N-MINTBOOST-OUT-01`** — mint-boost fractional retirement carry.
- **Game-over thorough hardening** — separate dedicated milestone scope.
- **`D-42N-RETRY-RNG-LAUNCH-FAQ-01`** — launch-comms FAQ entries from `/economic-analyst` INFO observations on (xiv).
- **`D-42N-RETRY-RNG-SCOPE-DOC-01`** — docstring/scope-boundary observation from `/contract-auditor` MEDIUM-tier note on (xiv).
- **Superseded-baseline SURF `it.skip` cleanup + launch-posture KI policy** — combined v42-baseline carry per `D-281-KI-01` rationale.

## Out of Scope

Explicitly excluded from v43.0; documented to prevent scope creep:

| Feature | Reason |
|---------|--------|
| Contract changes (any `contracts/` mutation) | AUDIT-ONLY posture per `D-43N-AUDIT-ONLY-01` user-authorization 2026-05-18. Actual remediations deferred to v44.0 FIX-MILESTONE. |
| Regression test coverage paired to FIX waves (TST-NN test files) | No FIX waves in v43.0 → no paired tests. v44.0 FIX-MILESTONE owns the surface-pair test phases. |
| `retryLootboxRng` structural rework | Failsafe per user disposition 2026-05-18 — ≤1 VRF→VRF replacement per stall event; does not manipulate pre-lock state. `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A accepted. |
| SAFE_BY_DESIGN dispositions for participating slots | Milestone goal explicitly precludes — "could possibly affect" = theoretical reachability; eliminate even if economic likelihood is LOW. |
| Off-chain indexer migration tooling | Off-chain handoff; v43.0 owns only audit + planning + 1 test-tree (FUZZ harness) artifacts. |
| Game-over hardening | Out-of-scope per dedicated future milestone framing. |
| Mint-boost fractional retirement | Out per `D-40N-MINTBOOST-OUT-01` carry. |
| New features / behavioral additions | v43.0 is purely audit — no new game mechanics, no economic-parameter changes, no new entry points. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CAT-01..06 | Phase 298 | Complete |
| FIXREC-01..05 | Phase 299 (audit-only repurpose per `D-43N-AUDIT-ONLY-01`) | Pending |
| ADMA-01..04 | Phase 300 (audit-only repurpose per `D-43N-AUDIT-ONLY-01`) | Pending |
| FUZZ-01..05 | Phase 301 (test-tree only; `vm.skip` strategy) | **COMPLETE 2026-05-18** (test/fuzz/RngLockDeterminism.t.sol; 18 fuzz functions; 17 vm.skip; forge test PASS at FOUNDRY_PROFILE=deep 10k runs) |
| SWP-01..05 | Phase 302 (3-skill HYBRID; invocation pre-authorized) | **COMPLETE 2026-05-19** (ZERO_FINDING_ELEVATION fast-path; 5 artifacts shipped: CHARGE + 3 per-skill MDs + integrated LOG; user disposition 5/5 accept-as-documented; Task 6 SKIPPED; documentation-class items → Phase 303 §6; FUZZ-harness extension → v44.0) |
| AUDIT-01..09 | Phase 303 (9-section TERMINAL deliverable) | Pending |
| REG-01..04 | Phase 303 | Pending |
| CLS-01..02 | Phase 303 (closure-flip pre-authorized) | Pending |

**Coverage:**
- v43.0 requirements: 40 total (6 CAT + 5 FIXREC + 4 ADMA + 5 FUZZ + 5 SWP + 9 AUDIT + 4 REG + 2 CLS) + 1 implicit no-SAFE_BY_DESIGN gate at SWP-04
- Mapped to phases: 40
- Unmapped: 0 ✓

**Phase numbering note:** Phase count FIXED at 6 (298-303) per `D-43N-AUDIT-ONLY-01` audit-only pivot. No envelope expansion — FIXREC + ADMA are single AGENT-COMMITTED artifacts covering all VIOLATIONs.

---

*Requirements defined: 2026-05-18*
*Last updated: 2026-05-18 after v43.0 milestone OPENED*
