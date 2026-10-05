// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {TicketCheckpointHarness} from "./TicketCheckpointDeterminism.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract NearParityLifecycleHarness is TicketCheckpointHarness {
    function phase(bool jackpot, bool lastDay, bool transition) external {
        jackpotPhaseFlag = jackpot;
        lastPurchaseDay = lastDay;
        phaseTransitionActive = transition;
        rngLockedFlag = false;
    }
    function finalJackpotDay() external { jackpotCounter = _jackpotDays() - 1; }
    function buy(address buyer, uint32 scaled) external returns (uint24 target) {
        target = _activeTicketLevel();
        _queueEntriesScaled(buyer, target, scaled);
    }
    function total(uint24 lvl, address buyer) external view returns (uint32) {
        return _entriesOwedTotal(lvl, buyer);
    }
    function ceiling() external view returns (uint24) { return _mintCeiling(); }
    function queueLength(uint24 lvl) external view returns (uint256) {
        return _ticketQueueLength(_tqReadKey(lvl)) + _ticketQueueLength(_tqWriteKey(lvl));
    }
}

contract NearQueueParityLifecycleTest is Test {
    NearParityLifecycleHarness h;
    address constant BUYER = address(0xA11CE);

    function setUp() public {
        vm.etch(ContractAddresses.GAME, address(new NearParityLifecycleHarness()).code);
        h = NearParityLifecycleHarness(ContractAddresses.GAME);
        h.initialize(3);
    }

    function drain(uint24 anchor) private {
        for (uint256 i; i < 20; ++i) {
            MineFlipGas.Result memory result = h.runTicketWork(anchor, 9_000_000);
            if (result.done) return;
        }
        fail("ticket sweep must finish");
    }

    function test_JackpotDebtClearsBeforeNextLastPurchaseDayReusesParity() public {
        h.phase(true, false, false);
        assertEq(h.buy(BUYER, 400), 3);
        h.credit(BUYER, 4, 800);
        h.finalJackpotDay();
        h.commit(0x123456, false);
        assertEq(h.buy(BUYER, 1_200), 4, "sealed jackpot routes new purchases forward");
        drain(4);
        assertEq(h.total(3, BUYER), 0);
        assertEq(h.queueLength(3), 0);
        assertEq(h.total(4, BUYER), 12, "next level write cohort survives read drain");
        (, uint256 oldCount) = h.digest(3);
        assertEq(oldCount, 4);

        h.phase(false, false, false);
        assertEq(h.buy(BUYER, 400), 4);
        assertEq(h.ceiling(), 4);
        h.phase(false, true, false);
        assertEq(h.ceiling(), 5);
        h.credit(BUYER, 5, 2_000);
        assertEq(h.total(4, BUYER), 16, "other parity remains intact");
        assertEq(h.total(5, BUYER), 20);
        assertEq(h.total(3, BUYER), 0, "old level cannot read reused debt");
        h.initialize(4);
        h.commit(0x654321, false);
        drain(4);
        assertEq(h.total(4, BUYER), 0);
        assertEq(h.total(5, BUYER), 0);
        assertEq(h.queueLength(4), 0);
        assertEq(h.queueLength(5), 0);
        (, uint256 nextCount) = h.digest(4);
        (, uint256 reusedCount) = h.digest(5);
        assertEq(nextCount, 24);
        assertEq(reusedCount, 20);
    }
}
