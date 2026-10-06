// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {Test} from "forge-std/Test.sol";
import {JackpotBattleDrawHarness} from "../fuzz/JackpotBattleDraw.t.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract JackpotBattleDrawGasHarness is JackpotBattleDrawHarness {
    /// @dev Pre-walk implementation, retained only as the gas baseline for the same seeded field.
    function independent(uint24 lvl, uint256 word, uint256 cursor, uint256 remaining)
        external view returns (address[] memory winners, uint256 next, bool exhausted)
    {
        uint256 eligible = cursor >> 32;
        uint24[99] memory levels;
        uint256 count;
        for (uint256 offset; offset < 99; ++offset) {
            uint24 candidate = lvl + 1 + uint24(offset);
            bool live = cursor == 0 ? _ticketQueueLength(_tqFarFutureKey(candidate)) != 0
                : eligible & (uint256(1) << offset) != 0;
            if (live) {
                eligible |= uint256(1) << offset;
                levels[count++] = candidate;
            }
        }
        uint256 wanted = remaining < JackpotBattleFieldLib.MAX_CHUNK ? remaining : JackpotBattleFieldLib.MAX_CHUNK;
        if (count == 0) return (new address[](0), 0, true);
        winners = new address[](wanted);
        uint256 ordinal = uint32(cursor);
        for (uint256 i; i < wanted; ++i) {
            uint256 entropy = EntropyLib.hash2(word, ordinal + i);
            uint24 candidate = levels[entropy % count];
            uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(candidate))];
            uint256 len = queue.length;
            if (len == 0) continue;
            uint256 idx = (entropy >> 128) % len;
            uint256 packed = _tqWordAt(queue, idx);
            winners[i] = address(uint160(_entryRecordOf(candidate, uint32(packed >> ((idx & 7) << 5)))));
        }
        next = (eligible << 32) | (ordinal + wanted);
    }
}

/// @dev Use FOUNDRY_ISOLATE=true: every measured external call must start with cold storage,
///      including after fixture writes and the other selector's call.
contract JackpotBattleDrawGasTest is Test {
    JackpotBattleDrawGasHarness private h;

    function setUp() public { h = new JackpotBattleDrawGasHarness(); }

    function _seed(uint256 levelCount, uint256 ownersPerLevel) private {
        for (uint24 lv = 41; lv < 41 + levelCount; ++lv) {
            address[] memory owners = new address[](ownersPerLevel);
            for (uint256 i; i < owners.length; ++i) owners[i] = address(uint160(uint256(lv) * 10_000 + i));
            h.seed(lv, owners, false);
        }
    }

    function _measure(uint256 target, bool expectSavings) private {
        (, uint256 oldCursor,) = h.independent(40, 123456789, 0, target);
        uint256 oldGas = vm.lastCallGas().gasTotalUsed;
        (, uint256 cursor,) = h.collect(40, 123456789, 0, target);
        uint256 newGas = vm.lastCallGas().gasTotalUsed;
        emit log_named_uint("independent first chunk", oldGas);
        emit log_named_uint("sequential first chunk", newGas);
        if (expectSavings) assertLt(newGas, oldGas);
        else assertLt(newGas, 1_000_000, "singleton selection must stay within its draw allowance");
        if (target > JackpotBattleFieldLib.MAX_CHUNK) {
            h.independent(40, 123456789, oldCursor, target - JackpotBattleFieldLib.MAX_CHUNK);
            oldGas = vm.lastCallGas().gasTotalUsed;
            h.collect(40, 123456789, cursor, target - JackpotBattleFieldLib.MAX_CHUNK);
            newGas = vm.lastCallGas().gasTotalUsed;
            emit log_named_uint("independent resumed chunk", oldGas);
            emit log_named_uint("sequential resumed chunk", newGas);
            if (expectSavings) assertLt(newGas, oldGas);
            else assertLt(newGas, 1_000_000, "singleton continuation must stay bounded");
        }
    }

    function test_NinetyNineLargeLevels() public { _seed(99, 256); _measure(500, true); }
    function test_OneLargeLevel() public { _seed(1, 1024); _measure(500, true); }
    function test_EarlyFloorFifteenSeats() public { _seed(99, 16); _measure(15, true); }
    function test_SingletonLevelsRemainBounded() public { _seed(99, 1); _measure(500, false); }
}
