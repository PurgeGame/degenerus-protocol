// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract PeripheralReuseTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    uint32 private id;

    function setUp() public {
        _deployProtocol();
        id = _giveWalletId(ALICE);
    }
    function _map(uint256 key, uint256 root) private pure returns (bytes32) {
        return keccak256(abi.encode(key, root));
    }
    function _level(uint24 lvl) private {
        uint256 word = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32((word & ~(uint256(type(uint24).max) << 96)) | (uint256(lvl) << 96)));
    }
    function _incin(uint24 level_, uint256 amount) private {
        _level(level_);
        vm.prank(address(game)); wwxrp.creditPrize(id, amount);
        vm.prank(ALICE); wwxrp.enter(0, amount);
    }

    function testIncineratorTagCountAndWholeWordReplacement() public {
        _incin(99, 100);
        _incin(99, 200);
        bytes32 slot = _map(0, 7);
        vm.store(address(wwxrp), slot, bytes32(type(uint256).max));
        _incin(199, 25);
        (uint256 total, uint32 count) = wwxrp.incineratorInfo(200);
        assertEq(total, 25); assertEq(count, 1);
        (uint32 owner, uint256 score) = wwxrp.incineratorEntryAt(200, 0);
        assertEq(owner, id); assertEq(score, 25);
        assertEq(uint256(vm.load(address(wwxrp), slot)), (uint256(id) << 192) | 25, "complete interval reset");
        (total, count) = wwxrp.incineratorInfo(100);
        assertEq(total, 0); assertEq(count, 0);
        (owner, score) = wwxrp.incineratorEntryAt(100, 0);
        assertEq(owner, 0); assertEq(score, 0);
        (owner, score) = wwxrp.incineratorEntryAt(200, 1);
        assertEq(owner, 0); assertEq(score, 0, "old tail excluded");
        vm.prank(address(game)); assertEq(wwxrp.resolveIncinerator(100, 3), 0);
    }

    function testGnrWeightTagReplacesOldLevelAndPoisonedHighBits() public {
        vm.store(address(gnrus), bytes32(uint256(4)), bytes32(uint256(uint160(address(0xCAFE)))));
        vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.balanceOf.selector, ALICE), abi.encode(uint256(100e12)));
        bytes32 slot = _map(0, 25);
        vm.store(address(gnrus), slot, bytes32(type(uint256).max));
        uint24 lvl = gnrus.currentLevel();
        assertEq(gnrus.slotApproveWeight(lvl, 0), 0);
        vm.prank(ALICE); gnrus.vote(0);
        assertEq(gnrus.slotApproveWeight(lvl, 0), 100);
        assertEq(uint256(vm.load(address(gnrus), slot)), (uint256(lvl) << 232) | 100);
        vm.store(address(gnrus), bytes32(uint256(2)), bytes32(uint256(lvl + 1)));
        vm.prank(ALICE); gnrus.vote(0);
        assertEq(gnrus.slotApproveWeight(lvl, 0), 0);
        assertEq(gnrus.slotApproveWeight(lvl + 1, 0), 100);
    }

    function testAffiliateTaggedBankDiscardsEveryStaleField() public {
        bytes32 code = bytes32("ALICE");
        vm.prank(ALICE); affiliate.createAffiliateCode(code, 0);
        bytes32 slot = _map(1, 3);
        vm.store(address(affiliate), slot, bytes32(type(uint256).max));
        assertEq(affiliate.totalAffiliateScore(5), 0);
        vm.prank(address(game)); affiliate.payAffiliate(1_000, code, 456, 5, true, 0);
        assertEq(affiliate.totalAffiliateScore(5), 200);
        (uint32 top, uint96 score) = affiliate.affiliateTop(5);
        assertEq(top, id); assertEq(score, 200);
        assertEq(uint256(vm.load(address(affiliate), slot)), (uint256(5) << 232) | (uint256(id) << 163) | (uint256(200) << 128) | 200);
        vm.prank(address(game)); affiliate.payAffiliate(500, code, 456, 9, true, 0);
        assertEq(affiliate.totalAffiliateScore(5), 0);
        (top, score) = affiliate.affiliateTop(5);
        assertEq(top, 0); assertEq(score, 0);
        assertEq(affiliate.totalAffiliateScore(9), 100);
    }

    function testBafBoardTagsAndBothWordResets() public {
        for (uint32 i; i < 4; ++i) {
            vm.prank(address(coinflip)); jackpots.recordBafFlip(id + i, 10, 100 - i);
        }
        uint256 base = uint256(_map(1, 1));
        vm.store(address(jackpots), bytes32(base), bytes32(type(uint256).max));
        vm.store(address(jackpots), bytes32(base + 1), bytes32(type(uint256).max));
        vm.prank(address(coinflip)); jackpots.recordBafFlip(id, 50, 25);
        assertEq(jackpots.bafHeadWinner(10, 0, 0), 0, "old tag is empty");
        assertEq(jackpots.bafHeadWinner(50, 0, 0), id);
        assertEq(uint256(vm.load(address(jackpots), bytes32(base))), (uint256(id) << 96) | 25, "first word overwritten");
        vm.prank(address(coinflip)); jackpots.recordBafFlip(id + 1, 50, 20);
        vm.prank(address(coinflip)); jackpots.recordBafFlip(id + 2, 50, 15);
        assertEq(uint256(vm.load(address(jackpots), bytes32(base + 1))), (uint256(id + 2) << 96) | 15, "second word overwritten");
    }

    function testBafDrawUsesOneBankAndRejectsOldDayAndTail() public {
        uint24 day = game.currentDayView() + 1;
        vm.prank(address(game)); coin.mintForGame(ALICE, 1_000);
        vm.prank(address(game)); coinflip.armBafDraw(day);
        vm.prank(ALICE); coinflip.depositCoinflip(0, 100);
        vm.prank(ALICE); coinflip.depositCoinflip(0, 200);
        bytes32 slot = _map(0, 8);
        vm.store(address(coinflip), slot, bytes32(type(uint256).max));
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(game)); coinflip.armBafDraw(day + 1);
        vm.prank(ALICE); coinflip.depositCoinflip(0, 100);
        (uint32 owner, uint96 total) = coinflip.bafDrawEntryAt(day + 1, 0);
        assertEq(owner, id); assertEq(total, 100);
        assertEq(uint256(vm.load(address(coinflip), slot)), (uint256(id) << 96) | 100);
        (owner, total) = coinflip.bafDrawEntryAt(day, 0);
        assertEq(owner, 0); assertEq(total, 0);
        (owner, total) = coinflip.bafDrawEntryAt(day + 1, 1);
        assertEq(owner, 0); assertEq(total, 0);
    }

    function testWwxrpBalanceRetainsSentinelAndDayBitmapBoundaries() public {
        bytes32 slot = _map(id, 10);
        vm.prank(address(game)); wwxrp.creditPrize(id, 99);
        assertEq(uint256(vm.load(address(wwxrp), slot)), 100);
        vm.prank(ALICE); wwxrp.withdraw(0, 0);
        assertEq(wwxrp.claimable(id), 0);
        assertEq(uint256(vm.load(address(wwxrp), slot)), 1);
        vm.store(address(wwxrp), _map(0, 5), bytes32(uint256(1) << 255));
        vm.store(address(wwxrp), _map(1, 5), bytes32(uint256(1)));
        assertFalse(wwxrp.dayClaimed(254)); assertTrue(wwxrp.dayClaimed(255));
        assertTrue(wwxrp.dayClaimed(256)); assertFalse(wwxrp.dayClaimed(257));
    }
}
