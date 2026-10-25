// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract BoundedRedemptionStageSeeder is DegenerusGameStorage {
    function seed() external {
        gameOver = false;
        rngLockedFlag = false;
        rngFlagsAndNudges &= ~(uint16(1) << 13);
        _clearRngRequest();
        _setRngComplete(false);
        _setRngSessionPublished(true);
        rngWordCurrent = 2;
        rngRequestTime = uint48(block.timestamp);
        ticketsFullyProcessed = true;
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
    }
}

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
            abi.encodeCall(sdgnrs.closeRedemptionBatch_g165517, (game.claimableWinningsOf(address(sdgnrs)))), false);
    }
    function test_P1_ResolveAndSettleBatch() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _closeAsGame();
        // Native replay must see the same real stage gate, not a Forge-only mock.
        bytes memory original = address(game).code;
        vm.etch(address(game), type(BoundedRedemptionStageSeeder).runtimeCode);
        BoundedRedemptionStageSeeder(address(game)).seed();
        vm.etch(address(game), original);
        assertEq(game.rngConsumerStage_g379(), 1);
        _measureBounded("P1_settle", address(sdgnrs), address(game), 0,
            abi.encodeCall(sdgnrs.runRedemptionWork, (_wordForRoll(100), uint256(12_000_000))), false);
    }
    function test_P1_ReusedBatchBurn() public {
        for (uint256 i; i < 2; ++i) {
            _burn(alice, sdgnrs.totalSupply() / 1000);
            _resolveLive(100);
            vm.prank(address(game)); sdgnrs.runRedemptionWork(settlementWord, 12_000_000);
            assertFalse(sdgnrs.redemptionSettlementPending_g153837());
        }
        _measureBounded("P1_reused_burn", address(sdgnrs), alice, 0,
            abi.encodeCall(sdgnrs.burn, (sdgnrs.totalSupply() / 1000)), false);
    }
}
