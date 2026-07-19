// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title CenturyDrivenTransition -- driven end-to-end proof of the century (x00)
///        prize-pool doubling floor through the REAL advance path.
///
/// @notice Drives the full protocol from level 0 through the level-200 transition with
///         organic advanceGame/VRF cycles (pool seeded via vm.store each level, tickets =
///         the constructor's perpetual vault/sDGNRS entries). Proves, in order:
///         1. level 100 carries NO century floor (snapshot still zero): its target is the
///            plain ratchet, and the transition snapshots the achieved pool;
///         2. after the century jackpot ends, _endPhase resets levelPrizePool[100] to the
///            reachable x01 base while the century snapshot survives untouched;
///         3. at level 199's purchase phase the effective target is the curved floor
///            (2x the level-100 snapshot), not the plain ratchet;
///         4. a pool ABOVE the plain ratchet but BELOW the floor does NOT latch the
///            level-200 transition (and does not end the game);
///         5. a pool above the floor transitions into level 200, and the snapshot
///            advances to level 200's achieved pool.
contract CenturyDrivenTransitionTest is DeployProtocol {
    // Slot positions (confirmed via `forge inspect DegenerusGame storageLayout`).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant JACKPOT_PHASE_SHIFT = 120; // byte 15: jackpotPhaseFlag
    uint256 private constant RNG_LOCKED_SHIFT = 152; // byte 19: rngLockedFlag
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2; // [future:128][next:128]
    uint256 private constant LEVEL_PRIZE_POOL_SLOT = 23; // mapping(uint24 => uint256)
    uint256 private constant CENTURY_SLOT = 63;
    uint256 private constant CENTURY_SHIFT = 80; // bytes [10:26): lastCenturyPrizePool

    uint256 private simTime;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        // Solvency backing for 200 levels of seeded pools and jackpot payouts.
        vm.deal(address(game), 100_000 ether);
        // The 200-level drive runs ~10k advance transactions; unmetered so the
        // cumulative burn stays under the harness per-test gas limit.
        vm.pauseGasMetering();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _slot0() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(SLOT_0)));
    }

    function _jackpotPhase() internal view returns (bool) {
        return ((_slot0() >> JACKPOT_PHASE_SHIFT) & 0xFF) != 0;
    }

    function _rngLocked() internal view returns (bool) {
        return ((_slot0() >> RNG_LOCKED_SHIFT) & 0xFF) != 0;
    }

    function _nextPool() internal view returns (uint256) {
        return uint128(
            uint256(
                vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
            )
        );
    }

    /// @dev Raise nextPrizePool to `targetNext` (never lowers; preserves future half).
    function _seedNextPool(uint256 targetNext) internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        if (uint256(uint128(packed)) >= targetNext) return;
        uint128 future = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32((uint256(future) << 128) | targetNext)
        );
    }

    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        bytes32 slot = keccak256(
            abi.encode(uint256(lvl), LEVEL_PRIZE_POOL_SLOT)
        );
        return uint256(vm.load(address(game), slot));
    }

    function _centurySnapshot() internal view returns (uint128) {
        return uint128(
            uint256(vm.load(address(game), bytes32(CENTURY_SLOT))) >>
                CENTURY_SHIFT
        );
    }

    function _targetView() internal view returns (uint256) {
        (bool ok, bytes memory data) = address(game).staticcall(
            abi.encodeWithSignature("prizePoolTargetView()")
        );
        require(ok, "view failed");
        return abi.decode(data, (uint256));
    }

    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(
            keccak256(abi.encode(block.timestamp, game.level(), reqId))
        );
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    /// @dev Advance one calendar day: warp, then drive advanceGame + VRF fulfillment
    ///      until the day is fully drained (advance reverts NotTimeYet). The 300-call
    ///      budget covers the century jackpot days, whose metered multi-tx drain runs
    ///      far deeper than a normal daily cycle; an undrained remainder simply
    ///      carries into the next day's mid-day path.
    function _driveDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 j = 0; j < 300; j++) {
            _fulfillVrfIfPending();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }
    }

    // ---------------------------------------------------------------------
    // The driven century lifecycle
    // ---------------------------------------------------------------------

    function testCenturyTransitionRequiresCurvedPool() public {
        // --- Phase A: drive levels 1-99 organically with just-met targets ---
        // Seed nextPool a hair over the live target each purchase day, so each level's
        // recorded ratchet stays near bootstrap scale (~51 ETH by level 99).
        _driveToLevelPurchasePhase(99, 1500);

        // --- Phase B: no floor at the first century; the transition snapshots it ---
        uint256 plainRatchet = _levelPrizePool(99);
        assertGt(plainRatchet, 0, "ratchet base must be recorded");
        assertEq(_centurySnapshot(), 0, "snapshot must still be zero before level 100");
        assertEq(
            _targetView(),
            plainRatchet,
            "level-100 target must be the plain ratchet while the snapshot is zero"
        );

        // Fund the first century big so the level-200 floor sits far above later
        // ratchets: the century pool spills into futurePool at consolidation, and
        // _endPhase reseeds levelPrizePool[100] from futurePool/3, so the floor only
        // towers over the post-reset ratchet when the century pool dwarfs that spill.
        // (The jackpot may run compressed — a target met this early legitimately
        // compresses the jackpot days, so _endPhase can reset levelPrizePool[100]
        // within the same drive. The snapshot is the durable observable.)
        _seedNextPool(10_000 ether);
        for (uint256 i = 0; i < 10 && game.level() < 100; i++) {
            _driveDay();
        }
        assertEq(game.level(), 100, "target-met pool must advance into level 100");

        uint256 achieved = uint256(_centurySnapshot());
        assertGe(
            achieved,
            10_000 ether,
            "transition must snapshot the achieved (funded) pool as the doubling base"
        );

        // --- Phase C: _endPhase resets the x01 base; the snapshot survives ---
        for (uint256 i = 0; i < 15 && game.level() < 101; i++) {
            if (!_jackpotPhase() && !_rngLocked()) {
                _seedNextPool(_targetView() + 0.01 ether);
            }
            _driveDay();
        }
        assertEq(game.level(), 101, "game must continue past the century");
        assertTrue(
            _levelPrizePool(100) != achieved,
            "endPhase must reset levelPrizePool[100] to the x01 restart base"
        );
        assertEq(
            _centurySnapshot(),
            uint128(achieved),
            "century snapshot must survive the endPhase reset"
        );

        // --- Phase D: the curved floor governs the level-200 target ---
        _driveToLevelPurchasePhase(199, 1500);
        uint256 floor = 2 * achieved; // 2x tier: snapshot far below 500k ETH
        uint256 ratchet199 = _levelPrizePool(199);
        assertLt(
            ratchet199,
            floor,
            "setup: plain ratchet must sit below the century floor"
        );
        assertEq(
            _targetView(),
            floor,
            "level-200 target must be the curved floor, not the ratchet"
        );

        // Above the plain ratchet but below the floor: the transition must NOT latch.
        _seedNextPool(ratchet199 + 100 ether);
        assertLt(_nextPool(), floor, "setup: pool must stay below the floor");
        for (uint256 i = 0; i < 4; i++) {
            _driveDay();
        }
        assertEq(game.level(), 199, "sub-floor pool must not advance the century");
        assertFalse(
            _jackpotPhase(),
            "sub-floor pool must not enter the century jackpot"
        );
        assertFalse(game.gameOver(), "sub-floor stall must not end the game");

        // --- Phase E: above the floor the transition proceeds; snapshot advances ---
        _seedNextPool(floor + 0.01 ether);
        for (uint256 i = 0; i < 10 && game.level() < 200; i++) {
            _driveDay();
        }
        assertEq(game.level(), 200, "supra-floor pool must advance into level 200");
        uint256 achieved200 = uint256(_centurySnapshot());
        assertGt(
            achieved200,
            floor,
            "snapshot must advance to level 200's achieved pool, above its floor"
        );
        assertFalse(game.gameOver(), "game must be alive after the second century");
    }

    /// @dev Drive organically (target seeded just-met each purchase day) until `lvl`'s
    ///      purchase phase is reached with the day drained and no RNG in flight.
    function _driveToLevelPurchasePhase(uint24 lvl, uint256 maxDays) internal {
        for (uint256 day = 0; day < maxDays; day++) {
            if (game.level() >= lvl && !_jackpotPhase() && !_rngLocked()) break;
            assertFalse(game.gameOver(), "game must not die during the drive");
            if (!_jackpotPhase() && !_rngLocked()) {
                _seedNextPool(_targetView() + 0.01 ether);
            }
            _driveDay();
        }
        assertEq(game.level(), lvl, "drive must reach the requested level");
        assertFalse(_jackpotPhase(), "requested level must be in purchase phase");
    }
}
