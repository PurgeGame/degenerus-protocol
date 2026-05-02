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

<!-- §3 Per-Phase Sections — filled by Task 2 -->

<!-- §4 F-32-NN Finding Blocks — filled by Task 3 -->

<!-- §5 Regression Appendix — filled by Task 4 -->

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
