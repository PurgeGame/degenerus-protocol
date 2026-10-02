// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";

contract HotDurationHarness is Craps {
    function run(Bets memory b, bytes32 seed, uint256 bank, uint256 cap, uint256 budget, uint256 boost)
        external pure returns (SlipResult memory)
    {
        return _settleSlip(b, seed, bank, 0, cap, budget, address(123), boost);
    }
}

contract CrapsHotDurationTest is Test {
    HotDurationHarness engine = new HotDurationHarness();
    CrapsOracle oracle = new CrapsOracle();

    function _board(bool pass) private pure returns (Craps.Bets memory b) {
        b.passLine = pass ? 5 : 0;
        b.place4 = 3;
        b.place6 = 5;
        b.hard4 = 3;
        b.hard8 = 3;
        b.dontPass = 5;
    }

    function test_boundedHandsMatchIndependentPerRollOracle() public view {
        uint256[7] memory limits = [uint256(1), 11, 12, 13, 511, 512, 600];
        uint256[8] memory rates = [uint256(30), 25, 20, 18, 14, 10, 7, 5];
        for (uint256 side; side < 2; ++side) {
            Craps.Bets memory b = _board(side == 0);
            for (uint256 k; k < 32; ++k) {
                bytes32 seed = keccak256(abi.encode("hot-bounds", k));
                uint256 terms = 12 | (rates[k % 8] << 8) | ((k % 4) << 16);
                for (uint256 j; j < limits.length; ++j) {
                    Craps.SlipResult memory got = engine.run(b, seed, 1_000_000e18, 8, limits[j], terms);
                    CrapsOracle.SlipResult memory want = oracle.resolveSlipUnder(
                        b, seed, 1_000_000e18, 0, 8, limits[j], address(123), terms
                    );
                    assertEq(got.bankrollOut, want.bankrollOut, "bounded money");
                    assertEq(got.totalRolls, want.totalRolls, "bounded rolls");
                    assertEq(got.handsPlayed, want.handsPlayed, "bounded hands");
                    assertEq(got.peakBankroll, want.peakBankroll, "bounded peak");
                    assertEq(got.hottestHand, want.hottestHand, "longest hand and tie order");
                }
            }
        }
    }

    function test_noBonusThroughRoll12EvenOnYourShooterTurn() public view {
        for (uint256 k; k < 100; ++k) {
            bytes32 seed = keccak256(abi.encode("short", k));
            Craps.Bets memory b = _board(k % 2 == 0);
            for (uint256 limit = 11; limit <= 12; ++limit) {
                Craps.SlipResult memory bare = engine.run(b, seed, 1000e18, 1, limit, 0);
                Craps.SlipResult memory hot = engine.run(b, seed, 1000e18, 1, limit, 12 | (30 << 8));
                assertEq(hot.bankrollOut, bare.bankrollOut, "short hand paid hot");
                Craps.SlipResult memory rotation = engine.run(b, seed, 1000e18, 1, limit, 1 << 16);
                Craps.SlipResult memory both = engine.run(b, seed, 1000e18, 1, limit, 12 | (30 << 8) | (1 << 16));
                assertEq(rotation.bankrollOut, bare.bankrollOut, "cold shooter paid a personal bonus");
                assertEq(both.bankrollOut, bare.bankrollOut, "cold overlap paid a bonus");
            }
        }
    }

    // Script: point 10, neutral rolls, seven-out. The late dark win must count
    // only its 3:4 profit; all earlier neutral rolls earn nothing.
    function test_scriptedDarkWinOn12Versus13ExcludesPrincipal() public view {
        Craps.Bets memory b;
        b.dontPass = 5;
        for (uint256 rolls = 12; rolls <= 13; ++rolls) {
            uint8[] memory dice = new uint8[](rolls * 2);
            for (uint256 i; i < rolls; ++i) { dice[2*i] = 1; dice[2*i+1] = 2; }
            dice[0] = 5; dice[1] = 5;
            dice[2*rolls-2] = 3; dice[2*rolls-1] = 4;
            CrapsOracle.Outcome memory o = oracle.resolveHandWithScriptedDice(b, dice, bytes32(0));
            assertEq(o.rolls, rolls);
            assertEq(o.profit, 3.75e18);
            assertEq(o.returned, 8.75e18);
            assertEq(o.hotProfit, rolls == 13 ? 3.75e18 : 0);
        }
    }

    function test_scriptedPointMadeOn12DoesNotResetAndDeadHardwayStaysDead() public view {
        Craps.Bets memory b;
        b.hard4 = 1; b.place4 = 1; b.passLine = 1;
        uint8[] memory dice = new uint8[](16 * 2);
        for (uint256 i; i < 16; ++i) { dice[2*i] = 1; dice[2*i+1] = 2; }
        dice[0] = 5; dice[1] = 5; // point 10
        dice[2] = 2; dice[3] = 2; // early hard four pays
        dice[4] = 1; dice[5] = 3; // easy four kills hardway
        dice[22] = 5; dice[23] = 5; // roll 12 makes point
        dice[24] = 3; dice[25] = 4; // roll 13 come-out seven: live pass pays
        dice[26] = 5; dice[27] = 5; // new point
        dice[28] = 2; dice[29] = 2; // place pays; dead hardway cannot
        dice[30] = 3; dice[31] = 4; // seven-out
        CrapsOracle.Outcome memory o = oracle.resolveHandWithScriptedDice(b, dice, bytes32(0));
        assertEq(o.rolls, 16);
        assertEq(o.hotProfit, 3e18);
        assertEq(o.profit, 15e18);
    }

    function testFuzz_singleHandMatchesProfitFormula(bytes32 seed, bool pass, uint8 rate) public view {
        Craps.Bets memory b = _board(pass);
        CrapsOracle.Outcome memory o = oracle.resolveHand(b, oracle.handSeed(seed, 0));
        uint256 bonus = o.hotProfit * (uint256(rate) + 30) / 100;
        Craps.SlipResult memory got = engine.run(b, seed, 1000e18, 1, 600, 12 | (uint256(rate) << 8) | (1 << 16));
        assertEq(got.bankrollOut, 1000e18 - oracle.stakeFor(b) + o.returned + bonus);
        assertEq(got.totalRolls, o.rolls);
    }
}
