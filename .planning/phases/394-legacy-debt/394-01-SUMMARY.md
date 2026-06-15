---
phase: 394-legacy-debt
plan: 01
subsystem: audit-net
tags: [council, cross-model, v50, legacy-debt, whale-pass, afsub, mintdiv, net-1]
requires:
  - "the byte-frozen subject a8b702a7 (FOUNDATION 388)"
  - "the neutral v50 council prompt (394-01-COUNCIL-PROMPT-V50.md)"
provides:
  - "NET 1 (cross-model council) ON RECORD for the v50 legacy-debt slice (LEGACY-01, LEGACY-02)"
  - "raw gemini + codex per-item traced audits under council/"
  - "394-01-COUNCIL-NET.md — the capture record + RAW leads routed to 394-03 Wave-2 adjudication"
affects:
  - "394-03 (Wave-2 Claude net + adjudication) — folds the council leads in before any per-item verdict"
  - "the deferred audit/FINDINGS-v50.0.md (authored at 394-03/396)"
tech-stack:
  added: []
  patterns:
    - "council.sh dual-CLI fan-out (gemini + codex in parallel, skipped[] non-fatal)"
    - "neutral charge + by-design exclusion list + numbered break-targets + per-item FINDING/SOUND output"
    - "RAW capture only at NET 1; adjudication deferred to Wave-2 (both-nets-on-record rule, AUDIT-V63-PLAN §2)"
key-files:
  created:
    - ".planning/phases/394-legacy-debt/394-01-COUNCIL-NET.md"
    - ".planning/phases/394-legacy-debt/council/v50.gemini.txt"
    - ".planning/phases/394-legacy-debt/council/v50.codex.txt"
    - ".planning/phases/394-legacy-debt/council/v50.council.json"
  modified:
    - ".planning/phases/394-legacy-debt/394-01-COUNCIL-PROMPT-V50.md (authored + committed prior session 691315c5)"
decisions:
  - "codex usage limit RESET — both gemini + codex on record this run; skipped[] EMPTY; no post-reset codex re-run owed for THIS slice (the 392/393 carry → 396 still stands separately)"
  - "the two council FINDINGS are DIVERGENT + cross-contradicting (codex FINDING LEGACY-01 vs gemini SOUND; gemini FINDING LEGACY-02b vs codex SOUND) — routed RAW to 394-03, not adjudicated here"
metrics:
  duration: "~25 min (continuation — Task 1 pre-committed; Task 2 fan-out + capture this session)"
  tasks_completed: 2
  files_touched: 7
  completed: 2026-06-15
---

# Phase 394 Plan 01: LEGACY-DEBT v50 Slice — NET 1 (Cross-Model Council) Summary

NET 1 (the Gemini + Codex council) is ON RECORD for the full v50 legacy-debt slice (LEGACY-01 whale-pass
O(1) deferred-claim path + box-open record; LEGACY-02 AFSUB pass-gating + OPEN-E re-attest + MINTDIV index
alignment) against the byte-frozen subject `a8b702a7` — BOTH models returned substantive per-item traces
this run (codex's usage cap reset), and the two FINDINGS they raised are DIVERGENT and cross-contradicting,
the ideal input for the Wave-2 skeptic dual-gate at 394-03.

## What was done

- **Task 1 (pre-committed by prior session, `691315c5`):** authored `394-01-COUNCIL-PROMPT-V50.md` — the
  neutral council prompt (250 lines) charged against `a8b702a7`, matching the approved 391/392 shape:
  header role + `git show a8b702a7:...` read convention, the USER-locked threat-priority line (freeze
  DOMINANT / value-non-equivalence SPINE / access confirmatory), the trust-boundary framing, the
  KNOWN-BY-DESIGN exclusion list (AFSUB inclusive boundary intended; OPEN-E operator-approval IS the trust
  boundary; whale-pass/WWXRP economics by-design; genesis self-break; lootbox-timing not a player edge), the
  three v50 items as dedicated numbered break-targets, and the per-finding FINDING/VERIFIED-SOUND output
  format. No verdict pre-stated. Verified: passes all automated checks (a8b702a7, LEGACY-01/-02, whale-pass
  / AFSUB / OPEN-E / MINTDIV / value-equiv / freeze terms).

- **Task 2 (this session, `0dab499d`):** cleared the stale 0-byte `.err` files from the prior interrupted
  fan-out, re-ran `council.sh --out-dir .../council --label v50 .../394-01-COUNCIL-PROMPT-V50.md`. Both
  gemini AND codex returned OK (non-empty traced audits; both `.err` 0 bytes; `council.sh` exit 0).
  Immediately git-status-verified the byte-freeze (subject unmutated, no stray files), then authored
  `394-01-COUNCIL-NET.md` (the capture record: manifest available/skipped, raw output paths, per-model
  one-line characterization, the DIVERGENCE map, the RAW leads routed to 394-03, the byte-freeze
  attestation, the "NET 1 ON RECORD" line, the codex-reset note for 396).

## Council outcome (RAW — not adjudicated; adjudication is 394-03)

| Item | gemini | codex |
|------|--------|-------|
| LEGACY-01 (whale-pass O(1) claim + box record) | **VERIFIED SOUND** (value-equivalent + freeze-safe + single-shot) | **FINDING (SPINE)** — delayed-materialization horizon drift (claim-time `level+1` vs open-time) |
| LEGACY-02a (AFSUB pass-gating + OPEN-E consent) | **VERIFIED SOUND** | **VERIFIED SOUND** (convergent) |
| LEGACY-02b (MINTDIV index alignment) | **FINDING (SPINE)** — `processed` reset mid-player → quadrant bias | **VERIFIED SOUND** (reset only at `remainingOwed == 0`) |

The two FINDINGS are DIVERGENT and cross-contradicting — each model VERIFIED SOUND on the exact item the
OTHER flagged. The splits land on the two prime targets the slice charged HARD, requiring the skeptic
dual-gate ([[feedback_skeptic_pass_before_catastrophe]]) at 394-03 against the frozen source. LEGACY-02a is
convergent SOUND across both models. The box-open RECORD half of LEGACY-01 (enqueue/freeze subpart) is also
convergent SOUND — the LEGACY-01 divergence is isolated to the claim-time horizon.

Two load-bearing anchors for 394-03 adjudication (verified to resolve at the frozen source, NOT
adjudicated): (1) a `D-04 — timing shifts from open-time` doc comment at
`DegenerusGameLootboxModule.sol:1483` on `_activateWhalePass` suggests codex's claim-time horizon may be
DOCUMENTED v50 INTENT, not accidental drift; (2) the MINTDIV `processed = 0` reset fires only at
`remainingOwed == 0` (`MintModule:672-676`) — codex's refutation point — vs gemini's quadrant-offset
`(uint8(i & 3) << 6)` dependence on `i = processed` (`MintModule:761`). 394-03 must reconstruct/extend the
MINTDIV cross-path-equality oracle to force a mid-player budget split at a non-multiple-of-4 `take`.

## Deviations from Plan

None — plan executed as written. The only departure from a clean first run is a continuation handle: a prior
session had committed Task 1 (`691315c5`) and started a fan-out that was interrupted before producing output
(leaving two 0-byte `.err` files, no `.txt`, no `council.json`). Task 1 was verified complete (not redone);
the stale `.err` files were removed (a single specific pair) and the fan-out re-run to completion for Task 2.

A faithful-recording outcome that differs from the plan's EXPECTATION (not a deviation in execution): the
plan anticipated codex would likely SKIP (usage-capped since 392) and that a post-reset codex re-run would
be flagged → 396. Instead codex's usage limit RESET and it returned a full audit — so `skipped[]` is EMPTY,
the dual-NET is satisfied by the council alone on this slice, and no codex re-run is owed for 394-01. This is
recorded faithfully in the COUNCIL-NET (T-394-02 mitigation), and the reset is flagged as an OPPORTUNITY to
pick up the carried 392/393 codex second-source re-runs at 396 while the limit holds.

## Known Stubs

None. This plan produces audit-net capture documents only — no code, no UI, no data-wiring stubs.

## Authentication Gates

None.

## Self-Check: PASSED

Created files verified present:
- FOUND: .planning/phases/394-legacy-debt/394-01-COUNCIL-NET.md
- FOUND: .planning/phases/394-legacy-debt/council/v50.gemini.txt
- FOUND: .planning/phases/394-legacy-debt/council/v50.codex.txt
- FOUND: .planning/phases/394-legacy-debt/council/v50.council.json
- FOUND: .planning/phases/394-legacy-debt/394-01-COUNCIL-PROMPT-V50.md (Task 1)

Commits verified present:
- FOUND: 691315c5 (Task 1 — author neutral v50 legacy-debt council prompt)
- FOUND: 0dab499d (Task 2 — run v50 council fan-out + record NET 1 capture)

Byte-freeze verified: `git diff a8b702a7 -- contracts/` EMPTY; `git status --porcelain contracts/` EMPTY.
