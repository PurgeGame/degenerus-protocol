// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {FLIP} from "../../contracts/FLIP.sol";

/// @dev Expose the production RNG gate; settlement, quests, burn and craps are all real.
contract AutoDecimatorAdvanceHarness is DegenerusGameAdvanceModule {
    function applyOpeningWord(uint24 day) external {
        bool lastPurchase = !jackpotPhaseFlag && lastPurchaseDay;
        uint24 purchaseLevel = lastPurchase && rngLockedFlag ? level : level + 1;
        rngGate(uint48(block.timestamp), day, purchaseLevel, lastPurchase, 0, dailyIdx);
    }
}

contract AutoDecimatorGameHarness is DegenerusGame {
    function prepareOpening(uint24 day, uint24 lvl, uint256 word, bool opening) external {
        dailyIdx = day - 1;
        purchaseStartDay = day - 1;
        level = lvl;
        rngRequestTime = uint48(block.timestamp);
        rngLockedFlag = true;
        rngWordCurrent = word;
        decWindowOpen = true;
        decDayOneActive = opening;
        lastPurchaseDay = opening;
        if (opening) _setPrizePools(10 ether, 20 ether);
    }

    function applyOpeningWord(uint24 day) external {
        (bool ok, bytes memory err) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeCall(AutoDecimatorAdvanceHarness.applyOpeningWord, (day))
        );
        if (!ok) assembly { revert(add(err, 32), mload(err)) }
    }

    function prepareNextRequest(uint24 day) external {
        dailyIdx = day - 1;
        rngRequestTime = 0;
        vrfRequestId = 0;
        rngWordCurrent = 0;
        rngLockedFlag = false;
        lastPurchaseDay = false;
    }

    function entry(uint24 lvl) external view returns (uint192 burn, uint8 bucket) {
        DecBet storage bet = decBurn[lvl][ContractAddresses.SDGNRS];
        return (bet.burn, bet.bucket);
    }
}

contract SdgnrsAutoDecimatorTest is DeployProtocol {
    address private constant HOUSE = ContractAddresses.SDGNRS;
    uint256 private constant CAP = 150_000 ether;
    bytes32 private constant BURN_EVENT = keccak256("DecimatorBurn(address,uint256,uint8)");
    bytes32 private constant SETTLED_EVENT = keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)");
    bytes32 private constant QUEST_EVENT = keccak256("QuestSlotRolled(uint24,uint8,uint8,uint8,uint24)");
    AutoDecimatorGameHarness private harness;
    uint256 private genesisBackingSnapshot;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(AutoDecimatorGameHarness).runtimeCode);
        vm.etch(address(advanceModule), type(AutoDecimatorAdvanceHarness).runtimeCode);
        harness = AutoDecimatorGameHarness(payable(address(game)));
        // Bank one genesis win and arm sDGNRS's perpetual auto-rebuy normally.
        for (uint24 day = 1; day <= 20; ++day) {
            _warp(day);
            vm.prank(address(game));
            coinflip.processCoinflipPayouts(0, day == 1 ? 3 : 2, day);
        }
        genesisBackingSnapshot = vm.snapshotState();
        // Most cases start without a seed reserve; the mixed-source case restores it.
        uint256 banked = coinflip.previewSalvageFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(banked);
        assertEq(coinflip.previewSalvageFlipBacking(HOUSE), 0);
    }

    function _warp(uint24 day) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _fund(uint256 amount) private {
        vm.prank(address(game));
        coinflip.creditFlip(HOUSE, amount);
    }

    function _prepare(uint24 day, uint24 lvl, uint256 word, bool opening) private {
        _warp(day);
        harness.prepareOpening(day, lvl, word, opening);
    }

    function _autoBurn() private returns (uint256) {
        uint24 resolutionLevel = game.level() + 1;
        vm.prank(address(game));
        return coin.autoDecimatorBurn(resolutionLevel);
    }

    function _burned(Vm.Log[] memory logs) private view returns (uint256 amount, uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coin) && logs[i].topics[0] == BURN_EVENT) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), HOUSE);
                (uint256 spent,) = abi.decode(logs[i].data, (uint256, uint8));
                amount += spent;
                ++count;
            }
        }
    }

    function test_OpeningBurnsCarryBeforeCrapsAndCompletesTodaysQuest() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        uint256 supplyBefore = coin.totalSupply();
        vm.recordLogs();
        harness.applyOpeningWord(21);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 spent, uint256 count) = _burned(logs);
        assertEq(spent, CAP);
        assertEq(count, 1);
        assertTrue(game.rngLocked(), "carry burn is safe before the broader game unlock");
        assertEq(coin.totalSupply(), supplyBefore, "backing is consumed without minting");
        assertEq(coin.balanceOf(HOUSE), 0);
        (, bool secondary) = quests.questCompletionToday(HOUSE);
        assertTrue(secondary, "opening day's decimator quest completes");
        (, bool afking) = quests.effectiveBaseStreakAndAfking(HOUSE);
        assertTrue(afking, "activity reads the active afking run");
        uint256 questReward = coinflip.coinflipAmount(HOUSE);
        assertGt(questReward, 0, "quest pays a next-day flip credit");

        // The same quest reward also boosts the decimator base, under the normal cap.
        uint256 base = CAP + questReward;
        // Day-one burns are exempt from the last-purchase-day debuff, so the opening
        // bonus lands whole.
        uint256 multiplier = ActivityCurveLib.decMultBps(game.playerActivityScore(HOUSE)) * 12_000 / 10_000;
        // The multiplier covers the first 500k FLIP of base; base beyond it counts 1x.
        uint256 multipliedBase = base <= 500_000 ether ? base : 500_000 ether;
        uint256 expected = multipliedBase * multiplier / 10_000 + (base - multipliedBase);
        (uint192 weight, uint8 bucket) = harness.entry(5);
        assertEq(weight, expected, "quest reward and opening bonus enter normal weight math");
        assertEq(bucket, ActivityCurveLib.decBucket(game.playerActivityScore(HOUSE), 5));

        uint256 settleIndex = type(uint256).max;
        uint256 questIndex = type(uint256).max;
        uint256 burnIndex = type(uint256).max;
        uint256 crapsIndex = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip) && logs[i].topics[0] == SETTLED_EVENT) settleIndex = i;
            if (logs[i].emitter == address(quests) && logs[i].topics[0] == QUEST_EVENT) questIndex = i;
            if (logs[i].emitter == address(coin) && logs[i].topics[0] == BURN_EVENT) burnIndex = i;
            if (logs[i].emitter == address(crapsBattle) && crapsIndex == type(uint256).max) crapsIndex = i;
        }
        assertLt(settleIndex, questIndex, "coinflip settles before daily quests");
        assertLt(questIndex, burnIndex, "daily quests are rolled before the entry");
        assertLt(burnIndex, crapsIndex, "decimator gets first use of backing before craps");
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_RepeatedAdvancesCannotBurnTwice() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        uint256 backing = coinflip.previewSalvageFlipBacking(HOUSE);
        (uint192 weight,) = harness.entry(5);
        harness.applyOpeningWord(21);
        assertEq(coinflip.previewSalvageFlipBacking(HOUSE), backing);
        (uint192 afterWeight,) = harness.entry(5);
        assertEq(afterWeight, weight);

        _prepare(22, 14, 3, true);
        harness.applyOpeningWord(22);
        (uint192 nextWeight,) = harness.entry(15);
        assertGt(nextWeight, 0, "a later window receives its own entry");
    }

    function test_RealAdvanceGameReachesTheOpeningEntry() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        vm.deal(address(game), 1000 ether);
        vm.recordLogs();
        game.advanceGame();
        (uint256 spent, uint256 count) = _burned(vm.getRecordedLogs());
        assertEq(spent, CAP);
        assertEq(count, 1);
        (uint192 weight,) = harness.entry(5);
        assertGt(weight, 0, "entry uses resolution level after request-time promotion");
        (uint192 previousWeight,) = harness.entry(4);
        assertEq(previousWeight, 0, "cached purchase level is not the resolution level");
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_CenturyOpeningTargetsLevel100() public {
        _fund(400_000 ether);
        _prepare(21, 99, 3, true);
        vm.deal(address(game), 1000 ether);
        game.advanceGame();
        (uint192 weight,) = harness.entry(100);
        assertGt(weight, 0);
        (uint192 previousWeight,) = harness.entry(99);
        assertEq(previousWeight, 0);
    }

    function test_UnderfundedAttemptCannotRetryInTheSameWindow() public {
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        _fund(400_000 ether);
        harness.applyOpeningWord(21);
        // The next real daily request clears the opening flag while the decimator stays open.
        _warp(22);
        harness.prepareNextRequest(22);
        harness.applyOpeningWord(22);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 3);
        harness.applyOpeningWord(22);
        assertTrue(game.decWindow());
        assertGt(coinflip.previewSalvageFlipBacking(HOUSE), CAP);
        (uint192 weight,) = harness.entry(5);
        assertEq(weight, 0);
    }

    function test_NoOpeningLatchLeavesBackingForCraps() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, false);
        harness.applyOpeningWord(21);
        (uint192 weight,) = harness.entry(5);
        assertEq(weight, 0);
        assertGt(coinflip.previewSalvageFlipBacking(HOUSE), CAP);
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_EmptyBackingSkipsAndStillOpensCraps() public {
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        (uint192 weight,) = harness.entry(5);
        assertEq(weight, 0);
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_PendingLossCannotEscapeIntoDecimator() public {
        _fund(400_000 ether);
        _prepare(21, 3, 3, false);
        harness.applyOpeningWord(21);
        assertGt(coinflip.previewSalvageFlipBacking(HOUSE), CAP);
        _prepare(22, 4, 2, true);
        vm.recordLogs();
        harness.applyOpeningWord(22);
        (, uint256 count) = _burned(vm.getRecordedLogs());
        assertEq(count, 0, "advance settles the loss before attempting entry");
        assertEq(coinflip.previewSalvageFlipBacking(HOUSE), 0, "loss applied before sizing entry");
        (uint192 weight,) = harness.entry(5);
        assertEq(weight, 0);
    }

    function test_ConsumesClaimablesBeforeCarry() public {
        assertTrue(vm.revertToState(genesisBackingSnapshot));
        uint256 reserve = coinflip.previewSalvageFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(reserve - 50_000 ether);
        _fund(100_000 ether);
        _prepare(21, 4, 3, true);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 3, 21);
        uint256 banked = coinflip.previewClaimCoinflips(HOUSE);
        (,, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(HOUSE);
        assertGt(banked, 0);
        assertLt(banked, CAP, "fixture spends both sources");
        assertGt(banked + carry, CAP);
        assertEq(_autoBurn(), CAP);
        assertEq(coinflip.previewClaimCoinflips(HOUSE), 0);
        (,, uint256 afterCarry,) = coinflip.coinflipAutoRebuyInfo(HOUSE);
        assertEq(afterCarry, banked + carry - CAP);
    }

    function testFuzz_BankrollCapAndMinimum(uint256 bankroll) public {
        bankroll = bound(bankroll, 0, 300_000 ether);
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 3, 21);
        uint256 backing = coinflip.previewSalvageFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(backing - bankroll);
        uint256 expected = bankroll < 1000 ether ? 0 : bankroll < CAP ? bankroll : CAP;
        assertEq(_autoBurn(), expected);
        assertEq(coinflip.previewSalvageFlipBacking(HOUSE), bankroll - expected);
    }

    function test_MinimumEntryOnlyPartiallyCompletesQuest() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 3, 21);
        uint256 backing = coinflip.previewSalvageFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(backing - 1000 ether);
        vm.prank(address(game));
        quests.rollDailyQuest(21, 3, false, false, true);
        assertEq(_autoBurn(), 1000 ether);
        (, bool secondary) = quests.questCompletionToday(HOUSE);
        assertFalse(secondary);
        (,, uint128[2] memory progress,) = quests.playerQuestStates(HOUSE);
        assertEq(progress[1], 1000 ether);
    }

    function test_OnlyGameMaySpendHouseBacking() public {
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.autoDecimatorBurn(5);
        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.autoDecimatorBurn(5);
    }
}
