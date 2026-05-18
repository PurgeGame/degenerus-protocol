---
phase: 298-vrf-read-graph-catalog-catalog
plan: 10
subsystem: audit
tags: [audit, vrf, read-graph, catalog, mintmodule, trait-generation, mintcln, v43.0, planning-artifact]

# Dependency graph
requires:
  - phase: v42.0 Phase 290 (mint-batch-event-sig-cleanup-mintcln)
    provides: D-42N-MINTCLN-SCOPE-01 + D-42N-EVT-BREAK-01 + 3-input keccak + owed-in-baseKey collapse (the audit-subject surface this consumer §10 catalogs)
  - phase: v41.0 Phase 281 (mint-batch-determinism-fix-fix)
    provides: D-281-STARTINDEX-SEMANTICS-01 + D-281-FIX-SHAPE-01 (owed-salt 4th-keccak-input invariant; collapsed into baseKey low 32 bits at Phase 290; cross-call seed-separation baseline)
  - phase: Phase 298 plan-phase
    provides: D-298-CONSUMER-LIST-01 §10 entry + D-298-TRACE-DEPTH-01 + D-298-EXEMPT-REACH-01 + D-298-EXEMPT-CROSSCONTRACT-01 + D-298-RECOMMEND-DEPTH-01 + D-43N-AUDIT-ONLY-01 (no SAFE_BY_DESIGN class)
provides:
  - 298-10-CATALOG-section.md — §10 backward-trace catalog for MintModule trait-generation consumer (CAT-01 §A traced function set + CAT-02 §B SLOAD table + CAT-03 §C per-slot writer enumeration + CAT-04 §D verdict matrix + CAT-06 §E remediation tactics)
affects: [298 main-context integration §14/§15/§16/§17 — §10 contributes 7 participating slots, 42 verdict rows (18 VIOLATION, 23 EXEMPT-ADVANCEGAME, 1 EXEMPT-VRFCALLBACK, 0 EXEMPT-RETRYLOOTBOXRNG) to the cross-consumer dedup index]

# Tech tracking
tech-stack:
  added: []  # planning artifact only; zero contract / test / tooling additions
  patterns:
    - "Per-consumer sub-agent §10 catalog with explicit file:line enumeration per feedback_verify_call_graph_against_source.md (Phase 294 BURNIE gap precedent)"
    - "Two outer-loop entry tracing: processFutureTicketBatch (entropy via parameter) + processTicketBatch (entropy via lootboxRngWordByIndex SLOAD) both converge on _raritySymbolBatch — both traced for completeness"
    - "Phase 290 MINTCLN audit-subject surface re-traced post-collapse: 3-input keccak (baseKey, entropyWord, groupIdx) at MintModule:563-565 + owed-in-baseKey low 32 bits invariant preserved"
    - "feedback_rng_window_storage_read_freshness.md F-41-02/03 discipline: ALL SLOADs enumerated including pre-existing traitBurnTicket[lvl][traitId].length read inside output assembly block"
    - "Per-callsite verdict-matrix per D-298-EXEMPT-REACH-01: 42 rows keyed on (slot × writer-fn × callsite-file-line) tuples"

key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-10-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-10-SUMMARY.md
  modified: []

key-decisions:
  - "Trace covers BOTH processFutureTicketBatch (caller-supplied entropy from rngGate-returned rngWord) AND processTicketBatch (self-SLOADs lootboxRngWordByIndex[lrIndex-1] at MintModule:686) — they share _raritySymbolBatch + _rollRemainder consumer body"
  - "Phase 290 MINTCLN-02 owed-in-baseKey collapse re-traced: ticketsOwedPacked[rk][player] SLOAD at MintModule:423/:761 IS the carrier of the cross-call seed-separation invariant (replaces v41 ownedSalt 4th keccak input) — classified Participating? YES"
  - "Pre-existing traitBurnTicket[lvl][traitId].length SLOAD at MintModule:614 (inside assembly output block) enumerated per feedback_rng_window_storage_read_freshness.md ALL-SLOADs discipline; classified NON-PARTICIPATING with F-41-02/03 attestation (self-coupled within consumer stack; no external writer exists — grep confirms zero other SSTORE sites of traitBurnTicket)"
  - "Phase 290 _processOneTicketEntry zero-owed→rolled-to-1 stale-low-32-baseKey disposition NOT contradicted — Phase 290 acknowledged the structural-closure ACCEPTABLE inside self-stack; §10 VIOLATIONS are CROSS-stack writers of ticketsOwedPacked that race the snapshot from outside the consumer's stack (different bug class)"
  - "All 18 VIOLATIONS dispositioned tactic (a) rngLockedFlag-gated revert — uniform recommendation reflects that the consumer's freshness depends on ticketQueue + ticketsOwedPacked snapshot; double-buffer (ticketWriteSlot swap at _swapAndFreeze:299) partially protects intra-window but cross-window writes accumulate in the SAME write slot the next cycle drains"
  - "WhaleModule.purchaseDeityPass:543 existing rngLockedFlag gate cited as canonical tactic-(a) pattern; remediation note records that purchaseWhaleBundle / purchaseLazyPass / openLootBox / openBurnieLootBox / purchase (MintModule._purchaseFor) / claimWhalePass / recordDecBurn lack equivalent top-level gates and are the candidate FIX surfaces"

patterns-established:
  - "feedback_rng_backward_trace.md backward-trace from MintModule trait-generation consumer (Phase 290 audit-subject surface) — successor to Phase 287 JPSURF format scaled to per-consumer §10 granularity"
  - "Phase 290 MINTCLN carry: explicit re-citation of 3-input keccak signature + owed-in-baseKey layout (lvl<<224 | queueIdx<<192 | player<<32 | owed) inside §A function-set notes column and §B participating-set summary"
  - "EXEMPT-VRFCALLBACK exemplar: rawFulfillRandomWords mid-day branch writing lootboxRngWordByIndex[index] at AdvanceModule.sol:1761 is the canonical EXEMPT-VRFCALLBACK reach for this consumer family"

requirements-completed: [CAT-01, CAT-02, CAT-03, CAT-04, CAT-06]

# Metrics
duration: ~5min
completed: 2026-05-18
---

# Phase 298 Plan 10: §10 MintModule Trait-Generation Catalog Summary

**§10 backward-trace catalog AGENT-COMMITTED for the MintModule trait-generation consumer (Phase 290 MINTCLN audit-subject surface — 3-input keccak with owed-in-baseKey at `MintModule:563-565`). 7 participating slots enumerated. 42 verdict rows: 18 VIOLATION (all tactic (a) gated-revert), 23 EXEMPT-ADVANCEGAME, 1 EXEMPT-VRFCALLBACK. Zero `contracts/` + `test/` mutations.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-18 (PARALLEL-DISPATCH session)
- **Completed:** 2026-05-18
- **Tasks:** 1 (AGENT-COMMITTED; zero contract / test edits)
- **Files created:** 2 (CATALOG section + this SUMMARY)

## Accomplishments

- `298-10-CATALOG-section.md` (243 lines) covers all 5 CAT sub-headings (§A traced function set + §B SLOAD table + §C per-slot writer enumeration + §D verdict matrix + §E remediation tactics).
- **§A: 11 functions traced** across MintModule + Storage + libraries — `processFutureTicketBatch`, `processTicketBatch`, `_resolveZeroOwedRemainder`, `_processOneTicketEntry`, `_raritySymbolBatch` (THE 3-input keccak consumer at :563-:565), `_rollRemainder`, `_tqReadKey`, `_tqFarFutureKey`, `_lrRead`, `EntropyLib.hash2`, `DegenerusTraitUtils.traitFromWord`.
- **§B: 10 SLOAD slots enumerated** with `Participating? YES/NO` classification. 7 participating: `lootboxRngPacked` (LR_INDEX field), `lootboxRngWordByIndex[lrIndex-1]`, `ticketWriteSlot`, `ticketLevel`, `ticketCursor`, `ticketQueue[rk]` (length + elements), `ticketsOwedPacked[rk][player]`. 1 NON-PARTICIPATING with F-41-02/03 attestation: `traitBurnTicket[lvl][traitId].length` (self-coupled within consumer stack; no external writer per grep verification). 1 N/A: `level` storage (not directly read by trace; cached as parameter). 1 compile-time constant: `traitBurnTicket.slot` reference.
- **§C: 7-slot writer enumeration** covers every external/public/internal function that writes any participating slot. Includes constructor (DegenerusGame:226-227 init), advanceGame self-stack writes, AND non-EXEMPT-stack writers from `purchaseWhaleBundle`, `purchaseLazyPass`, `purchaseDeityPass`, `openLootBox`, `openBurnieLootBox`, `purchase` (`MintModule._purchaseFor`), `claimWhalePass`, `recordDecBurn`-reach (`_awardDecimatorLootbox`), `_redeemWhalePassRange`.
- **§D: 42-row verdict matrix** — 18 VIOLATION, 23 EXEMPT-ADVANCEGAME, 1 EXEMPT-VRFCALLBACK (`rawFulfillRandomWords` mid-day branch at AdvanceModule.sol:1761), 0 EXEMPT-RETRYLOOTBOXRNG (domain-separated VRF per D-42N-RETRY-RNG-DOMAIN-SEP-01). Zero `SAFE_BY_DESIGN` classifications per `D-43N-AUDIT-ONLY-01`.
- **§E: 18 VIOLATION rows dispositioned tactic (a) gated-revert** with ≤80-char rationale per row. Cross-references `WhaleModule.purchaseDeityPass:543` as the canonical in-codebase pattern.
- **Phase 290 MINTCLN carry preserved:** §A function table notes column explicitly cites the 3-input keccak signature at `MintModule:563-:565` `keccak256(abi.encode(baseKey, entropyWord, groupIdx))`. §B summary section flags the `ticketsOwedPacked[rk][player].owed` SLOAD as the carrier of the cross-call seed-separation invariant per Phase 290 design-intent trace section (i). Phase 290's `_processOneTicketEntry` zero-owed→rolled-to-1 disposition is explicitly NOT contradicted (different bug class — that's intra-stack ACCEPTABLE; §10 VIOLATIONS are CROSS-stack writer races).
- **Commitment-window analysis (per `feedback_rng_commitment_window.md`):** §D adds explicit reasoning that the race is BETWEEN advanceGame transactions (not within one — Solidity is sequential within a transaction). The `_queueTickets` near-future gate is INSUFFICIENT to prevent CROSS-transaction races because writers target near-future levels (level+1..+5), the SAME range the consumer drains.
- **Double-buffer mitigation analysis:** `_swapAndFreeze` toggles `ticketWriteSlot` to protect the read slot, but cross-window writes accumulate in the write slot which becomes the next-cycle read slot — partial coverage, NOT full closure.
- **ALL-SLOADs discipline:** Pure helpers (`EntropyLib.hash2`, `DegenerusTraitUtils.traitFromWord`, `_rollRemainder`, `_tqFarFutureKey`) attested as ZERO-SLOAD via grep verification. LCG iteration at `MintModule:574/:577` flagged as local-variable arithmetic (no SLOAD).

## Task Commits

1. **Task 10.1: §10 catalog section + summary** — single AGENT-COMMITTED commit (this plan); zero contract / test / KNOWN-ISSUES modifications.

## Files Created/Modified

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-10-CATALOG-section.md` (243 lines) — §10 catalog with 5 CAT sub-headings + commitment-window analysis + double-buffer mitigation analysis + cross-reference to Phase 290 MINTCLN audit-subject surface.
- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-10-SUMMARY.md` (this file).

## Frozen-Contract Discipline Attestation

`git diff --name-only HEAD | grep -E '^(contracts|test)/' | wc -l` returns **0** post-plan. Zero `contracts/` + `test/` modifications. Per `feedback_no_contract_commits.md` + `D-43N-AUDIT-ONLY-01`: Phase 298 is analysis-only; no FIX-class contract changes surface mid-catalog.

## Verification

All success criteria from Plan 10 verification block satisfied:
- `[x]` `298-10-CATALOG-section.md` exists with §A + §B + §C + §D + §E (verified via `test -f` + `grep -q "## CAT-NN"` chain).
- `[x]` §D ∈ {EXEMPT-ADVANCEGAME, EXEMPT-VRFCALLBACK, EXEMPT-RETRYLOOTBOXRNG, VIOLATION} — verified by row-class summary (23 + 1 + 0 + 18 = 42).
- `[x]` Zero `SAFE_BY_DESIGN` classifications (verified via `! grep -q "SAFE_BY_DESIGN"`).
- `[x]` §E VIOLATION rows each have tactic ∈ {(a), (b), (c), (d)} + ≤80-char rationale — 18 VIOLATION rows × 1 tactic letter each (all (a)).
- `[x]` `298-10-SUMMARY.md` exists.
- `[x]` Zero `contracts/` + zero `test/` modifications.

## Methodology Feedback Honored

- `feedback_rng_backward_trace.md` — trace IS backward from `_raritySymbolBatch` keccak consumer at `MintModule:563-:565` through `_processOneTicketEntry`/`processFutureTicketBatch`/`processTicketBatch` outer loops back to the entropy sources (`rngGate` parameter forwarding + `lootboxRngWordByIndex[lrIndex-1]` SLOAD).
- `feedback_rng_window_storage_read_freshness.md` — every SLOAD in the consumer's call graph enumerated, including the pre-existing `traitBurnTicket[lvl][traitId].length` SLOAD inside the assembly output block (classified NON-PARTICIPATING with explicit F-41-02/03-style attestation).
- `feedback_rng_commitment_window.md` — explicit commitment-window analysis added (§D + §E): writes BETWEEN advanceGame transactions are the race-window; intra-transaction Solidity-sequential execution forecloses intra-call races.
- `feedback_verify_call_graph_against_source.md` — every function reference carries explicit `file:line` citation; no "by construction" / "single fn reaches all paths" claims. Phase 294 BURNIE gap precedent honored by enumerating BOTH `processFutureTicketBatch` AND `processTicketBatch` outer loops (the duplicate-logic flagged in `D-42N-MINTCLN-SCOPE-01` requires both to be independently traced because the call paths differ — only the inner `_raritySymbolBatch` is shared).
- `feedback_no_contract_commits.md` — zero `contracts/` mutations; planning artifact only.

## Decisions Made

(See `key-decisions` in frontmatter for the full set; highlights below.)

- **Trace covers both outer-loop entries.** `processFutureTicketBatch` and `processTicketBatch` both converge on `_raritySymbolBatch` — both are traced independently. The entropy sources differ (parameter vs SLOAD) but the participating-slot set is identical.
- **`ticketsOwedPacked[rk][player]` classified Participating? YES** per Phase 290 owed-in-baseKey collapse — the SLOAD IS the cross-call seed-separation invariant.
- **`traitBurnTicket[lvl][traitId].length` classified NON-PARTICIPATING** with self-coupled-within-consumer-stack attestation; grep verifies zero external writers.
- **All 18 VIOLATIONS dispositioned tactic (a)** — gated-revert mirrors the existing `purchaseDeityPass:543` pattern; tactics (b)/(c)/(d) inapplicable per structural constraints.

## Deviations from Plan

None. Plan executed exactly as written. Per Plan 10 `<acceptance_criteria>` block: file exists with all 5 CAT sub-headings; §B Participating? column populated; §C covers every YES slot; every §D row classified (no SAFE_BY_DESIGN); every VIOLATION has §E tactic + rationale; zero `contracts/` + `test/` modifications.

## Issues Encountered

None.

## User Setup Required

None — planning artifact only.

## Next Phase Readiness

- **Main-context integration (Phase 298 Plan 14 — main-context integrator):** Plan 14's §14 unique-slot index dedup will cross-reference §10's 7 participating slots against §1-§13 outputs. The MintModule consumer shares `ticketQueue[rk]` + `ticketsOwedPacked[rk][player]` slots with JackpotModule (§1/§2/§3), DecimatorModule (§4/§13), and LootboxModule (§6/§7) — expect heavy cross-consumer dedup. The `lootboxRngWordByIndex[lrIndex-1]` SLOAD is shared with LootboxModule (§6/§7) + DegeneretteModule (§8) — same VRF index, different consumers.
- **Phase 299 FIXREC handoff:** The 18 tactic-(a) VIOLATIONS in §E identify candidate FIX surfaces: `WhaleModule.purchaseWhaleBundle` / `purchaseLazyPass` (no top-level gate); `LootboxModule.openLootBox` / `openBurnieLootBox` (no daily-VRF gate; domain-separated VRF but shared write target); `MintModule._purchaseFor` (no blanket gate; only level-target redirect at :1221); `WhaleModule.claimWhalePass` (no top-level gate; partial coverage via downstream `_queueTicketRange` revert); `DecimatorModule._awardDecimatorLootbox` (no gate on EOA-reach via `recordDecBurn`); `Storage._redeemWhalePassRange` (no top-level gate).

## Hand-off Statement

§10 backward-trace complete and AGENT-COMMITTED. Plan 14 main-context integrator can consume `298-10-CATALOG-section.md` directly into the §14 unique-slot dedup + §15 cross-consumer writer table + §16 verdict-matrix consolidation. Per `D-298-EXEC-SHAPE-01` Plan 14 owns §17 CAT-06 grep-gate fresh sweep; §10 sub-agent does NOT pre-run the grep gate.

## Self-Check: PASSED

- `[x]` `298-10-CATALOG-section.md` exists at expected path
- `[x]` All 5 CAT sub-headings present (verified via `grep -q "## CAT-01"` + CAT-02 + CAT-03 + CAT-04 + CAT-06)
- `[x]` No `SAFE_BY_DESIGN` token (verified via `! grep -q "SAFE_BY_DESIGN"`)
- `[x]` Zero `contracts/` + `test/` modifications (verified via `git diff --name-only HEAD | grep -E '^(contracts|test)/' | wc -l` returning 0)
- `[x]` §B Participating? column populated for every SLOAD row
- `[x]` §C writer enumeration covers every Participating? YES slot from §B (7/7)
- `[x]` §D verdict matrix classifies every row with one of the 4 exempt/violation tokens (42/42)
- `[x]` §E has tactic + rationale for every VIOLATION row (18/18)
- `[x]` Phase 290 MINTCLN 3-input keccak + owed-in-baseKey explicitly cited in §A function table notes column and §B participating-set summary
- `[x]` `298-10-SUMMARY.md` exists at expected path

---
*Phase: 298-vrf-read-graph-catalog-catalog*
*Plan: 10*
*Completed: 2026-05-18*
