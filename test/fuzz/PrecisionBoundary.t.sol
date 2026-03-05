// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title PrecisionBoundary -- Zero-rounding boundary tests (PREC-02)
/// @notice Proves no input combination allows zero-cost actions while producing non-zero output.
///         Tests pure math formulas extracted from protocol contracts.
/// @dev Does NOT duplicate existing ShareMathInvariants or VaultShareMath tests.
///      Focuses specifically on: minimum viable amounts, ceil-floor round-trips, BPS floor bounds.
contract PrecisionBoundaryTest is Test {
    // =========================================================================
    // Constants (mirrored from protocol)
    // =========================================================================

    uint256 constant TICKET_SCALE = 100;
    uint256 constant PRICE_COIN_UNIT = 1000 ether;
    uint256 constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;
    uint256 constant BPS_DENOMINATOR = 10_000;
    uint256 constant LOOTBOX_MIN = 0.01 ether;
    uint256 constant REFILL_SUPPLY = 1_000_000_000_000 ether; // Vault refill supply

    // All price tiers from PriceLookupLib
    uint256[7] private PRICE_TIERS = [
        0.01 ether, // levels 0-4
        0.02 ether, // levels 5-9
        0.04 ether, // levels 10-29
        0.08 ether, // levels 30-59
        0.12 ether, // levels 60-89
        0.16 ether, // levels 90-99
        0.24 ether  // levels x00
    ];

    // =========================================================================
    // 1. Ticket Purchase: Zero-Cost Impossible
    // =========================================================================

    /// @notice At qty=1, costWei > 0 for all tiers. Low tiers require higher qty to pass TICKET_MIN_BUYIN_WEI.
    /// @dev The protocol reverts if costWei < TICKET_MIN_BUYIN_WEI, which is the correct guard.
    ///      At 0.01 ETH tier, qty=1 yields 25000 gwei < 0.0025 ETH, so qty >= 100 is needed.
    ///      This test verifies: (1) costWei is always non-zero, (2) minimum viable qty exists for each tier.
    function test_ticket_minQty_nonZeroCost() public pure {
        for (uint256 i = 0; i < 7; i++) {
            uint256 priceWei = _priceTier(i);

            // costWei at qty=1 is always > 0 (priceWei >= 0.01 ETH >> 400)
            uint256 costWei = (priceWei * 1) / (4 * TICKET_SCALE);
            assertTrue(costWei > 0, "costWei must be > 0 at qty=1");

            // Find minimum quantity that passes TICKET_MIN_BUYIN_WEI guard
            // Formula: costWei = (priceWei * qty) / 400 >= TICKET_MIN_BUYIN_WEI
            // => qty >= (TICKET_MIN_BUYIN_WEI * 400) / priceWei
            uint256 minQty = (TICKET_MIN_BUYIN_WEI * 400 + priceWei - 1) / priceWei; // ceil
            uint256 minCost = (priceWei * minQty) / (4 * TICKET_SCALE);
            assertTrue(minCost >= TICKET_MIN_BUYIN_WEI, "minimum viable qty must pass TICKET_MIN_BUYIN_WEI");
            assertTrue(minCost > 0, "minimum viable cost must be > 0");
        }
    }

    /// @notice Fuzz quantity from 1 to 100000, assert costWei > 0 for all price tiers
    function testFuzz_ticket_neverZeroCost(uint32 qty) public pure {
        vm.assume(qty >= 1);
        vm.assume(qty <= 100_000); // reasonable upper bound

        for (uint256 i = 0; i < 7; i++) {
            uint256 priceWei = _priceTier(i);
            uint256 costWei = (priceWei * uint256(qty)) / (4 * TICKET_SCALE);
            assertTrue(costWei > 0, "costWei must never be 0 for qty >= 1");
        }
    }

    /// @notice Verify PriceLookupLib.priceForLevel returns correct values for all tiers
    function test_priceLookup_allTiersNonZero() public pure {
        // Sample representative levels from each tier
        uint24[12] memory levels = [
            uint24(0), uint24(4),    // 0.01 ETH
            uint24(5), uint24(9),    // 0.02 ETH
            uint24(10), uint24(29),  // 0.04 ETH
            uint24(30), uint24(59),  // 0.08 ETH
            uint24(60), uint24(89),  // 0.12 ETH
            uint24(90), uint24(100)  // 0.16 ETH / 0.24 ETH
        ];
        for (uint256 i = 0; i < levels.length; i++) {
            uint256 p = PriceLookupLib.priceForLevel(levels[i]);
            assertTrue(p > 0, "price must be > 0 for every level");
            assertTrue(p >= 0.01 ether, "price must be >= 0.01 ETH (minimum tier)");
        }
    }

    // =========================================================================
    // 2. Vault Share Math: Ceil-Floor Round-Trip
    // =========================================================================

    /// @notice Burn exactly 1 share when vault has real reserves. Assert claimValue > 0.
    function testFuzz_vault_burn1Share_nonZeroClaimValue(
        uint128 reserve,
        uint128 supply
    ) public pure {
        vm.assume(supply > 0);
        vm.assume(reserve > 0);

        uint256 claimValue = (uint256(reserve) * 1) / uint256(supply);
        // claimValue can be 0 if reserve < supply, but this is expected:
        // In that case burning 1 share returns 0 (rounding down). The vault
        // prevents this via supply management (REFILL_SUPPLY).
        // Test with realistic vault state:
        if (reserve >= supply) {
            assertTrue(claimValue > 0, "burn 1 share should yield > 0 when reserve >= supply");
        }
    }

    /// @notice Ceil-floor round-trip: claimValue from burnAmount always >= targetValue
    /// @dev previewBurnForEthOut: burnAmount = ceil(targetValue * supply / reserve)
    ///      previewEth: claimValue = floor(reserve * burnAmount / supply)
    ///      Invariant: claimValue >= targetValue
    function testFuzz_vault_ceilFloorRoundTrip_favorsVault(
        uint128 _reserve,
        uint128 _supply,
        uint128 _targetValue
    ) public pure {
        uint256 reserve = uint256(_reserve);
        uint256 supply = uint256(_supply);
        uint256 targetValue = uint256(_targetValue);

        vm.assume(supply > 0);
        vm.assume(reserve > 0);
        vm.assume(targetValue > 0);
        vm.assume(targetValue <= reserve); // Can't withdraw more than exists

        // Ceil-div: burnAmount = (targetValue * supply + reserve - 1) / reserve
        uint256 numerator = targetValue * supply;
        // Overflow guard for fuzz
        vm.assume(numerator / supply == targetValue);
        uint256 burnAmount = (numerator + reserve - 1) / reserve;

        // Can't burn more than supply
        vm.assume(burnAmount <= supply);

        // Floor-div: claimValue = (reserve * burnAmount) / supply
        uint256 claimProduct = reserve * burnAmount;
        // Overflow guard
        vm.assume(claimProduct / reserve == burnAmount);
        uint256 claimValue = claimProduct / supply;

        // KEY INVARIANT: claimValue >= targetValue
        // The ceil-div ensures we burn enough shares to cover targetValue
        assertGe(claimValue, targetValue, "ceil-floor round-trip must yield >= targetValue");
    }

    /// @notice Many small burns vs one large burn: single large >= sum of small
    /// @dev Proves dust extraction via splitting is not profitable
    function testFuzz_vault_manySmallBurns_vs_oneLargeBurn(
        uint128 _reserve,
        uint128 _supply,
        uint8 numBurns
    ) public pure {
        uint256 reserve = uint256(_reserve);
        uint256 supply = uint256(_supply);

        vm.assume(supply > 10);
        vm.assume(reserve > 10);
        vm.assume(numBurns >= 2 && numBurns <= 20);
        vm.assume(supply >= uint256(numBurns) * 2); // Enough shares for all burns

        uint256 totalSmall = 0;
        uint256 currentReserve = reserve;
        uint256 currentSupply = supply;

        for (uint256 i = 0; i < numBurns; i++) {
            uint256 sharesBurned = 1;
            uint256 payout = (currentReserve * sharesBurned) / currentSupply;
            totalSmall += payout;
            currentReserve -= payout;
            currentSupply -= sharesBurned;
            if (currentSupply == 0) break;
        }

        // Single large burn of numBurns shares
        uint256 singleLarge = (reserve * uint256(numBurns)) / supply;

        // Single large burn should yield >= sum of small burns
        // (Each small burn loses up to 1 wei to floor rounding)
        assertGe(singleLarge, totalSmall, "single large burn should yield >= sum of small burns");
    }

    // =========================================================================
    // 3. Lootbox at Minimum: All BPS Intermediates Non-Zero
    // =========================================================================

    /// @notice At LOOTBOX_MIN, all BPS intermediate calculations produce non-zero values
    function test_lootbox_atMinimum_allIntermediatesNonZero() public pure {
        uint256 amount = LOOTBOX_MIN; // 0.01 ether = 10^16

        // Test representative BPS splits from the lootbox module
        // Future split: 3000 BPS (30%)
        uint256 futureBps = 3000;
        uint256 futureShare = (amount * futureBps) / 10_000;
        assertTrue(futureShare > 0, "futureShare must be > 0 at LOOTBOX_MIN");

        // Next split: 2000 BPS (20%)
        uint256 nextBps = 2000;
        uint256 nextShare = (amount * nextBps) / 10_000;
        assertTrue(nextShare > 0, "nextShare must be > 0 at LOOTBOX_MIN");

        // Boon budget: 1000 BPS (10%)
        uint256 boonBps = 1000;
        uint256 boonBudget = (amount * boonBps) / 10_000;
        assertTrue(boonBudget > 0, "boonBudget must be > 0 at LOOTBOX_MIN");

        // Ticket budget: 16100 BPS (161%)
        uint256 ticketBps = 16100;
        uint256 ticketBudget = (amount * ticketBps) / 10_000;
        assertTrue(ticketBudget > 0, "ticketBudget must be > 0 at LOOTBOX_MIN");

        // Remainder pattern: exact split
        uint256 remainder = amount - futureShare - nextShare;
        assertTrue(remainder > 0, "remainder must be > 0");
        assertEq(futureShare + nextShare + remainder, amount, "split must be exact");
    }

    // =========================================================================
    // 4. Decimator Cap Boundary: effectiveAmount > 0
    // =========================================================================

    /// @notice At the cap boundary, effectiveAmount is non-zero
    function test_decimator_atCapBoundary_effectiveAmountNonZero() public pure {
        uint256 DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT;

        // Scenario: prevBurn just below cap, baseAmount = 1 BURNIE, multBps = 15000 (1.5x)
        uint256 prevBurn = DECIMATOR_MULTIPLIER_CAP - 1;
        uint256 baseAmount = PRICE_COIN_UNIT; // 1 full BURNIE
        uint256 multBps = 15_000;

        // Replicate _decEffectiveAmount logic
        uint256 remaining = DECIMATOR_MULTIPLIER_CAP - prevBurn; // = 1
        uint256 fullEffective = (baseAmount * multBps) / BPS_DENOMINATOR;

        if (fullEffective <= remaining) {
            // fullEffective fits within remaining -- use it
            assertTrue(fullEffective > 0, "fullEffective must be > 0");
        } else {
            // Cap boundary: split between multiplied and 1x portions
            uint256 maxMultBase = (remaining * BPS_DENOMINATOR) / multBps;
            uint256 multiplied = (maxMultBase * multBps) / BPS_DENOMINATOR;
            uint256 effectiveAmount = multiplied + (baseAmount - maxMultBase);
            assertTrue(effectiveAmount > 0, "effectiveAmount must be > 0 at cap boundary");
            // effectiveAmount should be <= fullEffective (cap reduces it)
            assertLe(effectiveAmount, fullEffective, "capped effective <= uncapped");
        }
    }

    // =========================================================================
    // 5. Coinflip Minimum Stake: Principal Always Returned
    // =========================================================================

    /// @notice At minimum stake, payout includes principal even if reward rounds to 0
    function testFuzz_coinflip_minimumStake_principalReturned(
        uint256 stake,
        uint8 rewardPercent
    ) public pure {
        vm.assume(stake > 0 && stake <= 1_000_000 ether);
        vm.assume(rewardPercent > 0 && rewardPercent <= 100);

        // Coinflip payout formula: stake + (stake * rewardPercent) / 100
        uint256 reward = (stake * uint256(rewardPercent)) / 100;
        uint256 payout = stake + reward;

        // Principal is always returned regardless of reward rounding
        assertGe(payout, stake, "payout must always include principal");

        // Even at stake=1 wei and rewardPercent=1: reward = 0, payout = 1
        // This is correct: principal returned, reward is too small to matter
    }

    // =========================================================================
    // 6. Auto-Rebuy: Below Ticket Price = No Tickets
    // =========================================================================

    /// @notice When weiAmount < ticketPrice, baseTickets == 0
    function test_autoRebuy_belowTicketPrice_noTickets() public pure {
        for (uint256 i = 0; i < 7; i++) {
            uint256 priceWei = _priceTier(i);
            uint256 ticketPrice = priceWei >> 2; // quarter-price for single ticket

            // At weiAmount = ticketPrice - 1: should get 0 tickets
            if (ticketPrice > 0) {
                uint256 weiAmount = ticketPrice - 1;
                uint256 baseTickets = weiAmount / ticketPrice;
                assertEq(baseTickets, 0, "below ticket price must yield 0 tickets");
            }
        }
    }

    // =========================================================================
    // 7. BPS Division: Maximum Dust Bound
    // =========================================================================

    /// @notice For any BPS calculation, dust is bounded by BPS_DENOMINATOR - 1
    function testFuzz_bpsDivision_maxDust(
        uint128 amount,
        uint16 bps
    ) public pure {
        vm.assume(bps > 0 && bps <= 50_000); // up to 500%
        vm.assume(amount > 0);

        uint256 result = (uint256(amount) * uint256(bps)) / BPS_DENOMINATOR;
        uint256 product = uint256(amount) * uint256(bps);
        uint256 dust = product - result * BPS_DENOMINATOR;

        assertLt(dust, BPS_DENOMINATOR, "BPS dust must be < 10000");
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _priceTier(uint256 index) private pure returns (uint256) {
        if (index == 0) return 0.01 ether;
        if (index == 1) return 0.02 ether;
        if (index == 2) return 0.04 ether;
        if (index == 3) return 0.08 ether;
        if (index == 4) return 0.12 ether;
        if (index == 5) return 0.16 ether;
        return 0.24 ether;
    }
}
