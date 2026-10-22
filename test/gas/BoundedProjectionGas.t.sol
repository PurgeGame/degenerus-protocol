// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {Vm} from "forge-std/Vm.sol";

contract BoundedProjectionStore {
    function store(uint256 value) external { assembly ("memory-safe") { sstore(0, value) } }
    function pay(address recipient) external {
        assembly ("memory-safe") { if iszero(call(gas(), recipient, 1, 0, 0, 0, 0)) { revert(0, 0) } }
    }
}

contract BoundedProjectionGasTest is BoundedGasProbe {
    function _value(Vm.Log[] memory logs, string memory wanted) private pure returns (uint256) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != keccak256("log_named_uint(string,uint256)")) continue;
            (string memory key, uint256 value) = abi.decode(logs[i].data, (string, uint256));
            if (keccak256(bytes(key)) == keccak256(bytes(wanted))) return value;
        }
        revert("missing projection measurement");
    }
    function _check(string memory label, uint256 beforeValue, uint256 afterValue, bool warm, int256 delta) private {
        BoundedProjectionStore host = new BoundedProjectionStore();
        vm.store(address(host), bytes32(0), bytes32(beforeValue));
        vm.recordLogs();
        _measureBounded(label, address(host), address(this), 0, abi.encodeCall(host.store, (afterValue)), warm);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_value(logs, "first_write_cold_slots"), 1, "SSTORE is the first touch");
        uint256 current = _value(logs, "osaka_frame_gross");
        assertEq(_value(logs, "projected_glamsterdam_total"), uint256(int256(current) + delta));
    }
    function test_NewAccountReplacesOldCreationCharge() public {
        BoundedProjectionStore host = new BoundedProjectionStore();
        vm.deal(address(host), 1);
        vm.recordLogs();
        _measureBounded("projection_new_account", address(host), address(this), 0,
            abi.encodeCall(host.pay, (address(0xF0F0))), false);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_value(logs, "new_accounts"), 1);
        assertEq(_value(logs, "value_calls"), 1);
        assertEq(_value(logs, "projected_glamsterdam_total"),
            _value(logs, "osaka_frame_gross") + 161_300);
    }
    function test_ColdFreshStoreUsesNoExtraWarmCharge() public {
        _check("projection_cold_fresh", 0, 1, false, 87_920);
    }
    function test_ColdChangedStoreUsesNoExtraWarmCharge() public {
        _check("projection_cold_changed", 1, 2, false, 7_100);
    }
    function test_ColdNoopStorePaysOnlyColdAccess() public {
        _check("projection_cold_noop", 1, 1, false, -100);
    }
    function test_WarmChangedStoreRetainsWarmCharge() public {
        _check("projection_warm_changed", 1, 2, true, 7_200);
    }
}
