// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @notice Presale payout regression: real buys and FIFO engine opens, with one immutable
///         word per session. Only earned credit, completed ticket prerequisites and entropy
///         are seeded. Tests preserve the tier ratio, live-pool clamp and closing-dust bounds;
///         the closing entry's own resolution pays the Pool.PresaleBox remainder
///         (`poolBalance` then `transferFromPool`) after every earlier presale box.
contract PresaleBoxDrain is DeployProtocol {
    using BoxOrderLib for uint256;

    uint256 constant SLOT_PRESALE_BOX_ETH_SOLD = GameSlots.PRESALE_BOX_ETH_SOLD;
    uint256 constant SLOT_PRESALE_BOX_CREDIT = GameSlots.PRESALE_BOX_CREDIT;
    uint256 constant PRESALE_BOX_ETH_CAP = 50 ether;
    uint256 constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572; // "QueuedOrder"
    uint256 constant QUEUED_ENTRY_TAG = uint256(1) << 46;
    bytes32 constant OPENED = keccak256("PresaleBoxOpened(uint32,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 constant SWEPT = keccak256("PresaleBoxRemainderSwept(uint32,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _poolBal() private view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool.PresaleBox);
    }

    /// @dev Next unsettled position of the read buffer.
    function _cursor() private view returns (uint256) {
        return uint48(uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8));
    }

    function _entry(uint48 index, uint256 position) private view returns (uint256) {
        return RecyclingState.boxEntry(address(game), index, position);
    }

    /// @dev One real presale buy; asserts it appended the next entry of the write buffer.
    function _buyBox(address buyer, uint256 amount) private {
        uint32 id = game.walletIdOf(buyer);
        if (id == 0) id = _giveWalletId(buyer);
        vm.store(address(game), keccak256(abi.encode(uint256(id), SLOT_PRESALE_BOX_CREDIT)), bytes32(amount));
        vm.deal(buyer, amount);
        uint48 index = RecyclingState.writeBuffer(address(game));
        uint256 before = RecyclingState.boxCount(address(game), index);
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(0, amount);
        assertEq(RecyclingState.boxCount(address(game), index), before + 1, "one entry per presale purchase");
        assertEq(_entry(index, before).boId(), id, "the entry carries the buyer's wallet ID");
    }

    /// @dev The presale branch roll of entry `position` in `index`:
    ///      hash4(hash4(QUEUED_ORDER_DOMAIN, word, buffer, position), walletId, PRESALE_BOX_TAG, buffer).
    function _outcome(uint256 word, address buyer, uint48 index, uint256 position) private view returns (uint256) {
        uint256 root = uint256(keccak256(abi.encode(QUEUED_ORDER_DOMAIN, word, uint256(index), position)));
        uint256 seed = uint256(keccak256(abi.encode(
            root, uint256(game.walletIdOf(buyer)), uint256(keccak256("PRESALE_BOX")), uint256(index)
        )));
        return uint16(seed) % 100;
    }

    function _allDgnrsWord(address[] memory buyers, uint48 index, uint256 base) private view returns (uint256 word) {
        for (word = 2; word < 100_000; ++word) {
            bool all = true;
            for (uint256 i; i < buyers.length; ++i) {
                uint256 roll = _outcome(word, buyers[i], index, base + i);
                if (roll < 50 || roll >= 90) { all = false; break; }
            }
            if (all) return word;
        }
        revert("no common DGNRS word found");
    }

    /// @dev The closer rolls the WWXRP branch and at least 40% of the cohort rolls DGNRS.
    function _realisticWord(uint256 word, address[] memory buyers, uint48 index, uint256 base)
        private
        view
        returns (bool)
    {
        uint256 last = buyers.length - 1;
        if (_outcome(word, buyers[last], index, base + last) < 90) return false;
        uint256 branches;
        for (uint256 i; i < buyers.length; ++i) {
            uint256 roll = _outcome(word, buyers[i], index, base + i);
            if (roll >= 50 && roll < 90) ++branches;
        }
        return branches * 100 >= buyers.length * 40;
    }

    /// @dev Independent expression of the documented curve and three-significant-figure floor.
    function _expectedReward(uint256 start, uint256 tier, uint256 amount) private pure returns (uint256) {
        uint256 raw = start * tier * amount / (400 * 1 ether);
        uint256 scale = 1;
        while (raw / scale >= 1000) scale *= 10;
        return raw / scale * scale;
    }

    function _tier(uint256 sold) private pure returns (uint256) {
        return sold < 10 ether ? 30 : sold < 20 ether ? 25 : sold < 30 ether ? 20 : sold < 40 ether ? 15 : 10;
    }

    /// @dev The FIFO transcript accumulated across engine calls.
    struct Transcript {
        uint256 opened;
        uint256 swept;
        bool sawSweep;
        uint256[] paid;
    }

    /// @dev The worker owns the checkpoint: bound each mineFlip's gas and verify the emitted FIFO
    ///      transcript across all checkpoints. `buyers` hold entries base..base+n-1 of `index`.
    ///      Progress is read off the resolution events: once the cohort completes, the same
    ///      engine call may already seal the next request, which restarts the cursor.
    function _openAll(uint48 index, uint256 base, uint256 word, address[] memory buyers, uint256 amount)
        private returns (uint256[] memory paid, uint256 swept)
    {
        uint256[] memory amounts = new uint256[](buyers.length);
        for (uint256 i; i < buyers.length; ++i) amounts[i] = amount;
        return _openAll(index, base, word, buyers, amounts);
    }

    /// @dev `_openAll` with each entry's own applied presale amount.
    function _openAll(uint48 index, uint256 base, uint256 word, address[] memory buyers, uint256[] memory amounts)
        private returns (uint256[] memory paid, uint256 swept)
    {
        RecyclingState.seedWord(address(game), index, bytes32(word));
        // These payout fixtures buy presale boxes only: there is no ticket producer to drain.
        // Explicitly model the completed producer prerequisite before entering the human stage.
        bytes32 slot = bytes32(GameSlots.TICKETS_FULLY_PROCESSED);
        uint256 flags = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(flags | (uint256(1) << (GameSlots.TICKETS_FULLY_PROCESSED_OFFSET * 8))));
        assertEq(RecyclingState.boxCount(address(game), index), base + buyers.length, "the sealed cohort's read count");
        assertEq(_cursor(), base, "the sweep starts at the cohort");
        Transcript memory t;
        t.paid = new uint256[](buyers.length);
        vm.recordLogs();
        for (uint256 calls; t.opened < buyers.length && calls < 100; ++calls) {
            uint256 before = t.opened;
            game.mineFlip{gas: 8_000_000}(0);
            _scan(vm.getRecordedLogs(), index, base, buyers, amounts, t);
            assertGt(t.opened, before, "ready FIFO sweep advances");
        }
        assertEq(t.opened, buyers.length, "every queued entry opened exactly once");
        (paid, swept) = (t.paid, t.swept);
        for (uint256 i; i < buyers.length; ++i) {
            assertEq(sdgnrs.balanceOf(buyers[i]), paid[i] + (i == buyers.length - 1 ? swept : 0), "credits match result");
        }
        // Replay probe: whatever the engine does next (or NoWork / a pending word), it pays no entry twice.
        vm.recordLogs();
        (bool replayed,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        replayed;
        Vm.Log[] memory replay = vm.getRecordedLogs();
        for (uint256 i; i < replay.length; ++i) {
            assertFalse(replay[i].emitter == address(game) && replay[i].topics.length != 0
                && replay[i].topics[0] == OPENED, "completed entries cannot pay twice");
        }
    }

    /// @dev Fold one engine call's presale resolutions into the transcript, in FIFO order.
    function _scan(
        Vm.Log[] memory logs,
        uint48 index,
        uint256 base,
        address[] memory buyers,
        uint256[] memory amounts,
        Transcript memory t
    ) private view {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == OPENED) {
                assertLt(t.opened, buyers.length, "no duplicate resolution");
                assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf(buyers[t.opened]), "FIFO recipient");
                assertEq(
                    uint256(logs[i].topics[2]),
                    QUEUED_ENTRY_TAG | ((base + t.opened) << 1) | index,
                    "the entry's own buffer and position"
                );
                (uint256 resolved,, uint256 dgnrsPaid,, bool closing,,) = abi.decode(
                    logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32)
                );
                assertEq(resolved, amounts[t.opened], "applied amount preserved");
                if (closing) assertEq(t.opened, buyers.length - 1, "closing buyer is last");
                t.paid[t.opened++] = dgnrsPaid;
            } else if (logs[i].topics[0] == SWEPT) {
                assertEq(t.opened, buyers.length, "the remainder follows every resolution");
                assertFalse(t.sawSweep, "remainder paid once");
                assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf(buyers[buyers.length - 1]));
                t.swept = abi.decode(logs[i].data, (uint256));
                t.sawSweep = true;
            }
        }
    }

    function test_PFIX03_TierShapePreserved() public {
        uint48 index = RecyclingState.writeBuffer(address(game));
        uint256 base = RecyclingState.boxCount(address(game), index);
        address[] memory buyers = new address[](2);
        buyers[0] = makeAddr("tier1Buyer");
        buyers[1] = makeAddr("tier5Buyer");
        _buyBox(buyers[0], 1 ether);
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(40 ether)));
        _buyBox(buyers[1], 1 ether);
        assertEq(_entry(index, base).boPresaleTier(), 0, "bought below 10 ETH sold: tier 0");
        assertEq(_entry(index, base + 1).boPresaleTier(), 4, "bought from 40 ETH sold: tier 4");
        uint256 start = _poolBal();
        (uint256[] memory paid, uint256 swept) =
            _openAll(index, base, _allDgnrsWord(buyers, index, base), buyers, 1 ether);
        assertGt(paid[0], 0, "tier1 drew DGNRS");
        assertGt(paid[1], 0, "tier5 drew DGNRS");
        assertEq(paid[0], paid[1] * 3, "tier-1 DGNRS-per-ETH == 3 * tier-5 DGNRS-per-ETH");
        assertEq(paid[0], _expectedReward(start, 30, 1 ether), "tier1 fixed curve");
        assertEq(paid[1], _expectedReward(start, 10, 1 ether), "tier5 fixed curve");
        assertEq(swept, 0, "sale remains open");
        assertEq(start - _poolBal(), paid[0] + paid[1], "pool conservation");
    }

    function test_PFIX03_EarlyDgnrsRunEmptiesPoolBeforeClose_ClampHolds() public {
        uint48 index = RecyclingState.writeBuffer(address(game));
        uint256 base = RecyclingState.boxCount(address(game), index);
        address[] memory buyers = new address[](7);
        for (uint256 i; i < buyers.length; ++i) {
            buyers[i] = makeAddr(string(abi.encodePacked("clampBuyer", vm.toString(i))));
            if (i == 6) vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(45 ether)));
            _buyBox(buyers[i], 5 ether);
        }
        assertTrue(_entry(index, base + 6).boPresaleClosing(), "final box closes sale");
        uint256 start = 100_000 ether;
        uint256 excess = _poolBal() - start;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.PresaleBox, address(0xDEAD), excess);
        (uint256[] memory paid, uint256 swept) =
            _openAll(index, base, _allDgnrsWord(buyers, index, base), buyers, 5 ether);
        uint256 remaining = start;
        for (uint256 i; i < buyers.length; ++i) {
            if (i == 6) assertLe(remaining, 1, "pool ~0 before the closing box");
            uint256 expected = _expectedReward(start, _tier(i == 6 ? 45 ether : i * 5 ether), 5 ether);
            if (expected > remaining) expected = remaining;
            assertEq(paid[i], expected, "exact payout after live-pool clamp");
            assertLe(paid[i], remaining, "no per-box draw exceeds live pool");
            remaining -= paid[i];
        }
        assertGt(paid[0], 0, "early DGNRS branch paid");
        assertLe(paid[6] + swept, 1, "closing roll plus remainder <= 1 wei dust");
        assertLe(_poolBal(), 1, "pool ~0 after closing box");
        assertEq(remaining - swept, _poolBal(), "pool conservation");
    }

    function test_PFIX02_RealisticRun_ClosingSweepIsDust() public {
        uint48 index = RecyclingState.writeBuffer(address(game));
        uint256 base = RecyclingState.boxCount(address(game), index);
        address[] memory buyers = new address[](250);
        assertEq(buyers.length * 0.2 ether, PRESALE_BOX_ETH_CAP);
        for (uint256 i; i < buyers.length; ++i) {
            buyers[i] = makeAddr(string(abi.encodePacked("runBuyer", vm.toString(i))));
            _buyBox(buyers[i], 0.2 ether);
        }
        assertTrue(_entry(index, base + 249).boPresaleClosing(), "final box closes sale");
        uint256 start = _poolBal();
        // One fixed word produces the full 50/40/10 distribution naturally: the first word whose
        // closer rolls the WWXRP branch (asserted below) and whose cohort realizes at least the
        // nominal 40% DGNRS branch rate — a realistic run, not a below-nominal one in which the
        // pool legitimately keeps more for the closing entry. Branches only, never any reward.
        uint256 word = 2;
        while (!_realisticWord(word, buyers, index, base)) ++word;
        uint256 branches;
        (uint256[] memory paid, uint256 swept) = _openAll(index, base, word, buyers, 0.2 ether);
        uint256 remaining = start;
        uint256 cumulative;
        for (uint256 i; i < buyers.length; ++i) {
            uint256 roll = _outcome(word, buyers[i], index, base + i);
            bool dgnrsBranch = roll >= 50 && roll < 90;
            if (dgnrsBranch) ++branches;
            uint256 expected = dgnrsBranch ? _expectedReward(start, _tier(i * 0.2 ether), 0.2 ether) : 0;
            if (expected > remaining) expected = remaining;
            assertEq(paid[i], expected, "realized branch and frozen tier determine payout");
            remaining -= paid[i];
            cumulative += paid[i];
        }
        assertGe(branches * 100, buyers.length * 30, "realized DGNRS branch rate >= 30%");
        assertLe(branches * 100, buyers.length * 50, "realized DGNRS branch rate <= 50%");
        assertGe(_outcome(word, buyers[249], index, base + 249), 90, "closer is the WWXRP branch");
        assertEq(paid[249], 0, "closing WWXRP branch draws no DGNRS");
        assertLe(swept, start / 100, "closing remainder <= poolStart/100");
        assertLe(_poolBal(), start / 100, "residual pool <= poolStart/100 after close");
        assertGe(cumulative * 100, start * 90, "per-box cumulative DGNRS draw >= 90% of poolStart");
        assertEq(remaining - swept, _poolBal(), "pool conservation");
        emit log_named_uint("fixture word", word);
        emit log_named_uint("closing remainder (wei)", swept);
    }

    /// @notice The closing entry — here one whose applied amount is the last 1 wei of the sale —
    ///         pays the Pool.PresaleBox remainder (`poolBalance`, then `transferFromPool`) inside
    ///         its own resolution: after every earlier presale box has resolved, exactly once,
    ///         to its own wallet, leaving the pool empty. The cohort's draws are at most 7.5% and
    ///         2.5% of the pool, so the remainder is large whatever the word.
    function test_PFIX02_ClosingEntryPaysTheRemainderAfterEveryEarlierBox() public {
        uint48 index = RecyclingState.writeBuffer(address(game));
        uint256 base = RecyclingState.boxCount(address(game), index);
        address[] memory buyers = new address[](3);
        buyers[0] = makeAddr("earlyBuyer");
        buyers[1] = makeAddr("lateBuyer");
        buyers[2] = makeAddr("oneWeiCloser");
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;
        amounts[2] = 1;
        _buyBox(buyers[0], 1 ether);
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(45 ether)));
        _buyBox(buyers[1], 1 ether);
        // The requested minimum clamps to the sale's last wei and closes it.
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(PRESALE_BOX_ETH_CAP - 1)));
        _buyBox(buyers[2], 0.01 ether);
        uint256 closer = _entry(index, base + 2);
        assertEq(closer.boPresaleWei(), 1, "the closing entry holds exactly the applied 1 wei");
        assertTrue(closer.boPresaleClosing(), "the 1-wei purchase closes the sale");
        assertFalse(_entry(index, base + 1).boPresaleClosing(), "only the closing purchase carries the flag");
        assertEq(game.presaleBoxEthRemaining(), 0, "sale closed");

        uint256 start = _poolBal();
        (uint256[] memory paid, uint256 swept) = _openAll(index, base, 2, buyers, amounts);
        assertGt(swept, 0, "the closing entry paid a remainder");
        assertEq(swept, start - paid[0] - paid[1] - paid[2], "the remainder is the pool after every presale roll");
        assertEq(_poolBal(), 0, "the closing entry leaves the pool empty");
    }
}
