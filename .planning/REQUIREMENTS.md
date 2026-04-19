# Milestone v30.0 — Full Fresh-Eyes VRF Consumer Determinism Audit

**Goal:** For every function in `contracts/` that consumes a VRF word, prove that from the moment the VRF request is fired, every variable influencing how that word is eventually consumed is frozen — backward (input state committed) and forward (consumption-site state unchangeable by any actor), exhaustively enumerated. The only accepted violations of this invariant are the four documented exceptions in `KNOWN-ISSUES.md`.

**Audit baseline:** HEAD `7ab515fe` at milestone start (contract tree identical to v29.0 `1646d5af`; all post-v29 commits are docs-only).
**Write policy:** READ-only — no `contracts/` / `test/` edits.
**Deliverable:** `audit/FINDINGS-v30.0.md`.

**Accepted RNG exceptions (documented — out of scope for re-litigation):**

1. **Non-VRF entropy for affiliate winner roll** — deterministic seed, gas optimization. KNOWN-ISSUES.md.
2. **Gameover prevrandao fallback** — `_getHistoricalRngFallback` after 14-day VRF outage. KNOWN-ISSUES.md.
3. **Gameover RNG substitution for mid-cycle write-buffer tickets** — F-29-04 invariant disclosure. KNOWN-ISSUES.md.
4. **EntropyLib XOR-shift PRNG** — VRF-seeded, known theoretical non-uniformity. KNOWN-ISSUES.md.

---

## v30.0 Requirements

### INV — VRF Consumer Inventory

- [ ] **INV-01**: Exhaustively enumerate every VRF-consuming call site in `contracts/` (no sampling). The universe list of consumers — daily RNG reads, mid-day lootbox RNG reads, gap backfill reads, gameover entropy reads, and any other surfaces discovered fresh-eyes.
- [x] **INV-02**: Classify each consumer by path family: `daily` / `mid-day-lootbox` / `gap-backfill` / `gameover-entropy` / `other`. Produce a typed inventory table. (Completed 2026-04-19 — Plan 237-02; 146 rows classified in `audit/v30-237-02-CLASSIFICATION.md`; commit `f142adaf`.)
- [ ] **INV-03**: Per-consumer, produce the full call graph from VRF request origination through `rawFulfillRandomWords` to consumption site, including all intermediate storage touchpoints.

### BWD — Backward Freeze Proof (per consumer)

- [x] **BWD-01**: For each consumer, trace backward from the consumption site to its originating VRF request. Every storage read on the consumption path must map to a write site that either (a) executed before the VRF request, or (b) is unreachable by any actor between request and consumption. (Completed 2026-04-19 — Plan 238-01; 146 Backward Freeze Table rows in `audit/v30-238-01-BWD.md` with 6 shared-prefix chains + 16 bespoke-tail rows; commit `d0a37c75`.)
- [x] **BWD-02**: For each consumer, enumerate every storage variable read at consumption time. Classify each as `written-before-request` OR `unreachable-after-request`. No variable may be `mutable-after-request` except via an explicitly-documented KNOWN-ISSUES exception. (Completed 2026-04-19 — Plan 238-01; Write-Site Classification column populated for all 146 rows: 124 `written-before-request` + 22 `EXCEPTION` with KI Cross-Ref; forbidden mutable verdict absent from every data cell; commit `d0a37c75`.)
- [x] **BWD-03**: For each consumer, perform adversarial closure: can a player, admin, or validator mutate any backward-input state between request and consumption? Exhaustively answered per consumer, not sampled. (Completed 2026-04-19 — Plan 238-01; 146 Backward Adversarial Closure Table rows with 4-actor taxonomy per D-07 [player/admin/validator/VRF oracle] and closed 4-value actor-cell vocabulary per D-08 in `audit/v30-238-01-BWD.md`; BWD-03 Verdict: 124 SAFE + 22 EXCEPTION + 0 CANDIDATE_FINDING; commit `d0a37c75`.)

### FWD — Forward Freeze Proof (per consumer)

- [ ] **FWD-01**: For each consumer, enumerate every piece of state read at consumption time and map it to its write path(s). This is the "what will be read" universe for that consumer.
- [ ] **FWD-02**: For each consumer, perform adversarial closure on forward mutability: can any actor mutate any consumption-site state between VRF request and consumption? Exhaustively answered per consumer.
- [ ] **FWD-03**: For each consumer, verify the specific gating mechanism (rngLocked / lootbox index-advance / phase-transition gate / semantic path gate) actually blocks every forward mutation path identified in FWD-01/02. Gating must be proven effective, not assumed.

### RNG — rngLocked Invariant (global)

- [ ] **RNG-01**: Prove the `rngLockedFlag` set/clear state machine is airtight across all set sites, all clear sites, and all early-return / revert paths. No set-without-clear or clear-without-matching-set.
- [ ] **RNG-02**: Enumerate every permissionless function in `contracts/` that could touch RNG-consumer input state or consumption-time state. Each either (a) respects rngLocked, (b) respects an equivalent isolation (lootbox index-advance), or (c) is proven orthogonal (writes to state no RNG consumer reads).
- [ ] **RNG-03**: Re-justify from first principles the two documented asymmetries: (a) lootbox RNG uses index-advance instead of rngLockedFlag, (b) advanceGame-origin writes are exempt from the rngLocked guard via `phaseTransitionActive`. Neither may be assumed carried forward — both re-proven.

### GO — Gameover Jackpot Safety (VRF-available branch)

- [ ] **GO-01**: Enumerate every consumer of the *gameover* VRF word: gameover jackpot winner selection, trait rolls, terminal ticket drain, final-day burn/coinflip resolution, sweep distribution, and any other surfaces. The universe list of gameover-VRF consumers.
- [ ] **GO-02**: Prove the gameover jackpot is fully deterministic on the **VRF-available branch** (i.e. when the gameover VRF word is the real `rawFulfillRandomWords` output, not the prevrandao fallback). No player, admin, or validator may influence trait rolls, winner selection, or payout values between gameover VRF request and consumption.
- [ ] **GO-03**: Enumerate every state variable that feeds into gameover jackpot resolution — winner indices, pool totals, trait arrays, pending queues, counter state — each confirmed frozen at the moment of gameover VRF request.
- [ ] **GO-04**: Verify gameover trigger timing (120-day liveness stall / pool deficit) cannot be manipulated by any actor to align with a specific mid-cycle state that biases the jackpot on the VRF-available branch. Timing-based bias explicitly disproven.
- [ ] **GO-05**: Confirm the gameover jackpot branch is structurally distinct from the F-29-04 mid-cycle ticket substitution path — jackpot inputs must be frozen irrespective of write-buffer swap state. F-29-04 applies only to tickets awaiting mid-day fulfillment; it must not leak into jackpot-input determinism.

### EXC — Confirm Exceptions are Exhaustive

- [ ] **EXC-01**: Confirm the affiliate winner roll is the *only* non-VRF-seeded randomness consumer in `contracts/`. No other deterministic-seed surface (`block.timestamp`, `block.number`, packed counters, etc.) leaks into any RNG-derived payout or winner-selection path.
- [ ] **EXC-02**: Verify the gameover prevrandao fallback trigger gating still holds: only reachable inside `_gameOverEntropy`, only when an in-flight VRF request has been outstanding ≥ `GAMEOVER_RNG_FALLBACK_DELAY = 14 days`. No additional entry points exist.
- [ ] **EXC-03**: Verify F-29-04 (mid-cycle RNG substitution) scope unchanged — terminal-state only, no player-reachable timing, applies only to tickets in the post-swap write buffer. Distinct from GO-02 which covers the VRF-available gameover-jackpot branch.
- [ ] **EXC-04**: Verify `EntropyLib.entropyStep()` seed derivation remains fully VRF-derived via `keccak256(rngWord, player, day, amount)`. No new entry point bypasses the keccak seed construction.

### REG — Regression Appendix

- [ ] **REG-01**: Re-verify v29.0 RNG-adjacent findings (F-29-03, F-29-04) against current baseline. Each item PASS / REGRESSED / SUPERSEDED.
- [ ] **REG-02**: Re-verify documented rngLocked invariant items from v25.0 + v3.7 + v3.8 against current baseline (VRF path audit, VRF commitment window audit, lootbox RNG lifecycle, VRF stall resilience).

### FIND — Consolidation

- [ ] **FIND-01**: Consolidate all v30.0 findings into `audit/FINDINGS-v30.0.md` with executive summary (CRITICAL/HIGH/MEDIUM/LOW/INFO counts), per-consumer proof table covering INV + BWD + FWD + RNG + GO, and a dedicated gameover-jackpot section for GO-01..05.
- [ ] **FIND-02**: Append regression appendix to `audit/FINDINGS-v30.0.md` covering REG-01 + REG-02 with verdict per item.
- [ ] **FIND-03**: Promote any new KI-eligible items discovered in v30.0 to `KNOWN-ISSUES.md`. Items that qualify: accepted design decisions, tolerable theoretical non-uniformities, non-exploitable asymmetries.

---

## Future Requirements

_(none deferred this milestone)_

---

## Out of Scope

- ETH / BURNIE conservation — covered v29.0 Phase 235 Plans 01-02
- Indexer / database / sim / frontend — covered v28.0; not RNG scope
- Contract `test/` changes — READ-only pattern
- Contract `contracts/` edits — READ-only pattern
- Re-litigating the 4 accepted KNOWN-ISSUES RNG exceptions (affiliate roll / prevrandao fallback / F-29-04 mid-cycle substitution / EntropyLib XOR-shift)
- Cross-function ETH/BURNIE accounting — reconfirmed v29.0, not re-audited

---

## Traceability

Every v30.0 requirement maps to exactly one phase. Coverage: 26/26 (100%). No orphans.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INV-01 | Phase 237 | Pending |
| INV-02 | Phase 237 | ✅ Complete (2026-04-19, Plan 237-02) |
| INV-03 | Phase 237 | Pending |
| BWD-01 | Phase 238 | Pending |
| BWD-02 | Phase 238 | Pending |
| BWD-03 | Phase 238 | Pending |
| FWD-01 | Phase 238 | Pending |
| FWD-02 | Phase 238 | Pending |
| FWD-03 | Phase 238 | Pending |
| RNG-01 | Phase 239 | Pending |
| RNG-02 | Phase 239 | Pending |
| RNG-03 | Phase 239 | Pending |
| GO-01 | Phase 240 | Pending |
| GO-02 | Phase 240 | Pending |
| GO-03 | Phase 240 | Pending |
| GO-04 | Phase 240 | Pending |
| GO-05 | Phase 240 | Pending |
| EXC-01 | Phase 241 | Pending |
| EXC-02 | Phase 241 | Pending |
| EXC-03 | Phase 241 | Pending |
| EXC-04 | Phase 241 | Pending |
| REG-01 | Phase 242 | Pending |
| REG-02 | Phase 242 | Pending |
| FIND-01 | Phase 242 | Pending |
| FIND-02 | Phase 242 | Pending |
| FIND-03 | Phase 242 | Pending |

**Coverage summary by phase:**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 237 — VRF Consumer Inventory & Call Graph | INV-01, INV-02, INV-03 | 3 |
| 238 — Backward & Forward Freeze Proofs | BWD-01..03, FWD-01..03 | 6 |
| 239 — rngLocked Invariant & Permissionless Sweep | RNG-01, RNG-02, RNG-03 | 3 |
| 240 — Gameover Jackpot Safety | GO-01..05 | 5 |
| 241 — Exception Closure | EXC-01..04 | 4 |
| 242 — Regression + Findings Consolidation | REG-01, REG-02, FIND-01..03 | 5 |
| **Total** | | **26** |
