// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {CrapsPreferenceStore} from "../craps/CrapsPreferenceStore.sol";

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract JackpotBattleDedupGasTest is Test {
    function setUp() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsPreferenceStore()).code);
    }

    function _measure(uint8 shape, uint256 n, uint256 limit) private {
        address[] memory entrants = new address[](n);
        for (uint256 i; i < n; ++i) {
            entrants[i] = shape == 0 ? address(uint160(i + 1))
                : shape == 1 ? address(uint160((i + 1) << 8)) // distinct wallets on one low byte: the exact scan
                : shape == 2 ? address(uint160(1))
                : address(uint160((i % 10) << 8)); // collisions, repeats, and address(0)
        }
        uint256 beforeGas = gasleft();
        uint256[] memory field = JackpotBattleFieldLib.prepare(entrants);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("JACKPOT_FIELD_PREPARE_GAS", used);
        assertLt(used, limit, "bounded dedupe and one preference batch");
        assertEq(field.length, n, "one word per drawn entry");
        for (uint256 i; i < n; ++i) {
            assertEq(address(uint160(field[i])), entrants[i], "draw order");
            assertEq(field[i] >> JackpotBattleFieldLib.UNITS_SHIFT, 1, "one unit per entry");
        }
    }

    function test_FullChunkDistinctLanes() public { _measure(0, JackpotBattleFieldLib.MAX_CHUNK, 700_000); }
    function test_FullChunkSharedLowByte() public { _measure(1, JackpotBattleFieldLib.MAX_CHUNK, 3_000_000); }
    function test_FullChunkSameWallet() public { _measure(2, JackpotBattleFieldLib.MAX_CHUNK, 300_000); }
    function test_CollisionsAndRepeatedWallets() public { _measure(3, JackpotBattleFieldLib.MAX_CHUNK, 400_000); }
    function test_SingleEntrant() public { _measure(0, 1, 30_000); }
}
