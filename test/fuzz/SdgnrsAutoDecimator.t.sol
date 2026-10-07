// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {activityScoreOf} from "../helpers/ActivityScoreOf.sol";

/// @dev Expose the production RNG gate; settlement, quests, burn and craps are all real.
contract AutoDecimatorAdvanceHarness is DegenerusGameAdvanceModule {
    function applyOpeningWord(uint24 day) external {
        if (_recordedDailyWord(day) != 0) return;
        (bool ok, bytes memory err) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameAdvanceModule.applyDailyWord.selector)
        );
        if (!ok) assembly ("memory-safe") { revert(add(err, 32), mload(err)) }
    }
}

contract AutoDecimatorGameHarness is DegenerusGame {
    function setDecReference(uint64 stack, uint40 count, uint24 lvl) external {
        decPreviousStack = stack;
        decPreviousCount = count;
    }

    function prepareOpening(uint24 day, uint24 lvl, uint256 word, bool opening) external {
        dailyIdx = day - 1;
        purchaseStartDay = day - 1;
        level = lvl;
        rngRequestTime = uint48(block.timestamp);
        rngRequestDay = day;
        ticketsFullyProcessed = true;
        rngLockedFlag = true;
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        rngWordCurrent = word < 2 ? RNG_WORD_WAITING : word;
        _setDecWindowOpen(true);
        if (opening) decBattleRounds[lvl + 1].openedDay = _simulatedDayIndex();
        _setDecDayOneActive(opening);
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
        rngRequestTime = 1;
        vrfRequestId = 1;
        _setRngRequestActive(false);
        rngWordCurrent = RNG_WORD_WAITING;
        rngLockedFlag = false;
        lastPurchaseDay = false;
        // The opening day's session is over (its read consumers are done), so the engine's next
        // action is the real daily request.
        _setRngComplete(true);
    }

    /// @dev The wallet's entry for `lvl` (zero if its latest entry is another event); whole-FLIP stack.
    function entryFor(uint24 lvl, address owner) public view returns (uint64 id, uint256 stack) {
        uint256 latest = decBattlePlayers[_walletIdOf(owner)];
        if (uint24(latest >> 64) != lvl) return (0, 0);
        id = uint64(latest);
        stack = (_loadDecEntry(lvl, uint64(id)) >> 62);
    }

    function entry(uint24 lvl) external view returns (uint256 stack, uint64 id) {
        (id, stack) = entryFor(lvl, ContractAddresses.SDGNRS);
    }

}

contract SdgnrsAutoDecimatorTest is DeployProtocol {
    address private constant HOUSE = ContractAddresses.SDGNRS;
    uint32 private constant HOUSE_ID = 2;
    uint256 private constant CAP = 8000;
    bytes32 private constant BURN_EVENT = keccak256("DecimatorBurn(uint32,uint256,uint64)");
    bytes32 private constant RECORDED_EVENT =
        keccak256("DecBurnRecorded(uint32,uint24,uint64,uint256,uint256,uint256,uint32)");
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
        uint256 banked = coinflip.previewFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(banked);
        assertEq(coinflip.previewFlipBacking(HOUSE), 0);
    }

    function _warp(uint24 day) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _fund(uint256 amount) private {
        vm.prank(address(game));
        coinflip.creditFlip(HOUSE_ID, amount);
    }

    function _prepare(uint24 day, uint24 lvl, uint256 word, bool opening) private {
        _warp(day);
        harness.prepareOpening(day, lvl, word, opening);
    }

    function _autoBurn() private returns (uint256) {
        uint24 resolutionLevel = game.level() + 1;
        vm.prank(address(game));
        return coin.autoDecimatorBurn(resolutionLevel, CAP);
    }

    /// @dev The single DecBurnRecorded of one burn: its base (burn plus bonuses) and credited chips.
    function _recorded(Vm.Log[] memory logs) private view returns (uint256 base, uint256 credited) {
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == RECORDED_EVENT) {
                (base, credited,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint32));
                ++found;
            }
        }
        assertEq(found, 1, "one recorded burn");
    }

    function _burned(Vm.Log[] memory logs) private view returns (uint256 amount, uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coin) && logs[i].topics[0] == BURN_EVENT) {
                assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf(HOUSE));
                (uint256 spent,) = abi.decode(logs[i].data, (uint256, uint64));
                amount += spent;
                ++count;
            }
        }
    }

    function test_ManualBurnUsesFullMultiplierAndLateTopupDecay() public {
        address player = makeAddr("manual-decimator");
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        uint32 playerId = _giveWalletId(player);
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, player), abi.encode(uint256(500), playerId));
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScoreCachedById.selector, playerId), abi.encode(uint256(500)));
        vm.prank(address(game)); coin.mintForGame(player, 4_000_000);
        vm.recordLogs();
        vm.prank(player); coin.decimatorBurn(0, 2_000_000, 0);
        (uint256 firstBase, uint256 firstCredit) = _recorded(vm.getRecordedLogs());
        (uint64 id, uint256 first) = harness.entryFor(5, player);
        assertGt(id, 0);
        assertEq(first, firstCredit);
        assertEq(first, firstBase * ActivityCurveLib.decBattleMultBps(activityScoreOf(address(game), player)) / 10_000);
        _warp(23);
        vm.recordLogs();
        vm.prank(player); coin.decimatorBurn(0, 2_000_000, 0);
        (uint256 topupBase,) = _recorded(vm.getRecordedLogs());
        (uint64 again, uint256 total) = harness.entryFor(5, player);
        uint256 mult = ActivityCurveLib.decBattleMultBps(activityScoreOf(address(game), player));
        assertEq(again, id);
        assertEq(total, first + topupBase * mult * 81 / 1_000_000);
        assertEq(coin.balanceOf(player), 0);
    }

    function test_OpeningBurnsCarryBeforeCrapsAndCompletesTodaysQuest() public {
        _fund(400_000);
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
        (, bool secondary) = quests.questCompletionToday(HOUSE_ID);
        assertTrue(secondary, "opening day's decimator quest completes");
        (, bool afking) = quests.effectiveBaseStreakAndAfking(HOUSE_ID);
        assertTrue(afking, "activity reads the active afking run");
        uint256 questReward = coinflip.coinflipAmount(HOUSE);
        assertGt(questReward, 0, "quest pays a next-day flip credit");

        uint256 base = CAP + questReward;
        uint256 multiplier = ActivityCurveLib.decBattleMultBps(activityScoreOf(address(game), HOUSE));
        uint256 expected = base * multiplier / 10_000; // whole FLIP of chips
        (uint256 weight, uint64 id) = harness.entry(5);
        assertEq(weight, expected, "quest reward enters day-zero chip math");
        assertEq(id, 1);

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
        _fund(400_000);
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        uint256 backing = coinflip.previewFlipBacking(HOUSE);
        (uint256 weight,) = harness.entry(5);
        harness.applyOpeningWord(21);
        assertEq(coinflip.previewFlipBacking(HOUSE), backing);
        (uint256 afterWeight,) = harness.entry(5);
        assertEq(afterWeight, weight);

        _prepare(22, 14, 3, true);
        harness.applyOpeningWord(22);
        (uint256 nextWeight,) = harness.entry(15);
        assertGt(nextWeight, 0, "a later window receives its own entry");
    }

    function test_RealAdvanceGameReachesTheOpeningEntry() public {
        _fund(400_000);
        _prepare(21, 4, 3, true);
        vm.deal(address(game), 1000 ether);
        vm.recordLogs();
        // Genesis (initProtocolDeity) queues VAULT+SDGNRS perpetual entries into the
        // far-future key space for every level 2..100 at deploy. _mintCeiling() here is
        // level(4)+1 = 5, and level 5's far-future pool (2 owners) is exactly the "latched
        // last purchase day's frozen next-level pool" the daily drain gate now mints inside
        // the unified sweep BEFORE rngGate — one full budget per call, one thing per advance
        // (see runTicketWork's far-future continuation block). That first call resolves
        // the pool and returns early (STAGE_TICKETS_WORKING); the second call finds the gate
        // clear and reaches rngGate, where the opening-day decimator burn fires.
        game.mineFlip();
        game.mineFlip();
        (uint256 spent, uint256 count) = _burned(vm.getRecordedLogs());
        assertEq(spent, CAP);
        assertEq(count, 1);
        (uint256 weight,) = harness.entry(5);
        assertGt(weight, 0, "entry uses resolution level after request-time promotion");
        (uint256 previousWeight,) = harness.entry(4);
        assertEq(previousWeight, 0, "cached purchase level is not the resolution level");
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_CenturyOpeningTargetsLevel100() public {
        _fund(400_000);
        _prepare(21, 99, 3, true);
        vm.deal(address(game), 1000 ether);
        // As in test_RealAdvanceGameReachesTheOpeningEntry: _mintCeiling() = level(99)+1 = 100,
        // and genesis queued VAULT+SDGNRS perpetual entries into level 100's far-future pool at
        // deploy. The first mineFlip() call mints that pool inside the daily drain gate and
        // returns early; the second reaches rngGate and the opening-day decimator entry.
        game.mineFlip();
        game.mineFlip();
        (uint256 weight,) = harness.entry(100);
        assertGt(weight, 0);
        (uint256 previousWeight,) = harness.entry(99);
        assertEq(previousWeight, 0);
    }

    function test_UnderfundedAttemptCannotRetryInTheSameWindow() public {
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        _fund(400_000);
        harness.applyOpeningWord(21);
        // The next real daily request clears the opening flag while the decimator stays open.
        _warp(22);
        harness.prepareNextRequest(22);
        // The real daily request is the keeper engine's RequestDaily action (the advance module
        // only applies a delivered word); the word is then published and applied by the engine.
        uint256 requestBefore = mockVRF.lastRequestId();
        for (uint256 i; i < 20 && mockVRF.lastRequestId() == requestBefore; ++i) game.mineFlip();
        assertGt(mockVRF.lastRequestId(), requestBefore, "real daily request");
        assertTrue(game.rngLocked());
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 3);
        for (uint256 i; i < 20 && game.rngWordForDay(22) == 0; ++i) game.mineFlip();
        assertGt(game.rngWordForDay(22), 0, "day 22 word applied");
        assertTrue(game.decWindow());
        assertGt(coinflip.previewFlipBacking(HOUSE), CAP);
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
    }

    function test_NoOpeningLatchLeavesBackingForCraps() public {
        _fund(400_000);
        _prepare(21, 4, 3, false);
        harness.applyOpeningWord(21);
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
        assertGt(coinflip.previewFlipBacking(HOUSE), CAP);
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_EmptyBackingSkipsAndStillOpensCraps() public {
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
        assertGt(crapsBattle.daySeatNumberOf(21, HOUSE), 0);
    }

    function test_PendingLossCannotEscapeIntoDecimator() public {
        _fund(400_000);
        _prepare(21, 3, 3, false);
        harness.applyOpeningWord(21);
        assertGt(coinflip.previewFlipBacking(HOUSE), CAP);
        _prepare(22, 4, 2, true);
        vm.recordLogs();
        harness.applyOpeningWord(22);
        (, uint256 count) = _burned(vm.getRecordedLogs());
        assertEq(count, 0, "advance settles the loss before attempting entry");
        assertEq(coinflip.previewFlipBacking(HOUSE), 0, "loss applied before sizing entry");
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
    }

    function test_ConsumesClaimablesBeforeCarry() public {
        assertTrue(vm.revertToState(genesisBackingSnapshot));
        uint256 reserve = coinflip.previewFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(reserve - 2000);
        _fund(400_000);
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
        bankroll = bound(bankroll, 0, 2 * CAP);
        _fund(2 * CAP);
        _prepare(21, 4, 3, true);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 3, 21);
        uint256 backing = coinflip.previewFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(backing - bankroll);
        uint256 expected = bankroll < 2000 ? 0 : bankroll < CAP ? bankroll : CAP;
        assertEq(_autoBurn(), expected);
        assertEq(coinflip.previewFlipBacking(HOUSE), bankroll - expected);
    }

    function test_MinimumEntryCompletesDecimatorQuest() public {
        _fund(400_000);
        _prepare(21, 4, 3, true);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 3, 21);
        uint256 backing = coinflip.previewFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(backing - 2000);
        vm.prank(address(game));
        quests.rollDailyQuest(21, 3, false, false, true);
        assertEq(_autoBurn(), 2000);
        (, bool secondary) = quests.questCompletionToday(HOUSE_ID);
        assertTrue(secondary);
        (,, uint128[2] memory progress,) = quests.playerQuestStates(HOUSE_ID);
        assertEq(progress[1], 2000);
    }

    function test_OnlyGameMaySpendHouseBacking() public {
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.autoDecimatorBurn(5, CAP);
        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.autoDecimatorBurn(5, CAP);
    }

    function test_PreviousReferenceAboveOldCapControlsOpeningBurn() public {
        _fund(2_000_000);
        harness.setDecReference(400_001, 2, 100);
        _prepare(21, 104, 3, true);
        vm.recordLogs();
        harness.applyOpeningWord(21);
        (uint256 spent, uint256 count) = _burned(vm.getRecordedLogs());
        assertEq(spent, 800_002, "fourfold rational average, not rounded average or old ceiling");
        assertEq(count, 1);
    }

    function test_SubminimumReferenceSkipsWithoutConsuming() public {
        _fund(400_000);
        _prepare(21, 4, 3, true);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 3, 21);
        uint256 beforeBacking = coinflip.previewFlipBacking(HOUSE);
        vm.expectCall(address(coinflip), abi.encodeWithSignature("consumeFlipBacking(address,uint256)"), 0);
        vm.prank(address(game));
        assertEq(coin.autoDecimatorBurn(5, 1600), 0);
        assertEq(coinflip.previewFlipBacking(HOUSE), beforeBacking);
    }

    function test_ManualMinimumIncludesEveryTopup() public {
        address player = makeAddr("minimum-decimator");
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        vm.prank(address(game));
        coin.mintForGame(player, 8000);
        vm.startPrank(player);
        vm.expectRevert(FLIP.AmountLTMin.selector);
        coin.decimatorBurn(0, 1999, 0);
        coin.decimatorBurn(0, 2000, 0);
        vm.expectRevert(FLIP.AmountLTMin.selector);
        coin.decimatorBurn(0, 1999, 0);
        coin.decimatorBurn(0, 2000, 0);
        vm.stopPrank();
        assertEq(coin.balanceOf(player), 4000);
        (uint64 id,) = harness.entryFor(5, player);
        assertEq(id, 1, "topup retains its original entry");
    }
}
