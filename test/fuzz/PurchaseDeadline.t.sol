// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

contract PurchaseDeadlineHarness is DegenerusGameStorage {
    function seed(uint24 lvl, uint24 age, uint48 requestTime, uint24 sealedAge, uint8 phase) external {
        level = lvl;
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - age;
        dailyIdx = day - sealedAge;
        rngRequestTime = requestTime;
        lastPurchaseDay = phase == 1;
        jackpotPhaseFlag = phase == 2;
    }

    function liveness() external view returns (bool) { return _livenessTriggered(); }
    function distress() external view returns (bool) { return _isDistressMode(); }
}

contract PurchaseDeadlineTest is Test {
    PurchaseDeadlineHarness private h;

    function setUp() public {
        vm.warp(1000 days + 12 hours);
        h = new PurchaseDeadlineHarness();
    }

    function test_day29_30_31() public {
        h.seed(1, 29, 0, 1, 0);
        assertFalse(h.distress());
        assertFalse(h.liveness());
        h.seed(1, 30, 0, 1, 0);
        assertTrue(h.distress(), "day 30 remains a rescue day");
        assertFalse(h.liveness());
        h.seed(1, 31, 0, 1, 0);
        assertTrue(h.liveness(), "purchase deadline expires on day 31");
    }

    function test_genesis364_365_366() public {
        h.seed(0, 364, 0, 1, 0);
        assertFalse(h.distress());
        assertFalse(h.liveness());
        h.seed(0, 365, 0, 1, 0);
        assertTrue(h.distress());
        assertFalse(h.liveness());
        h.seed(0, 366, 0, 1, 0);
        assertTrue(h.liveness());
    }

    function test_preDeadlineRequestGetsExisting14DayGrace() public {
        uint48 start = uint48(block.timestamp - 1 days);
        h.seed(5, 31, start, 2, 0);
        assertFalse(h.liveness(), "request on day 30 suppresses day 31 death");
        vm.warp(uint256(start) + 14 days - 1);
        assertFalse(h.liveness(), "grace remains open just before 14 days");
        vm.warp(uint256(start) + 14 days);
        assertTrue(h.liveness(), "14 days of request age expires grace");
    }

    function test_postDeadlineRequestCannotReopenPurchases() public {
        h.seed(5, 31, uint48(block.timestamp), 1, 0);
        assertTrue(h.liveness(), "a terminal request does not reset the deadline");
    }

    function test_productivePhasesKeepIndependent30DayDeadman() public {
        for (uint8 phase = 1; phase <= 2; ++phase) {
            h.seed(5, 31, 0, 1, phase);
            assertFalse(h.liveness(), "funded phase may finish beyond purchase deadline");
            h.seed(5, 60, 0, 30, phase);
            assertFalse(h.liveness(), "deadman is still strict greater-than 30");
            h.seed(5, 61, 0, 31, phase);
            assertTrue(h.liveness(), "deadman fires after 30 days without a seal");
        }
    }
}

contract PurchaseDeadlineSeeder is DegenerusGame {
    function seed(uint24 age) external {
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        levelPrizePool[1] = 10 ether;
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }
}

contract PurchaseDeadlineIntegrationTest is DeployProtocol {
    address private constant BUYER = address(0xB077);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(BUYER, 10 ether);
        vm.deal(address(game), 20 ether);
    }

    function _seed(uint24 age) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(PurchaseDeadlineSeeder).runtimeCode);
        PurchaseDeadlineSeeder(payable(address(game))).seed(age);
        vm.etch(address(game), original);
    }

    function _advanceWithVrf() private {
        game.advanceGame();
        uint256 id = mockVRF.lastRequestId();
        if (id != 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(id);
            if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(id))));
        }
    }

    function test_day30DistressLootboxRescuesLevel() public {
        _seed(30);
        uint256 nextBefore = game.nextPrizePoolView();
        vm.prank(BUYER);
        game.purchase{value: 2 ether}(BUYER, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.nextPrizePoolView() - nextBefore, 2 ether, "distress routes entire purchase to next");

        // Finish the funded level beyond its purchase deadline, across all three jackpot days.
        uint256 nextTimestamp = block.timestamp;
        for (uint256 day; day < 6; ++day) {
            for (uint256 step; step < 200; ++step) {
                if (game.level() == 2 && !game.jackpotPhase() && !game.rngLocked()) return;
                _advanceWithVrf();
                if (!game.rngLocked()) break;
            }
            assertFalse(game.gameOver(), "funded level must not die at day 31");
            nextTimestamp += 1 days;
            vm.warp(nextTimestamp);
        }
        fail("rescued level did not finish its jackpot");
    }

    function test_day31BlocksPurchaseAndSettlesGameOver() public {
        _seed(31);
        assertTrue(game.livenessTriggered());
        vm.prank(BUYER);
        vm.expectRevert(bytes4(keccak256("E()")));
        game.purchase{value: 1 ether}(BUYER, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        for (uint256 i; i < 30 && !game.gameOver(); ++i) _advanceWithVrf();
        assertTrue(game.gameOver(), "unfunded level ends after the 30-day deadline");
    }
}
