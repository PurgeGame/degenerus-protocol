// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameDecimatorModule} from "../../contracts/modules/DegenerusGameDecimatorModule.sol";

/// @dev Module harness: seeds an entered round and the session state the seal checks, and
///      issues the seal as the facade self-call does (`msg.sender == address(this)`).
contract DegradeDecimatorSealHarness is DegenerusGameDecimatorModule {
    function enter(uint24 lvl, uint64 count) external {
        level = lvl - 1;
        decBattleRounds[lvl].count = count;
        decBattleRounds[lvl].openedDay = _simulatedDayIndex();
    }

    function publish(uint256 word) external {
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        _setRngComplete(true);
    }

    function setQueue(uint256 q) external { decBattleQueue = q; }
    function setWindow(bool open) external { _setDecWindowOpen(open); }

    function seal(uint256 pool, uint24 lvl, uint256 word) external returns (uint256) {
        return this.runDecimatorJackpot(pool, lvl, word);
    }

    function phaseOf(uint24 lvl) external view returns (uint8) { return decBattleRounds[lvl].phase; }
    function poolOf(uint24 lvl) external view returns (uint128) { return decBattleRounds[lvl].poolWei; }
    function queue() external view returns (uint256) { return decBattleQueue; }
    function complete() external view returns (bool) { return _rngComplete(); }
    function reserved() external view returns (uint256) { return claimablePool; }
}

/// @notice Daily-spine degrade (DAILY-3): a Decimator seal the session cannot take hands the pool
///         back unsealed instead of reverting the last-purchase consolidation. The round keeps its
///         entries at phase 0, the pool stays with the caller, no entrant is paid and the RNG
///         session is untouched. Run: forge test --match-path test/repro/DegradeDecimatorSeal.t.sol -vv
contract DegradeDecimatorSealTest is Test {
    uint24 private constant LVL = 15;
    uint256 private constant WORD = 0xBEEF1234;
    uint256 private constant POOL = 3 ether;
    DegradeDecimatorSealHarness private h;

    function setUp() public {
        vm.warp(30 days);
        h = new DegradeDecimatorSealHarness();
        h.enter(LVL, 4);
        h.publish(WORD);
    }

    function _assertUnsealed(uint256 returned, uint256 queueBefore) private {
        assertEq(returned, POOL, "the whole pool is handed back");
        assertEq(h.phaseOf(LVL), 0, "round stays entered, not sealed");
        assertEq(h.poolOf(LVL), 0, "no pool pinned to the round");
        assertEq(h.queue(), queueBefore, "settlement queue untouched");
        assertTrue(h.complete(), "RNG session untouched");
        assertEq(h.reserved(), 0, "no entrant is paid");
    }

    /// @dev Another round is still queued for settlement.
    function test_QueueOccupiedHandsPoolBack() public {
        h.setQueue(uint256(LVL - 10) | (uint256(LVL - 10) << 24));
        uint256 queueBefore = h.queue();
        _assertUnsealed(h.seal(POOL, LVL, WORD), queueBefore);
    }

    /// @dev The window is still open for this round.
    function test_WindowOpenHandsPoolBack() public {
        h.setWindow(true);
        _assertUnsealed(h.seal(POOL, LVL, WORD), 0);
    }

    /// @dev The word offered is not the published session word.
    function test_WordMismatchHandsPoolBack() public {
        _assertUnsealed(h.seal(POOL, LVL, WORD + 1), 0);
    }

    /// @dev A pool past the uint128 field.
    function test_OversizedPoolHandsPoolBack() public {
        uint256 big = uint256(type(uint128).max) + 1;
        assertEq(h.seal(big, LVL, WORD), big);
        assertEq(h.phaseOf(LVL), 0);
        assertTrue(h.complete());
    }

    /// @dev Caller authentication still reverts.
    function test_DirectCallStillReverts() public {
        vm.expectRevert();
        h.runDecimatorJackpot(POOL, LVL, WORD);
    }

    /// @dev Reachable shape: the seal proceeds and pins the pool, the queue and the session.
    function test_ReachableSealUnchanged() public {
        uint256 returned = h.seal(POOL, LVL, WORD);
        assertEq(returned, 0, "pool spent into the round");
        assertEq(h.phaseOf(LVL), 1);
        assertEq(h.poolOf(LVL), uint128(POOL));
        assertEq(h.queue(), uint256(LVL) | (uint256(LVL) << 24));
        assertFalse(h.complete(), "session held for settlement");
    }
}
