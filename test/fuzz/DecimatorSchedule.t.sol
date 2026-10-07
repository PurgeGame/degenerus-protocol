// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract DecimatorScheduleHost is DegenerusGameAdvanceModule {
    function prime(uint24 next, bool fast, bool sealing) external returns (uint24 day) {
        day = _simulatedDayIndex();
        level = next - 1;
        dailyIdx = day - 1;
        purchaseStartDay = day - (fast ? 1 : 3);
        lastPurchaseDay = !fast && !sealing;
        jackpotFlags = 2; // preserve the independent pending bonus bit
        subsFullyProcessed = true;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        _afkingResetDay = day;
        _setRngComplete(!sealing);
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        rngWordCurrent = 777;
        _setPrizePools(uint128(1000000 ether), 0);
        if (sealing) {
            rngLockedFlag = true;
            rngRequestDay = day;
            _recordDailyRng(day, 777);
            jackpotWork.kind = 1;
            jackpotWork.lvl = next;
        }
    }
    function flags() external view returns (uint8) { return jackpotFlags; }
    function finalDay() external view returns (bool) { return _isFinalJackpotDay(jackpotCounter, jackpotFlags); }
    function routing() external view returns (uint24) { return _activeTicketLevel(); }
    function closed() external view returns (bool) { return lastPurchaseDay; }
}

contract DecimatorScheduleTest is Test {
    DecimatorScheduleHost private h;
    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 5 days);
        vm.etch(ContractAddresses.GAME, type(DecimatorScheduleHost).runtimeCode);
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, type(DegenerusGameJackpotModule).runtimeCode);
        vm.mockCall(ContractAddresses.AFFILIATE, abi.encodeWithSignature("affiliateTop(uint24)"), abi.encode(uint32(0), uint96(0)));
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("poolBalance(uint8)"), abi.encode(uint256(0)));
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("lockJackpotBattle(uint24,uint256,uint24)"), abi.encode(uint64(0)));
        vm.mockCall(ContractAddresses.QUESTS, abi.encodeWithSignature("rollDailyQuest(uint24,uint256,bool,bool,bool)"), abi.encode(false));
        vm.mockCall(ContractAddresses.STETH_TOKEN, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        // Charity address is read from the shared interface constant; no-return mock catches its selector.
        vm.mockCall(ContractAddresses.GNRUS, abi.encodeWithSignature("pickCharity(uint24)"), "");
        h = DecimatorScheduleHost(ContractAddresses.GAME);
    }
    function test_RequestForcesOneDayBeforeRoutingAtBothClosureSpeeds() public {
        uint256 clean = vm.snapshotState();
        for (uint8 speed; speed < 2; ++speed) {
            assertTrue(vm.revertToState(clean)); clean = vm.snapshotState();
            uint24 day = h.prime(5, speed == 1, false);
            h.prepareRequestBoundary(day);
            assertEq(h.flags(), 3);
            assertTrue(h.finalDay());
            assertEq(h.routing(), 6);
        }
    }
    function test_SlowPurchaseSealForcesX5AndPreservesOtherSchedules() public {
        uint24[4] memory levels = [uint24(5), 15, 95, 100];
        uint256 clean = vm.snapshotState();
        for (uint256 i; i < levels.length; ++i) {
            assertTrue(vm.revertToState(clean)); clean = vm.snapshotState();
            h.prime(levels[i], false, true);
            // x00's ordinary seal also arms its existing coinflip BAF draw and settles the vault.
            vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("armBafDraw(uint24)"), "");
            vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("depositCoinflip(address,uint256)"), "");
            MineFlipGas.Result memory result = h.runDailyPhase(5_000_000);
            assertTrue(result.done);
            assertTrue(h.closed());
            assertEq(h.flags(), i < 2 ? 3 : 2);
            assertEq(h.finalDay(), i < 2);
        }
    }
}
