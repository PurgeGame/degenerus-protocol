---
phase: 445-spec-design-lock-the-implementation-contract
plan: 04
subsystem: spec-design-lock
tags: [v71, foilpack, design-lock, spec, storage-keying, user-signoff]
requires:
  - "445-01 (economics section)"
  - "445-02 (storage section)"
  - "445-03 (entrypoints section)"
provides:
  - "445-SPEC.md — the single canonical build-ready v71 Foil Pack design-lock SPEC (Phase 446 builds from it)"
  - "PIN 1 RESOLVED to level=>player surviving-record keying (USER sign-off 2026-06-19)"
  - "PIN 2 ACCEPTED unchanged ([144-167] stamp / [0-143] payload)"
affects:
  - "Phase 446 IMPL — declares foilRecord as mapping(uint24 => mapping(address => uint256))"
tech-stack:
  added: []
  patterns:
    - "Nested-mapping (level=>player) surviving-record storage keying — one DECLARED base slot, per-entry slots at keccak-derived addresses"
    - "PIN 2 packed 168-bit superset retained byte-unchanged; the level stamp's role demoted from cap to redundant cross-check"
key-files:
  created:
    - ".planning/phases/445-spec-design-lock-the-implementation-contract/445-04-SUMMARY.md"
  modified:
    - ".planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC.md"
    - ".planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-D-storage.md"
    - ".planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-E-entrypoints.md"
decisions:
  - "PIN 1 → level=>player surviving-record (mapping(uint24 => mapping(address => uint256))) — CHOSEN over single-slot; the L+1-re-buy self-overwrite loss edge is ELIMINATED"
  - "PIN 2 → [144-167] stamp / [0-143] payload bit layout ACCEPTED unchanged; stamp role = redundant cross-check (the outer level key is now the cap)"
  - "T-445-D3 disposition upgraded accept → mitigate (grief-resistance is now structural)"
metrics:
  duration: "~7 min (Task 3 resolution + reconciliation)"
  completed: "2026-06-20"
  tasks: "3/3"
  files-modified: 3
---

# Phase 445 Plan 04: Consolidate the canonical SPEC + USER sign-off Summary

Consolidated the three section files into the single canonical `445-SPEC.md` (Tasks 1–2), then resolved the
Task-3 USER sign-off checkpoint by reconciling the SPEC to **PIN 1 = level=>player surviving-record keying**
and **PIN 2 = the locked bit-offset accepted unchanged** across all three SPEC files.

## What This Plan Did

- **Task 1 (prior):** assembled `445-SPEC.md` in the house design-lock format — front matter (baseline `99f2e53f`
  @ `ffbd7796`, closure `MILESTONE_V70_AT_HEAD…`), the consolidated §A/§D/§E sections, the REQ-coverage map for
  all 20 phase REQ-IDs, the §6 hard-floor map, and the four corrected anchors.
- **Task 2 (prior):** appended the consolidated threat model (Trust Boundaries TB-1..5, STRIDE register
  T-445-D*/E* + T-445-SC, SEC-01/SEC-02 design-basis) and the top-level §T USER-decisions callout.
- **Task 3 (this session — USER signed off 2026-06-19):** PAUSED for USER review, collected the two sign-offs,
  and reconciled the SPEC to the chosen variants. **PIN 1 changed** from the single-slot form to the
  `level=>player` surviving-record form; **PIN 2 accepted** unchanged.

## USER Sign-off (2026-06-19) — recorded as RESOLVED

| Pin | Decision | Outcome |
| --- | --- | --- |
| **PIN 1** — `foilRecord` keying | CHANGED to `mapping(uint24 => mapping(address => uint256))` (level=>player, surviving-record) | The single-slot self-overwrite **player-loss edge is ELIMINATED**; grief-resistance is now STRUCTURAL (distinct levels are independent records). The single-slot form is now the documented *rejected* alternative. |
| **PIN 2** — packed bit-offset | ACCEPTED unchanged (`[144-167]` stamp / `[0-143]` payload) | The 168-bit superset layout and all `_FOIL_*` masks/shifts (`_FOIL_STAMP_SHIFT=144`, `_FOIL_MULT_SHIFT=128`) are byte-unchanged. The stamp's role changes from the cap mechanism to a **redundant self-consistency cross-check** (the outer level key now scopes the record). |

## Reconciliation Applied (the level=>player keying, coherently, everywhere)

- **Keying:** `foilRecord` → `mapping(uint24 => mapping(address => uint256))`; outer key = raw `uint24 level`
  (`:236`), inner key = player. All reads/writes → `foilRecord[lvl][msg.sender]` (buy) /
  `foilRecord[recLevel][player]` (claim).
- **Cap (FOIL-01):** now `foilRecord[lvl][player] != 0` (presence in the level sub-map; a real buy's
  `multBps ≥ 20000` makes the record non-zero). No stamp-equality auto-reset needed — the nested level key
  inherently scopes the record per level.
- **Accessor `_foilRecordFor`:** simplified to a single SLOAD of `foilRecord[lvl][player]`; the century-style
  stamp-compare auto-reset is dropped (the nested key replaces it). A retained stamp assertion is a redundant
  defensive check (always true).
- **Loss edge ELIMINATED:** §D.4, the §E grief note, and the threat-model rows (T-445-D3, TB-4) rewritten — a
  re-buy at L+1 writes `foilRecord[L+1][player]` and never touches `foilRecord[L][player]`; L's unclaimed
  signatures survive until claimed.
- **T-445-D3 disposition:** upgraded `accept` → `mitigate` (the grief surface is structurally resolved).
- **SEC-04 / slot count (clarified, NOT inflated):** a nested mapping still occupies exactly ONE declared base
  mapping slot (per-(level, player) entries live at keccak-derived addresses). "Two new base mapping slots" and
  "no existing slot moved" stay TRUE; only the §D.5 net *runtime* cost line rises to "1 packed slot per
  (level, player) that ever bought".
- **§D.6 PIN 1 + §T Decision 1 / Decision 3:** rewritten as RESOLVED records; the §T heading flipped from
  "USER Decisions to Confirm Before the 446 IMPL Gate" to a RESOLVED decisions record an IMPL-446 author reads
  as final. Decision 3 (the loss edge) is now resolved/eliminated, not an open acceptance.
- **Overview / front-matter refs (§0):** the "LOCKED single-slot" lines flipped to the level=>player resolution.

## What Was NOT Changed (preserved exactly)

- **PIN 2 bit layout** — byte-unchanged (`[0-127]` sigs, `[128-143]` multBps, `[144-167]` stamp, `[168-255]`
  reserved 0; `_FOIL_STAMP_SHIFT=144`, `_FOIL_MULT_SHIFT=128`).
- **Economics §A**, the match/payout/calibration numbers (§E.7 **≈1.9376 faces/pack/30d**), the §6 hard-floor
  map, and the REQ-coverage map's 20 REQ-IDs — all intact.

## Files

- `.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC.md` — the consolidated canonical SPEC (§0/§D/§E/§S/§T reconciled to level=>player; PIN 2 retained)
- `.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-D-storage.md` — storage section (D.1/D.2/D.4/D.5/D.6/D.7 reconciled)
- `.planning/phases/445-spec-design-lock-the-implementation-contract/445-SPEC-E-entrypoints.md` — entrypoints section (buy storage write + claim grief note reconciled)

## Commits

- `a43a56df` — docs(445-04): resolve PIN 1 to level=>player per USER sign-off; PIN 2 accepted

## Deviations from Plan

None — the plan's Task 3 explicitly provisioned for "if the USER requests a change to either pin, update the
corresponding SPEC section (and 445-SPEC-D-storage.md) to the chosen variant". The USER changed PIN 1 to
level=>player; this summary records that resolution. No `contracts/*.sol` touched (read-only constraint honored);
`STATE.md` / `ROADMAP.md` left for the orchestrator.

## Known Stubs

None — this is a paper-only design-lock SPEC; no code stubs.

## Threat Flags

None — no new security surface introduced beyond the design-locked-here / attested-downstream items
(SEC-01/SEC-02/SEC-04) already in the SPEC's threat model. The PIN 1 change *reduces* surface (T-445-D3
accept → mitigate).

## Self-Check: PASSED

- All 20 phase REQ-IDs (FOIL-01..05, RARE-01..04, MATCH-01..10, SEC-03) grep-present in `445-SPEC.md`.
- `mapping(uint24 => mapping(address => uint256))` / `level=>player` is the CHOSEN keying; single-slot
  appears ONLY as the rejected alternative / eliminated edge.
- PIN 2 layout byte-unchanged (`_FOIL_STAMP_SHIFT = 144`, `_FOIL_MULT_SHIFT = 128`; `[144-167]`/`[0-143]`).
- Calibration ≈1.9376 faces/pack/30d unchanged; no fenced Solidity in any of the three SPEC files.
- `git diff --quiet -- contracts/` CLEAN; `STATE.md` / `ROADMAP.md` untouched.
- Commit `a43a56df` present in git history; all four SPEC/SUMMARY files exist on disk.
