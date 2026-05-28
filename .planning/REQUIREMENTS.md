# Requirements: Degenerus Protocol — v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol

**Milestone:** v50.0 (started 2026-05-27)
**Audit baseline → subject:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` → v50.0 closure HEAD. Every cited `file:line` MUST be re-attested vs the v49.0-closure HEAD before any patch.
**Scope source:** the milestone discussion (2026-05-27) + the three v50 forward-seeds (`v49-whale-pass-claim-refactor-seed`, `v50-afking-pass-only-sub-simplify-seed`, `mintmodule-processed-advance-divergence-seed`). No research (internal refinements + an internally-grounded deliverable).
**Posture:** the three contract items (WHALE/AFSUB/MINTDIV) ship as ONE batched USER-APPROVED `contracts/*.sol` diff; HARD STOP at the commit boundary. Security/RNG-freeze floor over gas (`feedback_security_over_gas`); items WHALE + MINTDIV touch RNG-adjacent paths and must be RE-PROVEN freeze-safe, not assumed. The external RNG-audit protocol (RNGAUDIT) is a package-only deliverable authored against the frozen post-v50 tree. Pre-launch redeploy-fresh (storage break fine).

---

## v50.0 Requirements

### Whale-Pass O(1) Claim Refactor (WHALE)
- [ ] **WHALE-01**: The box-open whale-pass mint stops looping. The inline ~100-iteration `_queueTickets` whale-pass mint at box-open (`DegenerusGameLootboxModule.sol:~1250-1260`) is replaced by an O(1) record of a pending whale-pass claim (beneficiary + amount/level), so opening a box is uniform cost regardless of whale-pass status.
- [ ] **WHALE-02**: A player-paid `claimWhalePass()` entrypoint materializes the queued whale-pass tickets (the deferred `_queueTickets` mint), with the gas borne by the beneficiary at claim time rather than the box-opener at open time. SPEC locks the exact signature (caller-is-beneficiary vs permissionless-with-beneficiary-arg) and the pending-claim storage shape.
- [ ] **WHALE-03**: Box opens become uniform O(1) → the 331 whale-pass-weighted `autoOpen` gas budget carve-out is retired and `OPEN_BATCH` returns to a flat per-box sizing. The new flat `OPEN_BATCH` is re-confirmed to stay under the autoOpen tx-gas ceiling at the worst-case uniform open.
- [x] **WHALE-04**: RNG-freeze safety is PROVEN (not assumed) for the split: the queued whale-pass tickets target a FUTURE level (verify against the `_queueTickets` level math); neither the O(1) record at box-open nor `claimWhalePass()` writes any slot that participates in the CURRENT RNG window during `rngLock` (or reverts if it would); the `rngLock` liveness gate and the `_applyWhalePassStats` timing/semantics are preserved (stats applied at the same logical point, not advanced/delayed in a way that perturbs a frozen input).

### AfKing Pass-Gated Subscriptions (AFSUB)
- [ ] **AFSUB-01**: The BURNIE-purchased subscription window is REMOVED — `burnForKeeper` and the `paidThroughDay` time-funding accounting are deleted; a subscription's lifetime is no longer extended by burning BURNIE. (`AfKing.sol`; the BURNIE `burnForKeeper` sink + its DegenerusGame/BurnieCoin counterpart are removed or repurposed per SPEC.)
- [ ] **AFSUB-02**: Subscriptions are PASS-GATED — `validThroughLevel` is encoded at subscribe time (derived from the subscriber's pass), and each sweep iteration validity check is `currentLevel <= validThroughLevel` (the same cheap stored-field compare as the retired `paidThroughDay` — NO per-iteration external pass read on the non-crossing path, NO GASOPT-05-class regression).
- [ ] **AFSUB-03**: At the level crossing (`currentLevel > validThroughLevel`) the sub's pass is re-read EXACTLY ONCE → refresh-or-evict: a still-valid (new or upgraded) pass refreshes `validThroughLevel` and the sub continues; otherwise the sub is evicted. This is NOT an unconditional kick, and the crossing is the ONLY external pass read on the hot path.
- [ ] **AFSUB-04**: Third-party box funding (the OPEN-E shared `fundingSource`) is PRESERVED — pass-gating does NOT moot OPEN-E. The 4 OPEN-E structural protections (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub temporal bound) are re-attested to hold under the pass-gated model (`open-e-operator-approval-trust-boundary`).
- [ ] **AFSUB-05**: The cancel/eviction path preserves the locked SUB-07 in-place cancel-tombstone semantics and the v49 swap-pop membership invariant (membership ⟺ packed != 0); pass-eviction must NOT reproduce the H-CANCEL-SWAP-MISS missed-day class (`afking-cancel-tombstone-streak-finding`).

### MintModule Advance-Divergence — Confirm-Then-Fix (MINTDIV)
- [x] **MINTDIV-01**: SPEC establishes, with evidence, whether `processTicketBatch`'s within-player `startIndex` advance (`writesUsed>>1`, `DegenerusGameMintModule.sol:~671`) can diverge from `processFutureTicketBatch`'s `+= take` (`:~398`) — i.e., whether a single player's owed can split across budget slices AND that split yields divergent per-ticket trait indices. Reachability + the divergence mechanism are PROVEN or REFUTED (not asserted).
- [ ] **MINTDIV-02**: If reachable → the within-player index advance is aligned across the two loops so per-ticket trait indices are identical whether or not a player's owed splits across budget slices, with NO change to the frozen-word trait derivation for any non-split case. If NOT reachable → documented NEGATIVE with the proof and no contract change (the seed candidate is closed either way).

### External-LLM RNG-Audit Protocol — Deliverable, Package-Only (RNGAUDIT)
- [ ] **RNGAUDIT-01**: The protocol states the freeze invariant precisely as the external auditor's target — "while `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word + its deterministic derivations may be unknown" — plus the exempt entry points (`advanceGame()` + reachable resolution flow, the VRF coordinator callback, `retryLootboxRng()` failsafe). (`v45-vrf-freeze-invariant`.)
- [ ] **RNGAUDIT-02**: The protocol is a MULTI-ROUND adversarial sequence designed to force rigor across a multi-turn external session: (R1) catalog the VRF read-graph — every participating slot with its writers + readers across all modules; (R2) independently re-derive each slot's freeze status (frozen / reverts-if-written-during-lock / proven-non-participating); (R3) adversarially challenge the catalog (hunt for any writer that escapes the freeze, any cross-module composition that does); (R4) reconcile + report. The external model performs its OWN discovery — no answer key / no internal findings are embedded ("different perspective" is the point).
- [x] **RNGAUDIT-03**: The protocol ships a self-contained context pack sufficient to run cold against the contracts: the module/RNG-window map, the `rngLock` mechanics, where the VRF word enters and is consumed, the contract inventory, and the back-and-forth variable-tracing methodology ("trace every variable across modules — what writes it, what reads it, what is locked during an RNG window"). It does NOT depend on access to our `audit/FINDINGS-*.md`.
- [ ] **RNGAUDIT-04**: The protocol is authored against the FROZEN post-v50 tree (after WHALE/AFSUB/MINTDIV land), is model-agnostic (usable in both Gemini and ChatGPT, with context-window chunking guidance for feeding the contracts), and is explicitly PACKAGE-ONLY — running it through the external models and triaging their output is a FUTURE cycle, OUT of v50.0.

### Test Proofs (TST)
- [ ] **TST-01**: Whale-pass refactor is proven equivalent — a box-open followed by `claimWhalePass()` yields the same materialized tickets / traits / whale-pass stats as the old inline mint; box-open is demonstrated uniform-O(1) (whale vs non-whale opener); and a freeze-invariant fuzz (extending the v43 `RngLockDeterminism` harness) proves the deferred record + claim perturb no current-window entropy input.
- [ ] **TST-02**: AfKing pass-gated subs are proven — an active sub is swept while `currentLevel <= validThroughLevel`; evicted at the crossing with no valid pass; refreshed (continues) at the crossing with a valid/upgraded pass; the non-crossing path performs NO external pass read; the OPEN-E 4-protection behavior re-attests; and the cancel-tombstone / swap-pop membership invariant holds (no missed-day regression).
- [ ] **TST-03**: The MINTDIV same-traits regression lands — byte-identical per-ticket trait derivation across a budget-slice split for an affected player (covers the fix if real, or codifies the not-reachable boundary if refuted).
- [ ] **TST-04**: Full-suite regression is NON-WIDENING vs the v49.0 baseline (net-zero new regression; enumerated-red-set guard by NAME), absorbing any test renames/oracle migrations from the three contract items.

### Adversarial Security Sweep + Delta Audit (SWEEP)
- [ ] **SWEEP-01**: A 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) is run against the frozen v50 subject, charged with: whale-pass deferred-claim timing (can a claim alter RNG-derived outcomes / future-level traits / stats), pass-gated sub eviction-or-refresh abuse + OPEN-E re-attest, MintModule index correctness, and freeze across all the new paths. Every elevation passes the skeptic dual-gate.
- [ ] **SWEEP-02**: The delta-audit attests NON-WIDENING vs the v49.0 baseline `b0511ca2` — every `contracts/`+`test/` diff is attributable to a v50 work item; the RNG/VRF-freeze invariant is re-attested intact across the WHALE + MINTDIV edits.
- [ ] **SWEEP-03**: `audit/FINDINGS-v50.0.md` is authored (9-section, mirroring v44/v46/v47/v48/v49), with any findings adjudicated or deferred per USER direction; `chmod 444` at closure.

### Cross-Cutting — SPEC Reconciliation + IMPL + TERMINAL (BATCH)
- [x] **BATCH-01**: SPEC design-lock — settle the shared signatures (the whale-pass pending-claim storage + `claimWhalePass()` signature, the AfKing `validThroughLevel` field + refresh-or-evict control flow, the MintModule index alignment), PROVE/REFUTE MINTDIV-01 reachability, fix the RNGAUDIT protocol structure, and grep-attest every cited `file:line` vs the v49.0 HEAD before any patch.
- [ ] **BATCH-02**: The ONE batched USER-APPROVED `contracts/*.sol` diff (WHALE + AFSUB + MINTDIV-if-real) is applied in producer-before-consumer order; HARD STOP at the commit boundary (locally compiled/tested, never committed without explicit user hand-review).
- [ ] **BATCH-03**: TERMINAL closure — re-attest all v50.0 requirements at closure and apply the atomic 5-doc closure flip (`MILESTONE_V50_AT_HEAD_<sha>` + ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS + chmod 444 the findings).

---

## Out of Scope (v50.0)

- **Running the external RNG-audit protocol / triaging its findings** — RNGAUDIT is package-only; feeding it to Gemini/ChatGPT and adjudicating their output is a FUTURE cycle (USER decision 2026-05-27).
- **Off-chain indexer / webpage** — separate frontend track.
- **Any non-RNG / non-keeper-adjacent contract surface** beyond the three named items (WHALE box-open / AFSUB AfKing subs / MINTDIV MintModule per-ticket loops).
- **The SWAP cash-share ≤40% tighten** — v48 advisory; USER accepted ≤60% as canonical. Revisit only if explicitly requested.
- **The v44 §9d 135-anchor maximalist register** — carries forward unchanged; NOT live vectors (`project_rnglock_audit_disposition`).
- **`1 ether - decayN` unchecked hardening** — still deferred pending the `_wadPow ≤ WAD` rounding proof.

---

## Future Requirements (deferred, not this milestone)

- Run the external RNG-audit protocol through Gemini + ChatGPT, ingest their reports, and triage each claim (confirm/refute/fix/document) — the follow-on cycle to RNGAUDIT.
- Any whale-pass / AfKing / MintModule follow-ups surfaced by SWEEP-01 and deferred by USER direction.

---

## Traceability

**25/25 v50.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.** Phases continue from 333 → 334..338 (SPEC → IMPL → TST → AUDIT-PROTOCOL → TERMINAL). Statuses flip to Complete as phases close; all 25 re-attested at the Phase 338 TERMINAL closure (BATCH-03 + SWEEP-01/02/03).

| Requirement | Phase | Status |
|-------------|-------|--------|
| WHALE-01 | Phase 335 (IMPL) | Pending |
| WHALE-02 | Phase 335 (IMPL) | Pending |
| WHALE-03 | Phase 335 (IMPL) | Pending |
| WHALE-04 | Phase 334 (SPEC) | Complete |
| AFSUB-01 | Phase 335 (IMPL) | Pending |
| AFSUB-02 | Phase 335 (IMPL) | Pending |
| AFSUB-03 | Phase 335 (IMPL) | Pending |
| AFSUB-04 | Phase 335 (IMPL) | Pending |
| AFSUB-05 | Phase 335 (IMPL) | Pending |
| MINTDIV-01 | Phase 334 (SPEC) | Complete |
| MINTDIV-02 | Phase 335 (IMPL) | Pending |
| RNGAUDIT-01 | Phase 337 (AUDIT-PROTOCOL) | Pending |
| RNGAUDIT-02 | Phase 337 (AUDIT-PROTOCOL) | Pending |
| RNGAUDIT-03 | Phase 337 (AUDIT-PROTOCOL) | Complete |
| RNGAUDIT-04 | Phase 337 (AUDIT-PROTOCOL) | Pending |
| TST-01 | Phase 336 (TST) | Pending |
| TST-02 | Phase 336 (TST) | Pending |
| TST-03 | Phase 336 (TST) | Pending |
| TST-04 | Phase 336 (TST) | Pending |
| SWEEP-01 | Phase 338 (TERMINAL) | Pending |
| SWEEP-02 | Phase 338 (TERMINAL) | Pending |
| SWEEP-03 | Phase 338 (TERMINAL) | Pending |
| BATCH-01 | Phase 334 (SPEC) | Complete |
| BATCH-02 | Phase 335 (IMPL) | Pending |
| BATCH-03 | Phase 338 (TERMINAL) | Pending |

**Per-phase count (verification):**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 334 SPEC | BATCH-01, WHALE-04, MINTDIV-01 | 3 |
| 335 IMPL | WHALE-01, WHALE-02, WHALE-03, AFSUB-01, AFSUB-02, AFSUB-03, AFSUB-04, AFSUB-05, MINTDIV-02, BATCH-02 | 10 |
| 336 TST | TST-01, TST-02, TST-03, TST-04 | 4 |
| 337 AUDIT-PROTOCOL | RNGAUDIT-01, RNGAUDIT-02, RNGAUDIT-03, RNGAUDIT-04 | 4 |
| 338 TERMINAL | SWEEP-01, SWEEP-02, SWEEP-03, BATCH-03 | 4 |
| **Total** | | **25** |

> **Center-of-gravity notes:** WHALE-04 (freeze-safety PROOF) and MINTDIV-01 (reachability PROVE/REFUTE) center at SPEC (334) because both are design-gating proofs that decide whether/how the split + the MintModule alignment are authored; their build lands at IMPL (335, under WHALE-01/02/03 and MINTDIV-02) and their empirical proof at TST (336, TST-01 / TST-03). RNGAUDIT-01..04 center at AUDIT-PROTOCOL (337) — the protocol STRUCTURE is sketched at SPEC under BATCH-01 but the authored deliverable lands at 337 against the FROZEN post-v50 tree. MINTDIV-02's contract scope is CONDITIONAL on the 334 reachability verdict (reachable → align; not-reachable → documented NEGATIVE, no contract change).

> **Note on §13e-style "uncovered" warnings:** as in the v47/v48/v49 milestones, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; the TERMINAL closure (Phase 338: SWEEP-01/02/03 + BATCH-03) re-attests the full 25-requirement set. The TST / AUDIT-PROTOCOL / TERMINAL phases do not "uncover" the IMPL reqs — they re-prove, package against, and re-attest them.

*Last updated: 2026-05-27 — v50.0 traceability filled by the roadmapper at ROADMAP creation (25 reqs / 7 categories: WHALE 4 · AFSUB 5 · MINTDIV 2 · RNGAUDIT 4 · TST 4 · SWEEP 3 · BATCH 3; phases 334-338). Statuses flip to Complete as phases close; all re-attested at the Phase 338 TERMINAL closure.*
