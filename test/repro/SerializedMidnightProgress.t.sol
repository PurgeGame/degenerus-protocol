// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";
import {MiddayFrozenPoolLatch} from "./MiddayFrozenPoolLatch.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Real request, fulfilment and unaided production keeper routing across midnight.
contract SerializedMidnightProgressTest is MiddayFrozenPoolLatch {
    function _crossMidnight(uint256 subscribers, bool rewarded) private {
        vm.pauseGasMetering();
        _latchMiddayAfterTarget(false);
        assertFalse(game.rngComplete(), "the requested cycle is not complete before delivery");
        _fulfillPending();
        assertFalse(_ticketsFullyProcessed(), "nonvacuity: read tickets remain");
        assertFalse(game.boxIndexComplete(RecyclingState.readBuffer(address(game))), "nonvacuity: read box frontier remains");
        uint256 existing = game.subscriberCount();
        for (uint256 i; i + existing < subscribers; ++i) {
            address owner = address(uint160(0xF00000 + i));
            vm.deal(owner, 10 ether);
            _grantSeat(owner);
            // The free mint tranche has 1,000 seats. Fill the remaining live
            // subscriber set through the real 998-seat vault tranche.
            if (afkingSubToken.balanceOf(owner) == 0) {
                vm.prank(address(vault));
                afkingSubToken.vaultMintSeats(owner, 1);
            }
            vm.prank(owner);
            game.subscribe{value: 1 ether}(address(0), false, false, 1, address(0));
        }
        if (subscribers != 0) assertEq(game.subscriberCount(), subscribers, "nonvacuity: full subscriber ring");
        // Subscribing queues indexed cover boxes, also bound to the next write cohort.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 previousRequest = mockVRF.lastRequestId();
        // The single engine entry handles both funded and unrewarded safe checkpoints.
        // Funding changes transaction boundaries, never the committed cohort's identity.
        uint256 committedWord = RecyclingState.currentWord(address(game));
        uint48 committedRead = RecyclingState.readBuffer(address(game));
        vm.resumeGasMetering();
        vm.recordLogs();
        for (uint256 i; i < 1024 && mockVRF.lastRequestId() == previousRequest; ++i) {
            vm.prank(address(0xC4A9));
            if (rewarded) game.mineFlip{gas: 12_000_000}();
            else game.mineFlip{gas: 9_500_000}();
            if (mockVRF.lastRequestId() == previousRequest) {
                assertEq(RecyclingState.currentWord(address(game)), committedWord, "continuation retains old entropy");
                assertEq(RecyclingState.readBuffer(address(game)), committedRead, "continuation retains old read buffer");
            }
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 bounties;
        bool ticketWork;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (uint8 stage,) = abi.decode(logs[i].data, (uint8, uint24));
                assertTrue(stage != 18, "consumer cleanup cannot report a fresh daily word applied");
            }
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("TraitsGenerated(address,uint256,uint32)")) ticketWork = true;
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("MinerBounty(uint8,address,uint256)")) ++bounties;
        }
        assertTrue(ticketWork, "the old ticket cohort generated traits before the next request");
        if (rewarded) assertGt(bounties, 0, "mineFlip pays for completed keeper work");
        else assertEq(bounties, 0, "low-funded engine never pays a miner bounty, including read drains");
        assertGt(mockVRF.lastRequestId(), previousRequest, "keeper alone drained read consumers and requested the next day");
        assertTrue(game.rngLocked(), "the fresh daily request reached its lock");
        assertFalse(game.rngComplete(), "a fresh request clears the completion marker");
        assertFalse(game.boxIndexComplete(RecyclingState.readBuffer(address(game))), "fresh read buffer needs its new word");
        assertEq(uint256(game.extsload(keccak256(abi.encode(RecyclingState.writeBuffer(address(game)), uint256(57))))), 0, "old read header reset once at seal");
    }
    function test_MidnightCommitsFinalTicketLatchBeforeWaitingForBoxes() public { _crossMidnight(0, true); }
    function test_LowGasMidnightDrainsWithoutPayingBounty() public { _crossMidnight(0, false); }
    function test_AdminPreservesVaultOwnerForStalledRequestRetry() public {
        vm.pauseGasMetering();
        _latchMiddayAfterTarget(false);
        uint256 request = mockVRF.lastRequestId();
        uint48 committedRead = RecyclingState.readBuffer(address(game));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(vault.isVaultOwner(ContractAddresses.CREATOR), "fixture creator holds the vault majority");
        assertFalse(vault.isVaultOwner(address(game)), "Game is not the vault owner");
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng();
        assertGt(mockVRF.lastRequestId(), request, "Admin forwards the owner's authorized retry");
        assertFalse(game.rngLocked(), "retry preserves the original midday request mode");
        assertEq(RecyclingState.readBuffer(address(game)), committedRead, "retry preserves the committed cohort");
        _fulfillPending();
        for (uint256 i; i < 1024 && !game.rngLocked(); ++i) game.mineFlip();
        assertTrue(game.rngLocked(), "after the midday cohort drains the next daily request locks");
    }
    // 2 protocol + 1,000 free + 998 vault seats is the reachable supply ceiling.
    function test_MidnightDefersSubscriberStampingUntilReadCohortCompletes() public { _crossMidnight(2000, true); }
}
