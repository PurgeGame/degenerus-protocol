// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Test} from "forge-std/Test.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract TerminalCoordinatorFixture {
    uint256 public calls;
    uint8 public mode;
    error Refused();
    function setMode(uint8 value) external { mode = value; }
    function requestRandomWords(VRFRandomWordsRequest calldata) external returns (uint256) {
        if (mode == 1) revert Refused();
        if (mode == 2) assembly ("memory-safe") { invalid() }
        return ++calls;
    }
}

contract TerminalCoinflipFixture {
    uint256 public settlements;
    uint24 public settledDay;
    function getCoinflipDayResult(uint24) external pure returns (uint16, bool) { return (0, false); }
    function processCoinflipPayouts(uint8, uint256, uint24 day) external { ++settlements; settledDay = day; }
    function processCoinflipGap(uint256, uint24, uint24) external {}
}

/// @dev Answers the payout's game-over hooks and balance reads with nothing.
contract TerminalSinkFixture {
    uint256 public burns;
    function burnAtGameOver() external { ++burns; }
    function tombstoneAtGameOver() external { ++burns; }
    function balanceOf(address) external pure returns (uint256) { return 0; }
    function closeRedemptionBatch(uint256) external pure returns (uint256) { return 0; }
    function resolveTerminalRedemptions() external pure {}
}

/// @dev Drives the live terminal worker (`runGameOverAdvance`, mineFlip's Terminal stage) on a
///      latched normal ending whose prior day sealed with a word.
contract TerminalRngCheckpointHarness is DegenerusGameGameOverModule {
    function seed(address coordinator) external returns (uint24 priorDay) {
        priorDay = _simulatedDayIndex();
        dailyIdx = priorDay;
        level = 10;
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
        _setRngTerminal();
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        rngWordCurrent = 777;
        rngRequestDay = 0;
        rngRequestTime = 0;
        _recordDailyRng(priorDay, 777);
        vrfCoordinator = IVRFCoordinator(coordinator);
    }
    function deliver(uint256 word) external { rngWordCurrent = word; }
    function identity() external view returns (uint24, uint48, bool, bool) {
        return (rngRequestDay, rngRequestTime, _rngRequestActive(), _rngSessionPublished());
    }
    function appliedAt() external view returns (uint48) { return lastVrfProcessedTimestamp; }
    function dayWord(uint24 day) external view returns (uint256) { return _recordedDailyWord(day); }
    function dead() external view returns (bool) { return _vrfDead(); }
}

contract TerminalRngCheckpointsTest is Test {
    TerminalRngCheckpointHarness private h;
    TerminalCoordinatorFixture private vrf;
    uint24 private priorDay;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 100 days);
        h = new TerminalRngCheckpointHarness();
        vrf = new TerminalCoordinatorFixture();
        priorDay = h.seed(address(vrf));
        vm.etch(ContractAddresses.COINFLIP, type(TerminalCoinflipFixture).runtimeCode);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("closeRedemptionBatch(uint256)"), abi.encode(uint256(0)));
    }

    /// @dev One terminal call at level 10 on `day`, `callGas` as its gas and allowance.
    function _advance(uint24 day, uint256 callGas) private returns (bool progressed) {
        (,,, progressed) = h.runGameOverAdvance{gas: callGas}(day, 10, callGas);
    }

    function test_LowGasAttemptDoesNotArmRefusalTimerOrReplacePriorWord() public {
        assertFalse(_advance(priorDay, 1_000_000), "a low-gas call admits no request");
        (uint24 day, uint48 at, bool active, bool published) = h.identity();
        assertEq(day, 0);
        assertEq(at, 0);
        assertFalse(active);
        assertTrue(published);
        assertEq(vrf.calls(), 0);
        assertEq(h.dayWord(priorDay), 777);
    }

    function test_TerminalApplicationStaysPinnedAcrossMidnightAndDoesNotRepeat() public {
        assertTrue(_advance(priorDay, 4_000_000));
        assertEq(vrf.calls(), 1, "the terminal request went out");
        (uint24 day, uint48 at,,) = h.identity();
        assertEq(day, priorDay + 1, "a sealed normal day cannot supply the terminal identity");
        h.deliver(0xC0FFEE);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        _advance(priorDay + 2, gasleft());
        uint48 applied = h.appliedAt();
        TerminalCoinflipFixture cf = TerminalCoinflipFixture(ContractAddresses.COINFLIP);
        assertEq(cf.settlements(), 1);
        assertEq(cf.settledDay(), day);
        assertEq(h.dayWord(day), 0xC0FFEE);
        // The next terminal call moves on to the (empty) payout and never re-applies the word.
        vm.etch(ContractAddresses.STETH_TOKEN, type(TerminalSinkFixture).runtimeCode);
        vm.etch(ContractAddresses.GNRUS, type(TerminalSinkFixture).runtimeCode);
        vm.etch(ContractAddresses.COIN, type(TerminalSinkFixture).runtimeCode);
        vm.etch(ContractAddresses.SDGNRS, type(TerminalSinkFixture).runtimeCode);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        _advance(priorDay + 4, gasleft());
        assertEq(cf.settlements(), 1);
        assertEq(h.appliedAt(), applied);
        (uint24 retainedDay, uint48 retainedAt, bool active, bool published) = h.identity();
        assertEq(retainedDay, day);
        assertEq(retainedAt, at);
        assertTrue(active && published);
    }

    function test_ExtremeCalibrationCannotPreventFirstTerminalRequest() public {
        (,,, bool progressed) = h.runGameOverAdvance{gas: 4_000_000}(
            priorDay, 10, MineFlipGas.budget(4_000_000, type(uint32).max, true));
        assertTrue(progressed);
        assertEq(vrf.calls(), 1);
    }

    function test_CoordinatorGasFailureDoesNotArmRefusalTimer() public {
        vrf.setMode(2);
        vm.expectRevert();
        h.runGameOverAdvance{gas: 4_000_000}(
            priorDay, 10, MineFlipGas.budget(4_000_000, type(uint32).max, true));
        (uint24 day, uint48 at, bool active,) = h.identity();
        assertEq(day, 0);
        assertEq(at, 0);
        assertFalse(active);
        vrf.setMode(0);
        assertTrue(_advance(priorDay, 4_000_000));
        assertEq(vrf.calls(), 1, "same request remains retryable");
    }

    function test_SemanticRefusalRetainsFirstTimerAndEventuallyExpires() public {
        vrf.setMode(1);
        // The first refused attempt still arms the request identity, so the call progresses.
        assertTrue(_advance(priorDay, 4_000_000));
        assertEq(vrf.calls(), 0, "no request was accepted");
        (uint24 day, uint48 at,,) = h.identity();
        assertEq(day, priorDay + 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        // A repeated refusal with nothing else advanced bubbles the coordinator's error.
        vm.expectRevert(TerminalCoordinatorFixture.Refused.selector);
        _advance(priorDay + 1, 4_000_000);
        (uint24 againDay, uint48 againAt,,) = h.identity();
        assertEq(againDay, day);
        assertEq(againAt, at);
        vm.warp(uint256(at) + 14 days + 1);
        assertTrue(h.dead());
    }
}
