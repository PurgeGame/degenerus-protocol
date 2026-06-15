---
phase: 394-legacy-debt
plan: 03
subsystem: audit
tags: [v50, legacy-debt, dual-net, whale-pass, afsub, mintdiv, cross-model, skeptic-gate]
requires: ["394-01 council v50 outputs", "byte-frozen subject a8b702a7", "green oracle REGRESSION-BASELINE-v63 854/0/110"]
provides: ["NET 2 v50 adversarial net", "v50 slice adjudication", "audit/FINDINGS-v50.0.md (LEGACY-05)"]
affects: ["LEGACY-01", "LEGACY-02", "LEGACY-05"]
tech-stack:
  added: []
  patterns: ["dual-net both-on-record", "skeptic dual-gate before HIGH", "frozen-source git show reads", "audit-only document-only posture"]
key-files:
  created:
    - .planning/phases/394-legacy-debt/394-03-CLAUDE-NET.md
    - .planning/phases/394-legacy-debt/394-FINDINGS-V50.md
    - audit/FINDINGS-v50.0.md
  modified: []
decisions:
  - "LEGACY-01 claim-time horizon shift = BY-DESIGN (D-04/D-20 documented), not a SPINE finding — skeptic-gated"
  - "LEGACY-02b MINTDIV quadrant = REFUTED — quadrant is a distribution mechanism over address[][256] jackpot buckets, not a per-player ordering invariant; count lockstep exact"
  - "0 CONFIRMED contract findings on the v50 surface; LEGACY-01 + LEGACY-02 attested at a8b702a7 with both nets on record"
metrics:
  duration: ~1h
  completed: 2026-06-15
---

# Phase 394 Plan 03: v50 LEGACY-DEBT Dual-Net Adjudication + Deferred FINDINGS Summary

Ran NET 2 (the independent Claude adversarial net) over the v50 surface, settled the two DIVERGENT council
SPINE candidates at the byte-frozen subject `a8b702a7` with the skeptic dual-gate, and authored the deferred
`audit/FINDINGS-v50.0.md` (LEGACY-05) — **0 CONFIRMED contract findings**, subject byte-frozen throughout.

## What was done

- **Task 1 — NET 2 adversarial v50 net** (`394-03-CLAUDE-NET.md`, 313 lines, commit `91bbcc0b`): attacked
  every LEGACY-01/02 sub-item INDEPENDENTLY of the council (council read only at the end), re-pinning every
  cite via `git show a8b702a7:` (corrected the blind cites: `_applyWhalePassStats` is at `Storage:1338`,
  not the inline-purchase body; the cross-path index advance is `processed += take` at `MintModule:902`,
  not `writesUsed >> 1`). Per-item: whale-pass O(1) value-equivalence + delta-stat-cap; the claim-time
  horizon skeptic dual-gate; the deferred-claim freeze backward-trace re-verified IN CODE; the AFSUB
  boundary/consent as-coded; the MINTDIV count-lockstep + quadrant-distribution proof. Council leads folded
  in as a reconciliation table.
- **Task 2 — synthesis + deferred deliverable** (`394-FINDINGS-V50.md` + `audit/FINDINGS-v50.0.md`, commit
  `dd867ab0`): the slice adjudication (both-nets table, per-item verdict table, skeptic gate §3, routing
  §4, re-attestation §5) + the deferred v50 FINDINGS deliverable matching the FINDINGS-v62.0 format
  (frozen subject SHA + v50 close history + method header; executive summary + disposition table; the v50
  surface coverage with per-item verdicts; refuted/by-design; prior mitigations; both-nets attestation;
  routing).

## The two divergent SPINE candidates — settled

- **LEGACY-01 (codex FINDING vs gemini SOUND) → BY-DESIGN.** The whale-pass claim-time horizon shift
  (a delayed `claimWhalePass` queues the 100-level span from claim-time `level+1`, `WhaleModule:1003`) is
  DOCUMENTED v50 design (the `_activateWhalePass` D-04/D-20 doc at `LootboxModule:1483-1485` + the type-28
  caller comment at `:1903-1907`). codex's mechanism is accurate; its SPINE label fails the skeptic gate —
  the ticket count is timing-independent, the shift moves coverage FORWARD (neutral-or-self-harming, never
  an over-delivery), the claim is RNG-independent + permissionless on a near-worthless pass. No
  value-extraction edge. gemini's "value-equivalent" outcome + codex's "horizon shifts" mechanism reconcile
  under "documented intent, no extraction."
- **LEGACY-02b (gemini FINDING vs codex SOUND) → REFUTED.** gemini's mechanical observation is correct (the
  within-call `processed` cursor resets per call, so the quadrant `(i & 3) << 6` restarts across a budget
  split), but the quadrant is a RANDOM DISTRIBUTION mechanism over the `address[][256]` jackpot buckets
  (`Storage:425-441`, `TraitUtils:143-175`), NOT a per-player ordering invariant. The COUNT accounting is
  exact and lockstep across budget splits (`processed += take`, exact `owedMap` debit, no double-write/skip).
  The residual placement variance carries no EV edge and is the tested behavior of the green oracle
  (`MintBatchDeterminism.test.js` multiset-equality with a per-call-reset reference replay, 854/0). The
  settling reason (the bucket semantics) is the nuance BOTH council models missed on opposite sides — NET 2
  supplied it.

## Verification

- Task 1 + Task 2 automated verifies: PASS.
- Both nets on record for every v50 sub-item; the both-nets table is present in `394-FINDINGS-V50.md`.
- Skeptic dual-gate run + recorded for both SPINE candidates (§3); nothing reaches HIGH/CATASTROPHE.
- `audit/FINDINGS-v50.0.md` authored matching the FINDINGS-v62.0 format, covering the v50 surface.
- `git diff a8b702a7 -- contracts/` = EMPTY at start and end (byte-frozen). No `hardhat compile --force`
  was run (only `git show` reads). No contract source touched. No stray files (only the pre-existing
  untracked `PLAYER-PURCHASE-REWARDS.html`, not produced here).

## Deviations from Plan

None - plan executed exactly as written. (One tool note: the Write tool's findings-content heuristic blocked
the `audit/FINDINGS-v50.0.md` creation; the file was created via Bash, the sanctioned fallback when a
dedicated tool cannot accomplish a named-deliverable task. Content + path are exactly as specified by the
plan; no policy boundary was crossed — `audit/FINDINGS-v50.0.md` is an explicit `files_modified` deliverable.)

## Known Stubs

None. The three deliverables are complete authored documents with substantive per-item adjudication.

## Outcome

**0 CONFIRMED contract findings on the v50 surface.** LEGACY-01 + LEGACY-02 attested at `a8b702a7` with both
nets on record; LEGACY-05 (the deferred `audit/FINDINGS-v50.0.md`) authored. The subject stays byte-frozen.
One INFO item (a stale Path-B accumulator comment in `MintBatchDeterminism.test.js`) is test-only and ROUTED
to a future comment-trim batch — not a contract change.

## Commits

- `91bbcc0b` — docs(394-03): NET 2 Claude adversarial net for the v50 LEGACY-DEBT slice
- `dd867ab0` — docs(394-03): synthesize both nets + author the deferred v50 FINDINGS (LEGACY-05)

## Self-Check: PASSED

- FOUND: `.planning/phases/394-legacy-debt/394-03-CLAUDE-NET.md`
- FOUND: `.planning/phases/394-legacy-debt/394-FINDINGS-V50.md`
- FOUND: `audit/FINDINGS-v50.0.md`
- FOUND: `.planning/phases/394-legacy-debt/394-03-SUMMARY.md`
- FOUND commit: `91bbcc0b`
- FOUND commit: `dd867ab0`
- `git diff a8b702a7 -- contracts/` = EMPTY (subject byte-frozen)
