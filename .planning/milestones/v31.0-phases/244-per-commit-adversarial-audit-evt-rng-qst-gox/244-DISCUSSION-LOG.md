# Phase 244: Per-Commit Adversarial Audit (EVT + RNG + QST + GOX) — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `244-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 244 — Per-Commit Adversarial Audit (EVT + RNG + QST + GOX)
**Areas discussed:** QST-05 gas-savings reproduction (1 area; all others auto-decided via Phase 230 / 237 / 238 / 243 precedents)

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Plan split + wave topology | 4-plan single-wave parallel (recommended) vs 5-plan vs 2-plan | (auto-decided) |
| Deliverable shape + cross-REQ overlap | Single consolidated `audit/v31-244-PER-COMMIT-AUDIT.md` + per-REQ closure (recommended) vs per-commit files vs single-pass multi-REQ | (auto-decided) |
| QST-05 gas-savings reproduction | Methodology + verdict bar | ✓ |
| Phase 245 hand-off + REFACTOR_ONLY proof | Pre-flag SDR/GOE candidates + side-by-side prose with named-element reasoning (recommended) vs strict scope / bytecode-diff | (auto-decided) |

**User's choice:** Discuss QST-05 only; auto-decide all other areas via prior-phase precedents.

**Notes:** User has demonstrated a strong preference for "auto-decide via precedents" mode (Phase 243 CONTEXT). The strong shape of v29.0 Phase 231-234 (per-feature plan split) + v30.0 Phase 238 (single-wave parallel) + Phase 243 (consolidated single-file deliverable + per-REQ closure + scope-guard deferral) made auto-decision low-risk for the other 3 areas. QST-05 surfaced as the genuinely contested area because the user's `feedback_gas_worst_case.md` rule directly collides with the v31.0 milestone READ-only constraint.

---

## QST-05 Gas-Savings Reproduction

### Question 1 — Methodology

| Option | Description | Selected |
|--------|-------------|----------|
| Theoretical-only + INFO default (Recommended) | Derive theoretical worst-case from code inspection; verdict on direction match; INFO-unreproducible if magnitude unverifiable | |
| Theoretical + opportunistic existing-test sampling | Theoretical-WC primary; existing-test deltas as supplementary evidence when explicitly mapped | |
| Default INFO-unreproducible across all 3 claims | Skip theoretical-WC entirely; mark all 3 INFO up-front | |
| Bytecode-delta-only (no gas) | `forge inspect bytecode` deployed-bytecode delta; structural-change verification only; magnitude is INFO commentary | ✓ |

**User's choice:** Bytecode-delta-only (no gas)

**Notes:** This is a more conservative read than the recommended "Theoretical-only" option — the user opted to remove gas measurement from QST-05 verification entirely and treat it as a structural-change verification. This honors `feedback_gas_worst_case.md` (don't run existing benchmarks) AND READ-only (no new tests) AND eliminates the theoretical-WC derivation step entirely. The trade-off is that magnitude (-142k / -153k / -76k WC claims) becomes INFO-only commentary rather than gated evidence — a deliberate scope reduction for QST-05.

### Question 2 — Verdict Bar

| Option | Description | Selected |
|--------|-------------|----------|
| Direction-only bar (Recommended) | SAFE = direction matches + savings exist + no regression on adjacent paths; magnitude is INFO-only | ✓ |
| Magnitude-tolerant bar (±20%) | SAFE = direction matches AND magnitude within ±20% of claim | |
| Magnitude-strict bar (±5%) | SAFE = magnitude within ±5% | |
| INFO-only bar (no SAFE) | Treat QST-05 as INFO-track unconditionally; never SAFE | |

**User's choice:** Direction-only bar

**Notes:** Combined with the bytecode-delta-only methodology (Q1 answer), this means SAFE for QST-05 = (a) bytecode delta shows the structural changes present (dropped `freshEth` return, `ethFreshWei→ethMintSpendWei` rename, removed dead branches verifiable in opcode delta) AND (b) direction matches the claim (deployed bytecode is smaller OR opcode-pattern changes match expected savings sites) AND (c) no regression on adjacent paths. INFO-unreproducible = direction can't be confirmed from bytecode delta alone (e.g., compiler optimizer reordered surrounding code so the QST-05 hunk's contribution is not isolatable). Magnitude is NOT enforced — gas magnitude is unreproducible under READ-only-+-bytecode-only regime.

---

## Final Check

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context | Lock all auto-decided areas + write CONTEXT.md | ✓ |
| Explore more gray areas | Surface additional gray areas (bytecode-diff metadata stripping / RNG-02 KI-envelope wording / EVT-02 BAF-coupling depth / severity pre-classification) | |

**User's choice:** Ready for context

**Notes:** All other gray areas explicitly accepted as auto-decided per precedent. CONTEXT.md captures both the auto-decisions (D-01, D-02, D-04, D-05, D-06, D-07, D-08, D-16, D-17, D-18, D-19, D-20, D-21, D-22) and the explicitly-discussed QST-05 decisions (D-13, D-14).

---

## Claude's Discretion

The following areas were left to planner / executor discretion per CONTEXT D-04 / D-08 / D-09 / D-15 / D-16 final bullets:

- Exact within-section ordering of per-REQ verdict tables vs prose blocks
- Whether 244-04 GOX consolidation is inlined in the GOX SUMMARY commit OR a separate `244-04-CONSOLIDATION.md` artifact
- Whether to include a per-REQ closure heatmap at the top of the consolidated deliverable
- Whether QST-05 bytecode evidence is inlined or linked to a companion file
- Severity pre-classification timing (Phase 244 vs `TBD-246`) — recommended pre-classify per D-08 unless ambiguous
- Whether to add "verdict count card" headers per bucket section
- Phase 245 Pre-Flag subsection grouping format (per-REQ / per-file / per-vector)

---

## Deferred Ideas

The following ideas surfaced during analysis but were noted for future phases / milestones:

- **Differential-fuzz QST-05 reproduction** — gold-standard gas-delta measurement under controlled state; blocked by READ-only constraint; future-milestone candidate (e.g., v32.0 "gas-claim verification" with READ-only lifted for `test/`)
- **Cross-milestone severity calibration sweep** — formal cross-milestone severity-rubric standardization (Codex of Severity); future audit-tooling milestone
- **Bytecode-delta automated CI gate** — wire QST-05 bytecode-diff methodology into PR CI; out of READ-only v31.0 scope; future-milestone candidate
- **Phase 245 Pre-Flag → SDR/GOE plan inheritance protocol** — D-16 leaves consumption pattern to Phase 245's CONTEXT; defer to Phase 245 CONTEXT discussion

---

*End of Phase 244 discussion log.*
