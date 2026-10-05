// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";

/// @notice Defensive reserve saturation under deliberately corrupted storage.
/// Real closes reserve the maximum; these cases prove terminal resolution cannot underflow.
contract DegradeRedemptionResolveTest is RedemptionFixture {
    function _seed(uint96 reserve) private {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _closeAsGame();
        uint256 packed = uint256(vm.load(address(sdgnrs), bytes32(0)));
        uint256 mask = uint256(type(uint96).max) << 128;
        vm.store(address(sdgnrs), bytes32(0), bytes32((packed & ~mask) | (uint256(reserve) << 128)));
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserve);
    }
    function _resolve() private { vm.prank(address(game)); sdgnrs.resolveTerminalRedemptions(); }
    function test_ReservationBelowMaxShareSaturates() public {
        _seed(1 ether);
        uint256 eth = address(sdgnrs).balance;
        _resolve();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 10 ether);
        assertEq(_rollOf(1), 100);
        assertEq(address(sdgnrs).balance, eth);
    }
    function test_ReachableReleaseUnchanged() public {
        _seed(20.5 ether); _resolve();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 13 ether, "other batch reserve retained");
    }
    function test_SecondResolveIsNoOp() public {
        _seed(1 ether); _resolve(); _resolve();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 10 ether);
        assertEq(_rollOf(1), 100);
    }
}
