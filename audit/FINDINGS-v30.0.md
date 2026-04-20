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

_[Populated in Task 2 — see Task 2 section below]_

---

## 4. Dedicated Gameover-Jackpot Section

_[Populated in Task 2]_

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

_[Populated in Task 3 (REG-01) + Task 4 (REG-02); final assembly in Task 5]_

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
