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
    function commitWriteWord(uint256 word) external {
        _swapRngBuffers();
        _resetLootboxWriteBuffer(_rngWriteBuffer());
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        rngLockedFlag = false;
        humanReadComplete = boxPlayers[_rngReadBuffer()].length == 0 && degeneretteQueue[_rngReadBuffer()].length == 0;
    }
    function boxState(address buyer) external view returns (uint256 count, uint256 cursor, bool complete) {
        return (_boxOrderCount(_boxOrder(_rngReadBuffer(), buyer)), boxCursor, humanReadComplete);
    }
}

contract RedemptionBatchingTest is AutomaticRedemptionSettlementTest {
    address private keeper = address(0xC4A123);
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");

    /// @dev The miner's one reward clock: the later of the last accepted callback and the day reset.
    function _rewardElapsed() private view returns (uint256) {
        uint256 ts = vm.getBlockTimestamp();
        uint256 due = uint48(uint256(vm.load(address(game), bytes32(uint256(33)))));
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
                if (expected != 0) expected = expected < 1 ether ? 1 ether : (expected / 1 ether) * 1 ether;
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
        assertEq(coinflip.coinflipAmount(keeper) - prior, (reward / 1 ether) * 1 ether, "keeper credited exactly the engine reward");
    }

    function _batch(uint256 allowance) private returns (bool done, uint256 charged, uint256 quote) {
        vm.prank(address(game));
        uint256 before = gasleft();
        MineFlipGas.Result memory result = sdgnrs.runRedemptionWork(allowance);
        return (result.done, before - gasleft(), result.rewardBasis);
    }
    function _newBurners(uint256 n, uint256 amount) internal returns (address[] memory players) {
        players = new address[](n);
        for (uint256 i; i < n; ++i) {
            players[i] = address(uint160(0xBA7000 + i));
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
    function _boxState(address buyer) private returns (uint256 count, uint256 cursor, bool complete) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(RedemptionBatchGameSeeder).runtimeCode);
        (count, cursor, complete) = RedemptionBatchGameSeeder(payable(address(game))).boxState(buyer);
        vm.etch(address(game), real);
    }
    function _buyHuman(address buyer, uint256 count) private {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(buyer, price * count);
        vm.prank(buyer);
        game.purchase{value: price * count}(buyer, 0, BoxOrderLib.boSmalls(count), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function test_MoreThanOneBeneficiarySettlesWithExactExistingBounty() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        (bool done, uint256 charged, uint256 quote) = _batch(9_000_000);
        assertTrue(done);
        assertLe(charged, 9_000_000);
        assertEq(quote, 2);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        (done, charged, quote) = _batch(9_000_000);
        assertTrue(done); assertLt(charged, 100_000); assertEq(quote, 0);
    }
    function test_MaximumNextBeneficiaryWaitsWholeAndThenCompletes() public {
        uint24 day = game.currentDayView();
        address[] memory players = _newBurners(3, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        (uint96 thirdExpected,,) = sdgnrs.pendingRedemptions(players[2], day);
        // Two maximum beneficiaries fit 4M; the third's whole admission then does not.
        (bool done, uint256 charged, uint256 quote) = _batch(4_000_000);
        assertFalse(done); assertLe(charged, 4_000_000);
        (uint96 first,,) = sdgnrs.pendingRedemptions(players[0], day);
        (uint96 second,,) = sdgnrs.pendingRedemptions(players[1], day);
        (uint96 third,,) = sdgnrs.pendingRedemptions(players[2], day);
        assertEq(first, 0); assertEq(second, 0); assertEq(third, thirdExpected); assertGt(third, 0);
        uint256 beforeReserve = sdgnrs.pendingRedemptionEthValue();
        (done, charged,) = _batch(1_000_000);
        assertFalse(done); assertLt(charged, 100_000); assertEq(sdgnrs.pendingRedemptionEthValue(), beforeReserve);
        (done, charged, quote) = _batch(9_000_000);
        assertTrue(done); assertLe(charged, 9_000_000); assertEq(quote, 1);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_ManuallyClaimedCohortNeedsOnlyBoundedCleanupWithoutBounty() public {
        uint24 day = game.currentDayView();
        address[] memory players = _newBurners(3, 1 ether);
        _resolve(day, 100, 99);
        for (uint256 i; i < players.length; ++i) sdgnrs.claimRedemption(players[i], day);
        assertTrue(sdgnrs.redemptionSettlementPending(), "keeper cleanup is still owed");
        (bool done, uint256 charged, uint256 quote) = _batch(40_000);
        assertFalse(done); assertLt(charged, 100_000); assertEq(quote, 0);
        assertTrue(sdgnrs.redemptionSettlementPending());
        (done, charged, quote) = _batch(150_000);
        assertTrue(done); assertLt(charged, 150_000); assertEq(quote, 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }
    function test_EscrowOnlySuccessfulClaimReceivesTheExistingClaimBounty() public {
        vm.deal(address(sdgnrs), 0);
        vm.mockCall(address(coinflip), abi.encodeWithSelector(coinflip.redeemableFlipBacking.selector), abi.encode(1000 ether));
        vm.mockCall(address(coinflip), abi.encodeWithSelector(coinflip.withdrawRedeemedFlip.selector), abi.encode());
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        (uint96 base,, uint96 escrow) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(base, 0); assertGt(escrow, 0);
        _resolve(day, 100, 99);
        (bool done,, uint256 quote) = _batch(9_000_000);
        assertTrue(done);
        assertEq(quote, 1);
        (base,, escrow) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(base, 0); assertEq(escrow, 0);
    }

    function test_ManualAndBatchPlayerEventsAndBalancesAreIdentical() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, 1 ether); // Dust-forfeit branch alongside a real chunk.
        _resolve(day, 175, 99);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        sdgnrs.claimRedemption(alice, day); sdgnrs.claimRedemption(bob, day);
        bytes32 manualLogs = keccak256(abi.encode(vm.getRecordedLogs()));
        bytes32 manualBalances = keccak256(abi.encode(game.claimableWinningsOf(alice), game.claimableWinningsOf(bob),
            game.futurePrizePoolView(), address(sdgnrs).balance, sdgnrs.pendingRedemptionEthValue()));
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        (bool done,,) = _batch(9_000_000);
        assertTrue(done);
        assertEq(keccak256(abi.encode(vm.getRecordedLogs())), manualLogs, "ordered player settlement and queue events");
        assertEq(keccak256(abi.encode(game.claimableWinningsOf(alice), game.claimableWinningsOf(bob),
            game.futurePrizePoolView(), address(sdgnrs).balance, sdgnrs.pendingRedemptionEthValue())), manualBalances);
    }
    // Pins coinflip.creditFlip in the router: external keeper gets the exact single credit.
    // The miner pays measured gas above each call's unpaid first 1M at the capped base fee, so the
    // fixture settles real lootbox claims (above that threshold) at a nonzero base fee.
    function test_MineFlipPaysExternalKeeperOnceAndNoBoxesStillCommits() public {
        vm.fee(1 gwei);
        uint24 day = game.currentDayView();
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
        uint24 day = game.currentDayView();
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
        address buyer = address(0xB0C1);
        _buyHuman(buyer, 1);
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000); _resolve(day, 175, 99); _commitWord(99);
        // The keeper is paid the engine's measured-gas reward for the shared call (the per-box
        // flat bounty no longer exists); the claim is sized so the call clears the unpaid first 1M.
        vm.fee(1 gwei);
        (uint256 reward, uint256 used) = _keeperMine(10_000_000);
        emit log_named_uint("redemption_plus_human_box_miner_execution_gas", used);
        (uint256 count,, bool complete) = _boxState(buyer);
        assertEq(count, 0); assertTrue(complete);
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertGt(reward, 0, "keeper paid for the shared call");
    }
    function test_OversizedFirstHumanBoxWaitsAndRedemptionsCommit() public {
        address buyer = address(0xB0C2);
        _buyHuman(buyer, 100);
        uint24 day = game.currentDayView();
        _newBurners(2, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99); _commitWord(99);
        // At the measured boundary allowance (<= 10M) the call admits one maximum claim; the engine
        // keeps admitting chunks while a larger allowance covers the next declared bound.
        uint256 boundary = _boundaryAllowance(10_000_000);
        emit log_named_uint("maximum_redemption_admission_boundary_allowance", boundary);
        vm.prank(keeper); game.mineFlip{gas: boundary}();
        (uint256 count, uint256 cursor, bool complete) = _boxState(buyer);
        assertEq(count, 100); assertEq(cursor, 0); assertFalse(complete);
        assertGt(sdgnrs.pendingRedemptionEthValue(), 0, "next maximum claim retains its reserve");
        assertTrue(sdgnrs.redemptionSettlementPending());
        for (uint256 i; i < 4 && count != 0; ++i) {
            vm.prank(keeper); game.mineFlip{gas: 10_000_000}();
            (count,, complete) = _boxState(buyer);
        }
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(count, 0); // Completing this cohort may request its generated next cohort.
    }
    function test_ColdMaximumRedemptionDefersWholeHumanOrderAtMeasuredBoundary() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        address first = address(0xB0C4);
        address second = address(0xB0C5);
        _buyHuman(first, 100); _buyHuman(second, 64);
        _resolve(day, 175, 99); _commitWord(99);
        vm.cool(address(game)); vm.cool(address(sdgnrs)); vm.cool(address(coinflip)); vm.cool(address(mockStETH));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE); vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE); vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE); vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        // At the measured boundary (the smallest allowance admitting the maximum claim, declared
        // 500k + 28 x 60k) the call succeeds and settles the claim, and its remaining allowance
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
        address buyer = address(0xB0C3);
        _buyHuman(buyer, 1);
        uint24 day = game.currentDayView();
        address[] memory players = _newBurners(67, 1 ether);
        _resolve(day, 100, 99);
        for (uint256 j; j < 22; ++j) sdgnrs.claimRedemption(players[j], day);
        // A caller may fund a safe checkpoint. The remaining physical gas admits
        // the dust claims but cannot admit the next whole human order.
        _commitWord(99);
        vm.prank(keeper); game.mineFlip{gas: 3_300_000}();
        assertFalse(sdgnrs.redemptionSettlementPending());
        (uint256 count, uint256 cursor, bool complete) = _boxState(buyer);
        assertEq(count, 1); assertEq(cursor, 0); assertFalse(complete);
        vm.prank(keeper); game.mineFlip();
        (count,, complete) = _boxState(buyer);
        assertEq(count, 0);
    }

    function test_OversizedFirstBetWaitsAndNextFreshCallSettlesIt() public {
        uint24 day = game.currentDayView();
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
