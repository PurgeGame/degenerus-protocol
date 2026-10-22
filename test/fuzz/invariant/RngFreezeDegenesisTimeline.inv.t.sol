// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RngWindowFreeze} from "./RngWindowFreeze.inv.t.sol";
import {RngIndexDrainOrderingInvariants} from "./RngIndexDrainOrdering.inv.t.sol";
import {CrapsRngSeal} from "./CrapsRngSeal.inv.t.sol";

/// @title RngFreezeDegenesisTimeline -- the three RNG-freeze suites on the Degenesis timeline
/// @notice Each suite runs unchanged, with its own handler, properties and non-vacuity gate,
///         but deployed on day index 1: its setUp's one-day warp lands on Degenesis day 1, so
///         the campaign runs through the sale (level 0, the Degenesis daily branch, cohort
///         pricing at each daily request, Craps windows from Degenesis day 2) instead of after
///         an empty sale week.

contract RngWindowFreezeDegenesis is RngWindowFreeze {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}

contract RngIndexDrainOrderingDegenesis is RngIndexDrainOrderingInvariants {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    /// @dev Own counter keys, so the non-vacuity floor counts this suite's runs, not the parent's.
    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }
}

contract CrapsRngSealDegenesis is CrapsRngSeal {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}
