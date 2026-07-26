// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockLinkToken} from "../../contracts/mocks/MockLinkToken.sol";

/// @dev A retired VRF coordinator that models the two behaviours the shared MockVRFCoordinator
///      does not: `cancelSubscription` reverting while the subscription still has an
///      outstanding request (Chainlink v2.5 `PendingRequestExists`), and refunding the balance
///      in LINK rather than native. Both are load-bearing for retrySubCancel — without the
///      revert there is no retry to test, and without the LINK refund nothing lands to forward.
contract RetiredCoordinator {
    error PendingRequestExists();

    MockLinkToken private immutable link;
    bool public backlogPending = true;
    bool public cancelled;

    constructor(MockLinkToken link_) {
        link = link_;
    }

    function clearBacklog() external {
        backlogPending = false;
    }

    function cancelSubscription(uint256, address to) external {
        if (backlogPending) revert PendingRequestExists();
        cancelled = true;
        uint256 bal = link.balanceOf(address(this));
        if (bal != 0) link.transfer(to, bal);
    }
}

/// @title RetrySubCancel — LINK recovery from a retired VRF subscription must never be one-shot.
/// @notice A coordinator swap overwrites `coordinator`/`subscriptionId` but never transfers
///         subscription ownership, so DegenerusAdmin stays the retired subscription's owner and
///         can still cancel it. `cancelSubscription` reverts while a request is outstanding —
///         the normal state at swap time — so the recovery has to survive failing and being
///         retried later, on BOTH legs: the cancel and the forward.
contract RetrySubCancelTest is DeployProtocol {
    event SubscriptionRecovered(uint256 indexed subId, address indexed to, uint256 amount);

    RetiredCoordinator private retired;
    address private vaultOwner;
    address private outsider;

    uint256 private constant RETIRED_SUB = 4242;
    uint256 private constant STRANDED = 500 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        vaultOwner = makeAddr("retry_vaultOwner");
        outsider = makeAddr("retry_outsider");
        vm.mockCall(
            address(vault),
            abi.encodeWithSignature("isVaultOwner(address)", vaultOwner),
            abi.encode(true)
        );

        // A retired coordinator still holding the stranded LINK balance.
        retired = new RetiredCoordinator(mockLINK);
        mockLINK.mint(address(retired), STRANDED);
    }

    function _linkOf(address a) internal view returns (uint256) {
        return mockLINK.balanceOf(a);
    }

    function _liveSubBalance() internal view returns (uint96 bal) {
        (bal, , , , ) = mockVRF.getSubscription(1);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Access control and the live-pair guard
    // ──────────────────────────────────────────────────────────────────────

    function test_rejectsNonVaultOwner() public {
        vm.prank(outsider);
        vm.expectRevert(bytes4(keccak256("NotAuthorized()")));
        admin.retrySubCancel(address(retired), RETIRED_SUB);
    }

    /// @notice Cancelling the LIVE pair would delete the subscription the game points at.
    function test_rejectsLivePair() public {
        address liveCoord = admin.coordinator();
        uint256 liveSub = admin.subscriptionId();

        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("SubscriptionActive()")));
        admin.retrySubCancel(liveCoord, liveSub);
    }

    /// @notice The guard keys on the PAIR: the same id on a different coordinator is retired.
    function test_sameSubIdOnDifferentCoordinatorIsNotTheLivePair() public {
        retired.clearBacklog();
        uint256 liveId = admin.subscriptionId();

        vm.prank(vaultOwner);
        admin.retrySubCancel(address(retired), liveId); // must not revert
        assertTrue(retired.cancelled(), "retired cancel did not run");
    }

    // ──────────────────────────────────────────────────────────────────────
    // THE POINT: not one-shot
    // ──────────────────────────────────────────────────────────────────────

    /// @notice While the backlog is pending the cancel REVERTS — surfacing to the caller
    ///         rather than silently consuming the attempt — and the exact same call succeeds
    ///         once the old coordinator drains. Nothing is spent by the failed try.
    function test_revertsWhileBacklogPending_thenSucceedsOnRetry() public {
        vm.prank(vaultOwner);
        vm.expectRevert(RetiredCoordinator.PendingRequestExists.selector);
        admin.retrySubCancel(address(retired), RETIRED_SUB);

        assertEq(_linkOf(address(retired)), STRANDED, "failed attempt moved LINK");
        assertFalse(retired.cancelled(), "cancel recorded despite revert");

        // The old coordinator finally drains its backlog.
        retired.clearBacklog();

        vm.prank(vaultOwner);
        admin.retrySubCancel(address(retired), RETIRED_SUB);

        assertEq(_linkOf(address(retired)), 0, "stranded LINK not recovered on retry");
    }

    /// @notice Repeated failures stay retryable — the attempt is not consumed by trying.
    function test_repeatedFailuresRemainRetryable() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(vaultOwner);
            vm.expectRevert(RetiredCoordinator.PendingRequestExists.selector);
            admin.retrySubCancel(address(retired), RETIRED_SUB);
        }
        retired.clearBacklog();
        vm.prank(vaultOwner);
        admin.retrySubCancel(address(retired), RETIRED_SUB);
        assertEq(_linkOf(address(retired)), 0, "recovery blocked after repeated failures");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Routing
    // ──────────────────────────────────────────────────────────────────────

    /// @notice While the game runs, recovered LINK refuels the LIVE subscription.
    function test_refuelsLiveSubscriptionWhileGameRuns() public {
        retired.clearBacklog();
        uint96 before = _liveSubBalance();

        vm.prank(vaultOwner);
        admin.retrySubCancel(address(retired), RETIRED_SUB);

        assertEq(
            uint256(_liveSubBalance()),
            uint256(before) + STRANDED,
            "recovered LINK did not refuel the live subscription"
        );
        assertEq(_linkOf(address(admin)), 0, "LINK stalled in Admin");
    }

    /// @notice At game over the vault is the terminal destination, matching shutdownVrf.
    function test_routesToVaultAtGameOver() public {
        retired.clearBacklog();
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("gameOver()"),
            abi.encode(true)
        );
        uint256 vaultBefore = _linkOf(address(vault));

        vm.prank(vaultOwner);
        admin.retrySubCancel(address(retired), RETIRED_SUB);

        assertEq(
            _linkOf(address(vault)) - vaultBefore,
            STRANDED,
            "recovered LINK did not reach the vault at game over"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // The second leg: a cancel that succeeded but whose forward failed
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A failed forward rolls the cancel back with it: the whole call reverts, the
    ///         retired subscription is untouched, and no LINK is left parked in Admin with the
    ///         handle already spent. The same call then succeeds once the forward recovers.
    function test_failedForwardRollsBackAtomically() public {
        retired.clearBacklog();

        vm.mockCallRevert(
            address(mockLINK),
            abi.encodeWithSelector(MockLinkToken.transferAndCall.selector),
            "forward down"
        );

        vm.prank(vaultOwner);
        vm.expectRevert();
        admin.retrySubCancel(address(retired), RETIRED_SUB);

        // Cancel rolled back with the forward — nothing moved, nothing spent.
        assertEq(_linkOf(address(retired)), STRANDED, "cancel was not rolled back");
        assertEq(_linkOf(address(admin)), 0, "LINK parked in Admin after a failed forward");
        assertFalse(retired.cancelled(), "cancel persisted through a reverted call");

        // Forward recovers; the identical call now completes.
        vm.clearMockedCalls();
        vm.mockCall(
            address(vault),
            abi.encodeWithSignature("isVaultOwner(address)", vaultOwner),
            abi.encode(true)
        );
        uint96 before = _liveSubBalance();

        vm.prank(vaultOwner);
        admin.retrySubCancel(address(retired), RETIRED_SUB);

        assertEq(_linkOf(address(admin)), 0, "LINK stalled in Admin");
        assertEq(
            uint256(_liveSubBalance()),
            uint256(before) + STRANDED,
            "retried recovery did not reach the live subscription"
        );
    }
}
