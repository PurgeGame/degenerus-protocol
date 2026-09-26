// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {IDegenerusGameBoonModule, IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {stdError} from "forge-std/StdError.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";

contract RejectingBoonRecipient {
    fallback() external { revert("recipient callback forbidden"); }
}

contract ProtocolBoonFixture is DegenerusGameStorage {
    function word(uint24 day, uint256 value) external { rngWordByDay[day] = value; }
    function genesisDay(uint24 day) external { dailyIdx = day; purchaseStartDay = day; }
    function resolve(address module, uint24 awardDay) external {
        (bool ok, bytes memory data) = module.delegatecall(
            abi.encodeCall(IDegenerusGameBoonModule.resolveProtocolBoonDraws, (awardDay))
        );
        if (!ok) assembly { revert(add(data, 32), mload(data)) }
    }
    function generatedSpins(address module, address player, uint8 symbol) external {
        (bool ok, bytes memory data) = module.delegatecall(abi.encodeCall(
            IDegenerusGameDegeneretteModule.resolveEthSpinFromBox, (player, 0.01 ether, 0, 12345, symbol)
        ));
        if (!ok) assembly { revert(add(data, 32), mload(data)) }
        (ok, data) = module.delegatecall(abi.encodeCall(
            IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox, (player, 300 ether, 0, 12345, symbol)
        ));
        if (!ok) assembly { revert(add(data, 32), mload(data)) }
    }
    function endGame() external { gameOver = true; }
    function requireLivenessTriggered() external view { require(_livenessTriggered(), "not past death deadline"); }
    function maxEntries(address issuer, uint24 day) external {
        protocolBoonPools[issuer][day & 1].day = day;
        protocolBoonPools[issuer][day & 1].entryCount = type(uint32).max;
    }
    function fullWeight(address issuer, uint24 day) external {
        protocolBoonPools[issuer][day & 1].day = day;
        protocolBoonPools[issuer][day & 1].totalWeight = type(uint64).max;
    }
    function bet(uint48 index, uint64 id) external view returns (uint256) { return degeneretteQueue[index][id - 1]; }
    function heroWeight(uint24 day, uint8 symbol) external view returns (uint32) {
        return uint32(dailyHeroWagers[day][symbol >> 3] >> ((symbol & 7) * 32));
    }
    function openIndex() external { _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1); }
    function clearDeity(uint8 symbol) external { deityBySymbol[symbol] = address(0); }
    function seedBoon(address player, uint24 day) external {
        boonPacked[player].slot1 = (uint256(3) | (uint256(day) << BP_LANE_DAY_SHIFT)) << BP_DEGEN_LANE0_SHIFT;
    }
    function claimable(address player, uint256 amount) external {
        _creditClaimable(player, amount + 1);
        claimablePool += uint128(amount + 1);
    }
    function staleMintStreak(address player) external {
        level = 10;
        jackpotPhaseFlag = true;
        mintPacked_[player] = (uint256(9) << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT)
            | (uint256(40) << BitPackingLib.LEVEL_STREAK_SHIFT);
    }
    function occupyEveryLane(address player, uint24 stamp) external {
        uint256 tier = 3;
        uint256 d = stamp;
        boonPacked[player].slot0 = (d << BP_COINFLIP_DAY_SHIFT) | (tier << BP_COINFLIP_TIER_SHIFT)
            | (d << BP_LOOTBOX_DAY_SHIFT) | (tier << BP_LOOTBOX_TIER_SHIFT)
            | (d << BP_PURCHASE_DAY_SHIFT) | (tier << BP_PURCHASE_TIER_SHIFT)
            | (tier << BP_DECIMATOR_TIER_SHIFT)
            | (d << BP_WHALE_DAY_SHIFT) | (tier << BP_WHALE_TIER_SHIFT);
        uint256 lane = tier | (d << BP_LANE_DAY_SHIFT);
        boonPacked[player].slot1 = lane | (d << BP_DEITY_PASS_DAY_SHIFT) | (tier << BP_DEITY_PASS_TIER_SHIFT)
            | (d << BP_LAZY_PASS_DAY_SHIFT) | (tier << BP_LAZY_PASS_TIER_SHIFT)
            | (lane << BP_DEGEN_LANE0_SHIFT) | (lane << (BP_DEGEN_LANE0_SHIFT + 24))
            | (lane << (BP_DEGEN_LANE0_SHIFT + 48));
        whalePassClaims[player] = 1_000; // occupied; the counter is a plain uint256 increment
    }
    function boonWords(address player) external view returns (uint256, uint256) {
        return (boonPacked[player].slot0, boonPacked[player].slot1);
    }
    function multiplier(uint256 score) external pure returns (uint256) {
        return ActivityCurveLib.boonDrawMultUnits(score);
    }
}

contract ProtocolBoonDrawTest is DeployProtocol {
    DegenerusGameLens private lens;
    ProtocolBoonFixture private fixture;
    address private bettor;
    uint24 private day;

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        fixture = new ProtocolBoonFixture();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        day = game.currentDayView();
        bettor = makeAddr("bettor");
        vm.deal(bettor, 1_000_000 ether);
        vm.deal(address(this), 1_000_000 ether);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.openIndex, ()));
        _score(bettor, 0);
    }
    function _bet(uint8 symbol, uint128 amount) private {
        game.placeDegeneretteBet{value: amount}(address(0), 0, amount, 1, symbol);
    }
    function _fixtureCall(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), original);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }
    function _resolve() private {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.resolve, (address(boonModule), day + 1)));
    }
    function _score(address who, uint256 score) private {
        vm.mockCall(address(quests), abi.encodeWithSelector(quests.effectiveBaseStreakAndAfking.selector, who), abi.encode(uint32(score * 2), false));
    }
    function _ready() private {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, uint256(12345))));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 1, uint256(987654321))));
    }
    function _finishDailyAdvance(uint256 seed) private {
        uint256 fulfilled = mockVRF.lastRequestId();
        for (uint256 i; i < 150; ++i) {
            game.advanceGame();
            uint256 request = mockVRF.lastRequestId();
            if (request > fulfilled) {
                mockVRF.fulfillRandomWords(request, seed);
                fulfilled = request;
            }
            if (!game.rngLocked() && game.rngWordForDay(game.currentDayView()) != 0) return;
        }
        fail("daily advance must finish after the boon stage");
    }
    function _assertBettorAwards(Vm.Log[] memory logs, uint256 expected) private view {
        uint256 issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)")) continue;
            assertEq(logs[i].emitter, address(game));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), bettor);
            assertEq(uint256(logs[i].topics[3]), day);
            ++issued;
        }
        assertEq(issued, expected);
    }
    function testPaidEthWeightTruncatedAndEachIssuerIsolated() public {
        _score(bettor, 400);
        uint256 vaultStake = coinflip.coinflipAmount(address(vault));
        uint256 sdgnrsStake = coinflip.coinflipAmount(address(sdgnrs));
        uint256 future = game.futurePrizePoolView();
        vm.prank(bettor); _bet(0, 0.00995 ether + 17 gwei);
        vm.prank(bettor); _bet(6, 0.025 ether);
        assertEq(game.futurePrizePoolView(), future + 0.03495 ether + 17 gwei);
        assertEq(coinflip.coinflipAmount(address(vault)), vaultStake);
        assertEq(coinflip.coinflipAmount(address(sdgnrs)), sdgnrsStake);
        DegenerusGameStorage.ProtocolBoonPool memory pool = lens.protocolBoonPool(address(game), address(vault), day);
        assertEq(pool.totalWageredWei, 0.00995 ether + 17 gwei);
        assertEq(pool.totalWeight, 99 * 1600);
        assertEq(pool.entryCount, 1);
        assertEq(pool.awardedMask, 0);
        DegenerusGameStorage.ProtocolBoonEntry memory e = lens.protocolBoonEntryAt(address(game), address(vault), day, 0);
        assertEq(e.player, bettor); assertEq(e.cumulativeWeight, 99 * 1600); assertEq(e.scoreSnapshot, 400);
        e = lens.protocolBoonEntryAt(address(game), address(sdgnrs), day, 0);
        assertEq(e.cumulativeWeight, 250 * 1600);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).totalWageredWei, 0.025 ether);
    }

    function testScoresAreSnapshottedAndCapAtThreeTimes() public {
        uint256[6] memory scores = [uint256(0), 1, 400, 401, 1200, 5000];
        uint256[6] memory mult = [uint256(800), 802, 1600, 1601, 2400, 2400];
        uint256 sum;
        for (uint32 i; i < scores.length; ++i) {
            _score(bettor, scores[i]);
            (uint256 units, uint16 score, uint16 multiplier, uint64 weight) = lens.protocolBoonQuote(address(game), bettor, 0.005 ether);
            assertEq(units, 50); assertEq(score, scores[i]); assertEq(multiplier, mult[i]); assertEq(weight, 50 * mult[i]);
            vm.prank(bettor); _bet(0, 0.005 ether);
            sum += 50 * mult[i];
            DegenerusGameStorage.ProtocolBoonEntry memory entry = lens.protocolBoonEntryAt(address(game), address(vault), day, i);
            assertEq(entry.cumulativeWeight, sum); assertEq(entry.scoreSnapshot, scores[i]);
        }
        _score(bettor, 0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, sum);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 4).scoreSnapshot, 1200);
    }

    function testBoonEntryAddsOnePackedHeaderAndOnePackedEntryWrite() public {
        for (uint256 i; i < 2; ++i) {
            vm.record();
            vm.prank(bettor); _bet(0, 0.005 ether);
            (, bytes32[] memory writes) = vm.accesses(address(game));
            bytes32 poolSlot = keccak256(abi.encode(uint256(day & 1), keccak256(abi.encode(address(vault), uint256(48)))));
            bytes32 entryRoot = keccak256(abi.encode(uint256(day & 1), keccak256(abi.encode(address(vault), uint256(49)))));
            bytes32 entrySlot = keccak256(abi.encode(i, entryRoot));
            uint256 headerWrites;
            uint256 entryWrites;
            for (uint256 j; j < writes.length; ++j) {
                if (writes[j] == poolSlot) ++headerWrites;
                if (writes[j] == entrySlot) ++entryWrites;
            }
            assertEq(headerWrites, 1); assertEq(entryWrites, 1);
        }
    }

    function testFuzzMultiplierMonotoneAndBounded(uint16 score) public view {
        uint256 m = fixture.multiplier(score);
        assertGe(m, 800); assertLe(m, 2400);
        assertGe(fixture.multiplier(uint256(score) + 1), m);
        if (score >= 1200) assertEq(m, 2400);
    }
    function testSingleBettorWinsAllSixWithoutDailyOrLifetimeCaps() public {
        // More than the ordinary recipient lifetime cap, all six slots on each day.
        for (uint256 round; round < 12; ++round) {
            vm.prank(bettor); _bet(0, 0.005 ether);
            vm.prank(bettor); _bet(6, 0.005 ether);
            _ready();
            _resolve();
            _resolve(); // same-day retry cannot issue twice
            assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
            assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
            (,, uint8 used,,) = game.deityBoonData(address(vault));
            assertEq(used, 7);
            ++day;
        }
    }
    function testAutomaticWinningIntervalsMatchIndependentLinearModel() public {
        for (uint160 i; i < 25; ++i) {
            address who = address(5000 + i);
            vm.deal(who, 1 ether);
            _score(who, i * 60);
            vm.prank(who); _bet(0, uint128((i + 1) * 0.005 ether));
        }
        _ready();
        (bool ready, address[3] memory winners, uint32[3] memory indices, uint64[3] memory rolls) =
            lens.findProtocolBoonWinners(address(game), address(vault), day);
        assertTrue(ready);
        uint256 total = lens.protocolBoonPool(address(game), address(vault), day).totalWeight;
        for (uint8 slot; slot < 3; ++slot) {
            uint256 expectedRoll = uint256(keccak256(abi.encode(
                keccak256("degenerus.protocol.boon.winner"), address(vault), day, slot, uint256(987654321)
            ))) % total;
            assertEq(rolls[slot], expectedRoll);
            uint256 cumulative;
            for (uint32 i; i < 25; ++i) {
                cumulative += 50 * (i + 1) * fixture.multiplier(uint256(i) * 60);
                if (expectedRoll < cumulative) { assertEq(indices[slot], i); assertEq(winners[slot], address(uint160(5000 + i))); break; }
            }

        }
        vm.recordLogs();
        _resolve();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 issued;
        bytes32 sig = keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (uint8 slot, uint32 index,) = abi.decode(logs[i].data, (uint8, uint32, uint8));
            assertEq(index, indices[slot]);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), winners[slot]);
            ++issued;
        }
        assertEq(issued, 3);
    }
    function testInvalidOrUnfundedBetsCannotCreateEntries() public {
        vm.expectRevert(); vm.prank(bettor); _bet(0, 0.005 ether - 1);
        vm.expectRevert(); vm.prank(bettor); game.placeDegeneretteBet(address(0), 0, 0.005 ether, 1, 0);
        vm.expectRevert(); vm.prank(bettor); game.placeDegeneretteBet{value: 0.005 ether}(address(0), 0, 0.005 ether, 0, 0);
        vm.expectRevert(); boonModule.resolveProtocolBoonDraws(day + 1);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 0).player, address(0));
    }

    function testLaunchDayEthBetsReceiveAllSixBoonsThroughRealAdvance() public {
        vm.warp(86_400); // DeployProtocol's day-1 timestamp.
        day = game.currentDayView();
        assertEq(day, 1);
        assertEq(game.rngWordForDay(1), 0);
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(6, 0.005 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        _finishDailyAdvance(987654321);
        _assertBettorAwards(vm.getRecordedLogs(), 6);
        assertEq(game.rngWordForDay(day), 0, "launch day still has no RNG word");
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
        (bool ready, address[3] memory winners,,) = lens.findProtocolBoonWinners(address(game), address(vault), day);
        assertTrue(ready, "winner view supports launch-day pools");
        for (uint256 i; i < 3; ++i) assertEq(winners[i], bettor);
        vm.recordLogs();
        _resolve();
        _assertBettorAwards(vm.getRecordedLogs(), 0);
    }
    function testGenesisBetsWorkWhenDeploymentCrossesAReset() public {
        // A delayed deployment may initialize dailyIdx after relative day 1.
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.genesisDay, (day)));
        assertEq(game.rngWordForDay(day), 0);
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(6, 0.005 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        _finishDailyAdvance(987654321);
        _assertBettorAwards(vm.getRecordedLogs(), 6);
        assertEq(game.rngWordForDay(day), 0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
    }
    function testEthEntriesStayOpenBeforeAndAfterDailyVrfFulfillmentWhileLocked() public {
        for (uint256 i; i < 150 && !game.rngLocked(); ++i) game.advanceGame();
        assertTrue(game.rngLocked());
        assertEq(game.rngWordForDay(day), 0);
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(6, 0.005 ether);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 12345);
        assertTrue(game.rngLocked());
        vm.prank(bettor); _bet(0, 0.01 ether);
        vm.prank(bettor); _bet(6, 0.01 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 2);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 2);
        _finishDailyAdvance(12345);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        _finishDailyAdvance(987654321);
        _assertBettorAwards(vm.getRecordedLogs(), 6);
    }
    function testManualProtocolBoonsBlockedIncludingApprovedOperator() public {
        _ready();
        vm.prank(address(vault)); game.setOperatorApproval(address(this), true);
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        game.issueDeityBoon(address(vault), bettor, 0);
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        vm.prank(address(vault));
        game.issueDeityBoon(address(0), bettor, 0);
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        vm.prank(address(sdgnrs));
        game.issueDeityBoon(address(0), bettor, 0);
        vm.expectRevert(DegenerusGameStorage.OnlyDelegatecall.selector);
        boonModule.issueDeityBoon(address(vault), bettor, 0);
    }
    function testRecipientContractCannotRejectAutomaticDelivery() public {
        RejectingBoonRecipient receiver = new RejectingBoonRecipient();
        game.placeDegeneretteBet{value: 0.005 ether}(address(receiver), 0, 0.005 ether, 1, 0);
        game.placeDegeneretteBet{value: 0.005 ether}(address(receiver), 0, 0.005 ether, 1, 6);
        _ready();
        vm.recordLogs();
        _resolve();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)")) continue;
            assertEq(address(uint160(uint256(logs[i].topics[2]))), address(receiver));
            ++issued;
        }
        assertEq(issued, 6);
    }

    function testWeightOverflowCannotTruncateOrPartiallyFundEntry() public {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.fullWeight, (address(vault), day)));
        uint256 future = game.futurePrizePoolView();
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(bettor); _bet(0, 0.005 ether);
        assertEq(game.futurePrizePoolView(), future);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, type(uint64).max);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
        vm.expectRevert(); lens.protocolBoonQuote(address(game), bettor, type(uint256).max);
    }

    function testAutomaticDrawWaitsForWordAndNeverIssuesLate() public {
        vm.prank(bettor); _bet(0, 0.005 ether);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 1, uint256(123))));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, uint256(456))));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
    }
    function testMissingPredecessorUsesAwardWordForMenuAndDoesNotReplay() public {
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 1, uint256(123))));
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        _resolve();
        Vm.Log[] memory fallbackLogs = vm.getRecordedLogs();
        _assertBettorAwards(fallbackLogs, 3);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        vm.recordLogs();
        _resolve();
        _assertBettorAwards(vm.getRecordedLogs(), 0);
        assertTrue(vm.revertToState(snapshot));
        // The fallback must produce the same menu as a normal draw with this seed.
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, uint256(123))));
        vm.recordLogs();
        _resolve();
        assertEq(keccak256(abi.encode(vm.getRecordedLogs())), keccak256(abi.encode(fallbackLogs)));
    }
    function testNextDayBetCannotChangeTheClosedPool() public {
        _score(bettor, 400);
        vm.prank(bettor); _bet(0, 0.005 ether);
        _ready();
        vm.prank(bettor); _bet(0, 1.25 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, 80_000);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day + 1).totalWeight, 20_000_000);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day + 1).awardedMask, 0);
    }
    function testFuzzAllSixCollisionsKeepStrongerBoonsWithoutReverting(uint256 menuWord) public {
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(6, 0.005 ether);
        _ready();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, menuWord | 1)));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.occupyEveryLane, (bettor, day + 1)));
        vm.prank(address(game)); quests.awardQuestStreakShield(bettor, type(uint16).max);
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        (uint256 s0, uint256 s1) = ProtocolBoonFixture(address(game)).boonWords(bettor);
        vm.etch(address(game), original);
        _resolve();
        vm.etch(address(game), address(fixture).code);
        (uint256 after0, uint256 after1) = ProtocolBoonFixture(address(game)).boonWords(bettor);
        vm.etch(address(game), original);
        assertEq(after0, s0, "active stronger lanes stay unchanged");
        assertEq(after1, s1, "currency lanes cannot collide with each other");
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
    }
    function testRealDailyAdvanceAutomaticallyAwardsAndContinues() public {
        // Drive requests and all intermediate drain stages through production code.
        uint256 fulfilled;
        for (uint256 d; d < 2; ++d) {
            if (d == 1) {
                vm.prank(bettor); _bet(0, 0.005 ether);
                vm.prank(bettor); _bet(6, 0.005 ether);
                day = game.currentDayView();
                vm.warp(vm.getBlockTimestamp() + 1 days);
            }
            bool finished;
            for (uint256 i; i < 150; ++i) {
                game.advanceGame();
                uint256 request = mockVRF.lastRequestId();
                if (request > fulfilled) {
                    mockVRF.fulfillRandomWords(request, 12345 + d);
                    fulfilled = request;
                }
                if (!game.rngLocked() && game.rngWordForDay(game.currentDayView()) != 0) { finished = true; break; }
            }
            assertTrue(finished, "daily advance must finish after the boon stage");
        }
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
    }
    function testCheckedEntryCountCannotPartiallyFundBet() public {
        uint256 future = game.futurePrizePoolView();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.maxEntries, (address(vault), day)));
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(bettor); _bet(0, 0.005 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, type(uint32).max);
        assertEq(game.futurePrizePoolView(), future);
    }

    function testGameOverRejectsBetsAndNeverIssuesBoons() public {
        vm.prank(bettor); _bet(0, 0.005 ether);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.endGame, ()));
        _ready();
        vm.recordLogs();
        _resolve();
        _assertBettorAwards(vm.getRecordedLogs(), 0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 0);
        // A terminal game retains the liveness trigger that ended it.
        vm.warp(vm.getBlockTimestamp() + 1_000 days);
        vm.expectRevert(); vm.prank(bettor); _bet(0, 0.005 ether);
        vm.expectRevert(); vm.prank(bettor); _bet(6, 0.005 ether);
    }

    function testLivenessDeadlineRejectsEthEntries() public {
        vm.warp(vm.getBlockTimestamp() + 1_000 days);
        day = game.currentDayView();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.requireLivenessTriggered, ()));
        assertFalse(game.gameOver());
        vm.expectRevert(); vm.prank(bettor); _bet(0, 0.005 ether);
        vm.expectRevert(); vm.prank(bettor); _bet(6, 0.005 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 0);
    }

    function testOnlyEthAndProtocolSymbolsCreateEntries() public {
        vm.prank(address(game)); coin.mintForGame(bettor, 1000 ether);
        vm.prank(address(game)); wwxrp.mintPrize(bettor, 10 ether);
        for (uint8 symbol; symbol < 32; ++symbol) {
            vm.prank(bettor); _bet(symbol, 0.005 ether);
        }
        for (uint8 i; i < 2; ++i) {
            uint8 symbol = i == 0 ? 0 : 6;
            vm.prank(bettor); game.placeDegeneretteBet(address(0), 1, 100 ether, 1, symbol);
            vm.expectRevert(bytes4(keccak256("UnsupportedCurrency()")));
            vm.prank(bettor); game.placeDegeneretteBet(address(0), 3, 1 ether, 1, symbol);
        }
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 1);
    }

    function testRawPaidTotalAcrossSpinsExcludesBoonBoostAndMatchesHeroLedger() public {
        _score(bettor, 400);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.seedBoon, (bettor, day)));
        vm.prank(bettor); game.placeDegeneretteBet{value: 0.03 ether}(address(0), 0, 0.01 ether, 3, 6);
        DegenerusGameStorage.ProtocolBoonPool memory pool = lens.protocolBoonPool(address(game), address(sdgnrs), day);
        assertEq(pool.totalWageredWei, 0.03 ether);
        assertEq(pool.totalWeight, 300 * 1600);
        assertEq(pool.entryCount, 1);
        // Locate the symbol ledger through the fixture's layout, without guessing a slot.
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        uint256 bet = ProtocolBoonFixture(address(game)).bet(1, 1);
        assertEq(address(uint160(bet)), bettor, "the bettor owns queue position 0");
        assertEq(((bet >> 188) & type(uint64).max) * 1 gwei, 0.0112 ether, "effective stake actually received the boon");
        assertEq(ProtocolBoonFixture(address(game)).heroWeight(day, 6), 300);
        vm.etch(address(game), original);
    }

    function testGiftAndApprovedOperatorUseRecipientAndTheirScore() public {
        address recipient = makeAddr("recipient");
        _score(recipient, 400);
        _score(bettor, 1200);
        vm.prank(bettor); game.placeDegeneretteBet{value: 0.005 ether}(recipient, 0, 0.005 ether, 1, 0);
        DegenerusGameStorage.ProtocolBoonEntry memory entry = lens.protocolBoonEntryAt(address(game), address(vault), day, 0);
        assertEq(entry.player, recipient); assertEq(entry.scoreSnapshot, 400); assertEq(entry.cumulativeWeight, 80_000);
        vm.prank(bettor); game.setOperatorApproval(address(this), true);
        game.placeDegeneretteBet{value: 0.005 ether}(bettor, 0, 0.005 ether, 1, 6);
        entry = lens.protocolBoonEntryAt(address(game), address(sdgnrs), day, 0);
        assertEq(entry.player, bettor); assertEq(entry.scoreSnapshot, 1200); assertEq(entry.cumulativeWeight, 120_000);
    }

    function testClaimableEthFundsTheSameWeightWithoutFreshValue() public {
        vm.deal(address(game), address(game).balance + 0.02 ether);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.claimable, (bettor, 0.02 ether)));
        vm.prank(bettor); game.placeDegeneretteBet(address(0), 0, 0.02 ether, 1, 0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWageredWei, 0.02 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, 200 * 800);
    }

    function testUninitializedDeityDoesNotCreateEntries() public {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.clearDeity, (0)));
        vm.prank(bettor); _bet(0, 0.005 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
    }

    function testQuoteUsesCanonicalScoreDuringJackpotPhase() public {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.staleMintStreak, (bettor)));
        (, uint16 score,, uint64 weight) = lens.protocolBoonQuote(address(game), bettor, 0.005 ether);
        assertEq(score, 40);
        vm.prank(bettor); _bet(0, 0.005 ether);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 0).scoreSnapshot, score);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, weight);
    }

    function testFuzzPaidWeightMatchesQuote(uint128 amount, uint16 score) public {
        amount = uint128(bound(amount, 0.005 ether, 100 ether) / 1 gwei * 1 gwei); // whole-gwei stakes
        score = uint16(bound(score, 0, 30_000));
        _score(bettor, score);
        (, uint16 quotedScore,, uint64 weight) = lens.protocolBoonQuote(address(game), bettor, amount);
        vm.prank(bettor); _bet(0, amount);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, weight);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWageredWei, amount);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 0).scoreSnapshot, quotedScore);
    }

    function testGeneratedSpinsDoNotEnrollEvenWithProtocolHeroes() public {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.generatedSpins, (address(degeneretteModule), bettor, 0)));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.generatedSpins, (address(degeneretteModule), bettor, 6)));
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 0);
    }

    function testEntryEventIdentifiesPaidStakeAndRecipient() public {
        _score(bettor, 400);
        vm.recordLogs();
        vm.prank(bettor); game.placeDegeneretteBet{value: 0.02 ether}(address(0), 0, 0.005 ether, 4, 6);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 entries;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("ProtocolBoonDrawEntered(address,address,uint24,uint256,uint16,uint64,uint32)")) continue;
            assertEq(logs[i].emitter, address(game));
            assertEq(address(uint160(uint256(logs[i].topics[1]))), address(sdgnrs));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), bettor);
            assertEq(uint256(logs[i].topics[3]), day);
            (uint256 amount, uint16 score, uint64 weight, uint32 index) = abi.decode(logs[i].data, (uint256, uint16, uint64, uint32));
            assertEq(amount, 0.02 ether); assertEq(score, 400); assertEq(weight, 320_000); assertEq(index, 0);
            ++entries;
        }
        assertEq(entries, 1);
    }

    function testFuzzSplittingStakeCannotGainWeight(uint96 a, uint96 b, uint16 score) public {
        a = uint96(bound(a, 0.005 ether, 0.5 ether) / 1 gwei * 1 gwei);
        b = uint96(bound(b, 0.005 ether, 0.5 ether) / 1 gwei * 1 gwei);
        score = uint16(bound(score, 0, 30_000));
        _score(bettor, score);
        vm.prank(bettor); _bet(0, uint128(a) + b);
        uint64 whole = lens.protocolBoonPool(address(game), address(vault), day).totalWeight;
        vm.prank(bettor); _bet(6, a);
        vm.prank(bettor); _bet(6, b);
        uint64 split = lens.protocolBoonPool(address(game), address(sdgnrs), day).totalWeight;
        assertLe(split, whole);
        assertLe(whole - split, fixture.multiplier(score));
    }

    // ---------------------------------------------------------------------
    // Two-day rings: day D's pool and entry slots are reused by day D + 2
    // ---------------------------------------------------------------------

    bytes32 private constant AWARDED_SIG =
        keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)");

    function _poolWord(address issuer, uint24 d) private view returns (uint256) {
        return uint256(vm.load(
            address(game), keccak256(abi.encode(uint256(d & 1), keccak256(abi.encode(issuer, uint256(48)))))
        ));
    }

    function _countAwards(Vm.Log[] memory logs) private pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == AWARDED_SIG) ++n;
    }

    /// @dev Day D + 2 takes over day D's slots after D's draw: the pool restarts empty under
    ///      D + 2's tag, entry 0 is overwritten, leftovers past the count stay hidden, and day D
    ///      now reads empty (its history lives in the events).
    function testRingSlotReusedTwoDaysLaterStartsEmpty() public {
        _score(bettor, 400);
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(0, 0.01 ether);
        _ready();
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        uint256 drawnWord = _poolWord(address(vault), day);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        address other = makeAddr("ringOther");
        vm.deal(other, 1 ether);
        _score(other, 0);
        vm.prank(other); _bet(0, 0.005 ether);

        DegenerusGameStorage.ProtocolBoonPool memory p = lens.protocolBoonPool(address(game), address(vault), day + 2);
        assertEq(p.day, day + 2);
        assertEq(p.entryCount, 1);
        assertEq(p.awardedMask, 0);
        assertEq(p.totalWageredWei, 0.005 ether);
        assertEq(p.totalWeight, 50 * fixture.multiplier(0));
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day + 2, 0).player, other);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day + 2, 1).player, address(0));
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
        assertTrue(_poolWord(address(vault), day + 2) != drawnWord, "same slot rewritten");
    }

    /// @dev A pool whose draw day passed with no draw (a stall) is never drawn later, even on an
    ///      award day whose own pool maps to the same ring slot and holds nothing of its own.
    function testStaleUndrawnPoolNeverDrawsOnALaterAwardDay() public {
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(6, 0.005 ether);
        uint256 staleVault = _poolWord(address(vault), day);
        uint256 staleSdgnrs = _poolWord(address(sdgnrs), day);
        // Day + 1 passes with no draw; day + 2 has no bets; day + 3 draws day + 2.
        vm.warp(vm.getBlockTimestamp() + 3 days);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 2, uint256(111))));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 3, uint256(222))));
        vm.recordLogs();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.resolve, (address(boonModule), day + 3)));
        assertEq(_countAwards(vm.getRecordedLogs()), 0, "stale pool drew on a later day's words");
        assertEq(_poolWord(address(vault), day), staleVault, "stale vault pool touched");
        assertEq(_poolWord(address(sdgnrs), day), staleSdgnrs, "stale sDGNRS pool touched");
        assertEq(lens.protocolBoonPool(address(game), address(vault), day + 2).entryCount, 0);
    }

    /// @dev Production advance over a stale ring slot: two days after a drawn pool, a quiet day's
    ///      draw finds the older pool's weight in the shared slot, calls the draw, which awards
    ///      nothing and writes nothing, and the daily advance still completes.
    function testRealAdvanceOverAStaleRingSlotAwardsNothing() public {
        _finishDailyAdvance(1);
        vm.prank(bettor); _bet(0, 0.005 ether);
        vm.prank(bettor); _bet(6, 0.005 ether);
        uint24 x = game.currentDayView();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishDailyAdvance(2);
        assertEq(lens.protocolBoonPool(address(game), address(vault), x).awardedMask, 7, "x drawn on x + 1");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishDailyAdvance(3);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        // Un-draw the stale pools so only the day-tag guard can stop them drawing on x + 3.
        for (uint256 i; i < 2; ++i) {
            address issuer = i == 0 ? address(vault) : address(sdgnrs);
            bytes32 slot = keccak256(abi.encode(uint256(x & 1), keccak256(abi.encode(issuer, uint256(48)))));
            vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) & ~(uint256(0xFF) << 208)));
        }
        uint256 vaultWord = _poolWord(address(vault), x);
        uint256 sdgnrsWord = _poolWord(address(sdgnrs), x);
        vm.recordLogs();
        _finishDailyAdvance(4);
        assertEq(_countAwards(vm.getRecordedLogs()), 0, "stale slot awarded");
        assertEq(_poolWord(address(vault), x), vaultWord, "stale vault slot written");
        assertEq(_poolWord(address(sdgnrs), x), sdgnrsWord, "stale sDGNRS slot written");
    }

    struct RefEntry {
        address player;
        uint64 cumulative;
    }

    /// @dev Random multi-day schedules: each day takes 0-3 bets from three bettors on either
    ///      protocol symbol, and each day's draw either happens on time or is skipped (a stall).
    ///      Every award must match an independent per-day model (a fresh pool per day, as if no
    ///      slot were ever reused): same day, slot, winning index and winner.
    function testFuzzRingMatchesPerDayModel(uint256 seed) public {
        address[3] memory bettors = [makeAddr("ringA"), makeAddr("ringB"), makeAddr("ringC")];
        for (uint256 b; b < 3; ++b) {
            vm.deal(bettors[b], 1_000 ether);
            _score(bettors[b], 100 * b);
        }
        uint256 days_ = 8;
        RefEntry[][2][] memory ref = new RefEntry[][2][](days_ + 1);
        for (uint256 k; k <= days_; ++k) {
            if (k > 0 && (uint256(keccak256(abi.encode(seed, k))) >> 200) % 3 != 0) {
                _ringDraw(seed, k, ref[k - 1]);
            }
            if (k == days_) break;
            ref[k] = _ringBets(seed, k, bettors);
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
    }

    /// @dev Draw yesterday's pool on today's words and check every award against the model.
    function _ringDraw(uint256 seed, uint256 k, RefEntry[][2] memory entries) private {
        uint24 d = day + uint24(k);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (d - 1, uint256(keccak256(abi.encode(seed, "m", k))))));
        uint256 w = uint256(keccak256(abi.encode(seed, "w", k)));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (d, w)));
        vm.recordLogs();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.resolve, (address(boonModule), d)));
        _checkAwards(vm.getRecordedLogs(), entries, d - 1, w);
    }

    /// @dev Place day k's random bets and return the model's entries per issuer (vault, sDGNRS).
    function _ringBets(uint256 seed, uint256 k, address[3] memory bettors)
        private
        returns (RefEntry[][2] memory out)
    {
        uint256 r = uint256(keccak256(abi.encode(seed, k)));
        uint256 n = r % 4;
        out[0] = new RefEntry[](0);
        out[1] = new RefEntry[](0);
        for (uint256 i; i < n; ++i) {
            uint256 b = (r >> (8 + i * 4)) % 3;
            uint256 side = (r >> (40 + i)) & 1;
            uint128 amount = uint128((0.005 ether + ((r >> (64 + i * 16)) % 1000) * 0.001 ether) / 1 gwei * 1 gwei);
            vm.prank(bettors[b]); _bet(side == 0 ? 0 : 6, amount);
            uint64 weight = uint64((uint256(amount) / 1e14) * fixture.multiplier(100 * b));
            out[side] = _append(out[side], bettors[b], weight);
        }
    }

    function _append(RefEntry[] memory list, address player, uint64 weight) private pure returns (RefEntry[] memory grown) {
        grown = new RefEntry[](list.length + 1);
        uint64 prior;
        for (uint256 i; i < list.length; ++i) grown[i] = list[i];
        if (list.length != 0) prior = list[list.length - 1].cumulative;
        grown[list.length] = RefEntry(player, prior + weight);
    }

    function _indexOf(address[3] memory list, address who) private pure returns (uint256) {
        for (uint256 i; i < 3; ++i) if (list[i] == who) return i;
        revert("unknown bettor");
    }

    function _checkAwards(Vm.Log[] memory logs, RefEntry[][2] memory entries, uint24 d, uint256 w) private view {
        uint64[2] memory totals;
        for (uint256 side; side < 2; ++side) {
            if (entries[side].length != 0) totals[side] = entries[side][entries[side].length - 1].cumulative;
        }
        uint256[2] memory seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != AWARDED_SIG) continue;
            address issuer = address(uint160(uint256(logs[i].topics[1])));
            uint256 side = issuer == address(vault) ? 0 : 1;
            assertEq(uint256(logs[i].topics[3]), d, "award for the wrong day");
            (uint8 slot, uint32 index, ) = abi.decode(logs[i].data, (uint8, uint32, uint8));
            uint256 roll = uint256(keccak256(abi.encode(
                keccak256("degenerus.protocol.boon.winner"), issuer, d, slot, w
            ))) % totals[side];
            uint32 lo;
            uint32 hi = uint32(entries[side].length);
            while (lo < hi) {
                uint32 mid = lo + (hi - lo) / 2;
                if (entries[side][mid].cumulative <= roll) lo = mid + 1;
                else hi = mid;
            }
            assertEq(index, lo, "winning index");
            assertEq(address(uint160(uint256(logs[i].topics[2]))), entries[side][lo].player, "winner");
            ++seen[side];
        }
        assertEq(seen[0], entries[0].length != 0 ? 3 : 0, "vault award count");
        assertEq(seen[1], entries[1].length != 0 ? 3 : 0, "sDGNRS award count");
    }
}
