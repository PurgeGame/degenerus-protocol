// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract EightWinnerHarness is DegenerusGameJackpotModule, BucketSeed {
    // kind: 0 early bird, 1 main daily. Both draw off the day's main board now.
    function seed(uint256 word, uint256 tickets, uint8 mask, uint8 kind) external {
        level = 41;
        uint24 source = kind == 1 ? 41 : 42;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        for (uint8 q; q < 4; ++q) {
            if ((mask & (1 << q)) != 0) {
                _seedBucketDistinct(source, traits[q], 64, uint160(0x10000 + uint256(q) * 0x1000));
            }
        }
        if (kind == 0) dailyTicketBudgetsPacked = (tickets * 4) << 144;
        else {
            dailyJackpotCoinTicketsPending = true;
            dailyTicketBudgetsPacked = 1 | ((tickets * 4) << 8);
        }
    }
}

contract JackpotEightWinnerGroupsTest is Test {
    bytes32 private constant WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");

    function _winnerFingerprint(uint256 word, uint256 tickets, uint8 kind) private returns (bytes32 result) {
        EightWinnerHarness h = new EightWinnerHarness();
        h.seed(word, tickets, 15, kind);
        vm.recordLogs();
        if (kind == 0) h.payEarlyBirdTickets(word);
        else h.payDailyJackpotCoinAndTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != WIN) continue;
            (, uint24 source, uint256 index,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
            result = keccak256(abi.encode(result, logs[i].topics[1], logs[i].topics[3], source, index));
            ++count;
        }
        assertEq(count, 384, "both budgets are past the 160 ETH sizing cap");
    }

    /// @dev Past the sizing cap the winner count is fixed, so a larger prize keeps every winner.
    function testFuzz_AwardSizeCannotChangeTicketWinners(uint256 word, uint8 kindSeed) public {
        uint8 kind = kindSeed % 2;
        assertEq(_winnerFingerprint(word, 2048, kind), _winnerFingerprint(word, 4096, kind),
            "changing each prize's size must preserve the selected ticket occurrences");
    }

    function _draw(uint256 word, uint256 tickets, uint8 mask, uint8 kind)
        private returns (uint256[4] memory counts)
    {
        EightWinnerHarness h = new EightWinnerHarness();
        h.seed(word, tickets, mask, kind);
        vm.recordLogs();
        if (kind == 0) h.payEarlyBirdTickets(word);
        else h.payDailyJackpotCoinAndTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 cap = _ticketCap(tickets * 0.08 ether);
        if (tickets < cap) cap = tickets;
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

    /// @dev Independent doubling reference: 1, doubled at 40, 160, 640, ... ETH, at most `max`.
    function _mult(uint256 value, uint256 max) private pure returns (uint256 m) {
        m = 1;
        uint256 step = 40 ether;
        while (m < max && value >= step) {
            m *= 2;
            step *= 4;
        }
    }

    /// @dev Independent model of the ticket winner cap.
    function _ticketCap(uint256 value) private pure returns (uint256) {
        return 96 * _mult(value, 4);
    }

    function testFuzz_TicketGroupsAcrossBudgetsAndEmptyQuadrants(uint256 word, uint16 budget, uint8 mask, uint8 kind) public {
        _draw(word, uint256(budget) % 401, mask & 15, kind % 2);
    }

    /// @dev 1,000 tickets at 0.08 ETH (80 ETH) size 192 winners: 64 in each non-solo quadrant
    ///      for both legs.
    function test_NormalTicketTables() public {
        for (uint8 kind; kind < 2; ++kind) {
            uint256[4] memory counts = _draw(123, 1000, 15, kind);
            uint256 solo;
            uint256 total;
            for (uint256 q; q < 4; ++q) {
                if (counts[q] == 0) ++solo;
                else assertEq(counts[q], 64);
                total += counts[q];
            }
            assertEq(solo, 1, "the day's solo ETH quadrant stays excluded");
            assertEq(total, 192);
        }
    }

    function test_BudgetEdgesAndSingleActiveQuadrant() public {
        uint256[8] memory budgets = [uint256(0), 1, 7, 8, 15, 16, 95, 97];
        for (uint256 i; i < budgets.length; ++i) {
            _draw(123, budgets[i], 15, 0);
            _draw(123, budgets[i], 1, 1);
        }
    }
}
