# Phase 245: sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `245-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 245 — sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification
**Areas discussed:** claimRedemption ungated-state classification + per-wei accounting formalism (2 areas; plan split + GOE-06 depth auto-decided via Phase 244 precedent)

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Plan split + matrix shape | 2 plans SDR+GOE single-wave parallel (recommended) vs 3 plans (SDR-matrix-foundation + SDR-closures + GOE) vs 1 combined plan. AND SDR-01 matrix representation: giant 6×8 matrix vs per-REQ re-walk. | (auto-decided) |
| GOE-06 emergent-behavior depth | Close 2 Pre-Flag candidates only (recommended, cheaper) vs exhaustive negative-space sweep | (auto-decided) |
| claimRedemption ungated state | Property-to-prove SAFE vs Standalone INFO vs Dual SAFE+INFO | ✓ |
| Per-wei accounting formalism | Prose + spot-check vs Formal invariant-lemma vs Hybrid | ✓ |

**User's choice:** Discuss claimRedemption + per-wei accounting; auto-decide plan split + GOE-06 depth via 244 precedent.

**Notes:** User continues the Phase 243/244 pattern of auto-deciding shape/topology decisions via prior-phase precedent and drilling into discriminators that materially change verdict handling. The 2 selected areas both concern VERDICT BAR calibration (severity classification + proof rigor), not structural shape — which is the area where 244's heavy precedent leaves genuine discretion. Plan split + GOE-06 depth are structural decisions with strong 244 analogs (D-01 per-bucket plan split + D-12 cost-effective rigor), low-risk to auto-decide.

---

## Gray Area 1: claimRedemption Ungated State

### Question — How should the ungated-but-intentional state be classified?

| Option | Description | Selected |
|--------|-------------|----------|
| Property-to-prove SAFE (Recommended) | Absorb into SDR-01/04/05 verdicts; each REQ enumerates adversarial vectors; no standalone finding; assumes implicit gate (`roll != 0`) is stable | ✓ |
| Standalone INFO finding | Emit `SEVERITY: INFO` prose block documenting convention drift; Phase 246 FIND-02 may reclassify; flags future-refactor risk | |
| Dual: SAFE verdict + INFO note | Verdict closes SAFE, separate INFO prose block documents convention drift; most rigorous, slightly more volume | |

**User's choice:** Property-to-prove SAFE

**Notes:** The Phase 244 Pre-Flag L2477 already observed this ungated state and characterized it as "intended design — back-half of 2-step redemption flow, relies on `roll != 0` implicit gate, ETH already segregated via `pendingRedemptionEthValue`." Per CONTEXT.md D-08 taxonomy, INTENTIONAL behavior matching design claim = SAFE, not INFO. The user's choice treats the implicit `roll != 0` gate as algorithmically load-bearing (not a convention accident) — a redemption cannot claim what has not been resolved, so the gate is a structural invariant not a drifted convention. Future-refactor risk is handled by Phase 246 REG-01 regression coverage (if the implicit invariant breaks, regression catches it) rather than by pre-emptive INFO-flag. Matches Phase 244 D-07 per-REQ closure philosophy: audit trail stays clean of hedged observations.

---

## Gray Area 2: Per-Wei Accounting Rigor

### Question — Evidence format for SDR-02 (pendingRedemptionEthValue exactness) + SDR-05 (per-wei conservation across 6 timings)

| Option | Description | Selected |
|--------|-------------|----------|
| Prose + spot-check (Recommended) | Phase 244 style; verdict rows cite code lines, prose narrates entry/exit, one worked example per timing; fast, reviewer-scannable | ✓ |
| Formal invariant-lemma | Explicit entry/exit ledger; ∑_ins == ∑_outs algebraic proof; every mutation site cataloged; per-timing reconciliation; ~2-3x volume, dispute-proof | |
| Hybrid: prose + wei-ledger table | Prose-heavy verdict blocks + compact per-timing wei-ledger table (columns: Timing / Site / IN / OUT / Net / Source line); not full algebraic proof but one-glance column balance | |

**User's choice:** Prose + spot-check

**Notes:** Consistent with the user's pattern of cost-effective rigor (e.g., Phase 244 QST-05 BYTECODE-DELTA-ONLY over theoretical-gas-WC; Phase 244 D-07 per-REQ closure over multi-REQ verdict cells). Phase 244's prose-heavy style produced 87 V-rows across 19 REQs in ~6 hours with 0 finding candidates — the method works. Formal invariant-lemma would significantly extend Phase 245's write-up time + produce a write-up that's harder to reproduce in review (reviewer must follow algebraic reconciliation rather than scan prose citations). The hybrid option was viable but adds a table format that needs its own maintenance; the user opted for the simpler prose-only approach. If Phase 246 reviewer finds prose insufficient, the formal ledger is deferred to a future milestone per Deferred Ideas in CONTEXT.md.

---

## Auto-Decided Areas (per Phase 244 precedent)

### Plan split + matrix shape
- **2 plans single-wave parallel** (245-01 SDR + 245-02 GOE) — matches 244 D-01/D-02 per-bucket parallel split
- **SDR-01 matrix representation: per-REQ re-walk, no mega-matrix** — cleaner grep per REQ, matches 244 D-07 per-REQ closure

### GOE-06 emergent-behavior depth
- **Close 2 Pre-Flag candidates only** (skipped-BAF-pool × drain + wrapper-held-backing conservation) — exhaustive sweep deferred unless either candidate escalates ≥ MEDIUM per CONTEXT D-13

---

## Final Check

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context | Lock all auto-decided areas + write CONTEXT.md | ✓ |
| Explore more gray areas | Surface additional gray areas (SDR-01 foundation-row format / multi-tx drain re-entry depth / KI EXC-03 envelope wording / severity pre-classification) | |

**User's choice:** Ready for context (implicit — completed the 2-question interactive round; no further discussion requested)

**Notes:** CONTEXT.md captures both the 2 explicitly-discussed decisions (D-09 claimRedemption SAFE-absorption, D-10 + D-11 prose + spot-check methodology) AND the auto-decisions (D-01..D-08 plan split + matrix shape + deliverable shape; D-12 + D-13 GOE-06 cost-effective depth; D-14 + D-16 per-REQ methodology details; D-17 cross-cite discipline; D-18 Phase 246 hand-off format; D-20..D-25 scope-boundary carries from 243/244).

---

## Claude's Discretion

The following areas were left to planner / executor discretion per CONTEXT D-04 / D-08 / D-15 / D-16 final bullets + explicit carry from 244 Claude's Discretion:

- Exact within-section ordering of per-REQ verdict tables vs prose blocks
- Whether 245-02 GOE consolidation is inlined in 245-02 SUMMARY commit OR a separate `245-02-CONSOLIDATION.md` artifact
- Whether to include a per-REQ closure heatmap at the top of the consolidated deliverable
- SDR-01 foundation-row format (one-row-per-timing vs one-row-per-timing × reachable-path)
- Severity pre-classification timing (Phase 245 pre-classify vs TBD-246)
- Per-bucket "change count card" headers (mirroring 244 per-bucket cards)
- GOE-06 sweep-expansion scope if triggered per D-13
- Phase 246 Input subsection grouping format (by-REQ / by-severity / by-file)

---

## Deferred Ideas

The following ideas surfaced during analysis but were noted for future phases / milestones (captured in CONTEXT.md `<deferred>`):

- **Exhaustive GOE-06 negative-space sweep** — construct cross-feature scenarios from scratch beyond the 2 pre-flagged candidates; deferred unless escalation per D-13
- **Formal invariant-lemma style for per-wei conservation** — explicit algebraic ∑_ins == ∑_outs proofs; deferred per user choice of prose + spot-check
- **claimRedemption as standalone INFO finding-candidate** — document ungated entry as convention-drift; deferred per user choice of property-to-prove SAFE
- **SDR-01 mega-matrix representation** — 6-timings × 8-REQs monolithic table; deferred per auto-decided per-REQ re-walk
- **Multi-tx drain STAGE_TICKETS_WORKING formal re-entry model** — state-machine model of drain re-entry; deferred (SDR-03 covers via prose per D-14)
- **Phase 245 Pre-Flag → Phase 246 FIND-02 severity calibration protocol** — D-18 specifies the hand-off format; protocol refinement deferred to future milestone if needed

---

*End of Phase 245 discussion log.*
