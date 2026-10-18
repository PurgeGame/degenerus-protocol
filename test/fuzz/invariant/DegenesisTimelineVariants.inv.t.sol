// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {LoanAccountingInvariant} from "./LoanAccounting.inv.t.sol";
import {RedemptionInvariants} from "./RedemptionInvariants.inv.t.sol";

/// @title LoanAccountingDegenesis -- the loan ledger, payout and solvency invariants on the day-1
///        timeline, so borrowing, repayment and seizure run through the Degenesis week and the
///        level-1 launch that follows it.
contract LoanAccountingDegenesis is LoanAccountingInvariant {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}

/// @title RedemptionInvariantsDegenesis -- sDGNRS redemption solvency, supply and claim invariants
///        on the day-1 timeline, while Degenesis cohorts split into sDGNRS AFKing and pay sDGNRS.
contract RedemptionInvariantsDegenesis is RedemptionInvariants {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    /// @dev Own counter keys, so the non-vacuity floor counts this suite's runs, not the parent's.
    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }
}
