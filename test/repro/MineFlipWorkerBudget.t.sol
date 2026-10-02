// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameLootboxModule, IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipBudget} from "../../contracts/libraries/MineFlipBudget.sol";
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
    function order(address owner) external view returns (uint256) { return _boxOrder(_rngReadBuffer(), owner); }
    function cursor() external view returns (uint256) { return boxCursor; }
    function bet() external view returns (uint256) { return degeneretteQueue[_rngReadBuffer()][0]; }
    function sweep(uint256 allowance) external returns (uint256 opened, uint256 report) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameLootboxModule.openHumanBoxes.selector, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint256, uint256));
    }
    function sweepBet(uint256 allowance, bool legacyFirst) external returns (uint256, uint256, uint256, uint256) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameDegeneretteModule.sweepDegeneretteBets.selector,
                _rngReadBuffer(), 0, allowance, legacyFirst, _lootboxWord(_rngReadBuffer()))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint256, uint256, uint256, uint256));
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
        game.purchase{value: 1 ether}(BUYER, 0, BoxOrderLib.boCustoms(100, 0.01 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        host.publishRead();
        assertEq(BoxOrderLib.boCount(host.order(BUYER)), 100);
    }
    function test_FirstWideBoxWaitsForItsFullAllowanceWithEitherReturnEncoding() public {
        _queueWideBox();
        uint256 beforeOrder = host.order(BUYER);
        (uint256 opened, uint256 charged) = host.sweep(639);
        assertEq(opened, 0); assertLe(charged, 639);
        assertEq(host.order(BUYER), beforeOrder); assertEq(host.cursor(), 0);
        (opened, charged) = host.sweep(PACKED | 639);
        assertEq(opened, 0); assertLe(charged >> 128, 639);
        assertEq(host.order(BUYER), beforeOrder); assertEq(host.cursor(), 0);
        (opened, charged) = host.sweep(PACKED | 640);
        assertEq(opened, 100); assertEq(charged >> 128, 640);
        assertEq(host.order(BUYER), 0);
    }
    function test_HumanCannotBypassEarlierConsumers() public {
        _queueWideBox();
        uint256 beforeOrder = host.order(BUYER);
        for (uint8 stage; stage <= 2; ++stage) {
            host.priorWork(stage);
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(stage == 1));
            (uint256 opened, uint256 charged) = host.sweep(PACKED | 1824);
            assertEq(opened, 0); assertEq(charged, 0);
            assertEq(host.order(BUYER), beforeOrder); assertEq(host.cursor(), 0);
        }
    }
    function test_BetLegacyFirstFlagCannotOvershootAndChargeIncludesFlushReserve() public {
        vm.prank(BUYER);
        game.placeDegeneretteBet{value: 0.125 ether}(BUYER, 0, uint128(0.005 ether), 25, 9);
        host.publishRead();
        uint256 beforeBet = host.bet();
        (uint256 resolved, uint256 pos, uint256 charged,) = host.sweepBet(241, true);
        assertEq(resolved, 0); assertEq(pos, 0); assertEq(charged, 6);
        assertEq(host.bet(), beforeBet);
        (resolved, pos, charged,) = host.sweepBet(242, true);
        assertEq(resolved, 1); assertEq(pos, 1); assertEq(charged, 242);
        assertTrue(host.bet() != beforeBet);
    }
    function test_DownstreamFailureRollsBackBoxMarkerAndCursor() public {
        _queueWideBox();
        uint256 beforeOrder = host.order(BUYER);
        bytes memory code = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, hex"fe");
        vm.expectRevert(); host.sweep(PACKED | 640);
        assertEq(host.order(BUYER), beforeOrder); assertEq(host.cursor(), 0);
        vm.etch(ContractAddresses.GAME_BOON_MODULE, code);
        (uint256 opened, uint256 charged) = host.sweep(PACKED | 640);
        assertEq(opened, 100); assertLe(charged >> 128, 640);
    }
    function testFuzz_TinyAllowanceIsAlwaysSafe(uint8 raw) public {
        _queueWideBox();
        uint256 allowance = uint256(raw) % 25;
        (uint256 opened, uint256 charged) = host.sweep(PACKED | allowance);
        assertEq(opened, 0); assertLe(charged >> 128, allowance);
        assertEq(BoxOrderLib.boCount(host.order(BUYER)), 100); assertEq(host.cursor(), 0);
    }
}

contract BudgetDecimatorFixture is DecimatorBattleHarness {
    function priorWork(uint8 stage) external {
        ticketsFullyProcessed = stage != 0;
        _pendingBoxCount = stage == 2 ? 1 : 0;
        humanReadComplete = stage != 3;
    }
}
contract BudgetBoundedEngine {
    function settleSlipBounded(uint256, uint256, uint256, uint256, bytes32, uint256 bankroll, address, uint256, uint256)
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
        vm.prank(ContractAddresses.COIN); host.recordDecBurn(address(0xA11CE), LVL, 1000 ether, 10_000, 0);
        uint256 word = 2;
        while (uint256(keccak256(abi.encode(keccak256("decimator.battle.final-coin.v1"), word, LVL, uint64(1)))) & 1 == 0) ++word;
        host.seal(LVL, 30 ether, word);
    }
    function test_RunRankAndPayEachReserveBeforeMutation() public {
        (uint256 done, uint256 charged, bool moved) = host.settleDecimatorWinners(121);
        assertEq(done, 0); assertLe(charged, 121); assertFalse(moved); assertEq(host.roundOf(LVL).cursor, 0);
        (done, charged, moved) = host.settleDecimatorWinners(122);
        assertEq(done, 1); assertLe(charged, 122); assertTrue(moved); assertEq(host.roundOf(LVL).cursor, 1);
        (done, charged, moved) = host.settleDecimatorWinners(22);
        assertEq(done, 0); assertLe(charged, 22); assertFalse(moved); assertEq(host.roundOf(LVL).phase, 1);
        (done, charged, moved) = host.settleDecimatorWinners(23);
        assertEq(done, 1); assertEq(charged, 23); assertTrue(moved); assertEq(host.roundOf(LVL).phase, 2);
        (done, charged, moved) = host.settleDecimatorWinners(27);
        assertEq(done, 0); assertLe(charged, 27); assertFalse(moved); assertEq(host.roundOf(LVL).paid, 0);
        (done, charged, moved) = host.settleDecimatorWinners(28);
        assertEq(done, 1); assertEq(charged, 28); assertTrue(moved); assertEq(host.roundOf(LVL).phase, 3);
        assertEq(host.queue(), 0);
    }
    function test_DecimatorCannotBypassAnyEarlierStage() public {
        bytes memory beforeRound = abi.encode(host.roundOf(LVL));
        for (uint8 stage; stage < 4; ++stage) {
            host.priorWork(stage);
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(stage == 1));
            (uint256 done, uint256 charged, bool moved) = host.settleDecimatorWinners(1824);
            assertEq(done, 0); assertEq(charged, 0); assertFalse(moved);
            assertEq(abi.encode(host.roundOf(LVL)), beforeRound);
        }
    }
    function test_EngineFailurePreservesRoundAndReservation() public {
        bytes memory beforeRound = abi.encode(host.roundOf(LVL));
        uint256 reserved = host.reserved();
        vm.etch(ContractAddresses.CRAPS_ENGINE, hex"fe");
        vm.expectRevert(); host.settleDecimatorWinners(122);
        assertEq(abi.encode(host.roundOf(LVL)), beforeRound); assertEq(host.reserved(), reserved);
    }
    function testFuzz_ChargedUnitsNeverExceedSuppliedAllowance(uint16 raw) public {
        uint256 allowance = raw;
        (, uint256 charged,) = host.settleDecimatorWinners(allowance);
        assertLe(charged, MineFlipBudget.clamp(allowance));
    }
}
