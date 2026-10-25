// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;


import {NativeGasExport} from "../helpers/NativeGasExport.sol";
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

    /// @dev Thirty completed logical purchase rounds with a recent completion. Extra wall
    ///      windows model accumulated harmless delays across prior rounds.
    function seed(uint256 word, uint24 extraWallWindows) external {
        uint24 day = _wallDay();
        level = 9;
        dailyIdx = day - 1 - extraWallWindows;
        purchaseStartDay = dailyIdx - 30;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
        _setLevelPrizePool(9, 1000 ether);
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
///      (VRF alive, so the loan book settles next), the second settles the empty loan book, the
///      third sends the ending's own terminal request; once answered, the next applies the
///      word and closes its single committed flip cohort; later calls finish the payout checkpoints.
///      setUp runs everything before the measured step, so the test body starts cold.
abstract contract ColdTerminalFixture is DeployProtocol, NativeGasExport {
    uint256 internal constant WORD = uint256(keccak256("cold-terminal-full-payout")) | 1;
    bytes32 private terminalStateSlot;

    /// @dev True: the test body applies the delivered terminal word, then pays out. False: setUp
    ///      also applies it, so the payout is the test body's first (cold) transaction.
    function _fresh() internal pure virtual returns (bool);

    /// @dev Accumulated extra reset windows across prior logical rounds, independent of
    ///      the recent completion timestamp.
    function _extraWallWindows() internal pure virtual returns (uint24) {
        return 0;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        uint24 lastSealedDay = game.currentWallDayView() - 1 - _extraWallWindows();
        _seedLogicalFixtureDay(lastSealedDay);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, WORD, lastSealedDay);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ColdTerminalSeeder).runtimeCode);
        terminalStateSlot = ColdTerminalSeeder(payable(address(game))).terminalPaidSlot();
        ColdTerminalSeeder(payable(address(game))).seed(WORD, _extraWallWindows());
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
            uint256 nativeSnapshot = vm.snapshotState();
            vm.recordLogs();
            uint256 before = gasleft();
            game.mineRun{gas: 11_500_000 - 21_192}(0);
            uint256 used = before - gasleft() + 21_192;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            _exportTerminal(nativeSnapshot, string.concat("payout-", vm.toString(calls)));
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length == 0) continue;
                bytes32 topic = logs[i].topics[0];
                if (topic == keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)")) {
                    ++winners;
                    (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                    awarded += amount;
                }
                if (topic == keccak256("DeityPassRefundsSettled(uint256)")) refunds += abi.decode(logs[i].data, (uint256));
                if (topic == keccak256("DailyRngApplied(uint24,uint256,uint256)")) ++rngApplied;
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

    function _exportTerminal(uint256 snapshot, string memory stage) private {
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length == 0) return;
        assertTrue(vm.revertToState(snapshot));
        string memory label = string.concat("terminal-", vm.toString(_extraWallWindows()), "-", _fresh() ? "fresh-" : "recorded-", stage);
        this.exportNativeFixture(label, address(this), address(game), abi.encodeCall(game.mineRun, (uint32(0))));
        game.mineRun{gas: 11_500_000 - 21_192}(0);
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
        game.mineRun(0); // decision
        game.mineRun(0); // the (empty) loan book
        assertEq(mockVRF.lastRequestId(), before, "no request before the loan book is settled");
        uint256 requestSnapshot = vm.snapshotState();
        game.mineRun(0);
        uint256 id = mockVRF.lastRequestId();
        assertGt(id, before, "the ending sends its own terminal request");
        assertFalse(game.gameOver(), "the payout waits for the terminal word");
        assertEq(game.rngWordForDay(game.currentDayView_g542950() + 1), 0, "no word before the request is answered");
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            uint256 post = vm.snapshotState();
            assertTrue(vm.revertToState(requestSnapshot));
            this.exportNativeFixture(string.concat("terminal-request-", vm.toString(_extraWallWindows()), _fresh() ? "-fresh" : "-recorded"),
                address(this), address(game), abi.encodeCall(game.mineRun, (uint32(0))));
            assertTrue(vm.revertToState(post));
            vm.deleteStateSnapshot(post);
        }
        vm.deleteStateSnapshot(requestSnapshot);
        mockVRF.fulfillRandomWords(id, WORD);
    }

    /// @dev Applying the terminal word records its logical cohort and reserved read index.
    function _applyTerminalWord() private {
        uint24 day = game.currentDayView_g542950() + 1;
        // Cooling newly created accounts during setUp can discard their deployment in Foundry's
        // persisted setup state. The recorded fixture starts its measured work in the test body;
        // only fresh-word fixtures need explicit cooling before this application measurement.
        if (_fresh()) _coolTerminal();
        uint256 nativeSnapshot = vm.snapshotState();
        vm.recordLogs();
        uint256 before = gasleft();
        game.mineRun{gas: 11_500_000 - 21_192}(0);
        uint256 used = before - gasleft() + 21_192;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (_fresh()) _exportTerminal(nativeSnapshot, "apply");
        this.assertTerminalApplication(logs, day, used);
        assertTrue(vm.deleteStateSnapshot(nativeSnapshot));
    }

    function assertTerminalApplication(Vm.Log[] calldata logs, uint24 day, uint256 used) external {
        require(msg.sender == address(this), "terminal assertion self-call");
        uint256 applied;
        uint256 results;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256("DailyRngApplied(uint24,uint256,uint256)")) ++applied;
            if (logs[i].emitter == address(coinflip)
                && logs[i].topics[0] == keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)")) {
                ++results;
            }
        }
        emit log_named_uint("terminal_word_apply_including_intrinsic", used);
        emit log_named_uint("terminal_coinflip_results", results);
        assertFalse(game.gameOver(), "the payout takes its own transaction");
        assertEq(game.rngWordForDay(day), WORD, "terminal word recorded");
        assertEq(applied, 1, "only the terminal day emits DailyRngApplied");
        assertEq(results, 0, "terminal entry settles no coinflip day");
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

/// @dev Calendar time can exceed logical time across many delayed rounds; terminal
///      application still resolves only its single legitimate cohort.
contract AdvanceColdTerminalFreshLongGap is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) {
        return true;
    }

    function _extraWallWindows() internal pure override returns (uint24) {
        return 60;
    }

    function test_ColdTerminalAfterLongGapRefundsAndAwards() public {
        _check();
    }
}
