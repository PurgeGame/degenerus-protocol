// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The previous facade dispatcher, with the original authorization and
///      return/revert forwarding. Both sides use the same production boon module.
contract CustomerBoonReferenceFacade {
    error Unauthorized();
    function consumeCoinflipBoon(address) external returns (uint16) {
        if (msg.sender != ContractAddresses.COIN && msg.sender != ContractAddresses.COINFLIP
            && msg.sender != ContractAddresses.WWXRP) revert Unauthorized();
        (bool ok, bytes memory data) = ContractAddresses.GAME_BOON_MODULE.delegatecall(msg.data);
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint16));
    }
    function consumeDecimatorBoon(address player) external returns (uint16) {
        if (msg.sender != ContractAddresses.COIN) revert Unauthorized();
        (bool ok, bytes memory data) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
            abi.encodeWithSignature("consumeDecimatorBoost(address)", player)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint16));
    }

}

contract CustomerBoonDispatchTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }

    function _run(address caller, address player, bytes32 slot) private returns (bytes32) {
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory data) = address(game).call(abi.encodeCall(game.consumeCoinflipBoon, (player)));
        return keccak256(abi.encode(ok, data, vm.getRecordedLogs(), vm.load(address(game), slot),
            vm.load(address(game), bytes32(uint256(slot) + 1))));
    }

    function testFuzz_DispatchPreservesLaneExpiryEventsAndAuthorization(
        uint256 slot0, uint256 slot1, uint8 callerSeed, bool zeroPlayer
    ) public {
        address player = zeroPlayer ? address(0) : address(0xA11CE);
        address[4] memory callers = [ContractAddresses.COIN, ContractAddresses.COINFLIP,
            ContractAddresses.WWXRP, address(0xBAD)];
        address caller = callers[callerSeed % 4];
        bytes32 slot = keccak256(abi.encode(player, uint256(50)));
        vm.store(address(game), slot, bytes32(slot0));
        vm.store(address(game), bytes32(uint256(slot) + 1), bytes32(slot1));
        uint256 snap = vm.snapshotState();
        vm.etch(address(game), type(CustomerBoonReferenceFacade).runtimeCode);
        bytes32 expected = _run(caller, player, slot);
        assertTrue(vm.revertToState(snap));
        assertEq(_run(caller, player, slot), expected);
    }
    function _decimator(address caller, address player, bytes32 slot) private returns (bytes32) {
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory data) = address(game).call(abi.encodeCall(game.consumeDecimatorBoon, (player)));
        return keccak256(abi.encode(ok, data, vm.getRecordedLogs(), vm.load(address(game), slot),
            vm.load(address(game), bytes32(uint256(slot) + 1))));
    }

    function testFuzz_DecimatorDispatchPreservesExpiryEventsAndAuthorization(
        uint256 slot0, uint256 slot1, uint8 callerSeed, bool zeroPlayer, bool emptyTier
    ) public {
        address player = zeroPlayer ? address(0) : address(0xA11CE);
        address[4] memory callers = [ContractAddresses.COIN, ContractAddresses.COINFLIP,
            ContractAddresses.WWXRP, address(0xBAD)];
        address caller = callers[callerSeed % 4];
        if (emptyTier) slot0 &= ~(uint256(255) << 168);
        bytes32 slot = keccak256(abi.encode(player, uint256(50)));
        vm.store(address(game), slot, bytes32(slot0));
        vm.store(address(game), bytes32(uint256(slot) + 1), bytes32(slot1));
        uint256 snap = vm.snapshotState();
        vm.etch(address(game), type(CustomerBoonReferenceFacade).runtimeCode);
        bytes32 expected = _decimator(caller, player, slot);
        assertTrue(vm.revertToState(snap));
        assertEq(_decimator(caller, player, slot), expected);
    }

}
