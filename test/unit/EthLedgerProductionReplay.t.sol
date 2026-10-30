// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EthLedgerProductionProof} from "../halmos/EthLedgerProductionProof.t.sol";

contract EthLedgerProductionReplay is EthLedgerProductionProof {
    function test_symbolicCounterexamplesReplay() public {
        check_loan_credit_retains_total_obligations(7, 8, 0, 0, 0, 0, 0, 0, true);
        check_loan_credit_retains_total_obligations(7, 8, 0, 0, 0, 0, 0, 0, false);
        check_claim_credit_is_local(7, 8, 0, 2 ** 95, 2 ** 95, 0);
        check_combined_debit_keeps_lanes_separate(7, 8, 0, 2 ** 95, 0, 0);
        check_prepaid_credit_accounts_liability(7, 8, 0, 2 ** 95, 2 ** 95, 0);
        check_shortfall_conserves_and_preserves_sentinel(7, 8, 0, 2 ** 95, 1, true);
        check_shortfall_conserves_and_preserves_sentinel(7, 8, 0, 0, 0, false);
    }

    function testFuzz_ledgerTransitions(uint96 claim, uint96 prepaid, uint96 amount) public {
        claimablePool = 0;
        check_claim_credit_is_local(7, 8, claim, prepaid, amount, 123);
        check_prepaid_credit_accounts_liability(7, 8, claim, prepaid, amount, claim);
        check_combined_debit_keeps_lanes_separate(7, 8, claim, prepaid, claim, prepaid);
        check_shortfall_conserves_and_preserves_sentinel(7, 8, claim, prepaid, amount, true);
        check_redemption_release_is_reclassification_and_once(claim, prepaid, amount);
        check_loan_credit_retains_total_obligations(7, 8, claim, prepaid, amount, claim, prepaid, claim / 2, true);
        check_loan_credit_retains_total_obligations(7, 8, claim, prepaid, amount, claim, prepaid, prepaid / 2, false);
    }
}
