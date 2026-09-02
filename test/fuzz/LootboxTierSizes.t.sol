// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {C1Viewer} from "../repro/C1BoxAutoOpen.t.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Reads a stored order's rate lanes and the EV multiplier its score maps to, through the
///      game's own storage layout and curve.
contract RateViewer is DegenerusGame {
    function rates(uint48 index, address who)
        external
        view
        returns (uint256 level, uint256 evBps, uint256 boostBps, uint256 adjBps, uint256 distressBps)
    {
        uint256 w = lootboxOrder[index][who];
        level = (w >> LB_LEVEL_SHIFT) & LB_LEVEL_MASK;
        evBps = _lootboxEvMultiplierFromScore((w >> LB_SCORE_SHIFT) & LB_SCORE_MASK);
        boostBps = (w >> LB_BOOST_SHIFT) & LB_BPS_MASK;
        adjBps = (w >> LB_ADJ_SHIFT) & LB_BPS_MASK;
        distressBps = (w >> LB_DISTRESS_SHIFT) & LB_BPS_MASK;
    }
}

/// @title LootboxTierSizes -- a medium box is five ticket prices and a large box twenty-five
/// @notice The box order stores tier COUNTS; the open multiplies the level's ticket price by the
///         tier's multiple (1x / 5x / 25x) to size each roll. Mutation v78 rewrote the medium
///         size `price * 5` as `price - 5` in the open walk and no foundry oracle noticed: the
///         tier multiples were asserted nowhere. This buys one box of each tier in one order,
///         lands the word, auto-opens, and reads the three sizes back off `LootBoxOpened`.
contract LootboxTierSizes is DeployProtocol {
    address internal actor;

    bytes32 internal constant OPENED =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _word(uint48 index) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).rngWordFor(index);
        vm.etch(address(game), real);
    }

    /// @dev Point the permissionless open walk at `index` (cursor 0), as the auto-open repro does.
    function _parkBoxFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(56));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 m = (uint256(1) << 48) - 1;
        packed &= ~(m << (7 * 8));
        packed &= ~(m << (13 * 8));
        packed |= (uint256(index) & m) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.advanceGame() {} catch {}
            if (game.rngLocked()) break;
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("daily", i))) | 1) {} catch {}
                }
            }
        }
        for (uint256 i; i < 10 && game.rngLocked(); i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("dailyword", i))) | 1) {} catch {}
                }
            }
            vm.prank(actor);
            try game.advanceGame() {} catch {}
        }
    }

    function test_tiersOpenAtOneFiveAndTwentyFivePrices() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();

        // One of each tier, plus a one-ETH custom box so the pending ETH clears the mid-day
        // request threshold (the tiers alone are 31 ticket prices).
        uint256 order = BoxOrderLib.boOrder(1, 1, 1, 1, 1 ether);
        uint256 nominal = 31 * priceWei + 1 ether;
        vm.prank(actor);
        game.purchase{value: nominal + 1 ether}(actor, 400, order, bytes32(0), MintPaymentKind.DirectEth, false);

        vm.prank(actor);
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // A box that draws the ETH or WWXRP spin reports through the spin contracts instead of
        // `LootBoxOpened`, so search the word for a draw where all four boxes open plainly. The
        // word only moves the spin lottery and the ticket targets; the SIZES are the order's.
        uint256[4] memory sizes;
        bool found;
        for (uint256 w = 1; w <= 64 && !found; w++) {
            uint256 snap = vm.snapshotState();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("tier_word", w))) | 1);
            assertGt(_word(N), 0, "the word landed at the order's index");
            _parkBoxFrontier(N);
            vm.recordLogs();
            vm.prank(actor);
            uint256 opened = game.openBoxes(50);
            assertGt(opened, 0, "the walk opened the order");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 n;
            for (uint256 i; i < logs.length; i++) {
                if (logs[i].topics[0] != OPENED || logs[i].emitter != address(game)) continue;
                if (address(uint160(uint256(logs[i].topics[1]))) != actor) continue;
                (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                if (n < 4) sizes[n] = amount;
                n++;
            }
            assertLe(n, 4, "never more than the four boxes ordered");
            if (n == 4) found = true;
            else vm.revertToState(snap);
        }
        assertTrue(found, "some word opens all four boxes without a spin");
        // Sort; the custom (one ETH) is the largest, the three tiers sit below it.
        for (uint256 a; a < 4; a++) {
            for (uint256 b = a + 1; b < 4; b++) {
                if (sizes[b] < sizes[a]) (sizes[a], sizes[b]) = (sizes[b], sizes[a]);
            }
        }
        // `amount` is the box's EV-scaled figure: the wallet's EV, boost and adjustment rates ride
        // every tier alike, so the four figures keep the order's size ratios to within flooring.
        assertGt(sizes[0], 0, "the small box opened with a size");
        assertApproxEqAbs(sizes[1], 5 * sizes[0], 8, "the medium box is five small boxes");
        assertApproxEqAbs(sizes[2], 25 * sizes[0], 32, "the large box is twenty-five small boxes");
        assertApproxEqAbs(sizes[3], (1 ether / priceWei) * sizes[0], 1 ether / priceWei + 1, "the custom box is its own size in small boxes");
    }

    /// @dev The figure every plainly-opened box of `who` at `index` reported (all boxes of one
    ///      single-tier order share it); zero if every box drew a spin.
    function _rates(uint48 index, address who)
        internal
        returns (uint256 level, uint256 evBps, uint256 boostBps, uint256 adjBps)
    {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(RateViewer).runtimeCode);
        (level, evBps, boostBps, adjBps,) = RateViewer(payable(address(game))).rates(index, who);
        vm.etch(address(game), real);
    }

    /// @dev The figure `_rollTier` reports for a box of `size`: the boosted size, EV-scaled below
    ///      neutral, or the adjusted part EV-scaled plus the rest above it.
    function _expected(uint256 size, uint256 evBps, uint256 boostBps, uint256 adjBps) internal pure returns (uint256) {
        uint256 boosted = size + (size * boostBps) / 10_000;
        uint256 adjWei = (size * adjBps) / 10_000;
        return evBps <= 10_000 ? (boosted * evBps) / 10_000 : (adjWei * evBps) / 10_000 + (boosted - adjWei);
    }

    function _openedFigure(Vm.Log[] memory logs, address who, uint48 index) internal pure returns (uint256 fig) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != OPENED) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            if (uint48(uint256(logs[i].topics[2])) != index) continue;
            (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
            if (fig == 0) fig = amount;
            else require(fig == amount, "one single-tier order, one figure");
        }
    }

    /// @notice A one-tier order takes the lean immediate path (no five-lane batch). Three fresh
    ///         wallets buy three boxes of one tier each at the same index; the daily word lands,
    ///         the walk opens all nine, and the three per-tier figures keep 1 : 5 : 25.
    function test_singleTierOrdersOpenAtTheirMultiples() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: a fresh day");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();

        address[3] memory who = [makeAddr("smalls"), makeAddr("mediums"), makeAddr("larges")];
        uint256[3] memory orders = [BoxOrderLib.boOrder(3, 0, 0, 0, 0), BoxOrderLib.boOrder(0, 3, 0, 0, 0), BoxOrderLib.boOrder(0, 0, 3, 0, 0)];
        uint256[3] memory mults = [uint256(1), 5, 25];
        for (uint256 t; t < 3; t++) {
            vm.deal(who[t], 100 ether);
            vm.prank(who[t]);
            game.purchase{value: 3 * mults[t] * priceWei + 1 ether}(who[t], 400, orders[t], bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // The stored rate lanes, read before the open zeroes the orders: the exact figure each
        // tier must report follows from them and the tier's size alone.
        uint256[3] memory expected;
        for (uint256 t; t < 3; t++) {
            (uint256 lvl, uint256 ev, uint256 boost, uint256 adj) = _rates(N, who[t]);
            expected[t] = _expected(mults[t] * PriceLookupLib.priceForLevel(uint24(lvl)), ev, boost, adj);
        }

        // The daily word finalizes the index and lands the boxes' word without a mid-day request.
        _driveDailyCycleOnce();
        assertGt(_word(N), 0, "the daily word landed at the orders' index");
        _parkBoxFrontier(N);
        vm.recordLogs();
        vm.prank(actor);
        uint256 opened = game.openBoxes(100);
        assertGt(opened, 0, "the walk opened the orders");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[3] memory fig;
        for (uint256 t; t < 3; t++) {
            fig[t] = _openedFigure(logs, who[t], N);
            assertGt(fig[t], 0, "at least one box of the tier opened plainly");
            assertEq(fig[t], expected[t], "a box reports exactly its boosted, EV-scaled size");
        }
        assertApproxEqAbs(fig[1], 5 * fig[0], 8, "a medium box is five small boxes on the immediate path");
        assertApproxEqAbs(fig[2], 25 * fig[0], 32, "a large box is twenty-five small boxes on the immediate path");
    }
}
