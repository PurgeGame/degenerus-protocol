// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Target-contract tests and economic fixture configuration may isolate the owner role.
/// The complete deposit/approve/execute route is exercised in test/governance; this helper
/// deliberately does not advance game time or exercise escrow authorization.
library OwnerTargetCall {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function call(address target, bytes memory data, uint256 value) internal returns (bytes memory result) {
        (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
        if (mode == VmSafe.CallerMode.Prank || mode == VmSafe.CallerMode.RecurrentPrank) vm.stopPrank();
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (mode == VmSafe.CallerMode.RecurrentPrank) vm.startPrank(sender, origin);
        if (!ok) { assembly ("memory-safe") { revert(add(result, 32), mload(result)) } }
    }
}
