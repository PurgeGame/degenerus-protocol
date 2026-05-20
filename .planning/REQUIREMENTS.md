# Requirements: Degenerus Protocol — Audit Repository

**Defined:** 2026-05-20
**Milestone:** v45.0 Close the Lootbox EV-Cap Open-Ordering Hole (V-081)
**Posture:** USER-APPROVED contract change per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_no_contract_commits.md`; AGENT-COMMITTED test/planning per `D-43N-TEST-COMMITS-AUTO-01` lineage
**Audit baseline:** v44.0 closure HEAD `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349` (source tree frozen after `67e9ea6f` + `e5928fb8`)
**Load-bearing input:** RNGLOCK catalog V-081 / S-22 + `.planning/v45-lootbox-evcap-fix-plan.md` + memory `v45-vrf-freeze-invariant`
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

---

## v45.0 Goal (precise statement)

The purchased-lootbox EV-multiplier cap allocation must be **independent of the order boxes are opened**, closing the last strict-definition self-manipulation freeze violation (V-081 / S-22). Today `_applyEvMultiplierWithCap` in `contracts/modules/DegenerusGameLootboxModule.sol` consumes the per-(player, level) `LOOTBOX_EV_BENEFIT_CAP = 10 ether` **greedily at open**, and *any* non-neutral box — including sub-100% penalty boxes — draws it down. A player who has already seen the per-index VRF word can therefore open >100% boxes first, simultaneously maximising the bonus and exhausting the cap before the penalty boxes resolve, so the sub-100% penalties never bite. The fix has two parts: **(Change 1)** a bonus-only cap so penalties (and neutral) apply in full and never touch the cap, and **(Change 2)** moving purchased-box cap consumption from open → allocation, packing the per-box bonus allocation into the existing per-(index, player) slot so `openLootBox` applies a frozen, order-independent result with no cap SLOAD/SSTORE.

**Non-negotiable closure verdict at v45.0 TERMINAL:** `V-081 RESOLVED_AT_V45; ORDER_INDEPENDENCE PROVEN; PENALTY_DODGE ELIMINATED; SEED/ROLL UNCHANGED; 0 NEW_FINDINGS; 0 FREEZE_REGRESSIONS; KNOWN_ISSUES_UNMODIFIED`.

**Gas directive (user, 2026-05-20):** pack to the maximal practical extent — tightest field widths for the cap-bounded maxima, reuse the existing slot, introduce no new slot. Packing must never trade away a freeze invariant per `feedback_security_over_gas`.

---

## v45.0 Requirements

### Spec (SPEC) — Locked Design Decisions

> Locked at the SPEC phase. Every file:line citation in the plan grep-verified against contract HEAD per `feedback_verify_call_graph_against_source.md` before any patch.

- [x] **SPEC-01**: Packed-slot layout locked. The per-(index, player) score snapshot widens from `uint16` to a single packed `uint256` word holding `score+1` (`uint16`, 0 = unset) plus `adjustedPortion` (the cap-eligible ETH that received the bonus). Field widths chosen for the cap-bounded maxima: `adjustedPortion ≤ 10 ETH` fits `uint64` (2⁶⁴ ≈ 18.44 ETH). Mapping values never cross-pack and the `uint16` already occupied a full slot, so **no new storage slot is introduced**. SPEC evaluates whether any other cap-bounded per-box field can co-pack into the same word and locks the final layout + pack/unpack helper signatures. Optional rename `lootboxEvScorePacked → lootboxEvPacked` (now genuinely packed) decided here.
- [x] **SPEC-02**: Bonus-only cap semantics locked. In `_applyEvMultiplierWithCap`, `evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS` (penalty or neutral) returns `amount * evMultiplierBps / 10_000` and never consumes the cap; only `evMultiplierBps > NEUTRAL` draws from the cap. Applies to all three callers.
- [x] **SPEC-03**: Allocation-time tally + open-time application locked. At each purchased-box deposit, with the box's frozen multiplier from the first-deposit score snapshot: if `mult <= NEUTRAL`, store `score+1` only (no cap draw); if `mult > NEUTRAL`, draw `add = min(depositAmount, remaining)` where `remaining = CAP - lootboxEvBenefitUsedByLevel[player][lvl]`, advance the used-cap accumulator, and accumulate `adjustedPortion`. First deposit writes `score+1`; later deposits accumulate `adjustedPortion` only. `openLootBox` applies `scaled = mult <= NEUTRAL ? amount*mult/1e4 : adj*mult/1e4 + (amount - adj)` with no cap SLOAD/SSTORE, and the zero-at-open write clears the whole packed slot.
- [x] **SPEC-04**: Shared-cap disposition locked. `resolveLootboxDirect` (decimator/degenerette) and `resolveRedemptionLootbox` have no purchase/allocation point and keep consuming the same per-(player, level) cap at resolution via `_applyEvMultiplierWithCap` (now with Change 1). Backward-trace per `feedback_rng_backward_trace.md` confirms the shared accumulator cannot be reordered against a known word (purchased allocation fixed pre-word; on-the-fly scores already frozen — decimator = bucket-at-burn, degenerette = bet-time; both bounded by the cap). Disposition documented (fix-or-accept) in the SPEC.

### Implementation (IMPL) — Contract Changes

> Single batched USER-APPROVED contract diff per `feedback_batch_contract_approval.md`. No partial commits. Touches `DegenerusGameStorage.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameWhaleModule.sol`.

- [x] **IMPL-01**: Bonus-only cap in `_applyEvMultiplierWithCap` (`DegenerusGameLootboxModule.sol`) per SPEC-02 — sub-neutral/neutral boxes apply directly and never consume the cap.
- [x] **IMPL-02**: Widen the per-(index, player) snapshot to the packed `uint256` layout in `DegenerusGameStorage.sol` per SPEC-01 (+ optional rename); add `uint16`/`uint64` pack/unpack helpers.
- [x] **IMPL-03**: Purchase-time cap tally at all purchased-box deposit sites — `DegenerusGameMintModule.sol` (first-deposit + subsequent branches) and `DegenerusGameWhaleModule.sol` — per SPEC-03; advance `lootboxEvBenefitUsedByLevel[player][lvl]` and accumulate `adjustedPortion`.
- [x] **IMPL-04**: `openLootBox` (`DegenerusGameLootboxModule.sol`) applies the frozen allocation per SPEC-03 with no cap SLOAD/SSTORE; zero-at-open clears the whole packed slot.
- [x] **IMPL-05**: Raw `amount` preserved for the roll seed — `keccak(rngWord, player, day, amount)` and the index/word a box rolls against are unchanged; only reward scaling uses `adjustedPortion`. `lootboxEth` layout untouched.

### Invariants (INV) — Provable Acceptance Criteria

> Each becomes a test assertion (TST). Proven against the post-IMPL source tree. INV-01..06 are carried by the Phase 311 TST phase that proves them (INV-01←TST-01; INV-02/03←TST-02; INV-04←TST-03; INV-05←TST-04; INV-06←TST-01/TST-04 demonstrate pre-word allocation, re-attested at Phase 312 SWEEP + Phase 313 §3).

- [ ] **INV-01**: Order-independence — a player with mixed >100%/<100% boxes totalling >10 ETH receives the **same** total payout regardless of the order boxes are opened.
- [ ] **INV-02**: Penalty non-dodgeable — every sub-100% box applies its penalty on the full `amount` and never consumes the cap, in any open order.
- [ ] **INV-03**: Bonus correctness — for a player with ≤10 ETH of bonus-eligible deposits, every bonus box receives its full multiplier in any open order; cap exhaustion past 10 ETH opens marginal amounts at 100%.
- [ ] **INV-04**: Seed/roll unchanged — the index/word a box rolls against and `keccak(rngWord, player, day, amount)` are byte-identical to pre-IMPL behaviour for the same deposits.
- [ ] **INV-05**: All three callers resolve — `openLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox` all produce correct payouts; the shared per-(player, level) cap accumulator introduces no known-word ordering edge.
- [ ] **INV-06**: No freeze regression — no new player-discretionary writer of any slot consumed against the live VRF word in `[rng request, unlock]`; the packing/tally changes only move pre-word allocation, never a live-resolution input.

### Test (TST) — Foundry Coverage

> Test-tree AGENT-COMMITTED per `D-43N-TEST-COMMITS-AUTO-01`.

- [ ] **TST-01**: Order-independence test — randomised open orders over a mixed >100%/<100% portfolio >10 ETH assert identical total payout (proves INV-01).
- [ ] **TST-02**: Penalty-dodge regression — a portfolio crafted to dodge penalties under the old greedy cap now always applies sub-100% penalties (proves INV-02); cap-exhaustion-past-10-ETH bonus correctness (proves INV-03).
- [ ] **TST-03**: Seed/roll invariance — assert the box's rolled index/word and seed are unchanged by the packing/scaling refactor for identical deposits (proves INV-04).
- [ ] **TST-04**: Three-caller resolution — `openLootBox` (purchased), `resolveLootboxDirect` (decimator + degenerette), `resolveRedemptionLootbox` (redemption) all resolve correctly with the shared cap (proves INV-05).
- [ ] **TST-05**: Build + gas — `forge build` PASS; gas check confirms open-path net-neutral-or-better (−1 SLOAD/−1 SSTORE at open; +1 SSTORE at allocation into the already-written packed slot) and no regression on the deposit path beyond the single packed SSTORE.

### Adversarial Sweep (SWP)

> SEQUENTIAL after IMPL + TST complete, per `D-NN-ADVERSARIAL-02` carry. HYBRID invocation: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT per `D-302-INVOKE-01`. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02`.

- [ ] **SWP-01**: Red-team the new allocation/packing surface — does purchase-time tally open a new manipulation (deposit-order griefing, cap-accounting drift across incremental deposits, packed-field overflow/aliasing), a new freeze violation, or a composition attack across deposit/open/resolve? Does the shared-cap path between purchased and on-the-fly boxes admit any known-word reorder? RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` if a candidate materialises.
- [ ] **SWP-02**: Confirm V-081 is structurally closed (not merely economically bounded) — no open order yields a different total payout; no path consumes the cap on a sub-neutral box.

### Audit Deliverable + Closure (AUDIT / CLS)

> SOURCE-TREE FROZEN during the terminal phase. Single-file deliverable per `D-NN-FILES-01`; forward-cite zero-emission per `D-NN-FCITE-01`.

- [ ] **AUDIT-01**: `audit/FINDINGS-v45.0.md` 9-section deliverable — §3 V-081 mechanic + fix attestation (order-independence proof, penalty-dodge elimination, seed-invariance, shared-cap disposition), §4 adversarial surfaces per SWP, packing/gas note; `chmod 444` at close.
- [ ] **AUDIT-02**: LEAN regression — v44.0 closure non-widening (`MILESTONE_V44_AT_HEAD_6f0ba296…` surfaces not in v45 scope unaffected) + spot-check that the EV-score/decimator/degenerette closures from `67e9ea6f`/`e5928fb8` remain intact.
- [ ] **CLS-01**: Closure flip — emit `MILESTONE_V45_AT_HEAD_<sha>` in the deliverable + cross-document propagation targets; atomic ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS flip post-§9c per `D-NN-CLOSURE-01` carry.

---

## Future Requirements (deferred, not this milestone)

- VRF-freeze housekeeping — LR_INDEX seed-search rotation confirmation (V-089/090) + re-catalog the v44 redemption storage (`pendingByDay`/`pendingResolveDay`) in RNGLOCK-CATALOG.
- v44.0 bookkeeping cleanup — flip the 36 stale v44 REQUIREMENTS.md checkboxes, register emergent INV-13/EDGE-19/EDGE-20, backfill the missing Phase 305 VERIFICATION.md.
- Remaining v43 backlog — 135 FIXREC entries (HANDOFF-01..110, 118..119), 22 ADMA recommendations (D-43N-V44-ADMA-01..22), ERRATUM-01.

## Out of Scope (explicit exclusions)

- **Re-auditing the VRF fallback + `retryLootboxRng` retry paths** — failsafes with no on-demand attack vector per memory `v45-vrf-freeze-invariant`; not player-summonable, so out of the freeze invariant's scope.
- **Accepted self-MEV races** — sDGNRS pool-balance claim-time race; boon/activity timing (now moot, all lootbox EV paths frozen at commitment). Documented, not fixed.
- **`resolveLootboxDirect` / `resolveRedemptionLootbox` purchase-side treatment** — N/A (no purchase/allocation point); they keep consuming the cap at resolution with Change 1 only.
- **New external entry points, admin surface, or behaviour changes** beyond the EV-cap allocation timing and bonus-only cap.
- **Game-over hardening** — separate dedicated milestone.

## Traceability

> Maps every v45.0 requirement to exactly one phase. INV-01..06 are provable acceptance criteria carried by the Phase 311 TST phase that proves them (each mapped to its proving TST below). 22/22 requirements mapped; 0 orphaned.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SPEC-01 | Phase 309 (SPEC) | Complete |
| SPEC-02 | Phase 309 (SPEC) | Complete |
| SPEC-03 | Phase 309 (SPEC) | Complete |
| SPEC-04 | Phase 309 (SPEC) | Complete |
| IMPL-01 | Phase 310 (IMPL) | Complete |
| IMPL-02 | Phase 310 (IMPL) | Complete |
| IMPL-03 | Phase 310 (IMPL) | Complete |
| IMPL-04 | Phase 310 (IMPL) | Complete |
| IMPL-05 | Phase 310 (IMPL) | Complete |
| INV-01 | Phase 311 (TST) — proven by TST-01 | Pending |
| INV-02 | Phase 311 (TST) — proven by TST-02 | Pending |
| INV-03 | Phase 311 (TST) — proven by TST-02 | Pending |
| INV-04 | Phase 311 (TST) — proven by TST-03 | Pending |
| INV-05 | Phase 311 (TST) — proven by TST-04 | Pending |
| INV-06 | Phase 311 (TST) — proven by TST-01/TST-04; re-attested Phase 312 SWEEP + Phase 313 §3 | Pending |
| TST-01 | Phase 311 (TST) | Pending |
| TST-02 | Phase 311 (TST) | Pending |
| TST-03 | Phase 311 (TST) | Pending |
| TST-04 | Phase 311 (TST) | Pending |
| TST-05 | Phase 311 (TST) | Pending |
| SWP-01 | Phase 312 (SWEEP) | Pending |
| SWP-02 | Phase 312 (SWEEP) | Pending |
| AUDIT-01 | Phase 313 (TERMINAL) | Pending |
| AUDIT-02 | Phase 313 (TERMINAL) | Pending |
| CLS-01 | Phase 313 (TERMINAL) | Pending |
