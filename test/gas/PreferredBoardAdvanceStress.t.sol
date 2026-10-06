// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {PurchaseDailyFixture, FreshWordLeg, PurchaseDailySeeder} from "./PurchaseDailyWorstCase.t.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Distinct wallets that all share low byte zero.
function fieldWallet(uint256 offset, uint256 i) pure returns (address) {
    return address(uint160((0x3000000 + offset * 256 + i) << 8));
}

/// @dev Seeds every unminted queue the award draw reads with low-byte-sharing wallets, so each draw
///      chunk's field preparation takes its exact duplicate scan.
contract PreferredFieldSeeder is DegenerusGame, WalletSeed {
    function seedLowByteField(uint24 purchaseLevel, uint256 holders) external {
        for (uint24 c = purchaseLevel + 1; c <= purchaseLevel + 99; ++c) {
            for (uint256 i; i < holders; ++i) {
                address p = fieldWallet(c - purchaseLevel - 1, i);
                _tqAppend(_tqFarFutureKey(c), _seedWallet(p));
            }
        }
    }
}

/// @dev A real bytecode/real VRF-word witness at the 500-award cap: every drawn wallet shares one low
///      byte and saved a legal seven-chip board before the request. Each battle step and the daily
///      after it is measured alone. This establishes a reachable cost, not an exhaustive maximum over
///      all 256-bit words.
contract PreferredBoardAdvanceStress is PurchaseDailyFixture, FreshWordLeg {
    uint32 internal constant BOARD = 18879049; // one each: pass, place 4/5/6/8, hard 4/8 (seven named chips)
    uint256 internal constant FIELD_HOLDERS = 20;
    /// @dev 40,000 ETH at 0.04 ETH is 5,000,000 FLIP of Added: the 500-award cap.
    uint256 internal constant PREV_POOL_AWARD_CAP = 40_000 ether;

    function setUp() public {
        PurchaseDailySeeder.Shape memory s =
            _shape(MAIN_HOLDERS, BONUS_HOLDERS, 0, NEXT_POOL_QUIET, PREV_POOL_AWARD_CAP);
        _seedFresh(s);
        bytes memory gameCode = address(game).code;
        vm.etch(address(game), type(PreferredFieldSeeder).runtimeCode);
        PreferredFieldSeeder(payable(address(game))).seedLowByteField(LVL + 1, FIELD_HOLDERS);
        vm.etch(address(game), gameCode);
        for (uint256 offset; offset < 99; ++offset) {
            for (uint256 i; i < FIELD_HOLDERS; ++i) {
                vm.prank(fieldWallet(offset, i));
                crapsBattle.setPreferredBoard(BOARD);
            }
        }
        _armFreshWord(s.word, 400);
    }

    function test_ReachableExpensiveSavedBoardAdvance() public {
        _applyWord(false, EIP7825_TX_GAS_CAP);
        IJackpotBattle battle = IJackpotBattle(address(crapsBattle));
        uint256 steps;
        uint256 entries;
        uint256 largest;
        (,,, bool complete) = battle.jackpotProgress();
        while (!complete) {
            assertLt(steps++, 40, "the battle stalled");
            (uint256 used, Tally memory t) = _measure();
            assertEq(t.stage, STAGE_PURCHASE_BATTLE, "a battle step has its own stage");
            assertEq(t.ethWins + t.ticketWins, 0, "a battle step shares no daily leg");
            assertLe(used, BATTLE_TX_LIMIT, "a saved-board battle tx crossed 10M");
            entries += _savedBoardEntries();
            if (used > largest) largest = used;
            (,,, complete) = battle.jackpotProgress();
        }
        emit log_named_uint("SAVED_BOARD_BATTLE_STEPS", steps);
        emit log_named_uint("REACHABLE_SAVED_BOARD_BATTLE_TX_GAS", largest);
        assertEq(entries, 500, "the award cap drew in full");

        (uint256 dailyGas, Tally memory daily) = _measure();
        emit log_named_uint("SAVED_BOARD_DAILY_STAGE_GAS", dailyGas);
        assertEq(daily.stage, STAGE_PURCHASE_DAILY, "the daily follows the battle");
        assertEq(daily.battleEntries, 0, "the battle never rides the daily stage");
    }

    /// @dev Awarded entries in the last measured tx; each must carry its wallet's saved board.
    function _savedBoardEntries() private view returns (uint256 n) {
        for (uint256 i; i < lastLogs.length; ++i) {
            if (lastLogs[i].topics.length == 0 || lastLogs[i].topics[0] != BATTLE_ENTRY_SIG) continue;
            (, uint32 chips) = abi.decode(lastLogs[i].data, (uint256, uint32));
            assertEq(chips, BOARD, "an awarded entry lost its saved board");
            ++n;
        }
    }
}
