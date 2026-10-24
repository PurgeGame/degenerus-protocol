// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {TicketGasHarness} from "../repro/JackpotTicketAwardChunks.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev The original heavy 512-holder quadrants, isolated into individual units
/// with the production first-progress context. A zero allowance commits exactly
/// one mandatory unit, leaving no budget for an optional following unit.
contract JackpotEthNativeUnitsTest is NativeGasExport {
    TicketGasHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    function setUp() public {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
        h = new TicketGasHarness();
        h.seed(LVL, WORD, false);
        h.seedDaily(LVL);
    }

    function _one() private returns (MineFlipGas.Result memory) {
        return h.runDailyJackpot(true, LVL, WORD, MineFlipGas.budget(0, 10_000, true));
    }

    function _measure(string memory label, uint256 allowance, uint256 expectedWins, bool expectDone) private {
        uint256 snapshot = vm.snapshotState();
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.recordLogs();
        MineFlipGas.Result memory result = h.runDailyJackpot(true, LVL, WORD, allowance);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 wins;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == ETH_WIN) ++wins;
        assertEq(wins, expectedWins, "exact original sampler group");
        assertEq(result.done, expectDone, "expected phase completion");
        assertEq(result.progressed, allowance != 320_000, "only the plan-only call refuses progress");
        assertLt(used, 10_000_000, "one checkpoint fits");
        emit log_named_uint("cold_native_eth_unit", used);
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(label, address(this), address(h),
                abi.encodeCall(h.runDailyJackpot, (true, LVL, WORD, allowance)));
        }
        vm.deleteStateSnapshot(snapshot);
    }

    function test_NativeEthSetupOnly() public {
        _measure("jackpot-unit-setup", MineFlipGas.budget(0, 10_000, true), 0, false);
    }
    function test_NativeEthFirstGroup() public {
        assertTrue(_one().progressed);
        _measure("jackpot-unit-first-eight", MineFlipGas.budget(0, 10_000, true), Bounds.JACKPOT_ETH_AWARD_CHUNK, false);
    }
    function test_NativeEthContinuationGroup() public {
        assertTrue(_one().progressed);
        assertTrue(_one().progressed);
        _measure("jackpot-unit-next-eight", MineFlipGas.budget(0, 10_000, true), Bounds.JACKPOT_ETH_AWARD_CHUNK, false);
    }
    function test_NativeEthPlanOnly() public {
        assertTrue(_one().progressed);
        _measure("jackpot-unit-plan", 320_000, 0, false);
    }
    function test_NativeEthFinalGroup() public {
        for (uint256 i; i < 256; ++i) {
            uint256 snapshot = vm.snapshotState();
            bool done = _one().done;
            if (!done) { vm.deleteStateSnapshot(snapshot); continue; }
            assertTrue(vm.revertToStateAndDelete(snapshot));
            _measure("jackpot-unit-final-solo", MineFlipGas.budget(0, 10_000, true), 1, true);
            return;
        }
        revert("canonical groups must complete");
    }
}
