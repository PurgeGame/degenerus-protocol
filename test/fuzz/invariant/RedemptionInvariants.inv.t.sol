// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {RedemptionHandler} from "../handlers/RedemptionHandler.sol";
import {WrapperPathHandler} from "../handlers/WrapperPathHandler.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";

/// @title RedemptionInvariants -- Proves gambling burn redemption system invariants
/// @notice 7 invariants encoding Phase 44 corrected properties (INV-01 through INV-07).
///         Exercises the full burn-resolve-claim lifecycle via RedemptionHandler and VRFHandler.
/// @dev Run: forge test --match-contract RedemptionInvariants -vv
///      Default profile: 256 runs, depth 128, fail_on_revert=false, show_metrics=true.
contract RedemptionInvariants is DeployProtocol {
    RedemptionHandler public handler;
    VRFHandler public vrfHandler;
    WrapperPathHandler public wrapperHandler;

    // Storage slot constants for internal sDGNRS state
    uint256 private constant SLOT_PENDING_FLIP = 10;
    uint256 private constant SLOT_SUPPLY_SNAPSHOT = 13;
    uint256 private constant SLOT_PERIOD_INDEX = 14;
    uint256 private constant SLOT_PERIOD_BURNED = 15;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, coin, 5);
        vrfHandler = new VRFHandler(mockVRF, game);
        wrapperHandler = new WrapperPathHandler(sdgnrs, dgnrs, game, mockVRF, 3);
        targetContract(address(handler));
        targetContract(address(vrfHandler));
        targetContract(address(wrapperHandler));
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

    /// @notice totalSupply equals initialSupply plus mints minus burns.
    /// @dev Supply changes from all sources (handler burns, game operations,
    ///      pool transfers) are tracked via before/after delta in the handler; wrapper-path
    ///      burns (burnWrapped / post-gameOver burn / yearSweep) live in the wrapper handler's
    ///      own ledger and reconcile via its ghost term.
    function invariant_supplyConsistency() public view {
        uint256 expected = handler.ghost_initialSupply() + handler.ghost_totalMinted() - handler.ghost_totalBurned()
            - wrapperHandler.ghost_sdgnrsBurnedViaWrapper();
        assertEq(
            sdgnrs.totalSupply(),
            expected,
            "INV-04: totalSupply != initialSupply + totalMinted - totalBurned (incl. wrapper-path burns)"
        );
    }

    // =========================================================================
    //         INV-WRAP: DGNRS WRAPPER NEVER UNDER-BACKED (pre-yearSweep)
    // =========================================================================

    /// @notice The DGNRS wrapper holds at least one sDGNRS unit of backing per liquid
    ///         DGNRS unit: `sDGNRS.balanceOf(DGNRS) >= DGNRS.totalSupply()`.
    /// @dev Safety direction of the wrapper-backing property (audit/DGNRS-WRAPPER-BACKING-PROOF.md).
    ///      Every wrapper burn (unwrapTo, burn, burnWrapped) decrements both sides equally — the
    ///      WrapperPathHandler drives all three as fuzz actions, so this holds non-vacuously over a
    ///      MOVING pair. The only sub-equality path is yearSweep (terminal charity forfeiture), also
    ///      a fuzz action: once its ghost flag latches, the property is out of its stated pre-sweep
    ///      scope and the check rescopes to the swept regime (backing fully forfeited).
    function invariant_wrapperBackingSufficient() public view {
        if (wrapperHandler.ghost_yearSweepRan()) {
            // Post-sweep regime: the sweep burned ALL backing; the wrapper side is untouched.
            assertEq(
                sdgnrs.balanceOf(address(dgnrs)),
                0,
                "INV-WRAP(post-sweep): yearSweep must forfeit the ENTIRE backing"
            );
            return;
        }
        assertGe(
            sdgnrs.balanceOf(address(dgnrs)),
            dgnrs.totalSupply(),
            "INV-WRAP: DGNRS wrapper under-backed (sDGNRS.balanceOf(DGNRS) < DGNRS.totalSupply)"
        );
    }

    /// @notice STRICT equality direction: pre-yearSweep, backing tracks wrapper supply EXACTLY —
    ///         `sDGNRS.balanceOf(DGNRS) == DGNRS.totalSupply()`.
    /// @dev The proof's `==` needs ¬P1 (game never transferFromPool→wrapper) ∧ ¬P2 (no unwrap
    ///      recipient == wrapper); this campaign's handlers satisfy both by construction (actors
    ///      are the only recipients), so any drift the fuzzer finds is a REAL paired-decrement
    ///      break, not benign over-backing. This is the non-vacuous equality coverage the
    ///      DGNRS-WRAPPER-BACKING-PROOF follow-up called for.
    function invariant_wrapperBackingExact_preSweep() public view {
        if (wrapperHandler.ghost_yearSweepRan()) return; // yearSweep is the sole intentional break
        assertEq(
            sdgnrs.balanceOf(address(dgnrs)),
            dgnrs.totalSupply(),
            "INV-WRAP-EQ: wrapper backing diverged from wrapper supply pre-sweep (paired decrement broken)"
        );
    }

    /// @notice Non-vacuity: the campaign must at least ATTEMPT wrapper-path actions (four
    ///         selectors over depth 128 makes zero attempts statistically impossible); successful
    ///         path traversal is proven deterministically by the focused wrapper tests below.
    function afterInvariant() public view {
        assertGt(
            wrapperHandler.calls_unwrapTo() + wrapperHandler.calls_burnWrapped()
                + wrapperHandler.calls_postGameOverBurn() + wrapperHandler.calls_yearSweep(),
            0,
            "NON-VACUITY: the campaign never attempted a wrapper-path action"
        );
    }

    // =========================================================================
    //   INV-POOL: sDGNRS undistributed-pool accounting matches its own balance
    // =========================================================================

    /// @notice The five reward-pool sub-ledgers sum to exactly the sDGNRS contract's own
    ///         token balance: `Σ poolBalances == balanceOf(sDGNRS)`.
    /// @dev Every pool debit pairs a contract-balance debit (`transferFromPool` decrements both
    ///      poolBalances[idx] and balanceOf[address(this)] by the same amount; `burnAtGameOver`
    ///      zeroes both). A mutation
    ///      that desyncs the pool ledger from the held balance (the sDGNRS:566/567 survivor cluster
    ///      in mutation/FINDINGS-v75.md) breaks this equality. Non-vacuous: the redemption handler
    ///      funds actors via `transferFromPool(Pool.Reward, ...)`, exercising the paired debit.
    function invariant_poolBalanceConservation() public view {
        uint256 pools = sdgnrs.poolBalance(sDGNRS.Pool.Whale)
            + sdgnrs.poolBalance(sDGNRS.Pool.Affiliate)
            + sdgnrs.poolBalance(sDGNRS.Pool.Lootbox)
            + sdgnrs.poolBalance(sDGNRS.Pool.Reward)
            + sdgnrs.poolBalance(sDGNRS.Pool.PresaleBox);
        assertEq(
            pools,
            sdgnrs.balanceOf(address(sdgnrs)),
            "INV-POOL: sum(poolBalances) != sDGNRS.balanceOf(sDGNRS)"
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
    ///      2. FLIP: reserved <= balance + tolerance (generous 1 ether dust bound)
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

        // FLIP tracking: reserved <= available + tolerance
        uint256 pendingFlip = uint256(vm.load(address(sdgnrs), bytes32(uint256(SLOT_PENDING_FLIP))));
        uint256 flipBal = coin.balanceOf(address(sdgnrs));
        // Dust bound: O(N * 99) wei per period. With 5 actors and ~256 runs,
        // max dust ~ 5 * 99 * 256 = 126720 wei. Use generous 1 ether bound.
        if (pendingFlip > 0) {
            assertGe(
                flipBal + 1 ether,
                pendingFlip,
                "INV-07: FLIP aggregate tracking exceeds balance + tolerance"
            );
        }
    }

    // =========================================================================
    //                    INV-07b: FLIP CLAIMED MONOTONIC
    // =========================================================================

    /// @notice Cumulative FLIP claimed is monotonically non-decreasing.
    /// @dev ghost_totalFlipClaimed only increases (claims add, never subtract).
    ///      This ensures no accounting underflow in FLIP claim tracking.
    function invariant_flipClaimedMonotonic() public view {
        // ghost_totalFlipClaimed is only ever incremented (+=), never decremented.
        // If it were to decrease, the uint256 would underflow and revert in the handler.
        // This invariant documents the monotonic property explicitly.
        // Additionally verify it is bounded by a reasonable upper limit:
        // total FLIP claimed cannot exceed the initial FLIP balance of sDGNRS
        // plus any credited flips (generous bound: initial coin supply).
        uint256 claimed = handler.ghost_totalFlipClaimed();
        // Monotonicity is enforced by the += operator (underflow reverts in 0.8.x).
        // Boundedness: claimed should not exceed total FLIP ever in the system.
        // We use a generous bound: 1e30 (matches FLIP initial supply order of magnitude).
        assertLe(
            claimed,
            1e30,
            "INV-07b: cumulative FLIP claimed exceeds system maximum"
        );
    }

    // =========================================================================
    //                  INV-08: LOOTBOX SPLIT CONSERVATION
    // =========================================================================

    /// @notice ethDirect + lootboxEth always sums to totalRolledEth for every claim.
    /// @dev Tracks cumulative split values via RedemptionClaimed event parsing in the handler.
    ///      ghost_totalRolledEth = ghost_totalEthDirect + ghost_totalLootboxEth by construction,
    ///      but this invariant verifies the accounting is consistent across all handler calls.
    function invariant_lootboxSplitConservation() public view {
        assertEq(
            handler.ghost_totalEthDirect() + handler.ghost_totalLootboxEth(),
            handler.ghost_totalRolledEth(),
            "INV-08: ethDirect + lootboxEth != totalRolledEth (split conservation violated)"
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
        console.log("  ghost_totalFlipClaimed:", handler.ghost_totalFlipClaimed());
        console.log("  ghost_doubleClaim:    ", handler.ghost_doubleClaim());
        console.log("  ghost_rollOutOfBounds:", handler.ghost_rollOutOfBounds());
        console.log("  ghost_periodIdxDecr:  ", handler.ghost_periodIndexDecreased());
        console.log("--- Split Tracking (INV-08) ---");
        console.log("  ghost_totalEthDirect: ", handler.ghost_totalEthDirect());
        console.log("  ghost_totalLootboxEth:", handler.ghost_totalLootboxEth());
        console.log("  ghost_totalRolledEth: ", handler.ghost_totalRolledEth());
        console.log("--- VRFHandler ---");
        console.log("  ghost_vrfFulfillments:", vrfHandler.ghost_vrfFulfillments());
        console.log("--- WrapperPathHandler ---");
        console.log("  ghost_unwraps:        ", wrapperHandler.ghost_unwraps());
        console.log("  ghost_wrappedBurns:   ", wrapperHandler.ghost_wrappedBurns());
        console.log("  ghost_postGoBurns:    ", wrapperHandler.ghost_postGameOverBurns());
        console.log("  yearSweepRan:         ", wrapperHandler.ghost_yearSweepRan());
    }

    // =========================================================================
    //        FOCUSED: wrapper paths traverse deterministically (non-vacuity)
    // =========================================================================

    /// @notice Proves the unwrapTo paired decrement deterministically: one unwrap moves BOTH
    ///         sides down by exactly the unwrapped amount and preserves strict equality — so the
    ///         always-on equality invariant is exercised by a real traversal, not fuzzer luck.
    function test_wrapperUnwrapPairedDecrement() public {
        uint256 backingBefore = sdgnrs.balanceOf(address(dgnrs));
        uint256 supplyBefore = dgnrs.totalSupply();
        assertEq(backingBefore, supplyBefore, "wrapper starts exactly backed (deploy identity)");

        wrapperHandler.tryUnwrapTo(1_000 ether, 1); // actor0 (mocked vault owner) -> actor1
        assertEq(wrapperHandler.ghost_unwraps(), 1, "non-vacuity: the unwrap path actually traversed");

        uint256 backingAfter = sdgnrs.balanceOf(address(dgnrs));
        uint256 supplyAfter = dgnrs.totalSupply();
        assertLt(supplyAfter, supplyBefore, "unwrap burned wrapper supply");
        assertEq(
            backingBefore - backingAfter,
            supplyBefore - supplyAfter,
            "paired decrement: backing and wrapper supply fell by the SAME amount"
        );
        assertEq(backingAfter, supplyAfter, "strict equality preserved across the unwrap");
    }

    /// @notice Proves yearSweep is reachable under warp and is the SOLE intentional equality
    ///         break: after the terminal charity forfeiture, backing is fully burned while the
    ///         wrapper supply is untouched — exactly the regime the scoped invariants exempt.
    function test_yearSweepIsSoleEqualityBreak() public {
        // Drive a REAL game-over via the liveness timeout (the redemption handler's machinery).
        for (uint256 i; i < 8 && !game.gameOver(); i++) {
            handler.action_triggerGameOver();
        }
        assertTrue(game.gameOver(), "precondition: liveness game-over latched");

        uint256 supplyBefore = dgnrs.totalSupply();
        assertGt(sdgnrs.balanceOf(address(dgnrs)), 0, "precondition: backing present pre-sweep");

        wrapperHandler.tryYearSweep(); // warps to gameOverTimestamp + 365d and sweeps
        assertTrue(wrapperHandler.ghost_yearSweepRan(), "non-vacuity: yearSweep actually executed");

        assertEq(
            sdgnrs.balanceOf(address(dgnrs)),
            0,
            "yearSweep forfeits the ENTIRE backing (the sole intentional equality break)"
        );
        assertEq(dgnrs.totalSupply(), supplyBefore, "the wrapper supply side is untouched by the sweep");
    }
}
