// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {DecimatorSamplingLib as Sampling} from "../../contracts/libraries/DecimatorSamplingLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";

contract BoundedHeapSeeder is DecimatorBattleHarness {
    /// @dev A valid ascending min-heap. Its entries were all recorded normally.
    ///      The pending final sampled entry is settled by the real Craps engine.
    function seedHeap(uint8 count, bool reject, bool rankOnly) external {
        DecBattleRound storage round = decBattleRounds[5];
        round.winners = count;
        uint256 n = Sampling.field(_currentRngWord(), 5, round.count).count;
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
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
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
        _measureBounded(label, address(host), address(this), 0,
            abi.encodeCall(host.runDecimatorWork, (uint256(14_000_000))), false);
        assertEq(host.queue(), 0, "same complete final-entry/rank/payout work in both replays");
        emit log_named_uint("completed_winners", host.roundOf(5).winners);
    }
    function test_G5_FirstHeapWord() public { _run("G5_first", 0, false, false); }
    function test_G5_FinalHeapPosition() public { _run("G5_fill200", 199, false, false); }
    function test_G5_RootReplacement() public { _run("G5_replace200", 200, false, false); }
    function test_G5_WeakEntryRejected() public { _run("G5_reject200", 200, true, false); }
    function test_G5_RankAndPayout() public { _run("G5_rank_pay200", 200, false, true); }
}
