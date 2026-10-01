// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Initial conditions only: a funded first jackpot day with already-materialized
/// ticket owners. No settlement or request is performed under this runtime.
contract DailyJackpotCommitmentSeeder is DegenerusGame, BucketSeed {
    function seed(address attacker) external {
        uint24 day = _simulatedDayIndex();
        level = 4;
        purchaseStartDay = day - 3;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        jackpotCounter = 0;
        jackpotFlags = 0;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        gameOver = false;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 0;
        dailyTicketBudgetsPacked = 0;
        dailyJackpotCoinTicketsPending = false;
        goldenTicket = 0;
        _setPrizePools(30 ether, 100 ether);
        currentPrizePool = 80 ether;
        claimablePool = 0;
        yieldAccumulator = 0;
        rngWordByDay[day - 1] = 123_456;
        // One settled hero: quadrant 1, symbol 5. A wager placed during the request
        // window belongs to `day`, never to this sealed ledger.
        dailyHeroWagers[day - 1][1] = uint256(1000) << (5 * 32);
        whalePassClaims[attacker] = 2;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);

        // Word 2's raw board is [12,98,134,215]; the committed hero changes 98 to 101.
        // Distinct source-level owners make an early-bird/main source swap observable.
        uint8[4] memory traits = [uint8(12), 101, 134, 215];
        for (uint24 lvl = 4; lvl <= 5; ++lvl) {
            for (uint8 q; q < 4; ++q) {
                _seedBucket(lvl, traits[q], address(uint160(0x1000 + (lvl - 4) * 16 + q)), 128);
                // Other paid owners exist: the absence of a hero, or reading the live
                // day's rival hero, must select a different persisted owner and fail.
                _seedBucket(lvl, uint8(q * 64 + 1), address(uint160(0x2000 + (lvl - 4) * 16 + q)), 128);
            }
            _seedBucket(lvl, 98, address(uint160(0x3000 + lvl)), 128);
            _seedBucket(lvl, 103, address(uint160(0x4000 + lvl)), 128);
        }
    }
}

/// @notice Outcome-level commitment proof for the ordinary first jackpot day's ETH,
/// early-bird tickets and main tickets. Uses public advanceGame, the real VRF callback,
/// and separate bounded stages; it never calls a privileged jackpot payout directly.
///
/// Independent word-2 oracle: raw traits [12,98,134,215], sealed hero -> [12,101,134,215],
/// hash(2,4)&3 == 3 -> solo q0; daily bps = 765. With 80 ETH current and 100 ETH future,
/// freeze removes 1 ETH to pending, daily budgets are 4.896 ETH / 1.224 ETH tickets,
/// early bird is 2.97 ETH. Price(5)=.02, entry unit=.005: ETH pays [2.016,.96,.96,.96];
/// main gives [0,64,64,96] entries; early bird [0,160,192,160] entries. These constants
/// are not obtained from live events, production jackpot helpers or the compared branch.
///
/// Scope: seeded materialized one-owner-per-trait cohorts, no deities, no gold ladder,
/// no pass conversion, no turbo/final-day/century path. Random sampling within a mixed-owner
/// bucket is covered elsewhere. Pending revenues are reconciled, not assumed immutable.
contract DailyJackpotCommitmentFreezeTest is DeployProtocol {
    address private constant ATTACKER = address(0xA771);
    uint256 private constant WORD = 2;
    bytes32 private constant ADVANCE = keccak256("Advance(uint8,uint24)");
    bytes4 private constant RNG_LOCKED = bytes4(keccak256("RngLocked()"));
    uint24 private day;

    struct Result {
        bytes32 outcomes;
        uint256 steps;
        uint256 mutations;
        uint256 pendingNext;
        uint256 pendingFuture;
    }

    function setUp() public {
        _deployProtocol();
        uint256 start = (399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;
        vm.warp(start);
        vm.deal(address(game), 210 ether);
        vm.deal(ATTACKER, 100 ether);
        bytes memory runtime = address(game).code;
        vm.etch(address(game), type(DailyJackpotCommitmentSeeder).runtimeCode);
        DailyJackpotCommitmentSeeder(payable(address(game))).seed(ATTACKER);
        vm.etch(address(game), runtime);
        day = game.currentDayView();
        vm.warp(start - 1 days);
        vm.prank(address(game));
        crapsBattle.openBonusDay();
        vm.warp(start);
        assertFalse(game.rngLocked());
        assertTrue(game.jackpotPhase());
        assertEq(game.gameOverTimestamp(), 0, "live jackpot fixture");
    }

    function _owner(uint256 cohort, uint256 quadrant) private pure returns (address) {
        return address(uint160(0x1000 + cohort * 16 + quadrant));
    }

    function _pending() private view returns (uint256 next, uint256 future) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(11))));
        return (uint128(packed), packed >> 128);
    }

    function _budgets() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(6))));
    }

    function _packed() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(0)));
    }

    function _hero(uint24 forDay) private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(keccak256(abi.encode(forDay, uint256(44)))) + 1)));
    }

    function _advance() private returns (uint8 stage) {
        assertTrue(game.advanceDue(), "a bounded stage must remain publicly reachable");
        vm.recordLogs();
        game.advanceGame();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
                ++found;
            }
        }
        assertEq(found, 1, "one progress marker per advance");
    }

    function _perturb() private {
        assertTrue(game.rngLocked(), "probe must exercise the actual committed window");
        uint256 oldHero = _hero(day - 1);
        uint256 liveHero = _hero(day);
        uint256 liveNext = game.nextPrizePoolView();
        uint256 liveFuture = game.futurePrizePoolView();
        uint256 oldOwed = game.entriesOwedView(4, ATTACKER);
        (uint256 pendingNext, uint256 pendingFuture) = _pending();
        vm.startPrank(ATTACKER);
        // These both SUCCEED: a late purchase adds a write-cohort owner and a late
        // ETH wager adds a rival hero to today's ledger. Neither can enter this draw.
        game.purchase{value: 0.01 ether}(ATTACKER, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        game.placeDegeneretteBet{value: 0.01 ether}(ATTACKER, 0, 0.01 ether, 1, 15);
        vm.expectRevert(RNG_LOCKED);
        game.claimWhalePass(ATTACKER);
        vm.expectRevert(RNG_LOCKED);
        game.purchaseWhalePass{value: 20 ether}(ATTACKER, 1, bytes32(0));
        vm.stopPrank();
        assertEq(game.openBoxes(1000), 0, "public box settlement cannot bypass the daily lock");
        assertGt(game.entriesOwedView(4, ATTACKER), oldOwed, "late purchase must really add owed entries");
        assertGt(_hero(day), liveHero, "late wager must really write the rival hero");
        assertEq(_hero(day - 1), oldHero, "committed hero ledger unchanged");
        assertEq(game.nextPrizePoolView(), liveNext, "late revenue cannot change the frozen next pool");
        assertEq(game.futurePrizePoolView(), liveFuture, "late revenue cannot change the frozen future pool");
        (uint256 next, uint256 future) = _pending();
        assertGt(next + future, pendingNext + pendingFuture, "late revenue must reach pending backing");
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _assertRecipients(bool paidEth, bool early, bool main) private view returns (bytes32 digest) {
        uint256[4] memory eth = [uint256(2.016 ether), 0.96 ether, 0.96 ether, 0.96 ether];
        uint256[4] memory earlyEntries = [uint256(0), 160, 192, 160];
        uint256[4] memory mainEntries = [uint256(0), 64, 64, 96];
        for (uint256 q; q < 4; ++q) {
            address currentOwner = _owner(0, q);
            address earlyOwner = _owner(1, q);
            uint256 credited = game.claimableWinningsOf(currentOwner);
            uint256 mainOwed = game.entriesOwedView(5, currentOwner);
            uint256 earlyOwed = game.entriesOwedView(5, earlyOwner);
            assertEq(credited, paidEth ? eth[q] : 0, "ETH recipient must match committed board and exact share");
            assertEq(mainOwed, main ? mainEntries[q] : 0, "main tickets must belong to committed current-level owners");
            assertEq(earlyOwed, early ? earlyEntries[q] : 0, "early tickets must belong to committed next-level owners");
            assertEq(game.claimableWinningsOf(earlyOwner), 0, "early cohort cannot receive current-level ETH");
            assertEq(game.entriesOwedView(4, currentOwner), 0, "daily awards queue at the next level");
            digest = keccak256(abi.encode(digest, currentOwner, credited, mainOwed, earlyOwner, earlyOwed));
            for (uint256 cohort; cohort < 2; ++cohort) {
                address other = address(uint160(0x2000 + cohort * 16 + q));
                assertEq(game.claimableWinningsOf(other), 0, "unselected paid owner received ETH");
                assertEq(game.entriesOwedView(5, other), 0, "unselected paid owner received tickets");
            }
        }
        for (uint256 lvl = 4; lvl <= 5; ++lvl) {
            for (uint256 base = 0x3000; base <= 0x4000; base += 0x1000) {
                address other = address(uint160(base + lvl));
                assertEq(game.claimableWinningsOf(other), 0, "uncommitted hero selected an ETH owner");
                assertEq(game.entriesOwedView(5, other), 0, "uncommitted hero selected a ticket owner");
            }
        }
        assertEq(game.claimableWinningsOf(ATTACKER), 0, "late buyer cannot join committed ETH cohort");
        assertEq(game.entriesOwedView(5, ATTACKER), 0, "late buyer cannot join committed prize cohort");
    }

    function _run(bool perturb, uint256 word) private returns (Result memory result) {
        assertEq(_advance(), 1, "first call must request fresh entropy");
        assertTrue(game.rngLocked());
        assertEq(uint24(_packed() >> 24), day - 1, "logical day frozen at request");
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled);
        assertEq(game.futurePrizePoolView(), 99 ether, "freeze's 1% pending seed");
        if (perturb) {
            _perturb();
            ++result.mutations;
        }
        mockVRF.fulfillRandomWords(request, word);
        (,, fulfilled) = mockVRF.pendingRequests(request);
        assertTrue(fulfilled);

        bool paidEth;
        bool early;
        bool main;
        for (; result.steps < 20 && game.rngLocked(); ++result.steps) {
            if (perturb) {
                _perturb();
                ++result.mutations;
            }
            (result.pendingNext, result.pendingFuture) = _pending();
            uint8 stage = _advance();
            if (stage == 10) {
                assertFalse(paidEth, "ETH stage cannot pay twice");
                paidEth = true;
                assertEq(game.currentPrizePoolView(), 73.88 ether, "current debit = ETH plus main-ticket backing");
                assertEq(game.nextPrizePoolView(), 34.194 ether, "main and early ticket backing moved exactly");
                assertEq(game.futurePrizePoolView(), 96.03 ether, "early budget debited from frozen future pool");
                assertEq(game.claimablePoolView(), 4.896 ether, "liability equals all recipient ETH credits");
                assertEq(uint64(_budgets() >> 8), 244, "main entry budget latched once");
                assertEq(uint64(_budgets() >> 144), 594, "early entry budget latched once");
            } else if (stage == 14) {
                assertTrue(paidEth);
                assertFalse(early, "early stage cannot pay twice");
                early = true;
                assertEq(uint64(_budgets() >> 144), 0, "early field consumed");
                assertEq(uint64(_budgets() >> 8), 244, "main field survives early stage");
            } else if (stage == 8) {
                assertTrue(paidEth && early, "main stage must follow ETH and early stages");
                main = true;
                assertEq(_budgets(), 0, "all daily budget fields consumed");
            } else {
                assertTrue(stage == 18 || stage == 16 || stage == 5, "unexpected daily path");
                assertFalse(paidEth, "other work cannot intervene in priced payout legs");
            }
            result.outcomes = _assertRecipients(paidEth, early, main);
            if (!main) {
                assertTrue(game.rngLocked(), "lock survives between distinct payout stages");
                assertEq(uint24(_packed() >> 24), day - 1, "day cannot seal between payout stages");
            }
        }
        assertTrue(paidEth && early && main, "all three financial stages must execute");
        assertFalse(game.rngLocked(), "bounded daily chain must seal");
        assertEq(uint24(_packed() >> 24), day, "logical day advanced exactly once");
        assertEq(uint8(_packed() >> 128), 1, "jackpot counter advanced exactly once");
        assertEq(game.rngWordForDay(day), word, "daily word is the delivered commitment");
        assertEq(game.currentPrizePoolView(), 73.88 ether);
        assertEq(game.claimablePoolView(), 4.896 ether);
        assertEq(game.nextPrizePoolView(), 34.194 ether + result.pendingNext, "unfreeze merges actual pending next");
        assertEq(
            game.futurePrizePoolView(), 96.03 ether + result.pendingFuture, "unfreeze merges actual pending future"
        );
        (uint256 pendingNext, uint256 pendingFuture) = _pending();
        assertEq(pendingNext + pendingFuture, 0, "pending buffer clears at seal");
    }

    function testDailyEthAndBothTicketLegsKeepCommittedOwners() public {
        uint256 snapshot = vm.snapshotState();
        Result memory baseline = _run(false, WORD);
        assertTrue(vm.revertToState(snapshot));
        Result memory attacked = _run(true, WORD);
        assertEq(attacked.outcomes, baseline.outcomes, "public mutations changed persisted prize ownership or amounts");
        assertEq(attacked.steps, baseline.steps, "late work must not enter the committed daily stages");
        assertGe(attacked.mutations, 4, "before fulfillment and between all three financial stages");
        assertGt(attacked.pendingNext + attacked.pendingFuture, baseline.pendingNext + baseline.pendingFuture);
    }

    /// @dev A negative oracle control, separate from the scratch-production mutation campaign.
    /// It cannot pass merely because two copies of the same wrong implementation agree.
    function testIndependentOutcomeOracleRejectsWrongWord() public {
        vm.expectRevert();
        this.runWrongWord();
    }

    function runWrongWord() external {
        _run(false, WORD ^ 1);
    }
}
