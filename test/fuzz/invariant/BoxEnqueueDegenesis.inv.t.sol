// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {BoxCreationHandler} from "../handlers/BoxCreationHandler.sol";
import {BoxEnqueue} from "./BoxEnqueue.inv.t.sol";

/// @title BoxEnqueueDegenesis -- box queue append/FIFO properties after a real Degenesis week (turbo)
/// @notice The queue starts past the week's credit-earning lootbox entries.
contract BoxEnqueueDegenesis is BoxEnqueue, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _acc(string memory k, uint256 v) internal override returns (uint256) {
        return super._acc(string.concat("DGT_", k), v);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        vm.deal(address(game), address(game).balance + 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);
        handler = new BoxCreationHandler(game, deityPass, mockVRF, 5);
        targetContract(address(handler));
        bytes4[] memory excluded = new bytes4[](1);
        excluded[0] = BoxCreationHandler.debugRewriteEntry.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
