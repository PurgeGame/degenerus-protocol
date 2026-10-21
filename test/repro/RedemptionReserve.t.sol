// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {DegenerusGameRngUtils} from "../../contracts/modules/DegenerusGameRngUtils.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

contract RedemptionReserveHarness is DegenerusGameRngUtils {
    function close() external { _closeRedemptionBatch(); }
    function reserveFromOrdinary(uint256 amount) external {
        _debitClaimable(SDGNRS_WALLET_ID, amount);
        _setRedemptionReserve(_redemptionReserve() + amount);
    }
    function seedBorrower(uint32 id) external {
        level = 1;
        uint24 day = _simulatedDayIndex();
        dailyIdx = day;
        purchaseStartDay = day;
        _recordDailyRng(day - 1, 123456);
        _queueEntries(id, _activeTicketLevel() + 6, 3_000_000, false);
    }
    function topUp() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(
            abi.encodeWithSignature("topUpSdgnrsAfking()"));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
    function whale(uint24 day) external returns (uint256 paid) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(
            abi.encodeWithSignature("purchaseWhalePassForSdgnrs(uint24)", day));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint256));
    }
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
    function pools() external view returns (uint256) {
        (uint128 n, uint128 f) = _getPrizePools();
        (uint128 pn, uint128 pf) = _getPendingPools();
        return uint256(currentPrizePool) + claimablePool + n + f + pn + pf;
    }
}

contract RedemptionReserveGasBomb {
    fallback() external payable { assembly ("memory-safe") { invalid() } }
}

contract RedemptionReserveTest is RedemptionFixture {
    function _callHarness(bytes memory data) private returns (bytes memory result) {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionReserveHarness).runtimeCode);
        (bool ok, bytes memory output) = address(game).call(data);
        vm.etch(address(game), code);
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
        return output;
    }
    function _closeFundedReserve() private {
        _callHarness(abi.encodeCall(RedemptionReserveHarness.close, ()));
    }
    function _fundOrdinary(uint256 amount) private {
        GameFunding.setClaimable(2, amount + 1);
    }
    function _start(uint16 roll) private {
        settlementWord = _wordForRoll(roll);
        vm.mockCall(address(game), abi.encodeWithSelector(game.rngConsumerStage.selector), abi.encode(uint8(1)));
        assertFalse(_work(RESOLVE_ONLY_ALLOWANCE));
    }
    function _settlePaid(address who, uint32 batch) private {
        uint256 expected = _claimBase(who, batch) * _rollOf(batch) / 100 / 2;
        uint256 before = game.claimableWinningsOf(who);
        vm.recordLogs();
        assertTrue(_work(9_000_000));
        (bool found, uint256 direct,) = _claimedLegs(vm.getRecordedLogs(), who, batch);
        assertTrue(found, "fixed-budget worker paid the claim");
        assertEq(direct, expected);
        assertGe(game.claimableWinningsOf(who), before + expected);
    }
    function testLoanAfkingAndWhaleCannotSpendClosedReserve() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _fundOrdinary(1_000 ether);
        mockStETH.mint(address(game), 1_000 ether);
        _callHarness(abi.encodeCall(RedemptionReserveHarness.seedBorrower, (game.walletIdOf(bob))));
        uint256 burnAmount = sdgnrs.totalSupply() / 100;
        _burn(alice, burnAmount);
        _burn(bob, burnAmount);
        _burn(carol, burnAmount);
        vm.deal(address(game), 0);
        _closeFundedReserve();
        uint256 reserve = game.redemptionReserve();
        assertGt(reserve, 50 ether);
        uint256 ordinary = game.claimableWinningsOf(address(sdgnrs));
        _callHarness(abi.encodeCall(RedemptionReserveHarness.topUp, ()));
        assertLt(game.claimableWinningsOf(address(sdgnrs)), ordinary, "AFKing spends ordinary backing");
        ordinary = game.claimableWinningsOf(address(sdgnrs));
        uint24 day = game.currentDayView();
        uint256 bought = abi.decode(_callHarness(abi.encodeCall(RedemptionReserveHarness.whale, (day))), (uint256));
        assertGt(bought, 0, "whale purchase actually executes");
        assertLt(game.claimableWinningsOf(address(sdgnrs)), ordinary);
        ordinary = game.claimableWinningsOf(address(sdgnrs));
        DegenerusGameLens lens = new DegenerusGameLens();
        uint32 borrower = game.walletIdOf(bob);
        uint24 due = game.level() + 1;
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), borrower, due, ordinary - 1 ether);
        assertTrue(q.eligible, "borrow actually eligible");
        assertEq(q.principal, ordinary - 1 ether, "collateral drains ordinary funds down to lender floor");
        vm.prank(bob);
        game.borrow(borrower, due, ordinary - 1 ether, 0);
        assertLt(game.claimableWinningsOf(address(sdgnrs)), ordinary, "loan spends ordinary backing");
        assertEq(game.redemptionReserve(), reserve, "none of the three spends reaches reserve");
        _start(100);
        uint256 poolBefore = abi.decode(_callHarness(abi.encodeCall(RedemptionReserveHarness.pools, ())), (uint256));
        address[3] memory holders = [alice, bob, carol];
        uint256[3] memory beforeCredits;
        uint256[3] memory expected;
        for (uint256 i; i < 3; ++i) {
            beforeCredits[i] = game.claimableWinningsOf(holders[i]);
            expected[i] = _claimBase(holders[i], 1) / 2;
        }
        vm.recordLogs();
        assertTrue(_work(9_000_000));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < 3; ++i) {
            (bool found, uint256 direct,) = _claimedLegs(logs, holders[i], 1);
            assertTrue(found, "every beneficiary is paid after ordinary backing is spent");
            assertEq(direct, expected[i]);
            assertGe(game.claimableWinningsOf(holders[i]), beforeCredits[i] + expected[i]);
        }
        assertLt(game.redemptionReserve(), reserve, "only settlement consumed the protected reserve");
        uint256 poolAfter = abi.decode(_callHarness(abi.encodeCall(RedemptionReserveHarness.pools, ())), (uint256));
        assertEq(poolAfter, poolBefore, "ledger settlement conserves aggregate Game pools");
    }
    /// @dev Requests need the read certificate, which settlement must finish first, so no close
    ///      meets a settling batch; while one settles its reserve counts once in the preview.
    function testSettlingReserveCountsOnceInBackingPreview() public {
        _fundOrdinary(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.deal(address(game), 0);
        _closeFundedReserve();
        assertGt(game.redemptionReserve(), 0, "a close keeps the whole reserve in the Game");
        assertTrue(sdgnrs.redemptionSettlementPending());
        (uint256 preview,) = sdgnrs.previewBurnValue(sdgnrs.totalSupply());
        assertEq(preview, 100 ether - sdgnrs.pendingRedemptionEthValue(), "preview counts the reserve exactly once");
    }

    function testLeftoverReturnsAndNextClosePricesIt() public {
        _fundOrdinary(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.deal(address(game), 0);
        _closeFundedReserve();
        _start(100);
        _settlePaid(alice, 1);
        uint256 leftover = game.redemptionReserve();
        assertGt(leftover, 0, "maximum-minus-roll reserve stays protected until next close");
        uint256 money = game.claimableWinningsOf(address(sdgnrs)) - 1 + leftover;
        uint256 supply = sdgnrs.totalSupply();
        uint256 amount = supply / 100;
        _burn(bob, amount);
        uint256 expected = money * amount / supply / 1 gwei * 1 gwei;
        uint256 ordinary = game.claimableWinningsOf(address(sdgnrs));
        _closeFundedReserve();
        (, , uint96 base,,,) = sdgnrs.redemptionBatches(2);
        assertEq(base, expected, "next close includes released leftovers in price");
        assertEq(game.claimableWinningsOf(address(sdgnrs)) + game.redemptionReserve(), ordinary + leftover);
    }
    function testTerminalClaimPullsReserveImmediatelyAfterShortClose() public {
        _fundOrdinary(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.deal(address(game), 0.1 ether);
        mockStETH.mint(address(game), 100 ether);
        _closeFundedReserve();
        assertGt(game.redemptionReserve(), 0);
        _terminalize();
        uint256 expected = _claimBase(alice, 1);
        uint256 before = _received(alice);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, 1);
        assertEq(_received(alice) - before, expected, "terminal beneficiary paid now");
        assertEq(game.redemptionReserve(), 0);
    }
    function testLargeGameBackingCapsBatchWithoutTruncating() public {
        // A well-formed adversarial yield balance can fit Game's uint128 ledger but exceed uint96.
        _fundOrdinary(uint256(type(uint96).max) * 100);
        uint256 supply = sdgnrs.totalSupply();
        uint256 tokens = supply / 100;
        (uint256 preview,) = sdgnrs.previewBurnValue(supply);
        assertEq(preview, type(uint96).max, "preview uses the packed value ceiling");
        _burn(alice, tokens);
        vm.deal(address(game), 0);
        _closeFundedReserve();
        (,uint96 payout,uint96 base,,,) = sdgnrs.redemptionBatches(1);
        uint256 expected = uint256(type(uint96).max) * tokens / supply / 1 gwei * 1 gwei;
        assertEq(base, expected, "large ledger cannot wrap the batch base");
        assertEq(payout, expected * 175 / 100, "maximum payout is not truncated");
        assertEq(game.redemptionReserve(), payout);
        (preview,) = sdgnrs.previewBurnValue(sdgnrs.totalSupply());
        assertEq(preview, uint256(type(uint96).max) - payout);
        _start(100);
        _settlePaid(alice, 1);
    }
    function testOversizedTokenBalanceCannotOverflowPreviewOrTerminalCustody() public {
        _fundOrdinary(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.mockCall(address(mockStETH), abi.encodeWithSelector(mockStETH.balanceOf.selector, address(sdgnrs)),
            abi.encode(type(uint256).max));
        (uint256 preview,) = sdgnrs.previewBurnValue(sdgnrs.totalSupply() + _escrow());
        assertEq(preview, 100 ether, "unrepresentable token output contributes zero");
        _closeFundedReserve();
        _terminalize();
        uint256 expected = _claimBase(alice, 1);
        uint256 before = alice.balance;
        vm.prank(alice);
        sdgnrs.claimRedemption(0, 1);
        assertEq(alice.balance - before, expected, "malformed token amount cannot block available ETH payout");
    }
    function testRevertedClaimKeepsFlipPrincipalAndEthBacking() public { _checkRevert(false, true); }
    function testGasExhaustedClaimRevertsStepAndKeepsBacking() public { _checkRevert(true, true); }
    function testRevertedClaimAfterLostFlipKeepsPrincipalForfeited() public { _checkRevert(false, false); }
    /// @dev A roll-100 word whose batch-1 synthetic flip wins or loses as asked.
    function _wordForFlip(bool won) private pure returns (uint256 word) {
        for (uint256 k;; ++k) {
            word = ((uint256(100 - 21) + 155 * k) << 8) | 2;
            if ((_synthReward(word, 1) != 0) == won) return word;
        }
    }
    /// @dev A claim that cannot complete reverts the step with the reserve, FLIP backing and claim
    ///      untouched. Once it works the claim pays from the protected reserve, a won flip pays the
    ///      claimant rather than returning to backing, and the unrolled remainder goes home at the
    ///      next close.
    function _checkRevert(bool exhaustGas, bool won) private {
        _fundOrdinary(100 ether);
        _seedFlipBacking(1_000_000);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.deal(address(game), 0);
        _closeFundedReserve();
        (,,, uint96 escrow,,) = sdgnrs.redemptionBatches(1);
        assertGt(escrow, 0);
        settlementWord = _wordForFlip(won);
        _mockSettlingStage();
        assertFalse(_work(RESOLVE_ONLY_ALLOWANCE));
        vm.prank(address(sdgnrs));
        uint256 backing = coinflip.redeemableFlipBacking();
        uint256 reserve = game.redemptionReserve();
        bytes memory module = ContractAddresses.GAME_LOOTBOX_MODULE.code;
        if (exhaustGas) vm.etch(ContractAddresses.GAME_LOOTBOX_MODULE, type(RedemptionReserveGasBomb).runtimeCode);
        else vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"deadbeef");
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        _assertWorkRevertsUnchanged(1, 9_000_000);
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved, "the claim's reserve is still held");
        assertGt(_claimTokens(alice, 1), 0, "the claim is still live");
        vm.prank(address(sdgnrs));
        assertEq(coinflip.redeemableFlipBacking(), backing, "FLIP backing is untouched");
        assertEq(game.redemptionReserve(), reserve);
        vm.clearMockedCalls();
        vm.etch(ContractAddresses.GAME_LOOTBOX_MODULE, module);
        _mockSettlingStage();
        uint256 stake = coinflip.coinflipAmount(alice);
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(_claimTokens(alice, 1), 0);
        vm.prank(address(sdgnrs));
        assertEq(coinflip.redeemableFlipBacking(), backing, "a paid claim never returns its FLIP principal to backing");
        if (won) assertGt(coinflip.coinflipAmount(alice), stake, "a won flip pays the claimant");
        else assertEq(coinflip.coinflipAmount(alice), stake, "a lost flip forfeits the principal");
        vm.clearMockedCalls();
        uint256 leftover = game.redemptionReserve();
        assertGt(leftover, 0, "the unrolled remainder stays protected until the next close");
        uint256 ordinary = game.claimableWinningsOf(address(sdgnrs));
        _closeFundedReserve();
        assertEq(game.redemptionReserve(), 0);
        assertEq(uint256(vm.load(address(game), bytes32(uint256(84)))), 1, "released reserve home retains its sentinel");
        assertEq(game.claimableWinningsOf(address(sdgnrs)), ordinary + leftover, "the remainder returns to ordinary backing");
    }
}
