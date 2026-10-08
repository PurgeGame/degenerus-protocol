// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {Test} from "forge-std/Test.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Craps} from "../../contracts/Craps.sol";

contract BudgetReadFixture is DegenerusGame {
    function publishRead() external {
        _swapRngBuffers();
        rngWordCurrent = 0xBEEF1234;
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        rngLockedFlag = false;
        ticketsFullyProcessed = true;
        _pendingBoxCount = 0;
        dailyIdx = _simulatedDayIndex();
    }
    function priorWork(uint8 stage) external {
        ticketsFullyProcessed = stage != 0;
        _pendingBoxCount = stage == 2 ? 1 : 0;
    }
    /// @dev The read buffer's first entry while the cursor has not passed it (0 once settled).
    function order() external view returns (uint256) { return boxCursor == 0 ? _boxEntryAt(_rngReadBuffer(), 0) : 0; }
    function cursor() external view returns (uint256) { return boxCursor; }
    function betCursor() external view returns (uint256) { return degeneretteCursor; }
    function bet() external view returns (uint256 word) {
        word = _loadDegeneretteBet(_rngReadBuffer(), 0);
    }
    function workHuman(uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runHumanBoxWork(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
    function workBet(uint256 allowance) external returns (MineFlipGas.Result memory) {
        humanReadComplete = true;
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSignature("runDegeneretteWork(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
}

contract MineFlipHumanBudgetTest is DeployProtocol {
    BudgetReadFixture private host;
    address private constant BUYER = address(0xA11CE);
    uint256 private constant PACKED = uint256(1) << 255;
    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 5000 ether);
        vm.deal(BUYER, 100 ether);
        vm.etch(address(game), type(BudgetReadFixture).runtimeCode);
        host = BudgetReadFixture(payable(address(game)));
    }
    function _queueWideBox() private {
        vm.prank(BUYER);
        game.purchase{value: 1 ether}(0, 0, BoxOrderLib.boCustoms(100, 0.01 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        host.publishRead();
        assertEq(BoxOrderLib.boCount(host.order()), 100);
        assertEq(BoxOrderLib.boId(host.order()), game.walletIdOf(BUYER));
    }
    function test_PublicRouterAttemptsWideBoxAtMaximumCalibration() public {
        _queueWideBox();
        game.mineFlip{gas: 12_000_000}(type(uint32).max);
        assertEq(host.order(), 0);
        assertEq(host.cursor(), 1);
    }
    function test_InvalidMultiplierCannotMutatePendingBox() public {
        _queueWideBox();
        uint256 beforeOrder = host.order();
        vm.expectRevert(MineFlipGas.InvalidGasMultiplier.selector);
        game.mineFlip(9_999);
        assertEq(host.order(), beforeOrder);
    }
    function test_ZeroAndExplicitBaselineProduceSameBoxOutcome() public {
        _queueWideBox();
        uint256 snap = vm.snapshotState();
        game.mineFlip{gas: 12_000_000}(0);
        uint256 expected = game.claimableWinningsOf(BUYER);
        uint256 cursor = host.cursor();
        vm.revertToStateAndDelete(snap);
        game.mineFlip{gas: 12_000_000}(10_000);
        assertEq(game.claimableWinningsOf(BUYER), expected);
        assertEq(host.cursor(), cursor);
    }
    function test_FirstWideBoxWaitsForItsAtomicAllowance() public {
        _queueWideBox();
        uint256 beforeOrder = host.order();
        MineFlipGas.Result memory result = host.workHuman(2_000_000);
        assertFalse(result.progressed);
        assertEq(host.order(), beforeOrder);
        assertEq(host.cursor(), 0);
        result = host.workHuman{gas: 10_000_000}(9_000_000);
        assertEq(result.rewardBasis, 100);
        assertTrue(result.done);
        assertEq(host.order(), 0);
    }
    function test_HumanCannotBypassEarlierConsumers() public {
        _queueWideBox();
        uint256 beforeOrder = host.order();
        for (uint8 stage; stage <= 2; ++stage) {
            host.priorWork(stage);
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(stage == 1));
            MineFlipGas.Result memory result = host.workHuman(9_000_000);
            assertFalse(result.progressed);
            assertEq(host.order(), beforeOrder);
            assertEq(host.cursor(), 0);
        }
    }
    function test_ExtremeCalibrationAttemptsOneWholeBet() public {
        vm.prank(BUYER);
        game.placeDegeneretteBet{value: 0.125 ether}(0, 0, uint128(0.005 ether), 25, 9);
        host.publishRead();
        MineFlipGas.Result memory result = host.workBet{gas: 10_000_000}(
            MineFlipGas.budget(9_000_000, type(uint32).max, true));
        assertTrue(result.progressed);
        assertEq(host.betCursor(), 1);
    }
    function test_BetReservesWholeSlipBeforeMutation() public {
        vm.prank(BUYER);
        game.placeDegeneretteBet{value: 0.125 ether}(0, 0, uint128(0.005 ether), 25, 9);
        host.publishRead();
        uint256 beforeBet = host.bet();
        MineFlipGas.Result memory result = host.workBet(500_000);
        assertFalse(result.progressed);
        assertEq(host.bet(), beforeBet);
        result = host.workBet{gas: 10_000_000}(9_000_000);
        assertEq(result.rewardBasis, 1);
        assertTrue(result.done);
        assertEq(host.bet(), beforeBet, "resolution does not write the bet");
        assertEq(host.betCursor(), 1);
    }
    function test_LowGasBoxCallWaitsForTheAtomicEntry() public {
        _queueWideBox();
        uint256 beforeOrder = host.order();
        (bool ok,) = address(host).call{gas: 2_000_000}(abi.encodeCall(host.workHuman, (9_000_000)));
        assertTrue(ok);
        assertEq(host.order(), beforeOrder);
        assertEq(host.cursor(), 0);
    }
    function test_DownstreamFailureRollsBackBoxMarkerAndCursor() public {
        _queueWideBox();
        uint256 beforeOrder = host.order();
        bytes memory code = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, hex"fe");
        vm.expectRevert(); host.workHuman(9_000_000);
        assertEq(host.order(), beforeOrder);
        assertEq(host.cursor(), 0);
        vm.etch(ContractAddresses.GAME_BOON_MODULE, code);
        MineFlipGas.Result memory result = host.workHuman{gas: 10_000_000}(9_000_000);
        assertEq(result.rewardBasis, 100);
    }

}

contract BudgetDecimatorFixture is DecimatorBattleHarness {
    function priorWork(uint8 stage) external {
        ticketsFullyProcessed = stage != 0;
        _pendingBoxCount = stage == 2 ? 1 : 0;
        humanReadComplete = stage != 3;
    }

    /// @dev The single-survivor fixture after its flat-engine run, optionally after ranking.
    ///      Seed reachable checkpoints so each admission bound can be tested independently
    ///      even when a cheap preceding phase normally chains straight through it.
    function completedRunCheckpoint(bool ranked) external {
        uint24 lvl = uint24(decBattleQueue);
        DecBattleRound storage round = decBattleRounds[lvl];
        require(round.count == 2 && round.cursor == 0 && round.phase == 1);
        uint256 entry = _loadDecEntry(lvl, uint64(1));
        decBattleHeap[0] = (((entry >> 62) * 3000e18) << 64) | 1;
        round.cursor = 1;
        round.winners = 1;
        if (ranked) {
            round.phase = 2;
            round.champion = 1;
            uint256 recycled = uint256(round.poolWei) / 2 / HALF_WHALE_PASS_PRICE * HALF_WHALE_PASS_PRICE;
            claimablePool -= uint128(recycled);
            _setFuturePrizePool(_getFuturePrizePool() + recycled);
        }
    }
}
contract BudgetBoundedEngine {
    function settleSlipBounded(uint256, uint256, uint256, uint256, bytes32, uint256 bankroll, uint256, uint256, uint256)
        external pure returns (Craps.SlipResult memory result)
    { result.peakBankroll = bankroll; result.totalRolls = 511; }
}
contract MineFlipDecimatorBudgetTest is Test {
    BudgetDecimatorFixture private host;
    uint24 private constant LVL = 5;
    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        host = new BudgetDecimatorFixture();
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(BudgetBoundedEngine).runtimeCode);
        host.open(LVL);
        vm.prank(ContractAddresses.COIN); host.recordFor(address(0xA11CE), LVL, 2000, 10_000, 0);
        vm.prank(ContractAddresses.COIN); host.recordFor(address(0xB0B), LVL, 2000, 10_000, 0);
        uint256 word = 2;
        while (Sample.at(word, LVL, 2, 0) != 1) ++word;
        host.seal(LVL, 30 ether, word);
    }
    function test_ExtremeCalibrationFinishesSimulationRankingAndPayment() public {
        uint256 calls;
        while (host.queue() != 0 && calls++ < 10) {
            MineFlipGas.Result memory result = host.runDecimatorWork{gas: 10_000_000}(
                MineFlipGas.budget(9_000_000, type(uint32).max, true));
            assertTrue(result.progressed, "each subphase persists a checkpoint");
        }
        assertEq(host.queue(), 0);
        assertEq(host.roundOf(LVL).phase, 3);
        assertEq(host.balanceOf(address(0xA11CE)), 16.5 ether);
        assertEq(host.passesOf(address(0xA11CE)), 6);
        assertGt(calls, 1);
    }
    function test_RunReservesBeforeMutationThenChainsRankAndPay() public {
        MineFlipGas.Result memory result = host.runDecimatorWork(500_000);
        assertFalse(result.progressed);
        assertEq(host.roundOf(LVL).cursor, 0);
        result = host.runDecimatorWork(1_000_000);
        assertEq(result.rewardBasis, 3);
        assertEq(host.roundOf(LVL).cursor, 1);
        assertTrue(result.done);
        assertEq(host.roundOf(LVL).phase, 3);
        assertEq(host.queue(), 0);
    }
    function test_RankReservesBeforeMutationThenChainsPayment() public {
        host.completedRunCheckpoint(false);
        MineFlipGas.Result memory result = host.runDecimatorWork(300_000);
        assertFalse(result.progressed);
        assertEq(host.roundOf(LVL).phase, 1);
        assertEq(host.roundOf(LVL).champion, 0);
        assertEq(host.reserved(), 30 ether);
        result = host.runDecimatorWork(700_000);
        assertTrue(result.progressed);
        assertEq(result.rewardBasis, 2);
        assertTrue(result.done);
        assertEq(host.roundOf(LVL).phase, 3);
    }
    function test_PaymentReservesBeforeMutation() public {
        host.completedRunCheckpoint(true);
        MineFlipGas.Result memory result = host.runDecimatorWork(100_000);
        assertFalse(result.progressed);
        assertEq(host.roundOf(LVL).paid, 0);
        assertEq(host.balanceOf(address(0xA11CE)), 0);
        assertEq(host.passesOf(address(0xA11CE)), 0);
        result = host.runDecimatorWork(400_000);
        assertTrue(result.done);
        assertEq(result.rewardBasis, 1);
        assertEq(host.roundOf(LVL).phase, 3);
        assertEq(host.queue(), 0);
        assertEq(host.balanceOf(address(0xA11CE)), 16.5 ether);
        assertEq(host.passesOf(address(0xA11CE)), 6);
        assertEq(host.reserved() + host.future(), 30 ether);
    }
    function test_DecimatorCannotBypassAnyEarlierStage() public {
        bytes memory beforeRound = abi.encode(host.roundOf(LVL));
        for (uint8 stage; stage < 4; ++stage) {
            host.priorWork(stage);
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(stage == 1));
            MineFlipGas.Result memory result = host.runDecimatorWork(9_000_000);
            assertFalse(result.progressed);
            assertEq(abi.encode(host.roundOf(LVL)), beforeRound);
        }
    }
    function test_EngineFailurePreservesRoundAndReservation() public {
        bytes memory beforeRound = abi.encode(host.roundOf(LVL));
        uint256 reserved = host.reserved();
        vm.etch(ContractAddresses.CRAPS_ENGINE, hex"fe");
        vm.expectRevert(); host.runDecimatorWork(9_000_000);
        assertEq(abi.encode(host.roundOf(LVL)), beforeRound);
        assertEq(host.reserved(), reserved);
    }
    function test_LowGasSimulationWaitsWithoutMutatingRound() public {
        bytes memory beforeRound = abi.encode(host.roundOf(LVL));
        (bool ok,) = address(host).call{gas: 500_000}(abi.encodeCall(host.runDecimatorWork, (9_000_000)));
        assertTrue(ok);
        assertEq(abi.encode(host.roundOf(LVL)), beforeRound);
    }
}
