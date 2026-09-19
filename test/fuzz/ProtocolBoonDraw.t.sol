// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {IDegenerusGameBoonModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";

interface IBoonDonation {
    function donateFlipForBoons(uint256 amount) external;
}

contract RejectingBoonRecipient {
    function donate(address issuer) external {
        IBoonDonation(issuer).donateFlipForBoons(100 ether);
    }
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
    function endGame() external { gameOver = true; }
    function requireLivenessTriggered() external view { require(_livenessTriggered(), "not past death deadline"); }
    function finalDay(uint24 day) external {
        dailyIdx = day;
        rngWordByDay[day] = 123;
    }
    function maxEntries(address issuer, uint24 day) external {
        protocolBoonPools[issuer][day].entryCount = type(uint32).max;
    }
    function almostFullPool(address issuer, uint24 day) external {
        uint32 count = type(uint32).max - 1;
        protocolBoonPools[issuer][day] = ProtocolBoonPool(
            uint112(uint256(count) * 25_000 ether), uint64(count) * 600_000, count, 0
        );
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
    address private donor;
    uint24 private day;

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        fixture = new ProtocolBoonFixture();
        vm.warp(block.timestamp + 1 days);
        day = game.currentDayView();
        donor = makeAddr("donor");
        vm.prank(address(game)); coin.mintForGame(donor, 1_000_000 ether);
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
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, who), abi.encode(score));
    }
    function _ready() private {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, uint256(12345))));
        vm.warp(block.timestamp + 1 days);
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
    function _assertDonorAwards(Vm.Log[] memory logs, uint256 expected) private view {
        uint256 issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)")) continue;
            assertEq(logs[i].emitter, address(game));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), donor);
            assertEq(uint256(logs[i].topics[3]), day);
            ++issued;
        }
        assertEq(issued, expected);
    }
    function testPrincipalExactWeightTruncatedAndEachIssuerIsolated() public {
        _score(donor, 400);
        uint256 balance = coin.balanceOf(donor);
        uint256 vaultStake = coinflip.coinflipAmount(address(vault));
        uint256 sdgnrsStake = coinflip.coinflipAmount(address(sdgnrs));
        uint256 vaultWallet = coin.balanceOf(address(vault));
        vm.prank(donor); vault.donateFlipForBoons(199 ether + 17);
        vm.prank(donor); sdgnrs.donateFlipForBoons(25_000 ether);
        assertEq(coin.balanceOf(donor), balance - 25_199 ether - 17);
        assertEq(coin.balanceOf(address(vault)), vaultWallet);
        assertEq(coinflip.coinflipAmount(address(vault)), vaultStake + 199 ether + 17);
        assertEq(coinflip.coinflipAmount(address(sdgnrs)), sdgnrsStake + 25_000 ether);
        DegenerusGameStorage.ProtocolBoonPool memory p = lens.protocolBoonPool(address(game), address(vault), day);
        assertEq(p.totalDonatedWei, 199 ether + 17);
        assertEq(p.totalWeight, 1600);
        assertEq(p.entryCount, 1);
        assertEq(p.awardedMask, 0);
        DegenerusGameStorage.ProtocolBoonEntry memory e = lens.protocolBoonEntryAt(address(game), address(vault), day, 0);
        assertEq(e.donor, donor); assertEq(e.cumulativeWeight, 1600);
        assertEq(e.amountUnits, 1); assertEq(e.scoreSnapshot, 400);
        e = lens.protocolBoonEntryAt(address(game), address(sdgnrs), day, 0);
        assertEq(e.amountUnits, 250); assertEq(e.cumulativeWeight, 400_000);
    }
    function testScoresAreSnapshottedAndCapAtThreeTimes() public {
        uint256[6] memory scores = [uint256(0), 1, 400, 401, 1200, 5000];
        uint256[6] memory mult = [uint256(800), 802, 1600, 1601, 2400, 2400];
        uint256 sum;
        for (uint32 i; i < scores.length; ++i) {
            _score(donor, scores[i]);
            (uint8 units, uint16 score, uint16 multiplier, uint64 weight) = lens.protocolBoonQuote(address(game), donor, 100 ether);
            assertEq(units, 1); assertEq(score, scores[i]); assertEq(multiplier, mult[i]); assertEq(weight, mult[i]);
            vm.prank(donor); vault.donateFlipForBoons(100 ether);
            sum += mult[i];
            DegenerusGameStorage.ProtocolBoonEntry memory entry = lens.protocolBoonEntryAt(address(game), address(vault), day, i);
            assertEq(entry.cumulativeWeight, sum); assertEq(entry.scoreSnapshot, scores[i]);
        }
        _score(donor, 0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, sum);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 4).scoreSnapshot, 1200);
    }
    function testDonationStorageWriteFootprint() public {
        for (uint256 i; i < 2; ++i) {
            vm.record();
            vm.prank(donor); vault.donateFlipForBoons(100 ether);
            (, bytes32[] memory writes) = vm.accesses(address(game));
            assertEq(writes.length, 2, "one packed header write and one packed entry write");
            // Donations may only change the day's packed header and their own entry.
            bytes32 issuerRoot = keccak256(abi.encode(address(vault), uint256(48)));
            bytes32 poolSlot = keccak256(abi.encode(uint256(day), issuerRoot));
            bytes32 entryRoot = keccak256(abi.encode(uint256(day), keccak256(abi.encode(address(vault), uint256(49)))));
            bytes32 entrySlot = keccak256(abi.encode(i, entryRoot));
            for (uint256 j; j < writes.length; ++j) {
                assertTrue(writes[j] == poolSlot || writes[j] == entrySlot, "unrelated game state changed");
            }
        }
    }
    function testFuzzMultiplierMonotoneAndBounded(uint16 score) public view {
        uint256 m = fixture.multiplier(score);
        assertGe(m, 800); assertLe(m, 2400);
        assertGe(fixture.multiplier(uint256(score) + 1), m);
        if (score >= 1200) assertEq(m, 2400);
    }
    function testSingleDonorWinsAllSixWithoutDailyOrLifetimeCaps() public {
        // More than the ordinary recipient lifetime cap, all six slots on each day.
        for (uint256 round; round < 12; ++round) {
            vm.prank(donor); vault.donateFlipForBoons(100 ether);
            vm.prank(donor); sdgnrs.donateFlipForBoons(100 ether);
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
            vm.prank(address(game)); coin.mintForGame(who, 2500 ether);
            _score(who, i * 60);
            vm.prank(who); vault.donateFlipForBoons((i + 1) * 100 ether);
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
                cumulative += (i + 1) * fixture.multiplier(uint256(i) * 60);
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
    function testAmountBoundsInsufficientFundsAndUnauthorizedCallsAreAtomic() public {
        uint256 balance = coin.balanceOf(donor);
        uint256[3] memory badAmounts = [uint256(0), 100 ether - 1, 25_000 ether + 1];
        for (uint256 i; i < badAmounts.length; ++i) {
            vm.expectRevert(); vm.prank(donor); vault.donateFlipForBoons(badAmounts[i]);
        }
        vm.expectRevert(); vault.donateFlipForBoons(100 ether); // executor has no FLIP
        vm.expectRevert(); game.enterProtocolBoonDraw(donor, 100 ether);
        vm.expectRevert(); boonModule.enterProtocolBoonDraw(donor, 100 ether);
        vm.expectRevert(); boonModule.resolveProtocolBoonDraws(day + 1);
        assertEq(coin.balanceOf(donor), balance);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 0);
    }
    function testLaunchDayDonationsReceiveAllSixBoonsThroughRealAdvance() public {
        vm.warp(86_400); // DeployProtocol's day-1 timestamp.
        day = game.currentDayView();
        assertEq(day, 1);
        assertEq(game.rngWordForDay(1), 0);
        uint256 balance = coin.balanceOf(donor);
        uint256 vaultStake = coinflip.coinflipAmount(address(vault));
        uint256 sdgnrsStake = coinflip.coinflipAmount(address(sdgnrs));
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(100 ether);
        assertEq(coin.balanceOf(donor), balance - 200 ether);
        assertEq(coinflip.coinflipAmount(address(vault)), vaultStake + 100 ether);
        assertEq(coinflip.coinflipAmount(address(sdgnrs)), sdgnrsStake + 100 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 1);
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        _finishDailyAdvance(987654321);
        _assertDonorAwards(vm.getRecordedLogs(), 6);
        assertEq(game.rngWordForDay(day), 0, "launch day still has no RNG word");
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
        (bool ready, address[3] memory winners,,) = lens.findProtocolBoonWinners(address(game), address(vault), day);
        assertTrue(ready, "winner view supports launch-day pools");
        for (uint256 i; i < 3; ++i) assertEq(winners[i], donor);
        vm.recordLogs();
        _resolve();
        _assertDonorAwards(vm.getRecordedLogs(), 0);
    }
    function testGenesisDonationsWorkWhenDeploymentCrossesAReset() public {
        // A delayed deployment may initialize dailyIdx after relative day 1.
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.genesisDay, (day)));
        assertEq(game.rngWordForDay(day), 0);
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(100 ether);
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        _finishDailyAdvance(987654321);
        _assertDonorAwards(vm.getRecordedLogs(), 6);
        assertEq(game.rngWordForDay(day), 0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 7);
    }
    function testDonationsStayOpenBeforeAndAfterVrfFulfillmentWhileLocked() public {
        for (uint256 i; i < 150 && !game.rngLocked(); ++i) game.advanceGame();
        assertTrue(game.rngLocked());
        assertEq(game.rngWordForDay(day), 0);
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(100 ether);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 12345);
        assertTrue(game.rngLocked());
        vm.prank(donor); vault.donateFlipForBoons(200 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(200 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 2);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 2);
        _finishDailyAdvance(12345);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        _finishDailyAdvance(987654321);
        _assertDonorAwards(vm.getRecordedLogs(), 6);
    }
    function testManualProtocolBoonsBlockedIncludingApprovedOperator() public {
        _ready();
        vm.prank(address(vault)); game.setOperatorApproval(address(this), true);
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        game.issueDeityBoon(address(vault), donor, 0);
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        vm.prank(address(vault));
        game.issueDeityBoon(address(0), donor, 0);
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        vm.prank(address(sdgnrs));
        game.issueDeityBoon(address(0), donor, 0);
        vm.expectRevert(DegenerusGameStorage.OnlyDelegatecall.selector);
        boonModule.issueDeityBoon(address(vault), donor, 0);
    }
    function testRecipientContractCannotRejectAutomaticDelivery() public {
        RejectingBoonRecipient receiver = new RejectingBoonRecipient();
        vm.prank(address(game)); coin.mintForGame(address(receiver), 200 ether);
        receiver.donate(address(vault));
        receiver.donate(address(sdgnrs));
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
    function testMaximumPoolWidthsAcceptTheLastEntryWithoutOverflow() public {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.almostFullPool, (address(vault), day)));
        _score(donor, 1200);
        vm.prank(donor); vault.donateFlipForBoons(25_000 ether);
        DegenerusGameStorage.ProtocolBoonPool memory pool = lens.protocolBoonPool(address(game), address(vault), day);
        uint256 count = type(uint32).max;
        assertEq(pool.entryCount, count);
        assertEq(pool.totalDonatedWei, count * 25_000 ether);
        assertEq(pool.totalWeight, count * 600_000);
        DegenerusGameStorage.ProtocolBoonEntry memory entry =
            lens.protocolBoonEntryAt(address(game), address(vault), day, type(uint32).max - 1);
        assertEq(entry.cumulativeWeight, pool.totalWeight);
        assertEq(entry.donor, donor);
        uint256 balance = coin.balanceOf(donor);
        vm.expectRevert(); vm.prank(donor); vault.donateFlipForBoons(100 ether);
        assertEq(coin.balanceOf(donor), balance);
    }
    function testAutomaticDrawWaitsForWordAndNeverIssuesLate() public {
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        vm.warp(block.timestamp + 1 days);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 1, uint256(123))));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, uint256(456))));
        vm.warp(block.timestamp + 1 days);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
    }
    function testMissingPredecessorUsesAwardWordForMenuAndDoesNotReplay() public {
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.warp(block.timestamp + 1 days);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day + 1, uint256(123))));
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        _resolve();
        Vm.Log[] memory fallbackLogs = vm.getRecordedLogs();
        _assertDonorAwards(fallbackLogs, 3);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        vm.recordLogs();
        _resolve();
        _assertDonorAwards(vm.getRecordedLogs(), 0);
        assertTrue(vm.revertToState(snapshot));
        // The fallback must produce the same menu as a normal draw with this seed.
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, uint256(123))));
        vm.recordLogs();
        _resolve();
        assertEq(keccak256(abi.encode(vm.getRecordedLogs())), keccak256(abi.encode(fallbackLogs)));
    }
    function testNextDayDonationCannotChangeTheClosedPool() public {
        _score(donor, 400);
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        _ready();
        vm.prank(donor); vault.donateFlipForBoons(25_000 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).totalWeight, 1600);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day + 1).totalWeight, 400_000);
        _resolve();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day + 1).awardedMask, 0);
    }
    function testFuzzAllSixCollisionsKeepStrongerBoonsWithoutReverting(uint256 menuWord) public {
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(100 ether);
        _ready();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.word, (day, menuWord | 1)));
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.occupyEveryLane, (donor, day + 1)));
        vm.prank(address(game)); quests.awardQuestStreakShield(donor, type(uint16).max);
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        (uint256 s0, uint256 s1) = ProtocolBoonFixture(address(game)).boonWords(donor);
        vm.etch(address(game), original);
        _resolve();
        vm.etch(address(game), address(fixture).code);
        (uint256 after0, uint256 after1) = ProtocolBoonFixture(address(game)).boonWords(donor);
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
                vm.prank(donor); vault.donateFlipForBoons(100 ether);
                vm.prank(donor); sdgnrs.donateFlipForBoons(100 ether);
                day = game.currentDayView();
                vm.warp(block.timestamp + 1 days);
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
    function testCheckedEntryCountCannotDebitDonor() public {
        uint256 beforeBalance = coin.balanceOf(donor);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.maxEntries, (address(vault), day)));
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, type(uint32).max);
        assertEq(coin.balanceOf(donor), beforeBalance);
    }

    function testPostGameOverDonationsCreditBothIssuersWithoutIssuingBoons() public {
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.endGame, ()));
        uint256 beforeBalance = coin.balanceOf(donor);
        uint256 vaultStake = coinflip.coinflipAmount(address(vault));
        uint256 stakedStake = coinflip.coinflipAmount(address(sdgnrs));
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(200 ether);
        assertEq(coin.balanceOf(donor), beforeBalance - 300 ether);
        assertEq(coinflip.coinflipAmount(address(vault)), vaultStake + 100 ether);
        assertEq(coinflip.coinflipAmount(address(sdgnrs)), stakedStake + 200 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 1);
        _ready();
        vm.recordLogs();
        _resolve();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)"));
        }
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).awardedMask, 0);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).awardedMask, 0);
    }

    function testDonationsRemainOpenAfterLivenessDeadline() public {
        vm.warp(block.timestamp + 1_000 days);
        day = game.currentDayView();
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.requireLivenessTriggered, ()));
        assertFalse(game.gameOver(), "terminal flag has not latched yet");
        uint256 beforeBalance = coin.balanceOf(donor);
        uint256 vaultStake = coinflip.coinflipAmount(address(vault));
        uint256 stakedStake = coinflip.coinflipAmount(address(sdgnrs));
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        vm.prank(donor); sdgnrs.donateFlipForBoons(200 ether);
        assertEq(coin.balanceOf(donor), beforeBalance - 300 ether);
        assertEq(coinflip.coinflipAmount(address(vault)), vaultStake + 100 ether);
        assertEq(coinflip.coinflipAmount(address(sdgnrs)), stakedStake + 200 ether);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 1);
    }

    function testCoinflipDayOverflowRollsBackDonationAndPool() public {
        vm.warp(block.timestamp + uint256(type(uint24).max - day) * 1 days);
        day = game.currentDayView();
        assertEq(day, type(uint24).max);
        _fixtureCall(abi.encodeCall(ProtocolBoonFixture.finalDay, (day)));
        _score(donor, 1200);
        uint256 beforeBalance = coin.balanceOf(donor);
        vm.expectCall(address(coin), abi.encodeWithSelector(coin.burnCoin.selector, donor, 100 ether));
        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.creditFlip.selector, address(vault), 100 ether));
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(donor); vault.donateFlipForBoons(100 ether);
        assertEq(coin.balanceOf(donor), beforeBalance);
        DegenerusGameStorage.ProtocolBoonPool memory pool = lens.protocolBoonPool(address(game), address(vault), day);
        assertEq(pool.entryCount, 0);
        assertEq(pool.totalWeight, 0);
        assertEq(pool.totalDonatedWei, 0);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 0).donor, address(0));
    }
}
