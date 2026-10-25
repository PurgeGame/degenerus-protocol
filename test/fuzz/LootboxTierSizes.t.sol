// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {EvTaperRef} from "../helpers/EvTaperRef.sol";

/// @dev Reads a stored entry's rate lanes and the EV multiplier its score maps to, through the
///      game's own storage layout and curve.
contract RateViewer is DegenerusGame {
    function rates(uint48 buffer, uint256 position)
        external
        view
        returns (uint256 sizeWei, uint256 evBps, uint256 boostBps, uint256 adjBps, bool distress)
    {
        uint256 w = _boxEntryAt(buffer, position);
        sizeWei = BoxOrderLib.boSizeWei(w);
        evBps = _lootboxEvMultiplierFromScore(BoxOrderLib.boScore(w));
        boostBps = BoxOrderLib.boBoostBps(w);
        uint256 nominal = BoxOrderLib.boNominal(w);
        (uint256 eligible,) = EvTaperRef.eligible(_lootboxEvUsedFor(uint32(w), _activeTicketLevel()), nominal);
        adjBps = evBps > 10_000 && nominal != 0 ? eligible * 10_000 / nominal : 0;
        distress = w & LB_DISTRESS != 0;
    }
}

/// @title LootboxTierSizes -- a medium box is five ticket prices and a large box twenty-five
/// @notice A purchase picks ONE box type; the input decoder resolves a preset to the purchase
///         level's ticket price times its multiple (1x / 5x / 25x) and the entry stores that
///         per-box value. Mutation v78 rewrote the medium size `price * 5` as `price - 5` and no
///         foundry oracle noticed: the tier multiples were asserted nowhere. These buy each type
///         as its own purchase, read the stored per-box values, then open the boxes and read the
///         sizes back off `LootBoxOpened`.
contract LootboxTierSizes is DeployProtocol {
    address internal actor;

    bytes32 internal constant OPENED =
        keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _word(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev The `LootBoxOpened` tag of queued entry `position` in `buffer`.
    function _tag(uint48 buffer, uint256 position) internal pure returns (uint48) {
        return uint48((uint256(1) << 46) | (position << 1) | buffer);
    }

    /// @dev The mid-day request, issued by `caller`'s mineFlip as the engine's next action (the
    ///      only door to a mid-day word). Returns the fresh request's ID.
    function _mineMiddayRequest(address caller) internal returns (uint256 reqId) {
        uint256 prior = mockVRF.lastRequestId();
        vm.prank(caller);
        game.mineRun(0);
        reqId = mockVRF.lastRequestId();
        assertGt(reqId, prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
    }

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchaseOrderFor{value: priceWei}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.mineRun(0) {} catch {}
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
            try game.mineRun(0) {} catch {}
        }
        // A fresh request waits for every read consumer of the day's cohort to finish. A shut
        // craps window the day bound to the write buffer rides the next request, which the engine
        // makes as mid-day work; answer and drain it too, until the engine is idle.
        for (uint256 i; i < 20; i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("trailing", i))) | 1);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) break;
            if (!game.advanceDue()) continue; // a fresh request waits for its word
            vm.prank(actor);
            game.mineRun(0);
        }
        assertTrue(game.rngComplete(), "harness: the day's cohorts all completed");
    }

    /// @notice Each preset stores 1x / 5x / 25x the purchase level's ticket price per box and a
    ///         custom its exact units; the charged wei is quantity times that value.
    function test_kindsStoreOneFiveTwentyFivePricesPerBox() public {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint48 N = _idx();
        uint256[4] memory orders =
            [BoxOrderLib.boSmalls(2), BoxOrderLib.boMeds(2), BoxOrderLib.boLarges(2), BoxOrderLib.boCustoms(2, 1.234 ether)];
        uint256[4] memory perBox = [priceWei, 5 * priceWei, 25 * priceWei, 1.234 ether];
        for (uint256 t; t < 4; t++) {
            uint256 pos = RecyclingState.boxCount(address(game), N);
            uint256 balBefore = actor.balance;
            vm.prank(actor);
            game.purchaseOrderFor{value: 2 * perBox[t]}(0, 0, orders[t], bytes32(0), MintPaymentKind.DirectEth, false);
            assertEq(balBefore - actor.balance, 2 * perBox[t], "charged quantity x per-box value");
            uint256 entry = RecyclingState.boxEntry(address(game), N, pos);
            assertEq(BoxOrderLib.boCount(entry), 2, "quantity stored");
            assertEq(BoxOrderLib.boSizeWei(entry), perBox[t], "per-box value stored at purchase");
        }
    }

    /// @dev The rate lanes of queued entry `position` in `buffer`.
    function _rates(uint48 buffer, uint256 position)
        internal
        returns (uint256 sizeWei, uint256 evBps, uint256 boostBps, uint256 adjBps)
    {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(RateViewer).runtimeCode);
        (sizeWei, evBps, boostBps, adjBps,) = RateViewer(payable(address(game))).rates(buffer, position);
        vm.etch(address(game), real);
    }

    /// @dev The figure `_rollBoxes` reports for a box of `size`: the boosted size, EV-scaled below
    ///      neutral, or the adjusted part EV-scaled plus the rest above it.
    function _expected(uint256 size, uint256 evBps, uint256 boostBps, uint256 adjBps) internal pure returns (uint256) {
        uint256 boosted = size + (size * boostBps) / 10_000;
        uint256 adjWei = (size * adjBps) / 10_000;
        return evBps <= 10_000 ? (boosted * evBps) / 10_000 : (adjWei * evBps) / 10_000 + (boosted - adjWei);
    }

    /// @dev The figure every plainly-opened box of `who` under entry tag `tag` reported (all
    ///      boxes of one single-tier entry share it); zero if every box drew a spin.
    function _openedFigure(Vm.Log[] memory logs, address who, uint48 tag) internal view returns (uint256 fig) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != OPENED) continue;
            if (uint32(uint256(logs[i].topics[1])) != game.walletIdOf_g3120(who)) continue;
            if (uint48(uint256(logs[i].topics[2])) != tag) continue;
            (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
            if (fig == 0) fig = amount;
            else require(fig == amount, "one single-tier order, one figure");
        }
    }

    /// @notice Three fresh wallets buy three boxes of one tier each into the same buffer; the
    ///         daily word lands, the walk opens all nine, and the three per-tier figures keep
    ///         1 : 5 : 25.
    function test_singleTierOrdersOpenAtTheirMultiples() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: a fresh day");
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint48 N = _idx();

        address[3] memory who = [makeAddr("smalls"), makeAddr("mediums"), makeAddr("larges")];
        uint256[3] memory orders = [BoxOrderLib.boOrder(3, 0, 0, 0, 0), BoxOrderLib.boOrder(0, 3, 0, 0, 0), BoxOrderLib.boOrder(0, 0, 3, 0, 0)];
        uint256[3] memory mults = [uint256(1), 5, 25];
        uint256[3] memory pos;
        for (uint256 t; t < 3; t++) {
            vm.deal(who[t], 100 ether);
            pos[t] = RecyclingState.boxCount(address(game), N);
            vm.prank(who[t]);
            game.purchaseOrderFor{value: 3 * mults[t] * priceWei + 1 ether}(0, 400, orders[t], bytes32(0), MintPaymentKind.DirectEth, false);
            assertEq(RecyclingState.boxCount(address(game), N), pos[t] + 1, "each purchase appends one entry");
        }

        // The stored rate lanes: the exact figure each tier must report follows from them and
        // the tier's size alone.
        uint256[3] memory expected;
        for (uint256 t; t < 3; t++) {
            (uint256 size, uint256 ev, uint256 boost, uint256 adj) = _rates(N, pos[t]);
            assertEq(size, mults[t] * priceWei, "stored per-box value is the tier's multiple");
            expected[t] = _expected(size, ev, boost, adj);
        }

        // The daily word seals the buffer and lands the boxes' word without a mid-day request;
        // the same engine calls open the entries as read consumers of that word. Each entry's
        // own tag (buffer and position) on `LootBoxOpened` is the evidence the walk opened it.
        vm.recordLogs();
        _driveDailyCycleOnce();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[3] memory fig;
        for (uint256 t; t < 3; t++) {
            fig[t] = _openedFigure(logs, who[t], _tag(N, pos[t]));
            assertGt(fig[t], 0, "at least one box of the tier opened plainly");
            assertEq(fig[t], expected[t], "a box reports exactly its boosted, EV-scaled size");
        }
        assertApproxEqAbs(fig[1], 5 * fig[0], 8, "a medium box is five small boxes on the immediate path");
        assertApproxEqAbs(fig[2], 25 * fig[0], 32, "a large box is twenty-five small boxes on the immediate path");
    }
}
