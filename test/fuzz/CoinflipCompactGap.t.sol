// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CoinflipRngSpineBehavioral} from "./CoinflipRngSpineBehavioral.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CoinflipCompactGapTest is CoinflipRngSpineBehavioral {
    function testFuzz_PackedGapMatchesSequentialResultsAndBacking(uint256 root, uint8 length) public {
        uint24 start = 31;
        uint24 end = start + uint24(bound(length, 1, 31));
        uint256 snapshot = vm.snapshotState();
        vm.prank(GAME);
        coinflip.processCoinflipGap(root, start, end);
        uint256 batchedPool = coinflip.recordPool();
        vm.prank(ContractAddresses.SDGNRS);
        uint256 batchedBacking = coinflip.redeemableFlipBacking();
        for (uint24 day = start; day < end; ++day) {
            uint256 word = uint256(keccak256(abi.encodePacked(root, day)));
            if (word == 0) word = 1;
            (uint16 reward, bool win) = coinflip.getCoinflipDayResult(day);
            assertEq(reward, _expectedStoredByte(0, word, day));
            assertEq(win, _expectedWin(word));
        }
        assertTrue(vm.revertToState(snapshot));
        for (uint24 day = start; day < end; ++day) {
            uint256 word = uint256(keccak256(abi.encodePacked(root, day)));
            if (word == 0) word = 1;
            _resolveAndRead(0, word, day);
        }
        assertEq(coinflip.recordPool(), batchedPool);
        vm.prank(ContractAddresses.SDGNRS);
        assertEq(coinflip.redeemableFlipBacking(), batchedBacking);
    }

    function test_GapRetryCannotFundRecordPoolTwice() public {
        vm.prank(GAME);
        coinflip.processCoinflipGap(99, 31, 62);
        uint256 pool = coinflip.recordPool();
        vm.prank(GAME);
        coinflip.processCoinflipGap(99, 31, 62);
        assertEq(coinflip.recordPool(), pool);
    }

    function test_GapKeepsNeighboringPackedResults() public {
        _resolveAndRead(2, 555, 30);
        (uint16 beforeReward, bool beforeWin) = coinflip.getCoinflipDayResult(30);
        vm.prank(GAME);
        coinflip.processCoinflipGap(99, 31, 62);
        (uint16 afterReward, bool afterWin) = coinflip.getCoinflipDayResult(30);
        assertEq(afterReward, beforeReward);
        assertEq(afterWin, beforeWin);
        (uint16 unavailable, ) = coinflip.getCoinflipDayResult(62);
        assertEq(unavailable, 0);
    }
}
