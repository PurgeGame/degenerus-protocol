// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";

contract DepthCrapsDecoder is CrapsBattle {
    function preset(uint256 roll, uint256 period)
        external pure returns (uint128 bank, uint128 goal, uint256 round, uint256 units, uint256 tier)
    {
        return _bonusPreset(roll, period);
    }
    function schedRound(uint256 bank) external pure returns (uint256) { return _schedRound(bank); }
}

contract DepthJackpotDecoder is JackpotBattle {
    function preset(uint256 roll, uint256 period)
        external pure returns (uint128 bank, uint128 goal, uint256 round, uint256 units, uint256 tier)
    {
        return _bonusPreset(roll, period);
    }
}

/// @notice Scheduled Dice Runs open at two fifths of their bankroll (two and a half rounds deep),
///         in both preset copies, for every tier and every jackpot bankroll up to the cap.
contract CrapsScheduledDepthTest is Test {
    DepthCrapsDecoder private craps;
    DepthJackpotDecoder private jackpot;

    function setUp() public {
        craps = new DepthCrapsDecoder();
        jackpot = new DepthJackpotDecoder();
    }

    function testFuzz_BothPresetCopiesPlayTwoFifths(uint256 roll, uint8 periodSeed) public view {
        uint256 period = periodSeed % 5; // the jackpot period quotes only its fee
        (uint128 bank, uint128 goal, uint256 round, uint256 units, uint256 tier) = craps.preset(roll, period);
        (uint128 bank2, uint128 goal2, uint256 round2, uint256 units2, uint256 tier2) = jackpot.preset(roll, period);
        assertEq(bank, bank2, "bankroll copies agree");
        assertEq(goal, goal2, "goal copies agree");
        assertEq(round, round2, "round copies agree");
        assertEq(units, units2, "bounty copies agree");
        assertEq(tier, tier2, "tier copies agree");
        assertEq(round * 5, uint256(bank) * 2, "two and a half rounds deep");
        assertEq(goal, bank * 5, "the 5x goal is unchanged");
        assertTrue(bank == 600 || bank == 1800 || bank == 4500, "tier bankrolls are unchanged");
        assertEq(round % 30, 0, "rounds stay whole 30-multiples");
    }

    function test_EveryTierRound() public view {
        bool[3] memory seen;
        for (uint256 roll; roll < 600; ++roll) {
            for (uint256 period; period < 5; ++period) {
                (uint128 bank,, uint256 round,,) = craps.preset(uint256(keccak256(abi.encode(roll))), period);
                if (bank == 600) { assertEq(round, 240); seen[0] = true; }
                else if (bank == 1800) { assertEq(round, 720); seen[1] = true; }
                else { assertEq(bank, 4500); assertEq(round, 1800); seen[2] = true; }
            }
        }
        assertTrue(seen[0] && seen[1] && seen[2], "every tier drawn");
    }

    function test_JackpotRoundsAreExactAndFitALeg() public view {
        uint256[9] memory banks = [uint256(300), 600, 900, 1200, 6000, 30_000, 41_942_700, 41_943_000, 41_943_300];
        for (uint256 i; i < banks.length; ++i) {
            uint256 round = craps.schedRound(banks[i]);
            assertEq(round * 5, banks[i] * 2, "exact for every 300-multiple");
            assertEq(round % 120, 0, "a multiple of 120");
            if (banks[i] <= 41_943_000) assertLe(round, type(uint24).max, "fits one leg up to the cap");
            else assertGt(round, type(uint24).max, "the next 300-multiple would not fit");
        }
    }
}
