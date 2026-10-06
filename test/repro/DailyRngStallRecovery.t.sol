// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DailyRngStallRecovery — the council-confirmed stall-path repros.
///
/// @notice (1) ADMIN TRANSPORT RETRY. A stalled daily request holds its committed read
///         cohort unchanged. Mining waits for every caller; the vault owner can ask Admin
///         for one replacement after20h, preserving the original timeout, day and buffers.
///         Delivered entropy and terminal cutover forbid this normal-session retry.
///
///         (2) THE SEALED DAY'S KEY. Daily processing keys the foil board and the traits
///         event by the day being SEALED (dailyIdx + 1), never the wall clock. The two
///         diverge when the word lands a day late: the advance clamps to the logical day,
///         and a wall-day key would strand that day's foil claims under the wrong entry.
///
///         (3) THE JACKPOT-PHASE RETRY AND THE COMMITTED COHORT. A jackpot retry must
///         preserve the already committed ticket parity. Its replacement word must drain
///         that same cohort before the phase leaves the level behind.
contract DailyRngStallRecovery is DeployProtocol {
    bytes32 private constant DAILY_TRAITS_SIG =
        keccak256("DailyWinningTraits(uint24,uint32)");

    address private buyer = address(0xB4A1);
    address private keeper = address(0xC4A9);
    /// @dev The daily retry is the vault owner's (the >50.1% DGVE holder; the deployer here).
    address private owner = ContractAddresses.CREATOR;

    uint256 private simTime;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(keeper, 1 ether);
        // The state engine also requests the scheduled Craps read cohort between days.
        mockVRF.fundSubscription(1, 1_000 ether);
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
            if (!game.rngLocked()) _finishReadConsumers();
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
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
        _finishReadConsumers();
        _buyTickets();
        simTime += 1 days + 1;
        vm.warp(simTime);
        // Scheduled-table arming may checkpoint before the fresh daily request.
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) {
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            require(ok, "harness: the daily request advance must succeed");
        }
        require(game.rngLocked(), "harness: the daily word must be in flight");
        stalledReqId = mockVRF.lastRequestId();
    }

    // ---------------------------------------------------------------------
    // (1) Administrative retry while mining waits
    // ---------------------------------------------------------------------

    /// Before the timeout the gate blocks exactly as before: the cohort cannot drain
    /// wordless, and no retry is on offer yet.
    function testStalledDailyBlocksBeforeTheTimeout() public {
        vm.pauseGasMetering();
        _driveDay(); // settle the deploy-day advance
        _stallDailyRequest();

        vm.warp(simTime + 19 hours);
        vm.prank(keeper);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
        assertFalse(ok, "the gate must still block inside the 20-hour window");
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        admin.retryGameRng();
    }

    function testAdminRetryOwnsAuthorityAndPreservesTheFrozenSession() public {
        _driveDay();
        uint256 oldId = _stallDailyRequest();
        bytes32 state = game.extsload(bytes32(0));
        bytes32 dayAndEpochs = game.extsload(bytes32(uint256(5)));
        bytes32 buffer = game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED));
        uint48 sent = uint48(uint256(state) >> 48);
        vm.warp(uint256(sent) + 20 hours);

        vm.prank(owner);
        uint8 ownerAction = game.nextMinerAction();
        vm.prank(keeper);
        uint8 publicAction = game.nextMinerAction();
        assertEq(ownerAction, uint8(DegenerusGameStorage.MinerAction.Wait));
        assertEq(publicAction, ownerAction, "pending work selection is independent of caller");
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        vm.prank(keeper);
        vm.expectRevert(bytes4(keccak256("NotOwner()")));
        admin.retryGameRng();
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("OnlyAdmin()")));
        game.retryRng();
        vm.prank(ContractAddresses.ADMIN);
        vm.expectRevert(bytes4(keccak256("OnlyAdmin()")));
        DegenerusGameRngModule(ContractAddresses.GAME_RNG_MODULE).retryRng();
        assertEq(mockVRF.lastRequestId(), oldId, "rejected routes issued no replacement");

        // A nonzero base fee: at Foundry's default of zero any measured-gas reward would price at zero.
        vm.fee(1 gwei);
        uint256 credit = coinflip.coinflipAmount(owner);
        vm.prank(owner);
        admin.retryGameRng();
        assertGt(mockVRF.lastRequestId(), oldId, "Admin route issued the sole replacement");
        // rngFlagsAndNudges bit 10 (slot-0 bit 250) is the request's retry-spent flag.
        assertEq(uint256(game.extsload(bytes32(0))), uint256(state) | (uint256(1) << 250),
            "only the spent bit changes in lifecycle state; timeout origin stays fixed");
        assertEq(game.extsload(bytes32(uint256(5))), dayAndEpochs, "logical day and ticket epochs stay frozen");
        assertEq(game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED)), buffer, "buffer identity and pending metadata stay frozen");
        assertEq(uint256(game.extsload(bytes32(uint256(3)))), 1, "replacement still awaits entropy");
        assertEq(coinflip.coinflipAmount(owner), credit, "administrative retry pays no miner reward");
    }

    function testAdminRetryRejectsDeliveredUnpublishedEntropy() public {
        _driveDay();
        uint256 id = _stallDailyRequest();
        uint48 sent = uint48(uint256(game.extsload(bytes32(0))) >> 48);
        mockVRF.fulfillRandomWords(id, 0xF00D);
        bytes32 word = game.extsload(bytes32(uint256(3)));
        assertGt(uint256(word), 1, "word delivered without a publication call");
        vm.warp(uint256(sent) + 20 hours);
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        admin.retryGameRng();
        assertEq(mockVRF.lastRequestId(), id);
        assertEq(game.extsload(bytes32(uint256(3))), word, "delivered entropy cannot be replaced");
    }

    function testAdminRetryRejectsTerminalAndLivenessExpiredSessions() public {
        _driveDay();
        uint256 id = _stallDailyRequest();
        bytes32 state = game.extsload(bytes32(0));
        uint48 sent = uint48(uint256(state) >> 48);
        vm.warp(uint256(sent) + 20 hours);
        // Isolate the explicit terminal guard while every retry-readiness predicate is true.
        vm.store(address(game), bytes32(0), bytes32(uint256(state) | (uint256(1) << 168)));
        assertTrue(game.gameOver());
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        admin.retryGameRng();
        vm.store(address(game), bytes32(0), state);
        vm.warp(uint256(sent) + 15 days);
        assertTrue(game.livenessTriggered(), "natural unanswered-request deadline expired");
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        admin.retryGameRng();
        assertEq(mockVRF.lastRequestId(), id, "terminal handling owns recovery after cutover");
    }

    /// At 20 hours Admin accepts the vault owner's retry even with a nonempty staged cohort;
    /// the replacement word then seals the day.
    /// Nobody else can fire it.
    function testStalledDailyRetriesAt20hWithTicketsPending() public {
        vm.pauseGasMetering();
        _driveDay();
        uint24 sealedBefore = _dailyIdx();
        uint256 stalledReqId = _stallDailyRequest();

        vm.warp(simTime + 20 hours + 1);
        vm.prank(keeper);
        (bool ok, ) = address(admin).call(abi.encodeWithSignature("retryGameRng()"));
        assertFalse(ok, "only the vault owner fires the retry");
        vm.prank(owner);
        (ok, ) = address(admin).call(abi.encodeWithSignature("retryGameRng()"));
        assertTrue(ok, "the 20-hour retry must be reachable with tickets pending");
        uint256 retryReqId = mockVRF.lastRequestId();
        assertGt(retryReqId, stalledReqId, "the retry must fire a fresh VRF request");

        // The retried word resolves the same staged cohort and the day seals.
        uint256 word = uint256(keccak256(abi.encode("retry", retryReqId)));
        mockVRF.fulfillRandomWords(retryReqId, word);
        for (uint256 j = 0; j < 200; j++) {
            (bool adv, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!adv) break;
        }
        assertGt(_dailyIdx(), sealedBefore, "the retried word must seal the day");
    }

    /// The retry is once-per-stall: the retry-spent flag latches, and a second 20-hour wait
    /// offers nothing more (recovery is then the retried word or a coordinator swap).
    function testDailyRetryIsSingleShot() public {
        vm.pauseGasMetering();
        _driveDay();
        _stallDailyRequest();

        vm.warp(simTime + 20 hours + 1);
        vm.prank(owner);
        (bool ok, ) = address(admin).call(abi.encodeWithSignature("retryGameRng()"));
        assertTrue(ok, "harness: first retry must fire");

        vm.warp(simTime + 41 hours);
        vm.prank(owner);
        (bool second, ) = address(admin).call(
            abi.encodeWithSignature("retryGameRng()")
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
                abi.encodeWithSignature("mineFlip()")
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

    /// Jackpot-phase buys route to the CURRENT level. Admin must not swap again on retry:
    /// the original request already committed the cohort to the read slot,
    /// and a second swap flips it back to the write slot where jackpot processing
    /// never finds it.
    function testJackpotRetryKeepsTheCommittedCohortInTheReadSlot() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        // The engine requests mid-day words on its own for closed Craps windows (6d0e64b09), and a
        // mid-day request commits queued tickets: settle that before the cohort under test is
        // bought, so the day's daily request is the one that commits it.
        _settleMidday();
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

        // The Admin transport retry leaves the committed ticket buffer untouched.
        simTime += 20 hours + 1;
        vm.warp(simTime);
        vm.prank(owner);
        (bool ok, ) = address(admin).call(abi.encodeWithSignature("retryGameRng()"));
        assertTrue(ok, "the 20-hour retry must fire in jackpot phase");
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
                abi.encodeWithSignature("mineFlip()")
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
            // Settle the engine's own mid-day work (closed Craps windows) before the day's buy,
            // so each day's cohort is committed by its daily request.
            _settleMidday();
            if (!game.rngLocked()) {
                _buyTickets();
            }
            _stallNextDailyRequest();
            _clearQueue(_readKeyOf(L + 1));
            simTime += 20 hours + 1;
            vm.warp(simTime);
            vm.prank(owner);
            (bool ok, ) = address(admin).call(
                abi.encodeWithSignature("retryGameRng()")
            );
            assertTrue(ok, "the 20-hour retry must fire on every jackpot day");
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
            if (!game.rngLocked()) _finishReadConsumers();
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) {
                simTime += 1 days + 1;
                vm.warp(simTime);
                // Cross the target only after 4+ purchase days so the phase latches
                // UNCOMPRESSED (day - psd <= 3 would set jackpotFlags = 1)
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
            if (!game.rngLocked()) _finishReadConsumers();
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) return;
        }
    }

    /// @dev Answer and drain the mid-day work the state engine requests on its own once a day
    ///      is sealed (a closed Craps window rides a mid-day request whenever the subscription
    ///      covers it, 6d0e64b09), until the engine is idle with nothing in flight.
    function _settleMidday() internal {
        for (uint256 i; i < 64; i++) {
            if (game.rngLocked()) return;
            uint8 action = game.nextMinerAction();
            if (action == 0 || action == 17) return; // Idle, or the next day's RequestDaily
            if (action == 2) {
                uint256 id = mockVRF.lastRequestId();
                (, , bool done) = mockVRF.pendingRequests(id);
                if (done) return;
                _fulfillPending();
            } else {
                game.mineFlip();
            }
        }
        revert("harness: mid-day work did not settle");
    }

    /// @dev Cross the day boundary and advance (never fulfilling) until the daily
    ///      request is in flight.
    function _stallNextDailyRequest() internal {
        if (!game.rngLocked()) _finishReadConsumers();
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 100; i++) {
            if (game.rngLocked()) return;
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) break;
        }
        require(game.rngLocked(), "harness: the daily request must be in flight");
    }

    /// @dev Seed the live next-pool half (slot 2, low 128 bits) up to targetNext.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(2)),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext)
        );
    }

    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev The read-slot key for a level under the current parity.
    function _readKeyOf(uint24 lvl) internal view returns (uint24) {
        return _ticketWriteSlot() ? lvl : lvl | TICKET_SLOT_BIT;
    }

    /// @dev Zero _ticketQueueLength(key) (models an award-less previous draw). Queue slots
    ///      recycle 1..100 under an absolute-level tag (c729ecfc9): clear the physical root only
    ///      while it is authenticated to this key's level.
    function _clearQueue(uint24 key) internal {
        if (TQ.length(address(game), key) == 0) return;
        vm.store(
            address(game),
            keccak256(abi.encode(uint256(TQ.queueKey(key)), uint256(12))),
            bytes32(0)
        );
    }

    /// @dev _ticketQueueLength(key), through the authenticated physical slot.
    function _queueLen(uint24 key) internal view returns (uint256) {
        return TQ.length(address(game), key);
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

    // ---------------------------------------------------------------------
    // (4) The death clock owns game-over
    // ---------------------------------------------------------------------

    /// A VRF outage is waited out for 14 days from the stalled request's send; outliving that
    /// window it is a dead VRF, and the game ends deterministically even with its day deadline
    /// (here the level-0 365-day window) far off.
    function testVrfOutageEndsOnlyOnceItOutlivesTheDeadWindow() public {
        vm.pauseGasMetering();
        _driveDay();
        _stallDailyRequest();

        simTime += 13 days;
        vm.warp(simTime);
        assertFalse(game.livenessTriggered(), "inside the VRF-dead window a stall is only waited out");

        simTime += 2 days;
        vm.warp(simTime);
        assertTrue(game.livenessTriggered(), "14 days with nothing delivered: VRF dead");
        for (uint256 j = 0; j < 20 && !game.gameOver(); j++) {
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) break;
        }
        assertTrue(game.gameOver(), "the deterministic ending completes");
    }

    /// Game-over is permanent in both directions: once the terminal path has run, the trigger
    /// it latched on must keep reading true, or every liveness-gated paid entrypoint reopens
    /// while the game is dead. The deadman reads currentDay - dailyIdx, so the terminal seal
    /// must not retire that staleness.
    function testGameOverImpliesLivenessAfterAJackpotPhaseDeadman() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");

        // VRF dies mid-jackpot-phase and never returns; the deadman is the only trigger here.
        simTime += 121 days;
        vm.warp(simTime);
        assertTrue(game.livenessTriggered(), "harness: the deadman must fire");

        for (uint256 j = 0; j < 400; j++) {
            if (game.gameOver()) break;
            _fulfillPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) break;
        }
        assertTrue(game.gameOver(), "harness: the terminal path must latch game-over");

        assertTrue(
            game.livenessTriggered(),
            "game-over must keep the liveness trigger set, not retire its own evidence"
        );
    }
}
