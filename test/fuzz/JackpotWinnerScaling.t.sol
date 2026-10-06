// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test, Vm} from "forge-std/Test.sol";
import {QuadrantWhaleHarness} from "./QuadrantWhalePass.t.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Live ETH draws: non-solo targets [32, 16, 4] double at 40, 160, 640, 2,560 and
///      10,240 ETH, to at most [1024, 512, 128]; the solo stays one winner. Ticket legs double
///      the same way: 96, 192 from 40 ETH, 384 from 160 ETH.
contract JackpotWinnerScalingTest is Test {
    uint24 private constant LVL = 4;
    uint160 private constant BASE = 0xA00000;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 private constant PASS_WIN = keccak256("JackpotWhalePassWin(uint32,uint256,uint8)");

    QuadrantWhaleHarness private h;

    function setUp() public {
        vm.warp(101 days);
        h = new QuadrantWhaleHarness();
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
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

    function _reference(uint256 pool, uint256 b) private pure returns (uint256) {
        return pool == 0 ? 0 : b * _mult(pool, 32);
    }

    /// @dev Counts by role (large, medium, small, solo) under the entropy rotation.
    function _roles(uint16[4] memory counts, uint256 entropy) private pure returns (uint256[4] memory roles) {
        uint256 offset = entropy & 3;
        for (uint256 k; k < 4; ++k) roles[k] = counts[(k + 4 - offset) & 3];
    }

    function test_TargetTable() public pure {
        uint256[10] memory pools = [
            uint256(0), 1, 10 ether, 40 ether, 160 ether, 200 ether, 640 ether, 2_560 ether, 10_240 ether, 1_000_000 ether
        ];
        uint256[3][10] memory want = [
            [uint256(0), 0, 0], [uint256(32), 16, 4], [uint256(32), 16, 4], [uint256(64), 32, 8],
            [uint256(128), 64, 16], [uint256(128), 64, 16], [uint256(256), 128, 32], [uint256(512), 256, 64],
            [uint256(1024), 512, 128], [uint256(1024), 512, 128]
        ];
        for (uint256 i; i < pools.length; ++i) {
            for (uint256 entropy; entropy < 4; ++entropy) {
                uint16[4] memory counts = JackpotBucketLib.ethWinnerTargets(pools[i], entropy);
                uint256[4] memory roles = _roles(counts, entropy);
                for (uint256 k; k < 3; ++k) assertEq(roles[k], want[i][k]);
                assertEq(roles[3], pools[i] == 0 ? 0 : 1, "the solo stays one winner");
                assertEq(counts[JackpotBucketLib.soloBucketIndex(entropy)], roles[3], "solo sits on the solo index");
            }
        }
    }

    function testFuzz_TargetsMatchReferenceAndGrowMonotone(uint256 a, uint256 b, uint256 entropy) public pure {
        a = bound(a, 0, 20_000 ether);
        b = bound(b, a, 20_000 ether);
        uint256[4] memory ra = _roles(JackpotBucketLib.ethWinnerTargets(a, entropy), entropy);
        uint256[4] memory rb = _roles(JackpotBucketLib.ethWinnerTargets(b, entropy), entropy);
        uint256[3] memory base = [uint256(32), 16, 4];
        for (uint256 k; k < 3; ++k) {
            assertEq(ra[k], _reference(a, base[k]), "matches the independent reference");
            assertLe(ra[k], rb[k], "a larger budget never targets fewer winners");
            assertLe(rb[k], base[k] * 32, "capped at 32x the base");
        }
    }

    function test_FourfoldBudgetDoublesTargets() public pure {
        for (uint256 m = 1; m <= 32; m *= 2) {
            uint256[4] memory roles = _roles(JackpotBucketLib.ethWinnerTargets(10 ether * m * m, 0), 0);
            assertEq(roles[0], 32 * m);
            assertEq(roles[1], 16 * m);
            assertEq(roles[2], 4 * m);
        }
    }

    function testFuzz_OrderSettlesNonSoloLargestFirstThenSolo(uint16[4] memory counts, uint8 solo) public pure {
        solo %= 4;
        uint8[4] memory order = JackpotBucketLib.bucketOrderSoloLast(counts, solo);
        assertEq(order[3], solo, "the solo settles last");
        uint256 seen;
        for (uint256 j; j < 4; ++j) seen |= 1 << order[j];
        assertEq(seen, 15, "every quadrant exactly once");
        for (uint256 j; j < 2; ++j) {
            assertGe(counts[order[j]], counts[order[j + 1]], "largest first");
            if (counts[order[j]] == counts[order[j + 1]]) assertLt(order[j], order[j + 1], "ties keep the lower index");
        }
    }

    function _ticketReference(uint256 value) private pure returns (uint256) {
        return 96 * _mult(value, 4);
    }

    /// @dev Ticket legs: 96 winners, 192 from 40 ETH, 384 from 160 ETH.
    function test_TicketWinnerCapTable() public pure {
        uint256[8] memory values = [uint256(0), 1, 10 ether, 40 ether, 90 ether, 160 ether, 640 ether, 1_000_000 ether];
        uint256[8] memory want = [uint256(96), 96, 96, 192, 192, 384, 384, 384];
        for (uint256 i; i < values.length; ++i) assertEq(JackpotBucketLib.ticketWinnerCap(values[i]), want[i]);
    }

    function testFuzz_TicketWinnerCapMatchesReferenceAndGrows(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 1_000 ether);
        b = bound(b, a, 1_000 ether);
        uint256 capA = JackpotBucketLib.ticketWinnerCap(a);
        assertEq(capA, _ticketReference(a), "matches the independent reference");
        assertLe(capA, JackpotBucketLib.ticketWinnerCap(b), "a larger budget never caps fewer winners");
        assertGe(capA, 96);
        assertLe(capA, 384);
    }

    struct Tally {
        uint256[4] slots;
        uint256[4] each;
        uint256[4] halves;
        uint256 eth;
    }

    /// @dev A 5,000 ETH single-day final jackpot. The 20% ticket leg leaves a 4,000 ETH ETH
    ///      budget, targeting 512 / 256 / 64 plus the solo.
    function test_FiveThousandEthFinalDayMatchesThePlan() public {
        uint256 word = 1337;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        for (uint8 q; q < 4; ++q) h.seedBucket(LVL, traits[q], 65, BASE + uint160(q) * 0x10000);
        h.prepare(5_000 ether, 0, true);
        Tally memory t;
        for (uint256 calls;; ++calls) {
            assertLt(calls, 16, "the leg finishes");
            vm.recordLogs();
            MineFlipGas.Result memory r = h.runDailyJackpot(true, LVL, word, 9_000_000);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] == ETH_WIN) {
                    uint256 q = uint256(logs[i].topics[3]) >> 6;
                    (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                    if (t.slots[q] == 0) t.each[q] = amount;
                    assertEq(amount, t.each[q]);
                    ++t.slots[q];
                    t.eth += amount;
                } else if (logs[i].topics[0] == PASS_WIN) {
                    uint160 w = uint160(uint256(logs[i].topics[1]));
                    (uint256 halves,) = abi.decode(logs[i].data, (uint256, uint8));
                    t.halves[(w - BASE) / 0x10000] += halves;
                }
            }
            if (r.done) break;
        }
        // Roles by winner count: [slots, award, half passes].
        uint256[3][4] memory want = [
            [uint256(512), 0.7 ether, 58], [uint256(256), 1.5 ether, 58], [uint256(64), 6.2 ether, 58], [uint256(1), 1870.8 ether, 266]
        ];
        for (uint256 k; k < 4; ++k) {
            bool found;
            for (uint256 q; q < 4; ++q) {
                if (t.slots[q] != want[k][0]) continue;
                found = true;
                assertEq(t.each[q], want[k][1], "award per winner");
                assertEq(t.halves[q], want[k][2], "pass conversion from the full allocation");
            }
            assertTrue(found, "every role pays its count");
        }
        assertEq(t.eth, 3_010 ether, "cash paid");
        (uint128 next, uint128 future) = h.poolsView();
        assertEq(next, 20 ether + 1_000 ether, "the ticket leg");
        assertEq(future, 990 ether, "220 full passes back the future pool");
        assertEq(h.currentPoolView(), 0, "the final day spends the whole pool");
        assertEq(h.claimablePoolView(), 3_010 ether);
    }
}
