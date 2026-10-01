// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @title WardenLbxClosingBoxOrder -- the closing presale box cannot front-run its cohort
/// @notice Box-order migration: the removed permissionless per-(player,index) `openBox` let the
///         closing buyer open before the same-index cohort, which is what the original version of
///         this test set out to prove was harmless (order-independent DGNRS). That capability no
///         longer exists: `openBoxes` is a strict in-order, oldest-first walk of `boxPlayers[index & 1]`,
///         so the closer (bought last, the crossing buy) can never be opened ahead of its cohort
///         (bought first) -- the title's claim now holds STRUCTURALLY rather than merely by
///         observed invariant. This test instead proves: (1) the cohort drains before the closer is
///         even reachable, (2) the closer's own roll and the pool's residual "drain latch" sweep
///         (both credited to the closer) are the two components of the one call that finishes the
///         index, decomposed via the `PresaleBoxRemainderSwept` event, and (3) the closer's own roll
///         never itself takes a windfall share of the pool -- the remainder does, via the latch.
contract WardenLbxClosingBoxOrder is DeployProtocol {
    uint256 constant SLOT_PRESALE_BOX_ETH_SOLD = 16;
    uint256 constant SLOT_PRESALE_BOX_CREDIT = 17;
    uint256 constant SLOT_PRESALE_BOX_ETH = 18;
    uint256 constant SLOT_LOOTBOX_RNG_PACKED = 33;
    uint256 constant SLOT_LOOTBOX_RNG_WORD = 34;
    uint256 constant PRESALE_BOX_ETH_CAP = 50 ether;

    bytes32 constant REMAINDER_SWEPT_TOPIC = keccak256("PresaleBoxRemainderSwept(address,uint256)");

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

    function _boxRecord(uint48 index, address player) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(SLOT_PRESALE_BOX_ETH)));
        return uint256(vm.load(address(game), keccak256(abi.encode(player, inner))));
    }

    function _setRngWord(uint48 index, uint256 word) internal {
        RecyclingState.seedWord(address(game), uint48(index), bytes32(word));
    }

    function _setPoolBalanceTo(uint256 target) internal {
        uint256 cur = _poolBal();
        if (cur <= target) return;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.PresaleBox, address(0xDEAD), cur - target);
    }

    function _outcome(uint256 rngWord, address player, uint48 index) internal pure returns (uint256) {
        return uint16(uint256(keccak256(abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, index)))) % 100;
    }

    function _buyBox(address buyer, uint256 amount) internal returns (uint48 index) {
        vm.store(address(game), keccak256(abi.encode(buyer, uint256(SLOT_PRESALE_BOX_CREDIT))), bytes32(amount));
        vm.deal(buyer, amount);
        index = _lrIndex();
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(buyer, amount);
    }

    /// @dev Advance LR_INDEX past `index` (mirrors a landed VRF word) and park the sweep's open
    ///      frontier exactly on it, so a bounded openBoxes() call can only ever touch this index's
    ///      queue.
    function _finalizeAndParkSweep(uint48 index) internal {
        uint256 mask48 = (uint256(1) << 48) - 1;
        uint256 lr = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED)));
        vm.store(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED), bytes32((lr & ~mask48) | (uint256(index) + 1)));

        bytes32 cursorSlot = bytes32(uint256(56)); // packed (boxCursor @ byte 7, boxCursorIndex @ byte 13)
        uint256 cur = uint256(vm.load(address(game), cursorSlot));
        cur &= ~(mask48 << (7 * 8));
        cur &= ~(mask48 << (13 * 8));
        cur |= (uint256(index) & mask48) << (13 * 8);
        vm.store(address(game), cursorSlot, bytes32(cur));
    }

    /// @dev Sum every PresaleBoxRemainderSwept amount in `logs` (there is at most one per sweep
    ///      call in this test, but summing is the honest read of "what the latch swept").
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
        for (uint256 i; i < 3; ++i) _buyBox(v[i], amount);

        // The crossing buy: cumulative sold = cap - amount, so this box latches closing.
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(PRESALE_BOX_ETH_CAP - amount)));
        address closer = makeAddr("closer");
        _buyBox(closer, amount);
        assertTrue((_boxRecord(index, closer) >> 255) & 1 == 1, "closer holds the closing bit");

        uint256 pool = 100_000 ether;
        _setPoolBalanceTo(pool);

        // One committed word for the whole index; pick one under which every victim rolls the
        // DGNRS band (the word is a VRF output -- the search only selects the 6.4% case).
        uint256 word;
        for (word = 1; word < 100_000; ++word) {
            bool all = true;
            for (uint256 i; i < 3; ++i) {
                uint256 o = _outcome(word, v[i], index);
                if (o < 50 || o >= 90) { all = false; break; }
            }
            if (all) break;
        }
        _setRngWord(index, word);

        // Finalize `index` and park the sweep frontier on it: boxPlayers[index & 1] queues v[0],
        // v[1], v[2] (bought first), then closer (bought last, the crossing buy) -- the ONLY
        // order the in-order sweep can ever produce now.
        _finalizeAndParkSweep(index);

        // openBoxes(2): the afking leg's ring scan (the deploy's standing subscribers, none with a
        // pending box) rounds up to one step of maxCount, leaving the human sweep one entry-weight
        // of budget. That sweep always runs the first entry of a call regardless of its cost
        // (openHumanBoxes), then the `opened != 0` guard stops before a second -- three such calls
        // open exactly the cohort, one at a time, and never reach the closer.
        for (uint256 i; i < 3; ++i) {
            assertEq(sdgnrs.balanceOf(closer), 0, "closer cannot front-run -- still unopened while cohort drains");
            game.openBoxes(2);
            assertGt(sdgnrs.balanceOf(v[i]), 0, "cohort-first: DGNRS-branch victim is paid");
        }
        uint256 remainder = _poolBal();
        assertGt(remainder, 0, "the pool still holds a remainder once the cohort alone has drawn");
        assertEq(sdgnrs.balanceOf(closer), 0, "the closer is still unreached after the whole cohort");

        // Opening the closer is the entry that completes the index, so its own roll AND the
        // pool's drain-latch sweep (both credited to `closer`) land in this one call -- there is
        // no longer a call boundary between "the closing open" and "the later sweep past the
        // close index" the way the removed per-(player,index) door allowed. The
        // PresaleBoxRemainderSwept event still isolates the latch's contribution from the
        // closer's own roll.
        uint256 closerBalBefore = sdgnrs.balanceOf(closer);
        vm.recordLogs();
        uint256 opened = game.openBoxes(2);
        assertEq(opened, 1, "exactly the closer's one entry opened");
        uint256 sweptRemainder = _remainderSweptIn(vm.getRecordedLogs());
        uint256 closerOwnRoll = sdgnrs.balanceOf(closer) - closerBalBefore - sweptRemainder;

        assertEq(sweptRemainder, remainder, "the drain latch sweeps exactly the pool's pre-close remainder");
        assertEq(_poolBal(), 0, "the drain latch leaves the pool empty");
        assertLt(closerOwnRoll, pool / 2, "the closer's own roll never itself takes the pool");
        emit log_named_uint("closer own roll (wei)", closerOwnRoll);
        emit log_named_uint("remainder swept at drain (wei)", remainder);
    }
}
