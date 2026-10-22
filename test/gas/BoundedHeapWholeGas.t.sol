// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DecimatorSamplingLib as Sampling} from "../../contracts/libraries/DecimatorSamplingLib.sol";

contract BoundedHeapWholeGasTest is Test {
    DecimatorBattleHarness private host;
    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        host = new DecimatorBattleHarness();
        vm.etch(ContractAddresses.CRAPS_ENGINE, vm.getDeployedCode("CrapsEngine.sol:CrapsEngine"));
    }
    function measured() external returns (MineFlipGas.Result memory result, uint256 gross) {
        require(msg.sender == address(this), "measurement self-call");
        result = host.runDecimatorWork{gas: 15_000_000}(14_000_000);
        gross = vm.lastCallGas().gasTotalUsed;
    }
    function test_G5_ThreeCompleteRoundsWithRealEngine() public {
        uint256 total;
        uint256 batches;
        uint256 peak;
        uint256 sampled;
        uint256 paid;
        for (uint24 round = 5; round <= 25; round += 10) {
            host.open(round);
            vm.startPrank(ContractAddresses.COIN);
            for (uint64 i = 1; i <= 2000; ++i) host.recordFor(address(uint160(i)), round, uint256(i) * 1000, 10_000, 0);
            vm.stopPrank();
            uint256 word = uint256(keccak256(abi.encode("decimator gas", round)));
            host.seal(round, 100 ether, word);
            while (uint24(host.queue()) != 0) {
                (MineFlipGas.Result memory result, uint256 used) = this.measured();
                assertTrue(result.progressed);
                assertGt(result.rewardBasis, 0);
                assertLt(used, 15_000_000, "actual nested frame below transaction allowance");
                total += used;
                if (used > peak) peak = used;
                ++batches;
                assertLt(batches, 100, "bounded complete campaign");
                emit log_named_uint("batch_gross", used);
                emit log_named_uint("batch_reward_basis", result.rewardBasis);
                emit log_named_uint("batch_cursor", host.roundOf(round).cursor);
            }
            assertEq(host.roundOf(round).cursor, Sampling.field(word, round, 2000).count);
            assertEq(host.roundOf(round).winners, 200);
            assertEq(host.roundOf(round).paid, 200);
            sampled += host.roundOf(round).cursor;
            paid += host.roundOf(round).paid;
        }
        emit log_named_uint("whole_rounds_gross", total);
        emit log_named_uint("whole_rounds_batches", batches);
        emit log_named_uint("whole_rounds_peak", peak);
        emit log_named_uint("whole_rounds_sampled", sampled);
        emit log_named_uint("whole_rounds_paid", paid);
    }
}
