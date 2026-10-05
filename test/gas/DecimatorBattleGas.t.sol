// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract DecimatorBattleGasTest is Test {
    DecimatorBattleHarness private h;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        h = new DecimatorBattleHarness();
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
    }

    function test_SealGasIndependentOfPopulation() public {
        h.open(5);
        h.forceCount(5, 1);
        uint256 gasBefore = gasleft();
        h.seal(5, 100 ether, 321);
        uint256 single = gasBefore - gasleft();
        // Fresh harness gives both rounds an empty queue.
        DecimatorBattleHarness big = new DecimatorBattleHarness();
        big.open(5);
        big.forceCount(5, type(uint40).max);
        gasBefore = gasleft();
        big.seal(5, 100 ether, 321);
        uint256 many = gasBefore - gasleft();
        assertLt(many, single + 10_000);
        assertEq(big.roundOf(5).capacity, 200);
        emit log_named_uint("seal, uint64 max entrants", many);
    }

    /// @dev Exercises the pinned settleSlip STATICCALL for every entry in each bounded batch.
    function test_RealEngineBatchesStayBelowKeeperEnvelope() public {
        uint256 peakGas;
        uint256 batches;
        for (uint24 round = 5; round <= 25; round += 10) {
            h.open(round);
            vm.startPrank(ContractAddresses.COIN);
            for (uint64 i = 1; i <= 2000; ++i) {
                h.recordDecBurn(address(uint160(i)), round, uint256(i) * 1000, 10_000, 0);
            }
            vm.stopPrank();
            h.seal(round, 100 ether, uint256(keccak256(abi.encode("decimator gas", round))));
            while (uint24(h.queue()) != 0) {
                vm.cool(address(h));
                vm.cool(ContractAddresses.CRAPS_ENGINE);
                uint256 gasBefore = gasleft();
                MineFlipGas.Result memory result = h.runDecimatorWork{gas: 15_000_000}(14_000_000);
                uint256 used = gasBefore - gasleft();
                assertGt(result.rewardBasis, 0);
                assertTrue(result.progressed);
                assertLe(used, 14_020_000, "native allowance including external call frame");
                assertLt(used, 15_000_000, "decimator worker fits supplied gas");
                if (used > peakGas) peakGas = used;
                ++batches;
            }
        }
        emit log_named_uint("real engine maximum batch gas (3 x 2000 entries)", peakGas);
        emit log_named_uint("total batches", batches);
    }
}
