// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";

/// @notice Terminal stETH custody covers every outstanding reserve while a batch remains unsettled.
///         Live batches price on ETH and Game backing; custody turns into stETH before the
///         terminal claims (as the final sweep can leave it).
contract SdgnrsStethReserveDoubleBook is RedemptionFixture {
    function _pair(bool reverse) internal {
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n); _burn(bob, n);
        uint32 id = _resolveLive(175);
        uint256 a = _claimBase(alice, id) * 175 / 100;
        uint256 b = _claimBase(bob, id) * 175 / 100;
        assertGt(a, 0, "live batch priced on ETH custody");
        vm.deal(address(sdgnrs), 0);
        mockStETH.mint(address(sdgnrs), 10_000 ether);
        _terminalize();
        address first = reverse ? bob : alice;
        address second = reverse ? alice : bob;
        vm.prank(first); sdgnrs.claimRedemption(0, id);
        assertGe(mockStETH.balanceOf(address(sdgnrs)), sdgnrs.pendingRedemptionEthValue());
        vm.prank(second); sdgnrs.claimRedemption(0, id);
        assertEq(mockStETH.balanceOf(alice), a);
        assertEq(mockStETH.balanceOf(bob), b);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_bothClaimantsPaid_claimOrderXY() public { _pair(false); }
    function test_bothClaimantsPaid_claimOrderYX() public { _pair(true); }
    /// @dev A settled batch leaves its unrolled maximum and rounding dust in backing: the next
    ///      batch prices on everything the paid claim did not take.
    function test_UnrolledExcessAndDustReturnToNextBatchBacking() public {
        vm.deal(address(sdgnrs), 10_000 ether);
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n);
        uint32 first = _resolveLive(100);
        uint256 rolled = _claimBase(alice, first);
        assertGt(rolled, 0);
        uint256 backing = _money();
        uint256 credit = game.claimableWinningsOf(alice);
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(_claimTokens(alice, first), 0);
        assertGt(game.claimableWinningsOf(alice), credit, "the claim is paid");
        assertLt(address(sdgnrs).balance, 10_000 ether, "the paid claim left custody");
        assertApproxEqAbs(_money(), backing, 1 gwei, "payment leaves the rest of the backing intact");
        uint256 expected = (_money() * n / sdgnrs.totalSupply() / 1 gwei) * 1 gwei;
        _burn(bob, n);
        uint32 second = _resolveLive(100);
        assertEq(_claimBase(bob, second), expected);
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
}
