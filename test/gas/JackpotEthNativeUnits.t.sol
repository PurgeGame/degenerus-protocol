// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {TicketGasHarness} from "../repro/JackpotTicketAwardChunks.t.sol";
import {Test} from "forge-std/Test.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameJackpotModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {ProfileModules} from "../helpers/ProfileModules.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev TicketGasHarness only seeds storage here. The measured entry delegatecalls the deployed jackpot
///      shell at GAME_JACKPOT_MODULE (etched by ProfileModules.installGame) in the harness storage, the way
///      the Game dispatches runDailyJackpot, so the bytecode measured is the deployed one rather than the
///      raw module compiled into the harness.
contract DeployedJackpotHost is TicketGasHarness {
    function runDeployedDailyJackpot(bool inJackpot, uint24 lvl, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameJackpotModule.runDailyJackpot.selector, inJackpot, lvl, word, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
}

/// @dev The original heavy 512-holder quadrants, isolated into individual units
/// with the production first-progress context. A zero allowance commits exactly
/// one mandatory unit, leaving no budget for an optional following unit.
contract JackpotEthNativeUnitsTest is Test {
    DeployedJackpotHost private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    function setUp() public {
        // Deployed EIP-170 shells at every module address (jackpot, ticket, foil, whale, ...), not the raw modules.
        ProfileModules.installGame(vm);
        h = new DeployedJackpotHost();
        h.seed(LVL, WORD, false);
        h.seedDaily(LVL);
    }

    function _one() private returns (MineFlipGas.Result memory) {
        return h.runDeployedDailyJackpot(true, LVL, WORD, MineFlipGas.budget(0, 10_000, true));
    }

    function _measure(uint256 allowance, uint256 expectedWins, bool expectDone) private {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.recordLogs();
        MineFlipGas.Result memory result = h.runDeployedDailyJackpot(true, LVL, WORD, allowance);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 wins;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == ETH_WIN) ++wins;
        assertEq(wins, expectedWins, "exact original sampler group");
        assertEq(result.done, expectDone, "expected phase completion");
        assertEq(result.progressed, allowance != 320_000, "only the plan-only call refuses progress");
        assertLt(used, 10_000_000, "one checkpoint fits");
        emit log_named_uint("cold_native_eth_unit", used);
    }

    function test_NativeEthSetupOnly() public {
        _measure(MineFlipGas.budget(0, 10_000, true), 0, false);
    }
    function test_NativeEthFirstGroup() public {
        assertTrue(_one().progressed);
        _measure(MineFlipGas.budget(0, 10_000, true), Bounds.JACKPOT_ETH_AWARD_CHUNK, false);
    }
    function test_NativeEthContinuationGroup() public {
        assertTrue(_one().progressed);
        assertTrue(_one().progressed);
        _measure(MineFlipGas.budget(0, 10_000, true), Bounds.JACKPOT_ETH_AWARD_CHUNK, false);
    }
    function test_NativeEthPlanOnly() public {
        assertTrue(_one().progressed);
        _measure(320_000, 0, false);
    }
    function test_NativeEthFinalGroup() public {
        for (uint256 i; i < 256; ++i) {
            uint256 snapshot = vm.snapshotState();
            bool done = _one().done;
            if (!done) { vm.deleteStateSnapshot(snapshot); continue; }
            assertTrue(vm.revertToStateAndDelete(snapshot));
            _measure(MineFlipGas.budget(0, 10_000, true), 1, true);
            return;
        }
        revert("canonical groups must complete");
    }
}
