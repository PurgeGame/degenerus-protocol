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
        (bool done, uint256 charged, uint256 quote) = _batch(9_000_000);
        assertFalse(done); assertLe(charged, 9_000_000);
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
    function test_MineFlipPaysExternalKeeperOnceAndNoBoxesStillCommits() public {
        uint24 day = game.currentDayView();
        _burn(alice, 1 ether); _burn(bob, 1 ether);
        _resolve(day, 100, 99);

        uint256 prior = coinflip.coinflipAmount(keeper);
        vm.prank(keeper); game.mineFlip();
        assertGt(coinflip.coinflipAmount(keeper) - prior, 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }
    function test_LowGasMineClearsRedemptionsWithoutMinerCredit() public {
        uint24 day = game.currentDayView();
        _burn(alice, 1 ether); _burn(bob, 1 ether);
        _resolve(day, 100, 99); _commitWord(99);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 prior = coinflip.coinflipAmount(keeper);
        vm.prank(keeper); game.mineFlip{gas: 9_500_000}();
        assertEq(coinflip.coinflipAmount(keeper), prior);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }
    function test_RedemptionThenAffordableHumanBoxSharesOneCall() public {
        address buyer = address(0xB0C1);
        _buyHuman(buyer, 1);
        uint24 day = game.currentDayView();
        _burn(alice, 1 ether); _resolve(day, 100, 99); _commitWord(99);
        uint256 prior = coinflip.coinflipAmount(keeper);
        vm.prank(keeper); game.mineFlip();
        (uint256 count,, bool complete) = _boxState(buyer);
        assertEq(count, 0); assertTrue(complete);
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertGt(coinflip.coinflipAmount(keeper) - prior, 24_000_000_000_000 * 1000 ether / game.mintPrice());
    }
    function test_OversizedFirstHumanBoxWaitsAndRedemptionsCommit() public {
        address buyer = address(0xB0C2);
        _buyHuman(buyer, 100);
        uint24 day = game.currentDayView();
        _newBurners(2, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99); _commitWord(99);
        vm.prank(keeper); game.mineFlip();
        (uint256 count, uint256 cursor, bool complete) = _boxState(buyer);
        assertEq(count, 100); assertEq(cursor, 0); assertFalse(complete);
        assertGt(sdgnrs.pendingRedemptionEthValue(), 0, "next maximum claim retains its reserve");
        assertTrue(sdgnrs.redemptionSettlementPending());
        for (uint256 i; i < 4 && count != 0; ++i) {
            vm.prank(keeper); game.mineFlip();
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
        vm.prank(keeper);
        uint256 beforeGas = gasleft();
        game.mineFlip();
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("cold_maximum_redemption_composition_gas", used);
        assertLe(used, 10_000_000, "entire composition below current gas ceiling");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        (uint256 count, uint256 cursor,) = _boxState(first);
        assertEq(count, 100, "next indivisible order remains whole"); assertEq(cursor, 0);
        // Both orders fit individually; continuation follows their committed FIFO.
        for (uint256 i; i < 3 && count != 0; ++i) {
            vm.prank(keeper); game.mineFlip();
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
        vm.prank(keeper); game.mineFlip{gas: 3_500_000}();
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertGt(game.degeneretteBetInfo(index, 1), 0, "remainder cannot fund first whole bet");
        vm.prank(keeper); game.mineFlip();
        assertEq(game.degeneretteBetInfo(index, 1), 0, "fresh allowance resolves deferred bet");
    }
}
