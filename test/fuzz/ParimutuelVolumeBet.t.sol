// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @dev Exposes the packed volume counter's mechanics: the purchase-path accumulate, the
///      freeze routing, and the unfreeze fold's roll. Inherits the real module, so a slot
///      or mask drift fails here before it fails in production.
contract VolumeCounterHarness is DegenerusGameAdvanceModule {
    function apc(uint128 nextAdd, uint128 futureAdd, uint48 hundredths) external {
        _addPrizeContribution(nextAdd, futureAdd, hundredths);
    }

    function setFrozen(bool frozen) external {
        prizePoolFrozen = frozen;
    }

    function fold() external {
        _unfreezePool();
    }

    function liveVolume() external view returns (uint48) {
        return _getLiveTicketVolume();
    }

    function pools() external view returns (uint128 next, uint128 future) {
        return _getPrizePools();
    }

    function pendingRaw() external view returns (uint256) {
        return prizePoolPendingPacked;
    }
}

/// @title ParimutuelVolumeBet -- the ticket-volume parimutuel.
///
/// @notice Three layers. The counter layer pins the packed volume mechanics on the real
///         storage helpers. The market layer drives placement, settlement and the void
///         rule with pushes pranked as GAME — recordVolume is the game's act at the RNG
///         request — while FLIP and Coinflip stay REAL, keeping the burn/credit
///         conservation assertions load-bearing. The lifecycle layer buys tickets on the
///         real game and watches the freeze push the sealed round out, unpranked.
contract ParimutuelVolumeBetTest is DeployProtocol {
    bytes4 private constant MARKET_GATES =
        bytes4(keccak256("marketBetGates(address,uint24)"));
    bytes4 private constant GROWTH_STATE =
        bytes4(keccak256("growthState(uint24)"));

    uint256 private constant STAKE = 1_000 ether;
    uint256 private constant CREDIT = 25 ether;

    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);
    address private carol = address(0xCAB0);
    address private keeper = address(0xC1A9);

    uint256 private simTime;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 100_000 ether);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev Fund and clear the lifetime gate WITH the placement credit
    ///      (mayBet = true, earnsReward = true).
    function _fund(address who, uint256 amount) internal {
        _fundNoGate(who, amount);
        _gate(who, true, true);
    }

    function _fundNoGate(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _gate(address who, bool mayBet, bool earnsReward) internal {
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(MARKET_GATES, who),
            abi.encode(mayBet, earnsReward)
        );
    }

    /// @dev Warp into the betting window — 22:57 to 00:00 UTC of the current protocol
    ///      day — and return the round a bet placed now joins.
    function _openWindow() internal returns (uint24 round) {
        uint256 dayStart = ((block.timestamp - GameTimeLib.JACKPOT_RESET_TIME) / 1 days) *
            1 days +
            GameTimeLib.JACKPOT_RESET_TIME;
        uint256 target = dayStart + 1 days + 60; // one minute past the next day break
        vm.warp(target);
        simTime = target;
        round = GameTimeLib.currentDayIndex() + 1;
    }

    /// @dev Push a sealed round as the game does at the RNG request.
    function _push(uint24 round, uint48 total) internal {
        vm.prank(address(game));
        parimutuel.recordVolume(round, total);
    }

    /// @dev Open the window AND make the market scoreable: seal round - 1 with `prev` so
    ///      the open round settles against it on its own seal.
    function _openScoreable(uint48 prev) internal returns (uint24 round) {
        round = _openWindow();
        _push(round - 1, prev);
    }

    function _bet(address who, bool over) internal {
        vm.prank(who);
        parimutuel.placeVolumeBet(address(0), over);
    }

    function _claimOne(address who, uint24 round) internal returns (uint256) {
        uint24[] memory rounds = new uint24[](1);
        rounds[0] = round;
        vm.prank(who);
        return parimutuel.claimVolume(who, rounds);
    }

    function _flipReach(address who) internal view returns (uint256) {
        return coin.balanceOfWithClaimable(who) + coinflip.coinflipAmount(who);
    }

    function _list3(
        address a,
        address b,
        address c
    ) internal pure returns (address[] memory out) {
        out = new address[](3);
        out[0] = a;
        out[1] = b;
        out[2] = c;
    }

    // =====================================================================
    // Counter mechanics on the real storage helpers
    // =====================================================================

    /// The volume counter rides the purchase RMW: an unfrozen contribution lands raw
    /// ticket units in the live counter alongside the pool halves.
    function testCounterAccumulatesInTheLiveSlot() public {
        VolumeCounterHarness h = new VolumeCounterHarness();
        h.apc(uint128(3 ether), uint128(1 ether), 25);
        h.apc(0, 0, 75);
        assertEq(h.liveVolume(), 100, "units must accumulate in the live counter");
        (uint128 next, uint128 future) = h.pools();
        assertEq(next, 3 ether, "the pool halves ride the same write");
        assertEq(future, 1 ether, "the pool halves ride the same write");
    }

    /// A zero-prize purchase still counts: the zero-check spans all three fields, so an
    /// ETH buy whose prize share rounds to nothing still lands its volume.
    function testZeroPrizeContributionStillCounts() public {
        VolumeCounterHarness h = new VolumeCounterHarness();
        h.apc(0, 0, 40);
        assertEq(h.liveVolume(), 40, "volume must count without a prize contribution");
    }

    /// Frozen contributions route to the pending counter; the fold ADDS the pool halves
    /// but ROLLS the counter — pending replaces live, because the live total was read and
    /// scored at the freeze and the pending buys belong to the next round.
    function testFoldAddsPoolsAndRollsTheCounter() public {
        VolumeCounterHarness h = new VolumeCounterHarness();
        h.apc(uint128(2 ether), 0, 30); // live: 30 units, 2 ETH next

        h.setFrozen(true);
        h.apc(uint128(5 ether), uint128(1 ether), 70); // pending: 70 units
        assertEq(h.liveVolume(), 30, "frozen buys must not move the live counter");

        h.fold();
        assertEq(h.liveVolume(), 70, "the fold must roll the pending counter in");
        (uint128 next, uint128 future) = h.pools();
        assertEq(next, 7 ether, "the fold must add the next halves");
        assertEq(future, 1 ether, "the fold must add the future halves");
        assertEq(h.pendingRaw(), 0, "the fold must zero the pending slot");
    }

    // =====================================================================
    // The push: recordVolume as the game's act
    // =====================================================================

    function testPushRejectsForeignCaller() public {
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.OnlyGame.selector);
        parimutuel.recordVolume(5, 100);
    }

    /// The first seal has no predecessor: it stores the benchmark and settles nothing.
    function testFirstSealSettlesNothing() public {
        uint24 round = _openWindow();
        _push(round - 1, 500);

        (, , , , , uint8 outcome, bool voided, ) = parimutuel.volumeMarketState(
            alice,
            round - 1
        );
        assertEq(outcome, 0, "the first sealed round must have no outcome");
        assertTrue(voided, "the first sealed round is closed and unscoreable: voided");
    }

    /// An adjacent seal scores strictly: more volume than the predecessor is OVER, a tie
    /// belongs to the UNDER.
    function testAdjacentSealScoresStrictlyGreater() public {
        uint24 round = _openScoreable(100);

        _push(round, 101);
        (, , , , , uint8 outcome, , ) = parimutuel.volumeMarketState(alice, round);
        assertEq(outcome, 1, "more volume than the benchmark must resolve OVER");

        _push(round + 1, 101);
        (, , , , , uint8 tied, , ) = parimutuel.volumeMarketState(alice, round + 1);
        assertEq(tied, 2, "an exact tie must resolve UNDER");

        _push(round + 2, 100);
        (, , , , , uint8 under, , ) = parimutuel.volumeMarketState(alice, round + 2);
        assertEq(under, 2, "less volume than the benchmark must resolve UNDER");
    }

    /// A seal that jumps rounds — a VRF stall swallowed the days between — scores nothing:
    /// the resuming round's span covers several days and no adjacent comparison exists.
    /// The benchmark still rolls, so the round after the resume scores normally.
    function testGapSealVoidsButRollsTheBenchmark() public {
        uint24 round = _openScoreable(100);

        _push(round + 3, 400); // the stall: rounds round..round+2 never sealed
        (, , , , , uint8 outcome, bool voided, ) = parimutuel.volumeMarketState(
            alice,
            round + 3
        );
        assertEq(outcome, 0, "a gap seal must not score against a stale benchmark");
        assertTrue(voided, "the resuming round is closed and unscoreable: voided");

        _push(round + 4, 500);
        (, , , , , uint8 next, , ) = parimutuel.volumeMarketState(alice, round + 4);
        assertEq(next, 1, "the round after the resume must score against the roll");
    }

    /// The outcome latch is write-once: no later push can revise a settled round.
    function testOutcomeLatchIsWriteOnce() public {
        uint24 round = _openScoreable(100);
        _push(round, 200); // OVER

        // A hostile replay of the same adjacency cannot flip the bit.
        vm.prank(address(game));
        parimutuel.recordVolume(round, 200);
        (, , , , , uint8 outcome, , ) = parimutuel.volumeMarketState(alice, round);
        assertEq(outcome, 1, "a settled round's answer is permanent");
    }

    // =====================================================================
    // Placement
    // =====================================================================

    /// The window is the 1h03m from the day break to midnight UTC, computed off the
    /// clock alone — no game call.
    function testWindowOpensAtTheDayBreak() public {
        uint24 round = _openScoreable(100);

        // Inside the window: the bet books to the open round.
        _fund(alice, STAKE);
        _bet(alice, true);
        (, uint128 overCount, , uint8 side, , , , ) = parimutuel.volumeMarketState(
            alice,
            round
        );
        assertEq(overCount, 1, "an in-window bet must book");
        assertEq(side, 1, "the side must record");

        // Past midnight: closed.
        vm.warp(block.timestamp + 2 hours);
        _fund(bob, STAKE);
        vm.prank(bob);
        vm.expectRevert(DegenerusParimutuel.MarketClosed.selector);
        parimutuel.placeVolumeBet(address(0), true);
    }

    /// Before anything has sealed the open round has no benchmark and could only void, so
    /// the market reads closed rather than open-and-worthless.
    function testMarketClosedBeforeTheFirstSeal() public {
        _openWindow();
        _fund(alice, STAKE);
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.MarketClosed.selector);
        parimutuel.placeVolumeBet(address(0), true);
    }

    /// The lifetime bar, unmocked: a wallet that never bought anything may not bet.
    function testNeverBoughtPlayerCannotBet() public {
        _openScoreable(100);
        _fundNoGate(alice, STAKE);
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeVolumeBet(address(0), true);
    }

    /// Past the lifetime bar but short of the level quest: the bet books, the credit does
    /// not. The gate splits exactly there.
    function testGatedCreditPaysEligibleOnly() public {
        _openScoreable(100);

        _fund(alice, STAKE); // (true, true): bet + credit
        uint256 aliceBefore = _flipReach(alice);
        _bet(alice, true);
        assertEq(
            aliceBefore - _flipReach(alice),
            STAKE - CREDIT,
            "an eligible bettor nets the stake less the placement credit"
        );

        _fundNoGate(bob, STAKE);
        _gate(bob, true, false); // lifetime yes, quest no
        uint256 bobBefore = _flipReach(bob);
        _bet(bob, false);
        assertEq(
            bobBefore - _flipReach(bob),
            STAKE,
            "a bettor short of the quest gate pays the full stake and earns no credit"
        );
    }

    /// The credit's ladder: 25 through 23:24:59 (the decay clock anchors at 23:15 but
    /// the first full step elapses at 23:25), then -5 per ten minutes, holding 5 from
    /// 23:55 through the window's close. One bettor per step, all inside one window on
    /// one round, with the quote view pinned against what each placement actually paid.
    function testCreditDecaysThroughTheWindow() public {
        _openScoreable(100);
        uint256 dayBase = block.timestamp - (block.timestamp % 1 days);

        uint256[7] memory tod = [
            uint256(83_699), // 23:14:59 — before the decay anchor
            84_299, // 23:24:59 — anchored but no full step elapsed
            84_300, // 23:25:00 — first drop
            84_900, // 23:35
            85_500, // 23:45
            86_100, // 23:55 — the floor step
            86_399 // 23:59:59 — last second of the window
        ];
        uint256[7] memory expected = [
            uint256(25 ether),
            25 ether,
            20 ether,
            15 ether,
            10 ether,
            5 ether,
            5 ether
        ];

        for (uint256 i; i < 7; ++i) {
            address p = address(uint160(0xDECA10 + i));
            _fund(p, STAKE);
            vm.warp(dayBase + tod[i]);
            assertEq(
                parimutuel.volumeBetCredit(),
                expected[i],
                "the quote must follow the decay ladder"
            );
            uint256 before = _flipReach(p);
            _bet(p, i % 2 == 0);
            assertEq(
                before - _flipReach(p),
                STAKE - expected[i],
                "the placement must pay exactly what the quote reads"
            );
        }
    }

    function testSecondBetSameRoundReverts() public {
        _openScoreable(100);
        _fund(alice, STAKE * 2);
        _bet(alice, true);
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        parimutuel.placeVolumeBet(address(0), false);
    }

    /// The credit stays far under the stake, so a placement is deflationary on its own
    /// terms whatever the round later pays.
    function testPlacementIsNetDeflationary() public {
        _openScoreable(100);
        uint256 supplyBefore = coin.totalSupply();
        _fund(alice, STAKE);
        uint256 funded = coin.totalSupply() - supplyBefore;
        _bet(alice, true);
        assertLt(
            coin.totalSupply(),
            supplyBefore + funded,
            "a placement must burn more than it credits"
        );
    }

    // =====================================================================
    // Claim and the void refund
    // =====================================================================

    /// Winners split the whole book; the loser takes nothing.
    function testSettledRoundPaysTheWinningSide() public {
        uint24 round = _openScoreable(100);
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _fund(carol, STAKE);
        _bet(alice, true);
        _bet(bob, true);
        _bet(carol, false);

        _push(round, 200); // OVER

        assertEq(_claimOne(alice, round), (STAKE * 3) / 2, "winners split the book");
        assertEq(_claimOne(bob, round), (STAKE * 3) / 2, "winners are paid identically");
        assertEq(_claimOne(carol, round), 0, "the loser is paid nothing");
    }

    /// An open round pays nothing yet: no bit, and the round is not past.
    function testOpenRoundIsNotClaimable() public {
        uint24 round = _openScoreable(100);
        _fund(alice, STAKE);
        _bet(alice, true);
        assertEq(_claimOne(alice, round), 0, "an open round must pay nothing");
    }

    /// A round that closed without a bit refunds the stake — BOTH sides. Nobody was
    /// scored, so nobody may profit; the refund is flat and once-only.
    function testVoidedRoundRefundsBothSidesOnce() public {
        uint24 round = _openScoreable(100);
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _bet(alice, true);
        _bet(bob, false);

        // The stall: the next seal jumps clean past the bet round.
        _push(round + 3, 400);

        assertEq(_claimOne(alice, round), STAKE, "OVER side takes the stake back");
        assertEq(_claimOne(bob, round), STAKE, "UNDER side takes the stake back");
        assertEq(_claimOne(alice, round), 0, "the refund is once-only");

        (, , , , bool claimed, , bool voided, uint256 payout) = parimutuel
            .volumeMarketState(alice, round);
        assertTrue(voided, "the round must read voided");
        assertTrue(claimed, "the refund must latch the claimed bit");
        assertEq(payout, 0, "nothing may remain quotable");
    }

    /// The refund makes a voided book FLIP-neutral: everything burned comes back, nothing
    /// more.
    function testVoidedRoundIsFlipNeutral() public {
        uint24 round = _openScoreable(100);
        uint256 supplyBefore = coin.totalSupply();
        _fundNoGate(alice, STAKE);
        _gate(alice, true, false); // no credit: isolate the stake/refund pair
        _fundNoGate(bob, STAKE);
        _gate(bob, true, false);
        uint256 funded = coin.totalSupply() - supplyBefore;

        _bet(alice, true);
        _bet(bob, false);
        _push(round + 3, 400);
        _claimOne(alice, round);
        _claimOne(bob, round);

        assertLe(
            coin.totalSupply(),
            supplyBefore + funded,
            "a voided round must never mint net FLIP"
        );
    }

    // =====================================================================
    // Crank
    // =====================================================================

    /// One call pays every winner and the caller a per-winner bounty; the route tuple
    /// prices it exactly as the growth crank does.
    function testCrankPaysWinnersAndBounty() public {
        uint24 round = _openScoreable(100);
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _fund(carol, STAKE);
        _bet(alice, true);
        _bet(bob, true);
        _bet(carol, false);
        _push(round, 200); // OVER

        // Route tuple for the bounty price: level 50, purchase phase.
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(GROWTH_STATE, uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), uint24(50), false, uint8(0))
        );

        uint256 keeperBefore = _flipReach(keeper);
        vm.prank(keeper);
        uint256 total = parimutuel.claimVolumeRound(round, _list3(alice, bob, carol));
        assertEq(total, STAKE * 3, "the crank must pay out the whole book");
        assertEq(
            _flipReach(keeper) - keeperBefore,
            (2 * 15_000_000_000_000 * 1000 ether) / PriceLookupLib.priceForLevel(51),
            "two settled winners pay two bounties at the routed level"
        );
    }

    /// A voided round is not crankable — every position pays the same stake back, so
    /// there is no shared divisor to amortize; the named path handles it.
    function testCrankRefusesAVoidedRound() public {
        uint24 round = _openScoreable(100);
        _fund(alice, STAKE);
        _bet(alice, true);
        _push(round + 3, 400); // void the bet round

        vm.prank(keeper);
        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        parimutuel.claimVolumeRound(round, _list3(alice, bob, carol));
    }

    /// The opener probe: a spent list reverts on one cold read, before the outcome or any
    /// game call.
    function testCrankRevertsOnASweptOpener() public {
        uint24 round = _openScoreable(100);
        _fund(alice, STAKE);
        _fund(carol, STAKE);
        _bet(alice, true);
        _bet(carol, false);
        _push(round, 200);

        vm.mockCall(
            address(game),
            abi.encodeWithSelector(GROWTH_STATE, uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), uint24(50), false, uint8(0))
        );
        address[] memory list = _list3(alice, carol, address(0xDEAD));
        vm.prank(keeper);
        parimutuel.claimVolumeRound(round, list);

        vm.prank(keeper);
        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        parimutuel.claimVolumeRound(round, list);
    }

    // =====================================================================
    // Lifecycle: the real freeze pushes the real counter
    // =====================================================================

    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(
            keccak256(abi.encode(block.timestamp, game.level(), reqId))
        );
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    function _driveDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 j = 0; j < 200; j++) {
            _fulfillVrfIfPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
    }

    /// An ETH ticket buy lands its raw units in the day's counter, and the NEXT day's
    /// RNG request pushes exactly that total out as the sealed round. Counted raw:
    /// 4,000 purchase units, whatever the purchase boost grants on top — no per-call
    /// rounding, so fragmenting a buy cannot move the count.
    function testFreezePushesTheRealCounter() public {
        vm.pauseGasMetering();
        // Settle the deploy-day advance so the next drive is an ordinary daily cycle.
        _driveDay();

        address buyer = address(0xB0B5);
        vm.deal(buyer, 200 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        vm.prank(buyer);
        game.purchase{value: (priceWei * 4000) / 400}(
            buyer, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false
        );

        vm.recordLogs();
        _driveDay(); // the day break: RNG request freezes and pushes the seal

        bytes32 sig = keccak256("VolumeRoundSealed(uint24,uint48,uint48)");
        bool sawSeal;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(parimutuel) || logs[i].topics[0] != sig) {
                continue;
            }
            sawSeal = true;
            (uint48 total, ) = abi.decode(logs[i].data, (uint48, uint48));
            assertEq(
                total,
                4000,
                "the sealed total must be the buy's raw units"
            );
        }
        assertTrue(sawSeal, "the day break must push a sealed round");
    }
}
