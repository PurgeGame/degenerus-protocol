// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;


import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {RedemptionCloseTools} from "./helpers/RedemptionCloseTools.sol";
import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @dev Etched over the Game for state seeding. `enterDue` jumps `level` to a due level and arms
///      its seizure the way `prepareRequestBoundary` does; `seize` runs the production seizure
///      worker in the Game's context.
contract LoanSeeder is DegenerusGameStorage {
    function end() external { gameOver = true; }
    function finalSweep() external { _goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1); }
    function lock(bool on) external { rngLockedFlag = on; }
    function setLevel(uint24 level_) external { level = level_; }
    function lateBorrowWindow(uint8 phase, bool writeSlot) external {
        level = 29;
        jackpotPhaseFlag = phase != 0;
        jackpotCounter = phase == 2 ? JACKPOT_DAYS - 1 : 0;
        phaseTransitionActive = phase == 3;
        rngLockedFlag = true;
        ticketWriteSlot = writeSlot;
        prizePoolFrozen = true;
        _setPendingPools(0.5 ether, 0.25 ether);
    }
    function creditStallDays(uint24 count) external { purchaseStartDay += count; }
    function awardSdgnrs(uint32 id, uint256 amount) external {
        dgnrs.transferFromPool(IsDGNRS.Pool.Reward, _payee(_walletElement(id)), amount);
    }
    function seedLevel(uint32 id, uint24 level_, uint32 entries) external { _queueEntries(id, level_, entries, false); }

    function seed(uint32 id, uint32 entries, uint128 claimable, uint128 prepaid) external {
        uint24 day = _simulatedDayIndex();
        _recordDailyRng(day - 1, 123456);
        dailyIdx = day;
        purchaseStartDay = day;
        if (entries != 0) _queueEntries(id, _activeTicketLevel() + 6, entries, false);
        uint256 old = balancesPacked[id];
        // The claimable sentinel is not backed by claimablePool. Fixtures may also seed
        // a zero raw balance, so exclude the sentinel independently on both sides.
        uint256 oldBacked = uint128(old) > 1 ? uint128(old) - 1 : 0;
        uint256 newBacked = claimable > 1 ? claimable - 1 : 0;
        claimablePool = uint128(uint256(claimablePool) + newBacked + prepaid - oldBacked - (old >> 128));
        balancesPacked[id] = uint256(claimable) | (uint256(prepaid) << 128);
    }

    function enterDue(uint24 due) external {
        level = due;
        if (_loansDueCount[due] != 0) {
            _setLoansDuePending(true);
            loanSeizeCursor = 0;
        }
    }

    function seize() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

contract RejectLoanEth {
    function borrow(address game, uint24 due) external {
        (bool ok, bytes memory reason) =
            game.call(abi.encodeWithSignature("borrow(uint32,uint24,uint256,uint256)", uint32(0), due, type(uint256).max, uint256(0)));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
    receive() external payable { revert("reject ETH"); }
}

/// @notice Loans replace account sales: borrow against far-future tickets, repay with interest before
///         the due level, or the lender takes the account at that level exactly as a sale did.
contract AccountLoansTest is RedemptionCloseTools {
    address private seller;
    uint32 private root;
    bytes private gameRuntime;
    address private seeder;
    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        seller = makeAddr("loan-borrower");
        root = _giveWalletId(seller);
        _grantSmurfBase(seller, 4);
        vm.deal(seller, 100 ether);
        vm.deal(address(game), 10_000 ether);
        gameRuntime = address(game).code;
        seeder = address(new LoanSeeder());
        lens = new DegenerusGameLens();
        _resolve(2, true);
        _seed(root, 400, 0, 0);
        _seed(2, 0, 100 ether, 0);
    }

    // ---------------------------------------------------------------- helpers

    function _etch() private { vm.etch(address(game), seeder.code); }
    function _unetch() private { vm.etch(address(game), gameRuntime); }

    function _seed(uint32 id, uint32 entries, uint128 claimable, uint128 prepaid) private {
        _etch(); LoanSeeder(address(game)).seed(id, entries, claimable, prepaid); _unetch();
    }

    function _seedLevel(uint32 id, uint24 lvl, uint32 entries) private {
        _etch(); LoanSeeder(address(game)).seedLevel(id, lvl, entries); _unetch();
    }

    function _setLevel(uint24 lvl) private {
        _etch(); LoanSeeder(address(game)).setLevel(lvl); _unetch();
    }

    function _resolve(uint24 day, bool win) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        uint256 word = win ? 123457 : 123456;
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, word, day);
    }

    /// @dev Move to the day after the deployment endpoint and complete its subscriber pass, so a
    ///      new run can start (the fixtures park the clock before the deploy day).
    function _openSubscriptionDay() private {
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 9) * 1 days + 82_621);
        _finishSubscriptionWindow();
    }

    function _child() private returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.prank(seller);
        id = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _payee(uint32 id) private view returns (address payee) {
        (, payee, ) = game.resolveAccount(id, address(0));
    }

    function _pool() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
    }

    function _nextDue() private view returns (uint24) {
        return game.level() + 1;
    }

    /// @dev Borrow the full quote for `id` due at `due`; returns the principal.
    function _borrow(uint32 id, uint24 due) private returns (uint256 principal) {
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, due, type(uint256).max);
        assertTrue(q.eligible, "borrow eligible");
        principal = q.principal;
        vm.prank(seller);
        game.borrow(id, due, type(uint256).max, principal);
    }

    /// @dev Enter `due` and run the production seizure worker.
    function _seize(uint24 due) private {
        _etch();
        LoanSeeder(address(game)).enterDue(due);
        LoanSeeder(address(game)).seize();
        _unetch();
    }

    /// @dev Borrow against `id` and default: the borrower keeps the principal, the lender the account.
    function _default(uint32 id) private returns (uint256 principal) {
        uint24 due = _nextDue();
        principal = _borrow(id, due);
        _seize(due);
    }

    function _coinState(uint32 id, uint128 bank, uint128 carry, uint24 lastDay) private {
        bytes32 slot = keccak256(abi.encode(id, uint256(2)));
        vm.store(address(coinflip), slot, bytes32(uint256(bank) | (uint256(lastDay) << 128)
            | (uint256(lastDay) << 152) | (uint256(1) << 176)));
        vm.store(address(coinflip), bytes32(uint256(slot) + 1), bytes32(uint256(carry) << 128));
    }

    function _giveSdgnrs(address player, uint256 amount) private {
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, player, amount);
    }

    function _endGame() private {
        _etch(); LoanSeeder(address(game)).end(); _unetch();
    }

    function _fundVaultLender() private {
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, 100 ether, 0);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.setLiquidationBuyFallback(true, 1 ether);
    }

    function _awardEth(uint32 id, uint256 amount) private {
        GameFunding.credit(id, amount);
    }

    function _rate(uint256 d) private pure returns (uint256) {
        if (d <= 20) return 1000 - (d - 2) * 500 / 18;
        return 500 - (d - 20) * 300 / 80;
    }

    // ---------------------------------------------------------------- valuation

    function test_ValuationTwoSlopesAtEachDistance() public {
        uint24 cl = lens.activeTicketLevelOf(address(game));
        uint32 fresh = _giveWalletId(makeAddr("valuation"));
        uint256[6] memory ds = [uint256(3), 10, 20, 21, 50, 100];
        uint256 expected;
        for (uint256 i; i < ds.length; ++i) {
            uint24 target = uint24(cl + ds[i]);
            _seedLevel(fresh, target, 40);
            expected += PriceLookupLib.priceForLevel(target) * 10 * _rate(ds[i]) / 10_000;
        }
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), fresh, cl, type(uint256).max);
        assertEq(q.principal, expected, "every level from due + 2 counts at its distance rate");
        assertEq(_rate(2), 1000);
        assertEq(_rate(20), 500);
        assertEq(_rate(100), 200);
        // A later due level drops the near levels from the collateral.
        DegenerusGameLens.LoanQuote memory later = lens.previewBorrow(address(game), fresh, uint24(cl + 9), type(uint256).max);
        uint256 dropped = PriceLookupLib.priceForLevel(uint24(cl + 3)) * 10 * _rate(3) / 10_000
            + PriceLookupLib.priceForLevel(uint24(cl + 10)) * 10 * _rate(10) / 10_000;
        assertEq(later.principal, expected - dropped, "levels below due + 2 are not collateral");
    }

    function testFuzz_ValuationMatchesReference(uint8 a, uint8 b, uint16 entriesA, uint16 entriesB) public {
        uint24 cl = lens.activeTicketLevelOf(address(game));
        uint256 da = 3 + uint256(a) % 98;
        uint256 db = 3 + uint256(b) % 98;
        vm.assume(da != db);
        uint32 fresh = _giveWalletId(makeAddr("valuation-fuzz"));
        uint32 ea = uint32(entriesA) * 4 + 4;
        uint32 eb = uint32(entriesB) * 4 + 4;
        _seedLevel(fresh, uint24(cl + da), ea);
        _seedLevel(fresh, uint24(cl + db), eb);
        uint256 expected = PriceLookupLib.priceForLevel(uint24(cl + da)) * (ea / 4) * _rate(da) / 10_000
            + PriceLookupLib.priceForLevel(uint24(cl + db)) * (eb / 4) * _rate(db) / 10_000;
        assertEq(lens.previewBorrow(address(game), fresh, cl, type(uint256).max).principal, expected);
    }

    function test_SameQuoteOnDifferentDays() public {
        uint256 first = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        _resolve(9, false);
        _seed(2, 0, 100 ether, 0);
        assertEq(lens.previewBorrow(address(game), root, 1, type(uint256).max).principal, first, "no daily randomness");
    }

    function test_BorrowPaysTheLensQuoteExactly() public {
        uint256 before = seller.balance;
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        uint256 principal = _borrow(root, 1);
        assertGt(principal, 0.05 ether);
        assertEq(seller.balance, before + principal);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore - principal);
        assertEq(_pool(), poolBefore - principal);
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), root);
        assertEq(info.principal, principal);
        assertEq(info.lenderId, 2);
        assertEq(info.dueLevel, 1);
        assertEq(info.family, 1);
        assertEq(_payee(root), seller, "the borrower keeps the account during the loan");
    }

    // ---------------------------------------------------------------- partial loans

    function test_PartialLoanPaysOnlyTheAmount() public {
        uint256 full = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        uint256 amount = full / 3;
        assertGt(amount, 0.05 ether);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, amount);
        assertEq(q.maxPrincipal, full, "the full quote stays visible");
        assertEq(q.principal, amount);
        assertTrue(q.eligible);

        uint256 before = seller.balance;
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        vm.prank(seller);
        game.borrow(root, 1, amount, amount);
        assertEq(seller.balance, before + amount);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore - amount);
        assertEq(_pool(), poolBefore - amount);
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), root);
        assertEq(info.principal, amount);
        assertEq(info.owed, amount * 105 / 100, "interest accrues on the amount taken");

        vm.deal(seller, info.owed);
        vm.prank(seller); game.repay{value: info.owed}(root);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore - amount + info.owed);
        assertEq(lens.loanOf(address(game), root).principal, 0);
    }

    function test_AmountAboveQuoteTakesTheQuote() public {
        uint256 full = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        assertEq(lens.previewBorrow(address(game), root, 1, full + 1 ether).principal, full);
        vm.prank(seller); game.borrow(root, 1, full + 1 ether, full);
        assertEq(lens.loanOf(address(game), root).principal, full);
    }

    function test_PartialLoanBelowMinimumReverts() public {
        assertGt(lens.previewBorrow(address(game), root, 1, type(uint256).max).principal, 0.05 ether);
        assertFalse(lens.previewBorrow(address(game), root, 1, 0.05 ether - 1).eligible);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 1, 0.05 ether - 1, 0);
        vm.prank(seller); game.borrow(root, 1, 0.05 ether, 0);
        assertEq(lens.loanOf(address(game), root).principal, 0.05 ether);
    }

    function test_LatePartialLoanPaysHalfOfTheAmountInTickets() public {
        _warpDaysIn(21);
        uint24 cl = lens.activeTicketLevelOf(address(game));
        uint256 price = PriceLookupLib.priceForLevel(cl);
        uint256 amount = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal / 2;
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, amount);
        uint256 ticketWei = amount / 2 / price * price;
        assertGt(ticketWei, 0);
        assertEq(q.ticketWei, ticketWei);
        uint256 before = seller.balance;
        vm.prank(seller); game.borrow(root, 1, amount, amount - ticketWei);
        assertEq(seller.balance, before + amount - ticketWei);
    }

    function test_PartialLoanDefaultStillSeizesTheAccount() public {
        uint256 amount = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal / 2;
        assertGt(amount, 0.05 ether);
        vm.prank(seller); game.borrow(root, 1, amount, 0);
        assertEq(lens.loanOf(address(game), root).principal, amount);
        _seize(1);
        assertEq(game.acquiredBuyer(root), 2, "the account is the collateral, whatever was drawn");
    }

    // ---------------------------------------------------------------- late-level ticket half

    /// @dev Warp to `daysIn` days past the level's purchase start.
    function _warpDaysIn(uint256 daysIn) private {
        uint256 start = uint24(uint256(vm.load(address(game), bytes32(GameSlots.PURCHASE_START_DAY))));
        vm.warp((start + daysIn - 1 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function test_DayTwentyLoanIsAllEth() public {
        _warpDaysIn(20);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        assertEq(q.ticketWei, 0, "day 20 is not past the threshold");
        uint256 before = seller.balance;
        uint256 entriesBefore = game.entriesOwedView(1, seller);
        _borrow(root, 1);
        assertEq(seller.balance, before + q.principal);
        assertEq(game.entriesOwedView(1, seller), entriesBefore);
    }

    function test_LateLevelLoanPaysHalfInTickets() public {
        _warpDaysIn(21);
        uint24 cl = lens.activeTicketLevelOf(address(game));
        uint256 price = PriceLookupLib.priceForLevel(cl);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        uint256 ticketWei = q.principal / 2 / price * price;
        assertGt(ticketWei, 0);
        assertEq(q.ticketWei, ticketWei, "lens mirrors the ticket half");

        uint256 before = seller.balance;
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        uint256 nextBefore = game.nextPrizePoolView();
        uint256 futureBefore = game.futurePrizePoolView();
        uint256 entriesBefore = game.entriesOwedView(cl, seller);

        vm.prank(seller);
        game.borrow(root, 1, type(uint256).max, q.principal - ticketWei);

        assertEq(seller.balance, before + q.principal - ticketWei, "the rest pays out as ETH");
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore - q.principal, "lender funds it all");
        assertEq(_pool(), poolBefore - q.principal);
        assertEq(game.entriesOwedView(cl, seller), entriesBefore + ticketWei / price * 4, "whole tickets");
        assertEq(game.nextPrizePoolView(), nextBefore + ticketWei - ticketWei / 10, "90% next pool");
        assertEq(game.futurePrizePoolView(), futureBefore + ticketWei / 10, "10% future pool");
        assertEq(lens.loanOf(address(game), root).principal, q.principal, "the loan is the full principal");
        assertEq(lens.loanOf(address(game), root).owed, q.principal * 105 / 100);
    }

    function test_JackpotPhaseLoanIsAllEth() public {
        _warpDaysIn(21);
        bytes32 slot0 = vm.load(address(game), bytes32(GameSlots.JACKPOT_PHASE_FLAG));
        vm.store(address(game), bytes32(GameSlots.JACKPOT_PHASE_FLAG),
            slot0 | bytes32(uint256(1) << (GameSlots.JACKPOT_PHASE_FLAG_OFFSET * 8)));
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        assertEq(q.ticketWei, 0, "jackpot phase pays no tickets");
        uint256 before = seller.balance;
        _borrow(root, 1);
        assertEq(seller.balance, before + q.principal);
    }

    function test_LateLevelMinEthOutBoundsTheEthPart() public {
        _warpDaysIn(21);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        assertGt(q.ticketWei, 0);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()")));
        game.borrow(root, 1, type(uint256).max, q.principal - q.ticketWei + 1);
    }

    function testFuzz_LateBorrowPreservesCommittedTicketsAndPools(uint8 phaseSeed, bool writeSlot) public {
        uint8 phase = uint8(bound(phaseSeed, 0, 3));
        _seedLevel(root, 35, 400);
        _warpDaysIn(21);
        _etch(); LoanSeeder(address(game)).lateBorrowWindow(phase, writeSlot); _unetch();
        uint24 target = phase == 1 ? 29 : 30;
        uint24 writeKey = target | (writeSlot ? uint24(1 << 23) : 0);
        uint24 readKey = target | (writeSlot ? 0 : uint24(1 << 23));
        uint80 committed = TicketQueueStorage.owedById(address(game), readKey, root);
        uint256 writeBefore = uint32(TicketQueueStorage.owedById(address(game), writeKey, root) >> 8);
        uint256 livePools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 pending = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED)));
        uint256 claimableBefore = _pool();
        uint256 custodyBefore = address(game).balance;
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 30, type(uint256).max);
        uint256 tickets = phase == 0 ? q.principal / 2 / PriceLookupLib.priceForLevel(target) : 0;
        assertTrue(q.eligible);
        if (phase == 0) assertGt(tickets, 0);
        assertEq(q.ticketWei, tickets * PriceLookupLib.priceForLevel(target));

        vm.prank(seller); game.borrow(root, 30, type(uint256).max, q.principal - q.ticketWei);

        assertEq(TicketQueueStorage.owedById(address(game), readKey, root), committed,
            "a loan cannot change the committed ticket cohort");
        assertEq(uint32(TicketQueueStorage.owedById(address(game), writeKey, root) >> 8),
            writeBefore + tickets * 4, "tickets follow the active purchase level and write slot");
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED))), livePools,
            "frozen prize pools cannot change");
        uint256 pendingAfter = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED)));
        assertEq(uint128(pendingAfter), uint128(pending) + q.ticketWei - q.ticketWei / 10);
        assertEq(pendingAfter >> 128, (pending >> 128) + q.ticketWei / 10);
        assertEq(_pool(), claimableBefore - q.principal);
        assertEq(address(game).balance, custodyBefore - q.principal + q.ticketWei);
    }

    function test_LateLoanUsesStethOnlyForCashPart() public {
        _warpDaysIn(21);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        uint256 cash = q.principal - q.ticketWei;
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), q.principal);
        uint256 stethBefore = mockStETH.balanceOf(address(game));
        uint256 sellerBefore = mockStETH.balanceOf(seller);
        vm.prank(seller); game.borrow(root, 1, type(uint256).max, cash);
        assertApproxEqAbs(mockStETH.balanceOf(seller), sellerBefore + cash, 1);
        assertApproxEqAbs(mockStETH.balanceOf(address(game)), stethBefore - cash, 1,
            "the ticket part retains its backing in the game");
        assertEq(game.entriesOwedView(1, seller), q.ticketWei / PriceLookupLib.priceForLevel(1) * 4);
    }

    function test_LateLoanFailedPayoutRollsBackTicketsAndPools() public {
        RejectLoanEth receiver = new RejectLoanEth();
        uint32 id = _giveWalletId(address(receiver));
        _seed(id, 400, 1, 0);
        _warpDaysIn(21);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, 1, type(uint256).max);
        assertGt(q.ticketWei, 0);
        uint256 poolsBefore = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 claimableBefore = _pool();
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        vm.expectRevert(bytes4(keccak256("TransferFailed()"))); receiver.borrow(address(game), 1);
        assertEq(game.entriesOwedView(1, address(receiver)), 0);
        assertEq(lens.loanOf(address(game), id).principal, 0);
        assertEq(lens.loansDue(address(game), 1).length, 0);
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED))), poolsBefore);
        assertEq(_pool(), claimableBefore);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore);
    }

    function test_CreditedStallDaysDelayLoanTicketThreshold() public {
        _warpDaysIn(21);
        assertGt(lens.previewBorrow(address(game), root, 1, type(uint256).max).ticketWei, 0);
        _etch(); LoanSeeder(address(game)).creditStallDays(2); _unetch();
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 1, type(uint256).max);
        assertEq(q.ticketWei, 0);
        uint256 before = seller.balance;
        _borrow(root, 1);
        assertEq(seller.balance, before + q.principal);
    }

    function test_LateLoanBelowOneTicketPaysAllCash() public {
        _setLevel(9);
        _seedLevel(root, 12, 60);
        _warpDaysIn(21);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), root, 10, type(uint256).max);
        assertTrue(q.eligible);
        assertLt(q.principal / 2, PriceLookupLib.priceForLevel(10));
        assertEq(q.ticketWei, 0);
        uint256 before = seller.balance;
        _borrow(root, 10);
        assertEq(seller.balance, before + q.principal);
        assertEq(game.entriesOwedView(10, seller), 0);
    }

    function test_LateSmurfLoanCreditsTicketsToBorrowingAccount() public {
        uint32 child = _child();
        _seed(child, 400, 1, 0);
        _warpDaysIn(21);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), child, 1, type(uint256).max);
        uint24 writeKey = uint8(uint256(vm.load(address(game), bytes32(0)))
            >> (GameSlots.TICKET_WRITE_SLOT_OFFSET * 8)) == 0 ? 1 : uint24(1 | (1 << 23));
        uint256 childBefore = uint32(TicketQueueStorage.owedById(address(game), writeKey, child) >> 8);
        uint80 rootBefore = TicketQueueStorage.owedById(address(game), writeKey, root);
        uint256 cashBefore = seller.balance;
        vm.prank(seller); game.borrow(child, 1, type(uint256).max, q.principal - q.ticketWei);
        assertEq(seller.balance, cashBefore + q.principal - q.ticketWei);
        assertEq(uint32(TicketQueueStorage.owedById(address(game), writeKey, child) >> 8),
            childBefore + q.ticketWei / PriceLookupLib.priceForLevel(1) * 4);
        assertEq(TicketQueueStorage.owedById(address(game), writeKey, root), rootBefore);
        assertEq(lens.loanOf(address(game), child).principal, q.principal);
        assertEq(lens.loanOf(address(game), root).principal, 0);
    }

    // ---------------------------------------------------------------- borrow gates

    function test_BorrowGates() public {
        // Due level must be ahead.
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 0, type(uint256).max, 0);
        // Due level + 2 must sit inside the 100-level horizon.
        uint24 cl = lens.activeTicketLevelOf(address(game));
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, cl + 99, type(uint256).max, 0);
        // Slippage.
        uint256 principal = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 1, type(uint256).max, principal + 1);
        // Below the 0.05 ETH minimum.
        uint32 small = _giveWalletId(makeAddr("small"));
        _seedLevel(small, cl + 6, 8);
        assertLt(lens.previewBorrow(address(game), small, 1, type(uint256).max).principal, 0.05 ether);
        assertFalse(lens.previewBorrow(address(game), small, 1, type(uint256).max).eligible);
        vm.prank(makeAddr("small")); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(small, 1, type(uint256).max, 0);
        // One loan per account.
        _borrow(root, 1);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 2, type(uint256).max, 0);
        // Protocol roots.
        vm.prank(address(sdgnrs)); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(2, 1, type(uint256).max, 0);
    }

    function test_BorrowAndRepayDuringRngLock() public {
        _etch(); LoanSeeder(address(game)).lock(true); _unetch();
        assertTrue(lens.previewBorrow(address(game), root, 1, type(uint256).max).eligible, "the lock does not gate borrowing");
        uint256 principal = _borrow(root, 1);
        assertGt(principal, 0);
        uint256 owed = lens.loanOf(address(game), root).owed;
        vm.prank(seller); game.repay{value: owed}(root);
        assertEq(lens.loanOf(address(game), root).principal, 0);
    }

    function test_OnlyOwnerBorrowsAndOperatorsCannot() public {
        address operator = makeAddr("loan-operator");
        vm.prank(seller); game.setOperatorApproval(root, operator, true);
        vm.prank(operator); vm.expectRevert(DegenerusGameStorage.NotApproved.selector); game.borrow(root, 1, type(uint256).max, 0);
        vm.prank(makeAddr("stranger")); vm.expectRevert(DegenerusGameStorage.NotApproved.selector); game.borrow(root, 1, type(uint256).max, 0);
    }

    function test_GameOverBlocksBorrow() public {
        _endGame();
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 1, type(uint256).max, 0);
    }

    function test_MainSmurfCapButSmurfsBorrowFreely() public {
        _grantSmurfBase(seller, 8);
        uint32[] memory kids = new uint32[](6);
        for (uint256 i; i < 5; ++i) kids[i] = _child();
        assertTrue(lens.previewBorrow(address(game), root, 1, type(uint256).max).eligible, "five smurfs: the main may borrow");
        kids[5] = _child();
        assertFalse(lens.previewBorrow(address(game), root, 1, type(uint256).max).eligible, "six smurfs: the main may not");
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 1, type(uint256).max, 0);
        _seed(kids[5], 400, 0, 0);
        uint256 principal = _borrow(kids[5], 1);
        assertGt(principal, 0);
        assertEq(lens.loanOf(address(game), kids[5]).family, 1, "a smurf's seizure touches only itself");
    }

    function test_FamilySizeRecordedForMain() public {
        _child(); _child();
        _borrow(root, 1);
        assertEq(lens.loanOf(address(game), root).family, 3);
    }

    function test_OpenMainLoanBlocksSmurfCreationUntilRepaid() public {
        _borrow(root, 3);
        uint256 price = game.mintPrice();
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()")));
        game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        uint256 owed = lens.loanOf(address(game), root).owed;
        vm.prank(seller); game.repay{value: owed}(root);
        _child();
    }

    function test_MainAndSmurfLoansAreIndependent() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        _borrow(root, 2);
        _borrow(child, 1);
        assertGt(lens.loanOf(address(game), root).principal, 0);
        assertGt(lens.loanOf(address(game), child).principal, 0);
    }

    // ---------------------------------------------------------------- repay

    function _owedRef(uint256 p, uint256 start, uint256 due, uint256 lvl) private pure returns (uint256) {
        uint256 used = lvl > start ? lvl - start : 1;
        return p * (100 + (due - start) + 4 * used) / 100;
    }

    function test_RepayOwedFollowsUsedAndUnusedLevels() public {
        _seedLevel(root, 30, 400);
        uint256 p = _borrow(root, 20);
        DegenerusGameLens.LoanInfo memory info;
        uint24[5] memory lvls = [uint24(0), 1, 2, 10, 19];
        uint256[5] memory mult = [uint256(124), 124, 128, 160, 196];
        for (uint256 i; i < lvls.length; ++i) {
            _setLevel(lvls[i]);
            info = lens.loanOf(address(game), root);
            assertEq(info.owed, _owedRef(p, 0, 20, lvls[i]), "closed form");
            assertEq(info.owed, p * mult[i] / 100, "T = 20 table");
        }
        _setLevel(19);
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        vm.prank(seller); game.repay{value: p * 196 / 100}(root);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore + p * 196 / 100);
        assertEq(_pool(), poolBefore + p * 196 / 100);
        assertEq(lens.loanOf(address(game), root).principal, 0);
    }

    function test_OneLevelTermHasNoEarlyFee() public {
        uint256 p = _borrow(root, 1);
        assertEq(lens.loanOf(address(game), root).owed, p * 105 / 100);
    }

    function test_RepayFromClaimableKeepsSentinelAndConservesPool() public {
        uint256 p = _borrow(root, 4);
        uint256 owed = lens.loanOf(address(game), root).owed;
        _seed(root, 0, uint128(owed), 0);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("Insolvent()"))); game.repay(root);
        _seed(root, 0, uint128(owed + 1), 0);
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        vm.prank(seller); game.repay(root);
        assertEq(uint128(uint256(vm.load(address(game), keccak256(abi.encode(root, GameSlots.BALANCES_PACKED))))), 1);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore + owed);
        assertEq(_pool(), poolBefore, "internal move");
        assertGt(owed, p);
    }

    function test_RepayMixedAndOverpay() public {
        _borrow(root, 4);
        uint256 owed = lens.loanOf(address(game), root).owed;
        _seed(root, 0, uint128(owed / 2 + 1), 0);
        uint256 poolBefore = _pool();
        vm.prank(seller); game.repay{value: owed - owed / 2}(root);
        assertEq(_pool(), poolBefore + (owed - owed / 2));

        _borrow(root, 4);
        owed = lens.loanOf(address(game), root).owed;
        uint256 afkBefore = uint256(vm.load(address(game), keccak256(abi.encode(root, GameSlots.BALANCES_PACKED)))) >> 128;
        poolBefore = _pool();
        vm.prank(seller); game.repay{value: owed + 3 ether}(root);
        uint256 afkAfter = uint256(vm.load(address(game), keccak256(abi.encode(root, GameSlots.BALANCES_PACKED)))) >> 128;
        assertEq(afkAfter, afkBefore + 3 ether, "excess goes to the account's AFKing balance");
        assertEq(_pool(), poolBefore + owed + 3 ether);
    }

    function test_RepayAllowedDuringRngLockButNotAtDueLevel() public {
        _borrow(root, 2);
        _etch(); LoanSeeder(address(game)).lock(true); _unetch();
        uint256 owed = lens.loanOf(address(game), root).owed;
        vm.prank(seller); game.repay{value: owed}(root);

        _etch(); LoanSeeder(address(game)).lock(false); _unetch();
        _borrow(root, 2);
        _setLevel(2);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.repay{value: 10 ether}(root);
    }

    function test_OnlyOwnerRepays() public {
        _borrow(root, 2);
        address stranger = makeAddr("repay-stranger");
        vm.deal(stranger, 10 ether);
        vm.prank(stranger); vm.expectRevert(DegenerusGameStorage.NotApproved.selector); game.repay{value: 1 ether}(root);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.repay{value: 1 ether}(root + 9);
    }

    /// @dev A loan still open once the game is over was left by a VRF-dead ending (a VRF-alive
    ///      ending settles every loan before it ends; TerminalLoanSettlement). Repayment is closed
    ///      and nothing settles it later.
    function test_GameOverClosesRepaymentOfALoanTheEndingLeftOpen() public {
        uint256 p = _borrow(root, 3);
        _endGame();
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.repay{value: 10 ether}(root);
        assertEq(_payee(root), seller);
        assertEq(game.walletIdOf(seller), root);
        assertGt(p, 0);
    }

    function testFuzz_DueListSwapAndPop(uint256 seed) public {
        uint32[] memory ids = new uint32[](12);
        address[] memory owners = new address[](12);
        for (uint256 i; i < ids.length; ++i) {
            owners[i] = makeAddr(string(abi.encode("list", i)));
            vm.deal(owners[i], 100 ether);
            ids[i] = _giveWalletId(owners[i]);
            _seed(ids[i], 400, 0, 0);
        }
        _seed(2, 0, 100 ether, 0);
        bool[] memory open = new bool[](12);
        for (uint256 step; step < 40; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 k = seed % ids.length;
            uint24 due = uint24(2 + (seed >> 8) % 3);
            if (open[k]) {
                uint256 owed = lens.loanOf(address(game), ids[k]).owed;
                vm.prank(owners[k]); game.repay{value: owed}(ids[k]);
                open[k] = false;
            } else {
                uint256 principal = lens.previewBorrow(address(game), ids[k], due, type(uint256).max).principal;
                vm.prank(owners[k]); game.borrow(ids[k], due, type(uint256).max, principal);
                open[k] = true;
            }
            uint256 total;
            for (uint24 x = 2; x <= 4; ++x) {
                uint32[] memory list = lens.loansDue(address(game), x);
                total += list.length;
                for (uint256 j; j < list.length; ++j) {
                    DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), list[j]);
                    assertEq(info.dueLevel, x, "listed under its due level");
                    bytes32 word = vm.load(address(game), keccak256(abi.encode(uint256(list[j]), GameSlots.LOANS)));
                    assertEq(uint32(uint256(word) >> 152), j, "index field points back at its lane");
                }
            }
            uint256 expected;
            for (uint256 i; i < ids.length; ++i) if (open[i]) ++expected;
            assertEq(total, expected, "the lists hold exactly the open loans");
        }
    }

    // ---------------------------------------------------------------- borrow payout (ETH then stETH)

    function _stGame() private view returns (uint256) {
        return mockStETH.balanceOf(address(game));
    }

    function test_BorrowShortfallPaysEthBalanceThenStethRemainder() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        uint256 ethLeft = principal / 3;
        vm.deal(address(game), ethLeft);
        mockStETH.mint(address(game), principal);
        uint256 stGameBefore = _stGame();
        uint256 sellerEth = seller.balance;
        uint256 sellerSt = mockStETH.balanceOf(seller);
        vm.prank(seller);
        game.borrow(root, 1, type(uint256).max, principal);
        uint256 stPaid = principal - ethLeft;
        assertEq(seller.balance, sellerEth + ethLeft);
        assertApproxEqAbs(mockStETH.balanceOf(seller), sellerSt + stPaid, 1);
        assertEq(address(game).balance, 0);
        assertApproxEqAbs(_stGame(), stGameBefore - stPaid, 1);
    }

    function test_EthPlusStethShortfallRollsBackBorrow() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        vm.deal(address(game), principal / 2);
        mockStETH.mint(address(game), principal / 2 - 1);
        vm.prank(seller);
        vm.expectRevert(DegenerusGameStorage.TransferFailed.selector);
        game.borrow(root, 1, type(uint256).max, 0);
        assertEq(lens.loanOf(address(game), root).principal, 0);
        assertEq(lens.loansDue(address(game), 1).length, 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore);
    }

    function test_NoEthRequiredWhenStethCoversPrincipal() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), principal);
        uint256 sellerEth = seller.balance;
        vm.prank(seller);
        game.borrow(root, 1, type(uint256).max, principal);
        assertEq(seller.balance, sellerEth);
        assertApproxEqAbs(mockStETH.balanceOf(seller), principal, 1);
    }

    function test_RejectingRecipientRollsBackEntireBorrow() public {
        RejectLoanEth rejector = new RejectLoanEth();
        uint32 id = _giveWalletId(address(rejector));
        _seed(id, 400, 1 ether + 1, 2 ether);
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        vm.expectRevert(DegenerusGameStorage.TransferFailed.selector); rejector.borrow(address(game), 1);
        assertEq(lens.loanOf(address(game), id).principal, 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore);
    }

    function test_StethOnlyPaymentNeedsNoEthReceiver() public {
        RejectLoanEth rejector = new RejectLoanEth();
        uint32 id = _giveWalletId(address(rejector));
        _seed(id, 400, 0, 0);
        uint256 principal = lens.previewBorrow(address(game), id, 1, type(uint256).max).principal;
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), principal);
        rejector.borrow(address(game), 1);
        assertApproxEqAbs(mockStETH.balanceOf(address(rejector)), principal, 1);
    }

    function test_OwnCashStaysWithAccountWithoutChangingPrincipal() public {
        uint256 quote = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        _seed(root, 0, 2 ether + 1, 3 ether);
        assertEq(lens.previewBorrow(address(game), root, 1, type(uint256).max).principal, quote);
        _borrow(root, 1);
        assertEq(uint256(vm.load(address(game), keccak256(abi.encode(root, GameSlots.BALANCES_PACKED)))),
            uint256(2 ether + 1) | (uint256(3 ether) << 128));
    }

    // ---------------------------------------------------------------- lenders

    function test_VaultFallbackLendsAndKeepsConfiguredFloor() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, uint128(principal / 2 + 1), uint128(2 ether + principal - principal / 2));
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.setLiquidationBuyFallback(true, 2 ether);
        assertEq(lens.previewBorrow(address(game), root, 1, type(uint256).max).lenderId, 1);
        _borrow(root, 1);
        assertEq(game.claimableWinningsOf(address(vault)), 1);
        assertEq(game.afkingFundingOf(address(vault)), 2 ether);
        _seize(1);
        assertEq(_payee(root), address(vault));
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.setLiquidationBuyFallback(false, 2 ether);
        _seed(root, 0, 1 ether + 1, 0);
        uint32[] memory ids = new uint32[](1); ids[0] = root;
        vm.prank(address(vault));
        (uint256 ethOut, ) = game.sweepAccounts(ids);
        assertEq(ethOut, 1 ether);
    }

    function test_FallbackDisabledAndInsufficientFloorReject() public {
        _seed(2, 0, 1 ether, 0);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("Insolvent()"))); game.borrow(root, 1, type(uint256).max, 0);
        _seed(1, 0, 2 ether, 0);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE); vault.setLiquidationBuyFallback(true, 2 ether);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("Insolvent()"))); game.borrow(root, 1, type(uint256).max, 0);
    }

    function test_SdgnrsPriorityAndFloorEquality() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        _seed(2, 0, uint128(1 ether + principal), 0);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE); vault.setLiquidationBuyFallback(true, 0);
        assertEq(lens.previewBorrow(address(game), root, 1, type(uint256).max).lenderId, 2);
        _borrow(root, 1);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), 1 ether);
    }

    // ---------------------------------------------------------------- default = the old sale

    function test_SmurfQuotaStaysWithSeizedIdAndReplacementStartsAtZero() public {
        uint32 child = _child();
        uint256 quota = uint256(vm.load(address(game), GameSlotKeys.mintPacked(root))) >> 224;
        _seed(child, 400, 0, 0);
        _default(child);
        assertEq(uint256(vm.load(address(game), GameSlotKeys.mintPacked(root))) >> 224, quota);
        assertEq(lens.smurfCreationInfo(address(game), root).createdLifetime, 1);
        _default(root);
        assertEq(uint256(vm.load(address(game), GameSlotKeys.mintPacked(root))) >> 224, quota);
        assertFalse(lens.smurfCreationInfo(address(game), root).eligibleMain);
        uint32 replacement = _giveWalletId(seller);
        assertTrue(replacement != root);
        assertEq(lens.smurfCreationInfo(address(game), replacement).createdLifetime, 0);
        assertEq(game.walletIdentityOf(seller), root);
    }

    function testFuzz_LaterAwardsRemainCollectibleByAuthorizedCaller(bool vaultLender) public {
        uint32 child = _child();
        if (vaultLender) _fundVaultLender();
        _default(root);
        uint32 lender = vaultLender ? 1 : 2;
        address payee = vaultLender ? address(vault) : address(sdgnrs);
        assertEq(game.acquiredBuyer(root), lender);
        assertEq(game.acquiredBuyer(child), lender);
        address caller = vaultLender ? address(vault) : makeAddr("unrelated-sweeper");
        uint32[] memory ids = new uint32[](2); ids[0] = root; ids[1] = child;
        vm.prank(caller); game.sweepAccounts(ids);
        uint256 sellerBefore = seller.balance;
        for (uint24 day = 3; day <= 4; ++day) {
            _awardEth(child, 2 ether);
            _awardEth(root, 1 ether);
            vm.prank(address(game)); wwxrp.creditPrize(child, 77);
            vm.prank(address(game)); coinflip.creditFlip(child, 10_000);
            _resolve(day, true);
            uint256 lenderBefore = game.claimableWinningsOf(payee);
            // The root was explicitly seeded at zero; the created child already has its sentinel.
            uint256 expected = day == 3 ? 3 ether - 1 : 3 ether;
            vm.prank(caller); (uint256 ethOut, uint256 paid) = game.sweepAccounts(ids);
            assertEq(ethOut, expected);
            assertEq(game.claimableWinningsOf(payee), lenderBefore + expected);
            assertGt(paid, 0);
            uint256 prize = wwxrp.claimable(child);
            vm.prank(caller); assertEq(wwxrp.withdrawAcquired(child), prize);
        }
        assertEq(seller.balance, sellerBefore);
        if (!vaultLender) assertEq(caller.balance, 0);
    }

    function test_LaterVaultSweepCanActuallyBeWithdrawn() public {
        uint32 child = _child();
        _fundVaultLender();
        _default(root);
        _seed(1, 0, 1, 0);
        _awardEth(child, 3 ether);
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        vm.prank(address(vault));
        game.sweepAccounts(ids);
        uint256 before = address(vault).balance + mockStETH.balanceOf(address(vault));
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.playerAction(ContractAddresses.GAME, abi.encodeWithSignature("claimWinningsStethFirst()"), 0);
        assertEq(address(vault).balance + mockStETH.balanceOf(address(vault)), before + 3 ether);
    }

    function test_SmurfSdgnrsRewardsBurnAutomaticallyWithoutDeletingAccount() public {
        uint32 child = _child();
        _default(root);
        uint256 amount = 123e12;
        uint256 supply = sdgnrs.totalSupply();
        _etch(); LoanSeeder(address(game)).awardSdgnrs(child, amount); _unetch();
        assertEq(sdgnrs.totalSupply(), supply - amount);
        assertEq(game.acquiredBuyer(child), 2);
    }

    function test_SeizureBurnsEntireSdgnrsBalanceWithoutPayoutOrRedemption() public {
        _giveSdgnrs(seller, 10e12);
        uint24 due = _nextDue();
        uint256 principal = _borrow(root, due);
        uint256 supply = sdgnrs.totalSupply();
        uint256 backing = address(sdgnrs).balance;
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        uint256 beforeEth = seller.balance;
        assertEq(sdgnrs.balanceOf(seller), 10e12, "nothing burns while the loan is open");
        _seize(due);
        assertEq(sdgnrs.balanceOf(seller), 0);
        assertEq(sdgnrs.totalSupply(), supply - 10e12);
        assertEq(address(sdgnrs).balance, backing);
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved);
        assertEq(seller.balance, beforeEth, "the principal was paid at borrowing");
        assertGt(principal, 0);
    }

    function test_SmurfSeizureLeavesOwnerWalletSdgnrsBalanceAndSupply() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        _giveSdgnrs(seller, 10e12);
        uint256 supply = sdgnrs.totalSupply();
        _default(child);
        assertEq(sdgnrs.balanceOf(seller), 10e12);
        assertEq(sdgnrs.totalSupply(), supply);
        assertEq(game.walletIdOf(seller), root);
        assertEq(_payee(child), address(sdgnrs));
        assertEq(_payee(root), seller);
        _default(root);
        assertEq(sdgnrs.balanceOf(seller), 0);
    }

    function test_MainSeizureBurnsWholeNativeSdgnrsEvenWithChildren() public {
        _child();
        _giveSdgnrs(seller, 1);
        _giveSdgnrs(seller, 10e12);
        uint256 supply = sdgnrs.totalSupply();
        _default(root);
        assertEq(sdgnrs.balanceOf(seller), 0);
        assertEq(sdgnrs.totalSupply(), supply - 10e12 - 1);
        assertEq(game.walletIdOf(seller), 0);
    }

    function test_PreviouslySubmittedRedemptionRemainsWithSeizedAccount() public {
        GameFunding.credit(2, 10_000 ether);
        _primeCurrentDayRng();
        _giveSdgnrs(seller, 10e18);
        vm.prank(seller); sdgnrs.burn(5e18);
        (uint32 batch, , , uint256 beforeEscrow) = sdgnrs.redemptionBatchState();
        _default(root);
        (uint80 tokens, ) = sdgnrs.pendingRedemptions(root, batch);
        (, , , uint256 afterEscrow) = sdgnrs.redemptionBatchState();
        assertEq(tokens, 5e18);
        assertEq(afterEscrow, beforeEscrow);
        assertEq(_payee(root), address(sdgnrs));
    }

    function test_SeizureClosesRunForRemoval() public {
        _openSubscriptionDay();
        uint256 seat = _grantSeat(seller);
        vm.prank(seller); game.subscribe{value: 2 ether}(root, true, 1, seat);
        // Keep the borrowing main below the automatic-repayment threshold so this tests seizure.
        _seed(root, 400, 0, 0);
        uint24 due = _nextDue();
        _borrow(root, due);
        (uint256 lane, uint256 position1) = GameSlotKeys.subLane(address(game), root);
        assertGt(position1, 0, "the run continues during the loan");
        assertEq((lane >> 68) & 1, 0, "not pending removal during the loan");
        _seize(due);
        (lane, position1) = GameSlotKeys.subLane(address(game), root);
        assertGt(position1, 0, "the closed run waits in the set for the next pass");
        assertEq((lane >> 68) & 1, 1, "seizure marks the run for removal");
    }

    function test_ChildSweepDoesNotResumeSubscription() public {
        uint32 child = _child();
        _openSubscriptionDay();
        uint256 seat = _grantSeat(seller);
        vm.prank(seller); game.subscribe{value: 2 ether}(child, false, 1, seat);
        // Keep the borrowing main below the automatic-repayment threshold so this tests seizure.
        _seed(root, 0, 0, 0);
        _default(root);
        (uint256 lane,) = GameSlotKeys.subLane(address(game), child);
        assertEq((lane >> 68) & 1, 1, "a main's seizure stops its smurf's run");
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        game.sweepAccounts(ids);
        vm.prank(address(sdgnrs)); vm.expectRevert(bytes4(keccak256("NotApproved()"))); game.subscribe(child, false, 1, 0);
        (lane,) = GameSlotKeys.subLane(address(game), child);
        assertEq((lane >> 68) & 1, 1, "the sweep leaves the run closed");
    }

    function test_WholeFamilyTransfersWithoutPayingForChildren() public {
        uint32 child = _child();
        uint256 before = lens.previewBorrow(address(game), root, 1, type(uint256).max).principal;
        _seed(child, 8000, 4 ether, 3 ether);
        assertEq(lens.previewBorrow(address(game), root, 1, type(uint256).max).principal, before);
        uint256 table = uint256(keccak256(abi.encode(GameSlots.WALLETS)));
        bytes32 childElement = vm.load(address(game), bytes32(table + child));
        _default(root);
        assertEq(_payee(root), address(sdgnrs));
        assertEq(_payee(child), address(sdgnrs));
        assertEq(vm.load(address(game), bytes32(table + child)), childElement);
        assertEq(game.walletIdOf(seller), 0);
        (, , bool authorized) = game.resolveAccount(child, seller);
        assertFalse(authorized);
    }

    function test_SelectedCoinflipBankAndCarryBelongToLender() public {
        _coinState(root, 77, 1234, 2);
        uint256 before = coin.balanceOf(seller);
        _default(root);
        assertEq(coin.balanceOf(seller), before);
        (, uint256 flipOut) = game.sweepAccounts(_one(root));
        assertEq(flipOut, 1311);
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(root);
        assertFalse(enabled);
        assertEq(carry, 0);
    }

    function test_DelayedChildCollectionKeepsOrdinaryPostSeizureLoss() public {
        uint32 child = _child();
        _coinState(child, 71, 10_000, 2);
        _default(root);
        _resolve(3, false);
        (, uint256 flipOut) = game.sweepAccounts(_one(child));
        assertEq(flipOut, 71);
        (, flipOut) = game.sweepAccounts(_one(child));
        assertEq(flipOut, 0);
    }

    function test_OperatorLosesChildApprovalAtSeizure() public {
        uint32 child = _child();
        address operator = makeAddr("loan-operator");
        vm.startPrank(seller);
        game.setOperatorApproval(root, operator, true);
        game.setOperatorApproval(child, operator, true);
        vm.stopPrank();
        _default(root);
        (, , bool allowed) = game.resolveAccount(child, operator);
        assertFalse(allowed);
    }

    function test_StandaloneChildStaysWithItsLenderWhenParentLaterDefaults() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        _default(child);
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, 100 ether, 0);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE); vault.setLiquidationBuyFallback(true, 1 ether);
        _default(root);
        assertEq(_payee(root), address(vault));
        assertEq(_payee(child), address(sdgnrs));
    }

    function test_OrphanedSmurfLoanSeizesToItsOwnLenderAfterMainDefault() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        // The smurf borrows from sDGNRS, due later; the main borrows from the Vault, due first.
        _borrow(child, 2);
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, 100 ether, 0);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE); vault.setLiquidationBuyFallback(true, 1 ether);
        _borrow(root, 1);
        _seize(1);
        assertEq(_payee(child), address(vault), "the family moved with the main");
        vm.deal(address(vault), 10 ether);
        vm.prank(seller); vm.expectRevert(DegenerusGameStorage.NotApproved.selector); game.repay{value: 5 ether}(child);
        _seize(2);
        assertEq(_payee(child), address(sdgnrs), "explicit seizure overrides the inherited owner");
        assertEq(game.acquiredBuyer(child), 2);
        assertEq(_payee(root), address(vault));
    }

    function test_SweepDuplicatesConservePoolAndPayCallerNothing() public {
        uint32 child = _child();
        _seed(child, 0, 2 ether + 1, 3 ether);
        _default(root);
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        uint32[] memory ids = new uint32[](3); ids[0] = child; ids[1] = child; ids[2] = root;
        (uint256 ethOut, ) = game.sweepAccounts(ids);
        assertEq(ethOut, 5 ether);
        (ethOut, ) = game.sweepAccounts(ids);
        assertEq(ethOut, 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore + 5 ether);
        assertEq(_pool(), poolBefore);
    }

    function test_NewAccountDoesNotResetVotesOrDefaultReferralOwnership() public {
        vm.store(address(gnrus), bytes32(uint256(7)), bytes32(uint256(uint160(address(0xBEEF)))));
        vm.prank(address(game)); sdgnrs.transferFromPool(sDGNRS.Pool.Reward, seller, 1e12);
        vm.prank(seller); gnrus.vote(3);
        uint24 lvl = gnrus.currentLevel();
        _default(root);
        uint32 replacement = _giveWalletId(seller);
        assertNotEq(replacement, root);
        assertEq(game.walletIdentityOf(seller), root);
        assertTrue(gnrus.hasVoted(lvl, seller, 3));
        (address owner, uint32 codeId, ) = affiliate.affiliateCode(bytes32(uint256(uint160(seller))));
        assertEq(owner, address(sdgnrs)); assertEq(codeId, root);
    }

    function test_RepaidLoanIsNeverSeized() public {
        _child();
        uint24 due = _nextDue();
        _borrow(root, due);
        uint256 owed = lens.loanOf(address(game), root).owed;
        vm.prank(seller); game.repay{value: owed}(root);
        _seize(due);
        assertEq(_payee(root), seller);
        assertEq(game.walletIdOf(seller), root);
        _child();
    }

    // ---------------------------------------------------------------- unified sweeps

    function _one(uint32 id) private pure returns (uint32[] memory ids) {
        ids = new uint32[](1);
        ids[0] = id;
    }

    function test_SweepPlayerSmurfPreservesFundingAndRebuy() public {
        uint32 child = _child();
        _seed(child, 0, 2 ether + 1, 3 ether);
        _coinState(child, 77, 1234, 2);
        uint256 poolBefore = _pool();
        uint256 mainBefore = game.claimableWinningsOf(seller);
        uint256 flipBefore = coin.balanceOf(seller);
        uint256 walletBefore = seller.balance;
        vm.prank(seller);
        (uint256 ethOut, uint256 flipOut) = game.sweepAccounts(_one(child));
        assertEq(ethOut, 2 ether);
        assertEq(flipOut, 77);
        assertEq(game.claimableWinningsOf(seller), mainBefore + ethOut);
        assertEq(coin.balanceOf(seller), flipBefore + flipOut);
        assertEq(seller.balance, walletBefore, "ETH remains inside the game");
        assertEq(_pool(), poolBefore);
        (uint128 claimable, uint128 prepaid) = lens.accountBalances(address(game), child);
        assertEq(claimable, 1);
        assertEq(prepaid, 3 ether);
        (bool enabled,, uint256 carry,) = coinflip.coinflipAutoRebuyInfoById(child);
        assertTrue(enabled);
        assertEq(carry, 1234);
        vm.prank(seller);
        (ethOut, flipOut) = game.sweepAccounts(_one(child));
        assertEq(ethOut, 0);
        assertEq(flipOut, 0);
    }

    function test_SweepPlayerRequiresSourceApprovalAndCannotRedirect() public {
        uint32 child = _child();
        address operator = makeAddr("sweep-operator");
        _seed(child, 0, 2 ether + 1, 0);
        _coinState(child, 77, 0, 2);
        vm.prank(seller); game.setOperatorApproval(root, operator, true);
        vm.prank(operator); vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.sweepAccounts(_one(child));
        vm.prank(seller); game.setOperatorApproval(child, operator, true);
        uint256 mainBefore = game.claimableWinningsOf(seller);
        vm.prank(operator);
        game.sweepAccounts(_one(child));
        assertEq(game.claimableWinningsOf(seller), mainBefore + 2 ether);
        assertEq(coin.balanceOf(operator), 0);
        assertEq(operator.balance, 0);
        vm.prank(seller); game.setOperatorApproval(child, operator, false);
        vm.prank(operator); vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.sweepAccounts(_one(child));
    }

    function test_SweepSdgnrsFamilyPermissionlesslyAndRepeatedly() public {
        uint32 child = _child();
        _default(root);
        _seed(root, 0, 2 ether + 1, 3 ether);
        _seed(child, 0, 4 ether + 1, 5 ether);
        _coinState(child, 77, 1234, 2);
        uint32[] memory ids = new uint32[](3);
        ids[0] = root; ids[1] = child; ids[2] = child;
        uint256 mainBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 flipBefore = coinflip.coinflipAmountById(2);
        uint256 poolBefore = _pool();
        address stranger = makeAddr("sweep-stranger");
        vm.prank(stranger);
        (uint256 ethOut, uint256 flipOut) = game.sweepAccounts(ids);
        assertEq(ethOut, 14 ether);
        assertEq(flipOut, 1311);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), mainBefore + ethOut);
        assertEq(coinflip.coinflipAmountById(2), flipBefore + flipOut);
        assertEq(_pool(), poolBefore);
        assertEq(stranger.balance, 0);
        assertEq(coin.balanceOf(stranger), 0);
        vm.prank(stranger);
        (ethOut, flipOut) = game.sweepAccounts(ids);
        assertEq(ethOut, 0); assertEq(flipOut, 0);
        _awardEth(child, 1 ether);
        _coinState(child, 25, 0, 2);
        vm.prank(stranger);
        (ethOut, flipOut) = game.sweepAccounts(ids);
        assertEq(ethOut, 1 ether); assertEq(flipOut, 25);
        assertEq(game.acquiredBuyer(child), 2, "sweep preserves ownership and account");
    }

    function test_SweepVaultRequiresOwnerWrapperAndGameOnlyFlipHook() public {
        uint32 child = _child();
        _fundVaultLender();
        _default(root);
        _seed(child, 0, 2 ether + 1, 3 ether);
        _coinState(child, 77, 1234, 2);
        address stranger = makeAddr("vault-sweep-stranger");
        vm.prank(stranger); vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.sweepAccounts(_one(child));
        vm.prank(stranger); vm.expectRevert(bytes4(keccak256("OnlyDegenerusGame()")));
        coinflip.sweepAccountCoinflips(child);
        vm.prank(stranger); vm.expectRevert(bytes4(keccak256("NotVaultOwner()"))); vault.playerAction(
            ContractAddresses.GAME,
            abi.encodeWithSignature("sweepAccounts(uint32[])", _one(child)),
            0
        );
        uint256 mainBefore = game.claimableWinningsOf(address(vault));
        uint256 flipBefore = coin.vaultMintAllowance();
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        (uint256 ethOut, uint256 flipOut) = abi.decode(vault.playerAction(
            ContractAddresses.GAME,
            abi.encodeWithSignature("sweepAccounts(uint32[])", _one(child)),
            0
        ), (uint256, uint256));
        assertEq(ethOut, 5 ether); assertEq(flipOut, 1311);
        assertEq(game.claimableWinningsOf(address(vault)), mainBefore + ethOut);
        assertEq(coin.vaultMintAllowance(), flipBefore + flipOut);
    }

    function test_SweepUsesEachCurrentOwnerIncludingSeparatelySeizedChild() public {
        uint32 child = _child();
        _seed(child, 400, 0, 0);
        _default(child); // child belongs to sDGNRS
        _fundVaultLender();
        _default(root); // main belongs to vault
        _seed(child, 0, 1 ether + 1, 0);
        _seed(root, 0, 2 ether + 1, 0);
        uint32[] memory ids = new uint32[](2); ids[0] = child; ids[1] = root;
        uint256 sdBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 vaultBefore = game.claimableWinningsOf(address(vault));
        vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.sweepAccounts(ids);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), sdBefore, "unauthorized batch rolls back fully");
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.playerAction(ContractAddresses.GAME, abi.encodeWithSignature("sweepAccounts(uint32[])", ids), 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), sdBefore + 1 ether);
        assertEq(game.claimableWinningsOf(address(vault)), vaultBefore + 2 ether);
    }

    function test_SweepAcquiredCarryCannotEscapePendingLoss() public {
        uint32 child = _child();
        _coinState(child, 71, 10_000, 2);
        _default(root);
        vm.warp(block.timestamp + 1 days);
        (uint256 ethOut, uint256 flipOut) = game.sweepAccounts(_one(child));
        assertEq(ethOut, 0); assertEq(flipOut, 71);
        (bool enabled,, uint256 carry,) = coinflip.coinflipAutoRebuyInfoById(child);
        assertTrue(enabled); assertEq(carry, 10_000);
        _resolve(3, false);
        (, flipOut) = game.sweepAccounts(_one(child));
        assertEq(flipOut, 0, "pending loss must consume the carry");
        (enabled,, carry,) = coinflip.coinflipAutoRebuyInfoById(child);
        assertFalse(enabled); assertEq(carry, 0);
    }

    function test_SweepRejectsRootsInvalidIdsAndOversizedBatches() public {
        vm.expectRevert(DegenerusGameStorage.E.selector); game.sweepAccounts(_one(root));
        vm.expectRevert(DegenerusGameStorage.E.selector); game.sweepAccounts(_one(0));
        vm.expectRevert(DegenerusGameStorage.E.selector); game.sweepAccounts(_one(type(uint32).max));
        uint32[] memory ids = new uint32[](33);
        vm.expectRevert(DegenerusGameStorage.E.selector); game.sweepAccounts(ids);
        (uint256 ethOut, uint256 flipOut) = game.sweepAccounts(new uint32[](0));
        assertEq(ethOut, 0); assertEq(flipOut, 0);
        vm.expectRevert(bytes4(keccak256("OnlyDegenerusGame()"))); coinflip.sweepAccountCoinflips(root);
    }

    function test_SweepAtGameOverIncludesPrepaidAndRejectsAfterFinalSweep() public {
        uint32 child = _child();
        _seed(child, 0, 2 ether + 1, 3 ether);
        _endGame();
        uint256 mainBefore = game.claimableWinningsOf(seller);
        vm.prank(seller);
        (uint256 ethOut,) = game.sweepAccounts(_one(child));
        assertEq(ethOut, 5 ether);
        assertEq(game.claimableWinningsOf(seller), mainBefore + ethOut);
        _etch(); LoanSeeder(address(game)).finalSweep(); _unetch();
        vm.prank(seller); vm.expectRevert(DegenerusGameStorage.E.selector);
        game.sweepAccounts(_one(child));
    }

    function test_SweepOrdinaryClaimableAppliesSourceCashoutCurseOnlyOnce() public {
        uint32 child = _child();
        vm.warp(block.timestamp + 6 days);
        // Seed after advancing time so dailyIdx, the cashout staleness clock, advances too.
        _seed(child, 0, 1 ether + 1, 0);
        uint256 before = game.mintPackedOfId(child);
        vm.prank(seller); game.sweepAccounts(_one(child));
        uint256 after_ = game.mintPackedOfId(child);
        assertEq((after_ >> 203) & 31, ((before >> 203) & 31) + 2);
        vm.prank(seller); game.sweepAccounts(_one(child));
        assertEq(game.mintPackedOfId(child), after_, "empty repeat cannot add a curse");
    }

    function testFuzz_SweepConservesBalances(uint96 winnings, uint96 prepaid, bool acquired) public {
        uint32 child = _child();
        if (acquired) _default(root);
        _seed(child, 0, uint128(winnings) + 1, prepaid);
        address payee = acquired ? address(sdgnrs) : seller;
        uint256 mainBefore = game.claimableWinningsOf(payee);
        uint256 poolBefore = _pool();
        // Exercise the full batch bound with duplicates: only the first visit may debit ETH.
        uint32[] memory ids = new uint32[](32);
        for (uint256 i; i < ids.length; ++i) ids[i] = child;
        vm.prank(seller);
        (uint256 ethOut,) = game.sweepAccounts(ids);
        uint256 expected = uint256(winnings) + (acquired ? prepaid : 0);
        assertEq(ethOut, expected);
        assertEq(game.claimableWinningsOf(payee), mainBefore + expected);
        assertEq(_pool(), poolBefore);
        (uint128 claimable, uint128 funding) = lens.accountBalances(address(game), child);
        assertEq(claimable, 1);
        assertEq(funding, acquired ? 0 : prepaid);
    }
}
