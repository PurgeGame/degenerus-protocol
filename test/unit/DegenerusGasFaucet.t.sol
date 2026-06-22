// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {
    DegenerusGasFaucet,
    IGameLevel,
    IAffiliateScore,
    IVaultOwnership
} from "../../contracts/DegenerusGasFaucet.sol";

/// @title DegenerusGasFaucet unit suite
/// @notice Exercises the donation-funded gas-dust faucet in isolation. The three live surfaces it
///         reads (GAME.level(), AFFILIATE.affiliateScore(), VAULT.isVaultOwner()) are stubbed with
///         vm.mockCall at the ContractAddresses constants the faucet hard-wires, so no full protocol
///         deploy is needed. Covers dispense sizing, the three-part qualification gate, the one-use
///         cap (incl. duplicate-list and skip-on-revert paths), the dry-break, access control on
///         every gated entry point, the reentrancy guard, and the donate/withdraw surfaces.
contract DegenerusGasFaucetTest is Test {
    DegenerusGasFaucet internal faucet;

    address internal constant GAME = ContractAddresses.GAME;
    address internal constant AFFILIATE = ContractAddresses.AFFILIATE;
    address internal constant VAULT = ContractAddresses.VAULT;

    uint24 internal constant LVL = 7;

    address internal owner = makeAddr("vaultOwner");
    address internal distributor = makeAddr("distributor");
    address internal stranger = makeAddr("stranger");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // Events mirrored from the faucet for expectEmit.
    event Donated(address indexed from, uint256 amount);
    event Funded(address indexed recipient, uint24 indexed level, uint256 amount);
    event SendFailed(address indexed recipient, uint256 amount);
    event ApprovedDistributorSet(address indexed distributor, bool approved);
    event ParamsUpdated(uint256 minAffiliateScore, uint256 gasPerTx, uint256 gasPriceWei);
    event Withdrawn(address indexed to, uint256 amount);

    function setUp() public {
        faucet = new DegenerusGasFaucet();
        vm.deal(address(faucet), 100 ether);

        // Current level.
        vm.mockCall(GAME, abi.encodeWithSelector(IGameLevel.level.selector), abi.encode(LVL));

        // Vault ownership: default everyone false, then `owner` true (longer calldata wins).
        vm.mockCall(VAULT, abi.encodeWithSelector(IVaultOwnership.isVaultOwner.selector), abi.encode(false));
        vm.mockCall(
            VAULT,
            abi.encodeWithSelector(IVaultOwnership.isVaultOwner.selector, owner),
            abi.encode(true)
        );

        // Affiliate score: default everyone qualifies (2,000 FLIP > 1,000 min); override per-test.
        vm.mockCall(
            AFFILIATE,
            abi.encodeWithSelector(IAffiliateScore.affiliateScore.selector),
            abi.encode(uint256(2_000e18))
        );

        vm.prank(owner);
        faucet.setApprovedDistributor(distributor, true);
    }

    function _setScore(address who, uint256 score) internal {
        vm.mockCall(
            AFFILIATE,
            abi.encodeWithSelector(IAffiliateScore.affiliateScore.selector, LVL, who),
            abi.encode(score)
        );
    }

    function _one(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    // ---------------------------------------------------------------------
    // Sizing
    // ---------------------------------------------------------------------
    function test_dispenseAmount_isGasPerTxTimesPrice() public view {
        assertEq(faucet.dispenseAmount(), uint256(350_000) * 250_000_000);
    }

    // ---------------------------------------------------------------------
    // Qualification gate
    // ---------------------------------------------------------------------
    function test_qualifies_true() public view {
        assertTrue(faucet.qualifies(alice));
    }

    function test_qualifies_false_whenHoldsEth() public {
        vm.deal(alice, 1 wei);
        assertFalse(faucet.qualifies(alice));
    }

    function test_qualifies_false_whenBelowScore() public {
        _setScore(alice, 999e18);
        assertFalse(faucet.qualifies(alice));
    }

    function test_qualifies_true_atExactThreshold() public {
        _setScore(alice, 1_000e18);
        assertTrue(faucet.qualifies(alice));
    }

    function test_qualifies_false_afterFunded() public {
        vm.prank(distributor);
        faucet.distribute(_one(alice));
        assertFalse(faucet.qualifies(alice));
    }

    // ---------------------------------------------------------------------
    // Distribution — happy path
    // ---------------------------------------------------------------------
    function test_distribute_fundsQualifying() public {
        uint256 amount = faucet.dispenseAmount();
        vm.expectEmit(true, true, true, true, address(faucet));
        emit Funded(alice, LVL, amount);

        vm.prank(distributor);
        uint256 funded = faucet.distribute(_one(alice));

        assertEq(funded, 1);
        assertEq(alice.balance, amount);
        assertTrue(faucet.hasReceived(alice));
    }

    function test_distribute_byVaultOwner() public {
        vm.prank(owner);
        uint256 funded = faucet.distribute(_one(alice));
        assertEq(funded, 1);
    }

    function test_distribute_skipsNonQualifying_mixedBatch() public {
        vm.deal(bob, 1 wei); // holds ETH → skip
        _setScore(carol, 10e18); // below threshold → skip

        address[] memory rs = new address[](3);
        rs[0] = alice;
        rs[1] = bob;
        rs[2] = carol;

        vm.prank(distributor);
        uint256 funded = faucet.distribute(rs);

        assertEq(funded, 1);
        assertEq(alice.balance, faucet.dispenseAmount());
        assertEq(bob.balance, 1 wei);
        assertEq(carol.balance, 0);
    }

    // ---------------------------------------------------------------------
    // One-use cap
    // ---------------------------------------------------------------------
    function test_distribute_oneUseCap_acrossCalls() public {
        vm.prank(distributor);
        faucet.distribute(_one(alice));
        uint256 balAfter = alice.balance;

        // alice now holds ETH AND hasReceived; second call must not pay again.
        vm.prank(distributor);
        uint256 funded2 = faucet.distribute(_one(alice));
        assertEq(funded2, 0);
        assertEq(alice.balance, balAfter);
    }

    function test_distribute_duplicateInSameList_paysOnce() public {
        address[] memory rs = new address[](2);
        rs[0] = alice;
        rs[1] = alice;

        vm.prank(distributor);
        uint256 funded = faucet.distribute(rs);

        assertEq(funded, 1);
        assertEq(alice.balance, faucet.dispenseAmount());
    }

    // ---------------------------------------------------------------------
    // Dry-break
    // ---------------------------------------------------------------------
    function test_distribute_breaksWhenDry() public {
        uint256 amount = faucet.dispenseAmount();
        // Drain to exactly enough for two top-ups.
        vm.prank(owner);
        faucet.withdraw(owner, address(faucet).balance);
        vm.deal(address(faucet), amount * 2);

        address[] memory rs = new address[](3);
        rs[0] = alice;
        rs[1] = bob;
        rs[2] = carol;

        vm.prank(distributor);
        uint256 funded = faucet.distribute(rs);

        assertEq(funded, 2);
        assertEq(carol.balance, 0); // never reached the third — faucet went dry
        assertEq(address(faucet).balance, 0);
    }

    // ---------------------------------------------------------------------
    // Gas-capped send: a contract whose receive() reverts (needs > 2300 gas) is rejected; under
    // checks-effects-interactions its one allowance is already consumed, and the batch continues.
    // ---------------------------------------------------------------------
    function test_distribute_contractRejectingTransfer_forfeitsAllowance() public {
        RejectingReceiver rej = new RejectingReceiver();
        _setScore(address(rej), 2_000e18);
        uint256 amount = faucet.dispenseAmount();

        vm.expectEmit(true, true, true, true, address(faucet));
        emit SendFailed(address(rej), amount);

        vm.prank(distributor);
        uint256 funded = faucet.distribute(_one(address(rej)));

        assertEq(funded, 0);
        assertEq(address(rej).balance, 0);
        assertTrue(faucet.hasReceived(address(rej))); // CEI: allowance spent before the send
    }

    // ---------------------------------------------------------------------
    // A contract with a trivial receive() still gets the dust — the faucet caps gas, it does not
    // ban contracts. The 2300 stipend covers an empty receive but no logic beyond it.
    // ---------------------------------------------------------------------
    function test_distribute_trivialReceiveContract_succeeds() public {
        EmptyReceiver er = new EmptyReceiver();
        _setScore(address(er), 2_000e18);

        vm.prank(distributor);
        uint256 funded = faucet.distribute(_one(address(er)));

        assertEq(funded, 1);
        assertEq(address(er).balance, faucet.dispenseAmount());
        assertTrue(faucet.hasReceived(address(er)));
    }

    // ---------------------------------------------------------------------
    // Reentrancy cannot double-pay: CEI sets hasReceived BEFORE the send, so a reentrant
    // distribute() for the same address short-circuits on the one-use flag. No guard required.
    // ---------------------------------------------------------------------
    function test_distribute_reentrancyCannotDoublePay() public {
        ReentrantDistributor evil = new ReentrantDistributor(faucet);
        _setScore(address(evil), 2_000e18);
        vm.prank(owner);
        faucet.setApprovedDistributor(address(evil), true);

        uint256 amount = faucet.dispenseAmount();
        uint256 faucetBefore = address(faucet).balance;

        // evil's receive() reenters distribute([evil]); the reentrant call sees hasReceived[evil]
        // already set (CEI) and skips. Depending on forwarded gas the hook either completes
        // harmlessly or reverts — either way evil can never collect a second grant.
        vm.prank(distributor);
        uint256 funded = faucet.distribute(_one(address(evil)));

        assertTrue(faucet.hasReceived(address(evil)));               // allowance spent up front
        assertLe(address(evil).balance, amount);                    // NEVER paid twice
        assertLe(faucetBefore - address(faucet).balance, amount);   // faucet lost at most one grant
        assertLe(funded, 1);
    }

    // ---------------------------------------------------------------------
    // Access control
    // ---------------------------------------------------------------------
    function test_distribute_revertsForStranger() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusGasFaucet.NotAuthorized.selector);
        faucet.distribute(_one(alice));
    }

    function test_distribute_zeroAmount_reverts() public {
        vm.prank(owner);
        faucet.setParams(1_000e18, 0, 250_000_000); // gasPerTx = 0 → dispense 0
        vm.prank(distributor);
        vm.expectRevert(DegenerusGasFaucet.NothingToDispense.selector);
        faucet.distribute(_one(alice));
    }

    function test_setParams_onlyVaultOwner() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusGasFaucet.NotVaultOwner.selector);
        faucet.setParams(5_000e18, 400_000, 1_000_000_000);

        vm.expectEmit(false, false, false, true, address(faucet));
        emit ParamsUpdated(5_000e18, 400_000, 1_000_000_000);
        vm.prank(owner);
        faucet.setParams(5_000e18, 400_000, 1_000_000_000);

        assertEq(faucet.minAffiliateScore(), 5_000e18);
        assertEq(faucet.gasPerTx(), 400_000);
        assertEq(faucet.gasPriceWei(), 1_000_000_000);
        assertEq(faucet.dispenseAmount(), uint256(400_000) * 1_000_000_000);
    }

    function test_setApprovedDistributor_onlyVaultOwner() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusGasFaucet.NotVaultOwner.selector);
        faucet.setApprovedDistributor(stranger, true);
    }

    function test_setApprovedDistributor_zeroAddrReverts() public {
        vm.prank(owner);
        vm.expectRevert(DegenerusGasFaucet.ZeroAddress.selector);
        faucet.setApprovedDistributor(address(0), true);
    }

    function test_setApprovedDistributor_revoke() public {
        vm.prank(owner);
        faucet.setApprovedDistributor(distributor, false);
        vm.prank(distributor);
        vm.expectRevert(DegenerusGasFaucet.NotAuthorized.selector);
        faucet.distribute(_one(alice));
    }

    // ---------------------------------------------------------------------
    // Donations + withdrawal
    // ---------------------------------------------------------------------
    function test_receive_emitsDonated() public {
        vm.deal(stranger, 5 ether);
        vm.expectEmit(true, false, false, true, address(faucet));
        emit Donated(stranger, 5 ether);
        vm.prank(stranger);
        (bool ok, ) = address(faucet).call{value: 5 ether}("");
        assertTrue(ok);
    }

    function test_withdraw_onlyVaultOwner() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusGasFaucet.NotVaultOwner.selector);
        faucet.withdraw(stranger, 1 ether);
    }

    function test_withdraw_zeroAddrReverts() public {
        vm.prank(owner);
        vm.expectRevert(DegenerusGasFaucet.ZeroAddress.selector);
        faucet.withdraw(address(0), 1 ether);
    }

    function test_withdraw_movesEth() public {
        uint256 before = owner.balance;
        vm.prank(owner);
        faucet.withdraw(owner, 3 ether);
        assertEq(owner.balance, before + 3 ether);
        assertEq(address(faucet).balance, 97 ether);
    }

    function test_withdraw_sweepsAllViaBalance() public {
        uint256 before = owner.balance;
        vm.prank(owner);
        faucet.withdraw(owner, address(faucet).balance);
        assertEq(owner.balance, before + 100 ether);
        assertEq(address(faucet).balance, 0);
    }
}

/// @dev A recipient whose ETH receive always reverts.
contract RejectingReceiver {
    receive() external payable {
        revert("nope");
    }
}

/// @dev A recipient with a no-op receive — accepts ETH within the 2300-gas stipend.
contract EmptyReceiver {
    receive() external payable {}
}

/// @dev An approved distributor that reenters distribute() from its receive hook.
contract ReentrantDistributor {
    DegenerusGasFaucet internal immutable FAUCET;

    constructor(DegenerusGasFaucet faucet) {
        FAUCET = faucet;
    }

    receive() external payable {
        address[] memory rs = new address[](1);
        rs[0] = address(this);
        FAUCET.distribute(rs); // reverts Reentrancy → bubbles up → outer send fails
    }
}
