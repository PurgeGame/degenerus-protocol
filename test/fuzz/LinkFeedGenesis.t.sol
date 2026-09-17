// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

// ContractAddresses.LINK_ETH_FEED — the constructor-install path.
//
// The constant is address(0) in a clean checkout, which leaves DegenerusAdmin's
// feed slot empty for the feed-swap governance path to fill; the Hardhat suite
// (test/unit/FeedGovernance.test.js) is pinned to that zero and covers it. The
// Foundry pipeline patches the constant to MockLinkEthFeed, so this file covers
// the other side: a pinned feed is live from the constructor, prices donations
// immediately, and — being healthy — locks the governance path that would swap it.

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {MockLinkEthFeed} from "../../contracts/mocks/MockLinkEthFeed.sol";

contract LinkFeedGenesis is DeployProtocol {
    /// @dev keccak256("LinkEthFeedUpdated(address,address)")
    bytes32 private constant FEED_UPDATED_TOPIC =
        keccak256("LinkEthFeedUpdated(address,address)");

    Vm.Log[] private deployLogs;
    address private vaultOwner;

    function setUp() public {
        // Recording starts before the deploy so the admin constructor's own log is captured.
        vm.recordLogs();
        _deployProtocol();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            deployLogs.push(logs[i]);
        }

        vaultOwner = makeAddr("linkfeed_vaultOwner");
        vm.mockCall(
            address(vault),
            abi.encodeWithSignature("isVaultOwner(address)", vaultOwner),
            abi.encode(true)
        );
    }

    function test_genesis_installs_the_pinned_feed() public view {
        assertEq(
            admin.linkEthPriceFeed(),
            address(mockFeed),
            "constructor did not install ContractAddresses.LINK_ETH_FEED"
        );
    }

    function test_genesis_emits_the_install_from_zero() public view {
        uint256 hits;
        for (uint256 i = 0; i < deployLogs.length; ++i) {
            Vm.Log memory entry = deployLogs[i];
            if (entry.emitter != address(admin)) continue;
            if (entry.topics.length != 3 || entry.topics[0] != FEED_UPDATED_TOPIC) continue;
            assertEq(
                address(uint160(uint256(entry.topics[1]))),
                address(0),
                "install did not report an empty prior slot"
            );
            assertEq(
                address(uint160(uint256(entry.topics[2]))),
                address(mockFeed),
                "install reported a feed other than the pinned one"
            );
            ++hits;
        }
        assertEq(hits, 1, "expected exactly one LinkEthFeedUpdated at deploy");
    }

    function test_genesis_feed_prices_donations_immediately() public view {
        // MockLinkEthFeed is constructed at 0.004 ether per LINK, under the
        // 0.05 ether valuation ceiling, so the answer passes through uncapped.
        assertEq(
            admin.linkAmountToEth(1 ether),
            0.004 ether,
            "pinned feed did not value LINK at deploy"
        );
    }

    function test_genesis_feed_locks_the_swap_path() public {
        // A healthy feed has zero stall, so proposeFeedSwap is shut to every
        // path — the vault owner's and the community's alike.
        MockLinkEthFeed replacement = new MockLinkEthFeed(int256(0.005 ether));
        vm.prank(vaultOwner);
        vm.expectRevert(DegenerusAdmin.FeedHealthy.selector);
        admin.proposeFeedSwap(address(replacement));
    }

    function test_genesis_feed_swap_path_reopens_once_stale() public {
        // The lock is the feed's health, not the constructor: age the pinned
        // feed past the 2-day admin threshold and the path is open again.
        MockLinkEthFeed replacement = new MockLinkEthFeed(int256(0.005 ether));
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(vaultOwner);
        uint256 proposalId = admin.proposeFeedSwap(address(replacement));
        assertEq(proposalId, 1, "stalled feed did not reopen the swap path");
    }
}
