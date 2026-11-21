// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";

contract RepriceModelSink {
    uint256 public x;
    uint256 public t1;
    uint256 public t2;
    uint256 public r1;
    uint256 public r2;

    function poke() external {
        x = 1;
    }

    function setT(uint256 a, uint256 b) external {
        t1 = a;
        t2 = b;
    }

    function setR(bool fail) external {
        r1 = 9;
        r2 = 9;
        if (fail) revert();
    }

    receive() external payable {}
}

contract RepriceModelCaller {
    RepriceModelSink public immutable sink;
    uint256 public a;

    constructor(RepriceModelSink s) payable {
        sink = s;
    }

    function run(address dead) external {
        sink.poke();
        payable(address(sink)).transfer(1);
        (bool ok,) = dead.call{value: 1}("");
        require(ok);
        sink.setT(7, 7);
        sink.setT(0, 0);
        try sink.setR(true) {} catch {}
        a = 5;
    }
}

/// @notice Pins GlamsterdamReprice to the EIP-8037 / EIP-8038 schedule on a call whose accesses
///         are known: two value sends (one to a dead account), code-size checks, two slots created
///         and cleared inside the call, two slots written in a reverted frame, and two kept slots.
contract GlamsterdamRepriceModelTest is Test {
    function test_ModelPricesEachGlamsterdamTerm() external {
        RepriceModelSink sink = new RepriceModelSink();
        RepriceModelCaller caller = new RepriceModelCaller{value: 10}(sink);
        address dead = address(uint160(0xDEAD0000DEAD));
        uint256 snap = vm.snapshotState();

        vm.startDebugTraceRecording();
        caller.run(dead);
        VmSafe.DebugStep[] memory steps = vm.stopAndReturnDebugTraceRecording();
        uint256 census;
        for (uint256 i; i < steps.length; ++i) {
            if (steps[i].contractAddr != address(this) && (steps[i].opcode == 0x3b || steps[i].opcode == 0x3c)) {
                ++census;
            }
        }
        assertTrue(vm.revertToState(snap));

        vm.startStateDiffRecording();
        caller.run(dead);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(1_000_000, acc, address(caller));

        // Four checked calls without return data (poke, setT twice, setR); the caller's own
        // check before `run` sits at the measured frame's depth and is outside the call.
        assertEq(census, 4, "opcode census");
        assertEq(r.codeReads, census, "code reads inside the call");
        assertEq(r.valueCalls, 2, "transfer and the dead-account send");
        assertEq(r.newAccounts, 1, "the dead account");
        assertEq(r.coldAccounts, 2, "sink and the dead account; the target is warm");
        // x, t1, t2, r1, r2 and a are each first changes from zero.
        assertEq(r.firstChanges, 6, "first changes");
        assertEq(r.newSlots, 2, "x and a stay; t1/t2 are cleared and r1/r2 revert");
        assertEq(
            r.execDelta,
            int256(2 * 400 + 2 * 2_300 + 4 * 100) - 25_000 - 6 * 9_900,
            "cold accounts, value calls, code reads, dropped new-account charge, first changes"
        );
        assertEq(r.glamsterdamExec, uint256(int256(1_000_000) + r.execDelta), "execution");
        assertEq(r.finalStateGas, 2 * 97_920 + 183_600, "state gas kept at the end");
        // Peak: x and the dead account (281,520), then t1 and t2 before their clear.
        assertEq(r.stateGas, 2 * 97_920 + 183_600 + 97_920, "peak state gas");
        assertTrue(vm.revertToState(snap));
    }

    function measured(RepriceModelCaller caller, address dead) external returns (uint256) {
        caller.run(dead);
        return vm.lastCallGas().gasTotalUsed;
    }

    /// @dev Recording warms every account and slot it sees for the rest of the test; the replay's
    ///      cold-equivalent must rebuild the isolated cold call exactly, and a later "cold" call reads
    ///      as warm as the replay.
    function test_ColdEquivalentRebuildsTheColdCall() external {
        RepriceModelSink sink = new RepriceModelSink();
        RepriceModelCaller caller = new RepriceModelCaller{value: 10}(sink);
        address dead = address(uint160(0xDEAD0000DEAD));
        uint256 snap = vm.snapshotState();
        uint256 cold = this.measured(caller, dead);
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        uint256 replay = this.measured(caller, dead);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        assertTrue(vm.revertToState(snap));
        uint256 later = this.measured(caller, dead);
        assertLt(replay, cold, "the recorded replay reads warm");
        assertEq(later, replay, "a later cold call in the same test reads as warm as the replay");
        assertEq(GlamsterdamReprice.coldEquivalent(replay, acc, address(caller), address(this)), cold,
            "cold-equivalent of the replay");
    }
}
