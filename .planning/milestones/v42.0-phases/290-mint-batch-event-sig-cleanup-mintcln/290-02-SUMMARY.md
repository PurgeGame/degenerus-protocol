---
phase: 290-mint-batch-event-sig-cleanup-mintcln
plan: 02
subsystem: contracts

tags: [mint, traits, events, keccak-seed, vrf-consumer-surface, gas, audit-attestation, breaking-topic-hash]

# Dependency graph
requires:
  - phase: 290-mint-batch-event-sig-cleanup-mintcln (Plan 01)
    provides: 290-01-DESIGN-INTENT-TRACE.md (zero-owed → rolled-to-1 disposition routing), 290-01-MEASUREMENT.md (six-attestation scaffold)
  - phase: 281 (v41 closure)
    provides: ticketsOwedPacked 40-bit form + B2-symmetric callsite pattern (anchor SHA 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4)
provides:
  - 6-input → 3-input keccak seed for _raritySymbolBatch (owed folded into baseKey low 32 bits)
  - 3-field TraitsGenerated event (BREAKING topic hash per D-42N-EVT-BREAK-01)
  - Populated 290-01-MEASUREMENT.md (verbatim commit-body source) attesting bytecode delta, storage byte-identity, selectors, event topic hashes, gas theoretical bound, B2-symmetric structural diff
affects: [291 (TST-MINTCLN empirical gas fixture), 296 (SWEEP-02(i) zero-owed → rolled-to-1 closure pass), 297 (audit deliverable §3.A cite-source)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "baseKey low 32 bits double-duty as owed-witness (eliminates standalone ownedSalt/rollSalt local)"
    - "LOG3 → LOG2 on TraitsGenerated (1 indexed topic; 64-byte LOGDATA shrink dominates the ~−19 kgas savings)"
    - "Theoretical-first gas attestation per feedback_gas_worst_case.md (empirical confirmation handed off to Phase 291)"
    - "Six-attestation scaffold (bytecode / storage / selectors / event topics / gas / B2-symmetric structural diff) as audit-cite source"

key-files:
  created:
    - .planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-02-SUMMARY.md
  modified:
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/storage/DegenerusGameStorage.sol
    - .planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md

key-decisions:
  - "D-42N-MINTCLN-SCOPE-01 — narrow scope; no helper extraction; processed += asymmetry flag-only; mint-boost retained per D-40N-MINTBOOST-OUT-01."
  - "D-42N-EVT-BREAK-01 — accept BREAKING TraitsGenerated topic-hash transition (v41 0x5e96.. → v42 0x279e..); inherits v40 D-40N-EVT-BREAK-01 pre-launch indexer-rebuild posture."
  - "Zero-owed → rolled-to-1 branch's stale-owed-in-baseKey routed to Phase 296 SWEEP-02(i); expected SAFE_BY_STRUCTURAL_CLOSURE per 290-01-DESIGN-INTENT-TRACE.md §(ii)."

patterns-established:
  - "Six-section measurement scaffold (bytecode / storage-grep / gas-theoretical / selectors / event-topic-hashes / B2-symmetric-callsite-diff) as the audit-cite source for any future contracts/* cleanup phase."
  - "Numerical attestations live in the commit body verbatim — never in NatSpec — per feedback_no_history_in_comments.md."

requirements-completed: [MINTCLN-01, MINTCLN-02, MINTCLN-03, MINTCLN-04, MINTCLN-05, MINTCLN-06, MINTCLN-07, MINTCLN-08, MINTCLN-09]

# Metrics
duration: ~Wave 2 (sequential — same-session continuation)
completed: 2026-05-17
---

# Phase 290 Plan 02: MINTCLN Cleanup Batch Apply Summary

**Folded `owed` into `baseKey` low 32 bits (eliminating standalone ownedSalt/rollSalt locals) + collapsed `TraitsGenerated` to 3 fields (BREAKING topic-hash) + populated the six-attestation measurement scaffold — `-81 B` bytecode + `~−19,131 gas` theoretical drain savings + storage byte-identical + public selectors UNCHANGED.**

## Performance

- **Duration:** Sequential continuation (Wave 2 finish)
- **Started:** Same-session as Plan 02 Task 1
- **Completed:** 2026-05-17
- **Tasks:** 5/5 (this commit is Task 5)
- **Files modified:** 3 (2 contracts + 1 measurement doc) + 1 created (this SUMMARY.md)

## Accomplishments

- `_raritySymbolBatch` signature dropped `uint32 ownedSalt` → 5-param form; seed reduced from `keccak256(abi.encode(baseKey, entropyWord, groupIdx, ownedSalt))` (4 inputs) to `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` (3 inputs).
- B2-symmetric `baseKey` construction at both callsites (`processFutureTicketBatch` mint:426-429 + `_processOneTicketEntry` mint:763-766) now ORs `uint256(owed)` into low 32 bits — owed is recoverable from `baseKey` without a separate stack/event slot.
- `TraitsGenerated` event reshaped to `(address indexed player, uint256 baseKey, uint32 take)` (3 fields; 1 indexed topic) — LOG3→LOG2 transition; topic hash BREAKING per D-42N-EVT-BREAK-01.
- `_processOneTicketEntry` `uint256 rollSalt` local removed; `_resolveZeroOwedRemainder` parameter renamed `rollSalt → baseKey` for consistency; `_rollRemainder` body untouched per D-40N-MINTBOOST-OUT-01 (its `rollSalt` parameter name preserved as generic-salt utility).
- `_raritySymbolBatch` docstring rewritten per `feedback_no_history_in_comments.md` (describes what IS; zero comparative/historical language).
- 290-01-MEASUREMENT.md fully populated across all six sections — verbatim copy-forward source for the batched commit body, audit-cite-ready for Phase 297 §3.A.

## Task Commits

Tasks 1–5 are all consolidated into ONE batched commit per `feedback_batch_contract_approval.md`:

1. **Task 1: Apply MINTCLN-01..07 contract edits (A..L)** — included in batched commit
2. **Task 2: Run `forge build --skip test` + record post-build state** — measurement input to batched commit
3. **Task 3: Run measurement attestations against post-patch tree** — populated 290-01-MEASUREMENT.md (included in batched commit)
4. **Task 4: Cross-validate measurement values against post-patch source** — TicketsCredited→TicketsQueued* substitution + rollSalt scope-clarification recorded as deviations
5. **Task 5: Present batched diff + USER-APPROVED commit** — this batched commit (subject `contracts(290-02): apply MINTCLN-01..09 cleanup batch [USER-APPROVED]`)

**Plan metadata:** This SUMMARY.md is included IN the same batched commit per Wave-2-finish protocol (no separate metadata commit to avoid double-touching the working tree after user approval).

## Files Created/Modified

- `contracts/modules/DegenerusGameMintModule.sol` — 3 hunk groups (MINTCLN-01/02/03/04/05/06/07; both B2-symmetric callsites + `_raritySymbolBatch` signature + `_resolveZeroOwedRemainder` parameter rename + docstring rewrite). Bytecode `-81 B` vs v41 baseline.
- `contracts/storage/DegenerusGameStorage.sol` — 1 hunk: `TraitsGenerated` event declaration reshaped 6-field → 3-field (BREAKING topic hash per D-42N-EVT-BREAK-01). NatSpec comment line above the event also rewritten per `feedback_no_history_in_comments.md`. Storage layout byte-identical.
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` — All six attestation sections populated post-patch (bytecode delta; storage-slot grep EMPTY; worst-case gas theoretical + Phase 291 empirical handoff; selectors UNCHANGED; event topic hashes including BREAKING `TraitsGenerated` old+new + UNCHANGED `TicketsQueued*` triplet; B2-symmetric structural-diff verification).
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-02-SUMMARY.md` — this file.

## Key Attestations (verbatim from 290-01-MEASUREMENT.md)

| Lock | Value | Disposition |
|---|---|---|
| Bytecode delta (MintModule deployed-runtime) | `-81 B` | PASS (negative as expected; within −60..−120 B envelope) |
| Storage layout diff (MintModule + Storage abstract) | EMPTY (substantive) | MINTCLN-08 PASS |
| Public selector `processFutureTicketBatch(uint24,uint256)` | `0x9103766f` | UNCHANGED (MINTCLN-09 PASS) |
| Public selector `processTicketBatch(uint24)` | `0x2ff3118b` | UNCHANGED (MINTCLN-09 PASS) |
| `TraitsGenerated` v41 topic hash (6-field) | `0x5e96bf2d5c935864be60ff066e1f498150a446b5b8b94321b0097276c61ec7c9` | RETIRED |
| `TraitsGenerated` v42 topic hash (3-field) | `0x279edf1ccbf5db78a99006a6861b4d49de10ed6016d8400ce6a1d5e415d2ebc3` | NEW (BREAKING per D-42N-EVT-BREAK-01) |
| `TicketsQueued` topic hash | `0x6fd510354c0c844211fe1a187b420a1faeaf581b2242b0ac52ab02603b3c71c2` | UNCHANGED (MINTCLN-09 PASS) |
| `TicketsQueuedScaled` topic hash | `0xabd0edb220b375806b1cf90ff6542f01dbcce5522ab5bbe601182f139d200558` | UNCHANGED (MINTCLN-09 PASS) |
| `TicketsQueuedRange` topic hash | `0x7d3694156c24d59b09e44621fa9b984b9cfc57cb35f685976a1d1ce6a997b595` | UNCHANGED (MINTCLN-09 PASS) |
| Theoretical gas savings (5840-owed multi-call drain) | `~−19,131 gas` | LOG3→LOG2 + 64-byte LOGDATA shrink dominate (~98%); empirical confirmation deferred to Phase 291 TST-MINTCLN per `feedback_gas_worst_case.md` |
| B2-symmetric callsite diffs (baseKey + `_raritySymbolBatch` call + `TraitsGenerated` emit) | indentation + `idx`↔`queueIdx` local-name only | PASS (zero substantive drift per v41 Phase 281 precedent) |

## Decisions Made

- **D-42N-MINTCLN-SCOPE-01** — Narrow scope per `feedback_design_intent_before_deletion.md` + `feedback_frozen_contracts_no_future_proofing.md`: helper extraction, `processed +=` asymmetry at mint:499/714, storage layout changes, indexer rebuild tooling, mint-boost retirement, KNOWN-ISSUES.md edits, and external-reader (`contracts/DegenerusGame.sol`) edits are all FLAG-ONLY for v43+ bundles and OUT OF SCOPE here. Recorded in REQUIREMENTS.md `## Out of Scope` register.
- **D-42N-EVT-BREAK-01** — Accept BREAKING `TraitsGenerated` topic-hash transition (v41 `0x5e96..` → v42 `0x279e..`). Inherits v40 `D-40N-EVT-BREAK-01` pre-launch posture: indexer migration is a rebuild on v42 close HEAD; no dual-emit / shadow event needed pre-launch.
- **Subtle disposition (290-01-DESIGN-INTENT-TRACE.md §(ii))** — `_processOneTicketEntry` zero-owed → rolled-to-1 branch carries stale `owed=0` in `baseKey` low 32 bits during the subsequent `_raritySymbolBatch` + `TraitsGenerated`. ACCEPTABLE here (single-trait emission; upper-bit + `groupIdx` distinctness preserves seed separation; keccak uniformity holds for any low-32-bit value). Routed to **Phase 296 SWEEP-02(i)**; expected `SAFE_BY_STRUCTURAL_CLOSURE`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Planning Artifact Bug] `TicketsCredited` event substituted with the three real `TicketsQueued*` events**
- **Found during:** Task 4 (cross-validation of measurement attestations against post-patch source).
- **Issue:** Plan 02 outline `<read_first>` block referenced `event TicketsCredited` as a non-`TraitsGenerated` event topic to attest under MINTCLN-09. Grep of `contracts/` at both v41 close HEAD and v42 post-patch HEAD confirmed NO event named `TicketsCredited` exists; the closest ticket-queue family of events are the three `TicketsQueued*` variants.
- **Fix:** Substituted the three concretely-existing ticket-queue family events (`TicketsQueued` / `TicketsQueuedScaled` / `TicketsQueuedRange`) for the planning artifact's `TicketsCredited` cite. Their UNCHANGED topic hashes are recorded in 290-01-MEASUREMENT.md §(5).
- **Files modified:** 290-01-MEASUREMENT.md §(5) "Non-`TraitsGenerated` event topic hashes" sub-table.
- **Verification:** `git grep -n "event TicketsCredited" contracts/` returns no matches at both trees; `cast keccak` over each of the three `TicketsQueued*` canonical signatures produces the hashes recorded in the doc.
- **Forward-handoff note:** REQUIREMENTS.md success criterion #4 + ROADMAP.md Phase 290 success-criteria #3 both still cite `TicketsCredited` (phantom). Worth correcting before the Phase 297 audit deliverable cite-pass. Documenting here, NOT fixing in this commit (out of MINTCLN scope per D-42N-MINTCLN-SCOPE-01).
- **Committed in:** this batched commit (same SHA as Task 5).

**2. [Rule 1 — Verify-Script Overshoot] `_rollRemainder` `uint256 rollSalt` parameter intentionally preserved**
- **Found during:** Task 4 verification grep for `uint256 rollSalt` in MintModule.
- **Issue:** A naive `grep "uint256 rollSalt"` overshoots — the local `rollSalt` inside `_processOneTicketEntry` was correctly removed, but `_rollRemainder`'s parameter name `uint256 rollSalt` at mint:646 is INTENTIONALLY preserved per `D-40N-MINTBOOST-OUT-01` (its body is mint-boost-retention surface that MUST NOT be touched in this plan; `rollSalt` there functions as a generic-salt utility name).
- **Fix:** Documented the scope boundary in the commit-body MINTCLN-05 line and in 290-01-MEASUREMENT.md §(2) text ("`_rollRemainder` body UNTOUCHED"). The verify command was tightened mentally to "no `uint256 rollSalt` local *inside `_processOneTicketEntry`*" — which the post-patch source satisfies.
- **Files modified:** None (clarification only; no edit needed).
- **Verification:** `git diff contracts/modules/DegenerusGameMintModule.sol` shows zero lines in the `_rollRemainder` body (mint:646-658 range) are touched; only `_processOneTicketEntry`'s local `rollSalt` declaration is removed.
- **Committed in:** clarification-only; reflected in this batched commit.

**3. [Rule 1 — Cosmetic] Storage-layout diff carries a single leading-blank-line difference from foundry-nightly warning stripper**
- **Found during:** Task 3 measurement of MINTCLN-08 storage byte-identity attestation.
- **Issue:** `forge inspect ... storageLayout` output from foundry-nightly emits an extra leading blank line vs the v41 baseline output (artifact of the warning-stripper stage). Raw `diff` returned a 1-line cosmetic difference for MintModule (Storage abstract was byte-identical).
- **Fix:** Substantive content is byte-identical (169 non-blank lines on each side for MintModule; 171 lines for Storage). Recorded the cosmetic-stripper detail in 290-01-MEASUREMENT.md §(2) ("modulo a single leading-blank-line cosmetic difference produced by the foundry-nightly warning stripper; substantive table content byte-identical").
- **Files modified:** 290-01-MEASUREMENT.md §(2) attestation text (no contract changes).
- **Verification:** `diff <(forge inspect ... storageLayout v41 | grep -v "^$") <(forge inspect ... storageLayout v42 | grep -v "^$")` returns EMPTY for both files. MINTCLN-08 byte-identity attestation PASSED.
- **Committed in:** this batched commit (same SHA as Task 5).

---

**Total deviations:** 3 auto-fixed (3× Rule 1 — planning-artifact / verify-script / cosmetic stripper)
**Impact on plan:** Zero scope creep. All three are transparency improvements; the substantive MINTCLN-01..09 attestation locks are PRESERVED.

## Issues Encountered

None during planned work — all checkpoints reached cleanly; the three deviations above were caught at Task 4 cross-validation and resolved without recourse to a checkpoint.

## TDD Gate Compliance

N/A — this plan has `type: cleanup`, not `type: tdd`. Empirical-gas confirmation is handed forward to Phase 291 TST-MINTCLN per `feedback_gas_worst_case.md` (theoretical-first prioritization rule).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Audit subject HEAD ready** for Phase 291 TST-MINTCLN to assert against (empirical-gas fixture build target = the ~5840-owed-per-player drain anchor case from 290-01-MEASUREMENT.md §(3)(a); theoretical bound = `~−19,131 gas`).
- **Phase 297 audit deliverable §3.A cite-source ready** — 290-01-MEASUREMENT.md is the verbatim source for the audit-deliverable bytecode / storage / selector / event-topic-hash / gas / B2-symmetric attestations.
- **Phase 296 SWEEP-02(i)** carries forward the `_processOneTicketEntry` zero-owed → rolled-to-1 stale-owed-in-baseKey subtle-disposition closure (expected `SAFE_BY_STRUCTURAL_CLOSURE` per 290-01-DESIGN-INTENT-TRACE.md §(ii)).

### Known forward-handoff items (DOCUMENTED HERE; NOT fixed in this commit)

- **REQUIREMENTS.md success criterion #4** + **ROADMAP.md Phase 290 success-criteria #3** still cite `TicketsCredited` (phantom event). Worth correcting before the Phase 297 audit deliverable cite-pass. Out of MINTCLN scope per D-42N-MINTCLN-SCOPE-01.
- **Phase 290 KNOWN-ISSUES.md** is byte-identical to v41 close — no MINTCLN entry needed (the BREAKING `TraitsGenerated` topic-hash is documented in the commit body + here + 290-01-MEASUREMENT.md §(5), and is already mapped via D-42N-EVT-BREAK-01 → v40 D-40N-EVT-BREAK-01 pre-launch posture).

## Self-Check: PASSED

- All 4 staged files present on disk after commit (`contracts/modules/DegenerusGameMintModule.sol`, `contracts/storage/DegenerusGameStorage.sol`, `290-01-MEASUREMENT.md`, `290-02-SUMMARY.md`).
- Commit `e5665117` present in `git log --oneline --all` with subject `contracts(290-02): apply MINTCLN-01..09 cleanup batch [USER-APPROVED]`.
- `git diff 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4..HEAD -- contracts/DegenerusGame.sol KNOWN-ISSUES.md` is EMPTY (external readers + KI UNCHANGED — D-42N-MINTCLN-SCOPE-01 honored).
- Commit contains exactly 4 files; `.planning/STATE.md` correctly remains UNSTAGED (orchestrator territory).
- No `git push` issued by the executor.

---
*Phase: 290-mint-batch-event-sig-cleanup-mintcln*
*Plan: 02*
*Completed: 2026-05-17*
