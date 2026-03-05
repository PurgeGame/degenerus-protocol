// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

/// @title Share-Based Payout Math Fuzz Tests
/// @notice Tests the core (reserve * amount) / supply formula used by DegenerusVault and DegenerusStonk.
/// @dev These formulas determine how much ETH/stETH/BURNIE a user receives when burning shares.
///      Key properties: no overflow, no division-by-zero, proportional fairness.
contract ShareMathInvariantsTest is Test {
    uint256 constant REFILL_SUPPLY = 1_000_000_000_000 ether; // 1T tokens

    /// @notice (reserve * amount) / supply never exceeds reserve
    function testFuzz_payoutNeverExceedsReserve(
        uint128 reserve,
        uint128 amount,
        uint128 supply
    ) public pure {
        vm.assume(supply > 0);
        vm.assume(amount <= supply);

        uint256 payout = (uint256(reserve) * uint256(amount)) / uint256(supply);
        assertLe(payout, uint256(reserve), "payout should never exceed total reserve");
    }

    /// @notice burning entire supply returns entire reserve (minus rounding)
    function testFuzz_burnAllReturnsAll(uint128 reserve, uint128 supply) public pure {
        vm.assume(supply > 0);
        vm.assume(reserve > 0);

        uint256 payout = (uint256(reserve) * uint256(supply)) / uint256(supply);
        assertEq(payout, uint256(reserve), "burning all shares should return all reserve");
    }

    /// @notice two users burning sequentially get <= total reserve
    function testFuzz_twoUsersSolvency(
        uint256 reserve,
        uint256 totalShares,
        uint256 userAShares
    ) public pure {
        vm.assume(totalShares > 1);
        vm.assume(totalShares <= 1_000_000_000_000 ether);
        vm.assume(userAShares > 0 && userAShares < totalShares);
        vm.assume(reserve > 0 && reserve <= 1_000_000 ether);

        uint256 userBShares = totalShares - userAShares;

        // User A burns first
        uint256 payoutA = (reserve * userAShares) / totalShares;
        uint256 remainingReserve = reserve - payoutA;
        uint256 remainingShares = totalShares - userAShares;

        // User B burns from remaining
        uint256 payoutB = (remainingReserve * userBShares) / remainingShares;

        // Total paid out should never exceed original reserve
        assertLe(payoutA + payoutB, reserve, "total payouts must not exceed reserve");

        // Rounding loss should be minimal (at most 1 wei per operation)
        assertLe(reserve - (payoutA + payoutB), 2, "rounding loss should be <= 2 wei");
    }

    /// @notice proportional fairness: user with 2x shares gets ~2x payout
    function testFuzz_proportionalFairness(uint256 reserve, uint256 totalShares) public pure {
        vm.assume(totalShares > 2);
        vm.assume(totalShares <= 1_000_000_000_000 ether);
        vm.assume(reserve > 100); // Avoid dust
        vm.assume(reserve <= 1_000_000 ether);

        uint256 smallShare = totalShares / 3;
        uint256 bigShare = smallShare * 2;

        uint256 smallPayout = (reserve * smallShare) / totalShares;
        uint256 bigPayout = (reserve * bigShare) / totalShares;

        // bigPayout should be roughly 2x smallPayout (within rounding)
        if (smallPayout > 0) {
            assertLe(bigPayout, smallPayout * 2 + 2, "big should be <= ~2x small");
            assertGe(bigPayout, smallPayout * 2 - 2, "big should be >= ~2x small");
        }
    }

    /// @notice ETH-preferential payout: ethOut + stethOut == claimValue
    function testFuzz_ethPreferentialSplit(
        uint256 claimValue,
        uint256 ethBal,
        uint256 stethBal
    ) public pure {
        vm.assume(claimValue > 0 && claimValue <= 1_000_000 ether);
        vm.assume(ethBal <= 1_000_000 ether);
        vm.assume(stethBal <= 1_000_000 ether);
        vm.assume(ethBal + stethBal >= claimValue);

        uint256 ethOut;
        uint256 stethOut;

        if (claimValue <= ethBal) {
            ethOut = claimValue;
            stethOut = 0;
        } else {
            ethOut = ethBal;
            stethOut = claimValue - ethOut;
        }

        assertEq(ethOut + stethOut, claimValue, "split must sum to claim value");
        assertLe(ethOut, ethBal, "ethOut must not exceed eth balance");
        assertLe(stethOut, stethBal, "stethOut must not exceed steth balance");
    }

    /// @notice refill mechanism: burning all shares then refilling keeps system consistent
    function testFuzz_refillMechanism(uint256 reserve, uint256 burnAmount) public pure {
        uint256 totalShares = REFILL_SUPPLY;
        vm.assume(burnAmount > 0 && burnAmount <= totalShares);
        vm.assume(reserve > 0 && reserve <= 1_000_000 ether);

        uint256 payout = (reserve * burnAmount) / totalShares;
        uint256 remainingReserve = reserve - payout;
        uint256 remainingShares = totalShares - burnAmount;

        if (remainingShares == 0) {
            // Full burn: refill with REFILL_SUPPLY
            remainingShares = REFILL_SUPPLY;
            // After refill, new burner should get proportional share of remaining reserve
            if (remainingReserve > 0) {
                uint256 newPayout = (remainingReserve * REFILL_SUPPLY) / REFILL_SUPPLY;
                assertEq(newPayout, remainingReserve, "refilled full burn should return all remaining");
            }
        }

        assertGt(remainingShares, 0, "shares should never be zero after refill");
    }

    /// @notice no overflow for realistic values
    function testFuzz_noOverflow(uint128 reserve, uint128 amount, uint128 supply) public pure {
        vm.assume(supply > 0);
        vm.assume(amount <= supply);

        // This should never overflow with uint128 inputs in uint256 math
        uint256 payout = (uint256(reserve) * uint256(amount)) / uint256(supply);
        assertLe(payout, uint256(reserve), "payout bounded by reserve");
    }
}
