---
phase: 392-entropy-and-econ
plan: 03
subsystem: reward-game-theory / ECON audit (dual-net adjudication)
tags: [audit, econ, money-pump, ev-neutrality, whale-pass, quest-streak, skeptic-gate, both-nets]
requires:
  - 392-01-COUNCIL-NET.md (NET 1 — gemini on record, codex skipped)
  - 388-02-FINDING-CANDIDATES.md (FC-392 owned ECON leads)
  - PAPER-REWARD-CHANGES-BRIEF.md (the documented EV claims to verify)
  - byte-frozen subject a8b702a7 (contracts tree 2934d3d8)
provides:
  - 392-03-CLAUDE-NET.md (NET 2 — independent Claude adversarial ECON net)
  - 392-FINDINGS-ECON.md (the ECON-slice adjudication: both nets, skeptic gate, per-item verdicts)
  - ECON-01..06 attested at a8b702a7 (0 CONFIRMED contract findings)
affects:
  - 392-04 (BURNIE slice + the consolidated 392-FINDINGS.md index ties both slices)
  - 396 TERMINAL (recommended post-reset codex second-source re-run of the two HIGH candidates)
tech-stack:
  added: []
  patterns: [dual-net both-on-record, skeptic-dual-gate, per-leg-liquid-accounting, in-code-EV-arithmetic-verification, audit-only-routing]
key-files:
  created:
    - .planning/phases/392-entropy-and-econ/392-03-CLAUDE-NET.md
    - .planning/phases/392-entropy-and-econ/392-FINDINGS-ECON.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
decisions:
  - "ECON-04 money pump REFUTED via per-leg liquid accounting (kicker illiquid flip-gated ≈0.030·V, box sub-unity, value-in won-first) + skeptic dual-gate — no HIGH"
  - "ECON-06 streak pump REFUTED at source (afking slot-0 skip + completionMask dedup + mutually-exclusive compute) + skeptic dual-gate — no HIGH"
  - "ECON-05 whale-pass BY-DESIGN (P(S=9)≈6.74e-8 / ~99M boxes-per-pass; global per-bracket flag caps supply)"
  - "0 CONFIRMED contract findings; ECON-01..06 attested document-only at a8b702a7; subject byte-frozen"
  - "codex capped — post-reset codex second-source re-run of the two HIGH candidates recommended (carry to 396)"
metrics:
  duration: ~50min
  completed: 2026-06-15
  tasks: 2
  files_created: 2
  files_modified: 3
  commits: 3
---

# Phase 392 Plan 03: NET 2 (Claude) + Adjudication — ECON Slice Summary

NET 2 (the deep Claude adversarial net) is on record for the ECON reward-game-theory slice independent of
the council, and the ECON slice (ECON-01..06 + FC-392-01..10 + FC-392-14/-15) is adjudicated with BOTH nets
on record, the skeptic dual-gate applied to the two gemini HIGH candidates (the ECON-04 money pump + the
ECON-06 streak pump — **both REFUTED at the frozen source**), the EV-neutrality re-verified in code against
the PAPER brief, the two genuine EV changes confirmed in code, the money-pump composition searched with
per-leg liquid accounting, the whale-pass acquisition cost quantified, and the bounded-accrual swept —
**0 CONFIRMED contract findings; ECON-01..06 attested document-only at `a8b702a7`; subject byte-frozen
throughout.**

## What was built

- **`392-03-CLAUDE-NET.md`** (NET 2, 466 lines): the independent Claude adversarial net. §0 frozen-source
  pin table; §1 per-surface bounded-accrual sweep (ECON-01); §2 in-code EV-neutrality arithmetic matched to
  every PAPER-brief claim (ECON-02); §3 the two-EV-change confirmation (ECON-03) + FC-392-04 stale comment;
  §4 the money-pump composition search with per-leg liquid wei/value accounting + the skeptic dual-gate
  (ECON-04 — the PRIORITY); §5 the whale-pass P(S=9) quantification + per-bracket supply-cap proof
  (ECON-05/FC-392-07); §6 the streak-machinery trace + skeptic dual-gate (ECON-06/FC-392-01/-02); §7 the
  EV-cap / sentinel / affiliate leads + the council fold-in (FC-392-03/-05/-10/-14/-15); §8 the provisional
  verdict summary.
- **`392-FINDINGS-ECON.md`** (the adjudication deliverable, 183 lines): §1 both-nets-on-record attestation
  (codex-skip + post-reset re-run flagged); §2 the per-item verdict table (every ECON req + every owned lead
  with a CONFIRMED/REFUTED/BY-DESIGN/MONITOR verdict + settling cite); §3 the skeptic gate (the two HIGH
  candidates run through the dual-gate, recorded); §4 routing (0 CONFIRMED; carried INFO/MONITOR;
  FC-392-08 cross-refs → 390/393; codex second-source routed); §5 the per-req re-attestation line.

## The two priority adjudications (gemini HIGH candidates — both REFUTED)

### ECON-04 money pump (PRIORITY) — REFUTED

The gemini HIGH claim: a player at score ≥6,000 (EV multiplier = 100% neutral) recycles 1 ETH of claimable
into boxes, expects 1 ETH back, AND collects 0.1 ETH BURNIE flip-credit as "pure profit" = a ≥110% RTP loop.

Per-leg liquid accounting against the frozen source settles it:
- The 10% recycle kicker is **illiquid BURNIE flip-credit** (`Mint:1740-1745` → `coinflip.creditFlip` →
  `_addDailyFlip(...,false,false)`, `Coinflip:903-908`). It must SURVIVE a 50/50 survival flip (×0.5) and
  carries the BURNIE peg-vs-realizable discount (≈0.59) ⇒ realized ≈ **0.030·V**, not the 0.10·V gemini
  treats as cash.
- The box at neutral EV returns its OWN sub-unity reward components in liquid ETH (`_applyEvMultiplierWithCap`
  returns `amount` unscaled at neutral, `Lootbox:483-485`; 40% of value is non-ETH: BURNIE / WWXRP / a
  finite DGNRS pool; tickets are future-level + variance-discounted). The 100% multiplier means no value
  added — NOT a guaranteed 1.0-ETH liquid return.
- The value-in `V` is **real WON claimable** (a positive-variance event must occur first).
- The presale 25% box-credit is box-spend-restricted + presale-windowed; the ETH-spin recirc is depth 1
  (`allowEthSpin=false`, `Degenerette:1463`); the EV uplift is 10-ETH/(player,level) capped.

Per-iteration liquid value-out (< V) < value-in (V) ⇒ no closed positive loop. The skeptic dual-gate fails
the profitability condition. The "cap only bounds the uplift" claim is harmless: the floor (≤100%) is never
a profit source. **REFUTED — no HIGH.**

### ECON-06 streak pump — REFUTED

The gemini HIGH claim: toggling afking↔manual on the same day harvests BOTH an afking-delivered streak AND a
manual slot-0 +1, breaching the ≤3/day bound.

The machinery trace at the frozen source settles it: `completionMask` (per-day, per-slot) dedups
(`Quests:1708-1711`); the afking branch makes slot-0 streak-NEUTRAL specifically to prevent the
double-channel (`if (!afking)` block skipped, `Quests:1745-1752`); `_effectiveQuestStreak` reads the manual
OR the afking compute MUTUALLY-EXCLUSIVELY, never summed (`Storage:2284-2293`). Re-completing slot 0 the
same day returns `false` (mask bit set). The double-channel does not exist. The skeptic dual-gate confirms:
no double-count, and even a transient over-count is a ramp-SPEED matter (the ceilings are FIXED at 40,000 EV
/ 30,500 ROI / streak-clamp-100, all < the 65,534 hard cap) = the documented "halve + uncap" intent.
**REFUTED — no HIGH.**

## Deviations from Plan

None — the plan executed as written. The only path adjustment was the frozen-source path (storage is at
`contracts/storage/DegenerusGameStorage.sol`, not the root path the plan's interface comment assumed) —
re-pinned and read correctly via `git show a8b702a7:`. No contract source was touched.

## Authentication gates

None.

## Known Stubs

None — both deliverables are complete adjudication documents.

## Threat Flags

None — this is an audit-only documentation plan over a byte-frozen subject; it introduces no contract
surface. (The frozen subject's own ECON surface is adjudicated, not modified.)

## Routing

- **0 CONFIRMED contract findings.** ECON-01..06 attested document-only at `a8b702a7`.
- **Carried MONITOR/INFO** (no contract change): FC-392-04 stale EV-band comment (`Lootbox:472-473`);
  FC-392-03 documented decimator ramp; FC-392-15 carried v62 affiliate-score asymmetry (unchanged).
- **Cross-refs:** FC-392-08 solvency-CEI half → 390 SOLVENCY-SPINE (FC-390-01/-02); permissionless-race
  half → 393 PERMISSIONLESS-COMPOSITION (FC-393-03); ECON cap-RMW half BY-DESIGN here.
- **codex second-source (ROUTED):** codex was capped. A post-reset codex re-run of the two HIGH candidates
  (ECON-04, ECON-06) is RECOMMENDED to second-source NET 2's refutation; carry to 396 terminal
  council-on-refuted if still capped.

## Self-Check: PASSED

- `392-03-CLAUDE-NET.md` FOUND; commit `3e59899a` FOUND.
- `392-FINDINGS-ECON.md` FOUND; commit `4cf91f2c` FOUND.
- `git diff a8b702a7 -- contracts/` EMPTY (subject byte-frozen throughout).
- All 18 IDs (ECON-01..06 + FC-392-01..10 + FC-392-14/-15) present in both deliverables; both-nets table,
  skeptic gate, money-pump composition result, EV-neutrality arithmetic, whale-pass quant all present.
