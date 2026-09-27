// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PurchaseDailyFixture, FreshWordLeg, PurchaseDailySeeder} from "./PurchaseDailyWorstCase.t.sol";

/// @dev Prepare a legal pre-request queue whose fifty drawn wallets all share a low byte.
contract PreferredFieldSeeder is DegenerusGameStorage {
    function alignField(uint24 lvl, uint256 rngWord) external {
        uint256 entropy = uint256(keccak256(abi.encode(rngWord, lvl, keccak256("far-future-coin"))));
        uint256 visited;
        uint256 found;
        for (uint256 pick; pick < 16 && found < 50; ++pick) {
            entropy = EntropyLib.hash2(entropy, pick);
            uint256 offset = entropy % 99;
            if ((visited >> offset) & 1 != 0) continue;
            visited |= 1 << offset;
            uint24 candidate = lvl + 1 + uint24(offset);
            uint24 key = _tqFarFutureKey(candidate);
            uint256[] storage queue = ticketQueue[key];
            uint256 len = queue.length;
            if (len == 0) continue;
            uint256 take = 50 - found;
            if (take > len) take = len;
            uint256 idx = (entropy >> 128) % len;
            for (uint256 k; k < take; ++k) {
                uint32 pos = uint32(_tqWordAt(queue, idx) >> ((idx & 7) << 5));
                address old = lvlEntryOwner[candidate][pos - 1].owner;
                address p = address(uint160((found + 1) << 8));
                lvlEntryOwner[candidate][pos - 1].owner = p;
                delete entryOwnerPosition[key][old];
                entryOwnerPosition[key][p] = pos;
                ++found;
                if (++idx == len) idx = 0;
            }
        }
        require(found == 50, "field size");
    }
}

/// @dev A real bytecode/real VRF-word witness; every preference is legal and exists before the draw.
///      This establishes a reachable cost, not an exhaustive maximum over all 256-bit words.
contract PreferredBoardAdvanceStress is PurchaseDailyFixture, FreshWordLeg {
    function setUp() public {
        PurchaseDailySeeder.Shape memory s = _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, uint128(PREV_POOL_OPEN25 + 1 ether), PREV_POOL_OPEN25);
        s.word = 493;
        _seedFresh(s);
        uint32 board = 18879049; // one each: pass, place 4/5/6/8, hard 4/8 (seven named chips)
        uint256 compact;
        for (uint256 i; i < 10; ++i) compact |= uint256((board >> (i * 3)) & 7) << (i * 2);
        for (uint256 offset; offset < 99; ++offset) {
            for (uint256 i; i < FF_HOLDERS; ++i) {
                address p = address(BASE + 0x2000000 + uint160(offset) * 0x1000 + uint160(i + 1));
                vm.store(address(crapsBattle), keccak256(abi.encode(p, uint256(15))), bytes32(compact << 64 | 1 << 84));
            }
        }
        bytes memory gameCode = address(game).code;
        vm.etch(address(game), type(PreferredFieldSeeder).runtimeCode);
        PreferredFieldSeeder(address(game)).alignField(110, s.word);
        vm.etch(address(game), gameCode);
        for (uint256 i; i < 50; ++i) {
            address p = address(uint160((i + 1) << 8));
            vm.store(address(crapsBattle), keccak256(abi.encode(p, uint256(15))), bytes32(compact << 64 | 1 << 84));
        }
        _armFreshWord(s.word, 400);
    }
    function test_ReachableExpensiveSavedBoardAdvance() public {
        (uint256 dailyGas, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertEq(daily.battleRuns, 0, "battle must not ride the RNG/ETH stage");
        emit log_named_uint("SAVED_BOARD_DAILY_STAGE_GAS", dailyGas);
        (uint256 used, Tally memory t) = _measure();
        _emitTally("REACHABLE_SAVED_BOARD_ADVANCE", used, t);
        assertEq(t.stage, STAGE_PURCHASE_BATTLE);
        assertEq(t.ethWins + t.ticketWins, 0);
        assertEq(t.battleDistinct, 50);
        emit log_named_uint("REACHABLE_ADVANCE_GAS", used);
        _assertBattleCaps(used);
    }
}
