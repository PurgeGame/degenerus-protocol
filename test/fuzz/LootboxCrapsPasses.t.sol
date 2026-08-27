// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title The lootbox's craps day-pass lane, end to end
/// @notice Drives the REAL production path: a box is set up in Game storage, `openBox` resolves it
///         through the shipped module, and everything asserted here is read back out of the live
///         craps table. Nothing about the conversion is mirrored or restated — a mirror could agree
///         with itself while the shipped arithmetic drifted underneath it.
contract LootboxCrapsPasses is DeployProtocol {
    uint256 constant SLOT_LOOTBOX_ETH = 15;
    uint256 constant SLOT_LOOTBOX_WORD = 34;
    uint256 constant LB_SCORE_SHIFT = 24;
    uint256 constant LB_CUSTOM_COUNT_SHIFT = 105;
    uint256 constant LB_CUSTOM_SIZE_SHIFT = 113;
    uint256 constant LB_CUSTOM_SCALE = 1e12;

    bytes32 constant PASS_EVENT = keccak256("LootBoxCrapsPasses(address,uint32,uint32,uint24)");

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    function _nested(uint256 baseSlot, uint48 index, address player) internal pure returns (bytes32) {
        return keccak256(abi.encode(player, keccak256(abi.encode(uint256(index), baseSlot))));
    }

    function _simple(uint256 baseSlot, uint48 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(index), baseSlot));
    }

    function _setupLootbox(address player, uint48 index, uint256 ethAmount, uint256 vrfWord) internal {
        uint256 packed = uint256(game.level()) | (uint256(1) << LB_SCORE_SHIFT)
            | (uint256(1) << LB_CUSTOM_COUNT_SHIFT) | ((ethAmount / LB_CUSTOM_SCALE) << LB_CUSTOM_SIZE_SHIFT);
        vm.store(address(game), _nested(SLOT_LOOTBOX_ETH, index, player), bytes32(packed));
        vm.store(address(game), _simple(SLOT_LOOTBOX_WORD, index), bytes32(vrfWord));
    }

    /// @dev Open a box on a chosen word and report what, if anything, it announced. Deliberately
    ///      OBSERVES rather than predicts: restating the module's seed derivation here would give a
    ///      fixture that agrees with a copy of the code instead of with the code.
    function _open(address player, uint48 index, uint256 word, uint256 size)
        internal
        returns (bool found, uint32 normal, uint32 high, uint24 day)
    {
        _setupLootbox(player, index, size, word);
        vm.recordLogs();
        vm.prank(player);
        game.openBox(player, index);
        return _passEventIn(vm.getRecordedLogs());
    }

    /// @dev Walk fresh words until one lands in the pass lane, and report the word that did it.
    ///      About one box in ten qualifies, so this finds one quickly; a sweep that never does is
    ///      itself the failure.
    function _findPassWord(address player, uint48 base, uint256 size)
        internal
        returns (uint256 word, uint32 normal, uint32 high)
    {
        for (uint256 i = 1; i < 60; ++i) {
            uint256 w = uint256(keccak256(abi.encode("pass", base, i)));
            (bool found, uint32 n, uint32 h,) = _open(player, uint48(uint256(base) + i), w, size);
            if (found) return (w, n, h);
        }
        revert("no box in this sweep reached the pass lane");
    }

    function _passEventIn(Vm.Log[] memory logs)
        internal
        pure
        returns (bool found, uint32 normal, uint32 high, uint24 day)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == PASS_EVENT) {
                (normal, high, day) = abi.decode(logs[i].data, (uint32, uint32, uint24));
                found = true;
            }
        }
    }

    function _ready() internal returns (address player) {
        _completeDay(0xBEEF0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xBEEF0002);
        player = makeAddr("boxer");
        vm.deal(player, 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────

    /// @dev THE LANE REACHES THE TABLE. Whatever a pass box announces, the craps table is holding
    ///      exactly that much a moment later — one pass seated where a day was free, the rest
    ///      banked, and the two adding up to the award.
    function test_aPassBoxDeliversToTheCrapsTable() public {
        address player = _ready();
        (, uint32 normal, uint32 high) = _findPassWord(player, 4000, 10 ether);
        assertGt(uint256(normal) + high, 0, "the award was empty, so nothing was measured");

        (uint256 bankedN, uint256 bankedH) = crapsBattle.passCreditsOf(player);
        uint24 tomorrow = crapsBattle.currentDayIndex() + 1;
        uint256 seated = crapsBattle.dayStateOf(tomorrow, player) == 0 ? 0 : 1;

        assertEq(
            bankedN + bankedH + seated,
            uint256(normal) + high,
            "the table holds a different award than the box announced"
        );
    }

    /// @dev ONE DENOMINATION PER BOX, never a mixture. A box that would pay past twenty normal
    ///      passes pays high-roller ones INSTEAD — it does not pay twenty normal and then top up.
    function test_aBoxPaysOneDenominationNotAMixture() public {
        address player = _ready();
        uint256 seen;
        uint256 mixed;
        for (uint48 i = 1; i < 45; ++i) {
            (bool found, uint32 n, uint32 h,) =
                _open(player, 5000 + i, uint256(keccak256(abi.encode("mix", i))), (uint256(i) % 9 + 1) * 30 ether);
            if (!found) continue;
            ++seen;
            if (n != 0 && h != 0) ++mixed;
        }
        // Without this the loop could find nothing and the assertion below would be vacuous.
        assertGt(seen, 2, "no box in this sweep reached the pass lane, so nothing was measured");
        assertEq(mixed, 0, "a single box paid both denominations");
    }

    /// @dev THE AWARD IS A FUNCTION OF THE COMMITTED WORD ALONE. Replaying the same box from the
    ///      same state, at a different time and block, draws the identical count — so no
    ///      timestamp, caller, block or evolving salt reaches the outcome.
    function test_theAwardIsAFunctionOfTheCommittedWordAlone() public {
        address player = _ready();
        uint256 snap = vm.snapshotState();
        (uint256 word, uint32 n1, uint32 h1) = _findPassWord(player, 6000, 40 ether);
        uint48 index = 6000;
        // Re-find the exact index the winning word used by replaying the search deterministically.
        for (uint256 i = 1; i < 60; ++i) {
            if (uint256(keccak256(abi.encode("pass", uint48(6000), i))) == word) {
                index = uint48(6000 + i);
                break;
            }
        }

        vm.revertToState(snap);
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 5000);
        (bool f2, uint32 n2, uint32 h2,) = _open(player, index, word, 40 ether);

        assertTrue(f2, "the replay reached no pass lane at all");
        assertEq(n1, n2, "the replay drew a different normal count");
        assertEq(h1, h2, "the replay drew a different high count");
    }

    /// @dev TWO BUCKETS OF TWENTY, and the zero-pass fallback is real.
    ///
    ///      A box big enough that its budget clears a whole pass announces one whenever it reaches
    ///      the lane, so its announce rate IS the lane's share of the table: ten percent, not the
    ///      fifteen the three flat-FLIP buckets used to carry and not the five that was left
    ///      behind. A SMALL box reaches the lane just as often but frequently rounds to zero and
    ///      takes the WWXRP consolation instead, so it announces strictly less — which is the
    ///      fallback showing up in the only place it is observable from outside.
    function test_thePassLaneIsTwoBucketsAndSmallBoxesFallBack() public {
        address player = _ready();
        uint256 n = 200;
        uint256 big;
        uint256 small;
        for (uint48 i = 1; i <= n; ++i) {
            (bool f1,,,) = _open(player, 9000 + i, uint256(keccak256(abi.encode("big", i))), 200 ether);
            if (f1) ++big;
            (bool f2,,,) = _open(player, 20000 + i, uint256(keccak256(abi.encode("small", i))), 3 ether);
            if (f2) ++small;
        }
        emit log_named_uint("announced, large boxes", big);
        emit log_named_uint("announced, small boxes", small);

        // A MIX CHECK, NOT A CHI-SQUARED. Two buckets of twenty put the mean at 20 of these 200
        // with a standard deviation near 4.2, so the band is set to separate bucket COUNTS —
        // one bucket lands on 10 and three on 30, and neither fits inside ±8 of 20 — rather than
        // to chase sampling noise. The words are fixed, so the figure is stable run to run.
        assertApproxEqAbs(big, n / 10, 8, "the pass lane is not two buckets of twenty");
        assertLt(big, n, "every box reached the pass lane, so the other lanes are gone");
        assertLt(small, big, "small boxes announced as often as large ones: the zero-pass fallback is not firing");
    }

    /// @dev FAIL-OPEN. Lootbox settlement is a permissionless sweep other players depend on, so a
    ///      craps table that cannot be reached must not take a box down with it: the open still
    ///      succeeds, and the award is still announced so nothing about it is invisible.
    function test_anUnreachableTableDoesNotWedgeTheBox() public {
        address player = _ready();
        uint256 snap = vm.snapshotState();
        (uint256 word,,) = _findPassWord(player, 8000, 10 ether);
        uint48 index = 8000;
        for (uint256 i = 1; i < 60; ++i) {
            if (uint256(keccak256(abi.encode("pass", uint48(8000), i))) == word) {
                index = uint48(8000 + i);
                break;
            }
        }

        // Back to before any of it happened, then break the table.
        vm.revertToState(snap);
        vm.etch(address(crapsBattle), hex"60006000fd");

        (bool found,,, uint24 day) = _open(player, index, word, 10 ether);
        assertTrue(found, "the award went unannounced when the table was unreachable");
        assertEq(day, 0, "an unreachable table still reported a reservation");
    }
}
