// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {SolvencyActionHandler} from "./SolvencyActionHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @title SolvencyActionHandlerShape — RED-gate construction + surface contract for the new handler.
/// @notice Proves SolvencyActionHandler exists, builds the multi-surface action handler over a DISJOINT
///         actor range, exposes a complete trackedAddrs() cover (actors ++ VAULT/SDGNRS/GNRUS), and surfaces
///         the per-surface success ghost counters the wired invariant uses for its non-vacuity gate. This is
///         the failing-first test that drives the handler into existence (TDD RED → GREEN).
contract SolvencyActionHandlerShape is DeployProtocol {
    SolvencyActionHandler internal h;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        h = new SolvencyActionHandler(game, deityPass, mockVRF, 5);
    }

    function testTrackedAddrsIsCompleteCover() public view {
        address[] memory addrs = h.trackedAddrs();
        // 5 actors ++ the three protocol balance holders.
        assertEq(addrs.length, h.actorCount() + 3, "tracked = actors ++ 3 protocol addrs");
        assertEq(addrs[addrs.length - 3], ContractAddresses.VAULT, "VAULT present");
        assertEq(addrs[addrs.length - 2], ContractAddresses.SDGNRS, "SDGNRS present");
        assertEq(addrs[addrs.length - 1], ContractAddresses.GNRUS, "GNRUS present");
    }

    function testActorsAreInDisjointRange() public view {
        // Actors live in the 0x5A000 band — disjoint from V61AfkingSpendHandler (0xAF000) and
        // WhaleHandler (0xB0000) so the two invariants' actor sets never collide if co-targeted.
        address[] memory addrs = h.trackedAddrs();
        for (uint256 i; i < h.actorCount(); i++) {
            uint160 a = uint160(addrs[i]);
            assertGe(a, uint160(0x5A000), "actor >= 0x5A000 base");
            assertLt(a, uint160(0x5A000 + 1000), "actor in the bounded band");
        }
    }

    function testGhostCountersStartZero() public view {
        assertEq(h.ghost_passBuys(), 0, "passBuys starts 0");
        assertEq(h.ghost_presaleBuys(), 0, "presaleBuys starts 0");
        assertEq(h.ghost_claims(), 0, "claims starts 0");
    }
}
