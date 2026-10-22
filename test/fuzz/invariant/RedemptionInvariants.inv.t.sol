// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {RedemptionHandler} from "../handlers/RedemptionHandler.sol";
import {WrapperPathHandler} from "../handlers/WrapperPathHandler.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {GameFunding} from "../../helpers/GameFunding.sol";

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
        GameFunding.credit(2, 10_000 ether);
        mockVRF.fundSubscription(1, 100 ether);
        for (uint256 i; i < handler.getActorCount(); ++i) _giveWalletId(handler.getActor(i));
        // A wrapped gambling burn records its claim on the burner's wallet ID; without one every
        // tryBurnWrapped reverts NoWalletId.
        for (uint256 i; i < wrapperHandler.actorCount(); ++i) _giveWalletId(wrapperHandler.actors(i));
        handler.setStethMock(address(mockStETH));
        // Make redemption invariants non-vacuous even when random calls end the
        // game immediately: every sequence starts with a real pending claim.
        handler.action_burn(0, 10 ether);
        assertEq(handler.successfulBurns(), 1, "campaign starts with an admitted redemption");
        assertEq(handler.getBatchCount(), 1, "seeded batch is tracked");
        targetContract(address(handler));
        targetContract(address(vrfHandler));
        targetContract(address(wrapperHandler));
        // The handlers never read msg.sender. The fuzz dictionary includes protocol addresses; with sDGNRS as
        // the sender the deep run lost its ETH between two calls (no replay reproduces it), so callers are plain accounts.
        for (uint160 i = 1; i <= 4; ++i) targetSender(address(0xCAFE00 + i));
        // The two fixture setters are configuration, not actions: a random setStethMock address makes
        // every later funding toggle revert.
        bytes4[] memory redemptionSelectors = new bytes4[](7);
        redemptionSelectors[0] = RedemptionHandler.action_burn.selector;
        redemptionSelectors[1] = RedemptionHandler.action_burnOnPreviousDay.selector;
        redemptionSelectors[2] = RedemptionHandler.action_advanceDay.selector;
        redemptionSelectors[3] = RedemptionHandler.action_settle.selector;
        redemptionSelectors[4] = RedemptionHandler.action_triggerGameOverSometimes.selector;
        redemptionSelectors[5] = RedemptionHandler.action_claim.selector;
        redemptionSelectors[6] = RedemptionHandler.action_toggleStethFallback.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: redemptionSelectors}));
        // VRF transport only: the 30-day warpTime trips the VRF deadman (liveness) within a few draws, which
        // blocks every burn; game over is driven by the redemption handler's own trigger.
        bytes4[] memory vrfSelectors = new bytes4[](2);
        vrfSelectors[0] = VRFHandler.fulfillVrf.selector;
        vrfSelectors[1] = VRFHandler.warpPastVrfTimeout.selector;
        targetSelector(FuzzSelector({addr: address(vrfHandler), selectors: vrfSelectors}));
    }

    // =========================================================================
    //                         INV-01: ETH SEGREGATION SOLVENCY
    // =========================================================================

    /// @notice Segregated redemption value never exceeds what backs it.
    /// @dev Live, the Game's redemption reserve backs it and sDGNRS custody is ignored; after game
    ///      over custody and sDGNRS's Game claimable (which holds the released reserve) back it.
    ///      Uses assertGe (not assertEq): backing may exceed the segregated amount.
    function invariant_ethSegregationSolvency() public view {
        uint256 segregated = sdgnrs.pendingRedemptionEthValue();
        uint256 backing = game.redemptionReserve();
        if (game.gameOver()) {
            uint256 claimable = game.claimableWinningsOf(address(sdgnrs));
            backing += address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)) + (claimable > 1 ? claimable - 1 : 0);
        }
        assertGe(
            backing,
            segregated,
            "INV-01: segregated redemption value exceeds its backing"
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

    /// @notice Non-vacuity: the campaign must actually complete the redemption lifecycle and move the
    ///         wrapper, not merely attempt it.
    /// @dev Successes, not attempts. Liveness (game over's first step) blocks every burn, so the campaign
    ///      keeps it rare enough for the lifecycle to run first: the game-over trigger acts on one draw in four
    ///      and the VRF warps stop at the retry timeout. Measured over 1,798 default-profile runs: about 2 campaign burns per run, a batch resolved in 90% of runs, a claim in
    ///      94%, an unwrap in 56%, a wrapped burn in 60%, a post-game-over wrapper burn in 33%, the year sweep
    ///      in 91%. Successes are therefore accumulated over the process (unique RI_ prefix) and each
    ///      leg must be non-zero once MIN_RUNS runs have completed: a campaign burn beyond the seeded one,
    ///      a resolved batch, a claim, an unwrap, a wrapped gambling burn, a year sweep and, after
    ///      POST_GO_MIN_RUNS runs, a post-game-over wrapper burn.
    uint256 private constant MIN_RUNS = 16;
    /// @dev The ten invariants of this contract run in parallel on the same fuzz seed, so the first runs are the
    ///      same few sequences counted ten times; the rarest leg (a wrapper burn after game over: 113 burns over 256
    ///      single-test runs) is required only once enough cumulative runs hold distinct ones.
    uint256 private constant POST_GO_MIN_RUNS = 256;

    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        uint256 runs = _acc("RI_RUNS", 1);
        uint256 burns = _acc("RI_burns", handler.successfulBurns() - 1); // the seeded burn excluded
        uint256 resolved = _acc("RI_resolved", handler.ghost_resolvedBatches());
        uint256 claims = _acc("RI_claims", handler.ghost_claimCount());
        uint256 unwraps = _acc("RI_unwraps", wrapperHandler.ghost_unwraps());
        uint256 wrapped = _acc("RI_wrappedBurns", wrapperHandler.ghost_wrappedBurns());
        uint256 postGo = _acc("RI_postGoBurns", wrapperHandler.ghost_postGameOverBurns());
        uint256 sweeps = _acc("RI_sweeps", wrapperHandler.ghost_yearSweepRan() ? 1 : 0);
        if (runs < MIN_RUNS) return;
        assertGt(burns, 0, "NON-VACUITY: no campaign redemption burn ever succeeded");
        assertGt(resolved, 0, "NON-VACUITY: no redemption batch was ever resolved");
        assertGt(claims, 0, "NON-VACUITY: no redemption was ever claimed");
        assertGt(unwraps, 0, "NON-VACUITY: no unwrapTo ever succeeded");
        assertGt(wrapped, 0, "NON-VACUITY: no wrapped gambling burn ever succeeded");
        assertGt(sweeps, 0, "NON-VACUITY: the year sweep never ran");
        if (runs < POST_GO_MIN_RUNS) return;
        assertGt(postGo, 0, "NON-VACUITY: no post-game-over wrapper burn ever succeeded");
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
            + sdgnrs.poolBalance(sDGNRS.Pool.Degenesis);
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
