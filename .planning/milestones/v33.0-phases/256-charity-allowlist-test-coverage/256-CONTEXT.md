# Phase 256: Charity Allowlist Test Coverage — Context

**Gathered:** 2026-05-06
**Status:** Ready for planning

<domain>
## Phase Boundary

A new Hardhat test surface that exercises every behaviorally observable v33.0 charity-allowlist surface landed in Phases 254 + 255, plus the conservation invariants and post-gameover GNRUS-side state that Phase 257 will audit. All tests pass against the post-Phase-255 contract HEAD with the v33.0 storage skeleton + `setCharity` + `vote(uint8 slot)` + `pickCharity(uint24 level)` + `_flushedBitmap` / `_popcount32` helpers + view helpers in place.

Six requirements (TST-01..06 per REQUIREMENTS.md):

- **TST-01** — Hardhat unit tests for `setCharity` covering both branches (instant-apply when `currentSlate[slot] == address(0)`; queue when filled), all sad paths (vault-owner gating, `InvalidSlot`, `SlotAlreadyEmpty`, `SlotLocked`, `CapExceeded`), and pending-overwrite (queue A then B → only B applies on flush).
- **TST-02** — Edit-queue level-boundary semantics (instant-apply slot votable in same level; queued replace / remove keep OLD address votable until flush; after `pickCharity` advances level, queued edits visible in current slate, dead pending entries cleared).
- **TST-03** — `vote(uint8 slot)` weighting + sad paths: single-slot full-weight, multi-slot full-weight independently, double-vote `VoteRejected(REJECT_ALREADY_VOTED)`, empty-slot `VoteRejected(REJECT_EMPTY_SLOT)`, zero-weight `VoteRejected(REJECT_ZERO_WEIGHT)`, slot-bounds `InvalidSlot`.
- **TST-04** — `pickCharity` winner selection: single-active-slot wins; multi-vote highest-weight wins; tie → lowest slot index wins (concrete weights wired); three `LevelSkipped` paths (zero active slots / zero votes / 2%-rounds-to-zero).
- **TST-05** — Conservation across the level transition: total ETH/stETH/GNRUS balance changes match expected 2% distribution; sDGNRS / DGNRS / BURNIE supplies unchanged; soulbound enforcement (`transfer` / `transferFrom` / `approve` revert `TransferDisabled`) intact.
- **TST-06** — Post-gameover inertness: GNRUS-side consistency after `burnAtGameOver` (single smoke test — see D-256-POSTGAMEOVER-01).

**Audit baseline:** v33.0 HEAD post-Phase-255 (latest tip after `feat(255-03): implement pickCharity(uint24 level) external onlyGame`). Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md` + `feedback_wait_for_approval.md` + `feedback_manual_review_before_push.md`: every `test/governance/`, `test/unit/DegenerusCharity.test.js`, `test/integration/CharityGameHooks.test.js`, and `test/helpers/charityFixture.js` modification requires explicit per-commit user approval (test/ files are under the same write-policy umbrella as contracts/).

**Phase 256 boundary state at close:**
- `test/governance/CharityAllowlist.test.js` (NEW) — full v33.0 governance surface coverage (setCharity / vote / pickCharity / cap / sad paths / queued-cancel / multi-slot vote / tie-break / 3 LevelSkipped paths).
- `test/unit/DegenerusCharity.test.js` — pruned to retain Token Metadata + Soulbound + Burn Redemption + `burnAtGameOver` + `receive` + Edge Cases describes only. The 3 stale v32-shape Governance describes (`Governance -- Propose`, `Governance -- Vote`, `Governance -- pickCharity`) are deleted entirely (not stubbed, not commented — per `feedback_no_history_in_comments.md`). The stale top-level constants `PROPOSE_THRESHOLD_BPS`, `VAULT_VOTE_BPS`, `MAX_CREATOR_PROPOSALS` are deleted; the `proposalCount` assertion in `Token Metadata` is replaced or deleted.
- `test/integration/CharityGameHooks.test.js` — extended with the conservation + level-transition full-game-advance test cases (TST-05). The stale `LevelSkipped(0) when no proposals exist` describe is rewritten in v33.0 shape (`LevelSkipped(0) when no active slots`).
- `test/helpers/charityFixture.js` (NEW) — factored helper: `impersonate` / `stopImpersonating` / `giveSDGNRS` / `deployGNRUSFixture` (the v33.0 charity-specific subset of the existing `deployFullProtocol` flow), reused across the new governance file + the trimmed unit file + the integration extension.

</domain>

<decisions>
## Implementation Decisions

### Test-File Layout

- **D-256-LAYOUT-01 (new `test/governance/CharityAllowlist.test.js` + prune existing unit file):**
  - **Create** `test/governance/CharityAllowlist.test.js` to own ALL v33.0 governance surface — `setCharity` (both branches + every sad path + queued-cancel + cap), `vote(uint8 slot)` (weighting + 4 reject paths), `pickCharity` (winner selection + tie-break + 3 LevelSkipped paths + idempotence + level-arg checks), edit-queue level-boundary semantics, contract-recipient acceptance, multi-slot vote independence, and ONE TST-06 GNRUS-side smoke (per D-256-POSTGAMEOVER-01).
  - **Prune** `test/unit/DegenerusCharity.test.js` (currently 992 lines / 78 it-blocks) by deleting the three stale v32-shape Governance describes (`Governance -- Propose`, `Governance -- Vote`, `Governance -- pickCharity`) entirely. Keep `Token Metadata` (drop the `proposalCount` assertion — v33 has no proposalCount), `Soulbound Enforcement`, `Burn Redemption`, `burnAtGameOver`, `receive() -- ETH acceptance`, `Edge Cases`. Delete the unused module-level constants `PROPOSE_THRESHOLD_BPS`, `VAULT_VOTE_BPS`, `MAX_CREATOR_PROPOSALS`.
  - Matches ROADMAP wording: "A new Hardhat test surface under `test/governance/` (or similar)".
  - **Rejected — rewrite-in-place:** Single 1500+ line file mixing token-shape + governance — file size unwieldy, ownership unclear at audit time. Separation by concern is cleaner.
  - **Rejected — keep stale describes commented out:** Violates `feedback_no_history_in_comments.md` (no rollback cruft, no "removed for v33.0" notes). Deletion is the correct shape.

### Conservation Test Driver (TST-05)

- **D-256-CONSERVATION-01 (full game-advance integration in `test/integration/CharityGameHooks.test.js`):**
  - Drive the conservation test cases via the **real game flow** — exercise `DegenerusGameAdvanceModule:1634`'s `charityResolve.pickCharity(lvl - 1)` call from a real level-advance event (jackpot / VRF / mint plumbing as required by the existing integration fixture). NOT impersonate-and-call.
  - Add to existing `test/integration/CharityGameHooks.test.js` (252 lines) — extends the established `pickCharity fires at level transition` describe block with v33.0-shape assertions:
    - `LevelResolved(level, slot, recipient, distribution)` event fired with correct `slot` index + `recipient` from `currentSlate[bestSlot]`.
    - `recipient` GNRUS balance increased by the expected 2% distribution.
    - GNRUS `totalSupply` unchanged across the transition (no burn).
    - sDGNRS `totalSupply` + `votingSupply` unchanged across the transition.
    - DGNRS `totalSupply` unchanged.
    - BURNIE total-supply / per-pool accounting unchanged.
    - Soulbound enforcement still intact: `transfer` / `transferFrom` / `approve` on `gnrus` revert `TransferDisabled` (smoke-check after the level transition).
  - Rewrite the stale `LevelSkipped(0) when no proposals exist for level 0` it-block to `LevelSkipped(0) when no active slots in slate` (v33.0 shape — slate-empty, not proposal-empty).
  - **Why integration over impersonation:** Phase 257 AUDIT-03 conservation re-proof grep-cites integration-side coverage as evidence. Impersonate-and-call would be invisible to the game-side wire (`IGNRUSResolve` interface at `DegenerusGameAdvanceModule.sol:31-34`); only the integration-driven path proves the wire is alive at HEAD.
  - **Rejected — impersonate-and-call:** Faster, but bypasses the `IGNRUSResolve` wire. Phase 257 audit would have to re-derive that the wire works.
  - **Rejected — both:** Overkill. Integration alone gives the audit-grade evidence; the unit governance file already covers fine-grained `pickCharity` mechanics via direct calls (see D-256-POSTGAMEOVER-01 for the unit-side `pickCharity` driver pattern).

  **Unit-side `pickCharity` driver pattern in `test/governance/CharityAllowlist.test.js`:** Use `hardhat_impersonateAccount` on the game contract address to call `pickCharity(level)` directly — fast, deterministic, isolates GNRUS-side mechanics. This is the existing v32-era pattern in the current `DegenerusCharity.test.js` (`runGovernanceCycle` helper @ line 119). Conservation invariants are NOT asserted at this level — they're integration-only.

### Post-Gameover Inertness (TST-06)

- **D-256-POSTGAMEOVER-01 (ONE smoke test — GNRUS-side state only):**
  - Single it-block in `test/governance/CharityAllowlist.test.js` (or `test/unit/DegenerusCharity.test.js` `burnAtGameOver` describe — planner picks): after `burnAtGameOver`, assert `balanceOf[gnrusAddress] == 0` AND `totalSupply` reduced by the unallocated pool (already structurally covered by the existing `burnAtGameOver` describes — this it-block is a guarded restate).
  - **`setCharity` / `vote` / `pickCharity` post-gameover are explicitly NOT tested.** Documented behavior:
    - **Why inert by absence:** No game-side flow calls `charityResolve.pickCharity(...)` after `burnAtGameOver` — `DegenerusGameAdvanceModule:1634` is the only caller and it stops at gameover. With no further `pickCharity`, any `setCharity` mutation or `vote` weight write is functionally meaningless (no winner ever computed, no GNRUS ever distributed).
    - **GNRUS pool drained:** `burnAtGameOver` zeroes `balanceOf[address(this)]` and reduces `totalSupply`. Even if `pickCharity` were somehow re-invoked, the distribution math `(unallocated * DISTRIBUTION_BPS) / BPS_DENOM` evaluates to 0 → `LevelSkipped` skip-path C fires → no harm.
    - **Contract has no `finalized` guard on `setCharity` / `vote` / `pickCharity`** — confirmed by reading `contracts/GNRUS.sol`. This is **deliberate non-coverage** in Phase 256, NOT a deviation that needs amending in Phase 254 / 255.
  - REQUIREMENTS TST-06 wording "either revert or are inert (chosen behavior documented)" is satisfied by this CONTEXT.md prose + the ONE smoke test. Phase 257 audit will cite this section if it surfaces a finding-candidate around post-gameover surface (likely classified SAFE — pool drained, no exploitable state).
  - **Rejected — zero new tests:** Slightly misses the REQUIREMENTS TST-06 "verify GNRUS-side consistency" wording. ONE smoke is the floor.
  - **Rejected — two smoke tests with `pickCharity` post-burn no-op:** Overspec. The single GNRUS-state assertion + this CONTEXT.md prose covers the audit story.

### Test-Helper Factor

- **D-256-HELPER-01 (`test/helpers/charityFixture.js`):** Factor the v33.0 charity-specific test setup into a shared helper. Exports:
  - `impersonate(address)` / `stopImpersonating(address)` — copied verbatim from `test/unit/DegenerusCharity.test.js:26-43`. Keeps the 100-ETH balance set + impersonate-account RPC flow.
  - `giveSDGNRS(sdgnrs, gameAddress, recipient, amount)` — copied verbatim from `test/unit/DegenerusCharity.test.js:48-52`. Game-impersonated `transferFromPool(POOL_REWARD, ...)` flow.
  - `POOL_REWARD = 3` constant.
  - `deployGNRUSFixture()` — wraps `deployFullProtocol` with the v33.0-appropriate sDGNRS distribution to `voter1` / `voter2` / `voter3`. Returns the protocol object + named voter / recipient signers + addresses (matches the existing fixture shape at `DegenerusCharity.test.js:57-116`). REMOVES the v32 0.5%-threshold reasoning (no `PROPOSE_THRESHOLD_BPS` math) — voter amounts are tuned for v33 vote-weight scenarios (see `<specifics>`).
  - Optional convenience: `setCharityAs(gnrus, signer, slot, recipient)` — wraps `gnrus.connect(signer).setCharity(slot, recipient)` with vault-owner-impersonation if needed (vault-owner gating tests can pass the vault-owner signer directly).
  - `runLevelTransitionViaGame(...)` — for unit-side `pickCharity` calls (impersonate game, advance level, return receipt). Used ONLY by the unit governance file. The integration file uses real game flow per D-256-CONSERVATION-01.
  - Both `test/governance/CharityAllowlist.test.js` and the trimmed `test/unit/DegenerusCharity.test.js` import from this helper. Reduces duplication; future sDGNRS / vault-owner shape changes update one place.

### Gas Worst-Case Derivation + Regression Guardrail

- **D-256-GAS-01 (theoretical worst case derived in PLAN.md, then ONE measurement assertion):** Per `feedback_gas_worst_case.md` ("derive theoretical worst case FIRST, then test it").
  - **Plan-phase output:** PLAN.md derives theoretical worst case for the two hot paths:
    - **`setCharity` worst case:** instant-apply branch with full pending-edit set (`pendingEditSet == 0xFFFFF`, all 20 bits set) — `_futureBitmapAfter` iterates 20 slots, each with one cold SLOAD on `pendingEdit[i]` + popcount + cap-check + 1 SSTORE on `currentSlate[slot]` + 1 SSTORE on `currentActiveBitmap` (warm via the hot-pack slot) + 1 emit `CharityApplied`. Theoretical ceiling: ~22.1k SSTORE (cold currentSlate) + ~21k SLOAD ×20 (cold pendingEdit) + ~5k arithmetic + ~1.7k emit = ~70k–90k gas ceiling. Planner refines from the `_futureBitmapAfter` loop body.
    - **`pickCharity` worst case:** full 20-slot flush (every unlocked slot has a pending edit) + full 20-slot winner scan (every slot active post-flush, all weighted) + distribution apply. Theoretical ceiling: 20×(SLOAD pendingEdit + SSTORE currentSlate + SSTORE clear pendingEdit + emit CharityFlushed) + 20×(SLOAD slotApproveWeight) + 1 SSTORE bitmap + 1 SSTORE pendingEditSet + 1 SSTORE balanceOf[recipient] + 1 SSTORE balanceOf[address(this)] + 2 emits = ~600k–800k gas ceiling. Planner refines.
  - **Test-phase output:** ONE measurement test in `test/governance/CharityAllowlist.test.js` (or a dedicated `test/gas/CharityGas.test.js` — planner picks):
    - Fully populate the 20-slot slate via `setCharity` (instant-apply mostly + queue + flush sequence).
    - Drive `pickCharity` with all 20 slots active post-flush + all weighted (one voter per slot, full sDGNRS weight).
    - Assert `tx.gasUsed < CEILING` where CEILING = the PLAN.md theoretical ceiling × ~1.1 buffer. Regression guardrail — fires if a future commit introduces an O(n²) or hidden cold SLOAD.
  - **NOT a full gas suite.** Per-branch `setCharity` gas measurements, per-vote-count gas curves, etc. are deferred. If Phase 257 audit surfaces a gas-bomb finding, that's a new phase.

### Contract-Recipient Acceptance (Phase 254 deviation lock)

- **D-256-CONTRACT-RECIPIENT-01 (positive test: `setCharity(slot, contractAddress)` succeeds):** Phase 254 SUMMARY notes the `RecipientIsContract` revert path was **REMOVED** as a Phase 254 deviation (ROADMAP success criterion 1 explicitly says "Contract recipients accepted by design — no `RecipientIsContract` revert path to test"). Add a positive assertion in `test/governance/CharityAllowlist.test.js`:
  - `setCharity(uint8 slot, contractAddress)` on an empty slot → instant-apply branch — succeeds, emits `CharityApplied(slot, contractAddress)`, `currentSlate[slot] == contractAddress`.
  - Use any deployed protocol contract address as the recipient (e.g., `mockStETH.getAddress()` or `vault.getAddress()` — any non-EOA address available from the fixture).
  - Locks the deviation in test code; pre-empts a Phase 257 finding-candidate row.

### Queued-Add-Then-Cancel Branch

- **D-256-CANCEL-QUEUED-01 (test the non-obvious removal special case in `setCharity`):** `contracts/GNRUS.sol:382-391` has a special case: when `currentSlate[slot] == address(0)` AND `pendingEditSet[slot] == 1`, calling `setCharity(slot, address(0))` cancels the queued add (clears `pendingEdit[slot]`, clears the bitmap bit, emits `CharityQueued(slot, 0)`). This is a non-obvious branch — neither pure instant-apply nor pure queue. Add an explicit test:
  - Step 1: Queue an add to slot 5: `setCharity(5, addrA)` — slot is empty + no pending → falls into the else branch? Actually re-reading the code: line 380 checks `if (current == address(0))` then line 382 checks `if (recipient == address(0))`. So `setCharity(5, addrA)` with slot 5 empty + no pending → instant-apply (NOT queue). Need to construct the queued-add state differently.
  - **Correction:** The "queued add" state arises after `pickCharity` flushes a remove (slot was filled, queue-removed via `setCharity(slot, 0)` on a filled non-locked slot, then flushed → slot is now empty + no pending). Then a fresh `setCharity(slot, addrB)` instant-applies (no queue). Re-reading line 380-407: there is **no path** that creates `current == 0 && pendingEditSet[slot] == 1` because instant-apply on an empty slot writes `currentSlate[slot]` directly (no queue), and queue branch only fires when `current != 0`.
  - **Reconciliation:** the special case at line 382-391 is therefore **structurally unreachable in normal flow** — but it's defense-in-depth code (handles a hypothetical state where `pendingEditSet` bit is set on an empty slot — impossible by current invariants but the guard is cheap). This actually means: the test should **assert the structural unreachability** rather than try to drive the path. The planner should:
    - Confirm in PLAN.md whether this branch is reachable (it likely is NOT under current invariants).
    - If unreachable, document it as "defensive guard, no test path" and note it as a Phase 257 audit row (likely SAFE with grep-cited proof of unreachability).
    - If reachable via some sequence the planner discovers, add an explicit test driving that sequence.
  - **Discretion:** planner verdicts reachability + writes test or documents unreachability accordingly.

### Tie-Break Concrete Weights

- **D-256-TIEBREAK-01 (Claude's discretion — concrete weights wired by planner):** TST-04 says "tie → lowest slot index wins (concrete weights wired)". Exact sDGNRS amounts are planner discretion. Suggested shape (planner can refine):
  - voter1 votes slot 5 with 100 sDGNRS, voter2 votes slot 3 with 100 sDGNRS — assert `LevelResolved` event has `slot == 3` (lowest wins).
  - Edge: voter1 votes slot 5 with 100 sDGNRS, voter2 votes slot 5 with 100 sDGNRS, voter3 votes slot 3 with 200 sDGNRS — assert slot 3 wins (highest weight beats lowest-slot-tie-break in the non-tie case).
  - One additional case: 4-way tie across slots 3, 5, 7, 11 each with 100 sDGNRS — assert slot 3 wins (lowest among ALL tied slots).

### vote() Reason-Code Coverage

- **D-256-VOTE-REJECT-01 (assert all 4 vote rejection paths via reason codes):** Phase 255 D-255-VOTEREJECT-01 introduced `error VoteRejected(uint8 reason)` with constants `REJECT_EMPTY_SLOT = 0`, `REJECT_ALREADY_VOTED = 1`, `REJECT_ZERO_WEIGHT = 2`. Plus the slot-bounds check uses `error InvalidSlot()`. Test all 4:
  - `slot >= 20` → `revertedWithCustomError(gnrus, "InvalidSlot")` (no args).
  - `currentSlate[slot] == address(0)` → `revertedWithCustomError(gnrus, "VoteRejected").withArgs(0)` (REJECT_EMPTY_SLOT).
  - Double-vote on same `(level, voter, slot)` → `revertedWithCustomError(gnrus, "VoteRejected").withArgs(1)` (REJECT_ALREADY_VOTED).
  - Voter with `< 1e18 sDGNRS` (e.g., 0.5e18) → `revertedWithCustomError(gnrus, "VoteRejected").withArgs(2)` (REJECT_ZERO_WEIGHT). NOT zero balance — zero balance would also work but `< 1e18` exercises the integer-division floor (`/ 1e18 == 0`), which is the actual code path.

### pickCharity Reason-Code Coverage

- **D-256-PICKCHARITY-REJECT-01 (assert both `PickCharityRejected` reasons):** Phase 255 D-255-PICKCHARITY-ERROR-01 introduced `error PickCharityRejected(uint8 reason)` with `REJECT_LEVEL_NOT_ACTIVE = 0` and `REJECT_LEVEL_ALREADY_RESOLVED = 1`. Test both:
  - `pickCharity(level + 5)` (wrong level) → `revertedWithCustomError(gnrus, "PickCharityRejected").withArgs(0)`.
  - Re-call `pickCharity(level)` after first call succeeded → `revertedWithCustomError(gnrus, "PickCharityRejected").withArgs(1)`.

### Locked-Slot Coverage

- **D-256-LOCKED-SLOT-01 (test all three locked-slot paths):** Per `LOCKED_SLOTS = 3` (slots 0/1/2 immutable once filled):
  - First fill of slot 0/1/2 → instant-apply succeeds (locked-slot guard requires `current != 0`).
  - `setCharity(0, addrB)` after slot 0 filled with `addrA` → reverts `SlotLocked`.
  - `setCharity(0, address(0))` (remove attempt) on filled slot 0 → reverts `SlotLocked`.
  - `setCharity(1, addrB)` after slot 1 filled → reverts `SlotLocked` (parametric across all three locked slots).
  - **Voters CAN vote on locked slots** (per Phase 255 `<specifics>`) — add explicit positive test: voter votes on slot 0/1/2 → succeeds, `slotApproveWeight[level][0/1/2] += weight`.

### Multi-Slot Vote Independence

- **D-256-MULTI-VOTE-01 (vote applies FULL weight to EACH slot independently):** Per Phase 255 D-255-WEIGHT-STORAGE-01 and PROJECT.md design lock ("voter can approve multiple slots independently"). Test:
  - voter1 has 100 sDGNRS. voter1 calls `vote(3)` then `vote(5)` then `vote(7)` in same level — all three succeed, each emits `Voted(level, slot, voter1, 100)`, `slotApproveWeight[level][3] == 100`, `slotApproveWeight[level][5] == 100`, `slotApproveWeight[level][7] == 100`. Total weight applied = 300, NOT 100/3.
  - Confirms there's no "vote weight is divided across slots" misimplementation.

### Reuse / Drop Existing v32 Test Constants

- **D-256-CONST-CLEANUP-01:** Drop from `test/unit/DegenerusCharity.test.js` (now stale):
  - `PROPOSE_THRESHOLD_BPS = 50n` (line 16) — propose() deleted.
  - `VAULT_VOTE_BPS = 500n` (line 17) — vault-owner bonus removed.
  - `MAX_CREATOR_PROPOSALS = 5` (line 18) — propose() deleted.
  - Keep `INITIAL_SUPPLY` (still 1T), `MIN_BURN`, `DISTRIBUTION_BPS`, `BPS_DENOM`, `POOL_REWARD = 3` — still consumed by Burn / burnAtGameOver / fixture.
  - The `Token Metadata` describe assertion `proposalCount starts at 0` (line 175) is removed — `proposalCount` storage was deleted in Phase 254. No replacement needed (token-metadata describe stays focused on ERC-20 fields + currentLevel + finalized).

### Claude's Discretion

- **Tie-break exact sDGNRS amounts** — D-256-TIEBREAK-01 covers shape, planner picks numbers.
- **Gas-test file location** — `test/governance/CharityAllowlist.test.js` describe block vs new `test/gas/CharityGas.test.js` (per `test/gas/` directory convention). Planner picks; if `test/gas/` already has charity-related entries, co-locate.
- **Gas ceiling buffer** — D-256-GAS-01 suggests ×1.1 over theoretical worst case; planner adjusts based on Hardhat's solc gas estimation noise.
- **Queued-add-then-cancel reachability** — D-256-CANCEL-QUEUED-01 has an open question on whether the line 382-391 branch is reachable. Planner verdicts in PLAN.md.
- **TST-06 smoke location** — D-256-POSTGAMEOVER-01 says "in `test/governance/` or in `burnAtGameOver` describe of unit file"; planner picks based on cleanest narrative.
- **Whether to add a fuzz test for tie-break** — TST-04 doesn't require fuzz coverage; planner can add a bounded property test if it fits naturally into the Hardhat suite.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 256 Anchors

- `.planning/REQUIREMENTS.md` §"v33.0 Requirements" → §"TST" — 6 Phase 256 requirements (TST-01..06) verbatim.
- `.planning/ROADMAP.md` §"Phase 256: Charity Allowlist Test Coverage" — 5 success criteria; depends-on = Phase 254 + 255; write policy = `test/governance/...` requires explicit per-commit user approval per `feedback_no_contract_commits.md`; gas analysis derives theoretical worst case FIRST per `feedback_gas_worst_case.md`.
- `.planning/PROJECT.md` §"Current Milestone: v33.0 Charity Allowlist Governance" — full design lock (vote weight = sdgnrs balance / 1e18, no bonus, no threshold; tie-break = lowest active slot index; locked slots 0/1/2 immutable; cap = 20).

### Phase 254 + 255 Predecessor Artifacts (test surface)

- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-CONTEXT.md` — D-254-PENDING-01 (sentinel semantics), D-254-COUNT-01 (bitmap as single source of truth), D-254-EVENT-01 (CharityApplied / CharityQueued event style), D-254-VIEW-01 (paired-array view shape), D-254-VOTEPICK-01 (Phase 254 deletes propose/vote/pickCharity entirely; Phase 255 re-adds vote + pickCharity in new shape), D-254-ERROR-PRUNE-01 (errors deleted in Phase 254 + new errors added: `InvalidSlot`, `SlotAlreadyEmpty`, `SlotLocked`, `CapExceeded`).
- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-02-SUMMARY.md` — `setCharity` revert order documentation; **deviation: `RecipientIsContract` removed** (informs D-256-CONTRACT-RECIPIENT-01).
- `.planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-03-SUMMARY.md` — `_flushedBitmap` private helper, 5 view helpers (`getCharity`, `getActiveSlots`, `getPendingEdits`, `activeCount`, `activeCountAfterFlush`).
- `.planning/phases/255-vote-rewrite-resolve-flush-event-error-cleanup/255-CONTEXT.md` — D-255-VOTEREJECT-01 (reason codes 0/1/2 for vote sad paths), D-255-WEIGHT-STORAGE-01 (slotApproveWeight nested mapping), D-255-VOTE-REVERT-ORDER-01 (vote revert order), D-255-FLUSH-ORDER-01 (pickCharity operation order), D-255-PICKCHARITY-ERROR-01 (PickCharityRejected with reasons 0/1), D-255-FLUSH-EVENT-01 (CharityFlushed per applied edit), D-255-EVENT-CLEANUP-01 (Voted + LevelResolved v33 shapes).

### Live Contract State (post-Phase-255 HEAD)

- `contracts/GNRUS.sol` (post-Phase-255 HEAD) — current state to test against. All hot paths in scope:
  - `setCharity` @ L366-408 (instant-apply / queue / removal-special-case / locked-slot / cap)
  - `_futureBitmapAfter` @ L416-444 (cap-check helper used by setCharity)
  - `_flushedBitmap` @ L450-464 (used by `activeCountAfterFlush` view)
  - `_popcount32` @ L469-480
  - `getCharity` / `getActiveSlots` / `getPendingEdits` / `activeCount` / `activeCountAfterFlush` @ L489-552 (view helpers)
  - `vote(uint8 slot)` @ L558-581 (4 reject paths + state writes)
  - `pickCharity(uint24 level)` @ L601-674 (level-arg-check / idempotence / flush / 3 LevelSkipped paths / distribution)
  - `burn` @ L282 + `burnAtGameOver` @ L340 (preserved Phase 254/255)
  - Soulbound stubs @ L263-269 (`transfer` / `transferFrom` / `approve` revert `TransferDisabled`)
  - Errors @ L55-93 (the v33.0 error set: `Unauthorized`, `TransferDisabled`, `ZeroAddress`, `TransferFailed`, `InsufficientBurn`, `GameNotOver`, `AlreadyFinalized`, `InvalidSlot`, `SlotAlreadyEmpty`, `SlotLocked`, `CapExceeded`, `VoteRejected(uint8)`, `PickCharityRejected(uint8)`)
  - Events @ L100-124 (the v33.0 event set: `Transfer`, `Burn`, `Voted`, `LevelResolved`, `LevelSkipped`, `GameOverFinalized`, `CharityApplied`, `CharityQueued`, `CharityFlushed`)
  - Constants `LOCKED_SLOTS = 3`, `MAX_ACTIVE_SLOTS = 20`, `DISTRIBUTION_BPS = 200`, `BPS_DENOM = 10_000`, `MIN_BURN = 1e18`, `INITIAL_SUPPLY = 1e30`

### Existing Test Surface (in scope for prune / extend / reuse)

- `test/unit/DegenerusCharity.test.js` (992 lines / 78 it-blocks) — prune target per D-256-LAYOUT-01. Stale: `Governance -- Propose` (L379), `Governance -- Vote (proposalId)` (L505), `Governance -- pickCharity` (L617), `proposalCount` assertion in Token Metadata (L175), constants `PROPOSE_THRESHOLD_BPS`/`VAULT_VOTE_BPS`/`MAX_CREATOR_PROPOSALS` (L16-18). Keep: Token Metadata (minus L175), Soulbound, Burn Redemption, burnAtGameOver, receive, Edge Cases.
- `test/integration/CharityGameHooks.test.js` (252 lines) — extend target per D-256-CONSERVATION-01. Stale: `LevelSkipped(0) when no proposals exist for level 0` (L149) — rewrite to v33.0 slate-empty wording. Reusable: `pickCharity fires at level transition` describe (L115), `burnAtGameOver fires during gameover drain` describe (L192).
- `test/helpers/deployFixture.js` (171 lines) — `deployFullProtocol()` returns full 23-contract stack including `gnrus`, `sdgnrs`, `vault`, `game`. Used by both `DegenerusCharity.test.js` and `CharityGameHooks.test.js`. Phase 256 helper `test/helpers/charityFixture.js` wraps this — does NOT replace.
- `test/helpers/testUtils.js` (73 lines) — `eth()`, `getEvent`, `getEvents`, `ZERO_ADDRESS`. Reused as-is.

### Audit Baseline + Downstream Wire

- `audit/FINDINGS-v32.0.md` — closure attestation `MILESTONE_V32_AT_HEAD_acd88512` (carries forward via Phase 257 regression appendix).
- `contracts/modules/DegenerusGameAdvanceModule.sol:31-34` — `interface IGNRUSResolve { function pickCharity(uint24 level) external; }` (signature match — Phase 255 preserved).
- `contracts/modules/DegenerusGameAdvanceModule.sol:1634` — `charityResolve.pickCharity(lvl - 1);` (the wire that D-256-CONSERVATION-01 integration test exercises).
- `contracts/modules/DegenerusGameGameOverModule.sol:145` — `charityGameOver.burnAtGameOver();` (covered by existing CharityGameHooks integration `burnAtGameOver fires during gameover drain` describe).

### Project-Wide Feedback Memory (governs commit/edit policy)

- `feedback_no_contract_commits.md` — every `test/` modification requires explicit per-commit user approval (test/ files under same write-policy umbrella as contracts/).
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents test/ changes are "pre-approved".
- `feedback_wait_for_approval.md` — present diff and wait for explicit approval before editing.
- `feedback_manual_review_before_push.md` — never push without explicit user review of the diff.
- `feedback_no_history_in_comments.md` — pruned describes are deleted, not commented out, not annotated with "removed for v33.0" notes.
- `feedback_no_dead_guards.md` — no orphaned helpers in `charityFixture.js`; only export what's consumed.
- `feedback_gas_worst_case.md` — D-256-GAS-01 derives theoretical worst case in PLAN.md FIRST, then ONE measurement assertion as regression guardrail.
- `feedback_skip_research_test_phases.md` — Phase 256 is mechanical test-coverage; skip `gsd-research-phase` and plan directly.
- `feedback_test_rnglock.md` — not directly applicable (no RNG path in v33.0 charity governance), but the deploy-blocking-tests-must-run-before-deploy principle applies: Phase 256 tests are the gate before any v33.0 deploy.
- `feedback_batch_contract_approval.md` — test file edits batch into one diff per file at end of phase; user approves once per file (NOT per atomic commit during agent work).

### Cross-Phase Context (v33.0 milestone)

- `.planning/REQUIREMENTS.md` §"AUDIT" → AUDIT-01..04 — Phase 257 consumes Phase 256 test pass-rate as evidence that the v33.0 surface is exercised; AUDIT-02 adversarial sweep cross-references Phase 256 tests for SAFE attestations.
- Phase 257 success criterion 4 (conservation re-proof) cites the integration-side conservation tests from D-256-CONSERVATION-01 as evidence.
- Phase 257 closure signal `MILESTONE_V33_AT_HEAD_<sha>` requires Phase 256 tests passing at the post-test HEAD.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Test Assets

- **`deployFullProtocol()` fixture** (`test/helpers/deployFixture.js:31-146`) — full 23-contract stack with mock VRF / stETH / LINK / feed. Returns named signers (`deployer`, `alice`, `bob`, `carol`, `dan`, `eve`, `others[]`) + protocol contracts including `gnrus`, `sdgnrs`, `dgnrs`, `vault`, `game`, all 9 game modules, and the 4 mock externals. Charity tests reuse via the new `charityFixture.js` wrapper (D-256-HELPER-01).
- **`impersonate(address)` / `stopImpersonating(address)`** (`test/unit/DegenerusCharity.test.js:26-43`) — hardhat_impersonateAccount + 100-ETH balance set + getSigner(). Migrate verbatim into `charityFixture.js`.
- **`giveSDGNRS(sdgnrs, gameAddress, recipient, amount)`** (`test/unit/DegenerusCharity.test.js:48-52`) — game-impersonated `transferFromPool(POOL_REWARD, recipient, amount)` flow. Migrate verbatim into `charityFixture.js`.
- **Existing `Token Metadata` / `Soulbound Enforcement` / `Burn Redemption` / `burnAtGameOver` / `receive() -- ETH acceptance` / `Edge Cases` describes** in `DegenerusCharity.test.js` — preserved in the prune; only the 3 Governance describes deleted.
- **Existing `pickCharity fires at level transition` + `burnAtGameOver fires during gameover drain` describes** in `CharityGameHooks.test.js` — preserved + extended per D-256-CONSERVATION-01.
- **`testUtils.js` helpers** (`eth`, `getEvent`, `getEvents`, `ZERO_ADDRESS`) — reused as-is.

### Established Patterns

- **Hardhat `revertedWithCustomError(contract, "ErrorName").withArgs(...)`** — reuses the existing pattern from `DegenerusCharity.test.js` (e.g., L437 `AlreadyProposed`, L549 `InvalidProposal`). Phase 256 reason-code asserts use this verbatim with the new error names from Phase 254 + 255 + the `uint8 reason` arg for the two `*-Rejected` errors.
- **Game-impersonation for `pickCharity`** (`DegenerusCharity.test.js` `runGovernanceCycle` helper @ L120) — the v32-era pattern of impersonating the game address to call `pickCharity` directly. Phase 256 reuses this for unit-side `pickCharity` driving (NOT for integration conservation per D-256-CONSERVATION-01).
- **Vault-owner gating** — vote-related tests don't touch vault-owner gating; `setCharity` tests do (vault-owner-only). Vault-owner is the contract `deployer` by default (per `vault.isVaultOwner(deployer.address)` returning true after deploy). Tests use `deployer` for `setCharity` calls; non-deployer signers test the `Unauthorized` revert.
- **Reason-code assertions with `withArgs(N)`** — NEW pattern in Phase 256 per Phase 255 `*-Rejected(reason)` errors. Pattern:
  ```js
  await expect(gnrus.connect(voter).vote(slot))
    .to.be.revertedWithCustomError(gnrus, "VoteRejected")
    .withArgs(2); // REJECT_ZERO_WEIGHT
  ```
  Tests can mirror the Phase 255 reason-code constants (could be inlined as `const REJECT_ZERO_WEIGHT = 2;` at the top of the test file for readability — planner discretion).

### Integration Points

- **`test/governance/`** — new directory created in this phase (currently absent). Hardhat picks up the directory automatically (no `hardhat.config.js` change needed).
- **`test/helpers/charityFixture.js`** — new file, factored from `DegenerusCharity.test.js`. Imported by both the new governance file and the trimmed unit file.
- **`test/integration/CharityGameHooks.test.js`** — extended (not replaced). The conservation describe added at the end keeps the existing `pickCharity fires at level transition` + `burnAtGameOver fires during gameover drain` describes intact.
- **No `contracts/` writes in Phase 256.** D-256-POSTGAMEOVER-01 explicitly chose NOT to amend Phase 254/255 to add `finalized` guards — post-gameover behavior tested as inert by absence.
- **`hardhat.config.js`** — verify the test glob already covers `test/**/*.test.js` (it does — Hardhat's default). No config change needed.

</code_context>

<specifics>
## Specific Ideas

- **vote-weight zero setup:** voter with `< 1e18` sDGNRS (e.g., `5e17` = 0.5 sDGNRS) triggers `weight = 5e17 / 1e18 == 0` → `VoteRejected(REJECT_ZERO_WEIGHT)`. Tests this branch (NOT just zero-balance, which would also work but doesn't exercise the integer-floor math).
- **Multi-slot vote independence:** voter1 with 100 sDGNRS calls `vote(3)`, `vote(5)`, `vote(7)` — each gets full 100 weight. Total `sum(slotApproveWeight[level][i])` = 300, NOT 100/3 = ~33.
- **Tie-break weights (suggested):** voter1 votes slot 5 with 100, voter2 votes slot 3 with 100 → slot 3 wins (lowest tie-break). Planner refines exact numbers.
- **Locked-slot first-fill:** `setCharity(0, addrA)` succeeds (instant-apply since `current == 0`); `setCharity(0, addrB)` reverts `SlotLocked` (locked-slot guard at L375 fires before branch dispatch); `setCharity(0, address(0))` ALSO reverts `SlotLocked` (guard fires regardless of recipient).
- **Cap = 20 fill order:** to fill 20 slots for the cap test, fill slots 0-19 via successive `setCharity` calls (all instant-apply since each slot is empty). Cap test then attempts a 21st via the queue branch on a filled non-locked slot (e.g., `setCharity(5, newAddr)` with the future bitmap popcount calculating to 21 — but this is structurally impossible since cap = 20 and we already have 20 set; so the queue case actually replaces, not adds. Cap=21 only happens via instant-apply on a previously-cleared slot when pendingEdits add others — planner derives the exact call sequence in PLAN.md).
- **Edit-queue level-boundary stress:** queue replace on slot 5, queue remove on slot 7, instant-apply slot 12 — all in same level. Voters can vote slot 5 (sees OLD address), slot 7 (still votable until flush), slot 12 (votable in same level — instant-apply was D-254-EVENT-01 separation rationale). After `pickCharity`, slot 5 has new address, slot 7 is empty, slot 12 unchanged, all `pendingEdit` entries cleared, `pendingEditSet == 0`.
- **Conservation across level transition (integration):** assert deltas across the `pickCharity` call:
  - `gnrus.balanceOf(recipient) += distribution` where `distribution = unallocated * 200 / 10000 = unallocated * 0.02`.
  - `gnrus.balanceOf(gnrusAddress) -= distribution`.
  - `gnrus.totalSupply()` unchanged.
  - `sdgnrs.totalSupply()`, `sdgnrs.votingSupply()` unchanged.
  - `dgnrs.totalSupply()` unchanged.
  - BURNIE / coinflip per-pool accounting unchanged.
  - `gnrus.transfer(...)` reverts `TransferDisabled` (smoke).
- **GNRUS-side post-gameover smoke (TST-06):** after `burnAtGameOver`:
  - `gnrus.balanceOf(gnrusAddress) == 0`.
  - `gnrus.totalSupply() == 0` (unallocated was the entire supply at this point — fixture-dependent; may need to be `<initial unallocated>` if any prior `pickCharity` distributions reduced the pool).
  - `gnrus.finalized() == true`.
  - `GameOverFinalized` event emitted.
- **Reason-code constants in test file:** copy-paste from `contracts/GNRUS.sol`:
  ```js
  const REJECT_EMPTY_SLOT = 0;
  const REJECT_ALREADY_VOTED = 1;
  const REJECT_ZERO_WEIGHT = 2;
  const REJECT_LEVEL_NOT_ACTIVE = 0;
  const REJECT_LEVEL_ALREADY_RESOLVED = 1;
  ```
  Inline at top of `test/governance/CharityAllowlist.test.js` for readability.

</specifics>

<deferred>
## Deferred Ideas

- **Active-count accounting drift stress** (was option in 2nd question, NOT selected) — Phase 257 AUDIT-02-(f) sweep target. Defer to Phase 257 — it has the adversarial-sweep budget and grep-cited evidence requirement that fits this analysis better than test-coverage.
- **Edit-queue pending-overwrite explicit stress test (queue A then B → only B applies)** (was option in 2nd question, NOT selected) — TST-01 success criterion 1 covers it implicitly via the cap test's queue scenarios. Add only if planner finds a structural ambiguity that needs an explicit assertion.
- **Cap=21 in BOTH branches as separate tests** (was option in 2nd question, NOT selected) — covered by ROADMAP success criterion 1 ("`CapExceeded` on 21st add via either branch") with a single combined test scenario; separate per-branch tests are overspec.
- **Fuzz coverage for tie-break / vote weighting** — TST-04 + TST-03 don't require fuzz. If Phase 257 audit surfaces a finding-candidate that benefits from fuzz coverage, that's a new phase or a sibling Halmos invariant addition.
- **Full gas suite per branch / per vote count** — D-256-GAS-01 limits this phase to ONE measurement assertion as regression guardrail. Per-branch gas curves and gas-bomb fuzz are deferred.
- **Solidity coverage report wiring** (e.g., `solidity-coverage` plugin) — out of scope; if Phase 257 wants line-coverage evidence, that's its own phase or addendum.
- **Foundry / Halmos invariant coverage for the v33.0 surface** — Phase 256 is Hardhat-only per ROADMAP wording. Foundry fuzz and Halmos symbolic invariants for v33.0 are a separate phase if Phase 257 audit identifies the need.
- **Move stale v32 test artifacts to an archive directory** — out of scope; deletion is the chosen disposition (per `feedback_no_history_in_comments.md`).
- **TST-06 contract amendment to add `finalized` guards** — explicitly REJECTED in D-256-POSTGAMEOVER-01. If a future v34.0+ change wants stronger post-gameover guarantees, that's its own phase.

</deferred>

---

*Phase: 256-charity-allowlist-test-coverage*
*Context gathered: 2026-05-06*
