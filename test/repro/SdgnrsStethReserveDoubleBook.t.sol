// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @notice Terminal stETH custody covers every outstanding reserve while a batch remains unsettled.
///         Live batches price on Game backing only; custody turns into stETH before the
///         terminal claims (as the final sweep can leave it).
contract SdgnrsStethReserveDoubleBook is RedemptionFixture {
    function _pair(bool reverse) internal {
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n); _burn(bob, n);
        uint32 id = _resolveLive(175);
        uint256 a = _claimBase(alice, id) * 175 / 100;
        uint256 b = _claimBase(bob, id) * 175 / 100;
        assertGt(a, 0, "live batch priced on Game backing");
        // The final sweep leaves custody as stETH: nothing remains in the Game for sDGNRS.
        GameFunding.setReserve(0);
        GameFunding.setClaimable(2, 1);
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
        GameFunding.credit(2, 10_000 ether);
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n);
        uint32 first = _resolveLive(100);
        uint256 rolled = _claimBase(alice, first);
        assertGt(rolled, 0);
        uint256 backing = _money();
        uint256 credit = game.claimableWinningsOf(alice);
        uint256 reserveBefore = game.redemptionReserve();
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(_claimTokens(alice, first), 0);
        assertGt(game.claimableWinningsOf(alice), credit, "the claim is paid");
        assertLt(game.redemptionReserve(), reserveBefore, "the paid claim left the Game reserve");
        assertApproxEqAbs(_money(), backing, 1 gwei, "payment leaves the rest of the backing intact");
        uint256 expected = (_money() * n / sdgnrs.totalSupply() / 1 gwei) * 1 gwei;
        _burn(bob, n);
        uint32 second = _resolveLive(100);
        assertEq(_claimBase(bob, second), expected);
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
}
