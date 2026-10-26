// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Run with FOUNDRY_ISOLATE=true. Execution gas of one ticket purchase for a manual buyer
///      (primary completing / already complete) and an afking buyer on its run's start day and
///      on a later run day, and of the Quests side of a new run.
contract AfkingStartDayQuestGasTest is DeployProtocol {
    uint256 private price;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;

    function setUp() public {
        _deployProtocol();
        (,,,, price) = game.purchaseInfo_g1027();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
    }

    function testGas_ManualBuyCompletesPrimary() public {
        address p = _player("manualFirst");
        _measure(p, "manual_completes_primary");
    }

    function testGas_ManualBuyPrimaryDone() public {
        address p = _player("manualRepeat");
        _buy(p);
        _measure(p, "manual_primary_done");
    }

    function testGas_AfkingBuyStartDay() public {
        address p = _player("afkStart");
        _subscribe(p);
        _measure(p, "afking_start_day");
    }

    function testGas_AfkingBuyLaterDay() public {
        address p = _player("afkLater");
        _subscribe(p);
        _deliverDay();
        _measure(p, "afking_later_day");
    }

    /// @dev The Quests side of a new run on its own.
    function testGas_BeginAfkingQuestsSide() public {
        address p = _player("beginOnly");
        uint32 id = game.walletIdOf_g3120(p);
        uint24 day = game.currentDayView_g542950();
        vm.prank(address(game));
        quests.beginAfking(id, day);
        uint256 gasUsed = vm.snapshotGasLastCall("afking-start-day-quest", "begin_afking");
        emit log_named_string("scenario", "begin_afking");
        emit log_named_uint("execution_gas", gasUsed);
    }

    function _measure(address p, string memory label) private {
        vm.deal(p, p.balance + price);
        vm.prank(p);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 gasUsed = vm.snapshotGasLastCall("afking-start-day-quest", label);
        emit log_named_string("scenario", label);
        emit log_named_uint("execution_gas", gasUsed);
    }

    function _player(string memory name) private returns (address p) {
        p = makeAddr(name);
        uint32 id = game.walletIdOf_g3120(p);
        if (id == 0) id = _giveWalletId(p);
        vm.deal(address(this), 50 ether);
        game.depositAfkingFunding{value: 50 ether}(id);
    }

    function _subscribe(address p) private {
        uint256 seat = _grantSeat(p);
        vm.prank(p);
        game.subscribe(0, false, 1, seat);
    }

    function _buy(address p) private {
        vm.deal(p, p.balance + price);
        vm.prank(p);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _deliverDay() private {
        _settle(0xF00D1);
        _t += 1 days;
        vm.warp(_t);
        _settle(0xF00D3);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
        _finishSubscriptionWindow();
    }

    function _settle(uint256 vrfWord) private {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfill(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
            _fulfill(vrfWord);
        }
    }

    function _fulfill(uint256 vrfWord) private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }
}
