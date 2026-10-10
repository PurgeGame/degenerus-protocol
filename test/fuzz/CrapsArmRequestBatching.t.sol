// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Craps} from "../../contracts/Craps.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Arming a shut Craps window and requesting its word share one mineFlip when gas
///         allows; a later stop or refused request keeps the completed arm.
contract CrapsArmRequestBatchingTest is DeployProtocol {
    address internal constant KEEPER = address(0xC0FFEE);
    bytes32 internal constant ARMED = keccak256("CrapsBonusArmed(bytes32,uint48,uint48)");
    uint24 internal today;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000 ether);
        // Genesis is a warm-up day with no windows; play from genesis + 1, an hour in.
        vm.warp(block.timestamp + 1 days);
        _settle();
        today = crapsBattle.currentDayIndex();
    }

    function _settle() internal {
        for (uint256 i; i < 400; ++i) {
            uint256 req = mockVRF.lastRequestId();
            if (req != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(req);
                if (!fulfilled) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("word", req))));
            }
            if (!game.advanceDue()) return;
            vm.prank(KEEPER);
            game.mineFlip(0);
        }
        revert("fixture did not settle");
    }

    function _slot(uint256 period) internal view returns (uint64) {
        return uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    function _seat(address player, uint256 period) internal {
        (uint128 bankroll,,,,,) = crapsBattle.bonusTermsFor(today, period);
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(player, uint256(bankroll) * 4);
        Craps.Bets memory board;
        board.passLine = 3;
        board.place8 = 3;
        board.place9 = 1;
        vm.prank(player);
        crapsBattle.enterBonusBattle(period, board, 1);
    }

    function _armedIn(Vm.Log[] memory logs, uint64 slot) internal view returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(crapsBattle) && logs[i].topics.length == 4
                && logs[i].topics[0] == ARMED && uint256(logs[i].topics[2]) == slot) return true;
        }
        return false;
    }

    function _mine(uint256 gasLimit) internal returns (bool armed, bool requested, uint256 used) {
        return _mine(gasLimit, 0);
    }

    function _mine(uint256 gasLimit, uint32 calibration) internal returns (bool armed, bool requested, uint256 used) {
        uint64 slot = _slot(1);
        uint256 before = mockVRF.lastRequestId();
        vm.recordLogs();
        vm.prank(KEEPER);
        uint256 start = gasleft();
        game.mineFlip{gas: gasLimit}(calibration);
        used = start - gasleft();
        armed = _armedIn(vm.getRecordedLogs(), slot);
        requested = mockVRF.lastRequestId() != before;
    }

    function test_ShutWindowArmsAndRequestsItsWordInOneCall() public {
        _seat(address(0xBEEF), 1);
        vm.warp(vm.getBlockTimestamp() + 5 hours + 10 minutes); // period 1 shuts 6h03m in
        (bool armed, bool requested, uint256 used) = _mine(16_000_000);
        emit log_named_uint("arm_plus_midday_request_gas", used);
        assertTrue(armed, "the shut window was armed");
        assertTrue(requested, "the same call requested the window's word");
        assertGt(crapsBattle.slotIndexOf(_slot(1)), 0);
        assertFalse(game.rngComplete(), "the request opened a new read session");
    }

    function test_MaximumCalibrationKeepsTheArmAndANextCallRequests() public {
        _seat(address(0xBEEF), 1);
        vm.warp(vm.getBlockTimestamp() + 5 hours + 10 minutes);
        // The arm is the mandatory first unit; maximum calibration scales the request's
        // estimate past any supplied gas, so the request is deferred to the next call.
        (bool armed, bool requested, uint256 used) = _mine(16_000_000, type(uint32).max);
        emit log_named_uint("arm_only_gas", used);
        assertTrue(armed, "maintenance committed as the first unit");
        assertFalse(requested, "the request did not fit the calibrated estimate");
        assertEq(game.nextMinerAction(), 18, "the request is the next action");
        (armed, requested, used) = _mine(16_000_000);
        emit log_named_uint("request_only_gas", used);
        assertFalse(armed, "the window is not armed twice");
        assertTrue(requested, "a later call requests the armed window's word");
    }

    function test_RefusedRequestKeepsTheArm() public {
        _seat(address(0xBEEF), 1);
        vm.warp(vm.getBlockTimestamp() + 5 hours + 10 minutes);
        vm.prank(ContractAddresses.CREATOR);
        game.setMiddayMaxBasefee(5);
        vm.fee(6 gwei);
        (bool armed, bool requested,) = _mine(16_000_000);
        assertTrue(armed, "a refused optional request does not undo the arm");
        assertFalse(requested);
        assertGt(crapsBattle.slotIndexOf(_slot(1)), 0);
        vm.fee(1 gwei);
        (armed, requested,) = _mine(16_000_000);
        assertFalse(armed);
        assertTrue(requested, "the request succeeds once its gate clears");
    }

    function test_LaterShutWindowWaitsBehindTheArmedHead() public {
        _seat(address(0xBEEF), 1);
        _seat(address(0xFACE), 2);
        vm.warp(vm.getBlockTimestamp() + 11 hours + 10 minutes); // period 2 shuts 12h03m in
        (bool armed, bool requested,) = _mine(16_000_000);
        assertTrue(armed && requested, "the oldest window arms and requests first");
        assertEq(crapsBattle.slotIndexOf(_slot(2)), 0, "the next window waits for the head's settlement");
        assertEq(crapsBattle.minerSlot(), _slot(1), "the cursor stays on the armed head");
    }
}
