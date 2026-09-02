// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {CrapsRngSealHandler} from "../handlers/CrapsRngSealHandler.sol";

/// @title CrapsRealWiringConservation — the table's payout liability through the REAL ring.
///
/// @notice The craps conservation campaign (CrapsConservation.inv) proves the table's books
///         against mocks that record what crosses the boundary. This campaign drives the SAME
///         doors through the real FLIP burn gate, the real Coinflip credit lane and the real
///         vault, with no mock in the loop. A craps win is credited as next-day coinflip stake —
///         minted value, by design an expected-value sink with variance, so the table is not a
///         closed pool and "out <= in" is not its invariant. Its solvency claim is a LIABILITY
///         BOUND: every settling call credits at most what the settlement itself can draw from —
///         each slip's own previewed return, the field's pooled stake, the day's ladder and high
///         budgets, and the progressive balance. A credit beyond that bound would be a payout
///         from a source the design does not have.
///
///         Alongside it, the vault's lifetime comp budget: exactly two hundred day passes, every
///         grant debited once, an over-ask refused whole.
///
/// @dev Test-only. Same handler as the RNG seal campaign (real lifecycle); credits are measured
///      in isolation around each settling call so the coinflip's own daily resolution never
///      pollutes the figure. The burned / subsidy / pass-seat ghosts are kept as surveillance.
contract CrapsRealWiringConservation is DeployProtocol {
    CrapsRngSealHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);

        handler = new CrapsRngSealHandler(game, mockVRF, coin, crapsBattle, 5);
        targetContract(address(handler));

        bytes4[] memory excluded = new bytes4[](1);
        excluded[0] = CrapsRngSealHandler.debugSeedWordedArmAndCheck.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    /// @notice THE SPINE: no settlement credits more than the settlement can draw from.
    function invariant_creditsNeverExceedTheSettlementBound() public view {
        if (handler.ghost_creditsOverBound() != 0) {
            revert(
                string.concat(
                    "CRAPS-LEDGER: a settling call credited more stake than its liability bound: credited=",
                    vm.toString(handler.ghost_lastOverCredited()),
                    " bound=",
                    vm.toString(handler.ghost_lastOverBound()),
                    " slot=",
                    vm.toString(handler.ghost_lastOverSlot()),
                    handler.ghost_lastOverWasKeep() ? " (keeper crank)" : " (resolveSlot)"
                )
            );
        }
    }

    /// @notice The vault's comp budget is a lifetime two hundred, debited exactly once per pass.
    function invariant_vaultCompBudgetExact() public view {
        assertEq(
            uint256(vault.crapsCompsRemaining()),
            200 - handler.ghost_compsGranted(),
            "VAULT-COMPS: remaining budget diverged from the grants"
        );
        assertTrue(
            handler.ghost_compGrantsRefused() != type(uint256).max,
            "VAULT-COMPS: an over-ask was served or a within-budget grant was refused"
        );
    }

    function invariant_ledgerExercised() public view {
        handler.ghost_flipBurnedIn();
        handler.ghost_subsidies();
        handler.ghost_passSeatValue();
        handler.ghost_creditedOut();
        handler.ghost_creditsOverBound();
        handler.ghost_compsGranted();
        handler.ghost_compGrantsRefused();
    }

    function afterInvariant() public view {
        assertGt(handler.ghost_creditedOut(), 0, "vacuous: no settlement ever credited stake");
        assertGt(handler.ghost_flipBurnedIn(), 0, "vacuous: no FLIP was ever burned into the table");
        assertGt(handler.ghost_subsidies(), 0, "vacuous: no day ever opened with a budget");
        assertGt(handler.ghost_compsGranted(), 0, "vacuous: the vault never granted a comp");
    }
}
