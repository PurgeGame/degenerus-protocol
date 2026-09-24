// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

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
        rngWordCurrent = word;
        lastPurchaseDay = phase == 1;
        jackpotPhaseFlag = phase == 2;
        lootboxRngPacked = 1;
    }

    function applyWordFor(uint48 t, uint256 word) external {
        rngWordByDay[_simulatedDayIndexAt(t)] = word;
    }

    function startEnding() external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
    }

    function seedMiddayRequest(uint48 t) external {
        rngRequestTime = t;
        vrfRequestId = 777;
        rngLockedFlag = false;
        rngWordByDay[_simulatedDayIndexAt(t)] = 123;
    }

    function latchDeadMidday() external {
        _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
        vrfRequestId = 0;
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
        uint48 sent = uint48(block.timestamp - 2 days) & ~uint48(1);
        h.seed(5, 32, sent, 3, 0, 0);
        assertFalse(h.liveness(), "past the deadline but behind: the deadline waits");
        vm.warp(uint256(sent) + 14 days - 1);
        assertFalse(h.liveness(), "still inside the VRF-dead window");
        vm.warp(uint256(sent) + 14 days);
        assertTrue(h.vrfDead(), "14 days unanswered");
        assertTrue(h.liveness(), "VRF dead ends the game");
    }

    function test_retryBitKeepsTheWindowAndTheDay() public {
        uint48 sent = uint48(block.timestamp - 2 days) & ~uint48(1);
        h.seed(5, 32, sent | 1, 3, 0, 0);
        assertFalse(h.liveness(), "a spent retry does not end the grace");
        vm.warp(uint256(sent) + 14 days - 1);
        assertFalse(h.liveness(), "the retry did not restart or extend the window");
        vm.warp(uint256(sent) + 14 days + 1); // the stamp carries the retry bit (+1s)
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
        assertFalse(h.liveness(), "behind (unattended days) past the deadline: waits");
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

    function test_middayRequestPromotesInLivePlayButDeadEndingStaysLatched() public {
        uint48 sent = uint48(block.timestamp - 15 days);
        h.seed(5, 10, sent, 15, 0, 0);
        h.seedMiddayRequest(sent);
        assertFalse(h.vrfDead(), "a live mid-day request can still be promoted on advance");
        h.startEnding();
        assertTrue(h.vrfDead(), "a terminal ending cannot promote it and times out");
        h.latchDeadMidday();
        assertTrue(h.vrfDead(), "dropping the request ID cannot reopen the game");
    }

    function test_middayRequestPastDeadmanUsesDeterministicEnding() public {
        uint48 sent = uint48(block.timestamp - 31 days);
        h.seed(5, 10, sent, 31, 0, 0);
        h.seedMiddayRequest(sent);
        assertTrue(h.vrfDead(), "deadman blocks the usual mid-day promotion");
        assertTrue(h.liveness(), "deterministic exit stays reachable");
    }
}

/// @dev Etch overlay to seed an exact dead-VRF terminal state; every measured call still runs
///      the production DegenerusGame runtime (restored after seeding).
contract DeadVrfSeeder is DegenerusGame, BucketSeed {
    function seedDeadStall(uint24 lvl) external {
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - 10;
        dailyIdx = day - 15;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = true;
        rngWordCurrent = 0;
        vrfRequestId = 777;
        rngRequestTime = uint48(block.timestamp - 15 days) & ~uint48(1);
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
    }

    function seedCreated(uint24 lvl, uint8 trait, address player, uint256 n) external {
        _seedBucket(lvl, trait, player, n);
    }

    function seedQueued(uint24 lvl, bool writeSide, address player, uint32 entries, uint8 rem)
        external
        returns (uint32 posPlusOne)
    {
        uint24 rk = writeSide ? _tqWriteKey(lvl) : _tqReadKey(lvl);
        _seedQueued(rk, lvl, player, (uint80(entries) << 8) | uint80(rem));
        posPlusOne = entryOwnerPosition[rk][player];
    }

    function seedFoil(uint24 lvl, uint24 resolveDay, address player) external returns (uint256 index) {
        EntryOwner[] storage owners = lvlEntryOwner[lvl];
        uint256 ownerIdx = owners.length;
        owners.push(EntryOwner(player, 0));
        foilBuyers[resolveDay].push(((ownerIdx + 1) << 192) | (uint256(lvl) << 160) | uint256(uint160(player)));
        index = foilBuyers[resolveDay].length - 1;
        if (resolveDay > foilLastResolveDay) foilLastResolveDay = resolveDay;
        if (foilDrainDay == 0 || foilDrainDay > resolveDay) foilDrainDay = resolveDay;
    }

    function deadState()
        external
        view
        returns (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits, uint256 left)
    {
        return (deadPot, deadTotal, deadCreated, deadUncreated, deadTraitCount, deadUncreatedLeft);
    }

    function sealedDay() external view returns (uint24) {
        return dailyIdx;
    }

    /// @dev Day `s` (30 days ago) is stuck in processing with its word delivered (and, if
    ///      `applied`, already recorded); nothing has sealed since, so the deadman has fired.
    function seedStuckDay(uint24 lvl, uint256 word, bool applied) external returns (uint24 s) {
        uint24 day = _simulatedDayIndex();
        s = day - 30;
        purchaseStartDay = s - 5;
        dailyIdx = s - 1;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = true;
        rngWordCurrent = word;
        vrfRequestId = 777;
        rngRequestTime = uint48(block.timestamp - 30 days) & ~uint48(1);
        rngWordByDay[s] = applied ? word : 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
        // The stuck request's reserved lootbox index, not yet worded.
        uint48 idx = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, idx + 1);
    }

    function vrfDeadView() external view returns (bool) {
        return _vrfDead();
    }

    /// @dev Past the purchase deadline at the start of a caught-up day with no word, VRF alive.
    ///      A mid-day request committed the read side and its lootbox word has landed.
    function seedDeadlineWithLandedCohort(uint24 lvl, uint256 boxWord) external {
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - 31;
        dailyIdx = day - 1;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = false;
        rngWordCurrent = 0;
        vrfRequestId = 0;
        rngRequestTime = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
        lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1] = boxWord;
    }

    function terminalQueues(uint24 lvl) external view returns (uint256 readLen, uint256 writeLen, uint256 swapped) {
        return (
            ticketQueue[_tqReadKey(lvl)].length,
            ticketQueue[_tqWriteKey(lvl)].length,
            _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK)
        );
    }

    /// @dev Entries (and remainder) still owed at registry position `posPlusOne`.
    function owedAt(uint24 lvl, uint32 posPlusOne) external view returns (uint256) {
        return (_entryRecord(lvl, posPlusOne) >> 160) & ((uint256(1) << 40) - 1);
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
        for (uint256 i; i < 20 && !game.gameOver(); ++i) game.advanceGame();
        assertTrue(game.gameOver(), "dead ending reached game over");
    }

    function _state() private returns (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits, uint256 left) {
        (pot, total, created, uncreated, traits, left) = _seeder().deadState();
        _restore();
    }

    function _ref(uint256 kind, uint256 hi, uint256 lo) private pure returns (uint256) {
        return (kind << 248) | (hi << 64) | lo;
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
        game.claimDeadVrf(alice, refs);
        assertEq(game.claimableWinningsOf(alice), 3 * (perTrait / 4), "alice: 3 of trait 3's four tickets");

        uint256[] memory one = new uint256[](1);
        one[0] = _ref(0, 3, 3);
        vm.expectRevert();
        game.claimDeadVrf(alice, one); // bob's ticket, not alice's
        game.claimDeadVrf(bob, one);
        assertEq(game.claimableWinningsOf(bob), perTrait / 4, "bob: 1 of trait 3's four tickets");
        vm.expectRevert();
        game.claimDeadVrf(bob, one); // already claimed

        uint256[] memory two = new uint256[](2);
        two[0] = _ref(0, 200, 0);
        two[1] = _ref(0, 200, 1);
        game.claimDeadVrf(carol, two);
        assertEq(game.claimableWinningsOf(carol), 2 * (perTrait / 2), "carol: a whole trait's share");

        one[0] = _ref(1, 0, davePos);
        game.claimDeadVrf(dave, one);
        assertEq(game.claimableWinningsOf(dave), (pot * 450) / total, "dave: the average for 4.5 entries");
        vm.expectRevert();
        game.claimDeadVrf(dave, one); // owed zeroed

        one[0] = _ref(1, 0, erinPos);
        game.claimDeadVrf(erin, one);
        assertEq(game.claimableWinningsOf(erin), (pot * 200) / total, "erin: the average for 2 entries");

        one[0] = _ref(2, foilDay, foilIdx);
        game.claimDeadVrf(frank, one);
        assertEq(game.claimableWinningsOf(frank), (pot * 1600) / total, "frank: the average for a foil pack");
        vm.expectRevert();
        game.claimDeadVrf(frank, one); // pack word zeroed

        uint256 paid = game.claimableWinningsOf(alice) + game.claimableWinningsOf(bob)
            + game.claimableWinningsOf(carol) + game.claimableWinningsOf(dave)
            + game.claimableWinningsOf(erin) + game.claimableWinningsOf(frank);
        assertLe(paid, pot, "never more than the pot");
        assertLt(pot - paid, 16, "only rounding dust left");
        (,,,,, uint256 left) = _state();
        assertEq(left, 0, "every uncreated unit claimed exactly once");
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
        game.advanceGame(); // final sweep
        uint256[] memory one = new uint256[](1);
        one[0] = _ref(1, 0, davePos);
        vm.expectRevert();
        game.claimDeadVrf(dave, one);
    }

    /// @dev The dead ending has no word to roll a pending gambling-burn pool with, so it calls
    ///      sDGNRS pendingResolveDay and then resolveRedemptionPeriod at 100, the expected roll.
    function test_pendingRedemptionResolvesAtExpectedValue() public {
        _seedHoldings();
        uint24 d = game.currentDayView() - 1;
        vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.pendingResolveDay.selector), abi.encode(d));
        vm.expectCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.resolveRedemptionPeriod.selector, uint16(100), d));
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
        for (uint256 i; i < 40 && !game.rngLocked(); ++i) game.advanceGame();
        uint24 r = game.currentDayView();
        uint256 req = mockVRF.lastRequestId();
        assertTrue(game.rngLocked(), "day R requested");

        vm.warp(block.timestamp + 14 days);
        assertTrue(game.livenessTriggered(), "VRF dead after 14 days with nothing delivered");
        mockVRF.fulfillRandomWords(req, 0xDEAD); // lands late, before anyone advanced
        assertFalse(game.livenessTriggered(), "a delivered word means VRF works");
        for (uint256 i; i < 10 && game.rngWordForDay(r) == 0; ++i) game.advanceGame();
        assertEq(game.rngWordForDay(r), 0xDEAD, "the stalled day finishes on its own word");
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
            game.advanceGame();
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
        uint256 derived = uint256(keccak256(abi.encodePacked(uint256(0xF00D), s)));
        if (applied) {
            assertEq(game.rngWordForDay(s), 0x57AC, "an applied stuck day keeps its word");
            assertEq(
                game.rngWordForDay(s + 1),
                uint256(keccak256(abi.encodePacked(uint256(0xF00D), s + 1))),
                "later days derive from the terminal word"
            );
        } else {
            assertEq(game.rngWordForDay(s), derived, "an unapplied stuck day derives from the terminal word");
        }
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

    /// @dev The deadline path runs before the normal new-day promotion of a stalled mid-day
    ///      request. If that mid-day request never answers, its day already has a daily word;
    ///      the terminal path must still declare it dead after 14 days and keep liveness latched.
    function test_unansweredMiddayRequestAtDeadlineEndsDeterministically() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(30); // target unmet on the deadline day
        _restore();

        for (uint256 i; i < 50 && !game.rngLocked(); ++i) game.advanceGame();
        uint256 dailyId = mockVRF.lastRequestId();
        assertTrue(game.rngLocked(), "deadline day's daily request");
        mockVRF.fulfillRandomWords(dailyId, 0xBEEF);
        for (uint256 i; i < 50 && game.rngLocked(); ++i) game.advanceGame();
        assertFalse(game.rngLocked(), "deadline day sealed");
        assertFalse(game.livenessTriggered(), "deadline day remains open");

        uint24 requestDay = game.currentDayView();
        assertTrue(game.rngWordForDay(requestDay) != 0, "mid-day request's day has its daily word");
        address buyer = makeAddr("midday-buyer");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        game.purchase{value: 1 ether}(
            buyer, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertFalse(game.livenessTriggered(), "small box buy did not meet the pool target");
        game.requestLootboxRng();
        assertGt(mockVRF.lastRequestId(), dailyId, "a real mid-day request is outstanding");
        uint256 sent = block.timestamp;

        vm.warp(sent + 1 days);
        assertTrue(game.livenessTriggered(), "unmet purchase deadline fires");
        game.advanceGame(); // terminal path latches and waits on the mid-day request
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

        for (uint256 i; i < 40 && !game.rngLocked(); ++i) game.advanceGame();
        assertTrue(game.rngLocked(), "deadline day requested; VRF stalls");

        vm.warp(block.timestamp + 13 hours);
        vm.prank(ContractAddresses.CREATOR);
        game.advanceGame(); // the vault owner's single retry
        vm.warp(block.timestamp + 1 days);
        assertFalse(game.livenessTriggered(), "past the deadline, behind, inside the window");

        address buyer = makeAddr("stall-buyer");
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchase{value: 2 ether}(buyer, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);

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
                game.advanceGame();
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
        for (uint256 i; i < 200; ++i) {
            if (game.gameOver()) return;
            _answer(vrf); // a request already in flight must land before the advance can use it
            game.advanceGame();
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
        vm.prank(ContractAddresses.CRAPS);
        game.requestLootboxRng(); // lootbox-only: nothing queued to swap

        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertFalse(game.gameOver(), "the ending waits on the request in flight");

        MockVRFCoordinator fresh = _freshCoordinator();
        assertEq(fresh.lastRequestId(), 1, "the swap re-issued the mid-day request");

        vm.recordLogs();
        _runDay(fresh);
        assertTrue(game.gameOver(), "ended");
        assertFalse(_sawPayoutFixed(vm.getRecordedLogs()), "on the normal VRF payout");
    }

    /// @dev The deadline day seals and nobody advances the next day. The day after catches up:
    ///      its gap credit moves the deadline behind it while it is being processed. It must
    ///      still finish on its own word (the trigger stays off for a worded day), and the ending
    ///      must start the next day on a terminal word requested after the freeze.
    function test_catchUpPastTheDeadlineFinishesItsDayThenEndsOnAFreshWord() public {
        vm.etch(address(game), type(DeadlineSeeder).runtimeCode);
        DeadlineSeeder(payable(address(game))).seed(30);
        _restore();
        _runDay(mockVRF);
        uint24 dl = game.currentDayView();

        vm.warp(block.timestamp + 2 days); // dl + 1 unattended
        assertFalse(game.livenessTriggered(), "behind: the deadline waits");
        game.advanceGame(); // day dl + 2 requests
        assertTrue(game.rngLocked(), "requested");
        _answer(mockVRF);
        game.advanceGame(); // applies the word, backfills dl + 1, credits the deadline
        assertTrue(game.rngWordForDay(dl + 2) != 0, "day dl + 2 worded");
        assertEq(_sealedDay(), dl + 1, "caught up");
        assertFalse(game.livenessTriggered(), "a worded day finishes on its own word");

        _runDay(mockVRF);
        assertFalse(game.gameOver(), "day dl + 2 completed normally");
        assertEq(_sealedDay(), dl + 2, "and sealed");

        vm.warp(block.timestamp + 1 days);
        assertTrue(game.livenessTriggered(), "the next day starts the ending");
        uint256 before = mockVRF.lastRequestId();
        vm.recordLogs();
        _runDay(mockVRF);
        assertTrue(game.gameOver(), "ended");
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
        for (uint256 i; i < 40 && !game.rngLocked(); ++i) game.advanceGame();
        assertTrue(game.rngLocked(), "daily request stalls");

        vm.warp(block.timestamp + 13 hours);
        MockVRFCoordinator fresh = _freshCoordinator();
        assertEq(fresh.lastRequestId(), 1, "the swap re-sent the daily request");

        vm.prank(ContractAddresses.CREATOR);
        try game.advanceGame() {} catch {} // waiting on the word: may revert RngNotReady
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
        DeadVrfSeeder s = _seeder();
        s.seedDeadlineWithLandedCohort(LVL, 0xB0B5);
        for (uint160 i = 1; i <= 24; ++i) s.seedQueued(TLVL, false, address(0xD00D0000 + i), 60, 0);
        uint32 erinAt = s.seedQueued(TLVL, true, erin, 2, 0);
        _restore();
        assertTrue(game.livenessTriggered(), "deadline passed, caught up, VRF alive");
        uint256 req0 = mockVRF.lastRequestId();
        uint256 snap = vm.snapshotState();

        // Full-gas reference: one batch's cost, then the cost of the whole call that swaps and
        // sends the terminal request (an upper bound on what a fall-through needs).
        uint256 g0 = gasleft();
        game.advanceGame();
        uint256 batchGas = g0 - gasleft();
        (uint256 readLen,, uint256 swapped) = _terminalQueues();
        assertEq(swapped, 0, "a batch call leaves the swap window open");
        assertGt(readLen, 0, "one batch does not drain the read side");
        uint256 requestGas;
        for (uint256 i; i < 50 && mockVRF.lastRequestId() == req0; ++i) {
            g0 = gasleft();
            game.advanceGame();
            requestGas = g0 - gasleft();
        }
        assertGt(mockVRF.lastRequestId(), req0, "the terminal request went out");
        vm.revertToState(snap);

        // A survivor ran the batch and must leave the window open with no request. A revert whose
        // limit's 1/64 reserve (with margin) covers the whole swap-and-request call is the
        // non-vacuity witness: the module kept enough gas after the batch failed to have sent
        // the terminal request, had it swallowed the failure.
        uint256 witnessGas;
        uint256 leakGas;
        uint256 step = batchGas / 128;
        for (uint256 g = batchGas; g > step * 8; g -= step) {
            snap = vm.snapshotState();
            try game.advanceGame{gas: g}() {
                (,, swapped) = _terminalQueues();
                if (leakGas == 0 && (swapped != 0 || mockVRF.lastRequestId() != req0)) leakGas = g;
            } catch (bytes memory err) {
                if (g / 66 > requestGas) {
                    assertEq(bytes4(err), DegenerusGameStorage.EmptyRevert.selector, "no error of its own");
                    witnessGas = g;
                }
            }
            vm.revertToState(snap);
        }
        emit log_named_uint("batchGas", batchGas);
        emit log_named_uint("requestGas", requestGas);
        emit log_named_uint("witnessGas", witnessGas);
        emit log_named_uint("leakGas", leakGas);
        assertGt(witnessGas, 0, "a starved batch left enough gas to send the terminal request");

        // End to end: a starved call first (the leak if one exists, else the witness), then full
        // gas. The read side drains, the write cohort swaps in and draws on the terminal word.
        try game.advanceGame{gas: leakGas != 0 ? leakGas : witnessGas}() {} catch {}
        for (uint256 i; i < 80 && !game.gameOver(); ++i) {
            game.advanceGame();
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
