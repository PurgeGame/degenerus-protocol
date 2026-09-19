// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract EightWinnerHarness is DegenerusGameJackpotModule, BucketSeed {
    // kind: 0 early bird, 1 main daily, 2 carryover.
    function seed(uint256 word, uint256 tickets, uint8 mask, uint8 kind) external {
        level = 41;
        uint24 source = kind == 1 ? 41 : 42;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(
            kind == 1 ? word : EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS")))
        );
        for (uint8 q; q < 4; ++q) {
            if ((mask & (1 << q)) != 0) {
                _seedBucketDistinct(source, traits[q], 64, uint160(0x10000 + uint256(q) * 0x1000));
            }
        }
        if (kind == 0) dailyTicketBudgetsPacked = (tickets * 4) << 144;
        else if (kind == 1) {
            dailyJackpotCoinTicketsPending = true;
            dailyTicketBudgetsPacked = 1 | ((tickets * 4) << 8);
        } else dailyTicketBudgetsPacked = 1 | ((tickets * 4) << 72) | (uint256(1) << 136);
    }
}

contract JackpotEightWinnerGroupsTest is Test {
    bytes32 private constant WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");

    function _draw(uint256 word, uint256 tickets, uint8 mask, uint8 kind)
        private returns (uint256[4] memory counts)
    {
        EightWinnerHarness h = new EightWinnerHarness();
        h.seed(word, tickets, mask, kind);
        vm.recordLogs();
        if (kind == 0) h.payEarlyBirdTickets(word);
        else if (kind == 1) h.payDailyJackpotCoinAndTickets(word);
        else h.payCarryoverTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 cap = tickets < (kind == 0 ? 128 : 96) ? tickets : (kind == 0 ? 128 : 96);
        if (cap >= 8) cap = (cap / 8) * 8;
        uint256[4] memory groupWords;
        uint256[4] memory laneMasks;
        uint256 paid;
        uint256 entriesTotal;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != WIN) continue;
            uint256 q = uint256(logs[i].topics[3]) >> 6;
            assertTrue((mask & (1 << q)) != 0, "empty quadrants cannot win");
            (uint32 entries,, uint256 index,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
            assertEq(entries, (tickets / cap) * 4, "equal whole-ticket prizes across quadrants");
            if (counts[q] % 8 == 0) {
                groupWords[q] = index / 8;
                laneMasks[q] = 0;
            }
            assertEq(index / 8, groupWords[q], "eight winners share one packed source word");
            uint256 bit = 1 << (index % 8);
            assertEq(laneMasks[q] & bit, 0, "no repeated lane inside a full word");
            laneMasks[q] |= bit;
            ++counts[q];
            if (counts[q] % 8 == 0) assertEq(laneMasks[q], 255, "every lane of the group is used");
            ++paid;
            entriesTotal += entries;
        }
        assertEq(paid, mask == 0 ? 0 : cap, "funded slots conserved after empty-bucket redistribution");
        assertLe(entriesTotal, tickets * 4, "never create unbacked ticket entries");
        for (uint256 q; q < 4; ++q) {
            if (cap >= 8) assertEq(counts[q] % 8, 0, "every funded bucket gets whole words");
        }
    }

    function testFuzz_TicketGroupsAcrossBudgetsAndEmptyQuadrants(uint256 word, uint16 budget, uint8 mask, uint8 kind) public {
        _draw(word, uint256(budget) % 401, mask & 15, kind % 3);
    }

    function test_NormalTicketTables() public {
        uint256[4] memory counts = _draw(123, 1000, 15, 1);
        uint256 solo;
        for (uint256 q; q < 4; ++q) {
            if (counts[q] == 0) ++solo;
            else assertEq(counts[q], 32);
        }
        assertEq(solo, 1, "main-board solo ETH quadrant stays excluded");
        counts = _draw(123, 1000, 15, 2);
        for (uint256 q; q < 4; ++q) assertEq(counts[q], 24);
        counts = _draw(123, 1000, 15, 0);
        for (uint256 q; q < 4; ++q) assertEq(counts[q], 32);
    }

    function test_BudgetEdgesAndSingleActiveQuadrant() public {
        uint256[8] memory budgets = [uint256(0), 1, 7, 8, 15, 16, 95, 97];
        for (uint256 i; i < budgets.length; ++i) {
            _draw(123, budgets[i], 15, 0);
            _draw(123, budgets[i], 1, 1);
        }
    }

    function _ethTable(uint256 pool, uint16[4] memory expected) private pure {
        for (uint256 rotation; rotation < 4; ++rotation) {
            uint16[4] memory counts = JackpotBucketLib.bucketCountsForPool(pool, rotation, 63_600);
            for (uint256 q; q < 4; ++q) assertEq(counts[q], expected[(q + rotation) % 4]);
        }
    }

    function test_EthTablesAtScaleBoundaries() public pure {
        _ethTable(0, [uint16(0), 0, 0, 0]);
        _ethTable(1 wei, [uint16(24), 16, 8, 1]);
        _ethTable(10 ether, [uint16(24), 16, 8, 1]);
        _ethTable(50 ether, [uint16(48), 32, 16, 1]);
        _ethTable(100 ether, [uint16(80), 56, 24, 1]);
        _ethTable(200 ether, [uint16(152), 104, 48, 1]);
        _ethTable(1_000_000 ether, [uint16(152), 104, 48, 1]);
    }

    function testFuzz_EthScalingStaysAlignedMonotoneAndBounded(uint96 rawPool, uint256 entropy) public pure {
        uint256 pool = uint256(rawPool) % (250 ether);
        uint16[4] memory counts = JackpotBucketLib.bucketCountsForPool(pool, entropy, 63_600);
        uint16[4] memory next = JackpotBucketLib.bucketCountsForPool(pool + 1 ether, entropy, 63_600);
        uint256 total;
        uint256 solo;
        for (uint256 q; q < 4; ++q) {
            total += counts[q];
            assertGe(next[q], counts[q], "growing budget cannot reduce the winner count");
            if (counts[q] == 1) ++solo;
            else assertEq(counts[q] % 8, 0);
        }
        assertEq(solo, pool == 0 ? 0 : 1);
        assertLe(total, 305, "rounding must preserve the full transaction's winner ceiling");
    }
}
