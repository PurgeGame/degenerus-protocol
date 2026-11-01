// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {HumanOrderGasSeed} from "./HumanOrderNativeGas.t.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev Forced-outcome atomic order execution on the complete deployment prestate.
/// Outcome forcing is confined to the separately compiled probe.
contract ForcedRedemptionEnvelopeGasTest is DeployProtocol {
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
            this.check(i, orders[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function check(uint256 shape, uint256 order) external {
        require(msg.sender == address(this), "fixture self-call");
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        host.seedOrder(PLAYER, order, 1);
        assertEq(host.rawAtomic(), 20, "the full twenty-box order executes");
        assertEq(host.entriesLeft(), 0, "the atomic cursor commits");
    }
}
