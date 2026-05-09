---
phase: 260-gold-solo-priority-injection
plan: 01
subsystem: jackpot-distribution
tags: [solo-priority, gold-trait, effective-entropy, atomic-injection, batched-approval]
requirements-completed: [SOLO-01, SOLO-02, SOLO-03, SOLO-04, SOLO-05, SOLO-06, SOLO-07]
dependency-graph:
  requires:
    - "Phase 259 (`weightedColorBucket` color==7 gold tier must exist before `_pickSoloQuadrant` ever fires on a non-empty gold set)"
    - "v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399` (audit baseline; SOLO-06/SOLO-07 byte-identity proofs anchored here)"
  provides:
    - "`_pickSoloQuadrant(uint8[4], uint256) → uint8` `internal pure` helper in `DegenerusGameJackpotModule.sol` (Plan 02 `JackpotSoloTester` wraps this via inheritance)"
    - "`effectiveEntropy` substitution at all 4 ETH-distribution sites (L282 / L349 / L524 / L1147) — atomic per ROADMAP atomicity constraint"
    - "L349 ↔ L1147 SPLIT_CALL1 → SPLIT_CALL2 coherence by construction (identical site-local block at both sites)"
    - "REQUIREMENTS.md SOLO-01 / SOLO-08(d) wording amended (D-13/D-14)"
    - "ROADMAP.md Phase 260 success criterion #1 wording amended (D-13/D-14)"
  affects:
    - "Plan 02 JackpotSoloTester (will inherit DegenerusGameJackpotModule and call `_pickSoloQuadrant` via external-pure passthrough)"
    - "Plan 03 SOLO-09 integration test (verifies the L349 → L1147 split-mode coherence end-to-end)"
    - "Phase 261 STAT-04 (gold-solo coverage simulation), STAT-05 (gas regression on `_pickSoloQuadrant` worst-case 4-gold)"
tech-stack:
  added: []
  patterns:
    - "Site-local block discipline (D-08 canonical names: `traitIds`/`traitIdsDaily`, `entropy`/`entropyDaily`, `soloQuadrant`, `effectiveEntropy`)"
    - "Substitution mask `(entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` (clears bits 0-1 then re-injects rotation index that satisfies `JackpotBucketLib.soloBucketIndex(effectiveEntropy) == soloQuadrant`)"
    - "Bit-disjoint entropy axes: bits 0-1 → bucket rotation; bits 4+ → gold tie-break; bits 2-3 unused"
key-files:
  created: []
  modified:
    - "contracts/modules/DegenerusGameJackpotModule.sol — added `_pickSoloQuadrant` helper above `_executeJackpot`; substituted `effectiveEntropy` at L282 (`runTerminalJackpot`), L349 (`payDailyJackpot` jackpot-phase), L524 (`payDailyJackpot` purchase-phase), L1147 (`_resumeDailyEth` SPLIT_CALL2). +46 / -11 lines vs v33.0 baseline `4ce3703d`."
    - ".planning/REQUIREMENTS.md — SOLO-01 visibility `private pure` → `internal pure` (D-13); SOLO-01 + SOLO-08(d) tie-break formula `((entropy >> 4) & 3) % goldCount` → `(entropy >> 4) % goldCount` (D-14)."
    - ".planning/ROADMAP.md — Phase 260 success criterion #1 wording amended (D-13/D-14, lockstep with REQUIREMENTS.md and CONTEXT.md); 260-01-PLAN.md checkbox ticked; progress table updated to `1/3 In progress`."
    - ".planning/STATE.md — Phase 260 plan position advanced to 2 of 3."
decisions:
  - "Helper placed directly above `_executeJackpot` (line ~1086 post-insertion) per CONTEXT.md `<deferred>` planner-default placement (adjacent to the ETH-distribution helper cluster)."
  - "Site-local block at L349 declares `soloQuadrant`/`effectiveEntropy` inside the `if (isJackpotPhase) { ... }` early-return scope; site-local block at L524 declares same names at function-body scope. Solidity emits 'shadows an existing declaration' warnings for these — ACCEPTED (warnings, not errors; compile exits 0). Refactoring to silence the warnings would either rename `effectiveEntropy` (forbidden by D-08 canonical naming) or wrap L527-end of `payDailyJackpot` in an extra block (which re-indents the L527 non-injection-site bonus-traits emit block and breaks SOLO-06 byte-identity proof). Plan 03 phase-end batched diff review can revisit if the user prefers a rename of one site."
  - "STATE.md `progress.completed_plans` advanced to 4/6 (Phase 259 had 3, this plan adds 1; recompute `percent` = 4/6 = 67%)."
metrics:
  duration: "~10 minutes (mechanical injection + 3 doc edits)"
  completed: "2026-05-08"
  task-count: 3
  files-modified: 4
---

# Phase 260 Plan 01: Gold Solo Priority Injection (Helper + 4 Sites + Doc Lockstep) Summary

Add the `_pickSoloQuadrant(uint8[4], uint256) internal pure returns (uint8)` helper to `DegenerusGameJackpotModule.sol` and substitute `effectiveEntropy` at all 4 ETH-distribution sites (L282/L349/L524/L1147) atomically; amend REQUIREMENTS.md and ROADMAP.md SOLO-01/SOLO-08(d) wording per D-13/D-14 to keep the spec ↔ code in lockstep.

## Tasks Executed

### Task 1 — Helper + 4-site `effectiveEntropy` injection in `DegenerusGameJackpotModule.sol`

Added the `_pickSoloQuadrant` helper directly above `_executeJackpot` (post-edit line ~1086) with the exact body locked by CONTEXT.md `<specifics>` (D-04 random-among-gold, drops `& 3` mask):

```solidity
function _pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8) {
    uint8[4] memory goldQuads;
    uint8 goldCount;
    for (uint8 i; i < 4; ++i) {
        if (((traits[i] >> 3) & 7) == 7) {
            goldQuads[goldCount++] = i;
        }
    }
    if (goldCount == 0) {
        return uint8((3 - (entropy & 3)) & 3);
    }
    return goldQuads[uint8((entropy >> 4) % goldCount)];
}
```

Visibility is `internal pure` (D-01) so the Plan 02 `JackpotSoloTester` contract can wrap it via inheritance + an `external pure` passthrough.

Site-local substitution blocks installed at all 4 injection sites (line numbers post-edit):

| Site | Function (line anchor) | Locals declared | `effectiveEntropy` consumed by |
|------|------------------------|-----------------|--------------------------------|
| 1 | `runTerminalJackpot` (L286-289 — block immediately after `traitIds` derivation) | `soloQuadrant`, `effectiveEntropy` | `bucketCountsForPoolCap`, `shareBpsByBucket`, `_processDailyEth` |
| 2 | `payDailyJackpot` jackpot-phase main (L454-455 — block immediately after `traitIdsDaily` derivation, BEFORE the `if (dailyEthBudget != 0)` block at L462) | `soloQuadrant`, `effectiveEntropy` (uses `entropyDaily` because the surrounding code already has `entropyDaily`) | `bucketCountsForPoolCap`, `shareBpsByBucket`, `_processDailyEth` (all inside `if (dailyEthBudget != 0)`) |
| 3 | `payDailyJackpot` purchase-phase main (L529-532 — block AFTER `winningTraitsPacked = _rollWinningTraits(randWord, false)`, BEFORE the bonus-traits emit block) | `traitIds`, `entropy`, `soloQuadrant`, `effectiveEntropy` (entropy hoisted into a local since the existing site computed it inline as a struct field) | `JackpotParams.entropy` field at L555 (`entropy: effectiveEntropy`) → `_executeJackpot` → `_runJackpotEthFlow` |
| 4 | `_resumeDailyEth` (L1175-1178 — full body rewrite extracts canonical site-local block ABOVE the `_processDailyEth` call so substitution is unambiguous and matches L349 line-for-line) | `entropy`, `traitIds`, `soloQuadrant`, `effectiveEntropy` | `bucketCountsForPoolCap`, `shareBpsByBucket`, `_processDailyEth` — inputs are byte-identical to v33.0 except `entropy` → `effectiveEntropy` (and the inline `_rollWinningTraits(...)`/`unpackWinningTraits(...)` chain is hoisted into a `traitIds` local) |

L349 and L1147 produce identical `effectiveEntropy` from identical `(randWord, lvl, EntropyLib.hash2)` inputs by construction (same `randWord`, same `lvl`, same `_rollWinningTraits(randWord, false)`, same `EntropyLib.hash2(randWord, lvl)`, same `_pickSoloQuadrant` output, same substitution formula). SPLIT_CALL1 → SPLIT_CALL2 coherence guaranteed.

### Task 2 — REQUIREMENTS.md + ROADMAP.md wording lockstep (D-13 / D-14)

REQUIREMENTS.md SOLO-01 amended:
- `New private helper` → `New helper`
- `private pure returns (uint8)` → `internal pure returns (uint8)` (D-13)
- `goldQuads[uint8((entropy >> 4) & 3) % goldCount]` → `goldQuads[uint8((entropy >> 4) % goldCount)]` (D-14)
- Appended visibility-rationale sentence about the `JackpotSoloTester` wrapper (per CONTEXT.md D-01..D-03).

REQUIREMENTS.md SOLO-08(d) amended:
- `(d) tie-break is `entropy >> 4 & 3 mod goldCount` (not `entropy & 3`)` → `(d) tie-break is `(entropy >> 4) % goldCount`` (D-14)
- Appended `(rotation reads bits 0-1; tie-break reads bits 4+)` so the disjoint-bits rationale survives the formula simplification.

ROADMAP.md Phase 260 success criterion #1 amended (lockstep):
- `private pure helper present in` → `internal pure helper present in` (D-13)
- `goldQuads[uint8((entropy >> 4) & 3) % goldCount]` → `goldQuads[uint8((entropy >> 4) % goldCount)]` (D-14)

### Task 3 — SOLO-06 + SOLO-07 byte-identity verification

`JackpotBucketLib.sol` byte-identity vs v33.0 baseline `4ce3703d`: PASS (0 diff lines).

8 non-injection sites in `DegenerusGameJackpotModule.sol`: PASS (0 hits on every grep against modified-line markers).

## Automated Verification (recorded per success_criteria #2)

```
=== compile ===
Compiled 1 Solidity file successfully (evm target: paris).
(2 shadow warnings — `soloQuadrant` and `effectiveEntropy` declared in both the L349 inner-`if`-block and the L524 function-body scope of `payDailyJackpot`; warnings, not errors. See "Deviations" below.)

=== helper signature grep === 1
function _pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8)

=== `effectiveEntropy = (entropy & ~uint256(3))` form (expect 3: L282/L524/L1147) === 3

=== `effectiveEntropy = (entropyDaily & ~uint256(3))` form (expect 1: L349) === 1

=== `entropy: effectiveEntropy` (expect 1: L524 JackpotParams field) === 1

=== `_pickSoloQuadrant(traitIds(Daily)?, entropy(Daily)?)` call sites (expect ≥4) === 4

=== history-comment grep `(previously|formerly|used to|swapped from|changed from|v33\.0 used|v34\.0 update|was rotation)` (expect 0) === 0

=== JackpotBucketLib byte-identity vs 4ce3703d (expect 0 lines) === 0

=== Non-injection token grep — `_rollWinningTraits(randWord, true)` mods (expect 0) === 0

=== Non-injection token grep — `_runEarlyBirdLootboxJackpot|_distributeTicketJackpot|_awardDailyCoinToTraitWinners|emitDailyWinningTraits` mods (expect 0) === 0

=== Diff hunk count vs v33.0 baseline === 8 hunks total, all within the 5 expected areas:
- L284 (Site 1: `runTerminalJackpot`)
- L449 / L459 / L481 (Site 2 sub-hunks: `payDailyJackpot` jackpot-phase main — substitution block at L451-455, then 3 substitution sites in the if-block at L463 / L485 / L489)
- L522 / L547 (Site 3 sub-hunks: `payDailyJackpot` purchase-phase — substitution block at L526-532 and `JackpotParams.entropy` at L555)
- L1077 (Site 5: `_pickSoloQuadrant` helper insertion above `_executeJackpot`)
- L1140 (Site 4: `_resumeDailyEth` body rewrite)

=== Diffstat ===
contracts/modules/DegenerusGameJackpotModule.sol | 57 +++++++++++++++++++-----
1 file changed, 46 insertions(+), 11 deletions(-)

=== REQUIREMENTS.md grep ===
internal-pure SOLO-01 form: 1
legacy `private pure returns (uint8)`: 0
new tie-break formula `goldQuads[uint8((entropy >> 4) % goldCount)]`: 1
legacy tie-break `goldQuads[uint8((entropy >> 4) & 3) % goldCount]`: 0
new SOLO-08(d) wording `(d) tie-break is \`(entropy >> 4) % goldCount\``: 1
legacy SOLO-08(d) wording `entropy >> 4 & 3 mod goldCount`: 0

=== ROADMAP.md grep ===
new `internal pure helper present in`: 1
legacy `private pure helper present in`: 0
new tie-break formula: 1
legacy tie-break formula: 0
```

All success_criteria #1-#8 (SOLO-01..07 + REQUIREMENTS/ROADMAP wording) satisfied. Success criterion #9 (diff staged but NOT committed by this plan; awaiting batched D-10 user approval at phase close) is satisfied by the working-tree state below.

## Working Tree State (D-10 batched approval — NOT committed by this plan)

```
$ git status --short
 M .planning/REQUIREMENTS.md
 M .planning/ROADMAP.md
 M .planning/STATE.md
 M contracts/modules/DegenerusGameJackpotModule.sol
```

**Plan 01 will commit only `260-01-SUMMARY.md` itself** (alongside `STATE.md` + `ROADMAP.md` plan-progress tracking updates) per the orchestrator's sequential-executor instruction. The contract diff and the REQUIREMENTS.md / ROADMAP.md success-criterion-#1 wording amendments stay staged-but-uncommitted; Plan 03's phase-end checkpoint presents the FULL phase batched diff (this plan's contract + REQUIREMENTS + ROADMAP edits + Plan 02's `JackpotSoloTester` + unit tests + Plan 03's SOLO-09 integration test) for a single explicit user approval per `feedback_batch_contract_approval.md`, `feedback_no_contract_commits.md`, `feedback_never_preapprove_contracts.md`.

## Deviations from Plan

**1. Solidity shadow warnings at L349 / L524 site-local declarations** — `soloQuadrant` and `effectiveEntropy` are declared both inside the `if (isJackpotPhase) { ... }` block at L454-455 (jackpot-phase main path) AND at function-body scope at L531-532 (purchase-phase path) within `payDailyJackpot`. Solidity 0.8.34 emits "This declaration shadows an existing declaration" warnings for these even though the `return` at L524 makes the two paths execution-disjoint. **Disposition: ACCEPTED** — the warnings are NOT errors (compile exits 0; success_criterion #1 satisfied). The two natural fixes both have downsides:
- Renaming `effectiveEntropy` at one site violates D-08 canonical naming ("`effectiveEntropy` is canonical (used in the success-criterion text; do not rename)").
- Wrapping the L527-end purchase-phase code in an additional `{ ... }` block silences the warning but re-indents every line in the wrap, including the L527 bonus-traits emit block — which would break the SOLO-06 byte-identity proof against v33.0 baseline at the L527 non-injection site (every line in the block would appear as a `+/-` whitespace edit in `git diff`).

The accepted compromise is to leave the warnings in place. Plan 03's phase-end batched diff review provides an opportunity for the user to revisit if they prefer a rename of one site (e.g., `effectiveEntropyJackpot` at L349 / `effectiveEntropy` at L524). Documented here for reviewer awareness; no behavior impact (warnings are static-analysis advisory only).

**2. Inserted helper directly above `_executeJackpot` (post-edit L1086)** — Plan deferred placement to the planner with default "adjacent to `_executeJackpot` / `_processDailyEth` / `_runJackpotEthFlow` cluster (~lines 1080–1190)". I chose immediately above `_executeJackpot` (replacing nothing — inserted before the comment header). This is informational, not a deviation per se — it matches the planner-default in CONTEXT.md `<deferred>`.

No bug fixes (Rule 1) or critical missing functionality (Rule 2) needed. No architectural questions (Rule 4). Plan executed exactly as specified except for the one accepted shadow-warning deviation above.

## Authentication Gates

None encountered. All work was local code edits on the main working tree.

## Threat Surface Scan

This plan is itself the implementation of CONTEXT.md `<threat_model>` mitigations T-260-01-01 through T-260-01-07. No NEW security-relevant surface introduced beyond what the threat model already documented. The substitution mask shape `(entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` is the locked formula from SOLO-02..05 and CONTEXT.md `<specifics>` — verified by 4× site-local grep (3× `entropy` form + 1× `entropyDaily` form) and the call-site `entropy: effectiveEntropy` grep at L555.

## Known Stubs

None. The helper has reachable branches in both the zero-gold case (`return uint8((3 - (entropy & 3)) & 3);`) and the gold-present case (`return goldQuads[uint8((entropy >> 4) % goldCount)];`). Plan 02 unit tests (SOLO-08) exercise both. No placeholder values, no hardcoded empty data, no UI stubs.

## Self-Check: PASSED

- Files claimed modified — all 4 verified present in `git status --short`:
  - `contracts/modules/DegenerusGameJackpotModule.sol` — FOUND
  - `.planning/REQUIREMENTS.md` — FOUND
  - `.planning/ROADMAP.md` — FOUND
  - `.planning/STATE.md` — FOUND
- Helper signature grep returns 1: VERIFIED.
- 4 substitution sites accounted for (3× `entropy` form + 1× `entropyDaily` form): VERIFIED.
- 4 `_pickSoloQuadrant` call sites: VERIFIED.
- SOLO-06 / SOLO-07 byte-identity proofs: VERIFIED (0 diff lines for `JackpotBucketLib.sol`; 0 token-grep hits for non-injection-site identifiers in the `DegenerusGameJackpotModule.sol` patch).
- REQUIREMENTS.md / ROADMAP.md wording lockstep with CONTEXT.md D-13/D-14: VERIFIED (10/10 grep checks pass).
- Compile exits 0: VERIFIED (with 2 shadow warnings, accepted per Deviation #1).
- Diff staged but NOT committed for contract + REQUIREMENTS + ROADMAP-success-criterion-#1: VERIFIED (`git status --short` shows working-tree-modified, no `M ` (staged) prefix on the contract file beyond what the user has explicitly staged).
- Commits NOT created by this plan beyond the `docs(260-01): plan summary` commit that records this SUMMARY.md and the STATE/ROADMAP-tracking updates.
