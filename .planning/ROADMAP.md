# Roadmap: Degenerus Protocol — Audit Repository

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Milestones

- ✅ **v44.0 sStonk Per-Day Redemption Refactor** — Phases 304-308 (shipped 2026-05-20)
- ✅ **v45.0 VRF-Rotation Liveness Fix** — Phases 309-314 (shipped 2026-05-23, minimal close)
- ✅ **v46.0 Do-Work Crank + AfKing Subscription** — Phases 316-320 (shipped 2026-05-24)
- ✅ **v47.0 Rake-Free Presale + Lootbox-Boon Unification** — Phases 321-324 (shipped 2026-05-25)
- ✅ **v48.0 sDGNRS Salvage Swap + v47 Deferred Fixes + Keeper/Pool/Tombstone/Hero** — Phases 325-328 (shipped 2026-05-26)
- ✅ **v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep** — Phases 329-333 (shipped 2026-05-27)
- 🔨 **v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol** — Phases 334-338 (started 2026-05-27)

---

## 🔨 v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol (Active — started 2026-05-27)

**Milestone:** v50.0 (started 2026-05-27)
**Defined:** 2026-05-27
**Audit baseline → subject:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` → v50.0 closure HEAD (TBD at TERMINAL). Subject = the single batched USER-APPROVED `contracts/*.sol` diff reconciling the three contract items (WHALE O(1) whale-pass claim · AFSUB pass-gated AfKing subs · MINTDIV per-ticket advance-divergence, confirm-then-fix). The external RNG-audit protocol (RNGAUDIT) is a separate package-only deliverable authored against the FROZEN post-v50 tree — NOT part of the contract subject and NOT a substitute for the internal TERMINAL sweep.
**Scope source:** `.planning/REQUIREMENTS.md` (25 v50.0 REQ-IDs across 7 categories: WHALE 4 · AFSUB 5 · MINTDIV 2 · RNGAUDIT 4 · TST 4 · SWEEP 3 · BATCH 3) + the milestone discussion (2026-05-27) + the three v50 forward-seeds (`v49-whale-pass-claim-refactor-seed`, `v50-afking-pass-only-sub-simplify-seed`, `mintmodule-processed-advance-divergence-seed`). **No research** (internal refinements + an internally-grounded deliverable) — no phase needs a research sub-phase (attestation + design-proof + established-methodology only).

> **Cross-cutting rule (every requirement):** every cited `file:line` MUST be re-attested against the **v49.0-closure HEAD `b0511ca2`** before any patch (no "by construction" / "single fn reaches all paths" claim survives un-checked — the `DegenerusGame` mint/jackpot inline-duplication precedent; `feedback_verify_call_graph_against_source`). The cited anchors (`DegenerusGameLootboxModule.sol:~1250-1260` whale-pass mint, `DegenerusGameMintModule.sol:~671` / `:~398` advance loops, `AfKing.sol` `burnForKeeper`/`paidThroughDay`) carry `~` approximations from the seeds — exact lines confirmed at SPEC. Security / RNG-freeze floor over gas (`feedback_security_over_gas` + `v45-vrf-freeze-invariant`). **WHALE + MINTDIV touch RNG-adjacent paths → the RNG/VRF-freeze invariant is RE-PROVEN, not assumed.** Pre-launch redeploy-fresh (storage-layout break fine, no migration; `feedback_frozen_contracts_no_future_proofing`).

> **Posture:** the three contract items (WHALE + AFSUB + MINTDIV-if-real) ship as **ONE batched USER-APPROVED `contracts/*.sol` diff** at IMPL with a **HARD STOP at the contract-commit boundary** (applied + locally compiled/tested, NEVER committed without explicit user hand-review of the single batched diff — `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`; `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`). MINTDIV-02's contract change is CONDITIONAL on the MINTDIV-01 reachability verdict — if NOT reachable, the diff carries no MintModule change and MINTDIV-02 closes as a documented NEGATIVE with the proof. Tests + planning + docs AGENT-committable.

> **Shared-surface note:** WHALE item 1 touches `_queueTickets`, which lives NEAR the MintModule per-ticket paths MINTDIV item 3 audits → SPEC reconciles any overlap so the two RNG-adjacent edits land in one coherent diff. AFSUB (`AfKing.sol`) is comparatively isolated but must re-hold the OPEN-E 4-protection structure (`open-e-operator-approval-trust-boundary`) and the v49 swap-pop membership invariant + the SUB-07 cancel-tombstone (`afking-cancel-tombstone-streak-finding`).

> **Phase numbering** continues from the previous milestone — v49.0 ended at Phase 333, so **v50.0 starts at Phase 334.** Not reset to 1. (Prior milestones' phase dirs are archived under `.planning/milestones/vXX.0-phases/`.)

> **Milestone shape** matches the established v44–v49 audit pattern, extended with a dedicated package-only AUDIT-PROTOCOL phase: **SPEC design-lock (+ the MINTDIV reachability proof + the protocol structure) → single batched IMPL contract diff → TST proof → AUDIT-PROTOCOL author against the frozen tree → TERMINAL internal delta-audit + 3-skill genuine-PARALLEL adversarial sweep + `audit/FINDINGS-v50.0.md` (chmod 444) + atomic 5-doc closure flip.** The contract-boundary HARD STOP lives at exactly ONE IMPL phase (335); the internal adversarial sweep + closure is the TERMINAL phase (338); the RNGAUDIT external protocol (337) is a separate work-product, NOT a substitute for the internal sweep.

### Phases

- [ ] **Phase 334: SPEC — Design-Lock + MINTDIV Reachability Proof + RNGAUDIT Structure + Call-Graph Attestation** - Settle the shared signatures for the three contract items (whale-pass pending-claim storage + `claimWhalePass()` signature; AfKing `validThroughLevel` field + refresh-or-evict control flow; MintModule index alignment), PROVE/REFUTE the MINTDIV-01 divergence reachability with evidence, PROVE (not assume) the WHALE-04 RNG-freeze safety of the deferred-claim split, fix the RNGAUDIT protocol structure, and grep-attest every cited `file:line` vs the v49.0 HEAD `b0511ca2` — paper-only, zero `contracts/*.sol`.
- [ ] **Phase 335: IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV-if-real)** - Land the single reconciled `contracts/*.sol` diff in producer-before-consumer order: the O(1) whale-pass pending-claim + player-paid `claimWhalePass()` (retiring the inline ~100-loop mint and the 331 autoOpen carve-out), the pass-gated AfKing subscription model (`burnForKeeper`/`paidThroughDay` removed, `validThroughLevel` + refresh-or-evict, OPEN-E preserved), and — if MINTDIV-01 proved reachable — the within-player index alignment; applied + locally compiled/tested, then HELD at the contract-commit boundary for explicit user hand-review.
- [ ] **Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression** - Prove the whale-pass refactor materializes the same tickets/traits/stats with uniform-O(1) opens + a freeze fuzz that the deferred record+claim perturb no current-window entropy; the pass-gated sub sweeps/evicts/refreshes correctly with no per-iter pass read on the non-crossing path + OPEN-E re-attest + no missed-day regression; the MINTDIV same-traits-across-split regression; and a NON-WIDENING full-suite regression vs the v49.0 baseline.
- [ ] **Phase 337: AUDIT-PROTOCOL — Author the Model-Agnostic Multi-Round External-LLM RNG-Audit Kit (Package-Only)** - Author the model-agnostic, multi-round adversarial external-LLM RNG-audit protocol (freeze-invariant target + exempt entry points / R1 catalog → R2 independent re-derive → R3 adversarial challenge → R4 reconcile / self-contained cold-start context pack with no answer key) against the FROZEN post-v50 tree, designed to drive an external model's (Gemini / ChatGPT) OWN discovery. Package-only — running it / triaging its output is OUT of v50.0.
- [ ] **Phase 338: TERMINAL — Internal Delta Audit + 3-Skill Adversarial Sweep + Closure** - NON-WIDENING delta-audit vs the v49.0 baseline `b0511ca2`, the internal 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT) charged against whale-pass deferred-claim timing + pass-gated eviction/refresh abuse + OPEN-E re-attest + MintModule index correctness + freeze across all new paths, author `audit/FINDINGS-v50.0.md` (chmod 444), and the atomic 5-doc closure flip with the `MILESTONE_V50_AT_HEAD_<sha>` signal.

---

## Phase Details

### Phase 334: SPEC — Design-Lock + MINTDIV Reachability Proof + RNGAUDIT Structure + Call-Graph Attestation

**Goal**: The three contract items' shared signatures are settled in writing so the IMPL phase re-authors a fully reconciled diff with zero "by construction" assumptions, the MINTDIV-01 divergence is PROVEN or REFUTED with evidence (not asserted), the WHALE-04 RNG-freeze safety of the deferred whale-pass claim is PROVEN on paper before any code is written, the RNGAUDIT external-protocol structure is fixed (the round sequence + context-pack skeleton it will be authored against at Phase 337), and every cited `file:line` is grep-verified against the v49.0-closure HEAD `b0511ca2` — paper-only, zero `contracts/*.sol`.
**Depends on**: Nothing (first v50.0 phase; consumes the v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` as the frozen audit baseline)
**Requirements**: BATCH-01, WHALE-04, MINTDIV-01
**Success Criteria** (what must be TRUE):

  1. The shared signatures are settled in writing (BATCH-01) — the whale-pass pending-claim storage shape + the `claimWhalePass()` signature (caller-is-beneficiary vs permissionless-with-beneficiary-arg, decided), the AfKing `validThroughLevel` field placement (packed into the existing `Sub` layout, no per-iter SLOAD beyond the stored compare) + the refresh-or-evict control flow at the level crossing, and the MintModule within-player index alignment shape — are reconciled so no downstream file ships an intermediate broken state, and the shared `_queueTickets` surface (touched by WHALE, audited near by MINTDIV) is reconciled across the two RNG-adjacent edits.
  2. The WHALE-04 RNG-freeze safety is PROVEN, not assumed — the queued whale-pass tickets are shown to target a FUTURE level (verified against the `_queueTickets` level math at `DegenerusGameLootboxModule.sol`), neither the O(1) record at box-open nor `claimWhalePass()` is shown to write any slot that participates in the CURRENT RNG window during `rngLock` (or it reverts if it would), and the `rngLock` liveness gate + `_applyWhalePassStats` timing/semantics are proven preserved (stats applied at the same logical point, not advanced/delayed in a way that perturbs a frozen input) — `v45-vrf-freeze-invariant` re-attested for the split on paper.
  3. The MINTDIV-01 reachability is PROVEN or REFUTED with evidence — SPEC establishes, with a traced argument, whether `processTicketBatch`'s within-player `startIndex` advance (`writesUsed>>1`, `DegenerusGameMintModule.sol:~671`) can diverge from `processFutureTicketBatch`'s `+= take` (`:~398`): whether a single player's owed can split across budget slices AND whether that split yields divergent per-ticket trait indices. The verdict (reachable → fix at IMPL / not-reachable → documented NEGATIVE, no contract change) is recorded so MINTDIV-02's IMPL scope is decided before any patch.
  4. The RNGAUDIT external-protocol structure is fixed (feeding Phase 337) — the multi-round sequence (R1 catalog → R2 independent re-derive → R3 adversarial challenge → R4 reconcile) and the self-contained cold-start context-pack skeleton (module/RNG-window map, `rngLock` mechanics, VRF word entry/consume points, contract inventory, variable-tracing methodology) are sketched as the authoring target, with the "drive the external model's OWN discovery — no answer key" constraint recorded; full authoring against the FROZEN post-v50 tree is Phase 337.
  5. Every cited `file:line` across the milestone scope is grep-verified against the v49.0-closure HEAD `b0511ca2` and any drift is corrected in the SPEC (no "by construction" survives un-checked) — including the whale-pass inline mint (`DegenerusGameLootboxModule.sol:~1250-1260`), the two MintModule per-ticket loops (`:~671` / `:~398`), the AfKing `burnForKeeper`/`paidThroughDay` sink + the subscribe-time pass gate + the OPEN-E `fundingSource`/consent-gate surface, and the `_applyWhalePassStats` timing site — confirming the producer-before-consumer edit-order map for the IMPL re-author.

**Plans**: 4 plans (paper-only SPEC; all autonomous, zero `contracts/*.sol`)

- [x] 334-01-PLAN.md — WHALE-04 freeze-safety proof (SC2) + MINTDIV-01 reachability verdict (SC3)
- [x] 334-02-PLAN.md — whale-pass + MintModule design-lock (SC1) + RNGAUDIT structure sketch (SC4) + grep-attestation table (SC5)
- [x] 334-03-PLAN.md — AfKing pass-gated subscription design-lock + OPEN-E/SUB-07/swap-pop preservation criteria (SC1, AFSUB slice)
- [x] 334-04-PLAN.md — producer-before-consumer IMPL-335 edit-order map (SC1 integration) + SPEC index + multi-source coverage audit

**UI hint**: no

### Phase 335: IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV-if-real)

**Goal**: The three RNG-adjacent contract refinements land as a single reconciled `contracts/*.sol` diff under the SPEC's settled shared signatures — the box-open whale-pass mint becomes an O(1) pending-claim record + a player-paid `claimWhalePass()` that materializes the tickets (retiring the inline ~100-loop `_queueTickets` mint and, with uniform O(1) opens, the 331 whale-pass-weighted `autoOpen` budget carve-out so `OPEN_BATCH` returns to flat per-box sizing); the AfKing subscription is pass-gated (`burnForKeeper`/`paidThroughDay` removed, `validThroughLevel` encoded at subscribe, per-iter `currentLevel <= validThroughLevel` with a single pass re-read + refresh-or-evict at the crossing, OPEN-E + the cancel-tombstone/swap-pop invariants preserved); and — only if MINTDIV-01 proved reachable — the within-player index advance is aligned across the two loops — applied + locally compiled/tested, then HELD at the contract-commit boundary for explicit user hand-review.
**Depends on**: Phase 334 (the SPEC must settle the shared signatures + return the MINTDIV-01 reachability verdict + prove the WHALE-04 freeze safety first)
**Requirements**: WHALE-01, WHALE-02, WHALE-03, AFSUB-01, AFSUB-02, AFSUB-03, AFSUB-04, AFSUB-05, MINTDIV-02, BATCH-02
**Success Criteria** (what must be TRUE):

  1. The box-open whale-pass mint stops looping and a player-paid claim materializes it (WHALE-01/02) — the inline ~100-iteration `_queueTickets` whale-pass mint at box-open (`DegenerusGameLootboxModule.sol:~1250-1260`) is replaced by an O(1) record of a pending whale-pass claim (beneficiary + amount/level) so opening a box is uniform cost regardless of whale-pass status, and a `claimWhalePass()` entrypoint (per the SPEC-locked signature + pending-claim storage shape) materializes the deferred mint with the gas borne by the beneficiary at claim time, not the box-opener at open time.
  2. Box opens become uniform O(1) → the autoOpen carve-out is retired (WHALE-03) — the 331 whale-pass-weighted `autoOpen` gas budget carve-out is removed and `OPEN_BATCH` returns to a flat per-box sizing, with the new flat `OPEN_BATCH` re-confirmed to stay under the autoOpen tx-gas ceiling at the worst-case uniform open.
  3. The AfKing subscription is pass-gated with the BURNIE window removed (AFSUB-01/02/03) — `burnForKeeper` + the `paidThroughDay` time-funding accounting are deleted (the BURNIE sink + its DegenerusGame/BurnieCoin counterpart removed or repurposed per SPEC), `validThroughLevel` is encoded at subscribe (derived from the subscriber's pass) and each sweep iteration validity check is the cheap stored-field compare `currentLevel <= validThroughLevel` (NO per-iteration external pass read on the non-crossing path, NO GASOPT-05-class regression), and at the crossing (`currentLevel > validThroughLevel`) the pass is re-read EXACTLY ONCE → refresh-or-evict (a still-valid new/upgraded pass refreshes `validThroughLevel` and the sub continues; otherwise evicted — NOT an unconditional kick; the crossing is the ONLY external pass read on the hot path).
  4. OPEN-E and the cancel/eviction invariants are preserved (AFSUB-04/05) — third-party box funding (the OPEN-E shared `fundingSource`) STAYS (pass-gating does NOT moot OPEN-E) and the 4 OPEN-E structural protections (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub temporal bound) hold under the pass-gated model, and the cancel/eviction path preserves the locked SUB-07 in-place cancel-tombstone semantics + the v49 swap-pop membership invariant (membership ⟺ packed != 0) so pass-eviction does NOT reproduce the H-CANCEL-SWAP-MISS missed-day class.
  5. The MINTDIV index alignment lands only if reachable, and the diff is HELD at the contract-commit boundary (MINTDIV-02 / BATCH-02) — if MINTDIV-01 proved reachable, the within-player index advance is aligned across the two loops so per-ticket trait indices are identical whether or not a player's owed splits across budget slices (NO change to the frozen-word trait derivation for any non-split case); if NOT reachable, no MintModule change ships and MINTDIV-02 closes as a documented NEGATIVE with the proof. The whole diff is authored producer-before-consumer per the SPEC edit-order map, applied to `contracts/` and locally compiling/tested (`ContractAddresses.sol` freely modifiable), but NOT committed without explicit user hand-review of the single batched diff.

**Plans**: 7 plans (5 waves; W1 parallel = 335-01/02/03; W2 = 335-04; W3 = 335-05; W4 = 335-06; W5 USER hand-review = 335-07)
Plans:
**Wave 1**

- [x] 335-01-PLAN.md — Storage confirm + DegenerusGame facade: add `lazyPassHorizon` view + retire WHALE-03 autoOpen gas-weighting → flat opened-count guard
- [x] 335-02-PLAN.md — LootboxModule WHALE-01: O(1) `whalePassClaims +=` at box-open + drop ≤10 bonus band (D-21); WHALE-02 by convergence onto existing `WhaleModule:1018`
- [x] 335-03-PLAN.md — MintModule MINTDIV-02 one-liner: `processed += writesUsed >> 1` → `+= take` (matches `processFutureTicketBatch:502`)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 335-04-PLAN.md — AfKing + BurnieCoin AFSUB cluster: delete `burnForKeeper`/`paidThroughDay`/`WINDOW_DAYS`/`FLAG_WINDOW_PAID`; repurpose `Sub` offset 5 → `validThroughLevel`; rewrite subscribe + `_autoBuy` (refresh-or-evict via existing tombstone); preserve OPEN-E + v49 swap-pop

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 335-05-PLAN.md — Test migration (D-IMPL-02 full-alignment): 7 test files rewritten in lockstep with the contract diff

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 335-06-PLAN.md — Local verification: `forge build` + `forge test` green-or-baseline + `KeeperOpenBoxWorstCaseGas` re-run (D-IMPL-04 OPEN_BATCH picker); authors `335-LOCAL-VERIFICATION.md`

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 335-07-PLAN.md — BATCH-02 HARD STOP: USER hand-review gate (`autonomous: false`); ONE atomic commit covering 5 contracts + 7 tests upon explicit USER approval; NO push

**UI hint**: no

### Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression

**Goal**: The three contract items are proven behaviorally correct empirically — the whale-pass refactor materializes the same tickets/traits/whale-pass stats as the old inline mint with demonstrably uniform-O(1) opens and a freeze fuzz that the deferred record+claim perturb no current-window entropy; the pass-gated subscription sweeps while valid / evicts at the crossing with no valid pass / refreshes (continues) at the crossing with a valid pass, performs NO external pass read on the non-crossing path, re-attests the OPEN-E 4-protection behavior, and holds the cancel-tombstone / swap-pop membership invariant; the MINTDIV same-traits regression lands (covering the fix if real or codifying the not-reachable boundary if refuted); and the full suite is NON-WIDENING vs the v49.0 baseline — restoring a clean v50.0 regression baseline.
**Depends on**: Phase 335 (tests exercise the applied diff — the materialized claim path, the pass-gated sweep, the index alignment — not SPEC placeholders)
**Requirements**: TST-01, TST-02, TST-03, TST-04
**Success Criteria** (what must be TRUE):

  1. The whale-pass refactor is proven equivalent + uniform + freeze-safe (TST-01) — a box-open followed by `claimWhalePass()` yields the same materialized tickets / traits / whale-pass stats as the old inline mint; box-open is demonstrated uniform-O(1) (whale vs non-whale opener, gas-bounded equivalent); and a freeze-invariant fuzz extending the v43 `RngLockDeterminism` harness proves the deferred record + claim perturb no current-window entropy input (byte-identical consumed VRF-derived output).
  2. The AfKing pass-gated subs are proven (TST-02) — an active sub is swept while `currentLevel <= validThroughLevel`; evicted at the crossing with no valid pass; refreshed (continues) at the crossing with a valid/upgraded pass; the non-crossing path performs NO external pass read (asserted, e.g. via a call-count / state-read oracle); the OPEN-E 4-protection behavior re-attests; and the cancel-tombstone / swap-pop membership invariant holds with no missed-day regression.
  3. The MINTDIV same-traits regression lands (TST-03) — byte-identical per-ticket trait derivation across a budget-slice split for an affected player (covering the fix if MINTDIV-01 proved reachable, or codifying the not-reachable boundary with the proof if refuted) — the seed candidate is closed empirically either way.
  4. The full-suite regression is NON-WIDENING vs the v49.0 baseline (TST-04) — net-zero new regression (every red named in the v49 baseline / enumerated-deferred set by NAME), absorbing any test renames / oracle migrations from the three contract items (e.g. whale-pass open/claim test re-homes, AfKing sub-window → pass-gated oracle migration), and a clean v50.0 regression baseline ledger is recorded.

**Plans**: 6 plans (linear sequential per D-CC-02; W1=336-01, W2=336-02, W3=336-03, W4=336-04, W5=336-05, W6=336-06 USER hand-review gate per D-CC-03)
Plans:

**Wave 1** — TST-01 freeze leg

- [x] 336-01-PLAN.md — extend `test/fuzz/RngLockDeterminism.t.sol` with `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` + perturbation cls 11 (claimWhalePass); empirical re-attest of `334-WHALE04-FREEZE-PROOF.md` under default + `FOUNDRY_PROFILE=deep`

**Wave 2** *(blocked on Wave 1 completion)* — TST-01 equivalence/grant

- [x] 336-02-PLAN.md — extend `test/fuzz/RngFreezeAndRemovalProofs.t.sol` with `testClaimWhalePassMaterializesFutureWindowAndAppliesStats`; closes the file header deferral at lines 38-46 (the WHALE-01/02 roundtrip equivalence per D-TST01-03 + D-03 + D-04 + D-IMPL-01)

**Wave 3** *(blocked on Wave 2 completion)* — TST-01 uniform-O(1)

- [x] 336-03-PLAN.md — extend `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` with `testWhaleOpenerEqualsNonWhaleOpenerGas`; whale vs non-whale opener gas equivalence within documented tolerance (D-TST01-04)

**Wave 4** *(blocked on Wave 3 completion)* — TST-02 no-pass-SLOAD oracle

- [x] 336-04-PLAN.md — extend `test/fuzz/AfKingSubscription.t.sol` with `testNonCrossingPathPerformsZeroLazyPassHorizonSloads` (first `vm.expectCall` use in the test tree per RESEARCH §Summary finding 1; D-TST02-02)

**Wave 5** *(blocked on Wave 4 completion)* — TST-03 MINTDIV cross-path equality

- [ ] 336-05-PLAN.md — create NEW `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol`: deterministic anchor `testMintDivCrossPathEquality_OwedSplitsAcrossSlices` + boundary fuzz overlay `testFuzz_MintDiv_BoundaryOwedCrossPath` (D-TST03-01..04; cites `334-MINTDIV01-REACHABILITY-VERDICT.md` by path)

**Wave 6** *(blocked on Wave 5 completion)* — TST-04 ledger USER gate

- [ ] 336-06-PLAN.md — author `test/REGRESSION-BASELINE-v50.md` mirroring `test/REGRESSION-BASELINE-v49.md` §1/§2/§6/§7 verbatim; copy pre-derived 42-name v50 union from `336-RESEARCH.md` §"Pre-derived v50 baseline set"; `autonomous: false` USER hand-review gate at the binding NAME-set-equality headline per D-CC-03 (the ONLY USER-gated commit in Phase 336)
**UI hint**: no

### Phase 337: AUDIT-PROTOCOL — Author the Model-Agnostic Multi-Round External-LLM RNG-Audit Kit (Package-Only)

**Goal**: A self-contained, model-agnostic, multi-round adversarial external-LLM RNG-audit kit is authored against the FROZEN post-v50 tree (after WHALE/AFSUB/MINTDIV land) — it states the freeze invariant precisely as the external auditor's target, drives a multi-round R1→R4 adversarial sequence that forces the external model's OWN discovery (no answer key), and ships a cold-start context pack sufficient to run the contracts through Gemini or ChatGPT — so the USER can obtain an independent cross-model RNG audit in a future cycle. PACKAGE-ONLY: running it / triaging its output is explicitly OUT of v50.0. This is a documentation/deliverable phase — zero `contracts/*.sol`.
**Depends on**: Phase 336 (the protocol is authored against the FROZEN post-v50 tree — the contract items must be implemented + test-proven so the variable-tracing catalog reflects the final post-v50 read-graph, not a moving target)
**Requirements**: RNGAUDIT-01, RNGAUDIT-02, RNGAUDIT-03, RNGAUDIT-04
**Success Criteria** (what must be TRUE):

  1. The protocol states the freeze invariant precisely as the external auditor's target (RNGAUDIT-01) — "while `rngLockedFlag = true`, every storage slot that participates in any VRF-influenced output is frozen until `rngLockedFlag = false`; only the incoming VRF word + its deterministic derivations may be unknown" — plus the exempt entry points (`advanceGame()` + reachable resolution flow, the VRF coordinator callback, `retryLootboxRng()` failsafe), grounded in `v45-vrf-freeze-invariant`.
  2. The protocol is a MULTI-ROUND adversarial sequence (RNGAUDIT-02) — (R1) catalog the VRF read-graph (every participating slot with its writers + readers across all modules); (R2) independently re-derive each slot's freeze status (frozen / reverts-if-written-during-lock / proven-non-participating); (R3) adversarially challenge the catalog (hunt for any writer that escapes the freeze, any cross-module composition that does); (R4) reconcile + report — designed so the external model performs its OWN discovery, with NO answer key / no internal findings embedded ("different perspective" is the point).
  3. The protocol ships a self-contained cold-start context pack (RNGAUDIT-03) — the module/RNG-window map, the `rngLock` mechanics, where the VRF word enters and is consumed, the contract inventory, and the back-and-forth variable-tracing methodology ("trace every variable across modules — what writes it, what reads it, what is locked during an RNG window") — sufficient to run cold against the contracts WITHOUT access to our `audit/FINDINGS-*.md`.
  4. The protocol is authored against the FROZEN post-v50 tree, model-agnostic, and explicitly PACKAGE-ONLY (RNGAUDIT-04) — it reflects the post-WHALE/AFSUB/MINTDIV read-graph, is usable in both Gemini and ChatGPT (with context-window chunking guidance for feeding the contracts), and states explicitly that running it through the external models + triaging their output is a FUTURE cycle, OUT of v50.0.

**Plans**: TBD
**UI hint**: no

### Phase 338: TERMINAL — Internal Delta Audit + 3-Skill Adversarial Sweep + Closure

**Goal**: The v50.0 audit subject (the single batched diff — the O(1) whale-pass claim + pass-gated AfKing subs + the MINTDIV alignment-if-real, FROZEN at the IMPL HEAD) is delta-audited NON-WIDENING against the v49.0 baseline `b0511ca2`, swept by the internal 3-skill genuine-PARALLEL adversarial pass charged against the highest-risk whale-pass deferred-claim timing + pass-gated eviction/refresh abuse + MintModule index correctness + freeze-across-new-paths surfaces, consolidated into `audit/FINDINGS-v50.0.md`, and the milestone is closed with the `MILESTONE_V50_AT_HEAD_<sha>` signal and the atomic 5-doc closure flip — re-attesting all 25 v50.0 requirements. The internal sweep is the load-bearing close; the external RNGAUDIT protocol (Phase 337) is a separate work-product, NOT a substitute.
**Depends on**: Phase 337 (the AUDIT-PROTOCOL deliverable is part of the v50.0 work-product set re-attested at closure; and the internal sweep runs against the same frozen post-v50 tree the protocol was authored against)
**Requirements**: SWEEP-01, SWEEP-02, SWEEP-03, BATCH-03
**Success Criteria** (what must be TRUE):

  1. The internal 3-skill genuine-PARALLEL adversarial sweep runs (SWEEP-01) — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` (`/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) against the frozen v50 subject, charged with: whale-pass deferred-claim timing (can a claim alter RNG-derived outcomes / future-level traits / stats), pass-gated sub eviction-or-refresh abuse + the OPEN-E re-attest, MintModule index correctness, and freeze across ALL the new paths (the deferred record + claim, the pass-gated sweep, the index alignment) — with every elevation passed through the skeptic dual-gate before being recorded.
  2. The delta-audit attests NON-WIDENING vs the v49.0 baseline `b0511ca2` (SWEEP-02) — every `contracts/`+`test/` diff is attributable to a v50 work item (the LootboxModule whale-pass O(1) record + `claimWhalePass()`, the AfKing pass-gated sub surface, the MintModule alignment-if-real, the autoOpen carve-out retirement, the BURNIE `burnForKeeper` sink removal), each surface attested non-widening relative to the baseline, and the RNG/VRF-freeze invariant is re-attested intact across the WHALE + MINTDIV edits.
  3. `audit/FINDINGS-v50.0.md` is authored at the v50.0 closure HEAD (SWEEP-03) — 9-section, mirroring the v44/v46/v47/v48/v49 pattern, chmod 444, folding in the delta-audit (§3/§5) + the sweep disposition (§4), with any findings adjudicated or deferred per USER direction.
  4. The closure flip is applied (BATCH-03) — all 25 v50.0 requirements re-attested at closure, the `MILESTONE_V50_AT_HEAD_<sha>` closure signal emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) applied with `chmod 444` on the findings; the closure plan is a single blocking USER closure-verdict + signal-format approval gate (autonomous:false) — the auto-advance is HELD at the closure boundary per `feedback_pause_at_contract_phase_boundaries`.

**Plans**: TBD
**UI hint**: no

---

## Progress

**Execution Order:** Phases execute in numeric order: 334 → 335 → 336 → 337 → 338

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 334. SPEC — Design-Lock + MINTDIV Reachability + RNGAUDIT Structure | v50.0 | 4/4 | Complete    | 2026-05-27 |
| 335. IMPL — The ONE Batched Contract Diff | v50.0 | 7/7 | Complete   | 2026-05-28 |
| 336. TST — Equivalence + Freeze + Divergence + Regression | v50.0 | 4/6 | In Progress|  |
| 337. AUDIT-PROTOCOL — External-LLM RNG-Audit Kit (Package-Only) | v50.0 | 0/TBD | Not started | - |
| 338. TERMINAL — Internal Delta Audit + Sweep + Closure | v50.0 | 0/TBD | Not started | - |

---

## Coverage (v50.0)

**25/25 v50.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 334 SPEC | BATCH-01, WHALE-04, MINTDIV-01 | 3 |
| 335 IMPL | WHALE-01, WHALE-02, WHALE-03, AFSUB-01, AFSUB-02, AFSUB-03, AFSUB-04, AFSUB-05, MINTDIV-02, BATCH-02 | 10 |
| 336 TST | TST-01, TST-02, TST-03, TST-04 | 4 |
| 337 AUDIT-PROTOCOL | RNGAUDIT-01, RNGAUDIT-02, RNGAUDIT-03, RNGAUDIT-04 | 4 |
| 338 TERMINAL | SWEEP-01, SWEEP-02, SWEEP-03, BATCH-03 | 4 |
| **Total** | | **25** |

**Per-category split (verification):**

| Category | Total | SPEC | IMPL | TST | AUDIT-PROTOCOL | TERMINAL |
|----------|-------|------|------|-----|----------------|----------|
| WHALE | 4 | 1 (04) | 3 (01,02,03) | — | — | — |
| AFSUB | 5 | — | 5 (01–05) | — | — | — |
| MINTDIV | 2 | 1 (01) | 1 (02) | — | — | — |
| RNGAUDIT | 4 | — | — | — | 4 (01–04) | — |
| TST | 4 | — | — | 4 (01–04) | — | — |
| SWEEP | 3 | — | — | — | — | 3 (01–03) |
| BATCH | 3 | 1 (01) | 1 (02) | — | — | 1 (03) |
| **Total** | **25** | **3** | **10** | **4** | **4** | **4** |

**Center-of-gravity rationale (where a requirement spans design + impl + test):**

- **WHALE-04** (the RNG-freeze safety PROOF of the deferred-claim split — future-level target, no current-window write during `rngLock`, `_applyWhalePassStats` timing) → SPEC (334), where it is PROVEN on paper; the O(1) record + `claimWhalePass()` that the proof governs land under WHALE-01/02/03 (IMPL 335); the freeze fuzz that PROVES it empirically is TST-01 (TST 336). Centered at SPEC because the freeze-safety decision gates whether the split is even authored.
- **MINTDIV-01** (the reachability PROVE/REFUTE) → SPEC (334), because the verdict determines whether MINTDIV-02 ships a contract change at all; **MINTDIV-02** (the alignment-if-real, or the documented NEGATIVE) → IMPL (335); the same-traits-across-split regression is TST-03 (TST 336).
- **AFSUB-04/05** (OPEN-E re-attest + the cancel-tombstone/swap-pop invariant) → IMPL (335) as the structural-preservation acceptance criteria the pass-gated model must satisfy; their empirical re-attest is TST-02 (336) and the TERMINAL SWEEP-01 (338) re-attests OPEN-E as a closure condition. Homed at IMPL because the preservation must be built in, not bolted on.
- **BATCH-01** (the single SPEC design-lock) absorbs the shared-signature reconciliation + the MINTDIV-01 evidence framing + the RNGAUDIT structure sketch + the grep-attestation; it does not duplicate the WHALE/AFSUB/MINTDIV requirements those decisions feed.
- **BATCH-02** (the single batched contract diff + the contract-commit HARD STOP) → IMPL (335); the diff is authored producer-before-consumer with MINTDIV conditional on the 334 verdict.
- **RNGAUDIT-01..04** (the external-LLM protocol) → AUDIT-PROTOCOL (337) as the authoring phase; its STRUCTURE is sketched at SPEC (334, under BATCH-01 SC4) but the authored deliverable + its self-containment + model-agnosticism + package-only framing all land at 337 against the FROZEN post-v50 tree. NOT counted at SPEC — the structure sketch is design input, not the deliverable.
- **BATCH-03** (the TERMINAL closure flip) re-attests all 25 v50.0 requirements at closure — alongside SWEEP-01/02/03 in Phase 338. The internal sweep (SWEEP-01) is the load-bearing close; the external RNGAUDIT protocol (337) is a separate work-product, NOT a substitute.

✓ All 25 v50.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

**Note on §13e-style "uncovered" warnings:** as in the v47/v48/v49 roadmaps, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; SWEEP-01/02/03 + BATCH-03 re-attest the full 25-requirement set at TERMINAL. The TST / AUDIT-PROTOCOL / TERMINAL phases do not "uncover" the IMPL reqs — they re-prove, package against, and re-attest them.

---

<details>
<summary>✅ v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep (Phases 329-333) — SHIPPED 2026-05-27</summary>

**Closure signal:** `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (subject FROZEN `4c9f9d9b`; 0 NEW findings [21 probes: 15 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN]; OPEN-E 4-protection HOLD without `:676`; RNG-freeze intact; 666/42/17 by NAME). Audit baseline → subject: v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. ONE batched USER-APPROVED diff `63bc16ca` + the 331 GAS re-peg `4c9f9d9b`. Shape: SPEC → IMPL → GAS → TST → TERMINAL (the dedicated GAS phase because the break-even bounty re-peg was load-bearing). **PUSHED to origin/main 2026-05-27** (`0d9d321f`→`5803da95`, 274 commits — published the prior-unpushed v46/v47/v48/v49 contract history).

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 329. SPEC — Design-Lock + 4 Structural Invariants | 3/3 | Complete | 2026-05-26 |
| 330. IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts) | 9/9 | Complete | 2026-05-27 |
| 331. GAS — Worst-Case Marginal + Break-Even @0.5gwei Peg | 6/5 | Complete | 2026-05-27 |
| 332. TST — Freeze Fuzz + One-Category + Regression | 6/6 | Complete | 2026-05-27 |
| 333. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-27 |

**Coverage:** 36/36 requirements mapped (329 SPEC: 4 · 330 IMPL: 18 · 331 GAS: 5 · 332 TST: 5 · 333 TERMINAL: 4, re-attests all 36); 0 orphaned, 0 duplicated. Per-category: ROUTER 10 · ADV 5 · GAS 6 · GASOPT 4 (GASOPT-02 SUBSUMED into GASOPT-03) · TST 5 · SWEEP 3 · BATCH 3. Closure verdict: UNIFIED_KEEPER_ROUTER + ADVANCE_BOUNTY_RE-HOMED + BOUNTY_RE-PEGGED @0.5gwei + DEGENERETTE_RESOLVE RENAMED + GASOPT-01/03/04/05; 5 surfaces NON-WIDENING; OPEN-E 4-protection HOLD without `:676`; RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED. Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v49.0.md` (chmod 444). v50 seeds captured at closure: `v49-whale-pass-claim-refactor-seed` + `v50-afking-pass-only-sub-simplify-seed` + `mintmodule-processed-advance-divergence-seed` (the three v50.0 contract items).

</details>

<details>
<summary>✅ v48.0 sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle (Phases 325-328) — SHIPPED 2026-05-26</summary>

**Closure signal:** `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (subject frozen `1575f4a9`; 0 NEW findings; F-47-01 + F-47-02 RESOLVED_AT_V48). Audit baseline → subject: v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` → v48.0 closure HEAD. ONE batched USER-APPROVED diff `f50cc634` + the 327 HERO-04 constant-only finals landing `1575f4a9`. Shape: SPEC → IMPL → TST → TERMINAL.

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 325. SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation | 3/3 | Complete | 2026-05-25 |
| 326. IMPL — The ONE Batched Contract Diff (all 7 items) | 8/8 | Complete | 2026-05-25 |
| 327. TST — Repro/Same-Results + No-Arb + EV + Regression Proofs | 6/6 | Complete | 2026-05-26 |
| 328. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-26 |

**Coverage:** 40/40 requirements mapped (325 SPEC: 5 · 326 IMPL: 25 · 327 TST: 9 · 328 TERMINAL: 1, re-attests all 40); 0 orphaned, 0 duplicated. Per-category: PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 · HERO 6 · SWAP 9 · BATCH 3. Closure verdict: all 7 surfaces shipped (presale-drain fix, redemption stETH-fallback, keeper rename + VAULT-code 75/20/5, AfKing pool recovery, gameover BURNIE tombstone, Degenerette hero 2-pt rescale, sDGNRS far-future salvage swap); RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED. One informational SWAP cash-share doc-drift advisory (USER-accepted ≤60% as canonical, NOT a finding). Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v48.0.md` (chmod 444).

</details>

<details>
<summary>✅ v44.0–v47.0 (Phases 304-324) — SHIPPED</summary>

Full per-phase detail for v44.0 (304-308), v45.0 (309-314), v46.0 (316-320), and v47.0 (321-324) lives in `.planning/MILESTONES.md`. Summary:

- **v47.0** Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle (321-324, shipped 2026-05-25; signal `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`). 4-phase SPEC→IMPL→TST→TERMINAL; 45/45 reqs. 2 MEDIUM findings (F-47-01 + F-47-02) DEFERRED→v48.0 (both RESOLVED_AT_V48). H-CANCEL-SWAP-MISS RESOLVED_AT_V47.
- **v46.0** Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (316-320, shipped 2026-05-24; signal `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`). 6-phase FEATURE milestone with the dedicated GAS phase 319 (the break-even peg precedent v49.0 mirrored); the in-tree `AfKing` keeper shipped here. 1 MEDIUM finding H-CANCEL-SWAP-MISS DEFERRED→v47.0 (RESOLVED_AT_V47).
- **v45.0** VRF-Rotation Liveness Fix + Consolidate-Forward Delta Audit (309-314, shipped 2026-05-23, minimal close; signal `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`). The CATASTROPHE-class VRF-rotation orphan-index liveness fix; the `v45-vrf-freeze-invariant` north-star established here.
- **v44.0** sStonk Per-Day Redemption Refactor + Accounting Invariant Proof (304-308, shipped 2026-05-20; signal `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`). V-184 CATASTROPHE structurally closed; 13/13 invariants proven.

</details>

---
*Roadmap created: 2026-05-25 (v48.0)*
*v49.0 milestone added: 2026-05-26 (5 phases 329-333, SPEC→IMPL→GAS→TST→TERMINAL; 36 reqs / 7 categories) — SHIPPED 2026-05-27, archived to the collapsed block above.*
*v50.0 milestone added: 2026-05-27 (5 phases 334-338, SPEC→IMPL→TST→AUDIT-PROTOCOL→TERMINAL; 25 reqs / 7 categories: WHALE 4 · AFSUB 5 · MINTDIV 2 · RNGAUDIT 4 · TST 4 · SWEEP 3 · BATCH 3). Phase numbering continues from 333 → 334. Established audit-milestone shape extended with a dedicated package-only AUDIT-PROTOCOL phase (337) between TST and TERMINAL; the contract-boundary HARD STOP at exactly ONE IMPL phase (335); the internal 3-skill adversarial sweep + closure at TERMINAL (338) — the RNGAUDIT external protocol is a separate work-product, not a substitute for the internal sweep. MINTDIV-02 IMPL scope CONDITIONAL on the MINTDIV-01 reachability verdict at SPEC.*
