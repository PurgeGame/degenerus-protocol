// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title WardenLbxClosingBoxOrder -- the closing presale box cannot front-run its cohort
/// @notice mineFlip's human-box stage is a strict in-order, oldest-first walk of the sealed
///         buffer's box queue (one entry per purchase, settled from `boxCursor`), so the closer
///         (bought last, the crossing buy) can never be opened ahead of its cohort (bought
///         first) -- the title's claim holds STRUCTURALLY rather than merely by observed
///         invariant. This test proves: (1) the cohort drains before the closer is even
///         reachable, (2) the closer's own roll and the pool's remainder (both credited to the
///         closer) are the two components of the closing entry's one resolution, decomposed via
///         the `PresaleBoxRemainderSwept` event, and (3) the closer's own roll never itself takes
///         a windfall share of the pool -- the remainder does, after that roll.
contract WardenLbxClosingBoxOrder is DeployProtocol {
    using BoxOrderLib for uint256;

    uint256 constant SLOT_PRESALE_BOX_ETH_SOLD = GameSlots.PRESALE_BOX_ETH_SOLD;
    uint256 constant SLOT_PRESALE_BOX_CREDIT = GameSlots.PRESALE_BOX_CREDIT;
    uint256 constant PRESALE_BOX_ETH_CAP = 50 ether;
    uint256 constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572; // "QueuedOrder"

    bytes32 constant REMAINDER_SWEPT_TOPIC = keccak256("PresaleBoxRemainderSwept(uint32,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _poolBal() internal view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool.PresaleBox);
    }

    function _lrIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Next unsettled position of the read buffer.
    function _cursor() internal view returns (uint256) {
        return uint48(uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8));
    }

    /// @dev Deliver and publish `word` for the sealed cohort at `index`, as a fulfilled mid-day
    ///      request leaves it, on a sealed day (dailyIdx = today, tickets drained): the cohort's
    ///      human entries are then the next engine stage, cursor at the queue head.
    function _setRngWord(uint48 index, uint256 word) internal {
        RecyclingState.seedWord(address(game), uint48(index), bytes32(word));
        // dailyIdx and ticketsFullyProcessed share one slot.
        require(GameSlots.DAILY_IDX == GameSlots.TICKETS_FULLY_PROCESSED, "slot-0 fixture");
        uint256 slot0 = uint256(vm.load(address(game), bytes32(GameSlots.DAILY_IDX)));
        uint256 dayShift = GameSlots.DAILY_IDX_OFFSET * 8;
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << dayShift)) | (uint256(game.currentDayView()) << dayShift)
            | (uint256(1) << (GameSlots.TICKETS_FULLY_PROCESSED_OFFSET * 8));
        vm.store(address(game), bytes32(GameSlots.DAILY_IDX), bytes32(slot0));
    }

    /// @dev The smallest mineFlip allowance that opens one more entry (bisection over snapshots).
    ///      Each entry is admitted only while the remaining allowance covers its declared bound,
    ///      and every presale-only entry carries the same bound, so this budget opens exactly one.
    function _oneEntryBudget() internal returns (uint256) {
        uint256 before = _cursor();
        uint256 lo = 100_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            bool opened = ok && _cursor() > before;
            vm.revertToStateAndDelete(snap);
            if (opened) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    function _setPoolBalanceTo(uint256 target) internal {
        uint256 cur = _poolBal();
        if (cur <= target) return;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.PresaleBox, address(0xDEAD), cur - target);
    }

    /// @dev The presale branch roll of entry `position` in `index` (see `_resolvePresaleBox`).
    function _outcome(uint256 rngWord, address player, uint48 index, uint256 position) internal view returns (uint256) {
        uint256 root = uint256(keccak256(abi.encode(QUEUED_ORDER_DOMAIN, rngWord, uint256(index), position)));
        uint256 seed = uint256(keccak256(abi.encode(
            root, uint256(game.walletIdOf(player)), uint256(keccak256("PRESALE_BOX")), uint256(index)
        )));
        return uint16(seed) % 100;
    }

    /// @dev One real presale buy; returns the entry's position in the write buffer.
    function _buyBox(address buyer, uint256 amount) internal returns (uint256 position) {
        uint32 id = game.walletIdOf(buyer);
        if (id == 0) id = _giveWalletId(buyer);
        vm.store(address(game), keccak256(abi.encode(uint256(id), uint256(SLOT_PRESALE_BOX_CREDIT))), bytes32(amount));
        vm.deal(buyer, amount);
        position = RecyclingState.boxCount(address(game), _lrIndex());
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(0, amount);
        assertEq(RecyclingState.boxCount(address(game), _lrIndex()), position + 1, "one entry per purchase");
    }

    /// @dev Sum every PresaleBoxRemainderSwept amount in `logs` (at most one: the closing entry's).
    function _remainderSweptIn(Vm.Log[] memory logs) internal pure returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == REMAINDER_SWEPT_TOPIC) {
                total += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    function test_ClosingBoxOpensOnlyAfterItsCohortViaTheInOrderSweep() public {
        uint48 index = _lrIndex();
        // 1-ETH boxes: tier-1 draws are 7.5% of poolStart each, so the cohort leaves a remainder.
        uint256 amount = 1 ether;
        address[3] memory v = [makeAddr("victim0"), makeAddr("victim1"), makeAddr("victim2")];
        uint256[3] memory pos;
        for (uint256 i; i < 3; ++i) pos[i] = _buyBox(v[i], amount);

        // The crossing buy: cumulative sold = cap - amount, so this box latches closing.
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(PRESALE_BOX_ETH_CAP - amount)));
        address closer = makeAddr("closer");
        uint256 closerPos = _buyBox(closer, amount);
        assertEq(closerPos, pos[2] + 1, "the closer is appended after its cohort");
        assertTrue(RecyclingState.boxEntry(address(game), index, closerPos).boPresaleClosing(), "closer holds the closing bit");

        uint256 pool = 100_000 ether;
        _setPoolBalanceTo(pool);

        // One committed word for the whole buffer; pick one under which every victim rolls the
        // DGNRS band (the word is a VRF output -- the search only selects the 6.4% case).
        uint256 word;
        for (word = 1; word < 100_000; ++word) {
            bool all = true;
            for (uint256 i; i < 3; ++i) {
                uint256 o = _outcome(word, v[i], index, pos[i]);
                if (o < 50 || o >= 90) { all = false; break; }
            }
            if (all) break;
        }
        // Seal `index` with its word: its queue holds v[0], v[1], v[2] (bought first), then the
        // closer (bought last, the crossing buy) -- the ONLY order the in-order sweep can walk.
        _setRngWord(index, word);
        assertEq(pos[0], 0, "fixture: the cohort heads the queue");
        assertEq(_cursor(), 0, "the sweep starts at the queue head");

        // Each engine call gets the smallest allowance that opens an entry, which never fits a
        // second -- three such calls open exactly the cohort, one at a time, and never reach the
        // closer.
        for (uint256 i; i < 3; ++i) {
            assertEq(sdgnrs.balanceOf(closer), 0, "closer cannot front-run -- still unopened while cohort drains");
            game.mineFlip{gas: _oneEntryBudget()}();
            assertEq(_cursor(), pos[i] + 1, "exactly the next cohort entry opened");
            assertGt(sdgnrs.balanceOf(v[i]), 0, "cohort-first: DGNRS-branch victim is paid");
        }
        uint256 remainder = _poolBal();
        assertGt(remainder, 0, "the pool still holds a remainder once the cohort alone has drawn");
        assertEq(sdgnrs.balanceOf(closer), 0, "the closer is still unreached after the whole cohort");

        // Opening the closer's entry runs its own roll and then pays the pool's remainder (both
        // credited to `closer`) in the same resolution. The PresaleBoxRemainderSwept event
        // isolates the remainder from the closer's own roll.
        uint256 closerBalBefore = sdgnrs.balanceOf(closer);
        uint256 closerBudget = _oneEntryBudget();
        vm.recordLogs();
        game.mineFlip{gas: closerBudget}();
        assertEq(_cursor(), closerPos + 1, "exactly the closer's one entry opened");
        uint256 sweptRemainder = _remainderSweptIn(vm.getRecordedLogs());
        uint256 closerOwnRoll = sdgnrs.balanceOf(closer) - closerBalBefore - sweptRemainder;

        assertEq(sweptRemainder, remainder - closerOwnRoll, "the remainder is exactly what the closer's own roll left");
        assertEq(_poolBal(), 0, "the closing entry leaves the pool empty");
        assertLt(closerOwnRoll, pool / 2, "the closer's own roll never itself takes the pool");
        emit log_named_uint("closer own roll (wei)", closerOwnRoll);
        emit log_named_uint("remainder paid at close (wei)", sweptRemainder);
    }
}
