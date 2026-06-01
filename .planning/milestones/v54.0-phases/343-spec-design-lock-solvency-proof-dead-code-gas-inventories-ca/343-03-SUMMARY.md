---
phase: 343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca
plan: 03
subsystem: testing
tags: [solidity, audit, dead-code, gas-scavenger, keeper-funding, de-custody, spec]

# Dependency graph
requires:
  - phase: 343-01
    provides: "343-GREP-ATTESTATION.md — the ACTUAL re-pinned file:line anchors (source of truth) for the kill-set + the GAS-01 blast radius"
provides:
  - "343-CLEANUP-INVENTORY.md — CLEANUP-01 grep-attested de-custody dead-code kill-set (14 items), each with actual file:line + a re-run repo-wide caller grep; the D-06 producer-before-consumer integrity gate; D-05 poolOf-deleted-entirely note; the payable-ABI narrow target; the new AfKing IGame ABI additions"
  - "343-GAS-INVENTORY.md — GAS-01 gas-scavenger-lens advisory candidate list (11 SCAV rows, behavior-identical tagged, ADVISORY/UNVALIDATED, 345 /gas-skeptic the gate); the ~9k/buy baseline; the claimableWinnings {uint128 normal, uint128 keeper} packing candidate framed per PLAN-V54 §2 + flagged for 345"
affects: [344-impl-cleanup-02-removal, 345-gas-cleanup, 343-04-edit-order-map, 343-05-spec-index]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Grep-attested kill-set: every removal candidate carries a re-run repo-wide caller grep (command + hit count) proving orphan-after-removal"
    - "Gas-scavenger lens adopted INLINE (no nested skill/sub-agent): aggressive ADVISORY candidate list, validation deferred to the 345 gas-skeptic gate"

key-files:
  created:
    - .planning/phases/343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca/343-CLEANUP-INVENTORY.md
    - .planning/phases/343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca/343-GAS-INVENTORY.md
  modified: []

key-decisions:
  - "D-05 enforced: AfKing.poolOf deleted entirely (no replacement view); canonical balance = game.keeperFundingOf(player)"
  - "D-06 integrity gate recorded: AfKing.withdraw/poolOf orphaned ONLY after the v48 recovery legs (StakedStonk:539 + Vault:517) are removed — producer-before-consumer order for 344"
  - "Payable-ABI kill narrowed to AfKing.sol:43 (the only interface decl) + the IDegenerusGameModules.sol:237 comment — payable→non-payable IN PLACE, not a deletion"
  - "D-04 packing candidate documented + FLAGGED for 345 (zero hot-path benefit; ~15+ access-site blast radius; trades against feedback_security_over_gas); default = keep separate mapping; NOT decided here"

patterns-established:
  - "Pattern: paper-only inventory authoring with git diff --name-only -- contracts/ asserted EMPTY before every commit"
  - "Pattern: gas-scavenger persona adopted inline (read SKILL.md, apply the lens directly) to avoid nesting a skill fleet in a subagent"

requirements-completed: [CLEANUP-01, GAS-01]

# Metrics
duration: ~14min
completed: 2026-05-30
---

# Phase 343 Plan 03: De-Custody Dead-Code Kill-Set + Gas-Opportunity Inventory Summary

**CLEANUP-01 grep-attested 14-item de-custody kill-set (each with a re-run caller grep + the D-06 integrity gate) and the GAS-01 gas-scavenger-lens 11-candidate advisory inventory + the claimableWinnings packing candidate framed and flagged for the 345 gas-skeptic — both paper-only, zero contracts/ edits.**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-05-30
- **Completed:** 2026-05-30
- **Tasks:** 2
- **Files modified:** 2 created

## Accomplishments

- **343-CLEANUP-INVENTORY.md (CLEANUP-01):** the de-custody dead-code kill-set — 14 items, each with its ACTUAL `file:line` (from the Wave-1 attestation, re-confirmed) AND a RE-RUN repo-wide caller grep recorded with the exact command + hit count. `recoverAfKingPool` recorded at **0 external callers** (`grep -rn 'recoverAfKingPool' contracts/` → 1 hit, only its own def). `depositFor` at 0 hits. `withdraw`/`poolOf` at exactly 2 callers — both inside the v48 recovery legs. The **D-06 integrity gate** (poolOf/withdraw orphaned ONLY after StakedStonk:539 + Vault:517 are removed) is its own section with the 344 edit-order constraint. `poolOf` recorded **deleted entirely per D-05** (canonical = `game.keeperFundingOf`). The payable-ABI kill **narrowed** to `AfKing.sol:43` + the `IDegenerusGameModules.sol:237` comment (payable→non-payable in place). The **new AfKing IGame ABI additions** (depositKeeperFunding/withdrawKeeperFunding/keeperFundingOf + extended keeperSnapshot) recorded as an ADD, not a kill.
- **343-GAS-INVENTORY.md (GAS-01):** the gas-scavenger-lens advisory candidate list — 11 SCAV rows over the D-03 blast radius, each tagged behavior-identical / same-results, with a Skeptic-note column. Whole list marked **ADVISORY / UNVALIDATED** with the **345 `/gas-skeptic`** named as the sole gate. The **~9k/buy de-custody baseline** noted and explicitly excluded from the incremental total. The **claimableWinnings `{uint128 normal, uint128 keeper}` packing candidate** documented with the full PLAN-V54 §2 framing (width-safe, zero hot-path benefit, ~15+ attested access sites, trades against `feedback_security_over_gas`) and **FLAGGED for 345**; default = keep the separate mapping.
- Both `<automated>` verify gates pass; `git diff --name-only -- contracts/` EMPTY throughout; no "v1/simplified/for now" language.

## Task Commits

Each task was committed atomically:

1. **Task 1: CLEANUP-01 grep-attested de-custody kill-set inventory** — `c35aadb2` (docs)
2. **Task 2: GAS-01 gas-scavenger advisory candidate list + packing framing** — `428f7581` (docs)

**Plan metadata:** (final docs commit — SUMMARY + STATE + ROADMAP)

## Files Created/Modified

- `.planning/phases/343-.../343-CLEANUP-INVENTORY.md` (125 lines) — the CLEANUP-01 14-item grep-attested kill-set + D-06 integrity gate + D-05/payable-narrow/IGame-ABI-additions notes
- `.planning/phases/343-.../343-GAS-INVENTORY.md` (98 lines) — the GAS-01 gas-scavenger-lens advisory candidate list + the packing-candidate framing flagged for 345

## Decisions Made

- **Gas-scavenger persona adopted INLINE** (read `~/.claude/skills/gas-scavenger/SKILL.md`, applied the aggressive code-removal lens directly over the blast-radius files) rather than invoking `/gas-scavenger` as a skill or spawning a sub-agent — per the plan's no-nesting constraint. The doc references the gas-scavenger lens explicitly and carries its optimizer context (runs=2, bytecode-weighted) and output discipline (behavior-identical tag, confidence, Skeptic-note).
- **Trusted the attestation over RESEARCH on every conflict** (e.g. `poolOf` view at `:492`/return `:493`, recovery leg at `StakedStonk:539`, the single payable decl at `AfKing.sol:43`, comment-only at `IDegenerusGameModules.sol:237`) and re-ran every caller grep against the live tree rather than transcribing RESEARCH.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' actions, acceptance criteria, and `<automated>` verifies were satisfied directly; no bugs, missing functionality, or blocking issues surfaced (paper-only Markdown authoring over a byte-identical-to-`83a84431` tree).

## Issues Encountered

None. The `_poolOf` repo-wide grep flagged 1 non-AfKing file (`DegenerusGame.sol:1819`); inspection confirmed it is a comment-only mention ("mis-credited the keeper's own _poolOf"), not a symbol reference — recorded as such in the inventory, not a live caller.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **344 IMPL** has the CLEANUP-02 removal input: the grep-attested kill-set + the D-06 producer-before-consumer order constraint (remove the Vault/sDGNRS recovery legs before/with deleting `poolOf`/`withdraw`).
- **345 GAS+CLEANUP** has the GAS-01 advisory candidate list to validate via `/gas-skeptic` + the packing candidate flagged for evaluation.
- **343-04** (edit-order map) can cite this kill-set's ordering gate; **343-05** (SPEC index) can index both deliverables.
- No blockers. Zero `contracts/*.sol` edits — the paper-only invariant held.

## Self-Check: PASSED

- FOUND: 343-CLEANUP-INVENTORY.md
- FOUND: 343-GAS-INVENTORY.md
- FOUND: 343-03-SUMMARY.md
- FOUND commit: c35aadb2 (Task 1)
- FOUND commit: 428f7581 (Task 2)
- `git diff --name-only -- contracts/` EMPTY (zero contract edits)

---
*Phase: 343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca*
*Completed: 2026-05-30*
