// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {QaSlots} from "../helpers/QaSlots.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Regression: days covered by an open AFKing run are never billed as missed. During a run
///         the Game makes no Quests call between beginAfking and finalizeAfking, so a manual action
///         that reaches a Quests handler on a later run day (here a self coinflip deposit ->
///         handleFlip -> _questSyncState) used to bill the run's days: it burned held shields, or
///         zeroed the dormant streak and reset shieldCenturyHighWater, after which finalizeAfking
///         re-granted centuries already credited. Each case compares against the identical run with
///         no manual action (control); the manual run must now match it exactly. Full protocol;
///         quest state is seeded once with vm.store to a reachable shape (streak 250, primary
///         completed on the subscribe day, century high-water 2).
contract AfkingMidRunShieldBurn is DeployProtocol {
    uint256 private constant QSTATE = QaSlots.STATE;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint256 private _nonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
    }

    // ---- quest-state packing (PlayerQuestState single slot) ----
    function _qslot(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), QSTATE));
    }

    function _q(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(ContractAddresses.QUESTS, _qslot(id)));
    }

    function _shields(uint32 id) internal view returns (uint256) { return (_q(id) >> 200) & 0xff; }
    function _highWater(uint32 id) internal view returns (uint256) { return (_q(id) >> 104) & 0xff; }
    function _streak(uint32 id) internal view returns (uint256) { return (_q(id) >> 72) & 0xffff; }
    function _afkingSince(uint32 id) internal view returns (uint256) { return (_q(id) >> 208) & 0xffffff; }

    /// @dev A player who completed the daily primary on day `s` with streak `streak`, century
    ///      high-water streak/100 and `shields` held shields (e.g. from lootbox boons).
    function _seedQuestState(uint32 id, uint24 s, uint16 streak, uint8 shields) internal {
        uint256 w = uint256(s) | (uint256(s) << 24) | (uint256(s) << 48)
            | (uint256(streak) << 72) | (uint256(streak) << 88)
            | (uint256(streak / 100) << 104) | (uint256(shields) << 200);
        vm.store(ContractAddresses.QUESTS, _qslot(id), bytes32(w));
    }

    // ---- drive helpers (same production path as QuestBoonAfkingStreakLoss) ----
    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _settle(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
            _fulfillPending(vrfWord);
        }
    }

    function _deliverDay() internal {
        uint256 w = uint256(keccak256(abi.encode("reg-afk", _nonce++))) | 1;
        _settle(w ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settle(w);
        _settle(uint256(keccak256(abi.encode("reg-afk-c", w))) | 1);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
    }

    function _selfFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame_g152734(who, amount);
        vm.prank(who);
        coinflip.playCoinflip(0, amount);
    }

    /// @dev Subscribe on day S, deliver 3 run days, then (optionally) one manual coinflip deposit,
    ///      then cancel. Returns the post-finalize shields / high-water / streak.
    function _scenario(address p, uint8 shieldsHeld, bool manual)
        internal returns (uint256 shieldsAfter, uint256 hwAfter, uint256 streakAfter, uint256 midShields, uint256 midHw)
    {
        uint32 id = _giveWalletId(p);
        uint24 s = uint24(game.currentDayView_g542950());
        _seedQuestState(id, s, 250, shieldsHeld);

        vm.deal(address(this), 50 ether);
        game.depositAfkingFunding{value: 50 ether}(id);
        uint256 seat = _grantSeat(p);
        vm.prank(p);
        game.subscribe(0, false, 1, seat);
        assertEq(_afkingSince(id), s, "run started on S");
        assertEq(_shields(id), shieldsHeld, "beginAfking billed nothing");

        _deliverDay();
        _deliverDay();
        _deliverDay();
        assertGt(uint256(game.currentDayView_g542950()), uint256(s) + 2, "run covers >= 2 later days");
        assertEq(_shields(id), shieldsHeld, "the run itself never touches Quests");

        if (manual) _selfFlip(p, 1_000);
        midShields = _shields(id);
        midHw = _highWater(id);

        vm.prank(p);
        game.subscribe(0, false, 0, 0); // cancel -> finalizeAfking
        assertEq(_afkingSince(id), 0, "finalized");
        shieldsAfter = _shields(id);
        hwAfter = _highWater(id);
        streakAfter = _streak(id);
    }

    /// Case A: shields held through the run stay held; a mid-run manual action burns none.
    function test_MidRunManualActionBurnsNoShield() public {
        address p = makeAddr("afk_shield_holder");
        uint256 snap = vm.snapshotState();
        (uint256 cShields, uint256 cHw, uint256 cStreak,,) = _scenario(p, 5, false);
        assertTrue(vm.revertToState(snap));
        (uint256 mShields, uint256 mHw, uint256 mStreak, uint256 midShields, uint256 midHw) = _scenario(p, 5, true);

        assertEq(cShields, 5, "control keeps all 5 shields");
        assertEq(midShields, 5, "a mid-run manual action bills no run-covered day");
        assertEq(midHw, cHw, "mid-run high-water untouched");
        assertEq(mShields, cShields, "same shields as the control after finalize");
        assertEq(mStreak, cStreak, "finalized streak identical: the run covered those days");
        assertEq(mHw, cHw, "high-water identical");
    }

    /// Case B: no shields. The mid-run manual action neither zeroes the dormant streak's century
    /// high-water nor lets finalize re-grant centuries already credited before the run.
    function test_MidRunManualActionKeepsHighWaterAndGrantsNoCentury() public {
        address p = makeAddr("afk_no_shield");
        uint256 snap = vm.snapshotState();
        (uint256 cShields, uint256 cHw, uint256 cStreak,,) = _scenario(p, 0, false);
        assertTrue(vm.revertToState(snap));
        (uint256 mShields, uint256 mHw, uint256 mStreak, uint256 midShields, uint256 midHw) = _scenario(p, 0, true);

        assertEq(cShields, 0, "control: centuries 1-2 already credited, nothing new");
        assertEq(cHw, 2, "control: high-water stays at century 2");
        assertEq(midHw, 2, "mid-run high-water untouched by the manual action");
        assertEq(midShields, 0);
        assertEq(mStreak, cStreak, "same finalized streak");
        assertEq(mHw, cHw, "same high-water after finalize");
        assertEq(mShields, cShields, "no re-granted century shields");
    }
}
