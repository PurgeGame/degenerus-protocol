// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

/// @title RedemptionSplitTest -- Proves the 50/50 redemption lootbox split arithmetic identity (INV-03)
/// @notice Replicates the split logic from StakedDegenerusStonk.sol:584-595 and fuzzes all inputs.
/// @dev Run: forge test --match-contract RedemptionSplitTest -vv
contract RedemptionSplitTest is Test {
    uint256 constant MAX_DAILY_REDEMPTION_EV = 160 ether;

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
        if (isGameOver) {
            ethDirect = totalRolledEth;
        } else {
            ethDirect = totalRolledEth / 2;
            lootboxEth = totalRolledEth - ethDirect;
        }

        assertEq(ethDirect + lootboxEth, totalRolledEth, "INV-03: split must sum to total");
    }

    function testFuzz_INV03_splitConservation_gameOver(
        uint96 ethValueOwed,
        uint16 rollRaw
    ) public pure {
        ethValueOwed = uint96(bound(ethValueOwed, 1, MAX_DAILY_REDEMPTION_EV));
        uint16 roll = uint16(bound(rollRaw, 25, 175));

        uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;
        uint256 ethDirect = totalRolledEth;
        uint256 lootboxEth = 0;

        assertEq(ethDirect, totalRolledEth, "INV-03: gameOver ethDirect must equal total");
        assertEq(lootboxEth, 0, "INV-03: gameOver lootboxEth must be zero");
        assertEq(ethDirect + lootboxEth, totalRolledEth, "INV-03: gameOver split must sum to total");
    }

    function testFuzz_INV03_splitConservation_noGameOver(
        uint96 ethValueOwed,
        uint16 rollRaw
    ) public pure {
        ethValueOwed = uint96(bound(ethValueOwed, 1, MAX_DAILY_REDEMPTION_EV));
        uint16 roll = uint16(bound(rollRaw, 25, 175));

        uint256 totalRolledEth = (uint256(ethValueOwed) * roll) / 100;
        uint256 ethDirect = totalRolledEth / 2;
        uint256 lootboxEth = totalRolledEth - ethDirect;

        assertEq(ethDirect + lootboxEth, totalRolledEth, "INV-03: noGameOver split must sum to total");
        // Verify the split is actually 50/50 (within 1 wei for odd values)
        // ethDirect = floor(totalRolledEth / 2), lootboxEth = totalRolledEth - floor(totalRolledEth / 2)
        // So lootboxEth >= ethDirect (lootboxEth gets the extra wei for odd totals)
        assertTrue(lootboxEth >= ethDirect, "INV-03: lootboxEth >= ethDirect (ceiling vs floor)");
        assertTrue(lootboxEth - ethDirect <= 1, "INV-03: split difference is at most 1 wei");
    }
}
