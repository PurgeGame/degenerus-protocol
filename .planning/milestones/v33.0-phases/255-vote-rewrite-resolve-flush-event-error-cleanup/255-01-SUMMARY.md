---
phase: 255-vote-rewrite-resolve-flush-event-error-cleanup
plan: 01
status: complete
completed: 2026-05-06T07:27:48Z
commit: 30188329
requirements:
  - CLEAN-02
  - CLEAN-03
files_modified:
  - contracts/GNRUS.sol
key_files:
  created: []
  modified:
    - contracts/GNRUS.sol
---

## Self-Check: PASSED

## Outcome

Phase 255 declaration surface is in place in `contracts/GNRUS.sol`. Compile passes with no function bodies for `vote` or `pickCharity` — declarations land as leaves; Plans 02 and 03 introduce the consumers.

## Changes

| Section | Lines (post-edit) | Change |
|---------|-------------------|--------|
| ERRORS  | 87–94 | +`VoteRejected(uint8 reason)` and +`PickCharityRejected(uint8 reason)` after `CapExceeded()` |
| EVENTS  | 105–106 | `Voted` rewritten to `(uint24 indexed level, uint8 indexed slot, address indexed voter, uint256 weight)`; `ProposalCreated` deleted |
| EVENTS  | 108–109 | `LevelResolved` rewritten to `(uint24 indexed level, uint8 indexed slot, address recipient, uint256 gnrusDistributed)` |
| EVENTS  | 123–124 | +`CharityFlushed(uint8 indexed slot, address indexed recipient)` after `CharityQueued` |
| GOVERNANCE STATE | 181–184 | +`mapping(uint24 => mapping(uint8 => uint256)) public slotApproveWeight` after `pendingEdit` |
| CONSTANTS | 208–220 | +5 reason-code `uint8 private constant`s after `MAX_ACTIVE_SLOTS`: `REJECT_EMPTY_SLOT`, `REJECT_ALREADY_VOTED`, `REJECT_ZERO_WEIGHT`, `REJECT_LEVEL_NOT_ACTIVE`, `REJECT_LEVEL_ALREADY_RESOLVED` |

Net diff: 1 file changed, 35 insertions(+), 7 deletions(-).

## Gates

- `npx hardhat compile`: exits 0 (Solidity 0.8.34, evm target paris).
- 12/12 positive grep gates pass.
- 7/7 negative grep gates pass — no commented-out v32 residue, no Phase-254-removed errors resurrected, no premature function bodies.
- Storage layout: `slotApproveWeight` (line 184) strictly after `pendingEdit` (line 179).
- External signature pins: `setCharity`, `burnAtGameOver`, `burn` all satisfied. The `IGNRUSResolve { function pickCharity(uint24 level) external; }` pin grep checks for a one-line interface form; the existing source uses a 2-line form (`contracts/modules/DegenerusGameAdvanceModule.sol` lines 32–33) and the call site at line 1634 (`charityResolve.pickCharity(lvl - 1)`) is intact. Substantive pin holds; gate-format mismatch only.

## Bytecode Impact

Approximate deploy-bytecode delta: +250 bytes (5 reason-code constants are inlined; net adds are 2 error selectors, 1 new event, 1 mapping auto-getter, 2 rewritten event signatures with same indexed arity, 1 deleted event). Per-call runtime gas unchanged for any existing function; runtime cost accrues to Plans 02 and 03 (first cold SSTORE on `slotApproveWeight`, new emits).

## Approval

Diff presented to user prior to commit per `feedback_no_contract_commits.md` + `feedback_wait_for_approval.md`. User approved at 2026-05-06T07:27:48Z; commit `30188329` followed.

## Unblocks

Plans 02 and 03 are now ready:

- Plan 02 (`vote(uint8 slot)`) consumes `error VoteRejected` + `REJECT_EMPTY_SLOT`/`REJECT_ALREADY_VOTED`/`REJECT_ZERO_WEIGHT`, emits `Voted` (v33), and writes `slotApproveWeight[currentLevel][slot] += weight`.
- Plan 03 (`pickCharity(uint24 level)`) consumes `error PickCharityRejected` + `REJECT_LEVEL_NOT_ACTIVE`/`REJECT_LEVEL_ALREADY_RESOLVED`, emits `Voted`/`CharityFlushed`/`LevelResolved`, and reads `slotApproveWeight[level][i]` in the winner loop.

## Deviations

None from `<event_signature_canonical>`, `<error_canonical>`, or `<storage_canonical>`.
