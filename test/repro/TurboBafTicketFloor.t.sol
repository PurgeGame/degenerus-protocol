// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title TurboBafTicketFloor — BAF award tickets rolled onto the floor level under turbo.
///
/// @notice `_awardJackpotTickets` rolls a winner's lootbox leg into ticket entries at a level
///         >= the passed floor, and the roll's 30% leg can land ON the floor exactly. In a
///         NORMAL x10 jackpot phase the floor `lvl` is safe: the entries queue into the write
///         slot, jackpot day 2's swap commits them, and the jackpot-phase drain names lvl. A
///         TURBO phase (compressedJackpotFlag >= 2) collapses all draws inside one RNG lock —
///         no further swap ever fires for the level (mid-day requests are locked out), and the
///         transition moves every later drain to lvl + 1 and beyond — so a floor-level award
///         queued during the collapse would sit at a key no drain ever names again.
///         `runBafJackpot` therefore routes the floor to lvl + 1 when the flag reads >= 2.
///
///         Drive: turbo-chain levels from genesis (seed the next pool over target every
///         purchase day, so each level collapses in one locked chain), deposit coinflips
///         daily so the buyer accrues BAF bracket-10 score (recordBafFlip on claim), and let
///         level 10's collapsed chain run its BAF. Reachability is asserted (turbo flag,
///         BAF resolved = epoch bump), then: no entries may remain at level 10's queue keys.
contract TurboBafTicketFloor is DeployProtocol {
    address private buyer = address(0xB4A1);
    address private crank = address(0xC4A9);

    uint256 private simTime;

    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev Clock offset folded into every fulfillment word (word = keccak(simTime, reqId)).
    ///      Chosen so the level-10 BAF's daily-flip bit lands 1 (a skipped BAF would leave
    ///      the floor path unexercised; the epoch reachability assert guards against that).
    uint256 private constant WORD_NUDGE = 1;

    function setUp() public {
        _deployProtocol();
        // Derive simTime arithmetically from ONE pre-warp timestamp read: a second
        // block.timestamp read after vm.warp can be CSE'd to the pre-warp value,
        // which would silently drop WORD_NUDGE from every fulfillment word.
        simTime = block.timestamp + 1 days + WORD_NUDGE;
        vm.warp(simTime);
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 500_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
        // FLIP stake for daily coinflip deposits (BAF score accrues on claimed wins).
        deal(address(coin), buyer, 5_000_000 ether, true);
    }

    function testTurboBafFloorAwardsDoNotStrandAtTheCollapsedLevel() public {
        vm.pauseGasMetering();
        _driveThroughLevelTenTurbo();

        // Reachability: the level-10 phase collapsed under turbo and its BAF resolved.
        assertGe(
            _compressedFlag(),
            2,
            "harness: level 10 must have collapsed under turbo (flag preserved as bonus latch)"
        );
        assertEq(
            _bafEpoch(10),
            1,
            "harness: the level-10 BAF must have resolved (epoch bump), not skipped"
        );

        // Let the next level's purchase days drain the lvl+1 queues normally.
        _runFullDay();
        _runFullDay();

        assertEq(
            _queueLen(10) + _queueLen(10 | TICKET_SLOT_BIT),
            0,
            "no BAF award entries may strand at the collapsed level's queue keys"
        );
        assertEq(
            _entriesOwed(10, buyer) + _entriesOwed(10 | TICKET_SLOT_BIT, buyer),
            0,
            "no owed entries may strand at the collapsed level"
        );
    }

    /// @notice The x0 evening latch (tier 2) keeps purchases open for the rest of the
    ///         sealed day, so a mid-day lootbox request can fire inside the window. Its
    ///         ticket-buffer swap must be refused: the next daily request is the
    ///         transition that collapses every draw under its lock, so a swapped cohort
    ///         crossed by a stall would sit write-side through the collapse — safe but
    ///         drawless. Drive: reach the level-10 latch day, fire a mid-day request
    ///         between two buys, assert no buffer flip, then cross WITHOUT fulfilling
    ///         (stall promotion) and run the collapse out. Nothing may strand at the
    ///         x0 level's keys.
    function testLatchDayMiddayRequestRefusesTheSwap() public {
        vm.pauseGasMetering();
        _driveToLevelTenLatchDay();

        _buyTickets();
        bool swapped = _middayRequest();
        assertFalse(
            swapped,
            "the latch-day mid-day request must not flip the ticket buffer"
        );
        assertTrue(
            _ticketsFullyProcessed(),
            "the read window stays drained: no latch, no pending mid-day batch"
        );
        _buyTickets();

        // Cross without fulfilling: the stalled request resolves via promotion or
        // orphan backfill, and the transition collapses the whole phase.
        _runPromotedCrossingDay();
        require(
            _level() >= 10,
            "harness: the level-10 transition must have run"
        );

        // Let the next level's purchase days drain any trailing keys.
        _runFullDay();
        _runFullDay();

        assertEq(
            _queueLen(10) + _queueLen(10 | TICKET_SLOT_BIT),
            0,
            "no cohort may strand at the collapsed x0 level's queue keys"
        );
        assertEq(
            _entriesOwed(10, buyer) + _entriesOwed(10 | TICKET_SLOT_BIT, buyer),
            0,
            "no owed entries may strand at the collapsed x0 level"
        );
    }

    // ---------------------------------------------------------------------
    // Drive
    // ---------------------------------------------------------------------

    /// @dev Turbo-chain from genesis until level 10's jackpot phase has completed: every
    ///      purchase day seeds the next pool over target (purchaseDays <= 1 arms turbo), buys
    ///      tickets into the building level, and deposits coinflips for BAF score.
    function _driveThroughLevelTenTurbo() internal {
        // Settle the deploy-warp day first: warping over an un-advanced day makes the
        // next chain gap-backfill (purchaseStartDay += gap), which pushes purchaseDays
        // past 1 and structurally disarms turbo.
        _settleToday();
        for (uint256 i = 0; i < 120; i++) {
            require(!game.gameOver(), "harness: gameOver before level 10");
            if (_level() >= 10 && !game.jackpotPhase()) return;
            if (!game.jackpotPhase()) {
                // Seed just over the ratcheting target (target(L+1) = levelPrizePool[L])
                // so every level arms turbo while the pools stay small enough that BAF
                // winner slices remain below the whale-pass threshold (ticket rolls).
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
                _tryCoinflipDeposit();
            }
            _runFullDay();
        }
        revert("harness: never completed level 10");
    }

    /// @dev Turbo-chain levels 1-9 (same seeding as above), stopping ON the day the
    ///      level-10 evening latch fires: lastPurchaseDay with the tier-2 flag, the
    ///      phase not yet entered — the x0 last-purchase window. purchaseInfo's lvl
    ///      runs one behind the level being sold, so the latch day reads lvl == 9.
    function _driveToLevelTenLatchDay() internal {
        _settleToday();
        for (uint256 i = 0; i < 120; i++) {
            require(
                !game.gameOver(),
                "harness: gameOver before the level-10 latch"
            );
            (uint24 lvl, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == 9) {
                require(
                    _compressedFlag() == 2,
                    "harness: the x0 latch must be tier 2"
                );
                return;
            }
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
                _tryCoinflipDeposit();
            }
            _runFullDay();
        }
        revert("harness: never reached the level-10 latch day");
    }

    /// @dev Run the advance chain to exhaustion on the current (already-warped) day.
    function _settleToday() internal {
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
    }

    /// @dev levelPrizePool[lvl] — the mapping sits at slot 23. levelPrizePool[L] is the
    ///      target the NEXT level's pool must exceed; 0 until first recorded.
    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 v = uint256(
            vm.load(
                address(game),
                keccak256(abi.encode(uint256(lvl), uint256(23)))
            )
        );
        return v < 50 ether ? 50 ether : v;
    }

    function _tryCoinflipDeposit() internal {
        vm.prank(buyer);
        try coinflip.depositCoinflip(buyer, 500 ether) {} catch {}
    }

    // ---------------------------------------------------------------------
    // Helpers (shared shape with MiddaySwapJackpotCohort)
    // ---------------------------------------------------------------------

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
        game.purchase{value: (priceWei * 4000) / 400}(
            buyer,
            4000,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
    }

    /// @dev Cross the day boundary and run the whole advance chain to the day seal.
    function _runFullDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
    }

    /// @dev Buy a lootbox and fire a mid-day lootbox request; report whether the
    ///      ticket buffer flipped (shared shape with MiddaySwapJackpotCohort).
    function _middayRequest() internal returns (bool swapped) {
        vm.prank(buyer);
        game.purchase{value: 2 ether}(
            buyer,
            0,
            BoxOrderLib.boCustom(2 ether),
            bytes32(0),
            MintPaymentKind.DirectEth,
            false
        );
        bool before = _ticketWriteSlot();
        vm.prank(crank);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature("requestLootboxRng()")
        );
        require(ok, "harness: requestLootboxRng must be callable");
        swapped = _ticketWriteSlot() != before;
    }

    /// @dev Cross the day boundary WITHOUT fulfilling the outstanding request, then
    ///      run the chain to exhaustion (fulfilling from the first loop entry on).
    function _runPromotedCrossingDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(
            abi.encodeWithSignature("advanceGame()")
        );
        ok; // the promotion entry may or may not revert once its stage breaks
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            (ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
    }

    /// @dev Seed the live next-pool half (slot 2, low 104 bits) up to targetNext.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 currentNext = packed & ((uint256(1) << 104) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(2)),
            bytes32((packed & ~((uint256(1) << 104) - 1)) | targetNext)
        );
    }

    // ---- storage probes ----

    /// @dev ticketQueue[key].length — the mapping sits at slot 12.
    function _queueLen(uint24 key) internal view returns (uint256) {
        return
            uint256(
                vm.load(
                    address(game),
                    keccak256(abi.encode(uint256(key), uint256(12)))
                )
            );
    }

    /// @dev entriesOwedPacked[key][player] >> 8 — the mapping sits at slot 13.
    function _entriesOwed(
        uint24 key,
        address player
    ) internal view returns (uint256) {
        bytes32 outer = keccak256(abi.encode(uint256(key), uint256(13)));
        return
            uint256(vm.load(address(game), keccak256(abi.encode(player, outer)))) >>
            8;
    }

    /// @dev level — slot 0, bytes [12:15).
    function _level() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint24(s0 >> 96);
    }

    /// @dev jackpotCounter — slot 0, byte 16.
    function _jackpotCounter() internal view returns (uint8) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(s0 >> 128);
    }

    /// @dev compressedJackpotFlag — slot 0, byte 23.
    function _compressedFlag() internal view returns (uint8) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(s0 >> 184);
    }

    /// @dev ticketsFullyProcessed — slot 0, byte 24 bit 0.
    function _ticketsFullyProcessed() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 192) & 1) != 0;
    }

    /// @dev Ticket write-slot parity bit — slot 0, byte 25 bit 0.
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 200) & 1) != 0;
    }

    /// @dev jackpots.bafLevel[lvl].epoch — the mapping sits at Jackpots slot 2; epoch is
    ///      the low uint64 of the packed struct slot.
    function _bafEpoch(uint24 lvl) internal view returns (uint64) {
        return
            uint64(
                uint256(
                    vm.load(
                        address(jackpots),
                        keccak256(abi.encode(uint256(lvl), uint256(2)))
                    )
                )
            );
    }
}
