// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {RngIndexDrainHandler} from "../handlers/RngIndexDrainHandler.sol";

/// @notice Public-path ordinary ticket drains persist the traits derived from their
/// committed nonzero word before advancing the index. This campaign deliberately keeps
/// one ticket buyer and no foil purchases, below the seated-round threshold. Other
/// trait consumers have separate suites; encountering one here fails rather than skips.
contract RngIndexDrainOrderingInvariants is DeployProtocol {
    RngIndexDrainHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        handler = new RngIndexDrainHandler(game, mockVRF, admin);

        // Deterministic public-path anchor: every fuzz run begins with actual generated
        // entries checked by the same oracle as later actions. Acceptance does not depend
        // on randomly discovering a request/fulfillment/drain sequence.
        handler.purchase(2000);
        // The engine prepares the day one checkpoint per call before its daily request
        // (60d31f775), and the handler's bounded keeper call may stop at that preparation.
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) handler.advance();
        assertTrue(game.rngLocked(), "anchor daily request did not go out");
        handler.fulfillVrf(uint256(keccak256("rng-binding-invariant-anchor")));
        for (uint256 i; i < 100 && game.rngLocked(); ++i) handler.advance();
        assertFalse(game.rngLocked(), "anchor daily cycle did not finish");
        _assertCoverage();
        _assertBinding();

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.purchase.selector;
        selectors[1] = handler.advance.selector;
        selectors[2] = handler.fulfillVrf.selector;
        selectors[3] = handler.warpTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function _assertCoverage() private view {
        assertGt(handler.ghost_dailyDrainBranchEntered(), 0, "ordinary drain was never checked");
        assertGt(handler.ghost_entriesChecked(), 0, "no persisted entries were checked");
        assertGe(handler.ghost_buyerEntriesChecked(), 20, "paid buyer entries never reached the oracle");
    }

    function _assertBinding() private view {
        assertEq(handler.ghost_bindingMismatches(), 0, "persisted traits/owners differ from committed-word replay");
        assertEq(handler.ghost_unsupportedConsumers(), 0, "fixture entered a trait consumer outside this oracle");
        assertEq(handler.ghost_drainBeforeSwapViolations(), 0, "index changed during a ticket-materializing call");
        assertEq(handler.ghost_zeroEntropyConsumptions(), 0, "drain used an unpopulated commitment");
    }

    function invariant_drainBinding() public view {
        _assertBinding();
    }

    function invariant_drainCoverage() public view {
        _assertCoverage();
    }

    function afterInvariant() public view {
        _assertCoverage();
        _assertBinding();
    }

    function test_anchorChecksPersistedEntries() public view {
        _assertCoverage();
        _assertBinding();
    }
}
