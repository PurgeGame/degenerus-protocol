// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";

interface IGameBoonView {
    function boonPacked(address player) external view returns (uint256 slot0, uint256 slot1);
    function consumeCoinflipBoon(address player) external returns (uint16);
}

/// @title WwxrpBoonLaneSkip -- WWXRP.enter reads the Game's WWXRP boon lane before consuming
/// @notice enter() dispatches the Game's consumeCoinflipBoon only when the player's WWXRP lane
///         (Game slot 50 mapping, second word, bits 232..255) has a nonzero tier. These tests pin
///         that slot against the Game's own getter and prove the skipped dispatch is a no-op.
contract WwxrpBoonLaneSkipTest is DeployProtocol {
    uint256 private constant BOON_PACKED_SLOT = 50;
    uint256 private constant WWXRP_LANE_SHIFT = 232;
    uint256 private constant LANE_DAY_SHIFT = 3;
    uint256 private constant LANE_DEITY_BIT = 0x4;
    bytes32 private constant BOON_CONSUMED_SIG = keccak256("BoonConsumed(address,uint8,uint16)");

    address internal alice;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        alice = makeAddr("alice");
        vm.prank(address(game));
        wwxrp.mintPrize(alice, 1_000_000 ether);
    }

    function _slot(address player, uint256 word) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(player, BOON_PACKED_SLOT))) + word);
    }

    function _write(address player, uint256 s0, uint256 s1) private {
        vm.store(address(game), _slot(player, 0), bytes32(s0));
        vm.store(address(game), _slot(player, 1), bytes32(s1));
    }

    function _today() private view returns (uint24) {
        return game.currentDayView();
    }

    function _lane(uint256 tier, bool deity, uint256 day) private pure returns (uint256) {
        return ((day & 0x1FFFFF) << LANE_DAY_SHIFT) | (deity ? LANE_DEITY_BIT : 0) | tier;
    }

    /// @dev The slot WWXRP reads is the second word of the Game's public boonPacked getter.
    function testFuzz_SlotPinnedToGameGetter(address player, uint256 s0, uint256 s1) public {
        _write(player, s0, s1);
        (uint256 g0, uint256 g1) = IGameBoonView(address(game)).boonPacked(player);
        assertEq(g0, s0, "slot0");
        assertEq(g1, s1, "slot1");
        assertEq(uint256(game.extsload(_slot(player, 1))), s1, "extsload");
    }

    /// @dev A live WWXRP boon is still found and spent: the lane is read, the consume runs,
    ///      BoonConsumed fires at tier x 400 and the lane clears.
    function testLiveWwxrpBoonIsSpent() public {
        uint256 others = uint256(0xABCDEF) << 184;
        _write(alice, 0, others | (_lane(3, false, _today()) << WWXRP_LANE_SHIFT));
        vm.expectCall(address(game), abi.encodeCall(IGameBoonView.consumeCoinflipBoon, (alice)), 1);
        vm.expectEmit(true, false, false, true, address(game));
        emit BoonConsumed(alice, 7, 1200);
        vm.prank(alice);
        wwxrp.enter(25 ether);
        (, uint256 s1) = IGameBoonView(address(game)).boonPacked(alice);
        assertEq(s1, others, "WWXRP lane not cleared or another lane touched");
    }

    /// @dev An expired WWXRP boon has a nonzero tier, so the consume still runs and clears it,
    ///      paying nothing — exactly the pre-check-free behavior.
    function testExpiredWwxrpBoonIsStillCleared() public {
        vm.warp(vm.getBlockTimestamp() + 12 days);
        uint24 d = _today();
        _write(alice, 0, _lane(2, false, d - 10) << WWXRP_LANE_SHIFT);
        vm.expectCall(address(game), abi.encodeCall(IGameBoonView.consumeCoinflipBoon, (alice)), 1);
        vm.prank(alice);
        wwxrp.enter(25 ether);
        (, uint256 s1) = IGameBoonView(address(game)).boonPacked(alice);
        assertEq(s1, 0, "expired WWXRP lane not cleared");
    }

    /// @dev A deity-issued WWXRP boon is live only on its stamp day: that day it pays tier x 400;
    ///      a day later its tier is still set, so the consume runs, clears it and pays nothing.
    function testDeityLaneLiveTodayAndClearedAfter() public {
        uint24 d = _today();
        _write(alice, 0, _lane(3, true, d) << WWXRP_LANE_SHIFT);
        vm.expectEmit(true, false, false, true, address(game));
        emit BoonConsumed(alice, 7, 1200);
        vm.prank(alice);
        wwxrp.enter(25 ether);
        (, uint256 s1) = IGameBoonView(address(game)).boonPacked(alice);
        assertEq(s1, 0, "same-day deity lane not spent");

        _write(alice, 0, _lane(3, true, d) << WWXRP_LANE_SHIFT);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.expectCall(address(game), abi.encodeCall(IGameBoonView.consumeCoinflipBoon, (alice)), 1);
        vm.recordLogs();
        vm.prank(alice);
        wwxrp.enter(25 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != BOON_CONSUMED_SIG, "stale deity lane paid");
        }
        (, s1) = IGameBoonView(address(game)).boonPacked(alice);
        assertEq(s1, 0, "stale deity lane not cleared");
    }

    /// @dev Any boon state at all. The dispatch happens iff the WWXRP tier is nonzero; when it
    ///      is skipped, the Game's consume (run on a snapshot as WWXRP) returns 0, writes nothing
    ///      and logs nothing, and enter() leaves both boon words untouched.
    function testFuzz_DispatchIffWwxrpTierNonzero(uint256 s0, uint256 s1, uint256 amount) public {
        amount = bound(amount, 25 ether, 10_000 ether);
        _write(alice, s0, s1);
        bool nonzeroTier = (s1 >> WWXRP_LANE_SHIFT) & 3 != 0;

        if (!nonzeroTier) {
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            vm.startStateDiffRecording();
            vm.prank(address(wwxrp));
            uint16 bps = IGameBoonView(address(game)).consumeCoinflipBoon(alice);
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            assertEq(bps, 0, "skipped consume would have paid");
            assertEq(vm.getRecordedLogs().length, 0, "skipped consume would have logged");
            for (uint256 i; i < acc.length; ++i) {
                for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                    assertFalse(acc[i].storageAccesses[j].isWrite, "skipped consume would have written");
                }
            }
            (uint256 g0, uint256 g1) = IGameBoonView(address(game)).boonPacked(alice);
            assertEq(g0, s0, "skipped consume would have written slot0");
            assertEq(g1, s1, "skipped consume would have written slot1");
            vm.revertToState(snap);
        }

        vm.expectCall(
            address(game), abi.encodeCall(IGameBoonView.consumeCoinflipBoon, (alice)), nonzeroTier ? 1 : 0
        );
        vm.recordLogs();
        vm.prank(alice);
        wwxrp.enter(amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (!nonzeroTier) {
            (uint256 g0, uint256 g1) = IGameBoonView(address(game)).boonPacked(alice);
            assertEq(g0, s0, "enter touched slot0");
            assertEq(g1, s1, "enter touched slot1");
            for (uint256 i; i < logs.length; ++i) {
                assertTrue(logs[i].topics[0] != BOON_CONSUMED_SIG, "boon consumed without a WWXRP tier");
            }
        } else {
            (, uint256 g1) = IGameBoonView(address(game)).boonPacked(alice);
            assertEq(g1, s1 & ~(uint256(0xFFFFFF) << WWXRP_LANE_SHIFT), "consume touched another lane");
        }
    }

    event BoonConsumed(address indexed player, uint8 boonType, uint16 boostBps);
}
