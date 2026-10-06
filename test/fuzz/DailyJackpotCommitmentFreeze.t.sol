// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

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
        _recordDailyRng(day - 1, 123_456);
        // One settled hero: quadrant 1, symbol 5. A wager placed during the request
        // window belongs to `day`, never to this sealed ledger.
        lootboxRngPacked = _recordDailyHeroWager(day - 1, 1, 5, 1000, lootboxRngPacked);
        _seedHalfPasses(attacker, 2);
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
/// early-bird tickets and main tickets. Uses public mineFlip, the real VRF callback,
/// and separate bounded stages; it never calls a privileged jackpot payout directly.
///
/// Independent word-2 oracle: raw traits [12,98,134,215], sealed hero -> [12,101,134,215],
/// hash(2,4)&3 == 3 -> solo q0; daily bps = 765. With 80 ETH current and 100 ETH future,
/// freeze removes 1 ETH to pending, daily budgets are 4.896 ETH / 1.224 ETH tickets,
/// early bird is 2.97 ETH. Price(5)=.02, entry unit=.005: ETH pays [2.296,.9,.9,.8] (whole 0.1 ETH
/// units, non-solo leftovers to the solo);
/// main gives [0,64,64,96] entries; early bird [0,128,128,128] entries (96-winner cap). These constants
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

    function _hero(uint24 forDay) private view returns (uint256 packed) {
        for (uint8 symbol; symbol < 8; ++symbol) {
            packed |= game.getDailyHeroWager(forDay, 1, symbol) << (uint256(symbol) * 32);
        }
    }

    /// @dev One public mineFlip. The engine composes every admitted checkpoint into a call, so
    ///      each call is given the smallest of a fixed ladder of allowances that admits work:
    ///      1.5M admits single payout checkpoints (never a second payout stage's setup), larger
    ///      rungs only the indivisible request / word-apply actions. Returns every progress
    ///      marker of the call, in order.
    function _advance() private returns (uint8[] memory stages) {
        assertTrue(game.advanceDue(), "a bounded stage must remain publicly reachable");
        uint256[10] memory ladder = [uint256(1_500_000), 2_000_000, 2_500_000, 3_000_000, 3_500_000, 4_000_000,
            4_500_000, 6_000_000, 10_000_000, 16_700_000];
        Vm.Log[] memory logs;
        for (uint256 r; r < ladder.length; ++r) {
            vm.recordLogs();
            try game.mineFlip{gas: ladder[r]}() {
                logs = vm.getRecordedLogs();
                break;
            } catch (bytes memory err) {
                vm.getRecordedLogs();
                assertEq(bytes4(err), MineFlipGas.InsufficientExecutionGas.selector, "only an allowance refusal retries");
                assertTrue(r + 1 < ladder.length, "a realistic allowance must make progress");
            }
        }
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE) ++found;
        }
        stages = new uint8[](found);
        found = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE) {
                (stages[found++],) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    /// @dev Tickets an owner holds at level 5: still-queued entries plus entries materialized
    ///      into the level-5 trait buckets (main daily awards materialize directly into the live
    ///      next-level buffer, 95d88f68b).
    function _level5Entries(address owner) private view returns (uint256 total) {
        total = game.entriesOwedView(5, owner);
        for (uint16 trait; trait < 256; ++trait) {
            (uint24 count,,) = game.getEntries(uint8(trait), 5, 0, type(uint32).max, owner);
            total += count;
        }
    }

    function _coinTicketsPending() private view returns (bool) {
        return (_packed() >> 176) & 1 != 0;
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

    /// @dev Leg states: 0 not started (nothing paid), 1 part-way through its checkpoint calls (at
    ///      most the committed amount, to the committed owners), 2 complete (exactly committed).
    function _expectLeg(uint256 actual, uint256 committed, uint8 state, string memory reason) private pure {
        if (state == 2) assertEq(actual, committed, reason);
        else if (state == 1) assertLe(actual, committed, reason);
        else assertEq(actual, 0, reason);
    }

    function _assertRecipients(uint8 ethState, uint8 earlyState, uint8 mainState) private view returns (bytes32 digest) {
        // Whole 0.1 ETH units, at most the [32,16,4] targets (5b25fded0): each 0.96 ETH non-solo
        // share pays 9 x 0.1 / 9 x 0.1 / 4 x 0.2 to its one owner; the .06+.06+.16 leftovers
        // move to the solo, which settles last (was the exact [2.016,.96,.96,.96]).
        uint256[4] memory eth = [uint256(2.296 ether), 0.9 ether, 0.9 ether, 0.8 ether];
        // 96-winner ticket cap (5b25fded0; was 128): 3 non-solo quadrants x 32 winners x 1 ticket.
        uint256[4] memory earlyEntries = [uint256(0), 128, 128, 128];
        uint256[4] memory mainEntries = [uint256(0), 64, 64, 96];
        for (uint256 q; q < 4; ++q) {
            address currentOwner = _owner(0, q);
            address earlyOwner = _owner(1, q);
            uint256 credited = game.claimableWinningsOf(currentOwner);
            uint256 mainOwed = _level5Entries(currentOwner);
            // Cohort-1 owners hold 128 seeded level-5 entries; early-bird awards stay queued.
            uint256 earlyOwed = game.entriesOwedView(5, earlyOwner);
            _expectLeg(credited, eth[q], ethState, "ETH recipient must match committed board and exact share");
            _expectLeg(mainOwed, mainEntries[q], mainState, "main tickets must belong to committed current-level owners");
            _expectLeg(earlyOwed, earlyEntries[q], earlyState, "early tickets must belong to committed next-level owners");
            assertEq(game.claimableWinningsOf(earlyOwner), 0, "early cohort cannot receive current-level ETH");
            assertEq(game.entriesOwedView(4, currentOwner), 0, "daily awards queue at the next level");
            digest = keccak256(abi.encode(digest, currentOwner, credited, mainOwed, earlyOwner, earlyOwed));
            for (uint256 cohort; cohort < 2; ++cohort) {
                address other = address(uint160(0x2000 + cohort * 16 + q));
                assertEq(game.claimableWinningsOf(other), 0, "unselected paid owner received ETH");
                assertEq(_level5Entries(other), cohort == 1 ? 128 : 0, "unselected paid owner received tickets");
            }
        }
        for (uint256 lvl = 4; lvl <= 5; ++lvl) {
            for (uint256 base = 0x3000; base <= 0x4000; base += 0x1000) {
                address other = address(uint160(base + lvl));
                assertEq(game.claimableWinningsOf(other), 0, "uncommitted hero selected an ETH owner");
                assertEq(_level5Entries(other), lvl == 5 ? 128 : 0, "uncommitted hero selected a ticket owner");
            }
        }
        assertEq(game.claimableWinningsOf(ATTACKER), 0, "late buyer cannot join committed ETH cohort");
        assertEq(game.entriesOwedView(5, ATTACKER), 0, "late buyer cannot join committed prize cohort");
    }

    function _run(bool perturb, uint256 word) private returns (Result memory result) {
        // The synthetic day-400 jump leaves expired Craps maintenance (one checkpoint per call)
        // ahead of the request; the first call that progresses the day must request fresh entropy.
        uint8[] memory first;
        for (uint256 i; i < 1000; ++i) {
            first = _advance();
            if (first.length != 0) break;
            assertFalse(game.rngLocked(), "maintenance runs before the request");
        }
        assertEq(first.length, 1, "the request call carries one marker");
        assertEq(first[0], 1, "first call must request fresh entropy");
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
        uint256 phase;
        for (; result.steps < 200 && game.rngLocked(); ++result.steps) {
            if (perturb) {
                _perturb();
                ++result.mutations;
            }
            (result.pendingNext, result.pendingFuture) = _pending();
            uint8[] memory stages = _advance();
            // Legs may span several checkpoint calls, and the engine composes every admitted
            // checkpoint into a call: once the battle completes, cheap legs can share its call.
            // Markers must still follow the committed order, and a leg's completion is read from
            // the field it consumes.
            bool sealedNow;
            bool laterLeg;
            for (uint256 k; k < stages.length; ++k) {
                uint8 stage = stages[k];
                if (stage == 10) {
                    assertLe(phase, 1, "ETH leg follows the word and battle, precedes ticket legs");
                    phase = 1;
                } else if (stage == 14) {
                    assertLe(phase, 2, "early leg precedes the main leg");
                    phase = 2;
                    laterLeg = true;
                } else if (stage == 8) {
                    assertLe(phase, 3, "main leg is last");
                    phase = 3;
                    laterLeg = true;
                    sealedNow = true;
                } else {
                    assertTrue(stage == 18 || stage == 16 || stage == 5, "unexpected daily path");
                    assertEq(phase, 0, "other work cannot intervene in priced payout legs");
                }
            }
            if (!paidEth && (_coinTicketsPending() || laterLeg)) {
                paidEth = true;
                assertEq(game.currentPrizePoolView(), 73.88 ether, "current debit = ETH plus main-ticket backing");
                assertEq(game.claimablePoolView(), 4.896 ether, "liability equals all recipient ETH credits");
                if (!sealedNow) {
                    // The seal (main leg) merges pending revenue; checked at the end instead.
                    assertEq(game.nextPrizePoolView(), 34.194 ether, "main and early ticket backing moved exactly");
                    assertEq(game.futurePrizePoolView(), 96.03 ether, "early budget debited from frozen future pool");
                }
                if (!laterLeg) {
                    assertEq(uint64(_budgets() >> 8), 244, "main entry budget latched once");
                    assertEq(uint64(_budgets() >> 144), 594, "early entry budget latched once");
                }
            }
            if (paidEth && !early && uint64(_budgets() >> 144) == 0) {
                early = true;
                if (!sealedNow) assertEq(uint64(_budgets() >> 8), 244, "main field survives early stage");
            }
            if (early && !main && _budgets() == 0 && !_coinTicketsPending()) {
                main = true;
                assertTrue(sealedNow, "the main leg seals the day in its own call");
            }
            result.outcomes = _assertRecipients(
                paidEth ? 2 : phase >= 1 ? 1 : 0, early ? 2 : phase >= 2 ? 1 : 0, main ? 2 : phase >= 3 ? 1 : 0
            );
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
