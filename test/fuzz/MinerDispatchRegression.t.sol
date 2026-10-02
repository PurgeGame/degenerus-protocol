// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract MinerDispatchHarness is DegenerusGameMinerModule {
    function seed(bool ticketsDone, bool humanDone, bool nextDayDue) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = nextDayDue ? today - 1 : today;
        _afkingResetDay = dailyIdx;
        purchaseStartDay = today;
        level = 10;
        ticketsFullyProcessed = ticketsDone;
        humanReadComplete = humanDone;
        rngFlagsAndNudges = uint16(1) << 15;
        rngWordCurrent = 1234;
        rngRequestTime = uint48(block.timestamp);
        _lrWrite(LR_WORK_READY_SHIFT, LR_WORK_READY_MASK, block.timestamp);
        if (!ticketsDone) _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
    }

    function state() external view returns (
        bool complete, bool ticketsDone, bool humanDone, uint32 ticketPos, uint48 boxPos,
        uint24 requestDay, bool active, uint256 pendingBoxes
    ) {
        return (_rngComplete(), ticketsFullyProcessed, humanReadComplete, ticketCursor,
            boxCursor, rngRequestDay, _rngRequestActive(), _pendingBoxCount);
    }
}

/// @dev Identical ABI to the trusted worker, with deliberate malformed-return cases.
contract DispatchTicketWorker is DegenerusGameStorage {
    error RepeatedTicketDispatch();
    uint8 private immutable mode;

    constructor(uint8 mode_) { mode = mode_; }

    function runTicketWork(uint24, uint256) external returns (MineFlipGas.Result memory) {
        if (ticketsFullyProcessed || ticketCursor != 0) revert RepeatedTicketDispatch();
        if (mode >= 1 && mode <= 3) {
            _pendingBoxCount = 123;
            uint8 variant = mode;
            assembly ("memory-safe") {
                let ptr := mload(0x40)
                mstore(ptr, 0)
                mstore(add(ptr, 32), 1)
                mstore(add(ptr, 64), 0)
                switch variant
                case 1 { return(ptr, 64) }
                case 2 { mstore(ptr, 2) }
                case 3 { mstore(add(ptr, 32), 2) }
                return(ptr, 96)
            }
        }
        if (mode == 4) {
            ++ticketCursor;
            return MineFlipGas.Result(true, false, 1);
        }
        if (mode == 5) return MineFlipGas.Result(false, false, type(uint256).max);
        if (mode == 6) revert MineFlipGas.WorkGasBound();
        return MineFlipGas.Result(false, true, type(uint256).max);
    }
}

contract DispatchAfkingWorker is DegenerusGameStorage {
    error WrongConsumerOrder();

    function runHumanBoxWork(uint256) external returns (MineFlipGas.Result memory) {
        if (!ticketsFullyProcessed || humanReadComplete || _rngComplete()
            || _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert WrongConsumerOrder();
        humanReadComplete = true;
        boxCursor = 17;
        return MineFlipGas.Result(true, true, 1);
    }

    function runSubscriberWork(uint24 day, uint256) external returns (MineFlipGas.Result memory) {
        if (!_rngComplete() || day != _afkingResetDay || day <= dailyIdx || subsFullyProcessed) {
            revert WrongConsumerOrder();
        }
        subsFullyProcessed = true;
        return MineFlipGas.Result(true, true, 1);
    }
}

contract DispatchRequestWorker is DegenerusGameStorage {
    error RequestBeforeCompletion();

    function requestDailyRng(uint24 day) external {
        if (!_rngComplete() || !subsFullyProcessed || day != _afkingResetDay || day <= dailyIdx) {
            revert RequestBeforeCompletion();
        }
        rngRequestDay = day;
        rngWordCurrent = RNG_WORD_WAITING;
        rngLockedFlag = true;
        _setRngComplete(false);
        _setRngRequestActive(true);
    }
}

contract MinerDispatchRegressionTest is Test {
    MinerDispatchHarness private game;

    function setUp() public {
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 27) * 1 days + 84_000);
        vm.fee(1 gwei);
        vm.etch(ContractAddresses.GAME, address(new MinerDispatchHarness()).code);
        game = MinerDispatchHarness(ContractAddresses.GAME);
        vm.etch(ContractAddresses.GAME_AFKING_MODULE, address(new DispatchAfkingWorker()).code);
        vm.etch(ContractAddresses.GAME_RNG_MODULE, address(new DispatchRequestWorker()).code);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(false));
    }

    function _tickets(uint8 mode) private {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DispatchTicketWorker(mode)).code);
        game.seed(false, false, false);
    }

    function _assertRolledBack() private view {
        (bool complete, bool ticketsDone, bool humanDone, uint32 ticketPos, uint48 boxPos,,, uint256 pending) = game.state();
        assertFalse(complete);
        assertFalse(ticketsDone);
        assertFalse(humanDone);
        assertEq(ticketPos, 0);
        assertEq(boxPos, 0);
        assertEq(pending, 0, "malformed worker effects must roll back");
    }

    function test_ResultStillRequiresTheThirdAbiWord() public {
        _tickets(1);
        vm.expectRevert();
        game.mineFlip();
        _assertRolledBack();
    }

    function test_ResultStillRejectsNoncanonicalProgressBool() public {
        _tickets(2);
        vm.expectRevert();
        game.mineFlip();
        _assertRolledBack();
    }

    function test_ResultStillRejectsNoncanonicalDoneBool() public {
        _tickets(3);
        vm.expectRevert();
        game.mineFlip();
        _assertRolledBack();
    }

    function test_DoneWithoutProgressNormalizesTicketsAndReselectsHumanWork() public {
        _tickets(0);
        game.mineFlip();
        (bool complete, bool ticketsDone, bool humanDone,, uint48 boxPos,,,) = game.state();
        assertTrue(complete, "all read consumers must certify in the same call");
        assertTrue(ticketsDone);
        assertTrue(humanDone);
        assertEq(boxPos, 17, "the next worker must replace the initial ticket action");
    }

    function test_CertificationContinueReselectsPreparationThenRequest() public {
        game.seed(true, true, true);
        game.mineFlip();
        (bool complete,,,,, uint24 requestDay, bool active,) = game.state();
        assertFalse(complete, "the new commitment invalidates the completed read certificate");
        assertTrue(active);
        assertEq(requestDay, 28, "certification must continue through preparation to the new request");
    }

    function test_PartialWorkerStopsBeforeAnyLaterConsumer() public {
        _tickets(4);
        game.mineFlip();
        (bool complete, bool ticketsDone, bool humanDone, uint32 ticketPos, uint48 boxPos,,,) = game.state();
        assertFalse(complete);
        assertFalse(ticketsDone);
        assertFalse(humanDone);
        assertEq(ticketPos, 1);
        assertEq(boxPos, 0);
    }

    function test_NoProgressResultDoesNotDispatchOrNormalizeAnythingElse() public {
        _tickets(5);
        vm.recordLogs();
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        game.mineFlip();
        assertEq(vm.getRecordedLogs().length, 0, "a no-op must not emit paid work");
        _assertRolledBack();
    }

    function test_WorkerGasBoundFailureStillBubbles() public {
        _tickets(6);
        vm.expectRevert(MineFlipGas.WorkGasBound.selector);
        game.mineFlip();
        _assertRolledBack();
    }
}
