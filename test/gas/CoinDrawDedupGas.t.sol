// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {CoinDrawBattle} from "../../contracts/CoinDrawBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CoinDrawDedupGasTest is Test {
    CoinDrawBattle private battle;

    function setUp() public { battle = new CoinDrawBattle(); }

    function _measure(uint8 shape, uint256 n) private {
        address[] memory entrants = new address[](n);
        for (uint256 i; i < n; ++i) {
            entrants[i] = shape == 0 ? address(uint160(i + 1))
                : shape == 1 ? address(uint160((i + 1) << 8))
                : shape == 2 ? address(uint160(1))
                : address(uint160((i % 10) << 8)); // collisions, repeats, and address(0)
        }
        vm.prank(ContractAddresses.GAME);
        uint256 beforeGas = gasleft();
        (address[] memory players, uint256[] memory owed) = battle.resolve(7, entrants, 150_000 ether, 12345);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("COIN_DRAW_DEDUP_CALL_GAS", used);
        assertLt(used, 7_310_000);
        if (shape == 0 && n == 50) assertLt(used, 2_200_000, "distinct field lost its scan savings");
        if (shape == 1) assertLt(used, 2_400_000, "collisions must retain the original scan bound");
        if (shape == 2) assertLt(used, 70_000, "repeats must stay cheap");
        uint256 unique = shape == 2 ? 1 : shape == 3 ? 10 : n;
        assertEq(players.length, unique);
        assertEq(owed.length, unique);
        for (uint256 i; i < unique; ++i) assertEq(players[i], entrants[i], "first draw order");
    }

    function test_FiftyDistinctLanes() public { _measure(0, 50); }
    function test_FiftyCollidingLanes() public { _measure(1, 50); }
    function test_FiftySameWallet() public { _measure(2, 50); }
    function test_CollisionsAndRepeatedWallets() public { _measure(3, 50); }
    function test_SingleEntrant() public { _measure(0, 1); }
}
