// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title MiddayFrozenPoolLatch — a mid-day request that freezes a future pool must release.
///
/// @notice The first fresh request after the purchase goal freezes the next level's
///         far-future pool. A mid-day request gives that pool an isolated work latch,
///         retaining the ordinary current-level write buffer for a later word. The mid-day
///         branch of mineFlip re-runs the ticket worker only while the sweep probe still
///         finds work (or a foil bucket is pending), and only a FINISHED return releases
///         ticketsFullyProcessed and the latch. The batch that empties the frozen pool must
///         therefore report finished itself: once the pool is empty nothing re-enters the
///         worker, mineFlip reverts NoWork, and a stuck latch would refuse every
///         further mid-day request (RngNotReady) until the next day's advance.
///
///         Seen live on day 33 / level 12 (blocks 47223421..47223981).
///
///         Suite shape:
///           A  advance   — drained by mineFlip: the latch releases the same day and a
///                          second mid-day request is accepted.
///           B  router    — drained through the mineFlip router only: same outcome.
///           C  foil      — a real foil purchase stays in the foil write cohort while the
///                          isolated future pool drains, and a later mid-day word never
///                          moves it; the next daily commitment generates the foil.
///           D  craps     — an ordinary request while a craps window waits on the write buffer
///                          (which waives the lootbox pending-value gates, so no lootbox is
///                          needed) freezes and latches the same way; the latch releases the
///                          same day.
contract MiddayFrozenPoolLatch is DeployProtocol {
    uint48 private crapsWindowBuffer;
    address private buyer = address(0xB4A1);
    address private crank = address(0xC4A9);
    address private lateBuyer = address(0x1A7E);

    uint256 private simTime;
    uint24 private currentKey;
    uint256 private currentOwed;

    uint24 private constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    bytes4 private constant SEL_NOT_TIME_YET = bytes4(keccak256("NoWork()"));
    bytes4 private constant SEL_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 200_000 ether);
        vm.deal(crank, 10 ether);
        vm.deal(lateBuyer, 100 ether);
        // Clear MIN_LINK_FOR_LOOTBOX_RNG. The admin ctor creates subId 1.
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // A. Drained by mineFlip
    // ---------------------------------------------------------------------

    function testMiddayLatchReleasesAfterFrozenPoolDrainsViaAdvance() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayAfterTarget(false);

        _fulfillPending();
        bytes4 last = _crankAdvance(200);

        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // B. Drained through the mineFlip router only
    // ---------------------------------------------------------------------

    function testMiddayLatchReleasesAfterFrozenPoolDrainsViaMineFlip() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayAfterTarget(false);

        _fulfillPending();
        for (uint256 i = 0; i < 200; i++) {
            if (!game.advanceDue()) break;
            vm.prank(crank);
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) break;
        }
        // The router only advances while advanceDue() says so; whatever it left must be
        // the released state, with mineFlip itself refusing only as "nothing to do".
        bytes4 last = _crankAdvance(1);

        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // C. Foil work preserves the isolated future-pool boundary
    // ---------------------------------------------------------------------

    function testMiddayLatchWaitsForFoilThenReleasesSameDay() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayAfterTarget(false, true);
        assertGt(_foilWriteCount(), 0, "reachability: the paid foil awaits a normal commitment");
        assertFalse(_foilResolved(), "the future-pool word cannot resolve the ordinary write foil");

        _fulfillPending();
        bytes4 last = _crankAdvance(200);

        assertGt(_foilWriteCount(), 0, "isolated future-pool completion preserves the paid foil");
        assertFalse(_foilResolved(), "the isolated pool never borrows the foil's future word");
        _assertReleased(ffKey, day, last);
        // Foil packs ride the daily request only (foilWriteSlot): the second mid-day word that
        // _assertReleased drained never moves the foil cohort, so the paid foil still waits.
        assertGt(_foilWriteCount(), 0, "a mid-day request never moves the paid foil");
        assertFalse(_foilResolved(), "a mid-day word never generates the paid foil");
        // The next daily request freezes the foil cohort and its word generates the pack.
        simTime = vm.getBlockTimestamp() + 1 days;
        vm.warp(simTime);
        for (uint256 i; i < 400 && !_foilResolved(); ++i) {
            _fulfillPending();
            (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) assertTrue(_selector(ret) != SEL_NOT_TIME_YET, "harness: the crank idled before the foil generated");
        }
        assertTrue(_foilResolved(), "the next daily commitment must finish the paid foil");
    }

    // ---------------------------------------------------------------------
    // D. The craps table's request, no lootbox pending
    // ---------------------------------------------------------------------

    function testMiddayLatchReleasesAfterPendingCrapsWindowRequest() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayAfterTarget(true);

        _fulfillPending();
        // The window's cohort drains on the delivered word: clear its pending bit as the table does.
        vm.prank(ContractAddresses.CRAPS);
        game.setCrapsRngPending(crapsWindowBuffer, false);
        bytes4 last = _crankAdvance(200);

        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // Drive
    // ---------------------------------------------------------------------

    /// @dev Reach a sealed ordinary purchase day, then cross the target. A target already
    ///      met at the preceding daily request would have minted this pool before the seal.
    ///      The next mid-day request is therefore the first fresh word after this crossing.
    function _latchMiddayAfterTarget(bool viaCraps) internal returns (uint24 ffKey, uint24 day) {
        return _latchMiddayAfterTarget(viaCraps, false);
    }

    function _latchMiddayAfterTarget(bool viaCraps, bool withFoil) internal returns (uint24 ffKey, uint24 day) {
        uint24 programLevel = _driveToSealedPurchaseDay();
        _finishReadConsumers();
        ffKey = (programLevel + 2) | TICKET_FAR_FUTURE_BIT;
        assertGt(_queueLen(ffKey), 0, "reachability: the frozen next-level pool must hold entries");
        assertTrue(_ticketsFullyProcessed(), "reachability: the sealed day leaves the read slot drained");

        _seedNextPrizePool(51 ether);
        _buyTickets();
        bool before = _ticketWriteSlot();
        currentKey = (programLevel + 1) | (before ? TICKET_SLOT_BIT : 0);
        currentOwed = uint32(TicketQueueStorage.owed(address(game), currentKey, buyer) >> 8);
        assertGt(currentOwed, 0, "reachability: current tickets await their own commitment");
        if (withFoil) {
            (,,,, uint256 foilPrice) = game.purchaseInfo();
            vm.prank(buyer);
            game.purchase{value: foilPrice * 10}(buyer, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        }
        if (viaCraps) {
            // A shut craps window waiting on the write buffer; an ordinary caller requests.
            crapsWindowBuffer = uint48(RecyclingState.writeBuffer(address(game)));
            vm.prank(ContractAddresses.CRAPS);
            game.setCrapsRngPending(crapsWindowBuffer, true);
            uint256 priorReq = mockVRF.lastRequestId();
            vm.prank(crank);
            game.mineFlip();
            assertGt(mockVRF.lastRequestId(), priorReq, "mineFlip issued the mid-day request");
        } else {
            _middayRequest();
        }
        assertEq(_ticketWriteSlot(), before, "the early future-pool request preserves current writes");
        assertEq(_midDayLatch(), 2, "reachability: the mid-day request must isolate the future pool");
        (,,,, uint256 price) = game.purchaseInfo();
        vm.prank(lateBuyer);
        game.purchase{value: price * 10}(lateBuyer, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        day = game.currentDayView();
    }

    function _assertReleased(uint24 ffKey, uint24 day, bytes4 lastRevert) internal {
        assertEq(game.currentDayView(), day, "harness: everything above ran within the request day");
        assertEq(_queueLen(ffKey), 0, "the mid-day drain must empty the frozen pool");
        assertEq(_midDayLatch(), 0, "the latch must release once the frozen pool is drained");
        assertTrue(_ticketsFullyProcessed(), "the read slot must be marked drained");
        assertFalse(game.advanceDue(), "nothing is left for a keeper");
        assertEq(lastRevert, SEL_NOT_TIME_YET, "mineFlip must refuse only as nothing-to-do");
        assertEq(uint32(TicketQueueStorage.owed(address(game), currentKey, buyer) >> 8), currentOwed,
            "the isolated drain preserves original current-level tickets");
        assertEq(uint32(TicketQueueStorage.owed(address(game), currentKey, lateBuyer) >> 8), 40,
            "post-request current tickets remain queued for a later word");

        // Ticket completion releases MID, but the whole word must finish before
        // another reservation. Drain its boxes/fields through their real effects.
        _finishReadConsumers();
        // A second eligible mid-day request the same day is then accepted.
        vm.prank(buyer);
        game.purchase{value: 2 ether}(buyer, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        // A stuck latch would hold the request back: it must be the engine's next action.
        vm.prank(crank);
        assertEq(game.minerAction(), 18, "a stuck latch refuses the next request");
        uint256 priorReq = mockVRF.lastRequestId();
        vm.prank(crank);
        (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("mineFlip()"));
        if (!ok) {
            assertTrue(_selector(ret) != SEL_RNG_NOT_READY, "a stuck latch refuses the next request");
            revert("a second mid-day request must be accepted");
        }
        assertGt(mockVRF.lastRequestId(), priorReq, "a second mid-day request must be accepted");
        _fulfillPending();
        assertEq(_crankAdvance(200), SEL_NOT_TIME_YET);
        assertFalse(game.jackpotPhase(), "the later commitment drains before the jackpot phase");
        assertEq(uint32(TicketQueueStorage.owed(address(game), currentKey, lateBuyer) >> 8), 0);
        uint24 currentLevel = currentKey & ~TICKET_SLOT_BIT;
        uint256 materialized;
        for (uint16 trait; trait < 256; ++trait) {
            (uint24 count,,) = game.getEntries(uint8(trait), currentLevel, 0, type(uint32).max, lateBuyer);
            materialized += count;
        }
        assertEq(materialized, 40, "every late purchase materializes before the current jackpot");
    }

    function _driveToSealedPurchaseDay() internal returns (uint24 programLevel) {
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "harness: gameOver before the seal");
            (uint24 lvl, bool inJackpot, bool lpd, bool rngL, ) = game.purchaseInfo();
            if (!inJackpot && !lpd && !rngL && _ticketsFullyProcessed()
                && game.rngWordForDay(game.currentDayView()) != 0 && game.rngComplete()
                && !game.advanceDue()) return lvl;
            _fulfillPending();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) {
                simTime += 1 days + 1;
                vm.warp(simTime);
                _buyTickets();
            }
        }
        revert("harness: did not reach a sealed ordinary purchase day");
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _crankAdvance(uint256 n) internal returns (bytes4 last) {
        for (uint256 i = 0; i < n; i++) {
            (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) return _selector(ret);
        }
    }

    function _selector(bytes memory ret) internal pure returns (bytes4 s) {
        if (ret.length >= 4) {
            assembly {
                s := mload(add(ret, 32))
            }
        }
    }

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId)));
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _buyTickets() internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        vm.prank(buyer);
        game.purchase{value: (priceWei * 4000) / 400}(buyer, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _middayRequest() internal {
        vm.prank(buyer);
        game.purchase{value: 2 ether}(buyer, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 priorReq = mockVRF.lastRequestId();
        vm.prank(crank);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
        require(ok && mockVRF.lastRequestId() > priorReq, "harness: mineFlip must issue the mid-day request");
    }

    /// @dev Seed the live next-pool half (slot 2, low 128 bits) up to targetNext.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(address(game), bytes32(uint256(2)), bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext));
    }

    // ---- storage probes ----

    function _slot0() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(0))));
    }

    /// @dev _ticketQueueLength(key) — the mapping sits at slot 12.
    function _queueLen(uint24 key) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(key), uint256(12)))));
    }

    /// @dev ticketWriteSlot — slot 0, byte 25.
    function _ticketWriteSlot() internal view returns (bool) {
        return ((_slot0() >> 200) & 1) != 0;
    }

    /// @dev ticketsFullyProcessed — slot 0, byte 24.
    function _ticketsFullyProcessed() internal view returns (bool) {
        return ((_slot0() >> 192) & 1) != 0;
    }

    /// @dev LR_MID_DAY — lootboxRngPacked (slot 33) bits [224, 232).
    function _midDayLatch() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(uint256(33)))) >> 224) & 0xFF;
    }

    /// @dev foilQueue (slot 61) keyed by foilWriteSlot (slot 62, byte 10), the foil cohort's
    ///      own toggle that only the daily request flips.
    function _foilWriteCount() internal view returns (uint256) {
        bool foilWriteSlot = ((uint256(vm.load(address(game), bytes32(uint256(62)))) >> 80) & 1) != 0;
        return uint256(vm.load(address(game),
            keccak256(abi.encode(uint256(foilWriteSlot ? 1 : 0), uint256(61)))));
    }

    function _foilResolved() internal view returns (bool) {
        uint24 lvl = currentKey & ~TICKET_SLOT_BIT;
        uint256 packed = uint256(vm.load(address(game),
            keccak256(abi.encode(buyer, keccak256(abi.encode(uint256(lvl & 3), uint256(58)))))));
        assertEq(uint24(packed >> 208), lvl, "foil record retains the purchased level");
        return packed >> 255 != 0;
    }

}
