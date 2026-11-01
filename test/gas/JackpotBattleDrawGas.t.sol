// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {Test} from "forge-std/Test.sol";
import {JackpotBattleDrawHarness} from "../fuzz/JackpotBattleDraw.t.sol";

/// @dev Use FOUNDRY_ISOLATE=true: every measured external call must start with cold storage,
///      including after fixture writes and the other selector's call.
contract JackpotBattleDrawGasTest is Test {
    JackpotBattleDrawHarness private h;
    /// @dev Cold gas of one field-draw chunk (up to MAX_CHUNK seats).
    uint256 private constant CHUNK_BOUND = 1_000_000;

    function setUp() public { h = new JackpotBattleDrawHarness(); }

    function _seed(uint256 levelCount, uint256 ownersPerLevel) private {
        for (uint24 lv = 41; lv < 41 + levelCount; ++lv) {
            address[] memory owners = new address[](ownersPerLevel);
            for (uint256 i; i < owners.length; ++i) owners[i] = address(uint160(uint256(lv) * 10_000 + i));
            h.seed(lv, owners, false);
        }
    }

    function _measure(uint256 target) private {
        (, uint256 cursor,) = h.collect(40, 123456789, 0, target);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("first chunk", used);
        assertLt(used, CHUNK_BOUND, "a draw chunk stays within its allowance");
        if (target > JackpotBattleFieldLib.MAX_CHUNK) {
            h.collect(40, 123456789, cursor, target - JackpotBattleFieldLib.MAX_CHUNK);
            used = vm.lastCallGas().gasTotalUsed;
            emit log_named_uint("resumed chunk", used);
            assertLt(used, CHUNK_BOUND, "a resumed draw chunk stays within its allowance");
        }
    }

    function test_NinetyNineLargeLevels() public { _seed(99, 256); _measure(500); }
    function test_OneLargeLevel() public { _seed(1, 1024); _measure(500); }
    function test_EarlyFloorFifteenSeats() public { _seed(99, 16); _measure(15); }
    function test_SingletonLevelsRemainBounded() public { _seed(99, 1); _measure(500); }
}
