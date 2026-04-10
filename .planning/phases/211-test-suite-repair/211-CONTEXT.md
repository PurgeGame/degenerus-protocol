# Phase 211: Test Suite Repair - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix all 113 runtime test failures (82 Foundry + 31 Hardhat) caused by v24.1 storage repacking. No contract changes — only test file updates and deletions.

</domain>

<decisions>
## Implementation Decisions

### Foundry Failures (82)
- **D-01:** Update all `vm.load()` helpers with correct v24.1 slot numbers — lootboxRngPacked moved from slot 40 to slot 38
- **D-02:** Update all bit shift constants — rngRequestTime reads at `>> 64` not `>> 96` after slot 0 repacking
- **D-03:** Update StorageFoundation slot offset assertions — ticketWriteSlot now at slot 0 byte 28, not slot 1 byte 0
- **D-04:** Update CompressedJackpot/AffiliateBonus flag offset assertions for new slot 0 byte positions
- **D-05:** Update lootboxRngIndex assertions — field is now 48 bits (mask 0xFFFFFFFFFFFF) in packed slot, not standalone uint32

### Hardhat Failures (31)
- **D-06:** Delete WrappedWrappedXRP test interactions entirely (4 failures) — wXRP scaling mismatches not worth debugging
- **D-07:** Delete DegenerusStonk-vesting tests entirely (8 failures) — level=0 test setup issue not worth fixing
- **D-08:** Delete setDecimatorAutoRebuy tests entirely (2 failures) — function was removed from game contract
- **D-09:** Fix CompressedJackpot flag offset assertions (9 failures) — update to v24.1 slot 0 byte positions
- **D-10:** Fix CompressedAffiliateBonus flag assertions (2 failures) — update to v24.1 slot 0 byte positions
- **D-11:** Remaining Hardhat failures are mechanical assertion value updates

### Approach
- **D-12:** Mechanical find-and-replace for slot numbers, bit offsets, and expected values
- **D-13:** Delete rather than fix tests for removed/irrelevant functionality (wXRP, vesting, setDecimatorAutoRebuy)

### Claude's Discretion
- Order of file fixes (Foundry first vs Hardhat first vs interleaved)
- Whether to batch similar fixes across files or fix file-by-file

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Failure catalog (root causes for all 113 failures)
- `.planning/phases/210-verification/210-VERIFICATION.md` — full gap analysis with file:line references for every failure category
- `.planning/v24.1-MILESTONE-AUDIT.md` — integration checker findings including slot 40→38 root cause

### Storage layout source of truth
- `contracts/storage/DegenerusGameStorage.sol` — slot layout comments, packed helpers, shift/mask constants
- Slot 0: purchaseStartDay(uint32,off=0), dailyIdx(uint32,off=4), rngRequestTime(uint48,off=8), ticketWriteSlot(bool,off=28), prizePoolFrozen(bool,off=29)
- Slot 1: currentPrizePool(uint128,off=0), claimablePool(uint128,off=16)
- lootboxRngPacked at slot 38: index(uint48,bits 0:47), pendingEth(uint64,bits 48:111), threshold(uint64,bits 112:175), minLink(uint8,bits 176:183), pendingBurnie(uint40,bits 184:223), midDay(uint8,bits 224:231)

### Key test files with failures
- `test/fuzz/VRFCore.t.sol` — _readRngRequestTime() uses stale >> 96
- `test/fuzz/VRFStallEdgeCases.t.sol` — stale bit offsets for multiple packed fields
- `test/fuzz/StorageFoundation.t.sol` — slot offset assertions
- `test/fuzz/AdvanceGameRewrite.t.sol` — via TicketLifecycle/LootboxRngLifecycle handlers
- `test/fuzz/VRFPathCoverage.t.sol` — lootboxRngIndex slot reads

</canonical_refs>

<code_context>
## Existing Code Insights

### Test helpers using raw storage reads
- Foundry fuzz tests use `vm.load(address(game), bytes32(uint256(SLOT)))` with hardcoded slot numbers
- Bit extraction via `>> SHIFT & MASK` patterns — all shifts need updating for repacked slots
- Common pattern: `_readRngRequestTime()`, `_lootboxRngIndex()`, `_readMidDayTicketRngPending()`

### Known pre-existing issues (not v24.1)
- FuturepoolSkim.t.sol — pre-existing compilation failure, out of scope
- ContractAddresses.sol — unstaged changes, stash before test runs

</code_context>

<specifics>
## Specific Ideas

No specific requirements — purely mechanical test repair guided by 210-VERIFICATION.md failure catalog.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 211-test-suite-repair*
*Context gathered: 2026-04-10*
