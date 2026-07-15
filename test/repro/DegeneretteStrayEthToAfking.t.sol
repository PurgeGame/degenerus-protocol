// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @notice Regression: ETH sent alongside a token (FLIP/WWXRP) Degenerette bet — which consumes no
///         ETH — is credited to the funder's withdrawable afking balance (solvency-preserving via
///         claimablePool), not stranded in the contract. A zero-value token bet is unaffected.
contract DegeneretteStrayEthToAfking is DeployProtocol {
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;
    uint32 private constant TICKET = 0x01020304;

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        player = makeAddr("stray_eth_player");
        vm.deal(player, 1_000 ether);
        vm.deal(address(game), 1_000_000 ether);
        // LR index = 1 so placement passes NotStarted; the word stays 0 (placement needs it unfulfilled).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
        _seedFuturePrizePool(10_000_000 ether);
    }

    function test_flip_bet_strayEth_creditsAfking() public {
        uint128 perTicket = 100 ether;
        vm.prank(address(game));
        coin.mintForGame(player, perTicket);

        uint256 afkingBefore = game.afkingFundingOf(player);
        uint256 poolBefore = game.claimablePoolView();
        uint256 stray = 5 ether;

        vm.prank(player);
        game.placeDegeneretteBet{value: stray}(address(0), CURRENCY_FLIP, perTicket, 1, TICKET, 0);

        assertEq(game.afkingFundingOf(player), afkingBefore + stray, "stray ETH not credited to afking");
        assertEq(
            game.claimablePoolView(),
            poolBefore + stray,
            "claimablePool must rise by the credited afking (solvency identity preserved)"
        );
    }

    function test_wwxrp_bet_strayEth_creditsAfking() public {
        uint128 perTicket = 1 ether;
        vm.prank(address(game));
        wwxrp.mintPrize(player, perTicket);

        uint256 afkingBefore = game.afkingFundingOf(player);
        uint256 poolBefore = game.claimablePoolView();
        uint256 stray = 3 ether;

        vm.prank(player);
        game.placeDegeneretteBet{value: stray}(address(0), CURRENCY_WWXRP, perTicket, 1, TICKET, 0);

        assertEq(game.afkingFundingOf(player), afkingBefore + stray, "WWXRP stray ETH not credited to afking");
        assertEq(game.claimablePoolView(), poolBefore + stray, "claimablePool must rise by the credited afking");
    }

    function test_flip_bet_noEth_afkingUnchanged() public {
        uint128 perTicket = 100 ether;
        vm.prank(address(game));
        coin.mintForGame(player, perTicket);

        uint256 afkingBefore = game.afkingFundingOf(player);
        uint256 poolBefore = game.claimablePoolView();

        vm.prank(player);
        game.placeDegeneretteBet(address(0), CURRENCY_FLIP, perTicket, 1, TICKET, 0);

        assertEq(game.afkingFundingOf(player), afkingBefore, "no-ETH token bet must not touch afking");
        assertEq(game.claimablePoolView(), poolBefore, "no-ETH token bet must not touch claimablePool");
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }
}
