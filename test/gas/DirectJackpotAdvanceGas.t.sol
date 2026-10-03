// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";

contract DirectAdvanceSeeder is DegenerusGame, BucketSeed {
    function seed(uint256 word) external {
        uint24 day = _simulatedDayIndex();
        level = 41;
        purchaseStartDay = day - 2;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        jackpotCounter = 1;
        jackpotFlags = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        humanReadComplete = true;
        _afkingResetDay = day;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        rngRequestDay = day;
        rngWordCurrent = word;
        _setRngComplete(false);
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        _recordDailyRng(day, word);
        dailyJackpotCoinTicketsPending = true;
        dailyTicketBudgetsPacked = 1 | (uint256(480 * 4) << 8);
        _setPrizePools(500 ether, 500 ether);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        for (uint8 q; q < 4; ++q) _seedBucketDistinct(41, traits[q], 128, uint160(0x10000 + uint256(q) * 0x10000));
        _setTicketBufferLevel(42);
    }
    function inspect() external view returns (bool pending, uint256 entries, uint256 queued) {
        pending = dailyJackpotCoinTicketsPending;
        for (uint256 t; t < 256; ++t) entries += _bucketLength(42, t);
        queued = _ticketQueueLength(_tqWriteKey(42));
    }
}

contract DirectJackpotAdvanceGasTest is DeployProtocol {
    bytes private gameCode;
    bytes32 private constant WIN = keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 10 days);
        gameCode = address(game).code;
        vm.etch(address(game), type(DirectAdvanceSeeder).runtimeCode);
        DirectAdvanceSeeder(payable(address(game))).seed(0xAC4DE45EDBEEF);
        vm.etch(address(game), gameCode);
        vm.deal(address(game), 1000 ether);
    }
    function _run(uint256 supplied) private {
        uint256 calls;
        uint256 wins;
        uint256 maxGas;
        bool pending = true;
        while (pending && calls < 30) {
            vm.cool(address(game));
            vm.cool(ContractAddresses.GAME_MINER_MODULE);
            vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
            vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
            vm.cool(ContractAddresses.GAME_TICKET_MODULE);
            vm.recordLogs();
            uint256 before = gasleft();
            game.mineFlip{gas: supplied}();
            uint256 used = before - gasleft() + 21_064;
            if (used > maxGas) maxGas = used;
            assertLt(used, 10_000_000);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) if (logs[j].topics[0] == WIN) {
                (,uint8 count,,,) = abi.decode(logs[j].data, (uint16,uint8,uint32,uint256[4],uint256[4]));
                wins += count;
            }
            vm.etch(address(game), type(DirectAdvanceSeeder).runtimeCode);
            uint256 entries;
            uint256 queued;
            (pending, entries, queued) = DirectAdvanceSeeder(payable(address(game))).inspect();
            assertEq(queued, 0, "real engine uses direct delivery");
            if (!pending) assertEq(entries, 480 * 4);
            vm.etch(address(game), gameCode);
            ++calls;
        }
        assertFalse(pending);
        assertEq(wins, 96);
        assertGt(calls, 1, "engine resumes a partial ticket leg");
        emit log_named_uint("real mineFlip calls", calls);
        emit log_named_uint("maximum mineFlip gas including intrinsic", maxGas);
    }
    function test_RealMineFlipUnderTenMillion() public { _run(9_500_000); }
    function test_RealMineFlipSmallerCalls() public { _run(6_500_000); }
}
