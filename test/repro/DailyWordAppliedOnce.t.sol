// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Production Game with one seam: the same delegatecall into the Advance module that the
///      miner's DailyApply dispatch makes, so a second application can be attempted from the
///      Game's own address and storage.
contract ApplyOnceHost is DegenerusGame {
    function applyAgain() external {
        (bool ok, bytes memory reason) =
            ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(abi.encodeWithSignature("applyDailyWord_g1652()"));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}

/// @title DailyWordAppliedOnce -- a recorded daily word is never applied a second time
/// @notice `applyDailyWord_g1652` records the day's word, settles the day's coinflip, rolls the
///         day's quests and opens the craps bonus day. It reverts `E()` when
///         `_recordedDailyWord(rngRequestDay) != 0`; the miner selects DailyApply only while that
///         word is unrecorded (`_nextMinerAction`), and DailyPhase once it is. The Game exposes no
///         selector for the apply, and the module refuses a call outside the Game's context.
///         A real day is driven to the state right after the apply (lock held, DailyPhase next),
///         where every other precondition of the apply still holds, and the second application
///         is attempted through the Game's own delegatecall.
contract DailyWordAppliedOnceTest is DeployProtocol {
    uint8 private constant STAGE_DAILY_WORD_APPLIED = 18;
    bytes32 private constant ADVANCE = keccak256("Advance(uint8,uint24)");
    bytes32 private constant DAY_RESOLVED = keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)");
    address private constant BUYER = address(0xB0B5);
    address private constant MINER = address(0xA11E);

    bytes private realCode;
    uint24 private day;
    uint256 private applied;
    uint256 private resolved;

    function setUp() public {
        _deployProtocol();
        realCode = address(game).code;
        vm.recordLogs();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(BUYER, 100 ether);
        vm.prank(BUYER);
        game.purchaseOrderFor{value: 0.05 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        _completeDay(0xC0FFEE01);
        (applied, resolved) = (0, 0);
        // Day D: the daily request is out and its word delivered.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) {
            _fulfillPending(0xD0);
            _mineChecked();
        }
        assertTrue(game.rngLocked(), "fixture: day D requested");
        // The daily index advances at the request, so it names the requested day.
        day = game.currentDayView_g542950();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB16B00B5);
        // Smallest calls up to the apply, then one call that admits only the apply.
        for (uint256 i; game.nextMinerAction() != uint8(DegenerusGameStorage.MinerAction.DailyApply); ++i) {
            require(i < 64, "fixture: never reached DailyApply");
            _mineSmallest();
        }
        assertEq(game.rngWordForDay(day), 0, "fixture: word not yet recorded");
        _mineSmallest();
    }

    /// @dev Drive until a daily lock has been taken and released, answering every request
    ///      (a mid-day request can precede the daily one).
    function _completeDay(uint256 word) private {
        bool sawLock;
        for (uint256 i; i < 128 && !(sawLock && !game.rngLocked()); ++i) {
            _fulfillPending(word);
            _mineChecked();
            sawLock = sawLock || game.rngLocked();
        }
        assertTrue(sawLock && !game.rngLocked(), "fixture: day completed");
        _finishReadConsumers();
    }

    function _fulfillPending(uint256 word) private {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(id);
        if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(word, id))));
    }

    function _mineChecked() private {
        vm.prank(MINER);
        (bool ok, bytes memory err) = address(game).call{gas: 16_000_000}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        if (!ok) assembly ("memory-safe") { revert(add(err, 32), mload(err)) }
        _countLogs();
    }

    function _mineCounted(uint256 gas) private returns (bool ok) {
        vm.prank(MINER);
        (ok,) = address(game).call{gas: gas}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        // Recorded logs include those of a reverted call; count only committed work.
        if (ok) _countLogs();
        else vm.getRecordedLogs();
    }

    function _mineSmallest() private {
        for (uint256 g = 300_000; g <= 16_000_000; g += 100_000) {
            if (_mineCounted(g)) return;
        }
        revert("fixture: no gas admitted the next action");
    }

    function _countLogs() private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) && logs[i].emitter != address(coinflip)) continue;
            if (logs[i].topics[0] == ADVANCE) {
                (uint8 stage,) = abi.decode(logs[i].data, (uint8, uint24));
                if (stage == STAGE_DAILY_WORD_APPLIED) ++applied;
            } else if (logs[i].topics[0] == DAY_RESOLVED && uint256(logs[i].topics[1]) == day) {
                ++resolved;
            }
        }
    }

    /// @notice State after the apply: the word is recorded, the day is still locked and every
    ///         precondition of the apply other than the recorded-word check still holds.
    function test_RecordedWordStateIsTheApplyFrontier() public view {
        assertTrue(game.rngWordForDay(day) != 0, "the apply recorded the word");
        assertTrue(game.rngLocked(), "the daily lock is still held");
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.DailyPhase),
            "the miner selects DailyPhase, never DailyApply, once the word is recorded");
        assertEq(applied, 1, "exactly one apply so far");
    }

    /// @notice The second application through the Game's own delegatecall reverts `E()` and
    ///         changes nothing: not the recorded word, not the day's coinflip result.
    function test_SecondApplicationOfARecordedWordReverts() public {
        uint256 word = game.rngWordForDay(day);
        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(day);
        assertTrue(reward != 0, "fixture: day D coinflip settled by the first apply");
        vm.etch(address(game), type(ApplyOnceHost).runtimeCode);
        vm.expectRevert(bytes4(keccak256("E()")));
        ApplyOnceHost(payable(address(game))).applyAgain();
        vm.etch(address(game), realCode);
        assertEq(game.rngWordForDay(day), word, "recorded word unchanged");
        (uint16 reward2, bool win2) = coinflip.getCoinflipDayResult(day);
        assertEq(reward2, reward, "coinflip reward unchanged");
        assertEq(win2, win, "coinflip result unchanged");
    }

    /// @notice No other door reaches the apply: the Game has no such selector and the module
    ///         refuses any call outside the Game's storage context.
    function test_NoExternalDoorReachesTheApply() public {
        (bool ok,) = address(game).call(abi.encodeWithSignature("applyDailyWord_g1652()"));
        assertFalse(ok, "the Game exposes no apply selector");
        vm.prank(address(game));
        (ok,) = ContractAddresses.GAME_ADVANCE_MODULE.call(abi.encodeWithSignature("applyDailyWord_g1652()"));
        assertFalse(ok, "the module refuses a direct call, even from the Game's address");
    }

    /// @notice Driving the rest of the day and the next day through the engine applies day D's
    ///         word exactly once and resolves day D's coinflip exactly once.
    function test_EngineAppliesEachDailyWordOnce() public {
        for (uint256 i; i < 256 && game.rngLocked(); ++i) _mineSmallest();
        assertFalse(game.rngLocked(), "day D completed");
        _finishReadConsumers();
        _countLogs();
        assertEq(applied, 1, "day D applied once");
        assertEq(resolved, 1, "day D coinflip resolved once");
        uint256 word = game.rngWordForDay(day);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _completeDay(0xD00D);
        assertEq(applied, 2, "the next day applies its own word once");
        assertEq(resolved, 1, "day D never resolved again");
        assertEq(game.rngWordForDay(day), word, "day D word unchanged by the next day");
    }
}
