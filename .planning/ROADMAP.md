# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ✅ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (shipped 2026-04-15) — see [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md)
- ✅ **v29.0 Post-v27 Contract Delta Audit** — Phases 230-236 (shipped 2026-04-18) — see [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md)
- ✅ **v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit** — Phases 237-242 (shipped 2026-04-20) — see [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md)
- 🟢 **v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit** — Phases 243-246 (in progress, started 2026-04-23)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

<details>
<summary>✅ v27.0 Call-Site Integrity Audit (Phases 220-223) — SHIPPED 2026-04-13</summary>

- [x] Phase 220: Delegatecall Target Alignment (2/2 plans) — completed 2026-04-12
- [x] Phase 221: Raw Selector & Calldata Audit (2/2 plans) — completed 2026-04-12
- [x] Phase 222: External Function Coverage Gap (3/3 plans) — completed 2026-04-13
- [x] Phase 223: Findings Consolidation (2/2 plans) — completed 2026-04-13

</details>

<details>
<summary>✅ v28.0 Database & API Intent Alignment Audit (Phases 224-229) — SHIPPED 2026-04-15</summary>

- [x] Phase 224: API Route & OpenAPI Alignment (1/1 plans) — completed 2026-04-13
- [x] Phase 225: API Handler Behavior & Validation Schema Alignment (3/3 plans) — completed 2026-04-13
- [x] Phase 226: Schema, Migration & Orphan Audit (4/4 plans) — completed 2026-04-15
- [x] Phase 227: Indexer Event Processing Correctness (3/3 plans) — completed 2026-04-15
- [x] Phase 228: Cursor, Reorg & View Refresh State Machines (2/2 plans) — completed 2026-04-15
- [x] Phase 229: Findings Consolidation (2/2 plans) — completed 2026-04-15

**Findings:** 69 total (0 CRITICAL/HIGH/MEDIUM, 27 LOW, 42 INFO). See [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md) and [audit/FINDINGS-v28.0.md](../audit/FINDINGS-v28.0.md).

</details>

<details>
<summary>✅ v29.0 Post-v27 Contract Delta Audit (Phases 230-236) — SHIPPED 2026-04-18</summary>

- [x] Phase 230: Delta Extraction & Scope Map (1/1 plans) — completed 2026-04-17
- [x] Phase 231: Earlybird Jackpot Audit (3/3 plans) — completed 2026-04-17
- [x] Phase 232: Decimator Audit (3/3 plans) — completed 2026-04-18
- [x] Phase 232.1: RNG-Index Ticket Drain Ordering Enforcement (3/3 plans) — completed 2026-04-18
- [x] Phase 233: Jackpot/BAF + Entropy Audit (3/3 plans) — completed 2026-04-19
- [x] Phase 234: Quests / Boons / Misc Audit (1/1 plans) — completed 2026-04-19
- [x] Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition (5/5 plans) — completed 2026-04-18
- [x] Phase 236: Regression + Findings Consolidation (2/2 plans) — completed 2026-04-18

**Findings:** 4 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 32 prior findings re-verified (31 PASS + 1 SUPERSEDED + 0 REGRESSED). See [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md) and [audit/FINDINGS-v29.0.md](../audit/FINDINGS-v29.0.md).

</details>

<details>
<summary>✅ v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit (Phases 237-242) — SHIPPED 2026-04-20</summary>

- [x] Phase 237: VRF Consumer Inventory & Call Graph (3/3 plans) — completed 2026-04-19
- [x] Phase 238: Backward & Forward Freeze Proofs (3/3 plans) — completed 2026-04-19
- [x] Phase 239: rngLocked Invariant & Permissionless Sweep (3/3 plans) — completed 2026-04-19
- [x] Phase 240: Gameover Jackpot Safety (3/3 plans) — completed 2026-04-19
- [x] Phase 241: Exception Closure (1/1 plans) — completed 2026-04-19
- [x] Phase 242: Regression + Findings Consolidation (1/1 plans) — completed 2026-04-20

**Findings:** 17 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 31 prior findings re-verified (31 PASS + 0 REGRESSED + 0 SUPERSEDED). 0 of 17 candidates promoted to KNOWN-ISSUES.md (D-05 default path). See [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md) and [audit/FINDINGS-v30.0.md](../audit/FINDINGS-v30.0.md).

</details>

### v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit (Phases 243-246)

- [x] **Phase 243: Delta Extraction & Per-Commit Classification** — COMPLETE at HEAD `cc68bfc7` (all 3 plans closed 2026-04-23): single authoritative delta-surface catalog `audit/v31-243-DELTA-SURFACE.md` published with 42 changelog + 26 classification + 60 call-site + 41 Consumer-Index + 2 storage rows; FINAL READ-only per D-21
- [ ] **Phase 244: Per-Commit Adversarial Audit (EVT + RNG + QST + GOX)** — Audit every post-v30 code change adversarially against its commit-message behavior claim
- [ ] **Phase 245: sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification** — Prove every redemption path × gameover-timing matrix is fund-conserving and re-verify pre-existing gameover invariants against the new delta
- [ ] **Phase 246: Findings Consolidation + Lean Regression Appendix** — Publish `audit/FINDINGS-v31.0.md` and update `KNOWN-ISSUES.md` only if D-09 3-predicate gating passes

## Phase Details

### Phase 243: Delta Extraction & Per-Commit Classification
**Goal**: Establish the exact audit surface — every changed function, state variable, event, and downstream call site — for the 5 post-v30.0 commits, so per-commit adversarial audit has a complete, grep-reproducible target list
**Depends on**: Nothing (first phase of v31.0)
**Requirements**: DELTA-01, DELTA-02, DELTA-03
**Success Criteria** (what must be TRUE):
  1. Per-commit function/state/event inventory published covering all 5 commits (`ced654df`, `16597cac`, `6b3f4f3c`, `771893d1`, `ffced9ef`) with per-commit + aggregate counts — reviewer can reproduce via the documented `git diff` commands (DELTA-01)
  2. Every changed function labeled with one of {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}, with the diff hunk cited and hunk-level annotation attached — zero function is "unclassified" (DELTA-02)
  3. Every changed function's and interface's downstream call sites enumerated across `contracts/` via reproducible grep output — zero caller unaccounted for (DELTA-03)
  4. `.planning/phases/243-*/` artifacts committed + `audit/v31-243-DELTA-SURFACE.md` (or equivalent upstream file) published, referenced by Phase 244 plans as their sole scope input
**Plans:** 3 plans
Plans:
- [x] 243-01-PLAN.md — DELTA-01 enumeration wave 1 COMPLETE at 771893d1 (original pass) + cc68bfc7 (addendum pass): per-commit function/state/event/interface inventory + storage slot-layout diff + reproduction recipe (populated Sections 0/1/4/5/7.1 + 7.1.b)
- [x] 243-02-PLAN.md — DELTA-02 classification wave 2 COMPLETE at cc68bfc7 (commit `cfafebd8` + plan-close `cb91dfef`): D-04 5-bucket verdict per function with hunk citation + D-19 evidence burden (populated Section 2 + Section 1 change-count cards + §7.2; 2 NEW / 23 MODIFIED_LOGIC / 1 REFACTOR_ONLY / 0 DELETED / 0 RENAMED across 26 D-243-F rows)
- [x] 243-03-PLAN.md — DELTA-03 call-site catalog wave 2 COMPLETE at cc68bfc7 (commit `87e68995`): grep-reproducible downstream call sites + Consumer Index + final READ-only lock (populated Sections 3/6/§7.3 and flipped file status to FINAL; 60 D-243-X + 41 D-243-I rows)

### Phase 244: Per-Commit Adversarial Audit (EVT + RNG + QST + GOX)
**Goal**: Adversarially audit every contract code change in the 5 post-v30 commits against its commit-message behavior claim — surface every finding candidate (SAFE / INFO / LOW / MEDIUM / HIGH / CRITICAL) before Phase 245/246 consolidation
**Depends on**: Phase 243
**Requirements**: EVT-01, EVT-02, EVT-03, EVT-04, RNG-01, RNG-02, RNG-03, QST-01, QST-02, QST-03, QST-04, QST-05, GOX-01, GOX-02, GOX-03, GOX-04, GOX-05, GOX-06, GOX-07
**Success Criteria** (what must be TRUE):
  1. Every `JackpotTicketWin` emit path proven to emit non-zero `TICKET_SCALE`-scaled `ticketCount`, with the new `JackpotWhalePassWin` emit proven to cover the previously-silent large-amount odd-index BAF path and event NatSpec proven accurate (EVT-01..EVT-04)
  2. `_unlockRng(day)` removal from the two-call-split continuation proven safe — every reaching path enumerated and shown to clear `rngLocked` elsewhere on the same tick; v30.0 `rngLockedFlag` AIRTIGHT invariant RE_VERIFIED_AT_HEAD `771893d1`; reformat-only sub-change proven behaviorally equivalent (RNG-01..RNG-03)
  3. `MINT_ETH` quest progress + earlybird DGNRS counting proven correct on gross spend (fresh + recycled) with no double-counting; affiliate fresh-vs-recycled 20-25/5 split proven preserved; `_callTicketPurchase` return drop + `ethFreshWei → ethMintSpendWei` rename proven behaviorally equivalent; gas-savings claim (-142k/-153k/-76k WC) either reproduced or flagged INFO-unreproducible (QST-01..QST-05)
  4. All 8 purchase/claim paths moved from `gameOver` → `_livenessTriggered` enumerated and shown consistent with existing ticket-queue guards; `sDGNRS.burn`/`burnWrapped` State-1 block proven to close the orphan-redemption window; `handleGameOverDrain` proven to subtract `pendingRedemptionEthValue` BEFORE the 33/33/34 split; VRF-dead 14-day grace fallback + `_gameOverEntropy` `rngRequestTime` clearing + gameover-before-liveness ordering in `_handleGameOverPath` all proven correct; `DegenerusGameStorage.sol` (+27 lines) slot-layout change verified via `forge inspect` (GOX-01..GOX-07)
  5. Every audited REQ receives a closed per-commit verdict {SAFE / INFO / LOW / MEDIUM / HIGH / CRITICAL} with evidence — all finding candidates surfaced into the v31.0 candidate pool before Phase 246 consolidation
**Plans**: 4 plans, single-wave parallel per 244-CONTEXT.md D-01/D-02
Plans:
- [x] 244-01-PLAN.md — EVT bucket (ced654df + cc68bfc7 BAF-coupling addendum per D-03): EVT-01/EVT-02/EVT-03/EVT-04 closed at cc68bfc7 with 22 V-rows (5+5+8+4) across 4 REQs; 19 SAFE + 7 INFO; 0 finding candidates; 1.7 bullets 6 + 7 closed per CONTEXT.md D-09; bullet 8 deferred-NOTE to 244-02/244-04. Working file: `audit/v31-244-EVT.md`. Commits: `61e5f1b9` (Task 1) + `4b714a84` (Task 2)
- [ ] 244-02-PLAN.md — RNG bucket (16597cac): RNG-01/RNG-02/RNG-03
- [ ] 244-03-PLAN.md — QST bucket (6b3f4f3c): QST-01..QST-05
- [ ] 244-04-PLAN.md — GOX bucket (771893d1) + consolidation into `audit/v31-244-PER-COMMIT-AUDIT.md`: GOX-01..GOX-07

### Phase 245: sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification
**Goal**: Prove the sDGNRS redemption lifecycle × gameover-timing matrix is fund-conserving with hard guarantees (every redemption path works as intended, no funds lost, math closes exactly), AND re-verify every pre-existing gameover invariant (v24.0 / v29.0) still holds against the new liveness-gate + `pendingRedemptionEthValue` drain-subtraction delta
**Depends on**: Phase 243 (delta surface), Phase 244 (per-commit verdicts inform interaction-surface entries)
**Requirements**: SDR-01, SDR-02, SDR-03, SDR-04, SDR-05, SDR-06, SDR-07, SDR-08, GOE-01, GOE-02, GOE-03, GOE-04, GOE-05, GOE-06
**Success Criteria** (what must be TRUE):
  1. Full redemption-state-transition × gameover-timing matrix enumerated across all six timings (a)-(f) from SDR-01 (pre-liveness all three steps / VRF-pending crossings / post-gameOver request blocked / VRF-dead `_gameOverEntropy` fallback resolution) — every cell closed with a named verdict (SDR-01)
  2. `pendingRedemptionEthValue` accounting proven exact at every entry/exit (request → resolve → claim or fail-roll return) with zero dust and zero overshoot, AND `handleGameOverDrain` proven to subtract the full `pendingRedemptionEthValue` BEFORE the 33/33/34 claimable split (SDR-02, SDR-03)
  3. Per-wei conservation closed for every wei entering `pendingRedemptionEthValue`: exactly one exit (to claimer OR back to pool) under every gameover timing — never both, never neither. `claimRedemption` post-gameOver proven DOS-free, starvation-free, underflow-free, and race-free vs the 30-day sweep (SDR-04, SDR-05)
  4. State-1 orphan-redemption window proven closed (sDGNRS.burn + burnWrapped block covers every reachable creator path), sDGNRS supply conservation proven across the full redemption lifecycle including gameover interception, and `_gameOverEntropy` fallback substitution (F-29-04 class) proven fair for VRF-pending redemptions with no pending-limbo post-gameOver (SDR-06, SDR-07, SDR-08)
  5. Every pre-existing gameover invariant RE_VERIFIED_AT_HEAD `771893d1`: F-29-04 RNG-consumer determinism; v24.0 claimablePool 33/33/34 split + 30-day sweep; purchase-blocking entry-point coverage (updated for liveness-gate shift); VRF-available vs prevrandao fallback gameover-jackpot branches given the new 14-day grace; `gameOverPossible` BURNIE endgame gate (v11.0) (GOE-01..GOE-05)
  6. Any cross-feature emergent behavior introduced by the liveness-gate × sDGNRS-redemption × `pendingRedemptionEthValue`-drain-subtraction interaction enumerated exhaustively — either closed with verdict or surfaced as finding candidate for Phase 246 (GOE-06)
**Plans**: TBD

### Phase 246: Findings Consolidation + Lean Regression Appendix
**Goal**: Publish `audit/FINDINGS-v31.0.md` as the milestone deliverable with executive summary, per-phase sections, F-31-NN finding blocks under the D-08 5-bucket severity rubric, and a LEAN regression appendix (only prior findings directly touched by the deltas — not the full v30.0 31-row sweep); promote to `KNOWN-ISSUES.md` only items passing D-09 3-predicate gating
**Depends on**: Phase 243, Phase 244, Phase 245 (terminal phase; consolidates all prior output)
**Requirements**: FIND-01, FIND-02, FIND-03, REG-01, REG-02
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v31.0.md` published in v29/v30 shape — executive summary, per-phase sections, F-31-NN finding blocks, milestone-close attestation at HEAD `771893d1` (or current HEAD at phase-close) (FIND-01)
  2. Every finding classified under the D-08 5-bucket severity rubric {CRITICAL, HIGH, MEDIUM, LOW, INFO} with justification — zero finding is severity-unlabeled (FIND-02)
  3. `KNOWN-ISSUES.md` either updated with new accepted-design entries that pass D-09 3-predicate gating (accepted-design + non-exploitable + sticky) OR explicitly left UNMODIFIED per D-16 default path — the Non-Promotion Ledger lists every candidate that failed gating with the failing predicate identified (FIND-03)
  4. Lean regression appendix published: every v30.0 F-30-NNN or prior finding directly touched by the 5 in-scope deltas spot-checked, F-29-04 RE_VERIFIED_AT_HEAD, and any prior finding superseded by the new code explicitly marked SUPERSEDED with citation. The full v30.0 31-row sweep is NOT re-run per milestone scope decision (REG-01, REG-02)
  5. D-25 terminal-phase rule honored — zero forward-cites emitted; any finding that cannot close in v31.0 routes to an F-31-NN block with explicit rollover addendum or is closed via regression verdict

**Plans**: TBD

## Progress

**Execution Order:** Phase 243 first (delta surface foundation). Phase 244 depends on 243. Phase 245 depends on 243 (delta surface) and 244 (candidate verdicts). Phase 246 is terminal and depends on 243/244/245. Phases 244 and 245 may partially overlap once 243 lands (SDR/GOE plans in 245 can begin against the Phase 243 surface without waiting on every Phase 244 verdict — SDR interaction points are statically enumerable from the delta surface + 244 verdicts merge in during consolidation).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 243. Delta Extraction & Per-Commit Classification | 3/3 | Complete | 2026-04-23 |
| 244. Per-Commit Adversarial Audit (EVT + RNG + QST + GOX) | 0/? | Not started | — |
| 245. sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification | 0/? | Not started | — |
| 246. Findings Consolidation + Lean Regression Appendix | 0/? | Not started | — |

Plan counts will be filled in as each phase is planned via `/gsd-plan-phase N`.
