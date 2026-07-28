// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title MiddaySwapJackpotCohort — the mid-day lootbox freeze against a jackpot-phase cohort.
///
/// @notice `requestLootboxRng` freezes the ticket buffer with `_swapTicketSlot()`, the SAME
///         single global toggle the daily request uses. In the JACKPOT phase player buys
///         route to `level`, not `level + 1` (`_activeTicketLevel`), while the daily jackpot
///         queues its ticket AWARDS at `level + 1`. The global swap therefore re-points BOTH
///         keys at once, and every drain that follows the swap must name both — the routed
///         cohort first, then the award queue — before the mid-day latch clears. The same
///         holds for the new-day pre-RNG gate when a mid-day batch crosses the day boundary.
///
///         On the level's PENULTIMATE day the swap is refused outright (the guard in
///         requestLootboxRng): a freeze window opened there can cross into the final day via
///         a stalled-word promotion with the read slot busy, leaving the post-request write
///         cohort at a key no later swap ever commits. The queues instead wait for the final
///         request's own sentinel commit, which its chain drains.
///
///         Suite shape:
///           A  mechanism   — an early-day swap commits the routed cohort and the mid-day
///                            drain empties BOTH read keys before releasing the latch.
///           B  regression  — a mid-day request on the penultimate jackpot day must not
///                            strand the cohort (the original defect's trigger day).
///           C  control     — identical drive with no mid-day request strands nothing.
///           D  permanence  — nothing lingers a further full level after the B scenario.
///           E  early day   — a request on the FIRST jackpot day strands nothing.
///           F  promotion   — a penultimate-day request whose word NEVER arrives promotes
///                            onto the final day; the stall-window buys must not strand.
///           F2 crossing    — a latched batch left undrained across a non-final boundary is
///                            finished by the pre-RNG gate at both keys; nothing strands.
///           G  awards-only — a swap fired with no routed buys pending drains the award
///                            queue alone; nothing strands.
///           H  freeze      — a buy placed AFTER the mid-day request stays on the write
///                            side through the whole mid-day drain (it can never resolve
///                            against that request's word) and still materializes.
///           I  guard       — the penultimate-day request is served without a swap: no
///                            latch, read slot stays drained.
contract MiddaySwapJackpotCohort is DeployProtocol {
    address private buyer = address(0xB4A1);
    address private crank = address(0xC4A9);

    uint256 private simTime;

    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;
    uint8 private constant JACKPOT_LEVEL_CAP = 5;
    uint8 private constant MIDDAY_NEVER = 255;

    // Day-runner modes for the day after the mid-day request.
    uint8 private constant MODE_DRAIN_SAME_DAY = 0;
    uint8 private constant MODE_CROSS_FULFILLED = 1;
    uint8 private constant MODE_CROSS_PROMOTED = 2;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 200_000 ether);
        vm.deal(crank, 10 ether);
        // Clear MIN_LINK_FOR_LOOTBOX_RNG (40 LINK). The admin ctor creates subId 1.
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // A. Mechanism
    // ---------------------------------------------------------------------

    /// An early-day mid-day request commits the routed jackpot-phase cohort (the global swap
    /// flips its key into the read slot), and the mid-day drain that follows empties BOTH
    /// read keys — the routed cohort at `level` and the award queue at `level + 1` — before
    /// the latch releases.
    function testMiddayRequestCommitsAndDrainsTheRoutedCohort() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        uint24 L = _level();

        // The day's own jackpot leaves award tickets at level + 1.
        assertGt(
            _queueLen(_writeKeyOf(L + 1)),
            0,
            "reachability: the jackpot queues its award tickets at level + 1"
        );
        assertTrue(
            _ticketsFullyProcessed(),
            "reachability: the sealed day leaves the read slot drained"
        );

        // A jackpot-phase buy routes to `level` (_activeTicketLevel), into the write slot.
        _buyTickets();
        uint24 cohortKey = _writeKeyOf(L);
        assertGt(_queueLen(cohortKey), 0, "harness: the cohort must stage at the current level");

        bool parityBefore = _ticketWriteSlot();
        require(_middayRequest(), "harness: the early-day mid-day flip must fire");
        assertTrue(
            _ticketWriteSlot() != parityBefore,
            "the mid-day request must flip the global ticket buffer"
        );
        assertEq(
            _readKeyOf(L),
            cohortKey,
            "the flip re-points the routed cohort into the READ slot"
        );

        _drainMidday();
        assertEq(_queueLen(_readKeyOf(L)), 0, "the mid-day drain clears the routed level");
        assertEq(_queueLen(_readKeyOf(L + 1)), 0, "and the award queue at level + 1");
        assertTrue(
            _ticketsFullyProcessed(),
            "the latch releases only once both read keys are empty"
        );
    }

    // ---------------------------------------------------------------------
    // B. Regression: the penultimate-day request
    // ---------------------------------------------------------------------

    /// ONE permissionless mid-day request on the penultimate jackpot day — the original
    /// defect's trigger: the probe hardcoded level + 1, the swap flipped the routed cohort
    /// out of reach, the final day's swap flipped it further, and the transition retired the
    /// level's keys for good. Now the guard refuses that swap and nothing strands.
    function testSingleMiddayRequestOnThePenultimateJackpotDayStrandsTheCohort() public {
        vm.pauseGasMetering();
        (uint24 L, uint256 priceWei, ) = _runJackpotPhase(
            JACKPOT_LEVEL_CAP - 1,
            MODE_DRAIN_SAME_DAY,
            true
        );

        uint256 strandedA = _queueLen(L);
        uint256 strandedB = _queueLen(L | TICKET_SLOT_BIT);
        uint256 owedA = _entriesOwed(L, buyer);
        uint256 owedB = _entriesOwed(L | TICKET_SLOT_BIT, buyer);

        emit log_named_uint("stranded queue addresses (slot A)", strandedA);
        emit log_named_uint("stranded queue addresses (slot B)", strandedB);
        emit log_named_uint("buyer entries owed (slot A)", owedA);
        emit log_named_uint("buyer entries owed (slot B)", owedB);
        emit log_named_uint("whole-ticket price at the level (wei)", priceWei);
        emit log_named_uint(
            "buyer face value stranded (wei)",
            ((owedA + owedB) * priceWei) / 4
        );

        assertEq(
            strandedA + strandedB,
            0,
            "no paid cohort may strand at the finished level after the transition"
        );
    }

    // ---------------------------------------------------------------------
    // C. Control
    // ---------------------------------------------------------------------

    /// The identical drive with the mid-day request removed. Every jackpot day's cohort is
    /// picked up by the next daily swap, and the final day routes buys to level + 1 — so
    /// the level's keys end empty.
    function testControlWithoutTheMiddayRequestNothingStrands() public {
        vm.pauseGasMetering();
        (uint24 L, , ) = _runJackpotPhase(MIDDAY_NEVER, MODE_DRAIN_SAME_DAY, true);

        assertEq(
            _queueLen(L),
            0,
            "control: slot A must be empty at the finished level"
        );
        assertEq(
            _queueLen(L | TICKET_SLOT_BIT),
            0,
            "control: slot B must be empty at the finished level"
        );
    }

    // ---------------------------------------------------------------------
    // D. Permanence probe
    // ---------------------------------------------------------------------

    /// Drive the whole NEXT level (purchase phase to target, jackpot phase to transition)
    /// after a penultimate-day mid-day request: nothing may linger at the finished level.
    function testNothingLingersAFurtherFullLevel() public {
        vm.pauseGasMetering();
        (uint24 L, , ) = _runJackpotPhase(
            JACKPOT_LEVEL_CAP - 1,
            MODE_DRAIN_SAME_DAY,
            true
        );

        // A whole further level: purchase phase to target, then its jackpot phase out.
        for (uint256 i = 0; i < 60 && _level() <= L + 1; i++) {
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(500 ether);
            }
            _buyTickets();
            _runFullDay();
            if (game.gameOver()) break;
        }

        assertGt(_level(), L, "harness: the game must have moved past the level");
        assertEq(
            _queueLen(L) + _queueLen(L | TICKET_SLOT_BIT),
            0,
            "no queue entries may remain at the retired level"
        );
        assertEq(
            _entriesOwed(L, buyer) + _entriesOwed(L | TICKET_SLOT_BIT, buyer),
            0,
            "no owed entries may remain at the retired level"
        );
    }

    // ---------------------------------------------------------------------
    // E. An earlier jackpot day
    // ---------------------------------------------------------------------

    /// A request on the FIRST jackpot day (counter == 1): the cohort resolves and nothing
    /// strands at the level once the phase runs out.
    function testMiddayRequestOnTheFirstJackpotDayStrandsNothing() public {
        vm.pauseGasMetering();
        (uint24 L, uint256 priceWei, bool swapped) = _runJackpotPhase(
            1,
            MODE_DRAIN_SAME_DAY,
            true
        );
        assertTrue(swapped, "harness: an early-day request must commit the buffer");

        uint256 stranded = _queueLen(L) + _queueLen(L | TICKET_SLOT_BIT);
        uint256 owed = _entriesOwed(L, buyer) +
            _entriesOwed(L | TICKET_SLOT_BIT, buyer);
        emit log_named_uint("first-day: stranded addresses", stranded);
        emit log_named_uint("first-day: buyer entries owed", owed);
        emit log_named_uint(
            "first-day: buyer face value stranded (wei)",
            (owed * priceWei) / 4
        );

        assertEq(
            stranded,
            0,
            "an early-day mid-day request must not strand the cohort"
        );
    }

    // ---------------------------------------------------------------------
    // F. Penultimate-day request, word never arrives (promotion crossing)
    // ---------------------------------------------------------------------

    /// The mid-day request fires on the penultimate day, buys land after it, and its word
    /// NEVER arrives that day. The next (final) morning the stalled request is promoted to
    /// the daily request. Every cohort — pre-request, stall-window, and award queue — must
    /// still materialize; nothing may strand past the transition.
    function testPenultimateStalledWordPromotionStrandsNothing() public {
        vm.pauseGasMetering();
        (uint24 L, uint256 priceWei, ) = _runJackpotPhase(
            JACKPOT_LEVEL_CAP - 1,
            MODE_CROSS_PROMOTED,
            true
        );

        uint256 stranded = _queueLen(L) + _queueLen(L | TICKET_SLOT_BIT);
        uint256 owed = _entriesOwed(L, buyer) +
            _entriesOwed(L | TICKET_SLOT_BIT, buyer);
        emit log_named_uint("promotion: stranded addresses", stranded);
        emit log_named_uint("promotion: buyer entries owed", owed);
        emit log_named_uint(
            "promotion: buyer face value stranded (wei)",
            (owed * priceWei) / 4
        );

        assertEq(
            stranded,
            0,
            "a stalled-word promotion onto the final day must not strand any cohort"
        );
    }

    // ---------------------------------------------------------------------
    // F2. Latched batch crossing a non-final boundary
    // ---------------------------------------------------------------------

    /// A committed mid-day batch (two swaps still ahead) left undrained across the day
    /// boundary: the new-day pre-RNG gate must finish BOTH read keys — the routed cohort at
    /// lvl and the flipped award queue at lvl + 1 — before the daily swap re-points the
    /// read slot. Nothing strands once the phase runs out.
    function testMiddayBatchCrossingTheDayBoundaryStrandsNothing() public {
        vm.pauseGasMetering();
        (uint24 L, uint256 priceWei, bool swapped) = _runJackpotPhase(
            JACKPOT_LEVEL_CAP - 2,
            MODE_CROSS_FULFILLED,
            true
        );
        assertTrue(swapped, "harness: the non-penultimate flip must fire");

        uint256 stranded = _queueLen(L) + _queueLen(L | TICKET_SLOT_BIT);
        uint256 owed = _entriesOwed(L, buyer) +
            _entriesOwed(L | TICKET_SLOT_BIT, buyer);
        emit log_named_uint("crossing: stranded addresses", stranded);
        emit log_named_uint("crossing: buyer entries owed", owed);
        emit log_named_uint(
            "crossing: buyer face value stranded (wei)",
            (owed * priceWei) / 4
        );

        assertEq(
            stranded,
            0,
            "a mid-day batch crossing the day boundary must not strand the cohort"
        );
    }

    // ---------------------------------------------------------------------
    // G. Awards-only request
    // ---------------------------------------------------------------------

    /// No routed buys pending on the request day: the probe finds only the award queue at
    /// level + 1, commits it, and the mid-day drain resolves it. Nothing strands once the
    /// phase runs out.
    function testAwardsOnlyMiddayRequestStrandsNothing() public {
        vm.pauseGasMetering();
        (uint24 L, , bool swapped) = _runJackpotPhase(
            JACKPOT_LEVEL_CAP - 2,
            MODE_DRAIN_SAME_DAY,
            false
        );
        assertTrue(swapped, "harness: the awards-only flip must fire");

        assertEq(
            _queueLen(L) + _queueLen(L | TICKET_SLOT_BIT),
            0,
            "an awards-only mid-day request must not strand anything at the level"
        );
    }

    // ---------------------------------------------------------------------
    // H. The freeze property
    // ---------------------------------------------------------------------

    /// A buy placed AFTER the mid-day request lands on the write side and stays there
    /// through the whole mid-day drain — the request's word can never reach it — and the
    /// cohort still materializes by the end of the phase (no strand).
    function testBuyAfterMiddayRequestIsFrozenOutOfThatWord() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        uint24 L = _level();

        // Reach a day with two swaps still ahead, buying daily so every day has a cohort.
        for (
            uint256 d = 0;
            d < 12 && _jackpotCounter() != JACKPOT_LEVEL_CAP - 2;
            d++
        ) {
            _buyTickets();
            _runFullDay();
            require(game.jackpotPhase(), "harness: phase ended before the target day");
        }

        _buyTickets(); // pre-request cohort
        require(_middayRequest(), "harness: the mid-day flip must fire");

        // Post-request buy: must land on the (fresh) write side of the routed level.
        uint24 frozenKey = _writeKeyOf(L);
        uint256 lenBefore = _queueLen(frozenKey);
        _buyTickets();
        uint256 lenAfter = _queueLen(frozenKey);
        assertGt(lenAfter, lenBefore, "the post-request buy must stage on the write side");

        _drainMidday();
        assertEq(
            _queueLen(frozenKey),
            lenAfter,
            "the mid-day drain must never consume the write side: the post-request buy is frozen out of the word"
        );
        assertEq(_queueLen(_readKeyOf(L)), 0, "while the committed read side fully drains");

        // Run the phase out: the frozen cohort must still materialize (no strand).
        for (uint256 d = 0; d < 12 && game.jackpotPhase(); d++) {
            _runFullDay();
        }
        _runFullDay();
        assertEq(
            _queueLen(L) + _queueLen(L | TICKET_SLOT_BIT),
            0,
            "the post-request cohort must materialize by the end of the phase"
        );
    }

    // ---------------------------------------------------------------------
    // I. The penultimate-day guard
    // ---------------------------------------------------------------------

    /// On the penultimate day the request is served — the word still resolves pending
    /// lootboxes — but the buffer swap is refused: no parity flip, no latch, and the read
    /// slot stays drained. The queued cohorts wait for the final request's own commit.
    function testPenultimateDayRequestIsServedWithoutASwap() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");

        for (
            uint256 d = 0;
            d < 12 && _jackpotCounter() != JACKPOT_LEVEL_CAP - 1;
            d++
        ) {
            _buyTickets();
            _runFullDay();
            require(game.jackpotPhase(), "harness: phase ended before penultimate day");
        }

        _buyTickets();
        bool swapped = _middayRequest();
        assertFalse(swapped, "the penultimate-day request must not flip the buffer");
        assertTrue(
            _ticketsFullyProcessed(),
            "the read slot stays drained: no latch, no pending mid-day batch"
        );
    }

    // ---------------------------------------------------------------------
    // J. Turbo-arm crossing
    // ---------------------------------------------------------------------

    /// A latched mid-day batch from a fresh purchase-phase evening crosses the boundary
    /// into a morning whose pool already exceeds the next target — the turbo-arm state.
    /// The arm must defer to the compressed path: the promotion cannot swap (read slot
    /// busy), and a collapsed same-lock jackpot phase would leave the post-request buys
    /// at a key no drain ever names again. With the defer, the next day's real request
    /// swaps and drains them; nothing strands at the building level's keys.
    function testTurboArmCrossingStrandsNothing() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        require(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        uint24 L = _level();

        // Run the jackpot phase out; the transition completes during the last day, so
        // the current sealed day IS purchaseStartDay (tomorrow has purchaseDays == 1).
        for (uint256 d = 0; d < 12 && game.jackpotPhase(); d++) {
            _buyTickets();
            _runFullDay();
        }
        require(!game.jackpotPhase(), "harness: the phase must have transitioned");
        uint24 building = _level() + 1;

        // Fresh-phase evening: pre-request cohort, latched mid-day request, buys after
        // it, and a pool seeded over the next target so tomorrow is turbo-armable.
        _buyTickets();
        require(_middayRequest(), "harness: the purchase-phase flip must fire");
        _buyTickets();
        _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);

        // Cross without fulfilling: the promotion resolves the stalled request.
        _runPromotedCrossingDay();

        // Run the building level's phase out however it resolves (compressed or not).
        for (uint256 d = 0; d < 15 && !(_level() >= building && !game.jackpotPhase()); d++) {
            _buyTickets();
            _runFullDay();
            require(!game.gameOver(), "harness: gameOver before the level completed");
        }
        _runFullDay();

        assertEq(
            _queueLen(building) + _queueLen(building | TICKET_SLOT_BIT),
            0,
            "no cohort may strand at the building level after a turbo-arm crossing"
        );
        assertEq(
            _entriesOwed(building, buyer) +
                _entriesOwed(building | TICKET_SLOT_BIT, buyer),
            0,
            "no owed entries may strand at the building level"
        );
    }

    // ---------------------------------------------------------------------
    // Drive
    // ---------------------------------------------------------------------

    /// @dev Reach the jackpot phase, buy on every jackpot day (except, when buyOnMiddayDay
    ///      is false, the request day itself), fire ONE mid-day lootbox request on the day
    ///      whose jackpotCounter reads `middayAtCounter` (255 = never), run the following
    ///      day per `mode`, and run the phase out through the transition. Returns the level
    ///      that just finished, its whole-ticket price, and whether the request swapped.
    function _runJackpotPhase(
        uint8 middayAtCounter,
        uint8 mode,
        bool buyOnMiddayDay
    ) internal returns (uint24 L, uint256 priceWei, bool swapped) {
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        require(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        L = _level();
        (, , , , priceWei) = game.purchaseInfo();

        for (uint256 d = 0; d < 12 && game.jackpotPhase(); d++) {
            uint8 counter = _jackpotCounter();
            bool middayDay = counter == middayAtCounter;
            if (buyOnMiddayDay || !middayDay) {
                _buyTickets();
            }
            if (middayDay) {
                swapped = _middayRequest();
                if (mode == MODE_DRAIN_SAME_DAY) {
                    _drainMidday();
                } else if (mode == MODE_CROSS_PROMOTED) {
                    // Stall-window buys land after the request, before any word.
                    _buyTickets();
                    _runPromotedCrossingDay();
                    continue;
                }
                // MODE_CROSS_FULFILLED: leave the batch for the next day's gate;
                // _runFullDay fulfills the word before its first advance.
            }
            _runFullDay();
        }
        require(!game.jackpotPhase(), "harness: the phase must have transitioned");
        // Settle the transition tail.
        _runFullDay();
    }

    /// @dev Cross the boundary WITHOUT fulfilling the outstanding mid-day word: the first
    ///      advance runs the stalled-request promotion (or the rngGate re-fire), and only
    ///      then does the (new) request get its word and the day drain out.
    function _runPromotedCrossingDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        ok; // the promotion entry may or may not revert once its stage breaks
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            (ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) break;
        }
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

    /// @dev Buy a 2-ETH lootbox (clears the 1-ETH mid-day threshold) then fire the
    ///      permissionless mid-day request from an unrelated account. True iff the
    ///      global ticket buffer toggled.
    function _middayRequest() internal returns (bool swapped) {
        vm.prank(buyer);
        game.purchase{value: 2 ether}(
            buyer,
            0,
            2 ether,
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

    function _drainMidday() internal {
        _fulfillPending();
        for (uint256 i = 0; i < 100; i++) {
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
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

    function _driveToJackpotPhase() internal {
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

    /// @dev levelPrizePool[lvl] — the mapping sits at slot 23; levelPrizePool[L] is the
    ///      target the level-(L+1) pool must exceed.
    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 v = uint256(
            vm.load(
                address(game),
                keccak256(abi.encode(uint256(lvl), uint256(23)))
            )
        );
        return v < 50 ether ? 50 ether : v;
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

    function _readKeyOf(uint24 lvl) internal view returns (uint24) {
        return _ticketWriteSlot() ? lvl : lvl | TICKET_SLOT_BIT;
    }

    function _writeKeyOf(uint24 lvl) internal view returns (uint24) {
        return _ticketWriteSlot() ? lvl | TICKET_SLOT_BIT : lvl;
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

    /// @dev ticketWriteSlot — slot 0, byte 25.
    function _ticketWriteSlot() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 200) & 1) != 0;
    }

    /// @dev ticketsFullyProcessed — slot 0, byte 24.
    function _ticketsFullyProcessed() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> 192) & 1) != 0;
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
}
