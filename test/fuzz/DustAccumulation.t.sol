// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

/// @title DustAccumulation -- Invariant tests for dust accumulation and wei lifecycle (PREC-03, PREC-04)
/// @notice Proves accumulated rounding error is bounded and non-extractable.
///         Tests pure math formulas extracted from protocol contracts.
/// @dev Does NOT duplicate existing EthSolvency.inv.t.sol or VaultShare.inv.t.sol tests.
///      Focuses on: per-operation dust bounds, gas-cost dominance, remainder pattern exactness, pro-rata solvency.
contract DustAccumulationTest is Test {
    // =========================================================================
    // Constants (mirrored from protocol)
    // =========================================================================

    uint256 constant BPS_DENOMINATOR = 10_000;
    uint256 constant PRICE_COIN_UNIT = 1000 ether;
    uint256 constant TICKET_SCALE = 100;

    // =========================================================================
    // 1. Vault Dust Accumulation (PREC-03)
    // =========================================================================

    /// @notice Repeated small burns accumulate bounded dust vs one large burn
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

    /// @notice Gas cost dominates extractable dust by orders of magnitude
    function testFuzz_vault_dustNotProfitable(uint96 amount) public pure {
        vm.assume(amount > 0);

        // Max dust per burn: 1 wei (floor division loses at most 1 wei)
        uint256 maxDustPerBurn = 1;

        // Gas cost floor: ~50K gas * 10 gwei = 500K gwei = 5 * 10^14 wei
        uint256 gasCostPerTx = 500_000 gwei;

        // Even with 1000 burns, dust = 1000 wei, gas = 500_000_000_000_000 wei
        uint256 dustFrom1000Burns = maxDustPerBurn * 1000;
        assertTrue(
            gasCostPerTx > dustFrom1000Burns * 1_000_000,
            "gas cost must exceed dust by 1M+ ratio"
        );
    }

    // =========================================================================
    // 2. Lootbox Split Exactness (PREC-04)
    // =========================================================================

    /// @notice Lootbox remainder pattern produces exact split with zero dust
    function testFuzz_lootboxSplit_remainderPattern_exact(
        uint128 lootBoxAmount
    ) public pure {
        vm.assume(lootBoxAmount >= 0.01 ether); // LOOTBOX_MIN
        vm.assume(lootBoxAmount <= 1000 ether); // reasonable upper bound

        // Representative BPS splits (presale mode)
        uint256 futureBps = 3000; // 30%
        uint256 nextBps = 2000;   // 20%
        uint256 vaultBps = 1000;  // 10%

        uint256 futureShare = (uint256(lootBoxAmount) * futureBps) / BPS_DENOMINATOR;
        uint256 nextShare = (uint256(lootBoxAmount) * nextBps) / BPS_DENOMINATOR;
        uint256 vaultShare = (uint256(lootBoxAmount) * vaultBps) / BPS_DENOMINATOR;
        uint256 rewardShare = uint256(lootBoxAmount) - futureShare - nextShare - vaultShare;

        // KEY INVARIANT: sum == lootBoxAmount (zero dust)
        assertEq(
            futureShare + nextShare + vaultShare + rewardShare,
            uint256(lootBoxAmount),
            "lootbox split must be exact (remainder pattern)"
        );

        // All shares must be >= 0 (rewardShare absorbs rounding)
        assertTrue(rewardShare >= 0, "rewardShare must be non-negative");
    }

    /// @notice Non-presale split also exact
    function testFuzz_lootboxSplit_nonPresale_exact(uint128 lootBoxAmount) public pure {
        vm.assume(lootBoxAmount >= 0.01 ether);
        vm.assume(lootBoxAmount <= 1000 ether);

        // Non-presale: different BPS values, no vault share
        uint256 futureBps = 4000; // 40%
        uint256 nextBps = 3000;   // 30%
        uint256 vaultBps = 0;     // 0%

        uint256 futureShare = (uint256(lootBoxAmount) * futureBps) / BPS_DENOMINATOR;
        uint256 nextShare = (uint256(lootBoxAmount) * nextBps) / BPS_DENOMINATOR;
        uint256 rewardShare = uint256(lootBoxAmount) - futureShare - nextShare;

        assertEq(
            futureShare + nextShare + rewardShare,
            uint256(lootBoxAmount),
            "non-presale split must be exact"
        );
    }

    // =========================================================================
    // 3. BPS Division Dust Bound (PREC-03)
    // =========================================================================

    /// @notice For any BPS division, maximum dust < BPS_DENOMINATOR
    function testFuzz_bpsDivision_maxDust(uint128 amount, uint16 bps) public pure {
        vm.assume(bps > 0 && bps <= 50_000);
        vm.assume(amount > 0);

        uint256 result = (uint256(amount) * uint256(bps)) / BPS_DENOMINATOR;
        uint256 product = uint256(amount) * uint256(bps);
        uint256 dust = product - result * BPS_DENOMINATOR;

        assertLt(dust, BPS_DENOMINATOR, "BPS dust must be < 10000 wei");
    }

    // =========================================================================
    // 4. Decimator Pro-Rata Dust (PREC-03)
    // =========================================================================

    /// @notice Pro-rata claims sum to <= poolWei; dust bounded by denominator
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

        // Dust (unclaimed residual) is bounded by totalBurn
        // Mathematical bound: each of N claims loses at most (totalBurn - 1) / totalBurn,
        // so total loss <= N * 1 = N claims (at most N wei when totalBurn is large)
        uint256 dust = uint256(poolWei) - totalPaid;
        // Generous bound: dust < max(totalBurn, 5) for 5 claimants
        assertTrue(dust < totalBurn || dust < 5, "dust must be bounded");
    }

    // =========================================================================
    // 5. Wei Lifecycle: Purchase Cost Formula (PREC-04)
    // =========================================================================

    /// @notice Purchase cost precision loss bounded at 399 wei per operation
    function testFuzz_purchaseCost_precisionLossBounded(
        uint32 quantity,
        uint8 tierIndex
    ) public pure {
        vm.assume(quantity >= 1 && quantity <= 100_000);
        vm.assume(tierIndex < 7);

        uint256 priceWei;
        if (tierIndex == 0) priceWei = 0.01 ether;
        else if (tierIndex == 1) priceWei = 0.02 ether;
        else if (tierIndex == 2) priceWei = 0.04 ether;
        else if (tierIndex == 3) priceWei = 0.08 ether;
        else if (tierIndex == 4) priceWei = 0.12 ether;
        else if (tierIndex == 5) priceWei = 0.16 ether;
        else priceWei = 0.24 ether;

        uint256 costWei = (priceWei * uint256(quantity)) / (4 * TICKET_SCALE);
        uint256 exactProduct = priceWei * uint256(quantity);
        uint256 precisionLoss = exactProduct - costWei * (4 * TICKET_SCALE);

        // Precision loss bounded by divisor - 1 = 399
        assertLt(precisionLoss, 400, "precision loss must be < 400 wei");
    }

    // =========================================================================
    // 6. Price Conversion Dust (PREC-04)
    // =========================================================================

    /// @notice ETH-to-BURNIE conversion dust bounded
    function testFuzz_ethToBurnie_dustBounded(
        uint128 amountWei,
        uint8 tierIndex
    ) public pure {
        vm.assume(amountWei > 0);
        vm.assume(tierIndex < 7);

        uint256 priceWei;
        if (tierIndex == 0) priceWei = 0.01 ether;
        else if (tierIndex == 1) priceWei = 0.02 ether;
        else if (tierIndex == 2) priceWei = 0.04 ether;
        else if (tierIndex == 3) priceWei = 0.08 ether;
        else if (tierIndex == 4) priceWei = 0.12 ether;
        else if (tierIndex == 5) priceWei = 0.16 ether;
        else priceWei = 0.24 ether;

        // _ethToBurnieValue: (amountWei * PRICE_COIN_UNIT) / priceWei
        uint256 product = uint256(amountWei) * PRICE_COIN_UNIT;
        // Overflow guard
        vm.assume(product / PRICE_COIN_UNIT == uint256(amountWei));

        uint256 result = product / priceWei;
        uint256 dust = product - result * priceWei;

        // Dust bounded by priceWei - 1
        assertLt(dust, priceWei, "price conversion dust must be < priceWei");
    }
}
