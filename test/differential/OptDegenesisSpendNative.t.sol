// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisVaultSpend} from "../fuzz/DegenesisVaultSpend.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";

/// @dev Reuse the funded, real seven-day-sale fixture and its independent accounting tests.
contract OptDegenesisSpendNative is DegenesisVaultSpend, NativeGasExport {
    function testNativeSpendTickets() public { _exportSpend("opt-spend-tickets", false, 4000, 0); }
    function testNativeSpendWhale() public { _exportSpend("opt-spend-whale", true, 1, 0); }

    function _exportSpend(string memory label, bool whale, uint256 quantity, uint256 boxOrder) private {
        _nativeFixture(label, address(vault), address(game),
            abi.encodeCall(game.spendDegenesis, (uint32(0), whale, quantity, boxOrder, budget)));
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        if (bytes(dir).length != 0) {
            vm.writeJson(vm.toString(block.number), string.concat(dir, "/", label, ".call.json"), ".number");
        }
    }
}
