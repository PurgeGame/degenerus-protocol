// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @title WardenLbxClosingBoxOrder -- the closing presale box cannot front-run its cohort
/// @notice `openBox` is permissionless per (player, index), so the closing buyer can open before
///         the same-index cohort. The Pool.PresaleBox remainder is paid by the sweep's drain latch
///         once every presale box has drawn, never at the closing box's own open: the cohort's
///         DGNRS is identical under both open orders and the closer takes only the residue.
contract WardenLbxClosingBoxOrder is DeployProtocol {
    uint256 constant SLOT_PRESALE_BOX_ETH_SOLD = 16;
    uint256 constant SLOT_PRESALE_BOX_CREDIT = 17;
    uint256 constant SLOT_PRESALE_BOX_ETH = 18;
    uint256 constant SLOT_LOOTBOX_RNG_PACKED = 33;
    uint256 constant SLOT_LOOTBOX_RNG_WORD = 34;
    uint256 constant PRESALE_BOX_ETH_CAP = 50 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _poolBal() internal view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool.PresaleBox);
    }

    function _lrIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED))) & 0xFFFFFFFFFFFF);
    }

    function _boxRecord(uint48 index, address player) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(SLOT_PRESALE_BOX_ETH)));
        return uint256(vm.load(address(game), keccak256(abi.encode(player, inner))));
    }

    function _setRngWord(uint48 index, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(index), uint256(SLOT_LOOTBOX_RNG_WORD))), bytes32(word));
    }

    function _setPoolBalanceTo(uint256 target) internal {
        uint256 cur = _poolBal();
        if (cur <= target) return;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.PresaleBox, address(0xDEAD), cur - target);
    }

    function _outcome(uint256 rngWord, address player, uint256 amount) internal pure returns (uint256) {
        return uint16(uint256(keccak256(abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)))) % 100;
    }

    function _buyBox(address buyer, uint256 amount) internal returns (uint48 index) {
        vm.store(address(game), keccak256(abi.encode(buyer, uint256(SLOT_PRESALE_BOX_CREDIT))), bytes32(amount));
        vm.deal(buyer, amount);
        index = _lrIndex();
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(buyer, amount);
    }

    function test_ClosingBoxOpenOrderCannotMoveCohortDgnrs() public {
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
                uint256 o = _outcome(word, v[i], amount);
                if (o < 50 || o >= 90) { all = false; break; }
            }
            if (all) break;
        }
        _setRngWord(index, word);

        // Cohort first, closing box last: every DGNRS-branch victim is paid off the pool and the
        // closing open pays only its own roll.
        uint256 snap = vm.snapshotState();
        uint256[3] memory designDgnrs;
        for (uint256 i; i < 3; ++i) {
            game.openBox(v[i], index);
            designDgnrs[i] = sdgnrs.balanceOf(v[i]);
            assertGt(designDgnrs[i], 0, "cohort-first: DGNRS-branch victim is paid");
        }
        game.openBox(closer, index);
        uint256 closerRoll = sdgnrs.balanceOf(closer);
        uint256 remainder = _poolBal();
        assertGt(remainder, 0, "the closing open leaves the remainder in the pool");
        assertLt(closerRoll, pool / 2, "the closing open never takes the pool");
        vm.revertToState(snap);

        // Closing box opened first (permissionless openBox), same word: the cohort draws the same
        // DGNRS and the closer's open pays the same roll.
        game.openBox(closer, index);
        assertEq(sdgnrs.balanceOf(closer), closerRoll, "closer-first: the open pays the roll alone");
        for (uint256 i; i < 3; ++i) {
            game.openBox(v[i], index);
            assertEq(sdgnrs.balanceOf(v[i]), designDgnrs[i], "closer-first: cohort DGNRS unchanged");
        }
        assertEq(_poolBal(), remainder, "remainder is order-independent");

        // The remainder reaches the closer only once the in-order sweep drains presale: advance
        // LR_INDEX so the index is finalized, then let the sweep walk past the close index.
        for (uint48 i = 1; i < index; ++i) _setRngWord(i, word);
        uint256 lr = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED)));
        vm.store(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED), bytes32(lr + 1));
        uint256 opened = game.openBoxes(1_000_000);
        assertEq(opened, 0, "every record at the index was already opened by hand");
        assertEq(_poolBal(), 0, "the drain latch sweeps the remainder");
        assertEq(sdgnrs.balanceOf(closer), closerRoll + remainder, "remainder paid to the closer at the drain");
        emit log_named_uint("closer roll (wei)", closerRoll);
        emit log_named_uint("remainder swept at drain (wei)", remainder);
    }
}
