// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IDegenerusCoin} from "../../contracts/interfaces/IDegenerusCoin.sol";

/// @title RngNudge -- quote protection and whole-FLIP rounding tests
contract RngNudge is Test {
    DegenerusGame private game;
    address private alice;
    address private bob;

    function setUp() public {
        vm.warp(
            (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1) *
                1 days +
                82_620
        );
        game = new DegenerusGame();
        alice = makeAddr("nudge-alice");
        bob = makeAddr("nudge-bob");
    }

    function test_nudgeQuotesRoundUpToWholeFlip() public {
        uint256[6] memory expected = [
            uint256(100 ether),
            150 ether,
            225 ether,
            338 ether,
            507 ether,
            760 ether
        ];

        for (uint256 i = 0; i < expected.length; ++i) {
            (uint256 queued, uint256 cost) = game.rngNudgeQuote();
            assertEq(queued, i, "queued count");
            assertEq(cost, expected[i], "rounded quote");
            assertEq(cost % 1 ether, 0, "quote must be whole FLIP");

            bytes memory burnCall = abi.encodeCall(
                IDegenerusCoin.burnCoin,
                (alice, cost)
            );
            vm.mockCall(ContractAddresses.COIN, burnCall, bytes(""));
            vm.expectCall(ContractAddresses.COIN, burnCall);
            vm.prank(alice);
            game.reverseFlip(cost);
        }

        (uint256 finalQueued, uint256 nextCost) = game.rngNudgeQuote();
        assertEq(finalQueued, expected.length, "final queued count");
        assertEq(nextCost, 1_140 ether, "seventh quote");
    }

    function test_staleQuoteRevertsBeforeBurn() public {
        (, uint256 staleCost) = game.rngNudgeQuote();

        vm.mockCall(
            ContractAddresses.COIN,
            abi.encodeCall(IDegenerusCoin.burnCoin, (bob, staleCost)),
            bytes("")
        );
        vm.prank(bob);
        game.reverseFlip(staleCost);

        (uint256 queued, uint256 liveCost) = game.rngNudgeQuote();
        assertEq(queued, 1, "bob queued first nudge");
        assertEq(liveCost, 150 ether, "live price advanced");

        vm.mockCallRevert(
            ContractAddresses.COIN,
            abi.encodeCall(IDegenerusCoin.burnCoin, (alice, staleCost)),
            abi.encodeWithSignature("UnexpectedBurn()")
        );
        vm.expectRevert(DegenerusGame.NudgeCostChanged.selector);
        vm.prank(alice);
        game.reverseFlip(staleCost);

        (queued, liveCost) = game.rngNudgeQuote();
        assertEq(queued, 1, "stale quote queued no nudge");
        assertEq(liveCost, 150 ether, "live quote unchanged after revert");
    }
}
