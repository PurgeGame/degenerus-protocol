// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {LegacyCrapsEngine} from "../helpers/LegacyCrapsEngine.sol";

/// @dev Test-only inline wrapper with explicit bounds, including the historical 8,192-roll limit.
contract InlineCrapsReference is Craps {
    function run(uint256 chips, uint256 chipFlip, uint256 scatter, uint256 count, bytes32 seed,
        uint256 bankroll, uint256 goal, address player, uint256 boost, uint256 budget)
        external pure returns (SlipResult memory)
    {
        Bets memory board = _boardFrom(chips, chipFlip);
        _scatterInto(board, scatter, chipFlip, count);
        return _settleSlip(board, seed, bankroll, goal, _MAX_SLIP_HANDS, budget, uint256(uint160(player)), boost);
    }
}

/// @dev Current duration-rule engine versus the inline reference under shared and historical
///      roll limits. The deterministic 400-slip digest was regenerated for the duration rule;
///      payouts are also checked against the independent per-roll oracle in separate suites.
contract CrapsEngineParity is Test {
    // Generated from the duration-rule Solidity engine; independent oracle parity is
    // covered by CrapsHotDuration and CrapsShooterBoost, including bounded runs.
    bytes32 internal constant INLINE_ENGINE_DIGEST =
        0x9f1d8924e3c2482c6be7f34b7ce0dd9ae2497ddb2feaaddcce01730ad777aff2;

    function testFuzz_CompactHeaderPreservesEveryOutcome(
        uint32 owner, uint256 word, uint8 chipsRaw, bool awarded, bool custom
    ) public {
        owner = uint32(bound(owner, 1, type(uint32).max));
        uint256 chips = (uint256(chipsRaw) % 8) << ((word % 10) * 3);
        uint48 slot = custom ? uint48((1 << 40) + 7) : 86;
        uint256 betId = (uint256(slot) << 64) | 3;
        uint256 oldHeader = owner | (chips << 160) | (uint256(4) << 206) | (uint256(0x7f) << 217);
        uint256 compact = owner | (chips << 32) | (uint256(4) << 62) | (uint256(0x7f) << 65);
        if (awarded) { oldHeader |= uint256(1) << 224; compact |= uint256(1) << 72; }
        CrapsEngine engine = new CrapsEngine();
        LegacyCrapsEngine legacy = new LegacyCrapsEngine();
        Craps.SlipResult memory before = legacy.settleBattle(
            betId, oldHeader, 30, 1500, 7500, slot, (uint256(9) << 64) | 3, word);
        Craps.SlipResult memory after_ = engine.settleBattle(
            betId, compact, 30, 1500, 7500, slot, (uint256(9) << 64) | 3, word);
        assertEq(keccak256(abi.encode(before)), keccak256(abi.encode(after_)), "compact header changed a run");
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_directRunUsesSharedRollCeiling(bytes32 seed, bool latched) public {
        CrapsEngine e = new CrapsEngine();
        uint256 goal = latched ? 5e39 : 5e40;
        // Enough capital to force a bound, with a full board and no survival or scatter ambiguity.
        uint256 chips = 3 | (3 << 9) | (3 << 12) | (1 << 15);
        Craps.SlipResult memory direct = e.settleSlip(chips, 1, 0, 0, seed, 1e40, goal, 1, 0);
        assertGe(direct.totalRolls, 600, "stopped before the shared budget");
        assertLe(direct.totalRolls, 1_111, "passed the shared ceiling");
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
                packed, chipFlip, uint256(keccak256(abi.encode(h, "scatter"))), n, seed, bankroll, goal, uint256(uint160(player)), boost
            );
            Craps.SlipResult memory current = ref.run(
                packed, chipFlip, uint256(keccak256(abi.encode(h, "scatter"))), n, seed, bankroll, goal, player, boost, 600
            );
            assertEq(keccak256(abi.encode(r)), keccak256(abi.encode(current)), "shared-budget inline parity");
            Craps.SlipResult memory legacy = ref.run(
                packed, chipFlip, uint256(keccak256(abi.encode(h, "scatter"))), n, seed, bankroll, goal, player, boost, 8_192
            );
            assertLe(r.totalRolls, 1_111);
            assertLe(r.totalRolls, legacy.totalRolls, "lower limit lengthened the run");
            if (legacy.totalRolls < 600) {
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
        assertEq(bytes32(acc), INLINE_ENGINE_DIGEST, "duration engine regression digest changed");
    }
}
