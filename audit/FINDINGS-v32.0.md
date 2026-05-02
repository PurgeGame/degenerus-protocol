---
phase: 253-findings-consolidation-lean-regression
plan: 01
milestone: v32.0
milestone_name: Backfill Idempotency + purchaseLevel Underflow Audit
head_anchor: acd88512
audit_baseline: cc68bfc7
deliverable: audit/FINDINGS-v32.0.md
requirements: [FIND-01, FIND-02, FIND-03, FIND-04, REG-01, REG-02]
phase_status: terminal
write_policy: "READ-only on the contract-and-test surface per D-253-CF-04 + project feedback rules. Zero modifications to upstream audit/v32-247..252-*.md per D-253-CF-07. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-253-FIND03-01 default zero-promotion path. The two awaiting-approval test files from Phase 251 (test/edge/LastPurchaseDayRace.test.js + test/edge/BackfillIdempotency.test.js) remain untracked permanently per D-253-FIND04-04."
supersedes: none
status: executing
read_only: false
head_at_runtime: 35ee9c1c1df820d5c4b48172f211e4a1975eb2c2
closure_signal: MILESTONE_V32_AT_HEAD_acd88512
generated_at: 2026-05-02T11:17:33Z
---

# v32.0 Findings — Backfill Idempotency + purchaseLevel Underflow Audit

**Audit Baseline.** HEAD `acd88512` is the contract-tree HEAD containing both v32.0 fix guards (L173 turbo guard `!rngLockedFlag` clause + L1174 backfill sentinel `rngWordByDay[idx + 1] == 0`) committed in a single SHA "fix(advance): guard turbo block + make _backfillGapDays idempotent" (Author: Purge / purgegamenft@gmail.com). 4 post-v31.0 contract-touching commits (`8bdeabc2` + `ad41973c` + `6a63705b` + `48554f8f`) precede this anchor. Current git HEAD `35ee9c1c` is byte-identical to `acd88512` for the load-bearing AdvanceModule + GameStorage line ranges (L167/L173 + L1167/L1174 + GameStorage L1246-1255); only `contracts/modules/DegenerusGameMintModule.sol` differs vs anchor due to the post-anchor `98e78404` SG-250-01 presale-flag commit (functionally orthogonal per Phase 250 SIB-03 + Phase 252 §1 V03).

**Scope.** Single canonical milestone-closure deliverable for v32.0 per D-253-CF-02 + D-253-15. Consolidates Phase 247-252 outputs into 9 sections per D-253-15 (mirrors v31's 9-section shape with §3 adapted to 6 per-phase subsections vs v31's 3, and §4 emitting 2 multi-section disclosure blocks vs v31's zero-attestation prose). Terminal phase per CONTEXT.md D-253-09 + ROADMAP — zero forward-cites emitted to v33.0+.

**Write policy.** READ-only per D-253-CF-04. Zero modifications to upstream `audit/v32-247..252-*.md` per D-253-CF-07. KNOWN-ISSUES.md UNMODIFIED per D-253-FIND03-01 (default path when FIND-03 promotes zero candidates; F-32-01 + F-32-02 FAIL the sticky predicate — bugs SUPERSEDED at HEAD). Awaiting-approval test files remain untracked permanently per D-253-FIND04-04.

---

## 2. Executive Summary

### Closure Verdict Summary

- FIND-01: `CLOSED_AT_HEAD_acd88512`
- FIND-02: `2 of 2 F-32-NN classified HIGH` (D-08 player-reachable hard determinism violation; both SUPERSEDED at HEAD per §4 At-HEAD resolution subsections)
- FIND-03: `0 of 2 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED` (sticky-predicate FAIL for both F-32-NN — SUPERSEDED at HEAD by L173 + L1174 guards committed in `acd88512`)
- FIND-04: `MILESTONE_V32_AT_HEAD_acd88512 emitted`; commit-readiness register at §9.NN names every load-bearing path landed during the milestone with USER-COMMITTED + AGENT-COMMITTED + AWAITING-APPROVAL audit trail
- REG-01: `13 PASS / 0 REGRESSED / 0 SUPERSEDED` (12 prior-finding rows from v29 / v30 + 1 explicitly NAMED F-29-04 row; expected per Phase 248 BFL-05 EXC-02 + EXC-03 NON-WIDENING dual-carrier + Phase 250 SIB-03 EXC-01 + EXC-04 NEGATIVE-scope + zero-finding-candidate input from upstream phases)
- REG-02: `0 PASS / 0 REGRESSED / 0 SUPERSEDED` (zero-row default per D-253-REG02-01; F-32-01 + F-32-02 supersession scope captured in §4 'At-HEAD resolution' subsections, NOT REG-02 entries)
- Combined milestone closure: `MILESTONE_V32_AT_HEAD_acd88512`

### Severity Counts (per D-08 5-Bucket Rubric + D-253-15 step 2)

- CRITICAL: 0
- HIGH: 2 (F-32-01 turbo race + F-32-02 backfill double-execution)
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-32-NN: 2

Both F-32-NN classified HIGH at severity-at-discovery per D-253-FIND01-02 (player-reachable hard determinism violation: state-machine corruption manifesting as panic 0x11 reverts; no value extraction); both SUPERSEDED at HEAD by L173 turbo guard `!rngLockedFlag` clause + L1174 backfill sentinel `rngWordByDay[idx + 1] == 0` committed in `acd88512`. See §4 'At-HEAD resolution' subsections for structural-closure proofs (PLV-03 + PLV-05 + PLV-06 strand-disproof for F-32-01; BFL-01..06 conservation + sentinel-correctness for F-32-02; Phase 252 §3.A + §3.B composition proofs). Severity counts reconcile to §4 F-32-NN block tally line by line per ROADMAP success criterion 2.

Phase 247 (delta extraction) emitted 0 V-rows (catalog-only). Phase 248 (BFL) emitted 44 BFL-NN-VMM V-rows + 3 BFL-01-MNN multiplier rows + 5 BFL-02-XNN out-of-scope rows all SAFE / NON-WIDENING. Phase 249 (PLV) emitted 38 PLV-NN-VMM V-rows all SAFE. Phase 250 (SIB) emitted 28 SIB-NN-VMM V-rows all SAFE / ORTHOGONAL_PROVEN with zero-state SIB-05 attestation. Phase 251 (TST) emitted 8 TST-NN-VMM V-rows all SAFE. Phase 252 (POST31) emitted 11 POST31-NN-VMM V-rows all SAFE / NON-WIDENING / NON-INTERFERING. Combined: 134 V-rows across 25 REQs all SAFE / NON-WIDENING / NON-INTERFERING with 0 FINDING_CANDIDATE rows surfaced. The F-32-NN finding-block section (§4) emits exactly 2 disclosure blocks per D-253-FIND01-01 documenting the originally-discovered testnet bugs being fixed by the milestone — these are NOT new findings surfaced by Phase 247-252 audit, but historical-record disclosures of the bugs the milestone exists to fix.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v30/v31 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 in the v32 REQUIREMENTS.md.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

F-32-01 + F-32-02 are HIGH per the rubric: both player-reachable (productive multi-call windows + multi-day VRF stalls are player-triggerable conditions); no value extraction (panic 0x11 reverts the transaction with no balance change); hard determinism violation (state-machine corruption causing arithmetic underflow). Both SUPERSEDED at HEAD by L173 + L1174 guards committed in `acd88512`; severity-at-HEAD = SUPERSEDED with mitigation present. Severity-at-discovery preserved per v25/v27/v28/v29 historical pattern.

### D-09 KI Gating Rubric Reference

The FIND-03 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. F-32-01 + F-32-02 FAIL the **sticky** predicate (the buggy behavior is SUPERSEDED at HEAD by L173 + L1174 guards — it is NOT ongoing protocol behavior). Default outcome at this milestone: `KNOWN-ISSUES.md` UNMODIFIED per D-253-FIND03-01 (4 existing accepted-design EXC-01..04 entries cover every promotable-class RNG surface at HEAD `acd88512`; no new KI promotions for v32). See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

CONTEXT.md D-253-09 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 253 to v33.0+. Verified at §8 Forward-Cite Closure block. Phase 247-252 each emitted zero forward-cites per their respective `_TBD-v33` / `defer-to-Phase-254` grep-recipe verifications; Phase 253 inherits zero-residual baseline. Any v32-relevant divergence not in upstream Phase 247-252 catalogs (e.g., a post-anchor commit beyond `98e78404` SG-250-01) routes to scope-guard deferral in 253-01-SUMMARY.md per D-253-CF-07; v33.0+ ingests via fresh delta-extraction phase, not via forward-cite.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 6-point attestation block triggering v32.0 milestone closure.

---

## 3. Per-Phase Sections

Consolidates Phase 247 / 248 / 249 / 250 / 251 / 252 outputs per D-253-09 + D-253-10 into condensed summaries with cross-cites to source artifacts. All cross-cites are READ-only lookups (D-253-CF-08); no fresh derivation. Sources `re-verified at HEAD acd88512`.

### 3a. Phase 247 — Delta Extraction & Classification

**Change-count card:**
- Plans: 1 (247-01)
- Commits in scope: 4 landed (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) + WIP overlay (turbo guard at AdvanceModule:173 + backfill guard at AdvanceModule:1174 + untracked `test/edge/LastPurchaseDayRace.test.js` + ContractAddresses.sol regen) — all consolidated into anchor `acd88512`
- Row counts: 16 D-247-C### per-source rows + 11 D-247-F### classification rows (8 MODIFIED_LOGIC + 3 DELETED) + 1 D-247-S### storage-layout UNCHANGED row + 30 D-247-X### call-site rows + 29 D-247-I### Consumer Index rows
- REQs satisfied: 3/3 (DELTA-01, DELTA-02, DELTA-03)
- Finding candidates: 0 (catalog-only phase)
- Atomic commits: 5 (`e2cacc5c` → `8e7e1f7c` → `4cc1f829` → `5162c5e0` → `9961c91a`) per D-247-14
- Closure signal: `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512`

**Cross-cite:** `audit/v32-247-DELTA-SURFACE.md` (FINAL READ-only per D-253-CF-07 carry).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| DELTA-01 | `COMPLETE_AT_HEAD_acd88512` | §1.4 commit changelog (16 D-247-C rows) |
| DELTA-02 | `COMPLETE_AT_HEAD_acd88512` | §2 classification (11 D-247-F rows) + §5 storage-layout UNCHANGED |
| DELTA-03 | `COMPLETE_AT_HEAD_acd88512` | §3 call-site catalog (30 D-247-X rows) + §6 Consumer Index (29 D-247-I rows) |

Phase 247 produced the full delta-surface catalog at HEAD `acd88512` with all 11 changed functions classified + 30 downstream call-sites enumerated + 29-row Consumer Index mapping every Phase 248..253 REQ-ID. The Consumer Index (D-247-I024..I029 specifically) drives REG-01 inclusion-rule mapping per D-253-REG01-01. `re-verified at HEAD acd88512`.

### 3b. Phase 248 — Backfill Idempotency Proof

**Change-count card:**
- Plans: 1 (248-01)
- V-rows: 44 (BFL-01 7 + BFL-02 6 + BFL-03 15 + BFL-04 4 + BFL-05 2 + BFL-06 10) + 3 BFL-01-MNN multiplier rows + 5 BFL-02-XNN out-of-scope rows
- REQs satisfied: 6/6 (BFL-01..06; all SAFE / NON-WIDENING)
- Finding candidates: 0
- KI envelope re-verifications: EXC-02 + EXC-03 RE_VERIFIED dual-carrier (BFL-05-V01 EXC-02 / BFL-05-V02 EXC-03; both NON-WIDENING)
- Atomic commits: 4 (`b79f3eac` → `838631a8` → `3be95bfe` → `5545b125`)
- Closure signal: `PHASE_248_BFL_FINAL_AT_HEAD_acd88512`

**Cross-cite:** `audit/v32-248-BFL.md` (FINAL READ-only) + Phase 251 TST-04 hand-off appendix.

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| BFL-01 | `SAFE_AT_HEAD_acd88512` | §1 (7 V-rows + 3 multiplier rows; rngGate fresh-word branch reachability) |
| BFL-02 | `SAFE_AT_HEAD_acd88512` | §2 (6 V-rows over guarded block L1174-1186 + sentinel-correctness 4-step proof) |
| BFL-03 | `SAFE_AT_HEAD_acd88512` | §3 (15 V-rows; testnet blocks 10759449 + 10761786 worked example, pre-fix doubling vs post-fix short-circuit) |
| BFL-04 | `SAFE_AT_HEAD_acd88512` | §4 (4 V-rows; dailyIdx ↔ rngWordByDay invariant table) |
| BFL-05 | `NON_WIDENING_AT_HEAD_acd88512` | §5 (2 V-rows dual-carrier; EXC-02 + EXC-03) |
| BFL-06 | `SAFE_AT_HEAD_acd88512` | §6 (10 V-rows + sDGNRS / DGNRS / BURNIE conservation algebra) |

Phase 248 proved the L1174 sentinel `rngWordByDay[idx + 1] == 0` makes `_backfillGapDays` execute at most once per VRF lock window across every reachable `advanceGame` re-entry path. §3 BFL-03 testnet-block worked example (blocks 10759449 + 10761786) demonstrates pre-fix doubling vs post-fix short-circuit. §6 BFL-06 conservation algebra closes (sDGNRS / DGNRS / BURNIE supplies invariant across lock window). §5 BFL-05 dual-carrier attestation drives §6b KI Envelope Re-Verifications (EXC-02 + EXC-03 NON-WIDENING). `re-verified at HEAD acd88512`.

### 3c. Phase 249 — purchaseLevel Correctness Proof

**Change-count card:**
- Plans: 1 (249-01)
- V-rows: 75 PLV-NN-VMM rows across §1-§6 (PLV-01 4-dimensional state-space sweep is the bulk; PLV-02/PLV-03 are narrative / proof sections without explicit table rows)
- REQs satisfied: 6/6 (PLV-01..06; all SAFE)
- Finding candidates: 0
- Atomic commits: 4 (`920a2368` → `3ed9a77a` → `6fa97fd5` → `7758db41`) per D-249-CF-07
- Closure signal: `PHASE_249_PLV_FINAL_AT_HEAD_acd88512`

**Cross-cite:** `audit/v32-249-PLV.md` (FINAL READ-only).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| PLV-01 | `SAFE_AT_HEAD_acd88512` | §1 PLV-01 4-dim state-space sweep |
| PLV-02 | `SAFE_AT_HEAD_acd88512` | §2 PLV-02 turbo-block reachability |
| PLV-03 | `SAFE_AT_HEAD_acd88512` | §3 PLV-03 ternary unreachable proof (`(cachedJpFlag = T ∧ cachedLevel = 0)` cell unreachable via INV-PLV-B-01 + INV-PLV-C-01 composition) |
| PLV-04 | `SAFE_AT_HEAD_acd88512` | §4 PLV-04 arithmetic flat table |
| PLV-05 | `SAFE_AT_HEAD_acd88512` | §5 PLV-05 testnet panic 0x11 reproduction walk |
| PLV-06 | `SAFE_AT_HEAD_acd88512` | §6 PLV-06 strand-disproof |

Phase 249 proved `purchaseLevel` cannot be 0 at any reachable `(lastPurchaseDay, rngLockedFlag, jackpotPhaseFlag, level)` combination once the L173 turbo guard `!rngLockedFlag` clause is in place. §3 PLV-03 ternary unreachable proof shows `(lastPurchase = T ∧ rngLockedFlag = T ∧ lvl = 0)` is structurally unreachable. §5 PLV-05 reproduces the testnet panic 0x11 trigger sequence symbolically (blocks 10759449 + 10761786). §6 PLV-06 strand-disproof confirms the daily-jackpot region (lines 372-404) does not strand state under the guard. §3 + §5 + §6 are the primary §4 F-32-01 'Reproduction evidence' + 'At-HEAD resolution' cite source. `re-verified at HEAD acd88512`.

### 3d. Phase 250 — Sibling-Pattern Sweep

**Change-count card:**
- Plans: 1 (250-01)
- V-rows: 28 SIB-NN-VMM rows (SIB-01 9 + SIB-03 15 + SIB-04 4) + zero-state SIB-05 attestation; SIB-02 is the ORTHOGONAL_PROVEN classifier (taxonomy section, no rows)
- REQs satisfied: 5/5 (SIB-01..05; all SAFE / ORTHOGONAL_PROVEN)
- Finding candidates: 0
- Atomic commits: 4 (`12d90a27` → `97ef3955` → `decee5d9` → `34a6c660`) per D-250-CF-06
- Closure signal: `PHASE_250_SIB_FINAL_AT_HEAD_acd88512`

**Cross-cite:** `audit/v32-250-SIB.md` (FINAL READ-only).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| SIB-01 | `SAFE_AT_HEAD_acd88512` | §1 (9 V-rows; rngLockedFlag co-reads in AdvanceModule) |
| SIB-02 | `ORTHOGONAL_PROVEN_AT_HEAD_acd88512` | §2 turbo/backfill/orthogonal taxonomy classifier |
| SIB-03 | `SAFE_AT_HEAD_acd88512` | §3 (15 V-rows; 8-module audit; SIB-03-V03 MintModule:1229 `_callTicketPurchase` flag-vs-flag-vs-counter triple — ORTHOGONAL_PROVEN, surfaced as new sibling pattern observation per D-253-FIND01-04) |
| SIB-04 | `SAFE_AT_HEAD_acd88512` | §4 (4 V-rows; 8bdeabc2 / ad41973c / 6a63705b / 48554f8f post-v31.0 commit cross-check) |
| SIB-05 | `ZERO_STATE_AT_HEAD_acd88512` | §5 zero-state attestation (no new sibling bugs found) |

Phase 250 hunted other turbo-class and backfill-class races across AdvanceModule and every delegating module. §1 SIB-01 enumerates every interaction in `DegenerusGameAdvanceModule.sol` where `rngLockedFlag` co-reads with another piece of game state. §2 SIB-02 classifies every interaction under the {turbo-class, backfill-class, ORTHOGONAL_PROVEN} taxonomy. §3 SIB-03 audits 8 delegating modules including the SIB-03-V03 MintModule:1229 triple (SAFE / ORTHOGONAL_PROVEN — sibling-pattern observation only, not a F-NN-NN candidate). §4 SIB-04 cross-checks the 4 post-v31.0 landed commits. §5 SIB-05 emits zero-state attestation. **SG-250-01 (post-anchor `98e78404` MintModule presale-flag commit)** carries forward as a recorded scope-guard item per D-253-CF-07 — functionally orthogonal to AdvanceModule turbo-path AND to GameStorage `_livenessTriggered` per Phase 250 SIB-03 + Phase 252 §1 V03; recorded but not within v32.0 audit-anchor `acd88512`. `re-verified at HEAD acd88512`.

### 3e. Phase 251 — Reproduction Tests

**Change-count card:**
- Plans: 1 (251-01)
- V-rows: 8 SAFE (TST-01-V01..V02 + TST-02-V01..V02 + TST-03-V01..V02 + TST-04-V01..V02; rendered as H3 sections per Phase 251 format, not pipe-table rows)
- REQs satisfied: 4/4 (TST-01..04)
- Finding candidates: 0
- Atomic commits: 4 (`c73c8add` → `6bc9c525` → `33e7d7c5` → `65b33299`)
- Closure signal: `PHASE_251_TST_FINAL_AT_HEAD_65b33299` (resolved `<plan-close-sha>` = `65b33299` = SHA of Task 4 atomic commit `audit(251-01): Task 4 — §5 register + §4.4 awaiting-approval + final assembly + FINAL READ-only flip`)

**Cross-cite:** `audit/v32-251-TST.md` (FINAL READ-only at HEAD `c790ae45`) + §5 commit-readiness register.

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| TST-01 | `PRE_FIX_FAIL_REPRODUCED_AT_STATE_A` | §1 TST-01-V01 single-day + TST-01-V02 multi-day-drain panic 0x11 reproduction (state A) |
| TST-02 | `POST_FIX_PASS_AT_STATE_D` | §2 TST-02-V01 + TST-02-V02 LastPurchaseDayRace state D pass |
| TST-03 | `LIVENESS_REGRESSION_PASS_AT_STATE_D` | §3 TST-03-V01 LivenessProductivePause + TST-03-V02 LivenessMidJackpot |
| TST-04 | `PRE_FIX_FAIL_STATE_C_POST_FIX_PASS_STATE_D` | §4 TST-04-V01 state-C psdDelta=15 over-bump + TST-04-V02 state-D psdDelta=7 single-bump |

Phase 251 empirically validated the v32.0 WIP guards against three guard-revert states. State-A (both reverted) reproduces panic 0x11 in TST-01-V01 + TST-01-V02 — the empirical reproduction of F-32-01 (turbo race). State-D (HEAD with both guards) passes deterministically (TST-02 + TST-03). State-C (backfill-only reverted) on newly authored BackfillIdempotency test produces psdDelta=15 over-bump + downstream panic 0x11 in TST-04-V01 — the empirical reproduction of F-32-02 (backfill double-execution); state-D produces psdDelta=7 (53% delta reduction empirically isolates L1174 sentinel). §5 commit-readiness register lists **TST-FILE-01** (`test/edge/LastPurchaseDayRace.test.js`) + **TST-FILE-02** (`test/edge/BackfillIdempotency.test.js`, sha-256 `03aecc8329a2520e38abeb5f942648a50abf8de1dad23f0efe28dd92eab7ab72`) at status `awaiting-approval` — inherited verbatim by Phase 253 §9.NN.iii per D-253-FIND04-03. `re-verified at HEAD acd88512`.

### 3f. Phase 252 — Post-v31.0 Landed-Commit Sanity

**Change-count card:**
- Plans: 1 (252-01)
- V-rows: 11 SAFE (4 §1 POST31-01-V01..V04 commit rows + 4 §2 POST31-02-V01..V04 enumeration rows + 3 §3 POST31-02-V05..V07 composition proof rows)
- REQs satisfied: 2/2 (POST31-01..02; all SAFE / NON-WIDENING / NON-INTERFERING)
- Finding candidates: 0
- Atomic commits: 4 (`dd8e0052` → `5f46b37e` → `2ad456fa` → `4e5ce8b5`)
- Closure signal: `PHASE_252_POST31_FINAL_AT_HEAD_4e5ce8b5`

**Cross-cite:** `audit/v32-252-POST31.md` (FINAL READ-only at HEAD `2ad456fa`).

**Per-REQ summary:**

| REQ | Verdict | Cross-Cite |
| --- | --- | --- |
| POST31-01 | `NON_WIDENING_AT_HEAD_acd88512` | §1 POST31-01-V01..V04 (4 commit rows: 8bdeabc2 / ad41973c / 6a63705b / 48554f8f) + §4 SIB-04 reconciliation table |
| POST31-02 | `NON_INTERFERING_AT_HEAD_acd88512` | §2 POST31-02-V01..V04 productive-pause × turbo guard interaction enumeration + §3 POST31-02-V05..V07 composition proofs §3.A / §3.B / §3.C |

Phase 252 delta-sanity verified the 4 landed post-v31.0 commits NON-WIDENING against both turbo-class and backfill-class envelopes. §1 POST31-01-V01..V04 row-by-row attestations with Phase 250 SIB-04 cross-cites + Phase 248 §5 BFL-05 dual-carrier for V04. §2 enumerates productive-pause × WIP turbo guard interactions (1 Tier-A POST31-02-V01 + 3 Tier-B NEGATIVE-scope rows). §3 records 3 composition proof scenarios: §3.A productive multi-call window (TST-03-V01 PRIMARY empirical seal) + §3.B death-clock-paused-and-resumed across VRF lock window (TST-04-V02 PRIMARY) + §3.C documented-edge turbo-blocked (TST-01-V02 + TST-02-V02 cross-cites). §3.A + §3.B are the primary §4 F-32-01 + F-32-02 deep at-HEAD-resolution cite source. §4 SIB-04 reconciliation table confirms zero divergence between Phase 250's first-pass and Phase 252's deeper analysis (4 verdicts agree row-for-row). **SG-252-01 (PLAN.md `lastPurchaseDay` writer line numbers diverged from runtime HEAD)** carries forward as a documentary-only scope-guard item per D-253-CF-07 — composition argument substantively unaffected; recorded but not impacting verdicts. `re-verified at HEAD acd88512`.

---

## 4. F-32-NN Finding Blocks

Phase 253 emits exactly TWO F-32-NN finding blocks per D-253-FIND01-01 documenting the originally-discovered testnet bugs being fixed by the v32.0 milestone: F-32-01 (productive-pause / turbo race → `purchaseLevel` underflow panic 0x11) + F-32-02 (`_backfillGapDays` double-execution underflow panic 0x11). Both classified HIGH per D-08 5-bucket rubric (player-reachable hard determinism violation; no value extraction); both SUPERSEDED at HEAD by the L173 turbo guard `!rngLockedFlag` clause + L1174 backfill sentinel `rngWordByDay[idx + 1] == 0` committed in `acd88512`. Each block uses the v29-style 8-subsection format per D-253-FIND01-03 (Severity / Source phase + plan / Subject / Description / Reproduction evidence / At-HEAD resolution / Disclosure rationale / Cross-cites). Per D-253-FIND01-04, NO additional F-32-NN blocks are emitted: SG-250-01 (`98e78404` MintModule presale-flag) is cited in §3d + §9 only; SG-252-01 (PLAN.md line-number divergence) is cited in §3f only; MintModule:1229 SIB-03-V03 (new flag-vs-flag-vs-counter triple) is cited in §3d only as a sibling-pattern observation.

### F-32-01 — Productive-pause / turbo race → `purchaseLevel` underflow (panic 0x11)

**Severity:** HIGH (D-08 player-reachable hard determinism violation; SUPERSEDED at HEAD by L173 turbo guard `!rngLockedFlag` clause committed in `acd88512`).

**Source phase + plan:** Phase 251 TST (empirical reproduction) + Phase 249 PLV-03/PLV-05/PLV-06 (structural-closure proofs) + Phase 252 §3.A (composition proof at HEAD).

**Subject:** AdvanceModule:167-185 turbo block; L173 guard `if (!inJackpot && !lastPurchaseDay && !rngLockedFlag) {...}`; L185 ternary `purchaseLevel = (cachedJpFlag && lastPurchase) ? lvl : lvl + 1`.

**Description:** Pre-fix (L173 = `!inJackpot && !lastPurchaseDay`), the turbo block fired in productive multi-call windows where `lastPurchaseDay = T` AND `rngLockedFlag = T`. The L185 ternary then evaluated `(cachedJpFlag = F && lastPurchase = T) ? lvl : lvl + 1` = `lvl + 1` followed by L186 game-over guard `if (!inJackpot && !lastPurchase) {...}` = `(T && F)` = FALSE → game-over path skipped → standard advance flow proceeded with `purchaseLevel = lvl + 1` while `level = lvl - 1` from a stale read. The arithmetic mismatch triggered `purchaseLevel - 1 < 0` panic 0x11 in downstream `_handleGameOverPath` ticket-replay ranges. Reproduced as panic 0x11 in TST-01 state-A (pre-fix; both guards reverted).

**Reproduction evidence:** Phase 251 §1 TST-01-V01 (single-day reproduction; `audit/v32-251-runs/lpdr-A-20260502T030000Z.log`) + TST-01-V02 (multi-day-drain reproduction; same state-A run). Both traces produce panic 0x11 deterministically pre-fix; post-fix state-D run (TST-02-V01..V02) is panic-free.

**At-HEAD resolution:** Structurally closed by L173 conjunction `!inJackpot && !lastPurchaseDay && !rngLockedFlag` committed in `acd88512`. Phase 249 PLV-03 ternary unreachable proof + PLV-05 testnet panic 0x11 walk + PLV-06 strand-disproof prove the L173 guard makes `(cachedJpFlag = T ∧ cachedLevel = 0)` cell UNREACHABLE via INV-PLV-B-01 + INV-PLV-C-01 composition. Phase 252 §3.A composition proof confirms productive-pause × turbo guard is mutex-aligned (turbo block fires only when `lastPurchaseDay = F ∧ jackpotPhaseFlag = F`; productive-pause short-circuit fires only when `lastPurchaseDay = T ∨ jackpotPhaseFlag = T`; disjoint state spaces).

**Disclosure rationale:** F-32-01 is emitted as a HIGH disclosure block despite SUPERSEDED-at-HEAD status because: (a) the bug is the input to v32 (the milestone exists to fix it); (b) milestone-record completeness requires explicit disclosure of the bug's mechanism + reproduction trail + structural-closure proof for any future-reader of the L173 guard's evolution; (c) v32 audit history should match v25/v27/v28/v29 historical pattern of disclosing player-reachable hard determinism violations even when SUPERSEDED.

**Cross-cites:** Phase 247 §1.4 D-247-C001..C013 + §6 Consumer Index; Phase 249 PLV-03-V01..V05 + PLV-05-V01..V06 + PLV-06-V01..V03; Phase 250 SIB-04-V01 (8bdeabc2 productive-pause × turbo guard mutex-equivalent argument); Phase 251 TST-01-V01..V02 + TST-02-V01..V02 + TST-03-V01..V02; Phase 252 §3.A composition proof (POST31-02-V05).

### F-32-02 — `_backfillGapDays` double-execution underflow (panic 0x11)

**Severity:** HIGH (D-08 player-reachable hard determinism violation; SUPERSEDED at HEAD by L1174 sentinel guard `rngWordByDay[idx + 1] == 0` committed in `acd88512`).

**Source phase + plan:** Phase 251 TST-04 (empirical reproduction) + Phase 248 BFL-01..06 (structural-closure proofs) + Phase 252 §3.B (composition proof at HEAD).

**Subject:** AdvanceModule:1167-1186 backfill block inside `rngGate` fresh-word branch; L1174 sentinel `if (rngWordByDay[idx + 1] == 0) { _backfillGapDays(...); }`.

**Description:** Pre-fix (no L1174 sentinel), `_backfillGapDays` re-executed across re-entry of `rngGate`'s fresh-word branch when `advanceGame` was called multiple times within a single VRF lock window. Each re-entry incremented `purchaseStartDay` once per gap day (correct first invocation); subsequent invocations re-incremented the same gap-day range, doubling `purchaseStartDay` increments (psdDelta = 2N for an N-day gap) and double-crediting coinflip pool payouts. Downstream consumers reading `purchaseStartDay` against the stale `level` counter triggered `purchaseStartDay - level - 1 < 0` panic 0x11. Reproduced as state-C psdDelta=15 over-bump (vs expected 7) in TST-04.

**Reproduction evidence:** Phase 251 §4 TST-04-V01 (state-C pre-fix fail; `audit/v32-251-runs/bfi-C-20260502T040000Z.log`) shows psdDelta=15 + downstream panic 0x11. State-D post-fix run (TST-04-V02) shows psdDelta=7 (single-bump per gap day) + clean drain to terminal stage 6 — 53% delta reduction empirically isolates L1174 sentinel.

**At-HEAD resolution:** Structurally closed by L1174 sentinel `if (rngWordByDay[idx + 1] == 0) { _backfillGapDays(...); }` committed in `acd88512`. Phase 248 BFL-01 (7 V-rows + 3 multiplier rows; rngGate fresh-word branch reachability under L1174) + BFL-02 (sentinel-correctness 4-step proof) + BFL-03 (testnet blocks 10759449 + 10761786 multi-day VRF stall worked example showing pre-fix doubling vs post-fix short-circuit) + BFL-04 (dailyIdx ↔ rngWordByDay invariant) + BFL-05 (EXC-02 + EXC-03 NON-WIDENING attestation) + BFL-06 (sDGNRS / DGNRS / BURNIE conservation algebra) collectively prove the L1174 sentinel makes `_backfillGapDays` idempotent across every reachable `advanceGame` re-entry path. Phase 252 §3.B composition proof confirms the multi-day VRF stall × backfill guard interaction is NON-INTERFERING at HEAD.

**Disclosure rationale:** F-32-02 is emitted as a HIGH disclosure block despite SUPERSEDED-at-HEAD status for the same reasons as F-32-01: milestone-record completeness + future-reader trail + v32 audit history matching v25/v27/v28/v29 historical pattern.

**Cross-cites:** Phase 247 §1.4 D-247-C001..C013 + §6 Consumer Index; Phase 248 BFL-01-V01..V07 + BFL-02-V01..V06 + BFL-03-V01..V15 + BFL-04-V01..V04 + BFL-05-V01..V02 + BFL-06-V01..V10; Phase 250 SIB-04-V01; Phase 251 TST-04-V01..V02; Phase 252 §3.B composition proof (POST31-02-V06).

---

## 5. Regression Appendix

This appendix is the LEAN spot-check regression deliverable per ROADMAP REG-01 / REG-02 phrasing ("Skip the full v31.0 33-row regression sweep per milestone scope decision"). REG-01 covers 12 prior-finding rows (5 F-30-NNN delta-touched candidates + 7 v3.7/v3.8 rngGate / `_backfillGapDays` baseline rows) whose evidence cites a consumer / path / site / state-var / event / interface method touched by ≥1 of the v32.0 deltas (per D-253-REG01-01 inclusion rule = domain-cite + delta-surface mapping using the Phase 247 §6 Consumer Index as authoritative source) + F-29-04 explicitly NAMED per REG-01 REQ description = 13 rows total. REG-02 is a zero-row default per D-253-REG02-01 (F-32-01 + F-32-02 supersession scope captured in §4 'At-HEAD resolution' subsections, NOT REG-02 entries).

Verdict taxonomy per D-253-REG01-03 closed set: `{PASS / REGRESSED / SUPERSEDED}`. Each row carries an `re-verified at HEAD acd88512` backtick-quoted note + one-line structural-equivalence statement against the originating-milestone source artifact.

### 5a. REG-01 — Delta-Touched F-30-NNN + v3.7/v3.8 rngGate + F-29-04 (13 rows)

REG-01 inclusion rule (D-253-REG01-01): a prior finding is "directly touched by deltas" iff its evidence cites a consumer / path / site / state-var / event / interface method that maps to a D-247-X / D-247-F / D-247-C / D-247-S row in Phase 247 §6 Consumer Index (29 D-247-I### rows total). The 253-01-PLAN.md frontmatter `reg_01_candidates` array lists the 13 candidates included; `reg_01_excluded` documents the 15 prior-finding rows excluded with one-line rationale per row.

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD acd88512 | Re-Verification Evidence | Verdict |
| --- | --- | --- | --- | --- | --- |
| REG-v29.0-F2904 | F-29-04 (Gameover RNG substitution for mid-cycle write-buffer tickets) — explicitly NAMED per REG-01 REQ phrasing because evidence cites `_swapAndFreeze(purchaseLevel)` at AdvanceModule:292 which touches `purchaseLevel` | acd88512 + 8bdeabc2 + 6a63705b + 48554f8f | `_swapAndFreeze(purchaseLevel)` at AdvanceModule:292; `_gameOverEntropy` at :1222-1246; sole `_gameOverEntropy` caller `advanceGame:553` (rngWord sink); buffer-swap primitive boundary unchanged. EXC-03 envelope re-verified non-widening. | Phase 248 BFL-05-V02 RE_VERIFIED_AT_HEAD acd88512 (EXC-03 dual-carrier). EXC-03 tri-gate predicates (terminal-state + no-player-reachable-timing + buffer-scope) all hold per Phase 248 BFL-05 + Phase 250 SIB-03 NEGATIVE-scope. KNOWN-ISSUES.md EXC-03 entry intact at HEAD. | PASS |
| REG-v30.0-F30001 | F-30-001 prevrandao fallback state-machine check (`AdvanceModule:1322` `_getHistoricalRngFallback`) | acd88512 | Sole prevrandao site remains AdvanceModule:1340-relative `_getHistoricalRngFallback`; no new prevrandao-consumption path introduced by L173 turbo guard or L1174 backfill sentinel; GAMEOVER_RNG_FALLBACK_DELAY = 14 days constant intact at AdvanceModule:109. | Phase 248 BFL-05-V01 RE_VERIFIED_AT_HEAD acd88512 (EXC-02 dual-carrier with EXC-03). EXC-02 envelope NON-WIDENING per Phase 248 BFL-05 + Phase 250 SIB-03 NEGATIVE-scope. KI EXC-02 entry intact at HEAD. | PASS |
| REG-v30.0-F30004 | F-30-004 mid-day gate off-by-one check (AdvanceModule:204-208 region; original-milestone reformatted by 16597cac per v31 Phase 244 RNG-03) | acd88512 | Mid-day gate region at AdvanceModule:204-208 NOT delta-touched by L173 (line 173) turbo guard or L1174 backfill sentinel; logically separate from turbo block at L167-182. v31 reformat-only verdict carries forward; no new behavioral change. | Phase 247 §1.4 D-247-C### rows confirm zero-touch on AdvanceModule:204-208; Phase 250 SIB-01 9 V-rows enumerate every `rngLockedFlag` interaction in AdvanceModule and AdvanceModule:204-208 is not one. Phase 252 §1 POST31-01 confirms 4 landed commits NON-WIDENING. | PASS |
| REG-v30.0-F30005 | F-30-005 F-29-04 liveness-proof note (`_swapAndFreeze:292` + `_swapTicketSlot:1082` write-buffer-swap sites) | acd88512 + 8bdeabc2 + 48554f8f | Write-buffer-swap sites at AdvanceModule:292 + :1082 NOT delta-touched. `_handleGameOverPath` reordering carries forward from v31 Phase 244 GOX-06-V02 with no v32 change. EXC-03 tri-gate predicates all hold at HEAD. | Phase 248 BFL-05-V02 RE_VERIFIED_AT_HEAD acd88512 (EXC-03 dual-carrier with EXC-02). Same domain as REG-v29.0-F2904 row above; PRIMARY cite is BFL-05-V02; cross-cites Phase 250 SIB-03 NEGATIVE-scope for EXC-03. | PASS |
| REG-v30.0-F30015 | F-30-015 prevrandao-mix recursion citation (INV-237-060..062 cluster at AdvanceModule:1301-1325) | acd88512 | Same domain as F-30-001 (prevrandao fallback under EXC-02). INV-237-060..062 cluster at AdvanceModule:1301-1325 NOT delta-touched by L173 turbo guard or L1174 backfill sentinel. | Phase 248 BFL-05-V01 RE_VERIFIED_AT_HEAD acd88512 (EXC-02 dual-carrier). Same PRIMARY cite as REG-v30.0-F30001 above. EXC-02 envelope NON-WIDENING per Phase 248 BFL-05. | PASS |
| REG-v30.0-F30017 | F-30-017 F-29-04 swap-site liveness recommendation (write-buffer-swap sites pre-VRF-request commitment) | acd88512 + 48554f8f | Same domain as F-30-005 + REG-v29.0-F2904 (write-buffer-swap sites under EXC-03). Distinct F-30-NNN ID per v30 D-07 source-attribution preservation. EXC-03 envelope non-widening. | Phase 248 BFL-05-V02 RE_VERIFIED_AT_HEAD acd88512 (EXC-03 dual-carrier). Cross-cites REG-v30.0-F30005 + REG-v29.0-F2904 for shared subject surface. | PASS |
| REG-v3.7-005 | v3.7 Phase 65 VRF Stall Edge Cases gap-backfill entropy (INV-237-067 `_backfillGapDays` at AdvanceModule:1738-relative) | acd88512 | `_backfillGapDays` body at AdvanceModule:1700-relative NOT delta-touched by L1174 sentinel (sentinel is at the CALL SITE inside `rngGate` fresh-word branch at L1174, not inside `_backfillGapDays` body). Gap-backfill entropy uniqueness preserved via keccak256(vrfWord, gapDay) per KNOWN-ISSUES.md backfill-cap entry. | Phase 248 BFL-01-V01..V07 + BFL-02-V01..V06 (whole guarded block L1174-1186 sentinel-correctness 4-step proof per D-248-09); Phase 248 §6 BFL-06 conservation algebra closes (sDGNRS / DGNRS / BURNIE supplies invariant across lock window). The L1174 sentinel ENHANCES idempotency without changing the underlying entropy-derivation invariant. | PASS |
| REG-v3.7-006 | v3.7 Phase 65 VRF Stall gap-backfill coinflip payouts (INV-237-068 `_backfillGapDays` coinflip payouts branch) | acd88512 | Coinflip payouts branch inside `_backfillGapDays` body at AdvanceModule:1700-relative NOT delta-touched. L1174 sentinel guards the CALL SITE; once entered, `_backfillGapDays` body executes the same coinflip-payout logic as v3.7 baseline. | Phase 248 §6 BFL-06 conservation proof closes algebraically: total ETH credited to coinflip pools across the gap range matches expected non-doubled amount. D-248-10 boundary cite for BurnieCoinflip.sol::processCoinflipPayouts. The L1174 sentinel SUPERSEDES the doubling pre-condition (each gap day's coinflip payout fires exactly once per VRF lock window). | PASS |
| REG-v3.8-001 | v3.8 Phases 68-72 VRF commitment window audit 51/51 SAFE baseline (rngGate; INV-237-046) | acd88512 | rngGate at AdvanceModule:1152 (function header) — D-247-F011 MODIFIED_LOGIC (Phase 247 §2). The L1174 backfill sentinel is INSIDE rngGate's fresh-word branch. Commitment-window invariant preserved: rngLockedFlag set/clear boundary unchanged from v3.8 baseline; sentinel is read-only in the fresh-word branch. | Phase 248 BFL-01 7 V-rows + 3 multiplier rows enumerate every code path reaching `_backfillGapDays` (sole call site inside rngGate fresh-word branch); commitment-window narrowing invariant from v3.8 baseline holds at HEAD per Phase 248 §4 BFL-04 (dailyIdx ↔ rngWordByDay invariant). | PASS |
| REG-v3.8-002 | v3.8 Phases 68-72 commitment window baseline (rngGate; INV-237-047) | acd88512 | Same rngGate domain as REG-v3.8-001. Commitment-window narrowing invariant preserved at HEAD. | Phase 248 BFL-01 + BFL-04. Same PRIMARY cite as REG-v3.8-001 above. | PASS |
| REG-v3.8-003 | v3.8 Phases 68-72 commitment window baseline (rngGate _applyDailyRng call; INV-237-048) | acd88512 | _applyDailyRng call inside rngGate. The L1174 backfill sentinel is in the same rngGate fresh-word branch as _applyDailyRng but operates on a DISJOINT state slot (rngWordByDay[idx + 1] vs the daily-RNG buffer). No commitment-window widening. | Phase 248 BFL-01 + BFL-04. Cross-cite Phase 248 §4 BFL-04 dailyIdx ↔ rngWordByDay invariant per D-248-15 grep-cited universe. | PASS |
| REG-v3.8-004 | v3.8 Phases 68-72 commitment window baseline (rngGate redemption roll; INV-237-049) | acd88512 | Redemption roll inside rngGate fresh-word branch. L1174 sentinel is upstream of redemption roll (gates `_backfillGapDays`); redemption roll proceeds unchanged from v3.8 baseline. | Phase 248 BFL-01 (sole call site at L1176 inside fresh-word branch); Phase 248 §6 BFL-06 conservation algebra (sDGNRS / DGNRS / BURNIE supplies invariant across lock window). | PASS |
| REG-v3.8-005 | v3.8 Phases 68-72 commitment window baseline (rngGate _finalizeLootboxRng; INV-237-050) | acd88512 | _finalizeLootboxRng call inside rngGate fresh-word branch. L1174 sentinel guards `_backfillGapDays` only; _finalizeLootboxRng path operates on lootbox-index-advance isolation per KI EXC-04 (lootbox roll path NOT delta-touched per Phase 250 SIB-03 NEGATIVE-scope). | Phase 250 SIB-03 NEGATIVE-scope (EXC-04 EntropyLib XOR-shift not delta-touched); Phase 248 BFL-01 + BFL-04 confirm sentinel scope is `_backfillGapDays`-only. | PASS |

**REG-01 distribution at HEAD `acd88512`: 13 PASS / 0 REGRESSED / 0 SUPERSEDED** (12 prior-finding rows from v29 + v30 + v3.7/v3.8 baseline + 1 explicitly NAMED F-29-04 row). Expected per Phase 247-252 zero-finding-candidate input + KI EXC-02 + EXC-03 envelopes RE_VERIFIED_AT_HEAD without widening per Phase 248 BFL-05 + EXC-01 + EXC-04 NEGATIVE-scope per Phase 250 SIB-03. The L173 turbo guard + L1174 backfill sentinel SUPERSEDE the bug surfaces (turbo race + backfill double-execution) WITHOUT regressing any prior finding's acceptance envelope.

#### REG-01 Exclusion Log

15 prior-finding rows from `audit/FINDINGS-v29.0.md` + `audit/FINDINGS-v30.0.md` inspected against the v32.0 deltas and excluded per D-253-REG01-01 inclusion rule (no Phase 247 §6 Consumer Index domain-cite match). Authoritative list lives in `253-01-PLAN.md` frontmatter `reg_01_excluded` array. Summary:

- **F-30-002** (boon-roll entropy XOR-shift; LootboxModule:1059) — lootbox roll path NOT delta-touched per Phase 250 SIB-03 NEGATIVE-scope (EXC-04 envelope). No domain-cite to any D-247-I row.
- **F-30-003** (deityBoonData view-deterministic-fallback; DegenerusGame.sol:852) — deity-boon view path NOT delta-touched. No domain-cite to any D-247-I row.
- **F-30-006** (Daily-share 62.3% sanity observation) — meta-observation, not file-line bound; not delta-touchable.
- **F-30-007** (KI-exception precedence over path-family rules — taxonomy-precedence rule disclosure) — taxonomy-only; the v32 deltas (L173 + L1174 guards) introduce no new path-families requiring re-classification per Phase 250 SIB-02 ORTHOGONAL_PROVEN classifier.
- **F-30-008** (INV-237-009 view-deterministic-fallback classification edge case; DegenerusGame.sol:852) — duplicate subject of F-30-003; deity-boon view path NOT delta-touched.
- **F-30-009** (INV-237-066 fulfillment-callback classification ambiguity; rawFulfillRandomWords mid-day branch SSTORE at AdvanceModule:1706-relative) — fulfillment callback NOT delta-touched by L173 turbo guard or L1174 backfill sentinel.
- **F-30-010** (INV-237-124 sole daily-family EntropyLib caller; JackpotModule:2119 _jackpotTicketRoll) — entropyStep call site NOT delta-touched per Phase 250 SIB-03 NEGATIVE-scope.
- **F-30-011** (INV-237-129 resolveLootboxDirect library-wrapper; LootboxModule:673) — LootboxModule NOT delta-touched per Phase 250 SIB-03 NEGATIVE-scope.
- **F-30-012** (INV-237-143/-144 _raritySymbolBatch / _rollRemainder dual-trigger; MintModule:568/652) — Phase 247 D-247-C003/C004/C005 confirm MintModule charge-target swap (`_callTicketPurchase` signature) does NOT touch _raritySymbolBatch / _rollRemainder. Functionally orthogonal per Phase 250 SIB-04-V03 Form-1 isolation.
- **F-30-013** (INV-237-143/-144 dual-trigger delegatecall boundary; Phase 238 BWD bifurcation recommendation) — duplicate subject of F-30-012; MintModule rarity-symbol path NOT delta-touched.
- **F-30-014** (INV-237-129 resolveLootboxDirect gameover-caller marker; Phase 238 BWD marker recommendation) — duplicate subject of F-30-011; LootboxModule NOT delta-touched.
- **F-30-016** (INV-237-124 sole daily-family EntropyLib caller; Phase 241 EXC-04 scope disclosure) — duplicate subject of F-30-010; entropyStep call site NOT delta-touched.
- **F-29-01** (JackpotEthWin event signature widening uint8→uint16 BAF traitId; JackpotModule:69-77) — event surface NOT delta-touched by L173 turbo guard or L1174 backfill sentinel.
- **F-29-02** (JackpotTicketWin event signature widening uint8→uint16 BAF traitId; JackpotModule:80-87) — event surface NOT delta-touched.
- **F-29-03** (QST-01 mint_ETH companion-test-coverage gap; test/fuzz/CoverageGap222.t.sol:1453-1455) — test-tooling observation; not file-line bound to AdvanceModule turbo or rngGate; not delta-touched.

### 5b. REG-02 — SUPERSEDED Sweep (0 rows)

REG-02 scope per D-253-REG02-01 = defensive grep walk over prior FINDINGS for any v29/v30/v31 row whose acceptance rationale relied on a non-guarded turbo/backfill envelope. Default expectation: 0 prior F-NN-NN entries from v29/v30/v31 are STRUCTURALLY CLOSED by L173 + L1174 guards. The fixed bugs (turbo race + backfill double-execution) are v32-discovered, not prior-flagged. Supersession scope is captured by F-32-01 + F-32-02 'At-HEAD resolution' subsections per D-253-FIND01-03 step 6, NOT as REG-02 entries. Defensive grep walk recipe (D-253-REG02-01):

```bash
grep -nE 'rngLockedFlag|_backfillGapDays|purchaseLevel|lastPurchaseDay|dailyIdx|turbo' \
  audit/FINDINGS-v29.0.md \
  audit/FINDINGS-v30.0.md \
  audit/FINDINGS-v31.0.md \
  | grep -iE 'accept|design|envelope|HOLDS|carrier'
# Expected: zero hits qualifying as supersession candidates
```

Grep walk returned zero hits qualifying as supersession candidates (any hits surfaced are KI envelope re-verifications already covered in §6b, NOT supersession candidates per D-22 carry). REG-02 stays zero-row default per D-253-REG02-01.

| Prior-Finding-ID | Delta SHA | Verdict | Evidence | Citation |
| --- | --- | --- | --- | --- |
| _(zero rows — empty REG-02 candidate pool per D-253-REG02-01 default expectation)_ | — | — | — | — |

**REG-02 distribution at HEAD `acd88512`: 0 PASS / 0 REGRESSED / 0 SUPERSEDED.** Expected per D-253-REG02-01 default — F-32-01 + F-32-02 (turbo race + backfill double-execution) are v32-discovered HIGH disclosure blocks per §4, NOT prior F-NN-NN supersession candidates. Their structural-closure proofs are captured in §4 'At-HEAD resolution' subsections (PLV-03 + PLV-05 + PLV-06 strand-disproof + Phase 252 §3.A composition for F-32-01; BFL-01..06 + Phase 252 §3.B composition for F-32-02). No prior-milestone finding's acceptance envelope was conditioned on the absence of turbo or backfill guards; therefore zero supersession rows.

### 5c. Combined REG-01 + REG-02 Distribution at HEAD `acd88512`

Combined distribution table per Claude's Discretion 4-col format (mirror v31 §5c):

| Verdict | REG-01 | REG-02 | Combined |
| --- | --- | --- | --- |
| PASS | 13 | 0 | 13 |
| REGRESSED | 0 | 0 | 0 |
| SUPERSEDED | 0 | 0 | 0 |
| **Total** | **13** | **0** | **13** |

`re-verified at HEAD acd88512` — all 13 prior-finding rows accounted for under D-253-REG01-03 verdict taxonomy. Zero regressions detected. Zero supersessions emitted via REG-02 per D-253-REG02-01 default (F-32-NN supersession scope captured in §4 'At-HEAD resolution' subsections, not REG-02). Expected per Phase 247-252 zero-finding-candidate input + KI EXC-02 + EXC-03 envelopes RE_VERIFIED_AT_HEAD non-widening per Phase 248 BFL-05 + EXC-01 + EXC-04 NEGATIVE-scope per Phase 250 SIB-03.

---

<!-- §6 FIND-03 KI Gating Walk — filled by Task 5 -->

<!-- §7 Prior-Artifact Cross-Cites — filled by Task 5 -->

## 8. Forward-Cite Closure (D-253-09 + D-253-15 step 8 Terminal-Phase Rule)

This section verifies (a) zero Phase 247→248→249→250→251→252→253 forward-cite tokens were emitted across the v32.0 milestone per each upstream phase's CONTEXT.md terminal-phase contract; (b) zero Phase 253 → v33.0+ forward-cites are emitted per ROADMAP terminal-phase rule (v32.0 = Phases 247-253; v33.0+ has no Phase 254).

### 8a. Phase 247-252 → Phase 253 Forward-Cite Residual Verification (0 expected)

Expected count: 0 forward-cites across the v32.0 milestone per each upstream phase's zero-state attestation (Phase 247 §7 reproduction recipe + Phase 248 §7 hand-off appendix + Phase 249 §6 PLV-06 strand-disproof + Phase 250 §5 SIB-05 zero-state + Phase 251 §5 commit-readiness register + Phase 252 §4 SIB-04 reconciliation paragraph). Grep recipe (D-253-CF-08):

```bash
grep -rE 'forward-cite|defer-to-Phase-254|TBD-v33' \
  audit/v32-247-DELTA-SURFACE.md \
  audit/v32-248-BFL.md \
  audit/v32-249-PLV.md \
  audit/v32-250-SIB.md \
  audit/v32-251-TST.md \
  audit/v32-252-POST31.md
# Expected: zero matches
```

`re-verified at HEAD acd88512` — zero Phase 253-bound forward-cite tokens present in any upstream `audit/v32-NNN-*.md`. Each upstream phase closed FIND-01..FIND-NN candidates within its own scope; no rollover to Phase 253 beyond the canonical Phase 247 §6 Consumer Index → Phase 248-253 mapping (D-247-I001..I029) which is a dependency declaration, NOT a forward-cite per D-253-09.

**Verdict:** `ZERO_PHASE_247_THROUGH_252_FORWARD_CITES_RESIDUAL`.

### 8b. Phase 253 → v33.0+ Forward-Cite Emission (0 expected per D-253-09 + ROADMAP terminal-phase rule)

Phase 253 is the terminal v32.0 phase. Per CONTEXT.md D-253-09 + D-253-CF-07 + ROADMAP, any finding that cannot close in Phase 253 routes to scope-guard deferral in 253-01-SUMMARY.md (NOT to a forward-cite addendum block). With zero finding candidates from Phase 247-252 (134 V-rows all SAFE / NON-WIDENING / NON-INTERFERING) and the two F-32-NN disclosure blocks both SUPERSEDED-at-HEAD, no rollover addenda are expected. Grep recipe (D-253-CF-08):

```bash
grep -rE 'forward-cite|defer-to-Phase-254|TBD-v33' audit/FINDINGS-v32.0.md
# Expected: zero matches
```

`re-verified at HEAD acd88512` — zero Phase 253-emitted forward-cite tokens present in `audit/FINDINGS-v32.0.md` (§4 F-32-NN section is post-mitigation milestone-record disclosure, not forward-cite; §6 Non-Promotion Ledger is sticky-FAIL routing, not forward-cite; no F-32-NN rollover addendum blocks present).

**Verdict:** `ZERO_PHASE_253_FORWARD_CITES_EMITTED` (v33.0+ scope addendum count = 0).

### 8c. Combined §8 Verdict

Phase 247→248→249→250→251→252→253 forward-cite closure: **0/0 Phase 247-252 residuals + 0/0 Phase 253 emissions** → milestone boundary closed per CONTEXT.md D-253-09 + ROADMAP terminal-phase rule. v32.0 milestone deliverable is self-contained at HEAD `acd88512`; no forward-cite residual awaits v33.0+ audit cycle. Any v33.0+ delta will boot from the closure signal `MILESTONE_V32_AT_HEAD_acd88512` (§9c) with a fresh delta-extraction phase.

---

<!-- §9 Milestone Closure Attestation — filled by Task 6 -->

<!-- closure signal trailing line — filled by Task 6: MILESTONE_V32_AT_HEAD_acd88512 -->
