# Phase 236: Regression + Findings Consolidation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `236-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 236-regression-findings-consolidation
**Areas discussed:** FINDINGS-v29.0.md shape, KNOWN-ISSUES.md policy (FIND-02)

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Plan split axis | 217 style (consolidation + regression appendix) vs 229 style (findings + tracking sync) vs 3-plan split | |
| FINDINGS-v29.0.md shape for a near-clean cycle | Shape for 3 SAFE-INFO candidates + per-phase vs per-type sectioning | ✓ |
| KNOWN-ISSUES.md policy (FIND-02) | New entries + back-refs + promotion scope | ✓ |
| Regression sweep methodology | Text-trace vs test-runs vs both | |

**User's choice:** FINDINGS-v29.0.md shape + KNOWN-ISSUES.md policy. Plan split defaults to 217 style; regression methodology defaults to text-trace at HEAD.

---

## FINDINGS-v29.0.md Shape

### Q1: How should the 3 SAFE-INFO carry-in candidates appear in FINDINGS-v29.0.md?

| Option | Description | Selected |
|--------|-------------|----------|
| Full v27.0-style INFO blocks | Each carries F-29-NN ID with full per-finding table; consistent with v27/v28 precedent even at low count | ✓ |
| Compressed 'Observations' section | One short section listing the 3 as bullets; acknowledges clean-cycle nature | |
| Full blocks + clean-cycle callout | Full blocks plus a top-of-document executive callout | |

**User's choice:** Full v27.0-style INFO blocks (Recommended).

### Q2: Section by originating phase or group by observation type?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-phase sections, phase order | Mirrors v27.0/v28.0 precedent exactly; preserves phase ↔ finding traceability | ✓ |
| Grouped by observation type | Cleaner thematic read but breaks traceability | |
| Flat F-29-01..03 list, no sectioning | Skip subsection headers given small count | |

**User's choice:** Per-phase sections, phase order (Recommended).

### Q3: Regression Appendix detail level (32 prior findings)?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-item table, one row each | ID / Severity / verdict / evidence; 217-02 precedent; heavy but auditable | ✓ |
| Grouped by verdict with per-item list | PASS/REGRESSED/SUPERSEDED subsections with bullet lists | |
| Rollup summary + spot-check table | Paragraph summary plus smaller spot-check table | |

**User's choice:** Per-item table, one row each (Recommended).

### Q4: Executive summary — clean-cycle callout or strict v27.0?

| Option | Description | Selected |
|--------|-------------|----------|
| Strict v27.0 format + concise assessment paragraph | Severity table + 'Overall Assessment' paragraph noting zero on-chain findings | ✓ |
| Prominent clean-cycle banner above severity table | Blockquote banner reads like milestone success marker | |
| Strict v27.0 format, no clean-cycle language | Severity table + standard assessment paragraph only | |

**User's choice:** Strict v27.0 format + concise assessment paragraph (Recommended).

**Notes:** User consistently picked recommended (v27.0-precedent-mirroring) options. The preference is for audit-report consistency over milestone-completion signaling.

---

## KNOWN-ISSUES.md Policy (FIND-02)

### Q1: Which v29.0 items should be promoted to NEW KI design-decision entries?

| Option | Description | Selected |
|--------|-------------|----------|
| BAF event-widening + BAF_TRAIT_SENTINEL=420 pattern (F-29-01/02) | Design pattern for BAF jackpots; sentinel uint16=420 out-of-domain | ✓ |
| 232.1 RNG-index ticket-drain ordering invariant | Hardening fix, not new design decision | |
| 234-01 companion-test-coverage (F-29-03) | Test-tooling observation, not design | |
| None — no new KI entries this milestone | v29.0 is pure re-audit cycle | |

**User's choice:** BAF event-widening + BAF_TRAIT_SENTINEL=420 pattern (Recommended).

**User notes (verbatim):** "we need the 'write buffer can get a different RNG at GAMEOVER' thing mentioned"

**Claude's follow-up:** Identified from 235-05 TRNX-01 audit that this refers to the Gameover path's `_swapTicketSlot` at AdvanceModule:595 drain using `_gameOverEntropy` rather than the daily VRF word. Asked for confirmation of phrasing before locking in.

### Q2: Should existing KI entries get F-29-NN back-references?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — targeted back-refs where v29.0 re-proved the invariant | ~3-4 entries (Gameover prevrandao F-25-08, Decimator over-reserve F-25-12, Lootbox RNG index F-25-07) | ✓ |
| No back-refs — regression appendix alone is sufficient | Avoid churn; wardens chase the appendix | |
| Full cross-ref — every v25/v27 ID gets a v29 marker | Consistent but noisy; implies re-verification that didn't happen | |

**User's choice:** Yes — targeted back-refs where v29.0 re-proved the invariant (Recommended).

### Q3 (confirmation): Is THIS the gameover-RNG subtlety you want disclosed?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — the Round-1/Round-2 drain entropy on the gameover path | Write-buffer tickets drain against `_gameOverEntropy` instead of daily VRF word | |
| Partially — but different angle | Re-phrase based on user's actual meaning | ✓ |
| No — different issue entirely | Different gameover RNG behavior | |

**User's choice:** Partially — with clarification.

**User notes (verbatim):** "I mean that if there was a mid day rng request that swapped ticket write buffers and then, before clearing it, gameover happens, those tickets will use gameover entropy rather than the mid day one that they were 'supposed' to. not a big deal it's all random and there is no way for anyone to really exploit or force this to happen and it is at gameover anyways so who cares. but it does violate my rule that there can be absolutely no non-determinism of any rng consuming stuff"

**Captured:** User surfaced a new protocol invariant — "no non-determinism of RNG-consuming stuff." The gameover path technically violates this invariant when a mid-cycle buffer swap leaves tickets in the write buffer that then drain under `_gameOverEntropy` instead of the anticipated daily/lootbox VRF word. Non-exploitable (gameover trigger is uncontrollable by an attacker at a specific mid-cycle state) but disclosure-worthy per user's invariant rule.

### Q4: How should the gameover RNG substitution item be routed?

| Option | Description | Selected |
|--------|-------------|----------|
| New F-29-04 INFO + KNOWN-ISSUES entry | FINDINGS block + paired KI entry; ID anchors the disclosure | ✓ |
| KNOWN-ISSUES.md entry only — no F-29 ID | Avoid retrofitting a 'finding' post-hoc | |
| Both — F-29-04 in FINDINGS + fuller KI entry | Same as option 1 but expanded KI content | |

**User's choice:** New F-29-04 INFO + KNOWN-ISSUES entry (Recommended).

### Q5: Severity for F-29-04?

| Option | Description | Selected |
|--------|-------------|----------|
| INFO — accepted design, no exploit path | Matches user framing + F-25-08 same-domain acceptance | ✓ |
| LOW — determinism-invariant violation | Elevate because it technically violates a stated invariant | |
| N/A — KI-only routing selected above | Not applicable (F-29-04 routing chosen) | |

**User's choice:** INFO — accepted design, no exploit path (Recommended).

---

## Final Check

### Q: Ready to create context, or explore more gray areas?

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context | Write CONTEXT.md + DISCUSSION-LOG.md, commit, surface next steps | ✓ |
| Explore more gray areas | Additional gray areas: BAF consolidation 1 vs 2 IDs, FIND-03 exec table scope, commit strategy | |

**User's choice:** I'm ready for context (Recommended).

---

## Claude's Discretion

- Plan split axis — deferred to planner; ROADMAP leans 217 style (2 plans: consolidation + regression appendix)
- Regression sweep methodology — defaulted to text-trace at HEAD `1646d5af` per 217-02 precedent
- Tracking sync timing — fold into Plan 236-02 OR defer to `/gsd-complete-milestone`; planner decides
- F-29-01 vs F-29-02 BAF consolidation (1 block or 2) — planner decides based on narrative clarity
- Wave structure and commit strategy — planner decides

## Deferred Ideas

- Cross-milestone finding-rate trend analysis (v25 → v27 → v29) — nice-to-have, not required by FIND-01/02/03
- Standalone "Protocol Invariants" reference doc documenting the "RNG-consumer determinism" invariant formally — candidate for v30+ or out-of-cycle docs phase
- 232.1 RNG-index ordering invariant as standalone KI entry — rejected this milestone (D-09); revisit only if a future warden misreads the ordering code
- HIGHER-severity promotion via cross-phase amplification — none identified; v29.0 findings are on distinct surfaces
