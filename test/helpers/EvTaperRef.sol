// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @dev Independent reference for the lootbox EV allowance taper: marginal weight 1 to 10 ETH,
///      1 -> 1/2 over 10..20 ETH, 1/2 -> 0 over 20..40 ETH. Integrates exactly in integers and
///      floors once, where the contract floors per segment, so the contract result is at most
///      this value and at least this value minus 2.
library EvTaperRef {
    /// @dev 80e18 x the integral of the weight over [0, x], exact.
    function weightIntegral80(uint256 x) internal pure returns (uint256) {
        if (x <= 10 ether) return 80 ether * x;
        if (x <= 20 ether) return 800 ether * 1 ether + 2 * (400 ether * 1 ether - (30 ether - x) ** 2);
        if (x > 40 ether) x = 40 ether;
        return 1400 ether * 1 ether + (400 ether * 1 ether - (40 ether - x) ** 2);
    }

    /// @dev Weighted eligible share of `spend` starting `used` in, and the clamped usage after.
    function eligible(uint256 used, uint256 spend) internal pure returns (uint256 amount, uint256 usedAfter) {
        if (used >= 40 ether) return (0, used);
        usedAfter = used + spend > 40 ether ? 40 ether : used + spend;
        amount = (weightIntegral80(usedAfter) - weightIntegral80(used)) / 80 ether;
    }
}
