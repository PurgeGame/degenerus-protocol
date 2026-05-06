# Phase 254: GNRUS Allowlist Storage, Admin Op & Storage Repack — Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

`GNRUS.sol` (`contracts/GNRUS.sol`) is rewritten to expose a single vault-owner-gated `setCharity(uint8 slot, address recipient)` admin entry point backed by a 20-slot current slate + sparse pending edit queue. All dead proposal-flow state, errors, events, AND the v32-shape `propose()` / `vote()` / `pickCharity()` / `getProposal()` / `getLevelProposals()` functions are functionally removed (per `feedback_no_history_in_comments.md` — no commenting-out, no rollback cruft). Storage is repacked for tightest layout post-removal. Contract MUST compile cleanly at Phase 254 close with `setCharity` + view helpers + `burn` + `burnAtGameOver` + soulbound stubs as the only functional surface; governance is intentionally non-functional between Phase 254 close and Phase 255 open (acceptable — protocol is pre-launch, Phase 256 tests run end-of-milestone).

Five requirements (ALW-01..04 + CLEAN-01 per REQUIREMENTS.md):

- **ALW-01** — Storage for current charity slate (≤20 active slots, address-only, uint8 slot index, packing rationale + per-slot read gas documented).
- **ALW-02** — Storage for pending edit queue with sentinel distinguishing "no pending" from "pending remove (recipient=0)".
- **ALW-03** — `setCharity(uint8 slot, address recipient)` single admin entry point (vault-owner-gated; covers add/replace/remove via `recipient == address(0)` semantics; locked-slot guard fires before queue/instant-apply branching; cap enforced on post-flush active count via either branch; emits indexer-compatible events distinguishing instant-apply vs queued).
- **ALW-04** — View helpers: `getCharity(uint8) returns (address)`, `getActiveSlots() returns (uint8[], address[])` (paired-array variant per D-254-VIEW-01 below), `getPendingEdits() returns (uint8[], address[])`, `activeCount() returns (uint8)` (current slate only), `activeCountAfterFlush() returns (uint8)` (current ± pending).
- **CLEAN-01** — Functional removal of `Proposal` struct, `proposals`, `proposalCount`, `levelProposalStart`, `levelProposalCount`, `hasProposed`, `creatorProposalCount`, `levelVaultOwner`, `levelSdgnrsSnapshot`. Re-pack remaining state for tightest layout post-removal; document new layout vs v32.0 baseline `acd88512`. `hasVoted` mapping ALSO redeclared in this phase from `(uint24 => address => uint48 => bool)` to `(uint24 => address => uint8 => bool)` per D-254-HASVOTED-01 (single coherent storage layout from Phase 254 onward).

**Audit baseline:** v32.0 HEAD `acd88512` (closure signal `MILESTONE_V32_AT_HEAD_acd88512`). Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_wait_for_approval.md` + `feedback_manual_review_before_push.md`: every `contracts/GNRUS.sol` modification requires explicit per-commit user approval. `contracts/ContractAddresses.sol` is modifiable per `feedback_contractaddresses_policy.md` if regen is needed (likely not — selector-set changes are internal to GNRUS).

**Phase 254 boundary state:**
- v32-shape `propose()` / `vote()` / `pickCharity()` / `getProposal()` / `getLevelProposals()` ALL deleted (per D-254-VOTEPICK-01).
- Functional surface remaining: `setCharity` + view helpers (`getCharity`, `getActiveSlots`, `getPendingEdits`, `activeCount`, `activeCountAfterFlush`) + `burn` + `burnAtGameOver` + soulbound stubs (`transfer` / `transferFrom` / `approve` revert `TransferDisabled`) + `receive() payable`.
- Downstream caller `charityResolve.pickCharity(lvl-1)` at `contracts/modules/DegenerusGameAdvanceModule.sol:1634` will revert (selector mismatch) if exercised between Phase 254 close and Phase 255 open. Non-blocking — Phase 256 tests run end-of-milestone after Phase 255 re-adds `pickCharity` in new shape.
- `charityGameOver.burnAtGameOver()` at `contracts/modules/DegenerusGameGameOverModule.sol:145` remains functional (`burnAtGameOver` unchanged in Phase 254).

</domain>

<decisions>
## Implementation Decisions

### Storage Shape (Current Slate)

- **D-254-SLATE-01 (`address[20] private currentSlate`):** Statically-allocated 20-slot fixed array. Each address occupies its own storage slot (one full 32-byte slot per slot index — 20 storage slots total for a fully-populated slate). Read by index = single SLOAD. Exposed via `getCharity(uint8 slot) returns (address)` per ALW-04 (auto-generated array getter would take `uint256` not `uint8` and would clash with the named view — keep array `private`). Plain array chosen over `mapping(uint8 => address) + uint32 activeBitmap` for: (a) deterministic gas profile (no hidden bitmap drift), (b) Phase 255 `vote(uint8 slot)` needs cheap empty-slot check via `currentSlate[slot] == address(0)` — single SLOAD with array, (c) `pickCharity` slot-iteration over 0..19 is natural fit, (d) cap-accounting bitmap (`currentActiveBitmap`) lives separately in the hot-pack slot per D-254-REPACK-01 — storage choice for the slate doesn't conflate with cap-accounting bookkeeping.

### Pending Queue Layout

- **D-254-PENDING-01 (`mapping(uint8 => address) private pendingEdit` + `uint32 pendingEditSet` bitmap):** Sparse mapping for the recipient values + 32-bit bitmap (one bit per slot index 0..19; bits 20..31 always zero) tracking which slots have a pending edit. Bitmap solves the sentinel problem cleanly: bit set + mapping value zero = pending-remove (queued slot will be cleared at flush); bit set + mapping value non-zero = pending-replace; bit clear = no pending edit (mapping value undefined/zero, never read). Cheap for sparse 0–1-edits-per-level common case (one mapping SSTORE + one OR-bit update on `pendingEditSet`). Pending overwrite for the same slot replaces the mapping value (bitmap unchanged — bit already set). Flush iterates set bits via bitmap, applies each to current slate, clears the bitmap with one SSTORE (`pendingEditSet = 0`). Symmetric-shape rejected (`address[20] pendingSlate`) because each pending entry would cost cold-write 22.1k gas on a previously-zero array slot — same per-edit cost in the common case but persistent storage state across levels. Packed `bytes32[]` diff list rejected because dynamic-array push is more expensive than mapping write for the 0–1-edit common case AND requires linear scan for pending-overwrite.

### setCharity Event Shape

- **D-254-EVENT-01 (two events `CharityApplied` + `CharityQueued`):** Phase 254 emits two distinct events from `setCharity`:
  - `event CharityApplied(uint8 indexed slot, address indexed recipient)` — fires on instant-apply branch (`currentSlate[slot] == address(0)` at entry, post-locked-slot guard). `recipient` cannot be `address(0)` here because the removal special case (`recipient == 0 && currentSlate[slot] == 0 && !pendingEditSet[slot]`) reverts `SlotAlreadyEmpty` first.
  - `event CharityQueued(uint8 indexed slot, address indexed recipient)` — fires on queue branch (`currentSlate[slot] != address(0)` at entry, post-locked-slot guard — therefore only unlocked slots 3..19 reach this branch). `recipient == address(0)` here means "queued remove" — pending overwrite of any prior pending entry for the slot is implicit in the new event.
  - Two distinct topic[0] hashes — indexers can subscribe selectively (admin-action stream vs queued-state stream). Aligns with Phase 255 `RES-01` flush event (one event per applied flush per RES-01) — gives indexers a clean three-event lifecycle: `CharityQueued` → flush event → applied to current slate.
  - One-event-with-`applied: bool` rejected for indexer ergonomics (forces every consumer to filter in-handler).

### Active-Count Accounting + Storage Repack Target

- **D-254-COUNT-01 (derive activeCount from bitmap popcount):** No standalone `currentActiveCount` / `activeCountAfterFlush` counters. Maintain `uint32 currentActiveBitmap` (bit per slot 0..19; bit set ⇔ `currentSlate[slot] != address(0)`) updated synchronously with every write to `currentSlate` (instant-apply branch sets bit; flush of pending-remove clears bit — Phase 255 territory but the bitmap is structurally maintained from Phase 254 onward). Two view helpers:
  - `activeCount() returns (uint8)` — `popcount(currentActiveBitmap)` (Solidity inline assembly or library helper; popcount of a 32-bit value is small and constant-gas).
  - `activeCountAfterFlush() returns (uint8)` — popcount of the future bitmap = `currentActiveBitmap` modified by pending edits: for each set bit in `pendingEditSet`, if `pendingEdit[slot] == 0` clear the corresponding bit, else set the bit. Returns popcount of the resulting uint32. Single source of truth (the two bitmaps), no drift risk possible by construction.
  - Cap check at `setCharity` entry computes the would-be future bitmap based on the branch + recipient nullity, popcounts, compares to `MAX_ACTIVE_SLOTS = 20`. `CapExceeded` fires deterministically without separate counter bookkeeping.
- **D-254-REPACK-01 (single hot-pack slot):** Post-CLEAN-01 storage repack target. Combine into ONE storage slot (12 bytes total, 20 bytes free for future fields):
  - `uint24 currentLevel` (3 bytes)
  - `bool finalized` (1 byte)
  - `uint32 currentActiveBitmap` (4 bytes)
  - `uint32 pendingEditSet` (4 bytes)
  - All four are hot fields touched by `setCharity` / view helpers. One cold SLOAD warms the whole pack for the rest of the call. Plan-phase produces a before/after storage-layout diagram (v32.0 baseline `acd88512` vs v33.0 post-CLEAN-01) and locks the canonical layout in `254-01-PLAN.md` per ALW-01 documentation requirement.

### hasVoted Refactor Timing

- **D-254-HASVOTED-01 (redeclare in Phase 254 with new uint8 slot key):** Phase 254 deletes the v32-shape `mapping(uint24 => mapping(address => mapping(uint48 => bool))) hasVoted` AND immediately redeclares it as `mapping(uint24 => mapping(address => mapping(uint8 => bool))) hasVoted`. Storage slot moved as part of the CLEAN-01 repack pass — one coherent layout from Phase 254 onward, no second repack in Phase 255. `hasVoted` is unread between Phase 254 close and Phase 255 open (no `vote()` to consume it), but the storage definition is stable. Phase 255 `vote()` simply reads `hasVoted[currentLevel][msg.sender][slot]` per VOTE-01 — no further storage churn.

### vote() / pickCharity() Phase Boundary

- **D-254-VOTEPICK-01 (Phase 254 deletes vote() + pickCharity() + getProposal() + getLevelProposals() entirely; Phase 255 re-adds them in new shape):** Required for compile after `Proposal` struct + `proposals` mapping deletion (CLEAN-01) — current `vote()` references `proposals[proposalId]` and `pickCharity()` references `proposals[bestId].recipient`. Phase 254 deletes:
  - `function propose(address recipient) external returns (uint48)` — required by Phase 254 success criterion 1 ("structurally absent")
  - `function vote(uint48 proposalId, bool approveVote) external` — required to compile post-`Proposal`-deletion
  - `function pickCharity(uint24 level) external onlyGame` — required to compile post-`proposals`-mapping-deletion
  - `function getProposal(uint48) external view returns (...)` — references deleted `Proposal` struct
  - `function getLevelProposals(uint24) external view returns (uint48, uint8)` — references deleted `levelProposalStart` / `levelProposalCount` mappings
  - Phase 255 (VOTE-01..04 + RES-01..04) re-adds `vote(uint8 slot)` and `pickCharity(uint24 level)` from scratch with new signatures + slot-based hasVoted lookup + flush-then-iterate logic. Cleanest separation; matches the "Phase 254 = storage + admin op only" framing. Stub-with-revert variant rejected per `feedback_no_dead_guards.md`.

### Error Pruning Boundary

- **D-254-ERROR-PRUNE-01 (Phase 254 deletes propose+vote+pickCharity-exclusive errors; adds 4 new):** As a mechanical consequence of D-254-VOTEPICK-01, Phase 254 deletes ALL errors that were referenced ONLY by the deleted `propose()` / `vote()` / `pickCharity()` / `getProposal()` / `getLevelProposals()`:
  - `ProposalLimitReached` — propose() vault-owner cap (deleted)
  - `AlreadyProposed` — propose() community once-per-level (deleted)
  - `InsufficientStake` — propose() 0.5% threshold + vote() zero-weight (both deleted)
  - `AlreadyVoted` — vote() double-vote (deleted)
  - `InvalidProposal` — vote() proposalId range check (deleted)
  - `LevelAlreadyResolved` — pickCharity() idempotence guard (deleted)
  - `LevelNotActive` — pickCharity() level argument check (deleted)
  - **Kept in Phase 254** (still wired): `Unauthorized` (modifier + setCharity gating), `TransferDisabled` (soulbound stubs), `ZeroAddress` (still used by `_mint` internal), `TransferFailed` (burn external transfers), `InsufficientBurn` (burn min check), `RecipientIsContract` (setCharity contract-recipient check + retained for Phase 255 use), `GameNotOver` / `AlreadyFinalized` (burnAtGameOver guards).
  - **Added in Phase 254** (per ALW-03 + REQUIREMENTS.md CLEAN-03): `InvalidSlot` (`slot >= 20`), `SlotAlreadyEmpty` (admin no-op remove), `SlotLocked` (locked-slot 0/1/2 mutation attempt), `CapExceeded` (post-flush count > 20).
  - Phase 255 will re-add whatever errors `vote()` / `pickCharity()` need from scratch (per CLEAN-03). Phase 254 emits zero orphaned reverts at close per `feedback_no_dead_guards.md`.

### View Helper Return Shape

- **D-254-VIEW-01 (paired arrays for getActiveSlots and getPendingEdits):** Both views return `(uint8[] memory slots, address[] memory recipients)` paired arrays:
  - `getActiveSlots() returns (uint8[] memory slots, address[] memory recipients)` — length = `popcount(currentActiveBitmap)`. For each set bit in `currentActiveBitmap`, push `(slotIndex, currentSlate[slotIndex])`. Consumer gets full active-slate snapshot in one call.
  - `getPendingEdits() returns (uint8[] memory slots, address[] memory recipients)` — length = `popcount(pendingEditSet)`. For each set bit in `pendingEditSet`, push `(slotIndex, pendingEdit[slotIndex])` — the recipient value can be `address(0)` here (= queued remove). Consumer reconstructs full pending-edits set in one call.
  - Memory-only allocation; gas scales with active count (bounded by 20). Bitmap-iteration over 0..19 is constant-bounded. Ergonomic for indexers and frontends — no per-slot round-trip via `getCharity(slot)`.
  - Sparse-`uint8[]`-only-and-call-`getCharity`-per-slot variant rejected for round-trip cost. Raw-bitmap-exposure variant rejected as it conflicts with ALW-04 wording "(or equivalent enumerator)" — paired arrays ARE the enumerator.

### Constants

- **D-254-CONST-01:** Add `uint8 private constant LOCKED_SLOTS = 3` (slots 0/1/2 immutable once filled; per REQUIREMENTS.md). Add `uint8 private constant MAX_ACTIVE_SLOTS = 20` (cap; explicit constant rather than magic number for `CapExceeded` check + view helpers). Remove `uint16 private constant PROPOSE_THRESHOLD_BPS = 50` (orphaned with propose() deletion). Remove `uint16 private constant VAULT_VOTE_BPS = 500` (orphaned with vault-owner bonus removal in v33.0 design). Remove `uint8 private constant MAX_CREATOR_PROPOSALS = 5` (orphaned with propose() deletion). Keep `INITIAL_SUPPLY`, `MIN_BURN`, `DISTRIBUTION_BPS`, `BPS_DENOM` (still used by burn / future Phase 255 pickCharity).

### Constructor

- **D-254-CTOR-01:** Constructor unchanged — only mints `INITIAL_SUPPLY` to `address(this)`. Slate is empty at deploy per PROJECT.md ("Empty at deploy; vault owner populates after deploy") — `address[20] currentSlate` auto-zeros, `currentActiveBitmap = 0`, `pendingEditSet = 0`. No seeding logic in Phase 254. Locked-slot first-fill happens via post-deploy `setCharity` calls by the vault owner (operational seeding-window note flagged for FINDINGS-v33.0.md per Phase 257 AUDIT-02-(g) "locked-slot poisoning during seeding window — disclosed as trust-asymmetry note, operational mitigation").

### Claude's Discretion

- Choice of popcount implementation (inline assembly Hamming-weight algorithm, or library helper) for `activeCount` / `activeCountAfterFlush` view helpers — plan-phase or executor picks based on gas benchmark (uint32 popcount is small and constant; both options viable).
- Exact internal helper-function decomposition of `setCharity` (single monolithic function vs `_applyInstant` / `_queueEdit` / `_lockedSlotGuard` private helpers) — code-clarity call, no behavioral impact.
- Whether to declare `setCharity` as `external` or `external returns (bool applied)` (return value lets callers branch on instant-apply vs queued without re-reading state) — minor ergonomic call; default to no return value (events carry the signal).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone-Level Locks

- `.planning/PROJECT.md` §"Current Milestone: v33.0 Charity Allowlist Governance" — full design lock (admin entry, locked slots, two-branch semantics, cleanup scope, packing delegation to plan-phase, write policy)
- `.planning/REQUIREMENTS.md` §"v33.0 Requirements" → §"ALW", §"CLEAN" — five Phase 254 requirement specifications (ALW-01..04 + CLEAN-01) verbatim including revert-order, locked-slot semantics, instant-apply rule, queue rule, removal special case, cap enforcement
- `.planning/ROADMAP.md` §"Phase 254" — five success criteria; depends-on = nothing (first impl phase); write policy = `feedback_no_contract_commits.md` per-commit approval

### Audit Baseline + Audit-Anchor State

- `contracts/GNRUS.sol` (v32.0 HEAD `acd88512` working tree) — pre-Phase-254 state to delta against. Phase 254 plan/executor reads at this anchor for diff/repack computations
- `audit/FINDINGS-v32.0.md` — closure attestation `MILESTONE_V32_AT_HEAD_acd88512` (v32.0 baseline carries forward — Phase 254 is first commit above this anchor)

### Downstream Caller Inventory (for Phase 254 deletion-impact awareness)

- `contracts/modules/DegenerusGameAdvanceModule.sol:31-34` — `interface IGNRUSResolve { function pickCharity(uint24 level) external; }` declaration
- `contracts/modules/DegenerusGameAdvanceModule.sol:103-104` — `IGNRUSResolve private constant charityResolve = IGNRUSResolve(ContractAddresses.GNRUS);`
- `contracts/modules/DegenerusGameAdvanceModule.sol:1634` — `charityResolve.pickCharity(lvl - 1);` (will revert post-Phase-254-close until Phase 255 re-adds `pickCharity`; non-blocking — Phase 256 tests run end-of-milestone)
- `contracts/modules/DegenerusGameGameOverModule.sol:27-29` — `interface IGNRUSGameOver { function burnAtGameOver() external; }` declaration
- `contracts/modules/DegenerusGameGameOverModule.sol:145` — `charityGameOver.burnAtGameOver();` (UNAFFECTED — `burnAtGameOver` unchanged in Phase 254)
- `contracts/DegenerusStonk.sol:301, 322, 329` — refer to `ContractAddresses.GNRUS` for sweep-to-charity (UNAFFECTED — sweep is via raw `transfer` / `call`, not GNRUS function calls)

### Existing Test Surface (for Phase 256 awareness, NOT modified in Phase 254)

- `test/unit/DegenerusCharity.test.js` (992 lines) — v32-shape unit tests; will be obsoleted by v33-shape tests landed in Phase 256. Do NOT modify in Phase 254.
- `test/integration/CharityGameHooks.test.js` (252 lines) — v32-shape integration tests; same status.
- `test/access/AccessControl.test.js` — references vault-owner gating; partially affected. Phase 256 will reconcile.

### Project-Wide Feedback Memory (governs commit/edit policy)

- `feedback_no_contract_commits.md` — every `contracts/GNRUS.sol` modification requires explicit per-commit user approval; orchestrator NEVER pre-approves
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are "pre-approved"
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing code
- `feedback_manual_review_before_push.md` — never push contract changes without explicit user review of the diff first
- `feedback_no_history_in_comments.md` — comments describe what IS, never what changed or what it used to be (no rollback cruft, no "removed for v33.0" notes)
- `feedback_no_dead_guards.md` — remove unreachable safety caps; don't waste gas on dead branches; no orphaned reverts after error deletion
- `feedback_contractaddresses_policy.md` — `ContractAddresses.sol` is modifiable without per-commit approval; every other `contracts/*.sol` requires approval
- `feedback_gas_worst_case.md` — gas analysis must derive theoretical worst case FIRST, then test it (applies to popcount + flush + cap-check gas justifications in plan)

### Cross-Phase Context (v33.0 milestone)

- `.planning/REQUIREMENTS.md` §"VOTE", §"RES", §"CLEAN-02..03" — Phase 255 scope; Phase 254's `hasVoted` redeclaration + repack target + bitmap shape consumed by Phase 255
- `.planning/REQUIREMENTS.md` §"TST" — Phase 256 will test the Phase 254 surface; ALW-04 view shape (paired arrays) consumed by test assertions
- `.planning/REQUIREMENTS.md` §"AUDIT" → AUDIT-02-(e), AUDIT-02-(f), AUDIT-02-(g), AUDIT-02-(h) — Phase 257 adversarial sweep on instant-apply branch abuse, active-count accounting drift, locked-slot poisoning, locked-slot lock-bypass; Phase 254 plan output should pre-emptively lay groundwork for these proofs (e.g., active-count single-source-of-truth via bitmap kills (f) drift attack class structurally)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`vault.isVaultOwner(msg.sender)` admin check pattern** (`contracts/GNRUS.sol:236-237` + `IDegenerusVaultOwner` interface) — already wired; reuse verbatim for `setCharity` gating. No new interface plumbing.
- **`recipient.code.length != 0` EOA check pattern** (`contracts/GNRUS.sol:366` in v32 propose) — copy verbatim into `setCharity` for the `recipient != 0` non-zero-recipient branch.
- **`Unauthorized` error** (`contracts/GNRUS.sol:55`) — reuse for vault-owner gating revert; no new error needed.
- **`RecipientIsContract` error** (`contracts/GNRUS.sol:91`) — reuse for contract-recipient check.
- **`onlyGame` modifier pattern** (`contracts/GNRUS.sol:244-247`) — kept; pickCharity (Phase 255) will reuse.
- **Storage-pack documentation pattern** (`contracts/GNRUS.sol:153-157` Proposal struct comments + `:169` slot pack comment) — copy stylistic pattern for the new hot-pack slot doc per D-254-REPACK-01.

### Established Patterns

- **Soulbound stub pattern** (`contracts/GNRUS.sol:263-269`) — UNCHANGED in Phase 254; transfer/transferFrom/approve all `revert TransferDisabled()`.
- **Underflow-safe burn arithmetic** (`contracts/GNRUS.sol:282-329`) — UNCHANGED in Phase 254.
- **Constant-naming convention** (`UPPER_SNAKE` for protocol constants) — apply to new `LOCKED_SLOTS = 3`, `MAX_ACTIVE_SLOTS = 20`.
- **Single-source-of-truth invariant via bitmap** — D-254-COUNT-01 establishes this for active-count; consistent with the project's gas-conscious + drift-resistant design philosophy (e.g., `feedback_gas_worst_case.md`).

### Integration Points

- **`contracts/GNRUS.sol` standalone** — Phase 254 modifies ONLY this file (and possibly nothing else). `ContractAddresses.sol` likely needs no regen — selector set changes are internal to GNRUS; no constant address layout change.
- **No interface ripples** — Phase 254 deletes `propose` / `vote` / `pickCharity` / `getProposal` / `getLevelProposals` from GNRUS, but the only inter-contract interface in active use is `IGNRUSResolve.pickCharity` (DegenerusGameAdvanceModule) and `IGNRUSGameOver.burnAtGameOver` (DegenerusGameGameOverModule). The IGNRUSResolve interface is interface-side declaration and won't fail compile when GNRUS.pickCharity disappears — call site at AdvanceModule:1634 will revert at runtime if reached pre-Phase-255 (acceptable per D-254-VOTEPICK-01).

</code_context>

<specifics>
## Specific Ideas

- **Bitmap popcount inline-assembly preference:** prefer Hamming-weight inline assembly (constant-gas, ~30 gas for uint32) over a library import — the project leans on inline-asm gas-tightness elsewhere. Plan-phase confirms with bench.
- **Hot-pack slot ordering:** keep `currentLevel` first in the pack (matches v32 layout where it's first in slot 2) for diff-visibility in storage-layout audit. Then `finalized`, then the two bitmaps. Plan-phase produces the explicit before/after diagram.
- **`setCharity` parameter order:** `(uint8 slot, address recipient)` per REQUIREMENTS.md verbatim — slot first, recipient second; `address(0)` recipient = remove signal.
- **Locked-slot guard revert message:** `SlotLocked` (per REQUIREMENTS.md CLEAN-03) — fires before queue/instant-apply branching; applies regardless of whether a pending edit would have existed for the slot.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 255** — `vote(uint8 slot)` rewrite (slot-based, no bonus weight, no propose threshold), `pickCharity(uint24 level)` flush-then-iterate rewrite (atomic apply pending → current at entry, slot 0→19 strict-`>` winner loop, lowest-slot tie-break, three LevelSkipped paths preserved), `Voted` + `LevelResolved` event signature rewrite, CLEAN-02/03 (remove `ProposalCreated` event + add vote/resolve errors as needed). Phase 254's `hasVoted` redeclaration (D-254-HASVOTED-01) + repack target (D-254-REPACK-01) + bitmap shape (D-254-COUNT-01) are pre-positioned for Phase 255 consumption.
- **Phase 256** — Hardhat test coverage for setCharity branches (instant-apply / queue / overwrite / locked-slot / sad-paths / cap), edit-queue level-boundary semantics, vote weighting + multi-slot + double-vote + empty-slot + zero-weight, pickCharity winner selection + tie-break + three LevelSkipped paths, conservation across level transition, post-gameover inertness. Phase 254 does NOT add tests (per D-254-VOTEPICK-01 + Phase 256 ownership).
- **Phase 257** — Delta audit + `audit/FINDINGS-v33.0.md` consolidation. Phase 254 plan-phase output (storage-layout diagram, packing rationale, gas table) feeds Phase 257 AUDIT-01 delta extraction + AUDIT-02-(e/f/g/h) adversarial proofs (instant-apply branch abuse, active-count accounting drift kill via bitmap, locked-slot poisoning trust-asymmetry note, locked-slot lock-bypass verification).
- **`setCharity` return value (`bool applied`)** — Claude discretion item from D-254 decisions; default to no return value, plan-phase or executor can choose to add if call-site ergonomics favor it.
- **v34.0+** — Audit of post-v32.0 commits (`002bde55` presale auto-deactivate, `2713ce61` setDecimatorAutoRebuy removal). Out of scope for v33.0 per PROJECT.md.

</deferred>

---

*Phase: 254-gnrus-allowlist-storage-admin-op-storage-repack*
*Context gathered: 2026-05-05*
