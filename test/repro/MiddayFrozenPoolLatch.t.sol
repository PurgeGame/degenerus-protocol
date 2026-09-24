// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title MiddayFrozenPoolLatch — a mid-day request on a latched last purchase day must release.
///
/// @notice On a level's last purchase day (lastPurchaseDay latched, RNG unlocked) the next
///         level's far-future pool is frozen, and a mid-day `requestLootboxRng` makes it sweep
///         work (`_frozenPoolDue`: lastPurchaseDay AND the LR_MID_DAY latch). The mid-day
///         branch of advanceGame re-runs the ticket worker only while the sweep probe still
///         finds work (or a foil bucket is pending), and only a FINISHED return releases
///         ticketsFullyProcessed and the latch. The batch that empties the frozen pool must
///         therefore report finished itself: once the pool is empty nothing re-enters the
///         worker, advanceGame reverts NotTimeYet, and a stuck latch would refuse every
///         further mid-day request (MidDayActive) until the next day's advance.
///
///         Seen live on day 33 / level 12 (blocks 47223421..47223981).
///
///         Suite shape:
///           A  advance   — drained by advanceGame: the latch releases the same day and a
///                          second mid-day request is accepted.
///           B  router    — drained through the mineFlip router only: same outcome.
///           C  foil      — a sealed foil bucket is pending alongside the pool: the batch
///                          that empties the pool must not report finished, and the latch
///                          releases only after the foil drain, still the same day. Normal
///                          play drains a day's sealed bucket inside that day's advance chain,
///                          so the pending bucket is STAGED (an empty bucket for today, whose
///                          word is sealed): it isolates the finished-flag composition.
///           D  craps     — the craps table's request (exempt from the lootbox pending-value
///                          gates, so no lootbox is needed) swaps and latches the same way;
///                          the latch releases the same day.
contract MiddayFrozenPoolLatch is DeployProtocol {
    address private buyer = address(0xB4A1);
    address private crank = address(0xC4A9);

    uint256 private simTime;

    uint24 private constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;
    uint8 private constant JACKPOT_TURBO = 1;

    bytes4 private constant SEL_NOT_TIME_YET = bytes4(keccak256("NotTimeYet()"));
    bytes4 private constant SEL_MID_DAY_ACTIVE = bytes4(keccak256("MidDayActive()"));

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 200_000 ether);
        vm.deal(crank, 10 ether);
        // Clear MIN_LINK_FOR_LOOTBOX_RNG. The admin ctor creates subId 1.
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // A. Drained by advanceGame
    // ---------------------------------------------------------------------

    function testMiddayLatchReleasesAfterFrozenPoolDrainsViaAdvance() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayOnLastPurchaseDay(false);

        _fulfillPending();
        bytes4 last = _crankAdvance(200);

        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // B. Drained through the mineFlip router only
    // ---------------------------------------------------------------------

    function testMiddayLatchReleasesAfterFrozenPoolDrainsViaMineFlip() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayOnLastPurchaseDay(false);

        _fulfillPending();
        for (uint256 i = 0; i < 200; i++) {
            if (!game.advanceDue()) break;
            vm.prank(crank);
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) break;
        }
        // The router only advances while advanceDue() says so; whatever it left must be
        // the released state, with advanceGame itself refusing only as "nothing to do".
        bytes4 last = _crankAdvance(1);

        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // C. A sealed foil bucket pending alongside the frozen pool
    // ---------------------------------------------------------------------

    function testMiddayLatchWaitsForFoilThenReleasesSameDay() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayOnLastPurchaseDay(false);
        _stagePendingFoilBucket(day);
        assertTrue(_foilPending(), "reachability: a sealed foil bucket must be pending mid-day");

        _fulfillPending();
        bytes4 last = _crankAdvance(200);

        assertFalse(_foilPending(), "the mid-day drain must finish the foil bucket");
        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // D. The craps table's request, no lootbox pending
    // ---------------------------------------------------------------------

    function testMiddayLatchReleasesAfterCrapsRequest() public {
        vm.pauseGasMetering();
        (uint24 ffKey, uint24 day) = _latchMiddayOnLastPurchaseDay(true);

        _fulfillPending();
        bytes4 last = _crankAdvance(200);

        _assertReleased(ffKey, day, last);
    }

    // ---------------------------------------------------------------------
    // Drive
    // ---------------------------------------------------------------------

    /// @dev Reach a sealed, non-turbo last purchase day with the frozen pool non-empty, buy
    ///      tickets so the write side holds work, and fire the mid-day request that swaps
    ///      and latches — from a lootbox buyer's crank, or with `viaCraps` from the craps table
    ///      with no lootbox pending.
    function _latchMiddayOnLastPurchaseDay(bool viaCraps) internal returns (uint24 ffKey, uint24 day) {
        uint24 programLevel = _driveToSealedLastPurchaseDay();
        require(_jackpotFlags() & JACKPOT_TURBO == 0, "harness: the seal must be the standard (non-turbo) path");
        ffKey = (programLevel + 2) | TICKET_FAR_FUTURE_BIT;
        assertGt(_queueLen(ffKey), 0, "reachability: the frozen next-level pool must hold entries");
        assertTrue(_ticketsFullyProcessed(), "reachability: the sealed day leaves the read slot drained");

        _buyTickets();
        bool before = _ticketWriteSlot();
        if (viaCraps) {
            vm.prank(ContractAddresses.CRAPS);
            (bool ok, ) = address(game).call(abi.encodeWithSignature("requestLootboxRng()"));
            require(ok, "harness: the craps request must be callable");
        } else {
            _middayRequest();
        }
        assertTrue(_ticketWriteSlot() != before, "reachability: the mid-day request must swap");
        assertEq(_midDayLatch(), 1, "reachability: the mid-day request must set the latch");
        day = game.currentDayView();
    }

    function _assertReleased(uint24 ffKey, uint24 day, bytes4 lastRevert) internal {
        assertEq(game.currentDayView(), day, "harness: everything above ran within the request day");
        assertEq(_queueLen(ffKey), 0, "the mid-day drain must empty the frozen pool");
        assertEq(_midDayLatch(), 0, "the latch must release once the frozen pool is drained");
        assertTrue(_ticketsFullyProcessed(), "the read slot must be marked drained");
        assertFalse(game.advanceDue(), "nothing is left for a keeper");
        assertEq(lastRevert, SEL_NOT_TIME_YET, "advanceGame must refuse only as nothing-to-do");

        // A second mid-day request the same day is accepted (no MidDayActive).
        vm.prank(buyer);
        game.purchase{value: 2 ether}(buyer, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(crank);
        (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("requestLootboxRng()"));
        if (!ok) {
            assertTrue(_selector(ret) != SEL_MID_DAY_ACTIVE, "a stuck latch refuses the next request");
            revert("a second mid-day request must be accepted");
        }
    }

    function _driveToSealedLastPurchaseDay() internal returns (uint24 programLevel) {
        uint256 stalledDays;
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "harness: gameOver before the seal");
            (uint24 lvl, bool inJackpot, bool lpd, bool rngL, ) = game.purchaseInfo();
            if (!inJackpot && lpd && !rngL) return lvl;
            _fulfillPending();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) {
                simTime += 1 days + 1;
                vm.warp(simTime);
                unchecked {
                    ++stalledDays;
                }
                if (stalledDays >= 5) {
                    _seedNextPrizePool(49.9 ether);
                }
                _buyTickets();
            }
        }
        revert("harness: did not reach the last-purchase-day seal");
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _crankAdvance(uint256 n) internal returns (bytes4 last) {
        for (uint256 i = 0; i < n; i++) {
            (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("advanceGame()"));
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

    /// @dev Stage an empty foil bucket for `day` as the next to drain: foilCursor = 0 and
    ///      foilDrainDay = foilLastResolveDay = day (slot 62, bytes 0 / 4 / 7), with no buyers
    ///      in foilBuyers[day]. `day`'s word is sealed, so _foilDrainPending reads true and the
    ///      drain walks the bucket (resolving nobody) and moves past it.
    function _stagePendingFoilBucket(uint24 day) internal {
        require(uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(10))))) != 0, "harness: the day word must be sealed");
        uint256 s62 = uint256(vm.load(address(game), bytes32(uint256(62))));
        require(uint24(s62 >> 56) == 0, "harness: no foil may have been bought");
        s62 &= ~((uint256(1) << 80) - 1);
        s62 |= (uint256(day) << 56) | (uint256(day) << 32);
        vm.store(address(game), bytes32(uint256(62)), bytes32(s62));
    }

    function _middayRequest() internal {
        vm.prank(buyer);
        game.purchase{value: 2 ether}(buyer, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(crank);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("requestLootboxRng()"));
        require(ok, "harness: requestLootboxRng must be callable");
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

    /// @dev ticketQueue[key].length — the mapping sits at slot 12.
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

    /// @dev _foilDrainPending mirror: foilDrainDay / foilLastResolveDay (slot 62, bytes 4 and 7)
    ///      against rngWordByDay (slot 10).
    function _foilPending() internal view returns (bool) {
        uint256 s62 = uint256(vm.load(address(game), bytes32(uint256(62))));
        uint24 dd = uint24(s62 >> 32);
        uint24 last = uint24(s62 >> 56);
        if (last == 0 || dd > last) return false;
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(dd), uint256(10))))) != 0;
    }

    /// @dev jackpotFlags — slot 0, byte 23.
    function _jackpotFlags() internal view returns (uint8) {
        return uint8(_slot0() >> 184);
    }
}
