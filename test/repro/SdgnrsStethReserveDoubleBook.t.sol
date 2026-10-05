// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";

/// @notice stETH custody covers every outstanding reserve, including parked older batches.
contract SdgnrsStethReserveDoubleBook is RedemptionFixture {
    function _pair(bool reverse) internal {
        vm.deal(address(sdgnrs), 0);
        mockStETH.mint(address(sdgnrs), 10_000 ether);
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n); _burn(bob, n);
        uint32 id = _resolveLive(175);
        uint256 a = _claimBase(alice, id) * 175 / 100;
        uint256 b = _claimBase(bob, id) * 175 / 100;
        _terminalize();
        address first = reverse ? bob : alice;
        address second = reverse ? alice : bob;
        vm.prank(first); sdgnrs.claimRedemption(first, id);
        assertGe(mockStETH.balanceOf(address(sdgnrs)), sdgnrs.pendingRedemptionEthValue());
        vm.prank(second); sdgnrs.claimRedemption(second, id);
        assertEq(mockStETH.balanceOf(alice), a);
        assertEq(mockStETH.balanceOf(bob), b);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_bothClaimantsPaid_claimOrderXY() public { _pair(false); }
    function test_bothClaimantsPaid_claimOrderYX() public { _pair(true); }
    function test_ParkedReserveIsExcludedFromNextBatchBacking() public {
        vm.deal(address(sdgnrs), 0);
        mockStETH.mint(address(sdgnrs), 10_000 ether);
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n);
        uint32 first = _resolveLive(175);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"12345678");
        assertTrue(_work(9_000_000));
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        assertGt(reserved, 0);
        vm.clearMockedCalls();
        uint256 holderBase = sdgnrs.totalSupply();
        uint256 expected = ((10_000 ether - reserved) * n / holderBase / 1 gwei) * 1 gwei;
        _burn(bob, n);
        uint32 second = _resolveLive(175);
        assertEq(_claimBase(bob, second), expected);
        assertGe(mockStETH.balanceOf(address(sdgnrs)), sdgnrs.pendingRedemptionEthValue());
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved);
        vm.prank(alice); sdgnrs.claimParkedRedemption(alice, first);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
}
