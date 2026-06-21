# Phase 452: GEN (generator-first; NO contract edit) - Context

**Gathered:** 2026-06-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Lock the three v73.0 design decisions, then rewrite + verify `derive_5_tables.py` as the
canonical byte-reproduce source for **Variant-2** (color-gated-by-symbol) scoring, regenerate
the full constant family (honest + rigged), and present the regenerated tables + the measured
EV-drift number. **Zero contract risk — no `.sol` is touched in this phase.** The contract edit
is deferred to Phase 453 IMPL (the sole approval gate).

The decisions locked here set (a) the *rig mechanism* IMPL will encode and (b) the *table shape*
the generator produces.

**Variant-2 rule (`_score`):** today S = A + 2H counts 4 color axes + 4 symbol axes
*independently* (hero symbol +2; S∈{0..9}; pay floor S≥2). Variant-2 gates color behind symbol:
per quadrant a symbol match scores +1 (hero symbol +2), and the color scores +1 **only if that
quadrant's symbol also matched**. Max stays 9 (hero quad 3 + three ordinary quads ×2), and
**S=9 remains exactly the all-8-axes event** — jackpot odds P(S=9), the jackpot pins, and the
WWXRP S=9 whale-pass bracket are byte-identical to HEAD. Effect: main slot moves from ~1-in-3 /
32% to ~1-in-5 at ~2× multipliers at **identical EV**.

</domain>

<decisions>
## Implementation Decisions

### DEC-01 — WWXRP rig mechanism (`_rigWwxrpResult`)
- **D-01: R2 — score-bearing rig.** Narrow the rig's eligible-cell pool to cells that actually
  raise S under Variant-2: an unmatched **non-hero symbol** (always +1), or an unmatched
  **color on a quadrant whose symbol already matched** (color "unlocks" → +1). Exclude no-op
  colors (a color on a quadrant whose symbol is still unmatched buys nothing). This preserves
  the **display==score-honest** invariant (every visible forced match also moves the score) and
  a real ~60% near-win lift (RIG-03). The existing **m≥7 cap stays**, so the rig can never
  manufacture S=9 → **P(S=9) invariant** (RIG-02).
  - Generator: `p_score_distribution_rigged` is re-derived to force only score-bearing cells,
    with an explicit **empty-eligible-pool** case — when M≤6 but the only unmatched cells are
    the (excluded) hero symbol and no-op colors, there is no lift that round.
  - Rejected R1 (leave the pool as-is, accept no-op forces): not actually simpler — the rigged
    distribution must be re-derived for Variant-2 regardless — and it breaks display==score
    honesty and dilutes the lift. No upside.

### DEC-02 — EV-equality across picks (the Variant-2 wrinkle)
- **D-02: Option A — 5 per-N tables, averaged over hero placement.** Variant-2 couples color to
  symbol, so the **hero quadrant's gold-ness** now shifts P_N(S): within a fixed N, a hero-gold
  ticket and a hero-common ticket have slightly different score distributions, so one per-N
  table can no longer be *exactly* EV-equal across both sub-cases.
  - **GEN still measures and reports** the worst-case drift between the hero-gold and
    hero-common sub-cases (free — no contract cost; satisfies EVEQ-01).
  - **Escalation to Option B is deprioritized.** USER ruling: residual gold-payout drift is a
    **don't-care** (explicitly for WWXRP — "worthless shitcoin, dont worry about it"). Do NOT
    add per-`(N, hero-is-gold)` tables (~8–9 tables + a `_getBasePayoutBps` dispatch tweak) for
    ordinary drift. Only revisit B if the measured drift is *grossly* outside the generator's
    existing ~0.5 centi-x neutral-or-just-under tolerance (not expected).
  - **Solvency note (why A is safe regardless):** the generator already guarantees every per-N
    table is neutral-or-just-under 100 centi-x (`assert ev_frac <= 100`). Under Option A a
    hero-gold vs hero-common ticket of the same N differ only by a hair of RTP and **both stay
    ≤100** — the house is never EV-negative, so A introduces no solvency risk.

### DEC-03 — Pay floor stays S≥2
- **D-03: Yes — pay floor S≥2 (confirmed).** Under Variant-2: a lone ordinary (non-hero) symbol
  = S=1 → pays 0; the hero symbol alone = S=2 → pays; a full color+symbol double on one quadrant
  = S=2 → pays. So "a bare ordinary symbol wins nothing; you need the hero or a full double."
  Matches the foil precedent's "double matters"; consistent with SCORE-02. USER: "payout stays
  min >=s2".

### Claude's Discretion
- The exact internal form of the re-derived `p_score_distribution_rigged` (enumeration order,
  how the empty-eligible-pool case is expressed) is an implementation detail for GEN, provided
  the self-asserts hold (per-N basePayoutEV ∈ (99,100] honest **and** rigged; bonus-EV = 5.000%;
  all WWXRP factors < 2^64; rigged P(S=9) == honest P(S=9)).
- Doc-comment wording refresh on `_score` / `_rigWwxrpResult` / the constant blocks.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner) MUST read these before planning or implementing.**

### Milestone scope
- `.planning/ROADMAP.md` — Phase 452 GEN success criteria; the 452→456 sequence; the
  generator-first posture and the single approval gate (453 IMPL).
- `.planning/REQUIREMENTS.md` — GEN-01/02/03, EVEQ-01, the DEC-01/02/03 table, Out-of-Scope,
  and the contract anchors (§Anchors).

### The generator (the artifact this phase rewrites)
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — **canonical byte-reproduce
  source.** Currently encodes old `S = A + 2H` + the variant-B rigged dist (`ordinary-only +1,
  60%, M≤6 gate`). Phase 452 rewrites it for Variant-2 (honest + R2-rigged), holding the same
  calibration + self-asserts. `_S9` pins (`S9_PIN`) and the WWXRP `_ROI_` family stay untouched.
- `.planning/notes/degenerette-recalibration/model_wwxrp_rig.py` — scoping model for the rig.

### The contract surface (read-only this phase; edited in 453)
- `contracts/modules/DegenerusGameDegeneretteModule.sol`:
  - `_score` ~L1053 — the rule being changed to Variant-2 (SCORE-01).
  - `_rigWwxrpResult` ~L1299 — the rig being adapted to R2 (RIG-01/02/03). Note the current
    pass-1 builds `u` = unmatched-ordinary-cell count (color any quadrant + non-hero symbol);
    R2 narrows this pool to score-bearing cells.
  - `_getBasePayoutBps` ~L1175 — per-N table dispatch (`isWwxrp` selects the `_RIG_` family;
    S=9 pin shared). Option A keeps this dispatch shape unchanged.
  - `_wwxrpRoi` ~L1259 + `_roiBpsFromScore` ~L1225 — the ROI / WWXRP-RTP curves held fixed
    (INV-01/02).
  - constant blocks ~L283-360 — regenerated verbatim from the script in 453.
- Foil precedent: commit `16225de6` — `DegenerusGameFoilPackModule._tryClaimFoilMatch` shipped
  the same Variant-2 color-gated-by-symbol rule for the foil *match* (T∈0..8, pay T≥4). This is
  the proven shape being ported into the core betting engine.

### Verification gates (relevant at 454 TST, named here for traceability)
- `test/stat/DegenerettePerNEvExactness.test.js` — per-N byte-reproduce + EV-exactness oracle.
- `test/stat/DegeneretteBonusEv.test.js` — 5.000% bonus-EV oracle.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `derive_5_tables.py` self-assert + PASS-ALL pattern: per-N `basePayoutEV ∈ (99,100]`,
  `ETH bonus EV = 5.000%`, `factors < 2^64`, `rigged P(S=9) == honest P(S=9)`. The rewrite
  keeps this exact assert harness — it is what makes the regen trustworthy before any `.sol`.
- The `SHAPE`/`S9_PIN`/residual-absorption solve (`_solve_table`) is currency-agnostic and is
  reused unchanged for the Variant-2 honest and R2-rigged distributions — only the *probability
  distribution* feeding it (`p_score_distribution` / `p_score_distribution_rigged`) changes.
- `_getBasePayoutBps` / `_wwxrpFactor` / `_fullTicketPayout` already take an `isWwxrp` flag and
  a separate `_RIG_` constant family — Variant-2 reuses this split as-is (no new dispatch under
  Option A).

### Established Patterns
- **S=9 = all-8-axes, structurally pinned.** Both old and Variant-2 scoring make S=9 the
  all-doubles event; the pins (`QUICK_PLAY_PAYOUT_N{N}_S9`) and P(S=9) are a relabel, never
  recomputed. The Variant-2 rewrite must preserve `rig[9] == honest[9]` (existing assert).
- **m≥7 rig cap** is the mechanism that keeps P(S=9) invariant under the rig — carried into R2
  unchanged.
- **Neutral-or-just-under house edge:** every base table asserts EV ≤ 100 centi-x. This is what
  makes Option A solvency-safe despite the hero-goldness drift.

### Integration Points
- The generator's stdout `FINAL PASTE-READY CONSTANTS` block is the diff target for the TST
  byte-reproduce gate and the source the 453 IMPL diff pastes verbatim. GEN produces it; IMPL
  consumes it; TST re-derives and diffs.

</code_context>

<specifics>
## Specific Ideas

- USER on DEC-02: "if the gold-payout is slightly different for wwxrp I don't care it's a
  worthless shitcoin, dont worry about it." → Option A, drift accepted, no Option-B escalation
  for ordinary drift. Consistent with the standing ruling that WWXRP RTP>100% / WWXRP-worthless
  is by-design (see `degenerette-wwxrp-rtp-by-design` memory).
- USER on DEC-01: "do r2". USER on DEC-03: "payout stays min >=s2".

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Out-of-scope items are already enumerated in
`.planning/REQUIREMENTS.md` §Out of Scope: foil match rescore, activity-score curves, the
currency split, bet placement, pools/solvency paths.)

</deferred>

---

*Phase: 452-GEN (generator-first; NO contract edit)*
*Context gathered: 2026-06-21*
