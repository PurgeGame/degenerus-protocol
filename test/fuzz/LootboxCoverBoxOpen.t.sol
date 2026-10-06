// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title LootboxCoverBoxOpen -- a pass purchase's boxes open one per pass at their value
/// @notice A whale pass appends its own entry through `recordCoverBox`: one custom box worth
///         10% of a pass per pass bought; the entry's open resolves that many equal boxes, each
///         on the same EV scaling a bought custom box of the same size gets, plus whatever boost
///         the buyer earned. Mutation v78 deleted the pass box roll and nothing in foundry noticed.
///         A fresh wallet's 0.24 ETH custom box opened in the same buffer is the yardstick; the
///         word is searched until no box draws a spin, so a missing box can never hide behind
///         a spin.
contract LootboxCoverBoxOpen is DeployProtocol {
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
        game.mineFlip();
        reqId = mockVRF.lastRequestId();
        assertGt(reqId, prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
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
            try game.mineFlip() {} catch {}
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
            try game.mineFlip() {} catch {}
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
            game.mineFlip();
        }
        assertTrue(game.rngComplete(), "harness: the day's cohorts all completed");
    }

    /// @dev Count the opens for `who` under entry tag `tag`, with the smallest and largest amount opened.
    function _openedOf(Vm.Log[] memory logs, address who, uint48 tag)
        internal
        pure
        returns (uint256 n, uint256 lo, uint256 hi)
    {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != OPENED) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            if (uint48(uint256(logs[i].topics[2])) != tag) continue;
            (uint256 a,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
            if (n == 0 || a < lo) lo = a;
            if (a > hi) hi = a;
            n++;
        }
    }

    function test_whalePassCoverBoxesOpenOnePerPassAtTheirValue() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        uint48 N = _idx();

        // Five whale passes cover 1.2 ETH as five 0.24 ETH boxes; the yardstick is a fresh
        // wallet's 0.24 ETH custom box. Together they clear the mid-day request threshold.
        address whale = makeAddr("whaleBuyer");
        address plain = makeAddr("plainBuyer");
        vm.deal(whale, 20 ether);
        vm.deal(plain, 10 ether);
        uint256 whalePos = RecyclingState.boxCount(address(game), N);
        vm.prank(whale);
        game.purchaseWhalePass{value: 12 ether}(whale, 5, bytes32(0));
        uint256 plainPos = RecyclingState.boxCount(address(game), N);
        assertEq(plainPos, whalePos + 1, "the pass purchase is one entry");
        vm.prank(plain);
        game.purchase{value: 0.24 ether + 1 ether}(plain, 400, BoxOrderLib.boOrder(0, 0, 0, 1, 0.24 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 reqId = _mineMiddayRequest(actor);

        // A box that draws a spin reports through the spin contracts, so search the word for a
        // draw where both boxes open plainly; the word never changes what a box is WORTH.
        uint256 coverLo;
        uint256 coverHi;
        uint256 plainAmt;
        bool found;
        for (uint256 w = 1; w <= 64 && !found; w++) {
            uint256 snap = vm.snapshotState();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("cover_word", w))) | 1);
            // The engine publishes the word and opens the read cohort's entries as read consumers.
            vm.recordLogs();
            vm.prank(actor);
            game.mineFlip();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertGt(_word(N), 0, "the word landed for the entries' buffer");
            assertTrue(game.boxIndexComplete(N), "the walk opened the entries");
            (uint256 nCover, uint256 cLo, uint256 cHi) = _openedOf(logs, whale, _tag(N, whalePos));
            (uint256 nPlain, uint256 q,) = _openedOf(logs, plain, _tag(N, plainPos));
            assertLe(nCover, 5, "one box per pass, never more");
            assertLe(nPlain, 1, "one custom box was bought");
            if (nCover == 5 && nPlain == 1) {
                (coverLo, coverHi, plainAmt, found) = (cLo, cHi, q, true);
            } else {
                vm.revertToState(snap);
            }
        }
        assertTrue(found, "some word opens all six boxes plainly: the pass IS five boxes");
        assertGt(coverLo, 0, "every pass box carries its recorded value");
        assertGe(coverLo, plainAmt, "a 0.24 ETH pass box is worth at least a bought 0.24 ETH box");
        assertLe(coverHi, 3 * plainAmt, "and its boost cannot triple it");
    }
}
