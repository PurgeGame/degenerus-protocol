// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
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

/// @dev Measures one settlement call inside its own frame. Under FOUNDRY_ISOLATE each test call is
///      a transaction, which cools storage as a real keeper call finds it; measuring here keeps
///      that transaction's base cost, paid once per mineFlip, out of the leg's charge.
contract DecimatorPricingMeter {
    function settle(DecimatorBattleHarness h, uint256 budget) external returns (uint256 used, uint256 units) {
        uint256 before = gasleft();
        (, units,) = h.settleDecimatorWinners(budget);
        used = before - gasleft();
    }
}

/// @notice The Decimator's work units against measured gas: every settlement call, cold, must cost
///         at most 90% of the units it charges at 4,700 gas each. Real-engine fields cover every
///         named-chip count; probe fields force the heaviest heap shapes on fresh and reused slots.
contract DecimatorPricingTest is Test {
    uint256 private constant UNIT_GAS = 4700;
    DecimatorBattleHarness private h;
    DecimatorPricingMeter private meter;
    uint256 private maxRatioBps;
    uint256 private maxCallGas;
    uint24 private nextLevel = 5;
    uint256 private fieldPool = 100 ether;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
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

    function _settleAll(uint256 budget) private {
        for (uint256 guard; uint24(h.queue()) != 0 && guard < 20_000; ++guard) {
            vm.cool(address(h));
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            (uint256 used, uint256 units) = meter.settle(h, budget);
            assertLe(used * 10, units * UNIT_GAS * 9, "call exceeds 90% of its charge");
            uint256 ratio = used * 10_000 / (units * UNIT_GAS);
            if (ratio > maxRatioBps) maxRatioBps = ratio;
            if (used > maxCallGas) maxCallGas = used;
        }
        assertEq(uint24(h.queue()), 0, "settled");
    }

    function _report(string memory label) private {
        emit log_named_uint(string.concat(label, ": worst gas / charge (bps)"), maxRatioBps);
        emit log_named_uint(string.concat(label, ": heaviest call gas"), maxCallGas);
    }

    /// @dev Real dice on every board size: full-budget calls and one-item calls.
    function test_RealEngineCallsWithinCharge() public {
        for (uint256 salt = 1; salt <= 3; ++salt) {
            _field(700, salt, true, 0);
            _settleAll(1920);
        }
        _field(300, 9, true, 0);
        _settleAll(10); // one item per call: the call frame plus a single run, rank or credit
        _report("real engine");
        assertLt(maxCallGas, 10_000_000, "a full keeper leg stays under 10M");
    }

    /// @dev The hottest round of the 200,000-run simulation (round 259: nine of its 200 entries ran
    ///      600+ rolls unbounded), rebuilt exactly, so capped 511-roll runs settle through the module.
    function test_HotRoundCappedRunsWithinCharge() public {
        uint24 lvl = nextLevel; // level 5, the simulation's
        nextLevel += 10;
        h.open(lvl);
        vm.startPrank(ContractAddresses.COIN);
        for (uint64 id = 1; id <= 200; ++id) {
            h.recordDecBurn(address(uint160(id) + 0x1000), lvl, 1000 ether + uint256(id) * 1 ether, 10_000, _board(id));
        }
        vm.stopPrank();
        h.seal(lvl, 50 ether, uint256(keccak256(abi.encode("round200k", uint256(259)))));
        _settleAll(10);
        _report("hot round, one item a call");
        uint24 again = nextLevel;
        nextLevel += 10;
        h.open(again);
        vm.startPrank(ContractAddresses.COIN);
        for (uint64 id = 1; id <= 200; ++id) {
            h.recordDecBurn(address(uint160(id) + 0x1000), again, 1000 ether + uint256(id) * 1 ether, 10_000, _board(id));
        }
        vm.stopPrank();
        h.seal(again, 50 ether, uint256(keccak256(abi.encode("round200k", uint256(259)))));
        _settleAll(1920);
        _report("hot round, full calls");
    }

    /// @dev A pool big enough that every share buys half passes: payouts alternate ETH credits and
    ///      half-pass awards to fresh addresses, one item a call and in full calls.
    function test_WhalePassPayoutsWithinCharge() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorPricingFlatProbe).runtimeCode);
        fieldPool = 2000 ether;
        _field(1000, 300, false, 0);
        _settleAll(10);
        _field(1000, 301, false, 0);
        _settleAll(1920);
        _report("whale pass payouts");
    }

    /// @dev Heaviest heap shapes on fresh slots, then again on the reused slots of later rounds.
    function test_HeapShapesWithinChargeFreshAndReused() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorPricingFlatProbe).runtimeCode);
        for (uint8 pass; pass < 2; ++pass) {
            for (uint8 shape = 1; shape <= 3; ++shape) {
                _field(1000, 100 + pass * 10 + shape, false, shape);
                _settleAll(10);
                _field(1000, 200 + pass * 10 + shape, false, shape);
                _settleAll(1920);
            }
        }
        _report("heap shapes");
    }
}
