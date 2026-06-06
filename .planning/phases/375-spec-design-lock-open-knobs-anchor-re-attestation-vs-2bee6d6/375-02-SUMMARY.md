---
phase: 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6
plan: 02
subsystem: spec
tags: [design-lock, spec-integrity, anchor-re-attestation, edit-order-map, bit-packing, solvency, smart-contract-audit, 2bee6d6f]

# Dependency graph
requires:
  - phase: 375-01
    provides: "375-ANCHOR-REATTESTATION.md (the 2bee6d6f-grounded re-attested anchor table + the 4 CORRECTED lines + the 3 verification verdicts)"
  - phase: v60.0-closure
    provides: "frozen baseline 2bee6d6f (the IMPL subject the SPEC anchors are grounded on)"
provides:
  - ".planning/SPEC-V61-DESIGN-LOCK.md — the Phase 375 design-lock SPEC: locked knobs D-01..D-05 + the two verification verdicts + the 2bee6d6f-re-attested anchor table + the producer-before-consumer edit-order map (Track A balances / Track B curse counter) + the CURE-vs-PACK-repack write-after-write cross-check + a Coverage section"
  - "the single batched-diff input Phase 376 IMPL authors the AFPAY+PACK+CURSE+SMITE diff from (settled knobs + settled edit order + baseline-true anchors)"
  - "the SOLVENCY accessor-invariant home pinned for SEC-02 (378): the PACK accessor layer, re-attested to Storage:358/365/851 + PayoutUtils:25/39/63 + the GameAfkingModule afking pair"
affects: [376-IMPL (the edit targets + the Track A/B order), 378-TST (SEC-02 SOLVENCY anchor)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "design-lock SPEC folds the re-attested anchor table so the IMPL diff is self-contained (no mid-diff re-grep) and grounded on baseline-true lines"
    - "producer-before-consumer edit order expressed as two slot-independent tracks (balances mapping vs mintPacked_) with an explicit write-after-write cross-check where the two tracks share a buy path"

key-files:
  created:
    - .planning/SPEC-V61-DESIGN-LOCK.md
  modified: []

key-decisions:
  - "D-01 accessor-first PACK/AFPAY sequencing LOCKED (PACK-01 -> PACK-02 -> AFPAY-01..07); supersedes the PLAN-V61-MILESTONE-SCOPE.md §2 / REQUIREMENTS.md PACK-02 feature-first wording (both deferred the choice to SPEC-01)"
  - "D-02 AfkingSpent emitted at EVERY afking debit (both _processMintPayment and the shared _settleShortfall); deliberate departure from silent claimable spends"
  - "D-03 CURSE_COUNT_CAP = 20 points (doubles as the uint8-wrap guard; headroom above the 5-stack smite ceiling)"
  - "D-04 protocol-addr skip (VAULT/SDGNRS/GNRUS) kept for both smite() and the cashout-curse SET; protects the sDGNRS redemption-snapshot activity-score read at the CORRECTED line :932"
  - "D-05 staleness day-basis = _currentMintDay() (not _simulatedDayIndex())"
  - "SPEC cites the 4 CORRECTED baseline anchors (claimablePool decl :365, cure host _purchaseForWith :1093, _recordLootboxMintDay :1000, sDGNRS read :932) instead of the pre-attestation CONTEXT.md ~:NNN"

requirements-completed: [SPEC-01]

# Metrics
duration: 4min
completed: 2026-06-06
---

# Phase 375 Plan 02: SPEC Design-Lock — Open Knobs + Re-Attested Anchors + Edit-Order Map Summary

**Authored `.planning/SPEC-V61-DESIGN-LOCK.md` (the single SPEC-01 deliverable): locks the open knobs D-01..D-05 + both Plan 01 verification verdicts in writing, folds the `2bee6d6f`-re-attested 29-anchor table (adopting the 4 CORRECTED lines), maps the producer-before-consumer edit order as two slot-independent tracks (Track A PACK accessor → repack → AFPAY waterfall · Track B CURSE infra → SMITE) with the CURE-vs-PACK-repack write-after-write cross-check, and carries a Coverage section mapping the three Phase-375 Success Criteria.**

**Artifact:** `.planning/SPEC-V61-DESIGN-LOCK.md` (285 lines, paper-only — ZERO `contracts/*.sol`).

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-06T21:10:21Z
- **Completed:** 2026-06-06T21:14:42Z
- **Tasks:** 3
- **Files modified:** 1 (the `.planning/` artifact; ZERO `contracts/*.sol`)

## Accomplishments

- **Locked all five open knobs (D-01..D-05) in writing** with a clearly-headed subsection each, restating the LOCKED value + rationale + affected REQ-IDs verbatim from `375-CONTEXT.md`:
  - **D-01** accessor-first (PACK-01 → PACK-02 → AFPAY-01..07), with the explicit feature-first→accessor-first reconciliation noting it supersedes `PLAN-V61-MILESTONE-SCOPE.md` §2 / `REQUIREMENTS.md` PACK-02.
  - **D-02** `AfkingSpent` at every afking debit (both `_processMintPayment` AND `_settleShortfall`), with the deliberate-departure call-out vs silent claimable spends.
  - **D-03** `CURSE_COUNT_CAP = 20` (uint8-wrap-guard double-duty + headroom above the 5-stack smite ceiling).
  - **D-04** VAULT/SDGNRS/GNRUS protocol-addr skip for both `smite()` and the curse SET (sDGNRS-redemption-snapshot rationale).
  - **D-05** staleness basis `_currentMintDay()`.
- **Folded Plan 01's two verification verdicts:** `purchaseWith` DEAD → leave untouched at IMPL (lands in `_purchaseForWith`/`_processMintPayment`); self-smite HARMLESS-by-design → no guard required. Both cite `375-ANCHOR-REATTESTATION.md`.
- **Folded the `2bee6d6f`-grounded re-attested anchor table** (29 anchors, 13 files) into the SPEC so the 376 diff is self-contained, plus a dedicated "CONTEXT.md → re-attested corrections" section flagging the 4 CORRECTED drifts.
- **Adopted the 4 CORRECTED baseline anchors** everywhere the SPEC names them: `claimablePool` decl **:365** (not the cited `~:838-839` doc-comment), cure host **`_purchaseForWith` :1093** (not the transposed `_purchaseWithFor` `~:1285`), `_recordLootboxMintDay` **:1000** (not `~:983`), sDGNRS redemption read **:932** (not `~:942`). The cure-host name correction is called out explicitly so 376 is not steered to the non-existent `_purchaseWithFor` symbol.
- **Mapped the producer-before-consumer edit order** as two slot-independent tracks: Track A (PACK-01 → PACK-02 → AFPAY-01 → AFPAY-02..06 → AFPAY-07, accessor-first rationale) · Track B (CURSE-01 → CURSE-02 → CURSE-03 → CURSE-04 → CURSE-05 → CURSE-06 → CURSE-07 → SMITE-01).
- **Recorded the CURE-vs-PACK-repack write-after-write cross-check:** CURSE-04 CURE mutates `mintPacked_` curse bits while the PACK repack mutates the balances mapping → DIFFERENT slots → no clobber, the two tracks are independent.
- **Pinned the SOLVENCY accessor-invariant home** (the PACK accessor layer; re-attested to `Storage:358/365/851` + `PayoutUtils:25/39/63` + the `GameAfkingModule` afking pair) for SEC-02 (378).
- **Carried a Coverage section** mapping the three Phase-375 Success Criteria (SC1 locked knobs / SC2 re-attested anchors / SC3 edit-order map) to their SPEC sections, plus a coverage self-check table confirming no CONTEXT.md decision or verification item is omitted.

## Task Commits

Each task was committed atomically (docs-only, force-added past the `.planning/` gitignore):

1. **Task 1: Lock the open knobs (D-01..D-05 + verification verdicts + hard floor)** - `797e39f9` (docs)
2. **Task 2: Fold the re-attested anchor table + map the producer-before-consumer edit order** - `efa15561` (docs)
3. **Task 3: Coverage section + coverage self-check** - `26d803af` (docs)

**Plan metadata:** _(committed in the final docs commit with SUMMARY/STATE/ROADMAP)_

## Files Created/Modified

- `.planning/SPEC-V61-DESIGN-LOCK.md` (created) - the v61.0 design-lock SPEC: §1 Locked Knobs (D-01..D-05 + the two verification verdicts + the hard floor) · §2 the 4 CORRECTED corrections · §3 the full 29-anchor re-attested table grounded on `2bee6d6f` + the SOLVENCY home · §4 the producer-before-consumer edit-order map (Track A + Track B + the write-after-write cross-check) · §5 Coverage + the coverage self-check + the forward note.

## Decisions Made

- **D-01 accessor-first sequencing LOCKED** — PACK accessor layer + repack land FIRST, then the AFPAY waterfall is authored ONCE against the accessors (PACK-01 → PACK-02 → AFPAY-01..07). Supersedes the "feature-first" wording in `PLAN-V61-MILESTONE-SCOPE.md` §2 / `REQUIREMENTS.md` PACK-02 (both deferred the exact choice to SPEC-01 → this is the intended lock, not a conflict).
- **D-02 `AfkingSpent` at every afking debit LOCKED** — emitted at both `_processMintPayment` AND the shared `_settleShortfall`, a deliberate departure from how claimable spends stay silent outside `_processMintPayment`.
- **D-03 `CURSE_COUNT_CAP = 20` points LOCKED** — doubles as the mandatory uint8-wrap guard; clean headroom above the 5-stack (10-point) smite ceiling.
- **D-04 protocol-addr skip kept LOCKED** — both `smite()` and the cashout-curse SET skip VAULT/SDGNRS/GNRUS (constant compares); protects the sDGNRS redemption-snapshot activity-score read at the CORRECTED line **:932**.
- **D-05 staleness day-basis `_currentMintDay()` LOCKED** — the ≤1-day skew vs `_simulatedDayIndex()` is immaterial against the 5-day window.
- **Cite the re-attested baseline anchors, not the CONTEXT.md `~:NNN`** — the SPEC uses the 4 CORRECTED lines (`:365` / `_purchaseForWith :1093` / `:1000` / `:932`) so the 376 diff edits baseline-true symbols and is not steered to the non-existent `_purchaseWithFor`.

## Deviations from Plan

None - plan executed exactly as written. (No bugs, no missing critical functionality, no blocking issues, no architectural changes.) The contract-commit-guard PreToolUse hook tripped once on a Task-1 verification `git add` because the compound command contained the literal substring `contracts/` in a `grep -c` argument (a false-positive pattern-match, not an actual contract stage). Resolved by re-running the `git add -f .planning/SPEC-V61-DESIGN-LOCK.md` with no `contracts/` substring in the command; the guard was honored (NOT bypassed — `CONTRACTS_COMMIT_APPROVED` was never set), and zero contract files were ever staged or committed. Recorded as a process note, not a plan deviation.

## Issues Encountered

- The PreToolUse contract-commit guard matches the literal string `contracts/` anywhere in a Bash command, so verification one-liners that grep for `contracts/` in their own output trip it. Mitigation (used for the rest of the plan): keep `git add -f <path>` on its own line and use `grep '^contract'` (anchored, no trailing slash) for the staged-path safety checks. No contract files were staged at any point.

## Next Phase Readiness

- **Phase 376 (IMPL)** can author the ONE batched `contracts/*.sol` diff directly from `.planning/SPEC-V61-DESIGN-LOCK.md`: all five knobs are locked, the anchor table provides baseline-true `file:line` edit targets, the 4 CORRECTED lines flag where CONTEXT.md drifted (notably the cure host is `_purchaseForWith` `:1093`), and the Track A / Track B order with the write-after-write cross-check settles the edit sequence. No "by construction" assumptions remain.
- **Phase 378 (SEC-02)** has the SOLVENCY-01 accessor-invariant home pinned (the PACK accessor layer, re-attested to `Storage:358/365/851` + `PayoutUtils:25/39/63` + the `GameAfkingModule` afking pair) to anchor the re-proof at ONE home.

## Self-Check: PASSED

- `.planning/SPEC-V61-DESIGN-LOCK.md` — FOUND (285 lines)
- Task 1 commit `797e39f9` — FOUND
- Task 2 commit `efa15561` — FOUND
- Task 3 commit `26d803af` — FOUND
- All five locked decisions (D-01..D-05) + the two verification verdicts (`purchaseWith` DEAD, self-smite harmless) — present
- The re-attested anchor table grounded on `2bee6d6f` + the 4 CORRECTED lines (`:365` / `_purchaseForWith :1093` / `:1000` / `:932`) — present
- The Track A + Track B edit-order map + the CURE-vs-PACK-repack write-after-write cross-check — present
- The Coverage section mapping the three Phase-375 Success Criteria — present
- `git status --porcelain` for the contract directory — empty (ZERO `contracts/*.sol` modified)

---
*Phase: 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6*
*Completed: 2026-06-06*
