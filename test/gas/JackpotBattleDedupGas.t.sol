// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {CrapsPreferenceStore} from "../craps/CrapsPreferenceStore.sol";

import {Test} from "forge-std/Test.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract JackpotBattleDedupGasTest is Test {
    JackpotBattle private battle;

    function setUp() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsPreferenceStore()).code); battle = new JackpotBattle(); }

    function _measure(uint8 shape, uint256 n) private {
        address[] memory entrants = new address[](n);
        for (uint256 i; i < n; ++i) {
            entrants[i] = shape == 0 ? address(uint160(i + 1))
                : shape == 1 ? address(uint160((i + 1) << 8))
                : shape == 2 ? address(uint160(1))
                : address(uint160((i % 10) << 8)); // collisions, repeats, and address(0)
        }
        uint256 beforeGas = gasleft();
        uint256[] memory field = JackpotBattleFieldLib.prepare(entrants, 150_000 ether);
        vm.prank(ContractAddresses.GAME);
        (address[] memory players, uint256[] memory owed,,,) = battle.resolve(7, field, 150_000 ether, 12345);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("JACKPOT_BATTLE_DEDUP_CALL_GAS", used);
        assertLt(used, 7_475_000);
        if (shape == 0 && n == 50) assertLt(used, 2_200_000, "distinct field lost its scan savings");
        if (shape == 1) assertLt(used, 2_400_000, "collisions must retain the original scan bound");
        // Original 90k allowance plus 2k for the draw-wide multiplier event and arithmetic.
        if (shape == 2) assertLt(used, 92_000, "repeats include only one preference lookup and one multiplier event");
        uint256 unique = shape == 2 ? 1 : shape == 3 ? 10 : n;
        assertEq(players.length, unique);
        assertEq(owed.length, unique);
        for (uint256 i; i < unique; ++i) assertEq(players[i], entrants[i], "first draw order");
    }

    function test_FiftyDistinctLanes() public { _measure(0, 50); }
    function test_FiftyCollidingLanes() public { _measure(1, 50); }
    function test_FiftySameWallet() public { _measure(2, 50); }
    function test_CollisionsAndRepeatedWallets() public { _measure(3, 50); }
    function test_TenEntrants() public { _measure(0, 10); }
    function test_TwentyFiveEntrants() public { _measure(0, 25); }
    function test_SingleEntrant() public { _measure(0, 1); }
}
