// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DegenesisGasBase, DegenesisGasHost} from "./DegenesisGas.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenesisBoonReference as Ref} from "../fuzz/helpers/DegenesisBoonReference.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @notice Full production settlement call: dispatch, expiry, all deliveries, event, primary,
///         flush and close.
contract DegenesisBoonGasTest is DegenesisGasBase {
    uint32 private id;
    uint256 private q;

    function setUp() public {
        _deployProtocol();
        _etchHost();
        id = host.hostWallet(address(0xB008));
        q = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) / 3;
    }

    function testNativeFullThreeDrawChunkAndSeventhClose() public {
        uint256 n = 128;
        for (uint256 i; i < n; ++i) {
            uint32 recipient = host.hostWallet(address(uint160(0xC00800 + i)));
            host.hostOrder(7, i, recipient, 50_000, 0);
        }
        host.hostClosed(6);
        host.hostCohort(7, n * 50_000, n, true);
        host.hostActive(q, 9, 0);
        host.hostWord(275);
        bytes memory input = abi.encodeCall(DegenesisGasHost.hostRun, (type(uint128).max));
        _cool();
        vm.recordLogs();
        (bool ok, bytes memory output) = address(host).call(input);
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bool progressed, bool done, uint256 basis) = abi.decode(output, (bool, bool, uint256));
        assertTrue(progressed && done, "full cohort completes");
        assertEq(basis, n, "one reward per order");
        uint256 companions;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("DegenesisBoonsRolled(uint32,uint8,uint32,uint24)")) continue;
            (uint8 day, uint32 index, uint24 types_) = abi.decode(logs[i].data, (uint8, uint32, uint24));
            assertEq(day, 7);
            assertEq(index, companions);
            assertEq(types_, Ref.selected(5 ether, Ref.root(275, 7, index)));
            assertEq(Ref.packedCount(types_), 3);
            ++companions;
        }
        assertEq(companions, n);
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), 0, "seventh close burns inventory");
    }
}
