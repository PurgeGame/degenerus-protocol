// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Test} from "forge-std/Test.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {TransientLivenessHarness} from "./TransientLiveness.t.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

contract PurchaseDeadlineTest is Test {
    TransientLivenessHarness private h;
    function setUp() public { vm.warp(1000 days + 12 hours); h = new TransientLivenessHarness(); }
    function test_BothLevelZeroAndLaterLevelsUseThirtyCompletedDays() public {
        for (uint24 lvl; lvl < 2; ++lvl) {
            h.seed(lvl, 29, true, uint48(vm.getBlockTimestamp() - 1 days));
            assertFalse(h.liveness()); assertFalse(h.distress());
            h.seed(lvl, 30, false, uint48(vm.getBlockTimestamp() - 1 days));
            assertFalse(h.liveness()); assertTrue(h.distress());
            h.seed(lvl, 30, true, uint48(vm.getBlockTimestamp()));
            assertFalse(h.liveness(), "completion window stays open for rescue");
            vm.warp(vm.getBlockTimestamp() + 1 days);
            assertTrue(h.liveness());
        }
    }
    function test_FundedPhasesOnlyFaceFourteenDayHardDeadline() public {
        uint48 nowTs = uint48(vm.getBlockTimestamp());
        for (uint8 phase = 1; phase <= 2; ++phase) {
            h.seed(5, 31, true, nowTs); h.phase(phase);
            vm.warp(uint256(nowTs) + 14 days - 1); assertFalse(h.liveness());
            vm.warp(uint256(nowTs) + 14 days); assertTrue(h.liveness());
        }
    }
}
contract PurchaseDeadlineSeeder is DegenerusGame {
    function seed(uint24 age) external {
        uint24 day = 9 + age;
        level = 1;
        purchaseStartDay = 9;
        dailyIdx = day;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - (age > 30 ? 1 days : 0));
        lastDailyRequestWallDay = _wallDayAt(lastDailyCompletedAt);
        _setRngComplete(true);
        _setLevelPrizePool(1, 10 ether);
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        _releaseTicketQueue(_tqFarFutureKey(2));
        earlyTicketLevel = 2;
        ticketsFullyProcessed = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }
}

contract PurchaseDeadlineIntegrationTest is DeployProtocol {
    address private constant BUYER = address(0xB077);

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        vm.warp(block.timestamp + 500 days);
        vm.deal(BUYER, 10 ether);
        vm.deal(address(game), 20 ether);
    }

    function _seed(uint24 age) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(PurchaseDeadlineSeeder).runtimeCode);
        PurchaseDeadlineSeeder(payable(address(game))).seed(age);
        vm.etch(address(game), original);
        uint256 packed = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((packed & ~(uint256(0xffffff) << 176)) | (uint256(9 + age) << 176)));
    }

    function _advanceWithVrf() private {
        game.mineFlip(0);
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
        game.purchase{value: 2 ether}(0, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.nextPrizePoolView() - nextBefore, 2 ether, "distress routes entire purchase to next");

        // Finish the funded level beyond its purchase deadline, across all three jackpot days.
        uint256 nextTimestamp = block.timestamp;
        // setUp's synthetic 500-day jump leaves expired scheduled Craps days that the engine
        // maintains one checkpoint per call before the day's request, so a day is driven until
        // the engine has nothing left to do (not merely until a call leaves the lock clear).
        for (uint256 day; day < 6; ++day) {
            for (uint256 step; step < 1000; ++step) {
                if (game.level() == 2 && !game.jackpotPhase() && !game.rngLocked()) return;
                if (!game.rngLocked() && !game.advanceDue()) break;
                _advanceWithVrf();
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
        game.purchase{value: 1 ether}(0, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        for (uint256 i; i < 30 && !game.gameOver(); ++i) _advanceWithVrf();
        assertTrue(game.gameOver(), "unfunded level ends after the 30-day deadline");
    }
}
