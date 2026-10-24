// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {HumanOrderGasSeed} from "./HumanOrderNativeGas.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev Export the complete deployment prestate for the original G7 forced-outcome
/// calibration. Outcome forcing is confined to the separately compiled native probe.
contract ForcedRedemptionEnvelopeGasTest is DeployProtocol, NativeGasExport {
    address private constant PLAYER = address(0xB0A20);

    function setUp() public {
        _deployProtocol(false);
        vm.deal(address(game), 50_000 ether);
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
    }

    function test_CompleteTwentyBoxCalibrationPrestates() public {
        uint256[4] memory orders = [BoxOrderLib.boSmalls(20), BoxOrderLib.boLarges(20),
            BoxOrderLib.boCustoms(20, 10 ether), BoxOrderLib.boCustoms(20, 2_000 ether)];
        for (uint256 i; i < orders.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            this.checkAndExport(i, orders[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function checkAndExport(uint256 shape, uint256 order) external {
        require(msg.sender == address(this), "fixture self-call");
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        host.seedOrder(PLAYER, order, 1);
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        if (bytes(dir).length != 0) {
            // Materialize the actual constructor-backed roots before the first
            // isolated world dump; no synthetic balances or slots are inferred.
            for (uint256 i; i <= GameSlots.DEGENERETTE_QUEUE + 1; ++i) {
                bytes32 slot = bytes32(i);
                vm.store(address(host), slot, vm.load(address(host), slot));
            }
            address[9] memory accounts = [address(coinflip), address(coin), address(sdgnrs),
                address(wwxrp), address(crapsBattle), address(vault), address(gnrus),
                ContractAddresses.RECORD_BOUNTY, ContractAddresses.DEITY_PASS];
            for (uint256 a; a < accounts.length; ++a) {
                vm.etch(accounts[a], accounts[a].code);
                for (uint256 i; i < 32; ++i) {
                    bytes32 slot = bytes32(i);
                    vm.store(accounts[a], slot, vm.load(accounts[a], slot));
                }
            }
            string memory label = string.concat("redemption-forced-prestate-", vm.toString(shape));
            vm.dumpState(string.concat(dir, "/", label, ".complete.json"));
            this.exportNativeFixture(label, address(this), address(host), abi.encodeCall(host.rawAtomic, ()));
        }
        assertEq(host.rawAtomic(), 20, "the full twenty-box order executes");
        assertEq(host.entriesLeft(), 0, "the atomic cursor commits");
    }
}
