// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {LoanAccountingHandler} from "../handlers/LoanAccountingHandler.sol";

/// @title LoanAccounting -- account loans against an independent spec ledger (docs/ACCOUNT-LOANS.md)
/// @notice After every step:
///         1. every closed loan paid its lender exactly the spec amount (early: P(100+T+4c)/100,
///            at the due level: P(1+5%T)) or the lender owns the account; nothing else happens;
///         2. each lender's claimable + AFKing moved by exactly receipts - principals + sweeps;
///         3. a borrow credits principal - ticket part to AFKing without moving custody, the ticket part (half, whole tickets,
///            past day 20 of the purchase phase, never in the jackpot phase) as entries at the
///            active level, pooled 90/10;
///         4. canonical solvency holds, and no loan, funding, sweep or claim step moves
///            backing - obligations;
///         5. owners, open loans and due lists match the model (main seizure takes the family, a
///            smurf seized alone keeps its lender, one open loan per account, swap-and-pop lists).
///         `afterInvariant` requires each run to have borrowed (on day 20 and after it), repaid,
///         auto-repaid and seized; the handler's fixed opening forces all of them.
/// @dev Campaign size: the repo `[invariant]` default (256 runs x 128 depth).
contract LoanAccountingInvariant is DeployProtocol {
    LoanAccountingHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        handler = new LoanAccountingHandler(game, sdgnrs, vault);
        handler.init();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.step.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function _noViolations(uint256 inv) internal view {
        (uint256 n, string memory first) = handler.violations(inv);
        assertEq(n, 0, first);
    }

    function invariant_closedLoansPaidSpecOrSeized() public view {
        _noViolations(1);
    }

    function invariant_lenderLedger() public view {
        _noViolations(2);
        handler.checkLedger();
    }

    function invariant_borrowCredit() public view {
        _noViolations(3);
    }

    function invariant_solvency() public view {
        _noViolations(4);
        handler.checkSolvency();
    }

    function invariant_ownershipAndDueLists() public view {
        _noViolations(5);
        handler.checkOwnership();
    }

    /// @notice Progress floor per run, plus a coverage report accumulated across runs.
    function afterInvariant() public {
        assertGt(handler.ghost_borrows(), 0, "no borrow");
        assertGt(handler.ghost_ticketBorrows(), 0, "no late-window borrow");
        assertGt(handler.ghost_day20Borrows(), 0, "no borrow on the day-20 boundary");
        assertGt(handler.ghost_repays(), 0, "no repayment");
        assertGt(handler.ghost_autoRepays(), 0, "no auto-repayment");
        assertGt(handler.ghost_seizures(), 0, "no seizure");

        _bump("LA_RUNS", 1);
        _bump("LA_CALLS", handler.calls());
        _bump("LA_BORROWS", handler.ghost_borrows());
        _bump("LA_TICKET_BORROWS", handler.ghost_ticketBorrows());
        _bump("LA_DAY20_BORROWS", handler.ghost_day20Borrows());
        _bump("LA_JACKPOT_BORROWS", handler.ghost_jackpotBorrows());
        _bump("LA_VAULT_LOANS", handler.ghost_vaultLoans());
        _bump("LA_SMURF_LOANS", handler.ghost_smurfLoans());
        _bump("LA_REPAYS", handler.ghost_repays());
        _bump("LA_REPAYS_CLAIMABLE", handler.ghost_repaysFromClaimable());
        _bump("LA_AUTO_REPAYS", handler.ghost_autoRepays());
        _bump("LA_SEIZURES", handler.ghost_seizures());
        _bump("LA_MAIN_SEIZURES", handler.ghost_mainSeizures());
        _bump("LA_ORPHAN_SEIZURES", handler.ghost_orphanSeizures());
        _bump("LA_CHUNKED", handler.ghost_chunkedSettles());
        _bump("LA_SWEEPS", handler.ghost_sweeps());
        _bump("LA_CLAIMS", handler.ghost_claims());
        _bump("LA_GATE_REJECTS", handler.ghost_gateRejects());
        _bump("LA_CLOSED", handler.ghost_closed());
        string[18] memory keys = ["LA_RUNS", "LA_CALLS", "LA_BORROWS", "LA_TICKET_BORROWS", "LA_DAY20_BORROWS",
            "LA_JACKPOT_BORROWS",
            "LA_VAULT_LOANS", "LA_SMURF_LOANS", "LA_REPAYS", "LA_REPAYS_CLAIMABLE", "LA_AUTO_REPAYS", "LA_SEIZURES",
            "LA_MAIN_SEIZURES", "LA_ORPHAN_SEIZURES", "LA_CHUNKED", "LA_SWEEPS", "LA_CLAIMS", "LA_GATE_REJECTS"];
        for (uint256 i; i < keys.length; ++i) {
            console.log(string.concat("LA_REPORT ", keys[i], "=", vm.toString(vm.envOr(keys[i], uint256(0)))));
        }
        console.log(string.concat("LA_REPORT LA_CLOSED=", vm.toString(vm.envOr("LA_CLOSED", uint256(0)))));
    }

    function _bump(string memory key, uint256 by) internal {
        vm.setEnv(key, vm.toString(vm.envOr(key, uint256(0)) + by));
    }
}
