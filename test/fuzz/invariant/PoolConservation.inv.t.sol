// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {PoolFlowHandler} from "../handlers/PoolFlowHandler.sol";

/// @title PoolConservation — FUZZ-05 (POOL-CONSERVATION) canonical always-on conservation invariant.
///
/// @notice Builds the conservation oracle that the existing pool checks DO NOT assert (case (c) BUILD). The
///         four pool accessors already exist and `MultiLevel.inv.t.sol::invariant_poolSumConsistency` even READS
///         all four — but it asserts almost nothing (only `gameBalance >= claimablePool`; the other three pools
///         land in unused locals). `Composition.inv.t.sol::invariant_poolSolvency` sums the four pools but only
///         catches `sum > balance` after the fact. Neither asserts the FUZZ-05 property: that the
///         future->next->current / consolidation / skim / jackpot transfers CONSERVE the total and never mint
///         unbacked credit. This invariant asserts exactly that.
///
///         THE TWO PROPERTIES (driven by PoolFlowHandler over the [invariant] profile, runs=256 depth=128):
///
///         (1) invariant_totalPoolsFullyBacked — the backing bound, STRENGTHENED from MultiLevel's
///             `balance >= claimablePool` to the FULL summed obligation:
///               currentPrizePool + nextPrizePool + futurePrizePool + claimablePool
///                 <= address(game).balance + stETH.
///             A consolidation/jackpot transfer that inflated a pool beyond the ETH+stETH the contract holds
///             would break this. (MultiLevel's check only covers ONE of the four pools; this covers all four.)
///
///         (2) invariant_noUnbackedCreditMinted — the CONSERVATION property the others miss. The summed
///             four-pool obligation can never exceed the real ETH that actually entered the contract:
///               sum(4 pools) <= startingBacking + ghost_realInflow
///             where startingBacking is the setUp-time balance+stETH and ghost_realInflow is the cumulative
///             msg.value across successful buys. An internal transfer (future->next->current, the time-based
///             future-take skim, the jackpot settlement that credits claimable) can only RESHAPE the split
///             across the four pools — it can NEVER inflate the total out of thin air, because no real ETH
///             entered to back the new credit. A transfer that minted unbacked credit would push sum(4 pools)
///             above startingBacking + ghost_realInflow and this would FAIL. Outflow (claim payouts) only
///             SHRINKS the obligation, so the bound stays directionally safe without subtracting it.
///
///         NON-VACUITY. The conservation property is only meaningful if pool-to-pool transfers actually ran.
///         afterInvariant gates acceptance on ghost_advances > 0 — a campaign where advanceGame never succeeded
///         (no consolidation/skim/jackpot transfer ran) is a vacuous green and FAILS. A focused non-vacuity test
///         additionally drives the handler's advance action directly and asserts ghost_advances > 0 so a
///         transfer that silently minted unbacked credit could not hide behind a "nothing moved" green.
///
///         FALSIFIABILITY. A focused test seeds the exact T-381-05-01 bug shape — a pool inflated WITHOUT any
///         real ETH inflow (a transfer that mints unbacked credit) — by field-isolated vm.store-ing an
///         increment into futurePrizePool (slot 2 high half) with NO matching balance/inflow, then asserts BOTH
///         the backing bound AND the conservation bound now register the break. Restoring the slot returns both
///         to green. A passing assertion proves the wired conservation property is genuinely falsifiable, not
///         vacuously true.
///
/// @dev Test-only. ZERO contracts/*.sol mutation. All pool movement in the campaign is the contract's own doing
///      via real entrypoints (the handler NEVER vm.stores a pool); the falsifiability seed is confined to this
///      focused test and restored immediately.
contract PoolConservation is DeployProtocol {
    PoolFlowHandler public handler;

    // The setUp-time backing (ETH + stETH) captured BEFORE any handler action. The conservation bound is
    // sum(4 pools) <= startingBacking + ghost_realInflow: the obligation the contract recognizes can never
    // exceed (what was already there) + (real ETH that entered through buys).
    uint256 public startingBacking;

    // Slot 2 holds prizePoolsPacked = (futurePrizePool << 128) | nextPrizePool (forge inspect, authoritative).
    // Used ONLY by the focused falsifiability test to inject unbacked credit into futurePrizePool.
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        // Back the pool-moving buys with solvent funds so a buy/advance that DOES run does not revert on the
        // contract's balance — the conservation property is about whether transfers mint unbacked credit, not
        // about the contract running dry. This generous balance becomes part of startingBacking (a transfer
        // cannot mint credit against it: the bound is sum <= startingBacking + inflow, and an internal transfer
        // adds nothing to either side).
        vm.deal(address(game), 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);

        // Capture the backing AFTER funding but BEFORE any action, so ghost_realInflow accounts for every wei
        // that subsequently enters via a buy.
        startingBacking = address(game).balance + mockStETH.balanceOf(address(game));

        handler = new PoolFlowHandler(game, mockVRF, 5);
        targetContract(address(handler));
    }

    // =========================================================================
    // INVARIANT 1: sum(4 pools) <= ETH + stETH  (the FULL backing bound)
    // =========================================================================

    /// @notice The summed four-pool obligation is always fully backed by the ETH+stETH the contract holds. This
    ///         STRENGTHENS MultiLevel's `balance >= claimablePool` (one pool) to all four pools — a
    ///         consolidation/jackpot transfer that inflated a pool beyond the contract's backing would break it.
    function invariant_totalPoolsFullyBacked() public view {
        uint256 sumPools = game.currentPrizePoolView() +
            game.nextPrizePoolView() +
            game.futurePrizePoolView() +
            game.claimablePoolView();
        uint256 backing = address(game).balance + mockStETH.balanceOf(address(game));
        assertLe(
            sumPools,
            backing,
            "POOL-CONSERVATION: summed pool obligation exceeds ETH+stETH backing (unbacked credit)"
        );
    }

    // =========================================================================
    // INVARIANT 2: sum(4 pools) <= startingBacking + realInflow  (CONSERVATION)
    // =========================================================================

    /// @notice THE CONSERVATION PROPERTY the existing checks miss. The summed four-pool obligation can never
    ///         exceed the real ETH that actually entered the contract (startingBacking + the cumulative buy
    ///         msg.value). An internal transfer (future->next->current, the future-take skim, the jackpot
    ///         settlement crediting claimable) only RESHAPES the split across pools — it adds nothing to the
    ///         right-hand side, so it can never push the left-hand side above it. A transfer that minted
    ///         unbacked credit (inflated a pool with no matching inflow) would break this. Claim payouts only
    ///         SHRINK the obligation, so the bound stays directionally safe without subtracting outflow.
    function invariant_noUnbackedCreditMinted() public view {
        uint256 sumPools = game.currentPrizePoolView() +
            game.nextPrizePoolView() +
            game.futurePrizePoolView() +
            game.claimablePoolView();
        assertLe(
            sumPools,
            startingBacking + handler.ghost_realInflow(),
            "POOL-CONSERVATION: summed pool obligation exceeds startingBacking + real ETH inflow (unbacked credit minted by an internal transfer)"
        );
    }

    /// @notice Diagnostic: real ETH out never exceeds real ETH in plus what was already backing the contract.
    ///         A self-evident ledger sanity check (no payout draws more than entered + starting backing).
    function invariant_outflowNeverExceedsInflowPlusStart() public view {
        assertLe(
            handler.ghost_realOutflow(),
            startingBacking + handler.ghost_realInflow(),
            "ghost: cumulative payout never exceeds startingBacking + real inflow"
        );
    }

    // =========================================================================
    // NON-VACUITY: pool-to-pool transfers actually ran during the campaign
    // =========================================================================

    /// @notice afterInvariant runs once at the END of the campaign. The conservation property is only meaningful
    ///         if advanceGame actually ran the consolidation/skim/jackpot transfer machinery at least once —
    ///         otherwise no value ever moved between pools and the bound holds vacuously. Gating on
    ///         ghost_advances > 0 makes a "green because nothing moved" pass impossible: if no advance succeeded
    ///         across the 256/128 run, this campaign FAILS.
    function afterInvariant() public view {
        assertGt(
            handler.ghost_advances(),
            0,
            "NON-VACUITY: advanceGame must succeed > 0 times (else no pool-to-pool transfer ran and conservation is vacuous)"
        );
    }

    // =========================================================================
    // NON-VACUITY (focused): driving advance directly runs real pool transfers
    // =========================================================================

    /// @notice Drive the handler's advance action directly (deterministic seeds spanning the actor pool) and
    ///         assert ghost_advances > 0 — i.e. advanceGame ran the consolidation/skim/jackpot transfers at the
    ///         fixture level independent of the fuzzer's sequencing. A transfer that silently minted unbacked
    ///         credit would still move value here and so could be caught by the invariants. Also asserts the two
    ///         conservation bounds hold AFTER the directly-driven transfers (real movement, still conserved).
    function test_poolTransfersExercised_nonVacuous() public {
        // Seed some real inflow first so the pools have value to consolidate, then advance across the actors.
        for (uint256 a; a < handler.actorCount(); a++) {
            handler.buy(a, 1000, 0);
        }
        for (uint256 a; a < handler.actorCount(); a++) {
            handler.advance(a, a + 1);
        }

        assertGt(
            handler.ghost_advances(),
            0,
            "fixture: advanceGame ran > 0 times (real consolidation/skim/jackpot transfers occurred)"
        );

        // The conservation bounds must hold after the directly-driven transfers — value was RESHAPED across the
        // four pools, never minted.
        uint256 sumPools = game.currentPrizePoolView() +
            game.nextPrizePoolView() +
            game.futurePrizePoolView() +
            game.claimablePoolView();
        assertLe(
            sumPools,
            address(game).balance + mockStETH.balanceOf(address(game)),
            "fixture: pools fully backed after real transfers"
        );
        assertLe(
            sumPools,
            startingBacking + handler.ghost_realInflow(),
            "fixture: no unbacked credit after real transfers (sum <= startingBacking + inflow)"
        );
    }

    // =========================================================================
    // FALSIFIABILITY: a pool inflated with NO inflow breaks both conservation bounds
    // =========================================================================

    /// @notice The T-381-05-01 bug shape the net catches: an internal transfer (consolidation/skim/jackpot)
    ///         that mints unbacked credit — inflating a pool total with NO matching real ETH inflow. We simulate
    ///         that by field-isolated vm.store-ing an increment into futurePrizePool (slot 2 high half) WITHOUT
    ///         dealing any ETH or recording any inflow, then assert BOTH conservation bounds register the break:
    ///         the summed obligation now exceeds the ETH+stETH backing AND exceeds startingBacking + inflow.
    ///         Restoring the slot returns both bounds to green. If the invariant were vacuous (never reading the
    ///         inflated pool, or comparing against a quantity that drifts with it), this seeded break would NOT
    ///         register — so a passing assertion proves the wired conservation property is genuinely falsifiable.
    function test_invariantIsFalsifiable_unbackedCreditMint() public {
        // Pre: both bounds hold at fresh deploy (pools tiny vs. the generous backing).
        assertTrue(_backingBoundHolds(), "pre: backing bound holds before the seeded break");
        assertTrue(_conservationBoundHolds(), "pre: conservation bound holds before the seeded break");

        // Capture the real prizePoolsPacked slot.
        uint256 before = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT)));
        uint256 nextLow = uint128(before);
        uint256 futureHigh = before >> 128;

        // The bug: inflate futurePrizePool by an amount that exceeds ALL backing — a transfer minting credit
        // out of thin air, with NO ETH dealt and NO inflow recorded.
        uint256 injected = startingBacking + handler.ghost_realInflow() + 1_000 ether;
        uint256 broken = ((futureHigh + injected) << 128) | nextLow;
        vm.store(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT), bytes32(broken));

        // Both bounds must now register the break (the futurePrizePool inflation has no backing).
        assertEq(game.futurePrizePoolView(), futureHigh + injected, "the seeded futurePrizePool inflation is in effect");
        assertFalse(
            _backingBoundHolds(),
            "FALSIFIABILITY: an unbacked pool inflation must break sum(4 pools) <= ETH+stETH"
        );
        assertFalse(
            _conservationBoundHolds(),
            "FALSIFIABILITY: an unbacked pool inflation must break sum(4 pools) <= startingBacking + inflow"
        );

        // Restore — both bounds return to green (proves the break was the injection, not a pre-existing drift).
        vm.store(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT), bytes32(before));
        assertTrue(_backingBoundHolds(), "post: backing bound restored after undoing the seeded break");
        assertTrue(_conservationBoundHolds(), "post: conservation bound restored after undoing the seeded break");
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _sumFourPools() internal view returns (uint256) {
        return
            game.currentPrizePoolView() +
            game.nextPrizePoolView() +
            game.futurePrizePoolView() +
            game.claimablePoolView();
    }

    /// @dev Boolean form of invariant_totalPoolsFullyBacked (for the falsifiability test).
    function _backingBoundHolds() internal view returns (bool) {
        return _sumFourPools() <= address(game).balance + mockStETH.balanceOf(address(game));
    }

    /// @dev Boolean form of invariant_noUnbackedCreditMinted (for the falsifiability test).
    function _conservationBoundHolds() internal view returns (bool) {
        return _sumFourPools() <= startingBacking + handler.ghost_realInflow();
    }
}
