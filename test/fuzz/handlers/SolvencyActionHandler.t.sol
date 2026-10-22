// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameSlots} from "../../helpers/GameSlots.sol";

import {DeployProtocol, DegenesisDeployProtocol} from "../helpers/DeployProtocol.sol";
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
        h = new SolvencyActionHandler(game, deityPass, mockVRF, 5, false);
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
        assertEq(h.ghost_boxBuys(), 0, "boxBuys starts 0");
        assertEq(h.ghost_degenesisBuys(), 0, "degenesisBuys starts 0");
        assertEq(h.ghost_claims(), 0, "claims starts 0");
    }
}

/// @title SolvencyActionHandlerDegenesis -- the Degenesis actions are reachable on the day-1 timeline.
contract SolvencyActionHandlerDegenesis is DegenesisDeployProtocol {
    SolvencyActionHandler internal h;
    address internal actor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days); // Degenesis day 1
        vm.deal(address(game), 5_000_000 ether);
        h = new SolvencyActionHandler(game, deityPass, mockVRF, 5, true);
        actor = h.actors(1);
    }

    function _budget() internal view returns (uint256) {
        return uint128(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET))));
    }

    function testDegenesisBuyEarnsCreditAndSplitsAtTheDailyRequest() public {
        // A credit-earning purchase then a Degenesis buy, once per payment mode.
        for (uint256 mode; mode < 4; ++mode) h.buyDegenesis(1, 1 ether, 1 ether, mode);
        assertGt(h.ghost_degenesisBuys(), 0, "a Degenesis box was bought");
        assertGt(h.ghost_degenesisVolume(), 0, "volume recorded");
        assertGt(h.ghost_degenesisClaimableFunded(), 0, "a buy drew claimable or afking");
        assertEq(_budget(), 0, "nothing splits before the day seals");

        h.warpDay();
        h.advance(1, 7);
        h.advance(1, 8);
        assertGt(_budget(), 0, "the daily request split the sealed cohort into the Vault budget");

        h.spendVaultBudget(400, 0, 1);
        assertEq(h.ghost_vaultSpends(), 1, "the Vault spent budget on a ticket");
    }
}
