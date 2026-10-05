// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
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
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = RedemptionHandler.action_burn.selector;
        selectors[1] = RedemptionHandler.action_advanceDay.selector;
        selectors[2] = RedemptionHandler.action_claim.selector;
        selectors[3] = RedemptionHandler.action_triggerGameOver.selector;
        selectors[4] = RedemptionHandler.action_burnOnPreviousDay.selector;
        selectors[5] = RedemptionHandler.action_toggleStethFallback.selector;
        selectors[6] = RedemptionHandler.action_settle.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        // Ensure all campaigns start with a real claim, not only reverting random actions.
        handler.action_burn(0, 1_000_000 ether);
    }
    function invariant_INV_01_WriteOnceRoll() public view {
        for (uint256 i; i < handler.getBatchCount(); ++i) {
            uint32 id = handler.batches(i);
            uint16 first = handler.firstRoll(id);
            if (first != 0) assertEq(_rollOf(id), first);
        }
        assertEq(handler.ghost_rollOutOfBounds(), 0);
    }
    function invariant_INV_02_EthConservationExact() public view {
        uint256 expected;
        (uint32 open,uint32 settling,,) = sdgnrs.redemptionBatchState();
        for (uint256 i; i < handler.getBatchCount(); ++i) {
            uint32 id = handler.batches(i);
            if (id == open) continue;
            (uint128 tokens,,uint96 base,,uint16 roll,) = sdgnrs.redemptionBatches(id);
            if (roll == 0) { expected += uint256(base) * 175 / 100; continue; }
            if (id == settling) {
                expected += uint256(base) * roll / 100 - handler.paidRolled(id);
            } else {
                // After the cursor drains, rounding dust is released; only parked claims remain.
                for (uint256 a; a < handler.getActorCount(); ++a) {
                    uint256 pending = _claimTokens(handler.getActor(a), id);
                    expected += (uint256(base) * pending / tokens) * roll / 100;
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
            (uint128 total,uint128 snapshot,,,,) = sdgnrs.redemptionBatches(id);
            uint256 recorded;
            for (uint256 a; a < handler.getActorCount(); ++a) {
                address actor = handler.getActor(a);
                if (id != open || !handler.claimed(id, actor)) recorded += handler.submitted(id, actor);
                (uint128 pending,uint16 score) = sdgnrs.pendingRedemptions(actor, id);
                if (handler.claimed(id, actor)) { assertEq(pending, 0); assertEq(score, 0); }
                else {
                    assertEq(pending, handler.submitted(id, actor));
                    assertEq(score, handler.frozenScore(id, actor));
                }
                if (id == open) pendingOpen += pending;
            }
            assertEq(total, recorded, "batch token weight");
            assertLe(total, uint256(snapshot) / 2, "batch supply cap");
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
        assertGe(address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs)), sdgnrs.pendingRedemptionEthValue());
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
