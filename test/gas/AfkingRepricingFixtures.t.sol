// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {SubscriberNativeGasHost} from "./SubscriberAfkingNativeGas.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

contract AfkingRepricingHost is SubscriberNativeGasHost {
    function protocolMembers() external {
        for (uint256 i; i < 2; ++i) {
            uint32 id = _seedWallet(i == 0 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS);
            _seedSubscriber(id, false);
            Sub storage sub = _subOf[id];
            sub.flags = 0;
            sub.dailyQuantity = i == 0 ? 0 : 1;
            sub.lastAutoBoughtDay = dailyIdx;
            sub.lastOpenedDay = dailyIdx;
        }
    }
    function moreOpenMembers(uint256 boxes, uint256 tickets) external {
        for (uint256 i; i < boxes + tickets; ++i) {
            bool ticket = i < tickets;
            uint32 id = _seedWallet(address(uint160(0x900000 + i)));
            _seedSubscriber(id, ticket);
            Sub storage sub = _subOf[id];
            sub.dailyQuantity = 1;
            sub.flags = ticket ? 4 : 0;
            sub.amount = 10;
            sub.score = 305;
            sub.lastAutoBoughtDay = dailyIdx;
            sub.lastOpenedDay = ticket ? dailyIdx : dailyIdx - 1;
            if (!ticket) ++_pendingBoxCount;
        }
    }
}

/// @dev Opt-in export of initialized protocol states for read-only Geth replay. The export
///      restores the actual Game runtime: public mineFlip and all dependencies are production
///      bytecode, except the same explicit VRF/stETH/LINK/feed mocks as the integration suite.
contract AfkingRepricingFixturesTest is DeployProtocol {
    function test_ExportRepricingFixtures() public {
        string memory directory = vm.envOr("AFKING_REPRICING_STATE_DIR", string(""));
        if (bytes(directory).length == 0) return;
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.deal(address(game), 50_000 ether);
        bytes memory gameCode = address(game).code;
        uint256 snapshot = vm.snapshotState();
        vm.etch(address(game), type(AfkingRepricingHost).runtimeCode);
        AfkingRepricingHost host = AfkingRepricingHost(payable(address(game)));
        host.prepare(false);
        host.protocolMembers();
        // Maximum quantity, alternating box/ticket input order. Processing must still buy boxes first.
        for (uint256 i; i < 16; ++i) host.add(address(uint160(0x700000 + i)), i & 1 == 0 ? 5 : 0);
        vm.etch(address(game), gameCode);
        _export(directory, "buy", 18);
        assertTrue(vm.revertToState(snapshot));

        snapshot = vm.snapshotState();
        vm.etch(address(game), type(AfkingRepricingHost).runtimeCode);
        host.openFixture(address(0x800000), 0xC0FFEE);
        host.protocolMembers();
        vm.etch(address(game), gameCode);
        _export(directory, "open-max", 3);
        assertTrue(vm.revertToState(snapshot));

        vm.etch(address(game), type(AfkingRepricingHost).runtimeCode);
        host.openFixture(address(0x800000), 0xC0FFEE);
        host.protocolMembers();
        host.moreOpenMembers(13, 1984);
        vm.etch(address(game), gameCode);
        _export(directory, "open-mixed-cap", 2000);
    }

    function _export(string memory directory, string memory name, uint256 members) private {
        string memory prefix = string.concat(directory, "/", name);
        vm.dumpState(string.concat(prefix, ".json"));
        string memory metadata = string.concat(
            '{"game":"', vm.toString(address(game)), '","timestamp":', vm.toString(block.timestamp),
            ',"members":', vm.toString(members), ',"name":"', name, '"}'
        );
        vm.writeJson(metadata, string.concat(prefix, ".meta.json"));
    }
}
