// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {Vm} from "forge-std/Vm.sol";

contract TerminalAffiliateSeeder is DegenerusGame, BucketSeed {
    function seed(uint24 lvl, uint8 phase, uint256 word, address creditor, uint128 reserved) external {
        uint24 day = _simulatedDayIndex();
        level = lvl;
        purchaseStartDay = day - 366;
        dailyIdx = day - 121;
        jackpotPhaseFlag = phase == 1;
        lastPurchaseDay = phase >= 2;
        rngLockedFlag = phase == 3;
        rngWordByDay[day] = word;
        ticketsFullyProcessed = true;
        levelPrizePool[lvl] = 1000 ether;
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        _creditClaimable(creditor, reserved);
        claimablePool = reserved;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        uint24 terminalLevel = _gameOverTicketLevel(lvl);
        for (uint8 q; q < 4; ++q) _seedBucket(terminalLevel, traits[q], address(0x715E7), 1000);
    }

    function clearDayWord() external {
        rngWordByDay[_simulatedDayIndex()] = 0;
    }

    /// @dev The locked daily request, sent today, has its word delivered but not yet applied.
    function deliverPreFreezeWord(uint256 word) external {
        rngWordByDay[_simulatedDayIndex()] = 0;
        rngRequestTime = uint48(block.timestamp) & ~uint48(1);
        vrfRequestId = 777;
        rngWordCurrent = word;
    }

    function paidPass(address owner, uint96 paid) external {
        deityPassOwners.push(owner);
        deityPassPricePaid[owner] = paid;
    }

    function accruedAffiliate(address sub, uint32 amount) external {
        _subOf[sub].affiliateBase = amount;
    }
}

contract RejectingTerminalAffiliate {
    fallback() external payable { revert("no recipient callbacks"); }
}

contract TerminalAffiliatePayoutTest is DeployProtocol {
    uint256 private constant WORD = 0x987654321;
    uint256 private constant PRE_FREEZE_WORD = 0x1234567;
    address private constant TOP = address(0xAFF1);
    address private constant LATE = address(0xAFF2);
    address private constant CREDITOR = address(0xC4ED17);
    bytes32 private constant PAID = keccak256("TerminalAffiliatePaid(address,uint24,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
    }

    function _fixture(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TerminalAffiliateSeeder).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), original);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }

    function _seed(uint24 lvl, uint8 phase, uint128 funds, uint128 reserved) private {
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.seed, (lvl, phase, WORD, CREDITOR, reserved)));
        vm.deal(address(game), funds);
    }

    function _rank(address who, uint24 lvl, uint256 amount, address sub) private {
        bytes32 code = bytes32(uint256(uint160(who)));
        // Address-derived referral codes already resolve to their address owner.
        vm.prank(address(game));
        affiliate.payAffiliate(amount, code, sub, lvl, true, 0);
    }

    /// @dev Sends the ending's own terminal request. With no pre-freeze request to drop, this is
    ///      the ending's first transaction, which also latches the cohort level and the affiliate.
    function _latchAndRequest() private returns (uint256 requestId) {
        uint256 before = mockVRF.lastRequestId();
        game.advanceGame();
        assertTrue(game.rngLocked(), "terminal word requested");
        requestId = mockVRF.lastRequestId();
        assertGt(requestId, before, "the ending's own terminal request");
    }

    /// @dev Answers the terminal request; the word is applied in a transaction of its own, which
    ///      pays nothing, so the payout always runs on a later advance.
    function _applyTerminalWord(uint256 requestId) private {
        mockVRF.fulfillRandomWords(requestId, WORD);
        vm.recordLogs();
        game.advanceGame();
        assertFalse(game.gameOver(), "applying the word does not pay out");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) assertTrue(logs[i].topics[0] != PAID, "no award with the word");
    }

    /// @dev Phase 3 freezes with the last-purchase request in flight. The ending's first
    ///      transaction latches the cohort level the lock promoted, spends that request's word
    ///      on its own lootbox index only and drops it; the terminal word is then the ending's
    ///      own request.
    function _dropPreFreezeRequest() private {
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.deliverPreFreezeWord, (PRE_FREEZE_WORD)));
        bytes32 applied = keccak256("LootboxRngApplied(uint48,uint256,uint256)");
        vm.recordLogs();
        game.advanceGame();
        assertFalse(game.rngLocked(), "pre-freeze request dropped");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool finalized;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != applied) continue;
            (, uint256 word,) = abi.decode(logs[i].data, (uint48, uint256, uint256));
            assertEq(word, PRE_FREEZE_WORD);
            finalized = true;
        }
        assertTrue(finalized, "pre-freeze word finalizes its lootbox index");
        _applyTerminalWord(_latchAndRequest());
    }

    function _assertSettlement(uint24 terminalLevel, uint256 jackpot, address winner, uint256 share) private {
        vm.expectCall(address(game), abi.encodeWithSelector(game.runTerminalJackpot.selector, jackpot, terminalLevel, WORD));
        uint256 previous = game.claimableWinningsOf(winner);
        uint256 previousLiability = uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
        vm.recordLogs();
        game.advanceGame();
        assertTrue(game.gameOver(), "real terminal advance completes");
        assertEq(game.claimableWinningsOf(winner), previous + share);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 awards;
        uint256 credited;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("PlayerCredited(address,uint256)")) {
                credited += abi.decode(logs[i].data, (uint256));
            }
            if (logs[i].topics[0] != PAID) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), winner);
            assertEq(uint256(logs[i].topics[2]), terminalLevel);
            assertEq(abi.decode(logs[i].data, (uint256)), share);
            ++awards;
        }
        assertEq(awards, share == 0 ? 0 : 1);
        uint256 liability = uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
        assertEq(liability, previousLiability + credited, "every credit reserved exactly once");
    }

    function testFuzzSplitUsesTerminalCohortLevelInEveryPhase(uint8 phase, uint96 funds) public {
        phase = uint8(bound(phase, 0, 3));
        funds = uint96(bound(funds, 100, 10_000 ether));
        uint24 terminalLevel = phase == 1 || phase == 3 ? 10 : 11;
        _seed(10, phase, funds, 0);
        _rank(TOP, terminalLevel, 1000 ether, address(0xB001));
        // A larger score at the adjacent, wrong level must not steal the terminal reward.
        _rank(LATE, terminalLevel == 10 ? 11 : 10, 10_000 ether, address(0xB002));
        if (phase == 3) _dropPreFreezeRequest();
        uint256 share = uint256(funds) / 50;
        _assertSettlement(terminalLevel, funds - share, TOP, share);
        assertEq(game.claimableWinningsOf(LATE), 0);
        uint256 reserved = uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
        assertLe(reserved, funds, "all payouts remain backed");
    }

    function testRefundsAndExistingClaimsAreReservedBeforeSplit() public {
        _seed(9, 0, 100 ether, 30 ether);
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.paidPass, (address(0xDE17), 24 ether)));
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.paidPass, (address(0xDE18), 10 ether)));
        _rank(TOP, 10, 1000 ether, address(0xB001));
        _assertSettlement(10, 39.2 ether, TOP, 0.8 ether);
        assertEq(game.claimableWinningsOf(CREDITOR), 30 ether);
        assertEq(game.claimableWinningsOf(address(0xDE17)), 20 ether);
        assertEq(game.claimableWinningsOf(address(0xDE18)), 10 ether);
    }

    function testNoAffiliateGivesEntireAvailablePoolToJackpot() public {
        _seed(10, 0, 100 ether, 30 ether);
        _assertSettlement(11, 70 ether, TOP, 0);
    }

    function testRoundingDustStaysInJackpot() public {
        _seed(10, 0, 101, 0);
        _rank(TOP, 11, 1000 ether, address(0xB001));
        _assertSettlement(11, 99, TOP, 2);
    }

    function testPoolBelowFiftyWeiPaysNoAffiliateShare() public {
        _seed(10, 0, 49, 0);
        _rank(TOP, 11, 1000 ether, address(0xB001));
        _assertSettlement(11, 49, TOP, 0);
    }

    function testNoDistributableFundsPreservesExistingLiability() public {
        _seed(10, 0, 100 ether, 100 ether);
        _rank(TOP, 11, 1000 ether, address(0xB001));
        game.advanceGame();
        assertTrue(game.gameOver());
        assertEq(game.claimableWinningsOf(TOP), 0);
        assertEq(game.claimableWinningsOf(CREDITOR), 100 ether);
    }

    function testTieKeepsTheExistingLeader() public {
        _seed(10, 0, 100 ether, 0);
        _rank(TOP, 11, 1000 ether, address(0xB001));
        _rank(LATE, 11, 1000 ether, address(0xB002));
        _assertSettlement(11, 98 ether, TOP, 2 ether);
    }

    function testAccruedAffiliateClaimBeforeSettlementCanWin() public {
        _seed(10, 0, 100 ether, 0);
        _rank(TOP, 11, 1000 ether, address(0xB001));
        _rank(LATE, 11, 0, address(0xB002));
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.accruedAffiliate, (address(0xB002), uint32(1000))));
        address[] memory subs = new address[](1);
        subs[0] = address(0xB002);
        affiliate.claim(subs);
        _assertSettlement(11, 98 ether, LATE, 2 ether);
    }

    function testLateAffiliateClaimAndAdvanceRetryCannotChangePayout() public {
        _seed(10, 0, 100 ether, 0);
        _rank(TOP, 11, 1000 ether, address(0xB001));
        _rank(LATE, 11, 0, address(0xB002));
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.accruedAffiliate, (address(0xB002), uint32(1000))));
        _assertSettlement(11, 98 ether, TOP, 2 ether);
        address[] memory subs = new address[](1);
        subs[0] = address(0xB002);
        affiliate.claim(subs);
        (address top,) = affiliate.affiliateTop(11);
        assertEq(top, LATE, "post-death score really changed the leader");
        vm.recordLogs();
        game.advanceGame();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) assertTrue(logs[i].topics[0] != PAID);
        assertEq(game.claimableWinningsOf(TOP), 2 ether);
        assertEq(game.claimableWinningsOf(LATE), 0);
    }

    /// @dev Real terminal path: the cohort latch and the ending's own request come first, the
    ///      word is applied in its own transaction, and only then does the payout run. A
    ///      first-ever ranking at the terminal level placed after the latch, before or after the
    ///      word, must not reach the payout or shrink the draw's pool.
    function testRankingAfterTheTerminalLatchCannotReachTheDraw() public {
        _seed(10, 0, 100 ether, 0);
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.clearDayWord, ()));
        uint256 requestId = _latchAndRequest();
        _rank(LATE, 11, 1000 ether, address(0xB002)); // leaderboard 0 -> ranked, after the latch
        _applyTerminalWord(requestId);
        _rank(address(0xAFF3), 11, 10_000 ether, address(0xB003)); // word public, payout pending
        vm.expectCall(address(game), abi.encodeWithSelector(game.runTerminalJackpot.selector, 100 ether, uint24(11), WORD));
        vm.recordLogs();
        game.advanceGame();
        assertTrue(game.gameOver(), "terminal payout ran");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) assertTrue(logs[i].topics[0] != PAID, "no affiliate award");
        assertEq(game.claimableWinningsOf(LATE), 0, "late ranking not paid");
        assertEq(game.claimableWinningsOf(address(0xAFF3)), 0, "ranking after the word not paid");
    }

    function testRankingBeforeTheTerminalLatchIsPaidAfterTheWord() public {
        _seed(10, 0, 100 ether, 0);
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.clearDayWord, ()));
        _rank(TOP, 11, 1000 ether, address(0xB001));
        _applyTerminalWord(_latchAndRequest());
        _assertSettlement(11, 98 ether, TOP, 2 ether);
    }

    function testOvertakenBetweenLatchAndWordKeepsTheLatchedLeader() public {
        _seed(10, 0, 100 ether, 0);
        _fixture(abi.encodeCall(TerminalAffiliateSeeder.clearDayWord, ()));
        _rank(TOP, 11, 1000 ether, address(0xB001));
        uint256 requestId = _latchAndRequest();
        assertEq(address(uint160(uint256(vm.load(address(game), bytes32(uint256(69)))))), TOP, "slot 69 holds the latched leader");
        _rank(LATE, 11, 10_000 ether, address(0xB002)); // overtakes on the live leaderboard, after the latch
        (address liveTop,) = affiliate.affiliateTop(11);
        assertEq(liveTop, LATE, "live leaderboard moved");
        _applyTerminalWord(requestId);
        _assertSettlement(11, 98 ether, TOP, 2 ether);
        assertEq(game.claimableWinningsOf(LATE), 0, "overtaker not paid");
    }

    function testRejectingAffiliateCannotBlockTerminalSettlement() public {
        _seed(10, 0, 100 ether, 0);
        address winner = address(new RejectingTerminalAffiliate());
        _rank(winner, 11, 1000 ether, address(0xB001));
        _assertSettlement(11, 98 ether, winner, 2 ether);
    }
}
