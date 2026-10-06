// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {BudgetReadFixture} from "../repro/MineFlipWorkerBudget.t.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {Test} from "forge-std/Test.sol";

contract NativeAtomicReadFixture is BudgetReadFixture {
    function setCommittedWord(uint256 word) external { rngWordCurrent = word; }
    function fundFuture() external { _setFuturePrizePool(1_000_000 ether); }
}

/// @notice Whole bets remain indivisible even though a transaction can now process >10M gas.
contract NativeAtomicDegeneretteTest is DeployProtocol {
    NativeAtomicReadFixture private host;
    address private constant PLAYER = address(0xA7051C);

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 1_000_000 ether);
        vm.deal(PLAYER, 10_000 ether);
        vm.prank(address(game)); coin.mintForGame(PLAYER, 1_000_000 ether);
        vm.etch(address(game), type(NativeAtomicReadFixture).runtimeCode);
        host = NativeAtomicReadFixture(payable(address(game)));
        host.fundFuture();
    }

    function _winningWord(uint32 index, uint8 minimum, bool flip) private pure returns (uint256 word) {
        for (uint256 nonce;; ++nonce) {
            word = uint256(keccak256(abi.encode("native atomic bet", nonce)));
            (uint8 score,) = Ref.score(Ref.player(word, index, 9, 0, false), Ref.house(word, index, 0, false));
            if (score >= minimum && (!flip || uint256(keccak256(abi.encode(
                word, uint256(uint160(PLAYER)), uint256(1), uint256(0x446567656e537572766976616c)
            ))) & 1 == 1)) return word;
        }
    }

    function _measure(uint8 currency, uint128 stake, uint8 spins, uint8 minimum) private returns (uint256 used) {
        uint32 index = uint32(RecyclingState.writeBuffer(address(game)));
        uint256 word = _winningWord(index, minimum, currency == 1);
        vm.prank(PLAYER);
        game.placeDegeneretteBet{value: currency == 0 ? uint256(stake) * spins : 0}(PLAYER, currency, stake, spins, 9);
        host.publishRead();
        host.setCommittedWord(word);
        uint256 packed = host.bet();
        assertEq((packed >> 165) & 31, spins);
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(address(sdgnrs)); vm.cool(address(crapsBattle));
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE); vm.cool(ContractAddresses.GAME_BOON_MODULE);
        uint256 beforeGas = gasleft();
        MineFlipGas.Result memory result = host.workBet{gas: 15_000_000}(14_000_000);
        used = beforeGas - gasleft();
        assertTrue(result.done);
        assertEq(result.rewardBasis, 1);
        assertTrue(host.bet() >> 255 != 0, "whole bet completed atomically");
        assertLt(used, 10_000_000, "one immutable bet meets the chunk sizing guideline");
    }

    function test_Max25EthSpinsWithHighScoreAndWinBoxFitOneStep() public {
        uint256 used = _measure(0, 100 ether, 25, 7);
        assertGt(sdgnrs.balanceOf(PLAYER), 0, "high-score sDGNRS award executed");
        emit log_named_uint("cold_atomic_25_eth_spins_high_score_and_box", used);
    }

    function test_Max15FlipSpinsAndSurvivalMintFitOneStep() public {
        uint256 beforeBalance = coin.balanceOf(PLAYER);
        uint256 used = _measure(1, 100, 15, 5);
        assertGt(coin.balanceOf(PLAYER), beforeBalance - 1500 ether, "surviving FLIP winnings minted");
        emit log_named_uint("cold_atomic_15_flip_spins_survival", used);
    }
}

/// @notice A long real dice run, including its live heap insertion, remains one checkpoint step.
contract NativeAtomicDecimatorTest is Test {
    function _board(uint64 id) private pure returns (uint32 chips, uint256 named) {
        uint32[8] memory boards = [uint32(0), 1, 2, 3, uint32(3 | 1 << 9),
            uint32(3 << 27 | 2 << 9), uint32(3 | 3 << 9), uint32(3 | 3 << 9 | 1 << 24)];
        chips = boards[id % 8];
        for (uint256 i; i < 30; i += 3) named += (chips >> i) & 7;
    }

    function test_LongRealDiceRunWithHeapInsertionFitsOneStep() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
        DecimatorBattleHarness host = new DecimatorBattleHarness();
        uint256 word = uint256(keccak256(abi.encode("round200k", uint256(259))));
        bytes32 seed = keccak256(abi.encode(keccak256("decimator.battle.dice.v1"), word, uint24(5)));
        uint64 longest;
        uint64 longestStratum;
        uint256 rolls;
        for (uint64 i; i < 99; ++i) {
            uint64 id = Sample.at(word, 5, 200, i);
            (uint32 chips, uint256 named) = _board(id);
            Craps.SlipResult memory run = CrapsEngine(ContractAddresses.CRAPS_ENGINE).settleSlipBounded(
                chips, 60, uint256(keccak256(abi.encode(keccak256("decimator.battle.board.v1"), word, uint24(5), id))),
                10 - named, seed, 3000 ether, address(uint160(id) + 0x1000),
                (0x050c070c0a0c0e0c120c140c190c1e0c >> (named << 4)) & 0xFFFF, (511 << 16) | 48
            );
            if (run.totalRolls > rolls) { rolls = run.totalRolls; longest = id; longestStratum = i; }
        }
        assertGt(rolls, 300, "fixture exercises a long real dice run");
        // Leave another sampled stratum after the measured run so ranking cannot chain.
        host.open(5);
        for (uint64 id = 1; id <= 200; ++id) {
            (uint32 chips,) = _board(id);
            vm.prank(ContractAddresses.COIN);
            host.recordDecBurn(address(uint160(id) + 0x1000), 5, 2000 + uint256(id), 10_000, chips);
        }
        host.seal(5, 50 ether, word);
        uint256 runAllowance = GasBounds.DECIMATOR_RUN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000;
        while (host.roundOf(5).cursor < longestStratum) {
            host.runDecimatorWork{gas: 15_000_000}(runAllowance);
        }
        assertEq(host.roundOf(5).cursor, longestStratum);
        assertEq(Sample.at(word, 5, 200, longestStratum), longest);
        vm.cool(address(host)); vm.cool(ContractAddresses.CRAPS_ENGINE);
        uint256 beforeGas = gasleft();
        MineFlipGas.Result memory result = host.runDecimatorWork{gas: 15_000_000}(runAllowance);
        uint256 used = beforeGas - gasleft();
        uint64 cursor = host.roundOf(5).cursor;
        assertEq(cursor, longestStratum + 1, "the next sampled run is not admitted");
        assertEq(host.roundOf(5).phase, 1, "the measured call runs entries only");
        assertEq(result.rewardBasis, 1);
        assertLt(used, 10_000_000, "one real dice run meets the chunk sizing guideline");
        emit log_named_uint("atomic_decimator_long_run_rolls", rolls);
        emit log_named_uint("cold_atomic_decimator_run_and_heap", used);
    }
}
