// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract ColdTerminalSeeder is DegenerusGame, BucketSeed {
    /// @dev Past the purchase deadline with nothing in flight. `sealedAge` 1 is the start of a
    ///      caught-up day (the deadline ending); a longer stretch has also fired the deadman.
    function seed(uint256 word, uint24 sealedAge) external {
        uint24 day = _simulatedDayIndex();
        level = 9;
        purchaseStartDay = day - 121;
        dailyIdx = day - sealedAge;
        levelPrizePool[9] = 1000 ether;
        ticketsFullyProcessed = true;
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(10, traits[q], 5000, uint160(0x7E000000 + uint256(q) * 0x100000));
        }
        for (uint256 i; i < 30; ++i) {
            address owner = address(uint160(0xD3170000 + i));
            deityPassOwners.push(owner);
            deityPassPricePaid[owner] = 20 ether;
        }
    }
}

/// @dev The normal ending runs in separate transactions: the first latches the terminal level and
///      affiliate and sends the ending's own terminal request; once answered, the next applies the
///      word (deriving every skipped day); the one after pays out. setUp runs everything before
///      the measured step, so storage the test body touches is still cold.
abstract contract ColdTerminalFixture is DeployProtocol {
    uint256 internal constant WORD = uint256(keccak256("cold-terminal-full-payout")) | 1;

    /// @dev True: the test body applies the delivered terminal word, then pays out. False: setUp
    ///      also applies it, so the payout is the test body's first (cold) transaction.
    function _fresh() internal pure virtual returns (bool);

    /// @dev Days since the last sealed day. 1 = caught up; a longer stretch is the deadman's
    ///      ending, whose terminal word also derives every skipped day (at most 31).
    function _sealedAge() internal pure virtual returns (uint24) {
        return 1;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, WORD, 399);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ColdTerminalSeeder).runtimeCode);
        ColdTerminalSeeder(payable(address(game))).seed(WORD, _sealedAge());
        vm.etch(address(game), original);
        vm.prank(address(0xAFF1));
        affiliate.createAffiliateCode(bytes32("TERMINAL"), 0);
        vm.prank(address(game));
        affiliate.payAffiliate(1000 ether, bytes32("TERMINAL"), address(0xAFF2), 10, true, 0);
        vm.deal(address(game), 5000 ether);
        _requestTerminalWord();
        if (!_fresh()) _applyTerminalWord();
    }

    function _check() internal {
        if (_fresh()) _applyTerminalWord();
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: 16_777_216 - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 winners;
        uint256 refunds;
        uint256 rngApplied;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics[0];
            if (topic == keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)")) ++winners;
            if (topic == keccak256("DeityPassRefundsSettled(uint256)")) refunds = abi.decode(logs[i].data, (uint256));
            if (topic == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++rngApplied;
        }
        emit log_named_uint("full_cold_terminal_including_intrinsic", used);
        emit log_named_uint("terminal_ETH_awards", winners);
        assertTrue(game.gameOver(), "terminal payout must complete");
        assertEq(winners, 305, "all terminal draw slots must execute");
        assertEq(refunds, 600 ether, "30 paid refunds; genesis has no refund basis");
        assertEq(rngApplied, 0, "the payout runs on the recorded terminal word");
        assertEq(game.claimableWinningsOf(address(0xAFF1)), 88 ether, "affiliate gets 2% after refunds");
        assertLt(used, 15_000_000, "terminal transaction exceeds review target");
    }

    /// @dev The ending's first transaction sends its own terminal request; the coordinator
    ///      answers it with the word the winning buckets were seeded for.
    function _requestTerminalWord() private {
        uint256 before = mockVRF.lastRequestId();
        game.advanceGame();
        uint256 id = mockVRF.lastRequestId();
        assertGt(id, before, "the ending sends its own terminal request");
        assertFalse(game.gameOver(), "the payout waits for the terminal word");
        assertEq(game.rngWordForDay(game.currentDayView()), 0, "no word before the request is answered");
        mockVRF.fulfillRandomWords(id, WORD);
    }

    /// @dev A delivered terminal word is applied in its own transaction: the word itself, the
    ///      derived words of every skipped day (each settling that day's coinflips), the
    ///      terminal day's coinflips, any pending redemption and the reserved lootbox index.
    function _applyTerminalWord() private {
        uint24 day = game.currentDayView();
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: 16_777_216 - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 applied;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++applied;
        }
        uint24 gap = _sealedAge() - 1;
        if (gap > 31) gap = 31;
        emit log_named_uint("terminal_word_apply_including_intrinsic", used);
        emit log_named_uint("terminal_word_derived_days", gap);
        assertFalse(game.gameOver(), "the payout takes its own transaction");
        assertEq(game.rngWordForDay(day), WORD, "terminal word recorded");
        assertEq(applied, uint256(gap) + 1, "every skipped day derived, then the terminal day");
        if (gap != 0) {
            uint24 firstGap = day - _sealedAge() + 1;
            assertEq(
                game.rngWordForDay(firstGap),
                uint256(keccak256(abi.encodePacked(WORD, firstGap))),
                "skipped days derive from the terminal word"
            );
        }
        assertLt(used, 15_000_000, "terminal word application exceeds review target");
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
///      so the terminal word derives the capped 31 skipped days in the same transaction.
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
