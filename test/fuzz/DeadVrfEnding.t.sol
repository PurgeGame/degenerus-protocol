// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {DeadVrfSeeder} from "./helpers/DeadVrfSeeder.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Liveness predicate harness: storage-only, no deployment.
contract DeadVrfLivenessHarness is DegenerusGameStorage {
    function seed(uint24 lvl, uint24 age, uint48 requestTime, uint24 sealedAge, uint8 phase, uint256 word)
        external
    {
        level = lvl;
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - age;
        dailyIdx = day - sealedAge;
        rngRequestTime = requestTime;
        _setRngRequestActive(requestTime > 1);
        rngWordCurrent = word < 2 ? RNG_WORD_WAITING : word;
        // The last daily word was applied on the last sealed day (an unattended gap since then).
        lastVrfProcessedTimestamp = uint48(block.timestamp - uint256(sealedAge) * 1 days);
        lastPurchaseDay = phase == 1;
        jackpotPhaseFlag = phase == 2;
        lootboxRngPacked = 1;
    }

    function applyWordFor(uint48 t, uint256 word) external {
        _recordDailyRng(_simulatedDayIndexAt(t), word);
    }

    function startEnding() external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
    }

    function markRetrySpent() external {
        _spendRngRetry();
    }

    function seedMiddayRequest(uint48 t) external {
        rngRequestTime = t;
        _setRngRequestActive(t > 1);
        _setRngSessionPublished(false);
        vrfRequestId = 777;
        rngLockedFlag = false;
        _recordDailyRng(_simulatedDayIndexAt(t), 123);
    }

    function latchDeadMidday() external {
        _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
        _setRngRequestActive(false);
    }

    function liveness() external view returns (bool) {
        return _livenessTriggered();
    }

    function vrfDead() external view returns (bool) {
        return _vrfDead();
    }
}

/// @notice The trigger's three causes: a request unanswered for 14 days (VRF dead), 30 days
///         without a sealed day, and the purchase deadline — which fires only once the game
///         has caught up, so a stall across it has the whole 14-day window to recover.
contract DeadVrfLivenessTest is Test {
    DeadVrfLivenessHarness private h;

    function setUp() public {
        vm.warp(1000 days + 12 hours);
        h = new DeadVrfLivenessHarness();
    }

    function test_stallAcrossDeadlineWaitsForTheVrfDeadWindow() public {
        // Request sent on the deadline day (sealed day before it), never answered.
        uint48 sent = uint48(block.timestamp - 2 days);
        h.seed(5, 32, sent, 3, 0, 0);
        assertFalse(h.liveness(), "past the deadline but behind: the deadline waits");
        vm.warp(uint256(sent) + 14 days - 1);
        assertFalse(h.liveness(), "still inside the VRF-dead window");
        vm.warp(uint256(sent) + 14 days);
        assertTrue(h.vrfDead(), "14 days unanswered");
        assertTrue(h.liveness(), "VRF dead ends the game");
    }

    function test_retryBitKeepsTheWindowAndTheDay() public {
        uint48 sent = uint48(block.timestamp - 2 days);
        h.seed(5, 32, sent, 3, 0, 0);
        h.markRetrySpent();
        assertFalse(h.liveness(), "a spent retry does not end the grace");
        vm.warp(uint256(sent) + 14 days - 1);
        assertFalse(h.liveness(), "the retry did not restart or extend the window");
        vm.warp(uint256(sent) + 14 days);
        assertTrue(h.liveness(), "the window runs from the original send");
    }

    function test_backlogWordIsNeverDead() public {
        uint48 sent = uint48(block.timestamp - 20 days);
        h.seed(5, 10, sent, 20, 2, 0xB0B);
        h.applyWordFor(sent, 0xB0B);
        assertFalse(h.vrfDead(), "an applied word is not a dead VRF");
        assertFalse(h.liveness(), "a 20-day backlog in the jackpot phase stays alive");
    }

    function test_deliveredWordMeansVrfWorks() public {
        h.seed(5, 10, uint48(block.timestamp - 15 days), 15, 2, 0xB0B);
        assertFalse(h.vrfDead(), "delivered but never applied (a stuck day): VRF works, not dead");
        h.seed(5, 10, uint48(block.timestamp - 15 days), 15, 2, 0);
        assertTrue(h.vrfDead(), "nothing delivered for 14 days: dead");
    }

    function test_deadlineFiresOnceCaughtUpOrOnceTheEndingStarted() public {
        h.seed(5, 31, 0, 1, 0, 0);
        assertTrue(h.liveness(), "caught up past the deadline");
        h.seed(5, 33, 0, 3, 0, 0);
        assertFalse(h.liveness(), "behind past the deadline (a gap, however it arose): waits for its credit");
        h.seed(5, 33, uint48(block.timestamp - 2 days), 3, 0, 0);
        assertFalse(h.liveness(), "behind with a request in flight (a stall): waits for its credit");
        h.startEnding();
        assertTrue(h.liveness(), "an ending in progress keeps it on");
    }

    function test_deadlineWaitsOutADayThatAlreadyHasItsWord() public {
        h.seed(5, 31, 0, 1, 0, 0);
        assertTrue(h.liveness(), "start of a caught-up day past the deadline");
        h.applyWordFor(uint48(block.timestamp), 0xB0B);
        assertFalse(h.liveness(), "a worded day finishes on its own word");
        h.seed(5, 31, 0, 0, 0, 0);
        assertFalse(h.liveness(), "a day already sealed: the ending starts tomorrow");
        h.startEnding();
        assertTrue(h.liveness(), "an ending in progress keeps it on");
    }

    function test_middayRequestUnansweredFourteenDaysIsDeadAndStaysLatched() public {
        uint48 sent = uint48(block.timestamp - 15 days);
        h.seed(5, 10, sent, 15, 0, 0);
        h.seedMiddayRequest(sent);
        assertTrue(h.vrfDead(), "no promotion rescues a mid-day request: 14 days unanswered is dead");
        h.startEnding();
        assertTrue(h.vrfDead(), "a terminal ending cannot promote it and times out");
        h.latchDeadMidday();
        assertTrue(h.vrfDead(), "dropping the request ID cannot reopen the game");
    }

    function test_middayRequestPastDeadmanUsesDeterministicEnding() public {
        uint48 sent = uint48(block.timestamp - 31 days);
        h.seed(5, 10, sent, 31, 0, 0);
        h.seedMiddayRequest(sent);
        assertTrue(h.vrfDead(), "a mid-day request past the deadman is dead");
        assertTrue(h.liveness(), "deterministic exit stays reachable");
    }
}

contract DeadVrfEndingTest is DeployProtocol {
    uint24 private constant LVL = 5000; // purchase phase: the terminal ticket level is LVL + 1 (no genesis passes reach it)
    uint24 private constant TLVL = LVL + 1;
    bytes32 private constant PAYOUT_FIXED_SIG =
        keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)");

    bytes private realCode;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private carol = makeAddr("carol");
    address private dave = makeAddr("dave");
    address private erin = makeAddr("erin");
    address private frank = makeAddr("frank");

    uint32 private davePos;
    uint32 private erinPos;
    uint24 private foilDay;
    uint256 private foilIdx;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 200 days);
        vm.deal(address(game), 100 ether);
        realCode = address(game).code;
    }

    function _seeder() private returns (DeadVrfSeeder s) {
        vm.etch(address(game), type(DeadVrfSeeder).runtimeCode);
        s = DeadVrfSeeder(payable(address(game)));
    }

    function _restore() private {
        vm.etch(address(game), realCode);
    }

    function _seedHoldings() private {
        DeadVrfSeeder s = _seeder();
        s.seedDeadStall(LVL);
        // Created: trait 3 holds alice x3 + bob x1; trait 200 holds carol x2.
        s.seedCreated(TLVL, 3, alice, 3);
        s.seedCreated(TLVL, 3, bob, 1);
        s.seedCreated(TLVL, 200, carol, 2);
        // Uncreated: dave 4 entries + half an entry (read side), erin 2 entries (write side).
        davePos = s.seedQueued(TLVL, false, dave, 4, 50);
        erinPos = s.seedQueued(TLVL, true, erin, 2, 0);
        // Uncreated: frank's foil pack, resolve day never worded.
        foilDay = uint24(block.timestamp / 1 days);
        foilIdx = s.seedFoil(TLVL, foilDay, frank);
        _restore();
    }

    function _endGame() private {
        for (uint256 i; i < 20 && !game.gameOver(); ++i) game.mineFlip(0);
        assertTrue(game.gameOver(), "dead ending reached game over");
    }

    function _state() private returns (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits, uint256 left) {
        (pot, total, created, uncreated, traits, left) = _seeder().deadState();
        _restore();
    }

    function _ref(uint256 kind, uint256 hi, uint256 lo) private pure returns (uint256) {
        return (kind << 248) | (hi << (kind == 1 ? 32 : 64)) | lo;
    }

    function test_deadEndingSplitsThePotDeterministically() public {
        _seedHoldings();
        assertTrue(game.livenessTriggered(), "request unanswered 15 days");
        _endGame();

        (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits,) = _state();
        assertGt(pot, 0, "a pot was fixed");
        assertEq(created, 6, "six created tickets");
        assertEq(traits, 2, "two non-empty traits");
        assertEq(uncreated, 450 + 200 + 1600, "4.5 + 2 queued entries and one 16-entry foil pack");
        assertEq(total, 600 + 2250, "total weight");

        uint256 perTrait = (pot * created * 100) / total / traits;

        uint256[] memory refs = new uint256[](3);
        refs[0] = _ref(0, 3, 0);
        refs[1] = _ref(0, 3, 1);
        refs[2] = _ref(0, 3, 2);
        game.claimDeadVrf(game.walletIdOf(alice), refs);
        assertEq(game.claimableWinningsOf(alice), 3 * (perTrait / 4), "alice: 3 of trait 3's four tickets");

        uint256[] memory one = new uint256[](1);
        one[0] = _ref(0, 3, 3);
        uint32 aliceId = game.walletIdOf(alice);
        vm.expectRevert();
        game.claimDeadVrf(aliceId, one); // bob's ticket, not alice's
        game.claimDeadVrf(game.walletIdOf(bob), one);
        assertEq(game.claimableWinningsOf(bob), perTrait / 4, "bob: 1 of trait 3's four tickets");
        uint32 bobId = game.walletIdOf(bob);
        vm.expectRevert();
        game.claimDeadVrf(bobId, one); // already claimed

        uint256[] memory two = new uint256[](2);
        two[0] = _ref(0, 200, 0);
        two[1] = _ref(0, 200, 1);
        game.claimDeadVrf(game.walletIdOf(carol), two);
        assertEq(game.claimableWinningsOf(carol), 2 * (perTrait / 2), "carol: a whole trait's share");

        one[0] = _ref(1, TLVL | (uint24(1) << 23), davePos);
        game.claimDeadVrf(game.walletIdOf(dave), one);
        assertEq(game.claimableWinningsOf(dave), (pot * 450) / total, "dave: the average for 4.5 entries");
        uint32 daveId = game.walletIdOf(dave);
        vm.expectRevert();
        game.claimDeadVrf(daveId, one); // owed zeroed

        one[0] = _ref(1, TLVL, erinPos);
        game.claimDeadVrf(game.walletIdOf(erin), one);
        assertEq(game.claimableWinningsOf(erin), (pot * 200) / total, "erin: the average for 2 entries");

        one[0] = _ref(2, foilDay & 1, foilIdx);
        game.claimDeadVrf(game.walletIdOf(frank), one);
        assertEq(game.claimableWinningsOf(frank), (pot * 1600) / total, "frank: the average for a foil pack");
        uint32 frankId = game.walletIdOf(frank);
        vm.expectRevert();
        game.claimDeadVrf(frankId, one); // pack word zeroed

        uint256 paid = game.claimableWinningsOf(alice) + game.claimableWinningsOf(bob)
            + game.claimableWinningsOf(carol) + game.claimableWinningsOf(dave)
            + game.claimableWinningsOf(erin) + game.claimableWinningsOf(frank);
        assertLe(paid, pot, "never more than the pot");
        assertLt(pot - paid, 16, "only rounding dust left");
        (,,,,, uint256 left) = _state();
        assertEq(left, 0, "every uncreated unit claimed exactly once");
    }

    function test_SameStableOwnerClaimsThreeTerminalDomainsExactlyOnce() public {
        DeadVrfSeeder s = _seeder();
        s.seedDeadStall(LVL);
        uint32 id = s.seedQueued(TLVL, false, dave, 3, 0);
        assertEq(s.seedQueued(TLVL, true, dave, 5, 0), id);
        assertEq(s.seedFuture(TLVL, dave, 7), id);
        _restore();
        _endGame();
        (uint256 pot, uint256 total,, uint256 uncreated,,) = _state();
        assertEq(uncreated, 1500);
        assertEq(total, 1500);
        uint32 erinId = game.walletIdOf(erin);
        uint32 daveId = game.walletIdOf(dave);
        uint256[] memory refs = new uint256[](1);
        refs[0] = _ref(1, TLVL | (uint24(1) << 23), id);
        vm.expectRevert(); game.claimDeadVrf(erinId, refs);
        refs[0] = _ref(1, TLVL + 1, id);
        vm.expectRevert(); game.claimDeadVrf(daveId, refs);
        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = _ref(1, TLVL, id);
        duplicate[1] = duplicate[0];
        vm.expectRevert(); game.claimDeadVrf(daveId, duplicate);
        assertEq(game.claimableWinningsOf(dave), 0, "duplicate batch rolls back atomically");
        uint24[3] memory keys = [TLVL | (uint24(1) << 23), TLVL, TLVL | (uint24(1) << 22)];
        uint256[3] memory weights = [uint256(300), 500, 700];
        uint256 paid;
        for (uint256 i; i < 3; ++i) {
            refs[0] = _ref(1, keys[i], id);
            game.claimDeadVrf(daveId, refs);
            paid += pot * weights[i] / total;
            assertEq(game.claimableWinningsOf(dave), paid);
            vm.expectRevert(); game.claimDeadVrf(daveId, refs);
        }
        (,,,,,uint256 left) = _state();
        assertEq(left, 0);
        assertEq(_seeder().pendingWord(TLVL, dave), uint256(1) << 255);
        _restore();
        assertLe(paid, pot);
        assertLt(pot - paid, 3);
    }

    /// @dev After game over the one path that must keep working is the sDGNRS deterministic
    ///      burn. A dead daily request leaves the RNG lock set for good; the burn does not read it.
    function test_sdgnrsDeterministicBurnWorksAfterTheDeadEnding() public {
        address holder = makeAddr("sdgnrs-holder");
        vm.prank(address(game));
        uint256 got = sdgnrs.transferFromPool(sDGNRS.Pool.Reward, holder, 1000e18);
        assertGt(got, 0, "holder funded");
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 10 ether);

        _seedHoldings();
        _endGame();
        assertTrue(game.rngLocked(), "the dead daily request's lock is never released");

        uint256 before = holder.balance;
        vm.prank(holder);
        (uint256 ethOut, uint256 stethOut,) = sdgnrs.burn(got);
        assertGt(ethOut + stethOut, 0, "deterministic burn pays");
        assertEq(holder.balance - before, ethOut, "ETH leg delivered");
        assertEq(sdgnrs.balanceOf(holder), 0, "burned");
    }

    function test_claimsCloseAtTheFinalSweep() public {
        _seedHoldings();
        _endGame();
        vm.warp(block.timestamp + 31 days);
        game.mineFlip(0); // final sweep
        uint256[] memory one = new uint256[](1);
        one[0] = _ref(1, TLVL | (uint24(1) << 23), davePos);
        uint32 daveId = game.walletIdOf(dave);
        vm.expectRevert();
        game.claimDeadVrf(daveId, one);
    }

    /// @dev Both endings resolve an unrolled closed batch at the terminal 100% rate.
    function test_pendingRedemptionResolvesAtExpectedValue() public {
        _seedHoldings();
        vm.expectCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.resolveTerminalRedemptions.selector));
        _endGame();
    }

    /// @dev Real flow: a daily request with no word applied for 14 days ends the game
    ///      deterministically. A word that arrives after the window, before anyone advanced,
    ///      was never applied, so it is late and counts for nothing.
    function test_wordDeliveredAfterTheWindowStillCounts() public {
        // A live level-1 purchase phase, sealed yesterday (setUp's warp alone would trip the
        // 30-day deadman before the stall begins).
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(5);
        _restore();
        // The synthetic 200-day setup also owes expired scheduled-day maintenance (one engine
        // checkpoint per call) before the daily commitment, as in test_swapSpendsTheDailyRetry.
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) game.mineFlip(0);
        uint24 r = game.currentDayView();
        uint256 req = mockVRF.lastRequestId();
        assertTrue(game.rngLocked(), "day R requested");

        vm.warp(block.timestamp + 14 days);
        assertTrue(game.livenessTriggered(), "VRF dead after 14 days with nothing delivered");
        mockVRF.fulfillRandomWords(req, 0xDEAD); // lands late, before anyone advanced
        assertFalse(game.livenessTriggered(), "a delivered word means VRF works");
        for (uint256 i; i < 64 && uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24) < r; ++i) game.mineFlip(0);
        assertEq(uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24), r, "stalled day completed");
        assertEq(game.rngWordForDay(r), 0, "old processing word is not claim history");
        _assertCoinflipResult(r, 0xDEAD);
        assertFalse(game.gameOver(), "the game carries on");
    }

    /// @dev A day stuck in processing (VRF fine) until the 30-day deadman: the ending must draw
    ///      on a terminal word it requests itself, never on the stuck day's word. `applied`
    ///      false = the stuck transaction was the one that would have applied the word.
    function _stuckDayEndsOnAFreshWord(bool applied) private {
        vm.etch(address(game), type(DeadVrfSeeder).runtimeCode);
        uint24 s = DeadVrfSeeder(payable(address(game))).seedStuckDay(LVL, 0x57AC, applied);
        _restore();
        assertTrue(game.livenessTriggered(), "deadman");
        assertFalse(_vrfDeadView(), "a delivered word: VRF works");

        uint256 before = mockVRF.lastRequestId();
        vm.recordLogs();
        for (uint256 i; i < 20 && !game.gameOver(); ++i) {
            game.mineFlip(0);
            uint256 id = mockVRF.lastRequestId();
            if (id != before) {
                (,, bool done) = mockVRF.pendingRequests(id);
                if (!done) mockVRF.fulfillRandomWords(id, 0xF00D);
            }
        }
        assertTrue(game.gameOver(), "ended");
        assertFalse(_sawPayoutFixed(vm.getRecordedLogs()), "the normal VRF ending");
        assertGt(mockVRF.lastRequestId(), before, "on a fresh terminal request");
        uint24 today = game.currentDayView();
        assertTrue(game.rngWordForDay(today) != 0, "applied to the ending's own day");
        assertEq(game.rngWordForDay(s), 0, "old processing words are retired");
        assertEq(game.rngWordForDay(s + 1), 0, "gap words have no archive");
        // The terminal backfill starts after an already-applied day. Gap wins take raw-root
        // bits 1..31 from that original start and pay a fixed double-or-nothing 100% profit
        // (backfilled coinflip days, 60d31f775: stored 100 on a win, 1 on a loss).
        uint24 gapStart = applied ? s + 1 : s;
        if (applied) _assertCoinflipResult(s, 0x57AC);
        else _assertGapCoinflipResult(s, (uint256(0xF00D) >> 1) & 1 != 0);
        _assertGapCoinflipResult(s + 1, (uint256(0xF00D) >> (1 + uint256(s + 1) - gapStart)) & 1 != 0);
    }

    function _assertCoinflipResult(uint24 day, uint256 word) private view {
        _assertCoinflipResult(day, word, word & 1 != 0);
    }

    function _assertGapCoinflipResult(uint24 day, bool expectedWin) private view {
        (uint16 actual, bool win) = coinflip.getCoinflipDayResult(day);
        assertEq(actual, expectedWin ? 100 : 1);
        assertEq(win, expectedWin);
    }

    function _assertCoinflipResult(uint24 day, uint256 word, bool expectedWin) private view {
        (uint16 actual, bool win) = coinflip.getCoinflipDayResult(day);
        uint256 hash = uint256(keccak256(abi.encodePacked(keccak256("degenerus.coinflip.reward-percent"), word, day)));
        uint16 expected = !expectedWin ? 1 : hash % 20 == 0 ? 50 : hash % 20 == 1 ? 150 : uint16(hash % 38 + 78);
        assertEq(actual, expected);
        assertEq(win, expectedWin);
    }

    function test_stuckDayWithAppliedWordEndsOnAFreshWord() public {
        _stuckDayEndsOnAFreshWord(true);
    }

    function test_stuckDayWithDeliveredWordEndsOnAFreshWord() public {
        _stuckDayEndsOnAFreshWord(false);
    }

    function _vrfDeadView() private returns (bool dead) {
        dead = _seeder().vrfDeadView();
        _restore();
    }

    /// @dev A sealed daily day can leave its box/bet cohort pending under serialization. Finish it
    ///      with maximum calibration to defer continuations after first progress, then
    ///      `caller`'s mineFlip issues the mid-day request, the engine's last stage.
    function _mineMiddayRequest(address caller) private returns (uint256 id) {
        uint48 read = RecyclingState.readBuffer(address(game));
        for (uint256 i; i < 50 && !game.boxIndexComplete(read); ++i) game.mineFlip{gas: 2_000_000}(type(uint32).max);
        assertTrue(game.boxIndexComplete(read), "the test's prior delivered read cohort must finish");
        uint256 before = mockVRF.lastRequestId();
        vm.prank(caller);
        game.mineFlip(0);
        id = mockVRF.lastRequestId();
        assertGt(id, before, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "the request is a mid-day one");
    }

    /// @dev The deadline path runs before the normal new-day promotion of a stalled mid-day
    ///      request. If that mid-day request never answers, its day already has a daily word;
    ///      the terminal path must still declare it dead after 14 days and keep liveness latched.
    function test_unansweredMiddayRequestAtDeadlineEndsDeterministically() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(30); // target unmet on the deadline day
        _restore();

        // The synthetic 200-day setup owes expired scheduled-day maintenance first.
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) game.mineFlip(0);
        uint256 dailyId = mockVRF.lastRequestId();
        assertTrue(game.rngLocked(), "deadline day's daily request");
        mockVRF.fulfillRandomWords(dailyId, 0xBEEF);
        for (uint256 i; i < 50 && game.rngLocked(); ++i) game.mineFlip(0);
        assertFalse(game.rngLocked(), "deadline day sealed");
        assertFalse(game.livenessTriggered(), "deadline day remains open");

        // The engine requests a mid-day word on its own for closed Craps windows once the day
        // seals (6d0e64b09); settle that so the buyer's request below is the one left unanswered.
        _runDay(mockVRF);
        uint24 requestDay = game.currentDayView();
        assertTrue(game.rngWordForDay(requestDay) != 0, "mid-day request's day has its daily word");
        address buyer = makeAddr("midday-buyer");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        game.purchase{value: 1 ether}(
            0, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertFalse(game.livenessTriggered(), "small box buy did not meet the pool target");
        _mineMiddayRequest(buyer);
        assertGt(mockVRF.lastRequestId(), dailyId, "a real mid-day request is outstanding");
        uint256 sent = block.timestamp;

        vm.warp(sent + 1 days);
        assertTrue(game.livenessTriggered(), "unmet purchase deadline fires");
        game.mineFlip(0); // terminal path latches and waits on the mid-day request
        assertFalse(game.gameOver(), "the request is still inside its window");

        vm.warp(sent + 14 days - 1);
        assertFalse(game.gameOver());
        vm.warp(sent + 14 days);
        vm.recordLogs();
        _endGame();
        assertTrue(_sawPayoutFixed(vm.getRecordedLogs()), "dead mid-day request uses deterministic payout");
        assertTrue(game.livenessTriggered(), "dead ending stays latched after dropping the request ID");
    }

    /// @dev Real flow: a stall across the purchase deadline keeps the level open. The vault
    ///      owner's retry and a coordinator swap inside the window do not end it, a buyer can
    ///      still meet the target during the stall, and once VRF recovers the level carries on.
    function test_stallAcrossDeadlineKeepsTheLevelRescuable() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(30); // today is the deadline day
        _restore();

        // The synthetic 200-day setup owes expired scheduled-day maintenance first.
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) game.mineFlip(0);
        assertTrue(game.rngLocked(), "deadline day requested; VRF stalls");

        vm.warp(block.timestamp + 21 hours);
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng(); // the vault owner's single retry (20h)
        vm.warp(block.timestamp + 1 days);
        assertFalse(game.livenessTriggered(), "past the deadline, behind, inside the window");

        address buyer = makeAddr("stall-buyer");
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchase{value: 2 ether}(0, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        MockVRFCoordinator fresh = new MockVRFCoordinator();
        uint256 sub = fresh.createSubscription();
        fresh.addConsumer(sub, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(fresh), sub, bytes32(uint256(1)));
        assertFalse(game.livenessTriggered(), "a swap never ends the grace");

        uint256 t = block.timestamp;
        for (uint256 d; d < 8; ++d) {
            for (uint256 i; i < 200; ++i) {
                if (game.level() == 2 && !game.jackpotPhase() && !game.rngLocked()) return;
                assertFalse(game.gameOver(), "rescued level must not end");
                _answer(fresh); // the swap re-sent the request and spent the retry: answer it first
                game.mineFlip(0);
                uint256 id = fresh.lastRequestId();
                if (id != 0) {
                    (,, bool done) = fresh.pendingRequests(id);
                    if (!done) fresh.fulfillRandomWords(id, uint256(keccak256(abi.encode(id))));
                }
                if (!game.rngLocked() && !game.advanceDue()) break;
            }
            t += 1 days;
            vm.warp(t);
        }
        fail("the rescued level did not finish");
    }

    /// @dev Advance (answering every request on `vrf`) until the day seals or the game ends.
    function _runDay(MockVRFCoordinator vrf) private {
        // 1024, not 200: the synthetic 200-day setup owes one expired scheduled-day maintenance
        // checkpoint per call before the day's request (as in test_swapSpendsTheDailyRetry).
        for (uint256 i; i < 1024; ++i) {
            if (game.gameOver()) return;
            _answer(vrf); // a request already in flight must land before the advance can use it
            game.mineFlip(0);
            _answer(vrf);
            if (!game.rngLocked() && !game.advanceDue()) return;
        }
        fail("day did not settle");
    }

    function _answer(MockVRFCoordinator vrf) private {
        uint256 id = vrf.lastRequestId();
        if (id == 0) return;
        (,, bool done) = vrf.pendingRequests(id);
        if (!done) vrf.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, "word"))));
    }

    function _freshCoordinator() private returns (MockVRFCoordinator fresh) {
        fresh = new MockVRFCoordinator();
        uint256 sub = fresh.createSubscription();
        fresh.addConsumer(sub, address(game));
        fresh.fundSubscription(sub, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(fresh), sub, bytes32(uint256(1)));
    }

    /// @dev A lootbox-only mid-day request (no ticket cohort swapped) sent on the deadline day
    ///      and never answered by the old coordinator. Governance swaps in a working one: the
    ///      swap must re-issue that request, so the ending is the normal VRF one rather than
    ///      the deterministic one 14 days later.
    function test_lootboxOnlyMiddayRequestIsReissuedBySwap() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(30);
        _restore();
        _runDay(mockVRF);
        assertFalse(game.rngLocked(), "deadline day sealed");
        // lootbox-only: a box with no ticket leg, so nothing is queued to swap. Its value sits
        // under the mid-day threshold, so only a funded donor's mineFlip requests the word.
        address donor = makeAddr("midday-donor");
        vm.deal(donor, 1 ether);
        vm.prank(donor);
        game.purchase{value: 0.5 ether}(
            0, 0, BoxOrderLib.boCustom(0.5 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertFalse(game.advanceDue(), "a creditless caller has no mid-day request below the threshold");
        mockFeed.setUpdatedAt(block.timestamp); // the credit charge prices off a fresh feed
        vm.fee(1 gwei); // a priced block, so the charge is nonzero
        vm.prank(ContractAddresses.ADMIN);
        game.creditMiddayRng(donor, 1 ether);
        _mineMiddayRequest(donor);
        assertLt(game.middayRngCredits(donor), 1 ether, "the donor's credit paid the threshold gate");

        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
        assertFalse(game.gameOver(), "the ending waits on the request in flight");

        MockVRFCoordinator fresh = _freshCoordinator();
        assertEq(fresh.lastRequestId(), 1, "the swap re-issued the mid-day request");

        vm.recordLogs();
        _runDay(fresh);
        assertTrue(game.gameOver(), "ended");
        assertFalse(_sawPayoutFixed(vm.getRecordedLogs()), "on the normal VRF payout");
    }

    /// @dev The deadline day seals and nobody advances the next day. The skipped day is a gap: it
    ///      is credited and the day after seals normally; the following caught-up day starts the
    ///      ending on a terminal word requested after the freeze.
    function test_skippedDayPastTheDeadlineIsCreditedThenEndsOnAFreshWord() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(30);
        _restore();
        _runDay(mockVRF);
        uint24 dl = game.currentDayView();

        // vm.getBlockTimestamp, not block.timestamp: via-IR caches the latter across warps.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(game.livenessTriggered(), "the first day past the deadline is frozen");
        vm.warp(vm.getBlockTimestamp() + 1 days); // dl + 1 left unattended
        assertEq(game.currentDayView(), dl + 2, "harness: two days past the sealed deadline day");
        assertFalse(game.livenessTriggered(), "the skipped day is a gap: it waits for its credit");
        _runDay(mockVRF);
        assertFalse(game.gameOver(), "the gap is credited and the day seals");
        assertTrue(game.rngWordForDay(dl + 2) != 0, "sealed on its own word");

        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(game.livenessTriggered(), "the next caught-up day past the deadline fires");
        uint256 before = mockVRF.lastRequestId();
        vm.recordLogs();
        _runDay(mockVRF);
        assertTrue(game.gameOver(), "the next advance ends the level");
        assertGt(mockVRF.lastRequestId(), before, "on a terminal word requested after the freeze");
        assertTrue(game.rngWordForDay(dl + 3) != 0, "applied to the ending's own day");
        assertFalse(_sawPayoutFixed(vm.getRecordedLogs()), "the normal VRF payout");
    }

    /// @dev A coordinator swap re-sends a stalled daily request and spends the vault owner's
    ///      retry: the owner cannot follow the swap with a retry that discards the new
    ///      coordinator's first answer.
    function test_swapSpendsTheDailyRetry() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(5);
        _restore();
        // The synthetic 200-day setup also owes expired scheduled-day maintenance.
        // Wait for the actual daily commitment before testing its retry allowance.
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) game.mineFlip(0);
        assertTrue(game.rngLocked(), "daily request stalls");

        vm.warp(block.timestamp + 13 hours);
        MockVRFCoordinator fresh = _freshCoordinator();
        assertEq(fresh.lastRequestId(), 1, "the swap re-sent the daily request");

        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert();
        admin.retryGameRng(); // the coordinator swap already spent the single retry
        assertEq(fresh.lastRequestId(), 1, "no retry after the swap");

        _runDay(fresh);
        assertFalse(game.rngLocked(), "the re-sent request's word completes the day");
    }

    function _terminalQueues() private returns (uint256 readLen, uint256 writeLen, uint256 swapped) {
        (readLen, writeLen, swapped) = _seeder().terminalQueues(TLVL);
        _restore();
    }

    /// @dev Before the ending's one swap, a read-side cohort whose word landed drains on it,
    ///      one batch per call. A caller who starves that batch of gas must not fall through to
    ///      the terminal request: that latches the swap window shut with the write cohort left
    ///      in the write slot, never drawn. The sweep starves the batch at every depth (the
    ///      worker itself, or the nested round drain inside it).
    function test_starvedPreSwapBatchCannotCloseTheSwapWindow() public {
        _checkStarvedPreSwapBatch(false);
    }

    /// @dev A coordinator can refuse the new request. That makes the dangerous fall-through
    ///      cheaper: the swap latch would still close, even though no request ID is installed.
    ///      Keep this affordable witness as well as the successful-request regression.
    function test_starvedPreSwapBatchWithRefusingCoordinatorCannotCloseTheSwapWindow() public {
        _checkStarvedPreSwapBatch(true);
    }

    function _checkStarvedPreSwapBatch(bool refusing) private {
        DeadVrfSeeder s = _seeder();
        s.seedDeadlineWithLandedCohort(LVL, 0xB0B5);
        for (uint160 i = 1; i <= 24; ++i) s.seedQueued(TLVL, false, address(0xD00D0000 + i), 1000, 0);
        uint32 erinAt = s.seedQueued(TLVL, true, erin, 2, 0);
        _restore();
        assertTrue(game.livenessTriggered(), "deadline passed, caught up, VRF alive");
        if (refusing) {
            vm.mockCallRevert(
                address(mockVRF), abi.encodeWithSelector(MockVRFCoordinator.requestRandomWords.selector),
                abi.encodeWithSignature("Error(string)", "coordinator refuses request")
            );
        }
        uint256 req0 = mockVRF.lastRequestId();
        uint256 snap = vm.snapshotState();

        // Realistic-allowance reference (owner rule: the engine spends whatever it is given, so
        // the reference batch is a 10M call, not an unbounded one): one call's cost, then the
        // cost of the call that swaps and sends the terminal request.
        uint256 g0 = gasleft();
        game.mineFlip{gas: 10_000_000}(0);
        uint256 batchGas = g0 - gasleft();
        (uint256 readLen,, uint256 swapped) = _terminalQueues();
        assertEq(swapped, 0, "a batch call leaves the swap window open");
        assertGt(readLen, 0, "one batch does not drain the read side");
        uint256 requestGas;
        for (uint256 i; i < 400 && swapped == 0; ++i) {
            g0 = gasleft();
            game.mineFlip{gas: 10_000_000}(0);
            requestGas = g0 - gasleft();
            (,, swapped) = _terminalQueues();
        }
        assertEq(swapped, 1, "full-gas reference reaches the terminal request attempt");
        if (refusing) assertEq(mockVRF.lastRequestId(), req0, "refused request installs no ID");
        else assertGt(mockVRF.lastRequestId(), req0, "the terminal request went out");
        vm.revertToState(snap);

        // Probe down through the mandatory first unit's actual cost. A survivor must leave
        // the window open with no request. A first-mode worker stops above its parents'
        // tails, so every call that fits the first unit succeeds; the probe continues in 2k
        // steps below two coarse steps until the first unit itself no longer fits. At the
        // lowest allowances even the root can OOG without enough gas to wrap the empty
        // failure; no semantic worker error is allowed.
        uint256 witnessGas;
        uint256 leakGas;
        uint256 step = batchGas / 128;
        for (uint256 g = batchGas; g >= 20_000; g -= g > 2 * step ? step : 2_000) {
            snap = vm.snapshotState();
            try game.mineFlip{gas: g}(0) {
                (,, swapped) = _terminalQueues();
                if (leakGas == 0 && (swapped != 0 || mockVRF.lastRequestId() != req0)) leakGas = g;
            } catch (bytes memory err) {
                // If the miner frame itself exhausts gas, the outer facade wraps its
                // empty revert as EmptyRevert. A spent worker allowance uses WorkGasBound.
                bytes4 selector = bytes4(err);
                assertTrue(err.length == 0 || (err.length == 4 && (
                    selector == MineFlipGas.InsufficientExecutionGas.selector
                    || selector == MineFlipGas.EmptyRevert.selector
                    || selector == MineFlipGas.WorkGasBound.selector
                )), "no semantic worker error");
                witnessGas = g;
            }
            vm.revertToState(snap);
        }
        emit log_named_uint("batchGas", batchGas);
        emit log_named_uint("requestGas", requestGas);
        emit log_named_uint("witnessGas", witnessGas);
        emit log_named_uint("leakGas", leakGas);
        assertGt(witnessGas, 0, "a real batch failure reached the no-own-error guard");

        // End to end: a starved call first (the leak if one exists, else the witness), then full
        // gas. The read side drains, the write cohort swaps in and draws on the terminal word.
        try game.mineFlip{gas: leakGas != 0 ? leakGas : witnessGas}(0) {} catch {}
        if (refusing) vm.clearMockedCalls();
        for (uint256 i; i < 80 && !game.gameOver(); ++i) {
            game.mineFlip(0);
            _answer(mockVRF);
        }
        assertTrue(game.gameOver(), "ended");
        (uint256 rl, uint256 wl, uint256 swp) = _terminalQueues();
        assertEq(swp, 1, "one terminal swap");
        assertEq(rl + wl, 0, "no terminal cohort stranded");
        assertEq(_owedAt(erinAt), 0, "the write cohort was drawn");
        assertEq(leakGas, 0, "a starved call closed the swap window");
    }

    function _owedAt(uint32 posPlusOne) private returns (uint256 owed) {
        owed = _seeder().owedAt(TLVL, posPlusOne);
        _restore();
    }

    function _sealedDay() private returns (uint24 idx) {
        idx = _seeder().sealedDay();
        _restore();
    }

    function _sawPayoutFixed(Vm.Log[] memory logs) private view returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == PAYOUT_FIXED_SIG) {
                return true;
            }
        }
        return false;
    }
}

/// @dev Level-1 purchase-phase state `age` days into its purchase window, sealed yesterday.
contract DeadlineSeeder is DegenerusGame {
    function seed(uint24 age) external {
        // Entering this purchase phase means the prior level's queues, including
        // its frozen level-2 pool, have already materialized.
        TQ.retireCompleted(address(this), 2);
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        levelPrizePool[1] = 10 ether;
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }
}
