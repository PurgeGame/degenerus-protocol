---
phase: 435-design-design-lock-the-point-unit-streak-path-packing-equiva
plan: 02
subsystem: audit
tags: [design-lock, packing, pendingFlip, accumulator-slot, subStreakLatch, lootboxRngPendingFlip, eip-170, v69]

# Dependency graph
requires:
  - phase: 435-01 (DESIGN-01 + DESIGN-02 sections of 435-DESIGN-LOCK.md)
    provides: subStreakLatch uint8->uint16 widening that consumes the 8 bits this plan frees; the design-lock doc to append to
  - phase: v68.0 baseline (contracts/ tree e9a5fc24)
    provides: byte-frozen Sub accumulator slot, pendingFlip accrue/clamp/settle, lootboxRngPacked layout
provides:
  - DESIGN-03 design-lock — Sub.pendingFlip uint32->uint24 (clamp re-pinned to the uint24 ceiling 16,777,215), the net-zero 72-bit accumulator repack proven 256-bit-exact (0 free) BEFORE+AFTER, lootboxRngPendingFlip confirmed distinct/out-of-scope
  - The 8 freed bits' slot arithmetic, EIP-170 re-check flag (436), and layout-golden recapture flag (438) that DESIGN-02's latch widening cross-references
  - Executor-ready per-symbol packing edit surface (a)-(e) for the 436 PACK-01 diff
affects: [436-IMPL (PACK-01), 437-TST (TST-02 clamp-saturation property), 438-REAUDIT (REAUDIT-01 layout golden + EIP-170)]

# Tech tracking
tech-stack:
  added: []
  patterns: [source-anchored design-lock with BEFORE/AFTER bit-arithmetic slot proof and per-symbol packing edit surface]

key-files:
  created: []
  modified:
    - .planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md

key-decisions:
  - "pendingFlip width locked: Sub.pendingFlip uint32->uint24 (Storage:2237); saturating clamp re-pinned 100_000_000 -> uint24 ceiling 16,777,215 (2^24-1, ~16.7M whole FLIP), far above any realistic per-sub claimable bank; can only UNDER-credit, off the solvency path; saturation-not-overflow asserted, handed to 437 TST-02"
  - "Accumulator repack locked net-zero: affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72 bits; the -8 from pendingFlip is the +8 to subStreakLatch (DESIGN-02/D-04); affiliateBase untouched at 32"
  - "Sub struct proven exactly 256 bits / 0 free BEFORE + AFTER (config 48 + per-sub stamp 40 + markers 96 + accumulator 72 = 256), totalled from the field declarations not the comments"
  - "lootboxRngPendingFlip uint40 (Storage:1525, bits [184:223], /1e18, max ~1.1T FLIP) confirmed a SEPARATE field of the global lootboxRngPacked uint256 — distinct type/container/scaling/purpose, NOT narrowed (D-08)"
  - "EIP-170 re-check is 436/PACK-01 (expected net-neutral); the forge-inspect storage-layout golden recapture is the expected new golden in 438 REAUDIT-01, NOT a layout drift"

patterns-established:
  - "Slot-packing locks are proven with an explicit BEFORE/AFTER field-width table totalled from the declarations; comment-vs-field discrepancies are reconciled inline with [ANCHOR NOTE], source is ground truth"

requirements-completed: [DESIGN-03]

# Metrics
duration: ~12min
completed: 2026-06-18
---

# Phase 435 Plan 02: Design-Lock pendingFlip Narrowing + Accumulator Repack Summary

**Appended the DESIGN-03 section to the v69 design-lock document: locked `Sub.pendingFlip` uint32→uint24 (saturating clamp re-pinned to the uint24 ceiling `16,777,215` = `2^24−1`), proved the 72-bit accumulator repack `affiliateBase(32)+pendingFlip(24)+subStreakLatch(16)=72` is net-zero with an explicit BEFORE/AFTER field-width table summing to exactly 256 bits (0 free), and confirmed `lootboxRngPendingFlip` (uint40) is a separate out-of-scope field — read-only against the byte-frozen v68 baseline `e9a5fc24`, NO `.sol` change.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-06-18
- **Tasks:** 1
- **Files modified:** 1 (435-DESIGN-LOCK.md, +123 lines appended), 1 summary

## Accomplishments

- **D-06 (pendingFlip narrowing):** Locked `Sub.pendingFlip` uint32→uint24 (`Storage:2237`), with the saturating clamp re-pinned from `100_000_000` to the uint24 ceiling `16,777,215` (`2^24−1`). Justified against the realistic per-sub claimable bank (whole-FLIP slot-0 quest reward + ticket-mode 10%/20% buyer bonus per delivered day): 16.7M whole FLIP can only ever bind for a never-claiming reinvest-whale, the same pathological shape the current 100M clamp catches — an UNDER-credit off the solvency path, never an overflow. Asserted the clamp is `min(...)` *before* the cast so the narrowed write provably never wraps (saturation-not-overflow, handed to 437 TST-02). Recorded the exact accrue/clamp/settle edit surface (a)-(e): casts `uint32(newOwed)`→`uint24(newOwed)` at `GameAfkingModule.sol:863`/`:928`, clamp constant swap at `:862`/`:927`, settle read at `:1097-1100` holds.
- **D-07 (net-zero repack):** Locked the accumulator repack `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72` — the −8 from pendingFlip is the +8 to subStreakLatch (DESIGN-02/D-04), `affiliateBase` untouched. Produced a full `Sub`-struct field-width table BEFORE + AFTER, totalled from the field declarations (config 48 + per-sub stamp 40 + markers 96 + accumulator 72 = **256 bits, 0 free** in both states). Flagged EIP-170 re-check (436/PACK-01, expected net-neutral) and the `forge inspect` layout-golden recapture (438 REAUDIT-01, the expected new golden — not a drift; the slot index is unchanged, only intra-slot offsets/types move).
- **D-08 (out-of-scope confirmation):** Confirmed `lootboxRngPendingFlip` (uint40, `Storage:1525`, bits [184:223], scaled /1e18, max ~1.1T FLIP) is a field of the **global** `lootboxRngPacked` uint256 — distinct from `Sub.pendingFlip` in type, container, scaling, and purpose. Recorded a side-by-side distinguishing table so 436 cannot narrow the wrong field. NOT narrowed.
- Re-confirmed every cited file:line anchor against the frozen `e9a5fc24` tree; recorded 4 `[ANCHOR NOTE]` corrections (source is ground truth).

## Task Commits

Each task was committed atomically with `git add -f` (`.planning/` is gitignored in this repo):

1. **Task 1: Author the DESIGN-03 section** — `52effc5f` (docs)

## Files Created/Modified
- `.planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md` — appended the `## DESIGN-03` section (+123 lines; the doc now holds DESIGN-01 + DESIGN-02 + DESIGN-03)

## Decisions Made

None beyond recording the USER-locked decisions D-06/D-07/D-08 (LOCKED in CONTEXT.md; this plan records them with source-anchored rationale and the slot proof). Claude's-discretion item (the precise uint24 clamp constant value — exact `2^24−1 = 16,777,215` vs a rounded `~16.7M`, and its constant name) was deferred to 436 IMPL with a recommendation to use the exact type ceiling so the cast is lossless by construction.

## Deviations from Plan

None - plan executed exactly as written. No deviation rules (1-4) triggered; no `contracts/*.sol`, STATE.md, or ROADMAP.md touched.

## Anchor Corrections (source is ground truth)

The plan's `<interfaces>` block and CONTEXT.md were re-confirmed against the frozen `e9a5fc24` tree. Four anchors were imprecise/incomplete and corrected inline in the design-lock with `[ANCHOR NOTE]` tags (none change a locked decision):

1. **pendingFlip clamp sites** — confirmed the exact blocks: ticket buyer-bonus `:861-863` (`newOwed` :861, `> 100_000_000` clamp :862, `uint32(newOwed)` write :863) and slot-0 reward `:925-929` (`newOwed` :925-926, clamp :927, write :928); settle `_settlePendingFlip:1097-1100` (read :1098, zero :1100). Cited ranges contained the true anchors; corrected for precision.
2. **affiliateBase scope clarification** — the sibling uint32 accumulator field (`:2229`) shares the 100M-clamp idiom (`GameAfkingModule.sol:920-922`) but is explicitly NOT in scope; D-06 narrows only `pendingFlip`. Recorded so 436 does not touch `affiliateBase`'s width or clamp.
3. **Three Sub-struct comment-vs-field width discrepancies** — totalling the field declarations surfaced: slot doc-comment `config (40b)` is wrong (declared sum = 48); field-section header `per-sub stamp (48 bits)` is wrong (declared sum = 40); field-section header `markers (72 bits)` is wrong (declared sum = 96). The declared fields are ground truth and the 256-bit-exact slot proof is computed from them; 436 should fix these comment labels while editing the struct. (The accumulator `72b` label is correct in both comment locations.)
4. **lootboxRngPendingFlip anchor** — CONTEXT.md cited `~Storage:1527`; the exact layout-comment line on the frozen tree is `:1525` (the `lootboxRngPacked` var declaration begins `:1530`). Corrected.

## Threat Model Coverage

- **T-435-04 (Tampering — accumulator-slot repack):** mitigated — explicit BEFORE/AFTER field-width table proves the net-zero repack keeps `Sub` at exactly one 256-bit slot (0 free), no new cold slot, no collision.
- **T-435-05 (DoS — pendingFlip uint24 value-range):** mitigated — the `2^24−1 = 16,777,215` clamp is justified above any realistic per-sub bank; the clamp can only under-credit (off the solvency path), identical risk shape to the current uint32+100M clamp; saturation-not-overflow asserted and handed to 437 TST-02.
- **T-435-06 (Spoofing — lootboxRngPendingFlip vs Sub.pendingFlip confusion):** mitigated — the distinguishing facts table (type uint40, container `lootboxRngPacked`, slot bits [184:223], /1e18 scaling, distinct purpose) recorded so 436 cannot narrow the wrong field.
- **T-435-SC (npm/pip/cargo installs):** N/A — read-only docs-only phase, no install task exists.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required. This is a documentation-only design-lock phase.

## Next Phase Readiness
- DESIGN-03 is design-locked with the uint24 narrowing + re-pinned clamp, the proven net-zero 256-bit-exact slot arithmetic, the per-symbol packing edit surface (a)-(e), and the lootboxRngPendingFlip out-of-scope confirmation. Executor-ready for the 436 PACK-01 diff (the sole `.sol` change of the v69 milestone).
- DESIGN-02's latch-widening cross-reference (the 8 freed bits) is now backed by this plan's slot arithmetic; the two sections are consistent (the −8/+8 net-zero is stated in both).
- 437 TST-02 owns the clamp-saturation property test; 438 REAUDIT-01 owns the layout-golden recapture (expected new golden) + EIP-170 re-attest.
- No blockers. NO `contracts/*.sol`, STATE.md, or ROADMAP.md modified (orchestrator owns those writes).

## Self-Check: PASSED
- `435-DESIGN-LOCK.md` has a `## DESIGN-03` section (appended after DESIGN-01 + DESIGN-02, +123 lines) ✓
- `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16)` present; `16,777,215`/`2^24`/`16.7M` present; `lootboxRngPendingFlip` present (Task 1 automated verify all PASS) ✓
- Full Sub field-width table BEFORE + AFTER both sum to 256 / 0 free; 3 comment-vs-field discrepancies reconciled from source ✓
- Commit `52effc5f` exists with the `.planning/` file in the commit (git show --stat: 123 insertions) ✓
- No `contracts/*.sol` modified (`git status --porcelain contracts/` empty); STATE.md / ROADMAP.md untouched ✓

---
*Phase: 435-design-design-lock-the-point-unit-streak-path-packing-equiva*
*Completed: 2026-06-18*
