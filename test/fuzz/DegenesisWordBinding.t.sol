// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegenesisWordBinding -- the degenesisWord copy outlives the two-day word ring
/// @notice Plan §3.3 "Binding": the bound day's word is copied into degenesisWord when it is
///         recorded, and settlement reads only that copy. A cohort whose settlement is still
///         running two daily words later (the ring slot of its bound day overwritten) still
///         resolves every order exactly as the reference computed from the bound day's word.
contract DegenesisWordBinding is DegenesisHarness {
    address[5] internal buyers;

    function setUp() public override {
        super.setUp();
        _drive(0);
        for (uint256 i; i < 5; ++i) {
            buyers[i] = _player(string.concat("wb-", vm.toString(i)));
            _earnCredit(buyers[i], 40 ether);
        }
        _driveDay(2, 0);
    }

    function _placeOrders(uint256 n) internal {
        _warpTo(2, 2 hours);
        for (uint256 i; i < n; ++i) {
            vm.warp(_dayStart(2) + 2 hours + i * 30);
            _buy(buyers[i % 5], 0.01 ether + (i % 11) * 0.0007 ether + (i % 4) * 0.0101 ether);
        }
    }

    function _ringTag(uint256 parity) internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.RNG_DAY_TAGS))) >> (parity * 24));
    }

    function _ringWord(uint256 parity) internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.RNG_WORD_BY_DAY + (uint256(parity) & 1))));
    }

    /// @dev Bind cohort 1 to day 3 with `w3`, settle one 128-order chunk, then run the day-4 and
    ///      day-5 daily words without finishing settlement (each day's last engine step can carry
    ///      at most one 128-order chunk, so n > 4 chunks keeps a backlog). Returns cohort 1's Q.
    function _bindAndRotate(uint256 n, uint256 w3) internal returns (uint256 q) {
        _placeOrders(n);
        q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        _requestOnly(w3);
        _driveToSettle();
        assertEq(_word(), w3, "word copied at recording");
        game.mineRun(0);
        assertLt(_activeCursor(), n, "backlog left after one chunk");
        _warpTo(4, 1 hours);
        _driveToSettle();
        _warpTo(5, 1 hours);
        _driveToSettle();
        assertEq(_closed(), 0, "cohort 1 still settling");
        assertLt(_activeCursor(), n, "backlog survives two more daily words");
        assertEq(_activeDay(), 3, "still bound to day 3");
        assertEq(_ringTag(1), 5, "day 3's ring slot now holds day 5");
        assertTrue(_ringWord(1) != w3, "day 3's ring word overwritten");
        assertEq(game.rngWordForDay(3), 0, "ring no longer serves day 3");
        assertEq(_word(), w3, "degenesisWord copy retained");
    }

    /// @notice The copy is written when the bound day's word is recorded, equals it, and is
    ///         cleared when the cohort closes.
    function test_WordCopiedWhenBoundDayWordRecorded() public {
        _placeOrders(150); // more than one 128-order chunk, so the copy is observable between steps
        uint256 w3 = uint256(keccak256("wb-copy"));
        _warpTo(3, 1 hours);
        _requestOnly(w3);
        assertEq(_activeDay(), 3, "priced and bound at the day-3 request");
        assertEq(_word(), 0, "no copy before the word is recorded");
        uint256 seen;
        for (uint256 i; i < 500 && _closed() == 0; ++i) {
            _mineStep(2_500_000);
            if (seen == 0 && _word() != 0) {
                seen = _word();
                assertEq(game.rngWordForDay(3), w3, "ring holds the same word");
            }
        }
        assertEq(seen, w3, "copy equals the recorded day-3 word");
        assertEq(_closed(), 1, "cohort closed");
        assertEq(_word(), 0, "copy cleared at close");
        assertEq(_active(), 0, "active cleared at close");
    }

    /// @notice Settlement finishes correctly after the ring rotated twice past the bound day:
    ///         every order equals the reference computed from the day-3 word.
    function test_SettlementCompletesAfterRingRotated() public {
        uint256 n = 520;
        uint256 w3 = uint256(keccak256("wb-rotate"));
        vm.recordLogs();
        uint256 q = _bindAndRotate(n, w3);
        _drive(0);
        Res[] memory got = _resolved(vm.getRecordedLogs());
        assertEq(_closed(), 1, "closed after the late finish");
        Res[] memory want = _refCohort(1, w3, q);
        assertEq(got.length, n, "every order once");
        for (uint256 i; i < n; ++i) _assertRes(got[i], want[i], string.concat("late order ", vm.toString(i)));
    }

    /// @notice Garbage in both ring slots, with day 3's tag forged back in, changes nothing:
    ///         settlement never reads rngWordByDay.
    function test_SettlementIgnoresRingWords() public {
        uint256 n = 520;
        uint256 w3 = uint256(keccak256("wb-ignore"));
        vm.recordLogs();
        uint256 q = _bindAndRotate(n, w3);
        uint256 junk = uint256(keccak256("ring-junk"));
        vm.store(address(game), bytes32(GameSlots.RNG_WORD_BY_DAY + (uint256(0) & 1)), bytes32(junk));
        vm.store(address(game), bytes32(GameSlots.RNG_WORD_BY_DAY + (uint256(1) & 1)), bytes32(junk ^ 1));
        uint256 tags = uint256(vm.load(address(game), bytes32(GameSlots.RNG_DAY_TAGS)));
        tags = (tags & ~(uint256(type(uint24).max) << 24)) | (uint256(3) << 24);
        vm.store(address(game), bytes32(GameSlots.RNG_DAY_TAGS), bytes32(tags));
        for (uint256 i; i < 500 && _closed() == 0; ++i) {
            if (!_mineStep(30_000_000)) break;
        }
        assertEq(_closed(), 1, "closed");
        Res[] memory got = _resolved(vm.getRecordedLogs());
        Res[] memory want = _refCohort(1, w3, q);
        assertEq(got.length, n, "every order once");
        for (uint256 i; i < n; ++i) _assertRes(got[i], want[i], string.concat("order ", vm.toString(i)));
    }

    /// @notice Settlement follows the degenesisWord slot: orders resolved after it is
    ///         overwritten use the new word, earlier ones keep the bound word.
    function test_SettlementReadsOnlyDegenesisWord() public {
        uint256 n = 520;
        uint256 w3 = uint256(keccak256("wb-follow"));
        vm.recordLogs();
        uint256 q = _bindAndRotate(n, w3);
        uint256 k = _activeCursor();
        uint256 w2 = uint256(keccak256("wb-forged"));
        vm.store(address(game), bytes32(GameSlots.DEGENESIS_WORD), bytes32(w2));
        _drive(0);
        Res[] memory got = _resolved(vm.getRecordedLogs());
        Res[] memory before_ = _refCohort(1, w3, q);
        Res[] memory after_ = _refCohort(1, w2, q);
        assertEq(got.length, n, "every order once");
        for (uint256 i; i < n; ++i) {
            _assertRes(got[i], i < k ? before_[i] : after_[i], string.concat("order ", vm.toString(i)));
        }
    }

    /// @notice Structural: the Degenesis module never names the word ring or its readers, and
    ///         Storage writes the copy only for the active cohort's bound day.
    function test_ModuleSourceNeverReadsWordRing() public view {
        string memory src = vm.readFile("contracts/modules/DegenerusGameDegenesisModule.sol");
        assertFalse(vm.contains(src, "rngWordByDay"), "no rngWordByDay");
        assertFalse(vm.contains(src, "_recordedDailyWord"), "no _recordedDailyWord");
        assertFalse(vm.contains(src, "_retainedDailyWord"), "no _retainedDailyWord");
        assertFalse(vm.contains(src, "rngWordCurrent"), "no rngWordCurrent");
        assertTrue(vm.contains(src, "g.word = degenesisWord;"), "settlement reads the copy");
        string memory st = vm.readFile("contracts/storage/DegenerusGameStorage.sol");
        assertTrue(
            vm.contains(
                st,
                "if (degenesisClosed < DEGENESIS_DAYS && uint24(degenesisActive >> GA_DAY_SHIFT) == day) degenesisWord = word;"
            ),
            "copy keyed on the bound day"
        );
    }
}
