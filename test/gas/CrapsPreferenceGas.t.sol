// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DecimatorBattleHarness} from "../fuzz/helpers/DecimatorBattleHarness.sol";
import {CrapsPins} from "../craps/CrapsPins.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsLens} from "../../contracts/CrapsLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";

contract CrapsValidatorGasProbe is CrapsBattle {
    function measure(uint32 board) external view returns (uint256 count, uint256 used) {
        uint256 start = gasleft();
        (, count) = _packChips(board);
        used = start - gasleft();
    }
}

/// @dev Identical measurement source and legal boards run on the base and candidate.
contract CrapsPreferenceGasTest is CrapsPins {
    CrapsBattle private table;
    CrapsLens private lens;
    address private alice = address(0xA11CE);
    uint32 private id;

    function setUp() public {
        _installPins();
        table = CrapsBattle(ContractAddresses.CRAPS);
        lens = new CrapsLens();
        id = game.registerWallet_g9539(alice, true);
    }

    function test_GasValidators() public {
        CrapsValidatorGasProbe probe = new CrapsValidatorGasProbe();
        DecimatorBattleHarness decimator = new DecimatorBattleHarness();
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        decimator.open(5);
        vm.prank(ContractAddresses.COIN);
        decimator.recordFor(alice, 5, 1000, 10_000, 0);
        uint32[5] memory boards = [uint32(0), 3, (3 << 9) | (3 << 12) | (1 << 27), 4 << 27, (5 << 27) | (2 << 24)];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < boards.length; ++i) {
            assertTrue(vm.revertToState(snapshot));
            (uint256 count, uint256 used) = probe.measure(boards[i]);
            assertLe(count, 7);
            emit log_named_uint(string.concat("validator-pack-", vm.toString(i)), used);
            vm.cool(address(decimator));
            vm.prank(ContractAddresses.COIN);
            uint256 start = gasleft();
            decimator.recordFor(alice, 5, 1000, 10_000, boards[i]);
            used = start - gasleft();
            emit log_named_uint(string.concat("validator-decimator-entry-", vm.toString(i)), used);
        }
    }

    function test_GasSaveReadAndPrepare() public {
        uint32[5] memory boards = [uint32(0), 3, (3 << 9) | (3 << 12) | (1 << 27), 3 << 27, 5 << 27];
        uint256 cases = vm.envOr("P8C_NEW_BOARDS", false) ? 5 : 4;
        uint256 snapshot = vm.snapshotState();
        for (uint256 b; b < cases; ++b) {
            assertTrue(vm.revertToState(snapshot));
            bytes32 key = keccak256(abi.encode(id, CrapsPreferenceLib.PASS_SLOT));
            vm.cool(address(table));
            vm.cool(address(game));
            vm.coolSlot(address(table), key);
            vm.prank(alice);
            uint256 start = gasleft();
            table.setPreferredBoard(0, boards[b]);
            uint256 savedGas = start - gasleft();
            emit log_named_uint(string.concat("save-", vm.toString(b)), savedGas);
            vm.cool(address(table));
            vm.coolSlot(address(table), key);
            start = gasleft();
            uint32 read = lens.preferredBoardOf(id);
            uint256 used = start - gasleft();
            assertEq(read, boards[b]);
            emit log_named_uint(string.concat("read-", vm.toString(b)), used);
            uint32[] memory ids = new uint32[](50);
            for (uint32 i; i < 50; ++i) {
                ids[i] = (i + 1) << 8;
                bytes32 slot = keccak256(abi.encode(ids[i], CrapsPreferenceLib.PASS_SLOT));
                vm.store(
                    address(table),
                    slot,
                    bytes32(
                        CrapsPreferenceLib.INITIALIZED
                            | (CrapsPreferenceLib.compress(boards[b]) << CrapsPreferenceLib.SHIFT)
                    )
                );
                vm.coolSlot(address(table), slot);
            }
            vm.cool(address(table));
            start = gasleft();
            uint256[] memory field = JackpotBattleFieldLib.prepare(ids);
            used = start - gasleft();
            emit log_named_uint(string.concat("prepare50-", vm.toString(b)), used);
            assertEq(field.length, 50);
            (read,) = CrapsPreferenceLib.decode(field[49] >> 96);
            assertEq(read, boards[b]);
        }
    }

    function test_GasChangedShapesThroughSettlement() public {
        uint32[3] memory boards = [uint32(5 << 27), (4 << 27) | (3 << 9), (5 << 27) | (2 << 24)];
        // Normal, high, and maximum legal custom round (rounded to ten chips).
        uint256[3] memory chip = [uint256(60), 600, uint256(type(uint24).max) / 10];
        for (uint256 b; b < boards.length; ++b) {
            for (uint256 t; t < chip.length; ++t) {
                uint256 start = gasleft();
                Craps.SlipResult memory r = table.settleSlip(
                    boards[b],
                    chip[t],
                    123,
                    b == 0 ? 5 : 3,
                    keccak256("p8c-settlement"),
                    chip[t] * 250e18,
                    chip[t] * 1250e18,
                    1,
                    t == 2 ? 0 : 0x050c
                );
                uint256 used = start - gasleft();
                emit log_named_uint(string.concat("settle-", vm.toString(b), "-", vm.toString(t)), used);
                assertLe(r.totalRolls, 1111);
                assertLe(used, 3_000_000);
                emit log_named_bytes32("settlement-result", keccak256(abi.encode(r)));
            }
        }
    }
}
