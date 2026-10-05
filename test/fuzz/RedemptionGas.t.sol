// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Regression coverage for request-bound, forward-priced redemption batches.
contract RedemptionGasTest is RedemptionFixture {

    function test_gas_burn_gambling() public {
        vm.cool(address(sdgnrs)); vm.cool(address(game));
        uint256 before = gasleft();
        _burn(alice, 1 ether);
        uint256 used = before - gasleft();
        emit log_named_uint("cold burn", used);
        assertLt(used, 350_000);
    }
    function test_gas_burnWrapped_gambling() public {
        dgnrs.transfer(alice, 1000 ether);
        vm.prank(alice); sdgnrs.burnWrapped(1000 ether);
        assertEq(_claimTokens(alice, _openBatchId()), 1000 ether);
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
        uint256 before = gasleft(); assertTrue(_work(4_000_000));
        emit log_named_uint("cold claim settlement", before - gasleft());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

}
