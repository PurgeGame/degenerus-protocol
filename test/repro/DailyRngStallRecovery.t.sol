// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title DailyRngStallRecovery — the council-confirmed stall-path repros.
///
/// @notice (1) THE RETRY BEHIND THE GATE. The daily drain gate exists to clean the read
///         slot before a FRESH request, but a stalled DAILY request makes that circular:
///         the staged cohort cannot drain without the very word the stall is withholding,
///         and rngGate's 12-hour retry sits behind the gate. The gate therefore offers the
///         same single retry itself. Pinned here: blocked before the timeout, permissionless
///         re-request at 12 hours with tickets pending, once-only (the LSB latch), and the
///         retried word seals the day.
///
///         (2) THE SEALED DAY'S KEY. Daily processing keys the foil board and the traits
///         event by the day being SEALED (dailyIdx + 1), never the wall clock. The two
///         diverge when the word lands a day late: the advance clamps to the logical day,
///         and a wall-day key would strand that day's foil claims under the wrong entry.
///
///         (3) THE JACKPOT-PHASE RETRY AND THE COMMITTED COHORT. Jackpot-phase buys
///         route to the CURRENT level, which the drain gate's purchaseLevel probe does
///         not see, so a stalled jackpot-day retry reaches the rngGate sentinel. The
///         sentinel must not swap the ticket buffer again: the committed cohort would
///         flip back to the write slot, and past the phase transition no drain probes
///         that level's keys — the paid cohort would strand permanently.
contract DailyRngStallRecovery is DeployProtocol {
    bytes32 private constant DAILY_TRAITS_SIG =
        keccak256("DailyWinningTraits(uint24,uint32,uint32,uint24)");

    address private buyer = address(0xB4A1);
    address private keeper = address(0xC4A9);

    uint256 private simTime;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(keeper, 1 ether);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId)));
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _driveDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 j = 0; j < 200; j++) {
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
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

    /// @dev Open a new protocol day and fire ONLY the daily request — no fulfillment —
    ///      leaving the bought cohort staged in the read slot behind the stalled word.
    function _stallDailyRequest() internal returns (uint256 stalledReqId) {
        _buyTickets();
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        require(ok, "harness: the daily request advance must succeed");
        require(game.rngLocked(), "harness: the daily word must be in flight");
        stalledReqId = mockVRF.lastRequestId();
    }

    // ---------------------------------------------------------------------
    // (1) The retry behind the gate
    // ---------------------------------------------------------------------

    /// Before the timeout the gate blocks exactly as before: the cohort cannot drain
    /// wordless, and no retry is on offer yet.
    function testStalledDailyBlocksBeforeTheTimeout() public {
        vm.pauseGasMetering();
        _driveDay(); // settle the deploy-day advance
        _stallDailyRequest();

        vm.warp(simTime + 11 hours);
        vm.prank(keeper);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        assertFalse(ok, "the gate must still block inside the 12-hour window");
    }

    /// At 12 hours any caller re-requests THROUGH the drain gate — the state this retry
    /// exists for is precisely a nonempty staged cohort — and the fresh word seals the day.
    function testStalledDailyRetriesAt12hWithTicketsPending() public {
        vm.pauseGasMetering();
        _driveDay();
        uint24 sealedBefore = _dailyIdx();
        uint256 stalledReqId = _stallDailyRequest();

        vm.warp(simTime + 12 hours + 1);
        vm.prank(keeper);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        assertTrue(ok, "the 12-hour retry must be reachable with tickets pending");
        uint256 retryReqId = mockVRF.lastRequestId();
        assertGt(retryReqId, stalledReqId, "the retry must fire a fresh VRF request");

        // The retried word resolves the same staged cohort and the day seals.
        uint256 word = uint256(keccak256(abi.encode("retry", retryReqId)));
        mockVRF.fulfillRandomWords(retryReqId, word);
        for (uint256 j = 0; j < 200; j++) {
            (bool adv, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!adv) break;
        }
        assertGt(_dailyIdx(), sealedBefore, "the retried word must seal the day");
    }

    /// The retry is once-per-stall: the LSB latch spends it, and a second 12-hour wait
    /// offers nothing more (recovery is then the retried word or a coordinator swap).
    function testDailyRetryIsSingleShot() public {
        vm.pauseGasMetering();
        _driveDay();
        _stallDailyRequest();

        vm.warp(simTime + 12 hours + 1);
        vm.prank(keeper);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        assertTrue(ok, "harness: first retry must fire");

        vm.warp(simTime + 25 hours);
        vm.prank(keeper);
        (bool second, ) = address(game).call(
            abi.encodeWithSignature("advanceGame()")
        );
        assertFalse(second, "the single daily retry must not re-arm itself");
    }

    // ---------------------------------------------------------------------
    // (2) The sealed day's key
    // ---------------------------------------------------------------------

    /// A word landing a full day late still processes under the ADVANCE's clamp — logical
    /// day dailyIdx + 1 — and the traits event (and with it the foil board) must carry
    /// that sealed day, not the wall day the clock has since reached.
    function testLateWordKeysTraitsToTheSealedDay() public {
        vm.pauseGasMetering();
        _driveDay();
        _stallDailyRequest();
        uint24 sealedDay = _dailyIdx() + 1; // the day this stalled word will resolve

        // The wall clock crosses the next day break before the word arrives.
        simTime += 1 days + 1;
        vm.warp(simTime);
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(
            reqId,
            uint256(keccak256(abi.encode("late", reqId)))
        );

        vm.recordLogs();
        for (uint256 j = 0; j < 200; j++) {
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }

        bool sawTraits;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] != DAILY_TRAITS_SIG) continue;
            sawTraits = true;
            assertEq(
                uint256(logs[i].topics[1]),
                uint256(sealedDay),
                "the traits day must be the sealed day, not the wall day"
            );
        }
        assertTrue(sawTraits, "harness: late processing must still emit the daily traits");
    }

    // ---------------------------------------------------------------------
    // (3) The jackpot-phase retry and the committed cohort
    // ---------------------------------------------------------------------

    /// Jackpot-phase buys route to the CURRENT level, which the pre-RNG drain gate's
    /// purchaseLevel probe does not see — so a stalled jackpot-day retry reaches the
    /// rngGate sentinel instead of the gate's no-swap branch. The sentinel must not
    /// swap again: the original request already committed the cohort to the read slot,
    /// and a second swap flips it back to the write slot where jackpot processing
    /// never finds it.
    function testJackpotRetryKeepsTheCommittedCohortInTheReadSlot() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        uint24 L = _level();
        assertEq(_queueLen(L), 0, "harness: level queue A starts drained");
        assertEq(_queueLen(L | TICKET_SLOT_BIT), 0, "harness: level queue B starts drained");

        // Morning buy on a jackpot day routes to the CURRENT level's write slot.
        _buyTickets();
        bool parityBefore = _ticketWriteSlot();
        uint24 cohortKey = parityBefore ? L | TICKET_SLOT_BIT : L;
        assertGt(_queueLen(cohortKey), 0, "harness: cohort staged at the current level");

        // The day's request commits the cohort (swap: its key becomes the read slot),
        // then the word stalls.
        _stallNextDailyRequest();
        bool parityAfterRequest = _ticketWriteSlot();
        assertTrue(
            parityAfterRequest != parityBefore,
            "harness: the daily request must commit the cohort"
        );
        assertGt(
            _queueLen(cohortKey),
            0,
            "harness: the cohort now sits in the read slot"
        );

        // A ticket AWARD from the previous draw routes to the next level and would
        // satisfy the drain gate's purchaseLevel probe, sending the retry through the
        // gate's own no-swap branch. Model the award-less previous draw instead: with
        // read(L+1) empty the gate is skipped and the retry meets the rngGate sentinel
        // — the state under test.
        _clearQueue(_readKeyOf(L + 1));

        // 12h retry fires through the rngGate sentinel.
        simTime += 12 hours + 1;
        vm.warp(simTime);
        vm.prank(keeper);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        assertTrue(ok, "the 12-hour retry must fire in jackpot phase");
        assertEq(
            _ticketWriteSlot(),
            parityAfterRequest,
            "the retry must NOT swap the ticket buffer again"
        );
        assertGt(
            _queueLen(cohortKey),
            0,
            "the committed cohort must still sit in the read slot after the retry"
        );

        // Recovery: the retried word arrives and the day's processing drains the cohort.
        // (Only the cohort's read-slot key must empty — the daily jackpot legitimately
        // queues freshly AWARDED tickets into the opposite, write-slot key.)
        _fulfillPending();
        for (uint256 j = 0; j < 200; j++) {
            (bool adv, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!adv) break;
        }
        assertEq(_queueLen(cohortKey), 0, "the committed cohort must drain after recovery");
    }

    /// Sweep the WHOLE jackpot phase stalling and retrying every day's request. On the
    /// final jackpot day a double swap would park the paid cohort in the write slot,
    /// and the phase transition ends all probing of that level's keys — the cohort
    /// would strand permanently. After the transition both keys must be empty.
    function testFinalJackpotDayRetryDoesNotStrandTheCohort() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        uint24 L = _level();

        for (uint256 d = 0; d < 12 && game.jackpotPhase(); d++) {
            if (!game.rngLocked()) {
                _buyTickets();
            }
            _stallNextDailyRequest();
            _clearQueue(_readKeyOf(L + 1));
            simTime += 12 hours + 1;
            vm.warp(simTime);
            vm.prank(keeper);
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            assertTrue(ok, "the 12-hour retry must fire on every jackpot day");
            _fulfillPending();
            _drainUntilUnlocked();
        }

        assertFalse(game.jackpotPhase(), "harness: the phase must have transitioned");
        assertEq(
            _queueLen(L),
            0,
            "no paid cohort may strand at the finished level after the transition"
        );
        assertEq(
            _queueLen(L | TICKET_SLOT_BIT),
            0,
            "no paid cohort may strand at the finished level after the transition"
        );
    }

    // ---------------------------------------------------------------------
    // Jackpot-phase drive helpers
    // ---------------------------------------------------------------------

    /// @dev Drive purchase phase to target (seed + buy each stalled day) until
    ///      jackpotPhase() flips true.
    function _driveToJackpotPhase() internal {
        vm.deal(buyer, 10_000 ether);
        uint256 stalledDays;
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "harness: gameOver before jackpot phase");
            if (game.jackpotPhase()) return;
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) {
                simTime += 1 days + 1;
                vm.warp(simTime);
                // Cross the target only after 4+ purchase days so the phase latches
                // UNCOMPRESSED (day - psd <= 3 would set compressedJackpotFlag = 1)
                // and the jackpot runs its full multi-day span.
                unchecked {
                    ++stalledDays;
                }
                if (stalledDays >= 5) {
                    _seedNextPrizePool(49.9 ether);
                }
                _buyTickets();
            }
        }
        revert("harness: did not reach jackpot phase");
    }

    /// @dev Advance + fulfill within the current day until the RNG unlocks.
    function _drainUntilUnlocked() internal {
        for (uint256 i = 0; i < 200; i++) {
            if (!game.rngLocked()) return;
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) return;
        }
    }

    /// @dev Cross the day boundary and advance (never fulfilling) until the daily
    ///      request is in flight.
    function _stallNextDailyRequest() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 100; i++) {
            if (game.rngLocked()) return;
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
        require(game.rngLocked(), "harness: the daily request must be in flight");
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

    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev The read-slot key for a level under the current parity.
    function _readKeyOf(uint24 lvl) internal view returns (uint24) {
        return _ticketWriteSlot() ? lvl : lvl | TICKET_SLOT_BIT;
    }

    /// @dev Zero ticketQueue[key].length (models an award-less previous draw).
    function _clearQueue(uint24 key) internal {
        vm.store(
            address(game),
            keccak256(abi.encode(uint256(key), uint256(12))),
            bytes32(0)
        );
    }

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

    /// @dev ticketWriteSlot — slot 0, byte 25.
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 200) & 1) != 0;
    }

    /// @dev level — slot 0, bytes [12:15).
    function _level() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint24(s0 >> 96);
    }

    /// @dev Read dailyIdx from packed slot 0, bytes [3:6] (uint24, bit offset 24) —
    ///      the same attested decode VRFStallEdgeCases uses.
    function _dailyIdx() internal view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint24(s0 >> 24);
    }
}
