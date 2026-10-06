// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {AfkingStethHost} from "./helpers/AfkingStethFixture.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Fixture additions: pin a subscriber pass to a day without touching the ring or level.
contract AfkingFrameHost is AfkingStethHost {
    function pin(uint24 day) external {
        _afkingResetDay = day;
        dailyIdx = day - 1;
        _subCursor = 0;
        subsFullyProcessed = false;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        humanReadComplete = true;
        ticketsFullyProcessed = true;
    }

    function resetDay() external view returns (uint24) { return _afkingResetDay; }
}

/// @notice A run frame (afkCoveredThroughDay / afkingStartDay) only moves forward: a lagging pass
///         of an earlier day delivering to a sub re-framed on a later day must not drop covered
///         below start (uint24 underflow on every later streak read / finalize).
contract AfkingStreakFrameNoRegress is DeployProtocol {
    AfkingFrameHost internal host;
    address internal constant PLAYER = address(0xA11CE);
    address internal constant OP = address(0x0BEA7);
    uint256 internal constant WORK_GAS = 8_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 3 days);
        vm.etch(address(game), type(AfkingFrameHost).runtimeCode);
        host = AfkingFrameHost(payable(address(game)));
        vm.deal(address(game), 100 ether);
    }

    function _sub(address who) internal view returns (DegenerusGameStorage.Sub memory) {
        return host.stateOf(who);
    }

    function _assertFrame(string memory tag) internal view {
        DegenerusGameStorage.Sub memory s = _sub(address(vault));
        assertGe(s.afkCoveredThroughDay, s.afkingStartDay, tag);
    }

    function _work() internal returns (MineFlipGas.Result memory r) {
        r = host.subWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(r.done, "pass completes");
    }

    /// Real sequence: day-D pass pinned and still partial at D+1; VAULT cancelled and re-subscribed
    /// unfunded (exempt branch) on D+1; vault funded; lagging day-D walk delivers to VAULT.
    function test_VaultResubscribedLaterDayThenLaggingPassDelivers() public {
        uint24 dayD = host.currentDayView();
        host.pin(dayD);

        // Wall clock passes into D+1 with the day-D pass untouched.
        vm.warp(block.timestamp + 1 days);
        uint24 dayD1 = host.currentDayView();
        assertEq(dayD1, dayD + 1, "clock advanced one day");

        // Approved operator cancels then re-subscribes the VAULT with no game-side funding.
        address owner = ContractAddresses.CREATOR;
        vm.prank(owner);
        vault.gameSetOperatorApproval(OP, true);
        vm.prank(OP);
        game.subscribe(address(vault), false, true, 0, address(0));
        vm.prank(OP);
        game.subscribe(address(vault), false, true, 1, address(0));

        DegenerusGameStorage.Sub memory s = _sub(address(vault));
        assertEq(s.afkCoveredThroughDay, dayD1, "new run covered framed on D+1");
        assertEq(s.afkingStartDay, dayD1, "new run start framed on D+1");
        assertLt(s.lastAutoBoughtDay, dayD1, "exempt unfunded start stamps nothing");

        // Vault becomes funded before the lagging day-D walk reaches it.
        vm.deal(address(this), 10 ether);
        game.depositAfkingFunding{value: 5 ether}(address(vault));
        assertEq(host.resetDay(), dayD, "pass still pinned to D");

        _work(); // day-D walk delivers to VAULT with processDay = D
        s = _sub(address(vault));
        assertEq(s.lastAutoBoughtDay, dayD, "VAULT delivered for day D");
        _assertFrame("after lagging day-D walk");
        assertEq(s.afkCoveredThroughDay, dayD1, "frame did not move backwards");
        assertEq(s.afkingStartDay, dayD1, "start unchanged");

        // D+1 pass (includes the box open of day D) completes without reverting.
        host.nextDay();
        assertEq(host.resetDay(), dayD1);
        _work();
        _assertFrame("after day-D+1 pass");
        s = _sub(address(vault));
        assertEq(s.lastAutoBoughtDay, dayD1, "VAULT delivered for day D+1");

        // A later cancel (finalize reads covered - start) succeeds.
        vm.prank(OP);
        game.subscribe(address(vault), false, true, 0, address(0));
        assertEq(_sub(address(vault)).dailyQuantity, 0, "cancelled");
    }

    /// Existing behaviour: an ordinary subscriber's covered day advances by one per delivered day
    /// and the run start shifts by the gap across a skipped day (streak frozen over the gap).
    function test_OrdinarySubscriberAdvancesPerDayAndFreezesAcrossGap() public {
        host.prepare();
        uint256 q = 1;
        host.add(PLAYER, address(0), false, true, uint8(q), host.price() * 6, 0);
        uint24 d0 = host.resetDay();
        DegenerusGameStorage.Sub memory s = _sub(PLAYER);
        assertEq(s.afkCoveredThroughDay, d0 - 1);
        uint24 start0 = s.afkingStartDay;

        _work();
        s = _sub(PLAYER);
        assertEq(s.afkCoveredThroughDay, d0, "day 1 delivered");
        assertEq(s.afkingStartDay, start0, "no gap, start fixed");

        vm.warp(block.timestamp + 1 days);
        host.nextDay();
        _work();
        s = _sub(PLAYER);
        assertEq(s.afkCoveredThroughDay, d0 + 1, "day 2 delivered");
        assertEq(s.afkingStartDay, start0, "no gap, start fixed");
        uint24 span = s.afkCoveredThroughDay - s.afkingStartDay;

        // Skip one whole day, then deliver: start shifts by the gap so the streak span is +1 only.
        vm.warp(block.timestamp + 2 days);
        host.nextDay();
        _work();
        s = _sub(PLAYER);
        assertEq(s.afkCoveredThroughDay, d0 + 3, "covered jumps to processDay");
        assertEq(s.afkingStartDay, start0 + 1, "start shifted by the one-day gap");
        assertEq(s.afkCoveredThroughDay - s.afkingStartDay, span + 1, "streak gains one, gap frozen");
    }
}
