// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {LiquidationQuote} from "../../contracts/interfaces/ILiquidation.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

contract IdReviewOperator {
    function configure(Coinflip flip, uint32 id) external {
        flip.setCoinflipAutoRebuy(id, true, 0);
    }
}

/// @dev Tries both the former owner and a previously approved operator DURING the ETH callback.
contract IdReviewSeller {
    DegenerusGame private game;
    Coinflip private flip;
    IdReviewOperator private operator;
    uint32 private root;
    uint32 private child;
    bool private armed;
    bool public callbackRan;
    uint32 public replacement;
    uint32 public replacementChild;

    function sell(DegenerusGame game_, Coinflip flip_, IdReviewOperator operator_, uint32 root_, uint32 child_) external {
        game = game_;
        flip = flip_;
        operator = operator_;
        root = root_;
        child = child_;
        armed = true;
        game.liquidateAccount(root, 1);
    }

    receive() external payable {
        if (!armed) return;
        armed = false;
        callbackRan = true;
        for (uint256 i; i < 2; ++i) {
            uint32 id = i == 0 ? root : child;
            (,, bool authorized) = game.resolveAccount(id, address(this));
            require(!authorized, "seller still authorized in callback");
            (,, authorized) = game.resolveAccount(id, address(operator));
            require(!authorized, "operator still authorized in callback");
            (bool ok,) = address(game).call(abi.encodeWithSignature("claimWinnings(uint32,uint256)", id, 1));
            require(!ok, "seller withdrew sold credit");
            (ok,) = address(game).call(abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", id, 1));
            require(!ok, "seller withdrew sold funding");
            (ok,) = address(game).call(abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", id, address(operator), true));
            require(!ok, "seller restored stale approval");
            (ok,) = address(operator).call(abi.encodeCall(IdReviewOperator.configure, (flip, id)));
            require(!ok, "operator changed sold account");
        }
        // Re-register through a real paid door, then allocate a child while the sale is in flight.
        uint256 price = game.mintPrice();
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        replacement = game.walletIdOf(address(this));
        replacementChild = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }
}

contract IdAuthorizationReviewTest is DeployProtocol {
    address private owner;
    uint32 private root;
    uint32 private child;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 200; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) mockVRF.fulfillRandomWords(request, 0x1DA0D17);
            }
            if (game.rngComplete() && !game.advanceDue()) break;
            game.mineFlip{gas: 15_000_000}();
        }
        assertTrue(game.rngComplete());
        owner = address(new IdReviewSeller());
        root = _giveWalletId(owner);
        vm.deal(owner, 100 ether);
        uint256 price = game.mintPrice();
        vm.prank(owner);
        child = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _accountDigest(uint32 id) private view returns (bytes32) {
        return keccak256(abi.encode(
            game.extsload(GameSlotKeys.walletElement(id)),
            game.extsload(GameSlotKeys.mintPacked(id)),
            game.extsload(GameSlotKeys.balances(id)),
            game.extsload(GameSlotKeys.byId(id, GameSlots.BOON_PACKED)),
            coinflip.coinflipAmountById(id), wwxrp.claimable(id)
        ));
    }

    function _award(uint32 id, uint256 amount) private {
        vm.deal(address(sdgnrs), amount);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: amount}(id, amount);
    }

    function test_SaleCallbackCannotReuseOldOwnershipOrOperatorApprovals() public {
        IdReviewOperator operator = new IdReviewOperator();
        vm.startPrank(owner);
        game.setOperatorApproval(root, address(operator), true);
        game.setOperatorApproval(child, address(operator), true);
        game.purchaseWhalePass{value: 2.4 ether}(root, 1, 0);
        game.depositAfkingFunding{value: 0.1 ether}(root);
        game.depositAfkingFunding{value: 0.1 ether}(child);
        vm.stopPrank();
        // Successful controls: both IDs genuinely authorize the operator before the sale.
        operator.configure(coinflip, root);
        operator.configure(coinflip, child);
        _award(root, 0.1 ether);
        _award(child, 0.1 ether);
        _award(2, 100 ether);
        LiquidationQuote memory q = game.previewLiquidateAccount(root);
        assertTrue(q.eligible);
        assertGt(q.price, 0);
        bytes32 rootBank = game.extsload(GameSlotKeys.balances(root));
        bytes32 childBank = game.extsload(GameSlotKeys.balances(child));
        IdReviewSeller(payable(owner)).sell(game, coinflip, operator, root, child);
        assertTrue(IdReviewSeller(payable(owner)).callbackRan());
        uint32 replacement = IdReviewSeller(payable(owner)).replacement();
        uint32 replacementChild = IdReviewSeller(payable(owner)).replacementChild();
        assertGt(replacement, child);
        assertGt(replacementChild, replacement);
        assertEq(game.walletIdOf(owner), replacement);
        assertEq(game.walletIdentityOf(owner), root, "governance identity survives re-registration");
        assertEq(game.extsload(GameSlotKeys.balances(root)), rootBank);
        assertEq(game.extsload(GameSlotKeys.balances(child)), childBank);
        for (uint256 i; i < 2; ++i) {
            uint32 id = i == 0 ? root : child;
            (, address payee, bool authorized) = game.resolveAccount(id, owner);
            assertEq(payee, address(sdgnrs));
            assertFalse(authorized);
            (,, authorized) = game.resolveAccount(id, address(operator));
            assertFalse(authorized);
        }
        (, address newPayee, bool newAuth) = game.resolveAccount(replacementChild, owner);
        assertEq(newPayee, owner);
        assertTrue(newAuth);
        (,, newAuth) = game.resolveAccount(replacementChild, address(operator));
        assertFalse(newAuth, "approvals cannot leak into newly allocated IDs");
    }

    function _probeEmpty(uint32 id) private {
        bytes32 before_ = _accountDigest(id);
        uint256 length = uint256(game.extsload(bytes32(GameSlots.WALLETS)));
        // Public cache and idempotent settlement calls must not initialize a future account.
        game.playerActivityScoreCachedById(id);
        uint32[] memory ids = new uint32[](3);
        ids[0] = id; ids[1] = id; ids[2] = 0;
        game.claimAfkingFlip(ids);
        (bool ok,) = address(game).call(abi.encodeCall(game.claimWhalePass, (id)));
        assertFalse(ok, "unallocated pass claims must reject");
        (ok,) = address(game).call(abi.encodeCall(game.depositAfkingFunding, (id)));
        assertFalse(ok, "unallocated credit target must reject");
        (ok,) = address(game).call(abi.encodeCall(game.setOperatorApproval, (id, address(this), true)));
        assertFalse(ok, "cannot preapprove an unallocated ID");
        assertEq(_accountDigest(id), before_);
        assertEq(uint256(game.extsload(bytes32(GameSlots.WALLETS))), length);
    }

    function testFuzz_PublicCallsCannotPoisonFutureIds(uint32 candidate) public {
        uint32 next = uint32(uint256(game.extsload(bytes32(GameSlots.WALLETS))));
        uint32 target = uint32(bound(candidate, next, type(uint32).max));
        _probeEmpty(0); // This caller has no ID: zero must remain the empty sentinel.
        _probeEmpty(target);
        _probeEmpty(next);
        address newcomer = makeAddr("id-review-newcomer");
        assertEq(_giveWalletId(newcomer), next);
        assertEq(uint256(game.extsload(GameSlotKeys.walletElement(next))), uint160(newcomer));
        assertEq(game.extsload(GameSlotKeys.mintPacked(next)), bytes32(0));
        assertEq(game.extsload(GameSlotKeys.balances(next)), bytes32(0));
        (,, bool authorized) = game.resolveAccount(next, address(this));
        assertFalse(authorized);
    }

    function testFuzz_DirtyIdCalldataCannotAliasAnAuthorizedAccount(uint224 highBits) public {
        highBits = uint224(bound(highBits, 1, type(uint224).max));
        // Authorize this caller for the low 32-bit ID, so failure tests ABI validation itself.
        vm.prank(owner);
        game.setOperatorApproval(child, address(this), true);
        coinflip.setCoinflipAutoRebuy(child, true, 0);
        uint256 dirty = (uint256(highBits) << 32) | child;
        bytes32 before_ = _accountDigest(child);
        (bool ok,) = address(game).call(abi.encodeWithSignature("claimWinnings(uint32,uint256)", dirty, 1));
        assertFalse(ok);
        (ok,) = address(coinflip).call(abi.encodeWithSignature("setCoinflipAutoRebuy(uint32,bool,uint256)", dirty, false, 0));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", dirty, 1));
        assertFalse(ok);
        assertEq(_accountDigest(child), before_);
    }

    function test_InternalModuleAndTrustedCreditDoorsCannotBeForged() public {
        bytes32 before_ = _accountDigest(child);
        bytes memory purchase = abi.encodeWithSignature(
            "purchaseWith(uint32,uint256,uint256,bytes32,uint8,uint256,uint32)",
            child, 400, 0, bytes32(0), uint8(MintPaymentKind.DirectEth), 100 ether, root
        );
        (bool ok,) = address(game).call(purchase);
        assertFalse(ok, "Game cannot dispatch arbitrary module selectors");
        (ok,) = address(mintModule).call(purchase);
        assertFalse(ok, "direct module call cannot use Game's downstream privileges");
        (ok,) = address(game).call(abi.encodeCall(game.registerWallet, (address(this), true)));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeCall(game.registerWalletIdentity, (address(this))));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeCall(game.creditRedemptionDirect, (child, 100 ether)));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeCall(game.drainAffiliateBase, (child)));
        assertFalse(ok);
        (ok,) = address(coinflip).call(abi.encodeCall(coinflip.creditFlip, (child, 100_000)));
        assertFalse(ok);
        (ok,) = address(wwxrp).call(abi.encodeCall(wwxrp.creditPrize, (child, 100_000)));
        assertFalse(ok);
        assertEq(_accountDigest(child), before_);
        assertEq(game.walletIdOf(address(this)), 0);
    }
}
