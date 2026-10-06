// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice Presale payout regression: real buys and FIFO engine opens, with one immutable
///         word per session. Only earned credit, completed ticket prerequisites and entropy
///         are seeded. Tests preserve the tier ratio, live-pool clamp and closing-dust bounds.
contract PresaleBoxDrain is DeployProtocol {
    uint256 constant SLOT_PRESALE_BOX_ETH_SOLD = GameSlots.PRESALE_BOX_ETH_SOLD;
    uint256 constant SLOT_PRESALE_BOX_CREDIT = GameSlots.PRESALE_BOX_CREDIT;
    uint256 constant SLOT_PRESALE_BOX_ETH = GameSlots.PRESALE_BOX_ETH;
    uint256 constant PRESALE_BOX_ETH_CAP = 50 ether;
    bytes32 constant OPENED = keccak256("PresaleBoxOpened(address,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 constant SWEPT = keccak256("PresaleBoxRemainderSwept(address,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _poolBal() private view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool.PresaleBox);
    }

    function _boxRecord(uint48 index, address player) private view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), SLOT_PRESALE_BOX_ETH));
        return uint256(vm.load(address(game), keccak256(abi.encode(player, inner))));
    }

    function _buyBox(address buyer, uint256 amount) private {
        uint32 id = game.walletIdOf(buyer);
        if (id == 0) id = _giveWalletId(buyer);
        vm.store(address(game), keccak256(abi.encode(uint256(id), SLOT_PRESALE_BOX_CREDIT)), bytes32(amount));
        vm.deal(buyer, amount);
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(buyer, amount);
    }

    function _outcome(uint256 word, address buyer, uint48 index) private pure returns (uint256) {
        return uint16(uint256(keccak256(abi.encodePacked(word, keccak256("PRESALE_BOX"), buyer, index)))) % 100;
    }

    function _allDgnrsWord(address[] memory buyers, uint48 index) private pure returns (uint256 word) {
        for (word = 2; word < 100_000; ++word) {
            bool all = true;
            for (uint256 i; i < buyers.length; ++i) {
                uint256 roll = _outcome(word, buyers[i], index);
                if (roll < 50 || roll >= 90) { all = false; break; }
            }
            if (all) return word;
        }
        revert("no common DGNRS word found");
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

    /// @dev The worker owns the checkpoint: bound each mineFlip's gas and verify the emitted FIFO
    ///      transcript across all checkpoints.
    function _openAll(uint48 index, uint256 word, address[] memory buyers, uint256 amount)
        private returns (uint256[] memory paid, uint256 swept)
    {
        RecyclingState.seedWord(address(game), index, bytes32(word));
        // These payout fixtures buy presale boxes only: there is no ticket producer to drain.
        // Explicitly model the completed producer prerequisite before entering the human stage.
        uint256 flags = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32(flags | (uint256(1) << 192)));
        vm.recordLogs();
        uint256 opened;
        for (uint256 calls; opened < buyers.length && calls < 100; ++calls) {
            game.mineFlip{gas: 8_000_000}();
            uint256 consumed = _consumed(index, buyers);
            assertGt(consumed, opened, "ready FIFO sweep advances");
            opened = consumed;
        }
        assertEq(opened, buyers.length, "every queued buyer opened exactly once");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        paid = new uint256[](buyers.length);
        uint256 cursor;
        bool sawSweep;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == OPENED) {
                assertLt(cursor, buyers.length, "no duplicate resolution");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), buyers[cursor], "FIFO recipient");
                assertEq(uint256(logs[i].topics[2]), index, "one immutable session identity");
                (uint256 resolved,, uint256 dgnrsPaid,, bool closing,,) = abi.decode(
                    logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32)
                );
                assertEq(resolved, amount, "buy amount preserved");
                if (closing) assertEq(cursor, buyers.length - 1, "closing buyer is last");
                paid[cursor++] = dgnrsPaid;
            } else if (logs[i].topics[0] == SWEPT) {
                assertEq(cursor, buyers.length, "sweep follows every resolution");
                assertFalse(sawSweep, "remainder swept once");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), buyers[buyers.length - 1]);
                swept = abi.decode(logs[i].data, (uint256));
                sawSweep = true;
            }
        }
        assertEq(cursor, buyers.length, "one result per queued buyer");
        for (uint256 i; i < buyers.length; ++i) {
            assertEq(_boxRecord(index, buyers[i]), 0, "record consumed");
            assertEq(sdgnrs.balanceOf(buyers[i]), paid[i] + (i == buyers.length - 1 ? swept : 0), "credits match result");
        }
        // Replay probe: whatever the engine does next (or NoWork / a pending word), it pays no record twice.
        vm.recordLogs();
        (bool replayed,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
        replayed;
        Vm.Log[] memory replay = vm.getRecordedLogs();
        for (uint256 i; i < replay.length; ++i) {
            assertFalse(replay[i].emitter == address(game) && replay[i].topics.length != 0
                && replay[i].topics[0] == OPENED, "completed records cannot pay twice");
        }
    }

    function _consumed(uint48 index, address[] memory buyers) private view returns (uint256 n) {
        for (uint256 i; i < buyers.length; ++i) if (_boxRecord(index, buyers[i]) == 0) ++n;
    }

    function test_PFIX03_TierShapePreserved() public {
        uint48 index = RecyclingState.writeBuffer(address(game));
        address[] memory buyers = new address[](2);
        buyers[0] = makeAddr("tier1Buyer");
        buyers[1] = makeAddr("tier5Buyer");
        _buyBox(buyers[0], 1 ether);
        vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(40 ether)));
        _buyBox(buyers[1], 1 ether);
        assertLt(uint96(_boxRecord(index, buyers[0]) >> 96), 10 ether);
        assertGe(uint96(_boxRecord(index, buyers[1]) >> 96), 40 ether);
        uint256 start = _poolBal();
        (uint256[] memory paid, uint256 swept) = _openAll(index, _allDgnrsWord(buyers, index), buyers, 1 ether);
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
        address[] memory buyers = new address[](7);
        for (uint256 i; i < buyers.length; ++i) {
            buyers[i] = makeAddr(string(abi.encodePacked("clampBuyer", vm.toString(i))));
            if (i == 6) vm.store(address(game), bytes32(SLOT_PRESALE_BOX_ETH_SOLD), bytes32(uint256(45 ether)));
            _buyBox(buyers[i], 5 ether);
        }
        assertEq(_boxRecord(index, buyers[6]) >> 255, 1, "final box closes sale");
        uint256 start = 100_000 ether;
        uint256 excess = _poolBal() - start;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.PresaleBox, address(0xDEAD), excess);
        (uint256[] memory paid, uint256 swept) = _openAll(index, _allDgnrsWord(buyers, index), buyers, 5 ether);
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
        assertLe(paid[6] + swept, 1, "closing roll plus sweep <= 1 wei dust");
        assertLe(_poolBal(), 1, "pool ~0 after closing box");
        assertEq(remaining - swept, _poolBal(), "pool conservation");
    }

    function test_PFIX02_RealisticRun_ClosingSweepIsDust() public {
        uint48 index = RecyclingState.writeBuffer(address(game));
        address[] memory buyers = new address[](250);
        assertEq(buyers.length * 0.2 ether, PRESALE_BOX_ETH_CAP);
        for (uint256 i; i < buyers.length; ++i) {
            buyers[i] = makeAddr(string(abi.encodePacked("runBuyer", vm.toString(i))));
            _buyBox(buyers[i], 0.2 ether);
        }
        assertEq(_boxRecord(index, buyers[249]) >> 255, 1, "final box closes sale");
        uint256 start = _poolBal();
        // Fixed words produce the full 50/40/10 distribution naturally; never choose a
        // fresh word per player or search using the reward assertions under test.
        uint256 word = index == 0 ? 4 : 6;
        uint256 branches;
        (uint256[] memory paid, uint256 swept) = _openAll(index, word, buyers, 0.2 ether);
        uint256 remaining = start;
        uint256 cumulative;
        for (uint256 i; i < buyers.length; ++i) {
            uint256 roll = _outcome(word, buyers[i], index);
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
        assertGe(_outcome(word, buyers[249], index), 90, "closer is the WWXRP branch");
        assertEq(paid[249], 0, "closing WWXRP branch draws no DGNRS");
        assertLe(swept, start / 100, "closing sweep <= poolStart/100");
        assertLe(_poolBal(), start / 100, "residual pool <= poolStart/100 after close");
        assertGe(cumulative * 100, start * 90, "per-box cumulative DGNRS draw >= 90% of poolStart");
        assertEq(remaining - swept, _poolBal(), "pool conservation");
    }
}
