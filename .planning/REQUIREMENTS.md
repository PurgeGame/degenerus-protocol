# Requirements: Degenerus Protocol — Audit Repository

**Defined:** 2026-05-20 (V-081 groundwork) · **Redefined:** 2026-05-22 (consolidate-forward)
**Milestone:** v45.0 VRF-Rotation Liveness Fix + Consolidate-Forward Delta Audit
**Posture:** VRF-rotation fix is a single batched USER-APPROVED contract change per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_no_contract_commits.md` + `feedback_manual_review_before_push.md`; AGENT-COMMITTED test/planning/audit per `D-43N-TEST-COMMITS-AUTO-01` lineage. Degenerette / jackpot / V-081 contract changes already landed (user-committed).
**Audit baseline → subject:** v44.0 closure HEAD `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` → v45.0 closure HEAD. Subject = every `contracts/` commit in that delta (V-081 `9bcd582d`, jackpot pending-pool `6e5acd7e`, degenerette `92b110bf`, + the VRF-rotation fix landed this milestone).
**Load-bearing input:** `audit/FINDINGS-v44.0.md` §9d VRF-governance cluster (HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02) + memory `project_vrf_rotation_midday_orphan_index` + `v45-vrf-freeze-invariant`.
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

---

## v45.0 Goal (precise statement)

Close the CATASTROPHE-class VRF-rotation orphan-index liveness defect in `updateVrfCoordinatorAndSub` (and the governance-VRF freeze-violation cluster it overlaps), audit the already-landed degenerette refactor, and consolidate-audit every contract change since the v44.0 baseline into one closure signal at current HEAD.

**Root cause (CONFIRMED 2026-05-20):** `updateVrfCoordinatorAndSub` (AdvanceModule ~:1687) clears `rngWordCurrent` + `LR_MID_DAY` but never backfills `lootboxRngWordByIndex[N]` — the index a stalled mid-day `requestLootboxRng` swap was bound to. Scenario A (same-day advance): `processTicketBatch` reads `entropy = lootboxRngWordByIndex[N] = 0` → deterministic/entropy-0 traits (HIGH, EV-positive grind). Scenario B (next-day): daily-drain gate reverts, `requestLootboxRng`/`retryLootboxRng` bricked, orphan-backfill helper unreachable behind the revert → ~120-day freeze until `_livenessTriggered` forces a premature game-over.

**Non-negotiable closure verdict at v45.0 TERMINAL (target):** `VRF_ROTATION_ORPHAN RESOLVED_AT_V45; ROTATION_LIVENESS PRESERVED; FREEZE_INVARIANT INTACT_UNDER_ROTATION; <N> of <N> VRF_CLUSTER_ANCHORS RESOLVED; CONSOLIDATE_FORWARD_DELTA AUDITED (V-081 + jackpot-pending-pool + degenerette); 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`.

**Fix-shape directive:** NOT pre-locked. Decided at SPEC via design-intent backward-trace across timing/state combos per `feedback_design_intent_before_deletion.md`; validator-influenceable entropy backfill is rejected per `feedback_security_over_gas.md`. Recommended candidate (memory): re-issue the in-flight mid-day request on the new coordinator (keep `LR_MID_DAY=1`, set `vrfRequestId`/`rngRequestTime`) so existing retry/callback lands a real word in [N]; alternative is the §9d "queue + apply" `pendingVrfRotationPacked` split. Call-graph citations grep-verified per `feedback_verify_call_graph_against_source.md` before any patch.

---

## v45.0 Groundwork — V-081 Lootbox EV-Cap (phases 309/310, COMPLETE)

> Retained verbatim from the original v45.0 scope. These shipped at Phase 309 (SPEC) + Phase 310 (IMPL, `9bcd582d`, verified 5/5) and stand as completed groundwork. V-081 is audited as a delta surface at the TERMINAL phase (DELTA-02); its order-independence / penalty-dodge acceptance criteria are attested by construction, not by dedicated regression (see Out of Scope).

### Spec (SPEC) — Locked Design Decisions

- [x] **SPEC-01**: Packed-slot layout locked — per-(index, player) snapshot widened from `uint16` to a packed `uint256` holding `score+1` (`uint16`) + `adjustedPortion` (`uint64`, cap-bounded ≤10 ETH); no new storage slot introduced.
- [x] **SPEC-02**: Bonus-only cap semantics locked — `_applyEvMultiplierWithCap` returns `amount * evMultiplierBps / 10_000` for `<= NEUTRAL` (never consumes the cap); only `> NEUTRAL` draws from it.
- [x] **SPEC-03**: Allocation-time tally + open-time application locked — cap drawn at purchased-box deposit (`add = min(deposit, remaining)`), `openLootBox` applies the frozen allocation with no cap SLOAD/SSTORE.
- [x] **SPEC-04**: Shared-cap disposition locked — `resolveLootboxDirect` / `resolveRedemptionLootbox` keep consuming the cap at resolution; backward-trace confirms no known-word reorder.

### Implementation (IMPL) — Contract Changes (landed `9bcd582d`)

- [x] **IMPL-01**: Bonus-only cap in `_applyEvMultiplierWithCap`.
- [x] **IMPL-02**: Packed `uint256` snapshot layout + pack/unpack helpers in `DegenerusGameStorage.sol`.
- [x] **IMPL-03**: Purchase-time cap tally at the `MintModule` + `WhaleModule` deposit sites.
- [x] **IMPL-04**: `openLootBox` applies the frozen allocation; zero-at-open clears the whole packed slot.
- [x] **IMPL-05**: Raw `amount` preserved for the roll seed (`keccak(rngWord, player, day, amount)` and the rolled index/word unchanged).

---

## v45.0 Active Requirements

### VRF — VRF-Rotation Liveness Fix (the contract change)

> SPEC (311) + IMPL (312). Single batched USER-APPROVED diff touching `DegenerusGameAdvanceModule.sol` (+ any VRF-config storage). Closes the §9d governance-VRF cluster.

- [ ] **VRF-01**: After an emergency coordinator/subscription rotation while a mid-day lootbox RNG request is in flight, the bound index `lootboxRngWordByIndex[N]` resolves to a real (non-zero, VRF-derived) word — no same-day deterministic / entropy-0 traits. (Closes Scenario A.)
- [ ] **VRF-02**: After such a rotation the protocol stays live — `requestLootboxRng`, `retryLootboxRng`, and the daily-drain advance gate remain reachable; no permanent revert / ~120-day freeze / forced premature game-over. (Closes Scenario B.)
- [ ] **VRF-03**: Emergency rotation cannot break the rngLock freeze invariant — no VRF-participating slot (`vrfCoordinator`, `vrfSubscriptionId`, `vrfKeyHash`, `rngRequestTime`, `LR_MID_DAY`) is mutated mid-window in a way that changes any in-flight VRF-derived output. (Closes **HANDOFF-78/85/87/89/91** = V-137/V-155/V-157/V-159/V-161.)
- [ ] **VRF-04**: VRF wiring is one-shot — `wireVrf` seals after init; a second wire reverts. (Closes **HANDOFF-86/88/90 + ADMA-01** = V-156/V-158/V-160.)
- [ ] **VRF-05**: The rotation + wire protections cover the `DegenerusVault`-routed admin dispatch, verified by backward-trace. (**ADMA-02**.)

### DGAUD — Degenerette Refactor Audit (audit-only, `92b110bf`)

> Audit of an already-landed change; no new fix expected unless the audit surfaces one.

- [ ] **DGAUD-01**: The `92b110bf` storage-slot shift (removal of `playerDegeneretteEthWagered` + `topDegeneretteByLevel`) is confirmed safe pre-deploy — full-suite recompile clean; no storage collision with any retained slot.
- [ ] **DGAUD-02**: `dailyHeroWagers` (the Jackpot RNG hero-override input) write-path is byte-identical after the refactor — removing the per-player/per-level tracking did not alter hero-wager accounting.
- [ ] **DGAUD-03**: No dangling references to the removed mappings/views remain in `contracts/` or interfaces; off-chain leaderboard reconstruction from `BetPlaced` events is viable (events still emitted with the required fields).
- [ ] **DGAUD-04**: Backlog rows touching the degenerette surface are re-verified against the refactored module — HANDOFF-01..03 (S-02 `dailyHeroWagers`), HANDOFF-18 (V-031 prizePool degenerette-bet), HANDOFF-81 (V-142 `degeneretteBets`), HANDOFF-82 (V-147 `prizePoolPendingPacked` frozen-branch) — disposition updated.

### DELTA — Consolidate-Forward Delta Audit (terminal)

- [ ] **DELTA-01**: Audit subject re-anchored — §3.A delta-surface table enumerates every `contracts/` commit from v44.0 closure HEAD through v45.0 closure HEAD (V-081 `9bcd582d`, jackpot `6e5acd7e`, degenerette `92b110bf`, + the VRF-rotation fix).
- [ ] **DELTA-02**: V-081 (Phase 310 fix) audited as a delta surface — order-independence / penalty-dodge elimination / seed-invariance attested at source level (by construction, no dedicated regression per the ride-on-delta decision).
- [ ] **DELTA-03**: Jackpot pending-pool fix `6e5acd7e` + regression `f3e21064` audited — yield-surplus obligations now include `prizePoolPendingPacked`; no over-distribution of pending ETH as yield; no new freeze/solvency surface.
- [ ] **DELTA-04**: Degenerette refactor `92b110bf` delta covered (cross-refs DGAUD-01..04).

### VTST — VRF Regression + Freeze-Invariant Fuzz (Foundry, AGENT-COMMITTED)

- [x] **VTST-01**: Orphan-index reproduction — a pre-fix harness reproduces Scenario A (rotation mid-flight → `lootboxRngWordByIndex[N]==0` → deterministic traits); post-fix asserts a real VRF word lands in [N]. (Proves VRF-01.) — `test/fuzz/VrfRotationOrphanIndex.t.sol` (`f6cc92c9` + `611deb20`)
- [x] **VTST-02**: Liveness-after-rotation — post-fix, `requestLootboxRng` / `retryLootboxRng` / daily-drain advance all succeed after a rotation; no permanent revert / forced game-over. (Proves VRF-02.)
- [x] **VTST-03**: Freeze-invariant fuzz under rotation — perturb a coordinator/sub rotation between VRF request and fulfilment; assert every VRF-derived output is byte-identical to the no-rotation baseline (extends the v43 `RngLockDeterminism.t.sol` harness). (Proves VRF-03.)
- [ ] **VTST-04**: `wireVrf` one-shot lock — a second wire reverts; the vault-routed wire path reverts. (Proves VRF-04 / VRF-05.)

### SWP — Adversarial Sweep

> SEQUENTIAL after IMPL + VTST complete, per `D-NN-ADVERSARIAL-02` carry. HYBRID invocation: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT per `D-302-INVOKE-01`. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02`. Skeptic filter per `feedback_skeptic_pass_before_catastrophe.md` before any elevation.

- [ ] **SWP-01**: Red-team the VRF-rotation fix — rotation-spam / stuck-pending / double-request griefing, a new liveness-DoS, a new freeze violation, or a `wireVrf`-lock that breaks a legitimate ops path. RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` if a candidate materialises.
- [ ] **SWP-02**: Composition pass across the consolidated delta surfaces — V-081 allocation/packing, jackpot pending-pool obligations, degenerette removal — any cross-surface composition attack or differential behaviour an attacker can game.

### Audit Deliverable + Closure (AUDIT / REG / CLS)

> SOURCE-TREE FROZEN during the terminal phase. Single-file deliverable per `D-NN-FILES-01`; forward-cite zero-emission per `D-NN-FCITE-01`.

- [ ] **AUDIT-01**: `audit/FINDINGS-v45.0.md` 9-section deliverable — §3 VRF-rotation fix attestation (orphan-index closed, liveness preserved, freeze-invariant intact under rotation, HANDOFF/ADMA rows closed) + §3.A delta-surface table + degenerette-audit disposition + jackpot pending-pool delta; §4 adversarial surfaces per SWP; `chmod 444` at close.
- [ ] **REG-01**: LEAN regression — v44.0 closure NON-WIDENING (`MILESTONE_V44_AT_HEAD_6f0ba296…` surfaces not in v45 scope byte-identical); the EV-score / decimator / degenerette closures from `67e9ea6f` / `e5928fb8` remain intact; the v43 rngLock determinism harness still PASS.
- [ ] **CLS-01**: Closure flip — emit `MILESTONE_V45_AT_HEAD_<sha>` in the deliverable + cross-document propagation targets; atomic ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS flip post-§9c per `D-NN-CLOSURE-01` carry.

---

## Future Requirements (deferred, not this milestone)

- **Remaining ~115 v44 backlog anchors** — everything but the VRF-governance cluster: HANDOFF-01..77 (less the degenerette re-verify rows folded into DGAUD-04), 79..110, 118..119; ADMA-03..22; ADMA-ERRATUM-01. Stay in the `audit/FINDINGS-v44.0.md` §9d register (~24 active-fix sub-phases of work) for a future milestone.
- **v44.0 bookkeeping cleanup** — register emergent INV-13/EDGE-19/EDGE-20; backfill the missing Phase 305 VERIFICATION.md.
- **v43 FUZZ harness 3 missing edge-case functions** — cross-EOA Sybil within rngLock window + ERC721 receiver-callback re-entry on deity-pass mint + stETH yield accrual mid-window (v43 P302 DEFER).

## Out of Scope (explicit exclusions)

| Feature | Reason |
|---------|--------|
| Dedicated V-081 regression (order-independence / penalty-dodge) + V-081-specific sweep | User decision 2026-05-22 — V-081 rides on the consolidate-forward delta-audit (DELTA-02); criteria attested by construction at source level, not by Foundry regression. Documented coverage gap; the original INV-01..06 / TST-01..05 / SWP-01..02 are recoverable from the 309/310 SPEC. |
| Jackpot pending-pool new fix/test work | Already fixed (`6e5acd7e`) + regressed (`f3e21064`); delta-audit coverage only (DELTA-03). |
| VRF fallback / `retryLootboxRng` retry-path re-audit | Failsafes, not player-summonable per memory `v45-vrf-freeze-invariant`; outside the freeze invariant's scope. |
| Non-VRF v44 backlog anchors (claimablePool, prizePool, sDGNRS pool, activity-score/boon, ticketQueue, decBurn clusters) | Scoped out per the "VRF cluster only" backlog decision; remain in the §9d register. |
| New external entry points / admin surface beyond the VRF-rotation rework | No behaviour change outside VRF rotation + wiring lock. |
| Game-over thorough hardening | Separate dedicated milestone scope. |

## Traceability

> Maps every v45.0 requirement to a phase. Groundwork (309/310) is COMPLETE. Active-phase assignments (311–315) are the orchestrator's initial mapping; the roadmapper finalises phase boundaries and refreshes this table. VRF-01..05 are provable acceptance criteria carried by the VTST phase that proves them.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SPEC-01..04 | Phase 309 (SPEC) | Complete |
| IMPL-01..05 | Phase 310 (IMPL) | Complete |
| VRF-01 | Phase 311 (SPEC) → 312 (IMPL) — proven by VTST-01 | Pending |
| VRF-02 | Phase 311 (SPEC) → 312 (IMPL) — proven by VTST-02 | Pending |
| VRF-03 | Phase 311 (SPEC) → 312 (IMPL) — proven by VTST-03 | Pending |
| VRF-04 | Phase 311 (SPEC) → 312 (IMPL) — proven by VTST-04 | Pending |
| VRF-05 | Phase 311 (SPEC) → 312 (IMPL) — proven by VTST-04 | Pending |
| DGAUD-01 | Phase 314 (SWEEP) / 315 (TERMINAL) | Pending |
| DGAUD-02 | Phase 314 (SWEEP) / 315 (TERMINAL) | Pending |
| DGAUD-03 | Phase 314 (SWEEP) / 315 (TERMINAL) | Pending |
| DGAUD-04 | Phase 314 (SWEEP) / 315 (TERMINAL) | Pending |
| DELTA-01 | Phase 315 (TERMINAL) | Pending |
| DELTA-02 | Phase 315 (TERMINAL) | Pending |
| DELTA-03 | Phase 315 (TERMINAL) | Pending |
| DELTA-04 | Phase 315 (TERMINAL) | Pending |
| VTST-01 | Phase 313 (TST) | Complete (`f6cc92c9` + `611deb20`) |
| VTST-02 | Phase 313 (TST) | Complete |
| VTST-03 | Phase 313 (TST) | Complete |
| VTST-04 | Phase 313 (TST) | Pending |
| SWP-01 | Phase 314 (SWEEP) | Pending |
| SWP-02 | Phase 314 (SWEEP) | Pending |
| AUDIT-01 | Phase 315 (TERMINAL) | Pending |
| REG-01 | Phase 315 (TERMINAL) | Pending |
| CLS-01 | Phase 315 (TERMINAL) | Pending |

**Coverage:**
- v45.0 active requirements: 22 total (5 VRF + 4 DGAUD + 4 DELTA + 4 VTST + 2 SWP + 3 AUDIT/REG/CLS)
- Groundwork (complete): 9 (4 SPEC + 5 IMPL)
- Mapped to phases: 31 / 31 ✓ — 0 orphaned

---
*Requirements defined: 2026-05-20 (V-081) · redefined 2026-05-22 (consolidate-forward)*
*Last updated: 2026-05-22 after v45.0 redefinition — pre-roadmapper. Phase boundaries 311–315 finalised by the roadmapper.*
