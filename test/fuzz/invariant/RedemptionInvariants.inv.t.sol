// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {RedemptionHandler} from "../handlers/RedemptionHandler.sol";
import {WrapperPathHandler} from "../handlers/WrapperPathHandler.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";

/// @title RedemptionInvariants -- Proves gambling burn redemption system invariants
/// @notice Current redemption solvency, supply, wrapper backing and claim invariants.
/// @dev Per-batch reservation sums and the supply cap are checked by RedemptionAccounting.
///      Legacy scalar slots and never-updated ghost counters are not current properties.
///         Exercises the full burn-resolve-claim lifecycle via RedemptionHandler and VRFHandler.
/// @dev Run: forge test --match-contract RedemptionInvariants -vv
///      Default profile: 256 runs, depth 128, fail_on_revert=false, show_metrics=true.
contract RedemptionInvariants is DeployProtocol {
    RedemptionHandler public handler;
    VRFHandler public vrfHandler;
    WrapperPathHandler public wrapperHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, coin, 5);
        vrfHandler = new VRFHandler(mockVRF, game);
        wrapperHandler = new WrapperPathHandler(sdgnrs, dgnrs, game, mockVRF, 3);
        vm.deal(address(sdgnrs), 10_000 ether);
        mockVRF.fundSubscription(1, 100 ether);
        for (uint256 i; i < handler.getActorCount(); ++i) _giveWalletId(handler.getActor(i));
        // Make redemption invariants non-vacuous even when random calls end the
        // game immediately: every sequence starts with a real pending claim.
        handler.action_burn(0, 10 ether);
        assertEq(handler.successfulBurns(), 1, "campaign starts with an admitted redemption");
        assertEq(handler.getBatchCount(), 1, "seeded batch is tracked");
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
    //                        INV-06: ROLL BOUNDS
    // =========================================================================

    /// @notice Roll bounds always in [21, 175] for resolved periods.
    /// @dev The handler's ghost_rollOutOfBounds counter increments if any
    ///      resolved period has a roll outside the valid range.
    function invariant_rollBounds() public view {
        assertEq(
            handler.ghost_rollOutOfBounds(),
            0,
            "INV-06: resolved roll outside [21, 175]"
        );
    }


    // =========================================================================
    //        FOCUSED: wrapper paths traverse deterministically (non-vacuity)
    // =========================================================================

    function test_seededRedemptionCompletesRealClaim() public {
        for (uint256 i; i < 32 && handler.ghost_claimCount() == 0; ++i) {
            handler.action_settle(99);
        }
        assertEq(handler.ghost_claimCount(), 1, "seeded redemption settles exactly once");
        invariant_ethSegregationSolvency();
        invariant_noDoubleClaim();
        invariant_supplyConsistency();
        invariant_rollBounds();
    }

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
        // Twelve actions: the genesis cohort's drain and the request cycle it shifts take ten.
        for (uint256 i; i < 12 && !game.gameOver(); i++) {
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
