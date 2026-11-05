// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BoundedCall} from "../../contracts/libraries/BoundedCall.sol";

/// @dev Records the gas each call arrives with. Cheap, so it never fails once reached.
contract GasWitnessDependency {
    uint256 public reached;
    uint256 public lowestEntryGas = type(uint256).max;

    function ping() external payable {
        uint256 entry = gasleft();
        ++reached;
        if (entry < lowestEntryGas) lowestEntryGas = entry;
    }

    function peek() external view returns (uint256) {
        return gasleft();
    }
}

/// @dev Builds a worker meter from a context word, as a nested frame does, then makes one bounded call.
contract MeteredBoundedCaller {
    function call(uint256 context, address target, uint256 value, uint256 minimum, uint256 reserve)
        external returns (bool ok)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(context);
        (ok,) = BoundedCall.callValueRemaining(meter, target, value, minimum, reserve,
            abi.encodeWithSignature("ping()"), 0);
    }

    function read(uint256 context, address target, uint256 minimum, uint256 reserve)
        external view returns (bool ok, uint256 entryGas)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(context);
        (ok, entryGas) = BoundedCall.staticWordRemaining(meter, target, minimum, reserve,
            abi.encodeWithSignature("peek()"));
    }

    receive() external payable {}
}

/// @title A dependency is reached only with its declared minimum, whatever gas or calibration the caller picks
/// @notice Every failure policy behind BoundedCall (a skipped stake, an unfunded subscription, a read taken
///         as zero, a skipped cancellation, an expired subscriber) is sound only if the dependency had its
///         minimum when it failed. So for every transaction gas, multiplier, first-unit or continuation
///         meter, ancestor floor, minimum and tail: the call either refuses before reaching the
///         dependency, or the dependency starts with at least its minimum.
contract DependencyAdmissionGuaranteeTest is Test {
    /// @dev The callee's own dispatch before its first gasleft().
    uint256 internal constant ENTRY_SLACK = 1_000;

    GasWitnessDependency internal dep;
    MeteredBoundedCaller internal caller;

    function setUp() public {
        dep = new GasWitnessDependency();
        caller = new MeteredBoundedCaller();
        vm.deal(address(caller), 1 ether);
    }

    function _context(uint256 allowance, uint32 multiplier, bool first) private pure returns (uint256) {
        return MineFlipGas.budget(allowance, multiplier, first);
    }

    function _shape(uint256 seed) private pure returns (uint32 multiplier, bool first, uint256 allowance,
        uint256 minimum, uint256 reserve)
    {
        uint256 m = seed % 6;
        multiplier = m == 0 ? MineFlipGas.MIN_MULTIPLIER : m == 1 ? 5_000 : m == 2 ? MineFlipGas.DEFAULT_MULTIPLIER
            : m == 3 ? 40_000 : uint32(bound(seed >> 8, MineFlipGas.MIN_MULTIPLIER, 100_000));
        first = (seed >> 40) & 1 == 0;
        // Raw context when the allowance draw is zero: no floor. Otherwise a nested frame's allowance.
        allowance = (seed >> 48) % 3 == 0 ? type(uint192).max : bound(seed >> 64, 0, 4_000_000);
        minimum = bound(seed >> 96, 10_000, 1_200_000);
        reserve = bound(seed >> 128, 0, 600_000);
    }

    function testFuzz_ValueCallReachesItsDependencyOnlyWithItsMinimum(uint256 seed, uint256 gasLimit, bool valued)
        public
    {
        (uint32 multiplier, bool first, uint256 allowance, uint256 minimum, uint256 reserve) = _shape(seed);
        gasLimit = bound(gasLimit, 30_000, 6_000_000);
        uint256 before = dep.reached();
        (bool called, bytes memory ret) = address(caller).call{gas: gasLimit}(abi.encodeCall(
            caller.call, (_context(allowance, multiplier, first), address(dep), valued ? 1 : 0, minimum, reserve)));
        if (dep.reached() == before) return;
        assertTrue(called, "a reached dependency leaves its caller able to finish");
        assertTrue(abi.decode(ret, (bool)), "the cheap dependency succeeds once reached");
        assertGe(dep.lowestEntryGas() + ENTRY_SLACK, minimum, "reached below its declared minimum");
    }

    function testFuzz_ReadReachesItsDependencyOnlyWithItsMinimum(uint256 seed, uint256 gasLimit) public view {
        (uint32 multiplier, bool first, uint256 allowance, uint256 minimum, uint256 reserve) = _shape(seed);
        gasLimit = bound(gasLimit, 30_000, 6_000_000);
        (bool called, bytes memory ret) = address(caller).staticcall{gas: gasLimit}(abi.encodeCall(
            caller.read, (_context(allowance, multiplier, first), address(dep), minimum, reserve)));
        if (!called) return;
        (bool ok, uint256 entryGas) = abi.decode(ret, (bool, uint256));
        // A refused read never returns: admission reverts. A returned read was reached.
        assertTrue(ok, "a reached read succeeds");
        assertGe(entryGas + ENTRY_SLACK, minimum, "read reached below its declared minimum");
    }

    /// @dev The first unit forwards all gas but still refuses short of minimum + EIP-150 share + overhead,
    ///      at every calibration (the first unit is never scaled).
    function test_FirstUnitRefusesBelowTheDependencyMinimum() public {
        uint256 context = _context(type(uint192).max, MineFlipGas.MIN_MULTIPLIER, true);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        caller.call{gas: 900_000}(context, address(dep), 0, 1_000_000, 300_000);
        assertEq(dep.reached(), 0, "a short first unit never reaches the dependency");
        assertTrue(caller.call{gas: 1_100_000}(context, address(dep), 0, 1_000_000, 300_000));
        assertEq(dep.reached(), 1);
        assertGe(dep.lowestEntryGas() + ENTRY_SLACK, 1_000_000);
    }
}
