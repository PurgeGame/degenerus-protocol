// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameDegenesisModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";

contract OptCalldataObserver {
    event Routed(bytes input, address sender, uint256 value);
    fallback() external payable { emit Routed(msg.data, msg.sender, msg.value); }
}

contract OptCalldataRoutingTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.etch(ContractAddresses.GAME_DEGENESIS_MODULE, address(new OptCalldataObserver()).code);
    }

    function testFuzz_RoutePreservesArgumentsCallerValue(uint32 id, uint256 amount, bytes32 tail) public {
        bytes4 original = game.buyDegenesisBox.selector;
        bytes memory arguments = abi.encode(id, amount, tail);
        address caller = address(0xCA11);
        vm.deal(caller, 1 ether);
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory output) = address(game).call{value: 1 ether}(bytes.concat(original, arguments));
        assertTrue(ok);
        assertEq(output.length, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(game));
        assertEq(logs[0].topics[0], keccak256("Routed(bytes,address,uint256)"));
        assertEq(logs[0].data, abi.encode(bytes.concat(IDegenerusGameDegenesisModule.buyDegenesisBox_g1442.selector, abi.encode(id, amount)), caller, uint256(1 ether)));
    }

    function test_InvalidAbiIsRejectedBeforeDelegate() public {
        bytes4[1] memory selectors = [game.buyDegenesisBox.selector];
        for (uint256 i; i < selectors.length; ++i) {
            (bool shortOk, bytes memory shortReason) = address(game).call(bytes.concat(selectors[i], abi.encode(uint32(1))));
            assertFalse(shortOk); assertEq(shortReason.length, 0);
            (bool dirtyOk, bytes memory dirtyReason) = address(game).call(bytes.concat(selectors[i], abi.encode(uint256(1) << 32, uint256(0))));
            assertFalse(dirtyOk); assertEq(dirtyReason.length, 0);
        }
    }

    function test_UnusedFacadeAliasIsRemoved() public {
        vm.recordLogs();
        (bool ok,) = address(game).call(abi.encodeWithSelector(
            bytes4(keccak256("buyDegenesisBox_g1442(uint32,uint256)")), uint32(0), uint256(0)));
        assertFalse(ok);
        assertEq(vm.getRecordedLogs().length, 0);
    }
}
