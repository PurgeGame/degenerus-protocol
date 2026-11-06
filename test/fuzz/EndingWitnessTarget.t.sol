// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {EndingWitness} from "./helpers/EndingWitness.sol";

/// @dev The engine's own `_prizePoolTarget` over the real storage layout, so the witness's raw
///      slot reads are compared against the compiler-resolved ones.
contract EndingTargetHarness is DegenerusGameStorage {
    function setLevelPool(uint24 lvl, uint256 pool) external {
        _setLevelPrizePool(lvl, pool);
    }

    function pushCentury(uint128 pool) external {
        centuryPrizePools.push(pool);
    }

    function target(uint24 purchaseLvl) external view returns (uint256) {
        return _prizePoolTarget(purchaseLvl);
    }
}

/// @title EndingWitnessTarget -- the purchase-timeout oracle reads the engine's exact pool target
/// @notice The premature-ending witness re-derives `_prizePoolTarget` from raw storage. These
///         tests compare it with the engine's own function on the same storage, at ordinary
///         levels, at century levels on every floor tier, and where the previous level's
///         recycled slot already holds another level (a zero target, as the engine reads it).
contract EndingWitnessTargetTest is Test {
    function _check(EndingTargetHarness h, uint24 purchaseLvl) internal view {
        assertEq(EndingWitness.prizePoolTarget(address(h), purchaseLvl), h.target(purchaseLvl), "witness target");
    }

    function testFuzz_targetMatchesTheEngine(
        uint24 purchaseLvl,
        uint128 prevPool,
        bool stale,
        uint8 centuries,
        uint128 seedPool
    ) public {
        purchaseLvl = uint24(bound(purchaseLvl, 1, 1_000));
        EndingTargetHarness h = new EndingTargetHarness();
        // A stale slot holds the level four below, which shares its recycled position.
        if (stale && purchaseLvl > 4) h.setLevelPool(purchaseLvl - 5, prevPool);
        else h.setLevelPool(purchaseLvl - 1, prevPool);
        centuries = uint8(bound(centuries, 0, 5));
        for (uint256 i; i < centuries; ++i) {
            h.pushCentury(uint128(uint256(keccak256(abi.encode(seedPool, i))) % 3_000_000 ether));
        }
        _check(h, purchaseLvl);
    }

    function test_centuryFloorOnEveryTier() public {
        uint128[4] memory snaps = [uint128(400_000 ether), 500_000 ether, 800_000 ether, 1_500_000 ether];
        for (uint256 t; t < snaps.length; ++t) {
            for (uint256 n = 1; n <= 3; ++n) {
                EndingTargetHarness h = new EndingTargetHarness();
                h.setLevelPool(199, 1 ether);
                for (uint256 i; i < n; ++i) h.pushCentury(i + 1 == n ? snaps[t] : uint128(7 ether));
                _check(h, 200);
                assertGt(h.target(200), 1 ether, "the century floor binds");
            }
        }
    }

    function test_staleSlotIsAZeroTarget() public {
        EndingTargetHarness h = new EndingTargetHarness();
        h.setLevelPool(41, 50 ether);
        assertEq(h.target(46), 0, "the engine reads a recycled slot as zero");
        _check(h, 46);
        h.setLevelPool(95, 50 ether);
        h.pushCentury(10 ether);
        _check(h, 100);
        assertEq(h.target(100), 20 ether, "a century over a recycled slot is the floor alone");
    }
}
