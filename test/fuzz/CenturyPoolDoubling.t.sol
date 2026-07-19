// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title CenturyPoolDoubling -- regression suite for the century (x00) prize-pool
///        doubling floor in DegenerusGameStorage._prizePoolTarget.
///
/// @notice A century level's next-pool ratchet target is the previous level's recorded
///         pool raised to a curved multiple of the previous century's achieved pool
///         (lastCenturyPrizePool, zero until the first x00 purchase->jackpot transition
///         snapshots it): 2x by default, 1.5x above 500k ETH, 1.3x above 1M ETH. A zero
///         snapshot imposes no floor, and non-century levels use the plain ratchet.
///         These tests pin the target math through prizePoolTargetView and the FLIP
///         redeem gate by forcing level, the ratchet mapping, and the century snapshot
///         directly.
contract CenturyPoolDoublingTest is DeployProtocol {
    // Slot positions (confirmed via `forge inspect DegenerusGame storageLayout`).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant LEVEL_SHIFT = 96; // slot 0 bytes [12:15): level (uint24)
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2; // [future:128][next:128]
    uint256 private constant LEVEL_PRIZE_POOL_SLOT = 23; // mapping(uint24 => uint256)
    uint256 private constant CENTURY_SLOT = 63; // shared with foil cursors
    uint256 private constant CENTURY_SHIFT = 80; // slot 63 bytes [10:26): lastCenturyPrizePool (uint128)

    uint256 private constant REDEEM_QTY = 4000; // 10 whole tickets, above the min buy-in

    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("century_buyer");
        vm.deal(address(game), 5_000 ether);
        _fundFlip(buyer, 1_000_000 ether);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT_0)));
        s0 &= ~(uint256(0xFFFFFF) << LEVEL_SHIFT);
        s0 |= uint256(lvl) << LEVEL_SHIFT;
        vm.store(address(game), bytes32(SLOT_0), bytes32(s0));
    }

    function _setLevelPrizePool(uint24 lvl, uint256 pool) internal {
        bytes32 slot = keccak256(
            abi.encode(uint256(lvl), LEVEL_PRIZE_POOL_SLOT)
        );
        vm.store(address(game), slot, bytes32(pool));
    }

    function _setLastCenturyPool(uint128 pool) internal {
        uint256 word = uint256(
            vm.load(address(game), bytes32(CENTURY_SLOT))
        );
        word &= ~(((uint256(1) << 128) - 1) << CENTURY_SHIFT);
        word |= uint256(pool) << CENTURY_SHIFT;
        vm.store(address(game), bytes32(CENTURY_SLOT), bytes32(word));
    }

    function _setNextPool(uint128 next) internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        uint128 future = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32((uint256(future) << 128) | uint256(next))
        );
    }

    function _targetView() internal view returns (uint256) {
        (bool ok, bytes memory data) = address(game).staticcall(
            abi.encodeWithSignature("prizePoolTargetView()")
        );
        require(ok, "view failed");
        return abi.decode(data, (uint256));
    }

    function _redeem() internal returns (bool ok) {
        vm.prank(buyer);
        (ok, ) = address(game).call(
            abi.encodeWithSignature(
                "redeemFlip(address,uint256)",
                buyer,
                REDEEM_QTY
            )
        );
    }

    // ---------------------------------------------------------------------
    // Pre-first-century state
    // ---------------------------------------------------------------------

    /// @notice The snapshot starts at zero and a zero snapshot imposes no floor:
    ///         level 100 runs on the plain ratchet until a century has completed.
    function testZeroSnapshotImposesNoFloor() public {
        uint256 word = uint256(
            vm.load(address(game), bytes32(CENTURY_SLOT))
        );
        assertEq(uint128(word >> CENTURY_SHIFT), 0, "snapshot must start at zero");
        _setLevel(99); // purchase level 100, no century completed yet
        _setLevelPrizePool(99, 60 ether);
        assertEq(_targetView(), 60 ether, "zero snapshot must leave the plain ratchet");
    }

    // ---------------------------------------------------------------------
    // Target math (prizePoolTargetView)
    // ---------------------------------------------------------------------

    /// @notice Century purchase level (100): the doubling floor binds when it exceeds the
    ///         plain ratchet base.
    function testCenturyFloorRaisesTarget() public {
        _setLevel(99); // purchase level 100
        _setLevelPrizePool(99, 60 ether);
        _setLastCenturyPool(100 ether);
        assertEq(_targetView(), 200 ether, "target must be 2x the previous century pool");
    }

    /// @notice Century purchase level: the plain ratchet base wins when it already exceeds
    ///         double the previous century pool.
    function testCenturyRatchetWinsWhenAboveFloor() public {
        _setLevel(99);
        _setLevelPrizePool(99, 300 ether);
        _setLastCenturyPool(100 ether);
        assertEq(_targetView(), 300 ether, "ratchet base must win above the century floor");
    }

    /// @notice Curve mid tier: above 500k ETH the floor multiplier tapers to 1.5x.
    function testCenturyCurveMidTier() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _setLastCenturyPool(600_000 ether);
        assertEq(_targetView(), 900_000 ether, "floor must be 1.5x above 500k ETH");
    }

    /// @notice Curve top tier: above 1M ETH the floor multiplier tapers to 1.3x.
    function testCenturyCurveTopTier() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _setLastCenturyPool(2_000_000 ether);
        assertEq(_targetView(), 2_600_000 ether, "floor must be 1.3x above 1M ETH");
    }

    /// @notice Curve boundaries are strict: exactly 500k stays 2x, exactly 1M stays 1.5x.
    function testCenturyCurveBoundaries() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _setLastCenturyPool(500_000 ether);
        assertEq(_targetView(), 1_000_000 ether, "exactly 500k must still be 2x");
        _setLastCenturyPool(1_000_000 ether);
        assertEq(_targetView(), 1_500_000 ether, "exactly 1M must still be 1.5x");
    }

    /// @notice Non-century purchase level (99): the century snapshot is ignored entirely.
    function testNonCenturyIgnoresCenturySnapshot() public {
        _setLevel(98); // purchase level 99
        _setLevelPrizePool(98, 60 ether);
        _setLastCenturyPool(1_000 ether);
        assertEq(_targetView(), 60 ether, "non-century target must be the plain ratchet");
    }

    // ---------------------------------------------------------------------
    // FLIP redeem gate
    // ---------------------------------------------------------------------

    /// @notice At a century purchase level the redeem window stays shut while nextPool
    ///         clears the plain ratchet but not the doubling floor.
    function testRedeemGateEnforcesCenturyFloor() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _setLastCenturyPool(100 ether);
        _setNextPool(150 ether); // > 60 ratchet, < 200 floor
        assertFalse(_redeem(), "redeem must revert below the century doubling floor");
    }

    /// @notice Once nextPool strictly exceeds the doubled floor the window opens.
    function testRedeemGateOpensAboveCenturyFloor() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _setLastCenturyPool(100 ether);
        _setNextPool(201 ether); // > 200 floor
        assertTrue(_redeem(), "redeem should succeed above the century doubling floor");
    }
}
