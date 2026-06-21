# Roadmap — Milestone v73.0 — Degenerette "Variant-2" Color-Gated Rescore (+ WWXRP Preservation)

> **Subject:** RESETS off the v72.0 closure (`MILESTONE_V72_AT_HEAD_e94f1719…`; `contracts/` tree `4407181d` @ `e94f1719`). The IMPL diff (453) produces the new v73 byte-frozen subject.
> **Posture:** a bounded contract LOGIC change on the core Degenerette `_score` + the re-audit it forces. Port the color-gated-by-symbol rule (shipped on the foil match `16225de6`) into the betting engine: ~1-in-5 / ~2× at IDENTICAL EV, WWXRP rig family recalibrated to preserve P(S=9) / RTP curve / S=9 whale-pass bracket / ROI curve / per-N EV=100.
> **Numbering continues 451 → 452.** No research (internal recalibration of existing source with a shipped precedent).
> **The ONLY approval gate is the IMPL contract commit (453).** Everything else (the generator rewrite + table regen, EV-drift measurement, tests, proofs, re-audit, findings) commits autonomously.
> **Generator-first (hard):** Phase 452 GEN rewrites + verifies `derive_5_tables.py` and presents the regenerated tables + the EV-drift number BEFORE any contract edit — a no-contract-risk front-loaded phase.
> **3 design decisions** (DEC-01 rig R1/R2 · DEC-02 EV-equality A/B · DEC-03 floor S≥2) are locked in `/gsd-discuss-phase 452`.

---

## Phase 452 — GEN (generator-first; NO contract edit)

**Goal:** Lock the 3 design decisions, then rewrite + verify `derive_5_tables.py` as the canonical byte-reproduce source, regenerate the full constant family, and present the regenerated tables + the Option-A EV-drift number. Zero contract risk — no `.sol` is touched in this phase.

**Requirements:** GEN-01, GEN-02, GEN-03, EVEQ-01

**Success criteria:**
1. The 3 decisions (DEC-01/02/03) are locked in discuss-phase and recorded.
2. `derive_5_tables.py` rewritten for Variant-2 (honest + rigged dist, same calibration, same self-asserts); self-asserts pass (per-N basePayoutEV ∈ (99,100] centi-x honest + rigged; bonus-EV = 5.000%; all WWXRP factors < 2^64).
3. The full constant family is regenerated (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED/_S8`, `WWXRP_FACTORS_N{0..4}`, the `_RIG_` family); `_S9` pins + `WWXRP_ROI_*` confirmed untouched.
4. Option-A EV-drift across hero placement is measured and reported; DEC-02 resolved (keep A if < ~0.5 centi-x, else escalate to B) — the resolution feeds the IMPL table shape.
5. Numeric pre-proof that P(S=9) and the WWXRP RTP curve are unchanged vs HEAD (the generator confirms it before any contract edit).

## Phase 453 — IMPL (the sole approval gate)

**Goal:** Implement Variant-2 in the contract as ONE batched, USER-approved `.sol` diff — the `_score` rewrite, the `_rigWwxrpResult` adaptation, the regenerated constant blocks, and the doc-comment refresh.

**Requirements:** SCORE-01, SCORE-02, SCORE-03, RIG-01, RIG-02, RIG-03, IMPL-01

**Success criteria:**
1. `_score` implements Variant-2 (per-quadrant symbol +1 / hero +2; color +1 only if that quadrant's symbol matched; S∈{0..9}; floor S≥2).
2. `_rigWwxrpResult` forces score-bearing cells per DEC-01, preserving P(S=9) via the m≥7 cap (and, if R2, display==score honest + the ~60% near-win lift).
3. The regenerated constant blocks from 452 are pasted in verbatim; `_S9` pins + `WWXRP_ROI_*` untouched.
4. `forge build` clean; EIP-170 fits.
5. The diff lands as ONE batched commit only after explicit USER hand-review (commit-guard `CONTRACTS_COMMIT_APPROVED=1` + hook move-aside) — produces the byte-frozen v73 subject.

## Phase 454 — TST

**Goal:** Prove the byte-reproduce gate + the held-fixed invariants + behaviour parity on the new scoring.

**Requirements:** TST-01, TST-02, INV-01, INV-02, INV-03, INV-04

**Success criteria:**
1. Byte-reproduce gate green — a stat test that regenerates the constants from `derive_5_tables.py` matches the committed constant blocks exactly.
2. Numeric proof: WWXRP RTP curve (`WWXRP_ROI_*` 70→115→118→120%), the ROI curve (`_roiBpsFromScore` 90→99.9%), P(S=9), and the S=9 whale-pass bracket are unchanged vs HEAD.
3. Degenerette unit + invariant tests + stat oracles green; full-suite parity (`forge` + Hardhat).
4. The Option-A EV-drift is within tolerance in-contract (or Option-B was adopted and proven exactly EV-equal).

## Phase 455 — REAUDIT

**Goal:** Re-audit the betting engine on the new scoring (core scoring touched) across the 3 pillars.

**Requirements:** AUD-01

**Success criteria:**
1. **Solvency** — no path pays unbacked value; per-N EV ≤ 100 holds on the new tables; the rig surplus stays accounted.
2. **RNG integrity** — every WWXRP/Degenerette VRF consumer remains frozen-at-commitment on the new `_score`/`_rigWwxrpResult`; the rig introduces no new steer.
3. **Liveness / no-brick** — resolution + advanceGame cannot be gas-bricked or state-corrupted by the rewritten scoring; pull-claim preserved.
4. Cross-model (Codex; gemini if revived) on every load-bearing correctness/security claim; isolated-subagent nets otherwise.

## Phase 456 — TERMINAL

**Goal:** Ship the evidence pack and flip the closure signal.

**Requirements:** TERM-01

**Success criteria:**
1. `audit/FINDINGS-v73.0.md` (chmod 444) + `AUDIT-V73-REPORT.html` authored.
2. Closure signal `MILESTONE_V73_AT_HEAD_<sha>`; subject confirmed byte-frozen at the IMPL diff.
3. Archive `milestones/v73.0-{ROADMAP,REQUIREMENTS}.md`; tag `v73.0` (BY HAND, per repo convention).

---

## Coverage

| Phase | Requirements | Count |
|-------|--------------|-------|
| 452 GEN | GEN-01, GEN-02, GEN-03, EVEQ-01 | 4 |
| 453 IMPL | SCORE-01, SCORE-02, SCORE-03, RIG-01, RIG-02, RIG-03, IMPL-01 | 7 |
| 454 TST | TST-01, TST-02, INV-01, INV-02, INV-03, INV-04 | 6 |
| 455 REAUDIT | AUD-01 | 1 |
| 456 TERMINAL | TERM-01 | 1 |

**19 requirements mapped across 5 phases — all covered ✓**

---
*Roadmap created: 2026-06-21 (authored BY HAND at milestone v73.0 init)*
