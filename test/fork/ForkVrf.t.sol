// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {Vm} from "forge-std/Vm.sol";
import {ForkDeployProtocol} from "./ForkDeployProtocol.sol";
import {ForkPins} from "./ForkPins.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @title Real-coordinator native funding, request validation and cancellation.
/// @dev Proof delivery is simulated; native funding and subscription operations are real.
contract ForkVrfTest is ForkDeployProtocol {
    bytes32 private constant SUBSCRIPTION_CANCELED = keccak256("SubscriptionCanceled(uint256,address,uint256,uint256)");
    /// @dev The coordinator's registered 1000 gwei lane (s_provingKeys -> exists, maxGas 1000 gwei).
    bytes32 private constant KEY_HASH_1000_GWEI = 0xc6bf2e7b88e5cfbb4946ff23af846494ae1f3c65270b79ee7876c9aa99d3d45f;

    struct Request {
        uint256 id;
        bytes32 keyHash;
        uint256 subId;
        address sender;
        uint16 confirmations;
        uint32 callbackGas;
        uint32 numWords;
        bytes extraArgs;
    }

    uint256 private subId;

    function setUp() public {
        _forkAndDeploy();
        subId = admin.subscriptionId();
    }

    // ------------------------------------------------------------------ helpers

    function _decodeRequests(Vm.Log[] memory logs) private pure returns (Request[] memory out) {
        out = new Request[](_requestsIn(logs));
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != ForkPins.VRF_COORDINATOR || logs[i].topics[0] != RANDOM_WORDS_REQUESTED) continue;
            Request memory r = out[n++];
            r.keyHash = logs[i].topics[1];
            r.subId = uint256(logs[i].topics[2]);
            r.sender = address(uint160(uint256(logs[i].topics[3])));
            (r.id,, r.confirmations, r.callbackGas, r.numWords, r.extraArgs) =
                abi.decode(logs[i].data, (uint256, uint256, uint16, uint32, uint32, bytes));
        }
    }

    /// @dev Crank WITHOUT answering until the daily lock is taken; returns the logged request.
    function _dailyRequest() private returns (Request memory r) {
        vm.recordLogs();
        for (uint256 i; i < 32 && !game.rngLocked(); ++i) {
            vm.prank(keeper);
            game.mineFlip(0);
        }
        assertTrue(game.rngLocked(), "the daily request never went out");
        Request[] memory reqs = _decodeRequests(vm.getRecordedLogs());
        assertEq(reqs.length, 1, "exactly one request reaches the coordinator");
        r = reqs[0];
    }

    /// @dev Crank WITHOUT answering until a new request reaches the coordinator or the engine idles.
    function _crankUntilRequest(uint256 maxCalls) private returns (Request[] memory reqs) {
        vm.recordLogs();
        for (uint256 i; i < maxCalls; ++i) {
            vm.prank(keeper);
            try game.mineFlip(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (sel != NO_WORK && sel != RNG_NOT_READY) {
                    emit log_named_bytes("unexpected mineFlip revert", reason);
                    fail("mineFlip reverted");
                }
                break;
            }
            if (game.rngLocked() || _pendingRequest() != 0) break;
        }
        reqs = _decodeRequests(vm.getRecordedLogs());
    }

    function _donate(address donor, uint256 amount) private {
        vm.deal(donor, amount);
        vm.prank(donor);
        admin.donateVrf{value: amount}();
    }

    function _subBalance() private view returns (uint96 bal) {
        (,bal,,,) = coordinator.getSubscription(subId);
    }

    /// @dev Day 1 settled: the first daily request answered and consumed.
    function _settleFirstDay() private {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _crank(200);
        assertFalse(game.rngLocked(), "fixture: first day did not settle");
    }

    // ------------------------------------------------------------------ wiring

    /// @notice DegenerusAdmin's constructor created a REAL v2.5 subscription it owns, with the game
    ///         as its only consumer, and wired the same coordinator / sub / registered key hash
    ///         into the game. The coordinator's live config admits the game's request shape.
    function test_constructorWiresARealSubscription() public view {
        assertGt(subId, 0, "no subscription");
        (uint96 bal, uint96 nativeBal, uint64 reqCount, address owner, address[] memory consumers) =
            coordinator.getSubscription(subId);
        assertEq(owner, address(admin), "the Admin owns the subscription");
        assertEq(consumers.length, 1, "one consumer");
        assertEq(consumers[0], address(game), "the game is the consumer");
        assertEq(uint256(bal) + nativeBal + reqCount, 0, "fresh subscription");
        assertFalse(coordinator.pendingRequestExists(subId), "nothing pending at deploy");

        assertEq(admin.coordinator(), ForkPins.VRF_COORDINATOR);
        assertEq(admin.vrfKeyHash(), ForkPins.VRF_KEY_HASH);
        assertEq(address(uint160(uint256(vm.load(address(game), bytes32(GameSlots.VRF_COORDINATOR))))), ForkPins.VRF_COORDINATOR);
        assertEq(vm.load(address(game), bytes32(GameSlots.VRF_KEY_HASH)), ForkPins.VRF_KEY_HASH);
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.VRF_SUBSCRIPTION_ID))), subId);

        (bool exists, uint64 maxGas) = coordinator.s_provingKeys(ForkPins.VRF_KEY_HASH);
        assertTrue(exists, "key hash registered on the real coordinator");
        assertEq(maxGas, 200 gwei, "the 200 gwei lane");

        (uint16 minConf, uint32 maxGasLimit,,,,,, uint8 nativePremium,) = coordinator.s_config();
        assertLe(minConf, 4, "mid-day confirmations (4) are above the coordinator minimum");
        assertGe(coordinator.MAX_REQUEST_CONFIRMATIONS(), 6, "daily confirmations (6) are below the maximum");
        assertGe(maxGasLimit, GAME_CALLBACK_GAS, "the 150k callback fits the coordinator ceiling");
        assertGe(coordinator.MAX_NUM_WORDS(), 1);
        // Sizing pins the coordinator native premium.
        assertEq(nativePremium, 24, "native sizing assumes 24% premium");
    }

    // ------------------------------------------------------------------ daily request

    /// @notice The daily request is accepted by the real coordinator with the game's exact
    ///         parameters, native billing (nativePayment=true), and is pending on the coordinator.
    function test_dailyRequestIsAcceptedByTheRealCoordinator() public {
        vm.deal(address(game), 0); // Unfunded transport must still accept a daily request.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        Request memory r = _dailyRequest();
        assertEq(r.keyHash, ForkPins.VRF_KEY_HASH, "keyHash");
        assertEq(r.subId, subId, "subId");
        assertEq(r.sender, address(game), "sender");
        assertEq(r.confirmations, 6, "daily confirmations");
        assertEq(r.callbackGas, 150_000, "callback gas");
        assertEq(r.numWords, 1, "numWords");
        assertEq(r.extraArgs, abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, true), "extraArgs = V1{nativePayment:true}");
        assertEq(r.id, uint256(vm.load(address(game), bytes32(GameSlots.VRF_REQUEST_ID))), "the game stored the real id");
        assertTrue(coordinator.s_requestCommitments(r.id) != bytes32(0), "commitment recorded");
        assertTrue(coordinator.pendingRequestExists(subId), "pending on the subscription");
        // The request was accepted with a ZERO-NATIVE subscription: v2.5 bills at fulfilment, so
        // an unfunded daily request does not revert — it would simply never be fulfilled.
        assertEq(_subBalance(), 0);
    }

    /// @notice The coordinator's answer is consumed: only the coordinator may call back, a
    ///         wrong id is ignored, the word fits the 150k callback, and the day settles with it.
    ///         The next day issues a fresh request id from the same subscription.
    function test_fulfilledWordIsConsumedAndTheNextDayRequestsAgain() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint24 day = game.currentDayView();
        Request memory r = _dailyRequest();
        assertEq(game.rngWordForDay(day), 0, "no word before fulfilment");

        uint256[] memory words = new uint256[](1);
        words[0] = 0xC0FFEE;
        vm.expectRevert(bytes4(keccak256("OnlyCoordinator()")));
        game.rawFulfillRandomWords(r.id, words);
        vm.prank(ForkPins.VRF_COORDINATOR);
        game.rawFulfillRandomWords(r.id + 1, words);
        assertFalse(game.isRngFulfilled(), "a foreign request id is ignored");

        assertTrue(_fulfill(r.id, 0xC0FFEE), "callback within 300k gas");
        assertFalse(coordinator.pendingRequestExists(subId), "the coordinator retired the commitment");
        _crank(200);
        assertFalse(game.rngLocked(), "the daily lock released");
        assertTrue(game.rngWordForDay(day) != 0, "the day's word was applied");
        assertEq(game.lastVrfProcessed(), uint48(vm.getBlockTimestamp()), "VRF processing timestamp");

        vm.warp(vm.getBlockTimestamp() + 1 days);
        Request memory next = _dailyRequest();
        assertTrue(next.id != r.id, "a fresh request id");
        assertEq(next.subId, subId);
        assertTrue(_fulfill(next.id, 0xBEEF));
        _crank(200);
        assertTrue(game.rngWordForDay(day + 1) != 0, "day two settled");
    }

    /// @notice The admin retry after 20 hours issues a second REAL request on the same
    ///         subscription. The abandoned request stays pending on the coordinator: a late
    ///         answer to it is ignored by the game, and only its own fulfilment (or never)
    ///         clears it from the subscription.
    function test_retryIssuesAFreshRealRequestAndOrphansTheOld() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        Request memory first = _dailyRequest();
        vm.warp(vm.getBlockTimestamp() + 20 hours);
        vm.recordLogs();
        vm.prank(_vaultOwner());
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retryGameRng, ()), 0);
        Request[] memory retried = _decodeRequests(vm.getRecordedLogs());
        assertEq(retried.length, 1, "one retry request");
        assertTrue(retried[0].id != first.id);
        assertEq(retried[0].confirmations, 6, "a daily retry keeps daily confirmations");
        assertTrue(coordinator.s_requestCommitments(first.id) != bytes32(0), "old request still pending");
        assertTrue(coordinator.s_requestCommitments(retried[0].id) != bytes32(0), "new request pending");

        assertTrue(_fulfill(retried[0].id, 0xA11CE));
        _crank(200);
        assertFalse(game.rngLocked(), "the retried word settled the day");
        assertTrue(coordinator.pendingRequestExists(subId), "the orphan keeps the subscription 'pending'");
        uint48 processed = game.lastVrfProcessed();
        assertTrue(_fulfill(first.id, 0xDEAD), "late answer accepted by the callback");
        assertEq(game.lastVrfProcessed(), processed, "and ignored by the game");
        assertFalse(coordinator.pendingRequestExists(subId), "only its own answer clears the orphan");
    }

    // ------------------------------------------------------------------ funding

    /// @notice Native donations fund the real subscription and bank quarter-value credit.
    function test_nativeDonationFundsTheRealSubscription() public {
        address donor = makeAddr("donor");
        uint256 before = _subBalance();
        _donate(donor, 1 ether);
        assertEq(_subBalance() - before, 1 ether);
        assertEq(address(admin).balance, 0);
        assertEq(game.middayRngCredits(donor), 0.25 ether);
    }

    /// @notice The mid-day request reads the REAL subscription balance: below the 0.1302 ETH floor
    ///         the engine declines it; once funded it goes out with 4 confirmations.
    function test_middayRequestIsGatedOnTheRealSubscriptionBalance() public {
        vm.deal(address(game), 0); // Prevent the fixture bankroll from supplying a daily refill.
        _settleFirstDay();
        address buyer = makeAddr("boxBuyer");
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        Request[] memory none = _crankUntilRequest(64);
        assertEq(none.length, 0, "an unfunded subscription gets no mid-day request");

        _donate(makeAddr("donor"), 100 ether);
        Request[] memory reqs = _crankUntilRequest(64);
        assertEq(reqs.length, 1, "the funded mid-day request went out");
        assertEq(reqs[0].confirmations, 4, "mid-day confirmations");
        assertEq(reqs[0].sender, address(game));
        assertFalse(game.rngLocked(), "a mid-day request takes no daily lock");
        assertTrue(_fulfill(reqs[0].id, 0x5EED));
        _crank(200);
        assertEq(_pendingRequest(), 0, "the mid-day word was consumed");
    }

    // ------------------------------------------------------------------ coordinator swap

    /// @notice The emergency coordinator swap, executed against the real coordinator (rotating to a
    ///         fresh subscription on it, on the 1000 gwei lane): the old subscription's cancel hits
    ///         PendingRequestExists (the stalled request) and is absorbed; a new real subscription
    ///         is created with the game as consumer, and the stalled daily request is re-issued on
    ///         it in the same transaction. Once the stalled request clears, retrySubCancel cancels
    ///         the retired subscription: the real coordinator refunds native ETH into Admin.receive, which retains and
    ///         forwards it to the live subscription without credit.
    function test_coordinatorSwapAndRetiredSubscriptionRecovery() public {
        address voter = makeAddr("voter");
        _giveWalletId(voter);
        uint256 stake = sdgnrs.totalSupply() / 50;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, voter, stake);
        _donate(makeAddr("donor"), 50 ether);
        (bool laneExists,) = coordinator.s_provingKeys(KEY_HASH_1000_GWEI);
        assertTrue(laneExists, "the replacement lane is registered");

        vm.warp(vm.getBlockTimestamp() + 1 days);
        Request memory stalled = _dailyRequest();
        vm.warp(vm.getBlockTimestamp() + 45 hours);

        vm.prank(_vaultOwner());
        uint256 proposalId = admin.propose(ForkPins.VRF_COORDINATOR, KEY_HASH_1000_GWEI, 150_000);
        vm.recordLogs();
        vm.prank(voter);
        admin.vote(proposalId, true);
        Request[] memory reissued = _decodeRequests(vm.getRecordedLogs());

        uint256 newSub = admin.subscriptionId();
        assertTrue(newSub != subId, "a new subscription");
        assertEq(admin.vrfKeyHash(), KEY_HASH_1000_GWEI);
        (,uint96 newBal,, address newOwner, address[] memory consumers) = coordinator.getSubscription(newSub);
        assertEq(newOwner, address(admin));
        assertEq(consumers.length, 1);
        assertEq(consumers[0], address(game));
        assertEq(newBal, 0, "the Admin held no native ETH to forward");
        assertEq(reissued.length, 1, "the stalled daily request was re-issued");
        assertEq(reissued[0].subId, newSub);
        assertEq(reissued[0].keyHash, KEY_HASH_1000_GWEI);
        assertEq(reissued[0].confirmations, 6);
        (,uint96 oldBal,, address oldOwner,) = coordinator.getSubscription(subId);
        assertEq(oldBal, 50 ether, "the retired subscription still holds the native ETH");
        assertEq(oldOwner, address(admin));

        // The new coordinator's answer settles the stalled day.
        assertTrue(_fulfill(reissued[0].id, 0x5A1E));
        _crank(200);
        assertFalse(game.rngLocked(), "the day settled on the replacement subscription");

        // Recovery: refused while the retired request is pending, then cancel + forward.
        vm.prank(_vaultOwner());
        vm.expectRevert(bytes4(keccak256("PendingRequestExists()")));
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retrySubCancel, (ForkPins.VRF_COORDINATOR, subId)), 0);
        // The retired request is answered late (the game ignores it: a different request id).
        uint48 processed = game.lastVrfProcessed();
        _fulfillOn(subId, stalled.id, 0xDEAD);
        assertEq(game.lastVrfProcessed(), processed, "late answer on the retired subscription ignored");
        vm.prank(_vaultOwner());
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retrySubCancel, (ForkPins.VRF_COORDINATOR, subId)), 0);
        (,newBal,,,) = coordinator.getSubscription(newSub);
        assertEq(newBal, 50 ether, "the retired native ETH funds the live subscription");
        assertEq(address(admin).balance, 0);
        vm.expectRevert(bytes4(keccak256("InvalidSubscription()")));
        coordinator.getSubscription(subId);
    }

    // ------------------------------------------------------------------ game over

    /// @notice The healthy ending: every request answered, so the final sweep's shutdownVrf
    ///         cancels the REAL subscription and the coordinator refunds its native ETH to the vault.
    function test_gameOverCancelsTheRealSubscriptionAndRefundsTheVault() public {
        _donate(makeAddr("donor"), 75 ether);
        _driveToGameOver();
        assertFalse(coordinator.pendingRequestExists(subId), "fixture: every request answered");
        uint256 vaultNative = ContractAddresses.VAULT.balance;
        uint96 subNative = _subBalance();
        assertEq(subNative, 75 ether, "fulfilment billing is not simulated");

        vm.recordLogs();
        vm.warp(vm.getBlockTimestamp() + 30 days + 1);
        _crank(40);
        assertEq(admin.subscriptionId(), 0, "handle spent");
        assertEq(ContractAddresses.VAULT.balance - vaultNative, subNative, "the vault received the native ETH");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool canceled;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == ForkPins.VRF_COORDINATOR && logs[i].topics[0] == SUBSCRIPTION_CANCELED) {
                (address to, uint256 unusedTokenRefund, uint256 amountNative) = abi.decode(logs[i].data, (address, uint256, uint256));
                assertEq(to, ContractAddresses.VAULT);
                assertEq(unusedTokenRefund, 0);
                assertEq(amountNative, subNative);
                canceled = true;
            }
        }
        assertTrue(canceled, "coordinator SubscriptionCanceled");
        vm.expectRevert(bytes4(keccak256("InvalidSubscription()")));
        coordinator.getSubscription(subId);
    }

    /// @notice The VRF-dead ending, on the real coordinator: the unanswered request is still
    ///         pending when the final sweep runs, so cancelSubscription reverts with
    ///         PendingRequestExists. shutdownVrf absorbs it (the sweep completes, the handle is
    ///         spent) and the native ETH stays in the subscription, still owned by the Admin.
    ///         retrySubCancel cannot recover it while the request is pending; if the coordinator
    ///         ever answers it, the same call refunds the vault.
    function test_deadVrfEndingLeavesNativeOnTheCoordinatorUntilTheRequestClears() public {
        _donate(makeAddr("donor"), 60 ether);
        vm.recordLogs();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 32 && !game.rngLocked(); ++i) {
            vm.prank(keeper);
            game.mineFlip(0);
        }
        assertTrue(game.rngLocked(), "fixture: daily request pending");

        // Fourteen days unanswered: the deterministic ending, then the sweep 30 days later. No
        // request is ever answered here.
        vm.warp(vm.getBlockTimestamp() + 15 days);
        for (uint256 i; i < 400 && !game.gameOver(); ++i) {
            vm.prank(keeper);
            try game.mineFlip(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                assertTrue(sel == NO_WORK || sel == RNG_NOT_READY, "dead-VRF ending reverted");
                vm.warp(vm.getBlockTimestamp() + 1 days);
            }
        }
        assertTrue(game.gameOver(), "the VRF-dead ending latched");
        vm.warp(vm.getBlockTimestamp() + 30 days + 1);
        for (uint256 i; i < 40 && admin.subscriptionId() != 0; ++i) {
            vm.prank(keeper);
            try game.mineFlip(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                assertTrue(sel == NO_WORK || sel == RNG_NOT_READY, "sweep reverted");
                break;
            }
        }
        Request[] memory all = _decodeRequests(vm.getRecordedLogs());
        assertGe(all.length, 1);

        assertEq(admin.subscriptionId(), 0, "the sweep spent the handle");
        assertEq(address(game).balance, 0, "the sweep completed");
        assertTrue(coordinator.pendingRequestExists(subId), "the dead request is still pending");
        (uint96 stranded,,, address owner,) = coordinator.getSubscription(subId);
        assertEq(stranded, 60 ether, "native ETH left on the coordinator");
        assertEq(owner, address(admin), "still owned by the Admin");

        uint256 vaultNative = ContractAddresses.VAULT.balance;
        vm.prank(_vaultOwner());
        vm.expectRevert(bytes4(keccak256("PendingRequestExists()")));
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retrySubCancel, (ForkPins.VRF_COORDINATOR, subId)), 0);

        // Should the coordinator ever answer, the retired subscription becomes cancellable.
        for (uint256 i; i < all.length; ++i) {
            if (coordinator.s_requestCommitments(all[i].id) != bytes32(0)) _fulfill(all[i].id, 0xD00D + i);
        }
        assertFalse(coordinator.pendingRequestExists(subId));
        vm.prank(_vaultOwner());
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retrySubCancel, (ForkPins.VRF_COORDINATOR, subId)), 0);
        assertEq(ContractAddresses.VAULT.balance - vaultNative, 60 ether, "recovered to the vault");
    }
}
