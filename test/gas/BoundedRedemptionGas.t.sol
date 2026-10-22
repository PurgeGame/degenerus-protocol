// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";

contract BoundedRedemptionGasTest is RedemptionFixture, BoundedGasProbe {
    function test_P1_FirstBatchBurn() public {
        _measureBounded("P1_first_burn", address(sdgnrs), alice, 0,
            abi.encodeCall(sdgnrs.burn, (sdgnrs.totalSupply() / 1000)), false);
    }
    function test_P1_RepeatedBatchBurn() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _measureBounded("P1_repeat_burn", address(sdgnrs), bob, 0,
            abi.encodeCall(sdgnrs.burn, (sdgnrs.totalSupply() / 1000)), false);
    }
    function test_P1_CloseBatch() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _measureBounded("P1_close", address(sdgnrs), address(game), 0,
            abi.encodeCall(sdgnrs.closeRedemptionBatch, (game.claimableWinningsOf(address(sdgnrs)))), false);
    }
    function test_P1_ResolveAndSettleBatch() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _closeAsGame(); _mockSettlingStage();
        _measureBounded("P1_settle", address(sdgnrs), address(game), 0,
            abi.encodeCall(sdgnrs.runRedemptionWork, (_wordForRoll(100), uint256(12_000_000))), false);
    }
    function test_P1_ReusedBatchBurn() public {
        for (uint256 i; i < 2; ++i) {
            _burn(alice, sdgnrs.totalSupply() / 1000);
            _resolveLive(100);
            vm.prank(address(game)); sdgnrs.runRedemptionWork(settlementWord, 12_000_000);
            assertFalse(sdgnrs.redemptionSettlementPending());
        }
        _measureBounded("P1_reused_burn", address(sdgnrs), alice, 0,
            abi.encodeCall(sdgnrs.burn, (sdgnrs.totalSupply() / 1000)), false);
    }
}
