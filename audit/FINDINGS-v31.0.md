---
phase: 246-findings-consolidation-lean-regression-appendix
plan: 01
milestone: v31.0
milestone_name: Post-v30 Delta Audit + Gameover Edge-Case Re-Audit
head_anchor: cc68bfc7
audit_baseline: 7ab515fe
deliverable: audit/FINDINGS-v31.0.md
requirements: [REG-01, REG-02, FIND-01, FIND-02, FIND-03]
phase_status: terminal
write_policy: READ-only on the contract-and-test surface; writes confined to .planning/ and audit/FINDINGS-v31.0.md; KNOWN-ISSUES.md untouched unless FIND-03 promotes >=1 candidate per CONTEXT.md D-07 (default = UNMODIFIED)
supersedes: none
status: executing
generated_at: 2026-04-24T23:38:06Z
---

# v31.0 Findings — Post-v30 Delta Audit + Gameover Edge-Case Re-Audit

**Audit Baseline.** HEAD `cc68bfc7` — 5 commits above v30.0 baseline `7ab515fe` (12 files, 4 code-touching: `ced654df` JackpotTicketWin event scaling + `16597cac` rngunlock fix + `6b3f4f3c` quests recycled-ETH + `771893d1` gameover liveness-gate + sDGNRS redemption protection + `cc68bfc7` BAF-flip-gate addendum + `ffced9ef` docs-only). `git diff cc68bfc7..HEAD` over the contract-and-test surface is empty at every Task 1-6 boundary. Current git HEAD is `117da286` (docs-only commits above contract-tree HEAD `cc68bfc7`).

**Scope.** Single canonical milestone-closure deliverable for v31.0 per CONTEXT.md D-01 + D-13. Consolidates Phase 243-245 outputs into 9 sections per D-13 (v30 had 10 sections; v31 drops v30's §4 Dedicated Gameover-Jackpot Section which was Phase-240-specific). Terminal phase per CONTEXT.md D-17 / D-25 — zero forward-cites emitted to v32.0+.

**Write policy.** READ-only on the contract-and-test surface per CONTEXT.md D-20 + project feedback rules (`feedback_no_contract_commits.md`, `feedback_never_preapprove_contracts.md`). Zero modifications to upstream `audit/v31-243-DELTA-SURFACE.md` + `audit/v31-244-PER-COMMIT-AUDIT.md` + `audit/v31-245-SDR-GOE.md` (per D-21). `KNOWN-ISSUES.md` untouched per D-07 conditional-write rule (default path when FIND-03 promotes zero candidates; see §6).

---

## 2. Executive Summary

### Closure Verdict Summary

- FIND-01: `CLOSED_AT_HEAD_cc68bfc7`
- REG-01: `6 PASS / 0 REGRESSED / 0 SUPERSEDED` (5 F-30-NNN delta-touched candidates + F-29-04 explicitly NAMED per CONTEXT.md D-08; expected distribution per Phase 245 SDR-08-V01 + GOE-01-V01 + GOE-04-V02 RE_VERIFIED_AT_HEAD)
- REG-02: `0 PASS / 0 REGRESSED / 1 SUPERSEDED` (1 sDGNRS orphan-redemption window structurally closed by 771893d1 — pre-identified candidate per CONTEXT.md D-10 + D-11)
- FIND-02: `ASSEMBLED_COMBINED_REGRESSION_APPENDIX`
- FIND-03: `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`
- Combined milestone closure: `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`

### Severity Counts (per CONTEXT.md D-14 expected distribution)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-31-NN: 0

Phase 244 emitted 87 V-rows across 19 REQs (EVT 22 + RNG 20 + QST 24 + GOX 21) all SAFE floor severity with 0 finding candidates. Phase 245 emitted 55 V-rows across 14 REQs (SDR 40 + GOE 15) all SAFE floor severity with 0 finding candidates. Combined: 142 V-rows across 33 REQs all SAFE floor; 0 F-31-NN finding candidates surfaced. The F-31-NN finding-block section (§4) is therefore a one-paragraph zero-attestation prose block per CONTEXT.md D-13 with cross-cite to Phase 245 §5 zero-state subsection at audit/v31-245-SDR-GOE.md L1623-1637.

### D-05 5-Bucket Severity Rubric

Severity calibration mapped via the v30/v31 player-reachability × value-extraction × determinism-break frame inherited from v30 D-08 per CONTEXT.md D-05 carry.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

The rubric is published for completeness + future-reader benefit; FIND-02 has zero candidates to classify per the zero-finding-candidate input from Phase 244 + Phase 245.

### KI Gating Rubric Reference (per CONTEXT.md D-06 carry from v30 D-09)

The FIND-03 KI-eligibility 3-predicate test (D-06) is distinct from the D-05 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at zero finding candidates: `KNOWN-ISSUES.md` UNMODIFIED per D-07 default path (see §6 KI Gating Walk + Non-Promotion Ledger zero-row variant).

### Forward-Cite Closure Summary

CONTEXT.md D-25 terminal-phase rule: zero forward-cites emitted from Phase 246 to v32.0+. Verified at §8 Forward-Cite Closure block. Phase 244 → 245 + Phase 245 → 246 forward-cite discharge: 17/17 Phase 244 §Phase-245-Pre-Flag bullets (L2470-2521) CLOSED in Phase 245 (verified in §8a). Phase 245 → 246: 0 forward-cites emitted per Phase 245 §5 zero-state attestation (verified in §8b).

### Attestation Anchor

See §9 Milestone Closure Attestation for the CONTEXT.md D-18 6-point attestation block triggering v31.0 milestone closure.

---

## 3. Per-Phase Sections

Consolidates Phase 243 / 244 / 245 outputs per CONTEXT.md D-13 + D-16 into condensed summaries with cross-cites to source artifacts. All cross-cites are READ-only lookups (CONTEXT.md D-21); no fresh derivation. Sources `re-verified at HEAD cc68bfc7`.

### 3a. Phase 243 — Delta Extraction & Per-Commit Classification

**Change-count card:**
- Commits in scope: 5 (`ced654df` + `16597cac` + `6b3f4f3c` + `771893d1` + `cc68bfc7` BAF addendum) + `ffced9ef` docs-only enumerated for completeness
- Files: 14 (4 code-touching + 10 metadata/docs)
- Lines changed: +187 / -67
- Plans: 3 (243-01 DELTA-01 enumeration / 243-02 DELTA-02 classification / 243-03 DELTA-03 call-site catalog)
- Row counts: 42 D-243-C### changelog rows + 26 D-243-F### classification rows (2 NEW + 23 MODIFIED_LOGIC + 1 REFACTOR_ONLY + 0 DELETED + 0 RENAMED) + 60 D-243-X### call-site rows + 41 D-243-I### Consumer Index rows + 2 D-243-S### storage rows
- REQs satisfied: 3/3 (DELTA-01, DELTA-02, DELTA-03)
- Finding candidates: 0
- Severity floor: SCOPE-MAP only (Phase 243 is delta-extraction, not adversarial audit)

**Cross-cite:** `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only per CONTEXT.md D-21 carry from Phase 243 D-21).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | ------- | ---------- |
| DELTA-01 | COMPLETE_AT_HEAD_cc68bfc7 | `audit/v31-243-DELTA-SURFACE.md` Sections 0+1+4+5+§7.1+§7.1.b |
| DELTA-02 | COMPLETE_AT_HEAD_cc68bfc7 | `audit/v31-243-DELTA-SURFACE.md` Section 2 (26 D-243-F### rows) + Section 1 change-count cards + §7.2 |
| DELTA-03 | COMPLETE_AT_HEAD_cc68bfc7 | `audit/v31-243-DELTA-SURFACE.md` Sections 3+6+§7.3 (60 D-243-X### + 41 D-243-I### rows) |

Phase 243 produced the full delta-surface catalog at HEAD cc68bfc7 with all 26 changed functions classified + all 60 downstream call-sites enumerated + a 41-row Consumer Index mapping every v31.0 REQ to D-243-X/F/C/I/S rows. Phase 243 §6 Consumer Index drives REG-01 inclusion-rule mapping per CONTEXT.md D-08.

### 3b. Phase 244 — Per-Commit Adversarial Audit (EVT + RNG + QST + GOX)

**Change-count card:**
- Plans: 4 (244-01 EVT / 244-02 RNG / 244-03 QST / 244-04 GOX + FINAL CONSOLIDATION)
- Buckets: 4 (EVT-01..04 + RNG-01..03 + QST-01..05 + GOX-01..07 = 19 REQs)
- V-rows: 87 (EVT 22 + RNG 20 + QST 24 + GOX 21)
- REQs satisfied: 19/19 (all SAFE floor severity)
- INFO observations closed in-phase: 7 (NatSpec-disclosed surfaces + by-design RE_VERIFIED envelopes + direction-only bytecode commentary per CONTEXT.md Phase 244 D-14)
- Finding candidates: 0
- KI envelope re-verifications: EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 via GOX-04-V02
- Pre-Flag bullets emitted: 16 (consumed by Phase 245 as ADVISORY input per CONTEXT.md D-25)
- Final consolidation: `audit/v31-244-PER-COMMIT-AUDIT.md` (2,858 lines, FINAL READ-only)

**Cross-cite:** `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only per CONTEXT.md D-21). Working files preserved as appendices per Phase 244 D-05: `audit/v31-244-EVT.md` (394 lines) + `audit/v31-244-RNG.md` (447 lines) + `audit/v31-244-QST.md` (800 lines) + `audit/v31-244-GOX.md` (801 lines).

**Per-bucket summary:**

| Bucket | Commits | V-rows | REQs | Finding Candidates | Severity Floor | KI Re-Verify |
| ------ | ------- | ------ | ---- | ------------------ | -------------- | ------------ |
| EVT (Plan 244-01) | ced654df + cc68bfc7 BAF addendum | 22 | EVT-01..04 (4 REQs) | 0 | SAFE | — |
| RNG (Plan 244-02) | 16597cac | 20 | RNG-01..03 (3 REQs) | 0 | SAFE | — |
| QST (Plan 244-03) | 6b3f4f3c | 24 | QST-01..05 (5 REQs) | 0 | SAFE | — |
| GOX (Plan 244-04) | 771893d1 | 21 | GOX-01..07 (7 REQs) | 0 | SAFE | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 (GOX-04-V02) |

Per-bucket prose:

- **EVT:** Every JackpotTicketWin emit path proven to emit non-zero TICKET_SCALE-scaled ticketCount; new JackpotWhalePassWin emit covers the previously-silent large-amount odd-index BAF path; ticketCount uniformly TICKET_SCALE-scaled across BAF and trait-matched paths; event NatSpec accurate. Phase 243 §1.7 bullets 6+7 closed in 244-01; bullet 8 deferred-NOTE to 244-04 (closed in 244-04 GOX-06-V03 PRIMARY).
- **RNG:** `_unlockRng(day)` removal from two-call-split continuation proven SAFE — every reaching path enumerated; `rngLocked` clears elsewhere on same tick. v30.0 `rngLockedFlag` AIRTIGHT invariant RE_VERIFIED_AT_HEAD cc68bfc7. Reformat-only changes proven behaviorally equivalent. KI EXC-03 RE_VERIFIED_AT_HEAD via RNG-01-V11 (cited by Phase 245 SDR-08-V01 + GOE-01-V01 dual carriers as PRIMARY).
- **QST:** MINT_ETH quest progress + earlybird DGNRS counting proven correct on gross spend (fresh + recycled) with no double-counting. Affiliate fresh-vs-recycled 20-25/5 split byte-identical baseline vs HEAD per QST-03 NEGATIVE-scope gate. `_callTicketPurchase` return drop + `ethFreshWei → ethMintSpendWei` rename proven behaviorally equivalent. Gas-savings claim direction-only confirmed via BYTECODE-DELTA-ONLY methodology (DegenerusGameMintModule stripped body shrank by 36 bytes; DegenerusQuests stripped body byte-identical per REFACTOR_ONLY rename D-243-F007).
- **GOX:** All 8 purchase/claim paths moved from `gameOver` → `_livenessTriggered` enumerated (GOX-01); sDGNRS.burn + burnWrapped State-1 block closes orphan-redemption window (GOX-02-V01/V02); `handleGameOverDrain` subtracts pendingRedemptionEthValue BEFORE 33/33/34 split (GOX-03-V01); VRF-dead 14-day grace fallback proven (GOX-04 + EXC-02 RE_VERIFIED); `_gameOverEntropy` rngRequestTime clearing + gameover-before-liveness ordering proven (GOX-05 + GOX-06); DegenerusGameStorage slot layout verified via `forge inspect` (GOX-07 FAST-CLOSE).

**§Phase-243 §1.7 Pre-Flag bullet closure:** All 8/8 §1.7 INFO bullets CLOSED in-phase across the 4 buckets:
- bullets 1+2+4 → GOX-02-V01/V02 + GOX-03-V03
- bullet 3 → RNG-02-V04 PRIMARY + GOX-06-V01 DERIVED cross-cite
- bullet 5 → GOX-06-V02
- bullets 6+7 → 244-01 EVT-V0X
- bullet 8 → GOX-06-V03 PRIMARY closure

**§Phase-245 Pre-Flag emission:** 16 SDR/GOE observations emitted per CONTEXT.md Phase 244 D-16 as ADVISORY input to Phase 245.

### 3c. Phase 245 — sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification

**Change-count card:**
- Plans: 2 (245-01 SDR / 245-02 GOE + FINAL CONSOLIDATION)
- Buckets: 2 (SDR-01..08 + GOE-01..06 = 14 REQs)
- V-rows: 55 (SDR 40 + GOE 15)
- REQs satisfied: 14/14 (all SAFE floor severity)
- Finding candidates: 0
- KI envelope re-verifications:
  - **EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 at GOE-04-V02** (4×4 VRF vs prevrandao branch disjointness matrix under Tier-1 14-day grace; cross-cites Phase 244 GOX-04-V02 PRIMARY)
  - **EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 at SDR-08-V01 + GOE-01-V01** (dual carriers; full `_gameOverEntropy` scope; cross-cites Phase 244 RNG-01-V11 PRIMARY)
- Phase 244 §Phase-245-Pre-Flag closure: 17/17 Phase 244 Pre-Flag bullets CLOSED in-phase (10 SDR + 7 GOE) — zero rolled forward to Phase 246 per CONTEXT.md D-25
- Final consolidation: `audit/v31-245-SDR-GOE.md` (1636 lines, FINAL READ-only per CONTEXT.md Phase 245 D-05; 4 sections + §0 heatmap + §5 Phase-246-Input zero-state at L1623-1637)

**Cross-cite:** `audit/v31-245-SDR-GOE.md` (FINAL READ-only per CONTEXT.md D-21). Working files preserved as appendices per Phase 245 D-05: `audit/v31-245-SDR.md` (924 lines) + `audit/v31-245-GOE.md` (432 lines).

**Per-bucket summary:**

| Bucket | Commits | V-rows | REQs | Finding Candidates | Severity Floor | KI Re-Verify |
| ------ | ------- | ------ | ---- | ------------------ | -------------- | ------------ |
| SDR (Plan 245-01) | 771893d1 + cc68bfc7 surface | 40 (6 SDR-01-T{a-f} foundation + 34 standard) | SDR-01..08 (8 REQs) | 0 | SAFE | EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 (SDR-08-V01) |
| GOE (Plan 245-02) | pre-existing invariants vs delta | 15 | GOE-01..06 (6 REQs) | 0 | SAFE | EXC-02 RE_VERIFIED_AT_HEAD cc68bfc7 (GOE-04-V02) + EXC-03 RE_VERIFIED_AT_HEAD cc68bfc7 (GOE-01-V01) |

Per-bucket prose:

- **SDR:** Full redemption-state-transition × gameover-timing matrix enumerated across all 6 timings (a)-(f) — pre-liveness all three steps / VRF-pending crossings / post-gameOver request blocked / VRF-dead `_gameOverEntropy` fallback resolution. Per-wei conservation closed for every wei entering pendingRedemptionEthValue (exactly one exit, never both/neither). State-1 orphan-redemption window proven closed; sDGNRS supply conservation proven across full redemption lifecycle including gameover interception. `_gameOverEntropy` fallback substitution for VRF-pending redemptions (F-29-04 class) proven fair (no pending-limbo post-gameOver). Backward-trace + commitment-window methodology applied at SDR-08 per project skills.
- **GOE:** F-29-04 RNG-consumer determinism RE_VERIFIED at HEAD; v24.0 claimablePool 33/33/34 split + 30-day sweep re-verified against new pendingRedemptionEthValue subtraction; purchase-blocking entry-point coverage updated for liveness-gate shift (full external-function inventory at GOE-03 — 25+ entries gate-classified i/ii/iii beyond Phase 244 GOX-01 8-path primary); VRF vs prevrandao branch disjointness 4×4 matrix under 14-day grace; `gameOverPossible` BURNIE endgame gate (v11.0) re-verified across all new liveness paths. GOE-06 closes both Phase 244 Pre-Flag candidates SAFE (cc68bfc7 skipped-BAF-pool × handleGameOverDrain: skipped wei captured in totalFunds, not stranded; burnWrapped State-0/1/2 wrapper-backing conservation: storage-key separation preserves backing through burnAtGameOver per matched burn-pair invariant).

**§Phase-244 Pre-Flag bullet closure:** All 17/17 Phase 244 Pre-Flag bullets CLOSED in-phase (zero rolled forward to Phase 246):
- 10 SDR-grouped (L2477/2478/2481/2482/2485/2488/2491/2494/2497/2500)
- 7 GOE-grouped (L2503/2506/2509/2512/2515/2518/2519)

---

## 4. F-31-NN Finding Blocks

**F-31-NN: NONE** (sentinel header per CONTEXT.md D-13 Claude's Discretion grep-friendliness option).

Phase 244 (`audit/v31-244-PER-COMMIT-AUDIT.md` FINAL READ-only) emitted 87 verdict rows across 19 REQs (EVT 22 + RNG 20 + QST 24 + GOX 21) all SAFE floor severity with 0 finding candidates and 7 INFO observations all closed in-phase per CONTEXT.md Phase 244 D-14. Phase 245 (`audit/v31-245-SDR-GOE.md` FINAL READ-only) emitted 55 verdict rows across 14 REQs (SDR 40 + GOE 15) all SAFE floor severity with 0 finding candidates and zero INFO observations beyond the absorbed-SAFE claimRedemption gate per CONTEXT.md Phase 245 D-09. Combined across both phases: **142 verdict rows across 33 REQs all SAFE floor severity; 0 F-31-NN finding candidates surfaced.**

The Phase 246 FIND-01 finding-candidate pool is therefore **empty**. No `F-31-NN` IDs are assigned in this milestone deliverable. FIND-02 has no candidates to classify under the §2 D-05 5-bucket severity rubric. The §6 FIND-03 Non-Promotion Ledger is a zero-row variant per CONTEXT.md D-15.

The zero-attestation source is the Phase 245 §5 Phase-246-Input subsection at `audit/v31-245-SDR-GOE.md` L1623-1637 per CONTEXT.md Phase 245 D-18:

> Zero finding candidates emitted — Phase 246 FIND-01 pool from Phase 245 is empty; FIND-02 has no candidates to reclassify; FIND-03 KI delta is zero.

The terminal-phase rule (CONTEXT.md D-17 / D-25) is honored: zero forward-cites emitted from Phase 246 to v32.0+. Any finding candidate that surfaced post-Phase-245 closure (none did) would have routed to a `F-31-NN — TBD-v32` block with explicit rollover addendum per the Phase 245 → 246 hand-off contract; the rollover-addendum mechanism is documented for future-reader benefit but unused at HEAD `cc68bfc7`.

KI envelope re-verifications (EXC-02 + EXC-03 RE_VERIFIED_AT_HEAD `cc68bfc7` from Phase 245 SDR-08-V01 + GOE-01-V01 + GOE-04-V02 dual carriers) are **NOT** F-31-NN finding candidates and are **NOT** KI promotions per CONTEXT.md D-22. They confirm existing `KNOWN-ISSUES.md` entries' acceptance envelopes did not widen against the v31.0 deltas. They are documented in §6 KI Gating Walk as "envelope-non-widening attestations."

---

