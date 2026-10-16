// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Regression coverage for request-bound, forward-priced redemption batches.
contract RedemptionGasTest is RedemptionFixture {
    /// @dev Admits any single claim. Independent assertion of the protocol limit: a claim's
    ///      admission bound is base 600k plus one 3.2M human entry and 125k per box, capped at
    ///      twenty boxes (6.3M); with its 1/63 call retention, 12k call reserve, 100k tail and
    ///      2k check reserve it needs ~6.514M.
    uint256 private constant ONE_CLAIM_ALLOWANCE = 7_000_000;

    function test_gas_burn_gambling() public {
        vm.cool(address(sdgnrs)); vm.cool(address(game));
        uint256 before = gasleft();
        _burn(alice, 1e18);
        uint256 used = before - gasleft();
        emit log_named_uint("cold burn", used);
        assertLt(used, 350_000);
    }
    function test_gas_burnWrapped_gambling() public {
        _dgnrsFromVault(alice, 1e18);
        vm.prank(alice); sdgnrs.burnWrapped(1e18);
        assertEq(_claimTokens(alice, _openBatchId()), 1e18);
    }
    function test_gas_closeRedemptionBatch() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        vm.cool(address(sdgnrs)); vm.cool(address(coinflip));
        uint256 before = gasleft(); _closeAsGame();
        uint256 used = before - gasleft();
        emit log_named_uint("cold batch close", used);
        assertLt(used, 1_000_000);
    }
    function test_gas_settleRedemption() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolveLive(175);
        vm.cool(address(sdgnrs)); vm.cool(address(game));
        uint256 before = gasleft(); assertTrue(_work(ONE_CLAIM_ALLOWANCE));
        emit log_named_uint("cold claim settlement", before - gasleft());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

}
