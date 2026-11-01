// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {AccountFixture} from "./AccountFixture.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {WalletTableLib} from "../../contracts/libraries/WalletTableLib.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @title AcquiredAccountAuthority -- authority over an ordinary account before and after a
///        production seizure by each lender, the seller's fresh account, and payee-resolver parity
/// @notice An ordinary account is controlled by its wallet and the operators it approves. A loan
///         default hands it to the lender: the lender is payee and authority, the seller's key and
///         every prior operator lose authority, the seller's default ID clears, and the seller's
///         wallet can register a fresh account that inherits nothing. Game `_payee` (via
///         `resolveAccount`), `WalletTableLib.ownerOf` and `Lens.walletOfId` agree throughout.
contract AcquiredAccountAuthorityTest is AccountFixture {
    error E();
    error NotApproved();

    /// @dev Coinflip.playerState root and flipsClaimableDay slot (scripts/layout/golden/Coinflip.json).
    uint256 private constant CF_PLAYER_STATE_ROOT = 2;
    uint256 private constant CF_CLAIMABLE_DAY_SLOT = 4;

    address private seller;
    uint32 private id;
    address private operator;
    address private stranger;

    function setUp() public {
        _setUpAccountFixture();
        (seller, id) = _wallet("acq_seller");
        operator = makeAddr("acq_operator");
        stranger = makeAddr("acq_stranger");
        vm.deal(operator, 100 ether);
        vm.deal(stranger, 100 ether);
        vm.prank(seller);
        game.setOperatorApproval(id, operator, true);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _payee(uint32 who) private view returns (address payee) {
        (, payee,) = game.resolveAccount_g7029(who, address(0));
    }

    function _authorized(uint32 who, address caller) private view returns (bool ok) {
        (,, ok) = game.resolveAccount_g7029(who, caller);
    }

    /// @dev Every resolver names `expected` for allocated `who`.
    function _assertResolversAgree(uint32 who, address expected) private view {
        assertEq(_payee(who), expected, "Game payee");
        assertEq(WalletTableLib.ownerOf(who), expected, "WalletTableLib.ownerOf");
        assertEq(accountLens.walletOfId(address(game), who), expected, "Lens.walletOfId");
    }

    /// @dev Game rejects `who` with `E`; the external resolvers read zero.
    function _assertUnallocated(uint32 who) private {
        vm.expectRevert(E.selector);
        game.resolveAccount_g7029(who, address(0));
        assertEq(WalletTableLib.ownerOf(who), address(0), "WalletTableLib.ownerOf zero");
        assertEq(accountLens.walletOfId(address(game), who), address(0), "Lens.walletOfId zero");
    }

    function _cfState(uint32 who) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(who), CF_PLAYER_STATE_ROOT));
    }

    /// @dev Settled coinflip winnings with nothing left to walk.
    function _seedCoinflipClaimable(uint32 who, uint256 amount) private {
        uint256 latest = uint24(uint256(vm.load(address(coinflip), bytes32(CF_CLAIMABLE_DAY_SLOT))));
        vm.store(address(coinflip), _cfState(who), bytes32((latest << 128) | amount));
    }

    function _creditWwxrp(uint32 who, uint256 amount) private {
        vm.prank(address(game));
        wwxrp.creditPrize(who, amount);
    }

    // ---------------------------------------------------------------------
    // Ordinary control
    // ---------------------------------------------------------------------

    function test_OrdinaryAccount_WalletAndOperatorControlStrangerDoesNot() public {
        assertTrue(_authorized(id, seller), "the wallet");
        assertTrue(_authorized(id, operator), "its operator");
        assertFalse(_authorized(id, stranger), "a stranger");
        assertEq(game.acquiredBuyer(id), 0);
        ext.x_creditClaimable(id, 1 ether);
        uint256 raw = _fixtureClaimable(id);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.claimClaimable(id);
        uint256 before = seller.balance;
        vm.prank(operator);
        game.claimClaimable(id);
        assertEq(seller.balance - before, raw - 1, "the operator's claim paid the wallet");
        assertEq(operator.balance, 100 ether, "the operator receives nothing");
    }

    // ---------------------------------------------------------------------
    // Seizure: authority and routing
    // ---------------------------------------------------------------------

    function test_SeizureByVault_AuthorityAndPendingProceeds() public { _seizure(VAULT_ID); }

    function test_SeizureBySdgnrs_AuthorityAndPendingProceeds() public { _seizure(SDGNRS_ID); }

    function _seizure(uint32 lender) private {
        address lenderAddr = _lenderAddress(lender);
        // Pending results created before the seizure, below the loan's full-term amount.
        ext.x_creditClaimable(id, 0.01 ether);
        _creditWwxrp(id, 77 ether);
        _seedCoinflipClaimable(id, 9_000);
        // The seller's native sDGNRS burns at seizure.
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, seller, 3e12);
        assertGt(sdgnrs.balanceOf(seller), 0, "fixture: the seller holds sDGNRS");

        _acquire(seller, id, lender);

        // Ownership: one hop to the lender.
        (address key, address payee, bool sellerOk) = game.resolveAccount_g7029(id, seller);
        assertEq(key, seller, "the key stays the former borrower");
        assertEq(payee, lenderAddr, "the lender is the payee");
        assertFalse(sellerOk, "the seller lost authority");
        assertFalse(_authorized(id, operator), "the prior operator lost authority");
        assertTrue(_authorized(id, lenderAddr), "the lender acts for the account");
        assertEq(game.walletIdOf_g3120(seller), 0, "the seller's default ID cleared");
        assertEq(sdgnrs.balanceOf(seller), 0, "the seller's native sDGNRS burned");
        _assertResolversAgree(id, lenderAddr);

        // The seller and the prior operator are rejected on the account's doors.
        address[2] memory losers = [seller, operator];
        for (uint256 i; i < 2; ++i) {
            vm.startPrank(losers[i]);
            vm.expectRevert(NotApproved.selector);
            game.claimClaimable(id);
            vm.expectRevert(NotApproved.selector);
            game.withdrawAfkingFunding(id, 1);
            vm.expectRevert(NotApproved.selector);
            game.setOperatorApproval(id, stranger, true);
            uint256 price = game.mintPrice();
            vm.expectRevert(NotApproved.selector);
            game.purchaseOrderFor{value: price}(id, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
            vm.expectRevert(WWXRP.NotApproved.selector);
            wwxrp.withdraw(id, 0);
            vm.stopPrank();
        }

        // Pending ETH and settled FLIP collect to the lender under its destination rule: anyone
        // for sDGNRS, the Vault itself for the Vault.
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        if (lender == VAULT_ID) {
            vm.prank(stranger);
            vm.expectRevert(NotApproved.selector);
            game.sweepAccounts(ids);
        }
        uint256 lenderClaimable = _fixtureClaimable(lender);
        uint256 lenderFlip = _lenderFlipMark(lender);
        uint256 owedEth = _fixtureClaimable(id) - 1 + _fixtureAfking(id);
        _expectLenderFlip(lender);
        vm.prank(lender == VAULT_ID ? lenderAddr : stranger);
        (uint256 eth, uint256 flipOut) = game.sweepAccounts(ids);
        assertEq(eth, owedEth, "every pending wei collected");
        assertGe(eth, 0.01 ether - 1, "the pre-seizure credit is included");
        assertEq(_fixtureClaimable(lender) - lenderClaimable, eth, "to the lender's claimable");
        assertEq(_fixtureClaimable(id), 1, "the account keeps its sentinel");
        assertEq(flipOut, 9_000, "the settled FLIP collected");
        _assertLenderFlip(lender, lenderFlip, flipOut);
        assertEq(coin.balanceOf(seller), 0, "nothing to the seller");

        // WWXRP winnings collect permissionlessly to the lender.
        uint256 w0 = wwxrp.balanceOf(lenderAddr);
        vm.prank(stranger);
        assertEq(wwxrp.withdrawAcquired(id), 77 ether);
        assertEq(wwxrp.balanceOf(lenderAddr) - w0, 77 ether, "WWXRP minted to the lender");
        assertEq(wwxrp.balanceOf(seller) + wwxrp.balanceOf(stranger), 0);
    }

    function test_WithdrawAcquiredRejectsOrdinaryAccounts() public {
        _creditWwxrp(id, 5);
        vm.expectRevert(WWXRP.NotApproved.selector);
        wwxrp.withdrawAcquired(id);
    }

    function test_SweepRejectsOrdinaryAccounts() public {
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        vm.prank(seller);
        vm.expectRevert(E.selector);
        game.sweepAccounts(ids);
    }

    // ---------------------------------------------------------------------
    // The seller's fresh account
    // ---------------------------------------------------------------------

    function test_SellerRegistersAFreshAccount_Vault() public { _fresh(VAULT_ID); }

    function test_SellerRegistersAFreshAccount_Sdgnrs() public { _fresh(SDGNRS_ID); }

    function _fresh(uint32 lender) private {
        uint256 price = game.mintPrice();
        vm.prank(seller);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 oldMint = _fixtureMint(id);
        assertGt(oldMint, 0, "fixture: the old account has history");
        _acquire(seller, id, lender);

        // The self shorthand registers a new account on the seller's next paying action.
        vm.prank(seller);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint32 fresh = game.walletIdOf_g3120(seller);
        assertTrue(fresh != 0 && fresh != id, "a new ID");
        assertEq(game.acquiredBuyer(fresh), 0, "an ordinary account");
        _assertResolversAgree(fresh, seller);
        assertTrue(_authorized(fresh, seller), "the seller controls it");
        assertFalse(_authorized(fresh, operator), "the old approval does not carry over");
        DegenerusGameLens.LoanInfo memory loan = accountLens.loanOf(address(game), fresh);
        assertEq(loan.principal, 0, "no debt inherited");
        assertEq(loan.lenderId, 0);
        assertEq((_fixtureMint(fresh) >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1, 0, "no deity inherited");
        assertEq(
            (_fixtureMint(fresh) >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24,
            1,
            "only its own purchase counts"
        );
        // The old account stays with its lender.
        _assertResolversAgree(id, _lenderAddress(lender));
        assertFalse(_authorized(id, seller));
    }

    // ---------------------------------------------------------------------
    // Payee resolvers agree
    // ---------------------------------------------------------------------

    function test_ResolversAgree_ReservedOrdinaryUnallocated() public {
        _assertResolversAgree(VAULT_ID, ContractAddresses.VAULT);
        _assertResolversAgree(SDGNRS_ID, ContractAddresses.SDGNRS);
        _assertResolversAgree(3, ContractAddresses.GNRUS);
        _assertResolversAgree(id, seller);
        _assertUnallocated(0);
        _assertUnallocated(id + 1);
        _assertUnallocated(type(uint32).max);
    }

    function test_ResolversAgree_AcquiredByEachLender() public {
        // A second account borrows from sDGNRS, due one level later.
        (address other, uint32 otherId) = _wallet("acq_second_seller");
        ext.x_seedLevel(otherId, 8, 400);
        ext.x_creditClaimable(SDGNRS_ID, 500 ether);
        DegenerusGameLens.LoanQuote memory q = accountLens.previewBorrow(address(game), otherId, 2, type(uint256).max);
        assertEq(q.lenderId, SDGNRS_ID, "fixture: sDGNRS lends");
        uint256 keep = _fixtureBalances(otherId);
        vm.prank(other);
        game.borrow(otherId, 2, type(uint256).max, q.principal);
        ext.x_setBalances(otherId, uint128(keep), uint128(keep >> 128));

        _acquire(seller, id, VAULT_ID);
        _assertResolversAgree(id, ContractAddresses.VAULT);
        _assertResolversAgree(otherId, other);

        ext.x_enterDue(2);
        ext.x_runSeizure();
        assertEq(game.acquiredBuyer(otherId), SDGNRS_ID);
        _assertResolversAgree(otherId, ContractAddresses.SDGNRS);
        _assertResolversAgree(id, ContractAddresses.VAULT);
        _assertResolversAgree(VAULT_ID, ContractAddresses.VAULT);
        _assertResolversAgree(SDGNRS_ID, ContractAddresses.SDGNRS);
        _assertUnallocated(otherId + 1);
    }
}
