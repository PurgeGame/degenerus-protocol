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

/// @dev Etched over the Game for state seeding. `enterDue` jumps `level` to a due level and arms
///      its seizure the way `prepareRequestBoundary` does; `seize` runs the production seizure
///      worker in the Game's context.
contract LoanSeeder is DegenerusGameStorage {
    function end() external { gameOver = true; }
    function lock(bool on) external { rngLockedFlag = on; }
    function setLevel(uint24 level_) external { level = level_; }
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
        claimablePool = uint128(uint256(claimablePool) + claimable + prepaid - uint128(old) - (old >> 128));
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
            game.call(abi.encodeWithSignature("borrow(uint32,uint24,uint256)", uint32(0), due, uint256(0)));
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
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, due);
        assertTrue(q.eligible, "borrow eligible");
        principal = q.principal;
        vm.prank(seller);
        game.borrow(id, due, principal);
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
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(true, 1 ether);
    }

    function _awardEth(uint32 id, uint256 amount) private {
        vm.deal(address(sdgnrs), address(sdgnrs).balance + amount);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: amount}(id, amount);
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
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), fresh, cl);
        assertEq(q.principal, expected, "every level from due + 2 counts at its distance rate");
        assertEq(_rate(2), 1000);
        assertEq(_rate(20), 500);
        assertEq(_rate(100), 200);
        // A later due level drops the near levels from the collateral.
        DegenerusGameLens.LoanQuote memory later = lens.previewBorrow(address(game), fresh, uint24(cl + 9));
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
        assertEq(lens.previewBorrow(address(game), fresh, cl).principal, expected);
    }

    function test_SameQuoteOnDifferentDays() public {
        uint256 first = lens.previewBorrow(address(game), root, 1).principal;
        _resolve(9, false);
        _seed(2, 0, 100 ether, 0);
        assertEq(lens.previewBorrow(address(game), root, 1).principal, first, "no daily randomness");
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

    // ---------------------------------------------------------------- borrow gates

    function test_BorrowGates() public {
        // Due level must be ahead.
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 0, 0);
        // Due level + 2 must sit inside the 100-level horizon.
        uint24 cl = lens.activeTicketLevelOf(address(game));
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, cl + 99, 0);
        // Slippage.
        uint256 principal = lens.previewBorrow(address(game), root, 1).principal;
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 1, principal + 1);
        // Below the 0.05 ETH minimum.
        uint32 small = _giveWalletId(makeAddr("small"));
        _seedLevel(small, cl + 6, 8);
        assertLt(lens.previewBorrow(address(game), small, 1).principal, 0.05 ether);
        assertFalse(lens.previewBorrow(address(game), small, 1).eligible);
        vm.prank(makeAddr("small")); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(small, 1, 0);
        // One loan per account.
        _borrow(root, 1);
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 2, 0);
        // Protocol roots.
        vm.prank(address(sdgnrs)); vm.expectRevert(); game.borrow(2, 1, 0);
    }

    function test_BorrowAndRepayDuringRngLock() public {
        _etch(); LoanSeeder(address(game)).lock(true); _unetch();
        assertTrue(lens.previewBorrow(address(game), root, 1).eligible, "the lock does not gate borrowing");
        uint256 principal = _borrow(root, 1);
        assertGt(principal, 0);
        uint256 owed = lens.loanOf(address(game), root).owed;
        vm.prank(seller); game.repay{value: owed}(root);
        assertEq(lens.loanOf(address(game), root).principal, 0);
    }

    function test_OnlyOwnerBorrowsAndOperatorsCannot() public {
        address operator = makeAddr("loan-operator");
        vm.prank(seller); game.setOperatorApproval(root, operator, true);
        vm.prank(operator); vm.expectRevert(DegenerusGameStorage.NotApproved.selector); game.borrow(root, 1, 0);
        vm.prank(makeAddr("stranger")); vm.expectRevert(DegenerusGameStorage.NotApproved.selector); game.borrow(root, 1, 0);
    }

    function test_GameOverBlocksBorrow() public {
        _endGame();
        vm.prank(seller); vm.expectRevert(); game.borrow(root, 1, 0);
    }

    function test_MainSmurfCapButSmurfsBorrowFreely() public {
        _grantSmurfBase(seller, 8);
        uint32[] memory kids = new uint32[](6);
        for (uint256 i; i < 5; ++i) kids[i] = _child();
        assertTrue(lens.previewBorrow(address(game), root, 1).eligible, "five smurfs: the main may borrow");
        kids[5] = _child();
        assertFalse(lens.previewBorrow(address(game), root, 1).eligible, "six smurfs: the main may not");
        vm.prank(seller); vm.expectRevert(bytes4(keccak256("E()"))); game.borrow(root, 1, 0);
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

    function test_GameOverBorrowerKeepsEverything() public {
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
                uint256 principal = lens.previewBorrow(address(game), ids[k], due).principal;
                vm.prank(owners[k]); game.borrow(ids[k], due, principal);
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
        uint256 principal = lens.previewBorrow(address(game), root, 1).principal;
        uint256 ethLeft = principal / 3;
        vm.deal(address(game), ethLeft);
        mockStETH.mint(address(game), principal);
        uint256 stGameBefore = _stGame();
        uint256 sellerEth = seller.balance;
        uint256 sellerSt = mockStETH.balanceOf(seller);
        vm.prank(seller);
        game.borrow(root, 1, principal);
        uint256 stPaid = principal - ethLeft;
        assertEq(seller.balance, sellerEth + ethLeft);
        assertApproxEqAbs(mockStETH.balanceOf(seller), sellerSt + stPaid, 1);
        assertEq(address(game).balance, 0);
        assertApproxEqAbs(_stGame(), stGameBefore - stPaid, 1);
    }

    function test_EthPlusStethShortfallRollsBackBorrow() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1).principal;
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        vm.deal(address(game), principal / 2);
        mockStETH.mint(address(game), principal / 2 - 1);
        vm.prank(seller);
        vm.expectRevert(DegenerusGameStorage.TransferFailed.selector);
        game.borrow(root, 1, 0);
        assertEq(lens.loanOf(address(game), root).principal, 0);
        assertEq(lens.loansDue(address(game), 1).length, 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), lenderBefore);
    }

    function test_NoEthRequiredWhenStethCoversPrincipal() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1).principal;
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), principal);
        uint256 sellerEth = seller.balance;
        vm.prank(seller);
        game.borrow(root, 1, principal);
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
        uint256 principal = lens.previewBorrow(address(game), id, 1).principal;
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), principal);
        rejector.borrow(address(game), 1);
        assertApproxEqAbs(mockStETH.balanceOf(address(rejector)), principal, 1);
    }

    function test_OwnCashStaysWithAccountWithoutChangingPrincipal() public {
        uint256 quote = lens.previewBorrow(address(game), root, 1).principal;
        _seed(root, 0, 2 ether + 1, 3 ether);
        assertEq(lens.previewBorrow(address(game), root, 1).principal, quote);
        _borrow(root, 1);
        assertEq(uint256(vm.load(address(game), keccak256(abi.encode(root, GameSlots.BALANCES_PACKED)))),
            uint256(2 ether + 1) | (uint256(3 ether) << 128));
    }

    // ---------------------------------------------------------------- lenders

    function test_VaultFallbackLendsAndKeepsConfiguredFloor() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1).principal;
        _seed(2, 0, 1 ether, 0);
        _seed(1, 0, uint128(principal / 2), uint128(2 ether + principal - principal / 2));
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(true, 2 ether);
        assertEq(lens.previewBorrow(address(game), root, 1).lenderId, 1);
        _borrow(root, 1);
        assertEq(game.claimableWinningsOf(address(vault)), 0);
        assertEq(game.afkingFundingOf(address(vault)), 2 ether);
        _seize(1);
        assertEq(_payee(root), address(vault));
        vm.prank(ContractAddresses.CREATOR);
        vault.setLiquidationBuyFallback(false, 2 ether);
        _seed(root, 0, 1 ether + 1, 0);
        uint32[] memory ids = new uint32[](1); ids[0] = root;
        assertEq(game.harvestAcquiredAccounts(1, ids), 1 ether);
    }

    function test_FallbackDisabledAndInsufficientFloorReject() public {
        _seed(2, 0, 1 ether, 0);
        vm.prank(seller); vm.expectRevert(); game.borrow(root, 1, 0);
        _seed(1, 0, 2 ether, 0);
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 2 ether);
        vm.prank(seller); vm.expectRevert(); game.borrow(root, 1, 0);
    }

    function test_SdgnrsPriorityAndFloorEquality() public {
        uint256 principal = lens.previewBorrow(address(game), root, 1).principal;
        _seed(2, 0, uint128(1 ether + principal), 0);
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 0);
        assertEq(lens.previewBorrow(address(game), root, 1).lenderId, 2);
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

    function testFuzz_LaterAwardsRemainPermissionlesslyCollectible(bool vaultLender) public {
        uint32 child = _child();
        if (vaultLender) _fundVaultLender();
        _default(root);
        uint32 lender = vaultLender ? 1 : 2;
        address payee = vaultLender ? address(vault) : address(sdgnrs);
        assertEq(game.acquiredBuyer(root), lender);
        assertEq(game.acquiredBuyer(child), lender);
        address caller = makeAddr("unrelated-sweeper");
        uint32[] memory ids = new uint32[](2); ids[0] = root; ids[1] = child;
        vm.prank(caller); assertEq(game.harvestAcquiredAccounts(lender, ids), 0);
        uint256 sellerBefore = seller.balance;
        for (uint24 day = 3; day <= 4; ++day) {
            _awardEth(child, 2 ether);
            _awardEth(root, 1 ether);
            vm.prank(address(game)); wwxrp.creditPrize(child, 77);
            vm.prank(address(game)); coinflip.creditFlip(child, 10_000);
            _resolve(day, true);
            uint256 lenderBefore = game.claimableWinningsOf(payee);
            uint256 expected = day == 3 ? 3 ether - 2 : 3 ether;
            vm.prank(caller); assertEq(game.harvestAcquiredAccounts(lender, ids), expected);
            assertEq(game.claimableWinningsOf(payee), lenderBefore + expected);
            uint256 prize = wwxrp.claimable(child);
            vm.prank(caller); assertEq(wwxrp.withdrawAcquired(child), prize);
            vm.prank(caller); uint256 paid = coinflip.claimAcquiredCoinflips(child);
            assertGt(paid, 0);
        }
        assertEq(seller.balance, sellerBefore);
        assertEq(caller.balance, 0);
    }

    function test_LaterVaultHarvestCanActuallyBeWithdrawn() public {
        uint32 child = _child();
        _fundVaultLender();
        _default(root);
        _seed(1, 0, 1, 0);
        _awardEth(child, 3 ether);
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        game.harvestAcquiredAccounts(1, ids);
        uint256 before = address(vault).balance + mockStETH.balanceOf(address(vault));
        vm.prank(ContractAddresses.CREATOR);
        vault.gameClaimWinnings();
        assertEq(address(vault).balance + mockStETH.balanceOf(address(vault)), before + 3 ether - 1);
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
        vm.deal(address(sdgnrs), 10_000 ether);
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

    function test_SeizureLeavesExternalFundingAndRevokesConsent() public {
        address funder = makeAddr("external-funder");
        uint32 funderId = _giveWalletId(funder);
        vm.prank(funder); game.setAfkingFundingApproval(0, root, true);
        uint256 seat = _grantSeat(seller);
        vm.prank(seller); game.subscribe{value: 2 ether}(root, false, true, 1, funderId, seat);
        uint256 otherMoney = game.afkingFundingOf(funder);
        uint24 due = _nextDue();
        _borrow(root, due);
        assertEq(uint8(GameSlotKeys.subWord(address(game), root)), 1, "the run continues during the loan");
        _seize(due);
        assertEq(uint8(GameSlotKeys.subWord(address(game), root)), 0, "seizure stops the run");
        assertEq(game.afkingFundingOf(funder), otherMoney);
        assertFalse(game.afkingFundingApproved(funderId, root));
    }

    function test_ChildHarvestDoesNotResumeSubscription() public {
        uint32 child = _child();
        uint256 seat = _grantSeat(seller);
        vm.prank(seller); game.subscribe{value: 2 ether}(child, false, false, 1, root, seat);
        _default(root);
        assertEq(uint8(GameSlotKeys.subWord(address(game), child)), 0, "a main's seizure stops its smurf's run");
        uint32[] memory ids = new uint32[](1); ids[0] = child;
        game.harvestAcquiredAccounts(2, ids);
        vm.prank(address(sdgnrs)); vm.expectRevert(); game.subscribe(child, false, false, 1, 0, 0);
    }

    function test_WholeFamilyTransfersWithoutPayingForChildren() public {
        uint32 child = _child();
        uint256 before = lens.previewBorrow(address(game), root, 1).principal;
        _seed(child, 8000, 4 ether, 3 ether);
        assertEq(lens.previewBorrow(address(game), root, 1).principal, before);
        uint256 table = uint256(keccak256(abi.encode(uint256(13))));
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
        assertEq(coinflip.claimAcquiredCoinflips(root), 1311);
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(root);
        assertFalse(enabled);
        assertEq(carry, 0);
    }

    function test_DelayedChildCollectionKeepsOrdinaryPostSeizureLoss() public {
        uint32 child = _child();
        _coinState(child, 71, 10_000, 2);
        _default(root);
        _resolve(3, false);
        assertEq(coinflip.claimAcquiredCoinflips(child), 71);
        assertEq(coinflip.claimAcquiredCoinflips(child), 0);
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
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 1 ether);
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
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 1 ether);
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

    function test_HarvestDuplicatesConservePoolAndPayCallerNothing() public {
        uint32 child = _child();
        _seed(child, 0, 2 ether + 1, 3 ether);
        _default(root);
        uint256 lenderBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = _pool();
        uint32[] memory ids = new uint32[](3); ids[0] = child; ids[1] = child; ids[2] = root;
        assertEq(game.harvestAcquiredAccounts(2, ids), 5 ether);
        assertEq(game.harvestAcquiredAccounts(2, ids), 0);
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
}
