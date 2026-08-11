// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title BafWeightedDrawTest — pins the BAF Slice A2 amount-weighted draw in Coinflip.
///
/// @notice One armed flip day per BAF bracket (the x0 level's last purchase day stakes
///         it). Every direct self-funded deposit staking the armed day appends a
///         cumulative interval weighted by its raw FLIP principal; the BAF slice pays
///         5% of the pool to ONE winner drawn over those intervals with a
///         domain-separated roll of the transition word, located by binary search.
///         An empty book returns address(0) and the slice refunds, exactly as an
///         empty board did.
///
/// @dev The behaviours pinned here are the ones a refactor would quietly break:
///      - The normal 100-FLIP minimum is the only entry bar — no whale floor.
///      - Weight is the raw principal (whole FLIP): bonuses, boon boosts, record
///        claims, recycle legs, gifts, operator deposits, and protocol credits all
///        carry zero weight.
///      - Probability is interval measure: repeat deposits are additive and
///        splitting moves no probability.
///      - Ordinary (un-armed) days write NO draw state.
///      - Entries key the deposit's target day, so the book closes at the day
///        boundary — before the deciding word can be requested.
///      - The draw perturbs no other BAF slice for a fixed word and state.
contract BafWeightedDrawTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    bytes32 internal constant TAG = "COINFLIP_BAF_DRAW_WINNER";

    address private alice;
    address private bob;
    address private carol;
    address private operator;

    function setUp() public {
        _deployProtocol();
        alice = makeAddr("draw_alice");
        bob = makeAddr("draw_bob");
        carol = makeAddr("draw_carol");
        operator = makeAddr("draw_operator");
        // Wall clock at day 2 so deposits target day 3 (clear of the day-1/2 seeds).
        _warpToDay(2);
    }

    // ---------------------------------------------------------------------
    // Arming surface
    // ---------------------------------------------------------------------

    function testArmBafDrawIsGameOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        coinflip.armBafDraw(3);

        vm.prank(GAME);
        coinflip.armBafDraw(3);
        (uint24 day, , ) = coinflip.bafDrawInfo();
        assertEq(day, 3, "the game arms the draw day");
    }

    // ---------------------------------------------------------------------
    // Eligibility: the 100-FLIP minimum is the only bar
    // ---------------------------------------------------------------------

    /// @notice A minimum-size (100 FLIP) direct deposit on the armed day enters the
    ///         draw and, as the only entry, wins it for every word.
    function testMinimumDepositEntersAndCanWin() public {
        _arm(3);
        _selfDeposit(alice, 100 ether);

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(total, 100, "weight is the whole-FLIP principal");
        assertEq(count, 1, "one entry recorded");

        (address p, uint96 cum) = coinflip.bafDrawEntryAt(3, 0);
        assertEq(p, alice, "the entry belongs to the depositor");
        assertEq(cum, 100, "cumulative endpoint equals the sole weight");

        assertEq(
            coinflip.bafDrawWinner(uint256(keccak256("any_word"))),
            alice,
            "a 100-FLIP entry can win"
        );
    }

    /// @notice No 200k threshold survives anywhere in the draw path: a whale-size
    ///         deposit records exactly its principal, same rule as the minnow.
    function testNoWhaleFloorRemains() public {
        _arm(3);
        _selfDeposit(alice, 100 ether);
        _selfDeposit(bob, 200_000 ether);

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 2, "both sizes enter under one rule");
        assertEq(total, 100 + 200_000, "weights are raw principal at every size");
    }

    // ---------------------------------------------------------------------
    // Interval boundaries and additivity
    // ---------------------------------------------------------------------

    /// @notice Alice 100 / Bob 300: alice owns [0,100), bob [100,400) — pinned at
    ///         the exact boundary rolls.
    function testExactOneToThreeIntervalBoundaries() public {
        _arm(3);
        _selfDeposit(alice, 100 ether);
        _selfDeposit(bob, 300 ether);

        (, uint96 total, ) = coinflip.bafDrawInfo();
        assertEq(total, 400, "total weight");

        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 0)), alice, "roll 0");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 99)), alice, "roll 99");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 100)), bob, "roll 100");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 399)), bob, "roll 399");
    }

    /// @notice Alice 100, Bob 100, Alice 200: three separate intervals, and alice's
    ///         combined measure is 300/400 — repeat deposits are additive with no
    ///         per-player aggregation.
    function testRepeatDepositsRemainAdditive() public {
        _arm(3);
        _selfDeposit(alice, 100 ether);
        _selfDeposit(bob, 100 ether);
        _selfDeposit(alice, 200 ether);

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 3, "repeat deposits append separate intervals");
        assertEq(total, 400, "total weight");

        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 0)), alice, "[0,100) alice");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 99)), alice, "[0,100) alice hi");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 100)), bob, "[100,200) bob");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 199)), bob, "[100,200) bob hi");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 200)), alice, "[200,400) alice");
        assertEq(coinflip.bafDrawWinner(_wordForRoll(3, 400, 399)), alice, "[200,400) alice hi");
    }

    /// @notice Binary search agrees with a linear reference walk over the recorded
    ///         cumulative endpoints for arbitrary entry sets and words.
    function testFuzzBinarySearchMatchesLinearReference(uint256 seed, uint256 word) public {
        _arm(3);
        uint256 n = 1 + (seed % 24);
        for (uint256 i; i < n; ++i) {
            address p = makeAddr(string(abi.encodePacked("fz", uint8(i % 7))));
            uint256 amount = (100 + (uint256(keccak256(abi.encode(seed, i))) % 50_000)) * 1 ether;
            _selfDeposit(p, amount);
        }

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, n, "every deposit appended");

        uint256 roll = uint256(
            keccak256(abi.encodePacked(TAG, address(coinflip), uint24(3), word))
        ) % uint256(total);

        address expected;
        for (uint32 i; i < count; ++i) {
            (address p, uint96 cum) = coinflip.bafDrawEntryAt(3, i);
            if (uint256(cum) > roll) {
                expected = p;
                break;
            }
        }
        assertTrue(expected != address(0), "reference walk must find a winner");
        assertEq(coinflip.bafDrawWinner(word), expected, "binary == linear reference");
    }

    // ---------------------------------------------------------------------
    // Ordinary days and the day boundary
    // ---------------------------------------------------------------------

    /// @notice With no armed day, a direct deposit writes NO draw state and emits
    ///         no entry event.
    function testOrdinaryDayDepositWritesNoDrawState() public {
        vm.recordLogs();
        _selfDeposit(alice, 5_000 ether);

        (uint24 day, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(day, 0, "nothing armed");
        assertEq(total, 0, "no weight recorded");
        assertEq(count, 0, "no entries recorded");
        (address p, uint96 cum) = coinflip.bafDrawEntryAt(3, 0);
        assertEq(p, address(0), "no entry at the target day");
        assertEq(cum, 0, "no endpoint at the target day");
        _assertNoDrawEnteredLog();
    }

    /// @notice An armed day's book closes at the day boundary: a deposit made the
    ///         next day targets a later flip day and appends nothing.
    function testEntriesCloseAtTheDayBoundary() public {
        _arm(3);
        _selfDeposit(alice, 100 ether); // day-2 deposit stakes day 3: enters

        _warpToDay(3);
        vm.recordLogs();
        _selfDeposit(bob, 100_000 ether); // stakes day 4: locked out of day 3's book

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 1, "the boundary closed the book");
        assertEq(total, 100, "no late weight joined");
        _assertNoDrawEnteredLog();
        assertEq(
            coinflip.bafDrawWinner(uint256(keccak256("boundary_word"))),
            alice,
            "the sole in-window entry still wins"
        );
    }

    // ---------------------------------------------------------------------
    // Exclusions: only direct self-funded principal carries weight
    // ---------------------------------------------------------------------

    /// @notice Gifts, operator deposits, protocol flip credits, and sDGNRS backing
    ///         all carry zero draw weight on the armed day.
    function testGiftOperatorAndCreditsCarryNoWeight() public {
        _arm(3);

        // Permissionless gift: bob funds a stake credited to alice.
        vm.prank(GAME);
        coin.mintForGame(bob, 1_000 ether);
        vm.prank(bob);
        coinflip.depositCoinflip(alice, 1_000 ether);

        // Approved-operator deposit: operator spends alice's FLIP for her stake.
        vm.prank(alice);
        game.setOperatorApproval(operator, true);
        vm.prank(GAME);
        coin.mintForGame(alice, 1_000 ether);
        vm.prank(operator);
        coinflip.depositCoinflip(alice, 1_000 ether);

        // Protocol flip credit (quest-reward shape).
        vm.prank(ContractAddresses.QUESTS);
        coinflip.creditFlip(alice, 1_000 ether);

        // sDGNRS backing credit (FLIP de-circulation shape).
        vm.prank(ContractAddresses.COIN);
        coinflip.creditSdgnrsBacking(1_000 ether);

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0, "no indirect leg may enter the draw");
        assertEq(total, 0, "no indirect weight recorded");
        assertEq(
            coinflip.bafDrawWinner(uint256(keccak256("excl_word"))),
            address(0),
            "an all-indirect day draws nobody"
        );
    }

    /// @notice A boon boost inflates the stake but not the draw weight.
    function testBoonBoostCarriesNoWeight() public {
        _arm(3);
        vm.mockCall(
            GAME,
            abi.encodeWithSelector(IDegenerusGame.consumeCoinflipBoon.selector),
            abi.encode(uint16(2500))
        );
        _selfDeposit(alice, 1_000 ether);
        vm.clearMockedCalls();

        assertGe(
            coinflip.coinflipAmount(alice),
            1_250 ether,
            "harness: the 25% boon boost must have landed on the stake"
        );
        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 1, "the deposit itself enters once");
        assertEq(total, 1_000, "weight is the raw principal, not the boosted stake");
    }

    /// @notice A rebet funded from settled winnings weighs its raw principal — the
    ///         recycling bonus rides the stake, never the draw.
    function testRecycleLegCarriesNoWeight() public {
        // Bank a win: day-2 deposit stakes day 3; resolve day 3 as a win.
        _selfDeposit(alice, 1_000 ether);
        _resolveDay(3, true);

        // Day-3 deposits stake day 4: arm day 4 and rebet out of the winnings.
        _arm(4);
        vm.prank(alice);
        coinflip.depositCoinflip(address(0), 500 ether);

        (, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 1, "the rebet enters once");
        assertEq(total, 500, "weight is the raw principal, not principal + recycle bonus");
        assertGt(
            coinflip.coinflipAmount(alice),
            500 ether,
            "harness: the recycle bonus must have landed on the stake"
        );
    }

    /// @notice A flip-record claim folded into the deposit inflates the stake but
    ///         not the draw weight.
    function testRecordClaimCarriesNoWeight() public {
        _arm(3);
        uint256 amount = 250_000 ether; // clears the record floor; bootstrap claim pays
        _selfDeposit(alice, amount);

        assertEq(coinflip.biggestFlipEver(), amount, "harness: the record must have armed");
        assertGt(
            coinflip.coinflipAmount(alice),
            amount,
            "harness: the record claim must have joined the stake"
        );
        (, uint96 total, ) = coinflip.bafDrawInfo();
        assertEq(total, 250_000, "weight is the raw principal, not principal + claim");
    }

    // ---------------------------------------------------------------------
    // Jackpots wiring: empty refund and slice isolation
    // ---------------------------------------------------------------------

    /// @notice An armed day nobody entered returns address(0) and the whole Slice A2
    ///         amount refunds — with no other BAF state, the full pool returns.
    function testEmptyDrawRefundsSliceA2() public {
        _arm(3);
        uint256 pool = 100 ether;
        vm.prank(GAME);
        (address[] memory w, , uint256 back) = jackpots.runBafJackpot(
            pool,
            10,
            uint256(keccak256("empty_word"))
        );
        assertEq(w.length, 0, "nothing to pay anywhere");
        assertEq(back, pool, "every slice, A2 included, refunds in full");
    }

    /// @notice With one recorded entry, Slice A2 pays exactly 5% to the drawn winner
    ///         and everything else still refunds.
    function testSoleEntryTakesExactlyTheFivePercentSlice() public {
        _arm(3);
        _selfDeposit(alice, 100 ether);
        uint256 pool = 100 ether;
        vm.prank(GAME);
        (address[] memory w, uint256[] memory a, uint256 back) = jackpots.runBafJackpot(
            pool,
            10,
            uint256(keccak256("sole_word"))
        );
        assertEq(w.length, 1, "the draw is the only funded slice");
        assertEq(w[0], alice, "the sole entrant wins the draw");
        assertEq(a[0], pool / 20, "Slice A2 is exactly 5%");
        assertEq(back, pool - pool / 20, "the rest refunds");
    }

    /// @notice For a fixed word and fixed BAF state, adding draw entries changes
    ///         ONLY Slice A2: every other winner/amount is identical with and
    ///         without the draw.
    function testOtherSlicesUnperturbedByTheDraw() public {
        _arm(3);
        // Build board + score state through the real credit path.
        vm.startPrank(ContractAddresses.COINFLIP);
        jackpots.recordBafFlip(alice, 10, 900 ether);
        jackpots.recordBafFlip(bob, 10, 700 ether);
        jackpots.recordBafFlip(carol, 10, 500 ether);
        vm.stopPrank();

        uint256 pool = 100 ether;
        uint256 word = uint256(keccak256("isolation_word"));

        uint256 snap = vm.snapshotState();
        vm.prank(GAME);
        (address[] memory w1, uint256[] memory a1, uint256 r1) = jackpots.runBafJackpot(
            pool,
            10,
            word
        );
        vm.revertToState(snap);

        _selfDeposit(alice, 100 ether);
        _selfDeposit(bob, 300 ether);
        vm.prank(GAME);
        (address[] memory w2, uint256[] memory a2, uint256 r2) = jackpots.runBafJackpot(
            pool,
            10,
            word
        );

        // Run 2 must be run 1 plus exactly one extra credited entry: the A2 winner
        // at 5%, inserted at the A2 position (after Slice A when A credited).
        assertEq(w2.length, w1.length + 1, "exactly one new credited slice");
        uint256 a2Idx = type(uint256).max;
        for (uint256 i; i < w2.length; ++i) {
            if (a2Idx == type(uint256).max && a2[i] == pool / 20) {
                // First 5%-sized entry is A2 (slice B pays 5% too, but only ever
                // after A2 in the buffer; the earliest match is A2).
                a2Idx = i;
            }
        }
        assertTrue(a2Idx != type(uint256).max, "the A2 credit must appear");
        assertTrue(a2Idx == 1 || (a2Idx == 0 && w1.length == 0), "A2 sits at its slice position");

        uint256 j;
        for (uint256 i; i < w2.length; ++i) {
            if (i == a2Idx) continue;
            assertEq(w2[i], w1[j], "non-A2 winner order unchanged");
            assertEq(a2[i], a1[j], "non-A2 amount unchanged");
            ++j;
        }
        assertEq(r1 - r2, pool / 20, "the refund shrinks by exactly the paid A2 share");
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _arm(uint24 day) internal {
        vm.prank(GAME);
        coinflip.armBafDraw(day);
    }

    /// @dev Wall clock just inside GameTimeLib day `d`.
    function _warpToDay(uint24 d) internal {
        vm.warp(
            (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
    }

    /// @dev Resolve day `epoch` as the GAME, wall clock at `epoch`.
    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 word = uint256(keccak256(abi.encodePacked("draw_day_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }

    /// @dev Mint wallet FLIP and self-deposit it (direct — carries draw weight).
    function _selfDeposit(address who, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame(who, amount);
        vm.prank(who);
        coinflip.depositCoinflip(address(0), amount);
    }

    /// @dev Scan words until the draw's domain hash lands exactly on `target`.
    function _wordForRoll(
        uint24 day,
        uint256 total,
        uint256 target
    ) internal view returns (uint256 word) {
        for (uint256 i; i < 200_000; ++i) {
            word = uint256(keccak256(abi.encode("roll_scan", i)));
            uint256 roll = uint256(
                keccak256(abi.encodePacked(TAG, address(coinflip), day, word))
            ) % total;
            if (roll == target) return word;
        }
        revert("no word found for target roll");
    }

    /// @dev Assert the recorded logs carry no BafDrawEntered event.
    function _assertNoDrawEnteredLog() internal {
        bytes32 sig = keccak256("BafDrawEntered(uint24,address,uint32,uint96,uint96)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != sig, "no draw entry may be recorded");
        }
    }
}
