# Phase 255: Vote Rewrite, Resolve Flush & Event/Error Cleanup — Context

**Gathered:** 2026-05-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Re-add `vote(uint8 slot)` and `pickCharity(uint24 level)` to `contracts/GNRUS.sol` from scratch against the v33.0 storage skeleton landed in Phase 254. Rewrite `Voted` and `LevelResolved` event signatures (slot-based per CLEAN-02), delete `ProposalCreated`, delete `ProposalLimitReached` / `AlreadyProposed` / `InvalidProposal` errors, add a single `VoteRejected(uint8 reason)` error covering the three vote sad paths (empty slot, already voted, zero weight). Reuse `_flushedBitmap` / `_popcount32` (Phase 254) for the atomic flush at `pickCharity` entry.

**Functional surface delivered at Phase 255 close:**
- `setCharity(uint8, address)` (Phase 254 — unchanged)
- 5 view helpers (Phase 254 — unchanged)
- `burn(uint256)` + `burnAtGameOver()` + soulbound stubs + `receive()` (unchanged from v32)
- **NEW:** `vote(uint8 slot) external`
- **NEW:** `pickCharity(uint24 level) external onlyGame`
- v33.0 storage skeleton (Phase 254)

**External signature pin:** `pickCharity(uint24 level) external onlyGame` is consumed by `contracts/modules/DegenerusGameAdvanceModule.sol:1634` via `interface IGNRUSResolve { function pickCharity(uint24 level) external; }`. Phase 255 MUST preserve this signature exactly.

**Audit baseline:** v33.0 HEAD post-Phase-254 (commit `469d7fc1` — `feat(254): GNRUS v33.0 — storage repack + setCharity + view helpers`). Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_wait_for_approval.md` + `feedback_manual_review_before_push.md`: every `contracts/GNRUS.sol` modification requires explicit per-commit user approval.

</domain>

<decisions>
## Implementation Decisions

### Vote Sad-Path Error Shape

- **D-255-VOTEREJECT-01 (single `VoteRejected(uint8 reason)` error with reason codes):** Three vote sad paths fold into one error type to minimize selector count + bytecode footprint.
  ```solidity
  error VoteRejected(uint8 reason);

  uint8 private constant REJECT_EMPTY_SLOT     = 0;  // currentSlate[slot] == address(0)
  uint8 private constant REJECT_ALREADY_VOTED  = 1;  // hasVoted[level][voter][slot] == true
  uint8 private constant REJECT_ZERO_WEIGHT    = 2;  // sdgnrs.balanceOf(voter) / 1e18 == 0
  ```
  - Tests assert via Hardhat's `revertedWithCustomError(contract, "VoteRejected").withArgs(N)` — single selector, three reason values.
  - `slot >= MAX_ACTIVE_SLOTS` (== 20) bound check uses the EXISTING `error InvalidSlot()` from Phase 254 — slot bounds is a structural validation, not a vote-rejection state.
  - REQUIREMENTS.md CLEAN-03 hint about "repurpose `InsufficientStake` for empty-balance voter rejection" is now stale — `InsufficientStake` was deleted in Phase 254 and `VoteRejected(REJECT_ZERO_WEIGHT)` replaces it.

### pickCharity Flush Event Shape

- **D-255-FLUSH-EVENT-01 (per-edit `CharityFlushed(uint8 indexed slot, address indexed recipient)` emit):** At `pickCharity` entry, the flush iterates `pendingEditSet` bits and applies each pending edit to `currentSlate` + `currentActiveBitmap`. For EACH applied edit, emit `CharityFlushed(slot, recipient)` once. `recipient == address(0)` signals a flush-removed slot (matches D-254-PENDING-01 sentinel).
  ```solidity
  event CharityFlushed(uint8 indexed slot, address indexed recipient);
  ```
  - Worst case: 20 emits per `pickCharity` call (when every unlocked slot has a pending edit).
  - Mirrors Phase 254's `CharityApplied` / `CharityQueued` single-event style — indexer pattern is consistent across the v33.0 charity lifecycle.
  - Three-event lifecycle for indexers: `CharityQueued` → `CharityFlushed` → (optionally) `LevelResolved` if winner is at the same slot.
  - Aggregate-event variant rejected for paired-array encoding overhead and indexer ergonomics (paired arrays in indexed event topics not supported; would force `data` field with manual decode).

### Per-(Level, Slot) Approve Weight Storage

- **D-255-WEIGHT-STORAGE-01 (`mapping(uint24 => mapping(uint8 => uint256)) public slotApproveWeight`):** Standard nested mapping accumulator. `vote(uint8 slot)` does `slotApproveWeight[currentLevel][slot] += weight`. `pickCharity` winner loop reads `slotApproveWeight[level][i]` for each set bit in the post-flush `currentActiveBitmap`.
  - Two cold SLOADs per `vote()` (level outer + slot inner).
  - Auto-getter `slotApproveWeight(uint24, uint8) returns (uint256)` exposed for indexers + tests at zero extra code cost.
  - Old-level entries persist in storage post-pickCharity (no cleanup — deliberate per `feedback_no_dead_guards.md`; 20-cold-SSTORE wipe per level would burn ~110k gas for no functional benefit, and historical query is a free side-benefit for indexers).
  - Packed-key (`mapping(uint256 => uint256)` with `(level << 8) | slot`) variant rejected — saves ~2.1k gas/vote on cold SLOADs but loses auto-getter ergonomics, adds key-pack helper code, and the savings are negligible given vote() worst case (~50k gas total — see <gas_table> below).
  - Per-level static array (`mapping(uint24 => uint256[20])`) variant rejected — 20 cold SSTOREs zero-init gas spike on first vote of each level (~440k gas) is unacceptable.
  - Smaller weight type (uint96 / uint128) variant rejected — premature packing; only one weight per (level, slot) tuple, no second weight to pair with. uint256 is the natural type.

### vote() Revert Order

- **D-255-VOTE-REVERT-ORDER-01 (locked):** `vote(uint8 slot)` revert order:
  1. **InvalidSlot** — `if (slot >= MAX_ACTIVE_SLOTS) revert InvalidSlot();` (reuses Phase 254 error)
  2. **VoteRejected(REJECT_EMPTY_SLOT)** — `if (currentSlate[slot] == address(0)) revert VoteRejected(REJECT_EMPTY_SLOT);`
  3. **VoteRejected(REJECT_ALREADY_VOTED)** — `if (hasVoted[level][voter][slot]) revert VoteRejected(REJECT_ALREADY_VOTED);`
  4. **VoteRejected(REJECT_ZERO_WEIGHT)** — `uint256 weight = sdgnrs.balanceOf(voter) / 1e18; if (weight == 0) revert VoteRejected(REJECT_ZERO_WEIGHT);`
  5. State writes: `hasVoted[level][voter][slot] = true; slotApproveWeight[level][slot] += weight;`
  6. `emit Voted(level, slot, voter, weight);`
  - Order chosen so cheapest checks (storage-read `currentSlate`, storage-read `hasVoted`) fire before the expensive cross-contract `sdgnrs.balanceOf` call — sad-path callers don't pay for the indirect call.

### pickCharity Atomic Flush Order

- **D-255-FLUSH-ORDER-01 (locked):** `pickCharity(uint24 level)` operation order:
  1. **Modifier:** `onlyGame` (preserved from v32 — caller is `DegenerusGameAdvanceModule:1634`)
  2. **Level argument check:** `if (level != currentLevel) revert ...;` and `if (levelResolved[level]) revert ...;` — reuse `LevelNotActive` and `LevelAlreadyResolved`? **NO** — Phase 254 deleted both errors per D-254-ERROR-PRUNE-01. Need to either re-add them or pick one of the existing errors. **DECISION:** add a single new error `error PickCharityRejected(uint8 reason)` mirroring `VoteRejected` shape (reasons: REJECT_LEVEL_NOT_ACTIVE = 0, REJECT_LEVEL_ALREADY_RESOLVED = 1) — keeps the `*-Rejected(reason)` pattern consistent across v33.0 governance.
     - `levelResolved[level] = true;` and `currentLevel = level + 1;` set BEFORE flush (idempotence guard locked first; the rest of the function is reentrancy-irrelevant since vote/pickCharity are non-reentrant by EVM semantics — the storage writes are committed before the loop).
  3. **Flush phase:** iterate `pendingEditSet` bits 0..19; for each set bit:
     a. Read `pendingEdit[slot]` once.
     b. Update `currentSlate[slot]` to the pending value.
     c. Update `currentActiveBitmap` bit (set if pending value != 0; clear if pending value == 0).
     d. Clear `pendingEdit[slot]` (zero out the mapping entry).
     e. `emit CharityFlushed(slot, pendingValue);`
     After the loop, set `pendingEditSet = 0;` (single SSTORE clears the bitmap).
  4. **Skip-path A:** `if (currentActiveBitmap == 0) { emit LevelSkipped(level); return; }` — zero active slots after flush (RES-03 path a).
  5. **Winner phase:** iterate slots 0..19 against the post-flush `currentActiveBitmap`:
     - Track `bestSlot = type(uint8).max;` and `bestWeight = 0;`
     - For each set bit `i`: if `slotApproveWeight[level][i] > bestWeight`, update `bestWeight = slotApproveWeight[level][i]; bestSlot = i;`
     - Strict `>` ensures lowest-slot tie-break (RES-02).
  6. **Skip-path B:** `if (bestSlot == type(uint8).max) { emit LevelSkipped(level); return; }` — zero votes cast (RES-03 path b).
  7. **Distribution:** `uint256 unallocated = balanceOf[address(this)]; uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;`
  8. **Skip-path C:** `if (distribution == 0) { emit LevelSkipped(level); return; }` — 2% rounds to zero (RES-03 path c).
  9. **Apply distribution:** `address recipient = currentSlate[bestSlot]; balanceOf[address(this)] -= distribution; balanceOf[recipient] += distribution; emit Transfer(address(this), recipient, distribution); emit LevelResolved(level, bestSlot, recipient, distribution);`

- **D-255-PICKCHARITY-ERROR-01 (`error PickCharityRejected(uint8 reason)`):** Mirrors `VoteRejected` reason-code pattern. Reasons:
  ```solidity
  uint8 private constant REJECT_LEVEL_NOT_ACTIVE       = 0;  // level != currentLevel
  uint8 private constant REJECT_LEVEL_ALREADY_RESOLVED = 1;  // levelResolved[level] == true
  ```
  - Could also reuse `VoteRejected` with shared reason codes, but the failure domains are distinct (vote vs. resolve) and shared codes would be confusing. Two separate errors with parallel shape is cleaner.

### Event Cleanup

- **D-255-EVENT-CLEANUP-01:** Delete `event ProposalCreated(...)` (orphaned in Phase 254; this is the CLEAN-02 deletion). Rewrite `event Voted` from v32 `Voted(uint24 indexed level, uint48 indexed proposalId, address indexed voter, bool approve, uint256 weight)` to v33 `Voted(uint24 indexed level, uint8 indexed slot, address indexed voter, uint256 weight)` (drop `bool approve` — approve-only voting; drop `proposalId` indexed arg → replace with `slot`). Rewrite `event LevelResolved` from v32 `LevelResolved(uint24 indexed level, uint48 indexed winningProposalId, address recipient, uint256 gnrusDistributed)` to v33 `LevelResolved(uint24 indexed level, uint8 indexed slot, address recipient, uint256 gnrusDistributed)` (replace `winningProposalId` with `slot`). Add `event CharityFlushed(uint8 indexed slot, address indexed recipient)` per D-255-FLUSH-EVENT-01.

### Reentrancy / CEI

- **D-255-CEI-01:** Both `vote` and `pickCharity` are CEI-clean by structure. `vote` does no external calls after state writes (`emit Voted` is just a log). `pickCharity` does the balance write + `emit Transfer` + `emit LevelResolved` — no external call into `recipient` (GNRUS is soulbound, so the recipient cannot withdraw via callback; they must explicitly `burn()` to redeem). No reentrancy guard needed.

### Claude's Discretion

- Storage-slot ordering of new `slotApproveWeight` mapping (immediately after `pendingEdit` to keep governance state co-located vs anywhere else — pick whichever the planner deems cleanest for the storage-layout diagram).
- Inline vs separate helper for the flush loop body (single inline for-loop in `pickCharity` is fine; could factor to `_flushPending()` private helper if it improves audit readability — planner's call).
- Reason-code constants: `private constant uint8` (chosen above) vs Solidity `enum VoteRejectReason` — uint8 constants are more gas-friendly and let tests pass raw integers; enum would force a casting layer. Sticking with uint8 constants unless planner finds a strong reason to switch.
- Whether `pickCharity` should also emit a `CharityFlushBatch(uint24 indexed level, uint8 count)` aggregate counter event in addition to per-edit `CharityFlushed` for indexer-side checksumming. Planner can add if the cost (~750 gas) is worth the indexer convenience; default = no aggregate.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 255 Anchors

- `.planning/REQUIREMENTS.md` §"v33.0 Requirements" → §"VOTE", §"RES", §"CLEAN" — 10 Phase 255 requirements (VOTE-01..04, RES-01..04, CLEAN-02, CLEAN-03) verbatim including locked event signatures + locked tie-break rule + locked LevelSkipped paths
- `.planning/ROADMAP.md` §"Phase 255" — 5 success criteria (lines 150-161); depends-on = Phase 254
- `.planning/PROJECT.md` §"Current Milestone: v33.0 Charity Allowlist Governance" — full design lock (vote weight purely sdgnrs balance, no bonus, no threshold; tie-break = lowest active slot index)

### Phase 254 Predecessor Artifacts (storage skeleton + helpers consumed here)

- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-01-SUMMARY.md` — storage layout diagram (post-Plan-01 v33.0 layout); confirms `currentSlate`, `pendingEdit`, `currentActiveBitmap`, `pendingEditSet`, redeclared `hasVoted` (uint8 inner key), `levelResolved`
- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-02-SUMMARY.md` — `setCharity` revert order; `_futureBitmapAfter` + `_popcount32` helpers; **deviation: `RecipientIsContract` removed** (informs Phase 256 test plan + Phase 257 audit; ROADMAP updated in this commit)
- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-03-SUMMARY.md` — `_flushedBitmap` private helper (Phase 255 `pickCharity` reuses for the atomic flush); 5 view helpers
- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-CONTEXT.md` — D-254-COUNT-01 (bitmap as single source of truth), D-254-PENDING-01 (sentinel semantics), D-254-EVENT-01 (CharityApplied/CharityQueued event style — D-255-FLUSH-EVENT-01 mirrors)
- `contracts/GNRUS.sol` (post-Phase-254 HEAD `469d7fc1`) — current state to delta against. `vote` and `pickCharity` are functionally absent

### Audit Baseline + Downstream Caller Inventory

- `audit/FINDINGS-v32.0.md` — closure attestation `MILESTONE_V32_AT_HEAD_acd88512`
- `contracts/modules/DegenerusGameAdvanceModule.sol:31-34` — `interface IGNRUSResolve { function pickCharity(uint24 level) external; }` declaration (signature pin)
- `contracts/modules/DegenerusGameAdvanceModule.sol:103-104` — `IGNRUSResolve private constant charityResolve = IGNRUSResolve(ContractAddresses.GNRUS);`
- `contracts/modules/DegenerusGameAdvanceModule.sol:1634` — `charityResolve.pickCharity(lvl - 1);` (Phase 255 must preserve external signature exactly)
- `contracts/modules/DegenerusGameGameOverModule.sol:145` — `charityGameOver.burnAtGameOver();` (UNAFFECTED — `burnAtGameOver` unchanged in Phase 255)

### Project-Wide Feedback Memory (governs commit/edit policy)

- `feedback_no_contract_commits.md` — every `contracts/GNRUS.sol` modification requires explicit per-commit user approval
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are "pre-approved"
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing code
- `feedback_manual_review_before_push.md` — never push contract changes without explicit user review of the diff first
- `feedback_no_history_in_comments.md` — comments describe what IS, never what changed (no rollback cruft, no "removed for v33.0" notes)
- `feedback_no_dead_guards.md` — remove unreachable safety caps; no orphaned reverts after error deletion
- `feedback_gas_worst_case.md` — gas analysis must derive theoretical worst case FIRST, then test it (Phase 256 owns the measurement; Phase 255 plan derives the theoretical numbers)

### Cross-Phase Context (v33.0 milestone)

- `.planning/REQUIREMENTS.md` §"TST" — Phase 256 will test the Phase 255 surface; D-255-VOTEREJECT-01 reason codes consumed by sad-path test assertions
- `.planning/REQUIREMENTS.md` §"AUDIT" → AUDIT-02-(a..i) — Phase 257 adversarial sweep; D-255-FLUSH-EVENT-01 + D-255-FLUSH-ORDER-01 + the active-count single-source-of-truth pattern (D-254-COUNT-01) pre-empt drift attack class

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 254)

- **`_flushedBitmap()` private view helper** (`contracts/GNRUS.sol`) — composes the would-be future bitmap from `currentActiveBitmap` ± all pending edits. `pickCharity` flush phase can EITHER call this (read-only composition) and then walk the result, OR perform the flush inline (mutating `currentSlate` + `currentActiveBitmap` + `pendingEdit` + `pendingEditSet` as it iterates). **Recommendation:** inline flush is cheaper (avoids the read-then-walk-twice pattern) and matches the "atomic apply" semantics in RES-01 better. `_flushedBitmap` stays useful for the `activeCountAfterFlush()` view.
- **`_popcount32(uint32) private pure`** — `pickCharity` skip-path A (`currentActiveBitmap == 0`) doesn't need popcount; the bitmap-zero check is a single comparison. `_popcount32` may not be needed at all in Phase 255 — that's fine (it's already consumed by the view helpers).
- **`vault.isVaultOwner(msg.sender)` admin pattern** (`setCharity` step 1) — NOT consumed by `vote()` (no admin gating on voting). Vault-owner check pattern stays where it is.
- **`onlyGame` modifier** (`contracts/GNRUS.sol`) — preserved from v32; `pickCharity` reuses verbatim.
- **`hasVoted` mapping** (Phase 254 redeclared with uint8 inner key) — `vote()` reads/writes `hasVoted[currentLevel][msg.sender][slot]`.
- **`currentSlate` private array** — `vote()` reads `currentSlate[slot]` for empty-slot check; `pickCharity` reads `currentSlate[bestSlot]` for distribution recipient.
- **`pendingEdit` private mapping + `pendingEditSet` bitmap** — `pickCharity` flush phase reads + clears.
- **`currentActiveBitmap`** — `pickCharity` flush phase updates synchronously with `currentSlate` writes; winner phase iterates set bits.
- **`levelResolved` mapping** — `pickCharity` idempotence guard.
- **Distribution math** (`(unallocated * DISTRIBUTION_BPS) / BPS_DENOM`) — preserved verbatim from v32 `pickCharity`.
- **`Transfer` event** — preserved verbatim; reused for the GNRUS distribution to `recipient`.

### Established Patterns

- **Bitmap as single source of truth (D-254-COUNT-01)** — `currentActiveBitmap` and `pendingEditSet` are authoritative. Phase 255 `pickCharity` flush mutates both synchronously with `currentSlate` writes; no separate counter to drift.
- **Hot-pack slot 2** — `currentLevel`, `finalized`, `currentActiveBitmap`, `pendingEditSet` all share one storage slot. `pickCharity` writes `currentLevel = level + 1` and `currentActiveBitmap` updates; both hit the warm slot after the first read.
- **CEI ordering** — state writes before external interactions (Phase 254 burn, Phase 255 distribution).
- **Per-error reason-code pattern (NEW in Phase 255)** — `VoteRejected(uint8 reason)` + `PickCharityRejected(uint8 reason)` introduce a new pattern for v33.0 governance errors. Phase 256 tests assert via `revertedWithCustomError(...).withArgs(N)`. Phase 257 audit should grep for the constants to confirm reason coverage.

### Integration Points

- **`contracts/GNRUS.sol` standalone** — Phase 255 modifies ONLY this file. No `ContractAddresses.sol` regen needed (no constant address layout change).
- **`DegenerusGameAdvanceModule:1634` caller** — currently broken at runtime between Phase 254 close and Phase 255 close. Phase 255 close restores it. Phase 256 integration tests must exercise the full game-advance → `pickCharity` chain (not just GNRUS in isolation).

</code_context>

<specifics>
## Specific Ideas

- **No vault-owner bonus weight code path anywhere in Phase 255 output** — VOTE-03 + Phase 257 AUDIT-02-(c) verification target. Vote weight = `sdgnrs.balanceOf(voter) / 1e18`, full stop.
- **Locked-slot vote behavior — no special-casing.** Voters CAN vote on locked slots normally (slots 0/1/2 are regular slate slots once filled, just immutable from the admin side). `vote()` only checks empty/already-voted/zero-weight. The locked-slot guard lives exclusively in `setCharity`.
- **Old-level `slotApproveWeight` entries persist in storage post-pickCharity** — deliberate; per `feedback_no_dead_guards.md`. Wiping 20 cold SSTOREs per level for no functional benefit is wasted gas. Indexers get free historical query as a side-benefit.
- **Reason-code constant naming convention:** `REJECT_<UPPER_SNAKE_CASE_REASON>` for vote rejections; constants live alongside the error declaration in the ERRORS section.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 256 — Hardhat test coverage** for the full v33.0 surface (setCharity branches, vote weighting + sad paths, pickCharity winner selection + tie-break + 3 LevelSkipped paths, conservation across level transition, post-gameover inertness, gas measurement against theoretical worst-case ceilings from Phase 254 + 255 SUMMARYs).
- **Phase 257 — Adversarial audit + `audit/FINDINGS-v33.0.md`** including AUDIT-02-(a..i) sweep. Phase 255 plan output (revert orders, gas tables, reason-code constants) feeds Phase 257 delta extraction.
- **Aggregate `CharityFlushBatch` event** — Claude's Discretion item; planner may add for indexer-side checksum if cost is justified.
- **Old-level `slotApproveWeight` cleanup** — deliberate non-cleanup per gas. If a future v34.0+ change wants to wipe these for storage-rent-style economics, that's its own phase.
- **`InsufficientStake` repurposing** — REQUIREMENTS.md CLEAN-03 hint is now stale (Phase 254 deleted that error; Phase 255 doesn't repurpose). REQUIREMENTS.md CLEAN-03 wording could be cleaned up at v33.0 milestone close (when REQUIREMENTS.md gets archived as `v33.0-REQUIREMENTS.md`); not blocking.

</deferred>

---

*Phase: 255-vote-rewrite-resolve-flush-event-error-cleanup*
*Context gathered: 2026-05-06*
