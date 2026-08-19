// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title BoxOrderOpenGas -- what a box costs to open under the count model.
///
/// @notice Sizing measurement for `MAX_BOXES_PER_ORDER`. The count model made an entry's cost a
///         function of how many boxes it holds rather than a flat per-entry constant, and the
///         cap exists to keep one maximum entry inside a single call. That only holds if the
///         per-box marginal is what the design assumed, so this measures it directly:
///
///           (1) PER-BOX MARGINAL inside one entry -- gas(N boxes) - gas(1 box), over N-1. This
///               is the number the cap divides into the budget. It is measured inside ONE entry
///               on purpose: consolidation means the second box through the hundredth share the
///               settlement lanes with the first, so the marginal is much lower than the cost of
///               the first box, and it is the marginal that the cap is sized against.
///
///           (2) MAX-ENTRY TOTAL -- one player, MAX_BOXES_PER_ORDER boxes, opened in a single
///               call. The invariant this exists to check: a maximum entry fits a call on its
///               own. The afking and human legs no longer share a call, so this is the whole
///               tx, not a share of one.
///
///           (3) PER-PLAYER ASYMMETRY -- N boxes for ONE player against N boxes spread across N
///               players. The count model's central claim is that the first collapses to one set
///               of per-player writes while the second pays N cold sets; this puts a number on it.
///
/// @dev Orders are packed [small:8][med:8][large:8][customCount:8][customSize:48], so an order of
///      N smalls is just the integer N. A small is one ticket price, 0.01 ETH at genesis levels.
///
///      Loose asserts only -- this is a recorder for a sizing decision, not a regression gate.
///      Test-only: ZERO contracts/*.sol mutated.
contract BoxOrderOpenGas is DeployProtocol {
    /// @dev The 16.7M HARD never-exceed ceiling used throughout test/gas/*.t.sol.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;
    /// @dev The real mainnet block gas limit -- the bound the cap is actually sized against.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;
    /// @dev MAX_BOXES_PER_ORDER in DegenerusGameStorage.
    uint256 internal constant MAX_BOXES = 100;
    /// @dev Foundry's gasleft-delta excludes the ~21,064 intrinsic every real tx also pays.
    uint256 internal constant INTRINSIC_TX_GAS = 21_064;
    /// @dev OPEN_WEIGHT_BUDGET in GameAfkingModule — the shared per-call walk budget.
    uint256 internal constant OPEN_WEIGHT_BUDGET = 1920;
    /// @dev The sweep's two walk weights (DegenerusGameStorage): an entry's floor, and each box.
    ///      Budgets below are in these units, not in boxes.
    uint256 internal constant ENTRY_W = 15;
    uint256 internal constant BOX_W = 6;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
    }

    // =========================================================================
    // (1) per-box marginal inside one entry
    // =========================================================================

    function testPerBoxMarginalWithinOneEntry() public {
        uint256 snap = vm.snapshotState();

        uint256 gasOne = _measureOpen(1, "one_");
        vm.revertToState(snap);
        uint256 gasMany = _measureOpen(MAX_BOXES, "many_");

        assertGt(gasMany, gasOne, "non-vacuity: a 100-box entry costs more than a 1-box entry");
        uint256 perBox = (gasMany - gasOne) / (MAX_BOXES - 1);

        emit log_named_uint("open_gas_1_box", gasOne);
        emit log_named_uint("open_gas_100_boxes", gasMany);
        emit log_named_uint("per_box_marginal_gas", perBox);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);
    }

    // =========================================================================
    // (2) a maximum entry, opened in one call
    // =========================================================================

    function testMaxEntryFitsOneCall() public {
        uint256 gasUsed = _measureOpen(MAX_BOXES, "max_");

        emit log_named_uint("max_entry_boxes", MAX_BOXES);
        emit log_named_uint("max_entry_open_gas", gasUsed);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        assertLt(
            gasUsed + INTRINSIC_TX_GAS,
            MAINNET_BLOCK_GAS_LIMIT,
            "a maximum entry fits a mainnet block on its own"
        );
        assertLt(
            gasUsed + INTRINSIC_TX_GAS,
            EFFECTIVE_GAS_CEILING,
            "a maximum entry fits under the 16.7M ceiling on its own"
        );
    }

    // =========================================================================
    // (2b) the same entry in LARGE boxes
    // =========================================================================

    /// @notice The smalls measurement is the cheap end: at 0.01 ETH a box's spin branches stake
    ///         almost nothing, and some early-return outright. A large is 25x a ticket price, so
    ///         its spins actually run — this is the number the cap should be sized against.
    function testMaxEntryLargeBoxes() public {
        uint256 gasUsed = _measureOpen(MAX_BOXES << 16, "lg_"); // packed: large-tier count

        emit log_named_uint("max_entry_large_boxes", MAX_BOXES);
        emit log_named_uint("max_entry_large_open_gas", gasUsed);

        assertLt(
            gasUsed + INTRINSIC_TX_GAS,
            EFFECTIVE_GAS_CEILING,
            "a maximum entry of LARGE boxes fits under the 16.7M ceiling on its own"
        );
    }

    /// @notice Saturated boon chance and the largest user-controlled loop, without relying on
    ///         the preset price curve. Each custom box is 10 ETH and the order holds 100 boxes.
    function testMaxEntrySaturatedCustomBoxes() public {
        uint256 customScaled = 10 ether / 1e12;
        uint256 order = (MAX_BOXES << 24) | (customScaled << 32);
        uint256 gasUsed = _measureOpen(order, "sat_");

        emit log_named_uint("max_entry_saturated_custom_boxes", MAX_BOXES);
        emit log_named_uint("max_entry_saturated_custom_open_gas", gasUsed);
        assertLt(gasUsed + INTRINSIC_TX_GAS, EFFECTIVE_GAS_CEILING, "saturated custom entry fits");
    }

    /// @notice Twenty-five boxes in every user tier. This is the maximum-count mixed shape and
    ///         exercises four independent boon budgets/delegatecalls before tier batching.
    function testMaxEntryMixedTiers() public {
        uint256 customScaled = 10 ether / 1e12;
        uint256 count = 25;
        uint256 order = count |
            (count << 8) |
            (count << 16) |
            (count << 24) |
            (customScaled << 32);
        uint256 gasUsed = _measureOpen(order, "mix_");

        emit log_named_uint("max_entry_mixed_tier_boxes", MAX_BOXES);
        emit log_named_uint("max_entry_mixed_tier_open_gas", gasUsed);
        assertLt(gasUsed + INTRINSIC_TX_GAS, EFFECTIVE_GAS_CEILING, "mixed-tier entry fits");
    }

    // =========================================================================
    // (3) one player's N boxes against N players' one box each
    // =========================================================================

    function testOnePlayerCheaperThanManyPlayers() public {
        uint256 n = 20;
        uint256 snap = vm.snapshotState();

        uint256 gasOnePlayer = _measureOpen(n, "single_");
        vm.revertToState(snap);
        uint256 gasManyPlayers = _measureOpenSpread(n, "spread_");

        emit log_named_uint("boxes", n);
        emit log_named_uint("one_player_n_boxes_gas", gasOnePlayer);
        emit log_named_uint("n_players_one_box_each_gas", gasManyPlayers);
        emit log_named_uint("ratio_pct", (gasManyPlayers * 100) / gasOnePlayer);

        assertLt(
            gasOnePlayer,
            gasManyPlayers,
            "N boxes for one player cost less than N boxes across N players"
        );
    }

    // =========================================================================
    // (4) a full-budget sweep of the EXPENSIVE shape
    // =========================================================================

    /// @notice The budget's worst case is not one wide entry — it is many NARROW ones, because
    ///         every entry pays its own cold per-player settlement however few boxes it holds.
    ///         OPEN_WEIGHT_BUDGET is 1920 units and a one-box entry costs 15 + 6 = 21 units,
    ///         so a full budget is about 90 such entries after cursor overhead. This queues more
    ///         than that and spends the whole budget in one call.
    function testFullBudgetSweepOfNarrowEntries() public {
        uint256 queued = 150; // > the ~90 a full budget affords, so the budget binds
        uint256 price = _ticketPrice();
        for (uint256 i; i < queued; ++i) {
            address b = makeAddr(string(abi.encodePacked("narrow_", _u(i))));
            vm.deal(b, price + 1 ether);
            vm.prank(b);
            game.purchase{value: price}(b, 0, 1, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        _landWord(uint256(keccak256("narrow_w")) | 1);
        _cool();

        vm.prank(makeAddr("narrow_keeper"));
        uint256 before = gasleft();
        // openBoxes converts its remainder into walk units at ENTRY_W, so passing
        // OPEN_WEIGHT_BUDGET / ENTRY_W reproduces the rewarded crank's exact human budget
        // (mineFlip hands openHumanBoxes OPEN_WEIGHT_BUDGET walk units directly).
        uint256 opened = game.openBoxes(OPEN_WEIGHT_BUDGET / ENTRY_W);
        uint256 gasUsed = before - gasleft();

        emit log_named_uint("narrow_entries_queued", queued);
        emit log_named_uint("narrow_entries_opened", opened);
        emit log_named_uint("full_budget_sweep_gas", gasUsed);

        assertGt(opened, 0, "non-vacuity: the sweep opened real entries");
        assertLt(opened, queued, "the budget binds: some queued entries wait for the next call");
        assertLt(
            gasUsed + INTRINSIC_TX_GAS,
            EFFECTIVE_GAS_CEILING,
            "a full-budget sweep of the expensive shape stays under the 16.7M ceiling"
        );
    }

    // =========================================================================
    // Fixture
    // =========================================================================

    /// @dev One buyer takes a packed order; the day cycles so the index's word lands; then the
    ///      whole entry opens in one measured call.
    function _measureOpen(uint256 order, string memory prefix) internal returns (uint256 gasUsed) {
        address buyer = makeAddr(string(abi.encodePacked(prefix, "buyer")));
        uint256 small = order & 0xFF;
        uint256 medium = (order >> 8) & 0xFF;
        uint256 large = (order >> 16) & 0xFF;
        uint256 custom = (order >> 24) & 0xFF;
        uint256 customWei = ((order >> 32) & ((uint256(1) << 48) - 1)) * 1e12;
        uint256 boxes = small + medium + large + custom;
        uint256 cost = _ticketPrice() *
            (small + 5 * medium + 25 * large) +
            custom * customWei;
        vm.deal(buyer, cost + 10 ether);
        vm.prank(buyer);
        game.purchase{value: cost}(
            buyer,
            0,
            order,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );

        _landWord(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);

        _cool();
        address keeper = makeAddr(string(abi.encodePacked(prefix, "keeper")));
        vm.prank(keeper);
        uint256 before = gasleft();
        // The sweep, not the manual shell: it needs no index, and with only the two permanent
        // deploy subscribers in the ring its afking leg is a fixed O(1) gate. Budget is in WALK
        // UNITS — one entry plus its boxes, with slack for the index header.
        uint256 opened = game.openBoxes(ENTRY_W + boxes * BOX_W + 10);
        gasUsed = before - gasleft();
        assertEq(opened, boxes, "non-vacuity: every queued box actually opened");
    }

    /// @dev `n` distinct buyers each take a single small, then all open in one measured sweep.
    function _measureOpenSpread(uint256 n, string memory prefix) internal returns (uint256 gasUsed) {
        uint256 price = _ticketPrice();
        for (uint256 i; i < n; ++i) {
            address b = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            vm.deal(b, price + 1 ether);
            vm.prank(b);
            game.purchase{value: price}(b, 0, 1, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        _landWord(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);

        _cool();
        address keeper = makeAddr(string(abi.encodePacked(prefix, "keeper")));
        vm.prank(keeper);
        uint256 before = gasleft();
        // n separate entries, each one entry-weight plus its single box's weight.
        uint256 opened = game.openBoxes(n * (ENTRY_W + BOX_W) + 20);
        gasUsed = before - gasleft();
        assertEq(opened, n, "non-vacuity: every player's box actually opened");
    }

    /// @dev Whole-ticket price at the active purchase level — a small box is exactly one of
    ///      these, so it is also the per-box cost of a small order.
    function _ticketPrice() internal view returns (uint256 priceWei) {
        (, , , , priceWei) = game.purchaseInfo();
    }

    /// @dev Drive a new day so the pending index finalizes and its word lands.
    function _landWord(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
        _settleClean(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    /// @dev Re-cool every account the measured path touches, so the bracketed measurement pays
    ///      COLD access costs — what a fresh keeper transaction pays on mainnet. The fixture's
    ///      own setup runs in the same test tx and would otherwise pre-warm everything.
    function _cool() internal {
        vm.cool(address(game));
        vm.cool(ContractAddresses.COINFLIP);
        vm.cool(ContractAddresses.COIN);
        vm.cool(ContractAddresses.QUESTS);
        vm.cool(ContractAddresses.WWXRP);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v != 0) {
            b = abi.encodePacked(bytes1(uint8(48 + (v % 10))), b);
            v /= 10;
        }
        return string(b);
    }
}
