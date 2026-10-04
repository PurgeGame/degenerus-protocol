// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract JackpotCheckpointHarness is DegenerusGameJackpotModule, BucketSeed {
    function seed(uint24 lvl, uint256 word, bool concentrated) external {
        level = lvl - 1;
        dailyIdx = 100;
        rngLockedFlag = true;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < (concentrated ? 1 : 4); ++q) {
            this.seedOne(lvl, traits[q], uint160(0x10000 + uint256(q) * 0x10000));
        }
        traits[3] = GoldSixLib.daily(traits[3], word);
        dailyFoilDraw[(dailyIdx + 1) & 1] = _packFoilDraw(
            JackpotBucketLib.packWinningTraits(traits), level, dailyIdx + 1, word);
        // 1,000 tickets (40 ETH at 0.04): 192 winners at 5 tickets each.
        dailyTicketBudgetsPacked = uint256(1000 * 4) << 144;
    }
    function seedOne(uint24 lvl, uint8 trait, uint160 base) external {
        _seedBucketDistinct(lvl, trait, 512, base);
    }
    function progress() external view returns (uint8, uint8, uint16, uint128) {
        return (jackpotWork.kind, jackpotWork.quadrant, jackpotWork.winner, jackpotWork.paid);
    }
    function seedDaily(uint24 lvl) external {
        level = lvl;
        jackpotPhaseFlag = true;
        jackpotCounter = 1;
        _setCurrentPrizePool(10_000 ether);
        _setPrizePools(0, 5_000 ether);
    }
    function accounting() external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        return (_getCurrentPrizePool(), _getNextPrizePool(), _getFuturePrizePool(), claimablePool, goldenTicket, dailyTicketBudgetsPacked);
    }
    function liabilities() external view returns (uint256) { return claimablePool; }
    function claimable(address player) external view returns (uint256) { return _claimableOf(player); }
    function pending() external view returns (uint256) { return dailyTicketBudgetsPacked; }
    function terminalGeometry(uint256 word, uint24 lvl, uint256 pool)
        external pure returns (uint16[4] memory counts, uint256[4] memory shares)
    {
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        uint256 raw = EntropyLib.hash2(word, lvl);
        uint8 solo = _pickSoloQuadrant(traits, raw);
        uint256 entropy = (raw & ~uint256(3)) | ((3 - solo) & 3);
        counts = JackpotBucketLib.terminalWinnerCounts(entropy);
        uint64 packed = uint64(6000) | (uint64(1333) << 16) | (uint64(1333) << 32) | (uint64(1334) << 48);
        uint16[4] memory bps = JackpotBucketLib.shareBpsByBucket(packed, uint8(entropy & 3));
        shares = JackpotBucketLib.bucketShares(pool, bps, counts, solo);
    }
}

contract JackpotCheckpointsTest is Test {
    JackpotCheckpointHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant POOL = 1000 ether + 997;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 private constant TICKET_WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");

    function setUp() public {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        h = new JackpotCheckpointHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
    }

    function _digest(bytes32 digest, Vm.Log[] memory logs) private pure returns (bytes32) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("log_named_uint(string,uint256)")) continue;
            digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
        }
        return digest;
    }

    function _terminal(uint256 allowance) private returns (MineFlipGas.Result memory result, uint256 paid) {
        vm.cool(address(h));
        vm.prank(ContractAddresses.GAME);
        uint256 beforeGas = gasleft();
        (result, paid) = h.runTerminalJackpotWork{gas: 10_000_000}(POOL, LVL, WORD, allowance);
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("cold terminal checkpoint including intrinsic", used);
        assertLt(used, 10_000_000, "complete transaction envelope");
    }

    function _earlyBird(uint256 allowance, uint256 supplied) private returns (MineFlipGas.Result memory result) {
        vm.cool(address(h));
        uint256 beforeGas = gasleft();
        result = h.runEarlyBirdTickets{gas: supplied}(WORD, allowance);
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("cold ticket checkpoint including intrinsic", used);
        assertLt(used, 10_000_000);
    }

    function test_TerminalQuadrantsPreserveTranscriptSharesAndLiabilities() public {
        h.seed(LVL, WORD, false);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        (MineFlipGas.Result memory full, uint256 paidFull) = _terminal(9_000_000);
        Vm.Log[] memory fullLogs = vm.getRecordedLogs();
        bytes32 digestFull = _digest(0, fullLogs);
        while (!full.done) {
            vm.recordLogs();
            uint256 delta;
            (full, delta) = _terminal(9_000_000);
            paidFull += delta;
            digestFull = _digest(digestFull, vm.getRecordedLogs());
        }
        assertEq(h.liabilities(), paidFull);
        (uint16[4] memory counts, uint256[4] memory shares) = h.terminalGeometry(WORD, LVL, POOL);
        uint256 expected;
        for (uint8 q; q < 4; ++q) expected += (shares[q] / counts[q]) * counts[q];
        assertEq(paidFull, expected, "only original per-winner rounding remains unpaid");
        assertTrue(vm.revertToState(snap));
        bytes32 digestSplit;
        uint256 paidSplit;
        bool done;
        uint256 calls;
        while (!done && calls < 8) {
            vm.recordLogs();
            (MineFlipGas.Result memory result, uint256 delta) = _terminal(6_700_000);
            digestSplit = _digest(digestSplit, vm.getRecordedLogs());
            assertTrue(result.progressed);
            paidSplit += delta;
            assertEq(h.liabilities(), paidSplit, "every checkpoint has its matching liability");
            done = result.done;
            ++calls;
        }
        assertTrue(done);
        assertGt(calls, 1, "quadrant checkpoint exercised");
        assertEq(paidSplit, paidFull);
        assertEq(digestSplit, digestFull, "ordered winners, entry indexes, and amounts match");
    }

    function test_ConcentratedTicketsAwardInFixedGroups() public {
        h.seed(LVL, WORD, true);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        MineFlipGas.Result memory full = _earlyBird(12_000_000, 12_500_000);
        bytes32 digestFull = _digest(0, vm.getRecordedLogs());
        uint256 awards = full.rewardBasis;
        while (!full.done) {
            vm.recordLogs();
            full = _earlyBird(12_000_000, 12_500_000);
            awards += full.rewardBasis;
            digestFull = _digest(digestFull, vm.getRecordedLogs());
        }
        assertEq(awards, 192);
        assertEq(h.pending(), 0);
        assertTrue(vm.revertToState(snap));
        bytes32 digestSplit;
        uint256 splitAwards;
        bool done;
        bool midQuadrant;
        uint256 calls;
        while (!done && calls < 32) {
            vm.recordLogs();
            // Small calls stop between eight-winner groups inside the 128-winner quadrant.
            MineFlipGas.Result memory result = _earlyBird(1_000_000, 1_500_000);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            digestSplit = _digest(digestSplit, logs);
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != TICKET_WIN) continue;
                (uint32 entries, uint24 source, uint256 index, bool rounded) = abi.decode(logs[i].data, (uint32,uint24,uint256,bool));
                assertEq(entries, 20, "5 whole tickets per slot");
                assertEq(source, LVL);
                assertFalse(rounded);
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(uint160(0x10001 + index)));
            }
            (, , uint16 winner,) = h.progress();
            assertEq(winner % 8, 0, "checkpoint sits on a group start");
            if (winner != 0) midQuadrant = true;
            assertEq(result.rewardBasis % 8, 0, "awards land in whole groups");
            assertTrue(result.progressed);
            splitAwards += result.rewardBasis;
            done = result.done;
            ++calls;
        }
        assertTrue(done);
        assertTrue(midQuadrant, "mid-quadrant checkpoints exercised");
        assertGt(calls, 2);
        assertEq(splitAwards, awards);
        assertEq(digestSplit, digestFull);
    }

    function test_LowCallerGasCheckpointPreservesCompletedTranscript() public {
        h.seed(LVL, WORD, true);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        MineFlipGas.Result memory result = _earlyBird(12_000_000, 12_500_000);
        bytes32 expectedTranscript = _digest(0, vm.getRecordedLogs());
        while (!result.done) {
            vm.recordLogs();
            result = _earlyBird(12_000_000, 12_500_000);
            expectedTranscript = _digest(expectedTranscript, vm.getRecordedLogs());
        }
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        result = _earlyBird(9_000_000, 3_000_000);
        bytes32 actual = _digest(0, vm.getRecordedLogs());
        assertFalse(result.done, "low gas stops at a safe checkpoint");
        uint256 calls;
        while (!result.done && calls++ < 12) {
            vm.recordLogs();
            result = _earlyBird(12_000_000, 12_500_000);
            actual = _digest(actual, vm.getRecordedLogs());
        }
        assertTrue(result.done);
        assertEq(actual, expectedTranscript);
    }

    function test_SuccessfulOutputPrefixDoesNotDependOnCallerGas() public {
        h.seed(LVL, WORD, false);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        (MineFlipGas.Result memory a, uint256 paidA) = h.runTerminalJackpotWork{gas: 10_000_000}(POOL, LVL, WORD, 9_000_000);
        bytes32 digestA = _digest(0, vm.getRecordedLogs());
        (uint8 kindA, uint8 qA,,) = h.progress();
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        (MineFlipGas.Result memory b, uint256 paidB) = h.runTerminalJackpotWork{gas: 15_000_000}(POOL, LVL, WORD, 9_000_000);
        bytes32 digestB = _digest(0, vm.getRecordedLogs());
        (uint8 kindB, uint8 qB,,) = h.progress();
        assertEq(abi.encode(a), abi.encode(b));
        assertEq(paidA, paidB);
        assertEq(kindA, kindB);
        assertEq(qA, qB);
        assertEq(digestA, digestB);
    }
    function test_GoldenArmingAndWhaleConversionRemainExactlyOnceAcrossQuadrants() public {
        uint256 word = 1;
        while (true) {
            uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
            if (((traits[0] >> 3) & 7) == 7 && ((traits[1] >> 3) & 7) == 7
                && ((traits[2] >> 3) & 7) == 7 && ((traits[3] >> 3) & 7) == 7) break;
            ++word;
        }
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
        h.seed(LVL, word, false);
        h.seedDaily(LVL);
        uint256 snap = vm.snapshotState();
        bytes32 referenceTranscript;
        MineFlipGas.Result memory result;
        uint256 calls;
        do {
            vm.cool(address(h));
            vm.cool(ContractAddresses.GAME_WHALE_MODULE);
            vm.recordLogs();
            result = h.runDailyJackpot{gas: 10_000_000}(true, LVL, word, 9_000_000);
            referenceTranscript = _digest(referenceTranscript, vm.getRecordedLogs());
        } while (!result.done && calls++ < 8);
        assertTrue(result.done);
        (uint256 current, uint256 next, uint256 future, uint256 liability, uint256 golden, uint256 tickets) = h.accounting();
        assertEq(current + next + future + liability, 15_000 ether);
        assertGt(future, 5_000 ether, "quadrant passes recycle their exact cost");
        assertTrue(golden & (uint256(1) << 189) != 0, "all-gold solo quadrant arms once");
        bytes32 referenceState = keccak256(abi.encode(current, next, future, liability, golden, tickets));
        assertTrue(vm.revertToState(snap));
        bytes32 splitTranscript;
        calls = 0;
        do {
            vm.cool(address(h));
            vm.cool(ContractAddresses.GAME_WHALE_MODULE);
            vm.recordLogs();
            result = h.runDailyJackpot{gas: 10_000_000}(true, LVL, word, 6_700_000);
            splitTranscript = _digest(splitTranscript, vm.getRecordedLogs());
        } while (!result.done && calls++ < 8);
        assertTrue(result.done);
        assertGt(calls, 0);
        (current, next, future, liability, golden, tickets) = h.accounting();
        assertEq(keccak256(abi.encode(current, next, future, liability, golden, tickets)), referenceState);
        assertEq(splitTranscript, referenceTranscript);
    }
}
