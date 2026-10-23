// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {RedemptionHandler} from "../fuzz/handlers/RedemptionHandler.sol";

/// @notice Independent token, reserve, cap and first-write accounting across real requests.
contract RedemptionAccounting is RedemptionFixture {
    RedemptionHandler public handler;
    function setUp() public override {
        super.setUp();
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, coin, 4);
        handler.setCoinflip(address(coinflip));
        handler.setStethMock(address(mockStETH));
        for (uint256 i; i < handler.getActorCount(); ++i) _giveWalletId(handler.getActor(i));
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = RedemptionHandler.action_burn.selector;
        selectors[1] = RedemptionHandler.action_advanceDay.selector;
        selectors[2] = RedemptionHandler.action_claim.selector;
        selectors[3] = RedemptionHandler.action_triggerGameOverSometimes.selector;
        selectors[4] = RedemptionHandler.action_burnOnPreviousDay.selector;
        selectors[5] = RedemptionHandler.action_toggleStethFallback.selector;
        selectors[6] = RedemptionHandler.action_settle.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        // Ensure all campaigns start with a real claim, not only reverting random actions.
        uint256 amount = _minimumLiveBurn();
        handler.action_burn(0, amount);
        assertEq(handler.successfulBurns(), 1, "campaign starts with an admitted redemption");
        assertEq(handler.getBatchCount(), 1, "seeded batch is tracked");
    }
    /// @dev Batch records live in a two-slot parity ring: only the open batch and the one
    ///      before it are retained; an earlier id reads as empty once its slot is reused.
    function _retained(uint32 id) internal view returns (bool) {
        (uint32 open,,,) = sdgnrs.redemptionBatchState();
        return id + 1 >= open;
    }
    function invariant_INV_01_WriteOnceRoll() public view {
        for (uint256 i; i < handler.getBatchCount(); ++i) {
            uint32 id = handler.batches(i);
            uint16 first = handler.firstRoll(id);
            if (first != 0 && _retained(id)) assertEq(_rollOf(id), first);
        }
        assertEq(handler.ghost_rollOutOfBounds(), 0);
    }
    function invariant_INV_02_EthConservationExact() public view {
        uint256 expected;
        (uint32 open,uint32 settling,,) = sdgnrs.redemptionBatchState();
        for (uint256 i; i < handler.getBatchCount(); ++i) {
            uint32 id = handler.batches(i);
            if (id == open) continue;
            (uint128 tokens,uint96 payout,,,uint16 roll,) = sdgnrs.redemptionBatches(id);
            if (roll == 0) { expected += payout; continue; }
            if (id == settling) {
                expected += uint256(payout) - handler.paidRolled(id);
            } else {
                // After the cursor drains, rounding dust is released; only parked claims remain.
                for (uint256 a; a < handler.getActorCount(); ++a) {
                    uint256 pending = _claimTokens(handler.getActor(a), id);
                    expected += uint256(payout) * pending / tokens;
                }
            }
        }
        assertEq(sdgnrs.pendingRedemptionEthValue(), expected, "exact outstanding reserve including cursor dust");
    }
    function invariant_INV_04_TokenConservation() public view {
        (uint32 open,,,uint256 escrow) = sdgnrs.redemptionBatchState();
        uint256 pendingOpen;
        for (uint256 i; i < handler.getBatchCount(); ++i) {
            uint32 id = handler.batches(i);
            if (!_retained(id)) {
                // A retired batch finished settling before its slot was reused: nothing remains.
                for (uint256 a; a < handler.getActorCount(); ++a) {
                    (uint128 left,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(handler.getActor(a)), id);
                    assertEq(left, 0, "retired batch leaves no claim");
                }
                continue;
            }
            (uint128 total,,,,,) = sdgnrs.redemptionBatches(id);
            uint256 recorded;
            for (uint256 a; a < handler.getActorCount(); ++a) {
                address actor = handler.getActor(a);
                if (id != open || !handler.claimed(id, actor)) recorded += handler.submitted(id, actor);
                (uint128 pending,uint16 score) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(actor), id);
                if (handler.claimed(id, actor)) { assertEq(pending, 0); assertEq(score, 0); }
                else {
                    assertEq(pending, handler.submitted(id, actor));
                    assertEq(score, handler.frozenScore(id, actor));
                }
                if (id == open) pendingOpen += pending;
            }
            assertEq(total, recorded, "batch token weight");
            assertLe(total, 1e24, "hard raw-token supply bound");
        }
        assertEq(escrow, pendingOpen, "unpriced holder share");
        assertEq(sdgnrs.totalSupply(), handler.ghost_initialSupply() + handler.ghost_totalMinted() - handler.ghost_totalBurned());
        assertEq(handler.ghost_doubleClaim(), 0);
    }
    function invariant_INV_13_OnlyOneSettlingBatch() public view {
        (uint32 open,uint32 settling,,) = sdgnrs.redemptionBatchState();
        assertEq(sdgnrs.redemptionSettlementPending(), settling != 0);
        if (settling != 0) assertEq(settling + 1, open);
    }
    function invariant_balanceCoversPendingRedemptionEth() public view {
        assertGe(address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)) + game.redemptionReserve(),
            sdgnrs.pendingRedemptionEthValue());
    }
    /// @dev Non-vacuity: setUp seeds one admitted burn, so the campaign itself must burn, resolve and claim.
    ///      A single run can legitimately miss a leg (game over can latch first), so successes are
    ///      accumulated over the process (unique RA_ prefix) and each must be non-zero once 16 runs completed.
    ///      Measured over 1,285 default-profile runs (game-over trigger acting on one draw in four, see the
    ///      handler): about 2 campaign burns per run,
    ///      a batch resolved in 78% of runs, a claim in all but one.
    function afterInvariant() public {
        uint256 runs = _acc("RA_RUNS", 1);
        uint256 burns = _acc("RA_burns", handler.successfulBurns() - 1); // the seeded burn excluded
        uint256 resolved = _acc("RA_resolved", handler.ghost_resolvedBatches());
        uint256 claims = _acc("RA_claims", handler.ghost_claimCount());
        uint256 days_ = _acc("RA_days", handler.calls_advanceDay());
        if (runs < 16) return;
        assertGt(burns, 0, "vacuous: no campaign redemption burn ever succeeded");
        assertGt(resolved, 0, "vacuous: no redemption batch was ever resolved");
        assertGt(claims, 0, "vacuous: no redemption was ever claimed");
        assertGt(days_, 0, "vacuous: the campaign never advanced a day");
    }

    function _acc(string memory k, uint256 v) private returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function test_HandlerCompletesRealClaimAndFundingModes() public {
        handler.action_toggleStethFallback(0);
        assertTrue(handler.stethFallbackMode());
        handler.action_advanceDay(99);
        handler.action_settle(99);
        assertGt(handler.ghost_claimCount(), 0);
        invariant_INV_02_EthConservationExact();
        invariant_balanceCoversPendingRedemptionEth();
        handler.action_toggleStethFallback(1);
        assertFalse(handler.stethFallbackMode());
    }

}
