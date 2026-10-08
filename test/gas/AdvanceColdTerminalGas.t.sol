// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract ColdTerminalSeeder is DegenerusGame, BucketSeed {
    function terminalPaidSlot() external pure returns (bytes32 slot) {
        assembly ("memory-safe") { slot := gameOverStatePacked.slot }
    }

    /// @dev Past the purchase deadline with nothing in flight. `sealedAge` 1 is the start of a
    ///      caught-up day (the deadline ending); a longer stretch has also fired the deadman.
    function seed(uint256 word, uint24 sealedAge) external {
        uint24 day = _simulatedDayIndex();
        level = 9;
        purchaseStartDay = day - 121;
        dailyIdx = day - sealedAge;
        levelPrizePool[9] = 1000 ether;
        ticketsFullyProcessed = true;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(10, traits[q], 5000, uint160(0x7E000000 + uint256(q) * 0x100000));
        }
        for (uint256 i; i < 30; ++i) {
            address owner = address(uint160(0xD3170000 + i));
            _seedDeity(owner);
            deityPassPricePaid[_seedWallet(owner)] = 20 ether;
        }
    }
}

/// @dev The normal ending runs in separate transactions: the first latches the terminal level
///      and sends the ending's own terminal request; once answered, the next applies the
///      word and settles capped coinflip backfill; later calls finish the payout checkpoints.
///      setUp runs everything before the measured step, so the test body starts cold.
abstract contract ColdTerminalFixture is DeployProtocol {
    uint256 internal constant WORD = uint256(keccak256("cold-terminal-full-payout")) | 1;
    bytes32 private terminalStateSlot;

    /// @dev True: the test body applies the delivered terminal word, then pays out. False: setUp
    ///      also applies it, so the payout is the test body's first (cold) transaction.
    function _fresh() internal pure virtual returns (bool);

    /// @dev Days since the last sealed day. 1 = caught up; a longer stretch is the deadman's
    ///      ending, whose terminal word also settles at most 31 skipped coinflip days.
    function _sealedAge() internal pure virtual returns (uint24) {
        return 1;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        uint24 lastSealedDay = game.currentDayView() - _sealedAge();
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, WORD, lastSealedDay);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ColdTerminalSeeder).runtimeCode);
        terminalStateSlot = ColdTerminalSeeder(payable(address(game))).terminalPaidSlot();
        ColdTerminalSeeder(payable(address(game))).seed(WORD, _sealedAge());
        vm.etch(address(game), original);
        vm.deal(address(game), 5000 ether);
        _requestTerminalWord();
        if (!_fresh()) _applyTerminalWord();
    }

    function _check() internal {
        assertGt(ContractAddresses.GAME_MINER_MODULE.code.length, 0, "miner deployment survives setup");
        if (_fresh()) _applyTerminalWord();
        uint256 winners;
        uint256 awarded;
        uint256 refunds;
        uint256 rngApplied;
        uint256 largestCall;
        uint256 totalGas;
        uint256 calls;
        while (!_terminalPaid() && calls < 8) {
            _coolTerminal();
            vm.recordLogs();
            uint256 before = gasleft();
            game.mineFlip{gas: 11_500_000 - 21_192}(0);
            uint256 used = before - gasleft() + 21_192;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length == 0) continue;
                bytes32 topic = logs[i].topics[0];
                if (topic == keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)")) {
                    ++winners;
                    (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                    awarded += amount;
                }
                if (topic == keccak256("DeityPassRefundsSettled(uint256)")) refunds += abi.decode(logs[i].data, (uint256));
                if (topic == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++rngApplied;
            }
            if (used > largestCall) largestCall = used;
            totalGas += used;
            ++calls;
            // This fixture chooses an 11.5M transaction envelope; the protocol caps steps, not transactions.
            assertLt(used, 11_500_000, "terminal checkpoint transaction exceeds review target");
        }
        emit log_named_uint("largest_cold_terminal_call_including_intrinsic", largestCall);
        emit log_named_uint("full_cold_terminal_including_intrinsic", totalGas);
        emit log_named_uint("terminal_payout_calls", calls);
        emit log_named_uint("terminal_ETH_awards", winners);
        assertTrue(game.gameOver(), "terminal ending must be latched");
        assertTrue(_terminalPaid(), "all terminal payout checkpoints must complete");
        assertEq(winners, 305, "all terminal draw slots must execute");
        assertEq(refunds, 600 ether, "30 paid refunds; genesis has no refund basis");
        assertEq(rngApplied, 0, "the payout runs on the recorded terminal word");
        assertApproxEqAbs(awarded, 4400 ether, 305, "the terminal cohort receives the pot after refunds");
    }

    function _terminalPaid() private view returns (bool) {
        return (uint256(vm.load(address(game), terminalStateSlot)) >> 48) & 0xff != 0;
    }

    function _coolTerminal() private {
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_GAMEOVER_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(address(mockStETH));
        vm.cool(address(coin));
        vm.cool(address(coinflip));
        vm.cool(address(sdgnrs));
        vm.cool(address(gnrus));
        vm.cool(address(affiliate));
    }

    /// @dev The ending's first transaction sends its own terminal request; the coordinator
    ///      answers it with the word the winning buckets were seeded for.
    function _requestTerminalWord() private {
        uint256 before = mockVRF.lastRequestId();
        game.mineFlip(0);
        uint256 id = mockVRF.lastRequestId();
        assertGt(id, before, "the ending sends its own terminal request");
        assertFalse(game.gameOver(), "the payout waits for the terminal word");
        assertEq(game.rngWordForDay(game.currentDayView()), 0, "no word before the request is answered");
        mockVRF.fulfillRandomWords(id, WORD);
    }

    /// @dev Applying the terminal word records its day and reserved lootbox index, and settles
    ///      the capped skipped coinflip days using the original win bits and 100% win rewards.
    function _applyTerminalWord() private {
        uint24 day = game.currentDayView();
        // Cooling newly created accounts during setUp can discard their deployment in Foundry's
        // persisted setup state. The recorded fixture starts its measured work in the test body;
        // only fresh-word fixtures need explicit cooling before this application measurement.
        if (_fresh()) _coolTerminal();
        vm.recordLogs();
        uint256 before = gasleft();
        game.mineFlip{gas: 11_500_000 - 21_192}(0);
        uint256 used = before - gasleft() + 21_192;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 applied;
        uint256 gapResults;
        uint24 gap = _sealedAge() - 1;
        if (gap > 31) gap = 31;
        uint24 firstGap = day - _sealedAge() + 1;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++applied;
            if (logs[i].emitter == address(coinflip)
                && logs[i].topics[0] == keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)")) {
                uint24 resolvedDay = uint24(uint256(logs[i].topics[1]));
                if (resolvedDay >= firstGap && resolvedDay < firstGap + gap) {
                    (bool win, uint16 reward,) = abi.decode(logs[i].data, (bool, uint16, uint128));
                    assertEq(reward, 100, "every backfilled flip uses double-or-nothing rewards");
                    assertEq(win, (WORD >> (1 + resolvedDay - firstGap)) & 1 != 0, "gap win bits stay pinned");
                    ++gapResults;
                }
            }
        }
        emit log_named_uint("terminal_word_apply_including_intrinsic", used);
        emit log_named_uint("terminal_coinflip_backfill_days", gap);
        assertFalse(game.gameOver(), "the payout takes its own transaction");
        assertEq(game.rngWordForDay(day), WORD, "terminal word recorded");
        assertEq(applied, 1, "only the terminal day emits DailyRngApplied");
        assertEq(gapResults, gap, "every capped gap day must settle exactly once");
        for (uint24 i; i < gap; ++i) {
            bool expectedWin = (WORD >> (1 + i)) & 1 != 0;
            (uint16 reward, bool win) = coinflip.getCoinflipDayResult(firstGap + i);
            assertEq(win, expectedWin, "stored gap outcomes keep the original word bits");
            assertEq(reward, expectedWin ? 100 : 1, "stored gap payout or loss sentinel");
        }
        assertLt(used, 11_500_000, "terminal word application exceeds review target");
    }
}

/// @dev The payout transaction, cold, on the ending's own terminal word already applied in setUp.
contract AdvanceColdTerminalRecorded is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) {
        return false;
    }

    function test_ColdTerminalWithAllRefundsAndAwards() public {
        _check();
    }
}

/// @dev The delivered terminal word's application, cold, then the payout.
contract AdvanceColdTerminalFresh is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) {
        return true;
    }

    function test_ColdTerminalWithFreshWordRefundsAndAwards() public {
        _check();
    }
}

/// @dev The widest terminal-word application: the deadman's ending reached long after it fired,
///      so the terminal word settles the capped 31 skipped coinflip days in the same transaction.
contract AdvanceColdTerminalFreshLongGap is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) {
        return true;
    }

    function _sealedAge() internal pure override returns (uint24) {
        return 60;
    }

    function test_ColdTerminalAfterLongGapRefundsAndAwards() public {
        _check();
    }
}
