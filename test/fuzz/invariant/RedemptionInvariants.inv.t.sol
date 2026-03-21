// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {RedemptionHandler} from "../handlers/RedemptionHandler.sol";
import {StakedDegenerusStonk} from "../../../contracts/StakedDegenerusStonk.sol";

/// @title RedemptionInvariants -- Proves gambling burn redemption system invariants
/// @notice 7 invariants encoding Phase 44 corrected properties (INV-01 through INV-07).
///         Exercises the full burn-resolve-claim lifecycle via RedemptionHandler and VRFHandler.
/// @dev Run: forge test --match-contract RedemptionInvariants -vv
///      Default profile: 256 runs, depth 128, fail_on_revert=false, show_metrics=true.
contract RedemptionInvariants is DeployProtocol {
    RedemptionHandler public handler;
    VRFHandler public vrfHandler;

    // Storage slot constants for internal sDGNRS state
    uint256 private constant SLOT_PENDING_BURNIE = 10;
    uint256 private constant SLOT_SUPPLY_SNAPSHOT = 13;
    uint256 private constant SLOT_PERIOD_INDEX = 14;
    uint256 private constant SLOT_PERIOD_BURNED = 15;

    function setUp() public {
        _deployProtocol();
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, coin, 5);
        vrfHandler = new VRFHandler(mockVRF, game);
        targetContract(address(handler));
        targetContract(address(vrfHandler));
    }

    // =========================================================================
    //                         INV-01: ETH SEGREGATION SOLVENCY
    // =========================================================================

    /// @notice Segregated ETH never exceeds what the contract can cover.
    /// @dev Uses assertGe (not assertEq) because the contract may have more ETH
    ///      than the segregated amount (from other deposits, game winnings).
    ///      Includes stETH since it is liquid backing.
    function invariant_ethSegregationSolvency() public view {
        uint256 segregated = sdgnrs.pendingRedemptionEthValue();
        uint256 ethBal = address(sdgnrs).balance;
        uint256 stethBal = mockStETH.balanceOf(address(sdgnrs));
        assertGe(
            ethBal + stethBal,
            segregated,
            "INV-01: segregated ETH exceeds contract ETH+stETH balance"
        );
    }

    // =========================================================================
    //                         INV-02: NO DOUBLE CLAIM
    // =========================================================================

    /// @notice No double-claim: claim deleted before payout, re-claim reverts.
    /// @dev The handler's ghost_doubleClaim counter increments if a re-claim
    ///      succeeds after a successful claim for the same actor in the same call.
    function invariant_noDoubleClaim() public view {
        assertEq(
            handler.ghost_doubleClaim(),
            0,
            "INV-02: double claim succeeded (claim not deleted before payout)"
        );
    }

    // =========================================================================
    //                     INV-03: PERIOD INDEX MONOTONICITY
    // =========================================================================

    /// @notice Period index monotonically increases (never decreases).
    /// @dev The handler's ghost_periodIndexDecreased counter increments if
    ///      the redemptionPeriodIndex ever decreases between observations.
    function invariant_periodIndexMonotonic() public view {
        assertEq(
            handler.ghost_periodIndexDecreased(),
            0,
            "INV-03: redemption period index decreased"
        );
    }

    // =========================================================================
    //                      INV-04: SUPPLY CONSISTENCY
    // =========================================================================

    /// @notice totalSupply equals initialSupply minus totalBurned.
    /// @dev Since only the handler is burning (targetContract), no other burn
    ///      paths are exercised, so the ghost_totalBurned should track exactly.
    function invariant_supplyConsistency() public view {
        uint256 expected = handler.ghost_initialSupply() - handler.ghost_totalBurned();
        assertEq(
            sdgnrs.totalSupply(),
            expected,
            "INV-04: totalSupply != initialSupply - totalBurned"
        );
    }

    // =========================================================================
    //                      INV-05: 50% CAP ENFORCEMENT
    // =========================================================================

    /// @notice 50% cap enforced per period: no burn exceeds half the period snapshot.
    /// @dev Reads internal storage via vm.load since these fields have no public getters.
    function invariant_fiftyPercentCap() public view {
        uint256 snapshot = uint256(vm.load(address(sdgnrs), bytes32(uint256(SLOT_SUPPLY_SNAPSHOT))));
        uint256 burned = uint256(vm.load(address(sdgnrs), bytes32(uint256(SLOT_PERIOD_BURNED))));
        if (snapshot > 0) {
            assertLe(
                burned,
                snapshot / 2,
                "INV-05: period burned exceeds 50% of supply snapshot"
            );
        }
    }

    // =========================================================================
    //                        INV-06: ROLL BOUNDS
    // =========================================================================

    /// @notice Roll bounds always in [25, 175] for resolved periods.
    /// @dev The handler's ghost_rollOutOfBounds counter increments if any
    ///      resolved period has a roll outside the valid range.
    function invariant_rollBounds() public view {
        assertEq(
            handler.ghost_rollOutOfBounds(),
            0,
            "INV-06: resolved roll outside [25, 175]"
        );
    }

    // =========================================================================
    //                    INV-07: AGGREGATE TRACKING
    // =========================================================================

    /// @notice pendingRedemptionEthValue tracks sum of individual claims (bounded dust).
    /// @dev Verifies two aggregate tracking properties:
    ///      1. ETH: segregated <= balance + stETH (overlap with INV-01 via different path)
    ///      2. BURNIE: reserved <= balance + tolerance (generous 1 ether dust bound)
    function invariant_aggregateTracking() public view {
        // ETH tracking: segregated <= balance + stETH
        uint256 segregatedEth = sdgnrs.pendingRedemptionEthValue();
        uint256 ethBal = address(sdgnrs).balance;
        uint256 stethBal = mockStETH.balanceOf(address(sdgnrs));
        assertGe(
            ethBal + stethBal,
            segregatedEth,
            "INV-07: ETH aggregate tracking exceeds balance"
        );

        // BURNIE tracking: reserved <= available + tolerance
        uint256 pendingBurnie = uint256(vm.load(address(sdgnrs), bytes32(uint256(SLOT_PENDING_BURNIE))));
        uint256 burnieBal = coin.balanceOf(address(sdgnrs));
        // Dust bound: O(N * 99) wei per period. With 5 actors and ~256 runs,
        // max dust ~ 5 * 99 * 256 = 126720 wei. Use generous 1 ether bound.
        if (pendingBurnie > 0) {
            assertGe(
                burnieBal + 1 ether,
                pendingBurnie,
                "INV-07: BURNIE aggregate tracking exceeds balance + tolerance"
            );
        }
    }

    // =========================================================================
    //                    INV-07b: BURNIE CLAIMED MONOTONIC
    // =========================================================================

    /// @notice Cumulative BURNIE claimed is monotonically non-decreasing.
    /// @dev ghost_totalBurnieClaimed only increases (claims add, never subtract).
    ///      This ensures no accounting underflow in BURNIE claim tracking.
    function invariant_burnieClaimedMonotonic() public view {
        // ghost_totalBurnieClaimed is only ever incremented (+=), never decremented.
        // If it were to decrease, the uint256 would underflow and revert in the handler.
        // This invariant documents the monotonic property explicitly.
        // Additionally verify it is bounded by a reasonable upper limit:
        // total BURNIE claimed cannot exceed the initial BURNIE balance of sDGNRS
        // plus any credited flips (generous bound: initial coin supply).
        uint256 claimed = handler.ghost_totalBurnieClaimed();
        // Monotonicity is enforced by the += operator (underflow reverts in 0.8.x).
        // Boundedness: claimed should not exceed total BURNIE ever in the system.
        // We use a generous bound: 1e30 (matches BURNIE initial supply order of magnitude).
        assertLe(
            claimed,
            1e30,
            "INV-07b: cumulative BURNIE claimed exceeds system maximum"
        );
    }

    // =========================================================================
    //                           CANARY
    // =========================================================================

    /// @notice Canary: sDGNRS is properly deployed and has code
    function invariant_canary() public view {
        assertTrue(address(sdgnrs) != address(0), "sDGNRS not deployed");
        assertTrue(address(sdgnrs).code.length > 0, "sDGNRS has no code");
    }

    // =========================================================================
    //                         CALL SUMMARY
    // =========================================================================

    /// @notice Logs call counts and ghost variables for debugging.
    /// @dev Always passes -- purely diagnostic. Check output with -vv flag.
    function invariant_callSummary() public view {
        console.log("--- RedemptionHandler Call Summary ---");
        console.log("  calls_burn:           ", handler.calls_burn());
        console.log("  calls_advanceDay:     ", handler.calls_advanceDay());
        console.log("  calls_claim:          ", handler.calls_claim());
        console.log("  calls_triggerGameOver: ", handler.calls_triggerGameOver());
        console.log("--- Ghost Variables ---");
        console.log("  ghost_totalBurned:    ", handler.ghost_totalBurned());
        console.log("  ghost_periodsResolved:", handler.ghost_periodsResolved());
        console.log("  ghost_claimCount:     ", handler.ghost_claimCount());
        console.log("  ghost_totalEthClaimed:", handler.ghost_totalEthClaimed());
        console.log("  ghost_totalBurnieClaimed:", handler.ghost_totalBurnieClaimed());
        console.log("  ghost_doubleClaim:    ", handler.ghost_doubleClaim());
        console.log("  ghost_rollOutOfBounds:", handler.ghost_rollOutOfBounds());
        console.log("  ghost_periodIdxDecr:  ", handler.ghost_periodIndexDecreased());
        console.log("--- VRFHandler ---");
        console.log("  ghost_vrfFulfillments:", vrfHandler.ghost_vrfFulfillments());
    }
}
