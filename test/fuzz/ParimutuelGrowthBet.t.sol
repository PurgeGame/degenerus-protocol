// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

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
///         end to end: bet during a jackpot phase, transition, settlement — the push landing
///         from the real transition, nothing pranked.
contract ParimutuelGrowthBetTest is DeployProtocol {
    // growthState(uint24) — the scoring half mocks only the key-0 route tuple; ratchet
    // terms left the market's reads entirely (settlement arrives as a pushed bit).
    bytes4 private constant GROWTH_STATE = bytes4(keccak256("growthState(uint24)"));
    bytes4 private constant IS_OP_APPROVED =
        bytes4(keccak256("isOperatorApproved(address,address)"));
    bytes4 private constant MARKET_GATES =
        bytes4(keccak256("marketBetGates(address,uint24)"));

    uint256 private constant STAKE = 1_000;

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
            abi.encode(true, true, _giveWalletId(who))
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

    /// @dev FLIP the settlement stage still owes `who` on `round`: the win quoted by marketState
    ///      (0 for a loser, a non-bettor, an unsettled round or a win already paid).
    function _owed(address who, uint24 round) internal view returns (uint256 owed) {
        (, , , , , , , owed) = parimutuel.marketState(who, round);
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

        assertGt(_owed(alice, 50), 0, "OVER bettor is owed a payout");
        assertEq(_owed(bob, 50), 0, "UNDER bettor is owed nothing");
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
        assertEq(_owed(alice, 50), 0, "the OVER bettor is owed nothing on a tie");
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
        assertGt(_owed(alice, 50), 0, "the shallower-contraction OVER side is owed a payout");
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
        assertEq(_owed(alice, 50), 0, "an unsettled round owes nothing");
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
        assertEq(_owed(alice, 1), STAKE, "the uncontested winner is owed the stake back");
    }

    // =====================================================================
    // Century ratchet substitution
    // =====================================================================

    /// The reason boundary rounds are scoreable at all: a century level's term comes from
    /// the pushed achieved pool, so _endPhase rewriting levelPrizePool[x00] to 40% of futurePool
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
        _fund(alice, STAKE + 7);
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

        uint256 aliceOut = _owed(alice, 50);
        uint256 bobOut = _owed(bob, 50);
        assertEq(aliceOut, bobOut, "a fixed stake must pay every winner identically");
        assertEq(
            aliceOut,
            (STAKE * 3) / 2,
            "two winners must split a three-bet pot evenly"
        );
        assertEq(_owed(carol, 50), 0, "the loser is owed nothing");
    }

    /// An empty losing side needs no special case: the payout collapses to the stake back.
    function testEmptyLosingSidePaysStakeBack() public {
        _fund(alice, STAKE);
        _mockOpenAt(50, 0, true);
        _bet(alice, true);

        _settleOver(50);
        assertEq(
            _owed(alice, 50),
            STAKE,
            "an uncontested winner is owed exactly the stake back"
        );
    }

    /// When the winning side is empty nobody is owed anything, so the losing side stays burned.
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

        assertEq(_owed(alice, 50), 0, "a losing bettor is owed nothing");
        assertEq(_owed(bob, 50), 0, "a losing bettor is owed nothing");
        assertEq(
            coin.totalSupply(),
            supplyBefore,
            "both stakes must stay burned when no winner exists"
        );
    }

    /// The whole book is redistribution: winners are never owed more FLIP than the round
    /// burned.
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

        assertLe(
            _owed(alice, 50) + _owed(bob, 50) + _owed(carol, 50),
            funded,
            "a round must never owe more FLIP than it burned"
        );
        assertLe(
            coin.totalSupply(),
            supplyBefore + funded,
            "a round must never mint net FLIP"
        );
    }

    // =====================================================================
    // Settlement helpers
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
        uint256[3] memory expected = [uint256(150), 150, 37];
        for (uint8 day; day < 3; ++day) {
            _mockOpenAt(50, day, true);
            (, , , uint256 reward, , , , ) = parimutuel.marketState(alice, 50);
            assertEq(
                reward,
                expected[day],
                "quest reward must follow the three-day schedule"
            );
        }
    }

    /// A closed market still quotes the ladder: phaseDay 0 maps to the top tier, so the
    /// number shown before a phase opens is what the first day will actually pay.
    function testQuestRewardQuotesTheTopTierWhileClosed() public {
        _mockOpenAt(50, 0, false);
        (, , , uint256 reward, , , , ) = parimutuel.marketState(alice, 50);
        assertEq(reward, 150, "a closed market must quote the first day's tier");
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
        uint32 aliceId = _giveWalletId(alice);
        vm.prank(address(game));
        quests.beginAfking(aliceId, 1);

        _fund(alice, STAKE);
        uint256 before = _flipReach(alice);
        _mockOpenAt(50, 1, true);
        _bet(alice, true);

        assertEq(
            before - _flipReach(alice),
            STAKE - 150,
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
        // mintPacked_ holding ONLY curse bits, as a smite against a fresh address leaves it.
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(
                bytes4(keccak256("mintPackedFor(address)")),
                alice
            ),
            abi.encode(uint256(20) << BitPackingLib.CURSE_COUNT_SHIFT)
        );
        _mockOpenAt(50, 0, true);
        vm.prank(alice);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeBet(address(0), true);
    }

    /// recordGrowthBet is PARIMUTUEL-only — no other caller can mint quest rewards.
    function testQuestRewardRejectsForeignCaller() public {
        uint32 aliceId = _giveWalletId(alice);
        vm.prank(alice);
        vm.expectRevert();
        quests.recordGrowthBet(aliceId, alice, 50, 150);

        vm.prank(address(game));
        vm.expectRevert();
        quests.recordGrowthBet(aliceId, alice, 50, 150);
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
                abi.encodeWithSignature("mineFlip()")
            );
            if (!ok) break;
        }
    }

    /// @dev One engine checkpoint at a time. A single mineFlip composes every checkpoint its allowance
    ///      admits (60d31f775), so an unbounded call can open and close a state inside one transaction.
    ///      Offer the smallest allowance (in 250k steps up to the 16.7M ceiling) that makes progress;
    ///      the engine then stops at the next checkpoint boundary it cannot admit, and the state between
    ///      stages is observable. Needs live gas metering (the engine meters with gasleft()).
    function _mineStep() internal returns (bool ok) {
        for (uint256 g = 1_000_000; g <= 16_750_000; g += 250_000) {
            (ok, ) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip()"));
            if (ok) return true;
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
        _finishReadConsumers();
        bool ok;
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) {
            (ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            require(ok, "harness: prerequisites and daily request must progress");
        }
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
        uint256 packedMint = (uint256(400) << BitPackingLib.LEVEL_UNITS_SHIFT) |
            (uint256(round) << BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT) |
            (uint256(5) << 48);
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(
                bytes4(keccak256("mintPackedFor(address)")),
                alice
            ),
            abi.encode(packedMint)
        );

        _fund(alice, STAKE);
        assertEq(quests.effectiveBaseStreak(game.walletIdOf(alice)), 0, "harness: fresh streak");
        _bet(alice, true);

        // Two full protocol days pass with no daily quest from alice, then one read
        // separates every world. No bump at all reads 0. A bump that also marked
        // activity (the old behavior) anchors the lapse clock to the bet day, so the
        // missed day bills the streak to 0. Only the pure counter credit — +1, no
        // anchor, nothing for missed days to bill against — reads 1.
        _driveDay();
        _driveDay();
        assertEq(
            quests.effectiveBaseStreak(game.walletIdOf(alice)),
            1,
            "the bet must add one streak day that carries no daily-quest protection"
        );
    }

    /// End to end on the real game: bet during a live jackpot phase, let the protocol
    /// transition, then claim against the ratchet the transition actually wrote. Nothing
    /// pushes a result into the market — the outcome is derived from levelPrizePool alone.
    /// A turbo phase pays its whole jackpot in ONE physical day, so its market would
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
        // Stepped one checkpoint per call (`_mineStep`), so metering must run.
        vm.resumeGasMetering();
        for (uint256 d = 0; d < 8; d++) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            for (uint256 j = 0; j < 400; j++) {
                _fulfillVrfIfPending();
                if (!_mineStep()) break;
                if (game.jackpotPhase() && game.jackpotDuration() == 1) {
                    (, , , , bool open, ) = game.growthState(0);
                    assertFalse(open, "a turbo phase must never take bets");
                    turboObservations++;
                }
            }
        }

        assertGt(turboObservations, 0, "harness: never observed a live turbo phase");
    }

    /// The market closes when the level's DRAWS end, not when jackpotPhaseFlag drops.
    /// _endPhase seals the level but leaves the flag up until the transition closes, and zeroes the
    /// day counter on the way, so a market keyed on the flag alone would stay open there AND quote
    /// the first day's 150 FLIP to the last mover. Driven one checkpoint per call so the span is
    /// observable whenever it outlives a call.
    /// @dev One mineFlip composes every checkpoint its allowance admits (60d31f775). When the last
    ///      draw chunk leaves the transition's declared bound (TRANSITION_CLOSE) in the call, the draws
    ///      end and the transition closes in the same call, and no bet can land between them; this
    ///      fixture's last chunk is admitted only with that much slack, so the ending call is
    ///      asserted to run the two checkpoints in order (Advance stage 9 then stage 3). A cheaper
    ///      bound/actual gap leaves the span standing between calls, so the market gate is then
    ///      checked on the pre-ending snapshot with exactly the two fields `_endPhase` writes
    ///      (phaseTransitionActive set, jackpotCounter zeroed; flag still up).
    function testBettingClosesWhenDrawsEndNotWhenFlagDrops() public {
        vm.pauseGasMetering();

        uint24 round = _driveToLiveJackpotPhase();
        _fund(alice, STAKE);
        _bet(alice, true); // in-phase bet still books

        bool sawSpan;
        // Stepped one checkpoint per call (`_mineStep`), so metering must run.
        vm.resumeGasMetering();
        for (uint256 d = 0; d < 40 && !sawSpan; d++) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            for (uint256 j = 0; j < 400; j++) {
                _fulfillVrfIfPending();
                bool wasLive = game.jackpotPhase();
                uint256 snap = vm.snapshotState();
                vm.recordLogs();
                if (!_mineStep()) break;
                // The span: draws ended, flag not yet dropped.
                if (game.jackpotPhase()) {
                    (, , , , bool open, uint8 phaseDay) = game.growthState(0);
                    if (!open) {
                        sawSpan = true;
                        _assertSpanClosed(phaseDay);
                        break;
                    }
                } else if (wasLive) {
                    // The ending call: the draws ended, then the transition closed, in one call.
                    _assertEndsDrawsBeforeTransition(vm.getRecordedLogs());
                    vm.revertToState(snap);
                    uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
                    slot0 = (slot0 & ~(uint256(0xFF) << 128)) | (uint256(1) << 160); // jackpotCounter = 0, phaseTransitionActive
                    vm.store(address(game), bytes32(0), bytes32(slot0));
                    assertTrue(game.jackpotPhase(), "the flag is still up in the span");
                    (, , , , bool open, uint8 phaseDay) = game.growthState(0);
                    assertFalse(open, "the market is shut once the draws end");
                    sawSpan = true;
                    _assertSpanClosed(phaseDay);
                    break;
                }
                if (game.level() > round) break;
            }
            if (game.level() > round) break;
        }

        assertTrue(sawSpan, "harness: never observed the post-draw span");
    }

    function _assertSpanClosed(uint8 phaseDay) internal {
        assertEq(phaseDay, 0, "_endPhase zeroed the counter, which is what made the span quote 150");
        _fund(bob, STAKE);
        vm.prank(bob);
        vm.expectRevert(DegenerusParimutuel.MarketClosed.selector);
        parimutuel.placeBet(address(0), true);
    }

    /// @dev Advance(stage, lvl) from the game: STAGE_JACKPOT_PHASE_ENDED (9) precedes
    ///      STAGE_TRANSITION_DONE (3) in the ending call.
    function _assertEndsDrawsBeforeTransition(Vm.Log[] memory logs) internal view {
        bytes32 sig = keccak256("Advance(uint8,uint24)");
        uint256 ended = type(uint256).max;
        uint256 closed = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0 || logs[i].topics[0] != sig) continue;
            (uint8 stage, ) = abi.decode(logs[i].data, (uint8, uint24));
            if (stage == 9 && ended == type(uint256).max) ended = i;
            if (stage == 3 && closed == type(uint256).max) closed = i;
        }
        assertTrue(ended != type(uint256).max, "the ending call ended the draws");
        assertTrue(closed != type(uint256).max, "the ending call closed the transition");
        assertLt(ended, closed, "the draws end before the transition drops the flag");
    }

    function testLifecycleBetTransitionSettlement() public {
        vm.pauseGasMetering();

        uint24 round = _driveToLiveJackpotPhase();

        (uint24 openRound, , , , , , , ) = parimutuel.marketState(alice, round);
        assertEq(openRound, round, "the live jackpot phase must expose an open round");

        _fund(alice, STAKE);
        _fund(bob, STAKE);
        _bet(alice, true);
        _bet(bob, false);
        uint256 aliceStakeBefore = coinflip.coinflipAmount(alice);
        uint256 bobStakeBefore = coinflip.coinflipAmount(bob);

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

        // The mining stage pays the winning side the whole book as flip credit.
        (, , , , uint8 aliceSide, , , ) = parimutuel.marketState(alice, round);
        address winner = aliceSide == outcome ? alice : bob;
        address loser = winner == alice ? bob : alice;
        uint256 winnerBefore = winner == alice ? aliceStakeBefore : bobStakeBefore;
        uint256 loserBefore = winner == alice ? bobStakeBefore : aliceStakeBefore;
        for (uint256 i = 0; i < 20; i++) {
            (, , , , , bool paid, , ) = parimutuel.marketState(winner, round);
            if (paid) break;
            _driveDay();
        }
        (, , , , , bool settled, , uint256 owed) = parimutuel.marketState(winner, round);
        assertTrue(settled, "the mining stage must pay the winner");
        assertEq(owed, 0, "nothing remains owed to the winner");
        assertEq(
            coinflip.coinflipAmount(winner) - winnerBefore,
            STAKE * 2,
            "the winning side must take the entire two-bet pot"
        );
        assertEq(coinflip.coinflipAmount(loser), loserBefore, "the losing side is paid nothing");
    }
}
