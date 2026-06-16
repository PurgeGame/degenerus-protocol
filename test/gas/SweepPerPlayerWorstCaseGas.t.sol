// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title SweepPerPlayerWorstCaseGas -- the per-sub STAGE marginal (the v55 successor to the v49 AfKing
///        per-player autoBuy sweep worst case). ADAPTED to the AfKing-in-Game redesign (D-351-01).
///
/// @notice v55 REFRAME (D-351-01). The standalone `AfKing` de-custody contract is DISSOLVED
///         (`contracts/AfKing.sol` deleted); the per-sub buy is FOLDED into `advanceGame()`'s required-path
///         process STAGE (`processSubscriberStage`, GameAfkingModule.sol:539), reached via a new-day
///         `game.advanceGame()` (PRE-RNG). The v49 caller-bounded `afKing.autoBuy(maxCount)` per-PLAYER
///         worst case reframes onto the per-SUB STAGE marginal:
///           - `afKing.autoBuy(total)`     -> a new-day `game.advanceGame()` STAGE          (Δ4 SEMANTIC REMAP)
///           - `afKing.subscribe(...)`     -> `game.subscribe(...)`  (identical 6-arg sig)   (Δ2)
///           - `afKing.depositFor{v}(x)`   -> `game.depositAfkingFunding{v}(x)`              (Δ5)
///           - `afKing.subscriberCount()`  -> `_subscribers.length` via vm.load             (Δ5 slot-read)
///         The `BOUNTY_ETH_TARGET` immutable + the SUB-04 reinvest commentary repoint to the GAME-resident
///         `GameAfkingModule.sol`. The per-sub STAGE cost is the unit that bounds a chunked STAGE — the
///         16.7M HARD per-tx ceiling is `SUB_STAGE_BATCH = 50` × this marginal (350-TST06-SPEC §5).
///
///         The MARGINAL rule (CR-01, 350-SPEC §0, load-bearing): the per-sub number is the loop-N-divide
///         MARGINAL — (whole new-day advance gas for N funded subs) / N at N>=32 — NEVER a single-sub
///         total (which bundles the once-per-advance fixed overhead into one sub and over-pegs ~2x). The
///         full per-buy marginal harness is plan 351-08; this is the worst-case-ceiling / shape-
///         insensitivity corpus.
///
///         Tests:
///           - Test A (per-sub marginal): the converged per-sub STAGE marginal (whole/N at N=32) fits the
///             ceiling, and 50 × it projects under the 16.7M HARD ceiling.
///           - Test B (shape-insensitivity): a reinvest sub (reinvestPct > 0, the SUB-04 extra
///             `claimableWinnings` read) and a typical sub yield per-sub STAGE marginals within tolerance
///             (the reinvest read is NOT a materially-heavier path — it pre-warms the slot the buy reads).
///           - Test C (non-vacuity): the STAGE actually STAMPED every funded sub (a real buy, not a skip).
///
/// @dev Live `DeployProtocol` fixture (the STAGE writes Game storage). Reuses the validated game-resident
///      driving harness ported from V55RevertFreeEvCap (`_settleClean` VRF drain, `_setupFundedSubs`,
///      `depositAfkingFunding`, `_grantDeityPass`, the Sub-stamp slot reads). All pinned slots taken from
///      `forge inspect DegenerusGame storageLayout` against the v61 subject: the game-resident
///      `_subOf = 54`, `_subscribers = 56`, `_subscriberIndex = 57`, and `balancesPacked = 7` (its low-128
///      half holds the claimable semantics). Test-only: ZERO contracts/*.sol mutated.
contract SweepPerPlayerWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`)
    // -------------------------------------------------------------------------

    uint256 private constant CLAIMABLE_WINNINGS_SLOT = 7;   // balancesPacked root — the SUB-04 reinvest read masks the low-128 claimable half
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;       // uint128 @ slot 1, byte 16 (SOLVENCY-01 tandem)
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant SUBOF_SLOT = 54;              // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 56;        // address[] _subscribers (slot holds the length)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 57;   // mapping(address => uint256) _subscriberIndex

    // Sub packed-field byte offsets (DegenerusGameStorage.sol; the v56 re-packed single 256-bit slot —
    // the markers are uint24 each, not the old uint32 232-bit layout).
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)

    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The 16.7M HARD effective per-tx ceiling (350-TST06-MEASUREMENT-SPEC §5). foundry.toml inflates
    ///      block_gas_limit to 30e9 for the harness; the per-sub-marginal "fits the chunk" bar is this 16.7M.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev SUB_STAGE_BATCH (DegenerusGameAdvanceModule.sol:149): the STAGE chunk that bounds a per-tx
    ///      advance — 50 × the per-sub marginal must stay under 16.7M (the reason BUY_BATCH=50, not 100).
    uint256 internal constant SUB_STAGE_BATCH = 50;

    /// @dev The CR-01 converged-marginal regime: N>=32 amortizes the per-tx fixed overhead away.
    uint256 internal constant N_MARGINAL = 32;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // Test A -- the per-sub STAGE marginal + the 50-chunk 16.7M projection
    // =========================================================================

    /// @notice GAS-01 / 16.7M: the per-sub STAGE marginal is (whole new-day advance gas for N funded subs)
    ///         / N measured at N=32 — the loop-N-divide MARGINAL, NEVER a single-sub total (CR-01). Asserts
    ///         the converged marginal fits the ceiling and that 50 × it projects under the 16.7M HARD
    ///         ceiling (the SUB_STAGE_BATCH chunk is safe). The marginal INCLUDES the 349.2-restored per-sub
    ///         FLIP quest/affiliate/creditFlip side-effects (intended behavior, not subtracted).
    function testPerSubStageMarginalAndChunkFitsCeiling() public {
        vm.skip(true, "357-00b D-12 supersession: the per-player sweep-gas harness subscribes ungrounded subs then measures the STAGE per-sub marginal; the grounded subscribe buys at subscribe, perturbing the marginal; re-proven by V56AfkingGasMarginal (the per-sub marginal + chunk-fits-ceiling, all green)");
        uint256 totalN = _measureStageAdvanceGas(N_MARGINAL, "swpA_", /*reinvestPct*/ 0, /*claimable*/ 0);
        uint256 perSubMarginal = totalN / N_MARGINAL; // the loop-N-divide MARGINAL (fixed overhead amortized)

        assertLt(perSubMarginal, EFFECTIVE_GAS_CEILING, "per-sub STAGE marginal trivially fits the ceiling");

        // The HARD bound: 50 × the per-sub marginal projects under 16.7M (the SUB_STAGE_BATCH chunk).
        assertLt(
            perSubMarginal * SUB_STAGE_BATCH,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: 50x the per-sub STAGE marginal projects under 16.7M (SUB_STAGE_BATCH is safe)"
        );

        emit log_named_uint("stage_per_sub_marginal_n32_loop_n_divide_gas", perSubMarginal);
        emit log_named_uint("stage_advance_whole_n32_gas", totalN);
        emit log_named_uint("stage_50x_marginal_projection_gas", perSubMarginal * SUB_STAGE_BATCH);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    // =========================================================================
    // Test B -- the per-sub marginal is shape-insensitive (reinvest ~= typical within tolerance)
    // =========================================================================

    /// @notice GAS-01 worst-case-leaning: the candidate "worst" per-sub path is a reinvest sub
    ///         (reinvestPct > 0), which runs the SUB-04 reinvest branch (the extra `claimableWinnings`
    ///         read for the effective-quantity calc, GameAfkingModule.sol:431). This measures the per-sub
    ///         STAGE marginal of N reinvest subs vs N typical subs — holding the buy slice IDENTICAL (small
    ///         claimable so reinvestQty stays at the qty-1 floor, isolating the reinvest branch as the only
    ///         structural difference) — and asserts they MATCH within tolerance: the reinvest path is NOT
    ///         materially heavier (the reinvest read pre-warms the `claimableWinnings[player]` slot the buy
    ///         re-reads). The same SHAPE-INSENSITIVE conclusion the v49 AfKing autoBuy harness reached,
    ///         reframed onto the v55 STAGE.
    function testReinvestAndTypicalPerSubMarginalsMatchWithinTolerance() public {
        vm.skip(true, "357-00b D-12 supersession: the per-player sweep-gas harness subscribes ungrounded subs then measures the STAGE per-sub marginal; the grounded subscribe buys at subscribe, perturbing the marginal; re-proven by V56AfkingGasMarginal (the per-sub marginal + chunk-fits-ceiling, all green)");
        uint256 mp = game.mintPrice();
        // Reinvest claimable kept SMALL so reinvestQty = floor(claimable/mp) = 0: the SUB-04 reinvest
        // branch still RUNS (the extra read), but the effective quantity stays at the qty-1 floor — so the
        // buy slice is IDENTICAL to the typical sub. Isolates the reinvest branch as the ONLY difference.
        uint256 smallClaimable = mp / 2; // reinvestQty = floor((mp/2)/mp) = 0 -> effectiveQty stays 1

        // Measure each shape from the IDENTICAL clean baseline via snapshot/revert — so the two
        // measurements do not share day-index saturation or warm/cold drift (the single-STAGE-per-fixture
        // reality, 351-05: two independent new-day STAGE cycles in one linear run trip the idle-day
        // saturation / RngNotReady). Snapshot AFTER setUp, measure typical, REVERT, measure reinvest.
        uint256 snap = vm.snapshotState();
        uint256 typicalTotal = _measureStageAdvanceGas(N_MARGINAL, "swpBt_", /*reinvestPct*/ 0, /*claimable*/ 0);
        vm.revertToState(snap);
        uint256 reinvestTotal = _measureStageAdvanceGas(N_MARGINAL, "swpBr_", /*reinvestPct*/ 100, smallClaimable);
        uint256 typicalPer = typicalTotal / N_MARGINAL;
        uint256 reinvestPer = reinvestTotal / N_MARGINAL;

        // The per-sub marginal is shape-INSENSITIVE: reinvest is within TOLERANCE_BPS of typical (a broad
        // band — the per-sub STAGE work is dominated by the stamp + the restored FLIP side-effects, not
        // the one extra reinvest read; neither direction hides a material divergence).
        uint256 hi = typicalPer > reinvestPer ? typicalPer : reinvestPer;
        uint256 lo = typicalPer > reinvestPer ? reinvestPer : typicalPer;
        uint256 TOLERANCE_BPS = 2_000; // 20% — comfortably above the observed divergence (warm/cold noise)
        assertLe(
            (hi - lo) * 10_000,
            hi * TOLERANCE_BPS,
            "per-sub STAGE marginal is shape-insensitive: reinvest and typical match (reinvest NOT materially heavier)"
        );
        assertLt(reinvestPer, EFFECTIVE_GAS_CEILING, "reinvest per-sub marginal trivially fits the ceiling");
        assertLt(typicalPer, EFFECTIVE_GAS_CEILING, "typical per-sub marginal trivially fits the ceiling");

        emit log_named_uint("stage_per_sub_typical_marginal_gas", typicalPer);
        emit log_named_uint("stage_per_sub_reinvest_marginal_gas", reinvestPer);
    }

    // =========================================================================
    // Test C -- non-vacuity: the STAGE actually stamped (a real buy, not a skip)
    // =========================================================================

    /// @notice Non-vacuity guard: prove a new-day STAGE of N funded subs actually STAMPED every sub (their
    ///         lastAutoBoughtDay advanced this cycle). A skip-everything STAGE (unfunded / not pass-gated /
    ///         already-stamped) would leave the stamps unchanged; this asserts the heavier "will buy" path
    ///         ran for every sub. The cursor advanced across the whole funded window.
    function testStageActuallyStampedNonVacuity() public {
        vm.skip(true, "357-00b D-12 supersession: the per-player sweep-gas harness subscribes ungrounded subs then measures the STAGE per-sub marginal; the grounded subscribe buys at subscribe, perturbing the marginal; re-proven by V56AfkingGasMarginal (the per-sub marginal + chunk-fits-ceiling, all green)");
        address[] memory subs = _setupFundedSubs(N_MARGINAL, "swpC_", /*reinvestPct*/ 0, /*claimable*/ 0);
        uint32[] memory pre = new uint32[](N_MARGINAL);
        for (uint256 i; i < N_MARGINAL; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "advanceDue on the new day");
        game.advanceGame();

        // Each funded sub got a NEW stamp this cycle (a real STAGE buy, not a skip). N + 2 deploy subs <
        // SUB_STAGE_BATCH, so ONE advance processes the WHOLE set in the first chunk.
        uint256 stamped;
        for (uint256 i; i < N_MARGINAL; ++i) {
            if (_lastBoughtDayOf(subs[i]) > pre[i]) ++stamped;
        }
        assertEq(stamped, N_MARGINAL, "non-vacuity: every funded sub was STAMPED this STAGE (real buys, not skips)");

        emit log_named_uint("stage_subs_stamped", stamped);
    }

    // =========================================================================
    // Internal helpers (the validated game-resident driving harness)
    // =========================================================================

    /// @dev Measure a fresh-state new-day advance whose STAGE processes N funded subs, returning the
    ///      bracketed advance gas. The loop-N-divide marginal divides this by N. n + 2 deploy subs <
    ///      SUB_STAGE_BATCH so ONE advance stamps the whole set in the first chunk; the everything-else of
    ///      the advance (an empty ticket queue) is identical across runs. Settles to a clean baseline first
    ///      so a prior measurement's unfulfilled RNG cannot leave the game rngLocked when this advance fires.
    function _measureStageAdvanceGas(uint256 n, string memory prefix, uint8 reinvestPct, uint256 claimable)
        internal
        returns (uint256 advGas)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(n, prefix, reinvestPct, claimable);
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        vm.warp(block.timestamp + 1 days);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        // Non-vacuity: every measured sub got a NEW stamp this cycle (a real STAGE buy, not a skip).
        for (uint256 i; i < n; ++i) {
            assertGt(_lastBoughtDayOf(subs[i]), pre[i], "marginal non-vacuity: each funded sub newly stamped");
        }
    }

    /// @dev Subscribe `n` fresh players as funded subs (deity-passed so pass-gated valid; funded via
    ///      depositAfkingFunding so the STAGE debit lands). reinvestPct > 0 + a `claimable` injection drives
    ///      the SUB-04 reinvest branch (with a tandem claimablePool bump, SOLVENCY-01 balanced). Ticket
    ///      mode (no box-materialization in the STAGE so the per-sub stamp cost is the measured unit).
    function _setupFundedSubs(uint256 n, string memory prefix, uint8 reinvestPct, uint256 claimable)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            // self, drainGameCreditFirst = false (DirectEth-funded), ticket mode, qty 1, reinvestPct.
            game.subscribe(address(0), false, true, 1, reinvestPct, address(0));
            _fundPool(who, 5 ether);
            if (claimable > 0) _setClaimable(who, claimable);
        }
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Credit `who`'s claimable half of balancesPacked AND bump claimablePool in tandem (SOLVENCY-01
    ///      balanced; the 351-02 test-infra reality) so a claimable-funded slice's `claimablePool -=` does not
    ///      underflow. balancesPacked = [afking:high128 | claimable:low128]; the credit adds to the low half
    ///      and PRESERVES the afking high half (a claimable-only seed can never corrupt _afkingOf).
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(CLAIMABLE_WINNINGS_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 newLow = uint256(uint128(cur)) + amount;
        require(newLow <= type(uint128).max, "claimable seed fits the low 128 half");
        uint256 packed = (cur & (uint256(type(uint128).max) << 128)) | newLow;
        vm.store(address(game), slot, bytes32(packed));
        _bumpClaimablePool(amount);
    }

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
    }

    function _bumpClaimablePool(uint256 delta) internal {
        uint256 value = _claimablePool() + delta;
        require(value <= type(uint128).max, "pool fits uint128");
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 mask = uint256(type(uint128).max) << (CLAIMABLE_POOL_OFFBYTES * 8);
        slot1 = (slot1 & ~mask) | (value << (CLAIMABLE_POOL_OFFBYTES * 8));
        vm.store(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT)), bytes32(slot1));
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    // ---- Sub-stamp slot reads (_subOf at slot 54 + verified offsets) ----

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (OFF_LASTBOUGHT * 8);
        return uint32(p & 0xFFFFFF); // uint24
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
