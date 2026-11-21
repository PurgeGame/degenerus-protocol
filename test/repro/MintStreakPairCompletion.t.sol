// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @notice The level mint streak records whenever the primary MINT_ETH quest completes, including
///         when a secondary quest completes in the same purchase. No storage writes: only
///         vm.deal, vm.prank, vm.warp and mock-VRF answers. The deploy day's slot 1 is the seeded
///         FOIL and the second day's is the fixed LOOTBOX (no prior word); a rolled
///         DEGENERETTE_ETH day is reached by answering a day's word with ordinary values until the
///         next day's request, which rolls from it, picks DEGENERETTE_ETH.
contract MintStreakPairCompletion is DeployProtocol {
    uint8 private constant QT_MINT_ETH = 1;
    uint8 private constant QT_LOOTBOX = 6;
    uint8 private constant QT_DEG_ETH = 7;

    uint256 private price;

    function setUp() public {
        _deployProtocol();
        (,,,, price) = game.purchaseInfo_g1027();
    }

    // ------------------------------------------------------------------ helpers

    function _streak(uint32 id) private view returns (uint256 lc, uint256 s) {
        uint256 w = game.mintPackedOfId_g5372(id);
        lc = (w >> BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) & BitPackingLib.MASK_24;
        s = (w >> BitPackingLib.LEVEL_STREAK_SHIFT) & BitPackingLib.MASK_24;
    }

    function _bet(address p) private {
        vm.deal(p, p.balance + 2 * price);
        vm.prank(p);
        game.betDegenerette{value: 2 * price}(0, 0, uint128(2 * price), 1, 9);
    }

    function _ticket(address p) private {
        vm.deal(p, p.balance + price);
        vm.prank(p);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// Two small boxes only (2x price, no tickets).
    function _boxesOnly(address p) private {
        vm.deal(p, p.balance + 2 * price);
        vm.prank(p);
        game.purchaseOrderFor{value: 2 * price}(0, 0, 2, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// Foil-only purchase: no ticket leg, no box leg -> straight to _buyFoilPack.
    function _foilOnly(address p) private {
        uint256 cost = 10 * price;
        vm.deal(p, p.balance + cost);
        vm.prank(p);
        game.purchaseOrderFor{value: cost}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
    }

    function _advanceDay(uint256 salt) private {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 50; ++i) {
            _mineAll(200);
            uint256 req = mockVRF.lastRequestId();
            if (req == 0) break;
            (, , bool fulfilled) = mockVRF.pendingRequests(req);
            if (fulfilled) break;
            mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("v9-01-second", salt, req))));
        }
        _mineAll(200);
        assertFalse(game.rngLocked(), "fixture: day settled");
    }

    function _slot1Today() private view returns (uint8 t1, bool today) {
        QuestInfo[2] memory q = quests.getActiveQuests();
        t1 = q[1].questType;
        today = q[1].day == uint24(game.currentDayView_g542950()) && q[0].day == q[1].day
            && q[0].questType == QT_MINT_ETH;
    }

    // ------------------------------------------------------------------ foil-only route

    /// Control: a foil-only buy on the deploy day completes the primary and the seeded FOIL
    /// secondary in one purchase and records 1/1.
    function test_foilOnly_control_records() public {
        address p = makeAddr("foilCtl");
        _foilOnly(p);
        uint32 id = game.walletIdOf_g3120(p);
        (bool d0, bool d1) = quests.questCompletionToday(id);
        assertTrue(d0, "primary done");
        assertTrue(d1, "seeded FOIL secondary done in the same purchase");
        (uint256 lc, uint256 s) = _streak(id);
        emit log_named_uint("foil control lastCompleted", lc);
        emit log_named_uint("foil control levelStreak", s);
        assertEq(lc, 1);
        assertEq(s, 1);
    }

    /// A bet first (no slot-1 progress on the FOIL day), then a foil-only buy completes both: recorded.
    function test_foilOnly_afterBet_records() public {
        address p = makeAddr("foilPair");
        _bet(p);
        _foilOnly(p);
        uint32 id = game.walletIdOf_g3120(p);
        (bool d0, bool d1) = quests.questCompletionToday(id);
        assertTrue(d0, "primary done");
        assertTrue(d1, "secondary pair-completed in the foil buy");
        (uint256 lc, uint256 s) = _streak(id);
        assertEq(lc, 1);
        assertEq(s, 1);
    }

    /// On a rolled DEGENERETTE_ETH day: bet first (secondary progress), then a ticket buy completes
    /// the primary and pair-completes the secondary: recorded.
    function test_ticket_afterBet_records() public {
        bool found;
        uint256 salt;
        for (salt = 200; salt < 260; ++salt) {
            uint256 snap = vm.snapshotState();
            _advanceDay(salt);
            _advanceDay(salt + 1000);
            (uint8 t1, bool today) = _slot1Today();
            if (today && t1 == QT_DEG_ETH) {
                found = true;
                break;
            }
            vm.revertToState(snap);
        }
        assertTrue(found, "a DEGENERETTE_ETH secondary rolled for some ordinary VRF word");
        emit log_named_uint("salt producing DEGENERETTE_ETH day", salt);
        (,,,, price) = game.purchaseInfo_g1027();
        address p = makeAddr("ticketPair");
        _bet(p);
        _ticket(p);
        uint32 id = game.walletIdOf_g3120(p);
        (bool d0, bool d1) = quests.questCompletionToday(id);
        assertTrue(d0, "primary done");
        assertTrue(d1, "secondary done");
        (uint256 lc, uint256 s) = _streak(id);
        assertEq(lc, 1);
        assertEq(s, 1);
    }

    // ------------------------------------------------------------------ the fixed LOOTBOX day

    /// The second day's slot 1 is the fixed LOOTBOX (its request has no prior word); a
    /// two-small-box buy (no tickets) then completes MINT_ETH and the LOOTBOX secondary in one
    /// call, and the level streak records like the ticket-only control on the same day.
    function test_rolledLootboxDay_boxesOnly_records() public {
        bool found;
        uint256 salt;
        for (salt = 100; salt < 140; ++salt) {
            uint256 snap = vm.snapshotState();
            _advanceDay(salt);
            (uint8 t1, bool today) = _slot1Today();
            if (today && t1 == QT_LOOTBOX) {
                found = true;
                break;
            }
            vm.revertToState(snap);
        }
        assertTrue(found, "a LOOTBOX secondary rolled for some ordinary VRF word");
        emit log_named_uint("salt producing LOOTBOX day", salt);
        (,,,, price) = game.purchaseInfo_g1027();

        address ctl = makeAddr("lbCtl");
        _ticket(ctl);
        uint32 cid = game.walletIdOf_g3120(ctl);
        (uint256 lc, uint256 s) = _streak(cid);
        assertEq(lc, 1, "control records");
        assertEq(s, 1);

        address p = makeAddr("lbPair");
        _boxesOnly(p);
        uint32 id = game.walletIdOf_g3120(p);
        (bool d0, bool d1) = quests.questCompletionToday(id);
        assertTrue(d0, "primary done by box spend");
        assertTrue(d1, "LOOTBOX secondary done in the same call");
        (lc, s) = _streak(id);
        assertEq(lc, 1, "recorded");
        assertEq(s, 1, "recorded");
    }
}
