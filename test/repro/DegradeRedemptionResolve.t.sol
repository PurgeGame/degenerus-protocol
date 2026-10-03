// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @notice Daily-spine degrade (DAILY-1): `resolveRedemptionPeriod` saturates the reservation
///         release when the cumulative reservation sits below the stamped day's MAX share, so the
///         advance that applies the daily word completes instead of reverting on underflow.
/// @dev The seeded state is unreachable (submit adds exactly the MAX share it later releases); it
///      is written straight into sDGNRS storage: slot 0 packs `_totalSupply` (uint128),
///      `_pendingRedemptionEthValue` (uint96 at bit 128) and `_pendingResolveDay` (uint24 at
///      bit 224); `pendingAggregate.ethBase` is the low uint64 of its own slot.
///      Run: forge test --match-path test/repro/DegradeRedemptionResolve.t.sol -vv
contract DegradeRedemptionResolveTest is DeployProtocol {
    uint24 private constant DAY = 77;
    uint64 private constant ETH_BASE_GWEI = 4_000_000_000; // 4 ETH
    uint256 private constant ETH_BASE = uint256(ETH_BASE_GWEI) * 1e9;
    uint16 private constant ROLL = 120;
    uint256 private constant SEGREGATED_MAX = ETH_BASE * 175 / 100;
    uint256 private constant ROLLED = ETH_BASE * ROLL / 100;

    bytes32 private aggregateSlot;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _stampSlot0(0);
        vm.record();
        sdgnrs.hasPendingRedemptions(DAY);
        (bytes32[] memory reads,) = vm.accesses(address(sdgnrs));
        for (uint256 i; i < reads.length; ++i) {
            if (reads[i] != bytes32(0)) aggregateSlot = reads[i];
        }
        require(aggregateSlot != bytes32(0), "harness: aggregate slot not found");
    }

    function _stampSlot0(uint96 reserved) private {
        uint256 word = uint256(vm.load(address(sdgnrs), bytes32(0)));
        // Clear bits 128..247 (reservation value and stamped day), keep supply and higher bits.
        word &= ~(((uint256(1) << 120) - 1) << 128);
        word |= uint256(reserved) << 128;
        word |= uint256(DAY) << 224;
        vm.store(address(sdgnrs), bytes32(0), bytes32(word));
    }

    function _seed(uint96 reserved) private {
        _stampSlot0(reserved);
        uint256 agg = uint256(vm.load(address(sdgnrs), aggregateSlot));
        agg = (agg & ~uint256(type(uint64).max)) | ETH_BASE_GWEI;
        vm.store(address(sdgnrs), aggregateSlot, bytes32(agg));
        assertEq(sdgnrs.pendingResolveDay(), DAY, "harness: day stamped");
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved, "harness: reservation seeded");
        assertTrue(sdgnrs.hasPendingRedemptions(DAY), "harness: pool pending");
    }

    function _resolve() private {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(ROLL, DAY);
    }

    /// @dev Reservation below the day's MAX share: the release floors at zero and the rolled
    ///      amount becomes the whole reservation. No ETH moves anywhere.
    function test_ReservationBelowMaxShareSaturates() public {
        _seed(uint96(1 ether));
        assertLt(1 ether, SEGREGATED_MAX, "harness: seeded below the MAX share");
        uint256 sdgnrsEth = address(sdgnrs).balance;
        uint256 gameEth = address(game).balance;
        uint256 claimable = game.claimableWinningsOf(address(sdgnrs));

        _resolve();

        assertEq(sdgnrs.pendingRedemptionEthValue(), ROLLED, "rolled amount is the whole reservation");
        assertEq(sdgnrs.pendingResolveDay(), 0, "sentinel cleared: the day is resolved");
        assertEq(sdgnrs.redemptionPeriods(DAY), ROLL, "roll recorded for claims");
        assertFalse(sdgnrs.hasPendingRedemptions(DAY));
        assertEq(address(sdgnrs).balance, sdgnrsEth, "no ETH moved out of sDGNRS");
        assertEq(address(game).balance, gameEth, "no ETH moved out of the game");
        assertEq(game.claimableWinningsOf(address(sdgnrs)), claimable, "no claimable created");
    }

    /// @dev Reachable shape: the reservation holds the MAX share plus other days' value, and the
    ///      release is the exact telescoping difference.
    function test_ReachableReleaseUnchanged() public {
        uint96 others = uint96(3 ether);
        _seed(uint96(SEGREGATED_MAX) + others);

        _resolve();

        assertEq(sdgnrs.pendingRedemptionEthValue(), uint256(others) + ROLLED, "MAX released, rolled retained");
        assertEq(sdgnrs.pendingResolveDay(), 0);
        assertEq(sdgnrs.redemptionPeriods(DAY), ROLL);
    }

    /// @dev Resolve is idempotent on the cleared sentinel in both shapes.
    function test_SecondResolveIsNoOp() public {
        _seed(uint96(1 ether));
        _resolve();
        uint256 afterValue = sdgnrs.pendingRedemptionEthValue();
        _resolve();
        assertEq(sdgnrs.pendingRedemptionEthValue(), afterValue);
        assertEq(sdgnrs.pendingResolveDay(), 0);
    }
}
