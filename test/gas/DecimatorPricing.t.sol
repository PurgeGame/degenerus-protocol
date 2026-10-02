// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

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
