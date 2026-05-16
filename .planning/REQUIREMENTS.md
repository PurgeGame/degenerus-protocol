# Requirements: v41.0 Mint-Batch Cross-Call Determinism Fix

**Milestone:** v41.0
**Audit baseline:** `MILESTONE_V40_AT_HEAD_cd549499`
**Phase shape:** Multi-phase (final split decided at plan-phase; expected ~3-5 phases — fix + tests + sweep + terminal audit)
**Single terminal deliverable:** `audit/FINDINGS-v41.0.md` (per D-NN-FILES-01 carry → D-41N-FILES-01)
**Scope:** Fix a critical within-player determinism defect in `DegenerusGameMintModule.processFutureTicketBatch` (L385-L532). The local `uint32 processed` declared at L419 lives only on the stack, so when a single player's `owed` count exceeds the per-call `writesBudget`, subsequent calls re-enter with `processed = 0`, regenerate identical `keccak256(baseKey, entropyWord, groupIdx=0)` seeds, and emit identical 292-trait sequences. Confirmed in production on a live pre-launch indexer: 20 blocks (10862393..10862412) emitted byte-identical `TraitsGenerated(player, lvl=1, queueIdx=6, startIndex=0, count=292, entropy=2f02…)` events. **First non-zero finding milestone in v25..v41 audit history** — §4 contains a non-zero F-41-NN finding block (severity HIGH or CRITICAL; PRODUCTION_REPLAYABLE). Plus cross-surface sweep for analogous local-var-on-stack resumption defects in other batched/cursor-based loops across `contracts/modules/`.

## Out of Scope

- **Trait-credit replay or indexer rewind tooling** — v41.0 fixes forward; pre-launch state-rewind is operationally handled outside the audit repo. The audit deliverable cites the realized miscount as PRODUCTION_REPLAYABLE evidence but does NOT produce migration tooling.
- **Mint-batch architectural refactor** — `processFutureTicketBatch` retains its (writesBudget, cursor, packed-owed) cooperative-yield design. The fix is narrowly to persist within-player progress across yields, not to restructure the yield primitive.
- **`_raritySymbolBatch` algorithm changes** — the LCG + keccak-per-group-of-16 trait-generation algorithm is byte-equivalent post-fix. Only its `startIndex` input changes from `0-on-resumption` to the correct cross-call value.
- **Cross-day re-entrancy** — daily VRF (`entropy`) rotates per day; multi-call drains that span a day boundary already get fresh entropy (which would IN-SCOPE de-collide the bug). The fix targets the within-day multi-call case. Day-boundary behavior is verified preserved (not changed).
- **Mint-boost fractional retirement** (`D-40N-MINTBOOST-OUT-01` carry) — `_queueTicketsScaled` + `_rollRemainder` + `rem` byte STAY for mint-boost. v41.0 fix is to `processFutureTicketBatch`, not the upstream queuing.
- **KNOWN-ISSUES.md historical-entry shape decision** — whether to record the realized miscount as a HISTORICAL closed entry is locked at plan-phase per `D-41N-KI-01`. Default is record-as-historical (this is the first non-zero finding; the audit deliverable cites it as fixed at v41.0 close).
- **New storage layout / new admin / new upgrade hooks** — fix shape (a) may widen `ticketsOwedPacked` packed-form OR add a sibling map; this is the ONLY allowed storage-layout impact and must be attested (FIX-02 + AUDIT-04). No other storage / admin / upgrade-hook changes.
- **New public/external mutation entry points** — `processFutureTicketBatch(uint24, uint256)` selector + parameter types byte-identical post-fix. No new external entry points.
- **`runrewardjackpots` module-misplacement note** — stale 2026-04-02 backlog note; carries forward to v42.0+.
- **Game-over thorough hardening** — deferred to dedicated game-over hardening milestone.
- **LBX-02 fixture-coverage gap** (RE-DEFERRED-V41+ at v40.0 close per `D-40N-LBX02-OUT-01`) — RE-DEFERRED-V42+ at v41.0 open; fixture-coverage gap persists; analytical worst-case continues to be load-bearing per Phase 266 GAS-01 + `feedback_gas_worst_case.md`.
- **Superseded-baseline SURF `it.skip` cleanup** (RE-DEFERRED-V41+ at v40.0 close) — RE-DEFERRED-V42+ at v41.0 open; v41.0 will surface a NEW superseded-baseline SURF row at v40→v41 boundary for the MintModule patch; v42+ backlog cleanup task.

## v41.0 Requirements

### FIX — Contract-side determinism fix (contracts/modules/DegenerusGameMintModule.sol)

- [x] **FIX-01**: `processFutureTicketBatch` (L385-L532) produces a trait sequence byte-identical to a hypothetical single-call drain when a single player's `owed` count requires N ≥ 2 calls to fully drain. Concretely: for any `(rk, player)` pair where `owed > writesBudget / 2` at queue-time, the multiset of traits credited to that player across N consecutive `processFutureTicketBatch` invocations equals the multiset that a single-call drain (hypothetical infinite `writesBudget`) would have produced. Within-player progress persists across calls.
- [x] **FIX-02**: Storage layout regression — if fix shape adds a new storage slot or widens an existing slot, all non-mutated slots remain byte-identical to v40.0 closure HEAD `cd549499`. Storage-slot grep proof committed to AUDIT artifacts. Fix shape (a) widens `ticketsOwedPacked[rk][player]` beyond 40 bits OR adds a sibling map. Fix shape (b) adds an `initialOwed[rk][player]` slot at queue-time. Fix shape (c) adds nothing.
- [x] **FIX-03**: Public ABI signature byte-identical — `processFutureTicketBatch(uint24, uint256) → (bool, bool, uint32)` selector + parameter types + return shape unchanged. `TicketsCredited` + `TraitsGenerated` + `TicketsQueued` event topic hashes preserved (the `TraitsGenerated.startIndex` field's MEANING changes post-fix, but its ABI shape does not).
- [x] **FIX-04**: `TraitsGenerated.startIndex` accurately reflects within-player progress across calls. Specifically: for a single player whose drain spans N calls, the emitted `startIndex` sequence is monotonically non-decreasing within the player's batch run and resets to 0 only on the `remainingOwed == 0` transition (player completion → next player). Post-fix, an indexer can reconstruct the exact trait-sequence position from `(level, queueIdx, startIndex, count)` without ambiguity.
- [x] **FIX-05**: Fix-shape choice (a/b/c) recorded as decision anchor `D-41N-FIX-SHAPE-01` BEFORE the contract patch lands. Per `feedback_design_intent_before_deletion.md`: design-intent trace covers (i) original 40-bit packing rationale; (ii) why `processed` was placed on stack vs storage; (iii) game-theory implications of each shape (does shape c's per-call nonce open MEV / griefing on the trait-distribution? does shape a's wider packed form change `_rollRemainder` semantics for mint-boost?); (iv) gas-cost comparison at queue-time + per-call. Decision rationale committed to plan artifact.

### TST-FIX — Multi-call drain regression fixture (test/edge/ or test/mint/)

- [x] **TST-FIX-01**: Multi-call drain trait-byte-identity regression — fixture mints player with `owed > writesBudget / 2` (forcing N ≥ 2 calls within a single VRF day); advances `processFutureTicketBatch` N times with the same daily `entropy`; asserts the concatenated trait multiset matches a single-call (`writesBudget = ∞`) drain trait-by-trait. The cross-call-equivalence-to-single-call invariant is the load-bearing property the fix establishes.
- [x] **TST-FIX-02**: `TraitsGenerated.startIndex` monotonicity across calls — same fixture as TST-FIX-01; asserts emitted `startIndex` sequence is monotonically non-decreasing within a player's batch run; resets to 0 only when a new player begins in the cursor. Specifically: call 1 emits `startIndex=0, count=X1`; call 2 emits `startIndex=X1, count=X2`; … ; final call emits `startIndex=X1+X2+…, count=X_remaining` then transitions to the next player at `startIndex=0`.
- [x] **TST-FIX-03**: Distinct keccak seeds per call — assert that the keccak seed inputs `(baseKey, entropyWord, groupIdx)` differ across the N calls covering a single player. Witnessed via at least one of: (a) `groupIdx` value differs (since `groupIdx = startIndex >> 4` and `startIndex` advances per FIX-04, `groupIdx` advances by at least 1 per call covering a player); (b) synthetic test-only assertion via `expect` on cumulative trait-counts not collapsing to a 20×-duplicate distribution; (c) on-chain trace inspection of `_raritySymbolBatch` call args. Test proves the fix eliminates the v40 defect at the algorithmic level.
- [x] **TST-FIX-04**: Single-call drain byte-identity preserved — for any `(rk, player)` pair where `owed ≤ writesBudget` (single-call drain), the trait multiset post-fix matches a v40-baseline-execution trait multiset. The fix MUST NOT alter behavior when the whole player fits in one call. Captured baseline via a recorded v40 trace OR a deterministic seed run against a v40-tagged fixture.
- [x] **TST-FIX-05**: Storage layout regression — shape-dependent. **Shape (a)**: `ticketsOwedPacked` packed-form re-validation — read low 8 bits = `rem` byte (preserved); next 24 bits = `owed` (preserved); high 8+ bits = `processed` (NEW); attest the 24-bit `owed` field can still hold the maximum-owed value the contract allows. **Shape (b)**: new `initialOwed[rk][player]` slot attested; written at queue-time on the existing 4-5 callsites; storage-slot grep proof. **Shape (c)**: zero storage delta; gas regression instead (TST-FIX-NN). Test fixture matches the chosen shape; the unchosen shapes' tests are inapplicable.
- [x] **TST-FIX-06**: On-chain anchor replay regression — fixture replays the production anchor scenario: `player @ queueIdx=6` with `~5840 owed` (= 19×292 + 119+) ; daily entropy `2f02…` ; multi-call drain spanning ~20 calls. Pre-fix: produces 20 identical 292-trait sequences (matches the on-chain emission witnessed at blocks 10862393..10862412). Post-fix: produces 20 distinct trait sequences whose concatenation matches a single-call drain. The fixture is the regression artifact that would have caught the bug pre-deploy and is the load-bearing PRODUCTION_REPLAYABLE evidence for §4.

### SWEEP — Cross-surface batched-loop audit (contracts/modules/)

- [ ] **SWEEP-01**: Enumerate all batched / cursor-based loops in `contracts/modules/`. Candidate surfaces (non-exhaustive; plan-phase enumerates the full list): `DegenerusGameMintModule.processFutureTicketBatch` (CONFIRMED DEFECT); `DegenerusGameLootboxModule._resolveLootboxCommon` + auto-resolve callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`); `JackpotModule._awardDailyCoinToTraitWinners` + `_awardFarFutureCoinJackpot` + `_jackpotTicketRoll` 2-roll pattern + `_awardJackpotTickets`; `BurnieCoinflip` claim path + daily resolution loops; `DegenerusGameAdvanceModule` advance-game bounty loops; `DegenerusQuests` quest-reward batched loops; `DegenerusGameDegeneretteModule.advance` if present. Each loop catalogued in a SWEEP-LOG.md artifact.
- [ ] **SWEEP-02**: Per-loop attestation — for each loop enumerated by SWEEP-01, answer (i) does a within-iteration counter (analogous to `processed`) ever exit on the stack without being persisted to storage? (ii) does a per-call resumption regenerate identical RNG inputs (`baseKey`, `entropyWord`, `groupIdx`-equivalent)? (iii) is there a `writesBudget`-equivalent cooperative-yield mechanism that could split a single conceptual operation across calls? If all three answers are negative (no within-iteration counter, no resumption RNG collision, no cooperative yield), the loop is SAFE-BY-STRUCTURE.
- [ ] **SWEEP-03**: Lootbox queue-advance attestation — `_resolveLootboxCommon` + `resolveLootboxDirect` + `resolveRedemptionLootbox` cross-call seed-distinct attestation. v40.0 Bernoulli predicate consumes `bits[152..167]` of per-resolution seed; per-resolution seed comes from per-VRF-call `keccak(rngWord, player)` chain (v40 close trace). Each resolution is single-shot (no cooperative yield); attestation confirms no analogous defect.
- [ ] **SWEEP-04**: Jackpot ticket-award batched-loop attestation — `_awardDailyCoinToTraitWinners` + `_awardFarFutureCoinJackpot` + `_jackpotTicketRoll` 2-roll pattern (L2157/L2166) + `_awardJackpotTickets`. v40.0 Bernoulli at `JackpotModule:2216` consumes `bits[200..215]` of per-roll entropy; per-roll entropy evolves via `EntropyLib.entropyStep` between rolls. Each `_jackpotTicketRoll` is single-shot within a single `advanceGame` call. Cross-call attestation: do the jackpot batched loops EVER cooperative-yield across `advanceGame` calls? If yes, do they regenerate identical entropy on resumption? Plan-phase + sweep-execution answer.
- [ ] **SWEEP-05**: Any new F-41-NN finding surfaced by SWEEP-01..04 gets a remediation requirement (`FIX-SWEEP-NN`) and a test (`TST-SWEEP-NN`) — count expands at plan-phase. Default: 0 additional findings (mint-batch is the only known defect). The SWEEP outcome is recorded in `audit/FINDINGS-v41.0.md` §4 (any new F-41-NN finding) and §5 (sweep methodology + negative-result attestations).

### TST-SWEEP — Tests for any sweep-derived patches

- [ ] **TST-SWEEP-01**: Per sweep-derived F-41-NN finding, regression test covers the cross-call seed-distinct property at the affected surface. Count = number of new findings from SWEEP-05; default 0. Placeholder requirement; plan-phase expands or removes.

### AUDIT — Findings doc + adversarial pass

- [ ] **AUDIT-01**: `audit/FINDINGS-v41.0.md` §3.A delta-surface table enumerates the v40→v41 audit-subject commits — fix commit(s) + test commit(s) + any sweep-derived patches. Phase-row groups match the final phase split (set at plan-phase).
- [ ] **AUDIT-02**: §4 includes a non-zero **F-41-01** finding block for the mint-batch determinism defect. Severity classification per D-08 5-Bucket Severity Rubric: HIGH or CRITICAL (justification at plan-phase based on launch-posture impact). Status: PRODUCTION_REPLAYABLE (cites on-chain evidence at blocks 10862393..10862412 — 20 byte-identical `TraitsGenerated` events). Disposition: RESOLVED_AT_V41 (post fix-shape patch). Citation chain: `D-41N-FIX-SHAPE-01` + the chosen-shape contract commit + TST-FIX-06 anchor-replay regression as the load-bearing pre-deploy detection artifact.
- [ ] **AUDIT-03**: §3.C conservation re-proof — chosen fix-shape preserves (i) total-traits-credited invariant: sum over all (rk, player) of `_raritySymbolBatch.count` = sum of all queued ticket awards (`owed` consumed across all calls); (ii) bit-slice independence: shape (a)/(b) introduce no new entropy-slice consumption; shape (c) consumes a NEW entropy slice and must attest non-collision with existing consumers (bits[0..12] jackpot path-select, bits[152..167] manual+auto-resolve Bernoulli, bits[200..215] jackpot Bernoulli); (iii) storage byte-identity for non-mutated slots.
- [ ] **AUDIT-04**: §3.B zero-new-state grep-proof attestation — fix-shape (a)/(b) adds a storage slot (attested via grep); fix-shape (c) adds zero storage. ALL shapes attest zero new public/external mutation entry points; zero new admin entry points; zero new modifiers; zero new upgrade hooks. 5-row roll-up matches v36..v40 audit-attestation pattern.
- [ ] **AUDIT-05**: 3-skill PARALLEL adversarial pass (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03 carry; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry) charged specifically with red-teaming the chosen fix shape. Required hypothesis surface: (i) does the fix re-introduce a different determinism break? (ii) does shape (c) per-call-nonce open MEV / griefing on the trait-distribution (e.g., can a transaction-ordering attacker force a specific trait by selecting block number)? (iii) does shape (a) wider packed form change `_rollRemainder` interaction semantics for mint-boost paths? (iv) does shape (b) `initialOwed` storage open any griefing where a queue-time write could be manipulated? Adversarial pass disposition committed to `<phase>-01-ADVERSARIAL-LOG.md`.
- [ ] **AUDIT-06**: KI walkthrough — EXC-01..03 RE_VERIFIED-NEGATIVE-scope at v41 (the v41 audit subject has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction). EXC-04 stays STRUCTURALLY ELIMINATED (no resurrection at v41 — EntropyLib `entropyStep` was deleted at v40.0 Phase 278 `8a81a87c` and is not reintroduced). KI envelope re-verifications committed to AUDIT §6 (or wherever the v36..v40 KI walkthrough conventionally lives).
- [ ] **AUDIT-07**: §9 closure-verdict math now exercises non-zero F-NN path for the first time in audit history. Closure signal: `MILESTONE_V41_AT_HEAD_<sha>`. Closure-verdict structure: `1 of 1 F-41-NN RESOLVED_AT_V41; 0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_<MODIFIED|UNMODIFIED>` (KI status per AUDIT-08).
- [ ] **AUDIT-08**: KNOWN-ISSUES.md disposition decision recorded as `D-41N-KI-01`. Default: record realized v41-historical miscount as a HISTORICAL closed entry (cites blocks 10862393..10862412; cites RESOLVED_AT_V41 disposition; cites `D-41N-FIX-SHAPE-01`). Alternative: defer disposition to launch posture review (record only in §9 closure prose, not in KNOWN-ISSUES.md). Decision locked at plan-phase.

### REG — Regression

- [ ] **REG-01**: v40.0 closure signal `MILESTONE_V40_AT_HEAD_cd549499` NON-WIDENING for v40-touched surfaces NOT in v41 scope — `DegenerusGameLootboxModule` Bernoulli + WWXRP consolation; `JackpotModule._jackpotTicketRoll` Bernoulli + `_jackpotTicketRoll` keccak self-mix (post-ENT-05 refactor); `LootBoxOpened`/`BurnieLootOpen`/`JackpotTicketWin` event shapes; whole-BURNIE floor at LootboxModule:1080 + JackpotModule:1842/1922; all byte-identical between v40 close HEAD and v41 close HEAD on non-Mint surfaces.
- [ ] **REG-02**: v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` NON-WIDENING — TraitUtils 3 functions + `_pickSoloQuadrant` + JackpotBucketLib byte-identical at v41 close HEAD.
- [ ] **REG-03**: KI envelope EXC-01..03 re-verifications — NEGATIVE-scope at v41 (no affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction in the v41 audit subject). EXC-04 STRUCTURALLY ELIMINATED preserved — `EntropyLib.entropyStep` does not reappear in `contracts/` at v41 close HEAD.
- [ ] **REG-04**: Prior-finding spot-check sweep PASS across `audit/FINDINGS-v25..v40.0.md` for v41-touched function/surface set (`DegenerusGameMintModule.processFutureTicketBatch` + `_raritySymbolBatch` + any sweep-derived surfaces). Each prior finding on these surfaces re-verified RESOLVED or NEGATIVE-scope at v41 close HEAD.

## Traceability

REQ-ID → Phase mapping (29/29 v41.0 requirements mapped; 100% coverage; no orphans):

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-01 | Phase 281 | Complete |
| FIX-02 | Phase 281 | Complete |
| FIX-03 | Phase 281 | Complete |
| FIX-04 | Phase 281 | Complete |
| FIX-05 | Phase 281 | Complete |
| TST-FIX-01 | Phase 282 | Complete |
| TST-FIX-02 | Phase 282 | Complete |
| TST-FIX-03 | Phase 282 | Complete |
| TST-FIX-04 | Phase 282 | Complete |
| TST-FIX-05 | Phase 282 | Complete |
| TST-FIX-06 | Phase 282 | Complete |
| SWEEP-01 | Phase 283 | Pending |
| SWEEP-02 | Phase 283 | Pending |
| SWEEP-03 | Phase 283 | Pending |
| SWEEP-04 | Phase 283 | Pending |
| SWEEP-05 | Phase 283 | Pending |
| TST-SWEEP-01 | Phase 283 | Pending (placeholder; count expands at plan-phase per SWEEP-05) |
| AUDIT-01 | Phase 284 | Pending |
| AUDIT-02 | Phase 284 | Pending |
| AUDIT-03 | Phase 284 | Pending |
| AUDIT-04 | Phase 284 | Pending |
| AUDIT-05 | Phase 284 | Pending |
| AUDIT-06 | Phase 284 | Pending |
| AUDIT-07 | Phase 284 | Pending |
| AUDIT-08 | Phase 284 | Pending |
| REG-01 | Phase 284 | Pending |
| REG-02 | Phase 284 | Pending |
| REG-03 | Phase 284 | Pending |
| REG-04 | Phase 284 | Pending |

**Per-phase summary:**

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 281: Mint-Batch Determinism Fix (FIX) | FIX-01..05 | 5 |
| Phase 282: Multi-Call Drain Regression Fixture (TST-FIX) | TST-FIX-01..06 | 6 |
| Phase 283: Cross-Surface Batched-Loop Sweep (SWEEP) | SWEEP-01..05, TST-SWEEP-01 | 6 |
| Phase 284: Delta Audit + Findings Consolidation (Terminal) | AUDIT-01..08, REG-01..04 | 12 |
| **Total** | | **29** |

Coverage verdict: 29/29 v41.0 requirements mapped to exactly one phase. No orphans. No duplicates.
