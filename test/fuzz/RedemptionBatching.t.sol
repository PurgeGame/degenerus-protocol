// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
        return sdgnrs.processRedemptionSettlement(allowance);
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
        (bool done, uint256 charged, uint256 quote) = _batch(1856);
        assertTrue(done);
        assertLe(charged, 1856);
        assertEq(quote, 2 * 24_000_000_000_000 * 1000 ether / game.mintPrice());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        (done, charged, quote) = _batch(1856);
        assertTrue(done); assertEq(charged, 0); assertEq(quote, 0);
    }
    function test_MaximumNextBeneficiaryWaitsWholeAndThenCompletes() public {
        uint24 day = game.currentDayView();
        address[] memory players = _newBurners(3, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        (uint96 thirdExpected,,) = sdgnrs.pendingRedemptions(players[2], day);
        (bool done, uint256 charged, uint256 quote) = _batch(1856);
        assertFalse(done); assertLe(charged, 1856);
        (uint96 first,,) = sdgnrs.pendingRedemptions(players[0], day);
        (uint96 second,,) = sdgnrs.pendingRedemptions(players[1], day);
        (uint96 third,,) = sdgnrs.pendingRedemptions(players[2], day);
        assertEq(first, 0); assertEq(second, 0); assertEq(third, thirdExpected); assertGt(third, 0);
        uint256 beforeReserve = sdgnrs.pendingRedemptionEthValue();
        (done, charged,) = _batch(700);
        assertFalse(done); assertEq(charged, 0); assertEq(sdgnrs.pendingRedemptionEthValue(), beforeReserve);
        (done, charged, quote) = _batch(1856);
        assertTrue(done); assertLe(charged, 1856);
        assertEq(quote, 24_000_000_000_000 * 1000 ether / game.mintPrice());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_ManuallyClaimedCohortNeedsOnlyBoundedCleanupWithoutBounty() public {
        uint24 day = game.currentDayView();
        address[] memory players = _newBurners(3, 1 ether);
        _resolve(day, 100, 99);
        for (uint256 i; i < players.length; ++i) sdgnrs.claimRedemption(players[i], day);
        assertTrue(sdgnrs.redemptionSettlementPending(), "keeper cleanup is still owed");
        (bool done, uint256 charged, uint256 quote) = _batch(11);
        assertFalse(done); assertEq(charged, 0); assertEq(quote, 0);
        assertTrue(sdgnrs.redemptionSettlementPending());
        (done, charged, quote) = _batch(12);
        assertTrue(done); assertEq(charged, 12); assertEq(quote, 0);
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
        (bool done,, uint256 quote) = _batch(1856);
        assertTrue(done);
        assertEq(quote, 24_000_000_000_000 * 1000 ether / game.mintPrice());
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
        (bool done,,) = _batch(1856);
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
        uint256 expected = 2 * 24_000_000_000_000 * 1000 ether / game.mintPrice();
        uint256 prior = coinflip.coinflipAmount(keeper);
        vm.prank(keeper); game.mineFlip();
        assertEq(coinflip.coinflipAmount(keeper) - prior, expected);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }
    function test_UnrewardedAdvanceClearsRedemptionsWithoutKeeperCredit() public {
        uint24 day = game.currentDayView();
        _burn(alice, 1 ether); _burn(bob, 1 ether);
        _resolve(day, 100, 99); _commitWord(99);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 prior = coinflip.coinflipAmount(keeper);
        vm.prank(keeper); game.advanceGame();
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
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        vm.prank(keeper); game.mineFlip();
        (count,, complete) = _boxState(buyer);
        assertEq(count, 0); assertTrue(complete);
    }
    function test_ColdMaximumRedemptionThenLargestFittingHumanComposition() public {
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
        emit log_named_uint("cold_maximum_redemption_plus_164_boxes_gas", used);
        assertLe(used, 10_000_000, "entire composition below existing gas target");
        (uint256 count,, bool complete) = _boxState(first);
        assertEq(count, 0); assertTrue(complete);
        (count,, complete) = _boxState(second);
        assertEq(count, 0); assertTrue(complete);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_NearBudgetCompletionDefersHumanBoxUntilFreshAllowance() public {
        address buyer = address(0xB0C3);
        _buyHuman(buyer, 1);
        uint24 day = game.currentDayView();
        address[] memory players = _newBurners(67, 1 ether);
        _resolve(day, 100, 99);
        for (uint256 j; j < 22; ++j) sdgnrs.claimRedemption(players[j], day);
        // The manual prefix advances the cursor: 45 claims * 40 + completion 12
        // leaves too little of the shared allowance for the next human box.
        _commitWord(99);
        vm.prank(keeper); game.mineFlip();
        assertFalse(sdgnrs.redemptionSettlementPending());
        (uint256 count, uint256 cursor, bool complete) = _boxState(buyer);
        assertEq(count, 1); assertEq(cursor, 0); assertFalse(complete);
        vm.prank(keeper); game.mineFlip();
        (count,, complete) = _boxState(buyer);
        assertEq(count, 0); assertTrue(complete);
    }

    function test_OversizedFirstBetWaitsAndNextFreshCallSettlesIt() public {
        uint24 day = game.currentDayView();
        _newBurners(45, 1 ether);
        game.placeDegeneretteBet{value: 0.125 ether}(bob, 0, 0.005 ether, 25, 0);
        _resolve(day, 100, 99); _commitWord(99);
        vm.prank(keeper); game.mineFlip();
        assertFalse(sdgnrs.redemptionSettlementPending());
        (,, bool complete) = _boxState(bob);
        assertFalse(complete, "strict remainder cannot fund first bet");
        vm.prank(keeper); game.mineFlip();
        (,, complete) = _boxState(bob);
        assertTrue(complete, "fresh allowance eventually resolves deferred bet");
    }
}
