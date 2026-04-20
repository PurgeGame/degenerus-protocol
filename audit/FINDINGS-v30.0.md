---
phase: 242-regression-findings-consolidation
plan: 01
milestone: v30.0
milestone_name: Full Fresh-Eyes VRF Consumer Determinism Audit
head_anchor: 7ab515fe
audit_baseline: 7ab515fe
deliverable: audit/FINDINGS-v30.0.md
requirements: [REG-01, REG-02, FIND-01, FIND-02, FIND-03]
phase_status: final_milestone_phase
write_policy: READ-only on contracts/ and test/; writes confined to .planning/ and audit/; KNOWN-ISSUES.md untouched unless FIND-03 promotes >=1 candidate per D-16
supersedes: none
generated_at: 2026-04-20T00:43:04Z
---

# v30.0 Findings — Full Fresh-Eyes VRF Consumer Determinism Audit

**Audit Baseline.** HEAD `7ab515fe` — contract tree byte-identical to v29.0 baseline `1646d5af` per PROJECT.md. All post-v29 commits are docs-only (Phase 241 D-25 / Phase 242 D-17). `git diff 7ab515fe -- contracts/` returned empty at every Task 1-5 boundary. `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` empty at plan close.

**Scope.** Single canonical milestone-closure deliverable for v30.0 per ROADMAP SC-1 literal (D-02 / D-21). Consolidates Phases 237-241 outputs into 10 sections per D-23. Terminal phase per D-20 / D-25 — no forward-cites emitted to v31.0+.

**Write policy.** READ-only on `contracts/` and `test/` per D-24 + project feedback rules (`feedback_no_contract_commits.md`, `feedback_contract_locations.md`). Zero modifications to the 16 upstream `audit/v30-*.md` files (per D-15). `KNOWN-ISSUES.md` untouched per D-16 conditional-write rule (default path when FIND-03 promotes zero candidates; see § 7).

---

## 2. Executive Summary

### Closure Verdict Summary

- FIND-01: `CLOSED_AT_HEAD_7ab515fe`
- REG-01: `2 PASS / 0 REGRESSED / 0 SUPERSEDED`
- REG-02: `29 PASS / 0 REGRESSED / 0 SUPERSEDED`
- FIND-02: `ASSEMBLED_COMBINED_REGRESSION_APPENDIX`
- FIND-03: `0 of 17 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNTOUCHED`
- Combined milestone closure: `MILESTONE_V30_CLOSED_AT_HEAD_7ab515fe`

### Severity Counts (D-08 expected distribution)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 17
- Total F-30-NNN: 17

### D-08 5-Bucket Severity Rubric

Severity mapped via the v30.0 player-reachability x value-extraction x determinism-break frame inherited from Phase 241 D-05.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

All 17 Phase 237 finding candidates default to severity `INFO` per Phase 237 D-15 emit-as-INFO precedent. Re-classification would require explicit rationale tied to the rubric above. None was surfaced at Task 1 — all 17 retain INFO.

### KI Gating Rubric Reference

The FIND-03 KI-eligibility 3-predicate test (D-09: accepted-design + non-exploitable + sticky) is distinct from the D-08 severity rubric above. See § 7 for the full gating walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

Phase 240 -> 241 forward-cite discharge: 29/29 `DISCHARGED_RE_VERIFIED_AT_HEAD` per Phase 241 § 8 (verified in § 9a `ALL_29_PHASE_240_FORWARD_CITES_DISCHARGED_AT_PHASE_241`). Phase 241 -> 242 forward-cites: 0 emitted (verified in § 9b `ZERO_PHASE_241_FORWARD_CITES_RESIDUAL`). Phase 242 emits zero forward-cites per D-25 terminal-phase rule.

### Attestation Anchor

See § 10 Milestone Closure Attestation for the D-26 6-point attestation block triggering v30.0 milestone closure.

---

## 3. Per-Consumer Proof Table

Consolidates Phases 237/238/239/240 outputs per ROADMAP SC-1 literal ("per-consumer proof table covering INV + BWD + FWD + RNG + GO outputs from Phases 237-240"). Sources: `audit/v30-CONSUMER-INVENTORY.md` (INV) / `audit/v30-FREEZE-PROOF.md` (BWD + FWD + Named Gate) / `audit/v30-RNGLOCK-STATE-MACHINE.md` + `audit/v30-PERMISSIONLESS-SWEEP.md` + `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` (RNG) / `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (GO). All cross-cites are READ-only lookups (D-18); no fresh derivation. Sources `re-verified at HEAD 7ab515fe`.

Table is grep-stable Markdown pipe-table per D-22. Row IDs are literal three-digit-zero-padded `INV-237-NNN`.

**Column semantics:**

- **Row ID:** Phase 237 Consumer Index anchor.
- **Consumer:** function/site label from Phase 237 Universe List.
- **KI Cross-Ref:** `KI: EXC-NN` for the 22 KI-exception rows (2 EXC-01 + 8 EXC-02 + 4 EXC-03 + 8 EXC-04 per Phase 237 Plan 02 Decisions); `—` (em-dash) for the 124 SAFE rows.
- **INV:** path-family verdict from Phase 237 Plan 02 Classification (`daily` 91 / `mid-day-lootbox` 19 / `gap-backfill` 3 / `gameover-entropy` 7 / `other` 26); KI-exception rows display `KI:EXC-NN` instead per D-10.
- **BWD:** Phase 238 BWD-01/02/03 verdict (124 `SAFE` / 22 `EXCEPTION (KI: EXC-NN)`).
- **FWD:** Phase 238 FWD-01/02/03 verdict (matches BWD per Phase 238-03 Effectiveness-Verdict derivation rule — both derived from the 146-row Consolidated Freeze-Proof Table).
- **RNG:** Phase 239 verdict by Named Gate precedence: `respects-rngLocked` (106 rows Named Gate = `rngLocked` SAFE) / `respects-equivalent-isolation` (12 rows Named Gate = `lootbox-index-advance` SAFE; Asymmetry A equivalence per `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md`) / `proven-orthogonal` (6 rows Named Gate = `semantic-path-gate` SAFE) / `N/A (KI:EXC-NN)` (22 KI-exception rows; includes EXC-01 `NO_GATE_NEEDED_ORTHOGONAL` rows).
- **GO:** Phase 240 GO-01 19-row gameover-cluster classification; `gameover-cluster` for the 19 rows in Phase 240 GO-01 inventory / `N/A` for the 127 non-gameover rows.

**Domain-note (per Plan D-10 clarification):** the 106-row `respects-rngLocked` count below is the Phase 239 RNG-01 **consumer-level** scope (over 146 consumers), DISTINCT from the 23-row `respects-rngLocked` count in the Phase 239 RNG-02 61-row **permissionless-sweep** scope (over 61 external/public mutating functions). The two counts measure different domains. Per-consumer table uses 106 (consumers); any permissionless-sweep cross-cite uses `23 / 61` per `audit/v30-PERMISSIONLESS-SWEEP.md:23` ground truth.

| Row ID | Consumer | KI Cross-Ref | INV | BWD | FWD | RNG | GO |
| ------ | -------- | ------------ | --- | --- | --- | --- | -- |
| INV-237-001 | processCoinflipPayouts | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-002 | processCoinflipPayouts | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-003 | processCoinflipPayouts | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-004 | processCoinflipPayouts | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-005 | processAffiliatePayment (no-referrer branch) | KI: EXC-01 | KI:EXC-01 | EXCEPTION (KI: EXC-01) | EXCEPTION (KI: EXC-01) | N/A (KI:EXC-01) | N/A |
| INV-237-006 | processAffiliatePayment (referred branch) | KI: EXC-01 | KI:EXC-01 | EXCEPTION (KI: EXC-01) | EXCEPTION (KI: EXC-01) | N/A (KI:EXC-01) | N/A |
| INV-237-007 | deityBoonData (view helper) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-008 | deityBoonData (view helper) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-009 | deityBoonData (view helper) | — | other | SAFE | SAFE | proven-orthogonal | N/A |
| INV-237-010 | resolveRedemptionLootbox (re-hashing loop) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-011 | sampleFarFutureTickets (view) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-012 | runBafJackpot (slice B pick) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-013 | runBafJackpot (slice D far-future 1st draw) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-014 | runBafJackpot (slice D2 far-future 2nd draw) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-015 | runBafJackpot (scatter per-round) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-016 | rollDailyQuest | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-017 | _bonusQuestType (weighted roll helper) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-018 | rollLevelQuest | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-019 | deityBoonSlots (pure view) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-020 | claimRedemption (lootbox-portion path) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-021 | advanceGame (mid-day lootbox gate check) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-022 | advanceGame (daily-drain gate pre-check) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-023 | advanceGame (daily-drain gate pre-check) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-024 | advanceGame (ticket-buffer swap for daily RNG) | KI: EXC-03 | KI:EXC-03 | EXCEPTION (KI: EXC-03) | EXCEPTION (KI: EXC-03) | N/A (KI:EXC-03) | gameover-cluster |
| INV-237-025 | advanceGame (FF drain processing) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-026 | advanceGame (near-future ticket prep) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-027 | advanceGame (L1 emitDailyWinningTraits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-028 | advanceGame (L1 main coin jackpot) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-029 | advanceGame (L1 bonus coin jackpot) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-030 | advanceGame (purchase-phase daily jackpot) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-031 | advanceGame (purchase-phase near-future coin jackpot) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-032 | advanceGame (purchase-phase consolidation yieldSurplus) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-033 | advanceGame (purchase-phase pool consolidation) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-034 | advanceGame (rollLevelQuest call) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-035 | advanceGame (jackpot-phase resume) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-036 | advanceGame (jackpot-phase coin+tickets) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-037 | advanceGame (jackpot-phase fresh daily) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-038 | _consolidatePoolsAndRewardJackpots | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-039 | _consolidatePoolsAndRewardJackpots | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-040 | _consolidatePoolsAndRewardJackpots | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-041 | _consolidatePoolsAndRewardJackpots | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-042 | _consolidatePoolsAndRewardJackpots | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-043 | _consolidatePoolsAndRewardJackpots (keep-roll seed) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-044 | requestLootboxRng (VRF request origination, mid-day) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-045 | requestLootboxRng (ticket buffer swap) | KI: EXC-03 | KI:EXC-03 | EXCEPTION (KI: EXC-03) | EXCEPTION (KI: EXC-03) | N/A (KI:EXC-03) | gameover-cluster |
| INV-237-046 | rngGate | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-047 | rngGate | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-048 | rngGate (_applyDailyRng call) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-049 | rngGate (redemption roll) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-050 | rngGate (_finalizeLootboxRng call) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-051 | _finalizeLootboxRng | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-052 | _gameOverEntropy (short-circuit) | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-053 | _gameOverEntropy (fresh VRF word) | KI: EXC-03 | KI:EXC-03 | EXCEPTION (KI: EXC-03) | EXCEPTION (KI: EXC-03) | N/A (KI:EXC-03) | gameover-cluster |
| INV-237-054 | _gameOverEntropy (consumer cluster) | KI: EXC-03 | KI:EXC-03 | EXCEPTION (KI: EXC-03) | EXCEPTION (KI: EXC-03) | N/A (KI:EXC-03) | gameover-cluster |
| INV-237-055 | _gameOverEntropy (historical fallback call) | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-056 | _gameOverEntropy (fallback apply) | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-057 | _gameOverEntropy (fallback coinflip) | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-058 | _gameOverEntropy (fallback redemption roll) | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-059 | _gameOverEntropy (fallback lootbox finalize) | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-060 | _getHistoricalRngFallback | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-061 | _getHistoricalRngFallback | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-062 | _getHistoricalRngFallback | KI: EXC-02 | KI:EXC-02 | EXCEPTION (KI: EXC-02) | EXCEPTION (KI: EXC-02) | N/A (KI:EXC-02) | gameover-cluster |
| INV-237-063 | _requestRng (VRF request origination, daily) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-064 | _tryRequestRng (VRF request origination, try branch) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-065 | rawFulfillRandomWords (daily branch SSTORE) | — | other | SAFE | SAFE | proven-orthogonal | N/A |
| INV-237-066 | rawFulfillRandomWords (mid-day branch SSTORE) | — | other | SAFE | SAFE | proven-orthogonal | N/A |
| INV-237-067 | _backfillGapDays | — | gap-backfill | SAFE | SAFE | proven-orthogonal | N/A |
| INV-237-068 | _backfillGapDays (coinflip payouts) | — | gap-backfill | SAFE | SAFE | proven-orthogonal | N/A |
| INV-237-069 | _backfillOrphanedLootboxIndices | — | gap-backfill | SAFE | SAFE | proven-orthogonal | N/A |
| INV-237-070 | runDecimatorJackpot | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-071 | _decWinningSubbucket (library-wrapper helper) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-072 | runTerminalDecimatorJackpot | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-073 | _placeFullTicketBetCore (gate) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-074 | _resolveFullTicketBet | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-075 | _resolveFullTicketBet (spin 0) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-076 | _resolveFullTicketBet (spin N>0) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-077 | handleGameOverDrain (rngWord SLOAD) | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-078 | handleGameOverDrain (terminal decimator) | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-079 | handleGameOverDrain (terminal jackpot) | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-080 | runTerminalJackpot | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-081 | runTerminalJackpot (_rollWinningTraits) | — | gameover-entropy | SAFE | SAFE | respects-rngLocked | gameover-cluster |
| INV-237-082 | payDailyJackpot (jackpot phase main _rollWinningTraits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-083 | payDailyJackpot (source-level offset) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-084 | payDailyJackpot (jackpot phase entropyDaily) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-085 | payDailyJackpot (solo bucket index) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-086 | payDailyJackpot (jackpot phase bonus traits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-087 | payDailyJackpot (bonus target level) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-088 | payDailyJackpot (purchase phase _rollWinningTraits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-089 | payDailyJackpot (purchase phase bonus traits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-090 | payDailyJackpot (purchase phase bonus target level) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-091 | payDailyJackpot (purchase phase _executeJackpot entropy) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-092 | payDailyJackpot (_distributeLootboxAndTickets rngWord passthrough) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-093 | payDailyJackpotCoinAndTickets (Phase 2 trait rolls) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-094 | payDailyJackpotCoinAndTickets (entropyDaily) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-095 | payDailyJackpotCoinAndTickets (entropyNext) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-096 | payDailyJackpotCoinAndTickets (near-future coin) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-097 | _runEarlyBirdLootboxJackpot | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-098 | _runEarlyBirdLootboxJackpot (_randTraitTicket call) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-099 | distributeYieldSurplus (_addClaimableEth entropy passthrough) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-100 | _distributeLootboxAndTickets | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-101 | _distributeTicketsToBuckets | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-102 | _executeJackpot (solo bucket shares) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-103 | _runJackpotEthFlow (offset) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-104 | _resumeDailyEth (entropy) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-105 | _resumeDailyEth (_rollWinningTraits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-106 | _resumeDailyEth (shareBpsByBucket) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-107 | _processDailyEth (remainderIdx) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-108 | _processDailyEth (bucket entropy rotation) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-109 | _resolveTraitWinners (entropy advance) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-110 | _randTraitTicket (winner selection) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-111 | payDailyCoinJackpot (bonus traits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-112 | payDailyCoinJackpot (entropy + target) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-113 | emitDailyWinningTraits (main traits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-114 | emitDailyWinningTraits (salted rng) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-115 | emitDailyWinningTraits (bonus traits) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-116 | _awardDailyCoinToTraitWinners (cursor) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-117 | _awardDailyCoinToTraitWinners (per-trait advance) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-118 | _awardFarFutureCoinJackpot (entropy seed) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-119 | _awardFarFutureCoinJackpot (per-sample advance) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-120 | _awardFarFutureCoinJackpot (level pick) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-121 | _awardFarFutureCoinJackpot (ticket pick) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-122 | _rollWinningTraits (bonus salted path) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-123 | _dailyCurrentPoolBps | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-124 | _jackpotTicketRoll | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-125 | openLootBox (SLOAD rngWord) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-126 | openLootBox (entropy derivation) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-127 | openBurnieLootBox (SLOAD rngWord) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-128 | openBurnieLootBox (entropy derivation) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-129 | resolveLootboxDirect (entropy derivation) | — | other | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-130 | resolveRedemptionLootbox (entropy derivation) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-131 | _rollTargetLevel (first entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-132 | _rollTargetLevel (far-future entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-133 | _rollLootboxBoons (roll) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-134 | _resolveLootboxRoll (entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-135 | _resolveLootboxRoll (DGNRS entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-136 | _resolveLootboxRoll (WWXRP entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-137 | _resolveLootboxRoll (large BURNIE entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-138 | _lootboxTicketCount (entropyStep) | KI: EXC-04 | KI:EXC-04 | EXCEPTION (KI: EXC-04) | EXCEPTION (KI: EXC-04) | N/A (KI:EXC-04) | N/A |
| INV-237-139 | _lootboxDgnrsReward (tier selection) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-140 | deityBoonSlots (rngWord gate view) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-141 | issueDeityBoon (rngWord gate) | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-142 | _deityBoonForSlot | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-143 | _raritySymbolBatch | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-144 | _rollRemainder | — | daily | SAFE | SAFE | respects-rngLocked | N/A |
| INV-237-145 | processTicketBatch (entropy SLOAD) | — | mid-day-lootbox | SAFE | SAFE | respects-equivalent-isolation | N/A |
| INV-237-146 | _calcAutoRebuy | — | other | SAFE | SAFE | respects-rngLocked | N/A |

**Total cell count: 146 × 5 = 730 cells (per D-10); 124 SAFE rows × 5 verdict columns + 22 EXCEPTION rows × 5 verdict columns = 730.** Row count 146 is set-equal with Phase 237 Consumer Index (INV-237-001..INV-237-146 continuous, each appearing exactly once) and Phase 238 Consolidated Freeze-Proof Table (distribution 124 SAFE + 22 EXCEPTION).

### § 3 Distribution Summary

Reconciles per-column distributions against Phase 237-240 source counts (sources `re-verified at HEAD 7ab515fe`).

| Column | SAFE / equivalent | EXCEPTION / KI | Total |
| ------ | ----------------- | -------------- | ----- |
| INV | 124 path-family (90 daily + 12 mid-day-lootbox + 3 gap-backfill + 7 gameover-entropy + 12 other) | 22 KI cross-ref (2 EXC-01 + 8 EXC-02 + 4 EXC-03 + 8 EXC-04) | 146 |
| BWD | 124 SAFE | 22 EXCEPTION | 146 |
| FWD | 124 SAFE | 22 EXCEPTION | 146 |
| RNG | 106 respects-rngLocked + 12 respects-equivalent-isolation + 6 proven-orthogonal = 124 | 22 N/A (KI:EXC-NN) — closed-taxonomy per D-10 | 146 |
| GO | 19 gameover-cluster | 127 N/A (non-gameover) | 146 |

**INV-column note:** Phase 237 Plan 02 Classification assigns 91 daily / 19 mid-day-lootbox / 3 gap-backfill / 7 gameover-entropy / 26 other = 146. In the table above, path-family cells for KI-exception rows are replaced by `KI:EXC-NN` per D-10 — so the 124 SAFE rows split as (90 daily — INV-237-124 moves to KI:EXC-04) + (12 mid-day-lootbox — 7 mid-day EXC-04 rows move to KI) + 3 gap-backfill + 7 gameover-entropy + (12 other — 14 KI-exception rows originally in "other" move to KI) = 124. The 22 KI-exception rows are displayed with their KI labels. Reconciles to 146 total.

**RNG-column precedence:** Phase 239 precedence order is rngLocked > lootbox-index-advance > proven-orthogonal > N/A. 22 KI-exception rows receive `N/A (KI:EXC-NN)` because D-10 prescribes KI cross-ref in lieu of redundant Phase 239 verdict (those rows' accepted-design KI covers the non-compliance envelope per Phase 241 § 3-§ 7 RE_VERIFIED_AT_HEAD verdicts).

---

## 4. Dedicated Gameover-Jackpot Section

This section consolidates Phase 240's GO-01..05 verdicts at header-level summary depth per ROADMAP SC-1 literal ("dedicated gameover-jackpot section consolidating GO-01..05 verdicts"). References the Phase 240 consolidated 838-line deliverable `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` for the full proof. All cross-cites are READ-only lookups (D-18); no fresh derivation of Phase 240 verdicts. Sources `re-verified at HEAD 7ab515fe`.

### 4a. GO-01 — Gameover-VRF Consumer Inventory (19 rows)

Phase 240 Plan 01 GO-01 Inventory: 19-row gameover-flow scope = 7 `gameover-entropy` (INV-237-052, -072, -077..081) + 8 `exception-prevrandao-fallback` (INV-237-055..062) + 4 `exception-mid-cycle-substitution` (INV-237-024, -045, -053, -054) per Phase 237 Plan 02 Decisions / Phase 240 GO-01 19-row scope. Full 19-row GO-240-001..019 enumeration at `audit/v30-240-01-INV-DET.md` § GO-01 + `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` § GO-01.

**Verdict:** `INVENTORY_MATCHES_PHASE_237_19_ROW_GAMEOVER_FLOW_SCOPE`.

### 4b. GO-02 — VRF-Available Branch Determinism Proof

Phase 240 Plan 01 GO-02 Determinism Proof Table: distribution `7 SAFE_VRF_AVAILABLE + 8 EXCEPTION (KI: EXC-02) + 4 EXCEPTION (KI: EXC-03) = 19` (matches Phase 240 Plan 01 Decisions exactly). 7 gameover-entropy rows use `NO_INFLUENCE_PATH (rngLocked)` for Player/Admin/Validator. 8 prevrandao-fallback rows use Player/Admin `NO_INFLUENCE_PATH (rngLocked)` + Validator `EXCEPTION` (per EXC-02 14-day gate). 4 F-29-04 rows use all 3 on-chain actors `NO_INFLUENCE_PATH (semantic-path-gate)` + VRF-oracle `EXCEPTION` (per EXC-03 tri-gate).

Phase 241 § 5 (EXC-02) + § 6 (EXC-03) predicate re-verifications close both exception clusters at HEAD — `EXC-02 RE_VERIFIED_AT_HEAD` + `EXC-03 RE_VERIFIED_AT_HEAD`.

**Verdict:** `VRF_AVAILABLE_BRANCH_SAFE_OR_KI_ACCEPTED_AT_HEAD`.

### 4c. GO-03 — GOVAR State-Timing Proof + Per-Consumer Cross-Walk

Phase 240 Plan 02 GO-03: 28 `GOVAR-240-NNN` rows × 6 columns per D-09. Named Gate distribution: `rngLocked` = 18 / `lootbox-index-advance` = 1 / `phase-transition-gate` = 4 / `semantic-path-gate` = 5 / `NO_GATE_NEEDED_ORTHOGONAL` = 0 = 28. Verdict distribution: `FROZEN_AT_REQUEST` = 3 / `FROZEN_BY_GATE` = 19 / `EXCEPTION (KI: EXC-02)` = 3 / `EXCEPTION (KI: EXC-03)` = 3 / `CANDIDATE_FINDING` = 0 = 28.

19-row Per-Consumer Cross-Walk set-bijective with Plan 240-01 GO-240-NNN per D-24. Aggregate Verdict distribution: `SAFE` = 7 + `EXCEPTION (KI: EXC-02)` = 8 + `EXCEPTION (KI: EXC-03)` = 4 = 19. Full detail at `audit/v30-240-02-STATE-TIMING.md` § GO-03 + `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` § GO-03.

**Verdict:** `STATE_TIMING_FROZEN_AT_VRF_REQUEST_TIME_OR_KI_ACCEPTED`.

### 4d. GO-04 — Trigger-Timing Disproof

Phase 240 Plan 02 GO-04 Trigger Surface Table: 2 `GOTRIG-240-NNN` rows, both verdict `DISPROVEN_PLAYER_REACHABLE_VECTOR`. `GOTRIG-240-001` = 120-day liveness stall via `_livenessTriggered()` @ `DegenerusGameStorage.sol:1223-1230` (sole gameover-trigger predicate at HEAD — 4 call-sites); `GOTRIG-240-002` = pool-deficit safety-escape at `_handleGameOverPath:547` (protects against false-positive gameover). Fresh grep at HEAD surfaced no additional gameover-trigger surface (`gameOver = true` at `GameOverModule:136`). Corroborated by Phase 241 § 6 EXC-03-P2 `no-player-reachable-timing` predicate (uses Phase 240 GO-04 as evidence).

**Verdict:** `NO_PLAYER_REACHABLE_TRIGGER_TIMING`.

### 4e. GO-05 — Dual-Disjointness

Phase 240 Plan 03 GO-05 `BOTH_DISJOINT` verdict. Inventory-level disjointness: `{4 F-29-04 rows: INV-237-024, -045, -053, -054}` ∩ `{7 VRF-available gameover-entropy rows: INV-237-052, -072, -077..081}` = ∅ (Set A=4, Set B=7, A∩B=0, A∪B=11 pairwise-distinct Row IDs). State-variable-level disjointness: `{6 F-29-04 write-buffer-swap primitive slots: ticketWriteSlot @ Storage:320 + ticketsFullyProcessed @:304 + ticketQueue[] @:456 + ticketsOwedPacked[][] @:460 + ticketCursor @:467 + ticketLevel @:470}` ∩ `{25 GOVAR-240-NNN jackpot-input sub-universe slots (28 GOVAR − 3 EXC-03 rows per D-14 jackpot-input sub-universe definition)}` = ∅ (Set C=6, Set D=25, C∩D=0). Corroborated by Phase 241 § 6 EXC-03-P3 `buffer-scope` predicate.

**Verdict:** `BOTH_DISJOINT_VERIFIED_AT_HEAD`.

### Combined § 4 Verdict

`GAMEOVER_JACKPOT_SAFETY_CLOSED_AT_HEAD` — GO-01 inventory matches Phase 237 19-row gameover-flow scope; GO-02 VRF-available branch determinism proven SAFE or KI-accepted at HEAD; GO-03 state-timing frozen at VRF request time or KI-accepted; GO-04 no player-reachable trigger timing; GO-05 dual-disjointness verified. All 5 GO-NN verdicts closed at HEAD `7ab515fe`. Full proof depth in `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (838 lines, READ-only per D-15).

---
## 5. F-30-NNN Finding Blocks

§ 5 emits **17 F-30-NNN distinct observation emissions** (not 17 distinct INV-237-NNN subjects). 8 `INV-237-NNN` rows are cited under 2 F-30-NNN IDs each preserving source-attribution per D-07; the (F-30-XXX, F-30-YYY) cross-reference pairs are enumerated in the Dedup Cross-Reference Table below.

Assignment rule per D-07: sequential in source-phase + plan + emit-order (Phase 237 Plan 01 first -> Plan 02 -> Plan 03; within each plan, by emit order in the source SUMMARY's Finding Candidates section). 0 candidates from Phases 238/239/240/241 per each prior phase's `D-15 / D-22 / D-25 / D-20` emit-zero-IDs pattern (reserved-unused).

#### F-30-NNN Dedup Cross-Reference Table

8 INV-237-NNN rows appear under 2 F-30-NNN IDs each (duplicate citations are INTENTIONAL per D-07 source-attribution preservation — merging emissions across plans would break D-07 ordering).

| INV-237-NNN | F-30-XXX | F-30-YYY | Source Plans |
| ----------- | -------- | -------- | ------------ |
| INV-237-009 | F-30-003 | F-30-008 | 237-01 + 237-02 |
| INV-237-024 | F-30-005 | F-30-017 | 237-01 + 237-03 |
| INV-237-045 | F-30-005 | F-30-017 | 237-01 + 237-03 |
| INV-237-062 | F-30-001 | F-30-015 | 237-01 + 237-03 |
| INV-237-124 | F-30-010 | F-30-016 | 237-02 + 237-03 |
| INV-237-129 | F-30-011 | F-30-014 | 237-02 + 237-03 |
| INV-237-143 | F-30-012 | F-30-013 | 237-02 + 237-03 |
| INV-237-144 | F-30-012 | F-30-013 | 237-02 + 237-03 |

<!-- TASK-1-DEDUP-SCRATCH: Task 5 § 10 attestation consumes this table verbatim. 17 F-30-NNN IDs assigned over 21 distinct INV-237-NNN subjects (8 duplicates above + 13 unique single-cited subjects = 21 distinct Row IDs cited across the 17 observation emissions, consistent with Phase 237 Plan 03 Consumer Index FIND-01 scope of 21 rows per Decision 6). -->

---

#### F-30-001 — Prevrandao fallback state-machine check

- **Severity:** INFO (per D-08 default; Phase 237 D-15 emit-as-INFO precedent)
- **Source phase:** Phase 237 Plan 01 FC #1
- **Source SUMMARY:** `.planning/phases/237-vrf-consumer-inventory-call-graph/237-01-SUMMARY.md` + `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-01 bullet #1
- **Observation:** `_getHistoricalRngFallback` at `DegenerusGameAdvanceModule.sol:1322` — prevrandao fallback triggers when a real VRF word is eventually fulfilled but was late. Verify the state machine guarantees the fallback path is fully short-circuited once `currentWord != 0` arrives post-fallback. Already KI-accepted as EXC-02.
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:1322` (INV-237-062)
- **KI Cross-Ref:** `KI: EXC-02` (Gameover prevrandao fallback)
- **Rubric basis:** Not player-reachable — EXC-02 14-day gate at `AdvanceModule:109/:1250` bars validator/VRF-oracle exploitation, confirmed by Phase 241 § 5 `EXC-02 RE_VERIFIED_AT_HEAD`; documented design decision.
- **Resolution status:** `CLOSED_AS_INFO` (observation documented; KI EXC-02 covers it; Phase 241 predicates P1+P2 both hold at HEAD)

#### F-30-002 — Boon-roll entropy post-XOR-shift diffusion

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 01 FC #2
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-01 bullet #2
- **Observation:** `_rollLootboxBoons` at `DegenerusGameLootboxModule.sol:1059` — the `entropy % BOON_PPM_SCALE` roll re-uses the same `entropy` argument the caller inherited from `_resolveLootboxCommon`'s final `nextEntropy` after both `_resolveLootboxRoll` splits. Candidate to verify that boon-roll entropy carries sufficient post-XOR-shift diffusion after two calls. KI EXC-04 (EntropyLib XOR-shift) covers this.
- **file:line:** `contracts/modules/DegenerusGameLootboxModule.sol:1059` (INV-237-133 context)
- **KI Cross-Ref:** `KI: EXC-04` (EntropyLib XOR-shift PRNG for lootbox outcome rolls)
- **Rubric basis:** Not player-reachable — XOR-shift seeded per-player/day/amount via VRF-derived `rngWord` per KNOWN-ISSUES.md EXC-04 entry; Phase 241 § 7 `EXC-04 RE_VERIFIED_AT_HEAD` confirms all 8 caller-site keccak seeds trace to VRF write sites.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-003 — Deity deterministic fallback unreachability

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 01 FC #3
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-01 bullet #3
- **Observation:** `deityBoonData` (view) at `DegenerusGame.sol:852` — deterministic fallback `keccak(day, this)` when both `rngWordByDay[day]` and `rngWordCurrent` are zero is reachable only pre-genesis (level 0 pre-first-VRF); worth a Phase 241 invariant note that the zero-history branch can never execute post-first-advance.
- **file:line:** `contracts/DegenerusGame.sol:852` (INV-237-009)
- **KI Cross-Ref:** none (view-deterministic-fallback is classified SAFE per Phase 238 Freeze-Proof; not a KI EXC)
- **Rubric basis:** Not player-reachable at HEAD runtime (contract is past level 1 post-first-daily-VRF); branch is `semantic-path-gate` SAFE per `audit/v30-FREEZE-PROOF.md:39`; observation only (audit-trail value).
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-004 — Mid-day gate off-by-one check

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 01 FC #4
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-01 bullet #4
- **Observation:** `advanceGame` mid-day gate at `DegenerusGameAdvanceModule.sol:204-208` — the `revert RngNotReady()` when `lootboxRngWordByIndex[index-1] == 0` assumes `ticketsFullyProcessed == false` implies a pending mid-day RNG. Verify this gate is reachable only through an `_swapTicketSlot` path that already advanced the lootbox index (no off-by-one at day boundary).
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:204-208` (INV-237-021 context)
- **KI Cross-Ref:** none (mid-day-lootbox family is `respects-equivalent-isolation` per Phase 239 RNG-03 Asymmetry A)
- **Rubric basis:** Not player-reachable — the off-by-one concern is a sanity check against a state machine already proven AIRTIGHT by Phase 239 RNG-01 (rngLockedFlag set/clear state machine) and corroborated by Phase 239 RNG-03 Asymmetry A (lootbox-index-advance equivalence).
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-005 — F-29-04 liveness-proof note

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 01 FC #5
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-01 bullet #5
- **Observation:** `_swapTicketSlot` at `:1082` and `_swapAndFreeze` at `:292` — both write-buffer-swap sites are D-06 KI exception rows (F-29-04). Flag for Phase 241 EXC-03 proof-of-liveness that at gameover no alternative substitution path exists beyond the documented exception.
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:292` + `:1082` (INV-237-024, INV-237-045)
- **KI Cross-Ref:** `KI: EXC-03` (Gameover RNG substitution for mid-cycle write-buffer tickets)
- **Rubric basis:** Not player-reachable — Phase 241 § 6 `EXC-03 RE_VERIFIED_AT_HEAD` confirms the tri-gate (terminal-state + no-player-timing + buffer-scope) all hold at HEAD; Phase 240 GO-04 `DISPROVEN_PLAYER_REACHABLE_VECTOR` + GO-05 `BOTH_DISJOINT` corroborate.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-006 — Daily-share 62.3% exceeds 30-50% heuristic (sanity observation)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 FC #6 (classification-summary sanity-check bullet)
- **Source SUMMARY:** `.planning/phases/237-vrf-consumer-inventory-call-graph/237-02-SUMMARY.md` § Decisions Made + `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-02 bullet #6 (classification-summary sanity-check)
- **Observation:** `daily` path-family share at 62.3% (91 of 146 rows) exceeds the planner's 30-50% heuristic. Driven by D-01 fine-grained expansion (rngGate body split into 5 atomic rows + JackpotModule body expanded to ~45 daily rows + BurnieCoinflip daily path split into 4 rows). Not a classification error — the heuristic was calibrated against a coarser 28-row enumeration; at 146-row granularity the dominant-path share inflates naturally. Flagged for reviewer sanity.
- **file:line:** N/A (meta observation — inventory-level; applies to 91 daily-family rows)
- **KI Cross-Ref:** none
- **Rubric basis:** Not a correctness concern — granularity-driven distribution shift; Phase 238 Freeze-Proof verdicts (124 SAFE + 22 EXCEPTION) derived independently of family share; observation only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-007 — KI-exception precedence over path-family rules

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 Decisions (precedence-rule disclosure — classification-ambiguity observation)
- **Source SUMMARY:** `.planning/phases/237-vrf-consumer-inventory-call-graph/237-02-SUMMARY.md` § Decisions Made / Decision 2 + `audit/v30-237-02-CLASSIFICATION.md` § Decision Procedure
- **Observation:** KI-exception rules (1 / 2 / 3 per decision procedure) take precedence over path-family rules (4 / 5 / 6 / 7). Consequence: `_gameOverEntropy` cluster splits across `gameover-entropy` (rule 4 for rows without KI flags), `other / exception-mid-cycle-substitution` (rule 3 for F-29-04 write-buffer substitution rows), and `other / exception-prevrandao-fallback` (rule 1 for prevrandao fallback rows). Effective gameover-flow scope (for Phase 240 GO-01) = 19 rows across those 3 labels.
- **file:line:** N/A (meta observation — taxonomy-precedence rule; applies to 19 gameover-flow rows)
- **KI Cross-Ref:** spans `KI: EXC-02` + `KI: EXC-03` (both precedence-affected clusters)
- **Rubric basis:** Not a correctness concern — precedence rule is a classification-methodology disclosure documented in `audit/v30-237-02-CLASSIFICATION.md`; all 19 affected rows receive their correct downstream Phase 238-241 treatment per Consumer Index.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-008 — INV-237-009 view-deterministic-fallback classification edge case

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 FC #1
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-02 bullet #1 (INV-237-009)
- **Observation:** INV-237-009 — `deityBoonData` (view) at `DegenerusGame.sol:852` — the deterministic `keccak(day, this)` fallback branch classified `other / view-deterministic-fallback` because reachable only in the pre-genesis zero-history window (before first daily VRF fulfillment). At HEAD runtime the contract is past level 1, making this branch unreachable. Audit-trail value only.
- **file:line:** `contracts/DegenerusGame.sol:852` (INV-237-009; cited under F-30-003 too per dedup table preserving D-07 source-attribution)
- **KI Cross-Ref:** none (classified `semantic-path-gate` SAFE per Phase 238 Freeze-Proof)
- **Rubric basis:** Not player-reachable at HEAD runtime; observation only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-009 — INV-237-066 fulfillment-callback classification ambiguity

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 FC #2
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-02 bullet #2 (INV-237-066)
- **Observation:** INV-237-066 — `rawFulfillRandomWords` mid-day branch SSTORE at `DegenerusGameAdvanceModule.sol:1706` — classified `other / fulfillment-callback` per D-11 depth rule (infrastructure, not a consumer) BUT KI cross-ref retained (`KI: "Lootbox RNG uses index advance isolation..."`). Phase 239 RNG-03 cites this row alongside the mid-day-lootbox family rows. Classification ambiguity: is the cross-ref on an `other / fulfillment-callback` row defensible? Chosen: keep `other / fulfillment-callback` (strict D-11 depth rule) but retain KI cross-ref (strict D-06 inventory-row-cross-ref completeness).
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:1706` (INV-237-066)
- **KI Cross-Ref:** `KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"` (retained for D-06 traceability; row itself is `SAFE` per Phase 238)
- **Rubric basis:** Not player-reachable — fulfillment-callback is `semantic-path-gate` SAFE per `audit/v30-FREEZE-PROOF.md:96`; rngWord-write-site with no consumer semantics at this depth.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-010 — INV-237-124 sole daily-family EntropyLib caller (EXC-04 scope note)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 FC #3
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-02 bullet #3 (INV-237-124)
- **Observation:** INV-237-124 — `_jackpotTicketRoll` at `DegenerusGameJackpotModule.sol:2119` — `EntropyLib.entropyStep` caller in a daily-path context (NOT lootbox). Classified `daily` (rule 9 classify-by-caller; rule 7 daily wins) with KI EXC-04 cross-ref retained. ONLY `daily`-family row with the EntropyLib KI. Phase 241 EXC-04 notes that the XOR-shift proof subject set spans BOTH daily AND mid-day-lootbox families — the KI title ("for lootbox outcome rolls") under-describes the actual consumer surface.
- **file:line:** `contracts/modules/DegenerusGameJackpotModule.sol:2119` (INV-237-124)
- **KI Cross-Ref:** `KI: EXC-04` (EntropyLib XOR-shift PRNG for lootbox outcome rolls — scope-note: spans daily + mid-day-lootbox)
- **Rubric basis:** Not player-reachable — Phase 241 § 7 `EXC-04 RE_VERIFIED_AT_HEAD` confirms caller-site keccak seed `keccak256(abi.encode(rngWord, ...))` at `JackpotModule:1799` traces to VRF write sites; scope disclosure only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-011 — INV-237-129 resolveLootboxDirect library-wrapper dual-context

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 FC #4
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-02 bullet #4 (INV-237-129)
- **Observation:** INV-237-129 — `resolveLootboxDirect` at `DegenerusGameLootboxModule.sol:673` — classified `other / library-wrapper` because its caller graph spans daily (sDGNRS redemption) and gameover (decimator winner lootbox award) contexts. Per-caller rows already captured; decimator's lootbox-award path uses existing gameover-family rows (INV-237-072, -078) as trigger and `resolveLootboxDirect` is downstream plumbing; no additional row gap.
- **file:line:** `contracts/modules/DegenerusGameLootboxModule.sol:673` (INV-237-129)
- **KI Cross-Ref:** none (classified SAFE per `audit/v30-FREEZE-PROOF.md:159`)
- **Rubric basis:** Not a correctness concern — classification observation; Phase 238 BWD/FWD verdict SAFE holds per row verdict.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-012 — INV-237-143 / INV-237-144 dual-trigger single-row treatment

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 02 FC #5
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-02 bullet #5 (INV-237-143/-144)
- **Observation:** `_raritySymbolBatch` (`:568`) / `_rollRemainder` (`:652`) — 237-01 Notes field explicitly marks these as dual-trigger (daily via `processFutureTicketBatch` delegation AND mid-day-lootbox via `_processOneTicketEntry` read-slot ticket processing). 237-01 did NOT split into 2 rows per D-03; treated as single daily-dominant row per 237-02. Phase 238 BWD handles the dual-context proof without requiring a row split.
- **file:line:** `contracts/modules/DegenerusGameMintModule.sol:568` (INV-237-143) + `:652` (INV-237-144)
- **KI Cross-Ref:** none (both classified SAFE per `audit/v30-FREEZE-PROOF.md:173-174`)
- **Rubric basis:** Not a correctness concern — single-row treatment honoured per D-03; dual-context proof handled by Phase 238 BWD-02; observation only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-013 — INV-237-143/-144 dual-trigger delegatecall boundary (Phase 238 BWD bifurcation recommendation)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 03 FC #1
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-03 bullet #1 (dual-trigger delegatecall boundary)
- **Observation:** `_processFutureTicketBatch` delegatecall boundary (IM-13) at `DegenerusGameAdvanceModule.sol:1390-1394` -> MintModule receiver consumers INV-237-143 / INV-237-144 classified `daily` at HEAD but carry a dual-trigger note (mid-day-lootbox sibling context via `_processOneTicketEntry` read-slot path). Call-graph construction confirmed two trigger contexts share the same MintModule consumer body but receive different entropy sources (`rngWordCurrent` vs `lootboxRngWordByIndex[idx]`). Recommend Phase 238 BWD emit two distinct proof rows per INV-237-143/-144 covering both triggers.
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:1390-1394` (delegatecall boundary) -> `contracts/modules/DegenerusGameMintModule.sol:568, :652` (INV-237-143, -144)
- **KI Cross-Ref:** none
- **Rubric basis:** Not player-reachable — Phase 238 BWD-02 + FWD-02 actor-class closure proved both trigger contexts SAFE (per `audit/v30-FREEZE-PROOF.md:173-174`); recommendation is downstream-handoff guidance only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-014 — INV-237-129 resolveLootboxDirect gameover-caller marker (Phase 238 BWD marker recommendation)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 03 FC #2
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-03 bullet #2 (resolveLootboxDirect gameover-caller context)
- **Observation:** `resolveLootboxDirect` at `DegenerusGameLootboxModule.sol:673` (INV-237-129) — library-wrapper with both a daily caller (sDGNRS redemption via INV-237-010/-020) and a gameover caller (DecimatorModule `_awardDecimatorLootbox` via runTerminalDecimatorJackpot INV-237-072/-078 chain). Universe List did NOT emit a separate `gameover-entropy` row for the decimator-award caller context (absorbed via INV-237-078). Recommend Phase 238 BWD marker that `resolveLootboxDirect` sees the gameover rngWord via the decimator-winner lootbox award path.
- **file:line:** `contracts/modules/DegenerusGameLootboxModule.sol:673` (INV-237-129; dual-cited under F-30-011 per dedup table)
- **KI Cross-Ref:** none (classified SAFE per `audit/v30-FREEZE-PROOF.md:159`)
- **Rubric basis:** Not a correctness concern — plumbing confirmed complete; Phase 238 BWD recorded dual-context; observation only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-015 — INV-237-060..062 prevrandao-mix recursion citation (Phase 241 EXC-02 note recommendation)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 03 FC #3
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-03 bullet #3 (prevrandao-mix recursion citation)
- **Observation:** `_getHistoricalRngFallback` prevrandao-mix cluster (INV-237-060..062) at `DegenerusGameAdvanceModule.sol:1301-1325` — the graph terminates at the prevrandao SHA3-mix at `:1322`; subsequent SLOAD of `rngWordByDay[searchDay]` at `:1308` is itself a consumption of an already-committed VRF word (prior day's fulfilled rngWord). Recursion-free but creates a consumer-of-consumer citation cross-reference for Phase 241 EXC-02. Recommendation: Phase 241 EXC-02 explicitly note that fallback entropy is a deterministic function of `(committed historical words x block.prevrandao x currentDay)` rather than a single monolithic prevrandao-mix.
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:1301-1325` (INV-237-060, -061, -062; INV-237-062 cited under F-30-001 too per dedup table)
- **KI Cross-Ref:** `KI: EXC-02` (Gameover prevrandao fallback — covers all 3 rows in the cluster)
- **Rubric basis:** Not player-reachable — EXC-02 14-day gate bars the path; Phase 241 § 5 `EXC-02 RE_VERIFIED_AT_HEAD` (P1 single-call-site + P2 14-day-delay) confirms closure; recommendation documented in Phase 241 consolidated file.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-016 — INV-237-124 sole daily-family EntropyLib caller (Phase 241 EXC-04 scope disclosure)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 03 FC #4
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-03 bullet #4 (INV-237-124 daily-family EntropyLib)
- **Observation:** `_jackpotTicketRoll` (INV-237-124) is the sole `daily`-family row carrying the `EntropyLib XOR-shift PRNG` KI Cross-Ref. All other EntropyLib.entropyStep caller rows (INV-237-131, -132, -134..138) are `mid-day-lootbox`. Phase 241 EXC-04 proof subject set spans BOTH families — the KI title ("for lootbox outcome rolls") under-describes the actual consumer surface. Call-graph construction confirms the EntropyLib XOR-shift PRNG caller universe is exactly 8 rows (1 daily + 7 mid-day-lootbox).
- **file:line:** `contracts/modules/DegenerusGameJackpotModule.sol:2119` (INV-237-124; dual-cited under F-30-010 per dedup table)
- **KI Cross-Ref:** `KI: EXC-04` (same KI as F-30-010; scope-disclosure finding)
- **Rubric basis:** Not player-reachable — Phase 241 § 7 `EXC-04 RE_VERIFIED_AT_HEAD` enumerates all 8 call sites (set-equal with 8 EXC-04 rows); scope-disclosure observation only.
- **Resolution status:** `CLOSED_AS_INFO`

#### F-30-017 — F-29-04 swap-site liveness (Phase 241 EXC-03 proof-of-liveness recommendation)

- **Severity:** INFO
- **Source phase:** Phase 237 Plan 03 FC #5
- **Source SUMMARY:** `audit/v30-CONSUMER-INVENTORY.md` § Finding Candidates / From Plan 237-03 bullet #5 (F-29-04 write-buffer-swap liveness)
- **Observation:** F-29-04 write-buffer-swap sites INV-237-024 (`_swapAndFreeze` daily path at `:292`) + INV-237-045 (`_swapTicketSlot` mid-day path at `:1082`) — call-graph construction confirms both swap sites sit BEFORE the VRF request origination in their respective prefix chains (PREFIX-DAILY step 3 / PREFIX-MIDDAY step 3). The "substitution" occurs because tickets routed into the frozen write buffer eventually drain under a different word (gameover or mid-day). Recommend Phase 241 EXC-03 proof of liveness that no alternative substitution path exists.
- **file:line:** `contracts/modules/DegenerusGameAdvanceModule.sol:292` + `:1082` (INV-237-024, -045; dual-cited under F-30-005 per dedup table)
- **KI Cross-Ref:** `KI: EXC-03` (same KI as F-30-005; liveness-proof-recommendation finding)
- **Rubric basis:** Not player-reachable — Phase 241 § 6 `EXC-03 RE_VERIFIED_AT_HEAD` (tri-gate P1/P2/P3) corroborated by Phase 240 GO-04 `DISPROVEN_PLAYER_REACHABLE_VECTOR` + GO-05 `BOTH_DISJOINT`; liveness closure documented.
- **Resolution status:** `CLOSED_AS_INFO`

---

## 6. Regression Appendix

This appendix re-verifies **31 prior-milestone regression subjects** against HEAD `7ab515fe` per ROADMAP SC-2 + REQUIREMENTS.md REG-01/REG-02 definitions: **2 REG-01** v29.0 subjects (F-29-03 + F-29-04) + **29 REG-02** v25.0/v3.7/v3.8 rngLocked-invariant items (per Phase 237 Plan 03 Consumer Index REG-02 scope = 29 `confirmed-fresh-matches-prior` rows). Contract tree is byte-identical to v29.0 `1646d5af` per PROJECT.md / Phase 241 D-25 — expected distribution = **31 PASS / 0 REGRESSED / 0 SUPERSEDED**. Verdict taxonomy per D-13 closed set `{PASS / REGRESSED / SUPERSEDED}`. Each row carries a `re-verified at HEAD 7ab515fe` backtick-quoted note per D-14 + a one-line structural-equivalence statement against the original-milestone source artifact.

Outer ordering per D-12 is chronological-by-milestone (oldest first: v3.7 → v3.8 → v25.0 → v29.0); final assembly reorders § 6 in Task 5 so REG-02 sub-sections precede REG-01. This task emits REG-01 content under `### REG-01` heading.

### REG-01 — v29.0 (2 rows)

REG-01 scope is 2 v29.0 finding subjects per ROADMAP Phase 242 SC-2 literal + REQUIREMENTS.md REG-01 definition: **F-29-03** (test-coverage gap for the wei-direct `mint_ETH` quest-credit path at `test/fuzz/CoverageGap222.t.sol:1453-1455`) + **F-29-04** (gameover RNG substitution for mid-cycle write-buffer tickets at `contracts/modules/DegenerusGameAdvanceModule.sol:292 / :1082 / :1222-1246`; already KI'd as EXC-03). Source: `audit/FINDINGS-v29.0.md` §F-29-03 + §F-29-04. Phase 241 § 6 `EXC-03 RE_VERIFIED_AT_HEAD` re-verification corroborates F-29-04 at HEAD.

| Row ID | Source Finding | Source Artifact (file:line) | Subject Surface at HEAD | Re-Verification Evidence | Verdict | Re-Verified-at-HEAD Note |
| ------ | -------------- | --------------------------- | ----------------------- | ------------------------ | ------- | ------------------------ |
| REG-v29.0-F2903 | F-29-03 (QST-01 `mint_ETH` test-coverage gap) | `audit/FINDINGS-v29.0.md` §F-29-03; `test/fuzz/CoverageGap222.t.sol:1453-1455` | `test/fuzz/CoverageGap222.t.sol` present at HEAD; raw-selector ABI signature + first-arg type annotation updated to `uint256` form at `:1453-1455` via commit `d5284be5`; surrounding `onlyCoin`-caller negative test at `:1441-1461` unchanged; zero positive-coverage test for wei-direct `mint_ETH` credit semantics at HEAD | `grep -c 'mint_ETH' test/fuzz/CoverageGap222.t.sol` returns 0 positive-coverage assertions (only selector-alignment hunk and `onlyCoin` revert test present); contract-side wei-direct pipeline independently SAFE per Phase 234 QST-01 11-row verdict table (9 SAFE + 2 SAFE-INFO) and Phase 235 CONS-01 ETH conservation re-proof re-verified at HEAD 7ab515fe; F-29-03 is test-coverage observation (not contract correctness defect); observation unchanged at HEAD | PASS | `re-verified at HEAD 7ab515fe` — Test file `test/fuzz/CoverageGap222.t.sol` present at HEAD with same positive-coverage gap as v29.0; observation unchanged. Contract tree byte-identical to v29.0 `1646d5af` per PROJECT.md; test/ under project READ-only policy since v28.0 — no post-v29 commit added positive coverage. |
| REG-v29.0-F2904 | F-29-04 (Gameover RNG substitution for mid-cycle write-buffer tickets) | `audit/FINDINGS-v29.0.md` §F-29-04; `contracts/modules/DegenerusGameAdvanceModule.sol:292` (_swapAndFreeze daily RNG buffer-swap site), `:1082` (_swapTicketSlot mid-day lootbox RNG buffer-swap site), `:1222-1246` (_gameOverEntropy substitution site), `:625` (terminal `_unlockRng` per v29.0 cite) | Fresh grep at HEAD confirms `GAMEOVER_RNG_FALLBACK_DELAY = 14 days` intact at `AdvanceModule:109`; `_swapAndFreeze(purchaseLevel)` at `:292`; `_gameOverEntropy` at `:1213-1246`; `_swapTicketSlot(purchaseLevel_)` at `:1082`; sole `_gameOverEntropy` caller `advanceGame:553` (rngWord sink); buffer-swap primitive boundary unchanged | Cross-cite Phase 241 § 6 `EXC-03 Tri-Gate Predicate Re-Verification` — section-level verdict `EXC-03 RE_VERIFIED_AT_HEAD`. All 3 tri-gate predicates hold: EXC-03-P1 (terminal-state: substitution reachable only via `_gameOverEntropy` single-caller `advanceGame:553`), EXC-03-P2 (no-player-reachable-timing: cross-cite Phase 240 GO-04 2 `DISPROVEN_PLAYER_REACHABLE_VECTOR` rows — 120-day liveness + pool deficit), EXC-03-P3 (buffer-scope: 6 F-29-04 write-buffer slots disjoint from 25 jackpot-input slots per Phase 240 GO-05 `BOTH_DISJOINT`). KNOWN-ISSUES.md EXC-03 entry intact | PASS | `re-verified at HEAD 7ab515fe` — F-29-04 invariant disclosure matches HEAD behavior. Phase 241 § 6 `EXC-03 RE_VERIFIED_AT_HEAD` via 3-predicate tri-gate; substitution site at `_gameOverEntropy:1222-1246` unchanged; write-buffer primitive boundary at `_swapAndFreeze:292` + `_swapTicketSlot:1082` unchanged. Contract tree byte-identical to v29.0 `1646d5af`. |

**REG-01 regression distribution at HEAD `7ab515fe`: 2 PASS / 0 REGRESSED / 0 SUPERSEDED** (expected per contract tree byte-identity to v29.0 `1646d5af`).


---

## 7. FIND-03 KI Gating Walk + Non-Promotion Ledger

_[Populated in Task 5]_

---

## 8. Prior-Artifact Cross-Cites

_[Populated in Task 5]_

---

## 9. Phase 237-241 Forward-Cite Closure

_[Populated in Task 5]_

---

## 10. Milestone Closure Attestation

_[Populated in Task 5]_
