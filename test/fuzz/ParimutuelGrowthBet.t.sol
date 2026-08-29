// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @dev Exposes _growthRatchet and the two entries it chooses between. Inheriting the real
///      storage layout rather than pinning slots keeps this honest if the layout moves.
contract GrowthRatchetHarness is DegenerusGameStorage {
    function setLevelPool(uint24 lvl, uint256 value) external {
        levelPrizePool[lvl] = value;
    }

    function pushCentury(uint128 value) external {
        centuryPrizePools.push(value);
    }

    function ratchet(uint24 lvl) external view returns (uint256) {
        return _growthRatchet(lvl);
    }
}

/// @dev Exposes the transition's growth comparison — the cross-multiplied scoring the
///      game evaluates once per level and pushes to the market as a settled bit.
contract GrowthMathHarness is DegenerusGameAdvanceModule {
    function over(
        uint256 prevR,
        uint256 currR,
        uint256 nextR
    ) external pure returns (bool) {
        return _growthOver(prevR, currR, nextR);
    }
}

/// @title ParimutuelGrowthBet -- the growth-bet parimutuel.
///
/// @notice Two halves. The scoring half drives DegenerusParimutuel with settlement
///         pushes pranked as GAME — the transition's own act — plus the extracted
///         comparison targeted directly, so arbitrary ratchet histories (contractions,
///         exact ties) are reachable without simulating a hundred levels; FLIP,
///         Coinflip and Quests stay REAL throughout, so the burn/credit conservation
///         assertions are load-bearing. The lifecycle half drives the real advance path
///         end to end: bet during a jackpot phase, transition, claim — the push landing
///         from the real transition, nothing pranked.
contract ParimutuelGrowthBetTest is DeployProtocol {
    // growthState(uint24) — the scoring half mocks only the key-0 route tuple; ratchet
    // terms left the market's reads entirely (settlement arrives as a pushed bit).
    bytes4 private constant GROWTH_STATE = bytes4(keccak256("growthState(uint24)"));
    bytes4 private constant IS_OP_APPROVED =
        bytes4(keccak256("isOperatorApproved(address,address)"));
    bytes4 private constant MARKET_GATES =
        bytes4(keccak256("marketBetGates(address,uint24)"));

    uint256 private constant STAKE = 1_000 ether;

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

    /// @dev Mint FLIP through the GAME-gated path, and clear the lifetime bet gate: a
    ///      funded bettor in these tests stands for a player who has bought before, so
    ///      the gate is pinned open per player (prefix match — any level).
    function _fund(address who, uint256 amount) internal {
        _fundNoGate(who, amount);
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(MARKET_GATES, who),
            abi.encode(true, true)
        );
    }

    /// @dev Fund WITHOUT clearing the gate — for the never-bought case, where the real
    ///      quests answer (mintPackedFor == 0) is the subject.
    function _fundNoGate(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    /// @dev Pin game.growthState(round) to a fixed tuple.
    function _mockState(
        uint24 round,
        uint256 ratchetPrev,
        uint256 ratchetRound,
        uint256 ratchetNext,
        uint24 currentLevel,
        bool open,
        uint8 phaseDay
    ) internal {
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(GROWTH_STATE, round),
            abi.encode(
                ratchetPrev,
                ratchetRound,
                ratchetNext,
                currentLevel,
                open,
                phaseDay
            )
        );
    }

    /// @dev Open the market at `currentLevel`. growthState(0) is the one key every path
    ///      asks now — placement, view and crank all read only the route tuple. The round
    ///      key is mocked too for older shapes, harmlessly.
    function _mockOpenAt(uint24 currentLevel, uint8 phaseDay, bool open) internal {
        _mockState(0, 0, 0, 0, currentLevel, open, phaseDay);
        _mockState(currentLevel, 0, 0, 0, currentLevel, open, phaseDay);
    }

    function _bet(address who, bool over) internal {
        vm.prank(who);
        parimutuel.placeBet(address(0), over);
    }

    function _claimOne(address who, uint24 round) internal returns (uint256) {
        uint24[] memory rounds = new uint24[](1);
        rounds[0] = round;
        vm.prank(who);
        return parimutuel.claim(who, rounds);
    }

    /// @dev Total FLIP a player can currently reach: wallet balance, settled coinflip
    ///      winnings, and the stake still riding on an unsettled flip. creditFlip books a
    ///      payout as that third term, which balanceOfWithClaimable does not span — it
    ///      counts only what previewClaimCoinflips already resolved.
    function _flipReach(address who) internal view returns (uint256) {
        return
            coin.balanceOfWithClaimable(who) + coinflip.coinflipAmount(who);
    }

    // =====================================================================
    // Scoring: outcome derivation
    // =====================================================================

    /// A round resolves OVER only when the next level's growth RATE strictly exceeds its own.
    function testOutcomeOverRequiresStrictAcceleration() public {
        // growth(50) = 100/40 = 2.5x. growth(51) = 300/100 = 3.0x > 2.5x -> OVER. The
        // comparison is the game's, evaluated at the transition; the market receives it.
        GrowthMathHarness math = new GrowthMathHarness();
        assertTrue(
            math.over(40 ether, 100 ether, 300 ether),
            "accelerating growth must score OVER"
        );

        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, false);

        _settleOver(50);

        (, , , , , , uint8 outcome, ) = parimutuel.marketState(alice, 50);
        assertEq(outcome, 1, "the pushed OVER must be the round's outcome");

        assertGt(_claimOne(alice, 50), 0, "OVER bettor must be paid");
        assertEq(_claimOne(bob, 50), 0, "UNDER bettor must be paid nothing");
    }

    /// An exact tie is not acceleration, so it resolves UNDER.
    function testOutcomeTieResolvesUnder() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        // growth(50) = 100/40 = 2.5x. growth(51) = 250/100 = 2.5x — equal, not greater.
        _settle(50, false);

        (, , , , , , uint8 outcome, ) = parimutuel.marketState(alice, 50);
        assertEq(outcome, 2, "an exact tie must resolve UNDER");
        assertEq(_claimOne(alice, 50), 0, "the OVER bettor loses a tie");
    }

    /// A contracting level is just a ratio below 1, and a shallower contraction still
    /// beats a deeper one. An absolute-difference subject would rank these the same way only
    /// by accident; the ratio makes it the definition.
    function testOutcomeShallowerContractionBeatsDeeper() public {
        // growth(50) = 100/300 = 0.33x. growth(51) = 90/100 = 0.9x > 0.33x -> OVER.
        GrowthMathHarness math = new GrowthMathHarness();
        assertTrue(
            math.over(300 ether, 100 ether, 90 ether),
            "a shallower contraction must score OVER"
        );

        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        _settleOver(50);

        (, , , , , , uint8 outcome, ) = parimutuel.marketState(alice, 50);
        assertEq(outcome, 1, "a shallower contraction must still resolve OVER");
        assertGt(_claimOne(alice, 50), 0, "the shallower-contraction OVER side must be paid");
    }

    /// Both levels contracted and the subject contracted HARDER -> UNDER.
    function testOutcomeDeepeningContractionResolvesUnder() public {
        // growth(50) = 100/110 = 0.91x. growth(51) = 1 wei / 100 ETH ~ 0 -> UNDER.
        GrowthMathHarness math = new GrowthMathHarness();
        assertFalse(
            math.over(110 ether, 100 ether, 1),
            "a deepening contraction must score UNDER"
        );

        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        _settle(50, false);
        (, , , , , , uint8 outcome, ) = parimutuel.marketState(alice, 50);
        assertEq(outcome, 2, "a deepening contraction must resolve UNDER");
    }

    /// A round stays unsettled until the transition that banks its successor entry pushes
    /// the bit. `level` is promoted one RNG request BEFORE that transition, so "the level
    /// moved on" is not a sound settled-predicate; an unwritten bit is.
    function testRoundUnsettledUntilSuccessorPoolBanked() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        // Level has already advanced to 51, but no transition has pushed round 50's bit.
        _mockState(0, 0, 0, 0, 51, false, 0);

        (, , , , , , uint8 outcome, uint256 payout) = parimutuel.marketState(alice, 50);
        assertEq(outcome, 0, "a round must stay unsettled while its successor entry is 0");
        assertEq(payout, 0, "an unsettled round must quote no payout");
        assertEq(_claimOne(alice, 50), 0, "an unsettled round must pay nothing");
    }

    // =====================================================================
    // Century + genesis skips
    // =====================================================================

    /// _endPhase overwrites levelPrizePool[x00], but the game serves every century term
    /// from the pushed achieved pool instead, so the three boundary rounds are ordinary
    /// rounds and take bets like any other.
    function testCenturyRoundsAcceptBets() public {
        uint24[3] memory boundary = [uint24(199), uint24(200), uint24(201)];
        for (uint256 i; i < boundary.length; ++i) {
            _fund(alice, STAKE);
            _mockOpenAt(boundary[i], 0, true);
            _bet(alice, true);
            (uint24 openRound, , , , uint8 side, , , ) = parimutuel.marketState(
                alice,
                boundary[i]
            );
            assertEq(openRound, boundary[i], "a century boundary round must be open");
            assertEq(side, 1, "the bet must be recorded");
        }
    }

    /// The neighbours of the skipped band still take bets, so the skip is three rounds
    /// wide and not a level more.
    function testCenturyNeighboursStillOpen() public {
        uint24[2] memory live = [uint24(198), uint24(202)];
        for (uint256 i; i < live.length; ++i) {
            _fund(alice, STAKE);
            _mockOpenAt(live[i], 0, true);
            _bet(alice, true);
            (uint24 openRound, , , , uint8 side, , , ) = parimutuel.marketState(
                alice,
                live[i]
            );
            assertEq(openRound, live[i], "round adjacent to a century must be open");
            assertEq(side, 1, "the bet must be recorded");
        }
    }

    /// Round 0 is the sole skip: growthState reports no ratchet terms for it, so it could
    /// never settle and a stake left there would strand.
    function testRoundZeroRefusesBets() public {
        _fund(alice, STAKE);
        _mockOpenAt(0, 0, true);
        vm.prank(alice);
        vm.expectRevert();
        parimutuel.placeBet(address(0), true);
    }

    /// Round 1 needs no case of its own: its reference is BOOTSTRAP_PRIZE_POOL, written at
    /// construction and every bit as permanent as a banked entry, so the game scores it
    /// normally and the market takes its bet like any other round.
    function testRoundOneScoresOffBootstrap() public {
        // growth(1) = 40/10 = 4x. growth(2) = 200/40 = 5x > 4x -> OVER.
        GrowthMathHarness math = new GrowthMathHarness();
        assertTrue(
            math.over(10 ether, 40 ether, 200 ether),
            "round 1 must score against the bootstrap reference"
        );

        _fund(alice, STAKE);
        _mockOpenAt(1, 0, true);
        _bet(alice, true);

        _settleOver(1);
        (, , , , , , uint8 outcome, ) = parimutuel.marketState(alice, 1);
        assertEq(outcome, 1, "round 1 settles like any other round");
        assertEq(_claimOne(alice, 1), STAKE, "the uncontested winner takes the stake back");
    }

    // =====================================================================
    // Century ratchet substitution
    // =====================================================================

    /// The reason boundary rounds are scoreable at all: a century level's term comes from
    /// the pushed achieved pool, so _endPhase rewriting levelPrizePool[x00] to futurePool/3
    /// cannot move it. Without this, the same round answers one way during the century's
    /// jackpot phase and the other way after — paying both sides and minting FLIP.
    function testCenturyTermIgnoresTheEndPhaseOverwrite() public {
        GrowthRatchetHarness h = new GrowthRatchetHarness();
        h.pushCentury(900 ether); // level 100's achieved pool, snapshotted at transition

        // Pre-overwrite: levelPrizePool[100] still holds the achieved value.
        h.setLevelPool(100, 900 ether);
        assertEq(h.ratchet(100), 900 ether, "century term must read the pushed pool");

        // _endPhase lands and rewrites the entry to the reachable x01 base.
        h.setLevelPool(100, 7 ether);
        assertEq(
            h.ratchet(100),
            900 ether,
            "the overwrite must not move the century term"
        );
    }

    /// A century that has not completed reads 0 — the market's unsettled predicate — rather
    /// than reverting out of bounds and bricking marketState/claim for the x99 round.
    function testUncompletedCenturyReadsZeroRatherThanReverting() public {
        GrowthRatchetHarness h = new GrowthRatchetHarness();
        assertEq(h.ratchet(100), 0, "an uncompleted century must read 0");
        assertEq(h.ratchet(200), 0, "a far-future century must read 0");

        h.pushCentury(500 ether);
        assertEq(h.ratchet(100), 500 ether, "century 1 resolves once pushed");
        assertEq(h.ratchet(200), 0, "century 2 is still uncompleted");
    }

    /// Level 0 is excluded from the century branch, so round 1 keeps reading the seeded
    /// BOOTSTRAP_PRIZE_POOL instead of a century that will never exist.
    function testLevelZeroReadsTheSeededEntryNotACentury() public {
        GrowthRatchetHarness h = new GrowthRatchetHarness();
        h.setLevelPool(0, 50 ether);
        assertEq(h.ratchet(0), 50 ether, "level 0 must read its seeded ratchet entry");
    }

    /// Non-century levels are untouched by the substitution.
    function testNonCenturyLevelsReadLevelPrizePool() public {
        GrowthRatchetHarness h = new GrowthRatchetHarness();
        h.pushCentury(900 ether);
        h.setLevelPool(99, 400 ether);
        h.setLevelPool(101, 600 ether);
        assertEq(h.ratchet(99), 400 ether, "x99 reads levelPrizePool");
        assertEq(h.ratchet(101), 600 ether, "x01 reads levelPrizePool");
    }

    // =====================================================================
    // Stake, access and one-bet-per-address
    // =====================================================================

    /// The stake is fixed, so exactly one ticket's worth of FLIP leaves the bettor.
    function testFixedStakeBurnsExactlyOneTicket() public {
        _fund(alice, STAKE + 7 ether);
        uint256 before = _flipReach(alice);

        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        assertEq(
            before - _flipReach(alice),
            STAKE,
            "a bet must cost exactly the fixed stake"
        );
    }

    function testSecondBetSameRoundReverts() public {
        _fund(alice, STAKE * 2);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        vm.prank(alice);
        vm.expectRevert();
        parimutuel.placeBet(address(0), false);
    }

    /// A bet spends the player's FLIP, so it stays on the gated side: an unapproved third
    /// party cannot place one on someone else's behalf.
    function testUnapprovedThirdPartyCannotBet() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);

        vm.mockCall(
            address(game),
            abi.encodeWithSelector(IS_OP_APPROVED, alice, bob),
            abi.encode(false)
        );
        vm.prank(bob);
        vm.expectRevert();
        parimutuel.placeBet(alice, true);
    }

    /// An approved operator may bet, and the bet belongs to the player — not the operator.
    function testApprovedOperatorBetsForPlayer() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);

        vm.mockCall(
            address(game),
            abi.encodeWithSelector(IS_OP_APPROVED, alice, bob),
            abi.encode(true)
        );
        uint256 aliceBefore = _flipReach(alice);
        uint256 bobBefore = _flipReach(bob);

        vm.prank(bob);
        parimutuel.placeBet(alice, true);

        (, , , , uint8 aliceSide, , , ) = parimutuel.marketState(alice, 50);
        (, , , , uint8 bobSide, , , ) = parimutuel.marketState(bob, 50);
        assertEq(aliceSide, 1, "the bet must be recorded to the player");
        assertEq(bobSide, 0, "the operator must hold no position");
        assertEq(
            aliceBefore - _flipReach(alice),
            STAKE,
            "the player's FLIP must fund it"
        );
        assertEq(_flipReach(bob), bobBefore, "the operator must pay nothing");
    }

    /// Betting is shut outside the jackpot phase, during the daily RNG window, and after
    /// game over — all three collapse into the single bettingOpen term.
    function testClosedMarketRefusesBets() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, false);
        vm.prank(alice);
        vm.expectRevert();
        parimutuel.placeBet(address(0), true);
    }

    // =====================================================================
    // Payout
    // =====================================================================

    /// Every winner is paid the same, and the pot is the whole book.
    function testPayoutUniformAcrossWinners() public {
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _fund(carol, STAKE);

        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, true);
        _bet(carol, false); // one loser funds the two winners

        _settleOver(50);

        uint256 aliceOut = _claimOne(alice, 50);
        uint256 bobOut = _claimOne(bob, 50);
        assertEq(aliceOut, bobOut, "a fixed stake must pay every winner identically");
        assertEq(
            aliceOut,
            (STAKE * 3) / 2,
            "two winners must split a three-bet pot evenly"
        );
        assertEq(_claimOne(carol, 50), 0, "the loser must be paid nothing");
    }

    /// An empty losing side needs no special case: the payout collapses to the stake back.
    function testEmptyLosingSidePaysStakeBack() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        _settleOver(50);
        assertEq(
            _claimOne(alice, 50),
            STAKE,
            "an uncontested winner must get exactly the stake back"
        );
    }

    /// When the winning side is empty nobody can claim, so the losing side stays burned.
    /// That is deflationary, never inflationary — the failure direction that matters.
    function testEmptyWinningSideLeavesStakesBurned() public {
        uint256 supplyBefore = coin.totalSupply();
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        assertEq(coin.totalSupply(), supplyBefore + 2 * STAKE, "funding sanity");

        _mockOpenAt(50, 0, true);
        _bet(alice, false);
        _bet(bob, false); // nobody took OVER

        // ...and OVER wins.
        _settleOver(50);

        assertEq(_claimOne(alice, 50), 0, "a losing bettor must claim nothing");
        assertEq(_claimOne(bob, 50), 0, "a losing bettor must claim nothing");
        assertEq(
            coin.totalSupply(),
            supplyBefore,
            "both stakes must stay burned when no winner exists"
        );
    }

    /// A claim is once-only; the second is a silent no-op rather than a double payout.
    function testDoubleClaimPaysOnce() public {
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, false);

        _settleOver(50);

        uint256 first = _claimOne(alice, 50);
        assertGt(first, 0, "the first claim must pay");
        assertEq(_claimOne(alice, 50), 0, "a repeat claim must pay nothing");

        (, , , , , bool claimed, , uint256 quoted) = parimutuel.marketState(alice, 50);
        assertTrue(claimed, "the claimed bit must latch");
        assertEq(quoted, 0, "a claimed round must quote no payout");
    }

    /// Claiming is permissionless because it only ever credits the bettor: a stranger may
    /// crank it, and the FLIP still lands on the player.
    function testClaimIsPermissionlessAndCreditsTheBettor() public {
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, false);
        _settleOver(50);

        uint256 aliceBefore = _flipReach(alice);
        uint256 keeperBefore = _flipReach(keeper);

        uint24[] memory rounds = new uint24[](1);
        rounds[0] = 50;
        vm.prank(keeper);
        parimutuel.claim(alice, rounds);

        assertGt(_flipReach(alice), aliceBefore, "the bettor must receive the payout");
        assertEq(_flipReach(keeper), keeperBefore, "the cranker must receive nothing");
    }

    /// The whole book is redistribution: winners can never be credited more FLIP than the
    /// round burned.
    function testRoundNeverMintsNetFlip() public {
        uint256 supplyBefore = coin.totalSupply();
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _fund(carol, STAKE);
        uint256 funded = coin.totalSupply() - supplyBefore;

        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, false);
        _bet(carol, false);
        _settleOver(50);

        _claimOne(alice, 50);
        _claimOne(bob, 50);
        _claimOne(carol, 50);

        assertLe(
            coin.totalSupply(),
            supplyBefore + funded,
            "a round must never mint net FLIP"
        );
    }

    /// A batch tolerates junk: unbet, unsettled and lost rounds are skipped instead of
    /// reverting, so one stale id cannot brick the rest.
    function testClaimBatchSkipsUnclaimableRounds() public {
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, false);
        _settleOver(50); // round 49: never bet, never pushed — stays unsettled

        uint24[] memory rounds = new uint24[](3);
        rounds[0] = 49;
        rounds[1] = 50;
        rounds[2] = 49;

        vm.prank(keeper);
        uint256 total = parimutuel.claim(alice, rounds);
        assertEq(total, STAKE * 2, "the settled round must still pay through a junk batch");
    }

    // =====================================================================
    // Crank: settling one round for many players
    // =====================================================================

    /// @dev Settle `round` OVER exactly as the game does: push the bit pranked as GAME,
    ///      and move the routing tuple past the round — level promoted, purchase phase —
    ///      which is where a just-settled round always finds the game.
    function _settleOver(uint24 round) internal {
        _settle(round, true);
    }

    function _settle(uint24 round, bool over) internal {
        vm.prank(address(game));
        parimutuel.recordGrowth(round, over);
        _mockState(0, 0, 0, 0, round + 1, false, 0);
    }

    function _crank(
        address caller,
        uint24 round,
        address[] memory players
    ) internal returns (uint256) {
        vm.prank(caller);
        return parimutuel.claimRound(round, players);
    }

    /// @dev The crank bounty for `settled` winners actually paid, priced at the ROUTED
    ///      level — jackpot phase targets `crankLevel`, purchase phase the next — mirroring
    ///      the Game's mintPrice and the decimator/foil bounties. _settle leaves the
    ///      route tuple at (round + 1, purchase phase), so the routed level is round + 2.
    ///      The 15e12 wei target is spelled out here rather than read off the contract, so
    ///      moving the constant fails these tests instead of silently re-scaling them.
    function _expectedBounty(
        uint256 settled,
        uint24 crankLevel,
        bool bettingOpen
    ) internal pure returns (uint256) {
        return
            (settled * 15_000_000_000_000 * 1000 ether) /
            PriceLookupLib.priceForLevel(
                bettingOpen ? crankLevel : crankLevel + 1
            );
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

    /// @dev Three bettors on round 50 — alice and bob on OVER, carol on UNDER — with the round
    ///      pinned so OVER takes it. Two winners split a three-bet pot.
    function _threeBetRound() internal {
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _fund(carol, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, true);
        _bet(carol, false);
        _settleOver(50);
    }

    /// One call settles the whole book: every winner is paid, the loser is not.
    function testCrankPaysEveryWinnerOnTheRound() public {
        _threeBetRound();
        uint256 carolBefore = _flipReach(carol);

        uint256 total = _crank(keeper, 50, _list3(alice, bob, carol));
        assertEq(total, STAKE * 3, "the crank must pay out the whole book");
        assertEq(_flipReach(carol), carolBefore, "the losing side must be paid nothing");
    }

    /// The outcome and the per-winner payout are properties of the round, so every winner
    /// on it is paid the same amount.
    function testCrankPaysEveryWinnerTheSameShare() public {
        _threeBetRound();
        uint256 aliceBefore = _flipReach(alice);
        uint256 bobBefore = _flipReach(bob);

        _crank(keeper, 50, _list3(alice, bob, carol));
        assertEq(
            _flipReach(alice) - aliceBefore,
            (STAKE * 3) / 2,
            "each winner takes an equal share of the three-bet pot"
        );
        assertEq(
            _flipReach(bob) - bobBefore,
            (STAKE * 3) / 2,
            "both winners must be paid identically"
        );
    }

    /// A repeated address is paid once: its first pass sets the claimed bit.
    function testCrankPaysARepeatedAddressOnce() public {
        _threeBetRound();
        uint256 total = _crank(keeper, 50, _list3(alice, alice, alice));
        assertEq(total, (STAKE * 3) / 2, "a duplicated winner must be paid a single share");
    }

    /// Junk entries PAST THE OPENER are skipped rather than reverted, so one bad address
    /// cannot brick the batch for everyone else.
    function testCrankToleratesAddressesThatNeverBet() public {
        _threeBetRound();
        uint256 total = _crank(keeper, 50, _list3(alice, keeper, address(0xDEAD)));
        assertEq(total, (STAKE * 3) / 2, "the one real winner in the list must still be paid");
    }

    /// A settled round whose winning side is empty has nobody to pay — and no divisor.
    /// The crank must refuse rather than revert on the payout division.
    function testCrankOnEmptyWinningSideReverts() public {
        uint256 supplyBefore = coin.totalSupply();
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        uint256 funded = coin.totalSupply() - supplyBefore;

        _mockOpenAt(50, 0, true);
        _bet(alice, false);
        _bet(bob, false); // everyone on UNDER...
        _settleOver(50); // ...and the round resolves OVER

        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        _crank(keeper, 50, _list3(alice, bob, carol));
        assertLe(
            coin.totalSupply(),
            supplyBefore + funded,
            "the losing stakes must stay burned"
        );
    }

    /// An unsettled round settles nothing, so the crank refuses it — and the same list
    /// works once it settles.
    function testCrankOnUnsettledRoundRevertsThenPaysOnceSettled() public {
        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(bob, false);

        address[] memory list = _list3(alice, bob, carol);
        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        _crank(keeper, 50, list);

        _settleOver(50);
        assertEq(_crank(keeper, 50, list), STAKE * 2, "the settled round must pay the winner");
    }

    /// An empty list settles nothing and is refused rather than succeeding as a no-op.
    function testCrankOnEmptyListReverts() public {
        _threeBetRound();
        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        _crank(keeper, 50, new address[](0));
    }

    /// The opener is the spent-list probe: a list whose first address is already paid
    /// reverts instead of walking the rest for nothing, so the loser of a crank race
    /// fails its simulation rather than paying for the whole walk.
    function testCrankRevertsOnAnAlreadySweptOpener() public {
        _threeBetRound();
        address[] memory list = _list3(alice, bob, carol);
        _crank(keeper, 50, list);

        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        _crank(keeper, 50, list);
    }

    /// The opener must be a WINNER, not merely a bettor: a loser in front reverts.
    function testCrankRevertsOnALosingOpener() public {
        _threeBetRound();
        vm.expectRevert(DegenerusParimutuel.NothingToSettle.selector);
        _crank(keeper, 50, _list3(carol, alice, bob));
    }

    /// Permissionless, and paid for the work: the crank credits the bettors their payouts
    /// and the caller a gas-pegged bounty per winner it actually settled.
    function testCrankIsPermissionlessAndCreditsTheBettors() public {
        _threeBetRound();
        uint256 keeperBefore = _flipReach(keeper);
        uint256 aliceBefore = _flipReach(alice);

        _crank(keeper, 50, _list3(alice, bob, carol));
        assertGt(_flipReach(alice), aliceBefore, "the bettor must receive the payout");
        assertEq(
            _flipReach(keeper) - keeperBefore,
            _expectedBounty(2, 51, false),
            "the cranker must earn the bounty for the two winners it settled"
        );
    }

    /// A player who already claimed for themselves is skipped by the crank — and earns
    /// the cranker no bounty, since no claim was paid for them.
    function testCrankDoesNotRepayANamedClaim() public {
        _threeBetRound();

        uint24[] memory rounds = new uint24[](1);
        rounds[0] = 50;
        vm.prank(alice);
        assertEq(
            parimutuel.claim(alice, rounds),
            (STAKE * 3) / 2,
            "the named claim must pay alice her share"
        );

        uint256 keeperBefore = _flipReach(keeper);
        // bob leads: alice is spent, and a spent opener would refuse the whole call.
        uint256 total = _crank(keeper, 50, _list3(bob, alice, carol));
        assertEq(total, (STAKE * 3) / 2, "the crank must pay only the share still owed");
        assertEq(
            _flipReach(keeper) - keeperBefore,
            _expectedBounty(1, 51, false),
            "only the one winner actually settled may earn a bounty"
        );
    }

    /// Every winner reads as claimed afterwards, with nothing left owing.
    function testCrankMarksWinnersClaimed() public {
        _threeBetRound();
        _crank(keeper, 50, _list3(alice, bob, carol));

        (, , , , uint8 side, bool claimed, uint8 outcome, uint256 payout) = parimutuel
            .marketState(alice, 50);
        assertEq(side, 1, "the side must survive the crank");
        assertTrue(claimed, "the crank must set the claimed bit");
        assertEq(outcome, 1, "the round stays settled OVER");
        assertEq(payout, 0, "nothing may remain claimable");
    }

    /// The bounty is per winner ACTUALLY PAID, so it scales with settled count.
    function testCrankBountyScalesWithWinnersSettled() public {
        // Round 50: two winners on OVER, one loser.
        _threeBetRound();
        uint256 beforeTwo = _flipReach(keeper);
        _crank(keeper, 50, _list3(alice, bob, carol));
        uint256 earnedTwo = _flipReach(keeper) - beforeTwo;

        // Round 51: a single winner.
        _fund(alice, STAKE);
        _fund(carol, STAKE);
        _mockOpenAt(51, 0, true);
        _bet(alice, true);
        _bet(carol, false);
        _settleOver(51);

        uint256 beforeOne = _flipReach(keeper);
        _crank(keeper, 51, _list3(alice, carol, address(0xDEAD)));
        uint256 earnedOne = _flipReach(keeper) - beforeOne;

        assertEq(earnedTwo, _expectedBounty(2, 51, false), "two settled winners pay two bounties");
        assertEq(earnedOne, _expectedBounty(1, 52, false), "one settled winner pays one bounty");
        assertEq(earnedTwo, earnedOne * 2, "the bounty is linear in winners settled");
    }

    /// Losers, non-bettors and duplicates settle nothing, so padding a list earns the
    /// cranker nothing extra — the only anti-farm the bounty needs.
    function testCrankBountyIgnoresPaddedEntries() public {
        _threeBetRound();

        address[] memory padded = new address[](6);
        padded[0] = alice; // winner
        padded[1] = carol; // loser
        padded[2] = alice; // duplicate, already settled by index 0
        padded[3] = address(0xDEAD); // never bet
        padded[4] = bob; // winner
        padded[5] = keeper; // never bet

        uint256 keeperBefore = _flipReach(keeper);
        _crank(keeper, 50, padded);
        assertEq(
            _flipReach(keeper) - keeperBefore,
            _expectedBounty(2, 51, false),
            "a padded list may earn no more than its two genuine settlements"
        );
    }

    /// The crank reads no game-over state: FLIP is tombstoned there, so the credit is
    /// already worthless and the read would withhold nothing. Settlement is unchanged.
    function testCrankIsIndifferentToGameOver() public {
        _threeBetRound();
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(bytes4(keccak256("gameOver()"))),
            abi.encode(true)
        );

        uint256 keeperBefore = _flipReach(keeper);
        uint256 total = _crank(keeper, 50, _list3(alice, bob, carol));
        assertEq(total, STAKE * 3, "winners must still be paid the whole book");
        assertEq(
            _flipReach(keeper) - keeperBefore,
            _expectedBounty(2, 51, false),
            "the bounty is paid without consulting game-over state"
        );
    }

    /// The bounty rides the winners' batch in its tail slot, so a cranker that also won
    /// the round takes two slots. The stake write accumulates: it is paid its share AND
    /// its bounty, exactly as two separate credit calls would have paid.
    function testCrankBountyReachesACallerWhoAlsoWon() public {
        _fund(alice, STAKE);
        _fund(keeper, STAKE);
        _fund(carol, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(keeper, true);
        _bet(carol, false);
        _settleOver(50);

        uint256 keeperBefore = _flipReach(keeper);
        _crank(keeper, 50, _list3(alice, keeper, carol));
        assertEq(
            _flipReach(keeper) - keeperBefore,
            (STAKE * 3) / 2 + _expectedBounty(2, 51, false),
            "a winning cranker takes its share and its bounty, neither swallowing the other"
        );
    }

    /// The bounty is the CRANK's, not the named claim's: claiming for yourself or for one
    /// player across rounds pays the payout and nothing else.
    function testNamedClaimPaysNoBounty() public {
        _threeBetRound();

        uint24[] memory rounds = new uint24[](1);
        rounds[0] = 50;
        uint256 keeperBefore = _flipReach(keeper);
        vm.prank(keeper);
        parimutuel.claim(alice, rounds);
        assertEq(
            _flipReach(keeper),
            keeperBefore,
            "the named claim pays the bettor only"
        );
    }

    /// The payout leg is pure redistribution — the winners split exactly the burned stakes
    /// and the loser gets nothing — so the caller's bounty is the only FLIP the crank
    /// creates beyond them. Asserted on reach rather than totalSupply: creditFlipBatch
    /// books a next-day coinflip stake and never moves the ERC-20 supply, so a supply
    /// assertion here would hold no matter what the bounty paid.
    function testCrankCreatesOnlyTheBountyBeyondTheBurnedStakes() public {
        _threeBetRound();
        uint256 aliceBefore = _flipReach(alice);
        uint256 bobBefore = _flipReach(bob);
        uint256 carolBefore = _flipReach(carol);
        uint256 keeperBefore = _flipReach(keeper);

        _crank(keeper, 50, _list3(alice, bob, carol));

        assertEq(
            (_flipReach(alice) - aliceBefore) + (_flipReach(bob) - bobBefore),
            STAKE * 3,
            "the winners must split exactly the three burned stakes"
        );
        assertEq(_flipReach(carol), carolBefore, "the losing side must be paid nothing");
        assertEq(
            _flipReach(keeper) - keeperBefore,
            _expectedBounty(2, 51, false),
            "the bounty is the only FLIP created beyond the burned stakes"
        );
    }

    /// The bounty is priced at the ROUTED level, mirroring the Game's mintPrice and the
    /// decimator/foil bounties: purchase phase targets the NEXT level. Pinned at the x00
    /// boundary, where routed (x01, 0.04 ETH) and raw (x00, 0.24 ETH) differ 6x — the one
    /// place a regression to the raw level is visible, since every other test sits inside
    /// a single price tier.
    function testCrankBountyPricesAtTheNextLevelInPurchasePhase() public {
        _fund(alice, STAKE);
        _fund(carol, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(carol, false);
        // Settled, sitting at level 100 in PURCHASE phase -> routed level is 101.
        _settle(50, true);
        _mockState(0, 0, 0, 0, 100, false, 0);

        uint256 before = _flipReach(keeper);
        _crank(keeper, 50, _list3(alice, carol, address(0xDEAD)));

        assertEq(
            _flipReach(keeper) - before,
            _expectedBounty(1, 100, false),
            "purchase phase must price the bounty at the next level"
        );
    }

    /// The other half of the routing: in jackpot phase the crank prices at the CURRENT
    /// level. Same x00 boundary, so this pins 0.24 ETH where the sibling test pins 0.04.
    function testCrankBountyPricesAtTheCurrentLevelInJackpotPhase() public {
        _fund(alice, STAKE);
        _fund(carol, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);
        _bet(carol, false);
        // Settled, sitting at level 100 in JACKPOT phase -> routed level is 100.
        _settle(50, true);
        _mockState(0, 0, 0, 0, 100, true, 0);

        uint256 before = _flipReach(keeper);
        _crank(keeper, 50, _list3(alice, carol, address(0xDEAD)));

        assertEq(
            _flipReach(keeper) - before,
            _expectedBounty(1, 100, true),
            "jackpot phase must price the bounty at the current level"
        );
    }

    // =====================================================================
    // Quest
    // =====================================================================

    /// The reward halves per jackpot-phase day and floors to a whole FLIP:
    /// 150 / 75 / 37 / 18 across the phase's four jackpot days. Days 0 and 1 share the
    /// top tier — the counter reads 0 only until the first daily jackpot settles, and the
    /// whole first day prices at 150 rather than dropping a tier when that settlement
    /// lands. This is the sole corrective for parimutuel's last-mover advantage, so the
    /// schedule itself is the invariant.
    function testQuestRewardLadderSharesTheTopTierAcrossDayOne() public {
        uint256[5] memory expected = [
            uint256(150 ether), // day 0: transition until the first settlement
            150 ether, // day 1: the rest of the first day
            75 ether,
            37 ether,
            18 ether
        ];
        for (uint8 day; day <= 4; ++day) {
            _mockOpenAt(50, day, true);
            (, , , uint256 reward, , , , ) = parimutuel.marketState(alice, 50);
            assertEq(
                reward,
                expected[day],
                "quest reward must follow the four-day ladder"
            );
        }
    }

    /// A closed market still quotes the ladder: phaseDay 0 maps to the top tier, so the
    /// number shown before a phase opens is what the first day will actually pay.
    function testQuestRewardQuotesTheTopTierWhileClosed() public {
        _mockOpenAt(50, 0, false);
        (, , , uint256 reward, , , , ) = parimutuel.marketState(alice, 50);
        assertEq(reward, 150 ether, "a closed market must quote the first day's tier");
    }

    /// A player past the lifetime bar but short of the LEVEL quest still bets, and earns
    /// no quest reward — the reward gate is the level quest's, so it reaches active
    /// players only, while the weaker ever-bought bar decides who may bet at all.
    function testIneligiblePlayerBetsButEarnsNoQuestReward() public {
        _fund(alice, STAKE);
        uint256 before = _flipReach(alice);

        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        assertEq(
            before - _flipReach(alice),
            STAKE,
            "an ineligible bettor pays the stake and receives no quest credit"
        );
    }

    /// An active afking run stands in for the eligibility gate: the sub is buying this
    /// level's tickets from the player's own funding, so a bettor with zero manually
    /// minted units still earns the participation reward.
    function testAfkingRunSubstitutesForQuestEligibility() public {
        vm.prank(address(game));
        quests.beginAfking(alice, 1);

        _fund(alice, STAKE);
        uint256 before = _flipReach(alice);
        _mockOpenAt(50, 1, true);
        _bet(alice, true);

        assertEq(
            before - _flipReach(alice),
            STAKE - 150 ether,
            "an afking bettor with no minted units must still earn the day-1 reward"
        );
    }

    /// The lifetime bar, unmocked: a wallet that has never bought anything gets the real
    /// quests answer (mintPackedFor == 0 on both arms) and may not bet at all.
    function testNeverBoughtPlayerCannotBet() public {
        _fundNoGate(alice, STAKE);
        _mockOpenAt(50, 0, true);
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeBet(address(0), true);
    }

    /// The curse counter is the one mintPacked_ field a third party can write into a
    /// stranger's word (a deity smite), so it is masked out of the ever-bought test: a
    /// smitten wallet that never bought anything still may not bet.
    function testSmittenNeverBoughtPlayerStillCannotBet() public {
        _fundNoGate(alice, STAKE);
        // mintPacked_ holding ONLY curse bits (215-222), as a smite against a fresh
        // address leaves it.
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(
                bytes4(keccak256("mintPackedFor(address)")),
                alice
            ),
            abi.encode(uint256(20) << 215)
        );
        _mockOpenAt(50, 0, true);
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeBet(address(0), true);
    }

    /// recordGrowthBet is PARIMUTUEL-only — no other caller can mint quest rewards.
    function testQuestRewardRejectsForeignCaller() public {
        vm.prank(alice);
        vm.expectRevert();
        quests.recordGrowthBet(alice, 50, 150 ether);

        vm.prank(address(game));
        vm.expectRevert();
        quests.recordGrowthBet(alice, 50, 150 ether);
    }

    // =====================================================================
    // Lifecycle through the real advance path
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

    /// @dev Raise nextPrizePool over the live target so the next drive latches a
    ///      transition. Slot 2 packs [future:128 | next:128]; replace the next
    ///      half only.
    function _seedNextPool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        if ((packed & ((uint256(1) << 128) - 1)) >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(2)),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext)
        );
    }

    /// @dev Drive the real game into a live, settled jackpot phase on an ordinary round
    ///      (level >= 2, clear of the century band) and return that round.
    function _driveToLiveJackpotPhase() internal returns (uint24 round) {
        for (uint256 i = 0; i < 40 && game.level() < 2; i++) {
            if (!game.jackpotPhase()) _seedNextPool(50 ether);
            _driveDay();
        }
        for (uint256 i = 0; i < 40; i++) {
            if (game.jackpotPhase() && !game.rngLocked() && game.level() >= 2) break;
            if (!game.jackpotPhase()) _seedNextPool(200 ether);
            _driveDay();
        }

        require(game.jackpotPhase() && !game.rngLocked(), "harness: no live jackpot phase");
        round = game.level();
        require(round >= 2 && round % 100 > 1 && round % 100 != 99, "harness: skipped round");
    }

    /// Betting deliberately ignores the RNG lock: the market consumes no randomness and
    /// its terms are write-once, so the morning window — the day's word in flight, the
    /// day's results landing, players at their most attentive — takes bets like any other
    /// moment of the phase.
    function testBettingStaysOpenDuringTheRngWindow() public {
        vm.pauseGasMetering();
        uint24 round = _driveToLiveJackpotPhase();

        // Open a fresh day and advance exactly once: the first call of a day requests the
        // day's RNG and latches the lock, and nothing settles until the mock fulfills.
        simTime += 1 days + 1;
        vm.warp(simTime);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        require(ok, "harness: advance must request the day's RNG");
        require(game.rngLocked(), "harness: the day's word must be in flight");
        require(game.jackpotPhase(), "harness: the phase must still be live");

        (uint24 openRound, , , , , , , ) = parimutuel.marketState(alice, round);
        assertEq(openRound, round, "the locked window must still expose the open round");

        _fund(alice, STAKE);
        _bet(alice, true);
        (, uint128 overCount, , , uint8 side, , , ) = parimutuel.marketState(
            alice,
            round
        );
        assertEq(overCount, 1, "the locked-window bet must book");
        assertEq(side, 1, "the locked-window bet must record its side");
    }

    /// The quest's streak leg is a counter credit only, never the daily activity marker:
    /// a bet adds exactly +1 and leaves lastActiveDay untouched, so it cannot stand in
    /// for a daily quest. Observable through the decay-aware view: with no anchor ever
    /// set, later missed days have nothing to bill against and the +1 survives them —
    /// where the old anchor-bumping behavior would have lapsed it to 0.
    function testGrowthBetAddsAStreakDayWithoutMarkingActivity() public {
        vm.pauseGasMetering();
        uint24 round = _driveToLiveJackpotPhase();

        // Make alice level-quest eligible: a whole ticket (400 units) tagged at the
        // current level, and levelStreak 5 for the loyalty gate.
        uint256 packedMint = (uint256(400) << 228) |
            (uint256(round) << 104) |
            (uint256(5) << 48);
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(
                bytes4(keccak256("mintPackedFor(address)")),
                alice
            ),
            abi.encode(packedMint)
        );

        assertEq(quests.effectiveBaseStreak(alice), 0, "harness: fresh streak");
        _fund(alice, STAKE);
        _bet(alice, true);

        // Two full protocol days pass with no daily quest from alice, then one read
        // separates every world. No bump at all reads 0. A bump that also marked
        // activity (the old behavior) anchors the lapse clock to the bet day, so the
        // missed day bills the streak to 0. Only the pure counter credit — +1, no
        // anchor, nothing for missed days to bill against — reads 1.
        _driveDay();
        _driveDay();
        assertEq(
            quests.effectiveBaseStreak(alice),
            1,
            "the bet must add one streak day that carries no daily-quest protection"
        );
    }

    /// End to end on the real game: bet during a live jackpot phase, let the protocol
    /// transition, then claim against the ratchet the transition actually wrote. Nothing
    /// pushes a result into the market — the outcome is derived from levelPrizePool alone.
    /// A turbo phase takes all five logical days in ONE physical day, so its market would
    /// open and shut inside a single advance cycle — minutes, not days. Nobody outside the
    /// mempool could act on that, so a turbo level gets no market at all. Driven one advance
    /// at a time: at EVERY point where a turbo phase is live, betting must be shut.
    function testTurboLevelNeverOpensAMarket() public {
        vm.pauseGasMetering();

        // Run a level's jackpot phase out, landing in the next level's purchase phase.
        _driveToLiveJackpotPhase();
        for (uint256 i = 0; i < 20 && game.jackpotPhase(); i++) _driveDay();
        require(!game.jackpotPhase(), "harness: jackpot phase never ended");

        // Clear the ratchet target inside the two-day window that arms turbo
        // (AdvanceModule: purchaseDays <= 1 && nextPool > target).
        _seedNextPool(game.prizePoolTargetView() + 10 ether);

        uint256 turboObservations;
        for (uint256 d = 0; d < 8; d++) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            for (uint256 j = 0; j < 200; j++) {
                _fulfillVrfIfPending();
                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
                if (game.jackpotPhase() && game.jackpotCompressionTier() >= 2) {
                    (, , , , bool open, ) = game.growthState(0);
                    assertFalse(open, "a turbo phase must never take bets");
                    turboObservations++;
                }
            }
        }

        assertGt(turboObservations, 0, "harness: never observed a live turbo phase");
    }

    /// The market closes when the level's DRAWS end, not when jackpotPhaseFlag drops.
    /// _endPhase seals the level but leaves the flag up through the far-future ticket
    /// drain — one or more advances — and zeroes the day counter on the way, so a market
    /// keyed on the flag alone would stay open there AND quote the first day's 150 FLIP
    /// to the last mover. Driven one advance at a time so the span is observable.
    function testBettingClosesWhenDrawsEndNotWhenFlagDrops() public {
        vm.pauseGasMetering();

        uint24 round = _driveToLiveJackpotPhase();
        _fund(alice, STAKE);
        _bet(alice, true); // in-phase bet still books

        bool sawSpan;
        for (uint256 d = 0; d < 40 && !sawSpan; d++) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            for (uint256 j = 0; j < 200; j++) {
                _fulfillVrfIfPending();
                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
                // The span: draws ended, flag not yet dropped.
                if (game.jackpotPhase()) {
                    (, , , , bool open, uint8 phaseDay) = game.growthState(0);
                    if (!open) {
                        sawSpan = true;
                        assertEq(
                            phaseDay,
                            0,
                            "_endPhase zeroed the counter, which is what made the span quote 150"
                        );
                        _fund(bob, STAKE);
                        vm.prank(bob);
                        vm.expectRevert(DegenerusParimutuel.MarketClosed.selector);
                        parimutuel.placeBet(address(0), true);
                        break;
                    }
                }
                if (game.level() > round) break;
            }
            if (game.level() > round) break;
        }

        assertTrue(sawSpan, "harness: never observed the post-draw span");
    }

    function testLifecycleBetTransitionClaim() public {
        vm.pauseGasMetering();

        uint24 round = _driveToLiveJackpotPhase();

        (uint24 openRound, , , , , , , ) = parimutuel.marketState(alice, round);
        assertEq(openRound, round, "the live jackpot phase must expose an open round");

        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _bet(alice, true);
        _bet(bob, false);

        (, uint128 overCount, uint128 underCount, , , , , ) = parimutuel.marketState(
            alice,
            round
        );
        assertEq(overCount, 1, "one OVER bet must be booked");
        assertEq(underCount, 1, "one UNDER bet must be booked");

        // The round is unsettled until the NEXT level banks its pool.
        (, , , , , , uint8 midOutcome, ) = parimutuel.marketState(alice, round);
        assertEq(midOutcome, 0, "an in-flight round must not be settled");

        // Drive through the transition into the next level.
        for (uint256 i = 0; i < 60 && game.level() <= round; i++) {
            if (!game.jackpotPhase()) _seedNextPool(5_000 ether);
            _driveDay();
        }
        assertGt(game.level(), round, "the protocol must advance past the bet round");

        (, , , , , , uint8 outcome, ) = parimutuel.marketState(alice, round);
        assertTrue(outcome == 1 || outcome == 2, "the round must settle after transition");

        // Exactly one side is paid, and it is paid the whole book.
        uint256 aliceOut = _claimOne(alice, round);
        uint256 bobOut = _claimOne(bob, round);
        assertEq(
            aliceOut + bobOut,
            STAKE * 2,
            "the winning side must take the entire two-bet pot"
        );
        assertTrue(
            (aliceOut == 0) != (bobOut == 0),
            "exactly one side of a two-sided book may be paid"
        );
    }
}
