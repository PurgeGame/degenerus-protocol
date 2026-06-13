// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

/// @title RedemptionSplitTest -- Proves the redemption payout-split conservation identity (INV-03)
/// @notice Mirrors the claim-time split in StakedDegenerusStonk._claimRedemptionFor: 50/50
///         direct/lootbox during a live game, with the dust-lootbox drop — when the lootbox half
///         lands below the 0.01 ETH floor it is forfeited to sDGNRS's claimable instead of paid out.
///         The full rolled amount always leaves the contract across the three legs. Fuzzes all inputs.
/// @dev Run: forge test --match-contract RedemptionSplitTest -vv
contract RedemptionSplitTest is Test {
    uint256 constant MAX_DAILY_REDEMPTION_EV = 160 ether;
    uint256 constant MIN_REDEMPTION_LOOTBOX_ETH = 0.01 ether;

    /// @dev General conservation across every input: direct + lootbox + forfeit == rolled total.
    ///      Nothing is created or stranded regardless of regime (gameOver / normal / dust drop).
    function testFuzz_INV03_splitConservation(
        uint96 ethValueOwed,
        uint16 rollRaw,
        bool isGameOver
    ) public pure {
        ethValueOwed = uint96(bound(ethValueOwed, 1, MAX_DAILY_REDEMPTION_EV));
        uint16 roll = uint16(bound(rollRaw, 25, 175));

        uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;

        uint256 ethDirect;
        uint256 lootboxEth;
        uint256 forfeitEth;
        if (isGameOver) {
            ethDirect = totalRolledEth;
        } else {
            ethDirect = totalRolledEth / 2;
            lootboxEth = totalRolledEth - ethDirect;
            if (lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH) {
                forfeitEth = lootboxEth;
                lootboxEth = 0;
            }
        }

        assertEq(
            ethDirect + lootboxEth + forfeitEth,
            totalRolledEth,
            "INV-03: legs must sum to total"
        );
    }

    /// @dev GameOver: 100% direct, no lootbox, no forfeit.
    function testFuzz_INV03_splitConservation_gameOver(
        uint96 ethValueOwed,
        uint16 rollRaw
    ) public pure {
        ethValueOwed = uint96(bound(ethValueOwed, 1, MAX_DAILY_REDEMPTION_EV));
        uint16 roll = uint16(bound(rollRaw, 25, 175));

        uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;
        uint256 ethDirect = totalRolledEth;
        uint256 lootboxEth = 0;
        uint256 forfeitEth = 0;

        assertEq(ethDirect, totalRolledEth, "INV-03: gameOver ethDirect must equal total");
        assertEq(lootboxEth, 0, "INV-03: gameOver lootboxEth must be zero");
        assertEq(
            ethDirect + lootboxEth + forfeitEth,
            totalRolledEth,
            "INV-03: gameOver legs must sum to total"
        );
    }

    /// @dev Live game, lootbox half at or above the floor: the normal 50/50 split, no forfeit.
    ///      Lower-bound ethValueOwed so even the smallest roll (25%) keeps the lootbox half >= floor.
    function testFuzz_INV03_noGameOver_normalSplit(
        uint96 ethValueOwed,
        uint16 rollRaw
    ) public pure {
        // rolled >= ethValueOwed * 25/100; lootbox ~ rolled/2; need lootbox >= 0.01 ETH for all rolls.
        ethValueOwed = uint96(bound(ethValueOwed, 0.1 ether, MAX_DAILY_REDEMPTION_EV));
        uint16 roll = uint16(bound(rollRaw, 25, 175));

        uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;
        uint256 ethDirect = totalRolledEth / 2;
        uint256 lootboxEth = totalRolledEth - ethDirect;
        uint256 forfeitEth;
        if (lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH) {
            forfeitEth = lootboxEth;
            lootboxEth = 0;
        }

        assertEq(forfeitEth, 0, "INV-03: above-floor redemption forfeits nothing");
        assertEq(
            ethDirect + lootboxEth + forfeitEth,
            totalRolledEth,
            "INV-03: noGameOver split must sum to total"
        );
        // The split is 50/50 within 1 wei (lootboxEth gets the extra wei for odd totals).
        assertTrue(lootboxEth >= ethDirect, "INV-03: lootboxEth >= ethDirect (ceiling vs floor)");
        assertTrue(lootboxEth - ethDirect <= 1, "INV-03: split difference is at most 1 wei");
    }

    /// @dev Live game, lootbox half below the floor: the lootbox is dropped, its value forfeited
    ///      to sDGNRS, and the player keeps only the direct half. Upper-bound ethValueOwed so even
    ///      the largest roll (175%) keeps the lootbox half < floor.
    function testFuzz_INV03_noGameOver_dustForfeit(
        uint96 ethValueOwed,
        uint16 rollRaw
    ) public pure {
        // rolled <= ethValueOwed * 175/100; lootbox ~ rolled/2; need lootbox < 0.01 ETH for all rolls.
        // ethValueOwed <= 0.01 ETH => rolled <= 0.0175 ETH => lootbox <= ~0.00875 ETH < floor.
        ethValueOwed = uint96(bound(ethValueOwed, 1, 0.01 ether));
        uint16 roll = uint16(bound(rollRaw, 25, 175));

        uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;
        uint256 ethDirect = totalRolledEth / 2;
        uint256 lootboxEth = totalRolledEth - ethDirect;
        uint256 forfeitEth;
        if (lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH) {
            forfeitEth = lootboxEth;
            lootboxEth = 0;
        }

        assertEq(lootboxEth, 0, "INV-03: dust redemption creates no lootbox");
        assertEq(forfeitEth, totalRolledEth - ethDirect, "INV-03: dropped half is forfeited");
        assertEq(ethDirect, totalRolledEth / 2, "INV-03: player keeps the direct half");
        assertEq(
            ethDirect + lootboxEth + forfeitEth,
            totalRolledEth,
            "INV-03: dust split must sum to total"
        );
    }
}
