// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameFacade} from "../../contracts/modules/GameFacade.sol";

import {Vm} from "forge-std/Vm.sol";
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @title RedemptionAccounts -- sDGNRS redemption claims by account ID, and the protocol self pulls
/// @notice `claimRedemption(id, batch)`: `id == 0` is the caller
///         (no Game `resolveAccount` call); any other ID must authorize the caller (the key, a
///         smurf's owner or an approved operator), else `Unauthorized`; an unallocated ID reverts
///         Game `E`. The claim is deleted under the account's ID and paid to its payee (terminal ETH
///         push, open-batch unwind) or credited to its ID (live parked claim). Smurfs never burn, so
///         they hold no claim (`NoClaim`). sDGNRS and GNRUS pull their own Game claimable with
///         `claimWinnings(0)`.
contract RedemptionAccountsTest is RedemptionFixture {

    address internal operator = address(0x0FE7A70);
    address internal stranger = address(0x5712A6E);
    uint32 internal aliceId;

    function setUp() public override {
        super.setUp();
        _grantSmurfBase(alice, 1);
        aliceId = game.walletIdOf_g3120(alice);
        vm.prank(alice);
        game.setOperatorApproval(0, operator, true);
    }

    function _walletCount() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS))));
    }

    function _createSmurf(address o) internal returns (uint32 sid) {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(o, o.balance + price);
        vm.prank(o);
        sid = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        (address key, address payee,) = game.resolveAccount_g502(sid, o);
        require(key == address(0) && payee == o, "fixture: account owner");
    }

    /// @dev Strip sDGNRS's ETH and stETH custody so a live claim's legs refuse; returns what to restore.
    function _stripCustody() internal returns (uint256 eth, uint256 st) {
        eth = address(sdgnrs).balance;
        st = mockStETH.balanceOf(address(sdgnrs));
        vm.deal(address(sdgnrs), 0);
        if (st != 0) {
            vm.prank(address(sdgnrs));
            mockStETH.transfer(address(0xDEAD), st);
        }
    }

    function _restoreCustody(uint256 eth, uint256 st) internal {
        vm.deal(address(sdgnrs), eth);
        if (st != 0) {
            vm.prank(address(0xDEAD));
            mockStETH.transfer(address(sdgnrs), st);
        }
    }

    function _claimedFor(Vm.Log[] memory logs, address player) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(sdgnrs) || logs[i].topics[0] != CLAIMED_TOPIC) continue;
            if (uint32(uint256(logs[i].topics[1])) == game.walletIdOf_g3120(player)) ++n;
        }
    }

    // =====================================================================
    //                    13. claimRedemption after game over
    // =====================================================================

    /// @notice P's terminal claim for A deletes A's claim and pushes the rolled ETH to A; P gets
    ///         nothing; the event names A; the claim cannot pay twice.
    function test_TerminalClaim_ByOperator_PaysAccountPayee() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _resolveLive(100);
        uint256 expected = _claimBase(alice, id);
        _terminalize();
        uint256 before = _received(alice);
        uint256 opBefore = _received(operator);

        vm.expectCall(address(game), abi.encodeCall(GameFacade.resolveAccount_g502, (aliceId, operator)), 1);
        vm.recordLogs();
        vm.prank(operator);
        sdgnrs.claimRedemption(aliceId, id);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_received(alice) - before, expected, "the payee received the rolled amount");
        assertEq(_received(operator), opBefore, "nothing to the operator");
        assertEq(_claimTokens(alice, id), 0, "A's claim deleted");
        assertEq(_claimedFor(logs, alice), 1, "RedemptionClaimed names A");
        assertEq(_claimedFor(logs, operator), 0);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, id);
    }

    /// @notice P's claim on the batch still open at game over unwinds A's tokens at the game-over
    ///         value and pays A.
    function test_OpenBatchUnwind_ByOperator_PaysAccountPayee() public {
        uint32 open = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _latchGameOver();
        uint256 tokens = _claimTokens(alice, open);
        assertGt(tokens, 0);
        uint256 expected = _money() * tokens / (sdgnrs.totalSupply() + _escrow());
        uint256 before = _received(alice);
        uint256 opBefore = _received(operator);

        vm.recordLogs();
        vm.prank(operator);
        sdgnrs.claimRedemption(aliceId, open);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertApproxEqAbs(_received(alice) - before, expected, 1, "A paid the game-over value of its tokens");
        assertGt(_received(alice), before);
        assertEq(_received(operator), opBefore, "nothing to the operator");
        assertEq(_claimTokens(alice, open), 0, "A's open claim deleted");
        assertEq(_claimedFor(logs, alice), 1);
    }

    /// @notice X reverts Unauthorized on a closed and an open batch, an unallocated ID reverts E, and
    ///         a smurf holds no claim (`NoClaim` for its owner on either batch); A's claims survive.
    function test_Stranger_Unauthorized_UnallocatedE_SmurfNoClaim() public {
        uint32 smurfId = _createSmurf(alice);
        vm.prank(alice);
        game.setOperatorApproval(smurfId, operator, true);
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 closed = _resolveLive(100);
        uint32 open = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 2000);
        _terminalize();
        assertTrue(open != closed);

        vm.expectRevert(sDGNRS.Unauthorized.selector);
        vm.prank(stranger);
        sdgnrs.claimRedemption(aliceId, closed);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        vm.prank(stranger);
        sdgnrs.claimRedemption(aliceId, open);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        sdgnrs.claimRedemption(_walletCount(), closed);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimRedemption(smurfId, closed);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimRedemption(smurfId, open);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(operator);
        sdgnrs.claimRedemption(smurfId, closed);

        assertGt(_claimTokens(alice, closed), 0, "A's closed claim intact");
        assertGt(_claimTokens(alice, open), 0, "A's open claim intact");
    }

    /// @notice Error precedence on claimRedemption: NotResolved, then NotGameOver, then the account
    ///         check; the self claim (`id == 0`) makes no resolveAccount call.
    function test_ClaimRedemption_ErrorPrecedence_SelfNoResolve() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _openBatchId();
        _closeAsGame();
        vm.expectRevert(sDGNRS.NotResolved.selector);
        vm.prank(stranger);
        sdgnrs.claimRedemption(aliceId, id);

        settlementWord = _wordForRoll(100);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage_g379()"), abi.encode(uint8(1)));
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(settlementWord, 200_000);
        assertEq(_rollOf(id), 100);
        vm.expectRevert(sDGNRS.NotGameOver.selector);
        vm.prank(stranger);
        sdgnrs.claimRedemption(aliceId, id);

        _terminalize();
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        vm.prank(stranger);
        sdgnrs.claimRedemption(aliceId, id);

        uint256 before = _received(alice);
        vm.expectCall(address(game), abi.encodeWithSelector(GameFacade.resolveAccount_g502.selector), 0);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, id);
        assertGt(_received(alice), before, "self claim paid the caller");
        assertEq(_claimTokens(alice, id), 0);
    }

    /// @notice A live settlement step that reverts consumes nothing: if the game ends before it
    ///         succeeds, the account's claim is still live and the operator's terminal claim pays
    ///         the account's payee in full.
    function test_RevertedLiveSettlementLeavesClaimForOperatorAfterGameOver() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 batchId = _resolveLive(100);
        uint256 expected = _claimBase(alice, batchId);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"12345678");
        _assertWorkRevertsUnchanged(batchId, 9_000_000);
        _terminalize();
        assertGt(_claimTokens(alice, batchId), 0, "the unsettled claim is still live");
        uint256 before = _received(alice);
        vm.prank(operator);
        sdgnrs.claimRedemption(aliceId, batchId);
        assertEq(_received(alice) - before, expected, "the payee receives the rolled amount");
        assertEq(_claimTokens(alice, batchId), 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(operator);
        sdgnrs.claimRedemption(aliceId, batchId);
    }

    // =====================================================================
    //                    15. protocol self pulls by claimWinnings(0)
    // =====================================================================

    /// @notice At game over, an unwind that sDGNRS's custody cannot cover pulls sDGNRS's own Game
    ///         claimable with `claimWinnings(0)`, then pays the account's payee.
    function test_GameOverUnwind_PullsSdgnrsClaimableWithClaimWinningsZero() public {
        uint32 open = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _stripCustody();
        uint256 credit = 50 ether;
        GameFunding.credit(2, credit);
        assertEq(address(sdgnrs).balance, 0);
        assertGt(game.claimableWinningsOf(address(sdgnrs)), credit - 1);
        _latchGameOver();
        uint256 before = _received(alice);

        vm.expectCall(address(game), abi.encodeWithSignature("claimWinnings(uint32)", uint32(0)), 1);
        vm.prank(operator);
        sdgnrs.claimRedemption(aliceId, open);
        assertGt(_received(alice), before, "A paid from the pulled claimable");
        assertLe(game.claimableWinningsOf(address(sdgnrs)), 1, "sDGNRS drew its own claimable");
    }

    /// @notice A GNRUS burn its on-hand balance cannot cover pulls GNRUS's own Game claimable with
    ///         `claimWinnings(0)`.
    function test_GnrusBurn_PullsClaimableWithClaimWinningsZero() public {
        assertEq(game.walletIdOf_g3120(address(gnrus)), 3, "GNRUS holds reserved ID 3");
        vm.deal(address(gnrus), 0);
        uint256 credit = 10 ether;
        GameFunding.credit(3, credit);
        address holder = makeAddr("gnrus_holder");
        uint256 amount = gnrus.totalSupply() / 100;
        uint256 selfBal = gnrus.balanceOf(address(gnrus));
        deal(address(gnrus), address(gnrus), selfBal - amount);
        deal(address(gnrus), holder, amount);

        vm.expectCall(address(game), abi.encodeWithSignature("claimWinnings(uint32)", uint32(0)), 1);
        vm.prank(holder);
        gnrus.burn(amount);
        assertGt(holder.balance + mockStETH.balanceOf(holder), 0, "the holder was paid from the pull");
        assertLe(game.claimableWinningsOf(address(gnrus)), 1, "GNRUS drew its own claimable");
    }
}

/// @notice sDGNRS and the vault subscribe in their constructors with `subscribe(0, false, 1, 0)`,
///         before the seat token is deployed: the exempt subscriptions never call it.
contract SdgnrsConstructorSubscribeTest is DeployProtocol {
    bytes32 internal constant SUBSCRIPTION_UPDATED = keccak256("SubscriptionUpdated(uint32,uint8,bool)");

    function test_ConstructorSubscribe_BeforeSeatTokenExists() public {
        vm.expectCall(
            ContractAddresses.AFKING_SUB_TOKEN,
            abi.encodeWithSelector(AFKingSubscriptionToken.consumeSeat.selector),
            0
        );
        // Both protocol seats subscribe once, one lootbox unit a day.
        vm.expectCall(
            ContractAddresses.GAME,
            abi.encodeWithSignature("subscribe(uint32,bool,uint8,uint256)", uint32(0), false, uint8(1), uint256(0)),
            2
        );
        vm.recordLogs();
        _deployProtocol();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 sdgnrsSub = type(uint256).max;
        uint256 vaultSub = type(uint256).max;
        uint256 firstTokenLog = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == ContractAddresses.AFKING_SUB_TOKEN && firstTokenLog == type(uint256).max) {
                firstTokenLog = i;
            }
            if (logs[i].emitter != ContractAddresses.GAME || logs[i].topics[0] != SUBSCRIPTION_UPDATED) continue;
            uint32 player = uint32(uint256(logs[i].topics[1]));
            (uint8 qty, bool tickets) = abi.decode(logs[i].data, (uint8, bool));
            assertEq(qty, 1);
            assertFalse(tickets);
            if (player == 2) sdgnrsSub = i;
            if (player == 1) vaultSub = i;
        }
        assertTrue(sdgnrsSub != type(uint256).max, "sDGNRS subscribed at construction");
        assertTrue(vaultSub != type(uint256).max, "the vault subscribed at construction");
        assertTrue(firstTokenLog != type(uint256).max, "the seat token deployed");
        assertLt(sdgnrsSub, firstTokenLog, "sDGNRS subscribed before the seat token existed");
        assertLt(vaultSub, firstTokenLog);
        assertEq(address(afkingSubToken), ContractAddresses.AFKING_SUB_TOKEN);
    }
}
