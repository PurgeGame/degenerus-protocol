// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

contract BudgetMeasurementCallee {
    function answer(uint256 value) external pure returns (uint256) { return value + 1; }
}

/// @dev Fixed internal-call budgets must be compared with callee frame execution,
///      excluding the transaction intrinsic cost added to isolated top-level calls.
contract ForkBudgetMeasurementTest is Test {
    BudgetMeasurementCallee private target;

    function setUp() public { target = new BudgetMeasurementCallee(); }

    function nested(bytes calldata data) external returns (uint256 used) {
        require(msg.sender == address(this));
        (bool ok, bytes memory out) = address(target).call(data);
        used = vm.lastCallGas().gasTotalUsed;
        assertTrue(ok);
        assertEq(abi.decode(out, (uint256)), 8);
    }

    function test_IsolatedTopLevelIncludesTransactionIntrinsic() public {
        bytes memory data = abi.encodeCall(target.answer, (7));
        (bool ok, bytes memory out) = address(target).call(data);
        uint256 direct = vm.lastCallGas().gasTotalUsed;
        assertTrue(ok);
        assertEq(abi.decode(out, (uint256)), 8);
        uint256 frame = this.nested(data);
        emit log_named_uint("top-level lastCallGas", direct);
        emit log_named_uint("nested frame lastCallGas", frame);
        uint256 intrinsic = 21_000;
        uint256 tokens;
        for (uint256 i; i < data.length; ++i) {
            intrinsic += data[i] == 0 ? 4 : 16;
            tokens += data[i] == 0 ? 1 : 4;
        }
        emit log_named_uint("transaction intrinsic", intrinsic);
        if (vm.envOr("FOUNDRY_ISOLATE", false)) {
            uint256 expected = frame + intrinsic;
            uint256 floor = 21_000 + tokens * 10;
            assertEq(direct, expected < floor ? floor : expected);
        }
        else assertEq(direct, frame);
    }
}
