// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";

/// @dev Test-only inline wrapper with explicit bounds, including the historical 8,192-roll limit.
contract InlineCrapsReference is Craps {
    function run(uint256 chips, uint256 chipFlip, uint256 scatter, uint256 count, bytes32 seed,
        uint256 bankroll, uint256 goal, address player, uint256 boost, uint256 budget)
        external pure returns (SlipResult memory)
    {
        Bets memory board = _boardFrom(chips, chipFlip);
        _scatterInto(board, scatter, chipFlip, count);
        return _settleSlip(board, seed, bankroll, goal, _MAX_SLIP_HANDS, budget, player, boost);
    }
}

/// @dev The engine moved out of the table without changing a roll. The digest below was taken
///      from the inline engine at `e013043d9` — `_boardFrom`, `_scatterInto`, `_settleSlip`
///      compiled into CrapsBattle — over exactly this generator: four hundred slips across every
///      board shape, chip size, scatter count, bankroll, goal, owner and boost row. Preserve that
///      historical digest under its original limit, and compare today's engine to the inline
///      reference with the shared 1,000-roll budget. Runs ending before that budget stay identical.
contract CrapsEngineParity is Test {
    bytes32 internal constant INLINE_ENGINE_DIGEST =
        0x2385761337a93f4816ad870b1564f9a05f7e5bdeb8f9c532adbd9af0794945e9;

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_directAndRankedRunsUseSharedRollCeiling(bytes32 seed, bool latched) public {
        CrapsEngine e = new CrapsEngine();
        uint256 goal = latched ? 5e39 : 5e40;
        // Enough capital to force a bound, with a full board and no survival or scatter ambiguity.
        uint256 chips = 3 | (3 << 9) | (3 << 12) | (1 << 15);
        Craps.SlipResult memory direct = e.settleSlip(chips, 1, 0, 0, seed, 1e40, goal, address(1), 0);
        Craps.SlipResult memory ranked = e.settleRanked(chips, 1, 0, 0, seed, 1e40, goal, address(1), 0);
        assertGe(direct.totalRolls, 1_000, "stopped before the shared budget");
        assertLe(direct.totalRolls, 1_511, "passed the shared ceiling");
        assertEq(ranked.totalRolls, direct.totalRolls, "ranked entry used different bounds");
        assertEq(ranked.handsPlayed, direct.handsPlayed);
        assertEq(ranked.bankrollOut, direct.bankrollOut);
        assertEq(uint8(ranked.stop), uint8(direct.stop));
        assertEq(uint8(direct.stop), uint8(latched ? Craps.SlipStop.Goal : Craps.SlipStop.Bust));
        if (latched) assertGe(direct.bankrollOut, goal, "latched goal lost its reserve");
    }

    function test_sharedBudgetMatchesInlineReferenceAndLegacyPrefix() public {
        CrapsEngine e = new CrapsEngine();
        InlineCrapsReference ref = new InlineCrapsReference();
        uint256 acc;
        for (uint256 i = 0; i < 400; ++i) {
            uint256 h = uint256(keccak256(abi.encode("craps-engine-digest", i)));
            uint256 packed = h & 0x3FFFFFFF;
            uint256 chipFlip = 30 + ((h >> 32) % 3000);
            uint256 n = (h >> 48) % 11;
            bytes32 seed = keccak256(abi.encode(h, "seed"));
            uint256 bankroll = chipFlip * 10 * (1 + ((h >> 64) % 40)) * 1 ether;
            uint256 goal = bankroll * (2 + ((h >> 80) % 4));
            address player = address(uint160(h >> 96));
            uint256 boost = ((h >> 200) % 3 == 0) ? 0 : (h >> 160) & 0xFFFFFFFFFFFF;
            Craps.SlipResult memory r = e.settleSlip(
                packed, chipFlip, uint256(keccak256(abi.encode(h, "scatter"))), n, seed, bankroll, goal, player, boost
            );
            Craps.SlipResult memory current = ref.run(
                packed, chipFlip, uint256(keccak256(abi.encode(h, "scatter"))), n, seed, bankroll, goal, player, boost, 1_000
            );
            assertEq(keccak256(abi.encode(r)), keccak256(abi.encode(current)), "shared-budget inline parity");
            Craps.SlipResult memory legacy = ref.run(
                packed, chipFlip, uint256(keccak256(abi.encode(h, "scatter"))), n, seed, bankroll, goal, player, boost, 8_192
            );
            assertLe(r.totalRolls, 1_511);
            assertLe(r.totalRolls, legacy.totalRolls, "lower limit lengthened the run");
            if (legacy.totalRolls < 1_000) {
                assertEq(keccak256(abi.encode(r)), keccak256(abi.encode(legacy)), "short run changed");
            }
            acc = uint256(
                keccak256(
                    abi.encode(
                        acc, legacy.bankrollIn, legacy.bankrollOut, legacy.peakBankroll, legacy.handsPlayed,
                        legacy.unitsPlayed, legacy.totalRolls, uint8(legacy.stop)
                    )
                )
            );
        }
        assertEq(bytes32(acc), INLINE_ENGINE_DIGEST, "historical engine changed beyond its roll limit");
    }
}
