# Requirements: Degenerus Protocol — Audit Repository

**Defined:** 2026-05-18
**Milestone:** v43.0 Total rngLock Determinism — Every VRF Input Frozen at Commitment
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

---

## v43.0 Requirements

### Catalog (CAT) — VRF Read-Graph Enumeration

- [ ] **CAT-01**: Enumerate every code site that consumes VRF-derived entropy (every read of `randomness`, every keccak/xorshift chain rooted at the VRF word). Output: complete consumer-site list with file:line citations, grep-verified against source per `feedback_verify_call_graph_against_source.md`.
- [ ] **CAT-02**: For each VRF consumer site, walk every reachable SLOAD inside the resolution code path. Output: complete per-consumer SLOAD list with slot-name + module + file:line. No "by construction" or "covered by single fn" claims — every SLOAD enumerated explicitly per `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE gap precedent).
- [ ] **CAT-03**: For each unique participating slot identified in CAT-02, enumerate every external/public function (any contract in `contracts/`) that writes that slot. Includes ERC20/ERC721 inherited writers (transfer, transferFrom, approve, _mint, _burn) where applicable; admin/owner functions; affiliate registration writers; anything reachable from a non-internal entry point.
- [ ] **CAT-04**: Per-(slot × writer) verdict table. Classifications: `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION`. Every non-exempt writer = VIOLATION. No discretionary classifications.
- [ ] **CAT-05**: Output `.planning/RNGLOCK-CATALOG.md` artifact: per-consumer SLOAD list + per-slot writer enumeration + (slot × writer) verdict table + remediation-tactic recommendation per violation pair (a/b/c/d menu per FIX-01). Catalog table is load-bearing input for downstream FIX phases.
- [ ] **CAT-06**: Catalog completeness gate — independent grep sweep of `contracts/` confirms no participating slot or writer is missed (grep patterns: `function .*external`, `function .*public`, `slot:`, `assembly { sstore`, every storage variable declaration). Recorded as attestation in CAT-05 artifact.

### Fix (FIX) — Structural Elimination of Violations

- [ ] **FIX-01**: For each VIOLATION pair in CAT-04, contract change lands per chosen remediation tactic from the menu — (a) `rngLockedFlag`-gated revert at writer (revert with `RngLocked` custom error or equivalent if `rngLockedFlag == true`); (b) snapshot/anchor pattern reading from a slot frozen at lock time (Phase 288 `dailyIdx` + Phase 281 owed-salt precedents); (c) re-order computation to pre-lock; (d) make slot immutable.
- [ ] **FIX-02**: For each FIX-01 contract change, regression test asserts the freeze invariant for the chosen tactic — gated-revert: write reverts when `rngLockedFlag = true`; snapshot: anchor read returns frozen value across the window; reorder: computation happens strictly pre-lock; immutable: slot has no setter post-deploy.
- [ ] **FIX-03**: For each fixed participating slot, post-fix grep-verifies zero residual non-exempt writers. Recorded as attestation row in FINDINGS-v43.0.md §3.B per-slot table.
- [ ] **FIX-04**: Bytecode delta + storage layout delta documented per fix. Storage byte-identical preferred; BREAKING storage layout changes acceptable per pre-launch posture and indexer-migration handoff carry (`D-40N-EVT-BREAK-01` + `D-42N-EVT-BREAK-01`).
- [ ] **FIX-05**: Public ABI / event topic-hash changes (if any) documented per fix; BREAKING acceptable per pre-launch posture.

### Admin Lockdown (ADM) — Admin/Owner Path Sweep

- [ ] **ADM-01**: Enumerate every `onlyOwner` / `onlyAdmin` / role-gated external function across all modules in `contracts/`. Output: complete function list with file:line + role-gate annotation.
- [ ] **ADM-02**: For each admin function, identify slot writes (cross-reference with CAT-03 writer table). Mark which functions write participating slots.
- [ ] **ADM-03**: For each violating admin function, add `rngLockedFlag`-gated revert. Includes governance, parameter updates, charity allowlist, decimator config, presale config, and any other admin surface enumerated in ADM-01.
- [ ] **ADM-04**: Regression tests for admin lockdown — each violating admin function reverts with `RngLocked` (or equivalent) when called during `rngLockedFlag = true`; succeeds when `rngLockedFlag = false`.

### Fuzz (FUZZ) — State-Shuffle Determinism Harness

- [ ] **FUZZ-01**: Foundry harness `test/fuzz/RngLockDeterminism.t.sol` (or equivalent name) — fuzzes randomized action sequences mid-rngLock window (between VRF request and fulfillment).
- [ ] **FUZZ-02**: Action set includes — bets, mints, claims, ERC20/ERC721 transfers, approvals, affiliate registration, every admin/owner function, `retryLootboxRng` invocations.
- [ ] **FUZZ-03**: For each randomized perturbation sequence, asserts every VRF-derived output (jackpot recipients, jackpot amounts, trait awards, lootbox tickets, hero-override outcome) is byte-identical to the no-perturbation baseline.
- [ ] **FUZZ-04**: Coverage: every VRF-influenced output surface enumerated in CAT-01 (whole consumer set) is exercised by at least one fuzz case.
- [ ] **FUZZ-05**: Edge cases — admin-during-lock perturbations, near-end-of-window perturbations (last block before unlock), multi-tx-batch perturbations, multi-block perturbations within the window, retryLootboxRng-during-lock perturbations (failsafe path).

### Adversarial Sweep (SWP) — 3-Skill HYBRID Pass

- [ ] **SWP-01**: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass charged with finding any storage path violating the freeze invariant. Output: hypothesis-disposition table.
- [ ] **SWP-02**: `/zero-day-hunter` PARALLEL_SUBAGENT pass on novel attack surfaces (composition attacks, cross-module read/write races, ERC-callback-induced state mutations, multi-block window exploits). Output: hypothesis-disposition table.
- [ ] **SWP-03**: `/economic-analyst` PARALLEL_SUBAGENT pass on game-theoretic write-induced effects (incentive-compatible adversarial actions during window). Output: hypothesis-disposition table.
- [ ] **SWP-04**: Disposition: any FINDING_CANDIDATE routes back to an additional FIX wave. Any SAFE_BY_DESIGN candidate is REJECTED — milestone goal precludes SAFE_BY_DESIGN dispositions for participating slots. Two-pass re-pass discipline per D-284-ADVERSARIAL-RE-PASS-01 carry if any FIX wave lands after initial pass.
- [ ] **SWP-05**: `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. `/economic-analyst` IN SCOPE per D-271-ADVERSARIAL-03 carry.

### Audit Deliverable (AUDIT) — FINDINGS-v43.0.md Terminal

- [ ] **AUDIT-01**: `audit/FINDINGS-v43.0.md` 9-section terminal deliverable. §3.A delta-surface table enumerates every USER-APPROVED contract commit + every USER-APPROVED test commit + every AGENT-COMMITTED audit/planning commit across v43.0 phases.
- [ ] **AUDIT-02**: §3.B per-exempt-entry-point attestation matrix — for each of the 3 exempt entry points, per-participating-slot row proves the exempt write does not violate downstream invariants.
- [ ] **AUDIT-03**: §3.C conservation re-proof for the freeze invariant — every participating slot has a 4-tuple attestation (slot identity / writer-set / freeze gate / consumer-set).
- [ ] **AUDIT-04**: §4 adversarial-pass disposition table — every hypothesis (charged + beyond-charge) from SWP-01..03 with verdict.
- [ ] **AUDIT-05**: §5 LEAN regression — REG-01 (v42.0 non-widening) + REG-02 (v41.0 non-widening) + REG-03 (v40.0 non-widening) + REG-04 (prior-finding spot-check across v25..v42).
- [ ] **AUDIT-06**: §6 KI walkthrough — EXC-01..03 RE_VERIFIED-NEGATIVE-scope at v43; EXC-04 STRUCTURALLY ELIMINATED preserved.
- [ ] **AUDIT-07**: §7 prior-artifact cross-cites (no forward-cites per D-NN-FCITE-01 carry).
- [ ] **AUDIT-08**: §8 forward-cite closure (zero post-milestone references; pickup-pointers via locked-decision IDs only).
- [ ] **AUDIT-09**: §9 closure attestation — verdict + 9-phase (or however-many) wave summary + closure signal + Deferred-to-Future register.

### Regression (REG) — Cross-Milestone Non-Widening Proofs

- [ ] **REG-01**: v42.0 closure non-widening — every v42.0 audit-subject surface (MINTCLN, HRROLL, DPNERF, RETRY_LOOTBOX_RNG) is byte-identical at v43.0 close except where explicitly modified by a v43.0 FIX phase. Modifications enumerated explicitly.
- [ ] **REG-02**: v41.0 closure non-widening — F-41-01/02/03 fix sites preserved (owed-salt at mint-batch; `dailyIdx` anchor at hero-override; cross-day determinism).
- [ ] **REG-03**: v40.0 closure non-widening — whole-ticket Bernoulli sites + ENT-05 keccak refactor + `_queueLootboxTickets` retirement + whole-BURNIE floor preserved.
- [ ] **REG-04**: Prior-finding spot-check across `audit/FINDINGS-v25..v42.0.md` for any v43-touched surface set — no regression of prior-milestone fixes.

### Closure (CLS) — Terminal Closure-Flip

- [ ] **CLS-01**: 2-commit sequential SHA orchestration per D-297-CLOSURE-01 + D-284-CLOSURE-01 precedent — Commit 1 ships audit deliverable with `<commit-1-sha>` placeholder; Commit 2 resolves placeholder + propagates verbatim + chmod 444 + atomic 5-doc closure flip (ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS).
- [ ] **CLS-02**: Closure signal `MILESTONE_V43_AT_HEAD_<sha>` propagated atomically across all 5 docs. `audit/FINDINGS-v43.0.md` chmod 444 (read-only at closure).

---

## Deferred to Future Milestones

Items explicitly out of v43.0 scope; carried forward via locked-decision IDs per `D-297-DEFER-01` + `D-281-FCITE-01` carry chain:

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
| `retryLootboxRng` structural rework | Failsafe per user disposition 2026-05-18 — ≤1 VRF→VRF replacement per stall event; does not manipulate pre-lock state. `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A accepted. |
| SAFE_BY_DESIGN dispositions for participating slots | Milestone goal explicitly precludes — "could possibly affect" = theoretical reachability; eliminate even if economic likelihood is LOW. |
| Off-chain indexer migration tooling | Off-chain handoff; v43.0 owns only contract + test + audit artifacts. |
| Game-over hardening | Out-of-scope per dedicated future milestone framing. |
| Mint-boost fractional retirement | Out per `D-40N-MINTBOOST-OUT-01` carry. |
| New features / behavioral additions | v43.0 is purely structural — no new game mechanics, no economic-parameter changes, no new entry points. |

## Traceability

Empty; populated during ROADMAP creation per workflow Step 10.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CAT-01..06 | Phase [N] | Pending |
| FIX-01..05 | Phase [N..M] | Pending |
| ADM-01..04 | Phase [N] | Pending |
| FUZZ-01..05 | Phase [N] | Pending |
| SWP-01..05 | Phase [N] | Pending |
| AUDIT-01..09 | Phase [N] | Pending |
| REG-01..04 | Phase [N] | Pending |
| CLS-01..02 | Phase [N] | Pending |

**Coverage:**
- v43.0 requirements: 41 total (6 CAT + 5 FIX + 4 ADM + 5 FUZZ + 5 SWP + 9 AUDIT + 4 REG + 2 CLS + 1 implicit no-SAFE_BY_DESIGN gate at SWP-04)
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 41 ⚠️

---

*Requirements defined: 2026-05-18*
*Last updated: 2026-05-18 after v43.0 milestone OPENED*
