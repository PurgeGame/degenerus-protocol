// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {Vm} from "forge-std/Vm.sol";

contract TerminalKnownWordSeeder is DegenerusGame, BucketSeed {
    function seed(uint256 word, address subscriber) external {
        uint24 day = _simulatedDayIndex();
        level = 10;
        purchaseStartDay = day - 120;
        dailyIdx = day - 1;
        levelPrizePool[10] = 1000 ether;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        _subOf[subscriber].affiliateBase = 1000;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(11, traits[q], 256, uint160(0x710000 + uint256(q) * 0x10000));
        }
    }
}

/// @notice Terminal payout changes must not reroll recipients, even when the daily word is public.
///         The request, fulfillment, affiliate claim and terminal settlement use production code.
contract TerminalAffiliateKnownWordTest is DeployProtocol {
    uint256 private constant WORD = 0x987654321;
    address private constant AFFILIATE = address(0xAFF1);
    address private constant SUBSCRIBER = address(0xB001);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TerminalKnownWordSeeder).runtimeCode);
        TerminalKnownWordSeeder(payable(address(game))).seed(WORD, SUBSCRIBER);
        vm.etch(address(game), original);
        vm.deal(address(game), 100 ether);
        // Record the referral without ranking it; the subscriber has unclaimed commission.
        vm.prank(address(game));
        affiliate.payAffiliate(0, bytes32(uint256(uint160(AFFILIATE))), SUBSCRIBER, 11, true, 0);
    }

    function test_KnownDailyWordAffiliateDeductionPreservesWinners() public {
        assertFalse(game.livenessTriggered(), "request day is the purchase deadline");
        game.advanceGame();
        uint256 requestId = mockVRF.lastRequestId();
        assertGt(requestId, 0, "real daily request");
        assertTrue(game.rngLocked());
        mockVRF.fulfillRandomWords(requestId, WORD);
        vm.warp(block.timestamp + 14 days + 2);
        assertTrue(game.livenessTriggered(), "the grace period expired without an advance");
        (address top,) = affiliate.affiliateTop(11);
        assertEq(top, address(0), "terminal board is initially empty");
        uint256 snapshot = vm.snapshotState();

        vm.expectCall(
            address(game), abi.encodeWithSelector(game.runTerminalJackpot.selector, 100 ether, uint24(11), WORD)
        );
        vm.recordLogs();
        _finishTerminal();
        bytes32 withoutClaim = _winnerFingerprint(vm.getRecordedLogs());
        assertTrue(game.gameOver());
        assertEq(game.claimableWinningsOf(AFFILIATE), 0);

        vm.revertToState(snapshot);
        address[] memory subscribers = new address[](1);
        subscribers[0] = SUBSCRIBER;
        affiliate.claim(subscribers); // permissionless, after the word is already public
        (top,) = affiliate.affiliateTop(11);
        assertEq(top, AFFILIATE);
        vm.expectCall(
            address(game), abi.encodeWithSelector(game.runTerminalJackpot.selector, 98 ether, uint24(11), WORD)
        );
        vm.recordLogs();
        _finishTerminal();
        bytes32 withClaim = _winnerFingerprint(vm.getRecordedLogs());
        assertTrue(game.gameOver());
        assertEq(game.claimableWinningsOf(AFFILIATE), 2 ether);
        assertEq(mockVRF.lastRequestId(), requestId, "terminal payout reused the daily word");
        assertEq(withoutClaim, withClaim, "affiliate deduction changes amounts, never jackpot recipients");
    }

    function _finishTerminal() private {
        for (uint256 i; i < 8 && !game.gameOver(); ++i) {
            game.advanceGame();
        }
        assertTrue(game.gameOver(), "terminal drain and payout completed");
    }

    function _winnerFingerprint(Vm.Log[] memory logs) private pure returns (bytes32 fingerprint) {
        bytes32 eventId = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == eventId) {
                // Only recipient addresses: changed payout amounts alone cannot satisfy this test.
                fingerprint = keccak256(abi.encode(fingerprint, logs[i].topics[1]));
            }
        }
        assertTrue(fingerprint != bytes32(0), "actual terminal winners were emitted");
    }
}
