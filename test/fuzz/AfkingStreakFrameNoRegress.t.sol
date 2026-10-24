// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {AfkingStethHost} from "./helpers/AfkingStethFixture.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Fixture additions: pin a subscriber pass to a day without touching the ring or level.
contract AfkingFrameHost is AfkingStethHost {
    function pin(uint24 day) external {
        _afkingResetDay = day;
        dailyIdx = day - 1;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
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

/// @notice A run's checkpoint only moves forward and its derived streak never falls: a lagging pass
///         of an earlier day cannot move a member's checkpoint past the endpoint, and settling
///         folds the elapsed days into the checkpoint streak without changing the live streak.
contract AfkingStreakFrameNoRegress is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf_g3120(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

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

    function _sub(address who) internal view returns (AfkingStethHost.SubView memory) {
        return host.stateOf(who);
    }

    /// @dev The live streak: checkpoint streak plus the days from the checkpoint to the endpoint.
    function _live(address who) internal view returns (uint256) {
        AfkingStethHost.SubView memory s = host.stateOf(who);
        uint24 endpoint = host.endpoint();
        return s.checkpointStreak + (endpoint > s.checkpointDay ? endpoint - s.checkpointDay : 0);
    }

    function _work() internal returns (MineFlipGas.Result memory r) {
        r = host.subWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(r.done, "pass completes");
    }

    /// A later wall day cannot move a run while its earlier preparation is active, and the
    /// lagging pass leaves every checkpoint at or before the endpoint.
    function test_VaultUpdateWaitsWhileEarlierDayPreparationIsPinned() public {
        uint24 dayD = host.currentDayView();
        host.pin(dayD);
        vm.warp(block.timestamp + 1 days);
        uint32 vaultId = _aid(address(vault));
        vm.prank(ContractAddresses.CREATOR);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, OP, true),
            0
        )), 0), (bytes));
        AfkingStethHost.SubView memory beforeSub = _sub(address(vault));
        vm.prank(OP);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        game.subscribe(vaultId, false, 0, 0);
        vm.prank(OP);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        game.subscribe(vaultId, false, 1, 0);
        assertEq(_sub(address(vault)).checkpointDay, beforeSub.checkpointDay);
        assertEq(_sub(address(vault)).checkpointStreak, beforeSub.checkpointStreak);
        vm.deal(address(this), 10 ether);
        game.depositAfkingFunding{value: 5 ether}(vaultId);
        assertEq(host.resetDay(), dayD);
        _work();
        assertEq(host.endpoint(), dayD, "the lagging pass completed its own day");
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), vaultId), "the Vault bought into the lagging cohort");
        AfkingStethHost.SubView memory afterSub = _sub(address(vault));
        assertGe(afterSub.checkpointDay, beforeSub.checkpointDay, "checkpoint never moves backward");
        assertLe(afterSub.checkpointDay, host.endpoint(), "checkpoint never passes the endpoint");
    }

    /// An ordinary member's live streak rises by one per completed pass, and settling folds the
    /// elapsed days into the checkpoint without moving the live streak. A day nobody cranked is
    /// credited with the next completed pass.
    function test_OrdinarySubscriberStreakDerivesFromCheckpointAndEndpoint() public {
        host.prepare();
        host.add(PLAYER, true, 1, host.price() * 6, 0);
        uint32 id = _aid(PLAYER);
        uint24 d0 = host.resetDay();
        AfkingStethHost.SubView memory s = _sub(PLAYER);
        assertEq(s.checkpointDay, d0 - 1);
        assertEq(s.checkpointStreak, 9);
        assertEq(_live(PLAYER), 9, "nothing credited before a pass completes");

        _work();
        assertEq(host.endpoint(), d0, "day 1 delivered");
        assertEq(_sub(PLAYER).checkpointDay, d0 - 1, "a pass does not move the checkpoint");
        assertEq(_live(PLAYER), 10);

        vm.warp(block.timestamp + 1 days);
        host.nextDay();
        _work();
        assertEq(host.endpoint(), d0 + 1, "day 2 delivered");
        assertEq(_live(PLAYER), 11);

        // Settling folds the two elapsed days into the checkpoint and keeps the live streak.
        uint256 stakeBefore = coinflip.coinflipAmount(PLAYER);
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        game.claimAfkingFlip(ids);
        s = _sub(PLAYER);
        assertEq(s.checkpointDay, d0 + 1, "checkpoint moved to the endpoint");
        assertEq(s.checkpointStreak, 11, "elapsed days folded into the checkpoint streak");
        assertEq(_live(PLAYER), 11, "the live streak does not move on settlement");
        assertEq(coinflip.coinflipAmount(PLAYER) - stakeBefore, 2 * 200, "two days of the ticket reward");
        game.claimAfkingFlip(ids);
        assertEq(_sub(PLAYER).checkpointStreak, 11, "a repeat claim changes nothing");
        assertEq(coinflip.coinflipAmount(PLAYER) - stakeBefore, 2 * 200, "a repeat claim credits nothing");

        // Skip one whole day, then deliver: the next completed pass credits the days through it.
        vm.warp(block.timestamp + 2 days);
        host.nextDay();
        _work();
        assertEq(host.endpoint(), d0 + 3, "endpoint jumps to the processed day");
        assertEq(_live(PLAYER), 13, "the skipped day is credited with the next completed pass");
        assertEq(_sub(PLAYER).checkpointDay, d0 + 1, "the checkpoint stays behind the endpoint");
    }
}
