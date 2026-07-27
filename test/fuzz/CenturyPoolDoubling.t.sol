// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Drives _prizePoolTarget over the real storage layout without pinning a single slot:
///      inheriting the storage base gets the compiler to resolve every offset, so a layout
///      change cannot silently corrupt what these assertions read.
contract CenturyTargetHarness is DegenerusGameStorage {
    function setLevelPool(uint24 lvl, uint256 pool) external {
        levelPrizePool[lvl] = pool;
    }

    function pushCentury(uint128 pool) external {
        centuryPrizePools.push(pool);
    }

    function target(uint24 purchaseLvl) external view returns (uint256) {
        return _prizePoolTarget(purchaseLvl);
    }
}

/// @title CenturyPoolDoubling -- regression suite for the century (x00) prize-pool
///        doubling floor in DegenerusGameStorage._prizePoolTarget.
///
/// @notice A century level's next-pool ratchet target is the previous level's recorded
///         pool raised to a curved multiple of the previous century's achieved pool — the
///         newest entry of centuryPrizePools, empty until the first x00 purchase->jackpot
///         transition pushes one: 2x by default, 1.5x above 500k ETH, 1.3x above 1M ETH.
///         An empty history imposes no floor, and non-century levels use the plain ratchet.
///
///         The target math is pinned against a storage harness, so the table costs no slot
///         constants. The redeem gate is pinned against the REAL deployed game, which is
///         the only part that needs raw storage seeding.
contract CenturyPoolDoublingTest is DeployProtocol {
    // Slot positions (confirmed via `forge inspect DegenerusGame storageLayout`).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant LEVEL_SHIFT = 96; // slot 0 bytes [12:15): level (uint24)
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2; // [volume:48][future:104][next:104]
    uint256 private constant LEVEL_PRIZE_POOL_SLOT = 23; // mapping(uint24 => uint256)
    uint256 private constant CENTURY_POOLS_SLOT = 67; // uint128[] centuryPrizePools

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

    function _harness(uint24 prevLvl, uint256 ratchet)
        internal
        returns (CenturyTargetHarness h)
    {
        h = new CenturyTargetHarness();
        h.setLevelPool(prevLvl, ratchet);
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

    /// @dev Seed the real game's century history with one completed century. A dynamic
    ///      uint128[] keeps its length at its own slot and its elements from
    ///      keccak256(slot), two to a word — so element 0 is the low half of that word.
    function _seedCenturyHistory(uint128 pool) internal {
        vm.store(
            address(game),
            bytes32(CENTURY_POOLS_SLOT),
            bytes32(uint256(1))
        );
        vm.store(
            address(game),
            keccak256(abi.encode(CENTURY_POOLS_SLOT)),
            bytes32(uint256(pool))
        );
    }

    function _setNextPool(uint128 next) internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32((packed & ~((uint256(1) << 104) - 1)) | uint256(next))
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
    // Pre-first-century state (real game)
    // ---------------------------------------------------------------------

    /// @notice The history starts empty and an empty history imposes no floor: level 100
    ///         runs on the plain ratchet until a century has completed.
    function testEmptyHistoryImposesNoFloor() public {
        (, uint256 century100, , , , ) = game.growthState(100);
        assertEq(century100, 0, "history must start empty");
        _setLevel(99); // purchase level 100, no century completed yet
        _setLevelPrizePool(99, 60 ether);
        assertEq(_targetView(), 60 ether, "empty history must leave the plain ratchet");
    }

    // ---------------------------------------------------------------------
    // Target math (harness — no slot constants)
    // ---------------------------------------------------------------------

    /// @notice Century purchase level (100): the doubling floor binds when it exceeds the
    ///         plain ratchet base.
    function testCenturyFloorRaisesTarget() public {
        CenturyTargetHarness h = _harness(99, 60 ether);
        h.pushCentury(100 ether);
        assertEq(h.target(100), 200 ether, "target must be 2x the previous century pool");
    }

    /// @notice Century purchase level: the plain ratchet base wins when it already exceeds
    ///         double the previous century pool.
    function testCenturyRatchetWinsWhenAboveFloor() public {
        CenturyTargetHarness h = _harness(99, 300 ether);
        h.pushCentury(100 ether);
        assertEq(h.target(100), 300 ether, "ratchet base must win above the century floor");
    }

    /// @notice Curve mid tier: above 500k ETH the floor multiplier tapers to 1.5x.
    function testCenturyCurveMidTier() public {
        CenturyTargetHarness h = _harness(99, 60 ether);
        h.pushCentury(600_000 ether);
        assertEq(h.target(100), 900_000 ether, "floor must be 1.5x above 500k ETH");
    }

    /// @notice Curve top tier: above 1M ETH the floor multiplier tapers to 1.3x.
    function testCenturyCurveTopTier() public {
        CenturyTargetHarness h = _harness(99, 60 ether);
        h.pushCentury(2_000_000 ether);
        assertEq(h.target(100), 2_600_000 ether, "floor must be 1.3x above 1M ETH");
    }

    /// @notice Curve boundaries are strict: exactly 500k stays 2x, exactly 1M stays 1.5x.
    function testCenturyCurveBoundaries() public {
        CenturyTargetHarness a = _harness(99, 60 ether);
        a.pushCentury(500_000 ether);
        assertEq(a.target(100), 1_000_000 ether, "exactly 500k must still be 2x");

        CenturyTargetHarness b = _harness(99, 60 ether);
        b.pushCentury(1_000_000 ether);
        assertEq(b.target(100), 1_500_000 ether, "exactly 1M must still be 1.5x");
    }

    /// @notice Non-century purchase level (99): the century history is ignored entirely.
    function testNonCenturyIgnoresCenturyHistory() public {
        CenturyTargetHarness h = _harness(98, 60 ether);
        h.pushCentury(1_000 ether);
        assertEq(h.target(99), 60 ether, "non-century target must be the plain ratchet");
    }

    /// @notice Only the NEWEST century governs the floor — the history is a log, not a sum.
    function testFloorTracksTheNewestCentury() public {
        CenturyTargetHarness h = _harness(199, 60 ether);
        h.pushCentury(100 ether); // century 1
        h.pushCentury(400 ether); // century 2 — the one that must bind
        assertEq(h.target(200), 800 ether, "floor must follow the newest century");
    }

    // ---------------------------------------------------------------------
    // FLIP redeem gate (real game)
    // ---------------------------------------------------------------------

    /// @notice At a century purchase level the redeem window stays shut while nextPool
    ///         clears the plain ratchet but not the doubling floor.
    function testRedeemGateEnforcesCenturyFloor() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _seedCenturyHistory(100 ether);
        assertEq(_targetView(), 200 ether, "setup: seeded history must raise the target");
        _setNextPool(150 ether); // > 60 ratchet, < 200 floor
        assertFalse(_redeem(), "redeem must revert below the century doubling floor");
    }

    /// @notice Once nextPool strictly exceeds the doubled floor the window opens.
    function testRedeemGateOpensAboveCenturyFloor() public {
        _setLevel(99);
        _setLevelPrizePool(99, 60 ether);
        _seedCenturyHistory(100 ether);
        // Without this the case is vacuous: an unseeded history leaves the target at the
        // 60-ETH ratchet, which 201 clears for the wrong reason.
        assertEq(_targetView(), 200 ether, "setup: seeded history must raise the target");
        _setNextPool(201 ether); // > 200 floor
        assertTrue(_redeem(), "redeem should succeed above the century doubling floor");
    }
}
