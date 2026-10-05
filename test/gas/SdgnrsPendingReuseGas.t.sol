// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Regression coverage for request-bound, forward-priced redemption batches.
contract SdgnrsPendingReuseGasTest is RedemptionFixture {

    function test_ColdAlternatingBatchListsThroughFourRequests() public {
        for (uint256 i; i < 4; ++i) {
            uint32 id = _openBatchId();
            _burn(alice, 1 ether); _burn(bob, 1 ether);
            _resolveLive(100);
            assertTrue(_work(9_000_000));
            assertEq(_claimTokens(alice,id) + _claimTokens(bob,id), 0);
            assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
            assertEq(_openBatchId(), id + 1);
            assertFalse(sdgnrs.redemptionSettlementPending());
        }
    }

}
