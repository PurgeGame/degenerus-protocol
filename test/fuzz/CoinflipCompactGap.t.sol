// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CoinflipRngSpineBehavioral} from "./CoinflipRngSpineBehavioral.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameRngUtils} from "../../contracts/modules/DegenerusGameRngUtils.sol";

contract CoinflipGapRecoveryHarness is DegenerusGameRngUtils {
    function recover(uint256 root, uint24 start, uint24 end) external {
        _backfillGapDays(root, start, end);
    }
}

contract CoinflipCompactGapTest is CoinflipRngSpineBehavioral {
    uint24 private constant GAP_START = 31;
    uint24 private constant GAP_END = 62;
    uint256 private constant ALL_GAP_WINS = 0xfffffffe;

    function _gap(uint256 root, uint24 start, uint24 end) private {
        vm.prank(GAME);
        coinflip.processCoinflipGap(root, start, end);
    }

    function _backing() private returns (uint256) {
        vm.prank(ContractAddresses.SDGNRS);
        return coinflip.redeemableFlipBacking();
    }

    function _assertGap(uint256 root, uint24 originalStart, uint24 end) private view {
        for (uint24 day = originalStart; day < end; ++day) {
            bool expectedWin = (root >> (1 + day - originalStart)) & 1 != 0;
            (uint16 reward, bool win) = coinflip.getCoinflipDayResult(day);
            assertEq(win, expectedWin, "gap win follows its original root bit");
            assertEq(reward, expectedWin ? 100 : 1, "backfill is double or nothing; loss keeps sentinel");
        }
    }

    function testFuzz_PackedGapMatchesSequentialResultsAndBacking(uint256 root, uint8 length) public {
        uint24 end = GAP_START + uint24(bound(length, 1, 31));
        uint256 snapshot = vm.snapshotState();
        _gap(root, GAP_START, end);
        uint256 batchedPool = coinflip.recordPool();
        uint256 batchedBacking = _backing();
        _assertGap(root, GAP_START, end);
        assertTrue(vm.revertToState(snapshot));
        for (uint24 day = GAP_START; day < end; ++day) {
            // Keep the original start while each call clamps the already settled prefix.
            _gap(root, GAP_START, day + 1);
        }
        _assertGap(root, GAP_START, end);
        assertEq(coinflip.recordPool(), batchedPool, "same daily pool funding");
        assertEq(_backing(), batchedBacking, "same sequential backing settlement");
    }

    function test_AllZeroAllOneAndAlternatingBitsCrossPackedBoundary() public {
        uint256[3] memory roots = [uint256(0), type(uint256).max, uint256(0xaaaaaaaa)];
        for (uint256 i; i < roots.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            _gap(roots[i], GAP_START, GAP_END);
            _assertGap(roots[i], GAP_START, GAP_END);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function test_OutsideBitsDoNotChangeGapWinsOrFixedRewards() public {
        uint256 root = 0x9a532fac;
        _gap(root, GAP_START, GAP_END);
        bool[31] memory originalWins;
        for (uint24 day = GAP_START; day < GAP_END; ++day) {
            (, originalWins[day - GAP_START]) = coinflip.getCoinflipDayResult(day);
        }
        // A fresh disjoint range has the same offsets. Flip bit 0 and every bit
        // above the gap slice; neither outcomes nor fixed reward sizes may change.
        uint256 other = root ^ ~uint256(ALL_GAP_WINS);
        _gap(other, GAP_END, GAP_END + 31);
        _assertGap(other, GAP_END, GAP_END + 31);
        for (uint24 day = GAP_END; day < GAP_END + 31; ++day) {
            (, bool win) = coinflip.getCoinflipDayResult(day);
            assertEq(win, originalWins[day - GAP_END], "only bits 1..31 select gap wins");
        }
    }

    function test_GapRetryCannotFundRecordPoolTwice() public {
        _gap(99, GAP_START, GAP_END);
        uint256 pool = coinflip.recordPool();
        uint256 backing = _backing();
        vm.recordLogs();
        _gap(type(uint256).max, GAP_START, GAP_END);
        assertEq(vm.getRecordedLogs().length, 0, "completed retry emits no settlement");
        assertEq(coinflip.recordPool(), pool);
        assertEq(_backing(), backing);
        _assertGap(99, GAP_START, GAP_END);
    }

    function test_OverlappingPrefixKeepsOriginalBitOffsets() public {
        uint256 root = 0xabcde982;
        _gap(root, GAP_START, GAP_START + 13);
        uint256 prefixPool = coinflip.recordPool();
        _gap(root, GAP_START, GAP_END);
        _assertGap(root, GAP_START, GAP_END);
        assertEq(coinflip.recordPool(), prefixPool + 18 * 2_000 ether, "only remaining days fund the pool");
    }

    function test_GapKeepsNeighboringPackedResults() public {
        _resolveAndRead(2, 555, GAP_START - 1);
        (uint16 beforeReward, bool beforeWin) = coinflip.getCoinflipDayResult(GAP_START - 1);
        _gap(99, GAP_START, GAP_END);
        (uint16 afterReward, bool afterWin) = coinflip.getCoinflipDayResult(GAP_START - 1);
        assertEq(afterReward, beforeReward);
        assertEq(afterWin, beforeWin);
        (uint16 unavailable, ) = coinflip.getCoinflipDayResult(GAP_END);
        assertEq(unavailable, 0, "next packed lane remains unresolved");
        _resolveAndRead(6, 777, GAP_END);
        _assertGap(99, GAP_START, GAP_END);
        (afterReward, afterWin) = coinflip.getCoinflipDayResult(GAP_START - 1);
        assertEq(afterReward, beforeReward, "neighbor resolution preserves earlier packed lanes");
        assertEq(afterWin, beforeWin);
    }

    function test_RecoveryDayStillUsesNormalRandomRewardAndBitZero() public {
        uint256 root = 0x12345;
        while (_expectedReward(0, root, GAP_END) == 100) root += 2;
        _gap(root, GAP_START, GAP_END);
        _assertGap(root, GAP_START, GAP_END);
        (uint16 reward, bool win) = _resolveAndRead(0, root, GAP_END);
        assertTrue(win, "recovery day uses root bit zero");
        assertEq(reward, _expectedReward(0, root, GAP_END), "actual day retains its tagged amount roll");
        assertNotEq(reward, 100, "fixture distinguishes normal roll from fixed backfill amount");
    }

    function test_CompletedOversizedGapRetryDoesNothing() public {
        _resolveAndRead(0, 99, GAP_START + 32);
        uint256 pool = coinflip.recordPool();
        uint256 backing = _backing();
        vm.recordLogs();
        _gap(99, GAP_START, GAP_START + 32);
        assertEq(vm.getRecordedLogs().length, 0, "settled retry performs no work");
        assertEq(coinflip.recordPool(), pool, "settled retry cannot fund again");
        assertEq(_backing(), backing, "settled retry cannot change backing");
    }

    function testFuzz_RecoveryCallerBoundsOversizedGap(uint256 root, uint24 requestedEnd) public {
        requestedEnd = uint24(bound(requestedEnd, GAP_END + 1, type(uint24).max));
        uint256 pool = coinflip.recordPool();
        bytes memory gameCode = GAME.code;
        vm.etch(GAME, type(CoinflipGapRecoveryHarness).runtimeCode);
        CoinflipGapRecoveryHarness(GAME).recover(root, GAP_START, requestedEnd);
        vm.etch(GAME, gameCode);
        _assertGap(root, GAP_START, GAP_END);
        assertEq(coinflip.recordPool(), pool + 31 * 2_000 ether, "recovery settles only its bounded batch");
        (uint16 nextResult,) = coinflip.getCoinflipDayResult(GAP_END);
        assertEq(nextResult, 0, "day beyond recovery batch stays untouched");
    }

    function test_OnlyGameCanSetGapResults() public {
        vm.expectRevert(bytes4(keccak256("OnlyDegenerusGame()")));
        coinflip.processCoinflipGap(99, GAP_START, GAP_END);
    }

    function test_EmptyAndReversedGapsDoNothing() public {
        uint256 pool = coinflip.recordPool();
        _gap(99, GAP_START, GAP_START);
        _gap(99, GAP_END, GAP_START);
        assertEq(coinflip.recordPool(), pool);
        (uint16 result, ) = coinflip.getCoinflipDayResult(GAP_START);
        assertEq(result, 0);
    }

    /// @dev Arm the real sDGNRS rebuy lane, then fund a next-day stake through its
    ///      authorized incoming-credit path. No raw storage fixture or empty balance.
    function _fundGap() private returns (uint256 reserve) {
        for (uint24 day = 1; day < GAP_START; ++day) _resolveAndRead(0, 0, day);
        vm.warp((uint256(GAP_START - 2) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        reserve = _backing();
        vm.prank(ContractAddresses.COIN);
        coinflip.creditSdgnrsBacking(100_000 ether);
        assertEq(coinflip.coinflipAmount(ContractAddresses.SDGNRS), 100_000 ether, "funded gap starts with an actual stake");
        (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        assertTrue(enabled, "sDGNRS rebuy armed before the gap");
    }

    function test_FundedGapMatchesOrdinaryDailySettlement() public {
        uint256 reserve = _fundGap();
        uint256 snapshot = vm.snapshotState();
        _gap(ALL_GAP_WINS, GAP_START, GAP_END);
        uint256 batchPool = coinflip.recordPool();
        uint256 batchBacking = _backing();
        (, , uint256 batchCarry, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        uint256 expectedCarry = 100_000 ether;
        for (uint24 day = GAP_START; day < GAP_END; ++day) {
            uint256 payout = expectedCarry * 2;
            expectedCarry = payout + payout * 75 / 10_000;
        }
        assertEq(batchCarry, expectedCarry, "every win doubles then applies the existing0.75% recycle bonus");
        assertEq(batchBacking, reserve + batchCarry, "seed reserve and rolling winnings are disjoint");
        _assertGap(ALL_GAP_WINS, GAP_START, GAP_END);
        assertTrue(vm.revertToState(snapshot));
        for (uint24 day = GAP_START; day < GAP_END; ++day) {
            // Ordinary settlement independently reaches the same per-day win/reward.
            uint256 word = _wordForExactReward(day, 100, true);
            _resolveAndRead(0, word, day);
        }
        (, , uint256 sequentialCarry, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        assertEq(sequentialCarry, batchCarry, "daily carry rounding and order match");
        assertEq(_backing(), batchBacking, "backing matches ordinary settlements");
        assertEq(coinflip.recordPool(), batchPool, "record pool matches ordinary settlements");
    }

    function test_BackfillManualClaimsPayDoubleOrNothing() public {
        _fundGap();
        address player = makeAddr("backfill_manual_claimant");
        uint256 stake = 100 ether + 7;
        vm.prank(GAME);
        coinflip.creditFlip(player, stake);
        assertEq(coinflip.coinflipAmount(player), stake, "actual funded next-day stake");
        uint256 snapshot = vm.snapshotState();
        _gap(2, GAP_START, GAP_START + 1);
        assertEq(coinflip.previewClaimCoinflips(player), stake * 2);
        uint256 beforeBalance = coin.balanceOf(player);
        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflips(address(0), type(uint256).max);
        assertEq(claimed, stake * 2, "winning backfill returns stake plus100% profit");
        assertEq(coin.balanceOf(player), beforeBalance + stake * 2);
        assertTrue(vm.revertToState(snapshot));
        _gap(0, GAP_START, GAP_START + 1);
        assertEq(coinflip.previewClaimCoinflips(player), 0);
        beforeBalance = coin.balanceOf(player);
        vm.prank(player);
        claimed = coinflip.claimCoinflips(address(0), type(uint256).max);
        assertEq(claimed, 0, "losing backfill forfeits the stake");
        assertEq(coin.balanceOf(player), beforeBalance);
    }

    function test_FundedGapFinalLossClearsPriorWinningCarry() public {
        uint256 reserve = _fundGap();
        uint256 root = ALL_GAP_WINS & ~(uint256(1) << 31);
        _gap(root, GAP_START, GAP_END);
        _assertGap(root, GAP_START, GAP_END);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.SDGNRS);
        assertEq(carry, 0, "last gap bit loses every preceding compounded win");
        assertEq(_backing(), reserve, "only the seed reserve remains");
    }

    function test_Cold31DayFundedGapGas() public {
        _fundGap();
        vm.cool(address(coinflip));
        vm.cool(GAME);
        vm.cool(ContractAddresses.SDGNRS);
        vm.cool(ContractAddresses.COIN);
        vm.prank(GAME);
        uint256 beforeGas = gasleft();
        coinflip.processCoinflipGap(ALL_GAP_WINS, GAP_START, GAP_END);
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("cold funded 31-day gap including intrinsic gas", used);
        assertLt(used, 1_000_000, "bounded cold gap settlement");
        _assertGap(ALL_GAP_WINS, GAP_START, GAP_END);
    }
}
