// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ProtocolDrawGasSeeder, ProtocolDailyGasHost} from "./ProtocolBoonAdvanceGas.t.sol";
import {ProtocolBoonDrawSeeder} from "./helpers/ProtocolBoonDrawSeeder.sol";
import {AdvanceCenturyDiverseDestinations, CenturyNativeGasHost} from "./AdvanceCenturyConsolidationGas.t.sol";
import {Vm} from "forge-std/Vm.sol";

contract StorageReuseNativeDailySeeder is ProtocolDrawGasSeeder {
    function alignPurchaseWindow(uint24 day) external {
        purchaseStartDay = day - 1;
    }
}

/// @dev Native calibration of complete phase calls. Export separately from the
///      matched codec comparison: these larger fixtures use their production prestate.
contract StorageReuseNativeDailyContext is DeployProtocol, NativeGasExport {
    function test_nativeDailyApplyWithSixMaximumDepthBoons() public {
        _deployProtocol();
        uint24 day = 21_000;
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.etch(address(game), type(StorageReuseNativeDailySeeder).runtimeCode);
        StorageReuseNativeDailySeeder(address(game)).seed();
        StorageReuseNativeDailySeeder(address(game)).alignPurchaseWindow(day);
        vm.etch(address(game), type(ProtocolBoonDrawSeeder).runtimeCode);
        ProtocolBoonDrawSeeder(address(game)).seedPools(day, 987654321);
        vm.etch(address(game), type(ProtocolDailyGasHost).runtimeCode);
        ProtocolDailyGasHost(payable(address(game))).publishOnly();
        _nativeFixture("daily_apply_six_boons", address(0x8888), address(game),
            abi.encodeCall(ProtocolDailyGasHost.applyOnly, ()));
        vm.recordLogs();
        ProtocolDailyGasHost(payable(address(game))).applyOnly();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 awards;
        uint256 applies;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256("ProtocolBoonDrawAwarded(uint32,uint32,uint24,uint8,uint32,uint8)")) ++awards;
            if (logs[i].topics[0] == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++applies;
        }
        assertEq(awards, 6, "all maximum-depth boon draws executed");
        assertEq(applies, 1, "fresh daily word applied");
    }
}

contract StorageReuseNativeCenturyContext is AdvanceCenturyDiverseDestinations {
    function _centuryDay() internal pure override returns (uint24) { return 21_000; }
    function _vaultHistoryMode() internal pure override returns (uint8) { return 1; }

    function test_nativeCenturyApplyWithFullVaultHistory() public {
        vm.etch(address(game), type(CenturyNativeGasHost).runtimeCode);
        CenturyNativeGasHost host = CenturyNativeGasHost(payable(address(game)));
        host.publishOnly();
        for (uint256 reads; !host.prepareTicketsOnly{gas: 12_000_000}(); ++reads) {
            assertLt(reads, 32, "ticket prerequisites stalled");
        }
        _nativeFixture("daily_apply_century_vault_90", address(0x8888), address(game),
            abi.encodeCall(CenturyNativeGasHost.applyOnly, ()));
    }
}
