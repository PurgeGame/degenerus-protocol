// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @dev Enters the due level and runs the production seizure worker in the Game's context.
contract IdReviewSeizer is DegenerusGameStorage {
    function seizeDue(uint24 due) external {
        level = due;
        _setLoansDuePending(true);
        loanSeizeCursor = 0;
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

contract IdReviewOperator {
    function configure(Coinflip flip, uint32 id) external {
        flip.setCoinflipAutoRebuy(id, true, 0);
    }
}

/// @dev Borrows, then after the lender seized the account tries both the former owner and a
///      previously approved operator against it.
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

    function borrow(DegenerusGame game_, Coinflip flip_, IdReviewOperator operator_, uint32 root_, uint32 child_) external {
        game = game_;
        flip = flip_;
        operator = operator_;
        root = root_;
        child = child_;
        armed = true;
        game.borrow(root, 1, type(uint256).max, 1);
    }

    receive() external payable {}

    function probe() external {
        if (!armed) return;
        armed = false;
        callbackRan = true;
        for (uint256 i; i < 2; ++i) {
            uint32 id = i == 0 ? root : child;
            (,, bool authorized) = game.resolveAccount_g7029(id, address(this));
            require(!authorized, "seller still authorized in callback");
            (,, authorized) = game.resolveAccount_g7029(id, address(operator));
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
        // Re-register through a real paid door, then allocate a child.
        uint256 price = game.mintPrice();
        game.purchaseOrderFor{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        replacement = game.walletIdOf_g3120(address(this));
        (bool created, bytes memory reason) = address(game).call{value: price}(
            abi.encodeCall(game.createSmurf, (bytes32(0), MintPaymentKind.DirectEth))
        );
        require(!created && bytes4(reason) == bytes4(keccak256("SmurfCreationLimitReached()")),
            "replacement inherited sold quota");
        // Earn fresh capacity through a real pass purchase.
        game.purchaseDeityPass{value: 24 ether}(0, 3, 0);
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
            game.mineRun{gas: 15_000_000}(0);
        }
        assertTrue(game.rngComplete());
        owner = address(new IdReviewSeller());
        root = _giveWalletId(owner);
        _grantSmurfBase(owner, 1);
        vm.deal(owner, 100 ether);
        uint256 price = game.mintPrice();
        vm.prank(owner);
        child = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _accountDigest(uint32 id) private view returns (bytes32) {
        return keccak256(abi.encode(
            game.extsload_g2807007(GameSlotKeys.walletElement(id)),
            game.extsload_g2807007(GameSlotKeys.mintPacked(id)),
            game.extsload_g2807007(GameSlotKeys.balances(id)),
            game.extsload_g2807007(GameSlotKeys.byId(id, GameSlots.BOON_PACKED)),
            coinflip.coinflipAmountById(id), wwxrp.claimable(id)
        ));
    }

    function _award(uint32 id, uint256 amount) private {
        GameFunding.credit(id, amount);
    }

    function test_SeizureLeavesNoOldOwnershipOrOperatorApprovals() public {
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
        DegenerusGameLens.LoanQuote memory q = new DegenerusGameLens().previewBorrow(address(game), root, 1, type(uint256).max);
        assertTrue(q.eligible);
        assertGt(q.principal, 0);
        bytes32 rootBank = game.extsload_g2807007(GameSlotKeys.balances(root));
        bytes32 childBank = game.extsload_g2807007(GameSlotKeys.balances(child));
        IdReviewSeller(payable(owner)).borrow(game, coinflip, operator, root, child);
        bytes memory runtime = address(game).code;
        vm.etch(address(game), address(new IdReviewSeizer()).code);
        IdReviewSeizer(address(game)).seizeDue(1);
        vm.etch(address(game), runtime);
        IdReviewSeller(payable(owner)).probe();
        assertTrue(IdReviewSeller(payable(owner)).callbackRan());
        uint32 replacement = IdReviewSeller(payable(owner)).replacement();
        uint32 replacementChild = IdReviewSeller(payable(owner)).replacementChild();
        assertGt(replacement, child);
        assertGt(replacementChild, replacement);
        assertEq(game.walletIdOf_g3120(owner), replacement);
        assertEq(game.walletIdentityOf_g8516(owner), root, "governance identity survives re-registration");
        assertEq(game.extsload_g2807007(GameSlotKeys.balances(root)), rootBank);
        assertEq(game.extsload_g2807007(GameSlotKeys.balances(child)), childBank);
        for (uint256 i; i < 2; ++i) {
            uint32 id = i == 0 ? root : child;
            (, address payee, bool authorized) = game.resolveAccount_g7029(id, owner);
            assertEq(payee, address(sdgnrs));
            assertFalse(authorized);
            (,, authorized) = game.resolveAccount_g7029(id, address(operator));
            assertFalse(authorized);
        }
        (, address newPayee, bool newAuth) = game.resolveAccount_g7029(replacementChild, owner);
        assertEq(newPayee, owner);
        assertTrue(newAuth);
        (,, newAuth) = game.resolveAccount_g7029(replacementChild, address(operator));
        assertFalse(newAuth, "approvals cannot leak into newly allocated IDs");
    }

    function _probeEmpty(uint32 id) private {
        bytes32 before_ = _accountDigest(id);
        uint256 length = uint256(game.extsload_g2807007(bytes32(GameSlots.WALLETS)));
        // Public cache and idempotent settlement calls must not initialize a future account.
        game.playerActivityScoreCachedById_g975(id);
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
        assertEq(uint256(game.extsload_g2807007(bytes32(GameSlots.WALLETS))), length);
    }

    function testFuzz_PublicCallsCannotPoisonFutureIds(uint32 candidate) public {
        uint32 next = uint32(uint256(game.extsload_g2807007(bytes32(GameSlots.WALLETS))));
        uint32 target = uint32(bound(candidate, next, type(uint32).max));
        _probeEmpty(0); // This caller has no ID: zero must remain the empty sentinel.
        _probeEmpty(target);
        _probeEmpty(next);
        address newcomer = makeAddr("id-review-newcomer");
        assertEq(_giveWalletId(newcomer), next);
        assertEq(uint256(game.extsload_g2807007(GameSlotKeys.walletElement(next))), uint160(newcomer));
        assertEq(game.extsload_g2807007(GameSlotKeys.mintPacked(next)), bytes32(0));
        assertEq(game.extsload_g2807007(GameSlotKeys.balances(next)), bytes32(uint256(1)), "only the claimable sentinel");
        (,, bool authorized) = game.resolveAccount_g7029(next, address(this));
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
        (ok,) = address(game).call(abi.encodeCall(game.registerWallet_g9539, (address(this), true)));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeCall(game.registerWalletIdentity, (address(this))));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeCall(game.creditRedemptionDirect, (child, 100 ether)));
        assertFalse(ok);
        (ok,) = address(game).call(abi.encodeCall(game.drainAffiliateBases, (uint256(child), 0)));
        assertFalse(ok);
        (ok,) = address(coinflip).call(abi.encodeCall(coinflip.creditFlip_g317, (child, 100_000)));
        assertFalse(ok);
        (ok,) = address(wwxrp).call(abi.encodeCall(wwxrp.creditPrize, (child, 100_000)));
        assertFalse(ok);
        assertEq(_accountDigest(child), before_);
        assertEq(game.walletIdOf_g3120(address(this)), 0);
    }
}
