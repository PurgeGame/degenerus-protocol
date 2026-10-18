// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenesisDeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisSaleFlowHandler} from "../handlers/DegenesisSaleFlowHandler.sol";

/// @title DegenesisSaleFlow -- the sale's state machine under random interleavings
/// @notice Deploys on day index 1 and lets the handler buy, purchase, mine on bounded gas, delay or
///         answer VRF, warp and drive whole days, across the seven sale days and into the main launch
///         (and, in some runs, a liveness ending). The handler counts every departure from the sale's
///         state machine (see DegenesisSaleFlowHandler); all must stay zero. The ordering and
///         settlement departures are a second, separately falsifiable property.
/// @dev Non-vacuity accumulates over the process (unique DSF_ prefix): buys accepted and rejected off
///      the sale, cohorts priced, orders resolved, cohorts closed, the seventh close with its burn, a
///      launch past day 9, and a launch with the turbo.
contract DegenesisSaleFlow is DegenesisDeployProtocol {
    DegenesisSaleFlowHandler public handler;

    function setUp() public {
        _deployProtocol();
        handler = new DegenesisSaleFlowHandler(game, mockVRF, sdgnrs, 6);
        targetContract(address(handler));
    }

    /// @notice The level stays 0 with no latch through the sale; only well-formed live sale-day buys
    ///         are accepted; sealed cohorts never change; splits only after sealing and never undone;
    ///         degenesisClosed never decreases; nothing stays live after the seventh close or game over.
    function invariant_saleStateMachine() public view {
        assertEq(handler.bad_levelDuringSale(), 0, "level, latch, turbo or jackpot phase during the sale");
        assertEq(handler.bad_buyAccepted(), 0, "a buy was accepted off the sale, after the end, or malformed");
        assertEq(handler.bad_sealedCohortChanged(), 0, "a sealed cohort changed");
        assertEq(handler.bad_splitCleared(), 0, "a split flag cleared");
        assertEq(handler.bad_splitBeforeSeal(), 0, "a cohort split before it sealed or with another volume");
        assertEq(handler.bad_closedRegressed(), 0, "degenesisClosed decreased");
        assertEq(handler.bad_wordWithoutCohort(), 0, "a bound word without an active cohort");
        assertEq(handler.bad_liveAfterSeventhClose(), 0, "sale state live after the seventh close");
        assertEq(handler.bad_liveAfterGameOver(), 0, "an active cohort after game over");
    }

    /// @notice Cohorts price and close strictly in order, price only at a request after their day, each
    ///         order resolves once inside the active cohort, a cohort closes only after all its orders
    ///         resolved, and the inventory burns only at the seventh close.
    function invariant_settlementOrder() public view {
        assertEq(handler.bad_pricedOutOfOrder(), 0, "a cohort priced out of order");
        assertEq(handler.bad_pricedBeforeSeal(), 0, "a cohort priced before its day ended or with another volume");
        assertEq(handler.bad_resolvedTwice(), 0, "an order resolved twice");
        assertEq(handler.bad_resolvedOutsideActive(), 0, "an order resolved outside the active cohort");
        assertEq(handler.bad_closedOutOfOrder(), 0, "a cohort closed out of order");
        assertEq(handler.bad_closedWithUnresolved(), 0, "a cohort closed with unresolved orders");
        assertEq(handler.bad_burnNotOnSeventh(), 0, "inventory burned before the seventh close");
    }

    function _acc(string memory k, uint256 v) internal returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        uint256 runs = _acc("DSF_RUNS", 1);
        uint256 buys = _acc("DSF_buys", handler.ghost_buys());
        uint256 offSale = _acc("DSF_offSaleRejects", handler.ghost_offSaleRejects());
        uint256 priced = _acc("DSF_priced", handler.ghost_priced());
        uint256 resolved = _acc("DSF_resolved", handler.ghost_resolved());
        uint256 closes = _acc("DSF_closes", handler.ghost_closes());
        uint256 burns = _acc("DSF_burns", handler.ghost_burns());
        uint256 launched = _acc("DSF_launched", handler.ghost_launched());
        uint256 turbo = _acc("DSF_turbo", handler.ghost_turbo());
        if (runs < 16) return;
        assertGt(buys, 0, "vacuous: no Degenesis buy accepted");
        assertGt(offSale, 0, "vacuous: no off-sale buy was refused");
        assertGt(priced, 0, "vacuous: no cohort priced");
        assertGt(resolved, 0, "vacuous: no order resolved");
        assertGt(closes, 0, "vacuous: no cohort closed");
        assertGt(burns, 0, "vacuous: the sale never closed with its burn");
        assertGt(launched, 0, "vacuous: no run reached the main launch");
        assertGt(turbo, 0, "vacuous: no run launched with the turbo");
    }
}
