// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

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
///         The unified sweep drains every read-side key in the trailing window
///         [purchaseLevel-1 .. purchaseLevel+4], so a retired level keeps being named until
///         both its parities are empty: leftovers that a boundary crossing, promotion, or
///         turbo collapse parks on the write side are re-committed by a later swap and
///         drained instead of stranding.
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
    uint24 private constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;
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
    /// level's keys for good. The windowed sweep drains every committed key, so nothing
    /// strands.
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
    // I. The penultimate-day eligibility guard
    // ---------------------------------------------------------------------

    /// On the penultimate day the request is served — the word still resolves pending
    /// lootboxes — but the buffer swap is refused. The sweep's trailing window would
    /// drain a crossing cohort safely either way, but only AFTER the level retired
    /// (drawless); the guard keeps the whole evening cohort together on the write side
    /// for the final request's own commit, which its chain drains before the final draw.
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
            "the read window stays drained: no latch, no pending mid-day batch"
        );
    }

    // ---------------------------------------------------------------------
    // J. Turbo-arm crossing
    // ---------------------------------------------------------------------

    /// A latched mid-day batch from a fresh purchase-phase evening crosses the boundary
    /// into a morning whose pool already exceeds the next target — the turbo-arm state.
    /// The promotion cannot swap (read slot busy) and the collapsed same-lock jackpot
    /// phase issues no sentinel swap, so the post-request buys sit on the write side
    /// through the whole collapse. The trailing window keeps naming that level through
    /// the following purchase phase: the next request's swap re-commits them and the
    /// sweep drains them. Nothing strands at the building level's keys.
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
    // M. Terminal two-case entropy
    // ---------------------------------------------------------------------

    /// Economic death with working VRF — the normal ending. Death is detected before
    /// the day's request fires, so the terminal swap commits everything, the FRESH
    /// terminal word resolves it in a single drain, and no window key on either
    /// parity survives.
    function testTerminalFreshWordClearsEverythingInOneCohort() public {
        vm.pauseGasMetering();
        (uint24 L, , ) = _runJackpotPhase(MIDDAY_NEVER, MODE_DRAIN_SAME_DAY, true);

        // Purchase phase: queue a live cohort, then drive the liveness ending with
        // VRF fully working (fulfill everything).
        _buyTickets();
        assertGt(
            _queueLen(_writeKeyOf(L + 1)),
            0,
            "harness: the evening cohort must stage on the write side"
        );
        // ONE warp straight past the liveness deadline from the settled evening:
        // no intermediate day is ever requested, so the first advance detects
        // death on a fully-idle game (no recorded word, nothing in flight) and
        // the terminal path owns the whole swap/request/drain sequence. Repeated
        // shorter warps would instead run the stall-recovery re-walk, whose
        // recorded-but-unsealed day word is the delivered-word terminal case —
        // a different (write-buffer-forfeiting) ending than this test pins.
        simTime += 150 days;
        vm.warp(simTime);
        for (uint256 j = 0; j < 60 && !game.gameOver(); j++) {
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            ok;
            _fulfillPending();
        }
        assertTrue(game.gameOver(), "harness: liveness death must latch game over");

        _assertPayoutKeyClear(L + 1);
    }

    /// Dead-VRF death — the fallback ending. A daily request commits a cohort and is
    /// never fulfilled; stall-window buys land on the write side. Past the fallback
    /// grace the read cohort drains against the fallback word, then the fallbackDue
    /// swap commits the write cohort, which drains against the same word. Both
    /// parities of every window key end empty.
    function testTerminalFallbackClearsBothBuffers() public {
        vm.pauseGasMetering();
        (uint24 L, , ) = _runJackpotPhase(MIDDAY_NEVER, MODE_DRAIN_SAME_DAY, true);

        // Evening buys -> next day's request fires and swaps them committed; the
        // word never arrives; stall-window buys land on the fresh write side.
        _buyTickets();
        assertGt(
            _queueLen(_writeKeyOf(L + 1)),
            0,
            "harness: the evening cohort must stage on the write side"
        );
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        ok;
        require(game.rngLocked(), "harness: the daily request must be in flight");
        // Stall-window cohort: the daily lock does not block ticket buys (they land
        // on the fresh write buffer), so bypass the checked helper's lock-skip.
        _buyTicketsUnchecked();
        assertGt(
            _queueLen(_writeKeyOf(L + 1)),
            0,
            "harness: the stall-window cohort must stage on the write side"
        );

        // Dead VRF: never fulfill again; big warps ride the deadman + fallback
        // grace to the terminal fallback ending.
        for (uint256 i = 0; i < 10 && !game.gameOver(); i++) {
            simTime += 90 days;
            vm.warp(simTime);
            for (uint256 j = 0; j < 40; j++) {
                (ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
            }
        }
        assertTrue(game.gameOver(), "harness: dead-VRF death must latch game over");

        _assertPayoutKeyClear(L + 1);
    }

    /// @dev Terminal end-state: the PAYOUT key is fully drained on both parities and
    ///      its owed fully materialized. Queues at every other level are worthless at
    ///      game over and are deliberately never touched (no assertion on them).
    function _assertPayoutKeyClear(uint24 payoutKey) internal view {
        assertEq(
            _queueLen(payoutKey),
            0,
            "terminal: payout plain-parity queue must be empty"
        );
        assertEq(
            _queueLen(payoutKey | TICKET_SLOT_BIT),
            0,
            "terminal: payout alt-parity queue must be empty"
        );
        assertEq(
            _entriesOwed(payoutKey, buyer) +
                _entriesOwed(payoutKey | TICKET_SLOT_BIT, buyer),
            0,
            "terminal: the payout key's owed must be fully materialized"
        );
    }

    // ---------------------------------------------------------------------
    // L. The far-future barrier
    // ---------------------------------------------------------------------

    /// The crossing contract: when level L's transition runs, the far-future key of
    /// L+5 (the level that just became near) is drained WHOLE before the transition
    /// can complete — and from the arm's level increment onward that key is
    /// write-dead (the distance routing sends every target <= level+5 to the plain
    /// window keys), so it never holds content again.
    function testFarFutureBarrierCrossesWholeAndNeverRefills() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        uint24 L = _level();
        uint24 ffKey = (L + 5) | TICKET_FAR_FUTURE_BIT;

        // Non-vacuity: the deploy-time perpetual seeding guarantees far-future
        // content at the crossing key before its transition.
        assertGt(
            _queueLen(ffKey),
            0,
            "reachability: the crossing key must hold far-future content pre-transition"
        );

        // Run the phase out through the transition (the crossing drain runs inside it).
        for (uint256 d = 0; d < 12 && game.jackpotPhase(); d++) {
            _buyTickets();
            _runFullDay();
        }
        require(!game.jackpotPhase(), "harness: the phase must have transitioned");
        _runFullDay();

        assertEq(
            _queueLen(ffKey),
            0,
            "the crossing drain must empty the WHOLE far key at the transition"
        );

        // Drive the following level with daily buys and lootbox purchases (whose award
        // rolls exercise the near-offset routing): the crossed key must never refill.
        for (uint256 i = 0; i < 12 && _level() <= L + 1; i++) {
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(500 ether);
            }
            _buyTickets();
            vm.prank(buyer);
            game.purchase{value: 2 ether}(
                buyer,
                0,
                BoxOrderLib.boCustom(2 ether),
                bytes32(0),
                MintPaymentKind.DirectEth,
                false
            );
            _runFullDay();
            assertEq(
                _queueLen(ffKey),
                0,
                "a crossed far key must never be written again"
            );
            if (game.gameOver()) break;
        }
        assertGt(_level(), L, "harness: the game must have moved past the level");

        // The barrier moved exactly one level: the NEXT crossing key drained at the
        // next transition.
        assertEq(
            _queueLen((L + 6) | TICKET_FAR_FUTURE_BIT),
            0,
            "the next level's transition must have crossed the next far key"
        );
    }

    // ---------------------------------------------------------------------
    // K. Six-segment sweep gas shape
    // ---------------------------------------------------------------------

    /// The worst chained-call shape: every windowed read key non-empty at once, so one
    /// worker call opens six fresh segments (six cold derates, six releases) and then
    /// probes foil. The whole advance transaction must stay under the 10M per-tx target.
    function testSixSegmentSweepSingleCallStaysUnderTarget() public {
        vm.pauseGasMetering();
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        assertTrue(game.jackpotPhase(), "harness: must be inside the jackpot phase");
        uint24 L = _level();

        // Seed a 1-address / 4-entry cohort onto the READ side of every window key
        // [purchaseLevel-1 .. purchaseLevel+4] = [L .. L+5], and reopen the drain.
        for (uint24 t = L; t <= L + 5; t++) {
            _seedReadCohort(t, buyer, 4);
        }
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        vm.store(
            address(game),
            bytes32(uint256(0)),
            bytes32(s0 & ~(uint256(1) << 192)) // ticketsFullyProcessed = false
        );

        vm.resumeGasMetering();
        uint256 g = gasleft();
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        g -= gasleft();
        assertTrue(ok, "harness: the sweep advance must succeed");
        emit log_named_uint("six-segment sweep advance gas", g);
        assertGt(g, 0, "harness: gas metering must be live for the measurement");
        assertLt(g, 10_000_000, "the chained sweep call must stay under the 10M target");
    }

    /// @dev Seed one queued address with `entries` owed onto the CURRENT READ side of
    ///      level key `lvl` (queue mapping slot 12, owed mapping slot 13).
    function _seedReadCohort(uint24 lvl, address who, uint32 entries) internal {
        uint24 rk = _readKeyOf(lvl);
        bytes32 lenSlot = keccak256(abi.encode(uint256(rk), uint256(12)));
        uint256 len = uint256(vm.load(address(game), lenSlot));
        vm.store(address(game), lenSlot, bytes32(len + 1));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        vm.store(
            address(game),
            bytes32(uint256(dataBase) + len),
            bytes32(uint256(uint160(who)))
        );
        bytes32 owedSlot = keccak256(
            abi.encode(who, keccak256(abi.encode(uint256(rk), uint256(13))))
        );
        vm.store(address(game), owedSlot, bytes32((uint256(entries) << 8) | _seedOwnerBits(lvl, who)));
    }

    /// @dev Register `who` in lvlEntryOwner[lvl] (slot 67, append-only) the way every sink does at
    ///      queue time, returning the owner bits the owed word must carry (position + 1 << 48).
    function _seedOwnerBits(uint24 lvl, address who) internal returns (uint256) {
        bytes32 lenSlot = keccak256(abi.encode(uint256(lvl), uint256(67)));
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 elemSlot = bytes32(uint256(keccak256(abi.encode(lenSlot))) + len);
        vm.store(address(game), elemSlot, bytes32(uint256(uint160(who))));
        vm.store(address(game), lenSlot, bytes32(len + 1));
        return (len + 1) << 48;
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

    /// @dev Mid-stall purchase: ticket buys stay open under the daily RNG lock and
    ///      land on the write buffer; the checked helper's lock-skip would silently
    ///      drop a stall-window cohort.
    function _buyTicketsUnchecked() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
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
