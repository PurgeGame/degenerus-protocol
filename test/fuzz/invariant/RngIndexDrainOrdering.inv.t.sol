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
    uint256 internal anchorDrains;
    uint256 internal anchorEntries;
    uint256 internal anchorBuyerEntries;

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
        anchorDrains = handler.ghost_dailyDrainBranchEntered();
        anchorEntries = handler.ghost_entriesChecked();
        anchorBuyerEntries = handler.ghost_buyerEntriesChecked();

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

    /// @dev The coverage floor above is already met by the setUp anchor, so on its own it cannot tell a
    ///      campaign that checked nothing from one that did. The campaign's own drains and checked entries
    ///      (beyond the anchor) are accumulated over the process (unique RD_ prefix) and must be non-zero
    ///      once 16 runs have completed.
    function afterInvariant() public {
        _assertCoverage();
        _assertBinding();
        uint256 runs = _acc("RD_RUNS", 1);
        uint256 drains = _acc("RD_drains", handler.ghost_dailyDrainBranchEntered() - anchorDrains);
        uint256 entries = _acc("RD_entries", handler.ghost_entriesChecked() - anchorEntries);
        uint256 buyers = _acc("RD_buyerEntries", handler.ghost_buyerEntriesChecked() - anchorBuyerEntries);
        if (runs < 16) return;
        assertGt(drains, 0, "vacuous: the campaign never entered the ordinary drain");
        assertGt(entries, 0, "vacuous: the campaign never checked a persisted entry");
        assertGt(buyers, 0, "vacuous: the campaign never checked a paid buyer entry");
    }

    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function test_anchorChecksPersistedEntries() public view {
        _assertCoverage();
        _assertBinding();
    }
}
