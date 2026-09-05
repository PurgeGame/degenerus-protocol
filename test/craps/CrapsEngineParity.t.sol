// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";

/// @dev The engine moved out of the table without changing a roll. The digest below was taken
///      from the inline engine at `e013043d9` — `_boardFrom`, `_scatterInto`, `_settleSlip`
///      compiled into CrapsBattle — over exactly this generator: four hundred slips across every
///      board shape, chip size, scatter count, bankroll, goal, owner and boost row. The relocated
///      engine must fold to the same digest, run by run, or it is not the same engine.
contract CrapsEngineParity is Test {
    bytes32 internal constant INLINE_ENGINE_DIGEST =
        0x2385761337a93f4816ad870b1564f9a05f7e5bdeb8f9c532adbd9af0794945e9;

    function test_relocatedEngineMatchesInlineDigest() public {
        CrapsEngine e = new CrapsEngine();
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
            acc = uint256(
                keccak256(
                    abi.encode(
                        acc, r.bankrollIn, r.bankrollOut, r.peakBankroll, r.handsPlayed, r.unitsPlayed, r.totalRolls, uint8(r.stop)
                    )
                )
            );
        }
        assertEq(bytes32(acc), INLINE_ENGINE_DIGEST, "the relocated engine settles differently from the inline one");
    }
}
