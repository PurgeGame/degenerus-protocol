// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

/// @notice Arithmetic models for sequential rounding and pro-rata distributions.
/// @dev These isolate mathematical bounds; they do not execute production code.
///      Real vault payouts are exercised by ShareMathInvariants and VaultShareMath.
contract DustAccumulationTest is Test {
    function testFuzz_vault_repeatedSmallBurns_dustBounded(
        uint8 numBurns,
        uint96 shareAmount
    ) public pure {
        vm.assume(numBurns >= 2 && numBurns <= 50);
        vm.assume(shareAmount > 0 && shareAmount <= 1e18);

        // Realistic vault state: 100 ETH reserve, 1T supply (post-refill)
        uint256 reserve = 100 ether;
        uint256 supply = 1_000_000_000_000 ether;

        uint256 totalShares = uint256(numBurns) * uint256(shareAmount);
        vm.assume(totalShares <= supply / 2); // Don't burn more than half

        // Sequential small burns
        uint256 sumSmallBurns = 0;
        uint256 currentReserve = reserve;
        uint256 currentSupply = supply;

        for (uint256 i = 0; i < numBurns; i++) {
            uint256 payout = (currentReserve * uint256(shareAmount)) / currentSupply;
            sumSmallBurns += payout;
            currentReserve -= payout;
            currentSupply -= uint256(shareAmount);
        }

        // Single large burn of same total shares
        uint256 singleBurn = (reserve * totalShares) / supply;

        // Dust = difference between single large and sum of small
        uint256 dust = singleBurn > sumSmallBurns ? singleBurn - sumSmallBurns : 0;

        // Dust bounded: at most 1 wei per operation (from floor rounding)
        assertLe(dust, uint256(numBurns), "dust should be <= numBurns wei");
    }

    function testFuzz_proRata_sumBounded(
        uint128 poolWei,
        uint64 burn0,
        uint64 burn1,
        uint64 burn2,
        uint64 burn3,
        uint64 burn4
    ) public pure {
        vm.assume(poolWei > 0);

        uint256[5] memory burns = [uint256(burn0), uint256(burn1), uint256(burn2), uint256(burn3), uint256(burn4)];

        uint256 totalBurn = 0;
        for (uint256 i = 0; i < 5; i++) {
            totalBurn += burns[i];
        }
        vm.assume(totalBurn > 0);

        uint256 totalPaid = 0;
        for (uint256 i = 0; i < 5; i++) {
            if (burns[i] > 0) {
                uint256 share = (uint256(poolWei) * burns[i]) / totalBurn;
                totalPaid += share;
            }
        }

        // Sum of pro-rata claims must not exceed pool
        assertLe(totalPaid, uint256(poolWei), "pro-rata claims must not exceed pool");

        // Each of five floor-rounded claims loses less than one wei.
        assertLt(uint256(poolWei) - totalPaid, 5, "five claims lose less than five wei");
    }
}
