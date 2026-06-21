# Milestone v73.0 — Degenerette "Variant-2" Color-Gated Rescore (+ WWXRP Preservation) — Requirements

**Defined:** 2026-06-21
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

> **Posture:** A bounded contract **LOGIC change** on the core Degenerette scoring surface, plus the re-audit it forces. It **RESETS the audit subject** off the v72.0 closure (`MILESTONE_V72_AT_HEAD_e94f1719…`; `contracts/` tree `4407181d` @ `e94f1719`).
> **What changes:** port the color-gated-by-symbol match rule — already shipped on the *foil* match in commit `16225de6` — into the core Degenerette `_score`. Main slot moves from ~1-in-3 / 32% to **~1-in-5 spins at ~2× multipliers at IDENTICAL EV**; the full WWXRP rig family is recalibrated so everything that matters about WWXRP is preserved.
> **The rule (`_score`):** today S = A + 2H (4 color + 4 symbol axes counted independently; hero symbol +2; S∈{0..9}; pay floor S≥2). **Variant-2:** per quadrant a symbol match scores +1 (hero symbol +2), and the color scores +1 **only if that quadrant's symbol also matched**. S∈{0..9} unchanged; floor S≥2 unchanged; **S=9 is still the all-8-axes event — jackpot odds + payout pinned.**
> **3 design decisions are deferred to `/gsd-discuss-phase 452`** (see DEC-01/02/03 below) and are NOT resolved here.
> **Generator-first (hard):** `derive_5_tables.py` is rewritten + verified and the regenerated tables + EV-drift number presented **before any contract edit** (Phase 452 GEN carries zero contract risk). All contract edits land as ONE batched, USER-approved `.sol` diff (Phase 453 IMPL — the sole approval gate).

---

## v1 Requirements

### SCORE — the rule change (`_score`)

- [x] **SCORE-01**: `_score` implements Variant-2 — per quadrant, a symbol match scores +1 (hero symbol +2); the color scores +1 **only if that quadrant's symbol also matched**. Score S∈{0..9} unchanged.
- [x] **SCORE-02**: Pay floor stays **S≥2** — a lone ordinary (non-hero) symbol match pays 0; a hero symbol or a full color+symbol double pays. (Confirms DEC-03.)
- [x] **SCORE-03**: S=9 remains the all-8-axes event — the S=9 jackpot odds P(S=9), the jackpot pin values, and the WWXRP S=9 whale-pass bracket award are **byte-identical to HEAD**.

### RIG — WWXRP rig adaptation (`_rigWwxrpResult`)

- [x] **RIG-01**: `_rigWwxrpResult` is adapted to force **score-bearing** cells under Variant-2 (mechanism per DEC-01: R2 = force an unmatched non-hero symbol, or an unmatched color on a quadrant whose symbol already matches; R1 = leave-rig fallback).
- [x] **RIG-02**: P(S=9) is preserved under the rig via the existing **m≥7 cap** — the rig never manufactures an S=9 that honest play would not have produced at the pinned rate.
- [x] **RIG-03**: If R2 is chosen, the rig keeps **display==score honest** and preserves the ~60% near-win lift.

### GEN — canonical generator (`derive_5_tables.py`)

- [x] **GEN-01**: `derive_5_tables.py` is rewritten as the **canonical byte-reproduce source** — Variant-2 honest distribution + rigged distribution + the same calibration + the same self-asserts.
- [x] **GEN-02**: The generator's self-asserts pass: per-N `basePayoutEV ∈ (99,100]` centi-x (honest **and** rigged); ETH/WWXRP bonus-EV = 5.000%; all WWXRP factors < 2^64.
- [x] **GEN-03**: The full constant family is regenerated from the script — honest `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED/_S8`, `WWXRP_FACTORS_N{0..4}`, the full `_RIG_` family — with the `_S9` pins and `WWXRP_ROI_*` **untouched**. Doc-comments refreshed.

### EVEQ — EV-equality wrinkle (decision #2)

- [x] **EVEQ-01**: Because Variant-2 couples color+symbol, the hero quadrant's gold-ness now affects P(S) and one per-N table is no longer exactly EV-equal across picks. Measure **Option-A** drift (average over hero placement, 5 tables) and keep it if < ~0.5 centi-x; **escalate to Option-B** (index by `(N, hero-is-gold)`, ~8–9 tables + a small `_getBasePayoutBps` dispatch tweak) only on drift. (Resolves DEC-02 on measurement.)

### INV — invariants held fixed (numeric proof)

- [ ] **INV-01**: Activity ROI curve `_roiBpsFromScore` (90→99.9%) unchanged vs HEAD.
- [ ] **INV-02**: WWXRP RTP curve `WWXRP_ROI_*` (70→115→118→120%) unchanged vs HEAD.
- [ ] **INV-03**: Numeric proof that the WWXRP RTP curve and P(S=9) are unchanged vs HEAD under the rig.
- [ ] **INV-04**: The WWXRP S=9 whale-pass bracket award is unchanged vs HEAD.

### TST — verification gates

- [ ] **TST-01**: Byte-reproduce gate green — a stat test that regenerates the constants from `derive_5_tables.py` matches the committed constant blocks exactly.
- [ ] **TST-02**: `forge build` clean; Degenerette unit + invariant tests + stat oracles green; full-suite parity.

### IMPL — the gated contract diff

- [x] **IMPL-01**: The `_score` rewrite + `_rigWwxrpResult` adaptation + regenerated constant blocks + doc-comment refresh land as **ONE batched `.sol` diff**, committed only after explicit USER approval (the sole approval gate; commit-guard `CONTRACTS_COMMIT_APPROVED=1` + hook move-aside).

### AUD — re-audit the betting engine

- [ ] **AUD-01**: After the change (core scoring touched), re-audit the betting engine — Solvency · RNG-integrity (freeze-at-commitment of every WWXRP/Degenerette VRF consumer) · Liveness/no-brick re-attested on the new scoring; cross-model (Codex; gemini if revived) on every load-bearing claim.

### TERM — evidence pack + closure

- [ ] **TERM-01**: Evidence pack `audit/FINDINGS-v73.0.md` (+ HTML) + closure signal `MILESTONE_V73_AT_HEAD_<sha>`; subject confirmed byte-frozen at the IMPL diff.

---

## Decisions to lock in discuss-phase (452)

| ID | Decision | Recommendation |
|----|----------|----------------|
| **DEC-01** | Rig — **R2** (force an unmatched non-hero symbol, or an unmatched color on a quadrant whose symbol already matches; keeps display==score honest + the 60% near-win lift) vs **R1** (leave rig, accept score-no-op forces) | **R2** |
| **DEC-02** | EV-equality — **(A)** average over hero placement (5 tables, measure drift, keep if < ~0.5 centi-x) vs **(B)** index by `(N, hero-is-gold)` for exact equality (~8–9 tables + a small `_getBasePayoutBps` dispatch tweak) | **(A)**, escalate to (B) only on drift |
| **DEC-03** | Confirm pay floor stays **S≥2** (lone ordinary match pays 0; hero symbol or a full double pays) | **Yes** |

## Out of Scope

| Feature | Reason |
|---------|--------|
| The foil match rescore | Already shipped + audited (v72.0, commit `16225de6`) |
| Activity-score curves | Untouched — only the consumer *match* rule changes, not the score itself |
| The currency split (FLIP/ETH/WWXRP lanes) | Unchanged — the +5% ETH lane bonus / 5% bonus-EV is held fixed |
| Bet placement | Unchanged — only resolution scoring + payout tables change |
| Pools / solvency paths | Unchanged — EV=100 per N is preserved; no new value emitted |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GEN-01 | 452 GEN | Done |
| GEN-02 | 452 GEN | Done |
| GEN-03 | 452 GEN | Done |
| EVEQ-01 | 452 GEN | Done |
| SCORE-01 | 453 IMPL | Done |
| SCORE-02 | 453 IMPL | Done |
| SCORE-03 | 453 IMPL | Done |
| RIG-01 | 453 IMPL | Done |
| RIG-02 | 453 IMPL | Done |
| RIG-03 | 453 IMPL | Done |
| IMPL-01 | 453 IMPL | Done |
| TST-01 | 454 TST | Pending |
| TST-02 | 454 TST | Pending |
| INV-01 | 454 TST | Pending |
| INV-02 | 454 TST | Pending |
| INV-03 | 454 TST | Pending |
| INV-04 | 454 TST | Pending |
| AUD-01 | 455 REAUDIT | Pending |
| TERM-01 | 456 TERMINAL | Pending |

**Coverage:**
- v1 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0 ✓

## Anchors

- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `_score ~L1053`, `_rigWwxrpResult ~L1299`, constant blocks `~L283-360`, `_wwxrpRoi ~L1259`.
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — canonical generator.
- Foil precedent: commit `16225de6`.

---
*Requirements defined: 2026-06-21*
*Last updated: 2026-06-21 after milestone v73.0 init (authored BY HAND)*
