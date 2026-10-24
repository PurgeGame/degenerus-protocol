// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisDeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Former gap-packing regressions: only requested logical rounds can settle.
///         Packed boundary, duplicate settlement and raw-bit independence remain covered.
contract CoinflipCompactGapTest is DegenesisDeployProtocol {
    function setUp() public { _deployProtocol(); }

    function _request(uint24 day) private {
        vm.prank(ContractAddresses.GAME);
        coinflip.onDailyRequest(day);
    }

    function _settle(uint24 day, uint256 word) private {
        vm.prank(ContractAddresses.GAME);
        coinflip.processCoinflipPayouts(0, word, day);
    }

    function test_CalendarGapCreatesNoResultsOrEmission() public {
        _request(2);
        uint256 pool = coinflip.recordPool();
        vm.warp(block.timestamp + 8 days);
        assertEq(coinflip.requestedDailyIdx(), 2);
        for (uint24 day = 1; day <= 10; ++day) {
            (uint16 reward,) = coinflip.getCoinflipDayResult(day);
            assertEq(reward, 0);
        }
        _settle(2, 777);
        assertEq(coinflip.recordPool(), pool + 2_000);
        for (uint24 day = 3; day <= 10; ++day) {
            (uint16 reward,) = coinflip.getCoinflipDayResult(day);
            assertEq(reward, 0);
        }
    }

    function testFuzz_SequentialResultsCrossPackedBoundaries(uint256 root) public {
        for (uint24 day = 2; day <= 65; ++day) {
            _request(day);
            uint256 word = uint256(keccak256(abi.encode(root, day)));
            _settle(day, word);
            (, bool win) = coinflip.getCoinflipDayResult(day);
            assertEq(win, word & 1 != 0);
            if (day > 2) {
                (, bool previous) = coinflip.getCoinflipDayResult(day - 1);
                assertEq(previous, uint256(keccak256(abi.encode(root, day - 1))) & 1 != 0);
            }
        }
        (uint16 untouched,) = coinflip.getCoinflipDayResult(66);
        assertEq(untouched, 0);
    }

    function test_DuplicateSettlementCannotPayOrFundTwice() public {
        _request(2);
        _settle(2, 777);
        uint256 pool = coinflip.recordPool();
        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(2);
        vm.recordLogs();
        _settle(2, 888);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(coinflip.recordPool(), pool);
        (uint16 afterReward, bool afterWin) = coinflip.getCoinflipDayResult(2);
        assertEq(afterReward, reward);
        assertEq(afterWin, win);
    }

    function test_RequestHookIsSequentialAndGameOnly() public {
        vm.expectRevert();
        coinflip.onDailyRequest(2);
        _request(3);
        assertEq(coinflip.requestedDailyIdx(), 1);
        _request(2);
        _request(2);
        assertEq(coinflip.requestedDailyIdx(), 2);
    }
}
