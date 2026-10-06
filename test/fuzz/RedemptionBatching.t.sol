// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";
import {AutomaticRedemptionSettlementTest} from "./AutomaticRedemptionSettlement.t.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

contract RedemptionBatchGameSeeder is DegenerusGame {
    /// @dev Seal the write buffer (its box and bet counts latch into the read counts) and publish
    ///      `word` for it.
    function commitWriteWord(uint256 word) external {
        _swapRngBuffers();
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        rngLockedFlag = false;
        humanReadComplete = boxReadCount == 0 && degeneretteReadCount == 0;
    }
    /// @dev The read buffer's entry at `position`: its boxes still owed (zero once the cursor has
    ///      passed it), the cursor and the completion flag.
    function boxState(uint256 position) external view returns (uint256 count, uint256 cursor, bool complete) {
        count = position < boxCursor ? 0 : _boxEntryCount(_boxEntryAt(_rngReadBuffer(), position));
        return (count, boxCursor, humanReadComplete);
    }
}

contract RedemptionBatchingTest is AutomaticRedemptionSettlementTest {
    address private keeper = address(0xC4A123);
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");

    /// @dev The miner's one reward clock: the later of the latest VRF request (slot-0
    ///      rngRequestTime) and the day reset.
    function _rewardElapsed() private view returns (uint256) {
        uint256 ts = vm.getBlockTimestamp();
        uint256 due = uint48(uint256(vm.load(address(game), bytes32(0))) >> 48);
        uint256 reset = ts - (ts - 82_620) % 1 days;
        if (reset > due) due = reset;
        return ts > due ? ts - due : 0;
    }

    /// @dev The smallest allowance (100k steps, up to `ceiling`) with which the next keeper call
    ///      succeeds: the measured admission boundary of the next indivisible chunk. Probed on
    ///      snapshots; the state is left unchanged.
    function _boundaryAllowance(uint256 ceiling) private returns (uint256 g) {
        uint256 snap = vm.snapshotState();
        for (g = 1_000_000; g <= ceiling; g += 100_000) {
            vm.prank(keeper);
            try game.mineFlip{gas: g}() {
                assertTrue(vm.revertToState(snap));
                return g;
            } catch {
                assertTrue(vm.revertToState(snap));
            }
        }
        revert("harness: no allowance up to the ceiling progresses");
    }

    /// @dev One keeper call through the router: the keeper's only credit is the Game's measured-gas
    ///      reward (no per-claim or per-box bounty rides along), priced exactly by the engine formula
    ///      (gas above the unpaid first 1M, capped base fee, delay ladder, no pass, no lock). Returns
    ///      the credited reward and the call's measured execution gas.
    function _keeperMine(uint256 gasLimit) private returns (uint256 reward, uint256 used) {
        uint256 rewardPrice = game.mintPrice();
        uint256 elapsed = _rewardElapsed();
        bool lockedAtStart = game.rngLocked();
        uint256 prior = coinflip.coinflipAmount(keeper);
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip{gas: gasLimit}();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 credits;
        uint256 works;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (, uint256 measured, uint256 paid) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                uint256 step = elapsed / 30 minutes;
                if (step > 4) step = 4;
                uint256 cap = uint256(0.5 gwei) << step;
                uint256 rate = block.basefee < cap ? block.basefee : cap;
                uint256 expected = measured <= 1_000_000 ? 0
                    : (measured - 1_000_000) * rate * 1000 ether * (3000 + step * 4500) * (lockedAtStart ? 2 : 1)
                        / (rewardPrice * 10_000);
                // Whole-FLIP normalization at the payment site: positive sub-FLIP pays 1 FLIP.
                if (expected != 0) expected = expected < 1 ether ? 1 : expected / 1 ether;
                assertEq(paid, expected, "reward prices the measured engine gas");
                reward = paid;
                used = measured;
                ++works;
            }
            if (logs[i].emitter == address(coinflip) && logs[i].topics.length > 1
                && logs[i].topics[0] == STAKE_UPDATED && logs[i].topics[1] == bytes32(uint256(uint160(keeper)))) {
                ++credits;
            }
        }
        assertEq(works, 1, "one measured miner call");
        assertEq(credits, reward == 0 ? 0 : 1, "exactly one keeper credit");
        assertEq(coinflip.coinflipAmount(keeper) - prior, reward, "keeper credited exactly the engine reward");
    }

    function _drain(uint256 allowance) private returns (bool done, uint256 charged, uint256 quote) {
        vm.prank(address(game));
        uint256 before = gasleft();
        MineFlipGas.Result memory result = sdgnrs.runRedemptionWork(settlementWord, allowance);
        return (result.done, before - gasleft(), result.rewardBasis);
    }
    function _newBurners(uint256 n, uint256 amount) internal returns (address[] memory players) {
        players = new address[](n);
        for (uint256 i; i < n; ++i) {
            players[i] = address(uint160(0xBA7000 + i));
            _giveWalletId(players[i]); // a burn needs the beneficiary's wallet ID
            vm.prank(address(game));
            assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, players[i], amount), amount);
            _burn(players[i], amount);
        }
    }
    function _commitWord(uint256 word) private {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(RedemptionBatchGameSeeder).runtimeCode);
        RedemptionBatchGameSeeder(payable(address(game))).commitWriteWord(word);
        vm.etch(address(game), real);
    }
    function _boxState(uint256 position) private returns (uint256 count, uint256 cursor, bool complete) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(RedemptionBatchGameSeeder).runtimeCode);
        (count, cursor, complete) = RedemptionBatchGameSeeder(payable(address(game))).boxState(position);
        vm.etch(address(game), real);
    }
    /// @dev One entry of `count` small boxes; returns its position in the write buffer.
    function _buyHuman(address buyer, uint256 count) private returns (uint256 position) {
        position = RecyclingState.boxCount(address(game), RecyclingState.writeBuffer(address(game)));
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(buyer, price * count);
        vm.prank(buyer);
        game.purchase{value: price * count}(buyer, 0, BoxOrderLib.boSmalls(count), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function test_MoreThanOneBeneficiarySettlesWithExactExistingBounty() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        (bool done, uint256 charged, uint256 quote) = _drain(9_000_000);
        assertTrue(done);
        assertLe(charged, 9_000_000);
        assertEq(quote, 0, "measured miner gas is the sole bounty");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        (done, charged, quote) = _drain(9_000_000);
        assertTrue(done); assertLt(charged, 100_000); assertEq(quote, 0);
    }
    function test_MaximumNextBeneficiaryWaitsWholeAndThenCompletes() public {
        uint32 day = _openBatchId();
        address[] memory players = _newBurners(3, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        (uint128 thirdExpected,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[2]), day);
        // Two maximum beneficiaries fit 4M; the third's whole admission then does not.
        uint256 allowance = _oneClaimAllowance();
        (bool done, uint256 charged, uint256 quote) = _drain(allowance);
        assertFalse(done); assertLe(charged, 4_000_000);
        (uint128 first,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[0]), day);
        (uint128 second,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[1]), day);
        (uint128 third,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[2]), day);
        assertEq(first, 0); assertGt(second, 0); assertEq(third, thirdExpected); assertGt(third, 0);
        uint256 beforeReserve = sdgnrs.pendingRedemptionEthValue();
        (done, charged,) = _drain(1_000_000);
        assertFalse(done); assertLt(charged, 100_000); assertEq(sdgnrs.pendingRedemptionEthValue(), beforeReserve);
        (done, charged, quote) = _drain(9_000_000);
        assertTrue(done); assertLe(charged, 9_000_000); assertEq(quote, 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_ZeroValueClaimsStillNeedWholeClaimAdmission() public {
        uint32 day = _openBatchId();
        vm.deal(address(sdgnrs), 0);
        address[] memory players = _newBurners(3, 1 ether);
        _resolve(day, 100, 99);
        (bool done,,uint256 quote) = _drain(150_000);
        assertFalse(done); assertEq(quote, 0);
        assertEq(_claimTokens(players[0], day), 1 ether);
        (done,,quote) = _drain(9_000_000);
        assertTrue(done); assertEq(quote, 0);
        for (uint256 i; i < players.length; ++i) assertEq(_claimTokens(players[i], day), 0);
    }

    function test_EscrowUsesBatchSyntheticResultWithoutDailyResultRead() public {
        uint32 day = _openBatchId();
        vm.deal(address(sdgnrs), 0);
        _seedFlipBacking(1_000_000);
        address[] memory players = _newBurners(3, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        (uint128 tokens,,,uint96 escrow,,uint16 reward) = sdgnrs.redemptionBatches(day);
        assertGt(escrow, 0);
        vm.mockCallRevert(address(coinflip), abi.encodeWithSelector(coinflip.getCoinflipDayResult.selector),
            abi.encodeWithSignature("Error(string)", "redemption must use synthetic flip"));
        uint256[] memory expected = new uint256[](players.length);
        for (uint256 i; i < players.length; ++i) {
            uint256 share = uint256(escrow) * _claimTokens(players[i], day) / tokens;
            expected[i] = coinflip.coinflipAmount(players[i]) + (reward == 0 ? 0 : share + share * reward / 100);
        }
        (bool done,,uint256 quote) = _drain(9_000_000);
        assertTrue(done); assertEq(quote, 0);
        for (uint256 i; i < players.length; ++i) {
            assertEq(coinflip.coinflipAmount(players[i]), expected[i]);
            assertEq(_claimTokens(players[i], day), 0);
        }
    }

    function test_CachedEscrowRewardCannotBeSuppliedByAnExternalCaller() public {
        uint32 day = _openBatchId();
        uint32 aliceId = game.walletIdOf(alice);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.settleRedemptionHead(alice, aliceId, day, 99);
    }

    function test_PerClaimStepsAndOneCallPlayerEventsAndBalancesAreIdentical() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, 1 ether); // Dust-forfeit branch alongside a real chunk.
        _resolve(day, 175, 99);
        uint256 snap = vm.snapshotState();
        // Probe both step allowances first, so the recording holds only the applied steps.
        uint256 first = _oneClaimAllowance();
        _settleClaimAt(first);
        uint256 second = _oneClaimAllowance();
        assertTrue(vm.revertToState(snap));
        snap = vm.snapshotState();
        vm.recordLogs();
        _settleClaimAt(first); _settleClaimAt(second);
        assertFalse(sdgnrs.redemptionSettlementPending());
        bytes32 stepLogs = keccak256(abi.encode(vm.getRecordedLogs()));
        bytes32 stepBalances = keccak256(abi.encode(game.claimableWinningsOf(alice), game.claimableWinningsOf(bob),
            game.futurePrizePoolView(), address(sdgnrs).balance, sdgnrs.pendingRedemptionEthValue()));
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        (bool done,,) = _drain(9_000_000);
        assertTrue(done);
        assertEq(keccak256(abi.encode(vm.getRecordedLogs())), stepLogs, "ordered player settlement and queue events");
        assertEq(keccak256(abi.encode(game.claimableWinningsOf(alice), game.claimableWinningsOf(bob),
            game.futurePrizePoolView(), address(sdgnrs).balance, sdgnrs.pendingRedemptionEthValue())), stepBalances);
    }
    // Pins coinflip.creditFlip in the router: external keeper gets the exact single credit.
    // The miner pays measured gas above each call's unpaid first 1M at the capped base fee, so the
    // fixture settles real lootbox claims (above that threshold) at a nonzero base fee.
    function test_MineFlipPaysExternalKeeperOnceAndNoBoxesStillCommits() public {
        vm.fee(1 gwei);
        uint32 day = _openBatchId();
        _newBurners(2, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);

        (uint256 reward, uint256 used) = _keeperMine(10_000_000);
        emit log_named_uint("redemption_drain_miner_execution_gas", used);
        assertGt(reward, 0, "external keeper paid for the redemption drain");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }
    // The miner reward prices measured gas above each call's unpaid first 1M at min(basefee, cap),
    // so at a nonzero base fee the redemptions are cleared by calls held inside that first 1M
    // (each at the smallest allowance that admits its next chunk) and the keeper is credited nothing.
    function test_LowGasMineClearsRedemptionsWithoutMinerCredit() public {
        vm.fee(1 gwei);
        uint32 day = _openBatchId();
        _burn(alice, 1 ether); _burn(bob, 1 ether);
        _resolve(day, 100, 99); _commitWord(99);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(sdgnrs.redemptionSettlementPending(), "nonvacuity: redemptions await settlement");
        uint256 prior = coinflip.coinflipAmount(keeper);
        uint256 calls;
        for (; calls < 64 && sdgnrs.redemptionSettlementPending(); ++calls) {
            (uint256 reward, uint256 used) = _keeperMine(_minimumAllowance());
            emit log_named_uint("low_gas_call_execution_gas", used);
            assertLe(used, 1_000_000, "each low-gas call stays inside the unpaid first 1M");
            assertEq(reward, 0, "a call inside the unpaid first 1M credits nothing");
        }
        assertGt(calls, 0, "nonvacuity: low-gas calls ran");
        assertEq(coinflip.coinflipAmount(keeper), prior);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    /// @dev Smallest ladder allowance that admits the keeper's next chunk (probed on a snapshot);
    ///      every smaller allowance must be refused with InsufficientExecutionGas.
    function _minimumAllowance() private returns (uint256) {
        uint256[8] memory ladder =
            [uint256(1_000_000), 1_250_000, 1_500_000, 2_000_000, 2_500_000, 3_500_000, 5_000_000, 9_500_000];
        for (uint256 s; s < ladder.length; ++s) {
            uint256 snap = vm.snapshotState();
            vm.prank(keeper);
            (bool ok, bytes memory err) = address(game).call{gas: ladder[s]}(abi.encodeWithSignature("mineFlip()"));
            vm.revertToState(snap);
            if (ok) return ladder[s];
            assertEq(bytes4(err), MineFlipGas.InsufficientExecutionGas.selector, "a short allowance is refused, nothing else");
        }
        revert("no allowance up to 9.5M admits the next chunk");
    }
    function test_RedemptionThenAffordableHumanBoxSharesOneCall() public {
        uint256 pos = _buyHuman(address(0xB0C1), 20);
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000); _resolve(day, 175, 99); _commitWord(99);
        // The keeper is paid only the engine's measured-gas reward for the shared call; the claim
        // and the affordable 20-box order are sized so the call clears the unpaid first 1M
        // whatever their committed rolls draw.
        vm.fee(1 gwei);
        (uint256 reward, uint256 used) = _keeperMine(10_000_000);
        emit log_named_uint("redemption_plus_human_box_miner_execution_gas", used);
        (uint256 count,, bool complete) = _boxState(pos);
        assertEq(count, 0); assertTrue(complete);
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertGt(reward, 0, "keeper paid for the shared call");
    }
    function test_OversizedFirstHumanBoxWaitsAndRedemptionsCommit() public {
        uint256 pos = _buyHuman(address(0xB0C2), 100);
        uint32 day = _openBatchId();
        _newBurners(2, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99); _commitWord(99);
        // At the measured boundary allowance (<= 10M) the call admits one maximum claim; the engine
        // keeps admitting chunks while a larger allowance covers the next declared bound.
        uint256 boundary = _boundaryAllowance(10_000_000);
        emit log_named_uint("maximum_redemption_admission_boundary_allowance", boundary);
        vm.prank(keeper); game.mineFlip{gas: boundary}();
        (uint256 count, uint256 cursor, bool complete) = _boxState(pos);
        assertEq(count, 100); assertEq(cursor, 0); assertFalse(complete);
        assertGt(sdgnrs.pendingRedemptionEthValue(), 0, "next maximum claim retains its reserve");
        assertTrue(sdgnrs.redemptionSettlementPending());
        for (uint256 i; i < 4 && count != 0; ++i) {
            vm.prank(keeper); game.mineFlip{gas: 10_000_000}();
            (count,, complete) = _boxState(pos);
        }
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(count, 0); // Completing this cohort may request its generated next cohort.
    }
    function test_ColdMaximumRedemptionDefersWholeHumanOrderAtMeasuredBoundary() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        uint256 first = _buyHuman(address(0xB0C4), 100);
        uint256 second = _buyHuman(address(0xB0C5), 64);
        _resolve(day, 175, 99); _commitWord(99);
        vm.cool(address(game)); vm.cool(address(sdgnrs)); vm.cool(address(coinflip)); vm.cool(address(mockStETH));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE); vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE); vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE); vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        // At the measured boundary (the smallest allowance admitting the maximum claim, declared
        // 500k plus the bounded human-order cost) the call succeeds and settles the claim, and its remaining allowance
        // cannot admit the next whole 100-box order. The boundary is a realistic allowance (<= 10M).
        uint256 boundary = _boundaryAllowance(10_000_000);
        emit log_named_uint("maximum_redemption_admission_boundary_allowance", boundary);
        vm.prank(keeper);
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: boundary}();
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("cold_maximum_redemption_call_gas_including_intrinsic", used);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        (uint256 count, uint256 cursor,) = _boxState(first);
        assertEq(count, 100, "next indivisible order remains whole"); assertEq(cursor, 0);
        // Both orders fit individually; continuation follows their committed FIFO.
        for (uint256 i; i < 3 && count != 0; ++i) {
            vm.prank(keeper); game.mineFlip{gas: 10_000_000}();
            (count,,) = _boxState(second);
        }
        (count,,) = _boxState(first); assertEq(count, 0);
        (count,,) = _boxState(second); assertEq(count, 0);
    }

    function test_NearBudgetCompletionDefersHumanBoxUntilFreshAllowance() public {
        uint256 pos = _buyHuman(address(0xB0C3), 1);
        uint32 day = _openBatchId();
        address[] memory players = _newBurners(67, 1 ether);
        _resolve(day, 100, 99);
        for (uint256 j; j < 22; ++j) _settleOneClaim();
        (uint128 settled,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[21]), day);
        (uint128 next,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[22]), day);
        assertEq(settled, 0, "harness: the first 22 claims settled in FIFO order");
        assertGt(next, 0, "harness: 45 dust claims remain");
        // A caller may fund a safe checkpoint. The remaining physical gas admits
        // the dust claims but cannot admit the next whole human order.
        _commitWord(99);
        uint256 allowance;
        for (allowance = 1_000_000; allowance <= 8_000_000; allowance += 25_000) {
            uint256 snap = vm.snapshotState();
            vm.prank(keeper); try game.mineFlip{gas: allowance}() {} catch {}
            bool done = !sdgnrs.redemptionSettlementPending();
            assertTrue(vm.revertToState(snap));
            if (done) break;
        }
        vm.prank(keeper); game.mineFlip{gas: allowance}();
        assertFalse(sdgnrs.redemptionSettlementPending());
        (uint256 count, uint256 cursor, bool complete) = _boxState(pos);
        assertEq(count, 1); assertEq(cursor, 0); assertFalse(complete);
        vm.prank(keeper); game.mineFlip();
        (count,, complete) = _boxState(pos);
        assertEq(count, 0);
    }

    function test_OversizedFirstBetWaitsAndNextFreshCallSettlesIt() public {
        uint32 day = _openBatchId();
        _newBurners(45, 1 ether);
        game.placeDegeneretteBet{value: 0.125 ether}(bob, 0, 0.005 ether, 25, 0);
        _resolve(day, 100, 99); _commitWord(99);
        uint48 index = RecyclingState.readBuffer(address(game));
        // The smallest allowance that completes the redemption cohort leaves less than the last
        // claim's admission, which is below the whole 25-spin bet's.
        uint256 allowance = 2_000_000;
        for (; allowance < 10_000_000; allowance += 25_000) {
            uint256 snap = vm.snapshotState();
            vm.prank(keeper);
            try game.mineFlip{gas: allowance}() {} catch {}
            bool settled = !sdgnrs.redemptionSettlementPending();
            assertTrue(vm.revertToState(snap));
            if (settled) break;
        }
        vm.prank(keeper); game.mineFlip{gas: allowance}();
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertGt(game.degeneretteBetInfo(index, 1), 0, "remainder cannot fund first whole bet");
        vm.prank(keeper); game.mineFlip();
        assertEq(game.degeneretteBetInfo(index, 1), 0, "fresh allowance resolves deferred bet");
    }
}
