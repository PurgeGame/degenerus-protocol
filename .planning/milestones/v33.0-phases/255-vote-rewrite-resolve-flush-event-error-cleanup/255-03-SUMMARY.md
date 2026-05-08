---
phase: 255-vote-rewrite-resolve-flush-event-error-cleanup
plan: 03
status: complete
completed: 2026-05-06T07:47:57Z
commit: ac1d3741
requirements:
  - RES-01
  - RES-02
  - RES-03
  - RES-04
files_modified:
  - contracts/GNRUS.sol
key_files:
  created: []
  modified:
    - contracts/GNRUS.sol
---

## Self-Check: PASSED

## Outcome

`pickCharity(uint24 level) external onlyGame` implemented in `contracts/GNRUS.sol`. Atomic per-call resolution: idempotence guards FIRST, inline flush phase, 3 short-circuit skip paths, strict-`>` winner selection with sentinel, distribution preserved verbatim from v32. CEI-clean — zero external calls.

## Section Landed

New `// GOVERNANCE -- RESOLVE` section banner inserted between GOVERNANCE -- VOTE and RECEIVE FUNCTION. Function spans 99 lines including NatSpec.

## Operation Order (Locked, D-255-FLUSH-ORDER-01)

Cross-checked against canonical order via automated grep+sed pipeline. Observed sequence in pickCharity body matches the canonical 9-step plan:

| # | Action |
|---|--------|
| 1 | Argument validation: `revert PickCharityRejected(REJECT_LEVEL_NOT_ACTIVE)` / `revert PickCharityRejected(REJECT_LEVEL_ALREADY_RESOLVED)` |
| 2 | Idempotence guards SET FIRST: `levelResolved[level] = true; currentLevel = level + 1;` |
| 3 | Inline flush loop with local `bitmap` + `pSet` variables. Per set bit: read `pendingEdit[i]` → write `currentSlate[i]` → mutate local bitmap → `delete pendingEdit[i]` → emit `CharityFlushed(i, pendingValue)`. Final: `currentActiveBitmap = bitmap; pendingEditSet = 0;` |
| 4 | Skip-path A — `if (bitmap == 0) { emit LevelSkipped(level); return; }` |
| 5 | Winner phase — `bestSlot = type(uint8).max` sentinel; iterate 0..19; strict `if (w > bestWeight)` for RES-02 lowest-slot tie-break |
| 6 | Skip-path B — `if (bestSlot == type(uint8).max) { emit LevelSkipped(level); return; }` |
| 7 | Distribution math: `(unallocated * DISTRIBUTION_BPS) / BPS_DENOM` (preserved verbatim from v32) |
| 8 | Skip-path C — `if (distribution == 0) { emit LevelSkipped(level); return; }` |
| 9 | Apply: balanceOf write + `emit Transfer(address(this), recipient, distribution)` + `emit LevelResolved(level, bestSlot, recipient, distribution)` |

3 LevelSkipped emit sites + 1 Transfer + 1 LevelResolved (mutually exclusive — exactly one outcome per call).

## D-255-CEI-01 Negative Grep (Body-Only)

| Pattern | Count | Status |
|---------|-------|--------|
| `.call(` / `.delegatecall(` / `.staticcall(` / `sdgnrs.` / `vault.` / `game.` / `steth.` inside body | 0 | ZERO external calls |
| `_flushedBitmap(` call inside body | 0 | Inline flush, NOT helper call |
| `_flushPending` factored helper | 0 | Inline flush per CONTEXT recommendation |
| `w >= bestWeight` | 0 | Strict `>` only (RES-02) |
| `bestSlot >= MAX_ACTIVE_SLOTS` / `recipient == address(this)` orphaned guards | 0 | NO dead guards |

## External Signature Pin

| Pin | Result |
|-----|--------|
| `function pickCharity(uint24 level) external onlyGame` in contracts/GNRUS.sol | 1 ✓ |
| `interface IGNRUSResolve { function pickCharity(uint24 level) external; }` in DegenerusGameAdvanceModule.sol | present (lines 32–33, 2-line form) ✓ |
| `charityResolve.pickCharity(lvl - 1);` in DegenerusGameAdvanceModule.sol | 1 ✓ |

## Theoretical Worst-Case Gas

| Scenario | Estimate |
|----------|----------|
| Steady state (5 active, 10 voters, 0 pending) | ~70k |
| Edit-heavy (10 active, 20 voters, 5 pending) | ~250k |
| Worst case (20 active, 20 voters, 20 pending) | ~750k cold; net ~654k after EIP-3529 refunds |
| Skip-path B (no votes) | ~25k |
| Sad-paths (REJECT_LEVEL_*) | ~5k each |

Block gas limit ≈ 30M; worst-case pickCharity is ~2.5% of a full block. Phase 256 measurement targets per `<gas_table>` in 255-03-PLAN.md.

## Approval

Diff presented to user prior to commit per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`. User approved batched diff (Plans 02 + 03) at 2026-05-06T07:47:57Z; per-plan atomic commits followed (Plan 02: `e734cfe6`, Plan 03: `ac1d3741`).

## Phase 255 Closure Attestation

All 5 ROADMAP success criteria for Phase 255 satisfied across Plans 01/02/03:

1. **vote() rejects empty / double-vote / zero-weight; emits v33 Voted** — Plan 02.
2. **NO bonus / NO threshold; levelVaultOwner / levelSdgnrsSnapshot absent** — Plan 02 negative grep + Phase 254 cleanup.
3. **Atomic flush; per-edit emit; flush does not revert** — this plan (RES-01).
4. **Winner iterates 0→19 with strict `>`; 3 LevelSkipped paths; v33 LevelResolved with `slot` indexed** — this plan + Plan 01 (RES-02..04).
5. **Cleanup is functional removal; new errors VoteRejected + PickCharityRejected with reason codes; no orphaned reverts** — Plan 01 (CLEAN-02 + CLEAN-03) + Plan 02/03 reachability checks.

10/10 requirements addressed: VOTE-01..04, RES-01..04, CLEAN-02, CLEAN-03.

## Unblocks

- **Phase 256** (test coverage) — full vote() + pickCharity() surface present; downstream `DegenerusGameAdvanceModule:1634` runtime-restored; integration tests can exercise the full game-advance → pickCharity chain.
- **Phase 257** (delta audit) — impl-frozen baseline at commit `ac1d3741`.

## Deviations

None from `<flush_order_canonical>`, `<flush_implementation_notes>`, `<winner_loop_canonical>`, `<distribution_canonical>`, or the function body in step 2 of `<action>`.
