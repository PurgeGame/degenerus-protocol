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
        if (opening) decBattleRounds[lvl + 1].openedDay = _simulatedDayIndex();
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

    /// @dev The wallet's entry for `lvl` (zero if its latest entry is another event); stack in wei.
    function entryFor(uint24 lvl, address owner) public view returns (uint64 id, uint256 stack) {
        uint256 latest = decBattlePlayers[owner];
        if (uint24(latest >> 64) != lvl) return (0, 0);
        id = uint64(latest);
        stack = (decBattleEntries[(uint256(lvl) << 64) | id] >> 190) * 1 ether;
    }

    function entry(uint24 lvl) external view returns (uint256 stack, uint64 id) {
        (id, stack) = entryFor(lvl, ContractAddresses.SDGNRS);
    }

}

contract SdgnrsAutoDecimatorTest is DeployProtocol {
    address private constant HOUSE = ContractAddresses.SDGNRS;
    uint256 private constant CAP = 500_000 ether;
    bytes32 private constant BURN_EVENT = keccak256("DecimatorBurn(address,uint256,uint64)");
    bytes32 private constant RECORDED_EVENT =
        keccak256("DecBurnRecorded(address,uint24,uint64,uint256,uint256,uint256,uint32)");
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
                assertEq(address(uint160(uint256(logs[i].topics[1]))), HOUSE);
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
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, player), abi.encode(uint256(500)));
        vm.prank(address(game)); coin.mintForGame(player, 4_000_000 ether);
        vm.recordLogs();
        vm.prank(player); coin.decimatorBurn(player, 2_000_000 ether, 0);
        (uint256 firstBase, uint256 firstCredit) = _recorded(vm.getRecordedLogs());
        (uint64 id, uint256 first) = harness.entryFor(5, player);
        assertGt(id, 0);
        assertEq(first, firstCredit);
        assertEq(first, firstBase * ActivityCurveLib.decBattleMultBps(game.playerActivityScore(player)) / 10_000);
        _warp(23);
        vm.recordLogs();
        vm.prank(player); coin.decimatorBurn(player, 2_000_000 ether, 0);
        (uint256 topupBase,) = _recorded(vm.getRecordedLogs());
        (uint64 again, uint256 total) = harness.entryFor(5, player);
        uint256 mult = ActivityCurveLib.decBattleMultBps(game.playerActivityScore(player));
        assertEq(again, id);
        assertEq(total, first + topupBase * mult * 81 / 1_000_000);
        assertEq(coin.balanceOf(player), 0);
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

        uint256 base = CAP + questReward;
        uint256 multiplier = ActivityCurveLib.decBattleMultBps(game.playerActivityScore(HOUSE));
        uint256 expected = base * multiplier / 10_000 / 1 ether * 1 ether; // whole FLIP of chips
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
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        harness.applyOpeningWord(21);
        uint256 backing = coinflip.previewSalvageFlipBacking(HOUSE);
        (uint256 weight,) = harness.entry(5);
        harness.applyOpeningWord(21);
        assertEq(coinflip.previewSalvageFlipBacking(HOUSE), backing);
        (uint256 afterWeight,) = harness.entry(5);
        assertEq(afterWeight, weight);

        _prepare(22, 14, 3, true);
        harness.applyOpeningWord(22);
        (uint256 nextWeight,) = harness.entry(15);
        assertGt(nextWeight, 0, "a later window receives its own entry");
    }

    function test_RealAdvanceGameReachesTheOpeningEntry() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, true);
        vm.deal(address(game), 1000 ether);
        vm.recordLogs();
        // Genesis (initProtocolDeity) queues VAULT+SDGNRS perpetual entries into the
        // far-future key space for every level 2..100 at deploy. _mintCeiling() here is
        // level(4)+1 = 5, and level 5's far-future pool (2 owners) is exactly the "latched
        // last purchase day's frozen next-level pool" the daily drain gate now mints inside
        // the unified sweep BEFORE rngGate — one full budget per call, one thing per advance
        // (see processTicketBatch's far-future continuation block). That first call resolves
        // the pool and returns early (STAGE_TICKETS_WORKING); the second call finds the gate
        // clear and reaches rngGate, where the opening-day decimator burn fires.
        game.advanceGame();
        game.advanceGame();
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
        _fund(400_000 ether);
        _prepare(21, 99, 3, true);
        vm.deal(address(game), 1000 ether);
        // As in test_RealAdvanceGameReachesTheOpeningEntry: _mintCeiling() = level(99)+1 = 100,
        // and genesis queued VAULT+SDGNRS perpetual entries into level 100's far-future pool at
        // deploy. The first advanceGame() call mints that pool inside the daily drain gate and
        // returns early; the second reaches rngGate and the opening-day decimator entry.
        game.advanceGame();
        game.advanceGame();
        (uint256 weight,) = harness.entry(100);
        assertGt(weight, 0);
        (uint256 previousWeight,) = harness.entry(99);
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
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
    }

    function test_NoOpeningLatchLeavesBackingForCraps() public {
        _fund(400_000 ether);
        _prepare(21, 4, 3, false);
        harness.applyOpeningWord(21);
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
        assertGt(coinflip.previewSalvageFlipBacking(HOUSE), CAP);
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
        (uint256 weight,) = harness.entry(5);
        assertEq(weight, 0);
    }

    function test_ConsumesClaimablesBeforeCarry() public {
        assertTrue(vm.revertToState(genesisBackingSnapshot));
        uint256 reserve = coinflip.previewSalvageFlipBacking(HOUSE);
        vm.prank(HOUSE);
        coinflip.withdrawRedeemedFlip(reserve - 50_000 ether);
        _fund(400_000 ether);
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
