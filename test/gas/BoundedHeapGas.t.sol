// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {DecimatorSamplingLib as Sampling} from "../../contracts/libraries/DecimatorSamplingLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract BoundedHeapRedemptionState {
    function redemptionSettlementPending_g153837() external pure returns (bool) { return false; }
}

contract BoundedHeapSeeder is DecimatorBattleHarness {
    /// @dev A valid ascending min-heap. Its entries were all recorded normally.
    ///      The pending final sampled entry is settled by the real Craps engine.
    function seedHeap(uint8 count, bool reject, bool rankOnly) external {
        DecBattleRound storage round = decBattleRounds[5];
        round.winners = count;
        uint256 n = Sampling.field(_currentRngWord(), round.count).count;
        round.cursor = uint64(rankOnly ? n : n - 1);
        for (uint256 i; i < count; ++i) {
            uint256 score = reject ? uint256(type(uint192).max) - 200 + i : i + 1;
            decBattleHeap[i] = (score << 64) | (i + 1);
        }
    }
}

contract BoundedHeapGasTest is BoundedGasProbe {
    BoundedHeapSeeder private host;
    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82621);
        vm.etch(ContractAddresses.SDGNRS, type(BoundedHeapRedemptionState).runtimeCode);
        host = new BoundedHeapSeeder();
        vm.etch(ContractAddresses.CRAPS_ENGINE, vm.getDeployedCode("CrapsEngine.sol:CrapsEngine"));
        host.open(5);
        vm.startPrank(ContractAddresses.COIN);
        for (uint64 i = 1; i <= 2000; ++i) host.recordFor(address(uint160(i)), 5, uint256(i) * 1000, 10000, 0);
        vm.stopPrank();
        host.seal(5, 100 ether, 0xCAFE);
        assertEq(host.roundOf(5).capacity, 200);
    }
    function _run(string memory label, uint8 count, bool reject, bool rankOnly) private {
        host.seedHeap(count, reject, rankOnly);
        (uint256 exec, uint256 state) = _measureBounded(label, address(host), address(this), 0,
            abi.encodeCall(host.runDecimatorWork, (uint256(14_000_000))), false);
        assertEq(host.queue(), 0, "same complete final-entry/rank/payout work in both replays");
        uint256 winners = host.roundOf(5).winners;
        emit log_named_uint("completed_winners", winners);
        // Each unit the call ran was admitted on its own bound; the one tail follows the last.
        uint256 admitted = (rankOnly ? 0 : GasBounds.DECIMATOR_RUN_GAS_MAX) + GasBounds.DECIMATOR_RANK_GAS_MAX
            + winners * GasBounds.DECIMATOR_PAYMENT_GAS_MAX + GasBounds.DECIMATOR_FINAL_GAS_MAX
            + GasBounds.DECIMATOR_WORK_TAIL_GAS;
        emit log_named_uint("composed_admission", admitted);
        assertLe(exec + state, admitted, "Glamsterdam total fits the composed admission of the units it ran");
    }
    function test_G5_FirstHeapWord() public { _run("G5_first", 0, false, false); }
    function test_G5_FinalHeapPosition() public { _run("G5_fill200", 199, false, false); }
    function test_G5_RootReplacement() public { _run("G5_replace200", 200, false, false); }
    function test_G5_WeakEntryRejected() public { _run("G5_reject200", 200, true, false); }
    function test_G5_RankAndPayout() public { _run("G5_rank_pay200", 200, false, true); }
}
