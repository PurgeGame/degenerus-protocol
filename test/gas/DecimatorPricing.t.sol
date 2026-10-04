// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @dev A cold external frame around one engine run, as the module's run calls it.
contract DecimatorEngineMeter {
    function run(uint256 chips, bytes32 seed, uint256 bankroll, uint256 boost)
        external view returns (uint256 used, uint256 rolls)
    {
        uint256 beforeGas = gasleft();
        Craps.SlipResult memory r = CrapsEngine(ContractAddresses.CRAPS_ENGINE).settleSlipBounded(
            chips, 60, uint256(keccak256(abi.encode("board", seed))), 3, seed, bankroll, address(0xD1CE), boost,
            (511 << 16) | 48
        );
        used = beforeGas - gasleft();
        rolls = r.totalRolls;
    }
}

/// @dev Every run peaks at its starting bankroll after thirty rolls, so ranking follows the
///      stacks alone and the heap shape is chosen by the test.
contract DecimatorPricingFlatProbe {
    function settleSlipBounded(uint256, uint256, uint256, uint256, bytes32, uint256 bankroll, address, uint256, uint256)
        external
        pure
        returns (Craps.SlipResult memory r)
    {
        r.peakBankroll = bankroll;
        r.totalRolls = 30;
    }
}

/// @dev Native calls measured within an external frame; vm.cool and isolate exclude setup warmth.
contract DecimatorPricingMeter {
    function settle(DecimatorBattleHarness h, uint256 allowance)
        external returns (uint256 used, MineFlipGas.Result memory result)
    {
        uint256 beforeGas = gasleft();
        result = h.runDecimatorWork(allowance);
        used = beforeGas - gasleft();
    }
}

/// @notice Native Decimator worker progression under small and large gas allocations.
///         Real dice and forced heap/payout shapes preserve all semantic work boundaries.
contract DecimatorPricingTest is Test {
    DecimatorBattleHarness private h;
    DecimatorPricingMeter private meter;
    uint256 private maxRunGas;
    uint256 private maxRankGas;
    uint256 private maxPayGas;
    uint256 private maxCallGas;
    uint24 private nextLevel = 5;
    uint256 private fieldPool = 100 ether;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        h = new DecimatorBattleHarness();
        meter = new DecimatorPricingMeter();
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
    }

    /// @dev Valid boards naming 0..7 chips under the normal battle rules.
    function _board(uint256 i) private pure returns (uint32) {
        // Legs: pass line at bit 0, place 6 at 9, hard 8 at 24, don't pass at 27.
        uint32[8] memory boards = [
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(3),
            uint32(3 | 1 << 9),
            uint32(3 << 27 | 2 << 9),
            uint32(3 | 3 << 9),
            uint32(3 | 3 << 9 | 1 << 24)
        ];
        return boards[i % 8];
    }

    function _field(uint256 n, uint256 salt, bool boards, uint8 shape) private returns (uint24 lvl) {
        lvl = nextLevel;
        nextLevel += 10;
        h.open(lvl);
        vm.startPrank(ContractAddresses.COIN);
        for (uint256 i = 1; i <= n; ++i) {
            uint256 amount;
            if (shape == 1) amount = (n + 1 - i) * 1000 ether; // each heads entry is the new minimum
            else if (shape == 2) amount = i * 1000 ether; // each heads entry is the new maximum
            else if (shape == 3) amount = 1000 ether; // every score ties
            else amount = 1000 ether + uint256(keccak256(abi.encode(salt, i))) % (1_000_000 ether);
            h.recordDecBurn(address(uint160(salt * 1_000_000 + i)), lvl, amount, 10_000, boards ? _board(i) : 0);
        }
        vm.stopPrank();
        h.seal(lvl, uint128(fieldPool + salt), uint256(keccak256(abi.encode("pricing", salt))));
    }

    function _settleAll(uint256 allowance) private {
        for (uint256 guard; uint24(h.queue()) != 0 && guard < 20_000; ++guard) {
            uint24 lvl = uint24(h.queue());
            uint8 phase = h.roundOf(lvl).phase;
            bool ranking = phase == 1 && h.roundOf(lvl).cursor == h.roundOf(lvl).count;
            vm.cool(address(h));
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            (uint256 used, MineFlipGas.Result memory result) = meter.settle{gas: 15_000_000}(h, allowance);
            assertTrue(result.progressed, "admitted native action progresses");
            assertLe(used, allowance + 20_000, "native allowance plus measured call frame");
            if (ranking) {
                if (used > maxRankGas) maxRankGas = used;
            } else if (phase == 2) {
                if (used > maxPayGas) maxPayGas = used;
            } else if (used > maxRunGas) maxRunGas = used;
            if (used > maxCallGas) maxCallGas = used;
        }
        assertEq(uint24(h.queue()), 0, "settled");
    }

    uint256 private maxOneRun;
    uint256 private maxOnePay;

    /// @dev Settle with allowances that admit exactly one heads run or one payment per call, so
    ///      each measured call is a single indivisible item plus the worker's fixed frame.
    function _settleOneByOne() private {
        // The worker's frame before its first admission check, but less than one more item.
        uint256 runAllowance = GasBounds.DECIMATOR_RUN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 40_000;
        uint256 payAllowance = GasBounds.DECIMATOR_PAYMENT_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 30_000;
        for (uint256 guard; uint24(h.queue()) != 0 && guard < 20_000; ++guard) {
            uint24 lvl = uint24(h.queue());
            uint8 phase = h.roundOf(lvl).phase;
            bool ranking = phase == 1 && h.roundOf(lvl).cursor == h.roundOf(lvl).count;
            uint256 allowance = ranking ? 14_000_000 : phase == 2 ? payAllowance : runAllowance;
            vm.cool(address(h));
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            (uint256 used, MineFlipGas.Result memory result) = meter.settle{gas: 15_000_000}(h, allowance);
            assertTrue(result.progressed, "one-item allowance admits its item");
            if (ranking) {
                if (used > maxRankGas) maxRankGas = used;
            } else if (phase == 2) {
                if (used > maxOnePay) maxOnePay = used;
            } else if (used > maxOneRun) maxOneRun = used;
        }
        assertEq(uint24(h.queue()), 0, "settled");
    }

    /// @dev Per-item cold maxima against their declared bounds: one heads run (heaviest heap
    ///      shapes, flat engine), the 511-roll engine ceiling on the heaviest board, one ranking,
    ///      and one payment (whale-pass and ETH shapes, fresh recipients).
    function test_SingleItemColdMaximaAgainstDeclaredBounds() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorPricingFlatProbe).runtimeCode);
        for (uint8 shape = 1; shape <= 3; ++shape) {
            _field(1000, 400 + shape, false, shape);
            _settleOneByOne();
        }
        uint256 flatRun = maxOneRun;
        fieldPool = 2000 ether;
        _field(1000, 410, false, 0);
        _settleOneByOne();
        fieldPool = 100 ether;
        _field(1000, 411, false, 0);
        _settleOneByOne();

        // The engine's ceiling: 511 rolls before 48 shooters, the heaviest named board, a
        // bankroll no run can bust. Seeds are searched for runs that reach the roll bound.
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
        DecimatorEngineMeter em = new DecimatorEngineMeter();
        uint256 chips = 3 | 3 << 9 | 1 << 24; // seven named chips
        uint256 boost = (0x050c070c0a0c0e0c120c140c190c1e0c >> (7 << 4)) & 0xFFFF;
        uint256 ceilingRuns;
        uint256 engineMax;
        for (uint256 i; i < 400 && ceilingRuns < 4; ++i) {
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            (uint256 used, uint256 rolls) = em.run(chips, keccak256(abi.encode("ceiling", i)), 1e45, boost);
            if (rolls == 511) {
                ++ceilingRuns;
                if (used > engineMax) engineMax = used;
            }
        }
        assertGt(ceilingRuns, 0, "a run reached the 511-roll ceiling");
        uint256 runWorst = flatRun + engineMax;
        emit log_named_uint("DEC one heads run, flat engine, worst heap (cold)", flatRun);
        emit log_named_uint("DEC engine 511-roll ceiling run (cold)", engineMax);
        emit log_named_uint("DEC run worst = flat run + engine ceiling", runWorst);
        emit log_named_uint("DEC RANK cold max", maxRankGas);
        emit log_named_uint("DEC one payment cold max", maxOnePay);
        assertLe(runWorst, GasBounds.DECIMATOR_RUN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS, "run fits its bound");
        assertLe(maxRankGas, GasBounds.DECIMATOR_RANK_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS, "rank fits its bound");
        assertLe(maxOnePay, GasBounds.DECIMATOR_PAYMENT_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS, "payment fits its bound");
        assertLe(GasBounds.DECIMATOR_RUN_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS + 2_000, 10_000_000);
    }

    function _report(string memory label) private {
        emit log_named_uint(string.concat(label, ": cold RUN batch max"), maxRunGas);
        emit log_named_uint(string.concat(label, ": cold RANK max"), maxRankGas);
        emit log_named_uint(string.concat(label, ": cold PAY batch max"), maxPayGas);
        emit log_named_uint(string.concat(label, ": heaviest native call"), maxCallGas);
    }

    /// @dev Real dice on every board size: full-budget calls and small-allowance calls.
    function test_RealEngineCallsWithAvailableGas() public {
        for (uint256 salt = 1; salt <= 3; ++salt) {
            _field(700, salt, true, 0);
            _settleAll(14_000_000);
        }
        _field(300, 9, true, 0);
        _settleAll(1_000_000); // small allowance still reserves the largest indivisible run
        _report("real engine");
        assertLt(maxCallGas, 15_000_000, "worker fits its supplied execution gas");
    }

    /// @dev A hot round of the 200,000-run simulation (round 259: two of its 200 entries ran past
    ///      400 rolls, 24 past 300), rebuilt exactly, so its longest runs settle through the
    ///      module.
    function test_HotRoundCappedRunsWithAvailableGas() public {
        uint24 lvl = nextLevel; // level 5, the simulation's
        nextLevel += 10;
        h.open(lvl);
        vm.startPrank(ContractAddresses.COIN);
        for (uint64 id = 1; id <= 200; ++id) {
            h.recordDecBurn(address(uint160(id) + 0x1000), lvl, 1000 ether + uint256(id) * 1 ether, 10_000, _board(id));
        }
        vm.stopPrank();
        h.seal(lvl, 50 ether, uint256(keccak256(abi.encode("round200k", uint256(259)))));
        _settleAll(1_000_000);
        _report("hot round, small allowance");
        uint24 again = nextLevel;
        nextLevel += 10;
        h.open(again);
        vm.startPrank(ContractAddresses.COIN);
        for (uint64 id = 1; id <= 200; ++id) {
            h.recordDecBurn(address(uint160(id) + 0x1000), again, 1000 ether + uint256(id) * 1 ether, 10_000, _board(id));
        }
        vm.stopPrank();
        h.seal(again, 50 ether, uint256(keccak256(abi.encode("round200k", uint256(259)))));
        _settleAll(14_000_000);
        _report("hot round, full calls");
    }

    /// @dev A pool big enough that every share buys half passes: payouts alternate ETH credits and
    ///      half-pass awards to fresh addresses, small allowance and in full calls.
    function test_WhalePassPayoutsWithAvailableGas() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorPricingFlatProbe).runtimeCode);
        fieldPool = 2000 ether;
        _field(1000, 300, false, 0);
        _settleAll(1_000_000);
        _field(1000, 301, false, 0);
        _settleAll(14_000_000);
        _report("whale pass payouts");
    }

    /// @dev Heaviest heap shapes on fresh slots, then again on the reused slots of later rounds.
    function test_HeapShapesWithAvailableGasFreshAndReused() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorPricingFlatProbe).runtimeCode);
        for (uint8 pass; pass < 2; ++pass) {
            for (uint8 shape = 1; shape <= 3; ++shape) {
                _field(1000, 100 + pass * 10 + shape, false, shape);
                _settleAll(1_000_000);
                _field(1000, 200 + pass * 10 + shape, false, shape);
                _settleAll(14_000_000);
            }
        }
        _report("heap shapes");
    }
}
